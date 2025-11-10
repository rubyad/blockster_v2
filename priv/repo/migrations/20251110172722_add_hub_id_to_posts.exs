defmodule BlocksterV2.Repo.Migrations.AddHubIdToPosts do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      add :hub_id, references(:hubs, on_delete: :nilify_all)
    end

    create index(:posts, [:hub_id])
  end
end
