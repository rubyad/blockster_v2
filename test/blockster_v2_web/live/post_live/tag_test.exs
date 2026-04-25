defmodule BlocksterV2Web.PostLive.TagTest do
  @moduledoc """
  Tests for the redesigned Tag Browse page (Wave 5 Page #17).

  Route: /tag/:slug
  LiveView: BlocksterV2Web.PostLive.Tag
  Mock: docs/solana/tag_mock.html

  Tests cover: DS header/footer, compact hero with stats, filter chips,
  3-col post grid with hub badges + BUX pills, related tags chip cloud,
  tag-not-found redirect, anonymous + logged-in access.
  """

  use BlocksterV2Web.LiveCase, async: false

  alias BlocksterV2.Repo
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

    # Create the target tag with unique slug
    {:ok, tag} =
      BlocksterV2.Blog.get_or_create_tag("TestTag#{unique}")

    # Create a related tag
    {:ok, related_tag} =
      BlocksterV2.Blog.get_or_create_tag("RelatedTag#{unique}")

    # Create an author
    author =
      Repo.insert!(%User{
        wallet_address: "TestTagAuthor#{System.unique_integer([:positive])}",
        username: "TagAuthor#{unique}",
        bio: "Test tag author.",
        auth_method: "wallet"
      })

    # Create posts tagged with the target tag
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    posts =
      for i <- 1..5 do
        post =
          Repo.insert!(%Post{
            title: "TagArticle#{unique} #{i}",
            slug: "tagarticle-#{unique}-#{i}",
            excerpt: "Excerpt for tag article #{i}",
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
            featured_image: "https://example.com/tag-img-#{i}.jpg",
            author_id: author.id,
            hub_id: hub.id
          })

        # Associate post with the target tag
        BlocksterV2.Blog.update_post_tags(post, [tag.name])
        post
      end

    # Create a post tagged with the related tag (so it shows up in related)
    related_post =
      Repo.insert!(%Post{
        title: "RelatedTagArticle#{unique}",
        slug: "relatedtagarticle-#{unique}",
        content: %{"type" => "doc", "content" => []},
        published_at: now,
        view_count: 100,
        bux_earned: 50,
        base_bux_reward: 5,
        author_id: author.id,
        hub_id: hub.id
      })

    BlocksterV2.Blog.update_post_tags(related_post, [related_tag.name])

    %{
      tag: tag,
      related_tag: related_tag,
      hub: hub,
      author: author,
      posts: posts
    }
  end

  describe "page render · anonymous" do
    test "renders the tag page at /tag/:slug", %{conn: conn, tag: tag} do
      {:ok, _view, html} = live(conn, "/tag/#{tag.slug}")

      assert html =~ tag.name
      assert html =~ "Tag"
    end

    test "renders the design system header", %{conn: conn, tag: tag} do
      {:ok, _view, html} = live(conn, "/tag/#{tag.slug}")

      assert html =~ "ds-site-header"
    end

    test "renders the design system footer", %{conn: conn, tag: tag} do
      {:ok, _view, html} = live(conn, "/tag/#{tag.slug}")

      # Footer mission line — sentinel for the redesigned dark <.footer />.
      assert html =~ "Hustle hard. All in on crypto."
    end

    test "renders compact hero with tag name and hash prefix", %{conn: conn, tag: tag} do
      {:ok, _view, html} = live(conn, "/tag/#{tag.slug}")

      assert html =~ "##{tag.name}"
    end

    test "renders stats line in hero", %{conn: conn, tag: tag} do
      {:ok, _view, html} = live(conn, "/tag/#{tag.slug}")

      assert html =~ "posts"
      assert html =~ "reads"
    end

    test "renders filter chips", %{conn: conn, tag: tag} do
      {:ok, _view, html} = live(conn, "/tag/#{tag.slug}")

      assert html =~ "Latest"
      assert html =~ "Popular"
      assert html =~ "Most earned"
      assert html =~ "Long reads"
    end

    test "renders post grid with posts", %{conn: conn, tag: tag, posts: posts} do
      {:ok, _view, html} = live(conn, "/tag/#{tag.slug}")

      # Posts appear in the grid
      first_post = List.first(posts)
      assert html =~ first_post.title
    end

    test "post cards show hub badge", %{conn: conn, tag: tag, hub: hub} do
      {:ok, _view, html} = live(conn, "/tag/#{tag.slug}")

      assert html =~ hub.name
    end

    test "post cards show BUX reward pill", %{conn: conn, tag: tag} do
      {:ok, _view, html} = live(conn, "/tag/#{tag.slug}")

      # BUX pill — the blockster icon is present
      assert html =~ "blockster-icon.png"
    end

    test "renders related tags section", %{conn: conn, tag: tag, related_tag: related_tag} do
      {:ok, _view, html} = live(conn, "/tag/#{tag.slug}")

      assert html =~ "Related tags"
      assert html =~ "More like ##{tag.name}"
      assert html =~ related_tag.name
    end

    test "renders post count in filter row", %{conn: conn, tag: tag} do
      {:ok, _view, html} = live(conn, "/tag/#{tag.slug}")

      # We have 5 posts
      assert html =~ "5 posts"
    end
  end

  describe "tag not found" do
    test "redirects to / for nonexistent tag", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/", flash: %{"error" => "Tag not found"}}}} =
               live(conn, "/tag/nonexistent-#{System.unique_integer([:positive])}")
    end
  end

  describe "page render · logged in" do
    setup %{conn: conn, author: author} do
      %{conn: log_in_user(conn, author)}
    end

    test "renders the tag page when logged in", %{conn: conn, tag: tag} do
      {:ok, _view, html} = live(conn, "/tag/#{tag.slug}")

      assert html =~ tag.name
      assert html =~ "ds-site-header"
    end
  end
end
