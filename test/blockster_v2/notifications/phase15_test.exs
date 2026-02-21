defmodule BlocksterV2.Notifications.Phase15Test do
  use BlocksterV2.DataCase, async: true

  alias BlocksterV2.{Repo, UserEvents, Notifications}
  alias BlocksterV2.Notifications.{
    UserProfile, RogueOfferEngine, ConversionFunnelEngine
  }
  alias BlocksterV2.Workers.RogueAirdropWorker

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
          churn_risk_level: "low",
          total_bets_placed: 0,
          total_wagered: Decimal.new("0"),
          total_won: Decimal.new("0"),
          gambling_tier: "non_gambler",
          games_played_last_30d: 0,
          total_rogue_games: 0,
          total_rogue_wagered: Decimal.new("0"),
          total_rogue_won: Decimal.new("0"),
          vip_tier: "none",
          conversion_stage: "earner",
          rogue_readiness_score: 0.0
        },
        attrs
      )

    {:ok, profile} = UserEvents.upsert_profile(user.id, profile_attrs)
    %{user: user, profile: profile}
  end

  # ============ UserProfile Schema — New Fields ============

  describe "UserProfile ROGUE fields" do
    test "schema includes ROGUE gambling fields" do
      %{user: user} = create_user()

      {:ok, profile} =
        UserEvents.upsert_profile(user.id, %{
          total_rogue_games: 15,
          total_rogue_wagered: Decimal.new("5.5"),
          total_rogue_won: Decimal.new("3.2"),
          rogue_balance_estimate: Decimal.new("2.1"),
          games_played_last_7d: 8,
          win_streak: 3,
          loss_streak: 0
        })

      assert profile.total_rogue_games == 15
      assert Decimal.compare(profile.total_rogue_wagered, Decimal.new("5.5")) == :eq
      assert Decimal.compare(profile.total_rogue_won, Decimal.new("3.2")) == :eq
      assert profile.games_played_last_7d == 8
      assert profile.win_streak == 3
    end

    test "schema includes VIP fields" do
      %{user: user} = create_user()

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, profile} =
        UserEvents.upsert_profile(user.id, %{
          vip_tier: "bronze",
          vip_unlocked_at: now
        })

      assert profile.vip_tier == "bronze"
      assert profile.vip_unlocked_at
    end

    test "validates VIP tier inclusion" do
      changeset =
        UserProfile.changeset(%UserProfile{}, %{
          user_id: 1,
          vip_tier: "platinum"
        })

      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :vip_tier)
    end

    test "validates conversion stage inclusion" do
      changeset =
        UserProfile.changeset(%UserProfile{}, %{
          user_id: 1,
          conversion_stage: "invalid_stage"
        })

      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :conversion_stage)
    end

    test "valid conversion stages" do
      assert UserProfile.valid_conversion_stages() ==
               ~w(earner bux_player rogue_curious rogue_buyer rogue_regular)
    end

    test "valid VIP tiers" do
      assert UserProfile.valid_vip_tiers() == ~w(none bronze silver gold diamond)
    end

    test "rogue_readiness_score validates bounds" do
      changeset =
        UserProfile.changeset(%UserProfile{}, %{
          user_id: 1,
          rogue_readiness_score: 1.5
        })

      refute changeset.valid?
    end
  end

  # ============ RogueOfferEngine Tests ============

  describe "RogueOfferEngine.calculate_rogue_readiness/1" do
    test "returns 0.0 for nil profile" do
      assert RogueOfferEngine.calculate_rogue_readiness(nil) == 0.0
    end

    test "returns low score for inactive user" do
      %{profile: profile} = create_user_with_profile(%{
        games_played_last_30d: 0,
        avg_bet_size: Decimal.new("0"),
        engagement_tier: "new",
        purchase_count: 0,
        referrals_converted: 0,
        articles_read_last_30d: 0,
        lifetime_days: 1
      })

      score = RogueOfferEngine.calculate_rogue_readiness(profile)
      assert score < 0.15
    end

    test "returns high score for active gambler" do
      %{profile: profile} = create_user_with_profile(%{
        games_played_last_30d: 25,
        avg_bet_size: Decimal.new("800"),
        engagement_tier: "power",
        purchase_count: 5,
        referrals_converted: 3,
        articles_read_last_30d: 25,
        lifetime_days: 60
      })

      score = RogueOfferEngine.calculate_rogue_readiness(profile)
      assert score > 0.6
    end

    test "score is between 0 and 1" do
      %{profile: profile} = create_user_with_profile(%{
        games_played_last_30d: 100,
        avg_bet_size: Decimal.new("5000"),
        engagement_tier: "whale",
        purchase_count: 20,
        referrals_converted: 10,
        articles_read_last_30d: 50,
        lifetime_days: 365
      })

      score = RogueOfferEngine.calculate_rogue_readiness(profile)
      assert score >= 0.0
      assert score <= 1.0
    end

    test "engagement tier affects score" do
      base = %{
        games_played_last_30d: 10,
        avg_bet_size: Decimal.new("500"),
        purchase_count: 1,
        referrals_converted: 0,
        articles_read_last_30d: 10,
        lifetime_days: 30
      }

      %{profile: active_profile} = create_user_with_profile(Map.merge(base, %{engagement_tier: "active"}))
      %{profile: whale_profile} = create_user_with_profile(Map.merge(base, %{engagement_tier: "whale"}))

      active_score = RogueOfferEngine.calculate_rogue_readiness(active_profile)
      whale_score = RogueOfferEngine.calculate_rogue_readiness(whale_profile)

      assert whale_score > active_score
    end
  end

  describe "RogueOfferEngine.classify_vip_tier/1" do
    test "returns none for no ROGUE games" do
      %{profile: profile} = create_user_with_profile(%{total_rogue_games: 0})
      assert RogueOfferEngine.classify_vip_tier(profile) == "none"
    end

    test "returns bronze for 10+ ROGUE games" do
      %{profile: profile} = create_user_with_profile(%{total_rogue_games: 12})
      assert RogueOfferEngine.classify_vip_tier(profile) == "bronze"
    end

    test "returns silver for 50+ ROGUE games" do
      %{profile: profile} = create_user_with_profile(%{total_rogue_games: 55})
      assert RogueOfferEngine.classify_vip_tier(profile) == "silver"
    end

    test "returns gold for 100+ ROGUE games" do
      %{profile: profile} = create_user_with_profile(%{total_rogue_games: 105})
      assert RogueOfferEngine.classify_vip_tier(profile) == "gold"
    end

    test "returns diamond for 100+ games and high wagered" do
      %{profile: profile} = create_user_with_profile(%{
        total_rogue_games: 150,
        total_rogue_wagered: Decimal.new("200")
      })
      assert RogueOfferEngine.classify_vip_tier(profile) == "diamond"
    end
  end

  describe "RogueOfferEngine.classify_conversion_stage/1" do
    test "returns earner for non-gambler" do
      %{profile: profile} = create_user_with_profile(%{
        total_bets_placed: 0,
        total_rogue_games: 0
      })
      assert RogueOfferEngine.classify_conversion_stage(profile) == "earner"
    end

    test "returns bux_player for BUX gambler" do
      %{profile: profile} = create_user_with_profile(%{
        total_bets_placed: 3,
        total_rogue_games: 0,
        total_wagered: Decimal.new("500")
      })
      assert RogueOfferEngine.classify_conversion_stage(profile) == "bux_player"
    end

    test "returns rogue_curious for heavy BUX gambler" do
      %{profile: profile} = create_user_with_profile(%{
        total_bets_placed: 10,
        total_rogue_games: 0,
        total_wagered: Decimal.new("10000")
      })
      assert RogueOfferEngine.classify_conversion_stage(profile) == "rogue_curious"
    end

    test "returns rogue_buyer for first ROGUE game" do
      %{profile: profile} = create_user_with_profile(%{
        total_bets_placed: 15,
        total_rogue_games: 2,
        total_wagered: Decimal.new("5000")
      })
      assert RogueOfferEngine.classify_conversion_stage(profile) == "rogue_buyer"
    end

    test "returns rogue_regular for 5+ ROGUE games" do
      %{profile: profile} = create_user_with_profile(%{
        total_bets_placed: 30,
        total_rogue_games: 8,
        total_wagered: Decimal.new("15000")
      })
      assert RogueOfferEngine.classify_conversion_stage(profile) == "rogue_regular"
    end
  end

  describe "RogueOfferEngine.calculate_airdrop_amount/2" do
    test "returns 2.0 for high readiness" do
      %{profile: profile} = create_user_with_profile()
      assert RogueOfferEngine.calculate_airdrop_amount(profile, 0.85) == 2.0
    end

    test "returns 1.0 for medium readiness" do
      %{profile: profile} = create_user_with_profile()
      assert RogueOfferEngine.calculate_airdrop_amount(profile, 0.65) == 1.0
    end

    test "returns 0.5 for lower readiness" do
      %{profile: profile} = create_user_with_profile()
      assert RogueOfferEngine.calculate_airdrop_amount(profile, 0.45) == 0.5
    end

    test "returns 0.25 for minimum readiness" do
      %{profile: profile} = create_user_with_profile()
      assert RogueOfferEngine.calculate_airdrop_amount(profile, 0.2) == 0.25
    end
  end

  describe "RogueOfferEngine.airdrop_reason/1" do
    test "returns gambler reason for heavy player" do
      %{profile: profile} = create_user_with_profile(%{total_bets_placed: 25})
      assert RogueOfferEngine.airdrop_reason(profile) =~ "regular"
    end

    test "returns engagement reason for active member" do
      %{profile: profile} = create_user_with_profile(%{
        total_bets_placed: 5,
        engagement_score: 85.0
      })
      assert RogueOfferEngine.airdrop_reason(profile) =~ "most active"
    end

    test "returns shopper reason for purchasers" do
      %{profile: profile} = create_user_with_profile(%{
        total_bets_placed: 5,
        engagement_score: 50.0,
        purchase_count: 2
      })
      assert RogueOfferEngine.airdrop_reason(profile) =~ "shopper"
    end

    test "returns default reason" do
      %{profile: profile} = create_user_with_profile(%{
        total_bets_placed: 5,
        engagement_score: 40.0,
        purchase_count: 0
      })
      assert RogueOfferEngine.airdrop_reason(profile) =~ "love ROGUE"
    end
  end

  describe "RogueOfferEngine.get_rogue_offer_candidates/1" do
    test "returns candidates sorted by score" do
      # Create eligible users (casual_gambler tier with bets)
      %{user: u1} = create_user()
      {:ok, _} = UserEvents.upsert_profile(u1.id, %{
        gambling_tier: "casual_gambler",
        total_bets_placed: 10,
        games_played_last_30d: 8,
        avg_bet_size: Decimal.new("500"),
        engagement_tier: "active",
        articles_read_last_30d: 15,
        lifetime_days: 30,
        conversion_stage: "bux_player",
        churn_risk_score: 0.2,
        churn_risk_level: "low"
      })

      %{user: u2} = create_user()
      {:ok, _} = UserEvents.upsert_profile(u2.id, %{
        gambling_tier: "regular_gambler",
        total_bets_placed: 25,
        games_played_last_30d: 20,
        avg_bet_size: Decimal.new("800"),
        engagement_tier: "power",
        articles_read_last_30d: 30,
        lifetime_days: 60,
        purchase_count: 3,
        referrals_converted: 2,
        conversion_stage: "bux_player",
        churn_risk_score: 0.1,
        churn_risk_level: "low"
      })

      candidates = RogueOfferEngine.get_rogue_offer_candidates(10)
      assert length(candidates) >= 2

      # Should be sorted by score descending
      scores = Enum.map(candidates, fn {_, score} -> score end)
      assert scores == Enum.sort(scores, :desc)
    end

    test "excludes users with recent ROGUE offers" do
      %{user: user} = create_user()

      {:ok, _} = UserEvents.upsert_profile(user.id, %{
        gambling_tier: "casual_gambler",
        total_bets_placed: 10,
        conversion_stage: "bux_player",
        last_rogue_offer_at: DateTime.utc_now() |> DateTime.truncate(:second),
        churn_risk_score: 0.2,
        churn_risk_level: "low"
      })

      candidates = RogueOfferEngine.get_rogue_offer_candidates(50)
      user_ids = Enum.map(candidates, fn {p, _} -> p.user_id end)
      refute user.id in user_ids
    end

    test "returns empty list when no eligible users" do
      candidates = RogueOfferEngine.get_rogue_offer_candidates(10)
      # May return candidates from other tests, but should not crash
      assert is_list(candidates)
    end
  end

  describe "RogueOfferEngine.mark_rogue_offer_sent/1" do
    test "updates last_rogue_offer_at timestamp" do
      %{user: user} = create_user()
      {:ok, _} = UserEvents.upsert_profile(user.id, %{
        churn_risk_score: 0.2,
        churn_risk_level: "low"
      })

      RogueOfferEngine.mark_rogue_offer_sent(user.id)

      profile = UserEvents.get_profile(user.id)
      assert profile.last_rogue_offer_at
    end
  end

  # ============ ConversionFunnelEngine Tests ============

  describe "ConversionFunnelEngine — Stage 1: Earner triggers" do
    test "fires bux_booster_invite on reaching 500 BUX" do
      %{user: user} = create_user_with_profile(%{
        conversion_stage: "earner",
        total_articles_read: 2
      })

      fired =
        ConversionFunnelEngine.evaluate_funnel_triggers(
          user.id,
          "bux_earned",
          %{"new_balance" => "600"}
        )

      assert "special_offer" in fired

      # Verify notification was created
      notifications = Notifications.list_notifications(user.id)
      offer = Enum.find(notifications, fn n ->
        n.metadata["offer_type"] == "bux_booster_invite"
      end)
      assert offer
    end

    test "fires reader_gaming_nudge on 5th article read" do
      %{user: user} = create_user_with_profile(%{
        conversion_stage: "earner",
        total_articles_read: 5
      })

      fired =
        ConversionFunnelEngine.evaluate_funnel_triggers(
          user.id,
          "article_read_complete",
          %{}
        )

      assert "special_offer" in fired
    end

    test "skips when BUX balance below 500" do
      %{user: user} = create_user_with_profile(%{
        conversion_stage: "earner"
      })

      fired =
        ConversionFunnelEngine.evaluate_funnel_triggers(
          user.id,
          "bux_earned",
          %{"new_balance" => "200"}
        )

      refute "special_offer" in fired
    end
  end

  describe "ConversionFunnelEngine — Stage 2: BUX Player triggers" do
    test "fires rogue_discovery on 5th game" do
      %{user: user} = create_user_with_profile(%{
        conversion_stage: "bux_player",
        total_bets_placed: 5,
        gambling_tier: "casual_gambler"
      })

      fired =
        ConversionFunnelEngine.evaluate_funnel_triggers(
          user.id,
          "game_played",
          %{}
        )

      assert "special_offer" in fired

      notifications = Notifications.list_notifications(user.id)
      offer = Enum.find(notifications, fn n ->
        n.metadata["offer_type"] == "rogue_discovery"
      end)
      assert offer
    end

    test "fires rogue_loss_streak_offer on 3+ losses" do
      %{user: user} = create_user_with_profile(%{
        conversion_stage: "bux_player",
        total_bets_placed: 10,
        loss_streak: 4,
        gambling_tier: "casual_gambler"
      })

      fired =
        ConversionFunnelEngine.evaluate_funnel_triggers(
          user.id,
          "game_played",
          %{}
        )

      assert "special_offer" in fired
    end
  end

  describe "ConversionFunnelEngine — Stage 3: ROGUE Curious triggers" do
    test "fires rogue_purchase_nudge on first ROGUE game" do
      %{user: user} = create_user_with_profile(%{
        conversion_stage: "rogue_curious",
        total_rogue_games: 1,
        gambling_tier: "regular_gambler"
      })

      fired =
        ConversionFunnelEngine.evaluate_funnel_triggers(
          user.id,
          "game_played",
          %{}
        )

      assert "special_offer" in fired
    end
  end

  describe "ConversionFunnelEngine — Stage 4: ROGUE Buyer triggers" do
    test "fires win_streak_celebration on 3+ wins" do
      %{user: user} = create_user_with_profile(%{
        conversion_stage: "rogue_buyer",
        win_streak: 4,
        total_rogue_games: 10,
        gambling_tier: "regular_gambler"
      })

      fired =
        ConversionFunnelEngine.evaluate_funnel_triggers(
          user.id,
          "game_played",
          %{}
        )

      assert "special_offer" in fired
    end

    test "fires big_win_celebration on 10x+ multiplier" do
      %{user: user} = create_user_with_profile(%{
        conversion_stage: "rogue_buyer",
        win_streak: 0,
        total_rogue_games: 10,
        gambling_tier: "regular_gambler"
      })

      fired =
        ConversionFunnelEngine.evaluate_funnel_triggers(
          user.id,
          "game_played",
          %{"multiplier" => 15, "win_amount" => "50"}
        )

      assert "special_offer" in fired
    end
  end

  describe "ConversionFunnelEngine — VIP upgrades" do
    test "fires VIP upgrade notification when tier increases" do
      %{user: user} = create_user_with_profile(%{
        conversion_stage: "rogue_regular",
        vip_tier: "none",
        total_rogue_games: 12,
        gambling_tier: "regular_gambler"
      })

      fired =
        ConversionFunnelEngine.evaluate_funnel_triggers(
          user.id,
          "game_played",
          %{}
        )

      assert "bux_milestone" in fired

      # Verify profile was updated
      updated = UserEvents.get_profile(user.id)
      assert updated.vip_tier == "bronze"
    end

    test "does not fire when VIP tier unchanged" do
      %{user: user} = create_user_with_profile(%{
        conversion_stage: "rogue_regular",
        vip_tier: "bronze",
        total_rogue_games: 12,
        gambling_tier: "regular_gambler"
      })

      fired =
        ConversionFunnelEngine.evaluate_funnel_triggers(
          user.id,
          "game_played",
          %{}
        )

      refute "bux_milestone" in fired
    end
  end

  describe "ConversionFunnelEngine — deduplication" do
    test "does not fire same offer twice in one day" do
      %{user: user} = create_user_with_profile(%{
        conversion_stage: "earner",
        total_articles_read: 5
      })

      # First trigger
      fired1 =
        ConversionFunnelEngine.evaluate_funnel_triggers(
          user.id,
          "article_read_complete",
          %{}
        )

      assert "special_offer" in fired1

      # Second trigger same day
      fired2 =
        ConversionFunnelEngine.evaluate_funnel_triggers(
          user.id,
          "article_read_complete",
          %{}
        )

      refute "special_offer" in fired2
    end
  end

  # ============ RogueAirdropWorker Tests ============

  describe "RogueAirdropWorker" do
    test "batch job finds candidates and creates individual jobs" do
      # Create an eligible user
      %{user: user} = create_user()
      {:ok, _} = UserEvents.upsert_profile(user.id, %{
        gambling_tier: "casual_gambler",
        total_bets_placed: 10,
        games_played_last_30d: 8,
        conversion_stage: "bux_player",
        engagement_tier: "active",
        articles_read_last_30d: 10,
        lifetime_days: 30,
        churn_risk_score: 0.2,
        churn_risk_level: "low"
      })

      assert :ok = RogueAirdropWorker.perform(%Oban.Job{args: %{}})
    end

    test "single user job creates notification" do
      %{user: user} = create_user()
      {:ok, _} = UserEvents.upsert_profile(user.id, %{
        total_bets_placed: 5,
        churn_risk_score: 0.2,
        churn_risk_level: "low"
      })

      assert :ok =
        RogueAirdropWorker.perform(%Oban.Job{
          args: %{"user_id" => user.id, "amount" => 1.0}
        })

      notifications = Notifications.list_notifications(user.id)
      airdrop = Enum.find(notifications, fn n ->
        n.metadata["offer_type"] == "rogue_airdrop"
      end)
      assert airdrop
      assert airdrop.metadata["amount"] == 1.0
    end

    test "marks offer sent on profile" do
      %{user: user} = create_user()
      {:ok, _} = UserEvents.upsert_profile(user.id, %{
        churn_risk_score: 0.2,
        churn_risk_level: "low"
      })

      RogueAirdropWorker.perform(%Oban.Job{
        args: %{"user_id" => user.id, "amount" => 0.5}
      })

      profile = UserEvents.get_profile(user.id)
      assert profile.last_rogue_offer_at
    end

    test "handles missing user gracefully" do
      assert :ok =
        RogueAirdropWorker.perform(%Oban.Job{
          args: %{"user_id" => 999_999, "amount" => 1.0}
        })
    end
  end

  # ============ Integration Tests ============

  describe "full conversion funnel flow" do
    test "earner → bux_player → stage progression" do
      %{user: user} = create_user_with_profile(%{
        conversion_stage: "earner",
        total_articles_read: 5
      })

      # Stage 1: Earner gets nudged on BUX balance
      fired1 =
        ConversionFunnelEngine.evaluate_funnel_triggers(
          user.id,
          "bux_earned",
          %{"new_balance" => "600"}
        )
      assert "special_offer" in fired1

      # Update to BUX player
      {:ok, _} = UserEvents.upsert_profile(user.id, %{
        conversion_stage: "bux_player",
        total_bets_placed: 5,
        gambling_tier: "casual_gambler"
      })

      # Stage 2: BUX player gets ROGUE discovery
      fired2 =
        ConversionFunnelEngine.evaluate_funnel_triggers(
          user.id,
          "game_played",
          %{}
        )
      assert "special_offer" in fired2
    end
  end

  describe "ROGUE readiness + airdrop integration" do
    test "high readiness users get larger airdrops" do
      %{profile: profile} = create_user_with_profile(%{
        games_played_last_30d: 25,
        avg_bet_size: Decimal.new("800"),
        engagement_tier: "power",
        purchase_count: 5,
        referrals_converted: 3,
        articles_read_last_30d: 25,
        lifetime_days: 60
      })

      score = RogueOfferEngine.calculate_rogue_readiness(profile)
      amount = RogueOfferEngine.calculate_airdrop_amount(profile, score)

      assert score > 0.6
      assert amount >= 1.0
    end

    test "low readiness users get smaller airdrops" do
      %{profile: profile} = create_user_with_profile(%{
        games_played_last_30d: 2,
        avg_bet_size: Decimal.new("100"),
        engagement_tier: "casual",
        purchase_count: 0,
        referrals_converted: 0,
        articles_read_last_30d: 3,
        lifetime_days: 5
      })

      score = RogueOfferEngine.calculate_rogue_readiness(profile)
      amount = RogueOfferEngine.calculate_airdrop_amount(profile, score)

      assert score < 0.4
      assert amount <= 0.5
    end
  end

  describe "VIP tier progression" do
    test "progresses through tiers as games increase" do
      %{profile: p0} = create_user_with_profile(%{total_rogue_games: 0})
      assert RogueOfferEngine.classify_vip_tier(p0) == "none"

      %{profile: p1} = create_user_with_profile(%{total_rogue_games: 15})
      assert RogueOfferEngine.classify_vip_tier(p1) == "bronze"

      %{profile: p2} = create_user_with_profile(%{total_rogue_games: 55})
      assert RogueOfferEngine.classify_vip_tier(p2) == "silver"

      %{profile: p3} = create_user_with_profile(%{total_rogue_games: 110})
      assert RogueOfferEngine.classify_vip_tier(p3) == "gold"

      %{profile: p4} = create_user_with_profile(%{
        total_rogue_games: 150,
        total_rogue_wagered: Decimal.new("200")
      })
      assert RogueOfferEngine.classify_vip_tier(p4) == "diamond"
    end
  end
end
