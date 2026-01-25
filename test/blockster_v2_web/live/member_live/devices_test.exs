defmodule BlocksterV2Web.MemberLive.DevicesTest do
  use BlocksterV2Web.LiveCase, async: true

  alias BlocksterV2.Accounts
  alias BlocksterV2.Accounts.{User, UserFingerprint}
  alias BlocksterV2.Repo

  import Phoenix.LiveViewTest

  describe "mount /settings/devices" do
    test "redirects to login when user is not authenticated", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/settings/devices")
    end

    test "displays user's devices when authenticated", %{conn: conn} do
      # Create user with 2 devices
      {:ok, user, _session} =
        Accounts.authenticate_email_with_fingerprint(%{
          email: "test@example.com",
          wallet_address: "0xabc",
          smart_wallet_address: "0xdef",
          fingerprint_id: "fp_device1",
          fingerprint_confidence: 0.99
        })

      # Add second device
      Accounts.authenticate_email_with_fingerprint(%{
        email: "test@example.com",
        wallet_address: "0xabc",
        smart_wallet_address: "0xdef",
        fingerprint_id: "fp_device2",
        fingerprint_confidence: 0.95
      })

      conn = log_in_user(conn, user)

      {:ok, view, html} = live(conn, ~p"/settings/devices")

      # Verify page title
      assert html =~ "Registered Devices"

      # Verify device count displayed
      assert html =~ "You have"
      assert html =~ "2"
      assert html =~ "device(s) registered"

      # Verify primary device shown
      assert html =~ "Primary Device"

      # Verify secondary device shown
      assert html =~ "Secondary Device"

      # Verify confidence scores shown
      assert html =~ "99.0%"
      assert html =~ "95.0%"
    end

    test "displays empty state when user has no devices", %{conn: conn} do
      # Create user without fingerprints (edge case)
      {:ok, user} =
        Repo.insert(%User{
          email: "test@example.com",
          wallet_address: "0xabc",
          smart_wallet_address: "0xdef"
        })

      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/settings/devices")

      assert html =~ "0"
      assert html =~ "device(s) registered"
      assert html =~ "No devices registered"
    end

    test "displays formatted timestamps", %{conn: conn} do
      {:ok, user, _session} =
        Accounts.authenticate_email_with_fingerprint(%{
          email: "test@example.com",
          wallet_address: "0xabc",
          smart_wallet_address: "0xdef",
          fingerprint_id: "fp_device1",
          fingerprint_confidence: 0.99
        })

      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/settings/devices")

      # Verify timestamp formatting (should be like "January 24, 2026 at 10:30 PM")
      assert html =~ "First used:"
      assert html =~ "Last used:"
      assert html =~ ~r/\w+ \d+, \d{4} at \d+:\d+ (AM|PM)/
    end
  end

  describe "remove_device event" do
    setup %{conn: conn} do
      # Create user with 2 devices
      {:ok, user, _session} =
        Accounts.authenticate_email_with_fingerprint(%{
          email: "test@example.com",
          wallet_address: "0xabc",
          smart_wallet_address: "0xdef",
          fingerprint_id: "fp_primary",
          fingerprint_confidence: 0.99
        })

      Accounts.authenticate_email_with_fingerprint(%{
        email: "test@example.com",
        wallet_address: "0xabc",
        smart_wallet_address: "0xdef",
        fingerprint_id: "fp_secondary",
        fingerprint_confidence: 0.95
      })

      conn = log_in_user(conn, user)

      %{conn: conn, user: user}
    end

    test "removes secondary device successfully", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/settings/devices")

      # Remove secondary device
      html =
        view
        |> element("button[phx-value-fingerprint_id='fp_secondary']")
        |> render_click()

      # Verify flash message
      assert html =~ "Device removed successfully"

      # Verify device count updated
      assert html =~ "1"
      assert html =~ "device(s) registered"

      # Verify secondary device no longer shown
      refute html =~ "fp_secondary"

      # Verify primary device still shown
      assert html =~ "Primary Device"

      # Verify database updated
      devices = Accounts.get_user_devices(user.id)
      assert length(devices) == 1
      assert hd(devices).fingerprint_id == "fp_primary"
    end

    test "prevents removal of primary device", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/settings/devices")

      # Verify primary device has "Cannot remove" instead of Remove button
      assert html =~ "Cannot remove"

      # Verify no remove button for primary device
      assert has_element?(view, "button[phx-value-fingerprint_id='fp_primary']") == false
    end

    test "shows error when trying to remove last device", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/settings/devices")

      # Remove secondary device first
      view
      |> element("button[phx-value-fingerprint_id='fp_secondary']")
      |> render_click()

      # Manually add the secondary device back and remove primary to test last device protection
      # (This is testing the backend validation)
      assert {:error, :cannot_remove_last_device} =
               Accounts.remove_user_device(user.id, "fp_primary")
    end

    test "shows confirmation dialog before removing device", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings/devices")

      # Verify remove button has data-confirm attribute
      assert has_element?(
               view,
               "button[phx-value-fingerprint_id='fp_secondary'][data-confirm]"
             )

      # Verify confirmation message content
      element = element(view, "button[phx-value-fingerprint_id='fp_secondary']")
      html = render(element)
      assert html =~ "data-confirm"
      assert html =~ "Are you sure"
    end
  end

  describe "navigation" do
    test "has back to profile link", %{conn: conn} do
      {:ok, user, _session} =
        Accounts.authenticate_email_with_fingerprint(%{
          email: "test@example.com",
          wallet_address: "0xabc",
          smart_wallet_address: "0xdef",
          fingerprint_id: "fp_device1",
          fingerprint_confidence: 0.99
        })

      conn = log_in_user(conn, user)

      {:ok, view, html} = live(conn, ~p"/settings/devices")

      # Verify back link exists
      assert html =~ "Back to Profile"

      # Verify link points to profile
      assert has_element?(view, "a[href='/profile']")
    end
  end

  describe "info box" do
    test "displays device management information", %{conn: conn} do
      {:ok, user, _session} =
        Accounts.authenticate_email_with_fingerprint(%{
          email: "test@example.com",
          wallet_address: "0xabc",
          smart_wallet_address: "0xdef",
          fingerprint_id: "fp_device1",
          fingerprint_confidence: 0.99
        })

      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/settings/devices")

      # Verify info box content
      assert html =~ "About Device Management"
      assert html =~ "primary device"
      assert html =~ "cannot be removed"
      assert html =~ "anti-abuse protection"
    end
  end
end
