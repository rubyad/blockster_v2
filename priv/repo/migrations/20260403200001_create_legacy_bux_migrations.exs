defmodule BlocksterV2.Repo.Migrations.CreateLegacyBuxMigrations do
  use Ecto.Migration

  def change do
    create table(:legacy_bux_migrations) do
      add :email, :string, null: false
      add :legacy_bux_balance, :decimal, null: false, default: 0
      add :legacy_wallet_address, :string
      add :new_wallet_address, :string
      add :mint_tx_signature, :string
      add :migrated, :boolean, default: false, null: false
      add :migrated_at, :utc_datetime

      timestamps()
    end

    create unique_index(:legacy_bux_migrations, [:email])
    create index(:legacy_bux_migrations, [:migrated])
    create index(:legacy_bux_migrations, [:legacy_wallet_address])
  end
end
