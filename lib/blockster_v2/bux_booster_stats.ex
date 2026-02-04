defmodule BlocksterV2.BuxBoosterStats do
  @moduledoc """
  Provides betting statistics for the BuxBooster admin dashboard.

  ## Architecture (Phase 10 - Simplified)

  **Player stats** are stored in Mnesia `user_betting_stats` table:
  - Created for every user on signup (with zeros)
  - Updated in real-time on every bet settlement
  - No blockchain queries for player stats - just fast Mnesia lookups

  **Global stats** still come from on-chain contracts:
  - BUX: BuxBoosterGame.getBuxAccounting()
  - ROGUE: ROGUEBankroll.buxBoosterAccounting()

  ## Contract Addresses (Rogue Chain Mainnet - 560013)

  - BuxBoosterGame: 0x97b6d6A8f2c6AF6e6fb40f8d36d60DF2fFE4f17B
  - ROGUEBankroll: 0x51DB4eD2b69b598Fade1aCB5289C7426604AB2fd
  - BUX Token: 0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8
  """

  require Logger

  @bux_booster_game "0x97b6d6A8f2c6AF6e6fb40f8d36d60DF2fFE4f17B"
  @rogue_bankroll "0x51DB4eD2b69b598Fade1aCB5289C7426604AB2fd"
  @bux_token "0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8"
  @rpc_url "https://rpc.roguechain.io/rpc"

  # Function selectors (first 4 bytes of keccak256 hash of function signature)
  @get_bux_accounting_selector "0xb2cf35b4"
  @bux_booster_accounting_selector "0xb9a6a46c"
  @token_configs_selector "0x1b69dc5f"
  @get_house_info_selector "0x97b437bd"

  # Player stats selectors (per-difficulty breakdown)
  # BuxBoosterGame.getBuxPlayerStats(address)
  @get_bux_player_stats_selector "0x2a07f39f"
  # ROGUEBankroll.getBuxBoosterPlayerStats(address)
  @get_rogue_player_stats_selector "0x75db583f"

  # ============ Player Stats (Mnesia-based) ============

  @doc """
  Get all users with their betting stats, sorted by specified field.
  Queries Mnesia `user_betting_stats` table directly - no blockchain queries.

  ## Options
    - :page - page number (1-indexed, default: 1)
    - :per_page - users per page (default: 50)
    - :sort_by - field to sort by (:total_bets, :bux_wagered, :bux_pnl, :rogue_wagered, :rogue_pnl)
    - :sort_order - :asc or :desc (default: :desc)

  Returns:
    {:ok, %{
      players: [player_stats_map],
      total_count: integer,
      page: integer,
      per_page: integer,
      total_pages: integer
    }}
  """
  def get_all_player_stats(opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 50)
    sort_by = Keyword.get(opts, :sort_by, :total_bets)
    sort_order = Keyword.get(opts, :sort_order, :desc)

    # Get ALL records from user_betting_stats (every user has one)
    # Pattern: {:user_betting_stats, user_id, wallet, bux_stats..., rogue_stats..., timestamps...}
    # 20 elements total
    all_records =
      :mnesia.dirty_match_object(
        {:user_betting_stats, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}
      )

    # Convert to maps
    users_with_stats = Enum.map(all_records, &record_to_map/1)

    # Sort
    sorted = sort_users(users_with_stats, sort_by, sort_order)

    # Paginate
    total_count = length(sorted)
    total_pages = max(1, ceil(total_count / per_page))
    offset = (page - 1) * per_page

    paginated = sorted |> Enum.drop(offset) |> Enum.take(per_page)

    {:ok,
     %{
       players: paginated,
       total_count: total_count,
       page: page,
       per_page: per_page,
       total_pages: total_pages
     }}
  end

  @doc """
  Get stats for a specific user by user_id.
  """
  def get_user_stats(user_id) when is_integer(user_id) do
    case :mnesia.dirty_read(:user_betting_stats, user_id) do
      [record] -> {:ok, record_to_map(record)}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Get stats for a user by wallet address.
  """
  def get_user_stats_by_wallet(wallet_address) when is_binary(wallet_address) do
    wallet = String.downcase(wallet_address)

    # Search all records for matching wallet
    all_records =
      :mnesia.dirty_match_object(
        {:user_betting_stats, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}
      )

    case Enum.find(all_records, fn r -> String.downcase(elem(r, 2) || "") == wallet end) do
      nil -> {:error, :not_found}
      record -> {:ok, record_to_map(record)}
    end
  end

  @doc """
  Get count of users who have placed at least one bet.
  """
  def get_player_count do
    :mnesia.dirty_match_object(
      {:user_betting_stats, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}
    )
    |> Enum.count(fn record -> elem(record, 3) > 0 or elem(record, 10) > 0 end)
  end

  @doc """
  Get total count of all users (including those with zero bets).
  """
  def get_total_user_count do
    :mnesia.table_info(:user_betting_stats, :size)
  end

  # Convert Mnesia record to map
  # Record indices (0-indexed, 21 elements total):
  # 0: :user_betting_stats (table name)
  # 1: user_id, 2: wallet_address
  # 3-9: BUX stats (total_bets, wins, losses, wagered, winnings, losses_amt, net_pnl)
  # 10-16: ROGUE stats (same order)
  # 17: first_bet_at, 18: last_bet_at, 19: updated_at
  # 20: onchain_stats_cache (map with per-difficulty data or nil)
  defp record_to_map(record) do
    %{
      user_id: elem(record, 1),
      wallet: elem(record, 2),
      bux: %{
        total_bets: elem(record, 3),
        wins: elem(record, 4),
        losses: elem(record, 5),
        total_wagered: elem(record, 6),
        total_winnings: elem(record, 7),
        total_losses: elem(record, 8),
        net_pnl: elem(record, 9)
      },
      rogue: %{
        total_bets: elem(record, 10),
        wins: elem(record, 11),
        losses: elem(record, 12),
        total_wagered: elem(record, 13),
        total_winnings: elem(record, 14),
        total_losses: elem(record, 15),
        net_pnl: elem(record, 16)
      },
      combined: %{
        total_bets: elem(record, 3) + elem(record, 10),
        total_wins: elem(record, 4) + elem(record, 11),
        total_losses: elem(record, 5) + elem(record, 12)
      },
      first_bet_at: elem(record, 17),
      last_bet_at: elem(record, 18),
      updated_at: elem(record, 19),
      onchain_stats_cache: elem(record, 20)
    }
  end

  defp sort_users(users, :total_bets, order) do
    Enum.sort_by(users, & &1.combined.total_bets, order)
  end

  defp sort_users(users, :bux_wagered, order) do
    Enum.sort_by(users, & &1.bux.total_wagered, order)
  end

  defp sort_users(users, :bux_pnl, order) do
    Enum.sort_by(users, & &1.bux.net_pnl, order)
  end

  defp sort_users(users, :rogue_wagered, order) do
    Enum.sort_by(users, & &1.rogue.total_wagered, order)
  end

  defp sort_users(users, :rogue_pnl, order) do
    Enum.sort_by(users, & &1.rogue.net_pnl, order)
  end

  defp sort_users(users, _, order) do
    # Default: sort by total bets
    Enum.sort_by(users, & &1.combined.total_bets, order)
  end

  # ============ Player Stats (On-Chain - for Detail Page) ============

  @doc """
  Get full player stats from on-chain contracts including per-difficulty breakdown.
  This is used when admin views player detail page or clicks Refresh.

  Queries both BuxBoosterGame and ROGUEBankroll in parallel.

  Returns:
    {:ok, %{
      bux: %{total_bets, wins, losses, total_wagered, total_winnings, total_losses,
             bets_per_difficulty: [9], pnl_per_difficulty: [9], win_rate},
      rogue: %{same structure},
      combined: %{total_bets, total_wins, total_losses}
    }}
  """
  def get_player_stats(wallet_address) when is_binary(wallet_address) do
    tasks = [
      Task.async(fn -> get_bux_player_stats_onchain(wallet_address) end),
      Task.async(fn -> get_rogue_player_stats_onchain(wallet_address) end)
    ]

    [bux_result, rogue_result] = Task.await_many(tasks, 15_000)

    case {bux_result, rogue_result} do
      {{:ok, bux}, {:ok, rogue}} ->
        {:ok,
         %{
           bux: bux,
           rogue: rogue,
           combined: %{
             total_bets: bux.total_bets + rogue.total_bets,
             total_wins: bux.wins + rogue.wins,
             total_losses: bux.losses + rogue.losses
           }
         }}

      {{:error, reason}, _} ->
        Logger.error("[BuxBoosterStats] Failed to get BUX player stats: #{inspect(reason)}")
        {:error, {:bux_failed, reason}}

      {_, {:error, reason}} ->
        Logger.error("[BuxBoosterStats] Failed to get ROGUE player stats: #{inspect(reason)}")
        {:error, {:rogue_failed, reason}}
    end
  end

  @doc """
  Refresh on-chain stats for a player and save to Mnesia cache.
  Called when admin views player detail page or clicks Refresh.

  Returns the refreshed stats map.
  """
  def refresh_and_cache_player_stats(wallet_address) when is_binary(wallet_address) do
    wallet = String.downcase(wallet_address)

    case get_player_stats(wallet) do
      {:ok, stats} ->
        # Find and update the Mnesia record
        case find_record_by_wallet(wallet) do
          {:ok, record} ->
            # Update the onchain_stats_cache field (index 20)
            updated_record = put_elem(record, 20, stats)
            :mnesia.dirty_write(updated_record)
            {:ok, stats}

          {:error, :not_found} ->
            # No record exists - this shouldn't happen for a player with bets
            Logger.warning("[BuxBoosterStats] No Mnesia record found for wallet #{wallet}")
            {:ok, stats}
        end

      error ->
        error
    end
  end

  # Find Mnesia record by wallet address
  defp find_record_by_wallet(wallet_address) do
    wallet = String.downcase(wallet_address)

    all_records =
      :mnesia.dirty_match_object(
        {:user_betting_stats, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}
      )

    case Enum.find(all_records, fn r -> String.downcase(elem(r, 2) || "") == wallet end) do
      nil -> {:error, :not_found}
      record -> {:ok, record}
    end
  end

  @doc """
  Get BUX player stats from BuxBoosterGame.getBuxPlayerStats(address).

  Returns:
    {:ok, %{
      total_bets: integer,
      wins: integer,
      losses: integer,
      total_wagered: integer (wei),
      total_winnings: integer (wei),
      total_losses: integer (wei),
      net_pnl: integer (wei, calculated),
      bets_per_difficulty: [9 integers],
      pnl_per_difficulty: [9 integers (signed)],
      win_rate: float (percentage)
    }}
  """
  def get_bux_player_stats_onchain(wallet_address) do
    address_padded = encode_address(wallet_address)
    data = @get_bux_player_stats_selector <> address_padded

    case eth_call(@bux_booster_game, data) do
      {:ok, result} ->
        {:ok, decode_player_stats_result(result)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get ROGUE player stats from ROGUEBankroll.getBuxBoosterPlayerStats(address).

  Returns same structure as get_bux_player_stats_onchain/1.
  """
  def get_rogue_player_stats_onchain(wallet_address) do
    address_padded = encode_address(wallet_address)
    data = @get_rogue_player_stats_selector <> address_padded

    case eth_call(@rogue_bankroll, data) do
      {:ok, result} ->
        {:ok, decode_player_stats_result(result)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Decode player stats result from getBuxPlayerStats or getBuxBoosterPlayerStats
  # Returns: (totalBets, wins, losses, totalWagered, totalWinnings, totalLosses,
  #           betsPerDifficulty[9], pnlPerDifficulty[9])
  defp decode_player_stats_result(result) do
    hex = String.trim_leading(result, "0x")

    # First 6 uint256 values (6 * 64 = 384 chars)
    <<
      total_bets_hex::binary-size(64),
      wins_hex::binary-size(64),
      losses_hex::binary-size(64),
      total_wagered_hex::binary-size(64),
      total_winnings_hex::binary-size(64),
      total_losses_hex::binary-size(64),
      rest::binary
    >> = hex

    total_bets = parse_uint256(total_bets_hex)
    wins = parse_uint256(wins_hex)
    losses = parse_uint256(losses_hex)
    total_wagered = parse_uint256(total_wagered_hex)
    total_winnings = parse_uint256(total_winnings_hex)
    total_losses = parse_uint256(total_losses_hex)

    # Next: two dynamic arrays (betsPerDifficulty[9] and pnlPerDifficulty[9])
    # Dynamic arrays are encoded as: offset pointer, then data
    # For fixed-size arrays returned inline, they're just sequential values

    # Parse bets_per_difficulty (9 uint256 values)
    {bets_per_difficulty, rest2} = parse_uint256_array(rest, 9)

    # Parse pnl_per_difficulty (9 int256 values - signed)
    {pnl_per_difficulty, _rest3} = parse_int256_array(rest2, 9)

    # Calculate win rate
    win_rate =
      if total_bets > 0 do
        Float.round(wins / total_bets * 100, 2)
      else
        0.0
      end

    # Calculate net P/L
    net_pnl = total_winnings - total_losses

    %{
      total_bets: total_bets,
      wins: wins,
      losses: losses,
      total_wagered: total_wagered,
      total_winnings: total_winnings,
      total_losses: total_losses,
      net_pnl: net_pnl,
      bets_per_difficulty: bets_per_difficulty,
      pnl_per_difficulty: pnl_per_difficulty,
      win_rate: win_rate
    }
  end

  # Parse N consecutive uint256 values from hex string
  defp parse_uint256_array(hex, count) do
    {values, rest} =
      Enum.reduce(1..count, {[], hex}, fn _i, {acc, remaining} ->
        <<value_hex::binary-size(64), rest::binary>> = remaining
        value = parse_uint256(value_hex)
        {acc ++ [value], rest}
      end)

    {values, rest}
  end

  # Parse N consecutive int256 values from hex string
  defp parse_int256_array(hex, count) do
    {values, rest} =
      Enum.reduce(1..count, {[], hex}, fn _i, {acc, remaining} ->
        <<value_hex::binary-size(64), rest::binary>> = remaining
        value = parse_int256(value_hex)
        {acc ++ [value], rest}
      end)

    {values, rest}
  end

  # ============ Global Stats (On-Chain) ============

  @doc """
  Get BUX global betting stats from BuxBoosterGame.getBuxAccounting()

  Returns:
    {:ok, %{
      total_bets: integer,
      total_wins: integer,
      total_losses: integer,
      total_volume_wagered: integer,
      total_payouts: integer,
      total_house_profit: integer,
      largest_win: integer,
      largest_bet: integer
    }}
  """
  def get_bux_global_stats do
    data = @get_bux_accounting_selector

    case eth_call(@bux_booster_game, data) do
      {:ok, result} ->
        {:ok, decode_accounting_result(result)}

      {:error, reason} ->
        Logger.error("[BuxBoosterStats] Failed to get BUX global stats: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Get ROGUE global betting stats from ROGUEBankroll.buxBoosterAccounting()

  Returns same structure as get_bux_global_stats/0
  """
  def get_rogue_global_stats do
    data = @bux_booster_accounting_selector

    case eth_call(@rogue_bankroll, data) do
      {:ok, result} ->
        {:ok, decode_accounting_result(result)}

      {:error, reason} ->
        Logger.error("[BuxBoosterStats] Failed to get ROGUE global stats: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Get house balances for both BUX and ROGUE.

  Returns:
    {:ok, %{bux: integer, rogue: integer}}
  """
  def get_house_balances do
    tasks = [
      Task.async(fn -> get_bux_house_balance() end),
      Task.async(fn -> get_rogue_house_balance() end)
    ]

    [bux_result, rogue_result] = Task.await_many(tasks, 15_000)

    case {bux_result, rogue_result} do
      {{:ok, bux}, {:ok, rogue}} ->
        {:ok, %{bux: bux, rogue: rogue}}

      {{:error, reason}, _} ->
        {:error, {:bux_failed, reason}}

      {_, {:error, reason}} ->
        {:error, {:rogue_failed, reason}}
    end
  end

  @doc """
  Get BUX house balance from BuxBoosterGame.tokenConfigs(BUX_ADDRESS)
  """
  def get_bux_house_balance do
    address_padded = encode_address(@bux_token)
    data = @token_configs_selector <> address_padded

    case eth_call(@bux_booster_game, data) do
      {:ok, result} ->
        # tokenConfigs returns (bool enabled, uint256 houseBalance)
        # Skip first 32 bytes (enabled bool), take next 32 bytes (houseBalance)
        <<_enabled::binary-size(64), house_balance_hex::binary-size(64), _rest::binary>> =
          String.trim_leading(result, "0x")

        house_balance = parse_uint256(house_balance_hex)
        {:ok, house_balance}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get ROGUE house balance from ROGUEBankroll.getHouseInfo()
  Returns the net_balance which is what's available for betting.
  """
  def get_rogue_house_balance do
    data = @get_house_info_selector

    case eth_call(@rogue_bankroll, data) do
      {:ok, result} ->
        # getHouseInfo returns (netBalance, totalBalance, minBetSize, maxBetSize)
        # We want the netBalance (first uint256)
        <<net_balance_hex::binary-size(64), _rest::binary>> =
          String.trim_leading(result, "0x")

        net_balance = parse_uint256(net_balance_hex)
        {:ok, net_balance}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ============ Private Helpers ============

  defp eth_call(to, data) do
    body = %{
      jsonrpc: "2.0",
      method: "eth_call",
      params: [%{to: to, data: data}, "latest"],
      id: 1
    }

    case Req.post(@rpc_url, json: body, receive_timeout: 15_000) do
      {:ok, %{status: 200, body: %{"result" => result}}} ->
        {:ok, result}

      {:ok, %{status: 200, body: %{"error" => error}}} ->
        {:error, error}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Encode an Ethereum address to 32 bytes (left-padded with zeros)
  defp encode_address(address) do
    address
    |> String.trim_leading("0x")
    |> String.downcase()
    |> String.pad_leading(64, "0")
  end

  # Parse a hex string as unsigned 256-bit integer
  defp parse_uint256(hex) when byte_size(hex) == 64 do
    {value, ""} = Integer.parse(hex, 16)
    value
  end

  defp parse_uint256(hex) do
    padded = String.pad_leading(hex, 64, "0")
    parse_uint256(padded)
  end

  # Parse a hex string as signed 256-bit integer (two's complement)
  defp parse_int256(hex) when byte_size(hex) == 64 do
    {value, ""} = Integer.parse(hex, 16)

    # If highest bit is set, it's negative (two's complement)
    if value >= 0x8000000000000000000000000000000000000000000000000000000000000000 do
      value - 0x10000000000000000000000000000000000000000000000000000000000000000
    else
      value
    end
  end

  defp parse_int256(hex) do
    padded = String.pad_leading(hex, 64, "0")
    parse_int256(padded)
  end

  # Decode BuxAccounting or buxBoosterAccounting result
  # Returns: (totalBets, totalWins, totalLosses, totalVolumeWagered, totalPayouts, totalHouseProfit, largestWin, largestBet)
  defp decode_accounting_result(result) do
    hex = String.trim_leading(result, "0x")

    # Each value is 32 bytes (64 hex chars)
    <<
      total_bets_hex::binary-size(64),
      total_wins_hex::binary-size(64),
      total_losses_hex::binary-size(64),
      total_volume_wagered_hex::binary-size(64),
      total_payouts_hex::binary-size(64),
      total_house_profit_hex::binary-size(64),
      largest_win_hex::binary-size(64),
      largest_bet_hex::binary-size(64),
      _rest::binary
    >> = hex

    %{
      total_bets: parse_uint256(total_bets_hex),
      total_wins: parse_uint256(total_wins_hex),
      total_losses: parse_uint256(total_losses_hex),
      total_volume_wagered: parse_uint256(total_volume_wagered_hex),
      total_payouts: parse_uint256(total_payouts_hex),
      total_house_profit: parse_int256(total_house_profit_hex),
      largest_win: parse_uint256(largest_win_hex),
      largest_bet: parse_uint256(largest_bet_hex)
    }
  end
end
