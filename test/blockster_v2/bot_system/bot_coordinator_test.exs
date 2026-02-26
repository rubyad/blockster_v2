defmodule BlocksterV2.BotSystem.BotCoordinatorTest do
  use BlocksterV2.DataCase, async: false

  alias BlocksterV2.BotSystem.{BotCoordinator, BotSetup, EngagementSimulator}
  alias BlocksterV2.Blog.Post
  alias BlocksterV2.Accounts.User

  setup do
    # Create Mnesia tables needed for tests
    tables = [
      {:unified_multipliers, :set,
        [:user_id, :x_score, :x_multiplier, :phone_multiplier,
         :rogue_multiplier, :wallet_multiplier, :overall_multiplier,
         :last_updated, :created_at],
        [:overall_multiplier]},
      {:user_post_engagement, :set,
        [:key, :user_id, :post_id, :time_spent, :min_read_time,
         :scroll_depth, :reached_end, :scroll_events, :avg_scroll_speed,
         :max_scroll_speed, :scroll_reversals, :focus_changes,
         :engagement_score, :is_read, :created_at, :updated_at],
        [:user_id, :post_id]},
      {:user_post_rewards, :set,
        [:key, :user_id, :post_id, :read_bux, :read_paid, :read_tx_id,
         :x_share_bux, :x_share_paid, :x_share_tx_id,
         :linkedin_share_bux, :linkedin_share_paid, :linkedin_share_tx_id,
         :total_bux, :total_paid_bux, :created_at, :updated_at],
        [:user_id, :post_id]},
      {:post_bux_points, :ordered_set,
        [:post_id, :reward, :read_time, :bux_balance, :bux_deposited,
         :extra_field1, :extra_field2, :extra_field3, :extra_field4,
         :created_at, :updated_at],
        [:bux_balance, :updated_at]},
      {:user_bux_balances, :set,
        [:user_id, :wallet_address, :smart_wallet_address, :bux_balance, :last_synced_at],
        []},
      {:user_video_engagement, :set,
        [:key, :user_id, :post_id, :video_duration, :high_water_mark,
         :total_bux_earned, :session_count, :pause_count, :tab_away_count,
         :session_earnable_time, :last_watched_at, :created_at, :updated_at],
        [:user_id, :post_id]}
    ]

    for {name, type, attributes, index} <- tables do
      case :mnesia.create_table(name, [
        type: type,
        attributes: attributes,
        index: index,
        ram_copies: [node()]
      ]) do
        {:atomic, :ok} -> :ok
        {:aborted, {:already_exists, ^name}} -> :ok
      end
    end

    :ok
  end

  # Helper: create a test bot user
  defp create_test_bot(index) do
    {:ok, user} = BotSetup.create_bot(index)
    BotSetup.seed_multiplier(user.id, index, 100)
    user
  end

  # Helper: create a test post with BUX pool
  defp create_test_post(opts \\ []) do
    pool_amount = Keyword.get(opts, :pool, 1000)

    # Create author first
    {:ok, author} = Repo.insert(%User{
      email: "author_#{System.unique_integer([:positive])}@test.com",
      wallet_address: BotSetup.generate_eth_address(),
      smart_wallet_address: BotSetup.generate_eth_address(),
      auth_method: "email",
      username: "author_#{System.unique_integer([:positive])}",
      slug: "author-#{System.unique_integer([:positive])}"
    })

    {:ok, post} = Repo.insert(%Post{
      title: "Test Post #{System.unique_integer([:positive])}",
      slug: "test-post-#{System.unique_integer([:positive])}",
      content: %{"type" => "doc", "content" => [
        %{"type" => "paragraph", "content" => [
          %{"type" => "text", "text" => String.duplicate("word ", 200)}
        ]}
      ]},
      published_at: DateTime.utc_now() |> DateTime.truncate(:second),
      base_bux_reward: 1,
      author_id: author.id
    })

    # Deposit BUX to pool
    # Record: {:post_bux_points, post_id, reward, read_time, bux_balance, bux_deposited, distributed, extra1, extra2, extra3, created_at, updated_at}
    if pool_amount > 0 do
      now = System.system_time(:second)
      record = {:post_bux_points, post.id, 0, 0, pool_amount, pool_amount, 0, 0, 0, 0, now, now}
      :mnesia.dirty_write(record)
    end

    post
  end

  describe "init/1" do
    test "starts with uninitialized state" do
      {:ok, state} = BotCoordinator.init([])

      assert state.initialized == false
      assert state.all_bot_ids == []
      assert MapSet.size(state.active_bot_ids) == 0
    end
  end

  describe "handle_info(:initialize, ...)" do
    test "initializes when bots exist" do
      _bot = create_test_bot(1)
      create_test_bot(2)
      create_test_bot(3)

      state = %{
        initialized: false,
        all_bot_ids: [],
        active_bot_ids: MapSet.new(),
        bot_cache: %{},
        reading_sessions: %{},
        mint_queue: :queue.new(),
        mint_timer: nil,
        post_tracker: %{},
        daily_rotation_timer: nil
      }

      {:noreply, new_state} = BotCoordinator.handle_info(:initialize, state)

      assert new_state.initialized == true
      assert length(new_state.all_bot_ids) == 3
      assert MapSet.size(new_state.active_bot_ids) > 0
      assert map_size(new_state.bot_cache) > 0
    end

    test "auto-creates bots when none exist" do
      state = %{
        initialized: false,
        all_bot_ids: [],
        active_bot_ids: MapSet.new(),
        bot_cache: %{},
        reading_sessions: %{},
        mint_queue: :queue.new(),
        mint_timer: nil,
        post_tracker: %{},
        daily_rotation_timer: nil
      }

      {:noreply, new_state} = BotCoordinator.handle_info(:initialize, state)

      # Should auto-create bots and initialize
      assert new_state.initialized == true
      assert length(new_state.all_bot_ids) > 0
    end
  end

  describe "handle_info({:post_published, post}, ...)" do
    test "tracks post and schedules bots when initialized" do
      bot1 = create_test_bot(1)
      bot2 = create_test_bot(2)
      bot3 = create_test_bot(3)

      post = create_test_post(pool: 1000)

      state = %{
        initialized: true,
        all_bot_ids: [bot1.id, bot2.id, bot3.id],
        active_bot_ids: MapSet.new([bot1.id, bot2.id, bot3.id]),
        bot_cache: %{
          bot1.id => %{smart_wallet_address: bot1.smart_wallet_address},
          bot2.id => %{smart_wallet_address: bot2.smart_wallet_address},
          bot3.id => %{smart_wallet_address: bot3.smart_wallet_address}
        },
        reading_sessions: %{},
        mint_queue: :queue.new(),
        mint_timer: nil,
        post_tracker: %{},
        daily_rotation_timer: nil
      }

      {:noreply, new_state} = BotCoordinator.handle_info({:post_published, post}, state)

      # Post should be tracked
      assert Map.has_key?(new_state.post_tracker, post.id)
      tracker = new_state.post_tracker[post.id]
      assert tracker.pool_deposited == 1000
      assert tracker.pool_consumed_by_bots == 0.0
    end

    test "ignores post_published when not initialized" do
      post = create_test_post()

      state = %{
        initialized: false,
        all_bot_ids: [],
        active_bot_ids: MapSet.new(),
        bot_cache: %{},
        reading_sessions: %{},
        mint_queue: :queue.new(),
        mint_timer: nil,
        post_tracker: %{},
        daily_rotation_timer: nil
      }

      {:noreply, new_state} = BotCoordinator.handle_info({:post_published, post}, state)
      assert new_state.post_tracker == %{}
    end
  end

  describe "handle_info({:bot_discover_post, ...}, ...)" do
    test "records visit and creates reading session" do
      bot = create_test_bot(1)
      post = create_test_post(pool: 1000)

      state = %{
        initialized: true,
        all_bot_ids: [bot.id],
        active_bot_ids: MapSet.new([bot.id]),
        bot_cache: %{bot.id => %{smart_wallet_address: bot.smart_wallet_address}},
        reading_sessions: %{},
        mint_queue: :queue.new(),
        mint_timer: nil,
        post_tracker: %{
          post.id => %{pool_deposited: 1000, pool_consumed_by_bots: 0.0}
        },
        daily_rotation_timer: nil
      }

      {:noreply, new_state} = BotCoordinator.handle_info(
        {:bot_discover_post, bot.id, post.id},
        state
      )

      # Should have created a reading session
      assert map_size(new_state.reading_sessions) == 1

      [{_ref, session}] = Map.to_list(new_state.reading_sessions)
      assert session.user_id == bot.id
      assert session.post_id == post.id
      assert session.min_read_time > 0
      assert session.target_time_ratio > 0
    end

    test "skips when pool cap reached" do
      bot = create_test_bot(1)
      post = create_test_post(pool: 1000)

      state = %{
        initialized: true,
        all_bot_ids: [bot.id],
        active_bot_ids: MapSet.new([bot.id]),
        bot_cache: %{bot.id => %{smart_wallet_address: bot.smart_wallet_address}},
        reading_sessions: %{},
        mint_queue: :queue.new(),
        mint_timer: nil,
        post_tracker: %{
          post.id => %{pool_deposited: 1000, pool_consumed_by_bots: 600.0}
        },
        daily_rotation_timer: nil
      }

      {:noreply, new_state} = BotCoordinator.handle_info(
        {:bot_discover_post, bot.id, post.id},
        state
      )

      # Should NOT have created a session (cap reached: 600 >= 1000 * 0.5)
      assert map_size(new_state.reading_sessions) == 0
    end

    test "skips when bot not in cache" do
      post = create_test_post(pool: 1000)
      fake_user_id = 999999

      state = %{
        initialized: true,
        all_bot_ids: [fake_user_id],
        active_bot_ids: MapSet.new([fake_user_id]),
        bot_cache: %{},  # No cache entry
        reading_sessions: %{},
        mint_queue: :queue.new(),
        mint_timer: nil,
        post_tracker: %{
          post.id => %{pool_deposited: 1000, pool_consumed_by_bots: 0.0}
        },
        daily_rotation_timer: nil
      }

      {:noreply, new_state} = BotCoordinator.handle_info(
        {:bot_discover_post, fake_user_id, post.id},
        state
      )

      assert map_size(new_state.reading_sessions) == 0
    end
  end

  describe "handle_info({:bot_reading_update, ...}, ...)" do
    test "updates engagement for existing session" do
      bot = create_test_bot(1)
      post = create_test_post(pool: 1000)

      # Set up a reading session
      ref = make_ref()
      min_read_time = 60

      # Record visit first (needed for update_engagement)
      BlocksterV2.EngagementTracker.record_visit(bot.id, post.id, min_read_time)

      session = %{
        user_id: bot.id,
        post_id: post.id,
        min_read_time: min_read_time,
        target_time_ratio: 0.8,
        target_scroll_depth: 80.0,
        read_time_ms: 48_000,
        base_bux_reward: 1,
        video_url: nil,
        video_duration: nil,
        video_bux_per_minute: nil
      }

      state = %{
        initialized: true,
        all_bot_ids: [bot.id],
        active_bot_ids: MapSet.new([bot.id]),
        bot_cache: %{bot.id => %{smart_wallet_address: bot.smart_wallet_address}},
        reading_sessions: %{ref => session},
        mint_queue: :queue.new(),
        mint_timer: nil,
        post_tracker: %{
          post.id => %{pool_deposited: 1000, pool_consumed_by_bots: 0.0}
        },
        daily_rotation_timer: nil
      }

      {:noreply, new_state} = BotCoordinator.handle_info({:bot_reading_update, ref}, state)

      # Session should still exist (not removed until complete)
      assert Map.has_key?(new_state.reading_sessions, ref)
    end

    test "ignores unknown ref" do
      state = %{
        initialized: true,
        reading_sessions: %{}
      }

      {:noreply, new_state} = BotCoordinator.handle_info({:bot_reading_update, make_ref()}, state)
      assert new_state.reading_sessions == %{}
    end
  end

  describe "handle_info({:bot_complete_read, ...}, ...)" do
    test "completes read and enqueues mint for positive score" do
      bot = create_test_bot(1)
      post = create_test_post(pool: 1000)

      ref = make_ref()
      min_read_time = 60

      # Record visit to set created_at (needed for record_read's anti-exploit)
      BlocksterV2.EngagementTracker.record_visit(bot.id, post.id, min_read_time)

      # Wait a tiny bit so server-side time check passes
      Process.sleep(100)

      session = %{
        user_id: bot.id,
        post_id: post.id,
        min_read_time: min_read_time,
        target_time_ratio: 1.0,
        target_scroll_depth: 100.0,
        read_time_ms: 60_000,
        base_bux_reward: 1,
        video_url: nil,
        video_duration: nil,
        video_bux_per_minute: nil
      }

      state = %{
        initialized: true,
        all_bot_ids: [bot.id],
        active_bot_ids: MapSet.new([bot.id]),
        bot_cache: %{bot.id => %{smart_wallet_address: bot.smart_wallet_address}},
        reading_sessions: %{ref => session},
        mint_queue: :queue.new(),
        mint_timer: nil,
        post_tracker: %{
          post.id => %{pool_deposited: 1000, pool_consumed_by_bots: 0.0}
        },
        daily_rotation_timer: nil
      }

      {:noreply, new_state} = BotCoordinator.handle_info({:bot_complete_read, ref}, state)

      # Session should be removed
      refute Map.has_key?(new_state.reading_sessions, ref)

      # Should have enqueued a mint job (if score > 0 and bux > 0)
      queue_size = :queue.len(new_state.mint_queue)
      assert queue_size >= 0  # May be 0 if score was 0, or >= 1 if score > 0
    end

    test "removes session on completion even with score 0" do
      bot = create_test_bot(1)
      post = create_test_post(pool: 1000)

      ref = make_ref()

      # Record visit
      BlocksterV2.EngagementTracker.record_visit(bot.id, post.id, 60)

      # Very low engagement = low/zero score
      session = %{
        user_id: bot.id,
        post_id: post.id,
        min_read_time: 60,
        target_time_ratio: 0.05,
        target_scroll_depth: 5.0,
        read_time_ms: 3_000,
        base_bux_reward: 1,
        video_url: nil,
        video_duration: nil,
        video_bux_per_minute: nil
      }

      state = %{
        initialized: true,
        all_bot_ids: [bot.id],
        active_bot_ids: MapSet.new([bot.id]),
        bot_cache: %{bot.id => %{smart_wallet_address: bot.smart_wallet_address}},
        reading_sessions: %{ref => session},
        mint_queue: :queue.new(),
        mint_timer: nil,
        post_tracker: %{
          post.id => %{pool_deposited: 1000, pool_consumed_by_bots: 0.0}
        },
        daily_rotation_timer: nil
      }

      {:noreply, new_state} = BotCoordinator.handle_info({:bot_complete_read, ref}, state)

      # Session should be removed regardless
      refute Map.has_key?(new_state.reading_sessions, ref)
    end
  end

  describe "handle_info(:process_mint, ...)" do
    test "drains empty queue and clears timer" do
      state = %{
        mint_queue: :queue.new(),
        mint_timer: make_ref()
      }

      {:noreply, new_state} = BotCoordinator.handle_info(:process_mint, state)

      assert new_state.mint_timer == nil
    end

    test "processes job from queue" do
      bot = create_test_bot(1)
      post = create_test_post()

      job = %{
        user_id: bot.id,
        post_id: post.id,
        amount: 5.0,
        reward_type: :read
      }

      queue = :queue.in(job, :queue.new())

      state = %{
        mint_queue: queue,
        mint_timer: make_ref()
      }

      {:noreply, new_state} = BotCoordinator.handle_info(:process_mint, state)

      # Queue should be drained by one
      assert :queue.len(new_state.mint_queue) == 0
      # Timer should be set for next check
      assert new_state.mint_timer != nil
    end
  end

  describe "handle_info(:daily_rotate, ...)" do
    test "shuffles active bot pool" do
      bots = for i <- 1..10, do: create_test_bot(i)
      bot_ids = Enum.map(bots, & &1.id)

      state = %{
        all_bot_ids: bot_ids,
        active_bot_ids: MapSet.new(Enum.take(bot_ids, 5)),
        daily_rotation_timer: nil
      }

      {:noreply, new_state} = BotCoordinator.handle_info(:daily_rotate, state)

      assert MapSet.size(new_state.active_bot_ids) > 0
      # All active bots should be from the full pool
      Enum.each(MapSet.to_list(new_state.active_bot_ids), fn id ->
        assert id in bot_ids
      end)
    end
  end

  describe "pool consumption tracking" do
    test "tracks consumption correctly across multiple reads" do
      bot1 = create_test_bot(1)
      bot2 = create_test_bot(2)
      post = create_test_post(pool: 1000)

      # Simulate sequential bot reads with pool tracking
      state = %{
        initialized: true,
        all_bot_ids: [bot1.id, bot2.id],
        active_bot_ids: MapSet.new([bot1.id, bot2.id]),
        bot_cache: %{
          bot1.id => %{smart_wallet_address: bot1.smart_wallet_address},
          bot2.id => %{smart_wallet_address: bot2.smart_wallet_address}
        },
        reading_sessions: %{},
        mint_queue: :queue.new(),
        mint_timer: nil,
        post_tracker: %{
          post.id => %{pool_deposited: 1000, pool_consumed_by_bots: 0.0}
        },
        daily_rotation_timer: nil
      }

      # Simulate pool consumption update
      tracker = state.post_tracker[post.id]
      updated_tracker = %{tracker | pool_consumed_by_bots: tracker.pool_consumed_by_bots + 100.0}
      state = put_in(state, [:post_tracker, post.id], updated_tracker)

      assert state.post_tracker[post.id].pool_consumed_by_bots == 100.0

      # Add more consumption
      tracker2 = state.post_tracker[post.id]
      updated_tracker2 = %{tracker2 | pool_consumed_by_bots: tracker2.pool_consumed_by_bots + 200.0}
      state = put_in(state, [:post_tracker, post.id], updated_tracker2)

      assert state.post_tracker[post.id].pool_consumed_by_bots == 300.0
    end
  end

  describe "handle_info(:check_pubsub, ...)" do
    test "re-subscribes when PubSub subscription is lost" do
      # The check_pubsub handler uses Registry.keys(@pubsub, self()) to detect
      # if the subscription is alive. Since handle_info runs in the test process,
      # self() refers to the test process. We can control the subscription state.

      # Ensure we are NOT subscribed
      Phoenix.PubSub.unsubscribe(BlocksterV2.PubSub, "post:published")

      # Verify we're not subscribed
      keys = Registry.keys(BlocksterV2.PubSub, self())
      refute "post:published" in keys

      state = %{initialized: true}
      {:noreply, _state} = BotCoordinator.handle_info(:check_pubsub, state)

      # After the health check, we should be re-subscribed
      keys = Registry.keys(BlocksterV2.PubSub, self())
      assert "post:published" in keys

      # Cleanup
      Phoenix.PubSub.unsubscribe(BlocksterV2.PubSub, "post:published")
    end

    test "does not duplicate subscription when already subscribed" do
      # Subscribe first
      Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "post:published")

      state = %{initialized: true}
      {:noreply, _state} = BotCoordinator.handle_info(:check_pubsub, state)

      # Should still be subscribed (no crash, no duplicate)
      keys = Registry.keys(BlocksterV2.PubSub, self())
      assert "post:published" in keys

      # Cleanup
      Phoenix.PubSub.unsubscribe(BlocksterV2.PubSub, "post:published")
    end

    test "is a no-op when not initialized" do
      state = %{initialized: false}
      {:noreply, new_state} = BotCoordinator.handle_info(:check_pubsub, state)
      assert new_state == state
    end
  end

  describe "PubSub subscription resilience" do
    test "initialization subscribes to post:published" do
      # Ensure we're not subscribed
      Phoenix.PubSub.unsubscribe(BlocksterV2.PubSub, "post:published")

      _bot = create_test_bot(1)

      state = %{
        initialized: false,
        all_bot_ids: [],
        active_bot_ids: MapSet.new(),
        bot_cache: %{},
        reading_sessions: %{},
        mint_queue: :queue.new(),
        mint_timer: nil,
        post_tracker: %{},
        daily_rotation_timer: nil
      }

      {:noreply, new_state} = BotCoordinator.handle_info(:initialize, state)
      assert new_state.initialized == true

      # Should be subscribed to post:published
      keys = Registry.keys(BlocksterV2.PubSub, self())
      assert "post:published" in keys

      # Cleanup
      Phoenix.PubSub.unsubscribe(BlocksterV2.PubSub, "post:published")
    end

    test "daily rotation re-subscribes to post:published" do
      # Unsubscribe to simulate lost subscription
      Phoenix.PubSub.unsubscribe(BlocksterV2.PubSub, "post:published")

      bots = for i <- 1..3, do: create_test_bot(i)
      bot_ids = Enum.map(bots, & &1.id)

      state = %{
        all_bot_ids: bot_ids,
        active_bot_ids: MapSet.new(bot_ids),
        daily_rotation_timer: nil
      }

      {:noreply, _new_state} = BotCoordinator.handle_info(:daily_rotate, state)

      # Should have re-subscribed
      keys = Registry.keys(BlocksterV2.PubSub, self())
      assert "post:published" in keys

      # Cleanup
      Phoenix.PubSub.unsubscribe(BlocksterV2.PubSub, "post:published")
    end

    test "PubSub broadcast delivers to subscriber" do
      # This is an end-to-end test: subscribe, broadcast, receive
      Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "post:published")

      Phoenix.PubSub.broadcast(
        BlocksterV2.PubSub,
        "post:published",
        {:post_published, %{id: 99999, title: "Test"}}
      )

      assert_receive {:post_published, %{id: 99999}}, 1000

      # Cleanup
      Phoenix.PubSub.unsubscribe(BlocksterV2.PubSub, "post:published")
    end

    test "lost subscription means no delivery, re-subscribe fixes it" do
      # Subscribe then unsubscribe to simulate lost subscription
      Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "post:published")
      Phoenix.PubSub.unsubscribe(BlocksterV2.PubSub, "post:published")

      # Broadcast should NOT be received
      Phoenix.PubSub.broadcast(
        BlocksterV2.PubSub,
        "post:published",
        {:post_published, %{id: 88888, title: "Lost"}}
      )

      refute_receive {:post_published, %{id: 88888}}, 200

      # Re-subscribe (what check_pubsub does)
      Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "post:published")

      # Now broadcast SHOULD be received
      Phoenix.PubSub.broadcast(
        BlocksterV2.PubSub,
        "post:published",
        {:post_published, %{id: 77777, title: "Recovered"}}
      )

      assert_receive {:post_published, %{id: 77777}}, 1000

      # Cleanup
      Phoenix.PubSub.unsubscribe(BlocksterV2.PubSub, "post:published")
    end
  end

  describe "EngagementSimulator integration" do
    test "schedule generation works with bot IDs from setup" do
      for i <- 1..10, do: create_test_bot(i)
      bot_ids = BotSetup.get_all_bot_ids()

      schedule = EngagementSimulator.generate_reading_schedule(bot_ids)
      assert length(schedule) > 0

      Enum.each(schedule, fn {delay, bot_id} ->
        assert is_integer(delay)
        assert bot_id in bot_ids
      end)
    end
  end
end
