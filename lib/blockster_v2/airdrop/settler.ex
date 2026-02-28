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

  @num_winners 33

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
    Logger.info("[Settler] Closing round #{round.round_id} on-chain...")

    case BuxMinter.airdrop_close(round.round_id) do
      {:ok, response} ->
        block_hash = response["blockHashAtClose"]
        close_tx = response["transactionHash"]

        case Airdrop.close_round(round.round_id, block_hash, close_tx: close_tx) do
          {:ok, closed_round} ->
            Logger.info("[Settler] Round #{round.round_id} closed (tx: #{close_tx})")
            settle_round(closed_round)

          {:error, reason} ->
            Logger.error("[Settler] Failed to close round #{round.round_id} in DB: #{inspect(reason)}")
        end

      {:error, reason} ->
        Logger.error("[Settler] Failed to close round #{round.round_id} on-chain: #{inspect(reason)}")
    end
  end

  defp settle_round(%{status: "closed"} = round) do
    Logger.info("[Settler] Drawing winners for round #{round.round_id}...")

    case Airdrop.draw_winners(round.round_id) do
      {:ok, _updated_round} ->
        winners = Airdrop.get_winners(round.round_id)
        Logger.info("[Settler] Round #{round.round_id} drawn — #{length(winners)} winners")

        # Register prizes on-chain (non-fatal — setPrize is idempotent)
        register_prizes(round.round_id, winners)

        # Broadcast to LiveView subscribers
        Phoenix.PubSub.broadcast(
          BlocksterV2.PubSub,
          "airdrop:#{round.round_id}",
          {:airdrop_drawn, round.round_id, winners}
        )

      {:error, :no_entries} ->
        Logger.warning("[Settler] Round #{round.round_id} has no entries, skipping draw")

      {:error, reason} ->
        Logger.error("[Settler] Failed to draw round #{round.round_id}: #{inspect(reason)}")
    end
  end

  defp settle_round(%{status: status} = round) do
    Logger.info("[Settler] Round #{round.round_id} already in status #{status}, nothing to do")
  end

  defp register_prizes(round_id, winners) do
    Enum.each(winners, fn winner ->
      wallet = winner.external_wallet || winner.wallet_address

      case BuxMinter.airdrop_set_prize(round_id, winner.winner_index, wallet, winner.prize_usdt) do
        {:ok, _} ->
          Logger.debug("[Settler] Prize #{winner.winner_index} registered for #{wallet}")

        {:error, reason} ->
          Logger.warning("[Settler] Prize #{winner.winner_index} registration failed: #{inspect(reason)}")
      end
    end)
  end

  # ============================================================================
  # Recovery
  # ============================================================================

  defp recover_from_db(state) do
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
end
