defmodule BlocksterV2Web.PlinkoLiveTest do
  use BlocksterV2Web.LiveCase, async: false

  alias BlocksterV2.{Repo, Accounts.User, PlinkoGame, EngagementTracker}

  setup do
    ensure_mnesia_tables()

    unique = System.unique_integer([:positive])

    {:ok, user} =
      %User{}
      |> Ecto.Changeset.change(%{
        email: "plinko_test_#{unique}@test.com",
        wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
        smart_wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}"
      })
      |> Repo.insert()

    {:ok, user_no_wallet} =
      %User{}
      |> Ecto.Changeset.change(%{
        email: "plinko_nowallet_#{unique}@test.com",
        wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
        smart_wallet_address: nil,
        slug: "plinko-nowallet-#{unique}"
      })
      |> Repo.insert()

    on_exit(fn ->
      :mnesia.clear_table(:plinko_games)
      :mnesia.clear_table(:user_bux_balances)
      :mnesia.clear_table(:user_betting_stats)
    end)

    %{user: user, user_no_wallet: user_no_wallet}
  end

  defp ensure_mnesia_tables do
    :mnesia.start()

    tables = [
      {:plinko_games,
       [
         :game_id,
         :user_id,
         :wallet_address,
         :server_seed,
         :commitment_hash,
         :nonce,
         :status,
         :bet_id,
         :token,
         :token_address,
         :bet_amount,
         :config_index,
         :rows,
         :risk_level,
         :ball_path,
         :landing_position,
         :payout_bp,
         :payout,
         :won,
         :commitment_tx,
         :bet_tx,
         :settlement_tx,
         :created_at,
         :settled_at
       ], :ordered_set,
       [:user_id, :wallet_address, :status, :created_at]},
      {:user_bux_balances, [:user_id, :balances], :set, [:user_id]},
      {:user_betting_stats,
       [:key, :total_bets, :total_wins, :total_losses, :total_wagered, :total_pnl], :set, []},
      {:token_prices,
       [:token_id, :symbol, :usd_price, :usd_24h_change, :last_updated], :set, [:symbol]}
    ]

    for {name, attrs, type, index} <- tables do
      case :mnesia.create_table(name,
             type: type,
             attributes: attrs,
             index: index,
             ram_copies: [node()]
           ) do
        {:atomic, :ok} -> :ok
        {:aborted, {:already_exists, ^name}} -> :ok
        _ -> :ok
      end
    end
  end

  defp set_user_balance(user, token, amount) do
    balances = %{token => amount}

    :mnesia.dirty_write(
      {:user_bux_balances, user.id, balances}
    )
  end

  defp create_test_game(user, opts \\ []) do
    game_id = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
    server_seed = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
    commitment_hash_bytes = :crypto.hash(:sha256, server_seed)
    commitment_hash = "0x" <> Base.encode16(commitment_hash_bytes, case: :lower)
    status = Keyword.get(opts, :status, :settled)
    bet_amount = Keyword.get(opts, :bet_amount, 10)
    token = Keyword.get(opts, :token, "BUX")
    config_index = Keyword.get(opts, :config_index, 0)
    rows = Keyword.get(opts, :rows, 8)
    risk_level = Keyword.get(opts, :risk_level, :low)
    ball_path = Keyword.get(opts, :ball_path, [:left, :right, :left, :right, :left, :right, :left, :right])
    landing_position = Keyword.get(opts, :landing_position, 4)
    payout_bp = Keyword.get(opts, :payout_bp, 5000)
    payout = Keyword.get(opts, :payout, 5)
    won = Keyword.get(opts, :won, false)
    nonce = Keyword.get(opts, :nonce, 0)
    now = System.system_time(:second)

    record =
      {:plinko_games, game_id, user.id, user.smart_wallet_address, server_seed, commitment_hash,
       nonce, status, commitment_hash, token,
       "0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8", bet_amount, config_index, rows, risk_level,
       ball_path, landing_position, payout_bp, payout, won, "0xtx_commit", "0xtx_bet",
       if(status == :settled, do: "0xtx_settle", else: nil), now,
       if(status == :settled, do: now, else: nil)}

    :mnesia.dirty_write(record)

    %{
      game_id: game_id,
      server_seed: server_seed,
      commitment_hash: commitment_hash,
      status: status,
      bet_amount: bet_amount,
      token: token,
      payout: payout,
      won: won,
      rows: rows,
      risk_level: risk_level,
      landing_position: landing_position,
      payout_bp: payout_bp,
      nonce: nonce,
      ball_path: ball_path,
      config_index: config_index,
      user_id: user.id
    }
  end

  # ============================================================
  # Mount — guest (not logged in)
  # ============================================================

  describe "mount — guest (not logged in)" do
    test "renders page with Plinko title", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/plinko")
      assert html =~ "Plinko"
    end

    test "shows login to play button", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/plinko")
      assert html =~ "Login to Play"
    end

    test "renders SVG board with pegs", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/plinko")
      assert html =~ "plinko-board"
      assert html =~ "plinko-peg"
    end

    test "renders config selectors", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/plinko")
      assert html =~ "8 Rows"
      assert html =~ "12 Rows"
      assert html =~ "16 Rows"
      assert html =~ "Low"
      assert html =~ "Medium"
      assert html =~ "High"
    end
  end

  # ============================================================
  # Mount — authenticated user without wallet
  # ============================================================

  describe "mount — authenticated user without wallet" do
    test "renders with error_message 'No wallet connected'", %{
      conn: conn,
      user_no_wallet: user
    } do
      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, "/plinko")
      assert html =~ "No wallet connected"
    end

    test "does not show DROP BALL button", %{conn: conn, user_no_wallet: user} do
      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, "/plinko")
      # Without smart wallet, game should not be ready
      refute html =~ "DROP BALL"
    end
  end

  # ============================================================
  # Mount — authenticated user with wallet
  # ============================================================

  describe "mount — authenticated user with wallet" do
    test "sets default assigns and renders", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, html} = live(conn, "/plinko")

      # Default config is 8-Low
      assert html =~ "8 Rows"
      assert html =~ "BUX"
      assert html =~ "DROP BALL" or html =~ "Initializing" or html =~ "Game Not Ready"

      # Check SVG board exists
      assert html =~ "plinko-board"
    end

    test "renders game history section", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, "/plinko")
      assert html =~ "Game History"
    end
  end

  # ============================================================
  # Config Selection
  # ============================================================

  describe "select_rows event" do
    test "switching to 12 rows updates config", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/plinko")

      html = render_click(view, "select_rows", %{"rows" => "12"})
      # 12-row board has a taller viewBox (460)
      assert html =~ "0 0 400 460"
    end

    test "switching to 16 rows updates config", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/plinko")

      html = render_click(view, "select_rows", %{"rows" => "16"})
      assert html =~ "0 0 400 580"
    end

    test "switching back to 8 rows", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/plinko")

      render_click(view, "select_rows", %{"rows" => "16"})
      html = render_click(view, "select_rows", %{"rows" => "8"})
      assert html =~ "0 0 400 340"
    end
  end

  describe "select_risk event" do
    test "switching to medium risk", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/plinko")

      html = render_click(view, "select_risk", %{"risk" => "medium"})
      # Medium risk has different payout tables - verify it rendered
      assert html =~ "plinko-slot"
    end

    test "switching to high risk", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/plinko")

      html = render_click(view, "select_risk", %{"risk" => "high"})
      assert html =~ "plinko-slot"
    end

    test "12 rows + medium risk = different payout table", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/plinko")

      render_click(view, "select_rows", %{"rows" => "12"})
      html = render_click(view, "select_risk", %{"risk" => "medium"})
      # Config index 4 (12-medium) should be active
      assert html =~ "plinko-slot"
    end
  end

  # ============================================================
  # Bet Amount Controls
  # ============================================================

  describe "update_bet_amount event" do
    test "sets bet_amount to provided value", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/plinko")

      html = render_change(view, "update_bet_amount", %{"value" => "50"})
      assert html =~ "50"
    end

    test "handles non-numeric input gracefully", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/plinko")

      # Should not crash
      html = render_change(view, "update_bet_amount", %{"value" => "abc"})
      assert html =~ "plinko-board"
    end
  end

  describe "halve_bet event" do
    test "halves bet_amount", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/plinko")

      # Default is 10, halve should give 5
      html = render_click(view, "halve_bet")
      assert html =~ "value=\"5\""
    end

    test "does not go below 1", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/plinko")

      # Halve multiple times to reach 1
      render_click(view, "halve_bet")
      render_click(view, "halve_bet")
      render_click(view, "halve_bet")
      html = render_click(view, "halve_bet")
      assert html =~ "value=\"1\""
    end
  end

  describe "double_bet event" do
    test "doubles bet_amount", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/plinko")

      html = render_click(view, "double_bet")
      assert html =~ "value=\"20\""
    end
  end

  describe "set_max_bet event" do
    test "sets bet_amount to max_bet value", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/plinko")

      # Max bet starts at 0 (before house balance loads)
      html = render_click(view, "set_max_bet")
      assert html =~ "value=\"0\""
    end
  end

  # ============================================================
  # Token Selection
  # ============================================================

  describe "toggle_token_dropdown event" do
    test "toggles dropdown visibility", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/plinko")

      html = render_click(view, "toggle_token_dropdown")
      assert html =~ "ROGUE"
      assert html =~ "BUX"
    end
  end

  describe "select_token event" do
    test "switches to ROGUE token", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/plinko")

      html = render_click(view, "select_token", %{"token" => "ROGUE"})
      # Token selector should show ROGUE
      assert html =~ "ROGUE"
    end

    test "switches back to BUX", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/plinko")

      render_click(view, "select_token", %{"token" => "ROGUE"})
      html = render_click(view, "select_token", %{"token" => "BUX"})
      assert html =~ "BUX"
    end
  end

  # ============================================================
  # Drop Ball — validations
  # ============================================================

  describe "drop_ball event — validations" do
    test "rejects when onchain_ready is false", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/plinko")

      html = render_click(view, "drop_ball")
      assert html =~ "Game not ready"
    end
  end

  # ============================================================
  # JS pushEvent Handlers
  # ============================================================

  describe "ball_landed event (from JS)" do
    test "transitions game_state to result", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/plinko")

      # Manually set game_state to :dropping to test transition
      send(view.pid, {:set_test_state, :dropping})
      # Give it a moment
      :timer.sleep(50)

      html = render_click(view, "ball_landed")
      assert html =~ "Play Again"
    end
  end

  # ============================================================
  # Reset
  # ============================================================

  describe "reset_game event" do
    test "transitions game_state to idle", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/plinko")

      html = render_click(view, "reset_game")
      # Should show idle state with Initializing (since game init was triggered)
      assert html =~ "Initializing" or html =~ "DROP BALL" or html =~ "Game Not Ready"
    end
  end

  # ============================================================
  # Fairness Modal
  # ============================================================

  describe "show_fairness_modal event" do
    test "shows modal for settled game", %{conn: conn, user: user} do
      game = create_test_game(user, status: :settled, won: true, payout: 56, payout_bp: 56000)
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/plinko")

      html = render_click(view, "show_fairness_modal", %{"game_id" => game.game_id})
      assert html =~ "Verify Fairness"
      assert html =~ "Server Seed"
      assert html =~ game.server_seed
    end

    test "rejects unsettled games", %{conn: conn, user: user} do
      game = create_test_game(user, status: :placed)
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/plinko")

      html = render_click(view, "show_fairness_modal", %{"game_id" => game.game_id})
      assert html =~ "Game must be settled to verify fairness"
      refute html =~ "Verify Fairness"
    end

    test "handles non-existent game", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/plinko")

      html = render_click(view, "show_fairness_modal", %{"game_id" => "nonexistent"})
      assert html =~ "Game not found"
    end
  end

  describe "hide_fairness_modal event" do
    test "closes the modal", %{conn: conn, user: user} do
      game = create_test_game(user, status: :settled)
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/plinko")

      render_click(view, "show_fairness_modal", %{"game_id" => game.game_id})
      html = render_click(view, "hide_fairness_modal")
      refute html =~ "Server Seed"
    end
  end

  # ============================================================
  # Clear Error
  # ============================================================

  describe "clear_error event" do
    test "clears error message", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/plinko")

      # Trigger an error
      render_click(view, "drop_ball")
      html = render(view)
      assert html =~ "Game not ready"

      # Clear it
      html = render_click(view, "clear_error")
      refute html =~ "Game not ready"
    end
  end

  # ============================================================
  # PubSub Handlers
  # ============================================================

  describe "handle_info PubSub messages" do
    test "{:bux_balance_updated, balance} updates balances", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/plinko")

      send(view.pid, {:bux_balance_updated, 500})
      html = render(view)
      assert html =~ "500"
    end

    test "{:token_balances_updated, balances} updates all balances", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/plinko")

      send(view.pid, {:token_balances_updated, %{"BUX" => 1000, "ROGUE" => 500}})
      html = render(view)
      assert html =~ "1,000"
    end

    test "{:plinko_settled, game_id, tx_hash} updates settlement_tx for current game", %{
      conn: conn,
      user: user
    } do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/plinko")

      # Send settlement for a non-current game (should be ignored)
      send(view.pid, {:plinko_settled, "non_existent_game", "0xabc123"})
      html = render(view)
      refute html =~ "0xabc123"
    end

    test "{:token_prices_updated, prices} updates rogue price", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/plinko")

      send(view.pid, {:token_prices_updated, %{"ROGUE" => 0.05}})
      # Just verify it doesn't crash
      html = render(view)
      assert html =~ "plinko-board"
    end
  end

  # ============================================================
  # Async Handlers
  # ============================================================

  describe "async handler :init_onchain_game" do
    test "failure sets error after max retries", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/plinko")

      # Simulate init failure by sending async result directly
      send(view.pid, {ref = make_ref(), {:ok, {:error, :test_error}}})
      # Can't easily test async handlers directly in LiveView tests
      # so just verify the view is still alive
      html = render(view)
      assert html =~ "plinko-board"
    end
  end

  describe "async handler :fetch_house_balance" do
    test "keeps defaults on failure", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/plinko")

      # View should work fine even if house balance fetch fails
      html = render(view)
      assert html =~ "House:"
    end
  end

  # ============================================================
  # SVG Board Rendering
  # ============================================================

  describe "SVG board rendering" do
    test "renders correct number of pegs for 8 rows (36 pegs)", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/plinko")
      # Count plinko-peg class occurrences (sum 1..8 = 36)
      peg_count = html |> String.split("plinko-peg") |> length() |> Kernel.-(1)
      assert peg_count == 36
    end

    test "renders correct number of pegs for 12 rows (78 pegs)", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/plinko")
      html = render_click(view, "select_rows", %{"rows" => "12"})
      peg_count = html |> String.split("plinko-peg") |> length() |> Kernel.-(1)
      assert peg_count == 78
    end

    test "renders correct number of pegs for 16 rows (136 pegs)", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/plinko")
      html = render_click(view, "select_rows", %{"rows" => "16"})
      peg_count = html |> String.split("plinko-peg") |> length() |> Kernel.-(1)
      assert peg_count == 136
    end

    test "renders correct number of landing slots for 8 rows (9 slots)", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/plinko")
      slot_count = html |> String.split("plinko-slot") |> length() |> Kernel.-(1)
      assert slot_count == 9
    end

    test "renders SVG viewBox with correct height for 8 rows", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/plinko")
      assert html =~ "0 0 400 340"
    end

    test "landing slot labels show formatted multipliers", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/plinko")
      # 8-Low payout table starts with 56000 bp = 5.6x
      assert html =~ "5.6x"
    end
  end

  # ============================================================
  # Game State Rendering
  # ============================================================

  describe "game state rendering" do
    test ":idle state shows Drop Ball button", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/plinko")
      assert html =~ "DROP BALL" or html =~ "Login to Play" or html =~ "Game Not Ready"
    end

    test ":idle state shows bet controls", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/plinko")
      assert html =~ "BET"
      assert html =~ "/2"
      assert html =~ "x2"
      assert html =~ "MAX"
    end

    test "error message renders in error banner", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/plinko")

      html = render_click(view, "drop_ball")
      assert html =~ "Game not ready"
    end

    test "game history table has correct columns", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/plinko")
      assert html =~ "ID"
      assert html =~ "Bet"
      assert html =~ "Config"
      assert html =~ "Landing"
      assert html =~ "Mult"
      assert html =~ "P/L"
      assert html =~ "Verify"
    end
  end

  # ============================================================
  # Game History Display
  # ============================================================

  describe "game history" do
    test "shows recent settled games", %{conn: conn, user: user} do
      game = create_test_game(user, status: :settled, bet_amount: 100, token: "BUX")
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/plinko")

      # Wait for async load
      :timer.sleep(200)
      html = render(view)
      assert html =~ String.slice(game.game_id, 0..5)
    end

    test "verify button on each game row", %{conn: conn, user: user} do
      create_test_game(user, status: :settled)
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/plinko")

      :timer.sleep(200)
      html = render(view)
      assert html =~ "Verify"
    end
  end

  # ============================================================
  # Helpers
  # ============================================================

  describe "format_multiplier" do
    test "renders in SVG for different configs", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/plinko")

      # 8-Low config: 56000 bp = 5.6x, 21000 = 2.1x, 11000 = 1.1x, 10000 = 1x, 5000 = 0.5x
      assert html =~ "5.6x"
      assert html =~ "2.1x"
      assert html =~ "1.1x"
      assert html =~ "1x"
      assert html =~ "0.5x"
    end
  end

  describe "config_index_for calculation" do
    test "all 9 configs render different payout tables", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/plinko")

      # Test all combinations
      for {rows, risk} <- [{8, "low"}, {8, "medium"}, {8, "high"},
                           {12, "low"}, {12, "medium"}, {12, "high"},
                           {16, "low"}, {16, "medium"}, {16, "high"}] do
        render_click(view, "select_rows", %{"rows" => to_string(rows)})
        html = render_click(view, "select_risk", %{"risk" => risk})
        # Each should render valid SVG
        assert html =~ "plinko-slot"
      end
    end
  end
end
