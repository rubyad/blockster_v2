defmodule BlocksterV2.ContentAutomation.ContentQueue do
  @moduledoc """
  Schedules and publishes approved articles.

  Runs as a global singleton. Checks for approved queue entries every 10 minutes
  and publishes any that are due (scheduled_at <= now or unscheduled).
  """

  use GenServer
  require Logger

  alias BlocksterV2.ContentAutomation.{ContentPublisher, FeedStore, Settings}

  @check_interval :timer.minutes(10)

  # ── Client API ──

  def start_link(opts) do
    case BlocksterV2.GlobalSingleton.start_link(__MODULE__, opts) do
      {:ok, pid} -> {:ok, pid}
      {:already_registered, _pid} -> :ignore
    end
  end

  @doc "Force publish the next approved article (for admin)."
  def force_publish_next do
    case :global.whereis_name(__MODULE__) do
      :undefined -> {:error, :not_running}
      pid -> GenServer.call(pid, :force_publish_next, 60_000)
    end
  end

  @doc "Schedule a precise publish at a specific time."
  def schedule_at(scheduled_at) do
    case :global.whereis_name(__MODULE__) do
      :undefined -> :ok
      pid -> GenServer.cast(pid, {:schedule_at, scheduled_at})
    end
  end

  @doc "Get current queue state (for admin dashboard)."
  def get_state do
    case :global.whereis_name(__MODULE__) do
      :undefined -> {:error, :not_running}
      pid -> GenServer.call(pid, :get_state)
    end
  end

  # ── Server Callbacks ──

  @impl true
  def init(_opts) do
    Logger.info("[ContentQueue] Starting on #{node()}")
    schedule_check()

    {:ok, %{
      last_check: nil,
      total_published: 0
    }}
  end

  @impl true
  def handle_info(:check_queue, state) do
    state = maybe_publish(state)
    schedule_check()
    {:noreply, state}
  end

  @impl true
  def handle_info(:scheduled_publish, state) do
    Logger.info("[ContentQueue] Executing scheduled publish")
    state = maybe_publish(state)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:schedule_at, scheduled_at}, state) do
    delay_ms = DateTime.diff(scheduled_at, DateTime.utc_now(), :millisecond) |> max(0)
    Process.send_after(self(), :scheduled_publish, delay_ms)
    Logger.info("[ContentQueue] Precise publish scheduled in #{div(delay_ms, 1000)}s")
    {:noreply, state}
  end

  @impl true
  def handle_call(:force_publish_next, _from, state) do
    case publish_next_approved() do
      {:ok, post} ->
        {:reply, {:ok, post}, %{state | total_published: state.total_published + 1}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    info = Map.merge(state, %{
      next_check_in: "#{div(@check_interval, 60_000)} min"
    })
    {:reply, info, state}
  end

  # ── Publishing Logic ──

  defp maybe_publish(state) do
    state = %{state | last_check: DateTime.utc_now() |> DateTime.truncate(:second)}

    # Check for expired offers (runs regardless of pause state)
    check_expired_offers()

    cond do
      Settings.paused?() ->
        Logger.debug("[ContentQueue] Pipeline paused, skipping")
        state

      not should_publish_now?() ->
        state

      true ->
        case publish_next_approved() do
          {:ok, _post} ->
            %{state | total_published: state.total_published + 1}

          {:error, :nothing_approved} ->
            state

          {:error, reason} ->
            Logger.error("[ContentQueue] Publish failed: #{inspect(reason)}")
            state
        end
    end
  end

  defp publish_next_approved do
    case get_next_approved_entry() do
      nil ->
        {:error, :nothing_approved}

      entry ->
        ContentPublisher.publish_queue_entry(entry)
    end
  end

  defp get_next_approved_entry do
    import Ecto.Query

    now = DateTime.utc_now()

    BlocksterV2.ContentAutomation.ContentPublishQueue
    |> where([q], q.status == "approved")
    |> where([q], is_nil(q.scheduled_at) or q.scheduled_at <= ^now)
    |> order_by([q], asc: q.scheduled_at, asc: q.inserted_at)
    |> limit(1)
    |> BlocksterV2.Repo.one()
    |> case do
      nil -> nil
      entry -> BlocksterV2.Repo.preload(entry, [:author])
    end
  end

  # ── Scheduling Logic ──

  defp should_publish_now? do
    count_approved() > 0
  end

  defp count_approved do
    import Ecto.Query

    BlocksterV2.ContentAutomation.ContentPublishQueue
    |> where([q], q.status == "approved")
    |> BlocksterV2.Repo.aggregate(:count)
  end

  defp schedule_check do
    Process.send_after(self(), :check_queue, @check_interval)
  end

  # Check for published offers that have expired. Logs for admin awareness.
  # The show page already detects expiration in real-time via load_offer_data/1.
  defp check_expired_offers do
    expired = FeedStore.get_published_expired_offers(DateTime.utc_now())

    for entry <- expired do
      Logger.info("[ContentQueue] Offer expired: post #{entry.post_id} (#{entry.article_data["title"]})")
    end
  rescue
    e ->
      Logger.debug("[ContentQueue] Expired offer check failed: #{Exception.message(e)}")
  end
end
