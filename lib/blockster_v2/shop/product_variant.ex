defmodule BlocksterV2.Shop.ProductVariant do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "product_variants" do
    # Variant identification
    field :title, :string, default: "Default Title"
    field :sku, :string
    field :barcode, :string
    field :position, :integer, default: 1

    # Pricing
    field :price, :decimal
    field :compare_at_price, :decimal

    # Options (up to 3 like Shopify: Size, Color, Material)
    field :option1, :string
    field :option2, :string
    field :option3, :string

    # Inventory
    field :inventory_quantity, :integer, default: 0
    field :inventory_policy, :string, default: "deny"
    field :inventory_management, :string
    field :fulfillment_service, :string, default: "manual"

    # Shipping
    field :weight, :decimal
    field :weight_unit, :string, default: "kg"
    field :requires_shipping, :boolean, default: true

    # Tax
    field :taxable, :boolean, default: true
    field :tax_code, :string

    # Associations
    belongs_to :product, BlocksterV2.Shop.Product

    timestamps()
  end

  @required_fields [:product_id, :price]
  @optional_fields [
    :title,
    :sku,
    :barcode,
    :position,
    :compare_at_price,
    :option1,
    :option2,
    :option3,
    :inventory_quantity,
    :inventory_policy,
    :inventory_management,
    :fulfillment_service,
    :weight,
    :weight_unit,
    :requires_shipping,
    :taxable,
    :tax_code
  ]

  @doc false
  def changeset(variant, attrs) do
    variant
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:price, greater_than_or_equal_to: 0)
    |> validate_number(:compare_at_price, greater_than_or_equal_to: 0)
    |> validate_number(:inventory_quantity, greater_than_or_equal_to: 0)
    |> validate_inclusion(:inventory_policy, ["deny", "continue"])
    |> validate_inclusion(:weight_unit, ["kg", "g", "lb", "oz"])
    |> unique_constraint(:sku)
  end
end
