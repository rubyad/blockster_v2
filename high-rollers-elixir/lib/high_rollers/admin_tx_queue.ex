defmodule HighRollers.AdminTxQueue do
  @moduledoc """
  Serialized transaction queue for NFTRewarder admin operations.

  All admin wallet transactions (registerNFT, updateOwnership, withdrawTo)
  must go through this queue to prevent nonce conflicts. The queue processes
  transactions sequentially, waiting for each to confirm before the next.

  PERSISTENCE: Operations are written to hr_admin_ops before execution.
  If the server crashes, pending ops are retried on startup.

  RETRY: Failed operations retry with exponential backoff. After max retries,
  they're moved to dead letter status for manual review.

  Uses GlobalSingleton for cluster-wide single instance.
  """
  use GenServer
  require Logger

  @tx_delay_ms 100           # Delay between transactions
  @max_retries 3             # Max retry attempts
  @initial_backoff_ms 1_000  # Initial backoff (doubles each retry)
  @process_interval_ms 5_000 # Check for pending ops every 5 seconds

  # Unified admin ops table with status field
  @pending_table :hr_admin_ops

  # Contract addresses
  @nft_rewarder_address Application.compile_env(:high_rollers, :nft_rewarder_address)
  @nft_contract_address Application.compile_env(:high_rollers, :nft_contract_address)

  # Chain IDs
  @rogue_chain_id Application.compile_env(:high_rollers, :rogue_chain_id, 560013)
  @arbitrum_chain_id Application.compile_env(:high_rollers, :arbitrum_chain_id, 42161)

  # ===== Client API =====

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Enqueue NFT registration (called from ArbitrumEventPoller on mint).
  Returns immediately - operation processed in background.
  """
  def enqueue_register_nft(token_id, hostess_index, owner) do
    op_id = create_pending_op(:register_nft, token_id, %{
      hostess_index: hostess_index,
      owner: owner
    })
    # Trigger immediate processing
    GenServer.cast(__MODULE__, :process_pending)
    {:ok, op_id}
  end

  @doc """
  Enqueue ownership update (called from ArbitrumEventPoller on transfer).
  Returns immediately - operation processed in background.
  """
  def enqueue_update_ownership(token_id, new_owner) do
    op_id = create_pending_op(:update_ownership, token_id, %{
      new_owner: new_owner
    })
    # Trigger immediate processing
    GenServer.cast(__MODULE__, :process_pending)
    {:ok, op_id}
  end

  @doc """
  Enqueue affiliate linking (called from AffiliateController when wallet connects).
  Calls linkAffiliate(buyer, affiliate) on the Arbitrum NFT contract.
  Returns immediately - operation processed in background.
  """
  def enqueue_link_affiliate(buyer, affiliate) do
    # Use buyer address as the key for deduplication
    op_id = create_pending_op(:link_affiliate, buyer, %{
      buyer: String.downcase(buyer),
      affiliate: String.downcase(affiliate)
    })
    # Trigger immediate processing
    GenServer.cast(__MODULE__, :process_pending)
    {:ok, op_id}
  end

  @doc """
  Execute withdrawal immediately (user-initiated, needs synchronous response).
  Returns {:ok, receipt} or {:error, reason}.
  """
  def withdraw_to(token_ids, recipient) do
    GenServer.call(__MODULE__, {:withdraw_to, token_ids, recipient}, 120_000)
  end

  @doc """
  Execute time reward claim immediately (user-initiated, needs synchronous response).
  Returns {:ok, receipt} or {:error, reason}.
  """
  def claim_time_rewards(token_ids, recipient) do
    GenServer.call(__MODULE__, {:claim_time_rewards, token_ids, recipient}, 120_000)
  end

  @doc "Get count of pending operations"
  def pending_count do
    :mnesia.dirty_index_read(@pending_table, :pending, :status) |> length()
  end

  @doc "Get count of dead letter operations"
  def dead_letter_count do
    :mnesia.dirty_index_read(@pending_table, :dead_letter, :status) |> length()
  end

  @doc "Get all dead letter operations for manual review"
  def get_dead_letters do
    :mnesia.dirty_index_read(@pending_table, :dead_letter, :status)
    |> Enum.map(&op_to_map/1)
  end

  @doc "Retry a dead letter operation by resetting its status to pending"
  def retry_dead_letter({token_id, operation}) do
    key = {token_id, operation}
    case :mnesia.dirty_read({@pending_table, key}) do
      [record] ->
        if elem(record, 3) == :dead_letter do
          now = System.system_time(:second)
          # Reset status to pending, attempts to 0
          updated = record
          |> put_elem(3, :pending)  # status
          |> put_elem(4, 0)         # attempts
          |> put_elem(7, now)       # updated_at
          :mnesia.dirty_write(updated)
          GenServer.cast(__MODULE__, :process_pending)
          :ok
        else
          {:error, :not_dead_letter}
        end
      [] ->
        {:error, :not_found}
    end
  end

  # ===== Server Callbacks =====

  @impl true
  def init(_opts) do
    case init_wallet() do
      {:ok, wallet_state} ->
        Logger.info("[AdminTxQueue] Initialized:")
        Logger.info("  Rogue Chain wallet: #{wallet_state.wallet_address}, nonce: #{wallet_state.nonce}")
        if wallet_state.affiliate_linker_address do
          Logger.info("  Arbitrum wallet: #{wallet_state.affiliate_linker_address}, nonce: #{wallet_state.arbitrum_nonce}")
        end

        # Schedule periodic processing of pending ops
        schedule_process_pending()

        # Process any pending ops from before restart
        pending_count = :mnesia.dirty_index_read(@pending_table, :pending, :status) |> length()
        if pending_count > 0 do
          Logger.info("[AdminTxQueue] Found #{pending_count} pending ops from previous run")
          send(self(), :process_pending)
        end

        {:ok, Map.put(wallet_state, :processing, false)}

      {:error, reason} ->
        Logger.error("[AdminTxQueue] Failed to initialize: #{inspect(reason)}")
        # Return a disabled state instead of stopping - allows app to start without private keys
        {:ok, %{disabled: true, processing: false}}
    end
  end

  @impl true
  def handle_cast(:process_pending, %{disabled: true} = state) do
    {:noreply, state}
  end

  @impl true
  def handle_cast(:process_pending, %{processing: true} = state) do
    # Already processing, skip
    {:noreply, state}
  end

  @impl true
  def handle_cast(:process_pending, state) do
    new_state = process_all_pending(%{state | processing: true})
    {:noreply, %{new_state | processing: false}}
  end

  @impl true
  def handle_info(:process_pending, %{disabled: true} = state) do
    schedule_process_pending()
    {:noreply, state}
  end

  @impl true
  def handle_info(:process_pending, state) do
    if not state.processing do
      new_state = process_all_pending(%{state | processing: true})
      schedule_process_pending()
      {:noreply, %{new_state | processing: false}}
    else
      schedule_process_pending()
      {:noreply, state}
    end
  end

  @impl true
  def handle_call({:withdraw_to, _token_ids, _recipient}, _from, %{disabled: true} = state) do
    {:reply, {:error, :admin_wallet_not_configured}, state}
  end

  @impl true
  def handle_call({:withdraw_to, token_ids, recipient}, _from, state) do
    Logger.info("[AdminTxQueue] withdrawTo: #{length(token_ids)} NFTs to #{recipient}")
    gas_limit = 500_000 + length(token_ids) * 50_000

    case execute_withdraw_to(state, token_ids, recipient, gas_limit) do
      {:ok, receipt, new_state} ->
        {:reply, {:ok, receipt}, new_state}
      {:error, reason, new_state} ->
        {:reply, {:error, reason}, new_state}
    end
  end

  @impl true
  def handle_call({:claim_time_rewards, _token_ids, _recipient}, _from, %{disabled: true} = state) do
    {:reply, {:error, :admin_wallet_not_configured}, state}
  end

  @impl true
  def handle_call({:claim_time_rewards, token_ids, recipient}, _from, state) do
    Logger.info("[AdminTxQueue] claimTimeRewards: #{length(token_ids)} special NFTs to #{recipient}")
    gas_limit = 600_000 + length(token_ids) * 60_000

    case execute_claim_time_rewards(state, token_ids, recipient, gas_limit) do
      {:ok, receipt, new_state} ->
        {:reply, {:ok, receipt}, new_state}
      {:error, reason, new_state} ->
        {:reply, {:error, reason}, new_state}
    end
  end

  # ===== Private Functions =====

  defp schedule_process_pending do
    Process.send_after(self(), :process_pending, @process_interval_ms)
  end

  defp create_pending_op(operation, token_id, args) do
    now = System.system_time(:second)
    key = {token_id, operation}

    # Record layout for hr_admin_ops (8 fields total)
    record = {@pending_table, key, args, :pending, 0, nil, now, now}
    :mnesia.dirty_write(record)

    Logger.info("[AdminTxQueue] Created pending op: #{operation} for #{inspect(token_id)}")
    key
  end

  defp process_all_pending(state) do
    pending_ops = :mnesia.dirty_index_read(@pending_table, :pending, :status)
    |> Enum.sort_by(fn record -> elem(record, 6) end)  # Sort by created_at

    Enum.reduce(pending_ops, state, fn op_record, acc_state ->
      process_single_op(op_record, acc_state)
    end)
  end

  defp process_single_op(op_record, state) do
    # Record layout: {table, key, args, status, attempts, last_error, created_at, updated_at}
    {_table, {token_id, operation}, args, _status, attempts, _last_error, created_at, _updated_at} = op_record

    # Mark as processing
    now = System.system_time(:second)
    updated = put_elem(op_record, 3, :processing) |> put_elem(7, now)
    :mnesia.dirty_write(updated)

    Logger.info("[AdminTxQueue] Processing #{operation} for #{inspect(token_id)} (attempt #{attempts + 1})")

    # Execute the operation with telemetry
    start_time = System.monotonic_time()
    result = case operation do
      :register_nft ->
        execute_register_nft(state, token_id, args.hostess_index, args.owner)
      :update_ownership ->
        execute_update_ownership(state, token_id, args.new_owner)
      :link_affiliate ->
        execute_link_affiliate(state, args.buyer, args.affiliate)
    end
    duration = System.monotonic_time() - start_time

    key = {token_id, operation}

    case result do
      {:ok, receipt, new_state} ->
        # Emit success telemetry
        :telemetry.execute(
          [:high_rollers, :admin_tx, :send],
          %{duration: duration},
          %{action: operation, result: :success, tx_hash: receipt.tx_hash}
        )

        # Success - delete from pending
        :mnesia.dirty_delete({@pending_table, key})
        Logger.info("[AdminTxQueue] #{operation} for #{inspect(token_id)} succeeded")
        new_state

      {:error, reason, new_state} ->
        # Emit failure telemetry
        :telemetry.execute(
          [:high_rollers, :admin_tx, :send],
          %{duration: duration},
          %{action: operation, result: :error, tx_hash: nil}
        )

        new_attempts = attempts + 1

        if new_attempts >= @max_retries do
          # Move to dead letter status
          move_to_dead_letter(op_record, new_attempts, inspect(reason))
          Logger.error("[AdminTxQueue] #{operation} for #{inspect(token_id)} failed after #{new_attempts} attempts: #{inspect(reason)}")
        else
          # Update attempts and schedule retry with backoff
          backoff = trunc(@initial_backoff_ms * :math.pow(2, new_attempts - 1))
          updated = {@pending_table, key, args, :pending, new_attempts, inspect(reason), created_at, now}
          :mnesia.dirty_write(updated)
          Logger.warning("[AdminTxQueue] #{operation} for #{inspect(token_id)} failed (attempt #{new_attempts}): #{inspect(reason)}, will retry in #{backoff}ms")
          Process.sleep(backoff)
        end

        new_state
    end
  end

  defp move_to_dead_letter(op_record, attempts, last_error) do
    {_table, key, args, _status, _attempts, _last_error, created_at, _updated_at} = op_record
    now = System.system_time(:second)

    # Update status to :dead_letter
    dead_letter = {@pending_table, key, args, :dead_letter, attempts, last_error, created_at, now}
    :mnesia.dirty_write(dead_letter)
  end

  defp init_wallet do
    admin_key = Application.get_env(:high_rollers, :admin_private_key)

    if is_nil(admin_key) or admin_key == "" do
      {:error, :admin_private_key_not_configured}
    else
      # Initialize admin wallet
      wallet_address = derive_address_from_private_key(admin_key)
      {:ok, rogue_nonce} = HighRollers.Contracts.NFTRewarder.get_nonce(wallet_address)

      # Initialize affiliate linker wallet (optional)
      affiliate_linker_key = Application.get_env(:high_rollers, :affiliate_linker_private_key)

      {affiliate_linker_address, affiliate_linker_key_final, arbitrum_nonce} =
        if is_nil(affiliate_linker_key) or affiliate_linker_key == "" do
          Logger.warning("[AdminTxQueue] affiliate_linker_private_key not configured, using admin wallet for Arbitrum ops")
          {:ok, arb_nonce} = HighRollers.Contracts.NFTContract.get_nonce(wallet_address)
          {wallet_address, admin_key, arb_nonce}
        else
          linker_address = derive_address_from_private_key(affiliate_linker_key)
          {:ok, arb_nonce} = HighRollers.Contracts.NFTContract.get_nonce(linker_address)
          {linker_address, affiliate_linker_key, arb_nonce}
        end

      {:ok, %{
        admin_private_key: admin_key,
        wallet_address: wallet_address,
        nonce: rogue_nonce,
        affiliate_linker_private_key: affiliate_linker_key_final,
        affiliate_linker_address: affiliate_linker_address,
        arbitrum_nonce: arbitrum_nonce
      }}
    end
  end

  # ===== Transaction Execution =====

  defp execute_register_nft(state, token_id, hostess_index, owner) do
    # registerNFT(uint256 tokenId, uint8 hostessIndex, address owner)
    # Function selector: keccak256("registerNFT(uint256,uint8,address)")[:4]
    selector = function_selector("registerNFT(uint256,uint8,address)")
    data = selector <> encode_uint256(token_id) <> encode_uint8(hostess_index) <> encode_address(owner)

    execute_rogue_tx(state, data, 200_000)
  end

  defp execute_update_ownership(state, token_id, new_owner) do
    # updateOwnership(uint256 tokenId, address newOwner)
    selector = function_selector("updateOwnership(uint256,address)")
    data = selector <> encode_uint256(token_id) <> encode_address(new_owner)

    execute_rogue_tx(state, data, 150_000)
  end

  defp execute_withdraw_to(state, token_ids, recipient, gas_limit) do
    # withdrawTo(uint256[] tokenIds, address recipient)
    selector = function_selector("withdrawTo(uint256[],address)")
    data = selector <> encode_dynamic_array_and_address(token_ids, recipient)

    execute_rogue_tx(state, data, gas_limit)
  end

  defp execute_claim_time_rewards(state, token_ids, recipient, gas_limit) do
    # claimTimeRewards(uint256[] tokenIds, address recipient)
    selector = function_selector("claimTimeRewards(uint256[],address)")
    data = selector <> encode_dynamic_array_and_address(token_ids, recipient)

    execute_rogue_tx(state, data, gas_limit)
  end

  defp execute_link_affiliate(state, buyer, affiliate) do
    # linkAffiliate(address buyer, address affiliate)
    selector = function_selector("linkAffiliate(address,address)")
    data = selector <> encode_address(buyer) <> encode_address(affiliate)

    # Gas limit set to 1M - linkAffiliate adds to multiple arrays which can use significant gas
    case execute_arbitrum_tx(state, data, 1_000_000) do
      {:ok, receipt, new_state} ->
        # Mark user as linked on-chain
        HighRollers.Users.mark_linked_on_chain(buyer)
        {:ok, receipt, new_state}

      error ->
        error
    end
  end

  defp execute_rogue_tx(state, data, gas_limit, retry_count \\ 0) do
    case sign_and_send_tx(
      state.admin_private_key,
      @nft_rewarder_address,
      data,
      state.nonce,
      @rogue_chain_id,
      gas_limit,
      :rogue
    ) do
      {:ok, tx_hash} ->
        new_state = %{state | nonce: state.nonce + 1}
        case wait_for_receipt_rogue(tx_hash) do
          {:ok, receipt} ->
            Process.sleep(@tx_delay_ms)
            {:ok, receipt, new_state}
          {:error, reason} ->
            {:error, reason, new_state}
        end

      {:error, reason} ->
        # Check if nonce error and auto-retry once
        is_nonce_error = is_binary(reason) && String.contains?(reason, "nonce too low")
        if is_nonce_error && retry_count < 1 do
          Logger.warning("[AdminTxQueue] Nonce too low on Rogue, refreshing and retrying...")
          {:ok, fresh_nonce} = HighRollers.Contracts.NFTRewarder.get_nonce(state.wallet_address)
          new_state = %{state | nonce: fresh_nonce}
          execute_rogue_tx(new_state, data, gas_limit, retry_count + 1)
        else
          # Refresh nonce on error but don't retry
          {:ok, fresh_nonce} = HighRollers.Contracts.NFTRewarder.get_nonce(state.wallet_address)
          new_state = %{state | nonce: fresh_nonce}
          {:error, reason, new_state}
        end
    end
  end

  defp execute_arbitrum_tx(state, data, gas_limit, retry_count \\ 0) do
    case sign_and_send_tx(
      state.affiliate_linker_private_key,
      @nft_contract_address,
      data,
      state.arbitrum_nonce,
      @arbitrum_chain_id,
      gas_limit,
      :arbitrum
    ) do
      {:ok, tx_hash} ->
        new_state = %{state | arbitrum_nonce: state.arbitrum_nonce + 1}
        case wait_for_receipt_arbitrum(tx_hash) do
          {:ok, %{status: :success} = receipt} ->
            Process.sleep(@tx_delay_ms)
            {:ok, receipt, new_state}
          {:ok, %{status: :failed, tx_hash: failed_tx}} ->
            {:error, {:tx_reverted, failed_tx}, new_state}
          {:error, reason} ->
            {:error, reason, new_state}
        end

      {:error, reason} ->
        # Check if nonce error and auto-retry once
        is_nonce_error = is_binary(reason) && String.contains?(reason, "nonce too low")
        if is_nonce_error && retry_count < 1 do
          Logger.warning("[AdminTxQueue] Nonce too low on Arbitrum, refreshing and retrying...")
          {:ok, fresh_nonce} = HighRollers.Contracts.NFTContract.get_nonce(state.affiliate_linker_address)
          new_state = %{state | arbitrum_nonce: fresh_nonce}
          execute_arbitrum_tx(new_state, data, gas_limit, retry_count + 1)
        else
          # Refresh nonce on error but don't retry
          {:ok, fresh_nonce} = HighRollers.Contracts.NFTContract.get_nonce(state.affiliate_linker_address)
          new_state = %{state | arbitrum_nonce: fresh_nonce}
          {:error, reason, new_state}
        end
    end
  end

  defp sign_and_send_tx(private_key, to_address, data, nonce, chain_id, gas_limit, chain) do
    # Get gas price
    gas_price = get_gas_price(chain)

    # Build unsigned transaction
    tx = %{
      nonce: nonce,
      gas_price: gas_price,
      gas_limit: gas_limit,
      to: decode_address_bytes(to_address),
      value: 0,
      data: decode_hex_bytes(data),
      chain_id: chain_id
    }

    # Sign transaction using Ethers library
    private_key_bytes = decode_hex_bytes(private_key)

    case sign_transaction(tx, private_key_bytes) do
      {:ok, signed_tx_hex} ->
        # Send raw transaction
        rpc_url = case chain do
          :rogue -> Application.get_env(:high_rollers, :rogue_rpc_url)
          :arbitrum -> Application.get_env(:high_rollers, :arbitrum_rpc_url)
        end

        HighRollers.RPC.call(rpc_url, "eth_sendRawTransaction", [signed_tx_hex])

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp sign_transaction(tx, private_key_bytes) do
    # Use ExRLP and ExSecp256k1 for transaction signing
    # This is a simplified implementation - in production you might use a library
    try do
      # Encode transaction for signing (EIP-155)
      unsigned_tx = [
        encode_integer(tx.nonce),
        encode_integer(tx.gas_price),
        encode_integer(tx.gas_limit),
        tx.to,
        encode_integer(tx.value),
        tx.data,
        encode_integer(tx.chain_id),
        <<>>,
        <<>>
      ]

      unsigned_rlp = ExRLP.encode(unsigned_tx)
      msg_hash = ExKeccak.hash_256(unsigned_rlp)

      # Sign the hash
      # ExSecp256k1.sign/2 returns {:ok, {r, s, recovery_id}}
      {:ok, {r, s, recovery_id}} = ExSecp256k1.sign(msg_hash, private_key_bytes)

      # Calculate v value (EIP-155)
      v = tx.chain_id * 2 + 35 + recovery_id

      # Encode signed transaction
      signed_tx = [
        encode_integer(tx.nonce),
        encode_integer(tx.gas_price),
        encode_integer(tx.gas_limit),
        tx.to,
        encode_integer(tx.value),
        tx.data,
        encode_integer(v),
        r,
        s
      ]

      signed_rlp = ExRLP.encode(signed_tx)
      {:ok, "0x" <> Base.encode16(signed_rlp, case: :lower)}
    rescue
      e ->
        {:error, Exception.message(e)}
    end
  end

  defp encode_integer(0), do: <<>>
  defp encode_integer(n) when is_integer(n), do: :binary.encode_unsigned(n)

  defp get_gas_price(:rogue) do
    # Query Rogue Chain for current gas price
    case HighRollers.RPC.call_rogue("eth_gasPrice", []) do
      {:ok, hex} -> HighRollers.RPC.hex_to_int(hex)
      _ -> 1_000_000_000_000  # 1000 Gwei fallback (Rogue Chain base fee)
    end
  end

  defp get_gas_price(:arbitrum) do
    # Get current gas price from Arbitrum with 2x buffer for base fee fluctuation
    case HighRollers.RPC.call_arbitrum("eth_gasPrice", []) do
      {:ok, hex} ->
        base_price = HighRollers.RPC.hex_to_int(hex)
        # Double the gas price to handle base fee increases between fetch and submit
        base_price * 2
      _ -> 100_000_000  # 0.1 Gwei fallback
    end
  end

  defp wait_for_receipt_rogue(tx_hash) do
    HighRollers.Contracts.NFTRewarder.wait_for_receipt(tx_hash)
  end

  defp wait_for_receipt_arbitrum(tx_hash) do
    wait_for_receipt(tx_hash, :arbitrum, 60_000)
  end

  defp wait_for_receipt(tx_hash, chain, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    poll_receipt(tx_hash, chain, deadline)
  end

  defp poll_receipt(tx_hash, chain, deadline) do
    if System.monotonic_time(:millisecond) > deadline do
      {:error, :timeout}
    else
      rpc_call = case chain do
        :rogue -> &HighRollers.RPC.call_rogue/2
        :arbitrum -> &HighRollers.RPC.call_arbitrum/2
      end

      case rpc_call.("eth_getTransactionReceipt", [tx_hash]) do
        {:ok, nil} ->
          Process.sleep(1000)
          poll_receipt(tx_hash, chain, deadline)

        {:ok, receipt} ->
          {:ok, %{
            tx_hash: receipt["transactionHash"],
            block_number: HighRollers.RPC.hex_to_int(receipt["blockNumber"]),
            status: if(receipt["status"] == "0x1", do: :success, else: :failed)
          }}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # ===== Encoding Helpers =====

  defp function_selector(signature) do
    ExKeccak.hash_256(signature)
    |> binary_part(0, 4)
    |> Base.encode16(case: :lower)
    |> then(&("0x" <> &1))
  end

  defp encode_uint256(int) do
    int
    |> :binary.encode_unsigned()
    |> String.pad_leading(32, <<0>>)
    |> Base.encode16(case: :lower)
  end

  defp encode_uint8(int) do
    # uint8 is still padded to 32 bytes in ABI encoding
    int
    |> :binary.encode_unsigned()
    |> String.pad_leading(32, <<0>>)
    |> Base.encode16(case: :lower)
  end

  defp encode_address(address) do
    # Remove 0x prefix and pad to 32 bytes
    address
    |> String.replace_prefix("0x", "")
    |> String.downcase()
    |> String.pad_leading(64, "0")
  end

  defp encode_dynamic_array_and_address(token_ids, address) do
    # ABI encoding for (uint256[], address):
    # offset to array (64 = 0x40) + address + array_length + array_elements
    offset = "0000000000000000000000000000000000000000000000000000000000000040"
    address_encoded = encode_address(address)
    array_length = encode_uint256(length(token_ids))
    array_elements = Enum.map(token_ids, &encode_uint256/1) |> Enum.join()

    offset <> address_encoded <> array_length <> array_elements
  end

  defp decode_hex_bytes("0x" <> hex), do: Base.decode16!(hex, case: :mixed)
  defp decode_hex_bytes(hex) when is_binary(hex), do: Base.decode16!(hex, case: :mixed)

  defp decode_address_bytes("0x" <> hex) do
    Base.decode16!(hex, case: :mixed)
  end

  defp derive_address_from_private_key(private_key) do
    private_key_bytes = decode_hex_bytes(private_key)

    # Derive public key
    {:ok, public_key} = ExSecp256k1.create_public_key(private_key_bytes)

    # Remove the 04 prefix (uncompressed format) and hash
    <<_prefix::8, pubkey_rest::binary>> = public_key
    address_bytes = ExKeccak.hash_256(pubkey_rest) |> binary_part(12, 20)

    "0x" <> Base.encode16(address_bytes, case: :lower)
  end

  defp op_to_map({@pending_table, {token_id, operation}, args, status, attempts, last_error, created_at, updated_at}) do
    %{
      token_id: token_id,
      operation: operation,
      args: args,
      status: status,
      attempts: attempts,
      last_error: last_error,
      created_at: created_at,
      updated_at: updated_at
    }
  end
end
