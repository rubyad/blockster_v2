defmodule BlocksterV2.Notifications.Phase10Test do
  use BlocksterV2.DataCase, async: false

  alias BlocksterV2.{Notifications, Repo}
  alias BlocksterV2.Notifications.{EmailLog, EngagementScorer, Campaign}

  # ============ Test Helpers ============

  defp create_user(attrs \\ %{}) do
    wallet = "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}"

    {:ok, user} =
      BlocksterV2.Accounts.create_user_from_wallet(%{
        wallet_address: wallet,
        chain_id: 560013
      })

    email = Map.get(attrs, :email, "user_#{user.id}@test.com")
    username = Map.get(attrs, :username, "TestUser#{user.id}")

    user
    |> Ecto.Changeset.change(%{email: email, username: username})
    |> Repo.update!()
  end

  defp create_user_with_prefs(pref_overrides \\ %{}) do
    user = create_user()
    {:ok, prefs} = Notifications.get_or_create_preferences(user.id)

    if pref_overrides != %{} do
      {:ok, prefs} = Notifications.update_preferences(user.id, pref_overrides)
      {user, prefs}
    else
      {user, prefs}
    end
  end

  defp create_email_log(user_id, attrs \\ %{}) do
    base = %{
      user_id: user_id,
      email_type: "promotional",
      subject: "Test Email",
      sent_at: DateTime.utc_now() |> DateTime.truncate(:second),
      sendgrid_message_id: "sg_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"
    }

    {:ok, log} = Notifications.create_email_log(Map.merge(base, attrs))
    log
  end

  defp create_campaign(attrs \\ %{}) do
    base = %{
      name: "Test Campaign #{System.unique_integer([:positive])}",
      type: "email_blast",
      status: "sent"
    }

    {:ok, campaign} = Notifications.create_campaign(Map.merge(base, attrs))
    campaign
  end

  defp send_webhook(events) do
    Plug.Test.conn(:post, "/api/webhooks/sendgrid", Jason.encode!(events))
    |> Plug.Conn.put_req_header("content-type", "application/json")
    |> BlocksterV2Web.Endpoint.call(BlocksterV2Web.Endpoint.init([]))
  end

  # ============ SendGrid Webhook Tests ============

  describe "SendGrid webhook — open event" do
    test "updates opened_at on email_log" do
      {user, _} = create_user_with_prefs()
      log = create_email_log(user.id)

      conn = send_webhook([%{
        "event" => "open",
        "sg_message_id" => log.sendgrid_message_id,
        "timestamp" => DateTime.utc_now() |> DateTime.to_unix()
      }])

      assert conn.status == 200

      updated = Repo.get!(EmailLog, log.id)
      assert updated.opened_at != nil
    end

    test "only sets opened_at on first open" do
      {user, _} = create_user_with_prefs()
      first_time = DateTime.utc_now() |> DateTime.add(-3600) |> DateTime.truncate(:second)
      log = create_email_log(user.id)

      # First open
      log |> Ecto.Changeset.change(%{opened_at: first_time}) |> Repo.update!()

      # Second open should not overwrite
      send_webhook([%{
        "event" => "open",
        "sg_message_id" => log.sendgrid_message_id,
        "timestamp" => DateTime.utc_now() |> DateTime.to_unix()
      }])

      updated = Repo.get!(EmailLog, log.id)
      assert DateTime.compare(updated.opened_at, first_time) == :eq
    end

    test "increments campaign emails_opened" do
      campaign = create_campaign()
      {user, _} = create_user_with_prefs()
      log = create_email_log(user.id, %{campaign_id: campaign.id})

      send_webhook([%{
        "event" => "open",
        "sg_message_id" => log.sendgrid_message_id,
        "timestamp" => DateTime.utc_now() |> DateTime.to_unix()
      }])

      updated_campaign = Repo.get!(Campaign, campaign.id)
      assert updated_campaign.emails_opened == 1
    end
  end

  describe "SendGrid webhook — click event" do
    test "updates clicked_at on email_log" do
      {user, _} = create_user_with_prefs()
      log = create_email_log(user.id)

      send_webhook([%{
        "event" => "click",
        "sg_message_id" => log.sendgrid_message_id,
        "timestamp" => DateTime.utc_now() |> DateTime.to_unix()
      }])

      updated = Repo.get!(EmailLog, log.id)
      assert updated.clicked_at != nil
    end

    test "also sets opened_at if not already set" do
      {user, _} = create_user_with_prefs()
      log = create_email_log(user.id)

      send_webhook([%{
        "event" => "click",
        "sg_message_id" => log.sendgrid_message_id,
        "timestamp" => DateTime.utc_now() |> DateTime.to_unix()
      }])

      updated = Repo.get!(EmailLog, log.id)
      assert updated.opened_at != nil
      assert updated.clicked_at != nil
    end

    test "increments campaign emails_clicked" do
      campaign = create_campaign()
      {user, _} = create_user_with_prefs()
      log = create_email_log(user.id, %{campaign_id: campaign.id})

      send_webhook([%{
        "event" => "click",
        "sg_message_id" => log.sendgrid_message_id,
        "timestamp" => DateTime.utc_now() |> DateTime.to_unix()
      }])

      updated_campaign = Repo.get!(Campaign, campaign.id)
      assert updated_campaign.emails_clicked == 1
    end
  end

  describe "SendGrid webhook — bounce event" do
    test "marks email_log as bounced" do
      {user, _} = create_user_with_prefs()
      log = create_email_log(user.id)

      send_webhook([%{
        "event" => "bounce",
        "sg_message_id" => log.sendgrid_message_id,
        "timestamp" => DateTime.utc_now() |> DateTime.to_unix()
      }])

      updated = Repo.get!(EmailLog, log.id)
      assert updated.bounced == true
    end

    test "auto-suppresses email for bounced user" do
      {user, _} = create_user_with_prefs()
      log = create_email_log(user.id)

      send_webhook([%{
        "event" => "bounce",
        "sg_message_id" => log.sendgrid_message_id,
        "timestamp" => DateTime.utc_now() |> DateTime.to_unix()
      }])

      prefs = Notifications.get_preferences(user.id)
      refute prefs.email_enabled
    end
  end

  describe "SendGrid webhook — spam_report event" do
    test "marks as bounced and unsubscribed" do
      {user, _} = create_user_with_prefs()
      log = create_email_log(user.id)

      send_webhook([%{
        "event" => "spam_report",
        "sg_message_id" => log.sendgrid_message_id,
        "timestamp" => DateTime.utc_now() |> DateTime.to_unix()
      }])

      updated = Repo.get!(EmailLog, log.id)
      assert updated.bounced == true
      assert updated.unsubscribed == true
    end

    test "auto-unsubscribes from all marketing" do
      {user, _} = create_user_with_prefs()
      log = create_email_log(user.id)

      send_webhook([%{
        "event" => "spam_report",
        "sg_message_id" => log.sendgrid_message_id,
        "timestamp" => DateTime.utc_now() |> DateTime.to_unix()
      }])

      prefs = Notifications.get_preferences(user.id)
      refute prefs.email_enabled
      refute prefs.email_special_offers
      refute prefs.email_daily_digest
      refute prefs.email_re_engagement
    end
  end

  describe "SendGrid webhook — unsubscribe event" do
    test "marks email_log as unsubscribed" do
      {user, _} = create_user_with_prefs()
      log = create_email_log(user.id)

      send_webhook([%{
        "event" => "unsubscribe",
        "sg_message_id" => log.sendgrid_message_id,
        "timestamp" => DateTime.utc_now() |> DateTime.to_unix()
      }])

      updated = Repo.get!(EmailLog, log.id)
      assert updated.unsubscribed == true
    end

    test "disables email in user preferences" do
      {user, _} = create_user_with_prefs()
      log = create_email_log(user.id)

      send_webhook([%{
        "event" => "unsubscribe",
        "sg_message_id" => log.sendgrid_message_id,
        "timestamp" => DateTime.utc_now() |> DateTime.to_unix()
      }])

      prefs = Notifications.get_preferences(user.id)
      refute prefs.email_enabled
    end
  end

  describe "SendGrid webhook — edge cases" do
    test "handles unknown message ID gracefully" do
      conn = send_webhook([%{
        "event" => "open",
        "sg_message_id" => "nonexistent_message_id",
        "timestamp" => DateTime.utc_now() |> DateTime.to_unix()
      }])

      assert conn.status == 200
    end

    test "handles empty events array" do
      conn = send_webhook([])
      assert conn.status == 200
    end

    test "handles multiple events in single webhook" do
      {user, _} = create_user_with_prefs()
      log1 = create_email_log(user.id)
      log2 = create_email_log(user.id)

      conn = send_webhook([
        %{"event" => "open", "sg_message_id" => log1.sendgrid_message_id, "timestamp" => DateTime.utc_now() |> DateTime.to_unix()},
        %{"event" => "click", "sg_message_id" => log2.sendgrid_message_id, "timestamp" => DateTime.utc_now() |> DateTime.to_unix()}
      ])

      assert conn.status == 200

      assert Repo.get!(EmailLog, log1.id).opened_at != nil
      assert Repo.get!(EmailLog, log2.id).clicked_at != nil
    end

    test "handles unknown event type" do
      conn = send_webhook([%{
        "event" => "unknown_event",
        "sg_message_id" => "some_id"
      }])

      assert conn.status == 200
    end

    test "strips .filter suffix from sg_message_id" do
      {user, _} = create_user_with_prefs()
      log = create_email_log(user.id)

      send_webhook([%{
        "event" => "open",
        "sg_message_id" => "#{log.sendgrid_message_id}.filter0307p1mdw1-2166-6422E04E-15.0",
        "timestamp" => DateTime.utc_now() |> DateTime.to_unix()
      }])

      updated = Repo.get!(EmailLog, log.id)
      assert updated.opened_at != nil
    end
  end

  # ============ Engagement Scorer Tests ============

  describe "EngagementScorer.calculate_score/1" do
    test "returns engagement metrics for a user" do
      {user, _} = create_user_with_prefs()

      # Create some email logs
      for _ <- 1..5 do
        create_email_log(user.id)
      end

      # Mark some as opened/clicked
      Repo.all(from l in EmailLog, where: l.user_id == ^user.id, limit: 3)
      |> Enum.each(fn log ->
        log |> Ecto.Changeset.change(%{opened_at: DateTime.utc_now() |> DateTime.truncate(:second)}) |> Repo.update!()
      end)

      score = EngagementScorer.calculate_score(user.id)

      assert is_float(score.email_open_rate)
      assert is_float(score.email_click_rate)
      assert score.emails_sent == 5
      assert score.emails_opened == 3
      assert score.email_open_rate == 0.6
      assert is_integer(score.preferred_hour)
      assert is_list(score.preferred_categories)
      assert score.engagement_tier in [:highly_engaged, :moderately_engaged, :low_engagement, :dormant]
    end

    test "handles user with no activity" do
      {user, _} = create_user_with_prefs()
      score = EngagementScorer.calculate_score(user.id)

      assert score.emails_sent == 0
      assert score.email_open_rate == 0.0
      assert score.in_app_read_rate == 0.0
      assert score.engagement_tier == :dormant
    end
  end

  describe "EngagementScorer.classify_tier/2" do
    test "highly engaged" do
      assert EngagementScorer.classify_tier(0.7, 0.8) == :highly_engaged
    end

    test "moderately engaged" do
      assert EngagementScorer.classify_tier(0.4, 0.3) == :moderately_engaged
    end

    test "low engagement" do
      assert EngagementScorer.classify_tier(0.15, 0.1) == :low_engagement
    end

    test "dormant" do
      assert EngagementScorer.classify_tier(0.0, 0.05) == :dormant
    end
  end

  describe "EngagementScorer.aggregate_stats/1" do
    test "returns aggregate stats across all users" do
      {user1, _} = create_user_with_prefs()
      {user2, _} = create_user_with_prefs()

      create_email_log(user1.id)
      create_email_log(user2.id)

      stats = EngagementScorer.aggregate_stats(30)

      assert stats.total_emails_sent >= 2
      assert is_float(stats.overall_open_rate)
      assert is_float(stats.overall_click_rate)
      assert stats.period_days == 30
    end
  end

  describe "EngagementScorer.daily_email_volume/1" do
    test "returns daily breakdown" do
      {user, _} = create_user_with_prefs()
      create_email_log(user.id)

      volumes = EngagementScorer.daily_email_volume(30)

      assert is_list(volumes)
      if length(volumes) > 0 do
        day = hd(volumes)
        assert Map.has_key?(day, :date)
        assert Map.has_key?(day, :sent)
        assert Map.has_key?(day, :opened)
      end
    end
  end

  describe "EngagementScorer.send_time_distribution/1" do
    test "returns hourly distribution" do
      {user, _} = create_user_with_prefs()
      create_email_log(user.id)

      dist = EngagementScorer.send_time_distribution(30)

      assert is_list(dist)
      if length(dist) > 0 do
        entry = hd(dist)
        assert Map.has_key?(entry, :hour)
        assert Map.has_key?(entry, :sent)
      end
    end
  end

  describe "EngagementScorer.channel_comparison/1" do
    test "returns comparison of all channels" do
      {user, _} = create_user_with_prefs()
      create_email_log(user.id)

      comparison = EngagementScorer.channel_comparison(30)

      assert length(comparison) == 3
      channels = Enum.map(comparison, & &1.channel)
      assert "email" in channels
      assert "in_app" in channels
      assert "sms" in channels
    end
  end
end
