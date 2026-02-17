defmodule BlocksterV2.OrderMailer do
  @moduledoc """
  Swoosh-based mailer for order fulfillment notifications.
  Sends detailed order info to the fulfillment team.
  """

  import Swoosh.Email

  def fulfillment_notification(order) do
    new()
    |> to({"Fulfillment Team", fulfiller_email()})
    |> from({"Blockster Shop", "shop@blockster.com"})
    |> subject("New Order ##{order.order_number}")
    |> html_body(render_fulfillment_html(order))
    |> text_body(render_fulfillment_text(order))
  end

  defp render_fulfillment_html(order) do
    items_html =
      Enum.map_join(order.order_items, "", fn item ->
        variant = if item.variant_title, do: " &mdash; #{item.variant_title}", else: ""

        """
        <li>
          <strong>#{item.product_title}</strong>#{variant}
          &times; #{item.quantity}
          ($#{item.unit_price} each)
        </li>
        """
      end)

    line2 =
      if order.shipping_address_line2 && order.shipping_address_line2 != "",
        do: "#{order.shipping_address_line2}<br/>",
        else: ""

    phone =
      if order.shipping_phone && order.shipping_phone != "",
        do: "Phone: #{order.shipping_phone}",
        else: ""

    """
    <h2>New Order ##{order.order_number}</h2>
    <p><strong>Date:</strong> #{Calendar.strftime(order.inserted_at, "%Y-%m-%d %H:%M UTC")}</p>

    <h3>Items (#{length(order.order_items)})</h3>
    <ul>#{items_html}</ul>

    <h3>Shipping Address</h3>
    <p>
      #{order.shipping_name}<br/>
      #{order.shipping_address_line1}<br/>
      #{line2}#{order.shipping_city}, #{order.shipping_state} #{order.shipping_postal_code}<br/>
      #{order.shipping_country}<br/>
      #{phone}
    </p>

    <h3>Payment Summary</h3>
    <table>
      <tr><td>Subtotal:</td><td>$#{order.subtotal}</td></tr>
      <tr><td>BUX Discount:</td><td>-$#{order.bux_discount_amount}</td></tr>
      <tr><td>ROGUE Payment:</td><td>$#{order.rogue_payment_amount}</td></tr>
      <tr><td>Helio Payment:</td><td>$#{order.helio_payment_amount} (#{order.helio_payment_currency || "N/A"})</td></tr>
      <tr><td><strong>Total:</strong></td><td><strong>$#{order.total_paid}</strong></td></tr>
    </table>

    <p><em>Contact: #{order.shipping_email}</em></p>
    """
  end

  defp render_fulfillment_text(order) do
    items_text =
      Enum.map_join(order.order_items, "\n", fn item ->
        variant = if item.variant_title, do: " (#{item.variant_title})", else: ""
        "  - #{item.product_title}#{variant} x#{item.quantity} ($#{item.unit_price} each)"
      end)

    line2 =
      if order.shipping_address_line2 && order.shipping_address_line2 != "",
        do: "\n#{order.shipping_address_line2}",
        else: ""

    phone =
      if order.shipping_phone && order.shipping_phone != "",
        do: "\nPhone: #{order.shipping_phone}",
        else: ""

    """
    New Order ##{order.order_number}
    Date: #{Calendar.strftime(order.inserted_at, "%Y-%m-%d %H:%M UTC")}

    Items (#{length(order.order_items)}):
    #{items_text}

    Shipping Address:
    #{order.shipping_name}
    #{order.shipping_address_line1}#{line2}
    #{order.shipping_city}, #{order.shipping_state} #{order.shipping_postal_code}
    #{order.shipping_country}#{phone}

    Payment Summary:
    Subtotal: $#{order.subtotal}
    BUX Discount: -$#{order.bux_discount_amount}
    ROGUE Payment: $#{order.rogue_payment_amount}
    Helio Payment: $#{order.helio_payment_amount} (#{order.helio_payment_currency || "N/A"})
    Total: $#{order.total_paid}

    Contact: #{order.shipping_email}
    """
  end

  defp fulfiller_email do
    Application.get_env(:blockster_v2, :fulfillment_email, "fulfillment@blockster.com")
  end
end
