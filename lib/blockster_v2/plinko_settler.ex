defmodule BlocksterV2.PlinkoSettler do
  @moduledoc """
  Background worker that periodically checks for unsettled Plinko bets and settles them.

  Runs every 60 seconds and:
  1. Finds bets with status :placed older than 120 seconds
  2. Calls PlinkoGame.settle_game/1 for each stuck bet
  3. Handles failures gracefully (logs warning, continues to next)

  Uses GlobalSingleton pattern — only one instance runs across the cluster.
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

  @max_settle_attempts 3

  @impl true
  def init(_) do
    {:ok, %{registered: false, attempts: %{}}}
  end

  @impl true
  def handle_info(:registered, %{registered: false} = state) do
    Logger.info("[PlinkoSettler] Starting Plinko bet settlement checker (runs every minute)")
    schedule_check()
    {:noreply, %{state | registered: true}}
  end

  def handle_info(:registered, state) do
    {:noreply, state}
  end

  def handle_info(:check_unsettled_bets, state) do
    attempts = check_and_settle_stuck_bets(state.attempts)
    schedule_check()
    {:noreply, %{state | attempts: attempts}}
  end

  defp schedule_check do
    Process.send_after(self(), :check_unsettled_bets, @check_interval)
  end

  defp check_and_settle_stuck_bets(attempts) do
    now = System.system_time(:second)
    cutoff = now - @settlement_timeout

    # Find all :placed games older than cutoff
    case :mnesia.dirty_index_read(:plinko_games, :placed, :status) do
      games when is_list(games) ->
        stuck =
          Enum.filter(games, fn game ->
            elem(game, 7) == :placed and elem(game, 23) != nil and elem(game, 23) < cutoff
          end)

        if length(stuck) > 0 do
          Logger.info("[PlinkoSettler] Found #{length(stuck)} stuck Plinko bets, settling...")
        end

        Enum.reduce(stuck, attempts, fn game, acc ->
          game_id = elem(game, 1)
          attempt_count = Map.get(acc, game_id, 0)

          try do
            if attempt_count >= @max_settle_attempts do
              Logger.warning("[PlinkoSettler] Game #{game_id} failed #{attempt_count} times, force-marking as settled")

              case BlocksterV2.PlinkoGame.get_game(game_id) do
                {:ok, game_map} ->
                  BlocksterV2.PlinkoGame.mark_game_settled(game_id, game_map, "settlement_failed_max_retries")

                _ ->
                  :ok
              end

              Map.delete(acc, game_id)
            else
              age = now - elem(game, 23)
              Logger.info("[PlinkoSettler] Settling stuck Plinko bet: #{game_id} (placed #{age}s ago, attempt #{attempt_count + 1})")

              case BlocksterV2.PlinkoGame.settle_game(game_id) do
                {:ok, _} ->
                  Logger.info("[PlinkoSettler] Successfully settled #{game_id}")
                  Map.delete(acc, game_id)

                {:error, reason} ->
                  Logger.warning("[PlinkoSettler] Failed to settle #{game_id}: #{inspect(reason)}")
                  Map.put(acc, game_id, attempt_count + 1)
              end
            end
          rescue
            error ->
              Logger.error("[PlinkoSettler] Error settling game #{game_id}: #{inspect(error)}")
              Map.put(acc, game_id, attempt_count + 1)
          end
        end)

      _ ->
        attempts
    end
  end
end
