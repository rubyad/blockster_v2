defmodule BlocksterV2.Repo.Migrations.AddWidgetColumnsToAdBanners do
  use Ecto.Migration

  def change do
    alter table(:ad_banners) do
      add :widget_type, :string
      add :widget_config, :map, default: %{}
    end

    create index(:ad_banners, [:widget_type])
  end
end
