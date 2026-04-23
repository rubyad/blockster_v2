defmodule BlocksterV2Web.CartLive.IndexTest do
  @moduledoc """
  Tests for the redesigned cart page at `/cart`.

  The page is `BlocksterV2Web.CartLive.Index`, mounted in the `:redesign`
  live_session. It renders per-item BUX redemption, sticky order summary,
  suggested products, and the DS header + footer.
  """

  use BlocksterV2Web.LiveCase, async: false

  alias BlocksterV2.{Repo, Shop}
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

    # Create product with BUX discount + hub
    {:ok, product1} =
      Shop.create_product(%{
        title: "Phantom ghost crewneck",
        handle: "phantom-ghost-crewneck",
        status: "active",
        vendor: "Phantom",
        body_html: "Heavyweight fleece pullover.",
        bux_max_discount: 40,
        hub_id: hub.id
      })

    variant1 = Repo.insert!(%ProductVariant{
      product_id: product1.id,
      title: "M / Charcoal",
      price: Decimal.new("55.00"),
      option1: "M",
      option2: "Charcoal"
    })

    Repo.insert!(%ProductImage{
      product_id: product1.id,
      src: "https://example.com/crewneck.jpg",
      position: 1
    })

    # Create product WITHOUT discount, no hub
    {:ok, product2} =
      Shop.create_product(%{
        title: "Solana sticker pack",
        handle: "solana-sticker-pack",
        status: "active",
        vendor: "Solana",
        bux_max_discount: 0
      })

    Repo.insert!(%ProductVariant{
      product_id: product2.id,
      title: "Default",
      price: Decimal.new("8.00")
    })

    Repo.insert!(%ProductImage{
      product_id: product2.id,
      src: "https://example.com/stickers.jpg",
      position: 1
    })

    # Create user
    {:ok, user} =
      BlocksterV2.Accounts.create_user_from_wallet(%{
        wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
        chain_id: 560_013
      })

    %{hub: hub, product1: product1, variant1: variant1, product2: product2, user: user}
  end

  # ============================================================================
  # Anonymous visitor
  # ============================================================================

  describe "anonymous visitor" do
    test "redirects to homepage", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/cart")
    end
  end

  # ============================================================================
  # Empty cart
  # ============================================================================

  describe "empty cart" do
    test "renders empty cart state", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/cart")

      # DS header
      assert html =~ "ds-site-header"
      assert html =~ "SolanaWallet"
      assert html =~ "Why Earn BUX?"

      # Page hero
      assert html =~ "0 items"
      assert html =~ "Your cart is empty"

      # Empty state card
      assert html =~ "Nothing in here yet"
      assert html =~ "Browse the shop"
      assert html =~ "Earn BUX reading"
      assert html =~ ~s(href="/shop")

      # Footer
      assert html =~ "Where the chain meets the model."
    end
  end

  # ============================================================================
  # Filled cart · page render
  # ============================================================================

  describe "filled cart · render" do
    setup %{user: user, product1: product1, variant1: variant1, product2: product2} do
      {:ok, _item1} = CartContext.add_to_cart(user.id, product1.id, %{quantity: 1, variant_id: variant1.id})
      {:ok, _item2} = CartContext.add_to_cart(user.id, product2.id, %{quantity: 2})
      :ok
    end

    test "renders filled cart with items", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/cart")

      # DS header
      assert html =~ "ds-site-header"
      assert html =~ "Why Earn BUX?"

      # Page hero
      assert html =~ "Your cart"
      assert html =~ "items"

      # Footer
      assert html =~ "Where the chain meets the model."
    end

    test "renders product titles", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/cart")

      assert html =~ "Phantom ghost crewneck"
      assert html =~ "Solana sticker pack"
    end

    test "renders product images", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/cart")

      assert html =~ "crewneck.jpg"
      assert html =~ "stickers.jpg"
    end

    test "renders variant info", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/cart")

      # Product1 has variant with option1="M", option2="Charcoal"
      assert html =~ "Charcoal"
    end

    test "renders hub badge for products with hub", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/cart")

      assert html =~ "Phantom"
      assert html =~ "#AB9FF2"
    end

    test "renders quantity stepper", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/cart")

      assert html =~ "increment_quantity"
      assert html =~ "decrement_quantity"
    end

    test "renders order summary", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/cart")

      assert html =~ "Order summary"
      assert html =~ "Subtotal"
      assert html =~ "Total"
    end

    test "renders proceed to checkout button", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/cart")

      assert html =~ "Proceed to checkout"
      assert html =~ "proceed_to_checkout"
    end

    test "renders continue shopping link", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/cart")

      assert html =~ "Continue shopping"
      assert html =~ ~s(href="/shop")
    end

    test "renders payment info footnote", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/cart")

      assert html =~ "Pay with USD via Helio"
      assert html =~ "BUX burned on Solana"
    end

    test "renders BUX redemption for discount-eligible items", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/cart")

      assert html =~ "BUX to redeem"
      assert html =~ "update_bux_tokens"
    end
  end

  # ============================================================================
  # Handlers
  # ============================================================================

  describe "increment_quantity" do
    setup %{user: user, product1: product1, variant1: variant1} do
      {:ok, _item} = CartContext.add_to_cart(user.id, product1.id, %{quantity: 1, variant_id: variant1.id})
      :ok
    end

    test "increases item quantity", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/cart")

      cart = CartContext.get_or_create_cart(user.id) |> CartContext.preload_items()
      item = List.first(cart.cart_items)

      view |> element("button[phx-click='increment_quantity'][phx-value-item-id='#{item.id}']") |> render_click()

      html = render(view)
      # After increment, quantity should be 2
      assert html =~ ">2<"
    end
  end

  describe "decrement_quantity" do
    setup %{user: user, product1: product1, variant1: variant1} do
      {:ok, _item} = CartContext.add_to_cart(user.id, product1.id, %{quantity: 3, variant_id: variant1.id})
      :ok
    end

    test "decreases item quantity", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/cart")

      cart = CartContext.get_or_create_cart(user.id) |> CartContext.preload_items()
      item = List.first(cart.cart_items)

      view |> element("button[phx-click='decrement_quantity'][phx-value-item-id='#{item.id}']") |> render_click()

      html = render(view)
      # After decrement from 3, quantity should be 2
      assert html =~ ">2<"
    end
  end

  describe "remove_item" do
    setup %{user: user, product1: product1, variant1: variant1} do
      {:ok, _item} = CartContext.add_to_cart(user.id, product1.id, %{quantity: 1, variant_id: variant1.id})
      :ok
    end

    test "removes item and shows flash", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/cart")

      cart = CartContext.get_or_create_cart(user.id) |> CartContext.preload_items()
      item = List.first(cart.cart_items)

      view |> element("button[phx-click='remove_item'][phx-value-item-id='#{item.id}']") |> render_click()

      html = render(view)
      # After removing only item, should show empty cart
      assert html =~ "Your cart is empty"
    end
  end

  # ============================================================================
  # SHOP-cart · add-to-cart counter + item fields (PR 3a checklist)
  # ============================================================================

  describe "add-to-cart flow (SHOP-cart)" do
    test "cart counter goes from empty-state to singular after one add", %{
      conn: conn,
      user: user,
      product1: product1,
      variant1: variant1
    } do
      # Mount empty first so the baseline assertion is real, not synthetic.
      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/cart")
      assert html =~ "Your cart is empty"
      assert html =~ "0 items"

      # Add via the Cart context — same path the product page uses.
      {:ok, _item} =
        CartContext.add_to_cart(user.id, product1.id, %{
          quantity: 1,
          variant_id: variant1.id
        })

      {:ok, _view, html} = live(conn, ~p"/cart")

      # Counter on cart hero is pluralised per length(cart_items) — asserting
      # both the number and the singular/plural branch locks both in.
      refute html =~ "Your cart is empty"
      assert html =~ "1 item"
      refute html =~ "1 items"
    end

    test "cart counter reaches 2 after adding a second distinct item", %{
      conn: conn,
      user: user,
      product1: product1,
      variant1: variant1,
      product2: product2
    } do
      {:ok, _item1} =
        CartContext.add_to_cart(user.id, product1.id, %{
          quantity: 1,
          variant_id: variant1.id
        })

      {:ok, _item2} = CartContext.add_to_cart(user.id, product2.id, %{quantity: 1})

      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/cart")

      assert html =~ "2 items"
      refute html =~ "0 items"
    end

    test "each added item renders its title, image, and variant field values", %{
      conn: conn,
      user: user,
      product1: product1,
      variant1: variant1
    } do
      {:ok, _item} =
        CartContext.add_to_cart(user.id, product1.id, %{
          quantity: 3,
          variant_id: variant1.id
        })

      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/cart")

      # Title, image, and variant descriptor all present — catches the class
      # where preload drops or the template stops rendering an item field.
      assert html =~ "Phantom ghost crewneck"
      assert html =~ "crewneck.jpg"
      assert html =~ "Charcoal"
      # Quantity 3 surfaces as the stepper value.
      assert html =~ ">3<"
    end

    test "removing the only item drops the counter back to empty state", %{
      conn: conn,
      user: user,
      product1: product1,
      variant1: variant1
    } do
      {:ok, _item} =
        CartContext.add_to_cart(user.id, product1.id, %{
          quantity: 1,
          variant_id: variant1.id
        })

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/cart")

      cart = CartContext.get_or_create_cart(user.id) |> CartContext.preload_items()
      item = List.first(cart.cart_items)

      html =
        view
        |> element("button[phx-click='remove_item'][phx-value-item-id='#{item.id}']")
        |> render_click()

      assert html =~ "Your cart is empty"
    end
  end

  describe "update_bux_tokens" do
    setup %{user: user, product1: product1, variant1: variant1} do
      {:ok, _item} = CartContext.add_to_cart(user.id, product1.id, %{quantity: 1, variant_id: variant1.id})
      :ok
    end

    test "updates BUX amount on item", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/cart")

      cart = CartContext.get_or_create_cart(user.id) |> CartContext.preload_items()
      item = List.first(cart.cart_items)

      view
      |> element("form[phx-change='update_bux_tokens']")
      |> render_change(%{"item-id" => item.id, "bux" => "500"})

      # Verify the BUX was updated in DB
      updated_cart = CartContext.get_or_create_cart(user.id) |> CartContext.preload_items()
      updated_item = List.first(updated_cart.cart_items)
      assert updated_item.bux_tokens_to_redeem == 500
    end
  end
end
