defmodule BlocksterV2.Migration.LegacyBuxTest do
  use BlocksterV2.DataCase, async: false

  alias BlocksterV2.Migration.LegacyBux
  alias BlocksterV2.Migration.LegacyBuxMigration
  alias BlocksterV2.Repo

  setup do
    # Create a pending migration record
    {:ok, migration} =
      Repo.insert(%LegacyBuxMigration{
        email: "test@example.com",
        legacy_bux_balance: Decimal.new("500"),
        legacy_wallet_address: "0xOldEvmWallet123"
      })

    # Create a completed migration record
    {:ok, completed} =
      Repo.insert(%LegacyBuxMigration{
        email: "done@example.com",
        legacy_bux_balance: Decimal.new("200"),
        legacy_wallet_address: "0xOldEvmWallet456",
        new_wallet_address: "SolanaWallet456",
        mint_tx_signature: "5xSig123",
        migrated: true,
        migrated_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

    %{migration: migration, completed: completed}
  end

  describe "find_pending_migration/1" do
    test "finds pending migration by email", %{migration: migration} do
      result = LegacyBux.find_pending_migration("test@example.com")
      assert result != nil
      assert result.id == migration.id
      assert result.migrated == false
    end

    test "returns nil for already migrated", %{completed: _completed} do
      assert nil == LegacyBux.find_pending_migration("done@example.com")
    end

    test "returns nil for unknown email" do
      assert nil == LegacyBux.find_pending_migration("unknown@example.com")
    end

    test "case insensitive email matching", %{migration: migration} do
      result = LegacyBux.find_pending_migration("TEST@EXAMPLE.COM")
      assert result != nil
      assert result.id == migration.id
    end
  end

  describe "create_migration_record/1" do
    test "creates new record" do
      {:ok, record} = LegacyBux.create_migration_record(%{
        email: "new@example.com",
        legacy_bux_balance: 1000,
        legacy_wallet_address: "0xNewWallet"
      })

      assert record.email == "new@example.com"
      assert record.legacy_bux_balance == Decimal.new("1000")
      assert record.migrated == false
    end

    test "normalizes email to lowercase" do
      {:ok, record} = LegacyBux.create_migration_record(%{
        email: "UPPER@CASE.COM",
        legacy_bux_balance: 100
      })

      assert record.email == "upper@case.com"
    end

    test "does not create duplicate for same email" do
      # First one exists from setup
      result = LegacyBux.create_migration_record(%{
        email: "test@example.com",
        legacy_bux_balance: 999
      })

      # on_conflict: :nothing means it returns ok but doesn't insert
      assert {:ok, _} = result
    end
  end

  describe "migration_stats/0" do
    test "returns correct counts", %{migration: _m, completed: _c} do
      stats = LegacyBux.migration_stats()

      assert stats.total == 2
      assert stats.migrated == 1
      assert stats.pending == 1
    end
  end

  describe "claim_legacy_bux/3" do
    test "returns :not_found for invalid ID" do
      assert {:error, :not_found} = LegacyBux.claim_legacy_bux(999_999, "wallet", 1)
    end

    test "returns :already_claimed for migrated record", %{completed: completed} do
      assert {:error, :already_claimed} = LegacyBux.claim_legacy_bux(completed.id, "wallet", 1)
    end

    test "returns :zero_balance for zero-balance record" do
      {:ok, zero_record} =
        Repo.insert(%LegacyBuxMigration{
          email: "zero@example.com",
          legacy_bux_balance: Decimal.new("0")
        })

      assert {:error, :zero_balance} = LegacyBux.claim_legacy_bux(zero_record.id, "wallet", 1)
    end

    # Note: successful claim test requires a running settler service,
    # so we test the error path (mint fails with :not_configured in test env)
    test "returns error when minter not configured", %{migration: migration} do
      # In test env, settler secret is typically not set
      old = Application.get_env(:blockster_v2, :settler_secret)
      old_legacy = Application.get_env(:blockster_v2, :bux_minter_secret)
      Application.put_env(:blockster_v2, :settler_secret, nil)
      Application.put_env(:blockster_v2, :bux_minter_secret, nil)
      System.delete_env("BLOCKSTER_SETTLER_SECRET")
      System.delete_env("BUX_MINTER_SECRET")

      assert {:error, :not_configured} = LegacyBux.claim_legacy_bux(migration.id, "SolWallet123", 1)

      # Record should NOT be marked as migrated
      record = Repo.get!(LegacyBuxMigration, migration.id)
      assert record.migrated == false

      if old, do: Application.put_env(:blockster_v2, :settler_secret, old)
      if old_legacy, do: Application.put_env(:blockster_v2, :bux_minter_secret, old_legacy)
    end
  end
end
