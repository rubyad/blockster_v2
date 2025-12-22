defmodule BlocksterV2.Shop.ProductTag do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "product_tags" do
    field :name, :string
    field :slug, :string

    # Many-to-many with products
    many_to_many :products, BlocksterV2.Shop.Product,
      join_through: "product_tag_assignments",
      on_replace: :delete

    timestamps()
  end

  @required_fields [:name, :slug]

  @doc false
  def changeset(tag, attrs) do
    tag
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> generate_slug()
    |> unique_constraint(:slug)
    |> unique_constraint(:name)
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

      _ ->
        changeset
    end
  end
end
