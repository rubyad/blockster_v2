defmodule BlocksterV2.Repo.Migrations.CreateProductTags do
  use Ecto.Migration

  def change do
    # Product tags table
    create table(:product_tags, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :slug, :string, null: false

      timestamps()
    end

    create unique_index(:product_tags, [:slug])
    create unique_index(:product_tags, [:name])

    # Join table for product-tag many-to-many relationship
    create table(:product_tag_assignments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :product_id, references(:products, type: :binary_id, on_delete: :delete_all), null: false
      add :tag_id, references(:product_tags, type: :binary_id, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:product_tag_assignments, [:product_id, :tag_id])
    create index(:product_tag_assignments, [:tag_id])
  end
end
