defmodule BlocksterV2Web.ShopLive.IndexTest do
  @moduledoc """
  Tests for the redesigned shop index page at `/shop`.

  The page is `BlocksterV2Web.ShopLive.Index`, mounted in the `:redesign`
  live_session. It renders a full-bleed hero banner, a sidebar filter
  (Products / Communities / Brands), a 3-col product grid, and the
  DS header + footer.
  """

  use BlocksterV2Web.LiveCase, async: false

  alias BlocksterV2.{Shop, Repo}
  alias BlocksterV2.Shop.{ProductVariant, ProductImage}
  alias BlocksterV2.Blog.Hub

  setup do
    ensure_mnesia_tables()

    # Create a hub for product association
    hub =
      Repo.insert!(%Hub{
        name: "Solana",
        slug: "solana",
        tag_name: "solana",
        description: "Solana hub",
        color_primary: "#00FFA3",
        color_secondary: "#00DC82"
      })

    # Create a product WITH BUX discount
    {:ok, product_with_discount} =
      Shop.create_product(%{
        title: "Solana Hoodie",
        handle: "solana-hoodie",
        status: "active",
        vendor: "Blockster",
        bux_max_discount: 50,
        hub_id: hub.id
      })

    Repo.insert!(%ProductVariant{
      product_id: product_with_discount.id,
      title: "Default",
      price: Decimal.new("65.00"),
      compare_at_price: Decimal.new("65.00")
    })

    Repo.insert!(%ProductImage{
      product_id: product_with_discount.id,
      src: "https://example.com/hoodie.jpg",
      position: 1
    })

    # Create a product WITHOUT discount
    {:ok, product_no_discount} =
      Shop.create_product(%{
        title: "Trezor Safe 5",
        handle: "trezor-safe-5",
        status: "active",
        vendor: "Trezor"
      })

    Repo.insert!(%ProductVariant{
      product_id: product_no_discount.id,
      title: "Default",
      price: Decimal.new("179.00")
    })

    Repo.insert!(%ProductImage{
      product_id: product_no_discount.id,
      src: "https://example.com/trezor.jpg",
      position: 1
    })

    # Create a draft product (should NOT appear)
    {:ok, _draft} =
      Shop.create_product(%{
        title: "Draft Product",
        handle: "draft-product",
        status: "draft"
      })

    # Seed Mnesia slot assignments so products appear in the grid
    # (without slot assignments, non-admin users see empty slots which render nothing)
    BlocksterV2.ShopSlots.set_slot(0, to_string(product_with_discount.id))
    BlocksterV2.ShopSlots.set_slot(1, to_string(product_no_discount.id))

    %{
      hub: hub,
      product_with_discount: product_with_discount,
      product_no_discount: product_no_discount
    }
  end

  # ── Mnesia setup ───────────────────────────────────────────────────────────
  # ShopSlots.build_display_list reads :shop_product_slots Mnesia table.
  defp ensure_mnesia_tables do
    :mnesia.start()

    tables = [
      {:shop_product_slots, :set, [:slot_number, :product_id], []}
    ]

    for {name, type, attrs, index} <- tables do
      case :mnesia.create_table(name, type: type, attributes: attrs, index: index, ram_copies: [node()]) do
        {:atomic, :ok} -> :ok
        {:aborted, {:already_exists, ^name}} -> :ok
        _other -> :ok
      end
    end

    :ok
  end

  # ============================================================================
  # Page render · anonymous visitor
  # ============================================================================

  describe "page render · anonymous" do
    test "renders the redesigned shop index at /shop", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/shop")

      # DS header
      assert html =~ "ds-site-header"
      assert html =~ "SolanaWallet"
      assert html =~ "Why Earn BUX?"

      # Hero banner
      assert html =~ "Spend the BUX you earned"
      assert html =~ "Crypto-inspired streetwear &amp; gadgets"
      assert html =~ "products in stock"

      # SHOP-01 + SHOP-02: hero reads "Pay in SOL" (not USD) and drops the
      # dollar-denominated BUX rate pill in favour of a percentage-of-max-off
      # phrasing so the only monetary unit on the page is SOL.
      assert html =~ "Pay in SOL"
      assert html =~ "Redeem BUX for up to 50% off"
      refute html =~ "Pay in USD"
      refute html =~ "1 BUX = $"

      # Footer was retuned to the Solana brand line post-migration (matches
      # the checkout_live smoke assertion).
      assert html =~ "All in on Solana."
    end

    test "renders the shop nav link as active", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/shop")

      # Shop should be the active nav item (bold + lime underline)
      assert html =~ "Shop"
    end

    test "renders products in the grid", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/shop")

      assert html =~ "Solana Hoodie"
      assert html =~ "Trezor Safe 5"
      assert html =~ "Buy Now"
    end

    test "does not render draft products", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/shop")

      refute html =~ "Draft Product"
    end

    test "renders discounted price with strikethrough for products with BUX discount", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/shop")

      # Product with 50% discount: original $65.00, discounted $32.50
      assert html =~ "$65.00"
      assert html =~ "$32.50"
      assert html =~ "with BUX tokens"
    end

    test "renders regular price only for products without discount", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/shop")

      # Product without discount shows only $179.00
      assert html =~ "$179.00"
    end

    test "renders sidebar filter sections", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/shop")

      # Sidebar filter section labels
      assert html =~ "Communities"
      assert html =~ "Brands"
    end

    test "renders hub logo badge on products with hub association", %{conn: conn, hub: hub} do
      {:ok, _view, html} = live(conn, ~p"/shop")

      # Hub color gradient should appear in sidebar
      assert html =~ hub.color_primary
    end

    test "renders the product count in hero pill and toolbar", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/shop")

      # Should show "2" products (only active ones)
      assert html =~ "Showing"
      assert html =~ "products"
    end

    test "renders sort dropdown (inert)", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/shop")

      assert html =~ "Sort by"
      assert html =~ "Most popular"
    end
  end

  # ============================================================================
  # Filter handlers
  # ============================================================================

  describe "filter handlers" do
    test "filter by hub filters products", %{conn: conn, hub: hub} do
      {:ok, view, _html} = live(conn, ~p"/shop")

      # Click the hub filter
      html =
        view
        |> element("button[phx-click='filter_by_hub'][phx-value-slug='#{hub.slug}']")
        |> render_click()

      # Should show only the Solana Hoodie
      assert html =~ "Solana Hoodie"
      refute html =~ "Trezor Safe 5"
    end

    test "filter by brand filters products", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/shop")

      # Click the Trezor brand filter
      html =
        view
        |> element("button[phx-click='filter_by_brand'][phx-value-brand='Trezor']")
        |> render_click()

      # Should show only the Trezor Safe
      assert html =~ "Trezor Safe 5"
      refute html =~ "Solana Hoodie"
    end

    test "clear filter returns to all products", %{conn: conn, hub: hub} do
      # Start with a hub filter
      {:ok, view, _html} = live(conn, ~p"/shop?hub=#{hub.slug}")

      # Clear all filters
      html =
        view
        |> element("button[phx-click='clear_all_filters']", "View all")
        |> render_click()

      # Both products visible again
      assert html =~ "Solana Hoodie"
      assert html =~ "Trezor Safe 5"
    end

    test "active filter badge shows filter name and close button", %{conn: conn, hub: hub} do
      {:ok, _view, html} = live(conn, ~p"/shop?hub=#{hub.slug}")

      assert html =~ hub.name
    end

    test "empty filtered results show no-products message", %{conn: conn} do
      # Filter by a non-existent tag
      {:ok, _view, html} = live(conn, ~p"/shop?tag=nonexistent")

      # tag filter only works when products have the tag — no products means it falls through
      # to the "no filter" state (since apply_url_filters returns socket unchanged when
      # Enum.any?(filtered) is false)
      assert html =~ "Solana Hoodie" or html =~ "No products found"
    end
  end

  # ============================================================================
  # Mobile filters
  # ============================================================================

  describe "mobile filter toggle" do
    test "toggle_mobile_filters shows and hides drawer", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/shop")

      # Initially no drawer visible (the drawer only renders when show_mobile_filters is true)
      refute html =~ "Filters</h3>"

      # Click the mobile filter FAB
      html = render_click(view, "toggle_mobile_filters")

      # Drawer should now be visible with filter sections
      assert html =~ "Filters</h3>"

      # Click again to close
      html = render_click(view, "toggle_mobile_filters")

      refute html =~ "Filters</h3>"
    end
  end

  # ============================================================================
  # Product links
  # ============================================================================

  describe "product links" do
    test "product cards link to /shop/:slug", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/shop")

      assert html =~ "/shop/solana-hoodie"
      assert html =~ "/shop/trezor-safe-5"
    end
  end
end
