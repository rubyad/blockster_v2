defmodule BlocksterV2.Notifications.UserEvent do
  use Ecto.Schema
  import Ecto.Changeset

  @valid_event_types ~w(
    article_view article_read_complete article_read_partial article_share article_bookmark
    video_watch category_browse
    product_view product_view_duration product_add_to_cart product_remove_from_cart
    cart_view checkout_start checkout_abandon purchase_complete product_search
    hub_view hub_subscribe hub_unsubscribe
    referral_link_copy referral_link_share referral_conversion
    bux_earned bux_spent game_played multiplier_earned
    phone_verified x_connected wallet_connected telegram_connected telegram_group_joined rogue_deposited rogue_withdrawn
    signup profile_updated
    daily_login session_start session_end
    notification_received notification_viewed notification_clicked notification_dismissed
    email_opened email_clicked email_unsubscribed sms_clicked
  )

  @valid_categories ~w(content shop social engagement navigation notification)

  @category_map %{
    "article_view" => "content",
    "article_read_complete" => "content",
    "article_read_partial" => "content",
    "article_share" => "content",
    "article_bookmark" => "content",
    "video_watch" => "content",
    "category_browse" => "content",
    "product_view" => "shop",
    "product_view_duration" => "shop",
    "product_add_to_cart" => "shop",
    "product_remove_from_cart" => "shop",
    "cart_view" => "shop",
    "checkout_start" => "shop",
    "checkout_abandon" => "shop",
    "purchase_complete" => "shop",
    "product_search" => "shop",
    "hub_view" => "social",
    "hub_subscribe" => "social",
    "hub_unsubscribe" => "social",
    "referral_link_copy" => "social",
    "referral_link_share" => "social",
    "referral_conversion" => "social",
    "bux_earned" => "engagement",
    "bux_spent" => "engagement",
    "game_played" => "engagement",
    "multiplier_earned" => "engagement",
    "phone_verified" => "engagement",
    "x_connected" => "social",
    "wallet_connected" => "engagement",
    "telegram_connected" => "social",
    "telegram_group_joined" => "social",
    "rogue_deposited" => "engagement",
    "rogue_withdrawn" => "engagement",
    "signup" => "engagement",
    "profile_updated" => "engagement",
    "daily_login" => "navigation",
    "session_start" => "navigation",
    "session_end" => "navigation",
    "notification_received" => "notification",
    "notification_viewed" => "notification",
    "notification_clicked" => "notification",
    "notification_dismissed" => "notification",
    "email_opened" => "notification",
    "email_clicked" => "notification",
    "email_unsubscribed" => "notification",
    "sms_clicked" => "notification"
  }

  schema "user_events" do
    field :event_type, :string
    field :event_category, :string
    field :target_type, :string
    field :target_id, :string
    field :metadata, :map, default: %{}
    field :session_id, :string
    field :source, :string, default: "web"
    field :referrer, :string

    belongs_to :user, BlocksterV2.Accounts.User

    timestamps(updated_at: false)
  end

  def changeset(event \\ %__MODULE__{}, attrs) do
    event
    |> cast(attrs, [
      :user_id, :event_type, :event_category, :target_type, :target_id,
      :metadata, :session_id, :source, :referrer
    ])
    |> validate_required([:user_id, :event_type, :event_category])
    |> validate_inclusion(:event_type, @valid_event_types)
    |> validate_inclusion(:event_category, @valid_categories)
    |> foreign_key_constraint(:user_id)
  end

  @doc "Returns the category for a given event type"
  def categorize(event_type), do: Map.get(@category_map, event_type, "navigation")

  @doc "Returns all valid event types"
  def valid_event_types, do: @valid_event_types

  @doc "Returns all valid categories"
  def valid_categories, do: @valid_categories
end
