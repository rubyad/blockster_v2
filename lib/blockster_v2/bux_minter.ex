defmodule BlocksterV2.BuxMinter do
  @moduledoc """
  Client module for calling the BUX minting service.
  Mints BUX tokens to users' smart wallets when they earn rewards.
  NOTE: Hub tokens (moonBUX, neoBUX, etc.) removed - only BUX remains for rewards.
  """

  alias BlocksterV2.EngagementTracker
  require Logger

  # ETS table for deduplicating concurrent sync_user_balances_async calls
  @sync_dedup_table :bux_minter_sync_dedup
  # Minimum interval between syncs for the same user (in milliseconds)
  @sync_cooldown_ms 5_000

  # Valid token types that can be minted (hub tokens removed)
  @valid_tokens ~w(BUX)

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
  Returns the list of valid token types.
  """
  def valid_tokens, do: @valid_tokens

  @doc """
  Mints BUX tokens to a user's smart wallet.

  ## Parameters
    - wallet_address: The user's smart wallet address (ERC-4337)
    - amount: Number of tokens to mint
    - user_id: The user's ID (for logging)
    - post_id: The post ID that earned the reward (for logging)
    - reward_type: The type of reward - :read, :x_share, or :video_watch

  ## Returns
    - {:ok, response} on success with transaction details
    - {:error, reason} on failure

  NOTE: Hub tokens removed. Token parameter kept for backward compatibility but always mints BUX.
  """
  def mint_bux(wallet_address, amount, user_id, post_id, reward_type, _token \\ "BUX", _hub_id \\ nil)
      when reward_type in [:read, :x_share, :video_watch, :signup, :phone_verified, :shop_affiliate, :shop_refund] do
    minter_url = get_minter_url()
    api_secret = get_api_secret()

    # Always use BUX (hub tokens removed)
    token = "BUX"

    if is_nil(api_secret) or api_secret == "" do
      Logger.warning("[BuxMinter] API_SECRET not configured, skipping mint")
      {:error, :not_configured}
    else
      payload = %{
        walletAddress: wallet_address,
        amount: amount,
        userId: user_id,
        postId: post_id,
        token: token
      }

      headers = [
        {"Content-Type", "application/json"},
        {"Authorization", "Bearer #{api_secret}"}
      ]

      case http_post("#{minter_url}/mint", Jason.encode!(payload), headers) do
        {:ok, %{status_code: 200, body: body}} ->
          response = Jason.decode!(body)
          tx_hash = response["transactionHash"]
          actual_token = response["token"] || token

          # Mark the read reward as paid in Mnesia (only for read rewards)
          if reward_type == :read do
            EngagementTracker.mark_read_reward_paid(user_id, post_id, tx_hash)
          end

          # Update aggregate balance in user_bux_points (counts all tokens)
          # Fetch the specific token balance and update user_bux_balances
          case get_balance(wallet_address, actual_token) do
            {:ok, on_chain_balance} ->
              # Update aggregate balance (still stored in user_bux_points for backward compatibility)
              EngagementTracker.update_user_bux_balance(user_id, wallet_address, on_chain_balance)
              # Update per-token balance in user_bux_balances
              EngagementTracker.update_user_token_balance(user_id, wallet_address, actual_token, on_chain_balance)
            {:error, reason} ->
              Logger.warning("[BuxMinter] Could not fetch on-chain balance: #{inspect(reason)}")
          end

          # NOTE: Pool deductions moved to calling code for clarity and consistency
          # Each reward type (read, video, x_share) handles its own pool deduction
          # using EngagementTracker.deduct_from_pool_guaranteed()

          {:ok, response}

        {:ok, %{status_code: status, body: body}} ->
          error = Jason.decode!(body)
          Logger.error("[BuxMinter] Mint failed (#{status}): #{inspect(error)}")
          {:error, error["error"] || "Unknown error"}

        {:error, reason} ->
          Logger.error("[BuxMinter] HTTP request failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @doc """
  Burns (transfers to treasury) BUX tokens from a user's smart wallet for shop checkout.
  Calls the /burn endpoint on the BUX minter service.

  ## Parameters
    - wallet_address: The user's smart wallet address
    - amount: Number of BUX tokens to burn (integer)
    - user_id: The user's ID

  ## Returns
    - {:ok, response} with transactionHash on success
    - {:error, reason} on failure
  """
  def burn_bux(wallet_address, amount, user_id) do
    minter_url = get_minter_url()
    api_secret = get_api_secret()

    if is_nil(api_secret) or api_secret == "" do
      Logger.warning("[BuxMinter] API_SECRET not configured, skipping burn")
      {:error, :not_configured}
    else
      payload = %{
        walletAddress: wallet_address,
        amount: amount,
        userId: user_id,
        token: "BUX"
      }

      headers = [
        {"Content-Type", "application/json"},
        {"Authorization", "Bearer #{api_secret}"}
      ]

      case http_post("#{minter_url}/burn", Jason.encode!(payload), headers) do
        {:ok, %{status_code: 200, body: body}} ->
          response = Jason.decode!(body)

          if wallet_address do
            sync_user_balances_async(user_id, wallet_address, force: true)
          end

          {:ok, response}

        {:ok, %{status_code: status, body: body}} ->
          error =
            case Jason.decode(body) do
              {:ok, decoded} -> decoded
              {:error, _} -> %{"error" => "Burn failed (HTTP #{status})"}
            end

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
  Gets the BUX balance for a wallet address.
  NOTE: Hub tokens removed - always fetches BUX balance.
  """
  def get_balance(wallet_address, _token \\ "BUX") do
    minter_url = get_minter_url()
    api_secret = get_api_secret()
    token = "BUX"

    if is_nil(api_secret) or api_secret == "" do
      {:error, :not_configured}
    else
      headers = [
        {"Authorization", "Bearer #{api_secret}"}
      ]

      url = "#{minter_url}/balance/#{wallet_address}?token=#{token}"

      case http_get(url, headers) do
        {:ok, %{status_code: 200, body: body}} ->
          response = Jason.decode!(body)
          {:ok, response["balance"]}

        {:ok, %{status_code: _status, body: body}} ->
          error = Jason.decode!(body)
          {:error, error["error"] || "Unknown error"}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Gets all token balances for a wallet address.
  Returns a map of token => balance.
  """
  def get_all_balances(wallet_address) do
    minter_url = get_minter_url()
    api_secret = get_api_secret()

    if is_nil(api_secret) or api_secret == "" do
      {:error, :not_configured}
    else
      headers = [
        {"Authorization", "Bearer #{api_secret}"}
      ]

      case http_get("#{minter_url}/balances/#{wallet_address}", headers) do
        {:ok, %{status_code: 200, body: body}} ->
          response = Jason.decode!(body)
          {:ok, response["balances"]}

        {:ok, %{status_code: _status, body: body}} ->
          error = Jason.decode!(body)
          {:error, error["error"] || "Unknown error"}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Gets BUX and ROGUE balances.
  Returns {:ok, %{balances: %{"BUX" => float, "ROGUE" => float}}} or {:error, reason}.
  NOTE: Hub tokens removed - only BUX and ROGUE are fetched.
  """
  def get_aggregated_balances(wallet_address) do
    minter_url = get_minter_url()
    api_secret = get_api_secret()

    if is_nil(api_secret) or api_secret == "" do
      {:error, :not_configured}
    else
      headers = [
        {"Authorization", "Bearer #{api_secret}"}
      ]

      case http_get("#{minter_url}/aggregated-balances/#{wallet_address}", headers) do
        {:ok, %{status_code: 200, body: body}} ->
          response = Jason.decode!(body)
          {:ok, %{balances: response["balances"]}}

        {:ok, %{status_code: _status, body: body}} ->
          error = Jason.decode!(body)
          {:error, error["error"] || "Unknown error"}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Fetches BUX and ROGUE balances and updates the user_bux_balances Mnesia table.
  Call this on page load to sync on-chain balances with local cache.
  NOTE: Hub tokens removed - only syncs BUX and ROGUE.
  """
  def sync_user_balances(user_id, wallet_address) do
    case get_aggregated_balances(wallet_address) do
      {:ok, %{balances: balances}} ->
        # Filter to only BUX and ROGUE (hub tokens removed)
        filtered_balances = Map.take(balances, ["BUX", "ROGUE"])
        bux_balance = Map.get(filtered_balances, "BUX", 0)

        # Update BUX and ROGUE balances in Mnesia (broadcast: false to avoid redundant broadcasts)
        Enum.each(filtered_balances, fn {token, balance} ->
          EngagementTracker.update_user_token_balance(user_id, wallet_address, token, balance, broadcast: false)
        end)

        # Update the BUX balance in user_bux_points for backward compatibility
        EngagementTracker.update_user_bux_balance(user_id, wallet_address, bux_balance)

        # Broadcast token balances update to all LiveViews (including BuxBoosterLive)
        BlocksterV2Web.BuxBalanceHook.broadcast_token_balances_update(user_id, filtered_balances)

        {:ok, %{balances: filtered_balances}}

      {:error, reason} ->
        Logger.warning("[BuxMinter] Failed to sync balances for user #{user_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Syncs user balances asynchronously (fire and forget).
  Deduplicates concurrent calls for the same user - if a sync is already in-flight
  or completed within the last #{@sync_cooldown_ms}ms, the call is skipped.

  Options:
    - force: true - bypass deduplication (use after settlement/minting when balance MUST refresh)
  """
  def sync_user_balances_async(user_id, wallet_address, opts \\ []) do
    force = Keyword.get(opts, :force, false)

    if force do
      # Clear any existing cooldown so the sync runs immediately
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
            # Mark sync as completed with timestamp for cooldown
            :ets.insert(@sync_dedup_table, {user_id, :done, System.monotonic_time(:millisecond)})
          end
        end)

      :skip ->
        Logger.debug("[BuxMinter] Skipping duplicate sync for user #{user_id}")
        {:ok, :skipped}
    end
  end

  @doc """
  Gets the house balance for a specific token from the BuxBoosterGame contract.
  Returns {:ok, balance} or {:error, reason}.
  """
  def get_house_balance(token \\ "BUX") do
    minter_url = get_minter_url()
    api_secret = get_api_secret()

    token = normalize_token(token)

    if is_nil(api_secret) or api_secret == "" do
      Logger.error("[BuxMinter] API secret not configured!")
      {:error, :not_configured}
    else
      headers = [
        {"Authorization", "Bearer #{api_secret}"}
      ]

      url = "#{minter_url}/game-token-config/#{token}"

      case http_get(url, headers) do
        {:ok, %{status_code: 200, body: body}} ->
          response = Jason.decode!(body)

          # Parse balance - handle both "0" and "123.45" formats
          balance = case response["houseBalance"] do
            "0" -> 0.0
            val when is_binary(val) -> String.to_float(val)
            val when is_number(val) -> val / 1.0
          end

          {:ok, balance}

        {:ok, %{status_code: status, body: body}} ->
          Logger.warning("[BuxMinter] Got status #{status}: #{body}")
          error = Jason.decode!(body)
          {:error, error["error"] || "Unknown error"}

        {:error, reason} ->
          Logger.error("[BuxMinter] HTTP error: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @doc """
  Gets the house balance for ROGUE from the ROGUEBankroll contract.
  Returns {:ok, balance} or {:error, reason}.
  """
  def get_rogue_house_balance do
    minter_url = get_minter_url()
    api_secret = get_api_secret()

    if is_nil(api_secret) or api_secret == "" do
      Logger.error("[BuxMinter] API secret not configured!")
      {:error, :not_configured}
    else
      headers = [
        {"Authorization", "Bearer #{api_secret}"}
      ]

      url = "#{minter_url}/rogue-house-balance"

      case http_get(url, headers) do
        {:ok, %{status_code: 200, body: body}} ->
          response = Jason.decode!(body)

          # Parse net balance - this is what we use for max bet calculations
          balance = case response["netBalance"] do
            "0" -> 0.0
            val when is_binary(val) -> String.to_float(val)
            val when is_number(val) -> val / 1.0
          end

          {:ok, balance}

        {:ok, %{status_code: status, body: body}} ->
          Logger.warning("[BuxMinter] Got status #{status}: #{body}")
          error = Jason.decode!(body)
          {:error, error["error"] || "Unknown error"}

        {:error, reason} ->
          Logger.error("[BuxMinter] HTTP error: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  # Normalize token name - always returns BUX (hub tokens removed)
  defp normalize_token(_token), do: "BUX"

  @doc """
  Sets a player's referrer on both BuxBoosterGame and ROGUEBankroll contracts.
  Called when a new user signs up with a referral link.

  ## Parameters
    - player_wallet: The new user's smart wallet address
    - referrer_wallet: The referrer's smart wallet address

  ## Returns
    - {:ok, results} on success (at least one contract succeeded)
    - {:error, :already_set} if referrer already set on both contracts
    - {:error, reason} on failure
  """
  def set_player_referrer(player_wallet, referrer_wallet) do
    minter_url = get_minter_url()
    api_secret = get_api_secret()

    if is_nil(api_secret) or api_secret == "" do
      Logger.warning("[BuxMinter] API_SECRET not configured, skipping set_player_referrer")
      {:error, :not_configured}
    else
      payload = %{
        player: player_wallet,
        referrer: referrer_wallet
      }

      headers = [
        {"Content-Type", "application/json"},
        {"Authorization", "Bearer #{api_secret}"}
      ]

      case http_post("#{minter_url}/set-player-referrer", Jason.encode!(payload), headers) do
        {:ok, %{status_code: 200, body: body}} ->
          response = Jason.decode!(body)
          {:ok, response}

        {:ok, %{status_code: 409, body: body}} ->
          # Referrer already set on both contracts
          response = Jason.decode!(body)
          Logger.warning("[BuxMinter] Referrer already set: #{inspect(response)}")
          {:error, :already_set}

        {:ok, %{status_code: status, body: body}} ->
          error = Jason.decode!(body)
          Logger.error("[BuxMinter] Set referrer failed (#{status}): #{inspect(error)}")
          {:error, error["error"] || "Unknown error"}

        {:error, reason} ->
          Logger.error("[BuxMinter] HTTP request failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  # Private helpers

  # Claims a sync slot for a user. Returns :ok if we should proceed, :skip if deduplicated.
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

  # Exponential backoff for Req retries: 500ms, 1s, 2s, 4s, 8s
  defp retry_delay(retry_count) do
    500 * Integer.pow(2, retry_count - 1)
  end

  defp get_minter_url do
    # Use environment variable if set, otherwise fall back to public URL
    Application.get_env(:blockster_v2, :bux_minter_url) ||
      System.get_env("BUX_MINTER_URL") ||
      "https://bux-minter.fly.dev"
  end

  defp get_api_secret do
    Application.get_env(:blockster_v2, :bux_minter_secret) ||
      System.get_env("BUX_MINTER_SECRET")
  end

  defp http_post(url, body, headers) do
    # Use Req if available, otherwise fall back to httpc
    case Code.ensure_loaded(Req) do
      {:module, Req} ->
        # Use longer timeout for blockchain transactions which can take time
        # Use inet backend for DNS to avoid issues with Erlang distributed mode
        case Req.post(url, body: body, headers: headers, receive_timeout: 60_000,
               retry: :transient, retry_delay: &retry_delay/1, max_retries: 5,
               connect_options: [transport_opts: [inet_backend: :inet]]) do
          {:ok, %Req.Response{status: status, body: response_body}} ->
            body_string = if is_binary(response_body), do: response_body, else: Jason.encode!(response_body)
            {:ok, %{status_code: status, body: body_string}}
          {:error, reason} ->
            {:error, reason}
        end

      _ ->
        # Fallback to httpc with timeout to prevent hanging
        :inets.start()
        :ssl.start()

        url_charlist = String.to_charlist(url)
        body_charlist = String.to_charlist(body)
        headers_charlist = Enum.map(headers, fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)
        # Add 15 second timeout to prevent hanging
        http_options = [{:timeout, 15_000}, {:connect_timeout, 5_000}]

        case :httpc.request(:post, {url_charlist, headers_charlist, ~c"application/json", body_charlist}, http_options, []) do
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
        # Use inet backend for DNS to avoid issues with Erlang distributed mode
        case Req.get(url, headers: headers, receive_timeout: 30_000,
               retry: :transient, retry_delay: &retry_delay/1, max_retries: 5,
               connect_options: [transport_opts: [inet_backend: :inet]]) do
          {:ok, %Req.Response{status: status, body: response_body}} ->
            body_string = if is_binary(response_body), do: response_body, else: Jason.encode!(response_body)
            {:ok, %{status_code: status, body: body_string}}
          {:error, reason} ->
            {:error, reason}
        end

      _ ->
        # Fallback to httpc with timeout to prevent hanging
        :inets.start()
        :ssl.start()

        url_charlist = String.to_charlist(url)
        headers_charlist = Enum.map(headers, fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)
        # Add 10 second timeout to prevent hanging
        http_options = [{:timeout, 10_000}, {:connect_timeout, 5_000}]

        case :httpc.request(:get, {url_charlist, headers_charlist}, http_options, []) do
          {:ok, {{_, status, _}, _, response_body}} ->
            {:ok, %{status_code: status, body: to_string(response_body)}}
          {:error, reason} ->
            {:error, reason}
        end
    end
  end
end
