defmodule BlocksterV2.Repo.Migrations.AddAdminToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :is_admin, :boolean, default: false, null: false
    end

    # Set adam@blockster.com users as admins
    execute """
    UPDATE users
    SET is_admin = true
    WHERE email LIKE 'adam%@blockster.com'
    """, """
    UPDATE users
    SET is_admin = false
    WHERE email LIKE 'adam%@blockster.com'
    """
  end
end
