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

  ## What this migration does

  For every row in `airdrop_winners`:

  1. If `user_id` is set:
     - Follow the `merged_into_user_id` chain to the final active user.
     - If the final user's `wallet_address` differs from
       `winner.wallet_address`, update `winner.wallet_address` in place.
       The original EVM address moves to `external_wallet` (if empty)
       so the audit trail survives.

  2. If `user_id` is NULL:
     - Try a case-insensitive lookup against `users.wallet_address`
       (EVM addresses are case-insensitive as hex).
     - If a user is found with a merge chain terminating in a Solana
       user, apply the same rewrite.

  3. Log unresolvable rows (no user match, no merge chain, or stuck at
     a non-Solana address). These stay as-is.

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
  """

  use Ecto.Migration

  import Ecto.Query
  require Logger

  @max_merge_depth 10

  def up do
    dry_run? = System.get_env("AIRDROP_WINNER_BACKFILL_DRY_RUN") == "1"
    Logger.info("[BackfillWinnerSolanaAddresses] Starting (dry_run=#{dry_run?})")

    repo = repo()

    winners =
      from(w in "airdrop_winners",
        select: %{
          id: w.id,
          user_id: w.user_id,
          wallet_address: w.wallet_address,
          external_wallet: w.external_wallet
        }
      )
      |> repo.all()

    users_by_id = load_users_by_id(repo)
    users_by_wallet = index_by_wallet_ci(users_by_id)

    stats = %{checked: 0, rewritten: 0, already_solana: 0, unresolved: 0, no_change: 0}

    stats =
      Enum.reduce(winners, stats, fn w, acc ->
        final_wallet =
          resolve_final_wallet(w, users_by_id, users_by_wallet)

        case final_wallet do
          nil ->
            Logger.info(
              "[BackfillWinnerSolanaAddresses] UNRESOLVED winner id=#{w.id} user_id=#{inspect(w.user_id)} wallet=#{w.wallet_address}"
            )
            %{acc | checked: acc.checked + 1, unresolved: acc.unresolved + 1}

          same when same == w.wallet_address ->
            %{acc | checked: acc.checked + 1, no_change: acc.no_change + 1}

          solana when is_binary(solana) ->
            if looks_like_solana?(solana) do
              Logger.info(
                "[BackfillWinnerSolanaAddresses] #{(dry_run? && "WOULD REWRITE") || "REWRITE"} winner id=#{w.id} old=#{w.wallet_address} new=#{solana}"
              )

              unless dry_run? do
                external =
                  if (w.external_wallet || "") == "", do: w.wallet_address, else: w.external_wallet

                repo.update_all(
                  from(aw in "airdrop_winners", where: aw.id == ^w.id),
                  set: [wallet_address: solana, external_wallet: external]
                )
              end

              %{acc | checked: acc.checked + 1, rewritten: acc.rewritten + 1}
            else
              Logger.info(
                "[BackfillWinnerSolanaAddresses] SKIP non-Solana target winner id=#{w.id} user_id=#{inspect(w.user_id)} proposed=#{solana}"
              )
              %{acc | checked: acc.checked + 1, already_solana: acc.already_solana + 1}
            end
        end
      end)

    Logger.info(
      "[BackfillWinnerSolanaAddresses] Done. stats=#{inspect(stats)} dry_run=#{dry_run?}"
    )
  end

  def down do
    # Data migration — can't distinguish originally-Solana rows from ones
    # this migration rewrote. Restore from pre-migration pg_dump if
    # rollback is ever required. See moduledoc.
    :ok
  end

  defp load_users_by_id(repo) do
    from(u in "users",
      select: %{
        id: u.id,
        wallet_address: u.wallet_address,
        merged_into_user_id: u.merged_into_user_id,
        is_active: u.is_active
      }
    )
    |> repo.all()
    |> Enum.into(%{}, fn u -> {u.id, u} end)
  end

  defp index_by_wallet_ci(users_by_id) do
    Enum.reduce(users_by_id, %{}, fn {_id, u}, acc ->
      case u.wallet_address do
        nil -> acc
        addr -> Map.put(acc, String.downcase(addr), u)
      end
    end)
  end

  defp resolve_final_wallet(winner, users_by_id, users_by_wallet) do
    user =
      cond do
        is_integer(winner.user_id) -> Map.get(users_by_id, winner.user_id)
        is_binary(winner.wallet_address) ->
          Map.get(users_by_wallet, String.downcase(winner.wallet_address))
        true -> nil
      end

    case follow_merge_chain(user, users_by_id, @max_merge_depth) do
      nil -> nil
      final_user -> final_user.wallet_address
    end
  end

  defp follow_merge_chain(nil, _users_by_id, _depth), do: nil
  defp follow_merge_chain(user, _users_by_id, 0), do: user

  defp follow_merge_chain(user, users_by_id, depth) do
    case user.merged_into_user_id do
      nil ->
        user

      next_id when is_integer(next_id) ->
        case Map.get(users_by_id, next_id) do
          nil -> user
          next -> follow_merge_chain(next, users_by_id, depth - 1)
        end
    end
  end

  # Crude Solana-pubkey detector: base58 alphabet + length ≥ 32 ≤ 48.
  # EVM addresses start with `0x` and are 42 chars — they fail this.
  defp looks_like_solana?(addr) when is_binary(addr) do
    len = String.length(addr)
    len >= 32 and len <= 48 and
      not String.starts_with?(addr, "0x") and
      Regex.match?(~r/^[1-9A-HJ-NP-Za-km-z]+$/, addr)
  end

  defp looks_like_solana?(_), do: false
end
