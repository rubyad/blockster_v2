defmodule BlocksterV2.Repo.Migrations.AddSearchableToPosts do
  use Ecto.Migration

  def up do
    # Add tsvector column for full-text search
    alter table(:posts) do
      add :searchable, :tsvector
    end

    # Create GIN index for better search performance
    create index(:posts, [:searchable], using: :gin)

    # Create trigger function to automatically update searchable column
    execute """
    CREATE OR REPLACE FUNCTION posts_searchable_trigger() RETURNS trigger AS $$
    BEGIN
      NEW.searchable :=
        setweight(to_tsvector('english', coalesce(NEW.title, '')), 'A') ||
        setweight(to_tsvector('english', coalesce(NEW.excerpt, '')), 'B') ||
        setweight(to_tsvector('english', coalesce(NEW.content::text, '')), 'C');
      RETURN NEW;
    END
    $$ LANGUAGE plpgsql;
    """

    # Create trigger to update searchable on insert/update
    execute """
    CREATE TRIGGER posts_searchable_update
    BEFORE INSERT OR UPDATE ON posts
    FOR EACH ROW
    EXECUTE FUNCTION posts_searchable_trigger();
    """

    # Populate existing posts with searchable data
    execute """
    UPDATE posts SET searchable =
      setweight(to_tsvector('english', coalesce(title, '')), 'A') ||
      setweight(to_tsvector('english', coalesce(excerpt, '')), 'B') ||
      setweight(to_tsvector('english', coalesce(content::text, '')), 'C');
    """
  end

  def down do
    execute "DROP TRIGGER IF EXISTS posts_searchable_update ON posts;"
    execute "DROP FUNCTION IF EXISTS posts_searchable_trigger();"
    drop index(:posts, [:searchable])

    alter table(:posts) do
      remove :searchable
    end
  end
end
