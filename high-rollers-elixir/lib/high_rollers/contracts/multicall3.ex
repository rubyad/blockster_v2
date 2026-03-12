defmodule HighRollers.Contracts.Multicall3 do
  @moduledoc """
  Multicall3 helper for batching multiple eth_call requests into one.

  Used for Arbitrum only. Multicall3 is at canonical address:
  0xcA11bde05977b3631167028862bE2a173976CA11

  For Rogue Chain batching, use native batch functions on NFTRewarder instead.
  """

  require Logger

  @multicall3_address "0xcA11bde05977b3631167028862bE2a173976CA11"
  @default_batch_size 50
  @default_batch_delay_ms 200

  # aggregate3((address,bool,bytes)[]) selector (no 0x prefix - added when building data field)
  @aggregate3_selector "82ad56cb"

  @doc """
  Execute multiple calls via Multicall3.aggregate3().

  Takes a list of {target_address, calldata} tuples.
  All calls use allowFailure=true so one failure doesn't revert the batch.

  Returns {:ok, [{success, return_data}, ...]} or {:error, reason}.
  """
  def aggregate3(rpc_url, calls, opts \\ [])
  def aggregate3(_rpc_url, [], _opts), do: {:ok, []}

  def aggregate3(rpc_url, calls, opts) when is_list(calls) do
    encoded = @aggregate3_selector <> encode_call3_array(calls)
    timeout = Keyword.get(opts, :timeout, 30_000)

    case HighRollers.RPC.call(
      rpc_url,
      "eth_call",
      [%{to: @multicall3_address, data: "0x" <> encoded}, "latest"],
      timeout: timeout,
      max_retries: Keyword.get(opts, :max_retries, 3)
    ) do
      {:ok, result} ->
        {:ok, decode_result_array(result)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Execute calls in batches, returning all results in order.

  Splits `calls` into chunks of `batch_size` (default 50),
  executes each chunk as a single Multicall3 call, then
  concatenates results.

  Options:
    - batch_size: number of calls per Multicall3 invocation (default: 50)
    - batch_delay_ms: delay between batches for rate limiting (default: 200)
    - timeout: RPC timeout in ms (default: 30_000)
    - max_retries: max retry attempts (default: 3)
  """
  def aggregate3_batched(rpc_url, calls, opts \\ [])
  def aggregate3_batched(_rpc_url, [], _opts), do: {:ok, []}

  def aggregate3_batched(rpc_url, calls, opts) when is_list(calls) do
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)
    batch_delay_ms = Keyword.get(opts, :batch_delay_ms, @default_batch_delay_ms)

    calls
    |> Enum.chunk_every(batch_size)
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {batch, index}, {:ok, acc} ->
      # Delay between batches (not before the first one)
      if index > 0, do: Process.sleep(batch_delay_ms)

      case aggregate3(rpc_url, batch, opts) do
        {:ok, results} ->
          {:cont, {:ok, acc ++ results}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  # ===== ABI Encoding =====

  @doc """
  Encode a list of {target_address, calldata} tuples as a Call3[] array.

  Each Call3 struct: (address target, bool allowFailure, bytes callData)
  All calls use allowFailure=true.

  Returns hex string (no 0x prefix).
  """
  def encode_call3_array(calls) do
    # Dynamic array: offset to array data (32 bytes)
    # Array data: length (32 bytes) + offsets to each element + element data
    num_calls = length(calls)

    # Offset to array data = 32 (one slot for the array offset itself)
    array_offset = encode_uint256(32)

    # Array length
    array_length = encode_uint256(num_calls)

    # Encode each Call3 struct and compute offsets
    # Each struct is dynamic (contains bytes), so we need offsets
    encoded_structs = Enum.map(calls, fn {address, calldata} ->
      encode_call3_struct(address, calldata)
    end)

    # Compute offsets: first struct starts after all offset slots
    # Offset base = num_calls * 32 (bytes for the offset slots themselves)
    {offsets, _} = Enum.reduce(encoded_structs, {[], num_calls * 32}, fn struct_hex, {offsets_acc, current_offset} ->
      struct_bytes = div(String.length(struct_hex), 2)
      {offsets_acc ++ [encode_uint256(current_offset)], current_offset + struct_bytes}
    end)

    offset_hex = Enum.join(offsets)
    struct_data_hex = Enum.join(encoded_structs)

    array_offset <> array_length <> offset_hex <> struct_data_hex
  end

  defp encode_call3_struct(address, calldata) do
    # address (padded to 32 bytes)
    address_hex = pad_address(address)

    # allowFailure = true (1)
    allow_failure_hex = encode_uint256(1)

    # bytes callData: offset (32 bytes) + length (32 bytes) + data (padded to 32-byte boundary)
    # The offset is relative to the start of this struct = 96 (3 × 32: address + bool + offset)
    calldata_offset = encode_uint256(96)

    calldata_bytes = decode_hex(calldata)
    calldata_length = byte_size(calldata_bytes)
    calldata_length_hex = encode_uint256(calldata_length)

    # Pad calldata to 32-byte boundary
    padded_calldata = Base.encode16(calldata_bytes, case: :lower)
    padding_needed = rem(32 - rem(calldata_length, 32), 32)
    padding = if padding_needed == 32, do: "", else: String.duplicate("00", padding_needed)

    address_hex <> allow_failure_hex <> calldata_offset <> calldata_length_hex <> padded_calldata <> padding
  end

  # ===== ABI Decoding =====

  @doc """
  Decode Multicall3 Result[] response.

  Each Result = {bool success, bytes returnData}

  Returns list of {success_boolean, return_data_binary} tuples.
  """
  def decode_result_array("0x" <> hex) do
    data = Base.decode16!(hex, case: :mixed)

    # First 32 bytes: offset to array
    <<_array_offset::unsigned-256, rest::binary>> = data

    # Array length
    <<num_results::unsigned-256, rest2::binary>> = rest

    if num_results == 0 do
      []
    else
      # Read offsets to each Result struct
      {offsets, rest3} = read_uint256s(rest2, num_results)

      # Decode each Result struct at its offset
      # Offsets are relative to the start of the array data (after the length)
      # rest3 starts right after the offsets, but offsets are relative to after array length
      # The actual data blob = rest2 (offsets + struct data)
      Enum.map(offsets, fn offset ->
        # offset is relative to start of rest2
        # Subtract the offset slots size to get position in rest3
        struct_start = offset - num_results * 32

        <<_skip::binary-size(struct_start), struct_data::binary>> = rest3

        # Each Result: bool success (32 bytes) + offset to bytes (32 bytes)
        <<success_raw::unsigned-256, _data_offset::unsigned-256, data_length::unsigned-256, return_data::binary>> = struct_data

        actual_data = binary_part(return_data, 0, min(data_length, byte_size(return_data)))
        {success_raw != 0, actual_data}
      end)
    end
  end
  def decode_result_array(_), do: []

  # ===== Private Helpers =====

  defp encode_uint256(int) do
    int
    |> :binary.encode_unsigned()
    |> String.pad_leading(32, <<0>>)
    |> Base.encode16(case: :lower)
  end

  defp pad_address(address) do
    # Remove 0x prefix, left-pad to 64 hex chars (32 bytes)
    hex = String.replace_prefix(address, "0x", "") |> String.downcase()
    String.pad_leading(hex, 64, "0")
  end

  defp decode_hex("0x" <> hex), do: Base.decode16!(hex, case: :mixed)
  defp decode_hex(hex) when is_binary(hex), do: Base.decode16!(hex, case: :mixed)

  defp read_uint256s(data, count) do
    {values, rest} =
      Enum.reduce(1..count, {[], data}, fn _, {acc, <<val::unsigned-256, remaining::binary>>} ->
        {acc ++ [val], remaining}
      end)

    {values, rest}
  end
end
