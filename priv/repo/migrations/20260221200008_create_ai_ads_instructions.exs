defmodule BlocksterV2.Repo.Migrations.CreateAiAdsInstructions do
  use Ecto.Migration

  def change do
    create table(:ai_ads_instructions) do
      add :admin_user_id, references(:users, on_delete: :nilify_all), null: false
      add :instruction_text, :text, null: false
      add :parsed_intent, :map
      add :actions_taken, :map
      add :status, :string, default: "pending", size: 20
      add :completed_at, :utc_datetime

      add :inserted_at, :utc_datetime, null: false, default: fragment("NOW()")
    end

    create index(:ai_ads_instructions, [:status])
    create index(:ai_ads_instructions, [:admin_user_id])
  end
end
