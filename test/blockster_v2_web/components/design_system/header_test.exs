defmodule BlocksterV2Web.DesignSystem.HeaderTest do
  use ExUnit.Case, async: true
  use Phoenix.Component
  import Phoenix.LiveViewTest
  import BlocksterV2Web.DesignSystem

  describe "header/1 · anonymous variant" do
    test "shows the Connect Wallet button when current_user is nil" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.header current_user={nil} active="home" />
        """)

      assert html =~ "ds-header"
      assert html =~ "Connect Wallet"
      assert html =~ ~s(phx-click="show_wallet_selector")
    end

    test "renders the Blockster wordmark with lime icon" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.header current_user={nil} />
        """)

      assert html =~ "ds-logo"
      assert html =~ "blockster-icon.png"
      assert html =~ ">BL</span>"
      assert html =~ ">CKSTER</span>"
    end

    test "renders the lime Why Earn BUX banner" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.header current_user={nil} />
        """)

      assert html =~ "Why Earn BUX?"
      assert html =~ "Redeem BUX to enter sponsored airdrops."
    end

    test "show_why_earn_bux=false hides the banner" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.header current_user={nil} show_why_earn_bux={false} />
        """)

      refute html =~ "Why Earn BUX?"
    end

    test "highlights the active nav link" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.header current_user={nil} active="hubs" />
        """)

      assert html =~ "border-[#CAFC00]"
    end

    test "renders the search input with phx-keyup handler" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.header current_user={nil} />
        """)

      assert html =~ ~s(phx-keyup="search_posts")
    end
  end

  describe "header/1 · logged-in variant" do
    test "shows BUX balance with 2 decimal places, cart, notifications, and user dropdown" do
      user = %{username: "marcus", wallet_address: "7xQk8mPa3", slug: "marcus", is_author: false, is_admin: false}
      assigns = %{user: user}

      html =
        rendered_to_string(~H"""
        <.header
          current_user={@user}
          active="play"
          bux_balance={12_450}
          cart_item_count={3}
          unread_notification_count={5}
        />
        """)

      assert html =~ "ds-header"
      # BUX balance with 2 decimal places
      assert html =~ "12,450.00"
      # Cart badge
      assert html =~ ~r/>\s*3\s*</
      # Notification badge
      assert html =~ ~r/>\s*5\s*</
      # User dropdown trigger with BUX icon
      assert html =~ "ds-user-dropdown"
      refute html =~ "Connect Wallet"
    end

    test "renders the user dropdown with My Profile and Disconnect" do
      user = %{username: "marcus", wallet_address: "7xQk8", slug: "marcus", is_author: false, is_admin: false}
      assigns = %{user: user}

      html =
        rendered_to_string(~H"""
        <.header current_user={@user} />
        """)

      assert html =~ "My Profile"
      assert html =~ ~s(phx-click="disconnect_wallet")
      assert html =~ "/member/marcus"
    end

    test "preserves toggle_notification_dropdown handler on the bell" do
      user = %{username: "marcus", wallet_address: "abc", slug: "marcus", is_author: false, is_admin: false}
      assigns = %{user: user}

      html =
        rendered_to_string(~H"""
        <.header current_user={@user} />
        """)

      assert html =~ ~s(phx-click="toggle_notification_dropdown")
    end

    test "shows the notification dropdown panel when notification_dropdown_open is true" do
      user = %{username: "marcus", wallet_address: "abc", slug: "marcus", is_author: false, is_admin: false}
      assigns = %{user: user}

      html =
        rendered_to_string(~H"""
        <.header current_user={@user} notification_dropdown_open={true} recent_notifications={[]} />
        """)

      assert html =~ "ds-notification-dropdown"
      assert html =~ "No notifications yet"
    end

    test "notification badge caps at 99+" do
      user = %{username: "marcus", wallet_address: "abc", slug: "marcus", is_author: false, is_admin: false}
      assigns = %{user: user}

      html =
        rendered_to_string(~H"""
        <.header current_user={@user} unread_notification_count={150} />
        """)

      assert html =~ "99+"
    end

    test "shows admin links when user is_admin" do
      user = %{username: "admin", wallet_address: "abc", slug: "admin", is_author: true, is_admin: true}
      assigns = %{user: user}

      html =
        rendered_to_string(~H"""
        <.header current_user={@user} />
        """)

      assert html =~ "Create Article"
      assert html =~ "Dashboard"
      assert html =~ "Posts"
    end

    test "renders search results dropdown when show_search_results is true" do
      user = %{username: "marcus", wallet_address: "abc", slug: "marcus", is_author: false, is_admin: false}
      post = %{slug: "test-post", title: "Test Post", featured_image: "https://example.com/img.jpg", category: %{name: "DeFi"}}
      assigns = %{user: user, post: post}

      html =
        rendered_to_string(~H"""
        <.header current_user={@user} show_search_results={true} search_results={[@post]} />
        """)

      assert html =~ "Test Post"
      assert html =~ "DeFi"
    end
  end
end
