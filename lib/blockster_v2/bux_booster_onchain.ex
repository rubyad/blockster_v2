# lib/blockster_v2/bux_booster_onchain.ex
defmodule BlocksterV2.BuxBoosterOnchain do
  @moduledoc """
  On-chain BUX Booster game orchestration.

  Blockster is the orchestrator:
  - Generates server seeds
  - Stores seeds in Mnesia (:bux_booster_onchain_games table)
  - Calls BUX Minter to submit/settle transactions
  - Controls game flow and timing

  BUX Minter is a stateless transaction relay.

  ## Mnesia Table: :bux_booster_onchain_games
  Primary key: game_id (32-char hex string)
  """

  alias BlocksterV2.EngagementTracker
  require Logger

  @contract_address "0x97b6d6A8f2c6AF6e6fb40f8d36d60DF2fFE4f17B"

  defp bux_minter_url do
    Application.get_env(:blockster_v2, :bux_minter_url) || "https://bux-minter.fly.dev"
  end

  # Token contract addresses
  @token_addresses %{
    "BUX" => "0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8",
    "moonBUX" => "0x08F12025c1cFC4813F21c2325b124F6B6b5cfDF5",
    "neoBUX" => "0x423656448374003C2cfEaFF88D5F64fb3A76487C",
    "rogueBUX" => "0x56d271b1C1DCF597aA3ee454bCCb265d4Dee47b3",
    "flareBUX" => "0xd27EcA9bc2401E8CEf92a14F5Ee9847508EDdaC8",
    "nftBUX" => "0x9853e3Abea96985d55E9c6963afbAf1B0C9e49ED",
    "nolchaBUX" => "0x4cE5C87FAbE273B58cb4Ef913aDEa5eE15AFb642",
    "solBUX" => "0x92434779E281468611237d18AdE20A4f7F29DB38",
    "spaceBUX" => "0xAcaCa77FbC674728088f41f6d978F0194cf3d55A",
    "tronBUX" => "0x98eDb381281FA02b494FEd76f0D9F3AEFb2Db665",
    "tranBUX" => "0xcDdE88C8bacB37Fc669fa6DECE92E3d8FE672d96"
  }

  # Multipliers in basis points (10000 = 1x) - matches smart contract
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

  @doc """
  Initialize a new game session with explicit nonce.
  Generates server seed, stores in Mnesia, submits commitment to chain.

  Returns {:ok, %{game_id, commitment_hash, commitment_tx, nonce}} or {:error, reason}
  """
  def init_game_with_nonce(user_id, wallet_address, nonce) do

    # 2. Generate server seed (32 bytes as hex string without 0x prefix)
    server_seed = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)

    # 3. Calculate commitment hash (sha256 of the hex string for player verification)
    # This matches ProvablyFair.generate_commitment - hashes the string, not bytes
    commitment_hash_bytes = :crypto.hash(:sha256, server_seed)
    commitment_hash = "0x" <> Base.encode16(commitment_hash_bytes, case: :lower)

    # 4. Generate game ID (primary key)
    game_id = generate_game_id()
    now = System.system_time(:second)

    # 5. Submit commitment to contract (server controls the nonce)
    case submit_commitment(commitment_hash, wallet_address, nonce) do
      {:ok, tx_hash} ->
        Logger.info("[BuxBoosterOnchain] Commitment submitted - TX: #{tx_hash}, Player: #{wallet_address}, Nonce: #{nonce}")
        # Success! Write to Mnesia
        game_record = {
          :bux_booster_onchain_games,
          game_id,                    # PRIMARY KEY
          user_id,
          wallet_address,
          server_seed,
          commitment_hash,
          nonce,
          :committed,                 # status - already committed on-chain
          nil,                        # bet_id (set after placeBet)
          nil,                        # token
          nil,                        # token_address
          nil,                        # bet_amount
          nil,                        # difficulty
          nil,                        # predictions
          nil,                        # results
          nil,                        # won
          nil,                        # payout
          tx_hash,                    # commitment_tx - confirmed
          nil,                        # bet_tx
          nil,                        # settlement_tx
          now,                        # created_at
          nil                         # settled_at
        }
        :mnesia.dirty_write(game_record)

        Logger.info("[BuxBoosterOnchain] Commitment submitted: #{tx_hash} for player #{wallet_address}, nonce #{nonce}")
        {:ok, %{
          game_id: game_id,
          commitment_hash: commitment_hash,
          commitment_tx: tx_hash,
          nonce: nonce
        }}

      {:error, reason} ->
        Logger.error("[BuxBoosterOnchain] Failed to submit commitment: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Calculate game result BEFORE placing bet on-chain (for optimistic UI).
  Uses server seed already stored in Mnesia to generate results immediately.

  Returns {:ok, result} where result contains flip results, won status, and payout.
  """
  def calculate_game_result(game_id, predictions, bet_amount, token, difficulty) do
    case get_game(game_id) do
      {:ok, game} ->
        calculate_result(
          game.server_seed,
          game.nonce,
          predictions,
          bet_amount,
          token,
          difficulty,
          game.user_id
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Called when player's bet is placed on-chain.
  Updates the game record with bet details and calculates the result.

  Returns {:ok, result} where result contains flip results, won status, and payout.
  """
  def on_bet_placed(game_id, bet_id, bet_tx, predictions, bet_amount, token, difficulty) do
    case get_game(game_id) do
      {:ok, game} ->
        token_address = Map.get(@token_addresses, token, token)

        # Calculate result locally (we have the server seed)
        {:ok, result} = calculate_result(
          game.server_seed, game.nonce, predictions, bet_amount, token,
          difficulty, game.user_id
        )

        # Update created_at to NOW when bet is actually placed
        # This is important for the BetSettler which uses created_at to determine if a bet is stuck
        # Without this, reused game sessions from days ago would appear as "stuck" immediately
        now = System.system_time(:second)

        # Update game record with bet details and calculated results
        updated_record = {
          :bux_booster_onchain_games,
          game_id,
          game.user_id,
          game.wallet_address,
          game.server_seed,
          game.commitment_hash,
          game.nonce,
          :placed,                    # status
          bet_id,                     # bet_id
          token,                      # token
          token_address,              # token_address
          bet_amount,                 # bet_amount
          difficulty,                 # difficulty
          predictions,                # predictions
          result.results,             # results
          result.won,                 # won
          result.payout,              # payout
          game.commitment_tx,         # commitment_tx
          bet_tx,                     # bet_tx
          nil,                        # settlement_tx
          now,                        # created_at - updated to when bet is placed, not when game was created
          nil                         # settled_at
        }
        :mnesia.dirty_write(updated_record)

        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Calculate game result from server seed and bet details.
  This is called after bet is placed but before settlement.
  """
  def calculate_result(server_seed, nonce, predictions, bet_amount, token, difficulty, user_id) do
    # Generate client seed from bet details (deterministic from player choices only)
    client_seed_binary = generate_client_seed_from_bet(user_id, bet_amount, token, difficulty, predictions)
    client_seed_hex = Base.encode16(client_seed_binary, case: :lower)

    # Combined seed (matching ProvablyFair: SHA256(server_hex:client_hex:nonce))
    # All hex strings concatenated with colons
    combined_input = "#{server_seed}:#{client_seed_hex}:#{nonce}"
    combined_seed = :crypto.hash(:sha256, combined_input)

    # Generate flip results
    num_flips = get_flip_count(difficulty)
    results = generate_flip_results(combined_seed, num_flips)

    # Determine win/loss based on game mode
    won = check_win(predictions, results, difficulty)

    require Logger
    Logger.info("[BuxBooster] Win check - predictions: #{inspect(predictions)}, results: #{inspect(results)}, difficulty: #{difficulty}, won: #{won}")

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
  Settle the bet on-chain after animation completes.
  Calls BUX Minter to submit settleBet transaction with results.

  Returns {:ok, %{tx_hash, player_balance}} or {:error, reason}
  """
  def settle_game(game_id) do
    case get_game(game_id) do
      {:ok, game} when game.status == :settled ->
        # Already settled - return existing settlement info
        Logger.debug("[BuxBoosterOnchain] Game #{game_id} already settled, skipping")
        {:ok, %{tx_hash: game.settlement_tx, player_balance: nil, already_settled: true}}

      {:ok, game} when game.bet_id != nil ->
        # Add 0x prefix to server seed for the contract
        server_seed_hex = "0x" <> game.server_seed

        # V3: Send commitment_hash (which is the betId), results, and won status
        case settle_bet(game.commitment_hash, server_seed_hex, game.results, game.won) do
          {:ok, tx_hash, player_balance} ->
            # Update Mnesia record to settled
            mark_game_settled(game_id, game, tx_hash)
            Logger.info("[BuxBoosterOnchain] Game #{game_id} settled: #{tx_hash}")
            {:ok, %{tx_hash: tx_hash, player_balance: player_balance}}

          {:error, reason} ->
            # Check if it's a BetAlreadySettled error (0x05d09e5f)
            if is_bet_already_settled_error?(reason) do
              Logger.info("[BuxBoosterOnchain] Game #{game_id} was already settled on-chain, marking as settled")
              mark_game_settled(game_id, game, "already_settled_on_chain")
              {:ok, %{tx_hash: "already_settled_on_chain", player_balance: nil, already_settled: true}}
            else
              Logger.error("[BuxBoosterOnchain] Failed to settle game #{game_id}: #{inspect(reason)}")
              {:error, reason}
            end
        end

      {:ok, _game} ->
        {:error, :bet_not_placed}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Check if the error is BetAlreadySettled (error selector 0x05d09e5f)
  defp is_bet_already_settled_error?(reason) when is_binary(reason) do
    String.contains?(reason, "0x05d09e5f")
  end
  defp is_bet_already_settled_error?(_), do: false

  # Mark a game as settled in Mnesia
  defp mark_game_settled(game_id, game, tx_hash) do
    now = System.system_time(:second)
    updated_record = {
      :bux_booster_onchain_games,
      game_id,
      game.user_id,
      game.wallet_address,
      game.server_seed,
      game.commitment_hash,
      game.nonce,
      :settled,                   # status
      game.bet_id,
      game.token,
      game.token_address,
      game.bet_amount,
      game.difficulty,
      game.predictions,
      game.results,
      game.won,
      game.payout,
      game.commitment_tx,
      game.bet_tx,
      tx_hash,                    # settlement_tx
      game.created_at,
      now                         # settled_at
    }
    :mnesia.dirty_write(updated_record)
  end

  @doc """
  Sync player's on-chain balance to Mnesia.
  """
  def sync_balance(user_id, token, wallet_address) do
    token_address = Map.get(@token_addresses, token)

    case get_token_balance(token_address, wallet_address) do
      {:ok, balance_wei} ->
        # Convert from wei to integer tokens
        balance = div(balance_wei, 1_000_000_000_000_000_000)
        EngagementTracker.update_user_token_balance(user_id, wallet_address, token, balance)
        {:ok, balance}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get an existing unused game session for a user, or nil if none exists.
  This prevents creating duplicate commitments when user remounts the page.
  """
  def get_pending_game(user_id) do
    case :mnesia.dirty_index_read(:bux_booster_onchain_games, user_id, :user_id) do
      games when is_list(games) and length(games) > 0 ->
        # Find the most recent game with :pending or :committed status (unused commitment)
        pending_game = games
        |> Enum.filter(fn record ->
          status = elem(record, 7)
          status in [:pending, :committed]
        end)
        |> Enum.sort_by(fn record -> elem(record, 20) end, :desc)  # created_at
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
              commitment_tx: elem(record, 17),
              created_at: elem(record, 20)
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
  Calculates next nonce from Mnesia by finding the highest nonce from placed bets.
  Never queries the contract - Mnesia is the source of truth for nonces.
  """
  def get_or_init_game(user_id, wallet_address) do
    # Calculate next nonce from Mnesia based on placed bets (status :placed or :settled)
    next_nonce = case :mnesia.dirty_match_object({:bux_booster_onchain_games, :_, user_id, wallet_address, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}) do
      [] ->
        # No games yet, start with nonce 0
        0
      games ->
        # Find highest nonce from all PLACED/SETTLED games (not just committed)
        # This ensures we don't reuse nonces from abandoned commitments
        placed_games = Enum.filter(games, fn game -> elem(game, 7) in [:placed, :settled] end)

        case placed_games do
          [] ->
            # No placed bets yet, start with 0
            0
          _ ->
            # Get max nonce from placed bets and increment
            placed_games
            |> Enum.map(fn game -> elem(game, 6) end)  # nonce is at position 6
            |> Enum.max()
            |> Kernel.+(1)
        end
    end

    # Check if we already have a pending commitment with this nonce
    case get_pending_game(user_id) do
      %{wallet_address: ^wallet_address, commitment_tx: tx, nonce: nonce} = existing
          when tx != nil and nonce == next_nonce ->
        # Reuse existing committed game with correct nonce
        Logger.info("[BuxBoosterOnchain] Reusing existing game: #{existing.game_id}, nonce: #{existing.nonce}")
        {:ok, %{
          game_id: existing.game_id,
          commitment_hash: existing.commitment_hash,
          commitment_tx: existing.commitment_tx,
          nonce: existing.nonce
        }}

      _ ->
        # Create new game with calculated nonce
        Logger.info("[BuxBoosterOnchain] Creating new game with nonce #{next_nonce} (from Mnesia)")
        init_game_with_nonce(user_id, wallet_address, next_nonce)
    end
  end

  @doc """
  Get game details from Mnesia.
  Table: :bux_booster_onchain_games
  """
  def get_game(game_id) do
    case :mnesia.dirty_read({:bux_booster_onchain_games, game_id}) do
      [{:bux_booster_onchain_games, ^game_id, user_id, wallet_address, server_seed, commitment_hash,
        nonce, status, bet_id, token, token_address, bet_amount, difficulty, predictions, results,
        won, payout, commitment_tx, bet_tx, settlement_tx, created_at, settled_at}] ->
        {:ok, %{
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
          difficulty: difficulty,
          predictions: predictions,
          results: results,
          won: won,
          payout: payout,
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

  # ============ BUX Minter API Calls ============

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

    url = "#{bux_minter_url()}/submit-commitment"

    case http_post(url, body, headers) do
      {:ok, %{status_code: 200, body: resp_body}} ->
        case Jason.decode(resp_body) do
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

  defp settle_bet(commitment_hash, server_seed, results, won) do
    # Convert results from atoms to integers (0 for heads, 1 for tails)
    results_int = Enum.map(results, fn
      :heads -> 0
      0 -> 0
      :tails -> 1
      1 -> 1
      _ -> 0
    end)

    body = Jason.encode!(%{
      "commitmentHash" => commitment_hash,
      "serverSeed" => server_seed,
      "results" => results_int,
      "won" => won
    })

    headers = [
      {"Content-Type", "application/json"},
      {"Authorization", "Bearer #{get_api_secret()}"}
    ]

    url = "#{bux_minter_url()}/settle-bet"

    case http_post(url, body, headers) do
      {:ok, %{status_code: 200, body: resp_body}} ->
        case Jason.decode(resp_body) do
          {:ok, %{"success" => true, "txHash" => tx_hash, "payout" => payout}} ->
            {:ok, tx_hash, parse_balance(payout)}

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

  defp get_token_balance(token_address, wallet_address) do
    headers = [{"Authorization", "Bearer #{get_api_secret()}"}]
    url = "#{bux_minter_url()}/balance/#{wallet_address}?token=#{find_token_name(token_address)}"

    case http_get(url, headers) do
      {:ok, %{status_code: 200, body: resp_body}} ->
        case Jason.decode(resp_body) do
          {:ok, %{"balanceWei" => balance_wei}} ->
            {:ok, parse_balance(balance_wei)}

          {:ok, %{"balance" => balance}} ->
            # Convert formatted balance to wei
            {:ok, trunc(parse_balance(balance) * 1_000_000_000_000_000_000)}

          {:error, _} ->
            {:error, "Invalid response"}
        end

      {:ok, %{status_code: code, body: body}} ->
        {:error, "HTTP #{code}: #{body}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp find_token_name(token_address) do
    Enum.find_value(@token_addresses, "BUX", fn {name, addr} ->
      if String.downcase(addr) == String.downcase(token_address), do: name
    end)
  end

  defp get_api_secret do
    Application.get_env(:blockster_v2, :bux_minter_secret) ||
      System.get_env("BUX_MINTER_SECRET")
  end

  defp http_post(url, body, headers) do
    case Code.ensure_loaded(Req) do
      {:module, Req} ->
        case Req.post(url, body: body, headers: headers, receive_timeout: 60_000,
                      connect_options: [transport_opts: [inet_backend: :inet]]) do
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
        case :httpc.request(:post, {url_charlist, headers_charlist, ~c"application/json", body_charlist}, [], []) do
          {:ok, {{_, status, _}, _, response_body}} ->
            {:ok, %{status_code: status, body: to_string(response_body)}}
          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp http_get(url, headers) do
    case Code.ensure_loaded(Req) do
      {:module, Req} ->
        case Req.get(url, headers: headers, receive_timeout: 30_000,
                     connect_options: [transport_opts: [inet_backend: :inet]]) do
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
        headers_charlist = Enum.map(headers, fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)
        case :httpc.request(:get, {url_charlist, headers_charlist}, [], []) do
          {:ok, {{_, status, _}, _, response_body}} ->
            {:ok, %{status_code: status, body: to_string(response_body)}}
          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  # ============ Helper Functions ============

  # Get player's nonce from Mnesia.
  # Reads the nonce from the last successfully committed game (has commitment_tx set).
  # For a new game, nonce = last_committed_nonce + 1.
  defp get_player_nonce(wallet_address) do
    case :mnesia.dirty_index_read(:bux_booster_onchain_games, wallet_address, :wallet_address) do
      games when is_list(games) and length(games) > 0 ->
        # Find the most recent SETTLED game (not just committed)
        # Only count games that were actually bet on (status :placed or :settled)
        # Uncommitted games shouldn't increment the nonce counter
        last_settled = games
          |> Enum.filter(fn record ->
            # status is at position 7
            status = elem(record, 7)
            status in [:placed, :settled]
          end)
          |> Enum.sort_by(fn record -> elem(record, 20) end, :desc)  # Sort by created_at descending
          |> List.first()

        case last_settled do
          nil ->
            # No settled games yet
            0
          record ->
            # nonce is at position 6, next nonce is +1
            elem(record, 6) + 1
        end

      _ ->
        # No games for this wallet
        0
    end
  rescue
    _ -> 0
  catch
    :exit, _ -> 0
  end

  defp generate_game_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  defp generate_client_seed_from_bet(user_id, bet_amount, token, difficulty, predictions) do
    # Deterministic client seed from player-controlled values only (matches ProvablyFair module)
    predictions_str = predictions
    |> Enum.map(&Atom.to_string/1)
    |> Enum.join(",")

    input = "#{user_id}:#{bet_amount}:#{token}:#{difficulty}:#{predictions_str}"
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
    Float.round(bet_amount * multiplier / 10000, 2)
  end

  defp parse_balance(balance) when is_binary(balance) do
    case Integer.parse(balance) do
      {int, _} -> int
      :error -> 0
    end
  end
  defp parse_balance(balance) when is_integer(balance), do: balance
  defp parse_balance(_), do: 0

  # Public accessors
  def contract_address, do: @contract_address
  def token_address(token), do: Map.get(@token_addresses, token)
  def token_addresses, do: @token_addresses
  def multipliers, do: @multipliers
end
