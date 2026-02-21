defmodule BlocksterV2.Notifications.Phase17Test do
  use BlocksterV2.DataCase, async: true

  alias BlocksterV2.{Repo, UserEvents, Notifications}
  alias BlocksterV2.Notifications.{ChurnPredictor, RevivalEngine, UserProfile, UserEvent}
  alias BlocksterV2.Workers.ChurnDetectionWorker

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
      churn_risk_level: "low",
      days_since_last_active: 0,
      avg_sessions_per_week: 3.0,
      avg_session_duration_ms: 120_000,
      email_open_rate_30d: 0.5,
      email_click_rate_30d: 0.3,
      notification_fatigue_score: 0.1,
      articles_read_last_7d: 5,
      articles_read_last_30d: 15,
      total_articles_read: 30,
      content_completion_rate: 0.7,
      purchase_count: 1,
      referrals_converted: 1,
      preferred_hubs: [%{"name" => "Crypto News", "id" => 1}],
      consecutive_active_days: 5,
      games_played_last_30d: 0,
      total_bets_placed: 0,
      shop_interest_score: 0.3,
      referral_propensity: 0.4
    }

    merged = Map.merge(defaults, attrs)
    {:ok, profile} = UserEvents.upsert_profile(user_id, merged)
    profile
  end

  # ============ ChurnPredictor: Individual Signals ============

  describe "ChurnPredictor.frequency_decline_signal/1" do
    test "returns low risk for active users" do
      %{user: user} = create_user()
      profile = create_profile(user.id, %{avg_sessions_per_week: 5.0, days_since_last_active: 0})

      signal = ChurnPredictor.frequency_decline_signal(profile)
      assert signal < 0.3
    end

    test "returns high risk for inactive users" do
      %{user: user} = create_user()
      profile = create_profile(user.id, %{avg_sessions_per_week: 0.5, days_since_last_active: 20})

      signal = ChurnPredictor.frequency_decline_signal(profile)
      assert signal > 0.6
    end
  end

  describe "ChurnPredictor.session_shortening_signal/1" do
    test "returns low risk for long sessions" do
      %{user: user} = create_user()
      profile = create_profile(user.id, %{avg_session_duration_ms: 300_000})

      assert ChurnPredictor.session_shortening_signal(profile) == 0.0
    end

    test "returns high risk for very short sessions" do
      %{user: user} = create_user()
      profile = create_profile(user.id, %{avg_session_duration_ms: 20_000})

      assert ChurnPredictor.session_shortening_signal(profile) == 0.8
    end

    test "returns medium risk for no session data" do
      %{user: user} = create_user()
      profile = create_profile(user.id, %{avg_session_duration_ms: 0})

      assert ChurnPredictor.session_shortening_signal(profile) == 0.5
    end
  end

  describe "ChurnPredictor.email_engagement_signal/1" do
    test "returns low risk for high email engagement" do
      %{user: user} = create_user()
      profile = create_profile(user.id, %{email_open_rate_30d: 0.8, email_click_rate_30d: 0.6})

      signal = ChurnPredictor.email_engagement_signal(profile)
      assert signal < 0.3
    end

    test "returns high risk for no email engagement" do
      %{user: user} = create_user()
      profile = create_profile(user.id, %{email_open_rate_30d: 0.0, email_click_rate_30d: 0.0})

      signal = ChurnPredictor.email_engagement_signal(profile)
      assert signal == 1.0
    end
  end

  describe "ChurnPredictor.discovery_stall_signal/1" do
    test "returns high risk for no hub preferences" do
      %{user: user} = create_user()
      profile = create_profile(user.id, %{preferred_hubs: []})

      assert ChurnPredictor.discovery_stall_signal(profile) == 0.8
    end

    test "returns no risk for diverse hub preferences" do
      %{user: user} = create_user()
      hubs = [%{"name" => "A"}, %{"name" => "B"}, %{"name" => "C"}]
      profile = create_profile(user.id, %{preferred_hubs: hubs})

      assert ChurnPredictor.discovery_stall_signal(profile) == 0.0
    end
  end

  describe "ChurnPredictor.bux_earning_decline_signal/1" do
    test "returns low risk when recent activity matches average" do
      %{user: user} = create_user()
      profile = create_profile(user.id, %{articles_read_last_7d: 4, articles_read_last_30d: 16})

      signal = ChurnPredictor.bux_earning_decline_signal(profile)
      assert signal < 0.2
    end

    test "returns high risk when recent activity dropped" do
      %{user: user} = create_user()
      profile = create_profile(user.id, %{articles_read_last_7d: 0, articles_read_last_30d: 20})

      signal = ChurnPredictor.bux_earning_decline_signal(profile)
      assert signal == 1.0
    end
  end

  describe "ChurnPredictor.no_purchases_signal/1" do
    test "returns 0.3 for users with no purchases" do
      %{user: user} = create_user()
      profile = create_profile(user.id, %{purchase_count: 0})

      assert ChurnPredictor.no_purchases_signal(profile) == 0.3
    end

    test "returns 0.0 for users with purchases" do
      %{user: user} = create_user()
      profile = create_profile(user.id, %{purchase_count: 2})

      assert ChurnPredictor.no_purchases_signal(profile) == 0.0
    end
  end

  describe "ChurnPredictor.no_referrals_signal/1" do
    test "returns 0.2 for users with no referrals" do
      %{user: user} = create_user()
      profile = create_profile(user.id, %{referrals_converted: 0})

      assert ChurnPredictor.no_referrals_signal(profile) == 0.2
    end

    test "returns 0.0 for users with referrals" do
      %{user: user} = create_user()
      profile = create_profile(user.id, %{referrals_converted: 3})

      assert ChurnPredictor.no_referrals_signal(profile) == 0.0
    end
  end

  # ============ ChurnPredictor: Aggregate & Classification ============

  describe "ChurnPredictor.aggregate_signals/1" do
    test "returns low score for healthy signals" do
      signals = %{
        frequency_decline: 0.1,
        session_shortening: 0.0,
        email_engagement_decline: 0.2,
        discovery_stall: 0.0,
        bux_earning_decline: 0.1,
        notification_fatigue: 0.0,
        no_purchases: 0.0,
        no_referrals: 0.0
      }

      score = ChurnPredictor.aggregate_signals(signals)
      assert score < 0.2
    end

    test "returns high score for risky signals" do
      signals = %{
        frequency_decline: 0.9,
        session_shortening: 0.8,
        email_engagement_decline: 0.9,
        discovery_stall: 0.8,
        bux_earning_decline: 0.9,
        notification_fatigue: 0.8,
        no_purchases: 0.3,
        no_referrals: 0.2
      }

      score = ChurnPredictor.aggregate_signals(signals)
      assert score > 0.7
    end

    test "score is capped at 1.0" do
      signals = %{
        frequency_decline: 1.0,
        session_shortening: 1.0,
        email_engagement_decline: 1.0,
        discovery_stall: 1.0,
        bux_earning_decline: 1.0,
        notification_fatigue: 1.0,
        no_purchases: 1.0,
        no_referrals: 1.0
      }

      score = ChurnPredictor.aggregate_signals(signals)
      assert score == 1.0
    end
  end

  describe "ChurnPredictor.classify_risk_level/1" do
    test "classifies healthy" do
      assert ChurnPredictor.classify_risk_level(0.1) == "healthy"
    end

    test "classifies watch" do
      assert ChurnPredictor.classify_risk_level(0.4) == "watch"
    end

    test "classifies at_risk" do
      assert ChurnPredictor.classify_risk_level(0.6) == "at_risk"
    end

    test "classifies critical" do
      assert ChurnPredictor.classify_risk_level(0.8) == "critical"
    end

    test "classifies churning" do
      assert ChurnPredictor.classify_risk_level(0.95) == "churning"
    end
  end

  describe "ChurnPredictor.get_risk_tier/1" do
    test "returns correct tier for healthy score" do
      tier = ChurnPredictor.get_risk_tier(0.2)
      assert tier.status == "healthy"
      assert tier.channels == [:none]
    end

    test "returns correct tier for at_risk score" do
      tier = ChurnPredictor.get_risk_tier(0.6)
      assert tier.status == "at_risk"
      assert :email in tier.channels
    end

    test "returns correct tier for churning score" do
      tier = ChurnPredictor.get_risk_tier(0.95)
      assert tier.status == "churning"
      assert :sms in tier.channels
    end
  end

  # ============ ChurnPredictor: Intervention Selection ============

  describe "ChurnPredictor.select_intervention/2" do
    test "returns no intervention for healthy users" do
      tier = %{status: "healthy", channels: [:none]}
      %{user: user} = create_user()
      profile = create_profile(user.id)

      intervention = ChurnPredictor.select_intervention(tier, profile)
      assert intervention.type == :none
      assert intervention.channels == []
    end

    test "returns personalization for watch users" do
      tier = %{status: "watch", channels: [:personalization]}
      %{user: user} = create_user()
      profile = create_profile(user.id)

      intervention = ChurnPredictor.select_intervention(tier, profile)
      assert intervention.type == :personalization
    end

    test "returns re_engagement for at_risk users" do
      tier = %{status: "at_risk", channels: [:in_app, :email]}
      %{user: user} = create_user()
      profile = create_profile(user.id, %{days_since_last_active: 10})

      intervention = ChurnPredictor.select_intervention(tier, profile)
      assert intervention.type == :re_engagement
      assert intervention.offer.bux_bonus == 100
    end

    test "returns rescue for critical users" do
      tier = %{status: "critical", channels: [:in_app, :email, :bonus]}
      %{user: user} = create_user()
      profile = create_profile(user.id)

      intervention = ChurnPredictor.select_intervention(tier, profile)
      assert intervention.type == :rescue
      assert intervention.offer.bux_bonus == 500
    end

    test "returns all_out_save for churning users" do
      tier = %{status: "churning", channels: [:in_app, :email, :sms, :bonus]}
      %{user: user} = create_user()
      profile = create_profile(user.id)

      intervention = ChurnPredictor.select_intervention(tier, profile)
      assert intervention.type == :all_out_save
      assert intervention.offer.bux_bonus == 1000
      assert intervention.offer.free_rogue == 0.5
    end
  end

  # ============ ChurnPredictor: Full Prediction ============

  describe "ChurnPredictor.predict_churn/1" do
    test "returns full prediction for healthy user" do
      %{user: user} = create_user()
      profile = create_profile(user.id, %{
        avg_sessions_per_week: 5.0,
        days_since_last_active: 0,
        avg_session_duration_ms: 300_000,
        email_open_rate_30d: 0.8,
        email_click_rate_30d: 0.5,
        preferred_hubs: [%{"name" => "A"}, %{"name" => "B"}, %{"name" => "C"}],
        articles_read_last_7d: 5,
        articles_read_last_30d: 20,
        notification_fatigue_score: 0.0,
        purchase_count: 2,
        referrals_converted: 1
      })

      prediction = ChurnPredictor.predict_churn(profile)

      assert prediction.score < 0.3
      assert prediction.level == "healthy"
      assert is_map(prediction.signals)
      assert prediction.intervention.type == :none
    end

    test "returns full prediction for at-risk user" do
      %{user: user} = create_user()
      profile = create_profile(user.id, %{
        avg_sessions_per_week: 0.5,
        days_since_last_active: 15,
        avg_session_duration_ms: 20_000,
        email_open_rate_30d: 0.1,
        email_click_rate_30d: 0.0,
        preferred_hubs: [],
        articles_read_last_7d: 0,
        articles_read_last_30d: 10,
        notification_fatigue_score: 0.7,
        purchase_count: 0,
        referrals_converted: 0
      })

      prediction = ChurnPredictor.predict_churn(profile)

      assert prediction.score > 0.5
      assert prediction.level in ["at_risk", "critical", "churning"]
      assert prediction.intervention.type in [:re_engagement, :rescue, :all_out_save]
    end
  end

  describe "ChurnPredictor.fire_intervention/2" do
    test "creates notification for at-risk prediction" do
      %{user: user} = create_user()
      profile = create_profile(user.id, %{days_since_last_active: 10})

      prediction = %{
        score: 0.6,
        level: "at_risk",
        signals: %{},
        intervention: %{
          type: :re_engagement,
          channels: [:in_app, :email],
          message: "We miss you!",
          offer: %{bux_bonus: 100}
        }
      }

      {:ok, notif} = ChurnPredictor.fire_intervention(user.id, prediction)

      assert notif.type == "churn_intervention"
      assert notif.category == "system"
      assert notif.metadata[:churn_level] == "at_risk"
    end

    test "skips for healthy prediction" do
      prediction = %{
        score: 0.1,
        level: "healthy",
        signals: %{},
        intervention: %{type: :none, channels: [], message: nil, offer: nil}
      }

      assert :skip = ChurnPredictor.fire_intervention(1, prediction)
    end
  end

  describe "ChurnPredictor.intervention_sent_recently?/2" do
    test "returns false when no recent interventions" do
      %{user: user} = create_user()
      refute ChurnPredictor.intervention_sent_recently?(user.id)
    end

    test "returns true when recent intervention exists" do
      %{user: user} = create_user()

      Notifications.create_notification(user.id, %{
        type: "churn_intervention",
        category: "system",
        title: "We miss you"
      })

      assert ChurnPredictor.intervention_sent_recently?(user.id)
    end
  end

  describe "ChurnPredictor.get_at_risk_users/1" do
    test "returns users above score threshold" do
      %{user: u1} = create_user()
      create_profile(u1.id, %{churn_risk_score: 0.7, churn_risk_level: "critical"})

      %{user: u2} = create_user()
      create_profile(u2.id, %{churn_risk_score: 0.2, churn_risk_level: "low"})

      at_risk = ChurnPredictor.get_at_risk_users(0.5)
      user_ids = Enum.map(at_risk, & &1.user_id)

      assert u1.id in user_ids
      refute u2.id in user_ids
    end
  end

  # ============ RevivalEngine: User Type Classification ============

  describe "RevivalEngine.classify_user_type/1" do
    test "classifies reader" do
      %{user: user} = create_user()
      profile = create_profile(user.id, %{
        total_articles_read: 50,
        content_completion_rate: 0.8,
        games_played_last_30d: 0,
        total_bets_placed: 0,
        purchase_count: 0,
        shop_interest_score: 0.0,
        preferred_hubs: []
      })

      assert RevivalEngine.classify_user_type(profile) == "reader"
    end

    test "classifies gambler" do
      %{user: user} = create_user()
      profile = create_profile(user.id, %{
        total_articles_read: 2,
        content_completion_rate: 0.1,
        games_played_last_30d: 20,
        total_bets_placed: 50,
        purchase_count: 0,
        shop_interest_score: 0.0,
        preferred_hubs: []
      })

      assert RevivalEngine.classify_user_type(profile) == "gambler"
    end

    test "classifies shopper" do
      %{user: user} = create_user()
      profile = create_profile(user.id, %{
        total_articles_read: 2,
        content_completion_rate: 0.1,
        games_played_last_30d: 0,
        total_bets_placed: 0,
        purchase_count: 5,
        shop_interest_score: 0.8,
        preferred_hubs: []
      })

      assert RevivalEngine.classify_user_type(profile) == "shopper"
    end

    test "classifies hub_subscriber" do
      %{user: user} = create_user()
      profile = create_profile(user.id, %{
        total_articles_read: 2,
        content_completion_rate: 0.1,
        games_played_last_30d: 0,
        total_bets_placed: 0,
        purchase_count: 0,
        shop_interest_score: 0.0,
        preferred_hubs: [%{"name" => "A"}, %{"name" => "B"}, %{"name" => "C"}, %{"name" => "D"}, %{"name" => "E"}]
      })

      assert RevivalEngine.classify_user_type(profile) == "hub_subscriber"
    end

    test "returns general for users with no strong signals" do
      %{user: user} = create_user()
      profile = create_profile(user.id, %{
        total_articles_read: 0,
        content_completion_rate: 0.0,
        games_played_last_30d: 0,
        total_bets_placed: 0,
        purchase_count: 0,
        shop_interest_score: 0.0,
        preferred_hubs: []
      })

      assert RevivalEngine.classify_user_type(profile) == "general"
    end
  end

  # ============ RevivalEngine: Revival Stages ============

  describe "RevivalEngine.revival_stage/1" do
    test "returns 0 for recently active users" do
      assert RevivalEngine.revival_stage(1) == 0
    end

    test "returns stage 1 for 3 days away" do
      assert RevivalEngine.revival_stage(3) == 1
    end

    test "returns stage 2 for 7 days away" do
      assert RevivalEngine.revival_stage(7) == 2
    end

    test "returns stage 3 for 14 days away" do
      assert RevivalEngine.revival_stage(14) == 3
    end

    test "returns stage 4 for 30+ days away" do
      assert RevivalEngine.revival_stage(30) == 4
      assert RevivalEngine.revival_stage(60) == 4
    end
  end

  # ============ RevivalEngine: Revival Messages ============

  describe "RevivalEngine.get_revival_message/2" do
    test "returns reader stage 1 message" do
      %{user: user} = create_user()
      profile = create_profile(user.id, %{
        total_articles_read: 50,
        content_completion_rate: 0.8,
        preferred_hubs: [%{"name" => "Crypto News"}],
        games_played_last_30d: 0,
        total_bets_placed: 0,
        purchase_count: 0,
        shop_interest_score: 0.0
      })

      msg = RevivalEngine.get_revival_message(profile, 3)
      assert msg.title =~ "missed"
      assert msg.action_label == "Read Now"
    end

    test "returns reader stage 3 message with BUX offer" do
      %{user: user} = create_user()
      profile = create_profile(user.id, %{
        total_articles_read: 50,
        content_completion_rate: 0.8,
        games_played_last_30d: 0,
        total_bets_placed: 0,
        purchase_count: 0,
        shop_interest_score: 0.0,
        preferred_hubs: []
      })

      msg = RevivalEngine.get_revival_message(profile, 14)
      assert msg.offer != nil
      assert msg.offer.bux_bonus == 200
    end

    test "returns gambler stage 2 message with free game" do
      %{user: user} = create_user()
      profile = create_profile(user.id, %{
        total_articles_read: 0,
        content_completion_rate: 0.0,
        games_played_last_30d: 20,
        total_bets_placed: 50,
        purchase_count: 0,
        shop_interest_score: 0.0,
        preferred_hubs: []
      })

      msg = RevivalEngine.get_revival_message(profile, 7)
      assert msg.title =~ "100 BUX"
      assert msg.action_url == "/play"
      assert msg.offer.bux_bonus == 100
    end

    test "returns shopper stage 3 message with discount" do
      %{user: user} = create_user()
      profile = create_profile(user.id, %{
        total_articles_read: 0,
        content_completion_rate: 0.0,
        games_played_last_30d: 0,
        total_bets_placed: 0,
        purchase_count: 5,
        shop_interest_score: 0.8,
        preferred_hubs: []
      })

      msg = RevivalEngine.get_revival_message(profile, 14)
      assert msg.title =~ "15%"
      assert msg.action_url == "/shop"
      assert msg.offer.discount_pct == 15
    end

    test "returns general fallback for unknown user types" do
      %{user: user} = create_user()
      profile = create_profile(user.id, %{
        total_articles_read: 0,
        content_completion_rate: 0.0,
        games_played_last_30d: 0,
        total_bets_placed: 0,
        purchase_count: 0,
        shop_interest_score: 0.0,
        preferred_hubs: []
      })

      msg = RevivalEngine.get_revival_message(profile, 5)
      assert msg.title =~ "missed you"
    end
  end

  # ============ RevivalEngine: Welcome Back ============

  describe "RevivalEngine.check_welcome_back/2" do
    test "returns welcome_back for user away 7+ days" do
      %{user: user} = create_user()
      profile = create_profile(user.id, %{
        days_since_last_active: 10,
        engagement_score: 60.0
      })

      {:welcome_back, data} = RevivalEngine.check_welcome_back(user.id, profile)
      assert data.days_away == 10
      assert data.bonus_bux > 0
      assert data.user_type != nil
    end

    test "returns skip for recently active user" do
      %{user: user} = create_user()
      profile = create_profile(user.id, %{days_since_last_active: 3})

      assert :skip = RevivalEngine.check_welcome_back(user.id, profile)
    end

    test "returns skip if welcome back was sent recently" do
      %{user: user} = create_user()
      profile = create_profile(user.id, %{days_since_last_active: 10})

      Notifications.create_notification(user.id, %{
        type: "welcome_back",
        category: "system",
        title: "Welcome back!"
      })

      assert :skip = RevivalEngine.check_welcome_back(user.id, profile)
    end
  end

  describe "RevivalEngine.calculate_return_bonus/2" do
    test "returns higher bonus for longer absence" do
      %{user: user} = create_user()
      profile = create_profile(user.id, %{engagement_score: 40.0})

      bonus_7d = RevivalEngine.calculate_return_bonus(7, profile)
      bonus_14d = RevivalEngine.calculate_return_bonus(14, profile)
      bonus_30d = RevivalEngine.calculate_return_bonus(30, profile)

      assert bonus_14d > bonus_7d
      assert bonus_30d > bonus_14d
    end

    test "gives engagement multiplier for previously active users" do
      %{user: user} = create_user()
      high_profile = create_profile(user.id, %{engagement_score: 70.0})

      %{user: user2} = create_user()
      low_profile = create_profile(user2.id, %{engagement_score: 30.0})

      high_bonus = RevivalEngine.calculate_return_bonus(14, high_profile)
      low_bonus = RevivalEngine.calculate_return_bonus(14, low_profile)

      assert high_bonus > low_bonus
    end
  end

  describe "RevivalEngine.fire_welcome_back/2" do
    test "creates welcome back notification" do
      %{user: user} = create_user()

      welcome_data = %{
        days_away: 10,
        user_type: "reader",
        bonus_bux: 150,
        missed_articles: 5,
        message: "Welcome back after 10 days!"
      }

      {:ok, notif} = RevivalEngine.fire_welcome_back(user.id, welcome_data)

      assert notif.type == "welcome_back"
      assert notif.category == "system"
      assert notif.title =~ "10 days"
      assert notif.metadata[:bonus_bux] == 150
    end
  end

  # ============ RevivalEngine: Engagement Hooks ============

  describe "RevivalEngine.check_daily_bonus/1" do
    test "returns daily bonus for first read of day" do
      %{user: user} = create_user()

      assert {:daily_bonus, 50} = RevivalEngine.check_daily_bonus(user.id)
    end

    test "returns skip if already got daily bonus" do
      %{user: user} = create_user()

      Notifications.create_notification(user.id, %{
        type: "daily_bonus",
        category: "rewards",
        title: "Daily bonus!"
      })

      assert :skip = RevivalEngine.check_daily_bonus(user.id)
    end
  end

  describe "RevivalEngine.streak_reward/1" do
    test "returns reward for 3-day streak" do
      {3, bux} = RevivalEngine.streak_reward(3)
      assert bux == 100
    end

    test "returns reward for 7-day streak" do
      {7, bux} = RevivalEngine.streak_reward(7)
      assert bux == 500
    end

    test "returns reward for 14-day streak" do
      {14, bux} = RevivalEngine.streak_reward(14)
      assert bux == 1_500
    end

    test "returns reward for 30-day streak" do
      {30, bux} = RevivalEngine.streak_reward(30)
      assert bux == 5_000
    end

    test "returns nil for non-milestone streaks" do
      assert RevivalEngine.streak_reward(5) == nil
      assert RevivalEngine.streak_reward(10) == nil
    end
  end

  describe "RevivalEngine.daily_challenge/1" do
    test "returns reader challenge for readers" do
      %{user: user} = create_user()
      profile = create_profile(user.id, %{
        total_articles_read: 50,
        content_completion_rate: 0.8,
        games_played_last_30d: 0,
        total_bets_placed: 0,
        purchase_count: 0,
        shop_interest_score: 0.0,
        preferred_hubs: []
      })

      challenge = RevivalEngine.daily_challenge(profile)
      assert challenge.type == "read_articles"
      assert challenge.reward_bux > 0
    end

    test "returns gambler challenge for gamblers" do
      %{user: user} = create_user()
      profile = create_profile(user.id, %{
        total_articles_read: 0,
        content_completion_rate: 0.0,
        games_played_last_30d: 20,
        total_bets_placed: 50,
        purchase_count: 0,
        shop_interest_score: 0.0,
        preferred_hubs: []
      })

      challenge = RevivalEngine.daily_challenge(profile)
      assert challenge.type == "play_games"
      assert challenge.reward_bux == 200
    end
  end

  describe "RevivalEngine.weekly_quest/1" do
    test "returns reader quest for readers" do
      %{user: user} = create_user()
      profile = create_profile(user.id, %{
        total_articles_read: 50,
        content_completion_rate: 0.8,
        games_played_last_30d: 0,
        total_bets_placed: 0,
        purchase_count: 0,
        shop_interest_score: 0.0,
        preferred_hubs: []
      })

      quest = RevivalEngine.weekly_quest(profile)
      assert quest.type == "read_different_hubs"
      assert quest.reward_bux == 1_000
    end

    test "returns gambler quest for gamblers" do
      %{user: user} = create_user()
      profile = create_profile(user.id, %{
        total_articles_read: 0,
        content_completion_rate: 0.0,
        games_played_last_30d: 20,
        total_bets_placed: 50,
        purchase_count: 0,
        shop_interest_score: 0.0,
        preferred_hubs: []
      })

      quest = RevivalEngine.weekly_quest(profile)
      assert quest.type == "win_games"
      assert quest.reward_bux == 1_500
    end
  end

  # ============ RevivalEngine: Analytics Queries ============

  describe "RevivalEngine.churn_risk_distribution/0" do
    test "returns distribution of risk levels" do
      %{user: u1} = create_user()
      create_profile(u1.id, %{churn_risk_level: "low"})

      %{user: u2} = create_user()
      create_profile(u2.id, %{churn_risk_level: "critical"})

      dist = RevivalEngine.churn_risk_distribution()

      assert is_map(dist)
      assert Map.has_key?(dist, :healthy)
      assert Map.has_key?(dist, :critical)
      assert dist.healthy >= 1
      assert dist.critical >= 1
    end
  end

  describe "RevivalEngine.engagement_tier_distribution/0" do
    test "returns distribution of engagement tiers" do
      %{user: u1} = create_user()
      create_profile(u1.id, %{engagement_tier: "active"})

      %{user: u2} = create_user()
      create_profile(u2.id, %{engagement_tier: "dormant"})

      dist = RevivalEngine.engagement_tier_distribution()

      assert is_map(dist)
      assert Map.get(dist, "active", 0) >= 1
      assert Map.get(dist, "dormant", 0) >= 1
    end
  end

  describe "RevivalEngine.revival_success_rate/1" do
    test "returns zero rate when no revival notifications sent" do
      result = RevivalEngine.revival_success_rate(30)

      assert result.total_sent == 0
      assert result.rate == 0.0
    end

    test "calculates rate based on session activity after notification" do
      %{user: user} = create_user()

      # Send a revival notification
      Notifications.create_notification(user.id, %{
        type: "churn_intervention",
        category: "system",
        title: "We miss you"
      })

      # Simulate user returning (session_start event) — 1 day after notification
      one_day_later =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(86400, :second)
        |> NaiveDateTime.truncate(:second)

      %UserEvent{}
      |> UserEvent.changeset(%{
        user_id: user.id,
        event_type: "session_start",
        event_category: "engagement"
      })
      |> Ecto.Changeset.put_change(:inserted_at, one_day_later)
      |> Repo.insert!()

      result = RevivalEngine.revival_success_rate(30)

      assert result.total_sent >= 1
      assert result.returned >= 1
      assert result.rate > 0.0
    end
  end

  # ============ ChurnDetectionWorker ============

  describe "ChurnDetectionWorker" do
    test "performs successfully with at-risk users" do
      %{user: user} = create_user()
      create_profile(user.id, %{
        churn_risk_score: 0.7,
        churn_risk_level: "critical",
        days_since_last_active: 20,
        avg_sessions_per_week: 0.2,
        avg_session_duration_ms: 10_000,
        email_open_rate_30d: 0.0,
        email_click_rate_30d: 0.0,
        preferred_hubs: [],
        articles_read_last_7d: 0,
        articles_read_last_30d: 5,
        notification_fatigue_score: 0.5,
        purchase_count: 0,
        referrals_converted: 0
      })

      assert :ok = ChurnDetectionWorker.perform(%Oban.Job{args: %{}})
    end

    test "handles empty at-risk list" do
      assert :ok = ChurnDetectionWorker.perform(%Oban.Job{args: %{}})
    end

    test "does not send duplicate interventions" do
      %{user: user} = create_user()
      create_profile(user.id, %{
        churn_risk_score: 0.7,
        churn_risk_level: "critical",
        days_since_last_active: 20,
        avg_sessions_per_week: 0.2,
        avg_session_duration_ms: 10_000,
        email_open_rate_30d: 0.0,
        email_click_rate_30d: 0.0,
        preferred_hubs: [],
        articles_read_last_7d: 0,
        articles_read_last_30d: 5,
        notification_fatigue_score: 0.5,
        purchase_count: 0,
        referrals_converted: 0
      })

      # First run creates intervention
      :ok = ChurnDetectionWorker.perform(%Oban.Job{args: %{}})

      # Second run should skip (already sent recently)
      :ok = ChurnDetectionWorker.perform(%Oban.Job{args: %{}})

      # Should only have one intervention notification
      notifs = Notifications.list_notifications(user.id, limit: 50)
      churn_notifs = Enum.filter(notifs, fn n -> n.type == "churn_intervention" end)
      assert length(churn_notifs) == 1
    end
  end

  # ============ Integration Tests ============

  describe "full churn detection and revival lifecycle" do
    test "detects at-risk user, fires intervention, user returns, gets welcome back" do
      %{user: user} = create_user()

      # User starts as active, then becomes dormant
      profile = create_profile(user.id, %{
        churn_risk_score: 0.6,
        churn_risk_level: "high",
        days_since_last_active: 14,
        avg_sessions_per_week: 0.3,
        avg_session_duration_ms: 30_000,
        email_open_rate_30d: 0.2,
        email_click_rate_30d: 0.0,
        preferred_hubs: [%{"name" => "Crypto News"}],
        articles_read_last_7d: 0,
        articles_read_last_30d: 8,
        notification_fatigue_score: 0.3,
        purchase_count: 0,
        referrals_converted: 0,
        total_articles_read: 20,
        content_completion_rate: 0.6,
        engagement_score: 35.0
      })

      # 1. Predict churn
      prediction = ChurnPredictor.predict_churn(profile)
      assert prediction.score > 0.4

      # 2. Fire intervention
      {:ok, intervention_notif} = ChurnPredictor.fire_intervention(user.id, prediction)
      assert intervention_notif.type == "churn_intervention"

      # 3. Get revival message
      revival_msg = RevivalEngine.get_revival_message(profile, 14)
      assert revival_msg.offer != nil

      # 4. Check welcome back eligibility
      {:welcome_back, wb_data} = RevivalEngine.check_welcome_back(user.id, profile)
      assert wb_data.bonus_bux > 0

      # 5. Fire welcome back
      {:ok, wb_notif} = RevivalEngine.fire_welcome_back(user.id, wb_data)
      assert wb_notif.type == "welcome_back"

      # 6. All notifications created
      all_notifs = Notifications.list_notifications(user.id, limit: 10)
      types = Enum.map(all_notifs, & &1.type)
      assert "churn_intervention" in types
      assert "welcome_back" in types
    end
  end

  describe "engagement hook integration" do
    test "daily bonus + streak + challenge for active reader" do
      %{user: user} = create_user()
      profile = create_profile(user.id, %{
        total_articles_read: 50,
        content_completion_rate: 0.8,
        consecutive_active_days: 7,
        games_played_last_30d: 0,
        total_bets_placed: 0,
        purchase_count: 0,
        shop_interest_score: 0.0,
        preferred_hubs: []
      })

      # Daily bonus check
      {:daily_bonus, 50} = RevivalEngine.check_daily_bonus(user.id)

      # Streak reward at 7 days
      {7, 500} = RevivalEngine.streak_reward(7)

      # Daily challenge
      challenge = RevivalEngine.daily_challenge(profile)
      assert challenge.type == "read_articles"
      assert challenge.target == 2

      # Weekly quest
      quest = RevivalEngine.weekly_quest(profile)
      assert quest.type == "read_different_hubs"
    end
  end
end
