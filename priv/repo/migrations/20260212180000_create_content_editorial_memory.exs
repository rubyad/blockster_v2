defmodule BlocksterV2.Repo.Migrations.CreateContentEditorialMemory do
  use Ecto.Migration

  def change do
    create table(:content_editorial_memory, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :instruction, :text, null: false
      add :category, :string, default: "global"
      add :active, :boolean, default: true
      add :created_by, references(:users, on_delete: :nilify_all)
      add :source_queue_entry_id, references(:content_publish_queue, type: :binary_id, on_delete: :nilify_all)

      timestamps()
    end

    create index(:content_editorial_memory, [:active])
    create index(:content_editorial_memory, [:category])
  end
end
