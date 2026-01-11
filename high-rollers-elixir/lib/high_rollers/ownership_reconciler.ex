defmodule HighRollers.OwnershipReconciler do
  @moduledoc """
  Periodic reconciliation of NFT ownership from the Arbitrum NFT contract (source of truth).

  PROCESS:
  1. Get all NFTs from Mnesia (hr_nfts)
  2. Query Arbitrum NFT contract for current owner of each NFT
  3. Compare with Mnesia - update Mnesia if different
  4. Compare with NFTRewarder on Rogue Chain - enqueue update if different

  The Arbitrum NFT contract is the source of truth for ownership.

  Runs every 5 minutes. Uses GlobalSingleton to run on single node in cluster.
  Prevents overlapping syncs - waits for current sync to complete before starting next.
  """
  use GenServer
  require Logger

  @reconcile_interval_ms :timer.minutes(5)
  @batch_size 50  # Query contract in smaller batches to avoid rate limiting
  @batch_delay_ms 500  # Delay between batches

  @zero_address "0x0000000000000000000000000000000000000000"

  # ===== Client API =====

  def start_link(opts) do
    case HighRollers.GlobalSingleton.start_link(__MODULE__, opts) do
      {:ok, pid} -> {:ok, pid}
      {:already_registered, _pid} -> :ignore
    end
  end

  @doc "Force immediate reconciliation (for testing/manual trigger)"
  def reconcile_now do
    GenServer.cast({:global, __MODULE__}, :reconcile)
  end

  @doc "Get last reconciliation stats"
  def get_stats do
    GenServer.call({:global, __MODULE__}, :get_stats)
  end

  # ===== Server Callbacks =====

  @impl true
  def init(_opts) do
    Logger.info("[OwnershipReconciler] Started, will reconcile every #{div(@reconcile_interval_ms, 60_000)} minutes")
    schedule_reconcile()

    {:ok, %{
      last_run: nil,
      last_duration_ms: nil,
      mnesia_updates: 0,
      rewarder_updates: 0,
      errors: 0,
      reconciling: false
    }}
  end

  @impl true
  def handle_cast(:reconcile, %{reconciling: true} = state) do
    Logger.info("[OwnershipReconciler] Already reconciling, skipping manual trigger")
    {:noreply, state}
  end

  @impl true
  def handle_cast(:reconcile, state) do
    # Run reconciliation in a spawned process to not block GenServer
    parent = self()
    spawn(fn ->
      result = do_reconcile()
      send(parent, {:reconcile_complete, result})
    end)
    {:noreply, %{state | reconciling: true}}
  end

  @impl true
  def handle_info(:reconcile, %{reconciling: true} = state) do
    # Skip if already reconciling - will schedule again when current one completes
    Logger.debug("[OwnershipReconciler] Skipping scheduled reconcile - already in progress")
    {:noreply, state}
  end

  @impl true
  def handle_info(:reconcile, state) do
    # Run reconciliation in a spawned process to not block GenServer
    parent = self()
    spawn(fn ->
      result = do_reconcile()
      send(parent, {:reconcile_complete, result})
    end)
    {:noreply, %{state | reconciling: true}}
  end

  @impl true
  def handle_info({:reconcile_complete, result}, state) do
    # Schedule next reconcile only after current one completes
    schedule_reconcile()

    {:noreply, %{state |
      reconciling: false,
      last_run: result.completed_at,
      last_duration_ms: result.duration_ms,
      mnesia_updates: result.mnesia_updates,
      rewarder_updates: result.rewarder_updates,
      errors: result.errors
    }}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = Map.take(state, [:last_run, :last_duration_ms, :mnesia_updates, :rewarder_updates, :errors, :reconciling])
    {:reply, stats, state}
  end

  # ===== Private Functions =====

  defp schedule_reconcile do
    Process.send_after(self(), :reconcile, @reconcile_interval_ms)
  end

  defp do_reconcile do
    start_time = System.monotonic_time(:millisecond)
    Logger.info("[OwnershipReconciler] Starting reconciliation...")

    # Get all NFTs from Mnesia
    all_nfts = HighRollers.NFTStore.get_all()
    total_count = length(all_nfts)

    if total_count == 0 do
      Logger.info("[OwnershipReconciler] No NFTs to reconcile")
      %{
        completed_at: DateTime.utc_now(),
        duration_ms: 0,
        mnesia_updates: 0,
        rewarder_updates: 0,
        errors: 0
      }
    else
      Logger.info("[OwnershipReconciler] Checking #{total_count} NFTs against Arbitrum contract")

      # Process in batches
      {mnesia_updates, rewarder_updates, errors} =
        all_nfts
        |> Enum.chunk_every(@batch_size)
        |> Enum.reduce({0, 0, 0}, fn batch, {m_acc, r_acc, e_acc} ->
          {batch_mnesia, batch_rewarder, batch_errors} = reconcile_batch(batch)
          # Delay between batches to avoid rate limiting
          Process.sleep(@batch_delay_ms)
          {m_acc + batch_mnesia, r_acc + batch_rewarder, e_acc + batch_errors}
        end)

      duration = System.monotonic_time(:millisecond) - start_time

      if mnesia_updates > 0 or rewarder_updates > 0 do
        Logger.warning("[OwnershipReconciler] Updated #{mnesia_updates} Mnesia records, queued #{rewarder_updates} NFTRewarder updates, #{errors} errors (#{duration}ms)")
      else
        Logger.info("[OwnershipReconciler] All ownership up to date (#{duration}ms)")
      end

      %{
        completed_at: DateTime.utc_now(),
        duration_ms: duration,
        mnesia_updates: mnesia_updates,
        rewarder_updates: rewarder_updates,
        errors: errors
      }
    end
  end

  defp reconcile_batch(nfts) do
    Enum.reduce(nfts, {0, 0, 0}, fn nft, {m_acc, r_acc, e_acc} ->
      case reconcile_single_nft(nft) do
        {:ok, :no_change} ->
          {m_acc, r_acc, e_acc}

        {:ok, :mnesia_updated} ->
          {m_acc + 1, r_acc, e_acc}

        {:ok, :both_updated} ->
          {m_acc + 1, r_acc + 1, e_acc}

        {:ok, :rewarder_queued} ->
          {m_acc, r_acc + 1, e_acc}

        {:error, reason} ->
          Logger.warning("[OwnershipReconciler] Error for token #{nft.token_id}: #{inspect(reason)}")
          {m_acc, r_acc, e_acc + 1}
      end
    end)
  end

  defp reconcile_single_nft(nft) do
    # Query Arbitrum NFT contract for current owner (source of truth)
    case HighRollers.Contracts.NFTContract.get_owner_of(nft.token_id) do
      {:ok, contract_owner} ->
        contract_owner_lower = String.downcase(contract_owner)
        mnesia_owner_lower = String.downcase(nft.owner)

        # Check if Mnesia needs updating
        mnesia_changed = contract_owner_lower != mnesia_owner_lower

        if mnesia_changed do
          Logger.info("[OwnershipReconciler] Token #{nft.token_id}: Mnesia owner #{mnesia_owner_lower} -> contract owner #{contract_owner_lower}")
          # Update Mnesia with correct owner from contract
          HighRollers.NFTStore.update_owner(nft.token_id, contract_owner_lower)
        end

        # Check if NFTRewarder needs updating
        rewarder_queued = maybe_update_rewarder(nft.token_id, contract_owner_lower)

        cond do
          mnesia_changed and rewarder_queued -> {:ok, :both_updated}
          mnesia_changed -> {:ok, :mnesia_updated}
          rewarder_queued -> {:ok, :rewarder_queued}
          true -> {:ok, :no_change}
        end

      {:error, :not_found} ->
        # Token doesn't exist on contract (burned or invalid)
        Logger.warning("[OwnershipReconciler] Token #{nft.token_id} not found on contract")
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_update_rewarder(token_id, correct_owner) do
    # Check NFTRewarder for current owner
    case HighRollers.Contracts.NFTRewarder.get_nft_owner(token_id) do
      {:ok, rewarder_owner} ->
        rewarder_owner_lower = String.downcase(rewarder_owner)

        # Skip if zero address (not registered yet) or already correct
        if rewarder_owner_lower == @zero_address or rewarder_owner_lower == correct_owner do
          false
        else
          # Queue update to NFTRewarder
          Logger.info("[OwnershipReconciler] Token #{token_id}: NFTRewarder owner #{rewarder_owner_lower} -> #{correct_owner}")
          case HighRollers.AdminTxQueue.enqueue_update_ownership(token_id, correct_owner) do
            {:ok, _op_id} -> true
            {:error, _reason} -> false
          end
        end

      {:error, _reason} ->
        # Can't check NFTRewarder, skip
        false
    end
  end
end
