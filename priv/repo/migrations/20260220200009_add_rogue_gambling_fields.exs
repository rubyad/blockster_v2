defmodule BlocksterV2.Repo.Migrations.AddRogueGamblingFields do
  use Ecto.Migration

  def change do
    alter table(:user_profiles) do
      # ROGUE-specific gambling tracking
      add :total_rogue_games, :integer, default: 0
      add :total_rogue_wagered, :decimal, default: 0
      add :total_rogue_won, :decimal, default: 0
      add :rogue_balance_estimate, :decimal, default: 0
      add :games_played_last_7d, :integer, default: 0

      # Streak tracking
      add :win_streak, :integer, default: 0
      add :loss_streak, :integer, default: 0

      # VIP tier
      add :vip_tier, :string, default: "none"
      add :vip_unlocked_at, :utc_datetime

      # Conversion funnel stage
      add :conversion_stage, :string, default: "earner"

      # ROGUE offer tracking
      add :last_rogue_offer_at, :utc_datetime
      add :rogue_readiness_score, :float, default: 0.0
    end
  end
end
