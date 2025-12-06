defmodule BlocksterV2.Blog.Hub do
  use Ecto.Schema
  import Ecto.Changeset

  schema "hubs" do
    field :name, :string
    field :slug, :string
    field :tag_name, :string
    field :description, :string
    field :logo_url, :string
    field :banner_url, :string
    field :website_url, :string
    field :twitter_url, :string
    field :telegram_url, :string
    field :instagram_url, :string
    field :linkedin_url, :string
    field :tiktok_url, :string
    field :discord_url, :string
    field :reddit_url, :string
    field :youtube_url, :string
    field :color_primary, :string
    field :color_secondary, :string
    field :is_active, :boolean, default: true

    # Associations
    has_many :posts, BlocksterV2.Blog.Post
    has_many :events, BlocksterV2.Events.Event
    many_to_many :followers, BlocksterV2.Accounts.User,
      join_through: "hub_followers",
      on_replace: :delete

    timestamps()
  end

  @doc false
  def changeset(hub, attrs) do
    hub
    |> cast(attrs, [
      :name,
      :slug,
      :tag_name,
      :description,
      :logo_url,
      :banner_url,
      :website_url,
      :twitter_url,
      :telegram_url,
      :instagram_url,
      :linkedin_url,
      :tiktok_url,
      :discord_url,
      :reddit_url,
      :youtube_url,
      :color_primary,
      :color_secondary,
      :is_active
    ])
    |> validate_required([:name, :tag_name])
    |> generate_slug()
    |> validate_required([:slug])
    |> unique_constraint(:slug)
    |> unique_constraint(:tag_name)
  end

  defp generate_slug(changeset) do
    case get_field(changeset, :name) do
      nil ->
        changeset

      name ->
        slug =
          name
          |> String.downcase()
          |> String.replace(~r/[^a-z0-9\s-]/, "")
          |> String.replace(~r/\s+/, "-")
          |> String.trim("-")

        put_change(changeset, :slug, slug)
    end
  end
end
