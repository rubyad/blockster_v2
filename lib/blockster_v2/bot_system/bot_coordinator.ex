defmodule BlocksterV2.BotSystem.BotCoordinator do
  @moduledoc """
  GlobalSingleton GenServer that orchestrates bot reading behavior.

  Subscribes to `"post:published"` PubSub, schedules bots to read posts
  on a natural decay curve, manages a rate-limited mint queue, and
  tracks pool consumption caps per post.

  Feature-flagged via `config :blockster_v2, :bot_system, enabled: true`.
  """

  use GenServer
  require Logger

  alias BlocksterV2.BotSystem.{BotSetup, EngagementSimulator}
  alias BlocksterV2.{EngagementTracker, BuxMinter, UnifiedMultiplier, Blog}

  @pubsub BlocksterV2.PubSub

  # --- Public API ---

  def start_link(_opts) do
    case BlocksterV2.GlobalSingleton.start_link(__MODULE__, []) do
      {:ok, pid} -> {:ok, pid}
      {:already_registered, _pid} -> :ignore
    end
  end

  @doc """
  Manually trigger initialization. Useful for local dev testing
  when bots are created after the coordinator starts.
  """
  def reinitialize do
    case :global.whereis_name(__MODULE__) do
      :undefined -> {:error, :not_running}
      pid -> send(pid, :initialize); :ok
    end
  end

  @doc """
  Start the coordinator manually (for dev/testing when feature flag is off).
  Uses start (not start_link) so the process survives the caller exiting.
  """
  def start_manual do
    # Clean up stale global registration if process is dead
    case :global.whereis_name(__MODULE__) do
      :undefined -> :ok
      pid ->
        if Process.alive?(pid) do
          Logger.info("[BotCoordinator] Already running at #{inspect(pid)}")
          {:ok, pid}
        else
          :global.unregister_name(__MODULE__)
          :ok
        end
    end
    |> case do
      {:ok, pid} -> {:ok, pid}
      :ok ->
        case GenServer.start(__MODULE__, [], name: {:global, __MODULE__}) do
          {:ok, pid} ->
            Logger.info("[BotCoordinator] Started manually: #{inspect(pid)}")
            {:ok, pid}
          {:error, {:already_started, pid}} ->
            {:ok, pid}
          error ->
            Logger.error("[BotCoordinator] Failed to start: #{inspect(error)}")
            error
        end
    end
  end

  @doc """
  Returns coordinator state for debugging.
  """
  def debug_state do
    case :global.whereis_name(__MODULE__) do
      :undefined -> {:error, :not_running}
      pid -> :sys.get_state(pid)
    end
  end

  @impl true
  def init(_opts) do
    Logger.info("[BotCoordinator] init/1 called, scheduling :initialize in 30s")
    # Delay initialization to let Mnesia and Repo warm up
    Process.send_after(self(), :initialize, :timer.seconds(30))

    {:ok, %{
      initialized: false,
      all_bot_ids: [],
      active_bot_ids: MapSet.new(),
      bot_cache: %{},
      reading_sessions: %{},
      mint_queue: :queue.new(),
      mint_timer: nil,
      post_tracker: %{},
      daily_rotation_timer: nil
    }}
  end

  @impl true
  def terminate(reason, _state) do
    Logger.warning("[BotCoordinator] Terminating: #{inspect(reason)}")
  end

  # --- Handle Info: Initialization ---

  @impl true
  def handle_info(:initialize, state) do
    try do
      bot_ids = BotSetup.get_all_bot_ids()

      # Auto-create bots on first deploy if none exist
      bot_ids = if bot_ids == [] do
        Logger.info("[BotCoordinator] No bots found — creating 1000 bot users (first deploy)")
        {:ok, _created} = BotSetup.create_all_bots(1000)
        BotSetup.get_all_bot_ids()
      else
        bot_ids
      end

      if bot_ids == [] do
        Logger.error("[BotCoordinator] Bot creation failed — retrying in 60s")
        Process.send_after(self(), :initialize, :timer.seconds(60))
        {:noreply, %{state | initialized: false}}
      else
        active_count = get_config(:active_bot_count, 300)
        active_ids = bot_ids |> Enum.shuffle() |> Enum.take(active_count) |> MapSet.new()

        # Build cache of bot smart wallets
        cache = build_bot_cache(bot_ids)

        # Subscribe to post published and pool deposit events
        Phoenix.PubSub.subscribe(@pubsub, "post:published")
        Phoenix.PubSub.subscribe(@pubsub, "post:pool_deposit")

        # Schedule periodic PubSub health check (every 5 min)
        # Subscriptions can be lost during turbulent startups (outage recovery, etc.)
        schedule_pubsub_check()

        # Backfill recent posts (also seeds pools on posts that need them)
        backfill_days = get_config(:backfill_days, 7)
        schedule_backfill(active_ids, backfill_days)

        # Schedule daily rotation at 3 AM UTC
        rotation_timer = schedule_daily_rotation()

        Logger.info("[BotCoordinator] Initialized with #{length(bot_ids)} bots, #{MapSet.size(active_ids)} active")

        {:noreply, %{state |
          initialized: true,
          all_bot_ids: bot_ids,
          active_bot_ids: active_ids,
          bot_cache: cache,
          daily_rotation_timer: rotation_timer
        }}
      end
    rescue
      e ->
        Logger.error("[BotCoordinator] Initialization failed: #{inspect(e)}\n#{Exception.format_stacktrace(__STACKTRACE__)}")
        # Retry in 30 seconds
        Process.send_after(self(), :initialize, :timer.seconds(30))
        {:noreply, %{state | initialized: false}}
    end
  end

  # --- Handle Info: Post Published (PubSub) ---

  @impl true
  def handle_info({:post_published, post}, %{initialized: true} = state) do
    Logger.info("[BotCoordinator] New post published: #{post.id} - #{post.title}")

    state = track_post(state, post)
    active_list = MapSet.to_list(state.active_bot_ids)
    schedule = EngagementSimulator.generate_reading_schedule(active_list)

    Logger.info("[BotCoordinator] Scheduling #{length(schedule)} bots for post #{post.id}")

    Enum.each(schedule, fn {delay_ms, bot_id} ->
      Process.send_after(self(), {:bot_discover_post, bot_id, post.id}, delay_ms)
    end)

    {:noreply, state}
  end

  def handle_info({:post_published, _post}, state), do: {:noreply, state}

  # --- Handle Info: Pool Topped Up (PubSub) ---

  @impl true
  def handle_info({:pool_topped_up, post_id, new_deposited}, %{initialized: true} = state) do
    case Map.get(state.post_tracker, post_id) do
      nil ->
        # Post not tracked yet — ignore (will be picked up on next publish)
        {:noreply, state}

      tracker ->
        old_deposited = tracker.pool_deposited

        if new_deposited > old_deposited do
          # Update pool_deposited so cap_reached? uses the new total
          state = put_in(state, [:post_tracker, post_id, :pool_deposited], new_deposited)

          # Only schedule bots that haven't already earned on this post
          active_list = MapSet.to_list(state.active_bot_ids)
          unrewarded = Enum.filter(active_list, fn bot_id ->
            not already_rewarded?(bot_id, post_id)
          end)

          if unrewarded != [] do
            schedule = EngagementSimulator.generate_reading_schedule(unrewarded)

            Logger.info("[BotCoordinator] Pool topped up for post #{post_id}: #{old_deposited} → #{new_deposited}, scheduling #{length(schedule)} new bots (#{length(active_list) - length(unrewarded)} already read)")

            Enum.each(schedule, fn {delay_ms, bot_id} ->
              Process.send_after(self(), {:bot_discover_post, bot_id, post_id}, delay_ms)
            end)
          end

          {:noreply, state}
        else
          {:noreply, state}
        end
    end
  end

  def handle_info({:pool_topped_up, _post_id, _deposited}, state), do: {:noreply, state}

  # --- Handle Info: Bot Reading Session (3 messages) ---

  # Message 1: Bot discovers and starts reading a post
  @impl true
  def handle_info({:bot_discover_post, user_id, post_id}, state) do
    with true <- state.initialized,
         true <- pool_available?(state, post_id),
         false <- cap_reached?(state, post_id),
         bot_data when bot_data != nil <- Map.get(state.bot_cache, user_id) do

      post = get_cached_post(post_id)

      if post do
        word_count = EngagementTracker.count_words(post.content)
        min_read_time = EngagementTracker.calculate_min_read_time(word_count)

        # Record the visit (sets created_at for anti-exploit timing)
        case EngagementTracker.record_visit(user_id, post_id, min_read_time) do
          {:ok, _} ->
            # Generate score target for this reading session
            {target_time_ratio, target_scroll_depth, _score} = EngagementSimulator.generate_score_target()

            # Calculate real read time in ms
            read_time_ms = round(min_read_time * target_time_ratio * 1000)
            # Ensure minimum 10 seconds
            read_time_ms = max(read_time_ms, 10_000)

            # Schedule mid-read update at ~50%
            mid_delay = div(read_time_ms, 2)
            ref = make_ref()

            Process.send_after(self(), {:bot_reading_update, ref}, mid_delay)

            session = %{
              user_id: user_id,
              post_id: post_id,
              min_read_time: min_read_time,
              target_time_ratio: target_time_ratio,
              target_scroll_depth: target_scroll_depth,
              read_time_ms: read_time_ms,
              base_bux_reward: post.base_bux_reward || 1,
              video_url: post.video_url,
              video_duration: post.video_duration,
              video_bux_per_minute: post.video_bux_per_minute
            }

            {:noreply, put_in(state, [:reading_sessions, ref], session)}

          {:error, reason} ->
            Logger.debug("[BotCoordinator] record_visit failed for bot #{user_id}, post #{post_id}: #{inspect(reason)}")
            {:noreply, state}
        end
      else
        {:noreply, state}
      end
    else
      _ -> {:noreply, state}
    end
  end

  # Message 2: Mid-read engagement update
  @impl true
  def handle_info({:bot_reading_update, ref}, state) do
    case Map.get(state.reading_sessions, ref) do
      nil ->
        {:noreply, state}

      session ->
        partial_metrics = EngagementSimulator.generate_partial_metrics(
          session.target_time_ratio,
          session.target_scroll_depth,
          session.min_read_time,
          0.5
        )

        EngagementTracker.update_engagement(session.user_id, session.post_id, partial_metrics)

        # Schedule completion at remaining time
        remaining_ms = div(session.read_time_ms, 2)
        Process.send_after(self(), {:bot_complete_read, ref}, remaining_ms)

        {:noreply, state}
    end
  end

  # Message 3: Complete read, calculate reward, enqueue mint
  @impl true
  def handle_info({:bot_complete_read, ref}, state) do
    case Map.pop(state.reading_sessions, ref) do
      {nil, _state} ->
        {:noreply, state}

      {session, sessions} ->
        state = %{state | reading_sessions: sessions}

        final_metrics = EngagementSimulator.generate_final_metrics(
          session.target_time_ratio,
          session.target_scroll_depth,
          session.min_read_time
        )

        case EngagementTracker.record_read(session.user_id, session.post_id, final_metrics) do
          {:ok, score} when score > 0 ->
            multiplier = UnifiedMultiplier.get_overall_multiplier(session.user_id)
            # geo_multiplier = 1.0 because unified multiplier already includes phone tier
            raw_bux = EngagementTracker.calculate_bux_earned(score, session.base_bux_reward, multiplier, 1.0)

            # Floor bot rewards — jittered so amounts look natural
            min_reward = get_config(:min_bot_reward, 5.0)
            bux = if raw_bux > 0 and raw_bux < min_reward do
              Float.round(min_reward + :rand.uniform() * min_reward, 2)
            else
              raw_bux
            end

            if bux > 0 do
              case EngagementTracker.record_read_reward(session.user_id, session.post_id, bux) do
                {:ok, recorded_bux} ->
                  state = enqueue_mint(state, %{
                    user_id: session.user_id,
                    post_id: session.post_id,
                    amount: recorded_bux,
                    reward_type: :read
                  })

                  # Update pool consumption tracker
                  state = update_pool_consumption(state, session.post_id, recorded_bux)

                  # Maybe schedule video watch
                  state = maybe_schedule_video(state, session, ref)

                  {:noreply, state}

                {:already_rewarded, _existing} ->
                  {:noreply, state}

                {:error, _reason} ->
                  {:noreply, state}
              end
            else
              {:noreply, state}
            end

          _ ->
            {:noreply, state}
        end
    end
  end

  # --- Handle Info: Video Session (2 messages) ---

  @impl true
  def handle_info({:bot_start_video, user_id, post_id, video_duration, video_bux_per_minute}, state) do
    case EngagementTracker.record_video_view(user_id, post_id, video_duration) do
      {:ok, _} ->
        {_watch_pct, watch_seconds} = EngagementSimulator.generate_video_params(video_duration)
        ref = make_ref()

        session = %{
          user_id: user_id,
          post_id: post_id,
          watch_seconds: watch_seconds,
          video_duration: video_duration,
          video_bux_per_minute: video_bux_per_minute
        }

        Process.send_after(self(), {:bot_complete_video, ref}, watch_seconds * 1000)

        {:noreply, put_in(state, [:reading_sessions, ref], session)}

      _ ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:bot_complete_video, ref}, state) do
    case Map.pop(state.reading_sessions, ref) do
      {nil, _} ->
        {:noreply, state}

      {session, sessions} ->
        state = %{state | reading_sessions: sessions}
        multiplier = UnifiedMultiplier.get_overall_multiplier(session.user_id)

        bux_per_min = if session.video_bux_per_minute do
          Decimal.to_float(session.video_bux_per_minute)
        else
          1.0
        end

        raw_bux = EngagementSimulator.calculate_video_bux(session.watch_seconds, bux_per_min, multiplier)

        # Floor bot video rewards — jittered
        min_reward = get_config(:min_bot_reward, 5.0)
        bux = if raw_bux > 0 and raw_bux < min_reward do
          Float.round(min_reward + :rand.uniform() * min_reward, 2)
        else
          raw_bux
        end

        if bux > 0 do
          case EngagementTracker.record_read_reward(session.user_id, session.post_id, bux) do
            {:ok, _} ->
              state = enqueue_mint(state, %{
                user_id: session.user_id,
                post_id: session.post_id,
                amount: bux,
                reward_type: :video_watch,
                video_session: %{
                  watch_seconds: session.watch_seconds,
                  video_duration: session.video_duration
                }
              })

              {:noreply, state}

            _ ->
              {:noreply, state}
          end
        else
          {:noreply, state}
        end
    end
  end

  # --- Handle Info: Mint Queue ---

  @impl true
  def handle_info(:process_mint, state) do
    case :queue.out(state.mint_queue) do
      {:empty, _} ->
        {:noreply, %{state | mint_timer: nil}}

      {{:value, job}, remaining_queue} ->
        state = %{state | mint_queue: remaining_queue}

        # Process mint asynchronously
        Task.start(fn -> process_mint_job(job) end)

        # Schedule next mint
        interval = get_config(:mint_interval_ms, 5_000)
        timer = Process.send_after(self(), :process_mint, interval)

        {:noreply, %{state | mint_timer: timer}}
    end
  end

  # --- Handle Info: PubSub Health Check ---

  @impl true
  def handle_info(:check_pubsub, %{initialized: true} = state) do
    # Verify our PubSub subscription is alive by checking the Registry.
    # Subscriptions can be silently lost during turbulent startups (outage recovery).
    # See docs/outage-report-feb-2026.md for context.
    keys = Registry.keys(@pubsub, self())

    for topic <- ["post:published", "post:pool_deposit"] do
      unless topic in keys do
        Logger.warning("[BotCoordinator] PubSub subscription lost — re-subscribing to #{topic}")
        Phoenix.PubSub.subscribe(@pubsub, topic)
      end
    end

    schedule_pubsub_check()
    {:noreply, state}
  end

  def handle_info(:check_pubsub, state), do: {:noreply, state}

  # --- Handle Info: Daily Rotation ---

  @impl true
  def handle_info(:daily_rotate, state) do
    active_count = get_config(:active_bot_count, 300)
    new_active = state.all_bot_ids |> Enum.shuffle() |> Enum.take(active_count) |> MapSet.new()

    Logger.info("[BotCoordinator] Daily rotation: #{MapSet.size(new_active)} active bots")

    # Re-subscribe as belt-and-suspenders (subscription may have been lost)
    Phoenix.PubSub.subscribe(@pubsub, "post:published")
    Phoenix.PubSub.subscribe(@pubsub, "post:pool_deposit")

    timer = schedule_daily_rotation()

    {:noreply, %{state | active_bot_ids: new_active, daily_rotation_timer: timer}}
  end

  # --- Handle Info: Backfill post tracking ---

  @impl true
  def handle_info({:track_post_for_backfill, post}, state) do
    {:noreply, track_post(state, post)}
  end

  # Catch-all for unknown messages
  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # --- Private Helpers ---

  defp get_config(key, default) do
    config = Application.get_env(:blockster_v2, :bot_system, [])
    Keyword.get(config, key, default)
  end

  defp build_bot_cache(bot_ids) do
    alias BlocksterV2.Repo
    alias BlocksterV2.Accounts.User
    import Ecto.Query

    users = Repo.all(
      from u in User,
        where: u.id in ^bot_ids,
        select: {u.id, u.smart_wallet_address}
    )

    Map.new(users, fn {id, smart_wallet} ->
      {id, %{smart_wallet_address: smart_wallet}}
    end)
  end

  defp track_post(state, post) do
    min_pool = get_config(:min_pool_balance, 100)
    default_pool = get_config(:default_pool_size, 5000)
    {balance, deposited, _distributed} = EngagementTracker.get_post_pool_stats(post.id)

    # Auto-seed pool if below minimum (same as backfill does).
    # This handles manually created posts and the race condition where
    # content automation's deposit_bux runs after the PubSub broadcast.
    deposited =
      if balance < min_pool do
        case EngagementTracker.deposit_post_bux(post.id, default_pool) do
          {:ok, _} ->
            Logger.info("[BotCoordinator] Auto-seeded pool for post #{post.id} with #{default_pool} BUX")
            deposited + default_pool

          _ ->
            deposited
        end
      else
        deposited
      end

    tracker = %{
      pool_deposited: deposited,
      pool_consumed_by_bots: 0.0
    }
    put_in(state, [:post_tracker, post.id], tracker)
  end

  defp pool_available?(state, post_id) do
    min_pool = get_config(:min_pool_balance, 100)
    balance = EngagementTracker.get_post_bux_balance(post_id)
    balance >= min_pool and Map.has_key?(state.post_tracker, post_id)
  end

  defp cap_reached?(state, post_id) do
    cap_pct = get_config(:pool_cap_percentage, 0.5)

    case Map.get(state.post_tracker, post_id) do
      nil -> true  # No tracking = skip
      tracker ->
        tracker.pool_consumed_by_bots >= tracker.pool_deposited * cap_pct
    end
  end

  defp already_rewarded?(user_id, post_id) do
    case EngagementTracker.get_rewards(user_id, post_id) do
      nil -> false
      record ->
        read_bux = elem(record, 4)
        read_bux != nil and read_bux > 0
    end
  end

  defp update_pool_consumption(state, post_id, amount) do
    case Map.get(state.post_tracker, post_id) do
      nil -> state
      tracker ->
        updated = %{tracker | pool_consumed_by_bots: tracker.pool_consumed_by_bots + amount}
        put_in(state, [:post_tracker, post_id], updated)
    end
  end

  defp maybe_schedule_video(state, session, _ref) do
    video_watch_pct = get_config(:video_watch_percentage, 0.35)

    if session.video_url && session.video_duration && session.video_duration > 0 && :rand.uniform() < video_watch_pct do
      # Delay video start by 5-30 seconds after finishing reading
      delay = Enum.random(5_000..30_000)
      Process.send_after(self(), {
        :bot_start_video,
        session.user_id,
        session.post_id,
        session.video_duration,
        session.video_bux_per_minute
      }, delay)
    end

    state
  end

  defp enqueue_mint(state, job) do
    queue = :queue.in(job, state.mint_queue)
    queue_size = :queue.len(queue)

    if queue_size > 500 do
      Logger.warning("[BotCoordinator] Mint queue at #{queue_size} jobs (backpressure)")
    end

    # Start processing if not already running
    state = if state.mint_timer == nil do
      timer = Process.send_after(self(), :process_mint, 0)
      %{state | mint_timer: timer}
    else
      state
    end

    %{state | mint_queue: queue}
  end

  defp process_mint_job(job) do
    bot_cache = get_bot_cache_entry(job.user_id)
    wallet = bot_cache && bot_cache.smart_wallet_address

    if wallet do
      case BuxMinter.mint_bux(wallet, job.amount, job.user_id, job.post_id, job.reward_type) do
        {:ok, _response} ->
          # Deduct from pool after successful mint
          EngagementTracker.deduct_from_pool_guaranteed(job.post_id, job.amount)

          # Handle video session completion
          if job[:video_session] do
            vs = job.video_session
            EngagementTracker.update_video_engagement_session(job.user_id, job.post_id, %{
              new_high_water_mark: vs.watch_seconds,
              session_bux: job.amount,
              pause_count: 0,
              tab_away_count: 0
            })
          end

          Logger.debug("[BotCoordinator] Minted #{job.amount} BUX for bot #{job.user_id} on post #{job.post_id}")

        {:error, reason} ->
          Logger.warning("[BotCoordinator] Mint failed for bot #{job.user_id}: #{inspect(reason)}")
      end
    else
      Logger.warning("[BotCoordinator] No wallet found for bot #{job.user_id}")
    end
  rescue
    e ->
      Logger.warning("[BotCoordinator] Mint job crashed: #{inspect(e)}")
  end

  defp get_bot_cache_entry(user_id) do
    # Access the coordinator state from the process - use a simple approach
    # Since we're in a spawned Task, we need to query the DB directly
    alias BlocksterV2.Repo
    alias BlocksterV2.Accounts.User
    import Ecto.Query

    case Repo.one(from u in User, where: u.id == ^user_id, select: u.smart_wallet_address) do
      nil -> nil
      address -> %{smart_wallet_address: address}
    end
  end

  defp schedule_backfill(active_ids, backfill_days) do
    Task.start(fn ->
      # Small delay to ensure coordinator is fully initialized
      Process.sleep(5_000)

      cutoff = DateTime.utc_now() |> DateTime.add(-backfill_days * 24 * 3600, :second)
      posts = Blog.list_published_posts(limit: 100)

      recent_posts = Enum.filter(posts, fn post ->
        post.published_at && DateTime.compare(post.published_at, cutoff) == :gt
      end)

      # Auto-seed pools on posts that need them
      min_pool = get_config(:min_pool_balance, 100)
      default_pool = get_config(:default_pool_size, 5000)
      seeded = seed_missing_pools(recent_posts, min_pool, default_pool)
      if seeded > 0, do: Logger.info("[BotCoordinator] Seeded pools on #{seeded} posts (#{default_pool} BUX each)")

      active_list = MapSet.to_list(active_ids)

      Enum.each(recent_posts, fn post ->
        post_age_ms = DateTime.diff(DateTime.utc_now(), post.published_at, :millisecond)
        schedule = EngagementSimulator.generate_backfill_schedule(active_list, post_age_ms)

        if schedule != [] do
          Logger.info("[BotCoordinator] Backfill: scheduling #{length(schedule)} bots for post #{post.id} (age: #{div(post_age_ms, 3_600_000)}h)")

          coordinator = :global.whereis_name(__MODULE__)
          if coordinator != :undefined do
            # Send post tracking first
            send(coordinator, {:track_post_for_backfill, post})
            Enum.each(schedule, fn {delay_ms, bot_id} ->
              Process.send_after(coordinator, {:bot_discover_post, bot_id, post.id}, delay_ms)
            end)
          end
        end
      end)
    end)
  end

  defp seed_missing_pools(posts, min_pool, default_pool) do
    Enum.reduce(posts, 0, fn post, count ->
      balance = EngagementTracker.get_post_bux_balance(post.id)

      if balance < min_pool do
        case EngagementTracker.deposit_post_bux(post.id, default_pool) do
          {:ok, _} -> count + 1
          _ -> count
        end
      else
        count
      end
    end)
  end

  defp schedule_pubsub_check do
    Process.send_after(self(), :check_pubsub, :timer.minutes(5))
  end

  defp schedule_daily_rotation do
    now = DateTime.utc_now()
    # Schedule for 3 AM UTC tomorrow
    tomorrow_3am =
      now
      |> DateTime.to_date()
      |> Date.add(1)
      |> DateTime.new!(~T[03:00:00], "Etc/UTC")

    delay_ms = DateTime.diff(tomorrow_3am, now, :millisecond)
    Process.send_after(self(), :daily_rotate, delay_ms)
  end

  defp get_cached_post(post_id) do
    # Use Repo directly — posts are DB-backed, no cache needed for bot reads
    BlocksterV2.Repo.get(BlocksterV2.Blog.Post, post_id)
  end
end
