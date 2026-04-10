defmodule BlocksterV2.Repo.Migrations.AddTemplateToAdBanners do
  use Ecto.Migration

  def change do
    alter table(:ad_banners) do
      add :template, :string, default: "image"
      add :params, :map, default: %{}
    end
  end
end
