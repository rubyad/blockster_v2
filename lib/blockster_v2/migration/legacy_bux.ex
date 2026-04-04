defmodule BlocksterV2.Migration.LegacyBux do
  @moduledoc """
  Handles migration of BUX balances from Rogue Chain (EVM) to Solana.

  Legacy users who signed up with email on the old system can claim their
  BUX balance on Solana by verifying their email address on the new system.

  Flow:
  1. Admin snapshots current user_bux_balances (Mnesia) into PostgreSQL
  2. New user verifies email → system checks for matching legacy account
  3. User clicks "Claim BUX" → system mints SPL BUX to their Solana wallet
  4. Migration record marked as migrated (one-time)
  """

  alias BlocksterV2.Repo
  alias BlocksterV2.Migration.LegacyBuxMigration
  alias BlocksterV2.BuxMinter
  import Ecto.Query
  require Logger

  @doc """
  Looks up a pending (unclaimed) legacy BUX migration record by email.
  Returns nil if no record exists or already migrated.
  """
  def find_pending_migration(email) do
    email = String.trim(email) |> String.downcase()

    Repo.one(
      from m in LegacyBuxMigration,
        where: m.email == ^email,
        where: m.migrated == false
    )
  end

  @doc """
  Claims the legacy BUX balance by minting SPL BUX to the user's Solana wallet.

  Returns {:ok, migration} on success, {:error, reason} on failure.
  """
  def claim_legacy_bux(migration_id, wallet_address, user_id) do
    case Repo.get(LegacyBuxMigration, migration_id) do
      nil ->
        {:error, :not_found}

      %{migrated: true} ->
        {:error, :already_claimed}

      migration ->
        amount = Decimal.to_float(migration.legacy_bux_balance)

        if amount <= 0 do
          {:error, :zero_balance}
        else
          case BuxMinter.mint_bux(wallet_address, amount, user_id, nil, :signup) do
            {:ok, response} ->
              signature = response["signature"]
              now = DateTime.utc_now() |> DateTime.truncate(:second)

              migration
              |> Ecto.Changeset.change(%{
                new_wallet_address: wallet_address,
                mint_tx_signature: signature,
                migrated: true,
                migrated_at: now
              })
              |> Repo.update()

            {:error, reason} ->
              Logger.error("[LegacyBux] Mint failed for migration #{migration_id}: #{inspect(reason)}")
              {:error, reason}
          end
        end
    end
  end

  @doc """
  Creates a legacy BUX migration record for a user.
  Used during the snapshot phase to populate the migration table.
  """
  def create_migration_record(attrs) do
    %LegacyBuxMigration{}
    |> LegacyBuxMigration.changeset(attrs)
    |> Repo.insert(on_conflict: :nothing, conflict_target: :email)
  end

  @doc """
  Snapshots a single user's BUX balance into the migration table.
  Called by admin or batch process.
  """
  def snapshot_user(user) do
    if user.email && user.email != "" do
      bux_balance = BlocksterV2.EngagementTracker.get_user_bux_balance(user.id)

      if bux_balance > 0 do
        create_migration_record(%{
          email: String.downcase(user.email),
          legacy_bux_balance: bux_balance,
          legacy_wallet_address: user.smart_wallet_address || user.wallet_address
        })
      else
        {:ok, :zero_balance}
      end
    else
      {:ok, :no_email}
    end
  end

  @doc """
  Returns stats about the legacy migration.
  """
  def migration_stats do
    total = Repo.aggregate(LegacyBuxMigration, :count)
    migrated = Repo.one(from m in LegacyBuxMigration, where: m.migrated == true, select: count())
    pending = total - migrated

    total_bux = Repo.one(
      from m in LegacyBuxMigration,
        select: coalesce(sum(m.legacy_bux_balance), 0)
    ) || Decimal.new(0)

    claimed_bux = Repo.one(
      from m in LegacyBuxMigration,
        where: m.migrated == true,
        select: coalesce(sum(m.legacy_bux_balance), 0)
    ) || Decimal.new(0)

    %{
      total: total,
      migrated: migrated,
      pending: pending,
      total_bux: total_bux,
      claimed_bux: claimed_bux
    }
  end
end
