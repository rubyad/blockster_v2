defmodule BlocksterV2Web.HubLive.ShowTest do
  @moduledoc """
  Smoke + structure tests for the redesigned hub show page.

  The page is `BlocksterV2Web.HubLive.Show` mounted at `/hub/:slug`. Per the
  redesign release plan, the page shows a brand-color hero banner, sticky
  5-tab nav (All/News/Videos/Shop/Events), mosaic post grid, and per-tab
  content sections.
  """

  use BlocksterV2Web.ConnCase
  import Phoenix.LiveViewTest

  alias BlocksterV2.Repo
  alias BlocksterV2.Blog.{Hub, Post}
  alias BlocksterV2.Shop.{Product, ProductVariant, ProductImage}

  # Use struct-based insert to bypass changeset's generate_slug (which overwrites slug from name)
  defp insert_hub(attrs) do
    uid = System.unique_integer([:positive])
    defaults = %{
      name: "TestHub#{uid}",
      tag_name: "testhub#{uid}",
      slug: "testhub-#{uid}",
      color_primary: "#7D00FF",
      color_secondary: "#4A00B8",
      description: "A test hub for the show page",
      is_active: true
    }

    Repo.insert!(struct(Hub, Map.merge(defaults, attrs)))
  end

  defp insert_post(attrs) do
    defaults = %{
      title: "A post #{System.unique_integer([:positive])}",
      slug: "post-#{System.unique_integer([:positive])}",
      excerpt: "A short excerpt",
      featured_image: "https://example.com/img.jpg",
      published_at: DateTime.utc_now() |> DateTime.truncate(:second),
      kind: "other"
    }

    Repo.insert!(struct(Post, Map.merge(defaults, attrs)))
  end

  describe "GET /hub/:slug · anonymous" do
    test "mounts and renders the page with header and footer", %{conn: conn} do
      hub = insert_hub(%{name: "Moonpay", slug: "moonpay-show", tag_name: "moonpay_show"})
      insert_post(%{hub_id: hub.id})

      {:ok, _view, html} = live(conn, ~p"/hub/moonpay-show")

      assert html =~ "ds-header"
      assert html =~ "ds-footer"
      # Footer mission line — sentinel for the redesigned dark <.footer />.
      assert html =~ "Hustle hard. All in on crypto."
    end

    test "renders the hub banner with hub name and description", %{conn: conn} do
      hub = insert_hub(%{
        name: "Solana",
        slug: "solana-show",
        tag_name: "solana_show",
        description: "The fastest blockchain",
        color_primary: "#00FFA3",
        color_secondary: "#00DC82"
      })
      insert_post(%{hub_id: hub.id})

      {:ok, _view, html} = live(conn, ~p"/hub/solana-show")

      assert html =~ "ds-hub-banner"
      assert html =~ "Solana"
      assert html =~ "The fastest blockchain"
      assert html =~ "#00FFA3"
    end

    test "renders 5-tab navigation", %{conn: conn} do
      hub = insert_hub(%{slug: "tabs-test", tag_name: "tabs_test"})
      insert_post(%{hub_id: hub.id})

      {:ok, _view, html} = live(conn, ~p"/hub/tabs-test")

      assert html =~ "ds-hub-tabs"
      assert html =~ "All"
      assert html =~ "News"
      assert html =~ "Videos"
      assert html =~ "Shop"
      assert html =~ "Events"
    end

    test "renders pinned post on All tab", %{conn: conn} do
      hub = insert_hub(%{slug: "pinned-test", tag_name: "pinned_test"})
      insert_post(%{hub_id: hub.id, title: "The featured article"})

      {:ok, _view, html} = live(conn, ~p"/hub/pinned-test")

      assert html =~ "The featured article"
      assert html =~ "Pinned"
    end

    test "renders mosaic posts on All tab", %{conn: conn} do
      hub = insert_hub(%{slug: "mosaic-test", tag_name: "mosaic_test"})
      for i <- 1..5 do
        insert_post(%{hub_id: hub.id, title: "Mosaic Post #{i}"})
      end

      {:ok, _view, html} = live(conn, ~p"/hub/mosaic-test")

      assert html =~ "Latest stories"
      assert html =~ "Mosaic Post"
    end

    test "renders empty state when hub has no posts", %{conn: conn} do
      insert_hub(%{slug: "empty-show", tag_name: "empty_show"})

      {:ok, _view, html} = live(conn, ~p"/hub/empty-show")

      assert html =~ "No posts available yet"
    end

    test "renders Why Earn BUX banner", %{conn: conn} do
      hub = insert_hub(%{slug: "bux-show", tag_name: "bux_show"})
      insert_post(%{hub_id: hub.id})

      {:ok, _view, html} = live(conn, ~p"/hub/bux-show")

      assert html =~ "Why Earn BUX?"
      assert html =~ "Redeem BUX to enter sponsored airdrops"
    end

    test "anonymous user sees Connect Wallet in header", %{conn: conn} do
      hub = insert_hub(%{slug: "anon-show", tag_name: "anon_show"})
      insert_post(%{hub_id: hub.id})

      {:ok, _view, html} = live(conn, ~p"/hub/anon-show")

      assert html =~ "Connect Wallet"
    end
  end

  describe "tab switching" do
    test "switch_tab to news shows all posts as news", %{conn: conn} do
      hub = insert_hub(%{slug: "news-tab", tag_name: "news_tab"})
      insert_post(%{hub_id: hub.id, title: "My News Article"})

      {:ok, view, _html} = live(conn, ~p"/hub/news-tab")

      html = view |> element(~s|button[phx-value-tab="news"]|) |> render_click()

      assert html =~ "News from"
      assert html =~ "My News Article"
    end

    test "switch_tab to videos shows videos tab content", %{conn: conn} do
      hub = insert_hub(%{slug: "videos-tab", tag_name: "videos_tab"})
      insert_post(%{hub_id: hub.id})

      {:ok, view, _html} = live(conn, ~p"/hub/videos-tab")

      html = view |> element(~s|button[phx-value-tab="videos"]|) |> render_click()

      assert html =~ "Videos"
      assert html =~ "No videos yet"
    end

    test "switch_tab to shop shows shop tab content", %{conn: conn} do
      hub = insert_hub(%{slug: "shop-tab", tag_name: "shop_tab"})
      insert_post(%{hub_id: hub.id})

      {:ok, view, _html} = live(conn, ~p"/hub/shop-tab")

      html = view |> element(~s|button[phx-value-tab="shop"]|) |> render_click()

      assert html =~ "Hub merch"
      assert html =~ "No products yet"
    end

    # Regression: the hub mount used to pipe `Shop.list_products_by_hub/1`
    # through `Enum.map(&Shop.prepare_product_for_display/1)`, but
    # `list_products_by_hub` already applies that transform internally —
    # so the double-map blew up with `KeyError: key :variants not found`
    # on the display map the first call returned. The test in the
    # previous block seeds NO products so the `Enum.map` was a no-op and
    # the bug stayed hidden; this one seeds a product so the mount
    # actually exercises the transform.
    test "mounts with hub products without KeyError on :variants", %{conn: conn} do
      hub = insert_hub(%{slug: "hub-with-products", tag_name: "hub_with_products"})

      product =
        Repo.insert!(%Product{
          title: "Don't Trust, Verify Hoodie",
          handle: "dont-trust-verify-hoodie-#{System.unique_integer([:positive])}",
          status: "active",
          vendor: "Flare",
          hub_id: hub.id
        })

      Repo.insert!(%ProductVariant{
        product_id: product.id,
        title: "M",
        price: Decimal.new("45.00"),
        position: 0
      })

      Repo.insert!(%ProductImage{
        product_id: product.id,
        src: "https://example.com/hoodie.jpg",
        position: 0
      })

      {:ok, view, _html} = live(conn, ~p"/hub/hub-with-products")

      # Landing on /hub/:slug used to raise before the shop tab was
      # even clicked because the products list was computed at mount.
      # Clicking shop now renders the product card too. Select by the
      # top-nav wrapper so the fallback "View all" link (same phx-value)
      # at the bottom of a populated shop section isn't a 2-element
      # ambiguous match.
      html =
        view
        |> element(~s|.ds-hub-tabs button[phx-value-tab="shop"]|)
        |> render_click()

      assert html =~ "Don&#39;t Trust, Verify Hoodie"
      assert html =~ "https://example.com/hoodie.jpg"
      refute html =~ "No products yet"
    end

    test "switch_tab to events shows empty state per D15", %{conn: conn} do
      hub = insert_hub(%{slug: "events-tab", tag_name: "events_tab"})
      insert_post(%{hub_id: hub.id})

      {:ok, view, _html} = live(conn, ~p"/hub/events-tab")

      html = view |> element(~s|button[phx-value-tab="events"]|) |> render_click()

      assert html =~ "ds-events-empty"
      assert html =~ "No events yet from this hub"
      assert html =~ "Notify me"
    end

    test "switching back to all tab shows pinned post", %{conn: conn} do
      hub = insert_hub(%{slug: "back-all", tag_name: "back_all"})
      insert_post(%{hub_id: hub.id, title: "Back to all post"})

      {:ok, view, _html} = live(conn, ~p"/hub/back-all")

      # Switch to news then back to all
      view |> element(~s|button[phx-value-tab="news"]|) |> render_click()
      html = view |> element(~s|button[phx-value-tab="all"]|) |> render_click()

      assert html =~ "Back to all post"
    end
  end

  describe "follow button" do
    test "renders Follow Hub button for anonymous users", %{conn: conn} do
      hub = insert_hub(%{slug: "follow-anon", tag_name: "follow_anon"})
      insert_post(%{hub_id: hub.id})

      {:ok, _view, html} = live(conn, ~p"/hub/follow-anon")

      assert html =~ "Follow Hub"
      assert html =~ "toggle_follow"
    end
  end

  describe "hub not found" do
    test "redirects to homepage with flash", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/", flash: %{"error" => "Hub not found"}}}} =
               live(conn, ~p"/hub/nonexistent-hub-slug")
    end
  end

  describe "post links" do
    test "post cards link to /:slug", %{conn: conn} do
      hub = insert_hub(%{slug: "link-test", tag_name: "link_test"})
      insert_post(%{hub_id: hub.id, title: "Link Test Post", slug: "link-test-post"})

      {:ok, _view, html} = live(conn, ~p"/hub/link-test")

      assert html =~ "/link-test-post"
    end
  end

  describe "breadcrumb" do
    test "shows Hubs breadcrumb link", %{conn: conn} do
      hub = insert_hub(%{slug: "breadcrumb-test", tag_name: "breadcrumb_test", name: "BCHub"})
      insert_post(%{hub_id: hub.id})

      {:ok, _view, html} = live(conn, ~p"/hub/breadcrumb-test")

      assert html =~ "/hubs"
      assert html =~ "BCHub"
    end
  end
end
