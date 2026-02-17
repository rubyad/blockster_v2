defmodule BlocksterV2.Orders.OrderItem do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "order_items" do
    belongs_to :order, BlocksterV2.Orders.Order
    field :product_id, :binary_id
    field :product_title, :string
    field :product_image, :string
    field :variant_id, :binary_id
    field :variant_title, :string
    field :quantity, :integer, default: 1
    field :unit_price, :decimal
    field :subtotal, :decimal
    field :bux_discount_amount, :decimal, default: Decimal.new("0")
    field :bux_tokens_redeemed, :integer, default: 0
    field :tracking_number, :string
    field :tracking_url, :string
    field :fulfillment_status, :string, default: "unfulfilled"
    timestamps(type: :utc_datetime)
  end

  @required_fields [:order_id, :product_id, :product_title, :quantity, :unit_price, :subtotal]
  @optional_fields [:product_image, :variant_id, :variant_title, :bux_discount_amount, :bux_tokens_redeemed, :tracking_number, :tracking_url, :fulfillment_status]

  def changeset(order_item, attrs) do
    order_item
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:quantity, greater_than: 0)
    |> validate_number(:unit_price, greater_than_or_equal_to: 0)
    |> validate_inclusion(:fulfillment_status, ["unfulfilled", "processing", "shipped", "delivered"])
    |> foreign_key_constraint(:order_id)
  end
end
