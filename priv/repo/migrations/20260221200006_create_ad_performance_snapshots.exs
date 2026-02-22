defmodule BlocksterV2.Repo.Migrations.CreateAdPerformanceSnapshots do
  use Ecto.Migration

  def change do
    create table(:ad_performance_snapshots) do
      add :campaign_id, references(:ad_campaigns, on_delete: :delete_all)
      add :creative_id, references(:ad_creatives, on_delete: :nilify_all)
      add :platform, :string, null: false, size: 20

      add :snapshot_at, :utc_datetime, null: false

      add :impressions, :bigint, default: 0
      add :clicks, :bigint, default: 0
      add :conversions, :integer, default: 0
      add :spend, :decimal, precision: 10, scale: 2, default: 0

      # Computed metrics
      add :ctr, :decimal, precision: 8, scale: 4
      add :cpc, :decimal, precision: 8, scale: 4
      add :cpm, :decimal, precision: 8, scale: 4
      add :roas, :decimal, precision: 8, scale: 4

      # Platform-specific
      add :platform_metrics, :map, default: %{}

      add :inserted_at, :utc_datetime, null: false, default: fragment("NOW()")
    end

    create index(:ad_performance_snapshots, [:campaign_id, :snapshot_at])
    create index(:ad_performance_snapshots, [:snapshot_at])
  end
end
