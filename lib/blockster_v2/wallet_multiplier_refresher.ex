defmodule BlocksterV2.WalletMultiplierRefresher do
  @moduledoc """
  Background GenServer that recalculates hardware wallet multipliers daily.

  Runs at 3:00 AM UTC every day to refresh multipliers for all users with connected wallets.
  Uses GlobalSingleton for safe multi-node deployment.
  """

  use GenServer
  require Logger
  alias BlocksterV2.{WalletMultiplier, Wallets, GlobalSingleton}

  # Refresh every 24 hours (3:00 AM UTC)
  @refresh_interval :timer.hours(24)

  def start_link(opts) do
    case GlobalSingleton.start_link(__MODULE__, opts) do
      {:ok, pid} ->
        {:ok, pid}

      {:already_registered, _pid} ->
        Logger.info("[WalletMultiplierRefresher] Already running on another node")
        :ignore
    end
  end

  def init(_opts) do
    Logger.info("[WalletMultiplierRefresher] Starting multiplier refresh service")

    # Schedule first refresh based on time until 3 AM UTC
    schedule_next_refresh()

    {:ok, %{last_refresh: nil, refresh_count: 0}}
  end

  # Public API

  @doc """
  Manually trigger a refresh of all wallet multipliers.
  """
  def refresh_all_multipliers do
    GenServer.call({:global, __MODULE__}, :refresh_all, :timer.minutes(5))
  end

  @doc """
  Get refresh service status.
  """
  def status do
    GenServer.call({:global, __MODULE__}, :status)
  end

  # Server Callbacks

  def handle_call(:refresh_all, _from, state) do
    result = do_refresh_all_multipliers()
    {:reply, result, Map.put(state, :last_refresh, System.system_time(:second))}
  end

  def handle_call(:status, _from, state) do
    {:reply, state, state}
  end

  def handle_info(:refresh_multipliers, state) do
    Logger.info("[WalletMultiplierRefresher] Starting scheduled multiplier refresh")

    result = do_refresh_all_multipliers()

    # Schedule next refresh
    schedule_next_refresh()

    new_state =
      state
      |> Map.put(:last_refresh, System.system_time(:second))
      |> Map.update(:refresh_count, 1, &(&1 + 1))

    Logger.info(
      "[WalletMultiplierRefresher] Completed refresh #{new_state.refresh_count}: #{inspect(result)}"
    )

    {:noreply, new_state}
  end

  # Private Functions

  defp schedule_next_refresh do
    # Calculate time until 3:00 AM UTC tomorrow
    now = DateTime.utc_now()
    target_hour = 3

    # Get 3 AM today
    target_today =
      DateTime.new!(Date.utc_today(), Time.new!(target_hour, 0, 0), "Etc/UTC")

    # If we've passed 3 AM today, schedule for tomorrow
    target =
      if DateTime.compare(now, target_today) == :gt do
        DateTime.add(target_today, 1, :day)
      else
        target_today
      end

    delay_ms = DateTime.diff(target, now, :millisecond)

    Logger.info(
      "[WalletMultiplierRefresher] Next refresh scheduled for #{DateTime.to_iso8601(target)} (in #{div(delay_ms, 1000)} seconds)"
    )

    Process.send_after(self(), :refresh_multipliers, delay_ms)
  end

  defp do_refresh_all_multipliers do
    # Get all connected wallets from Mnesia
    connected_wallets =
      :mnesia.dirty_match_object({:connected_wallets, :_, :_, :_, :_, :_, :_})

    # Get unique user IDs
    user_ids = Enum.map(connected_wallets, fn record -> elem(record, 1) end) |> Enum.uniq()

    Logger.info(
      "[WalletMultiplierRefresher] Refreshing multipliers for #{length(user_ids)} users"
    )

    # Refresh multiplier for each user
    results =
      Enum.map(user_ids, fn user_id ->
        try do
          case WalletMultiplier.update_user_multiplier(user_id) do
            {:ok, multiplier_data} ->
              {:ok, user_id, multiplier_data.total_multiplier}

            error ->
              Logger.error(
                "[WalletMultiplierRefresher] Failed to update multiplier for user #{user_id}: #{inspect(error)}"
              )

              {:error, user_id, error}
          end
        rescue
          e ->
            Logger.error(
              "[WalletMultiplierRefresher] Exception updating multiplier for user #{user_id}: #{inspect(e)}"
            )

            {:error, user_id, e}
        end
      end)

    # Count successes and failures
    successes = Enum.count(results, fn {status, _, _} -> status == :ok end)
    failures = Enum.count(results, fn {status, _, _} -> status == :error end)

    %{
      total_users: length(user_ids),
      successes: successes,
      failures: failures,
      timestamp: System.system_time(:second)
    }
  end
end
