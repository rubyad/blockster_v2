defmodule BlocksterV2.PoolPositionsTest do
  use BlocksterV2.DataCase, async: false

  alias BlocksterV2.PoolPositions

  setup do
    :mnesia.start()

    case :mnesia.create_table(:user_pool_positions,
           attributes: [
             :id,
             :user_id,
             :vault_type,
             :total_cost,
             :total_lp,
             :realized_gain,
             :updated_at
           ],
           ram_copies: [node()],
           type: :set,
           index: [:user_id, :vault_type]
         ) do
      {:atomic, :ok} ->
        :ok

      {:aborted, {:already_exists, :user_pool_positions}} ->
        :mnesia.clear_table(:user_pool_positions)
    end

    :ok
  end

  # The audit's POOL-03 regression expressed as a single shared property
  # over :sol + :bux — the ACB bug was vault-agnostic.
  for vault <- ["sol", "bux"] do
    describe "record_deposit + record_withdraw (#{vault})" do
      test "partial withdraw reduces total_cost proportionally (#{vault})" do
        vault = unquote(vault)
        user_id = System.unique_integer([:positive])

        # Deposit 1.0 at lp_price 1.0 → total_cost=1.0, total_lp=1.0
        PoolPositions.record_deposit(user_id, vault, 1.0, 1.0)

        %{total_cost: tc0, total_lp: tl0, realized_gain: rg0} =
          PoolPositions.get(user_id, vault)

        assert_in_delta tc0, 1.0, 1.0e-9
        assert_in_delta tl0, 1.0, 1.0e-9
        assert rg0 == 0.0

        # Withdraw 50% of LP at lp_price 1.0 → total_cost = 0.5, total_lp = 0.5,
        # realized_gain = 0 (no price change).
        PoolPositions.record_withdraw(user_id, vault, 0.5, 1.0)

        %{total_cost: tc1, total_lp: tl1, realized_gain: rg1} =
          PoolPositions.get(user_id, vault)

        assert_in_delta tc1, 0.5, 1.0e-9
        assert_in_delta tl1, 0.5, 1.0e-9
        assert_in_delta rg1, 0.0, 1.0e-9
      end

      test "full withdraw zeroes total_cost + total_lp (#{vault})" do
        vault = unquote(vault)
        user_id = System.unique_integer([:positive])

        PoolPositions.record_deposit(user_id, vault, 2.0, 1.0)
        PoolPositions.record_withdraw(user_id, vault, 2.0, 1.0)

        %{total_cost: tc, total_lp: tl} = PoolPositions.get(user_id, vault)

        assert tc == 0.0
        assert tl == 0.0
      end

      test "withdraw at higher lp_price accrues realized_gain (#{vault})" do
        vault = unquote(vault)
        user_id = System.unique_integer([:positive])

        # Deposit 1.0 at lp_price 1.0
        PoolPositions.record_deposit(user_id, vault, 1.0, 1.0)

        # lp_price rose to 1.2 — withdraw half the LP (0.5 LP) @ 1.2 =
        # proceeds 0.6, cost_removed 0.5, realized_gain 0.1.
        PoolPositions.record_withdraw(user_id, vault, 0.5, 1.2)

        %{realized_gain: rg, total_cost: tc, total_lp: tl} =
          PoolPositions.get(user_id, vault)

        assert_in_delta rg, 0.1, 1.0e-9
        assert_in_delta tc, 0.5, 1.0e-9
        assert_in_delta tl, 0.5, 1.0e-9
      end

      test "summary returns cost_basis + current_value + unrealized_pnl + realized_gain (#{vault})" do
        vault = unquote(vault)
        user_id = System.unique_integer([:positive])

        PoolPositions.record_deposit(user_id, vault, 1.0, 1.0)
        PoolPositions.record_withdraw(user_id, vault, 0.5, 1.2)

        # After: total_cost 0.5, total_lp 0.5, realized_gain 0.1.
        # Current lp_price 1.3 → current_value 0.5 * 1.3 = 0.65,
        # unrealized_pnl 0.65 - 0.5 = 0.15.
        summary = PoolPositions.summary(user_id, vault, 0.5, 1.3)

        assert_in_delta summary.cost_basis, 0.5, 1.0e-9
        assert_in_delta summary.current_value, 0.65, 1.0e-9
        assert_in_delta summary.unrealized_pnl, 0.15, 1.0e-9
        assert_in_delta summary.realized_gain, 0.1, 1.0e-9
      end

      test "reset_position wipes the row so seed_if_missing re-seeds (#{vault})" do
        vault = unquote(vault)
        user_id = System.unique_integer([:positive])

        PoolPositions.record_deposit(user_id, vault, 1.0, 1.0)
        assert %{total_cost: _} = PoolPositions.get(user_id, vault)

        PoolPositions.reset_position(user_id, vault)
        assert PoolPositions.get(user_id, vault) == nil

        PoolPositions.seed_if_missing(user_id, vault, 0.9, 1.1)
        %{total_cost: tc, total_lp: tl} = PoolPositions.get(user_id, vault)
        assert_in_delta tc, 0.9 * 1.1, 1.0e-9
        assert_in_delta tl, 0.9, 1.0e-9
      end
    end
  end

  describe "POOL-03 regression — the audit screenshot values" do
    test "1 SOL deposit then 0.5 SOL-LP withdraw leaves ~0.5 cost basis, not 1.0008" do
      # The audit captured cost_basis: 1.0008, unrealized P/L: -0.5121 after
      # a partial withdraw, because record_withdraw never fired. With the
      # PoolPositions call site fixed (POOL-03 commit) cost_basis MUST drop
      # proportionally.
      user_id = System.unique_integer([:positive])

      # Deposit 1.0008 SOL @ lp_price 1.024 → total_cost 1.0008, total_lp ≈ 0.9773
      PoolPositions.record_deposit(user_id, "sol", 1.0008, 1.024)
      %{total_lp: tl0} = PoolPositions.get(user_id, "sol")

      # Withdraw 0.5 SOL-LP @ lp_price 1.024 → cost_removed ≈ 0.512,
      # remaining total_cost ≈ 0.489.
      PoolPositions.record_withdraw(user_id, "sol", 0.5, 1.024)
      %{total_cost: tc, total_lp: tl_rem} = PoolPositions.get(user_id, "sol")

      assert_in_delta tc, 1.0008 * (tl0 - 0.5) / tl0, 1.0e-6

      # The audit's pre-fix observation: cost_basis stayed at 1.0008.
      # Assert we moved AWAY from that — at least 0.1 reduction.
      assert tc < 1.0008 - 0.1,
             "cost_basis should drop after partial withdraw, saw #{tc} (pre-fix bug had it stuck at 1.0008)"
      assert tl_rem > 0
    end
  end
end
