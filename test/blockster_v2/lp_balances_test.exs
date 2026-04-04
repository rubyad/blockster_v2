defmodule BlocksterV2.LpBalancesTest do
  use BlocksterV2.DataCase, async: false

  alias BlocksterV2.EngagementTracker

  # ============================================================================
  # Tests for LP balance tracking (Phase 7 — bSOL/bBUX LP tokens)
  # ============================================================================

  setup do
    :mnesia.start()

    # Create user_lp_balances table
    case :mnesia.create_table(:user_lp_balances, [
           attributes: [:user_id, :wallet_address, :updated_at, :bsol_balance, :bbux_balance],
           ram_copies: [node()],
           type: :set,
           index: [:wallet_address]
         ]) do
      {:atomic, :ok} -> :ok
      {:aborted, {:already_exists, :user_lp_balances}} ->
        case :mnesia.add_table_copy(:user_lp_balances, node(), :ram_copies) do
          {:atomic, :ok} -> :ok
          {:aborted, {:already_exists, :user_lp_balances, _}} -> :ok
        end
        :mnesia.clear_table(:user_lp_balances)
    end

    :ok
  end

  # ============================================================================
  # get_user_lp_balances Tests
  # ============================================================================

  describe "get_user_lp_balances/1" do
    test "returns zero balances for unknown user" do
      result = EngagementTracker.get_user_lp_balances(999_999)
      assert result == %{bsol: 0.0, bbux: 0.0}
    end

    test "returns stored balances" do
      user_id = 42
      wallet = "TestWallet123"

      record = {:user_lp_balances, user_id, wallet, System.system_time(:second), 1.5, 2500.0}
      :mnesia.dirty_write(record)

      result = EngagementTracker.get_user_lp_balances(user_id)
      assert result == %{bsol: 1.5, bbux: 2500.0}
    end
  end

  # ============================================================================
  # get_user_bsol_balance Tests
  # ============================================================================

  describe "get_user_bsol_balance/1" do
    test "returns 0.0 for unknown user" do
      assert EngagementTracker.get_user_bsol_balance(999_999) == 0.0
    end

    test "returns stored bSOL balance" do
      user_id = 43
      record = {:user_lp_balances, user_id, "wallet1", System.system_time(:second), 3.14, 0.0}
      :mnesia.dirty_write(record)

      assert EngagementTracker.get_user_bsol_balance(user_id) == 3.14
    end

    test "handles nil bsol_balance gracefully" do
      user_id = 44
      record = {:user_lp_balances, user_id, "wallet1", System.system_time(:second), nil, 100.0}
      :mnesia.dirty_write(record)

      assert EngagementTracker.get_user_bsol_balance(user_id) == 0.0
    end
  end

  # ============================================================================
  # get_user_bbux_balance Tests
  # ============================================================================

  describe "get_user_bbux_balance/1" do
    test "returns 0.0 for unknown user" do
      assert EngagementTracker.get_user_bbux_balance(999_999) == 0.0
    end

    test "returns stored bBUX balance" do
      user_id = 45
      record = {:user_lp_balances, user_id, "wallet1", System.system_time(:second), 0.0, 7777.0}
      :mnesia.dirty_write(record)

      assert EngagementTracker.get_user_bbux_balance(user_id) == 7777.0
    end

    test "handles nil bbux_balance gracefully" do
      user_id = 46
      record = {:user_lp_balances, user_id, "wallet1", System.system_time(:second), 5.0, nil}
      :mnesia.dirty_write(record)

      assert EngagementTracker.get_user_bbux_balance(user_id) == 0.0
    end
  end

  # ============================================================================
  # update_user_bsol_balance Tests
  # ============================================================================

  describe "update_user_bsol_balance/3" do
    test "creates new record when none exists" do
      user_id = 50
      wallet = "NewWallet123"

      assert {:ok, 2.5} = EngagementTracker.update_user_bsol_balance(user_id, wallet, 2.5)

      result = EngagementTracker.get_user_lp_balances(user_id)
      assert result.bsol == 2.5
      assert result.bbux == 0.0
    end

    test "updates existing record preserving bbux balance" do
      user_id = 51
      wallet = "ExistingWallet"

      # Create initial record with both balances
      record = {:user_lp_balances, user_id, wallet, System.system_time(:second), 1.0, 500.0}
      :mnesia.dirty_write(record)

      # Update only bsol
      assert {:ok, 3.0} = EngagementTracker.update_user_bsol_balance(user_id, wallet, 3.0)

      result = EngagementTracker.get_user_lp_balances(user_id)
      assert result.bsol == 3.0
      assert result.bbux == 500.0
    end

    test "updates wallet address on existing record" do
      user_id = 52
      old_wallet = "OldWallet"
      new_wallet = "NewWallet"

      record = {:user_lp_balances, user_id, old_wallet, System.system_time(:second), 1.0, 0.0}
      :mnesia.dirty_write(record)

      assert {:ok, 2.0} = EngagementTracker.update_user_bsol_balance(user_id, new_wallet, 2.0)

      # Read raw record to check wallet was updated
      [raw] = :mnesia.dirty_read({:user_lp_balances, user_id})
      assert elem(raw, 2) == new_wallet
    end

    test "handles integer input" do
      user_id = 53
      assert {:ok, balance} = EngagementTracker.update_user_bsol_balance(user_id, "w", 10)
      assert is_float(balance)
      assert balance == 10.0
    end

    test "handles string input" do
      user_id = 54
      assert {:ok, balance} = EngagementTracker.update_user_bsol_balance(user_id, "w", "5.5")
      assert balance == 5.5
    end
  end

  # ============================================================================
  # update_user_bbux_balance Tests
  # ============================================================================

  describe "update_user_bbux_balance/3" do
    test "creates new record when none exists" do
      user_id = 60
      wallet = "NewBBUXWallet"

      assert {:ok, 1000.0} = EngagementTracker.update_user_bbux_balance(user_id, wallet, 1000.0)

      result = EngagementTracker.get_user_lp_balances(user_id)
      assert result.bsol == 0.0
      assert result.bbux == 1000.0
    end

    test "updates existing record preserving bsol balance" do
      user_id = 61
      wallet = "ExistingBBUXWallet"

      record = {:user_lp_balances, user_id, wallet, System.system_time(:second), 5.0, 100.0}
      :mnesia.dirty_write(record)

      assert {:ok, 200.0} = EngagementTracker.update_user_bbux_balance(user_id, wallet, 200.0)

      result = EngagementTracker.get_user_lp_balances(user_id)
      assert result.bsol == 5.0
      assert result.bbux == 200.0
    end

    test "handles zero balance" do
      user_id = 62
      assert {:ok, 0.0} = EngagementTracker.update_user_bbux_balance(user_id, "w", 0)
    end
  end

  # ============================================================================
  # Concurrent Update Tests
  # ============================================================================

  describe "concurrent updates" do
    test "sequential updates to both LP types work correctly" do
      user_id = 70
      wallet = "ConcurrentWallet"

      assert {:ok, 1.0} = EngagementTracker.update_user_bsol_balance(user_id, wallet, 1.0)
      assert {:ok, 500.0} = EngagementTracker.update_user_bbux_balance(user_id, wallet, 500.0)
      assert {:ok, 2.0} = EngagementTracker.update_user_bsol_balance(user_id, wallet, 2.0)

      result = EngagementTracker.get_user_lp_balances(user_id)
      assert result.bsol == 2.0
      assert result.bbux == 500.0
    end
  end
end
