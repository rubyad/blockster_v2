defmodule BlocksterV2.Repo.Migrations.AddTxHashToShareRewards do
  use Ecto.Migration

  def change do
    alter table(:share_rewards) do
      add :tx_hash, :string
    end
  end
end
