defmodule BlocksterV2.CoinFlipGame do
  @moduledoc """
  Solana Coin Flip game orchestration (Phase 6 migration).

  Replaces BuxBoosterOnchain for new games on Solana. Same provably fair logic,
  same game flow, but targets the Solana settler service and uses a clean
  Mnesia table (:coin_flip_games) without EVM-specific fields.

  ## Game Flow
  1. Server generates server seed, stores in Mnesia
  2. Commitment hash (SHA256 of server seed) submitted to bankroll via settler
  3. Player places bet (SOL or BUX) — settler builds tx, wallet signs
  4. Results calculated immediately (optimistic UI)
  5. Settlement happens in background via settler

  ## Mnesia Table: :coin_flip_games
  Primary key: game_id (32-char hex string)
  """

  alias BlocksterV2.EngagementTracker
  require Logger

  # Multipliers in basis points (10000 = 1x) - matches bankroll program
  @multipliers %{
    -4 => 10200,
    -3 => 10500,
    -2 => 11300,
    -1 => 13200,
    1 => 19800,
    2 => 39600,
    3 => 79200,
    4 => 158400,
    5 => 316800
  }

  defp settler_url do
    Application.get_env(:blockster_v2, :settler_url) || "http://localhost:3000"
  end

  defp get_api_secret do
    Application.get_env(:blockster_v2, :settler_secret) ||
      Application.get_env(:blockster_v2, :bux_minter_secret) ||
      System.get_env("SETTLER_SECRET") ||
      System.get_env("BUX_MINTER_SECRET")
  end

  @doc """
  Initialize a new game session with explicit nonce.
  Generates server seed, stores in Mnesia, submits commitment to bankroll via settler.

  Returns {:ok, %{game_id, commitment_hash, commitment_sig, nonce}} or {:error, reason}
  """
  def init_game_with_nonce(user_id, wallet_address, nonce) do
    # Generate server seed (32 bytes as hex string without prefix)
    raw_seed = :crypto.strong_rand_bytes(32)
    server_seed = Base.encode16(raw_seed, case: :lower)

    # Commitment hash of RAW bytes (must match what Rust program hashes on-chain)
    commitment_hash_bytes = :crypto.hash(:sha256, raw_seed)
    commitment_hash = Base.encode16(commitment_hash_bytes, case: :lower)

    # Generate game ID (primary key)
    game_id = generate_game_id()
    now = System.system_time(:second)

    # Submit commitment to bankroll program via settler
    case submit_commitment(commitment_hash, wallet_address, nonce) do
      {:ok, signature} ->
        Logger.info("[CoinFlipGame] Commitment submitted - sig: #{signature}, player: #{wallet_address}, nonce: #{nonce}")

        game_record = {
          :coin_flip_games,
          game_id,              # PRIMARY KEY
          user_id,
          wallet_address,
          server_seed,
          commitment_hash,
          nonce,
          :committed,           # status
          nil,                  # vault_type (set when bet placed)
          nil,                  # bet_amount
          nil,                  # difficulty
          nil,                  # predictions
          nil,                  # results
          nil,                  # won
          nil,                  # payout
          signature,            # commitment_sig
          nil,                  # bet_sig
          nil,                  # settlement_sig
          now,                  # created_at
          nil                   # settled_at
        }
        :mnesia.dirty_write(game_record)

        {:ok, %{
          game_id: game_id,
          commitment_hash: commitment_hash,
          commitment_sig: signature,
          nonce: nonce
        }}

      {:error, reason} ->
        Logger.error("[CoinFlipGame] Failed to submit commitment for nonce #{nonce}, player #{wallet_address}: #{inspect(reason)}")
        reason_str = if is_binary(reason), do: reason, else: inspect(reason)
        if String.contains?(reason_str, "NonceMismatch") or String.contains?(reason_str, "0x1771") do
          {:error, {:nonce_mismatch, nonce}}
        else
          {:error, reason}
        end
    end
  end

  @doc """
  Calculate game result BEFORE placing bet on-chain (for optimistic UI).
  Uses server seed already stored in Mnesia to generate results immediately.
  """
  def calculate_game_result(game_id, predictions, bet_amount, vault_type, difficulty) do
    case get_game(game_id) do
      {:ok, game} ->
        calculate_result(
          game.server_seed,
          game.nonce,
          predictions,
          bet_amount,
          vault_type,
          difficulty,
          game.user_id
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Called when player's bet is placed on Solana.
  Updates the game record with bet details and calculates the result.
  """
  def on_bet_placed(game_id, bet_sig, predictions, bet_amount, vault_type, difficulty) do
    case get_game(game_id) do
      {:ok, game} ->
        # Calculate result locally (we have the server seed)
        {:ok, result} = calculate_result(
          game.server_seed, game.nonce, predictions, bet_amount, vault_type,
          difficulty, game.user_id
        )

        # Update created_at to NOW when bet is actually placed
        # Important for BetSettler which uses created_at to determine if a bet is stuck
        now = System.system_time(:second)

        updated_record = {
          :coin_flip_games,
          game_id,
          game.user_id,
          game.wallet_address,
          game.server_seed,
          game.commitment_hash,
          game.nonce,
          :placed,                  # status
          vault_type,               # vault_type (:sol or :bux)
          bet_amount,
          difficulty,
          predictions,
          result.results,
          result.won,
          result.payout,
          game.commitment_sig,
          bet_sig,                  # bet_sig
          nil,                      # settlement_sig
          now,                      # created_at (updated to bet placement time)
          nil                       # settled_at
        }
        :mnesia.dirty_write(updated_record)

        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Calculate game result from server seed and bet details.
  Same provably fair algorithm as BuxBoosterOnchain.
  """
  def calculate_result(server_seed, nonce, predictions, bet_amount, vault_type, difficulty, user_id) do
    # Generate client seed from bet details (deterministic from player choices only)
    client_seed_binary = generate_client_seed_from_bet(user_id, bet_amount, vault_type, difficulty, predictions)
    client_seed_hex = Base.encode16(client_seed_binary, case: :lower)

    # Combined seed (SHA256(server_hex:client_hex:nonce))
    combined_input = "#{server_seed}:#{client_seed_hex}:#{nonce}"
    combined_seed = :crypto.hash(:sha256, combined_input)

    # Generate flip results
    num_flips = get_flip_count(difficulty)
    results = generate_flip_results(combined_seed, num_flips)

    # Determine win/loss based on game mode
    won = check_win(predictions, results, difficulty)

    Logger.debug("[CoinFlipGame] Result calculated for game")

    # Calculate payout
    payout = if won, do: calculate_payout(bet_amount, difficulty), else: 0

    {:ok, %{
      results: results,
      won: won,
      payout: payout,
      server_seed: server_seed
    }}
  end

  @doc """
  Settle the bet on the bankroll program after animation completes.
  Calls settler to submit settlement transaction.
  """
  def settle_game(game_id) do
    case get_game(game_id) do
      {:ok, game} when game.status == :settled ->
        Logger.debug("[CoinFlipGame] Game #{game_id} already settled, skipping")
        {:ok, %{signature: game.settlement_sig, already_settled: true}}

      {:ok, game} when game.status == :manual_review ->
        Logger.debug("[CoinFlipGame] Game #{game_id} in manual_review — skipping settle attempts")
        {:error, :manual_review}

      {:ok, game} when game.status == :placed ->
        attempt_settle(game_id, game, game.server_seed)

      {:ok, _game} ->
        {:error, :bet_not_placed}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp attempt_settle(game_id, game, server_seed) do
    case settle_bet(game.wallet_address, game.nonce, server_seed, game.won, game.payout, game.vault_type) do
      {:ok, signature} ->
        mark_game_settled(game_id, game, signature)
        update_user_betting_stats(game.user_id, game.vault_type, game.bet_amount, game.won, game.payout)
        broadcast_pool_activity(game)
        broadcast_bet_settled(game.vault_type)
        broadcast_game_settled(game, signature)
        Logger.info("[CoinFlipGame] Game #{game_id} settled: #{signature}")
        {:ok, %{signature: signature}}

      {:error, {:commitment_mismatch, onchain_commitment, _computed}} ->
        handle_commitment_mismatch(game_id, game, onchain_commitment)

      {:error, reason} ->
        if is_already_settled_error?(reason) do
          Logger.info("[CoinFlipGame] Game #{game_id} was already settled on-chain, marking as settled")
          mark_game_settled(game_id, game, "already_settled_on_chain")
          update_user_betting_stats(game.user_id, game.vault_type, game.bet_amount, game.won, game.payout)
          broadcast_pool_activity(game)
          broadcast_bet_settled(game.vault_type)
          broadcast_game_settled(game, "already_settled_on_chain")
          {:ok, %{signature: "already_settled_on_chain", already_settled: true}}
        else
          Logger.error("[CoinFlipGame] Failed to settle game #{game_id}: #{inspect(reason)}")
          {:error, reason}
        end
    end
  end

  # CF-01 recovery path. The settler reported SHA256(our server_seed) does
  # NOT match the on-chain bet_order.commitment_hash. This is the
  # pending_commitment race: two submit_commitment calls landed between
  # place_bet attempts and the chain stored commitment B while Mnesia's
  # per-game record holds seed A. Look up the Mnesia row whose
  # commitment_hash matches what's actually on chain; if we find a seed
  # whose SHA256 matches, resettle with THAT seed. If not, this bet is
  # unrecoverable — mark it :manual_review so the background settler
  # stops retrying (see CoinFlipBetSettler + PR 2b dead-letter queue).
  defp handle_commitment_mismatch(game_id, game, onchain_commitment) when is_binary(onchain_commitment) do
    case get_game_by_commitment_hash(onchain_commitment) do
      {:ok, alt_game} when alt_game.game_id == game_id ->
        # Same game — the on-chain commitment matches our stored
        # commitment_hash but SHA256(seed) doesn't. Internal corruption:
        # stored seed doesn't hash to stored commitment. Mark manual_review.
        Logger.error(
          "[CoinFlipGame] Game #{game_id} commitment_mismatch points back to the same row — " <>
            "stored server_seed does not hash to stored commitment_hash. Marking manual_review."
        )
        mark_game_manual_review(game_id, game, "commitment_mismatch_self")
        {:error, :manual_review}

      {:ok, alt_game} ->
        Logger.warning(
          "[CoinFlipGame] Game #{game_id} commitment_mismatch — on-chain commitment " <>
            "#{onchain_commitment} matches game #{alt_game.game_id}; resettling with its seed"
        )
        # Flag the original (now-orphaned) game for manual_review so it
        # doesn't get retried. Then re-submit settlement with the correct
        # seed but the original bet's nonce/vault/payout.
        mark_game_manual_review(game_id, game, "commitment_mismatch_superseded_by_#{alt_game.game_id}")
        attempt_settle(game_id, game, alt_game.server_seed)

      {:error, :not_found} ->
        Logger.error(
          "[CoinFlipGame] Game #{game_id} commitment_mismatch — no Mnesia seed matches on-chain " <>
            "commitment #{onchain_commitment}. Marking manual_review."
        )
        mark_game_manual_review(game_id, game, "commitment_mismatch_no_seed")
        {:error, :manual_review}
    end
  end

  defp handle_commitment_mismatch(game_id, game, _nil_or_bad_hash) do
    Logger.error("[CoinFlipGame] Game #{game_id} commitment_mismatch with no onchain hash — marking manual_review")
    mark_game_manual_review(game_id, game, "commitment_mismatch_bad_response")
    {:error, :manual_review}
  end

  defp is_already_settled_error?(reason) when is_binary(reason) do
    String.contains?(reason, "already") and String.contains?(reason, "settled")
  end
  defp is_already_settled_error?(_), do: false

  defp mark_game_settled(game_id, game, signature) do
    now = System.system_time(:second)
    updated_record = {
      :coin_flip_games,
      game_id,
      game.user_id,
      game.wallet_address,
      game.server_seed,
      game.commitment_hash,
      game.nonce,
      :settled,
      game.vault_type,
      game.bet_amount,
      game.difficulty,
      game.predictions,
      game.results,
      game.won,
      game.payout,
      game.commitment_sig,
      game.bet_sig,
      signature,                  # settlement_sig
      game.created_at,
      now                         # settled_at
    }
    :mnesia.dirty_write(updated_record)
  end

  # Park a bet in :manual_review so the background settler stops retrying
  # it. Writes a short reason into the settlement_sig slot for debugging
  # (the slot is unused for unsettled bets; no real signature is lost).
  defp mark_game_manual_review(game_id, game, reason) do
    now = System.system_time(:second)
    updated_record = {
      :coin_flip_games,
      game_id,
      game.user_id,
      game.wallet_address,
      game.server_seed,
      game.commitment_hash,
      game.nonce,
      :manual_review,
      game.vault_type,
      game.bet_amount,
      game.difficulty,
      game.predictions,
      game.results,
      game.won,
      game.payout,
      game.commitment_sig,
      game.bet_sig,
      "manual_review:#{reason}",
      game.created_at,
      now
    }
    :mnesia.dirty_write(updated_record)
  end

  # User-scoped broadcast so both direct settlement (from the LV settle call)
  # AND background CoinFlipBetSettler settlements update the user's
  # "Recent games" panel live. settlement_sig is passed in because `game`
  # in the caller's scope is a snapshot from BEFORE mark_game_settled wrote
  # the new signature. Falls back silently if PubSub isn't running (test
  # env without the supervisor).
  defp broadcast_game_settled(game, settlement_sig) do
    user_id = game.user_id

    payload = %{
      game_id: game.game_id,
      vault_type:
        if(is_atom(game.vault_type), do: Atom.to_string(game.vault_type), else: to_string(game.vault_type)),
      bet_amount: game.bet_amount,
      difficulty: game.difficulty,
      # Keep multiplier derivable from @multipliers so the LV's recent-games
      # render has the field it expects. Match the basis-points → float
      # conversion the LV does (get_multiplier_for_difficulty/1 / @multipliers).
      multiplier: Map.get(@multipliers, game.difficulty, 10000) / 10000,
      predictions: game.predictions,
      results: game.results,
      won: game.won,
      payout: game.payout,
      commitment_hash: game.commitment_hash,
      server_seed: game.server_seed,
      nonce: game.nonce,
      commitment_sig: game.commitment_sig,
      bet_sig: game.bet_sig,
      settlement_sig: settlement_sig
    }

    Phoenix.PubSub.broadcast(
      BlocksterV2.PubSub,
      "coin_flip_settlement:#{user_id}",
      {:new_settled_game, payload}
    )

    Phoenix.PubSub.broadcast(
      BlocksterV2.PubSub,
      "coin_flip_settlement:#{user_id}",
      {:game_settled, game.game_id}
    )
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  defp broadcast_pool_activity(game) do
    vault_str = if is_atom(game.vault_type), do: Atom.to_string(game.vault_type), else: to_string(game.vault_type)
    token = String.upcase(vault_str)
    type = if game.won, do: "win", else: "loss"
    decimals = if vault_str == "sol", do: 4, else: 2

    bet_str = format_amount(game.bet_amount, decimals)
    payout_str = format_amount(game.payout, decimals)

    wallet = game.wallet_address || ""
    short_wallet = if byte_size(wallet) > 8 do
      "#{String.slice(wallet, 0, 4)}..#{String.slice(wallet, -4, 4)}"
    else
      wallet
    end

    activity = %{
      "type" => type,
      "game" => "Coin Flip",
      "game_id" => game.game_id,
      "commitment_sig" => game.commitment_sig,
      "bet_sig" => game.bet_sig,
      "settlement_sig" => game.settlement_sig,
      "bet" => "#{bet_str} #{token}",
      "payout" => "#{payout_str} #{token}",
      "profit" => format_profit(game.won, game.bet_amount, game.payout, decimals, token),
      "wallet" => short_wallet,
      "time" => "just now",
      "_created_at" => System.system_time(:second)
    }

    Phoenix.PubSub.broadcast(BlocksterV2.PubSub, "pool_activity:#{vault_str}", {:pool_activity, activity})
  rescue
    _ -> :ok
  end

  defp broadcast_bet_settled(vault_type) do
    vault_str = if is_atom(vault_type), do: Atom.to_string(vault_type), else: to_string(vault_type)
    Phoenix.PubSub.broadcast(BlocksterV2.PubSub, "pool:settlements", {:bet_settled, vault_str})
  rescue
    _ -> :ok
  end

  defp format_amount(nil, _), do: "0"
  defp format_amount(amount, decimals) when is_number(amount), do: smart_format(amount, decimals)
  defp format_amount(_, _), do: "0"

  # Use more decimals for small values so they don't display as 0.00
  defp smart_format(amount, min_decimals) when is_number(amount) do
    abs_val = abs(amount / 1.0)
    decimals = cond do
      abs_val >= 1.0 -> min_decimals
      abs_val >= 0.01 -> max(min_decimals, 4)
      abs_val >= 0.0001 -> max(min_decimals, 6)
      abs_val > 0 -> max(min_decimals, 8)
      true -> min_decimals
    end
    :erlang.float_to_binary(amount / 1.0, decimals: decimals) |> String.trim_trailing("0") |> String.trim_trailing(".")
  end

  defp format_profit(true, bet, payout, decimals, token) when is_number(bet) and is_number(payout) do
    profit = payout - bet
    "+#{smart_format(profit, decimals)} #{token}"
  end
  defp format_profit(false, bet, _payout, decimals, token) when is_number(bet) do
    "-#{smart_format(bet, decimals)} #{token}"
  end
  defp format_profit(_, _, _, _, _), do: ""

  defp update_user_betting_stats(user_id, vault_type, bet_amount, won, payout) do
    # Map vault_type to the existing stats format
    # BUX stats are used for :bux vault, SOL stats use the ROGUE slot (repurposed)
    token = if vault_type == :sol, do: "SOL", else: "BUX"

    case :mnesia.dirty_read(:user_betting_stats, user_id) do
      [record] ->
        now = System.system_time(:millisecond)
        first_bet_at = elem(record, 17) || now

        updated = case token do
          "SOL" -> update_sol_stats(record, bet_amount, won, payout, now, first_bet_at)
          _ -> update_bux_stats(record, bet_amount, won, payout, now, first_bet_at)
        end

        :mnesia.dirty_write(updated)

      [] ->
        # Create stats record if missing
        Logger.warning("[CoinFlipGame] Missing user_betting_stats for user #{user_id}, creating now")
        now = System.system_time(:millisecond)
        bet_amount_base = to_base_units(bet_amount, vault_type)
        payout_base = to_base_units(payout, vault_type)

        {bux_stats, sol_stats} = case token do
          "SOL" ->
            sol = calculate_stats(bet_amount_base, won, payout_base)
            {{0, 0, 0, 0, 0, 0, 0}, sol}
          _ ->
            bux = calculate_stats(bet_amount_base, won, payout_base)
            {bux, {0, 0, 0, 0, 0, 0, 0}}
        end

        {bux_bets, bux_wins, bux_losses, bux_wagered, bux_winnings, bux_losses_amt, bux_pnl} = bux_stats
        {sol_bets, sol_wins, sol_losses, sol_wagered, sol_winnings, sol_losses_amt, sol_pnl} = sol_stats

        record = {:user_betting_stats, user_id, "",
          bux_bets, bux_wins, bux_losses, bux_wagered, bux_winnings, bux_losses_amt, bux_pnl,
          sol_bets, sol_wins, sol_losses, sol_wagered, sol_winnings, sol_losses_amt, sol_pnl,
          now, now, now,
          nil}
        :mnesia.dirty_write(record)
    end
    :ok
  end

  # SOL stats reuse the ROGUE slot positions (10-16) in user_betting_stats
  defp update_sol_stats(record, bet_amount, won, payout, now, first_bet_at) do
    bet_base = to_base_units(bet_amount, :sol)
    payout_base = to_base_units(payout, :sol)
    winnings = if won, do: payout_base - bet_base, else: 0
    losses = if won, do: 0, else: bet_base
    net_change = if won, do: payout_base - bet_base, else: -bet_base

    record
    |> put_elem(10, elem(record, 10) + 1)
    |> put_elem(11, elem(record, 11) + (if won, do: 1, else: 0))
    |> put_elem(12, elem(record, 12) + (if won, do: 0, else: 1))
    |> put_elem(13, elem(record, 13) + bet_base)
    |> put_elem(14, elem(record, 14) + winnings)
    |> put_elem(15, elem(record, 15) + losses)
    |> put_elem(16, elem(record, 16) + net_change)
    |> put_elem(17, first_bet_at)
    |> put_elem(18, now)
    |> put_elem(19, now)
  end

  defp update_bux_stats(record, bet_amount, won, payout, now, first_bet_at) do
    bet_base = to_base_units(bet_amount, :bux)
    payout_base = to_base_units(payout, :bux)
    winnings = if won, do: payout_base - bet_base, else: 0
    losses = if won, do: 0, else: bet_base
    net_change = if won, do: payout_base - bet_base, else: -bet_base

    record
    |> put_elem(3, elem(record, 3) + 1)
    |> put_elem(4, elem(record, 4) + (if won, do: 1, else: 0))
    |> put_elem(5, elem(record, 5) + (if won, do: 0, else: 1))
    |> put_elem(6, elem(record, 6) + bet_base)
    |> put_elem(7, elem(record, 7) + winnings)
    |> put_elem(8, elem(record, 8) + losses)
    |> put_elem(9, elem(record, 9) + net_change)
    |> put_elem(17, first_bet_at)
    |> put_elem(18, now)
    |> put_elem(19, now)
  end

  defp calculate_stats(bet_base, won, payout_base) do
    winnings = if won, do: payout_base - bet_base, else: 0
    losses = if won, do: 0, else: bet_base
    net_pnl = if won, do: payout_base - bet_base, else: -bet_base
    {1, (if won, do: 1, else: 0), (if won, do: 0, else: 1), bet_base, winnings, losses, net_pnl}
  end

  # Convert to base units (lamports for SOL, smallest unit for BUX)
  defp to_base_units(nil, _vault_type), do: 0
  defp to_base_units(amount, :sol) when is_float(amount), do: trunc(amount * 1_000_000_000)
  defp to_base_units(amount, :sol) when is_integer(amount), do: amount * 1_000_000_000
  defp to_base_units(amount, :bux) when is_float(amount), do: trunc(amount * 1_000_000_000)
  defp to_base_units(amount, :bux) when is_integer(amount), do: amount * 1_000_000_000
  defp to_base_units(amount, _) when is_float(amount), do: trunc(amount * 1_000_000_000)
  defp to_base_units(amount, _) when is_integer(amount), do: amount * 1_000_000_000

  @doc """
  Get an existing unused game session for a user, or nil if none exists.
  Prevents creating duplicate commitments when user remounts the page.
  """
  def get_pending_game(user_id) do
    case :mnesia.dirty_index_read(:coin_flip_games, user_id, :user_id) do
      games when is_list(games) and length(games) > 0 ->
        pending_game = games
        |> Enum.filter(fn record ->
          status = elem(record, 7)
          status in [:pending, :committed]
        end)
        |> Enum.sort_by(fn record -> elem(record, 18) end, :desc)  # created_at
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
              commitment_sig: elem(record, 15),
              created_at: elem(record, 18)
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
  Get or create a game session.
  Calculates next nonce from Mnesia (like old BuxBoosterOnchain) — no on-chain state check.
  This is fast (<1ms) because it only reads local Mnesia, not Solana RPC.
  """
  def get_or_init_game(user_id, wallet_address) do
    # Calculate next nonce from Mnesia — same pattern as old BuxBoosterOnchain.
    mnesia_next = case :mnesia.dirty_match_object(
      {:coin_flip_games, :_, user_id, wallet_address, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}
    ) do
      [] -> 0
      games ->
        placed_games = Enum.filter(games, fn game -> elem(game, 7) in [:placed, :settled] end)
        case placed_games do
          [] -> 0
          _ ->
            placed_games
            |> Enum.map(fn game -> elem(game, 6) end)
            |> Enum.max()
            |> Kernel.+(1)
        end
    end

    # Reconciler A: Mnesia can drift below on-chain state if a frontend error
    # path fires between the user signing a bet tx and the LiveView recording
    # it as :placed. In that case Mnesia computes an already-used nonce,
    # `init` on the bet_order PDA fails with AccountAlreadyInUse, and the
    # user is stuck until Mnesia catches up. Take the max of Mnesia and
    # on-chain so we always move forward.
    onchain_next =
      case BlocksterV2.BuxMinter.get_player_state(wallet_address) do
        {:ok, %{"nonce" => n}} when is_integer(n) -> n
        _ -> 0
      end

    next_nonce = max(mnesia_next, onchain_next)

    if onchain_next > mnesia_next do
      Logger.warning(
        "[CoinFlipGame] Mnesia nonce (#{mnesia_next}) behind on-chain (#{onchain_next}) " <>
          "for wallet #{wallet_address} — using on-chain value. Likely a missed bet_confirmed event."
      )
    end

    # Reuse existing pending commitment if nonce matches
    case get_pending_game(user_id) do
      %{wallet_address: ^wallet_address, commitment_sig: sig, nonce: nonce} = existing
          when sig != nil and nonce == next_nonce ->
        Logger.info("[CoinFlipGame] Reusing existing game: #{existing.game_id}, nonce: #{existing.nonce}")
        {:ok, %{
          game_id: existing.game_id,
          commitment_hash: existing.commitment_hash,
          commitment_sig: existing.commitment_sig,
          nonce: existing.nonce
        }}

      _ ->
        Logger.info(
          "[CoinFlipGame] Creating new game with nonce #{next_nonce} " <>
            "(mnesia=#{mnesia_next}, onchain=#{onchain_next}) for user #{user_id}, wallet #{wallet_address}"
        )
        init_game_with_nonce(user_id, wallet_address, next_nonce)
    end
  end

  @doc """
  Look up a game record by its commitment_hash (hex string, lowercase, no prefix).

  Used during settlement to recover the correct server seed when the on-chain
  bet_order's commitment_hash drifts from the most-recently-initialised game
  for a given (player, nonce) — e.g. when two submit_commitment calls fire
  before the first place_bet lands and the on-chain player_state.pending_commitment
  gets overwritten (see docs/bug_audit_2026_04_22.md CF-01).

  Falls back to dirty_match_object if the :commitment_hash index is unavailable
  (e.g. in old test environments that create the table without the index).
  Returns {:ok, game_map} or {:error, :not_found}.
  """
  def get_game_by_commitment_hash(commitment_hash) when is_binary(commitment_hash) do
    records =
      try do
        :mnesia.dirty_index_read(:coin_flip_games, commitment_hash, :commitment_hash)
      catch
        :exit, _ ->
          :mnesia.dirty_match_object(
            {:coin_flip_games, :_, :_, :_, :_, commitment_hash,
             :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}
          )
      end

    case records do
      [record | _] -> {:ok, record_to_game(record)}
      _ -> {:error, :not_found}
    end
  rescue
    _ -> {:error, :not_found}
  end

  def get_game_by_commitment_hash(_), do: {:error, :not_found}

  defp record_to_game(
         {:coin_flip_games, game_id, user_id, wallet_address, server_seed, commitment_hash, nonce,
          status, vault_type, bet_amount, difficulty, predictions, results, won, payout,
          commitment_sig, bet_sig, settlement_sig, created_at, settled_at}
       ) do
    %{
      game_id: game_id,
      user_id: user_id,
      wallet_address: wallet_address,
      server_seed: server_seed,
      commitment_hash: commitment_hash,
      nonce: nonce,
      status: status,
      vault_type: vault_type,
      bet_amount: bet_amount,
      difficulty: difficulty,
      predictions: predictions,
      results: results,
      won: won,
      payout: payout,
      commitment_sig: commitment_sig,
      bet_sig: bet_sig,
      settlement_sig: settlement_sig,
      created_at: created_at,
      settled_at: settled_at
    }
  end

  @doc """
  Get game details from Mnesia.
  """
  def get_game(game_id) do
    case :mnesia.dirty_read({:coin_flip_games, game_id}) do
      [record] -> {:ok, record_to_game(record)}
      [] -> {:error, :not_found}
    end
  end

  # ============ Settler API Calls ============

  defp submit_commitment(commitment_hash, player, nonce) do
    body = Jason.encode!(%{
      "commitmentHash" => commitment_hash,
      "player" => player,
      "nonce" => nonce
    })

    headers = [
      {"Content-Type", "application/json"},
      {"Authorization", "Bearer #{get_api_secret()}"}
    ]

    url = "#{settler_url()}/submit-commitment"

    case http_post(url, body, headers) do
      {:ok, %{status_code: 200, body: resp_body}} ->
        case Jason.decode(resp_body) do
          {:ok, %{"success" => true, "signature" => sig}} ->
            {:ok, sig}

          # Also handle txHash format from settler stub
          {:ok, %{"success" => true, "txHash" => tx_hash}} ->
            {:ok, tx_hash}

          {:ok, %{"error" => error}} ->
            {:error, error}

          {:error, _} ->
            {:error, "Invalid response"}
        end

      {:ok, %{status_code: code, body: body}} ->
        {:error, "HTTP #{code}: #{body}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp settle_bet(player, nonce, server_seed, won, payout, vault_type) do
    body = Jason.encode!(%{
      "player" => player,
      "nonce" => nonce,
      "serverSeed" => server_seed,
      "won" => won,
      "payout" => payout,
      "vaultType" => Atom.to_string(vault_type || :bux)
    })

    headers = [
      {"Content-Type", "application/json"},
      {"Authorization", "Bearer #{get_api_secret()}"}
    ]

    url = "#{settler_url()}/settle-bet"

    # Settlement needs longer timeout — sendSettlerTx retries up to 3x with blockhash refresh
    case http_post(url, body, headers, receive_timeout: 60_000) do
      {:ok, %{status_code: 200, body: resp_body}} ->
        case Jason.decode(resp_body) do
          {:ok, %{"success" => true, "signature" => sig}} ->
            {:ok, sig}

          # Also handle txHash format from settler stub
          {:ok, %{"success" => true}} ->
            {:ok, "settled"}

          {:ok, %{"error" => error}} ->
            {:error, error}

          {:error, _} ->
            {:error, "Invalid response"}
        end

      # Settler's structured 409 for SHA256(seed) ≠ bet_order.commitment_hash.
      # Carries both hashes so callers can attempt recovery via Mnesia lookup
      # keyed on the on-chain commitment — or route the bet to manual_review
      # if no matching seed exists locally.
      {:ok, %{status_code: 409, body: resp_body}} ->
        case Jason.decode(resp_body) do
          {:ok, %{"error" => "commitment_mismatch"} = payload} ->
            {:error,
             {:commitment_mismatch, Map.get(payload, "onchain_commitment_hash"),
              Map.get(payload, "computed_commitment_hash")}}

          _ ->
            {:error, "HTTP 409: #{resp_body}"}
        end

      {:ok, %{status_code: code, body: body}} ->
        {:error, "HTTP #{code}: #{body}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp http_post(url, body, headers, opts \\ []) do
    timeout = Keyword.get(opts, :receive_timeout, 30_000)
    case Code.ensure_loaded(Req) do
      {:module, Req} ->
        case Req.post(url, body: body, headers: headers, receive_timeout: timeout) do
          {:ok, %Req.Response{status: status, body: response_body}} ->
            body_string = if is_binary(response_body), do: response_body, else: Jason.encode!(response_body)
            {:ok, %{status_code: status, body: body_string}}
          {:error, reason} ->
            {:error, reason}
        end

      _ ->
        :inets.start()
        :ssl.start()
        url_charlist = String.to_charlist(url)
        body_charlist = String.to_charlist(body)
        headers_charlist = Enum.map(headers, fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)
        http_options = [{:timeout, 15_000}, {:connect_timeout, 5_000}]
        case :httpc.request(:post, {url_charlist, headers_charlist, ~c"application/json", body_charlist}, http_options, []) do
          {:ok, {{_, status, _}, _, response_body}} ->
            {:ok, %{status_code: status, body: to_string(response_body)}}
          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  # ============ Helper Functions ============

  defp generate_game_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  defp generate_client_seed_from_bet(user_id, bet_amount, vault_type, difficulty, predictions) do
    predictions_str = predictions
    |> Enum.map(&Atom.to_string/1)
    |> Enum.join(",")

    token_str = if is_atom(vault_type), do: Atom.to_string(vault_type), else: to_string(vault_type)
    input = "#{user_id}:#{bet_amount}:#{token_str}:#{difficulty}:#{predictions_str}"
    :crypto.hash(:sha256, input)
  end

  defp generate_flip_results(combined_seed, num_flips) do
    for i <- 0..(num_flips - 1) do
      byte = :binary.at(combined_seed, i)
      if byte < 128, do: :heads, else: :tails
    end
  end

  defp get_flip_count(difficulty) do
    case difficulty do
      -4 -> 5
      -3 -> 4
      -2 -> 3
      -1 -> 2
      1 -> 1
      2 -> 2
      3 -> 3
      4 -> 4
      5 -> 5
    end
  end

  defp check_win(predictions, results, difficulty) when difficulty < 0 do
    # Win One mode: any match wins
    Enum.zip(predictions, results)
    |> Enum.any?(fn {pred, result} ->
      normalize_prediction(pred) == normalize_prediction(result)
    end)
  end

  defp check_win(predictions, results, _difficulty) do
    # Win All mode: all must match
    Enum.zip(predictions, results)
    |> Enum.all?(fn {pred, result} ->
      normalize_prediction(pred) == normalize_prediction(result)
    end)
  end

  defp normalize_prediction(pred) when pred in [:heads, 0, "heads"], do: :heads
  defp normalize_prediction(pred) when pred in [:tails, 1, "tails"], do: :tails
  defp normalize_prediction(pred), do: pred

  defp calculate_payout(bet_amount, difficulty) do
    multiplier = Map.get(@multipliers, difficulty, 10000)
    # Must floor (not round) to match on-chain integer truncation in calculate_max_payout.
    # Rust: max_payout = (raw_amount * multiplier_bps) / 10_000 (integer division truncates).
    # If we round up here, payout can exceed max_payout by 1 lamport → PayoutExceedsMax.
    raw = bet_amount * multiplier / 10000
    decimals = if bet_amount < 1.0, do: 9, else: 6
    trunc(raw * :math.pow(10, decimals)) / :math.pow(10, decimals)
  end

  @doc """
  Get recent settled/placed games for a vault type (for pool activity feed).
  Returns up to `limit` games sorted by created_at descending.
  """
  def get_recent_games_by_vault(vault_type, limit \\ 50) when vault_type in [:sol, :bux] do
    # Match all games with the given vault_type (position 8)
    :mnesia.dirty_match_object(
      {:coin_flip_games, :_, :_, :_, :_, :_, :_, :_, vault_type, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}
    )
    |> Enum.filter(fn record ->
      status = elem(record, 7)
      status in [:placed, :settled]
    end)
    |> Enum.sort_by(fn record -> elem(record, 18) end, :desc)
    |> Enum.take(limit)
    |> Enum.map(fn record ->
      %{
        type: if(elem(record, 13), do: "win", else: "loss"),
        game: "Coin Flip",
        game_id: elem(record, 1),
        bet_amount: elem(record, 9),
        payout: elem(record, 14),
        wallet: elem(record, 3),
        vault_type: Atom.to_string(elem(record, 8)),
        difficulty: elem(record, 10),
        predictions: elem(record, 11),
        results: elem(record, 12),
        commitment_sig: elem(record, 15),
        bet_sig: elem(record, 16),
        settlement_sig: elem(record, 17),
        status: elem(record, 7),
        created_at: elem(record, 18)
      }
    end)
  rescue
    _ -> []
  catch
    :exit, _ -> []
  end

  @doc """
  Compute period stats for a vault type, optionally filtered by seconds_back.
  Pass nil for all-time. Returns %{total: n, wins: n, volume: f, payout: f, profit: f}.
  """
  def period_stats(vault_type, seconds_back \\ nil) when vault_type in [:sol, :bux] do
    cutoff = if seconds_back, do: System.system_time(:second) - seconds_back, else: 0

    games =
      :mnesia.dirty_match_object(
        {:coin_flip_games, :_, :_, :_, :_, :_, :_, :settled, vault_type, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}
      )
      |> Enum.filter(fn record -> elem(record, 19) >= cutoff end)

    total = length(games)
    wins = Enum.count(games, fn record -> elem(record, 13) == true end)

    volume = Enum.reduce(games, 0.0, fn record, acc ->
      bet = elem(record, 9)
      if is_number(bet), do: acc + bet, else: acc
    end)

    payout = Enum.reduce(games, 0.0, fn record, acc ->
      p = elem(record, 14)
      if is_number(p), do: acc + p, else: acc
    end)

    %{total: total, wins: wins, volume: volume, payout: payout, profit: volume - payout}
  rescue
    _ -> %{total: 0, wins: 0, volume: 0.0, payout: 0.0, profit: 0.0}
  catch
    :exit, _ -> %{total: 0, wins: 0, volume: 0.0, payout: 0.0, profit: 0.0}
  end

  # Public accessors
  def multipliers, do: @multipliers

  @doc "Maximum possible payout for a bet (used for on-chain max_payout field)."
  def max_payout(bet_amount, difficulty), do: calculate_payout(bet_amount, difficulty)
end
