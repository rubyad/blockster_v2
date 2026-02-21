defmodule BlocksterV2.Notifications.Phase1Test do
  use BlocksterV2.DataCase, async: true

  alias BlocksterV2.Notifications
  alias BlocksterV2.Notifications.{Notification, NotificationPreference, Campaign, EmailLog}

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

  # ============ Notification Schema Tests ============

  describe "Notification schema" do
    test "valid changeset with all fields" do
      %{user: user} = create_user()
      attrs = notification_attrs(user.id)
      changeset = Notification.changeset(%Notification{}, attrs)
      assert changeset.valid?
    end

    test "requires user_id, type, category, title" do
      changeset = Notification.changeset(%Notification{}, %{})
      refute changeset.valid?
      assert errors_on(changeset) |> Map.has_key?(:user_id)
      assert errors_on(changeset) |> Map.has_key?(:type)
      assert errors_on(changeset) |> Map.has_key?(:category)
      assert errors_on(changeset) |> Map.has_key?(:title)
    end

    test "validates type inclusion" do
      %{user: user} = create_user()

      changeset =
        Notification.changeset(%Notification{}, %{
          user_id: user.id,
          type: "invalid_type",
          category: "content",
          title: "Test"
        })

      refute changeset.valid?
      assert errors_on(changeset) |> Map.has_key?(:type)
    end

    test "validates category inclusion" do
      %{user: user} = create_user()

      changeset =
        Notification.changeset(%Notification{}, %{
          user_id: user.id,
          type: "hub_post",
          category: "invalid_category",
          title: "Test"
        })

      refute changeset.valid?
      assert errors_on(changeset) |> Map.has_key?(:category)
    end

    test "all valid types accepted" do
      %{user: user} = create_user()

      valid_types = ~w(new_article hub_post hub_event content_recommendation weekly_roundup
        special_offer flash_sale shop_new_product shop_restock price_drop cart_abandonment
        referral_prompt referral_signup referral_reward hub_milestone
        bux_earned bux_milestone reward_summary multiplier_upgrade game_settlement
        order_confirmed order_shipped order_delivered welcome account_security maintenance)

      for type <- valid_types do
        changeset =
          Notification.changeset(%Notification{}, %{
            user_id: user.id,
            type: type,
            category: "content",
            title: "Test #{type}"
          })

        assert changeset.valid?, "Expected type #{type} to be valid"
      end
    end

    test "all valid categories accepted" do
      %{user: user} = create_user()

      for category <- ~w(content offers social rewards system) do
        changeset =
          Notification.changeset(%Notification{}, %{
            user_id: user.id,
            type: "hub_post",
            category: category,
            title: "Test"
          })

        assert changeset.valid?, "Expected category #{category} to be valid"
      end
    end

    test "read_changeset sets read_at" do
      %{user: user} = create_user()
      {:ok, notification} = Notifications.create_notification(user.id, notification_attrs(user.id))
      assert is_nil(notification.read_at)

      changeset = Notification.read_changeset(notification)
      assert changeset.changes[:read_at]
    end

    test "click_changeset sets clicked_at and read_at" do
      %{user: user} = create_user()
      {:ok, notification} = Notifications.create_notification(user.id, notification_attrs(user.id))

      changeset = Notification.click_changeset(notification)
      assert changeset.changes[:clicked_at]
      assert changeset.changes[:read_at]
    end

    test "unread?/1 returns true for unread notifications" do
      assert Notification.unread?(%Notification{read_at: nil})
      refute Notification.unread?(%Notification{read_at: DateTime.utc_now()})
    end
  end

  # ============ Notification CRUD Tests ============

  describe "create_notification/2" do
    test "creates a notification with valid attrs" do
      %{user: user} = create_user()
      attrs = notification_attrs(user.id)

      assert {:ok, notification} = Notifications.create_notification(user.id, attrs)
      assert notification.type == "hub_post"
      assert notification.category == "content"
      assert notification.title == "New in Gaming Hub"
      assert notification.body == "Check out the latest article"
      assert notification.action_url == "/test-article"
      assert notification.metadata == %{"post_id" => 1, "hub_id" => 5}
      assert is_nil(notification.read_at)
    end

    test "fails with invalid attrs" do
      assert {:error, changeset} = Notifications.create_notification(999_999, %{})
      refute changeset.valid?
    end

    test "broadcasts via PubSub" do
      %{user: user} = create_user()
      Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "notifications:#{user.id}")

      attrs = notification_attrs(user.id)
      {:ok, notification} = Notifications.create_notification(user.id, attrs)

      assert_receive {:new_notification, ^notification}
    end
  end

  describe "list_notifications/2" do
    test "returns notifications for user in reverse chronological order" do
      %{user: user} = create_user()

      {:ok, n1} = Notifications.create_notification(user.id, notification_attrs(user.id, %{title: "First"}))
      {:ok, n2} = Notifications.create_notification(user.id, notification_attrs(user.id, %{title: "Second"}))

      notifications = Notifications.list_notifications(user.id)
      assert length(notifications) == 2
      # Both should be present, most recent first (by inserted_at desc, then id desc)
      ids = Enum.map(notifications, & &1.id)
      assert n1.id in ids
      assert n2.id in ids
      # The one with the higher ID should come first (newer)
      assert hd(notifications).id > List.last(notifications).id
    end

    test "excludes dismissed notifications" do
      %{user: user} = create_user()

      {:ok, _n1} = Notifications.create_notification(user.id, notification_attrs(user.id, %{title: "Visible"}))
      {:ok, n2} = Notifications.create_notification(user.id, notification_attrs(user.id, %{title: "Dismissed"}))

      Notifications.dismiss_notification(n2.id)

      notifications = Notifications.list_notifications(user.id)
      assert length(notifications) == 1
      assert hd(notifications).title == "Visible"
    end

    test "filters by category" do
      %{user: user} = create_user()

      {:ok, _} = Notifications.create_notification(user.id, notification_attrs(user.id, %{category: "content"}))
      {:ok, _} = Notifications.create_notification(user.id, notification_attrs(user.id, %{category: "offers", type: "special_offer"}))

      content = Notifications.list_notifications(user.id, category: "content")
      assert length(content) == 1

      offers = Notifications.list_notifications(user.id, category: "offers")
      assert length(offers) == 1
    end

    test "filters by read/unread status" do
      %{user: user} = create_user()

      {:ok, _} = Notifications.create_notification(user.id, notification_attrs(user.id, %{title: "Unread"}))
      {:ok, n2} = Notifications.create_notification(user.id, notification_attrs(user.id, %{title: "Read"}))

      Notifications.mark_as_read(n2.id)

      unread = Notifications.list_notifications(user.id, status: :unread)
      assert length(unread) == 1
      assert hd(unread).title == "Unread"

      read = Notifications.list_notifications(user.id, status: :read)
      assert length(read) == 1
      assert hd(read).title == "Read"
    end

    test "respects limit and offset" do
      %{user: user} = create_user()

      for i <- 1..5 do
        Notifications.create_notification(user.id, notification_attrs(user.id, %{title: "N#{i}"}))
      end

      page1 = Notifications.list_notifications(user.id, limit: 2, offset: 0)
      assert length(page1) == 2

      page2 = Notifications.list_notifications(user.id, limit: 2, offset: 2)
      assert length(page2) == 2

      page3 = Notifications.list_notifications(user.id, limit: 2, offset: 4)
      assert length(page3) == 1
    end

    test "does not return other users' notifications" do
      %{user1: user1, user2: user2} = create_user_pair()

      {:ok, _} = Notifications.create_notification(user1.id, notification_attrs(user1.id, %{title: "User1"}))
      {:ok, _} = Notifications.create_notification(user2.id, notification_attrs(user2.id, %{title: "User2"}))

      user1_notifs = Notifications.list_notifications(user1.id)
      assert length(user1_notifs) == 1
      assert hd(user1_notifs).title == "User1"
    end
  end

  describe "list_recent_notifications/2" do
    test "returns latest N notifications" do
      %{user: user} = create_user()

      for i <- 1..15 do
        Notifications.create_notification(user.id, notification_attrs(user.id, %{title: "N#{i}"}))
      end

      recent = Notifications.list_recent_notifications(user.id, 5)
      assert length(recent) == 5
    end
  end

  describe "unread_count/1" do
    test "returns count of unread, undismissed notifications" do
      %{user: user} = create_user()

      {:ok, _} = Notifications.create_notification(user.id, notification_attrs(user.id))
      {:ok, n2} = Notifications.create_notification(user.id, notification_attrs(user.id))
      {:ok, n3} = Notifications.create_notification(user.id, notification_attrs(user.id))

      assert Notifications.unread_count(user.id) == 3

      Notifications.mark_as_read(n2.id)
      assert Notifications.unread_count(user.id) == 2

      Notifications.dismiss_notification(n3.id)
      assert Notifications.unread_count(user.id) == 1
    end

    test "returns 0 for user with no notifications" do
      %{user: user} = create_user()
      assert Notifications.unread_count(user.id) == 0
    end
  end

  describe "mark_as_read/1" do
    test "marks notification as read" do
      %{user: user} = create_user()
      {:ok, notification} = Notifications.create_notification(user.id, notification_attrs(user.id))

      assert {:ok, updated} = Notifications.mark_as_read(notification.id)
      refute is_nil(updated.read_at)
    end

    test "returns error for non-existent notification" do
      assert {:error, :not_found} = Notifications.mark_as_read(999_999)
    end
  end

  describe "mark_as_clicked/1" do
    test "marks notification as clicked and read" do
      %{user: user} = create_user()
      {:ok, notification} = Notifications.create_notification(user.id, notification_attrs(user.id))

      assert {:ok, updated} = Notifications.mark_as_clicked(notification.id)
      refute is_nil(updated.clicked_at)
      refute is_nil(updated.read_at)
    end
  end

  describe "dismiss_notification/1" do
    test "marks notification as dismissed" do
      %{user: user} = create_user()
      {:ok, notification} = Notifications.create_notification(user.id, notification_attrs(user.id))

      assert {:ok, updated} = Notifications.dismiss_notification(notification.id)
      refute is_nil(updated.dismissed_at)
    end
  end

  describe "mark_all_as_read/1" do
    test "marks all unread notifications as read" do
      %{user: user} = create_user()

      {:ok, _} = Notifications.create_notification(user.id, notification_attrs(user.id))
      {:ok, _} = Notifications.create_notification(user.id, notification_attrs(user.id))
      {:ok, _} = Notifications.create_notification(user.id, notification_attrs(user.id))

      assert Notifications.unread_count(user.id) == 3

      assert {:ok, 3} = Notifications.mark_all_as_read(user.id)
      assert Notifications.unread_count(user.id) == 0
    end

    test "does not affect other users" do
      %{user1: user1, user2: user2} = create_user_pair()

      {:ok, _} = Notifications.create_notification(user1.id, notification_attrs(user1.id))
      {:ok, _} = Notifications.create_notification(user2.id, notification_attrs(user2.id))

      Notifications.mark_all_as_read(user1.id)

      assert Notifications.unread_count(user1.id) == 0
      assert Notifications.unread_count(user2.id) == 1
    end

    test "broadcasts count update" do
      %{user: user} = create_user()
      Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "notifications:#{user.id}")

      {:ok, _} = Notifications.create_notification(user.id, notification_attrs(user.id))
      # Flush the :new_notification message
      assert_receive {:new_notification, _}

      Notifications.mark_all_as_read(user.id)
      assert_receive {:notification_count_updated, 0}
    end
  end

  # ============ Notification Preferences Tests ============

  describe "notification preferences" do
    test "auto-created on wallet registration" do
      %{user: user} = create_user()
      prefs = Notifications.get_preferences(user.id)

      assert prefs
      assert prefs.email_enabled == true
      assert prefs.sms_enabled == true
      assert prefs.in_app_enabled == true
      assert prefs.in_app_toast_enabled == true
      assert prefs.max_emails_per_day == 3
      assert prefs.timezone == "UTC"
      refute is_nil(prefs.unsubscribe_token)
    end

    test "auto-created on email registration" do
      {:ok, user} =
        BlocksterV2.Accounts.create_user_from_email(%{
          email: "test_#{System.unique_integer([:positive])}@example.com",
          wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
          smart_wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}"
        })

      prefs = Notifications.get_preferences(user.id)
      assert prefs
      assert prefs.email_enabled == true
    end

    test "get_or_create_preferences creates if missing" do
      # Create user without going through normal registration flow
      {:ok, user} =
        BlocksterV2.Repo.insert(%BlocksterV2.Accounts.User{
          wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
          chain_id: 560013
        })

      # Should not have prefs yet (we bypassed registration)
      assert is_nil(Notifications.get_preferences(user.id))

      # get_or_create should create them
      assert {:ok, prefs} = Notifications.get_or_create_preferences(user.id)
      assert prefs.user_id == user.id
      assert prefs.email_enabled == true
    end

    test "update_preferences updates existing preferences" do
      %{user: user} = create_user()

      assert {:ok, updated} =
               Notifications.update_preferences(user.id, %{
                 email_enabled: false,
                 max_emails_per_day: 1,
                 timezone: "America/New_York"
               })

      assert updated.email_enabled == false
      assert updated.max_emails_per_day == 1
      assert updated.timezone == "America/New_York"
    end

    test "validates max_emails_per_day range" do
      %{user: user} = create_user()

      assert {:error, changeset} =
               Notifications.update_preferences(user.id, %{max_emails_per_day: 0})

      assert errors_on(changeset) |> Map.has_key?(:max_emails_per_day)

      assert {:error, changeset} =
               Notifications.update_preferences(user.id, %{max_emails_per_day: 11})

      assert errors_on(changeset) |> Map.has_key?(:max_emails_per_day)
    end

    test "unsubscribe_token is unique per user" do
      %{user1: user1, user2: user2} = create_user_pair()

      prefs1 = Notifications.get_preferences(user1.id)
      prefs2 = Notifications.get_preferences(user2.id)

      refute prefs1.unsubscribe_token == prefs2.unsubscribe_token
    end

    test "find_by_unsubscribe_token works" do
      %{user: user} = create_user()
      prefs = Notifications.get_preferences(user.id)

      found = Notifications.find_by_unsubscribe_token(prefs.unsubscribe_token)
      assert found.id == prefs.id
      assert found.user_id == user.id
    end

    test "unsubscribe_all disables email and sms" do
      %{user: user} = create_user()
      prefs = Notifications.get_preferences(user.id)

      assert {:ok, updated} = Notifications.unsubscribe_all(prefs.unsubscribe_token)
      assert updated.email_enabled == false
      assert updated.sms_enabled == false
    end

    test "unsubscribe_all returns error for invalid token" do
      assert {:error, :not_found} = Notifications.unsubscribe_all("invalid_token")
    end

    test "enforces unique user_id constraint" do
      %{user: user} = create_user()
      # Prefs already created by registration

      assert {:error, changeset} = Notifications.create_preferences(user.id)
      assert errors_on(changeset) |> Map.has_key?(:user_id)
    end
  end

  # ============ Campaign Tests ============

  describe "campaigns" do
    test "creates a campaign with valid attrs" do
      %{user: user} = create_user()

      assert {:ok, campaign} =
               Notifications.create_campaign(%{
                 name: "Summer Sale",
                 type: "email_blast",
                 subject: "50% off everything!",
                 title: "Summer Sale",
                 body: "<h1>Big sale!</h1>",
                 action_url: "/shop",
                 action_label: "Shop Now",
                 target_audience: "all",
                 created_by_id: user.id
               })

      assert campaign.name == "Summer Sale"
      assert campaign.status == "draft"
      assert campaign.send_email == true
    end

    test "validates required fields" do
      assert {:error, changeset} = Notifications.create_campaign(%{})
      refute changeset.valid?
      assert errors_on(changeset) |> Map.has_key?(:name)
      assert errors_on(changeset) |> Map.has_key?(:type)
    end

    test "validates type inclusion" do
      assert {:error, changeset} =
               Notifications.create_campaign(%{name: "Test", type: "invalid"})

      assert errors_on(changeset) |> Map.has_key?(:type)
    end

    test "validates status inclusion" do
      %{user: user} = create_user()

      {:ok, campaign} =
        Notifications.create_campaign(%{
          name: "Test",
          type: "email_blast",
          created_by_id: user.id
        })

      assert {:error, changeset} = Notifications.update_campaign_status(campaign, "invalid_status")
      assert errors_on(changeset) |> Map.has_key?(:status)
    end

    test "list_campaigns returns all campaigns" do
      {:ok, _} = Notifications.create_campaign(%{name: "Campaign 1", type: "email_blast"})
      {:ok, _} = Notifications.create_campaign(%{name: "Campaign 2", type: "sms_blast"})

      campaigns = Notifications.list_campaigns()
      assert length(campaigns) >= 2
    end

    test "list_campaigns filters by status" do
      {:ok, c1} = Notifications.create_campaign(%{name: "Draft", type: "email_blast"})
      {:ok, _} = Notifications.update_campaign_status(c1, "sent")
      {:ok, _} = Notifications.create_campaign(%{name: "Still Draft", type: "email_blast"})

      drafts = Notifications.list_campaigns(status: "draft")
      sent = Notifications.list_campaigns(status: "sent")

      assert Enum.any?(drafts, &(&1.name == "Still Draft"))
      assert Enum.any?(sent, &(&1.name == "Draft"))
    end

    test "update_campaign updates fields" do
      {:ok, campaign} = Notifications.create_campaign(%{name: "Original", type: "email_blast"})

      assert {:ok, updated} =
               Notifications.update_campaign(campaign, %{
                 name: "Updated",
                 subject: "New Subject"
               })

      assert updated.name == "Updated"
      assert updated.subject == "New Subject"
    end

    test "update_campaign_status transitions status" do
      {:ok, campaign} = Notifications.create_campaign(%{name: "Test", type: "email_blast"})
      assert campaign.status == "draft"

      assert {:ok, scheduled} = Notifications.update_campaign_status(campaign, "scheduled")
      assert scheduled.status == "scheduled"

      assert {:ok, sending} = Notifications.update_campaign_status(scheduled, "sending")
      assert sending.status == "sending"

      assert {:ok, sent} = Notifications.update_campaign_status(sending, "sent")
      assert sent.status == "sent"
    end
  end

  # ============ Email Log Tests ============

  describe "email logs" do
    test "creates an email log" do
      %{user: user} = create_user()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      assert {:ok, log} =
               Notifications.create_email_log(%{
                 user_id: user.id,
                 email_type: "digest",
                 subject: "Your daily digest",
                 sent_at: now,
                 sendgrid_message_id: "sg_123"
               })

      assert log.email_type == "digest"
      assert log.sendgrid_message_id == "sg_123"
    end

    test "validates required fields" do
      assert {:error, changeset} = Notifications.create_email_log(%{})
      assert errors_on(changeset) |> Map.has_key?(:user_id)
      assert errors_on(changeset) |> Map.has_key?(:email_type)
      assert errors_on(changeset) |> Map.has_key?(:sent_at)
    end

    test "emails_sent_today counts today's emails" do
      %{user: user} = create_user()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      for _ <- 1..3 do
        Notifications.create_email_log(%{
          user_id: user.id,
          email_type: "promo",
          sent_at: now
        })
      end

      assert Notifications.emails_sent_today(user.id) == 3
    end

    test "emails_sent_today returns 0 for no emails" do
      %{user: user} = create_user()
      assert Notifications.emails_sent_today(user.id) == 0
    end

    test "links to notification and campaign" do
      %{user: user} = create_user()
      {:ok, campaign} = Notifications.create_campaign(%{name: "Test", type: "email_blast"})
      {:ok, notification} = Notifications.create_notification(user.id, notification_attrs(user.id))
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      assert {:ok, log} =
               Notifications.create_email_log(%{
                 user_id: user.id,
                 email_type: "promo",
                 sent_at: now,
                 notification_id: notification.id,
                 campaign_id: campaign.id
               })

      assert log.notification_id == notification.id
      assert log.campaign_id == campaign.id
    end
  end

  # ============ HubFollower Schema Tests ============

  describe "HubFollower schema" do
    test "valid changeset" do
      changeset =
        BlocksterV2.Blog.HubFollower.changeset(%BlocksterV2.Blog.HubFollower{}, %{
          hub_id: 1,
          user_id: 1,
          notify_new_posts: true,
          notify_events: false
        })

      assert changeset.valid?
    end

    test "requires hub_id and user_id" do
      changeset = BlocksterV2.Blog.HubFollower.changeset(%BlocksterV2.Blog.HubFollower{}, %{})
      refute changeset.valid?
      assert errors_on(changeset) |> Map.has_key?(:hub_id)
      assert errors_on(changeset) |> Map.has_key?(:user_id)
    end

    test "notification_changeset only updates notification fields" do
      follower = %BlocksterV2.Blog.HubFollower{
        hub_id: 1,
        user_id: 1,
        notify_new_posts: true
      }

      changeset =
        BlocksterV2.Blog.HubFollower.notification_changeset(follower, %{
          notify_new_posts: false,
          email_notifications: false
        })

      assert changeset.valid?
      assert changeset.changes[:notify_new_posts] == false
      assert changeset.changes[:email_notifications] == false
    end
  end

  # ============ PubSub Integration Tests ============

  describe "PubSub broadcasting" do
    test "broadcast_new_notification sends to correct topic" do
      %{user: user} = create_user()
      Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "notifications:#{user.id}")

      notification = %Notification{id: 1, title: "Test", type: "hub_post"}
      Notifications.broadcast_new_notification(user.id, notification)

      assert_receive {:new_notification, ^notification}
    end

    test "broadcast_count_update sends count to correct topic" do
      %{user: user} = create_user()
      Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "notifications:#{user.id}")

      Notifications.broadcast_count_update(user.id, 5)
      assert_receive {:notification_count_updated, 5}
    end

    test "notifications don't leak between users" do
      %{user1: user1, user2: user2} = create_user_pair()

      Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "notifications:#{user1.id}")

      Notifications.create_notification(user2.id, notification_attrs(user2.id))

      refute_receive {:new_notification, _}, 100
    end
  end
end
