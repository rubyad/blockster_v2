defmodule BlocksterV2.BuxBoosterStats.Backfill do
  @moduledoc """
  One-time backfill of user_betting_stats for ALL existing users.
  Creates records for every user (with zeros for those who haven't bet).
  Populates historical bet data from bux_booster_onchain_games Mnesia table.

  ## Usage

  Run once after deploying the new table:

      BlocksterV2.BuxBoosterStats.Backfill.run()

  To check progress:

      BlocksterV2.BuxBoosterStats.Backfill.status()
  """

  require Logger

  alias BlocksterV2.Repo
  alias BlocksterV2.Accounts.User
  import Ecto.Query

  @doc """
  Run the backfill process.
  Creates user_betting_stats records for ALL users in PostgreSQL.
  Populates historical data from settled games in Mnesia.
  """
  def run do
    Logger.info("[Backfill] Starting user_betting_stats backfill...")

    # Step 1: Get ALL users from PostgreSQL (one-time read)
    all_users =
      Repo.all(
        from u in User,
          select: %{id: u.id, wallet_address: u.smart_wallet_address}
      )

    user_count = length(all_users)
    Logger.info("[Backfill] Found #{user_count} users in PostgreSQL")

    # Step 2: Get all settled games from Mnesia
    all_games =
      :mnesia.dirty_match_object(
        {:bux_booster_onchain_games, :_, :_, :_, :_, :_, :_, :settled, :_, :_, :_, :_, :_, :_, :_,
         :_, :_, :_, :_, :_, :_, :_}
      )

    game_count = length(all_games)
    Logger.info("[Backfill] Found #{game_count} settled games in Mnesia")

    # Step 3: Group games by user_id
    games_by_user = Enum.group_by(all_games, fn game -> elem(game, 2) end)

    # Step 4: Create a record for EVERY user
    now = System.system_time(:millisecond)

    {created, skipped} =
      Enum.reduce(all_users, {0, 0}, fn user, {created_count, skipped_count} ->
        # Check if record already exists
        case :mnesia.dirty_read(:user_betting_stats, user.id) do
          [_existing] ->
            # Record exists, skip
            {created_count, skipped_count + 1}

          [] ->
            # Create new record
            games = Map.get(games_by_user, user.id, [])

            record =
              if Enum.empty?(games) do
                create_empty_record(user.id, user.wallet_address, now)
              else
                calculate_stats_from_games(user.id, user.wallet_address, games, now)
              end

            :mnesia.dirty_write(record)
            {created_count + 1, skipped_count}
        end
      end)

    users_with_bets = map_size(games_by_user)
    users_without_bets = user_count - users_with_bets

    Logger.info("[Backfill] Complete!")
    Logger.info("[Backfill]   - #{created} new records created")
    Logger.info("[Backfill]   - #{skipped} existing records skipped")
    Logger.info("[Backfill]   - #{users_with_bets} users have betting history")
    Logger.info("[Backfill]   - #{users_without_bets} users have zero bets")

    {:ok,
     %{
       total_users: user_count,
       created: created,
       skipped: skipped,
       users_with_bets: users_with_bets,
       users_without_bets: users_without_bets,
       total_games: game_count
     }}
  end

  @doc """
  Check backfill status - how many users have records vs how many exist.
  """
  def status do
    # Count users in PostgreSQL
    pg_user_count = Repo.aggregate(User, :count, :id)

    # Count records in Mnesia
    mnesia_count =
      try do
        :mnesia.table_info(:user_betting_stats, :size)
      rescue
        _ -> 0
      end

    # Count users with bets
    users_with_bets =
      try do
        :mnesia.dirty_match_object(
          {:user_betting_stats, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_,
           :_, :_, :_, :_}
        )
        |> Enum.count(fn record -> elem(record, 3) > 0 or elem(record, 10) > 0 end)
      rescue
        _ -> 0
      end

    %{
      postgresql_users: pg_user_count,
      mnesia_records: mnesia_count,
      coverage_percent: if(pg_user_count > 0, do: Float.round(mnesia_count / pg_user_count * 100, 1), else: 0),
      users_with_bets: users_with_bets,
      needs_backfill: mnesia_count < pg_user_count
    }
  end

  @doc """
  Create a single user's betting stats record.
  Useful for manually creating a record for a specific user.
  """
  def create_for_user(user_id) when is_integer(user_id) do
    case Repo.get(User, user_id) do
      nil ->
        {:error, :user_not_found}

      user ->
        # Check if record exists
        case :mnesia.dirty_read(:user_betting_stats, user_id) do
          [_existing] ->
            {:error, :already_exists}

          [] ->
            now = System.system_time(:millisecond)

            games =
              :mnesia.dirty_index_read(:bux_booster_onchain_games, user_id, :user_id)
              |> Enum.filter(fn game -> elem(game, 7) == :settled end)

            record =
              if Enum.empty?(games) do
                create_empty_record(user_id, user.smart_wallet_address, now)
              else
                calculate_stats_from_games(user_id, user.smart_wallet_address, games, now)
              end

            :mnesia.dirty_write(record)
            {:ok, :created}
        end
    end
  end

  # ============ Private Helpers ============

  defp create_empty_record(user_id, wallet_address, now) do
    {:user_betting_stats, user_id, wallet_address || "",
     # BUX stats (all zeros)
     0, 0, 0, 0, 0, 0, 0,
     # ROGUE stats (all zeros)
     0, 0, 0, 0, 0, 0, 0,
     # first_bet_at, last_bet_at, updated_at
     nil, nil, now,
     # onchain_stats_cache (nil until admin refreshes)
     nil}
  end

  defp calculate_stats_from_games(user_id, wallet_address, games, now) do
    # Separate BUX and ROGUE games
    # Token is at index 9 in bux_booster_onchain_games
    bux_games = Enum.filter(games, fn g -> elem(g, 9) == "BUX" end)
    rogue_games = Enum.filter(games, fn g -> elem(g, 9) == "ROGUE" end)

    bux = aggregate_games(bux_games)
    rogue = aggregate_games(rogue_games)

    # Get first and last bet timestamps
    # created_at is at index 20, settled_at is at index 21
    all_timestamps = games |> Enum.map(&elem(&1, 20)) |> Enum.reject(&is_nil/1)

    first_bet =
      if Enum.empty?(all_timestamps), do: nil, else: Enum.min(all_timestamps)

    last_bet =
      if Enum.empty?(all_timestamps), do: nil, else: Enum.max(all_timestamps)

    {:user_betting_stats, user_id, wallet_address || "", bux.total_bets, bux.wins, bux.losses,
     bux.total_wagered, bux.total_winnings, bux.total_losses, bux.net_pnl, rogue.total_bets,
     rogue.wins, rogue.losses, rogue.total_wagered, rogue.total_winnings, rogue.total_losses,
     rogue.net_pnl, first_bet, last_bet, now,
     # onchain_stats_cache (nil until admin refreshes)
     nil}
  end

  defp aggregate_games([]) do
    %{
      total_bets: 0,
      wins: 0,
      losses: 0,
      total_wagered: 0,
      total_winnings: 0,
      total_losses: 0,
      net_pnl: 0
    }
  end

  defp aggregate_games(games) do
    Enum.reduce(
      games,
      %{
        total_bets: 0,
        wins: 0,
        losses: 0,
        total_wagered: 0,
        total_winnings: 0,
        total_losses: 0,
        net_pnl: 0
      },
      fn game, acc ->
        # bet_amount is at index 11, won is at index 15, payout is at index 16
        bet_amount = to_wei(elem(game, 11))
        won = elem(game, 15)
        payout = to_wei(elem(game, 16))

        winnings = if won, do: payout - bet_amount, else: 0
        losses = if won, do: 0, else: bet_amount
        net_change = if won, do: payout - bet_amount, else: -bet_amount

        %{
          acc
          | total_bets: acc.total_bets + 1,
            wins: acc.wins + if(won, do: 1, else: 0),
            losses: acc.losses + if(won, do: 0, else: 1),
            total_wagered: acc.total_wagered + bet_amount,
            total_winnings: acc.total_winnings + winnings,
            total_losses: acc.total_losses + losses,
            net_pnl: acc.net_pnl + net_change
        }
      end
    )
  end

  defp to_wei(nil), do: 0
  defp to_wei(amount) when is_float(amount), do: trunc(amount * 1_000_000_000_000_000_000)
  defp to_wei(amount) when is_integer(amount), do: amount * 1_000_000_000_000_000_000
end
