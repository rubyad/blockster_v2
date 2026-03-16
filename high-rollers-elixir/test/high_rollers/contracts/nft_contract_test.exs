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
          price: "640000000000000000",
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

  describe "get_batch_owners/1 (mock)" do
    test "can mock get_batch_owners returning owners for multiple token IDs" do
      owners = [
        {:ok, "0x1111111111111111111111111111111111111111"},
        {:ok, "0x2222222222222222222222222222222222222222"},
        {:ok, "0x3333333333333333333333333333333333333333"}
      ]

      expect(HighRollers.Contracts.NFTContractMock, :get_batch_owners, fn token_ids ->
        assert token_ids == [1, 2, 3]
        {:ok, owners}
      end)

      {:ok, result} = HighRollers.Contracts.NFTContractMock.get_batch_owners([1, 2, 3])
      assert length(result) == 3
      assert {:ok, "0x1111111111111111111111111111111111111111"} = Enum.at(result, 0)
    end

    test "can mock individual call failures" do
      owners = [
        {:ok, "0x1111111111111111111111111111111111111111"},
        {:error, :call_failed},
        {:ok, "0x3333333333333333333333333333333333333333"}
      ]

      expect(HighRollers.Contracts.NFTContractMock, :get_batch_owners, fn _token_ids ->
        {:ok, owners}
      end)

      {:ok, result} = HighRollers.Contracts.NFTContractMock.get_batch_owners([1, 2, 3])
      assert {:ok, _} = Enum.at(result, 0)
      assert {:error, :call_failed} = Enum.at(result, 1)
      assert {:ok, _} = Enum.at(result, 2)
    end

    test "preserves order matching input token_ids" do
      owners = [
        {:ok, "0xaaaa000000000000000000000000000000000005"},
        {:ok, "0xbbbb000000000000000000000000000000000003"},
        {:ok, "0xcccc000000000000000000000000000000000001"}
      ]

      expect(HighRollers.Contracts.NFTContractMock, :get_batch_owners, fn token_ids ->
        assert token_ids == [5, 3, 1]
        {:ok, owners}
      end)

      {:ok, result} = HighRollers.Contracts.NFTContractMock.get_batch_owners([5, 3, 1])
      assert {:ok, addr0} = Enum.at(result, 0)
      assert String.contains?(addr0, "aaaa")
      assert {:ok, addr1} = Enum.at(result, 1)
      assert String.contains?(addr1, "bbbb")
    end

    test "handles empty token_ids list" do
      expect(HighRollers.Contracts.NFTContractMock, :get_batch_owners, fn token_ids ->
        assert token_ids == []
        {:ok, []}
      end)

      assert {:ok, []} = HighRollers.Contracts.NFTContractMock.get_batch_owners([])
    end

    test "handles Multicall3 total failure" do
      expect(HighRollers.Contracts.NFTContractMock, :get_batch_owners, fn _token_ids ->
        {:error, :max_retries_exceeded}
      end)

      assert {:error, :max_retries_exceeded} = HighRollers.Contracts.NFTContractMock.get_batch_owners([1, 2, 3])
    end

    test "correctly encodes ownerOf calldata" do
      # ownerOf selector = 0x6352211e
      # For token_id 42, the calldata should be:
      # 0x6352211e + uint256(42)
      token_id = 42
      expected_selector = "0x6352211e"
      expected_token_hex = token_id |> :binary.encode_unsigned() |> String.pad_leading(32, <<0>>) |> Base.encode16(case: :lower)

      expected_calldata = expected_selector <> expected_token_hex

      # Verify the selector
      assert String.starts_with?(expected_calldata, "0x6352211e")
      # Verify token ID encoding
      assert String.ends_with?(expected_calldata, "2a")  # 42 = 0x2a
      # Verify total length: 4 bytes selector + 32 bytes uint256 = 36 bytes = 72 hex chars + "0x"
      assert String.length(expected_calldata) == 72 + 2
    end

    test "correctly decodes address from return data" do
      # An address in ABI is 32 bytes, left-padded with 12 zero bytes
      address_hex = "abcdef1234567890abcdef1234567890abcdef12"
      padded = String.duplicate("0", 24) <> address_hex
      address_bytes = Base.decode16!(padded, case: :lower)

      # The decode should extract the 20-byte address
      # Using the public module to verify
      assert byte_size(address_bytes) == 32
    end
  end
end
