defmodule BlocksterV2.Repo.Migrations.AddRevisionCountToPublishQueue do
  use Ecto.Migration

  def change do
    alter table(:content_publish_queue) do
      add :revision_count, :integer, default: 0
    end
  end
end
