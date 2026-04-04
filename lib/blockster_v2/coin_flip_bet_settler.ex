defmodule BlocksterV2.CoinFlipBetSettler do
  @moduledoc """
  Background worker that periodically checks for unsettled Coin Flip bets and attempts to settle them.

  Runs every minute and:
  1. Finds bets in :coin_flip_games with status = :placed
  2. Checks if they're older than 2 minutes
  3. Attempts to settle them via CoinFlipGame.settle_game

  Uses GlobalSingleton to run only one instance across multi-node deployments.
  """

  use GenServer
  require Logger

  @check_interval :timer.minutes(1)
  @settlement_timeout 120  # Don't try to settle bets younger than 2 minutes (in seconds)

  def start_link(_opts) do
    case BlocksterV2.GlobalSingleton.start_link(__MODULE__, []) do
      {:ok, pid} ->
        send(pid, :registered)
        {:ok, pid}

      {:already_registered, _pid} ->
        :ignore
    end
  end

  def init(_) do
    {:ok, %{registered: false}}
  end

  def handle_info(:registered, %{registered: false} = state) do
    Logger.info("[CoinFlipBetSettler] Starting bet settlement checker (runs every minute)")
    schedule_check()
    {:noreply, %{state | registered: true}}
  end

  def handle_info(:registered, state) do
    {:noreply, state}
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
      Logger.info("[CoinFlipBetSettler] Found #{length(unsettled_bets)} unsettled bets older than 2 minutes")
      Enum.each(unsettled_bets, &attempt_settlement/1)
    end
  end

  defp find_unsettled_bets(cutoff_time) do
    # Table structure (0-indexed from tuple element 1):
    # 1:game_id, 2:user_id, 3:wallet_address, 4:server_seed, 5:commitment_hash,
    # 6:nonce, 7:status, 8:vault_type, 9:bet_amount, 10:difficulty,
    # 11:predictions, 12:results, 13:won, 14:payout,
    # 15:commitment_sig, 16:bet_sig, 17:settlement_sig, 18:created_at, 19:settled_at
    :mnesia.dirty_match_object({:coin_flip_games, :_, :_, :_, :_, :_, :_, :placed, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_})
    |> Enum.filter(fn record ->
      created_at = elem(record, 18)
      created_at != nil and created_at < cutoff_time
    end)
    |> Enum.map(fn record ->
      %{
        game_id: elem(record, 1),
        user_id: elem(record, 2),
        created_at: elem(record, 18)
      }
    end)
  rescue
    _ -> []
  catch
    :exit, _ -> []
  end

  defp attempt_settlement(bet) do
    age_seconds = System.system_time(:second) - bet.created_at
    Logger.info("[CoinFlipBetSettler] Attempting to settle bet #{bet.game_id} (placed #{age_seconds}s ago)")

    case BlocksterV2.CoinFlipGame.settle_game(bet.game_id) do
      {:ok, %{signature: sig}} ->
        Logger.info("[CoinFlipBetSettler] Settled bet #{bet.game_id}: #{sig}")
        :ok

      {:error, reason} ->
        reason_str = if is_binary(reason), do: reason, else: inspect(reason)

        if String.contains?(reason_str, "AccountNotInitialized") do
          # Bet order doesn't exist on-chain — mark as failed to stop retrying
          Logger.warning("[CoinFlipBetSettler] Bet #{bet.game_id} has no on-chain bet order, marking as failed")
          mark_game_failed(bet.game_id)
        else
          Logger.error("[CoinFlipBetSettler] Failed to settle bet #{bet.game_id}: #{reason_str}")
        end
        :error
    end
  rescue
    error ->
      Logger.error("[CoinFlipBetSettler] Exception settling bet #{bet.game_id}: #{inspect(error)}")
      :error
  end

  defp mark_game_failed(game_id) do
    case :mnesia.dirty_read({:coin_flip_games, game_id}) do
      [record] ->
        # Set status to :settled to stop retry attempts (position 7 = status)
        updated = put_elem(record, 7, :settled)
        updated = put_elem(updated, 17, "failed_no_onchain_order")
        updated = put_elem(updated, 19, System.system_time(:second))
        :mnesia.dirty_write(updated)
      _ -> :ok
    end
  end
end
