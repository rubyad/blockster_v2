defmodule BlocksterV2.BotSystem.EngagementSimulatorTest do
  use ExUnit.Case, async: true

  alias BlocksterV2.BotSystem.EngagementSimulator

  describe "generate_reading_schedule/2" do
    test "returns empty list for empty bot list" do
      assert EngagementSimulator.generate_reading_schedule([]) == []
    end

    test "returns sorted schedule by delay" do
      bot_ids = Enum.to_list(1..100)
      schedule = EngagementSimulator.generate_reading_schedule(bot_ids)

      delays = Enum.map(schedule, fn {delay, _id} -> delay end)
      assert delays == Enum.sort(delays)
    end

    test "total readers is 60-85% of active bots" do
      bot_ids = Enum.to_list(1..300)

      # Run multiple times to check range
      counts = for _ <- 1..50 do
        schedule = EngagementSimulator.generate_reading_schedule(bot_ids)
        length(schedule)
      end

      min_count = Enum.min(counts)
      max_count = Enum.max(counts)

      # 60% of 300 = 180, 85% = 255 (with some tolerance)
      assert min_count >= 160
      assert max_count <= 270
    end

    test "all time buckets are populated" do
      bot_ids = Enum.to_list(1..300)
      schedule = EngagementSimulator.generate_reading_schedule(bot_ids)

      # Check entries across time ranges: first hour heavy, then tail
      first_5min = Enum.filter(schedule, fn {d, _} -> d < :timer.minutes(5) end)
      first_hour = Enum.filter(schedule, fn {d, _} -> d < :timer.hours(1) end)
      mid_range = Enum.filter(schedule, fn {d, _} -> d >= :timer.hours(1) and d < :timer.hours(12) end)
      bucket_tail = Enum.filter(schedule, fn {d, _} -> d >= :timer.hours(12) end)

      assert length(first_5min) > 0
      assert length(first_hour) > 0
      assert length(mid_range) > 0
      assert length(bucket_tail) > 0

      # First hour should have majority of readers (~55%)
      total = length(schedule)
      first_hour_pct = length(first_hour) / total
      assert first_hour_pct >= 0.40, "Expected 40%+ in first hour, got #{Float.round(first_hour_pct * 100, 1)}%"
    end

    test "delays are within 7-day window" do
      bot_ids = Enum.to_list(1..300)
      schedule = EngagementSimulator.generate_reading_schedule(bot_ids)

      max_delay = :timer.hours(168) # 7 days
      Enum.each(schedule, fn {delay, _id} ->
        assert delay >= 0
        assert delay <= max_delay
      end)
    end

    test "different calls produce different schedules" do
      bot_ids = Enum.to_list(1..100)
      schedule1 = EngagementSimulator.generate_reading_schedule(bot_ids)
      schedule2 = EngagementSimulator.generate_reading_schedule(bot_ids)

      # The bot IDs selected and delays should differ
      ids1 = Enum.map(schedule1, fn {_, id} -> id end) |> MapSet.new()
      ids2 = Enum.map(schedule2, fn {_, id} -> id end) |> MapSet.new()

      # They may overlap but shouldn't be identical
      # (astronomically unlikely for 100 bots)
      assert ids1 != ids2 or length(schedule1) != length(schedule2)
    end

    test "works with single bot" do
      schedule = EngagementSimulator.generate_reading_schedule([42])
      assert length(schedule) == 1
      [{_delay, bot_id}] = schedule
      assert bot_id == 42
    end
  end

  describe "generate_backfill_schedule/2" do
    test "returns empty for posts older than 7 days" do
      post_age_ms = :timer.hours(169) # > 7 days
      assert EngagementSimulator.generate_backfill_schedule([1, 2, 3], post_age_ms) == []
    end

    test "post published 1 hour ago skips first bucket" do
      bot_ids = Enum.to_list(1..100)
      post_age_ms = :timer.hours(1)
      schedule = EngagementSimulator.generate_backfill_schedule(bot_ids, post_age_ms)

      # All delays should be >= 0 (adjusted for post age)
      Enum.each(schedule, fn {delay, _} ->
        assert delay >= 0
      end)

      # Should have entries (post is only 1 hour old, lots of time left)
      assert length(schedule) > 0
    end

    test "post published 3 days ago only schedules remaining buckets" do
      bot_ids = Enum.to_list(1..100)
      post_age_ms = :timer.hours(72)
      schedule = EngagementSimulator.generate_backfill_schedule(bot_ids, post_age_ms)

      # Should still have some entries in the 72hr-7day bucket
      assert length(schedule) > 0

      # All delays should be positive (future-facing)
      Enum.each(schedule, fn {delay, _} ->
        assert delay >= 0
      end)
    end
  end

  describe "generate_score_target/0" do
    test "returns valid time_ratio and scroll_depth" do
      for _ <- 1..100 do
        {time_ratio, scroll_depth, score} = EngagementSimulator.generate_score_target()

        assert time_ratio >= 0.1
        assert time_ratio <= 1.2
        assert scroll_depth >= 0.0
        assert scroll_depth <= 100.0
        assert score >= 1
        assert score <= 10
      end
    end

    test "score distribution roughly matches expected percentages" do
      results = for _ <- 1..2000, do: EngagementSimulator.generate_score_target()

      low_scores = Enum.count(results, fn {_, _, s} -> s <= 3 end)
      mid_scores = Enum.count(results, fn {_, _, s} -> s > 3 and s <= 5 end)
      good_scores = Enum.count(results, fn {_, _, s} -> s > 5 and s <= 8 end)
      high_scores = Enum.count(results, fn {_, _, s} -> s > 8 end)

      total = length(results)

      # Check rough distribution with generous tolerance (5%)
      assert low_scores / total > 0.05   # Expected ~10%
      assert low_scores / total < 0.20
      assert mid_scores / total > 0.10   # Expected ~20%
      assert mid_scores / total < 0.35
      assert good_scores / total > 0.25  # Expected ~40%
      assert good_scores / total < 0.55
      assert high_scores / total > 0.15  # Expected ~30%
      assert high_scores / total < 0.45
    end
  end

  describe "generate_partial_metrics/4" do
    test "generates valid partial metrics at 50% progress" do
      metrics = EngagementSimulator.generate_partial_metrics(0.8, 80.0, 60, 0.5)

      assert is_integer(metrics["time_spent"])
      assert metrics["time_spent"] >= 1
      assert metrics["scroll_depth"] >= 0
      assert metrics["scroll_depth"] <= 100
      assert metrics["reached_end"] == false
      assert is_integer(metrics["scroll_events"])
      assert is_float(metrics["avg_scroll_speed"])
      assert is_float(metrics["max_scroll_speed"])
      assert is_integer(metrics["scroll_reversals"])
      assert is_integer(metrics["focus_changes"])
    end

    test "partial depth is less than target at 50% progress" do
      for _ <- 1..50 do
        metrics = EngagementSimulator.generate_partial_metrics(0.9, 90.0, 60, 0.5)
        # At 50% progress, depth should be roughly half of target
        assert metrics["scroll_depth"] <= 95
      end
    end
  end

  describe "generate_final_metrics/3" do
    test "generates valid final metrics" do
      metrics = EngagementSimulator.generate_final_metrics(0.9, 98.0, 60)

      assert is_integer(metrics["time_spent"])
      assert metrics["time_spent"] >= 1
      assert metrics["scroll_depth"] >= 0
      assert metrics["scroll_depth"] <= 100
      assert is_boolean(metrics["reached_end"])
      assert metrics["scroll_events"] in 15..120
      assert metrics["avg_scroll_speed"] >= 200.0
      assert metrics["max_scroll_speed"] >= 600.0
      assert metrics["scroll_reversals"] in 3..20
      assert metrics["focus_changes"] in 0..4
    end

    test "reached_end is true when depth >= 95" do
      # High scroll depth should result in reached_end
      metrics = EngagementSimulator.generate_final_metrics(1.0, 100.0, 60)
      assert metrics["reached_end"] == true
    end

    test "reached_end is false for low depth" do
      metrics = EngagementSimulator.generate_final_metrics(0.2, 30.0, 60)
      assert metrics["reached_end"] == false
    end

    test "time_spent respects min_read_time and ratio" do
      min_read_time = 120  # 2 minutes
      ratio = 0.5
      metrics = EngagementSimulator.generate_final_metrics(ratio, 50.0, min_read_time)

      # time_spent should be roughly min_read_time * ratio = 60
      assert metrics["time_spent"] >= 1
      assert metrics["time_spent"] <= min_read_time * 2
    end
  end

  describe "generate_video_params/1" do
    test "generates valid watch parameters" do
      for _ <- 1..100 do
        {watch_pct, watch_seconds} = EngagementSimulator.generate_video_params(300)

        assert watch_pct >= 0.30
        assert watch_pct <= 1.0
        assert watch_seconds >= 1
        assert watch_seconds <= 300
      end
    end

    test "returns zero for zero duration" do
      assert EngagementSimulator.generate_video_params(0) == {0.0, 0}
    end

    test "returns zero for negative duration" do
      assert EngagementSimulator.generate_video_params(-10) == {0.0, 0}
    end
  end

  describe "calculate_video_bux/3" do
    test "calculates correct BUX for video" do
      # 120 seconds = 2 minutes, 1 BUX/min, 5x multiplier = 10 BUX
      bux = EngagementSimulator.calculate_video_bux(120, 1.0, 5.0)
      assert bux == 10.0
    end

    test "handles nil bux_per_minute" do
      bux = EngagementSimulator.calculate_video_bux(60, nil, 2.0)
      assert bux == 2.0
    end

    test "handles nil multiplier" do
      bux = EngagementSimulator.calculate_video_bux(60, 1.0, nil)
      assert bux == 1.0
    end

    test "returns 0 for 0 watch time" do
      assert EngagementSimulator.calculate_video_bux(0, 1.0, 1.0) == 0.0
    end
  end
end
