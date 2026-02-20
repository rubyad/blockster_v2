# Backend Implementation Spec: Plinko + BUX Bankroll

> Complete implementation code for all backend modules. No placeholders, no abbreviations.
> Every module follows existing patterns from bux_booster_onchain.ex, bux_booster_bet_settler.ex,
> price_tracker.ex, bux_minter.ex, mnesia_initializer.ex, application.ex, and router.ex.

---

## 1. PlinkoGame (`lib/blockster_v2/plinko_game.ex`)

```elixir
defmodule BlocksterV2.PlinkoGame do
  @moduledoc """
  On-chain Plinko game orchestration.

  Blockster is the orchestrator:
  - Generates server seeds
  - Stores seeds in Mnesia (:plinko_games table)
  - Calls BUX Minter to submit/settle transactions
  - Controls game flow and timing

  BUX Minter is a stateless transaction relay.

  ## Mnesia Table: :plinko_games
  Primary key: game_id (32-char hex string)
  Tuple size: 25 elements (table name + 24 data fields)
  """

  alias BlocksterV2.{BuxMinter, EngagementTracker}
  require Logger

  @plinko_contract_address "0x<DEPLOYED>"  # Set after deployment

  @configs %{
    0 => {8, :low},    1 => {8, :medium},  2 => {8, :high},
    3 => {12, :low},   4 => {12, :medium}, 5 => {12, :high},
    6 => {16, :low},   7 => {16, :medium}, 8 => {16, :high}
  }

  # Token contract addresses
  @token_addresses %{
    "BUX" => "0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8",
    "ROGUE" => "0x0000000000000000000000000000000000000000"
  }

  # Payout tables in basis points (10000 = 1.0x) - MUST match contract exactly
  @payout_tables %{
    0 => [56000, 21000, 11000, 10000, 5000, 10000, 11000, 21000, 56000],
    1 => [130000, 30000, 13000, 7000, 4000, 7000, 13000, 30000, 130000],
    2 => [360000, 40000, 15000, 3000, 0, 3000, 15000, 40000, 360000],
    3 => [110000, 30000, 16000, 14000, 11000, 10000, 5000, 10000, 11000, 14000, 16000, 30000, 110000],
    4 => [330000, 110000, 40000, 20000, 11000, 6000, 3000, 6000, 11000, 20000, 40000, 110000, 330000],
    5 => [4050000, 180000, 70000, 20000, 7000, 2000, 0, 2000, 7000, 20000, 70000, 180000, 4050000],
    6 => [160000, 90000, 20000, 14000, 14000, 12000, 11000, 10000, 5000, 10000, 11000, 12000, 14000, 14000, 20000, 90000, 160000],
    7 => [1100000, 410000, 100000, 50000, 30000, 15000, 10000, 5000, 3000, 5000, 10000, 15000, 30000, 50000, 100000, 410000, 1100000],
    8 => [10000000, 1500000, 330000, 100000, 33000, 20000, 3000, 2000, 0, 2000, 3000, 20000, 33000, 100000, 330000, 1500000, 10000000]
  }

  # Public accessors
  def configs, do: @configs
  def payout_tables, do: @payout_tables
  def contract_address, do: @plinko_contract_address
  def token_address("ROGUE"), do: "0x0000000000000000000000000000000000000000"
  def token_address(token), do: Map.get(@token_addresses, token, token)
  def token_addresses, do: @token_addresses

  # ============ Game Lifecycle ============

  @doc """
  Get or create a game session.
  Calculates next nonce from Mnesia by finding the highest nonce from placed bets.
  Never queries the contract - Mnesia is the source of truth for nonces.
  """
  def get_or_init_game(user_id, wallet_address) do
    # Calculate next nonce from Mnesia based on placed/settled games
    next_nonce = case :mnesia.dirty_match_object({:plinko_games, :_, user_id, wallet_address, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}) do
      [] -> 0
      games ->
        placed_games = Enum.filter(games, fn game -> elem(game, 7) in [:placed, :settled] end)
        case placed_games do
          [] -> 0
          _ ->
            placed_games
            |> Enum.map(fn game -> elem(game, 6) end)  # nonce at position 6
            |> Enum.max()
            |> Kernel.+(1)
        end
    end

    # Check for reusable committed game with correct nonce
    case get_pending_game(user_id) do
      %{wallet_address: ^wallet_address, commitment_tx: tx, nonce: nonce} = existing
          when tx != nil and nonce == next_nonce ->
        Logger.info("[PlinkoGame] Reusing existing game: #{existing.game_id}, nonce: #{existing.nonce}")
        {:ok, %{
          game_id: existing.game_id,
          commitment_hash: existing.commitment_hash,
          commitment_tx: existing.commitment_tx,
          nonce: existing.nonce
        }}

      _ ->
        Logger.info("[PlinkoGame] Creating new game with nonce #{next_nonce} (from Mnesia)")
        init_game_with_nonce(user_id, wallet_address, next_nonce)
    end
  end

  @doc """
  Initialize a new game session with explicit nonce.
  Generates server seed, stores in Mnesia, submits commitment to chain.

  Returns {:ok, %{game_id, commitment_hash, commitment_tx, nonce}} or {:error, reason}
  """
  def init_game_with_nonce(user_id, wallet_address, nonce) do
    # Generate server seed (32 bytes as hex string without 0x prefix)
    server_seed = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)

    # Calculate commitment hash (sha256 of the hex string for player verification)
    commitment_hash_bytes = :crypto.hash(:sha256, server_seed)
    commitment_hash = "0x" <> Base.encode16(commitment_hash_bytes, case: :lower)

    # Generate game ID (primary key)
    game_id = generate_game_id()
    now = System.system_time(:second)

    # Submit commitment to contract via BUX Minter
    case BuxMinter.plinko_submit_commitment(commitment_hash, wallet_address, nonce) do
      {:ok, tx_hash} ->
        Logger.info("[PlinkoGame] Commitment submitted - TX: #{tx_hash}, Player: #{wallet_address}, Nonce: #{nonce}")

        # Write to Mnesia (25 elements: table name + 24 data fields)
        game_record = {
          :plinko_games,
          game_id,                    # 1: game_id (PK)
          user_id,                    # 2: user_id
          wallet_address,             # 3: wallet_address
          server_seed,                # 4: server_seed
          commitment_hash,            # 5: commitment_hash
          nonce,                      # 6: nonce
          :committed,                 # 7: status
          nil,                        # 8: bet_id
          nil,                        # 9: token
          nil,                        # 10: token_address
          nil,                        # 11: bet_amount
          nil,                        # 12: config_index
          nil,                        # 13: rows
          nil,                        # 14: risk_level
          nil,                        # 15: ball_path
          nil,                        # 16: landing_position
          nil,                        # 17: payout_bp
          nil,                        # 18: payout
          nil,                        # 19: won
          tx_hash,                    # 20: commitment_tx
          nil,                        # 21: bet_tx
          nil,                        # 22: settlement_tx
          now,                        # 23: created_at
          nil                         # 24: settled_at
        }
        :mnesia.dirty_write(game_record)

        {:ok, %{
          game_id: game_id,
          commitment_hash: commitment_hash,
          commitment_tx: tx_hash,
          nonce: nonce
        }}

      {:error, reason} ->
        Logger.error("[PlinkoGame] Failed to submit commitment: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Calculate game result from server seed and bet details.
  Uses Plinko-specific ball path generation (not coin flips).

  Returns {:ok, result} with ball_path, landing_position, payout, outcome, etc.
  """
  def calculate_result(server_seed, nonce, config_index, bet_amount, token, user_id) do
    {rows, _risk_level} = Map.get(@configs, config_index)

    # Client seed - deterministic from player-controlled values
    # No predictions field (unlike BuxBooster) since Plinko has no player choices
    input = "#{user_id}:#{bet_amount}:#{token}:#{config_index}"
    client_seed = :crypto.hash(:sha256, input) |> Base.encode16(case: :lower)

    # Combined seed (matches BuxBooster pattern: SHA256("server_hex:client_hex:nonce"))
    combined = :crypto.hash(:sha256, "#{server_seed}:#{client_seed}:#{nonce}")

    # Ball path: first `rows` bytes (SHA256 = 32 bytes, max rows = 16, always enough)
    ball_path = for i <- 0..(rows - 1) do
      byte = :binary.at(combined, i)
      if byte < 128, do: :left, else: :right
    end

    # Landing position = count of :right bounces
    landing_position = Enum.count(ball_path, &(&1 == :right))

    # Payout lookup
    payout_table = Map.get(@payout_tables, config_index)
    payout_bp = Enum.at(payout_table, landing_position)
    payout = div(bet_amount * payout_bp, 10000)

    # Determine outcome: won (profit), lost, or push (break even)
    outcome = cond do
      payout > bet_amount -> :won
      payout == bet_amount -> :push
      true -> :lost
    end

    {:ok, %{
      ball_path: ball_path,
      landing_position: landing_position,
      payout: payout,
      payout_bp: payout_bp,
      won: payout > bet_amount,
      outcome: outcome,
      server_seed: server_seed
    }}
  end

  @doc """
  Calculate game result from Mnesia (wrapper called from LiveView).
  Reads server_seed from stored game and delegates to calculate_result/6.
  """
  def calculate_game_result(game_id, config_index, bet_amount, token, user_id) do
    case get_game(game_id) do
      {:ok, game} ->
        calculate_result(game.server_seed, game.nonce, config_index, bet_amount, token, user_id)
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Called when player's bet is placed on-chain.
  Updates the game record with bet details and calculates the result.

  Returns {:ok, result} where result contains ball_path, landing_position, payout, etc.
  """
  def on_bet_placed(game_id, bet_id, bet_tx, bet_amount, token, config_index) do
    case get_game(game_id) do
      {:ok, game} ->
        token_address = Map.get(@token_addresses, token, token)
        {rows, risk_level} = Map.get(@configs, config_index)

        # Calculate result locally (we have the server seed)
        {:ok, result} = calculate_result(
          game.server_seed, game.nonce, config_index, bet_amount, token, game.user_id
        )

        now = System.system_time(:second)

        # Full Mnesia tuple (25 positions: table name + 24 fields)
        updated_record = {
          :plinko_games,
          game_id,                    # 1: game_id (PK)
          game.user_id,               # 2: user_id
          game.wallet_address,        # 3: wallet_address
          game.server_seed,           # 4: server_seed
          game.commitment_hash,       # 5: commitment_hash
          game.nonce,                 # 6: nonce
          :placed,                    # 7: status
          bet_id,                     # 8: bet_id
          token,                      # 9: token
          token_address,              # 10: token_address
          bet_amount,                 # 11: bet_amount
          config_index,               # 12: config_index
          rows,                       # 13: rows
          risk_level,                 # 14: risk_level
          result.ball_path,           # 15: ball_path
          result.landing_position,    # 16: landing_position
          result.payout_bp,           # 17: payout_bp
          result.payout,              # 18: payout
          result.won,                 # 19: won
          game.commitment_tx,         # 20: commitment_tx
          bet_tx,                     # 21: bet_tx
          nil,                        # 22: settlement_tx
          now,                        # 23: created_at (updated to bet time)
          nil                         # 24: settled_at
        }
        :mnesia.dirty_write(updated_record)

        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Settle the bet on-chain after animation completes.
  Branches on token type: BUX uses plinko_settle_bet, ROGUE uses plinko_settle_bet_rogue.

  Returns {:ok, %{tx_hash, player_balance}} or {:error, reason}
  """
  def settle_game(game_id) do
    case get_game(game_id) do
      {:ok, game} when game.status == :settled ->
        Logger.debug("[PlinkoGame] Game #{game_id} already settled, skipping")
        {:ok, %{tx_hash: game.settlement_tx, player_balance: nil, already_settled: true}}

      {:ok, game} when game.bet_id != nil ->
        server_seed_hex = "0x" <> game.server_seed

        # Branch on token type - BUX and ROGUE use different contract functions
        settle_fn = case game.token do
          "ROGUE" -> &BuxMinter.plinko_settle_bet_rogue/4
          _ -> &BuxMinter.plinko_settle_bet/4
        end

        case settle_fn.(game.commitment_hash, server_seed_hex, game.ball_path, game.landing_position) do
          {:ok, tx_hash, player_balance} ->
            mark_game_settled(game_id, game, tx_hash)
            update_user_betting_stats(game.user_id, game.token, game.bet_amount, game.won, game.payout)

            # Sync balances asynchronously
            if game.wallet_address do
              BuxMinter.sync_user_balances_async(game.user_id, game.wallet_address, force: true)
            end

            # Broadcast settlement to PlinkoLive
            Phoenix.PubSub.broadcast(
              BlocksterV2.PubSub,
              "plinko_settlement:#{game.user_id}",
              {:plinko_settled, game_id, tx_hash}
            )

            Logger.info("[PlinkoGame] Game #{game_id} settled: #{tx_hash}")
            {:ok, %{tx_hash: tx_hash, player_balance: player_balance}}

          {:error, reason} ->
            if is_bet_already_settled_error?(reason) do
              Logger.info("[PlinkoGame] Game #{game_id} already settled on-chain, marking as settled")
              mark_game_settled(game_id, game, "already_settled_on_chain")
              update_user_betting_stats(game.user_id, game.token, game.bet_amount, game.won, game.payout)
              {:ok, %{tx_hash: "already_settled_on_chain", player_balance: nil, already_settled: true}}
            else
              Logger.error("[PlinkoGame] Failed to settle game #{game_id}: #{inspect(reason)}")
              {:error, reason}
            end
        end

      {:ok, _game} ->
        {:error, :bet_not_placed}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Mark a game as settled in Mnesia.
  """
  def mark_game_settled(game_id, game, tx_hash) do
    now = System.system_time(:second)
    updated_record = {
      :plinko_games,
      game_id,                    # 1: game_id
      game.user_id,               # 2: user_id
      game.wallet_address,        # 3: wallet_address
      game.server_seed,           # 4: server_seed
      game.commitment_hash,       # 5: commitment_hash
      game.nonce,                 # 6: nonce
      :settled,                   # 7: status
      game.bet_id,                # 8: bet_id
      game.token,                 # 9: token
      game.token_address,         # 10: token_address
      game.bet_amount,            # 11: bet_amount
      game.config_index,          # 12: config_index
      game.rows,                  # 13: rows
      game.risk_level,            # 14: risk_level
      game.ball_path,             # 15: ball_path
      game.landing_position,      # 16: landing_position
      game.payout_bp,             # 17: payout_bp
      game.payout,                # 18: payout
      game.won,                   # 19: won
      game.commitment_tx,         # 20: commitment_tx
      game.bet_tx,                # 21: bet_tx
      tx_hash,                    # 22: settlement_tx
      game.created_at,            # 23: created_at
      now                         # 24: settled_at
    }
    :mnesia.dirty_write(updated_record)
  end

  @doc """
  Get game details from Mnesia.
  """
  def get_game(game_id) do
    case :mnesia.dirty_read({:plinko_games, game_id}) do
      [{:plinko_games, ^game_id, user_id, wallet_address, server_seed, commitment_hash,
        nonce, status, bet_id, token, token_address, bet_amount, config_index, rows,
        risk_level, ball_path, landing_position, payout_bp, payout, won,
        commitment_tx, bet_tx, settlement_tx, created_at, settled_at}] ->
        {:ok, %{
          game_id: game_id, user_id: user_id, wallet_address: wallet_address,
          server_seed: server_seed, commitment_hash: commitment_hash,
          nonce: nonce, status: status, bet_id: bet_id, token: token,
          token_address: token_address, bet_amount: bet_amount,
          config_index: config_index, rows: rows, risk_level: risk_level,
          ball_path: ball_path, landing_position: landing_position,
          payout_bp: payout_bp, payout: payout, won: won,
          commitment_tx: commitment_tx, bet_tx: bet_tx,
          settlement_tx: settlement_tx, created_at: created_at,
          settled_at: settled_at
        }}

      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  Get an existing unused game session for a user, or nil if none exists.
  """
  def get_pending_game(user_id) do
    case :mnesia.dirty_index_read(:plinko_games, user_id, :user_id) do
      games when is_list(games) and length(games) > 0 ->
        pending_game = games
        |> Enum.filter(fn record ->
          status = elem(record, 7)
          status in [:pending, :committed]
        end)
        |> Enum.sort_by(fn record -> elem(record, 23) end, :desc)  # created_at
        |> List.first()

        case pending_game do
          nil -> nil
          record ->
            %{
              game_id: elem(record, 1),
              user_id: elem(record, 2),
              wallet_address: elem(record, 3),
              server_seed: elem(record, 4),
              commitment_hash: elem(record, 5),
              nonce: elem(record, 6),
              status: elem(record, 7),
              commitment_tx: elem(record, 20),
              created_at: elem(record, 23)
            }
        end

      _ ->
        nil
    end
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  @doc """
  Load recent settled games for game history display.
  """
  def load_recent_games(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 30)
    offset = Keyword.get(opts, :offset, 0)

    :mnesia.dirty_index_read(:plinko_games, user_id, :user_id)
    |> Enum.filter(fn game -> elem(game, 7) == :settled end)
    |> Enum.sort_by(fn game -> elem(game, 23) end, :desc)  # created_at descending
    |> Enum.drop(offset)
    |> Enum.take(limit)
    |> Enum.map(&game_tuple_to_map/1)
  end

  # ============ User Betting Stats ============

  @doc """
  Update user betting stats in Mnesia for admin dashboard.
  Called after successful bet settlement. Reuses same :user_betting_stats table as BuxBooster.
  """
  def update_user_betting_stats(user_id, token, bet_amount, won, payout) do
    case :mnesia.dirty_read(:user_betting_stats, user_id) do
      [record] ->
        now = System.system_time(:millisecond)
        first_bet_at = elem(record, 17) || now

        updated = case token do
          "ROGUE" -> update_rogue_stats(record, bet_amount, won, payout, now, first_bet_at)
          _ -> update_bux_stats(record, bet_amount, won, payout, now, first_bet_at)
        end

        :mnesia.dirty_write(updated)

      [] ->
        Logger.warning("[PlinkoGame] Missing user_betting_stats for user #{user_id}, creating now")
        now = System.system_time(:millisecond)
        bet_amount_wei = to_wei(bet_amount)
        payout_wei = to_wei(payout)

        {bux_stats, rogue_stats} = case token do
          "ROGUE" ->
            rogue = calculate_stats(bet_amount_wei, won, payout_wei)
            {{0, 0, 0, 0, 0, 0, 0}, rogue}
          _ ->
            bux = calculate_stats(bet_amount_wei, won, payout_wei)
            {bux, {0, 0, 0, 0, 0, 0, 0}}
        end

        {bux_bets, bux_wins, bux_losses, bux_wagered, bux_winnings, bux_losses_amt, bux_pnl} = bux_stats
        {rogue_bets, rogue_wins, rogue_losses, rogue_wagered, rogue_winnings, rogue_losses_amt, rogue_pnl} = rogue_stats

        record = {:user_betting_stats, user_id, "",
          bux_bets, bux_wins, bux_losses, bux_wagered, bux_winnings, bux_losses_amt, bux_pnl,
          rogue_bets, rogue_wins, rogue_losses, rogue_wagered, rogue_winnings, rogue_losses_amt, rogue_pnl,
          now, now, now,
          nil}  # onchain_stats_cache
        :mnesia.dirty_write(record)
    end
    :ok
  end

  defp update_bux_stats(record, bet_amount, won, payout, now, first_bet_at) do
    bet_amount_wei = to_wei(bet_amount)
    payout_wei = to_wei(payout)
    winnings = if won, do: payout_wei - bet_amount_wei, else: 0
    losses = if won, do: 0, else: bet_amount_wei
    net_change = if won, do: payout_wei - bet_amount_wei, else: -bet_amount_wei

    record
    |> put_elem(3, elem(record, 3) + 1)                                  # bux_total_bets
    |> put_elem(4, elem(record, 4) + (if won, do: 1, else: 0))           # bux_wins
    |> put_elem(5, elem(record, 5) + (if won, do: 0, else: 1))           # bux_losses
    |> put_elem(6, elem(record, 6) + bet_amount_wei)                     # bux_total_wagered
    |> put_elem(7, elem(record, 7) + winnings)                           # bux_total_winnings
    |> put_elem(8, elem(record, 8) + losses)                             # bux_total_losses
    |> put_elem(9, elem(record, 9) + net_change)                         # bux_net_pnl
    |> put_elem(17, first_bet_at)                                        # first_bet_at
    |> put_elem(18, now)                                                 # last_bet_at
    |> put_elem(19, now)                                                 # updated_at
  end

  defp update_rogue_stats(record, bet_amount, won, payout, now, first_bet_at) do
    bet_amount_wei = to_wei(bet_amount)
    payout_wei = to_wei(payout)
    winnings = if won, do: payout_wei - bet_amount_wei, else: 0
    losses = if won, do: 0, else: bet_amount_wei
    net_change = if won, do: payout_wei - bet_amount_wei, else: -bet_amount_wei

    record
    |> put_elem(10, elem(record, 10) + 1)                                 # rogue_total_bets
    |> put_elem(11, elem(record, 11) + (if won, do: 1, else: 0))          # rogue_wins
    |> put_elem(12, elem(record, 12) + (if won, do: 0, else: 1))          # rogue_losses
    |> put_elem(13, elem(record, 13) + bet_amount_wei)                    # rogue_total_wagered
    |> put_elem(14, elem(record, 14) + winnings)                          # rogue_total_winnings
    |> put_elem(15, elem(record, 15) + losses)                            # rogue_total_losses
    |> put_elem(16, elem(record, 16) + net_change)                        # rogue_net_pnl
    |> put_elem(17, first_bet_at)                                         # first_bet_at
    |> put_elem(18, now)                                                  # last_bet_at
    |> put_elem(19, now)                                                  # updated_at
  end

  defp calculate_stats(bet_amount_wei, won, payout_wei) do
    winnings = if won, do: payout_wei - bet_amount_wei, else: 0
    losses = if won, do: 0, else: bet_amount_wei
    net_pnl = if won, do: payout_wei - bet_amount_wei, else: -bet_amount_wei
    {1, (if won, do: 1, else: 0), (if won, do: 0, else: 1), bet_amount_wei, winnings, losses, net_pnl}
  end

  defp to_wei(nil), do: 0
  defp to_wei(amount) when is_float(amount), do: trunc(amount * 1_000_000_000_000_000_000)
  defp to_wei(amount) when is_integer(amount), do: amount * 1_000_000_000_000_000_000

  # ============ Private Helpers ============

  defp is_bet_already_settled_error?(reason) when is_binary(reason) do
    String.contains?(reason, "0x05d09e5f")
  end
  defp is_bet_already_settled_error?(_), do: false

  defp generate_game_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  defp game_tuple_to_map({:plinko_games, game_id, user_id, wallet_address, server_seed,
      commitment_hash, nonce, status, bet_id, token, token_address, bet_amount,
      config_index, rows, risk_level, ball_path, landing_position, payout_bp,
      payout, won, commitment_tx, bet_tx, settlement_tx, created_at, settled_at}) do
    %{
      game_id: game_id, user_id: user_id, wallet_address: wallet_address,
      server_seed: server_seed, commitment_hash: commitment_hash,
      nonce: nonce, status: status, bet_id: bet_id, token: token,
      token_address: token_address, bet_amount: bet_amount,
      config_index: config_index, rows: rows, risk_level: risk_level,
      ball_path: ball_path, landing_position: landing_position,
      payout_bp: payout_bp, payout: payout, won: won,
      commitment_tx: commitment_tx, bet_tx: bet_tx,
      settlement_tx: settlement_tx, created_at: created_at,
      settled_at: settled_at
    }
  end
end
```

---

## 2. PlinkoSettler (`lib/blockster_v2/plinko_settler.ex`)

```elixir
defmodule BlocksterV2.PlinkoSettler do
  @moduledoc """
  Background worker that periodically checks for unsettled Plinko bets and attempts to settle them.

  Runs every minute and:
  1. Finds bets that have been placed but not settled (status = :placed)
  2. Checks if they're older than 120 seconds (to avoid settling bets still animating)
  3. Attempts to settle them via PlinkoGame.settle_game/1

  Global singleton via GlobalSingleton - only one instance runs across the cluster.
  """

  use GenServer
  require Logger

  @check_interval :timer.minutes(1)
  @settlement_timeout 120  # Don't try to settle bets younger than 2 minutes (in seconds)

  def start_link(_opts) do
    # Use GlobalSingleton to avoid killing existing process during name conflicts
    case BlocksterV2.GlobalSingleton.start_link(__MODULE__, []) do
      {:ok, pid} ->
        send(pid, :registered)
        {:ok, pid}

      {:already_registered, _pid} ->
        :ignore
    end
  end

  @impl true
  def init(_) do
    # Don't start work here - wait for :registered message from start_link
    {:ok, %{registered: false}}
  end

  @impl true
  def handle_info(:registered, %{registered: false} = state) do
    Logger.info("[PlinkoSettler] Starting Plinko bet settlement checker (runs every minute)")
    schedule_check()
    {:noreply, %{state | registered: true}}
  end

  def handle_info(:registered, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(:check_unsettled_bets, state) do
    check_and_settle_stuck_bets()
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check_unsettled_bets, @check_interval)
  end

  defp check_and_settle_stuck_bets do
    now = System.system_time(:second)
    cutoff = now - @settlement_timeout

    unsettled = find_unsettled_bets(cutoff)

    if length(unsettled) > 0 do
      Logger.info("[PlinkoSettler] Found #{length(unsettled)} unsettled Plinko bets older than 2 minutes")
      Enum.each(unsettled, &attempt_settlement/1)
    end
  end

  defp find_unsettled_bets(cutoff_time) do
    # Find all games with status = :placed
    # Mnesia tuple positions (0-indexed after table name):
    # 7:status, 23:created_at
    :mnesia.dirty_match_object({:plinko_games, :_, :_, :_, :_, :_, :_, :placed, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_})
    |> Enum.filter(fn record ->
      created_at = elem(record, 23)
      created_at != nil and created_at < cutoff_time
    end)
    |> Enum.map(fn record ->
      %{
        game_id: elem(record, 1),
        user_id: elem(record, 2),
        created_at: elem(record, 23)
      }
    end)
  end

  defp attempt_settlement(bet) do
    age_seconds = System.system_time(:second) - bet.created_at
    Logger.info("[PlinkoSettler] Attempting to settle Plinko bet #{bet.game_id} (placed #{age_seconds}s ago)")

    case BlocksterV2.PlinkoGame.settle_game(bet.game_id) do
      {:ok, %{tx_hash: tx_hash}} ->
        Logger.info("[PlinkoSettler] Successfully settled Plinko bet #{bet.game_id}: #{tx_hash}")
        :ok

      {:error, reason} ->
        Logger.error("[PlinkoSettler] Failed to settle Plinko bet #{bet.game_id}: #{inspect(reason)}")
        :error
    end
  rescue
    error ->
      Logger.error("[PlinkoSettler] Exception settling Plinko bet #{bet.game_id}: #{inspect(error)}")
      :error
  end
end
```

---

## 3. LPBuxPriceTracker (`lib/blockster_v2/lp_bux_price_tracker.ex`)

```elixir
defmodule BlocksterV2.LPBuxPriceTracker do
  @moduledoc """
  GenServer that polls BUXBankroll LP-BUX price every 60 seconds,
  stores 5-minute OHLC candles in Mnesia, and broadcasts via PubSub.

  Global singleton via GlobalSingleton - only one instance runs across the cluster.

  ## Mnesia Table: :lp_bux_candles
  Primary key: timestamp (unix seconds, aligned to 5-min boundaries)
  Fields: timestamp, open, high, low, close
  """

  use GenServer
  require Logger

  @poll_interval 60_000        # Fetch price every 60 seconds
  @candle_interval 300         # 5-minute candles (in seconds)
  @pubsub_topic "lp_bux_price"

  # ============ Client API ============

  def start_link(_opts) do
    case BlocksterV2.GlobalSingleton.start_link(__MODULE__, []) do
      {:ok, pid} ->
        send(pid, :registered)
        {:ok, pid}

      {:already_registered, _pid} ->
        :ignore
    end
  end

  @doc "Get current LP-BUX price from BUX Minter"
  def get_current_price do
    case BlocksterV2.BuxMinter.bux_bankroll_lp_price() do
      {:ok, price_str} -> {:ok, parse_price(price_str)}
      error -> error
    end
  end

  @doc "Get OHLC candles from Mnesia, aggregated to requested timeframe"
  def get_candles(timeframe_seconds, limit \\ 100) do
    now = System.system_time(:second)
    cutoff = now - (timeframe_seconds * limit)

    :mnesia.dirty_select(:lp_bux_candles, [
      {{:lp_bux_candles, :"$1", :"$2", :"$3", :"$4", :"$5"},
       [{:>=, :"$1", cutoff}],
       [{{:"$1", :"$2", :"$3", :"$4", :"$5"}}]}
    ])
    |> Enum.sort_by(&elem(&1, 0))
    |> aggregate_candles(timeframe_seconds)
  end

  @doc "Get price stats for various timeframes"
  def get_stats do
    now = System.system_time(:second)

    %{
      price_1h: get_high_low(now - 3600, now),
      price_24h: get_high_low(now - 86400, now),
      price_7d: get_high_low(now - 604800, now),
      price_30d: get_high_low(now - 2592000, now),
      price_all: get_high_low(0, now)
    }
  end

  @doc "Force refresh price (for manual trigger)"
  def refresh_price do
    GenServer.cast({:global, __MODULE__}, :poll_price)
  end

  # ============ Server Callbacks ============

  @impl true
  def init(_) do
    {:ok, %{current_candle: nil, candle_start: nil, registered: false, mnesia_ready: false}}
  end

  @impl true
  def handle_info(:registered, %{registered: false} = state) do
    Process.send_after(self(), :wait_for_mnesia, 1000)
    {:noreply, %{state | registered: true}}
  end

  def handle_info(:registered, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(:wait_for_mnesia, state) do
    attempts = Map.get(state, :mnesia_wait_attempts, 0)

    if attempts > 30 do
      Logger.error("[LPBuxPriceTracker] Gave up waiting for Mnesia lp_bux_candles table after 60 seconds")
      {:noreply, state}
    else
      case :global.whereis_name(__MODULE__) do
        pid when pid == self() ->
          if table_ready?(:lp_bux_candles) do
            Logger.info("[LPBuxPriceTracker] Mnesia table ready, starting price fetcher")
            send(self(), :poll_price)
            {:noreply, %{state | mnesia_ready: true}}
          else
            Logger.info("[LPBuxPriceTracker] Waiting for Mnesia lp_bux_candles table... (attempt #{attempts + 1})")
            Process.send_after(self(), :wait_for_mnesia, 2000)
            {:noreply, Map.put(state, :mnesia_wait_attempts, attempts + 1)}
          end

        other_pid ->
          Logger.info("[LPBuxPriceTracker] Another instance is now the global owner (#{inspect(other_pid)}), stopping")
          {:stop, :normal, state}
      end
    end
  end

  @impl true
  def handle_info(:poll_price, state) do
    case :global.whereis_name(__MODULE__) do
      pid when pid == self() ->
        state = do_poll_price(state)
        schedule_poll()
        {:noreply, state}

      other_pid ->
        Logger.info("[LPBuxPriceTracker] Another instance is now the global owner (#{inspect(other_pid)}), stopping")
        {:stop, :normal, state}
    end
  end

  @impl true
  def handle_cast(:poll_price, state) do
    case :global.whereis_name(__MODULE__) do
      pid when pid == self() ->
        state = do_poll_price(state)
        {:noreply, state}

      _other_pid ->
        {:noreply, state}
    end
  end

  # ============ Private Functions ============

  defp do_poll_price(state) do
    case BlocksterV2.BuxMinter.bux_bankroll_lp_price() do
      {:ok, price_str} ->
        price = parse_price(price_str)
        state = update_candle(state, price)
        broadcast_price(price, state)
        state

      {:error, reason} ->
        Logger.warning("[LPBuxPriceTracker] Failed to fetch LP price: #{inspect(reason)}")
        state
    end
  end

  defp update_candle(state, price) do
    now = System.system_time(:second)
    candle_start = div(now, @candle_interval) * @candle_interval

    if state.candle_start == candle_start do
      # Update existing candle
      candle = state.current_candle
      updated = %{candle |
        high: max(candle.high, price),
        low: min(candle.low, price),
        close: price
      }
      %{state | current_candle: updated}
    else
      # Save previous candle and start new one
      if state.current_candle do
        save_candle(state.current_candle)
      end

      new_candle = %{
        timestamp: candle_start,
        open: price,
        high: price,
        low: price,
        close: price
      }
      %{state | current_candle: new_candle, candle_start: candle_start}
    end
  end

  defp save_candle(candle) do
    record = {:lp_bux_candles, candle.timestamp, candle.open, candle.high,
              candle.low, candle.close}
    :mnesia.dirty_write(record)
  end

  defp broadcast_price(price, state) do
    Phoenix.PubSub.broadcast(BlocksterV2.PubSub, @pubsub_topic, {
      :lp_bux_price_updated,
      %{price: price, candle: state.current_candle}
    })
  end

  defp schedule_poll do
    Process.send_after(self(), :poll_price, @poll_interval)
  end

  defp parse_price(price_str) when is_binary(price_str) do
    case Integer.parse(price_str) do
      {price_int, _} -> price_int / 1.0e18  # Convert from 18-decimal to float
      :error ->
        case Float.parse(price_str) do
          {f, _} -> f
          :error -> 1.0
        end
    end
  end
  defp parse_price(price) when is_number(price), do: price / 1.0e18

  defp get_high_low(from, to) do
    candles = :mnesia.dirty_select(:lp_bux_candles, [
      {{:lp_bux_candles, :"$1", :"$2", :"$3", :"$4", :"$5"},
       [{:>=, :"$1", from}, {:"=<", :"$1", to}],
       [{{:"$3", :"$4"}}]}
    ])

    case candles do
      [] -> %{high: nil, low: nil}
      _ ->
        highs = Enum.map(candles, &elem(&1, 0))
        lows = Enum.map(candles, &elem(&1, 1))
        %{high: Enum.max(highs), low: Enum.min(lows)}
    end
  end

  defp aggregate_candles(base_candles, target_seconds) do
    base_candles
    |> Enum.group_by(fn {ts, _, _, _, _} ->
      div(ts, target_seconds) * target_seconds
    end)
    |> Enum.map(fn {group_ts, candles} ->
      opens = Enum.map(candles, &elem(&1, 1))
      highs = Enum.map(candles, &elem(&1, 2))
      lows = Enum.map(candles, &elem(&1, 3))
      closes = Enum.map(candles, &elem(&1, 4))

      %{
        time: group_ts,
        open: List.first(opens),
        high: Enum.max(highs),
        low: Enum.min(lows),
        close: List.last(closes)
      }
    end)
    |> Enum.sort_by(& &1.time)
  end

  defp table_ready?(table_name) do
    tables = :mnesia.system_info(:tables)

    if table_name in tables do
      case :mnesia.wait_for_tables([table_name], 1000) do
        :ok -> true
        {:timeout, _} -> false
        {:error, _} -> false
      end
    else
      false
    end
  catch
    :exit, _ -> false
  end
end
```

---

## 4. BuxMinter Additions (`lib/blockster_v2/bux_minter.ex`)

Add these functions to the existing `BlocksterV2.BuxMinter` module, before the private helpers section.

```elixir
  # ============ Plinko Game API Calls ============

  @doc "Submit commitment hash for Plinko game via BUX Minter"
  def plinko_submit_commitment(commitment_hash, player, nonce) do
    minter_url = get_minter_url()
    api_secret = get_api_secret()

    if is_nil(api_secret) or api_secret == "" do
      Logger.warning("[BuxMinter] API_SECRET not configured, skipping plinko commitment")
      {:error, :not_configured}
    else
      payload = %{
        "commitmentHash" => commitment_hash,
        "player" => player,
        "nonce" => nonce
      }

      headers = [
        {"Content-Type", "application/json"},
        {"Authorization", "Bearer #{api_secret}"}
      ]

      case http_post("#{minter_url}/plinko/submit-commitment", Jason.encode!(payload), headers) do
        {:ok, %{status_code: 200, body: body}} ->
          response = Jason.decode!(body)
          case response do
            %{"success" => true, "txHash" => tx_hash} -> {:ok, tx_hash}
            %{"error" => error} -> {:error, error}
            _ -> {:error, "Invalid response"}
          end

        {:ok, %{status_code: status, body: body}} ->
          error = Jason.decode!(body)
          Logger.error("[BuxMinter] Plinko commitment failed (#{status}): #{inspect(error)}")
          {:error, error["error"] || "HTTP #{status}"}

        {:error, reason} ->
          Logger.error("[BuxMinter] Plinko commitment HTTP error: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @doc "Settle Plinko bet on-chain (BUX path via BUXBankroll)"
  def plinko_settle_bet(commitment_hash, server_seed, path, landing_position) do
    minter_url = get_minter_url()
    api_secret = get_api_secret()

    if is_nil(api_secret) or api_secret == "" do
      {:error, :not_configured}
    else
      # Convert path atoms to integers (0 for left, 1 for right)
      path_int = Enum.map(path, fn
        :left -> 0
        0 -> 0
        :right -> 1
        1 -> 1
        _ -> 0
      end)

      payload = %{
        "commitmentHash" => commitment_hash,
        "serverSeed" => server_seed,
        "path" => path_int,
        "landingPosition" => landing_position
      }

      headers = [
        {"Content-Type", "application/json"},
        {"Authorization", "Bearer #{api_secret}"}
      ]

      case http_post("#{minter_url}/plinko/settle-bet", Jason.encode!(payload), headers) do
        {:ok, %{status_code: 200, body: body}} ->
          response = Jason.decode!(body)
          case response do
            %{"success" => true, "txHash" => tx_hash} ->
              {:ok, tx_hash, response["playerBalance"]}
            %{"error" => error} ->
              {:error, error}
            _ ->
              {:error, "Invalid response"}
          end

        {:ok, %{status_code: status, body: body}} ->
          error = Jason.decode!(body)
          {:error, error["error"] || "HTTP #{status}: #{body}"}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc "Settle Plinko ROGUE bet on-chain (via ROGUEBankroll)"
  def plinko_settle_bet_rogue(commitment_hash, server_seed, path, landing_position) do
    minter_url = get_minter_url()
    api_secret = get_api_secret()

    if is_nil(api_secret) or api_secret == "" do
      {:error, :not_configured}
    else
      path_int = Enum.map(path, fn
        :left -> 0
        0 -> 0
        :right -> 1
        1 -> 1
        _ -> 0
      end)

      payload = %{
        "commitmentHash" => commitment_hash,
        "serverSeed" => server_seed,
        "path" => path_int,
        "landingPosition" => landing_position
      }

      headers = [
        {"Content-Type", "application/json"},
        {"Authorization", "Bearer #{api_secret}"}
      ]

      case http_post("#{minter_url}/plinko/settle-bet-rogue", Jason.encode!(payload), headers) do
        {:ok, %{status_code: 200, body: body}} ->
          response = Jason.decode!(body)
          case response do
            %{"success" => true, "txHash" => tx_hash} ->
              {:ok, tx_hash, response["playerBalance"]}
            %{"error" => error} ->
              {:error, error}
            _ ->
              {:error, "Invalid response"}
          end

        {:ok, %{status_code: status, body: body}} ->
          error = Jason.decode!(body)
          {:error, error["error"] || "HTTP #{status}: #{body}"}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc "Get Plinko max BUX bet for a config (queries PlinkoGame which queries BUXBankroll)"
  def plinko_get_max_bet(config_index) do
    minter_url = get_minter_url()
    api_secret = get_api_secret()

    if is_nil(api_secret) or api_secret == "" do
      {:error, :not_configured}
    else
      headers = [{"Authorization", "Bearer #{api_secret}"}]

      case http_get("#{minter_url}/plinko/max-bet/#{config_index}", headers) do
        {:ok, %{status_code: 200, body: body}} ->
          response = Jason.decode!(body)
          {:ok, response["maxBet"]}

        {:ok, %{status_code: status, body: body}} ->
          error = Jason.decode!(body)
          {:error, error["error"] || "HTTP #{status}"}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # ============ BUX Bankroll API Calls ============

  @doc "Get BUX Bankroll house info (balance, LP supply, available liquidity)"
  def bux_bankroll_house_info do
    minter_url = get_minter_url()
    api_secret = get_api_secret()

    if is_nil(api_secret) or api_secret == "" do
      {:error, :not_configured}
    else
      headers = [{"Authorization", "Bearer #{api_secret}"}]

      case http_get("#{minter_url}/bux-bankroll/house-info", headers) do
        {:ok, %{status_code: 200, body: body}} ->
          {:ok, Jason.decode!(body)}

        {:ok, %{status_code: status, body: body}} ->
          error = Jason.decode!(body)
          {:error, error["error"] || "HTTP #{status}"}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc "Get current LP-BUX token price from BUXBankroll"
  def bux_bankroll_lp_price do
    minter_url = get_minter_url()
    api_secret = get_api_secret()

    if is_nil(api_secret) or api_secret == "" do
      {:error, :not_configured}
    else
      headers = [{"Authorization", "Bearer #{api_secret}"}]

      case http_get("#{minter_url}/bux-bankroll/lp-price", headers) do
        {:ok, %{status_code: 200, body: body}} ->
          response = Jason.decode!(body)
          {:ok, response["price"]}

        {:ok, %{status_code: status, body: body}} ->
          error = Jason.decode!(body)
          {:error, error["error"] || "HTTP #{status}"}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc "Get BUX Bankroll max bet for a config index"
  def bux_bankroll_max_bet(config_index) do
    minter_url = get_minter_url()
    api_secret = get_api_secret()

    if is_nil(api_secret) or api_secret == "" do
      {:error, :not_configured}
    else
      headers = [{"Authorization", "Bearer #{api_secret}"}]

      case http_get("#{minter_url}/bux-bankroll/max-bet/#{config_index}", headers) do
        {:ok, %{status_code: 200, body: body}} ->
          response = Jason.decode!(body)
          {:ok, response["maxBet"]}

        {:ok, %{status_code: status, body: body}} ->
          error = Jason.decode!(body)
          {:error, error["error"] || "HTTP #{status}"}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end
```

---

## 5. MnesiaInitializer Additions (`lib/blockster_v2/mnesia_initializer.ex`)

Add these two table definitions to the `@tables` list in `MnesiaInitializer`, after the existing `:upcoming_events` table.

```elixir
    # Plinko game sessions (provably fair, commit-reveal pattern)
    %{
      name: :plinko_games,
      type: :ordered_set,
      attributes: [
        :game_id,            # PRIMARY KEY - 32-char hex
        :user_id,            # PostgreSQL user ID
        :wallet_address,     # Smart wallet address
        :server_seed,        # 64-char hex (revealed after settlement)
        :commitment_hash,    # 0x-prefixed SHA256
        :nonce,              # Player's game counter
        :status,             # :committed | :placed | :settled | :expired
        :bet_id,             # On-chain bet ID (commitment hash)
        :token,              # "BUX" or "ROGUE"
        :token_address,      # Token contract address
        :bet_amount,         # Amount wagered (integer tokens)
        :config_index,       # 0-8
        :rows,               # 8, 12, or 16
        :risk_level,         # :low, :medium, :high
        :ball_path,          # [:left, :right, ...] list
        :landing_position,   # 0 to rows (integer)
        :payout_bp,          # Payout multiplier in basis points
        :payout,             # Actual payout amount
        :won,                # Boolean (payout > bet)
        :commitment_tx,      # TX hash for submitCommitment
        :bet_tx,             # TX hash for placeBet
        :settlement_tx,      # TX hash for settleBet
        :created_at,         # Unix timestamp (updated to bet placement time)
        :settled_at          # Unix timestamp (nil until settled)
      ],
      index: [:user_id, :wallet_address, :status, :created_at]
    },
    # LP-BUX price candles for BankrollLive chart
    %{
      name: :lp_bux_candles,
      type: :ordered_set,
      attributes: [:timestamp, :open, :high, :low, :close],
      index: []
    }
```

---

## 6. Application.ex Additions (`lib/blockster_v2/application.ex`)

Add these two children to the `genserver_children` list, after the existing `{BlocksterV2.BuxBoosterBetSettler, []}` entry:

```elixir
        # Plinko bet settlement checker (runs every minute to settle stuck bets)
        {BlocksterV2.PlinkoSettler, []},
        # LP-BUX price tracker (polls BUXBankroll every 60s, stores OHLC candles)
        {BlocksterV2.LPBuxPriceTracker, []},
```

---

## 7. Router.ex Additions (`lib/blockster_v2_web/router.ex`)

Add these routes to the `:default` live_session in `router.ex`, alongside the existing `/play` route:

```elixir
      live "/plinko", PlinkoLive, :index
      live "/bankroll", BankrollLive, :index
```

These go inside the existing `live_session :default` block, which already has `SearchHook`, `UserAuth`, and `BuxBalanceHook` on_mount hooks.

---

## Summary of Changes

| File | Type | What Changes |
|------|------|-------------|
| `lib/blockster_v2/plinko_game.ex` | NEW | Full game orchestration (get_or_init_game, init_game_with_nonce, calculate_result, on_bet_placed, settle_game, mark_game_settled, get_game, get_pending_game, load_recent_games, update_user_betting_stats) |
| `lib/blockster_v2/plinko_settler.ex` | NEW | GenServer global singleton, checks every 60s for stuck :placed games older than 120s |
| `lib/blockster_v2/lp_bux_price_tracker.ex` | NEW | GenServer global singleton, polls LP-BUX price every 60s, stores 5-min OHLC candles in Mnesia, broadcasts via PubSub |
| `lib/blockster_v2/bux_minter.ex` | MODIFIED | Add 7 functions: plinko_submit_commitment, plinko_settle_bet, plinko_settle_bet_rogue, plinko_get_max_bet, bux_bankroll_house_info, bux_bankroll_lp_price, bux_bankroll_max_bet |
| `lib/blockster_v2/mnesia_initializer.ex` | MODIFIED | Add 2 table definitions to @tables: :plinko_games (24 fields, ordered_set), :lp_bux_candles (5 fields, ordered_set) |
| `lib/blockster_v2/application.ex` | MODIFIED | Add 2 children: PlinkoSettler, LPBuxPriceTracker |
| `lib/blockster_v2_web/router.ex` | MODIFIED | Add 2 routes: /plinko, /bankroll |
