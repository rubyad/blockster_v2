defmodule BlocksterV2.Cart.CartItem do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "cart_items" do
    belongs_to :cart, BlocksterV2.Cart.Cart
    belongs_to :product, BlocksterV2.Shop.Product
    belongs_to :variant, BlocksterV2.Shop.ProductVariant
    field :quantity, :integer, default: 1
    field :bux_tokens_to_redeem, :integer, default: 0
    timestamps(type: :utc_datetime)
  end

  @required_fields [:cart_id, :product_id, :quantity]
  @optional_fields [:variant_id, :bux_tokens_to_redeem]

  def changeset(cart_item, attrs) do
    cart_item
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:quantity, greater_than: 0)
    |> validate_number(:bux_tokens_to_redeem, greater_than_or_equal_to: 0)
    |> unique_constraint([:cart_id, :product_id, :variant_id], name: :cart_items_unique_product_variant)
    |> foreign_key_constraint(:cart_id)
    |> foreign_key_constraint(:product_id)
    |> foreign_key_constraint(:variant_id)
  end
end
