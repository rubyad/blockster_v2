defmodule BlocksterV2.Repo.Migrations.ImprovePostAssociationsAndIndexes do
  use Ecto.Migration

  def up do
    # Add missing indexes for foreign keys and commonly queried fields
    create_if_not_exists index(:posts, [:author_id])
    create_if_not_exists index(:posts, [:published_at, :id])  # Composite for efficient pagination

    # Remove redundant category string field (we have category_id FK now)
    alter table(:posts) do
      remove_if_exists :category, :string
    end

    # Remove redundant author_name field (will be computed from author association)
    alter table(:posts) do
      remove_if_exists :author_name, :string
    end
  end

  def down do
    # Re-add the fields if rolling back
    alter table(:posts) do
      add_if_not_exists :category, :string
      add_if_not_exists :author_name, :string, null: false, default: "Unknown"
    end

    # Drop the indexes
    drop_if_exists index(:posts, [:author_id])
    drop_if_exists index(:posts, [:published_at, :id])
  end
end
