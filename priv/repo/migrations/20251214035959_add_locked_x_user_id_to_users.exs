defmodule BlocksterV2.Repo.Migrations.AddLockedXUserIdToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :locked_x_user_id, :string
    end

    # Each X account can only be locked to one user
    create unique_index(:users, [:locked_x_user_id], where: "locked_x_user_id IS NOT NULL")
  end
end
