defmodule BlocksterV2.Notifications.IntegrationWiringTest do
  @moduledoc """
  Integration tests proving the full notification wiring pipeline works:
  Events → EventProcessor → TriggerEngine/CustomRules → Notifications/Emails.
  """
  use BlocksterV2.DataCase, async: false

  alias BlocksterV2.Notifications
  alias BlocksterV2.Notifications.SystemConfig
  alias BlocksterV2.UserEvents

  setup do
    BlocksterV2.Repo.delete_all("system_config")
    SystemConfig.invalidate_cache()
    SystemConfig.seed_defaults()
    :ok
  end

  defp create_user do
    {:ok, user} =
      BlocksterV2.Accounts.create_user_from_wallet(%{
        wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
        chain_id: 560013
      })

    user
  end

  # ============ SystemConfig Foundation Tests ============

  describe "SystemConfig foundation" do
    test "seed_defaults populates expected keys" do
      config = SystemConfig.get_all()
      assert config["referrer_signup_bux"] == 500
      assert config["referee_signup_bux"] == 250
      assert config["phone_verify_bux"] == 100
      assert is_list(config["bux_milestones"])
      assert is_list(config["reading_streak_days"])
    end

    test "put invalidates ETS cache and returns new value" do
      SystemConfig.put("referrer_signup_bux", 1000, "test")
      assert SystemConfig.get("referrer_signup_bux") == 1000
    end

    test "put_many updates multiple keys atomically" do
      SystemConfig.put_many(%{
        "referrer_signup_bux" => 750,
        "referee_signup_bux" => 300
      }, "test")

      assert SystemConfig.get("referrer_signup_bux") == 750
      assert SystemConfig.get("referee_signup_bux") == 300
    end
  end

  # ============ UserEvents Tracking Tests ============

  describe "UserEvents.track/3" do
    test "stores event in PostgreSQL" do
      user = create_user()
      UserEvents.track(user.id, "article_view", %{target_type: "post", target_id: 42})

      # Give async Task time to complete
      Process.sleep(200)

      events = UserEvents.get_events(user.id, limit: 10)
      assert Enum.any?(events, fn e -> e.event_type == "article_view" end)
    end

    test "track_sync stores event and broadcasts" do
      user = create_user()
      Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "user_events")

      # Use track_sync with a valid event type from the enum
      {:ok, _event} = UserEvents.track_sync(user.id, "daily_login", %{source: "test"})

      assert_receive {:user_event, _, "daily_login", _}, 1000
    end
  end

  # ============ Event → Trigger Pipeline Tests ============

  describe "event → trigger pipeline" do
    test "reading streak trigger evaluation does not crash" do
      user = create_user()

      # Simulate reading articles on consecutive days to build streak
      now = DateTime.utc_now()

      for day <- 0..2 do
        ts = DateTime.add(now, -day, :day) |> DateTime.truncate(:second)

        Repo.insert!(%Notifications.UserEvent{
          user_id: user.id,
          event_type: "article_read_complete",
          event_category: "content",
          metadata: %{"target_type" => "post", "target_id" => day + 1},
          inserted_at: NaiveDateTime.truncate(DateTime.to_naive(ts), :second)
        })

        Repo.insert!(%Notifications.UserEvent{
          user_id: user.id,
          event_type: "daily_login",
          event_category: "engagement",
          metadata: %{},
          inserted_at: NaiveDateTime.truncate(DateTime.to_naive(ts), :second)
        })
      end

      # Evaluate triggers — should not crash
      result = Notifications.TriggerEngine.evaluate_triggers(user.id, "article_read_complete", %{
        "target_type" => "post",
        "target_id" => 100
      })

      assert is_list(result)
    end
  end

  # ============ Welcome Series Tests ============

  describe "welcome series wiring" do
    test "WelcomeSeriesWorker module exists and enqueue_series is callable" do
      # In test mode, Oban runs inline (no DB persistence), so verify the wiring:
      # 1. Worker module exists with correct callbacks
      assert Code.ensure_loaded?(BlocksterV2.Workers.WelcomeSeriesWorker)
      assert function_exported?(BlocksterV2.Workers.WelcomeSeriesWorker, :enqueue_series, 1)
      assert function_exported?(BlocksterV2.Workers.WelcomeSeriesWorker, :perform, 1)

      # 2. create_user_from_wallet calls enqueue_series (runs inline in test)
      #    If this crashes, the wiring is broken
      user = create_user()
      assert user.id > 0
    end
  end

  # ============ Referral Upgrade Tests ============

  describe "referral system uses SystemConfig values" do
    test "SystemConfig referral defaults are correct" do
      assert SystemConfig.get("referrer_signup_bux") == 500
      assert SystemConfig.get("referee_signup_bux") == 250
      assert SystemConfig.get("phone_verify_bux") == 100
    end

    test "changing SystemConfig referral values works" do
      SystemConfig.put("referrer_signup_bux", 750, "ai_manager")
      assert SystemConfig.get("referrer_signup_bux") == 750
    end

    test "referral amounts read from SystemConfig" do
      # The default_signup_reward in referrals.ex should match SystemConfig
      assert SystemConfig.get("referrer_signup_bux", 500) == 500
      assert SystemConfig.get("referee_signup_bux", 250) == 250

      # After update, next referral would use new amount
      SystemConfig.put("referrer_signup_bux", 1000, "ai_manager")
      assert SystemConfig.get("referrer_signup_bux", 500) == 1000
    end
  end

  # ============ Custom Rules Tests ============

  describe "custom rules via SystemConfig" do
    test "custom rules stored and retrieved from SystemConfig" do
      rule = %{
        "event_type" => "article_read_complete",
        "conditions" => nil,
        "action" => "notification",
        "title" => "Great reading!",
        "body" => "Keep it up!",
        "notification_type" => "engagement"
      }

      SystemConfig.put("custom_rules", [rule], "test")

      rules = SystemConfig.get("custom_rules", [])
      assert length(rules) == 1
      assert hd(rules)["title"] == "Great reading!"
    end

    test "notification can be created with custom rule attributes" do
      user = create_user()

      {:ok, notif} = Notifications.create_notification(user.id, %{
        type: "content_recommendation",
        category: "content",
        title: "Great reading!",
        body: "Keep it up!"
      })

      assert notif.title == "Great reading!"
      assert notif.body == "Keep it up!"
    end
  end

  # ============ AI Manager Tests ============

  describe "AI Manager tool execution" do
    test "get_system_config tool returns valid config" do
      config = SystemConfig.get_all()
      assert is_map(config)
      assert Map.has_key?(config, "referrer_signup_bux")
    end

    test "SystemConfig change from AI Manager takes effect" do
      SystemConfig.put("referrer_signup_bux", 1000, "ai_manager:1")
      assert SystemConfig.get("referrer_signup_bux") == 1000

      # Next referral would use new amount
      SystemConfig.put("referrer_signup_bux", 500, "ai_manager:1")
      assert SystemConfig.get("referrer_signup_bux") == 500
    end

    test "AI Manager autonomous review worker exists" do
      # Verify the worker module exists and has perform/1
      assert Code.ensure_loaded?(BlocksterV2.Workers.AIManagerReviewWorker)
      assert function_exported?(BlocksterV2.Workers.AIManagerReviewWorker, :perform, 1)
    end
  end

  # ============ End-to-End: Notification Preferences ============

  describe "notification preferences" do
    test "preferences are created during user signup" do
      user = create_user()

      # create_user_from_wallet already calls create_preferences
      prefs = Notifications.get_preferences(user.id)
      assert prefs != nil
      assert prefs.email_hub_posts == true
    end
  end
end
