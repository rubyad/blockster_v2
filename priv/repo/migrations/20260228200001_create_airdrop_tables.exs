defmodule BlocksterV2.Repo.Migrations.CreateAirdropTables do
  use Ecto.Migration

  def change do
    create table(:airdrop_rounds) do
      add :round_id, :integer, null: false
      add :status, :string, null: false, default: "pending"
      add :end_time, :utc_datetime, null: false
      add :server_seed, :string
      add :commitment_hash, :string, null: false
      add :block_hash_at_close, :string
      add :total_entries, :integer, null: false, default: 0
      add :vault_address, :string
      add :prize_pool_address, :string
      add :start_round_tx, :string
      add :close_tx, :string
      add :draw_tx, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:airdrop_rounds, [:round_id])
    create index(:airdrop_rounds, [:status])

    create table(:airdrop_entries) do
      add :user_id, references(:users, on_delete: :nothing), null: false
      add :round_id, :integer, null: false
      add :wallet_address, :string, null: false
      add :external_wallet, :string
      add :amount, :integer, null: false
      add :start_position, :integer, null: false
      add :end_position, :integer, null: false
      add :deposit_tx, :string

      timestamps(type: :utc_datetime)
    end

    create index(:airdrop_entries, [:user_id])
    create index(:airdrop_entries, [:round_id])
    create index(:airdrop_entries, [:wallet_address])

    create table(:airdrop_winners) do
      add :user_id, references(:users, on_delete: :nothing)
      add :round_id, :integer, null: false
      add :winner_index, :integer, null: false
      add :random_number, :integer, null: false
      add :wallet_address, :string, null: false
      add :external_wallet, :string
      add :deposit_start, :integer, null: false
      add :deposit_end, :integer, null: false
      add :deposit_amount, :integer, null: false
      add :prize_usd, :integer, null: false
      add :prize_usdt, :bigint, null: false
      add :claimed, :boolean, null: false, default: false
      add :claim_tx, :string
      add :claim_wallet, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:airdrop_winners, [:round_id, :winner_index])
    create index(:airdrop_winners, [:user_id])
    create index(:airdrop_winners, [:round_id])
    create index(:airdrop_winners, [:wallet_address])
  end
end
