defmodule BlocksterV2Web.WalletAuthEventsTest do
  @moduledoc """
  Integration tests for `WalletAuthEvents` — verifies the new Phase 5 social
  login event handlers push the correct events to the Web3Auth JS hook and
  transition socket assigns into the right connecting state.

  Uses a tiny throwaway LiveView that `use BlocksterV2Web.WalletAuthEvents` so
  we exercise the injected handlers without depending on a full page mount.
  """
  # ConnCase imports Plug.Conn which defines assign/3 — conflicts with
  # Phoenix.Component.assign/3 that the WalletAuthEvents macro relies on.
  # Use plain ExUnit and the LiveViewTest helpers directly.
  use ExUnit.Case, async: true

  import Plug.Test
  import Phoenix.LiveViewTest
  @endpoint BlocksterV2Web.Endpoint

  # Minimal host LiveView that pulls in the shared handlers.
  defmodule HostLive do
    use Phoenix.LiveView
    use BlocksterV2Web.WalletAuthEvents

    @impl true
    def mount(_params, _session, socket) do
      defaults = BlocksterV2Web.WalletAuthEvents.default_assigns()
      socket =
        Enum.reduce(defaults, socket, fn {k, v}, s ->
          Phoenix.Component.assign(s, k, v)
        end)

      socket = Phoenix.Component.assign(socket, :current_user, nil)
      {:ok, socket}
    end

    @impl true
    def render(assigns) do
      ~H"""
      <div id="host-live">
        provider=<%= @connecting_provider %>
        connecting=<%= @connecting %>
        email_stage=<%= @email_otp_stage %>
        email_prefill=<%= @email_prefill %>
      </div>
      """
    end
  end

  defp render_host(conn) do
    live_isolated(conn, HostLive)
  end

  setup do
    conn = Phoenix.ConnTest.build_conn() |> Plug.Test.init_test_session(%{})
    {:ok, conn: conn}
  end

  describe "start_email_login" do
    test "rejects empty email", %{conn: conn} do
      {:ok, view, _html} = render_host(conn)
      render_hook(view, "start_email_login", %{"email" => ""})
      assert render(view) =~ "connecting=false"
    end

    test "rejects invalid email", %{conn: conn} do
      {:ok, view, _html} = render_host(conn)
      render_hook(view, "start_email_login", %{"email" => "not-an-email"})
      assert render(view) =~ "connecting=false"
    end

    test "transitions to email OTP stage on valid email", %{conn: conn} do
      # start_email_login now kicks off our in-app OTP flow (sends code via
      # EmailOtpStore, transitions modal to code-entry). It no longer
      # immediately sets connecting=true — that happens after the code is
      # verified and a JWT is handed to Web3Auth's CUSTOM connector.
      {:ok, view, _html} = render_host(conn)
      render_hook(view, "start_email_login", %{"email" => "adam@blockster.com"})
      html = render(view)
      assert html =~ "email_stage=enter_code"
      assert html =~ "email_prefill=adam@blockster.com"
    end
  end

  describe "start_x/google/apple/telegram_login" do
    test "start_x_login sets connecting_provider=twitter", %{conn: conn} do
      {:ok, view, _html} = render_host(conn)
      render_hook(view, "start_x_login", %{})
      html = render(view)
      assert html =~ "connecting=true"
      assert html =~ "provider=twitter"
    end

    test "start_google_login sets connecting_provider=google", %{conn: conn} do
      {:ok, view, _html} = render_host(conn)
      render_hook(view, "start_google_login", %{})
      html = render(view)
      assert html =~ "provider=google"
    end

    test "start_apple_login sets connecting_provider=apple", %{conn: conn} do
      {:ok, view, _html} = render_host(conn)
      render_hook(view, "start_apple_login", %{})
      html = render(view)
      assert html =~ "provider=apple"
    end

    test "start_telegram_login sets connecting_provider=telegram", %{conn: conn} do
      {:ok, view, _html} = render_host(conn)
      render_hook(view, "start_telegram_login", %{})
      html = render(view)
      assert html =~ "provider=telegram"
    end
  end

  describe "web3auth_authenticated validation" do
    test "rejects missing wallet_address", %{conn: conn} do
      {:ok, view, _html} = render_host(conn)

      render_hook(view, "web3auth_authenticated", %{
        "wallet_address" => "",
        "id_token" => "abc",
        "provider" => "email"
      })

      html = render(view)
      # After rejection, connecting state is reset
      assert html =~ "connecting=false"
    end

    test "rejects missing id_token", %{conn: conn} do
      {:ok, view, _html} = render_host(conn)

      render_hook(view, "web3auth_authenticated", %{
        "wallet_address" => "FUWYT33RLgmCtGsSHvtv2avKLpDFovFDQSnuGjN5wDyP",
        "id_token" => "",
        "provider" => "email"
      })

      assert render(view) =~ "connecting=false"
    end
  end

  describe "web3auth_error" do
    test "clears connecting state + shows flash", %{conn: conn} do
      {:ok, view, _html} = render_host(conn)
      render_hook(view, "start_x_login", %{})
      assert render(view) =~ "connecting=true"

      render_hook(view, "web3auth_error", %{"error" => "popup blocked"})
      html = render(view)
      assert html =~ "connecting=false"
    end
  end

  describe "helpers" do
    test "valid_email? accepts standard shapes" do
      assert BlocksterV2Web.WalletAuthEvents.valid_email?("a@b.co")
      assert BlocksterV2Web.WalletAuthEvents.valid_email?("adam@blockster.com")
      assert BlocksterV2Web.WalletAuthEvents.valid_email?("user+tag@example.co.uk")
    end

    test "valid_email? rejects garbage" do
      refute BlocksterV2Web.WalletAuthEvents.valid_email?("")
      refute BlocksterV2Web.WalletAuthEvents.valid_email?("no-at-sign")
      refute BlocksterV2Web.WalletAuthEvents.valid_email?("two@at@signs")
      refute BlocksterV2Web.WalletAuthEvents.valid_email?("missing.tld@host")
      refute BlocksterV2Web.WalletAuthEvents.valid_email?(nil)
    end

    test "social_login_enabled? reads env with true default" do
      prev = System.get_env("SOCIAL_LOGIN_ENABLED")
      try do
        System.delete_env("SOCIAL_LOGIN_ENABLED")
        assert BlocksterV2Web.WalletAuthEvents.social_login_enabled?()

        System.put_env("SOCIAL_LOGIN_ENABLED", "false")
        refute BlocksterV2Web.WalletAuthEvents.social_login_enabled?()

        System.put_env("SOCIAL_LOGIN_ENABLED", "true")
        assert BlocksterV2Web.WalletAuthEvents.social_login_enabled?()
      after
        if prev, do: System.put_env("SOCIAL_LOGIN_ENABLED", prev), else: System.delete_env("SOCIAL_LOGIN_ENABLED")
      end
    end

    test "web3auth_config returns empty shape when disabled" do
      prev = System.get_env("SOCIAL_LOGIN_ENABLED")
      try do
        System.put_env("SOCIAL_LOGIN_ENABLED", "false")
        cfg = BlocksterV2Web.WalletAuthEvents.web3auth_config()
        assert cfg == %{client_id: ""}
      after
        if prev, do: System.put_env("SOCIAL_LOGIN_ENABLED", prev), else: System.delete_env("SOCIAL_LOGIN_ENABLED")
      end
    end

    test "web3auth_config defaults chain_id and network when env not set" do
      prev_enabled = System.get_env("SOCIAL_LOGIN_ENABLED")
      prev_chain = System.get_env("WEB3AUTH_CHAIN_ID")
      prev_net = System.get_env("WEB3AUTH_NETWORK")

      try do
        System.put_env("SOCIAL_LOGIN_ENABLED", "true")
        System.delete_env("WEB3AUTH_CHAIN_ID")
        System.delete_env("WEB3AUTH_NETWORK")

        cfg = BlocksterV2Web.WalletAuthEvents.web3auth_config()
        assert cfg[:chain_id] == "0x67"
        assert cfg[:network] == "SAPPHIRE_DEVNET"
      after
        restore_env("SOCIAL_LOGIN_ENABLED", prev_enabled)
        restore_env("WEB3AUTH_CHAIN_ID", prev_chain)
        restore_env("WEB3AUTH_NETWORK", prev_net)
      end
    end
  end

  defp restore_env(_key, nil), do: :ok
  defp restore_env(key, val), do: System.put_env(key, val)
end
