defmodule BlocksterV2Web.MemberLive.ShowTest do
  @moduledoc """
  Smoke + structure tests for the redesigned profile / member show page.

  The page is `BlocksterV2Web.MemberLive.Show` mounted at `/member/:slug`.
  Per the redesign release plan, the page shows a profile hero with stat
  cards, multiplier breakdown, sticky 5-tab nav
  (Activity/Following/Refer/Rewards/Settings), and per-tab content.

  Security: only the profile owner can view this page; anonymous users
  and non-owners are redirected.
  """

  use BlocksterV2Web.ConnCase
  import Phoenix.LiveViewTest

  alias BlocksterV2.Repo
  alias BlocksterV2.Accounts.User

  setup do
    ensure_mnesia_tables()
    :ok
  end

  # Ensure the Mnesia tables that MemberLive.Show depends on exist.
  # Uses the same table definitions as mnesia_initializer.ex to avoid bad_type errors.
  defp ensure_mnesia_tables do
    :mnesia.start()

    tables = [
      {:x_connections, :set,
        [:user_id, :x_user_id, :x_username, :x_name, :x_profile_image_url,
         :access_token_encrypted, :refresh_token_encrypted, :token_expires_at, :scopes,
         :connected_at, :x_score, :followers_count, :following_count, :tweet_count,
         :listed_count, :avg_engagement_rate, :original_tweets_analyzed, :account_created_at,
         :score_calculated_at, :updated_at],
        [:x_user_id, :x_username]},
      {:user_solana_balances, :set,
        [:user_id, :wallet_address, :updated_at, :sol_balance, :bux_balance],
        [:wallet_address]},
      {:unified_multipliers_v2, :set,
        [:user_id, :x_score, :x_multiplier, :phone_multiplier, :sol_multiplier,
         :email_multiplier, :overall_multiplier, :last_updated, :created_at],
        [:overall_multiplier]},
      {:user_post_rewards, :set,
        [:key, :user_id, :post_id, :read_bux, :read_paid, :read_tx_id,
         :x_share_bux, :x_share_paid, :x_share_tx_id, :linkedin_share_bux,
         :linkedin_share_paid, :linkedin_share_tx_id, :total_bux,
         :total_paid_bux, :created_at, :updated_at],
        [:user_id, :post_id]},
      {:user_video_engagement, :set,
        [:key, :user_id, :post_id, :high_water_mark, :total_earnable_time, :video_duration,
         :completion_percentage, :total_bux_earned, :last_session_bux, :total_pause_count,
         :total_tab_away_count, :session_count, :last_watched_at, :last_session_data,
         :updated_at, :tx_ids],
        [:user_id]},
      {:share_rewards, :set,
        [:key, :id, :user_id, :campaign_id, :x_connection_id, :retweet_id, :status,
         :bux_rewarded, :verified_at, :rewarded_at, :failure_reason, :tx_hash,
         :created_at, :updated_at],
        [:user_id, :campaign_id]},
      {:user_bux_balances, :set,
        [:user_id, :user_smart_wallet, :updated_at, :aggregate_bux_balance,
         :bux_balance, :moonbux_balance, :neobux_balance, :roguebux_balance,
         :flarebux_balance, :nftbux_balance, :nolchabux_balance, :solbux_balance,
         :spacebux_balance, :tronbux_balance, :tranbux_balance],
        [:user_smart_wallet, :aggregate_bux_balance]},
      {:referral_stats, :set,
        [:user_id, :total_referrals, :verified_referrals, :total_bux_earned,
         :total_rogue_earned, :updated_at],
        []},
      {:referrals, :set,
        [:user_id, :referrer_id, :referrer_wallet, :referee_wallet, :referred_at,
         :on_chain_synced],
        [:referrer_id, :referrer_wallet, :referee_wallet]},
      {:referral_earnings, :bag,
        [:id, :referrer_id, :referrer_wallet, :referee_wallet, :earning_type,
         :amount, :token, :tx_hash, :commitment_hash, :timestamp],
        [:referrer_id, :referrer_wallet, :referee_wallet, :commitment_hash]}
    ]

    for {name, type, attrs, index} <- tables do
      case :mnesia.create_table(name, type: type, attributes: attrs, index: index, ram_copies: [node()]) do
        {:atomic, :ok} -> :ok
        {:aborted, {:already_exists, ^name}} -> :ok
        _other -> :ok
      end
    end

    :ok
  end

  # Use struct-based insert to bypass changeset (avoids slug auto-generation issues)
  defp insert_user(attrs) do
    uid = System.unique_integer([:positive])
    defaults = %{
      username: "testuser#{uid}",
      wallet_address: "TestWallet#{uid}",
      slug: "testuser-#{uid}",
      auth_method: "wallet",
      phone_verified: false,
      email_verified: false,
      is_active: true
    }

    Repo.insert!(struct(User, Map.merge(defaults, attrs)))
  end

  defp log_in_user(conn, user) do
    {:ok, session} = BlocksterV2.Accounts.create_session(user.id)

    conn
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, session.token)
    |> Plug.Conn.put_session("wallet_address", user.wallet_address)
  end

  describe "GET /member/:slug · authenticated owner" do
    test "mounts and renders profile hero with username", %{conn: conn} do
      user = insert_user(%{username: "marcus", slug: "marcus"})
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/member/marcus")

      assert html =~ "ds-profile-hero"
      assert html =~ "marcus"
      assert html =~ "Your profile"
    end

    test "renders design system header and footer", %{conn: conn} do
      user = insert_user(%{slug: "hdrftr"})
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/member/hdrftr")

      assert html =~ "ds-header"
      assert html =~ "ds-footer"
      assert html =~ "Hustle hard. All in on crypto."
    end

    test "renders three stat cards", %{conn: conn} do
      user = insert_user(%{slug: "stats"})
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/member/stats")

      assert html =~ "BUX Balance"
      assert html =~ "BUX Multiplier"
      assert html =~ "SOL Balance"
      assert html =~ "ds-stat-card"
    end

    test "renders multiplier breakdown card", %{conn: conn} do
      user = insert_user(%{slug: "mult"})
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/member/mult")

      assert html =~ "ds-multiplier-breakdown"
      assert html =~ "How your multiplier works"
      assert html =~ "X Account"
      assert html =~ "Phone"
      assert html =~ "SOL Balance"
      assert html =~ "Email"
      assert html =~ "200"
    end

    test "renders 4-tab navigation", %{conn: conn} do
      # Refer tab removed 2026-04-27 — referral feature parked. Tabs are now
      # Activity / Following / Rewards / Settings.
      user = insert_user(%{slug: "tabs"})
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/member/tabs")

      assert html =~ "ds-profile-tabs"
      assert html =~ "Activity"
      assert html =~ "Following"
      assert html =~ "Rewards"
      assert html =~ "Settings"
      refute html =~ ~s|phx-value-tab="refer"|
    end

    @tag :skip
    test "renders Why Earn BUX banner", %{conn: conn} do
      # The `why_earn_bux_banner` is a DS header feature gated by
      # `assigns[:show_why_earn_bux]`. The member page doesn't enable it;
      # coverage lives on pages that do.
      user = insert_user(%{slug: "buxbanner"})
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/member/buxbanner")

      assert html =~ "ds-why-earn-bux"
      assert html =~ "Redeem BUX to enter sponsored airdrops"
    end

    test "shows wallet address in hero", %{conn: conn} do
      user = insert_user(%{slug: "wallet", wallet_address: "7xQk8abcdefghijklmnopqrstuvwxyz123456"})
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/member/wallet")

      # Truncated wallet should appear
      assert html =~ "7xQk8a"
    end

    test "shows member since date", %{conn: conn} do
      user = insert_user(%{slug: "since"})
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/member/since")

      assert html =~ "Member since"
    end
  end

  describe "verification banners" do
    test "shows email verification banner when email not verified", %{conn: conn} do
      user = insert_user(%{slug: "noemail", email_verified: false})
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/member/noemail")

      assert html =~ "ds-email-verify-banner"
      assert html =~ "Verify your email"
      assert html =~ "One thing left"
    end

    test "hides email verification banner when email verified", %{conn: conn} do
      user = insert_user(%{slug: "yesmail", email_verified: true})
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/member/yesmail")

      refute html =~ "ds-email-verify-banner"
    end

    test "shows phone verification banner when phone not verified", %{conn: conn} do
      user = insert_user(%{slug: "nophone", phone_verified: false})
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/member/nophone")

      assert html =~ "ds-phone-verify-banner"
      assert html =~ "Verify your phone"
    end

    test "hides phone verification banner when phone verified", %{conn: conn} do
      user = insert_user(%{slug: "yesphone", phone_verified: true})
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/member/yesphone")

      refute html =~ "ds-phone-verify-banner"
    end

    # MEMBER-01: verification banners address the CURRENT USER (`Verify your
    # phone to unlock 2× multiplier`). They must NOT render on another user's
    # profile page even when that other user hasn't verified — otherwise the
    # banner reads as if we're accusing the profile owner of missing a step,
    # when the CTA actually targets the viewer.
    test "hides email banner on another user's profile even if they're unverified",
         %{conn: conn} do
      other = insert_user(%{slug: "other-user-no-email", email_verified: false, phone_verified: true})
      me = insert_user(%{slug: "me-verified", email_verified: true, phone_verified: true})
      conn = log_in_user(conn, me)

      {:ok, _view, html} = live(conn, ~p"/member/other-user-no-email")

      refute html =~ "ds-email-verify-banner"
      refute html =~ "Verify your email"
      # sanity: we reached the other user's profile
      assert html =~ other.username
    end

    test "hides phone banner on another user's profile even if they're unverified",
         %{conn: conn} do
      other = insert_user(%{slug: "other-user-no-phone", email_verified: true, phone_verified: false})
      me = insert_user(%{slug: "me-also-verified", email_verified: true, phone_verified: true})
      conn = log_in_user(conn, me)

      {:ok, _view, html} = live(conn, ~p"/member/other-user-no-phone")

      refute html =~ "ds-phone-verify-banner"
      refute html =~ "Verify your phone"
      assert html =~ other.username
    end
  end

  describe "verification status pills" do
    test "shows green check for verified items", %{conn: conn} do
      user = insert_user(%{slug: "verified", phone_verified: true, email_verified: true})
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/member/verified")

      # Verified items use green check SVG (M9 16.17...)
      assert html =~ "M9 16.17"
    end
  end

  describe "tab switching" do
    test "switch_tab to following shows followed hubs section", %{conn: conn} do
      user = insert_user(%{slug: "followtab"})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/member/followtab")

      html = view |> element(~s|button[phx-value-tab="following"]|) |> render_click()

      assert html =~ "ds-following-tab"
      assert html =~ "Following"
      assert html =~ "Browse all hubs"
      assert html =~ "Discover more"
    end

    # "switch_tab to refer" test removed 2026-04-27 — referral feature parked.

    test "switch_tab to rewards shows rewards breakdown", %{conn: conn} do
      user = insert_user(%{slug: "rewardtab"})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/member/rewardtab")

      html = view |> element(~s|button[phx-value-tab="rewards"]|) |> render_click()

      assert html =~ "ds-rewards-tab"
      assert html =~ "Rewards"
      assert html =~ "Lifetime BUX earned"
      assert html =~ "By source"
      assert html =~ "Reading articles"
      assert html =~ "X shares"
      # Referrals subsection asserted previously removed 2026-04-27 alongside the rewards-tab Referrals card.
    end

    test "switch_tab to settings shows account details", %{conn: conn} do
      user = insert_user(%{slug: "settingstab", username: "settingsuser"})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/member/settingstab")

      html = view |> element(~s|.ds-profile-tabs button[phx-value-tab="settings"]|) |> render_click()

      assert html =~ "ds-settings-tab"
      assert html =~ "Settings"
      assert html =~ "Account details"
      assert html =~ "Connected accounts"
      # "Danger zone" was retired in the settings redesign.
      assert html =~ "settingsuser"
    end

    test "switch_tab back to activity shows activity table", %{conn: conn} do
      user = insert_user(%{slug: "backtab"})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/member/backtab")

      # Switch to settings then back to activity
      view |> element(~s|.ds-profile-tabs button[phx-value-tab="settings"]|) |> render_click()
      html = view |> element(~s|button[phx-value-tab="activity"]|) |> render_click()

      assert html =~ "ds-activity-tab"
      assert html =~ "Total earned"
    end

    test "tab=settings URL parameter opens settings tab directly", %{conn: conn} do
      user = insert_user(%{slug: "urltab"})
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, "/member/urltab?tab=settings")

      assert html =~ "ds-settings-tab"
      assert html =~ "Account details"
    end
  end

  describe "activity tab" do
    test "renders time period filter chips", %{conn: conn} do
      user = insert_user(%{slug: "periods"})
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/member/periods")

      assert html =~ "24H"
      assert html =~ "7D"
      assert html =~ "30D"
      assert html =~ "ALL"
    end

    test "shows empty state when no activities", %{conn: conn} do
      user = insert_user(%{slug: "noacts"})
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/member/noacts")

      assert html =~ "No activity yet"
    end

    test "set_time_period event changes period filter", %{conn: conn} do
      user = insert_user(%{slug: "period-chg"})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/member/period-chg")

      html = view |> element(~s|button[phx-value-period="7d"]|) |> render_click()

      assert html =~ "7 days"
    end
  end

  describe "security" do
    test "anonymous user sees public member view (no redirect)", %{conn: conn} do
      insert_user(%{slug: "secure-anon", username: "AnonTarget"})

      # Anonymous access now renders the public member view (not a redirect)
      {:ok, _view, html} = live(conn, ~p"/member/secure-anon")

      # Should show public view markers
      assert html =~ "ds-public-member"
      assert html =~ "AnonTarget"
      assert html =~ "Author profile"
    end

    test "member not found redirects to home", %{conn: conn} do
      user = insert_user(%{slug: "finder"})
      conn = log_in_user(conn, user)

      assert {:error, {:live_redirect, redirect}} = live(conn, ~p"/member/nonexistent-slug-here")
      assert redirect.to == "/"
      assert redirect.flash["error"] =~ "not found"
    end

    test "non-owner sees public view instead of redirect", %{conn: conn} do
      _target = insert_user(%{slug: "public-target", username: "TargetUser"})
      viewer = insert_user(%{slug: "viewer"})
      conn = log_in_user(conn, viewer)

      {:ok, _view, html} = live(conn, ~p"/member/public-target")

      # Should show public view, not owner view
      assert html =~ "ds-public-member"
      assert html =~ "TargetUser"
      assert html =~ "Author profile"
      # Should NOT show owner-only elements
      refute html =~ "ds-profile-hero"
      refute html =~ "Your profile"
      refute html =~ "ds-profile-tabs"
    end
  end

  describe "settings tab content" do
    test "shows X connect link when not connected", %{conn: conn} do
      user = insert_user(%{slug: "xconn"})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/member/xconn")
      html = view |> element(~s|.ds-profile-tabs button[phx-value-tab="settings"]|) |> render_click()

      assert html =~ "X (Twitter)"
      # When not connected, should show Connect option
      assert html =~ "Connect"
    end

    test "shows telegram connect button", %{conn: conn} do
      user = insert_user(%{slug: "tgconn"})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/member/tgconn")
      html = view |> element(~s|.ds-profile-tabs button[phx-value-tab="settings"]|) |> render_click()

      assert html =~ "Telegram"
      assert html =~ "connect_telegram"
    end

    test "shows email verify button in settings when not verified", %{conn: conn} do
      user = insert_user(%{slug: "emailset", email_verified: false, email: "test@example.com"})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/member/emailset")
      html = view |> element(~s|.ds-profile-tabs button[phx-value-tab="settings"]|) |> render_click()

      assert html =~ "Unverified"
      assert html =~ "open_email_verification"
    end

    test "shows auth method as Solana wallet", %{conn: conn} do
      user = insert_user(%{slug: "authmethod"})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/member/authmethod")
      html = view |> element(~s|.ds-profile-tabs button[phx-value-tab="settings"]|) |> render_click()

      assert html =~ "Authentication method"
      assert html =~ "Solana wallet"
      assert html =~ "Wallet Standard"
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # PUBLIC MEMBER VIEW TESTS
  # ═══════════════════════════════════════════════════════════════

  describe "public member view · identity hero" do
    test "renders public profile hero with username and slug", %{conn: conn} do
      insert_user(%{slug: "pub-hero", username: "PublicHero"})

      {:ok, _view, html} = live(conn, ~p"/member/pub-hero")

      assert html =~ "ds-public-member"
      assert html =~ "PublicHero"
      assert html =~ "@pub-hero"
      assert html =~ "Author profile"
    end

    test "renders bio when present", %{conn: conn} do
      insert_user(%{slug: "pub-bio", username: "BioUser", bio: "I write about Solana DeFi."})

      {:ok, _view, html} = live(conn, ~p"/member/pub-bio")

      assert html =~ "I write about Solana DeFi."
    end

    test "hides bio when nil", %{conn: conn} do
      insert_user(%{slug: "pub-nobio", username: "NoBioUser", bio: nil})

      {:ok, _view, html} = live(conn, ~p"/member/pub-nobio")

      refute html =~ "text-neutral-700 font-medium leading-relaxed"
    end

    test "shows Verified writer badge for authors", %{conn: conn} do
      insert_user(%{slug: "pub-author", username: "AuthorUser", is_author: true})

      {:ok, _view, html} = live(conn, ~p"/member/pub-author")

      assert html =~ "Verified writer"
    end

    test "hides Verified writer badge for non-authors", %{conn: conn} do
      insert_user(%{slug: "pub-noauthor", username: "RegularUser", is_author: false})

      {:ok, _view, html} = live(conn, ~p"/member/pub-noauthor")

      refute html =~ "Verified writer"
    end

    test "shows member since date", %{conn: conn} do
      insert_user(%{slug: "pub-since", username: "SinceUser"})

      {:ok, _view, html} = live(conn, ~p"/member/pub-since")

      assert html =~ "Member since"
    end

    test "renders Notify me and Share buttons (D17: no Follow)", %{conn: conn} do
      insert_user(%{slug: "pub-btns", username: "BtnUser"})

      {:ok, _view, html} = live(conn, ~p"/member/pub-btns")

      assert html =~ "Notify me"
      # Follow button should NOT be present (D17)
      refute html =~ "Follow"
    end
  end

  describe "public member view · stat cards" do
    test "renders 3 stat cards (Posts, Reads, BUX paid)", %{conn: conn} do
      insert_user(%{slug: "pub-stats", username: "StatUser"})

      {:ok, _view, html} = live(conn, ~p"/member/pub-stats")

      assert html =~ "Posts published"
      assert html =~ "Total reads"
      assert html =~ "BUX paid out"
      # Followers card should NOT be present (D17)
      refute html =~ "Followers"
    end
  end

  describe "public member view · tabs" do
    test "renders 4-tab navigation (Articles/Videos/Hubs/About)", %{conn: conn} do
      insert_user(%{slug: "pub-tabs", username: "TabUser"})

      {:ok, _view, html} = live(conn, ~p"/member/pub-tabs")

      assert html =~ "ds-public-tabs"
      assert html =~ "Articles"
      assert html =~ "Videos"
      assert html =~ "Hubs"
      assert html =~ "About"
    end

    test "does not show owner tabs (Settings/Following/Refer/Rewards)", %{conn: conn} do
      insert_user(%{slug: "pub-notabs", username: "NoOwnerTabs"})

      {:ok, _view, html} = live(conn, ~p"/member/pub-notabs")

      # Owner-only tabs should NOT appear in public view
      refute html =~ "ds-profile-tabs"
      refute html =~ "Rewards"
    end
  end

  describe "public member view · articles tab" do
    test "shows empty state when no posts", %{conn: conn} do
      insert_user(%{slug: "pub-noposts", username: "NoPosts"})

      {:ok, _view, html} = live(conn, ~p"/member/pub-noposts")

      assert html =~ "No posts published yet"
    end

    test "shows post cards when author has posts", %{conn: conn} do
      user = insert_user(%{slug: "pub-posts", username: "PostAuthor"})
      hub = Repo.insert!(%BlocksterV2.Blog.Hub{
        name: "TestHub",
        slug: "testhub-pub-#{System.unique_integer([:positive])}",
        color_primary: "#00FFA3",
        color_secondary: "#00DC82",
        token: "TST",
        tag_name: "testhub-pub"
      })
      Repo.insert!(%BlocksterV2.Blog.Post{
        title: "My Test Article",
        slug: "my-test-article-pub-#{System.unique_integer([:positive])}",
        content: %{"type" => "doc", "content" => [%{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "Some test content for the article."}]}]},
        excerpt: "A short excerpt.",
        published_at: DateTime.truncate(DateTime.utc_now(), :second),
        author_id: user.id,
        hub_id: hub.id,
        view_count: 1234,
        kind: "news"
      })

      {:ok, _view, html} = live(conn, ~p"/member/pub-posts")

      assert html =~ "ds-public-post-card"
      assert html =~ "My Test Article"
      assert html =~ "A short excerpt."
      assert html =~ "TestHub"
    end

    test "shows Published in sidebar with hubs", %{conn: conn} do
      user = insert_user(%{slug: "pub-sidebar", username: "SidebarAuthor"})
      hub = Repo.insert!(%BlocksterV2.Blog.Hub{
        name: "SidebarHub",
        slug: "sidebarhub-#{System.unique_integer([:positive])}",
        color_primary: "#7D00FF",
        color_secondary: "#4A00B8",
        token: "SBH",
        tag_name: "sidebarhub"
      })
      Repo.insert!(%BlocksterV2.Blog.Post{
        title: "Hub Post",
        slug: "hub-post-sidebar-#{System.unique_integer([:positive])}",
        content: %{"type" => "doc", "content" => []},
        published_at: DateTime.truncate(DateTime.utc_now(), :second),
        author_id: user.id,
        hub_id: hub.id
      })

      {:ok, _view, html} = live(conn, ~p"/member/pub-sidebar")

      assert html =~ "Published in"
      assert html =~ "SidebarHub"
      assert html =~ "1 stories"
    end
  end

  describe "public member view · tab switching" do
    test "switching to about tab renders about section", %{conn: conn} do
      insert_user(%{slug: "pub-about", username: "AboutUser", bio: "My bio text here."})

      {:ok, view, _html} = live(conn, ~p"/member/pub-about")

      html = view |> element(~s|.ds-public-tabs button[phx-value-tab="about"]|) |> render_click()

      assert html =~ "About"
      assert html =~ "My bio text here."
      assert html =~ "AboutUser"
    end

    test "switching to hubs tab renders hubs section", %{conn: conn} do
      insert_user(%{slug: "pub-hubstab", username: "HubsUser"})

      {:ok, view, _html} = live(conn, ~p"/member/pub-hubstab")

      html = view |> element(~s|.ds-public-tabs button[phx-value-tab="hubs"]|) |> render_click()

      assert html =~ "Communities"
      assert html =~ "Not published in any hubs yet"
    end

    test "switching to videos tab shows video content", %{conn: conn} do
      insert_user(%{slug: "pub-vidtab", username: "VidUser"})

      {:ok, view, _html} = live(conn, ~p"/member/pub-vidtab")

      html = view |> element(~s|.ds-public-tabs button[phx-value-tab="videos"]|) |> render_click()

      assert html =~ "Video content"
      assert html =~ "No videos published yet"
    end
  end

  describe "public member view · owner still sees owner view" do
    test "owner visiting own profile sees owner template", %{conn: conn} do
      user = insert_user(%{slug: "own-check", username: "OwnerCheck"})
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/member/own-check")

      # Should see owner view markers
      assert html =~ "ds-profile-hero"
      assert html =~ "Your profile"
      # Should NOT see public view
      refute html =~ "ds-public-member"
    end
  end

  describe "public member view · header and footer" do
    test "renders design system header and footer", %{conn: conn} do
      insert_user(%{slug: "pub-hf", username: "HFUser"})

      {:ok, _view, html} = live(conn, ~p"/member/pub-hf")

      assert html =~ "ds-header"
      assert html =~ "ds-footer"
      assert html =~ "Hustle hard. All in on crypto."
    end
  end
end
