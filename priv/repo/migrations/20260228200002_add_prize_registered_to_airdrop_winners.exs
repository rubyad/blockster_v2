defmodule BlocksterV2.Repo.Migrations.AddPrizeRegisteredToAirdropWinners do
  use Ecto.Migration

  def change do
    alter table(:airdrop_winners) do
      add :prize_registered, :boolean, default: false, null: false
    end
  end
end
