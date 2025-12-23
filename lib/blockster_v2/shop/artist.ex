defmodule BlocksterV2.Shop.Artist do
  use Ecto.Schema
  import Ecto.Changeset

  schema "artists" do
    field :name, :string
    field :slug, :string
    field :image, :string
    field :description, :string
    field :website, :string

    # Social URLs
    field :twitter_url, :string
    field :telegram_url, :string
    field :instagram_url, :string
    field :linkedin_url, :string
    field :tiktok_url, :string
    field :discord_url, :string
    field :reddit_url, :string
    field :youtube_url, :string

    has_many :products, BlocksterV2.Shop.Product

    timestamps(type: :utc_datetime)
  end

  @required_fields [:name, :slug]
  @optional_fields [
    :image,
    :description,
    :website,
    :twitter_url,
    :telegram_url,
    :instagram_url,
    :linkedin_url,
    :tiktok_url,
    :discord_url,
    :reddit_url,
    :youtube_url
  ]

  @doc false
  def changeset(artist, attrs) do
    artist
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> generate_slug()
    |> unique_constraint(:slug)
  end

  defp generate_slug(changeset) do
    case {get_field(changeset, :slug), get_field(changeset, :name)} do
      {nil, name} when is_binary(name) ->
        slug =
          name
          |> String.downcase()
          |> String.replace(~r/[^a-z0-9\s-]/, "")
          |> String.replace(~r/\s+/, "-")
          |> String.trim("-")

        put_change(changeset, :slug, slug)

      {"", name} when is_binary(name) ->
        slug =
          name
          |> String.downcase()
          |> String.replace(~r/[^a-z0-9\s-]/, "")
          |> String.replace(~r/\s+/, "-")
          |> String.trim("-")

        put_change(changeset, :slug, slug)

      _ ->
        changeset
    end
  end
end
