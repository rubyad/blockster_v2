defmodule BlocksterV2.ReferralRewardPoller do
  @moduledoc """
  Polls Rogue Chain for ReferralRewardPaid events from BuxBoosterGame and ROGUEBankroll.

  Follows the same pattern as high-rollers-elixir RogueRewardPoller:
  - Polls every 1 second for near-instant UI updates
  - Queries up to 5,000 blocks per poll
  - Persists last processed block in Mnesia
  - Non-blocking polling with overlap prevention
  - Backfills from deploy block on first run
  """
  use GenServer
  require Logger

  alias BlocksterV2.Referrals

  @poll_interval_ms 1_000  # 1 second (same as RogueRewardPoller)
  @max_blocks_per_query 5_000  # Rogue Chain is fast
  @backfill_chunk_size 10_000
  @backfill_delay_ms 100

  # Contract addresses
  @bux_booster_address "0x97b6d6A8f2c6AF6e6fb40f8d36d60DF2fFE4f17B"
  @rogue_bankroll_address "0x51DB4eD2b69b598Fade1aCB5289C7426604AB2fd"
  @rpc_url "https://rpc.roguechain.io/rpc"

  # Deploy block (set to block when V6/V8 with referrals is deployed)
  @deploy_block 114_408_876

  # Event topic: keccak256("ReferralRewardPaid(bytes32,address,address,address,uint256)")
  # For BuxBoosterGame (includes token address)
  # Note: Ethereum uses keccak256, NOT sha3_256 - they are different algorithms
  @bux_referral_topic "0x83eda93299f299bd0efe6595d6839bccd34b19e391c33f15dbc43e94828b4b1d"

  # Event topic: keccak256("ReferralRewardPaid(bytes32,address,address,uint256)")
  # For ROGUEBankroll (no token address - always ROGUE)
  @rogue_referral_topic "0x4f37886b09f4891aa2fd056cbff41c8eefd33d6438d913999a2fb0f83891b248"

  # ----- Public API -----

  def start_link(opts) do
    case BlocksterV2.GlobalSingleton.start_link(__MODULE__, opts) do
      {:ok, pid} -> {:ok, pid}
      {:already_registered, _pid} -> :ignore
    end
  end

  @doc """
  Manually trigger a backfill from a specific block (for testing/recovery).
  """
  def backfill_from_block(from_block) do
    GenServer.cast({:global, __MODULE__}, {:backfill, from_block})
  end

  @doc """
  Get the current poller state (for debugging).
  """
  def get_state do
    GenServer.call({:global, __MODULE__}, :get_state)
  end

  # ----- GenServer Callbacks -----

  @impl true
  def init(_opts) do
    Logger.info("[ReferralRewardPoller] Starting...")

    # Wait for Mnesia to be ready - check periodically
    Process.send_after(self(), :wait_for_mnesia, 500)

    {:ok, %{
      last_block: nil,
      polling: false,
      initialized: false
    }}
  end

  @impl true
  def handle_info(:wait_for_mnesia, state) do
    # Check if the Mnesia table exists using try/catch for :exit errors
    table_exists = try do
      :mnesia.table_info(:referral_poller_state, :type) == :set
    catch
      :exit, _ -> false
    end

    if table_exists do
      # Table exists, now initialize
      last_block = get_last_processed_block()
      current_block = get_current_block()

      Logger.info("[ReferralRewardPoller] Mnesia ready. Last processed: #{last_block}, Current: #{current_block}")

      # Check if we need to backfill
      if last_block < current_block - @max_blocks_per_query do
        spawn(fn -> backfill_events(last_block, current_block) end)
      end

      schedule_poll()
      {:noreply, %{state | last_block: last_block, initialized: true}}
    else
      # Table doesn't exist yet, wait more
      Process.send_after(self(), :wait_for_mnesia, 500)
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:poll, %{polling: true} = state) do
    # Already polling - skip this round (prevents overlap)
    schedule_poll()
    {:noreply, state}
  end

  @impl true
  def handle_info(:poll, %{initialized: false} = state) do
    schedule_poll()
    {:noreply, state}
  end

  @impl true
  def handle_info(:poll, state) do
    state = %{state | polling: true}
    start_time = System.monotonic_time(:millisecond)

    {new_state, events_count} = poll_events(state)

    duration = System.monotonic_time(:millisecond) - start_time
    if events_count > 0 do
      Logger.info("[ReferralRewardPoller] Processed #{events_count} events in #{duration}ms")
    end

    state = %{new_state | polling: false}
    schedule_poll()
    {:noreply, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_cast({:backfill, from_block}, state) do
    current_block = get_current_block()
    spawn(fn -> backfill_events(from_block, current_block) end)
    {:noreply, state}
  end

  # ----- Polling Logic -----

  defp poll_events(state) do
    current_block = get_current_block()
    from_block = state.last_block + 1
    to_block = min(from_block + @max_blocks_per_query - 1, current_block)

    if from_block > current_block do
      {state, 0}
    else
      # Poll both contracts
      bux_events = fetch_bux_referral_events(from_block, to_block)
      rogue_events = fetch_rogue_referral_events(from_block, to_block)

      # Process events
      Enum.each(bux_events, &process_bux_referral_event/1)
      Enum.each(rogue_events, &process_rogue_referral_event/1)

      # Save progress
      save_last_processed_block(to_block)

      {%{state | last_block: to_block}, length(bux_events) + length(rogue_events)}
    end
  end

  defp fetch_bux_referral_events(from_block, to_block) do
    params = %{
      address: @bux_booster_address,
      topics: [@bux_referral_topic],
      fromBlock: int_to_hex(from_block),
      toBlock: int_to_hex(to_block)
    }

    case rpc_call("eth_getLogs", [params]) do
      {:ok, logs} when is_list(logs) -> Enum.map(logs, &parse_bux_referral_log/1)
      {:ok, _} -> []
      {:error, _} -> []
    end
  end

  defp fetch_rogue_referral_events(from_block, to_block) do
    params = %{
      address: @rogue_bankroll_address,
      topics: [@rogue_referral_topic],
      fromBlock: int_to_hex(from_block),
      toBlock: int_to_hex(to_block)
    }

    case rpc_call("eth_getLogs", [params]) do
      {:ok, logs} when is_list(logs) -> Enum.map(logs, &parse_rogue_referral_log/1)
      {:ok, _} -> []
      {:error, _} -> []
    end
  end

  # ----- Event Parsing -----

  defp parse_bux_referral_log(log) do
    # Topics: [event_sig, commitmentHash, referrer, player]
    [_sig, commitment_hash, referrer_topic, player_topic] = log["topics"]

    # Data: [token (address), amount (uint256)]
    data = log["data"] |> String.slice(2..-1//1) |> Base.decode16!(case: :mixed)
    <<_padding::binary-size(12), token_bytes::binary-size(20), amount::unsigned-256>> = data

    %{
      commitment_hash: commitment_hash,
      referrer: decode_address_topic(referrer_topic),
      player: decode_address_topic(player_topic),
      token: "0x" <> Base.encode16(token_bytes, case: :lower),
      amount: amount,
      tx_hash: log["transactionHash"],
      block_number: hex_to_int(log["blockNumber"])
    }
  end

  defp parse_rogue_referral_log(log) do
    # Topics: [event_sig, commitmentHash, referrer, player]
    [_sig, commitment_hash, referrer_topic, player_topic] = log["topics"]

    # Data: [amount (uint256)]
    data = log["data"] |> String.slice(2..-1//1) |> Base.decode16!(case: :mixed)
    <<amount::unsigned-256>> = data

    %{
      commitment_hash: commitment_hash,
      referrer: decode_address_topic(referrer_topic),
      player: decode_address_topic(player_topic),
      token: nil,  # ROGUE (native token)
      amount: amount,
      tx_hash: log["transactionHash"],
      block_number: hex_to_int(log["blockNumber"])
    }
  end

  defp decode_address_topic(topic) do
    # Topic is 32 bytes, address is last 20 bytes
    "0x" <> address_hex = topic
    address_bytes = address_hex |> String.slice(-40, 40)
    "0x" <> String.downcase(address_bytes)
  end

  # ----- Event Processing -----

  defp process_bux_referral_event(event) do
    # Convert wei to token amount (18 decimals)
    amount = event.amount / :math.pow(10, 18)

    Referrals.record_bet_loss_earning(%{
      referrer_wallet: event.referrer,
      referee_wallet: event.player,
      amount: amount,
      token: "BUX",
      commitment_hash: event.commitment_hash,
      tx_hash: event.tx_hash
    })
  end

  defp process_rogue_referral_event(event) do
    # Convert wei to ROGUE amount (18 decimals)
    amount = event.amount / :math.pow(10, 18)

    Referrals.record_bet_loss_earning(%{
      referrer_wallet: event.referrer,
      referee_wallet: event.player,
      amount: amount,
      token: "ROGUE",
      commitment_hash: event.commitment_hash,
      tx_hash: event.tx_hash
    })
  end

  # ----- Backfill (on first run or after long downtime) -----

  defp backfill_events(from_block, to_block) do
    Logger.info("[ReferralRewardPoller] Backfilling from #{from_block} to #{to_block}")

    chunk_starts = Stream.iterate(from_block, &(&1 + @backfill_chunk_size))
    |> Enum.take_while(&(&1 <= to_block))

    Enum.each(chunk_starts, fn chunk_start ->
      chunk_end = min(chunk_start + @backfill_chunk_size - 1, to_block)

      # Fetch and process (skip broadcasts during backfill for performance)
      bux_events = fetch_bux_referral_events(chunk_start, chunk_end)
      rogue_events = fetch_rogue_referral_events(chunk_start, chunk_end)

      Enum.each(bux_events, fn event ->
        process_bux_referral_event_backfill(event)
      end)
      Enum.each(rogue_events, fn event ->
        process_rogue_referral_event_backfill(event)
      end)

      # Save progress
      save_last_processed_block(chunk_end)

      if length(bux_events) + length(rogue_events) > 0 do
        Logger.info("[ReferralRewardPoller] Backfill chunk #{chunk_start}-#{chunk_end}: #{length(bux_events) + length(rogue_events)} events")
      end

      # Rate limiting
      Process.sleep(@backfill_delay_ms)
    end)

    Logger.info("[ReferralRewardPoller] Backfill complete")
  end

  defp process_bux_referral_event_backfill(event) do
    amount = event.amount / :math.pow(10, 18)
    Referrals.record_bet_loss_earning_backfill(%{
      referrer_wallet: event.referrer,
      referee_wallet: event.player,
      amount: amount,
      token: "BUX",
      commitment_hash: event.commitment_hash,
      tx_hash: event.tx_hash
    })
  end

  defp process_rogue_referral_event_backfill(event) do
    amount = event.amount / :math.pow(10, 18)
    Referrals.record_bet_loss_earning_backfill(%{
      referrer_wallet: event.referrer,
      referee_wallet: event.player,
      amount: amount,
      token: "ROGUE",
      commitment_hash: event.commitment_hash,
      tx_hash: event.tx_hash
    })
  end

  # ----- Mnesia State Persistence -----

  defp get_last_processed_block do
    try do
      case :mnesia.dirty_read(:referral_poller_state, :rogue) do
        [{:referral_poller_state, :rogue, last_block, _updated_at}] -> last_block
        [] -> @deploy_block
      end
    catch
      :exit, _ -> @deploy_block
    end
  end

  defp save_last_processed_block(block) do
    record = {:referral_poller_state, :rogue, block, System.system_time(:second)}
    :mnesia.dirty_write(record)
  end

  # ----- RPC Helpers -----

  defp get_current_block do
    case rpc_call("eth_blockNumber", []) do
      {:ok, hex} -> hex_to_int(hex)
      {:error, _} -> 0
    end
  end

  defp rpc_call(method, params) do
    body = Jason.encode!(%{
      jsonrpc: "2.0",
      method: method,
      params: params,
      id: 1
    })

    http_options = [{:timeout, 30_000}, {:connect_timeout, 5_000}]
    headers = [{'content-type', 'application/json'}]
    url_charlist = String.to_charlist(@rpc_url)
    body_charlist = String.to_charlist(body)

    case :httpc.request(:post, {url_charlist, headers, 'application/json', body_charlist}, http_options, []) do
      {:ok, {{_, 200, _}, _, response_body}} ->
        case Jason.decode(to_string(response_body)) do
          {:ok, %{"result" => result}} -> {:ok, result}
          {:ok, %{"error" => error}} -> {:error, error}
          _ -> {:error, :decode_error}
        end
      {:ok, {{_, status, _}, _, _}} ->
        {:error, {:http_error, status}}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp int_to_hex(n), do: "0x" <> Integer.to_string(n, 16)

  defp hex_to_int("0x" <> hex), do: String.to_integer(hex, 16)
  defp hex_to_int(hex) when is_binary(hex), do: String.to_integer(hex, 16)

  defp schedule_poll do
    Process.send_after(self(), :poll, @poll_interval_ms)
  end
end
