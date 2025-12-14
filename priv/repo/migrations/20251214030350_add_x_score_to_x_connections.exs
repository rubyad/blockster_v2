defmodule BlocksterV2.Repo.Migrations.AddXScoreToXConnections do
  use Ecto.Migration

  def change do
    alter table(:x_connections) do
      # X account quality score (1-100)
      add :x_score, :integer
      # Raw metrics used to calculate score
      add :followers_count, :integer
      add :following_count, :integer
      add :tweet_count, :integer
      add :listed_count, :integer
      # Engagement rate calculated from original tweets only (not retweets)
      add :avg_engagement_rate, :float
      # Count of original tweets analyzed (excludes retweets)
      add :original_tweets_analyzed, :integer
      add :account_created_at, :utc_datetime
      add :score_calculated_at, :utc_datetime
    end
  end
end
