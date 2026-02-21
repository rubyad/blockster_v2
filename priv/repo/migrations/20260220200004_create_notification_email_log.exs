defmodule BlocksterV2.Repo.Migrations.CreateNotificationEmailLog do
  use Ecto.Migration

  def change do
    create table(:notification_email_log) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :notification_id, references(:notifications, on_delete: :nilify_all)
      add :campaign_id, references(:notification_campaigns, on_delete: :nilify_all)
      add :email_type, :string, null: false
      add :subject, :string
      add :sent_at, :utc_datetime, null: false
      add :opened_at, :utc_datetime
      add :clicked_at, :utc_datetime
      add :bounced, :boolean, default: false
      add :unsubscribed, :boolean, default: false
      add :sendgrid_message_id, :string

      timestamps()
    end

    create index(:notification_email_log, [:user_id, :sent_at])
    create index(:notification_email_log, [:campaign_id])
    create index(:notification_email_log, [:sendgrid_message_id])
  end
end
