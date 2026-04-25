defmodule BlocksterV2Web.CoinFlipLiveTest do
  @moduledoc """
  Smoke + structure tests for the redesigned coin flip page.

  The page is `BlocksterV2Web.CoinFlipLive` mounted at `/play` (in the
  `:redesign` live_session as of Wave 3 Page #7). It renders a 3-state
  game card (idle / in-progress / result), a page hero with stat bands,
  an "Your recent games" sidebar, and a recent games table.

  On-chain flow is covered by `coin_flip_game_test.exs` and the settler
  tests. These tests assert the template renders its structure, the
  handlers for bet/difficulty/prediction updates still fire, and the
  route is in the :redesign session.
  """

  use BlocksterV2Web.ConnCase
  import Phoenix.LiveViewTest

  alias BlocksterV2.Repo
  alias BlocksterV2.Accounts.User

  setup do
    ensure_mnesia_tables()
    :ok
  end

  # Ensure the Mnesia tables that CoinFlipLive depends on exist.
  defp ensure_mnesia_tables do
    :mnesia.start()

    tables = [
      {:user_solana_balances, :set,
        [:user_id, :wallet_address, :updated_at, :sol_balance, :bux_balance],
        [:wallet_address]},
      {:unified_multipliers_v2, :set,
        [:user_id, :x_score, :x_multiplier, :phone_multiplier, :sol_multiplier,
         :email_multiplier, :overall_multiplier, :last_updated, :created_at],
        [:overall_multiplier]},
      {:coin_flip_games, :ordered_set,
        [:game_id, :user_id, :wallet_address, :server_seed, :commitment_hash,
         :nonce, :status, :vault_type, :bet_amount, :difficulty, :predictions,
         :results, :won, :payout, :commitment_sig, :bet_sig, :settlement_sig,
         :created_at, :settled_at],
        [:user_id, :wallet_address, :status, :created_at, :commitment_hash]},
      {:user_lp_balances, :set,
        [:user_id, :wallet_address, :updated_at, :bsol_balance, :bbux_balance],
        [:wallet_address]},
      {:bux_booster_user_stats, :set,
        [:key, :user_id, :token_type, :last_updated, :total_games, :total_wins,
         :total_losses, :total_wagered, :total_won, :total_lost, :biggest_win,
         :biggest_loss, :current_streak, :best_streak, :worst_streak],
        [:user_id]}
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

  defp insert_user(attrs) do
    uid = System.unique_integer([:positive])
    defaults = %{
      username: "player#{uid}",
      wallet_address: "PlayerWallet#{uid}",
      slug: "player-#{uid}",
      auth_method: "wallet",
      phone_verified: false,
      email_verified: false,
      is_active: true
    }

    Repo.insert!(struct(User, Map.merge(defaults, attrs)))
  end

  defp log_in_user(conn, user) do
    {:ok, session} = BlocksterV2.Accounts.create_session(user.id)

    conn
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, session.token)
    |> Plug.Conn.put_session("wallet_address", user.wallet_address)
  end

  describe "GET /play · anonymous visitor" do
    test "mounts and renders design system header", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/play")

      assert html =~ "ds-header"
      assert html =~ "ds-site-header"
    end

    test "renders the Coin Flip page hero", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/play")

      assert html =~ "ds-play-hero"
      assert html =~ "Coin Flip"
      assert html =~ "Provably-fair"
      assert html =~ "Pick a side"
    end

    test "renders the 3-card stat band", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/play")

      assert html =~ "SOL Pool"
      assert html =~ "BUX Pool"
      assert html =~ "House Edge"
    end

    test "renders the idle-state game card with difficulty grid", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/play")

      assert html =~ "ds-play-game"
      assert html =~ "difficulty-grid"
      assert html =~ "1.98"
      assert html =~ "31.68"
      assert html =~ "Win one"
      assert html =~ "Win all"
    end

    test "renders the bet amount input and quick presets", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/play")

      assert html =~ "Bet amount"
      assert html =~ "MAX"
      assert html =~ "Potential profit"
    end

    test "renders the prediction row with coin buttons", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/play")

      assert html =~ "Pick your side"
      assert html =~ "toggle_prediction"
    end

    test "renders provably fair collapsible", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/play")

      assert html =~ "Provably fair"
      assert html =~ "Server seed locked"
    end

    test "renders place bet button", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/play")

      assert html =~ "start_game"
      # Button text — before predictions are made, shows "Make your prediction"
      assert html =~ "Make your prediction" or html =~ "Place Bet"
    end

    test "renders the recent games empty state", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/play")

      assert html =~ "ds-play-recent"
      assert html =~ "Recent games"
      # anonymous users have no games
      assert html =~ "No games played yet" or html =~ "Your last bets"
    end

    # CF-05 — BUX pool "Coming soon" pill: REMOVED in the 2026-04-24 build
    # entry. The BUX vault is funded on devnet now, so the stat card was
    # reverted from the brand-color "Coming soon" pill back to an em-dash
    # placeholder when the user hasn't selected the BUX token. Test deleted
    # to match shipped behavior.

    test "BUX pool card renders an em-dash placeholder when SOL is selected", %{conn: conn} do
      # The BUX pool figure only fills in once the user clicks the BUX
      # token toggle (the `format_balance(@house_balance)` for BUX is
      # gated on `@selected_token == "BUX"`). Anonymous default state =
      # SOL, so the BUX card renders the em-dash fallback.
      {:ok, _view, html} = live(conn, ~p"/play")

      assert html =~ "BUX Pool"
      # BUX figure block falls back to the em-dash when not selected.
      assert html =~ "—"
    end

    test "CF-06 — sidebar 'Your recent games' block is absent when user has 0 games",
         %{conn: conn} do
      # Anonymous user has @recent_games = []. The sidebar block that would
      # render "No games yet" is now hidden entirely; the full "Recent games"
      # table below the fold still renders its own empty state (so users
      # don't end up with zero empty-state blocks OR two parallel ones).
      {:ok, _view, html} = live(conn, ~p"/play")

      # Sidebar heading should NOT appear; below-the-fold table heading still does.
      refute html =~ "Your recent games"
      assert html =~ "Recent games"
    end

    test "renders design system footer", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/play")

      assert html =~ "ds-footer"
      # Footer mission line — sentinel for the redesigned dark <.footer />.
      assert html =~ "Hustle hard. All in on crypto."
    end

    test "renders sidebar idle-state cards (stats + legend)", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/play")

      assert html =~ "Your stats"
      assert html =~ "Two modes"
      assert html =~ "Win One"
      assert html =~ "Win All"
    end

    test "uses rocket and poop emojis for coin display (not H/T)", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/play")

      # Helper text mentions the emojis
      assert html =~ "🚀" or html =~ "💩"
    end
  end

  describe "GET /play · authenticated user" do
    test "mounts and renders game card", %{conn: conn} do
      user = insert_user(%{slug: "cf-user-1"})
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/play")

      assert html =~ "ds-play-game"
      assert html =~ "Coin Flip"
    end

    test "renders all 9 difficulty levels", %{conn: conn} do
      user = insert_user(%{slug: "cf-user-2"})
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/play")

      assert html =~ "1.02"
      assert html =~ "1.05"
      assert html =~ "1.13"
      assert html =~ "1.32"
      assert html =~ "1.98"
      assert html =~ "3.96"
      assert html =~ "7.92"
      assert html =~ "15.84"
      assert html =~ "31.68"
    end

    test "CoinFlipSolana hook is mounted on root element", %{conn: conn} do
      user = insert_user(%{slug: "cf-user-3"})
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/play")

      assert html =~ ~s(id="coin-flip-game")
      assert html =~ ~s(phx-hook="CoinFlipSolana")
    end
  end

  describe "handler: select_difficulty" do
    test "updates difficulty and the number of prediction coins", %{conn: conn} do
      user = insert_user(%{slug: "cf-diff"})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/play")

      html = view |> element(~s([phx-click="select_difficulty"][phx-value-level="2"])) |> render_click()

      # difficulty 2 is 2 flips "Win all"
      assert html =~ "3.96"
      # Two prediction coin buttons now — check for phx-value-index="1" and "2"
      assert html =~ ~s(phx-value-index="1")
      assert html =~ ~s(phx-value-index="2")
    end
  end

  describe "handler: toggle_prediction" do
    test "cycles through nil → :heads → :tails on successive clicks", %{conn: conn} do
      user = insert_user(%{slug: "cf-pred"})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/play")

      # First click: nil → heads
      html1 = view |> element(~s([phx-click="toggle_prediction"][phx-value-index="1"])) |> render_click()
      assert html1 =~ "casino-chip-heads"

      # Second click: heads → tails
      html2 = view |> element(~s([phx-click="toggle_prediction"][phx-value-index="1"])) |> render_click()
      assert html2 =~ "casino-chip-tails"
    end
  end

  describe "handler: set_preset" do
    test "updates bet amount to preset value", %{conn: conn} do
      user = insert_user(%{slug: "cf-preset"})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/play")

      html = view |> element(~s([phx-click="set_preset"][phx-value-amount="0.25"])) |> render_click()
      assert html =~ "0.25"
    end
  end

  describe "handler: select_token" do
    test "switches selected token", %{conn: conn} do
      user = insert_user(%{slug: "cf-token"})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/play")

      # The 2026-04-24 mobile-compact pass duplicates the token toggle
      # (mobile header + desktop card), so a CSS selector returns 2
      # elements and `element/2` raises. Fire the event by name instead
      # — the handler is the same regardless of which surface clicked.
      html = render_click(view, "select_token", %{"token" => "BUX"})
      assert html =~ "BUX"
    end
  end

  describe "handler: halve_bet / double_bet" do
    test "halve_bet fires without error", %{conn: conn} do
      user = insert_user(%{slug: "cf-half"})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/play")

      # halve_bet button is rendered for both the active bet input row
      # and the disabled mobile placeholder row, so CSS-selector lookup
      # is ambiguous. Trigger the handler directly.
      html = render_click(view, "halve_bet", %{})
      assert html =~ "ds-play-game"
    end

    test "double_bet fires without error", %{conn: conn} do
      user = insert_user(%{slug: "cf-double"})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/play")

      # See halve_bet test above — same dual-render reason.
      html = render_click(view, "double_bet", %{})
      assert html =~ "ds-play-game"
    end
  end

  # ==========================================================================
  # CF-07 — Recent games list updates live from PubSub broadcasts
  # ==========================================================================

  describe "PubSub: {:new_settled_game, payload} (CF-07)" do
    test "prepends a new settled game to @recent_games", %{conn: conn} do
      user = insert_user(%{slug: "cf-pubsub-1"})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/play")

      # Payload shape matches CoinFlipGame.broadcast_game_settled/2 (see
      # lib/blockster_v2/coin_flip_game.ex).
      payload = %{
        game_id: "cf_new_game_test_1",
        vault_type: "sol",
        bet_amount: 0.05,
        difficulty: 1,
        multiplier: 1.98,
        predictions: [:heads],
        results: [:heads],
        won: true,
        payout: 0.099,
        commitment_hash: String.duplicate("a", 64),
        server_seed: String.duplicate("b", 64),
        nonce: 5,
        commitment_sig: "cs_test",
        bet_sig: "bs_test",
        settlement_sig: "ss_test"
      }

      send(view.pid, {:new_settled_game, payload})
      html = render(view)

      # game_id leaks into the fairness-modal data attribute and the sig
      # markup; either reference is enough to prove the row landed.
      assert html =~ "cf_new_game_test_1" or html =~ "ss_test"
    end
  end

  # ==========================================================================
  # CF-02 — Recovery CTA on settlement failure states
  # ==========================================================================

  describe "settlement_status :manual_review (CF-02)" do
    test "{:settlement_failed, :manual_review} flips status and keeps the LV responsive", %{conn: conn} do
      user = insert_user(%{slug: "cf-manreview"})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/play")

      # Drive the LV directly into :manual_review. In production this comes
      # from the spawned settlement task after CoinFlipGame returns
      # {:error, :manual_review} (commitment_mismatch unrecoverable).
      send(view.pid, {:settlement_failed, :manual_review})

      # No crash; the result-card UI is only visible when game_state ==
      # :result which we can't easily stage from unit tests (requires a
      # fully-placed bet + :show_final_result handler firing). So the
      # assertion here is: the handler accepted the message, the LV is
      # still alive, and the idle-state page still renders. In particular
      # reset_game remains callable — proven by a subsequent render().
      assert Process.alive?(view.pid)
      html = render(view)
      assert is_binary(html)
      assert html =~ "ds-play-game"
    end
  end
end
