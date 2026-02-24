defmodule BlocksterV2.Repo.Migrations.AddBotPrivateKeyToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :bot_private_key, :string
    end
  end
end
