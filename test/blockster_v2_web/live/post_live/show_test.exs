defmodule BlocksterV2Web.PostLive.ShowTest do
  @moduledoc """
  Smoke + structure tests for the redesigned article page.

  The page is `BlocksterV2Web.PostLive.Show` mounted at `/:slug`. Per the redesign
  release plan, this file tests the new template structure: white article card,
  discover sidebar, suggest cards, preserved handlers.
  """

  use BlocksterV2Web.ConnCase
  import Phoenix.LiveViewTest

  alias BlocksterV2.Repo
  alias BlocksterV2.Blog.{Hub, Post, Category}

  defp insert_hub(attrs \\ %{}) do
    defaults = %{
      name: "TestHub #{System.unique_integer([:positive])}",
      tag_name: "testhub#{System.unique_integer([:positive])}",
      slug: "testhub-#{System.unique_integer([:positive])}",
      color_primary: "#7D00FF",
      color_secondary: "#4A00B8",
      description: "Test hub",
      is_active: true
    }

    %Hub{}
    |> Hub.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp insert_category(attrs \\ %{}) do
    defaults = %{
      name: "DeFi #{System.unique_integer([:positive])}",
      slug: "defi-#{System.unique_integer([:positive])}"
    }

    Repo.insert!(struct(Category, Map.merge(defaults, attrs)))
  end

  defp insert_post(attrs) do
    defaults = %{
      title: "Test Article #{System.unique_integer([:positive])}",
      slug: "test-article-#{System.unique_integer([:positive])}",
      excerpt: "A test excerpt for the article",
      featured_image: "https://example.com/img.jpg",
      content: %{"type" => "doc", "content" => [%{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "Hello world test content for the article."}]}]},
      published_at: DateTime.utc_now() |> DateTime.truncate(:second),
      author_name: "Test Author"
    }

    Repo.insert!(struct(Post, Map.merge(defaults, attrs)))
  end

  describe "GET /:slug · anonymous" do
    test "renders the article page with header and footer", %{conn: conn} do
      hub = insert_hub()
      post = insert_post(%{hub_id: hub.id})

      {:ok, _view, html} = live(conn, ~p"/#{post.slug}")

      # Design system header + footer rendered
      assert html =~ "ds-header"
      assert html =~ "ds-footer"
    end

    test "left sidebar no longer renders the hardcoded discover cards (replaced by widgets)", %{conn: conn} do
      post = insert_post(%{})

      {:ok, _view, html} = live(conn, ~p"/#{post.slug}")

      # Discover cards block was removed in Phase 6 — widgets render in its place.
      refute html =~ "More on Blockster"
      refute html =~ "Moonpay × Solana NYC happy hour"
      refute html =~ "Phoenix Protocol"
    end

    test "renders article title and category", %{conn: conn} do
      cat = insert_category(%{name: "Layer 2", slug: "layer-2"})
      post = insert_post(%{title: "The Future of Rollups", category_id: cat.id})

      {:ok, _view, html} = live(conn, ~p"/#{post.slug}")

      assert html =~ "The Future of Rollups"
      assert html =~ "Layer 2"
    end

    test "renders article excerpt", %{conn: conn} do
      post = insert_post(%{excerpt: "A deep dive into modern rollup architectures"})

      {:ok, _view, html} = live(conn, ~p"/#{post.slug}")

      assert html =~ "A deep dive into modern rollup architectures"
    end

    test "renders author avatar", %{conn: conn} do
      post = insert_post(%{})

      {:ok, _view, html} = live(conn, ~p"/#{post.slug}")

      # Author avatar (dark gradient circle matching mock's author-avatar class)
      assert html =~ "rounded-full grid place-items-center"
    end

    test "renders featured image", %{conn: conn} do
      post = insert_post(%{featured_image: "https://example.com/hero.jpg"})

      {:ok, _view, html} = live(conn, ~p"/#{post.slug}")

      assert html =~ "hero.jpg"
    end

    test "renders hub badge when post has a hub", %{conn: conn} do
      hub = insert_hub(%{name: "Moonpay Hub"})
      post = insert_post(%{hub_id: hub.id})

      {:ok, _view, html} = live(conn, ~p"/#{post.slug}")

      assert html =~ "Moonpay Hub"
    end

    test "returns 404 for non-existent slug", %{conn: conn} do
      assert_raise BlocksterV2Web.NotFoundError, fn ->
        live(conn, ~p"/this-slug-does-not-exist-12345")
      end
    end

    test "returns 404 for unpublished draft (anonymous)", %{conn: conn} do
      post = insert_post(%{published_at: nil})

      assert_raise BlocksterV2Web.NotFoundError, fn ->
        live(conn, ~p"/#{post.slug}")
      end
    end

    test "page uses eggshell background", %{conn: conn} do
      post = insert_post(%{})

      {:ok, _view, html} = live(conn, ~p"/#{post.slug}")

      assert html =~ "bg-[#fafaf9]"
    end

    # POST-01: author byline never renders the literal "Unknown". The old
    # behaviour was for posts with no author row (legacy / editorial content)
    # to surface "U · Unknown" in the hero byline, which reads as a render
    # bug. Now falls back to the hub name (if the post has one) or the
    # neutral "Blockster" editorial byline.
    test "author byline never renders 'Unknown' — falls back to hub name", %{conn: conn} do
      hub = insert_hub(%{name: "EditorialHub"})
      # Post with no author_id (nil) but a hub set.
      post = insert_post(%{hub_id: hub.id, author_id: nil, author_name: nil})

      {:ok, _view, html} = live(conn, ~p"/#{post.slug}")

      refute html =~ "Unknown"
      assert html =~ "EditorialHub"
    end

    test "author byline falls back to 'Blockster' when no author and no hub", %{conn: conn} do
      post = insert_post(%{hub_id: nil, author_id: nil, author_name: nil})

      {:ok, _view, html} = live(conn, ~p"/#{post.slug}")

      refute html =~ "Unknown"
      assert html =~ "Blockster"
    end
  end

  describe "GET /:slug · suggested posts" do
    test "renders suggested reading section with post cards", %{conn: conn} do
      hub = insert_hub()
      _post1 = insert_post(%{hub_id: hub.id, title: "Suggested One"})
      _post2 = insert_post(%{hub_id: hub.id, title: "Suggested Two"})
      main_post = insert_post(%{hub_id: hub.id, title: "Main Article"})

      {:ok, _view, html} = live(conn, ~p"/#{main_post.slug}")

      assert html =~ "Suggested For You"
    end
  end

  describe "GET /:slug · article body" do
    test "renders article content with article-body styling", %{conn: conn} do
      post = insert_post(%{})

      {:ok, _view, html} = live(conn, ~p"/#{post.slug}")

      assert html =~ "article-body"
      assert html =~ "Hello world test content"
    end

    test "renders tags when post has them", %{conn: conn} do
      post = insert_post(%{})
      tag = Repo.insert!(%BlocksterV2.Blog.Tag{name: "Solana", slug: "solana"})
      Repo.insert_all("post_tags", [%{post_id: post.id, tag_id: tag.id}])

      # Re-fetch to get tags
      {:ok, _view, html} = live(conn, ~p"/#{post.slug}")

      assert html =~ "Solana"
    end
  end

  describe "GET /:slug · Phase 3 widgets" do
    setup do
      BlocksterV2.Widgets.MnesiaCase.setup_widget_mnesia(%{})
      :ok
    end

    test "static rt-widget mock HTML is gone after Phase 3 cleanup", %{conn: conn} do
      post = insert_post(%{})

      {:ok, _view, html} = live(conn, ~p"/#{post.slug}")

      # These literal strings lived inside the deleted 979-1180 static block.
      refute html =~ "rt-widget rounded-2xl"
      refute html =~ "HERMES"
      refute html =~ "HIGH RISK"
    end

    test "widget banner on sidebar_right renders the skeleton even with empty cache", %{
      conn: conn
    } do
      post = insert_post(%{})

      {:ok, _banner} =
        BlocksterV2.Ads.create_banner(%{
          name: "rt-sky-test",
          placement: "sidebar_right",
          widget_type: "rt_skyscraper",
          widget_config: %{}
        })

      {:ok, _view, html} = live(conn, ~p"/#{post.slug}")

      assert html =~ ~s(phx-hook="RtSkyscraperWidget")
      assert html =~ "TOP ROGUEBOTS"
      # Empty cache → shimmer skeleton (Phase 6 polish)
      assert html =~ "rt-skyscraper-skeleton"
      assert html =~ "bw-skeleton"
    end

    test "widget banner on sidebar_left renders the fs_skyscraper skeleton", %{conn: conn} do
      post = insert_post(%{})

      {:ok, _banner} =
        BlocksterV2.Ads.create_banner(%{
          name: "fs-sky-test",
          placement: "sidebar_left",
          widget_type: "fs_skyscraper",
          widget_config: %{}
        })

      {:ok, _view, html} = live(conn, ~p"/#{post.slug}")

      assert html =~ ~s(phx-hook="FsSkyscraperWidget")
      assert html =~ "Gamble for a better price than market"
      # Empty cache → shimmer skeleton (Phase 6 polish)
      assert html =~ "fs-skyscraper-skeleton"
      assert html =~ "bw-skeleton"
    end

    test "live Mnesia bots are rendered into rt_skyscraper rows", %{conn: conn} do
      post = insert_post(%{})

      {:ok, _banner} =
        BlocksterV2.Ads.create_banner(%{
          name: "rt-sky-seeded",
          placement: "sidebar_right",
          widget_type: "rt_skyscraper",
          widget_config: %{}
        })

      bots = [
        %{
          "bot_id" => "kronos",
          "slug" => "kronos",
          "name" => "Kronos",
          "group_name" => "crypto",
          "lp_price" => 2.5,
          "bid_price" => 2.4,
          "ask_price" => 2.6,
          "sol_balance_ui" => 100.0,
          "lp_price_change_24h_pct" => 8.2,
          "market_open" => true,
          "rank" => 1
        }
      ]

      :mnesia.dirty_write({:widget_rt_bots_cache, :singleton, bots, System.system_time(:second)})

      {:ok, _view, html} = live(conn, ~p"/#{post.slug}")

      assert html =~ "KRONOS"
      assert html =~ "CRYPTO"
      assert html =~ "+8.2%"
      refute html =~ "rt-skyscraper-skeleton"
    end

    test "live Mnesia trades are rendered into fs_skyscraper rows", %{conn: conn} do
      post = insert_post(%{})

      {:ok, _banner} =
        BlocksterV2.Ads.create_banner(%{
          name: "fs-sky-seeded",
          placement: "sidebar_left",
          widget_type: "fs_skyscraper",
          widget_config: %{}
        })

      trades = [
        %{
          "id" => "order-live-1",
          "side" => "buy",
          "status_text" => "ORDER FILLED",
          "filled" => true,
          "token_symbol" => "JUP",
          "sol_amount_ui" => 0.1,
          "payout_ui" => 0.12,
          "multiplier" => 1.2,
          "discount_pct" => 5.0,
          "profit_ui" => 0.02,
          "profit_usd" => 3.2,
          "wallet_truncated" => "abcd…1234",
          "settled_at" => System.system_time(:second) - 30
        }
      ]

      :mnesia.dirty_write({:widget_fs_feed_cache, :singleton, trades, System.system_time(:second)})

      {:ok, _view, html} = live(conn, ~p"/#{post.slug}")

      assert html =~ ~s(data-trade-id="order-live-1")
      assert html =~ "BUY JUP"
      refute html =~ "fs-skyscraper-skeleton"
    end
  end

  describe "GET /:slug · Phase 4 chart widgets" do
    setup do
      BlocksterV2.Widgets.MnesiaCase.setup_widget_mnesia(%{})
      :ok
    end

    test "rt_chart_landscape banner on article_inline_1 renders with seeded selection", %{
      conn: conn
    } do
      post = insert_post(%{})

      {:ok, banner} =
        BlocksterV2.Ads.create_banner(%{
          name: "rt-chart-landscape-seeded",
          placement: "article_inline_1",
          widget_type: "rt_chart_landscape",
          widget_config: %{"selection" => "biggest_gainer"}
        })

      bots = [
        %{
          "bot_id" => "kronos",
          "slug" => "kronos",
          "name" => "KRONOS",
          "group_name" => "equities",
          "bid_price" => 0.1023,
          "ask_price" => 0.1026,
          "lp_price_change_7d_pct" => 6.78,
          "market_open" => true
        }
      ]

      :mnesia.dirty_write({:widget_rt_bots_cache, :singleton, bots, System.system_time(:second)})

      points = [%{"time" => 1, "value" => 0.1}, %{"time" => 2, "value" => 0.11}]

      :mnesia.dirty_write(
        {:widget_rt_chart_cache, {"kronos", "7d"}, "kronos", "7d", points, 0.11, 0.1, 6.78,
         System.system_time(:second)}
      )

      :mnesia.dirty_write(
        {:widget_selections, banner.id, "rt_chart_landscape", {"kronos", "7d"},
         System.system_time(:second)}
      )

      {:ok, _view, html} = live(conn, ~p"/#{post.slug}")

      assert html =~ ~s(phx-hook="RtChartWidget")
      assert html =~ ~s(data-widget-type="rt_chart_landscape")
      assert html =~ "TRACKING KRONOS"
      assert html =~ "KRONOS-LP Price"
      assert html =~ "+6.78%"
      # Seed blob carries the chart points
      assert html =~ ~s("value":0.11)
    end

    test "rt_chart_landscape without cached selection still renders empty shell", %{conn: conn} do
      post = insert_post(%{})

      {:ok, _banner} =
        BlocksterV2.Ads.create_banner(%{
          name: "rt-chart-landscape-empty",
          placement: "article_inline_1",
          widget_type: "rt_chart_landscape",
          widget_config: %{"selection" => "biggest_gainer"}
        })

      {:ok, _view, html} = live(conn, ~p"/#{post.slug}")

      assert html =~ ~s(phx-hook="RtChartWidget")
      assert html =~ "LIVE"
      # Empty price placeholders
      assert html =~ "—"
    end
  end

  describe "GET /:slug · Phase 5 widget wiring" do
    setup do
      BlocksterV2.Widgets.MnesiaCase.setup_widget_mnesia(%{})
      :ok
    end

    test "fs_hero_portrait banner on article_inline_2 renders the selected order with third-person copy",
         %{conn: conn} do
      post = insert_post(%{})

      {:ok, banner} =
        BlocksterV2.Ads.create_banner(%{
          name: "fs-hero-portrait-seeded",
          placement: "article_inline_2",
          widget_type: "fs_hero_portrait",
          widget_config: %{"selection" => "biggest_profit"}
        })

      trades = [
        %{
          "id" => "ord-picked",
          "side" => "buy",
          "filled" => true,
          "status_text" => "ORDER FILLED",
          "token_symbol" => "JUP",
          "sol_amount_ui" => 0.05,
          "payout_ui" => 633.12,
          "payout_usd" => 4.75,
          "sol_usd" => 4.30,
          "multiplier" => 1.10,
          "discount_pct" => 9.5,
          "profit_ui" => 57.55,
          "profit_usd" => 0.45,
          "profit_pct" => 10.0,
          "fill_chance_pct" => 40.0,
          "tx_signature" => "tx5k3ZHxaaaaaaaaaaaaaaaaaaaaaaaaaaaaaav95Rz6",
          "settled_at" => System.system_time(:second) - 60
        }
      ]

      :mnesia.dirty_write({:widget_fs_feed_cache, :singleton, trades, System.system_time(:second)})

      :mnesia.dirty_write(
        {:widget_selections, banner.id, "fs_hero_portrait", "ord-picked",
         System.system_time(:second)}
      )

      {:ok, _view, html} = live(conn, ~p"/#{post.slug}")

      assert html =~ ~s(data-widget-type="fs_hero_portrait")
      assert html =~ ~s(phx-hook="FsHeroWidget")
      # Selected order's data present
      assert html =~ "JUP"
      assert html =~ "633.12"
      # Third-person copy
      assert html =~ "Trader Received"
      assert html =~ "Trader Paid"
      refute html =~ "You received"
    end
  end
end
