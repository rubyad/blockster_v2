defmodule BlocksterV2.Repo.Migrations.CreateUserFingerprints do
  use Ecto.Migration

  def change do
    create table(:user_fingerprints) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :fingerprint_id, :string, null: false
      add :fingerprint_confidence, :float
      add :device_name, :string  # Optional: "iPhone", "Chrome on Mac", etc.
      add :last_seen_at, :utc_datetime
      add :first_seen_at, :utc_datetime, null: false
      add :is_primary, :boolean, default: false  # First device registered

      timestamps()
    end

    # A fingerprint can only belong to ONE user (anti-sybil rule)
    create unique_index(:user_fingerprints, [:fingerprint_id])

    # Fast lookup: find all fingerprints for a user
    create index(:user_fingerprints, [:user_id])
  end
end
