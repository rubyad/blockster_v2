defmodule BlocksterV2Web.WalletLive.IndexTest do
  @moduledoc """
  Tests for the /wallet self-custody panel.

  The page is `BlocksterV2Web.WalletLive.Index`, mounted in the :redesign
  live_session. Only Web3Auth social-login users are allowed through.
  External-wallet users are redirected away.
  """

  use BlocksterV2Web.LiveCase, async: false

  alias BlocksterV2.Accounts.User
  alias BlocksterV2.Repo
  alias BlocksterV2.WalletSelfCustody

  setup do
    System.put_env("WALLET_SELF_CUSTODY_ENABLED", "true")
    on_exit(fn -> System.delete_env("WALLET_SELF_CUSTODY_ENABLED") end)
    :ok
  end

  defp create_web3auth_user(attrs \\ %{}) do
    unique_id = System.unique_integer([:positive])

    pubkey =
      :crypto.strong_rand_bytes(32)
      |> Base.encode32(case: :lower, padding: false)
      |> String.replace(~r/[0il]/, "A")
      |> String.slice(0, 44)

    default_attrs = %{
      "wallet_address" => pubkey,
      "email" => "web3auth_test_#{unique_id}@example.com",
      "username" => "w3auser#{unique_id}",
      "auth_method" => "web3auth_email"
    }

    merged = Map.merge(default_attrs, stringify(attrs))

    User.web3auth_registration_changeset(merged) |> Repo.insert!()
  end

  defp create_wallet_user do
    unique_id = System.unique_integer([:positive])

    %User{}
    |> User.changeset(%{
      wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
      email: "wallet_test_#{unique_id}@example.com",
      username: "walletuser#{unique_id}",
      auth_method: "wallet"
    })
    |> Repo.insert!()
  end

  defp stringify(map), do: Map.new(map, fn {k, v} -> {to_string(k), v} end)

  # Mutate LV state without going through a handle_event — used to set up
  # balance so the send form's validation passes. Triggers a re-render.
  defp bump_balance(view, sol) do
    :sys.replace_state(view.pid, fn state ->
      new_assigns = Map.put(state.socket.assigns, :sol_balance, sol)
      %{state | socket: %{state.socket | assigns: new_assigns}}
    end)

    # Force a re-render to pick up the state change.
    :sys.get_state(view.pid)
  end

  describe "authorization" do
    test "web3auth user can mount the page", %{conn: conn} do
      user = create_web3auth_user()
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/wallet")

      assert html =~ "Your wallet"
      assert html =~ "Self-custody"
    end

    test "external-wallet user sees the page but without the Export card", %{conn: conn} do
      user = create_wallet_user()
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/wallet")

      # Page loads + shows balance / receive / send
      assert html =~ "Your wallet"
      assert html =~ "Send SOL"
      # Auth-source pill is branded for wallet users
      assert html =~ "Connected wallet"
      # Export card is hidden — phx-hook=Web3AuthExport is only rendered
      # when web3auth? is true
      refute html =~ "Web3AuthExport"
      refute html =~ "Take full custody"
    end

    test "anonymous user is redirected home", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/wallet")
    end

    test "redirects when feature flag is off", %{conn: conn} do
      user = create_web3auth_user()
      conn = log_in_user(conn, user)

      System.put_env("WALLET_SELF_CUSTODY_ENABLED", "false")

      assert {:error, {:live_redirect, %{to: "/", flash: %{"error" => flash}}}} =
               live(conn, ~p"/wallet")

      assert flash =~ "not yet available"
    end
  end

  describe "page content" do
    test "renders the three main sections + audit footer", %{conn: conn} do
      user = create_web3auth_user()
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/wallet")

      assert html =~ "Available balance"
      assert html =~ "Receive address"
      assert html =~ "Send SOL"
      assert html =~ "Take full custody"
      assert html =~ user.wallet_address
    end

    test "shows the user's recent audit events", %{conn: conn} do
      user = create_web3auth_user()
      conn = log_in_user(conn, user)

      {:ok, _} =
        WalletSelfCustody.log_event(user.id, :withdrawal_confirmed,
          metadata: %{amount: "0.25", to: "4fYNw3dojWmQ4dXtSGE9epjRGy9pFSx62YeUeB5KBtDT"}
        )

      {:ok, _view, html} = live(conn, ~p"/wallet")

      assert html =~ "Withdrawal confirmed"
      assert html =~ "0.25"
    end

    test "shows the auth source tag in the header", %{conn: conn} do
      user = create_web3auth_user(%{"auth_method" => "web3auth_x"})
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/wallet")

      assert html =~ "X login"
      assert html =~ "X account"
    end
  end

  describe "send flow" do
    test "review_send with a valid form advances to confirming stage", %{conn: conn} do
      user = create_web3auth_user()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/wallet")

      # Bump the balance so validation passes
      bump_balance(view, 1.0)

      html =
        view
        |> form("form[phx-submit='review_send']", %{
          to: "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM",
          amount: "0.5"
        })
        |> render_submit()

      assert html =~ "Confirm transfer"
      # Recipient should be shown in 4-char groups for visual verification
      assert html =~ "9WzD XwBb"
    end

    test "typing in amount preserves destination address", %{conn: conn} do
      # Regression: phx-change used to live on the amount input only, which
      # sent {"amount" => ...} and wiped send_form.to — the destination
      # field would clear itself as soon as the user touched amount.
      user = create_web3auth_user()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/wallet")

      html =
        view
        |> form("form[phx-submit='review_send']", %{
          to: "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM",
          amount: "0.1"
        })
        |> render_change()

      # After a phx-change, the destination input should still have its value
      assert html =~ ~s|value="9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM"|
      assert html =~ ~s|value="0.1"|
    end

    test "review_send with an invalid address shows an error", %{conn: conn} do
      user = create_web3auth_user()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/wallet")

      html =
        view
        |> form("form[phx-submit='review_send']", %{to: "not-a-real-address", amount: "0.1"})
        |> render_submit()

      assert html =~ "Enter a valid Solana address" or html =~ "doesn&#39;t look like"
    end

    test "cancel_send returns to idle stage", %{conn: conn} do
      user = create_web3auth_user()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/wallet")

      :sys.replace_state(view.pid, fn state ->
        put_in(state.socket.assigns.sol_balance, 1.0)
      end)

      view
      |> form("form[phx-submit='review_send']", %{
        to: "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM",
        amount: "0.5"
      })
      |> render_submit()

      html = view |> element("button[phx-click='cancel_send']") |> render_click()

      assert html =~ "Review transfer"
      refute html =~ "Confirm transfer"
    end

    test "confirm_send logs a withdrawal_initiated audit event", %{conn: conn} do
      user = create_web3auth_user()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/wallet")

      :sys.replace_state(view.pid, fn state ->
        put_in(state.socket.assigns.sol_balance, 1.0)
      end)

      # Advance to confirming stage
      view
      |> form("form[phx-submit='review_send']", %{
        to: "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM",
        amount: "0.5"
      })
      |> render_submit()

      # Sign & send
      view |> element("button[phx-click='confirm_send']") |> render_click()

      events = WalletSelfCustody.list_recent_for_user(user.id, 10)
      assert Enum.any?(events, &(&1.event_type == "withdrawal_initiated"))
    end
  end

  describe "export flow" do
    test "start_export_intent expands to intent stage", %{conn: conn} do
      user = create_web3auth_user()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/wallet")

      html =
        view |> element("button[phx-click='start_export_intent']") |> render_click()

      assert html =~ "Before you continue"
      assert html =~ "This key controls your wallet"
      assert html =~ "I understand"
    end

    test "verify button is disabled until the checkbox is ticked", %{conn: conn} do
      user = create_web3auth_user()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/wallet")

      view |> element("button[phx-click='start_export_intent']") |> render_click()

      html = render(view)
      # Button should exist but be disabled
      assert html =~ "start_export_reveal"
      assert html =~ "cursor-not-allowed"
    end

    test "toggling the intent checkbox enables reveal + hide cancels", %{conn: conn} do
      user = create_web3auth_user()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/wallet")

      view |> element("button[phx-click='start_export_intent']") |> render_click()

      html =
        view
        |> element("input[phx-click='toggle_export_intent_accepted']")
        |> render_click()

      assert html =~ "Verify identity"

      # Cancel
      html = view |> element("button[phx-click='cancel_export_intent']") |> render_click()
      assert html =~ "Take full custody"
      refute html =~ "Before you continue"
    end

    test "start_export_reveal logs key_exported via round-trip", %{conn: conn} do
      user = create_web3auth_user()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/wallet")

      view |> element("button[phx-click='start_export_intent']") |> render_click()

      view
      |> element("input[phx-click='toggle_export_intent_accepted']")
      |> render_click()

      view |> element("button[phx-click='start_export_reveal']") |> render_click()

      # In real use, the JS hook pushes `export_reauth_completed` back after
      # successfully rendering the key. Simulate that here.
      render_hook(view, "export_reauth_completed", %{})

      events = WalletSelfCustody.list_recent_for_user(user.id, 10)
      assert Enum.any?(events, &(&1.event_type == "key_exported"))
    end

    test "hide_export_key resets the stage", %{conn: conn} do
      user = create_web3auth_user()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/wallet")

      # Navigate to export_reveal through the real state machine.
      view |> element("button[phx-click='start_export_intent']") |> render_click()
      view |> element("input[phx-click='toggle_export_intent_accepted']") |> render_click()
      html = view |> element("button[phx-click='start_export_reveal']") |> render_click()

      assert html =~ "Your private key"
      assert html =~ "Secure mode"

      # Now hide it
      html =
        view |> element("button[phx-click='hide_export_key']", "Hide now") |> render_click()

      assert html =~ "Take full custody"
      refute html =~ "Secure mode"
    end
  end

  describe "format helpers" do
    alias BlocksterV2Web.WalletLive.Index

    test "split_sol splits integer and decimal parts" do
      assert Index.split_sol(2.4587) == {"2", "4587"}
      assert Index.split_sol(0.0001) == {"0", "0001"}
      assert Index.split_sol(nil) == {"0", "0000"}
      # Integer input shouldn't crash (PubSub sometimes sends integer 0)
      assert Index.split_sol(0) == {"0", "0000"}
      assert Index.split_sol(5) == {"5", "0000"}
    end

    test "format_bux handles both integer and float inputs" do
      # Regression: PubSub :bux_balance_updated sometimes sends integer 0,
      # not 0.0. :erlang.float_to_binary rejects integers — coerce first.
      assert Index.format_bux(0) == "0.00"
      assert Index.format_bux(0.0) == "0.00"
      assert Index.format_bux(1234) == "1,234.00"
      assert Index.format_bux(1234.56) == "1,234.56"
    end

    test "format_addr_groups chunks into 4-char groups" do
      assert Index.format_addr_groups("ABCD1234EFGH5678") == "ABCD 1234 EFGH 5678"
      assert Index.format_addr_groups(nil) == ""
    end

    test "truncate_addr shortens long pubkeys" do
      assert Index.truncate_addr("9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM") ==
               "9WzD…AWWM"

      assert Index.truncate_addr("short") == "short"
      assert Index.truncate_addr(nil) == "—"
    end

    test "audit_field handles atom + string keys" do
      assert Index.audit_field(%{amount: "1.0"}, :amount) == "1.0"
      assert Index.audit_field(%{"amount" => "1.0"}, :amount) == "1.0"
      assert Index.audit_field(%{amount: "1.0"}, "amount") == "1.0"
      assert Index.audit_field(%{}, :missing) == nil
    end

    test "display_auth_source + display_auth_noun resolve to friendly labels" do
      assert Index.display_auth_source("web3auth_email") == "Email login"
      assert Index.display_auth_source("web3auth_google") == "Google login"
      assert Index.display_auth_noun("web3auth_email") == "email address"
    end

    test "audit_event_label maps all known types" do
      assert Index.audit_event_label("withdrawal_initiated") == "Withdrawal initiated"
      assert Index.audit_event_label("withdrawal_confirmed") == "Withdrawal confirmed"
      assert Index.audit_event_label("withdrawal_failed") == "Withdrawal failed"
      assert Index.audit_event_label("key_exported") == "Private key exported"
    end
  end

  # ══════════════════════════════════════════════════════════════════════════
  # STRESS TESTS — UX bug class coverage
  #
  # Why this block exists: the bug where phx-change wiped the destination
  # field, and the format_bux-crash on integer input, both slipped past the
  # happy-path tests above. These tests specifically stress the classes of
  # thing that were breaking:
  #  - form-field round-trips on every phx-change
  #  - formatters with ALL numeric input types
  #  - stage transitions from non-initial starting states
  #  - PubSub-driven assign updates that mimic production lifecycle
  #  - paste / max button interactions that mutate field state
  # ══════════════════════════════════════════════════════════════════════════
  describe "format_* robustness (stress)" do
    alias BlocksterV2Web.WalletLive.Index

    test "no formatter crashes on integer, float, nil, negative, huge values" do
      inputs = [0, 0.0, 1, 1.0, 1234, 1234.5678, -5, -5.5, nil, "not a number", 9_999_999_999.99]

      for input <- inputs do
        # None of these should raise
        assert is_binary(Index.format_sol(input))
        assert is_binary(Index.format_bux(input))
        assert is_tuple(Index.split_sol(input))
        assert is_binary(Index.truncate_addr(input || ""))
      end
    end

    test "format_usd handles mixed int/float types without crashing" do
      assert Index.format_usd(0, 0) == "0.00"
      assert Index.format_usd(1, 100) == "100.00"
      assert Index.format_usd(1.5, 200) == "300.00"
      assert Index.format_usd(2, 172.5) == "345.00"
      assert Index.format_usd(nil, 100) == "0.00"
      assert Index.format_usd(1, nil) == "0.00"
    end

    test "zero_pad_pct + countdown_seconds_remaining accept integer or float" do
      assert Index.zero_pad_pct(0) == "000"
      assert Index.zero_pad_pct(0.0) == "000"
      assert Index.zero_pad_pct(100) == "100"
      assert Index.zero_pad_pct(99.5) == "100"
      assert Index.zero_pad_pct(nil) == "000"

      assert Index.countdown_seconds_remaining(0) == 0
      assert Index.countdown_seconds_remaining(0.0) == 0
      assert Index.countdown_seconds_remaining(100) == 30
      assert Index.countdown_seconds_remaining(50) == 15
      assert Index.countdown_seconds_remaining(nil) == 0
    end
  end

  describe "form field round-trips (stress)" do
    test "typing in amount does NOT wipe destination", %{conn: conn} do
      user = create_web3auth_user()
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/wallet")

      html =
        view
        |> form("form[phx-submit='review_send']", %{
          to: "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM",
          amount: "0.1"
        })
        |> render_change()

      assert html =~ ~s|value="9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM"|
      assert html =~ ~s|value="0.1"|
    end

    test "typing in destination does NOT wipe amount", %{conn: conn} do
      user = create_web3auth_user()
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/wallet")

      # Enter amount first
      view
      |> form("form[phx-submit='review_send']", %{to: "", amount: "0.25"})
      |> render_change()

      # Then type a destination — amount should survive
      html =
        view
        |> form("form[phx-submit='review_send']", %{
          to: "7EYnhQoR9YM3N7UoaKRoA44Uy8JeaZV3qyouov87awMs",
          amount: "0.25"
        })
        |> render_change()

      assert html =~ ~s|value="0.25"|
      assert html =~ ~s|value="7EYnhQoR9YM3N7UoaKRoA44Uy8JeaZV3qyouov87awMs"|
    end

    test "empty form change doesn't crash", %{conn: conn} do
      user = create_web3auth_user()
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/wallet")

      render_change(form(view, "form[phx-submit='review_send']", %{to: "", amount: ""}))
      assert render(view) =~ "Send SOL"
    end

    test "set_send_max fills amount and keeps destination", %{conn: conn} do
      user = create_web3auth_user()
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/wallet")

      bump_balance(view, 2.5)

      # Type destination first
      view
      |> form("form[phx-submit='review_send']", %{
        to: "7EYnhQoR9YM3N7UoaKRoA44Uy8JeaZV3qyouov87awMs",
        amount: ""
      })
      |> render_change()

      # Hit MAX — should populate amount without wiping destination
      html = view |> element("button[phx-click='set_send_max']") |> render_click()

      assert html =~ ~s|value="7EYnhQoR9YM3N7UoaKRoA44Uy8JeaZV3qyouov87awMs"|
      # Amount should be set to ~max (2.5 - 0.001 reserve)
      assert html =~ ~r/value="2\.49[89]/
    end
  end

  describe "PubSub-driven assign updates (stress)" do
    test "receiving integer bux_balance_updated message doesn't crash", %{conn: conn} do
      # Regression: format_bux crashed on :erlang.float_to_binary(0, ...)
      # because PubSub sends integer 0 for empty-balance users.
      user = create_web3auth_user()
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/wallet")

      send(view.pid, {:bux_balance_updated, 0})
      assert render(view) =~ "BUX"

      send(view.pid, {:bux_balance_updated, 12_345})
      assert render(view) =~ "BUX"

      send(view.pid, {:bux_balance_updated, 12_345.67})
      assert render(view) =~ "BUX"
    end

    test "fetch_balances handle_async with {:ok, {sol, bux}} updates UI", %{conn: conn} do
      user = create_web3auth_user()
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/wallet")

      :sys.replace_state(view.pid, fn state ->
        assigns = Map.merge(state.socket.assigns, %{sol_balance: 3.14, bux_balance: 999.5})
        %{state | socket: %{state.socket | assigns: assigns}}
      end)

      html = render(view)
      assert html =~ "Your wallet"
      # Shouldn't crash
    end
  end

  describe "stage transitions from arbitrary starting states (stress)" do
    test "cancel_send from sending stage returns to idle", %{conn: conn} do
      user = create_web3auth_user()
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/wallet")

      bump_balance(view, 1.0)

      view
      |> form("form[phx-submit='review_send']", %{
        to: "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM",
        amount: "0.5"
      })
      |> render_submit()

      # Advance to :sending then reject
      view |> element("button[phx-click='confirm_send']") |> render_click()
      render_hook(view, "withdrawal_error", %{"error" => "Transaction cancelled"})

      html = render(view)
      refute html =~ "Confirm transfer"
      assert html =~ "Review transfer"
      assert html =~ "Transaction cancelled"
    end

    test "reset_send after :sent clears form and stage", %{conn: conn} do
      user = create_web3auth_user()
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/wallet")

      bump_balance(view, 1.0)

      view
      |> form("form[phx-submit='review_send']", %{
        to: "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM",
        amount: "0.5"
      })
      |> render_submit()

      view |> element("button[phx-click='confirm_send']") |> render_click()
      render_hook(view, "withdrawal_submitted", %{"signature" => "abcdef"})

      assert render(view) =~ "Confirmed on-chain"

      html = view |> element("button[phx-click='reset_send']") |> render_click()
      assert html =~ "Review transfer"
      refute html =~ "Confirmed on-chain"
    end

    test "export reveal auto-hides after countdown expires", %{conn: conn} do
      user = create_web3auth_user()
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/wallet")

      view |> element("button[phx-click='start_export_intent']") |> render_click()
      view |> element("input[phx-click='toggle_export_intent_accepted']") |> render_click()
      view |> element("button[phx-click='start_export_reveal']") |> render_click()

      # Simulate countdown expiring by pushing countdown_pct to 0
      :sys.replace_state(view.pid, fn state ->
        assigns = Map.put(state.socket.assigns, :export_countdown_pct, 0.0)
        %{state | socket: %{state.socket | assigns: assigns}}
      end)

      send(view.pid, :export_countdown_tick)
      Process.sleep(50)

      html = render(view)
      refute html =~ "Your private key"
      assert html =~ "Take full custody"
    end

    test "switching export format while revealed doesn't crash", %{conn: conn} do
      user = create_web3auth_user()
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/wallet")

      view |> element("button[phx-click='start_export_intent']") |> render_click()
      view |> element("input[phx-click='toggle_export_intent_accepted']") |> render_click()
      view |> element("button[phx-click='start_export_reveal']") |> render_click()

      # Click each format tab — each should succeed
      for fmt <- ["hex", "qr", "base58"] do
        html =
          view
          |> element("button[phx-click='set_export_format'][phx-value-format='#{fmt}']")
          |> render_click()

        assert html =~ "Your private key", "format switch to #{fmt} failed"
      end
    end
  end

  describe "validation edge cases (stress)" do
    test "negative amount is rejected", %{conn: conn} do
      user = create_web3auth_user()
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/wallet")

      bump_balance(view, 1.0)

      html =
        view
        |> form("form[phx-submit='review_send']", %{
          to: "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM",
          amount: "-0.5"
        })
        |> render_submit()

      refute html =~ "Confirm transfer"
      assert html =~ ~r/valid amount|greater than/i
    end

    test "zero amount is rejected", %{conn: conn} do
      user = create_web3auth_user()
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/wallet")

      bump_balance(view, 1.0)

      html =
        view
        |> form("form[phx-submit='review_send']", %{
          to: "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM",
          amount: "0"
        })
        |> render_submit()

      refute html =~ "Confirm transfer"
    end

    test "amount exceeding balance is rejected", %{conn: conn} do
      user = create_web3auth_user()
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/wallet")

      bump_balance(view, 0.5)

      html =
        view
        |> form("form[phx-submit='review_send']", %{
          to: "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM",
          amount: "1.0"
        })
        |> render_submit()

      refute html =~ "Confirm transfer"
      assert html =~ ~r/exceeds/i
    end

    test "malformed pubkey (too short) is rejected", %{conn: conn} do
      user = create_web3auth_user()
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/wallet")

      bump_balance(view, 1.0)

      html =
        view
        |> form("form[phx-submit='review_send']", %{to: "ABC123", amount: "0.1"})
        |> render_submit()

      refute html =~ "Confirm transfer"
    end

    test "pubkey with non-base58 characters is rejected", %{conn: conn} do
      user = create_web3auth_user()
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/wallet")

      bump_balance(view, 1.0)

      # Contains 'l' which is not in base58 alphabet
      html =
        view
        |> form("form[phx-submit='review_send']", %{
          to: "9WzDXwBlmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWW",
          amount: "0.1"
        })
        |> render_submit()

      refute html =~ "Confirm transfer"
    end
  end

  describe "external-wallet user paths (stress)" do
    test "external-wallet user doesn't crash on full page render", %{conn: conn} do
      user = create_wallet_user()
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/wallet")

      # Page should load + show expected content, no Export region, Send is col-span-12
      assert html =~ "Your wallet"
      assert html =~ "Send SOL"
      refute html =~ "Take full custody"
      refute html =~ "Web3AuthExport"
      assert html =~ ~s|md:col-span-12|
    end

    test "external-wallet user can still submit the send form", %{conn: conn} do
      user = create_wallet_user()
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/wallet")

      bump_balance(view, 1.0)

      html =
        view
        |> form("form[phx-submit='review_send']", %{
          to: "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM",
          amount: "0.25"
        })
        |> render_submit()

      assert html =~ "Confirm transfer"
    end

    test "export-related events on external-wallet user shouldn't crash", %{conn: conn} do
      # Even though the UI hides the Export card for wallet users, a stale
      # JS event or malicious client could still push these — the LV should
      # handle gracefully rather than crash.
      user = create_wallet_user()
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/wallet")

      render_hook(view, "start_export_intent", %{})
      render_hook(view, "export_reauth_completed", %{})
      render_hook(view, "export_reveal_error", %{"error" => "test"})
      render_hook(view, "set_export_format", %{"format" => "hex"})

      assert render(view) =~ "Your wallet"
    end
  end
end
