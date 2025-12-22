defmodule BlocksterV2.Repo.Migrations.AddMaxInventoryToProducts do
  use Ecto.Migration

  def change do
    alter table(:products) do
      add :max_inventory, :integer
      add :sold_count, :integer, default: 0
    end
  end
end
