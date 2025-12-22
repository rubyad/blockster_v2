defmodule BlocksterV2.Repo.Migrations.CreateProductImages do
  use Ecto.Migration

  def change do
    create table(:product_images, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :product_id, references(:products, type: :binary_id, on_delete: :delete_all), null: false

      # Image data
      add :src, :string, null: false
      add :alt, :string
      add :position, :integer, default: 1
      add :width, :integer
      add :height, :integer

      # Optional variant association (for variant-specific images)
      add :variant_ids, {:array, :binary_id}, default: []

      timestamps()
    end

    create index(:product_images, [:product_id])
    create index(:product_images, [:position])
  end
end
