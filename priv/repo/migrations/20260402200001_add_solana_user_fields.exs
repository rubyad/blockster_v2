defmodule BlocksterV2.Repo.Migrations.AddSolanaUserFields do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :email_verified, :boolean, default: false
      add :email_verification_code, :string
      add :email_verification_sent_at, :utc_datetime
      add :legacy_email, :string
    end

    # Index for legacy email lookups during BUX migration
    create index(:users, [:legacy_email], where: "legacy_email IS NOT NULL")
  end
end
