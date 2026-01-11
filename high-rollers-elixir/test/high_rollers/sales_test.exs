defmodule HighRollers.SalesTest do
  @moduledoc """
  Tests for Sales Mnesia operations (mints and affiliate earnings).
  """
  use HighRollers.MnesiaCase, async: false

  alias HighRollers.Sales
  alias HighRollers.NFTStore

  # Start NFTStore GenServer for tests
  setup do
    # Try to start NFTStore, handling the case where it's already running
    case start_supervised(NFTStore) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    :ok
  end

  describe "get_sales/2" do
    test "returns paginated minted NFTs" do
      now = System.system_time(:second)

      insert_test_nft(%{token_id: 1, mint_tx_hash: "0x1", created_at: now - 300})
      insert_test_nft(%{token_id: 2, mint_tx_hash: "0x2", created_at: now - 200})
      insert_test_nft(%{token_id: 3, mint_tx_hash: "0x3", created_at: now - 100})
      insert_test_nft(%{token_id: 4, mint_tx_hash: nil})  # No mint tx - not a sale

      sales = Sales.get_sales(2, 0)
      assert length(sales) == 2

      # Most recent first
      assert Enum.at(sales, 0).token_id == 3
      assert Enum.at(sales, 1).token_id == 2
    end

    test "formats sale data correctly" do
      insert_test_nft(%{
        token_id: 1,
        original_buyer: "0xBUYER",
        hostess_index: 0,
        hostess_name: "Penelope Fatale",
        mint_price: "320000000000000000",  # 0.32 ETH
        mint_tx_hash: "0xabc123"
      })

      sales = Sales.get_sales()
      sale = Enum.at(sales, 0)

      assert sale.token_id == 1
      assert sale.buyer == "0xbuyer"  # Lowercased
      assert sale.hostess_index == 0
      assert sale.hostess_name == "Penelope Fatale"
      assert sale.price == "320000000000000000"
      assert sale.price_eth == "0.320000"  # Formatted
      assert sale.tx_hash == "0xabc123"
    end

    test "supports offset pagination" do
      now = System.system_time(:second)

      for i <- 1..10 do
        insert_test_nft(%{token_id: i, mint_tx_hash: "0x#{i}", created_at: now - i * 100})
      end

      # Page 2
      sales = Sales.get_sales(3, 3)
      assert length(sales) == 3
      assert Enum.at(sales, 0).token_id == 4  # After first 3
    end
  end

  describe "insert/1" do
    test "delegates to NFTStore.upsert" do
      attrs = %{
        token_id: 1,
        owner: "0xOWNER",
        original_buyer: "0xBUYER",
        hostess_index: 0,
        hostess_name: "Penelope Fatale",
        mint_tx_hash: "0xabc123",
        mint_block_number: 12345,
        mint_price: "320000000000000000"
      }

      assert :ok = Sales.insert(attrs)

      nft = NFTStore.get(1)
      assert nft.mint_tx_hash == "0xabc123"
    end
  end

  describe "insert_affiliate_earning/1" do
    test "inserts affiliate earning record" do
      attrs = %{
        token_id: 1,
        tier: 1,
        affiliate: "0xAFFILIATE",
        earnings: "16000000000000000",  # 0.016 ETH (5%)
        tx_hash: "0xmint123"
      }

      assert :ok = Sales.insert_affiliate_earning(attrs)

      earnings = Sales.get_earnings_by_token(1)
      assert length(earnings) == 1
      assert Enum.at(earnings, 0).tier == 1
      assert Enum.at(earnings, 0).earnings == "16000000000000000"
    end

    test "supports multiple earnings per token (tier1 and tier2)" do
      # Tier 1 (5%)
      Sales.insert_affiliate_earning(%{
        token_id: 1,
        tier: 1,
        affiliate: "0xTIER1",
        earnings: "16000000000000000",
        tx_hash: "0xmint"
      })

      # Tier 2 (1%)
      Sales.insert_affiliate_earning(%{
        token_id: 1,
        tier: 2,
        affiliate: "0xTIER2",
        earnings: "3200000000000000",
        tx_hash: "0xmint"
      })

      earnings = Sales.get_earnings_by_token(1)
      assert length(earnings) == 2
    end
  end

  describe "get_affiliate_stats/1" do
    test "calculates affiliate stats" do
      affiliate = "0xAFFILIATE"

      # Tier 1 earnings
      Sales.insert_affiliate_earning(%{
        token_id: 1, tier: 1, affiliate: affiliate,
        earnings: "16000000000000000", tx_hash: "0x1"
      })
      Sales.insert_affiliate_earning(%{
        token_id: 2, tier: 1, affiliate: affiliate,
        earnings: "16000000000000000", tx_hash: "0x2"
      })

      # Tier 2 earnings
      Sales.insert_affiliate_earning(%{
        token_id: 3, tier: 2, affiliate: affiliate,
        earnings: "3200000000000000", tx_hash: "0x3"
      })

      stats = Sales.get_affiliate_stats(affiliate)

      assert stats.tier1_count == 2
      assert stats.tier1_total == 32_000_000_000_000_000  # 2 × 0.016 ETH
      assert stats.tier2_count == 1
      assert stats.tier2_total == 3_200_000_000_000_000   # 0.0032 ETH
      assert stats.total_earned == 35_200_000_000_000_000
    end

    test "handles case-insensitive address lookup" do
      Sales.insert_affiliate_earning(%{
        token_id: 1, tier: 1, affiliate: "0xAbCdEf",
        earnings: "16000000000000000", tx_hash: "0x1"
      })

      stats = Sales.get_affiliate_stats("0xABCDEF")
      assert stats.tier1_count == 1
    end

    test "returns zeros for affiliate with no earnings" do
      stats = Sales.get_affiliate_stats("0xNONEXISTENT")

      assert stats.tier1_count == 0
      assert stats.tier1_total == 0
      assert stats.tier2_count == 0
      assert stats.tier2_total == 0
      assert stats.total_earned == 0
    end
  end

  describe "get_affiliate_earnings/3" do
    test "returns all earnings when address is nil" do
      Sales.insert_affiliate_earning(%{
        token_id: 1, tier: 1, affiliate: "0xAFF1",
        earnings: "16000000000000000", tx_hash: "0x1"
      })
      Sales.insert_affiliate_earning(%{
        token_id: 2, tier: 1, affiliate: "0xAFF2",
        earnings: "16000000000000000", tx_hash: "0x2"
      })

      earnings = Sales.get_affiliate_earnings(nil)
      assert length(earnings) == 2
    end

    test "filters by affiliate address" do
      Sales.insert_affiliate_earning(%{
        token_id: 1, tier: 1, affiliate: "0xAFF1",
        earnings: "16000000000000000", tx_hash: "0x1"
      })
      Sales.insert_affiliate_earning(%{
        token_id: 2, tier: 1, affiliate: "0xAFF2",
        earnings: "16000000000000000", tx_hash: "0x2"
      })

      earnings = Sales.get_affiliate_earnings("0xAFF1")
      assert length(earnings) == 1
      assert Enum.at(earnings, 0).affiliate == "0xaff1"
    end

    test "supports pagination" do
      for i <- 1..10 do
        Sales.insert_affiliate_earning(%{
          token_id: i, tier: 1, affiliate: "0xAFF",
          earnings: "16000000000000000", tx_hash: "0x#{i}"
        })
      end

      earnings = Sales.get_affiliate_earnings("0xAFF", 5, 3)
      assert length(earnings) == 5
    end

    test "includes hostess_index from NFT lookup" do
      # Insert NFT first
      insert_test_nft(%{token_id: 1, hostess_index: 3})

      Sales.insert_affiliate_earning(%{
        token_id: 1, tier: 1, affiliate: "0xAFF",
        earnings: "16000000000000000", tx_hash: "0x1"
      })

      earnings = Sales.get_affiliate_earnings("0xAFF")
      assert Enum.at(earnings, 0).hostess_index == 3
    end

    test "formats earnings as ETH" do
      insert_test_nft(%{token_id: 1})

      Sales.insert_affiliate_earning(%{
        token_id: 1, tier: 1, affiliate: "0xAFF",
        earnings: "16000000000000000",  # 0.016 ETH
        tx_hash: "0x1"
      })

      earnings = Sales.get_affiliate_earnings("0xAFF")
      assert Enum.at(earnings, 0).earnings_eth == "0.016000"
    end
  end

  describe "get_earnings_by_token/1" do
    test "returns all earnings for a token" do
      # Multiple affiliates for same token
      Sales.insert_affiliate_earning(%{
        token_id: 1, tier: 1, affiliate: "0xTIER1",
        earnings: "16000000000000000", tx_hash: "0xmint"
      })
      Sales.insert_affiliate_earning(%{
        token_id: 1, tier: 2, affiliate: "0xTIER2",
        earnings: "3200000000000000", tx_hash: "0xmint"
      })

      # Different token
      Sales.insert_affiliate_earning(%{
        token_id: 2, tier: 1, affiliate: "0xTIER1",
        earnings: "16000000000000000", tx_hash: "0xmint2"
      })

      earnings = Sales.get_earnings_by_token(1)
      assert length(earnings) == 2

      tiers = Enum.map(earnings, & &1.tier) |> Enum.sort()
      assert tiers == [1, 2]
    end

    test "returns empty list for token with no earnings" do
      earnings = Sales.get_earnings_by_token(99999)
      assert earnings == []
    end
  end
end
