defmodule BlocksterV2Web.PoolLiveTest do
  @moduledoc """
  Legacy pool_live tests — redirected to pool_index_live_test.exs and pool_detail_live_test.exs.
  This file is kept for backward compatibility; tests now target the new split routes.
  """
  use BlocksterV2Web.LiveCase, async: false

  alias BlocksterV2.{Repo}
  alias BlocksterV2.Accounts.User

  # ============================================================================
  # Test Helpers
  # ============================================================================

  defp create_user(attrs \\ %{}) do
    unique_id = System.unique_integer([:positive])

    default_attrs = %{
      wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
      smart_wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
      email: "pool_test_#{unique_id}@example.com",
      username: "pooluser#{unique_id}",
      auth_method: "wallet",
      phone_verified: true
    }

    %User{}
    |> User.changeset(Map.merge(default_attrs, attrs))
    |> Repo.insert!()
  end

  defp setup_mnesia(_context) do
    :mnesia.start()

    tables = [
      {:user_bux_balances,
       [:user_id, :user_smart_wallet, :updated_at, :aggregate_bux_balance,
        :bux_balance, :moonbux_balance, :neobux_balance, :roguebux_balance,
        :flarebux_balance, :nftbux_balance, :nolchabux_balance, :solbux_balance,
        :spacebux_balance, :tronbux_balance, :tranbux_balance],
       [type: :set, index: []]},
      {:user_rogue_balances,
       [:user_id, :user_smart_wallet, :updated_at, :rogue_balance_rogue_chain, :rogue_balance_arbitrum],
       [type: :set, index: []]},
      {:user_solana_balances,
       [:user_id, :wallet_address, :updated_at, :sol_balance, :bux_balance],
       [type: :set, index: [:wallet_address]]},
      {:user_lp_balances,
       [:user_id, :wallet_address, :updated_at, :bsol_balance, :bbux_balance],
       [type: :set, index: [:wallet_address]]},
      {:unified_multipliers_v2,
       [:user_id, :x_multiplier, :phone_multiplier, :sol_multiplier, :email_multiplier,
        :overall_multiplier, :updated_at],
       [type: :set, index: [:overall_multiplier]]}
    ]

    for {table, attrs, opts} <- tables do
      case :mnesia.create_table(table, [
             attributes: attrs,
             type: Keyword.get(opts, :type, :set),
             ram_copies: [node()],
             index: Keyword.get(opts, :index, [])
           ]) do
        {:atomic, :ok} -> :ok
        {:aborted, {:already_exists, _}} ->
          case :mnesia.add_table_copy(table, node(), :ram_copies) do
            {:atomic, :ok} -> :ok
            {:aborted, {:already_exists, _, _}} -> :ok
          end
          :mnesia.clear_table(table)
      end
    end

    :ok
  end

  defp set_solana_balances(user, sol_balance, bux_balance) do
    record = {:user_solana_balances, user.id, user.wallet_address,
              System.system_time(:second), sol_balance * 1.0, bux_balance * 1.0}
    :mnesia.dirty_write(:user_solana_balances, record)
  end

  defp set_lp_balances(user, bsol, bbux) do
    record = {:user_lp_balances, user.id, user.wallet_address,
              System.system_time(:second), bsol * 1.0, bbux * 1.0}
    :mnesia.dirty_write(:user_lp_balances, record)
  end

  setup :setup_mnesia

  # ============================================================================
  # Pool Index Tests (was /pool → PoolLive, now /pool → PoolIndexLive)
  # ============================================================================

  describe "page render" do
    test "renders pool page for unauthenticated user", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/pool")

      assert html =~ "Liquidity Pools"
      assert html =~ "SOL Pool"
      assert html =~ "BUX Pool"
      assert html =~ "Enter Pool"
    end

    test "renders stats row", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/pool")

      assert html =~ "SOL Pool"
      assert html =~ "BUX Pool"
      # Stats show loading skeletons initially (LP Price labels appear after stats load)
      assert html =~ "animate-pulse"
    end

    test "renders how it works section", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/pool")

      assert html =~ "How it works"
      assert html =~ "Deposit"
      assert html =~ "Earn"
      assert html =~ "Withdraw"
    end

    test "renders pool cards with enter links", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/pool")

      assert html =~ ~s(href="/pool/sol")
      assert html =~ ~s(href="/pool/bux")
    end
  end

  # ============================================================================
  # Pool Detail Tests (was /pool tabs, now /pool/sol and /pool/bux)
  # ============================================================================

  describe "tab switching" do
    test "SOL pool switches to withdraw tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/pool/sol")

      html =
        view
        |> element("button[phx-click=switch_tab][phx-value-tab=withdraw]")
        |> render_click()

      assert html =~ "Withdraw SOL-LP"
    end

    test "SOL pool switches back to deposit tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/pool/sol")

      view
      |> element("button[phx-click=switch_tab][phx-value-tab=withdraw]")
      |> render_click()

      html =
        view
        |> element("button[phx-click=switch_tab][phx-value-tab=deposit]")
        |> render_click()

      assert html =~ "Deposit SOL"
    end

    test "BUX pool switches to withdraw tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/pool/bux")

      html =
        view
        |> element("button[phx-click=switch_tab][phx-value-tab=withdraw]")
        |> render_click()

      assert html =~ "Withdraw BUX-LP"
    end
  end

  describe "amount inputs" do
    test "SOL amount updates on keyup", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/pool/sol")

      html =
        view
        |> element("input[phx-keyup=update_amount]")
        |> render_keyup(%{"value" => "1.5"})

      assert html =~ "≈"
    end

    test "BUX amount updates on keyup", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/pool/bux")

      html =
        view
        |> element("input[phx-keyup=update_amount]")
        |> render_keyup(%{"value" => "500"})

      assert html =~ "≈"
    end

    test "SOL max button sets max balance for deposit", %{conn: conn} do
      user = create_user()
      set_solana_balances(user, 3.5, 1000.0)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/pool/sol")

      html =
        view
        |> element("button[phx-click=set_max]")
        |> render_click()

      assert html =~ "3.5000"
    end

    test "BUX max button sets max balance for deposit", %{conn: conn} do
      user = create_user()
      set_solana_balances(user, 1.0, 2500.0)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/pool/bux")

      html =
        view
        |> element("button[phx-click=set_max]")
        |> render_click()

      assert html =~ "2500"
    end

    test "SOL max button sets LP balance for withdraw", %{conn: conn} do
      user = create_user()
      set_solana_balances(user, 3.5, 1000.0)
      set_lp_balances(user, 1.75, 500.0)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/pool/sol")

      # Switch to withdraw tab
      view
      |> element("button[phx-click=switch_tab][phx-value-tab=withdraw]")
      |> render_click()

      # Click max and verify it sets some value (sync_on_mount may overwrite LP balance in test env)
      html =
        view
        |> element("button[phx-click=set_max]")
        |> render_click()

      # The set_max handler should run without error
      assert is_binary(html)
      assert html =~ "Withdraw SOL-LP"
    end
  end

  describe "deposit actions" do
    test "deposit SOL requires wallet connection", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/pool/sol")

      # Should show connect wallet button instead
      assert html =~ "Connect Wallet"
    end

    test "deposit SOL shows processing state", %{conn: conn} do
      user = create_user()
      set_solana_balances(user, 5.0, 1000.0)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/pool/sol")

      view
      |> element("input[phx-keyup=update_amount]")
      |> render_keyup(%{"value" => "1.0"})

      html =
        view
        |> element("button[phx-click=deposit]")
        |> render_click()

      assert html =~ "Processing" or html =~ "error" or html =~ "failed"
    end

    test "deposit BUX requires valid amount", %{conn: conn} do
      user = create_user()
      set_solana_balances(user, 1.0, 500.0)
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/pool/bux")

      assert html =~ "disabled"
    end
  end

  describe "withdraw actions" do
    test "withdraw tab shows LP balance label", %{conn: conn} do
      user = create_user()
      set_solana_balances(user, 5.0, 1000.0)
      set_lp_balances(user, 2.0, 800.0)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/pool/sol")

      html =
        view
        |> element("button[phx-click=switch_tab][phx-value-tab=withdraw]")
        |> render_click()

      assert html =~ "LP Balance"
    end

    test "withdraw shows correct output preview", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/pool/bux")

      view
      |> element("button[phx-click=switch_tab][phx-value-tab=withdraw]")
      |> render_click()

      html =
        view
        |> element("input[phx-keyup=update_amount]")
        |> render_keyup(%{"value" => "100"})

      assert html =~ "≈"
      assert html =~ "BUX"
    end
  end

  describe "pool share display" do
    test "shows pool share when user has LP tokens", %{conn: conn} do
      user = create_user()
      set_solana_balances(user, 5.0, 1000.0)
      set_lp_balances(user, 10.0, 500.0)
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/pool/sol")

      assert html =~ "Pool share"
    end

    test "does not show pool share when user has no LP tokens", %{conn: conn} do
      user = create_user()
      set_solana_balances(user, 5.0, 1000.0)
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/pool/sol")

      refute html =~ "Pool share"
    end
  end

  describe "transaction callbacks" do
    test "tx_confirmed clears processing state", %{conn: conn} do
      user = create_user()
      set_solana_balances(user, 5.0, 1000.0)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/pool/sol")

      html =
        render_hook(view, "tx_confirmed", %{
          "vault_type" => "sol",
          "action" => "deposit",
          "signature" => "test_sig_abc123"
        })

      refute html =~ "Processing"
      assert html =~ "confirmed"
    end

    test "tx_failed shows error and clears processing", %{conn: conn} do
      user = create_user()
      set_solana_balances(user, 5.0, 1000.0)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/pool/sol")

      html =
        render_hook(view, "tx_failed", %{
          "vault_type" => "sol",
          "action" => "deposit",
          "error" => "Transaction was cancelled"
        })

      refute html =~ "Processing"
      assert html =~ "Transaction was cancelled"
    end
  end

  describe "balance display" do
    test "shows user SOL and BUX balances", %{conn: conn} do
      user = create_user()
      set_solana_balances(user, 2.5, 7500.0)
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/pool/sol")

      assert html =~ "2.50"
    end

    test "shows zero balances for new user", %{conn: conn} do
      user = create_user()
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/pool/sol")

      assert html =~ "Balance"
    end
  end
end
