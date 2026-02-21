defmodule BlocksterV2.Notifications.Phase7Test do
  use BlocksterV2.DataCase, async: true

  alias BlocksterV2.Notifications
  alias BlocksterV2.Notifications.{EmailBuilder, RateLimiter}

  # ============ Test Helpers ============

  defp create_user do
    {:ok, user} =
      BlocksterV2.Accounts.create_user_from_wallet(%{
        wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
        chain_id: 560013
      })

    user
  end

  # ============ Email Builder - Base Layout ============

  describe "email builder base layout" do
    test "all templates include HTML structure" do
      email = EmailBuilder.single_article("test@example.com", "Test", "token123", %{title: "Article"})
      html = email.html_body

      assert html =~ "<!DOCTYPE html>"
      assert html =~ "Blockster"
      assert html =~ "unsubscribe"
      assert html =~ "Manage preferences"
    end

    test "all templates include text fallback" do
      email = EmailBuilder.single_article("test@example.com", "Test", "token123", %{title: "Article"})
      text = email.text_body

      assert text =~ "Unsubscribe"
      assert text =~ "Manage preferences"
    end

    test "all templates set correct from address" do
      email = EmailBuilder.single_article("test@example.com", "Test", "token123", %{})
      assert {"Blockster", "notifications@blockster.com"} = email.from
    end

    test "all templates set correct to address" do
      email = EmailBuilder.single_article("user@example.com", "John", "token123", %{})
      assert [{"John", "user@example.com"}] = email.to
    end

    test "all templates include List-Unsubscribe header" do
      email = EmailBuilder.single_article("test@example.com", "Test", "mytoken", %{})
      headers = email.headers

      assert Map.has_key?(headers, "List-Unsubscribe")
      assert headers["List-Unsubscribe"] =~ "mytoken"
      assert Map.has_key?(headers, "List-Unsubscribe-Post")
    end

    test "unsubscribe URL uses the provided token" do
      email = EmailBuilder.single_article("test@example.com", "Test", "abc123token", %{})
      assert email.html_body =~ "/unsubscribe/abc123token"
      assert email.text_body =~ "/unsubscribe/abc123token"
    end

    test "dark mode CSS is included" do
      email = EmailBuilder.single_article("test@example.com", "Test", "token", %{})
      assert email.html_body =~ "prefers-color-scheme: dark"
    end
  end

  # ============ Single Article Template ============

  describe "single article email" do
    test "renders article title and body" do
      email = EmailBuilder.single_article("test@example.com", "Test", "token", %{
        title: "Crypto Market Update",
        body: "Markets are surging today",
        slug: "crypto-market-update"
      })

      assert email.subject =~ "Crypto Market Update"
      assert email.html_body =~ "Crypto Market Update"
      assert email.html_body =~ "Markets are surging today"
      assert email.text_body =~ "Markets are surging today"
    end

    test "includes hub name when provided" do
      email = EmailBuilder.single_article("test@example.com", "Test", "token", %{
        title: "Test Article",
        hub_name: "Crypto Hub"
      })

      assert email.subject =~ "Crypto Hub"
      assert email.html_body =~ "Crypto Hub"
    end

    test "includes hero image when provided" do
      email = EmailBuilder.single_article("test@example.com", "Test", "token", %{
        title: "Test",
        image_url: "https://example.com/hero.jpg"
      })

      assert email.html_body =~ "https://example.com/hero.jpg"
    end

    test "includes Read Article CTA" do
      email = EmailBuilder.single_article("test@example.com", "Test", "token", %{
        title: "Test",
        slug: "my-article"
      })

      assert email.html_body =~ "Read Article"
      assert email.html_body =~ "/my-article"
      assert email.text_body =~ "/my-article"
    end
  end

  # ============ Daily Digest Template ============

  describe "daily digest email" do
    test "renders multiple articles" do
      email = EmailBuilder.daily_digest("test@example.com", "Test", "token", %{
        articles: [
          %{title: "Article One", slug: "article-one", hub_name: "Hub A"},
          %{title: "Article Two", slug: "article-two"},
          %{title: "Article Three", slug: "article-three", hub_name: "Hub B"}
        ],
        date: ~D[2026-02-20]
      })

      assert email.subject =~ "Daily Digest"
      assert email.subject =~ "February 20, 2026"
      assert email.html_body =~ "Article One"
      assert email.html_body =~ "Article Two"
      assert email.html_body =~ "Article Three"
      assert email.html_body =~ "Hub A"
      assert email.text_body =~ "Article One"
    end

    test "handles empty articles list" do
      email = EmailBuilder.daily_digest("test@example.com", "Test", "token", %{articles: []})
      assert email.subject =~ "Daily Digest"
      assert email.html_body =~ "Browse All Articles"
    end
  end

  # ============ Promotional Template ============

  describe "promotional email" do
    test "renders offer details" do
      email = EmailBuilder.promotional("test@example.com", "Test", "token", %{
        title: "50% Off All Merch",
        body: "Limited time offer on all shop items",
        action_url: "https://blockster-v2.fly.dev/shop",
        action_label: "Shop Now"
      })

      assert email.subject == "50% Off All Merch"
      assert email.html_body =~ "50% Off All Merch"
      assert email.html_body =~ "Shop Now"
    end

    test "renders discount code" do
      email = EmailBuilder.promotional("test@example.com", "Test", "token", %{
        title: "Special Deal",
        discount_code: "SAVE20"
      })

      assert email.html_body =~ "SAVE20"
      assert email.text_body =~ "SAVE20"
    end

    test "renders hero image" do
      email = EmailBuilder.promotional("test@example.com", "Test", "token", %{
        title: "Sale",
        image_url: "https://example.com/banner.jpg"
      })

      assert email.html_body =~ "https://example.com/banner.jpg"
    end
  end

  # ============ Referral Prompt Template ============

  describe "referral prompt email" do
    test "renders referral link and reward" do
      email = EmailBuilder.referral_prompt("test@example.com", "Test", "token", %{
        referral_link: "https://blockster-v2.fly.dev/?ref=abc123",
        bux_reward: 1000
      })

      assert email.subject =~ "1000 BUX"
      assert email.html_body =~ "ref=abc123"
      assert email.html_body =~ "1000"
      assert email.text_body =~ "ref=abc123"
    end

    test "uses default reward when not provided" do
      email = EmailBuilder.referral_prompt("test@example.com", "Test", "token", %{})
      assert email.subject =~ "500 BUX"
    end
  end

  # ============ Weekly Reward Summary Template ============

  describe "weekly reward summary email" do
    test "renders weekly stats" do
      email = EmailBuilder.weekly_reward_summary("test@example.com", "Test", "token", %{
        total_bux_earned: 2500,
        articles_read: 15,
        days_active: 5,
        top_hub: "Crypto Daily"
      })

      assert email.subject =~ "2500 BUX"
      assert email.html_body =~ "2500"
      assert email.html_body =~ "15"
      assert email.html_body =~ "5"
      assert email.html_body =~ "Crypto Daily"
      assert email.text_body =~ "Crypto Daily"
    end

    test "renders without top hub" do
      email = EmailBuilder.weekly_reward_summary("test@example.com", "Test", "token", %{
        total_bux_earned: 100
      })

      assert email.html_body =~ "100"
      refute email.html_body =~ "Most active hub"
    end
  end

  # ============ Welcome Template ============

  describe "welcome email" do
    test "renders welcome message with username" do
      email = EmailBuilder.welcome("test@example.com", "Alice", "token", %{username: "Alice"})

      assert email.subject == "Welcome to Blockster!"
      assert email.html_body =~ "Alice"
      assert email.html_body =~ "Read articles to earn BUX"
      assert email.html_body =~ "Subscribe to hubs"
      assert email.html_body =~ "Redeem BUX"
    end

    test "uses fallback name" do
      email = EmailBuilder.welcome("test@example.com", nil, "token", %{})
      assert email.html_body =~ "there"
    end
  end

  # ============ Re-engagement Template ============

  describe "re-engagement email" do
    test "renders 3-day inactive message" do
      email = EmailBuilder.re_engagement("test@example.com", "Test", "token", %{
        days_inactive: 3,
        articles: [%{title: "Missed Article", slug: "missed-article"}]
      })

      assert email.subject =~ "unread articles"
      assert email.html_body =~ "3 days"
      assert email.html_body =~ "Missed Article"
    end

    test "renders 30-day inactive message with special offer" do
      email = EmailBuilder.re_engagement("test@example.com", "Test", "token", %{
        days_inactive: 30,
        special_offer: "Earn 2x BUX for your first 3 articles!"
      })

      assert email.subject =~ "miss you"
      assert email.html_body =~ "30 days"
      assert email.html_body =~ "Earn 2x BUX"
    end

    test "renders 7-day message" do
      email = EmailBuilder.re_engagement("test@example.com", "Test", "token", %{
        days_inactive: 7
      })

      assert email.subject =~ "BUX are waiting"
    end

    test "renders 14-day message" do
      email = EmailBuilder.re_engagement("test@example.com", "Test", "token", %{
        days_inactive: 14
      })

      assert email.subject =~ "what you missed"
    end
  end

  # ============ Order Update Template ============

  describe "order update email" do
    test "renders confirmed order" do
      email = EmailBuilder.order_update("test@example.com", "Test", "token", %{
        order_number: "BLK-001",
        status: "confirmed",
        items: [%{title: "Blockster Hoodie", quantity: 1}]
      })

      assert email.subject =~ "BLK-001"
      assert email.subject =~ "Confirmed"
      assert email.html_body =~ "CONFIRMED"
      assert email.html_body =~ "Blockster Hoodie"
    end

    test "renders shipped order with tracking" do
      email = EmailBuilder.order_update("test@example.com", "Test", "token", %{
        order_number: "BLK-002",
        status: "shipped",
        tracking_url: "https://tracking.example.com/123"
      })

      assert email.subject =~ "Shipped"
      assert email.html_body =~ "Track Your Order"
      assert email.html_body =~ "tracking.example.com/123"
    end

    test "renders delivered order" do
      email = EmailBuilder.order_update("test@example.com", "Test", "token", %{
        order_number: "BLK-003",
        status: "delivered"
      })

      assert email.subject =~ "Delivered"
      assert email.html_body =~ "Enjoy"
    end

    test "renders cancelled order" do
      email = EmailBuilder.order_update("test@example.com", "Test", "token", %{
        order_number: "BLK-004",
        status: "cancelled"
      })

      assert email.subject =~ "Cancelled"
    end
  end

  # ============ HTML Escaping ============

  describe "HTML escaping" do
    test "escapes HTML entities in content" do
      email = EmailBuilder.single_article("test@example.com", "Test", "token", %{
        title: "Prices <up> & \"rising\"",
        body: "BTC > $100k <script>alert('xss')</script>"
      })

      assert email.html_body =~ "&lt;up&gt;"
      assert email.html_body =~ "&amp;"
      assert email.html_body =~ "&quot;rising&quot;"
      assert email.html_body =~ "&lt;script&gt;"
    end

    test "handles nil values" do
      assert EmailBuilder.escape(nil) == ""
    end
  end

  # ============ Rate Limiter ============

  describe "rate limiter - channel checks" do
    test "allows send when email enabled" do
      user = create_user()
      assert :ok = RateLimiter.can_send?(user.id, :email)
    end

    test "blocks send when email disabled" do
      user = create_user()
      Notifications.update_preferences(user.id, %{email_enabled: false})
      assert {:error, :channel_disabled} = RateLimiter.can_send?(user.id, :email)
    end

    test "allows send when sms enabled" do
      user = create_user()
      assert :ok = RateLimiter.can_send?(user.id, :sms)
    end

    test "blocks send when sms disabled" do
      user = create_user()
      Notifications.update_preferences(user.id, %{sms_enabled: false})
      assert {:error, :channel_disabled} = RateLimiter.can_send?(user.id, :sms)
    end

    test "allows send for in_app when enabled" do
      user = create_user()
      assert :ok = RateLimiter.can_send?(user.id, :in_app)
    end

    test "blocks in_app when disabled" do
      user = create_user()
      Notifications.update_preferences(user.id, %{in_app_enabled: false})
      assert {:error, :channel_disabled} = RateLimiter.can_send?(user.id, :in_app)
    end

    test "returns error for user without preferences" do
      assert {:error, :no_preferences} = RateLimiter.can_send?(999_999, :email)
    end
  end

  describe "rate limiter - type checks" do
    test "blocks when specific email type is disabled" do
      user = create_user()
      Notifications.update_preferences(user.id, %{email_hub_posts: false})
      assert {:error, :type_disabled} = RateLimiter.can_send?(user.id, :email, "hub_post")
    end

    test "allows when specific email type is enabled" do
      user = create_user()
      assert :ok = RateLimiter.can_send?(user.id, :email, "hub_post")
    end

    test "blocks disabled SMS type" do
      user = create_user()
      Notifications.update_preferences(user.id, %{sms_special_offers: false})
      assert {:error, :type_disabled} = RateLimiter.can_send?(user.id, :sms, "special_offer")
    end

    test "allows unknown type (no preference mapping)" do
      user = create_user()
      assert :ok = RateLimiter.can_send?(user.id, :email, "some_unknown_type")
    end

    test "blocks daily_digest when disabled" do
      user = create_user()
      Notifications.update_preferences(user.id, %{email_daily_digest: false})
      assert {:error, :type_disabled} = RateLimiter.can_send?(user.id, :email, "daily_digest")
    end

    test "blocks reward alerts when disabled" do
      user = create_user()
      Notifications.update_preferences(user.id, %{email_reward_alerts: false})
      assert {:error, :type_disabled} = RateLimiter.can_send?(user.id, :email, "bux_earned")
    end
  end

  describe "rate limiter - rate limits" do
    test "blocks when daily email limit reached" do
      user = create_user()
      Notifications.update_preferences(user.id, %{max_emails_per_day: 2})

      # Log 2 emails
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      Notifications.create_email_log(%{
        user_id: user.id,
        email_type: "digest",
        subject: "Test",
        sent_at: now
      })

      Notifications.create_email_log(%{
        user_id: user.id,
        email_type: "promo",
        subject: "Test",
        sent_at: now
      })

      assert {:error, :rate_limited} = RateLimiter.can_send?(user.id, :email)
    end

    test "allows when under daily email limit" do
      user = create_user()
      Notifications.update_preferences(user.id, %{max_emails_per_day: 3})

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      Notifications.create_email_log(%{
        user_id: user.id,
        email_type: "digest",
        subject: "Test",
        sent_at: now
      })

      assert :ok = RateLimiter.can_send?(user.id, :email)
    end

    test "blocks when weekly SMS limit reached" do
      user = create_user()
      Notifications.update_preferences(user.id, %{max_sms_per_week: 1})

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      Notifications.create_email_log(%{
        user_id: user.id,
        email_type: "sms",
        subject: "SMS",
        sent_at: now
      })

      assert {:error, :rate_limited} = RateLimiter.can_send?(user.id, :sms)
    end
  end

  describe "rate limiter - quiet hours" do
    test "defers during quiet hours" do
      user = create_user()
      now = DateTime.utc_now() |> DateTime.to_time() |> Time.truncate(:second)

      # Set quiet hours to include current time
      quiet_start = Time.add(now, -3600)
      quiet_end = Time.add(now, 3600)

      Notifications.update_preferences(user.id, %{
        quiet_hours_start: quiet_start,
        quiet_hours_end: quiet_end,
        timezone: "UTC"
      })

      assert :defer = RateLimiter.can_send?(user.id, :email)
    end

    test "allows outside quiet hours" do
      user = create_user()
      now = DateTime.utc_now() |> DateTime.to_time() |> Time.truncate(:second)

      # Set quiet hours AWAY from current time (6 hours offset)
      quiet_start = Time.add(now, 6 * 3600)
      quiet_end = Time.add(now, 8 * 3600)

      Notifications.update_preferences(user.id, %{
        quiet_hours_start: quiet_start,
        quiet_hours_end: quiet_end,
        timezone: "UTC"
      })

      assert :ok = RateLimiter.can_send?(user.id, :email)
    end

    test "allows when no quiet hours set" do
      user = create_user()
      assert :ok = RateLimiter.can_send?(user.id, :email)
    end
  end

  # ============ Module Existence ============

  describe "module existence" do
    test "EmailBuilder module exists" do
      assert Code.ensure_loaded?(BlocksterV2.Notifications.EmailBuilder)
    end

    test "RateLimiter module exists" do
      assert Code.ensure_loaded?(BlocksterV2.Notifications.RateLimiter)
    end
  end
end
