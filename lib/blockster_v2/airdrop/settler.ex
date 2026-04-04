defmodule BlocksterV2.Airdrop.Settler do
  @moduledoc """
  GlobalSingleton GenServer that automatically settles airdrop rounds when they expire.

  Uses precise timer scheduling (Process.send_after) instead of polling.
  On startup, reconstructs state from DB to handle restarts gracefully:
  - "closed" round → settle immediately (interrupted settlement)
  - "open" round past end_time → settle immediately (missed timer)
  - "open" round in future → schedule timer for remaining delay
  - No active round → wait for :round_created cast

  Settlement pipeline (Solana):
  1. Close round on-chain → captures slot_at_close
  2. Draw winners locally (SHA256 provably fair)
  3. Submit draw_winners tx on-chain (server_seed + winner list)
  4. Broadcast results via PubSub
  """

  use GenServer
  require Logger

  alias BlocksterV2.{Airdrop, BuxMinter, GlobalSingleton}

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

    case BuxMinter.airdrop_close(round.round_id) do
      {:ok, response} ->
        slot_at_close = response["slotAtClose"]
        close_tx = response["transactionHash"]

        if slot_at_close do
          case Airdrop.close_round(round.round_id, slot_at_close, close_tx: close_tx) do
            {:ok, closed_round} ->
              Logger.info("[Settler] Round #{round.round_id} closed (slot: #{slot_at_close}, tx: #{close_tx})")
              settle_round(closed_round)

            {:error, reason} ->
              Logger.error("[Settler] Failed to close round #{round.round_id} in DB: #{inspect(reason)}")
          end
        else
          Logger.error("[Settler] Close response missing slotAtClose for round #{round.round_id}")
        end

      {:error, reason} ->
        Logger.error("[Settler] On-chain close failed for round #{round.round_id}: #{inspect(reason)}")
    end
  end

  defp settle_round(%{status: "closed"} = round) do
    Logger.info("[Settler] Drawing winners for round #{round.round_id}...")

    case Airdrop.draw_winners(round.round_id) do
      {:ok, _updated_round} ->
        winners = Airdrop.get_winners(round.round_id)
        Logger.info("[Settler] Round #{round.round_id} drawn — #{length(winners)} winners")

        # Submit draw to on-chain program
        draw_on_chain(round, winners)

        # Broadcast drawn state immediately
        Phoenix.PubSub.broadcast(
          BlocksterV2.PubSub,
          "airdrop:#{round.round_id}",
          {:airdrop_drawn, round.round_id, []}
        )

        # Reveal winners one by one via PubSub
        round_id = round.round_id
        Task.start(fn -> reveal_winners(round_id, winners) end)

      {:error, :no_entries} ->
        Logger.warning("[Settler] Round #{round.round_id} has no entries, skipping draw")

      {:error, reason} ->
        Logger.error("[Settler] Failed to draw round #{round.round_id}: #{inspect(reason)}")
    end
  end

  defp settle_round(%{status: status} = round) do
    Logger.info("[Settler] Round #{round.round_id} already in status #{status}, nothing to do")
  end

  defp reveal_winners(round_id, winners) do
    Enum.each(winners, fn winner ->
      Phoenix.PubSub.broadcast(
        BlocksterV2.PubSub,
        "airdrop:#{round_id}",
        {:airdrop_winner_revealed, round_id, winner}
      )
    end)
  end

  defp draw_on_chain(round, winners) do
    case Airdrop.get_round(round.round_id) do
      %{server_seed: server_seed} when is_binary(server_seed) ->
        # Build winner list for on-chain submission
        winner_infos =
          Enum.map(winners, fn w ->
            %{wallet: w.wallet_address, amount: w.prize_usd}
          end)

        case BuxMinter.airdrop_draw_winners(round.round_id, server_seed, winner_infos) do
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
