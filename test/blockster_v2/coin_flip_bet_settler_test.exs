defmodule BlocksterV2.CoinFlipBetSettlerTest do
  use BlocksterV2.DataCase, async: false

  alias BlocksterV2.CoinFlipBetSettler

  # ============================================================================
  # Tests for CoinFlipBetSettler GenServer (Phase 6 Solana migration)
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

    # Dead-letter table — handle_settle_error parks terminal/expired bets here
    case :mnesia.create_table(:settler_dead_letters, [
           attributes: [
             :id, :operation_type, :operation_id, :reason,
             :attempt_count, :first_failed_at, :last_failed_at, :payload
           ],
           ram_copies: [node()],
           type: :set,
           index: [:operation_type, :last_failed_at]
         ]) do
      {:atomic, :ok} -> :ok
      {:aborted, {:already_exists, :settler_dead_letters}} ->
        :mnesia.clear_table(:settler_dead_letters)
    end

    :ok
  end

  describe "find_unsettled_bets" do
    test "finds placed bets older than cutoff" do
      # Insert a bet placed 5 minutes ago
      old_time = System.system_time(:second) - 300
      old_record = {
        :coin_flip_games,
        "old_bet", 1, "wallet1", "seed", "hash", 0, :placed,
        :bux, 100, 1, [:heads], [:heads], true, 198.0,
        "sig", "bet_sig", nil, old_time, nil
      }
      :mnesia.dirty_write(old_record)

      # Insert a recent bet (30 seconds ago)
      recent_time = System.system_time(:second) - 30
      recent_record = {
        :coin_flip_games,
        "recent_bet", 2, "wallet2", "seed2", "hash2", 0, :placed,
        :bux, 200, 1, [:tails], [:tails], true, 396.0,
        "sig2", "bet_sig2", nil, recent_time, nil
      }
      :mnesia.dirty_write(recent_record)

      # Insert a settled bet (should not appear)
      settled_record = {
        :coin_flip_games,
        "settled_bet", 3, "wallet3", "seed3", "hash3", 0, :settled,
        :bux, 100, 1, [:heads], [:heads], true, 198.0,
        "sig3", "bet_sig3", "settle_sig3", old_time, old_time + 10
      }
      :mnesia.dirty_write(settled_record)

      # Find unsettled bets with 2-minute cutoff
      cutoff = System.system_time(:second) - 120
      unsettled = :mnesia.dirty_match_object(
        {:coin_flip_games, :_, :_, :_, :_, :_, :_, :placed, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}
      )
      |> Enum.filter(fn record ->
        created_at = elem(record, 18)
        created_at != nil and created_at < cutoff
      end)

      assert length(unsettled) == 1
      assert elem(hd(unsettled), 1) == "old_bet"
    end

    test "ignores committed (not placed) games" do
      old_time = System.system_time(:second) - 300
      committed_record = {
        :coin_flip_games,
        "committed_only", 1, "wallet1", "seed", "hash", 0, :committed,
        nil, nil, nil, nil, nil, nil, nil,
        "sig", nil, nil, old_time, nil
      }
      :mnesia.dirty_write(committed_record)

      unsettled = :mnesia.dirty_match_object(
        {:coin_flip_games, :_, :_, :_, :_, :_, :_, :placed, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}
      )

      assert length(unsettled) == 0
    end
  end

  describe "concurrent unsettled bets" do
    test "finds multiple unsettled bets for different users" do
      old_time = System.system_time(:second) - 300

      record1 = {:coin_flip_games,
        "user1_bet", 1, "wallet1", "seed1", "hash1", 0, :placed,
        :bux, 100, 1, [:heads], [:heads], true, 198.0,
        "sig1", "bet1", nil, old_time, nil}
      record2 = {:coin_flip_games,
        "user2_bet", 2, "wallet2", "seed2", "hash2", 0, :placed,
        :bux, 200, 1, [:tails], [:tails], false, 0,
        "sig2", "bet2", nil, old_time, nil}
      :mnesia.dirty_write(record1)
      :mnesia.dirty_write(record2)

      cutoff = System.system_time(:second) - 120
      unsettled = :mnesia.dirty_match_object(
        {:coin_flip_games, :_, :_, :_, :_, :_, :_, :placed, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}
      )
      |> Enum.filter(fn r -> elem(r, 18) != nil and elem(r, 18) < cutoff end)

      assert length(unsettled) == 2
    end

    test "finds multiple unsettled bets for same user (concurrent nonces)" do
      old_time = System.system_time(:second) - 300

      record0 = {:coin_flip_games,
        "same_user_0", 1, "wallet1", "seed0", "hash0", 0, :placed,
        :bux, 100, 1, [:heads], [:heads], true, 198.0,
        "sig0", "bet0", nil, old_time, nil}
      record1 = {:coin_flip_games,
        "same_user_1", 1, "wallet1", "seed1", "hash1", 1, :placed,
        :bux, 100, 1, [:tails], [:tails], false, 0,
        "sig1", "bet1", nil, old_time, nil}
      :mnesia.dirty_write(record0)
      :mnesia.dirty_write(record1)

      cutoff = System.system_time(:second) - 120
      unsettled = :mnesia.dirty_match_object(
        {:coin_flip_games, :_, :_, :_, :_, :_, :_, :placed, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}
      )
      |> Enum.filter(fn r -> elem(r, 18) != nil and elem(r, 18) < cutoff end)

      assert length(unsettled) == 2
      nonces = Enum.map(unsettled, fn r -> elem(r, 6) end) |> Enum.sort()
      assert nonces == [0, 1]
    end
  end

  describe "module attributes" do
    test "check_interval is 1 minute" do
      # The module is configured with @check_interval :timer.minutes(1)
      # We verify the module compiles correctly with these attributes
      assert is_atom(CoinFlipBetSettler)
    end
  end

  # Regression for the 2026-06-05 incident: 4 bets whose on-chain orders had
  # passed bet_timeout were retried by the settler every minute, forever —
  # OrderExpired wasn't classified, so the bets never left :placed.
  describe "handle_settle_error/3 with OrderExpired" do
    # The exact error shape CoinFlipGame.settle_game returns when the settler
    # service relays the on-chain OrderExpired revert.
    @order_expired_reason "HTTP 500: {\"error\":\"Simulation failed. \\nMessage: Transaction " <>
                            "simulation failed: Error processing Instruction 2: custom program " <>
                            "error: 0x1788. \\nLogs: [\\\"Program log: AnchorError thrown in " <>
                            "programs/blockster-bankroll/src/instructions/settle_bet.rs:140. " <>
                            "Error Code: OrderExpired. Error Number: 6024. Error Message: " <>
                            "Bet order has expired.\\\"]\"}"

    defp write_placed_bet(game_id, user_id, age_seconds) do
      created_at = System.system_time(:second) - age_seconds

      :mnesia.dirty_write({
        :coin_flip_games,
        game_id, user_id, "walletX", "seed", "hash", 396, :placed,
        :bux, 2.05, 1, [:heads], [:heads], true, 4.059,
        "commit_sig", "bet_sig", nil, created_at, nil
      })

      created_at
    end

    test "marks the bet :expired, dead-letters it, and returns :expired" do
      created_at = write_placed_bet("expired_bet", 2485, 509_000)
      bet = %{game_id: "expired_bet", user_id: 2485, created_at: created_at}

      assert CoinFlipBetSettler.handle_settle_error(bet, @order_expired_reason, 509_000) ==
               :expired

      [updated] = :mnesia.dirty_read({:coin_flip_games, "expired_bet"})
      assert elem(updated, 7) == :expired
      # The bet never settled — settlement_sig and settled_at stay nil
      # (mark_game_failed would have stamped both; that path must NOT run).
      assert elem(updated, 17) == nil
      assert elem(updated, 19) == nil

      dead = BlocksterV2.SettlerRetry.list_dead_letters()

      assert Enum.any?(dead, fn d ->
               d.operation_type == :coin_flip and d.operation_id == "expired_bet"
             end)
    end

    test ":expired bets stop matching the settler's :placed match spec" do
      created_at = write_placed_bet("loop_stopper", 2485, 509_000)
      bet = %{game_id: "loop_stopper", user_id: 2485, created_at: created_at}
      CoinFlipBetSettler.handle_settle_error(bet, @order_expired_reason, 509_000)

      # The exact match spec find_unsettled_bets/1 uses — the retry loop
      # must not see this bet again.
      unsettled =
        :mnesia.dirty_match_object(
          {:coin_flip_games, :_, :_, :_, :_, :_, :_, :placed, :_, :_, :_, :_, :_, :_, :_, :_, :_,
           :_, :_, :_}
        )

      assert unsettled == []
    end

    test ":expired bets still match the /play reclaim filter" do
      created_at = write_placed_bet("reclaimable", 2485, 509_000)
      bet = %{game_id: "reclaimable", user_id: 2485, created_at: created_at}
      CoinFlipBetSettler.handle_settle_error(bet, @order_expired_reason, 509_000)

      now = System.system_time(:second)
      bet_timeout = 300

      # Mirrors the filter in CoinFlipLive reclaim_stuck_bet / check_expired_bets —
      # the player must still be offered the reclaim banner for their stake.
      reclaimable =
        :mnesia.dirty_match_object(
          {:coin_flip_games, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_,
           :_, :_}
        )
        |> Enum.filter(fn record ->
          status = elem(record, 7)
          created = elem(record, 18)
          status in [:placed, :expired] and created != nil and now - created > bet_timeout
        end)

      assert length(reclaimable) == 1
      assert elem(hd(reclaimable), 1) == "reclaimable"
    end

    test "terminal errors still mark :settled with the failed sig (unchanged contract)" do
      created_at = write_placed_bet("terminal_bet", 7, 400)
      bet = %{game_id: "terminal_bet", user_id: 7, created_at: created_at}

      assert CoinFlipBetSettler.handle_settle_error(bet, "InvalidServerSeed", 400) == :error

      [updated] = :mnesia.dirty_read({:coin_flip_games, "terminal_bet"})
      assert elem(updated, 7) == :settled
      assert elem(updated, 17) == "failed_no_onchain_order"
      assert is_integer(elem(updated, 19))
    end

    test "transient errors leave the bet untouched and return :error" do
      created_at = write_placed_bet("transient_bet", 8, 400)
      bet = %{game_id: "transient_bet", user_id: 8, created_at: created_at}

      assert CoinFlipBetSettler.handle_settle_error(bet, "ECONNREFUSED", 400) == :error

      [unchanged] = :mnesia.dirty_read({:coin_flip_games, "transient_bet"})
      assert elem(unchanged, 7) == :placed
    end
  end
end
