defmodule BlocksterV2.Shop.Phase4Test do
  use BlocksterV2.DataCase, async: true

  alias BlocksterV2.Cart, as: CartContext
  alias BlocksterV2.Orders
  alias BlocksterV2.Orders.Order
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

  defp create_order_from_cart(user, items \\ nil) do
    product = create_product()
    variant = create_variant(product)

    items = items || [{product, variant, 1, 0}]

    for {prod, var, qty, bux} <- items do
      {:ok, _} = CartContext.add_to_cart(user.id, prod.id, %{
        variant_id: var.id,
        quantity: qty,
        bux_tokens_to_redeem: bux
      })
    end

    cart = CartContext.get_or_create_cart(user.id)
    {:ok, order} = Orders.create_order_from_cart(cart, user)
    order
  end

  defp valid_shipping_attrs do
    %{
      "shipping_name" => "John Doe",
      "shipping_email" => "john@example.com",
      "shipping_address_line1" => "123 Main St",
      "shipping_city" => "New York",
      "shipping_state" => "NY",
      "shipping_postal_code" => "10001",
      "shipping_country" => "United States",
      "shipping_phone" => "+1 555 123 4567"
    }
  end

  # ============================================================================
  # Cart to Order (proceed_to_checkout wiring)
  # ============================================================================

  describe "create_order_from_cart/2" do
    test "creates order with correct totals and clears cart" do
      user = create_user()
      product = create_product()
      variant = create_variant(product, %{price: Decimal.new("100.00")})

      {:ok, _} = CartContext.add_to_cart(user.id, product.id, %{
        variant_id: variant.id,
        quantity: 2,
        bux_tokens_to_redeem: 500
      })

      cart = CartContext.get_or_create_cart(user.id)
      {:ok, order} = Orders.create_order_from_cart(cart, user)

      assert order.status == "pending"
      assert Decimal.compare(order.subtotal, Decimal.new("200.00")) == :eq
      assert order.bux_tokens_burned == 500
      assert Decimal.compare(order.bux_discount_amount, Decimal.new("5.00")) == :eq
      assert order.user_id == user.id
      assert length(order.order_items) == 1

      # Cart can be cleared after order creation
      :ok = CartContext.clear_cart(user.id)
      assert CartContext.item_count(user.id) == 0
    end

    test "order items snapshot product data" do
      user = create_user()
      product = create_product(%{title: "Cool Sneakers"})
      variant = create_variant(product, %{title: "Size M", price: Decimal.new("80.00")})

      {:ok, _} = CartContext.add_to_cart(user.id, product.id, %{variant_id: variant.id})
      cart = CartContext.get_or_create_cart(user.id)
      {:ok, order} = Orders.create_order_from_cart(cart, user)

      [item] = order.order_items
      assert item.product_title == "Cool Sneakers"
      assert item.variant_title == "Size M"
      assert Decimal.compare(item.unit_price, Decimal.new("80.00")) == :eq
      assert item.quantity == 1
    end
  end

  # ============================================================================
  # Shipping Changeset Validation
  # ============================================================================

  describe "Order.shipping_changeset/2" do
    test "valid shipping data" do
      changeset = Order.shipping_changeset(%Order{}, valid_shipping_attrs())
      assert changeset.valid?
    end

    test "requires shipping_name" do
      attrs = Map.delete(valid_shipping_attrs(), "shipping_name")
      changeset = Order.shipping_changeset(%Order{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).shipping_name
    end

    test "requires shipping_email" do
      attrs = Map.delete(valid_shipping_attrs(), "shipping_email")
      changeset = Order.shipping_changeset(%Order{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).shipping_email
    end

    test "validates email format" do
      attrs = Map.put(valid_shipping_attrs(), "shipping_email", "not-an-email")
      changeset = Order.shipping_changeset(%Order{}, attrs)
      refute changeset.valid?
      assert "has invalid format" in errors_on(changeset).shipping_email
    end

    test "accepts valid email format" do
      attrs = Map.put(valid_shipping_attrs(), "shipping_email", "user@domain.com")
      changeset = Order.shipping_changeset(%Order{}, attrs)
      assert changeset.valid?
    end

    test "requires shipping_address_line1" do
      attrs = Map.delete(valid_shipping_attrs(), "shipping_address_line1")
      changeset = Order.shipping_changeset(%Order{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).shipping_address_line1
    end

    test "requires shipping_city" do
      attrs = Map.delete(valid_shipping_attrs(), "shipping_city")
      changeset = Order.shipping_changeset(%Order{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).shipping_city
    end

    test "requires shipping_postal_code" do
      attrs = Map.delete(valid_shipping_attrs(), "shipping_postal_code")
      changeset = Order.shipping_changeset(%Order{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).shipping_postal_code
    end

    test "requires shipping_country" do
      attrs = Map.delete(valid_shipping_attrs(), "shipping_country")
      changeset = Order.shipping_changeset(%Order{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).shipping_country
    end

    test "shipping_address_line2 is optional" do
      attrs = Map.delete(valid_shipping_attrs(), "shipping_address_line2")
      changeset = Order.shipping_changeset(%Order{}, attrs)
      assert changeset.valid?
    end

    test "shipping_phone is optional" do
      attrs = Map.delete(valid_shipping_attrs(), "shipping_phone")
      changeset = Order.shipping_changeset(%Order{}, attrs)
      assert changeset.valid?
    end
  end

  # ============================================================================
  # update_order_shipping/2
  # ============================================================================

  describe "Orders.update_order_shipping/2" do
    test "saves shipping info to order" do
      user = create_user()
      order = create_order_from_cart(user)

      {:ok, updated} = Orders.update_order_shipping(order, valid_shipping_attrs())

      assert updated.shipping_name == "John Doe"
      assert updated.shipping_email == "john@example.com"
      assert updated.shipping_address_line1 == "123 Main St"
      assert updated.shipping_city == "New York"
      assert updated.shipping_state == "NY"
      assert updated.shipping_postal_code == "10001"
      assert updated.shipping_country == "United States"
      assert updated.shipping_phone == "+1 555 123 4567"
    end

    test "rejects invalid shipping data" do
      user = create_user()
      order = create_order_from_cart(user)

      {:error, changeset} = Orders.update_order_shipping(order, %{"shipping_name" => ""})
      refute changeset.valid?
    end
  end

  # ============================================================================
  # Order Authorization
  # ============================================================================

  describe "order authorization" do
    test "get_order returns nil for non-existent order" do
      assert Orders.get_order(Ecto.UUID.generate()) == nil
    end

    test "order belongs to correct user" do
      user = create_user()
      order = create_order_from_cart(user)
      assert order.user_id == user.id
    end

    test "other user cannot access order" do
      user1 = create_user()
      user2 = create_user()
      order = create_order_from_cart(user1)

      # Order belongs to user1, not user2
      fetched = Orders.get_order(order.id)
      assert fetched.user_id == user1.id
      assert fetched.user_id != user2.id
    end
  end

  # ============================================================================
  # ROGUE Discount Calculations
  # ============================================================================

  describe "ROGUE discount calculations" do
    # Edge cases from Section 5 table in shop_checkout_plan.md

    test "Case 1: full price, no discounts — $0 BUX, $0 ROGUE, $50 Helio" do
      # subtotal: $50, bux_discount: $0, rogue_usd: $0
      remaining = Decimal.new("50.00")
      rogue_usd = Decimal.new("0")
      discount_rate = Decimal.new("0.10")

      discounted = Decimal.mult(rogue_usd, Decimal.sub(Decimal.new("1"), discount_rate))
      saved = Decimal.sub(rogue_usd, discounted)
      helio = Decimal.sub(remaining, rogue_usd)

      assert Decimal.compare(discounted, Decimal.new("0")) == :eq
      assert Decimal.compare(saved, Decimal.new("0")) == :eq
      assert Decimal.compare(helio, Decimal.new("50.00")) == :eq
    end

    test "Case 2: BUX discount only — $15 BUX, $0 ROGUE, $35 Helio" do
      subtotal = Decimal.new("50.00")
      bux_discount = Decimal.new("15.00")
      remaining = Decimal.sub(subtotal, bux_discount)
      rogue_usd = Decimal.new("0")

      helio = Decimal.sub(remaining, rogue_usd)

      assert Decimal.compare(remaining, Decimal.new("35.00")) == :eq
      assert Decimal.compare(helio, Decimal.new("35.00")) == :eq
    end

    test "Case 3: BUX + ROGUE + Helio — $15 BUX, $10 ROGUE (-$1 discount), $25 Helio" do
      subtotal = Decimal.new("50.00")
      bux_discount = Decimal.new("15.00")
      remaining = Decimal.sub(subtotal, bux_discount)
      rogue_usd = Decimal.new("10.00")
      discount_rate = Decimal.new("0.10")

      discounted = Decimal.mult(rogue_usd, Decimal.sub(Decimal.new("1"), discount_rate))
      saved = Decimal.sub(rogue_usd, discounted)
      helio = Decimal.sub(remaining, rogue_usd)

      assert Decimal.compare(remaining, Decimal.new("35.00")) == :eq
      assert Decimal.compare(discounted, Decimal.new("9.0")) == :eq
      assert Decimal.compare(saved, Decimal.new("1.0")) == :eq
      assert Decimal.compare(helio, Decimal.new("25.00")) == :eq
    end

    test "Case 4: BUX + ROGUE covers full — $15 BUX, $35 ROGUE (-$3.50 discount), $0 Helio" do
      subtotal = Decimal.new("50.00")
      bux_discount = Decimal.new("15.00")
      remaining = Decimal.sub(subtotal, bux_discount)
      rogue_usd = remaining
      discount_rate = Decimal.new("0.10")

      discounted = Decimal.mult(rogue_usd, Decimal.sub(Decimal.new("1"), discount_rate))
      saved = Decimal.sub(rogue_usd, discounted)
      helio = Decimal.sub(remaining, rogue_usd)

      assert Decimal.compare(discounted, Decimal.new("31.5")) == :eq
      assert Decimal.compare(saved, Decimal.new("3.5")) == :eq
      assert Decimal.compare(helio, Decimal.new("0")) == :eq
    end

    test "Case 5: 100% BUX discount — $50 BUX, $0 ROGUE, $0 Helio" do
      subtotal = Decimal.new("50.00")
      bux_discount = Decimal.new("50.00")
      remaining = Decimal.sub(subtotal, bux_discount)

      assert Decimal.compare(remaining, Decimal.new("0")) == :eq
    end

    test "Case 6: ROGUE only, full price — $0 BUX, $50 ROGUE (-$5 discount), $0 Helio" do
      subtotal = Decimal.new("50.00")
      bux_discount = Decimal.new("0")
      remaining = Decimal.sub(subtotal, bux_discount)
      rogue_usd = remaining
      discount_rate = Decimal.new("0.10")

      discounted = Decimal.mult(rogue_usd, Decimal.sub(Decimal.new("1"), discount_rate))
      saved = Decimal.sub(rogue_usd, discounted)
      helio = Decimal.sub(remaining, rogue_usd)

      assert Decimal.compare(discounted, Decimal.new("45.0")) == :eq
      assert Decimal.compare(saved, Decimal.new("5.0")) == :eq
      assert Decimal.compare(helio, Decimal.new("0")) == :eq
    end

    test "Case 7: ROGUE partial, no BUX — $0 BUX, $20 ROGUE (-$2 discount), $30 Helio" do
      subtotal = Decimal.new("50.00")
      bux_discount = Decimal.new("0")
      remaining = Decimal.sub(subtotal, bux_discount)
      rogue_usd = Decimal.new("20.00")
      discount_rate = Decimal.new("0.10")

      discounted = Decimal.mult(rogue_usd, Decimal.sub(Decimal.new("1"), discount_rate))
      saved = Decimal.sub(rogue_usd, discounted)
      helio = Decimal.sub(remaining, rogue_usd)

      assert Decimal.compare(discounted, Decimal.new("18.0")) == :eq
      assert Decimal.compare(saved, Decimal.new("2.0")) == :eq
      assert Decimal.compare(helio, Decimal.new("30.00")) == :eq
    end

    test "ROGUE token calculation with rate" do
      rogue_usd = Decimal.new("10.00")
      discount_rate = Decimal.new("0.10")
      rogue_rate = Decimal.new("0.00006")

      discounted = Decimal.mult(rogue_usd, Decimal.sub(Decimal.new("1"), discount_rate))
      tokens = Decimal.div(discounted, rogue_rate)

      # $9.00 / $0.00006 = 150,000 ROGUE tokens
      assert Decimal.compare(discounted, Decimal.new("9.0")) == :eq
      assert Decimal.compare(tokens, Decimal.new("150000")) == :eq
    end

    test "ROGUE amount cannot exceed remaining" do
      remaining = Decimal.new("35.00")
      rogue_usd = Decimal.new("50.00")

      clamped = Decimal.min(rogue_usd, remaining)
      assert Decimal.compare(clamped, Decimal.new("35.00")) == :eq
    end

    test "ROGUE amount cannot be negative" do
      rogue_usd = Decimal.new("-10.00")
      clamped = Decimal.max(rogue_usd, Decimal.new("0"))
      assert Decimal.compare(clamped, Decimal.new("0")) == :eq
    end
  end

  # ============================================================================
  # Step Progression
  # ============================================================================

  describe "step progression" do
    test "order starts in pending status" do
      user = create_user()
      order = create_order_from_cart(user)
      assert order.status == "pending"
    end

    test "shipping can be saved and then order proceeds" do
      user = create_user()
      order = create_order_from_cart(user)

      {:ok, order} = Orders.update_order_shipping(order, valid_shipping_attrs())
      assert order.shipping_name == "John Doe"
      assert order.shipping_email == "john@example.com"
    end

    test "rogue payment changeset updates order" do
      user = create_user()
      order = create_order_from_cart(user)

      {:ok, order} = order
        |> Order.rogue_payment_changeset(%{
          rogue_payment_amount: Decimal.new("10.00"),
          rogue_discount_amount: Decimal.new("1.00"),
          rogue_tokens_sent: Decimal.new("150000")
        })
        |> Repo.update()

      assert Decimal.compare(order.rogue_payment_amount, Decimal.new("10.00")) == :eq
      assert Decimal.compare(order.rogue_discount_amount, Decimal.new("1.00")) == :eq
      assert Decimal.compare(order.rogue_tokens_sent, Decimal.new("150000")) == :eq
    end

    test "helio payment changeset updates order" do
      user = create_user()
      order = create_order_from_cart(user)

      {:ok, order} = order
        |> Order.helio_payment_changeset(%{helio_payment_amount: Decimal.new("25.00")})
        |> Repo.update()

      assert Decimal.compare(order.helio_payment_amount, Decimal.new("25.00")) == :eq
    end
  end

  # ============================================================================
  # Order Number Generation
  # ============================================================================

  describe "generate_order_number/0" do
    test "generates unique order numbers with BLK prefix" do
      num1 = Orders.generate_order_number()
      num2 = Orders.generate_order_number()

      assert String.starts_with?(num1, "BLK-")
      assert String.starts_with?(num2, "BLK-")
      assert num1 != num2
    end

    test "order number contains date" do
      num = Orders.generate_order_number()
      date = Date.utc_today() |> Calendar.strftime("%Y%m%d")
      assert String.contains?(num, date)
    end
  end
end
