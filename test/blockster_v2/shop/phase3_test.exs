defmodule BlocksterV2.Shop.Phase3Test do
  use BlocksterV2.DataCase, async: true

  alias BlocksterV2.Cart, as: CartContext
  alias BlocksterV2.Shop
  alias BlocksterV2.Accounts.User

  # ============================================================================
  # Test Helpers
  # ============================================================================

  defp create_user(attrs \\ %{}) do
    unique_id = System.unique_integer([:positive])

    default_attrs = %{
      wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
      email: "user#{unique_id}@example.com",
      username: "user#{unique_id}",
      auth_method: "wallet"
    }

    %User{}
    |> User.changeset(Map.merge(default_attrs, attrs))
    |> Repo.insert!()
  end

  defp create_product(attrs \\ %{}) do
    unique_id = System.unique_integer([:positive])

    default_attrs = %{
      title: "Test Product #{unique_id}",
      handle: "test-product-#{unique_id}",
      status: "active",
      bux_max_discount: 50
    }

    {:ok, product} = Shop.create_product(Map.merge(default_attrs, attrs))
    product
  end

  defp create_variant(product, attrs \\ %{}) do
    default_attrs = %{
      product_id: product.id,
      price: Decimal.new("50.00"),
      title: "Default",
      inventory_quantity: 10,
      inventory_policy: "deny"
    }

    {:ok, variant} = Shop.create_variant(Map.merge(default_attrs, attrs))
    variant
  end

  # ============================================================================
  # Cart.item_count/1
  # ============================================================================

  describe "Cart.item_count/1" do
    test "returns 0 for user with no cart" do
      user = create_user()
      assert CartContext.item_count(user.id) == 0
    end

    test "returns 0 for user with empty cart" do
      user = create_user()
      CartContext.get_or_create_cart(user.id)
      assert CartContext.item_count(user.id) == 0
    end

    test "returns sum of quantities across all items" do
      user = create_user()
      product1 = create_product()
      variant1 = create_variant(product1)
      product2 = create_product()
      variant2 = create_variant(product2)

      {:ok, _} = CartContext.add_to_cart(user.id, product1.id, %{variant_id: variant1.id, quantity: 2})
      {:ok, _} = CartContext.add_to_cart(user.id, product2.id, %{variant_id: variant2.id, quantity: 3})

      assert CartContext.item_count(user.id) == 5
    end
  end

  # ============================================================================
  # Cart.clear_cart/1
  # ============================================================================

  describe "Cart.clear_cart/1" do
    test "clears all items from cart" do
      user = create_user()
      product = create_product()
      variant = create_variant(product)

      {:ok, _} = CartContext.add_to_cart(user.id, product.id, %{variant_id: variant.id, quantity: 2})
      assert CartContext.item_count(user.id) == 2

      :ok = CartContext.clear_cart(user.id)
      assert CartContext.item_count(user.id) == 0
    end

    test "returns :ok for user with no cart" do
      user = create_user()
      assert :ok = CartContext.clear_cart(user.id)
    end
  end

  # ============================================================================
  # Add to Cart (variant matching)
  # ============================================================================

  describe "add_to_cart with variants" do
    test "adds item with specific variant_id" do
      user = create_user()
      product = create_product()
      variant_s = create_variant(product, %{option1: "S", title: "Small"})
      _variant_m = create_variant(product, %{option1: "M", title: "Medium"})

      {:ok, item} = CartContext.add_to_cart(user.id, product.id, %{variant_id: variant_s.id, quantity: 1})
      assert item.variant_id == variant_s.id
      assert item.quantity == 1
    end

    test "increments quantity when same product+variant added again" do
      user = create_user()
      product = create_product()
      variant = create_variant(product, %{option1: "M"})

      {:ok, item1} = CartContext.add_to_cart(user.id, product.id, %{variant_id: variant.id, quantity: 1})
      {:ok, item2} = CartContext.add_to_cart(user.id, product.id, %{variant_id: variant.id, quantity: 2})

      assert item2.id == item1.id
      assert item2.quantity == 3
    end

    test "different variants of same product are separate cart items" do
      user = create_user()
      product = create_product()
      variant_s = create_variant(product, %{option1: "S"})
      variant_m = create_variant(product, %{option1: "M"})

      {:ok, _} = CartContext.add_to_cart(user.id, product.id, %{variant_id: variant_s.id})
      {:ok, _} = CartContext.add_to_cart(user.id, product.id, %{variant_id: variant_m.id})

      assert CartContext.item_count(user.id) == 2
    end
  end

  # ============================================================================
  # Cart Item Management
  # ============================================================================

  describe "update_item_quantity" do
    test "updates quantity for cart item" do
      user = create_user()
      product = create_product()
      variant = create_variant(product)

      {:ok, item} = CartContext.add_to_cart(user.id, product.id, %{variant_id: variant.id, quantity: 1})
      {:ok, updated} = CartContext.update_item_quantity(item, 5)
      assert updated.quantity == 5
    end
  end

  describe "remove_item" do
    test "removes a cart item" do
      user = create_user()
      product = create_product()
      variant = create_variant(product)

      {:ok, item} = CartContext.add_to_cart(user.id, product.id, %{variant_id: variant.id})
      assert CartContext.item_count(user.id) == 1

      {:ok, _} = CartContext.remove_item(item)
      assert CartContext.item_count(user.id) == 0
    end
  end

  # ============================================================================
  # BUX Token Adjustment
  # ============================================================================

  describe "update_item_bux" do
    test "sets BUX tokens within allowed range" do
      user = create_user()
      product = create_product(%{bux_max_discount: 50})
      variant = create_variant(product, %{price: Decimal.new("100.00")})

      {:ok, item} = CartContext.add_to_cart(user.id, product.id, %{variant_id: variant.id})
      # Max BUX = price * max_pct = 100 * 50 = 5000
      {:ok, updated} = CartContext.update_item_bux(item, 2500)
      assert updated.bux_tokens_to_redeem == 2500
    end

    test "rejects BUX tokens exceeding product max discount" do
      user = create_user()
      product = create_product(%{bux_max_discount: 10})
      variant = create_variant(product, %{price: Decimal.new("50.00")})

      {:ok, item} = CartContext.add_to_cart(user.id, product.id, %{variant_id: variant.id})
      # Max BUX = 50 * 10 = 500
      assert {:error, _msg} = CartContext.update_item_bux(item, 600)
    end

    test "rejects negative BUX amount" do
      user = create_user()
      product = create_product(%{bux_max_discount: 50})
      variant = create_variant(product, %{price: Decimal.new("50.00")})

      {:ok, item} = CartContext.add_to_cart(user.id, product.id, %{variant_id: variant.id})
      assert {:error, "BUX amount cannot be negative"} = CartContext.update_item_bux(item, -10)
    end
  end

  # ============================================================================
  # Cart Validation
  # ============================================================================

  describe "validate_cart_items" do
    test "returns :ok for valid cart" do
      user = create_user()
      product = create_product(%{status: "active"})
      variant = create_variant(product, %{inventory_quantity: 10, inventory_policy: "deny"})

      {:ok, _} = CartContext.add_to_cart(user.id, product.id, %{variant_id: variant.id, quantity: 2})
      cart = CartContext.get_or_create_cart(user.id) |> CartContext.preload_items()

      assert :ok = CartContext.validate_cart_items(cart)
    end

    test "reports error for inactive product" do
      user = create_user()
      product = create_product(%{status: "active"})
      variant = create_variant(product)

      {:ok, _} = CartContext.add_to_cart(user.id, product.id, %{variant_id: variant.id})

      # Archive the product
      Shop.update_product(product, %{status: "archived"})

      cart = CartContext.get_or_create_cart(user.id) |> CartContext.preload_items()
      assert {:error, errors} = CartContext.validate_cart_items(cart)
      assert Enum.any?(errors, &String.contains?(&1, "no longer available"))
    end

    test "reports error for out-of-stock variant" do
      user = create_user()
      product = create_product(%{status: "active"})
      variant = create_variant(product, %{inventory_quantity: 1, inventory_policy: "deny"})

      {:ok, item} = CartContext.add_to_cart(user.id, product.id, %{variant_id: variant.id, quantity: 1})
      {:ok, _} = CartContext.update_item_quantity(item, 5)

      cart = CartContext.get_or_create_cart(user.id) |> CartContext.preload_items()
      assert {:error, errors} = CartContext.validate_cart_items(cart)
      assert Enum.any?(errors, &String.contains?(&1, "in stock"))
    end
  end

  # ============================================================================
  # Cart Totals
  # ============================================================================

  describe "calculate_totals" do
    test "computes correct subtotal and BUX discount" do
      user = create_user()
      product = create_product(%{bux_max_discount: 50})
      variant = create_variant(product, %{price: Decimal.new("100.00")})

      {:ok, _item} = CartContext.add_to_cart(user.id, product.id, %{
        variant_id: variant.id,
        quantity: 2,
        bux_tokens_to_redeem: 500
      })

      cart = CartContext.get_or_create_cart(user.id) |> CartContext.preload_items()
      totals = CartContext.calculate_totals(cart, user.id)

      # Subtotal: $100 * 2 = $200
      assert Decimal.equal?(totals.subtotal, Decimal.new("200.00"))
      # BUX tokens: 500
      assert totals.total_bux_tokens == 500
      # BUX discount: 500 / 100 = $5.00
      assert Decimal.equal?(totals.total_bux_discount, Decimal.new("5"))
      # Remaining: $200 - $5 = $195
      assert Decimal.equal?(totals.remaining, Decimal.new("195"))
    end

    test "handles cart with multiple items" do
      user = create_user()

      product1 = create_product(%{bux_max_discount: 50})
      variant1 = create_variant(product1, %{price: Decimal.new("50.00")})

      product2 = create_product(%{bux_max_discount: 20})
      variant2 = create_variant(product2, %{price: Decimal.new("30.00")})

      {:ok, _} = CartContext.add_to_cart(user.id, product1.id, %{variant_id: variant1.id, quantity: 1, bux_tokens_to_redeem: 100})
      {:ok, _} = CartContext.add_to_cart(user.id, product2.id, %{variant_id: variant2.id, quantity: 2, bux_tokens_to_redeem: 0})

      cart = CartContext.get_or_create_cart(user.id) |> CartContext.preload_items()
      totals = CartContext.calculate_totals(cart, user.id)

      # Subtotal: $50 + $60 = $110
      assert Decimal.equal?(totals.subtotal, Decimal.new("110.00"))
      assert totals.total_bux_tokens == 100
    end
  end

  # ============================================================================
  # broadcast_cart_update/1
  # ============================================================================

  describe "broadcast_cart_update/1" do
    test "broadcasts cart count to PubSub" do
      user = create_user()
      product = create_product()
      variant = create_variant(product)

      Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "cart:#{user.id}")

      {:ok, _} = CartContext.add_to_cart(user.id, product.id, %{variant_id: variant.id, quantity: 3})
      CartContext.broadcast_cart_update(user.id)

      assert_receive {:cart_updated, 3}
    end
  end
end
