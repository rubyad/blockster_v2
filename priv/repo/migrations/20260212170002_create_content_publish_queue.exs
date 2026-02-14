defmodule BlocksterV2.Repo.Migrations.CreateContentPublishQueue do
  use Ecto.Migration

  def change do
    create table(:content_publish_queue, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :article_data, :map, null: false
      add :author_id, references(:users, on_delete: :nilify_all)
      add :scheduled_at, :utc_datetime
      add :status, :string, default: "pending"
      add :pipeline_id, :binary_id
      add :topic_id, references(:content_generated_topics, type: :binary_id, on_delete: :nilify_all)
      add :post_id, references(:posts, on_delete: :nilify_all)
      add :rejected_reason, :text
      add :reviewed_at, :utc_datetime
      add :reviewed_by, references(:users, on_delete: :nilify_all)

      timestamps()
    end

    create index(:content_publish_queue, [:status])
    create index(:content_publish_queue, [:scheduled_at])
    create index(:content_publish_queue, [:pipeline_id])
  end
end
