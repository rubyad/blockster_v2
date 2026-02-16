defmodule BlocksterV2.ContentAutomation.EventRoundupFormatTest do
  use ExUnit.Case, async: true

  alias BlocksterV2.ContentAutomation.EventRoundup

  defp sample_events do
    [
      %{
        name: "Bitcoin Amsterdam",
        event_type: "conference",
        start_date: ~D[2026-03-15],
        end_date: ~D[2026-03-17],
        location: "Amsterdam, Netherlands",
        url: "https://bitcoinamsterdam.com",
        description: "Major Bitcoin conference in Europe",
        tier: "major"
      },
      %{
        name: "Ethereum Denver",
        event_type: "conference",
        start_date: ~D[2026-03-20],
        end_date: nil,
        location: "Denver, CO",
        url: "https://ethdenver.com",
        description: nil,
        tier: "notable"
      },
      %{
        name: "Solana Firedancer Upgrade",
        event_type: "upgrade",
        start_date: ~D[2026-03-18],
        end_date: nil,
        location: nil,
        url: "https://solana.com/firedancer",
        description: "Major validator client upgrade",
        tier: "notable"
      },
      %{
        name: "ARB Token Unlock",
        event_type: "unlock",
        start_date: ~D[2026-03-16],
        end_date: nil,
        location: nil,
        url: nil,
        description: "1.5B ARB tokens unlocking",
        tier: "notable"
      }
    ]
  end

  describe "format_events_for_prompt/1" do
    test "groups events by type (conference, upgrade, unlock)" do
      result = EventRoundup.format_events_for_prompt(sample_events())

      assert result =~ "Conferences & Summits"
      assert result =~ "Protocol Upgrades & Launches"
      assert result =~ "Token Events"
    end

    test "includes event name" do
      result = EventRoundup.format_events_for_prompt(sample_events())

      assert result =~ "Bitcoin Amsterdam"
      assert result =~ "Solana Firedancer Upgrade"
      assert result =~ "ARB Token Unlock"
    end

    test "shows date range for multi-day events (start_date -- end_date)" do
      result = EventRoundup.format_events_for_prompt(sample_events())

      # Bitcoin Amsterdam: March 15 -- March 17, 2026
      assert result =~ "March 15"
      assert result =~ "March 17, 2026"
    end

    test "shows single date for one-day events" do
      result = EventRoundup.format_events_for_prompt(sample_events())

      # Solana upgrade: March 18, 2026 (single date)
      assert result =~ "March 18, 2026"
    end

    test "includes location when present" do
      result = EventRoundup.format_events_for_prompt(sample_events())

      assert result =~ "Amsterdam, Netherlands"
      assert result =~ "Denver, CO"
    end

    test "handles missing location gracefully" do
      # Solana upgrade has nil location - should not crash
      result = EventRoundup.format_events_for_prompt(sample_events())

      # Should still include the event
      assert result =~ "Solana Firedancer Upgrade"
    end

    test "handles missing URL gracefully" do
      # ARB Token Unlock has nil URL
      result = EventRoundup.format_events_for_prompt(sample_events())

      assert result =~ "ARB Token Unlock"
    end

    test "includes URLs when present" do
      result = EventRoundup.format_events_for_prompt(sample_events())

      assert result =~ "https://bitcoinamsterdam.com"
    end

    test "includes description when present" do
      result = EventRoundup.format_events_for_prompt(sample_events())

      assert result =~ "Major Bitcoin conference in Europe"
    end

    test "handles empty event list" do
      result = EventRoundup.format_events_for_prompt([])
      # Should return empty string or minimal output
      assert is_binary(result)
    end

    test "returns empty sections for types with no events" do
      # Only conferences, no regulatory events
      events = [
        %{
          name: "Test Conf",
          event_type: "conference",
          start_date: ~D[2026-03-15],
          end_date: nil,
          location: "NYC",
          url: nil,
          description: nil,
          tier: "notable"
        }
      ]

      result = EventRoundup.format_events_for_prompt(events)

      assert result =~ "Conferences & Summits"
      # Should NOT contain sections for empty types
      refute result =~ "Regulatory & Governance"
    end
  end
end
