defmodule BlocksterV2.Social.XScoreCalculator do
  @moduledoc """
  Calculates X account quality score (1-100) based on:
  - Follower quality (followers/following ratio)
  - Engagement rate on original tweets (excludes retweets)
  - Account age
  - Activity level
  - List presence
  - Follower scale

  The score is used as the x_multiplier for BUX rewards.
  Score is recalculated every 7 days.
  """

  require Logger

  alias BlocksterV2.Social.XApiClient
  alias BlocksterV2.{EngagementTracker, UnifiedMultiplier}

  @score_refresh_days 7

  @doc """
  Checks if a score needs to be calculated for the connection.
  Returns true if:
  - score_calculated_at is nil (never calculated)
  - More than 7 days have passed since last calculation

  Works with both Mnesia maps and legacy XConnection structs.
  """
  def needs_score_calculation?(%{score_calculated_at: nil}), do: true
  def needs_score_calculation?(%{score_calculated_at: calculated_at}) when is_struct(calculated_at, DateTime) do
    days_since = DateTime.diff(DateTime.utc_now(), calculated_at, :day)
    days_since >= @score_refresh_days
  end
  # Handle Unix timestamps (from Mnesia)
  def needs_score_calculation?(%{score_calculated_at: calculated_at}) when is_integer(calculated_at) do
    now = DateTime.utc_now() |> DateTime.to_unix()
    days_since = div(now - calculated_at, 86400)
    days_since >= @score_refresh_days
  end
  # Fallback for any other connection format
  def needs_score_calculation?(_connection), do: true

  @doc """
  Calculates and saves the X score for a connection if needed.
  Also updates the x_multiplier in Mnesia user_multipliers table.

  Returns {:ok, updated_connection} or {:error, reason}.
  """
  def maybe_calculate_and_save_score(connection, access_token) do
    if needs_score_calculation?(connection) do
      calculate_and_save_score(connection, access_token)
    else
      {:ok, connection}
    end
  end

  @doc """
  Forces calculation and saves the X score for a connection.
  Also updates the x_multiplier in Mnesia user_multipliers table.

  Returns {:ok, updated_connection} or {:error, reason}.
  """
  def calculate_and_save_score(connection, access_token) do
    Logger.info("[XScoreCalculator] Calculating X score for user #{connection.user_id}")

    case XApiClient.fetch_score_data(access_token, connection.x_user_id) do
      {:ok, %{user: user_data, tweets: tweets}} ->
        score_data = calculate_score(user_data, tweets)
        save_score(connection, score_data)

      {:error, reason} ->
        Logger.error("[XScoreCalculator] Failed to fetch score data: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Calculates the X score from user data and tweets.
  Returns a map with all score components and the final score.
  """
  def calculate_score(user_data, tweets) do
    public_metrics = user_data["public_metrics"] || %{}
    followers = public_metrics["followers_count"] || 0
    following = public_metrics["following_count"] || 0
    tweet_count = public_metrics["tweet_count"] || 0
    listed_count = public_metrics["listed_count"] || 0

    account_created_at = parse_created_at(user_data["created_at"])
    account_age_days = if account_created_at do
      DateTime.diff(DateTime.utc_now(), account_created_at, :day)
    else
      0
    end

    # Calculate engagement rate from original tweets only
    {avg_engagement_rate, avg_engagement_per_tweet, original_tweets_count} = calculate_engagement_rate(tweets, followers)

    # Score components (total = 100)
    follower_quality_score = calculate_follower_quality(followers, following)        # 25 points max
    engagement_score = calculate_engagement_score(avg_engagement_rate, avg_engagement_per_tweet, followers)  # 35 points max
    age_score = calculate_age_score(account_age_days)                                # 10 points max
    activity_score = calculate_activity_score(tweet_count, account_age_days)         # 15 points max
    list_score = calculate_list_score(listed_count)                                  # 5 points max
    follower_scale_score = calculate_follower_scale(followers)                       # 10 points max

    total_score = round(
      follower_quality_score +
      engagement_score +
      age_score +
      activity_score +
      list_score +
      follower_scale_score
    )

    # Clamp to 1-100
    final_score = max(1, min(100, total_score))

    Logger.info("[XScoreCalculator] Score breakdown: " <>
      "follower_quality=#{round(follower_quality_score)}, " <>
      "engagement=#{round(engagement_score)}, " <>
      "age=#{round(age_score)}, " <>
      "activity=#{round(activity_score)}, " <>
      "list=#{round(list_score)}, " <>
      "scale=#{round(follower_scale_score)}, " <>
      "total=#{final_score}")

    %{
      x_score: final_score,
      followers_count: followers,
      following_count: following,
      tweet_count: tweet_count,
      listed_count: listed_count,
      avg_engagement_rate: avg_engagement_rate,
      original_tweets_analyzed: original_tweets_count,
      account_created_at: account_created_at,
      score_calculated_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }
  end

  # Score component calculations

  # Follower quality: followers/following ratio (25 points max)
  # Ratio > 10 = max score, ratio < 0.1 = very low score
  defp calculate_follower_quality(followers, following) when following > 0 do
    ratio = followers / following
    # Cap at 10, normalize to 0-1, multiply by 25
    min(ratio / 10, 1.0) * 25
  end
  defp calculate_follower_quality(followers, _following) when followers > 0, do: 25.0
  defp calculate_follower_quality(_, _), do: 0.0

  # Engagement rate score (35 points max)
  # Split into rate component (17.5) and volume component (17.5)
  # Rate threshold scales down as followers increase (large accounts naturally have lower rates)
  # Volume requires 200+ avg engagements per tweet for max score
  defp calculate_engagement_score(engagement_rate, avg_engagement_per_tweet, followers) do
    # Rate component: 17.5 points max
    # Target rate scales with follower count:
    # - 0-1k followers: need 10% for max
    # - 1k-10k followers: need 5% for max
    # - 10k-100k followers: need 2% for max
    # - 100k+ followers: need 1% for max
    target_rate = cond do
      followers < 1_000 -> 0.10
      followers < 10_000 -> 0.05
      followers < 100_000 -> 0.02
      true -> 0.01
    end
    rate_score = min(engagement_rate / target_rate, 1.0) * 17.5

    # Volume component: 17.5 points max
    # Need 200+ average engagements per tweet for max score
    volume_score = min(avg_engagement_per_tweet / 200, 1.0) * 17.5

    rate_score + volume_score
  end

  # Account age score (10 points max)
  # 5+ years = max score
  defp calculate_age_score(days) do
    years = days / 365
    min(years / 5, 1.0) * 10
  end

  # Activity score (15 points max)
  # Based on tweets per month - 30 tweets/month = max
  defp calculate_activity_score(tweet_count, account_age_days) when account_age_days > 0 do
    months = max(account_age_days / 30, 1)
    tweets_per_month = tweet_count / months
    min(tweets_per_month / 30, 1.0) * 15
  end
  defp calculate_activity_score(_, _), do: 0.0

  # List score (5 points max)
  # Being on 50+ lists = max score
  defp calculate_list_score(listed_count) do
    min(listed_count / 50, 1.0) * 5
  end

  # Follower scale (10 points max)
  # Uses logarithmic scale: 10M followers (10^7) = max
  # Under 1k followers gets almost nothing, scales up from there
  defp calculate_follower_scale(followers) when followers >= 1000 do
    # log10(10,000,000) = 7, log10(1000) = 3
    # So we map 1k-10M (3-7 in log scale) to 0-10 points
    score = ((:math.log10(followers) - 3) / 4) * 10
    min(max(score, 0.0), 10.0)
  end
  defp calculate_follower_scale(followers) when followers > 0 do
    # Under 1k followers: tiny score (max ~1 point at 999)
    followers / 1000
  end
  defp calculate_follower_scale(_), do: 0.0

  # Calculate engagement rate from original tweets
  # Returns {engagement_rate, avg_engagement_per_tweet, tweet_count}
  defp calculate_engagement_rate([], _followers), do: {0.0, 0.0, 0}
  defp calculate_engagement_rate(tweets, followers) when followers > 0 do
    tweet_count = length(tweets)

    total_engagement = Enum.reduce(tweets, 0, fn tweet, acc ->
      metrics = tweet["public_metrics"] || %{}
      likes = metrics["like_count"] || 0
      retweets = metrics["retweet_count"] || 0
      replies = metrics["reply_count"] || 0
      quotes = metrics["quote_count"] || 0
      acc + likes + retweets + replies + quotes
    end)

    # Average engagement per tweet, normalized by followers
    avg_engagement_per_tweet = if tweet_count > 0, do: total_engagement / tweet_count, else: 0.0
    engagement_rate = avg_engagement_per_tweet / followers

    {engagement_rate, avg_engagement_per_tweet, tweet_count}
  end
  defp calculate_engagement_rate(tweets, _), do: {0.0, 0.0, length(tweets)}

  defp parse_created_at(nil), do: nil
  defp parse_created_at(date_string) do
    case DateTime.from_iso8601(date_string) do
      {:ok, datetime, _} -> datetime
      _ -> nil
    end
  end

  # Save score to Mnesia x_connections and user_multipliers tables
  defp save_score(connection, score_data) do
    user_id = connection.user_id

    # Update x_connection with score data
    case EngagementTracker.update_x_connection_score(user_id, score_data) do
      {:ok, updated_connection} ->
        # Update x_multiplier in Mnesia user_multipliers table (legacy)
        EngagementTracker.set_user_x_multiplier(user_id, score_data.x_score)

        # Update unified_multipliers table (V2 system)
        UnifiedMultiplier.update_x_multiplier(user_id, score_data.x_score)

        Logger.info("[XScoreCalculator] Saved X score #{score_data.x_score} for user #{user_id}")
        {:ok, updated_connection}

      {:error, reason} ->
        Logger.error("[XScoreCalculator] Failed to save score: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
