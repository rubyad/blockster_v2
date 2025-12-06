defmodule BlocksterV2.Repo.Migrations.AddYoutubeUrlToHubs do
  use Ecto.Migration

  def change do
    alter table(:hubs) do
      add :youtube_url, :string
    end
  end
end
