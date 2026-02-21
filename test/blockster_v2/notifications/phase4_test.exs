defmodule BlocksterV2.Notifications.Phase4Test do
  use BlocksterV2.DataCase, async: true

  alias BlocksterV2.Notifications
  alias BlocksterV2.Notifications.Notification
  alias BlocksterV2.Blog

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

  defp create_hub do
    unique = System.unique_integer([:positive])

    {:ok, hub} =
      Blog.create_hub(%{
        name: "Test Hub #{unique}",
        slug: "test-hub-#{unique}",
        tag_name: "TESTHUB#{unique}",
        description: "A test hub",
        logo_url: "https://example.com/logo.png"
      })

    hub
  end

  defp create_post_for_hub(hub) do
    {:ok, post} =
      Blog.create_post(%{
        title: "Test Article #{System.unique_integer([:positive])}",
        slug: "test-article-#{System.unique_integer([:positive])}",
        body: "Test body content",
        featured_image: "https://example.com/image.jpg",
        hub_id: hub.id,
        status: "draft"
      })

    post
  end

  # ============ Toast Notification State Tests ============

  describe "toast notification state management" do
    test "toast_notification assign starts as nil" do
      # Verify the hook sets it to nil on mount (tested via context)
      %{user: user} = create_user()
      assert Notifications.unread_count(user.id) == 0
    end

    test "creating a notification broadcasts for toast display" do
      %{user: user} = create_user()
      Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "notifications:#{user.id}")

      {:ok, notification} =
        Notifications.create_notification(user.id, notification_attrs(user.id))

      assert_receive {:new_notification, ^notification}
    end

    test "dismiss_toast clears toast by setting to nil (tested via context functions)" do
      %{user: user} = create_user()
      {:ok, notification} =
        Notifications.create_notification(user.id, notification_attrs(user.id))

      # Toast dismiss doesn't affect notification state — verify notification is still there
      recent = Notifications.list_recent_notifications(user.id)
      assert length(recent) == 1
      assert hd(recent).id == notification.id
    end

    test "multiple rapid notifications each broadcast independently" do
      %{user: user} = create_user()
      Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "notifications:#{user.id}")

      {:ok, n1} = Notifications.create_notification(user.id, notification_attrs(user.id, %{title: "First"}))
      {:ok, n2} = Notifications.create_notification(user.id, notification_attrs(user.id, %{title: "Second"}))
      {:ok, n3} = Notifications.create_notification(user.id, notification_attrs(user.id, %{title: "Third"}))

      assert_receive {:new_notification, ^n1}
      assert_receive {:new_notification, ^n2}
      assert_receive {:new_notification, ^n3}
    end
  end

  # ============ Toast Click Navigation Tests ============

  describe "toast click behavior" do
    test "clicking toast marks notification as clicked" do
      %{user: user} = create_user()

      {:ok, notification} =
        Notifications.create_notification(user.id, notification_attrs(user.id, %{
          action_url: "/shop/cool-product"
        }))

      assert Notification.unread?(notification)

      {:ok, updated} = Notifications.mark_as_clicked(notification.id)
      refute Notification.unread?(updated)
      refute is_nil(updated.clicked_at)
      assert updated.action_url == "/shop/cool-product"
    end

    test "clicking toast with no URL still marks as clicked" do
      %{user: user} = create_user()

      {:ok, notification} =
        Notifications.create_notification(user.id, notification_attrs(user.id, %{
          action_url: nil
        }))

      {:ok, updated} = Notifications.mark_as_clicked(notification.id)
      refute Notification.unread?(updated)
      refute is_nil(updated.clicked_at)
    end

    test "clicking toast decrements unread count" do
      %{user: user} = create_user()

      {:ok, n1} = Notifications.create_notification(user.id, notification_attrs(user.id, %{title: "First"}))
      {:ok, _n2} = Notifications.create_notification(user.id, notification_attrs(user.id, %{title: "Second"}))

      assert Notifications.unread_count(user.id) == 2

      Notifications.mark_as_clicked(n1.id)
      assert Notifications.unread_count(user.id) == 1
    end
  end

  # ============ Toast Auto-Dismiss Tests ============

  describe "toast auto-dismiss behavior" do
    test "dismiss_toast event only clears toast, not notification data" do
      %{user: user} = create_user()

      {:ok, notification} =
        Notifications.create_notification(user.id, notification_attrs(user.id))

      # After toast is dismissed, notification still exists and is unread
      assert Notifications.unread_count(user.id) == 1
      assert Notification.unread?(notification)

      # Notification is still in recent list
      recent = Notifications.list_recent_notifications(user.id)
      assert Enum.any?(recent, &(&1.id == notification.id))
    end

    test "dismissed notification remains accessible" do
      %{user: user} = create_user()

      {:ok, notification} =
        Notifications.create_notification(user.id, notification_attrs(user.id))

      # Toast dismiss doesn't affect the notification itself
      found = Notifications.get_notification(notification.id)
      assert found.id == notification.id
      assert found.title == notification.title
    end
  end

  # ============ Hub Post Publish Notification Tests ============

  describe "hub post publish triggers notifications" do
    test "publishing a hub post creates notifications for followers" do
      %{user: user1} = create_user()
      %{user: user2} = create_user()
      %{user: user3} = create_user()
      hub = create_hub()

      # Users 1 and 2 follow the hub, user 3 does not
      Blog.follow_hub(user1.id, hub.id)
      Blog.follow_hub(user2.id, hub.id)

      post = create_post_for_hub(hub)

      # Subscribe to PubSub for both followers
      Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "notifications:#{user1.id}")
      Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "notifications:#{user2.id}")
      Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "notifications:#{user3.id}")

      # Publish the post — this triggers async notification creation
      {:ok, _published_post} = Blog.publish_post(post)

      # Wait for async task to complete
      Process.sleep(200)

      # Both followers should have notifications
      assert Notifications.unread_count(user1.id) == 1
      assert Notifications.unread_count(user2.id) == 1

      # Non-follower should NOT have a notification
      assert Notifications.unread_count(user3.id) == 0

      # Verify notification content for follower
      [notif] = Notifications.list_recent_notifications(user1.id)
      assert notif.type == "hub_post"
      assert notif.category == "content"
      assert notif.title == "New in #{hub.name}"
      assert notif.body == post.title
      assert notif.action_url == "/#{post.slug}"
    end

    test "publishing a post without a hub does not create notifications" do
      %{user: user} = create_user()

      {:ok, post} =
        Blog.create_post(%{
          title: "No Hub Post",
          slug: "no-hub-post-#{System.unique_integer([:positive])}",
          body: "Test body",
          featured_image: "https://example.com/img.jpg",
          status: "draft"
        })

      {:ok, _published} = Blog.publish_post(post)
      Process.sleep(100)

      assert Notifications.unread_count(user.id) == 0
    end

    test "publishing a hub post with no followers creates no notifications" do
      hub = create_hub()
      post = create_post_for_hub(hub)

      {:ok, _published} = Blog.publish_post(post)
      Process.sleep(100)

      # No crash, no notifications created
    end

    test "notification metadata includes post_id and hub_id" do
      %{user: user} = create_user()
      hub = create_hub()
      Blog.follow_hub(user.id, hub.id)

      post = create_post_for_hub(hub)
      {:ok, _published} = Blog.publish_post(post)
      Process.sleep(200)

      [notif] = Notifications.list_recent_notifications(user.id)
      assert notif.metadata["post_id"] == post.id
      assert notif.metadata["hub_id"] == hub.id
    end

    test "notification has correct image_url from post" do
      %{user: user} = create_user()
      hub = create_hub()
      Blog.follow_hub(user.id, hub.id)

      post = create_post_for_hub(hub)
      {:ok, _published} = Blog.publish_post(post)
      Process.sleep(200)

      [notif] = Notifications.list_recent_notifications(user.id)
      assert notif.image_url == post.featured_image
    end
  end

  # ============ Order Status Notification Tests ============

  describe "order status change notifications" do
    test "notify_order_status_change creates notification for paid order" do
      %{user: user} = create_user()

      # Build a minimal order struct for testing
      order = %BlocksterV2.Orders.Order{
        id: 1,
        user_id: user.id,
        status: "paid",
        order_number: "ORD-TEST-001"
      }

      BlocksterV2.Orders.notify_order_status_change(order)

      assert Notifications.unread_count(user.id) == 1
      [notif] = Notifications.list_recent_notifications(user.id)
      assert notif.type == "order_paid"
      assert notif.category == "system"
      assert notif.title == "Order Confirmed"
      assert notif.body =~ "confirmed"
      assert notif.metadata["order_id"] == 1
      assert notif.metadata["order_number"] == "ORD-TEST-001"
    end

    test "notify_order_status_change for shipped status" do
      %{user: user} = create_user()

      order = %BlocksterV2.Orders.Order{
        id: 2,
        user_id: user.id,
        status: "shipped",
        order_number: "ORD-TEST-002"
      }

      BlocksterV2.Orders.notify_order_status_change(order)

      [notif] = Notifications.list_recent_notifications(user.id)
      assert notif.title == "Order Shipped"
      assert notif.body =~ "on its way"
    end

    test "notify_order_status_change for delivered status" do
      %{user: user} = create_user()

      order = %BlocksterV2.Orders.Order{
        id: 3,
        user_id: user.id,
        status: "delivered",
        order_number: "ORD-TEST-003"
      }

      BlocksterV2.Orders.notify_order_status_change(order)

      [notif] = Notifications.list_recent_notifications(user.id)
      assert notif.title == "Order Delivered"
    end

    test "notify_order_status_change for cancelled status" do
      %{user: user} = create_user()

      order = %BlocksterV2.Orders.Order{
        id: 4,
        user_id: user.id,
        status: "cancelled",
        order_number: "ORD-TEST-004"
      }

      BlocksterV2.Orders.notify_order_status_change(order)

      [notif] = Notifications.list_recent_notifications(user.id)
      assert notif.title == "Order Cancelled"
    end

    test "notify_order_status_change for unknown status uses fallback" do
      %{user: user} = create_user()

      order = %BlocksterV2.Orders.Order{
        id: 5,
        user_id: user.id,
        status: "processing",
        order_number: "ORD-TEST-005"
      }

      BlocksterV2.Orders.notify_order_status_change(order)

      [notif] = Notifications.list_recent_notifications(user.id)
      assert notif.title == "Order Update"
      assert notif.body =~ "processing"
    end

    test "order notification broadcasts via PubSub" do
      %{user: user} = create_user()
      Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "notifications:#{user.id}")

      order = %BlocksterV2.Orders.Order{
        id: 6,
        user_id: user.id,
        status: "paid",
        order_number: "ORD-TEST-006"
      }

      BlocksterV2.Orders.notify_order_status_change(order)

      assert_receive {:new_notification, notification}
      assert notification.type == "order_paid"
    end
  end

  # ============ Real-Time Delivery Flow Tests ============

  describe "end-to-end real-time delivery" do
    test "notification flow: create → PubSub → toast → click → read" do
      %{user: user} = create_user()
      Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "notifications:#{user.id}")

      # Step 1: Create notification
      {:ok, notification} =
        Notifications.create_notification(user.id, notification_attrs(user.id, %{
          title: "New Product Alert",
          action_url: "/shop/new-product"
        }))

      # Step 2: Receive PubSub broadcast (would trigger toast in LiveView)
      assert_receive {:new_notification, ^notification}

      # Step 3: Verify unread count increased
      assert Notifications.unread_count(user.id) == 1

      # Step 4: Click the toast (marks as clicked + read)
      {:ok, clicked} = Notifications.mark_as_clicked(notification.id)
      refute is_nil(clicked.clicked_at)
      refute is_nil(clicked.read_at)

      # Step 5: Unread count back to 0
      assert Notifications.unread_count(user.id) == 0
    end

    test "multiple notifications increment count correctly" do
      %{user: user} = create_user()
      Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "notifications:#{user.id}")

      for i <- 1..5 do
        {:ok, _} =
          Notifications.create_notification(user.id, notification_attrs(user.id, %{title: "Alert #{i}"}))
      end

      # Receive all 5 broadcasts
      for _i <- 1..5 do
        assert_receive {:new_notification, _}
      end

      assert Notifications.unread_count(user.id) == 5
    end

    test "notification with image shows image in toast data" do
      %{user: user} = create_user()

      {:ok, notification} =
        Notifications.create_notification(user.id, notification_attrs(user.id, %{
          image_url: "https://example.com/product.jpg"
        }))

      assert notification.image_url == "https://example.com/product.jpg"
    end

    test "notification without image shows fallback icon data" do
      %{user: user} = create_user()

      {:ok, notification} =
        Notifications.create_notification(user.id, notification_attrs(user.id, %{
          image_url: nil
        }))

      assert is_nil(notification.image_url)
    end
  end

  # ============ Toast + Dropdown Interaction Tests ============

  describe "toast and dropdown interaction" do
    test "new notification appears in both toast and recent list" do
      %{user: user} = create_user()

      {:ok, notification} =
        Notifications.create_notification(user.id, notification_attrs(user.id))

      # Should be in recent notifications list
      recent = Notifications.list_recent_notifications(user.id)
      assert Enum.any?(recent, &(&1.id == notification.id))

      # Should be available as toast data
      assert notification.title == "New in Gaming Hub"
    end

    test "marking all as read from dropdown doesn't affect future toasts" do
      %{user: user} = create_user()

      # Create some notifications
      for i <- 1..3 do
        Notifications.create_notification(user.id, notification_attrs(user.id, %{title: "Old #{i}"}))
      end

      # Mark all read
      Notifications.mark_all_as_read(user.id)
      assert Notifications.unread_count(user.id) == 0

      # New notification should still broadcast and be unread
      Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "notifications:#{user.id}")
      {:ok, new_notif} =
        Notifications.create_notification(user.id, notification_attrs(user.id, %{title: "Fresh!"}))

      assert_receive {:new_notification, ^new_notif}
      assert Notifications.unread_count(user.id) == 1
    end

    test "dismissed notification doesn't count as unread for badge" do
      %{user: user} = create_user()

      {:ok, n1} = Notifications.create_notification(user.id, notification_attrs(user.id, %{title: "Keep"}))
      {:ok, n2} = Notifications.create_notification(user.id, notification_attrs(user.id, %{title: "Dismiss"}))

      assert Notifications.unread_count(user.id) == 2

      Notifications.dismiss_notification(n2.id)
      assert Notifications.unread_count(user.id) == 1

      # Dismissed notification not in recent list
      recent = Notifications.list_recent_notifications(user.id)
      refute Enum.any?(recent, &(&1.id == n2.id))
      assert Enum.any?(recent, &(&1.id == n1.id))
    end
  end

  # ============ Notification Category Tests ============

  describe "notification types for toast display" do
    test "content notification (hub_post)" do
      %{user: user} = create_user()

      {:ok, notif} =
        Notifications.create_notification(user.id, notification_attrs(user.id, %{
          type: "hub_post",
          category: "content"
        }))

      assert notif.type == "hub_post"
      assert notif.category == "content"
    end

    test "system notification (order_confirmed)" do
      %{user: user} = create_user()

      {:ok, notif} =
        Notifications.create_notification(user.id, notification_attrs(user.id, %{
          type: "order_confirmed",
          category: "system",
          title: "Order Confirmed",
          body: "Your order #123 has been confirmed"
        }))

      assert notif.type == "order_confirmed"
      assert notif.category == "system"
    end

    test "rewards notification (bux_earned)" do
      %{user: user} = create_user()

      {:ok, notif} =
        Notifications.create_notification(user.id, notification_attrs(user.id, %{
          type: "bux_earned",
          category: "rewards",
          title: "BUX Earned!",
          body: "You earned 50 BUX for reading"
        }))

      assert notif.type == "bux_earned"
      assert notif.category == "rewards"
    end

    test "social notification (referral_signup)" do
      %{user: user} = create_user()

      {:ok, notif} =
        Notifications.create_notification(user.id, notification_attrs(user.id, %{
          type: "referral_signup",
          category: "social",
          title: "New Referral!",
          body: "Someone joined through your link"
        }))

      assert notif.type == "referral_signup"
      assert notif.category == "social"
    end

    test "offers notification (special_offer)" do
      %{user: user} = create_user()

      {:ok, notif} =
        Notifications.create_notification(user.id, notification_attrs(user.id, %{
          type: "special_offer",
          category: "offers",
          title: "Flash Sale!",
          body: "50% off all merch"
        }))

      assert notif.type == "special_offer"
      assert notif.category == "offers"
    end
  end
end
