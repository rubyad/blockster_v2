defmodule BlocksterV2.Shop.ProductImage do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "product_images" do
    field :src, :string
    field :alt, :string
    field :position, :integer, default: 1
    field :width, :integer
    field :height, :integer

    # Optional variant association (for variant-specific images)
    field :variant_ids, {:array, :binary_id}, default: []

    # Associations
    belongs_to :product, BlocksterV2.Shop.Product

    timestamps()
  end

  @required_fields [:product_id, :src]
  @optional_fields [:alt, :position, :width, :height, :variant_ids]

  @doc false
  def changeset(image, attrs) do
    image
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:position, greater_than_or_equal_to: 1)
  end
end
