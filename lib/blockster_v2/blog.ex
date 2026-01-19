defmodule BlocksterV2.Blog do
  @moduledoc """
  The Blog context.
  """

  import Ecto.Query, warn: false
  alias BlocksterV2.Repo
  alias BlocksterV2.Blog.Post
  alias BlocksterV2.Blog.Tag
  alias BlocksterV2.Blog.Category
  alias BlocksterV2.Blog.Hub

  # Base queries with proper preloading

  @doc false
  defp posts_base_query do
    from p in Post,
      preload: [:author, :category, :hub, tags: ^from(t in Tag, order_by: t.name)],
      order_by: [desc: p.published_at]
  end

  @doc false
  defp published_posts_query do
    from p in posts_base_query(),
      where: not is_nil(p.published_at)
  end

  @doc false
  defp populate_author_names(posts) when is_list(posts) do
    Enum.map(posts, &Post.populate_author_name/1)
  end

  @doc false
  defp populate_author_names(%Post{} = post) do
    Post.populate_author_name(post)
  end

  # Post listing functions

  @doc """
  Returns the list of published posts with all associations loaded.

  ## Options
    * `:limit` - Maximum number of posts to return
    * `:offset` - Number of posts to skip

  ## Examples
      iex> list_published_posts()
      [%Post{}, ...]

      iex> list_published_posts(limit: 10, offset: 20)
      [%Post{}, ...]
  """
  def list_published_posts(opts \\ []) do
    limit = Keyword.get(opts, :limit)
    offset = Keyword.get(opts, :offset, 0)

    published_posts_query()
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
    |> populate_author_names()
  end

  @doc """
  Returns a paginated list of published posts with metadata.

  ## Examples
      iex> list_published_posts_paginated(1, 20)
      %{
        posts: [%Post{}, ...],
        page: 1,
        per_page: 20,
        total_count: 45,
        total_pages: 3
      }
  """
  def list_published_posts_paginated(page \\ 1, per_page \\ 20) do
    offset = (page - 1) * per_page

    posts = published_posts_query()
      |> limit(^per_page)
      |> offset(^offset)
      |> Repo.all()
      |> populate_author_names()

    total_count = from(p in Post,
      where: not is_nil(p.published_at),
      select: count(p.id)
    ) |> Repo.one()

    %{
      posts: posts,
      page: page,
      per_page: per_page,
      total_count: total_count,
      total_pages: ceil(total_count / per_page)
    }
  end

  @doc """
  Returns the list of published posts filtered by tag slug.
  Uses association joins for efficiency.
  """
  def list_published_posts_by_tag(tag_slug, opts \\ []) do
    limit = Keyword.get(opts, :limit)
    exclude_ids = Keyword.get(opts, :exclude_ids, [])

    query =
      from(p in Post,
        join: t in assoc(p, :tags),
        where: not is_nil(p.published_at),
        where: t.slug == ^tag_slug,
        order_by: [desc: p.published_at],
        limit: ^limit,
        preload: [:author, :category, :hub, tags: ^from(t in Tag, order_by: t.name)]
      )

    query =
      if exclude_ids != [] do
        from(p in query, where: p.id not in ^exclude_ids)
      else
        query
      end

    query
    |> Repo.all()
    |> populate_author_names()
  end

  @doc """
  Returns the list of published posts filtered by category slug.
  Uses association joins for efficiency.
  """
  def list_published_posts_by_category(category_slug, opts \\ []) do
    limit = Keyword.get(opts, :limit)
    exclude_ids = Keyword.get(opts, :exclude_ids, [])

    query =
      from(p in Post,
        join: c in assoc(p, :category),
        where: not is_nil(p.published_at),
        where: c.slug == ^category_slug,
        order_by: [desc: p.published_at],
        limit: ^limit,
        preload: [:author, :category, :hub, tags: ^from(t in Tag, order_by: t.name)]
      )

    query =
      if exclude_ids != [] do
        from(p in query, where: p.id not in ^exclude_ids)
      else
        query
      end

    query
    |> Repo.all()
    |> populate_author_names()
  end

  @doc """
  Returns the list of published posts filtered by hub_id.
  """
  def list_published_posts_by_hub(hub_id, opts \\ []) do
    limit = Keyword.get(opts, :limit)
    exclude_ids = Keyword.get(opts, :exclude_ids, [])

    # Get the hub to access its tag_name
    hub = get_hub(hub_id)

    query = if hub && hub.tag_name do
      # Find posts that either have this hub_id OR have a tag matching the hub's tag_name
      from(p in Post,
        left_join: pt in "post_tags", on: pt.post_id == p.id,
        left_join: t in Tag, on: t.id == pt.tag_id,
        where: not is_nil(p.published_at),
        where: p.hub_id == ^hub_id or t.name == ^hub.tag_name,
        distinct: p.id,
        order_by: [desc: p.published_at],
        limit: ^limit,
        preload: [:author, :category, :hub, tags: ^from(t in Tag, order_by: t.name)]
      )
    else
      # Fallback to just hub_id if hub doesn't have a tag_name
      from(p in Post,
        where: not is_nil(p.published_at),
        where: p.hub_id == ^hub_id,
        order_by: [desc: p.published_at],
        limit: ^limit,
        preload: [:author, :category, :hub, tags: ^from(t in Tag, order_by: t.name)]
      )
    end

    query =
      if exclude_ids != [] do
        from(p in query, where: p.id not in ^exclude_ids)
      else
        query
      end

    query
    |> Repo.all()
    |> populate_author_names()
  end

  @doc """
  Returns the list of all posts (including unpublished) with all associations loaded.
  """
  def list_posts do
    from(p in posts_base_query(),
      order_by: [desc: p.inserted_at]
    )
    |> Repo.all()
    |> populate_author_names()
  end

  @doc """
  Lists published posts sorted by BUX pool balance (highest first),
  then by published_at for posts with equal/zero balance.

  Uses SortedPostsCache for O(1) pagination instead of sorting on every request.

  ## Options
    * `:limit` - Maximum number of posts to return (default: 20)
    * `:offset` - Number of posts to skip (default: 0)

  ## Examples
      iex> list_published_posts_by_pool(limit: 20, offset: 0)
      [%Post{bux_balance: 500}, %Post{bux_balance: 300}, ...]
  """
  def list_published_posts_by_pool(opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    offset = Keyword.get(opts, :offset, 0)

    # Get sorted post IDs from cache (O(1) slice operation)
    sorted_ids_with_balances = BlocksterV2.SortedPostsCache.get_page(limit, offset)
    post_ids = Enum.map(sorted_ids_with_balances, fn {id, _balance} -> id end)
    balances_map = Map.new(sorted_ids_with_balances)

    if Enum.empty?(post_ids) do
      []
    else
      # Fetch only the posts we need from database
      posts = from(p in Post,
        where: p.id in ^post_ids,
        preload: [:author, :category, :hub, tags: ^from(t in Tag, order_by: t.name)]
      )
      |> Repo.all()
      |> populate_author_names()

      # Re-order posts to match sorted order and attach balance
      post_ids
      |> Enum.map(fn post_id ->
        post = Enum.find(posts, fn p -> p.id == post_id end)
        if post do
          Map.put(post, :bux_balance, Map.get(balances_map, post_id, 0))
        end
      end)
      |> Enum.reject(&is_nil/1)
    end
  end

  @doc """
  Gets the total count of published posts (for pagination UI).
  Uses SortedPostsCache for O(1) lookup.
  """
  def count_published_posts do
    BlocksterV2.SortedPostsCache.count()
  end

  @doc """
  Lists published posts for a category sorted by BUX pool balance DESC.
  Uses SortedPostsCache for O(n) filter + O(1) pagination.

  ## Options
    * `:limit` - Maximum number of posts to return (default: 20)
    * `:offset` - Number of posts to skip (default: 0)
    * `:exclude_ids` - List of post IDs to exclude (default: [])
  """
  def list_published_posts_by_category_pool(category_slug, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    offset = Keyword.get(opts, :offset, 0)
    exclude_ids = Keyword.get(opts, :exclude_ids, [])

    # Get category by slug
    case get_category_by_slug(category_slug) do
      nil ->
        []

      category ->
        # Get sorted post IDs from cache
        # Fetch extra to account for exclusions
        fetch_limit = limit + length(exclude_ids)
        sorted_ids_with_balances = BlocksterV2.SortedPostsCache.get_page_by_category(
          category.id,
          fetch_limit,
          offset
        )

        # Filter out excluded IDs and take the limit
        filtered = sorted_ids_with_balances
          |> Enum.reject(fn {id, _} -> id in exclude_ids end)
          |> Enum.take(limit)

        post_ids = Enum.map(filtered, fn {id, _} -> id end)
        balances_map = Map.new(filtered)

        if Enum.empty?(post_ids) do
          []
        else
          # Fetch posts from database
          posts = from(p in Post,
            where: p.id in ^post_ids,
            preload: [:author, :category, :hub, tags: ^from(t in Tag, order_by: t.name)]
          )
          |> Repo.all()
          |> populate_author_names()

          # Re-order to match sorted order and attach balance
          post_ids
          |> Enum.map(fn post_id ->
            post = Enum.find(posts, fn p -> p.id == post_id end)
            if post, do: Map.put(post, :bux_balance, Map.get(balances_map, post_id, 0))
          end)
          |> Enum.reject(&is_nil/1)
        end
    end
  end

  @doc """
  Lists published posts for a tag sorted by BUX pool balance DESC.
  Uses SortedPostsCache for O(n) filter + O(1) pagination.

  ## Options
    * `:limit` - Maximum number of posts to return (default: 20)
    * `:offset` - Number of posts to skip (default: 0)
    * `:exclude_ids` - List of post IDs to exclude (default: [])
  """
  def list_published_posts_by_tag_pool(tag_slug, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    offset = Keyword.get(opts, :offset, 0)
    exclude_ids = Keyword.get(opts, :exclude_ids, [])

    # Get tag by slug
    case get_tag_by_slug(tag_slug) do
      nil ->
        []

      tag ->
        # Get sorted post IDs from cache
        # Fetch extra to account for exclusions
        fetch_limit = limit + length(exclude_ids)
        sorted_ids_with_balances = BlocksterV2.SortedPostsCache.get_page_by_tag(
          tag.id,
          fetch_limit,
          offset
        )

        # Filter out excluded IDs and take the limit
        filtered = sorted_ids_with_balances
          |> Enum.reject(fn {id, _} -> id in exclude_ids end)
          |> Enum.take(limit)

        post_ids = Enum.map(filtered, fn {id, _} -> id end)
        balances_map = Map.new(filtered)

        if Enum.empty?(post_ids) do
          []
        else
          # Fetch posts from database
          posts = from(p in Post,
            where: p.id in ^post_ids,
            preload: [:author, :category, :hub, tags: ^from(t in Tag, order_by: t.name)]
          )
          |> Repo.all()
          |> populate_author_names()

          # Re-order to match sorted order and attach balance
          post_ids
          |> Enum.map(fn post_id ->
            post = Enum.find(posts, fn p -> p.id == post_id end)
            if post, do: Map.put(post, :bux_balance, Map.get(balances_map, post_id, 0))
          end)
          |> Enum.reject(&is_nil/1)
        end
    end
  end

  @doc """
  Gets the count of published posts in a category.
  Uses SortedPostsCache for O(n) filter.
  """
  def count_published_posts_by_category(category_slug) do
    case get_category_by_slug(category_slug) do
      nil -> 0
      category -> BlocksterV2.SortedPostsCache.count_by_category(category.id)
    end
  end

  @doc """
  Gets the count of published posts with a tag.
  Uses SortedPostsCache for O(n) filter.
  """
  def count_published_posts_by_tag(tag_slug) do
    case get_tag_by_slug(tag_slug) do
      nil -> 0
      tag -> BlocksterV2.SortedPostsCache.count_by_tag(tag.id)
    end
  end

  @doc """
  Gets posts by a list of IDs. Returns only id, title, and slug for efficiency.
  """
  def get_posts_by_ids([]), do: []

  def get_posts_by_ids(post_ids) when is_list(post_ids) do
    from(p in Post,
      left_join: h in assoc(p, :hub),
      where: p.id in ^post_ids,
      select: %{id: p.id, title: p.title, slug: p.slug, hub_token: h.token}
    )
    |> Repo.all()
  end

  @doc """
  Searches published posts by title, excerpt, or author email.

  ## Examples
      iex> search_posts("blockchain")
      [%Post{}, ...]

      iex> search_posts("bitcoin", limit: 10)
      [%Post{}, ...]
  """
  def search_posts(query_string, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    search_term = "%#{query_string}%"

    from(p in published_posts_query(),
      left_join: a in assoc(p, :author),
      where: ilike(p.title, ^search_term) or
             ilike(p.excerpt, ^search_term) or
             ilike(a.email, ^search_term),
      limit: ^limit
    )
    |> Repo.all()
    |> populate_author_names()
  end

  @doc """
  Searches published posts using PostgreSQL full-text search.
  Returns posts ranked by relevance to the search query.

  ## Examples
      iex> search_posts_fulltext("blockchain technology")
      [%Post{}, ...]

      iex> search_posts_fulltext("bitcoin", limit: 10)
      [%Post{}, ...]
  """
  def search_posts_fulltext(query_string, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    # Convert query to support prefix matching
    # Split on spaces, add :* to each word for prefix matching, join with &
    tsquery = query_string
      |> String.split(~r/\s+/, trim: true)
      |> Enum.map(&"#{&1}:*")
      |> Enum.join(" & ")

    published_posts_query()
    |> exclude(:order_by)
    |> where([p], fragment(
        "searchable @@ to_tsquery('english', ?)",
        ^tsquery
      ))
    |> order_by([p], [
        desc: fragment(
          """
          CASE
            WHEN to_tsvector('english', COALESCE(?, '')) @@ to_tsquery('english', ?) THEN 100
            ELSE 0
          END + ts_rank_cd(searchable, to_tsquery('english', ?), 1)
          """,
          p.title,
          ^tsquery,
          ^tsquery
        ),
        desc: p.published_at
      ])
    |> limit(^limit)
    |> Repo.all()
    |> populate_author_names()
  end

  @doc """
  Gets a single post by slug with all associations loaded.
  Raises `Ecto.NoResultsError` if the Post does not exist.
  """
  def get_post_by_slug!(slug) do
    from(p in Post,
      where: p.slug == ^slug,
      preload: [:author, :category, :hub, tags: ^from(t in Tag, order_by: t.name)]
    )
    |> Repo.one!()
    |> populate_author_names()
  end

  @doc """
  Gets a single post with all associations loaded.
  Raises `Ecto.NoResultsError` if the Post does not exist.
  """
  def get_post!(id) do
    from(p in Post,
      where: p.id == ^id,
      preload: [:author, :category, :hub, tags: ^from(t in Tag, order_by: t.name)]
    )
    |> Repo.one!()
    |> populate_author_names()
  end

  @doc """
  Gets a single post with all associations loaded.
  Returns nil if the Post does not exist.
  """
  def get_post(id) do
    from(p in Post,
      where: p.id == ^id,
      preload: [:author, :category, :hub, tags: ^from(t in Tag, order_by: t.name)]
    )
    |> Repo.one()
    |> case do
      nil -> nil
      post -> populate_author_names(post)
    end
  end

  @doc """
  Gets related posts based on shared tags.
  Returns posts that share the most tags with the given post.

  ## Examples
      iex> get_related_posts(post, 5)
      [%Post{}, ...]
  """
  def get_related_posts(%Post{} = post, limit \\ 5) do
    tag_ids = case post.tags do
      %Ecto.Association.NotLoaded{} ->
        post = Repo.preload(post, :tags)
        Enum.map(post.tags, & &1.id)
      tags when is_list(tags) ->
        Enum.map(tags, & &1.id)
    end

    if Enum.empty?(tag_ids) do
      []
    else
      from(p in published_posts_query(),
        where: p.id != ^post.id,
        join: pt in "post_tags", on: pt.post_id == p.id,
        where: pt.tag_id in ^tag_ids,
        group_by: p.id,
        order_by: [desc: count(pt.tag_id), desc: p.published_at],
        limit: ^limit
      )
      |> Repo.all()
      |> populate_author_names()
    end
  end

  @doc """
  Creates a post.
  """
  def create_post(attrs \\ %{}) do
    %Post{}
    |> Post.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a post.
  """
  def update_post(%Post{} = post, attrs) do
    post
    |> Post.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a post.
  """
  def delete_post(%Post{} = post) do
    Repo.delete(post)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking post changes.
  """
  def change_post(%Post{} = post, attrs \\ %{}) do
    Post.changeset(post, attrs)
  end

  @doc """
  Publishes a post.
  """
  def publish_post(%Post{} = post) do
    post
    |> Post.publish()
    |> Repo.update()
  end

  @doc """
  Unpublishes a post.
  """
  def unpublish_post(%Post{} = post) do
    post
    |> Post.unpublish()
    |> Repo.update()
  end

  @doc """
  Increments the view count for a post.
  """
  def increment_view_count(%Post{} = post) do
    post
    |> Post.increment_view_count()
    |> Repo.update()
  end

  @doc """
  Updates post tags by tag names.
  """
  def update_post_tags(%Post{} = post, tag_names) when is_list(tag_names) do
    # Get or create all tags
    new_tags =
      Enum.map(tag_names, fn tag_name ->
        case get_or_create_tag(tag_name) do
          {:ok, tag} -> tag
          {:error, _} -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    # Merge with existing tags to avoid deletion
    post = Repo.preload(post, :tags)
    all_tags = (post.tags ++ new_tags) |> Enum.uniq_by(& &1.id)

    # Update the post's tags association
    post
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_assoc(:tags, all_tags)
    |> Repo.update()
  end

  @doc """
  Updates post tags by tag IDs (replaces existing tags).
  """
  def update_post_tags_by_ids(%Post{} = post, tag_ids) when is_list(tag_ids) do
    tags = Repo.all(from t in Tag, where: t.id in ^tag_ids)

    post
    |> Repo.preload(:tags)
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_assoc(:tags, tags)
    |> Repo.update()
  end

  # Category functions

  @doc """
  Returns the list of all categories ordered by name.
  """
  def list_categories do
    Category
    |> order_by([c], asc: c.name)
    |> Repo.all()
  end

  @doc """
  Gets a category by slug.
  """
  def get_category_by_slug(slug) do
    Repo.get_by(Category, slug: slug)
  end

  @doc """
  Gets a category by slug, raises if not found.
  """
  def get_category_by_slug!(slug) do
    Repo.get_by!(Category, slug: slug)
  end

  @doc """
  Creates a category.
  """
  def create_category(attrs \\ %{}) do
    %Category{}
    |> Category.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a category by id.
  """
  def get_category!(id), do: Repo.get!(Category, id)

  @doc """
  Updates a category.
  """
  def update_category(%Category{} = category, attrs) do
    category
    |> Category.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a category.
  """
  def delete_category(%Category{} = category) do
    Repo.delete(category)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking category changes.
  """
  def change_category(%Category{} = category, attrs \\ %{}) do
    Category.changeset(category, attrs)
  end

  # Tag functions

  @doc """
  Returns the list of all tags ordered by name.
  """
  def list_tags do
    Tag
    |> order_by([t], asc: t.name)
    |> Repo.all()
  end

  @doc """
  Gets a tag by slug.
  """
  def get_tag_by_slug(slug) do
    Repo.get_by(Tag, slug: slug)
  end

  @doc """
  Gets a tag by slug, raises if not found.
  """
  def get_tag_by_slug!(slug) do
    Repo.get_by!(Tag, slug: slug)
  end

  @doc """
  Gets or creates a tag by name.
  """
  def get_or_create_tag(name) do
    slug = Tag.generate_slug(name)

    case Repo.get_by(Tag, name: name) do
      nil ->
        %Tag{}
        |> Tag.changeset(%{name: name, slug: slug})
        |> Repo.insert()

      tag ->
        {:ok, tag}
    end
  end

  @doc """
  Creates a tag.
  """
  def create_tag(attrs \\ %{}) do
    %Tag{}
    |> Tag.changeset(attrs)
    |> Repo.insert()
  end

  # Hub functions

  @doc """
  Gets a single hub by ID.
  """
  def get_hub(id) do
    Repo.get(Hub, id)
  end

  @doc """
  Gets a hub by slug.
  """
  def get_hub_by_slug(slug) do
    Repo.get_by(Hub, slug: slug, is_active: true)
  end

  @doc """
  Gets a hub by slug, raises if not found.
  """
  def get_hub_by_slug!(slug) do
    Repo.get_by!(Hub, slug: slug, is_active: true)
  end

  @doc """
  Gets a hub by slug with followers preloaded.
  """
  def get_hub_by_slug_with_followers(slug) do
    Hub
    |> where([h], h.slug == ^slug and h.is_active == true)
    |> preload(:followers)
    |> Repo.one()
  end

  @doc """
  Gets a hub by slug with followers preloaded, raises if not found.
  """
  def get_hub_by_slug_with_followers!(slug) do
    Hub
    |> where([h], h.slug == ^slug and h.is_active == true)
    |> preload(:followers)
    |> Repo.one!()
  end

  @doc """
  Gets a hub by slug with followers, posts, and events preloaded.
  """
  def get_hub_by_slug_with_associations(slug) do
    Hub
    |> where([h], h.slug == ^slug and h.is_active == true)
    |> preload([:followers, :posts, :events])
    |> Repo.one()
  end

  @doc """
  Lists all active hubs.
  """
  def list_hubs do
    Hub
    |> where([h], h.is_active == true)
    |> order_by([h], asc: h.name)
    |> Repo.all()
  end

  @doc """
  Lists all hubs (active and inactive) for admin purposes.
  Active hubs are listed first, then inactive, both sorted by name.
  """
  def list_all_hubs do
    Hub
    |> order_by([h], [desc: h.is_active, asc: h.name])
    |> Repo.all()
  end

  @doc """
  Lists all active hubs with followers preloaded.
  """
  def list_hubs_with_followers do
    Hub
    |> where([h], h.is_active == true)
    |> order_by([h], asc: h.name)
    |> preload([:followers, :posts, :events])
    |> Repo.all()
  end

  @doc """
  Creates a hub.
  """
  def create_hub(attrs \\ %{}) do
    result = %Hub{}
    |> Hub.changeset(attrs)
    |> Repo.insert()

    # Refresh logo cache after creating hub
    case result do
      {:ok, hub} ->
        if hub.token && hub.token != "" do
          BlocksterV2.HubLogoCache.update_hub(hub.token, hub.logo_url)
        end
        {:ok, hub}
      error -> error
    end
  end

  @doc """
  Updates a hub.
  """
  def update_hub(%Hub{} = hub, attrs) do
    result = hub
    |> Hub.changeset(attrs)
    |> Repo.update()

    # Refresh logo cache after updating hub
    case result do
      {:ok, updated_hub} ->
        if updated_hub.token && updated_hub.token != "" do
          BlocksterV2.HubLogoCache.update_hub(updated_hub.token, updated_hub.logo_url)
        end
        {:ok, updated_hub}
      error -> error
    end
  end

  @doc """
  Deletes a hub.
  """
  def delete_hub(%Hub{} = hub) do
    Repo.delete(hub)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking hub changes.
  """
  def change_hub(%Hub{} = hub, attrs \\ %{}) do
    Hub.changeset(hub, attrs)
  end

  @doc """
  Gets the follower count for a hub.
  """
  def get_hub_follower_count(hub_id) do
    from(hf in "hub_followers",
      where: hf.hub_id == ^hub_id,
      select: count(hf.user_id)
    )
    |> Repo.one()
  end

  @doc """
  Gets follower counts for multiple hubs.
  Returns a map of hub_id => follower_count.
  """
  def get_hub_follower_counts(hub_ids) when is_list(hub_ids) do
    from(hf in "hub_followers",
      where: hf.hub_id in ^hub_ids,
      group_by: hf.hub_id,
      select: {hf.hub_id, count(hf.user_id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Adds bux_balance from Mnesia to posts.
  Returns posts with :bux_balance virtual field set.
  """
  def with_bux_balances(posts) when is_list(posts) do
    alias BlocksterV2.EngagementTracker

    post_ids = Enum.map(posts, & &1.id)
    balances = EngagementTracker.get_post_bux_balances(post_ids)

    Enum.map(posts, fn post ->
      Map.put(post, :bux_balance, Map.get(balances, post.id, 0))
    end)
  end

  def with_bux_balances(%Post{} = post) do
    alias BlocksterV2.EngagementTracker

    balance = EngagementTracker.get_post_bux_balance(post.id)
    Map.put(post, :bux_balance, balance)
  end
end
