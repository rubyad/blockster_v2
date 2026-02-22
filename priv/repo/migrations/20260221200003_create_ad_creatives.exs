defmodule BlocksterV2.Repo.Migrations.CreateAdCreatives do
  use Ecto.Migration

  def change do
    create table(:ad_creatives) do
      add :campaign_id, references(:ad_campaigns, on_delete: :delete_all)
      add :platform, :string, null: false, size: 20
      add :platform_creative_id, :string, size: 255

      # Creative content
      add :type, :string, null: false, size: 20
      add :headline, :string, size: 500
      add :body, :text
      add :cta_text, :string, size: 100
      add :image_url, :string, size: 500
      add :video_url, :string, size: 500
      add :hashtags, {:array, :string}, default: []

      # Source tracking
      add :source, :string, null: false, default: "ai", size: 20
      add :source_details, :map
      add :admin_override, :boolean, default: false

      # Performance
      add :status, :string, default: "draft", size: 20
      add :impressions, :bigint, default: 0
      add :clicks, :bigint, default: 0
      add :conversions, :integer, default: 0
      add :performance_score, :decimal, precision: 5, scale: 2

      # A/B testing
      add :variant_group, :string, size: 50
      add :is_winner, :boolean, default: false

      timestamps(type: :utc_datetime)
    end

    create index(:ad_creatives, [:campaign_id])
    create index(:ad_creatives, [:status])
  end
end
