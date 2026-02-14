defmodule BlocksterV2.ContentAutomation.FeedPoller do
  @moduledoc """
  Polls RSS feeds on a timer and stores new items in the database.
  Runs as a global singleton across the cluster (one poller per cluster).

  Poll interval: 5 minutes (configurable via runtime config).
  Fetches all active feeds in parallel, stores items incrementally per feed
  for crash resilience (partial failures don't lose successful results).
  """

  use GenServer
  require Logger

  alias BlocksterV2.ContentAutomation.{FeedConfig, FeedParser, FeedStore, Settings}

  @default_poll_interval :timer.minutes(5)

  # ── Client API ──

  def start_link(opts) do
    case BlocksterV2.GlobalSingleton.start_link(__MODULE__, opts) do
      {:ok, pid} -> {:ok, pid}
      {:already_registered, _pid} -> :ignore
    end
  end

  @doc "Force an immediate poll (for admin dashboard)."
  def force_poll do
    case :global.whereis_name(__MODULE__) do
      :undefined -> {:error, :not_running}
      pid -> GenServer.cast(pid, :force_poll)
    end
  end

  @doc "Get the current state (for admin dashboard)."
  def get_state do
    case :global.whereis_name(__MODULE__) do
      :undefined -> {:error, :not_running}
      pid -> GenServer.call(pid, :get_state)
    end
  end

  # ── Server Callbacks ──

  @impl true
  def init(_opts) do
    Logger.info("[FeedPoller] Starting on #{node()}")

    # Initialize settings ETS cache
    Settings.init_cache()

    # Schedule first poll after a short delay (let Mnesia finish initializing)
    Process.send_after(self(), :poll_feeds, :timer.seconds(30))

    {:ok, %{
      last_poll: nil,
      last_poll_results: %{},
      total_polls: 0
    }}
  end

  @impl true
  def handle_info(:poll_feeds, state) do
    state = do_poll(state)
    schedule_poll()
    {:noreply, state}
  end

  @impl true
  def handle_cast(:force_poll, state) do
    Logger.info("[FeedPoller] Force poll triggered")
    state = do_poll(state)
    {:noreply, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  # ── Polling Logic ──

  defp do_poll(state) do
    if Settings.paused?() do
      Logger.info("[FeedPoller] Pipeline is paused, skipping poll")
      state
    else
      feeds = FeedConfig.get_active_feeds()
      Logger.info("[FeedPoller] Polling #{length(feeds)} active feeds")

      results =
        feeds
        |> Task.async_stream(&poll_single_feed/1, max_concurrency: 5, timeout: 60_000)
        |> Enum.reduce(%{success: 0, failed: 0, new_items: 0}, fn
          {:ok, {:ok, count}}, acc ->
            %{acc | success: acc.success + 1, new_items: acc.new_items + count}

          {:ok, {:error, _reason}}, acc ->
            %{acc | failed: acc.failed + 1}

          {:exit, _reason}, acc ->
            %{acc | failed: acc.failed + 1}
        end)

      Logger.info(
        "[FeedPoller] Poll complete: #{results.success} feeds ok, " <>
        "#{results.failed} failed, #{results.new_items} new items stored"
      )

      %{state |
        last_poll: DateTime.utc_now() |> DateTime.truncate(:second),
        last_poll_results: results,
        total_polls: state.total_polls + 1
      }
    end
  end

  defp poll_single_feed(%{url: url, source: source, tier: tier}) do
    case Req.get(url, receive_timeout: 15_000, connect_options: [timeout: 10_000]) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        items =
          body
          |> FeedParser.parse()
          |> FeedParser.extract_items()
          |> Enum.map(fn item ->
            %{
              title: item.title,
              url: item.url,
              summary: item.summary,
              source: source,
              tier: Atom.to_string(tier),
              weight: FeedConfig.tier_weight(tier),
              published_at: item.published_at,
              fetched_at: DateTime.utc_now() |> DateTime.truncate(:second)
            }
          end)

        if length(items) > 0 do
          {inserted, _} = FeedStore.store_new_items(items)
          Logger.debug("[FeedPoller] #{source}: #{inserted} new / #{length(items)} total items")
          {:ok, inserted}
        else
          Logger.debug("[FeedPoller] #{source}: no items parsed")
          {:ok, 0}
        end

      {:ok, %{status: status}} ->
        Logger.warning("[FeedPoller] #{source} returned HTTP #{status}")
        {:error, {:http_status, status}}

      {:error, reason} ->
        Logger.warning("[FeedPoller] #{source} failed: #{inspect(reason)}")
        {:error, reason}
    end
  rescue
    e ->
      Logger.error("[FeedPoller] #{source} crashed: #{Exception.message(e)}")
      {:error, :crashed}
  end

  defp schedule_poll do
    interval =
      Application.get_env(:blockster_v2, :content_automation, [])[:feed_poll_interval] ||
        @default_poll_interval

    Process.send_after(self(), :poll_feeds, interval)
  end
end
