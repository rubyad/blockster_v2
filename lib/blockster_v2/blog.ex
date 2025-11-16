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

    from(p in published_posts_query(),
      join: t in assoc(p, :tags),
      where: t.slug == ^tag_slug,
      limit: ^limit
    )
    |> Repo.all()
    |> populate_author_names()
  end

  @doc """
  Returns the list of published posts filtered by category slug.
  Uses association joins for efficiency.
  """
  def list_published_posts_by_category(category_slug, opts \\ []) do
    limit = Keyword.get(opts, :limit)

    from(p in published_posts_query(),
      join: c in assoc(p, :category),
      where: c.slug == ^category_slug,
      limit: ^limit
    )
    |> Repo.all()
    |> populate_author_names()
  end

  @doc """
  Returns the list of published posts filtered by hub_id.
  """
  def list_published_posts_by_hub(hub_id, opts \\ []) do
    limit = Keyword.get(opts, :limit)

    # Get the hub to access its tag_name
    hub = get_hub(hub_id)

    query = if hub && hub.tag_name do
      # Find posts that either have this hub_id OR have a tag matching the hub's tag_name
      from(p in published_posts_query(),
        left_join: pt in "post_tags", on: pt.post_id == p.id,
        left_join: t in Tag, on: t.id == pt.tag_id,
        where: p.hub_id == ^hub_id or t.name == ^hub.tag_name,
        distinct: p.id,
        limit: ^limit
      )
    else
      # Fallback to just hub_id if hub doesn't have a tag_name
      from(p in published_posts_query(),
        where: p.hub_id == ^hub_id,
        limit: ^limit
      )
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
  Lists all active hubs.
  """
  def list_hubs do
    Hub
    |> where([h], h.is_active == true)
    |> order_by([h], asc: h.name)
    |> Repo.all()
  end

  @doc """
  Lists all active hubs with followers preloaded.
  """
  def list_hubs_with_followers do
    Hub
    |> where([h], h.is_active == true)
    |> order_by([h], asc: h.name)
    |> preload(:followers)
    |> Repo.all()
  end

  @doc """
  Creates a hub.
  """
  def create_hub(attrs \\ %{}) do
    %Hub{}
    |> Hub.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a hub.
  """
  def update_hub(%Hub{} = hub, attrs) do
    hub
    |> Hub.changeset(attrs)
    |> Repo.update()
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
end
