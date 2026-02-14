defmodule BlocksterV2.Repo.Migrations.CreateContentRevisionHistory do
  use Ecto.Migration

  def change do
    create table(:content_revision_history, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :queue_entry_id, references(:content_publish_queue, type: :binary_id, on_delete: :delete_all), null: false
      add :instruction, :text, null: false
      add :revision_number, :integer, null: false
      add :article_data_before, :map, null: false
      add :article_data_after, :map
      add :status, :string, default: "pending"
      add :error_reason, :text
      add :requested_by, references(:users, on_delete: :nilify_all)

      timestamps()
    end

    create index(:content_revision_history, [:queue_entry_id])
  end
end
