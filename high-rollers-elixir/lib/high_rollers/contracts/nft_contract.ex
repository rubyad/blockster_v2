defmodule HighRollers.Contracts.NFTContract do
  @moduledoc """
  Ethereum RPC interactions with the High Rollers NFT contract on Arbitrum.

  Uses polling with eth_getLogs instead of WebSocket subscriptions because:
  1. Arbitrum RPC providers often drop WebSocket connections
  2. eth_getFilterChanges causes "filter not found" errors
  3. Polling is more reliable for long-running services

  Mirrors the Node.js eventListener.js approach:
  - pollNFTRequestedEvents(fromBlock, toBlock)
  - pollNFTMintedEvents(fromBlock, toBlock)
  - pollTransferEvents(fromBlock, toBlock)
  """

  @behaviour HighRollers.Contracts.NFTContractBehaviour

  require Logger

  @contract_address Application.compile_env(:high_rollers, :nft_contract_address)
  @rpc_url Application.compile_env(:high_rollers, :arbitrum_rpc_url)

  # Event topic signatures (keccak256 of event signature)
  # NFTRequested(uint256 requestId, address sender, uint256 currentPrice, uint256 tokenId)
  @nft_requested_topic "0x" <> (
    ExKeccak.hash_256("NFTRequested(uint256,address,uint256,uint256)")
    |> Base.encode16(case: :lower)
  )

  # NFTMinted(uint256 requestId, address recipient, uint256 currentPrice, uint256 tokenId, uint8 hostess, address affiliate, address affiliate2)
  @nft_minted_topic "0x" <> (
    ExKeccak.hash_256("NFTMinted(uint256,address,uint256,uint256,uint8,address,address)")
    |> Base.encode16(case: :lower)
  )

  # Transfer(address indexed from, address indexed to, uint256 indexed tokenId) - ERC721 standard
  @transfer_topic "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"

  # Zero address for mint detection
  @zero_address "0x0000000000000000000000000000000000000000"

  # ===== Block Number =====

  @doc "Get current block number from Arbitrum"
  def get_block_number do
    case rpc_call("eth_blockNumber", []) do
      {:ok, hex_block} ->
        {:ok, hex_to_int(hex_block)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ===== Event Queries =====

  @doc """
  Get NFTRequested events in block range.
  Called when a user initiates a mint (VRF request sent).

  Returns list of:
  %{
    request_id: integer,
    sender: address,
    price: wei_string,
    token_id: integer,
    tx_hash: string,
    block_number: integer
  }
  """
  def get_nft_requested_events(from_block, to_block) do
    params = %{
      address: @contract_address,
      topics: [@nft_requested_topic],
      fromBlock: int_to_hex(from_block),
      toBlock: int_to_hex(to_block)
    }

    case rpc_call("eth_getLogs", [params]) do
      {:ok, logs} ->
        events = Enum.map(logs, &decode_nft_requested_event/1)
        {:ok, events}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get NFTMinted events in block range.
  Called when VRF callback completes and NFT is minted.

  Returns list of:
  %{
    request_id: integer,
    recipient: address,
    price: wei_string,
    token_id: integer,
    hostess_index: integer (0-7),
    affiliate: address,
    affiliate2: address,
    tx_hash: string,
    block_number: integer
  }
  """
  def get_nft_minted_events(from_block, to_block) do
    params = %{
      address: @contract_address,
      topics: [@nft_minted_topic],
      fromBlock: int_to_hex(from_block),
      toBlock: int_to_hex(to_block)
    }

    case rpc_call("eth_getLogs", [params]) do
      {:ok, logs} ->
        events = Enum.map(logs, &decode_nft_minted_event/1)
        {:ok, events}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get Transfer events in block range.
  Used to track ownership changes after minting.

  Returns list of:
  %{
    from: address,
    to: address,
    token_id: integer,
    tx_hash: string,
    block_number: integer
  }
  """
  def get_transfer_events(from_block, to_block) do
    params = %{
      address: @contract_address,
      topics: [@transfer_topic],
      fromBlock: int_to_hex(from_block),
      toBlock: int_to_hex(to_block)
    }

    case rpc_call("eth_getLogs", [params]) do
      {:ok, logs} ->
        events = Enum.map(logs, &decode_transfer_event/1)
        {:ok, events}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ===== Contract View Functions =====

  @doc "Get total supply of NFTs"
  def get_total_supply do
    # totalSupply() selector: 0x18160ddd
    case rpc_call("eth_call", [%{to: @contract_address, data: "0x18160ddd"}, "latest"]) do
      {:ok, result} ->
        {:ok, hex_to_int(result)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Get owner of a token"
  def get_owner_of(token_id) do
    # ownerOf(uint256) selector: 0x6352211e
    data = "0x6352211e" <> encode_uint256(token_id)

    case rpc_call("eth_call", [%{to: @contract_address, data: data}, "latest"]) do
      {:ok, "0x"} ->
        {:error, :not_found}

      {:ok, result} ->
        {:ok, decode_address(result)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Get hostess index for a token"
  def get_hostess_index(token_id) do
    # s_tokenIdToHostess(uint256) - calculate selector
    selector = function_selector("s_tokenIdToHostess(uint256)")
    data = selector <> encode_uint256(token_id)

    case rpc_call("eth_call", [%{to: @contract_address, data: data}, "latest"]) do
      {:ok, result} ->
        {:ok, hex_to_int(result)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Get nonce for an address"
  def get_nonce(address) do
    case rpc_call("eth_getTransactionCount", [address, "latest"]) do
      {:ok, hex} -> {:ok, hex_to_int(hex)}
      {:error, reason} -> {:error, reason}
    end
  end

  # ===== Event Decoders =====

  defp decode_nft_requested_event(log) do
    # NFTRequested has no indexed params, all data in log["data"]
    # Layout: requestId (32 bytes) + sender (32 bytes padded) + price (32 bytes) + tokenId (32 bytes)
    data = log["data"] |> String.slice(2..-1//1) |> Base.decode16!(case: :mixed)

    <<
      request_id::unsigned-256,
      _padding::96, sender_bytes::binary-size(20),
      price::unsigned-256,
      token_id::unsigned-256
    >> = data

    %{
      request_id: request_id,
      sender: "0x" <> Base.encode16(sender_bytes, case: :lower),
      price: Integer.to_string(price),
      token_id: token_id,
      tx_hash: log["transactionHash"],
      block_number: hex_to_int(log["blockNumber"])
    }
  end

  defp decode_nft_minted_event(log) do
    # NFTMinted: all params in data (non-indexed)
    # Layout: requestId + recipient + price + tokenId + hostess + affiliate + affiliate2
    data = log["data"] |> String.slice(2..-1//1) |> Base.decode16!(case: :mixed)

    <<
      request_id::unsigned-256,
      _pad1::96, recipient_bytes::binary-size(20),
      price::unsigned-256,
      token_id::unsigned-256,
      _pad2::248, hostess::unsigned-8,
      _pad3::96, affiliate_bytes::binary-size(20),
      _pad4::96, affiliate2_bytes::binary-size(20)
    >> = data

    %{
      request_id: request_id,
      recipient: "0x" <> Base.encode16(recipient_bytes, case: :lower),
      price: Integer.to_string(price),
      token_id: token_id,
      hostess_index: hostess,
      affiliate: "0x" <> Base.encode16(affiliate_bytes, case: :lower),
      affiliate2: "0x" <> Base.encode16(affiliate2_bytes, case: :lower),
      tx_hash: log["transactionHash"],
      block_number: hex_to_int(log["blockNumber"])
    }
  end

  defp decode_transfer_event(log) do
    # Transfer: from (indexed), to (indexed), tokenId (indexed)
    # Indexed params are in topics[1], topics[2], topics[3]
    [_event_sig, from_topic, to_topic, token_id_topic] = log["topics"]

    %{
      from: decode_address(from_topic),
      to: decode_address(to_topic),
      token_id: hex_to_int(token_id_topic),
      tx_hash: log["transactionHash"],
      block_number: hex_to_int(log["blockNumber"])
    }
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
  defp hex_to_int(hex) when is_binary(hex), do: String.to_integer(hex, 16)

  defp int_to_hex(int), do: "0x" <> Integer.to_string(int, 16)

  defp encode_uint256(int) do
    int
    |> :binary.encode_unsigned()
    |> String.pad_leading(32, <<0>>)
    |> Base.encode16(case: :lower)
  end

  defp decode_address("0x" <> hex) do
    # Address is last 20 bytes of 32-byte value (last 40 hex chars)
    "0x" <> String.downcase(String.slice(hex, -40, 40))
  end

  defp function_selector(signature) do
    "0x" <> (
      ExKeccak.hash_256(signature)
      |> binary_part(0, 4)
      |> Base.encode16(case: :lower)
    )
  end

  # Expose zero address for mint detection
  def zero_address, do: @zero_address
end
