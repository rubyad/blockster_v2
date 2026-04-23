defmodule BlocksterV2Web.CartLive.Index do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.Cart, as: CartContext
  alias BlocksterV2.Shop

  @token_value_usd 0.01

  @impl true
  def mount(_params, _session, socket) do
    case socket.assigns[:current_user] do
      nil ->
        {:ok,
         socket
         |> put_flash(:info, "Please connect your wallet to view your cart")
         |> redirect(to: ~p"/")}

      user ->
        cart = CartContext.get_or_create_cart(user.id) |> CartContext.preload_items()
        warnings = validate_cart(cart)
        suggested = load_suggested_products(cart)

        {:ok,
         socket
         |> assign(:page_title, "Your Cart")
         |> assign(:cart, cart)
         |> assign(:warnings, warnings)
         |> assign(:token_value_usd, @token_value_usd)
         # SHOP-13/GLOBAL-03: snapshot the SOL/USD rate at mount so intra-page
         # renders don't drift. Checkout uses the same pattern. /wallet is
         # explicitly excluded (WALLET-03 — always-live rate).
         |> assign(:sol_usd_rate, BlocksterV2.Shop.Pricing.sol_usd_rate())
         |> assign(:suggested_products, suggested)
         |> assign_totals()}
    end
  end

  @impl true
  def handle_event("increment_quantity", %{"item-id" => item_id}, socket) do
    item = find_item(socket.assigns.cart, item_id)

    if item do
      {:ok, _} = CartContext.update_item_quantity(item, item.quantity + 1)
      {:noreply, reload_cart(socket)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("decrement_quantity", %{"item-id" => item_id}, socket) do
    item = find_item(socket.assigns.cart, item_id)

    if item && item.quantity > 1 do
      {:ok, _updated} = CartContext.update_item_quantity(item, item.quantity - 1)
      # Clamp BUX if it exceeds new max after quantity decrease
      CartContext.clamp_bux_for_item(item, item.quantity - 1)
      {:noreply, reload_cart(socket)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("remove_item", %{"item-id" => item_id}, socket) do
    item = find_item(socket.assigns.cart, item_id)

    if item do
      {:ok, _} = CartContext.remove_item(item)
      {:noreply, reload_cart(socket) |> put_flash(:info, "Item removed from cart")}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("update_bux_tokens", %{"item-id" => item_id, "bux" => bux_str}, socket) do
    item = find_item(socket.assigns.cart, item_id)

    bux = case Integer.parse(bux_str) do
      {n, _} -> max(0, n)
      :error -> 0
    end

    if item do
      case CartContext.update_item_bux(item, bux) do
        {:ok, _updated} ->
          {:noreply, reload_cart(socket)}

        {:error, msg} when is_binary(msg) ->
          {:noreply, put_flash(socket, :error, msg)}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Could not update BUX amount")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("proceed_to_checkout", _, socket) do
    cart = socket.assigns.cart
    user = socket.assigns.current_user

    # If user already has a recent pending order that matches the current cart, reuse it.
    # If the cart has changed (items added/removed/quantities changed), expire the old order.
    case BlocksterV2.Orders.get_recent_pending_order(user.id) do
      %{id: order_id} = existing_order ->
        if cart_matches_order?(cart, existing_order) do
          {:noreply, push_navigate(socket, to: ~p"/checkout/#{order_id}")}
        else
          # Cart has changed — expire the stale order and create a fresh one
          BlocksterV2.Orders.update_order(existing_order, %{status: "expired"})
          create_order_from_cart(socket, cart, user)
        end

      nil ->
        create_order_from_cart(socket, cart, user)
    end
  end

  # ── Helpers ──────────────────────────────────────────────────────────────────

  defp find_item(cart, item_id) do
    Enum.find(cart.cart_items, &(&1.id == item_id))
  end

  defp reload_cart(socket) do
    user_id = socket.assigns.current_user.id
    cart = CartContext.get_or_create_cart(user_id) |> CartContext.preload_items()
    CartContext.broadcast_cart_update(user_id)

    socket
    |> assign(:cart, cart)
    |> assign(:warnings, validate_cart(cart))
    |> assign(:suggested_products, load_suggested_products(cart))
    |> assign_totals()
  end

  defp assign_totals(socket) do
    cart = socket.assigns.cart
    user_id = socket.assigns.current_user.id
    totals = CartContext.calculate_totals(cart, user_id)
    assign(socket, :totals, totals)
  end

  defp validate_cart(cart) do
    case CartContext.validate_cart_items(cart) do
      :ok -> []
      {:error, errors} -> errors
    end
  end

  defp cart_matches_order?(cart, order) do
    cart_fingerprint =
      cart.cart_items
      |> Enum.map(fn item -> {item.product_id, item.variant_id, item.quantity, item.bux_tokens_to_redeem} end)
      |> Enum.sort()

    order_fingerprint =
      order.order_items
      |> Enum.map(fn item -> {item.product_id, item.variant_id, item.quantity, item.bux_tokens_redeemed} end)
      |> Enum.sort()

    cart_fingerprint == order_fingerprint
  end

  defp create_order_from_cart(socket, cart, user) do
    case BlocksterV2.Orders.check_rate_limit(user.id) do
      {:error, :rate_limited} ->
        {:noreply, put_flash(socket, :error, "Too many orders. Please wait before placing another order.")}

      :ok ->
        case CartContext.validate_cart_items(cart) do
          :ok ->
            case BlocksterV2.Orders.create_order_from_cart(cart, user) do
              {:ok, order} ->
                {:noreply, push_navigate(socket, to: ~p"/checkout/#{order.id}")}

              {:error, _reason} ->
                {:noreply, put_flash(socket, :error, "Could not create order. Please try again.")}
            end

          {:error, errors} ->
            {:noreply,
             socket
             |> assign(:warnings, errors)
             |> put_flash(:error, "Please fix cart issues before checkout")}
        end
    end
  end

  defp load_suggested_products(cart) do
    cart_product_ids = Enum.map(cart.cart_items, & &1.product_id) |> MapSet.new()

    Shop.get_random_products(8)
    |> Enum.map(&Shop.prepare_product_for_display/1)
    |> Enum.reject(fn p -> MapSet.member?(cart_product_ids, p.id) end)
    |> Enum.take(4)
  rescue
    _ -> []
  end

  # ── Template helpers used in HEEx ──────────────────────────────────────────

  def item_price(item) do
    if item.variant && item.variant.price do
      item.variant.price
    else
      case item.product do
        %{variants: [first | _]} -> first.price
        _ -> Decimal.new("0")
      end
    end
  end

  def item_subtotal(item) do
    Decimal.mult(item_price(item), item.quantity)
  end

  def variant_label(item) do
    parts =
      [item.variant && item.variant.option1, item.variant && item.variant.option2]
      |> Enum.reject(&is_nil/1)

    if Enum.any?(parts), do: Enum.join(parts, " · "), else: nil
  end

  def item_image(item) do
    case item.product.images do
      [first | _] -> BlocksterV2.ImageKit.w128_h128(first.src)
      _ -> "https://via.placeholder.com/128x128?text=No+Image"
    end
  end

  def max_bux_for_item(item) do
    price = item_price(item)
    max_pct = item.product.bux_max_discount || 0

    # bux_max_discount=0 means uncapped (100%), same as product detail page
    effective_pct = if max_pct == 0, do: 100, else: max_pct

    per_unit =
      price
      |> Decimal.mult(Decimal.new("#{effective_pct}"))
      |> Decimal.round(0)
      |> Decimal.to_integer()

    per_unit * item.quantity
  end

  def max_bux_label(item) do
    max_pct = item.product.bux_max_discount || 0
    max_bux = max_bux_for_item(item)

    if max_pct > 0 do
      "max #{Number.Delimit.number_to_delimited(max_bux, precision: 0)} (#{max_pct}% off)"
    else
      "max #{Number.Delimit.number_to_delimited(max_bux, precision: 0)}"
    end
  end

  def hub_badge_style(item) do
    hub = item.product.hub

    cond do
      is_nil(hub) -> nil
      hub.color_primary && hub.color_secondary ->
        "background: linear-gradient(135deg, #{hub.color_primary}, #{hub.color_secondary})"
      hub.color_primary ->
        "background: #{hub.color_primary}"
      true ->
        nil
    end
  end

  def hub_name(item) do
    case item.product.hub do
      nil -> nil
      hub -> hub.name
    end
  end

  def format_cart_price(decimal) do
    decimal
    |> Decimal.round(2)
    |> Decimal.to_string()
  end
end
