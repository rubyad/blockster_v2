defmodule BlocksterV2.Repo.Migrations.CreateNotificationCampaigns do
  use Ecto.Migration

  def change do
    create table(:notification_campaigns) do
      add :name, :string, null: false
      add :type, :string, null: false
      add :status, :string, default: "draft"

      # Content
      add :subject, :string
      add :title, :string
      add :body, :text
      add :plain_text_body, :text
      add :image_url, :string
      add :action_url, :string
      add :action_label, :string

      # Targeting
      add :target_audience, :string, default: "all"
      add :target_hub_id, references(:hubs, on_delete: :nilify_all)
      add :target_criteria, :map, default: %{}

      # Channels
      add :send_email, :boolean, default: true
      add :send_sms, :boolean, default: false
      add :send_in_app, :boolean, default: true

      # Scheduling
      add :scheduled_at, :utc_datetime
      add :sent_at, :utc_datetime
      add :timezone_aware, :boolean, default: true

      # Stats
      add :total_recipients, :integer, default: 0
      add :emails_sent, :integer, default: 0
      add :emails_opened, :integer, default: 0
      add :emails_clicked, :integer, default: 0
      add :sms_sent, :integer, default: 0
      add :in_app_delivered, :integer, default: 0
      add :in_app_read, :integer, default: 0

      add :created_by_id, references(:users, on_delete: :nilify_all)

      timestamps()
    end

    create index(:notification_campaigns, [:status])
    create index(:notification_campaigns, [:scheduled_at])
  end
end
