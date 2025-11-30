defmodule BlocksterV2.Repo.Migrations.CreateEventTags do
  use Ecto.Migration

  def change do
    create table(:event_tags, primary_key: false) do
      add :event_id, references(:events, on_delete: :delete_all), null: false
      add :tag_id, references(:tags, on_delete: :delete_all), null: false
    end

    create index(:event_tags, [:event_id])
    create index(:event_tags, [:tag_id])
    create unique_index(:event_tags, [:event_id, :tag_id])
  end
end
