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
end
