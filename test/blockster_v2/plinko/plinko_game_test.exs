defmodule BlocksterV2.Plinko.PlinkoGameTest do
  use ExUnit.Case

  alias BlocksterV2.PlinkoGame

  @test_user_id 999
  @test_wallet "0xTEST_WALLET_ADDRESS"

  setup do
    # Ensure Mnesia is started and plinko_games table exists
    ensure_mnesia_table()
    :mnesia.clear_table(:plinko_games)
    :ok
  end

  # ============ get_game ============

  describe "get_game/1" do
    test "returns {:ok, game_map} for existing game" do
      game_id = write_committed_game(@test_user_id, @test_wallet, 0)
      assert {:ok, game} = PlinkoGame.get_game(game_id)
      assert game.game_id == game_id
      assert game.user_id == @test_user_id
      assert game.wallet_address == @test_wallet
      assert game.status == :committed
    end

    test "returns {:error, :not_found} for missing game" do
      assert {:error, :not_found} = PlinkoGame.get_game("nonexistent_game_id")
    end

    test "game map has all 24 fields" do
      game_id = write_committed_game(@test_user_id, @test_wallet, 0)
      {:ok, game} = PlinkoGame.get_game(game_id)

      expected_keys = [
        :game_id, :user_id, :wallet_address, :server_seed, :commitment_hash,
        :nonce, :status, :bet_id, :token, :token_address, :bet_amount,
        :config_index, :rows, :risk_level, :ball_path, :landing_position,
        :payout_bp, :payout, :won, :commitment_tx, :bet_tx, :settlement_tx,
        :created_at, :settled_at
      ]

      for key <- expected_keys do
        assert Map.has_key?(game, key), "Missing key: #{key}"
      end

      assert map_size(game) == 24
    end
  end

  # ============ get_pending_game ============

  describe "get_pending_game/1" do
    test "returns committed game for user_id" do
      game_id = write_committed_game(@test_user_id, @test_wallet, 0)
      pending = PlinkoGame.get_pending_game(@test_user_id)

      assert pending != nil
      assert pending.game_id == game_id
      assert pending.status == :committed
    end

    test "returns nil when no committed games exist" do
      assert PlinkoGame.get_pending_game(@test_user_id) == nil
    end

    test "does not return placed or settled games" do
      write_placed_game(@test_user_id, @test_wallet, 0)
      assert PlinkoGame.get_pending_game(@test_user_id) == nil
    end

    test "returns most recent committed game when multiple exist" do
      _older_id = write_committed_game(@test_user_id, @test_wallet, 0, System.system_time(:second) - 100)
      newer_id = write_committed_game(@test_user_id, @test_wallet, 1, System.system_time(:second))

      pending = PlinkoGame.get_pending_game(@test_user_id)
      assert pending.game_id == newer_id
    end
  end

  # ============ on_bet_placed ============

  describe "on_bet_placed/6" do
    test "updates game status from :committed to :placed" do
      game_id = write_committed_game(@test_user_id, @test_wallet, 0)

      assert {:ok, _result} =
               PlinkoGame.on_bet_placed(game_id, "0xBET123", "0xTX123", 100, "BUX", 0)

      {:ok, game} = PlinkoGame.get_game(game_id)
      assert game.status == :placed
    end

    test "stores bet_id, token, token_address, bet_amount, config_index" do
      game_id = write_committed_game(@test_user_id, @test_wallet, 0)
      PlinkoGame.on_bet_placed(game_id, "0xBET_ID", "0xBET_TX", 100, "BUX", 2)

      {:ok, game} = PlinkoGame.get_game(game_id)
      assert game.bet_id == "0xBET_ID"
      assert game.token == "BUX"
      assert game.token_address == "0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8"
      assert game.bet_amount == 100
      assert game.config_index == 2
    end

    test "calculates and stores ball_path, landing_position, payout_bp, payout, won" do
      game_id = write_committed_game(@test_user_id, @test_wallet, 0)
      {:ok, result} = PlinkoGame.on_bet_placed(game_id, "0xBET", "0xTX", 100, "BUX", 0)

      {:ok, game} = PlinkoGame.get_game(game_id)
      assert is_list(game.ball_path)
      assert length(game.ball_path) == 8
      assert is_integer(game.landing_position)
      assert is_integer(game.payout_bp)
      assert is_integer(game.payout)
      assert is_boolean(game.won)

      # Result should match what's stored
      assert game.ball_path == result.ball_path
      assert game.landing_position == result.landing_position
    end

    test "stores rows and risk_level from config lookup" do
      game_id = write_committed_game(@test_user_id, @test_wallet, 0)
      PlinkoGame.on_bet_placed(game_id, "0xBET", "0xTX", 100, "BUX", 5)

      {:ok, game} = PlinkoGame.get_game(game_id)
      assert game.rows == 12
      assert game.risk_level == :high
    end

    test "stores bet_tx hash" do
      game_id = write_committed_game(@test_user_id, @test_wallet, 0)
      PlinkoGame.on_bet_placed(game_id, "0xBET", "0xMY_TX_HASH", 100, "BUX", 0)

      {:ok, game} = PlinkoGame.get_game(game_id)
      assert game.bet_tx == "0xMY_TX_HASH"
    end

    test "returns {:ok, result} with calculated result" do
      game_id = write_committed_game(@test_user_id, @test_wallet, 0)
      {:ok, result} = PlinkoGame.on_bet_placed(game_id, "0xBET", "0xTX", 100, "BUX", 0)

      assert is_list(result.ball_path)
      assert is_integer(result.landing_position)
      assert is_integer(result.payout)
      assert is_integer(result.payout_bp)
      assert is_boolean(result.won)
      assert result.outcome in [:won, :lost, :push]
    end

    test "returns {:error, :not_found} for invalid game_id" do
      assert {:error, :not_found} =
               PlinkoGame.on_bet_placed("nonexistent", "0xBET", "0xTX", 100, "BUX", 0)
    end

    test "Mnesia tuple has exactly 25 elements after update" do
      game_id = write_committed_game(@test_user_id, @test_wallet, 0)
      PlinkoGame.on_bet_placed(game_id, "0xBET", "0xTX", 100, "BUX", 0)

      [record] = :mnesia.dirty_read({:plinko_games, game_id})
      assert tuple_size(record) == 25
    end
  end

  # ============ mark_game_settled ============

  describe "mark_game_settled/3" do
    test "writes :settled status to Mnesia" do
      game_id = write_placed_game(@test_user_id, @test_wallet, 0)
      {:ok, game} = PlinkoGame.get_game(game_id)

      PlinkoGame.mark_game_settled(game_id, game, "0xSETTLE_TX")

      {:ok, updated} = PlinkoGame.get_game(game_id)
      assert updated.status == :settled
    end

    test "stores settlement_tx" do
      game_id = write_placed_game(@test_user_id, @test_wallet, 0)
      {:ok, game} = PlinkoGame.get_game(game_id)

      PlinkoGame.mark_game_settled(game_id, game, "0xSETTLE_TX_HASH")

      {:ok, updated} = PlinkoGame.get_game(game_id)
      assert updated.settlement_tx == "0xSETTLE_TX_HASH"
    end

    test "stores settled_at as Unix timestamp" do
      game_id = write_placed_game(@test_user_id, @test_wallet, 0)
      {:ok, game} = PlinkoGame.get_game(game_id)

      before = System.system_time(:second)
      PlinkoGame.mark_game_settled(game_id, game, "0xTX")
      after_time = System.system_time(:second)

      {:ok, updated} = PlinkoGame.get_game(game_id)
      assert updated.settled_at >= before
      assert updated.settled_at <= after_time
    end
  end

  # ============ load_recent_games ============

  describe "load_recent_games/2" do
    test "returns only :settled games" do
      write_committed_game(@test_user_id, @test_wallet, 0)
      write_placed_game(@test_user_id, @test_wallet, 1)
      _settled_id = write_settled_game(@test_user_id, @test_wallet, 2)

      games = PlinkoGame.load_recent_games(@test_user_id)
      assert length(games) == 1
      assert hd(games).status == :settled
    end

    test "returns games sorted by created_at descending (newest first)" do
      write_settled_game(@test_user_id, @test_wallet, 0, System.system_time(:second) - 200)
      write_settled_game(@test_user_id, @test_wallet, 1, System.system_time(:second) - 100)
      write_settled_game(@test_user_id, @test_wallet, 2, System.system_time(:second))

      games = PlinkoGame.load_recent_games(@test_user_id)
      assert length(games) == 3

      timestamps = Enum.map(games, & &1.created_at)
      assert timestamps == Enum.sort(timestamps, :desc)
    end

    test "respects limit option" do
      for n <- 0..4 do
        write_settled_game(@test_user_id, @test_wallet, n)
      end

      games = PlinkoGame.load_recent_games(@test_user_id, limit: 2)
      assert length(games) == 2
    end

    test "respects offset option" do
      for n <- 0..4 do
        write_settled_game(@test_user_id, @test_wallet, n, System.system_time(:second) - (4 - n) * 10)
      end

      all_games = PlinkoGame.load_recent_games(@test_user_id)
      offset_games = PlinkoGame.load_recent_games(@test_user_id, offset: 2)

      assert length(offset_games) == 3
      assert hd(offset_games).game_id == Enum.at(all_games, 2).game_id
    end

    test "returns empty list for user with no games" do
      assert PlinkoGame.load_recent_games(12345) == []
    end

    test "returns maps (not tuples)" do
      write_settled_game(@test_user_id, @test_wallet, 0)
      [game | _] = PlinkoGame.load_recent_games(@test_user_id)
      assert is_map(game)
      assert Map.has_key?(game, :game_id)
    end

    test "default limit is 30" do
      for n <- 0..34 do
        write_settled_game(@test_user_id, @test_wallet, n)
      end

      games = PlinkoGame.load_recent_games(@test_user_id)
      assert length(games) == 30
    end
  end

  # ============ is_bet_already_settled_error? (via settle_game error handling) ============

  describe "contract error detection" do
    test "PlinkoGame module is loaded" do
      assert Code.ensure_loaded?(BlocksterV2.PlinkoGame)
    end
  end

  # ============ Test Helpers ============

  defp ensure_mnesia_table do
    # Start Mnesia if not running
    if :mnesia.system_info(:is_running) != :yes do
      :mnesia.start()
    end

    # Create table if it doesn't exist
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
end
