defmodule BlocksterV2.Repo.Migrations.CreateHubFollowers do
  use Ecto.Migration

  def change do
    create table(:hub_followers, primary_key: false) do
      add :hub_id, references(:hubs, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:hub_followers, [:hub_id])
    create index(:hub_followers, [:user_id])
    create unique_index(:hub_followers, [:hub_id, :user_id])
  end
end
