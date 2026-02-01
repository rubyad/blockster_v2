defmodule BlocksterV2.Repo.Migrations.AddReferrerToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :referrer_id, references(:users, on_delete: :nilify_all)
      add :referred_at, :utc_datetime
    end

    create index(:users, [:referrer_id])
  end
end
