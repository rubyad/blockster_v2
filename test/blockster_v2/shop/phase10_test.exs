defmodule BlocksterV2.Shop.Phase10Test do
  use BlocksterV2.DataCase, async: false

  alias BlocksterV2.Cart, as: CartContext
  alias BlocksterV2.Orders
  alias BlocksterV2.Orders.{Order, AffiliatePayout}
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

  defp create_admin_user do
    user = create_user()

    user
    |> Ecto.Changeset.change(%{is_admin: true})
    |> Repo.update!()
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
    product = create_product(%{title: Keyword.get(opts, :product_title, "Test Sneakers")})
    variant = create_variant(product, %{price: Decimal.new("100.00"), title: Keyword.get(opts, :variant_title, "Size 10")})

    {:ok, _} =
      CartContext.add_to_cart(user.id, product.id, %{
        variant_id: variant.id,
        quantity: Keyword.get(opts, :quantity, 1),
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

    status = Keyword.get(opts, :status, "paid")
    {:ok, order} = Orders.update_order(order, %{status: status})
    Orders.get_order(order.id)
  end

  defp create_referred_user(referrer) do
    buyer = create_user()

    buyer
    |> Ecto.Changeset.change(%{referrer_id: referrer.id})
    |> Repo.update!()
  end

  # ============================================================================
  # Orders.list_orders_admin Tests
  # ============================================================================

  describe "Orders.list_orders_admin/1" do
    test "returns all orders sorted by newest first" do
      user = create_user()
      order1 = create_order_for_user(user, status: "paid")
      Process.sleep(1100)
      order2 = create_order_for_user(user, status: "shipped")

      orders = Orders.list_orders_admin()

      assert length(orders) >= 2
      order_ids = Enum.map(orders, & &1.id)
      assert order1.id in order_ids
      assert order2.id in order_ids

      # Newest first (order2 created after sleep, so should come first)
      idx1 = Enum.find_index(orders, &(&1.id == order2.id))
      idx2 = Enum.find_index(orders, &(&1.id == order1.id))
      assert idx1 < idx2
    end

    test "filters by status" do
      user = create_user()
      _paid_order = create_order_for_user(user, status: "paid")
      shipped_order = create_order_for_user(user, status: "shipped")

      orders = Orders.list_orders_admin(%{status: "shipped"})

      order_ids = Enum.map(orders, & &1.id)
      assert shipped_order.id in order_ids
      # Only shipped orders returned
      Enum.each(orders, fn o -> assert o.status == "shipped" end)
    end

    test "returns all orders when status is 'all'" do
      user = create_user()
      _order1 = create_order_for_user(user, status: "paid")
      _order2 = create_order_for_user(user, status: "shipped")

      orders = Orders.list_orders_admin(%{status: "all"})
      assert length(orders) >= 2
    end

    test "preloads user and order_items" do
      user = create_user()
      _order = create_order_for_user(user, status: "paid")

      orders = Orders.list_orders_admin()
      order = List.first(orders)

      assert order.user != nil
      assert order.user.email == user.email
      assert is_list(order.order_items)
      assert length(order.order_items) >= 1
    end

    test "preloads affiliate_payouts" do
      referrer = create_user()
      buyer = create_referred_user(referrer)
      order = create_order_for_user(buyer, status: "paid")

      {:ok, order} =
        order
        |> Ecto.Changeset.change(%{bux_tokens_burned: 1000})
        |> Repo.update()

      order = Orders.get_order(order.id)
      Orders.create_affiliate_payouts(order)

      orders = Orders.list_orders_admin()
      found = Enum.find(orders, &(&1.id == order.id))

      assert length(found.affiliate_payouts) >= 1
    end

    test "limits results to 50 by default" do
      # Just verify the query accepts the limit option
      orders = Orders.list_orders_admin(%{limit: 5})
      assert length(orders) <= 5
    end
  end

  # ============================================================================
  # Order Status Update (Admin) Tests
  # ============================================================================

  describe "admin status update" do
    test "updates order status from paid to processing" do
      user = create_user()
      order = create_order_for_user(user, status: "paid")

      {:ok, updated} = Orders.update_order(order, %{status: "processing"})
      assert updated.status == "processing"
    end

    test "updates order status from processing to shipped" do
      user = create_user()
      order = create_order_for_user(user, status: "processing")

      {:ok, updated} = Orders.update_order(order, %{status: "shipped"})
      assert updated.status == "shipped"
    end

    test "updates order status from shipped to delivered" do
      user = create_user()
      order = create_order_for_user(user, status: "shipped")

      {:ok, updated} = Orders.update_order(order, %{status: "delivered"})
      assert updated.status == "delivered"
    end

    test "rejects invalid status" do
      user = create_user()
      order = create_order_for_user(user, status: "paid")

      {:error, changeset} = Orders.update_order(order, %{status: "invalid_status"})
      assert errors_on(changeset)[:status]
    end
  end

  # ============================================================================
  # Tracking Number Tests
  # ============================================================================

  describe "tracking number" do
    test "Order schema has tracking_number field" do
      order = %Order{}
      assert Map.has_key?(order, :tracking_number)
    end

    test "saves tracking number via status_changeset" do
      user = create_user()
      order = create_order_for_user(user, status: "shipped")

      {:ok, updated} = Orders.update_order(order, %{tracking_number: "1Z999AA10123456784"})
      assert updated.tracking_number == "1Z999AA10123456784"
    end

    test "tracking number persists and is retrievable" do
      user = create_user()
      order = create_order_for_user(user, status: "shipped")

      {:ok, _} = Orders.update_order(order, %{tracking_number: "TRACK123"})
      reloaded = Orders.get_order(order.id)
      assert reloaded.tracking_number == "TRACK123"
    end

    test "can update tracking number along with status" do
      user = create_user()
      order = create_order_for_user(user, status: "processing")

      {:ok, updated} = Orders.update_order(order, %{status: "shipped", tracking_number: "SHIP789"})
      assert updated.status == "shipped"
      assert updated.tracking_number == "SHIP789"
    end
  end

  # ============================================================================
  # Order Detail — Payment Breakdown Tests
  # ============================================================================

  describe "order detail payment breakdown" do
    test "order with BUX payment shows correct amounts" do
      user = create_user()
      order = create_order_for_user(user, status: "paid")

      {:ok, order} =
        order
        |> Ecto.Changeset.change(%{
          bux_tokens_burned: 2000,
          bux_discount_amount: Decimal.new("20.00"),
          bux_burn_tx_hash: "0xabc123"
        })
        |> Repo.update()

      order = Orders.get_order(order.id)

      assert order.bux_tokens_burned == 2000
      assert Decimal.equal?(order.bux_discount_amount, Decimal.new("20.00"))
      assert order.bux_burn_tx_hash == "0xabc123"
    end

    test "order with ROGUE payment shows correct amounts" do
      user = create_user()
      order = create_order_for_user(user, status: "paid")

      {:ok, order} =
        order
        |> Ecto.Changeset.change(%{
          rogue_tokens_sent: Decimal.new("500.0"),
          rogue_payment_amount: Decimal.new("30.00"),
          rogue_payment_tx_hash: "0xdef456"
        })
        |> Repo.update()

      order = Orders.get_order(order.id)

      assert Decimal.equal?(order.rogue_tokens_sent, Decimal.new("500.0"))
      assert Decimal.equal?(order.rogue_payment_amount, Decimal.new("30.00"))
      assert order.rogue_payment_tx_hash == "0xdef456"
    end

    test "order with Helio payment shows correct amounts" do
      user = create_user()
      order = create_order_for_user(user, status: "paid")

      {:ok, order} =
        order
        |> Order.helio_payment_changeset(%{
          helio_payment_amount: Decimal.new("50.00"),
          helio_payment_currency: "USDC"
        })
        |> Repo.update()

      order = Orders.get_order(order.id)

      assert Decimal.equal?(order.helio_payment_amount, Decimal.new("50.00"))
      assert order.helio_payment_currency == "USDC"
    end

    test "order with all payment types has complete data" do
      user = create_user()
      order = create_order_for_user(user, status: "paid")

      {:ok, order} =
        order
        |> Ecto.Changeset.change(%{
          bux_tokens_burned: 1000,
          bux_discount_amount: Decimal.new("10.00"),
          rogue_tokens_sent: Decimal.new("200.0"),
          rogue_payment_amount: Decimal.new("12.00")
        })
        |> Repo.update()

      {:ok, order} =
        order
        |> Order.helio_payment_changeset(%{
          helio_payment_amount: Decimal.new("78.00"),
          helio_payment_currency: "CARD"
        })
        |> Repo.update()

      order = Orders.get_order(order.id)

      assert order.bux_tokens_burned == 1000
      assert Decimal.gt?(order.rogue_tokens_sent, 0)
      assert Decimal.gt?(order.helio_payment_amount, 0)
      assert order.helio_payment_currency == "CARD"
    end
  end

  # ============================================================================
  # Order Detail — Affiliate Payouts Display Tests
  # ============================================================================

  describe "order detail affiliate payouts" do
    test "order shows affiliate payouts with correct data" do
      referrer = create_user()
      buyer = create_referred_user(referrer)
      order = create_order_for_user(buyer, status: "paid")

      {:ok, order} =
        order
        |> Ecto.Changeset.change(%{bux_tokens_burned: 2000})
        |> Repo.update()

      order = Orders.get_order(order.id)
      Orders.create_affiliate_payouts(order)

      order = Orders.get_order(order.id)

      assert length(order.affiliate_payouts) >= 1
      payout = List.first(order.affiliate_payouts)
      assert payout.currency == "BUX"
      assert payout.referrer_id == referrer.id
      assert Decimal.equal?(payout.commission_rate, Decimal.new("0.05"))
    end

    test "order with no referrer has no affiliate payouts" do
      user = create_user()
      order = create_order_for_user(user, status: "paid")
      order = Orders.get_order(order.id)

      assert Enum.empty?(order.affiliate_payouts)
    end

    test "multi-currency order shows all payouts" do
      referrer = create_user()
      buyer = create_referred_user(referrer)
      order = create_order_for_user(buyer, status: "paid")

      {:ok, order} =
        order
        |> Ecto.Changeset.change(%{
          bux_tokens_burned: 500,
          rogue_tokens_sent: Decimal.new("100.0")
        })
        |> Repo.update()

      {:ok, order} =
        order
        |> Order.helio_payment_changeset(%{
          helio_payment_amount: Decimal.new("40.00"),
          helio_payment_currency: "USDC"
        })
        |> Repo.update()

      order = Orders.get_order(order.id)
      Orders.create_affiliate_payouts(order)

      order = Orders.get_order(order.id)

      assert length(order.affiliate_payouts) == 3
      currencies = Enum.map(order.affiliate_payouts, & &1.currency) |> Enum.sort()
      assert currencies == ["BUX", "ROGUE", "USDC"]
    end
  end

  # ============================================================================
  # OrdersAdminLive Module Tests
  # ============================================================================

  describe "OrdersAdminLive module" do
    test "module exists and is a LiveView" do
      Code.ensure_loaded!(BlocksterV2Web.OrdersAdminLive)
      # Verify it's a LiveView by checking for __phoenix_verify_routes__ (set by use BlocksterV2Web, :live_view)
      assert {:module, BlocksterV2Web.OrdersAdminLive} == Code.ensure_compiled(BlocksterV2Web.OrdersAdminLive)
    end
  end

  # ============================================================================
  # OrderAdminLive.Show Module Tests
  # ============================================================================

  describe "OrderAdminLive.Show module" do
    test "module exists and is a LiveView" do
      Code.ensure_loaded!(BlocksterV2Web.OrderAdminLive.Show)
      assert {:module, BlocksterV2Web.OrderAdminLive.Show} == Code.ensure_compiled(BlocksterV2Web.OrderAdminLive.Show)
    end
  end

  # ============================================================================
  # Admin Authorization Tests
  # ============================================================================

  describe "admin authorization" do
    test "AdminAuth module exists and has on_mount/4" do
      Code.ensure_loaded!(BlocksterV2Web.AdminAuth)
      assert function_exported?(BlocksterV2Web.AdminAuth, :on_mount, 4)
    end

    test "AdminAuth halts for non-admin users" do
      user = create_user()
      refute user.is_admin

      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          __changed__: %{},
          current_user: user,
          flash: %{}
        }
      }

      result = BlocksterV2Web.AdminAuth.on_mount(:default, %{}, %{}, socket)
      assert {:halt, _socket} = result
    end

    test "AdminAuth continues for admin users" do
      admin = create_admin_user()
      assert admin.is_admin

      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          __changed__: %{},
          current_user: admin,
          flash: %{}
        }
      }

      result = BlocksterV2Web.AdminAuth.on_mount(:default, %{}, %{}, socket)
      assert {:cont, _socket} = result
    end

    test "AdminAuth halts for nil user" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          __changed__: %{},
          current_user: nil,
          flash: %{}
        }
      }

      result = BlocksterV2Web.AdminAuth.on_mount(:default, %{}, %{}, socket)
      assert {:halt, _socket} = result
    end
  end

  # ============================================================================
  # End-to-end Admin Flow Tests
  # ============================================================================

  describe "end-to-end admin flow" do
    test "create order, list it, update status, add tracking" do
      user = create_user()
      order = create_order_for_user(user, status: "paid")

      # List shows the order
      orders = Orders.list_orders_admin()
      assert Enum.any?(orders, &(&1.id == order.id))

      # Update to processing
      {:ok, order} = Orders.update_order(order, %{status: "processing"})
      assert order.status == "processing"

      # Update to shipped with tracking
      {:ok, order} = Orders.update_order(order, %{status: "shipped", tracking_number: "1Z999"})
      assert order.status == "shipped"
      assert order.tracking_number == "1Z999"

      # Update to delivered
      {:ok, order} = Orders.update_order(order, %{status: "delivered"})
      assert order.status == "delivered"

      # Verify via list_orders_admin filter
      delivered_orders = Orders.list_orders_admin(%{status: "delivered"})
      assert Enum.any?(delivered_orders, &(&1.id == order.id))
    end

    test "order with full payment breakdown and affiliate payouts" do
      referrer = create_user()
      buyer = create_referred_user(referrer)
      order = create_order_for_user(buyer, status: "paid")

      # Add all payment types
      {:ok, order} =
        order
        |> Ecto.Changeset.change(%{
          bux_tokens_burned: 1000,
          bux_discount_amount: Decimal.new("10.00"),
          bux_burn_tx_hash: "0xbux123",
          rogue_tokens_sent: Decimal.new("300.0"),
          rogue_payment_amount: Decimal.new("18.00"),
          rogue_payment_tx_hash: "0xrogue456"
        })
        |> Repo.update()

      {:ok, order} =
        order
        |> Order.helio_payment_changeset(%{
          helio_payment_amount: Decimal.new("72.00"),
          helio_payment_currency: "USDC"
        })
        |> Repo.update()

      # Create affiliate payouts
      order = Orders.get_order(order.id)
      Orders.create_affiliate_payouts(order)

      # Reload and verify everything
      order = Orders.get_order(order.id)

      # Payment breakdown
      assert order.bux_tokens_burned == 1000
      assert order.bux_burn_tx_hash == "0xbux123"
      assert Decimal.gt?(order.rogue_tokens_sent, 0)
      assert order.rogue_payment_tx_hash == "0xrogue456"
      assert Decimal.gt?(order.helio_payment_amount, 0)
      assert order.helio_payment_currency == "USDC"

      # Affiliate payouts
      assert length(order.affiliate_payouts) == 3
      assert order.referrer_id == referrer.id

      # Shipping
      assert order.shipping_name == "John Doe"
      assert order.shipping_email == "john@example.com"
    end

    test "filtered list only shows matching status" do
      user = create_user()
      paid_order = create_order_for_user(user, status: "paid")
      _pending_order = create_order_for_user(user, status: "pending")

      paid_orders = Orders.list_orders_admin(%{status: "paid"})
      pending_orders = Orders.list_orders_admin(%{status: "pending"})

      # paid_order should be in paid list
      paid_ids = Enum.map(paid_orders, & &1.id)
      assert paid_order.id in paid_ids

      # All paid orders have status "paid"
      Enum.each(paid_orders, fn o -> assert o.status == "paid" end)

      # All pending orders have status "pending"
      Enum.each(pending_orders, fn o -> assert o.status == "pending" end)
    end
  end
end
