defmodule BlocksterV2.Repo.Migrations.AddCustomPublishedAtToPosts do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      add :custom_published_at, :utc_datetime
    end
  end
end
