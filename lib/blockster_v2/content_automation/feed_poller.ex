defmodule BlocksterV2.ContentAutomation.FeedPoller do
  @moduledoc """
  Polls RSS feeds and X (Twitter) timelines on two independent timers and
  stores new items in the database. Runs as a global singleton across the cluster.

  Defaults: RSS = 5 min, X = 60 min. Both are configurable via runtime config
  (`feed_poll_interval`, `x_feed_poll_interval`).

  X timeline fetches go through `BlocksterV2.Social.XApiClient` using the brand
  X connection's access token. The handle → user_id lookup is cached in GenServer
  state to avoid spending API quota on repeated user-lookups.
  """

  use GenServer
  require Logger

  alias BlocksterV2.ContentAutomation.{Config, FeedConfig, FeedParser, FeedStore, Settings}
  alias BlocksterV2.Social
  alias BlocksterV2.Social.XApiClient

  @x_user_id_ttl :timer.hours(24 * 7)

  # ── Client API ──

  def start_link(opts) do
    case BlocksterV2.GlobalSingleton.start_link(__MODULE__, opts) do
      {:ok, pid} -> {:ok, pid}
      {:already_registered, _pid} -> :ignore
    end
  end

  @doc "Force an immediate RSS poll (for admin dashboard)."
  def force_poll do
    case :global.whereis_name(__MODULE__) do
      :undefined -> {:error, :not_running}
      pid -> GenServer.cast(pid, :force_poll_rss)
    end
  end

  @doc "Force an immediate X timeline poll."
  def force_poll_x do
    case :global.whereis_name(__MODULE__) do
      :undefined -> {:error, :not_running}
      pid -> GenServer.cast(pid, :force_poll_x)
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

    Settings.init_cache()

    Process.send_after(self(), :poll_rss, :timer.seconds(30))
    Process.send_after(self(), :poll_x, :timer.seconds(90))

    {:ok, %{
      last_poll: nil,
      last_poll_results: %{},
      last_x_poll: nil,
      last_x_poll_results: %{},
      total_polls: 0,
      total_x_polls: 0,
      x_user_id_cache: %{}
    }}
  end

  @impl true
  def handle_info(:poll_rss, state) do
    state = do_poll_rss(state)
    schedule_rss_poll()
    {:noreply, state}
  end

  def handle_info(:poll_x, state) do
    state = do_poll_x(state)
    schedule_x_poll()
    {:noreply, state}
  end

  @impl true
  def handle_cast(:force_poll_rss, state) do
    Logger.info("[FeedPoller] Force RSS poll triggered")
    {:noreply, do_poll_rss(state)}
  end

  def handle_cast(:force_poll_x, state) do
    Logger.info("[FeedPoller] Force X poll triggered")
    {:noreply, do_poll_x(state)}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  # ── RSS Polling ──

  defp do_poll_rss(state) do
    if Settings.paused?() do
      Logger.info("[FeedPoller] Pipeline is paused, skipping RSS poll")
      state
    else
      feeds = FeedConfig.get_active_rss_feeds()
      Logger.info("[FeedPoller] Polling #{length(feeds)} active RSS feeds")

      results =
        feeds
        |> Task.async_stream(&poll_rss_feed/1, max_concurrency: 5, timeout: 60_000, on_timeout: :kill_task)
        |> Enum.reduce(%{success: 0, failed: 0, new_items: 0}, &reduce_result/2)

      Logger.info(
        "[FeedPoller] RSS poll complete: #{results.success} ok, " <>
        "#{results.failed} failed, #{results.new_items} new items stored"
      )

      %{state |
        last_poll: now(),
        last_poll_results: results,
        total_polls: state.total_polls + 1
      }
    end
  end

  defp poll_rss_feed(%{url: url, source: source, tier: tier}) do
    case Req.get(url, receive_timeout: 15_000, connect_options: [timeout: 10_000]) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        items =
          body
          |> FeedParser.parse()
          |> FeedParser.extract_items()
          |> Enum.map(&to_feed_item(&1, source, tier))

        store_items(source, items)

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

  defp to_feed_item(item, source, tier) do
    %{
      title: item.title,
      url: item.url,
      summary: item.summary,
      source: source,
      tier: Atom.to_string(tier),
      weight: FeedConfig.tier_weight(tier),
      published_at: item.published_at,
      fetched_at: now()
    }
  end

  # ── X Polling ──

  defp do_poll_x(state) do
    cond do
      Settings.paused?() ->
        Logger.info("[FeedPoller] Pipeline is paused, skipping X poll")
        state

      true ->
        feeds = FeedConfig.get_active_x_feeds()

        case get_brand_access_token() do
          nil ->
            Logger.warning("[FeedPoller] No brand X token; skipping #{length(feeds)} X feeds")
            state

          access_token when feeds == [] ->
            _ = access_token
            state

          access_token ->
            Logger.info("[FeedPoller] Polling #{length(feeds)} active X feeds")
            {results, cache} = poll_x_feeds(feeds, access_token, state.x_user_id_cache)

            Logger.info(
              "[FeedPoller] X poll complete: #{results.success} ok, " <>
              "#{results.failed} failed, #{results.new_items} new items stored"
            )

            %{state |
              last_x_poll: now(),
              last_x_poll_results: results,
              total_x_polls: state.total_x_polls + 1,
              x_user_id_cache: cache
            }
        end
    end
  end

  defp poll_x_feeds(feeds, access_token, cache) do
    Enum.reduce(feeds, {%{success: 0, failed: 0, new_items: 0}, cache}, fn feed, {acc, cache_acc} ->
      case poll_x_feed(feed, access_token, cache_acc) do
        {:ok, count, cache_next} ->
          {%{acc | success: acc.success + 1, new_items: acc.new_items + count}, cache_next}

        {:error, reason, cache_next} ->
          Logger.warning("[FeedPoller] #{feed.source} X poll failed: #{inspect(reason)}")
          {%{acc | failed: acc.failed + 1}, cache_next}
      end
    end)
  end

  defp poll_x_feed(%{handle: handle, source: source, tier: tier}, access_token, cache) do
    with {:ok, user_id, cache} <- resolve_user_id(cache, handle, access_token),
         {:ok, tweets} <- XApiClient.get_user_tweets_with_metrics(access_token, user_id, 50) do
      items = Enum.map(tweets, &tweet_to_feed_item(&1, handle, source, tier))

      case store_items(source, items) do
        {:ok, count} -> {:ok, count, cache}
        {:error, reason} -> {:error, reason, cache}
      end
    else
      {:error, reason} -> {:error, reason, cache}
    end
  rescue
    e ->
      Logger.error("[FeedPoller] #{source} X poll crashed: #{Exception.message(e)}")
      {:error, :crashed, cache}
  end

  defp tweet_to_feed_item(tweet, handle, source, tier) do
    id = tweet["id"]
    text = tweet["text"] || ""

    %{
      title: truncate(text, 120),
      url: "https://twitter.com/#{handle}/status/#{id}",
      summary: text,
      source: source,
      tier: Atom.to_string(tier),
      weight: FeedConfig.tier_weight(tier),
      published_at: parse_tweet_time(tweet["created_at"]),
      fetched_at: now()
    }
  end

  defp parse_tweet_time(nil), do: now()
  defp parse_tweet_time(ts) do
    case DateTime.from_iso8601(ts) do
      {:ok, dt, _} -> DateTime.truncate(dt, :second)
      _ -> now()
    end
  end

  defp truncate(text, max) do
    text = text |> String.replace(~r/\s+/, " ") |> String.trim()
    if String.length(text) > max, do: String.slice(text, 0, max - 1) <> "…", else: text
  end

  # ── X user-id cache (handle → {id, resolved_at}) ──

  defp resolve_user_id(cache, handle, access_token) do
    now_ms = System.monotonic_time(:millisecond)

    case Map.get(cache, handle) do
      {id, resolved_at} when now_ms - resolved_at < @x_user_id_ttl ->
        {:ok, id, cache}

      _ ->
        case XApiClient.get_user_by_username(access_token, handle) do
          {:ok, %{"id" => id}} ->
            {:ok, id, Map.put(cache, handle, {id, now_ms})}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp get_brand_access_token do
    case Config.brand_x_user_id() do
      nil ->
        nil

      brand_user_id ->
        case Social.get_x_connection_for_user(brand_user_id) do
          nil -> nil
          connection -> connection.access_token
        end
    end
  end

  # ── Shared ──

  defp store_items(_source, []), do: {:ok, 0}

  defp store_items(source, items) do
    {inserted, _} = FeedStore.store_new_items(items)
    Logger.debug("[FeedPoller] #{source}: #{inserted} new / #{length(items)} total items")
    {:ok, inserted}
  end

  defp reduce_result({:ok, {:ok, count}}, acc),
    do: %{acc | success: acc.success + 1, new_items: acc.new_items + count}

  defp reduce_result({:ok, {:error, _reason}}, acc),
    do: %{acc | failed: acc.failed + 1}

  defp reduce_result({:exit, _reason}, acc),
    do: %{acc | failed: acc.failed + 1}

  defp schedule_rss_poll do
    Process.send_after(self(), :poll_rss, Config.feed_poll_interval())
  end

  defp schedule_x_poll do
    Process.send_after(self(), :poll_x, Config.x_feed_poll_interval())
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
