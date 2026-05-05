defmodule BlocksterV2.Repo.Migrations.AddSignupBonusGrantedAtToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :signup_bonus_granted_at, :utc_datetime
    end
  end
end
