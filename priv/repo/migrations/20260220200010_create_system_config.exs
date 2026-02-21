defmodule BlocksterV2.Repo.Migrations.CreateSystemConfig do
  use Ecto.Migration

  def change do
    create table(:system_config) do
      add :config, :map, default: %{}, null: false
      add :updated_by, :string, default: "system"

      timestamps()
    end
  end
end
