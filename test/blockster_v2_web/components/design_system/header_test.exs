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

      assert html =~ "ds-why-earn-bux"
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

    test "renders the search trigger button" do
      # The header's search chrome is a button that opens a modal, not an
      # inline input. The actual search `phx-keyup="search_posts"` lives on
      # the modal's input element, which only renders when
      # `@show_search_modal == true`.
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.header current_user={nil} />
        """)

      assert html =~ ~s(phx-click="open_search_modal")
    end
  end

  describe "header/1 · logged-in variant" do
    test "shows BUX balance with 2 decimal places, cart, notifications, and user dropdown" do
      user = %{username: "marcus", wallet_address: "7xQk8mPa3", slug: "marcus", is_author: false, is_admin: false, auth_method: "wallet"}
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
      user = %{username: "marcus", wallet_address: "7xQk8", slug: "marcus", is_author: false, is_admin: false, auth_method: "wallet"}
      assigns = %{user: user}

      html =
        rendered_to_string(~H"""
        <.header current_user={@user} />
        """)

      assert html =~ "My profile"
      assert html =~ ~s(phx-click="disconnect_wallet")
      assert html =~ "/member/marcus"
    end

    # Regression guard. The Wallet link kept disappearing from the user dropdown
    # whenever the WALLET_SELF_CUSTODY_ENABLED env var wasn't set in prod
    # (default off). The link is now always rendered for authenticated users —
    # the env-flag wrapper has been removed. Keep this test green so the link
    # can't get re-gated by accident.
    test "renders the Wallet link in the user dropdown for ALL authenticated users" do
      external_wallet_user = %{
        username: "marcus",
        wallet_address: "7xQk8",
        slug: "marcus",
        is_author: false,
        is_admin: false,
        auth_method: "wallet"
      }

      web3auth_user = %{
        username: "alice",
        wallet_address: "9zPm4",
        slug: "alice",
        is_author: false,
        is_admin: false,
        auth_method: "web3auth_email"
      }

      for user <- [external_wallet_user, web3auth_user] do
        assigns = %{user: user}

        html =
          rendered_to_string(~H"""
          <.header current_user={@user} />
          """)

        assert html =~ ~s(id="ds-user-menu-wallet-link"),
               "Wallet dropdown link missing for auth_method=#{user.auth_method}"

        assert html =~ ~s(href="/wallet"),
               "Wallet href missing for auth_method=#{user.auth_method}"
      end

      # External wallet users see the short label.
      assigns = %{user: external_wallet_user}

      external_html =
        rendered_to_string(~H"""
        <.header current_user={@user} />
        """)

      refute external_html =~ "Wallet &amp; self-custody"

      # Web3Auth users get the extended label + lime pulse dot.
      assigns = %{user: web3auth_user}

      web3_html =
        rendered_to_string(~H"""
        <.header current_user={@user} />
        """)

      assert web3_html =~ "Wallet &amp; self-custody"
      assert web3_html =~ "ds-pulse"
    end

    test "preserves toggle_notification_dropdown handler on the bell" do
      user = %{username: "marcus", wallet_address: "abc", slug: "marcus", is_author: false, is_admin: false, auth_method: "wallet"}
      assigns = %{user: user}

      html =
        rendered_to_string(~H"""
        <.header current_user={@user} />
        """)

      assert html =~ ~s(phx-click="toggle_notification_dropdown")
    end

    test "shows the notification dropdown panel when notification_dropdown_open is true" do
      user = %{username: "marcus", wallet_address: "abc", slug: "marcus", is_author: false, is_admin: false, auth_method: "wallet"}
      assigns = %{user: user}

      html =
        rendered_to_string(~H"""
        <.header current_user={@user} notification_dropdown_open={true} recent_notifications={[]} />
        """)

      assert html =~ "ds-notification-dropdown"
      assert html =~ "No notifications yet"
    end

    test "notification badge caps at 99+" do
      user = %{username: "marcus", wallet_address: "abc", slug: "marcus", is_author: false, is_admin: false, auth_method: "wallet"}
      assigns = %{user: user}

      html =
        rendered_to_string(~H"""
        <.header current_user={@user} unread_notification_count={150} />
        """)

      assert html =~ "99+"
    end

    test "shows admin links when user is_admin" do
      user = %{username: "admin", wallet_address: "abc", slug: "admin", is_author: true, is_admin: true, auth_method: "wallet"}
      assigns = %{user: user}

      html =
        rendered_to_string(~H"""
        <.header current_user={@user} />
        """)

      assert html =~ "Create article"
      assert html =~ "Dashboard"
      assert html =~ "Posts"
    end

    test "renders search results dropdown when show_search_modal + show_search_results are true" do
      # The search results dropdown was moved inside the search modal in the
      # redesign — it no longer appears on the header chrome directly.
      user = %{username: "marcus", wallet_address: "abc", slug: "marcus", is_author: false, is_admin: false, auth_method: "wallet"}
      post = %{slug: "test-post", title: "Test Post", featured_image: "https://example.com/img.jpg", category: %{name: "DeFi"}}
      assigns = %{user: user, post: post}

      html =
        rendered_to_string(~H"""
        <.header
          current_user={@user}
          show_search_modal={true}
          show_search_results={true}
          search_results={[@post]}
        />
        """)

      assert html =~ "Test Post"
      assert html =~ "DeFi"
    end
  end
end
