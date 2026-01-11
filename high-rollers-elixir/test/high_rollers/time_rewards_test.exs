defmodule HighRollers.TimeRewardsTest do
  @moduledoc """
  Tests for TimeRewards pure calculation functions.
  No Mnesia required - these are pure functions.
  """
  use ExUnit.Case, async: true

  alias HighRollers.TimeRewards

  describe "special_nft?/1" do
    test "returns true for special NFTs (2340-2700)" do
      assert TimeRewards.special_nft?(2340) == true
      assert TimeRewards.special_nft?(2500) == true
      assert TimeRewards.special_nft?(2700) == true
    end

    test "returns false for regular NFTs" do
      assert TimeRewards.special_nft?(1) == false
      assert TimeRewards.special_nft?(2339) == false
      assert TimeRewards.special_nft?(2701) == false
    end
  end

  describe "rate_per_second_wei/1" do
    test "returns correct rate for each hostess" do
      assert TimeRewards.rate_per_second_wei(0) == 2_125_029_000_000_000_000  # Penelope 100x
      assert TimeRewards.rate_per_second_wei(1) == 1_912_007_000_000_000_000  # Mia 90x
      assert TimeRewards.rate_per_second_wei(2) == 1_700_492_000_000_000_000  # Cleo 80x
      assert TimeRewards.rate_per_second_wei(3) == 1_487_470_000_000_000_000  # Sophia 70x
      assert TimeRewards.rate_per_second_wei(4) == 1_274_962_000_000_000_000  # Luna 60x
      assert TimeRewards.rate_per_second_wei(5) == 1_062_454_000_000_000_000  # Aurora 50x
      assert TimeRewards.rate_per_second_wei(6) == 849_946_000_000_000_000    # Scarlett 40x
      assert TimeRewards.rate_per_second_wei(7) == 637_438_000_000_000_000    # Vivienne 30x
    end

    test "returns 0 for invalid hostess index" do
      assert TimeRewards.rate_per_second_wei(8) == 0
      assert TimeRewards.rate_per_second_wei(-1) == 0
    end
  end

  describe "rate_per_second/1" do
    test "returns correct rate in ROGUE (float)" do
      # Penelope 100x: 2.125029 ROGUE/sec
      assert_in_delta TimeRewards.rate_per_second(0), 2.125029, 0.000001
      # Vivienne 30x: 0.637438 ROGUE/sec
      assert_in_delta TimeRewards.rate_per_second(7), 0.637438, 0.000001
    end
  end

  describe "calculate_pending/1" do
    test "returns zero_reward for nil start_time" do
      result = TimeRewards.calculate_pending(%{start_time: nil})
      assert result.pending == 0
      assert result.is_special == false
      assert result.has_started == false
    end

    test "returns zero_reward for zero start_time" do
      result = TimeRewards.calculate_pending(%{start_time: 0})
      assert result.pending == 0
      assert result.is_special == false
    end

    test "calculates pending rewards for active NFT" do
      now = System.system_time(:second)
      one_hour_ago = now - 3600

      result = TimeRewards.calculate_pending(%{
        start_time: one_hour_ago,
        last_claim_time: one_hour_ago,
        hostess_index: 0,  # Penelope
        total_claimed: "0"
      })

      # Penelope earns ~2.125 ROGUE/sec, 1 hour = 3600 seconds
      # Expected: ~7650 wei (2.125029 * 3600 = 7650.1044)
      assert result.pending > 0
      assert result.is_special == true
      assert result.has_started == true
      assert result.time_remaining > 0
    end

    test "caps rewards at 180 day end time" do
      now = System.system_time(:second)
      # Start time was 200 days ago (past the 180 day limit)
      start_time = now - (200 * 24 * 60 * 60)

      result = TimeRewards.calculate_pending(%{
        start_time: start_time,
        last_claim_time: start_time,
        hostess_index: 5,  # Aurora
        total_claimed: "0"
      })

      # Time remaining should be 0 (ended)
      assert result.time_remaining == 0
      assert result.percent_complete >= 100.0
    end

    test "calculates correct 24h earnings" do
      now = System.system_time(:second)
      two_days_ago = now - (2 * 24 * 60 * 60)

      result = TimeRewards.calculate_pending(%{
        start_time: two_days_ago,
        last_claim_time: two_days_ago,
        hostess_index: 7,  # Vivienne 30x
        total_claimed: "0"
      })

      # last_24h should be ~55,026 ROGUE (0.637438 * 86400 = 55,034.6432)
      assert result.last_24h > 0
      # Allow for some time drift between test setup and calculation
      assert_in_delta result.last_24h, 55034.6432, 100.0
    end
  end

  describe "calculate_hostess_time_stats/2" do
    test "calculates 24h and APY for hostess type" do
      # NFT value: 10M ROGUE in wei
      nft_value_wei = 10_000_000_000_000_000_000_000_000

      {time_24h_wei, time_apy} = TimeRewards.calculate_hostess_time_stats(0, nft_value_wei)  # Penelope

      # Penelope: 2.125029e18 rate/sec * 86400 seconds = ~183,602,505.6 ROGUE
      # But the function divides by 1e18, so we get ~183 ROGUE worth of wei value
      assert time_24h_wei > 0

      # APY should be calculated based on 180 day total annualized
      assert time_apy > 0
    end

    test "returns 0 APY when NFT value is 0" do
      {_time_24h_wei, time_apy} = TimeRewards.calculate_hostess_time_stats(0, 0)
      assert time_apy == 0
    end
  end

  describe "calculate_global_24h/1" do
    test "calculates global 24h across multiple NFTs" do
      now = System.system_time(:second)
      one_day_ago = now - 86400

      nfts = [
        %{start_time: one_day_ago, hostess_index: 0},  # Penelope
        %{start_time: one_day_ago, hostess_index: 7},  # Vivienne
      ]

      {global_24h, hostess_list} = TimeRewards.calculate_global_24h(nfts)

      # Should have combined 24h earnings
      assert global_24h > 0

      # Hostess list should have values for index 0 and 7
      assert Enum.at(hostess_list, 0) > 0  # Penelope
      assert Enum.at(hostess_list, 7) > 0  # Vivienne
      assert Enum.at(hostess_list, 1) == 0  # No Mia NFTs
    end

    test "handles NFTs with nil start_time" do
      nfts = [
        %{start_time: nil, hostess_index: 0},
        %{start_time: 0, hostess_index: 1},
      ]

      {global_24h, _hostess_list} = TimeRewards.calculate_global_24h(nfts)

      # Should be 0 since all NFTs have invalid start times
      assert global_24h == 0
    end
  end
end
