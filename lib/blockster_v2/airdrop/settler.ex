defmodule BlocksterV2.Airdrop.Settler do
  @moduledoc """
  GlobalSingleton GenServer that automatically settles airdrop rounds when they expire.

  Uses precise timer scheduling (Process.send_after) instead of polling.
  On startup, reconstructs state from DB to handle restarts gracefully:
  - "closed" round → settle immediately (interrupted settlement)
  - "open" round past end_time → settle immediately (missed timer)
  - "open" round in future → schedule timer for remaining delay
  - No active round → wait for :round_created cast
  """

  use GenServer
  require Logger

  alias BlocksterV2.{Airdrop, BuxMinter, GlobalSingleton}

  @rpc_url "https://rpc.roguechain.io/rpc"

  def start_link(opts) do
    case GlobalSingleton.start_link(__MODULE__, opts) do
      {:ok, pid} -> {:ok, pid}
      {:already_registered, _} -> :ignore
    end
  end

  @doc """
  Notify the settler that a new round was created.
  Called from Airdrop.create_round/1.
  """
  def notify_round_created(round_id, end_time) do
    GenServer.cast({:global, __MODULE__}, {:round_created, round_id, end_time})
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(_) do
    # Reconstruct state from DB on startup
    send(self(), :recover)
    {:ok, %{timer_ref: nil, round_id: nil}}
  end

  @impl true
  def handle_info(:recover, state) do
    {:noreply, recover_from_db(state)}
  end

  @impl true
  def handle_info({:settle, round_id}, state) do
    case Airdrop.get_round(round_id) do
      nil ->
        Logger.warning("[Settler] Round #{round_id} not found, ignoring timer")
        {:noreply, %{state | timer_ref: nil, round_id: nil}}

      round ->
        settle_round(round)
        {:noreply, %{state | timer_ref: nil, round_id: nil}}
    end
  end

  @impl true
  def handle_cast({:round_created, round_id, end_time}, state) do
    # Cancel any existing timer
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)

    delay_ms = max(DateTime.diff(end_time, DateTime.utc_now(), :millisecond), 0)
    Logger.info("[Settler] Round #{round_id} scheduled for settlement in #{div(delay_ms, 1000)}s")

    ref = Process.send_after(self(), {:settle, round_id}, delay_ms)
    {:noreply, %{state | timer_ref: ref, round_id: round_id}}
  end

  # ============================================================================
  # Settlement Pipeline
  # ============================================================================

  defp settle_round(%{status: "open"} = round) do
    Logger.info("[Settler] Closing round #{round.round_id}...")

    # Try on-chain close first, fall back to RPC block hash if vault has no active round
    {block_hash, close_tx} =
      case BuxMinter.airdrop_close(round.round_id) do
        {:ok, response} ->
          {response["blockHashAtClose"], response["transactionHash"]}

        {:error, reason} ->
          Logger.warning("[Settler] On-chain close failed (#{inspect(reason)}), falling back to RPC block hash")
          {fetch_rogue_block_hash(), nil}
      end

    if block_hash do
      case Airdrop.close_round(round.round_id, block_hash, close_tx: close_tx) do
        {:ok, closed_round} ->
          Logger.info("[Settler] Round #{round.round_id} closed (block_hash: #{block_hash})")
          settle_round(closed_round)

        {:error, reason} ->
          Logger.error("[Settler] Failed to close round #{round.round_id} in DB: #{inspect(reason)}")
      end
    else
      Logger.error("[Settler] Could not obtain block hash for round #{round.round_id}")
    end
  end

  defp settle_round(%{status: "closed"} = round) do
    Logger.info("[Settler] Drawing winners for round #{round.round_id}...")

    case Airdrop.draw_winners(round.round_id) do
      {:ok, _updated_round} ->
        winners = Airdrop.get_winners(round.round_id)
        Logger.info("[Settler] Round #{round.round_id} drawn — #{length(winners)} winners")

        # Sync draw on-chain so vault's getWinnerInfo() works
        draw_on_chain(round)

        # Broadcast drawn state immediately (empty winners — they reveal one by one)
        Phoenix.PubSub.broadcast(
          BlocksterV2.PubSub,
          "airdrop:#{round.round_id}",
          {:airdrop_drawn, round.round_id, []}
        )

        # Register prizes on-chain and reveal winners one by one as each confirms
        round_id = round.round_id
        Task.start(fn -> register_and_reveal_prizes(round_id, winners) end)

      {:error, :no_entries} ->
        Logger.warning("[Settler] Round #{round.round_id} has no entries, skipping draw")

      {:error, reason} ->
        Logger.error("[Settler] Failed to draw round #{round.round_id}: #{inspect(reason)}")
    end
  end

  defp settle_round(%{status: status} = round) do
    Logger.info("[Settler] Round #{round.round_id} already in status #{status}, nothing to do")
  end

  defp register_and_reveal_prizes(round_id, winners) do
    Enum.each(winners, fn winner ->
      wallet = winner.external_wallet || winner.wallet_address

      # 1. Register prize on PrizePool (Arbitrum) for USDT payout
      prize_registered =
        case BuxMinter.airdrop_set_prize(round_id, winner.winner_index, wallet, winner.prize_usdt) do
          {:ok, _} ->
            Logger.debug("[Settler] Prize #{winner.winner_index} registered for #{wallet}")
            Airdrop.mark_prize_registered(round_id, winner.winner_index)
            true

          {:error, reason} ->
            Logger.warning("[Settler] Prize #{winner.winner_index} registration failed: #{inspect(reason)}")
            false
        end

      # 2. Push winner to vault (Rogue Chain) for on-chain verification
      winner_data = %{
        random_number: winner.random_number,
        blockster_wallet: winner.wallet_address,
        external_wallet: winner.external_wallet || winner.wallet_address,
        bux_redeemed: winner.deposit_amount,
        block_start: winner.deposit_start,
        block_end: winner.deposit_end
      }

      # prize_position is 1-indexed (winner_index is 0-indexed)
      case BuxMinter.airdrop_set_winner(round_id, winner.winner_index + 1, winner_data) do
        {:ok, _} ->
          Logger.debug("[Settler] Winner #{winner.winner_index} set on vault")

        {:error, reason} ->
          Logger.warning("[Settler] Winner #{winner.winner_index} vault set failed: #{inspect(reason)}")
      end

      # 3. Reveal to UI (with current prize_registered status)
      revealed_winner = %{winner | prize_registered: prize_registered}

      Phoenix.PubSub.broadcast(
        BlocksterV2.PubSub,
        "airdrop:#{round_id}",
        {:airdrop_winner_revealed, round_id, revealed_winner}
      )
    end)
  end

  defp draw_on_chain(round) do
    case Airdrop.get_round(round.round_id) do
      %{server_seed: server_seed} when is_binary(server_seed) ->
        case BuxMinter.airdrop_draw_winners(server_seed) do
          {:ok, resp} ->
            Logger.info("[Settler] On-chain draw synced for round #{round.round_id}: tx=#{resp["transactionHash"]}")

          {:error, reason} ->
            Logger.warning("[Settler] On-chain draw failed (non-blocking): #{inspect(reason)}")
        end

      _ ->
        Logger.warning("[Settler] No server_seed found for round #{round.round_id}, skipping on-chain draw")
    end
  end

  # ============================================================================
  # Recovery
  # ============================================================================

  defp fetch_rogue_block_hash do
    body = %{jsonrpc: "2.0", method: "eth_getBlockByNumber", params: ["latest", false], id: 1}

    case Req.post(@rpc_url, json: body, receive_timeout: 15_000) do
      {:ok, %{status: 200, body: %{"result" => %{"hash" => hash}}}} ->
        Logger.info("[Settler] Fetched Rogue block hash via RPC: #{hash}")
        hash

      {:ok, %{body: body}} ->
        Logger.error("[Settler] Unexpected RPC response: #{inspect(body)}")
        nil

      {:error, reason} ->
        Logger.error("[Settler] RPC call failed: #{inspect(reason)}")
        nil
    end
  end

  defp recover_from_db(state) do
    verify_round_id_sync()

    case Airdrop.get_current_round() do
      %{status: "closed"} = round ->
        Logger.info("[Settler] Found interrupted round #{round.round_id} (closed), settling now")
        settle_round(round)
        state

      %{status: "open"} = round ->
        now = DateTime.utc_now()

        if DateTime.compare(round.end_time, now) == :lt do
          Logger.info("[Settler] Found expired round #{round.round_id}, settling now")
          settle_round(round)
          state
        else
          delay_ms = DateTime.diff(round.end_time, now, :millisecond)
          Logger.info("[Settler] Found active round #{round.round_id}, settling in #{div(delay_ms, 1000)}s")
          ref = Process.send_after(self(), {:settle, round.round_id}, delay_ms)
          %{state | timer_ref: ref, round_id: round.round_id}
        end

      %{status: "drawn"} ->
        Logger.info("[Settler] Current round already drawn, waiting for next round")
        state

      nil ->
        Logger.info("[Settler] No active round, waiting for :round_created")
        state
    end
  end

  defp verify_round_id_sync do
    import Ecto.Query, warn: false
    alias BlocksterV2.Airdrop.Round

    db_max =
      case BlocksterV2.Repo.one(from r in Round, select: max(r.round_id)) do
        nil -> 0
        max_id -> max_id
      end

    case BuxMinter.airdrop_get_vault_round_id() do
      {:ok, vault_round_id} ->
        cond do
          vault_round_id == db_max ->
            Logger.info("[Settler] Round IDs in sync: vault=#{vault_round_id}, DB=#{db_max}")

          vault_round_id > db_max ->
            Logger.warning("[Settler] Vault ahead of DB: vault=#{vault_round_id}, DB=#{db_max} (gap of #{vault_round_id - db_max})")

          vault_round_id < db_max ->
            Logger.error("[Settler] DB ahead of vault: vault=#{vault_round_id}, DB=#{db_max} — this should not happen!")
        end

      {:error, reason} ->
        Logger.warning("[Settler] Could not verify round ID sync (vault unreachable): #{inspect(reason)}")
    end
  end
end
