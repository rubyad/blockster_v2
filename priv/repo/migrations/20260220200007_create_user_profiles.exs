defmodule BlocksterV2.Repo.Migrations.CreateUserProfiles do
  use Ecto.Migration

  def change do
    create table(:user_profiles) do
      add :user_id, references(:users, on_delete: :delete_all), null: false

      # Content preferences
      add :preferred_categories, {:array, :map}, default: []
      add :preferred_hubs, {:array, :map}, default: []
      add :preferred_tags, {:array, :map}, default: []
      add :avg_read_duration_ms, :integer, default: 0
      add :avg_scroll_depth_pct, :integer, default: 0
      add :content_completion_rate, :float, default: 0.0
      add :articles_read_last_7d, :integer, default: 0
      add :articles_read_last_30d, :integer, default: 0
      add :total_articles_read, :integer, default: 0

      # Shopping behavior
      add :shop_interest_score, :float, default: 0.0
      add :avg_cart_value, :decimal
      add :purchase_count, :integer, default: 0
      add :total_spent, :decimal, default: 0
      add :viewed_products_last_30d, {:array, :integer}, default: []
      add :carted_not_purchased, {:array, :integer}, default: []
      add :price_sensitivity, :string, default: "unknown"
      add :preferred_payment_method, :string

      # Engagement patterns
      add :engagement_tier, :string, default: "new"
      add :engagement_score, :float, default: 0.0
      add :last_active_at, :utc_datetime
      add :days_since_last_active, :integer, default: 0
      add :avg_sessions_per_week, :float, default: 0.0
      add :avg_session_duration_ms, :integer, default: 0
      add :consecutive_active_days, :integer, default: 0
      add :lifetime_days, :integer, default: 0

      # Notification responsiveness
      add :email_open_rate_30d, :float, default: 0.0
      add :email_click_rate_30d, :float, default: 0.0
      add :in_app_click_rate_30d, :float, default: 0.0
      add :best_email_hour_utc, :integer
      add :best_email_day, :string
      add :notification_fatigue_score, :float, default: 0.0
      add :preferred_content_in_email, {:array, :string}, default: []

      # Referral behavior
      add :referral_propensity, :float, default: 0.0
      add :referrals_sent, :integer, default: 0
      add :referrals_converted, :integer, default: 0

      # BUX & gamification
      add :bux_balance, :decimal, default: 0
      add :bux_earned_last_30d, :decimal, default: 0
      add :games_played_last_30d, :integer, default: 0
      add :gamification_score, :float, default: 0.0

      # Gambling behavior (for Phase 15 - ROGUE conversion)
      add :gambling_tier, :string, default: "non_gambler"
      add :total_bets_placed, :integer, default: 0
      add :total_wagered, :decimal, default: 0
      add :total_won, :decimal, default: 0
      add :avg_bet_size, :decimal
      add :favorite_game, :string
      add :last_game_at, :utc_datetime

      # Churn risk
      add :churn_risk_score, :float, default: 0.0
      add :churn_risk_level, :string, default: "low"

      # Recalculation tracking
      add :last_calculated_at, :utc_datetime
      add :events_since_last_calc, :integer, default: 0

      timestamps()
    end

    create unique_index(:user_profiles, [:user_id])
    create index(:user_profiles, [:engagement_tier])
    create index(:user_profiles, [:engagement_score])
    create index(:user_profiles, [:last_active_at])
    create index(:user_profiles, [:churn_risk_level])
    create index(:user_profiles, [:gambling_tier])
  end
end
