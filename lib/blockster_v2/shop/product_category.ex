defmodule BlocksterV2.Shop.ProductCategory do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "product_categories" do
    field :name, :string
    field :slug, :string
    field :description, :string
    field :image_url, :string
    field :position, :integer, default: 0

    # Self-referential for parent/child categories
    belongs_to :parent, __MODULE__
    has_many :children, __MODULE__, foreign_key: :parent_id

    # Many-to-many with products
    many_to_many :products, BlocksterV2.Shop.Product,
      join_through: "product_category_assignments",
      on_replace: :delete

    timestamps()
  end

  @required_fields [:name, :slug]
  @optional_fields [:description, :image_url, :parent_id, :position]

  @doc false
  def changeset(category, attrs) do
    category
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

      _ ->
        changeset
    end
  end
end
