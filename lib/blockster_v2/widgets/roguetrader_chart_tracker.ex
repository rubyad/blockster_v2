defmodule BlocksterV2.Widgets.RogueTraderChartTracker do
  @moduledoc """
  Polls `GET /api/bots/:id/chart?tf=:tf` on the RogueTrader sister app for
  every known bot × every supported timeframe, staggered evenly across a
  60 second window. Caches each series in the `:widget_rt_chart_cache`
  Mnesia table keyed by `{bot_id, tf}` and broadcasts per-series on
  `"widgets:roguetrader:chart:\#{bot_id}_\#{tf}"`.

  The chart endpoint is 1–2 orders of magnitude heavier than `/api/bots`
  (300+ price points per series × 5 timeframes × 30 bots ≈ 45k points),
  so the default 60s cadence keeps sister-app load reasonable. Live widgets
  overlay the last-known snapshot price from `RogueTraderBotsTracker` on
  top of the chart so the trailing edge never looks stale.
  """

  use GenServer
  require Logger

  alias BlocksterV2.Widgets.RogueTraderBotsTracker

  @table :widget_rt_chart_cache
  @topic_prefix "widgets:roguetrader:chart:"
  @timeframes ~w(1h 6h 24h 48h 7d)
  @default_interval :timer.seconds(60)
  @default_timeout 5_000

  # ── Client API ────────────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    case BlocksterV2.GlobalSingleton.start_link(__MODULE__, opts) do
      {:ok, pid} ->
        send(pid, :registered)
        {:ok, pid}

      {:already_registered, _pid} ->
        :ignore
    end
  end

  @doc "Returns cached `[%{time, value}]` points for `{bot_id, tf}`, or `[]`."
  def get_series(bot_id, tf) when is_binary(bot_id) and is_binary(tf) do
    case dirty_read(bot_id, tf) do
      %{points: points} -> points
      _ -> []
    end
  end

  def get_series(_, _), do: []

  @doc "Returns the cached `change_pct` for `{bot_id, tf}`, or `nil`."
  def get_change_pct(bot_id, tf) do
    case dirty_read(bot_id, tf) do
      %{change_pct: v} when is_number(v) -> v
      _ -> nil
    end
  end

  @doc "Returns `%{high: h, low: l}` for `{bot_id, tf}`, or `nil`."
  def get_high_low(bot_id, tf) do
    case dirty_read(bot_id, tf) do
      %{high: h, low: l} when is_number(h) and is_number(l) -> %{high: h, low: l}
      _ -> nil
    end
  end

  @doc "Returns the list of timeframes the tracker polls."
  def timeframes, do: @timeframes

  @doc """
  Forces a single poll of `{bot_id, tf}` and waits for it to complete.

  Test-only — production polling is driven by the internal scheduler.
  """
  def poll_now(server \\ __MODULE__, bot_id, tf) do
    GenServer.call(server, {:poll_now, bot_id, tf}, 10_000)
  end

  # ── GenServer ─────────────────────────────────────────────────────────────

  @impl true
  def init(opts) do
    bot_ids = Keyword.get(opts, :bot_ids, nil)

    state = %{
      registered: false,
      interval:
        Keyword.get(opts, :interval, widgets_config(:roguetrader_chart_poll_interval_ms, @default_interval)),
      base_url:
        Keyword.get(opts, :base_url, widgets_config(:roguetrader_base_url, "https://roguetrader-v2.fly.dev")),
      req_options: Keyword.get(opts, :req_options, []),
      timeout: Keyword.get(opts, :timeout, widgets_config(:http_timeout_ms, @default_timeout)),
      auto_start: Keyword.get(opts, :auto_start, true),
      override_bot_ids: bot_ids,
      queue: [],
      cursor: 0,
      last_error: nil,
      last_fetched_at: nil,
      errors_by_series: %{}
    }

    if opts[:name] not in [nil, {:via, :global, __MODULE__}, {:global, __MODULE__}] or
         opts[:skip_global] do
      send(self(), :registered)
    end

    {:ok, state}
  end

  @impl true
  def handle_info(:registered, %{registered: true} = state), do: {:noreply, state}

  def handle_info(:registered, state) do
    Logger.info("[RogueTraderChartTracker] Started — sweep every #{state.interval}ms")
    if state.auto_start, do: Process.send_after(self(), :rebuild_queue, 500)
    {:noreply, %{state | registered: true}}
  end

  def handle_info(:rebuild_queue, state) do
    queue = build_queue(state)
    state = %{state | queue: queue, cursor: 0}

    if queue == [] do
      # No bots cached yet — retry in 5s
      if state.auto_start, do: Process.send_after(self(), :rebuild_queue, 5_000)
      {:noreply, state}
    else
      if state.auto_start, do: Process.send_after(self(), :tick, 0)
      {:noreply, state}
    end
  end

  def handle_info(:tick, state) do
    state = do_tick(state)
    {:noreply, state}
  end

  @impl true
  def handle_call({:poll_now, bot_id, tf}, _from, state) do
    state = do_poll_series(bot_id, tf, state)
    {:reply, :ok, state}
  end

  def handle_call(:get_state, _from, state), do: {:reply, state, state}

  # ── Scheduling ────────────────────────────────────────────────────────────

  defp do_tick(%{queue: []} = state) do
    if state.auto_start, do: Process.send_after(self(), :rebuild_queue, 5_000)
    state
  end

  defp do_tick(state) do
    {bot_id, tf} = Enum.at(state.queue, state.cursor)
    state = do_poll_series(bot_id, tf, state)

    next_cursor = state.cursor + 1
    queue_len = length(state.queue)

    cond do
      next_cursor >= queue_len ->
        # Sweep done — rebuild (bot list may have changed) and start again
        if state.auto_start do
          Process.send_after(self(), :rebuild_queue, state.interval |> max(1))
        end

        %{state | cursor: 0}

      true ->
        delay = max(div(state.interval, queue_len), 50)
        if state.auto_start, do: Process.send_after(self(), :tick, delay)
        %{state | cursor: next_cursor}
    end
  end

  defp build_queue(%{override_bot_ids: [_ | _] = ids}) do
    for id <- ids, tf <- @timeframes, do: {id, tf}
  end

  defp build_queue(_state) do
    bots = RogueTraderBotsTracker.get_bots()

    for bot <- bots,
        id = bot["slug"] || to_string(bot["bot_id"] || ""),
        id != "",
        tf <- @timeframes do
      {id, tf}
    end
  end

  # ── HTTP + cache ──────────────────────────────────────────────────────────

  defp do_poll_series(bot_id, tf, state) do
    case fetch_series(bot_id, tf, state) do
      {:ok, data} ->
        fetched_at = System.system_time(:second)
        write_cache(bot_id, tf, data, fetched_at)

        Phoenix.PubSub.broadcast(
          BlocksterV2.PubSub,
          @topic_prefix <> "#{bot_id}_#{tf}",
          {:rt_chart, bot_id, tf, data[:points]}
        )

        %{
          state
          | last_fetched_at: fetched_at,
            last_error: nil,
            errors_by_series: Map.delete(state.errors_by_series, {bot_id, tf})
        }

      {:error, reason} ->
        Logger.warning(
          "[RogueTraderChartTracker] #{bot_id}/#{tf} poll failed: #{inspect(reason)}"
        )

        %{
          state
          | last_error: reason,
            errors_by_series: Map.put(state.errors_by_series, {bot_id, tf}, reason)
        }
    end
  end

  defp fetch_series(bot_id, tf, state) do
    url = String.trim_trailing(state.base_url, "/") <> "/api/bots/#{bot_id}/chart?tf=#{tf}"

    req_opts =
      [
        receive_timeout: state.timeout,
        connect_options: [timeout: state.timeout],
        retry: false
      ] ++ state.req_options

    try do
      case Req.get(url, req_opts) do
        {:ok, %Req.Response{status: 200, body: body}} when is_map(body) ->
          {:ok, normalize(body)}

        {:ok, %Req.Response{status: status, body: body}} ->
          {:error, {:bad_status, status, body}}

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      e -> {:error, {:exception, Exception.message(e)}}
    end
  end

  defp normalize(body) do
    %{
      points: Map.get(body, "points", []),
      high: Map.get(body, "high"),
      low: Map.get(body, "low"),
      change_pct: Map.get(body, "change_pct") || Map.get(body, "change_percent")
    }
  end

  defp write_cache(bot_id, tf, data, fetched_at) do
    :mnesia.dirty_write({
      @table,
      {bot_id, tf},
      bot_id,
      tf,
      Map.get(data, :points, []),
      Map.get(data, :high),
      Map.get(data, :low),
      Map.get(data, :change_pct),
      fetched_at
    })

    :ok
  rescue
    e ->
      Logger.warning("[RogueTraderChartTracker] Mnesia write failed: #{inspect(e)}")
      :ok
  catch
    :exit, reason ->
      Logger.warning("[RogueTraderChartTracker] Mnesia write crashed: #{inspect(reason)}")
      :ok
  end

  defp dirty_read(bot_id, tf) do
    case :mnesia.dirty_read(@table, {bot_id, tf}) do
      [{@table, {^bot_id, ^tf}, _bot, _tf, points, high, low, change, fetched_at}] ->
        %{points: points, high: high, low: low, change_pct: change, fetched_at: fetched_at}

      _ ->
        nil
    end
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  defp widgets_config(key, default) do
    Application.get_env(:blockster_v2, :widgets, [])
    |> Keyword.get(key, default)
  end
end
