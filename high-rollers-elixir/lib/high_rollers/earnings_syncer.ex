defmodule HighRollers.EarningsSyncer do
  @moduledoc """
  Background service to sync NFT earnings from NFTRewarder contract.

  Contract provides: totalEarned, pendingAmount per NFT
  Server calculates: last24h (from reward_events), APY (from 24h and NFT value)

  Key optimization: 24h earnings per NFT is proportional to global 24h:
    nft_24h = global_24h × (nft_multiplier / total_multiplier_points)

  This is O(1) - one query for global 24h, then simple multiplication per NFT.

  Uses GlobalSingleton for cluster-wide single instance.
  """
  use GenServer
  require Logger

  @sync_interval_ms 60_000  # 60 seconds
  @batch_size 100

  @multipliers [100, 90, 80, 70, 60, 50, 40, 30]  # Index 0-7

  # ===== Client API =====

  def start_link(opts) do
    case HighRollers.GlobalSingleton.start_link(__MODULE__, opts) do
      {:ok, pid} -> {:ok, pid}
      {:already_registered, _pid} -> :ignore
    end
  end

  @doc "Force immediate sync (for testing/manual trigger)"
  def sync_now do
    GenServer.cast({:global, __MODULE__}, :sync_now)
  end

  # ===== Server Callbacks =====

  @impl true
  def init(_opts) do
    # Initial sync after a short delay to let other services start
    Process.send_after(self(), :initial_sync, 5_000)

    schedule_sync()

    Logger.info("[EarningsSyncer] Started")
    {:ok, %{syncing: false}}
  end

  @impl true
  def handle_info(:initial_sync, state) do
    # Run initial sync in background
    me = self()
    spawn(fn ->
      sync_all_nft_earnings()
      send(me, :sync_complete)
    end)
    {:noreply, %{state | syncing: true}}
  end

  @impl true
  def handle_info(:sync, %{syncing: true} = state) do
    # Skip if already syncing (prevents overlap)
    schedule_sync()
    {:noreply, state}
  end

  @impl true
  def handle_info(:sync, state) do
    me = self()
    spawn(fn ->
      sync_all_nft_earnings()
      send(me, :sync_complete)
    end)
    schedule_sync()
    {:noreply, %{state | syncing: true}}
  end

  @impl true
  def handle_info(:sync_complete, state) do
    {:noreply, %{state | syncing: false}}
  end

  @impl true
  def handle_cast(:sync_now, %{syncing: true} = state) do
    Logger.info("[EarningsSyncer] Already syncing, skipping manual trigger")
    {:noreply, state}
  end

  @impl true
  def handle_cast(:sync_now, state) do
    me = self()
    spawn(fn ->
      sync_all_nft_earnings()
      send(me, :sync_complete)
    end)
    {:noreply, %{state | syncing: true}}
  end

  # ===== Private Functions =====

  defp schedule_sync do
    Process.send_after(self(), :sync, @sync_interval_ms)
  end

  defp sync_all_nft_earnings do
    start_time = System.monotonic_time()
    all_nfts = HighRollers.NFTStore.get_all()
    total = length(all_nfts)

    result = if total == 0 do
      Logger.info("[EarningsSyncer] No NFTs to sync")
      :ok
    else
      do_sync_all_nft_earnings(all_nfts, total)
    end

    duration = System.monotonic_time() - start_time

    # Emit telemetry
    :telemetry.execute(
      [:high_rollers, :earnings_syncer, :sync],
      %{duration: duration, nfts_synced: total},
      %{batch_size: @batch_size}
    )

    result
  end

  defp do_sync_all_nft_earnings(all_nfts, total) do
    # Step 1: Get global 24h rewards ONCE
    one_day_ago = System.system_time(:second) - 86400
    global_24h_wei = HighRollers.Rewards.get_rewards_since(one_day_ago) || 0
    total_multiplier_points = HighRollers.NFTStore.get_total_multiplier_points() || 109_390

    # Get NFT value for APY calculation
    nft_value_in_rogue_wei = get_nft_value_in_rogue_wei()

    Logger.info("[EarningsSyncer] Syncing #{total} NFTs, global 24h: #{format_rogue(global_24h_wei)} ROGUE")

    # Step 2: Batch query contract for on-chain earnings
    all_nfts
    |> Enum.chunk_every(@batch_size)
    |> Enum.each(fn batch ->
      sync_batch(batch, global_24h_wei, total_multiplier_points, nft_value_in_rogue_wei)
      # Rate limiting
      Process.sleep(200)
    end)

    # Sync time reward last_claim_time from contract (backup for missed events)
    sync_time_reward_claim_times()

    # Update global and hostess stats
    sync_global_stats(global_24h_wei, nft_value_in_rogue_wei)
    sync_hostess_stats(global_24h_wei, total_multiplier_points, nft_value_in_rogue_wei)

    # Broadcast sync complete
    stats = HighRollers.Rewards.get_global_stats()
    Phoenix.PubSub.broadcast(HighRollers.PubSub, "earnings_events", {:earnings_synced, stats})

    Logger.info("[EarningsSyncer] Sync complete")
    :ok
  end

  defp sync_batch(batch, global_24h_wei, total_multiplier_points, nft_value_in_rogue_wei) do
    token_ids = Enum.map(batch, & &1.token_id)

    case HighRollers.Contracts.NFTRewarder.get_batch_nft_earnings(token_ids) do
      {:ok, earnings_list} ->
        # Step 3: Calculate off-chain metrics for each NFT
        Enum.each(earnings_list, fn %{token_id: token_id, total_earned: total_earned, pending_amount: pending_amount, hostess_index: hostess_index} ->
          multiplier = Enum.at(@multipliers, hostess_index, 30)

          # Proportional 24h share
          last_24h_earned =
            if total_multiplier_points > 0 do
              div(global_24h_wei * multiplier, total_multiplier_points)
            else
              0
            end

          # APY in basis points
          apy_basis_points =
            if nft_value_in_rogue_wei > 0 do
              annual_projection = last_24h_earned * 365
              div(annual_projection * 10000, nft_value_in_rogue_wei)
            else
              0
            end

          # Update via NFTStore
          HighRollers.NFTStore.update_earnings(token_id, %{
            total_earned: total_earned,
            pending_amount: pending_amount,
            last_24h_earned: Integer.to_string(last_24h_earned),
            apy_basis_points: apy_basis_points
          })
        end)

      {:error, reason} ->
        Logger.warning("[EarningsSyncer] Batch failed: #{inspect(reason)}")
    end
  end

  @doc """
  Sync time reward last_claim_time from contract.

  This serves as a backup mechanism to ensure Mnesia stays in sync with the
  contract's authoritative last_claim_time. If RogueRewardPoller misses a
  RewardClaimed event (due to crash, network issue, etc.), this will correct it.

  Only syncs special NFTs (token IDs 2340-2700) that have time rewards.
  """
  defp sync_time_reward_claim_times do
    # Get special NFTs (2340-2700) from unified hr_nfts table
    special_nfts = HighRollers.NFTStore.get_special_nfts_by_owner(nil)  # All special NFTs

    if Enum.empty?(special_nfts) do
      :ok
    else
      Logger.info("[EarningsSyncer] Syncing time reward claim times for #{length(special_nfts)} special NFTs")

      special_nfts
      |> Enum.chunk_every(50)  # Smaller batches for time reward queries
      |> Enum.each(fn batch ->
        Enum.each(batch, fn nft ->
          sync_single_time_reward(nft)
        end)

        # Rate limiting
        Process.sleep(100)
      end)
    end
  end

  defp sync_single_time_reward(nft) do
    # Time rewards are deterministic: pending = rate × (now - time_last_claim)
    # - time_start_time: when rewards started accruing (from contract registration)
    # - time_last_claim: when user last claimed (resets pending to 0)
    # - time_total_claimed: cumulative amount claimed so far
    #
    # We use get_time_reward_raw() to get the actual lastClaimTime from the contract's
    # public mapping, which is authoritative.

    case HighRollers.Contracts.NFTRewarder.get_time_reward_raw(nft.token_id) do
      {:ok, raw_info} ->
        updates = %{}

        # 1. Sync start_time from contract
        updates = if nft.time_start_time != raw_info.start_time and raw_info.start_time > 0 do
          Logger.info("[EarningsSyncer] Syncing time_start_time for token #{nft.token_id}: #{nft.time_start_time} -> #{raw_info.start_time}")
          Map.put(updates, :time_start_time, raw_info.start_time)
        else
          updates
        end

        # 2. Sync last_claim_time from contract (authoritative source)
        updates = if nft.time_last_claim != raw_info.last_claim_time and raw_info.last_claim_time > 0 do
          Logger.info("[EarningsSyncer] Syncing time_last_claim for token #{nft.token_id}: #{nft.time_last_claim} -> #{raw_info.last_claim_time}")
          Map.put(updates, :time_last_claim, raw_info.last_claim_time)
        else
          updates
        end

        # 3. Sync total_claimed from contract
        mnesia_claimed = parse_wei(nft.time_total_claimed) || 0

        updates = if raw_info.total_claimed != mnesia_claimed do
          Logger.info("[EarningsSyncer] Syncing time_total_claimed for token #{nft.token_id}: #{format_rogue(mnesia_claimed)} -> #{format_rogue(raw_info.total_claimed)} ROGUE")
          Map.put(updates, :time_total_claimed, Integer.to_string(raw_info.total_claimed))
        else
          updates
        end

        # Apply updates if any
        if map_size(updates) > 0 do
          HighRollers.NFTStore.update_time_reward(nft.token_id, updates)
        end

      {:error, reason} ->
        Logger.warning("[EarningsSyncer] Failed to get time reward raw info for token #{nft.token_id}: #{inspect(reason)}")
    end
  end

  defp parse_wei(nil), do: 0
  defp parse_wei(str) when is_binary(str) do
    case Integer.parse(str) do
      {int, _} -> int
      :error -> 0
    end
  end
  defp parse_wei(int) when is_integer(int), do: int

  defp sync_global_stats(global_24h_wei, nft_value_in_rogue_wei) do
    case HighRollers.Contracts.NFTRewarder.get_global_totals() do
      {:ok, totals} ->
        total_nfts = HighRollers.NFTStore.count()
        total_multiplier_points = HighRollers.NFTStore.get_total_multiplier_points()

        # Overall APY (average across all NFTs)
        overall_apy =
          if nft_value_in_rogue_wei > 0 and total_nfts > 0 do
            avg_24h_per_nft = div(global_24h_wei, total_nfts)
            annual = avg_24h_per_nft * 365
            div(annual * 10000, nft_value_in_rogue_wei)
          else
            0
          end

        HighRollers.Rewards.update_global_stats(%{
          total_rewards_received: Integer.to_string(totals.total_received),
          total_rewards_distributed: Integer.to_string(totals.total_distributed),
          rewards_last_24h: Integer.to_string(global_24h_wei),
          overall_apy_basis_points: overall_apy,
          total_nfts: total_nfts,
          total_multiplier_points: total_multiplier_points
        })

      {:error, reason} ->
        Logger.warning("[EarningsSyncer] Failed to get global totals: #{inspect(reason)}")
    end
  end

  defp sync_hostess_stats(global_24h_wei, total_multiplier_points, nft_value_in_rogue_wei) do
    for hostess_index <- 0..7 do
      multiplier = Enum.at(@multipliers, hostess_index, 30)
      nft_count = HighRollers.NFTStore.count_by_hostess(hostess_index)
      total_points = nft_count * multiplier

      share_basis_points =
        if total_multiplier_points > 0 do
          div(total_points * 10000, total_multiplier_points)
        else
          0
        end

      # Revenue 24h per NFT
      last_24h_per_nft =
        if total_multiplier_points > 0 do
          div(global_24h_wei * multiplier, total_multiplier_points)
        else
          0
        end

      # Revenue APY
      apy_basis_points =
        if nft_value_in_rogue_wei > 0 do
          annual = last_24h_per_nft * 365
          div(annual * 10000, nft_value_in_rogue_wei)
        else
          0
        end

      # Time rewards (for special NFTs)
      special_nft_count = HighRollers.NFTStore.count_special_by_hostess(hostess_index)
      {time_24h_per_nft, time_apy_basis_points} =
        if special_nft_count > 0 do
          HighRollers.TimeRewards.calculate_hostess_time_stats(hostess_index, nft_value_in_rogue_wei)
        else
          {0, 0}
        end

      HighRollers.Rewards.update_hostess_stats(hostess_index, %{
        nft_count: nft_count,
        total_points: total_points,
        share_basis_points: share_basis_points,
        last_24h_per_nft: Integer.to_string(last_24h_per_nft),
        apy_basis_points: apy_basis_points,
        time_24h_per_nft: Integer.to_string(time_24h_per_nft),
        time_apy_basis_points: time_apy_basis_points,
        special_nft_count: special_nft_count
      })
    end
  end

  defp get_nft_value_in_rogue_wei do
    # Try to get prices from Blockster's PriceTracker if available
    # Otherwise use defaults
    rogue_price = get_rogue_price()
    eth_price = get_eth_price()

    if rogue_price > 0 and eth_price > 0 do
      nft_value_usd = 0.32 * eth_price
      nft_value_rogue = nft_value_usd / rogue_price
      trunc(nft_value_rogue * 1.0e18)
    else
      # Default: ~9.6M ROGUE when prices unavailable
      9_600_000_000_000_000_000_000_000
    end
  end

  # Prices come from PriceCache (Mnesia) - fast synchronous reads
  defp get_rogue_price, do: HighRollers.PriceCache.get_rogue_price()
  defp get_eth_price, do: HighRollers.PriceCache.get_eth_price()

  defp format_rogue(wei) when is_integer(wei), do: Float.round(wei / 1.0e18, 2)
  defp format_rogue(_), do: 0.0
end
