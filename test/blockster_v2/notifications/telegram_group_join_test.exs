defmodule BlocksterV2.Notifications.TelegramGroupJoinTest do
  use BlocksterV2.DataCase, async: true

  alias BlocksterV2.{Repo, Accounts, Accounts.User, UserEvents}
  alias BlocksterV2.Notifications.UserEvent
  import Ecto.Query

  # ============ Test Helpers ============

  defp create_user(attrs \\ %{}) do
    {:ok, user} =
      Accounts.create_user_from_wallet(%{
        wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
        chain_id: 560013
      })

    if map_size(attrs) > 0 do
      {:ok, user} = Accounts.update_user(user, attrs)
      user
    else
      user
    end
  end

  defp events_for_user(user_id, event_type) do
    Repo.all(
      from e in UserEvent,
        where: e.user_id == ^user_id and e.event_type == ^event_type,
        order_by: [desc: e.inserted_at]
    )
  end

  # ============ UserEvent: telegram_group_joined Event Type ============

  describe "telegram_group_joined event type" do
    test "is a valid event type" do
      assert "telegram_group_joined" in UserEvent.valid_event_types()
    end

    test "is categorized as social" do
      assert UserEvent.categorize("telegram_group_joined") == "social"
    end

    test "telegram_connected is still a valid event type" do
      assert "telegram_connected" in UserEvent.valid_event_types()
    end

    test "telegram_connected is still categorized as social" do
      assert UserEvent.categorize("telegram_connected") == "social"
    end

    test "can be inserted via changeset" do
      user = create_user()

      changeset = UserEvent.changeset(%{
        user_id: user.id,
        event_type: "telegram_group_joined",
        event_category: "social",
        metadata: %{"source" => "webhook"}
      })

      assert changeset.valid?
      {:ok, event} = Repo.insert(changeset)

      assert event.event_type == "telegram_group_joined"
      assert event.event_category == "social"
      assert event.metadata["source"] == "webhook"
    end

    test "can be tracked via UserEvents.track_sync" do
      user = create_user()

      {:ok, event} = UserEvents.track_sync(user.id, "telegram_group_joined", %{
        source: "webhook",
        telegram_user_id: "12345"
      })

      assert event.event_type == "telegram_group_joined"
      assert event.event_category == "social"
    end

    test "is retrievable via UserEvents.get_events" do
      user = create_user()

      {:ok, _} = UserEvents.track_sync(user.id, "telegram_group_joined", %{source: "webhook"})
      {:ok, _} = UserEvents.track_sync(user.id, "telegram_connected", %{})

      events = UserEvents.get_events(user.id, event_type: "telegram_group_joined")
      assert length(events) == 1
      assert hd(events).event_type == "telegram_group_joined"
    end

    test "is countable via UserEvents.count_events" do
      user = create_user()

      {:ok, _} = UserEvents.track_sync(user.id, "telegram_group_joined", %{source: "webhook"})

      count = UserEvents.count_events(user.id, "telegram_group_joined")
      assert count == 1
    end
  end

  # ============ User Schema: telegram_group_joined_at Field ============

  describe "User telegram_group_joined_at field" do
    test "defaults to nil" do
      user = create_user()
      assert user.telegram_group_joined_at == nil
    end

    test "can be set via update_user" do
      user = create_user()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, updated} = Accounts.update_user(user, %{telegram_group_joined_at: now})
      assert updated.telegram_group_joined_at == now
    end

    test "persists through reload" do
      user = create_user()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, _} = Accounts.update_user(user, %{telegram_group_joined_at: now})

      reloaded = Repo.get!(User, user.id)
      assert reloaded.telegram_group_joined_at == now
    end

    test "is independent of telegram_connected_at" do
      user = create_user()
      connected_at = DateTime.utc_now() |> DateTime.add(-3600) |> DateTime.truncate(:second)
      joined_at = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, updated} = Accounts.update_user(user, %{
        telegram_connected_at: connected_at,
        telegram_group_joined_at: joined_at
      })

      assert updated.telegram_connected_at == connected_at
      assert updated.telegram_group_joined_at == joined_at
      refute updated.telegram_connected_at == updated.telegram_group_joined_at
    end

    test "can be set alongside other telegram fields" do
      user = create_user()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, updated} = Accounts.update_user(user, %{
        telegram_user_id: "12345",
        telegram_username: "testuser",
        telegram_connected_at: now,
        telegram_group_joined_at: now
      })

      assert updated.telegram_user_id == "12345"
      assert updated.telegram_username == "testuser"
      assert updated.telegram_connected_at == now
      assert updated.telegram_group_joined_at == now
    end

    test "can be nil when other telegram fields are set" do
      user = create_user(%{
        telegram_user_id: "99999",
        telegram_username: "nogroup",
        telegram_connected_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

      assert user.telegram_user_id == "99999"
      assert user.telegram_group_joined_at == nil
    end
  end

  # ============ All Event Types & Categories Integrity ============

  describe "event type registry integrity" do
    test "all event types have a category mapping" do
      for event_type <- UserEvent.valid_event_types() do
        category = UserEvent.categorize(event_type)
        assert category in UserEvent.valid_categories(),
          "Event type #{event_type} has invalid category: #{category}"
      end
    end

    test "telegram events are in the social category" do
      assert UserEvent.categorize("telegram_connected") == "social"
      assert UserEvent.categorize("telegram_group_joined") == "social"
    end

    test "x_connected is also social (consistency check)" do
      assert UserEvent.categorize("x_connected") == "social"
    end
  end
end
