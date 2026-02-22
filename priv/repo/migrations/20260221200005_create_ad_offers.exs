defmodule BlocksterV2.Repo.Migrations.CreateAdOffers do
  use Ecto.Migration

  def change do
    create table(:ad_offers) do
      add :campaign_id, references(:ad_campaigns, on_delete: :nilify_all)

      add :offer_type, :string, null: false, size: 30
      add :value, :string, null: false, size: 100
      add :code_prefix, :string, size: 20

      add :max_redemptions, :integer
      add :current_redemptions, :integer, default: 0
      add :daily_cap, :integer

      add :budget_allocated, :decimal, precision: 10, scale: 2
      add :budget_spent, :decimal, precision: 10, scale: 2, default: 0

      add :requires_phone_verification, :boolean, default: true
      add :requires_min_engagement, :boolean, default: true
      add :cooldown_days, :integer, default: 30

      add :expires_at, :utc_datetime
      add :status, :string, default: "active", size: 20

      timestamps(type: :utc_datetime)
    end

    create index(:ad_offers, [:campaign_id])
    create index(:ad_offers, [:status])

    create table(:ad_offer_codes) do
      add :offer_id, references(:ad_offers, on_delete: :delete_all)
      add :code, :string, null: false, size: 30
      add :user_id, references(:users, on_delete: :nilify_all)
      add :status, :string, default: "available", size: 20
      add :redeemed_at, :utc_datetime

      add :inserted_at, :utc_datetime, null: false, default: fragment("NOW()")
    end

    create unique_index(:ad_offer_codes, [:code])
    create index(:ad_offer_codes, [:user_id])
    create index(:ad_offer_codes, [:offer_id])
  end
end
