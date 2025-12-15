defmodule BlocksterV2.Repo.Migrations.CreateSectionSettings do
  use Ecto.Migration

  def change do
    create table(:section_settings) do
      add :section, :string, null: false
      add :title, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:section_settings, [:section])
  end
end
