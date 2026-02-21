defmodule BlocksterV2.Notifications.UserProfile do
  use Ecto.Schema
  import Ecto.Changeset

  @valid_engagement_tiers ~w(new casual active power whale dormant churned)
  @valid_price_sensitivities ~w(unknown low medium high)
  @valid_gambling_tiers ~w(non_gambler casual_gambler regular_gambler high_roller whale_gambler)
  @valid_churn_risk_levels ~w(low medium high critical)
  @valid_vip_tiers ~w(none bronze silver gold diamond)
  @valid_conversion_stages ~w(earner bux_player rogue_curious rogue_buyer rogue_regular)

  schema "user_profiles" do
    belongs_to :user, BlocksterV2.Accounts.User

    # Content preferences
    field :preferred_categories, {:array, :map}, default: []
    field :preferred_hubs, {:array, :map}, default: []
    field :preferred_tags, {:array, :map}, default: []
    field :avg_read_duration_ms, :integer, default: 0
    field :avg_scroll_depth_pct, :integer, default: 0
    field :content_completion_rate, :float, default: 0.0
    field :articles_read_last_7d, :integer, default: 0
    field :articles_read_last_30d, :integer, default: 0
    field :total_articles_read, :integer, default: 0

    # Shopping behavior
    field :shop_interest_score, :float, default: 0.0
    field :avg_cart_value, :decimal
    field :purchase_count, :integer, default: 0
    field :total_spent, :decimal, default: Decimal.new("0")
    field :viewed_products_last_30d, {:array, :integer}, default: []
    field :carted_not_purchased, {:array, :integer}, default: []
    field :price_sensitivity, :string, default: "unknown"
    field :preferred_payment_method, :string

    # Engagement patterns
    field :engagement_tier, :string, default: "new"
    field :engagement_score, :float, default: 0.0
    field :last_active_at, :utc_datetime
    field :days_since_last_active, :integer, default: 0
    field :avg_sessions_per_week, :float, default: 0.0
    field :avg_session_duration_ms, :integer, default: 0
    field :consecutive_active_days, :integer, default: 0
    field :lifetime_days, :integer, default: 0

    # Notification responsiveness
    field :email_open_rate_30d, :float, default: 0.0
    field :email_click_rate_30d, :float, default: 0.0
    field :in_app_click_rate_30d, :float, default: 0.0
    field :best_email_hour_utc, :integer
    field :best_email_day, :string
    field :notification_fatigue_score, :float, default: 0.0
    field :preferred_content_in_email, {:array, :string}, default: []

    # Referral behavior
    field :referral_propensity, :float, default: 0.0
    field :referrals_sent, :integer, default: 0
    field :referrals_converted, :integer, default: 0

    # BUX & gamification
    field :bux_balance, :decimal, default: Decimal.new("0")
    field :bux_earned_last_30d, :decimal, default: Decimal.new("0")
    field :games_played_last_30d, :integer, default: 0
    field :gamification_score, :float, default: 0.0

    # Gambling behavior
    field :gambling_tier, :string, default: "non_gambler"
    field :total_bets_placed, :integer, default: 0
    field :total_wagered, :decimal, default: Decimal.new("0")
    field :total_won, :decimal, default: Decimal.new("0")
    field :avg_bet_size, :decimal
    field :favorite_game, :string
    field :last_game_at, :utc_datetime

    # ROGUE-specific gambling
    field :total_rogue_games, :integer, default: 0
    field :total_rogue_wagered, :decimal, default: Decimal.new("0")
    field :total_rogue_won, :decimal, default: Decimal.new("0")
    field :rogue_balance_estimate, :decimal, default: Decimal.new("0")
    field :games_played_last_7d, :integer, default: 0
    field :win_streak, :integer, default: 0
    field :loss_streak, :integer, default: 0

    # VIP tier
    field :vip_tier, :string, default: "none"
    field :vip_unlocked_at, :utc_datetime

    # Conversion funnel
    field :conversion_stage, :string, default: "earner"
    field :last_rogue_offer_at, :utc_datetime
    field :rogue_readiness_score, :float, default: 0.0

    # Churn risk
    field :churn_risk_score, :float, default: 0.0
    field :churn_risk_level, :string, default: "low"

    # Recalculation tracking
    field :last_calculated_at, :utc_datetime
    field :events_since_last_calc, :integer, default: 0

    timestamps()
  end

  @cast_fields [
    :user_id, :preferred_categories, :preferred_hubs, :preferred_tags,
    :avg_read_duration_ms, :avg_scroll_depth_pct, :content_completion_rate,
    :articles_read_last_7d, :articles_read_last_30d, :total_articles_read,
    :shop_interest_score, :avg_cart_value, :purchase_count, :total_spent,
    :viewed_products_last_30d, :carted_not_purchased, :price_sensitivity,
    :preferred_payment_method,
    :engagement_tier, :engagement_score, :last_active_at, :days_since_last_active,
    :avg_sessions_per_week, :avg_session_duration_ms, :consecutive_active_days, :lifetime_days,
    :email_open_rate_30d, :email_click_rate_30d, :in_app_click_rate_30d,
    :best_email_hour_utc, :best_email_day, :notification_fatigue_score,
    :preferred_content_in_email,
    :referral_propensity, :referrals_sent, :referrals_converted,
    :bux_balance, :bux_earned_last_30d, :games_played_last_30d, :gamification_score,
    :gambling_tier, :total_bets_placed, :total_wagered, :total_won,
    :avg_bet_size, :favorite_game, :last_game_at,
    :total_rogue_games, :total_rogue_wagered, :total_rogue_won,
    :rogue_balance_estimate, :games_played_last_7d,
    :win_streak, :loss_streak,
    :vip_tier, :vip_unlocked_at,
    :conversion_stage, :last_rogue_offer_at, :rogue_readiness_score,
    :churn_risk_score, :churn_risk_level,
    :last_calculated_at, :events_since_last_calc
  ]

  def changeset(profile, attrs) do
    profile
    |> cast(attrs, @cast_fields)
    |> validate_required([:user_id])
    |> validate_inclusion(:engagement_tier, @valid_engagement_tiers)
    |> validate_inclusion(:price_sensitivity, @valid_price_sensitivities)
    |> validate_inclusion(:gambling_tier, @valid_gambling_tiers)
    |> validate_inclusion(:churn_risk_level, @valid_churn_risk_levels)
    |> validate_number(:engagement_score, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_number(:churn_risk_score, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    |> validate_number(:notification_fatigue_score, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    |> validate_inclusion(:vip_tier, @valid_vip_tiers)
    |> validate_inclusion(:conversion_stage, @valid_conversion_stages)
    |> validate_number(:rogue_readiness_score, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    |> unique_constraint(:user_id)
    |> foreign_key_constraint(:user_id)
  end

  def valid_engagement_tiers, do: @valid_engagement_tiers
  def valid_gambling_tiers, do: @valid_gambling_tiers
  def valid_churn_risk_levels, do: @valid_churn_risk_levels
  def valid_vip_tiers, do: @valid_vip_tiers
  def valid_conversion_stages, do: @valid_conversion_stages
end
