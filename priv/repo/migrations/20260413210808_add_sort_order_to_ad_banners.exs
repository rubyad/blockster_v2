defmodule BlocksterV2.Repo.Migrations.AddSortOrderToAdBanners do
  use Ecto.Migration

  def change do
    alter table(:ad_banners) do
      add :sort_order, :integer, default: 0, null: false
    end
  end
end
