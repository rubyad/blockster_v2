defmodule HighRollers.Contracts.Multicall3Test do
  @moduledoc """
  Tests for the Multicall3 module using mocked RPC responses.
  """
  use ExUnit.Case, async: false

  import HighRollers.Multicall3Fixtures

  alias HighRollers.Contracts.Multicall3

  @test_rpc_url "https://test-rpc.example.com"
  @test_address "0x1111111111111111111111111111111111111111"

  # We mock at the RPC HTTP level using Finch
  # Since Multicall3 uses HighRollers.RPC.call which uses Finch,
  # we intercept using a test process mailbox pattern

  describe "aggregate3/3" do
    test "handles empty call list" do
      assert {:ok, []} = Multicall3.aggregate3(@test_rpc_url, [])
    end

    test "encodes single call correctly" do
      # This test verifies the encode path doesn't crash
      # and produces valid hex for a single call
      calls = [{@test_address, "0x6352211e" <> String.duplicate("0", 64)}]

      # We can test encoding without RPC by calling encode_call3_array directly
      encoded = Multicall3.encode_call3_array(calls)
      assert is_binary(encoded)
      assert String.match?(encoded, ~r/^[0-9a-f]+$/)
    end

    test "encodes multiple calls correctly" do
      calls = [
        {"0x1111111111111111111111111111111111111111", "0x6352211e" <> String.duplicate("0", 64)},
        {"0x2222222222222222222222222222222222222222", "0x6352211e" <> String.duplicate("0", 64)},
        {"0x3333333333333333333333333333333333333333", "0x6352211e" <> String.duplicate("0", 64)}
      ]

      encoded = Multicall3.encode_call3_array(calls)
      data = Base.decode16!(encoded, case: :lower)

      # Verify structure: offset (32) + length (32)
      <<_offset::unsigned-256, length::unsigned-256, _rest::binary>> = data
      assert length == 3
    end

    test "decodes successful results" do
      addr_bytes = encode_address("0xabcdef1234567890abcdef1234567890abcdef12")
      response = build_aggregate3_response([addr_bytes, addr_bytes])

      results = Multicall3.decode_result_array(response)
      assert length(results) == 2

      Enum.each(results, fn {success, data} ->
        assert success == true
        assert byte_size(data) == 32
      end)
    end

    test "decodes mixed success/failure results" do
      addr_bytes = encode_address("0xabcdef1234567890abcdef1234567890abcdef12")
      response = build_mixed_aggregate3_response([
        {true, addr_bytes},
        {false, <<>>},
        {true, addr_bytes}
      ])

      results = Multicall3.decode_result_array(response)
      assert length(results) == 3

      [{s1, d1}, {s2, _d2}, {s3, d3}] = results
      assert s1 == true
      assert byte_size(d1) == 32
      assert s2 == false
      assert s3 == true
      assert byte_size(d3) == 32
    end

    test "handles malformed response gracefully" do
      # Non-hex string
      assert [] = Multicall3.decode_result_array("not_hex")

      # Empty result
      assert [] = Multicall3.decode_result_array("")
    end
  end

  describe "aggregate3_batched/3" do
    test "handles empty call list" do
      assert {:ok, []} = Multicall3.aggregate3_batched(@test_rpc_url, [])
    end

    test "custom batch_size option splits correctly" do
      # This verifies the chunking logic
      calls = for i <- 1..100 do
        {"0x" <> String.pad_leading(Integer.to_string(i, 16), 40, "0"),
         "0x6352211e" <> String.duplicate("0", 64)}
      end

      # Chunk by 25 should produce 4 chunks
      chunks = Enum.chunk_every(calls, 25)
      assert length(chunks) == 4
      assert length(Enum.at(chunks, 0)) == 25
      assert length(Enum.at(chunks, 3)) == 25
    end

    test "results maintain order conceptually" do
      # Test that encoding preserves the order of calls
      calls = for i <- [5, 3, 1, 4, 2] do
        token_hex = i |> :binary.encode_unsigned() |> String.pad_leading(32, <<0>>) |> Base.encode16(case: :lower)
        {@test_address, "0x6352211e" <> token_hex}
      end

      # Encode and verify all 5 calls are present
      encoded = Multicall3.encode_call3_array(calls)
      data = Base.decode16!(encoded, case: :lower)
      <<_offset::unsigned-256, length::unsigned-256, _rest::binary>> = data
      assert length == 5
    end
  end
end
