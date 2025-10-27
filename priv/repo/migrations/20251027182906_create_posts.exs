defmodule BlocksterV2.Repo.Migrations.CreatePosts do
  use Ecto.Migration

  def change do
    create table(:posts) do
      add :title, :string, null: false
      add :slug, :string, null: false
      add :content, :map, null: false, default: %{}
      add :excerpt, :text
      add :author_name, :string, null: false
      add :published_at, :utc_datetime
      add :view_count, :integer, default: 0
      add :category, :string

      timestamps()
    end

    create unique_index(:posts, [:slug])
    create index(:posts, [:published_at])
    create index(:posts, [:category])
  end
end
