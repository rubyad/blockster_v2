defmodule BlocksterV2.Repo.Migrations.AddFeaturedImageToPosts do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      add :featured_image, :string
    end
  end
end
