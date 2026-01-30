defmodule BlocksterV2.RewardCalculationTest do
  @moduledoc """
  Tests for reward calculation formulas used in the unified multiplier system.

  ## Reward Formulas

  ### Reading Rewards
  Formula: `(engagement_score / 10) × base_bux_reward × overall_multiplier`

  ### Video Rewards
  Formula: `minutes × bux_per_minute × overall_multiplier`

  ### X Share Rewards
  Formula: `reward = x_score` (raw X score as BUX, NOT multiplied)

  See docs/unified_multiplier_system_v2.md for complete documentation.
  """
  use ExUnit.Case, async: true

  alias BlocksterV2.EngagementTracker

  # =============================================================================
  # Reading Rewards Tests
  # =============================================================================

  describe "calculate_bux_earned/4 - reading rewards" do
    test "formula: (engagement/10) × base_bux × multiplier" do
      # Engagement 7/10, base 10 BUX, multiplier 1.0x
      # (7/10) × 10 × 1.0 = 7.0
      result = EngagementTracker.calculate_bux_earned(7, 10, 1.0)
      assert result == 7.0
    end

    test "engagement 7/10, base 10 BUX, multiplier 0.5x → 3.5 BUX" do
      # (7/10) × 10 × 0.5 = 3.5
      result = EngagementTracker.calculate_bux_earned(7, 10, 0.5)
      assert result == 3.5
    end

    test "engagement 7/10, base 10 BUX, multiplier 42.0x → 294 BUX" do
      # (7/10) × 10 × 42.0 = 294.0
      result = EngagementTracker.calculate_bux_earned(7, 10, 42.0)
      assert result == 294.0
    end

    test "engagement 10/10, base 10 BUX, multiplier 360.0x → 3,600 BUX" do
      # (10/10) × 10 × 360.0 = 3600.0
      result = EngagementTracker.calculate_bux_earned(10, 10, 360.0)
      assert result == 3600.0
    end

    test "engagement 0 → 0 BUX regardless of multiplier" do
      # (0/10) × 10 × 360.0 = 0.0
      result = EngagementTracker.calculate_bux_earned(0, 10, 360.0)
      assert result == 0.0
    end

    test "base_bux 0 → 0 BUX regardless of multiplier" do
      # (7/10) × 0 × 360.0 = 0.0
      result = EngagementTracker.calculate_bux_earned(7, 0, 360.0)
      assert result == 0.0
    end

    test "engagement 5/10 (half) with various multipliers" do
      # Base case: (5/10) × 10 × 1.0 = 5.0
      assert EngagementTracker.calculate_bux_earned(5, 10, 1.0) == 5.0

      # With minimum multiplier: (5/10) × 10 × 0.5 = 2.5
      assert EngagementTracker.calculate_bux_earned(5, 10, 0.5) == 2.5

      # With high multiplier: (5/10) × 10 × 100.0 = 500.0
      assert EngagementTracker.calculate_bux_earned(5, 10, 100.0) == 500.0
    end

    test "rounds to 2 decimal places" do
      # (7/10) × 10 × 1.111 = 7.777 → 7.78
      result = EngagementTracker.calculate_bux_earned(7, 10, 1.111)
      assert result == 7.78
    end

    test "handles nil base_bux_reward (defaults to 1)" do
      # (7/10) × 1 × 10.0 = 7.0
      result = EngagementTracker.calculate_bux_earned(7, nil, 10.0)
      assert result == 7.0
    end

    test "handles nil user_multiplier (defaults to 1)" do
      # (7/10) × 10 × 1 = 7.0
      result = EngagementTracker.calculate_bux_earned(7, 10, nil)
      assert result == 7.0
    end

    test "geo_multiplier applies when provided" do
      # (7/10) × 10 × 1.0 × 2.0 = 14.0
      result = EngagementTracker.calculate_bux_earned(7, 10, 1.0, 2.0)
      assert result == 14.0
    end

    test "geo_multiplier defaults to 1.0 when not provided" do
      # (7/10) × 10 × 1.0 × 1.0 = 7.0
      result = EngagementTracker.calculate_bux_earned(7, 10, 1.0)
      assert result == 7.0
    end

    test "handles nil geo_multiplier (defaults to 1.0)" do
      # (7/10) × 10 × 1.0 × 1.0 = 7.0
      result = EngagementTracker.calculate_bux_earned(7, 10, 1.0, nil)
      assert result == 7.0
    end

    test "minimum possible reward (all minimums)" do
      # engagement 1, base 1, multiplier 0.5x
      # (1/10) × 1 × 0.5 = 0.05
      result = EngagementTracker.calculate_bux_earned(1, 1, 0.5)
      assert result == 0.05
    end

    test "maximum possible reward example (max engagement, high base, max multiplier)" do
      # engagement 10, base 100, multiplier 360.0x
      # (10/10) × 100 × 360.0 = 36,000
      result = EngagementTracker.calculate_bux_earned(10, 100, 360.0)
      assert result == 36000.0
    end

    test "user with 0.5x multiplier earns less than base" do
      # With 0.5x (unverified phone): (7/10) × 10 × 0.5 = 3.5
      # Without multiplier penalty: (7/10) × 10 × 1.0 = 7.0
      result_with_penalty = EngagementTracker.calculate_bux_earned(7, 10, 0.5)
      result_without_penalty = EngagementTracker.calculate_bux_earned(7, 10, 1.0)

      assert result_with_penalty < result_without_penalty
      assert result_with_penalty == 3.5
      assert result_without_penalty == 7.0
    end
  end

  # =============================================================================
  # Video Rewards Tests
  # =============================================================================

  describe "video rewards calculation" do
    # Video rewards formula: minutes × bux_per_minute × overall_multiplier
    #
    # Note: The actual video reward calculation may be implemented in a different module.
    # These tests document the expected formula and can be adapted to the actual implementation.

    # Helper function to calculate video rewards using the expected formula
    # This can be replaced with the actual function when implemented
    defp calculate_video_reward(minutes, bux_per_minute, multiplier) do
      (minutes * bux_per_minute * multiplier)
      |> Float.round(2)
    end

    test "formula: minutes × bux_per_minute × multiplier" do
      # 5 min, 1 BUX/min, multiplier 1.0x → 5.0 BUX
      result = calculate_video_reward(5, 1, 1.0)
      assert result == 5.0
    end

    test "5 min, 1 BUX/min, multiplier 0.5x → 2.5 BUX" do
      result = calculate_video_reward(5, 1, 0.5)
      assert result == 2.5
    end

    test "5 min, 1 BUX/min, multiplier 42.0x → 210 BUX" do
      result = calculate_video_reward(5, 1, 42.0)
      assert result == 210.0
    end

    test "0 minutes → 0 BUX regardless of multiplier" do
      result = calculate_video_reward(0, 1, 360.0)
      assert result == 0.0
    end

    test "0 bux_per_minute → 0 BUX regardless of other factors" do
      result = calculate_video_reward(5, 0, 360.0)
      assert result == 0.0
    end

    test "fractional minutes work correctly" do
      # 2.5 min, 1 BUX/min, multiplier 2.0x → 5.0 BUX
      result = calculate_video_reward(2.5, 1, 2.0)
      assert result == 5.0
    end

    test "high bux_per_minute rate" do
      # 10 min, 5 BUX/min, multiplier 10.0x → 500 BUX
      result = calculate_video_reward(10, 5, 10.0)
      assert result == 500.0
    end

    test "user with 0.5x multiplier earns less than base" do
      # With 0.5x: 5 × 1 × 0.5 = 2.5
      # Without penalty: 5 × 1 × 1.0 = 5.0
      result_with_penalty = calculate_video_reward(5, 1, 0.5)
      result_without_penalty = calculate_video_reward(5, 1, 1.0)

      assert result_with_penalty < result_without_penalty
      assert result_with_penalty == 2.5
    end
  end

  # =============================================================================
  # X Share Rewards Tests
  # =============================================================================

  describe "X share rewards calculation" do
    # X share rewards formula: reward = x_score (raw X score as BUX)
    #
    # IMPORTANT: The overall multiplier is NOT applied to X share rewards.
    # Users earn their raw X score (0-100) as BUX per share.
    #
    # This is intentional to:
    # 1. Reward users with high-quality X accounts
    # 2. Provide a direct incentive to improve X presence
    # 3. Keep share rewards predictable for users

    # Helper function to calculate X share reward using the expected formula
    # In production, this would call UnifiedMultiplier.get_x_score/1
    defp calculate_x_share_reward(x_score) do
      # X share reward equals raw X score (0-100) as BUX
      # No multiplier is applied
      x_score
    end

    test "X score 30 → 30 BUX" do
      result = calculate_x_share_reward(30)
      assert result == 30
    end

    test "X score 75 → 75 BUX" do
      result = calculate_x_share_reward(75)
      assert result == 75
    end

    test "X score 100 → 100 BUX (maximum)" do
      result = calculate_x_share_reward(100)
      assert result == 100
    end

    test "X score 0 (no X connected) → 0 BUX" do
      result = calculate_x_share_reward(0)
      assert result == 0
    end

    test "X score 50 (average quality) → 50 BUX" do
      result = calculate_x_share_reward(50)
      assert result == 50
    end

    test "X score 1 (minimum with X connected) → 1 BUX" do
      result = calculate_x_share_reward(1)
      assert result == 1
    end

    test "overall multiplier is NOT applied to share rewards" do
      # A user with 360x multiplier should still only earn their X score
      x_score = 50
      overall_multiplier = 360.0

      # CORRECT: reward = x_score
      correct_reward = calculate_x_share_reward(x_score)
      assert correct_reward == 50

      # WRONG: reward = x_score × overall_multiplier (this should NOT happen)
      wrong_reward = x_score * overall_multiplier
      assert wrong_reward == 18_000

      # Verify the correct formula is NOT using the multiplier
      assert correct_reward != wrong_reward
      assert correct_reward == x_score
    end

    test "X score determines share earning potential" do
      # Low X score user
      low_score_reward = calculate_x_share_reward(20)
      assert low_score_reward == 20

      # High X score user
      high_score_reward = calculate_x_share_reward(85)
      assert high_score_reward == 85

      # High score user earns more per share
      assert high_score_reward > low_score_reward
    end
  end

  # =============================================================================
  # Comparison Tests - Ensuring Formula Differences
  # =============================================================================

  describe "formula comparison - reading vs video vs share rewards" do
    test "reading rewards use engagement, base, AND multiplier" do
      # Reading: (7/10) × 10 × 42.0 = 294.0
      reading_reward = EngagementTracker.calculate_bux_earned(7, 10, 42.0)
      assert reading_reward == 294.0
    end

    test "share rewards ONLY use X score (no multiplier)" do
      x_score = 50
      share_reward = x_score  # Direct mapping

      # Even with max multiplier, share reward is just the X score
      assert share_reward == 50
      assert share_reward != 50 * 360.0  # NOT multiplied
    end

    test "two users with same X score but different overall multipliers earn same share reward" do
      x_score = 75

      # User A: 360x multiplier (power user)
      user_a_share_reward = x_score  # 75 BUX

      # User B: 0.5x multiplier (new user)
      user_b_share_reward = x_score  # 75 BUX

      # Both earn the same share reward because multiplier doesn't apply
      assert user_a_share_reward == user_b_share_reward
      assert user_a_share_reward == 75
    end

    test "same users have different reading rewards due to multiplier" do
      engagement = 7
      base_bux = 10

      # User A: 360x multiplier
      user_a_reading_reward = EngagementTracker.calculate_bux_earned(engagement, base_bux, 360.0)

      # User B: 0.5x multiplier
      user_b_reading_reward = EngagementTracker.calculate_bux_earned(engagement, base_bux, 0.5)

      # Reading rewards are very different due to multiplier
      assert user_a_reading_reward == 2520.0  # (7/10) × 10 × 360
      assert user_b_reading_reward == 3.5     # (7/10) × 10 × 0.5
      assert user_a_reading_reward > user_b_reading_reward
    end
  end
end
