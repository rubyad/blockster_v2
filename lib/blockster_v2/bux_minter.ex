defmodule BlocksterV2.BuxMinter do
  @moduledoc """
  Client module for calling the BUX minting service.
  Mints BUX tokens to users' smart wallets when they earn rewards.
  """

  alias BlocksterV2.EngagementTracker
  require Logger

  @doc """
  Mints BUX tokens to a user's smart wallet.

  ## Parameters
    - wallet_address: The user's smart wallet address (ERC-4337)
    - amount: Number of BUX tokens to mint
    - user_id: The user's ID (for logging)
    - post_id: The post ID that earned the reward (for logging)

  ## Returns
    - {:ok, response} on success with transaction details
    - {:error, reason} on failure
  """
  def mint_bux(wallet_address, amount, user_id, post_id) do
    minter_url = get_minter_url()
    api_secret = get_api_secret()

    if is_nil(api_secret) or api_secret == "" do
      Logger.warning("[BuxMinter] API_SECRET not configured, skipping mint")
      {:error, :not_configured}
    else
      payload = %{
        walletAddress: wallet_address,
        amount: amount,
        userId: user_id,
        postId: post_id
      }

      headers = [
        {"Content-Type", "application/json"},
        {"Authorization", "Bearer #{api_secret}"}
      ]

      Logger.info("[BuxMinter] Minting #{amount} BUX to #{wallet_address} (user: #{user_id}, post: #{post_id})")

      case http_post("#{minter_url}/mint", Jason.encode!(payload), headers) do
        {:ok, %{status_code: 200, body: body}} ->
          response = Jason.decode!(body)
          tx_hash = response["transactionHash"]
          Logger.info("[BuxMinter] Mint successful: tx=#{tx_hash}")

          # Mark the read reward as paid in Mnesia
          EngagementTracker.mark_read_reward_paid(user_id, post_id, tx_hash)

          # Fetch the on-chain balance and update user_bux_points
          case get_balance(wallet_address) do
            {:ok, on_chain_balance} ->
              Logger.info("[BuxMinter] On-chain balance for #{wallet_address}: #{on_chain_balance}")
              EngagementTracker.update_user_bux_balance(user_id, wallet_address, on_chain_balance)
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
  def mint_bux_async(wallet_address, amount, user_id, post_id) do
    Task.start(fn ->
      mint_bux(wallet_address, amount, user_id, post_id)
    end)
  end

  @doc """
  Gets the BUX balance for a wallet address.
  """
  def get_balance(wallet_address) do
    minter_url = get_minter_url()
    api_secret = get_api_secret()

    if is_nil(api_secret) or api_secret == "" do
      {:error, :not_configured}
    else
      headers = [
        {"Authorization", "Bearer #{api_secret}"}
      ]

      case http_get("#{minter_url}/balance/#{wallet_address}", headers) do
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

  # Private helpers

  defp get_minter_url do
    # Use public URL for both environments - internal DNS can be unreliable
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
        case Req.post(url, body: body, headers: headers) do
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
        case Req.get(url, headers: headers) do
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
