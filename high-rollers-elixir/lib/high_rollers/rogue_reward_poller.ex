defmodule HighRollers.RogueRewardPoller do
  @moduledoc """
  Polls the NFTRewarder contract on Rogue Chain for:
  - RewardReceived: When ROGUEBankroll sends rewards after losing bets
  - RewardClaimed: When users withdraw their pending rewards

  Uses GlobalSingleton for cluster-wide single instance - only one node
  polls Rogue Chain at a time, preventing duplicate RPC calls and events.

  Polls every 1 second for near-instant UI updates. GenServer state tracks
  `polling: true/false` to prevent overlapping polls - if a poll takes longer
  than 1 second, the next :poll message is skipped until the current completes.

  RESTART RECOVERY:
  - Persists last_processed_block to Mnesia after each poll
  - On restart, resumes from last_processed_block (not current block)
  - First run: backfills from NFTRewarder deploy block
  """
  use GenServer
  require Logger

  @poll_interval_ms 1_000  # 1 second - fast polling for real-time UI
  @max_blocks_per_query 5000  # Rogue Chain is faster, can query more blocks
  @backfill_chunk_size 10_000
  @poller_state_table :hr_poller_state
  @deploy_block 109_350_000  # NFTRewarder deploy block on Rogue Chain

  # ===== Client API =====

  def start_link(opts) do
    case HighRollers.GlobalSingleton.start_link(__MODULE__, opts) do
      {:ok, pid} -> {:ok, pid}
      {:already_registered, _pid} -> :ignore
    end
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
          polling: false  # Prevents overlapping polls
        }

        # Backfill historical events on startup (runs async)
        if last_block < current_block do
          Logger.info("[RogueRewardPoller] Backfilling from block #{last_block} to #{current_block}")
          spawn(fn -> backfill_historical_events(last_block, current_block) end)
        end

        schedule_poll()

        Logger.info("[RogueRewardPoller] Started from block #{current_block}")
        {:ok, %{state | last_processed_block: current_block}}

      {:error, reason} ->
        Logger.error("[RogueRewardPoller] Failed to get current block: #{inspect(reason)}")
        # Retry after delay
        Process.send_after(self(), :retry_init, 5_000)
        {:ok, %{last_processed_block: last_block, polling: false, init_failed: true}}
    end
  end

  @impl true
  def handle_info(:retry_init, %{init_failed: true} = state) do
    case get_current_block() do
      {:ok, current_block} ->
        Logger.info("[RogueRewardPoller] Init retry succeeded, current block: #{current_block}")
        schedule_poll()
        {:noreply, %{state | last_processed_block: current_block, init_failed: false}}

      {:error, _} ->
        Process.send_after(self(), :retry_init, 5_000)
        {:noreply, state}
    end
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
      [:high_rollers, :rogue_poller, :poll],
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
    case :mnesia.dirty_read({@poller_state_table, :rogue}) do
      [{@poller_state_table, :rogue, block}] -> block
      [] -> @deploy_block  # First run: start from contract deploy
    end
  end

  defp save_last_processed_block(block) do
    :mnesia.dirty_write({@poller_state_table, :rogue, block})
  end

  defp poll_events_with_count(state) do
    case get_current_block() do
      {:ok, current_block} when current_block > state.last_processed_block ->
        from_block = state.last_processed_block + 1
        to_block = min(current_block, from_block + @max_blocks_per_query - 1)

        received_count = poll_reward_received_events_counted(from_block, to_block)
        claimed_count = poll_reward_claimed_events_counted(from_block, to_block)

        # Persist to Mnesia after each successful poll
        save_last_processed_block(to_block)

        events_count = received_count + claimed_count
        {%{state | last_processed_block: to_block}, events_count}

      {:ok, _} ->
        # No new blocks
        {state, 0}

      {:error, reason} ->
        Logger.warning("[RogueRewardPoller] Failed to get current block: #{inspect(reason)}")
        {state, 0}
    end
  end

  defp poll_reward_received_events_counted(from_block, to_block) do
    case HighRollers.Contracts.NFTRewarder.get_reward_received_events(from_block, to_block) do
      {:ok, events} ->
        Enum.each(events, fn event ->
          Logger.info("[RogueRewardPoller] RewardReceived: #{format_rogue(event.amount)} ROGUE")

          # Store in database
          HighRollers.Rewards.insert_event(%{
            commitment_hash: event.bet_id,
            amount: event.amount,
            timestamp: event.timestamp,
            block_number: event.block_number,
            tx_hash: event.tx_hash
          })

          # Broadcast to LiveViews
          Phoenix.PubSub.broadcast(HighRollers.PubSub, "reward_events", {:reward_received, event})
        end)
        length(events)

      {:error, reason} ->
        Logger.warning("[RogueRewardPoller] RewardReceived poll error: #{inspect(reason)}")
        0
    end
  end

  defp poll_reward_claimed_events_counted(from_block, to_block) do
    case HighRollers.Contracts.NFTRewarder.get_reward_claimed_events(from_block, to_block) do
      {:ok, events} ->
        Enum.each(events, fn event ->
          Logger.info("[RogueRewardPoller] RewardClaimed: #{format_rogue(event.amount)} ROGUE to #{short_address(event.user)}")

          # Record withdrawal
          HighRollers.Rewards.record_withdrawal(%{
            user_address: event.user,
            amount: event.amount,
            token_ids: Jason.encode!(event.token_ids),
            tx_hash: event.tx_hash
          })

          # Reset pending for claimed NFTs (EarningsSyncer will update on next sync)
          Enum.each(event.token_ids, &HighRollers.Rewards.reset_nft_pending/1)

          # Broadcast to LiveViews
          Phoenix.PubSub.broadcast(HighRollers.PubSub, "reward_events", {:reward_claimed, event})
        end)
        length(events)

      {:error, reason} ->
        Logger.warning("[RogueRewardPoller] RewardClaimed poll error: #{inspect(reason)}")
        0
    end
  end

  defp backfill_historical_events(from_block, to_block) do
    Logger.info("[RogueRewardPoller] Starting backfill: #{from_block} -> #{to_block}")

    chunk_starts = Stream.iterate(from_block, &(&1 + @backfill_chunk_size))
    |> Enum.take_while(&(&1 <= to_block))

    total_events = Enum.reduce_while(chunk_starts, 0, fn chunk_start, total ->
      chunk_end = min(chunk_start + @backfill_chunk_size - 1, to_block)

      event_count = backfill_reward_received_chunk(chunk_start, chunk_end)
      backfill_reward_claimed_chunk(chunk_start, chunk_end)

      # Save progress
      save_last_processed_block(chunk_end)

      new_total = total + event_count

      if chunk_end >= to_block do
        {:halt, new_total}
      else
        Process.sleep(100)  # Rate limiting
        {:cont, new_total}
      end
    end)

    Logger.info("[RogueRewardPoller] Backfill complete: #{total_events} reward events")
  end

  defp backfill_reward_received_chunk(from_block, to_block) do
    case HighRollers.Contracts.NFTRewarder.get_reward_received_events(from_block, to_block) do
      {:ok, events} ->
        Enum.each(events, fn event ->
          # During backfill, just store events (no broadcasts)
          HighRollers.Rewards.insert_event(%{
            commitment_hash: event.bet_id,
            amount: event.amount,
            timestamp: event.timestamp,
            block_number: event.block_number,
            tx_hash: event.tx_hash
          })
        end)
        length(events)

      {:error, reason} ->
        Logger.warning("[RogueRewardPoller] Backfill RewardReceived error: #{inspect(reason)}")
        0
    end
  end

  defp backfill_reward_claimed_chunk(from_block, to_block) do
    case HighRollers.Contracts.NFTRewarder.get_reward_claimed_events(from_block, to_block) do
      {:ok, events} ->
        Enum.each(events, fn event ->
          # During backfill, just store withdrawals (no broadcasts or pending resets)
          HighRollers.Rewards.record_withdrawal(%{
            user_address: event.user,
            amount: event.amount,
            token_ids: Jason.encode!(event.token_ids),
            tx_hash: event.tx_hash
          })
        end)
        length(events)

      {:error, reason} ->
        Logger.warning("[RogueRewardPoller] Backfill RewardClaimed error: #{inspect(reason)}")
        0
    end
  end

  defp get_current_block do
    HighRollers.Contracts.NFTRewarder.get_block_number()
  end

  defp format_rogue(wei_string) do
    wei = String.to_integer(wei_string)
    Float.round(wei / 1.0e18, 2)
  end

  defp short_address(address), do: String.slice(address, 0, 10) <> "..."
end
