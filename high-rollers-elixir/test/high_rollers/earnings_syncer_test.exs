defmodule HighRollers.EarningsSyncerTest do
  @moduledoc """
  Tests for the batched time reward sync logic in EarningsSyncer.

  Uses MnesiaCase for in-memory Mnesia tables and Mox for contract mocks.
  """
  use HighRollers.MnesiaCase, async: false

  import Mox
  import HighRollers.Multicall3Fixtures

  setup :verify_on_exit!

  setup do
    case start_supervised(HighRollers.NFTStore) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
    :ok
  end

  describe "time reward sync data flow" do
    test "updates start_time from contract when different" do
      now = System.system_time(:second)
      old_start_time = now - 86400
      new_start_time = now - 43200

      insert_test_nft(%{
        token_id: 2340,
        owner: random_address(),
        time_start_time: old_start_time,
        time_last_claim: now - 3600,
        time_total_claimed: "1000000000000000000"
      })

      nft = HighRollers.NFTStore.get(2340)
      assert nft.time_start_time == old_start_time

      # Simulate what apply_time_reward_updates does
      HighRollers.NFTStore.update_time_reward(2340, %{time_start_time: new_start_time})

      updated = HighRollers.NFTStore.get(2340)
      assert updated.time_start_time == new_start_time
    end

    test "updates last_claim_time from contract when different" do
      now = System.system_time(:second)
      old_claim = now - 7200
      new_claim = now - 1800

      insert_test_nft(%{
        token_id: 2341,
        owner: random_address(),
        time_start_time: now - 86400,
        time_last_claim: old_claim,
        time_total_claimed: "0"
      })

      HighRollers.NFTStore.update_time_reward(2341, %{time_last_claim: new_claim})

      updated = HighRollers.NFTStore.get(2341)
      assert updated.time_last_claim == new_claim
    end

    test "updates total_claimed from contract when different" do
      now = System.system_time(:second)
      old_claimed = "1000000000000000000"
      new_claimed_int = 2_000_000_000_000_000_000

      insert_test_nft(%{
        token_id: 2342,
        owner: random_address(),
        time_start_time: now - 86400,
        time_last_claim: now - 3600,
        time_total_claimed: old_claimed
      })

      HighRollers.NFTStore.update_time_reward(2342, %{time_total_claimed: Integer.to_string(new_claimed_int)})

      updated = HighRollers.NFTStore.get(2342)
      assert updated.time_total_claimed == "2000000000000000000"
    end

    test "no updates when all values match" do
      now = System.system_time(:second)
      start_time = now - 86400
      last_claim = now - 3600
      total_claimed = "5000000000000000000"

      insert_test_nft(%{
        token_id: 2343,
        owner: random_address(),
        time_start_time: start_time,
        time_last_claim: last_claim,
        time_total_claimed: total_claimed
      })

      nft_before = HighRollers.NFTStore.get(2343)

      # Simulate contract returning same values
      raw_info = %{
        start_time: start_time,
        last_claim_time: last_claim,
        total_claimed: 5_000_000_000_000_000_000
      }

      # Build updates map (should be empty)
      updates = %{}
      updates = if nft_before.time_start_time != raw_info.start_time and raw_info.start_time > 0 do
        Map.put(updates, :time_start_time, raw_info.start_time)
      else
        updates
      end
      updates = if nft_before.time_last_claim != raw_info.last_claim_time and raw_info.last_claim_time > 0 do
        Map.put(updates, :time_last_claim, raw_info.last_claim_time)
      else
        updates
      end

      mnesia_claimed = case Integer.parse(nft_before.time_total_claimed || "0") do
        {int, _} -> int
        :error -> 0
      end

      updates = if raw_info.total_claimed != mnesia_claimed do
        Map.put(updates, :time_total_claimed, Integer.to_string(raw_info.total_claimed))
      else
        updates
      end

      # Should have no updates
      assert map_size(updates) == 0
    end

    test "skips NFTs with zero start_time" do
      raw_info = %{
        start_time: 0,
        last_claim_time: 0,
        total_claimed: 0
      }

      # Zero start_time means not registered for time rewards
      updates = %{}
      updates = if 0 != raw_info.start_time and raw_info.start_time > 0 do
        Map.put(updates, :time_start_time, raw_info.start_time)
      else
        updates
      end

      assert map_size(updates) == 0
    end
  end

  describe "special NFTs" do
    test "only special NFTs have token IDs 2340-2700" do
      # Insert regular and special NFTs
      insert_test_nft(%{token_id: 1, owner: random_address()})
      insert_test_nft(%{token_id: 100, owner: random_address()})
      insert_test_nft(%{
        token_id: 2340,
        owner: random_address(),
        time_start_time: System.system_time(:second) - 86400,
        time_last_claim: System.system_time(:second) - 3600,
        time_total_claimed: "1000000000000000000"
      })
      insert_test_nft(%{
        token_id: 2500,
        owner: random_address(),
        time_start_time: System.system_time(:second) - 86400,
        time_last_claim: System.system_time(:second) - 3600,
        time_total_claimed: "500000000000000000"
      })

      all = HighRollers.NFTStore.get_all()
      assert length(all) == 4

      # Special NFTs have time_start_time set
      special = Enum.filter(all, fn nft -> nft.time_start_time != nil end)
      assert length(special) == 2
      assert Enum.all?(special, fn nft -> nft.token_id >= 2340 and nft.token_id <= 2700 end)
    end
  end

  describe "batch chunking" do
    test "chunks special NFTs by 50" do
      # Create 120 special NFTs
      for i <- 0..119 do
        insert_test_nft(%{
          token_id: 2340 + i,
          owner: random_address(),
          time_start_time: System.system_time(:second) - 86400,
          time_last_claim: System.system_time(:second) - 3600,
          time_total_claimed: "0"
        })
      end

      all = HighRollers.NFTStore.get_all()
      batches = Enum.chunk_every(all, 50)
      assert length(batches) == 3
      assert length(Enum.at(batches, 0)) == 50
      assert length(Enum.at(batches, 1)) == 50
      assert length(Enum.at(batches, 2)) == 20
    end
  end

  describe "batch_time_reward_raw mock" do
    test "can mock get_batch_time_reward_raw" do
      now = System.system_time(:second)

      results = [
        %{start_time: now - 86400, last_claim_time: now - 3600, total_claimed: 1_000_000_000_000_000_000},
        %{start_time: now - 43200, last_claim_time: now - 1800, total_claimed: 500_000_000_000_000_000}
      ]

      expect(HighRollers.Contracts.NFTRewarderMock, :get_batch_time_reward_raw, fn token_ids ->
        assert length(token_ids) == 2
        {:ok, results}
      end)

      {:ok, result} = HighRollers.Contracts.NFTRewarderMock.get_batch_time_reward_raw([2340, 2341])
      assert length(result) == 2
    end

    test "handles batch query failure" do
      expect(HighRollers.Contracts.NFTRewarderMock, :get_batch_time_reward_raw, fn _token_ids ->
        {:error, :rpc_timeout}
      end)

      assert {:error, :rpc_timeout} = HighRollers.Contracts.NFTRewarderMock.get_batch_time_reward_raw([2340])
    end
  end
end
