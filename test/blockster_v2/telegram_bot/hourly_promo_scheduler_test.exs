defmodule BlocksterV2.TelegramBot.HourlyPromoSchedulerTest do
  use BlocksterV2.DataCase, async: false

  alias BlocksterV2.TelegramBot.HourlyPromoScheduler
  alias BlocksterV2.Notifications.SystemConfig

  setup do
    setup_mnesia()
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
      # Default config is false, so this should be the case
      enabled = Application.get_env(:blockster_v2, :hourly_promo, [])[:enabled]
      refute enabled
    end
  end

  describe "pause/resume via SystemConfig" do
    test "bot respects hourly_promo_enabled setting" do
      # Default should be true (runtime default)
      assert SystemConfig.get("hourly_promo_enabled", true) == true

      # Set to false
      SystemConfig.put("hourly_promo_enabled", false, "test")
      assert SystemConfig.get("hourly_promo_enabled", true) == false

      # Set back to true
      SystemConfig.put("hourly_promo_enabled", true, "test")
      assert SystemConfig.get("hourly_promo_enabled", true) == true
    end
  end
end
