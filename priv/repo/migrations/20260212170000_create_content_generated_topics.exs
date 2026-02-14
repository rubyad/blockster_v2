defmodule BlocksterV2.Repo.Migrations.CreateContentGeneratedTopics do
  use Ecto.Migration

  def change do
    create table(:content_generated_topics, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :category, :string
      add :source_urls, {:array, :string}, default: []
      add :rank_score, :float
      add :source_count, :integer
      add :article_id, references(:posts, on_delete: :nilify_all)
      add :author_id, references(:users, on_delete: :nilify_all)
      add :pipeline_id, :binary_id
      add :published_at, :utc_datetime

      timestamps()
    end

    create index(:content_generated_topics, [:category])
    create index(:content_generated_topics, [:inserted_at])
    create index(:content_generated_topics, [:pipeline_id])
  end
end
