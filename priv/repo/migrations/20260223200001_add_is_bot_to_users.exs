defmodule BlocksterV2.Repo.Migrations.AddIsBotToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :is_bot, :boolean, default: false, null: false
    end

    create index(:users, [:is_bot], where: "is_bot = true")
  end
end
