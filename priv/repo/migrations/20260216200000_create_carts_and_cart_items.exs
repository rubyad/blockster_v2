defmodule BlocksterV2.Repo.Migrations.CreateCartsAndCartItems do
  use Ecto.Migration

  def change do
    create table(:carts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:carts, [:user_id])

    create table(:cart_items, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :cart_id, references(:carts, type: :binary_id, on_delete: :delete_all), null: false
      add :product_id, references(:products, type: :binary_id), null: false
      add :variant_id, references(:product_variants, type: :binary_id)
      add :quantity, :integer, null: false, default: 1
      add :bux_tokens_to_redeem, :integer, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:cart_items, [:cart_id])

    create unique_index(:cart_items, [:cart_id, :product_id, :variant_id],
      name: :cart_items_unique_product_variant
    )
  end
end
