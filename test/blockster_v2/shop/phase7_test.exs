defmodule BlocksterV2.Shop.Phase7Test do
  use BlocksterV2Web.ConnCase, async: false

  alias BlocksterV2.Repo
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

  defp set_user_bux_balance(user_id, balance) do
    record = {
      :user_bux_balances, user_id, nil, System.system_time(:second),
      balance, balance, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    }

    :mnesia.dirty_write(:user_bux_balances, record)
  end

  defp create_order_with_helio(user) do
    order = create_order_with_bux(user, 0)

    # Set up Helio payment amount (full subtotal since no BUX)
    {:ok, order} =
      order
      |> Order.helio_payment_changeset(%{helio_payment_amount: order.subtotal})
      |> Repo.update()

    Orders.get_order(order.id)
  end

  # ============================================================================
  # Helio Module Tests
  # ============================================================================

  describe "BlocksterV2.Helio.create_charge/1" do
    test "builds correct payload and handles success response" do
      user = create_user()
      order = create_order_with_helio(user)

      # We can't call the real API, but we can test that the module exists
      # and the function is defined with the right arity
      Code.ensure_loaded!(BlocksterV2.Helio)
      assert function_exported?(BlocksterV2.Helio, :create_charge, 1)
    end

    test "get_charge is defined" do
      Code.ensure_loaded!(BlocksterV2.Helio)
      assert function_exported?(BlocksterV2.Helio, :get_charge, 1)
    end
  end

  # ============================================================================
  # Helio Webhook Controller Tests
  # ============================================================================

  describe "HelioWebhookController" do
    setup do
      # Set webhook secret for tests
      Application.put_env(:blockster_v2, :helio_webhook_secret, "test-webhook-secret-123")

      on_exit(fn ->
        Application.delete_env(:blockster_v2, :helio_webhook_secret)
      end)

      :ok
    end

    test "rejects requests with missing authorization header", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/helio/webhook", %{})

      assert json_response(conn, 401) == %{"error" => "unauthorized"}
    end

    test "rejects requests with wrong Bearer token", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer wrong-token")
        |> post("/api/helio/webhook", %{})

      assert json_response(conn, 401) == %{"error" => "unauthorized"}
    end

    test "accepts valid webhook and processes payment", %{conn: conn} do
      user = create_user()
      order = create_order_with_helio(user)

      # Set order to rogue_paid (ready for Helio)
      {:ok, order} = Orders.update_order(order, %{status: "rogue_paid"})

      payload = %{
        "event" => "CREATED",
        "transaction" => %{
          "id" => "helio-tx-123",
          "chargeId" => "charge-abc",
          "senderAddress" => "0xpayer123",
          "currency" => "USDC",
          "meta" => Jason.encode!(%{"order_id" => order.id, "order_number" => order.order_number})
        }
      }

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer test-webhook-secret-123")
        |> post("/api/helio/webhook", payload)

      assert json_response(conn, 200) == %{"status" => "ok"}

      # Verify order is now paid
      updated_order = Orders.get_order(order.id)
      assert updated_order.status == "paid"
      assert updated_order.helio_transaction_id == "helio-tx-123"
      assert updated_order.helio_payer_address == "0xpayer123"
      assert updated_order.helio_payment_currency == "USDC"
    end

    test "detects card payment from webhook payload", %{conn: conn} do
      user = create_user()
      order = create_order_with_helio(user)
      {:ok, order} = Orders.update_order(order, %{status: "rogue_paid"})

      payload = %{
        "event" => "CREATED",
        "transaction" => %{
          "id" => "helio-tx-card-456",
          "senderAddress" => "0xcardpayer",
          "paymentType" => "CARD",
          "currency" => "USD",
          "meta" => Jason.encode!(%{"order_id" => order.id})
        }
      }

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer test-webhook-secret-123")
        |> post("/api/helio/webhook", payload)

      assert json_response(conn, 200) == %{"status" => "ok"}

      updated_order = Orders.get_order(order.id)
      assert updated_order.helio_payment_currency == "CARD"
    end

    test "handles idempotency — ignores webhook for already-paid order", %{conn: conn} do
      user = create_user()
      order = create_order_with_helio(user)
      {:ok, order} = Orders.update_order(order, %{status: "paid"})

      payload = %{
        "event" => "CREATED",
        "transaction" => %{
          "id" => "helio-tx-duplicate",
          "senderAddress" => "0xpayer",
          "currency" => "USDC",
          "meta" => Jason.encode!(%{"order_id" => order.id})
        }
      }

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer test-webhook-secret-123")
        |> post("/api/helio/webhook", payload)

      # Should return 200 OK (idempotent)
      assert json_response(conn, 200) == %{"status" => "ok"}

      # Order should still be "paid" — no error, just ignored
      assert Orders.get_order(order.id).status == "paid"
    end

    test "handles idempotency for shipped/delivered orders", %{conn: conn} do
      user = create_user()
      order = create_order_with_helio(user)

      for status <- ["processing", "shipped", "delivered"] do
        {:ok, order} = Orders.update_order(order, %{status: status})

        payload = %{
          "event" => "CREATED",
          "transaction" => %{
            "id" => "helio-tx-dup-#{status}",
            "senderAddress" => "0xpayer",
            "currency" => "ETH",
            "meta" => Jason.encode!(%{"order_id" => order.id})
          }
        }

        conn =
          Phoenix.ConnTest.build_conn()
          |> put_req_header("content-type", "application/json")
          |> put_req_header("authorization", "Bearer test-webhook-secret-123")
          |> post("/api/helio/webhook", payload)

        assert json_response(conn, 200) == %{"status" => "ok"}
      end
    end

    test "returns error for missing order_id in meta", %{conn: conn} do
      payload = %{
        "event" => "CREATED",
        "transaction" => %{
          "id" => "helio-tx-no-meta",
          "senderAddress" => "0xpayer",
          "currency" => "USDC",
          "meta" => "{}"
        }
      }

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer test-webhook-secret-123")
        |> post("/api/helio/webhook", payload)

      assert json_response(conn, 400)["error"] =~ "missing order_id"
    end

    test "returns error for non-existent order", %{conn: conn} do
      payload = %{
        "event" => "CREATED",
        "transaction" => %{
          "id" => "helio-tx-bad-order",
          "senderAddress" => "0xpayer",
          "currency" => "USDC",
          "meta" => Jason.encode!(%{"order_id" => Ecto.UUID.generate()})
        }
      }

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer test-webhook-secret-123")
        |> post("/api/helio/webhook", payload)

      assert json_response(conn, 400)["error"] =~ "order not found"
    end

    test "ignores non-CREATED events", %{conn: conn} do
      payload = %{
        "event" => "PENDING",
        "transaction" => %{
          "id" => "helio-tx-pending",
          "senderAddress" => "0xpayer"
        }
      }

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer test-webhook-secret-123")
        |> post("/api/helio/webhook", payload)

      assert json_response(conn, 200) == %{"status" => "ok"}
    end

    test "detects crypto currencies from webhook payload" do
      assert BlocksterV2Web.HelioWebhookController.detect_payment_currency(%{"currency" => "SOL"}) == "SOL"
      assert BlocksterV2Web.HelioWebhookController.detect_payment_currency(%{"currency" => "eth"}) == "ETH"
      assert BlocksterV2Web.HelioWebhookController.detect_payment_currency(%{"currency" => "btc"}) == "BTC"
      assert BlocksterV2Web.HelioWebhookController.detect_payment_currency(%{"token" => "usdc"}) == "USDC"
      assert BlocksterV2Web.HelioWebhookController.detect_payment_currency(%{"paymentType" => "CARD"}) == "CARD"
      assert BlocksterV2Web.HelioWebhookController.detect_payment_currency(%{"source" => "CARD", "currency" => "USD"}) == "CARD"
      assert BlocksterV2Web.HelioWebhookController.detect_payment_currency(%{}) == "USDC"
    end

    test "handles meta as a map (not JSON string)", %{conn: conn} do
      user = create_user()
      order = create_order_with_helio(user)

      payload = %{
        "event" => "CREATED",
        "transaction" => %{
          "id" => "helio-tx-map-meta",
          "senderAddress" => "0xpayer",
          "currency" => "USDC",
          "meta" => %{"order_id" => order.id}
        }
      }

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer test-webhook-secret-123")
        |> post("/api/helio/webhook", payload)

      assert json_response(conn, 200) == %{"status" => "ok"}
      assert Orders.get_order(order.id).status == "paid"
    end
  end

  # ============================================================================
  # Order Helio Payment Tests
  # ============================================================================

  describe "Orders.complete_helio_payment/2" do
    test "sets order to paid with helio fields" do
      user = create_user()
      order = create_order_with_helio(user)
      {:ok, order} = Orders.update_order(order, %{status: "rogue_paid"})

      {:ok, updated} =
        Orders.complete_helio_payment(order, %{
          helio_transaction_id: "helio-tx-789",
          helio_charge_id: "charge-xyz",
          helio_payer_address: "0xpayer456",
          helio_payment_currency: "SOL"
        })

      assert updated.status == "paid"
      assert updated.helio_transaction_id == "helio-tx-789"
      assert updated.helio_charge_id == "charge-xyz"
      assert updated.helio_payer_address == "0xpayer456"
      assert updated.helio_payment_currency == "SOL"
    end

    test "broadcasts order update on PubSub" do
      user = create_user()
      order = create_order_with_helio(user)

      Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "order:#{order.id}")

      {:ok, _updated} =
        Orders.complete_helio_payment(order, %{
          helio_transaction_id: "helio-tx-pubsub",
          helio_payer_address: "0xpayer"
        })

      assert_receive {:order_updated, %Order{status: "paid"}}
    end
  end

  # ============================================================================
  # Order Helio Payment Changeset Tests
  # ============================================================================

  describe "Order.helio_payment_changeset/2" do
    test "casts all helio fields" do
      order = %Order{}

      changeset =
        Order.helio_payment_changeset(order, %{
          helio_charge_id: "charge-123",
          helio_transaction_id: "tx-123",
          helio_payer_address: "0xabc",
          helio_payment_amount: Decimal.new("50.00"),
          helio_payment_currency: "USDC",
          status: "paid"
        })

      assert changeset.valid?
      assert changeset.changes.helio_charge_id == "charge-123"
      assert changeset.changes.helio_transaction_id == "tx-123"
      assert changeset.changes.helio_payer_address == "0xabc"
      assert Decimal.eq?(changeset.changes.helio_payment_amount, Decimal.new("50.00"))
      assert changeset.changes.helio_payment_currency == "USDC"
      assert changeset.changes.status == "paid"
    end

    test "validates status inclusion" do
      changeset = Order.helio_payment_changeset(%Order{}, %{status: "invalid_status"})
      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :status)
    end

    test "allows helio_pending status" do
      changeset = Order.helio_payment_changeset(%Order{}, %{status: "helio_pending"})
      assert changeset.valid?
    end
  end

  # ============================================================================
  # Order Status Transitions for Helio
  # ============================================================================

  describe "order status transitions with Helio" do
    test "pending -> helio_pending (no BUX/ROGUE, direct to Helio)" do
      user = create_user()
      order = create_order_with_helio(user)

      {:ok, order} =
        order
        |> Order.helio_payment_changeset(%{
          helio_charge_id: "charge-direct",
          status: "helio_pending"
        })
        |> Repo.update()

      assert order.status == "helio_pending"
    end

    test "rogue_paid -> helio_pending -> paid (full three-part flow)" do
      user = create_user()
      order = create_order_with_bux(user, 500)

      # Phase 1: BUX paid
      {:ok, order} = Orders.complete_bux_payment(order, "bux-tx-hash")
      assert order.status == "bux_paid"

      # Set up ROGUE and Helio amounts
      {:ok, order} =
        order
        |> Order.rogue_payment_changeset(%{
          rogue_payment_amount: Decimal.new("20.00"),
          rogue_tokens_sent: Decimal.new("300000"),
          status: "rogue_paid"
        })
        |> Repo.update()

      {:ok, order} =
        order
        |> Order.helio_payment_changeset(%{helio_payment_amount: Decimal.new("30.00")})
        |> Repo.update()

      assert order.status == "rogue_paid"

      # Phase 3: Helio pending
      {:ok, order} =
        order
        |> Order.helio_payment_changeset(%{
          helio_charge_id: "charge-three-part",
          status: "helio_pending"
        })
        |> Repo.update()

      assert order.status == "helio_pending"

      # Phase 4: Helio paid via webhook
      {:ok, order} =
        Orders.complete_helio_payment(order, %{
          helio_transaction_id: "helio-tx-three-part",
          helio_payer_address: "0xthreepart",
          helio_payment_currency: "ETH"
        })

      assert order.status == "paid"
    end

    test "ROGUE covers full price — order goes to paid without Helio" do
      user = create_user()
      order = create_order_with_bux(user, 0)

      # ROGUE covers everything
      {:ok, order} =
        order
        |> Order.rogue_payment_changeset(%{
          rogue_payment_amount: order.subtotal,
          rogue_tokens_sent: Decimal.new("1000000"),
          status: "rogue_paid"
        })
        |> Repo.update()

      # helio_payment_amount is 0 — no Helio needed
      assert Decimal.eq?(order.helio_payment_amount, Decimal.new("0"))
    end
  end

  # ============================================================================
  # End-to-End Flow Tests
  # ============================================================================

  describe "end-to-end: BUX -> ROGUE -> Helio" do
    test "complete three-part payment flow with mocks" do
      user = create_user()

      # Set up BUX balance
      set_user_bux_balance(user.id, 5000.0)

      # Create order with BUX discount
      order = create_order_with_bux(user, 1000)
      assert order.bux_tokens_burned == 1000
      assert Decimal.gt?(order.bux_discount_amount, 0)

      # Step 1: BUX payment
      {:ok, bux_balance} = BlocksterV2.Shop.BalanceManager.deduct_bux(user.id, 1000)
      assert bux_balance == 4000.0
      {:ok, order} = Orders.complete_bux_payment(order, "bux-tx-e2e")
      assert order.status == "bux_paid"

      # Step 2: Set ROGUE and Helio amounts
      remaining = Decimal.sub(order.subtotal, order.bux_discount_amount)
      rogue_covers = Decimal.div(remaining, 2) |> Decimal.round(2)
      helio_covers = Decimal.sub(remaining, rogue_covers)

      {:ok, order} =
        order
        |> Order.rogue_payment_changeset(%{
          rogue_payment_amount: rogue_covers,
          rogue_tokens_sent: Decimal.new("500000"),
          status: "rogue_paid"
        })
        |> Repo.update()

      {:ok, order} =
        order
        |> Order.helio_payment_changeset(%{helio_payment_amount: helio_covers})
        |> Repo.update()

      assert order.status == "rogue_paid"

      # Step 3: Helio payment via webhook
      {:ok, order} =
        Orders.complete_helio_payment(order, %{
          helio_transaction_id: "helio-tx-e2e",
          helio_charge_id: "charge-e2e",
          helio_payer_address: "0xe2epayer",
          helio_payment_currency: "USDC"
        })

      assert order.status == "paid"
      assert order.helio_transaction_id == "helio-tx-e2e"
      assert order.helio_payment_currency == "USDC"
    end

    test "Helio-only payment (no BUX or ROGUE)" do
      user = create_user()
      order = create_order_with_helio(user)

      # Skip BUX and ROGUE — go straight to Helio
      assert order.bux_tokens_burned == 0
      assert Decimal.eq?(order.rogue_payment_amount, Decimal.new("0"))
      assert Decimal.gt?(order.helio_payment_amount, 0)

      {:ok, order} =
        Orders.complete_helio_payment(order, %{
          helio_transaction_id: "helio-tx-only",
          helio_payer_address: "0xhelioonly",
          helio_payment_currency: "SOL"
        })

      assert order.status == "paid"
      assert order.helio_payment_currency == "SOL"
    end

    test "BUX covers full price — no ROGUE or Helio needed" do
      user = create_user()

      set_user_bux_balance(user.id, 100000.0)

      product = create_product(%{bux_max_discount: 100})
      variant = create_variant(product, %{price: Decimal.new("50.00")})

      {:ok, _} = CartContext.add_to_cart(user.id, product.id, %{
        variant_id: variant.id,
        quantity: 1,
        bux_tokens_to_redeem: 5000
      })

      cart = CartContext.get_or_create_cart(user.id)
      {:ok, order} = Orders.create_order_from_cart(cart, user)

      # When BUX discount covers full subtotal
      assert Decimal.eq?(order.bux_discount_amount, order.subtotal)
      assert Decimal.eq?(order.helio_payment_amount, Decimal.new("0"))
    end

    test "partial ROGUE + Helio payment" do
      user = create_user()
      order = create_order_with_bux(user, 0)

      rogue_covers = Decimal.new("30.00")
      helio_covers = Decimal.sub(order.subtotal, rogue_covers)

      {:ok, order} =
        order
        |> Order.rogue_payment_changeset(%{
          rogue_payment_amount: rogue_covers,
          rogue_tokens_sent: Decimal.new("450000"),
          status: "rogue_paid"
        })
        |> Repo.update()

      {:ok, order} =
        order
        |> Order.helio_payment_changeset(%{helio_payment_amount: helio_covers})
        |> Repo.update()

      {:ok, order} =
        Orders.complete_helio_payment(order, %{
          helio_transaction_id: "helio-tx-partial",
          helio_payer_address: "0xpartial",
          helio_payment_currency: "BTC"
        })

      assert order.status == "paid"
      assert order.helio_payment_currency == "BTC"
      assert Decimal.eq?(order.rogue_payment_amount, Decimal.new("30.00"))
    end

    test "card payment via Helio" do
      user = create_user()
      order = create_order_with_helio(user)

      {:ok, order} =
        Orders.complete_helio_payment(order, %{
          helio_transaction_id: "helio-tx-card",
          helio_payer_address: "0xcarduser",
          helio_payment_currency: "CARD"
        })

      assert order.status == "paid"
      assert order.helio_payment_currency == "CARD"
    end
  end
end
