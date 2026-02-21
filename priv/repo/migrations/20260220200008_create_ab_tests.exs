defmodule BlocksterV2.Repo.Migrations.CreateAbTests do
  use Ecto.Migration

  def change do
    create table(:ab_tests) do
      add :name, :string, null: false
      add :email_type, :string, null: false
      add :element_tested, :string, null: false
      add :status, :string, default: "running"
      add :variants, {:array, :map}, default: []
      add :start_date, :utc_datetime, null: false
      add :end_date, :utc_datetime
      add :min_sample_size, :integer, default: 100
      add :confidence_threshold, :float, default: 0.95
      add :winning_variant, :string
      add :results, :map, default: %{}

      timestamps()
    end

    create index(:ab_tests, [:email_type, :status])
    create index(:ab_tests, [:status])

    create table(:ab_test_assignments) do
      add :ab_test_id, references(:ab_tests, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :variant_id, :string, null: false
      add :email_log_id, references(:notification_email_log, on_delete: :nilify_all)
      add :opened, :boolean, default: false
      add :clicked, :boolean, default: false

      timestamps(updated_at: false)
    end

    create unique_index(:ab_test_assignments, [:ab_test_id, :user_id])
    create index(:ab_test_assignments, [:ab_test_id, :variant_id])
  end
end
