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

    # Use tag_name from opts if provided (avoids extra DB query when hub is already loaded)
    tag_name = Keyword.get(opts, :tag_name) || get_hub(hub_id) |> then(fn hub -> hub && hub.tag_name end)

    query = if tag_name do
      # Find posts that either have this hub_id OR have a tag matching the hub's tag_name
      # Use subquery to get distinct post IDs first, then order properly
      post_ids_query =
        from(p in Post,
          left_join: pt in "post_tags", on: pt.post_id == p.id,
          left_join: t in Tag, on: t.id == pt.tag_id,
          where: not is_nil(p.published_at),
          where: p.hub_id == ^hub_id or t.name == ^tag_name,
          select: p.id,
          distinct: true
        )

      from(p in Post,
        where: p.id in subquery(post_ids_query),
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
  Lists published video posts for a specific hub.

  Video posts are identified by having a non-null `video_id` field,
  which is extracted from YouTube URLs entered in the post form.

  ## Options

    * `:limit` - Maximum number of posts to return (default: 3)

  ## Examples

      iex> list_video_posts_by_hub(123)
      [%Post{video_id: "dQw4w9WgXcQ", ...}, ...]

      iex> list_video_posts_by_hub(123, limit: 5)
      [%Post{}, ...]

  """
  def list_video_posts_by_hub(hub_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 3)

    # Use tag_name from opts if provided (avoids extra DB query when hub is already loaded)
    tag_name = Keyword.get(opts, :tag_name) || get_hub(hub_id) |> then(fn hub -> hub && hub.tag_name end)

    query = if tag_name do
      # Find video posts that either have this hub_id OR have a tag matching the hub's tag_name
      post_ids_query =
        from(p in Post,
          left_join: pt in "post_tags", on: pt.post_id == p.id,
          left_join: t in Tag, on: t.id == pt.tag_id,
          where: not is_nil(p.published_at),
          where: not is_nil(p.video_id),
          where: p.hub_id == ^hub_id or t.name == ^tag_name,
          select: p.id,
          distinct: true
        )

      from(p in Post,
        where: p.id in subquery(post_ids_query),
        order_by: [desc: p.published_at],
        limit: ^limit,
        preload: [:author, :category, :hub, tags: ^from(t in Tag, order_by: t.name)]
      )
    else
      # Fallback to just hub_id if hub doesn't have a tag_name
      from(p in Post,
        where: not is_nil(p.published_at),
        where: not is_nil(p.video_id),
        where: p.hub_id == ^hub_id,
        order_by: [desc: p.published_at],
        limit: ^limit,
        preload: [:author, :category, :hub, tags: ^from(t in Tag, order_by: t.name)]
      )
    end

    query
    |> Repo.all()
    |> populate_author_names()
  end

  @doc """
  Returns random published posts, optionally excluding a specific post.
  Used for sidebar recommendations.
  """
  def get_random_posts(count, exclude_post_id \\ nil) do
    query =
      from p in Post,
        where: not is_nil(p.published_at) and not is_nil(p.featured_image),
        preload: [:category],
        order_by: fragment("RANDOM()"),
        limit: ^count

    query =
      if exclude_post_id do
        from p in query, where: p.id != ^exclude_post_id
      else
        query
      end

    Repo.all(query)
    |> with_bux_earned()
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
  Gets the total count of published posts (for pagination UI).
  """
  def count_published_posts do
    from(p in Post, where: not is_nil(p.published_at))
    |> Repo.aggregate(:count)
  end

  @doc """
  Gets the count of published posts in a category.
  """
  def count_published_posts_by_category(category_slug) do
    case get_category_by_slug(category_slug) do
      nil -> 0
      category ->
        from(p in Post,
          where: not is_nil(p.published_at),
          where: p.category_id == ^category.id
        )
        |> Repo.aggregate(:count)
    end
  end

  @doc """
  Gets the count of published posts with a tag.
  """
  def count_published_posts_by_tag(tag_slug) do
    case get_tag_by_slug(tag_slug) do
      nil -> 0
      tag ->
        from(p in Post,
          join: pt in "post_tags", on: pt.post_id == p.id,
          where: not is_nil(p.published_at),
          where: pt.tag_id == ^tag.id
        )
        |> Repo.aggregate(:count)
    end
  end

  # =============================================================================
  # Date-sorted queries (direct Ecto, no cache)
  # =============================================================================

  @doc """
  Lists published posts sorted by published_at DESC (newest first).
  Returns posts with :bux_balance set to total_distributed (BUX earned).
  """
  def list_published_posts_by_date(opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    offset = Keyword.get(opts, :offset, 0)

    published_posts_query()
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
    |> populate_author_names()
    |> with_bux_earned()
  end

  @doc """
  Lists published posts for a category sorted by published_at DESC.
  """
  def list_published_posts_by_date_category(category_slug, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    offset = Keyword.get(opts, :offset, 0)
    exclude_ids = Keyword.get(opts, :exclude_ids, [])

    case get_category_by_slug(category_slug) do
      nil -> []
      category ->
        query = from(p in Post,
          where: not is_nil(p.published_at),
          where: p.category_id == ^category.id,
          order_by: [desc: p.published_at],
          limit: ^limit,
          offset: ^offset,
          preload: [:author, :category, :hub, tags: ^from(t in Tag, order_by: t.name)]
        )

        query = if exclude_ids != [] do
          from(p in query, where: p.id not in ^exclude_ids)
        else
          query
        end

        query
        |> Repo.all()
        |> populate_author_names()
        |> with_bux_earned()
    end
  end

  @doc """
  Lists published posts for a tag sorted by published_at DESC.
  """
  def list_published_posts_by_date_tag(tag_slug, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    offset = Keyword.get(opts, :offset, 0)
    exclude_ids = Keyword.get(opts, :exclude_ids, [])

    case get_tag_by_slug(tag_slug) do
      nil -> []
      tag ->
        query = from(p in Post,
          join: pt in "post_tags", on: pt.post_id == p.id,
          where: not is_nil(p.published_at),
          where: pt.tag_id == ^tag.id,
          order_by: [desc: p.published_at],
          limit: ^limit,
          offset: ^offset,
          preload: [:author, :category, :hub, tags: ^from(t in Tag, order_by: t.name)]
        )

        query = if exclude_ids != [] do
          from(p in query, where: p.id not in ^exclude_ids)
        else
          query
        end

        query
        |> Repo.all()
        |> populate_author_names()
        |> with_bux_earned()
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
  Returns nil if not found.
  """
  def get_post_by_slug(slug) do
    from(p in Post,
      where: p.slug == ^slug,
      preload: [:author, :category, :hub, tags: ^from(t in Tag, order_by: t.name)]
    )
    |> Repo.one()
    |> case do
      nil -> nil
      post -> populate_author_names(post)
    end
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
  Returns suggested posts for a user — recent posts, shuffled.
  Excludes the current post and (for logged-in users) posts they've already read.

  ## Parameters
    - current_post_id: ID of the post being viewed (always excluded)
    - user_id: User ID (nil for anonymous users)
    - limit: Number of posts to return (default: 4)

  ## Returns
    List of Post structs with :bux_balance virtual field set to total_distributed
  """
  def get_suggested_posts(current_post_id, user_id \\ nil, limit \\ 4) do
    alias BlocksterV2.EngagementTracker

    # Build exclusion list
    exclude_ids = if user_id do
      read_ids = EngagementTracker.get_user_read_post_ids(user_id)
      [current_post_id | read_ids]
    else
      [current_post_id]
    end

    # Fetch 20 most recent published posts, then shuffle and take limit
    pool_size = 20

    query = from(p in Post,
      where: not is_nil(p.published_at),
      where: p.id not in ^exclude_ids,
      order_by: [desc: p.published_at],
      limit: ^pool_size,
      preload: [:category]
    )

    query
    |> Repo.all()
    |> with_bux_earned()
    |> Enum.shuffle()
    |> Enum.take(limit)
  end

  @doc """
  Creates a post.
  """
  def create_post(attrs \\ %{}) do
    result =
      %Post{}
      |> Post.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, %Post{published_at: published_at} = post} when not is_nil(published_at) ->
        # Notify hub followers if post belongs to a hub
        if post.hub_id do
          Task.start(fn -> notify_hub_followers_of_new_post(post) end)
        end

        # Post to Telegram
        post_with_hub = Repo.preload(post, :hub)
        Task.start(fn -> BlocksterV2.TelegramNotifier.send_new_post(post_with_hub) end)

        # Trigger AI Ads Manager evaluation
        Phoenix.PubSub.broadcast(BlocksterV2.PubSub, "post:published", {:post_published, post})

        {:ok, post}

      _ ->
        result
    end
  end

  @doc """
  Updates a post.
  """
  def update_post(%Post{} = post, attrs) do
    was_published = not is_nil(post.published_at)

    result =
      post
      |> Post.changeset(attrs)
      |> Repo.update()

    case result do
      {:ok, %Post{published_at: published_at} = updated_post}
      when not is_nil(published_at) and not was_published ->
        # Post just became published via edit — fire notifications
        if updated_post.hub_id do
          Task.start(fn -> notify_hub_followers_of_new_post(updated_post) end)
        end

        post_with_hub = Repo.preload(updated_post, :hub)
        Task.start(fn -> BlocksterV2.TelegramNotifier.send_new_post(post_with_hub) end)

        Phoenix.PubSub.broadcast(BlocksterV2.PubSub, "post:published", {:post_published, updated_post})

        {:ok, updated_post}

      _ ->
        result
    end
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
    result =
      post
      |> Post.publish()
      |> Repo.update()

    case result do
      {:ok, published_post} ->
        # Notify hub followers in the background if post belongs to a hub
        if published_post.hub_id do
          Task.start(fn -> notify_hub_followers_of_new_post(published_post) end)
        end

        # Post to Telegram
        post_with_hub = Repo.preload(published_post, :hub)
        Task.start(fn -> BlocksterV2.TelegramNotifier.send_new_post(post_with_hub) end)

        # Trigger AI Ads Manager evaluation
        Phoenix.PubSub.broadcast(BlocksterV2.PubSub, "post:published", {:post_published, published_post})

        {:ok, published_post}

      error ->
        error
    end
  end

  @doc """
  Notifies all followers of a hub that a new post has been published.
  """
  def notify_hub_followers_of_new_post(%Post{} = post) do
    hub = get_hub(post.hub_id)
    followers = get_hub_followers_with_preferences(hub.id)

    # Batch in-app notifications (single INSERT instead of N individual INSERTs)
    notification_rows =
      followers
      |> Enum.filter(fn follower ->
        Map.get(follower, :in_app_notifications, true) && Map.get(follower, :notify_new_posts, true)
      end)
      |> Enum.map(fn follower ->
        %{
          user_id: follower.user_id,
          type: "hub_post",
          category: "content",
          title: "New in #{hub.name}",
          body: post.title,
          image_url: post.featured_image,
          action_url: "/#{post.slug}",
          action_label: "Read Article",
          metadata: %{"post_id" => post.id, "hub_id" => hub.id}
        }
      end)

    if notification_rows != [] do
      BlocksterV2.Notifications.create_notifications_batch(notification_rows)
    end

    # Email notifications (already async via Oban workers)
    Enum.each(followers, fn follower ->
      send_email = Map.get(follower, :email_notifications, true) && Map.get(follower, :notify_new_posts, true)
      if send_email do
        BlocksterV2.Workers.HubPostNotificationWorker.enqueue(follower.user_id, post.id, hub.id)
      end
    end)
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

  # ============ Hub Follow/Unfollow ============

  alias BlocksterV2.Blog.HubFollower

  @doc """
  Follows a hub. Creates a hub_followers record.
  Returns {:ok, hub_follower} or {:error, changeset}.
  """
  def follow_hub(user_id, hub_id) do
    result =
      %HubFollower{}
      |> HubFollower.changeset(%{user_id: user_id, hub_id: hub_id})
      |> Repo.insert()

    case result do
      {:ok, _} ->
        hub = get_hub(hub_id)
        BlocksterV2.UserEvents.track(user_id, "hub_followed", %{
          target_type: "hub",
          target_id: hub_id,
          hub_slug: hub && hub.slug,
          hub_name: hub && hub.name
        })
      _ -> :ok
    end

    result
  end

  @doc """
  Unfollows a hub. Deletes the hub_followers record.
  Returns {:ok, hub_follower} or {:error, :not_found}.
  """
  def unfollow_hub(user_id, hub_id) do
    result =
      case Repo.get_by(HubFollower, user_id: user_id, hub_id: hub_id) do
        nil -> {:error, :not_found}
        follower -> Repo.delete(follower)
      end

    case result do
      {:ok, _} ->
        hub = get_hub(hub_id)
        BlocksterV2.UserEvents.track(user_id, "hub_unfollowed", %{
          target_type: "hub",
          target_id: hub_id,
          hub_slug: hub && hub.slug,
          hub_name: hub && hub.name
        })
      _ -> :ok
    end

    result
  end

  @doc """
  Toggles hub follow. If following, unfollows. If not following, follows.
  Returns {:ok, :followed} or {:ok, :unfollowed}.
  """
  def toggle_hub_follow(user_id, hub_id) do
    if user_follows_hub?(user_id, hub_id) do
      case unfollow_hub(user_id, hub_id) do
        {:ok, _} -> {:ok, :unfollowed}
        error -> error
      end
    else
      case follow_hub(user_id, hub_id) do
        {:ok, _} -> {:ok, :followed}
        error -> error
      end
    end
  end

  @doc """
  Checks if a user follows a hub.
  """
  def user_follows_hub?(user_id, hub_id) do
    from(hf in HubFollower,
      where: hf.user_id == ^user_id and hf.hub_id == ^hub_id
    )
    |> Repo.exists?()
  end

  @doc """
  Gets all hub IDs that a user follows.
  """
  def get_user_followed_hub_ids(user_id) do
    from(hf in HubFollower,
      where: hf.user_id == ^user_id,
      select: hf.hub_id
    )
    |> Repo.all()
  end

  @doc """
  Gets all user IDs that follow a hub (for notification delivery).
  """
  def get_hub_follower_user_ids(hub_id) do
    from(hf in HubFollower,
      where: hf.hub_id == ^hub_id,
      select: hf.user_id
    )
    |> Repo.all()
  end

  @doc """
  Gets hub followers with their notification preferences (for targeted notifications).
  """
  def get_hub_followers_with_preferences(hub_id) do
    from(hf in HubFollower,
      where: hf.hub_id == ^hub_id,
      select: hf
    )
    |> Repo.all()
  end

  @doc """
  Gets all hubs a user follows with hub details and per-hub notification settings.
  Returns list of maps with :hub and :follower keys.
  """
  def get_user_followed_hubs_with_settings(user_id) do
    from(hf in HubFollower,
      join: h in Hub,
      on: hf.hub_id == h.id,
      where: hf.user_id == ^user_id,
      select: %{
        hub: %{id: h.id, name: h.name, slug: h.slug, logo_url: h.logo_url},
        follower: %{
          notify_new_posts: hf.notify_new_posts,
          notify_events: hf.notify_events,
          email_notifications: hf.email_notifications,
          in_app_notifications: hf.in_app_notifications
        }
      },
      order_by: [asc: h.name]
    )
    |> Repo.all()
  end

  @doc """
  Gets user followed hubs with enriched data (description, follower count, post count).
  Used for the member profile "Following" tab.
  """
  def get_user_followed_hubs_enriched(user_id) do
    followed = from(hf in HubFollower,
      join: h in Hub,
      on: hf.hub_id == h.id,
      where: hf.user_id == ^user_id,
      select: %{
        id: h.id,
        name: h.name,
        slug: h.slug,
        logo_url: h.logo_url,
        description: h.description,
        color_primary: h.color_primary,
        tag_name: h.tag_name
      },
      order_by: [asc: h.name]
    )
    |> Repo.all()

    hub_ids = Enum.map(followed, & &1.id)

    # Batch-fetch follower counts
    follower_counts = get_hub_follower_counts(hub_ids)

    # Count posts per hub (including tag-based association, same logic as list_published_posts_by_hub)
    post_counts = Enum.into(followed, %{}, fn hub ->
      count = count_hub_posts(hub.id, hub.tag_name)
      {hub.id, count}
    end)

    Enum.map(followed, fn hub ->
      Map.merge(hub, %{
        follower_count: Map.get(follower_counts, hub.id, 0),
        post_count: Map.get(post_counts, hub.id, 0)
      })
    end)
  end

  defp count_hub_posts(hub_id, tag_name) when is_binary(tag_name) and tag_name != "" do
    from(p in Post,
      left_join: pt in "post_tags", on: pt.post_id == p.id,
      left_join: t in Tag, on: t.id == pt.tag_id,
      where: not is_nil(p.published_at),
      where: p.hub_id == ^hub_id or t.name == ^tag_name,
      select: count(p.id, :distinct)
    )
    |> Repo.one()
  end

  defp count_hub_posts(hub_id, _tag_name) do
    from(p in Post,
      where: p.hub_id == ^hub_id and not is_nil(p.published_at),
      select: count(p.id)
    )
    |> Repo.one()
  end

  @doc """
  Updates hub-specific notification settings for a user's hub follow.
  """
  def update_hub_follow_notifications(user_id, hub_id, attrs) do
    case Repo.get_by(HubFollower, user_id: user_id, hub_id: hub_id) do
      nil -> {:error, :not_found}
      follower ->
        follower
        |> HubFollower.notification_changeset(attrs)
        |> Repo.update()
    end
  end

  @doc """
  Adds total_distributed (BUX earned) from Mnesia to posts.
  Returns posts with :bux_balance virtual field set to total_distributed.
  """
  def with_bux_earned(posts) when is_list(posts) do
    alias BlocksterV2.EngagementTracker

    post_ids = Enum.map(posts, & &1.id)
    distributed_map = EngagementTracker.get_posts_total_distributed_batch(post_ids)

    Enum.map(posts, fn post ->
      Map.put(post, :bux_balance, Map.get(distributed_map, post.id, 0))
    end)
  end

  def with_bux_earned(%Post{} = post) do
    alias BlocksterV2.EngagementTracker

    distributed = EngagementTracker.get_post_total_distributed(post.id)
    Map.put(post, :bux_balance, distributed)
  end

  # Keep old name as alias for backward compatibility during rolling deploys
  def with_bux_balances(posts) when is_list(posts), do: with_bux_earned(posts)
  def with_bux_balances(%Post{} = post), do: with_bux_earned(post)
end
