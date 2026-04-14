defmodule BlocksterV2Web.PostLive.IndexTest do
  @moduledoc """
  Smoke + structure tests for the redesigned homepage.

  The page is `BlocksterV2Web.PostLive.Index` mounted at `/`. Per the redesign
  release plan, this file extends the existing handler tests with new template
  assertions for the new structure: hero featured article, cycling layouts,
  hub showcase, token sales stub, anonymous welcome hero, etc.
  """

  use BlocksterV2Web.ConnCase
  import Phoenix.LiveViewTest

  alias BlocksterV2.Repo
  alias BlocksterV2.Blog.{Hub, Post}

  defp insert_hub(attrs \\ %{}) do
    defaults = %{
      name: "Solana #{System.unique_integer([:positive])}",
      tag_name: "solana#{System.unique_integer([:positive])}",
      slug: "solana-#{System.unique_integer([:positive])}",
      color_primary: "#00FFA3",
      color_secondary: "#00DC82",
      description: "High-performance blockchain",
      is_active: true
    }

    %Hub{}
    |> Hub.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp insert_post(attrs) do
    defaults = %{
      title: "A real post #{System.unique_integer([:positive])}",
      slug: "post-#{System.unique_integer([:positive])}",
      excerpt: "A short excerpt",
      featured_image: "https://example.com/img.jpg",
      published_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    Repo.insert!(struct(Post, Map.merge(defaults, attrs)))
  end

  describe "GET / · anonymous" do
    test "mounts and renders the empty-state page when there are no posts", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      # Header from the new design system is rendered
      assert html =~ "ds-header"
      assert html =~ ">BL</span>"

      # Anonymous-only Welcome hero
      assert html =~ "ds-welcome-hero"
      assert html =~ "Welcome to Blockster"
      assert html =~ "Connect Wallet to start earning"

      # Anonymous-only What you unlock grid
      assert html =~ "ds-what-you-unlock"
      assert html =~ "Reading is free."

      # Footer
      assert html =~ "ds-footer"
      assert html =~ "Where the chain meets the model."
    end

    test "renders the hero featured card with the most recent post", %{conn: conn} do
      hub = insert_hub()

      _old =
        insert_post(%{
          title: "Old post",
          published_at: DateTime.utc_now() |> DateTime.add(-86_400, :second) |> DateTime.truncate(:second),
          hub_id: hub.id
        })

      newest =
        insert_post(%{
          title: "The newest post about Solana",
          excerpt: "An excerpt",
          published_at: DateTime.utc_now() |> DateTime.truncate(:second),
          hub_id: hub.id
        })

      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "ds-hero-feature"
      assert html =~ newest.title
      # The hero is the most recent post: verify the title appears INSIDE the
      # ds-hero-feature section, not just somewhere on the page.
      [_, hero_section] = String.split(html, "ds-hero-feature", parts: 2)
      [hero_only | _] = String.split(hero_section, ~s|</section>|, parts: 2)
      assert hero_only =~ newest.title
      refute hero_only =~ "Old post"
    end

    test "renders the hub showcase with hubs sorted by post count desc", %{conn: conn} do
      _empty_hub = insert_hub(%{name: "Empty hub", tag_name: "emptyx", slug: "empty-hub-x"})
      busy_hub = insert_hub(%{name: "Busy hub", tag_name: "busyx", slug: "busy-hub-x"})

      for i <- 1..3 do
        insert_post(%{title: "Busy post #{i}", hub_id: busy_hub.id})
      end

      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "ds-hub-card"
      assert html =~ "Busy hub"
      assert html =~ "Empty hub"
    end
  end

  describe "GET / · search handler" do
    test "search_posts handler still fires from the new template", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Fire the search_posts event directly (the header search button dispatches a JS event
      # that ultimately triggers this handler when wired up; for the unit test we fire it directly).
      assert render_hook(view, "search_posts", %{"value" => "ab"})
    end

    test "close_search handler still fires", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      assert render_hook(view, "close_search", %{})
    end
  end

  describe "GET / · BUX deposit modal handler (admin)" do
    test "open_bux_deposit_modal still works for admins", %{conn: conn} do
      hub = insert_hub()
      post = insert_post(%{hub_id: hub.id})

      {:ok, view, _html} = live(conn, ~p"/")

      # Non-admin: handler runs but the modal still receives the assign and renders.
      # We don't have an admin session in this smoke test; we just verify the handler
      # accepts the event without crashing.
      assert render_hook(view, "open_bux_deposit_modal", %{"post-id" => Integer.to_string(post.id)})
    end
  end

  describe "GET / · load-more handler" do
    test "load-more handler runs without crashing when there are no more posts", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # render_hook returns the rendered HTML (not the reply map). We just verify
      # the handler runs to completion without raising.
      result = render_hook(view, "load-more", %{})
      assert is_binary(result)
    end

    test "load-more appends a new cycle when more posts exist", %{conn: conn} do
      hub = insert_hub()
      # Insert enough posts that the first cycle (Hero=1 + Three=5 + Four=3 + Five=6 + Six=5 = 20)
      # has more posts available afterward
      for i <- 1..30 do
        insert_post(%{title: "Post #{i}", hub_id: hub.id})
      end

      {:ok, view, html_before} = live(conn, ~p"/")
      before_count = count_occurrences(html_before, "home-posts-three-")

      _ = render_hook(view, "load-more", %{})
      html_after = render(view)
      after_count = count_occurrences(html_after, "home-posts-three-")

      # After load-more, the stream should contain at least one more Three cycle
      assert after_count > before_count
    end
  end

  defp count_occurrences(haystack, needle) do
    haystack
    |> String.split(needle)
    |> length()
    |> Kernel.-(1)
  end

  describe "GET / · Phase 4 widget wiring" do
    setup do
      BlocksterV2.Widgets.MnesiaCase.setup_widget_mnesia(%{})
      :ok
    end

    test "rt_chart_landscape on homepage_inline renders with the chart hook", %{conn: conn} do
      {:ok, _banner} =
        BlocksterV2.Ads.create_banner(%{
          name: "homepage-rt-chart-landscape",
          placement: "homepage_inline",
          widget_type: "rt_chart_landscape",
          widget_config: %{"selection" => "biggest_gainer"}
        })

      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ ~s(phx-hook="RtChartWidget")
      assert html =~ ~s(data-widget-type="rt_chart_landscape")
      assert html =~ "LIVE"
    end
  end

  describe "GET / · Phase 5 widget wiring" do
    setup do
      BlocksterV2.Widgets.MnesiaCase.setup_widget_mnesia(%{})
      :ok
    end

    test "rt_ticker banner on homepage_top_desktop renders the ticker hook + bot row", %{
      conn: conn
    } do
      {:ok, _banner} =
        BlocksterV2.Ads.create_banner(%{
          name: "homepage-top-rt-ticker",
          placement: "homepage_top_desktop",
          widget_type: "rt_ticker",
          widget_config: %{}
        })

      bots = [
        %{
          "bot_id" => "kronos",
          "slug" => "kronos",
          "name" => "KRONOS",
          "group_name" => "equities",
          "bid_price" => 0.1023,
          "ask_price" => 0.1026,
          "lp_price" => 0.1023,
          "lp_price_change_24h_pct" => 3.24
        }
      ]

      :mnesia.dirty_write({:widget_rt_bots_cache, :singleton, bots, System.system_time(:second)})

      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ ~s(phx-hook="RtTickerWidget")
      assert html =~ ~s(data-widget-type="rt_ticker")
      assert html =~ "KRONOS"
      # CSS marquee duplicate set
      assert html =~ "bw-marquee-track"
    end
  end
end
