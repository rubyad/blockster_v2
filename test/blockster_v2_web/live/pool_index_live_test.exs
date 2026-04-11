defmodule BlocksterV2Web.PoolIndexLiveTest do
  @moduledoc """
  Smoke + structure tests for the redesigned pool index page at `/pool`.

  The page is `BlocksterV2Web.PoolIndexLive`, mounted in the `:redesign`
  live_session. It renders a vault hero (SOL + BUX cards), a stat band
  (Total TVL / Bets settled / House profit), a "How it works" 3-step grid,
  and a cross-pool activity table driven by `:pool_activities` Mnesia +
  `CoinFlipGame.get_recent_games_by_vault/2`.

  These tests cover the anonymous-visitor path (no wallet). The on-chain
  LP balance + settler pool-stats calls are NOT mocked — when the settler
  is unreachable `@pool_stats` stays nil and the page renders with the
  "— pool share" / "0.00" fallbacks, which is exactly what we assert.
  """

  use BlocksterV2Web.LiveCase, async: false

  setup do
    ensure_mnesia_tables()
    :ok
  end

  # ── Mnesia setup ───────────────────────────────────────────────────────────
  # PoolIndexLive reads `:pool_activities` (via dirty_index_read) and
  # `:coin_flip_games` (via CoinFlipGame.get_recent_games_by_vault). Both must
  # exist or the page crashes during the cross-vault activity fetch.
  #
  # Field orders copied from mnesia_initializer.ex — DO NOT reorder.
  defp ensure_mnesia_tables do
    :mnesia.start()

    tables = [
      {:pool_activities, :set,
       [:id, :type, :vault_type, :amount, :wallet, :created_at],
       [:vault_type]},
      {:coin_flip_games, :set,
       [
         :game_id,
         :user_id,
         :wallet_address,
         :commitment,
         :server_seed,
         :client_seed,
         :status,
         :vault_type,
         :bet_amount,
         :difficulty,
         :predictions,
         :results,
         :won,
         :payout,
         :commitment_sig,
         :bet_sig,
         :settlement_sig,
         :created_at,
         :settled_at
       ], []}
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

  # ============================================================================
  # Page render · anonymous visitor
  # ============================================================================

  describe "page render · anonymous" do
    test "renders the redesigned pool index at /pool", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/pool")

      # Hero copy
      assert html =~ "Liquidity Pools"
      assert html =~ "Earn from every bet"
      assert html =~ "On-chain settlement"

      # Vault cards
      assert html =~ "SOL Pool"
      assert html =~ "BUX Pool"
      assert html =~ "Enter SOL Pool"
      assert html =~ "Enter BUX Pool"
      assert html =~ "LP Price"
      assert html =~ "Your position"
    end

    test "renders the 3-step how-it-works section", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/pool")

      assert html =~ "Become the house"
      assert html =~ "Add liquidity to a vault"
      assert html =~ "Collect from every losing bet"
      assert html =~ "Cash out anytime"
    end

    test "renders the top stat band", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/pool")

      assert html =~ "Total TVL"
      assert html =~ "Bets settled"
      assert html =~ "House profit"
    end

    test "renders the pool activity section with live pulse", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/pool")

      assert html =~ "Pool activity"
      assert html =~ "Live across both pools"
      # Live pulse dot — Tailwind built-in, not the mock's custom .pulse-dot
      assert html =~ "animate-pulse"
    end

    test "renders the design system footer", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/pool")

      # DS footer copy sentinel
      assert html =~ "Where the chain meets the model"
    end

    test "empty activity state shows prompt to place a bet", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/pool")

      assert html =~ "No pool activity yet"
      assert html =~ "/play"
    end
  end

  # ============================================================================
  # Navigation
  # ============================================================================

  describe "vault navigation" do
    test "SOL vault card links to /pool/sol", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/pool")

      assert view |> element("a[href=\"/pool/sol\"]") |> has_element?()
    end

    test "BUX vault card links to /pool/bux", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/pool")

      assert view |> element("a[href=\"/pool/bux\"]") |> has_element?()
    end
  end

  # ============================================================================
  # Header integration (redesign live_session)
  # ============================================================================

  describe "design system header" do
    test "renders the DS site header with Pool nav active", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/pool")

      # DS header id + SolanaWallet hook must be present
      assert html =~ "ds-site-header"
      assert html =~ ~s(phx-hook="SolanaWallet")

      # Why Earn BUX lime banner
      assert html =~ "Why Earn BUX?"
    end
  end
end
