defmodule BlocksterV2.BuxMinter do
  @moduledoc """
  Client module for calling the BUX minting service.
  Mints BUX tokens to users' smart wallets when they earn rewards.
  NOTE: Hub tokens (moonBUX, neoBUX, etc.) removed - only BUX remains for rewards.
  """

  alias BlocksterV2.EngagementTracker
  require Logger

  # Valid token types that can be minted (hub tokens removed)
  @valid_tokens ~w(BUX)

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
    - reward_type: The type of reward - :read or :x_share

  ## Returns
    - {:ok, response} on success with transaction details
    - {:error, reason} on failure

  NOTE: Hub tokens removed. Token parameter kept for backward compatibility but always mints BUX.
  """
  def mint_bux(wallet_address, amount, user_id, post_id, reward_type, _token \\ "BUX", _hub_id \\ nil)
      when reward_type in [:read, :x_share] do
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

      Logger.info("[BuxMinter] Minting #{amount} #{token} to #{wallet_address} (user: #{user_id}, post: #{post_id})")

      case http_post("#{minter_url}/mint", Jason.encode!(payload), headers) do
        {:ok, %{status_code: 200, body: body}} ->
          response = Jason.decode!(body)
          tx_hash = response["transactionHash"]
          actual_token = response["token"] || token
          Logger.info("[BuxMinter] Mint successful: #{actual_token} tx=#{tx_hash}")

          # Mark the read reward as paid in Mnesia (only for read rewards)
          if reward_type == :read do
            EngagementTracker.mark_read_reward_paid(user_id, post_id, tx_hash)
          end

          # Update aggregate balance in user_bux_points (counts all tokens)
          # Fetch the specific token balance and update user_bux_balances
          case get_balance(wallet_address, actual_token) do
            {:ok, on_chain_balance} ->
              Logger.info("[BuxMinter] On-chain #{actual_token} balance for #{wallet_address}: #{on_chain_balance}")
              # Update aggregate balance (still stored in user_bux_points for backward compatibility)
              EngagementTracker.update_user_bux_balance(user_id, wallet_address, on_chain_balance)
              # Update per-token balance in user_bux_balances
              EngagementTracker.update_user_token_balance(user_id, wallet_address, actual_token, on_chain_balance)
            {:error, reason} ->
              Logger.warning("[BuxMinter] Could not fetch on-chain balance: #{inspect(reason)}")
          end

          # Add minted amount to post_bux_points
          EngagementTracker.add_post_bux_earned(post_id, amount)

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
  Mints BUX tokens asynchronously (fire and forget).
  Use this when you don't need to wait for the transaction to complete.
  """
  def mint_bux_async(wallet_address, amount, user_id, post_id, reward_type, _token \\ "BUX")
      when reward_type in [:read, :x_share] do
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
        Logger.info("[BuxMinter] Syncing balances for user #{user_id}: BUX=#{bux_balance}")

        # Update BUX and ROGUE balances in Mnesia
        Enum.each(filtered_balances, fn {token, balance} ->
          EngagementTracker.update_user_token_balance(user_id, wallet_address, token, balance)
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
  """
  def sync_user_balances_async(user_id, wallet_address) do
    Task.start(fn ->
      sync_user_balances(user_id, wallet_address)
    end)
  end

  @doc """
  Gets the house balance for a specific token from the BuxBoosterGame contract.
  Returns {:ok, balance} or {:error, reason}.
  """
  def get_house_balance(token \\ "BUX") do
    minter_url = get_minter_url()
    api_secret = get_api_secret()

    token = normalize_token(token)

    Logger.info("[BuxMinter] Fetching house balance for #{token} from #{minter_url}")

    if is_nil(api_secret) or api_secret == "" do
      Logger.error("[BuxMinter] API secret not configured!")
      {:error, :not_configured}
    else
      headers = [
        {"Authorization", "Bearer #{api_secret}"}
      ]

      url = "#{minter_url}/game-token-config/#{token}"
      Logger.info("[BuxMinter] GET #{url}")

      case http_get(url, headers) do
        {:ok, %{status_code: 200, body: body}} ->
          response = Jason.decode!(body)
          Logger.info("[BuxMinter] Got house balance: #{response["houseBalance"]} #{token}")

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

    Logger.info("[BuxMinter] Fetching ROGUE house balance from #{minter_url}")

    if is_nil(api_secret) or api_secret == "" do
      Logger.error("[BuxMinter] API secret not configured!")
      {:error, :not_configured}
    else
      headers = [
        {"Authorization", "Bearer #{api_secret}"}
      ]

      url = "#{minter_url}/rogue-house-balance"
      Logger.info("[BuxMinter] GET #{url}")

      case http_get(url, headers) do
        {:ok, %{status_code: 200, body: body}} ->
          response = Jason.decode!(body)
          Logger.info("[BuxMinter] Got ROGUE house balance: #{response["netBalance"]} ROGUE")

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

  # Private helpers

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
        case Req.post(url, body: body, headers: headers, receive_timeout: 60_000, connect_options: [transport_opts: [inet_backend: :inet]]) do
          {:ok, %Req.Response{status: status, body: response_body}} ->
            body_string = if is_binary(response_body), do: response_body, else: Jason.encode!(response_body)
            {:ok, %{status_code: status, body: body_string}}
          {:error, reason} ->
            {:error, reason}
        end

      _ ->
        # Fallback to httpc
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
        # Use inet backend for DNS to avoid issues with Erlang distributed mode
        case Req.get(url, headers: headers, receive_timeout: 30_000, connect_options: [transport_opts: [inet_backend: :inet]]) do
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
end
