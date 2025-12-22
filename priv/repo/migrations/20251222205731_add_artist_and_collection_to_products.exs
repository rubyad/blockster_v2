defmodule BlocksterV2.Repo.Migrations.AddArtistAndCollectionToProducts do
  use Ecto.Migration

  def change do
    alter table(:products) do
      add :artist, :string
      add :collection_name, :string
    end
  end
end
