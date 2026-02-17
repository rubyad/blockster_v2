defmodule BlocksterV2.Repo.Migrations.CreateAffiliatePayouts do
  use Ecto.Migration

  def change do
    create table(:affiliate_payouts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :order_id, references(:orders, type: :binary_id), null: false
      add :referrer_id, references(:users), null: false

      add :currency, :string, null: false
      add :basis_amount, :decimal, null: false
      add :commission_rate, :decimal, null: false, default: 0.05
      add :commission_amount, :decimal, null: false
      add :commission_usd_value, :decimal

      # Payout status
      add :status, :string, null: false, default: "pending"
      add :held_until, :utc_datetime
      add :paid_at, :utc_datetime
      add :tx_hash, :string
      add :failure_reason, :string

      timestamps(type: :utc_datetime)
    end

    create index(:affiliate_payouts, [:order_id])
    create index(:affiliate_payouts, [:referrer_id])
    create index(:affiliate_payouts, [:status])
  end
end
