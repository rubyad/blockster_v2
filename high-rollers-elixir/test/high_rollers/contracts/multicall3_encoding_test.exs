defmodule HighRollers.Contracts.Multicall3EncodingTest do
  @moduledoc """
  Tests for ABI encoding/decoding correctness in the Multicall3 module.
  """
  use ExUnit.Case, async: true

  alias HighRollers.Contracts.Multicall3

  describe "ABI encoding" do
    test "aggregate3 selector is correct (0x82ad56cb)" do
      # keccak256("aggregate3((address,bool,bytes)[])")
      selector_bytes = ExKeccak.hash_256("aggregate3((address,bool,bytes)[])")
      selector_hex = "0x" <> (binary_part(selector_bytes, 0, 4) |> Base.encode16(case: :lower))

      assert selector_hex == "0x82ad56cb"
    end

    test "single Call3 struct encoding" do
      address = "0x1111111111111111111111111111111111111111"
      calldata = "0x6352211e" <> String.duplicate("0", 64)  # ownerOf(0)

      encoded = Multicall3.encode_call3_array([{address, calldata}])

      # Should be valid hex
      assert is_binary(encoded)
      assert String.match?(encoded, ~r/^[0-9a-f]+$/)

      # Decode and verify structure
      data = Base.decode16!(encoded, case: :lower)

      # First 32 bytes: offset to array (should be 32 = 0x20)
      <<array_offset::unsigned-256, rest::binary>> = data
      assert array_offset == 32

      # Next 32 bytes: array length (should be 1)
      <<array_length::unsigned-256, _rest2::binary>> = rest
      assert array_length == 1
    end

    test "Call3 with varying calldata lengths" do
      address = "0x1111111111111111111111111111111111111111"

      # 4-byte calldata (just a selector)
      calldata_4 = "0x12345678"
      encoded_4 = Multicall3.encode_call3_array([{address, calldata_4}])
      assert is_binary(encoded_4)

      # 36-byte calldata (selector + 1 uint256)
      calldata_36 = "0x6352211e" <> String.duplicate("0", 64)
      encoded_36 = Multicall3.encode_call3_array([{address, calldata_36}])
      assert is_binary(encoded_36)

      # 68-byte calldata (selector + 2 uint256s)
      calldata_68 = "0x12345678" <> String.duplicate("0", 128)
      encoded_68 = Multicall3.encode_call3_array([{address, calldata_68}])
      assert is_binary(encoded_68)

      # Longer calldata produces larger encoding
      assert String.length(encoded_68) > String.length(encoded_36)
      assert String.length(encoded_36) > String.length(encoded_4)
    end

    test "empty calldata" do
      address = "0x1111111111111111111111111111111111111111"
      calldata = "0x"

      encoded = Multicall3.encode_call3_array([{address, calldata}])
      assert is_binary(encoded)
      data = Base.decode16!(encoded, case: :lower)

      # Should still have valid structure
      <<_array_offset::unsigned-256, array_length::unsigned-256, _rest::binary>> = data
      assert array_length == 1
    end

    test "address encoding is zero-padded to 32 bytes" do
      address = "0xaBcD000000000000000000000000000000001234"
      calldata = "0x12345678"

      encoded = Multicall3.encode_call3_array([{address, calldata}])
      data = Base.decode16!(encoded, case: :lower)

      # Skip: offset (32) + length (32) + struct offset (32) = 96 bytes
      <<_header::binary-size(96), struct_data::binary>> = data

      # First 32 bytes of struct = padded address
      <<address_word::binary-size(32), _rest::binary>> = struct_data

      # First 12 bytes should be zeros (padding), last 20 bytes = address
      <<padding::binary-size(12), addr_bytes::binary-size(20)>> = address_word
      assert padding == <<0::96>>
      assert "0x" <> Base.encode16(addr_bytes, case: :lower) == String.downcase(address)
    end

    test "multiple calls produce valid encoding" do
      calls = [
        {"0x1111111111111111111111111111111111111111", "0x6352211e" <> String.duplicate("0", 64)},
        {"0x2222222222222222222222222222222222222222", "0x6352211e" <> String.duplicate("0", 64)},
        {"0x3333333333333333333333333333333333333333", "0x6352211e" <> String.duplicate("0", 64)}
      ]

      encoded = Multicall3.encode_call3_array(calls)
      data = Base.decode16!(encoded, case: :lower)

      # Offset to array
      <<array_offset::unsigned-256, rest::binary>> = data
      assert array_offset == 32

      # Array length = 3
      <<array_length::unsigned-256, _rest2::binary>> = rest
      assert array_length == 3
    end
  end

  describe "ABI decoding" do
    test "single Result decoding" do
      # Build a response with one successful result containing an address
      address_bytes = <<0::96, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11,
                        0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11>>

      response = HighRollers.Multicall3Fixtures.build_aggregate3_response([address_bytes])

      results = Multicall3.decode_result_array(response)
      assert length(results) == 1

      [{success, return_data}] = results
      assert success == true
      assert byte_size(return_data) == 32
    end

    test "multiple Results decoding" do
      addr1 = <<0::96, 1::160>>
      addr2 = <<0::96, 2::160>>
      addr3 = <<0::96, 3::160>>

      response = HighRollers.Multicall3Fixtures.build_aggregate3_response([addr1, addr2, addr3])

      results = Multicall3.decode_result_array(response)
      assert length(results) == 3

      Enum.each(results, fn {success, data} ->
        assert success == true
        assert byte_size(data) == 32
      end)
    end

    test "empty return data on failure" do
      response = HighRollers.Multicall3Fixtures.build_mixed_aggregate3_response([{false, <<>>}])

      results = Multicall3.decode_result_array(response)
      assert length(results) == 1

      [{success, data}] = results
      assert success == false
      assert byte_size(data) == 0
    end

    test "large return data (multiple slots)" do
      # 128 bytes of return data
      large_data = :crypto.strong_rand_bytes(128)

      response = HighRollers.Multicall3Fixtures.build_aggregate3_response([large_data])

      results = Multicall3.decode_result_array(response)
      assert length(results) == 1

      [{success, data}] = results
      assert success == true
      assert data == large_data
    end

    test "mixed success/failure results" do
      addr_bytes = <<0::96, 0xAB::160>>

      response = HighRollers.Multicall3Fixtures.build_mixed_aggregate3_response([
        {true, addr_bytes},
        {false, <<>>},
        {true, addr_bytes}
      ])

      results = Multicall3.decode_result_array(response)
      assert length(results) == 3

      [{s1, _}, {s2, _}, {s3, _}] = results
      assert s1 == true
      assert s2 == false
      assert s3 == true
    end
  end
end
