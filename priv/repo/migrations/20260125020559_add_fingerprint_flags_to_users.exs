defmodule BlocksterV2.Repo.Migrations.AddFingerprintFlagsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      # Flag for users who attempted multi-account abuse
      add :is_flagged_multi_account_attempt, :boolean, default: false

      # Timestamp of last suspicious activity
      add :last_suspicious_activity_at, :utc_datetime

      # Number of devices registered for this user
      add :registered_devices_count, :integer, default: 0
    end

    create index(:users, [:is_flagged_multi_account_attempt])
  end
end
