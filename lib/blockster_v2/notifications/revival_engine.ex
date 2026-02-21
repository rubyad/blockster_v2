defmodule BlocksterV2.Notifications.RevivalEngine do
  @moduledoc """
  Manages revival sequences for dormant users. Classifies user type
  (reader, gambler, shopper, hub_subscriber) and selects appropriate
  re-engagement messages based on how long they've been away.

  Also handles welcome back detection and engagement hook logic
  (daily check-in bonus, reading streaks, challenges).
  """

  import Ecto.Query
  alias BlocksterV2.{Repo, Notifications}
  alias BlocksterV2.Notifications.{Notification, UserProfile}

  require Logger

  # ============ User Type Classification ============

  @doc """
  Classify a user's primary type based on their profile data.
  Returns one of: "reader", "gambler", "shopper", "hub_subscriber", "general"
  """
  def classify_user_type(profile) do
    scores = %{
      reader: reader_score(profile),
      gambler: gambler_score(profile),
      shopper: shopper_score(profile),
      hub_subscriber: hub_subscriber_score(profile)
    }

    {type, score} = Enum.max_by(scores, fn {_k, v} -> v end)

    if score > 0.0 do
      Atom.to_string(type)
    else
      "general"
    end
  end

  defp reader_score(profile) do
    articles = profile.total_articles_read || 0
    completion = profile.content_completion_rate || 0.0

    min(articles / 20.0, 1.0) * 0.6 + completion * 0.4
  end

  defp gambler_score(profile) do
    games = profile.games_played_last_30d || 0
    total_bets = profile.total_bets_placed || 0

    min(games / 10.0, 1.0) * 0.5 + min(total_bets / 20.0, 1.0) * 0.5
  end

  defp shopper_score(profile) do
    purchases = profile.purchase_count || 0
    shop_interest = profile.shop_interest_score || 0.0

    min(purchases / 3.0, 1.0) * 0.6 + shop_interest * 0.4
  end

  defp hub_subscriber_score(profile) do
    hubs = profile.preferred_hubs || []
    length(hubs) / 5.0 |> min(1.0)
  end

  # ============ Revival Sequences ============

  @doc """
  Get the appropriate revival message for a user based on their type and days away.
  Returns %{title, body, action_url, action_label, offer} map.
  """
  def get_revival_message(profile, days_away) do
    user_type = classify_user_type(profile)
    get_revival_message_for_type(user_type, profile, days_away)
  end

  @doc """
  Get revival message for a specific user type.
  """
  def get_revival_message_for_type(user_type, profile, days_away) do
    stage = revival_stage(days_away)

    case {user_type, stage} do
      # Content Reader
      {"reader", 1} ->
        hubs = format_hub_names(profile.preferred_hubs)
        %{
          title: "You missed new articles from #{hubs}",
          body: "Your favorite hubs have published new content since your last visit.",
          action_url: "/",
          action_label: "Read Now",
          offer: nil
        }

      {"reader", 2} ->
        streak = profile.consecutive_active_days || 0
        %{
          title: "Your reading streak was #{streak} days. Start a new one?",
          body: "Jump back in and build your streak for bonus BUX rewards.",
          action_url: "/",
          action_label: "Start Streak",
          offer: nil
        }

      {"reader", 3} ->
        %{
          title: "Here's 200 bonus BUX — read 1 article to claim",
          body: "We saved 200 BUX for you. Read any article to add them to your balance.",
          action_url: "/",
          action_label: "Claim BUX",
          offer: %{bux_bonus: 200}
        }

      {"reader", 4} ->
        %{
          title: "A special roundup just for you",
          body: "We compiled the best articles from this month based on your interests.",
          action_url: "/",
          action_label: "Read Roundup",
          offer: %{bux_bonus: 200}
        }

      # Gambler
      {"gambler", 1} ->
        %{
          title: "The game table misses you",
          body: "Your BUX balance is waiting. Come play a round.",
          action_url: "/play",
          action_label: "Play Now",
          offer: nil
        }

      {"gambler", 2} ->
        %{
          title: "Free game! We credited 100 BUX to your account",
          body: "100 BUX on the house. Play now before they expire.",
          action_url: "/play",
          action_label: "Play Free",
          offer: %{bux_bonus: 100}
        }

      {"gambler", 3} ->
        %{
          title: "New game mode launched + 0.5 free ROGUE",
          body: "Try the latest game mode with 0.5 free ROGUE. No risk, all reward.",
          action_url: "/play",
          action_label: "Try Now",
          offer: %{free_rogue: 0.5}
        }

      {"gambler", 4} ->
        %{
          title: "Double-or-nothing: 500 free BUX. One game.",
          body: "We'll give you 500 BUX for one last game. What do you say?",
          action_url: "/play",
          action_label: "Accept Challenge",
          offer: %{bux_bonus: 500}
        }

      # Shopper
      {"shopper", 1} ->
        %{
          title: "Items you viewed are selling fast",
          body: "Products you looked at recently are going quickly. Don't miss out.",
          action_url: "/shop",
          action_label: "Shop Now",
          offer: nil
        }

      {"shopper", 2} ->
        %{
          title: "Your BUX can buy something special",
          body: "Use your BUX balance toward your next purchase.",
          action_url: "/shop",
          action_label: "Browse Shop",
          offer: nil
        }

      {"shopper", 3} ->
        %{
          title: "Exclusive 15% off for returning shoppers",
          body: "48 hours only. Your exclusive welcome-back discount is ready.",
          action_url: "/shop",
          action_label: "Shop & Save",
          offer: %{discount_pct: 15}
        }

      {"shopper", 4} ->
        %{
          title: "New arrivals + your welcome-back discount",
          body: "Fresh products just dropped, and your exclusive discount is still active.",
          action_url: "/shop",
          action_label: "See New Arrivals",
          offer: %{discount_pct: 15}
        }

      # Hub Subscriber
      {"hub_subscriber", 1} ->
        hubs = format_hub_names(profile.preferred_hubs)
        %{
          title: "#{hubs} published new articles",
          body: "Your subscribed hubs have been busy since your last visit.",
          action_url: "/",
          action_label: "Catch Up",
          offer: nil
        }

      {"hub_subscriber", 2} ->
        hubs = format_hub_names(profile.preferred_hubs)
        %{
          title: "Your hubs are active! #{hubs}",
          body: "Members of your hubs have been reading and earning BUX. Join them!",
          action_url: "/",
          action_label: "Read Now",
          offer: nil
        }

      {"hub_subscriber", 3} ->
        %{
          title: "Hub members earned BUX this week",
          body: "Your hubs' community is growing. Join in and earn BUX by reading.",
          action_url: "/",
          action_label: "Start Reading",
          offer: %{bux_bonus: 100}
        }

      {"hub_subscriber", 4} ->
        %{
          title: "Hub spotlight: why subscribers keep coming back",
          body: "Discover what makes your favorite hubs special. Plus 200 bonus BUX.",
          action_url: "/",
          action_label: "Explore Hubs",
          offer: %{bux_bonus: 200}
        }

      # General / fallback
      {_, 1} ->
        %{
          title: "We've missed you at Blockster",
          body: "New content, new features — come see what's changed.",
          action_url: "/",
          action_label: "Explore",
          offer: nil
        }

      {_, 2} ->
        %{
          title: "Your BUX are waiting",
          body: "You have BUX in your account. Come earn more by reading.",
          action_url: "/",
          action_label: "Earn BUX",
          offer: nil
        }

      {_, 3} ->
        %{
          title: "Here's 200 BUX on us",
          body: "We saved 200 bonus BUX for you. Come back and claim them.",
          action_url: "/",
          action_label: "Claim BUX",
          offer: %{bux_bonus: 200}
        }

      {_, _} ->
        %{
          title: "Welcome back to Blockster",
          body: "We saved some surprises for you. Come see what's new.",
          action_url: "/",
          action_label: "Explore",
          offer: %{bux_bonus: 200}
        }
    end
  end

  @doc """
  Determine the revival stage (1-4) based on days away.
  Stage 1: 3 days, Stage 2: 7 days, Stage 3: 14 days, Stage 4: 30 days.
  """
  def revival_stage(days_away) do
    cond do
      days_away >= 30 -> 4
      days_away >= 14 -> 3
      days_away >= 7 -> 2
      days_away >= 3 -> 1
      true -> 0
    end
  end

  # ============ Welcome Back Detection ============

  @doc """
  Check if a user qualifies for a welcome back experience.
  Returns {:welcome_back, data} or :skip.
  """
  def check_welcome_back(user_id, profile) do
    days_away = profile.days_since_last_active || 0

    if days_away >= 7 && !welcome_back_sent_recently?(user_id) do
      bonus = calculate_return_bonus(days_away, profile)
      user_type = classify_user_type(profile)

      {:welcome_back, %{
        days_away: days_away,
        user_type: user_type,
        bonus_bux: bonus,
        missed_articles: estimate_missed_articles(profile),
        message: welcome_back_message(user_type, days_away)
      }}
    else
      :skip
    end
  end

  @doc """
  Calculate the return bonus based on days away and engagement history.
  """
  def calculate_return_bonus(days_away, profile) do
    base = cond do
      days_away >= 30 -> 500
      days_away >= 14 -> 200
      days_away >= 7 -> 100
      true -> 50
    end

    # Boost for previously engaged users
    engagement_score = profile.engagement_score || 0.0
    multiplier = if engagement_score > 50.0, do: 1.5, else: 1.0

    round(base * multiplier)
  end

  @doc """
  Fire a welcome back notification for a returning user.
  """
  def fire_welcome_back(user_id, welcome_data) do
    Notifications.create_notification(user_id, %{
      type: "welcome_back",
      category: "system",
      title: "Welcome back! You were missed for #{welcome_data.days_away} days",
      body: welcome_data.message,
      action_url: "/",
      action_label: "See What's New",
      metadata: %{
        days_away: welcome_data.days_away,
        bonus_bux: welcome_data.bonus_bux,
        user_type: welcome_data.user_type,
        missed_articles: welcome_data.missed_articles
      }
    })
  end

  # ============ Engagement Hooks ============

  @doc """
  Check if a user earned their daily check-in bonus.
  Returns {:daily_bonus, bux_amount} or :skip.
  """
  def check_daily_bonus(user_id) do
    if !already_got_daily_bonus?(user_id) do
      {:daily_bonus, 50}
    else
      :skip
    end
  end

  @doc """
  Get the streak reward for a given streak length.
  Returns {streak_length, bux_reward} or nil.
  """
  def streak_reward(streak_days) do
    rewards = %{
      3 => 100,
      7 => 500,
      14 => 1_500,
      30 => 5_000
    }

    case Map.get(rewards, streak_days) do
      nil -> nil
      bux -> {streak_days, bux}
    end
  end

  @doc """
  Generate a daily challenge for a user based on their profile.
  Returns %{description, reward_bux, target, progress} map.
  """
  def daily_challenge(profile) do
    user_type = classify_user_type(profile)

    case user_type do
      "reader" ->
        %{
          description: "Read 2 articles today for 2x BUX rewards",
          reward_bux: 100,
          target: 2,
          type: "read_articles"
        }

      "gambler" ->
        %{
          description: "Play 3 games today for 200 bonus BUX",
          reward_bux: 200,
          target: 3,
          type: "play_games"
        }

      "shopper" ->
        %{
          description: "Browse 3 products for 50 bonus BUX",
          reward_bux: 50,
          target: 3,
          type: "view_products"
        }

      _ ->
        %{
          description: "Read 1 article and explore 1 hub for 100 BUX",
          reward_bux: 100,
          target: 2,
          type: "explore"
        }
    end
  end

  @doc """
  Generate a weekly quest for a user based on their profile.
  Returns %{description, reward_bux, target, type} map.
  """
  def weekly_quest(profile) do
    user_type = classify_user_type(profile)

    case user_type do
      "reader" ->
        %{
          description: "Read from 3 different hubs this week for 1,000 BUX",
          reward_bux: 1_000,
          target: 3,
          type: "read_different_hubs"
        }

      "gambler" ->
        %{
          description: "Win 5 games this week for 1,500 BUX",
          reward_bux: 1_500,
          target: 5,
          type: "win_games"
        }

      _ ->
        %{
          description: "Read 5 articles this week for 500 BUX",
          reward_bux: 500,
          target: 5,
          type: "read_articles_weekly"
        }
    end
  end

  # ============ Retention Analytics Queries ============

  @doc """
  Get churn risk distribution across all profiled users.
  Returns %{healthy: n, watch: n, at_risk: n, critical: n, churning: n}.
  """
  def churn_risk_distribution do
    from(p in UserProfile,
      group_by: p.churn_risk_level,
      select: {p.churn_risk_level, count(p.id)}
    )
    |> Repo.all()
    |> Map.new()
    |> then(fn counts ->
      %{
        healthy: Map.get(counts, "low", 0),
        watch: Map.get(counts, "medium", 0),
        at_risk: Map.get(counts, "high", 0),
        critical: Map.get(counts, "critical", 0)
      }
    end)
  end

  @doc """
  Get revival success rate — what % of users who got a revival notification
  came back (had a session) within 7 days.
  """
  def revival_success_rate(days_lookback \\ 30) do
    since = NaiveDateTime.utc_now() |> NaiveDateTime.add(-days_lookback * 86400, :second)

    revival_notifs =
      from(n in Notification,
        where: n.type in ["re_engagement", "churn_intervention", "welcome_back"],
        where: n.inserted_at >= ^since,
        select: %{user_id: n.user_id, sent_at: n.inserted_at}
      )
      |> Repo.all()

    total = length(revival_notifs)

    if total == 0 do
      %{total_sent: 0, returned: 0, rate: 0.0}
    else
      returned =
        Enum.count(revival_notifs, fn notif ->
          check_since = notif.sent_at
          check_until = NaiveDateTime.add(check_since, 7 * 86400, :second)

          from(e in BlocksterV2.Notifications.UserEvent,
            where: e.user_id == ^notif.user_id,
            where: e.event_type == "session_start",
            where: e.inserted_at > ^check_since,
            where: e.inserted_at <= ^check_until
          )
          |> Repo.exists?()
        end)

      %{
        total_sent: total,
        returned: returned,
        rate: Float.round(returned / total, 2)
      }
    end
  end

  @doc """
  Get engagement tier distribution for all profiled users.
  """
  def engagement_tier_distribution do
    from(p in UserProfile,
      group_by: p.engagement_tier,
      select: {p.engagement_tier, count(p.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  # ============ Private Helpers ============

  defp format_hub_names(nil), do: "your hubs"
  defp format_hub_names([]), do: "your hubs"
  defp format_hub_names(hubs) when is_list(hubs) do
    names = Enum.take(hubs, 2) |> Enum.map(fn h -> h["name"] || h[:name] || "Hub" end)

    case names do
      [one] -> one
      [a, b] -> "#{a} and #{b}"
      _ -> "your hubs"
    end
  end

  defp welcome_back_sent_recently?(user_id) do
    since = NaiveDateTime.utc_now() |> NaiveDateTime.add(-7 * 86400, :second)

    from(n in Notification,
      where: n.user_id == ^user_id,
      where: n.type == "welcome_back",
      where: n.inserted_at >= ^since
    )
    |> Repo.exists?()
  end

  defp already_got_daily_bonus?(user_id) do
    today_start =
      NaiveDateTime.utc_now()
      |> NaiveDateTime.to_date()
      |> NaiveDateTime.new!(~T[00:00:00])

    from(n in Notification,
      where: n.user_id == ^user_id,
      where: n.type == "daily_bonus",
      where: n.inserted_at >= ^today_start
    )
    |> Repo.exists?()
  end

  defp estimate_missed_articles(profile) do
    # Rough estimate: avg articles_read_last_7d * weeks away
    weekly_rate = (profile.articles_read_last_7d || 0)
    days_away = profile.days_since_last_active || 0
    weeks_away = max(days_away / 7.0, 1.0)

    round(weekly_rate * weeks_away)
  end

  defp welcome_back_message(user_type, days_away) do
    case user_type do
      "reader" ->
        "While you were away for #{days_away} days, your favorite hubs published new articles. Start reading to earn BUX!"

      "gambler" ->
        "#{days_away} days away! Your lucky streak could be waiting. Come play a round."

      "shopper" ->
        "New products dropped while you were away for #{days_away} days. Check out the shop!"

      "hub_subscriber" ->
        "Your subscribed hubs posted new content over the last #{days_away} days. Catch up now!"

      _ ->
        "Welcome back after #{days_away} days! New content, new rewards — come explore."
    end
  end
end
