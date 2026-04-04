defmodule BlocksterV2.Migration.LegacyBuxMigration do
  use Ecto.Schema
  import Ecto.Changeset

  schema "legacy_bux_migrations" do
    field :email, :string
    field :legacy_bux_balance, :decimal
    field :legacy_wallet_address, :string
    field :new_wallet_address, :string
    field :mint_tx_signature, :string
    field :migrated, :boolean, default: false
    field :migrated_at, :utc_datetime

    timestamps()
  end

  def changeset(migration, attrs) do
    migration
    |> cast(attrs, [:email, :legacy_bux_balance, :legacy_wallet_address,
                    :new_wallet_address, :mint_tx_signature, :migrated, :migrated_at])
    |> validate_required([:email, :legacy_bux_balance])
    |> update_change(:email, &String.downcase/1)
    |> unique_constraint(:email)
  end
end
