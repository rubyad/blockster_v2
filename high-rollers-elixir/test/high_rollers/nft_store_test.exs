defmodule HighRollers.NFTStoreTest do
  @moduledoc """
  Tests for NFTStore Mnesia CRUD operations.
  Requires Mnesia tables - uses MnesiaCase for RAM-only test tables.
  """
  use HighRollers.MnesiaCase, async: false

  alias HighRollers.NFTStore

  # Start NFTStore GenServer for each test
  setup do
    # Try to start NFTStore, handling the case where it's already running
    case start_supervised(NFTStore) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    :ok
  end

  describe "upsert/1" do
    test "inserts new NFT record" do
      attrs = %{
        token_id: 1,
        owner: "0xABC123",
        hostess_index: 0,
        hostess_name: "Penelope Fatale",
        mint_tx_hash: "0xdef456"
      }

      assert :ok = NFTStore.upsert(attrs)

      nft = NFTStore.get(1)
      assert nft.token_id == 1
      assert nft.owner == "0xabc123"  # Lowercased
      assert nft.hostess_name == "Penelope Fatale"
    end

    test "updates existing NFT record preserving earnings" do
      # Insert initial NFT
      insert_test_nft(%{token_id: 1, total_earned: "1000000"})

      # Upsert with new owner (earnings should be preserved)
      attrs = %{
        token_id: 1,
        owner: "0xNEWOWNER",
        hostess_index: 0,
        hostess_name: "Penelope Fatale"
      }

      assert :ok = NFTStore.upsert(attrs)

      nft = NFTStore.get(1)
      assert nft.owner == "0xnewowner"
      assert nft.total_earned == "1000000"  # Preserved from original
    end

    test "sets default values for earnings fields" do
      attrs = %{
        token_id: 1,
        owner: "0xABC123",
        hostess_index: 0,
        hostess_name: "Penelope Fatale"
      }

      assert :ok = NFTStore.upsert(attrs)

      nft = NFTStore.get(1)
      assert nft.total_earned == "0"
      assert nft.pending_amount == "0"
      assert nft.last_24h_earned == "0"
      assert nft.apy_basis_points == 0
    end
  end

  describe "get/1" do
    test "returns NFT by token_id" do
      insert_test_nft(%{token_id: 42, hostess_index: 3})

      nft = NFTStore.get(42)
      assert nft.token_id == 42
      assert nft.hostess_index == 3
    end

    test "returns nil for non-existent token_id" do
      assert NFTStore.get(99999) == nil
    end
  end

  describe "get_by_owner/1" do
    test "returns all NFTs owned by address" do
      owner = "0xOWNER123"
      insert_test_nft(%{token_id: 1, owner: owner})
      insert_test_nft(%{token_id: 2, owner: owner})
      insert_test_nft(%{token_id: 3, owner: "0xOTHER"})

      nfts = NFTStore.get_by_owner(owner)
      assert length(nfts) == 2
      assert Enum.all?(nfts, fn nft -> nft.owner == String.downcase(owner) end)
    end

    test "handles case-insensitive lookup" do
      insert_test_nft(%{token_id: 1, owner: "0xAbCdEf"})

      # Query with different case
      nfts = NFTStore.get_by_owner("0xABCDEF")
      assert length(nfts) == 1
    end

    test "returns empty list for owner with no NFTs" do
      nfts = NFTStore.get_by_owner("0xNONEXISTENT")
      assert nfts == []
    end
  end

  describe "get_all/0" do
    test "returns all NFTs" do
      insert_test_nft(%{token_id: 1})
      insert_test_nft(%{token_id: 2})
      insert_test_nft(%{token_id: 3})

      nfts = NFTStore.get_all()
      assert length(nfts) == 3
    end

    test "returns empty list when no NFTs exist" do
      nfts = NFTStore.get_all()
      assert nfts == []
    end
  end

  describe "update_owner/2" do
    test "updates NFT owner" do
      insert_test_nft(%{token_id: 1, owner: "0xOLD"})

      assert :ok = NFTStore.update_owner(1, "0xNEW")

      nft = NFTStore.get(1)
      assert nft.owner == "0xnew"
    end

    test "returns error for non-existent NFT" do
      assert {:error, :not_found} = NFTStore.update_owner(99999, "0xNEW")
    end
  end

  describe "update_earnings/2" do
    test "updates earnings fields" do
      insert_test_nft(%{token_id: 1})

      attrs = %{
        total_earned: "5000000000000000000",
        pending_amount: "1000000000000000000",
        last_24h_earned: "500000000000000000",
        apy_basis_points: 1200
      }

      assert :ok = NFTStore.update_earnings(1, attrs)

      nft = NFTStore.get(1)
      assert nft.total_earned == "5000000000000000000"
      assert nft.pending_amount == "1000000000000000000"
      assert nft.last_24h_earned == "500000000000000000"
      assert nft.apy_basis_points == 1200
    end

    test "partial update preserves other fields" do
      insert_test_nft(%{token_id: 1, total_earned: "1000", pending_amount: "500"})

      # Only update total_earned
      assert :ok = NFTStore.update_earnings(1, %{total_earned: "2000"})

      nft = NFTStore.get(1)
      assert nft.total_earned == "2000"
      assert nft.pending_amount == "500"  # Preserved
    end
  end

  describe "count/0" do
    test "returns total NFT count" do
      assert NFTStore.count() == 0

      insert_test_nft(%{token_id: 1})
      insert_test_nft(%{token_id: 2})

      assert NFTStore.count() == 2
    end
  end

  describe "count_by_hostess/1" do
    test "returns count for specific hostess" do
      insert_test_nft(%{token_id: 1, hostess_index: 0})
      insert_test_nft(%{token_id: 2, hostess_index: 0})
      insert_test_nft(%{token_id: 3, hostess_index: 5})

      assert NFTStore.count_by_hostess(0) == 2
      assert NFTStore.count_by_hostess(5) == 1
      assert NFTStore.count_by_hostess(7) == 0
    end
  end

  describe "get_counts_by_hostess/0" do
    test "returns map of counts for all hostess types" do
      insert_test_nft(%{token_id: 1, hostess_index: 0})
      insert_test_nft(%{token_id: 2, hostess_index: 0})
      insert_test_nft(%{token_id: 3, hostess_index: 3})

      counts = NFTStore.get_counts_by_hostess()

      assert counts[0] == 2
      assert counts[3] == 1
      assert counts[7] == 0  # All indices present
    end
  end

  describe "get_total_multiplier_points/0" do
    test "calculates sum of multipliers for all NFTs" do
      # Insert NFTs with different hostesses
      insert_test_nft(%{token_id: 1, hostess_index: 0})  # 100x
      insert_test_nft(%{token_id: 2, hostess_index: 7})  # 30x

      total = NFTStore.get_total_multiplier_points()
      assert total == 130
    end
  end

  describe "special NFTs (time rewards)" do
    test "get_special_nfts_by_owner/1 returns only special NFTs" do
      owner = "0xOWNER"
      # Regular NFTs
      insert_test_nft(%{token_id: 100, owner: owner})
      insert_test_nft(%{token_id: 2339, owner: owner})
      # Special NFTs (2340-2700)
      insert_test_nft(%{token_id: 2340, owner: owner})
      insert_test_nft(%{token_id: 2500, owner: owner})
      insert_test_nft(%{token_id: 2700, owner: owner})
      # Another owner's special NFT
      insert_test_nft(%{token_id: 2341, owner: "0xOTHER"})

      special = NFTStore.get_special_nfts_by_owner(owner)
      assert length(special) == 3
      assert Enum.all?(special, fn nft -> nft.token_id >= 2340 and nft.token_id <= 2700 end)
    end

    test "get_special_nfts_by_owner/1 with nil returns all special NFTs" do
      insert_test_nft(%{token_id: 2340, owner: "0xONE"})
      insert_test_nft(%{token_id: 2341, owner: "0xTWO"})
      insert_test_nft(%{token_id: 100, owner: "0xONE"})  # Not special

      special = NFTStore.get_special_nfts_by_owner(nil)
      assert length(special) == 2
    end

    test "count_special_by_hostess/1 counts only special NFTs" do
      # Regular NFTs
      insert_test_nft(%{token_id: 100, hostess_index: 0})
      # Special NFTs
      insert_test_nft(%{token_id: 2340, hostess_index: 0})
      insert_test_nft(%{token_id: 2341, hostess_index: 0})
      insert_test_nft(%{token_id: 2342, hostess_index: 5})

      assert NFTStore.count_special_by_hostess(0) == 2
      assert NFTStore.count_special_by_hostess(5) == 1
      assert NFTStore.count_special_by_hostess(7) == 0
    end

    test "update_time_reward/2 updates time reward fields" do
      insert_test_nft(%{token_id: 2340})

      attrs = %{
        time_start_time: 1704067200,
        time_last_claim: 1704153600,
        time_total_claimed: "1000000000000000000"
      }

      assert :ok = NFTStore.update_time_reward(2340, attrs)

      nft = NFTStore.get(2340)
      assert nft.time_start_time == 1704067200
      assert nft.time_last_claim == 1704153600
      assert nft.time_total_claimed == "1000000000000000000"
    end

    test "record_time_claim/2 updates last_claim and accumulates total" do
      insert_test_nft(%{
        token_id: 2340,
        time_start_time: 1704067200,
        time_last_claim: 1704067200,
        time_total_claimed: "1000000000000000000"
      })

      # Claim 500 wei
      assert :ok = NFTStore.record_time_claim(2340, 500_000_000_000_000_000)

      nft = NFTStore.get(2340)
      assert nft.time_total_claimed == "1500000000000000000"  # Accumulated
      assert nft.time_last_claim != 1704067200  # Updated to now
    end
  end

  describe "pending mints" do
    test "insert_pending_mint/1 creates pending record" do
      attrs = %{
        request_id: "12345",
        sender: "0xBUYER",
        token_id: 100,
        price: "320000000000000000",
        tx_hash: "0xabc123"
      }

      assert :ok = NFTStore.insert_pending_mint(attrs)

      pending = NFTStore.get_pending_mint("12345")
      assert pending.request_id == "12345"
      assert pending.sender == "0xBUYER"
      assert pending.token_id == 100
    end

    test "delete_pending_mint/1 removes pending record" do
      attrs = %{
        request_id: "12345",
        sender: "0xBUYER",
        token_id: 100,
        price: "320000000000000000",
        tx_hash: "0xabc123"
      }

      NFTStore.insert_pending_mint(attrs)
      assert NFTStore.get_pending_mint("12345") != nil

      assert :ok = NFTStore.delete_pending_mint("12345")
      assert NFTStore.get_pending_mint("12345") == nil
    end

    test "get_pending_mint/1 returns nil for non-existent" do
      assert NFTStore.get_pending_mint("nonexistent") == nil
    end
  end

  describe "get_recent_sales/1" do
    test "returns most recent minted NFTs" do
      now = System.system_time(:second)

      insert_test_nft(%{token_id: 1, mint_tx_hash: "0x1", created_at: now - 100})
      insert_test_nft(%{token_id: 2, mint_tx_hash: "0x2", created_at: now - 50})
      insert_test_nft(%{token_id: 3, mint_tx_hash: "0x3", created_at: now})
      insert_test_nft(%{token_id: 4, mint_tx_hash: nil, created_at: now})  # No mint tx

      sales = NFTStore.get_recent_sales(2)
      assert length(sales) == 2
      # Most recent first
      assert Enum.at(sales, 0).token_id == 3
      assert Enum.at(sales, 1).token_id == 2
    end
  end
end
