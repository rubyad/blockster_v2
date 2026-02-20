defmodule BlocksterV2.PlinkoGame do
  @moduledoc """
  Plinko game orchestration module. Handles game lifecycle:
  committed -> placed -> settled.

  Follows BuxBoosterOnchain patterns for Mnesia state management,
  server seed generation, and commit-reveal provably fair system.
  """

  alias BlocksterV2.BuxMinter
  require Logger

  # ============ Module Attributes ============

  @plinko_contract_address "0x7E12c7077556B142F8Fb695F70aAe0359a8be10C"

  @configs %{
    0 => {8, :low},    1 => {8, :medium},  2 => {8, :high},
    3 => {12, :low},   4 => {12, :medium}, 5 => {12, :high},
    6 => {16, :low},   7 => {16, :medium}, 8 => {16, :high}
  }

  @token_addresses %{
    "BUX" => "0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8",
    "ROGUE" => "0x0000000000000000000000000000000000000000"
  }

  # Payout tables in basis points — MUST match contract exactly
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

  # ============ Public Accessors ============

  def configs, do: @configs
  def payout_tables, do: @payout_tables
  def plinko_contract_address, do: @plinko_contract_address

  def token_address("ROGUE"), do: "0x0000000000000000000000000000000000000000"
  def token_address(token), do: Map.get(@token_addresses, token, token)

  # ============ Game Lifecycle ============

  @doc """
  Get or create a game for a user. Reuses existing committed game if the nonce
  matches; otherwise creates a new one with the next nonce.
  """
  def get_or_init_game(user_id, wallet_address) do
    # Calculate next nonce from Mnesia based on placed/settled games
    next_nonce =
      case :mnesia.dirty_match_object(
             {:plinko_games, :_, user_id, wallet_address, :_, :_, :_, :_, :_, :_, :_, :_, :_,
              :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}
           ) do
        [] ->
          0

        games ->
          placed_games = Enum.filter(games, fn game -> elem(game, 7) in [:placed, :settled] end)

          case placed_games do
            [] ->
              0

            _ ->
              placed_games
              |> Enum.map(fn game -> elem(game, 6) end)
              |> Enum.max()
              |> Kernel.+(1)
          end
      end

    # Check for reusable committed game with correct nonce
    case get_pending_game(user_id) do
      %{wallet_address: ^wallet_address, commitment_tx: tx, nonce: nonce} = existing
      when tx != nil and nonce == next_nonce ->
        Logger.info("[PlinkoGame] Reusing existing game: #{existing.game_id}")

        {:ok,
         %{
           game_id: existing.game_id,
           commitment_hash: existing.commitment_hash,
           commitment_tx: existing.commitment_tx,
           nonce: existing.nonce
         }}

      _ ->
        Logger.info("[PlinkoGame] Creating new game with nonce #{next_nonce}")
        init_game_with_nonce(user_id, wallet_address, next_nonce)
    end
  end

  @doc """
  Create a new game: generate server seed, submit commitment on-chain, write to Mnesia.
  """
  def init_game_with_nonce(user_id, wallet_address, nonce) do
    # Generate server seed (32 bytes as hex string without 0x prefix)
    server_seed = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)

    # Calculate commitment hash: SHA256 of the hex string (matches BuxBooster pattern)
    commitment_hash_bytes = :crypto.hash(:sha256, server_seed)
    commitment_hash = "0x" <> Base.encode16(commitment_hash_bytes, case: :lower)

    game_id = generate_game_id()
    now = System.system_time(:second)

    # Submit commitment to contract via BUX Minter
    case BuxMinter.plinko_submit_commitment(commitment_hash, wallet_address, nonce) do
      {:ok, tx_hash} ->
        Logger.info(
          "[PlinkoGame] Commitment submitted - TX: #{tx_hash}, Player: #{wallet_address}, Nonce: #{nonce}"
        )

        # Write :committed game to Mnesia (25-element tuple: table name + 24 fields)
        game_record =
          {:plinko_games, game_id, user_id, wallet_address, server_seed, commitment_hash, nonce,
           :committed, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, tx_hash, nil, nil,
           now, nil}

        :mnesia.dirty_write(game_record)

        {:ok,
         %{
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
  Update game after bet is placed on-chain. Calculates ball path + payout locally.
  """
  def on_bet_placed(game_id, bet_id, bet_tx, bet_amount, token, config_index) do
    case get_game(game_id) do
      {:ok, game} ->
        token_addr = Map.get(@token_addresses, token, token)
        {rows, risk_level} = Map.get(@configs, config_index)

        # Calculate result locally (we have the server seed)
        {:ok, result} =
          calculate_result(game.server_seed, game.nonce, config_index, bet_amount, token, game.user_id)

        now = System.system_time(:second)

        # Full Mnesia tuple (25 positions: table name + 24 fields)
        updated_record =
          {:plinko_games, game_id, game.user_id, game.wallet_address, game.server_seed,
           game.commitment_hash, game.nonce, :placed, bet_id, token, token_addr, bet_amount,
           config_index, rows, risk_level, result.ball_path, result.landing_position,
           result.payout_bp, result.payout, result.won, game.commitment_tx, bet_tx, nil, now, nil}

        :mnesia.dirty_write(updated_record)

        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Settle a placed game on-chain via BUX Minter.
  The minter auto-detects BUX vs ROGUE from the on-chain bet.
  """
  def settle_game(game_id) do
    case get_game(game_id) do
      {:ok, game} when game.status == :settled ->
        Logger.debug("[PlinkoGame] Game #{game_id} already settled, skipping")
        {:ok, %{tx_hash: game.settlement_tx, player_balance: nil, already_settled: true}}

      {:ok, game} when game.bet_id != nil ->
        server_seed_hex = "0x" <> game.server_seed

        case BuxMinter.plinko_settle_bet(
               game.commitment_hash,
               server_seed_hex,
               game.ball_path,
               game.landing_position
             ) do
          {:ok, tx_hash, player_balance} ->
            mark_game_settled(game_id, game, tx_hash)
            update_user_betting_stats(game.user_id, game.token, game.bet_amount, game.won, game.payout)

            # Sync balances and broadcast
            if game.wallet_address do
              BuxMinter.sync_user_balances_async(game.user_id, game.wallet_address, force: true)
            end

            Phoenix.PubSub.broadcast(
              BlocksterV2.PubSub,
              "plinko_settlement:#{game.user_id}",
              {:plinko_settled, game_id, tx_hash}
            )

            Logger.info("[PlinkoGame] Game #{game_id} settled: #{tx_hash}")
            {:ok, %{tx_hash: tx_hash, player_balance: player_balance}}

          {:error, reason} ->
            if is_bet_already_settled_error?(reason) do
              Logger.info("[PlinkoGame] Game #{game_id} already settled on-chain")
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
  Write :settled status to Mnesia with settlement TX hash.
  """
  def mark_game_settled(game_id, game, tx_hash) do
    now = System.system_time(:second)

    settled_record =
      {:plinko_games, game_id, game.user_id, game.wallet_address, game.server_seed,
       game.commitment_hash, game.nonce, :settled, game.bet_id, game.token, game.token_address,
       game.bet_amount, game.config_index, game.rows, game.risk_level, game.ball_path,
       game.landing_position, game.payout_bp, game.payout, game.won, game.commitment_tx,
       game.bet_tx, tx_hash, game.created_at, now}

    :mnesia.dirty_write(settled_record)
  end

  # ============ Result Calculation ============

  @doc """
  Calculate Plinko result from server seed. Deterministic and provably fair.

  The ball path is derived from SHA256(server_seed:client_seed:nonce).
  Each byte < 128 = left, >= 128 = right. Landing position = count of rights.
  """
  def calculate_result(server_seed, nonce, config_index, bet_amount, token, user_id) do
    {rows, _risk_level} = Map.get(@configs, config_index)

    # Client seed — deterministic from player-controlled values
    input = "#{user_id}:#{bet_amount}:#{token}:#{config_index}"
    client_seed = :crypto.hash(:sha256, input) |> Base.encode16(case: :lower)

    # Combined seed (matches BuxBooster pattern)
    combined = :crypto.hash(:sha256, "#{server_seed}:#{client_seed}:#{nonce}")

    # Ball path: first `rows` bytes
    ball_path =
      for i <- 0..(rows - 1) do
        byte = :binary.at(combined, i)
        if byte < 128, do: :left, else: :right
      end

    # Landing position = count of :right bounces
    landing_position = Enum.count(ball_path, &(&1 == :right))

    # Payout lookup
    payout_table = Map.get(@payout_tables, config_index)
    payout_bp = Enum.at(payout_table, landing_position)
    payout = div(bet_amount * payout_bp, 10000)

    outcome =
      cond do
        payout > bet_amount -> :won
        payout == bet_amount -> :push
        true -> :lost
      end

    {:ok,
     %{
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
  Wrapper that reads game from Mnesia and delegates to calculate_result/6.
  """
  def calculate_game_result(game_id, config_index, bet_amount, token, user_id) do
    case get_game(game_id) do
      {:ok, game} ->
        calculate_result(game.server_seed, game.nonce, config_index, bet_amount, token, user_id)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ============ Mnesia Reads ============

  @doc """
  Read a single game from Mnesia by game_id.
  """
  def get_game(game_id) do
    case :mnesia.dirty_read({:plinko_games, game_id}) do
      [{:plinko_games, ^game_id, user_id, wallet_address, server_seed, commitment_hash, nonce,
        status, bet_id, token, token_address, bet_amount, config_index, rows, risk_level,
        ball_path, landing_position, payout_bp, payout, won, commitment_tx, bet_tx, settlement_tx,
        created_at, settled_at}] ->
        {:ok,
         %{
           game_id: game_id,
           user_id: user_id,
           wallet_address: wallet_address,
           server_seed: server_seed,
           commitment_hash: commitment_hash,
           nonce: nonce,
           status: status,
           bet_id: bet_id,
           token: token,
           token_address: token_address,
           bet_amount: bet_amount,
           config_index: config_index,
           rows: rows,
           risk_level: risk_level,
           ball_path: ball_path,
           landing_position: landing_position,
           payout_bp: payout_bp,
           payout: payout,
           won: won,
           commitment_tx: commitment_tx,
           bet_tx: bet_tx,
           settlement_tx: settlement_tx,
           created_at: created_at,
           settled_at: settled_at
         }}

      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  Find the most recent :committed game for a user (reusable commitment).
  """
  def get_pending_game(user_id) do
    case :mnesia.dirty_index_read(:plinko_games, user_id, :user_id) do
      games when is_list(games) and length(games) > 0 ->
        pending_game =
          games
          |> Enum.filter(fn record -> elem(record, 7) == :committed end)
          |> Enum.sort_by(fn record -> elem(record, 23) end, :desc)
          |> List.first()

        case pending_game do
          nil ->
            nil

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
  end

  @doc """
  Load recent settled games for a user (for game history).
  """
  def load_recent_games(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 30)
    offset = Keyword.get(opts, :offset, 0)

    :mnesia.dirty_index_read(:plinko_games, user_id, :user_id)
    |> Enum.filter(fn game -> elem(game, 7) == :settled end)
    |> Enum.sort_by(fn game -> elem(game, 23) end, :desc)
    |> Enum.drop(offset)
    |> Enum.take(limit)
    |> Enum.map(&game_tuple_to_map/1)
  end

  # ============ Private Helpers ============

  defp generate_game_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  defp game_tuple_to_map(
         {:plinko_games, game_id, user_id, wallet_address, server_seed, commitment_hash, nonce,
          status, bet_id, token, token_address, bet_amount, config_index, rows, risk_level,
          ball_path, landing_position, payout_bp, payout, won, commitment_tx, bet_tx,
          settlement_tx, created_at, settled_at}
       ) do
    %{
      game_id: game_id,
      user_id: user_id,
      wallet_address: wallet_address,
      server_seed: server_seed,
      commitment_hash: commitment_hash,
      nonce: nonce,
      status: status,
      bet_id: bet_id,
      token: token,
      token_address: token_address,
      bet_amount: bet_amount,
      config_index: config_index,
      rows: rows,
      risk_level: risk_level,
      ball_path: ball_path,
      landing_position: landing_position,
      payout_bp: payout_bp,
      payout: payout,
      won: won,
      commitment_tx: commitment_tx,
      bet_tx: bet_tx,
      settlement_tx: settlement_tx,
      created_at: created_at,
      settled_at: settled_at
    }
  end

  defp update_user_betting_stats(user_id, token, bet_amount, won, payout) do
    case :mnesia.dirty_read(:user_betting_stats, user_id) do
      [record] ->
        now = System.system_time(:millisecond)
        first_bet_at = elem(record, 17) || now

        updated =
          case token do
            "ROGUE" -> update_rogue_stats(record, bet_amount, won, payout, now, first_bet_at)
            _ -> update_bux_stats(record, bet_amount, won, payout, now, first_bet_at)
          end

        :mnesia.dirty_write(updated)

      [] ->
        Logger.warning("[PlinkoGame] Missing user_betting_stats for user #{user_id}, creating now")
        now = System.system_time(:millisecond)
        bet_amount_wei = to_wei(bet_amount)
        payout_wei = to_wei(payout)

        {bux_stats, rogue_stats} =
          case token do
            "ROGUE" ->
              rogue = calculate_stats(bet_amount_wei, won, payout_wei)
              {{0, 0, 0, 0, 0, 0, 0}, rogue}

            _ ->
              bux = calculate_stats(bet_amount_wei, won, payout_wei)
              {bux, {0, 0, 0, 0, 0, 0, 0}}
          end

        {bux_bets, bux_wins, bux_losses, bux_wagered, bux_winnings, bux_losses_amt, bux_pnl} =
          bux_stats

        {rogue_bets, rogue_wins, rogue_losses, rogue_wagered, rogue_winnings, rogue_losses_amt,
         rogue_pnl} = rogue_stats

        record =
          {:user_betting_stats, user_id, "", bux_bets, bux_wins, bux_losses, bux_wagered,
           bux_winnings, bux_losses_amt, bux_pnl, rogue_bets, rogue_wins, rogue_losses,
           rogue_wagered, rogue_winnings, rogue_losses_amt, rogue_pnl, now, now, now, nil}

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
    |> put_elem(3, elem(record, 3) + 1)
    |> put_elem(4, elem(record, 4) + if(won, do: 1, else: 0))
    |> put_elem(5, elem(record, 5) + if(won, do: 0, else: 1))
    |> put_elem(6, elem(record, 6) + bet_amount_wei)
    |> put_elem(7, elem(record, 7) + winnings)
    |> put_elem(8, elem(record, 8) + losses)
    |> put_elem(9, elem(record, 9) + net_change)
    |> put_elem(17, first_bet_at)
    |> put_elem(18, now)
    |> put_elem(19, now)
  end

  defp update_rogue_stats(record, bet_amount, won, payout, now, first_bet_at) do
    bet_amount_wei = to_wei(bet_amount)
    payout_wei = to_wei(payout)
    winnings = if won, do: payout_wei - bet_amount_wei, else: 0
    losses = if won, do: 0, else: bet_amount_wei
    net_change = if won, do: payout_wei - bet_amount_wei, else: -bet_amount_wei

    record
    |> put_elem(10, elem(record, 10) + 1)
    |> put_elem(11, elem(record, 11) + if(won, do: 1, else: 0))
    |> put_elem(12, elem(record, 12) + if(won, do: 0, else: 1))
    |> put_elem(13, elem(record, 13) + bet_amount_wei)
    |> put_elem(14, elem(record, 14) + winnings)
    |> put_elem(15, elem(record, 15) + losses)
    |> put_elem(16, elem(record, 16) + net_change)
    |> put_elem(17, first_bet_at)
    |> put_elem(18, now)
    |> put_elem(19, now)
  end

  defp calculate_stats(bet_amount_wei, won, payout_wei) do
    winnings = if won, do: payout_wei - bet_amount_wei, else: 0
    losses = if won, do: 0, else: bet_amount_wei
    net = if won, do: payout_wei - bet_amount_wei, else: -bet_amount_wei
    wins = if won, do: 1, else: 0
    loss_count = if won, do: 0, else: 1
    {1, wins, loss_count, bet_amount_wei, winnings, losses, net}
  end

  defp to_wei(amount) when is_integer(amount), do: amount * 1_000_000_000_000_000_000
  defp to_wei(amount) when is_float(amount), do: round(amount * 1_000_000_000_000_000_000)
  defp to_wei(nil), do: 0

  defp is_bet_already_settled_error?(reason) when is_binary(reason) do
    String.contains?(reason, "0x05d09e5f")
  end

  defp is_bet_already_settled_error?(_), do: false
end
