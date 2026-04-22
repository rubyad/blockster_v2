defmodule BlocksterV2.Repo.Migrations.BackfillWinnerSolanaAddressesTest do
  @moduledoc """
  Regression coverage for AIRDROP-02's winner-address backfill migration.

  Inserts raw `users` + `airdrop_winners` rows (bypassing the Ecto
  schemas so we don't trip `is_active`/fingerprint validation), runs
  the migration's `up/0`, and asserts the wallet rewrites against the
  merge chain.
  """

  use BlocksterV2.DataCase, async: false

  alias Ecto.Adapters.SQL
  alias BlocksterV2.Repo

  @solana_addr_a "EPhSojGV2NNMDh8dR2NUYA41eDPib3ey35c7pRhUnXoo"
  @solana_addr_b "5zBtyrkn7BXrN66G3QyaQvxdEEWoPuZKmQFr88dQtqUY"
  @evm_addr_a "0x1111111111111111111111111111111111111111"
  @evm_addr_b "0x2222222222222222222222222222222222222222"

  defp insert_user!(attrs) do
    # Use a direct SQL insert — Accounts.User changeset requires fields
    # (is_active, phone_verified, etc.) we don't need here, and the
    # migration only reads raw columns from `users`.
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    defaults = %{
      username: "mig_user_#{System.unique_integer([:positive])}",
      email: nil,
      wallet_address: nil,
      smart_wallet_address: nil,
      merged_into_user_id: nil,
      is_active: true,
      inserted_at: now,
      updated_at: now
    }

    merged = Map.merge(defaults, attrs)
    cols = Map.keys(merged)
    values = Enum.map(cols, &Map.get(merged, &1))
    col_list = cols |> Enum.map(&Atom.to_string/1) |> Enum.join(", ")
    placeholders = 1..length(cols) |> Enum.map(&"$#{&1}") |> Enum.join(", ")

    %{rows: [[id]]} =
      SQL.query!(Repo, "INSERT INTO users (#{col_list}) VALUES (#{placeholders}) RETURNING id", values)

    id
  end

  defp insert_winner!(attrs) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    defaults = %{
      round_id: 1,
      winner_index: 0,
      random_number: 1,
      wallet_address: @evm_addr_a,
      external_wallet: nil,
      deposit_start: 0,
      deposit_end: 100,
      deposit_amount: 100,
      prize_usd: 1000,
      prize_usdt: 1000,
      prize_registered: false,
      claimed: false,
      user_id: nil,
      inserted_at: now,
      updated_at: now
    }

    merged = Map.merge(defaults, attrs)
    cols = Map.keys(merged)
    values = Enum.map(cols, &Map.get(merged, &1))
    col_list = cols |> Enum.map(&Atom.to_string/1) |> Enum.join(", ")
    placeholders = 1..length(cols) |> Enum.map(&"$#{&1}") |> Enum.join(", ")

    %{rows: [[id]]} =
      SQL.query!(Repo, "INSERT INTO airdrop_winners (#{col_list}) VALUES (#{placeholders}) RETURNING id", values)

    id
  end

  defp get_winner!(id) do
    %{rows: [[wallet, external]]} =
      SQL.query!(
        Repo,
        "SELECT wallet_address, external_wallet FROM airdrop_winners WHERE id = $1",
        [id]
      )

    %{wallet_address: wallet, external_wallet: external}
  end

  describe "BackfillWinnerSolanaAddresses.up/0" do
    test "rewrites EVM address to Solana when user_id points to migrated user" do
      legacy_user_id = insert_user!(%{wallet_address: @evm_addr_a})

      solana_user_id =
        insert_user!(%{
          username: "mig_user_solana_#{System.unique_integer([:positive])}",
          wallet_address: @solana_addr_a
        })

      # Mark the legacy user as merged into the Solana user.
      SQL.query!(Repo, "UPDATE users SET merged_into_user_id = $1 WHERE id = $2", [
        solana_user_id,
        legacy_user_id
      ])

      winner_id =
        insert_winner!(%{user_id: legacy_user_id, wallet_address: @evm_addr_a})

      BlocksterV2.Airdrop.WinnerAddressBackfill.run(Repo)

      updated = get_winner!(winner_id)
      assert updated.wallet_address == @solana_addr_a
      assert updated.external_wallet == @evm_addr_a
    end

    test "rewrites via merged_into_user_id chain when user_id is NULL but wallet matches" do
      legacy_user_id = insert_user!(%{wallet_address: @evm_addr_b})

      solana_user_id =
        insert_user!(%{
          username: "mig_user_chain_#{System.unique_integer([:positive])}",
          wallet_address: @solana_addr_b
        })

      SQL.query!(Repo, "UPDATE users SET merged_into_user_id = $1 WHERE id = $2", [
        solana_user_id,
        legacy_user_id
      ])

      # Winner row has no user_id — lookup falls back to wallet match.
      winner_id = insert_winner!(%{user_id: nil, wallet_address: @evm_addr_b})

      BlocksterV2.Airdrop.WinnerAddressBackfill.run(Repo)

      updated = get_winner!(winner_id)
      assert updated.wallet_address == @solana_addr_b
      assert updated.external_wallet == @evm_addr_b
    end

    test "leaves Solana addresses untouched (idempotent)" do
      user_id = insert_user!(%{wallet_address: @solana_addr_a})
      winner_id = insert_winner!(%{user_id: user_id, wallet_address: @solana_addr_a})

      BlocksterV2.Airdrop.WinnerAddressBackfill.run(Repo)

      updated = get_winner!(winner_id)
      assert updated.wallet_address == @solana_addr_a
      # external_wallet stays NULL — nothing to migrate from.
      assert updated.external_wallet == nil
    end

    test "leaves winner wallet alone when merge chain terminates in a non-Solana address" do
      # Users chained through a second EVM address (never migrated to
      # Solana) should stay as EVM — the crude base58 guard rejects.
      user_id = insert_user!(%{wallet_address: @evm_addr_b})
      winner_id = insert_winner!(%{user_id: user_id, wallet_address: @evm_addr_a})

      BlocksterV2.Airdrop.WinnerAddressBackfill.run(Repo)

      updated = get_winner!(winner_id)
      assert updated.wallet_address == @evm_addr_a
    end

    test "dry-run mode logs without mutating" do
      legacy_user_id = insert_user!(%{wallet_address: @evm_addr_a})

      solana_user_id =
        insert_user!(%{
          username: "mig_user_dry_#{System.unique_integer([:positive])}",
          wallet_address: @solana_addr_a
        })

      SQL.query!(Repo, "UPDATE users SET merged_into_user_id = $1 WHERE id = $2", [
        solana_user_id,
        legacy_user_id
      ])

      winner_id = insert_winner!(%{user_id: legacy_user_id, wallet_address: @evm_addr_a})

      System.put_env("AIRDROP_WINNER_BACKFILL_DRY_RUN", "1")

      try do
        BlocksterV2.Airdrop.WinnerAddressBackfill.run(Repo)
      after
        System.delete_env("AIRDROP_WINNER_BACKFILL_DRY_RUN")
      end

      updated = get_winner!(winner_id)
      # Dry-run: wallet untouched even though the migration planned a rewrite.
      assert updated.wallet_address == @evm_addr_a
    end
  end
end
