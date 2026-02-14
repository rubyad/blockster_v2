defmodule BlocksterV2.Repo.Migrations.CreateContentFeedItems do
  use Ecto.Migration

  def change do
    create table(:content_feed_items) do
      add :url, :string, null: false
      add :title, :string, null: false
      add :summary, :text
      add :source, :string, null: false
      add :tier, :string, null: false
      add :weight, :float, default: 1.0
      add :published_at, :utc_datetime
      add :fetched_at, :utc_datetime, null: false
      add :processed, :boolean, default: false
      add :topic_cluster_id, references(:content_generated_topics, type: :binary_id, on_delete: :nilify_all)

      timestamps()
    end

    create unique_index(:content_feed_items, [:url])
    create index(:content_feed_items, [:source])
    create index(:content_feed_items, [:processed])
    create index(:content_feed_items, [:fetched_at])
  end
end
