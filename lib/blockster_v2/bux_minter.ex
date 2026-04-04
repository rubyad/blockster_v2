defmodule BlocksterV2.BuxMinter do
  @moduledoc """
  Client module for calling the BUX minting service.
  Calls the Solana settler service (blockster-settler) to mint SPL BUX tokens.

  Solana migration: This module now targets the settler service at BLOCKSTER_SETTLER_URL
  instead of the EVM bux-minter. The settler mints SPL BUX on Solana devnet/mainnet.
  """

  alias BlocksterV2.EngagementTracker
  require Logger

  # ETS table for deduplicating concurrent sync_user_balances_async calls
  @sync_dedup_table :bux_minter_sync_dedup
  # Minimum interval between syncs for the same user (in milliseconds)
  @sync_cooldown_ms 5_000

  @doc """
  Initializes the ETS table for sync deduplication.
  Called from Application supervision tree.
  """
  def init_dedup_table do
    if :ets.whereis(@sync_dedup_table) == :undefined do
      :ets.new(@sync_dedup_table, [:set, :public, :named_table, read_concurrency: true, write_concurrency: true])
    end

    :ok
  end

  @doc """
  Mints BUX SPL tokens to a user's Solana wallet.

  ## Parameters
    - wallet_address: The user's Solana wallet address (base58 pubkey)
    - amount: Number of tokens to mint
    - user_id: The user's ID (for logging)
    - post_id: The post ID that earned the reward (for logging, can be nil)
    - reward_type: The type of reward

  ## Returns
    - {:ok, response} on success with transaction signature
    - {:error, reason} on failure
  """
  def mint_bux(wallet_address, amount, user_id, post_id, reward_type, _token \\ "BUX", _hub_id \\ nil)
      when reward_type in [:read, :x_share, :video_watch, :signup, :phone_verified, :shop_affiliate, :shop_refund, :ai_bonus] do
    settler_url = get_settler_url()
    api_secret = get_api_secret()

    if is_nil(api_secret) or api_secret == "" do
      Logger.warning("[BuxMinter] API_SECRET not configured, skipping mint")
      {:error, :not_configured}
    else
      payload = %{
        wallet: wallet_address,
        amount: amount,
        userId: user_id,
        rewardType: Atom.to_string(reward_type)
      }

      headers = [
        {"Content-Type", "application/json"},
        {"Authorization", "Bearer #{api_secret}"}
      ]

      case http_post("#{settler_url}/mint", Jason.encode!(payload), headers) do
        {:ok, %{status_code: 200, body: body}} ->
          response = Jason.decode!(body)
          signature = response["signature"]

          # Mark the read reward as paid in Mnesia (only for read rewards)
          if reward_type == :read do
            EngagementTracker.mark_read_reward_paid(user_id, post_id, signature)
          end

          # Track gas spend for authority wallet monitoring
          ata_created = response["ataCreated"] || false
          BlocksterV2.AuthorityGasTracker.record_mint(ata_created)

          # Sync Solana balances after mint
          sync_user_balances_async(user_id, wallet_address, force: true)

          {:ok, response}

        {:ok, %{status_code: status, body: body}} ->
          error = safe_decode(body)
          Logger.error("[BuxMinter] Mint failed (#{status}): #{inspect(error)}")
          {:error, error["error"] || "Unknown error"}

        {:error, reason} ->
          Logger.error("[BuxMinter] HTTP request failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @doc """
  Burns (transfers to treasury) BUX tokens for shop checkout.
  Calls the /burn endpoint on the settler service.
  """
  def burn_bux(wallet_address, amount, user_id) do
    settler_url = get_settler_url()
    api_secret = get_api_secret()

    if is_nil(api_secret) or api_secret == "" do
      Logger.warning("[BuxMinter] API_SECRET not configured, skipping burn")
      {:error, :not_configured}
    else
      payload = %{
        wallet: wallet_address,
        amount: amount,
        userId: user_id
      }

      headers = [
        {"Content-Type", "application/json"},
        {"Authorization", "Bearer #{api_secret}"}
      ]

      case http_post("#{settler_url}/burn", Jason.encode!(payload), headers) do
        {:ok, %{status_code: 200, body: body}} ->
          response = Jason.decode!(body)

          if wallet_address do
            sync_user_balances_async(user_id, wallet_address, force: true)
          end

          {:ok, response}

        {:ok, %{status_code: status, body: body}} ->
          error = safe_decode(body)
          Logger.error("[BuxMinter] Burn failed (#{status}): #{inspect(error)}")
          {:error, error["error"] || "Burn failed"}

        {:error, reason} ->
          Logger.error("[BuxMinter] Burn HTTP request failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @doc """
  Mints BUX tokens asynchronously (fire and forget).
  Use this when you don't need to wait for the transaction to complete.
  """
  def mint_bux_async(wallet_address, amount, user_id, post_id, reward_type, _token \\ "BUX")
      when reward_type in [:read, :x_share, :video_watch] do
    Task.start(fn ->
      mint_bux(wallet_address, amount, user_id, post_id, reward_type)
    end)
  end

  @doc """
  Gets SOL and BUX balances for a Solana wallet.

  ## Returns
    - {:ok, %{sol: float, bux: float}} on success
    - {:error, reason} on failure
  """
  def get_balance(wallet_address) do
    settler_url = get_settler_url()
    api_secret = get_api_secret()

    if is_nil(api_secret) or api_secret == "" do
      {:error, :not_configured}
    else
      headers = [{"Authorization", "Bearer #{api_secret}"}]
      url = "#{settler_url}/balance/#{wallet_address}"

      case http_get(url, headers) do
        {:ok, %{status_code: 200, body: body}} ->
          response = Jason.decode!(body)
          {:ok, %{sol: response["sol"] || 0.0, bux: response["bux"] || 0.0}}

        {:ok, %{status_code: _status, body: body}} ->
          error = safe_decode(body)
          {:error, error["error"] || "Unknown error"}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Legacy get_balance/2 for backward compatibility.
  Ignores the token parameter and returns BUX balance as a float.
  """
  def get_balance(wallet_address, _token) do
    case get_balance(wallet_address) do
      {:ok, %{bux: bux}} -> {:ok, bux}
      error -> error
    end
  end

  @doc """
  Fetches SOL + BUX balances and updates the user_solana_balances Mnesia table.
  Call this on page load to sync on-chain balances with local cache.
  """
  def sync_user_balances(user_id, wallet_address) do
    case get_balance(wallet_address) do
      {:ok, %{sol: sol, bux: bux}} ->
        # Update Solana balances in new Mnesia table
        EngagementTracker.update_user_solana_bux_balance(user_id, wallet_address, bux)
        EngagementTracker.update_user_sol_balance(user_id, wallet_address, sol)

        # Update SOL multiplier after balance sync
        BlocksterV2.UnifiedMultiplier.update_sol_multiplier(user_id)

        # Update legacy BUX balance tables for backward compatibility
        EngagementTracker.update_user_bux_balance(user_id, wallet_address, bux)
        EngagementTracker.update_user_token_balance(user_id, wallet_address, "BUX", bux, broadcast: false)

        # Broadcast balance update to all LiveViews
        BlocksterV2Web.BuxBalanceHook.broadcast_balance_update(user_id, bux)
        BlocksterV2Web.BuxBalanceHook.broadcast_token_balances_update(user_id, %{"BUX" => bux, "SOL" => sol})

        {:ok, %{balances: %{"BUX" => bux, "SOL" => sol}}}

      {:error, reason} ->
        Logger.warning("[BuxMinter] Failed to sync balances for user #{user_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Syncs user balances asynchronously (fire and forget).
  Deduplicates concurrent calls for the same user.

  Options:
    - force: true - bypass deduplication (use after settlement/minting when balance MUST refresh)
  """
  def sync_user_balances_async(user_id, wallet_address, opts \\ []) do
    force = Keyword.get(opts, :force, false)

    if force do
      if :ets.whereis(@sync_dedup_table) != :undefined do
        :ets.delete(@sync_dedup_table, user_id)
      end
    end

    now = System.monotonic_time(:millisecond)

    case claim_sync_slot(user_id, now) do
      :ok ->
        Task.start(fn ->
          try do
            sync_user_balances(user_id, wallet_address)
          after
            :ets.insert(@sync_dedup_table, {user_id, :done, System.monotonic_time(:millisecond)})
          end
        end)

      :skip ->
        Logger.debug("[BuxMinter] Skipping duplicate sync for user #{user_id}")
        {:ok, :skipped}
    end
  end

  @doc """
  Gets pool stats from the Solana bankroll program.
  Returns vault balances, LP prices, etc.
  """
  @doc """
  Gets on-chain PlayerState for a wallet: nonce, has_active_order.
  Returns {:ok, %{nonce: int, has_active_order: bool}} or {:error, reason}
  """
  def get_player_state(wallet_address) do
    settler_url = get_settler_url()
    api_secret = get_api_secret()

    if is_nil(api_secret) or api_secret == "" do
      {:error, :not_configured}
    else
      headers = [{"Authorization", "Bearer #{api_secret}"}]

      case http_get("#{settler_url}/player-state/#{wallet_address}", headers) do
        {:ok, %{status_code: 200, body: body}} ->
          {:ok, Jason.decode!(body)}

        {:ok, %{status_code: status, body: body}} ->
          error = safe_decode(body)
          {:error, error["error"] || "Player state failed (HTTP #{status})"}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def get_pool_stats do
    settler_url = get_settler_url()
    api_secret = get_api_secret()

    if is_nil(api_secret) or api_secret == "" do
      {:error, :not_configured}
    else
      headers = [{"Authorization", "Bearer #{api_secret}"}]

      case http_get("#{settler_url}/pool-stats", headers) do
        {:ok, %{status_code: 200, body: body}} ->
          {:ok, Jason.decode!(body)}

        {:ok, %{status_code: status, body: body}} ->
          error = safe_decode(body)
          {:error, error["error"] || "Pool stats failed (HTTP #{status})"}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Gets the house balance from the bankroll vault for a given token.
  Used for max bet calculations in games.
  """
  def get_house_balance(token \\ "BUX") do
    case get_pool_stats() do
      {:ok, stats} ->
        vault_key = if token == "SOL", do: "sol", else: "bux"
        vault = stats[vault_key] || %{}
        balance = vault["netBalance"] || vault["totalBalance"] || 0.0
        {:ok, parse_balance(balance)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets LP token balance (bSOL or bBUX) for a wallet.
  vault_type: "sol" or "bux"
  """
  def get_lp_balance(wallet_address, vault_type) when vault_type in ["sol", "bux"] do
    settler_url = get_settler_url()
    api_secret = get_api_secret()

    if is_nil(api_secret) or api_secret == "" do
      {:error, :not_configured}
    else
      headers = [{"Authorization", "Bearer #{api_secret}"}]
      url = "#{settler_url}/lp-balance/#{wallet_address}/#{vault_type}"

      case http_get(url, headers) do
        {:ok, %{status_code: 200, body: body}} ->
          response = Jason.decode!(body)
          {:ok, parse_balance(response["balance"] || 0.0)}

        {:ok, %{status_code: _status, body: body}} ->
          error = safe_decode(body)
          {:error, error["error"] || "LP balance fetch failed"}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Builds an unsigned deposit transaction for user signing.
  vault_type: "sol" or "bux"
  Returns {:ok, base64_tx} or {:error, reason}
  """
  def build_deposit_tx(wallet_address, amount, vault_type) when vault_type in ["sol", "bux"] do
    settler_url = get_settler_url()
    api_secret = get_api_secret()

    if is_nil(api_secret) or api_secret == "" do
      {:error, :not_configured}
    else
      endpoint = if vault_type == "sol", do: "build-deposit-sol", else: "build-deposit-bux"
      payload = %{wallet: wallet_address, amount: amount}
      headers = auth_headers(api_secret)

      case http_post("#{settler_url}/#{endpoint}", Jason.encode!(payload), headers) do
        {:ok, %{status_code: 200, body: body}} ->
          response = Jason.decode!(body)
          {:ok, response["transaction"]}

        {:ok, %{status_code: status, body: body}} ->
          error = safe_decode(body)
          Logger.error("[BuxMinter] Build deposit tx failed (#{status}): #{inspect(error)}")
          {:error, error["error"] || "Build deposit tx failed"}

        {:error, reason} ->
          Logger.error("[BuxMinter] Build deposit tx HTTP failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @doc """
  Builds an unsigned place_bet transaction for user signing.
  vault_type: "sol" or "bux"
  Returns {:ok, base64_tx} or {:error, reason}
  """
  def build_place_bet_tx(wallet_address, game_id, nonce, amount, max_payout, vault_type) do
    settler_url = get_settler_url()
    api_secret = get_api_secret()

    if is_nil(api_secret) or api_secret == "" do
      {:error, :not_configured}
    else
      payload = %{
        wallet: wallet_address,
        gameId: game_id,
        nonce: nonce,
        amount: amount,
        maxPayout: max_payout,
        vaultType: vault_type
      }
      headers = auth_headers(api_secret)

      case http_post("#{settler_url}/build-place-bet", Jason.encode!(payload), headers) do
        {:ok, %{status_code: 200, body: body}} ->
          response = Jason.decode!(body)
          {:ok, response["transaction"]}

        {:ok, %{status_code: status, body: body}} ->
          error = safe_decode(body)
          Logger.error("[BuxMinter] Build place bet tx failed (#{status}): #{inspect(error)}")
          {:error, error["error"] || "Build place bet tx failed"}

        {:error, reason} ->
          Logger.error("[BuxMinter] Build place bet tx HTTP failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @doc """
  Builds an unsigned reclaim_expired transaction for user signing.
  Used to clear stuck bets that have expired on-chain.
  Returns {:ok, base64_tx} or {:error, reason}
  """
  def build_reclaim_expired_tx(wallet_address, nonce, vault_type) do
    settler_url = get_settler_url()
    api_secret = get_api_secret()

    if is_nil(api_secret) or api_secret == "" do
      {:error, :not_configured}
    else
      payload = %{wallet: wallet_address, nonce: nonce, vaultType: vault_type || "sol"}
      headers = auth_headers(api_secret)

      case http_post("#{settler_url}/build-reclaim-expired", Jason.encode!(payload), headers) do
        {:ok, %{status_code: 200, body: body}} ->
          response = Jason.decode!(body)
          {:ok, response["transaction"]}

        {:ok, %{status_code: status, body: body}} ->
          error = safe_decode(body)
          Logger.error("[BuxMinter] Build reclaim tx failed (#{status}): #{inspect(error)}")
          {:error, error["error"] || "Build reclaim tx failed"}

        {:error, reason} ->
          Logger.error("[BuxMinter] Build reclaim tx HTTP failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @doc """
  Builds an unsigned withdraw transaction for user signing.
  vault_type: "sol" or "bux"
  Returns {:ok, base64_tx} or {:error, reason}
  """
  def build_withdraw_tx(wallet_address, lp_amount, vault_type) when vault_type in ["sol", "bux"] do
    settler_url = get_settler_url()
    api_secret = get_api_secret()

    if is_nil(api_secret) or api_secret == "" do
      {:error, :not_configured}
    else
      endpoint = if vault_type == "sol", do: "build-withdraw-sol", else: "build-withdraw-bux"
      payload = %{wallet: wallet_address, lpAmount: lp_amount}
      headers = auth_headers(api_secret)

      case http_post("#{settler_url}/#{endpoint}", Jason.encode!(payload), headers) do
        {:ok, %{status_code: 200, body: body}} ->
          response = Jason.decode!(body)
          {:ok, response["transaction"]}

        {:ok, %{status_code: status, body: body}} ->
          error = safe_decode(body)
          Logger.error("[BuxMinter] Build withdraw tx failed (#{status}): #{inspect(error)}")
          {:error, error["error"] || "Build withdraw tx failed"}

        {:error, reason} ->
          Logger.error("[BuxMinter] Build withdraw tx HTTP failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  # ============================================================================
  # Airdrop Integration (adapted for Solana settler, full rewrite in Phase 8)
  # ============================================================================

  @doc """
  Starts a new airdrop round on the Solana airdrop program.
  """
  def airdrop_start_round(commitment_hash, end_time_unix) do
    settler_url = get_settler_url()
    api_secret = get_api_secret()

    if is_nil(api_secret) or api_secret == "" do
      {:error, :not_configured}
    else
      payload = %{commitmentHash: commitment_hash, endTime: end_time_unix}
      headers = auth_headers(api_secret)

      Logger.info("[BuxMinter] Starting airdrop round: commitment=#{String.slice(commitment_hash, 0, 16)}..., endTime=#{end_time_unix}")

      case http_post("#{settler_url}/airdrop-start-round", Jason.encode!(payload), headers) do
        {:ok, %{status_code: 200, body: body}} ->
          response = Jason.decode!(body)
          Logger.info("[BuxMinter] Airdrop round started: #{inspect(response)}")
          {:ok, response}

        {:ok, %{status_code: status, body: body}} ->
          error = safe_decode(body)
          Logger.error("[BuxMinter] Start round failed (#{status}): #{inspect(error)}")
          {:error, error["error"] || "Start round failed"}

        {:error, reason} ->
          Logger.error("[BuxMinter] Start round HTTP failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @doc """
  Builds an unsigned deposit BUX transaction for the airdrop program.
  User signs this with their wallet.
  """
  def airdrop_build_deposit(wallet, round_id, entry_index, amount) do
    settler_url = get_settler_url()
    api_secret = get_api_secret()

    if is_nil(api_secret) or api_secret == "" do
      {:error, :not_configured}
    else
      payload = %{wallet: wallet, roundId: round_id, entryIndex: entry_index, amount: amount}
      headers = auth_headers(api_secret)

      Logger.info("[BuxMinter] Building airdrop deposit tx: #{amount} BUX from #{wallet}")

      case http_post("#{settler_url}/airdrop-build-deposit", Jason.encode!(payload), headers) do
        {:ok, %{status_code: 200, body: body}} ->
          response = Jason.decode!(body)
          {:ok, response}

        {:ok, %{status_code: status, body: body}} ->
          error = safe_decode(body)
          Logger.error("[BuxMinter] Build deposit failed (#{status}): #{inspect(error)}")
          {:error, error["error"] || "Build deposit failed"}

        {:error, reason} ->
          Logger.error("[BuxMinter] Build deposit HTTP failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @doc """
  Builds an unsigned claim prize transaction for a winner.
  Winner signs this with their wallet.
  """
  def airdrop_build_claim(wallet, round_id, winner_index) do
    settler_url = get_settler_url()
    api_secret = get_api_secret()

    if is_nil(api_secret) or api_secret == "" do
      {:error, :not_configured}
    else
      payload = %{wallet: wallet, roundId: round_id, winnerIndex: winner_index}
      headers = auth_headers(api_secret)

      case http_post("#{settler_url}/airdrop-build-claim", Jason.encode!(payload), headers) do
        {:ok, %{status_code: 200, body: body}} -> {:ok, Jason.decode!(body)}
        {:ok, %{status_code: status, body: body}} ->
          error = safe_decode(body)
          Logger.error("[BuxMinter] Build claim failed (#{status}): #{inspect(error)}")
          {:error, error["error"] || "Build claim failed"}
        {:error, reason} ->
          Logger.error("[BuxMinter] Build claim HTTP failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @doc """
  Reads the current roundId from the airdrop program.
  """
  def airdrop_get_vault_round_id do
    settler_url = get_settler_url()
    api_secret = get_api_secret()

    if is_nil(api_secret) or api_secret == "" do
      {:error, :not_configured}
    else
      headers = [{"Authorization", "Bearer #{api_secret}"}]

      case http_get("#{settler_url}/airdrop-vault-round-id", headers) do
        {:ok, %{status_code: 200, body: body}} ->
          response = Jason.decode!(body)
          {:ok, response["roundId"]}

        {:ok, %{status_code: status, body: body}} ->
          error = safe_decode(body)
          Logger.error("[BuxMinter] Get vault roundId failed (#{status}): #{inspect(error)}")
          {:error, error["error"] || "Get vault roundId failed"}

        {:error, reason} ->
          Logger.error("[BuxMinter] Get vault roundId HTTP failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @doc """
  Closes the current airdrop round on Solana. Returns slotAtClose and tx signature.
  """
  def airdrop_close(round_id) do
    settler_url = get_settler_url()
    api_secret = get_api_secret()

    if is_nil(api_secret) or api_secret == "" do
      {:error, :not_configured}
    else
      payload = %{roundId: round_id}
      headers = auth_headers(api_secret)

      case http_post("#{settler_url}/airdrop-close", Jason.encode!(payload), headers) do
        {:ok, %{status_code: 200, body: body}} ->
          response = Jason.decode!(body)
          Logger.info("[BuxMinter] Airdrop round #{round_id} closed: #{inspect(response)}")
          {:ok, response}

        {:ok, %{status_code: status, body: body}} ->
          error = safe_decode(body)
          Logger.error("[BuxMinter] Airdrop close failed (#{status}): #{inspect(error)}")
          {:error, error["error"] || "Airdrop close failed"}

        {:error, reason} ->
          Logger.error("[BuxMinter] Airdrop close HTTP failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @doc """
  Draws airdrop winners on-chain with server seed and winner list.
  """
  def airdrop_draw_winners(round_id, server_seed, winners) do
    settler_url = get_settler_url()
    api_secret = get_api_secret()

    if is_nil(api_secret) or api_secret == "" do
      {:error, :not_configured}
    else
      payload = %{roundId: round_id, serverSeed: server_seed, winners: winners}
      headers = auth_headers(api_secret)

      case http_post("#{settler_url}/airdrop-draw-winners", Jason.encode!(payload), headers) do
        {:ok, %{status_code: 200, body: body}} ->
          response = Jason.decode!(body)
          Logger.info("[BuxMinter] Airdrop draw completed: #{inspect(response)}")
          {:ok, response}

        {:ok, %{status_code: status, body: body}} ->
          error = safe_decode(body)
          Logger.error("[BuxMinter] Airdrop draw failed (#{status}): #{inspect(error)}")
          {:error, error["error"] || "Airdrop draw failed"}

        {:error, reason} ->
          Logger.error("[BuxMinter] Airdrop draw HTTP failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @doc """
  Sets a player's referrer on the bankroll program.
  """
  def set_player_referrer(player_wallet, referrer_wallet) do
    settler_url = get_settler_url()
    api_secret = get_api_secret()

    if is_nil(api_secret) or api_secret == "" do
      Logger.warning("[BuxMinter] API_SECRET not configured, skipping set_player_referrer")
      {:error, :not_configured}
    else
      payload = %{player: player_wallet, referrer: referrer_wallet}
      headers = auth_headers(api_secret)

      case http_post("#{settler_url}/set-player-referrer", Jason.encode!(payload), headers) do
        {:ok, %{status_code: 200, body: body}} ->
          {:ok, Jason.decode!(body)}

        {:ok, %{status_code: 409, body: body}} ->
          response = Jason.decode!(body)
          Logger.warning("[BuxMinter] Referrer already set: #{inspect(response)}")
          {:error, :already_set}

        {:ok, %{status_code: status, body: body}} ->
          error = safe_decode(body)
          Logger.error("[BuxMinter] Set referrer failed (#{status}): #{inspect(error)}")
          {:error, error["error"] || "Unknown error"}

        {:error, reason} ->
          Logger.error("[BuxMinter] HTTP request failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  # ============================================================================
  # Deprecated EVM functions — removed in Solana migration
  # These return errors to avoid silent breakage in any remaining callers.
  # ============================================================================

  @doc false
  def get_aggregated_balances(_wallet_address) do
    Logger.warning("[BuxMinter] get_aggregated_balances is deprecated (Solana migration). Use get_balance/1 instead.")
    {:error, :deprecated}
  end

  @doc false
  def get_rogue_house_balance do
    Logger.warning("[BuxMinter] get_rogue_house_balance is deprecated (Solana migration). ROGUE removed.")
    {:error, :deprecated}
  end

  @doc false
  def transfer_rogue(_to_address, _amount, _user_id, _reason \\ "deprecated") do
    Logger.warning("[BuxMinter] transfer_rogue is deprecated (Solana migration). ROGUE removed.")
    {:error, :deprecated}
  end

  @doc false
  def get_all_balances(_wallet_address) do
    Logger.warning("[BuxMinter] get_all_balances is deprecated. Use get_balance/1 instead.")
    {:error, :deprecated}
  end

  # ============================================================================
  # Private helpers
  # ============================================================================

  defp claim_sync_slot(user_id, now) do
    if :ets.whereis(@sync_dedup_table) == :undefined, do: init_dedup_table()

    case :ets.lookup(@sync_dedup_table, user_id) do
      [{^user_id, :in_flight, _started_at}] ->
        :skip

      [{^user_id, :done, completed_at}] when now - completed_at < @sync_cooldown_ms ->
        :skip

      _ ->
        :ets.insert(@sync_dedup_table, {user_id, :in_flight, now})
        :ok
    end
  end

  defp retry_delay(retry_count) do
    500 * Integer.pow(2, retry_count - 1)
  end

  defp get_settler_url do
    Application.get_env(:blockster_v2, :settler_url) ||
      System.get_env("BLOCKSTER_SETTLER_URL") ||
      "http://localhost:3000"
  end

  defp get_api_secret do
    Application.get_env(:blockster_v2, :settler_secret) ||
      System.get_env("BLOCKSTER_SETTLER_SECRET") ||
      # Fall back to legacy bux_minter_secret during migration
      Application.get_env(:blockster_v2, :bux_minter_secret) ||
      System.get_env("BUX_MINTER_SECRET")
  end

  defp auth_headers(api_secret) do
    [
      {"Content-Type", "application/json"},
      {"Authorization", "Bearer #{api_secret}"}
    ]
  end

  defp safe_decode(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> decoded
      {:error, _} -> %{"error" => body}
    end
  end

  defp parse_balance(val) when is_float(val), do: val
  defp parse_balance(val) when is_integer(val), do: val / 1.0
  defp parse_balance(val) when is_binary(val) do
    case Float.parse(val) do
      {f, _} -> f
      :error -> 0.0
    end
  end
  defp parse_balance(_), do: 0.0

  defp http_post(url, body, headers) do
    case Code.ensure_loaded(Req) do
      {:module, Req} ->
        case Req.post(url, body: body, headers: headers, receive_timeout: 60_000,
               retry: false) do
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
  rescue
    e -> {:error, Exception.message(e)}
  catch
    :exit, reason -> {:error, {:exit, reason}}
  end

  defp http_get(url, headers) do
    case Code.ensure_loaded(Req) do
      {:module, Req} ->
        case Req.get(url, headers: headers, receive_timeout: 30_000,
               retry: :transient, retry_delay: &retry_delay/1, max_retries: 5) do
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
        http_options = [{:timeout, 10_000}, {:connect_timeout, 5_000}]

        case :httpc.request(:get, {url_charlist, headers_charlist}, http_options, []) do
          {:ok, {{_, status, _}, _, response_body}} ->
            {:ok, %{status_code: status, body: to_string(response_body)}}
          {:error, reason} ->
            {:error, reason}
        end
    end
  rescue
    e -> {:error, Exception.message(e)}
  catch
    :exit, reason -> {:error, {:exit, reason}}
  end
end
