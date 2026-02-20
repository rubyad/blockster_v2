defmodule BlocksterV2.Plinko.PlinkoSettlerTest do
  use ExUnit.Case

  alias BlocksterV2.PlinkoSettler

  setup do
    ensure_mnesia_table()
    :mnesia.clear_table(:plinko_games)
    :ok
  end

  # ============ Stuck Bet Detection ============

  describe "stuck bet detection" do
    test "finds :placed games older than 120 seconds" do
      # Write a placed game from 200 seconds ago
      _game_id = write_placed_game(1, "0xWALLET", 0, System.system_time(:second) - 200)

      stuck = find_stuck_bets()
      assert length(stuck) == 1
    end

    test "ignores :placed games newer than 120 seconds" do
      _game_id = write_placed_game(1, "0xWALLET", 0, System.system_time(:second) - 30)

      stuck = find_stuck_bets()
      assert length(stuck) == 0
    end

    test "ignores :committed games" do
      write_committed_game(1, "0xWALLET", 0, System.system_time(:second) - 200)

      stuck = find_stuck_bets()
      assert length(stuck) == 0
    end

    test "ignores :settled games" do
      write_settled_game(1, "0xWALLET", 0, System.system_time(:second) - 200)

      stuck = find_stuck_bets()
      assert length(stuck) == 0
    end

    test "does nothing when no stuck bets exist" do
      stuck = find_stuck_bets()
      assert stuck == []
    end
  end

  # ============ GenServer Lifecycle ============

  describe "lifecycle" do
    test "PlinkoSettler module is loaded" do
      assert Code.ensure_loaded?(BlocksterV2.PlinkoSettler)
    end

    test "module defines start_link/1" do
      assert function_exported?(PlinkoSettler, :start_link, 1)
    end

    test "module defines init/1" do
      assert function_exported?(PlinkoSettler, :init, 1)
    end

    test "init returns {:ok, state} with registered: false" do
      assert {:ok, %{registered: false}} = PlinkoSettler.init([])
    end
  end

  # ============ Test Helpers ============

  # Simulates the settler's stuck-bet-finding logic without actually settling
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

  defp ensure_mnesia_table do
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
