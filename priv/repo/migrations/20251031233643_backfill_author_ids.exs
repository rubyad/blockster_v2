defmodule BlocksterV2.Repo.Migrations.BackfillAuthorIds do
  use Ecto.Migration

  def up do
    # Update posts with author_name but no author_id by matching username
    execute """
    UPDATE posts
    SET author_id = users.id
    FROM users
    WHERE posts.author_name = users.username
    AND posts.author_id IS NULL
    """
  end

  def down do
    # This is a data migration, we don't want to reverse it
    :ok
  end
end
