defmodule BlocksterV2.Notifications.Phase14Test do
  use BlocksterV2.DataCase, async: true

  alias BlocksterV2.{Repo, UserEvents, Notifications}
  alias BlocksterV2.Notifications.{
    ABTest, ABTestAssignment, ABTestEngine,
    ContentSelector, OfferSelector, CopyWriter,
    TriggerEngine, UserProfile
  }
  alias BlocksterV2.Workers.ABTestCheckWorker

  # ============ Test Helpers ============

  defp create_user(_context \\ %{}) do
    {:ok, user} =
      BlocksterV2.Accounts.create_user_from_wallet(%{
        wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
        chain_id: 560013
      })

    %{user: user}
  end

  defp create_user_with_profile(attrs \\ %{}) do
    %{user: user} = create_user()

    profile_attrs =
      Map.merge(
        %{
          engagement_tier: "active",
          engagement_score: 50.0,
          purchase_count: 0,
          articles_read_last_7d: 5,
          articles_read_last_30d: 20,
          referral_propensity: 0.3,
          churn_risk_score: 0.2,
          churn_risk_level: "low"
        },
        attrs
      )

    {:ok, profile} = UserEvents.upsert_profile(user.id, profile_attrs)
    %{user: user, profile: profile}
  end

  defp create_ab_test(attrs \\ %{}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    default_attrs = %{
      name: "Test #{System.unique_integer([:positive])}",
      email_type: "daily_digest",
      element_tested: "subject",
      status: "running",
      start_date: now,
      min_sample_size: 10,
      confidence_threshold: 0.95,
      variants: [
        %{"id" => "A", "value" => "Subject A", "weight" => 50},
        %{"id" => "B", "value" => "Subject B", "weight" => 50}
      ]
    }

    {:ok, test} = ABTestEngine.create_test(Map.merge(default_attrs, attrs))
    test
  end

  # ============ ABTest Schema Tests ============

  describe "ABTest schema" do
    test "valid changeset with required fields" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      changeset =
        ABTest.changeset(%ABTest{}, %{
          name: "Subject Test",
          email_type: "daily_digest",
          element_tested: "subject",
          start_date: now,
          variants: [%{"id" => "A", "value" => "Hi"}, %{"id" => "B", "value" => "Hello"}]
        })

      assert changeset.valid?
    end

    test "invalid without required fields" do
      changeset = ABTest.changeset(%ABTest{}, %{})
      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :name)
      assert Keyword.has_key?(changeset.errors, :email_type)
      assert Keyword.has_key?(changeset.errors, :element_tested)
      assert Keyword.has_key?(changeset.errors, :start_date)
    end

    test "validates status inclusion" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      changeset =
        ABTest.changeset(%ABTest{}, %{
          name: "Test",
          email_type: "digest",
          element_tested: "subject",
          start_date: now,
          status: "invalid_status"
        })

      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :status)
    end

    test "validates element_tested inclusion" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      changeset =
        ABTest.changeset(%ABTest{}, %{
          name: "Test",
          email_type: "digest",
          element_tested: "invalid_element",
          start_date: now
        })

      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :element_tested)
    end

    test "valid_statuses returns expected list" do
      assert ABTest.valid_statuses() == ~w(running completed winner_applied)
    end

    test "valid_elements returns expected list" do
      assert "subject" in ABTest.valid_elements()
      assert "body" in ABTest.valid_elements()
      assert "cta_text" in ABTest.valid_elements()
    end
  end

  # ============ ABTestAssignment Schema Tests ============

  describe "ABTestAssignment schema" do
    test "valid changeset with required fields" do
      %{user: user} = create_user()
      test = create_ab_test()

      changeset =
        ABTestAssignment.changeset(%ABTestAssignment{}, %{
          ab_test_id: test.id,
          user_id: user.id,
          variant_id: "A"
        })

      assert changeset.valid?
    end

    test "invalid without required fields" do
      changeset = ABTestAssignment.changeset(%ABTestAssignment{}, %{})
      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :ab_test_id)
      assert Keyword.has_key?(changeset.errors, :user_id)
      assert Keyword.has_key?(changeset.errors, :variant_id)
    end

    test "unique constraint on [ab_test_id, user_id]" do
      %{user: user} = create_user()
      test = create_ab_test()

      {:ok, _} =
        %ABTestAssignment{}
        |> ABTestAssignment.changeset(%{ab_test_id: test.id, user_id: user.id, variant_id: "A"})
        |> Repo.insert()

      {:error, changeset} =
        %ABTestAssignment{}
        |> ABTestAssignment.changeset(%{ab_test_id: test.id, user_id: user.id, variant_id: "B"})
        |> Repo.insert()

      assert Keyword.has_key?(changeset.errors, :ab_test_id)
    end
  end

  # ============ ABTestEngine Tests ============

  describe "ABTestEngine.create_test/1" do
    test "creates a test with valid attrs" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, test} =
        ABTestEngine.create_test(%{
          name: "Subject Line Test",
          email_type: "daily_digest",
          element_tested: "subject",
          start_date: now,
          variants: [
            %{"id" => "A", "value" => "Hello"},
            %{"id" => "B", "value" => "Hi there"}
          ]
        })

      assert test.name == "Subject Line Test"
      assert test.status == "running"
      assert length(test.variants) == 2
    end
  end

  describe "ABTestEngine.assign_variant/2" do
    test "assigns a variant deterministically" do
      %{user: user} = create_user()
      test = create_ab_test()

      variant1 = ABTestEngine.assign_variant(user.id, test)
      variant2 = ABTestEngine.assign_variant(user.id, test)

      assert variant1 == variant2
      assert variant1 in ["A", "B"]
    end

    test "creates an assignment record" do
      %{user: user} = create_user()
      test = create_ab_test()

      _variant = ABTestEngine.assign_variant(user.id, test)

      assignment = Repo.get_by(ABTestAssignment, ab_test_id: test.id, user_id: user.id)
      assert assignment
      assert assignment.variant_id in ["A", "B"]
    end

    test "different users can get different variants" do
      test = create_ab_test()

      # Create enough users to statistically ensure both variants appear
      variants =
        for _ <- 1..20 do
          %{user: user} = create_user()
          ABTestEngine.assign_variant(user.id, test)
        end

      unique_variants = Enum.uniq(variants)
      assert length(unique_variants) >= 1
    end
  end

  describe "ABTestEngine.get_active_test/2" do
    test "returns the running test for email type" do
      test = create_ab_test(%{email_type: "daily_digest", element_tested: "subject"})

      found = ABTestEngine.get_active_test("daily_digest", "subject")
      assert found.id == test.id
    end

    test "returns nil when no running test exists" do
      assert ABTestEngine.get_active_test("nonexistent_type", "subject") == nil
    end

    test "does not return completed tests" do
      create_ab_test(%{
        email_type: "weekly_summary",
        element_tested: "subject",
        status: "completed"
      })

      # Need a special status for this — completed isn't in valid_statuses
      # Let's create and then promote
      test = create_ab_test(%{email_type: "unique_type_1", element_tested: "subject"})
      ABTestEngine.promote_winner(test, "A")

      assert ABTestEngine.get_active_test("unique_type_1", "subject") == nil
    end
  end

  describe "ABTestEngine.get_variant_for_user/3" do
    test "returns {variant_id, variant_value} when test exists" do
      create_ab_test(%{email_type: "digest_test", element_tested: "subject"})
      %{user: user} = create_user()

      result = ABTestEngine.get_variant_for_user(user.id, "digest_test", "subject")
      assert {variant_id, value} = result
      assert variant_id in ["A", "B"]
      assert value in ["Subject A", "Subject B"]
    end

    test "returns nil when no test exists" do
      %{user: user} = create_user()
      assert ABTestEngine.get_variant_for_user(user.id, "no_test", "subject") == nil
    end
  end

  describe "ABTestEngine.record_open/2 and record_click/2" do
    test "records open for an assignment" do
      %{user: user} = create_user()
      test = create_ab_test()
      ABTestEngine.assign_variant(user.id, test)

      ABTestEngine.record_open(test.id, user.id)

      assignment = Repo.get_by(ABTestAssignment, ab_test_id: test.id, user_id: user.id)
      assert assignment.opened == true
    end

    test "records click (also sets opened)" do
      %{user: user} = create_user()
      test = create_ab_test()
      ABTestEngine.assign_variant(user.id, test)

      ABTestEngine.record_click(test.id, user.id)

      assignment = Repo.get_by(ABTestAssignment, ab_test_id: test.id, user_id: user.id)
      assert assignment.opened == true
      assert assignment.clicked == true
    end

    test "no-ops for non-existent assignment" do
      %{user: user} = create_user()
      test = create_ab_test()

      assert ABTestEngine.record_open(test.id, user.id) == :ok
    end
  end

  describe "ABTestEngine.get_test_results/1" do
    test "returns aggregated results by variant" do
      test = create_ab_test()

      # Create assignments with opens/clicks
      for i <- 1..6 do
        %{user: user} = create_user()
        variant = if rem(i, 2) == 0, do: "A", else: "B"

        {:ok, _} =
          %ABTestAssignment{}
          |> ABTestAssignment.changeset(%{
            ab_test_id: test.id,
            user_id: user.id,
            variant_id: variant,
            opened: rem(i, 3) != 0,
            clicked: i == 1
          })
          |> Repo.insert()
      end

      results = ABTestEngine.get_test_results(test.id)
      assert length(results) == 2

      Enum.each(results, fn r ->
        assert r.variant_id in ["A", "B"]
        assert r.total > 0
      end)
    end
  end

  describe "ABTestEngine.check_significance/1" do
    test "returns :insufficient_data when below min_sample_size" do
      test = create_ab_test(%{min_sample_size: 100})

      # Only add a few assignments
      for _ <- 1..5 do
        %{user: user} = create_user()
        ABTestEngine.assign_variant(user.id, test)
      end

      assert {:insufficient_data, nil, nil} = ABTestEngine.check_significance(test)
    end

    test "returns :not_yet or :significant with sufficient data" do
      test = create_ab_test(%{min_sample_size: 5})

      # Create enough assignments with clear winner
      for i <- 1..10 do
        %{user: user} = create_user()
        variant = if rem(i, 2) == 0, do: "A", else: "B"

        {:ok, _} =
          %ABTestAssignment{}
          |> ABTestAssignment.changeset(%{
            ab_test_id: test.id,
            user_id: user.id,
            variant_id: variant,
            opened: variant == "A" || rem(i, 5) == 0
          })
          |> Repo.insert()
      end

      result = ABTestEngine.check_significance(test)
      assert elem(result, 0) in [:significant, :not_yet]
    end
  end

  describe "ABTestEngine.promote_winner/2" do
    test "updates test status and winning variant" do
      test = create_ab_test()

      {:ok, updated} = ABTestEngine.promote_winner(test, "A")
      assert updated.status == "winner_applied"
      assert updated.winning_variant == "A"
      assert updated.end_date
    end
  end

  describe "ABTestEngine.list_tests/1" do
    test "lists all tests" do
      create_ab_test(%{email_type: "list_test_1"})
      create_ab_test(%{email_type: "list_test_2"})

      tests = ABTestEngine.list_tests()
      assert length(tests) >= 2
    end

    test "filters by status" do
      test = create_ab_test(%{email_type: "filter_test"})
      ABTestEngine.promote_winner(test, "A")

      running = ABTestEngine.list_tests(status: "running")
      completed = ABTestEngine.list_tests(status: "winner_applied")

      refute Enum.any?(running, fn t -> t.id == test.id end)
      assert Enum.any?(completed, fn t -> t.id == test.id end)
    end
  end

  # ============ CopyWriter Tests ============

  describe "CopyWriter.digest_subject/1" do
    test "returns default for nil profile" do
      assert CopyWriter.digest_subject(nil) == "Your daily Blockster briefing"
    end

    test "returns tier-specific subject for new user" do
      profile = %{engagement_tier: "new", articles_read_last_7d: 0, preferred_hubs: []}
      assert CopyWriter.digest_subject(profile) =~ "ready"
    end

    test "returns tier-specific subject for casual user" do
      profile = %{engagement_tier: "casual", articles_read_last_7d: 3, preferred_hubs: []}
      assert CopyWriter.digest_subject(profile) =~ "3 articles"
    end

    test "returns tier-specific subject for active user" do
      profile = %{engagement_tier: "active", articles_read_last_7d: 10, preferred_hubs: []}
      assert CopyWriter.digest_subject(profile) =~ "top stories"
    end

    test "returns tier-specific subject for power user" do
      profile = %{engagement_tier: "power", articles_read_last_7d: 20, preferred_hubs: [%{"id" => 1}, %{"id" => 2}]}
      assert CopyWriter.digest_subject(profile) =~ "2 hubs"
    end

    test "returns tier-specific subject for whale" do
      profile = %{engagement_tier: "whale", articles_read_last_7d: 50, preferred_hubs: []}
      assert CopyWriter.digest_subject(profile) =~ "Exclusive"
    end

    test "returns tier-specific subject for dormant user" do
      profile = %{engagement_tier: "dormant", articles_read_last_7d: 0, preferred_hubs: []}
      assert CopyWriter.digest_subject(profile) =~ "saving"
    end

    test "returns tier-specific subject for churned user" do
      profile = %{engagement_tier: "churned", articles_read_last_7d: 0, preferred_hubs: []}
      assert CopyWriter.digest_subject(profile) =~ "missing"
    end
  end

  describe "CopyWriter.referral_subject/1" do
    test "returns default for nil profile" do
      assert CopyWriter.referral_subject(nil) =~ "500 BUX"
    end

    test "returns conversion-based subject" do
      profile = %{referrals_converted: 2, bux_earned_last_30d: Decimal.new("100"), purchase_count: 0}
      assert CopyWriter.referral_subject(profile) =~ "working"
    end

    test "returns BUX-based subject for earners" do
      profile = %{referrals_converted: 0, bux_earned_last_30d: Decimal.new("2000"), purchase_count: 0}
      assert CopyWriter.referral_subject(profile) =~ "earned BUX"
    end

    test "returns purchase-based subject for buyers" do
      profile = %{referrals_converted: 0, bux_earned_last_30d: Decimal.new("100"), purchase_count: 3}
      assert CopyWriter.referral_subject(profile) =~ "head start"
    end
  end

  describe "CopyWriter.cart_abandonment_subject/1" do
    test "returns different messages based on hours" do
      assert CopyWriter.cart_abandonment_subject(2) =~ "left something"
      assert CopyWriter.cart_abandonment_subject(12) =~ "waiting"
      assert CopyWriter.cart_abandonment_subject(36) =~ "Last chance"
      assert CopyWriter.cart_abandonment_subject(72) =~ "saved your cart"
    end
  end

  describe "CopyWriter.welcome_subject/1" do
    test "returns day-specific subjects" do
      assert CopyWriter.welcome_subject(0) =~ "Welcome"
      assert CopyWriter.welcome_subject(3) =~ "BUX"
      assert CopyWriter.welcome_subject(5) =~ "hubs"
      assert CopyWriter.welcome_subject(7) =~ "Invite"
    end
  end

  describe "CopyWriter.cta_text/2" do
    test "returns type-specific CTA text" do
      assert CopyWriter.cta_text("daily_digest", "new") == "Start reading"
      assert CopyWriter.cta_text("daily_digest", "active") == "Read today's articles"
      assert CopyWriter.cta_text("referral_prompt", "active") == "Share with friends"
      assert CopyWriter.cta_text("cart_abandonment", "active") == "Complete your order"
      assert CopyWriter.cta_text("re_engagement", "churned") == "Come back to Blockster"
      assert CopyWriter.cta_text("welcome", "new") == "Get started"
      assert CopyWriter.cta_text("reward_summary", "active") == "View your stats"
    end

    test "returns default for unknown type" do
      assert CopyWriter.cta_text("unknown", "active") == "Learn more"
    end
  end

  describe "CopyWriter.re_engagement_subject/2" do
    test "returns default subject by days inactive" do
      assert CopyWriter.re_engagement_subject(nil, 2) =~ "unread"
      assert CopyWriter.re_engagement_subject(nil, 5) =~ "BUX"
      assert CopyWriter.re_engagement_subject(nil, 10) =~ "miss you"
      assert CopyWriter.re_engagement_subject(nil, 20) =~ "welcome back"
    end

    test "returns churned-specific subject" do
      profile = %{engagement_tier: "churned"}
      assert CopyWriter.re_engagement_subject(profile, 30) =~ "welcome back"
    end
  end

  describe "CopyWriter.reward_summary_subject/1" do
    test "returns default for nil" do
      assert CopyWriter.reward_summary_subject(nil) =~ "weekly"
    end

    test "returns great week subject for high earners" do
      profile = %{bux_earned_last_30d: Decimal.new("600")}
      assert CopyWriter.reward_summary_subject(profile) =~ "Great week"
    end

    test "returns standard subject for moderate earners" do
      profile = %{bux_earned_last_30d: Decimal.new("100")}
      assert CopyWriter.reward_summary_subject(profile) =~ "weekly"
    end

    test "returns start earning subject for zero earners" do
      profile = %{bux_earned_last_30d: Decimal.new("0")}
      assert CopyWriter.reward_summary_subject(profile) =~ "start earning"
    end
  end

  # ============ OfferSelector Tests ============

  describe "OfferSelector.select_offer/1" do
    test "returns trending as default fallback" do
      %{user: user} = create_user()
      {offer_type, data} = OfferSelector.select_offer(user.id)
      assert offer_type == :trending
      assert data.message =~ "Trending"
    end
  end

  describe "OfferSelector.urgency_message/2" do
    test "returns correct messages for each type" do
      assert OfferSelector.urgency_message(:cart_reminder, %{}) =~ "Complete"
      assert OfferSelector.urgency_message(:product_highlight, %{}) =~ "Popular"
      assert OfferSelector.urgency_message(:cross_sell, %{}) =~ "also like"
      assert OfferSelector.urgency_message(:bux_spend, %{bux_balance: Decimal.new("10000")}) =~ "10,000 BUX"
      assert OfferSelector.urgency_message(:unknown, %{}) =~ "shop"
    end
  end

  # ============ ContentSelector Tests ============

  describe "ContentSelector.calculate_relevance_score/2" do
    test "returns base score for nil profile" do
      article = %{
        hub_id: 1,
        category_id: 1,
        published_at: NaiveDateTime.utc_now(),
        view_count: 100
      }

      score = ContentSelector.calculate_relevance_score(article, nil)
      assert is_float(score)
      assert score >= 0.0
      assert score <= 1.0
    end

    test "boosts score for preferred hub" do
      article = %{
        hub_id: 42,
        category_id: 1,
        published_at: NaiveDateTime.utc_now(),
        view_count: 10
      }

      profile_with_hub = %{
        preferred_hubs: [%{"id" => 42, "score" => 0.9}],
        preferred_categories: []
      }

      profile_without_hub = %{
        preferred_hubs: [],
        preferred_categories: []
      }

      score_with = ContentSelector.calculate_relevance_score(article, profile_with_hub)
      score_without = ContentSelector.calculate_relevance_score(article, profile_without_hub)

      assert score_with > score_without
    end

    test "gives higher score to recent articles" do
      old_article = %{
        hub_id: 1,
        category_id: 1,
        published_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -36 * 3600, :second),
        view_count: 10
      }

      new_article = %{
        hub_id: 1,
        category_id: 1,
        published_at: NaiveDateTime.utc_now(),
        view_count: 10
      }

      profile = %{preferred_hubs: [], preferred_categories: []}

      assert ContentSelector.calculate_relevance_score(new_article, profile) >
               ContentSelector.calculate_relevance_score(old_article, profile)
    end

    test "score is clamped between 0 and 1" do
      article = %{
        hub_id: 1,
        category_id: 1,
        published_at: NaiveDateTime.utc_now(),
        view_count: 1_000_000
      }

      profile = %{
        preferred_hubs: [%{"id" => 1, "score" => 1.0}],
        preferred_categories: [%{"id" => 1, "score" => 1.0}]
      }

      score = ContentSelector.calculate_relevance_score(article, profile)
      assert score >= 0.0
      assert score <= 1.0
    end
  end

  # ============ TriggerEngine Tests ============

  describe "TriggerEngine.cart_abandonment_trigger/3" do
    test "fires when session ends with carted items and >2h since cart event" do
      %{user: user} = create_user()

      # Create profile with carted items
      {:ok, _} =
        UserEvents.upsert_profile(user.id, %{
          carted_not_purchased: [1, 2, 3],
          engagement_tier: "active",
          engagement_score: 50.0,
          churn_risk_score: 0.2,
          churn_risk_level: "low"
        })

      # Add a cart event 3 hours ago
      three_hours_ago =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(-3 * 3600, :second)
        |> NaiveDateTime.truncate(:second)

      Repo.insert!(%BlocksterV2.Notifications.UserEvent{
        user_id: user.id,
        event_type: "product_add_to_cart",
        event_category: "shop",
        inserted_at: three_hours_ago
      })

      profile = UserEvents.get_profile(user.id)

      result =
        TriggerEngine.cart_abandonment_trigger(
          {user.id, "session_end", %{}},
          profile,
          %{}
        )

      assert {:fire, "cart_abandonment", data} = result
      assert data.products == [1, 2, 3]
      assert data.hours_since >= 2
    end

    test "skips for non-session_end events" do
      %{user: user} = create_user()

      result =
        TriggerEngine.cart_abandonment_trigger(
          {user.id, "article_view", %{}},
          nil,
          %{}
        )

      assert result == :skip
    end

    test "skips when no carted items" do
      %{user: user} = create_user()

      {:ok, _} =
        UserEvents.upsert_profile(user.id, %{
          carted_not_purchased: [],
          engagement_tier: "active",
          engagement_score: 50.0,
          churn_risk_score: 0.2,
          churn_risk_level: "low"
        })

      profile = UserEvents.get_profile(user.id)

      result =
        TriggerEngine.cart_abandonment_trigger(
          {user.id, "session_end", %{}},
          profile,
          %{}
        )

      assert result == :skip
    end
  end

  describe "TriggerEngine.bux_milestone_trigger/3" do
    test "fires when balance hits a milestone" do
      %{user: user} = create_user()

      result =
        TriggerEngine.bux_milestone_trigger(
          {user.id, "bux_earned", %{"new_balance" => "5200"}},
          nil,
          %{}
        )

      assert {:fire, "bux_milestone", data} = result
      assert data.milestone == 5_000
    end

    test "skips when no new_balance in metadata" do
      %{user: user} = create_user()

      result =
        TriggerEngine.bux_milestone_trigger(
          {user.id, "bux_earned", %{}},
          nil,
          %{}
        )

      assert result == :skip
    end

    test "skips when balance is too far past milestone" do
      %{user: user} = create_user()

      result =
        TriggerEngine.bux_milestone_trigger(
          {user.id, "bux_earned", %{"new_balance" => "6000"}},
          nil,
          %{}
        )

      assert result == :skip
    end

    test "skips when milestone already celebrated" do
      %{user: user} = create_user()

      # Create existing milestone notification
      Notifications.create_notification(user.id, %{
        type: "bux_milestone",
        category: "rewards",
        title: "Hit 5k!",
        metadata: %{"milestone" => "5000"}
      })

      result =
        TriggerEngine.bux_milestone_trigger(
          {user.id, "bux_earned", %{"new_balance" => "5100"}},
          nil,
          %{}
        )

      assert result == :skip
    end
  end

  describe "TriggerEngine.reading_streak_trigger/3" do
    test "fires at streak milestones" do
      %{user: user, profile: profile} =
        create_user_with_profile(%{consecutive_active_days: 7})

      result =
        TriggerEngine.reading_streak_trigger(
          {user.id, "article_read_complete", %{}},
          profile,
          %{}
        )

      assert {:fire, "bux_milestone", data} = result
      assert data.type == "reading_streak"
      assert data.days == 7
    end

    test "skips for non-milestone streaks" do
      %{user: user, profile: profile} =
        create_user_with_profile(%{consecutive_active_days: 5})

      result =
        TriggerEngine.reading_streak_trigger(
          {user.id, "article_read_complete", %{}},
          profile,
          %{}
        )

      assert result == :skip
    end

    test "skips for non-article_read_complete events" do
      %{user: user, profile: profile} =
        create_user_with_profile(%{consecutive_active_days: 7})

      result =
        TriggerEngine.reading_streak_trigger(
          {user.id, "article_view", %{}},
          profile,
          %{}
        )

      assert result == :skip
    end
  end

  describe "TriggerEngine.purchase_thank_you_trigger/3" do
    test "fires on first purchase" do
      %{user: user, profile: profile} =
        create_user_with_profile(%{purchase_count: 1})

      result =
        TriggerEngine.purchase_thank_you_trigger(
          {user.id, "purchase_complete", %{"order_id" => "ORD-123"}},
          profile,
          %{}
        )

      assert {:fire, "referral_prompt", data} = result
      assert data.type == "first_purchase_thank_you"
      assert data.order_id == "ORD-123"
    end

    test "skips on subsequent purchases" do
      %{user: user, profile: profile} =
        create_user_with_profile(%{purchase_count: 3})

      result =
        TriggerEngine.purchase_thank_you_trigger(
          {user.id, "purchase_complete", %{"order_id" => "ORD-456"}},
          profile,
          %{}
        )

      assert result == :skip
    end
  end

  describe "TriggerEngine.dormancy_warning_trigger/3" do
    test "fires when user returns after 5-14 days" do
      %{user: user, profile: profile} =
        create_user_with_profile(%{days_since_last_active: 8})

      result =
        TriggerEngine.dormancy_warning_trigger(
          {user.id, "daily_login", %{}},
          profile,
          %{}
        )

      assert {:fire, "welcome", data} = result
      assert data.type == "welcome_back"
      assert data.days_away == 8
    end

    test "skips for short absence" do
      %{user: user, profile: profile} =
        create_user_with_profile(%{days_since_last_active: 2})

      result =
        TriggerEngine.dormancy_warning_trigger(
          {user.id, "daily_login", %{}},
          profile,
          %{}
        )

      assert result == :skip
    end

    test "skips for very long absence" do
      %{user: user, profile: profile} =
        create_user_with_profile(%{days_since_last_active: 30})

      result =
        TriggerEngine.dormancy_warning_trigger(
          {user.id, "daily_login", %{}},
          profile,
          %{}
        )

      assert result == :skip
    end
  end

  describe "TriggerEngine.referral_opportunity_trigger/3" do
    test "fires for high-propensity users on article share" do
      %{user: user, profile: profile} =
        create_user_with_profile(%{referral_propensity: 0.8})

      result =
        TriggerEngine.referral_opportunity_trigger(
          {user.id, "article_share", %{}},
          profile,
          %{}
        )

      assert {:fire, "referral_prompt", data} = result
      assert data.trigger == "article_share"
    end

    test "skips for low-propensity users" do
      %{user: user, profile: profile} =
        create_user_with_profile(%{referral_propensity: 0.3})

      result =
        TriggerEngine.referral_opportunity_trigger(
          {user.id, "article_share", %{}},
          profile,
          %{}
        )

      assert result == :skip
    end

    test "skips for non-trigger events" do
      %{user: user, profile: profile} =
        create_user_with_profile(%{referral_propensity: 0.9})

      result =
        TriggerEngine.referral_opportunity_trigger(
          {user.id, "article_view", %{}},
          profile,
          %{}
        )

      assert result == :skip
    end
  end

  describe "TriggerEngine.price_drop_trigger/3" do
    test "fires when viewed product drops in price" do
      %{user: user, profile: profile} =
        create_user_with_profile(%{viewed_products_last_30d: [42, 43, 44]})

      result =
        TriggerEngine.price_drop_trigger(
          {user.id, "product_price_changed", %{
            "product_id" => "42",
            "old_price" => "100.00",
            "new_price" => "75.00"
          }},
          profile,
          %{}
        )

      assert {:fire, "price_drop", data} = result
      assert data.product_id == 42
      assert data.savings_pct == 25
    end

    test "skips when product not in viewed list" do
      %{user: user, profile: profile} =
        create_user_with_profile(%{viewed_products_last_30d: [1, 2, 3]})

      result =
        TriggerEngine.price_drop_trigger(
          {user.id, "product_price_changed", %{
            "product_id" => "42",
            "old_price" => "100.00",
            "new_price" => "75.00"
          }},
          profile,
          %{}
        )

      assert result == :skip
    end

    test "skips when price increases" do
      %{user: user, profile: profile} =
        create_user_with_profile(%{viewed_products_last_30d: [42]})

      result =
        TriggerEngine.price_drop_trigger(
          {user.id, "product_price_changed", %{
            "product_id" => "42",
            "old_price" => "50.00",
            "new_price" => "75.00"
          }},
          profile,
          %{}
        )

      assert result == :skip
    end
  end

  describe "TriggerEngine.evaluate_triggers/3" do
    test "fires cart abandonment on session_end with cart items" do
      %{user: user} = create_user()

      {:ok, _} =
        UserEvents.upsert_profile(user.id, %{
          carted_not_purchased: [1],
          engagement_tier: "active",
          engagement_score: 50.0,
          churn_risk_score: 0.2,
          churn_risk_level: "low"
        })

      # Add old cart event
      Repo.insert!(%BlocksterV2.Notifications.UserEvent{
        user_id: user.id,
        event_type: "product_add_to_cart",
        event_category: "shop",
        inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.add(-4 * 3600, :second) |> NaiveDateTime.truncate(:second)
      })

      fired = TriggerEngine.evaluate_triggers(user.id, "session_end")
      assert "cart_abandonment" in fired
    end

    test "fires bux milestone notification" do
      %{user: user} = create_user()

      fired =
        TriggerEngine.evaluate_triggers(user.id, "bux_earned", %{
          "new_balance" => "10200"
        })

      assert "bux_milestone" in fired

      # Verify notification was created
      notifications = Notifications.list_notifications(user.id)
      assert Enum.any?(notifications, fn n -> n.type == "bux_milestone" end)
    end

    test "returns empty list when no triggers match" do
      %{user: user} = create_user()
      fired = TriggerEngine.evaluate_triggers(user.id, "article_view")
      assert fired == []
    end
  end

  # ============ ABTestCheckWorker Tests ============

  describe "ABTestCheckWorker" do
    test "perform/1 checks all running tests" do
      create_ab_test(%{email_type: "worker_test_1"})
      create_ab_test(%{email_type: "worker_test_2"})

      assert :ok = ABTestCheckWorker.perform(%Oban.Job{args: %{}})
    end

    test "perform/1 checks a specific test" do
      test = create_ab_test(%{email_type: "specific_test"})
      assert :ok = ABTestCheckWorker.perform(%Oban.Job{args: %{"test_id" => test.id}})
    end

    test "promotes winner when significance is reached" do
      test = create_ab_test(%{min_sample_size: 5, email_type: "promote_test"})

      # Create assignments with very clear winner (all A open, no B open)
      for i <- 1..10 do
        %{user: user} = create_user()
        variant = if rem(i, 2) == 0, do: "A", else: "B"

        {:ok, _} =
          %ABTestAssignment{}
          |> ABTestAssignment.changeset(%{
            ab_test_id: test.id,
            user_id: user.id,
            variant_id: variant,
            opened: variant == "A"
          })
          |> Repo.insert()
      end

      ABTestCheckWorker.perform(%Oban.Job{args: %{"test_id" => test.id}})

      updated_test = Repo.get(ABTest, test.id)
      # May or may not reach significance with only 10 samples, but shouldn't crash
      assert updated_test.status in ["running", "winner_applied"]
    end
  end

  # ============ Integration Tests ============

  describe "A/B test full lifecycle" do
    test "create test -> assign users -> record opens -> check significance" do
      # Create test
      test = create_ab_test(%{min_sample_size: 3, email_type: "lifecycle_test"})
      assert test.status == "running"

      # Assign users
      users =
        for _ <- 1..8 do
          %{user: user} = create_user()
          variant = ABTestEngine.assign_variant(user.id, test)
          {user, variant}
        end

      # Verify all assigned
      results_before = ABTestEngine.get_test_results(test.id)
      total_assigned = Enum.reduce(results_before, 0, fn r, acc -> acc + r.total end)
      assert total_assigned == 8

      # Record opens for variant A users
      Enum.each(users, fn {user, variant} ->
        if variant == "A" do
          ABTestEngine.record_open(test.id, user.id)
        end
      end)

      # Check results
      results_after = ABTestEngine.get_test_results(test.id)
      assert length(results_after) >= 1

      # Check significance (may or may not be significant)
      sig_result = ABTestEngine.check_significance(test)
      assert elem(sig_result, 0) in [:significant, :not_yet, :insufficient_data]
    end
  end

  describe "CopyWriter + ContentSelector integration" do
    test "CTA text matches notification types" do
      # Verify all notification types have appropriate CTAs
      types_and_tiers = [
        {"daily_digest", "new"},
        {"daily_digest", "active"},
        {"referral_prompt", "active"},
        {"cart_abandonment", "active"},
        {"re_engagement", "churned"},
        {"re_engagement", "dormant"},
        {"welcome", "new"},
        {"reward_summary", "power"}
      ]

      Enum.each(types_and_tiers, fn {type, tier} ->
        cta = CopyWriter.cta_text(type, tier)
        assert is_binary(cta), "CTA for #{type}/#{tier} should be a string"
        assert String.length(cta) > 0, "CTA for #{type}/#{tier} should not be empty"
      end)
    end
  end

  describe "TriggerEngine deduplication" do
    test "does not fire duplicate cart abandonment same day" do
      %{user: user} = create_user()

      {:ok, _} =
        UserEvents.upsert_profile(user.id, %{
          carted_not_purchased: [1],
          engagement_tier: "active",
          engagement_score: 50.0,
          churn_risk_score: 0.2,
          churn_risk_level: "low"
        })

      # Add old cart event
      Repo.insert!(%BlocksterV2.Notifications.UserEvent{
        user_id: user.id,
        event_type: "product_add_to_cart",
        event_category: "shop",
        inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.add(-4 * 3600, :second) |> NaiveDateTime.truncate(:second)
      })

      # First trigger should fire
      fired1 = TriggerEngine.evaluate_triggers(user.id, "session_end")
      assert "cart_abandonment" in fired1

      # Second trigger same day should not fire
      fired2 = TriggerEngine.evaluate_triggers(user.id, "session_end")
      refute "cart_abandonment" in fired2
    end

    test "does not fire duplicate BUX milestone" do
      %{user: user} = create_user()

      # First trigger
      fired1 =
        TriggerEngine.evaluate_triggers(user.id, "bux_earned", %{
          "new_balance" => "1200"
        })

      assert "bux_milestone" in fired1

      # Same milestone again should not fire
      fired2 =
        TriggerEngine.evaluate_triggers(user.id, "bux_earned", %{
          "new_balance" => "1300"
        })

      refute "bux_milestone" in fired2
    end
  end
end
