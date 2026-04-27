defmodule BlocksterV2Web.NotificationLive.IndexTest do
  @moduledoc """
  Tests for the redesigned Notifications pages (Wave 6 Page #18).

  Routes: /notifications, /notifications/referrals, /notifications/settings
  LiveViews: NotificationLive.Index, NotificationLive.Referrals, NotificationSettingsLive.Index

  Tests cover: DS header/footer, notification list, filter chips,
  empty state, mark-all-read, referral dashboard, settings page.
  """

  use BlocksterV2Web.LiveCase, async: false

  alias BlocksterV2.Repo
  alias BlocksterV2.Accounts.User
  alias BlocksterV2.Notifications.Notification

  setup do
    ensure_mnesia_tables()

    unique = System.unique_integer([:positive])

    user =
      Repo.insert!(%User{
        wallet_address: "NotifTestWallet#{unique}",
        username: "notifuser#{unique}",
        auth_method: "wallet"
      })

    %{user: user}
  end

  defp ensure_mnesia_tables do
    tables = [
      {:referral_stats, :set, [:user_id, :total_referrals, :verified_referrals, :total_bux_earned, :total_rogue_earned, :updated_at]},
      {:referral_earnings, :bag, [:id, :referrer_id, :referrer_wallet, :referee_wallet, :earning_type, :amount, :token, :tx_hash, :commitment_hash, :timestamp], [:referrer_id]}
    ]

    for table <- tables do
      {name, type, attrs, indexes} =
        case table do
          {name, type, attrs, indexes} -> {name, type, attrs, indexes}
          {name, type, attrs} -> {name, type, attrs, []}
        end

      case :mnesia.create_table(name, attributes: attrs, type: type, index: indexes) do
        {:atomic, :ok} -> :ok
        {:aborted, {:already_exists, ^name}} -> :ok
        _other -> :ok
      end
    end
  end

  # ============ /notifications — Notification Index ============

  describe "notification index · anonymous" do
    test "renders the page with DS header", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/notifications")

      assert html =~ "ds-site-header"
    end

    test "renders the DS footer", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/notifications")

      # Footer mission line — sentinel for the redesigned dark <.footer />.
      assert html =~ "Hustle hard. All in on crypto."
    end

    test "renders the page hero with eyebrow", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/notifications")

      assert html =~ "Notifications"
    end

    test "renders filter chips", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/notifications")

      assert html =~ "All"
      assert html =~ "Unread"
      assert html =~ "Read"
    end

    test "renders empty state when no notifications", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/notifications")

      assert html =~ "All caught up"
    end

    test "renders settings link", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/notifications")

      assert html =~ "/notifications/settings"
    end

    # `renders referrals link` removed 2026-04-27 — referral feature parked,
    # the /notifications/referrals route + corresponding link card on
    # /notifications were both deleted. See router.ex + notification_live/index.ex.
  end

  describe "notification index · logged in" do
    setup %{conn: conn, user: user} do
      %{conn: log_in_user(conn, user)}
    end

    test "renders the page when logged in", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/notifications")

      assert html =~ "ds-site-header"
      assert html =~ "Notifications"
    end

    test "renders empty state when user has no notifications", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/notifications")

      assert html =~ "All caught up"
    end

    test "renders notifications when user has them", %{conn: conn, user: user} do
      _notification =
        Repo.insert!(%Notification{
          user_id: user.id,
          type: "new_article",
          category: "content",
          title: "New Article Published",
          body: "Check out this great article"
        })

      {:ok, _view, html} = live(conn, "/notifications")

      assert html =~ "New Article Published"
      assert html =~ "Check out this great article"
    end

    test "unread notification shows lime accent bar", %{conn: conn, user: user} do
      _notification =
        Repo.insert!(%Notification{
          user_id: user.id,
          type: "bux_earned",
          category: "rewards",
          title: "BUX Earned",
          body: "You earned 100 BUX"
        })

      {:ok, _view, html} = live(conn, "/notifications")

      # Unread shows lime accent bar
      assert html =~ "bg-[#CAFC00]"
    end

    test "mark all read button shows when unread exist", %{conn: conn, user: user} do
      _notification =
        Repo.insert!(%Notification{
          user_id: user.id,
          type: "new_article",
          category: "content",
          title: "Unread Notification",
          body: "This is unread"
        })

      {:ok, _view, html} = live(conn, "/notifications")

      assert html =~ "Mark all read"
    end

    test "filter chip click changes active filter", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/notifications")

      html =
        view
        |> element("button[phx-value-status='unread']")
        |> render_click()

      # The "Unread" chip should now be active (dark bg)
      assert html =~ "bg-[#0a0a0a] text-white border-[#0a0a0a]"
    end

    test "notification with action_label shows it", %{conn: conn, user: user} do
      _notification =
        Repo.insert!(%Notification{
          user_id: user.id,
          type: "special_offer",
          category: "offers",
          title: "Special Offer",
          body: "Limited time offer",
          action_url: "/shop",
          action_label: "Shop now"
        })

      {:ok, _view, html} = live(conn, "/notifications")

      assert html =~ "Shop now"
    end
  end

  # ============ /notifications/referrals describe blocks (10 tests)
  # removed 2026-04-27 — referral feature parked. The /notifications/referrals
  # route + NotificationLive.Referrals LV file were both deleted. ============

  # ============ /notifications/settings — Settings Page ============

  describe "notification settings · anonymous" do
    test "renders the page with DS header and footer", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/notifications/settings")

      assert html =~ "ds-site-header"
      # Footer mission line — sentinel for the redesigned dark <.footer />.
      assert html =~ "Hustle hard. All in on crypto."
    end

    test "renders settings title", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/notifications/settings")

      assert html =~ "Notification Settings"
    end

    test "renders login prompt for anonymous", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/notifications/settings")

      assert html =~ "Please log in"
    end

    test "renders back link to notifications", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/notifications/settings")

      assert html =~ "/notifications"
    end
  end

  describe "notification settings · logged in" do
    setup %{conn: conn, user: user} do
      %{conn: log_in_user(conn, user)}
    end

    test "renders email notifications section", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/notifications/settings")

      assert html =~ "Email Notifications"
    end

    test "renders in-app notifications section", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/notifications/settings")

      assert html =~ "In-App Notifications"
    end

    test "renders telegram section", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/notifications/settings")

      assert html =~ "Telegram"
      assert html =~ "Connect your Telegram"
    end

    test "renders unsubscribe section", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/notifications/settings")

      assert html =~ "Unsubscribe all"
    end

    test "renders toggle switches", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/notifications/settings")

      assert html =~ "role=\"switch\""
    end
  end
end
