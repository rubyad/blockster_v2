defmodule BlocksterV2.Repo.Migrations.AddFeaturedImageToEvents do
  use Ecto.Migration

  def change do
    alter table(:events) do
      add :featured_image, :string
    end
  end
end
