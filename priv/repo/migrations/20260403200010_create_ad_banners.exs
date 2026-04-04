defmodule BlocksterV2.Repo.Migrations.CreateAdBanners do
  use Ecto.Migration

  def change do
    create table(:ad_banners) do
      add :name, :string, null: false
      add :image_url, :string
      add :link_url, :string
      add :placement, :string, null: false
      add :dimensions, :string
      add :is_active, :boolean, default: true
      add :impressions, :integer, default: 0
      add :clicks, :integer, default: 0
      add :start_date, :date
      add :end_date, :date
      timestamps()
    end

    create index(:ad_banners, [:placement])
    create index(:ad_banners, [:is_active])
  end
end
