defmodule BlocksterV2.Repo.Migrations.CreateNotifications do
  use Ecto.Migration

  def change do
    create table(:notifications) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :type, :string, null: false
      add :category, :string, null: false
      add :title, :string, null: false
      add :body, :text
      add :image_url, :string
      add :action_url, :string
      add :action_label, :string

      # Flexible metadata
      add :metadata, :map, default: %{}

      # State
      add :read_at, :utc_datetime
      add :dismissed_at, :utc_datetime
      add :clicked_at, :utc_datetime

      # Delivery tracking
      add :email_sent_at, :utc_datetime
      add :sms_sent_at, :utc_datetime
      add :push_sent_at, :utc_datetime

      # Campaign linkage
      add :campaign_id, references(:notification_campaigns, on_delete: :nilify_all)

      timestamps()
    end

    create index(:notifications, [:user_id, :read_at])
    create index(:notifications, [:user_id, :inserted_at])
    create index(:notifications, [:type])
    create index(:notifications, [:campaign_id])
  end
end
