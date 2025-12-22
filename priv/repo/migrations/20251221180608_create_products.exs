defmodule BlocksterV2.Repo.Migrations.CreateProducts do
  use Ecto.Migration

  def change do
    create table(:products, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # Basic product info (Shopify-style)
      add :title, :string, null: false
      add :body_html, :text
      add :vendor, :string
      add :product_type, :string
      add :handle, :string, null: false
      add :status, :string, default: "draft"
      add :tags, {:array, :string}, default: []

      # Hub association (hubs table uses integer IDs)
      add :hub_id, references(:hubs, on_delete: :nilify_all)

      # Token discount settings
      add :bux_max_discount, :integer, default: 0
      add :hub_token_max_discount, :integer, default: 0

      # Publishing
      add :published_at, :utc_datetime
      add :published_scope, :string, default: "web"
      add :template_suffix, :string

      # SEO
      add :seo_title, :string
      add :seo_description, :text

      timestamps()
    end

    create unique_index(:products, [:handle])
    create index(:products, [:hub_id])
    create index(:products, [:status])
    create index(:products, [:product_type])
    create index(:products, [:vendor])
  end
end
