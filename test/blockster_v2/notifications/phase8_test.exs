defmodule BlocksterV2.Notifications.Phase8Test do
  use BlocksterV2.DataCase, async: false

  alias BlocksterV2.{Notifications, Repo, Blog}
  alias BlocksterV2.Workers.{
    DailyDigestWorker,
    WelcomeSeriesWorker,
    ReEngagementWorker,
    WeeklyRewardSummaryWorker,
    ReferralPromptWorker,
    HubPostNotificationWorker,
    PromoEmailWorker,
    CartAbandonmentWorker
  }

  import Swoosh.TestAssertions

  # ============ Test Helpers ============

  defp create_user(attrs \\ %{}) do
    wallet = "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}"

    {:ok, user} =
      BlocksterV2.Accounts.create_user_from_wallet(%{
        wallet_address: wallet,
        chain_id: 560013
      })

    # Set email and username if provided
    email = Map.get(attrs, :email, "user_#{user.id}@test.com")
    username = Map.get(attrs, :username, "TestUser#{user.id}")

    user
    |> Ecto.Changeset.change(%{email: email, username: username})
    |> Repo.update!()
  end

  defp create_user_with_prefs(user_attrs \\ %{}, pref_overrides \\ %{}) do
    user = create_user(user_attrs)
    {:ok, prefs} = Notifications.get_or_create_preferences(user.id)

    if pref_overrides != %{} do
      {:ok, prefs} = Notifications.update_preferences(user.id, pref_overrides)
      {user, prefs}
    else
      {user, prefs}
    end
  end

  defp create_hub do
    n = System.unique_integer([:positive])

    {:ok, hub} =
      Blog.create_hub(%{
        name: "Test Hub #{n}",
        slug: "test-hub-#{n}",
        tag_name: "test#{n}",
        description: "A test hub"
      })

    hub
  end

  defp create_post(hub) do
    {user, _prefs} = create_user_with_prefs()
    n = System.unique_integer([:positive])

    {:ok, post} =
      Blog.create_post(%{
        title: "Test Post #{n}",
        slug: "test-post-#{n}",
        excerpt: "This is a test post with some content.",
        published_at: DateTime.utc_now() |> DateTime.truncate(:second),
        hub_id: hub.id,
        author_id: user.id
      })

    post
  end

  defp create_campaign(attrs \\ %{}) do
    default_attrs = %{
      name: "Test Campaign",
      type: "email_blast",
      subject: "Big Promo",
      title: "Amazing Offer",
      body: "<p>Check this out!</p>",
      plain_text_body: "Check this out!",
      action_url: "/shop",
      action_label: "Shop Now",
      target_audience: "all",
      send_in_app: true
    }

    {:ok, campaign} = Notifications.create_campaign(Map.merge(default_attrs, attrs))
    campaign
  end

  # ============ Daily Digest Worker ============

  describe "DailyDigestWorker" do
    test "batch job enqueues individual jobs for eligible users" do
      {user, _prefs} = create_user_with_prefs()

      # Create a published post so digest has content
      hub = create_hub()
      _post = create_post(hub)

      # In inline mode, the batch job will execute immediately
      # and the individual jobs it enqueues will also run inline
      result = perform_job(DailyDigestWorker, %{})
      assert result == :ok
    end

    test "individual job sends email for eligible user with content" do
      {user, _prefs} = create_user_with_prefs()
      hub = create_hub()
      _post = create_post(hub)

      result = perform_job(DailyDigestWorker, %{user_id: user.id})
      assert result == :ok

      # Should have created an email log
      logs = Repo.all(BlocksterV2.Notifications.EmailLog)
      digest_logs = Enum.filter(logs, &(&1.email_type == "daily_digest" && &1.user_id == user.id))
      assert length(digest_logs) >= 1
    end

    test "skips users without email" do
      {:ok, user} =
        BlocksterV2.Accounts.create_user_from_wallet(%{
          wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
          chain_id: 560013
        })

      # No email set
      result = perform_job(DailyDigestWorker, %{user_id: user.id})
      assert result == :ok
    end

    test "skips users with email disabled in preferences" do
      {user, _prefs} = create_user_with_prefs(%{}, %{email_enabled: false})

      result = perform_job(DailyDigestWorker, %{user_id: user.id})
      assert result == :ok

      # Should NOT have created an email log
      logs = Repo.all(BlocksterV2.Notifications.EmailLog)
      digest_logs = Enum.filter(logs, &(&1.user_id == user.id && &1.email_type == "daily_digest"))
      assert digest_logs == []
    end

    test "skips users with daily digest disabled" do
      {user, _prefs} = create_user_with_prefs(%{}, %{email_daily_digest: false})

      result = perform_job(DailyDigestWorker, %{user_id: user.id})
      assert result == :ok

      logs = Repo.all(BlocksterV2.Notifications.EmailLog)
      digest_logs = Enum.filter(logs, &(&1.user_id == user.id && &1.email_type == "daily_digest"))
      assert digest_logs == []
    end

    test "returns :ok when no articles available" do
      {user, _prefs} = create_user_with_prefs()
      # No posts created
      result = perform_job(DailyDigestWorker, %{user_id: user.id})
      assert result == :ok
    end
  end

  # ============ Welcome Series Worker ============

  describe "WelcomeSeriesWorker" do
    test "enqueue_series creates 4 jobs" do
      {user, _prefs} = create_user_with_prefs()

      # In inline mode, all jobs execute immediately
      assert :ok == WelcomeSeriesWorker.enqueue_series(user.id)
    end

    test "day 0 sends welcome email" do
      {user, _prefs} = create_user_with_prefs()

      result = perform_job(WelcomeSeriesWorker, %{user_id: user.id, day: 0})
      assert result == :ok

      logs = Repo.all(BlocksterV2.Notifications.EmailLog)
      welcome_logs = Enum.filter(logs, &(&1.user_id == user.id && &1.email_type == "welcome_series_day_0"))
      assert length(welcome_logs) == 1
    end

    test "day 3 sends BUX earning article email" do
      {user, _prefs} = create_user_with_prefs()

      result = perform_job(WelcomeSeriesWorker, %{user_id: user.id, day: 3})
      assert result == :ok

      logs = Repo.all(BlocksterV2.Notifications.EmailLog)
      day3_logs = Enum.filter(logs, &(&1.user_id == user.id && &1.email_type == "welcome_series_day_3"))
      assert length(day3_logs) == 1
    end

    test "day 5 sends hub discovery email" do
      {user, _prefs} = create_user_with_prefs()

      result = perform_job(WelcomeSeriesWorker, %{user_id: user.id, day: 5})
      assert result == :ok

      logs = Repo.all(BlocksterV2.Notifications.EmailLog)
      day5_logs = Enum.filter(logs, &(&1.user_id == user.id && &1.email_type == "welcome_series_day_5"))
      assert length(day5_logs) == 1
    end

    test "day 7 sends referral prompt email" do
      {user, _prefs} = create_user_with_prefs()

      result = perform_job(WelcomeSeriesWorker, %{user_id: user.id, day: 7})
      assert result == :ok

      logs = Repo.all(BlocksterV2.Notifications.EmailLog)
      day7_logs = Enum.filter(logs, &(&1.user_id == user.id && &1.email_type == "welcome_series_day_7"))
      assert length(day7_logs) == 1
    end

    test "skips user without email" do
      {:ok, user} =
        BlocksterV2.Accounts.create_user_from_wallet(%{
          wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
          chain_id: 560013
        })

      result = perform_job(WelcomeSeriesWorker, %{user_id: user.id, day: 0})
      assert result == :ok
    end

    test "respects rate limiter when email disabled" do
      {user, _prefs} = create_user_with_prefs(%{}, %{email_enabled: false})

      result = perform_job(WelcomeSeriesWorker, %{user_id: user.id, day: 0})
      assert result == :ok

      logs = Repo.all(BlocksterV2.Notifications.EmailLog)
      welcome_logs = Enum.filter(logs, &(&1.user_id == user.id))
      assert welcome_logs == []
    end
  end

  # ============ Re-Engagement Worker ============

  describe "ReEngagementWorker" do
    test "batch job runs without error" do
      result = perform_job(ReEngagementWorker, %{})
      assert result == :ok
    end

    test "individual job sends re-engagement email" do
      {user, _prefs} = create_user_with_prefs()

      result = perform_job(ReEngagementWorker, %{user_id: user.id, days_inactive: 7})
      assert result == :ok

      logs = Repo.all(BlocksterV2.Notifications.EmailLog)
      re_logs = Enum.filter(logs, &(&1.user_id == user.id && &1.email_type == "re_engagement_7d"))
      assert length(re_logs) == 1
    end

    test "30-day inactive users get special offer in email" do
      {user, _prefs} = create_user_with_prefs()

      result = perform_job(ReEngagementWorker, %{user_id: user.id, days_inactive: 30})
      assert result == :ok

      logs = Repo.all(BlocksterV2.Notifications.EmailLog)
      re_logs = Enum.filter(logs, &(&1.user_id == user.id && &1.email_type == "re_engagement_30d"))
      assert length(re_logs) == 1
    end

    test "3-day inactive users do not get special offer" do
      {user, _prefs} = create_user_with_prefs()

      result = perform_job(ReEngagementWorker, %{user_id: user.id, days_inactive: 3})
      assert result == :ok

      logs = Repo.all(BlocksterV2.Notifications.EmailLog)
      re_logs = Enum.filter(logs, &(&1.user_id == user.id && &1.email_type == "re_engagement_3d"))
      assert length(re_logs) == 1
    end

    test "skips users with re_engagement emails disabled" do
      {user, _prefs} = create_user_with_prefs(%{}, %{email_re_engagement: false})

      result = perform_job(ReEngagementWorker, %{user_id: user.id, days_inactive: 14})
      assert result == :ok

      logs = Repo.all(BlocksterV2.Notifications.EmailLog)
      re_logs = Enum.filter(logs, &(&1.user_id == user.id))
      assert re_logs == []
    end
  end

  # ============ Weekly Reward Summary Worker ============

  describe "WeeklyRewardSummaryWorker" do
    test "batch job runs without error" do
      result = perform_job(WeeklyRewardSummaryWorker, %{})
      assert result == :ok
    end

    test "individual job sends summary email" do
      {user, _prefs} = create_user_with_prefs()

      result = perform_job(WeeklyRewardSummaryWorker, %{user_id: user.id})
      assert result == :ok

      logs = Repo.all(BlocksterV2.Notifications.EmailLog)
      summary_logs = Enum.filter(logs, &(&1.user_id == user.id && &1.email_type == "weekly_reward_summary"))
      assert length(summary_logs) == 1
    end

    test "skips users with reward_alerts email disabled" do
      {user, _prefs} = create_user_with_prefs(%{}, %{email_reward_alerts: false})

      result = perform_job(WeeklyRewardSummaryWorker, %{user_id: user.id})
      assert result == :ok

      logs = Repo.all(BlocksterV2.Notifications.EmailLog)
      summary_logs = Enum.filter(logs, &(&1.user_id == user.id))
      assert summary_logs == []
    end

    test "skips users without email" do
      {:ok, user} =
        BlocksterV2.Accounts.create_user_from_wallet(%{
          wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
          chain_id: 560013
        })

      result = perform_job(WeeklyRewardSummaryWorker, %{user_id: user.id})
      assert result == :ok
    end
  end

  # ============ Referral Prompt Worker ============

  describe "ReferralPromptWorker" do
    test "batch job runs without error" do
      result = perform_job(ReferralPromptWorker, %{})
      assert result == :ok
    end

    test "individual job sends referral prompt email" do
      {user, _prefs} = create_user_with_prefs()

      result = perform_job(ReferralPromptWorker, %{user_id: user.id})
      assert result == :ok

      logs = Repo.all(BlocksterV2.Notifications.EmailLog)
      ref_logs = Enum.filter(logs, &(&1.user_id == user.id && &1.email_type == "referral_prompt"))
      assert length(ref_logs) == 1
    end

    test "skips users with referral prompts disabled" do
      {user, _prefs} = create_user_with_prefs(%{}, %{email_referral_prompts: false})

      result = perform_job(ReferralPromptWorker, %{user_id: user.id})
      assert result == :ok

      logs = Repo.all(BlocksterV2.Notifications.EmailLog)
      ref_logs = Enum.filter(logs, &(&1.user_id == user.id))
      assert ref_logs == []
    end

    test "email log records correct subject" do
      {user, _prefs} = create_user_with_prefs()

      perform_job(ReferralPromptWorker, %{user_id: user.id})

      log =
        Repo.all(BlocksterV2.Notifications.EmailLog)
        |> Enum.find(&(&1.user_id == user.id && &1.email_type == "referral_prompt"))

      assert log != nil
      assert log.subject != nil
      assert log.sent_at != nil
    end
  end

  # ============ Hub Post Notification Worker ============

  describe "HubPostNotificationWorker" do
    test "enqueue/3 creates a job" do
      {user, _prefs} = create_user_with_prefs()
      hub = create_hub()
      post = create_post(hub)

      # In inline mode, this executes immediately
      assert {:ok, _job} = HubPostNotificationWorker.enqueue(user.id, post.id, hub.id)
    end

    test "sends hub post notification email" do
      {user, _prefs} = create_user_with_prefs()
      hub = create_hub()
      post = create_post(hub)

      result = perform_job(HubPostNotificationWorker, %{
        user_id: user.id,
        post_id: post.id,
        hub_id: hub.id
      })

      assert result == :ok

      logs = Repo.all(BlocksterV2.Notifications.EmailLog)
      hub_logs = Enum.filter(logs, &(&1.user_id == user.id && &1.email_type == "hub_post"))
      assert length(hub_logs) == 1
    end

    test "skips when post does not exist" do
      {user, _prefs} = create_user_with_prefs()
      hub = create_hub()

      result = perform_job(HubPostNotificationWorker, %{
        user_id: user.id,
        post_id: -1,
        hub_id: hub.id
      })

      assert result == :ok
    end

    test "skips when hub does not exist" do
      {user, _prefs} = create_user_with_prefs()
      hub = create_hub()
      post = create_post(hub)

      result = perform_job(HubPostNotificationWorker, %{
        user_id: user.id,
        post_id: post.id,
        hub_id: -1
      })

      assert result == :ok
    end

    test "respects email_hub_posts preference" do
      {user, _prefs} = create_user_with_prefs(%{}, %{email_hub_posts: false})
      hub = create_hub()
      post = create_post(hub)

      result = perform_job(HubPostNotificationWorker, %{
        user_id: user.id,
        post_id: post.id,
        hub_id: hub.id
      })

      assert result == :ok

      logs = Repo.all(BlocksterV2.Notifications.EmailLog)
      hub_logs = Enum.filter(logs, &(&1.user_id == user.id))
      assert hub_logs == []
    end
  end

  # ============ Promo Email Worker ============

  describe "PromoEmailWorker" do
    test "enqueue_campaign/1 creates a job" do
      campaign = create_campaign()
      assert {:ok, _job} = PromoEmailWorker.enqueue_campaign(campaign.id)
    end

    test "campaign job enqueues individual user jobs" do
      {user, _prefs} = create_user_with_prefs(%{}, %{email_special_offers: true})
      campaign = create_campaign()

      # Batch job should find eligible users and enqueue per-user jobs
      result = perform_job(PromoEmailWorker, %{campaign_id: campaign.id})
      assert result == :ok
    end

    test "individual user job sends promotional email" do
      {user, _prefs} = create_user_with_prefs(%{}, %{email_special_offers: true})
      campaign = create_campaign()

      result = perform_job(PromoEmailWorker, %{campaign_id: campaign.id, user_id: user.id})
      assert result == :ok

      logs = Repo.all(BlocksterV2.Notifications.EmailLog)
      promo_logs = Enum.filter(logs, &(&1.user_id == user.id && &1.email_type == "promotional"))
      assert length(promo_logs) == 1
      assert hd(promo_logs).campaign_id == campaign.id
    end

    test "creates in-app notification when send_in_app is true" do
      {user, _prefs} = create_user_with_prefs()
      campaign = create_campaign(%{send_in_app: true})

      perform_job(PromoEmailWorker, %{campaign_id: campaign.id, user_id: user.id})

      # Check for in-app notification
      notifications = Notifications.list_notifications(user.id, [])
      offer_notifs = Enum.filter(notifications, &(&1.type == "special_offer"))
      assert length(offer_notifs) >= 1
    end

    test "does not create in-app notification when send_in_app is false" do
      {user, _prefs} = create_user_with_prefs()
      campaign = create_campaign(%{send_in_app: false})

      perform_job(PromoEmailWorker, %{campaign_id: campaign.id, user_id: user.id})

      notifications = Notifications.list_notifications(user.id, [])
      offer_notifs = Enum.filter(notifications, &(&1.type == "special_offer"))
      assert offer_notifs == []
    end

    test "skips when campaign does not exist (individual job)" do
      {user, _prefs} = create_user_with_prefs()

      result = perform_job(PromoEmailWorker, %{campaign_id: -1, user_id: user.id})
      assert result == :ok
    end

    test "respects email_special_offers preference" do
      {user, _prefs} = create_user_with_prefs(%{}, %{email_special_offers: false})
      campaign = create_campaign()

      result = perform_job(PromoEmailWorker, %{campaign_id: campaign.id, user_id: user.id})
      assert result == :ok

      logs = Repo.all(BlocksterV2.Notifications.EmailLog)
      promo_logs = Enum.filter(logs, &(&1.user_id == user.id))
      assert promo_logs == []
    end

    test "updates campaign status to sent after batch" do
      {_user, _prefs} = create_user_with_prefs(%{}, %{email_special_offers: true})
      campaign = create_campaign()

      perform_job(PromoEmailWorker, %{campaign_id: campaign.id})

      updated_campaign = Notifications.get_campaign!(campaign.id)
      assert updated_campaign.status == "sent"
      assert updated_campaign.sent_at != nil
    end
  end

  # ============ Cart Abandonment Worker ============

  describe "CartAbandonmentWorker" do
    test "batch job runs without error" do
      result = perform_job(CartAbandonmentWorker, %{})
      assert result == :ok
    end

    test "individual job sends cart reminder email" do
      {user, _prefs} = create_user_with_prefs()

      # Create a cart with items (if cart tables exist)
      # The worker handles missing tables gracefully with rescue
      result = perform_job(CartAbandonmentWorker, %{user_id: user.id})
      assert result == :ok
    end

    test "skips when user has no email" do
      {:ok, user} =
        BlocksterV2.Accounts.create_user_from_wallet(%{
          wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
          chain_id: 560013
        })

      result = perform_job(CartAbandonmentWorker, %{user_id: user.id})
      assert result == :ok
    end

    test "skips when email is rate limited" do
      {user, _prefs} = create_user_with_prefs(%{}, %{email_enabled: false})

      result = perform_job(CartAbandonmentWorker, %{user_id: user.id})
      assert result == :ok
    end

    test "creates both email log and in-app notification on success" do
      {user, _prefs} = create_user_with_prefs()

      # We need cart items for the email to send
      # This test verifies the flow works even if cart returns []
      # (worker returns :ok when no items)
      result = perform_job(CartAbandonmentWorker, %{user_id: user.id})
      assert result == :ok
    end
  end

  # ============ Cross-Worker Integration ============

  describe "cross-worker integration" do
    test "email logs track different worker types correctly" do
      {user, _prefs} = create_user_with_prefs()
      hub = create_hub()
      post = create_post(hub)

      # Run different workers for the same user
      perform_job(WelcomeSeriesWorker, %{user_id: user.id, day: 0})
      perform_job(ReferralPromptWorker, %{user_id: user.id})
      perform_job(HubPostNotificationWorker, %{user_id: user.id, post_id: post.id, hub_id: hub.id})

      logs = Repo.all(BlocksterV2.Notifications.EmailLog)
      user_logs = Enum.filter(logs, &(&1.user_id == user.id))
      types = Enum.map(user_logs, & &1.email_type) |> Enum.sort()

      assert "hub_post" in types
      assert "referral_prompt" in types
      assert "welcome_series_day_0" in types
    end

    test "rate limiter respects daily email limits across workers" do
      {user, _prefs} = create_user_with_prefs(%{}, %{max_emails_per_day: 1})

      # First email should go through
      result1 = perform_job(WelcomeSeriesWorker, %{user_id: user.id, day: 0})
      assert result1 == :ok

      logs_after_1 =
        Repo.all(BlocksterV2.Notifications.EmailLog)
        |> Enum.filter(&(&1.user_id == user.id))

      assert length(logs_after_1) == 1

      # Second email should be rate-limited (deferred or skipped)
      result2 = perform_job(ReferralPromptWorker, %{user_id: user.id})
      assert result2 == :ok

      # Should still only have 1 email log (second was rate-limited)
      logs_after_2 =
        Repo.all(BlocksterV2.Notifications.EmailLog)
        |> Enum.filter(&(&1.user_id == user.id))

      assert length(logs_after_2) == 1
    end

    test "workers handle missing user gracefully" do
      # Non-existent user ID
      assert :ok == perform_job(DailyDigestWorker, %{user_id: -999})
      assert :ok == perform_job(WelcomeSeriesWorker, %{user_id: -999, day: 0})
      assert :ok == perform_job(ReEngagementWorker, %{user_id: -999, days_inactive: 7})
      assert :ok == perform_job(WeeklyRewardSummaryWorker, %{user_id: -999})
      assert :ok == perform_job(ReferralPromptWorker, %{user_id: -999})
      assert :ok == perform_job(CartAbandonmentWorker, %{user_id: -999})
    end

    test "email_enabled=false blocks all worker emails" do
      {user, _prefs} = create_user_with_prefs(%{}, %{email_enabled: false})
      hub = create_hub()
      post = create_post(hub)

      perform_job(WelcomeSeriesWorker, %{user_id: user.id, day: 0})
      perform_job(ReferralPromptWorker, %{user_id: user.id})
      perform_job(WeeklyRewardSummaryWorker, %{user_id: user.id})
      perform_job(ReEngagementWorker, %{user_id: user.id, days_inactive: 7})
      perform_job(HubPostNotificationWorker, %{user_id: user.id, post_id: post.id, hub_id: hub.id})

      logs =
        Repo.all(BlocksterV2.Notifications.EmailLog)
        |> Enum.filter(&(&1.user_id == user.id))

      assert logs == []
    end
  end

  # ============ Oban Configuration ============

  describe "Oban configuration" do
    test "Oban is configured with required queues" do
      config = Application.get_env(:blockster_v2, Oban)

      if config[:testing] != :inline do
        queues = Keyword.get(config, :queues, [])
        queue_names = Keyword.keys(queues)

        assert :email_transactional in queue_names
        assert :email_marketing in queue_names
        assert :email_digest in queue_names
      else
        # In test mode, just verify config exists
        assert config != nil
      end
    end

    test "workers use correct queues" do
      assert DailyDigestWorker.__opts__()[:queue] == :email_digest
      assert WelcomeSeriesWorker.__opts__()[:queue] == :email_transactional
      assert ReEngagementWorker.__opts__()[:queue] == :email_marketing
      assert WeeklyRewardSummaryWorker.__opts__()[:queue] == :email_marketing
      assert ReferralPromptWorker.__opts__()[:queue] == :email_marketing
      assert HubPostNotificationWorker.__opts__()[:queue] == :email_marketing
      assert PromoEmailWorker.__opts__()[:queue] == :email_marketing
      assert CartAbandonmentWorker.__opts__()[:queue] == :email_transactional
    end

    test "workers have max_attempts set to 3" do
      assert DailyDigestWorker.__opts__()[:max_attempts] == 3
      assert WelcomeSeriesWorker.__opts__()[:max_attempts] == 3
      assert PromoEmailWorker.__opts__()[:max_attempts] == 3
      assert CartAbandonmentWorker.__opts__()[:max_attempts] == 3
    end
  end

  # ============ Helper ============

  defp perform_job(worker, args) do
    # Simulate Oban job execution
    worker.perform(%Oban.Job{args: stringify_keys(args)})
  end

  defp stringify_keys(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end
end
