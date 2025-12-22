defmodule BlocksterV2.Repo.Migrations.CreateProductVariants do
  use Ecto.Migration

  def change do
    create table(:product_variants, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :product_id, references(:products, type: :binary_id, on_delete: :delete_all), null: false

      # Variant identification
      add :title, :string, default: "Default Title"
      add :sku, :string
      add :barcode, :string
      add :position, :integer, default: 1

      # Pricing
      add :price, :decimal, precision: 10, scale: 2, null: false
      add :compare_at_price, :decimal, precision: 10, scale: 2

      # Options (up to 3 options like Shopify: Size, Color, Material)
      add :option1, :string
      add :option2, :string
      add :option3, :string

      # Inventory
      add :inventory_quantity, :integer, default: 0
      add :inventory_policy, :string, default: "deny"
      add :inventory_management, :string
      add :fulfillment_service, :string, default: "manual"

      # Shipping
      add :weight, :decimal, precision: 10, scale: 2
      add :weight_unit, :string, default: "kg"
      add :requires_shipping, :boolean, default: true

      # Tax
      add :taxable, :boolean, default: true
      add :tax_code, :string

      timestamps()
    end

    create index(:product_variants, [:product_id])
    create unique_index(:product_variants, [:sku], where: "sku IS NOT NULL")
    create index(:product_variants, [:barcode])
  end
end
