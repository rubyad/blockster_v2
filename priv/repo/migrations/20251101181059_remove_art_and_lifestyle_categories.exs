defmodule BlocksterV2.Repo.Migrations.RemoveArtAndLifestyleCategories do
  use Ecto.Migration

  def up do
    # Set category_id to NULL for posts that have Art or Lifestyle categories
    execute """
    UPDATE posts
    SET category_id = NULL
    WHERE category_id IN (
      SELECT id FROM categories WHERE name IN ('Art', 'Lifestyle')
    )
    """

    # Delete Art and Lifestyle categories
    execute "DELETE FROM categories WHERE name IN ('Art', 'Lifestyle')"
  end

  def down do
    # Re-insert Art and Lifestyle categories
    execute """
    INSERT INTO categories (name, slug, inserted_at, updated_at) VALUES
      ('Art', 'art', NOW(), NOW()),
      ('Lifestyle', 'lifestyle', NOW(), NOW())
    ON CONFLICT (name) DO NOTHING
    """

    # Note: We cannot restore the previous category_id associations
    # as that data is lost when set to NULL in the up migration
  end
end
