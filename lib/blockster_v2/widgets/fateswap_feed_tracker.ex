defmodule BlocksterV2.Widgets.FateSwapFeedTracker do
  @moduledoc """
  Polls `GET /api/feed/recent?limit=20` on the FateSwap sister app every 3s,
  caches the trade list in Mnesia, broadcasts on `"widgets:fateswap:feed"`
  when the snapshot changes, and re-runs `WidgetSelector.pick_fs/2` for every
  active FateSwap widget banner.

  Runs as a `GlobalSingleton` in production — one tracker per cluster. All
  nodes read from the local Mnesia cache (`:widget_fs_feed_cache`) via
  `get_trades/0`, so reads stay cheap and don't cross nodes.

  Tests bypass the global registration path by calling
  `GenServer.start_link/3` directly and passing `:req_options` so the HTTP
  call goes through a `Req.Test` stub.
  """

  use GenServer
  require Logger

  alias BlocksterV2.Widgets.WidgetSelector

  @table :widget_fs_feed_cache
  @topic "widgets:fateswap:feed"
  @selection_topic_prefix "widgets:selection:"
  @default_interval :timer.seconds(3)
  @default_timeout 5_000
  @default_path "/api/feed/recent?limit=20"

  # ── Client API ────────────────────────────────────────────────────────────

  @doc """
  Starts the tracker as a `GlobalSingleton`. Used by the application
  supervision tree in production.
  """
  def start_link(opts \\ []) do
    case BlocksterV2.GlobalSingleton.start_link(__MODULE__, opts) do
      {:ok, pid} ->
        send(pid, :registered)
        {:ok, pid}

      {:already_registered, _pid} ->
        :ignore
    end
  end

  @doc """
  Returns the latest cached list of trades (string-keyed maps) or `[]`.

  Reads from local Mnesia — safe to call from any node.
  """
  def get_trades do
    case dirty_read() do
      %{trades: trades} -> trades
      _ -> []
    end
  end

  @doc """
  Returns the trade with the biggest `profit_lamports` among the cached
  settled+filled orders, or `nil`.
  """
  def get_top_profit_order do
    WidgetSelector.pick_fs(get_trades(), %{"selection" => "biggest_profit"})
    |> lookup_trade()
  end

  @doc """
  Returns the trade with the biggest `discount_pct` among the cached settled
  orders, or `nil`.
  """
  def get_top_discount_order do
    WidgetSelector.pick_fs(get_trades(), %{"selection" => "biggest_discount"})
    |> lookup_trade()
  end

  @doc """
  Returns the cached trade whose `"id"` matches `order_id`, or `nil`.
  """
  def get_order(order_id) when is_binary(order_id) do
    Enum.find(get_trades(), fn t -> t["id"] == order_id end)
  end

  def get_order(_), do: nil

  @doc "Returns the unix timestamp of the last successful poll, or `nil`."
  def last_fetched_at do
    case dirty_read() do
      %{fetched_at: at} -> at
      _ -> nil
    end
  end

  @doc """
  Returns the last poll error reason, or `nil` if the last poll
  succeeded (or the tracker isn't running). Safe to call from any
  node — falls back to `nil` when the GenServer is absent so widget
  renders degrade gracefully instead of crashing.
  """
  def get_last_error(server \\ __MODULE__) do
    try do
      GenServer.call(server, :get_last_error, 100)
    catch
      :exit, _ -> nil
    end
  end

  @doc false
  def poll_now(server \\ __MODULE__) do
    GenServer.call(server, :poll_now, 10_000)
  end

  # ── GenServer ─────────────────────────────────────────────────────────────

  @impl true
  def init(opts) do
    state = %{
      registered: false,
      interval: Keyword.get(opts, :interval, widgets_config(:fateswap_poll_interval_ms, @default_interval)),
      base_url: Keyword.get(opts, :base_url, widgets_config(:fateswap_base_url, "https://fateswap.fly.dev")),
      path: Keyword.get(opts, :path, @default_path),
      req_options: Keyword.get(opts, :req_options, []),
      timeout: Keyword.get(opts, :timeout, widgets_config(:http_timeout_ms, @default_timeout)),
      auto_start: Keyword.get(opts, :auto_start, true),
      last_error: nil,
      last_fetched_at: nil,
      last_trade_ids: nil
    }

    # For GlobalSingleton path, we wait for :registered. For direct local
    # start_link (tests, non-singleton starts), kick off immediately.
    if opts[:name] not in [nil, {:via, :global, __MODULE__}, {:global, __MODULE__}] or
         opts[:skip_global] do
      send(self(), :registered)
    end

    {:ok, state}
  end

  @impl true
  def handle_info(:registered, %{registered: true} = state), do: {:noreply, state}

  def handle_info(:registered, state) do
    Logger.info("[FateSwapFeedTracker] Started — polling every #{state.interval}ms")
    if state.auto_start, do: schedule_first_poll(state.interval)
    {:noreply, %{state | registered: true}}
  end

  def handle_info(:poll, state) do
    state = do_poll(state)
    if state.auto_start, do: schedule(state.interval)
    {:noreply, state}
  end

  @impl true
  def handle_call(:poll_now, _from, state) do
    state = do_poll(state)
    {:reply, :ok, state}
  end

  def handle_call(:get_state, _from, state), do: {:reply, state, state}

  def handle_call(:get_last_error, _from, state), do: {:reply, state.last_error, state}

  # ── Polling logic ─────────────────────────────────────────────────────────

  defp schedule_first_poll(interval) do
    Process.send_after(self(), :poll, min(interval, 500))
  end

  defp schedule(interval) do
    Process.send_after(self(), :poll, interval)
  end

  defp do_poll(state) do
    case fetch_trades(state) do
      {:ok, trades} ->
        on_success(trades, state)

      {:error, reason} ->
        Logger.warning("[FateSwapFeedTracker] Poll failed: #{inspect(reason)}")
        %{state | last_error: reason}
    end
  end

  defp fetch_trades(state) do
    url = String.trim_trailing(state.base_url, "/") <> state.path

    req_opts =
      [
        receive_timeout: state.timeout,
        connect_options: [timeout: state.timeout],
        retry: false
      ] ++ state.req_options

    try do
      case Req.get(url, req_opts) do
        {:ok, %Req.Response{status: 200, body: %{"trades" => trades}}} when is_list(trades) ->
          {:ok, trades}

        {:ok, %Req.Response{status: 200, body: trades}} when is_list(trades) ->
          {:ok, trades}

        {:ok, %Req.Response{status: status, body: body}} ->
          {:error, {:bad_status, status, body}}

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      e -> {:error, {:exception, Exception.message(e)}}
    end
  end

  defp on_success(trades, state) do
    fetched_at = System.system_time(:second)
    :ok = write_cache(trades, fetched_at)

    ids = trade_ids(trades)
    changed? = ids != state.last_trade_ids

    if changed? do
      Phoenix.PubSub.broadcast(BlocksterV2.PubSub, @topic, {:fs_trades, trades})
      refresh_selections(trades)
    end

    %{state | last_fetched_at: fetched_at, last_error: nil, last_trade_ids: ids}
  end

  defp trade_ids(trades) do
    trades
    |> Enum.map(fn
      %{"id" => id} -> id
      _ -> nil
    end)
  end

  # Re-run WidgetSelector for every active FateSwap widget banner and
  # broadcast `:selection_changed` per banner whose subject moved.
  defp refresh_selections(trades) do
    banners = WidgetSelector.list_banners(:fs)

    for banner <- banners do
      subject = WidgetSelector.pick_fs(trades, banner)
      previous = read_selection(banner.id)

      if subject != previous do
        write_selection(banner.id, banner.widget_type, subject)

        Phoenix.PubSub.broadcast(
          BlocksterV2.PubSub,
          @selection_topic_prefix <> Integer.to_string(banner.id),
          {:selection_changed, banner.id, subject}
        )
      end
    end
  rescue
    e -> Logger.warning("[FateSwapFeedTracker] Selector refresh failed: #{inspect(e)}")
  end

  # ── Mnesia helpers ────────────────────────────────────────────────────────

  defp write_cache(trades, fetched_at) do
    :mnesia.dirty_write({@table, :singleton, trades, fetched_at})
    :ok
  rescue
    e ->
      Logger.warning("[FateSwapFeedTracker] Mnesia write failed: #{inspect(e)}")
      :ok
  catch
    :exit, reason ->
      Logger.warning("[FateSwapFeedTracker] Mnesia write crashed: #{inspect(reason)}")
      :ok
  end

  defp dirty_read do
    case :mnesia.dirty_read(@table, :singleton) do
      [{@table, :singleton, trades, fetched_at}] ->
        %{trades: trades, fetched_at: fetched_at}

      _ ->
        nil
    end
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  defp write_selection(banner_id, widget_type, subject) do
    :mnesia.dirty_write({:widget_selections, banner_id, widget_type, subject, System.system_time(:second)})
    :ok
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  defp read_selection(banner_id) do
    case :mnesia.dirty_read(:widget_selections, banner_id) do
      [{:widget_selections, ^banner_id, _type, subject, _}] -> subject
      _ -> nil
    end
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  defp lookup_trade(nil), do: nil
  defp lookup_trade(order_id), do: get_order(order_id)

  defp widgets_config(key, default) do
    Application.get_env(:blockster_v2, :widgets, [])
    |> Keyword.get(key, default)
  end
end
