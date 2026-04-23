defmodule BlocksterV2Web.CheckoutLive.IndexTest do
  @moduledoc """
  Tests for the redesigned checkout page at `/checkout/:order_id`.

  The page is `BlocksterV2Web.CheckoutLive.Index`, mounted in the `:redesign`
  live_session. 4-step checkout: Shipping → Review → Payment → Confirmation.
  Payment step supports BUX burn + Helio USD widget.
  """

  use BlocksterV2Web.LiveCase, async: false

  alias BlocksterV2.{Repo, Shop, Orders}
  alias BlocksterV2.Cart, as: CartContext
  alias BlocksterV2.Shop.{ProductVariant, ProductImage}
  alias BlocksterV2.Blog.Hub

  setup do
    # Create a hub for product association
    hub =
      Repo.insert!(%Hub{
        name: "Phantom",
        slug: "phantom",
        tag_name: "phantom",
        description: "Phantom hub",
        color_primary: "#AB9FF2",
        color_secondary: "#534BB1"
      })

    # Create product with BUX discount
    {:ok, product} =
      Shop.create_product(%{
        title: "Phantom ghost crewneck",
        handle: "phantom-ghost-crewneck-#{System.unique_integer([:positive])}",
        status: "active",
        vendor: "Phantom",
        body_html: "Heavyweight fleece pullover.",
        bux_max_discount: 0,
        hub_id: hub.id
      })

    variant = Repo.insert!(%ProductVariant{
      product_id: product.id,
      title: "M / Charcoal",
      price: Decimal.new("55.00"),
      option1: "M",
      option2: "Charcoal"
    })

    Repo.insert!(%ProductImage{
      product_id: product.id,
      src: "https://example.com/crewneck.jpg",
      position: 1
    })

    # Create user
    {:ok, user} =
      BlocksterV2.Accounts.create_user_from_wallet(%{
        wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
        chain_id: 560_013
      })

    # Create cart, add item, create order
    cart = CartContext.get_or_create_cart(user.id)
    {:ok, _item} = CartContext.add_to_cart(user.id, product.id, %{
      variant_id: variant.id,
      quantity: 1,
      bux_tokens_to_redeem: 0
    })
    cart = CartContext.preload_items(CartContext.get_or_create_cart(user.id))
    {:ok, order} = Orders.create_order_from_cart(cart, user)
    order = Orders.get_order(order.id)

    %{hub: hub, product: product, variant: variant, user: user, order: order}
  end

  # ============================================================================
  # Anonymous visitor
  # ============================================================================

  describe "anonymous visitor" do
    test "redirects to homepage", %{conn: conn, order: order} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/checkout/#{order.id}")
    end
  end

  # ============================================================================
  # Wrong user
  # ============================================================================

  describe "wrong user" do
    test "redirects to cart", %{conn: conn, order: order} do
      {:ok, other_user} =
        BlocksterV2.Accounts.create_user_from_wallet(%{
          wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
          chain_id: 560_013
        })

      conn = log_in_user(conn, other_user)
      assert {:error, {:redirect, %{to: "/cart"}}} = live(conn, ~p"/checkout/#{order.id}")
    end
  end

  # ============================================================================
  # Non-existent order
  # ============================================================================

  describe "non-existent order" do
    test "redirects to cart", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      fake_uuid = Ecto.UUID.generate()
      assert {:error, {:redirect, %{to: "/cart"}}} = live(conn, ~p"/checkout/#{fake_uuid}")
    end
  end

  # ============================================================================
  # Step 1: Shipping
  # ============================================================================

  describe "shipping step" do
    test "renders DS header and footer", %{conn: conn, user: user, order: order} do
      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/checkout/#{order.id}")

      assert html =~ "ds-site-header"
      assert html =~ "SolanaWallet"
      assert html =~ "Why Earn BUX?"
      # Footer was retuned to the Solana brand line in the post-migration polish.
      assert html =~ "All in on Solana."
    end

    test "renders shipping form", %{conn: conn, user: user, order: order} do
      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/checkout/#{order.id}")

      # Step indicator
      assert html =~ "Step 1 of 4"
      assert html =~ "Where should we ship it?"

      # Form fields
      assert html =~ "Full name"
      assert html =~ ~s(name="shipping[shipping_name]")
      assert html =~ ~s(name="shipping[shipping_email]")
      assert html =~ ~s(name="shipping[shipping_address_line1]")
      assert html =~ ~s(name="shipping[shipping_city]")
      assert html =~ ~s(name="shipping[shipping_postal_code]")
      assert html =~ ~s(name="shipping[shipping_country]")
      assert html =~ ~s(name="shipping[shipping_phone]")

      # CTA
      assert html =~ "Continue to shipping options"
      assert html =~ "Back to Cart"
    end

    test "renders order summary sidebar", %{conn: conn, user: user, order: order} do
      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/checkout/#{order.id}")

      assert html =~ "Order summary"
      assert html =~ "Phantom ghost crewneck"
      assert html =~ "Subtotal"
      assert html =~ "Next step"
    end

    test "validate_shipping event works", %{conn: conn, user: user, order: order} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/checkout/#{order.id}")

      html =
        view
        |> form("[phx-submit='save_shipping']", shipping: %{shipping_name: ""})
        |> render_change()

      # Form should still render (validation doesn't crash)
      assert html =~ "shipping[shipping_name]"
    end

    test "save_shipping moves to rate selection", %{conn: conn, user: user, order: order} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/checkout/#{order.id}")

      html =
        view
        |> form("[phx-submit='save_shipping']", shipping: %{
          shipping_name: "Marcus Verren",
          shipping_email: "marcus@blockster.com",
          shipping_address_line1: "142 Cherry Lane",
          shipping_city: "Brooklyn",
          shipping_state: "NY",
          shipping_postal_code: "11217",
          shipping_country: "United States",
          shipping_phone: "+1 555 1234"
        })
        |> render_submit()

      # Should now show rate selection
      assert html =~ "Shipping to"
      assert html =~ "Marcus Verren"
      assert html =~ "Choose shipping method"
    end
  end

  # ============================================================================
  # Step 1b: Rate selection
  # ============================================================================

  describe "rate selection" do
    setup %{order: order} do
      # Pre-fill shipping address
      {:ok, order} = Orders.update_order_shipping(order, %{
        shipping_name: "Marcus Verren",
        shipping_email: "marcus@blockster.com",
        shipping_address_line1: "142 Cherry Lane",
        shipping_city: "Brooklyn",
        shipping_state: "NY",
        shipping_postal_code: "11217",
        shipping_country: "United States",
        shipping_phone: "+1 555 1234"
      })

      %{order: Orders.get_order(order.id)}
    end

    test "renders rate options", %{conn: conn, user: user, order: order} do
      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/checkout/#{order.id}")

      assert html =~ "Choose shipping method"
      assert html =~ "Standard Shipping"
      assert html =~ "Express Shipping"
    end

    test "select_shipping_rate moves to review", %{conn: conn, user: user, order: order} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/checkout/#{order.id}")

      html = render_click(view, "select_shipping_rate", %{"rate" => "us_standard"})

      # Should now show review step
      assert html =~ "Review your order"
      assert html =~ "Step 2 of 4"
    end

    test "edit_shipping_address returns to form", %{conn: conn, user: user, order: order} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/checkout/#{order.id}")

      html = render_click(view, "edit_shipping_address")

      assert html =~ "Where should we ship it?"
      assert html =~ "shipping[shipping_name]"
    end
  end

  # ============================================================================
  # Step 2: Review
  # ============================================================================

  describe "review step" do
    setup %{order: order} do
      # Pre-fill shipping address + select rate
      {:ok, order} = Orders.update_order_shipping(order, %{
        shipping_name: "Marcus Verren",
        shipping_email: "marcus@blockster.com",
        shipping_address_line1: "142 Cherry Lane",
        shipping_city: "Brooklyn",
        shipping_state: "NY",
        shipping_postal_code: "11217",
        shipping_country: "United States"
      })

      {:ok, order} = Orders.update_order_shipping_rate(order, %{
        shipping_cost: Decimal.new("5.99"),
        shipping_method: "us_standard"
      })

      %{order: Orders.get_order(order.id)}
    end

    test "renders review with order items", %{conn: conn, user: user, order: order} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/checkout/#{order.id}")

      # Navigate to review via rate selection
      html = render_click(view, "select_shipping_rate", %{"rate" => "us_standard"})

      assert html =~ "Review your order"
      assert html =~ "Phantom ghost crewneck"
      assert html =~ "Shipping to"
      assert html =~ "Marcus Verren"
      assert html =~ "Continue to payment"
      assert html =~ "Back to shipping"
    end

    test "go_to_step back to shipping", %{conn: conn, user: user, order: order} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/checkout/#{order.id}")
      _html = render_click(view, "select_shipping_rate", %{"rate" => "us_standard"})

      html = render_click(view, "go_to_step", %{"step" => "shipping"})

      assert html =~ "Choose shipping method"
    end

    test "proceed_to_payment moves to payment step", %{conn: conn, user: user, order: order} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/checkout/#{order.id}")
      _html = render_click(view, "select_shipping_rate", %{"rate" => "us_standard"})

      html = render_click(view, "proceed_to_payment")

      assert html =~ "Pay your order"
      assert html =~ "Step 3 of 4"
    end
  end

  # ============================================================================
  # Step 3: Payment
  # ============================================================================

  describe "payment step" do
    setup %{order: order} do
      {:ok, order} = Orders.update_order_shipping(order, %{
        shipping_name: "Marcus Verren",
        shipping_email: "marcus@blockster.com",
        shipping_address_line1: "142 Cherry Lane",
        shipping_city: "Brooklyn",
        shipping_state: "NY",
        shipping_postal_code: "11217",
        shipping_country: "United States"
      })

      {:ok, order} = Orders.update_order_shipping_rate(order, %{
        shipping_cost: Decimal.new("5.99"),
        shipping_method: "us_standard"
      })

      %{order: Orders.get_order(order.id)}
    end

    test "renders SOL payment card", %{conn: conn, user: user, order: order} do
      # Helio fiat card was removed in Phase 13; replaced by SOL-direct
      # payment intent with a countdown timer + address QR.
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/checkout/#{order.id}")
      _html = render_click(view, "select_shipping_rate", %{"rate" => "us_standard"})
      html = render_click(view, "proceed_to_payment")

      assert html =~ "Pay your order"
    end

    test "renders order total in sidebar", %{conn: conn, user: user, order: order} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/checkout/#{order.id}")
      _html = render_click(view, "select_shipping_rate", %{"rate" => "us_standard"})
      html = render_click(view, "proceed_to_payment")

      assert html =~ "Final total"
      assert html =~ "Subtotal"
    end

    test "back to review works", %{conn: conn, user: user, order: order} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/checkout/#{order.id}")
      _html = render_click(view, "select_shipping_rate", %{"rate" => "us_standard"})
      _html = render_click(view, "proceed_to_payment")

      html = render_click(view, "go_to_step", %{"step" => "review"})

      assert html =~ "Review your order"
    end
  end

  # ============================================================================
  # Step 3b: SHOP-14 BUX burn warning + non-refundable acknowledgement gate
  # ============================================================================

  describe "BUX burn warning gate (SHOP-14)" do
    setup %{order: order} do
      # Shipping + rate done so mount lands on :review; then we drive to :payment.
      {:ok, order} =
        Orders.update_order_shipping(order, %{
          shipping_name: "Marcus Verren",
          shipping_email: "marcus@blockster.com",
          shipping_address_line1: "142 Cherry Lane",
          shipping_city: "Brooklyn",
          shipping_state: "NY",
          shipping_postal_code: "11217",
          shipping_country: "United States"
        })

      {:ok, order} =
        Orders.update_order_shipping_rate(order, %{
          shipping_cost: Decimal.new("5.99"),
          shipping_method: "us_standard"
        })

      # Force bux_tokens_burned > 0 so the burn card renders on payment step.
      # The cart path is harder to provoke in unit tests (requires seeded Mnesia
      # BUX balance); mutating the order row post-creation isolates the UI
      # surface under test.
      order =
        order
        |> Ecto.Changeset.change(%{
          bux_tokens_burned: 1_000,
          bux_discount_amount: Decimal.new("10.00")
        })
        |> Repo.update!()

      %{order: Orders.get_order(order.id)}
    end

    test "renders non-refundable warning copy on payment step", %{conn: conn, user: user, order: order} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/checkout/#{order.id}")
      _ = render_click(view, "select_shipping_rate", %{"rate" => "us_standard"})
      html = render_click(view, "proceed_to_payment")

      assert html =~ "BUX is non-refundable"
      assert html =~ "I understand BUX is non-refundable"
      assert html =~ "15-minute window"
    end

    test "Send BUX button is disabled before acknowledgement", %{conn: conn, user: user, order: order} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/checkout/#{order.id}")
      _ = render_click(view, "select_shipping_rate", %{"rate" => "us_standard"})
      html = render_click(view, "proceed_to_payment")

      # `disabled` attribute rendered; `cursor-not-allowed` class applied.
      assert html =~ ~s(phx-click="initiate_bux_payment")
      assert html =~ "cursor-not-allowed"

      # The button with initiate_bux_payment should carry the disabled attribute.
      assert Regex.match?(
               ~r/phx-click="initiate_bux_payment"[^>]*disabled/s,
               html
             ) or
               Regex.match?(
                 ~r/disabled[^>]*phx-click="initiate_bux_payment"/s,
                 html
               )
    end

    test "clicking checkbox toggles ack and enables Send BUX button", %{
      conn: conn,
      user: user,
      order: order
    } do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/checkout/#{order.id}")
      _ = render_click(view, "select_shipping_rate", %{"rate" => "us_standard"})
      _ = render_click(view, "proceed_to_payment")

      html = render_click(view, "toggle_bux_warning_ack")

      # Button now rendered without `cursor-not-allowed` and without the
      # `disabled` attribute adjacent to `phx-click="initiate_bux_payment"`.
      refute Regex.match?(
               ~r/phx-click="initiate_bux_payment"[^>]*disabled/s,
               html
             )

      refute Regex.match?(
               ~r/disabled[^>]*phx-click="initiate_bux_payment"/s,
               html
             )
    end

    test "initiate_bux_payment without ack is a no-op with flash error", %{
      conn: conn,
      user: user,
      order: order
    } do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/checkout/#{order.id}")
      _ = render_click(view, "select_shipping_rate", %{"rate" => "us_standard"})
      _ = render_click(view, "proceed_to_payment")

      # Click the burn CTA without toggling the checkbox. The LV guard must
      # surface a flash error and MUST NOT touch BalanceManager / mutate the
      # order (otherwise this test would exit with :noproc since the
      # BalanceManager GenServer isn't started in :test).
      html = render_click(view, "initiate_bux_payment")
      assert html =~ "non-refundable"

      order_after = Orders.get_order(order.id)
      assert order_after.status == "pending"
      assert is_nil(order_after.bux_burn_started_at)
    end
  end

  # ============================================================================
  # Step 3c: SHOP-15 bux_burn_confirmed handler (server-side ready for hook)
  # ============================================================================

  describe "bux_burn_confirmed handler (SHOP-15)" do
    setup %{order: order} do
      # Order shaped to match the post-:initiate_bux_payment state: shipping
      # set, rate selected, status `:bux_pending`, bux_burn_started_at set.
      # This is the state the rebuilt JS hook will land the sig into.
      {:ok, order} =
        Orders.update_order_shipping(order, %{
          shipping_name: "Marcus Verren",
          shipping_email: "marcus@blockster.com",
          shipping_address_line1: "142 Cherry Lane",
          shipping_city: "Brooklyn",
          shipping_state: "NY",
          shipping_postal_code: "11217",
          shipping_country: "United States"
        })

      {:ok, order} =
        Orders.update_order_shipping_rate(order, %{
          shipping_cost: Decimal.new("5.99"),
          shipping_method: "us_standard"
        })

      started_at = DateTime.utc_now() |> DateTime.truncate(:second)

      order =
        order
        |> Ecto.Changeset.change(%{
          status: "bux_pending",
          bux_tokens_burned: 1_000,
          bux_discount_amount: Decimal.new("10.00"),
          bux_burn_started_at: started_at
        })
        |> Repo.update!()

      %{order: Orders.get_order(order.id)}
    end

    test "persists tx hash and advances status to :bux_paid", %{
      conn: conn,
      user: user,
      order: order
    } do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/checkout/#{order.id}")

      sig = "5vX" <> String.duplicate("a", 85)
      render_hook(view, "bux_burn_confirmed", %{"sig" => sig})

      order_after = Orders.get_order(order.id)
      assert order_after.bux_burn_tx_hash == sig
      assert order_after.status == "bux_paid"
    end

    test "legacy bux_payment_complete event still persists tx hash", %{
      conn: conn,
      user: user,
      order: order
    } do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/checkout/#{order.id}")

      legacy_hash = "5vX" <> String.duplicate("b", 85)
      render_hook(view, "bux_payment_complete", %{"tx_hash" => legacy_hash})

      assert Orders.get_order(order.id).bux_burn_tx_hash == legacy_hash
    end

    test "handler is idempotent — second firing does not overwrite tx hash", %{
      conn: conn,
      user: user,
      order: order
    } do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/checkout/#{order.id}")

      sig1 = "5vX" <> String.duplicate("c", 85)
      sig2 = "5vX" <> String.duplicate("d", 85)

      render_hook(view, "bux_burn_confirmed", %{"sig" => sig1})
      render_hook(view, "bux_burn_confirmed", %{"sig" => sig2})

      # First sig wins — the second firing is swallowed (guarding against a
      # double-pushEvent from the client).
      assert Orders.get_order(order.id).bux_burn_tx_hash == sig1
    end

    test "empty sig is a no-op", %{conn: conn, user: user, order: order} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/checkout/#{order.id}")

      render_hook(view, "bux_burn_confirmed", %{"sig" => ""})

      order_after = Orders.get_order(order.id)
      assert is_nil(order_after.bux_burn_tx_hash)
      assert order_after.status == "bux_pending"
    end
  end

  # ============================================================================
  # Step 4: Confirmation
  # ============================================================================

  describe "confirmation step" do
    setup %{order: order} do
      # Mark order as paid to reach confirmation
      {:ok, order} = Orders.update_order_shipping(order, %{
        shipping_name: "Marcus Verren",
        shipping_email: "marcus@blockster.com",
        shipping_address_line1: "142 Cherry Lane",
        shipping_city: "Brooklyn",
        shipping_state: "NY",
        shipping_postal_code: "11217",
        shipping_country: "United States"
      })

      {:ok, order} = Orders.update_order(order, %{status: "paid"})

      %{order: Orders.get_order(order.id)}
    end

    test "renders confirmation page", %{conn: conn, user: user, order: order} do
      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/checkout/#{order.id}")

      assert html =~ "Order complete"
      assert html =~ "Thanks,"
      assert html =~ order.order_number
      assert html =~ "Continue shopping"
    end

    test "renders DS footer", %{conn: conn, user: user, order: order} do
      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/checkout/#{order.id}")

      assert html =~ "All in on Solana."
    end
  end
end
