defmodule BlocksterV2.ContentAutomation.EventRoundupTest do
  use BlocksterV2.DataCase, async: false

  alias BlocksterV2.ContentAutomation.EventRoundup
  import BlocksterV2.ContentAutomation.Factory

  setup do
    ensure_mnesia_tables()

    # Clean up Mnesia events after each test
    on_exit(fn ->
      try do
        records = :mnesia.dirty_select(:upcoming_events, [
          {{:upcoming_events, :"$1", :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}, [], [:"$1"]}
        ])

        for id <- records do
          :mnesia.dirty_delete(:upcoming_events, id)
        end
      rescue
        _ -> :ok
      end
    end)

    :ok
  end

  describe "add_event/1" do
    test "inserts event into upcoming_events Mnesia table" do
      {:ok, id} = EventRoundup.add_event(%{
        name: "ETH Denver 2026",
        event_type: "conference",
        start_date: "2026-02-28",
        end_date: "2026-03-02",
        location: "Denver, CO",
        url: "https://ethdenver.com",
        description: "Annual Ethereum hackathon and conference"
      })

      assert is_binary(id)

      # Verify it's in Mnesia
      events = EventRoundup.list_events()
      assert Enum.any?(events, &(&1.name == "ETH Denver 2026"))
    end

    test "returns {:ok, event_id}" do
      result = EventRoundup.add_event(%{
        name: "Test Event",
        event_type: "conference",
        start_date: "2026-03-01"
      })

      assert {:ok, id} = result
      assert is_binary(id)
    end

    test "stores all fields" do
      {:ok, _id} = EventRoundup.add_event(%{
        name: "Full Event",
        event_type: "upgrade",
        start_date: "2026-03-15",
        end_date: "2026-03-16",
        location: "Virtual",
        url: "https://example.com/event",
        description: "A test event",
        tier: "headline"
      })

      events = EventRoundup.list_events()
      event = Enum.find(events, &(&1.name == "Full Event"))

      assert event.event_type == "upgrade"
      assert event.start_date == ~D[2026-03-15]
      assert event.end_date == ~D[2026-03-16]
      assert event.location == "Virtual"
      assert event.url == "https://example.com/event"
      assert event.description == "A test event"
      assert event.tier == "headline"
    end
  end

  describe "list_events/1" do
    test "lists all upcoming events sorted by start_date" do
      EventRoundup.add_event(%{name: "Event B", event_type: "conference", start_date: "2026-04-01"})
      EventRoundup.add_event(%{name: "Event A", event_type: "conference", start_date: "2026-03-01"})
      EventRoundup.add_event(%{name: "Event C", event_type: "conference", start_date: "2026-05-01"})

      events = EventRoundup.list_events()
      names = Enum.map(events, & &1.name)

      assert List.first(names) == "Event A"
      assert List.last(names) == "Event C"
    end

    test "supports filtering by date range" do
      EventRoundup.add_event(%{name: "March Event", event_type: "conference", start_date: "2026-03-15"})
      EventRoundup.add_event(%{name: "April Event", event_type: "conference", start_date: "2026-04-15"})
      EventRoundup.add_event(%{name: "May Event", event_type: "conference", start_date: "2026-05-15"})

      events = EventRoundup.list_events(from: ~D[2026-04-01], to: ~D[2026-04-30])
      assert length(events) == 1
      assert hd(events).name == "April Event"
    end

    test "returns empty list when no events exist" do
      events = EventRoundup.list_events()
      assert events == []
    end
  end

  describe "delete_event/1" do
    test "deletes event from Mnesia" do
      {:ok, id} = EventRoundup.add_event(%{name: "To Delete", event_type: "conference", start_date: "2026-03-01"})

      assert :ok = EventRoundup.delete_event(id)

      events = EventRoundup.list_events()
      refute Enum.any?(events, &(&1.id == id))
    end

    test "returns :ok" do
      {:ok, id} = EventRoundup.add_event(%{name: "Test", event_type: "conference"})
      assert :ok = EventRoundup.delete_event(id)
    end
  end

  describe "get_events_for_week/1" do
    test "merges admin-curated events with RSS-sourced events" do
      # Admin event via Mnesia
      today = Date.utc_today()
      future = Date.add(today, 3) |> Date.to_iso8601()
      EventRoundup.add_event(%{name: "Admin Event", event_type: "conference", start_date: future})

      # RSS event via DB (ContentGeneratedTopic with category "events")
      Repo.insert!(%BlocksterV2.ContentAutomation.ContentGeneratedTopic{
        title: "RSS Event: Token Unlock",
        category: "events",
        source_urls: ["https://example.com/event"]
      })

      events = EventRoundup.get_events_for_week(today)

      # Should have both admin and RSS events
      assert Enum.any?(events, &(&1.name == "Admin Event"))
      assert Enum.any?(events, &(&1.name == "RSS Event: Token Unlock"))
    end

    test "deduplicates events with Jaro distance > 0.85" do
      today = Date.utc_today()
      future = Date.add(today, 3) |> Date.to_iso8601()

      # Admin event
      EventRoundup.add_event(%{name: "Ethereum Denver Conference", event_type: "conference", start_date: future})

      # RSS event with very similar name
      Repo.insert!(%BlocksterV2.ContentAutomation.ContentGeneratedTopic{
        title: "Ethereum Denver Conference 2026",
        category: "events",
        source_urls: ["https://example.com/ethdenver"]
      })

      events = EventRoundup.get_events_for_week(today)

      # Should deduplicate — admin event takes priority
      eth_events = Enum.filter(events, fn e -> String.contains?(e.name, "Ethereum Denver") end)
      assert length(eth_events) == 1
      assert hd(eth_events).source == :admin
    end

    test "handles zero admin events gracefully (RSS only)" do
      Repo.insert!(%BlocksterV2.ContentAutomation.ContentGeneratedTopic{
        title: "RSS-Only Event",
        category: "events",
        source_urls: ["https://example.com/rss"]
      })

      events = EventRoundup.get_events_for_week(Date.utc_today())
      assert Enum.any?(events, &(&1.name == "RSS-Only Event"))
    end

    test "handles zero RSS events gracefully (admin only)" do
      today = Date.utc_today()
      future = Date.add(today, 3) |> Date.to_iso8601()
      EventRoundup.add_event(%{name: "Admin Only Event", event_type: "conference", start_date: future})

      events = EventRoundup.get_events_for_week(today)
      assert Enum.any?(events, &(&1.name == "Admin Only Event"))
    end

    test "returns events within next 10 days" do
      today = Date.utc_today()
      within_range = Date.add(today, 5) |> Date.to_iso8601()
      outside_range = Date.add(today, 15) |> Date.to_iso8601()

      EventRoundup.add_event(%{name: "Near Event", event_type: "conference", start_date: within_range})
      EventRoundup.add_event(%{name: "Far Event", event_type: "conference", start_date: outside_range})

      events = EventRoundup.get_events_for_week(today)
      names = Enum.map(events, & &1.name)

      assert "Near Event" in names
      refute "Far Event" in names
    end
  end
end
