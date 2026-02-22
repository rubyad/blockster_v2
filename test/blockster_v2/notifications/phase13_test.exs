defmodule BlocksterV2.Notifications.Phase13Test do
  use BlocksterV2.DataCase, async: true

  alias BlocksterV2.UserEvents
  alias BlocksterV2.Notifications.UserEvent

  # ============ Test Helpers ============

  defp create_user(_context \\ %{}) do
    {:ok, user} =
      BlocksterV2.Accounts.create_user_from_wallet(%{
        wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
        chain_id: 560013
      })

    %{user: user}
  end

  defp create_user_pair(_context \\ %{}) do
    %{user: user1} = create_user()
    %{user: user2} = create_user()
    %{user1: user1, user2: user2}
  end

  # ============ UserEvent Schema Tests ============

  describe "UserEvent schema" do
    test "valid changeset with required fields" do
      %{user: user} = create_user()

      changeset =
        UserEvent.changeset(%{
          user_id: user.id,
          event_type: "article_view",
          event_category: "content"
        })

      assert changeset.valid?
    end

    test "valid changeset with all fields" do
      %{user: user} = create_user()

      changeset =
        UserEvent.changeset(%{
          user_id: user.id,
          event_type: "product_view",
          event_category: "shop",
          target_type: "product",
          target_id: "42",
          metadata: %{"price" => "29.99"},
          session_id: "sess_abc123",
          source: "email",
          referrer: "campaign_123"
        })

      assert changeset.valid?
    end

    test "requires user_id, event_type, event_category" do
      changeset = UserEvent.changeset(%{})
      refute changeset.valid?
      assert errors_on(changeset) |> Map.has_key?(:user_id)
      assert errors_on(changeset) |> Map.has_key?(:event_type)
      assert errors_on(changeset) |> Map.has_key?(:event_category)
    end

    test "validates event_type inclusion" do
      %{user: user} = create_user()

      changeset =
        UserEvent.changeset(%{
          user_id: user.id,
          event_type: "invalid_type",
          event_category: "content"
        })

      refute changeset.valid?
      assert errors_on(changeset) |> Map.has_key?(:event_type)
    end

    test "validates event_category inclusion" do
      %{user: user} = create_user()

      changeset =
        UserEvent.changeset(%{
          user_id: user.id,
          event_type: "article_view",
          event_category: "invalid_cat"
        })

      refute changeset.valid?
      assert errors_on(changeset) |> Map.has_key?(:event_category)
    end

    test "categorize/1 maps event types to categories" do
      assert UserEvent.categorize("article_view") == "content"
      assert UserEvent.categorize("product_view") == "shop"
      assert UserEvent.categorize("hub_subscribe") == "social"
      assert UserEvent.categorize("bux_earned") == "engagement"
      assert UserEvent.categorize("daily_login") == "navigation"
      assert UserEvent.categorize("email_opened") == "notification"
      assert UserEvent.categorize("unknown_event") == "navigation"
    end

    test "valid_event_types returns all types" do
      types = UserEvent.valid_event_types()
      assert is_list(types)
      assert "article_view" in types
      assert "purchase_complete" in types
      assert "game_played" in types
      assert length(types) > 30
    end
  end

  # ============ UserEvents Tracking Tests ============

  describe "UserEvents.track_sync/3" do
    test "creates event with required fields" do
      %{user: user} = create_user()

      {:ok, event} = UserEvents.track_sync(user.id, "article_view", %{
        target_type: "post",
        target_id: 42
      })

      assert event.user_id == user.id
      assert event.event_type == "article_view"
      assert event.event_category == "content"
      assert event.target_type == "post"
      assert event.target_id == "42"
    end

    test "auto-categorizes events" do
      %{user: user} = create_user()

      {:ok, event} = UserEvents.track_sync(user.id, "purchase_complete", %{})
      assert event.event_category == "shop"

      {:ok, event2} = UserEvents.track_sync(user.id, "game_played", %{})
      assert event2.event_category == "engagement"
    end

    test "stores metadata correctly" do
      %{user: user} = create_user()

      {:ok, event} = UserEvents.track_sync(user.id, "article_read_complete", %{
        target_type: "post",
        target_id: 10,
        read_duration_ms: 45000,
        scroll_depth_pct: 85,
        engagement_score: 7.5
      })

      assert event.metadata["read_duration_ms"] == 45000
      assert event.metadata["scroll_depth_pct"] == 85
      assert event.metadata["engagement_score"] == 7.5
      # target_type and target_id are extracted, not in metadata
      refute Map.has_key?(event.metadata, "target_type")
    end

    test "handles string keys in metadata" do
      %{user: user} = create_user()

      {:ok, event} = UserEvents.track_sync(user.id, "product_view", %{
        "target_type" => "product",
        "target_id" => "99",
        "price" => "29.99"
      })

      assert event.target_type == "product"
      assert event.target_id == "99"
      assert event.metadata["price"] == "29.99"
    end

    test "stores session_id, source, referrer" do
      %{user: user} = create_user()

      {:ok, event} = UserEvents.track_sync(user.id, "daily_login", %{
        session_id: "sess_xyz",
        source: "email",
        referrer: "campaign_42"
      })

      assert event.session_id == "sess_xyz"
      assert event.source == "email"
      assert event.referrer == "campaign_42"
    end

    test "rejects invalid event types" do
      %{user: user} = create_user()

      {:error, changeset} = UserEvents.track_sync(user.id, "totally_invalid", %{})
      refute changeset.valid?
    end
  end

  describe "UserEvents.track/3 (async)" do
    test "returns :ok immediately" do
      %{user: user} = create_user()
      result = UserEvents.track(user.id, "daily_login")
      assert result == :ok
    end
  end

  # ============ Event Querying Tests ============

  describe "UserEvents.get_events/2" do
    test "returns events within time range" do
      %{user: user} = create_user()
      {:ok, _} = UserEvents.track_sync(user.id, "article_view", %{target_id: 1})
      {:ok, _} = UserEvents.track_sync(user.id, "article_view", %{target_id: 2})
      {:ok, _} = UserEvents.track_sync(user.id, "product_view", %{target_id: 3})

      events = UserEvents.get_events(user.id, days: 7)
      assert length(events) == 3
    end

    test "filters by event_type" do
      %{user: user} = create_user()
      {:ok, _} = UserEvents.track_sync(user.id, "article_view", %{})
      {:ok, _} = UserEvents.track_sync(user.id, "product_view", %{})

      events = UserEvents.get_events(user.id, event_type: "article_view")
      assert length(events) == 1
      assert hd(events).event_type == "article_view"
    end

    test "orders by most recent first" do
      %{user: user} = create_user()
      {:ok, e1} = UserEvents.track_sync(user.id, "article_view", %{target_id: 1})
      {:ok, e2} = UserEvents.track_sync(user.id, "article_view", %{target_id: 2})

      events = UserEvents.get_events(user.id, days: 7)
      assert hd(events).id == e2.id
    end

    test "isolates events between users" do
      %{user1: user1, user2: user2} = create_user_pair()
      {:ok, _} = UserEvents.track_sync(user1.id, "article_view", %{})
      {:ok, _} = UserEvents.track_sync(user2.id, "product_view", %{})

      events1 = UserEvents.get_events(user1.id, days: 7)
      assert length(events1) == 1
      assert hd(events1).event_type == "article_view"
    end
  end

  describe "UserEvents.count_events/3" do
    test "counts events of a specific type" do
      %{user: user} = create_user()
      {:ok, _} = UserEvents.track_sync(user.id, "article_view", %{})
      {:ok, _} = UserEvents.track_sync(user.id, "article_view", %{})
      {:ok, _} = UserEvents.track_sync(user.id, "product_view", %{})

      assert UserEvents.count_events(user.id, "article_view") == 2
      assert UserEvents.count_events(user.id, "product_view") == 1
      assert UserEvents.count_events(user.id, "game_played") == 0
    end
  end

  describe "UserEvents.get_last_event/2" do
    test "returns the most recent event of a type" do
      %{user: user} = create_user()
      {:ok, _} = UserEvents.track_sync(user.id, "article_view", %{target_id: 1})
      {:ok, e2} = UserEvents.track_sync(user.id, "article_view", %{target_id: 2})

      last = UserEvents.get_last_event(user.id, "article_view")
      assert last.id == e2.id
    end

    test "returns nil when no events exist" do
      %{user: user} = create_user()
      assert UserEvents.get_last_event(user.id, "article_view") == nil
    end
  end

  describe "UserEvents.event_summary/2" do
    test "returns event type counts as map" do
      %{user: user} = create_user()
      {:ok, _} = UserEvents.track_sync(user.id, "article_view", %{})
      {:ok, _} = UserEvents.track_sync(user.id, "article_view", %{})
      {:ok, _} = UserEvents.track_sync(user.id, "product_view", %{})

      summary = UserEvents.event_summary(user.id)
      assert summary["article_view"] == 2
      assert summary["product_view"] == 1
    end
  end

  # ============ User Isolation Tests ============

  describe "user isolation" do
    test "events are scoped to individual users" do
      %{user1: u1, user2: u2} = create_user_pair()

      UserEvents.track_sync(u1.id, "article_view", %{target_id: 1})
      UserEvents.track_sync(u1.id, "article_view", %{target_id: 2})
      UserEvents.track_sync(u2.id, "product_view", %{target_id: 3})

      assert UserEvents.count_events(u1.id, "article_view") == 2
      assert UserEvents.count_events(u1.id, "product_view") == 0
      assert UserEvents.count_events(u2.id, "product_view") == 1
      assert UserEvents.count_events(u2.id, "article_view") == 0
    end

  end

  # ============ Batch Tracking Tests ============

  describe "UserEvents.track_batch/1" do
    test "returns :ok for batch tracking" do
      %{user: user} = create_user()

      events = [
        %{user_id: user.id, event_type: "article_view", metadata: %{}},
        %{user_id: user.id, event_type: "product_view", metadata: %{}}
      ]

      assert :ok = UserEvents.track_batch(events)
    end
  end

  # ============ Edge Cases ============

  describe "edge cases" do
    test "handles nil target_id gracefully" do
      %{user: user} = create_user()
      {:ok, event} = UserEvents.track_sync(user.id, "daily_login", %{})
      assert event.target_id == nil
    end

    test "handles numeric target_id conversion" do
      %{user: user} = create_user()
      {:ok, event} = UserEvents.track_sync(user.id, "article_view", %{target_id: 42})
      assert event.target_id == "42"
    end

    test "empty events list for new user" do
      %{user: user} = create_user()
      events = UserEvents.get_events(user.id)
      assert events == []
    end

    test "event_summary returns empty map for new user" do
      %{user: user} = create_user()
      summary = UserEvents.event_summary(user.id)
      assert summary == %{}
    end

    test "get_event_types returns empty for new user" do
      %{user: user} = create_user()
      types = UserEvents.get_event_types(user.id)
      assert types == []
    end

  end
end
