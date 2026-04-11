defmodule BlocksterV2.Repo.Migrations.AddBioAndXHandleToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :bio, :text
      add :x_handle, :string
    end
  end
end
