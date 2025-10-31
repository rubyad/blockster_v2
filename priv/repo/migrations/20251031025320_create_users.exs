defmodule BlocksterV2.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :email, :string
      add :wallet_address, :string, null: false
      add :username, :string
      add :auth_method, :string, default: "wallet", null: false # "wallet" or "email"
      add :is_verified, :boolean, default: false, null: false
      add :bux_balance, :integer, default: 0, null: false
      add :level, :integer, default: 1, null: false
      add :experience_points, :integer, default: 0, null: false
      add :avatar_url, :string
      add :chain_id, :integer, default: 560013, null: false # Rogue Chain

      timestamps()
    end

    create unique_index(:users, [:wallet_address])
    create unique_index(:users, [:email])
    create index(:users, [:username])
  end
end
