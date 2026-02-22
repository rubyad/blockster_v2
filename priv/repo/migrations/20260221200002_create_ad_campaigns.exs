defmodule BlocksterV2.Repo.Migrations.CreateAdCampaigns do
  use Ecto.Migration

  def change do
    create table(:ad_campaigns) do
      add :account_id, references(:ad_platform_accounts, on_delete: :nilify_all)
      add :platform, :string, null: false, size: 20
      add :platform_campaign_id, :string, size: 255
      add :name, :string, null: false, size: 255
      add :status, :string, null: false, default: "draft", size: 30
      add :objective, :string, null: false, size: 50

      # What we're promoting
      add :content_type, :string, size: 30
      add :content_id, :bigint

      # Budget
      add :budget_daily, :decimal, precision: 10, scale: 2
      add :budget_lifetime, :decimal, precision: 10, scale: 2
      add :spend_total, :decimal, precision: 10, scale: 2, default: 0

      # Targeting
      add :targeting_config, :map, default: %{}

      # Who created it and how
      add :created_by, :string, default: "ai", size: 20
      add :created_by_user_id, references(:users, on_delete: :nilify_all)
      add :ai_confidence_score, :decimal, precision: 3, scale: 2
      add :admin_override, :boolean, default: false
      add :admin_notes, :text

      # Scheduling
      add :scheduled_start, :utc_datetime
      add :scheduled_end, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:ad_campaigns, [:status])
    create index(:ad_campaigns, [:platform])
    create index(:ad_campaigns, [:content_type, :content_id])
    create index(:ad_campaigns, [:account_id])
  end
end
