defmodule BlocksterV2.Repo.Migrations.CreateWaitlistEmails do
  use Ecto.Migration

  def change do
    create table(:waitlist_emails) do
      add :email, :string, null: false
      add :verification_token, :string
      add :verified_at, :utc_datetime
      add :token_sent_at, :utc_datetime

      timestamps()
    end

    create unique_index(:waitlist_emails, [:email])
    create index(:waitlist_emails, [:verification_token])
  end
end
