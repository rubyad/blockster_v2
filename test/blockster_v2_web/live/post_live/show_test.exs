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

    test "renders discover sidebar with event, sale, and airdrop cards", %{conn: conn} do
      post = insert_post(%{})

      {:ok, _view, html} = live(conn, ~p"/#{post.slug}")

      # Discover sidebar cards
      assert html =~ "More on Blockster"
      assert html =~ "Event"
      assert html =~ "Token sale"
      assert html =~ "Airdrop"
      # Event and Sale are stubs
      assert html =~ "Coming soon"
      assert html =~ "Stay tuned"
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
end
