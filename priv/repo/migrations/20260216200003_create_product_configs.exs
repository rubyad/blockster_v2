defmodule BlocksterV2.Repo.Migrations.CreateProductConfigs do
  use Ecto.Migration

  def change do
    create table(:product_configs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :product_id, references(:products, type: :binary_id), null: false

      # What variant options this product uses
      add :has_sizes, :boolean, default: false
      add :has_colors, :boolean, default: false
      add :has_custom_option, :boolean, default: false
      add :custom_option_label, :string

      # Size system type
      add :size_type, :string, default: "clothing"

      # Available options
      add :available_sizes, {:array, :string}, default: []
      add :available_colors, {:array, :string}, default: []

      # Checkout requirements
      add :requires_shipping, :boolean, default: true
      add :is_digital, :boolean, default: false

      # Affiliate settings (per-product override)
      add :affiliate_commission_rate, :decimal

      # Checkout toggle
      add :checkout_enabled, :boolean, default: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:product_configs, [:product_id])
  end
end
