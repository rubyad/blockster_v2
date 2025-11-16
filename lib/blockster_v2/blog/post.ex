defmodule BlocksterV2.Blog.Post do
  use Ecto.Schema
  import Ecto.Changeset

  schema "posts" do
    field :title, :string
    field :slug, :string
    field :content, :map
    field :excerpt, :string
    field :published_at, :utc_datetime
    field :custom_published_at, :utc_datetime
    field :view_count, :integer, default: 0
    field :featured_image, :string

    # BUX fields
    field :bux_total, :integer, default: 0
    field :bux_earned, :integer, default: 0
    field :value, :decimal
    field :tx_id, :string
    field :contact, :string

    # Virtual field - computed from author association
    field :author_name, :string, virtual: true

    # Associations
    belongs_to :author, BlocksterV2.Accounts.User
    belongs_to :category, BlocksterV2.Blog.Category
    belongs_to :hub, BlocksterV2.Blog.Hub
    many_to_many :tags, BlocksterV2.Blog.Tag,
      join_through: "post_tags",
      on_replace: :delete,
      preload_order: [asc: :name]

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
      :published_at,
      :custom_published_at,
      :view_count,
      :featured_image,
      :author_id,
      :category_id,
      :hub_id,
      :bux_total,
      :bux_earned,
      :value,
      :tx_id,
      :contact
    ])
    |> validate_required([:title])
    |> generate_slug()
    |> validate_format(:slug, ~r/^[a-z0-9-]+$/,
      message: "must be lowercase alphanumeric with dashes"
    )
    |> unique_constraint(:slug)
  end

  @doc """
  Computes the author_name from the loaded author association.
  Returns "Unknown" if author is not loaded or doesn't exist.
  """
  def compute_author_name(%__MODULE__{author: %Ecto.Association.NotLoaded{}}), do: "Unknown"
  def compute_author_name(%__MODULE__{author: nil}), do: "Unknown"
  def compute_author_name(%__MODULE__{author: author}) when is_map(author) do
    author.username || author.email || "Unknown"
  end

  @doc """
  Populates the virtual author_name field from the author association.
  Call this after preloading the author.
  """
  def populate_author_name(%__MODULE__{} = post) do
    %{post | author_name: compute_author_name(post)}
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
    # Use custom_published_at if set (for admin backdating), otherwise use current time
    published_date =
      if post.custom_published_at do
        post.custom_published_at
      else
        DateTime.utc_now() |> DateTime.truncate(:second)
      end

    post
    |> change(published_at: published_date)
  end

  def unpublish(post) do
    post
    |> change(published_at: nil)
  end

  def published?(post) do
    not is_nil(post.published_at)
  end
end
