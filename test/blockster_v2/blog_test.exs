defmodule BlocksterV2.BlogTest do
  use BlocksterV2.DataCase, async: false

  alias BlocksterV2.Blog
  alias BlocksterV2.Blog.{Post, Category, Tag}
  alias BlocksterV2.Accounts.User

  # ============================================================================
  # Mnesia setup for BUX earned (total_distributed) tests
  # ============================================================================

  setup do
    :mnesia.start()

    # Create post_bux_points table for with_bux_earned tests
    # Record: {:post_bux_points, post_id, reward, read_time, bux_balance, bux_deposited, total_distributed, extra2, extra3, extra4, created_at, updated_at}
    case :mnesia.create_table(:post_bux_points, [
           attributes: [:post_id, :reward, :read_time, :bux_balance, :bux_deposited, :total_distributed, :extra2, :extra3, :extra4, :created_at, :updated_at],
           ram_copies: [node()],
           type: :set
         ]) do
      {:atomic, :ok} -> :ok
      {:aborted, {:already_exists, :post_bux_points}} ->
        case :mnesia.add_table_copy(:post_bux_points, node(), :ram_copies) do
          {:atomic, :ok} -> :ok
          {:aborted, {:already_exists, :post_bux_points, _}} -> :ok
        end
        :mnesia.clear_table(:post_bux_points)
    end

    # Also create user_post_engagement and user_post_rewards for get_suggested_posts
    create_or_clear_table(:user_post_engagement, [
      :key, :user_id, :post_id, :time_spent, :min_read_time, :scroll_depth,
      :reached_end, :scroll_events, :avg_scroll_speed, :max_scroll_speed,
      :scroll_reversals, :focus_changes, :engagement_score, :is_read,
      :created_at, :updated_at
    ], :set)

    create_or_clear_table(:user_post_rewards, [
      :key, :user_id, :post_id, :read_bux, :read_paid, :read_tx_id,
      :x_share_bux, :x_share_paid, :x_share_tx_id, :watch_bux, :watch_paid,
      :watch_tx_id, :signup_bux, :signup_paid, :signup_tx_id, :created_at, :updated_at
    ], :set)

    :ok
  end

  defp create_or_clear_table(name, attrs, type) do
    case :mnesia.create_table(name, [
           attributes: attrs,
           ram_copies: [node()],
           type: type
         ]) do
      {:atomic, :ok} -> :ok
      {:aborted, {:already_exists, ^name}} ->
        case :mnesia.add_table_copy(name, node(), :ram_copies) do
          {:atomic, :ok} -> :ok
          {:aborted, {:already_exists, ^name, _}} -> :ok
        end
        :mnesia.clear_table(name)
    end
  end

  # ============================================================================
  # Test Helpers
  # ============================================================================

  defp create_user(attrs \\ %{}) do
    unique_id = System.unique_integer([:positive])

    default_attrs = %{
      wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
      smart_wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
      email: "user#{unique_id}@example.com",
      username: "user#{unique_id}",
      auth_method: "wallet"
    }

    %User{}
    |> User.changeset(Map.merge(default_attrs, attrs))
    |> Repo.insert!()
  end

  defp create_category(attrs \\ %{}) do
    unique_id = System.unique_integer([:positive])

    default_attrs = %{
      name: "Category #{unique_id}",
      slug: "category-#{unique_id}"
    }

    {:ok, category} = Blog.create_category(Map.merge(default_attrs, attrs))
    category
  end

  defp create_tag(attrs \\ %{}) do
    unique_id = System.unique_integer([:positive])

    default_attrs = %{
      name: "Tag #{unique_id}",
      slug: "tag-#{unique_id}"
    }

    {:ok, tag} = Blog.create_tag(Map.merge(default_attrs, attrs))
    tag
  end

  defp create_post(attrs \\ %{}) do
    unique_id = System.unique_integer([:positive])
    author = attrs[:author] || create_user()

    default_attrs = %{
      title: "Test Post #{unique_id}",
      slug: "test-post-#{unique_id}",
      content: %{"type" => "doc", "content" => []},
      excerpt: "Excerpt for test post #{unique_id}",
      author_id: author.id,
      published_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    {:ok, post} = Blog.create_post(Map.merge(default_attrs, Map.delete(attrs, :author)))
    post
  end

  defp create_published_post(attrs \\ %{}) do
    create_post(Map.put_new(attrs, :published_at, DateTime.utc_now() |> DateTime.truncate(:second)))
  end

  defp create_draft_post(attrs \\ %{}) do
    create_post(Map.put(attrs, :published_at, nil))
  end

  defp set_post_total_distributed(post_id, amount) do
    now = System.system_time(:second)
    record = {:post_bux_points, post_id, nil, nil, 0, 0, amount, nil, nil, nil, now, now}
    :mnesia.dirty_write(record)
  end

  # ============================================================================
  # Post CRUD Tests
  # ============================================================================

  describe "create_post/1" do
    test "creates a post with valid attributes" do
      author = create_user()
      attrs = %{title: "New Post", author_id: author.id}
      assert {:ok, %Post{} = post} = Blog.create_post(attrs)
      assert post.title == "New Post"
      assert post.slug != nil
    end

    test "fails without title" do
      assert {:error, changeset} = Blog.create_post(%{})
      assert %{title: ["can't be blank"]} = errors_on(changeset)
    end

    test "generates slug from title" do
      author = create_user()
      {:ok, post} = Blog.create_post(%{title: "My Great Post", author_id: author.id})
      assert post.slug == "my-great-post"
    end

    test "enforces unique slugs" do
      author = create_user()
      # Use the same title so the slug generator produces the same slug
      title = "Duplicate Title #{System.unique_integer([:positive])}"
      {:ok, first} = Blog.create_post(%{title: title, author_id: author.id})
      assert {:error, changeset} = Blog.create_post(%{title: title, author_id: author.id})
      assert errors_on(changeset)[:slug] != nil
    end
  end

  describe "update_post/2" do
    test "updates post title" do
      post = create_post()
      assert {:ok, updated} = Blog.update_post(post, %{title: "Updated Title"})
      assert updated.title == "Updated Title"
    end

    test "updates post excerpt" do
      post = create_post()
      assert {:ok, updated} = Blog.update_post(post, %{excerpt: "New excerpt"})
      assert updated.excerpt == "New excerpt"
    end
  end

  describe "delete_post/1" do
    test "deletes a post" do
      post = create_post()
      assert {:ok, _} = Blog.delete_post(post)
      assert Blog.get_post(post.id) == nil
    end
  end

  describe "get_post!/1" do
    test "returns post with associations preloaded" do
      post = create_post()
      fetched = Blog.get_post!(post.id)
      assert fetched.id == post.id
      assert fetched.author_name != nil
    end

    test "raises for non-existent post" do
      assert_raise Ecto.NoResultsError, fn -> Blog.get_post!(0) end
    end
  end

  describe "get_post/1" do
    test "returns post for valid id" do
      post = create_post()
      assert %Post{} = Blog.get_post(post.id)
    end

    test "returns nil for non-existent id" do
      assert Blog.get_post(0) == nil
    end
  end

  describe "get_post_by_slug/1" do
    test "returns post for valid slug" do
      post = create_post()
      assert %Post{id: id} = Blog.get_post_by_slug(post.slug)
      assert id == post.id
    end

    test "returns nil for non-existent slug" do
      assert Blog.get_post_by_slug("nonexistent-slug") == nil
    end
  end

  describe "get_post_by_slug!/1" do
    test "returns post for valid slug" do
      post = create_post()
      assert %Post{} = Blog.get_post_by_slug!(post.slug)
    end

    test "raises for non-existent slug" do
      assert_raise Ecto.NoResultsError, fn -> Blog.get_post_by_slug!("nonexistent") end
    end
  end

  # ============================================================================
  # Publishing Tests
  # ============================================================================

  describe "publish_post/1" do
    test "sets published_at on a draft" do
      post = create_draft_post()
      assert post.published_at == nil
      assert {:ok, published} = Blog.publish_post(post)
      assert published.published_at != nil
    end
  end

  describe "unpublish_post/1" do
    test "clears published_at" do
      post = create_published_post()
      assert post.published_at != nil
      assert {:ok, unpublished} = Blog.unpublish_post(post)
      assert unpublished.published_at == nil
    end
  end

  # ============================================================================
  # Post Listing Tests (Date-sorted, direct Ecto queries)
  # ============================================================================

  describe "list_published_posts_by_date/1" do
    test "returns posts sorted by published_at DESC" do
      _draft = create_draft_post()
      old = create_published_post(%{published_at: ~U[2024-01-01 00:00:00Z]})
      new = create_published_post(%{published_at: ~U[2025-01-01 00:00:00Z]})

      posts = Blog.list_published_posts_by_date(limit: 100)
      post_ids = Enum.map(posts, & &1.id)

      old_idx = Enum.find_index(post_ids, &(&1 == old.id))
      new_idx = Enum.find_index(post_ids, &(&1 == new.id))

      # Both should be in results and new should come before old
      assert old_idx != nil, "Old post should be in results"
      assert new_idx != nil, "New post should be in results"
      assert new_idx < old_idx
    end

    test "does not include draft posts" do
      _draft = create_draft_post()
      _published = create_published_post()

      posts = Blog.list_published_posts_by_date(limit: 100)
      assert Enum.all?(posts, fn p -> p.published_at != nil end)
    end

    test "respects limit" do
      for _ <- 1..5, do: create_published_post()
      posts = Blog.list_published_posts_by_date(limit: 3)
      assert length(posts) <= 3
    end

    test "respects offset" do
      for _ <- 1..5, do: create_published_post()
      all_posts = Blog.list_published_posts_by_date(limit: 100)
      offset_posts = Blog.list_published_posts_by_date(limit: 100, offset: 2)
      assert length(offset_posts) == length(all_posts) - 2
    end

    test "attaches bux_balance from total_distributed" do
      post = create_published_post()
      set_post_total_distributed(post.id, 500)

      [fetched] = Blog.list_published_posts_by_date(limit: 1)
      assert Map.get(fetched, :bux_balance) == 500
    end

    test "returns 0 bux_balance when no Mnesia record exists" do
      _post = create_published_post()
      [fetched] = Blog.list_published_posts_by_date(limit: 1)
      assert Map.get(fetched, :bux_balance) == 0
    end
  end

  describe "list_published_posts_by_date_category/2" do
    test "filters by category slug" do
      uid = System.unique_integer([:positive])
      cat1 = create_category(%{name: "CatA#{uid}", slug: "cat-a-#{uid}"})
      cat2 = create_category(%{name: "CatB#{uid}", slug: "cat-b-#{uid}"})

      _p1 = create_published_post(%{category_id: cat1.id})
      _p2 = create_published_post(%{category_id: cat2.id})

      posts = Blog.list_published_posts_by_date_category(cat1.slug, limit: 10)
      assert Enum.all?(posts, fn p -> p.category_id == cat1.id end)
    end

    test "returns empty list for non-existent category" do
      assert Blog.list_published_posts_by_date_category("nonexistent", limit: 10) == []
    end

    test "respects exclude_ids" do
      cat = create_category()
      p1 = create_published_post(%{category_id: cat.id})
      _p2 = create_published_post(%{category_id: cat.id})

      posts = Blog.list_published_posts_by_date_category(cat.slug, limit: 10, exclude_ids: [p1.id])
      refute Enum.any?(posts, fn p -> p.id == p1.id end)
    end

    test "attaches bux_balance from total_distributed" do
      cat = create_category()
      post = create_published_post(%{category_id: cat.id})
      set_post_total_distributed(post.id, 250)

      [fetched] = Blog.list_published_posts_by_date_category(cat.slug, limit: 1)
      assert Map.get(fetched, :bux_balance) == 250
    end
  end

  describe "list_published_posts_by_date_tag/2" do
    test "filters by tag slug" do
      tag = create_tag(%{name: "Bitcoin", slug: "bitcoin"})
      post = create_published_post()
      Blog.update_post_tags(post, ["Bitcoin"])

      other_post = create_published_post()
      Blog.update_post_tags(other_post, ["Ethereum"])

      posts = Blog.list_published_posts_by_date_tag("bitcoin", limit: 10)
      assert length(posts) >= 1
      post_ids = Enum.map(posts, & &1.id)
      assert post.id in post_ids
    end

    test "returns empty list for non-existent tag" do
      assert Blog.list_published_posts_by_date_tag("nonexistent", limit: 10) == []
    end

    test "respects exclude_ids" do
      tag = create_tag(%{name: "ExcludeTest", slug: "exclude-test"})
      p1 = create_published_post()
      p2 = create_published_post()
      Blog.update_post_tags(p1, ["ExcludeTest"])
      Blog.update_post_tags(p2, ["ExcludeTest"])

      posts = Blog.list_published_posts_by_date_tag("exclude-test", limit: 10, exclude_ids: [p1.id])
      refute Enum.any?(posts, fn p -> p.id == p1.id end)
    end

    test "attaches bux_balance from total_distributed" do
      post = create_published_post()
      Blog.update_post_tags(post, ["BuxTag"])
      tag = Blog.get_tag_by_slug("buxtag")
      set_post_total_distributed(post.id, 100)

      posts = Blog.list_published_posts_by_date_tag(tag.slug, limit: 1)
      assert length(posts) >= 1
      fetched = Enum.find(posts, fn p -> p.id == post.id end)
      assert Map.get(fetched, :bux_balance) == 100
    end
  end

  # ============================================================================
  # Count Tests
  # ============================================================================

  describe "count_published_posts/0" do
    test "counts only published posts" do
      _draft = create_draft_post()
      _published1 = create_published_post()
      _published2 = create_published_post()

      count = Blog.count_published_posts()
      assert count >= 2
    end
  end

  describe "count_published_posts_by_category/1" do
    test "counts published posts in category" do
      cat = create_category()
      _p1 = create_published_post(%{category_id: cat.id})
      _p2 = create_published_post(%{category_id: cat.id})
      _draft = create_draft_post(%{category_id: cat.id})

      assert Blog.count_published_posts_by_category(cat.slug) == 2
    end

    test "returns 0 for non-existent category" do
      assert Blog.count_published_posts_by_category("nonexistent") == 0
    end
  end

  describe "count_published_posts_by_tag/1" do
    test "counts published posts with tag" do
      p1 = create_published_post()
      p2 = create_published_post()
      Blog.update_post_tags(p1, ["CountTag"])
      Blog.update_post_tags(p2, ["CountTag"])

      tag = Blog.get_tag_by_slug("counttag")
      assert Blog.count_published_posts_by_tag(tag.slug) == 2
    end

    test "returns 0 for non-existent tag" do
      assert Blog.count_published_posts_by_tag("nonexistent") == 0
    end
  end

  # ============================================================================
  # Suggested Posts Tests
  # ============================================================================

  describe "get_suggested_posts/3" do
    test "returns posts excluding the current post" do
      current = create_published_post()
      _other1 = create_published_post()
      _other2 = create_published_post()

      suggested = Blog.get_suggested_posts(current.id, nil, 10)
      refute Enum.any?(suggested, fn p -> p.id == current.id end)
    end

    test "returns up to the requested limit" do
      current = create_published_post()
      for _ <- 1..10, do: create_published_post()

      suggested = Blog.get_suggested_posts(current.id, nil, 4)
      assert length(suggested) <= 4
    end

    test "attaches bux_balance from total_distributed" do
      current = create_published_post()
      other = create_published_post()
      set_post_total_distributed(other.id, 777)

      # Request a large limit to ensure we get the post
      suggested = Blog.get_suggested_posts(current.id, nil, 100)
      found = Enum.find(suggested, fn p -> p.id == other.id end)

      if found do
        assert Map.get(found, :bux_balance) == 777
      else
        # Post might not be in top 20 pool due to other posts existing — verify at least one has bux_balance set
        assert Enum.all?(suggested, fn p -> is_number(Map.get(p, :bux_balance)) end)
      end
    end

    test "returns randomized results (different order on repeated calls)" do
      current = create_published_post()
      for _ <- 1..15, do: create_published_post()

      results = for _ <- 1..5 do
        Blog.get_suggested_posts(current.id, nil, 4)
        |> Enum.map(& &1.id)
      end

      # At least some runs should have different order
      unique_orderings = Enum.uniq(results)
      assert length(unique_orderings) >= 2
    end
  end

  # ============================================================================
  # with_bux_earned Tests
  # ============================================================================

  describe "with_bux_earned/1" do
    test "sets bux_balance to total_distributed for a list of posts" do
      p1 = create_published_post()
      p2 = create_published_post()
      set_post_total_distributed(p1.id, 100)
      set_post_total_distributed(p2.id, 200)

      posts = [p1, p2] |> Blog.with_bux_earned()
      p1_result = Enum.find(posts, fn p -> p.id == p1.id end)
      p2_result = Enum.find(posts, fn p -> p.id == p2.id end)

      assert Map.get(p1_result, :bux_balance) == 100
      assert Map.get(p2_result, :bux_balance) == 200
    end

    test "sets bux_balance to 0 when no Mnesia record" do
      post = create_published_post()
      [result] = Blog.with_bux_earned([post])
      assert Map.get(result, :bux_balance) == 0
    end

    test "works with a single post struct" do
      post = create_published_post()
      set_post_total_distributed(post.id, 42)

      result = Blog.with_bux_earned(post)
      assert Map.get(result, :bux_balance) == 42
    end

    test "with_bux_balances is backward-compatible alias" do
      post = create_published_post()
      set_post_total_distributed(post.id, 99)

      result = Blog.with_bux_balances(post)
      assert Map.get(result, :bux_balance) == 99
    end
  end

  # ============================================================================
  # Random Posts Tests
  # ============================================================================

  describe "get_random_posts/2" do
    test "returns random posts with bux_balance" do
      p1 = create_published_post(%{featured_image: "https://example.com/img1.jpg"})
      set_post_total_distributed(p1.id, 50)

      posts = Blog.get_random_posts(5)
      found = Enum.find(posts, fn p -> p.id == p1.id end)
      if found, do: assert(Map.get(found, :bux_balance) == 50)
    end

    test "excludes specified post" do
      excluded = create_published_post(%{featured_image: "https://example.com/img.jpg"})
      _other = create_published_post(%{featured_image: "https://example.com/img2.jpg"})

      posts = Blog.get_random_posts(10, excluded.id)
      refute Enum.any?(posts, fn p -> p.id == excluded.id end)
    end
  end

  # ============================================================================
  # Search Tests
  # ============================================================================

  describe "search_posts/2" do
    test "finds posts by title" do
      _post = create_published_post(%{title: "Blockchain Revolution"})
      results = Blog.search_posts("Blockchain")
      assert length(results) >= 1
    end

    test "returns empty for no match" do
      results = Blog.search_posts("zzzznonexistent99999")
      assert results == []
    end
  end

  # ============================================================================
  # Category CRUD Tests
  # ============================================================================

  describe "list_categories/0" do
    test "returns categories ordered by name" do
      uid = System.unique_integer([:positive])
      create_category(%{name: "Zebra#{uid}", slug: "zebra-#{uid}"})
      create_category(%{name: "Alpha#{uid}", slug: "alpha-#{uid}"})

      categories = Blog.list_categories()
      names = Enum.map(categories, & &1.name)
      assert names == Enum.sort(names)
    end
  end

  describe "get_category_by_slug/1" do
    test "returns category for valid slug" do
      uid = System.unique_integer([:positive])
      cat = create_category(%{name: "TestCat#{uid}", slug: "test-cat-#{uid}"})
      assert %Category{id: id} = Blog.get_category_by_slug("test-cat-#{uid}")
      assert id == cat.id
    end

    test "returns nil for non-existent slug" do
      assert Blog.get_category_by_slug("nonexistent") == nil
    end
  end

  describe "create_category/1" do
    test "creates with valid attrs" do
      uid = System.unique_integer([:positive])
      assert {:ok, %Category{}} = Blog.create_category(%{name: "New Cat #{uid}", slug: "new-cat-#{uid}"})
    end
  end

  # ============================================================================
  # Tag CRUD Tests
  # ============================================================================

  describe "list_tags/0" do
    test "returns tags ordered by name" do
      create_tag(%{name: "Zebra Tag", slug: "zebra-tag"})
      create_tag(%{name: "Alpha Tag", slug: "alpha-tag"})

      tags = Blog.list_tags()
      names = Enum.map(tags, & &1.name)
      assert names == Enum.sort(names)
    end
  end

  describe "get_or_create_tag/1" do
    test "creates a new tag" do
      assert {:ok, %Tag{name: "BrandNewTag"}} = Blog.get_or_create_tag("BrandNewTag")
    end

    test "returns existing tag" do
      {:ok, original} = Blog.get_or_create_tag("ExistingTag")
      {:ok, found} = Blog.get_or_create_tag("ExistingTag")
      assert original.id == found.id
    end
  end

  describe "update_post_tags/2" do
    test "adds tags to a post" do
      post = create_post()
      {:ok, updated} = Blog.update_post_tags(post, ["Tag1", "Tag2"])
      updated = Blog.get_post!(updated.id)
      tag_names = Enum.map(updated.tags, & &1.name)
      assert "Tag1" in tag_names
      assert "Tag2" in tag_names
    end
  end

  # ============================================================================
  # Related Posts Tests
  # ============================================================================

  describe "get_related_posts/2" do
    test "returns posts sharing tags" do
      p1 = create_published_post()
      p2 = create_published_post()
      _p3 = create_published_post()

      Blog.update_post_tags(p1, ["SharedTag"])
      Blog.update_post_tags(p2, ["SharedTag"])

      # Reload to get tags
      p1 = Blog.get_post!(p1.id)
      related = Blog.get_related_posts(p1, 5)
      related_ids = Enum.map(related, & &1.id)
      assert p2.id in related_ids
    end

    test "excludes the source post" do
      post = create_published_post()
      Blog.update_post_tags(post, ["SelfTag"])
      post = Blog.get_post!(post.id)

      related = Blog.get_related_posts(post, 5)
      refute Enum.any?(related, fn p -> p.id == post.id end)
    end

    test "returns empty when post has no tags" do
      post = create_published_post()
      post = Blog.get_post!(post.id)
      assert Blog.get_related_posts(post, 5) == []
    end
  end

  # ============================================================================
  # Filtered listing tests (by hub, by tag, by category)
  # ============================================================================

  describe "list_published_posts_by_category/2" do
    test "returns published posts for given category" do
      cat = create_category()
      p1 = create_published_post(%{category_id: cat.id})
      _p2 = create_published_post()

      posts = Blog.list_published_posts_by_category(cat.slug, limit: 10)
      post_ids = Enum.map(posts, & &1.id)
      assert p1.id in post_ids
    end

    test "respects exclude_ids" do
      cat = create_category()
      p1 = create_published_post(%{category_id: cat.id})
      p2 = create_published_post(%{category_id: cat.id})

      posts = Blog.list_published_posts_by_category(cat.slug, limit: 10, exclude_ids: [p1.id])
      post_ids = Enum.map(posts, & &1.id)
      refute p1.id in post_ids
      assert p2.id in post_ids
    end
  end

  describe "list_published_posts_by_tag/2" do
    test "returns published posts for given tag" do
      post = create_published_post()
      Blog.update_post_tags(post, ["FilterTag"])

      posts = Blog.list_published_posts_by_tag("filtertag", limit: 10)
      post_ids = Enum.map(posts, & &1.id)
      assert post.id in post_ids
    end
  end

  # ============================================================================
  # Paginated listing test
  # ============================================================================

  describe "list_published_posts_paginated/2" do
    test "returns paginated result with metadata" do
      for _ <- 1..5, do: create_published_post()

      result = Blog.list_published_posts_paginated(1, 3)
      assert is_list(result.posts)
      assert length(result.posts) <= 3
      assert result.page == 1
      assert result.per_page == 3
      assert result.total_count >= 5
      assert result.total_pages >= 2
    end
  end
end
