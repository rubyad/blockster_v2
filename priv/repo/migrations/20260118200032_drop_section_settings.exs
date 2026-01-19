defmodule BlocksterV2.Repo.Migrations.DropSectionSettings do
  use Ecto.Migration

  def up do
    drop table(:section_settings)
  end

  def down do
    create table(:section_settings) do
      add :section, :string, null: false
      add :title, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:section_settings, [:section])
  end
end
