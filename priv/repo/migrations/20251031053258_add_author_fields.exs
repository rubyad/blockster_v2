defmodule BlocksterV2.Repo.Migrations.AddAuthorFields do
  use Ecto.Migration

  def change do
    # Add is_author field to users table
    alter table(:users) do
      add :is_author, :boolean, default: false, null: false
    end

    # Add author_id field to posts table
    alter table(:posts) do
      add :author_id, references(:users, on_delete: :nilify_all)
    end

    # Set admin users as authors by default
    execute """
    UPDATE users
    SET is_author = true
    WHERE is_admin = true
    """, """
    UPDATE users
    SET is_author = false
    WHERE is_admin = true
    """

    # Create index for faster author queries
    create index(:posts, [:author_id])
  end
end
