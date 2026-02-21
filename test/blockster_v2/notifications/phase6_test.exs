defmodule BlocksterV2.Notifications.Phase6Test do
  use BlocksterV2.DataCase, async: true

  alias BlocksterV2.Notifications
  alias BlocksterV2.Notifications.NotificationPreference
  alias BlocksterV2.Blog

  # ============ Test Helpers ============

  defp create_user do
    {:ok, user} =
      BlocksterV2.Accounts.create_user_from_wallet(%{
        wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
        chain_id: 560013
      })

    user
  end

  defp create_hub do
    unique = System.unique_integer([:positive])

    {:ok, hub} =
      Blog.create_hub(%{
        name: "Test Hub #{unique}",
        slug: "test-hub-#{unique}",
        tag_name: "TESTHUB#{unique}",
        description: "A test hub",
        logo_url: "https://example.com/logo.png"
      })

    hub
  end

  # ============ Preference CRUD ============

  describe "preference management" do
    test "auto-creates preferences on user registration" do
      user = create_user()
      prefs = Notifications.get_preferences(user.id)
      refute is_nil(prefs)
      assert prefs.user_id == user.id
    end

    test "preferences have correct defaults" do
      user = create_user()
      prefs = Notifications.get_preferences(user.id)

      # Email defaults
      assert prefs.email_enabled == true
      assert prefs.email_new_articles == true
      assert prefs.email_hub_posts == true
      assert prefs.email_special_offers == true
      assert prefs.email_daily_digest == true
      assert prefs.email_weekly_roundup == true
      assert prefs.email_referral_prompts == true
      assert prefs.email_reward_alerts == true
      assert prefs.email_shop_deals == true
      assert prefs.email_account_updates == true
      assert prefs.email_re_engagement == true

      # SMS defaults
      assert prefs.sms_enabled == true
      assert prefs.sms_special_offers == true
      assert prefs.sms_account_alerts == true
      assert prefs.sms_milestone_rewards == false

      # In-app defaults
      assert prefs.in_app_enabled == true
      assert prefs.in_app_toast_enabled == true
      assert prefs.in_app_sound_enabled == false

      # Frequency defaults
      assert prefs.max_emails_per_day == 3
      assert prefs.max_sms_per_week == 1

      # Quiet hours defaults
      assert is_nil(prefs.quiet_hours_start)
      assert is_nil(prefs.quiet_hours_end)
      assert prefs.timezone == "UTC"
    end

    test "preferences have an unsubscribe token" do
      user = create_user()
      prefs = Notifications.get_preferences(user.id)
      refute is_nil(prefs.unsubscribe_token)
      assert byte_size(prefs.unsubscribe_token) > 20
    end

    test "get_or_create_preferences returns existing prefs" do
      user = create_user()
      {:ok, prefs1} = Notifications.get_or_create_preferences(user.id)
      {:ok, prefs2} = Notifications.get_or_create_preferences(user.id)
      assert prefs1.id == prefs2.id
    end
  end

  # ============ Toggle Email Preferences ============

  describe "email preference toggles" do
    test "toggles email_enabled off" do
      user = create_user()
      {:ok, prefs} = Notifications.update_preferences(user.id, %{email_enabled: false})
      assert prefs.email_enabled == false
    end

    test "toggles email_enabled back on" do
      user = create_user()
      {:ok, _} = Notifications.update_preferences(user.id, %{email_enabled: false})
      {:ok, prefs} = Notifications.update_preferences(user.id, %{email_enabled: true})
      assert prefs.email_enabled == true
    end

    test "toggles individual email preferences" do
      user = create_user()

      {:ok, prefs} = Notifications.update_preferences(user.id, %{email_hub_posts: false})
      assert prefs.email_hub_posts == false

      {:ok, prefs} = Notifications.update_preferences(user.id, %{email_daily_digest: false})
      assert prefs.email_daily_digest == false

      {:ok, prefs} = Notifications.update_preferences(user.id, %{email_special_offers: false})
      assert prefs.email_special_offers == false
    end

    test "toggles multiple email preferences at once" do
      user = create_user()

      {:ok, prefs} =
        Notifications.update_preferences(user.id, %{
          email_new_articles: false,
          email_referral_prompts: false,
          email_re_engagement: false
        })

      assert prefs.email_new_articles == false
      assert prefs.email_referral_prompts == false
      assert prefs.email_re_engagement == false
      # Others unchanged
      assert prefs.email_hub_posts == true
    end
  end

  # ============ Toggle SMS Preferences ============

  describe "SMS preference toggles" do
    test "toggles sms_enabled off" do
      user = create_user()
      {:ok, prefs} = Notifications.update_preferences(user.id, %{sms_enabled: false})
      assert prefs.sms_enabled == false
    end

    test "toggles individual SMS preferences" do
      user = create_user()

      {:ok, prefs} = Notifications.update_preferences(user.id, %{sms_special_offers: false})
      assert prefs.sms_special_offers == false

      {:ok, prefs} = Notifications.update_preferences(user.id, %{sms_account_alerts: false})
      assert prefs.sms_account_alerts == false
    end

    test "enables sms_milestone_rewards (default off)" do
      user = create_user()
      prefs = Notifications.get_preferences(user.id)
      assert prefs.sms_milestone_rewards == false

      {:ok, prefs} = Notifications.update_preferences(user.id, %{sms_milestone_rewards: true})
      assert prefs.sms_milestone_rewards == true
    end
  end

  # ============ In-App Preferences ============

  describe "in-app preference toggles" do
    test "toggles in_app_enabled" do
      user = create_user()
      {:ok, prefs} = Notifications.update_preferences(user.id, %{in_app_enabled: false})
      assert prefs.in_app_enabled == false
    end

    test "toggles toast and sound" do
      user = create_user()

      {:ok, prefs} = Notifications.update_preferences(user.id, %{in_app_toast_enabled: false})
      assert prefs.in_app_toast_enabled == false

      {:ok, prefs} = Notifications.update_preferences(user.id, %{in_app_sound_enabled: true})
      assert prefs.in_app_sound_enabled == true
    end
  end

  # ============ Frequency Controls ============

  describe "frequency controls" do
    test "updates max_emails_per_day" do
      user = create_user()
      {:ok, prefs} = Notifications.update_preferences(user.id, %{max_emails_per_day: 5})
      assert prefs.max_emails_per_day == 5
    end

    test "validates max_emails_per_day range" do
      user = create_user()

      # Too low
      {:error, changeset} = Notifications.update_preferences(user.id, %{max_emails_per_day: 0})
      assert errors_on(changeset)[:max_emails_per_day]

      # Too high
      {:error, changeset} = Notifications.update_preferences(user.id, %{max_emails_per_day: 11})
      assert errors_on(changeset)[:max_emails_per_day]
    end

    test "updates max_sms_per_week" do
      user = create_user()
      {:ok, prefs} = Notifications.update_preferences(user.id, %{max_sms_per_week: 3})
      assert prefs.max_sms_per_week == 3
    end

    test "validates max_sms_per_week range" do
      user = create_user()

      {:error, changeset} = Notifications.update_preferences(user.id, %{max_sms_per_week: 6})
      assert errors_on(changeset)[:max_sms_per_week]
    end
  end

  # ============ Quiet Hours ============

  describe "quiet hours" do
    test "sets quiet hours" do
      user = create_user()

      {:ok, prefs} =
        Notifications.update_preferences(user.id, %{
          quiet_hours_start: ~T[22:00:00],
          quiet_hours_end: ~T[08:00:00]
        })

      assert prefs.quiet_hours_start == ~T[22:00:00]
      assert prefs.quiet_hours_end == ~T[08:00:00]
    end

    test "clears quiet hours" do
      user = create_user()

      {:ok, _} =
        Notifications.update_preferences(user.id, %{
          quiet_hours_start: ~T[22:00:00],
          quiet_hours_end: ~T[08:00:00]
        })

      {:ok, prefs} =
        Notifications.update_preferences(user.id, %{
          quiet_hours_start: nil,
          quiet_hours_end: nil
        })

      assert is_nil(prefs.quiet_hours_start)
      assert is_nil(prefs.quiet_hours_end)
    end

    test "updates timezone" do
      user = create_user()
      {:ok, prefs} = Notifications.update_preferences(user.id, %{timezone: "US/Eastern"})
      assert prefs.timezone == "US/Eastern"
    end
  end

  # ============ Per-Hub Notification Settings ============

  describe "per-hub notification settings" do
    test "gets user's followed hubs with settings" do
      user = create_user()
      hub1 = create_hub()
      hub2 = create_hub()

      {:ok, _} = Blog.follow_hub(user.id, hub1.id)
      {:ok, _} = Blog.follow_hub(user.id, hub2.id)

      hubs_with_settings = Blog.get_user_followed_hubs_with_settings(user.id)

      assert length(hubs_with_settings) == 2

      entry = Enum.find(hubs_with_settings, fn e -> e.hub.id == hub1.id end)
      assert entry.hub.name == hub1.name
      assert entry.follower.notify_new_posts == true
      assert entry.follower.email_notifications == true
    end

    test "returns empty list when no hubs followed" do
      user = create_user()
      assert Blog.get_user_followed_hubs_with_settings(user.id) == []
    end

    test "updates per-hub notification setting" do
      user = create_user()
      hub = create_hub()
      {:ok, _} = Blog.follow_hub(user.id, hub.id)

      {:ok, updated} =
        Blog.update_hub_follow_notifications(user.id, hub.id, %{notify_new_posts: false})

      assert updated.notify_new_posts == false
    end

    test "updates multiple per-hub settings" do
      user = create_user()
      hub = create_hub()
      {:ok, _} = Blog.follow_hub(user.id, hub.id)

      {:ok, updated} =
        Blog.update_hub_follow_notifications(user.id, hub.id, %{
          notify_new_posts: false,
          email_notifications: false
        })

      assert updated.notify_new_posts == false
      assert updated.email_notifications == false
      # Unchanged
      assert updated.notify_events == true
      assert updated.in_app_notifications == true
    end

    test "returns error when hub not followed" do
      user = create_user()
      hub = create_hub()

      assert {:error, :not_found} =
               Blog.update_hub_follow_notifications(user.id, hub.id, %{notify_new_posts: false})
    end

    test "isolates hub settings between users" do
      user1 = create_user()
      user2 = create_user()
      hub = create_hub()

      {:ok, _} = Blog.follow_hub(user1.id, hub.id)
      {:ok, _} = Blog.follow_hub(user2.id, hub.id)

      {:ok, _} = Blog.update_hub_follow_notifications(user1.id, hub.id, %{notify_new_posts: false})

      # User2's settings unchanged
      hubs = Blog.get_user_followed_hubs_with_settings(user2.id)
      entry = hd(hubs)
      assert entry.follower.notify_new_posts == true
    end
  end

  # ============ Unsubscribe All ============

  describe "unsubscribe all" do
    test "unsubscribe_all disables email and SMS" do
      user = create_user()
      prefs = Notifications.get_preferences(user.id)

      {:ok, updated} = Notifications.unsubscribe_all(prefs.unsubscribe_token)
      assert updated.email_enabled == false
      assert updated.sms_enabled == false
    end

    test "unsubscribe_all with invalid token returns error" do
      assert {:error, :not_found} = Notifications.unsubscribe_all("invalid_token_abc123")
    end

    test "find_by_unsubscribe_token finds correct preferences" do
      user = create_user()
      prefs = Notifications.get_preferences(user.id)

      found = Notifications.find_by_unsubscribe_token(prefs.unsubscribe_token)
      assert found.id == prefs.id
      assert found.user_id == user.id
    end

    test "find_by_unsubscribe_token returns nil for invalid token" do
      assert is_nil(Notifications.find_by_unsubscribe_token("nonexistent_token"))
    end
  end

  # ============ Unsubscribe Token Generation ============

  describe "unsubscribe token" do
    test "generates unique tokens" do
      token1 = NotificationPreference.generate_unsubscribe_token()
      token2 = NotificationPreference.generate_unsubscribe_token()
      refute token1 == token2
    end

    test "generates URL-safe tokens" do
      token = NotificationPreference.generate_unsubscribe_token()
      # URL-safe base64 should only contain alphanumeric, -, and _
      assert Regex.match?(~r/^[A-Za-z0-9_-]+$/, token)
    end
  end

  # ============ Settings LiveView Module ============

  describe "NotificationSettingsLive.Index module" do
    test "module exists and compiles" do
      assert Code.ensure_loaded?(BlocksterV2Web.NotificationSettingsLive.Index)
    end
  end

  # ============ Unsubscribe Controller ============

  describe "UnsubscribeController module" do
    test "module exists and compiles" do
      assert Code.ensure_loaded?(BlocksterV2Web.UnsubscribeController)
    end
  end

  # ============ Preference Isolation ============

  describe "preference isolation" do
    test "preferences are isolated between users" do
      user1 = create_user()
      user2 = create_user()

      {:ok, _} = Notifications.update_preferences(user1.id, %{email_enabled: false})

      prefs2 = Notifications.get_preferences(user2.id)
      assert prefs2.email_enabled == true
    end

    test "each user has a unique unsubscribe token" do
      user1 = create_user()
      user2 = create_user()

      prefs1 = Notifications.get_preferences(user1.id)
      prefs2 = Notifications.get_preferences(user2.id)

      refute prefs1.unsubscribe_token == prefs2.unsubscribe_token
    end
  end
end
