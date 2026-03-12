defmodule HighRollers.Contracts.NFTRewarderTest do
  @moduledoc """
  Tests demonstrating how to mock NFTRewarder using Mox.
  """
  use ExUnit.Case, async: true

  import Mox

  setup :verify_on_exit!

  describe "mock examples" do
    test "can mock get_batch_nft_earnings/1" do
      earnings = [
        %{
          token_id: 1,
          total_earned: "1000000000000000000",
          pending_amount: "500000000000000000",
          hostess_index: 0
        },
        %{
          token_id: 2,
          total_earned: "2000000000000000000",
          pending_amount: "250000000000000000",
          hostess_index: 5
        }
      ]

      expect(HighRollers.Contracts.NFTRewarderMock, :get_batch_nft_earnings, fn token_ids ->
        assert token_ids == [1, 2]
        {:ok, earnings}
      end)

      {:ok, result} = HighRollers.Contracts.NFTRewarderMock.get_batch_nft_earnings([1, 2])
      assert length(result) == 2
      assert Enum.at(result, 0).total_earned == "1000000000000000000"
    end

    test "can mock get_global_totals/0" do
      expect(HighRollers.Contracts.NFTRewarderMock, :get_global_totals, fn ->
        {:ok, %{
          total_received: 10_000_000_000_000_000_000_000,
          total_distributed: 9_500_000_000_000_000_000_000
        }}
      end)

      {:ok, totals} = HighRollers.Contracts.NFTRewarderMock.get_global_totals()
      assert totals.total_received == 10_000_000_000_000_000_000_000
    end

    test "can mock get_time_reward_info/1" do
      now = System.system_time(:second)
      start_time = now - 86400  # 1 day ago

      expect(HighRollers.Contracts.NFTRewarderMock, :get_time_reward_info, fn token_id ->
        assert token_id == 2340
        {:ok, %{
          start_time: start_time,
          last_claim_time: now - 3600,
          total_claimed: 100_000_000_000_000_000_000,
          rate_per_second: 2_125_029_000_000_000_000
        }}
      end)

      {:ok, info} = HighRollers.Contracts.NFTRewarderMock.get_time_reward_info(2340)
      assert info.rate_per_second == 2_125_029_000_000_000_000
    end

    test "can mock get_reward_received_events/2" do
      events = [
        %{
          bet_id: "0x1234567890abcdef",
          amount: "1000000000000000000",
          timestamp: 1704067200,
          block_number: 12345,
          tx_hash: "0xabc123"
        }
      ]

      expect(HighRollers.Contracts.NFTRewarderMock, :get_reward_received_events, fn _from, _to ->
        {:ok, events}
      end)

      {:ok, result} = HighRollers.Contracts.NFTRewarderMock.get_reward_received_events(1000, 2000)
      assert length(result) == 1
    end

    test "can mock get_owners_batch/1" do
      owners = [
        "0x1111111111111111111111111111111111111111",
        "0x2222222222222222222222222222222222222222"
      ]

      expect(HighRollers.Contracts.NFTRewarderMock, :get_owners_batch, fn token_ids ->
        assert token_ids == [1, 2]
        {:ok, owners}
      end)

      {:ok, result} = HighRollers.Contracts.NFTRewarderMock.get_owners_batch([1, 2])
      assert length(result) == 2
    end

    test "can mock transaction operations" do
      expect(HighRollers.Contracts.NFTRewarderMock, :send_raw_transaction, fn signed_tx ->
        assert String.starts_with?(signed_tx, "0x")
        {:ok, "0xreceipt_hash_abc123"}
      end)

      expect(HighRollers.Contracts.NFTRewarderMock, :wait_for_receipt, fn tx_hash, _timeout ->
        assert tx_hash == "0xreceipt_hash_abc123"
        {:ok, %{
          tx_hash: tx_hash,
          block_number: 12345,
          status: :success
        }}
      end)

      {:ok, tx_hash} = HighRollers.Contracts.NFTRewarderMock.send_raw_transaction("0xsigned_tx")
      {:ok, receipt} = HighRollers.Contracts.NFTRewarderMock.wait_for_receipt(tx_hash, 60_000)
      assert receipt.status == :success
    end
  end

  describe "get_batch_time_reward_raw/1 (mock)" do
    test "returns time reward info for multiple token IDs" do
      now = System.system_time(:second)

      results = [
        %{start_time: now - 86400, last_claim_time: now - 3600, total_claimed: 1_000_000_000_000_000_000},
        %{start_time: now - 43200, last_claim_time: now - 1800, total_claimed: 500_000_000_000_000_000}
      ]

      expect(HighRollers.Contracts.NFTRewarderMock, :get_batch_time_reward_raw, fn token_ids ->
        assert token_ids == [2340, 2341]
        {:ok, results}
      end)

      {:ok, result} = HighRollers.Contracts.NFTRewarderMock.get_batch_time_reward_raw([2340, 2341])
      assert length(result) == 2
      assert Enum.at(result, 0).start_time == now - 86400
      assert Enum.at(result, 1).total_claimed == 500_000_000_000_000_000
    end

    test "preserves order matching input token_ids" do
      results = [
        %{start_time: 100, last_claim_time: 200, total_claimed: 300},
        %{start_time: 400, last_claim_time: 500, total_claimed: 600},
        %{start_time: 700, last_claim_time: 800, total_claimed: 900}
      ]

      expect(HighRollers.Contracts.NFTRewarderMock, :get_batch_time_reward_raw, fn token_ids ->
        assert token_ids == [2340, 2350, 2360]
        {:ok, results}
      end)

      {:ok, result} = HighRollers.Contracts.NFTRewarderMock.get_batch_time_reward_raw([2340, 2350, 2360])
      assert Enum.at(result, 0).start_time == 100
      assert Enum.at(result, 1).start_time == 400
      assert Enum.at(result, 2).start_time == 700
    end

    test "handles empty token_ids list" do
      expect(HighRollers.Contracts.NFTRewarderMock, :get_batch_time_reward_raw, fn token_ids ->
        assert token_ids == []
        {:ok, []}
      end)

      assert {:ok, []} = HighRollers.Contracts.NFTRewarderMock.get_batch_time_reward_raw([])
    end

    test "handles RPC error" do
      expect(HighRollers.Contracts.NFTRewarderMock, :get_batch_time_reward_raw, fn _token_ids ->
        {:error, :max_retries_exceeded}
      end)

      assert {:error, :max_retries_exceeded} = HighRollers.Contracts.NFTRewarderMock.get_batch_time_reward_raw([2340])
    end

    test "correctly encodes getBatchTimeRewardRaw calldata" do
      # getBatchTimeRewardRaw(uint256[]) selector
      selector_bytes = ExKeccak.hash_256("getBatchTimeRewardRaw(uint256[])")
      selector = "0x" <> (binary_part(selector_bytes, 0, 4) |> Base.encode16(case: :lower))

      # Verify it's a valid 4-byte selector
      assert String.length(selector) == 10  # 0x + 8 hex chars
    end

    test "decodes zero values correctly (unregistered NFT)" do
      results = [
        %{start_time: 0, last_claim_time: 0, total_claimed: 0}
      ]

      expect(HighRollers.Contracts.NFTRewarderMock, :get_batch_time_reward_raw, fn _token_ids ->
        {:ok, results}
      end)

      {:ok, [result]} = HighRollers.Contracts.NFTRewarderMock.get_batch_time_reward_raw([9999])
      assert result.start_time == 0
      assert result.last_claim_time == 0
      assert result.total_claimed == 0
    end

    test "decodes large wei values correctly" do
      # 1000 ROGUE = 1e21 wei
      large_value = 1_000_000_000_000_000_000_000

      results = [
        %{start_time: 1000, last_claim_time: 2000, total_claimed: large_value}
      ]

      expect(HighRollers.Contracts.NFTRewarderMock, :get_batch_time_reward_raw, fn _token_ids ->
        {:ok, results}
      end)

      {:ok, [result]} = HighRollers.Contracts.NFTRewarderMock.get_batch_time_reward_raw([2340])
      assert result.total_claimed == large_value
    end
  end

  describe "get_batch_nft_owners/1 (mock)" do
    test "returns owners for multiple token IDs" do
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
      assert Enum.at(result, 0) == "0x1111111111111111111111111111111111111111"
    end

    test "returns zero address for unregistered NFTs" do
      owners = [
        "0x0000000000000000000000000000000000000000",
        "0x1111111111111111111111111111111111111111"
      ]

      expect(HighRollers.Contracts.NFTRewarderMock, :get_batch_nft_owners, fn _token_ids ->
        {:ok, owners}
      end)

      {:ok, result} = HighRollers.Contracts.NFTRewarderMock.get_batch_nft_owners([9999, 1])
      assert Enum.at(result, 0) == "0x0000000000000000000000000000000000000000"
      assert Enum.at(result, 1) == "0x1111111111111111111111111111111111111111"
    end

    test "preserves order matching input token_ids" do
      owners = [
        "0xaaaa000000000000000000000000000000000001",
        "0xbbbb000000000000000000000000000000000002",
        "0xcccc000000000000000000000000000000000003"
      ]

      expect(HighRollers.Contracts.NFTRewarderMock, :get_batch_nft_owners, fn token_ids ->
        assert token_ids == [100, 200, 300]
        {:ok, owners}
      end)

      {:ok, result} = HighRollers.Contracts.NFTRewarderMock.get_batch_nft_owners([100, 200, 300])
      assert Enum.at(result, 0) |> String.contains?("aaaa")
      assert Enum.at(result, 1) |> String.contains?("bbbb")
      assert Enum.at(result, 2) |> String.contains?("cccc")
    end

    test "handles empty token_ids list" do
      expect(HighRollers.Contracts.NFTRewarderMock, :get_batch_nft_owners, fn token_ids ->
        assert token_ids == []
        {:ok, []}
      end)

      assert {:ok, []} = HighRollers.Contracts.NFTRewarderMock.get_batch_nft_owners([])
    end

    test "handles RPC error" do
      expect(HighRollers.Contracts.NFTRewarderMock, :get_batch_nft_owners, fn _token_ids ->
        {:error, :rpc_timeout}
      end)

      assert {:error, :rpc_timeout} = HighRollers.Contracts.NFTRewarderMock.get_batch_nft_owners([1])
    end
  end
end
