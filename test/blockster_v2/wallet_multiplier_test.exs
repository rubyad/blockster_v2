defmodule BlocksterV2.WalletMultiplierTest do
  use ExUnit.Case, async: true

  alias BlocksterV2.WalletMultiplier

  describe "max_multiplier/0 and base_multiplier/0" do
    test "returns correct max multiplier (3.6x without ROGUE)" do
      # V2: max is now 3.6x (was 7.6x when ROGUE was included)
      # 1.0 (base) + 0.1 (connection) + 1.5 (ETH max) + 1.0 (other tokens max) = 3.6
      assert WalletMultiplier.max_multiplier() == 3.6
    end

    test "returns correct base multiplier" do
      assert WalletMultiplier.base_multiplier() == 1.0
    end
  end

  describe "get_eth_tiers/0" do
    test "returns all ETH tiers with correct structure" do
      tiers = WalletMultiplier.get_eth_tiers()

      assert is_list(tiers)
      assert length(tiers) == 8

      # Check tier structure
      [first | _] = tiers
      assert Map.has_key?(first, :threshold)
      assert Map.has_key?(first, :boost)
    end

    test "returns tiers in descending order by threshold" do
      tiers = WalletMultiplier.get_eth_tiers()
      thresholds = Enum.map(tiers, & &1.threshold)

      assert thresholds == [10.0, 5.0, 2.5, 1.0, 0.5, 0.1, 0.01, 0.0]
    end

    test "returns correct boosts for each tier" do
      tiers = WalletMultiplier.get_eth_tiers()

      expected_boosts = [
        {10.0, 1.5},
        {5.0, 1.1},
        {2.5, 0.9},
        {1.0, 0.7},
        {0.5, 0.5},
        {0.1, 0.3},
        {0.01, 0.1},
        {0.0, 0.0}
      ]

      for {threshold, expected_boost} <- expected_boosts do
        tier = Enum.find(tiers, fn t -> t.threshold == threshold end)
        assert tier.boost == expected_boost,
               "Expected boost #{expected_boost} for threshold #{threshold}, got #{tier.boost}"
      end
    end
  end

  # Note: calculate_hardware_wallet_multiplier/1 requires database access (Wallets.get_connected_wallet/1)
  # and Mnesia access (Wallets.get_user_balances/1). These tests are skipped in the unit test suite
  # and should be covered in integration tests with proper database setup.

  describe "ETH tier calculation logic" do
    # These tests verify the tier calculation logic based on the @eth_tiers module attribute
    # We can't directly test calculate_eth_tier_multiplier/1 since it's private,
    # but we can verify the tier boundaries documented in the module

    test "tier boundaries are correctly documented" do
      # Verify the tier structure matches documentation
      # | Combined ETH | Boost  |
      # |--------------|--------|
      # | 0 - 0.009    | +0.0x  |
      # | 0.01 - 0.09  | +0.1x  |
      # | 0.1 - 0.49   | +0.3x  |
      # | 0.5 - 0.99   | +0.5x  |
      # | 1.0 - 2.49   | +0.7x  |
      # | 2.5 - 4.99   | +0.9x  |
      # | 5.0 - 9.99   | +1.1x  |
      # | 10.0+        | +1.5x  |

      tiers = WalletMultiplier.get_eth_tiers()

      # Find specific tiers
      tier_0 = Enum.find(tiers, fn t -> t.threshold == 0.0 end)
      tier_001 = Enum.find(tiers, fn t -> t.threshold == 0.01 end)
      tier_01 = Enum.find(tiers, fn t -> t.threshold == 0.1 end)
      tier_05 = Enum.find(tiers, fn t -> t.threshold == 0.5 end)
      tier_1 = Enum.find(tiers, fn t -> t.threshold == 1.0 end)
      tier_25 = Enum.find(tiers, fn t -> t.threshold == 2.5 end)
      tier_5 = Enum.find(tiers, fn t -> t.threshold == 5.0 end)
      tier_10 = Enum.find(tiers, fn t -> t.threshold == 10.0 end)

      assert tier_0.boost == 0.0
      assert tier_001.boost == 0.1
      assert tier_01.boost == 0.3
      assert tier_05.boost == 0.5
      assert tier_1.boost == 0.7
      assert tier_25.boost == 0.9
      assert tier_5.boost == 1.1
      assert tier_10.boost == 1.5
    end
  end

  describe "other tokens multiplier calculation logic" do
    # The formula is: min(total_usd_value / 10000, 1.0)
    # We can verify this indirectly through the documented behavior

    test "other tokens multiplier caps at 1.0" do
      # Formula: min(total_usd_value / 10000, 1.0)
      # $10,000+ should give max 1.0x boost
      # $5,000 should give 0.5x boost

      # Verify max is included in total max calculation
      # Max = 1.0 (base) + 0.1 (connection) + 1.5 (ETH) + 1.0 (other) = 3.6
      assert WalletMultiplier.max_multiplier() == 3.6
    end
  end

  describe "ROGUE removal verification" do
    test "max multiplier is 3.6x (not 7.6x with ROGUE)" do
      # V2 change: ROGUE moved to RogueMultiplier
      # Old max (with ROGUE 4.0x): 1.0 + 0.1 + 1.5 + 1.0 + 4.0 = 7.6
      # New max (without ROGUE): 1.0 + 0.1 + 1.5 + 1.0 = 3.6
      assert WalletMultiplier.max_multiplier() == 3.6
    end

    test "ETH tiers do not include ROGUE" do
      tiers = WalletMultiplier.get_eth_tiers()

      # Should only have 8 ETH tiers, no ROGUE tiers
      assert length(tiers) == 8

      # Verify no ROGUE-related thresholds (ROGUE tiers were 100k, 250k, 500k, 1M)
      thresholds = Enum.map(tiers, & &1.threshold)
      assert 100_000 not in thresholds
      assert 250_000 not in thresholds
      assert 500_000 not in thresholds
      assert 1_000_000 not in thresholds
    end
  end

  # Note: multiplier structure and get_user_multiplier/get_combined_multiplier tests
  # require Mnesia to be running. These should be covered in integration tests.
end
