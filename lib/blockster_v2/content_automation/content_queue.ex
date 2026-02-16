defmodule BlocksterV2.ContentAutomation.ContentQueue do
  @moduledoc """
  Schedules and publishes approved articles.

  Runs as a global singleton. Checks for approved queue entries every 10 minutes
  and publishes any that are due (scheduled_at <= now or unscheduled).
  """

  use GenServer
  require Logger

  alias BlocksterV2.ContentAutomation.{ContentPublisher, EventRoundup, FeedStore, MarketContentScheduler, Settings}

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

    # Check for weekly content generation (runs regardless of pause state)
    maybe_generate_weekly_content()

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

  # Generate weekly content on schedule:
  # - Fridays (day 5): Market movers analysis
  # - Sundays (day 7): Event roundup
  # Also runs narrative report check on every cycle (self-gates via Settings).
  @doc false
  def maybe_generate_weekly_content do
    today = Date.utc_today()
    day = Date.day_of_week(today)
    today_str = Date.to_iso8601(today)

    # Friday: Weekly market movers
    if day == 5 do
      last_market = Settings.get(:last_market_movers_date)

      if last_market != today_str do
        Logger.info("[ContentQueue] Friday detected, generating weekly market movers")

        Task.start(fn ->
          case MarketContentScheduler.maybe_generate_weekly_movers() do
            {:ok, entry} ->
              Logger.info("[ContentQueue] Market movers generated: \"#{entry.article_data["title"]}\"")

            {:error, reason} ->
              Logger.warning("[ContentQueue] Market movers skipped: #{inspect(reason)}")
          end
        end)
      end
    end

    # Sunday: Weekly event roundup
    if day == 7 do
      last_generated = Settings.get(:last_weekly_roundup_date)

      if last_generated != today_str do
        Logger.info("[ContentQueue] Sunday detected, generating weekly event roundup")
        Settings.set(:last_weekly_roundup_date, today_str)

        Task.start(fn ->
          case EventRoundup.generate_weekly_roundup() do
            {:ok, entry} ->
              Logger.info("[ContentQueue] Weekly roundup generated: \"#{entry.article_data["title"]}\"")

            {:error, reason} ->
              Logger.warning("[ContentQueue] Weekly roundup skipped: #{inspect(reason)}")
          end
        end)
      end
    end

    # Every cycle: Check for strong narrative rotations (self-gates via Settings)
    Task.start(fn ->
      case MarketContentScheduler.maybe_generate_narrative_report() do
        {:ok, _results} ->
          Logger.info("[ContentQueue] Narrative report(s) generated")

        {:error, :no_strong_narratives} ->
          :ok

        {:error, reason} ->
          Logger.debug("[ContentQueue] Narrative report check: #{inspect(reason)}")
      end
    end)
  rescue
    e ->
      Logger.debug("[ContentQueue] Weekly content check failed: #{Exception.message(e)}")
  end
end
