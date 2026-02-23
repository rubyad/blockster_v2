defmodule BlocksterV2.Repo.Migrations.AddTelegramGroupJoinedToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :telegram_group_joined_at, :utc_datetime
    end
  end
end
