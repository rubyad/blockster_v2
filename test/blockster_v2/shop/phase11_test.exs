defmodule BlocksterV2.Shop.Phase11Test do
  use BlocksterV2.DataCase, async: false

  alias BlocksterV2.Cart, as: CartContext
  alias BlocksterV2.Orders
  alias BlocksterV2.Orders.{Order, OrderExpiryWorker}
  alias BlocksterV2.Shop
  alias BlocksterV2.Accounts.User

  # ============================================================================
  # Test Setup — ensure Mnesia tables + BalanceManager running
  # ============================================================================

  setup do
    :mnesia.start()

    bux_attrs = [
      :user_id, :user_smart_wallet, :updated_at, :aggregate_bux_balance,
      :bux_balance, :moonbux_balance, :neobux_balance, :roguebux_balance,
      :flarebux_balance, :nftbux_balance, :nolchabux_balance, :solbux_balance,
      :spacebux_balance, :tronbux_balance, :tranbux_balance
    ]

    create_or_clear_table(:user_bux_balances, bux_attrs, :set)

    create_or_clear_table(:user_rogue_balances,
      [:user_id, :user_smart_wallet, :updated_at, :rogue_balance_rogue_chain, :rogue_balance_arbitrum],
      :set
    )

    create_or_clear_table(:referral_earnings,
      [:id, :referrer_id, :referrer_wallet, :referee_wallet, :earning_type, :amount, :token, :tx_hash, :commitment_hash, :timestamp],
      :bag,
      [:referrer_id, :referrer_wallet, :referee_wallet, :commitment_hash]
    )

    create_or_clear_table(:referral_stats,
      [:user_id, :total_referrals, :verified_referrals, :total_bux_earned, :total_rogue_earned, :updated_at],
      :set
    )

    create_or_clear_table(:referrals,
      [:user_id, :referrer_id, :referrer_wallet, :referee_wallet, :referred_at, :on_chain_synced],
      :set,
      [:referrer_id, :referrer_wallet, :referee_wallet]
    )

    case GenServer.start_link(BlocksterV2.Shop.BalanceManager, %{}, name: {:global, BlocksterV2.Shop.BalanceManager}) do
      {:ok, pid} -> on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
      {:error, {:already_started, _}} -> :ok
    end

    :ok
  end

  defp create_or_clear_table(name, attrs, type, indices \\ []) do
    case :mnesia.create_table(name, [
           attributes: attrs,
           ram_copies: [node()],
           type: type,
           index: indices
         ]) do
      {:atomic, :ok} -> :ok
      {:aborted, {:already_exists, ^name}} ->
        case :mnesia.add_table_copy(name, node(), :ram_copies) do
          {:atomic, :ok} -> :ok
          {:aborted, {:already_exists, ^name, _}} -> :ok
        end
        :mnesia.clear_table(name)
    end
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

  defp create_order_for_user(user, opts \\ []) do
    product = create_product()
    variant = create_variant(product, %{price: Decimal.new("100.00"), title: "Size 10"})

    {:ok, _} =
      CartContext.add_to_cart(user.id, product.id, %{
        variant_id: variant.id,
        quantity: 1,
        bux_tokens_to_redeem: 0
      })

    cart = CartContext.get_or_create_cart(user.id)
    {:ok, order} = Orders.create_order_from_cart(cart, user)

    {:ok, order} =
      Orders.update_order_shipping(order, %{
        shipping_name: "John Doe",
        shipping_email: "john@example.com",
        shipping_address_line1: "123 Main St",
        shipping_city: "New York",
        shipping_state: "NY",
        shipping_postal_code: "10001",
        shipping_country: "US"
      })

    status = Keyword.get(opts, :status, "pending")

    if status != "pending" do
      {:ok, order} = Orders.update_order(order, %{status: status})
      Orders.get_order(order.id)
    else
      Orders.get_order(order.id)
    end
  end

  defp make_order_old(order, minutes_ago) do
    past = DateTime.add(DateTime.utc_now(), -minutes_ago, :minute) |> DateTime.truncate(:second)

    from(o in Order, where: o.id == ^order.id)
    |> Repo.update_all(set: [inserted_at: past])

    Orders.get_order(order.id)
  end

  # ============================================================================
  # OrderExpiryWorker Tests
  # ============================================================================

  describe "OrderExpiryWorker" do
    test "expires stale pending orders" do
      user = create_user()
      order = create_order_for_user(user, status: "pending")
      _order = make_order_old(order, 35)

      count = OrderExpiryWorker.expire_stale_orders()

      assert count >= 1
      reloaded = Orders.get_order(order.id)
      assert reloaded.status == "expired"
      assert reloaded.notes =~ "Auto-expired after 30 minutes"
    end

    test "expires stale bux_pending orders" do
      user = create_user()
      order = create_order_for_user(user, status: "bux_pending")
      _order = make_order_old(order, 35)

      OrderExpiryWorker.expire_stale_orders()

      reloaded = Orders.get_order(order.id)
      assert reloaded.status == "expired"
      assert reloaded.notes =~ "Auto-expired after 30 minutes"
    end

    test "expires stale rogue_pending orders" do
      user = create_user()
      order = create_order_for_user(user, status: "rogue_pending")
      _order = make_order_old(order, 35)

      OrderExpiryWorker.expire_stale_orders()

      reloaded = Orders.get_order(order.id)
      assert reloaded.status == "expired"
      assert reloaded.notes =~ "Auto-expired after 30 minutes"
    end

    test "flags bux_paid orders for manual review" do
      user = create_user()
      order = create_order_for_user(user, status: "bux_paid")
      _order = make_order_old(order, 35)

      OrderExpiryWorker.expire_stale_orders()

      reloaded = Orders.get_order(order.id)
      assert reloaded.status == "expired"
      assert reloaded.notes =~ "Partial payment received"
      assert reloaded.notes =~ "review for refund"
    end

    test "flags rogue_paid orders for manual review" do
      user = create_user()
      order = create_order_for_user(user, status: "rogue_paid")
      _order = make_order_old(order, 35)

      OrderExpiryWorker.expire_stale_orders()

      reloaded = Orders.get_order(order.id)
      assert reloaded.status == "expired"
      assert reloaded.notes =~ "Partial payment received"
      assert reloaded.notes =~ "review for refund"
    end

    test "does not expire paid orders" do
      user = create_user()
      order = create_order_for_user(user, status: "paid")
      _order = make_order_old(order, 60)

      OrderExpiryWorker.expire_stale_orders()

      reloaded = Orders.get_order(order.id)
      assert reloaded.status == "paid"
    end

    test "does not expire shipped orders" do
      user = create_user()
      order = create_order_for_user(user, status: "shipped")
      _order = make_order_old(order, 60)

      OrderExpiryWorker.expire_stale_orders()

      reloaded = Orders.get_order(order.id)
      assert reloaded.status == "shipped"
    end

    test "does not expire delivered orders" do
      user = create_user()
      order = create_order_for_user(user, status: "delivered")
      _order = make_order_old(order, 60)

      OrderExpiryWorker.expire_stale_orders()

      reloaded = Orders.get_order(order.id)
      assert reloaded.status == "delivered"
    end

    test "does not expire recent pending orders (under 30 min)" do
      user = create_user()
      order = create_order_for_user(user, status: "pending")

      OrderExpiryWorker.expire_stale_orders()

      reloaded = Orders.get_order(order.id)
      assert reloaded.status == "pending"
    end

    test "OrderExpiryWorker module exists" do
      assert {:module, BlocksterV2.Orders.OrderExpiryWorker} ==
               Code.ensure_compiled(BlocksterV2.Orders.OrderExpiryWorker)
    end
  end

  # ============================================================================
  # Cart Clearing After Payment Tests
  # ============================================================================

  describe "cart clearing after payment" do
    test "process_paid_order clears the user's cart" do
      user = create_user()
      product = create_product()
      variant = create_variant(product)

      # Add items to cart
      {:ok, _} = CartContext.add_to_cart(user.id, product.id, %{variant_id: variant.id, quantity: 2})
      assert CartContext.item_count(user.id) == 2

      # Create and pay for an order
      order = create_order_for_user(user, status: "paid")
      Orders.process_paid_order(order)

      # Cart should be empty
      assert CartContext.item_count(user.id) == 0
    end

    test "process_paid_order works when user has no cart" do
      user = create_user()
      order = create_order_for_user(user, status: "paid")

      # Should not crash even without a cart
      assert :ok == Orders.process_paid_order(order)
    end

    test "cart badge updates after payment" do
      user = create_user()
      product = create_product()
      variant = create_variant(product)

      {:ok, _} = CartContext.add_to_cart(user.id, product.id, %{variant_id: variant.id, quantity: 1})

      # Subscribe to cart updates
      Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "cart:#{user.id}")

      order = create_order_for_user(user, status: "paid")
      Orders.process_paid_order(order)

      # Should receive a cart_updated broadcast with count 0
      assert_receive {:cart_updated, 0}, 1000
    end

    test "clear_cart only affects the paying user" do
      user1 = create_user()
      user2 = create_user()
      product = create_product()
      variant = create_variant(product)

      {:ok, _} = CartContext.add_to_cart(user1.id, product.id, %{variant_id: variant.id, quantity: 1})
      {:ok, _} = CartContext.add_to_cart(user2.id, product.id, %{variant_id: variant.id, quantity: 3})

      order = create_order_for_user(user1, status: "paid")
      Orders.process_paid_order(order)

      # User1's cart cleared, user2's cart untouched
      assert CartContext.item_count(user1.id) == 0
      assert CartContext.item_count(user2.id) == 3
    end
  end

  # ============================================================================
  # Checkout Rate Limiting Tests
  # ============================================================================

  describe "checkout rate limiting" do
    test "recent_order_count returns 0 for user with no orders" do
      user = create_user()
      assert Orders.recent_order_count(user.id) == 0
    end

    test "recent_order_count counts orders in the last hour" do
      user = create_user()
      _order1 = create_order_for_user(user)
      _order2 = create_order_for_user(user)

      assert Orders.recent_order_count(user.id) == 2
    end

    test "recent_order_count ignores old orders" do
      user = create_user()
      order = create_order_for_user(user)
      make_order_old(order, 120)

      assert Orders.recent_order_count(user.id) == 0
    end

    test "check_rate_limit allows under limit" do
      user = create_user()
      _order1 = create_order_for_user(user)
      _order2 = create_order_for_user(user)

      assert :ok == Orders.check_rate_limit(user.id)
    end

    test "check_rate_limit blocks at limit" do
      user = create_user()

      Enum.each(1..20, fn _ ->
        create_order_for_user(user)
      end)

      assert {:error, :rate_limited} == Orders.check_rate_limit(user.id)
    end

    test "check_rate_limit allows again after old orders expire" do
      user = create_user()

      Enum.each(1..20, fn _ ->
        order = create_order_for_user(user)
        make_order_old(order, 65)
      end)

      assert :ok == Orders.check_rate_limit(user.id)
    end

    test "rate limit is per-user" do
      user1 = create_user()
      user2 = create_user()

      Enum.each(1..20, fn _ ->
        create_order_for_user(user1)
      end)

      assert {:error, :rate_limited} == Orders.check_rate_limit(user1.id)
      assert :ok == Orders.check_rate_limit(user2.id)
    end

    test "recent_order_count accepts custom minutes parameter" do
      user = create_user()
      order = create_order_for_user(user)
      make_order_old(order, 10)

      # Within 15 minutes: should count
      assert Orders.recent_order_count(user.id, 15) == 1
      # Within 5 minutes: should not count
      assert Orders.recent_order_count(user.id, 5) == 0
    end
  end

  # ============================================================================
  # Integration Tests
  # ============================================================================

  describe "end-to-end Phase 11 integration" do
    test "expired order cannot be checked out again" do
      user = create_user()
      order = create_order_for_user(user, status: "pending")
      make_order_old(order, 35)

      OrderExpiryWorker.expire_stale_orders()

      reloaded = Orders.get_order(order.id)
      assert reloaded.status == "expired"

      # Trying to update an expired order's status should still work (admin can change)
      {:ok, updated} = Orders.update_order(reloaded, %{status: "cancelled"})
      assert updated.status == "cancelled"
    end

    test "multiple stale orders of different statuses are all expired" do
      user = create_user()

      pending_order = create_order_for_user(user, status: "pending")
      make_order_old(pending_order, 40)

      bux_paid_order = create_order_for_user(user, status: "bux_paid")
      make_order_old(bux_paid_order, 40)

      paid_order = create_order_for_user(user, status: "paid")
      make_order_old(paid_order, 40)

      count = OrderExpiryWorker.expire_stale_orders()
      assert count >= 2

      assert Orders.get_order(pending_order.id).status == "expired"
      assert Orders.get_order(bux_paid_order.id).status == "expired"
      # Paid order should NOT be expired
      assert Orders.get_order(paid_order.id).status == "paid"
    end

    test "full lifecycle: create order, expire it, rate limit respected" do
      user = create_user()

      # Create 20 orders (hitting the rate limit)
      orders = Enum.map(1..20, fn _ -> create_order_for_user(user) end)

      # Rate limited
      assert {:error, :rate_limited} == Orders.check_rate_limit(user.id)

      # Expire all orders (make them old enough for both expiry and rate limit window)
      Enum.each(orders, &make_order_old(&1, 65))
      OrderExpiryWorker.expire_stale_orders()

      # All expired
      Enum.each(orders, fn o ->
        assert Orders.get_order(o.id).status == "expired"
      end)

      # Orders are now older than 60 min, so they no longer count against rate limit
      assert :ok == Orders.check_rate_limit(user.id)
    end
  end
end
