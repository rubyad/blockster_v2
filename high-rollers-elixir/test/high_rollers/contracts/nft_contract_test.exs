defmodule HighRollers.Contracts.NFTContractTest do
  @moduledoc """
  Tests demonstrating how to mock NFTContract using Mox.

  These tests show the mocking pattern that other tests can use.
  """
  use ExUnit.Case, async: true

  import Mox

  # Verify mocks at end of each test
  setup :verify_on_exit!

  describe "mock examples" do
    test "can mock get_block_number/0" do
      expect(HighRollers.Contracts.NFTContractMock, :get_block_number, fn ->
        {:ok, 12345678}
      end)

      assert {:ok, 12345678} = HighRollers.Contracts.NFTContractMock.get_block_number()
    end

    test "can mock get_nft_minted_events/2" do
      events = [
        %{
          request_id: 1,
          recipient: "0x1234567890123456789012345678901234567890",
          price: "320000000000000000",
          token_id: 100,
          hostess_index: 0,
          affiliate: "0x0000000000000000000000000000000000000000",
          affiliate2: "0x0000000000000000000000000000000000000000",
          tx_hash: "0xabc123",
          block_number: 12345
        }
      ]

      expect(HighRollers.Contracts.NFTContractMock, :get_nft_minted_events, fn from, to ->
        assert from == 1000
        assert to == 2000
        {:ok, events}
      end)

      {:ok, result} = HighRollers.Contracts.NFTContractMock.get_nft_minted_events(1000, 2000)
      assert length(result) == 1
      assert Enum.at(result, 0).token_id == 100
    end

    test "can mock get_transfer_events/2" do
      events = [
        %{
          from: "0x0000000000000000000000000000000000000000",
          to: "0x1234567890123456789012345678901234567890",
          token_id: 100,
          tx_hash: "0xdef456",
          block_number: 12346
        }
      ]

      expect(HighRollers.Contracts.NFTContractMock, :get_transfer_events, fn _from, _to ->
        {:ok, events}
      end)

      {:ok, result} = HighRollers.Contracts.NFTContractMock.get_transfer_events(1000, 2000)
      assert length(result) == 1
    end

    test "can mock errors" do
      expect(HighRollers.Contracts.NFTContractMock, :get_total_supply, fn ->
        {:error, :rpc_timeout}
      end)

      assert {:error, :rpc_timeout} = HighRollers.Contracts.NFTContractMock.get_total_supply()
    end

    test "can mock multiple calls" do
      expect(HighRollers.Contracts.NFTContractMock, :get_owner_of, 2, fn token_id ->
        case token_id do
          1 -> {:ok, "0xowner1"}
          2 -> {:ok, "0xowner2"}
        end
      end)

      assert {:ok, "0xowner1"} = HighRollers.Contracts.NFTContractMock.get_owner_of(1)
      assert {:ok, "0xowner2"} = HighRollers.Contracts.NFTContractMock.get_owner_of(2)
    end
  end
end
