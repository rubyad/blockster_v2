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
    field :color_primary, :string
    field :color_secondary, :string
    field :is_active, :boolean, default: true

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
