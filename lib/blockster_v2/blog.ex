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

  @doc """
  Returns the list of published posts.
  """
  def list_published_posts do
    Post
    |> where([p], not is_nil(p.published_at))
    |> order_by([p], desc: p.published_at)
    |> preload(:tags)
    |> Repo.all()
  end

  @doc """
  Returns the list of published posts filtered by tag slug.
  """
  def list_published_posts_by_tag(tag_slug) do
    Post
    |> join(:inner, [p], pt in "post_tags", on: p.id == pt.post_id)
    |> join(:inner, [p, pt], t in Tag, on: t.id == pt.tag_id)
    |> where([p, pt, t], not is_nil(p.published_at) and t.slug == ^tag_slug)
    |> order_by([p], desc: p.published_at)
    |> preload(:tags)
    |> Repo.all()
  end

  @doc """
  Returns the list of published posts filtered by category slug.
  """
  def list_published_posts_by_category(category_slug) do
    Post
    |> join(:inner, [p], c in Category, on: p.category_id == c.id)
    |> where([p, c], not is_nil(p.published_at) and c.slug == ^category_slug)
    |> order_by([p], desc: p.published_at)
    |> preload([:tags, :category_ref])
    |> Repo.all()
  end

  @doc """
  Returns the list of all posts (including unpublished).
  """
  def list_posts do
    Post
    |> order_by([p], desc: p.inserted_at)
    |> preload(:tags)
    |> Repo.all()
  end

  @doc """
  Gets a single post by slug.
  """
  def get_post_by_slug!(slug) do
    Post
    |> Repo.get_by!(slug: slug)
    |> Repo.preload(:tags)
  end

  @doc """
  Gets a single post.
  """
  def get_post!(id) do
    Post
    |> Repo.get!(id)
    |> Repo.preload(:tags)
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
    tags =
      Enum.map(tag_names, fn tag_name ->
        case get_or_create_tag(tag_name) do
          {:ok, tag} -> tag
          {:error, _} -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    # Update the post's tags association
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
  Lists all active hubs.
  """
  def list_hubs do
    Hub
    |> where([h], h.is_active == true)
    |> order_by([h], asc: h.name)
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
end
