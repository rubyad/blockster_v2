defmodule BlocksterV2.AirdropTest do
  use BlocksterV2.DataCase, async: true

  alias BlocksterV2.Airdrop
  alias BlocksterV2.Airdrop.{Round, Entry, Winner}
  alias BlocksterV2.Accounts.User

  # ============================================================================
  # Mnesia Setup
  # ============================================================================

  defp setup_mnesia(_context) do
    :mnesia.start()

    tables = [
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
    record =
      {:user_bux_balances, user.id, user.smart_wallet_address, DateTime.utc_now(),
       balance * 1.0, balance * 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0}

    :mnesia.dirty_write(:user_bux_balances, record)
  end

  setup :setup_mnesia

  # ============================================================================
  # Test Helpers
  # ============================================================================

  defp create_user(attrs \\ %{}) do
    unique_id = System.unique_integer([:positive])

    default_attrs = %{
      wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
      smart_wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
      email: "user#{unique_id}@example.com",
      username: "user#{unique_id}",
      auth_method: "wallet",
      phone_verified: true
    }

    %User{}
    |> User.changeset(Map.merge(default_attrs, attrs))
    |> Repo.insert!()
  end

  defp create_round(opts \\ []) do
    end_time = Keyword.get(opts, :end_time, ~U[2026-03-01 00:00:00Z])
    {:ok, round} = Airdrop.create_round(end_time, skip_vault: true)
    round
  end

  defp future_time, do: ~U[2026-04-01 00:00:00Z]

  # ============================================================================
  # Round Management Tests
  # ============================================================================

  describe "create_round/1" do
    test "creates a round with server_seed and commitment_hash" do
      {:ok, round} = Airdrop.create_round(future_time(), skip_vault: true)

      assert round.round_id == 1
      assert round.status == "open"
      assert round.end_time == future_time()
      assert round.server_seed != nil
      assert round.commitment_hash != nil
      assert round.total_entries == 0
      assert String.length(round.server_seed) == 64
      assert String.length(round.commitment_hash) == 64
    end

    test "commitment_hash is SHA256 of server_seed" do
      {:ok, round} = Airdrop.create_round(future_time(), skip_vault: true)

      expected_hash =
        :crypto.hash(:sha256, round.server_seed)
        |> Base.encode16(case: :lower)

      assert round.commitment_hash == expected_hash
    end

    test "auto-increments round_id" do
      {:ok, r1} = Airdrop.create_round(future_time(), skip_vault: true)
      {:ok, r2} = Airdrop.create_round(~U[2026-05-01 00:00:00Z], skip_vault: true)

      assert r1.round_id == 1
      assert r2.round_id == 2
    end

    test "accepts optional vault and prize pool addresses" do
      {:ok, round} = Airdrop.create_round(future_time(),
        skip_vault: true,
        vault_address: "0xvault",
        prize_pool_address: "0xpool"
      )

      assert round.vault_address == "0xvault"
      assert round.prize_pool_address == "0xpool"
    end
  end

  describe "get_current_round/0" do
    test "returns the open round" do
      round = create_round()
      current = Airdrop.get_current_round()

      assert current.id == round.id
      assert current.status == "open"
    end

    test "returns nil when no active round" do
      assert Airdrop.get_current_round() == nil
    end

    test "returns closed round (still active, just not accepting deposits)" do
      round = create_round()

      {:ok, closed} = Airdrop.close_round(round.round_id, "0xblockhash123")

      current = Airdrop.get_current_round()
      assert current.id == closed.id
      assert current.status == "closed"
    end

    test "returns drawn rounds so LiveView can display results" do
      round = create_round()
      user = create_user()

      # Add entries, close, and draw
      set_bux_balance(user, 100)
      {:ok, _} = Airdrop.redeem_bux(user, 100, round.round_id)
      {:ok, _} = Airdrop.close_round(round.round_id, "0x" <> String.duplicate("ab", 32))
      {:ok, _} = Airdrop.draw_winners(round.round_id)

      current = Airdrop.get_current_round()
      assert current.round_id == round.round_id
      assert current.status == "drawn"
    end
  end

  describe "get_round/1" do
    test "returns round by round_id" do
      round = create_round()
      found = Airdrop.get_round(round.round_id)

      assert found.id == round.id
    end

    test "returns nil for non-existent round" do
      assert Airdrop.get_round(999) == nil
    end
  end

  describe "get_past_rounds/0" do
    test "returns drawn rounds ordered by most recent" do
      r1 = create_round()
      user = create_user()

      set_bux_balance(user, 100)
      {:ok, _} = Airdrop.redeem_bux(user, 100, r1.round_id)
      {:ok, _} = Airdrop.close_round(r1.round_id, "0x" <> String.duplicate("ab", 32))
      {:ok, _} = Airdrop.draw_winners(r1.round_id)

      r2 = create_round(end_time: ~U[2026-05-01 00:00:00Z])
      set_bux_balance(user, 200)
      {:ok, _} = Airdrop.redeem_bux(user, 200, r2.round_id)
      {:ok, _} = Airdrop.close_round(r2.round_id, "0x" <> String.duplicate("cd", 32))
      {:ok, _} = Airdrop.draw_winners(r2.round_id)

      past = Airdrop.get_past_rounds()
      assert length(past) == 2
      assert hd(past).round_id == r2.round_id
    end

    test "excludes open and closed rounds" do
      _open = create_round()
      assert Airdrop.get_past_rounds() == []
    end
  end

  describe "close_round/2" do
    test "closes an open round with block hash" do
      round = create_round()
      {:ok, closed} = Airdrop.close_round(round.round_id, "0xblockhash")

      assert closed.status == "closed"
      assert closed.block_hash_at_close == "0xblockhash"
    end

    test "accepts optional close_tx" do
      round = create_round()
      {:ok, closed} = Airdrop.close_round(round.round_id, "0xhash", close_tx: "0xtxhash")

      assert closed.close_tx == "0xtxhash"
    end

    test "rejects closing a non-existent round" do
      assert {:error, :round_not_found} = Airdrop.close_round(999, "0xhash")
    end

    test "rejects closing an already closed round" do
      round = create_round()
      {:ok, _} = Airdrop.close_round(round.round_id, "0xhash1")

      assert {:error, {:invalid_status, "closed"}} = Airdrop.close_round(round.round_id, "0xhash2")
    end
  end

  # ============================================================================
  # Entry Management Tests
  # ============================================================================

  describe "redeem_bux/4" do
    test "creates entry with correct positions" do
      round = create_round()
      user = create_user()

      set_bux_balance(user, 100)
      {:ok, entry} = Airdrop.redeem_bux(user, 100, round.round_id)

      assert entry.user_id == user.id
      assert entry.amount == 100
      assert entry.start_position == 1
      assert entry.end_position == 100
      assert entry.wallet_address == user.smart_wallet_address
    end

    test "sequential entries get non-overlapping positions" do
      round = create_round()
      user1 = create_user()
      user2 = create_user()

      set_bux_balance(user1, 50)
      {:ok, e1} = Airdrop.redeem_bux(user1, 50, round.round_id)
      set_bux_balance(user2, 30)
      {:ok, e2} = Airdrop.redeem_bux(user2, 30, round.round_id)

      assert e1.start_position == 1
      assert e1.end_position == 50
      assert e2.start_position == 51
      assert e2.end_position == 80
    end

    test "same user can redeem multiple times" do
      round = create_round()
      user = create_user()

      set_bux_balance(user, 150)
      {:ok, e1} = Airdrop.redeem_bux(user, 100, round.round_id)
      {:ok, e2} = Airdrop.redeem_bux(user, 50, round.round_id)

      assert e1.start_position == 1
      assert e1.end_position == 100
      assert e2.start_position == 101
      assert e2.end_position == 150
    end

    test "updates round total_entries" do
      round = create_round()
      user = create_user()

      set_bux_balance(user, 150)
      {:ok, _} = Airdrop.redeem_bux(user, 100, round.round_id)
      updated = Airdrop.get_round(round.round_id)
      assert updated.total_entries == 100

      {:ok, _} = Airdrop.redeem_bux(user, 50, round.round_id)
      updated = Airdrop.get_round(round.round_id)
      assert updated.total_entries == 150
    end

    test "accepts external_wallet option" do
      round = create_round()
      user = create_user()

      set_bux_balance(user, 100)
      {:ok, entry} = Airdrop.redeem_bux(user, 100, round.round_id,
        external_wallet: "0xexternal"
      )

      assert entry.external_wallet == "0xexternal"
    end

    test "rejects when user is not phone verified" do
      round = create_round()
      user = create_user(%{phone_verified: false})

      assert {:error, :phone_not_verified} = Airdrop.redeem_bux(user, 100, round.round_id)
    end

    test "rejects when round is closed" do
      round = create_round()
      user = create_user()
      {:ok, _} = Airdrop.close_round(round.round_id, "0xhash")

      assert {:error, {:round_not_open, "closed"}} = Airdrop.redeem_bux(user, 100, round.round_id)
    end

    test "rejects when round is drawn" do
      round = create_round()
      user = create_user()

      set_bux_balance(user, 100)
      {:ok, _} = Airdrop.redeem_bux(user, 100, round.round_id)
      {:ok, _} = Airdrop.close_round(round.round_id, "0x" <> String.duplicate("ab", 32))
      {:ok, _} = Airdrop.draw_winners(round.round_id)

      assert {:error, {:round_not_open, "drawn"}} = Airdrop.redeem_bux(user, 50, round.round_id)
    end

    test "rejects non-existent round" do
      user = create_user()
      assert {:error, :round_not_found} = Airdrop.redeem_bux(user, 100, 999)
    end

    test "rejects zero amount" do
      round = create_round()
      user = create_user()
      assert {:error, :invalid_amount} = Airdrop.redeem_bux(user, 0, round.round_id)
    end

    test "rejects negative amount" do
      round = create_round()
      user = create_user()
      assert {:error, :invalid_amount} = Airdrop.redeem_bux(user, -10, round.round_id)
    end
  end

  describe "get_user_entries/2" do
    test "returns entries for a user in a round" do
      round = create_round()
      user = create_user()

      set_bux_balance(user, 80)
      {:ok, _} = Airdrop.redeem_bux(user, 50, round.round_id)
      {:ok, _} = Airdrop.redeem_bux(user, 30, round.round_id)

      entries = Airdrop.get_user_entries(user.id, round.round_id)
      assert length(entries) == 2
      assert Enum.at(entries, 0).amount == 50
      assert Enum.at(entries, 1).amount == 30
    end

    test "returns empty list for user with no entries" do
      round = create_round()
      user = create_user()

      assert Airdrop.get_user_entries(user.id, round.round_id) == []
    end

    test "does not return entries from other rounds" do
      r1 = create_round()
      r2 = create_round(end_time: ~U[2026-05-01 00:00:00Z])
      user = create_user()

      set_bux_balance(user, 50)
      {:ok, _} = Airdrop.redeem_bux(user, 50, r1.round_id)
      set_bux_balance(user, 30)
      {:ok, _} = Airdrop.redeem_bux(user, 30, r2.round_id)

      entries = Airdrop.get_user_entries(user.id, r1.round_id)
      assert length(entries) == 1
      assert hd(entries).amount == 50
    end
  end

  describe "get_total_entries/1" do
    test "returns total BUX deposited" do
      round = create_round()
      user1 = create_user()
      user2 = create_user()

      set_bux_balance(user1, 100)
      {:ok, _} = Airdrop.redeem_bux(user1, 100, round.round_id)
      set_bux_balance(user2, 50)
      {:ok, _} = Airdrop.redeem_bux(user2, 50, round.round_id)

      assert Airdrop.get_total_entries(round.round_id) == 150
    end

    test "returns 0 for round with no entries" do
      round = create_round()
      assert Airdrop.get_total_entries(round.round_id) == 0
    end

    test "returns 0 for non-existent round" do
      assert Airdrop.get_total_entries(999) == 0
    end
  end

  describe "get_participant_count/1" do
    test "returns unique wallet count" do
      round = create_round()
      user1 = create_user()
      user2 = create_user()

      set_bux_balance(user1, 150)
      {:ok, _} = Airdrop.redeem_bux(user1, 100, round.round_id)
      {:ok, _} = Airdrop.redeem_bux(user1, 50, round.round_id)
      set_bux_balance(user2, 30)
      {:ok, _} = Airdrop.redeem_bux(user2, 30, round.round_id)

      assert Airdrop.get_participant_count(round.round_id) == 2
    end
  end

  # ============================================================================
  # Draw Winners Tests
  # ============================================================================

  describe "draw_winners/1" do
    setup do
      round = create_round()
      user1 = create_user()
      user2 = create_user()
      user3 = create_user()

      # Create enough entries to draw from
      set_bux_balance(user1, 500)
      {:ok, _} = Airdrop.redeem_bux(user1, 500, round.round_id)
      set_bux_balance(user2, 300)
      {:ok, _} = Airdrop.redeem_bux(user2, 300, round.round_id)
      set_bux_balance(user3, 200)
      {:ok, _} = Airdrop.redeem_bux(user3, 200, round.round_id)

      block_hash = "0x" <> String.duplicate("ab", 32)
      {:ok, _} = Airdrop.close_round(round.round_id, block_hash)

      %{round: Airdrop.get_round(round.round_id), users: [user1, user2, user3]}
    end

    test "creates 33 winner records", %{round: round} do
      {:ok, _} = Airdrop.draw_winners(round.round_id)

      winners = Airdrop.get_winners(round.round_id)
      assert length(winners) == 33
    end

    test "updates round status to drawn", %{round: round} do
      {:ok, _} = Airdrop.draw_winners(round.round_id)

      updated = Airdrop.get_round(round.round_id)
      assert updated.status == "drawn"
    end

    test "assigns correct prize amounts", %{round: round} do
      {:ok, _} = Airdrop.draw_winners(round.round_id)

      winners = Airdrop.get_winners(round.round_id)

      # Prize pool: $2,000 total
      # 1st: $250
      assert Enum.at(winners, 0).prize_usd == 25_000
      assert Enum.at(winners, 0).prize_usdt == 250_000_000

      # 2nd: $150
      assert Enum.at(winners, 1).prize_usd == 15_000
      assert Enum.at(winners, 1).prize_usdt == 150_000_000

      # 3rd: $100
      assert Enum.at(winners, 2).prize_usd == 10_000
      assert Enum.at(winners, 2).prize_usdt == 100_000_000

      # 4th-33rd: $50 each
      for i <- 3..32 do
        assert Enum.at(winners, i).prize_usd == 5_000
        assert Enum.at(winners, i).prize_usdt == 50_000_000
      end

      # Total: $250 + $150 + $100 + (30 × $50) = $2,000
      total_usd = Enum.reduce(winners, 0, fn w, acc -> acc + w.prize_usd end)
      assert total_usd == 200_000
    end

    test "winners have valid random numbers within range", %{round: round} do
      {:ok, _} = Airdrop.draw_winners(round.round_id)

      winners = Airdrop.get_winners(round.round_id)
      total_entries = round.total_entries

      for winner <- winners do
        assert winner.random_number >= 1
        assert winner.random_number <= total_entries
      end
    end

    test "winners have valid deposit info", %{round: round} do
      {:ok, _} = Airdrop.draw_winners(round.round_id)

      winners = Airdrop.get_winners(round.round_id)

      for winner <- winners do
        assert winner.wallet_address != nil
        assert winner.deposit_start > 0
        assert winner.deposit_end >= winner.deposit_start
        assert winner.deposit_amount > 0
        # random_number falls within the deposit range
        assert winner.random_number >= winner.deposit_start
        assert winner.random_number <= winner.deposit_end
      end
    end

    test "winners are ordered by winner_index", %{round: round} do
      {:ok, _} = Airdrop.draw_winners(round.round_id)

      winners = Airdrop.get_winners(round.round_id)
      indices = Enum.map(winners, & &1.winner_index)
      assert indices == Enum.to_list(0..32)
    end

    test "rejects drawing from an open round" do
      round = create_round(end_time: ~U[2026-06-01 00:00:00Z])
      user = create_user()
      set_bux_balance(user, 100)
      {:ok, _} = Airdrop.redeem_bux(user, 100, round.round_id)

      assert {:error, {:invalid_status, "open"}} = Airdrop.draw_winners(round.round_id)
    end

    test "rejects drawing from a non-existent round" do
      assert {:error, :round_not_found} = Airdrop.draw_winners(999)
    end

    test "rejects drawing with no entries" do
      round = create_round(end_time: ~U[2026-06-01 00:00:00Z])
      {:ok, _} = Airdrop.close_round(round.round_id, "0xhash")

      assert {:error, :no_entries} = Airdrop.draw_winners(round.round_id)
    end

    test "accepts optional draw_tx", %{round: round} do
      {:ok, _} = Airdrop.draw_winners(round.round_id, draw_tx: "0xdrawtx")

      updated = Airdrop.get_round(round.round_id)
      assert updated.draw_tx == "0xdrawtx"
    end
  end

  # ============================================================================
  # Winner Management Tests
  # ============================================================================

  describe "get_winners/1" do
    test "returns all 33 winners ordered by winner_index" do
      round = create_round()
      user = create_user()
      set_bux_balance(user, 1000)
      {:ok, _} = Airdrop.redeem_bux(user, 1000, round.round_id)
      {:ok, _} = Airdrop.close_round(round.round_id, "0x" <> String.duplicate("ab", 32))
      {:ok, _} = Airdrop.draw_winners(round.round_id)

      winners = Airdrop.get_winners(round.round_id)
      assert length(winners) == 33
      assert Enum.at(winners, 0).winner_index == 0
      assert Enum.at(winners, 32).winner_index == 32
    end

    test "returns empty list for round with no draw" do
      round = create_round()
      assert Airdrop.get_winners(round.round_id) == []
    end
  end

  describe "is_winner?/2" do
    test "returns true for a winner" do
      round = create_round()
      user = create_user()
      set_bux_balance(user, 1000)
      {:ok, _} = Airdrop.redeem_bux(user, 1000, round.round_id)
      {:ok, _} = Airdrop.close_round(round.round_id, "0x" <> String.duplicate("ab", 32))
      {:ok, _} = Airdrop.draw_winners(round.round_id)

      # The only depositor, so they must be a winner
      assert Airdrop.is_winner?(user.id, round.round_id)
    end

    test "returns false for non-winner" do
      round = create_round()
      user = create_user()
      non_participant = create_user()

      set_bux_balance(user, 1000)
      {:ok, _} = Airdrop.redeem_bux(user, 1000, round.round_id)
      {:ok, _} = Airdrop.close_round(round.round_id, "0x" <> String.duplicate("ab", 32))
      {:ok, _} = Airdrop.draw_winners(round.round_id)

      refute Airdrop.is_winner?(non_participant.id, round.round_id)
    end
  end

  describe "claim_prize/5" do
    setup do
      round = create_round()
      user = create_user()
      set_bux_balance(user, 1000)
      {:ok, _} = Airdrop.redeem_bux(user, 1000, round.round_id)
      {:ok, _} = Airdrop.close_round(round.round_id, "0x" <> String.duplicate("ab", 32))
      {:ok, _} = Airdrop.draw_winners(round.round_id)

      winners = Airdrop.get_winners(round.round_id)

      %{round: Airdrop.get_round(round.round_id), user: user, winners: winners}
    end

    test "marks winner as claimed with tx and wallet", %{round: round, user: user} do
      {:ok, claimed} = Airdrop.claim_prize(user.id, round.round_id, 0, "0xclaim_tx", "0xclaim_wallet")

      assert claimed.claimed == true
      assert claimed.claim_tx == "0xclaim_tx"
      assert claimed.claim_wallet == "0xclaim_wallet"
    end

    test "rejects if already claimed", %{round: round, user: user} do
      {:ok, _} = Airdrop.claim_prize(user.id, round.round_id, 0, "0xtx1", "0xwallet1")

      assert {:error, :already_claimed} = Airdrop.claim_prize(user.id, round.round_id, 0, "0xtx2", "0xwallet2")
    end

    test "rejects if user doesn't own the winning index", %{round: round} do
      other_user = create_user()

      assert {:error, :not_your_prize} = Airdrop.claim_prize(other_user.id, round.round_id, 0, "0xtx", "0xwallet")
    end

    test "rejects non-existent winner" do
      assert {:error, :winner_not_found} = Airdrop.claim_prize(1, 999, 0, "0xtx", "0xwallet")
    end
  end

  # ============================================================================
  # Prize Helper Tests
  # ============================================================================

  describe "prize_usd_for_index/1" do
    test "returns correct prizes for each position" do
      # Prize pool: $2,000 total, values in USD cents
      assert Airdrop.prize_usd_for_index(0) == 25_000   # $250
      assert Airdrop.prize_usd_for_index(1) == 15_000   # $150
      assert Airdrop.prize_usd_for_index(2) == 10_000   # $100
      assert Airdrop.prize_usd_for_index(3) == 5_000    # $50
      assert Airdrop.prize_usd_for_index(32) == 5_000   # $50
    end
  end

  describe "prize_usdt_for_index/1" do
    test "returns correct USDT amounts (6 decimals)" do
      assert Airdrop.prize_usdt_for_index(0) == 250_000_000   # $250
      assert Airdrop.prize_usdt_for_index(1) == 150_000_000   # $150
      assert Airdrop.prize_usdt_for_index(2) == 100_000_000   # $100
      assert Airdrop.prize_usdt_for_index(3) == 50_000_000    # $50
    end
  end

  # ============================================================================
  # Verification Tests
  # ============================================================================

  describe "get_commitment_hash/1" do
    test "returns commitment hash for existing round" do
      round = create_round()
      hash = Airdrop.get_commitment_hash(round.round_id)

      assert hash != nil
      assert String.length(hash) == 64
    end

    test "returns nil for non-existent round" do
      assert Airdrop.get_commitment_hash(999) == nil
    end
  end

  describe "get_verification_data/1" do
    test "returns full data for drawn round" do
      round = create_round()
      user = create_user()
      set_bux_balance(user, 1000)
      {:ok, _} = Airdrop.redeem_bux(user, 1000, round.round_id)
      {:ok, _} = Airdrop.close_round(round.round_id, "0x" <> String.duplicate("ab", 32))
      {:ok, _} = Airdrop.draw_winners(round.round_id)

      {:ok, data} = Airdrop.get_verification_data(round.round_id)

      assert data.server_seed != nil
      assert data.commitment_hash != nil
      assert data.block_hash_at_close != nil
      assert data.total_entries == 1000
      assert data.round_id == round.round_id
    end

    test "rejects for non-drawn round" do
      round = create_round()
      assert {:error, :not_yet_drawn} = Airdrop.get_verification_data(round.round_id)
    end

    test "rejects for non-existent round" do
      assert {:error, :round_not_found} = Airdrop.get_verification_data(999)
    end
  end

  describe "verify_fairness/1" do
    test "returns true for valid drawn round" do
      round = create_round()
      user = create_user()
      set_bux_balance(user, 1000)
      {:ok, _} = Airdrop.redeem_bux(user, 1000, round.round_id)
      {:ok, _} = Airdrop.close_round(round.round_id, "0x" <> String.duplicate("ab", 32))
      {:ok, _} = Airdrop.draw_winners(round.round_id)

      assert Airdrop.verify_fairness(round.round_id) == true
    end
  end
end
