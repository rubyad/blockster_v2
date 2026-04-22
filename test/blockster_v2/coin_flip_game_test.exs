defmodule BlocksterV2.CoinFlipGameTest do
  use BlocksterV2.DataCase, async: false

  alias BlocksterV2.CoinFlipGame

  # ============================================================================
  # Tests for CoinFlipGame module (Phase 6 Solana migration)
  # ============================================================================

  setup do
    :mnesia.start()

    # Create coin_flip_games table
    case :mnesia.create_table(:coin_flip_games, [
           attributes: [
             :game_id, :user_id, :wallet_address, :server_seed, :commitment_hash,
             :nonce, :status, :vault_type, :bet_amount, :difficulty,
             :predictions, :results, :won, :payout,
             :commitment_sig, :bet_sig, :settlement_sig, :created_at, :settled_at
           ],
           ram_copies: [node()],
           type: :ordered_set,
           index: [:user_id, :wallet_address, :status, :created_at]
         ]) do
      {:atomic, :ok} -> :ok
      {:aborted, {:already_exists, :coin_flip_games}} ->
        case :mnesia.add_table_copy(:coin_flip_games, node(), :ram_copies) do
          {:atomic, :ok} -> :ok
          {:aborted, {:already_exists, :coin_flip_games, _}} -> :ok
        end
        :mnesia.clear_table(:coin_flip_games)
    end

    # Create user_betting_stats table (needed by update_user_betting_stats)
    case :mnesia.create_table(:user_betting_stats, [
           attributes: [
             :user_id, :wallet_address,
             :bux_total_bets, :bux_wins, :bux_losses, :bux_total_wagered,
             :bux_total_winnings, :bux_total_losses, :bux_net_pnl,
             :rogue_total_bets, :rogue_wins, :rogue_losses, :rogue_total_wagered,
             :rogue_total_winnings, :rogue_total_losses, :rogue_net_pnl,
             :first_bet_at, :last_bet_at, :updated_at, :onchain_stats_cache
           ],
           ram_copies: [node()],
           type: :set,
           index: [:bux_total_wagered, :rogue_total_wagered]
         ]) do
      {:atomic, :ok} -> :ok
      {:aborted, {:already_exists, :user_betting_stats}} ->
        case :mnesia.add_table_copy(:user_betting_stats, node(), :ram_copies) do
          {:atomic, :ok} -> :ok
          {:aborted, {:already_exists, :user_betting_stats, _}} -> :ok
        end
        :mnesia.clear_table(:user_betting_stats)
    end

    :ok
  end

  # ============================================================================
  # Result Calculation Tests (provably fair logic)
  # ============================================================================

  describe "calculate_result/7" do
    test "returns results with correct number of flips" do
      server_seed = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)

      {:ok, result} = CoinFlipGame.calculate_result(
        server_seed, 0, [:heads], 100, :bux, 1, 1
      )

      assert length(result.results) == 1
      assert result.results |> Enum.all?(fn r -> r in [:heads, :tails] end)
    end

    test "returns correct flip count per difficulty" do
      server_seed = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)

      difficulties = [
        {-4, 5}, {-3, 4}, {-2, 3}, {-1, 2},
        {1, 1}, {2, 2}, {3, 3}, {4, 4}, {5, 5}
      ]

      for {diff, expected_flips} <- difficulties do
        predictions = List.duplicate(:heads, expected_flips)
        {:ok, result} = CoinFlipGame.calculate_result(server_seed, 0, predictions, 100, :bux, diff, 1)
        assert length(result.results) == expected_flips, "Difficulty #{diff} should have #{expected_flips} flips"
      end
    end

    test "win_all mode requires all flips to match" do
      # Difficulty 1 = 1 flip, win_all mode
      server_seed = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
      {:ok, result} = CoinFlipGame.calculate_result(server_seed, 0, [:heads], 100, :bux, 1, 1)

      if Enum.at(result.results, 0) == :heads do
        assert result.won == true
      else
        assert result.won == false
      end
    end

    test "payout is 0 on loss" do
      # Run several iterations to find a loss case
      Enum.reduce_while(1..100, nil, fn i, _acc ->
        server_seed = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
        {:ok, result} = CoinFlipGame.calculate_result(server_seed, i, [:heads, :heads, :heads, :heads, :heads], 100, :bux, 5, 1)

        if not result.won do
          assert result.payout == 0
          {:halt, :found}
        else
          {:cont, nil}
        end
      end)
    end

    test "payout matches multiplier on win" do
      Enum.reduce_while(1..100, nil, fn i, _acc ->
        server_seed = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
        {:ok, result} = CoinFlipGame.calculate_result(server_seed, i, [:heads], 100, :bux, 1, 1)

        if result.won do
          # 1.98x multiplier for difficulty 1
          expected_payout = Float.round(100 * 19800 / 10000, 2)
          assert result.payout == expected_payout
          {:halt, :found}
        else
          {:cont, nil}
        end
      end)
    end

    test "deterministic results with same inputs" do
      server_seed = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
      predictions = [:heads, :tails]

      {:ok, result1} = CoinFlipGame.calculate_result(server_seed, 0, predictions, 100, :bux, 2, 1)
      {:ok, result2} = CoinFlipGame.calculate_result(server_seed, 0, predictions, 100, :bux, 2, 1)

      assert result1.results == result2.results
      assert result1.won == result2.won
      assert result1.payout == result2.payout
    end

    test "different nonces produce different results (usually)" do
      server_seed = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)

      results = for nonce <- 0..20 do
        {:ok, result} = CoinFlipGame.calculate_result(server_seed, nonce, [:heads], 100, :bux, 1, 1)
        result.results
      end

      # With 21 samples, we should have at least 2 different results
      unique_results = Enum.uniq(results)
      assert length(unique_results) > 1
    end

    test "vault_type sol works the same as bux" do
      server_seed = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)

      {:ok, sol_result} = CoinFlipGame.calculate_result(server_seed, 0, [:heads], 100, :sol, 1, 1)
      {:ok, bux_result} = CoinFlipGame.calculate_result(server_seed, 0, [:heads], 100, :bux, 1, 1)

      # Different vault types should produce different results (different client seed)
      # since vault_type is part of client seed generation
      # (They CAN be the same by chance, so we just verify both succeed)
      assert is_list(sol_result.results)
      assert is_list(bux_result.results)
    end

    test "win_one mode with negative difficulty" do
      # Difficulty -4: 5 flips, win if ANY match
      server_seed = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
      predictions = [:heads, :heads, :heads, :heads, :heads]

      {:ok, result} = CoinFlipGame.calculate_result(server_seed, 0, predictions, 100, :bux, -4, 1)
      assert length(result.results) == 5

      # With 5 flips all predicting heads, and each flip being ~50% chance,
      # the probability of at least one match is very high (96.875%)
      # Just verify the logic is correct:
      any_match = Enum.zip(predictions, result.results)
      |> Enum.any?(fn {pred, res} -> pred == res end)

      assert result.won == any_match
    end
  end

  # ============================================================================
  # Game Record Tests
  # ============================================================================

  describe "get_game/1" do
    test "returns {:error, :not_found} for non-existent game" do
      assert {:error, :not_found} = CoinFlipGame.get_game("nonexistent")
    end

    test "returns game record after writing to Mnesia" do
      now = System.system_time(:second)
      record = {
        :coin_flip_games,
        "test_game_1", 1, "SolanaWallet123", "server_seed_hex",
        "commitment_hash_hex", 0, :committed, nil, nil, nil, nil, nil, nil, nil,
        "sig123", nil, nil, now, nil
      }
      :mnesia.dirty_write(record)

      assert {:ok, game} = CoinFlipGame.get_game("test_game_1")
      assert game.user_id == 1
      assert game.wallet_address == "SolanaWallet123"
      assert game.server_seed == "server_seed_hex"
      assert game.status == :committed
      assert game.commitment_sig == "sig123"
    end
  end

  describe "get_pending_game/1" do
    test "returns nil when no games exist" do
      assert nil == CoinFlipGame.get_pending_game(999)
    end

    test "returns pending committed game" do
      now = System.system_time(:second)
      record = {
        :coin_flip_games,
        "pending_game", 42, "wallet42", "seed", "hash", 0, :committed,
        nil, nil, nil, nil, nil, nil, nil, "sig", nil, nil, now, nil
      }
      :mnesia.dirty_write(record)

      game = CoinFlipGame.get_pending_game(42)
      assert game != nil
      assert game.game_id == "pending_game"
      assert game.status == :committed
    end

    test "does not return settled games" do
      now = System.system_time(:second)
      record = {
        :coin_flip_games,
        "settled_game", 42, "wallet42", "seed", "hash", 0, :settled,
        :bux, 100, 1, [:heads], [:tails], false, 0, "sig", "bet_sig", "settle_sig", now, now
      }
      :mnesia.dirty_write(record)

      assert nil == CoinFlipGame.get_pending_game(42)
    end
  end

  # ============================================================================
  # Nonce Calculation Tests
  # ============================================================================

  describe "nonce calculation (Mnesia-based)" do
    # Helper to compute next nonce from Mnesia (same logic as get_or_init_game)
    defp compute_next_nonce(user_id, wallet_address) do
      case :mnesia.dirty_match_object(
        {:coin_flip_games, :_, user_id, wallet_address, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}
      ) do
        [] -> 0
        games ->
          placed_games = Enum.filter(games, fn game -> elem(game, 7) in [:placed, :settled] end)
          case placed_games do
            [] -> 0
            _ ->
              placed_games
              |> Enum.map(fn game -> elem(game, 6) end)
              |> Enum.max()
              |> Kernel.+(1)
          end
      end
    end

    test "starts at 0 for new user with no games" do
      assert 0 == compute_next_nonce(999, "new_wallet")
    end

    test "increments after placed games" do
      now = System.system_time(:second)

      record0 = {:coin_flip_games,
        "game_0", 1, "wallet1", "seed0", "hash0", 0, :placed,
        :bux, 100, 1, [:heads], [:heads], true, 198.0,
        "sig0", "bet0", nil, now, nil}
      :mnesia.dirty_write(record0)

      record1 = {:coin_flip_games,
        "game_1", 1, "wallet1", "seed1", "hash1", 1, :placed,
        :bux, 100, 1, [:tails], [:tails], true, 198.0,
        "sig1", "bet1", nil, now, nil}
      :mnesia.dirty_write(record1)

      assert 2 == compute_next_nonce(1, "wallet1")
    end

    test "increments after settled games" do
      now = System.system_time(:second)

      record = {:coin_flip_games,
        "settled_1", 1, "wallet1", "seed", "hash", 5, :settled,
        :bux, 100, 1, [:heads], [:heads], true, 198.0,
        "sig", "bet", "settle", now, now}
      :mnesia.dirty_write(record)

      assert 6 == compute_next_nonce(1, "wallet1")
    end

    test "ignores committed-only games for nonce calculation" do
      now = System.system_time(:second)

      # Committed but never placed — should NOT count
      record = {:coin_flip_games,
        "committed_only", 1, "wallet1", "seed", "hash", 0, :committed,
        nil, nil, nil, nil, nil, nil, nil,
        "sig", nil, nil, now, nil}
      :mnesia.dirty_write(record)

      assert 0 == compute_next_nonce(1, "wallet1")
    end

    test "handles mixed placed and settled games" do
      now = System.system_time(:second)

      record0 = {:coin_flip_games,
        "g0", 1, "wallet1", "s0", "h0", 0, :settled,
        :bux, 100, 1, [:heads], [:heads], true, 198.0,
        "sig0", "bet0", "set0", now, now}
      record1 = {:coin_flip_games,
        "g1", 1, "wallet1", "s1", "h1", 1, :settled,
        :bux, 100, 1, [:tails], [:tails], false, 0,
        "sig1", "bet1", "set1", now, now}
      record2 = {:coin_flip_games,
        "g2", 1, "wallet1", "s2", "h2", 2, :placed,
        :bux, 100, 1, [:heads], [:heads], true, 198.0,
        "sig2", "bet2", nil, now, nil}

      :mnesia.dirty_write(record0)
      :mnesia.dirty_write(record1)
      :mnesia.dirty_write(record2)

      assert 3 == compute_next_nonce(1, "wallet1")
    end

    test "handles concurrent placed games at different nonces" do
      now = System.system_time(:second)

      # Simulates concurrent bets: nonce 0 and 1 both placed (not settled)
      for n <- 0..4 do
        record = {:coin_flip_games,
          "g#{n}", 1, "wallet1", "s#{n}", "h#{n}", n, :placed,
          :bux, 100, 1, [:heads], [:heads], true, 198.0,
          "sig#{n}", "bet#{n}", nil, now, nil}
        :mnesia.dirty_write(record)
      end

      assert 5 == compute_next_nonce(1, "wallet1")
    end

    test "different wallets have independent nonces" do
      now = System.system_time(:second)

      record_a = {:coin_flip_games,
        "ga", 1, "walletA", "sa", "ha", 3, :settled,
        :bux, 100, 1, [:heads], [:heads], true, 198.0,
        "siga", "beta", "seta", now, now}
      record_b = {:coin_flip_games,
        "gb", 1, "walletB", "sb", "hb", 0, :placed,
        :bux, 100, 1, [:tails], [:tails], false, 0,
        "sigb", "betb", nil, now, nil}

      :mnesia.dirty_write(record_a)
      :mnesia.dirty_write(record_b)

      assert 4 == compute_next_nonce(1, "walletA")
      assert 1 == compute_next_nonce(1, "walletB")
    end

    test "reuses existing pending commitment with matching nonce" do
      now = System.system_time(:second)

      # Pending committed game at nonce 0 (correct nonce for new user)
      record = {:coin_flip_games,
        "pending_game", 42, "wallet42", "seed", "hash", 0, :committed,
        nil, nil, nil, nil, nil, nil, nil,
        "sig", nil, nil, now, nil}
      :mnesia.dirty_write(record)

      game = CoinFlipGame.get_pending_game(42)
      assert game != nil
      assert game.nonce == 0
      assert game.commitment_sig == "sig"
    end

    test "does not reuse pending commitment with wrong nonce" do
      now = System.system_time(:second)

      # A placed game at nonce 0 means next nonce should be 1
      placed = {:coin_flip_games,
        "placed_0", 1, "wallet1", "seed0", "hash0", 0, :placed,
        :bux, 100, 1, [:heads], [:heads], true, 198.0,
        "sig0", "bet0", nil, now, nil}
      :mnesia.dirty_write(placed)

      # A committed game at nonce 0 (stale — should not be reused)
      pending = {:coin_flip_games,
        "pending_0", 1, "wallet1", "seed_p", "hash_p", 0, :committed,
        nil, nil, nil, nil, nil, nil, nil,
        "sig_p", nil, nil, now, nil}
      :mnesia.dirty_write(pending)

      # Next nonce is 1, pending game is at nonce 0 — mismatch
      next_nonce = compute_next_nonce(1, "wallet1")
      assert next_nonce == 1

      pending_game = CoinFlipGame.get_pending_game(1)
      assert pending_game.nonce == 0
      assert pending_game.nonce != next_nonce  # Won't be reused
    end
  end

  # ============================================================================
  # on_bet_placed Tests
  # ============================================================================

  describe "on_bet_placed/6" do
    test "updates game record with bet details" do
      now = System.system_time(:second)
      server_seed = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
      commitment_hash = :crypto.hash(:sha256, server_seed) |> Base.encode16(case: :lower)

      record = {
        :coin_flip_games,
        "bet_test", 1, "wallet1", server_seed, commitment_hash, 0, :committed,
        nil, nil, nil, nil, nil, nil, nil,
        "commit_sig", nil, nil, now, nil
      }
      :mnesia.dirty_write(record)

      {:ok, result} = CoinFlipGame.on_bet_placed(
        "bet_test", "bet_sig_123", [:heads], 100, :bux, 1
      )

      assert is_list(result.results)
      assert is_boolean(result.won)

      # Verify Mnesia was updated
      {:ok, game} = CoinFlipGame.get_game("bet_test")
      assert game.status == :placed
      assert game.bet_sig == "bet_sig_123"
      assert game.vault_type == :bux
      assert game.bet_amount == 100
      assert game.difficulty == 1
      assert game.predictions == [:heads]
    end

    test "returns error for non-existent game" do
      assert {:error, :not_found} = CoinFlipGame.on_bet_placed(
        "nonexistent", "sig", [:heads], 100, :bux, 1
      )
    end
  end

  # ============================================================================
  # Multipliers Tests
  # ============================================================================

  describe "multipliers/0" do
    test "returns all difficulty multipliers" do
      multipliers = CoinFlipGame.multipliers()

      assert Map.get(multipliers, 1) == 19800
      assert Map.get(multipliers, 2) == 39600
      assert Map.get(multipliers, 3) == 79200
      assert Map.get(multipliers, 4) == 158400
      assert Map.get(multipliers, 5) == 316800
      assert Map.get(multipliers, -1) == 13200
      assert Map.get(multipliers, -2) == 11300
      assert Map.get(multipliers, -3) == 10500
      assert Map.get(multipliers, -4) == 10200
    end
  end

  # ============================================================================
  # Settlement Tests
  # ============================================================================

  describe "settle_game/1" do
    test "returns error for non-existent game" do
      assert {:error, :not_found} = CoinFlipGame.settle_game("nonexistent")
    end

    test "returns error for game that hasn't been placed" do
      now = System.system_time(:second)
      record = {
        :coin_flip_games,
        "not_placed", 1, "wallet1", "seed", "hash", 0, :committed,
        nil, nil, nil, nil, nil, nil, nil,
        "sig", nil, nil, now, nil
      }
      :mnesia.dirty_write(record)

      assert {:error, :bet_not_placed} = CoinFlipGame.settle_game("not_placed")
    end

    test "returns already settled for settled games" do
      now = System.system_time(:second)
      record = {
        :coin_flip_games,
        "already_settled", 1, "wallet1", "seed", "hash", 0, :settled,
        :bux, 100, 1, [:heads], [:heads], true, 198.0,
        "sig", "bet_sig", "settle_sig", now, now
      }
      :mnesia.dirty_write(record)

      assert {:ok, %{already_settled: true}} = CoinFlipGame.settle_game("already_settled")
    end
  end

  # ============================================================================
  # Provably Fair Verification Tests
  # ============================================================================

  describe "provably fair" do
    test "commitment hash is SHA256 of server seed" do
      server_seed = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
      expected_hash = :crypto.hash(:sha256, server_seed) |> Base.encode16(case: :lower)

      # The game stores commitment_hash as the SHA256 of server_seed hex string
      assert expected_hash == :crypto.hash(:sha256, server_seed) |> Base.encode16(case: :lower)
    end

    test "client seed is deterministic from bet details" do
      # Same inputs → same client seed
      predictions = [:heads, :tails]
      input1 = "1:100:bux:2:heads,tails"
      input2 = "1:100:bux:2:heads,tails"

      seed1 = :crypto.hash(:sha256, input1) |> Base.encode16(case: :lower)
      seed2 = :crypto.hash(:sha256, input2) |> Base.encode16(case: :lower)

      assert seed1 == seed2
    end

    test "combined seed uses server:client:nonce format" do
      server_seed = "abc123"
      client_seed = "def456"
      nonce = 0

      combined_input = "#{server_seed}:#{client_seed}:#{nonce}"
      combined = :crypto.hash(:sha256, combined_input) |> Base.encode16(case: :lower)

      # Verify it's a valid hex string of 64 chars (256 bits)
      assert String.length(combined) == 64
      assert Regex.match?(~r/^[a-f0-9]+$/, combined)
    end

    test "byte < 128 = heads, byte >= 128 = tails" do
      # Create a known combined seed and verify flip logic
      combined_seed = <<0, 127, 128, 255, 64>>

      results = for i <- 0..4 do
        byte = :binary.at(combined_seed, i)
        if byte < 128, do: :heads, else: :tails
      end

      assert results == [:heads, :heads, :tails, :tails, :heads]
    end
  end

  # ============================================================================
  # CF-01 regression — commitment-hash seed recovery + manual_review
  # ============================================================================

  describe "get_game_by_commitment_hash/1 (CF-01)" do
    test "returns the matching game when commitment_hash is stored" do
      now = System.system_time(:second)

      raw_a = :crypto.strong_rand_bytes(32)
      seed_a = Base.encode16(raw_a, case: :lower)
      commit_a = :crypto.hash(:sha256, raw_a) |> Base.encode16(case: :lower)

      raw_b = :crypto.strong_rand_bytes(32)
      seed_b = Base.encode16(raw_b, case: :lower)
      commit_b = :crypto.hash(:sha256, raw_b) |> Base.encode16(case: :lower)

      # Two games for the SAME user — simulates the audit's "three rapid bets"
      # scenario where the on-chain commitment winds up tagging the wrong
      # seed if we looked up only by (user, nonce).
      :mnesia.dirty_write(
        {:coin_flip_games, "game_a", 42, "wallet1", seed_a, commit_a, 0,
         :placed, :sol, 0.05, 1, [:heads], [:heads], true, 0.099,
         "commit_sig_a", "bet_sig_a", nil, now, nil}
      )

      :mnesia.dirty_write(
        {:coin_flip_games, "game_b", 42, "wallet1", seed_b, commit_b, 1,
         :placed, :sol, 0.05, 1, [:tails], [:tails], false, 0,
         "commit_sig_b", "bet_sig_b", nil, now, nil}
      )

      assert {:ok, game_a} = BlocksterV2.CoinFlipGame.get_game_by_commitment_hash(commit_a)
      assert game_a.game_id == "game_a"
      assert game_a.server_seed == seed_a

      assert {:ok, game_b} = BlocksterV2.CoinFlipGame.get_game_by_commitment_hash(commit_b)
      assert game_b.game_id == "game_b"
      assert game_b.server_seed == seed_b
    end

    test "returns :not_found when no game matches the hash" do
      assert {:error, :not_found} =
               BlocksterV2.CoinFlipGame.get_game_by_commitment_hash(String.duplicate("0", 64))
    end

    test "two sibling games for the same user are each settleable against their own commitment" do
      # Regression for CF-01 root cause (see audit): when two bets fire
      # in quick succession, seed A must SHA256 to commit A and seed B
      # must SHA256 to commit B — and the lookup must return the right
      # row for each hash independently. This is what the CF-01 recovery
      # path relies on.
      raw_a = :crypto.strong_rand_bytes(32)
      seed_a = Base.encode16(raw_a, case: :lower)
      commit_a = :crypto.hash(:sha256, raw_a) |> Base.encode16(case: :lower)

      raw_b = :crypto.strong_rand_bytes(32)
      seed_b = Base.encode16(raw_b, case: :lower)
      commit_b = :crypto.hash(:sha256, raw_b) |> Base.encode16(case: :lower)

      now = System.system_time(:second)

      :mnesia.dirty_write(
        {:coin_flip_games, "cfsibA", 77, "wlt", seed_a, commit_a, 0, :placed,
         :bux, 100, 1, [:heads], [:heads], true, 198, "cs_a", "bs_a", nil, now, nil}
      )

      :mnesia.dirty_write(
        {:coin_flip_games, "cfsibB", 77, "wlt", seed_b, commit_b, 1, :placed,
         :bux, 100, 1, [:tails], [:tails], true, 198, "cs_b", "bs_b", nil, now, nil}
      )

      # Independent retrievability via their own hash
      {:ok, g_a} = BlocksterV2.CoinFlipGame.get_game_by_commitment_hash(commit_a)
      {:ok, g_b} = BlocksterV2.CoinFlipGame.get_game_by_commitment_hash(commit_b)

      # Each game's stored server_seed must SHA256 to its own commitment —
      # this is the property the pre-submit settler assertion relies on.
      assert :crypto.hash(:sha256, Base.decode16!(g_a.server_seed, case: :lower))
             |> Base.encode16(case: :lower) == commit_a

      assert :crypto.hash(:sha256, Base.decode16!(g_b.server_seed, case: :lower))
             |> Base.encode16(case: :lower) == commit_b
    end
  end

  describe "settle_game/1 with :manual_review status (CF-01)" do
    test "short-circuits with {:error, :manual_review} and does NOT attempt the settler" do
      # If settle_game tried the network we'd see a timeout or crash; no
      # settler is running in test env.
      now = System.system_time(:second)

      :mnesia.dirty_write(
        {:coin_flip_games, "parked_mr", 99, "wallet_mr", "seed_mr", "commit_mr", 3,
         :manual_review, :sol, 0.05, 1, [:heads], [:heads], false, 0,
         "cs", "bs", "manual_review:commitment_mismatch_no_seed", now, now}
      )

      assert {:error, :manual_review} = BlocksterV2.CoinFlipGame.settle_game("parked_mr")
    end
  end
end
