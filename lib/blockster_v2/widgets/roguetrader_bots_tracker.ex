defmodule BlocksterV2.Widgets.RogueTraderBotsTracker do
  @moduledoc """
  Polls `GET /api/bots` on the RogueTrader sister app every 10s, caches the
  bot snapshot list in Mnesia, broadcasts on `"widgets:roguetrader:bots"`
  when the snapshot changes, and re-runs `WidgetSelector.pick_rt/2` for
  every active RogueTrader widget banner.

  Runs as a `GlobalSingleton` in production. All nodes read from the local
  Mnesia cache (`:widget_rt_bots_cache`) via `get_bots/0`, so reads stay
  cheap and don't cross nodes.
  """

  use GenServer
  require Logger

  alias BlocksterV2.Widgets.WidgetSelector

  @table :widget_rt_bots_cache
  @topic "widgets:roguetrader:bots"
  @selection_topic_prefix "widgets:selection:"
  @default_interval :timer.seconds(10)
  @default_timeout 5_000
  @default_path "/api/bots"

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

  @doc "Returns the cached bot list (string-keyed maps), or `[]`."
  def get_bots do
    case dirty_read() do
      %{bots: bots} -> bots
      _ -> []
    end
  end

  @doc "Returns the cached bot by slug or bot_id, or `nil`."
  def get_bot(id) when is_binary(id) do
    Enum.find(get_bots(), fn b ->
      b["slug"] == id or to_string(b["bot_id"]) == id
    end)
  end

  def get_bot(_), do: nil

  @doc "Returns the bot with the largest positive change % across all timeframes, or `nil`."
  def get_top_gainer do
    case WidgetSelector.pick_rt(get_bots(), %{"selection" => "biggest_gainer"}) do
      {bot_id, _tf} -> get_bot(bot_id)
      _ -> nil
    end
  end

  @doc "Returns the bot with the largest absolute change % across all timeframes, or `nil`."
  def get_top_mover do
    case WidgetSelector.pick_rt(get_bots(), %{"selection" => "biggest_mover"}) do
      {bot_id, _tf} -> get_bot(bot_id)
      _ -> nil
    end
  end

  @doc "Returns the bot with the largest `sol_balance`, or `nil`."
  def get_top_aum do
    case WidgetSelector.pick_rt(get_bots(), %{"selection" => "highest_aum"}) do
      {bot_id, _tf} -> get_bot(bot_id)
      _ -> nil
    end
  end

  @doc "Returns the unix timestamp of the last successful poll, or `nil`."
  def last_fetched_at do
    case dirty_read() do
      %{fetched_at: at} -> at
      _ -> nil
    end
  end

  @doc """
  Returns the last poll error reason, or `nil`. Safe to call from any
  node — returns `nil` when the GenServer isn't running so widgets
  never crash on an absent tracker.
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
      interval:
        Keyword.get(opts, :interval, widgets_config(:roguetrader_bots_poll_interval_ms, @default_interval)),
      base_url:
        Keyword.get(opts, :base_url, widgets_config(:roguetrader_base_url, "https://roguetrader-v2.fly.dev")),
      path: Keyword.get(opts, :path, @default_path),
      req_options: Keyword.get(opts, :req_options, []),
      timeout: Keyword.get(opts, :timeout, widgets_config(:http_timeout_ms, @default_timeout)),
      auto_start: Keyword.get(opts, :auto_start, true),
      last_error: nil,
      last_fetched_at: nil,
      last_snapshot_key: nil
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
    Logger.info("[RogueTraderBotsTracker] Started — polling every #{state.interval}ms")
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

  defp schedule_first_poll(interval), do: Process.send_after(self(), :poll, min(interval, 500))
  defp schedule(interval), do: Process.send_after(self(), :poll, interval)

  defp do_poll(state) do
    case fetch_bots(state) do
      {:ok, bots} ->
        on_success(bots, state)

      {:error, reason} ->
        Logger.warning("[RogueTraderBotsTracker] Poll failed: #{inspect(reason)}")
        %{state | last_error: reason}
    end
  end

  defp fetch_bots(state) do
    url = String.trim_trailing(state.base_url, "/") <> state.path

    req_opts =
      [
        receive_timeout: state.timeout,
        connect_options: [timeout: state.timeout],
        retry: false
      ] ++ state.req_options

    try do
      case Req.get(url, req_opts) do
        {:ok, %Req.Response{status: 200, body: %{"bots" => bots}}} when is_list(bots) ->
          {:ok, bots}

        {:ok, %Req.Response{status: 200, body: bots}} when is_list(bots) ->
          {:ok, bots}

        {:ok, %Req.Response{status: status, body: body}} ->
          {:error, {:bad_status, status, body}}

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      e -> {:error, {:exception, Exception.message(e)}}
    end
  end

  defp on_success(bots, state) do
    fetched_at = System.system_time(:second)
    :ok = write_cache(bots, fetched_at)

    key = snapshot_key(bots)
    changed? = key != state.last_snapshot_key

    if changed? do
      Phoenix.PubSub.broadcast(BlocksterV2.PubSub, @topic, {:rt_bots, bots})
      refresh_selections(bots)
    end

    %{state | last_fetched_at: fetched_at, last_error: nil, last_snapshot_key: key}
  end

  # Identity of a snapshot for change detection: (bot_id, lp_price, rank).
  # Any price or rank change triggers a broadcast.
  defp snapshot_key(bots) do
    Enum.map(bots, fn b ->
      {b["bot_id"] || b["slug"], b["lp_price"], b["rank"]}
    end)
  end

  defp refresh_selections(bots) do
    banners = WidgetSelector.list_banners(:rt)

    for banner <- banners do
      subject = WidgetSelector.pick_rt(bots, banner)
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
    e -> Logger.warning("[RogueTraderBotsTracker] Selector refresh failed: #{inspect(e)}")
  end

  # ── Mnesia helpers ────────────────────────────────────────────────────────

  defp write_cache(bots, fetched_at) do
    :mnesia.dirty_write({@table, :singleton, bots, fetched_at})
    :ok
  rescue
    e ->
      Logger.warning("[RogueTraderBotsTracker] Mnesia write failed: #{inspect(e)}")
      :ok
  catch
    :exit, reason ->
      Logger.warning("[RogueTraderBotsTracker] Mnesia write crashed: #{inspect(reason)}")
      :ok
  end

  defp dirty_read do
    case :mnesia.dirty_read(@table, :singleton) do
      [{@table, :singleton, bots, fetched_at}] ->
        %{bots: bots, fetched_at: fetched_at}

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

  defp widgets_config(key, default) do
    Application.get_env(:blockster_v2, :widgets, [])
    |> Keyword.get(key, default)
  end
end
