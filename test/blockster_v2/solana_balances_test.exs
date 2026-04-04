defmodule BlocksterV2.SolanaBalancesTest do
  use BlocksterV2.DataCase, async: false

  alias BlocksterV2.EngagementTracker

  # ============================================================================
  # Test Setup — create user_solana_balances Mnesia table
  # ============================================================================

  setup do
    :mnesia.start()

    case :mnesia.create_table(:user_solana_balances, [
           attributes: [:user_id, :wallet_address, :updated_at, :sol_balance, :bux_balance],
           ram_copies: [node()],
           type: :set
         ]) do
      {:atomic, :ok} -> :ok
      {:aborted, {:already_exists, :user_solana_balances}} ->
        case :mnesia.add_table_copy(:user_solana_balances, node(), :ram_copies) do
          {:atomic, :ok} -> :ok
          {:aborted, {:already_exists, :user_solana_balances, _}} -> :ok
        end
        :mnesia.clear_table(:user_solana_balances)
    end

    :ok
  end

  # ============================================================================
  # get_user_sol_balance/1 tests
  # ============================================================================

  describe "get_user_sol_balance/1" do
    test "returns 0.0 for user with no record" do
      assert EngagementTracker.get_user_sol_balance(999) == 0.0
    end

    test "returns SOL balance from Mnesia" do
      now = System.system_time(:second)
      :mnesia.dirty_write({:user_solana_balances, 1, "wallet123", now, 5.5, 100.0})

      assert EngagementTracker.get_user_sol_balance(1) == 5.5
    end

    test "returns 0.0 when sol_balance is nil" do
      now = System.system_time(:second)
      :mnesia.dirty_write({:user_solana_balances, 1, "wallet123", now, nil, 100.0})

      assert EngagementTracker.get_user_sol_balance(1) == 0.0
    end
  end

  # ============================================================================
  # get_user_solana_bux_balance/1 tests
  # ============================================================================

  describe "get_user_solana_bux_balance/1" do
    test "returns 0.0 for user with no record" do
      assert EngagementTracker.get_user_solana_bux_balance(999) == 0.0
    end

    test "returns BUX balance from Mnesia" do
      now = System.system_time(:second)
      :mnesia.dirty_write({:user_solana_balances, 1, "wallet123", now, 2.0, 500.5})

      assert EngagementTracker.get_user_solana_bux_balance(1) == 500.5
    end

    test "returns 0.0 when bux_balance is nil" do
      now = System.system_time(:second)
      :mnesia.dirty_write({:user_solana_balances, 1, "wallet123", now, 2.0, nil})

      assert EngagementTracker.get_user_solana_bux_balance(1) == 0.0
    end
  end

  # ============================================================================
  # get_user_solana_balances/1 tests
  # ============================================================================

  describe "get_user_solana_balances/1" do
    test "returns %{sol: 0.0, bux: 0.0} for missing user" do
      assert EngagementTracker.get_user_solana_balances(999) == %{sol: 0.0, bux: 0.0}
    end

    test "returns both SOL and BUX balances" do
      now = System.system_time(:second)
      :mnesia.dirty_write({:user_solana_balances, 1, "wallet123", now, 3.0, 750.0})

      assert EngagementTracker.get_user_solana_balances(1) == %{sol: 3.0, bux: 750.0}
    end
  end

  # ============================================================================
  # update_user_sol_balance/3 tests
  # ============================================================================

  describe "update_user_sol_balance/3" do
    test "creates new record when none exists" do
      assert {:ok, 2.5} = EngagementTracker.update_user_sol_balance(1, "wallet123", 2.5)

      assert [{:user_solana_balances, 1, "wallet123", _, 2.5, 0.0}] =
        :mnesia.dirty_read({:user_solana_balances, 1})
    end

    test "updates existing record's SOL balance" do
      now = System.system_time(:second)
      :mnesia.dirty_write({:user_solana_balances, 1, "wallet123", now, 1.0, 500.0})

      assert {:ok, 5.0} = EngagementTracker.update_user_sol_balance(1, "wallet123", 5.0)

      [{:user_solana_balances, 1, "wallet123", _, sol, bux}] =
        :mnesia.dirty_read({:user_solana_balances, 1})

      assert sol == 5.0
      assert bux == 500.0  # BUX unchanged
    end

    test "updates wallet address when it changes" do
      now = System.system_time(:second)
      :mnesia.dirty_write({:user_solana_balances, 1, "old_wallet", now, 1.0, 100.0})

      assert {:ok, 2.0} = EngagementTracker.update_user_sol_balance(1, "new_wallet", 2.0)

      [{:user_solana_balances, 1, wallet, _, _, _}] =
        :mnesia.dirty_read({:user_solana_balances, 1})

      assert wallet == "new_wallet"
    end

    test "handles string balance values" do
      assert {:ok, 3.14} = EngagementTracker.update_user_sol_balance(1, "wallet123", "3.14")

      [{:user_solana_balances, 1, _, _, sol, _}] =
        :mnesia.dirty_read({:user_solana_balances, 1})

      assert sol == 3.14
    end

    test "handles integer balance values" do
      assert {:ok, 5.0} = EngagementTracker.update_user_sol_balance(1, "wallet123", 5)

      [{:user_solana_balances, 1, _, _, sol, _}] =
        :mnesia.dirty_read({:user_solana_balances, 1})

      assert sol == 5.0
    end
  end

  # ============================================================================
  # update_user_solana_bux_balance/3 tests
  # ============================================================================

  describe "update_user_solana_bux_balance/3" do
    test "creates new record when none exists" do
      assert {:ok, 1000.0} = EngagementTracker.update_user_solana_bux_balance(1, "wallet123", 1000.0)

      assert [{:user_solana_balances, 1, "wallet123", _, 0.0, 1000.0}] =
        :mnesia.dirty_read({:user_solana_balances, 1})
    end

    test "updates existing record's BUX balance" do
      now = System.system_time(:second)
      :mnesia.dirty_write({:user_solana_balances, 1, "wallet123", now, 3.0, 500.0})

      assert {:ok, 750.0} = EngagementTracker.update_user_solana_bux_balance(1, "wallet123", 750.0)

      [{:user_solana_balances, 1, "wallet123", _, sol, bux}] =
        :mnesia.dirty_read({:user_solana_balances, 1})

      assert sol == 3.0   # SOL unchanged
      assert bux == 750.0
    end

    test "updates timestamp on write" do
      before = System.system_time(:second)
      EngagementTracker.update_user_solana_bux_balance(1, "wallet", 100.0)

      [{:user_solana_balances, 1, _, updated_at, _, _}] =
        :mnesia.dirty_read({:user_solana_balances, 1})

      assert updated_at >= before
    end

    test "handles string balance values" do
      assert {:ok, 250.5} = EngagementTracker.update_user_solana_bux_balance(1, "wallet", "250.5")
    end

    test "handles integer balance values" do
      assert {:ok, 100.0} = EngagementTracker.update_user_solana_bux_balance(1, "wallet", 100)
    end
  end

  # ============================================================================
  # Combined SOL + BUX update flow tests
  # ============================================================================

  describe "combined balance updates" do
    test "sequential SOL and BUX updates preserve both values" do
      EngagementTracker.update_user_sol_balance(1, "wallet123", 10.0)
      EngagementTracker.update_user_solana_bux_balance(1, "wallet123", 5000.0)

      balances = EngagementTracker.get_user_solana_balances(1)
      assert balances.sol == 10.0
      assert balances.bux == 5000.0
    end

    test "multiple updates for same user overwrite correctly" do
      EngagementTracker.update_user_sol_balance(1, "wallet", 1.0)
      EngagementTracker.update_user_sol_balance(1, "wallet", 2.0)
      EngagementTracker.update_user_sol_balance(1, "wallet", 3.0)

      assert EngagementTracker.get_user_sol_balance(1) == 3.0
    end

    test "different users have independent balances" do
      EngagementTracker.update_user_sol_balance(1, "wallet_a", 5.0)
      EngagementTracker.update_user_solana_bux_balance(1, "wallet_a", 1000.0)

      EngagementTracker.update_user_sol_balance(2, "wallet_b", 10.0)
      EngagementTracker.update_user_solana_bux_balance(2, "wallet_b", 2000.0)

      assert EngagementTracker.get_user_solana_balances(1) == %{sol: 5.0, bux: 1000.0}
      assert EngagementTracker.get_user_solana_balances(2) == %{sol: 10.0, bux: 2000.0}
    end
  end

  # ============================================================================
  # Edge cases
  # ============================================================================

  describe "edge cases" do
    test "zero balances" do
      EngagementTracker.update_user_sol_balance(1, "wallet", 0.0)
      EngagementTracker.update_user_solana_bux_balance(1, "wallet", 0.0)

      assert EngagementTracker.get_user_solana_balances(1) == %{sol: 0.0, bux: 0.0}
    end

    test "very small SOL balance (dust)" do
      EngagementTracker.update_user_sol_balance(1, "wallet", 0.000000001)
      assert EngagementTracker.get_user_sol_balance(1) == 0.000000001
    end

    test "very large BUX balance" do
      EngagementTracker.update_user_solana_bux_balance(1, "wallet", 999_999_999.0)
      assert EngagementTracker.get_user_solana_bux_balance(1) == 999_999_999.0
    end
  end
end
