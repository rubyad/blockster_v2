defmodule BlocksterV2.Notifications.Phase11Test do
  use BlocksterV2.DataCase, async: false

  alias BlocksterV2.{Notifications, Repo}
  alias BlocksterV2.Notifications.{Campaign, EmailLog, Notification}

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

  defp create_campaign(attrs \\ %{}) do
    base = %{
      name: "Test Campaign #{System.unique_integer([:positive])}",
      type: "email_blast",
      status: "draft"
    }

    {:ok, campaign} = Notifications.create_campaign(Map.merge(base, attrs))
    campaign
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

  defp create_notification(user_id, attrs \\ %{}) do
    base = %{
      type: "special_offer",
      category: "offers",
      title: "Test notification",
      body: "Test body"
    }

    {:ok, notif} = Notifications.create_notification(user_id, Map.merge(base, attrs))
    notif
  end

  # ============ Campaign CRUD ============

  describe "Campaign CRUD operations" do
    test "create_campaign/1 creates a campaign" do
      {:ok, campaign} = Notifications.create_campaign(%{
        name: "My Campaign",
        type: "email_blast",
        subject: "Hello World",
        title: "Welcome",
        body: "This is a test",
        target_audience: "all"
      })

      assert campaign.name == "My Campaign"
      assert campaign.type == "email_blast"
      assert campaign.status == "draft"
      assert campaign.target_audience == "all"
    end

    test "create_campaign/1 rejects invalid type" do
      {:error, changeset} = Notifications.create_campaign(%{
        name: "Bad Type",
        type: "invalid_type"
      })

      assert errors_on(changeset)[:type]
    end

    test "update_campaign/2 updates attributes" do
      campaign = create_campaign()

      {:ok, updated} = Notifications.update_campaign(campaign, %{
        subject: "Updated Subject",
        title: "Updated Title"
      })

      assert updated.subject == "Updated Subject"
      assert updated.title == "Updated Title"
    end

    test "update_campaign_status/2 changes status" do
      campaign = create_campaign()

      {:ok, updated} = Notifications.update_campaign_status(campaign, "sent")
      assert updated.status == "sent"
    end

    test "update_campaign_status/2 rejects invalid status" do
      campaign = create_campaign()

      {:error, changeset} = Notifications.update_campaign_status(campaign, "invalid_status")
      assert errors_on(changeset)[:status]
    end

    test "delete_campaign/1 removes the campaign" do
      campaign = create_campaign()

      {:ok, _} = Notifications.delete_campaign(campaign)
      assert Repo.get(Campaign, campaign.id) == nil
    end

    test "list_campaigns/0 returns all campaigns" do
      c1 = create_campaign(%{name: "First"})
      c2 = create_campaign(%{name: "Second"})

      campaigns = Notifications.list_campaigns()
      ids = Enum.map(campaigns, & &1.id)

      assert c1.id in ids
      assert c2.id in ids
    end

    test "list_campaigns/1 filters by status" do
      create_campaign(%{status: "draft"})
      create_campaign(%{status: "sent"})

      drafts = Notifications.list_campaigns(status: "draft")
      assert Enum.all?(drafts, &(&1.status == "draft"))

      sent = Notifications.list_campaigns(status: "sent")
      assert Enum.all?(sent, &(&1.status == "sent"))
    end
  end

  # ============ Campaign Recipient Count ============

  describe "campaign_recipient_count/1" do
    test "counts all users with email for 'all' audience" do
      create_user()
      create_user()

      campaign = %Campaign{target_audience: "all"}
      count = Notifications.campaign_recipient_count(campaign)

      assert count >= 2
    end

    test "counts active users for 'active_users' audience" do
      user = create_user()
      # User was just created so updated_at is recent — should count as active
      campaign = %Campaign{target_audience: "active_users"}
      count = Notifications.campaign_recipient_count(campaign)

      assert count >= 1
    end

    test "counts dormant users for 'dormant_users' audience" do
      user = create_user()
      # Set updated_at to 60 days ago to make user dormant
      two_months_ago = NaiveDateTime.utc_now() |> NaiveDateTime.add(-60 * 86400)

      import Ecto.Query
      from(u in BlocksterV2.Accounts.User, where: u.id == ^user.id)
      |> Repo.update_all(set: [updated_at: two_months_ago])

      campaign = %Campaign{target_audience: "dormant_users"}
      count = Notifications.campaign_recipient_count(campaign)

      assert count >= 1
    end

    test "counts phone verified users" do
      user = create_user()
      user |> Ecto.Changeset.change(%{phone_verified: true}) |> Repo.update!()

      campaign = %Campaign{target_audience: "phone_verified"}
      count = Notifications.campaign_recipient_count(campaign)

      assert count >= 1
    end
  end

  # ============ Campaign Stats ============

  describe "get_campaign_stats/1" do
    test "returns email and in_app stats for campaign" do
      user = create_user()
      campaign = create_campaign(%{status: "sent"})

      # Create email logs for campaign
      log = create_email_log(user.id, %{campaign_id: campaign.id})
      log |> Ecto.Changeset.change(%{opened_at: DateTime.utc_now() |> DateTime.truncate(:second)}) |> Repo.update!()

      # Create in-app notification for campaign
      create_notification(user.id, %{campaign_id: campaign.id})

      stats = Notifications.get_campaign_stats(campaign.id)

      assert stats.campaign.id == campaign.id
      assert stats.email.sent == 1
      assert stats.email.opened == 1
      assert stats.in_app.delivered == 1
    end

    test "returns zeros for campaign with no activity" do
      campaign = create_campaign()
      stats = Notifications.get_campaign_stats(campaign.id)

      assert stats.email.sent == 0
      assert stats.email.opened == 0
      assert stats.email.clicked == 0
      assert stats.in_app.delivered == 0
    end
  end

  # ============ Email Log Operations ============

  describe "email log operations" do
    test "update_email_log/2 updates castable attributes" do
      user = create_user()
      log = create_email_log(user.id, %{subject: "Original Subject"})

      {:ok, updated} = Notifications.update_email_log(log, %{
        subject: "Updated Subject"
      })

      assert updated.subject == "Updated Subject"
    end

    test "get_email_log_by_message_id/1 finds by sendgrid_message_id" do
      user = create_user()
      log = create_email_log(user.id)

      found = Notifications.get_email_log_by_message_id(log.sendgrid_message_id)
      assert found.id == log.id
    end

    test "get_email_log_by_message_id/1 returns nil for unknown id" do
      assert Notifications.get_email_log_by_message_id("nonexistent") == nil
    end
  end

  # ============ Campaign Channels ============

  describe "campaign channel configuration" do
    test "campaign defaults to email + in_app enabled, sms disabled" do
      campaign = create_campaign()

      assert campaign.send_email == true
      assert campaign.send_in_app == true
      assert campaign.send_sms == false
    end

    test "campaign can enable all channels" do
      campaign = create_campaign(%{
        send_email: true,
        send_in_app: true,
        send_sms: true
      })

      assert campaign.send_email == true
      assert campaign.send_in_app == true
      assert campaign.send_sms == true
    end

    test "campaign can disable all channels" do
      campaign = create_campaign(%{
        send_email: false,
        send_in_app: false,
        send_sms: false
      })

      assert campaign.send_email == false
      assert campaign.send_in_app == false
      assert campaign.send_sms == false
    end
  end

  # ============ Campaign Status Workflow ============

  describe "campaign status workflow" do
    test "draft -> sending -> sent" do
      campaign = create_campaign(%{status: "draft"})
      assert campaign.status == "draft"

      {:ok, sending} = Notifications.update_campaign_status(campaign, "sending")
      assert sending.status == "sending"

      {:ok, sent} = Notifications.update_campaign_status(sending, "sent")
      assert sent.status == "sent"
    end

    test "draft -> cancelled" do
      campaign = create_campaign(%{status: "draft"})

      {:ok, cancelled} = Notifications.update_campaign_status(campaign, "cancelled")
      assert cancelled.status == "cancelled"
    end

    test "draft -> scheduled -> cancelled" do
      campaign = create_campaign(%{status: "draft"})

      {:ok, scheduled} = Notifications.update_campaign_status(campaign, "scheduled")
      assert scheduled.status == "scheduled"

      {:ok, cancelled} = Notifications.update_campaign_status(scheduled, "cancelled")
      assert cancelled.status == "cancelled"
    end
  end

  # ============ Campaign Audience Types ============

  describe "campaign audience targeting" do
    test "all valid audience types accepted" do
      audiences = ["all", "hub_followers", "active_users", "dormant_users", "phone_verified", "custom"]

      for audience <- audiences do
        {:ok, campaign} = Notifications.create_campaign(%{
          name: "Audience #{audience}",
          type: "email_blast",
          target_audience: audience
        })

        assert campaign.target_audience == audience
      end
    end

    test "invalid audience type rejected" do
      {:error, changeset} = Notifications.create_campaign(%{
        name: "Bad Audience",
        type: "email_blast",
        target_audience: "invalid_audience"
      })

      assert errors_on(changeset)[:target_audience]
    end
  end

  # ============ Campaign Scheduling ============

  describe "campaign scheduling" do
    test "campaign can be scheduled with future datetime" do
      future = DateTime.utc_now() |> DateTime.add(86400) |> DateTime.truncate(:second)

      {:ok, campaign} = Notifications.create_campaign(%{
        name: "Scheduled Campaign",
        type: "email_blast",
        scheduled_at: future,
        status: "scheduled"
      })

      assert campaign.scheduled_at == future
      assert campaign.status == "scheduled"
    end

    test "campaign tracks sent_at timestamp" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      campaign = create_campaign()
      {:ok, updated} = Notifications.update_campaign(campaign, %{sent_at: now, status: "sent"})

      assert updated.sent_at == now
      assert updated.status == "sent"
    end
  end

  # ============ Campaign Stats Fields ============

  describe "campaign stats fields" do
    test "stats fields default to 0" do
      campaign = create_campaign()

      assert campaign.total_recipients == 0
      assert campaign.emails_sent == 0
      assert campaign.emails_opened == 0
      assert campaign.emails_clicked == 0
      assert campaign.sms_sent == 0
      assert campaign.in_app_delivered == 0
      assert campaign.in_app_read == 0
    end

    test "stats fields can be incremented via update_all" do
      campaign = create_campaign()

      {1, _} =
        Campaign
        |> Ecto.Query.where([c], c.id == ^campaign.id)
        |> Repo.update_all(inc: [emails_opened: 1])

      updated = Repo.get!(Campaign, campaign.id)
      assert updated.emails_opened == 1
    end
  end

  # ============ Campaign Content Fields ============

  describe "campaign content fields" do
    test "campaign stores all content fields" do
      {:ok, campaign} = Notifications.create_campaign(%{
        name: "Full Content",
        type: "multi_channel",
        subject: "Email subject",
        title: "Notification title",
        body: "<p>HTML body</p>",
        plain_text_body: "Plain text body",
        image_url: "https://example.com/image.jpg",
        action_url: "https://example.com/action",
        action_label: "Click Here"
      })

      assert campaign.subject == "Email subject"
      assert campaign.title == "Notification title"
      assert campaign.body == "<p>HTML body</p>"
      assert campaign.plain_text_body == "Plain text body"
      assert campaign.image_url == "https://example.com/image.jpg"
      assert campaign.action_url == "https://example.com/action"
      assert campaign.action_label == "Click Here"
    end
  end
end
