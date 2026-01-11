defmodule HighRollers.ArbitrumEventPoller do
  @moduledoc """
  Polls the Arbitrum NFT contract for events:
  - NFTRequested: New mint request (VRF pending)
  - NFTMinted: Mint completed
  - Transfer: Ownership changed

  Uses queryFilter polling (NOT WebSocket subscriptions) because Arbitrum
  RPC providers often drop WebSocket connections.

  Uses GlobalSingleton for cluster-wide single instance - only one node
  polls Arbitrum at a time, preventing duplicate RPC calls and events.

  Polls every 1 second for near-instant UI updates. GenServer state tracks
  `polling: true/false` to prevent overlapping polls - if a poll takes longer
  than 1 second, the next :poll message is skipped until the current completes.

  RESTART RECOVERY:
  - Persists last_processed_block to Mnesia after each poll
  - On restart, resumes from last_processed_block (not current block)
  - First run: backfills from contract deploy block

  This eliminates the need for a separate OwnershipSyncer - we never miss events.
  """
  use GenServer
  require Logger

  @poll_interval_ms 1_000  # 1 second - fast polling for real-time UI
  @max_blocks_per_query 1000
  @backfill_chunk_size 10_000
  @poller_state_table :hr_poller_state
  @deploy_block 420_000_000  # not deploy block but just before latest high rollers app was deployed

  # Zero address for mint detection
  @zero_address "0x0000000000000000000000000000000000000000"

  # ===== Client API =====

  def start_link(opts) do
    case HighRollers.GlobalSingleton.start_link(__MODULE__, opts) do
      {:ok, pid} -> {:ok, pid}
      {:already_registered, _pid} -> :ignore
    end
  end

  @doc """
  Trigger a manual backfill from the given block range.
  Runs asynchronously via GenServer cast - check logs for progress.
  """
  def backfill(from_block, to_block) do
    GenServer.cast({:global, __MODULE__}, {:backfill, from_block, to_block})
  end

  # ===== Server Callbacks =====

  @impl true
  def init(_opts) do
    # Load last processed block from Mnesia, or use deploy block for first run
    last_block = load_last_processed_block()

    case get_current_block() do
      {:ok, current_block} ->
        state = %{
          last_processed_block: last_block,
          pending_mints: %{},  # request_id => %{sender, token_id, timestamp}
          polling: false,      # Prevents overlapping polls
          backfilling: false   # True while backfill is running
        }

        # Backfill any missed events, then start polling
        if last_block < current_block do
          Logger.info("[ArbitrumEventPoller] Backfilling from block #{last_block} to #{current_block}")
          # Run backfill async, it will send :backfill_complete when done
          parent = self()
          spawn(fn ->
            backfill_events(last_block, current_block)
            send(parent, {:backfill_complete, current_block})
          end)
          Logger.info("[ArbitrumEventPoller] Started, waiting for backfill to complete before polling")
          {:ok, %{state | backfilling: true}}
        else
          # No backfill needed, start polling immediately
          schedule_poll()
          Logger.info("[ArbitrumEventPoller] Started, last processed: #{last_block}, current: #{current_block}")
          {:ok, %{state | last_processed_block: current_block}}
        end

      {:error, reason} ->
        Logger.error("[ArbitrumEventPoller] Failed to get current block: #{inspect(reason)}")
        # Retry after delay
        Process.send_after(self(), :retry_init, 5_000)
        {:ok, %{last_processed_block: last_block, pending_mints: %{}, polling: false, backfilling: false, init_failed: true}}
    end
  end

  @impl true
  def handle_info(:retry_init, %{init_failed: true} = state) do
    case get_current_block() do
      {:ok, current_block} ->
        Logger.info("[ArbitrumEventPoller] Init retry succeeded, current block: #{current_block}")
        schedule_poll()
        {:noreply, %{state | last_processed_block: current_block, init_failed: false}}

      {:error, _} ->
        Process.send_after(self(), :retry_init, 5_000)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:backfill_complete, current_block}, state) do
    Logger.info("[ArbitrumEventPoller] Backfill complete, starting normal polling from block #{current_block}")
    save_last_processed_block(current_block)
    schedule_poll()
    {:noreply, %{state | last_processed_block: current_block, backfilling: false}}
  end

  @impl true
  def handle_cast({:backfill, from_block, to_block}, state) do
    Logger.info("[ArbitrumEventPoller] Manual backfill requested: #{from_block} -> #{to_block}")
    # Run in spawned process to not block GenServer
    spawn(fn -> backfill_events(from_block, to_block) end)
    {:noreply, state}
  end

  @impl true
  def handle_info(:poll, %{backfilling: true} = state) do
    # Skip polling while backfill is running
    {:noreply, state}
  end

  @impl true
  def handle_info(:poll, %{polling: true} = state) do
    # Skip if already polling (prevents overlap)
    schedule_poll()
    {:noreply, state}
  end

  @impl true
  def handle_info(:poll, %{init_failed: true} = state) do
    # Skip polling if initialization failed
    {:noreply, state}
  end

  @impl true
  def handle_info(:poll, state) do
    state = %{state | polling: true}
    start_time = System.monotonic_time()
    {state, events_count} = poll_events_with_count(state)
    duration = System.monotonic_time() - start_time

    # Emit telemetry
    :telemetry.execute(
      [:high_rollers, :arbitrum_poller, :poll],
      %{duration: duration, events_count: events_count},
      %{from_block: state.last_processed_block - @max_blocks_per_query, to_block: state.last_processed_block}
    )

    state = %{state | polling: false}
    schedule_poll()
    {:noreply, state}
  end

  # ===== Private Functions =====

  defp schedule_poll do
    Process.send_after(self(), :poll, @poll_interval_ms)
  end

  defp load_last_processed_block do
    case :mnesia.dirty_read({@poller_state_table, :arbitrum}) do
      [{@poller_state_table, :arbitrum, block}] -> block
      [] -> @deploy_block  # First run: start from contract deploy
    end
  end

  defp save_last_processed_block(block) do
    :mnesia.dirty_write({@poller_state_table, :arbitrum, block})
  end

  defp poll_events_with_count(state) do
    case get_current_block() do
      {:ok, current_block} when current_block > state.last_processed_block ->
        from_block = state.last_processed_block + 1
        to_block = min(current_block, from_block + @max_blocks_per_query - 1)

        {state, requested_count} = poll_nft_requested_events_counted(state, from_block, to_block)
        {state, minted_count} = poll_nft_minted_events_counted(state, from_block, to_block)
        {state, transfer_count} = poll_transfer_events_counted(state, from_block, to_block)

        state = Map.put(state, :last_processed_block, to_block)

        # Persist to Mnesia after each successful poll
        save_last_processed_block(to_block)

        events_count = requested_count + minted_count + transfer_count
        {state, events_count}

      {:ok, _} ->
        # No new blocks
        {state, 0}

      {:error, reason} ->
        Logger.warning("[ArbitrumEventPoller] Failed to get current block: #{inspect(reason)}")
        {state, 0}
    end
  end

  @doc """
  Backfill historical events from a starting block to current.
  Called on startup if we're behind, and processes events in chunks.
  """
  defp backfill_events(from_block, to_block) do
    Logger.info("[ArbitrumEventPoller] Starting backfill: #{from_block} -> #{to_block}")

    chunk_starts = Stream.iterate(from_block, &(&1 + @backfill_chunk_size))
    |> Enum.take_while(&(&1 <= to_block))

    Enum.reduce_while(chunk_starts, 0, fn chunk_start, total ->
      chunk_end = min(chunk_start + @backfill_chunk_size - 1, to_block)

      # Process all event types for this chunk
      poll_nft_requested_events_backfill(chunk_start, chunk_end)
      poll_nft_minted_events_backfill(chunk_start, chunk_end)
      poll_transfer_events_backfill(chunk_start, chunk_end)

      # Save progress
      save_last_processed_block(chunk_end)

      new_total = total + (chunk_end - chunk_start + 1)
      Logger.info("[ArbitrumEventPoller] Backfill progress: #{new_total} blocks processed")

      # Rate limiting
      Process.sleep(200)

      if chunk_end >= to_block do
        {:halt, new_total}
      else
        {:cont, new_total}
      end
    end)

    Logger.info("[ArbitrumEventPoller] Backfill complete")
  end

  defp poll_nft_requested_events_backfill(from_block, to_block) do
    case HighRollers.Contracts.NFTContract.get_nft_requested_events(from_block, to_block) do
      {:ok, events} ->
        Enum.each(events, fn event ->
          # During backfill, just insert pending mint records
          HighRollers.NFTStore.insert_pending_mint(%{
            request_id: event.request_id,
            sender: event.sender,
            token_id: event.token_id,
            price: event.price,
            tx_hash: event.tx_hash
          })
        end)

      {:error, reason} ->
        Logger.warning("[ArbitrumEventPoller] Backfill NFTRequested error: #{inspect(reason)}")
    end
  end

  defp poll_nft_minted_events_backfill(from_block, to_block) do
    case HighRollers.Contracts.NFTContract.get_nft_minted_events(from_block, to_block) do
      {:ok, events} ->
        Enum.each(events, fn event ->
          handle_nft_minted(event, backfill: true)
        end)

      {:error, reason} ->
        Logger.warning("[ArbitrumEventPoller] Backfill NFTMinted error: #{inspect(reason)}")
    end
  end

  defp poll_transfer_events_backfill(from_block, to_block) do
    case HighRollers.Contracts.NFTContract.get_transfer_events(from_block, to_block) do
      {:ok, events} ->
        events
        |> Enum.reject(&(&1.from == @zero_address))
        |> Enum.each(fn event ->
          # During backfill, only update local ownership (don't spam NFTRewarder)
          HighRollers.NFTStore.update_owner(event.token_id, event.to)
        end)

      {:error, reason} ->
        Logger.warning("[ArbitrumEventPoller] Backfill Transfer error: #{inspect(reason)}")
    end
  end

  defp poll_nft_requested_events_counted(state, from_block, to_block) do
    case HighRollers.Contracts.NFTContract.get_nft_requested_events(from_block, to_block) do
      {:ok, events} ->
        state = Enum.reduce(events, state, fn event, acc ->
          handle_nft_requested(event, acc)
        end)
        {state, length(events)}

      {:error, reason} ->
        Logger.warning("[ArbitrumEventPoller] NFTRequested poll error: #{inspect(reason)}")
        {state, 0}
    end
  end

  defp poll_nft_minted_events_counted(state, from_block, to_block) do
    case HighRollers.Contracts.NFTContract.get_nft_minted_events(from_block, to_block) do
      {:ok, events} ->
        Enum.each(events, fn event ->
          handle_nft_minted(event, backfill: false)
        end)
        # Remove from pending_mints
        request_ids = Enum.map(events, & &1.request_id)
        state = update_in(state.pending_mints, &Map.drop(&1, request_ids))
        {state, length(events)}

      {:error, reason} ->
        Logger.warning("[ArbitrumEventPoller] NFTMinted poll error: #{inspect(reason)}")
        {state, 0}
    end
  end

  defp poll_transfer_events_counted(state, from_block, to_block) do
    case HighRollers.Contracts.NFTContract.get_transfer_events(from_block, to_block) do
      {:ok, events} ->
        # Filter out mint transfers (from = zero address)
        non_mint_events = Enum.reject(events, &(&1.from == @zero_address))
        Enum.each(non_mint_events, &handle_transfer/1)
        {state, length(non_mint_events)}

      {:error, reason} ->
        Logger.warning("[ArbitrumEventPoller] Transfer poll error: #{inspect(reason)}")
        {state, 0}
    end
  end

  defp handle_nft_requested(event, state) do
    Logger.info("[ArbitrumEventPoller] NFTRequested: requestId=#{event.request_id}, sender=#{event.sender}")

    # Store pending mint
    HighRollers.NFTStore.insert_pending_mint(%{
      request_id: event.request_id,
      sender: event.sender,
      token_id: event.token_id,
      price: event.price,
      tx_hash: event.tx_hash
    })

    # Broadcast to LiveViews
    Phoenix.PubSub.broadcast(HighRollers.PubSub, "nft_events", {:mint_requested, event})

    # Track in state for fallback polling
    put_in(state.pending_mints[event.request_id], %{
      sender: event.sender,
      token_id: event.token_id,
      timestamp: System.system_time(:second)
    })
  end

  defp handle_nft_minted(event, opts) do
    is_backfill = Keyword.get(opts, :backfill, false)

    Logger.info("[ArbitrumEventPoller] NFTMinted: tokenId=#{event.token_id}, hostess=#{event.hostess_index}")

    # Delete pending mint
    HighRollers.NFTStore.delete_pending_mint(event.request_id)

    # Insert NFT record
    hostess = HighRollers.Hostess.get(event.hostess_index)

    HighRollers.NFTStore.upsert(%{
      token_id: event.token_id,
      owner: event.recipient,
      hostess_index: event.hostess_index,
      hostess_name: hostess.name,
      mint_tx_hash: event.tx_hash,
      mint_block_number: event.block_number,
      mint_price: event.price,
      affiliate: event.affiliate,
      affiliate2: event.affiliate2
    })

    # Insert affiliate earnings if applicable
    # Tier 1: Direct referrer gets 20%
    if event.affiliate && event.affiliate != @zero_address do
      tier1_earnings = div(String.to_integer(event.price), 5)  # 20%
      tier1_earnings_str = Integer.to_string(tier1_earnings)
      HighRollers.Sales.insert_affiliate_earning(%{
        token_id: event.token_id,
        tier: 1,
        affiliate: event.affiliate,
        earnings: tier1_earnings_str,
        tx_hash: event.tx_hash
      })
      # Update tier 1 affiliate's withdrawable balance
      HighRollers.Users.add_affiliate_earnings(event.affiliate, tier1_earnings_str)
    end

    # Tier 2: Referrer's referrer gets 5%
    if event.affiliate2 && event.affiliate2 != @zero_address do
      tier2_earnings = div(String.to_integer(event.price), 20)  # 5%
      tier2_earnings_str = Integer.to_string(tier2_earnings)
      HighRollers.Sales.insert_affiliate_earning(%{
        token_id: event.token_id,
        tier: 2,
        affiliate: event.affiliate2,
        earnings: tier2_earnings_str,
        tx_hash: event.tx_hash
      })
      # Update tier 2 affiliate's withdrawable balance
      HighRollers.Users.add_affiliate_earnings(event.affiliate2, tier2_earnings_str)
    end

    # Register NFT in NFTRewarder on Rogue Chain (persistent queue with retry)
    # Skip during backfill - OwnershipReconciler will handle historical NFTs
    unless is_backfill do
      # AdminTxQueue will be implemented in Phase 7
      # For now, this is a no-op that will be enabled when AdminTxQueue is added
      if Code.ensure_loaded?(HighRollers.AdminTxQueue) and
         function_exported?(HighRollers.AdminTxQueue, :enqueue_register_nft, 3) do
        HighRollers.AdminTxQueue.enqueue_register_nft(event.token_id, event.hostess_index, event.recipient)
      end

      # Broadcast to all LiveViews subscribed to nft_events
      Phoenix.PubSub.broadcast(HighRollers.PubSub, "nft_events", {:nft_minted, event})

      # Broadcast to specific affiliate's LiveView for real-time earnings update
      if event.affiliate && event.affiliate != @zero_address do
        tier1_earnings = div(String.to_integer(event.price), 5)  # 20%
        Phoenix.PubSub.broadcast(
          HighRollers.PubSub,
          "affiliate:#{String.downcase(event.affiliate)}",
          {:affiliate_earning, %{token_id: event.token_id, tier: 1, earnings: tier1_earnings}}
        )
      end

      if event.affiliate2 && event.affiliate2 != @zero_address do
        tier2_earnings = div(String.to_integer(event.price), 20)  # 5%
        Phoenix.PubSub.broadcast(
          HighRollers.PubSub,
          "affiliate:#{String.downcase(event.affiliate2)}",
          {:affiliate_earning, %{token_id: event.token_id, tier: 2, earnings: tier2_earnings}}
        )
      end
    end
  end

  defp handle_transfer(event) do
    Logger.info("[ArbitrumEventPoller] Transfer: tokenId=#{event.token_id}, to=#{event.to}")

    # Update local ownership in hr_nfts table
    HighRollers.NFTStore.update_owner(event.token_id, event.to)

    # Update ownership on Rogue Chain (persistent queue with retry)
    # AdminTxQueue will be implemented in Phase 7
    if Code.ensure_loaded?(HighRollers.AdminTxQueue) and
       function_exported?(HighRollers.AdminTxQueue, :enqueue_update_ownership, 2) do
      HighRollers.AdminTxQueue.enqueue_update_ownership(event.token_id, event.to)
    end

    # Broadcast to LiveViews
    Phoenix.PubSub.broadcast(HighRollers.PubSub, "nft_events", {:nft_transferred, event})
  end

  defp get_current_block do
    HighRollers.Contracts.NFTContract.get_block_number()
  end
end
