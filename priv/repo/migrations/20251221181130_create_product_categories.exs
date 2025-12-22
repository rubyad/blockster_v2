defmodule BlocksterV2.Repo.Migrations.CreateProductCategories do
  use Ecto.Migration

  def change do
    # Product categories table
    create table(:product_categories, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :slug, :string, null: false
      add :description, :text
      add :image_url, :string
      add :parent_id, references(:product_categories, type: :binary_id, on_delete: :nilify_all)
      add :position, :integer, default: 0

      timestamps()
    end

    create unique_index(:product_categories, [:slug])
    create index(:product_categories, [:parent_id])
    create index(:product_categories, [:position])

    # Join table for product-category many-to-many relationship
    create table(:product_category_assignments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :product_id, references(:products, type: :binary_id, on_delete: :delete_all), null: false
      add :category_id, references(:product_categories, type: :binary_id, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:product_category_assignments, [:product_id, :category_id])
    create index(:product_category_assignments, [:category_id])
  end
end
