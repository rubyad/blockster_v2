defmodule BlocksterV2.RogueMultiplierTest do
  use ExUnit.Case, async: true

  alias BlocksterV2.RogueMultiplier

  describe "calculate_from_balance/1" do
    test "returns 1.0x multiplier for 0 ROGUE" do
      result = RogueMultiplier.calculate_from_balance(0)
      assert result.total_multiplier == 1.0
      assert result.boost == 0.0
      assert result.balance == 0
      assert result.capped_balance == 0
    end

    test "returns 1.0x multiplier for balance below 100k threshold" do
      result = RogueMultiplier.calculate_from_balance(99_999)
      assert result.total_multiplier == 1.0
      assert result.boost == 0.0
    end

    test "returns 1.4x multiplier at exactly 100k threshold" do
      result = RogueMultiplier.calculate_from_balance(100_000)
      assert result.total_multiplier == 1.4
      assert result.boost == 0.4
    end

    test "returns correct multiplier for each tier boundary" do
      # Test lower boundary of each tier
      tier_expectations = [
        {0, 1.0, 0.0},
        {100_000, 1.4, 0.4},
        {200_000, 1.8, 0.8},
        {300_000, 2.2, 1.2},
        {400_000, 2.6, 1.6},
        {500_000, 3.0, 2.0},
        {600_000, 3.4, 2.4},
        {700_000, 3.8, 2.8},
        {800_000, 4.2, 3.2},
        {900_000, 4.6, 3.6},
        {1_000_000, 5.0, 4.0}
      ]

      for {balance, expected_multiplier, expected_boost} <- tier_expectations do
        result = RogueMultiplier.calculate_from_balance(balance)

        assert result.total_multiplier == expected_multiplier,
               "Expected #{expected_multiplier}x for #{balance} ROGUE, got #{result.total_multiplier}x"

        assert result.boost == expected_boost,
               "Expected boost #{expected_boost} for #{balance} ROGUE, got #{result.boost}"
      end
    end

    test "returns correct multiplier for upper boundary of each tier" do
      # Test one below the next tier threshold
      tier_expectations = [
        {99_999, 1.0},
        {199_999, 1.4},
        {299_999, 1.8},
        {399_999, 2.2},
        {499_999, 2.6},
        {599_999, 3.0},
        {699_999, 3.4},
        {799_999, 3.8},
        {899_999, 4.2},
        {999_999, 4.6}
      ]

      for {balance, expected_multiplier} <- tier_expectations do
        result = RogueMultiplier.calculate_from_balance(balance)

        assert result.total_multiplier == expected_multiplier,
               "Expected #{expected_multiplier}x for #{balance} ROGUE, got #{result.total_multiplier}x"
      end
    end

    test "caps at 1M ROGUE - 5M ROGUE gives same multiplier as 1M" do
      result_1m = RogueMultiplier.calculate_from_balance(1_000_000)
      result_5m = RogueMultiplier.calculate_from_balance(5_000_000)

      assert result_1m.total_multiplier == 5.0
      assert result_5m.total_multiplier == 5.0
      assert result_5m.capped_balance == 1_000_000
      assert result_5m.balance == 5_000_000
    end

    test "caps at 1M ROGUE - balance above 1M is capped" do
      result = RogueMultiplier.calculate_from_balance(2_500_000)

      assert result.balance == 2_500_000
      assert result.capped_balance == 1_000_000
      assert result.total_multiplier == 5.0
    end

    test "handles nil balance" do
      result = RogueMultiplier.calculate_from_balance(nil)

      assert result.total_multiplier == 1.0
      assert result.boost == 0.0
      assert result.balance == 0.0
    end

    test "handles negative balance" do
      result = RogueMultiplier.calculate_from_balance(-1000)

      assert result.total_multiplier == 1.0
      assert result.boost == 0.0
    end

    test "handles float balance" do
      result = RogueMultiplier.calculate_from_balance(500_000.5)

      assert result.total_multiplier == 3.0
      assert result.boost == 2.0
    end

    test "returns next_tier info for non-maxed balances" do
      result = RogueMultiplier.calculate_from_balance(150_000)

      assert result.next_tier != nil
      assert result.next_tier.threshold == 200_000
      assert result.next_tier.boost == 0.8
      assert result.next_tier.multiplier == 1.8
      assert result.next_tier.rogue_needed == 50_000
    end

    test "returns nil next_tier for maxed balance" do
      result = RogueMultiplier.calculate_from_balance(1_000_000)

      assert result.next_tier == nil
    end

    test "calculates correct rogue_needed for next tier" do
      result = RogueMultiplier.calculate_from_balance(0)

      assert result.next_tier.threshold == 100_000
      assert result.next_tier.rogue_needed == 100_000
    end
  end

  describe "get_tiers/0" do
    test "returns all tiers with correct structure" do
      tiers = RogueMultiplier.get_tiers()

      assert is_list(tiers)
      assert length(tiers) == 11

      # Check first tier (highest)
      [first | _] = tiers
      assert first.threshold == 1_000_000
      assert first.boost == 4.0
      assert first.multiplier == 5.0

      # Check last tier (lowest)
      last = List.last(tiers)
      assert last.threshold == 0
      assert last.boost == 0.0
      assert last.multiplier == 1.0
    end
  end

  describe "max_multiplier/0 and base_multiplier/0" do
    test "returns correct max multiplier" do
      assert RogueMultiplier.max_multiplier() == 5.0
    end

    test "returns correct base multiplier" do
      assert RogueMultiplier.base_multiplier() == 1.0
    end
  end

  describe "get_multiplier/1" do
    test "returns base multiplier for non-integer user_id" do
      assert RogueMultiplier.get_multiplier(nil) == 1.0
      assert RogueMultiplier.get_multiplier("123") == 1.0
      assert RogueMultiplier.get_multiplier(%{}) == 1.0
    end
  end

  describe "calculate_rogue_multiplier/1" do
    test "returns default result for non-integer user_id" do
      result = RogueMultiplier.calculate_rogue_multiplier(nil)

      assert result.total_multiplier == 1.0
      assert result.boost == 0.0
      assert result.balance == 0.0
      assert result.next_tier.threshold == 100_000
    end

    test "returns default result for string user_id" do
      result = RogueMultiplier.calculate_rogue_multiplier("123")

      assert result.total_multiplier == 1.0
    end
  end
end
