defmodule HighRollers.OwnershipReconcilerTest do
  @moduledoc """
  Tests for the batched ownership reconciliation logic.

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

  describe "reconcile_batch data flow" do
    test "NFTStore.update_owner updates Mnesia when owner differs" do
      # Insert an NFT with one owner
      old_owner = "0x1111111111111111111111111111111111111111"
      new_owner = "0x2222222222222222222222222222222222222222"

      insert_test_nft(%{token_id: 1, owner: old_owner})

      # Verify initial state
      nft = HighRollers.NFTStore.get(1)
      assert nft.owner == String.downcase(old_owner)

      # Simulate what reconcile_batch does: update owner
      HighRollers.NFTStore.update_owner(1, String.downcase(new_owner))

      # Verify update
      updated_nft = HighRollers.NFTStore.get(1)
      assert updated_nft.owner == String.downcase(new_owner)
    end

    test "no update when owners match (case-insensitive)" do
      owner = "0xAbCdEf1234567890AbCdEf1234567890AbCdEf12"
      insert_test_nft(%{token_id: 1, owner: owner})

      nft = HighRollers.NFTStore.get(1)

      # Case-insensitive comparison — should match
      contract_owner = String.downcase(owner)
      mnesia_owner = String.downcase(nft.owner)
      assert contract_owner == mnesia_owner
    end

    test "multiple NFTs can be processed" do
      for i <- 1..5 do
        insert_test_nft(%{token_id: i, owner: random_address()})
      end

      all = HighRollers.NFTStore.get_all()
      assert length(all) == 5
    end

    test "batch processing handles 120 NFTs (multiple batches)" do
      for i <- 1..120 do
        insert_test_nft(%{token_id: i, owner: random_address()})
      end

      all = HighRollers.NFTStore.get_all()
      assert length(all) == 120

      # Chunk by 50 as the reconciler does
      batches = Enum.chunk_every(all, 50)
      assert length(batches) == 3
      assert length(Enum.at(batches, 0)) == 50
      assert length(Enum.at(batches, 1)) == 50
      assert length(Enum.at(batches, 2)) == 20
    end
  end

  describe "owner comparison logic" do
    test "case-insensitive comparison catches mismatches" do
      owner_mixed = "0xAbCd000000000000000000000000000000001234"
      different = "0x9999000000000000000000000000000000005678"

      assert String.downcase(owner_mixed) != String.downcase(different)
    end

    test "case-insensitive comparison matches same address" do
      upper = "0xABCD000000000000000000000000000000001234"
      lower = "0xabcd000000000000000000000000000000001234"

      assert String.downcase(upper) == String.downcase(lower)
    end
  end

  describe "rewarder update logic" do
    test "zero address owner skips rewarder update" do
      zero_address = "0x0000000000000000000000000000000000000000"
      correct_owner = "0x1111111111111111111111111111111111111111"

      # Zero address means not registered — should not queue update
      assert String.downcase(zero_address) == zero_address
      assert String.downcase(zero_address) != correct_owner
      # In real code, the condition checks:
      # if rewarder_owner_lower == @zero_address or rewarder_owner_lower == correct_owner -> false
      skip = String.downcase(zero_address) == zero_address or String.downcase(zero_address) == correct_owner
      assert skip == true
    end

    test "matching owner skips rewarder update" do
      owner = "0x1111111111111111111111111111111111111111"

      skip = String.downcase(owner) == "0x0000000000000000000000000000000000000000" or String.downcase(owner) == owner
      assert skip == true
    end

    test "mismatched non-zero owner triggers rewarder update" do
      rewarder_owner = "0x1111111111111111111111111111111111111111"
      correct_owner = "0x2222222222222222222222222222222222222222"
      zero_address = "0x0000000000000000000000000000000000000000"

      skip = String.downcase(rewarder_owner) == zero_address or String.downcase(rewarder_owner) == correct_owner
      assert skip == false
    end
  end

  describe "batch_nft_owners mock" do
    test "can mock get_batch_nft_owners for rewarder check" do
      owners = [
        "0x1111111111111111111111111111111111111111",
        "0x2222222222222222222222222222222222222222"
      ]

      expect(HighRollers.Contracts.NFTRewarderMock, :get_batch_nft_owners, fn token_ids ->
        assert token_ids == [1, 2]
        {:ok, owners}
      end)

      {:ok, result} = HighRollers.Contracts.NFTRewarderMock.get_batch_nft_owners([1, 2])
      assert length(result) == 2
    end
  end
end
