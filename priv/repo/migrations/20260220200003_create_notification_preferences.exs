defmodule BlocksterV2.Repo.Migrations.CreateNotificationPreferences do
  use Ecto.Migration

  def change do
    create table(:notification_preferences) do
      add :user_id, references(:users, on_delete: :delete_all), null: false

      # Email preferences
      add :email_new_articles, :boolean, default: true
      add :email_hub_posts, :boolean, default: true
      add :email_special_offers, :boolean, default: true
      add :email_daily_digest, :boolean, default: true
      add :email_weekly_roundup, :boolean, default: true
      add :email_referral_prompts, :boolean, default: true
      add :email_reward_alerts, :boolean, default: true
      add :email_shop_deals, :boolean, default: true
      add :email_account_updates, :boolean, default: true
      add :email_re_engagement, :boolean, default: true

      # SMS preferences
      add :sms_special_offers, :boolean, default: true
      add :sms_account_alerts, :boolean, default: true
      add :sms_milestone_rewards, :boolean, default: false

      # In-app preferences
      add :in_app_enabled, :boolean, default: true
      add :in_app_toast_enabled, :boolean, default: true
      add :in_app_sound_enabled, :boolean, default: false

      # Global controls
      add :email_enabled, :boolean, default: true
      add :sms_enabled, :boolean, default: true
      add :quiet_hours_start, :time, default: nil
      add :quiet_hours_end, :time, default: nil
      add :timezone, :string, default: "UTC"

      # Frequency controls
      add :max_emails_per_day, :integer, default: 3
      add :max_sms_per_week, :integer, default: 1

      # Unsubscribe token
      add :unsubscribe_token, :string

      timestamps()
    end

    create unique_index(:notification_preferences, [:user_id])
    create index(:notification_preferences, [:unsubscribe_token])
  end
end
