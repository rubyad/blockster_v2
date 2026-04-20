defmodule BlocksterV2.Repo.Migrations.CreateOrderPaymentIntents do
  use Ecto.Migration

  def change do
    create table(:order_payment_intents, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :order_id, references(:orders, type: :binary_id, on_delete: :delete_all), null: false
      add :buyer_wallet, :string, null: false
      add :pubkey, :string, null: false
      # Expected payment amount in SOL lamports (1 SOL = 10^9 lamports).
      # Stored as bigint so a 1000-SOL order still fits.
      add :expected_lamports, :bigint, null: false
      # Quoted USD amount at the moment of intent creation (for records).
      add :quoted_usd, :decimal, precision: 10, scale: 2, null: false
      # Locked SOL/USD rate at intent creation — used to verify the quote.
      add :quoted_sol_usd_rate, :decimal, precision: 12, scale: 4, null: false
      add :status, :string, null: false, default: "pending"
      add :funded_tx_sig, :string
      add :funded_lamports, :bigint
      add :funded_at, :utc_datetime
      add :swept_tx_sig, :string
      add :swept_at, :utc_datetime
      add :expires_at, :utc_datetime, null: false
      add :last_checked_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:order_payment_intents, [:order_id])
    create unique_index(:order_payment_intents, [:pubkey])
    create index(:order_payment_intents, [:status])
    create index(:order_payment_intents, [:expires_at])
  end
end
