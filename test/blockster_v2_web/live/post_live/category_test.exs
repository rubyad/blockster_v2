defmodule BlocksterV2Web.PostLive.CategoryTest do
  @moduledoc """
  Tests for the redesigned Category Browse page (Wave 5 Page #16).

  Route: /category/:slug
  LiveView: BlocksterV2Web.PostLive.Category
  Mock: docs/solana/category_mock.html

  Tests cover: DS header/footer, page hero with stats, featured post,
  filter chips, mosaic grid, related categories, featured author card,
  category-not-found redirect, anonymous access.
  """

  use BlocksterV2Web.LiveCase, async: false

  alias BlocksterV2.Repo
  # Category created via Blog.create_category/1
  alias BlocksterV2.Blog.Post
  alias BlocksterV2.Blog.Hub
  alias BlocksterV2.Accounts.User

  setup do
    unique = System.unique_integer([:positive])

    # Create a hub (tag_name is NOT NULL)
    hub =
      Repo.insert!(%Hub{
        name: "TestHub#{unique}",
        slug: "testhub-#{unique}",
        tag_name: "testhub-#{unique}",
        description: "Test hub",
        color_primary: "#00FFA3",
        color_secondary: "#00DC82"
      })

    # Create the target category with unique name/slug
    {:ok, category} =
      BlocksterV2.Blog.create_category(%{
        name: "TestCat#{unique}",
        slug: "testcat-#{unique}",
        description: "Lending, AMMs, perps, derivatives, restaking."
      })

    # Create a related category
    {:ok, related_category} =
      BlocksterV2.Blog.create_category(%{
        name: "RelatedCat#{unique}",
        slug: "relatedcat-#{unique}",
        description: "Layer 2 scaling solutions."
      })

    # Create an author
    author =
      Repo.insert!(%User{
        wallet_address: "TestCatAuthor#{System.unique_integer([:positive])}",
        username: "Jamie Chen",
        bio: "Markets writer focused on Solana DEXes.",
        auth_method: "wallet"
      })

    # Create posts in the category
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    posts =
      for i <- 1..5 do
        Repo.insert!(%Post{
          title: "TestCat Article #{i}",
          slug: "testcat-article-#{unique}-#{i}",
          excerpt: "Excerpt for article #{i}",
          content: %{
            "type" => "doc",
            "content" => [
              %{
                "type" => "paragraph",
                "content" => [%{"type" => "text", "text" => String.duplicate("word ", 500)}]
              }
            ]
          },
          published_at: DateTime.add(now, -i * 3600, :second),
          view_count: 1000 * i,
          bux_earned: 500 * i,
          base_bux_reward: 10,
          featured_image: "https://example.com/img-#{i}.jpg",
          author_id: author.id,
          category_id: category.id,
          hub_id: hub.id
        })
      end

    # Create a post in the related category
    Repo.insert!(%Post{
      title: "Related Article",
      slug: "related-article-#{unique}",
      content: %{"type" => "doc", "content" => []},
      published_at: now,
      view_count: 100,
      bux_earned: 50,
      base_bux_reward: 5,
      author_id: author.id,
      category_id: related_category.id,
      hub_id: hub.id
    })

    %{
      category: category,
      related_category: related_category,
      hub: hub,
      author: author,
      posts: posts
    }
  end

  describe "page render · anonymous" do
    test "renders the category page at /category/:slug", %{conn: conn, category: cat} do
      {:ok, _view, html} = live(conn, "/category/#{cat.slug}")

      assert html =~ cat.name
      assert html =~ "Category"
    end

    test "renders the design system header", %{conn: conn, category: cat} do
      {:ok, _view, html} = live(conn, "/category/#{cat.slug}")

      assert html =~ "ds-site-header"
    end

    test "renders the design system footer", %{conn: conn, category: cat} do
      {:ok, _view, html} = live(conn, "/category/#{cat.slug}")

      # Footer mission line — sentinel for the redesigned dark <.footer />.
      assert html =~ "Hustle hard. All in on crypto."
    end

    test "renders page hero with category name and description", %{conn: conn, category: cat} do
      {:ok, _view, html} = live(conn, "/category/#{cat.slug}")

      assert html =~ cat.name
      assert html =~ "Category · #{cat.name}"
      assert html =~ "Lending, AMMs, perps"
    end

    test "renders stat cards in page hero", %{conn: conn, category: cat} do
      {:ok, _view, html} = live(conn, "/category/#{cat.slug}")

      assert html =~ "Posts"
      assert html =~ "Readers"
      assert html =~ "BUX paid"
      assert html =~ "in this category"
    end

    test "renders featured post section", %{conn: conn, category: cat} do
      {:ok, _view, html} = live(conn, "/category/#{cat.slug}")

      # The featured post is the latest one (Article 1, published most recently)
      assert html =~ "TestCat Article 1"
      assert html =~ "Editor"
    end

    test "renders filter chips", %{conn: conn, category: cat} do
      {:ok, _view, html} = live(conn, "/category/#{cat.slug}")

      assert html =~ "Trending"
      assert html =~ "Latest"
      assert html =~ "Most earned"
      assert html =~ "Long reads"
    end

    test "renders mosaic grid with posts", %{conn: conn, category: cat} do
      {:ok, _view, html} = live(conn, "/category/#{cat.slug}")

      # Posts appear in the grid (excluding featured which is Article 1)
      assert html =~ "TestCat Article 2"
      assert html =~ "TestCat Article 3"
    end

    test "renders related categories section", %{conn: conn, category: cat, related_category: related} do
      {:ok, _view, html} = live(conn, "/category/#{cat.slug}")

      assert html =~ "Browse other categories"
      assert html =~ "If you like #{cat.name}"
      assert html =~ related.name
    end

    test "renders featured author card", %{conn: conn, category: cat} do
      {:ok, _view, html} = live(conn, "/category/#{cat.slug}")

      assert html =~ "Featured writer"
      assert html =~ "Jamie Chen"
      assert html =~ "#{cat.name} coverage"
    end

    test "featured author card shows stats", %{conn: conn, category: cat} do
      {:ok, _view, html} = live(conn, "/category/#{cat.slug}")

      assert html =~ "Posts"
      assert html =~ "Reads"
      assert html =~ "BUX paid out"
    end

    test "renders section header with story count", %{conn: conn, category: cat} do
      {:ok, _view, html} = live(conn, "/category/#{cat.slug}")

      assert html =~ "stories"
      assert html =~ "All #{cat.name} posts"
    end
  end

  describe "category not found" do
    test "redirects to / for nonexistent category", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/", flash: %{"error" => "Category not found"}}}} =
               live(conn, "/category/nonexistent-#{System.unique_integer([:positive])}")
    end
  end

  describe "page render · logged in" do
    setup %{conn: conn, author: author} do
      %{conn: log_in_user(conn, author)}
    end

    test "renders the category page when logged in", %{conn: conn, category: cat} do
      {:ok, _view, html} = live(conn, "/category/#{cat.slug}")

      assert html =~ cat.name
      assert html =~ "ds-site-header"
    end
  end
end
