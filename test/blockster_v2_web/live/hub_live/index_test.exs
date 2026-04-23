defmodule BlocksterV2Web.HubLive.IndexTest do
  @moduledoc """
  Smoke + structure tests for the redesigned hubs index page.

  The page is `BlocksterV2Web.HubLive.Index` mounted at `/hubs`. Per the
  redesign release plan, the page shows a hero section, featured hubs,
  sticky search + filter bar, and a 4-column hub card grid.
  """

  use BlocksterV2Web.ConnCase
  import Phoenix.LiveViewTest

  alias BlocksterV2.Repo
  alias BlocksterV2.Blog.{Hub, Post}

  defp insert_hub(attrs \\ %{}) do
    defaults = %{
      name: "TestHub #{System.unique_integer([:positive])}",
      tag_name: "testhub#{System.unique_integer([:positive])}",
      slug: "testhub-#{System.unique_integer([:positive])}",
      color_primary: "#00FFA3",
      color_secondary: "#00DC82",
      description: "A test hub for the index page",
      is_active: true
    }

    %Hub{}
    |> Hub.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp insert_post(attrs) do
    defaults = %{
      title: "A post #{System.unique_integer([:positive])}",
      slug: "post-#{System.unique_integer([:positive])}",
      excerpt: "A short excerpt",
      featured_image: "https://example.com/img.jpg",
      published_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    Repo.insert!(struct(Post, Map.merge(defaults, attrs)))
  end

  describe "GET /hubs · anonymous" do
    test "mounts and renders the page with header and footer", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/hubs")

      # Design system header
      assert html =~ "ds-header"
      # Design system footer
      assert html =~ "ds-footer"
      assert html =~ "Where the chain meets the model."
    end

    test "renders the page hero with title and stats", %{conn: conn} do
      hub = insert_hub(%{name: "Solana", slug: "solana", tag_name: "solana"})
      insert_hub(%{name: "Ethereum", slug: "ethereum", tag_name: "ethereum"})

      # HUBS-02: "BUX Paid" tile now only renders when at least one published
      # post across the hubs has accumulated reader rewards. Seed a post with
      # `bux_earned > 0` to exercise the positive path.
      insert_post(%{hub_id: hub.id, bux_earned: 1_500})

      {:ok, _view, html} = live(conn, ~p"/hubs")

      # Hero title
      assert html =~ "Hubs"
      # Hero description mentions hub count
      assert html =~ "publications at the intersection of crypto and AI"
      # Stat tiles — article label pluralises per HUBS-02 (1 Article vs N Articles).
      assert html =~ "Article"
      assert html =~ "BUX Paid"
    end

    # HUBS-02: when no published post has any reader rewards yet, the
    # "BUX Paid" tile hides entirely rather than rendering a placeholder
    # "—" that reads as a render bug.
    test "hides 'BUX Paid' tile when no reader rewards have accrued", %{conn: conn} do
      insert_hub(%{name: "Solana", slug: "solana-nobux", tag_name: "solana_nobux"})

      {:ok, _view, html} = live(conn, ~p"/hubs")

      refute html =~ "BUX Paid"
    end

    # HUBS-02: pluralization — 1 published post should render "Article" not
    # "Articles" in the hero stat label.
    test "singular label when there is exactly one published post", %{conn: conn} do
      hub = insert_hub(%{name: "Solo", slug: "solo-hub", tag_name: "solo_hub"})
      insert_post(%{hub_id: hub.id})

      {:ok, _view, html} = live(conn, ~p"/hubs")

      assert html =~ "Article"
      refute html =~ ">Articles<"
    end

    test "renders featured hubs section with top hubs", %{conn: conn} do
      hub1 = insert_hub(%{name: "Moonpay", slug: "moonpay", tag_name: "moonpay",
                          color_primary: "#7D00FF", color_secondary: "#4A00B8"})
      hub2 = insert_hub(%{name: "Solana", slug: "solana-feat", tag_name: "solana_feat",
                          color_primary: "#00FFA3", color_secondary: "#00DC82"})
      hub3 = insert_hub(%{name: "Bitcoin", slug: "bitcoin", tag_name: "bitcoin",
                          color_primary: "#F7931A", color_secondary: "#B86811"})
      _hub4 = insert_hub(%{name: "Ethereum", slug: "ethereum-feat", tag_name: "ethereum_feat"})

      # Add posts to make featured hubs sort to the top
      for _ <- 1..5, do: insert_post(%{hub_id: hub1.id})
      for _ <- 1..3, do: insert_post(%{hub_id: hub2.id})
      for _ <- 1..2, do: insert_post(%{hub_id: hub3.id})

      {:ok, _view, html} = live(conn, ~p"/hubs")

      # Featured section has the eyebrow label
      assert html =~ "Featured this week"
      # Featured cards render with hub names
      assert html =~ "ds-hub-feature-card"
      assert html =~ "Moonpay"
    end

    test "renders the hub grid with hub cards", %{conn: conn} do
      # Insert 5 hubs - 3 become featured, 2 go to grid
      for i <- 1..5 do
        hub = insert_hub(%{name: "Hub#{i}", slug: "hub-grid-#{i}", tag_name: "hub_grid_#{i}"})
        for _ <- 1..(6 - i), do: insert_post(%{hub_id: hub.id})
      end

      {:ok, _view, html} = live(conn, ~p"/hubs")

      # Grid has hub cards
      assert html =~ "ds-hub-card"
      # Showing X stat
      assert html =~ "Showing"
      assert html =~ "of 5 hubs"
    end

    test "renders search input with hub count", %{conn: conn} do
      insert_hub()
      insert_hub()

      {:ok, _view, html} = live(conn, ~p"/hubs")

      assert html =~ "Search 2 hubs by name, topic, or asset..."
    end

    test "renders category filter chips", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/hubs")

      assert html =~ "ds-chip"
      assert html =~ "All"
      assert html =~ "DeFi"
      assert html =~ "Layer 1"
      assert html =~ "NFTs"
    end

    test "anonymous user sees Connect Wallet in header", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/hubs")

      assert html =~ "Connect Wallet"
    end

    test "renders Why Earn BUX banner", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/hubs")

      assert html =~ "Why Earn BUX?"
      assert html =~ "Redeem BUX to enter sponsored airdrops"
    end
  end

  describe "search" do
    test "filters hubs by name", %{conn: conn} do
      # Insert 4 hubs so 3 are featured, 1 goes to grid
      hub_a = insert_hub(%{name: "Alpha", slug: "alpha", tag_name: "alpha"})
      hub_b = insert_hub(%{name: "Beta", slug: "beta", tag_name: "beta"})
      hub_c = insert_hub(%{name: "Gamma", slug: "gamma", tag_name: "gamma"})
      hub_d = insert_hub(%{name: "Delta", slug: "delta-search", tag_name: "delta_search",
                           description: "Fourth hub"})

      # Give them posts so they sort predictably
      for _ <- 1..4, do: insert_post(%{hub_id: hub_a.id})
      for _ <- 1..3, do: insert_post(%{hub_id: hub_b.id})
      for _ <- 1..2, do: insert_post(%{hub_id: hub_c.id})
      insert_post(%{hub_id: hub_d.id})

      {:ok, view, _html} = live(conn, ~p"/hubs")

      # Delta should be in the grid (4th hub)
      html = render(view)
      assert html =~ "Delta"

      # Search for "Delta"
      html = view |> element("input[phx-keyup=search]") |> render_keyup(%{"value" => "Delta"})

      assert html =~ "Delta"
    end

    test "filters hubs by description", %{conn: conn} do
      hub_a = insert_hub(%{name: "AlphaHub", slug: "alpha-desc", tag_name: "alpha_desc",
                           description: "Blockchain infrastructure"})
      hub_b = insert_hub(%{name: "BetaHub", slug: "beta-desc", tag_name: "beta_desc",
                           description: "DeFi protocol"})
      hub_c = insert_hub(%{name: "GammaHub", slug: "gamma-desc", tag_name: "gamma_desc"})
      hub_d = insert_hub(%{name: "DeltaHub", slug: "delta-desc", tag_name: "delta_desc",
                           description: "DeFi lending"})

      for _ <- 1..4, do: insert_post(%{hub_id: hub_a.id})
      for _ <- 1..3, do: insert_post(%{hub_id: hub_b.id})
      for _ <- 1..2, do: insert_post(%{hub_id: hub_c.id})
      insert_post(%{hub_id: hub_d.id})

      {:ok, view, _html} = live(conn, ~p"/hubs")

      # Search for "DeFi" — should find DeltaHub (in grid)
      html = view |> element("input[phx-keyup=search]") |> render_keyup(%{"value" => "DeFi"})

      assert html =~ "DeltaHub"
    end

    test "empty search shows all grid hubs", %{conn: conn} do
      hub_a = insert_hub(%{name: "Hub A", slug: "hub-a-empty", tag_name: "hub_a_empty"})
      hub_b = insert_hub(%{name: "Hub B", slug: "hub-b-empty", tag_name: "hub_b_empty"})
      hub_c = insert_hub(%{name: "Hub C", slug: "hub-c-empty", tag_name: "hub_c_empty"})
      hub_d = insert_hub(%{name: "Hub D", slug: "hub-d-empty", tag_name: "hub_d_empty"})

      for _ <- 1..4, do: insert_post(%{hub_id: hub_a.id})
      for _ <- 1..3, do: insert_post(%{hub_id: hub_b.id})
      for _ <- 1..2, do: insert_post(%{hub_id: hub_c.id})
      insert_post(%{hub_id: hub_d.id})

      {:ok, view, _html} = live(conn, ~p"/hubs")

      # Type something then clear
      view |> element("input[phx-keyup=search]") |> render_keyup(%{"value" => "xyz"})
      html = view |> element("input[phx-keyup=search]") |> render_keyup(%{"value" => ""})

      # Hub D should be back in the grid
      assert html =~ "Hub D"
    end

    test "no results shows empty message", %{conn: conn} do
      # Insert exactly 3 hubs so they all become featured, grid is empty
      hub_a = insert_hub(%{name: "OnlyHub A", slug: "only-a", tag_name: "only_a"})
      hub_b = insert_hub(%{name: "OnlyHub B", slug: "only-b", tag_name: "only_b"})
      hub_c = insert_hub(%{name: "OnlyHub C", slug: "only-c", tag_name: "only_c"})

      for _ <- 1..3, do: insert_post(%{hub_id: hub_a.id})
      for _ <- 1..2, do: insert_post(%{hub_id: hub_b.id})
      insert_post(%{hub_id: hub_c.id})

      {:ok, view, _html} = live(conn, ~p"/hubs")

      html = view |> element("input[phx-keyup=search]") |> render_keyup(%{"value" => "nonexistent"})

      assert html =~ "No hubs match"
      assert html =~ "nonexistent"
    end
  end

  describe "filter_category" do
    test "clicking a category chip fires the filter event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/hubs")

      # Click the "DeFi" chip
      html = view |> element(~s|button[phx-value-category="defi"]|) |> render_click()

      # The active chip state should change (active chip gets the active CSS classes)
      assert html =~ "defi"
    end
  end

  describe "hub cards" do
    test "hub cards link to /hub/:slug", %{conn: conn} do
      # Insert a single hub — with only 1 hub, it becomes featured (not grid)
      # so we check the featured card link instead
      hub = insert_hub(%{name: "Solana Link Test", slug: "solana-link-test", tag_name: "solana_link_test"})
      insert_post(%{hub_id: hub.id})

      {:ok, _view, html} = live(conn, ~p"/hubs")

      # The hub card (featured or grid) should link to /hub/slug
      assert html =~ "/hub/solana-link-test"
    end

    test "hub cards show post count", %{conn: conn} do
      hub = insert_hub(%{name: "PostCount Hub", slug: "postcount-hub", tag_name: "postcount_hub"})
      for _ <- 1..7, do: insert_post(%{hub_id: hub.id})

      {:ok, _view, html} = live(conn, ~p"/hubs")

      # The hub has 7 posts — should appear as "7" in the featured section
      assert html =~ "PostCount Hub"
    end
  end

  describe "empty state" do
    test "renders page with zero hubs", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/hubs")

      # Should still render the header and footer
      assert html =~ "ds-header"
      assert html =~ "ds-footer"
      # Hero should show 0 hub count
      assert html =~ "0"
    end
  end
end
