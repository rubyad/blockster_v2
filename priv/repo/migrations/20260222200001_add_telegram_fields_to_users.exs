defmodule BlocksterV2.Repo.Migrations.AddTelegramFieldsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :telegram_user_id, :string
      add :telegram_username, :string
      add :telegram_connect_token, :string
      add :telegram_connected_at, :utc_datetime
    end

    create unique_index(:users, [:telegram_user_id])
    create unique_index(:users, [:telegram_connect_token])
  end
end
