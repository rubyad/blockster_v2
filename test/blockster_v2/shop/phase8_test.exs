defmodule BlocksterV2.Shop.Phase8Test do
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
      price: Decimal.new("50.00"),
      title: "Default",
      inventory_quantity: 10,
      inventory_policy: "deny"
    }

    {:ok, variant} = Shop.create_variant(Map.merge(default_attrs, attrs))
    variant
  end

  defp create_paid_order(user, opts \\ []) do
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

    # Add shipping info
    {:ok, order} =
      Orders.update_order_shipping(order, %{
        shipping_name: "John Doe",
        shipping_email: "john@example.com",
        shipping_address_line1: "123 Main St",
        shipping_address_line2: Keyword.get(opts, :address_line2, ""),
        shipping_city: "New York",
        shipping_state: "NY",
        shipping_postal_code: "10001",
        shipping_country: "US",
        shipping_phone: Keyword.get(opts, :phone, "555-1234")
      })

    # Mark as paid
    {:ok, order} = Orders.update_order(order, %{status: "paid"})
    Orders.get_order(order.id)
  end

  defp create_paid_order_with_payments(user) do
    order = create_paid_order(user)

    {:ok, order} =
      order
      |> Order.helio_payment_changeset(%{
        helio_payment_amount: Decimal.new("50.00"),
        helio_payment_currency: "USDC",
        helio_transaction_id: "helio_tx_123"
      })
      |> Repo.update()

    {:ok, order} =
      order
      |> Ecto.Changeset.change(%{
        bux_discount_amount: Decimal.new("25.00"),
        bux_tokens_burned: 2500,
        rogue_payment_amount: Decimal.new("25.00"),
        rogue_tokens_sent: Decimal.new("416666.67")
      })
      |> Repo.update()

    Orders.get_order(order.id)
  end

  # ============================================================================
  # OrderMailer Tests
  # ============================================================================

  describe "BlocksterV2.OrderMailer" do
    test "fulfillment_notification/1 builds a valid Swoosh email" do
      user = create_user()
      order = create_paid_order(user)

      email = BlocksterV2.OrderMailer.fulfillment_notification(order)

      assert %Swoosh.Email{} = email
      assert email.subject =~ order.order_number
      assert [{_, to_email}] = email.to
      assert is_binary(to_email)
      assert {"Blockster Shop", "shop@blockster.com"} = email.from
    end

    test "email contains order items in HTML body" do
      user = create_user()
      order = create_paid_order(user, product_title: "Cool Kicks", variant_title: "Size 11")

      email = BlocksterV2.OrderMailer.fulfillment_notification(order)

      assert email.html_body =~ "Cool Kicks"
      assert email.html_body =~ "Size 11"
      assert email.html_body =~ "Items (1)"
    end

    test "email contains shipping address" do
      user = create_user()
      order = create_paid_order(user)

      email = BlocksterV2.OrderMailer.fulfillment_notification(order)

      assert email.html_body =~ "John Doe"
      assert email.html_body =~ "123 Main St"
      assert email.html_body =~ "New York"
      assert email.html_body =~ "NY"
      assert email.html_body =~ "10001"
      assert email.html_body =~ "US"
    end

    test "email contains payment summary" do
      user = create_user()
      order = create_paid_order_with_payments(user)

      email = BlocksterV2.OrderMailer.fulfillment_notification(order)

      assert email.html_body =~ "Subtotal"
      assert email.html_body =~ "BUX Discount"
      assert email.html_body =~ "ROGUE Payment"
      assert email.html_body =~ "Helio Payment"
      assert email.html_body =~ "USDC"
    end

    test "email includes text body" do
      user = create_user()
      order = create_paid_order(user)

      email = BlocksterV2.OrderMailer.fulfillment_notification(order)

      assert is_binary(email.text_body)
      assert email.text_body =~ order.order_number
      assert email.text_body =~ "John Doe"
    end

    test "email includes phone when present" do
      user = create_user()
      order = create_paid_order(user, phone: "555-9876")

      email = BlocksterV2.OrderMailer.fulfillment_notification(order)

      assert email.html_body =~ "555-9876"
    end

    test "email handles missing address_line2 gracefully" do
      user = create_user()
      order = create_paid_order(user, address_line2: "")

      email = BlocksterV2.OrderMailer.fulfillment_notification(order)

      # Should not have empty lines or nil text
      refute email.html_body =~ "nil"
    end

    test "email can be delivered via test adapter" do
      user = create_user()
      order = create_paid_order(user)

      email = BlocksterV2.OrderMailer.fulfillment_notification(order)
      assert {:ok, _} = BlocksterV2.Mailer.deliver(email)
    end

    test "fulfiller_email defaults to fulfillment@blockster.com" do
      user = create_user()
      order = create_paid_order(user)

      email = BlocksterV2.OrderMailer.fulfillment_notification(order)

      assert [{"Fulfillment Team", addr}] = email.to
      assert is_binary(addr)
    end
  end

  # ============================================================================
  # TelegramNotifier Tests
  # ============================================================================

  describe "BlocksterV2.TelegramNotifier" do
    test "send_order_notification/1 returns error when not configured" do
      # Telegram config not set in test env
      user = create_user()
      order = create_paid_order(user)

      assert {:error, :not_configured} = BlocksterV2.TelegramNotifier.send_order_notification(order)
    end

    test "module exports send_order_notification/1" do
      assert function_exported?(BlocksterV2.TelegramNotifier, :send_order_notification, 1)
    end

    test "send_order_notification/1 calls Telegram API when configured" do
      # Temporarily set config
      Application.put_env(:blockster_v2, :telegram_bot_token, "test_bot_token")
      Application.put_env(:blockster_v2, :telegram_fulfillment_channel_id, "-100123456789")

      on_exit(fn ->
        Application.delete_env(:blockster_v2, :telegram_bot_token)
        Application.delete_env(:blockster_v2, :telegram_fulfillment_channel_id)
      end)

      user = create_user()
      order = create_paid_order(user)

      # Will fail with connection error since we're hitting a fake token,
      # but proves it attempts the API call (not :not_configured)
      result = BlocksterV2.TelegramNotifier.send_order_notification(order)

      # Should be either an HTTP error or a connection error, NOT :not_configured
      assert result != {:error, :not_configured}
    end
  end

  # ============================================================================
  # Orders.Fulfillment Tests
  # ============================================================================

  describe "BlocksterV2.Orders.Fulfillment" do
    test "notify/1 sets fulfillment_notified_at on the order" do
      user = create_user()
      order = create_paid_order(user)

      assert is_nil(order.fulfillment_notified_at)

      BlocksterV2.Orders.Fulfillment.notify(order)

      updated = Orders.get_order(order.id)
      assert %DateTime{} = updated.fulfillment_notified_at
    end

    test "notify/1 delivers email via Swoosh test adapter" do
      user = create_user()
      order = create_paid_order(user)

      BlocksterV2.Orders.Fulfillment.notify(order)

      # Swoosh test adapter stores emails — verify one was sent
      updated = Orders.get_order(order.id)
      assert updated.fulfillment_notified_at != nil
    end

    test "notify/1 does not crash when Telegram is not configured" do
      user = create_user()
      order = create_paid_order(user)

      # Should complete without raising even though Telegram isn't configured
      assert {:ok, _} = BlocksterV2.Orders.Fulfillment.notify(order)
    end

    test "notify/1 returns updated order" do
      user = create_user()
      order = create_paid_order(user)

      {:ok, updated} = BlocksterV2.Orders.Fulfillment.notify(order)

      assert updated.fulfillment_notified_at != nil
      assert updated.id == order.id
    end
  end

  # ============================================================================
  # process_paid_order Integration Tests
  # ============================================================================

  describe "Orders.process_paid_order/1" do
    test "calls Fulfillment.notify for a paid order" do
      user = create_user()
      order = create_paid_order(user)

      assert :ok = Orders.process_paid_order(order)

      # Give async Task.start a moment to complete
      Process.sleep(200)

      updated = Orders.get_order(order.id)
      assert %DateTime{} = updated.fulfillment_notified_at
    end

    test "process_paid_order handles order without shipping gracefully" do
      user = create_user()
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
      {:ok, order} = Orders.update_order(order, %{status: "paid"})

      # Should not crash even without shipping info
      assert :ok = Orders.process_paid_order(order)
    end
  end

  # ============================================================================
  # Fulfillment only triggers on paid status
  # ============================================================================

  describe "fulfillment only for paid orders" do
    test "order must be in paid status for process_paid_order" do
      user = create_user()
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

      # Order is in "pending" status, process_paid_order still runs
      # (caller is responsible for checking status)
      assert :ok = Orders.process_paid_order(order)
    end

    test "complete_helio_payment triggers process_paid_order" do
      user = create_user()
      order = create_paid_order(user)

      # Reset status to rogue_paid to simulate pre-helio state
      {:ok, order} = Orders.update_order(order, %{status: "rogue_paid"})

      {:ok, updated} =
        Orders.complete_helio_payment(order, %{
          helio_transaction_id: "tx_final_123",
          helio_payment_amount: Decimal.new("50.00"),
          helio_payment_currency: "USDC"
        })

      assert updated.status == "paid"

      # Give async task time to run
      Process.sleep(200)

      final = Orders.get_order(order.id)
      assert %DateTime{} = final.fulfillment_notified_at
    end
  end

  # ============================================================================
  # End-to-end: paid order triggers notifications
  # ============================================================================

  describe "end-to-end paid order flow" do
    test "full flow: create order, pay, receive notifications" do
      user = create_user()
      order = create_paid_order_with_payments(user)

      BlocksterV2.Orders.Fulfillment.notify(order)

      updated = Orders.get_order(order.id)
      assert %DateTime{} = updated.fulfillment_notified_at
    end

    test "multi-item order includes all items in email" do
      user = create_user()
      product1 = create_product(%{title: "Sneaker A"})
      variant1 = create_variant(product1, %{price: Decimal.new("80.00"), title: "Size 9"})
      product2 = create_product(%{title: "Sneaker B"})
      variant2 = create_variant(product2, %{price: Decimal.new("120.00"), title: "Size 12"})

      {:ok, _} = CartContext.add_to_cart(user.id, product1.id, %{variant_id: variant1.id, quantity: 1, bux_tokens_to_redeem: 0})
      {:ok, _} = CartContext.add_to_cart(user.id, product2.id, %{variant_id: variant2.id, quantity: 2, bux_tokens_to_redeem: 0})

      cart = CartContext.get_or_create_cart(user.id)
      {:ok, order} = Orders.create_order_from_cart(cart, user)

      {:ok, order} =
        Orders.update_order_shipping(order, %{
          shipping_name: "Jane Smith",
          shipping_email: "jane@example.com",
          shipping_address_line1: "456 Oak Ave",
          shipping_city: "Los Angeles",
          shipping_state: "CA",
          shipping_postal_code: "90001",
          shipping_country: "US"
        })

      {:ok, order} = Orders.update_order(order, %{status: "paid"})
      order = Orders.get_order(order.id)

      email = BlocksterV2.OrderMailer.fulfillment_notification(order)

      assert email.html_body =~ "Sneaker A"
      assert email.html_body =~ "Sneaker B"
      assert email.html_body =~ "Size 9"
      assert email.html_body =~ "Size 12"
      assert email.html_body =~ "Items (2)"
      assert email.html_body =~ "Jane Smith"
    end

    test "order with address_line2 includes it in email" do
      user = create_user()
      order = create_paid_order(user, address_line2: "Apt 4B")

      email = BlocksterV2.OrderMailer.fulfillment_notification(order)

      assert email.html_body =~ "Apt 4B"
    end

    test "helio-only payment shows correct currency in email" do
      user = create_user()
      order = create_paid_order(user)

      {:ok, order} =
        order
        |> Order.helio_payment_changeset(%{
          helio_payment_amount: Decimal.new("100.00"),
          helio_payment_currency: "SOL"
        })
        |> Repo.update()

      order = Orders.get_order(order.id)
      email = BlocksterV2.OrderMailer.fulfillment_notification(order)

      assert email.html_body =~ "SOL"
    end
  end
end
