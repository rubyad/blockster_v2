defmodule BlocksterV2Web.BankrollLiveTest do
  use BlocksterV2Web.LiveCase, async: false

  alias BlocksterV2.{Repo, Accounts.User}

  setup do
    ensure_mnesia_tables()

    unique = System.unique_integer([:positive])

    {:ok, user} =
      %User{}
      |> Ecto.Changeset.change(%{
        email: "bankroll_test_#{unique}@test.com",
        wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
        smart_wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}"
      })
      |> Repo.insert()

    on_exit(fn ->
      :mnesia.clear_table(:lp_bux_candles)
    end)

    %{user: user}
  end

  defp ensure_mnesia_tables do
    :mnesia.start()

    tables = [
      {:lp_bux_candles, [:timestamp, :open, :high, :low, :close], :ordered_set, []},
      {:user_bux_balances, [:user_id, :balances], :set, [:user_id]}
    ]

    for {name, attrs, type, index} <- tables do
      case :mnesia.create_table(name, type: type, attributes: attrs, index: index, ram_copies: [node()]) do
        {:atomic, :ok} -> :ok
        {:aborted, {:already_exists, ^name}} -> :ok
        _ -> :ok
      end
    end
  end

  # ============================================================
  # Mount (unauthenticated)
  # ============================================================

  describe "mount (unauthenticated)" do
    test "renders bankroll page with title and pool stats", %{conn: conn} do
      {:ok, view, html} = live(conn, "/bankroll")
      assert html =~ "BUX Bankroll"
      # Pool stats load asynchronously - initial render shows loading state
      assert html =~ "Loading pool data..." or html =~ "Total BUX"

      # After async completes, stats labels appear (with zero values)
      :timer.sleep(300)
      html = render(view)
      assert html =~ "Total BUX"
      assert html =~ "LP-BUX Price"
    end

    test "shows login prompt instead of deposit form", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/bankroll")
      assert html =~ "Log in to deposit"
      assert html =~ "Connect Wallet"
    end

    test "does not show LP balance section for unauthenticated", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/bankroll")
      refute html =~ "Your Position"
    end

    test "shows how it works section", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/bankroll")
      assert html =~ "How It Works"
      assert html =~ "Deposit BUX to receive LP-BUX tokens"
    end
  end

  # ============================================================
  # Mount (authenticated)
  # ============================================================

  describe "mount (authenticated)" do
    test "renders deposit and withdraw tabs", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, "/bankroll")
      assert html =~ "Deposit"
      assert html =~ "Withdraw"
    end

    test "shows deposit form by default", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, "/bankroll")
      assert html =~ "Deposit BUX"
      assert html =~ "You receive"
    end

    test "shows user BUX balance", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, "/bankroll")
      assert html =~ "Balance:"
    end
  end

  # ============================================================
  # Timeframe selection
  # ============================================================

  describe "timeframe selection" do
    test "clicking timeframe tab updates selected", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/bankroll")

      html =
        view
        |> element("button", "7D")
        |> render_click()

      assert html =~ "bg-[#CAFC00]"
    end

    test "all timeframe buttons are rendered", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/bankroll")
      assert html =~ "1H"
      assert html =~ "24H"
      assert html =~ "7D"
      assert html =~ "30D"
      assert html =~ "ALL"
    end
  end

  # ============================================================
  # Deposit flow
  # ============================================================

  describe "deposit flow" do
    test "updating deposit amount shows LP preview", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/bankroll")

      html =
        view
        |> element("input[phx-keyup='update_deposit_amount']")
        |> render_keyup(%{"value" => "1000"})

      assert html =~ "You receive"
      assert html =~ "LP-BUX"
    end

    test "rejects zero deposit amount", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/bankroll")

      view |> element("input[phx-keyup='update_deposit_amount']") |> render_keyup(%{"value" => "0"})
      # Button is disabled for zero amounts; send event directly to test server-side validation
      html = render_hook(view, "deposit_bux", %{})

      assert html =~ "Enter a valid amount"
    end

    test "deposit_confirmed event clears loading and shows success", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/bankroll")

      render_hook(view, "deposit_confirmed", %{"tx_hash" => "0xabc123def456"})
      html = render(view)
      assert html =~ "Deposit confirmed"
    end

    test "deposit_failed event shows error message", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/bankroll")

      render_hook(view, "deposit_failed", %{"error" => "Insufficient BUX"})
      html = render(view)
      assert html =~ "Insufficient BUX"
    end

    test "set_max_deposit fills balance into input", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/bankroll")

      html =
        view
        |> element("button", "Balance:")
        |> render_click()

      # Should update deposit_amount (may be "0" if no balance)
      assert html =~ "Deposit BUX"
    end
  end

  # ============================================================
  # Withdraw flow
  # ============================================================

  describe "withdraw flow" do
    test "switching to withdraw tab shows withdraw form", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/bankroll")

      html =
        view
        |> element("button", "Withdraw")
        |> render_click()

      assert html =~ "Withdraw LP-BUX"
      assert html =~ "Withdrawal Price"
    end

    test "rejects zero withdraw amount", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/bankroll")

      # Switch to withdraw tab
      view |> element("button", "Withdraw") |> render_click()
      view |> element("input[phx-keyup='update_withdraw_amount']") |> render_keyup(%{"value" => "0"})
      # Button is disabled for zero amounts; send event directly to test server-side validation
      html = render_hook(view, "withdraw_bux", %{})

      assert html =~ "Enter a valid amount"
    end

    test "withdraw_confirmed event shows success", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/bankroll")

      render_hook(view, "withdraw_confirmed", %{"tx_hash" => "0xdef789abc"})
      html = render(view)
      assert html =~ "Withdrawal confirmed"
    end

    test "withdraw_failed event shows error", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/bankroll")

      render_hook(view, "withdraw_failed", %{"error" => "Insufficient LP-BUX balance"})
      html = render(view)
      assert html =~ "Insufficient LP-BUX balance"
    end
  end

  # ============================================================
  # PubSub handlers
  # ============================================================

  describe "PubSub handlers" do
    test "lp_bux_price_updated updates displayed price", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/bankroll")

      Phoenix.PubSub.broadcast(
        BlocksterV2.PubSub,
        "lp_bux_price",
        {:lp_bux_price_updated, %{price: 1.2345, candle: nil}}
      )

      :timer.sleep(50)
      html = render(view)
      assert html =~ "1.2345"
    end
  end

  # ============================================================
  # Chart rendering
  # ============================================================

  describe "chart rendering" do
    test "chart container is present with hook", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/bankroll")
      assert html =~ "lp-bux-chart"
      assert html =~ "LPBuxChart"
    end

    test "chart has phx-update=ignore to prevent LiveView overwriting", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/bankroll")
      assert html =~ "phx-update=\"ignore\""
    end
  end

  # ============================================================
  # Tab switching
  # ============================================================

  describe "tab switching" do
    test "deposit tab is active by default", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, "/bankroll")
      assert html =~ "Deposit BUX"
    end

    test "clicking withdraw tab switches to withdraw form", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/bankroll")

      html =
        view
        |> element("button", "Withdraw")
        |> render_click()

      assert html =~ "Withdraw LP-BUX"
      assert html =~ "Withdraw BUX"
    end

    test "switching tabs clears error messages", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/bankroll")

      # Trigger an error first via direct event (button is disabled for zero amounts)
      view |> element("input[phx-keyup='update_deposit_amount']") |> render_keyup(%{"value" => "0"})
      render_hook(view, "deposit_bux", %{})

      # Switch tab should clear error
      html =
        view
        |> element("button", "Withdraw")
        |> render_click()

      refute html =~ "Enter a valid amount"
    end
  end
end
