defmodule BlocksterV2.Repo.Migrations.CreateSiteSettings do
  use Ecto.Migration

  def change do
    create table(:site_settings) do
      add :key, :string, null: false
      add :value, :text

      timestamps()
    end

    create unique_index(:site_settings, [:key])
  end
end
