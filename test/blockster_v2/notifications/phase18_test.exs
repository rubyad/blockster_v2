defmodule BlocksterV2.Notifications.Phase18Test do
  use BlocksterV2.DataCase, async: true

  alias BlocksterV2.{Repo, UserEvents, Notifications}
  alias BlocksterV2.Notifications.{
    SendTimeOptimizer,
    DeliverabilityMonitor,
    ViralCoefficientTracker,
    PriceAlertEngine,
    EmailLog,
    UserProfile
  }

  # ============ Test Helpers ============

  defp create_user(_context \\ %{}) do
    {:ok, user} =
      BlocksterV2.Accounts.create_user_from_wallet(%{
        wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
        chain_id: 560013
      })

    %{user: user}
  end

  defp create_profile(user_id, attrs \\ %{}) do
    defaults = %{
      engagement_tier: "active",
      engagement_score: 50.0,
      churn_risk_score: 0.2,
      churn_risk_level: "low"
    }

    merged = Map.merge(defaults, attrs)
    {:ok, profile} = UserEvents.upsert_profile(user_id, merged)
    profile
  end

  defp create_email_log(user_id, attrs \\ %{}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # Split into changeset-castable fields and extra fields
    {extra_fields, base_attrs} =
      Map.merge(%{
        user_id: user_id,
        email_type: "daily_digest",
        subject: "Test Subject",
        sent_at: now
      }, attrs)
      |> Map.split([:opened_at, :clicked_at, :bounced])

    changeset =
      %EmailLog{}
      |> EmailLog.changeset(base_attrs)

    # Manually put_change for fields not in the changeset cast list
    changeset =
      Enum.reduce(extra_fields, changeset, fn {key, val}, cs ->
        Ecto.Changeset.put_change(cs, key, val)
      end)

    {:ok, log} = Repo.insert(changeset)
    log
  end

  # ============ SendTimeOptimizer ============

  describe "SendTimeOptimizer.optimal_send_hour/1" do
    test "returns user's best hour when available" do
      %{user: user} = create_user()
      create_profile(user.id, %{best_email_hour_utc: 14})

      assert SendTimeOptimizer.optimal_send_hour(user.id) == 14
    end

    test "returns default when user has no profile" do
      %{user: user} = create_user()

      hour = SendTimeOptimizer.optimal_send_hour(user.id)
      assert is_integer(hour)
      assert hour >= 0 and hour <= 23
    end
  end

  describe "SendTimeOptimizer.optimal_send_hour_from_profile/1" do
    test "returns best hour from profile" do
      %{user: user} = create_user()
      profile = create_profile(user.id, %{best_email_hour_utc: 9})

      assert SendTimeOptimizer.optimal_send_hour_from_profile(profile) == 9
    end

    test "returns default for nil profile" do
      assert SendTimeOptimizer.optimal_send_hour_from_profile(nil) == 10
    end

    test "returns default when profile has no best hour" do
      %{user: user} = create_user()
      profile = create_profile(user.id, %{best_email_hour_utc: nil})

      assert SendTimeOptimizer.optimal_send_hour_from_profile(profile) == 10
    end
  end

  describe "SendTimeOptimizer.delay_until_optimal/1" do
    test "returns non-negative delay" do
      %{user: user} = create_user()
      create_profile(user.id, %{best_email_hour_utc: 14})

      delay = SendTimeOptimizer.delay_until_optimal(user.id)
      assert is_integer(delay)
      assert delay >= 0
    end
  end

  describe "SendTimeOptimizer.delay_from_profile/1" do
    test "returns 0 when optimal hour matches current" do
      current_hour = DateTime.utc_now().hour

      %{user: user} = create_user()
      profile = create_profile(user.id, %{best_email_hour_utc: current_hour})

      assert SendTimeOptimizer.delay_from_profile(profile) == 0
    end

    test "returns positive delay when optimal hour is later" do
      # Pick a time in the future
      future_hour = rem(DateTime.utc_now().hour + 3, 24)

      %{user: user} = create_user()
      profile = create_profile(user.id, %{best_email_hour_utc: future_hour})

      delay = SendTimeOptimizer.delay_from_profile(profile)
      assert delay >= 0
    end
  end

  describe "SendTimeOptimizer.has_sufficient_data?/1" do
    test "returns false for user with no email logs" do
      %{user: user} = create_user()
      refute SendTimeOptimizer.has_sufficient_data?(user.id)
    end

    test "returns true for user with enough opened emails" do
      %{user: user} = create_user()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      for _i <- 1..6 do
        create_email_log(user.id, %{opened_at: now})
      end

      assert SendTimeOptimizer.has_sufficient_data?(user.id)
    end
  end

  describe "SendTimeOptimizer.hourly_engagement_distribution/1" do
    test "returns empty map for user with no opens" do
      %{user: user} = create_user()
      assert SendTimeOptimizer.hourly_engagement_distribution(user.id) == %{}
    end

    test "returns hour => count map" do
      %{user: user} = create_user()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      for _ <- 1..3 do
        create_email_log(user.id, %{opened_at: now})
      end

      dist = SendTimeOptimizer.hourly_engagement_distribution(user.id)
      assert is_map(dist)
      assert map_size(dist) >= 1
    end
  end

  describe "SendTimeOptimizer.optimization_stats/0" do
    test "returns stats map" do
      %{user: user} = create_user()
      create_profile(user.id, %{best_email_hour_utc: 14})

      %{user: user2} = create_user()
      create_profile(user2.id, %{best_email_hour_utc: nil})

      stats = SendTimeOptimizer.optimization_stats()

      assert is_map(stats)
      assert stats.users_optimized >= 1
      assert stats.users_default >= 1
      assert is_integer(stats.population_best_hour)
    end
  end

  # ============ DeliverabilityMonitor ============

  describe "DeliverabilityMonitor.calculate_metrics/1" do
    test "returns zeros when no emails sent" do
      metrics = DeliverabilityMonitor.calculate_metrics(7)

      assert metrics.sent == 0
      assert metrics.bounce_rate == 0.0
      assert metrics.open_rate == 0.0
    end

    test "calculates correct rates" do
      %{user: user} = create_user()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      # 3 sent, 1 bounced, 2 opened, 1 clicked
      create_email_log(user.id, %{bounced: true})
      create_email_log(user.id, %{opened_at: now, clicked_at: now})
      create_email_log(user.id, %{opened_at: now})

      metrics = DeliverabilityMonitor.calculate_metrics(7)

      assert metrics.sent == 3
      assert metrics.bounced == 1
      assert metrics.opened == 2
      assert metrics.clicked == 1
      assert_in_delta metrics.bounce_rate, 0.3333, 0.01
      assert_in_delta metrics.open_rate, 0.6667, 0.01
    end
  end

  describe "DeliverabilityMonitor.metrics_by_type/1" do
    test "returns metrics grouped by email type" do
      %{user: user} = create_user()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      create_email_log(user.id, %{email_type: "daily_digest", opened_at: now})
      create_email_log(user.id, %{email_type: "daily_digest"})
      create_email_log(user.id, %{email_type: "welcome"})

      by_type = DeliverabilityMonitor.metrics_by_type(7)

      assert length(by_type) >= 2
      digest = Enum.find(by_type, fn t -> t.email_type == "daily_digest" end)
      assert digest.sent == 2
      assert digest.opened == 1
    end
  end

  describe "DeliverabilityMonitor.check_alerts/1" do
    test "returns no alerts for healthy metrics" do
      %{user: user} = create_user()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      # Good metrics: all opened, none bounced
      for _ <- 1..20 do
        create_email_log(user.id, %{opened_at: now})
      end

      alerts = DeliverabilityMonitor.check_alerts(7)
      assert alerts == []
    end

    test "returns bounce rate alert" do
      %{user: user} = create_user()

      # 10 sent, 2 bounced = 20% bounce rate
      for _ <- 1..8 do
        create_email_log(user.id)
      end
      for _ <- 1..2 do
        create_email_log(user.id, %{bounced: true})
      end

      alerts = DeliverabilityMonitor.check_alerts(7)

      bounce_alert = Enum.find(alerts, fn a -> a.type == "high_bounce_rate" end)
      assert bounce_alert != nil
      assert bounce_alert.severity == "critical"
    end

    test "returns low open rate alert" do
      %{user: user} = create_user()

      # 20 sent, none opened
      for _ <- 1..20 do
        create_email_log(user.id)
      end

      alerts = DeliverabilityMonitor.check_alerts(7)

      open_alert = Enum.find(alerts, fn a -> a.type == "low_open_rate" end)
      assert open_alert != nil
    end
  end

  describe "DeliverabilityMonitor.health_score/1" do
    test "returns 100 when no emails sent" do
      assert DeliverabilityMonitor.health_score(7) == 100.0
    end

    test "returns high score for good metrics" do
      %{user: user} = create_user()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      for _ <- 1..10 do
        create_email_log(user.id, %{opened_at: now, clicked_at: now})
      end

      score = DeliverabilityMonitor.health_score(7)
      assert score > 50.0
    end

    test "returns low score for poor metrics" do
      %{user: user} = create_user()

      # All bounced, none opened
      for _ <- 1..10 do
        create_email_log(user.id, %{bounced: true})
      end

      score = DeliverabilityMonitor.health_score(7)
      assert score <= 40.0
    end
  end

  describe "DeliverabilityMonitor.daily_send_volume/1" do
    test "returns send counts by date" do
      %{user: user} = create_user()

      for _ <- 1..3 do
        create_email_log(user.id)
      end

      volume = DeliverabilityMonitor.daily_send_volume(7)
      assert length(volume) >= 1
      assert List.first(volume).count >= 3
    end
  end

  describe "DeliverabilityMonitor.recent_bounces/1" do
    test "returns empty list when no bounces" do
      assert DeliverabilityMonitor.recent_bounces() == []
    end

    test "returns bounced emails" do
      %{user: user} = create_user()
      create_email_log(user.id, %{bounced: true})
      create_email_log(user.id, %{bounced: true})

      bounces = DeliverabilityMonitor.recent_bounces()
      assert length(bounces) == 2
    end
  end

  # ============ ViralCoefficientTracker ============

  describe "ViralCoefficientTracker.calculate_k_factor/0" do
    test "returns 0 when no referrers" do
      result = ViralCoefficientTracker.calculate_k_factor()
      assert result.k_factor == 0.0
    end

    test "calculates K-factor from referral data" do
      %{user: u1} = create_user()
      create_profile(u1.id, %{referrals_sent: 10, referrals_converted: 3})

      %{user: u2} = create_user()
      create_profile(u2.id, %{referrals_sent: 5, referrals_converted: 2})

      result = ViralCoefficientTracker.calculate_k_factor()

      assert result.k_factor > 0.0
      assert result.total_referrers == 2
      assert result.total_sent == 15
      assert result.total_converted == 5
      assert result.avg_invites > 0.0
      assert result.conversion_rate > 0.0
    end
  end

  describe "ViralCoefficientTracker.is_viral?/1" do
    test "returns boolean result" do
      result = ViralCoefficientTracker.is_viral?()
      assert is_boolean(result)
    end

    test "uses configurable threshold" do
      %{user: user} = create_user()
      create_profile(user.id, %{referrals_sent: 5, referrals_converted: 2})

      # With a very high threshold, should be false
      refute ViralCoefficientTracker.is_viral?(100.0)
    end

    test "k_factor calculation matches is_viral?" do
      %{k_factor: k} = ViralCoefficientTracker.calculate_k_factor()
      assert ViralCoefficientTracker.is_viral?(k + 0.01) == false || k == 0.0
    end
  end

  describe "ViralCoefficientTracker.top_referrers/1" do
    test "returns top referrers sorted by conversions" do
      %{user: u1} = create_user()
      create_profile(u1.id, %{referrals_sent: 20, referrals_converted: 10})

      %{user: u2} = create_user()
      create_profile(u2.id, %{referrals_sent: 5, referrals_converted: 3})

      top = ViralCoefficientTracker.top_referrers(5)

      assert length(top) == 2
      assert List.first(top).referrals_converted == 10
      assert List.first(top).personal_conversion_rate == 0.5
    end

    test "excludes users with 0 conversions" do
      %{user: user} = create_user()
      create_profile(user.id, %{referrals_sent: 10, referrals_converted: 0})

      top = ViralCoefficientTracker.top_referrers()
      user_ids = Enum.map(top, & &1.user_id)
      refute user.id in user_ids
    end
  end

  describe "ViralCoefficientTracker.referral_funnel/0" do
    test "returns funnel metrics" do
      %{user: u1} = create_user()
      create_profile(u1.id, %{referrals_sent: 5, referrals_converted: 2})

      %{user: u2} = create_user()
      create_profile(u2.id, %{referrals_sent: 0, referrals_converted: 0})

      funnel = ViralCoefficientTracker.referral_funnel()

      assert funnel.total_users >= 2
      assert funnel.users_who_shared >= 1
      assert funnel.users_who_converted >= 1
      assert funnel.share_rate > 0.0
      assert funnel.conversion_rate > 0.0
    end
  end

  # ============ PriceAlertEngine ============

  describe "PriceAlertEngine.evaluate_price_change/2" do
    test "returns skip for small changes" do
      assert :skip = PriceAlertEngine.evaluate_price_change(1.0, 1.03)
    end

    test "returns significant for 5-10% changes" do
      {:fire, alert} = PriceAlertEngine.evaluate_price_change(1.0, 1.07)
      assert alert.severity == "significant"
      assert alert.direction == "up"
      assert_in_delta alert.change_pct, 7.0, 0.1
    end

    test "returns major for 10%+ changes" do
      {:fire, alert} = PriceAlertEngine.evaluate_price_change(1.0, 1.15)
      assert alert.severity == "major"
      assert alert.direction == "up"
    end

    test "detects price drops" do
      {:fire, alert} = PriceAlertEngine.evaluate_price_change(1.0, 0.88)
      assert alert.direction == "down"
      assert alert.change_pct < 0
    end

    test "returns skip for invalid prices" do
      assert :skip = PriceAlertEngine.evaluate_price_change(0, 1.0)
      assert :skip = PriceAlertEngine.evaluate_price_change(nil, 1.0)
    end
  end

  describe "PriceAlertEngine.price_alert_copy/1" do
    test "generates surge copy for major up" do
      {title, body} = PriceAlertEngine.price_alert_copy(%{
        direction: "up",
        severity: "major",
        change_pct: 15.0
      })

      assert title =~ "surging"
      assert body =~ "jumped"
    end

    test "generates dip copy for major down" do
      {title, body} = PriceAlertEngine.price_alert_copy(%{
        direction: "down",
        severity: "major",
        change_pct: -12.0
      })

      assert title =~ "dipped"
      assert body =~ "entry point"
    end

    test "generates mild copy for significant up" do
      {title, _body} = PriceAlertEngine.price_alert_copy(%{
        direction: "up",
        severity: "significant",
        change_pct: 6.0
      })

      assert title =~ "up"
    end
  end

  describe "PriceAlertEngine.get_alert_eligible_users/0" do
    test "returns users in ROGUE conversion stages" do
      %{user: u1} = create_user()
      create_profile(u1.id, %{conversion_stage: "rogue_curious"})

      %{user: u2} = create_user()
      create_profile(u2.id, %{conversion_stage: "earner"})

      eligible = PriceAlertEngine.get_alert_eligible_users()
      user_ids = Enum.map(eligible, & &1.user_id)

      assert u1.id in user_ids
      refute u2.id in user_ids
    end
  end

  describe "PriceAlertEngine.fire_price_notification/2" do
    test "creates price alert notification" do
      %{user: user} = create_user()

      alert_data = %{
        severity: "major",
        direction: "up",
        change_pct: 15.0,
        old_price: 0.00005,
        new_price: 0.0000575
      }

      {:ok, notif} = PriceAlertEngine.fire_price_notification(user.id, alert_data)

      assert notif.type == "price_drop"
      assert notif.category == "rewards"
      assert notif.title =~ "surging"
      assert notif.metadata[:severity] == "major"
    end
  end

  describe "PriceAlertEngine.price_alert_sent_recently?/1" do
    test "returns false when no recent alerts" do
      %{user: user} = create_user()
      refute PriceAlertEngine.price_alert_sent_recently?(user.id)
    end

    test "returns true after alert sent today" do
      %{user: user} = create_user()

      PriceAlertEngine.fire_price_notification(user.id, %{
        severity: "major",
        direction: "up",
        change_pct: 15.0,
        old_price: 0.00005,
        new_price: 0.0000575
      })

      assert PriceAlertEngine.price_alert_sent_recently?(user.id)
    end
  end

  describe "PriceAlertEngine.fire_price_alerts/1" do
    test "sends alerts to eligible users only" do
      %{user: u1} = create_user()
      create_profile(u1.id, %{conversion_stage: "rogue_buyer"})

      %{user: u2} = create_user()
      create_profile(u2.id, %{conversion_stage: "earner"})

      alert_data = %{
        severity: "major",
        direction: "up",
        change_pct: 12.0,
        old_price: 0.00005,
        new_price: 0.000056
      }

      count = PriceAlertEngine.fire_price_alerts(alert_data)
      assert count >= 1

      # u1 should have notification, u2 should not
      u1_notifs = Notifications.list_notifications(u1.id, limit: 10)
      u2_notifs = Notifications.list_notifications(u2.id, limit: 10)

      assert Enum.any?(u1_notifs, fn n -> n.type == "price_drop" end)
      refute Enum.any?(u2_notifs, fn n -> n.type == "price_drop" end)
    end

    test "deduplicates alerts within same day" do
      %{user: user} = create_user()
      create_profile(user.id, %{conversion_stage: "rogue_curious"})

      alert_data = %{
        severity: "significant",
        direction: "down",
        change_pct: -7.0,
        old_price: 0.00006,
        new_price: 0.0000558
      }

      count1 = PriceAlertEngine.fire_price_alerts(alert_data)
      count2 = PriceAlertEngine.fire_price_alerts(alert_data)

      assert count1 >= 1
      assert count2 == 0
    end
  end

  # ============ Integration Tests ============

  describe "send-time + deliverability integration" do
    test "optimization stats and health score are consistent" do
      %{user: user} = create_user()
      create_profile(user.id, %{best_email_hour_utc: 14})

      now = DateTime.utc_now() |> DateTime.truncate(:second)
      for _ <- 1..5 do
        create_email_log(user.id, %{opened_at: now, clicked_at: now})
      end

      opt_stats = SendTimeOptimizer.optimization_stats()
      assert opt_stats.users_optimized >= 1

      health = DeliverabilityMonitor.health_score(7)
      assert health >= 40.0

      # User has sufficient data for optimization
      assert SendTimeOptimizer.has_sufficient_data?(user.id)
    end
  end

  describe "viral coefficient + price alerts integration" do
    test "referral funnel and price alert eligibility are independent" do
      %{user: user} = create_user()
      create_profile(user.id, %{
        referrals_sent: 5,
        referrals_converted: 2,
        conversion_stage: "rogue_buyer"
      })

      # Appears in referral funnel
      funnel = ViralCoefficientTracker.referral_funnel()
      assert funnel.users_who_shared >= 1

      # Also eligible for price alerts
      eligible = PriceAlertEngine.get_alert_eligible_users()
      user_ids = Enum.map(eligible, & &1.user_id)
      assert user.id in user_ids
    end
  end
end
