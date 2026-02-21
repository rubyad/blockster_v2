defmodule BlocksterV2.Notifications.Phase5Test do
  use BlocksterV2.DataCase, async: true

  alias BlocksterV2.Notifications
  # ============ Test Helpers ============

  defp create_user(_context \\ %{}) do
    {:ok, user} =
      BlocksterV2.Accounts.create_user_from_wallet(%{
        wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
        chain_id: 560013
      })

    %{user: user}
  end

  defp notification_attrs(user_id, overrides) do
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

  defp create_notifications(user_id, count, overrides \\ %{}) do
    Enum.map(1..count, fn i ->
      {:ok, n} =
        Notifications.create_notification(
          user_id,
          notification_attrs(user_id, Map.merge(%{title: "Notification #{i}"}, overrides))
        )

      n
    end)
  end

  # ============ Notifications Page - List & Display ============

  describe "notifications page listing" do
    test "lists all notifications for a user" do
      %{user: user} = create_user()
      create_notifications(user.id, 5)

      notifications = Notifications.list_notifications(user.id)
      assert length(notifications) == 5
    end

    test "excludes dismissed notifications from listing" do
      %{user: user} = create_user()
      [n1, n2, n3] = create_notifications(user.id, 3)

      Notifications.dismiss_notification(n2.id)

      notifications = Notifications.list_notifications(user.id)
      assert length(notifications) == 2
      ids = Enum.map(notifications, & &1.id)
      assert n1.id in ids
      assert n3.id in ids
      refute n2.id in ids
    end

    test "returns notifications ordered by newest first" do
      %{user: user} = create_user()
      [n1, n2, n3] = create_notifications(user.id, 3)

      notifications = Notifications.list_notifications(user.id)
      ids = Enum.map(notifications, & &1.id)
      # Newest first (highest id last created)
      assert ids == [n3.id, n2.id, n1.id]
    end

    test "respects limit parameter" do
      %{user: user} = create_user()
      create_notifications(user.id, 10)

      notifications = Notifications.list_notifications(user.id, limit: 3)
      assert length(notifications) == 3
    end

    test "respects offset parameter for pagination" do
      %{user: user} = create_user()
      all_notifications = create_notifications(user.id, 10)

      page1 = Notifications.list_notifications(user.id, limit: 5, offset: 0)
      page2 = Notifications.list_notifications(user.id, limit: 5, offset: 5)

      assert length(page1) == 5
      assert length(page2) == 5

      page1_ids = Enum.map(page1, & &1.id) |> MapSet.new()
      page2_ids = Enum.map(page2, & &1.id) |> MapSet.new()
      assert MapSet.disjoint?(page1_ids, page2_ids)

      all_ids = Enum.map(all_notifications, & &1.id) |> MapSet.new()
      assert MapSet.union(page1_ids, page2_ids) == all_ids
    end

    test "returns empty list when no notifications exist" do
      %{user: user} = create_user()

      notifications = Notifications.list_notifications(user.id)
      assert notifications == []
    end

    test "isolates notifications between users" do
      %{user: user1} = create_user()
      %{user: user2} = create_user()

      create_notifications(user1.id, 3)
      create_notifications(user2.id, 2)

      assert length(Notifications.list_notifications(user1.id)) == 3
      assert length(Notifications.list_notifications(user2.id)) == 2
    end
  end

  # ============ Category Filtering ============

  describe "category filtering" do
    test "filters by content category" do
      %{user: user} = create_user()
      create_notifications(user.id, 2, %{category: "content"})
      create_notifications(user.id, 3, %{category: "offers"})
      create_notifications(user.id, 1, %{category: "system"})

      content = Notifications.list_notifications(user.id, category: "content")
      assert length(content) == 2
      assert Enum.all?(content, &(&1.category == "content"))
    end

    test "filters by offers category" do
      %{user: user} = create_user()
      create_notifications(user.id, 2, %{category: "content"})
      create_notifications(user.id, 3, %{category: "offers", type: "special_offer"})

      offers = Notifications.list_notifications(user.id, category: "offers")
      assert length(offers) == 3
      assert Enum.all?(offers, &(&1.category == "offers"))
    end

    test "filters by social category" do
      %{user: user} = create_user()
      create_notifications(user.id, 2, %{category: "social", type: "referral_prompt"})
      create_notifications(user.id, 3, %{category: "content"})

      social = Notifications.list_notifications(user.id, category: "social")
      assert length(social) == 2
    end

    test "filters by rewards category" do
      %{user: user} = create_user()
      create_notifications(user.id, 4, %{category: "rewards", type: "bux_earned"})
      create_notifications(user.id, 1, %{category: "content"})

      rewards = Notifications.list_notifications(user.id, category: "rewards")
      assert length(rewards) == 4
    end

    test "filters by system category" do
      %{user: user} = create_user()
      create_notifications(user.id, 1, %{category: "system", type: "order_confirmed"})
      create_notifications(user.id, 3, %{category: "content"})

      system = Notifications.list_notifications(user.id, category: "system")
      assert length(system) == 1
    end

    test "returns all categories when no filter" do
      %{user: user} = create_user()
      create_notifications(user.id, 1, %{category: "content"})
      create_notifications(user.id, 1, %{category: "offers", type: "special_offer"})
      create_notifications(user.id, 1, %{category: "social", type: "referral_prompt"})
      create_notifications(user.id, 1, %{category: "rewards", type: "bux_earned"})
      create_notifications(user.id, 1, %{category: "system", type: "order_confirmed"})

      all = Notifications.list_notifications(user.id)
      assert length(all) == 5
    end
  end

  # ============ Read/Unread Filtering ============

  describe "read/unread filtering" do
    test "filters unread notifications" do
      %{user: user} = create_user()
      [n1, _n2, _n3] = create_notifications(user.id, 3)

      Notifications.mark_as_read(n1.id)

      unread = Notifications.list_notifications(user.id, status: :unread)
      assert length(unread) == 2
      assert Enum.all?(unread, &is_nil(&1.read_at))
    end

    test "filters read notifications" do
      %{user: user} = create_user()
      [n1, _n2, _n3] = create_notifications(user.id, 3)

      Notifications.mark_as_read(n1.id)

      read = Notifications.list_notifications(user.id, status: :read)
      assert length(read) == 1
      assert hd(read).id == n1.id
    end

    test "combined category and status filtering" do
      %{user: user} = create_user()
      [content1, _content2] = create_notifications(user.id, 2, %{category: "content"})
      create_notifications(user.id, 2, %{category: "offers", type: "special_offer"})

      Notifications.mark_as_read(content1.id)

      # Unread content only
      unread_content = Notifications.list_notifications(user.id, category: "content", status: :unread)
      assert length(unread_content) == 1

      # All content (read + unread)
      all_content = Notifications.list_notifications(user.id, category: "content")
      assert length(all_content) == 2
    end
  end

  # ============ Mark as Read ============

  describe "mark as read" do
    test "marks a single notification as read" do
      %{user: user} = create_user()
      [n1 | _] = create_notifications(user.id, 3)

      assert is_nil(n1.read_at)
      {:ok, updated} = Notifications.mark_as_read(n1.id)
      refute is_nil(updated.read_at)
    end

    test "mark_as_read is idempotent" do
      %{user: user} = create_user()
      [n1 | _] = create_notifications(user.id, 1)

      {:ok, first_read} = Notifications.mark_as_read(n1.id)
      {:ok, second_read} = Notifications.mark_as_read(n1.id)

      # Should succeed both times
      refute is_nil(first_read.read_at)
      refute is_nil(second_read.read_at)
    end

    test "mark_as_read returns error for nonexistent notification" do
      assert {:error, :not_found} = Notifications.mark_as_read(999_999)
    end

    test "mark_as_clicked also marks as read" do
      %{user: user} = create_user()
      [n1 | _] = create_notifications(user.id, 1)

      {:ok, clicked} = Notifications.mark_as_clicked(n1.id)
      refute is_nil(clicked.read_at)
      refute is_nil(clicked.clicked_at)
    end
  end

  # ============ Bulk Mark All Read ============

  describe "bulk mark all as read" do
    test "marks all unread notifications as read" do
      %{user: user} = create_user()
      create_notifications(user.id, 5)

      assert Notifications.unread_count(user.id) == 5

      {:ok, count} = Notifications.mark_all_as_read(user.id)
      assert count == 5
      assert Notifications.unread_count(user.id) == 0
    end

    test "does not affect already-read notifications" do
      %{user: user} = create_user()
      [n1 | _] = create_notifications(user.id, 3)

      Notifications.mark_as_read(n1.id)
      assert Notifications.unread_count(user.id) == 2

      {:ok, count} = Notifications.mark_all_as_read(user.id)
      assert count == 2
    end

    test "does not affect dismissed notifications" do
      %{user: user} = create_user()
      [n1 | _] = create_notifications(user.id, 3)

      Notifications.dismiss_notification(n1.id)
      {:ok, count} = Notifications.mark_all_as_read(user.id)
      assert count == 2
    end

    test "broadcasts count update to 0 after mark all read" do
      %{user: user} = create_user()
      create_notifications(user.id, 3)

      Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "notifications:#{user.id}")
      Notifications.mark_all_as_read(user.id)

      assert_receive {:notification_count_updated, 0}
    end

    test "returns 0 when no unread notifications exist" do
      %{user: user} = create_user()
      {:ok, count} = Notifications.mark_all_as_read(user.id)
      assert count == 0
    end

    test "isolates mark_all_as_read between users" do
      %{user: user1} = create_user()
      %{user: user2} = create_user()

      create_notifications(user1.id, 3)
      create_notifications(user2.id, 2)

      Notifications.mark_all_as_read(user1.id)

      assert Notifications.unread_count(user1.id) == 0
      assert Notifications.unread_count(user2.id) == 2
    end
  end

  # ============ Infinite Scroll / Pagination ============

  describe "infinite scroll pagination" do
    test "first page returns correct number of results" do
      %{user: user} = create_user()
      create_notifications(user.id, 25)

      page1 = Notifications.list_notifications(user.id, limit: 20, offset: 0)
      assert length(page1) == 20
    end

    test "second page returns remaining results" do
      %{user: user} = create_user()
      create_notifications(user.id, 25)

      page2 = Notifications.list_notifications(user.id, limit: 20, offset: 20)
      assert length(page2) == 5
    end

    test "end_reached detection when results fewer than page size" do
      %{user: user} = create_user()
      create_notifications(user.id, 15)

      page = Notifications.list_notifications(user.id, limit: 20, offset: 0)
      assert length(page) < 20
    end

    test "pagination with category filter" do
      %{user: user} = create_user()
      create_notifications(user.id, 15, %{category: "content"})
      create_notifications(user.id, 10, %{category: "offers", type: "special_offer"})

      page1 = Notifications.list_notifications(user.id, category: "content", limit: 10, offset: 0)
      assert length(page1) == 10

      page2 = Notifications.list_notifications(user.id, category: "content", limit: 10, offset: 10)
      assert length(page2) == 5
    end

    test "pagination preserves ordering" do
      %{user: user} = create_user()
      all = create_notifications(user.id, 10)
      all_ids = all |> Enum.reverse() |> Enum.map(& &1.id)

      page1 = Notifications.list_notifications(user.id, limit: 5, offset: 0)
      page2 = Notifications.list_notifications(user.id, limit: 5, offset: 5)

      combined_ids = Enum.map(page1 ++ page2, & &1.id)
      assert combined_ids == all_ids
    end
  end

  # ============ LiveView Module ============

  describe "NotificationLive.Index module" do
    test "module exists and has expected functions" do
      assert Code.ensure_loaded?(BlocksterV2Web.NotificationLive.Index)
    end

    test "format_time handles nil" do
      assert BlocksterV2Web.NotificationLive.Index.format_time(nil) == ""
    end

    test "format_time handles recent timestamps" do
      now = DateTime.utc_now()

      # Just now (< 60 seconds ago)
      recent = DateTime.add(now, -30, :second)
      assert BlocksterV2Web.NotificationLive.Index.format_time(recent) == "just now"

      # Minutes ago
      minutes_ago = DateTime.add(now, -300, :second)
      assert BlocksterV2Web.NotificationLive.Index.format_time(minutes_ago) == "5m ago"

      # Hours ago
      hours_ago = DateTime.add(now, -7200, :second)
      assert BlocksterV2Web.NotificationLive.Index.format_time(hours_ago) == "2h ago"

      # Days ago
      days_ago = DateTime.add(now, -259200, :second)
      assert BlocksterV2Web.NotificationLive.Index.format_time(days_ago) == "3d ago"
    end

    test "format_time shows date for old notifications" do
      old = ~U[2026-01-15 10:00:00Z]
      result = BlocksterV2Web.NotificationLive.Index.format_time(old)
      assert result == "Jan 15"
    end
  end

  # ============ Unread Count ============

  describe "unread count" do
    test "returns correct count of unread notifications" do
      %{user: user} = create_user()
      create_notifications(user.id, 5)

      assert Notifications.unread_count(user.id) == 5
    end

    test "decrements after marking one as read" do
      %{user: user} = create_user()
      [n1 | _] = create_notifications(user.id, 5)

      Notifications.mark_as_read(n1.id)
      assert Notifications.unread_count(user.id) == 4
    end

    test "excludes dismissed from unread count" do
      %{user: user} = create_user()
      [n1 | _] = create_notifications(user.id, 5)

      Notifications.dismiss_notification(n1.id)
      assert Notifications.unread_count(user.id) == 4
    end

    test "returns 0 for user with no notifications" do
      %{user: user} = create_user()
      assert Notifications.unread_count(user.id) == 0
    end
  end
end
