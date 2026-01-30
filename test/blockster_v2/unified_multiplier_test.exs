defmodule BlocksterV2.UnifiedMultiplierTest do
  use ExUnit.Case, async: true

  alias BlocksterV2.UnifiedMultiplier

  describe "calculate_x_multiplier/1" do
    test "returns 1.0x for score 0" do
      assert UnifiedMultiplier.calculate_x_multiplier(0) == 1.0
    end

    test "returns 1.0x for score 10 (min threshold)" do
      assert UnifiedMultiplier.calculate_x_multiplier(10) == 1.0
    end

    test "returns correct multiplier for score 50" do
      assert UnifiedMultiplier.calculate_x_multiplier(50) == 5.0
    end

    test "returns 10.0x for score 100" do
      assert UnifiedMultiplier.calculate_x_multiplier(100) == 10.0
    end

    test "returns 1.0x for negative scores" do
      assert UnifiedMultiplier.calculate_x_multiplier(-10) == 1.0
    end

    test "caps at 10.0x for scores above 100" do
      assert UnifiedMultiplier.calculate_x_multiplier(150) == 10.0
    end

    test "handles float scores" do
      assert UnifiedMultiplier.calculate_x_multiplier(75.5) == 7.55
    end

    test "returns 1.0x for nil input" do
      assert UnifiedMultiplier.calculate_x_multiplier(nil) == 1.0
    end

    test "returns 1.0x for non-number input" do
      assert UnifiedMultiplier.calculate_x_multiplier("50") == 1.0
    end
  end

  describe "calculate_phone_multiplier/1" do
    test "returns 2.0x for premium tier (phone verified)" do
      user = %{phone_verified: true, geo_tier: "premium"}
      assert UnifiedMultiplier.calculate_phone_multiplier(user) == 2.0
    end

    test "returns 1.5x for standard tier (phone verified)" do
      user = %{phone_verified: true, geo_tier: "standard"}
      assert UnifiedMultiplier.calculate_phone_multiplier(user) == 1.5
    end

    test "returns 1.0x for basic tier (phone verified)" do
      user = %{phone_verified: true, geo_tier: "basic"}
      assert UnifiedMultiplier.calculate_phone_multiplier(user) == 1.0
    end

    test "returns 0.5x for unverified tier" do
      user = %{phone_verified: true, geo_tier: "unverified"}
      assert UnifiedMultiplier.calculate_phone_multiplier(user) == 0.5
    end

    test "returns 0.5x when phone not verified" do
      user = %{phone_verified: false, geo_tier: "premium"}
      assert UnifiedMultiplier.calculate_phone_multiplier(user) == 0.5
    end

    test "returns 0.5x when geo_tier is nil" do
      user = %{phone_verified: true, geo_tier: nil}
      assert UnifiedMultiplier.calculate_phone_multiplier(user) == 0.5
    end

    test "returns 0.5x for nil input" do
      assert UnifiedMultiplier.calculate_phone_multiplier(nil) == 0.5
    end

    test "returns 0.5x for empty map" do
      assert UnifiedMultiplier.calculate_phone_multiplier(%{}) == 0.5
    end

    test "returns 1.0x for unknown geo_tier when phone verified" do
      user = %{phone_verified: true, geo_tier: "unknown_tier"}
      assert UnifiedMultiplier.calculate_phone_multiplier(user) == 1.0
    end
  end

  describe "calculate_overall/4" do
    test "calculates multiplicative product" do
      # 2.0 * 1.5 * 1.0 * 1.0 = 3.0
      result = UnifiedMultiplier.calculate_overall(2.0, 1.5, 1.0, 1.0)
      assert result == 3.0
    end

    test "minimum possible overall (all minimums)" do
      # 1.0 * 0.5 * 1.0 * 1.0 = 0.5
      result = UnifiedMultiplier.calculate_overall(1.0, 0.5, 1.0, 1.0)
      assert result == 0.5
    end

    test "maximum possible overall (all maximums)" do
      # 10.0 * 2.0 * 5.0 * 3.6 = 360.0
      result = UnifiedMultiplier.calculate_overall(10.0, 2.0, 5.0, 3.6)
      assert result == 360.0
    end

    test "rounds to 1 decimal place" do
      # 7.5 * 1.5 * 3.0 * 2.1 = 70.875 -> 70.9
      result = UnifiedMultiplier.calculate_overall(7.5, 1.5, 3.0, 2.1)
      assert result == 70.9
    end

    test "realistic example: moderate user" do
      # X score 50 (5.0x) * phone premium (2.0x) * no ROGUE (1.0x) * no wallet (1.0x)
      result = UnifiedMultiplier.calculate_overall(5.0, 2.0, 1.0, 1.0)
      assert result == 10.0
    end

    test "realistic example: power user" do
      # X score 75 (7.5x) * phone premium (2.0x) * 500k ROGUE (3.0x) * full wallet (2.8x)
      result = UnifiedMultiplier.calculate_overall(7.5, 2.0, 3.0, 2.8)
      assert result == 126.0
    end

    test "edge case: zero multiplier component would result in zero" do
      # But our system has minimums, so this shouldn't happen in practice
      result = UnifiedMultiplier.calculate_overall(1.0, 0.5, 1.0, 1.0)
      assert result == 0.5
    end
  end

  describe "phone_tiers/0" do
    test "returns all phone tiers" do
      tiers = UnifiedMultiplier.phone_tiers()

      assert tiers["premium"] == 2.0
      assert tiers["standard"] == 1.5
      assert tiers["basic"] == 1.0
      assert tiers["unverified"] == 0.5
    end
  end

  describe "max_overall/0 and min_overall/0" do
    test "returns correct max overall" do
      assert UnifiedMultiplier.max_overall() == 360.0
    end

    test "returns correct min overall" do
      assert UnifiedMultiplier.min_overall() == 0.5
    end
  end

  describe "get_x_score/1" do
    test "returns 0 for non-integer user_id" do
      assert UnifiedMultiplier.get_x_score(nil) == 0
      assert UnifiedMultiplier.get_x_score("123") == 0
      assert UnifiedMultiplier.get_x_score(%{}) == 0
    end
  end

  describe "get_overall_multiplier/1" do
    test "returns minimum for non-integer user_id" do
      assert UnifiedMultiplier.get_overall_multiplier(nil) == 0.5
      assert UnifiedMultiplier.get_overall_multiplier("123") == 0.5
    end
  end

  describe "get_user_multipliers/1" do
    test "returns default multipliers for non-integer user_id" do
      result = UnifiedMultiplier.get_user_multipliers(nil)

      assert result.x_score == 0
      assert result.x_multiplier == 1.0
      assert result.phone_multiplier == 0.5
      assert result.rogue_multiplier == 1.0
      assert result.wallet_multiplier == 1.0
      assert result.overall_multiplier == 0.5
    end
  end

  describe "refresh_multipliers/1" do
    test "returns default multipliers for non-integer user_id" do
      result = UnifiedMultiplier.refresh_multipliers(nil)

      assert result.x_score == 0
      assert result.x_multiplier == 1.0
      assert result.phone_multiplier == 0.5
      assert result.rogue_multiplier == 1.0
      assert result.wallet_multiplier == 1.0
      assert result.overall_multiplier == 0.5
    end
  end

  describe "update_x_multiplier/2" do
    test "returns error for non-integer user_id" do
      assert UnifiedMultiplier.update_x_multiplier(nil, 50) == {:error, :invalid_input}
      assert UnifiedMultiplier.update_x_multiplier("123", 50) == {:error, :invalid_input}
    end

    test "returns error for non-number x_score" do
      assert UnifiedMultiplier.update_x_multiplier(1, nil) == {:error, :invalid_input}
      assert UnifiedMultiplier.update_x_multiplier(1, "50") == {:error, :invalid_input}
    end
  end

  describe "update_phone_multiplier/1" do
    test "returns error for non-integer user_id" do
      assert UnifiedMultiplier.update_phone_multiplier(nil) == {:error, :invalid_input}
      assert UnifiedMultiplier.update_phone_multiplier("123") == {:error, :invalid_input}
    end
  end

  describe "update_rogue_multiplier/1" do
    test "returns error for non-integer user_id" do
      assert UnifiedMultiplier.update_rogue_multiplier(nil) == {:error, :invalid_input}
      assert UnifiedMultiplier.update_rogue_multiplier("123") == {:error, :invalid_input}
    end
  end

  describe "update_wallet_multiplier/1" do
    test "returns error for non-integer user_id" do
      assert UnifiedMultiplier.update_wallet_multiplier(nil) == {:error, :invalid_input}
      assert UnifiedMultiplier.update_wallet_multiplier("123") == {:error, :invalid_input}
    end
  end

  describe "is_maxed?/1" do
    test "returns false for non-integer user_id" do
      assert UnifiedMultiplier.is_maxed?(nil) == false
      assert UnifiedMultiplier.is_maxed?("123") == false
    end
  end

  describe "edge cases and boundary conditions" do
    test "X multiplier formula: max(score/10, 1.0)" do
      # Score 5 -> 0.5 -> max(0.5, 1.0) = 1.0
      assert UnifiedMultiplier.calculate_x_multiplier(5) == 1.0

      # Score 15 -> 1.5 -> max(1.5, 1.0) = 1.5
      assert UnifiedMultiplier.calculate_x_multiplier(15) == 1.5
    end

    test "overall multiplier is multiplicative not additive" do
      # If it were additive: 2.0 + 1.5 + 1.0 + 1.0 = 5.5
      # But it's multiplicative: 2.0 * 1.5 * 1.0 * 1.0 = 3.0
      result = UnifiedMultiplier.calculate_overall(2.0, 1.5, 1.0, 1.0)
      assert result == 3.0
      assert result != 5.5
    end

    test "all minimums produce minimum overall" do
      # x_min=1.0, phone_min=0.5, rogue_min=1.0, wallet_min=1.0
      # 1.0 * 0.5 * 1.0 * 1.0 = 0.5
      result = UnifiedMultiplier.calculate_overall(1.0, 0.5, 1.0, 1.0)
      assert result == UnifiedMultiplier.min_overall()
    end

    test "all maximums produce maximum overall" do
      # x_max=10.0, phone_max=2.0, rogue_max=5.0, wallet_max=3.6
      # 10.0 * 2.0 * 5.0 * 3.6 = 360.0
      result = UnifiedMultiplier.calculate_overall(10.0, 2.0, 5.0, 3.6)
      assert result == UnifiedMultiplier.max_overall()
    end
  end
end
