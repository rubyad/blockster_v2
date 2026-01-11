defmodule HighRollers.Contracts.NFTRewarder do
  @moduledoc """
  Ethereum RPC interactions with the NFTRewarder contract on Rogue Chain.

  Handles:
  - Event queries (RewardReceived, RewardClaimed)
  - View function calls (getBatchNFTEarnings, totalRewardsReceived)
  - Admin write operations (via AdminTxQueue)
  """

  @behaviour HighRollers.Contracts.NFTRewarderBehaviour

  require Logger

  @contract_address Application.compile_env(:high_rollers, :nft_rewarder_address)
  @rpc_url Application.compile_env(:high_rollers, :rogue_rpc_url)

  # Event topics
  @reward_received_topic "0x" <> (
    ExKeccak.hash_256("RewardReceived(bytes32,uint256,uint256)")
    |> Base.encode16(case: :lower)
  )

  @reward_claimed_topic "0x" <> (
    ExKeccak.hash_256("RewardClaimed(address,uint256,uint256[])")
    |> Base.encode16(case: :lower)
  )

  # ===== Block Number =====

  @doc "Get current block number from Rogue Chain"
  def get_block_number do
    case rpc_call("eth_blockNumber", []) do
      {:ok, hex} -> {:ok, hex_to_int(hex)}
      {:error, reason} -> {:error, reason}
    end
  end

  # ===== Event Queries =====

  @doc """
  Get RewardReceived events (when ROGUEBankroll sends rewards after losing bets)

  Returns list of:
  %{
    bet_id: bytes32_hex,
    amount: wei_string,
    timestamp: integer,
    block_number: integer,
    tx_hash: string
  }
  """
  def get_reward_received_events(from_block, to_block) do
    params = %{
      address: @contract_address,
      topics: [@reward_received_topic],
      fromBlock: int_to_hex(from_block),
      toBlock: int_to_hex(to_block)
    }

    case rpc_call("eth_getLogs", [params]) do
      {:ok, logs} ->
        events = Enum.map(logs, fn log ->
          # RewardReceived(bytes32 indexed betId, uint256 amount, uint256 timestamp)
          # betId is indexed (topics[1]), amount and timestamp in data
          [_sig, bet_id_topic] = log["topics"]
          data = log["data"] |> String.slice(2..-1//1) |> Base.decode16!(case: :mixed)
          <<amount::unsigned-256, timestamp::unsigned-256>> = data

          %{
            bet_id: bet_id_topic,
            amount: Integer.to_string(amount),
            timestamp: timestamp,
            block_number: hex_to_int(log["blockNumber"]),
            tx_hash: log["transactionHash"]
          }
        end)
        {:ok, events}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get RewardClaimed events (when users withdraw pending rewards)

  Returns list of:
  %{
    user: address,
    amount: wei_string,
    token_ids: [integer],
    tx_hash: string
  }
  """
  def get_reward_claimed_events(from_block, to_block) do
    params = %{
      address: @contract_address,
      topics: [@reward_claimed_topic],
      fromBlock: int_to_hex(from_block),
      toBlock: int_to_hex(to_block)
    }

    case rpc_call("eth_getLogs", [params]) do
      {:ok, logs} ->
        events = Enum.map(logs, fn log ->
          # RewardClaimed(address indexed user, uint256 amount, uint256[] tokenIds)
          # user is indexed (topics[1]), amount and tokenIds in data
          [_sig, user_topic] = log["topics"]

          # Decode dynamic array from data
          data = log["data"] |> String.slice(2..-1//1) |> Base.decode16!(case: :mixed)
          <<amount::unsigned-256, _offset::unsigned-256, array_length::unsigned-256, rest::binary>> = data

          token_ids =
            for i <- 0..(array_length - 1) do
              <<token_id::unsigned-256>> = binary_part(rest, i * 32, 32)
              token_id
            end

          %{
            user: decode_address(user_topic),
            amount: Integer.to_string(amount),
            token_ids: token_ids,
            tx_hash: log["transactionHash"]
          }
        end)
        {:ok, events}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ===== View Functions =====

  @doc """
  Batch query NFT earnings from contract.
  Used by EarningsSyncer to efficiently fetch earnings for many NFTs at once.

  Returns list of maps with:
  %{
    token_id: integer,
    total_earned: string (wei),
    pending_amount: string (wei),
    hostess_index: integer
  }
  """
  def get_batch_nft_earnings(token_ids) when is_list(token_ids) do
    # getBatchNFTEarnings(uint256[]) returns (uint256[], uint256[], uint8[])
    selector = function_selector("getBatchNFTEarnings(uint256[])")

    # Encode dynamic array
    array_data = encode_uint256_array(token_ids)
    data = selector <> array_data

    case rpc_call("eth_call", [%{to: @contract_address, data: data}, "latest"]) do
      {:ok, result} ->
        # Decode three dynamic arrays
        decoded = decode_triple_array(result)

        # Combine with token_ids into list of maps
        earnings_list =
          token_ids
          |> Enum.with_index()
          |> Enum.map(fn {token_id, i} ->
            %{
              token_id: token_id,
              total_earned: Integer.to_string(Enum.at(decoded.total_earned, i, 0)),
              pending_amount: Integer.to_string(Enum.at(decoded.pending_amounts, i, 0)),
              hostess_index: Enum.at(decoded.hostess_indices, i, 0)
            }
          end)

        {:ok, earnings_list}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Get global totals from contract"
  def get_global_totals do
    received_selector = function_selector("totalRewardsReceived()")
    distributed_selector = function_selector("totalRewardsDistributed()")

    with {:ok, received_hex} <- rpc_call("eth_call", [%{to: @contract_address, data: received_selector}, "latest"]),
         {:ok, distributed_hex} <- rpc_call("eth_call", [%{to: @contract_address, data: distributed_selector}, "latest"]) do
      {:ok, %{
        total_received: hex_to_int(received_hex),
        total_distributed: hex_to_int(distributed_hex)
      }}
    end
  end

  @doc """
  Get raw time reward info struct from contract's public mapping.

  Returns the authoritative lastClaimTime which is NOT in getTimeRewardInfo().

  Contract returns (from public timeRewardInfo mapping):
  - startTime: uint256 - Unix timestamp when time rewards started
  - lastClaimTime: uint256 - Unix timestamp when rewards were last claimed
  - totalClaimed: uint256 - Total claimed time rewards so far (wei)

  Returns:
  %{
    start_time: integer,
    last_claim_time: integer,
    total_claimed: integer
  }
  """
  def get_time_reward_raw(token_id) do
    # timeRewardInfo(uint256) returns (uint256 startTime, uint256 lastClaimTime, uint256 totalClaimed)
    selector = function_selector("timeRewardInfo(uint256)")
    token_id_hex = token_id |> Integer.to_string(16) |> String.pad_leading(64, "0")
    data = selector <> token_id_hex

    case rpc_call("eth_call", [%{to: @contract_address, data: data}, "latest"]) do
      {:ok, result} ->
        hex = String.slice(result, 2..-1//1)
        <<start_time::unsigned-256,
          last_claim_time::unsigned-256,
          total_claimed::unsigned-256>> =
          Base.decode16!(hex, case: :mixed)

        {:ok, %{
          start_time: start_time,
          last_claim_time: last_claim_time,
          total_claimed: total_claimed
        }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get time reward info for a special NFT.

  Returns the authoritative data from the contract, used by
  EarningsSyncer as a backup sync mechanism to correct any missed events.

  Contract returns (NFTRewarder V4+):
  - startTime: uint256 - Unix timestamp when time rewards started
  - endTime: uint256 - Unix timestamp when time rewards end (180 days from start)
  - pending: uint256 - Current pending time rewards (wei)
  - claimed: uint256 - Total claimed time rewards so far (wei)
  - ratePerSecond: uint256 - Wei earned per second
  - timeRemaining: uint256 - Seconds until rewards end
  - totalFor180Days: uint256 - Total allocation for 180-day period (wei)
  - isActive: bool - Whether time rewards are currently active

  Returns:
  %{
    start_time: integer,
    end_time: integer,
    pending: integer,
    claimed: integer,
    rate_per_second: integer,
    time_remaining: integer,
    total_for_180_days: integer,
    is_active: boolean
  }
  """
  def get_time_reward_info(token_id) do
    # getTimeRewardInfo(uint256) returns (uint256 startTime, uint256 endTime, uint256 pending, uint256 claimed, uint256 ratePerSecond, uint256 timeRemaining, uint256 totalFor180Days, bool isActive)
    selector = function_selector("getTimeRewardInfo(uint256)")
    token_id_hex = token_id |> Integer.to_string(16) |> String.pad_leading(64, "0")
    data = selector <> token_id_hex

    case rpc_call("eth_call", [%{to: @contract_address, data: data}, "latest"]) do
      {:ok, result} ->
        # Decode 7 uint256 values + 1 bool (256 bytes total after 0x)
        hex = String.slice(result, 2..-1//1)
        <<start_time::unsigned-256,
          end_time::unsigned-256,
          pending::unsigned-256,
          claimed::unsigned-256,
          rate_per_second::unsigned-256,
          time_remaining::unsigned-256,
          total_for_180_days::unsigned-256,
          is_active_raw::unsigned-256>> =
          Base.decode16!(hex, case: :mixed)

        {:ok, %{
          start_time: start_time,
          end_time: end_time,
          pending: pending,
          claimed: claimed,
          rate_per_second: rate_per_second,
          time_remaining: time_remaining,
          total_for_180_days: total_for_180_days,
          is_active: is_active_raw != 0
        }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Get nonce for admin wallet"
  def get_nonce(address) do
    case rpc_call("eth_getTransactionCount", [address, "latest"]) do
      {:ok, hex} -> {:ok, hex_to_int(hex)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Wait for transaction receipt with polling"
  def wait_for_receipt(tx_hash, timeout_ms \\ 60_000) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    poll_for_receipt(tx_hash, deadline)
  end

  defp poll_for_receipt(tx_hash, deadline) do
    if System.monotonic_time(:millisecond) > deadline do
      {:error, :timeout}
    else
      case rpc_call("eth_getTransactionReceipt", [tx_hash]) do
        {:ok, nil} ->
          Process.sleep(1000)
          poll_for_receipt(tx_hash, deadline)

        {:ok, receipt} ->
          {:ok, %{
            tx_hash: receipt["transactionHash"],
            block_number: hex_to_int(receipt["blockNumber"]),
            status: if(receipt["status"] == "0x1", do: :success, else: :failed)
          }}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Get single NFT owner from contract.
  Queries the nftMetadata public mapping which returns (uint8 hostessIndex, bool registered, address owner).
  """
  def get_nft_owner(token_id) do
    # nftMetadata(uint256) returns (uint8 hostessIndex, bool registered, address owner)
    selector = function_selector("nftMetadata(uint256)")
    token_id_hex = token_id |> Integer.to_string(16) |> String.pad_leading(64, "0")
    data = selector <> token_id_hex

    case rpc_call("eth_call", [%{to: @contract_address, data: data}, "latest"]) do
      {:ok, "0x" <> hex} ->
        # Decode struct: uint8 (32 bytes) + bool (32 bytes) + address (32 bytes) = 96 bytes
        case Base.decode16(hex, case: :mixed) do
          {:ok, <<_hostess_index::unsigned-256, _registered::unsigned-256, owner_padded::unsigned-256>>} ->
            # Address is in the last 32 bytes, take last 20 bytes (40 hex chars)
            owner_hex = owner_padded |> Integer.to_string(16) |> String.pad_leading(40, "0")
            {:ok, "0x" <> String.downcase(owner_hex)}

          _ ->
            {:error, :decode_failed}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ===== Admin Write Operations =====

  @doc "Send a signed transaction (called by AdminTxQueue)"
  def send_raw_transaction(signed_tx_hex) do
    rpc_call("eth_sendRawTransaction", [signed_tx_hex])
  end

  # ===== Helpers =====

  defp rpc_call(method, params) do
    HighRollers.RPC.call(
      @rpc_url,
      method,
      params,
      timeout: 30_000,
      max_retries: 3
    )
  end

  defp hex_to_int("0x" <> hex), do: String.to_integer(hex, 16)
  defp hex_to_int("0x"), do: 0

  defp int_to_hex(int), do: "0x" <> Integer.to_string(int, 16)

  defp decode_address("0x" <> hex) do
    "0x" <> String.downcase(String.slice(hex, -40, 40))
  end

  defp function_selector(signature) do
    "0x" <> (
      ExKeccak.hash_256(signature)
      |> binary_part(0, 4)
      |> Base.encode16(case: :lower)
    )
  end

  defp encode_uint256_array(ints) do
    # ABI encode dynamic array: offset (32) + length (32) + elements (32 each)
    offset = String.duplicate("0", 62) <> "20"  # 0x20 = 32 (offset to array data)
    length = ints |> length() |> encode_uint256_raw()
    elements = Enum.map(ints, &encode_uint256_raw/1) |> Enum.join()
    offset <> length <> elements
  end

  defp encode_uint256_raw(int) do
    int
    |> :binary.encode_unsigned()
    |> String.pad_leading(32, <<0>>)
    |> Base.encode16(case: :lower)
  end

  defp decode_triple_array("0x" <> hex) do
    # Returns three dynamic arrays from getBatchNFTEarnings
    data = Base.decode16!(hex, case: :mixed)

    # First 96 bytes are offsets to each array
    <<offset1::unsigned-256, offset2::unsigned-256, offset3::unsigned-256, rest::binary>> = data

    # Each offset points to: length (32 bytes) + elements
    total_earned = decode_array_at_offset(rest, offset1 - 96)
    pending_amounts = decode_array_at_offset(rest, offset2 - 96)
    hostess_indices = decode_array_at_offset(rest, offset3 - 96)

    %{
      total_earned: total_earned,
      pending_amounts: pending_amounts,
      hostess_indices: hostess_indices
    }
  end

  defp decode_array_at_offset(data, offset) do
    <<_skip::binary-size(offset), length::unsigned-256, rest::binary>> = data

    for i <- 0..(length - 1) do
      <<value::unsigned-256>> = binary_part(rest, i * 32, 32)
      value
    end
  end

  defp decode_address_array("0x" <> hex) do
    # Dynamic array: first 32 bytes is offset, then length, then elements
    data = Base.decode16!(hex, case: :mixed)

    case data do
      <<_offset::unsigned-256, length::unsigned-256, rest::binary>> ->
        for i <- 0..(length - 1) do
          # Each address is padded to 32 bytes, take last 20 bytes
          <<_padding::binary-size(12), addr_bytes::binary-size(20)>> = binary_part(rest, i * 32, 32)
          "0x" <> Base.encode16(addr_bytes, case: :lower)
        end

      _ ->
        []
    end
  end
end
