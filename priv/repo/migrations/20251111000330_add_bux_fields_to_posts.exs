defmodule BlocksterV2.Repo.Migrations.AddBuxFieldsToPosts do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      add :bux_total, :integer, default: 0
      add :bux_earned, :integer, default: 0
      add :value, :decimal, precision: 10, scale: 2
      add :tx_id, :string
      add :contact, :string
    end
  end
end
