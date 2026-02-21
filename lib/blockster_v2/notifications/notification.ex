defmodule BlocksterV2.Notifications.Notification do
  use Ecto.Schema
  import Ecto.Changeset

  @valid_types ~w(new_article hub_post hub_event content_recommendation weekly_roundup
                  special_offer flash_sale shop_new_product shop_restock price_drop cart_abandonment
                  referral_prompt referral_signup referral_reward hub_milestone
                  bux_earned bux_milestone reward_summary multiplier_upgrade game_settlement
                  order_confirmed order_paid order_shipped order_delivered order_cancelled
                  order_processing order_bux_paid order_rogue_paid
                  welcome welcome_back re_engagement churn_intervention daily_bonus
                  account_security maintenance)

  @valid_categories ~w(content offers social rewards system)

  schema "notifications" do
    field :type, :string
    field :category, :string
    field :title, :string
    field :body, :string
    field :image_url, :string
    field :action_url, :string
    field :action_label, :string
    field :metadata, :map, default: %{}

    # State
    field :read_at, :utc_datetime
    field :dismissed_at, :utc_datetime
    field :clicked_at, :utc_datetime

    # Delivery tracking
    field :email_sent_at, :utc_datetime
    field :sms_sent_at, :utc_datetime
    field :push_sent_at, :utc_datetime

    belongs_to :user, BlocksterV2.Accounts.User
    belongs_to :campaign, BlocksterV2.Notifications.Campaign

    timestamps()
  end

  def changeset(notification, attrs) do
    notification
    |> cast(attrs, [
      :user_id, :type, :category, :title, :body, :image_url,
      :action_url, :action_label, :metadata, :campaign_id
    ])
    |> validate_required([:user_id, :type, :category, :title])
    |> validate_inclusion(:type, @valid_types)
    |> validate_inclusion(:category, @valid_categories)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:campaign_id)
  end

  def read_changeset(notification) do
    notification
    |> change(%{read_at: DateTime.utc_now() |> DateTime.truncate(:second)})
  end

  def dismiss_changeset(notification) do
    notification
    |> change(%{dismissed_at: DateTime.utc_now() |> DateTime.truncate(:second)})
  end

  def click_changeset(notification) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    notification
    |> change(%{clicked_at: now, read_at: notification.read_at || now})
  end

  def unread?(%__MODULE__{read_at: nil}), do: true
  def unread?(%__MODULE__{}), do: false
end
