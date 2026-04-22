defmodule BlocksterV2.Repo.Migrations.BackfillWinnerSolanaAddresses do
  @moduledoc """
  AIRDROP-02 — rewrite legacy EVM-style winner wallet addresses on the
  `airdrop_winners` table to the Solana address the user now uses.

  ## Why

  During the 2026 Solana migration, users who originally auth'd via an
  EVM wallet were migrated to a Solana wallet via `LegacyMerge.merge_legacy_into!`.
  The legacy user row gets `merged_into_user_id` pointing at the new
  Solana user; the new user's `wallet_address` is the Solana base58.

  The `airdrop_winners` rows captured at the time of an earlier round
  still hold the EVM-era `wallet_address` (0x…). The /airdrop page
  renders these directly, so users see 0x-prefixed hex on a Solana-era
  page even though their current wallet is Solana. The audit captured
  this as AIRDROP-02.

  ## Dry-run mode

  Set `AIRDROP_WINNER_BACKFILL_DRY_RUN=1` in the environment to log the
  planned rewrites WITHOUT touching the DB. Run once in dry-run to
  capture the log, then run for real after reviewing.

      AIRDROP_WINNER_BACKFILL_DRY_RUN=1 mix ecto.migrate

  ## Rollback

  `down/0` is a no-op. Data mutation only; we can't distinguish an
  originally-Solana address from one this migration wrote. Back up
  the `airdrop_winners` table (`pg_dump -t airdrop_winners …`) BEFORE
  running this migration. If rollback is required, restore from that
  dump — `mix ecto.rollback` will NOT undo the data change.

  Do NOT run this migration without an operator backup in hand. The
  migration is idempotent under re-run (rewriting a Solana-matching
  address is a no-op) but destructive in the first pass.

  Logic lives in `BlocksterV2.Airdrop.WinnerAddressBackfill` so it's
  testable via normal `mix test` — migrations themselves aren't on
  the compile path.
  """

  use Ecto.Migration

  def up do
    BlocksterV2.Airdrop.WinnerAddressBackfill.run(repo())
  end

  def down do
    # Data migration — can't distinguish originally-Solana rows from ones
    # this migration rewrote. Restore from pre-migration pg_dump if
    # rollback is ever required. See moduledoc.
    :ok
  end
end
