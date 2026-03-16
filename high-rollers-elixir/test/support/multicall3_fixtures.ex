defmodule HighRollers.Multicall3Fixtures do
  @moduledoc """
  Shared test helpers and fixtures for Multicall3 batching tests.

  Provides:
  - Pre-computed ABI-encoded payloads for known inputs
  - Mock RPC response builders
  - Helpers to build fake NFT structs for Mnesia
  """

  @doc """
  Build a mock RPC response for Multicall3.aggregate3 with all-success results.

  Each result has success=true and the provided return data.
  """
  def build_aggregate3_response(return_data_list) do
    encode_result_array(Enum.map(return_data_list, fn data -> {true, data} end))
  end

  @doc """
  Build a mock RPC response for Multicall3.aggregate3 with mixed results.

  Takes list of {success, return_data} tuples.
  """
  def build_mixed_aggregate3_response(results) do
    encode_result_array(results)
  end

  @doc """
  Build a 32-byte ABI-encoded address (left-padded with zeros).
  """
  def encode_address(address) do
    hex = String.replace_prefix(address, "0x", "")
    padding = String.duplicate("00", 12)
    Base.decode16!(padding <> hex, case: :mixed)
  end

  @doc """
  Build a 32-byte ABI-encoded uint256.
  """
  def encode_uint256_bytes(int) do
    int
    |> :binary.encode_unsigned()
    |> String.pad_leading(32, <<0>>)
  end

  @doc """
  Build a mock getBatchTimeRewardRaw response.

  Takes a list of {start_time, last_claim_time, total_claimed} tuples.
  Returns the "0x"-prefixed hex string as the RPC would.
  """
  def build_batch_time_reward_raw_response(entries) do
    n = length(entries)

    {start_times, last_claim_times, total_claimeds} =
      Enum.reduce(entries, {[], [], []}, fn {st, lct, tc}, {s_acc, l_acc, t_acc} ->
        {s_acc ++ [st], l_acc ++ [lct], t_acc ++ [tc]}
      end)

    # Three dynamic arrays — same encoding as getBatchNFTEarnings
    # Offsets to each array (3 * 32 bytes from start)
    # offset1 = 96 (3 * 32), offset2 = 96 + 32 + n*32, offset3 = offset2 + 32 + n*32
    offset1 = 96
    offset2 = offset1 + 32 + n * 32
    offset3 = offset2 + 32 + n * 32

    data =
      encode_uint256_hex(offset1) <>
      encode_uint256_hex(offset2) <>
      encode_uint256_hex(offset3) <>
      encode_uint256_array_hex(start_times) <>
      encode_uint256_array_hex(last_claim_times) <>
      encode_uint256_array_hex(total_claimeds)

    "0x" <> data
  end

  @doc """
  Build a mock getBatchNFTOwners response.

  Takes a list of address strings.
  Returns the "0x"-prefixed hex string as the RPC would.
  """
  def build_batch_nft_owners_response(addresses) do
    n = length(addresses)
    # Dynamic array: offset (32) + length (32) + elements (32 each)
    offset = encode_uint256_hex(32)
    length_hex = encode_uint256_hex(n)

    elements =
      Enum.map(addresses, fn addr ->
        hex = String.replace_prefix(addr, "0x", "") |> String.downcase()
        String.pad_leading(hex, 64, "0")
      end)
      |> Enum.join()

    "0x" <> offset <> length_hex <> elements
  end

  @doc """
  Build a fake NFT struct (map) mimicking what NFTStore returns.
  """
  def build_nft(overrides \\ %{}) do
    now = System.system_time(:second)

    defaults = %{
      token_id: :rand.uniform(2700),
      owner: random_address(),
      original_buyer: nil,
      hostess_index: :rand.uniform(8) - 1,
      hostess_name: "Test Hostess",
      mint_tx_hash: random_tx_hash(),
      mint_block_number: 1000,
      mint_price: "640000000000000000",
      affiliate: nil,
      affiliate2: nil,
      total_earned: "0",
      pending_amount: "0",
      last_24h_earned: "0",
      apy_basis_points: 0,
      time_start_time: nil,
      time_last_claim: nil,
      time_total_claimed: nil,
      created_at: now,
      updated_at: now
    }

    Map.merge(defaults, overrides)
  end

  @doc """
  Build a fake special NFT (time rewards enabled).
  """
  def build_special_nft(overrides \\ %{}) do
    now = System.system_time(:second)

    build_nft(Map.merge(%{
      token_id: 2340 + :rand.uniform(360),
      time_start_time: now - 86400,
      time_last_claim: now - 3600,
      time_total_claimed: "1000000000000000000"
    }, overrides))
  end

  @doc "Generate a random wallet address."
  def random_address do
    "0x" <> (:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower))
  end

  @doc "Generate a random transaction hash."
  def random_tx_hash do
    "0x" <> (:crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower))
  end

  # ===== Private Helpers =====

  defp encode_result_array(results) do
    n = length(results)

    # Result[]: offset to array (32) + length (32) + offsets to each result + result data
    array_offset = encode_uint256_hex(32)
    array_length = encode_uint256_hex(n)

    # Encode each Result struct
    encoded_results = Enum.map(results, fn {success, return_data} ->
      success_hex = encode_uint256_hex(if success, do: 1, else: 0)
      # Offset to bytes data = 64 (success slot + offset slot)
      data_offset_hex = encode_uint256_hex(64)
      data_length_hex = encode_uint256_hex(byte_size(return_data))
      data_hex = Base.encode16(return_data, case: :lower)

      # Pad to 32-byte boundary
      padding_needed = rem(32 - rem(byte_size(return_data), 32), 32)
      padding = if padding_needed == 32, do: "", else: String.duplicate("00", padding_needed)

      success_hex <> data_offset_hex <> data_length_hex <> data_hex <> padding
    end)

    # Compute offsets to each result (relative to start of results after length)
    {offsets, _} = Enum.reduce(encoded_results, {[], n * 32}, fn result_hex, {off_acc, current} ->
      result_bytes = div(String.length(result_hex), 2)
      {off_acc ++ [encode_uint256_hex(current)], current + result_bytes}
    end)

    offsets_hex = Enum.join(offsets)
    results_hex = Enum.join(encoded_results)

    "0x" <> array_offset <> array_length <> offsets_hex <> results_hex
  end

  defp encode_uint256_hex(int) do
    int
    |> :binary.encode_unsigned()
    |> String.pad_leading(32, <<0>>)
    |> Base.encode16(case: :lower)
  end

  defp encode_uint256_array_hex(ints) do
    length_hex = encode_uint256_hex(length(ints))
    elements = Enum.map(ints, &encode_uint256_hex/1) |> Enum.join()
    length_hex <> elements
  end
end
