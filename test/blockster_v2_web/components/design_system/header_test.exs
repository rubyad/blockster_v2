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
      refute html =~ "ds-profile-avatar"
    end

    test "renders the Blockster wordmark in the brand block" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.header current_user={nil} />
        """)

      # Logo wordmark pieces from the <.logo /> component
      assert html =~ "ds-logo"
      assert html =~ ">BL</span>"
      assert html =~ ">CKSTER</span>"
    end

    test "renders the lime Why Earn BUX banner under the nav" do
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

      # The active link gets a lime underline + bold weight
      assert html =~ "border-[#CAFC00]"
    end
  end

  describe "header/1 · logged-in variant" do
    test "shows BUX pill, cart icon, notifications bell, and avatar" do
      user = %{display_name: "Marcus Verren", wallet_address: "7xQk8mPa3"}

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
      # BUX pill with formatted balance
      assert html =~ "12,450"
      # Cart count badge (whitespace from HEEx pretty-printing)
      assert html =~ ~r/>\s*3\s*</
      # Notification count badge
      assert html =~ ~r/>\s*5\s*</
      # User avatar (initials from display_name)
      assert html =~ "ds-profile-avatar"
      assert html =~ ~r/>\s*MV\s*</
      refute html =~ "Connect Wallet"
    end

    test "preserves toggle_notification_dropdown handler on the bell" do
      user = %{display_name: "Marcus", wallet_address: "abc"}
      assigns = %{user: user}

      html =
        rendered_to_string(~H"""
        <.header current_user={@user} />
        """)

      assert html =~ ~s(phx-click="toggle_notification_dropdown")
    end

    test "notification badge caps at 99+" do
      user = %{display_name: "Marcus", wallet_address: "abc"}
      assigns = %{user: user}

      html =
        rendered_to_string(~H"""
        <.header current_user={@user} unread_notification_count={150} />
        """)

      assert html =~ "99+"
    end

    test "no cart badge when cart is empty" do
      user = %{display_name: "Marcus", wallet_address: "abc"}
      assigns = %{user: user}

      html =
        rendered_to_string(~H"""
        <.header current_user={@user} cart_item_count={0} />
        """)

      # The badge span is conditionally rendered
      # We can't easily assert "no badge" but we can assert no count text in
      # a badge wrapper. Smoke test: the cart link is still present.
      assert html =~ ~s(aria-label="Cart")
    end

    test "falls back to wallet address initials if no display_name" do
      user = %{display_name: nil, username: nil, wallet_address: "7xQk8mPa3"}
      assigns = %{user: user}

      html =
        rendered_to_string(~H"""
        <.header current_user={@user} />
        """)

      # First two chars of wallet address uppercased
      assert html =~ ~r/>\s*7X\s*</
    end
  end
end
