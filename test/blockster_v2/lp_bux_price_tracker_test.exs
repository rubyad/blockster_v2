defmodule BlocksterV2.LPBuxPriceTrackerTest do
  use ExUnit.Case, async: false
  alias BlocksterV2.LPBuxPriceTracker

  setup do
    # Ensure Mnesia is started and lp_bux_candles table exists
    :mnesia.start()

    case :mnesia.create_table(:lp_bux_candles, [
      attributes: [:timestamp, :open, :high, :low, :close],
      type: :ordered_set
    ]) do
      {:atomic, :ok} -> :ok
      {:aborted, {:already_exists, _}} -> :ok
    end

    on_exit(fn ->
      :mnesia.clear_table(:lp_bux_candles)
    end)

    :ok
  end

  # Helper: insert a candle directly into Mnesia
  defp insert_candle(timestamp, open, high, low, close) do
    :mnesia.dirty_write({:lp_bux_candles, timestamp, open, high, low, close})
  end

  # ============ Candle Aggregation ============

  describe "get_candles/2" do
    test "returns empty list when no candles exist" do
      assert LPBuxPriceTracker.get_candles(3600, 24) == []
    end

    test "returns raw 5-min candles when timeframe matches base (300s)" do
      now = System.system_time(:second)
      base = div(now, 300) * 300
      insert_candle(base - 600, 1.0, 1.1, 0.9, 1.05)
      insert_candle(base - 300, 1.05, 1.2, 1.0, 1.1)
      insert_candle(base, 1.1, 1.15, 1.05, 1.12)

      candles = LPBuxPriceTracker.get_candles(300, 100)
      assert length(candles) >= 3
      assert Enum.all?(candles, fn c -> Map.has_key?(c, :time) end)
    end

    test "aggregates 5-min candles into 1-hour candles correctly" do
      now = System.system_time(:second)
      hour_start = div(now, 3600) * 3600

      # Insert 12 x 5-min candles within the hour
      for i <- 0..11 do
        ts = hour_start + i * 300
        insert_candle(ts, 1.0 + i * 0.01, 1.0 + i * 0.01 + 0.05, 1.0 + i * 0.01 - 0.02, 1.0 + (i + 1) * 0.01)
      end

      candles = LPBuxPriceTracker.get_candles(3600, 100)
      # Should aggregate into 1 hourly candle
      assert length(candles) >= 1
      hourly = Enum.find(candles, fn c -> c.time == hour_start end)
      assert hourly != nil
      assert hourly.open == 1.0  # First 5-min candle's open
    end

    test "aggregated candles have correct high and low" do
      now = System.system_time(:second)
      hour_start = div(now, 3600) * 3600

      insert_candle(hour_start, 1.0, 1.5, 0.8, 1.2)         # high=1.5, low=0.8
      insert_candle(hour_start + 300, 1.2, 1.8, 0.9, 1.3)   # high=1.8, low=0.9
      insert_candle(hour_start + 600, 1.3, 1.4, 0.7, 1.1)   # high=1.4, low=0.7

      candles = LPBuxPriceTracker.get_candles(3600, 100)
      hourly = Enum.find(candles, fn c -> c.time == hour_start end)
      assert hourly.high == 1.8
      assert hourly.low == 0.7
    end

    test "aggregated candle has correct open (first) and close (last)" do
      now = System.system_time(:second)
      hour_start = div(now, 3600) * 3600

      insert_candle(hour_start, 1.0, 1.5, 0.8, 1.2)
      insert_candle(hour_start + 300, 1.2, 1.8, 0.9, 1.3)
      insert_candle(hour_start + 600, 1.3, 1.4, 0.7, 1.55)

      candles = LPBuxPriceTracker.get_candles(3600, 100)
      hourly = Enum.find(candles, fn c -> c.time == hour_start end)
      assert hourly.open == 1.0   # First sub-candle's open
      assert hourly.close == 1.55 # Last sub-candle's close
    end

    test "candles are sorted by timestamp ascending" do
      now = System.system_time(:second)
      base = div(now, 300) * 300
      insert_candle(base, 1.0, 1.1, 0.9, 1.05)
      insert_candle(base - 300, 1.05, 1.2, 1.0, 1.1)

      candles = LPBuxPriceTracker.get_candles(300, 100)
      timestamps = Enum.map(candles, & &1.time)
      assert timestamps == Enum.sort(timestamps)
    end

    test "respects count parameter to limit data range" do
      now = System.system_time(:second)
      base = div(now, 300) * 300

      # Insert 20 candles
      for i <- 0..19 do
        insert_candle(base - i * 300, 1.0, 1.1, 0.9, 1.0)
      end

      # Request only 5 candles worth of time
      candles = LPBuxPriceTracker.get_candles(300, 5)
      assert length(candles) <= 5
    end
  end

  # ============ Stats ============

  describe "get_stats/0" do
    test "returns high/low for each timeframe" do
      now = System.system_time(:second)
      base = div(now, 300) * 300
      insert_candle(base, 1.0, 1.5, 0.8, 1.2)

      stats = LPBuxPriceTracker.get_stats()
      assert Map.has_key?(stats, :price_1h)
      assert Map.has_key?(stats, :price_24h)
      assert Map.has_key?(stats, :price_7d)
      assert Map.has_key?(stats, :price_30d)
      assert Map.has_key?(stats, :price_all)
    end

    test "returns nil high/low when no data for a timeframe" do
      stats = LPBuxPriceTracker.get_stats()
      assert stats.price_1h == %{high: nil, low: nil}
    end

    test "returns correct high/low from candles within timeframe" do
      now = System.system_time(:second)
      base = div(now, 300) * 300
      insert_candle(base, 1.0, 2.5, 0.5, 1.2)
      insert_candle(base - 300, 1.2, 1.8, 0.9, 1.0)

      stats = LPBuxPriceTracker.get_stats()
      assert stats.price_1h.high == 2.5
      assert stats.price_1h.low == 0.5
    end
  end

  # ============ Mnesia Integration ============

  describe "candle storage" do
    test "candles are ordered by timestamp (ordered_set)" do
      insert_candle(300, 1.0, 1.1, 0.9, 1.05)
      insert_candle(100, 0.9, 1.0, 0.8, 0.95)
      insert_candle(200, 0.95, 1.05, 0.85, 1.0)

      all = :mnesia.dirty_select(:lp_bux_candles, [
        {{:lp_bux_candles, :"$1", :"$2", :"$3", :"$4", :"$5"},
         [],
         [{{:"$1", :"$2", :"$3", :"$4", :"$5"}}]}
      ])

      timestamps = Enum.map(all, &elem(&1, 0))
      assert timestamps == Enum.sort(timestamps)
    end

    test "dirty_select with range filter works" do
      insert_candle(100, 1.0, 1.1, 0.9, 1.0)
      insert_candle(200, 1.0, 1.1, 0.9, 1.0)
      insert_candle(300, 1.0, 1.1, 0.9, 1.0)
      insert_candle(400, 1.0, 1.1, 0.9, 1.0)

      # Select only ts >= 200 and <= 300
      result = :mnesia.dirty_select(:lp_bux_candles, [
        {{:lp_bux_candles, :"$1", :"$2", :"$3", :"$4", :"$5"},
         [{:>=, :"$1", 200}, {:"=<", :"$1", 300}],
         [{{:"$1"}}]}
      ])

      timestamps = Enum.map(result, &elem(&1, 0))
      assert length(timestamps) == 2
      assert 200 in timestamps
      assert 300 in timestamps
    end

    test "overwriting a candle at same timestamp updates it" do
      insert_candle(100, 1.0, 1.1, 0.9, 1.05)
      insert_candle(100, 1.0, 1.5, 0.7, 1.2)  # Overwrite

      [{:lp_bux_candles, 100, _open, high, low, close}] =
        :mnesia.dirty_read(:lp_bux_candles, 100)

      assert high == 1.5
      assert low == 0.7
      assert close == 1.2
    end
  end
end
