defmodule BlocksterV2.Repo.Migrations.CreateHubsTable do
  use Ecto.Migration

  def change do
    create table(:hubs) do
      add :name, :string, null: false
      add :slug, :string, null: false
      add :tag_name, :string, null: false
      add :description, :text
      add :logo_url, :string
      add :banner_url, :string
      add :website_url, :string
      add :color_primary, :string
      add :color_secondary, :string
      add :is_active, :boolean, default: true

      timestamps()
    end

    create unique_index(:hubs, [:slug])
    create unique_index(:hubs, [:tag_name])
  end
end
