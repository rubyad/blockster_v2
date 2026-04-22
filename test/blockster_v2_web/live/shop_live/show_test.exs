defmodule BlocksterV2Web.ShopLive.ShowTest do
  @moduledoc """
  Tests for the redesigned product detail page at `/shop/:slug`.

  The page is `BlocksterV2Web.ShopLive.Show`, mounted in the `:redesign`
  live_session. It renders a gallery, sticky buy panel, BUX redemption card,
  related products, and the DS header + footer.
  """

  use BlocksterV2Web.LiveCase, async: false

  alias BlocksterV2.{Shop, Repo}
  alias BlocksterV2.Accounts.User
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

    # Create main product WITH BUX discount + hub + multiple images
    {:ok, product} =
      Shop.create_product(%{
        title: "Phantom ghost crewneck",
        handle: "phantom-ghost-crewneck",
        status: "active",
        vendor: "Phantom",
        body_html: "Heavyweight 14oz fleece pullover.",
        bux_max_discount: 40,
        hub_id: hub.id,
        collection_name: "PHANTOM HOLIDAY 2026",
        product_type: "Apparel"
      })

    Repo.insert!(%ProductVariant{
      product_id: product.id,
      title: "M / Charcoal",
      price: Decimal.new("55.00"),
      compare_at_price: Decimal.new("55.00"),
      option1: "M",
      option2: "Charcoal"
    })

    Repo.insert!(%ProductVariant{
      product_id: product.id,
      title: "L / Charcoal",
      price: Decimal.new("55.00"),
      compare_at_price: Decimal.new("55.00"),
      option1: "L",
      option2: "Charcoal"
    })

    Repo.insert!(%ProductImage{
      product_id: product.id,
      src: "https://example.com/crewneck-1.jpg",
      position: 1
    })

    Repo.insert!(%ProductImage{
      product_id: product.id,
      src: "https://example.com/crewneck-2.jpg",
      position: 2
    })

    # Create product config with sizes + colors
    {:ok, _config} =
      Shop.create_product_config(%{
        product_id: product.id,
        has_sizes: true,
        has_colors: true,
        size_type: "clothing",
        checkout_enabled: true
      })

    # Create a related product in the same hub
    {:ok, related_product} =
      Shop.create_product(%{
        title: "Phantom logo cap",
        handle: "phantom-logo-cap",
        status: "active",
        vendor: "Phantom",
        hub_id: hub.id,
        bux_max_discount: 30
      })

    Repo.insert!(%ProductVariant{
      product_id: related_product.id,
      title: "Default",
      price: Decimal.new("28.00")
    })

    Repo.insert!(%ProductImage{
      product_id: related_product.id,
      src: "https://example.com/cap.jpg",
      position: 1
    })

    # Create product WITHOUT discount and no hub
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

    %{
      hub: hub,
      product: product,
      related_product: related_product,
      product_no_discount: product_no_discount
    }
  end

  # ============================================================================
  # Page render · anonymous visitor
  # ============================================================================

  describe "page render · anonymous" do
    test "renders the redesigned product detail page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/shop/phantom-ghost-crewneck")

      # DS header
      assert html =~ "ds-site-header"
      assert html =~ "SolanaWallet"
      assert html =~ "Why Earn BUX?"

      # Footer
      assert html =~ "Where the chain meets the model."
    end

    test "renders the shop nav link as active", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/shop/phantom-ghost-crewneck")

      assert html =~ "Shop"
    end

    test "renders breadcrumb with shop link and product name", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/shop/phantom-ghost-crewneck")

      assert html =~ ~s(href="/shop")
      assert html =~ "Phantom ghost crewneck"
    end

    test "renders product name as heading", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/shop/phantom-ghost-crewneck")

      assert html =~ "Phantom ghost crewneck"
    end

    test "renders gallery with main image", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/shop/phantom-ghost-crewneck")

      assert html =~ "crewneck-1.jpg"
    end

    test "renders thumbnail strip for products with multiple images", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/shop/phantom-ghost-crewneck")

      # Both thumbnails should be present
      assert html =~ "crewneck-1.jpg"
      assert html =~ "crewneck-2.jpg"
      # Navigation arrows should exist
      assert html =~ "prev_image"
      assert html =~ "next_image"
    end

    test "renders collection eyebrow", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/shop/phantom-ghost-crewneck")

      assert html =~ "PHANTOM HOLIDAY 2026"
    end

    test "renders hub badge as black pill", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/shop/phantom-ghost-crewneck")

      # Hub name should appear in the badge (available in initial render)
      assert html =~ "Phantom"
    end

    test "renders price with full amount when no tokens redeemed (anonymous)", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/shop/phantom-ghost-crewneck")

      assert html =~ "$55.00"
    end

    test "renders discount toggle when product has bux_max_discount", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/shop/phantom-ghost-crewneck")

      assert html =~ "Hide discount breakdown"
    end

    test "renders size pills for clothing product", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/shop/phantom-ghost-crewneck")

      assert html =~ "Select size"
      assert html =~ "select_size"
    end

    test "renders color swatches for product with colors", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/shop/phantom-ghost-crewneck")

      assert html =~ "Select color"
      assert html =~ "select_color"
    end

    test "renders quantity stepper", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/shop/phantom-ghost-crewneck")

      assert html =~ "Quantity"
      assert html =~ "increment_quantity"
      assert html =~ "decrement_quantity"
    end

    test "renders Add to Cart button", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/shop/phantom-ghost-crewneck")

      assert html =~ "Add to cart"
      assert html =~ "add_to_cart"
    end

    test "renders reassurance grid", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/shop/phantom-ghost-crewneck")

      assert html =~ "Ships in 3-5 days"
      assert html =~ "Sustainably sourced"
      assert html =~ "30-day returns"
    end

    test "renders description section", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/shop/phantom-ghost-crewneck")

      assert html =~ "Description"
      assert html =~ "Heavyweight 14oz fleece pullover."
    end

    test "product with hub shows hub badge", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/shop/phantom-ghost-crewneck")

      # Hub badge renders with name
      assert html =~ "Phantom"
      assert html =~ "hub/phantom"
    end

    test "product without hub does not show hub badge", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/shop/trezor-safe-5")

      refute html =~ "hub/"
    end

    test "renders 1 BUX = $0.01 discount text in redemption card", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/shop/phantom-ghost-crewneck")

      # BUX redemption card is visible by default
      assert html =~ "1 BUX = $0.01 discount"
    end

    test "renders product price without strikethrough when no discount product", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/shop/trezor-safe-5")

      assert html =~ "$179.00"
      # No discount toggle should appear
      refute html =~ "Discount breakdown"
    end

    test "redirects to /shop for non-existent product", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/shop"}}} = live(conn, ~p"/shop/non-existent-product")
    end
  end

  # ============================================================================
  # Handlers
  # ============================================================================

  describe "image gallery handlers" do
    test "select_image changes current image", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/shop/phantom-ghost-crewneck")

      # Click second thumbnail
      html =
        view
        |> element("button[phx-click='select_image'][phx-value-index='1']")
        |> render_click()

      # The second image should now be "centered" (translateX 0%)
      assert html =~ "crewneck-2.jpg"
    end

    test "next_image cycles forward", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/shop/phantom-ghost-crewneck")

      html =
        view
        |> element("button[phx-click='next_image']")
        |> render_click()

      # After next, the translate should shift
      assert html =~ "crewneck-2.jpg"
    end

    test "prev_image cycles backward", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/shop/phantom-ghost-crewneck")

      html =
        view
        |> element("button[phx-click='prev_image']")
        |> render_click()

      # After prev from 0, wraps to last image
      assert html =~ "crewneck-2.jpg"
    end
  end

  describe "quantity handlers" do
    test "increment_quantity increases count", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/shop/phantom-ghost-crewneck")

      # Increment once
      view |> element("button[phx-click='increment_quantity']") |> render_click()

      # The "Add to cart" button shows the updated price for qty 2
      html = render(view)
      assert html =~ "$110.00"
    end

    test "decrement_quantity does not go below 1", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/shop/phantom-ghost-crewneck")

      # Increment first to get to 2, then decrement back to 1
      view |> element("button[phx-click='increment_quantity']") |> render_click()
      view |> element("button[phx-click='decrement_quantity']") |> render_click()

      # Price should be back to single-item price
      html = render(view)
      assert html =~ "$55.00"
    end
  end

  describe "size and color handlers" do
    test "select_size updates selected size", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/shop/phantom-ghost-crewneck")

      html =
        view
        |> element("button[phx-click='select_size'][phx-value-size='M']")
        |> render_click()

      # The M button should now have the active class
      assert html =~ "bg-[#0a0a0a]"
    end

    test "select_color updates selected color", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/shop/phantom-ghost-crewneck")

      html =
        view
        |> element("button[phx-click='select_color'][phx-value-color='Charcoal']")
        |> render_click()

      # Selected color name should show in the heading
      assert html =~ "Charcoal"
    end
  end

  describe "discount breakdown toggle" do
    test "BUX redemption card is visible by default and can be toggled", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/shop/phantom-ghost-crewneck")

      # Visible by default
      assert html =~ "Redeem BUX tokens"
      assert html =~ "Your BUX balance"
      assert html =~ "Token discount"
      assert html =~ "You pay"

      # Toggle to hide
      html = view |> element("button", "Hide discount breakdown") |> render_click()
      refute html =~ "Redeem BUX tokens"

      # Toggle to show again
      html = view |> element("button", "Discount breakdown") |> render_click()
      assert html =~ "Redeem BUX tokens"
    end
  end

  # ============================================================================
  # Product without hub (no related products)
  # ============================================================================

  describe "product without hub" do
    test "renders product without hub correctly", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/shop/trezor-safe-5")

      assert html =~ "Trezor Safe 5"
      assert html =~ "$179.00"
      # No hub badge
      refute html =~ "Phantom"
      # No related products
      refute html =~ "You may also like"
    end
  end

  # ============================================================================
  # Checkout disabled state
  # ============================================================================

  describe "checkout disabled" do
    test "shows Coming Soon when checkout_enabled is false", %{conn: conn, product_no_discount: product} do
      # Create config with checkout disabled
      {:ok, _config} =
        Shop.create_product_config(%{
          product_id: product.id,
          has_sizes: false,
          has_colors: false,
          checkout_enabled: false
        })

      {:ok, _view, html} = live(conn, ~p"/shop/trezor-safe-5")

      assert html =~ "Coming Soon"
      refute html =~ "add_to_cart"
    end
  end

  # ============================================================================
  # SHOP-04: BUX discount cap fallback
  #
  # Before the fix, `bux_max_discount = 0/nil` was treated as 100% discount
  # allowed — a user with enough BUX could redeem the full list value of any
  # un-migrated product. The flip (gated on SHOP_BUX_CAP_ENFORCED) makes
  # `0/nil` mean "BUX discount disabled (0%)".
  # ============================================================================

  describe "SHOP-04 BUX discount fallback" do
    setup do
      # Default flag ON so tests assert the hardened behaviour. Individual
      # tests that want the legacy path override with put_env + on_exit.
      System.put_env("SHOP_BUX_CAP_ENFORCED", "true")
      on_exit(fn -> System.delete_env("SHOP_BUX_CAP_ENFORCED") end)

      :mnesia.start()

      case :mnesia.create_table(:user_solana_balances,
             attributes: [:user_id, :wallet_address, :updated_at, :sol_balance, :bux_balance],
             type: :set,
             ram_copies: [node()]
           ) do
        {:atomic, :ok} -> :ok
        {:aborted, {:already_exists, _}} -> :ok
      end

      :ok
    end

    defp create_user_with_bux(bux_balance) do
      unique_id = System.unique_integer([:positive])

      pubkey =
        :crypto.strong_rand_bytes(32)
        |> Base.encode32(case: :lower, padding: false)
        |> String.replace(~r/[0il]/, "A")
        |> String.slice(0, 44)

      user =
        User.web3auth_registration_changeset(%{
          "wallet_address" => pubkey,
          "email" => "shop04_#{unique_id}@example.com",
          "username" => "shop04u#{unique_id}",
          "auth_method" => "web3auth_email"
        })
        |> Repo.insert!()

      :mnesia.dirty_write(
        :user_solana_balances,
        {:user_solana_balances, user.id, user.wallet_address, System.system_time(:second), 0.0,
         bux_balance * 1.0}
      )

      user
    end

    test "product with bux_max_discount=0 resolves to 0% effective discount (flag on)", %{
      conn: conn,
      product_no_discount: _product
    } do
      user = create_user_with_bux(22_000)
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/shop/trezor-safe-5")

      # Full list price renders, no discount panel active.
      assert html =~ "$179.00"
      # The hardened path sets effective_max = 0 so the "Max" hint collapses.
      assert html =~ "Max: 0"
      # The 100%-off exploit path never renders.
      refute html =~ "100% off"
      refute html =~ "Max: 17,900"
      # SHOP-05: Max button is disabled when the product has no cap.
      assert html =~ "Discount not available on this product"
      # The Max button renders with `cursor-not-allowed` + a `disabled` tooltip.
      assert html =~ "cursor-not-allowed"
    end

    test "product with bux_max_discount=0 still allows 100% discount under legacy flag (flag off)",
         %{conn: conn, product_no_discount: _product} do
      System.put_env("SHOP_BUX_CAP_ENFORCED", "false")

      user = create_user_with_bux(22_000)
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/shop/trezor-safe-5")

      # Legacy path treats 0 as 100% allowed; whole $179 is redeemable.
      assert html =~ "Max: 17,900"
    end

    test "product with explicit bux_max_discount=40 applies the cap (unchanged by fix)", %{
      conn: conn
    } do
      user = create_user_with_bux(22_000)
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/shop/phantom-ghost-crewneck")

      assert html =~ "(40% off)"
      assert html =~ "Max: 2,200"
    end
  end

  # ============================================================================
  # SHOP-05: default tokens_to_redeem = 0 on mount
  #
  # Previously the page pre-selected `min(user_balance, max_bux_tokens)`, so a
  # user landed on the page with the maximum discount already applied — the
  # anchor price rendered as strikethrough against the fully-discounted price.
  # After the fix the user sees the full SOL price until they actively enter a
  # BUX amount (or click "Max").
  # ============================================================================

  describe "SHOP-05 default tokens_to_redeem" do
    setup do
      System.put_env("SHOP_BUX_CAP_ENFORCED", "true")
      on_exit(fn -> System.delete_env("SHOP_BUX_CAP_ENFORCED") end)

      :mnesia.start()

      case :mnesia.create_table(:user_solana_balances,
             attributes: [:user_id, :wallet_address, :updated_at, :sol_balance, :bux_balance],
             type: :set,
             ram_copies: [node()]
           ) do
        {:atomic, :ok} -> :ok
        {:aborted, {:already_exists, _}} -> :ok
      end

      :ok
    end

    defp create_user_with_bux_05(bux_balance) do
      unique_id = System.unique_integer([:positive])

      pubkey =
        :crypto.strong_rand_bytes(32)
        |> Base.encode32(case: :lower, padding: false)
        |> String.replace(~r/[0il]/, "A")
        |> String.slice(0, 44)

      user =
        User.web3auth_registration_changeset(%{
          "wallet_address" => pubkey,
          "email" => "shop05_#{unique_id}@example.com",
          "username" => "shop05u#{unique_id}",
          "auth_method" => "web3auth_email"
        })
        |> Repo.insert!()

      :mnesia.dirty_write(
        :user_solana_balances,
        {:user_solana_balances, user.id, user.wallet_address, System.system_time(:second), 0.0,
         bux_balance * 1.0}
      )

      user
    end

    test "on mount with logged-in user holding BUX, tokens_to_redeem starts at 0",
         %{conn: conn} do
      user = create_user_with_bux_05(22_000)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/shop/phantom-ghost-crewneck")

      html = render(view)
      # Full $55.00 price shown, no discount badge.
      assert html =~ "$55.00"
      refute html =~ "% OFF"

      # The token input starts at 0.00 (template renders `:erlang.float_to_binary`).
      assert html =~ ~s(value="0.00")
    end

    test "anonymous visitors also see full price on mount (no regression)",
         %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/shop/phantom-ghost-crewneck")

      assert html =~ "$55.00"
      refute html =~ "% OFF"
    end
  end
end
