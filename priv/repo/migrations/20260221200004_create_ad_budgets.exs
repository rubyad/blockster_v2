defmodule BlocksterV2.Repo.Migrations.CreateAdBudgets do
  use Ecto.Migration

  def change do
    create table(:ad_budgets) do
      add :platform, :string, size: 20
      add :period_type, :string, null: false, size: 10
      add :period_start, :date, null: false
      add :period_end, :date, null: false

      add :allocated_amount, :decimal, precision: 10, scale: 2, null: false
      add :spent_amount, :decimal, precision: 10, scale: 2, default: 0

      add :status, :string, default: "active", size: 20

      timestamps(type: :utc_datetime)
    end

    create index(:ad_budgets, [:platform, :period_start])
    create index(:ad_budgets, [:status])

    create table(:ad_budget_adjustments) do
      add :budget_id, references(:ad_budgets, on_delete: :delete_all)
      add :campaign_id, references(:ad_campaigns, on_delete: :nilify_all)

      add :old_amount, :decimal, precision: 10, scale: 2
      add :new_amount, :decimal, precision: 10, scale: 2
      add :reason, :text, null: false
      add :decided_by, :string, null: false, size: 50

      add :inserted_at, :utc_datetime, null: false, default: fragment("NOW()")
    end

    create index(:ad_budget_adjustments, [:budget_id])
  end
end
