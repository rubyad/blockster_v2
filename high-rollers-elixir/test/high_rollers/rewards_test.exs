defmodule HighRollers.RewardsTest do
  @moduledoc """
  Tests for Rewards Mnesia operations (events, withdrawals, stats).
  """
  use HighRollers.MnesiaCase, async: false

  alias HighRollers.Rewards

  describe "insert_event/1" do
    test "inserts reward event" do
      attrs = %{
        commitment_hash: "0xabc123",
        amount: "1000000000000000000",
        timestamp: 1704067200,
        block_number: 12345,
        tx_hash: "0xdef456"
      }

      assert :ok = Rewards.insert_event(attrs)

      events = Rewards.get_events(10)
      assert length(events) == 1
      assert Enum.at(events, 0).commitment_hash == "0xabc123"
      assert Enum.at(events, 0).amount == "1000000000000000000"
    end

    test "handles duplicate commitment_hash (idempotent)" do
      attrs = %{
        commitment_hash: "0xabc123",
        amount: "1000000000000000000",
        timestamp: 1704067200,
        block_number: 12345,
        tx_hash: "0xdef456"
      }

      assert :ok = Rewards.insert_event(attrs)
      assert :ok = Rewards.insert_event(attrs)  # Same event

      events = Rewards.get_events(10)
      assert length(events) == 1  # Deduplicated
    end
  end

  describe "get_rewards_since/1" do
    test "sums rewards since timestamp" do
      now = System.system_time(:second)
      one_day_ago = now - 86400

      # Event from yesterday (should be included)
      insert_test_reward_event(%{
        timestamp: now - 3600,  # 1 hour ago
        amount: "1000000000000000000"  # 1 ROGUE
      })

      # Event from today (should be included)
      insert_test_reward_event(%{
        timestamp: now - 1800,  # 30 min ago
        amount: "500000000000000000"  # 0.5 ROGUE
      })

      # Old event (should NOT be included)
      insert_test_reward_event(%{
        timestamp: now - 100000,  # ~27 hours ago
        amount: "2000000000000000000"  # 2 ROGUE
      })

      total = Rewards.get_rewards_since(one_day_ago)
      assert total == 1_500_000_000_000_000_000  # 1.5 ROGUE
    end

    test "returns 0 when no events" do
      now = System.system_time(:second)
      assert Rewards.get_rewards_since(now - 86400) == 0
    end
  end

  describe "get_events/2" do
    test "returns events with pagination" do
      now = System.system_time(:second)

      for i <- 1..15 do
        insert_test_reward_event(%{
          timestamp: now - i * 100,
          amount: "#{i}000000000000000000"
        })
      end

      # First page
      events = Rewards.get_events(10, 0)
      assert length(events) == 10

      # Second page
      events = Rewards.get_events(10, 10)
      assert length(events) == 5
    end

    test "returns events sorted by timestamp desc" do
      now = System.system_time(:second)

      insert_test_reward_event(%{timestamp: now - 300})  # Oldest
      insert_test_reward_event(%{timestamp: now - 100})  # Middle
      insert_test_reward_event(%{timestamp: now - 10})   # Newest

      events = Rewards.get_events(10)
      timestamps = Enum.map(events, & &1.timestamp)

      # Should be in descending order
      assert timestamps == Enum.sort(timestamps, :desc)
    end
  end

  describe "record_withdrawal/1" do
    test "records withdrawal event" do
      attrs = %{
        tx_hash: "0xwithdraw123",
        user_address: "0xUSER",
        amount: "5000000000000000000",
        token_ids: [1, 2, 3]
      }

      assert :ok = Rewards.record_withdrawal(attrs)

      withdrawals = Rewards.get_withdrawals_by_user("0xUSER")
      assert length(withdrawals) == 1
      assert Enum.at(withdrawals, 0).amount == "5000000000000000000"
      assert Enum.at(withdrawals, 0).token_ids == [1, 2, 3]
    end

    test "lowercases user address" do
      attrs = %{
        tx_hash: "0xwithdraw123",
        user_address: "0xAbCdEf",
        amount: "1000000000000000000",
        token_ids: [1]
      }

      assert :ok = Rewards.record_withdrawal(attrs)

      # Query with different case
      withdrawals = Rewards.get_withdrawals_by_user("0xABCDEF")
      assert length(withdrawals) == 1
    end
  end

  describe "get_withdrawals_by_user/2" do
    test "returns withdrawals for specific user" do
      Rewards.record_withdrawal(%{
        tx_hash: "0x1",
        user_address: "0xUSER1",
        amount: "1000000000000000000",
        token_ids: [1]
      })

      Rewards.record_withdrawal(%{
        tx_hash: "0x2",
        user_address: "0xUSER2",
        amount: "2000000000000000000",
        token_ids: [2]
      })

      withdrawals = Rewards.get_withdrawals_by_user("0xUSER1")
      assert length(withdrawals) == 1
      assert Enum.at(withdrawals, 0).token_ids == [1]
    end

    test "limits results" do
      for i <- 1..10 do
        Rewards.record_withdrawal(%{
          tx_hash: "0x#{i}",
          user_address: "0xUSER",
          amount: "1000000000000000000",
          token_ids: [i]
        })
      end

      withdrawals = Rewards.get_withdrawals_by_user("0xUSER", 5)
      assert length(withdrawals) == 5
    end
  end

  describe "global stats" do
    test "update_global_stats/1 and get_global_stats/0" do
      attrs = %{
        total_rewards_received: "10000000000000000000000",
        total_rewards_distributed: "9000000000000000000000",
        rewards_last_24h: "500000000000000000000",
        overall_apy_basis_points: 1500,
        total_nfts: 2342,
        total_multiplier_points: 109390
      }

      assert :ok = Rewards.update_global_stats(attrs)

      stats = Rewards.get_global_stats()
      assert stats.total_rewards_received == "10000000000000000000000"
      assert stats.total_nfts == 2342
      assert stats.overall_apy_basis_points == 1500
    end

    test "get_global_stats/0 returns nil when no stats" do
      assert Rewards.get_global_stats() == nil
    end
  end

  describe "hostess stats" do
    test "update_hostess_stats/2 and get_all_hostess_stats/0" do
      attrs = %{
        nft_count: 9,
        total_points: 900,
        share_basis_points: 823,
        last_24h_per_nft: "50000000000000000000",
        apy_basis_points: 1800,
        time_24h_per_nft: "183000000000000000000",
        time_apy_basis_points: 7500,
        special_nft_count: 3
      }

      assert :ok = Rewards.update_hostess_stats(0, attrs)  # Penelope

      all_stats = Rewards.get_all_hostess_stats()
      assert length(all_stats) == 8

      penelope_stats = Enum.find(all_stats, & &1.hostess_index == 0)
      assert penelope_stats.nft_count == 9
      assert penelope_stats.share_basis_points == 823
      assert penelope_stats.special_nft_count == 3
    end

    test "get_all_hostess_stats/0 returns empty data for uninitialized" do
      all_stats = Rewards.get_all_hostess_stats()
      assert length(all_stats) == 8

      # All should have hostess_index but no other data
      for stats <- all_stats do
        assert Map.has_key?(stats, :hostess_index)
        refute Map.has_key?(stats, :nft_count)
      end
    end
  end

  describe "time reward stats" do
    test "update_time_reward_stats/1 and get_time_reward_stats/0" do
      attrs = %{
        pool_deposited: "1000000000000000000000000",
        pool_remaining: "800000000000000000000000",
        pool_claimed: "200000000000000000000000",
        nfts_started: 361
      }

      assert :ok = Rewards.update_time_reward_stats(attrs)

      stats = Rewards.get_time_reward_stats()
      assert stats.pool_deposited == "1000000000000000000000000"
      assert stats.nfts_started == 361
    end

    test "get_time_reward_stats/0 returns nil when no stats" do
      assert Rewards.get_time_reward_stats() == nil
    end
  end
end
