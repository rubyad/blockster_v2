defmodule BlocksterV2.SettlerClient do
  @moduledoc """
  HTTP client for the subset of settler endpoints related to shop payment
  intents. Separate from BuxMinter to keep shop code decoupled from the
  engagement-reward flow.

  Endpoints:
    * POST /intents              → generate ephemeral keypair, return pubkey
    * GET  /intents/:pubkey      → report funding status
    * POST /intents/:pubkey/sweep → sweep balance to treasury
  """

  require Logger

  @doc """
  Generates an ephemeral Solana keypair tied to `order_id` on the settler.
  Returns `{:ok, %{pubkey: "..."}}` on success.
  """
  def create_payment_intent(order_id) do
    payload = Jason.encode!(%{orderId: order_id})

    case post("/intents", payload) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"pubkey" => pubkey}} when is_binary(pubkey) -> {:ok, %{pubkey: pubkey}}
          _ -> {:error, :invalid_response}
        end

      {:ok, %{status_code: status, body: body}} ->
        Logger.error("[SettlerClient] create_payment_intent #{status}: #{body}")
        {:error, :settler_error}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Returns current funding status for the ephemeral pubkey. Expected response:

      %{
        "balance_lamports" => 42_000_000,   # balance on the ephemeral address
        "funded"           => true,         # >= expected
        "funded_tx_sig"    => "xxxxx..."    # signature that funded it (nullable)
      }
  """
  def intent_status(pubkey, expected_lamports) do
    url = "/intents/#{pubkey}?expected=#{expected_lamports}"

    case get(url) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, resp} -> {:ok, resp}
          _ -> {:error, :invalid_response}
        end

      {:ok, %{status_code: status, body: body}} ->
        Logger.error("[SettlerClient] intent_status #{status}: #{body}")
        {:error, :settler_error}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Asks the settler to sweep the balance from ephemeral → treasury. The
  settler re-derives the keypair from `order_id` via HKDF, so we must pass
  it along.
  Returns `{:ok, %{tx_sig: "..."}}` on success.
  """
  def sweep_intent(pubkey, order_id) do
    body = Jason.encode!(%{orderId: order_id})

    case post("/intents/#{pubkey}/sweep", body) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"tx_sig" => sig}} when is_binary(sig) -> {:ok, %{tx_sig: sig}}
          _ -> {:error, :invalid_response}
        end

      {:ok, %{status_code: status, body: body}} ->
        Logger.error("[SettlerClient] sweep_intent #{status}: #{body}")
        {:error, :settler_error}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ── HTTP helpers ────────────────────────────────────────────────────────────

  defp post(path, body) do
    url = base_url() <> path

    case Req.post(url, body: body, headers: headers(), receive_timeout: 30_000, retry: false) do
      {:ok, %Req.Response{status: status, body: response_body}} ->
        {:ok, %{status_code: status, body: stringify(response_body)}}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp get(path) do
    url = base_url() <> path

    case Req.get(url, headers: headers(), receive_timeout: 20_000, retry: false) do
      {:ok, %Req.Response{status: status, body: response_body}} ->
        {:ok, %{status_code: status, body: stringify(response_body)}}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp base_url do
    Application.get_env(:blockster_v2, :settler_url) ||
      System.get_env("BLOCKSTER_SETTLER_URL") ||
      "http://localhost:3000"
  end

  defp api_secret do
    Application.get_env(:blockster_v2, :settler_secret) ||
      System.get_env("BLOCKSTER_SETTLER_SECRET") ||
      "dev-secret"
  end

  defp headers do
    [
      {"Content-Type", "application/json"},
      {"Authorization", "Bearer #{api_secret()}"}
    ]
  end

  defp stringify(body) when is_binary(body), do: body
  defp stringify(body), do: Jason.encode!(body)
end
