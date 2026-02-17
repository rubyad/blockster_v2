defmodule BlocksterV2.Shop.CheckoutTest do
  use BlocksterV2.DataCase, async: true

  alias BlocksterV2.Cart, as: CartContext
  alias BlocksterV2.Cart.Cart, as: CartSchema
  alias BlocksterV2.Cart.CartItem
  alias BlocksterV2.Orders
  alias BlocksterV2.Orders.{Order, OrderItem, AffiliatePayout}
  alias BlocksterV2.Shop
  alias BlocksterV2.Shop.ProductConfig
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
  # Schema Changeset Tests
  # ============================================================================

  describe "Cart.Cart changeset" do
    test "valid changeset with user_id" do
      user = create_user()
      changeset = CartSchema.changeset(%CartSchema{}, %{user_id: user.id})
      assert changeset.valid?
    end

    test "invalid without user_id" do
      changeset = CartSchema.changeset(%CartSchema{}, %{})
      refute changeset.valid?
      assert %{user_id: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "Cart.CartItem changeset" do
    test "valid changeset with required fields" do
      changeset =
        CartItem.changeset(%CartItem{}, %{
          cart_id: Ecto.UUID.generate(),
          product_id: Ecto.UUID.generate(),
          quantity: 2
        })

      assert changeset.valid?
    end

    test "invalid with zero quantity" do
      changeset =
        CartItem.changeset(%CartItem{}, %{
          cart_id: Ecto.UUID.generate(),
          product_id: Ecto.UUID.generate(),
          quantity: 0
        })

      refute changeset.valid?
      assert %{quantity: ["must be greater than 0"]} = errors_on(changeset)
    end

    test "invalid with negative bux_tokens_to_redeem" do
      changeset =
        CartItem.changeset(%CartItem{}, %{
          cart_id: Ecto.UUID.generate(),
          product_id: Ecto.UUID.generate(),
          quantity: 1,
          bux_tokens_to_redeem: -5
        })

      refute changeset.valid?
      assert %{bux_tokens_to_redeem: ["must be greater than or equal to 0"]} = errors_on(changeset)
    end

    test "defaults bux_tokens_to_redeem to 0" do
      changeset =
        CartItem.changeset(%CartItem{}, %{
          cart_id: Ecto.UUID.generate(),
          product_id: Ecto.UUID.generate(),
          quantity: 1
        })

      assert Ecto.Changeset.get_field(changeset, :bux_tokens_to_redeem) == 0
    end
  end

  describe "Orders.Order changesets" do
    test "create_changeset with valid data" do
      user = create_user()

      changeset =
        Order.create_changeset(%Order{}, %{
          order_number: "BLK-20260216-TEST",
          user_id: user.id,
          subtotal: Decimal.new("100.00"),
          total_paid: Decimal.new("100.00")
        })

      assert changeset.valid?
    end

    test "create_changeset requires order_number, user_id, subtotal, total_paid" do
      changeset = Order.create_changeset(%Order{}, %{})
      refute changeset.valid?
      errors = errors_on(changeset)
      assert errors[:order_number]
      assert errors[:user_id]
      assert errors[:subtotal]
      assert errors[:total_paid]
    end

    test "shipping_changeset validates required shipping fields" do
      changeset = Order.shipping_changeset(%Order{}, %{})
      refute changeset.valid?
      errors = errors_on(changeset)
      assert errors[:shipping_name]
      assert errors[:shipping_email]
      assert errors[:shipping_address_line1]
      assert errors[:shipping_city]
      assert errors[:shipping_postal_code]
      assert errors[:shipping_country]
    end

    test "shipping_changeset validates email format" do
      changeset =
        Order.shipping_changeset(%Order{}, %{
          shipping_name: "Test",
          shipping_email: "not-an-email",
          shipping_address_line1: "123 Main St",
          shipping_city: "NYC",
          shipping_postal_code: "10001",
          shipping_country: "US"
        })

      refute changeset.valid?
      assert %{shipping_email: ["has invalid format"]} = errors_on(changeset)
    end

    test "shipping_changeset valid with proper data" do
      changeset =
        Order.shipping_changeset(%Order{}, %{
          shipping_name: "Test User",
          shipping_email: "test@example.com",
          shipping_address_line1: "123 Main St",
          shipping_city: "NYC",
          shipping_postal_code: "10001",
          shipping_country: "US"
        })

      assert changeset.valid?
    end

    test "bux_payment_changeset requires tx_hash" do
      changeset = Order.bux_payment_changeset(%Order{}, %{status: "bux_paid"})
      refute changeset.valid?
      assert %{bux_burn_tx_hash: ["can't be blank"]} = errors_on(changeset)
    end

    test "status_changeset validates status values" do
      changeset = Order.status_changeset(%Order{}, %{status: "invalid_status"})
      refute changeset.valid?
      assert %{status: ["is invalid"]} = errors_on(changeset)
    end

    test "status_changeset accepts valid status" do
      for status <- ~w(pending bux_pending bux_paid rogue_pending rogue_paid helio_pending paid processing shipped delivered expired cancelled refunded) do
        changeset = Order.status_changeset(%Order{}, %{status: status})
        assert changeset.valid?, "Expected '#{status}' to be valid"
      end
    end
  end

  describe "Orders.OrderItem changeset" do
    test "valid with required fields" do
      changeset =
        OrderItem.changeset(%OrderItem{}, %{
          order_id: Ecto.UUID.generate(),
          product_id: Ecto.UUID.generate(),
          product_title: "Test Product",
          quantity: 2,
          unit_price: Decimal.new("25.00"),
          subtotal: Decimal.new("50.00")
        })

      assert changeset.valid?
    end

    test "invalid without required fields" do
      changeset = OrderItem.changeset(%OrderItem{}, %{})
      refute changeset.valid?
      errors = errors_on(changeset)
      assert errors[:order_id]
      assert errors[:product_id]
      assert errors[:product_title]
      # quantity has default 1, so won't appear in errors
      assert errors[:unit_price]
      assert errors[:subtotal]
    end

    test "validates fulfillment_status values" do
      changeset =
        OrderItem.changeset(%OrderItem{}, %{
          order_id: Ecto.UUID.generate(),
          product_id: Ecto.UUID.generate(),
          product_title: "Test",
          quantity: 1,
          unit_price: Decimal.new("10.00"),
          subtotal: Decimal.new("10.00"),
          fulfillment_status: "bad_status"
        })

      refute changeset.valid?
      assert %{fulfillment_status: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "Orders.AffiliatePayout changeset" do
    test "valid with required fields" do
      changeset =
        AffiliatePayout.changeset(%AffiliatePayout{}, %{
          order_id: Ecto.UUID.generate(),
          referrer_id: 1,
          currency: "BUX",
          basis_amount: Decimal.new("100"),
          commission_rate: Decimal.new("0.05"),
          commission_amount: Decimal.new("5")
        })

      assert changeset.valid?
    end

    test "validates currency values" do
      changeset =
        AffiliatePayout.changeset(%AffiliatePayout{}, %{
          order_id: Ecto.UUID.generate(),
          referrer_id: 1,
          currency: "INVALID",
          basis_amount: Decimal.new("100"),
          commission_rate: Decimal.new("0.05"),
          commission_amount: Decimal.new("5")
        })

      refute changeset.valid?
      assert %{currency: ["is invalid"]} = errors_on(changeset)
    end

    test "validates status values" do
      changeset =
        AffiliatePayout.changeset(%AffiliatePayout{}, %{
          order_id: Ecto.UUID.generate(),
          referrer_id: 1,
          currency: "BUX",
          basis_amount: 100,
          commission_rate: Decimal.new("0.05"),
          commission_amount: 5,
          status: "invalid"
        })

      refute changeset.valid?
      assert %{status: ["is invalid"]} = errors_on(changeset)
    end

    test "validates commission_rate bounds" do
      # Too high
      changeset =
        AffiliatePayout.changeset(%AffiliatePayout{}, %{
          order_id: Ecto.UUID.generate(),
          referrer_id: 1,
          currency: "BUX",
          basis_amount: 100,
          commission_rate: Decimal.new("1.5"),
          commission_amount: 5
        })

      refute changeset.valid?
      assert %{commission_rate: [_]} = errors_on(changeset)
    end
  end

  describe "Shop.ProductConfig changeset" do
    test "valid with product_id" do
      changeset =
        ProductConfig.changeset(%ProductConfig{}, %{
          product_id: Ecto.UUID.generate()
        })

      assert changeset.valid?
    end

    test "invalid without product_id" do
      changeset = ProductConfig.changeset(%ProductConfig{}, %{})
      refute changeset.valid?
      assert %{product_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates size_type values" do
      changeset =
        ProductConfig.changeset(%ProductConfig{}, %{
          product_id: Ecto.UUID.generate(),
          size_type: "invalid_type"
        })

      refute changeset.valid?
      assert %{size_type: ["is invalid"]} = errors_on(changeset)
    end

    test "accepts all valid size_types" do
      for size_type <- ~w(clothing mens_shoes womens_shoes unisex_shoes one_size) do
        changeset =
          ProductConfig.changeset(%ProductConfig{}, %{
            product_id: Ecto.UUID.generate(),
            size_type: size_type
          })

        assert changeset.valid?, "Expected size_type '#{size_type}' to be valid"
      end
    end

    test "defaults checkout_enabled to false" do
      changeset =
        ProductConfig.changeset(%ProductConfig{}, %{
          product_id: Ecto.UUID.generate()
        })

      assert Ecto.Changeset.get_field(changeset, :checkout_enabled) == false
    end
  end

  # ============================================================================
  # Cart Context Tests
  # ============================================================================

  describe "CartContext.get_or_create_cart/1" do
    test "creates a new cart for a user" do
      user = create_user()
      cart = CartContext.get_or_create_cart(user.id)
      assert cart.user_id == user.id
      assert cart.id
    end

    test "returns existing cart on subsequent calls" do
      user = create_user()
      cart1 = CartContext.get_or_create_cart(user.id)
      cart2 = CartContext.get_or_create_cart(user.id)
      assert cart1.id == cart2.id
    end
  end

  describe "CartContext.add_to_cart/3" do
    test "adds a new item to the cart" do
      user = create_user()
      product = create_product()
      _variant = create_variant(product)

      {:ok, item} = CartContext.add_to_cart(user.id, product.id)
      assert item.quantity == 1
      assert item.product_id == product.id
    end

    test "increments quantity for existing item" do
      user = create_user()
      product = create_product()
      _variant = create_variant(product)

      {:ok, item1} = CartContext.add_to_cart(user.id, product.id, %{quantity: 1})
      {:ok, item2} = CartContext.add_to_cart(user.id, product.id, %{quantity: 2})

      assert item2.id == item1.id
      assert item2.quantity == 3
    end

    test "adds separate items for different variants" do
      user = create_user()
      product = create_product()
      variant1 = create_variant(product, %{title: "Small", option1: "S"})
      variant2 = create_variant(product, %{title: "Large", option1: "L"})

      {:ok, item1} = CartContext.add_to_cart(user.id, product.id, %{variant_id: variant1.id})
      {:ok, item2} = CartContext.add_to_cart(user.id, product.id, %{variant_id: variant2.id})

      refute item1.id == item2.id
    end

    test "sets bux_tokens_to_redeem" do
      user = create_user()
      product = create_product()
      _variant = create_variant(product)

      {:ok, item} = CartContext.add_to_cart(user.id, product.id, %{bux_tokens_to_redeem: 500})
      assert item.bux_tokens_to_redeem == 500
    end
  end

  describe "CartContext.update_item_quantity/2" do
    test "updates item quantity" do
      user = create_user()
      product = create_product()
      _variant = create_variant(product)

      {:ok, item} = CartContext.add_to_cart(user.id, product.id)
      {:ok, updated} = CartContext.update_item_quantity(item, 5)
      assert updated.quantity == 5
    end
  end

  describe "CartContext.remove_item/1" do
    test "deletes the cart item" do
      user = create_user()
      product = create_product()
      _variant = create_variant(product)

      {:ok, item} = CartContext.add_to_cart(user.id, product.id)
      {:ok, _} = CartContext.remove_item(item)
      assert Repo.get(CartItem, item.id) == nil
    end
  end

  describe "CartContext.calculate_totals/2" do
    test "calculates correct subtotal" do
      user = create_user()
      product = create_product()
      _variant = create_variant(product, %{price: Decimal.new("25.00")})

      CartContext.add_to_cart(user.id, product.id, %{quantity: 2})
      cart = CartContext.get_or_create_cart(user.id)
      totals = CartContext.calculate_totals(cart, user.id)

      assert Decimal.equal?(totals.subtotal, Decimal.new("50.00"))
    end

    test "calculates bux discount" do
      user = create_user()
      product = create_product(%{bux_max_discount: 50})
      _variant = create_variant(product, %{price: Decimal.new("50.00")})

      CartContext.add_to_cart(user.id, product.id, %{bux_tokens_to_redeem: 1000})
      cart = CartContext.get_or_create_cart(user.id)
      totals = CartContext.calculate_totals(cart, user.id)

      assert totals.total_bux_tokens == 1000
      # 1000 BUX / 100 = $10 discount
      assert Decimal.equal?(totals.total_bux_discount, Decimal.new("10"))
    end
  end

  describe "CartContext.validate_cart_items/1" do
    test "returns :ok for valid items" do
      user = create_user()
      product = create_product(%{status: "active"})
      _variant = create_variant(product, %{inventory_quantity: 10})

      CartContext.add_to_cart(user.id, product.id)
      cart = CartContext.get_or_create_cart(user.id)
      assert :ok = CartContext.validate_cart_items(cart)
    end

    test "returns errors for inactive products" do
      user = create_user()
      product = create_product(%{status: "active"})
      _variant = create_variant(product)

      CartContext.add_to_cart(user.id, product.id)

      # Archive the product after adding to cart
      Shop.update_product(product, %{status: "archived"})

      cart = CartContext.get_or_create_cart(user.id)
      assert {:error, errors} = CartContext.validate_cart_items(cart)
      assert length(errors) > 0
    end
  end

  # ============================================================================
  # Orders Context Tests
  # ============================================================================

  describe "Orders.generate_order_number/0" do
    test "generates unique order numbers" do
      num1 = Orders.generate_order_number()
      num2 = Orders.generate_order_number()

      assert String.starts_with?(num1, "BLK-")
      assert num1 != num2
    end

    test "follows BLK-YYYYMMDD-XXXX format" do
      num = Orders.generate_order_number()
      assert Regex.match?(~r/^BLK-\d{8}-[A-Z0-9]{4}$/, num)
    end
  end

  describe "Orders.create_order_from_cart/2" do
    test "creates order with items from cart" do
      user = create_user()
      product = create_product(%{status: "active"})
      variant = create_variant(product, %{price: Decimal.new("50.00"), inventory_quantity: 10})

      CartContext.add_to_cart(user.id, product.id, %{variant_id: variant.id, quantity: 2})
      cart = CartContext.get_or_create_cart(user.id)

      {:ok, order} = Orders.create_order_from_cart(cart, user)

      assert order.user_id == user.id
      assert String.starts_with?(order.order_number, "BLK-")
      assert Decimal.equal?(order.subtotal, Decimal.new("100.00"))
      assert length(order.order_items) == 1

      item = hd(order.order_items)
      assert item.product_title == product.title
      assert item.quantity == 2
      assert Decimal.equal?(item.unit_price, Decimal.new("50.00"))
    end
  end

  # ============================================================================
  # ProductConfig CRUD Tests
  # ============================================================================

  describe "Shop.ProductConfig CRUD" do
    test "create_product_config" do
      product = create_product()

      {:ok, config} =
        Shop.create_product_config(%{
          product_id: product.id,
          has_sizes: true,
          size_type: "clothing",
          checkout_enabled: true
        })

      assert config.has_sizes == true
      assert config.size_type == "clothing"
      assert config.checkout_enabled == true
    end

    test "get_product_config" do
      product = create_product()
      {:ok, _config} = Shop.create_product_config(%{product_id: product.id})

      found = Shop.get_product_config(product.id)
      assert found.product_id == product.id
    end

    test "update_product_config" do
      product = create_product()
      {:ok, config} = Shop.create_product_config(%{product_id: product.id})

      {:ok, updated} = Shop.update_product_config(config, %{checkout_enabled: true, has_colors: true})
      assert updated.checkout_enabled == true
      assert updated.has_colors == true
    end

    test "unique constraint on product_id" do
      product = create_product()
      {:ok, _} = Shop.create_product_config(%{product_id: product.id})
      {:error, changeset} = Shop.create_product_config(%{product_id: product.id})
      assert %{product_id: ["has already been taken"]} = errors_on(changeset)
    end
  end
end
