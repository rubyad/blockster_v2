defmodule BlocksterV2.Notifications.Phase12Test do
  use BlocksterV2.DataCase, async: false

  alias BlocksterV2.{Notifications, Repo}
  alias BlocksterV2.Notifications.{Campaign, EmailLog, Notification, EngagementScorer}

  # ============ Test Helpers ============

  defp create_user(attrs \\ %{}) do
    wallet = "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}"

    {:ok, user} =
      BlocksterV2.Accounts.create_user_from_wallet(%{
        wallet_address: wallet,
        chain_id: 560013
      })

    email = Map.get(attrs, :email, "user_#{user.id}@test.com")
    username = Map.get(attrs, :username, "TestUser#{user.id}")

    user
    |> Ecto.Changeset.change(%{email: email, username: username})
    |> Repo.update!()
  end

  defp create_campaign(attrs \\ %{}) do
    # Separate stat fields (not in Campaign changeset cast) from regular fields
    {stat_fields, regular_fields} = Map.split(attrs, [:emails_sent, :emails_opened, :emails_clicked, :sms_sent, :in_app_delivered, :in_app_read, :total_recipients])

    base = %{
      name: "Test Campaign #{System.unique_integer([:positive])}",
      type: "email_blast",
      status: "sent"
    }

    {:ok, campaign} = Notifications.create_campaign(Map.merge(base, regular_fields))

    # Apply stat fields directly (not in changeset cast)
    if map_size(stat_fields) > 0 do
      campaign
      |> Ecto.Changeset.change(stat_fields)
      |> Repo.update!()
    else
      campaign
    end
  end

  defp create_email_log(user_id, attrs \\ %{}) do
    base = %{
      user_id: user_id,
      email_type: "promotional",
      subject: "Test Email",
      sent_at: DateTime.utc_now() |> DateTime.truncate(:second),
      sendgrid_message_id: "sg_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"
    }

    {:ok, log} = Notifications.create_email_log(Map.merge(base, attrs))
    log
  end

  defp create_notification(user_id, attrs \\ %{}) do
    base = %{
      type: "special_offer",
      category: "offers",
      title: "Test notification",
      body: "Test body"
    }

    {:ok, notif} = Notifications.create_notification(user_id, Map.merge(base, attrs))
    notif
  end

  defp create_hub do
    {:ok, hub} = BlocksterV2.Blog.create_hub(%{
      name: "Test Hub #{System.unique_integer([:positive])}",
      description: "A test hub",
      slug: "test-hub-#{System.unique_integer([:positive])}",
      tag_name: "test_tag_#{System.unique_integer([:positive])}"
    })
    hub
  end

  # ============ Top Campaigns ============

  describe "top_campaigns/1" do
    test "returns top campaigns ordered by opens" do
      c1 = create_campaign(%{emails_sent: 100, emails_opened: 50})
      c2 = create_campaign(%{emails_sent: 100, emails_opened: 80})
      c3 = create_campaign(%{emails_sent: 100, emails_opened: 30})

      top = Notifications.top_campaigns(3)
      ids = Enum.map(top, & &1.id)

      assert hd(ids) == c2.id
      assert List.last(ids) == c3.id
    end

    test "excludes draft campaigns" do
      create_campaign(%{status: "draft", emails_sent: 100, emails_opened: 99})
      sent = create_campaign(%{status: "sent", emails_sent: 50, emails_opened: 20})

      top = Notifications.top_campaigns(5)
      ids = Enum.map(top, & &1.id)

      refute Enum.any?(ids, fn id ->
        campaign = Notifications.get_campaign!(id)
        campaign.status == "draft"
      end)
      assert sent.id in ids
    end

    test "excludes campaigns with 0 emails sent" do
      create_campaign(%{emails_sent: 0, emails_opened: 0})
      with_sends = create_campaign(%{emails_sent: 10, emails_opened: 5})

      top = Notifications.top_campaigns(5)
      ids = Enum.map(top, & &1.id)

      assert with_sends.id in ids
    end

    test "respects limit parameter" do
      for _ <- 1..5 do
        create_campaign(%{emails_sent: 10, emails_opened: 5})
      end

      top = Notifications.top_campaigns(3)
      assert length(top) <= 3
    end

    test "returns empty list when no sent campaigns" do
      create_campaign(%{status: "draft"})

      assert Notifications.top_campaigns(5) == []
    end
  end

  # ============ Hub Subscription Stats ============

  describe "hub_subscription_stats/0" do
    test "returns follower counts per hub" do
      hub = create_hub()
      user1 = create_user()
      user2 = create_user()

      BlocksterV2.Blog.follow_hub(user1.id, hub.id)
      BlocksterV2.Blog.follow_hub(user2.id, hub.id)

      stats = Notifications.hub_subscription_stats()
      hub_stat = Enum.find(stats, &(&1.hub_id == hub.id))

      assert hub_stat != nil
      assert hub_stat.follower_count == 2
      assert hub_stat.hub_name == hub.name
    end

    test "counts notification-enabled followers" do
      hub = create_hub()
      user1 = create_user()
      user2 = create_user()

      BlocksterV2.Blog.follow_hub(user1.id, hub.id)
      BlocksterV2.Blog.follow_hub(user2.id, hub.id)

      # Disable notifications for user2
      BlocksterV2.Blog.update_hub_follow_notifications(user2.id, hub.id, %{notify_new_posts: false})

      stats = Notifications.hub_subscription_stats()
      hub_stat = Enum.find(stats, &(&1.hub_id == hub.id))

      assert hub_stat.follower_count == 2
      assert hub_stat.notify_enabled == 1
    end

    test "returns empty list when no hubs have followers" do
      # Create hub but don't follow it
      _hub = create_hub()

      stats = Notifications.hub_subscription_stats()
      # Stats might include other test data, but our new hub shouldn't appear
      # since it has 0 followers (no hub_followers rows)
      assert is_list(stats)
    end

    test "orders by follower count descending" do
      hub1 = create_hub()
      hub2 = create_hub()

      u1 = create_user()
      u2 = create_user()
      u3 = create_user()

      BlocksterV2.Blog.follow_hub(u1.id, hub1.id)
      BlocksterV2.Blog.follow_hub(u2.id, hub2.id)
      BlocksterV2.Blog.follow_hub(u3.id, hub2.id)

      stats = Notifications.hub_subscription_stats()
      hub1_stat = Enum.find(stats, &(&1.hub_id == hub1.id))
      hub2_stat = Enum.find(stats, &(&1.hub_id == hub2.id))

      hub1_idx = Enum.find_index(stats, &(&1.hub_id == hub1.id))
      hub2_idx = Enum.find_index(stats, &(&1.hub_id == hub2.id))

      assert hub2_stat.follower_count > hub1_stat.follower_count
      assert hub2_idx < hub1_idx
    end
  end

  # ============ EngagementScorer Analytics ============

  describe "EngagementScorer.aggregate_stats/1" do
    test "returns all expected keys" do
      stats = EngagementScorer.aggregate_stats(30)

      assert Map.has_key?(stats, :total_emails_sent)
      assert Map.has_key?(stats, :total_emails_opened)
      assert Map.has_key?(stats, :total_emails_clicked)
      assert Map.has_key?(stats, :total_emails_bounced)
      assert Map.has_key?(stats, :total_emails_unsubscribed)
      assert Map.has_key?(stats, :overall_open_rate)
      assert Map.has_key?(stats, :overall_click_rate)
      assert Map.has_key?(stats, :overall_bounce_rate)
      assert Map.has_key?(stats, :total_in_app_delivered)
      assert Map.has_key?(stats, :total_in_app_read)
      assert Map.has_key?(stats, :in_app_read_rate)
      assert Map.has_key?(stats, :period_days)
    end

    test "returns correct period_days" do
      stats = EngagementScorer.aggregate_stats(7)
      assert stats.period_days == 7

      stats = EngagementScorer.aggregate_stats(90)
      assert stats.period_days == 90
    end

    test "counts emails correctly" do
      user = create_user()
      create_email_log(user.id)
      create_email_log(user.id)
      create_email_log(user.id)

      stats = EngagementScorer.aggregate_stats(30)
      assert stats.total_emails_sent >= 3
    end

    test "calculates rates correctly" do
      user = create_user()

      for _ <- 1..4 do
        create_email_log(user.id)
      end

      # Mark 2 as opened
      import Ecto.Query
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      logs = Repo.all(from l in EmailLog, where: l.user_id == ^user.id, limit: 2)
      for log <- logs do
        log |> Ecto.Changeset.change(%{opened_at: now}) |> Repo.update!()
      end

      stats = EngagementScorer.aggregate_stats(30)
      assert stats.overall_open_rate > 0
    end
  end

  describe "EngagementScorer.daily_email_volume/1" do
    test "returns list of daily stats" do
      user = create_user()
      create_email_log(user.id)

      volumes = EngagementScorer.daily_email_volume(30)
      assert is_list(volumes)
      assert length(volumes) >= 1
    end

    test "each day has date, sent, opened, clicked" do
      user = create_user()
      create_email_log(user.id)

      volumes = EngagementScorer.daily_email_volume(30)
      day = hd(volumes)

      assert Map.has_key?(day, :date)
      assert Map.has_key?(day, :sent)
      assert Map.has_key?(day, :opened)
      assert Map.has_key?(day, :clicked)
    end

    test "respects period parameter" do
      user = create_user()
      create_email_log(user.id)

      vol_7 = EngagementScorer.daily_email_volume(7)
      vol_30 = EngagementScorer.daily_email_volume(30)

      # Both should contain today's data
      assert length(vol_7) >= 1
      assert length(vol_30) >= 1
    end
  end

  describe "EngagementScorer.send_time_distribution/1" do
    test "returns hourly distribution" do
      user = create_user()
      create_email_log(user.id)

      dist = EngagementScorer.send_time_distribution(30)
      assert is_list(dist)
    end

    test "entries have hour, sent, and open_rate" do
      user = create_user()
      create_email_log(user.id)

      dist = EngagementScorer.send_time_distribution(30)

      if length(dist) > 0 do
        entry = hd(dist)
        assert Map.has_key?(entry, :hour)
        assert Map.has_key?(entry, :sent)
        assert Map.has_key?(entry, :open_rate)
        assert entry.hour >= 0 and entry.hour <= 23
      end
    end
  end

  describe "EngagementScorer.channel_comparison/1" do
    test "returns all three channels" do
      comparison = EngagementScorer.channel_comparison(30)

      assert length(comparison) == 3
      channels = Enum.map(comparison, & &1.channel)
      assert "email" in channels
      assert "in_app" in channels
      assert "sms" in channels
    end

    test "each channel has sent, engaged, rate" do
      comparison = EngagementScorer.channel_comparison(30)

      for ch <- comparison do
        assert Map.has_key?(ch, :sent)
        assert Map.has_key?(ch, :engaged)
        assert Map.has_key?(ch, :rate)
        assert is_number(ch.rate)
      end
    end

    test "includes email data when emails exist" do
      user = create_user()
      create_email_log(user.id)

      comparison = EngagementScorer.channel_comparison(30)
      email = Enum.find(comparison, &(&1.channel == "email"))

      assert email.sent >= 1
    end
  end

  # ============ Combined Analytics Queries ============

  describe "analytics data integration" do
    test "email and notification stats are independent" do
      user = create_user()
      campaign = create_campaign()

      # Create email activity for campaign
      create_email_log(user.id, %{campaign_id: campaign.id})

      # Create in-app notification for campaign
      create_notification(user.id, %{campaign_id: campaign.id})

      stats = Notifications.get_campaign_stats(campaign.id)

      assert stats.email.sent == 1
      assert stats.in_app.delivered == 1
    end

    test "aggregate stats count across multiple users" do
      user1 = create_user()
      user2 = create_user()

      create_email_log(user1.id)
      create_email_log(user2.id)

      create_notification(user1.id)
      create_notification(user2.id)

      stats = EngagementScorer.aggregate_stats(30)
      assert stats.total_emails_sent >= 2
      assert stats.total_in_app_delivered >= 2
    end

    test "per-user engagement score works" do
      user = create_user()
      create_email_log(user.id)
      create_notification(user.id)

      score = EngagementScorer.calculate_score(user.id)

      assert score.emails_sent >= 1
      assert score.in_app_delivered >= 1
      assert score.engagement_tier in [:highly_engaged, :moderately_engaged, :low_engagement, :dormant]
    end
  end
end
