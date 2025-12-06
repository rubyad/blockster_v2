defmodule BlocksterV2.Repo.Migrations.AddSocialMediaUrlsToHubs do
  use Ecto.Migration

  def change do
    alter table(:hubs) do
      add :twitter_url, :string
      add :telegram_url, :string
      add :instagram_url, :string
      add :linkedin_url, :string
      add :tiktok_url, :string
      add :discord_url, :string
      add :reddit_url, :string
    end
  end
end
