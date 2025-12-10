defmodule BlocksterV2.Repo.Migrations.AddBaseBuxRewardToPosts do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      add :base_bux_reward, :integer, default: 1, null: false
    end
  end
end
