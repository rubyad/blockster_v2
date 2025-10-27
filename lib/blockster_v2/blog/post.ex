defmodule BlocksterV2.Blog.Post do
  use Ecto.Schema
  import Ecto.Changeset

  schema "posts" do
    field :title, :string
    field :slug, :string
    field :content, :map
    field :excerpt, :string
    field :author_name, :string
    field :published_at, :utc_datetime
    field :view_count, :integer, default: 0
    field :category, :string
    field :featured_image, :string

    timestamps()
  end

  @doc false
  def changeset(post, attrs) do
    post
    |> cast(attrs, [
      :title,
      :slug,
      :content,
      :excerpt,
      :author_name,
      :published_at,
      :view_count,
      :category,
      :featured_image
      :featured_image
    ])
    |> validate_required([:title, :author_name])
    |> generate_slug()
    |> validate_format(:slug, ~r/^[a-z0-9-]+$/,
      message: "must be lowercase alphanumeric with dashes"
    )
    |> unique_constraint(:slug)
  end

  defp generate_slug(changeset) do
    case get_change(changeset, :title) do
      nil ->
        changeset

      title ->
        slug =
          title
          |> String.downcase()
          |> String.replace(~r/[^a-z0-9\s-]/, "")
          |> String.replace(~r/\s+/, "-")
          |> String.trim("-")

        put_change(changeset, :slug, slug)
    end
  end

  def increment_view_count(post) do
    post
    |> change(view_count: post.view_count + 1)
  end

  def publish(post) do
    post
    |> change(published_at: DateTime.utc_now() |> DateTime.truncate(:second))
  end

  def unpublish(post) do
    post
    |> change(published_at: nil)
  end

  def published?(post) do
    not is_nil(post.published_at)
  end
end
