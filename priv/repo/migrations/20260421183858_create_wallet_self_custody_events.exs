defmodule BlocksterV2.Repo.Migrations.CreateWalletSelfCustodyEvents do
  use Ecto.Migration

  def change do
    create table(:wallet_self_custody_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :nilify_all), null: false

      # One of: withdrawal_initiated | withdrawal_confirmed | withdrawal_failed |
      # key_exported | export_reauth_completed
      add :event_type, :string, null: false

      # Metadata ONLY — never private key material. Safe keys:
      # amount (string), to (pubkey), signature (tx sig), format ("base58"|"hex"|"qr"),
      # error (error message), ip_hash (hashed if we need fingerprinting).
      add :metadata, :map, null: false, default: %{}

      # Request context for incident response.
      add :ip_address, :string
      add :user_agent, :string

      timestamps(type: :utc_datetime)
    end

    create index(:wallet_self_custody_events, [:user_id])
    create index(:wallet_self_custody_events, [:event_type])
    create index(:wallet_self_custody_events, [:user_id, :inserted_at])
  end
end
