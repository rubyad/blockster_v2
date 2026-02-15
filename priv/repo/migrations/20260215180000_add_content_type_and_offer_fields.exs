defmodule BlocksterV2.Repo.Migrations.AddContentTypeAndOfferFields do
  use Ecto.Migration

  def change do
    alter table(:content_generated_topics) do
      add :content_type, :string, default: "news"
      add :offer_type, :string
      add :expires_at, :utc_datetime
    end

    alter table(:content_publish_queue) do
      add :content_type, :string, default: "news"
      add :offer_type, :string
      add :expires_at, :utc_datetime
      add :cta_url, :string
      add :cta_text, :string
    end
  end
end
