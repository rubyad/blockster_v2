defmodule BlocksterV2.Repo.Migrations.CreateCuratedPosts do
  use Ecto.Migration

  def change do
    create table(:curated_posts) do
      add :section, :string, null: false  # "latest_news" or "conversations"
      add :position, :integer, null: false  # Position 1-10 for latest_news, 1-6 for conversations
      add :post_id, references(:posts, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:curated_posts, [:section, :position])
    create index(:curated_posts, [:post_id])
  end
end
