defmodule BlocksterV2.Notifications.ProfileEngine do
  @moduledoc """
  Calculates user engagement tiers, scores, gambling classification,
  and churn risk based on behavioral data from user_events.

  Used by ProfileRecalcWorker to build/update user_profiles.
  """

  import Ecto.Query
  alias BlocksterV2.Repo
  alias BlocksterV2.Notifications.{UserEvent, UserProfile, EmailLog}

  # ============ Engagement Tier Classification ============

  @doc """
  Classify user into engagement tier based on behavior signals.
  Returns one of: "new", "casual", "active", "power", "whale", "dormant", "churned"
  """
  def classify_engagement_tier(profile_data) do
    days_since_active = profile_data[:days_since_last_active] || profile_data.days_since_last_active || 0
    lifetime_days = profile_data[:lifetime_days] || profile_data.lifetime_days || 0
    sessions_per_week = profile_data[:avg_sessions_per_week] || profile_data.avg_sessions_per_week || 0.0
    purchase_count = profile_data[:purchase_count] || profile_data.purchase_count || 0
    total_spent = get_decimal(profile_data, :total_spent)

    cond do
      days_since_active > 30 -> "churned"
      days_since_active > 14 -> "dormant"
      lifetime_days < 7 -> "new"
      Decimal.compare(total_spent, Decimal.new("100")) == :gt or purchase_count > 5 -> "whale"
      sessions_per_week >= 3 and purchase_count > 0 -> "power"
      sessions_per_week < 0.5 -> "casual"
      sessions_per_week < 1.0 and purchase_count == 0 -> "casual"
      true -> "active"
    end
  end

  # ============ Engagement Score (0-100) ============

  @doc """
  Calculate composite engagement score (0-100) from profile data.
  Weights multiple dimensions of user activity.
  """
  def calculate_engagement_score(profile_data) do
    activity_score = calculate_activity_score(profile_data)
    content_score = calculate_content_score(profile_data)
    commerce_score = calculate_commerce_score(profile_data)
    social_score = calculate_social_score(profile_data)
    notification_score = calculate_notification_score(profile_data)

    score =
      activity_score * 0.30 +
      content_score * 0.25 +
      commerce_score * 0.20 +
      social_score * 0.10 +
      notification_score * 0.15

    Float.round(min(score, 100.0), 1)
  end

  # ============ Gambling Tier Classification ============

  @doc """
  Classify user into gambling tier based on gaming behavior.
  Returns one of: "non_gambler", "casual_gambler", "regular_gambler", "high_roller", "whale_gambler"
  """
  def classify_gambling_tier(profile_data) do
    games_played = profile_data[:games_played_last_30d] || 0
    total_bets = profile_data[:total_bets_placed] || 0
    total_wagered = get_decimal(profile_data, :total_wagered)
    avg_bet = get_decimal(profile_data, :avg_bet_size)

    cond do
      games_played == 0 and total_bets == 0 ->
        "non_gambler"

      games_played < 5 and Decimal.compare(total_wagered, Decimal.new("100")) != :gt ->
        "casual_gambler"

      Decimal.compare(total_wagered, Decimal.new("10000")) == :gt or
          Decimal.compare(avg_bet, Decimal.new("500")) == :gt ->
        "whale_gambler"

      Decimal.compare(total_wagered, Decimal.new("1000")) == :gt or
          Decimal.compare(avg_bet, Decimal.new("100")) == :gt ->
        "high_roller"

      true ->
        "regular_gambler"
    end
  end

  # ============ Churn Risk Prediction ============

  @doc """
  Calculate churn risk score (0.0-1.0) and level ("low", "medium", "high", "critical").
  Higher score = more likely to churn.
  """
  def calculate_churn_risk(profile_data) do
    days_since_active = profile_data[:days_since_last_active] || 0
    sessions_per_week = profile_data[:avg_sessions_per_week] || 0.0
    consecutive_days = profile_data[:consecutive_active_days] || 0
    email_open_rate = profile_data[:email_open_rate_30d] || 0.0
    fatigue_score = profile_data[:notification_fatigue_score] || 0.0
    engagement_score = profile_data[:engagement_score] || 0.0

    # Weighted risk signals
    inactivity_risk = min(days_since_active / 30.0, 1.0) * 0.35
    frequency_risk = max(1.0 - (sessions_per_week / 5.0), 0.0) * 0.20
    streak_risk = (if consecutive_days > 3, do: 0.0, else: 0.3) * 0.10
    email_risk = max(1.0 - email_open_rate, 0.0) * 0.15
    fatigue_risk = fatigue_score * 0.10
    engagement_risk = max(1.0 - (engagement_score / 100.0), 0.0) * 0.10

    score = Float.round(
      inactivity_risk + frequency_risk + streak_risk +
      email_risk + fatigue_risk + engagement_risk,
      2
    )

    score = min(max(score, 0.0), 1.0)

    level = cond do
      score >= 0.7 -> "critical"
      score >= 0.5 -> "high"
      score >= 0.3 -> "medium"
      true -> "low"
    end

    {score, level}
  end

  # ============ Profile Recalculation ============

  @doc """
  Recalculate all profile fields for a user from their event history.
  Returns a map of profile attributes ready for upsert.
  """
  def recalculate_profile(user_id) do
    events_30d = get_user_events(user_id, 30)
    events_7d = Enum.filter(events_30d, &within_last_n_days?(&1, 7))

    user = Repo.get(BlocksterV2.Accounts.User, user_id)
    lifetime_days = if user, do: Date.diff(Date.utc_today(), NaiveDateTime.to_date(user.inserted_at)), else: 0

    # Build profile data
    profile_data = %{
      # Content preferences
      preferred_categories: extract_category_preferences(events_30d),
      preferred_hubs: extract_hub_preferences(events_30d),
      avg_read_duration_ms: avg_metadata_int(events_30d, "article_read_complete", "read_duration_ms"),
      avg_scroll_depth_pct: avg_metadata_int(events_30d, "article_read_complete", "scroll_depth_pct"),
      content_completion_rate: completion_rate(events_30d),
      articles_read_last_7d: count_type(events_7d, "article_read_complete"),
      articles_read_last_30d: count_type(events_30d, "article_read_complete"),
      total_articles_read: total_event_count(user_id, "article_read_complete"),

      # Shopping behavior
      shop_interest_score: calculate_shop_interest(events_30d),
      purchase_count: total_event_count(user_id, "purchase_complete"),
      total_spent: sum_metadata_decimal(user_id, "purchase_complete", "total"),
      viewed_products_last_30d: extract_target_ids(events_30d, "product_view"),
      carted_not_purchased: extract_carted_not_purchased(events_30d),
      price_sensitivity: calculate_price_sensitivity(events_30d),

      # Engagement
      last_active_at: most_recent_event_time(events_30d),
      days_since_last_active: days_since_active(user_id),
      avg_sessions_per_week: calculate_session_frequency(events_30d),
      avg_session_duration_ms: avg_metadata_int(events_30d, "session_end", "duration_ms"),
      consecutive_active_days: calculate_streak(user_id),
      lifetime_days: lifetime_days,

      # Notification responsiveness
      email_open_rate_30d: calculate_email_rate(user_id, :opened, 30),
      email_click_rate_30d: calculate_email_rate(user_id, :clicked, 30),
      in_app_click_rate_30d: calculate_in_app_click_rate(user_id, 30),
      best_email_hour_utc: find_best_email_hour(user_id),
      notification_fatigue_score: calculate_fatigue(user_id, events_7d),

      # Referral
      referral_propensity: calculate_referral_propensity(events_30d),
      referrals_sent: count_type(events_30d, "referral_link_share"),
      referrals_converted: count_type(events_30d, "referral_conversion"),

      # Gamification
      games_played_last_30d: count_type(events_30d, "game_played"),

      # Gambling
      total_bets_placed: total_event_count(user_id, "game_played"),
      total_wagered: sum_metadata_decimal(user_id, "game_played", "bet_amount"),
      total_won: sum_metadata_decimal(user_id, "game_played", "payout"),
      avg_bet_size: avg_metadata_decimal(user_id, "game_played", "bet_amount"),

      # Recalculation tracking
      last_calculated_at: DateTime.utc_now() |> DateTime.truncate(:second),
      events_since_last_calc: 0
    }

    # Derive composite scores
    engagement_tier = classify_engagement_tier(profile_data)
    engagement_score = calculate_engagement_score(profile_data)
    gambling_tier = classify_gambling_tier(profile_data)
    {churn_score, churn_level} = calculate_churn_risk(Map.merge(profile_data, %{engagement_score: engagement_score}))

    conversion_stage = calculate_conversion_stage(profile_data)

    profile_data
    |> Map.merge(%{
      engagement_tier: engagement_tier,
      engagement_score: engagement_score,
      gambling_tier: gambling_tier,
      churn_risk_score: churn_score,
      churn_risk_level: churn_level,
      conversion_stage: conversion_stage
    })
  end

  # ============ Conversion Stage Classification ============

  @doc """
  Determine conversion stage from profile data.
  Stages: nil → "earner" → "bux_player" → "rogue_curious" → "rogue_buyer"

  Called during recalculation (every 6h) so stage stays up to date even without
  real-time events. Real-time updates in EventProcessor handle obvious transitions
  (first BUX game, first ROGUE game, first purchase) immediately.
  """
  def calculate_conversion_stage(profile_data) do
    purchase_count = profile_data[:purchase_count] || 0
    games_played = profile_data[:games_played_last_30d] || 0
    total_bets = profile_data[:total_bets_placed] || 0
    total_articles = profile_data[:total_articles_read] || 0
    gambling_tier = profile_data[:gambling_tier]

    cond do
      # Has made a purchase → rogue_buyer
      purchase_count > 0 ->
        "rogue_buyer"

      # Plays ROGUE games (whale or high roller) → rogue_curious
      gambling_tier in ["whale_gambler", "high_roller"] ->
        "rogue_curious"

      # Has played games → bux_player
      games_played > 0 or total_bets > 0 ->
        "bux_player"

      # Has read articles → earner
      total_articles > 0 ->
        "earner"

      # Default
      true ->
        nil
    end
  end

  # ============ Private: Event Querying ============

  defp get_user_events(user_id, days) do
    since = DateTime.utc_now() |> DateTime.add(-days, :day) |> DateTime.truncate(:second)

    UserEvent
    |> where([e], e.user_id == ^user_id)
    |> where([e], e.inserted_at >= ^since)
    |> order_by([e], desc: e.inserted_at)
    |> Repo.all()
  end

  defp within_last_n_days?(event, days) do
    cutoff = NaiveDateTime.utc_now() |> NaiveDateTime.add(-days * 86400, :second) |> NaiveDateTime.truncate(:second)
    NaiveDateTime.compare(event.inserted_at, cutoff) != :lt
  end

  # ============ Private: Content Preferences ============

  defp extract_category_preferences(events) do
    events
    |> Enum.filter(&(&1.event_type in ["article_view", "article_read_complete"]))
    |> Enum.flat_map(fn e ->
      cat_id = e.metadata["category_id"]
      cat_name = e.metadata["category_name"]
      if cat_id, do: [{cat_id, cat_name || "Unknown"}], else: []
    end)
    |> Enum.frequencies_by(fn {id, _name} -> id end)
    |> Enum.map(fn {id, count} ->
      names = events
        |> Enum.flat_map(fn e ->
          if e.metadata["category_id"] == id, do: [e.metadata["category_name"]], else: []
        end)
      name = List.first(Enum.reject(names, &is_nil/1)) || "Unknown"
      %{"id" => id, "name" => name, "score" => min(count / 10.0, 1.0)}
    end)
    |> Enum.sort_by(& &1["score"], :desc)
    |> Enum.take(10)
  end

  defp extract_hub_preferences(events) do
    events
    |> Enum.filter(&(&1.event_type in ["article_view", "article_read_complete", "hub_view", "hub_subscribe"]))
    |> Enum.flat_map(fn e ->
      hub_id = e.metadata["hub_id"]
      if hub_id, do: [{hub_id, e.metadata["hub_name"]}], else: []
    end)
    |> Enum.frequencies_by(fn {id, _name} -> id end)
    |> Enum.map(fn {id, count} ->
      names = events
        |> Enum.flat_map(fn e ->
          if e.metadata["hub_id"] == id, do: [e.metadata["hub_name"]], else: []
        end)
      name = List.first(Enum.reject(names, &is_nil/1)) || "Unknown"
      %{"id" => id, "name" => name, "score" => min(count / 10.0, 1.0)}
    end)
    |> Enum.sort_by(& &1["score"], :desc)
    |> Enum.take(10)
  end

  # ============ Private: Metrics Calculation ============

  defp count_type(events, event_type) do
    Enum.count(events, &(&1.event_type == event_type))
  end

  defp total_event_count(user_id, event_type) do
    UserEvent
    |> where([e], e.user_id == ^user_id)
    |> where([e], e.event_type == ^event_type)
    |> Repo.aggregate(:count, :id)
  end

  defp completion_rate(events) do
    views = count_type(events, "article_view")
    completes = count_type(events, "article_read_complete")
    if views > 0, do: Float.round(completes / views, 2), else: 0.0
  end

  defp avg_metadata_int(events, event_type, field) do
    values =
      events
      |> Enum.filter(&(&1.event_type == event_type))
      |> Enum.map(& &1.metadata[field])
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&to_integer/1)

    if values == [], do: 0, else: div(Enum.sum(values), length(values))
  end

  defp avg_metadata_decimal(_user_id, event_type, field) do
    result =
      from(e in UserEvent,
        where: e.event_type == ^event_type,
        select: fragment("AVG(CAST(metadata->>? AS DECIMAL))", ^field)
      )
      |> Repo.one()

    if result, do: Decimal.round(result, 2), else: nil
  end

  defp sum_metadata_decimal(user_id, event_type, field) do
    result =
      from(e in UserEvent,
        where: e.user_id == ^user_id and e.event_type == ^event_type,
        select: fragment("COALESCE(SUM(CAST(metadata->>? AS DECIMAL)), 0)", ^field)
      )
      |> Repo.one()

    result || Decimal.new("0")
  end

  defp extract_target_ids(events, event_type) do
    events
    |> Enum.filter(&(&1.event_type == event_type))
    |> Enum.map(& &1.target_id)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.map(&to_integer/1)
  end

  defp extract_carted_not_purchased(events) do
    carted = extract_target_ids(events, "product_add_to_cart") |> MapSet.new()
    purchased = extract_target_ids(events, "purchase_complete") |> MapSet.new()
    MapSet.difference(carted, purchased) |> MapSet.to_list()
  end

  # ============ Private: Shopping ============

  defp calculate_shop_interest(events) do
    shop_events = Enum.count(events, &(&1.event_category == "shop"))
    total_events = max(length(events), 1)
    Float.round(min(shop_events / total_events * 3, 1.0), 2)
  end

  defp calculate_price_sensitivity(events) do
    abandon_count = count_type(events, "checkout_abandon")
    purchase_count = count_type(events, "purchase_complete")

    cond do
      purchase_count == 0 and abandon_count == 0 -> "unknown"
      abandon_count > purchase_count * 2 -> "high"
      abandon_count > purchase_count -> "medium"
      true -> "low"
    end
  end

  # ============ Private: Engagement ============

  defp most_recent_event_time([]), do: nil
  defp most_recent_event_time([first | _]) do
    case first.inserted_at do
      %NaiveDateTime{} = ndt -> DateTime.from_naive!(ndt, "Etc/UTC")
      other -> other
    end
  end

  defp days_since_active(user_id) do
    case get_last_event(user_id) do
      nil -> 999
      event ->
        NaiveDateTime.diff(NaiveDateTime.utc_now(), event.inserted_at, :day)
    end
  end

  defp get_last_event(user_id) do
    UserEvent
    |> where([e], e.user_id == ^user_id)
    |> order_by([e], desc: e.inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  defp calculate_session_frequency(events) do
    session_count = events
      |> Enum.filter(&(&1.event_type == "session_start"))
      |> length()

    # Assume events span up to 30 days (4.3 weeks)
    Float.round(session_count / 4.3, 1)
  end

  defp calculate_streak(user_id) do
    # Get daily login events ordered by date
    events =
      from(e in UserEvent,
        where: e.user_id == ^user_id and e.event_type == "daily_login",
        select: fragment("DATE(?)", e.inserted_at),
        distinct: true,
        order_by: [desc: fragment("DATE(?)", e.inserted_at)]
      )
      |> Repo.all()

    count_consecutive_days(events, Date.utc_today(), 0)
  end

  defp count_consecutive_days([], _expected, count), do: count
  defp count_consecutive_days([date | rest], expected, count) do
    if Date.diff(expected, date) <= 1 do
      count_consecutive_days(rest, Date.add(date, -1), count + 1)
    else
      count
    end
  end

  # ============ Private: Notification Responsiveness ============

  defp calculate_email_rate(user_id, type, days) do
    since = DateTime.utc_now() |> DateTime.add(-days, :day) |> DateTime.truncate(:second)

    stats =
      from(l in EmailLog,
        where: l.user_id == ^user_id and l.sent_at >= ^since,
        select: %{
          sent: count(l.id),
          value: count(field(l, ^opened_or_clicked_field(type)))
        }
      )
      |> Repo.one()

    if stats && stats.sent > 0,
      do: Float.round(stats.value / stats.sent, 2),
      else: 0.0
  end

  defp opened_or_clicked_field(:opened), do: :opened_at
  defp opened_or_clicked_field(:clicked), do: :clicked_at

  defp calculate_in_app_click_rate(user_id, days) do
    since = DateTime.utc_now() |> DateTime.add(-days, :day) |> DateTime.truncate(:second)

    stats =
      from(n in BlocksterV2.Notifications.Notification,
        where: n.user_id == ^user_id and n.inserted_at >= ^since,
        select: %{
          total: count(n.id),
          clicked: count(n.clicked_at)
        }
      )
      |> Repo.one()

    if stats && stats.total > 0,
      do: Float.round(stats.clicked / stats.total, 2),
      else: 0.0
  end

  defp find_best_email_hour(user_id) do
    result =
      from(l in EmailLog,
        where: l.user_id == ^user_id and not is_nil(l.opened_at),
        group_by: fragment("EXTRACT(HOUR FROM ?)", l.opened_at),
        order_by: [desc: count(l.id)],
        select: fragment("CAST(EXTRACT(HOUR FROM ?) AS INTEGER)", l.opened_at),
        limit: 1
      )
      |> Repo.one()

    result
  end

  defp calculate_fatigue(user_id, events_7d) do
    notification_events = Enum.filter(events_7d, &(&1.event_category == "notification"))
    dismissed = Enum.count(notification_events, &(&1.event_type == "notification_dismissed"))
    total_notifs = max(length(notification_events), 1)

    dismiss_rate = dismissed / total_notifs

    # Also factor in email ignoring
    email_open_rate = calculate_email_rate(user_id, :opened, 7)
    email_ignore_factor = max(1.0 - email_open_rate, 0.0)

    fatigue = dismiss_rate * 0.5 + email_ignore_factor * 0.5
    Float.round(min(fatigue, 1.0), 2)
  end

  # ============ Private: Referral ============

  defp calculate_referral_propensity(events) do
    shares = count_type(events, "article_share") + count_type(events, "referral_link_share")
    referrals = count_type(events, "referral_conversion")

    share_score = min(shares / 5.0, 0.5)
    referral_score = min(referrals / 3.0, 0.5)

    Float.round(share_score + referral_score, 2)
  end

  # ============ Private: Engagement Sub-Scores (0-100) ============

  defp calculate_activity_score(data) do
    sessions = data[:avg_sessions_per_week] || 0.0
    streak = data[:consecutive_active_days] || 0
    days_inactive = data[:days_since_last_active] || 0

    session_score = min(sessions / 7.0, 1.0) * 40
    streak_score = min(streak / 14.0, 1.0) * 30
    recency_score = max(1.0 - (days_inactive / 30.0), 0.0) * 30

    session_score + streak_score + recency_score
  end

  defp calculate_content_score(data) do
    articles_7d = data[:articles_read_last_7d] || 0
    completion = data[:content_completion_rate] || 0.0

    reading_score = min(articles_7d / 10.0, 1.0) * 60
    completion_score = completion * 40

    reading_score + completion_score
  end

  defp calculate_commerce_score(data) do
    purchases = data[:purchase_count] || 0
    shop_interest = data[:shop_interest_score] || 0.0

    purchase_score = min(purchases / 5.0, 1.0) * 70
    interest_score = shop_interest * 30

    purchase_score + interest_score
  end

  defp calculate_social_score(data) do
    referrals = data[:referrals_converted] || 0
    propensity = data[:referral_propensity] || 0.0

    referral_score = min(referrals / 5.0, 1.0) * 60
    propensity_score = propensity * 40

    referral_score + propensity_score
  end

  defp calculate_notification_score(data) do
    email_rate = data[:email_open_rate_30d] || 0.0
    in_app_rate = data[:in_app_click_rate_30d] || 0.0
    fatigue = data[:notification_fatigue_score] || 0.0

    email_score = email_rate * 40
    in_app_score = in_app_rate * 30
    fatigue_penalty = fatigue * -30

    max(email_score + in_app_score + fatigue_penalty, 0.0)
  end

  # ============ Private: Helpers ============

  defp get_decimal(data, key) do
    val = data[key]
    cond do
      is_nil(val) -> Decimal.new("0")
      is_struct(val, Decimal) -> val
      is_binary(val) -> Decimal.new(val)
      is_number(val) -> Decimal.from_float(val / 1)
      true -> Decimal.new("0")
    end
  end

  defp to_integer(val) when is_integer(val), do: val
  defp to_integer(val) when is_binary(val) do
    case Integer.parse(val) do
      {int, _} -> int
      :error -> 0
    end
  end
  defp to_integer(val) when is_float(val), do: round(val)
  defp to_integer(_), do: 0
end
