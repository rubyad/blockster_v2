defmodule BlocksterV2.Shop.Phase5Test do
  use BlocksterV2.DataCase, async: false

  alias BlocksterV2.Cart, as: CartContext
  alias BlocksterV2.Orders
  alias BlocksterV2.Orders.Order
  alias BlocksterV2.Shop
  alias BlocksterV2.Accounts.User
  alias BlocksterV2.EngagementTracker

  # ============================================================================
  # Test Setup — ensure Mnesia table + BalanceManager running
  # ============================================================================

  setup do
    # Ensure Mnesia is started and user_bux_balances table exists
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

    # Also need user_rogue_balances — get_user_token_balances reads both tables
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

    # Start BalanceManager directly (not through GlobalSingleton for tests)
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
      price: Decimal.new("50.00"),
      title: "Default",
      inventory_quantity: 10,
      inventory_policy: "deny"
    }

    {:ok, variant} = Shop.create_variant(Map.merge(default_attrs, attrs))
    variant
  end

  defp create_order_with_bux(user, bux_tokens) do
    product = create_product()
    variant = create_variant(product, %{price: Decimal.new("100.00")})

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
    # Write directly to Mnesia table — must match all 15 attributes (16 elements with table name)
    # Attrs: user_id, user_smart_wallet, updated_at, aggregate_bux_balance,
    #   bux_balance, moonbux, neobux, roguebux, flarebux, nftbux, nolchabux, solbux, spacebux, tronbux, tranbux
    record = {
      :user_bux_balances, user_id, nil, System.system_time(:second),
      balance, balance, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    }

    :mnesia.dirty_write(:user_bux_balances, record)
  end

  # ============================================================================
  # BUX Deduction via BalanceManager
  # ============================================================================

  describe "BalanceManager.deduct_bux/2" do
    test "deducts BUX when balance is sufficient" do
      user = create_user()
      set_user_bux_balance(user.id, 5000)

      assert {:ok, new_balance} = BlocksterV2.Shop.BalanceManager.deduct_bux(user.id, 2000)
      assert new_balance == 3000
    end

    test "returns error when balance is insufficient" do
      user = create_user()
      set_user_bux_balance(user.id, 500)

      assert {:error, :insufficient, 500} = BlocksterV2.Shop.BalanceManager.deduct_bux(user.id, 2000)
    end

    test "deducts exact balance (edge case)" do
      user = create_user()
      set_user_bux_balance(user.id, 1000)

      assert {:ok, 0} = BlocksterV2.Shop.BalanceManager.deduct_bux(user.id, 1000)
    end

    test "returns error when balance is zero" do
      user = create_user()
      set_user_bux_balance(user.id, 0)

      assert {:error, :insufficient, 0} = BlocksterV2.Shop.BalanceManager.deduct_bux(user.id, 100)
    end
  end

  describe "BalanceManager.credit_bux/2" do
    test "credits BUX back to user" do
      user = create_user()
      set_user_bux_balance(user.id, 3000)

      # Deduct first
      {:ok, 1000} = BlocksterV2.Shop.BalanceManager.deduct_bux(user.id, 2000)

      # Credit back
      assert :ok = BlocksterV2.Shop.BalanceManager.credit_bux(user.id, 2000)

      # Balance should be restored
      assert EngagementTracker.get_user_bux_balance(user.id) == 3000
    end
  end

  # ============================================================================
  # Orders.complete_bux_payment/2
  # ============================================================================

  describe "Orders.complete_bux_payment/2" do
    test "updates order with tx hash and bux_paid status" do
      user = create_user()
      order = create_order_with_bux(user, 2000)

      assert order.status == "pending"
      assert order.bux_tokens_burned == 2000

      {:ok, updated} = Orders.complete_bux_payment(order, "0xabc123")

      assert updated.bux_burn_tx_hash == "0xabc123"
      assert updated.status == "bux_paid"
    end

    test "works with local reference tx hash" do
      user = create_user()
      order = create_order_with_bux(user, 500)

      {:ok, updated} = Orders.complete_bux_payment(order, "local-12345")

      assert updated.bux_burn_tx_hash == "local-12345"
      assert updated.status == "bux_paid"
    end
  end

  # ============================================================================
  # Order Status Transitions
  # ============================================================================

  describe "order status transitions" do
    test "pending -> bux_pending -> bux_paid" do
      user = create_user()
      order = create_order_with_bux(user, 1000)

      assert order.status == "pending"

      # Transition to bux_pending
      {:ok, order} = Orders.update_order(order, %{status: "bux_pending"})
      assert order.status == "bux_pending"

      # Transition to bux_paid
      {:ok, order} = Orders.complete_bux_payment(order, "0xtx123")
      assert order.status == "bux_paid"
    end

    test "bux_paid -> paid (when BUX covers everything)" do
      user = create_user()
      # Create order where BUX covers full price
      product = create_product(%{bux_max_discount: 100})
      variant = create_variant(product, %{price: Decimal.new("10.00")})

      {:ok, _} =
        CartContext.add_to_cart(user.id, product.id, %{
          variant_id: variant.id,
          quantity: 1,
          bux_tokens_to_redeem: 1000
        })

      cart = CartContext.get_or_create_cart(user.id)
      {:ok, order} = Orders.create_order_from_cart(cart, user)

      # BUX discount covers full subtotal
      assert Decimal.compare(order.bux_discount_amount, order.subtotal) == :eq

      # Mark bux_paid
      {:ok, order} = Orders.complete_bux_payment(order, "0xfull")
      assert order.status == "bux_paid"

      # Can transition to paid
      {:ok, order} = Orders.update_order(order, %{status: "paid"})
      assert order.status == "paid"
    end

    test "order with zero BUX stays in pending" do
      user = create_user()
      order = create_order_no_bux(user)

      assert order.status == "pending"
      assert order.bux_tokens_burned == 0
      assert Decimal.compare(order.bux_discount_amount, Decimal.new("0")) == :eq
    end
  end

  # ============================================================================
  # Insufficient Balance Handling
  # ============================================================================

  describe "insufficient BUX balance" do
    test "deduction fails when balance dropped below required amount" do
      user = create_user()
      order = create_order_with_bux(user, 3000)

      # User had enough BUX when adding to cart, but balance dropped
      set_user_bux_balance(user.id, 1000)

      # BalanceManager should reject
      assert {:error, :insufficient, 1000} = BlocksterV2.Shop.BalanceManager.deduct_bux(user.id, order.bux_tokens_burned)
    end

    test "balance is not deducted on failure" do
      user = create_user()
      set_user_bux_balance(user.id, 500)

      # Attempt deduction of more than available
      {:error, :insufficient, 500} = BlocksterV2.Shop.BalanceManager.deduct_bux(user.id, 2000)

      # Balance unchanged
      assert EngagementTracker.get_user_bux_balance(user.id) == 500
    end
  end

  # ============================================================================
  # BUX Payment Skip (amount = 0)
  # ============================================================================

  describe "skip BUX when amount is 0" do
    test "order with zero bux_tokens_burned has no BUX discount" do
      user = create_user()
      order = create_order_no_bux(user)

      assert order.bux_tokens_burned == 0
      assert Decimal.compare(order.bux_discount_amount, Decimal.new("0")) == :eq
      assert Decimal.compare(order.subtotal, Decimal.new("50.00")) == :eq
    end

    test "remaining_after_bux equals subtotal when no BUX" do
      user = create_user()
      order = create_order_no_bux(user)

      remaining = Decimal.sub(order.subtotal, order.bux_discount_amount)
      assert Decimal.compare(remaining, order.subtotal) == :eq
    end
  end

  # ============================================================================
  # BuxMinter.burn_bux/3 Function Exists
  # ============================================================================

  describe "BuxMinter.burn_bux/3" do
    test "function exists and is callable" do
      assert function_exported?(BlocksterV2.BuxMinter, :burn_bux, 3)
    end

    test "returns error when API secret not configured" do
      # In test env, API secret is not set
      result = BlocksterV2.BuxMinter.burn_bux("0xtest", 100, 1)
      assert {:error, _} = result
    end
  end

  # ============================================================================
  # Order.bux_payment_changeset/2 Validation
  # ============================================================================

  describe "Order.bux_payment_changeset/2" do
    test "requires bux_burn_tx_hash" do
      changeset = Order.bux_payment_changeset(%Order{}, %{status: "bux_paid"})
      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :bux_burn_tx_hash)
    end

    test "accepts valid bux payment data" do
      changeset =
        Order.bux_payment_changeset(%Order{}, %{
          bux_burn_tx_hash: "0xabc123",
          status: "bux_paid"
        })

      assert changeset.valid?
    end

    test "validates status inclusion" do
      changeset =
        Order.bux_payment_changeset(%Order{}, %{
          bux_burn_tx_hash: "0xabc",
          status: "invalid_status"
        })

      refute changeset.valid?
    end
  end

  # ============================================================================
  # Full BUX Payment Flow (Integration)
  # ============================================================================

  describe "full BUX payment flow" do
    test "deduct BUX -> complete order -> balance updated" do
      user = create_user()
      set_user_bux_balance(user.id, 5000)

      order = create_order_with_bux(user, 2000)
      assert order.bux_tokens_burned == 2000

      # Step 1: Deduct BUX
      {:ok, new_balance} = BlocksterV2.Shop.BalanceManager.deduct_bux(user.id, order.bux_tokens_burned)
      assert new_balance == 3000

      # Step 2: Update order status to bux_pending
      {:ok, order} = Orders.update_order(order, %{status: "bux_pending"})
      assert order.status == "bux_pending"

      # Step 3: Complete BUX payment with tx hash
      {:ok, order} = Orders.complete_bux_payment(order, "0xburn_tx_hash")
      assert order.status == "bux_paid"
      assert order.bux_burn_tx_hash == "0xburn_tx_hash"

      # Verify balance was deducted
      assert EngagementTracker.get_user_bux_balance(user.id) == 3000
    end

    test "failed BUX burn credits back balance" do
      user = create_user()
      set_user_bux_balance(user.id, 3000)

      order = create_order_with_bux(user, 1000)

      # Step 1: Deduct BUX
      {:ok, 2000} = BlocksterV2.Shop.BalanceManager.deduct_bux(user.id, 1000)

      # Step 2: Simulate burn failure — credit back
      :ok = BlocksterV2.Shop.BalanceManager.credit_bux(user.id, 1000)

      # Balance should be restored
      assert EngagementTracker.get_user_bux_balance(user.id) == 3000

      # Order stays in pending
      order = Orders.get_order(order.id)
      assert order.status == "pending"
    end

    test "100% BUX discount covers full subtotal" do
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

      # BUX discount equals subtotal — remaining is 0
      remaining = Decimal.sub(order.subtotal, order.bux_discount_amount)
      assert Decimal.compare(remaining, Decimal.new("0")) == :eq

      # Deduct and complete BUX payment
      {:ok, _} = BlocksterV2.Shop.BalanceManager.deduct_bux(user.id, order.bux_tokens_burned)
      {:ok, order} = Orders.complete_bux_payment(order, "0xfull_coverage")

      # Can mark as fully paid since no ROGUE/Helio needed
      {:ok, order} = Orders.update_order(order, %{status: "paid"})
      assert order.status == "paid"
    end

    test "serialized deduction prevents double-spend" do
      user = create_user()
      set_user_bux_balance(user.id, 3000)

      # Two orders trying to spend 2000 BUX each
      order1 = create_order_with_bux(user, 2000)
      # Create second cart item for second order
      :ok = CartContext.clear_cart(user.id)
      order2 = create_order_with_bux(user, 2000)

      # First deduction succeeds
      assert {:ok, 1000} = BlocksterV2.Shop.BalanceManager.deduct_bux(user.id, 2000)

      # Second deduction fails — insufficient (balance is 1000.0 float after Mnesia update)
      assert {:error, :insufficient, balance} = BlocksterV2.Shop.BalanceManager.deduct_bux(user.id, 2000)
      assert balance == 1000.0

      # Only first order can proceed
      {:ok, _} = Orders.complete_bux_payment(order1, "0xfirst")
      assert Orders.get_order(order2.id).status == "pending"
    end
  end
end
