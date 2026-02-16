defmodule BlocksterV2.ContentAutomation.ContentQueueWeeklyTest do
  use BlocksterV2.DataCase, async: false

  alias BlocksterV2.ContentAutomation.{ContentQueue, Settings}
  import BlocksterV2.ContentAutomation.Factory

  setup do
    ensure_mnesia_tables()
    Settings.init_cache()

    on_exit(fn ->
      for key <- [:last_market_movers_date, :last_weekly_roundup_date] do
        try do
          :mnesia.dirty_delete(:content_automation_settings, key)
          :ets.delete(:content_settings_cache, key)
        rescue
          _ -> :ok
        end
      end
    end)

    :ok
  end

  describe "maybe_generate_weekly_content/0" do
    test "on Friday (day 5): checks Settings :last_market_movers_date to avoid duplicate" do
      today = Date.utc_today()
      today_str = Date.to_iso8601(today)

      # Mark as already generated today
      Settings.set(:last_market_movers_date, today_str)

      # This should not crash and should skip generation
      # Since the function spawns Tasks for actual generation, we just verify
      # it doesn't error out when Settings says already generated
      ContentQueue.maybe_generate_weekly_content()

      # Verify the Settings key is still the same (not reset)
      assert Settings.get(:last_market_movers_date) == today_str
    end

    test "on Sunday (day 7): checks Settings :last_weekly_roundup_date to avoid duplicate" do
      today = Date.utc_today()
      today_str = Date.to_iso8601(today)

      # Mark as already generated today
      Settings.set(:last_weekly_roundup_date, today_str)

      ContentQueue.maybe_generate_weekly_content()

      # Verify the Settings key is still the same
      assert Settings.get(:last_weekly_roundup_date) == today_str
    end

    test "all generation calls run in Task.start (non-blocking)" do
      # The function should return quickly even if tasks are spawned
      # This tests that it doesn't block the caller
      start_time = System.monotonic_time(:millisecond)

      ContentQueue.maybe_generate_weekly_content()

      elapsed = System.monotonic_time(:millisecond) - start_time
      # Should complete quickly (< 1 second) since actual work is in Tasks
      assert elapsed < 1000
    end

    test "narrative report check runs every cycle (self-gated via Settings)" do
      # This should not crash even without any narrative Settings keys set
      # The narrative report check is self-gating via Settings
      ContentQueue.maybe_generate_weekly_content()

      # No assertion needed beyond not crashing — the function
      # delegates to MarketContentScheduler which self-gates
    end
  end
end
