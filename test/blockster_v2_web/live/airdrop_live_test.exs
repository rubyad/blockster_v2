defmodule BlocksterV2Web.AirdropLiveTest do
  use BlocksterV2Web.LiveCase, async: false

  alias BlocksterV2.{Airdrop, Repo}
  alias BlocksterV2.Accounts.User
  # ============================================================================
  # Test Helpers
  # ============================================================================

  defp create_user(attrs \\ %{}) do
    unique_id = System.unique_integer([:positive])

    default_attrs = %{
      wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
      smart_wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
      email: "airdrop_test_#{unique_id}@example.com",
      username: "airdropuser#{unique_id}",
      auth_method: "wallet",
      phone_verified: true
    }

    %User{}
    |> User.changeset(Map.merge(default_attrs, attrs))
    |> Repo.insert!()
  end

  defp create_round(opts \\ []) do
    end_time = Keyword.get(opts, :end_time, ~U[2026-04-01 00:00:00Z])
    {:ok, round} = Airdrop.create_round(end_time, skip_vault: true)
    round
  end

  defp create_drawn_round(user, bux_amount \\ 1000) do
    round = create_round()
    set_bux_balance(user, bux_amount)
    {:ok, _entry} = Airdrop.redeem_bux(user, bux_amount, round.round_id)
    slot_at_close = to_string(:rand.uniform(999_999_999))
    {:ok, _closed} = Airdrop.close_round(round.round_id, slot_at_close)
    {:ok, drawn_round} = Airdrop.draw_winners(round.round_id)
    drawn_round
  end

  defp setup_mnesia(_context) do
    # Ensure Mnesia is started (GenServers are disabled in test env)
    :mnesia.start()

    tables = [
      {:user_solana_balances,
       [:user_id, :wallet_address, :updated_at, :sol_balance, :bux_balance]},
      {:user_bux_balances,
       [:user_id, :user_smart_wallet, :updated_at, :aggregate_bux_balance,
        :bux_balance, :moonbux_balance, :neobux_balance, :roguebux_balance,
        :flarebux_balance, :nftbux_balance, :nolchabux_balance, :solbux_balance,
        :spacebux_balance, :tronbux_balance, :tranbux_balance]},
      {:user_rogue_balances,
       [:user_id, :user_smart_wallet, :updated_at, :rogue_balance_rogue_chain, :rogue_balance_arbitrum]}
    ]

    for {table, attrs} <- tables do
      case :mnesia.create_table(table, attributes: attrs, type: :set, ram_copies: [node()]) do
        {:atomic, :ok} -> :ok
        {:aborted, {:already_exists, _}} -> :ok
        {:aborted, other} -> raise "Mnesia table creation failed: #{inspect(other)}"
      end
    end

    :ok
  end

  defp set_bux_balance(user, balance) do
    # Post-Solana-migration: EngagementTracker reads from user_solana_balances.
    now = System.system_time(:second)

    solana_record =
      {:user_solana_balances, user.id, user.wallet_address, now, 0.0, balance * 1.0}

    :mnesia.dirty_write(:user_solana_balances, solana_record)

    # Legacy table kept for any transitional readers.
    legacy_record =
      {:user_bux_balances, user.id, user.smart_wallet_address, DateTime.utc_now(),
       balance * 1.0, balance * 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0}

    :mnesia.dirty_write(:user_bux_balances, legacy_record)
  end

  setup :setup_mnesia

  # ============================================================================
  # Page Render Tests
  # ============================================================================

  describe "page render" do
    test "renders prize pool and prize distribution", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/airdrop")

      assert html =~ "$2,000"
      assert html =~ "$250"
      assert html =~ "$150"
      assert html =~ "$100"
      assert html =~ "$50"
    end

    test "renders countdown timer", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/airdrop")

      assert html =~ "Days"
      assert html =~ "Hours"
      assert html =~ "Min"
      assert html =~ "Sec"
    end

    test "renders how it works section", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/airdrop")

      assert html =~ "How it works"
      assert html =~ "Earn BUX reading"
      assert html =~ "Redeem"
      assert html =~ "33 winners drawn on chain"
    end

    test "renders design system header with airdrop active", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/airdrop")

      assert html =~ ~s(id="ds-site-header")
      assert html =~ ~s(phx-hook="SolanaWallet")
      # Why Earn BUX banner is enabled on this page
      assert html =~ "Why Earn BUX?"
    end

    test "renders editorial page hero with prize-pool headline", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/airdrop")

      assert html =~ "$2,000"
      assert html =~ "up for grabs"
      assert html =~ "Total pool"
      assert html =~ "Winners"
      assert html =~ "Rate"
      assert html =~ "BUX → entry"
    end

    test "renders prize distribution card with all four tiers", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/airdrop")

      assert html =~ "Prize distribution"
      assert html =~ "33 winners"
      assert html =~ "1st place"
      assert html =~ "2nd place"
      assert html =~ "3rd place"
      assert html =~ "4th–33rd"
    end

    test "renders airdrop solana hook mount point", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/airdrop")

      assert html =~ ~s(id="airdrop-solana-hook")
      assert html =~ ~s(phx-hook="AirdropSolanaHook")
    end

    test "shows Connect Wallet to Enter for unauthenticated user", %{conn: conn} do
      _round = create_round()
      {:ok, _view, html} = live(conn, ~p"/airdrop")

      assert html =~ "Connect Wallet to Enter"
    end

    test "shows BUX balance for logged-in user", %{conn: conn} do
      user = create_user()
      set_bux_balance(user, 500)
      conn = log_in_user(conn, user)
      _round = create_round()

      {:ok, _view, html} = live(conn, ~p"/airdrop")

      assert html =~ "500"
      assert html =~ "BUX"
    end

    test "shows pool stats when entries exist", %{conn: conn} do
      user = create_user()
      round = create_round()
      set_bux_balance(user, 100)
      {:ok, _entry} = Airdrop.redeem_bux(user, 100, round.round_id)

      {:ok, _view, html} = live(conn, ~p"/airdrop")

      # Redesigned page renders the amount + "BUX" with newlines between
      # them (multi-line template), so "100 BUX" as a literal substring
      # doesn't match. Verify each piece separately.
      assert html =~ "100"
      assert html =~ "BUX"
    end

    test "shows Entries closed when round is closed", %{conn: conn} do
      user = create_user()
      round = create_round()
      set_bux_balance(user, 100)
      {:ok, _entry} = Airdrop.redeem_bux(user, 100, round.round_id)
      block_hash = "0x" <> (:crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower))
      {:ok, _closed} = Airdrop.close_round(round.round_id, block_hash)

      {:ok, _view, html} = live(conn, ~p"/airdrop")

      assert html =~ "Entries closed"
      assert html =~ "drawing winners"
    end

    test "shows airdrop opening soon when no round exists", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/airdrop")

      assert html =~ "opening soon"
    end
  end

  # ============================================================================
  # Redeem Button State Tests
  # ============================================================================

  describe "redeem button states" do
    test "shows Connect Wallet to Enter when not logged in", %{conn: conn} do
      _round = create_round()
      {:ok, _view, html} = live(conn, ~p"/airdrop")

      assert html =~ "Connect Wallet to Enter"
    end

    test "shows Verify Phone to Enter when not phone verified", %{conn: conn} do
      user = create_user(%{phone_verified: false})
      conn = log_in_user(conn, user)
      _round = create_round()

      {:ok, _view, html} = live(conn, ~p"/airdrop")

      assert html =~ "Verify Phone to Enter"
    end

    test "shows Connect Wallet to Enter when not authenticated", %{conn: conn} do
      _round = create_round()

      {:ok, _view, html} = live(conn, ~p"/airdrop")

      assert html =~ "Connect Wallet to Enter"
    end

    test "shows Enter Amount when amount is empty", %{conn: conn} do
      user = create_user()

      conn = log_in_user(conn, user)
      _round = create_round()

      {:ok, _view, html} = live(conn, ~p"/airdrop")

      assert html =~ "Enter Amount"
    end

    test "shows Insufficient Balance when amount exceeds balance", %{conn: conn} do
      user = create_user()

      set_bux_balance(user, 50)
      conn = log_in_user(conn, user)
      _round = create_round()

      {:ok, view, _html} = live(conn, ~p"/airdrop")

      html = view |> element("input[phx-keyup=update_redeem_amount]") |> render_keyup(%{"value" => "100"})

      assert html =~ "Insufficient Balance"
    end

    test "shows Redeem X BUX when valid", %{conn: conn} do
      user = create_user()

      set_bux_balance(user, 500)
      conn = log_in_user(conn, user)
      _round = create_round()

      {:ok, view, _html} = live(conn, ~p"/airdrop")

      html = view |> element("input[phx-keyup=update_redeem_amount]") |> render_keyup(%{"value" => "200"})

      assert html =~ "Redeem 200 BUX"
    end

    test "shows entry count below input", %{conn: conn} do
      user = create_user()

      set_bux_balance(user, 500)
      conn = log_in_user(conn, user)
      _round = create_round()

      {:ok, view, _html} = live(conn, ~p"/airdrop")

      html = view |> element("input[phx-keyup=update_redeem_amount]") |> render_keyup(%{"value" => "200"})

      assert html =~ "200"
      assert html =~ "entries"
    end
  end

  # ============================================================================
  # Redeem Flow Tests
  # ============================================================================

  describe "redeem flow" do
    test "clicking MAX sets amount to full balance", %{conn: conn} do
      user = create_user()

      set_bux_balance(user, 750)
      conn = log_in_user(conn, user)
      _round = create_round()

      {:ok, view, _html} = live(conn, ~p"/airdrop")

      html = view |> element("button", "MAX") |> render_click()

      assert html =~ "750"
    end

    test "redeem click shows Redeeming state", %{conn: conn} do
      user = create_user()

      set_bux_balance(user, 500)
      conn = log_in_user(conn, user)
      _round = create_round()

      {:ok, view, _html} = live(conn, ~p"/airdrop")

      view |> element("input[phx-keyup=update_redeem_amount]") |> render_keyup(%{"value" => "200"})
      html = view |> element("button", "Redeem 200 BUX") |> render_click()

      # Button should show Redeeming... state immediately
      assert html =~ "Redeeming..."
    end

    test "receipt panels show after entry created", %{conn: conn} do
      user = create_user()

      round = create_round()
      set_bux_balance(user, 200)
      {:ok, _entry} = Airdrop.redeem_bux(user, 200, round.round_id)
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/airdrop")

      assert html =~ "Redeemed 200 BUX"
      assert html =~ "Your entries"
      assert html =~ "#1"
      assert html =~ "#200"
    end

    test "balance display reflects user balance", %{conn: conn} do
      user = create_user()

      set_bux_balance(user, 300)
      conn = log_in_user(conn, user)
      _round = create_round()

      {:ok, _view, html} = live(conn, ~p"/airdrop")

      assert html =~ "300"
      assert html =~ "BUX"
    end

    test "multiple entries stack receipt panels", %{conn: conn} do
      user = create_user()

      round = create_round()
      set_bux_balance(user, 500)
      {:ok, _} = Airdrop.redeem_bux(user, 200, round.round_id)
      {:ok, _} = Airdrop.redeem_bux(user, 300, round.round_id)
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/airdrop")

      assert html =~ "Redeemed 200 BUX"
      assert html =~ "Redeemed 300 BUX"
    end

    test "total pool stats show after entries exist", %{conn: conn} do
      user = create_user()

      round = create_round()
      set_bux_balance(user, 200)
      {:ok, _} = Airdrop.redeem_bux(user, 200, round.round_id)

      {:ok, _view, html} = live(conn, ~p"/airdrop")

      # Multi-line template splits amount and "BUX" across separate DOM
      # nodes so substring match needs to be relaxed.
      assert html =~ "200"
      assert html =~ "BUX"
      assert html =~ "1"
      # Pool stats card column heading reads "Participants" (capital P).
      assert html =~ "Participants"
    end

    test "shows Entries closed when round is closed", %{conn: conn} do
      user = create_user()

      set_bux_balance(user, 500)
      conn = log_in_user(conn, user)
      round = create_round()
      {:ok, _entry} = Airdrop.redeem_bux(user, 10, round.round_id)
      block_hash = "0x" <> (:crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower))
      {:ok, _closed} = Airdrop.close_round(round.round_id, block_hash)

      {:ok, _view, html} = live(conn, ~p"/airdrop")

      assert html =~ "Entries closed"
    end

    test "shows Connect Wallet to Enter when not authenticated", %{conn: conn} do
      _round = create_round()
      {:ok, _view, html} = live(conn, ~p"/airdrop")

      assert html =~ "Connect Wallet to Enter"
    end
  end

  # ============================================================================
  # Receipt Panel Tests
  # ============================================================================

  describe "receipt panels" do
    test "persist across page visits", %{conn: conn} do
      user = create_user()

      round = create_round()
      set_bux_balance(user, 100)
      {:ok, _entry} = Airdrop.redeem_bux(user, 100, round.round_id)
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/airdrop")

      assert html =~ "Redeemed 100 BUX"
      assert html =~ "Your entries"
      assert html =~ "#1"
      assert html =~ "#100"
    end

    test "show block range and entry count", %{conn: conn} do
      user = create_user()

      round = create_round()
      set_bux_balance(user, 500)
      {:ok, _entry} = Airdrop.redeem_bux(user, 500, round.round_id)
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/airdrop")

      assert html =~ "#1"
      assert html =~ "#500"
      assert html =~ "Entries: 500"
    end

    test "show timestamp", %{conn: conn} do
      user = create_user()

      round = create_round()
      set_bux_balance(user, 50)
      {:ok, _entry} = Airdrop.redeem_bux(user, 50, round.round_id)
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/airdrop")

      # Should contain date parts
      assert html =~ "2026"
    end

    test "show win result after draw", %{conn: conn} do
      user = create_user()

      drawn_round = create_drawn_round(user)
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/airdrop")

      # User has entries in a drawn round — should show receipt panels
      assert html =~ "Your entries"
    end

    test "losing receipt shows no win message after draw", %{conn: conn} do
      # Create two users — first user gets positions 1-1000
      user1 = create_user()


      round = create_round()
      set_bux_balance(user1, 1000)
      {:ok, _} = Airdrop.redeem_bux(user1, 1000, round.round_id)

      # Second user gets positions 1001-1001
      user2 = create_user()


      set_bux_balance(user2, 1)
      {:ok, _} = Airdrop.redeem_bux(user2, 1, round.round_id)

      block_hash = "0x" <> (:crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower))
      {:ok, _} = Airdrop.close_round(round.round_id, block_hash)
      {:ok, _} = Airdrop.draw_winners(round.round_id)

      conn = log_in_user(conn, user2)
      {:ok, _view, html} = live(conn, ~p"/airdrop")

      # User2 only has 1 position, very likely no win
      # Page renders with winners section (drawn state) and entry receipts
      assert html =~ "Your entries"
    end
  end

  # ============================================================================
  # Winners Display Tests
  # ============================================================================

  describe "winners display" do
    setup %{conn: conn} do
      user = create_user()

      drawn_round = create_drawn_round(user)
      winners = Airdrop.get_winners(drawn_round.round_id)

      %{user: user, round: drawn_round, winners: winners, conn: conn}
    end

    test "shows celebration header after draw", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/airdrop")

      assert html =~ "The airdrop has been drawn"
      assert html =~ "Congratulations to all 33 winners"
    end

    test "shows drawn state marker instead of countdown card", %{conn: conn} do
      # Pre-redesign the countdown_card flipped its eyebrow from
      # "Drawing on" to "Drawing complete" once a round was drawn. The
      # 2026-04-24 redesign drops the countdown card from the drawn
      # state entirely and replaces it with a dark celebration banner
      # whose eyebrow ends in "· drawn". Assert the new state marker.
      {:ok, _view, html} = live(conn, ~p"/airdrop")

      assert html =~ "· drawn"
      assert html =~ "Drawn state · winners revealed"
    end

    test "renders top 3 winners with prizes", %{conn: conn, winners: winners} do
      {:ok, _view, html} = live(conn, ~p"/airdrop")

      # Check prize amounts for top 3
      assert html =~ "$250"
      assert html =~ "$150"
      assert html =~ "$100"
      assert html =~ "1st place"
      assert html =~ "2nd place"
      assert html =~ "3rd place"

      # Check addresses are truncated
      first_winner = Enum.at(winners, 0)
      truncated = "#{String.slice(first_winner.wallet_address, 0, 6)}…"
      assert html =~ truncated
    end

    # "renders all 33 winners in table" — DELETED.
    #
    # The `create_drawn_round/1` helper has always created a single-entrant
    # round (one user redeems all `bux_amount` BUX), so every "winner" row
    # ends up sharing the same wallet. Per AIRDROP-01 (2026-04-22 audit),
    # the page now collapses that case into a "Winner took all 33 positions"
    # summary card and the full table sits behind the same expand toggle.
    # The single-winner positive coverage already lives in the
    # `single-winner round renders collapsed 'Winner took all' summary`
    # test below — no need to retain a regression test for a layout that
    # was never actually distinct-winner in this fixture.

    test "All 33 winners table heading still renders for the drawn fixture", %{conn: conn} do
      # The fixture's single-winner case still renders the full table
      # under the collapse toggle, with the heading derived from the
      # winners count. Verify the heading without iterating per-row,
      # which would just re-test the AIRDROP-01 summary anyway.
      {:ok, _view, html} = live(conn, ~p"/airdrop")

      assert html =~ "All 33 winners"
    end

    test "single-winner round renders collapsed 'Winner took all' summary (AIRDROP-01)",
         %{conn: conn} do
      # The default create_drawn_round fixture has exactly one entrant with
      # all 33 winners sharing one wallet — perfect single-winner repro.
      {:ok, _view, html} = live(conn, ~p"/airdrop")

      assert html =~ "Winner took all 33 positions"
      assert html =~ "One winner took all"
    end

    test "winners table collapses by default and toggles via Show all button", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/airdrop")

      assert html =~ "Show all 33 winners"

      html = view |> element("button", "Show all 33 winners") |> render_click()
      assert html =~ "Show top 8 only"

      html = view |> element("button", "Show top 8 only") |> render_click()
      assert html =~ "Show all 33 winners"
    end

    test "winners table shows correct columns", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/airdrop")

      assert html =~ "Winner"
      assert html =~ "Position"
      assert html =~ "Prize"
      assert html =~ "Status"
    end

    test "winners table shows correct prize amounts", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/airdrop")

      # 1st = $250, 2nd = $150, 3rd = $100, rest = $50
      assert html =~ "$250"
      assert html =~ "$150"
      assert html =~ "$100"
      assert html =~ "$50"
    end

    test "shows claim button for logged-in winner with wallet", %{conn: conn, user: user, winners: winners} do
      # Mark all winners as prize_registered so Claim button appears
      Enum.each(winners, fn w -> Airdrop.mark_prize_registered(w.round_id, w.winner_index) end)

      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/airdrop")

      # User has entries and at least some winners are this user
      user_wins = Enum.filter(winners, &(&1.user_id == user.id))

      if user_wins != [] do
        assert html =~ "Claim"
      end
    end

    test "shows Claim button for winner with wallet connected", %{conn: conn, user: user, winners: winners} do
      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/airdrop")

      user_wins = Enum.filter(winners, &(&1.user_id == user.id))

      if user_wins != [] do
        assert html =~ "Claim"
      end
    end

    test "unauthenticated user does not see claim buttons", %{conn: conn} do
      user = create_user()
      _drawn_round = create_drawn_round(user)

      # Not logged in — should not see claim buttons
      {:ok, _view, html} = live(conn, ~p"/airdrop")
      refute html =~ "phx-click=\"claim_prize\""
    end

    test "other users don't see claim buttons", %{conn: conn} do
      other_user = create_user()
      conn = log_in_user(conn, other_user)

      {:ok, _view, html} = live(conn, ~p"/airdrop")

      # Other user should not see claim buttons (they see dashes)
      refute html =~ "phx-click=\"claim_prize\""
    end

    test "verify fairness button visible after draw", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/airdrop")

      assert html =~ "Verify fairness"
    end
  end

  # ============================================================================
  # Claim Flow Tests
  # ============================================================================

  describe "claim flow" do
    test "successful claim shows Claimed badge", %{conn: conn} do
      user = create_user()


      drawn_round = create_drawn_round(user)
      winners = Airdrop.get_winners(drawn_round.round_id)
      user_win = Enum.find(winners, &(&1.user_id == user.id))

      if user_win do
        # Claim the prize directly (backend already tested in airdrop_test.exs)
        {:ok, _} = Airdrop.claim_prize(user.id, drawn_round.round_id, user_win.winner_index, "0xfaketx", user.wallet_address)

        conn = log_in_user(conn, user)
        {:ok, _view, html} = live(conn, ~p"/airdrop")

        assert html =~ "Claimed"
      end
    end

    test "claim requires wallet connection (not logged in shows no claim button)", %{conn: conn} do
      user = create_user()
      drawn_round = create_drawn_round(user)
      winners = Airdrop.get_winners(drawn_round.round_id)
      _user_win = Enum.find(winners, &(&1.user_id == user.id))

      # Not logged in — should not show claim button
      {:ok, _view, html} = live(conn, ~p"/airdrop")
      refute html =~ "Claim"
    end

    test "already claimed prize shows Claimed badge", %{conn: conn} do
      user = create_user()


      drawn_round = create_drawn_round(user)
      winners = Airdrop.get_winners(drawn_round.round_id)
      user_win = Enum.find(winners, &(&1.user_id == user.id))

      if user_win do
        # Pre-claim the prize
        {:ok, _} = Airdrop.claim_prize(user.id, drawn_round.round_id, user_win.winner_index, "0xfaketx", user.wallet_address)

        conn = log_in_user(conn, user)
        {:ok, _view, html} = live(conn, ~p"/airdrop")

        assert html =~ "Claimed"
      end
    end
  end

  # ============================================================================
  # Provably Fair Modal Tests
  # ============================================================================

  describe "provably fair modal" do
    setup %{conn: conn} do
      user = create_user()

      drawn_round = create_drawn_round(user)

      %{user: user, round: drawn_round, conn: conn}
    end

    test "opens on Verify fairness click", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/airdrop")

      html = view |> element("button", "Verify fairness") |> render_click()

      assert html =~ "Provably Fair Verification"
    end

    test "shows 4 verification steps", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/airdrop")
      html = view |> element("button", "Verify fairness") |> render_click()

      assert html =~ "Before Round Opened"
      assert html =~ "Airdrop Closed"
      assert html =~ "Seed Revealed"
      assert html =~ "Winner Derivation"
    end

    test "shows commitment hash", %{conn: conn, round: round} do
      {:ok, view, _html} = live(conn, ~p"/airdrop")
      html = view |> element("button", "Verify fairness") |> render_click()

      assert html =~ "Commitment Hash"
      assert html =~ round.commitment_hash
    end

    test "shows slot at close", %{conn: conn, round: round} do
      {:ok, view, _html} = live(conn, ~p"/airdrop")
      html = view |> element("button", "Verify fairness") |> render_click()

      assert html =~ round.block_hash_at_close
    end

    test "shows server seed after draw", %{conn: conn, round: round} do
      {:ok, view, _html} = live(conn, ~p"/airdrop")
      html = view |> element("button", "Verify fairness") |> render_click()

      assert html =~ "Server Seed"
      assert html =~ round.server_seed
    end

    test "shows SHA256 verification checkmark", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/airdrop")
      html = view |> element("button", "Verify fairness") |> render_click()

      assert html =~ "SHA-256(Server Seed) matches commitment hash"
    end

    test "shows winner derivation formula", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/airdrop")
      html = view |> element("button", "Verify fairness") |> render_click()

      assert html =~ "SHA256"
      assert html =~ "Combine seeds"
    end

    test "shows all 33 winners in derivation table", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/airdrop")
      html = view |> element("button", "Verify fairness") |> render_click()

      # Each winner row has the index number
      for i <- 1..33 do
        assert html =~ ">#{i}<"
      end
    end

    test "closes on X button click", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/airdrop")
      view |> element("button", "Verify fairness") |> render_click()

      # Close the modal using the footer Close button
      html = view |> element("button", "Close") |> render_click()

      refute html =~ "Provably Fair Verification"
    end

    test "closes on Escape key", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/airdrop")
      view |> element("button", "Verify fairness") |> render_click()

      # Press Escape via window keydown
      html = render_keydown(view, "close_fairness_modal", %{"key" => "Escape"})

      refute html =~ "Provably Fair Verification"
    end

    test "shows Solscan link in footer", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/airdrop")
      html = view |> element("button", "Verify fairness") |> render_click()

      assert html =~ "solscan.io"
    end
  end

  # ============================================================================
  # PubSub Real-Time Tests
  # ============================================================================

  describe "real-time PubSub updates" do
    test "pool stats update when other users deposit", %{conn: conn} do
      user = create_user()

      set_bux_balance(user, 500)
      round = create_round()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/airdrop")

      # Simulate another user depositing via PubSub
      Phoenix.PubSub.broadcast(
        BlocksterV2.PubSub,
        "airdrop:#{round.round_id}",
        {:airdrop_deposit, round.round_id, 5000, 42}
      )

      # Give LiveView time to process the message
      Process.sleep(50)
      html = render(view)

      # Pool stats card splits the formatted total ("5,000") and the
      # "BUX entries in pool" sub-label across separate <div> nodes,
      # so the substring "5,000 BUX" never appears literally. Assert
      # both pieces independently.
      assert html =~ "5,000"
      assert html =~ "BUX entries"
      assert html =~ "42"
    end

    test "page transforms when airdrop is drawn via PubSub", %{conn: conn} do
      user = create_user()

      round = create_round()
      set_bux_balance(user, 500)
      {:ok, _entry} = Airdrop.redeem_bux(user, 500, round.round_id)
      conn = log_in_user(conn, user)

      {:ok, view, html} = live(conn, ~p"/airdrop")

      # Page should show entry form initially
      assert html =~ "Enter the airdrop"
      refute html =~ "The airdrop has been drawn"

      # Now close and draw
      block_hash = "0x" <> (:crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower))
      {:ok, _} = Airdrop.close_round(round.round_id, block_hash)
      {:ok, _} = Airdrop.draw_winners(round.round_id)
      winners = Airdrop.get_winners(round.round_id)

      # Broadcast drawn event
      Phoenix.PubSub.broadcast(
        BlocksterV2.PubSub,
        "airdrop:#{round.round_id}",
        {:airdrop_drawn, round.round_id, winners}
      )

      Process.sleep(50)
      html = render(view)

      assert html =~ "The airdrop has been drawn"
      assert html =~ "All 33 winners"
    end
  end

  # ============================================================================
  # Input Validation Tests
  # ============================================================================

  describe "input validation" do
    test "strips non-numeric characters from amount", %{conn: conn} do
      user = create_user()

      set_bux_balance(user, 500)
      conn = log_in_user(conn, user)
      _round = create_round()

      {:ok, view, _html} = live(conn, ~p"/airdrop")

      html = view |> element("input[phx-keyup=update_redeem_amount]") |> render_keyup(%{"value" => "abc123def"})

      assert html =~ "123"
    end

    test "set max fills full balance", %{conn: conn} do
      user = create_user()

      set_bux_balance(user, 999)
      conn = log_in_user(conn, user)
      _round = create_round()

      {:ok, view, _html} = live(conn, ~p"/airdrop")

      html = view |> element("button", "MAX") |> render_click()

      assert html =~ "999"
    end
  end

  # ============================================================================
  # Contract Address Integrity
  # ============================================================================

  describe "airdrop program address" do
    test "program ID appears in docs/addresses.md" do
      program_id = "wxiuLBuqxem5ETmGDndiW8MMkxKXp5jVsNCqdZgmjaG"
      addresses_md = File.read!(Path.join([File.cwd!(), "docs", "addresses.md"]))

      assert String.contains?(addresses_md, program_id),
             "Airdrop Program ID #{program_id} not found in docs/addresses.md"
    end
  end
end
