defmodule BlocksterV2.Blog do
  @moduledoc """
  The Blog context.
  """

  import Ecto.Query, warn: false
  alias BlocksterV2.Repo
  alias BlocksterV2.Blog.Post

  @doc """
  Returns the list of published posts.
  """
  def list_published_posts do
    Post
    |> where([p], not is_nil(p.published_at))
    |> order_by([p], desc: p.published_at)
    |> Repo.all()
  end

  @doc """
  Returns the list of all posts (including unpublished).
  """
  def list_posts do
    Post
    |> order_by([p], desc: p.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets a single post by slug.
  """
  def get_post_by_slug!(slug) do
    Repo.get_by!(Post, slug: slug)
  end

  @doc """
  Gets a single post.
  """
  def get_post!(id), do: Repo.get!(Post, id)

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
end
