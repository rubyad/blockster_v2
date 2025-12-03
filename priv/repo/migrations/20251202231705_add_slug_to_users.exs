defmodule BlocksterV2.Repo.Migrations.AddSlugToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :slug, :string
    end

    create unique_index(:users, [:slug])

    # Generate slugs for existing users with usernames
    execute """
    UPDATE users
    SET slug = LOWER(REPLACE(username, ' ', '-'))
    WHERE username IS NOT NULL AND username != ''
    """, ""
  end
end
