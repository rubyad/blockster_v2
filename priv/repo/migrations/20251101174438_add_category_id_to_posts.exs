defmodule BlocksterV2.Repo.Migrations.AddCategoryIdToPosts do
  use Ecto.Migration

  def up do
    # First, seed the categories table
    execute """
    INSERT INTO categories (name, slug, inserted_at, updated_at) VALUES
      ('Blockchain', 'blockchain', NOW(), NOW()),
      ('Market Analysis', 'market-analysis', NOW(), NOW()),
      ('Investment', 'investment', NOW(), NOW()),
      ('Events', 'events', NOW(), NOW()),
      ('Crypto Trading', 'crypto-trading', NOW(), NOW()),
      ('People', 'people', NOW(), NOW()),
      ('DeFi', 'defi', NOW(), NOW()),
      ('Announcements', 'announcements', NOW(), NOW()),
      ('Gaming', 'gaming', NOW(), NOW()),
      ('Tech', 'tech', NOW(), NOW()),
      ('Art', 'art', NOW(), NOW()),
      ('Lifestyle', 'lifestyle', NOW(), NOW()),
      ('Business', 'business', NOW(), NOW())
    ON CONFLICT (name) DO NOTHING
    """

    # Add category_id column
    alter table(:posts) do
      add :category_id, references(:categories, on_delete: :nilify_all)
    end

    create index(:posts, [:category_id])

    # Migrate existing category strings to category_id
    execute """
    UPDATE posts
    SET category_id = categories.id
    FROM categories
    WHERE posts.category = categories.name
    """

    # Keep the old category column for now (we can remove it later after verification)
  end

  def down do
    # Restore category strings from category_id
    execute """
    UPDATE posts
    SET category = categories.name
    FROM categories
    WHERE posts.category_id = categories.id
    """

    drop index(:posts, [:category_id])

    alter table(:posts) do
      remove :category_id
    end
  end
end
