defmodule BlocksterV2.Cart do
  @moduledoc """
  The Cart context for managing shopping carts and cart items.
  """

  import Ecto.Query, warn: false
  alias BlocksterV2.Repo
  alias BlocksterV2.Cart.{Cart, CartItem}
  alias BlocksterV2.EngagementTracker

  def get_or_create_cart(user_id) do
    case Repo.get_by(Cart, user_id: user_id) do
      nil ->
        {:ok, cart} = %Cart{} |> Cart.changeset(%{user_id: user_id}) |> Repo.insert()
        cart

      cart ->
        cart
    end
  end

  def preload_items(%Cart{} = cart) do
    Repo.preload(cart, cart_items: {from(ci in CartItem, order_by: ci.inserted_at), [product: [:images, :variants], variant: []]})
  end

  def preload_items(nil), do: nil

  def add_to_cart(user_id, product_id, attrs \\ %{}) do
    cart = get_or_create_cart(user_id)
    vid = Map.get(attrs, :variant_id)
    qty = Map.get(attrs, :quantity, 1)
    bux = Map.get(attrs, :bux_tokens_to_redeem, 0)

    existing =
      if vid do
        from(ci in CartItem,
          where: ci.cart_id == ^cart.id and ci.product_id == ^product_id and ci.variant_id == ^vid
        )
      else
        from(ci in CartItem,
          where: ci.cart_id == ^cart.id and ci.product_id == ^product_id and is_nil(ci.variant_id)
        )
      end
      |> Repo.one()

    if existing do
      existing
      |> CartItem.changeset(%{quantity: existing.quantity + qty, bux_tokens_to_redeem: bux})
      |> Repo.update()
    else
      %CartItem{}
      |> CartItem.changeset(%{
        cart_id: cart.id,
        product_id: product_id,
        variant_id: vid,
        quantity: qty,
        bux_tokens_to_redeem: bux
      })
      |> Repo.insert()
    end
  end

  def update_item_quantity(%CartItem{} = item, qty) when qty > 0 do
    item |> CartItem.changeset(%{quantity: qty}) |> Repo.update()
  end

  def update_item_bux(%CartItem{} = item, bux) do
    item = Repo.preload(item, [:product, :variant])

    price =
      if item.variant,
        do: item.variant.price,
        else: List.first(Repo.preload(item.product, :variants).variants).price

    max_pct = item.product.bux_max_discount || 0

    max_bux =
      Decimal.mult(price, Decimal.new("#{max_pct}"))
      |> Decimal.div(1)
      |> Decimal.round(0)
      |> Decimal.to_integer()

    cond do
      bux < 0 -> {:error, "BUX amount cannot be negative"}
      bux > max_bux -> {:error, "Maximum #{max_bux} BUX (#{max_pct}% max discount)"}
      true -> item |> CartItem.changeset(%{bux_tokens_to_redeem: bux}) |> Repo.update()
    end
  end

  def remove_item(%CartItem{} = item), do: Repo.delete(item)

  def calculate_totals(%Cart{} = cart, user_id) do
    cart = preload_items(cart)

    items =
      Enum.map(cart.cart_items, fn item ->
        price =
          if item.variant,
            do: item.variant.price,
            else: List.first(Repo.preload(item.product, :variants).variants).price

        %{
          item: item,
          unit_price: price,
          subtotal: Decimal.mult(price, item.quantity),
          bux_tokens: item.bux_tokens_to_redeem,
          bux_discount: Decimal.new("#{item.bux_tokens_to_redeem}") |> Decimal.div(100)
        }
      end)

    subtotal = Enum.reduce(items, Decimal.new("0"), &Decimal.add(&1.subtotal, &2))
    bux_tokens = Enum.reduce(items, 0, &(&1.bux_tokens + &2))
    bux_disc = Enum.reduce(items, Decimal.new("0"), &Decimal.add(&1.bux_discount, &2))

    bux_avail =
      case EngagementTracker.get_user_token_balances(user_id) do
        b when is_map(b) -> trunc(Map.get(b, "BUX", 0.0))
        _ -> 0
      end

    %{
      subtotal: subtotal,
      total_bux_discount: bux_disc,
      total_bux_tokens: bux_tokens,
      remaining: Decimal.sub(subtotal, bux_disc),
      bux_available: bux_avail,
      bux_allocated: bux_tokens,
      items: items
    }
  end

  def validate_cart_items(%Cart{} = cart) do
    cart = preload_items(cart)

    errors =
      Enum.reduce(cart.cart_items, [], fn item, acc ->
        product = Repo.preload(item.product, [:variants])

        cond do
          is_nil(product) ->
            ["#{item.product_id} no longer available" | acc]

          product.status != "active" ->
            ["#{product.title} no longer available" | acc]

          item.variant_id && is_nil(item.variant) ->
            ["Option for #{product.title} no longer available" | acc]

          item.variant && item.variant.inventory_policy == "deny" &&
              item.variant.inventory_quantity < item.quantity ->
            ["#{product.title} (#{item.variant.title}): only #{item.variant.inventory_quantity} in stock" | acc]

          true ->
            acc
        end
      end)

    if errors == [], do: :ok, else: {:error, Enum.reverse(errors)}
  end

  def item_subtotal(%CartItem{} = item) do
    item = Repo.preload(item, [:product, :variant])

    price =
      if item.variant,
        do: item.variant.price,
        else: List.first(Repo.preload(item.product, :variants).variants).price

    Decimal.mult(price, item.quantity)
  end

  def item_bux_discount(%CartItem{} = item) do
    Decimal.new("#{item.bux_tokens_to_redeem}") |> Decimal.div(100)
  end

  @doc "Returns total quantity of items in a user's cart."
  def item_count(user_id) do
    case Repo.get_by(Cart, user_id: user_id) do
      nil -> 0
      cart ->
        from(ci in CartItem, where: ci.cart_id == ^cart.id)
        |> Repo.aggregate(:sum, :quantity) || 0
    end
  end

  @doc "Removes all items from a user's cart."
  def clear_cart(user_id) do
    case Repo.get_by(Cart, user_id: user_id) do
      nil -> :ok
      cart ->
        from(ci in CartItem, where: ci.cart_id == ^cart.id) |> Repo.delete_all()
        :ok
    end
  end

  @doc "Broadcasts cart update to refresh badge count in navbar."
  def broadcast_cart_update(user_id) do
    count = item_count(user_id)
    Phoenix.PubSub.broadcast(BlocksterV2.PubSub, "cart:#{user_id}", {:cart_updated, count})
  end
end
