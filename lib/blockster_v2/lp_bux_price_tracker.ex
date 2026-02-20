defmodule BlocksterV2.LPBuxPriceTracker do
  @moduledoc """
  GenServer that polls BUXBankroll LP-BUX price every 60 seconds,
  stores 5-minute OHLC candles in Mnesia, and broadcasts via PubSub.

  Global singleton via GlobalSingleton - only one instance runs across the cluster.

  ## Mnesia Table: :lp_bux_candles
  Primary key: timestamp (unix seconds, aligned to 5-min boundaries)
  Fields: timestamp, open, high, low, close
  """

  use GenServer
  require Logger

  @poll_interval 60_000        # Fetch price every 60 seconds
  @candle_interval 300         # 5-minute candles (in seconds)
  @pubsub_topic "lp_bux_price"

  # ============ Client API ============

  def start_link(_opts) do
    case BlocksterV2.GlobalSingleton.start_link(__MODULE__, []) do
      {:ok, pid} ->
        send(pid, :registered)
        {:ok, pid}

      {:already_registered, _pid} ->
        :ignore
    end
  end

  @doc "Get current LP-BUX price from BUX Minter"
  def get_current_price do
    case BlocksterV2.BuxMinter.bux_bankroll_lp_price() do
      {:ok, price_str} -> {:ok, parse_price(price_str)}
      error -> error
    end
  end

  @doc "Get OHLC candles from Mnesia, aggregated to requested timeframe"
  def get_candles(timeframe_seconds, limit \\ 100) do
    now = System.system_time(:second)
    cutoff = now - (timeframe_seconds * limit)

    :mnesia.dirty_select(:lp_bux_candles, [
      {{:lp_bux_candles, :"$1", :"$2", :"$3", :"$4", :"$5"},
       [{:>=, :"$1", cutoff}],
       [{{:"$1", :"$2", :"$3", :"$4", :"$5"}}]}
    ])
    |> Enum.sort_by(&elem(&1, 0))
    |> aggregate_candles(timeframe_seconds)
  end

  @doc "Get price stats for various timeframes"
  def get_stats do
    now = System.system_time(:second)

    %{
      price_1h: get_high_low(now - 3600, now),
      price_24h: get_high_low(now - 86400, now),
      price_7d: get_high_low(now - 604_800, now),
      price_30d: get_high_low(now - 2_592_000, now),
      price_all: get_high_low(0, now)
    }
  end

  @doc "Force refresh price (for manual trigger)"
  def refresh_price do
    GenServer.cast({:global, __MODULE__}, :poll_price)
  end

  # ============ Server Callbacks ============

  @impl true
  def init(_) do
    {:ok, %{current_candle: nil, candle_start: nil, registered: false, mnesia_ready: false}}
  end

  @impl true
  def handle_info(:registered, %{registered: false} = state) do
    Process.send_after(self(), :wait_for_mnesia, 1000)
    {:noreply, %{state | registered: true}}
  end

  def handle_info(:registered, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(:wait_for_mnesia, state) do
    attempts = Map.get(state, :mnesia_wait_attempts, 0)

    if attempts > 30 do
      Logger.error("[LPBuxPriceTracker] Gave up waiting for Mnesia lp_bux_candles table after 60 seconds")
      {:noreply, state}
    else
      case :global.whereis_name(__MODULE__) do
        pid when pid == self() ->
          if table_ready?(:lp_bux_candles) do
            Logger.info("[LPBuxPriceTracker] Mnesia table ready, starting price fetcher")
            send(self(), :poll_price)
            {:noreply, %{state | mnesia_ready: true}}
          else
            Logger.info("[LPBuxPriceTracker] Waiting for Mnesia lp_bux_candles table... (attempt #{attempts + 1})")
            Process.send_after(self(), :wait_for_mnesia, 2000)
            {:noreply, Map.put(state, :mnesia_wait_attempts, attempts + 1)}
          end

        other_pid ->
          Logger.info("[LPBuxPriceTracker] Another instance is now the global owner (#{inspect(other_pid)}), stopping")
          {:stop, :normal, state}
      end
    end
  end

  @impl true
  def handle_info(:poll_price, state) do
    case :global.whereis_name(__MODULE__) do
      pid when pid == self() ->
        state = do_poll_price(state)
        schedule_poll()
        {:noreply, state}

      other_pid ->
        Logger.info("[LPBuxPriceTracker] Another instance is now the global owner (#{inspect(other_pid)}), stopping")
        {:stop, :normal, state}
    end
  end

  @impl true
  def handle_cast(:poll_price, state) do
    case :global.whereis_name(__MODULE__) do
      pid when pid == self() ->
        state = do_poll_price(state)
        {:noreply, state}

      _other_pid ->
        {:noreply, state}
    end
  end

  # ============ Private Functions ============

  defp do_poll_price(state) do
    case BlocksterV2.BuxMinter.bux_bankroll_lp_price() do
      {:ok, price_str} ->
        price = parse_price(price_str)
        state = update_candle(state, price)
        broadcast_price(price, state)
        state

      {:error, reason} ->
        Logger.warning("[LPBuxPriceTracker] Failed to fetch LP price: #{inspect(reason)}")
        state
    end
  end

  defp update_candle(state, price) do
    now = System.system_time(:second)
    candle_start = div(now, @candle_interval) * @candle_interval

    if state.candle_start == candle_start and state.current_candle != nil do
      # Update existing candle
      candle = state.current_candle
      updated = %{candle |
        high: max(candle.high, price),
        low: min(candle.low, price),
        close: price
      }
      %{state | current_candle: updated}
    else
      # Save previous candle and start new one
      if state.current_candle do
        save_candle(state.current_candle)
      end

      new_candle = %{
        timestamp: candle_start,
        open: price,
        high: price,
        low: price,
        close: price
      }
      %{state | current_candle: new_candle, candle_start: candle_start}
    end
  end

  defp save_candle(candle) do
    record = {:lp_bux_candles, candle.timestamp, candle.open, candle.high,
              candle.low, candle.close}
    :mnesia.dirty_write(record)
  end

  defp broadcast_price(price, state) do
    Phoenix.PubSub.broadcast(BlocksterV2.PubSub, @pubsub_topic, {
      :lp_bux_price_updated,
      %{price: price, candle: state.current_candle}
    })
  end

  defp schedule_poll do
    Process.send_after(self(), :poll_price, @poll_interval)
  end

  defp parse_price(price_str) when is_binary(price_str) do
    case Integer.parse(price_str) do
      {price_int, _} -> price_int / 1.0e18
      :error ->
        case Float.parse(price_str) do
          {f, _} -> f
          :error -> 1.0
        end
    end
  end
  defp parse_price(price) when is_number(price), do: price / 1.0e18

  defp get_high_low(from, to) do
    candles = :mnesia.dirty_select(:lp_bux_candles, [
      {{:lp_bux_candles, :"$1", :"$2", :"$3", :"$4", :"$5"},
       [{:>=, :"$1", from}, {:"=<", :"$1", to}],
       [{{:"$3", :"$4"}}]}
    ])

    case candles do
      [] -> %{high: nil, low: nil}
      _ ->
        highs = Enum.map(candles, &elem(&1, 0))
        lows = Enum.map(candles, &elem(&1, 1))
        %{high: Enum.max(highs), low: Enum.min(lows)}
    end
  end

  defp aggregate_candles(base_candles, target_seconds) do
    base_candles
    |> Enum.group_by(fn {ts, _, _, _, _} ->
      div(ts, target_seconds) * target_seconds
    end)
    |> Enum.map(fn {group_ts, candles} ->
      sorted = Enum.sort_by(candles, &elem(&1, 0))
      {_, first_open, _, _, _} = List.first(sorted)
      {_, _, _, _, last_close} = List.last(sorted)
      highs = Enum.map(candles, &elem(&1, 2))
      lows = Enum.map(candles, &elem(&1, 3))

      %{
        time: group_ts,
        open: first_open,
        high: Enum.max(highs),
        low: Enum.min(lows),
        close: last_close
      }
    end)
    |> Enum.sort_by(& &1.time)
  end

  defp table_ready?(table_name) do
    tables = :mnesia.system_info(:tables)

    if table_name in tables do
      case :mnesia.wait_for_tables([table_name], 1000) do
        :ok -> true
        {:timeout, _} -> false
        {:error, _} -> false
      end
    else
      false
    end
  catch
    :exit, _ -> false
  end
end
