defmodule BlocksterV2.BotSystem.DevSetup do
  @moduledoc """
  Development helper to set up and test the bot reader system locally.

  Usage from iex:
    BlocksterV2.BotSystem.DevSetup.setup_and_start()

  Or step by step:
    BlocksterV2.BotSystem.DevSetup.create_bots(20)
    BlocksterV2.BotSystem.DevSetup.seed_pools()
    BlocksterV2.BotSystem.DevSetup.start_coordinator()
  """

  alias BlocksterV2.{Repo, Blog, Blog.Post}
  alias BlocksterV2.BotSystem.{BotSetup, BotCoordinator}
  import Ecto.Query
  require Logger

  @doc """
  One-command setup: creates bots, seeds pools, starts coordinator.
  """
  def setup_and_start(bot_count \\ 20) do
    IO.puts("\n=== Bot Reader System - Dev Setup ===\n")

    # Step 1: Create bots
    create_bots(bot_count)

    # Step 2: Seed pools on recent posts
    seed_pools()

    # Step 3: Start coordinator
    start_coordinator()

    IO.puts("\n=== Setup complete! Watch logs for bot activity ===")
    IO.puts("Run BlocksterV2.BotSystem.DevSetup.status() to check progress\n")
  end

  @doc """
  Creates bot users (idempotent).
  """
  def create_bots(count \\ 20) do
    IO.puts("[1/3] Creating #{count} bot users...")
    {:ok, created} = BotSetup.create_all_bots(count)
    total = BotSetup.bot_count()
    IO.puts("  Created #{created} new bots (#{total} total)")
  end

  @doc """
  Seeds BUX pools on recent published posts that don't have pools yet.
  """
  def seed_pools(pool_amount \\ 5000, max_posts \\ 20) do
    IO.puts("[2/3] Seeding BUX pools on posts...")

    posts = Repo.all(
      from p in Post,
        where: not is_nil(p.published_at),
        order_by: [desc: p.published_at],
        limit: ^max_posts,
        select: {p.id, p.title}
    )

    seeded = Enum.reduce(posts, 0, fn {post_id, title}, acc ->
      case :mnesia.dirty_read({:post_bux_points, post_id}) do
        [record] ->
          balance = elem(record, 4) || 0
          if balance <= 0 do
            seed_pool(post_id, pool_amount)
            short_title = String.slice(title, 0..50)
            IO.puts("  Seeded #{pool_amount} BUX on post #{post_id}: #{short_title}...")
            acc + 1
          else
            acc
          end

        [] ->
          seed_pool(post_id, pool_amount)
          short_title = String.slice(title, 0..50)
          IO.puts("  Seeded #{pool_amount} BUX on post #{post_id}: #{short_title}...")
          acc + 1
      end
    end)

    IO.puts("  Seeded #{seeded} posts with #{pool_amount} BUX each")
  end

  @doc """
  Starts the bot coordinator (or reinitializes if already running).
  """
  def start_coordinator do
    IO.puts("[3/3] Starting bot coordinator...")

    case :global.whereis_name(BotCoordinator) do
      :undefined ->
        case BotCoordinator.start_manual() do
          {:ok, pid} ->
            IO.puts("  Coordinator started (#{inspect(pid)})")
            # Trigger initialization immediately
            Process.sleep(1000)
            BotCoordinator.reinitialize()
            IO.puts("  Initialization triggered")

          {:error, reason} ->
            IO.puts("  Failed to start: #{inspect(reason)}")
        end

      pid ->
        IO.puts("  Coordinator already running (#{inspect(pid)}), reinitializing...")
        BotCoordinator.reinitialize()
    end
  end

  @doc """
  Shows current system status.
  """
  def status do
    IO.puts("\n=== Bot Reader System Status ===\n")

    # Bot count
    total_bots = BotSetup.bot_count()
    IO.puts("Bots: #{total_bots}")

    # Coordinator state
    case BotCoordinator.debug_state() do
      {:error, :not_running} ->
        IO.puts("Coordinator: NOT RUNNING")

      state ->
        IO.puts("Coordinator: RUNNING")
        IO.puts("  Initialized: #{state.initialized}")
        IO.puts("  All bots: #{length(state.all_bot_ids)}")
        IO.puts("  Active bots: #{MapSet.size(state.active_bot_ids)}")
        IO.puts("  Active reading sessions: #{map_size(state.reading_sessions)}")
        IO.puts("  Mint queue size: #{:queue.len(state.mint_queue)}")
        IO.puts("  Tracked posts: #{map_size(state.post_tracker)}")

        if map_size(state.post_tracker) > 0 do
          IO.puts("\n  Pool consumption:")
          Enum.each(state.post_tracker, fn {post_id, tracker} ->
            pct = if tracker.pool_deposited > 0 do
              Float.round(tracker.pool_consumed_by_bots / tracker.pool_deposited * 100, 1)
            else
              0.0
            end
            IO.puts("    Post #{post_id}: #{Float.round(tracker.pool_consumed_by_bots, 1)}/#{tracker.pool_deposited} BUX (#{pct}%)")
          end)
        end
    end

    # Posts with pools
    try do
      pool_keys = :mnesia.dirty_all_keys(:post_bux_points)
      pools_with_balance = Enum.count(pool_keys, fn post_id ->
        case :mnesia.dirty_read({:post_bux_points, post_id}) do
          [record] -> (elem(record, 4) || 0) > 0
          [] -> false
        end
      end)
      IO.puts("\nPosts with BUX pools: #{length(pool_keys)} (#{pools_with_balance} with balance > 0)")
    rescue
      _ -> IO.puts("\nPosts with BUX pools: (Mnesia not ready)")
    end

    IO.puts("")
  end

  @doc """
  Simulate publishing a post to trigger bot reading (for testing PubSub flow).
  """
  def simulate_publish(post_id \\ nil) do
    post_id = post_id || get_recent_post_with_pool()

    if post_id do
      post = Repo.get(Post, post_id)
      if post do
        IO.puts("Broadcasting :post_published for: #{post.title}")
        Phoenix.PubSub.broadcast(BlocksterV2.PubSub, "post:published", {:post_published, post})
        IO.puts("Done! Watch logs for bot scheduling messages.")
      else
        IO.puts("Post #{post_id} not found")
      end
    else
      IO.puts("No posts with pools found. Run seed_pools() first.")
    end
  end

  # --- Private ---

  defp seed_pool(post_id, amount) do
    now = System.system_time(:second)
    # Record: {:post_bux_points, post_id, reward, read_time, balance, deposited, extra1, extra2, extra3, extra4, created_at, updated_at}
    record = {:post_bux_points, post_id, 0, 0, amount, amount, 0, 0, 0, 0, now, now}
    :mnesia.dirty_write(record)
  end

  defp get_recent_post_with_pool do
    try do
      :mnesia.dirty_all_keys(:post_bux_points)
      |> Enum.find(fn post_id ->
        case :mnesia.dirty_read({:post_bux_points, post_id}) do
          [record] -> (elem(record, 4) || 0) > 0
          [] -> false
        end
      end)
    rescue
      _ -> nil
    end
  end
end
