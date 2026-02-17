defmodule BlocksterV2.Shop.ProductConfig do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "product_configs" do
    belongs_to :product, BlocksterV2.Shop.Product
    field :has_sizes, :boolean, default: false
    field :has_colors, :boolean, default: false
    field :has_custom_option, :boolean, default: false
    field :custom_option_label, :string
    field :size_type, :string, default: "clothing"
    field :available_sizes, {:array, :string}, default: []
    field :available_colors, {:array, :string}, default: []
    field :requires_shipping, :boolean, default: true
    field :is_digital, :boolean, default: false
    field :affiliate_commission_rate, :decimal
    field :checkout_enabled, :boolean, default: false
    timestamps(type: :utc_datetime)
  end

  @valid_size_types ~w(clothing mens_shoes womens_shoes unisex_shoes one_size)

  def changeset(config, attrs) do
    config
    |> cast(attrs, [:product_id, :has_sizes, :has_colors, :has_custom_option, :custom_option_label, :size_type, :available_sizes, :available_colors, :requires_shipping, :is_digital, :affiliate_commission_rate, :checkout_enabled])
    |> validate_required([:product_id])
    |> validate_inclusion(:size_type, @valid_size_types)
    |> unique_constraint(:product_id)
    |> foreign_key_constraint(:product_id)
  end
end
