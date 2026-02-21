defmodule BlocksterV2.Notifications.NotificationPreference do
  use Ecto.Schema
  import Ecto.Changeset

  schema "notification_preferences" do
    # Email preferences
    field :email_new_articles, :boolean, default: true
    field :email_hub_posts, :boolean, default: true
    field :email_special_offers, :boolean, default: true
    field :email_daily_digest, :boolean, default: true
    field :email_weekly_roundup, :boolean, default: true
    field :email_referral_prompts, :boolean, default: true
    field :email_reward_alerts, :boolean, default: true
    field :email_shop_deals, :boolean, default: true
    field :email_account_updates, :boolean, default: true
    field :email_re_engagement, :boolean, default: true

    # SMS preferences
    field :sms_special_offers, :boolean, default: true
    field :sms_account_alerts, :boolean, default: true
    field :sms_milestone_rewards, :boolean, default: false

    # In-app preferences
    field :in_app_enabled, :boolean, default: true
    field :in_app_toast_enabled, :boolean, default: true
    field :in_app_sound_enabled, :boolean, default: false

    # Global controls
    field :email_enabled, :boolean, default: true
    field :sms_enabled, :boolean, default: true
    field :quiet_hours_start, :time, default: nil
    field :quiet_hours_end, :time, default: nil
    field :timezone, :string, default: "UTC"

    # Frequency controls
    field :max_emails_per_day, :integer, default: 3
    field :max_sms_per_week, :integer, default: 1

    # Unsubscribe token
    field :unsubscribe_token, :string

    belongs_to :user, BlocksterV2.Accounts.User

    timestamps()
  end

  def changeset(preference, attrs) do
    preference
    |> cast(attrs, [
      :user_id, :email_new_articles, :email_hub_posts, :email_special_offers,
      :email_daily_digest, :email_weekly_roundup, :email_referral_prompts,
      :email_reward_alerts, :email_shop_deals, :email_account_updates,
      :email_re_engagement, :sms_special_offers, :sms_account_alerts,
      :sms_milestone_rewards, :in_app_enabled, :in_app_toast_enabled,
      :in_app_sound_enabled, :email_enabled, :sms_enabled,
      :quiet_hours_start, :quiet_hours_end, :timezone,
      :max_emails_per_day, :max_sms_per_week, :unsubscribe_token
    ])
    |> validate_required([:user_id])
    |> validate_number(:max_emails_per_day, greater_than: 0, less_than_or_equal_to: 10)
    |> validate_number(:max_sms_per_week, greater_than_or_equal_to: 0, less_than_or_equal_to: 5)
    |> unique_constraint(:user_id)
    |> foreign_key_constraint(:user_id)
  end

  def generate_unsubscribe_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end
end
