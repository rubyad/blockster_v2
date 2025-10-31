defmodule BlocksterV2.Repo.Migrations.CreateUserSessions do
  use Ecto.Migration

  def change do
    create table(:user_sessions) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :token, :string, null: false
      add :expires_at, :utc_datetime, null: false
      add :last_active_at, :utc_datetime

      timestamps()
    end

    create unique_index(:user_sessions, [:token])
    create index(:user_sessions, [:user_id])
    create index(:user_sessions, [:expires_at])
  end
end
