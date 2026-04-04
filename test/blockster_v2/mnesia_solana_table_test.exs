defmodule BlocksterV2.MnesiaSolanaTableTest do
  use BlocksterV2.DataCase, async: false

  # ============================================================================
  # Tests for user_solana_balances Mnesia table schema
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

  describe "user_solana_balances table" do
    test "table exists and is writable" do
      record = {:user_solana_balances, 1, "SomeSolanaPubkey123", System.system_time(:second), 1.5, 100.0}
      assert :ok = :mnesia.dirty_write(record)
    end

    test "primary key is user_id" do
      now = System.system_time(:second)
      :mnesia.dirty_write({:user_solana_balances, 1, "wallet_a", now, 1.0, 100.0})
      :mnesia.dirty_write({:user_solana_balances, 2, "wallet_b", now, 2.0, 200.0})

      assert [{:user_solana_balances, 1, "wallet_a", _, 1.0, 100.0}] =
        :mnesia.dirty_read({:user_solana_balances, 1})

      assert [{:user_solana_balances, 2, "wallet_b", _, 2.0, 200.0}] =
        :mnesia.dirty_read({:user_solana_balances, 2})
    end

    test "writing same user_id overwrites (set type)" do
      now = System.system_time(:second)
      :mnesia.dirty_write({:user_solana_balances, 1, "wallet", now, 1.0, 100.0})
      :mnesia.dirty_write({:user_solana_balances, 1, "wallet", now, 5.0, 500.0})

      records = :mnesia.dirty_read({:user_solana_balances, 1})
      assert length(records) == 1
      [{:user_solana_balances, 1, _, _, sol, bux}] = records
      assert sol == 5.0
      assert bux == 500.0
    end

    test "stores Solana base58 addresses correctly (case-sensitive)" do
      now = System.system_time(:second)
      address = "7CuRyw2YkqQhUUFbw6CCnoedHWT8tK2c9UzZQYDGmxVX"
      :mnesia.dirty_write({:user_solana_balances, 1, address, now, 0.0, 0.0})

      [{:user_solana_balances, 1, stored_address, _, _, _}] =
        :mnesia.dirty_read({:user_solana_balances, 1})

      assert stored_address == address
    end

    test "reading non-existent user returns empty list" do
      assert [] = :mnesia.dirty_read({:user_solana_balances, 999})
    end

    test "can delete records" do
      now = System.system_time(:second)
      :mnesia.dirty_write({:user_solana_balances, 1, "wallet", now, 1.0, 100.0})
      :mnesia.dirty_delete({:user_solana_balances, 1})

      assert [] = :mnesia.dirty_read({:user_solana_balances, 1})
    end

    test "supports float precision for SOL (9 decimals)" do
      now = System.system_time(:second)
      sol_amount = 0.123456789
      :mnesia.dirty_write({:user_solana_balances, 1, "wallet", now, sol_amount, 0.0})

      [{:user_solana_balances, 1, _, _, stored_sol, _}] =
        :mnesia.dirty_read({:user_solana_balances, 1})

      assert_in_delta stored_sol, sol_amount, 1.0e-15
    end

    test "supports large BUX values" do
      now = System.system_time(:second)
      bux_amount = 1_000_000_000.0
      :mnesia.dirty_write({:user_solana_balances, 1, "wallet", now, 0.0, bux_amount})

      [{:user_solana_balances, 1, _, _, _, stored_bux}] =
        :mnesia.dirty_read({:user_solana_balances, 1})

      assert stored_bux == bux_amount
    end
  end

  describe "table independence from user_bux_balances" do
    test "user_solana_balances does not interfere with user_bux_balances" do
      # Set up legacy table
      legacy_attrs = [
        :user_id, :user_smart_wallet, :updated_at, :aggregate_bux_balance,
        :bux_balance, :moonbux_balance, :neobux_balance, :roguebux_balance,
        :flarebux_balance, :nftbux_balance, :nolchabux_balance, :solbux_balance,
        :spacebux_balance, :tronbux_balance, :tranbux_balance
      ]

      case :mnesia.create_table(:user_bux_balances, [
             attributes: legacy_attrs,
             ram_copies: [node()],
             type: :set
           ]) do
        {:atomic, :ok} -> :ok
        {:aborted, {:already_exists, :user_bux_balances}} ->
          case :mnesia.add_table_copy(:user_bux_balances, node(), :ram_copies) do
            {:atomic, :ok} -> :ok
            {:aborted, {:already_exists, :user_bux_balances, _}} -> :ok
          end
          :mnesia.clear_table(:user_bux_balances)
      end

      now = System.system_time(:second)

      # Write to Solana table
      :mnesia.dirty_write({:user_solana_balances, 1, "solana_wallet", now, 5.0, 1000.0})

      # Write to legacy table
      :mnesia.dirty_write({:user_bux_balances, 1, "evm_wallet", now, 500.0, 500.0,
        0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0})

      # Verify they are independent
      [{:user_solana_balances, 1, "solana_wallet", _, 5.0, 1000.0}] =
        :mnesia.dirty_read({:user_solana_balances, 1})

      [{:user_bux_balances, 1, "evm_wallet", _, 500.0, 500.0, _, _, _, _, _, _, _, _, _, _}] =
        :mnesia.dirty_read({:user_bux_balances, 1})
    end
  end
end
