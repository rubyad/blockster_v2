defmodule BlocksterV2.Repo.Migrations.AddLayoutToPosts do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      add :layout, :string, default: "default"
    end
  end
end
