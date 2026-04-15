defmodule BlocksterV2.Widgets.TrackerStatusTest do
  use ExUnit.Case, async: true

  alias BlocksterV2.Widgets.TrackerStatus

  describe "errors/0" do
    test "returns a map with the 3 tracker keys even when no trackers are running" do
      # In the test env the GlobalSingleton-wrapped trackers are not started,
      # so every get_last_error/0 hop falls through the catch clause and
      # returns nil. Errors map shape is still well-formed.
      errors = TrackerStatus.errors()

      assert is_map(errors)
      assert Map.has_key?(errors, :fs_feed)
      assert Map.has_key?(errors, :rt_bots)
      assert Map.has_key?(errors, :rt_chart)
    end
  end

  describe "any_errors?/1" do
    test "false when every slot is nil" do
      refute TrackerStatus.any_errors?(%{fs_feed: nil, rt_bots: nil, rt_chart: nil})
    end

    test "true when at least one slot has a value" do
      assert TrackerStatus.any_errors?(%{fs_feed: :timeout, rt_bots: nil, rt_chart: nil})
      assert TrackerStatus.any_errors?(%{fs_feed: nil, rt_bots: :nxdomain, rt_chart: nil})
    end

    test "false for non-map input" do
      refute TrackerStatus.any_errors?(nil)
      refute TrackerStatus.any_errors?(:anything)
    end
  end

  describe "widget_error?/2 — family routing" do
    @errors_fs_only %{fs_feed: :timeout, rt_bots: nil, rt_chart: nil}
    @errors_rt_bots_only %{fs_feed: nil, rt_bots: :nxdomain, rt_chart: nil}
    @errors_rt_chart_only %{fs_feed: nil, rt_bots: nil, rt_chart: :bad_status}

    test "fs_* widgets follow the fs_feed slot" do
      for type <- ~w(fs_skyscraper fs_ticker fs_hero_portrait fs_hero_landscape fs_square_compact fs_sidebar_tile) do
        assert TrackerStatus.widget_error?(type, @errors_fs_only),
               "expected #{type} to surface fs_feed error"

        refute TrackerStatus.widget_error?(type, @errors_rt_bots_only)
      end
    end

    test "rt_skyscraper / rt_ticker / rt_leaderboard_inline follow rt_bots" do
      for type <- ~w(rt_skyscraper rt_ticker rt_leaderboard_inline) do
        assert TrackerStatus.widget_error?(type, @errors_rt_bots_only)
        refute TrackerStatus.widget_error?(type, @errors_fs_only)
        # rt_chart error alone shouldn't affect these (they don't use chart data)
        refute TrackerStatus.widget_error?(type, @errors_rt_chart_only)
      end
    end

    test "rt_chart_* / rt_full_card / rt_square_compact / rt_sidebar_tile follow rt_bots OR rt_chart" do
      for type <- ~w(rt_chart_landscape rt_chart_portrait rt_full_card rt_square_compact rt_sidebar_tile) do
        assert TrackerStatus.widget_error?(type, @errors_rt_bots_only)
        assert TrackerStatus.widget_error?(type, @errors_rt_chart_only)
        refute TrackerStatus.widget_error?(type, @errors_fs_only)
      end
    end

    test "unknown widget_type returns false" do
      refute TrackerStatus.widget_error?("something_else", @errors_rt_bots_only)
      refute TrackerStatus.widget_error?(nil, @errors_rt_bots_only)
    end
  end
end
