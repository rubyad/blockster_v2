defmodule BlocksterV2.Repo.Migrations.CreateAiManagerLogs do
  use Ecto.Migration

  def change do
    create table(:ai_manager_logs) do
      add :review_type, :string, null: false
      add :input_summary, :text
      add :output_summary, :text
      add :changes_made, :map, default: %{}

      timestamps(updated_at: false)
    end

    create index(:ai_manager_logs, [:review_type])
    create index(:ai_manager_logs, [:inserted_at])
  end
end
