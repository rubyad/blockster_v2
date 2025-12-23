defmodule BlocksterV2.Repo.Migrations.CreateArtists do
  use Ecto.Migration

  def change do
    create table(:artists) do
      add :name, :string, null: false
      add :slug, :string, null: false
      add :image, :string
      add :description, :text
      add :website, :string

      # Social URLs (same as hubs)
      add :twitter_url, :string
      add :telegram_url, :string
      add :instagram_url, :string
      add :linkedin_url, :string
      add :tiktok_url, :string
      add :discord_url, :string
      add :reddit_url, :string
      add :youtube_url, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:artists, [:slug])
    create index(:artists, [:name])

    # Add artist_id to products
    alter table(:products) do
      add :artist_id, references(:artists, on_delete: :nilify_all)
    end

    create index(:products, [:artist_id])
  end
end
