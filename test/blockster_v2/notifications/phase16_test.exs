defmodule BlocksterV2.Notifications.Phase16Test do
  use BlocksterV2.DataCase, async: true

  alias BlocksterV2.{Repo, UserEvents, Notifications}
  alias BlocksterV2.Notifications.{ReferralEngine, UserProfile}
  alias BlocksterV2.Workers.ReferralLeaderboardWorker

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
          churn_risk_score: 0.2,
          churn_risk_level: "low",
          referral_propensity: 0.5,
          referrals_sent: 0,
          referrals_converted: 0
        },
        attrs
      )

    {:ok, profile} = UserEvents.upsert_profile(user.id, profile_attrs)
    %{user: user, profile: profile}
  end

  # ============ Reward Tiers ============

  describe "ReferralEngine.get_reward_tier/1" do
    test "returns tier 1 for 1-5 referrals" do
      tier = ReferralEngine.get_reward_tier(3)
      assert tier.referrer_bux == 500
      assert tier.friend_bux == 500
      assert tier.badge == nil
    end

    test "returns tier 2 for 6-15 referrals" do
      tier = ReferralEngine.get_reward_tier(10)
      assert tier.referrer_bux == 750
      assert tier.badge == "ambassador"
    end

    test "returns tier 3 for 16-30 referrals" do
      tier = ReferralEngine.get_reward_tier(20)
      assert tier.referrer_bux == 1000
      assert tier.friend_bux == 750
      assert tier.rogue == 1.0
    end

    test "returns tier 4 for 31-50 referrals" do
      tier = ReferralEngine.get_reward_tier(40)
      assert tier.referrer_bux == 1500
      assert tier.friend_bux == 1000
      assert tier.badge == "vip_referrer"
    end

    test "returns tier 5 for 51+ referrals" do
      tier = ReferralEngine.get_reward_tier(100)
      assert tier.referrer_bux == 2000
      assert tier.badge == "blockster_legend"
      assert tier.rogue == 0.5
    end
  end

  describe "ReferralEngine.calculate_referral_reward/1" do
    test "returns correct reward for tier 1" do
      {referrer, friend, rogue} = ReferralEngine.calculate_referral_reward(3)
      assert referrer == 500
      assert friend == 500
      assert rogue == 0
    end

    test "returns escalating rewards at higher tiers" do
      {r1, _, _} = ReferralEngine.calculate_referral_reward(5)
      {r2, _, _} = ReferralEngine.calculate_referral_reward(10)
      {r3, _, _} = ReferralEngine.calculate_referral_reward(25)

      assert r2 > r1
      assert r3 > r2
    end

    test "includes ROGUE bonus at tier 3+" do
      {_, _, rogue_t2} = ReferralEngine.calculate_referral_reward(10)
      {_, _, rogue_t3} = ReferralEngine.calculate_referral_reward(20)

      assert rogue_t2 == 0
      assert rogue_t3 > 0
    end
  end

  describe "ReferralEngine.badge_at_count/1" do
    test "returns nil for counts below badge threshold" do
      assert ReferralEngine.badge_at_count(1) == nil
      assert ReferralEngine.badge_at_count(5) == nil
    end

    test "returns ambassador badge at count 6" do
      assert ReferralEngine.badge_at_count(6) == "ambassador"
    end

    test "returns nil for counts within same badge tier" do
      assert ReferralEngine.badge_at_count(10) == nil
    end

    test "returns vip_referrer badge at count 31" do
      assert ReferralEngine.badge_at_count(31) == "vip_referrer"
    end

    test "returns blockster_legend at count 51" do
      assert ReferralEngine.badge_at_count(51) == "blockster_legend"
    end
  end

  describe "ReferralEngine.next_tier_info/1" do
    test "returns distance to next tier" do
      {next_min, remaining} = ReferralEngine.next_tier_info(3)
      assert next_min == 6
      assert remaining == 3
    end

    test "returns max_tier for highest tier" do
      assert ReferralEngine.next_tier_info(60) == :max_tier
    end

    test "returns correct remaining at tier boundary" do
      {_next_min, remaining} = ReferralEngine.next_tier_info(5)
      assert remaining == 1
    end
  end

  # ============ Lifecycle Notifications ============

  describe "ReferralEngine.notify_referral_signup/3" do
    test "creates signup notification for referrer" do
      %{user: referrer} = create_user()

      {:ok, notif} =
        ReferralEngine.notify_referral_signup(referrer.id, "Alice", 3)

      assert notif.type == "referral_signup"
      assert notif.category == "social"
      assert notif.title =~ "Alice"
      assert notif.title =~ "500 BUX"
      assert notif.metadata[:bux_earned] == 500
      assert notif.metadata[:referrals_converted] == 3
    end

    test "includes badge info when badge unlocked" do
      %{user: referrer} = create_user()

      {:ok, notif} =
        ReferralEngine.notify_referral_signup(referrer.id, "Bob", 6)

      assert notif.metadata[:badge_unlocked] == "ambassador"
    end

    test "includes next tier info in body" do
      %{user: referrer} = create_user()

      {:ok, notif} =
        ReferralEngine.notify_referral_signup(referrer.id, "Carol", 4)

      assert notif.body =~ "more referral"
    end
  end

  describe "ReferralEngine.notify_referral_first_bux/2" do
    test "creates first BUX notification" do
      %{user: referrer} = create_user()

      {:ok, notif} =
        ReferralEngine.notify_referral_first_bux(referrer.id, "Dave")

      assert notif.type == "referral_reward"
      assert notif.title =~ "Dave"
      assert notif.title =~ "first BUX"
      assert notif.metadata[:milestone] == "first_bux"
    end
  end

  describe "ReferralEngine.notify_referral_first_purchase/2" do
    test "creates first purchase notification with bonus" do
      %{user: referrer} = create_user()

      {:ok, notif} =
        ReferralEngine.notify_referral_first_purchase(referrer.id, "Eve")

      assert notif.type == "referral_reward"
      assert notif.body =~ "200 BUX"
      assert notif.metadata[:bonus_bux] == 200
      assert notif.metadata[:milestone] == "first_purchase"
    end
  end

  describe "ReferralEngine.notify_referral_first_game/2" do
    test "creates first game notification" do
      %{user: referrer} = create_user()

      {:ok, notif} =
        ReferralEngine.notify_referral_first_game(referrer.id, "Frank")

      assert notif.type == "referral_reward"
      assert notif.body =~ "ROGUE"
      assert notif.metadata[:milestone] == "first_game"
    end
  end

  # ============ Leaderboard ============

  describe "ReferralEngine.weekly_leaderboard/1" do
    test "returns users sorted by referral count" do
      %{user: u1} = create_user()
      {:ok, _} = UserEvents.upsert_profile(u1.id, %{
        referrals_converted: 5,
        churn_risk_score: 0.2,
        churn_risk_level: "low"
      })

      %{user: u2} = create_user()
      {:ok, _} = UserEvents.upsert_profile(u2.id, %{
        referrals_converted: 10,
        churn_risk_score: 0.2,
        churn_risk_level: "low"
      })

      leaderboard = ReferralEngine.weekly_leaderboard(limit: 10)

      assert length(leaderboard) >= 2

      # First should have more referrals
      first = List.first(leaderboard)
      assert first.rank == 1
      assert first.referrals_converted >= 10
    end

    test "excludes users with 0 referrals" do
      %{user: user} = create_user()
      {:ok, _} = UserEvents.upsert_profile(user.id, %{
        referrals_converted: 0,
        churn_risk_score: 0.2,
        churn_risk_level: "low"
      })

      leaderboard = ReferralEngine.weekly_leaderboard(limit: 50)
      user_ids = Enum.map(leaderboard, & &1.user_id)
      refute user.id in user_ids
    end

    test "calculates BUX earned based on tier" do
      %{user: user} = create_user()
      {:ok, _} = UserEvents.upsert_profile(user.id, %{
        referrals_converted: 8,
        churn_risk_score: 0.2,
        churn_risk_level: "low"
      })

      leaderboard = ReferralEngine.weekly_leaderboard(limit: 50)
      entry = Enum.find(leaderboard, fn e -> e.user_id == user.id end)

      assert entry
      # 8 referrals at tier 2 (750 per referral) = 6000
      assert entry.bux_earned == 8 * 750
    end

    test "respects limit parameter" do
      for _ <- 1..5 do
        %{user: u} = create_user()
        {:ok, _} = UserEvents.upsert_profile(u.id, %{
          referrals_converted: Enum.random(1..20),
          churn_risk_score: 0.2,
          churn_risk_level: "low"
        })
      end

      leaderboard = ReferralEngine.weekly_leaderboard(limit: 3)
      assert length(leaderboard) <= 3
    end
  end

  describe "ReferralEngine.user_leaderboard_position/1" do
    test "returns rank and total for user with referrals" do
      %{user: u1} = create_user()
      {:ok, _} = UserEvents.upsert_profile(u1.id, %{
        referrals_converted: 10,
        churn_risk_score: 0.2,
        churn_risk_level: "low"
      })

      %{user: u2} = create_user()
      {:ok, _} = UserEvents.upsert_profile(u2.id, %{
        referrals_converted: 5,
        churn_risk_score: 0.2,
        churn_risk_level: "low"
      })

      {rank, total} = ReferralEngine.user_leaderboard_position(u2.id)
      assert rank >= 1
      assert total >= 2
    end

    test "returns nil for user without referrals" do
      %{user: user} = create_user()
      {:ok, _} = UserEvents.upsert_profile(user.id, %{
        referrals_converted: 0,
        churn_risk_score: 0.2,
        churn_risk_level: "low"
      })

      assert ReferralEngine.user_leaderboard_position(user.id) == nil
    end
  end

  # ============ Referral Block for Emails ============

  describe "ReferralEngine.referral_block_for_email/2" do
    test "returns contextual block for daily_digest" do
      block = ReferralEngine.referral_block_for_email("daily_digest", nil)
      assert block.heading =~ "knowledge"
      assert block.cta == "Share Your Link"
    end

    test "returns contextual block for reward_summary" do
      block = ReferralEngine.referral_block_for_email("reward_summary", nil)
      assert block.heading =~ "friends"
    end

    test "returns contextual block for bux_milestone" do
      block = ReferralEngine.referral_block_for_email("bux_milestone", nil)
      assert block.heading =~ "Celebrate"
    end

    test "returns contextual block for game_result" do
      block = ReferralEngine.referral_block_for_email("game_result", nil)
      assert block.heading =~ "win"
    end

    test "returns contextual block for order_confirmation" do
      block = ReferralEngine.referral_block_for_email("order_confirmation", nil)
      assert block.heading =~ "purchase"
    end

    test "returns contextual block for cart_abandonment" do
      block = ReferralEngine.referral_block_for_email("cart_abandonment", nil)
      assert block.heading =~ "decide"
    end

    test "returns default block for unknown types" do
      block = ReferralEngine.referral_block_for_email("unknown", nil)
      assert block.heading =~ "Invite"
    end

    test "uses tier-appropriate reward amounts" do
      %{profile: high_profile} = create_user_with_profile(%{referrals_converted: 20})
      %{profile: low_profile} = create_user_with_profile(%{referrals_converted: 2})

      high_block = ReferralEngine.referral_block_for_email("daily_digest", high_profile)
      low_block = ReferralEngine.referral_block_for_email("daily_digest", low_profile)

      assert high_block.message =~ "1000"
      assert low_block.message =~ "500"
    end
  end

  # ============ Referral Prompt Logic ============

  describe "ReferralEngine.should_prompt_referral?/2" do
    test "prompts high-propensity users" do
      %{user: user, profile: profile} =
        create_user_with_profile(%{referral_propensity: 0.8})

      assert ReferralEngine.should_prompt_referral?(user.id, profile) == true
    end

    test "does not prompt low-propensity users" do
      %{user: user, profile: profile} =
        create_user_with_profile(%{referral_propensity: 0.1})

      assert ReferralEngine.should_prompt_referral?(user.id, profile) == false
    end

    test "does not repeat high-propensity prompt in same week" do
      %{user: user, profile: profile} =
        create_user_with_profile(%{referral_propensity: 0.8})

      # Create a recent referral prompt
      Notifications.create_notification(user.id, %{
        type: "referral_prompt",
        category: "social",
        title: "Share Blockster"
      })

      assert ReferralEngine.should_prompt_referral?(user.id, profile) == false
    end
  end

  # ============ ReferralLeaderboardWorker ============

  describe "ReferralLeaderboardWorker" do
    test "performs successfully with referrals" do
      %{user: user} = create_user()
      {:ok, _} = UserEvents.upsert_profile(user.id, %{
        referrals_converted: 5,
        churn_risk_score: 0.2,
        churn_risk_level: "low"
      })

      assert :ok = ReferralLeaderboardWorker.perform(%Oban.Job{args: %{}})
    end

    test "handles empty leaderboard gracefully" do
      assert :ok = ReferralLeaderboardWorker.perform(%Oban.Job{args: %{}})
    end
  end

  # ============ Integration Tests ============

  describe "full referral lifecycle" do
    test "referrer receives all milestone notifications" do
      %{user: referrer} = create_user()

      # Friend signs up
      {:ok, n1} = ReferralEngine.notify_referral_signup(referrer.id, "Alice", 1)
      assert n1.type == "referral_signup"

      # Friend earns first BUX
      {:ok, n2} = ReferralEngine.notify_referral_first_bux(referrer.id, "Alice")
      assert n2.type == "referral_reward"
      assert n2.metadata[:milestone] == "first_bux"

      # Friend makes first purchase
      {:ok, n3} = ReferralEngine.notify_referral_first_purchase(referrer.id, "Alice")
      assert n3.metadata[:milestone] == "first_purchase"
      assert n3.metadata[:bonus_bux] == 200

      # Friend plays first game
      {:ok, n4} = ReferralEngine.notify_referral_first_game(referrer.id, "Alice")
      assert n4.metadata[:milestone] == "first_game"

      # All 4 notifications created
      notifications = Notifications.list_notifications(referrer.id, limit: 10)
      assert length(notifications) == 4
    end
  end

  describe "tier progression" do
    test "rewards escalate as referral count grows" do
      {r1, _, _} = ReferralEngine.calculate_referral_reward(1)
      {r2, _, _} = ReferralEngine.calculate_referral_reward(6)
      {r3, _, _} = ReferralEngine.calculate_referral_reward(16)
      {r4, _, _} = ReferralEngine.calculate_referral_reward(31)
      {r5, _, _} = ReferralEngine.calculate_referral_reward(51)

      assert r1 < r2
      assert r2 < r3
      assert r3 < r4
      assert r4 < r5
    end
  end
end
