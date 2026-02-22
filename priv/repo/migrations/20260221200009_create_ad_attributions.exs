defmodule BlocksterV2.Repo.Migrations.CreateAdAttributions do
  use Ecto.Migration

  def change do
    create table(:ad_attributions) do
      add :user_id, references(:users, on_delete: :delete_all)

      add :utm_source, :string, size: 50
      add :utm_medium, :string, size: 50
      add :utm_campaign, :string, size: 100
      add :utm_content, :string, size: 100
      add :referral_code, :string, size: 50

      add :campaign_id, references(:ad_campaigns, on_delete: :nilify_all)
      add :creative_id, references(:ad_creatives, on_delete: :nilify_all)
      add :offer_id, references(:ad_offers, on_delete: :nilify_all)

      # Conversion events
      add :first_visit_at, :utc_datetime
      add :signup_at, :utc_datetime
      add :first_engagement_at, :utc_datetime
      add :first_purchase_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:ad_attributions, [:user_id])
    create index(:ad_attributions, [:campaign_id])
    create index(:ad_attributions, [:referral_code])
  end
end
