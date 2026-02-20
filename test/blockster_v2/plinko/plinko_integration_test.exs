defmodule BlocksterV2.Plinko.PlinkoIntegrationTest do
  use ExUnit.Case

  alias BlocksterV2.PlinkoGame

  @test_user_id 999
  @test_user_id_2 998
  @test_wallet "0xTEST_WALLET"
  @test_wallet_2 "0xTEST_WALLET_2"
  @wei 1_000_000_000_000_000_000

  setup do
    ensure_plinko_games_table()
    ensure_user_betting_stats_table()
    :mnesia.clear_table(:plinko_games)
    :mnesia.clear_table(:user_betting_stats)
    :ok
  end

  # ============ 1. Full Game Lifecycle ============

  describe "full game lifecycle" do
    test "committed → placed transition preserves server_seed and commitment_hash" do
      game_id = write_committed_game(@test_user_id, @test_wallet, 0)
      {:ok, committed} = PlinkoGame.get_game(game_id)

      {:ok, _result} = PlinkoGame.on_bet_placed(game_id, "0xBET", "0xTX", 100, "BUX", 0)
      {:ok, placed} = PlinkoGame.get_game(game_id)

      assert placed.server_seed == committed.server_seed
      assert placed.commitment_hash == committed.commitment_hash
    end

    test "placed → settled transition sets settlement_tx and settled_at" do
      game_id = write_placed_game(@test_user_id, @test_wallet, 0)
      {:ok, game} = PlinkoGame.get_game(game_id)

      PlinkoGame.mark_game_settled(game_id, game, "0xSETTLE_HASH")
      {:ok, settled} = PlinkoGame.get_game(game_id)

      assert settled.settlement_tx == "0xSETTLE_HASH"
      assert settled.settled_at != nil
      assert is_integer(settled.settled_at)
    end

    test "full lifecycle preserves user_id and wallet_address across all states" do
      game_id = write_committed_game(@test_user_id, @test_wallet, 0)
      {:ok, committed} = PlinkoGame.get_game(game_id)
      assert committed.user_id == @test_user_id
      assert committed.wallet_address == @test_wallet

      {:ok, _result} = PlinkoGame.on_bet_placed(game_id, "0xBET", "0xTX", 100, "BUX", 0)
      {:ok, placed} = PlinkoGame.get_game(game_id)
      assert placed.user_id == @test_user_id
      assert placed.wallet_address == @test_wallet

      PlinkoGame.mark_game_settled(game_id, placed, "0xSETTLE")
      {:ok, settled} = PlinkoGame.get_game(game_id)
      assert settled.user_id == @test_user_id
      assert settled.wallet_address == @test_wallet
    end

    test "result values (ball_path, payout, won) survive full lifecycle" do
      game_id = write_committed_game(@test_user_id, @test_wallet, 0)
      {:ok, result} = PlinkoGame.on_bet_placed(game_id, "0xBET", "0xTX", 100, "BUX", 0)
      {:ok, placed} = PlinkoGame.get_game(game_id)

      PlinkoGame.mark_game_settled(game_id, placed, "0xSETTLE")
      {:ok, settled} = PlinkoGame.get_game(game_id)

      assert settled.ball_path == result.ball_path
      assert settled.payout == result.payout
      assert settled.won == result.won
    end

    test "nonce preserved through entire lifecycle" do
      game_id = write_committed_game(@test_user_id, @test_wallet, 5)
      {:ok, committed} = PlinkoGame.get_game(game_id)
      assert committed.nonce == 5

      {:ok, _result} = PlinkoGame.on_bet_placed(game_id, "0xBET", "0xTX", 100, "BUX", 0)
      {:ok, placed} = PlinkoGame.get_game(game_id)
      assert placed.nonce == 5

      PlinkoGame.mark_game_settled(game_id, placed, "0xSETTLE")
      {:ok, settled} = PlinkoGame.get_game(game_id)
      assert settled.nonce == 5
    end

    test "created_at updates on bet placement, settled_at set on settlement" do
      old_time = System.system_time(:second) - 300
      game_id = write_committed_game(@test_user_id, @test_wallet, 0, old_time)
      {:ok, committed} = PlinkoGame.get_game(game_id)
      assert committed.created_at == old_time

      {:ok, _result} = PlinkoGame.on_bet_placed(game_id, "0xBET", "0xTX", 100, "BUX", 0)
      {:ok, placed} = PlinkoGame.get_game(game_id)
      # on_bet_placed overwrites created_at with now
      assert placed.created_at > old_time
      assert placed.settled_at == nil

      PlinkoGame.mark_game_settled(game_id, placed, "0xSETTLE")
      {:ok, settled} = PlinkoGame.get_game(game_id)
      assert settled.settled_at != nil
      assert settled.settled_at >= placed.created_at
    end

    test "Mnesia tuple has 25 elements at every lifecycle stage" do
      game_id = write_committed_game(@test_user_id, @test_wallet, 0)
      [committed_record] = :mnesia.dirty_read({:plinko_games, game_id})
      assert tuple_size(committed_record) == 25

      {:ok, _result} = PlinkoGame.on_bet_placed(game_id, "0xBET", "0xTX", 100, "BUX", 0)
      [placed_record] = :mnesia.dirty_read({:plinko_games, game_id})
      assert tuple_size(placed_record) == 25

      {:ok, game} = PlinkoGame.get_game(game_id)
      PlinkoGame.mark_game_settled(game_id, game, "0xSETTLE")
      [settled_record] = :mnesia.dirty_read({:plinko_games, game_id})
      assert tuple_size(settled_record) == 25
    end

    test "multiple games for same user progress independently" do
      game_id_1 = write_committed_game(@test_user_id, @test_wallet, 0)
      game_id_2 = write_committed_game(@test_user_id, @test_wallet, 1)

      # Place only game 1
      {:ok, _result} = PlinkoGame.on_bet_placed(game_id_1, "0xBET1", "0xTX1", 100, "BUX", 0)

      {:ok, game1} = PlinkoGame.get_game(game_id_1)
      {:ok, game2} = PlinkoGame.get_game(game_id_2)

      assert game1.status == :placed
      assert game2.status == :committed
    end
  end

  # ============ 2. Multi-Game Sequencing ============

  describe "multi-game sequencing" do
    test "sequential nonces stored and retrievable" do
      ids = for n <- 0..4, do: write_committed_game(@test_user_id, @test_wallet, n)

      for {id, expected_nonce} <- Enum.zip(ids, 0..4) do
        {:ok, game} = PlinkoGame.get_game(id)
        assert game.nonce == expected_nonce
      end
    end

    test "get_pending_game returns committed game with highest created_at" do
      _older = write_committed_game(@test_user_id, @test_wallet, 0, System.system_time(:second) - 100)
      newer = write_committed_game(@test_user_id, @test_wallet, 1, System.system_time(:second))

      pending = PlinkoGame.get_pending_game(@test_user_id)
      assert pending.game_id == newer
    end

    test "get_pending_game returns nil when all games placed or settled" do
      write_placed_game(@test_user_id, @test_wallet, 0)
      write_settled_game(@test_user_id, @test_wallet, 1)

      assert PlinkoGame.get_pending_game(@test_user_id) == nil
    end

    test "load_recent_games returns only settled, newest first" do
      write_committed_game(@test_user_id, @test_wallet, 0)
      write_placed_game(@test_user_id, @test_wallet, 1)
      write_settled_game(@test_user_id, @test_wallet, 2, System.system_time(:second) - 100)
      write_settled_game(@test_user_id, @test_wallet, 3, System.system_time(:second))

      games = PlinkoGame.load_recent_games(@test_user_id)
      assert length(games) == 2
      assert Enum.all?(games, &(&1.status == :settled))

      timestamps = Enum.map(games, & &1.created_at)
      assert timestamps == Enum.sort(timestamps, :desc)
    end

    test "load_recent_games pagination with multi-user isolation" do
      for n <- 0..4 do
        write_settled_game(@test_user_id, @test_wallet, n, System.system_time(:second) - (4 - n) * 10)
      end

      write_settled_game(@test_user_id_2, @test_wallet_2, 0)

      # Limit
      games = PlinkoGame.load_recent_games(@test_user_id, limit: 2)
      assert length(games) == 2

      # Offset
      all_games = PlinkoGame.load_recent_games(@test_user_id)
      offset_games = PlinkoGame.load_recent_games(@test_user_id, offset: 2)
      assert length(offset_games) == 3
      assert hd(offset_games).game_id == Enum.at(all_games, 2).game_id

      # User isolation
      user2_games = PlinkoGame.load_recent_games(@test_user_id_2)
      assert length(user2_games) == 1
    end

    test "concurrent games for different users don't interfere" do
      id1 = write_committed_game(@test_user_id, @test_wallet, 0)
      id2 = write_committed_game(@test_user_id_2, @test_wallet_2, 0)

      {:ok, _} = PlinkoGame.on_bet_placed(id1, "0xBET1", "0xTX1", 100, "BUX", 0)
      {:ok, _} = PlinkoGame.on_bet_placed(id2, "0xBET2", "0xTX2", 200, "BUX", 3)

      {:ok, game1} = PlinkoGame.get_game(id1)
      {:ok, game2} = PlinkoGame.get_game(id2)

      assert game1.user_id == @test_user_id
      assert game2.user_id == @test_user_id_2
      assert game1.bet_amount == 100
      assert game2.bet_amount == 200
      assert game1.config_index == 0
      assert game2.config_index == 3
    end
  end

  # ============ 3. Provably Fair Verification ============

  describe "provably fair verification" do
    test "commitment_hash equals 0x + hex(SHA256(server_seed))" do
      server_seed = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
      game_id = write_committed_game_with_seed(@test_user_id, @test_wallet, 0, server_seed)

      {:ok, game} = PlinkoGame.get_game(game_id)
      expected_hash = "0x" <> (:crypto.hash(:sha256, server_seed) |> Base.encode16(case: :lower))

      assert game.commitment_hash == expected_hash
    end

    test "deterministic: same inputs produce same ball_path and payout" do
      server_seed = "deadbeef" <> String.duplicate("0", 56)

      id1 = write_committed_game_with_seed(@test_user_id, @test_wallet, 0, server_seed)
      id2 = write_committed_game_with_seed(@test_user_id, @test_wallet, 0, server_seed)

      {:ok, r1} = PlinkoGame.on_bet_placed(id1, "0xBET1", "0xTX1", 100, "BUX", 0)
      {:ok, r2} = PlinkoGame.on_bet_placed(id2, "0xBET2", "0xTX2", 100, "BUX", 0)

      assert r1.ball_path == r2.ball_path
      assert r1.payout == r2.payout
      assert r1.landing_position == r2.landing_position
    end

    test "different nonce produces different result with same server_seed" do
      server_seed = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)

      id1 = write_committed_game_with_seed(@test_user_id, @test_wallet, 0, server_seed)
      id2 = write_committed_game_with_seed(@test_user_id, @test_wallet, 1, server_seed)

      {:ok, r1} = PlinkoGame.on_bet_placed(id1, "0xBET1", "0xTX1", 100, "BUX", 0)
      {:ok, r2} = PlinkoGame.on_bet_placed(id2, "0xBET2", "0xTX2", 100, "BUX", 0)

      # Extremely unlikely to be equal with different nonces
      assert r1.ball_path != r2.ball_path || r1.landing_position != r2.landing_position
    end

    test "on_bet_placed result matches independent calculate_result call" do
      game_id = write_committed_game(@test_user_id, @test_wallet, 0)
      {:ok, game} = PlinkoGame.get_game(game_id)

      {:ok, placed_result} = PlinkoGame.on_bet_placed(game_id, "0xBET", "0xTX", 100, "BUX", 0)
      {:ok, calc_result} = PlinkoGame.calculate_result(game.server_seed, game.nonce, 0, 100, "BUX", @test_user_id)

      assert placed_result.ball_path == calc_result.ball_path
      assert placed_result.landing_position == calc_result.landing_position
      assert placed_result.payout == calc_result.payout
      assert placed_result.payout_bp == calc_result.payout_bp
    end

    test "calculate_game_result reads from Mnesia correctly" do
      game_id = write_committed_game(@test_user_id, @test_wallet, 0)
      {:ok, game} = PlinkoGame.get_game(game_id)

      {:ok, direct_result} = PlinkoGame.calculate_result(game.server_seed, game.nonce, 0, 100, "BUX", @test_user_id)
      {:ok, game_result} = PlinkoGame.calculate_game_result(game_id, 0, 100, "BUX", @test_user_id)

      assert direct_result.ball_path == game_result.ball_path
      assert direct_result.payout == game_result.payout
    end

    test "ball path: byte < 128 = :left, >= 128 = :right, landing = count(:right)" do
      server_seed = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
      nonce = 0
      config_index = 0
      {rows, _risk} = PlinkoGame.configs()[config_index]

      # Reproduce the exact hash calculation
      input = "#{@test_user_id}:100:BUX:#{config_index}"
      client_seed = :crypto.hash(:sha256, input) |> Base.encode16(case: :lower)
      combined = :crypto.hash(:sha256, "#{server_seed}:#{client_seed}:#{nonce}")

      expected_path =
        for i <- 0..(rows - 1) do
          byte = :binary.at(combined, i)
          if byte < 128, do: :left, else: :right
        end

      expected_landing = Enum.count(expected_path, &(&1 == :right))

      id = write_committed_game_with_seed(@test_user_id, @test_wallet, nonce, server_seed)
      {:ok, result} = PlinkoGame.on_bet_placed(id, "0xBET", "0xTX", 100, "BUX", config_index)

      assert result.ball_path == expected_path
      assert result.landing_position == expected_landing
    end

    test "full verification chain: seed → commitment → path → landing → payout" do
      server_seed = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
      config_index = 2
      bet_amount = 500
      nonce = 3
      {rows, _risk} = PlinkoGame.configs()[config_index]

      # 1. Commitment
      commitment_hash = "0x" <> (:crypto.hash(:sha256, server_seed) |> Base.encode16(case: :lower))

      # 2. Write and place
      id = write_committed_game_with_seed(@test_user_id, @test_wallet, nonce, server_seed)
      {:ok, game} = PlinkoGame.get_game(id)
      assert game.commitment_hash == commitment_hash

      {:ok, result} = PlinkoGame.on_bet_placed(id, "0xBET", "0xTX", bet_amount, "BUX", config_index)

      # 3. Verify path length matches rows
      assert length(result.ball_path) == rows

      # 4. Verify landing position
      assert result.landing_position == Enum.count(result.ball_path, &(&1 == :right))

      # 5. Verify payout from table
      payout_table = PlinkoGame.payout_tables()[config_index]
      expected_bp = Enum.at(payout_table, result.landing_position)
      assert result.payout_bp == expected_bp
      assert result.payout == div(bet_amount * expected_bp, 10000)
    end
  end

  # ============ 4. settle_game Error Handling ============

  describe "settle_game error handling" do
    test "returns error when BuxMinter not configured for placed game" do
      game_id = write_placed_game(@test_user_id, @test_wallet, 0)

      result = PlinkoGame.settle_game(game_id)
      assert {:error, _reason} = result
    end

    test "returns {:error, :bet_not_placed} for committed game with no bet_id" do
      game_id = write_committed_game(@test_user_id, @test_wallet, 0)

      assert {:error, :bet_not_placed} = PlinkoGame.settle_game(game_id)
    end

    test "returns {:error, :not_found} for nonexistent game" do
      assert {:error, :not_found} = PlinkoGame.settle_game("nonexistent_game_id")
    end

    test "returns {:ok, already_settled: true} for settled game" do
      game_id = write_settled_game(@test_user_id, @test_wallet, 0)

      {:ok, result} = PlinkoGame.settle_game(game_id)
      assert result.already_settled == true
      assert result.tx_hash == "0xSETTLE_TX"
    end

    test "game status remains :placed after settle failure" do
      game_id = write_placed_game(@test_user_id, @test_wallet, 0)

      {:error, _reason} = PlinkoGame.settle_game(game_id)

      {:ok, game} = PlinkoGame.get_game(game_id)
      assert game.status == :placed
    end
  end

  # ============ 5. user_betting_stats Table ============

  describe "user_betting_stats table" do
    test "stats record has 21 elements (tuple size)" do
      write_user_betting_stats(@test_user_id, @test_wallet)
      [record] = :mnesia.dirty_read(:user_betting_stats, @test_user_id)
      assert tuple_size(record) == 21
    end

    test "zeroed stats record matches expected format" do
      write_user_betting_stats(@test_user_id, @test_wallet)
      stats = read_user_betting_stats(@test_user_id)

      assert stats.user_id == @test_user_id
      assert stats.wallet_address == @test_wallet
      assert stats.bux_total_bets == 0
      assert stats.bux_wins == 0
      assert stats.bux_losses == 0
      assert stats.bux_total_wagered == 0
      assert stats.bux_total_winnings == 0
      assert stats.bux_total_losses == 0
      assert stats.bux_net_pnl == 0
      assert stats.rogue_total_bets == 0
      assert stats.rogue_wins == 0
      assert stats.rogue_losses == 0
      assert stats.rogue_total_wagered == 0
      assert stats.rogue_total_winnings == 0
      assert stats.rogue_total_losses == 0
      assert stats.rogue_net_pnl == 0
      assert stats.onchain_stats_cache == nil
    end

    test "BUX win updates correct fields (bets+1, wins+1, wagered, winnings, pnl)" do
      write_user_betting_stats(@test_user_id, @test_wallet)
      bet_amount = 100
      payout = 560  # config 0 landing 0 = 56000bp = 5.6x
      apply_stats_update(@test_user_id, "BUX", bet_amount, true, payout)

      stats = read_user_betting_stats(@test_user_id)
      assert stats.bux_total_bets == 1
      assert stats.bux_wins == 1
      assert stats.bux_losses == 0
      assert stats.bux_total_wagered == bet_amount * @wei
      assert stats.bux_total_winnings == (payout - bet_amount) * @wei
      assert stats.bux_total_losses == 0
      assert stats.bux_net_pnl == (payout - bet_amount) * @wei
    end

    test "BUX loss updates correct fields (bets+1, losses+1, wagered, losses_amt, pnl)" do
      write_user_betting_stats(@test_user_id, @test_wallet)
      bet_amount = 100
      payout = 50  # lost half
      apply_stats_update(@test_user_id, "BUX", bet_amount, false, payout)

      stats = read_user_betting_stats(@test_user_id)
      assert stats.bux_total_bets == 1
      assert stats.bux_wins == 0
      assert stats.bux_losses == 1
      assert stats.bux_total_wagered == bet_amount * @wei
      assert stats.bux_total_winnings == 0
      assert stats.bux_total_losses == bet_amount * @wei
      assert stats.bux_net_pnl == -(bet_amount * @wei)
    end

    test "ROGUE bet updates ROGUE fields only, BUX fields stay zero" do
      write_user_betting_stats(@test_user_id, @test_wallet)
      apply_stats_update(@test_user_id, "ROGUE", 200, true, 600)

      stats = read_user_betting_stats(@test_user_id)
      # BUX fields untouched
      assert stats.bux_total_bets == 0
      assert stats.bux_total_wagered == 0
      # ROGUE fields updated
      assert stats.rogue_total_bets == 1
      assert stats.rogue_wins == 1
      assert stats.rogue_total_wagered == 200 * @wei
      assert stats.rogue_total_winnings == (600 - 200) * @wei
      assert stats.rogue_net_pnl == (600 - 200) * @wei
    end

    test "multiple bets accumulate correctly" do
      write_user_betting_stats(@test_user_id, @test_wallet)

      # Bet 1: BUX win
      apply_stats_update(@test_user_id, "BUX", 100, true, 300)
      # Bet 2: BUX loss
      apply_stats_update(@test_user_id, "BUX", 100, false, 50)
      # Bet 3: ROGUE win
      apply_stats_update(@test_user_id, "ROGUE", 500, true, 1000)

      stats = read_user_betting_stats(@test_user_id)
      assert stats.bux_total_bets == 2
      assert stats.bux_wins == 1
      assert stats.bux_losses == 1
      assert stats.bux_total_wagered == 200 * @wei
      assert stats.bux_total_winnings == 200 * @wei  # (300 - 100) from bet 1
      assert stats.bux_total_losses == 100 * @wei     # loss from bet 2
      assert stats.bux_net_pnl == (200 - 100) * @wei  # +200 from win, -100 from loss

      assert stats.rogue_total_bets == 1
      assert stats.rogue_wins == 1
      assert stats.rogue_total_wagered == 500 * @wei
    end
  end

  # ============ 6. PubSub Broadcasting ============

  describe "PubSub broadcasting" do
    test "subscribe and receive on correct topic format" do
      topic = "plinko_settlement:#{@test_user_id}"
      Phoenix.PubSub.subscribe(BlocksterV2.PubSub, topic)

      Phoenix.PubSub.broadcast(
        BlocksterV2.PubSub,
        topic,
        {:plinko_settled, "test_game_id", "0xTX_HASH"}
      )

      assert_receive {:plinko_settled, "test_game_id", "0xTX_HASH"}
    end

    test "message format is {:plinko_settled, game_id, tx_hash}" do
      topic = "plinko_settlement:#{@test_user_id}"
      Phoenix.PubSub.subscribe(BlocksterV2.PubSub, topic)

      game_id = "game_123"
      tx_hash = "0xABC123"

      Phoenix.PubSub.broadcast(BlocksterV2.PubSub, topic, {:plinko_settled, game_id, tx_hash})

      assert_receive {:plinko_settled, ^game_id, ^tx_hash}
    end

    test "user-scoped: different users don't receive each other's messages" do
      topic1 = "plinko_settlement:#{@test_user_id}"
      topic2 = "plinko_settlement:#{@test_user_id_2}"

      Phoenix.PubSub.subscribe(BlocksterV2.PubSub, topic1)

      Phoenix.PubSub.broadcast(
        BlocksterV2.PubSub,
        topic2,
        {:plinko_settled, "other_game", "0xOTHER"}
      )

      refute_receive {:plinko_settled, _, _}, 100
    end

    test "PubSub works within simulated lifecycle flow" do
      topic = "plinko_settlement:#{@test_user_id}"
      Phoenix.PubSub.subscribe(BlocksterV2.PubSub, topic)

      {game_id, _result, _settled} = simulate_full_lifecycle(@test_user_id, @test_wallet, 0, 100, "BUX", 0)

      # Simulate what settle_game would broadcast
      Phoenix.PubSub.broadcast(
        BlocksterV2.PubSub,
        topic,
        {:plinko_settled, game_id, "0xSETTLE_TX"}
      )

      assert_receive {:plinko_settled, ^game_id, "0xSETTLE_TX"}
    end
  end

  # ============ 7. PlinkoSettler Stuck Bet Detection ============

  describe "PlinkoSettler stuck bet detection" do
    test "detects placed game older than 120s" do
      write_placed_game(@test_user_id, @test_wallet, 0, System.system_time(:second) - 200)

      stuck = find_stuck_bets()
      assert length(stuck) == 1
    end

    test "ignores recently placed game (< 120s)" do
      write_placed_game(@test_user_id, @test_wallet, 0, System.system_time(:second) - 30)

      stuck = find_stuck_bets()
      assert length(stuck) == 0
    end

    test "ignores committed and settled games regardless of age" do
      write_committed_game(@test_user_id, @test_wallet, 0, System.system_time(:second) - 500)
      write_settled_game(@test_user_id, @test_wallet, 1, System.system_time(:second) - 500)

      stuck = find_stuck_bets()
      assert length(stuck) == 0
    end

    test "finds multiple stuck bets across different users" do
      write_placed_game(@test_user_id, @test_wallet, 0, System.system_time(:second) - 200)
      write_placed_game(@test_user_id_2, @test_wallet_2, 0, System.system_time(:second) - 300)

      stuck = find_stuck_bets()
      assert length(stuck) == 2
    end

    test "settled game no longer detected as stuck" do
      game_id = write_placed_game(@test_user_id, @test_wallet, 0, System.system_time(:second) - 200)
      assert length(find_stuck_bets()) == 1

      {:ok, game} = PlinkoGame.get_game(game_id)
      PlinkoGame.mark_game_settled(game_id, game, "0xSETTLE")

      assert length(find_stuck_bets()) == 0
    end
  end

  # ============ 8. Config Consistency ============

  describe "config consistency" do
    test "all 9 configs map to valid (rows, risk_level) tuples" do
      configs = PlinkoGame.configs()
      assert map_size(configs) == 9

      for {_idx, {rows, risk_level}} <- configs do
        assert rows in [8, 12, 16]
        assert risk_level in [:low, :medium, :high]
      end
    end

    test "all 9 payout tables have correct number of positions (rows + 1)" do
      configs = PlinkoGame.configs()
      payout_tables = PlinkoGame.payout_tables()

      assert map_size(payout_tables) == 9

      for {idx, {rows, _risk}} <- configs do
        table = Map.get(payout_tables, idx)
        assert length(table) == rows + 1, "Config #{idx}: expected #{rows + 1} positions, got #{length(table)}"
      end
    end

    test "no duplicate config indexes" do
      configs = PlinkoGame.configs()
      indexes = Map.keys(configs)
      assert Enum.sort(indexes) == Enum.to_list(0..8)
    end

    test "every config has a corresponding payout table" do
      configs = PlinkoGame.configs()
      payout_tables = PlinkoGame.payout_tables()

      for idx <- Map.keys(configs) do
        assert Map.has_key?(payout_tables, idx), "Missing payout table for config #{idx}"
      end
    end
  end

  # ============ 9. Edge Cases ============

  describe "edge cases" do
    test "on_bet_placed works for all 9 config indexes with correct ball_path length" do
      configs = PlinkoGame.configs()

      for {config_index, {rows, _risk}} <- configs do
        game_id = write_committed_game(@test_user_id, @test_wallet, config_index)
        {:ok, result} = PlinkoGame.on_bet_placed(game_id, "0xBET#{config_index}", "0xTX#{config_index}", 100, "BUX", config_index)

        assert length(result.ball_path) == rows,
          "Config #{config_index}: expected ball_path length #{rows}, got #{length(result.ball_path)}"
      end
    end

    test "ROGUE token stores zero address" do
      game_id = write_committed_game(@test_user_id, @test_wallet, 0)
      {:ok, _result} = PlinkoGame.on_bet_placed(game_id, "0xBET", "0xTX", 100, "ROGUE", 0)

      {:ok, game} = PlinkoGame.get_game(game_id)
      assert game.token == "ROGUE"
      assert game.token_address == "0x0000000000000000000000000000000000000000"
    end

    test "large bet amount doesn't overflow" do
      game_id = write_committed_game(@test_user_id, @test_wallet, 0)
      large_amount = 1_000_000_000

      {:ok, result} = PlinkoGame.on_bet_placed(game_id, "0xBET", "0xTX", large_amount, "BUX", 0)

      assert is_integer(result.payout)
      assert result.payout >= 0
    end

    test "mark_game_settled is idempotent (second call overwrites)" do
      game_id = write_placed_game(@test_user_id, @test_wallet, 0)
      {:ok, game} = PlinkoGame.get_game(game_id)

      PlinkoGame.mark_game_settled(game_id, game, "0xFIRST_TX")
      {:ok, first_settled} = PlinkoGame.get_game(game_id)
      assert first_settled.settlement_tx == "0xFIRST_TX"
      first_settled_at = first_settled.settled_at

      # Small delay to get different timestamp
      Process.sleep(1100)

      PlinkoGame.mark_game_settled(game_id, first_settled, "0xSECOND_TX")
      {:ok, second_settled} = PlinkoGame.get_game(game_id)
      assert second_settled.settlement_tx == "0xSECOND_TX"
      assert second_settled.settled_at >= first_settled_at
    end

    test "game with nil wallet_address still works for on_bet_placed" do
      game_id = write_committed_game(@test_user_id, nil, 0)
      {:ok, result} = PlinkoGame.on_bet_placed(game_id, "0xBET", "0xTX", 100, "BUX", 0)

      assert is_list(result.ball_path)
      {:ok, game} = PlinkoGame.get_game(game_id)
      assert game.wallet_address == nil
      assert game.status == :placed
    end
  end

  # ============ 10. Cross-Module Integration ============

  describe "cross-module integration" do
    test "game created → bet placed → becomes stuck → detected by settler" do
      game_id = write_committed_game(@test_user_id, @test_wallet, 0)
      {:ok, _result} = PlinkoGame.on_bet_placed(game_id, "0xBET", "0xTX", 100, "BUX", 0)

      # Verify it's placed but NOT stuck yet (just created)
      assert length(find_stuck_bets()) == 0

      # Manually age the record by rewriting with old created_at
      [record] = :mnesia.dirty_read({:plinko_games, game_id})
      old_record = put_elem(record, 23, System.system_time(:second) - 200)
      :mnesia.dirty_write(old_record)

      # Now it should be detected as stuck
      stuck = find_stuck_bets()
      assert length(stuck) == 1
      assert elem(hd(stuck), 1) == game_id
    end

    test "game settled before timeout is NOT detected by settler" do
      game_id = write_committed_game(@test_user_id, @test_wallet, 0)
      {:ok, _result} = PlinkoGame.on_bet_placed(game_id, "0xBET", "0xTX", 100, "BUX", 0)
      {:ok, game} = PlinkoGame.get_game(game_id)
      PlinkoGame.mark_game_settled(game_id, game, "0xSETTLE")

      # Even with old timestamp, settled games are not stuck
      [record] = :mnesia.dirty_read({:plinko_games, game_id})
      old_record = put_elem(record, 23, System.system_time(:second) - 200)
      :mnesia.dirty_write(old_record)

      assert length(find_stuck_bets()) == 0
    end

    test "settler ignores :committed games even if old" do
      write_committed_game(@test_user_id, @test_wallet, 0, System.system_time(:second) - 500)
      assert length(find_stuck_bets()) == 0
    end

    test "state transitions are mutually exclusive (can't be two states at once)" do
      game_id = write_committed_game(@test_user_id, @test_wallet, 0)
      {:ok, g1} = PlinkoGame.get_game(game_id)
      assert g1.status == :committed
      assert g1.status != :placed
      assert g1.status != :settled

      {:ok, _result} = PlinkoGame.on_bet_placed(game_id, "0xBET", "0xTX", 100, "BUX", 0)
      {:ok, g2} = PlinkoGame.get_game(game_id)
      assert g2.status == :placed
      assert g2.status != :committed
      assert g2.status != :settled

      PlinkoGame.mark_game_settled(game_id, g2, "0xSETTLE")
      {:ok, g3} = PlinkoGame.get_game(game_id)
      assert g3.status == :settled
      assert g3.status != :committed
      assert g3.status != :placed
    end
  end

  # ============ Test Helpers ============

  defp ensure_plinko_games_table do
    if :mnesia.system_info(:is_running) != :yes do
      :mnesia.start()
    end

    try do
      :mnesia.table_info(:plinko_games, :type)
    catch
      :exit, _ ->
        :mnesia.create_table(:plinko_games,
          type: :ordered_set,
          attributes: [
            :game_id, :user_id, :wallet_address, :server_seed, :commitment_hash,
            :nonce, :status, :bet_id, :token, :token_address, :bet_amount,
            :config_index, :rows, :risk_level, :ball_path, :landing_position,
            :payout_bp, :payout, :won, :commitment_tx, :bet_tx, :settlement_tx,
            :created_at, :settled_at
          ],
          index: [:user_id, :wallet_address, :status, :created_at],
          ram_copies: [node()]
        )
    end
  end

  defp ensure_user_betting_stats_table do
    if :mnesia.system_info(:is_running) != :yes do
      :mnesia.start()
    end

    try do
      :mnesia.table_info(:user_betting_stats, :type)
    catch
      :exit, _ ->
        :mnesia.create_table(:user_betting_stats,
          type: :set,
          attributes: [
            :user_id, :wallet_address,
            :bux_total_bets, :bux_wins, :bux_losses, :bux_total_wagered,
            :bux_total_winnings, :bux_total_losses, :bux_net_pnl,
            :rogue_total_bets, :rogue_wins, :rogue_losses, :rogue_total_wagered,
            :rogue_total_winnings, :rogue_total_losses, :rogue_net_pnl,
            :first_bet_at, :last_bet_at, :updated_at, :onchain_stats_cache
          ],
          index: [:bux_total_wagered, :rogue_total_wagered],
          ram_copies: [node()]
        )
    end
  end

  defp write_committed_game(user_id, wallet, nonce, created_at \\ nil) do
    game_id = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
    server_seed = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
    commitment_hash = "0x" <> (:crypto.hash(:sha256, server_seed) |> Base.encode16(case: :lower))
    now = created_at || System.system_time(:second)

    record =
      {:plinko_games, game_id, user_id, wallet, server_seed, commitment_hash, nonce,
       :committed, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
       "0xCOMMIT_TX", nil, nil, now, nil}

    :mnesia.dirty_write(record)
    game_id
  end

  defp write_committed_game_with_seed(user_id, wallet, nonce, server_seed, created_at \\ nil) do
    game_id = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
    commitment_hash = "0x" <> (:crypto.hash(:sha256, server_seed) |> Base.encode16(case: :lower))
    now = created_at || System.system_time(:second)

    record =
      {:plinko_games, game_id, user_id, wallet, server_seed, commitment_hash, nonce,
       :committed, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
       "0xCOMMIT_TX", nil, nil, now, nil}

    :mnesia.dirty_write(record)
    game_id
  end

  defp write_placed_game(user_id, wallet, nonce, created_at \\ nil) do
    game_id = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
    server_seed = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
    commitment_hash = "0x" <> (:crypto.hash(:sha256, server_seed) |> Base.encode16(case: :lower))
    now = created_at || System.system_time(:second)

    record =
      {:plinko_games, game_id, user_id, wallet, server_seed, commitment_hash, nonce,
       :placed, commitment_hash, "BUX", "0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8", 100,
       0, 8, :low, [:left, :right, :left, :right, :left, :right, :left, :right], 4,
       5000, 50, false, "0xCOMMIT_TX", "0xBET_TX", nil, now, nil}

    :mnesia.dirty_write(record)
    game_id
  end

  defp write_settled_game(user_id, wallet, nonce, created_at \\ nil) do
    game_id = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
    server_seed = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
    commitment_hash = "0x" <> (:crypto.hash(:sha256, server_seed) |> Base.encode16(case: :lower))
    now = created_at || System.system_time(:second)

    record =
      {:plinko_games, game_id, user_id, wallet, server_seed, commitment_hash, nonce,
       :settled, commitment_hash, "BUX", "0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8", 100,
       0, 8, :low, [:left, :right, :left, :right, :left, :right, :left, :right], 4,
       5000, 50, false, "0xCOMMIT_TX", "0xBET_TX", "0xSETTLE_TX", now, now + 5}

    :mnesia.dirty_write(record)
    game_id
  end

  defp write_user_betting_stats(user_id, wallet_address) do
    record =
      {:user_betting_stats, user_id, wallet_address,
       0, 0, 0, 0, 0, 0, 0,
       0, 0, 0, 0, 0, 0, 0,
       nil, nil, nil, nil}

    :mnesia.dirty_write(record)
  end

  defp read_user_betting_stats(user_id) do
    case :mnesia.dirty_read(:user_betting_stats, user_id) do
      [record] ->
        %{
          user_id: elem(record, 1),
          wallet_address: elem(record, 2),
          bux_total_bets: elem(record, 3),
          bux_wins: elem(record, 4),
          bux_losses: elem(record, 5),
          bux_total_wagered: elem(record, 6),
          bux_total_winnings: elem(record, 7),
          bux_total_losses: elem(record, 8),
          bux_net_pnl: elem(record, 9),
          rogue_total_bets: elem(record, 10),
          rogue_wins: elem(record, 11),
          rogue_losses: elem(record, 12),
          rogue_total_wagered: elem(record, 13),
          rogue_total_winnings: elem(record, 14),
          rogue_total_losses: elem(record, 15),
          rogue_net_pnl: elem(record, 16),
          first_bet_at: elem(record, 17),
          last_bet_at: elem(record, 18),
          updated_at: elem(record, 19),
          onchain_stats_cache: elem(record, 20)
        }

      [] ->
        nil
    end
  end

  # Simulates what the private update_user_betting_stats/5 does
  defp apply_stats_update(user_id, token, bet_amount, won, payout) do
    [record] = :mnesia.dirty_read(:user_betting_stats, user_id)
    bet_amount_wei = bet_amount * @wei
    payout_wei = payout * @wei
    winnings = if won, do: payout_wei - bet_amount_wei, else: 0
    losses = if won, do: 0, else: bet_amount_wei
    net_change = if won, do: payout_wei - bet_amount_wei, else: -bet_amount_wei
    now = System.system_time(:millisecond)
    first_bet_at = elem(record, 17) || now

    updated =
      case token do
        "ROGUE" ->
          record
          |> put_elem(10, elem(record, 10) + 1)
          |> put_elem(11, elem(record, 11) + if(won, do: 1, else: 0))
          |> put_elem(12, elem(record, 12) + if(won, do: 0, else: 1))
          |> put_elem(13, elem(record, 13) + bet_amount_wei)
          |> put_elem(14, elem(record, 14) + winnings)
          |> put_elem(15, elem(record, 15) + losses)
          |> put_elem(16, elem(record, 16) + net_change)
          |> put_elem(17, first_bet_at)
          |> put_elem(18, now)
          |> put_elem(19, now)

        _ ->
          record
          |> put_elem(3, elem(record, 3) + 1)
          |> put_elem(4, elem(record, 4) + if(won, do: 1, else: 0))
          |> put_elem(5, elem(record, 5) + if(won, do: 0, else: 1))
          |> put_elem(6, elem(record, 6) + bet_amount_wei)
          |> put_elem(7, elem(record, 7) + winnings)
          |> put_elem(8, elem(record, 8) + losses)
          |> put_elem(9, elem(record, 9) + net_change)
          |> put_elem(17, first_bet_at)
          |> put_elem(18, now)
          |> put_elem(19, now)
      end

    :mnesia.dirty_write(updated)
  end

  defp find_stuck_bets do
    now = System.system_time(:second)
    cutoff = now - 120

    case :mnesia.dirty_index_read(:plinko_games, :placed, :status) do
      games when is_list(games) ->
        Enum.filter(games, fn game ->
          elem(game, 7) == :placed and elem(game, 23) != nil and elem(game, 23) < cutoff
        end)

      _ ->
        []
    end
  end

  defp simulate_full_lifecycle(user_id, wallet, nonce, bet_amount, token, config_index) do
    game_id = write_committed_game(user_id, wallet, nonce)
    {:ok, result} = PlinkoGame.on_bet_placed(game_id, "0xBET", "0xTX", bet_amount, token, config_index)
    {:ok, placed_game} = PlinkoGame.get_game(game_id)
    PlinkoGame.mark_game_settled(game_id, placed_game, "0xSETTLE_TX")
    {:ok, settled_game} = PlinkoGame.get_game(game_id)
    {game_id, result, settled_game}
  end
end
