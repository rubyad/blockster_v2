defmodule BlocksterV2.Notifications.Phase13Test do
  use BlocksterV2.DataCase, async: true

  alias BlocksterV2.UserEvents
  alias BlocksterV2.Notifications.{UserEvent, UserProfile, ProfileEngine}
  alias BlocksterV2.Workers.ProfileRecalcWorker

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

  # ============ UserProfile Schema Tests ============

  describe "UserProfile schema" do
    test "valid changeset with user_id" do
      %{user: user} = create_user()
      changeset = UserProfile.changeset(%UserProfile{}, %{user_id: user.id})
      assert changeset.valid?
    end

    test "validates engagement_tier inclusion" do
      %{user: user} = create_user()

      changeset =
        UserProfile.changeset(%UserProfile{}, %{
          user_id: user.id,
          engagement_tier: "invalid_tier"
        })

      refute changeset.valid?
      assert errors_on(changeset) |> Map.has_key?(:engagement_tier)
    end

    test "validates gambling_tier inclusion" do
      %{user: user} = create_user()

      changeset =
        UserProfile.changeset(%UserProfile{}, %{
          user_id: user.id,
          gambling_tier: "invalid"
        })

      refute changeset.valid?
      assert errors_on(changeset) |> Map.has_key?(:gambling_tier)
    end

    test "validates churn_risk_level inclusion" do
      %{user: user} = create_user()

      changeset =
        UserProfile.changeset(%UserProfile{}, %{
          user_id: user.id,
          churn_risk_level: "invalid"
        })

      refute changeset.valid?
      assert errors_on(changeset) |> Map.has_key?(:churn_risk_level)
    end

    test "validates engagement_score range (0-100)" do
      %{user: user} = create_user()

      changeset =
        UserProfile.changeset(%UserProfile{}, %{
          user_id: user.id,
          engagement_score: 101.0
        })

      refute changeset.valid?
      assert errors_on(changeset) |> Map.has_key?(:engagement_score)
    end

    test "validates churn_risk_score range (0-1)" do
      %{user: user} = create_user()

      changeset =
        UserProfile.changeset(%UserProfile{}, %{
          user_id: user.id,
          churn_risk_score: 1.5
        })

      refute changeset.valid?
      assert errors_on(changeset) |> Map.has_key?(:churn_risk_score)
    end

    test "enforces unique user_id constraint" do
      %{user: user} = create_user()

      {:ok, _} = UserEvents.upsert_profile(user.id, %{engagement_tier: "new"})
      {:ok, profile} = UserEvents.upsert_profile(user.id, %{engagement_tier: "active"})
      assert profile.engagement_tier == "active"
    end

    test "default values are set correctly" do
      %{user: user} = create_user()
      {:ok, profile} = UserEvents.get_or_create_profile(user.id)

      assert profile.engagement_tier == "new"
      assert profile.engagement_score == 0.0
      assert profile.churn_risk_level == "low"
      assert profile.gambling_tier == "non_gambler"
      assert profile.articles_read_last_7d == 0
      assert profile.purchase_count == 0
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

  # ============ Profile CRUD Tests ============

  describe "UserEvents profile management" do
    test "get_or_create_profile creates new profile" do
      %{user: user} = create_user()
      {:ok, profile} = UserEvents.get_or_create_profile(user.id)
      assert profile.user_id == user.id
      assert profile.engagement_tier == "new"
    end

    test "get_or_create_profile returns existing profile" do
      %{user: user} = create_user()
      {:ok, p1} = UserEvents.get_or_create_profile(user.id)
      {:ok, p2} = UserEvents.get_or_create_profile(user.id)
      assert p1.id == p2.id
    end

    test "upsert_profile creates or updates" do
      %{user: user} = create_user()

      {:ok, p1} = UserEvents.upsert_profile(user.id, %{engagement_tier: "casual"})
      assert p1.engagement_tier == "casual"

      {:ok, p2} = UserEvents.upsert_profile(user.id, %{engagement_tier: "active"})
      assert p2.engagement_tier == "active"
      assert p1.id == p2.id
    end

    test "get_profile returns nil for nonexistent user" do
      assert UserEvents.get_profile(999_999) == nil
    end
  end

  # ============ ProfileEngine Tier Classification Tests ============

  describe "ProfileEngine.classify_engagement_tier/1" do
    test "classifies churned (>30 days inactive)" do
      assert ProfileEngine.classify_engagement_tier(%{
        days_since_last_active: 45,
        lifetime_days: 90,
        avg_sessions_per_week: 0.0,
        purchase_count: 0,
        total_spent: Decimal.new("0")
      }) == "churned"
    end

    test "classifies dormant (14-30 days inactive)" do
      assert ProfileEngine.classify_engagement_tier(%{
        days_since_last_active: 20,
        lifetime_days: 60,
        avg_sessions_per_week: 0.0,
        purchase_count: 0,
        total_spent: Decimal.new("0")
      }) == "dormant"
    end

    test "classifies new (<7 days old)" do
      assert ProfileEngine.classify_engagement_tier(%{
        days_since_last_active: 1,
        lifetime_days: 3,
        avg_sessions_per_week: 2.0,
        purchase_count: 0,
        total_spent: Decimal.new("0")
      }) == "new"
    end

    test "classifies whale (high spending)" do
      assert ProfileEngine.classify_engagement_tier(%{
        days_since_last_active: 1,
        lifetime_days: 60,
        avg_sessions_per_week: 5.0,
        purchase_count: 6,
        total_spent: Decimal.new("150")
      }) == "whale"
    end

    test "classifies power (frequent + buyer)" do
      assert ProfileEngine.classify_engagement_tier(%{
        days_since_last_active: 1,
        lifetime_days: 30,
        avg_sessions_per_week: 4.0,
        purchase_count: 2,
        total_spent: Decimal.new("30")
      }) == "power"
    end

    test "classifies casual (infrequent)" do
      assert ProfileEngine.classify_engagement_tier(%{
        days_since_last_active: 5,
        lifetime_days: 30,
        avg_sessions_per_week: 0.3,
        purchase_count: 0,
        total_spent: Decimal.new("0")
      }) == "casual"
    end

    test "classifies active (moderate use, no purchases)" do
      assert ProfileEngine.classify_engagement_tier(%{
        days_since_last_active: 1,
        lifetime_days: 30,
        avg_sessions_per_week: 2.0,
        purchase_count: 0,
        total_spent: Decimal.new("0")
      }) == "active"
    end
  end

  # ============ ProfileEngine Engagement Score Tests ============

  describe "ProfileEngine.calculate_engagement_score/1" do
    test "returns 0 for empty profile" do
      score = ProfileEngine.calculate_engagement_score(%{
        avg_sessions_per_week: 0.0,
        consecutive_active_days: 0,
        days_since_last_active: 30,
        articles_read_last_7d: 0,
        content_completion_rate: 0.0,
        purchase_count: 0,
        shop_interest_score: 0.0,
        referrals_converted: 0,
        referral_propensity: 0.0,
        email_open_rate_30d: 0.0,
        in_app_click_rate_30d: 0.0,
        notification_fatigue_score: 0.0
      })

      assert score >= 0.0
      assert score <= 10.0  # Should be very low for empty profile
    end

    test "returns high score for engaged user" do
      score = ProfileEngine.calculate_engagement_score(%{
        avg_sessions_per_week: 5.0,
        consecutive_active_days: 10,
        days_since_last_active: 0,
        articles_read_last_7d: 8,
        content_completion_rate: 0.8,
        purchase_count: 3,
        shop_interest_score: 0.7,
        referrals_converted: 2,
        referral_propensity: 0.6,
        email_open_rate_30d: 0.7,
        in_app_click_rate_30d: 0.5,
        notification_fatigue_score: 0.1
      })

      assert score >= 50.0
      assert score <= 100.0
    end

    test "score never exceeds 100" do
      score = ProfileEngine.calculate_engagement_score(%{
        avg_sessions_per_week: 50.0,
        consecutive_active_days: 100,
        days_since_last_active: 0,
        articles_read_last_7d: 100,
        content_completion_rate: 1.0,
        purchase_count: 50,
        shop_interest_score: 1.0,
        referrals_converted: 50,
        referral_propensity: 1.0,
        email_open_rate_30d: 1.0,
        in_app_click_rate_30d: 1.0,
        notification_fatigue_score: 0.0
      })

      assert score <= 100.0
    end
  end

  # ============ ProfileEngine Gambling Tier Tests ============

  describe "ProfileEngine.classify_gambling_tier/1" do
    test "classifies non_gambler" do
      assert ProfileEngine.classify_gambling_tier(%{
        games_played_last_30d: 0,
        total_bets_placed: 0,
        total_wagered: Decimal.new("0"),
        avg_bet_size: Decimal.new("0")
      }) == "non_gambler"
    end

    test "classifies casual_gambler" do
      assert ProfileEngine.classify_gambling_tier(%{
        games_played_last_30d: 3,
        total_bets_placed: 3,
        total_wagered: Decimal.new("50"),
        avg_bet_size: Decimal.new("17")
      }) == "casual_gambler"
    end

    test "classifies regular_gambler" do
      assert ProfileEngine.classify_gambling_tier(%{
        games_played_last_30d: 20,
        total_bets_placed: 20,
        total_wagered: Decimal.new("500"),
        avg_bet_size: Decimal.new("25")
      }) == "regular_gambler"
    end

    test "classifies high_roller" do
      assert ProfileEngine.classify_gambling_tier(%{
        games_played_last_30d: 30,
        total_bets_placed: 30,
        total_wagered: Decimal.new("2000"),
        avg_bet_size: Decimal.new("150")
      }) == "high_roller"
    end

    test "classifies whale_gambler" do
      assert ProfileEngine.classify_gambling_tier(%{
        games_played_last_30d: 50,
        total_bets_placed: 50,
        total_wagered: Decimal.new("15000"),
        avg_bet_size: Decimal.new("600")
      }) == "whale_gambler"
    end
  end

  # ============ ProfileEngine Churn Risk Tests ============

  describe "ProfileEngine.calculate_churn_risk/1" do
    test "low risk for active user" do
      {score, level} = ProfileEngine.calculate_churn_risk(%{
        days_since_last_active: 0,
        avg_sessions_per_week: 5.0,
        consecutive_active_days: 10,
        email_open_rate_30d: 0.7,
        notification_fatigue_score: 0.1,
        engagement_score: 75.0
      })

      assert score < 0.3
      assert level == "low"
    end

    test "medium risk for declining user" do
      {score, level} = ProfileEngine.calculate_churn_risk(%{
        days_since_last_active: 7,
        avg_sessions_per_week: 1.0,
        consecutive_active_days: 0,
        email_open_rate_30d: 0.3,
        notification_fatigue_score: 0.3,
        engagement_score: 30.0
      })

      assert score >= 0.3
      assert score < 0.5
      assert level == "medium"
    end

    test "high risk for mostly inactive user" do
      {score, level} = ProfileEngine.calculate_churn_risk(%{
        days_since_last_active: 15,
        avg_sessions_per_week: 0.2,
        consecutive_active_days: 0,
        email_open_rate_30d: 0.1,
        notification_fatigue_score: 0.6,
        engagement_score: 10.0
      })

      assert score >= 0.5
      assert level in ["high", "critical"]
    end

    test "critical risk for churning user" do
      {score, level} = ProfileEngine.calculate_churn_risk(%{
        days_since_last_active: 28,
        avg_sessions_per_week: 0.0,
        consecutive_active_days: 0,
        email_open_rate_30d: 0.0,
        notification_fatigue_score: 0.9,
        engagement_score: 2.0
      })

      assert score >= 0.7
      assert level == "critical"
    end

    test "score is bounded between 0 and 1" do
      {score, _level} = ProfileEngine.calculate_churn_risk(%{
        days_since_last_active: 100,
        avg_sessions_per_week: 0.0,
        consecutive_active_days: 0,
        email_open_rate_30d: 0.0,
        notification_fatigue_score: 1.0,
        engagement_score: 0.0
      })

      assert score >= 0.0
      assert score <= 1.0
    end
  end

  # ============ ProfileEngine Full Recalculation Tests ============

  describe "ProfileEngine.recalculate_profile/1" do
    test "recalculates content preferences from events" do
      %{user: user} = create_user()

      # Create article view events with category metadata
      for i <- 1..5 do
        UserEvents.track_sync(user.id, "article_read_complete", %{
          target_type: "post",
          target_id: i,
          category_id: 1,
          category_name: "DeFi",
          read_duration_ms: 30000,
          scroll_depth_pct: 80
        })
      end

      for i <- 6..7 do
        UserEvents.track_sync(user.id, "article_read_complete", %{
          target_type: "post",
          target_id: i,
          category_id: 2,
          category_name: "NFTs",
          read_duration_ms: 20000,
          scroll_depth_pct: 60
        })
      end

      profile = ProfileEngine.recalculate_profile(user.id)

      assert profile[:articles_read_last_30d] == 7
      assert profile[:avg_read_duration_ms] > 0
      assert length(profile[:preferred_categories]) > 0

      # DeFi should score higher than NFTs
      defi = Enum.find(profile[:preferred_categories], & &1["name"] == "DeFi")
      nfts = Enum.find(profile[:preferred_categories], & &1["name"] == "NFTs")
      assert defi["score"] >= nfts["score"]
    end

    test "recalculates shopping behavior" do
      %{user: user} = create_user()

      # Product views
      UserEvents.track_sync(user.id, "product_view", %{target_type: "product", target_id: 1})
      UserEvents.track_sync(user.id, "product_view", %{target_type: "product", target_id: 2})

      # Cart add
      UserEvents.track_sync(user.id, "product_add_to_cart", %{target_type: "product", target_id: 1})

      # Purchase
      UserEvents.track_sync(user.id, "purchase_complete", %{
        target_type: "order",
        target_id: 100,
        total: "45.00"
      })

      profile = ProfileEngine.recalculate_profile(user.id)

      assert profile[:shop_interest_score] > 0.0
      assert profile[:purchase_count] >= 1
      assert length(profile[:viewed_products_last_30d]) == 2
    end

    test "recalculates engagement tier and score" do
      %{user: user} = create_user()

      # Create some session events
      UserEvents.track_sync(user.id, "session_start", %{})
      UserEvents.track_sync(user.id, "daily_login", %{})
      UserEvents.track_sync(user.id, "article_read_complete", %{target_id: 1})

      profile = ProfileEngine.recalculate_profile(user.id)

      assert profile[:engagement_tier] in UserProfile.valid_engagement_tiers()
      assert profile[:engagement_score] >= 0.0
      assert profile[:engagement_score] <= 100.0
      assert profile[:last_calculated_at] != nil
      assert profile[:events_since_last_calc] == 0
    end

    test "classifies gambling tier" do
      %{user: user} = create_user()

      for _i <- 1..10 do
        UserEvents.track_sync(user.id, "game_played", %{
          bet_amount: "50",
          payout: "75",
          token: "BUX"
        })
      end

      profile = ProfileEngine.recalculate_profile(user.id)

      assert profile[:games_played_last_30d] == 10
      assert profile[:gambling_tier] in UserProfile.valid_gambling_tiers()
      assert profile[:gambling_tier] != "non_gambler"
    end

    test "calculates churn risk" do
      %{user: user} = create_user()

      # Active user
      UserEvents.track_sync(user.id, "daily_login", %{})
      UserEvents.track_sync(user.id, "session_start", %{})

      profile = ProfileEngine.recalculate_profile(user.id)

      assert profile[:churn_risk_score] >= 0.0
      assert profile[:churn_risk_score] <= 1.0
      assert profile[:churn_risk_level] in UserProfile.valid_churn_risk_levels()
    end
  end

  # ============ ProfileRecalcWorker Tests ============

  describe "ProfileRecalcWorker" do
    test "recalculates single user profile" do
      %{user: user} = create_user()

      # Create some events
      UserEvents.track_sync(user.id, "article_view", %{target_id: 1})
      UserEvents.track_sync(user.id, "daily_login", %{})

      # Run worker for single user
      assert :ok = ProfileRecalcWorker.perform(%Oban.Job{args: %{"user_id" => user.id}})

      profile = UserEvents.get_profile(user.id)
      assert profile != nil
      assert profile.last_calculated_at != nil
    end

    test "batch recalculation finds users needing update" do
      %{user: user} = create_user()

      # Create profile with pending events
      {:ok, _} = UserEvents.get_or_create_profile(user.id)
      UserEvents.track_sync(user.id, "article_view", %{target_id: 1})

      # Run batch worker
      assert :ok = ProfileRecalcWorker.perform(%Oban.Job{args: %{}})

      # Profile should be recalculated
      profile = UserEvents.get_profile(user.id)
      assert profile != nil
    end

    test "enqueue creates an Oban job" do
      %{user: user} = create_user()
      assert {:ok, %Oban.Job{}} = ProfileRecalcWorker.enqueue(user.id)
    end
  end

  # ============ Events Increment Counter Tests ============

  describe "events_since_last_calc tracking" do
    test "increments counter on event track" do
      %{user: user} = create_user()
      {:ok, _} = UserEvents.get_or_create_profile(user.id)

      UserEvents.track_sync(user.id, "article_view", %{})
      UserEvents.track_sync(user.id, "product_view", %{})

      profile = UserEvents.get_profile(user.id)
      assert profile.events_since_last_calc == 2
    end

    test "resets counter after recalculation" do
      %{user: user} = create_user()
      {:ok, _} = UserEvents.get_or_create_profile(user.id)

      UserEvents.track_sync(user.id, "article_view", %{})
      UserEvents.track_sync(user.id, "article_view", %{})

      # Verify counter incremented
      assert UserEvents.get_profile(user.id).events_since_last_calc == 2

      # Recalculate
      ProfileRecalcWorker.perform(%Oban.Job{args: %{"user_id" => user.id}})

      # Counter should be reset
      assert UserEvents.get_profile(user.id).events_since_last_calc == 0
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

    test "profiles are independent between users" do
      %{user1: u1, user2: u2} = create_user_pair()

      UserEvents.upsert_profile(u1.id, %{engagement_tier: "power"})
      UserEvents.upsert_profile(u2.id, %{engagement_tier: "casual"})

      assert UserEvents.get_profile(u1.id).engagement_tier == "power"
      assert UserEvents.get_profile(u2.id).engagement_tier == "casual"
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

    test "profile recalculation handles user with no events" do
      %{user: user} = create_user()
      profile = ProfileEngine.recalculate_profile(user.id)

      assert profile[:articles_read_last_30d] == 0
      assert profile[:engagement_tier] in ["new", "churned"]
    end
  end
end
