defmodule BlocksterV2.TelegramNotifier do
  @moduledoc """
  Sends order notifications to a Telegram fulfillment channel via Bot API.
  Uses Req.post directly — no extra dependencies needed.
  """

  require Logger

  @telegram_api "https://api.telegram.org"

  def send_order_notification(order) do
    token = bot_token()
    chat_id = channel_id()

    if is_nil(token) || is_nil(chat_id) do
      Logger.warning("[TelegramNotifier] Missing bot_token or channel_id config, skipping")
      {:error, :not_configured}
    else
      message = format_order_message(order)

      case Req.post("#{@telegram_api}/bot#{token}/sendMessage",
             json: %{
               chat_id: chat_id,
               text: message,
               parse_mode: "HTML"
             },
             receive_timeout: 30_000
           ) do
        {:ok, %{status: 200} = resp} ->
          {:ok, resp.body}

        {:ok, %{status: status} = resp} ->
          Logger.error("[TelegramNotifier] Telegram API returned #{status}: #{inspect(resp.body)}")
          {:error, {:http_error, status}}

        {:error, reason} ->
          Logger.error("[TelegramNotifier] Failed to send: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  defp format_order_message(order) do
    items_text =
      Enum.map_join(order.order_items, "\n", fn item ->
        variant = if item.variant_title, do: " (#{item.variant_title})", else: ""
        "  #{item.product_title}#{variant} x#{item.quantity} — $#{item.subtotal}"
      end)

    line2 =
      if order.shipping_address_line2 && order.shipping_address_line2 != "",
        do: order.shipping_address_line2 <> "\n",
        else: ""

    phone =
      if order.shipping_phone && order.shipping_phone != "",
        do: "Phone: #{order.shipping_phone}\n",
        else: ""

    """
    <b>New Order ##{order.order_number}</b>

    <b>Items:</b> #{length(order.order_items)}
    #{items_text}

    <b>Ship To:</b>
    #{order.shipping_name}
    #{order.shipping_address_line1}
    #{line2}#{order.shipping_city}, #{order.shipping_state} #{order.shipping_postal_code}
    #{order.shipping_country}
    #{phone}
    <b>Payment:</b>
    Subtotal: $#{order.subtotal}
    BUX: -$#{order.bux_discount_amount} (#{order.bux_tokens_burned} BUX)
    ROGUE: $#{order.rogue_payment_amount} (#{order.rogue_tokens_sent} ROGUE)
    Helio: $#{order.helio_payment_amount} (#{order.helio_payment_currency || "N/A"})
    <b>Total: $#{order.total_paid}</b>

    Contact: #{order.shipping_email}\
    """
  end

  def send_new_post(post) do
    token = posts_bot_token()
    chat_id = posts_channel_id()

    if is_nil(token) || is_nil(chat_id) do
      Logger.warning("[TelegramNotifier] Missing posts bot_token or channel_id, skipping")
      {:error, :not_configured}
    else
      message = format_post_message(post)

      case Req.post("#{@telegram_api}/bot#{token}/sendMessage",
             json: %{
               chat_id: chat_id,
               text: message,
               parse_mode: "HTML",
               disable_web_page_preview: false
             },
             receive_timeout: 30_000
           ) do
        {:ok, %{status: 200} = resp} ->
          Logger.info("[TelegramNotifier] Posted to Telegram: #{post.title}")
          {:ok, resp.body}

        {:ok, %{status: status} = resp} ->
          Logger.error("[TelegramNotifier] Telegram API returned #{status}: #{inspect(resp.body)}")
          {:error, {:http_error, status}}

        {:error, reason} ->
          Logger.error("[TelegramNotifier] Failed to send post: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  defp format_post_message(post) do
    url = "https://blockster.com/#{post.slug}"
    hub_line = if post.hub && post.hub.name, do: "\n#{post.hub.name}", else: ""

    """
    <b>#{escape_html(post.title)}</b>#{hub_line}

    #{url}\
    """
  end

  defp escape_html(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end
  defp escape_html(_), do: ""

  defp bot_token, do: Application.get_env(:blockster_v2, :telegram_bot_token)
  defp channel_id, do: Application.get_env(:blockster_v2, :telegram_fulfillment_channel_id)
  defp posts_bot_token, do: Application.get_env(:blockster_v2, :telegram_v2_bot_token) || Application.get_env(:blockster_v2, :telegram_posts_bot_token)
  defp posts_channel_id, do: Application.get_env(:blockster_v2, :telegram_v2_channel_id) || Application.get_env(:blockster_v2, :telegram_posts_channel_id)
end
