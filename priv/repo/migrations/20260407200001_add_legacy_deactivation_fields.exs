defmodule BlocksterV2.Repo.Migrations.AddLegacyDeactivationFields do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :is_active, :boolean, default: true, null: false
      add :merged_into_user_id, references(:users, on_delete: :nilify_all)
      add :deactivated_at, :utc_datetime
      add :pending_email, :string
    end

    create index(:users, [:merged_into_user_id])
    create index(:users, [:is_active])
  end
end
