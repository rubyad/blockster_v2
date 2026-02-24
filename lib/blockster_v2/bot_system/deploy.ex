defmodule BlocksterV2.BotSystem.Deploy do
  @moduledoc """
  Idempotent initialization for the bot reader system.

  Run on first deploy and any time you need to verify/repair:

      flyctl ssh console --app blockster-v2 -C "bin/blockster_v2 rpc 'BlocksterV2.BotSystem.Deploy.initialize()'"

  Safe to re-run — only creates missing bots, seeds missing pools, etc.
  """

  require Logger

  alias BlocksterV2.BotSystem.{BotSetup, BotCoordinator}
  alias BlocksterV2.{EngagementTracker, Blog}

  @target_bot_count 1000

  @doc """
  Full initialization. Idempotent — safe to call on every deploy.

  1. Creates bot users if fewer than #{@target_bot_count} exist
  2. Ensures coordinator is running and initialized
  3. Seeds BUX pools on recent posts that lack them
  4. Prints system status
  """
  def initialize do
    IO.puts("=== Bot System Initialization ===\n")

    # Step 1: Ensure bots exist
    {bot_status, bot_count} = ensure_bots()
    IO.puts("[1/4] Bots: #{bot_count} total (#{bot_status})")

    # Step 2: Ensure coordinator is running
    coord_status = ensure_coordinator()
    IO.puts("[2/4] Coordinator: #{coord_status}")

    # Step 3: Seed pools on recent posts that need them
    {seeded, skipped} = seed_pools()
    IO.puts("[3/4] Pools: #{seeded} seeded, #{skipped} already sufficient")

    # Step 4: Report status
    IO.puts("\n[4/4] Status:")
    report_status()

    IO.puts("\n=== Initialization Complete ===")
    :ok
  end

  @doc """
  Print current system status without changing anything.
  """
  def status do
    report_status()
    :ok
  end

  # --- Step 1: Ensure bots exist ---

  defp ensure_bots do
    existing = BotSetup.bot_count()

    if existing >= @target_bot_count do
      {:already_exist, existing}
    else
      IO.puts("  Creating #{@target_bot_count - existing} bots...")
      {:ok, created} = BotSetup.create_all_bots(@target_bot_count)
      {:created, existing + created}
    end
  end

  # --- Step 2: Ensure coordinator is running ---

  defp ensure_coordinator do
    case :global.whereis_name(BotCoordinator) do
      :undefined ->
        start_coordinator()

      pid ->
        state = :sys.get_state(pid)

        if state.initialized do
          "running (#{MapSet.size(state.active_bot_ids)} active bots, #{map_size(state.post_tracker)} tracked posts)"
        else
          # Running but not initialized — trigger it
          send(pid, :initialize)
          wait_for_init(pid, 10)
        end
    end
  end

  defp start_coordinator do
    config = Application.get_env(:blockster_v2, :bot_system, [])

    if Keyword.get(config, :enabled, false) do
      case BotCoordinator.start_manual() do
        {:ok, pid} ->
          wait_for_init(pid, 10)

        error ->
          "failed to start: #{inspect(error)}"
      end
    else
      "feature flag OFF — set BOT_SYSTEM_ENABLED=true and redeploy"
    end
  end

  defp wait_for_init(pid, attempts) when attempts > 0 do
    Process.sleep(5_000)
    state = :sys.get_state(pid)

    if state.initialized do
      "initialized (#{MapSet.size(state.active_bot_ids)} active bots)"
    else
      if attempts > 1 do
        wait_for_init(pid, attempts - 1)
      else
        "started but not yet initialized (may still be warming up)"
      end
    end
  end

  # --- Step 3: Seed pools on recent posts ---

  defp seed_pools do
    default_pool = get_config(:default_pool_size, 5000)
    min_pool = get_config(:min_pool_balance, 100)
    posts = Blog.list_published_posts(limit: 50)

    Enum.reduce(posts, {0, 0}, fn post, {seeded, skipped} ->
      balance = EngagementTracker.get_post_bux_balance(post.id)

      if balance < min_pool do
        case EngagementTracker.deposit_post_bux(post.id, default_pool) do
          {:ok, _} ->
            # Notify coordinator to track this post
            case :global.whereis_name(BotCoordinator) do
              :undefined -> :ok
              pid -> send(pid, {:track_post_for_backfill, post})
            end

            {seeded + 1, skipped}

          _ ->
            {seeded, skipped}
        end
      else
        {seeded, skipped + 1}
      end
    end)
  end

  # --- Step 4: Status report ---

  defp report_status do
    bot_count = BotSetup.bot_count()
    IO.puts("  Bots in DB: #{bot_count}")

    config = Application.get_env(:blockster_v2, :bot_system, [])
    IO.puts("  Feature flag: #{if Keyword.get(config, :enabled, false), do: "ON", else: "OFF"}")
    IO.puts("  Active bot count: #{Keyword.get(config, :active_bot_count, 300)}")
    IO.puts("  Min bot reward: #{Keyword.get(config, :min_bot_reward, 5.0)} BUX")
    IO.puts("  Mint interval: #{Keyword.get(config, :mint_interval_ms, 5000)}ms")

    case :global.whereis_name(BotCoordinator) do
      :undefined ->
        IO.puts("  Coordinator: NOT RUNNING")

      pid ->
        state = :sys.get_state(pid)
        IO.puts("  Coordinator: #{if state.initialized, do: "RUNNING", else: "NOT INITIALIZED"}")
        IO.puts("  Active bots: #{MapSet.size(state.active_bot_ids)}")
        IO.puts("  Tracked posts: #{map_size(state.post_tracker)}")
        IO.puts("  Reading sessions: #{map_size(state.reading_sessions)}")
        IO.puts("  Mint queue: #{:queue.len(state.mint_queue)}")

        if map_size(state.post_tracker) > 0 do
          total_consumed = Enum.reduce(state.post_tracker, 0.0, fn {_, t}, acc ->
            acc + t.pool_consumed_by_bots
          end)

          IO.puts("  Total BUX consumed by bots: #{Float.round(total_consumed, 1)}")
        end
    end
  end

  defp get_config(key, default) do
    config = Application.get_env(:blockster_v2, :bot_system, [])
    Keyword.get(config, key, default)
  end
end
