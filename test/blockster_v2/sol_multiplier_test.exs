defmodule BlocksterV2.SolMultiplierTest do
  use ExUnit.Case, async: true

  alias BlocksterV2.SolMultiplier

  describe "calculate_from_balance/1" do
    test "returns 0.0x multiplier for 0 SOL (cannot earn)" do
      result = SolMultiplier.calculate_from_balance(0.0)
      assert result.multiplier == 0.0
      assert result.balance == 0.0
    end

    test "returns 0.0x for balance below 0.01 SOL threshold" do
      result = SolMultiplier.calculate_from_balance(0.009)
      assert result.multiplier == 0.0
    end

    test "returns 1.0x at exactly 0.01 SOL threshold" do
      result = SolMultiplier.calculate_from_balance(0.01)
      assert result.multiplier == 1.0
    end

    test "returns correct multiplier for each tier boundary" do
      tier_expectations = [
        {0.0, 0.0},
        {0.009, 0.0},
        {0.01, 1.0},
        {0.05, 1.5},
        {0.1, 2.0},
        {0.25, 2.5},
        {0.5, 3.0},
        {1.0, 3.5},
        {2.5, 4.0},
        {5.0, 4.5},
        {10.0, 5.0}
      ]

      for {balance, expected_multiplier} <- tier_expectations do
        result = SolMultiplier.calculate_from_balance(balance)

        assert result.multiplier == expected_multiplier,
               "Expected #{expected_multiplier}x for #{balance} SOL, got #{result.multiplier}x"
      end
    end

    test "returns correct multiplier for mid-tier values" do
      mid_tier_expectations = [
        {0.03, 1.0},     # Mid of 0.01-0.04 tier
        {0.07, 1.5},     # Mid of 0.05-0.09 tier
        {0.15, 2.0},     # Mid of 0.1-0.24 tier
        {0.35, 2.5},     # Mid of 0.25-0.49 tier
        {0.75, 3.0},     # Mid of 0.5-0.99 tier
        {1.5, 3.5},      # Mid of 1.0-2.49 tier
        {3.5, 4.0},      # Mid of 2.5-4.99 tier
        {7.5, 4.5},      # Mid of 5.0-9.99 tier
        {50.0, 5.0}      # Well above max tier
      ]

      for {balance, expected_multiplier} <- mid_tier_expectations do
        result = SolMultiplier.calculate_from_balance(balance)

        assert result.multiplier == expected_multiplier,
               "Expected #{expected_multiplier}x for #{balance} SOL, got #{result.multiplier}x"
      end
    end

    test "returns correct multiplier for upper boundary of each tier" do
      upper_boundary_expectations = [
        {0.0099, 0.0},   # Just below 0.01
        {0.049, 1.0},    # Just below 0.05
        {0.099, 1.5},    # Just below 0.1
        {0.249, 2.0},    # Just below 0.25
        {0.499, 2.5},    # Just below 0.5
        {0.999, 3.0},    # Just below 1.0
        {2.499, 3.5},    # Just below 2.5
        {4.999, 4.0},    # Just below 5.0
        {9.999, 4.5}     # Just below 10.0
      ]

      for {balance, expected_multiplier} <- upper_boundary_expectations do
        result = SolMultiplier.calculate_from_balance(balance)

        assert result.multiplier == expected_multiplier,
               "Expected #{expected_multiplier}x for #{balance} SOL, got #{result.multiplier}x"
      end
    end

    test "large SOL balance gives max 5.0x" do
      result = SolMultiplier.calculate_from_balance(100.0)
      assert result.multiplier == 5.0
      assert result.balance == 100.0
    end

    test "handles nil balance" do
      result = SolMultiplier.calculate_from_balance(nil)
      assert result.multiplier == 0.0
      assert result.balance == 0.0
    end

    test "handles negative balance" do
      result = SolMultiplier.calculate_from_balance(-1.0)
      assert result.multiplier == 0.0
    end

    test "returns next_tier info for non-maxed balances" do
      result = SolMultiplier.calculate_from_balance(0.03)

      assert result.next_tier != nil
      assert result.next_tier.threshold == 0.05
      assert result.next_tier.multiplier == 1.5
      assert_in_delta result.next_tier.sol_needed, 0.02, 0.001
    end

    test "returns next_tier for zero balance" do
      result = SolMultiplier.calculate_from_balance(0.0)

      assert result.next_tier != nil
      assert result.next_tier.threshold == 0.01
      assert result.next_tier.multiplier == 1.0
    end

    test "returns nil next_tier for maxed balance (10+ SOL)" do
      result = SolMultiplier.calculate_from_balance(10.0)
      assert result.next_tier == nil
    end

    test "balance is preserved in result" do
      result = SolMultiplier.calculate_from_balance(3.14)
      assert result.balance == 3.14
    end
  end

  describe "get_tiers/0" do
    test "returns all tiers with correct structure" do
      tiers = SolMultiplier.get_tiers()

      assert is_list(tiers)
      assert length(tiers) == 10

      # Check first tier (highest)
      [first | _] = tiers
      assert first.threshold == 10.0
      assert first.multiplier == 5.0

      # Check last tier (lowest)
      last = List.last(tiers)
      assert last.threshold == 0.0
      assert last.multiplier == 0.0
    end
  end

  describe "max_multiplier/0 and min_multiplier/0" do
    test "returns correct max multiplier" do
      assert SolMultiplier.max_multiplier() == 5.0
    end

    test "returns correct min multiplier" do
      assert SolMultiplier.min_multiplier() == 0.0
    end
  end

  describe "get_multiplier/1" do
    test "returns min multiplier for non-integer user_id" do
      assert SolMultiplier.get_multiplier(nil) == 0.0
      assert SolMultiplier.get_multiplier("123") == 0.0
      assert SolMultiplier.get_multiplier(%{}) == 0.0
    end
  end

  describe "calculate/1" do
    test "returns default result for non-integer user_id" do
      result = SolMultiplier.calculate(nil)

      assert result.multiplier == 0.0
      assert result.balance == 0.0
      assert result.next_tier.threshold == 0.01
    end

    test "returns default result for string user_id" do
      result = SolMultiplier.calculate("123")
      assert result.multiplier == 0.0
    end
  end
end
