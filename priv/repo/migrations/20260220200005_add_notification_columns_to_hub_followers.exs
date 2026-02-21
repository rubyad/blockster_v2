defmodule BlocksterV2.Repo.Migrations.AddNotificationColumnsToHubFollowers do
  use Ecto.Migration

  def change do
    alter table(:hub_followers) do
      add :notify_new_posts, :boolean, default: true
      add :notify_events, :boolean, default: true
      add :email_notifications, :boolean, default: true
      add :in_app_notifications, :boolean, default: true
    end
  end
end
