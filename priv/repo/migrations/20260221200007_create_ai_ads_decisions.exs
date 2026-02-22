defmodule BlocksterV2.Repo.Migrations.CreateAiAdsDecisions do
  use Ecto.Migration

  def change do
    create table(:ai_ads_decisions) do
      add :decision_type, :string, null: false, size: 50
      add :input_context, :map, null: false
      add :reasoning, :text, null: false
      add :action_taken, :map, null: false
      add :outcome, :string, null: false, size: 20
      add :outcome_details, :map
      add :budget_impact, :decimal, precision: 10, scale: 2

      add :campaign_id, references(:ad_campaigns, on_delete: :nilify_all)
      add :platform, :string, size: 20
      add :admin_instruction_id, :bigint

      add :inserted_at, :utc_datetime, null: false, default: fragment("NOW()")
    end

    create index(:ai_ads_decisions, [:inserted_at])
    create index(:ai_ads_decisions, [:campaign_id])
    create index(:ai_ads_decisions, [:decision_type])
  end
end
