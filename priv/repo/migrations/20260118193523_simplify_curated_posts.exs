defmodule BlocksterV2.Repo.Migrations.SimplifyCuratedPosts do
  use Ecto.Migration

  def up do
    # First, clear all existing curated posts (fresh start)
    execute "DELETE FROM curated_posts"

    # Drop the old unique constraint
    drop_if_exists unique_index(:curated_posts, [:section, :position])

    # Remove section column
    alter table(:curated_posts) do
      remove :section
    end

    # Add new unique constraint on position alone
    create unique_index(:curated_posts, [:position])
  end

  def down do
    drop_if_exists unique_index(:curated_posts, [:position])

    alter table(:curated_posts) do
      add :section, :string
    end

    create unique_index(:curated_posts, [:section, :position])
  end
end
