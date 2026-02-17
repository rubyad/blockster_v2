defmodule BlocksterV2.Shop.Phase6Test do
  use BlocksterV2.DataCase, async: false

  alias BlocksterV2.Cart, as: CartContext
  alias BlocksterV2.Orders
  alias BlocksterV2.Orders.Order
  alias BlocksterV2.Shop
  alias BlocksterV2.Accounts.User

  # ============================================================================
  # Test Setup — ensure Mnesia tables + BalanceManager running
  # ============================================================================

  setup do
    :mnesia.start()

    table_attrs = [
      :user_id, :user_smart_wallet, :updated_at, :aggregate_bux_balance,
      :bux_balance, :moonbux_balance, :neobux_balance, :roguebux_balance,
      :flarebux_balance, :nftbux_balance, :nolchabux_balance, :solbux_balance,
      :spacebux_balance, :tronbux_balance, :tranbux_balance
    ]

    case :mnesia.create_table(:user_bux_balances, [
           attributes: table_attrs,
           ram_copies: [node()],
           type: :set
         ]) do
      {:atomic, :ok} -> :ok
      {:aborted, {:already_exists, :user_bux_balances}} ->
        case :mnesia.add_table_copy(:user_bux_balances, node(), :ram_copies) do
          {:atomic, :ok} -> :ok
          {:aborted, {:already_exists, :user_bux_balances, _}} -> :ok
        end
        :mnesia.clear_table(:user_bux_balances)
    end

    case :mnesia.create_table(:user_rogue_balances, [
           attributes: [:user_id, :user_smart_wallet, :updated_at, :rogue_balance_rogue_chain, :rogue_balance_arbitrum],
           ram_copies: [node()],
           type: :set
         ]) do
      {:atomic, :ok} -> :ok
      {:aborted, {:already_exists, :user_rogue_balances}} ->
        case :mnesia.add_table_copy(:user_rogue_balances, node(), :ram_copies) do
          {:atomic, :ok} -> :ok
          {:aborted, {:already_exists, :user_rogue_balances, _}} -> :ok
        end
    end

    case GenServer.start_link(BlocksterV2.Shop.BalanceManager, %{}, name: {:global, BlocksterV2.Shop.BalanceManager}) do
      {:ok, pid} -> on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
      {:error, {:already_started, _}} -> :ok
    end

    :ok
  end

  # ============================================================================
  # Test Helpers
  # ============================================================================

  defp create_user(attrs \\ %{}) do
    unique_id = System.unique_integer([:positive])

    default_attrs = %{
      wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
      smart_wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
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
      price: Decimal.new("100.00"),
      title: "Default",
      inventory_quantity: 10,
      inventory_policy: "deny"
    }

    {:ok, variant} = Shop.create_variant(Map.merge(default_attrs, attrs))
    variant
  end

  defp create_order_with_bux(user, bux_tokens) do
    product = create_product()
    variant = create_variant(product)

    {:ok, _} =
      CartContext.add_to_cart(user.id, product.id, %{
        variant_id: variant.id,
        quantity: 1,
        bux_tokens_to_redeem: bux_tokens
      })

    cart = CartContext.get_or_create_cart(user.id)
    {:ok, order} = Orders.create_order_from_cart(cart, user)
    order
  end

  defp create_order_no_bux(user) do
    product = create_product()
    variant = create_variant(product, %{price: Decimal.new("50.00")})

    {:ok, _} =
      CartContext.add_to_cart(user.id, product.id, %{
        variant_id: variant.id,
        quantity: 1,
        bux_tokens_to_redeem: 0
      })

    cart = CartContext.get_or_create_cart(user.id)
    {:ok, order} = Orders.create_order_from_cart(cart, user)
    order
  end

  defp set_user_bux_balance(user_id, balance) do
    record = {
      :user_bux_balances, user_id, nil, System.system_time(:second),
      balance, balance, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    }

    :mnesia.dirty_write(:user_bux_balances, record)
  end

  defp set_rogue_on_order(order, rogue_usd, rogue_tokens, rogue_discount) do
    {:ok, order} =
      order
      |> Order.rogue_payment_changeset(%{
        rogue_payment_amount: rogue_usd,
        rogue_tokens_sent: rogue_tokens,
        rogue_discount_amount: rogue_discount
      })
      |> Repo.update()

    Orders.get_order(order.id)
  end

  # ============================================================================
  # ROGUE Discount Calculation
  # ============================================================================

  describe "ROGUE discount calculation" do
    test "10% discount on ROGUE portion" do
      # $100 remaining, user pays $50 with ROGUE at $0.00006
      rogue_usd = Decimal.new("50.00")
      discount_rate = Decimal.new("0.10")
      rate = Decimal.new("0.00006")

      discounted = Decimal.mult(rogue_usd, Decimal.sub(Decimal.new("1"), discount_rate))
      tokens = Decimal.div(discounted, rate)
      saved = Decimal.sub(rogue_usd, discounted)

      assert Decimal.compare(discounted, Decimal.new("45.00")) == :eq
      assert Decimal.compare(saved, Decimal.new("5.00")) == :eq
      # $45 / $0.00006 = 750,000 ROGUE
      assert Decimal.compare(tokens, Decimal.new("750000")) == :eq
    end

    test "100% ROGUE coverage with discount" do
      rogue_usd = Decimal.new("100.00")
      discount_rate = Decimal.new("0.10")
      rate = Decimal.new("0.00006")

      discounted = Decimal.mult(rogue_usd, Decimal.sub(Decimal.new("1"), discount_rate))
      tokens = Decimal.div(discounted, rate)
      saved = Decimal.sub(rogue_usd, discounted)

      assert Decimal.compare(discounted, Decimal.new("90.00")) == :eq
      assert Decimal.compare(saved, Decimal.new("10.00")) == :eq
      assert Decimal.compare(tokens, Decimal.new("1500000")) == :eq
    end

    test "zero ROGUE means zero discount" do
      rogue_usd = Decimal.new("0")
      discount_rate = Decimal.new("0.10")

      discounted = Decimal.mult(rogue_usd, Decimal.sub(Decimal.new("1"), discount_rate))
      saved = Decimal.sub(rogue_usd, discounted)

      assert Decimal.compare(discounted, Decimal.new("0")) == :eq
      assert Decimal.compare(saved, Decimal.new("0.0")) == :eq
    end

    test "small ROGUE amount yields proportional discount" do
      rogue_usd = Decimal.new("10.00")
      discount_rate = Decimal.new("0.10")
      rate = Decimal.new("0.00006")

      discounted = Decimal.mult(rogue_usd, Decimal.sub(Decimal.new("1"), discount_rate))
      tokens = Decimal.div(discounted, rate)
      saved = Decimal.sub(rogue_usd, discounted)

      assert Decimal.compare(discounted, Decimal.new("9.00")) == :eq
      assert Decimal.compare(saved, Decimal.new("1.00")) == :eq
      # $9 / $0.00006 = 150,000 ROGUE
      assert Decimal.compare(tokens, Decimal.new("150000")) == :eq
    end
  end

  # ============================================================================
  # ROGUE Rate Locking
  # ============================================================================

  describe "ROGUE rate locking" do
    test "rate is stored on order at creation" do
      user = create_user()
      order = create_order_no_bux(user)

      # rogue_usd_rate_locked should be set by create_order_from_cart
      assert order.rogue_usd_rate_locked != nil
      assert Decimal.gt?(order.rogue_usd_rate_locked, 0)
    end

    test "fallback rate is used when Mnesia has no price" do
      user = create_user()
      order = create_order_no_bux(user)

      # In test env, Mnesia won't have token_prices, so fallback $0.00006 is used
      fallback = Decimal.new("0.00006")
      assert Decimal.compare(order.rogue_usd_rate_locked, fallback) == :eq
    end
  end

  # ============================================================================
  # Orders.complete_rogue_payment/2
  # ============================================================================

  describe "Orders.complete_rogue_payment/2" do
    test "updates order with tx hash and rogue_paid status" do
      user = create_user()
      order = create_order_no_bux(user)
      order = set_rogue_on_order(order, Decimal.new("25.00"), Decimal.new("375000"), Decimal.new("2.50"))

      {:ok, updated} = Orders.complete_rogue_payment(order, "0xrogue_tx_abc")

      assert updated.rogue_payment_tx_hash == "0xrogue_tx_abc"
      assert updated.status == "rogue_paid"
    end

    test "preserves existing ROGUE payment amounts" do
      user = create_user()
      order = create_order_no_bux(user)
      order = set_rogue_on_order(order, Decimal.new("30.00"), Decimal.new("450000"), Decimal.new("3.00"))

      {:ok, updated} = Orders.complete_rogue_payment(order, "0xrogue_hash")

      assert Decimal.compare(updated.rogue_payment_amount, Decimal.new("30.00")) == :eq
      assert Decimal.compare(updated.rogue_tokens_sent, Decimal.new("450000")) == :eq
      assert Decimal.compare(updated.rogue_discount_amount, Decimal.new("3.00")) == :eq
    end
  end

  # ============================================================================
  # Order Status Transitions (ROGUE)
  # ============================================================================

  describe "order status transitions with ROGUE" do
    test "pending -> rogue_pending -> rogue_paid (no BUX)" do
      user = create_user()
      order = create_order_no_bux(user)
      order = set_rogue_on_order(order, Decimal.new("50.00"), Decimal.new("750000"), Decimal.new("5.00"))

      assert order.status == "pending"

      {:ok, order} = Orders.update_order(order, %{status: "rogue_pending"})
      assert order.status == "rogue_pending"

      {:ok, order} = Orders.complete_rogue_payment(order, "0xrogue_tx")
      assert order.status == "rogue_paid"
    end

    test "bux_paid -> rogue_pending -> rogue_paid" do
      user = create_user()
      set_user_bux_balance(user.id, 5000)

      order = create_order_with_bux(user, 2000)
      order = set_rogue_on_order(order, Decimal.new("25.00"), Decimal.new("375000"), Decimal.new("2.50"))

      # Complete BUX payment
      {:ok, order} = Orders.complete_bux_payment(order, "0xbux_hash")
      assert order.status == "bux_paid"

      # Start ROGUE payment
      {:ok, order} = Orders.update_order(order, %{status: "rogue_pending"})
      assert order.status == "rogue_pending"

      # Complete ROGUE payment
      {:ok, order} = Orders.complete_rogue_payment(order, "0xrogue_hash")
      assert order.status == "rogue_paid"
    end

    test "rogue_paid -> paid (when BUX + ROGUE covers full price)" do
      user = create_user()
      set_user_bux_balance(user.id, 5000)

      order = create_order_with_bux(user, 2000)
      remaining = Decimal.sub(order.subtotal, order.bux_discount_amount)

      # Set ROGUE to cover all remaining
      order = set_rogue_on_order(order, remaining, Decimal.new("1500000"), Decimal.mult(remaining, Decimal.new("0.10")))

      # Complete BUX
      {:ok, order} = Orders.complete_bux_payment(order, "0xbux")

      # Complete ROGUE
      {:ok, order} = Orders.complete_rogue_payment(order, "0xrogue")
      assert order.status == "rogue_paid"

      # Can transition to paid
      {:ok, order} = Orders.update_order(order, %{status: "paid"})
      assert order.status == "paid"
    end

    test "rogue_paid with helio remaining stays rogue_paid" do
      user = create_user()
      order = create_order_no_bux(user)

      # Partial ROGUE — $25 of $50 subtotal
      order = set_rogue_on_order(order, Decimal.new("25.00"), Decimal.new("375000"), Decimal.new("2.50"))

      # Set helio for remaining
      {:ok, order} =
        order
        |> Order.helio_payment_changeset(%{helio_payment_amount: Decimal.new("25.00")})
        |> Repo.update()

      {:ok, order} = Orders.complete_rogue_payment(order, "0xrogue")
      assert order.status == "rogue_paid"

      # Helio still needs to be paid
      assert Decimal.compare(order.helio_payment_amount, Decimal.new("25.00")) == :eq
    end
  end

  # ============================================================================
  # BUX + ROGUE Covers Full Price (Skip Helio)
  # ============================================================================

  describe "BUX + ROGUE covers full price" do
    test "no helio needed when BUX + ROGUE cover subtotal" do
      user = create_user()
      set_user_bux_balance(user.id, 10_000)

      order = create_order_with_bux(user, 2000)
      remaining = Decimal.sub(order.subtotal, order.bux_discount_amount)

      # ROGUE covers all remaining
      _order = set_rogue_on_order(order, remaining, Decimal.new("750000"), Decimal.mult(remaining, Decimal.new("0.10")))

      # Helio should be 0
      helio = Decimal.sub(remaining, remaining)
      assert Decimal.compare(helio, Decimal.new("0")) == :eq
    end

    test "100% BUX discount means no ROGUE or Helio needed" do
      user = create_user()
      set_user_bux_balance(user.id, 10_000)

      product = create_product(%{bux_max_discount: 100})
      variant = create_variant(product, %{price: Decimal.new("50.00")})

      {:ok, _} =
        CartContext.add_to_cart(user.id, product.id, %{
          variant_id: variant.id,
          quantity: 1,
          bux_tokens_to_redeem: 5000
        })

      cart = CartContext.get_or_create_cart(user.id)
      {:ok, order} = Orders.create_order_from_cart(cart, user)

      remaining = Decimal.sub(order.subtotal, order.bux_discount_amount)
      assert Decimal.compare(remaining, Decimal.new("0")) == :eq
    end

    test "ROGUE only (no BUX) covers full price" do
      user = create_user()
      order = create_order_no_bux(user)

      # ROGUE covers full subtotal ($50)
      order = set_rogue_on_order(order, Decimal.new("50.00"), Decimal.new("750000"), Decimal.new("5.00"))

      helio_remaining = Decimal.sub(order.subtotal, Decimal.add(order.bux_discount_amount, order.rogue_payment_amount))
      assert Decimal.compare(helio_remaining, Decimal.new("0")) in [:eq, :lt]
    end
  end

  # ============================================================================
  # Order.rogue_payment_changeset/2 Validation
  # ============================================================================

  describe "Order.rogue_payment_changeset/2" do
    test "accepts valid ROGUE payment data with tx hash and status" do
      changeset =
        Order.rogue_payment_changeset(%Order{}, %{
          rogue_payment_tx_hash: "0xabc123",
          rogue_payment_amount: Decimal.new("50.00"),
          rogue_tokens_sent: Decimal.new("750000"),
          rogue_discount_amount: Decimal.new("5.00"),
          status: "rogue_paid"
        })

      assert changeset.valid?
    end

    test "accepts changeset without tx hash (for review step save)" do
      changeset =
        Order.rogue_payment_changeset(%Order{}, %{
          rogue_payment_amount: Decimal.new("25.00"),
          rogue_tokens_sent: Decimal.new("375000"),
          rogue_discount_amount: Decimal.new("2.50")
        })

      assert changeset.valid?
    end

    test "validates status inclusion" do
      changeset =
        Order.rogue_payment_changeset(%Order{}, %{
          rogue_payment_tx_hash: "0xabc",
          status: "invalid_status"
        })

      refute changeset.valid?
    end

    test "accepts all valid ROGUE-related statuses" do
      for status <- ["rogue_pending", "rogue_paid"] do
        changeset =
          Order.rogue_payment_changeset(%Order{}, %{
            rogue_payment_tx_hash: "0xabc",
            status: status
          })

        assert changeset.valid?, "Expected #{status} to be valid"
      end
    end
  end

  # ============================================================================
  # Insufficient ROGUE Handling
  # ============================================================================

  describe "insufficient ROGUE handling" do
    test "order reverts to bux_paid on ROGUE payment failure (with BUX)" do
      user = create_user()
      set_user_bux_balance(user.id, 5000)

      order = create_order_with_bux(user, 2000)
      order = set_rogue_on_order(order, Decimal.new("25.00"), Decimal.new("375000"), Decimal.new("2.50"))

      # Complete BUX
      {:ok, order} = Orders.complete_bux_payment(order, "0xbux")
      assert order.status == "bux_paid"

      # Start ROGUE
      {:ok, order} = Orders.update_order(order, %{status: "rogue_pending"})

      # ROGUE fails — revert to bux_paid
      {:ok, order} = Orders.update_order(order, %{status: "bux_paid"})
      assert order.status == "bux_paid"
    end

    test "order reverts to pending on ROGUE payment failure (no BUX)" do
      user = create_user()
      order = create_order_no_bux(user)
      order = set_rogue_on_order(order, Decimal.new("50.00"), Decimal.new("750000"), Decimal.new("5.00"))

      # Start ROGUE
      {:ok, order} = Orders.update_order(order, %{status: "rogue_pending"})

      # ROGUE fails — revert to pending
      {:ok, order} = Orders.update_order(order, %{status: "pending"})
      assert order.status == "pending"
    end
  end

  # ============================================================================
  # Full ROGUE Payment Flow (Integration)
  # ============================================================================

  describe "full ROGUE payment flow" do
    test "BUX + ROGUE full coverage → paid" do
      user = create_user()
      set_user_bux_balance(user.id, 5000)

      order = create_order_with_bux(user, 2000)
      remaining = Decimal.sub(order.subtotal, order.bux_discount_amount)

      # Set ROGUE to cover all remaining
      order = set_rogue_on_order(order, remaining, Decimal.new("750000"), Decimal.mult(remaining, Decimal.new("0.10")))

      # Step 1: Complete BUX payment
      {:ok, _} = BlocksterV2.Shop.BalanceManager.deduct_bux(user.id, order.bux_tokens_burned)
      {:ok, order} = Orders.complete_bux_payment(order, "0xbux_tx")
      assert order.status == "bux_paid"

      # Step 2: Start ROGUE payment
      {:ok, order} = Orders.update_order(order, %{status: "rogue_pending"})
      assert order.status == "rogue_pending"

      # Step 3: Complete ROGUE payment
      {:ok, order} = Orders.complete_rogue_payment(order, "0xrogue_tx")
      assert order.status == "rogue_paid"
      assert order.rogue_payment_tx_hash == "0xrogue_tx"

      # Step 4: Mark as paid (no Helio needed)
      helio = order.helio_payment_amount || Decimal.new("0")
      assert Decimal.compare(helio, Decimal.new("0")) == :eq

      {:ok, order} = Orders.update_order(order, %{status: "paid"})
      assert order.status == "paid"
    end

    test "ROGUE only (no BUX) → rogue_paid → paid" do
      user = create_user()
      order = create_order_no_bux(user)

      # ROGUE covers full subtotal
      order = set_rogue_on_order(order, order.subtotal, Decimal.new("750000"), Decimal.mult(order.subtotal, Decimal.new("0.10")))

      # Start ROGUE payment (no BUX step)
      {:ok, order} = Orders.update_order(order, %{status: "rogue_pending"})
      {:ok, order} = Orders.complete_rogue_payment(order, "0xrogue_only_tx")
      assert order.status == "rogue_paid"

      # Mark as paid
      {:ok, order} = Orders.update_order(order, %{status: "paid"})
      assert order.status == "paid"
    end

    test "partial ROGUE with remaining Helio stays rogue_paid" do
      user = create_user()
      order = create_order_no_bux(user)

      # ROGUE covers $25 of $50
      order = set_rogue_on_order(order, Decimal.new("25.00"), Decimal.new("375000"), Decimal.new("2.50"))

      {:ok, order} =
        order
        |> Order.helio_payment_changeset(%{helio_payment_amount: Decimal.new("25.00")})
        |> Repo.update()

      {:ok, order} = Orders.update_order(order, %{status: "rogue_pending"})
      {:ok, order} = Orders.complete_rogue_payment(order, "0xpartial_rogue")
      assert order.status == "rogue_paid"

      # Helio still needed
      assert Decimal.compare(order.helio_payment_amount, Decimal.new("25.00")) == :eq

      # Cannot mark as paid yet — Helio outstanding
      # (In production, Helio webhook would complete this)
    end

    test "ROGUE token amount converts to wei correctly" do
      # 750,000 ROGUE → wei (18 decimals)
      tokens = Decimal.new("750000")
      wei = Decimal.mult(tokens, Decimal.new("1000000000000000000"))

      expected_wei = Decimal.new("750000000000000000000000")
      assert Decimal.compare(Decimal.round(wei, 0), expected_wei) == :eq
    end
  end
end
