defmodule BlocksterV2.Airdrop.IntegrationTest do
  use BlocksterV2.DataCase, async: true

  alias BlocksterV2.Airdrop
  alias BlocksterV2.BuxMinter
  alias BlocksterV2.Accounts.User

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
    {:ok, round} = Airdrop.create_round(end_time)
    round
  end

  defp setup_drawn_round(users, amounts) do
    round = create_round()

    # Create entries for each user
    entries =
      Enum.zip(users, amounts)
      |> Enum.map(fn {user, amount} ->
        {:ok, entry} = Airdrop.redeem_bux(user, amount, round.round_id,
          external_wallet: user.wallet_address
        )
        entry
      end)

    # Close and draw
    block_hash = "0x" <> String.duplicate("ab", 32)
    {:ok, _} = Airdrop.close_round(round.round_id, block_hash)
    {:ok, _} = Airdrop.draw_winners(round.round_id)

    round = Airdrop.get_round(round.round_id)
    winners = Airdrop.get_winners(round.round_id)

    %{round: round, entries: entries, winners: winners}
  end

  # ============================================================================
  # BuxMinter.airdrop_deposit/4 Tests
  # ============================================================================

  describe "airdrop_deposit/4" do
    test "returns an error tuple (endpoints not yet deployed to production minter)" do
      wallet = "0x" <> String.duplicate("aa", 20)
      external = "0x" <> String.duplicate("bb", 20)

      result = BuxMinter.airdrop_deposit(wallet, external, 100, 1)

      # Either :not_configured (no secret) or HTTP error (endpoint doesn't exist yet)
      assert {:error, _reason} = result
    end
  end

  describe "airdrop_claim/2" do
    test "returns an error tuple (endpoints not yet deployed to production minter)" do
      result = BuxMinter.airdrop_claim(1, 0)

      assert {:error, _reason} = result
    end
  end

  describe "airdrop_set_prize/4" do
    test "returns an error tuple (endpoints not yet deployed to production minter)" do
      result = BuxMinter.airdrop_set_prize(1, 0, "0xwinner", 250_000_000)

      assert {:error, _reason} = result
    end
  end

  # ============================================================================
  # Claim Validation Tests
  # ============================================================================

  describe "claim_prize validation" do
    setup do
      user = create_user()
      %{round: round, winners: winners} = setup_drawn_round([user], [1000])
      %{round: round, user: user, winners: winners}
    end

    test "succeeds for legitimate winner with connected wallet", %{round: round, user: user} do
      external_wallet = "0x" <> String.duplicate("cc", 20)
      claim_tx = "0x" <> String.duplicate("dd", 32)

      {:ok, claimed} = Airdrop.claim_prize(
        user.id, round.round_id, 0, claim_tx, external_wallet
      )

      assert claimed.claimed == true
      assert claimed.claim_tx == claim_tx
      assert claimed.claim_wallet == external_wallet
    end

    test "rejects wrong user (user_id doesn't match winner)", %{round: round} do
      other_user = create_user()

      result = Airdrop.claim_prize(
        other_user.id, round.round_id, 0, "0xtx", "0xwallet"
      )

      assert {:error, :not_your_prize} = result
    end

    test "rejects already claimed prize", %{round: round, user: user} do
      {:ok, _} = Airdrop.claim_prize(user.id, round.round_id, 0, "0xtx1", "0xwallet1")

      result = Airdrop.claim_prize(user.id, round.round_id, 0, "0xtx2", "0xwallet2")
      assert {:error, :already_claimed} = result
    end

    test "rejects invalid round_id" do
      result = Airdrop.claim_prize(1, 9999, 0, "0xtx", "0xwallet")
      assert {:error, :winner_not_found} = result
    end

    test "rejects invalid winner_index", %{round: round, user: user} do
      result = Airdrop.claim_prize(user.id, round.round_id, 99, "0xtx", "0xwallet")
      assert {:error, :winner_not_found} = result
    end
  end

  # ============================================================================
  # Full Flow Tests (Mocked Blockchain)
  # ============================================================================

  describe "full airdrop flow" do
    test "create round → deposit → close → draw → verify winners → claim" do
      user1 = create_user()
      user2 = create_user()

      # 1. Create round
      {:ok, round} = Airdrop.create_round(~U[2026-03-15 00:00:00Z])
      assert round.status == "open"
      assert round.server_seed != nil
      assert round.commitment_hash != nil

      # 2. Users deposit BUX (simulating what would happen after airdrop_deposit call)
      {:ok, e1} = Airdrop.redeem_bux(user1, 500, round.round_id,
        external_wallet: user1.wallet_address,
        deposit_tx: "0xdeposit1"
      )
      assert e1.start_position == 1
      assert e1.end_position == 500

      {:ok, e2} = Airdrop.redeem_bux(user2, 300, round.round_id,
        external_wallet: user2.wallet_address,
        deposit_tx: "0xdeposit2"
      )
      assert e2.start_position == 501
      assert e2.end_position == 800

      # 3. Verify stats
      assert Airdrop.get_total_entries(round.round_id) == 800
      assert Airdrop.get_participant_count(round.round_id) == 2

      # 4. Close round
      block_hash = "0x" <> String.duplicate("ff", 32)
      {:ok, closed} = Airdrop.close_round(round.round_id, block_hash, close_tx: "0xclosetx")
      assert closed.status == "closed"
      assert closed.block_hash_at_close == block_hash

      # 5. Draw winners
      {:ok, drawn} = Airdrop.draw_winners(round.round_id, draw_tx: "0xdrawtx")
      assert drawn.status == "drawn"

      # 6. Verify winners
      winners = Airdrop.get_winners(round.round_id)
      assert length(winners) == 33

      # All winners have valid random numbers
      for w <- winners do
        assert w.random_number >= 1
        assert w.random_number <= 800
        assert w.wallet_address != nil
        assert w.external_wallet != nil
      end

      # Prize structure is correct
      assert Enum.at(winners, 0).prize_usd == 25_000
      assert Enum.at(winners, 1).prize_usd == 15_000
      assert Enum.at(winners, 2).prize_usd == 10_000

      for i <- 3..32 do
        assert Enum.at(winners, i).prize_usd == 5_000
      end

      # 7. Provably fair verification
      assert Airdrop.verify_fairness(round.round_id) == true
      {:ok, data} = Airdrop.get_verification_data(round.round_id)
      assert data.server_seed != nil
      assert data.commitment_hash != nil
      assert data.total_entries == 800

      # 8. Claim a prize (first winner)
      first_winner = hd(winners)
      {:ok, claimed} = Airdrop.claim_prize(
        first_winner.user_id,
        round.round_id,
        first_winner.winner_index,
        "0xarbitrum_claim_tx",
        "0xclaim_wallet"
      )

      assert claimed.claimed == true
      assert claimed.claim_tx == "0xarbitrum_claim_tx"
      assert claimed.claim_wallet == "0xclaim_wallet"

      # 9. Verify double-claim rejected
      assert {:error, :already_claimed} = Airdrop.claim_prize(
        first_winner.user_id,
        round.round_id,
        first_winner.winner_index,
        "0xtx2",
        "0xwallet2"
      )
    end

    test "two users deposit, both can win multiple prizes" do
      user1 = create_user()
      user2 = create_user()

      {:ok, round} = Airdrop.create_round(~U[2026-04-01 00:00:00Z])

      # User1 deposits 600 BUX (positions 1-600, 75% of pool)
      {:ok, _} = Airdrop.redeem_bux(user1, 600, round.round_id,
        external_wallet: user1.wallet_address
      )

      # User2 deposits 200 BUX (positions 601-800, 25% of pool)
      {:ok, _} = Airdrop.redeem_bux(user2, 200, round.round_id,
        external_wallet: user2.wallet_address
      )

      {:ok, _} = Airdrop.close_round(round.round_id, "0x" <> String.duplicate("cd", 32))
      {:ok, _} = Airdrop.draw_winners(round.round_id)

      winners = Airdrop.get_winners(round.round_id)

      # Both users should appear in the winners list
      user1_wins = Enum.filter(winners, &(&1.user_id == user1.id))
      user2_wins = Enum.filter(winners, &(&1.user_id == user2.id))

      # With 75%/25% split and 33 winners, both should have at least one win
      assert length(user1_wins) > 0
      assert length(user2_wins) > 0
      assert length(user1_wins) + length(user2_wins) == 33

      # User1 should have more wins (they have 75% of positions)
      assert length(user1_wins) > length(user2_wins)
    end

    test "database records are created correctly at each step" do
      user = create_user()

      # Round created
      {:ok, round} = Airdrop.create_round(~U[2026-05-01 00:00:00Z])
      assert Repo.aggregate(Airdrop.Round, :count) == 1
      assert Repo.aggregate(Airdrop.Entry, :count) == 0
      assert Repo.aggregate(Airdrop.Winner, :count) == 0

      # Entry created
      {:ok, _} = Airdrop.redeem_bux(user, 500, round.round_id)
      assert Repo.aggregate(Airdrop.Entry, :count) == 1
      assert Repo.aggregate(Airdrop.Winner, :count) == 0

      # Second entry
      {:ok, _} = Airdrop.redeem_bux(user, 300, round.round_id)
      assert Repo.aggregate(Airdrop.Entry, :count) == 2

      # After close - no new records, just status change
      {:ok, _} = Airdrop.close_round(round.round_id, "0x" <> String.duplicate("ee", 32))
      assert Repo.aggregate(Airdrop.Entry, :count) == 2
      assert Repo.aggregate(Airdrop.Winner, :count) == 0

      # After draw - 33 winner records created
      {:ok, _} = Airdrop.draw_winners(round.round_id)
      assert Repo.aggregate(Airdrop.Winner, :count) == 33

      # After claim - no new records, just update
      winners = Airdrop.get_winners(round.round_id)
      first = hd(winners)
      {:ok, _} = Airdrop.claim_prize(first.user_id, round.round_id, first.winner_index, "0xtx", "0xw")
      assert Repo.aggregate(Airdrop.Winner, :count) == 33

      claimed = Airdrop.get_winner(round.round_id, first.winner_index)
      assert claimed.claimed == true
    end

    test "deterministic draw — same inputs produce same winners" do
      user = create_user()

      # Create two rounds with the same server seed and block hash
      {:ok, round1} = Airdrop.create_round(~U[2026-03-01 00:00:00Z])
      {:ok, _} = Airdrop.redeem_bux(user, 1000, round1.round_id)
      {:ok, _} = Airdrop.close_round(round1.round_id, "0x" <> String.duplicate("ab", 32))

      # Save the seed before draw
      r1_data = Airdrop.get_round(round1.round_id)

      {:ok, _} = Airdrop.draw_winners(round1.round_id)
      winners1 = Airdrop.get_winners(round1.round_id)

      # Derive winners manually with same inputs
      combined_seed = Airdrop.keccak256_combined(
        r1_data.server_seed,
        r1_data.block_hash_at_close
      )

      # Each winner's random number should match
      for {w, i} <- Enum.with_index(winners1) do
        expected_pos = Airdrop.derive_position(combined_seed, i, 1000)
        assert w.random_number == expected_pos
      end
    end
  end

  # ============================================================================
  # Edge Cases
  # ============================================================================

  describe "edge cases" do
    test "single entry covers all positions" do
      user = create_user()
      round = create_round()
      {:ok, _} = Airdrop.redeem_bux(user, 100, round.round_id)
      {:ok, _} = Airdrop.close_round(round.round_id, "0x" <> String.duplicate("ab", 32))
      {:ok, _} = Airdrop.draw_winners(round.round_id)

      winners = Airdrop.get_winners(round.round_id)

      # All 33 winners should be the same user
      for w <- winners do
        assert w.user_id == user.id
        assert w.wallet_address == user.smart_wallet_address
      end
    end

    test "user with 1 BUX can still win" do
      user1 = create_user()
      user2 = create_user()

      round = create_round()
      {:ok, _} = Airdrop.redeem_bux(user1, 1, round.round_id,
        external_wallet: user1.wallet_address
      )
      {:ok, _} = Airdrop.redeem_bux(user2, 999, round.round_id,
        external_wallet: user2.wallet_address
      )

      {:ok, _} = Airdrop.close_round(round.round_id, "0x" <> String.duplicate("ab", 32))
      {:ok, _} = Airdrop.draw_winners(round.round_id)

      winners = Airdrop.get_winners(round.round_id)

      # User1 has position 1 only, may or may not win — but the system handles it
      user1_wins = Enum.filter(winners, &(&1.user_id == user1.id))
      # If they won, their random_number must be 1
      for w <- user1_wins do
        assert w.random_number == 1
      end
    end

    test "many small deposits from many users" do
      users = for _ <- 1..10, do: create_user()
      round = create_round()

      for user <- users do
        {:ok, _} = Airdrop.redeem_bux(user, 100, round.round_id,
          external_wallet: user.wallet_address
        )
      end

      assert Airdrop.get_total_entries(round.round_id) == 1000
      assert Airdrop.get_participant_count(round.round_id) == 10

      {:ok, _} = Airdrop.close_round(round.round_id, "0x" <> String.duplicate("ab", 32))
      {:ok, _} = Airdrop.draw_winners(round.round_id)

      winners = Airdrop.get_winners(round.round_id)
      assert length(winners) == 33

      # All winners should be from the depositing users
      winner_user_ids = Enum.map(winners, & &1.user_id) |> Enum.uniq()
      user_ids = Enum.map(users, & &1.id)
      for uid <- winner_user_ids do
        assert uid in user_ids
      end
    end
  end
end
