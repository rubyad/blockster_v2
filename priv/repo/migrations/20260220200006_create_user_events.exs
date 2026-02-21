defmodule BlocksterV2.Repo.Migrations.CreateUserEvents do
  use Ecto.Migration

  def change do
    create table(:user_events) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :event_type, :string, null: false
      add :event_category, :string, null: false
      add :target_type, :string
      add :target_id, :string
      add :metadata, :map, default: %{}
      add :session_id, :string
      add :source, :string, default: "web"
      add :referrer, :string

      timestamps(updated_at: false)
    end

    create index(:user_events, [:user_id, :inserted_at])
    create index(:user_events, [:user_id, :event_type])
    create index(:user_events, [:event_type, :inserted_at])
    create index(:user_events, [:target_type, :target_id])
    create index(:user_events, [:session_id])
  end
end
