defmodule BlocksterV2.Repo.Migrations.AddMetadataToEmailLog do
  use Ecto.Migration

  def change do
    alter table(:notification_email_log) do
      add :metadata, :map, default: %{}
    end
  end
end
