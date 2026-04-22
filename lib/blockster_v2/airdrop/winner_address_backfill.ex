defmodule BlocksterV2.Airdrop.WinnerAddressBackfill do
  @moduledoc """
  Library that powers the 20260422223000 data migration
  (`BlocksterV2.Repo.Migrations.BackfillWinnerSolanaAddresses`).

  Extracted so the logic is testable via normal `mix test` — migrations
  themselves aren't part of the compile path.

  See `docs/bug_audit_2026_04_22.md § AIRDROP-02` for the why and the
  migration moduledoc for operator runbook notes.
  """

  import Ecto.Query
  require Logger

  @max_merge_depth 10

  @doc """
  Runs the backfill against the given `Ecto.Repo`. Returns a stats map:

      %{checked: n, rewritten: n, already_solana: n, unresolved: n, no_change: n}

  Respects `AIRDROP_WINNER_BACKFILL_DRY_RUN=1` — dry-run logs without
  mutating.
  """
  @spec run(module()) :: map()
  def run(repo) do
    dry_run? = System.get_env("AIRDROP_WINNER_BACKFILL_DRY_RUN") == "1"
    Logger.info("[WinnerAddressBackfill] Starting (dry_run=#{dry_run?})")

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
        final_wallet = resolve_final_wallet(w, users_by_id, users_by_wallet)

        case final_wallet do
          nil ->
            Logger.info(
              "[WinnerAddressBackfill] UNRESOLVED winner id=#{w.id} user_id=#{inspect(w.user_id)} wallet=#{w.wallet_address}"
            )
            %{acc | checked: acc.checked + 1, unresolved: acc.unresolved + 1}

          same when same == w.wallet_address ->
            %{acc | checked: acc.checked + 1, no_change: acc.no_change + 1}

          solana when is_binary(solana) ->
            if looks_like_solana?(solana) do
              Logger.info(
                "[WinnerAddressBackfill] #{(dry_run? && "WOULD REWRITE") || "REWRITE"} winner id=#{w.id} old=#{w.wallet_address} new=#{solana}"
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
                "[WinnerAddressBackfill] SKIP non-Solana target winner id=#{w.id} user_id=#{inspect(w.user_id)} proposed=#{solana}"
              )
              %{acc | checked: acc.checked + 1, already_solana: acc.already_solana + 1}
            end
        end
      end)

    Logger.info("[WinnerAddressBackfill] Done. stats=#{inspect(stats)} dry_run=#{dry_run?}")
    stats
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

  @doc """
  Crude Solana-pubkey detector: base58 alphabet + length ≥ 32 ≤ 48.
  EVM addresses start with `0x` and are 42 chars — they fail this.
  Exposed for testing.
  """
  def looks_like_solana?(addr) when is_binary(addr) do
    len = String.length(addr)
    len >= 32 and len <= 48 and
      not String.starts_with?(addr, "0x") and
      Regex.match?(~r/^[1-9A-HJ-NP-Za-km-z]+$/, addr)
  end

  def looks_like_solana?(_), do: false
end
