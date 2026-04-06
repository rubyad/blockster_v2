defmodule BlocksterV2.CoinFlipConcurrentTest do
  use BlocksterV2.DataCase, async: false

  alias BlocksterV2.CoinFlipGame

  # ============================================================================
  # Integration tests for concurrent bet scenarios
  # Verifies that removing has_active_order allows fast consecutive bets
  # ============================================================================

  setup do
    :mnesia.start()

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

  # Helper to compute next nonce (mirrors get_or_init_game logic)
  defp compute_next_nonce(user_id, wallet) do
    case :mnesia.dirty_match_object(
      {:coin_flip_games, :_, user_id, wallet, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}
    ) do
      [] -> 0
      games ->
        placed_games = Enum.filter(games, fn g -> elem(g, 7) in [:placed, :settled] end)
        case placed_games do
          [] -> 0
          _ -> placed_games |> Enum.map(fn g -> elem(g, 6) end) |> Enum.max() |> Kernel.+(1)
        end
    end
  end

  # Helper to insert a game record
  defp insert_game(game_id, user_id, wallet, nonce, status, opts \\ []) do
    now = Keyword.get(opts, :created_at, System.system_time(:second))
    server_seed = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
    commitment_hash = :crypto.hash(:sha256, server_seed) |> Base.encode16(case: :lower)

    vault_type = if status in [:placed, :settled], do: :bux, else: nil
    bet_amount = if status in [:placed, :settled], do: 100, else: nil
    difficulty = if status in [:placed, :settled], do: 1, else: nil
    predictions = if status in [:placed, :settled], do: [:heads], else: nil
    results = if status in [:placed, :settled], do: [:heads], else: nil
    won = if status in [:placed, :settled], do: true, else: nil
    payout = if status in [:placed, :settled], do: 198.0, else: nil
    bet_sig = if status in [:placed, :settled], do: "bet_#{game_id}", else: nil
    settlement_sig = if status == :settled, do: "settle_#{game_id}", else: nil
    settled_at = if status == :settled, do: now, else: nil

    record = {:coin_flip_games,
      game_id, user_id, wallet, server_seed, commitment_hash,
      nonce, status, vault_type, bet_amount, difficulty,
      predictions, results, won, payout,
      "commit_#{game_id}", bet_sig, settlement_sig, now, settled_at}
    :mnesia.dirty_write(record)
    record
  end

  describe "nonce advances correctly across multiple placed bets" do
    test "sequential nonce 0→1→2→3→4" do
      for n <- 0..4 do
        assert n == compute_next_nonce(1, "wallet1")
        insert_game("game_#{n}", 1, "wallet1", n, :placed)
      end
      assert 5 == compute_next_nonce(1, "wallet1")
    end
  end

  describe "settling bets out of order" do
    test "doesn't break nonce calculation" do
      now = System.system_time(:second)

      # Place 3 bets
      insert_game("g0", 1, "wallet1", 0, :placed, created_at: now)
      insert_game("g1", 1, "wallet1", 1, :placed, created_at: now)
      insert_game("g2", 1, "wallet1", 2, :placed, created_at: now)

      assert 3 == compute_next_nonce(1, "wallet1")

      # Settle nonce 2 first (out of order)
      [{:coin_flip_games, "g2", _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _} = rec] =
        :mnesia.dirty_read(:coin_flip_games, "g2")
      :mnesia.dirty_write(put_elem(put_elem(rec, 7, :settled), 17, "settle_g2"))

      # Nonce should still be 3
      assert 3 == compute_next_nonce(1, "wallet1")

      # Settle nonce 0
      [{:coin_flip_games, "g0", _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _} = rec0] =
        :mnesia.dirty_read(:coin_flip_games, "g0")
      :mnesia.dirty_write(put_elem(put_elem(rec0, 7, :settled), 17, "settle_g0"))

      # Still 3
      assert 3 == compute_next_nonce(1, "wallet1")

      # Settle nonce 1
      [{:coin_flip_games, "g1", _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _} = rec1] =
        :mnesia.dirty_read(:coin_flip_games, "g1")
      :mnesia.dirty_write(put_elem(put_elem(rec1, 7, :settled), 17, "settle_g1"))

      # Still 3 — all settled, but max nonce is still 2
      assert 3 == compute_next_nonce(1, "wallet1")
    end
  end

  describe "unsettled bet doesn't block next bet" do
    test "can compute next nonce with unsettled predecessor" do
      insert_game("g0", 1, "wallet1", 0, :placed)
      # Nonce 0 is placed but not settled
      # Next nonce should be 1 (not blocked)
      assert 1 == compute_next_nonce(1, "wallet1")
    end

    test "can compute next nonce with multiple unsettled bets" do
      insert_game("g0", 1, "wallet1", 0, :placed)
      insert_game("g1", 1, "wallet1", 1, :placed)
      insert_game("g2", 1, "wallet1", 2, :placed)

      assert 3 == compute_next_nonce(1, "wallet1")
    end
  end

  describe "failed settlement doesn't break game flow" do
    test "can place new bet after failed settlement" do
      # Bet at nonce 0 placed but settlement failed (still :placed status)
      insert_game("failed_bet", 1, "wallet1", 0, :placed)

      # User should be able to start a new game at nonce 1
      assert 1 == compute_next_nonce(1, "wallet1")
    end

    test "background settler can still find failed bet" do
      old_time = System.system_time(:second) - 300
      insert_game("failed_bet", 1, "wallet1", 0, :placed, created_at: old_time)

      # New bet at nonce 1
      insert_game("new_bet", 1, "wallet1", 1, :placed)

      # Background settler finds the old bet
      cutoff = System.system_time(:second) - 120
      unsettled = :mnesia.dirty_match_object(
        {:coin_flip_games, :_, :_, :_, :_, :_, :_, :placed, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}
      )
      |> Enum.filter(fn r -> elem(r, 18) < cutoff end)

      assert length(unsettled) == 1
      assert elem(hd(unsettled), 1) == "failed_bet"
    end
  end

  describe "on_bet_placed with concurrent games" do
    test "each bet gets its own result based on its server seed" do
      now = System.system_time(:second)
      seed0 = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
      hash0 = :crypto.hash(:sha256, seed0) |> Base.encode16(case: :lower)
      seed1 = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
      hash1 = :crypto.hash(:sha256, seed1) |> Base.encode16(case: :lower)

      # Two committed games at different nonces
      rec0 = {:coin_flip_games,
        "concurrent_0", 1, "wallet1", seed0, hash0, 0, :committed,
        nil, nil, nil, nil, nil, nil, nil,
        "commit0", nil, nil, now, nil}
      rec1 = {:coin_flip_games,
        "concurrent_1", 1, "wallet1", seed1, hash1, 1, :committed,
        nil, nil, nil, nil, nil, nil, nil,
        "commit1", nil, nil, now, nil}
      :mnesia.dirty_write(rec0)
      :mnesia.dirty_write(rec1)

      # Place both bets
      {:ok, result0} = CoinFlipGame.on_bet_placed("concurrent_0", "bet0", [:heads], 100, :bux, 1)
      {:ok, result1} = CoinFlipGame.on_bet_placed("concurrent_1", "bet1", [:heads], 100, :bux, 1)

      # Both should have valid results
      assert is_list(result0.results)
      assert is_list(result1.results)

      # Both games should be :placed
      {:ok, game0} = CoinFlipGame.get_game("concurrent_0")
      {:ok, game1} = CoinFlipGame.get_game("concurrent_1")
      assert game0.status == :placed
      assert game1.status == :placed
      assert game0.nonce == 0
      assert game1.nonce == 1
    end
  end

  describe "settle_game with concurrent placed bets" do
    test "settling one bet doesn't affect another" do
      now = System.system_time(:second)
      seed0 = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
      hash0 = :crypto.hash(:sha256, seed0) |> Base.encode16(case: :lower)
      seed1 = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
      hash1 = :crypto.hash(:sha256, seed1) |> Base.encode16(case: :lower)

      # Two placed games
      rec0 = {:coin_flip_games,
        "settle_test_0", 1, "wallet1", seed0, hash0, 0, :placed,
        :bux, 100, 1, [:heads], [:heads], true, 198.0,
        "commit0", "bet0", nil, now, nil}
      rec1 = {:coin_flip_games,
        "settle_test_1", 1, "wallet1", seed1, hash1, 1, :placed,
        :bux, 100, 1, [:tails], [:tails], false, 0,
        "commit1", "bet1", nil, now, nil}
      :mnesia.dirty_write(rec0)
      :mnesia.dirty_write(rec1)

      # Manually mark game 0 as settled (simulating successful settlement)
      :mnesia.dirty_write(put_elem(put_elem(rec0, 7, :settled), 17, "settle_sig_0"))

      # Game 1 should still be :placed
      {:ok, game1} = CoinFlipGame.get_game("settle_test_1")
      assert game1.status == :placed

      # Game 0 should be :settled
      {:ok, game0} = CoinFlipGame.get_game("settle_test_0")
      assert game0.status == :settled

      # Next nonce should be 2 (max of 0, 1 = 1, +1 = 2)
      assert 2 == compute_next_nonce(1, "wallet1")
    end
  end
end
