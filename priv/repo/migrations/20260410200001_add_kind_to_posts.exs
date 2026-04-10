defmodule BlocksterV2.Repo.Migrations.AddKindToPosts do
  use Ecto.Migration

  def up do
    alter table(:posts) do
      add :kind, :string, default: "other", null: false
    end

    # Backfill all existing posts as "other"
    execute "UPDATE posts SET kind = 'other' WHERE kind IS NULL"

    # Index for filtering by kind (used by News/Videos tabs on hub show)
    create index(:posts, [:kind])
    create index(:posts, [:hub_id, :kind])
  end

  def down do
    drop_if_exists index(:posts, [:hub_id, :kind])
    drop_if_exists index(:posts, [:kind])

    alter table(:posts) do
      remove :kind
    end
  end
end
