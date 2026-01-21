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
    field :base_bux_reward, :integer, default: 1
    field :value, :decimal
    field :tx_id, :string
    field :contact, :string

    # Virtual field - computed from author association
    field :author_name, :string, virtual: true

    # Video fields
    field :video_url, :string
    field :video_id, :string
    field :video_duration, :integer        # seconds
    field :video_bux_per_minute, :decimal, default: Decimal.new("1.0")
    field :video_max_reward, :decimal      # nil = no cap

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
      :base_bux_reward,
      :value,
      :tx_id,
      :contact,
      :video_url,
      :video_id,
      :video_duration,
      :video_bux_per_minute,
      :video_max_reward
    ])
    |> extract_video_id()
    |> validate_required([:title])
    |> generate_slug()
    |> validate_format(:slug, ~r/^[a-z0-9-]+$/,
      message: "must be lowercase alphanumeric with dashes"
    )
    |> unique_constraint(:slug)
    |> sync_published_at_with_custom()
  end

  # When custom_published_at is changed on a published post, also update published_at
  defp sync_published_at_with_custom(changeset) do
    custom_published_at = get_change(changeset, :custom_published_at)
    current_published_at = get_field(changeset, :published_at)

    # Only sync if:
    # 1. custom_published_at is being changed
    # 2. The post is already published (has a published_at)
    if custom_published_at && current_published_at do
      put_change(changeset, :published_at, custom_published_at)
    else
      changeset
    end
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

  # Extract YouTube video ID from URL when video_url changes
  defp extract_video_id(changeset) do
    case get_change(changeset, :video_url) do
      nil -> changeset
      "" -> put_change(changeset, :video_id, nil)
      url ->
        video_id = extract_youtube_id(url)
        put_change(changeset, :video_id, video_id)
    end
  end

  @doc """
  Extracts YouTube video ID from various URL formats.
  Supports:
  - Standard: youtube.com/watch?v=VIDEO_ID
  - Short: youtu.be/VIDEO_ID
  - Embed: youtube.com/embed/VIDEO_ID
  """
  def extract_youtube_id(nil), do: nil
  def extract_youtube_id(""), do: nil

  def extract_youtube_id(url) when is_binary(url) do
    cond do
      # Standard: youtube.com/watch?v=VIDEO_ID
      String.contains?(url, "youtube.com/watch") ->
        uri = URI.parse(url)
        case uri.query do
          nil -> nil
          query ->
            URI.decode_query(query)
            |> Map.get("v")
        end

      # Short: youtu.be/VIDEO_ID
      String.contains?(url, "youtu.be/") ->
        URI.parse(url).path
        |> String.trim_leading("/")
        |> String.split("?")
        |> List.first()

      # Embed: youtube.com/embed/VIDEO_ID
      String.contains?(url, "youtube.com/embed/") ->
        URI.parse(url).path
        |> String.split("/")
        |> List.last()
        |> String.split("?")
        |> List.first()

      true -> nil
    end
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
