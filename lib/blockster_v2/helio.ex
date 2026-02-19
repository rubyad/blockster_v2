defmodule BlocksterV2.Helio do
  @moduledoc """
  API client for Helio (MoonPay Commerce) Charges API.
  Creates payment charges and retrieves charge status for the checkout flow.
  """

  require Logger

  @api_base "https://api.hel.io/v1"

  @doc """
  Creates a Helio charge for the remaining payment amount on an order.

  Returns `{:ok, %{charge_id: id, page_url: url}}` on success.
  """
  def create_charge(order) do
    payload = %{
      paymentRequestId: helio_paylink_id(),
      requestAmount: Decimal.to_string(order.helio_payment_amount),
      prepareRequestBody: %{
        customerDetails: %{
          additionalJSON: Jason.encode!(%{
            order_id: order.id,
            order_number: order.order_number
          })
        }
      }
    }

    api_key = Application.get_env(:blockster_v2, :helio_api_key)
    secret_key = Application.get_env(:blockster_v2, :helio_secret_key)

    case Req.post("#{@api_base}/charge/api-key",
           json: payload,
           params: [apiKey: api_key],
           headers: [{"authorization", "Bearer #{secret_key}"}],
           receive_timeout: 30_000,
           connect_options: [timeout: 10_000]
         ) do
      {:ok, %{status: status, body: body}} when status in [200, 201] ->
        # Extract charge token UUID from pageUrl (e.g. "https://moonpay.hel.io/charge/UUID")
        charge_token =
          case body["pageUrl"] do
            "https://moonpay.hel.io/charge/" <> token -> token
            url when is_binary(url) -> String.split(url, "/") |> List.last()
            _ -> body["id"]
          end

        {:ok, %{charge_id: body["id"], charge_token: charge_token, page_url: body["pageUrl"]}}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("[Helio] Charge creation failed (#{status}): #{inspect(body)}")
        {:error, "Helio error #{status}: #{inspect(body)}"}

      {:error, reason} ->
        Logger.error("[Helio] Charge creation request error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Fetches the status of an existing Helio charge.

  Returns `{:ok, body}` with charge details on success.
  """
  def get_charge(charge_id) do
    api_key = Application.get_env(:blockster_v2, :helio_api_key)

    case Req.get("#{@api_base}/charge/#{charge_id}",
           params: [apiKey: api_key],
           receive_timeout: 30_000,
           connect_options: [timeout: 10_000]
         ) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("[Helio] Get charge failed (#{status}): #{inspect(body)}")
        {:error, "Helio error #{status}: #{inspect(body)}"}

      {:error, reason} ->
        Logger.error("[Helio] Get charge request error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Lists recent transactions for a paylink.

  Returns `{:ok, transactions}` where transactions is a list of maps.
  """
  def get_paylink_transactions(paylink_id) do
    api_key = Application.get_env(:blockster_v2, :helio_api_key)
    secret_key = Application.get_env(:blockster_v2, :helio_secret_key)

    case Req.get("#{@api_base}/transactions/#{paylink_id}/transactions",
           params: [apiKey: api_key],
           headers: [{"authorization", "Bearer #{secret_key}"}],
           receive_timeout: 30_000,
           connect_options: [timeout: 10_000]
         ) do
      {:ok, %{status: 200, body: body}} when is_list(body) ->
        {:ok, body}

      {:ok, %{status: 200, body: %{"transactions" => txs}}} ->
        {:ok, txs}

      {:ok, %{status: 200, body: body}} ->
        # Might be wrapped differently
        {:ok, List.wrap(body)}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("[Helio] List transactions failed (#{status}): #{inspect(body)}")
        {:error, "Helio error #{status}"}

      {:error, reason} ->
        Logger.error("[Helio] List transactions error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp helio_paylink_id, do: Application.get_env(:blockster_v2, :helio_paylink_id)
end
