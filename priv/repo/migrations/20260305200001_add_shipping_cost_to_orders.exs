defmodule BlocksterV2.Repo.Migrations.AddShippingCostToOrders do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      add :shipping_cost, :decimal, precision: 10, scale: 2, default: 0
      add :shipping_method, :string
    end
  end
end
