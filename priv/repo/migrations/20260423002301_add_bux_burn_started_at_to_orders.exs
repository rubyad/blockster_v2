defmodule BlocksterV2.Repo.Migrations.AddBuxBurnStartedAtToOrders do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      add :bux_burn_started_at, :utc_datetime
    end
  end
end
