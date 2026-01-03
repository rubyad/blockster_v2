defmodule BlocksterV2.BuxBoosterBetSettler do
  @moduledoc """
  Background worker that periodically checks for unsettled BuxBooster bets and attempts to settle them.

  Runs every minute and:
  1. Finds bets that have been placed but not settled (status = :placed)
  2. Checks if they're older than 30 seconds (to avoid settling bets that just finished)
  3. Attempts to settle them via BUX Minter

  This ensures that bets don't get stuck in "placed" state due to temporary network issues,
  server restarts, or other transient failures.
  """

  use GenServer
  require Logger

  @check_interval :timer.minutes(1)
  @settlement_timeout 120  # Don't try to settle bets younger than 2 minutes (in seconds)

  def start_link(_opts) do
    # Use global registration to ensure only one BetSettler runs across the cluster
    # This prevents duplicate settlement attempts from multiple nodes
    case GenServer.start_link(__MODULE__, [], name: {:global, __MODULE__}) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, {:already_started, _pid}} ->
        # Another node already started the global GenServer - this is expected
        :ignore
    end
  end

  def init(_) do
    Logger.info("[BetSettler] Starting bet settlement checker (runs every minute)")
    schedule_check()
    {:ok, %{}}
  end

  def handle_info(:check_unsettled_bets, state) do
    check_and_settle_bets()
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check_unsettled_bets, @check_interval)
  end

  defp check_and_settle_bets do
    now = System.system_time(:second)
    cutoff_time = now - @settlement_timeout

    unsettled_bets = find_unsettled_bets(cutoff_time)

    if length(unsettled_bets) > 0 do
      Logger.info("[BetSettler] Found #{length(unsettled_bets)} unsettled bets older than 2 minutes")
      Enum.each(unsettled_bets, &attempt_settlement/1)
    end
  end

  defp find_unsettled_bets(cutoff_time) do
    # Find all games with status = :placed that are older than cutoff_time
    # Table structure (1-indexed):
    # 1:game_id, 2:user_id, 3:wallet_address, 4:server_seed, 5:commitment_hash,
    # 6:nonce, 7:status, 8:bet_id, 9:token, 10:token_address, 11:bet_amount,
    # 12:difficulty, 13:predictions, 14:results, 15:won, 16:payout,
    # 17:commitment_tx, 18:bet_tx, 19:settlement_tx, 20:created_at, 21:settled_at
    :mnesia.dirty_match_object({:bux_booster_onchain_games, :_, :_, :_, :_, :_, :_, :placed, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_})
    |> Enum.filter(fn record ->
      # Element 20 is created_at timestamp (when bet was placed)
      created_at = elem(record, 20)
      created_at != nil and created_at < cutoff_time
    end)
    |> Enum.map(fn record ->
      %{
        game_id: elem(record, 1),
        user_id: elem(record, 2),
        commitment_hash: elem(record, 5),
        server_seed: elem(record, 4),
        results: elem(record, 14),
        won: elem(record, 15),
        created_at: elem(record, 20)
      }
    end)
  end

  defp attempt_settlement(bet) do
    age_seconds = System.system_time(:second) - bet.created_at
    Logger.info("[BetSettler] Attempting to settle bet #{bet.game_id} (placed #{age_seconds}s ago)")

    # Use BuxBoosterOnchain.settle_game which handles the full settlement flow
    case BlocksterV2.BuxBoosterOnchain.settle_game(bet.game_id) do
      {:ok, %{tx_hash: tx_hash}} ->
        Logger.info("[BetSettler] ✅ Successfully settled bet #{bet.game_id}: #{tx_hash}")
        :ok

      {:error, reason} ->
        Logger.error("[BetSettler] ❌ Failed to settle bet #{bet.game_id}: #{inspect(reason)}")
        :error
    end
  rescue
    error ->
      Logger.error("[BetSettler] ❌ Exception settling bet #{bet.game_id}: #{inspect(error)}")
      :error
  end
end
