defmodule BlocksterV2.Notifications.Phase3Test do
  use BlocksterV2.DataCase, async: true

  alias BlocksterV2.Notifications
  alias BlocksterV2.Notifications.Notification

  # ============ Test Helpers ============

  defp create_user(_context \\ %{}) do
    {:ok, user} =
      BlocksterV2.Accounts.create_user_from_wallet(%{
        wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
        chain_id: 560013
      })

    %{user: user}
  end

  defp notification_attrs(user_id, overrides \\ %{}) do
    Map.merge(
      %{
        user_id: user_id,
        type: "hub_post",
        category: "content",
        title: "New in Gaming Hub",
        body: "Check out the latest article",
        image_url: "https://example.com/image.jpg",
        action_url: "/test-article",
        action_label: "Read Article",
        metadata: %{"post_id" => 1, "hub_id" => 5}
      },
      overrides
    )
  end

  defp create_notifications(user_id, count) do
    for i <- 1..count do
      {:ok, notification} =
        Notifications.create_notification(user_id, notification_attrs(user_id, %{title: "Notification #{i}"}))

      notification
    end
  end

  # ============ NotificationHook Module Existence Tests ============

  describe "NotificationHook module" do
    test "module is loaded and available" do
      # Ensure the module compiles and is available
      assert Code.ensure_loaded?(BlocksterV2Web.NotificationHook)
    end
  end

  # ============ Initial State Tests ============

  describe "initial notification state" do
    test "unread count is 0 for user with no notifications" do
      %{user: user} = create_user()
      assert Notifications.unread_count(user.id) == 0
    end

    test "unread count matches actual unread notifications" do
      %{user: user} = create_user()
      create_notifications(user.id, 5)
      assert Notifications.unread_count(user.id) == 5
    end

    test "recent notifications limited to 10" do
      %{user: user} = create_user()
      create_notifications(user.id, 15)

      recent = Notifications.list_recent_notifications(user.id, 10)
      assert length(recent) == 10
    end

    test "unread count excludes read notifications" do
      %{user: user} = create_user()
      [n1, _n2, n3] = create_notifications(user.id, 3)

      Notifications.mark_as_read(n1.id)
      Notifications.mark_as_read(n3.id)

      assert Notifications.unread_count(user.id) == 1
    end

    test "recent includes both read and unread" do
      %{user: user} = create_user()
      [n1, _n2, _n3] = create_notifications(user.id, 3)

      Notifications.mark_as_read(n1.id)

      recent = Notifications.list_recent_notifications(user.id)
      assert length(recent) == 3
    end
  end

  # ============ PubSub Integration Tests ============

  describe "real-time notification delivery via PubSub" do
    test "new notification broadcasts to user topic" do
      %{user: user} = create_user()
      Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "notifications:#{user.id}")

      {:ok, notification} = Notifications.create_notification(user.id, notification_attrs(user.id))

      assert_receive {:new_notification, ^notification}
    end

    test "mark_all_as_read broadcasts zero count" do
      %{user: user} = create_user()
      create_notifications(user.id, 3)

      Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "notifications:#{user.id}")

      Notifications.mark_all_as_read(user.id)
      assert_receive {:notification_count_updated, 0}
    end

    test "notifications don't leak between users" do
      %{user: user1} = create_user()
      %{user: user2} = create_user()

      Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "notifications:#{user1.id}")

      Notifications.create_notification(user2.id, notification_attrs(user2.id))

      refute_receive {:new_notification, _}, 100
    end

    test "broadcast_count_update sends correct count" do
      %{user: user} = create_user()
      Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "notifications:#{user.id}")

      Notifications.broadcast_count_update(user.id, 42)
      assert_receive {:notification_count_updated, 42}
    end
  end

  # ============ Notification Interaction Flow Tests ============

  describe "notification click/read flow" do
    test "clicking marks as read and clicked" do
      %{user: user} = create_user()
      {:ok, notification} = Notifications.create_notification(user.id, notification_attrs(user.id))

      assert Notification.unread?(notification)

      {:ok, updated} = Notifications.mark_as_clicked(notification.id)
      refute Notification.unread?(updated)
      refute is_nil(updated.clicked_at)
      refute is_nil(updated.read_at)
    end

    test "mark_all_as_read clears all unread" do
      %{user: user} = create_user()
      create_notifications(user.id, 5)

      assert Notifications.unread_count(user.id) == 5

      {:ok, 5} = Notifications.mark_all_as_read(user.id)
      assert Notifications.unread_count(user.id) == 0
    end

    test "new notification after mark_all_as_read is unread" do
      %{user: user} = create_user()
      create_notifications(user.id, 3)

      Notifications.mark_all_as_read(user.id)
      assert Notifications.unread_count(user.id) == 0

      Notifications.create_notification(user.id, notification_attrs(user.id, %{title: "New one"}))
      assert Notifications.unread_count(user.id) == 1
    end

    test "dismissing a notification removes it from lists" do
      %{user: user} = create_user()
      [n1, n2, _n3] = create_notifications(user.id, 3)

      Notifications.dismiss_notification(n2.id)

      recent = Notifications.list_recent_notifications(user.id)
      recent_ids = Enum.map(recent, & &1.id)

      assert n1.id in recent_ids
      refute n2.id in recent_ids
    end
  end

  # ============ Recent Notifications Order Tests ============

  describe "recent notifications ordering" do
    test "most recent first" do
      %{user: user} = create_user()
      notifications = create_notifications(user.id, 5)

      recent = Notifications.list_recent_notifications(user.id, 5)
      recent_ids = Enum.map(recent, & &1.id)
      original_ids = Enum.map(notifications, & &1.id) |> Enum.reverse()

      assert recent_ids == original_ids
    end

    test "respects limit parameter" do
      %{user: user} = create_user()
      create_notifications(user.id, 10)

      assert length(Notifications.list_recent_notifications(user.id, 3)) == 3
      assert length(Notifications.list_recent_notifications(user.id, 7)) == 7
    end
  end

  # ============ Multiple Notification Types Tests ============

  describe "notification types for dropdown display" do
    test "all categories represented" do
      %{user: user} = create_user()

      types = [
        %{type: "hub_post", category: "content", title: "New article"},
        %{type: "special_offer", category: "offers", title: "50% off!"},
        %{type: "referral_signup", category: "social", title: "Friend joined"},
        %{type: "bux_earned", category: "rewards", title: "Earned 100 BUX"},
        %{type: "order_confirmed", category: "system", title: "Order confirmed"}
      ]

      for attrs <- types do
        {:ok, _} = Notifications.create_notification(user.id, notification_attrs(user.id, attrs))
      end

      recent = Notifications.list_recent_notifications(user.id, 10)
      categories = Enum.map(recent, & &1.category) |> Enum.sort()
      assert categories == ["content", "offers", "rewards", "social", "system"]
    end

    test "notifications with images" do
      %{user: user} = create_user()

      {:ok, with_image} =
        Notifications.create_notification(user.id, notification_attrs(user.id, %{
          image_url: "https://example.com/image.jpg"
        }))

      {:ok, without_image} =
        Notifications.create_notification(user.id, notification_attrs(user.id, %{
          image_url: nil
        }))

      assert with_image.image_url == "https://example.com/image.jpg"
      assert is_nil(without_image.image_url)
    end

    test "notifications with action URLs" do
      %{user: user} = create_user()

      {:ok, with_url} =
        Notifications.create_notification(user.id, notification_attrs(user.id, %{
          action_url: "/shop/cool-item",
          action_label: "View Product"
        }))

      assert with_url.action_url == "/shop/cool-item"
      assert with_url.action_label == "View Product"
    end
  end

  # ============ Badge Count Tests ============

  describe "notification badge count" do
    test "badge shows correct count after interactions" do
      %{user: user} = create_user()

      # Start at 0
      assert Notifications.unread_count(user.id) == 0

      # Create 3 notifications
      [n1, n2, _n3] = create_notifications(user.id, 3)
      assert Notifications.unread_count(user.id) == 3

      # Read one
      Notifications.mark_as_read(n1.id)
      assert Notifications.unread_count(user.id) == 2

      # Click one (also marks as read)
      Notifications.mark_as_clicked(n2.id)
      assert Notifications.unread_count(user.id) == 1

      # Mark all read
      Notifications.mark_all_as_read(user.id)
      assert Notifications.unread_count(user.id) == 0

      # New notification brings count back
      Notifications.create_notification(user.id, notification_attrs(user.id))
      assert Notifications.unread_count(user.id) == 1
    end

    test "dismissed notifications don't count as unread" do
      %{user: user} = create_user()
      [_n1, n2, _n3] = create_notifications(user.id, 3)

      Notifications.dismiss_notification(n2.id)
      # Dismissed but unread — should NOT count
      assert Notifications.unread_count(user.id) == 2
    end
  end
end
