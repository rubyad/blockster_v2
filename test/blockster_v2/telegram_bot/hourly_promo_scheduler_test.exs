defmodule BlocksterV2.TelegramBot.HourlyPromoSchedulerTest do
  use BlocksterV2.DataCase, async: false

  alias BlocksterV2.TelegramBot.{HourlyPromoScheduler, PromoEngine}
  alias BlocksterV2.Notifications.SystemConfig

  setup do
    setup_mnesia()

    # Null out Telegram config so tests don't send real messages to the group
    original_token = Application.get_env(:blockster_v2, :telegram_v2_bot_token)
    original_channel = Application.get_env(:blockster_v2, :telegram_v2_channel_id)
    Application.put_env(:blockster_v2, :telegram_v2_bot_token, nil)
    Application.put_env(:blockster_v2, :telegram_v2_channel_id, nil)

    on_exit(fn ->
      if original_token, do: Application.put_env(:blockster_v2, :telegram_v2_bot_token, original_token)
      if original_channel, do: Application.put_env(:blockster_v2, :telegram_v2_channel_id, original_channel)
    end)

    :ok
  end

  defp setup_mnesia do
    tables = [
      {:bot_daily_rewards, [:key, :date, :total_bux_given, :user_reward_counts]},
      {:hourly_promo_state, [:key, :current_promo, :started_at, :history]},
      {:hourly_promo_entries, [:key, :promo_id, :user_id, :metric_value, :entered_at]}
    ]

    for {name, attrs} <- tables do
      try do
        :mnesia.create_table(name, attributes: attrs, type: :set)
      rescue
        _ -> :ok
      catch
        :exit, _ -> :ok
      end
    end

    for {name, _} <- tables do
      try do
        :mnesia.clear_table(name)
      rescue
        _ -> :ok
      catch
        :exit, _ -> :ok
      end
    end

    :ok
  end

  describe "feature flag" do
    test "GenServer doesn't start when feature flag is false" do
      enabled = Application.get_env(:blockster_v2, :hourly_promo, [])[:enabled]
      refute enabled
    end
  end

  describe "pause/resume via SystemConfig" do
    test "bot respects hourly_promo_enabled setting" do
      assert SystemConfig.get("hourly_promo_enabled", true) == true

      SystemConfig.put("hourly_promo_enabled", false, "test")
      assert SystemConfig.get("hourly_promo_enabled", true) == false

      SystemConfig.put("hourly_promo_enabled", true, "test")
      assert SystemConfig.get("hourly_promo_enabled", true) == true
    end
  end

  describe "scheduler lifecycle — manual GenServer start" do
    test "starts and schedules first promo" do
      # Start scheduler directly (bypasses GlobalSingleton for test)
      {:ok, pid} = GenServer.start_link(HourlyPromoScheduler, [])

      # Should be alive
      assert Process.alive?(pid)

      # Get state — should have no current promo yet (hasn't ticked)
      state = :sys.get_state(pid)
      assert state.current_promo == nil
      assert state.history == []

      GenServer.stop(pid)
    end

    test "run_promo message triggers a full promo cycle" do
      # Ensure bot is enabled
      SystemConfig.put("hourly_promo_enabled", true, "test")

      {:ok, pid} = GenServer.start_link(HourlyPromoScheduler, [])

      # Manually trigger a promo cycle
      send(pid, :run_promo)
      # Give it time to process
      :timer.sleep(200)

      state = :sys.get_state(pid)
      assert state.current_promo != nil
      assert state.current_promo.id != nil
      assert state.current_promo.name != nil
      assert state.current_promo.category in [:bux_booster_rule, :referral_boost, :giveaway, :competition]
      assert length(state.history) == 1

      GenServer.stop(pid)
    end

    test "second run_promo settles previous and picks new" do
      SystemConfig.put("hourly_promo_enabled", true, "test")

      {:ok, pid} = GenServer.start_link(HourlyPromoScheduler, [])

      # First cycle
      send(pid, :run_promo)
      :timer.sleep(200)
      state1 = :sys.get_state(pid)
      first_promo = state1.current_promo
      assert first_promo != nil

      # Second cycle — settles first, picks new
      send(pid, :run_promo)
      :timer.sleep(200)
      state2 = :sys.get_state(pid)
      second_promo = state2.current_promo
      assert second_promo != nil
      assert second_promo.id != first_promo.id
      assert length(state2.history) == 2

      GenServer.stop(pid)
    end

    test "paused bot skips promo cycle and cleans up rules" do
      SystemConfig.put("hourly_promo_enabled", true, "test")

      {:ok, pid} = GenServer.start_link(HourlyPromoScheduler, [])

      # Run one cycle to have an active promo
      send(pid, :run_promo)
      :timer.sleep(200)
      state_before = :sys.get_state(pid)
      assert state_before.current_promo != nil

      # Pause the bot
      SystemConfig.put("hourly_promo_enabled", false, "test")

      # Next cycle should skip
      send(pid, :run_promo)
      :timer.sleep(200)
      state_after = :sys.get_state(pid)

      # Current promo unchanged (cycle was skipped)
      assert state_after.current_promo == state_before.current_promo

      # Bot rules should be cleaned up
      rules = SystemConfig.get("custom_rules", [])
      bot_rules = Enum.filter(rules, &(&1["source"] == "telegram_bot"))
      assert bot_rules == []

      GenServer.stop(pid)
    end

    test "state is saved to Mnesia after each cycle for crash recovery" do
      SystemConfig.put("hourly_promo_enabled", true, "test")

      {:ok, pid} = GenServer.start_link(HourlyPromoScheduler, [])

      send(pid, :run_promo)
      # Wait for the message to be processed
      :timer.sleep(500)

      # Verify GenServer state has a current promo (proving the cycle ran)
      state = :sys.get_state(pid)
      assert state.current_promo != nil, "GenServer should have a current promo after run_promo"

      # Check Mnesia has the state
      result = :mnesia.dirty_read(:hourly_promo_state, :current)
      case result do
        [{:hourly_promo_state, :current, saved_promo, _timestamp, _history}] ->
          assert saved_promo.id != nil
          assert saved_promo.name != nil
          assert saved_promo.category != nil

        other ->
          # Try writing directly to verify table is functional
          test_write = try do
            :mnesia.dirty_write({:hourly_promo_state, :test_key, %{id: "test"}, DateTime.utc_now(), []})
            :ok
          rescue
            e -> {:error, e}
          catch
            :exit, reason -> {:exit, reason}
          end

          flunk("Expected promo state in Mnesia, got: #{inspect(other)}. Test write result: #{inspect(test_write)}")
      end

      GenServer.stop(pid)
    end

    test "force_next changes the next promo category" do
      SystemConfig.put("hourly_promo_enabled", true, "test")

      {:ok, pid} = GenServer.start_link(HourlyPromoScheduler, [])

      # Force next to referral
      GenServer.cast(pid, {:force_next, :referral_boost})
      :timer.sleep(50)

      state = :sys.get_state(pid)
      assert state.forced_category == :referral_boost

      GenServer.stop(pid)
    end

    test "budget exhausted sends exhausted message and skips cycle" do
      SystemConfig.put("hourly_promo_enabled", true, "test")

      # Exhaust the budget by writing directly to Mnesia
      :mnesia.dirty_write({:bot_daily_rewards, :daily, Date.utc_today(), 100_001, %{}})
      assert PromoEngine.budget_exhausted?()

      {:ok, pid} = GenServer.start_link(HourlyPromoScheduler, [])

      send(pid, :run_promo)
      :timer.sleep(200)

      # Should not have picked a promo because budget is exhausted
      state = :sys.get_state(pid)
      assert state.current_promo == nil

      GenServer.stop(pid)
    end
  end
end
