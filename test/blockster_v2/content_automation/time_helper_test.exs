defmodule BlocksterV2.ContentAutomation.TimeHelperTest do
  use ExUnit.Case, async: true

  alias BlocksterV2.ContentAutomation.TimeHelper

  setup_all do
    Calendar.put_time_zone_database(Tz.TimeZoneDatabase)
    :ok
  end

  describe "est_to_utc/1" do
    test "converts EST (winter) to UTC: 2:00 PM EST -> 7:00 PM UTC (+5h)" do
      # January is EST (UTC-5)
      naive = ~N[2026-01-15 14:00:00]
      result = TimeHelper.est_to_utc(naive)

      assert result.hour == 19
      assert result.zone_abbr == "UTC"
    end

    test "converts EDT (summer) to UTC: 2:00 PM EDT -> 6:00 PM UTC (+4h)" do
      # July is EDT (UTC-4)
      naive = ~N[2026-07-15 14:00:00]
      result = TimeHelper.est_to_utc(naive)

      assert result.hour == 18
      assert result.zone_abbr == "UTC"
    end

    test "handles midnight EST -> 5:00 AM UTC" do
      naive = ~N[2026-01-15 00:00:00]
      result = TimeHelper.est_to_utc(naive)

      assert result.hour == 5
      assert result.day == 15
    end

    test "handles midnight EDT -> 4:00 AM UTC" do
      naive = ~N[2026-07-15 00:00:00]
      result = TimeHelper.est_to_utc(naive)

      assert result.hour == 4
      assert result.day == 15
    end
  end

  describe "utc_to_est/1" do
    test "converts UTC to EST (winter): 7:00 PM UTC -> 2:00 PM EST" do
      utc = DateTime.new!(~D[2026-01-15], ~T[19:00:00], "Etc/UTC")
      result = TimeHelper.utc_to_est(utc)

      assert result.hour == 14
      assert result.zone_abbr == "EST"
    end

    test "converts UTC to EDT (summer): 6:00 PM UTC -> 2:00 PM EDT" do
      utc = DateTime.new!(~D[2026-07-15], ~T[18:00:00], "Etc/UTC")
      result = TimeHelper.utc_to_est(utc)

      assert result.hour == 14
      assert result.zone_abbr == "EDT"
    end

    test "round-trips correctly with est_to_utc" do
      naive = ~N[2026-02-15 10:30:00]
      result = naive |> TimeHelper.est_to_utc() |> TimeHelper.utc_to_est()

      assert result.hour == 10
      assert result.minute == 30
    end
  end

  describe "format_for_input/1" do
    test "produces YYYY-MM-DDTHH:MM format for datetime-local input" do
      utc = DateTime.new!(~D[2026-01-15], ~T[19:30:00], "Etc/UTC")
      result = TimeHelper.format_for_input(utc)

      # 19:30 UTC = 14:30 EST
      assert result == "2026-01-15T14:30"
    end

    test "converts from UTC to EST before formatting" do
      utc = DateTime.new!(~D[2026-07-15], ~T[18:45:00], "Etc/UTC")
      result = TimeHelper.format_for_input(utc)

      # 18:45 UTC = 14:45 EDT
      assert result == "2026-07-15T14:45"
    end

    test "returns nil for nil input" do
      assert TimeHelper.format_for_input(nil) == nil
    end
  end

  describe "format_display/1" do
    test "produces human-readable format with EST suffix" do
      utc = DateTime.new!(~D[2026-02-15], ~T[19:30:00], "Etc/UTC")
      result = TimeHelper.format_display(utc)

      # Feb is EST
      assert result =~ "Feb 15, 2026"
      assert result =~ "02:30 PM"
      assert result =~ "EST"
    end

    test "shows EDT suffix during daylight saving time (April-October)" do
      utc = DateTime.new!(~D[2026-06-15], ~T[18:30:00], "Etc/UTC")
      result = TimeHelper.format_display(utc)

      assert result =~ "EDT"
    end

    test "shows EST suffix outside daylight saving time (November-March)" do
      utc = DateTime.new!(~D[2026-12-15], ~T[19:30:00], "Etc/UTC")
      result = TimeHelper.format_display(utc)

      assert result =~ "EST"
    end

    test "returns nil for nil input" do
      assert TimeHelper.format_display(nil) == nil
    end
  end

  describe "DST boundary tests" do
    test "2026 spring forward: times near March 8 DST transition" do
      # Before spring forward (still EST): March 8, 2026 01:00 EST = 06:00 UTC
      pre_dst = ~N[2026-03-08 01:00:00]
      result = TimeHelper.est_to_utc(pre_dst)
      assert result.hour == 6

      # After spring forward (EDT): March 8, 2026 03:00 EDT = 07:00 UTC
      post_dst = ~N[2026-03-08 03:00:00]
      result = TimeHelper.est_to_utc(post_dst)
      assert result.hour == 7
    end

    test "2026 fall back: times near November 1 DST transition" do
      # After fall back (back to EST): November 1, 2026 03:00 EST = 08:00 UTC
      post_fallback = ~N[2026-11-01 03:00:00]
      result = TimeHelper.est_to_utc(post_fallback)
      assert result.hour == 8
    end
  end
end
