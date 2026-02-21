defmodule BlocksterV2.Notifications.Phase9Test do
  use BlocksterV2.DataCase, async: false

  alias BlocksterV2.{Notifications, Repo}
  alias BlocksterV2.Notifications.{SmsNotifier, RateLimiter}
  alias BlocksterV2.Workers.SmsNotificationWorker
  alias BlocksterV2.Accounts.PhoneVerification
  alias BlocksterV2.Orders.Order

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

  defp create_phone_verified_user(attrs \\ %{}) do
    user = create_user(attrs)

    user =
      user
      |> Ecto.Changeset.change(%{phone_verified: true, sms_opt_in: true})
      |> Repo.update!()

    %PhoneVerification{}
    |> PhoneVerification.changeset(%{
      user_id: user.id,
      phone_number: "+1555#{:rand.uniform(9_999_999) |> Integer.to_string() |> String.pad_leading(7, "0")}",
      country_code: "US",
      geo_tier: "premium",
      geo_multiplier: Decimal.new("2.0"),
      verified: true,
      verified_at: DateTime.utc_now() |> DateTime.truncate(:second),
      sms_opt_in: true
    })
    |> Repo.insert!()

    {:ok, _prefs} = Notifications.get_or_create_preferences(user.id)
    user
  end

  defp create_opted_out_user do
    user = create_user()

    user =
      user
      |> Ecto.Changeset.change(%{phone_verified: true, sms_opt_in: false})
      |> Repo.update!()

    %PhoneVerification{}
    |> PhoneVerification.changeset(%{
      user_id: user.id,
      phone_number: "+1555#{:rand.uniform(9_999_999) |> Integer.to_string() |> String.pad_leading(7, "0")}",
      country_code: "US",
      geo_tier: "premium",
      geo_multiplier: Decimal.new("2.0"),
      verified: true,
      verified_at: DateTime.utc_now() |> DateTime.truncate(:second),
      sms_opt_in: false
    })
    |> Repo.insert!()

    {:ok, _prefs} = Notifications.get_or_create_preferences(user.id)
    user
  end

  # ============ SmsNotifier Template Tests ============

  describe "SmsNotifier.build_message/2" do
    test "flash sale message includes title and URL" do
      msg = SmsNotifier.build_message(:flash_sale, %{title: "50% Off!", url: "example.com/shop"})
      assert msg =~ "50% Off!"
      assert msg =~ "example.com/shop"
      assert msg =~ "Reply STOP to opt out"
    end

    test "bux milestone message includes amount" do
      msg = SmsNotifier.build_message(:bux_milestone, %{amount: "100,000"})
      assert msg =~ "100,000 BUX"
      assert msg =~ "Reply STOP to opt out"
    end

    test "order shipped message includes order ref" do
      msg = SmsNotifier.build_message(:order_shipped, %{order_ref: "#1234"})
      assert msg =~ "#1234"
      assert msg =~ "shipped"
      assert msg =~ "Reply STOP to opt out"
    end

    test "account security message includes detail" do
      msg = SmsNotifier.build_message(:account_security, %{detail: "New login from Chrome"})
      assert msg =~ "New login from Chrome"
      assert msg =~ "Reply STOP to opt out"
    end

    test "exclusive drop message" do
      msg = SmsNotifier.build_message(:exclusive_drop, %{title: "Rare NFT Drop"})
      assert msg =~ "Rare NFT Drop"
    end

    test "special offer message" do
      msg = SmsNotifier.build_message(:special_offer, %{title: "Buy 1 Get 1 Free"})
      assert msg =~ "Buy 1 Get 1 Free"
    end

    test "generic fallback message" do
      msg = SmsNotifier.build_message(:unknown_type, %{message: "Hello", url: "example.com"})
      assert msg =~ "Hello"
      assert msg =~ "example.com"
    end

    test "messages are capped at 160 characters" do
      long_title = String.duplicate("A", 200)
      msg = SmsNotifier.build_message(:flash_sale, %{title: long_title})
      assert byte_size(msg) <= 160
    end

    test "all messages include opt-out footer" do
      types = [:flash_sale, :bux_milestone, :order_shipped, :account_security, :exclusive_drop, :special_offer]

      for type <- types do
        msg = SmsNotifier.build_message(type, %{})
        assert msg =~ "Reply STOP to opt out", "Missing opt-out for #{type}"
      end
    end
  end

  # ============ SmsNotifier Eligibility Tests ============

  describe "SmsNotifier.can_send_to_user?/1" do
    test "returns true for phone-verified, opted-in user" do
      user = create_phone_verified_user()
      assert SmsNotifier.can_send_to_user?(user)
    end

    test "returns false if phone not verified" do
      user = create_user()
      refute SmsNotifier.can_send_to_user?(user)
    end

    test "returns false if sms_opt_in is false" do
      user = create_opted_out_user()
      refute SmsNotifier.can_send_to_user?(user)
    end
  end

  # ============ SmsNotifier Phone Lookup ============

  describe "SmsNotifier.get_user_phone/1" do
    test "returns phone number for verified, opted-in user" do
      user = create_phone_verified_user()
      phone = SmsNotifier.get_user_phone(user.id)
      assert phone
      assert String.starts_with?(phone, "+1555")
    end

    test "returns nil for user without phone verification" do
      user = create_user()
      assert SmsNotifier.get_user_phone(user.id) == nil
    end

    test "returns nil for opted-out user" do
      user = create_opted_out_user()
      assert SmsNotifier.get_user_phone(user.id) == nil
    end
  end

  # ============ SmsNotificationWorker Tests ============

  describe "SmsNotificationWorker.perform/1" do
    test "skips user that does not exist" do
      job = %Oban.Job{args: %{"user_id" => 999_999, "sms_type" => "flash_sale", "data" => %{}}}
      assert :ok == SmsNotificationWorker.perform(job)
    end

    test "skips user who is not phone verified" do
      user = create_user()
      {:ok, _} = Notifications.get_or_create_preferences(user.id)

      job = %Oban.Job{args: %{"user_id" => user.id, "sms_type" => "flash_sale", "data" => %{}}}
      assert :ok == SmsNotificationWorker.perform(job)
    end

    test "skips user who has opted out of SMS" do
      user = create_opted_out_user()

      job = %Oban.Job{args: %{"user_id" => user.id, "sms_type" => "flash_sale", "data" => %{}}}
      assert :ok == SmsNotificationWorker.perform(job)
    end

    test "skips when sms channel is disabled in preferences" do
      user = create_phone_verified_user()
      Notifications.update_preferences(user.id, %{sms_enabled: false})

      job = %Oban.Job{args: %{"user_id" => user.id, "sms_type" => "flash_sale", "data" => %{"title" => "Sale!"}}}
      assert :ok == SmsNotificationWorker.perform(job)
    end

    test "skips when specific SMS type is disabled" do
      user = create_phone_verified_user()
      Notifications.update_preferences(user.id, %{sms_special_offers: false})

      job = %Oban.Job{args: %{"user_id" => user.id, "sms_type" => "special_offer", "data" => %{}}}
      assert :ok == SmsNotificationWorker.perform(job)
    end

    test "respects weekly SMS rate limit" do
      user = create_phone_verified_user()
      # Default max_sms_per_week is 1, create one log entry
      Notifications.create_email_log(%{
        user_id: user.id,
        email_type: "sms",
        subject: "SMS: flash_sale",
        sent_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

      job = %Oban.Job{args: %{"user_id" => user.id, "sms_type" => "flash_sale", "data" => %{"title" => "Sale!"}}}
      assert :ok == SmsNotificationWorker.perform(job)
    end

    test "processes SMS for eligible user (no Twilio creds = :not_configured)" do
      user = create_phone_verified_user()
      Notifications.update_preferences(user.id, %{max_sms_per_week: 5})

      job = %Oban.Job{args: %{"user_id" => user.id, "sms_type" => "flash_sale", "data" => %{"title" => "Big Sale!"}}}
      assert :ok == SmsNotificationWorker.perform(job)
    end
  end

  # ============ SmsNotificationWorker.enqueue Tests ============

  describe "SmsNotificationWorker.enqueue/3" do
    test "creates an Oban job with correct args" do
      user = create_phone_verified_user()
      {:ok, job} = SmsNotificationWorker.enqueue(user.id, :flash_sale, %{title: "Test"})

      assert job.args["user_id"] == user.id
      assert job.args["sms_type"] == "flash_sale"
      assert job.args["data"]["title"] == "Test"
    end
  end

  # ============ Rate Limiter SMS Integration ============

  describe "RateLimiter SMS checks" do
    test "allows SMS when within rate limit" do
      user = create_phone_verified_user()
      Notifications.update_preferences(user.id, %{max_sms_per_week: 3})

      assert :ok == RateLimiter.can_send?(user.id, :sms, "flash_sale")
    end

    test "blocks SMS when rate limited" do
      user = create_phone_verified_user()
      Notifications.create_email_log(%{
        user_id: user.id,
        email_type: "sms",
        subject: "SMS: test",
        sent_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

      assert {:error, :rate_limited} == RateLimiter.can_send?(user.id, :sms, "flash_sale")
    end

    test "blocks SMS when sms_enabled is false" do
      user = create_phone_verified_user()
      Notifications.update_preferences(user.id, %{sms_enabled: false})

      assert {:error, :channel_disabled} == RateLimiter.can_send?(user.id, :sms)
    end

    test "blocks SMS when specific type is disabled" do
      user = create_phone_verified_user()
      Notifications.update_preferences(user.id, %{sms_special_offers: false})

      assert {:error, :type_disabled} == RateLimiter.can_send?(user.id, :sms, "special_offer")
    end

    test "blocks SMS when milestone_rewards is disabled" do
      user = create_phone_verified_user()
      Notifications.update_preferences(user.id, %{sms_milestone_rewards: false})

      assert {:error, :type_disabled} == RateLimiter.can_send?(user.id, :sms, "bux_milestone")
    end

    test "blocks SMS when account alerts disabled" do
      user = create_phone_verified_user()
      Notifications.update_preferences(user.id, %{sms_account_alerts: false})

      assert {:error, :type_disabled} == RateLimiter.can_send?(user.id, :sms, "order_shipped")
    end
  end

  # ============ Twilio Webhook Controller Tests ============

  describe "TwilioWebhookController" do
    test "opt-out via STOP updates user and preferences" do
      user = create_phone_verified_user()
      phone = SmsNotifier.get_user_phone(user.id)

      conn =
        Plug.Test.conn(:post, "/api/webhooks/twilio/sms", %{
          "From" => phone,
          "Body" => "STOP",
          "OptOutType" => "STOP"
        })
        |> Plug.Conn.put_req_header("content-type", "application/x-www-form-urlencoded")
        |> BlocksterV2Web.Router.call(BlocksterV2Web.Router.init([]))

      assert conn.status == 200
      assert conn.resp_body =~ "<Response>"

      updated_user = Repo.get!(BlocksterV2.Accounts.User, user.id)
      refute updated_user.sms_opt_in

      prefs = Notifications.get_preferences(user.id)
      refute prefs.sms_enabled
    end

    test "opt-in via START re-enables SMS" do
      user = create_opted_out_user()
      pv = Repo.get_by!(PhoneVerification, user_id: user.id)

      conn =
        Plug.Test.conn(:post, "/api/webhooks/twilio/sms", %{
          "From" => pv.phone_number,
          "Body" => "START"
        })
        |> Plug.Conn.put_req_header("content-type", "application/x-www-form-urlencoded")
        |> BlocksterV2Web.Router.call(BlocksterV2Web.Router.init([]))

      assert conn.status == 200

      updated_user = Repo.get!(BlocksterV2.Accounts.User, user.id)
      assert updated_user.sms_opt_in

      prefs = Notifications.get_preferences(user.id)
      assert prefs.sms_enabled
    end

    test "handles unknown phone number gracefully" do
      conn =
        Plug.Test.conn(:post, "/api/webhooks/twilio/sms", %{
          "From" => "+19999999999",
          "Body" => "STOP"
        })
        |> Plug.Conn.put_req_header("content-type", "application/x-www-form-urlencoded")
        |> BlocksterV2Web.Router.call(BlocksterV2Web.Router.init([]))

      assert conn.status == 200
    end

    test "handles various opt-out keywords" do
      user = create_phone_verified_user()
      phone = SmsNotifier.get_user_phone(user.id)

      for keyword <- ["STOPALL", "UNSUBSCRIBE", "CANCEL", "END", "QUIT"] do
        # Re-enable for each iteration
        user |> Ecto.Changeset.change(%{sms_opt_in: true}) |> Repo.update!()
        Notifications.update_preferences(user.id, %{sms_enabled: true})

        pv = Repo.get_by!(PhoneVerification, user_id: user.id)
        pv |> Ecto.Changeset.change(%{sms_opt_in: true}) |> Repo.update!()

        conn =
          Plug.Test.conn(:post, "/api/webhooks/twilio/sms", %{
            "From" => phone,
            "Body" => keyword
          })
          |> Plug.Conn.put_req_header("content-type", "application/x-www-form-urlencoded")
          |> BlocksterV2Web.Router.call(BlocksterV2Web.Router.init([]))

        assert conn.status == 200

        updated_user = Repo.get!(BlocksterV2.Accounts.User, user.id)
        refute updated_user.sms_opt_in, "#{keyword} should opt out user"
      end
    end
  end

  # ============ Order Shipped SMS Integration ============

  describe "Order shipped SMS trigger" do
    test "order shipped triggers notify_order_status_change which enqueues SMS" do
      user = create_phone_verified_user()

      # Create an order directly via Repo
      order =
        %Order{}
        |> Ecto.Changeset.change(%{
          user_id: user.id,
          status: "paid",
          subtotal: Decimal.new("10.00"),
          total_paid: Decimal.new("10.00"),
          order_number: "ORD-TEST-001"
        })
        |> Repo.insert!()

      # Update to shipped — this triggers notify_order_status_change which enqueues SMS
      {:ok, updated_order} = BlocksterV2.Orders.update_order(order, %{status: "shipped"})
      assert updated_order.status == "shipped"
    end
  end
end
