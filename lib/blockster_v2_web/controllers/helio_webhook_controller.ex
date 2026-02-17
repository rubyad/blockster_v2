defmodule BlocksterV2Web.HelioWebhookController do
  use BlocksterV2Web, :controller

  require Logger

  @doc """
  Handles incoming Helio payment webhooks.

  Verifies the Bearer token, parses the payload, detects payment currency
  (card vs crypto), and calls Orders.complete_helio_payment/2.
  Handles idempotency by ignoring webhooks for already-paid orders.
  """
  def handle(conn, params) do
    with {:ok, _} <- verify_webhook_token(conn),
         {:ok, _result} <- process_webhook(params) do
      json(conn, %{status: "ok"})
    else
      {:error, :unauthorized} ->
        conn |> put_status(401) |> json(%{error: "unauthorized"})

      {:error, reason} ->
        Logger.warning("[HelioWebhook] Processing error: #{inspect(reason)}")
        conn |> put_status(400) |> json(%{error: to_string(reason)})
    end
  end

  defp verify_webhook_token(conn) do
    expected = Application.get_env(:blockster_v2, :helio_webhook_secret)

    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] when token == expected and expected != nil ->
        {:ok, :verified}

      _ ->
        {:error, :unauthorized}
    end
  end

  defp process_webhook(%{"event" => "CREATED", "transaction" => tx} = _params) do
    meta = parse_meta(tx)
    order_id = meta["order_id"]

    if is_nil(order_id) do
      {:error, "missing order_id in transaction meta"}
    else
      case BlocksterV2.Orders.get_order(order_id) do
        nil ->
          {:error, "order not found"}

        %{status: status} when status in ["paid", "processing", "shipped", "delivered"] ->
          # Idempotent — webhook already handled for this order
          {:ok, :already_processed}

        order ->
          currency = detect_payment_currency(tx)

          BlocksterV2.Orders.complete_helio_payment(order, %{
            helio_transaction_id: tx["id"],
            helio_charge_id: tx["chargeId"] || order.helio_charge_id,
            helio_payer_address: tx["senderAddress"],
            helio_payment_currency: currency
          })
      end
    end
  end

  defp process_webhook(_params) do
    # Ignore non-CREATED events (e.g. PENDING, EXPIRED)
    {:ok, :ignored}
  end

  defp parse_meta(%{"meta" => meta}) when is_binary(meta) do
    case Jason.decode(meta) do
      {:ok, decoded} -> decoded
      _ -> %{}
    end
  end

  defp parse_meta(%{"meta" => meta}) when is_map(meta), do: meta
  defp parse_meta(_), do: %{}

  @doc false
  def detect_payment_currency(tx) do
    cond do
      # Helio includes paymentType or source field indicating card
      tx["paymentType"] == "CARD" -> "CARD"
      tx["source"] == "CARD" -> "CARD"
      # Check the currency/token field
      is_binary(tx["currency"]) -> String.upcase(tx["currency"])
      is_binary(tx["token"]) -> String.upcase(tx["token"])
      # Fallback
      true -> "USDC"
    end
  end
end
