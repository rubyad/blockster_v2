defmodule BlocksterV2.Notifications.ChurnPredictor do
  @moduledoc """
  Enhanced churn prediction using 8 behavioral signals.
  Assigns risk tiers and selects appropriate interventions.

  Builds on top of ProfileEngine's basic churn risk by adding
  more granular signal analysis and intervention routing.
  """

  import Ecto.Query
  alias BlocksterV2.{Repo, Notifications, UserEvents}
  alias BlocksterV2.Notifications.{UserProfile, UserEvent, EmailLog, Notification}

  require Logger

  # ============ Risk Tiers ============

  @risk_tiers [
    %{min: 0.0, max: 0.3, status: "healthy", channels: [:none]},
    %{min: 0.3, max: 0.5, status: "watch", channels: [:personalization]},
    %{min: 0.5, max: 0.7, status: "at_risk", channels: [:in_app, :email]},
    %{min: 0.7, max: 0.9, status: "critical", channels: [:in_app, :email, :bonus]},
    %{min: 0.9, max: 1.01, status: "churning", channels: [:in_app, :email, :sms, :bonus]}
  ]

  @doc """
  Calculate detailed churn risk from 8 behavioral signals.
  Returns %{score, level, signals, intervention} map.
  """
  def predict_churn(profile) when is_map(profile) do
    signals = calculate_signals(profile)
    score = aggregate_signals(signals)
    level = classify_risk_level(score)
    tier = get_risk_tier(score)

    %{
      score: score,
      level: level,
      signals: signals,
      intervention: select_intervention(tier, profile)
    }
  end

  @doc """
  Calculate the 8 individual churn signals. Each returns 0.0-1.0.
  """
  def calculate_signals(profile) do
    %{
      frequency_decline: frequency_decline_signal(profile),
      session_shortening: session_shortening_signal(profile),
      email_engagement_decline: email_engagement_signal(profile),
      discovery_stall: discovery_stall_signal(profile),
      bux_earning_decline: bux_earning_decline_signal(profile),
      notification_fatigue: notification_fatigue_signal(profile),
      no_purchases: no_purchases_signal(profile),
      no_referrals: no_referrals_signal(profile)
    }
  end

  @doc """
  Aggregate 8 signals into a single churn risk score (0.0-1.0).
  """
  def aggregate_signals(signals) do
    weighted =
      signals[:frequency_decline] * 0.20 +
      signals[:session_shortening] * 0.15 +
      signals[:email_engagement_decline] * 0.15 +
      signals[:discovery_stall] * 0.10 +
      signals[:bux_earning_decline] * 0.15 +
      signals[:notification_fatigue] * 0.10 +
      signals[:no_purchases] * 0.08 +
      signals[:no_referrals] * 0.07

    Float.round(min(max(weighted, 0.0), 1.0), 2)
  end

  @doc """
  Classify risk level from score.
  """
  def classify_risk_level(score) do
    cond do
      score >= 0.9 -> "churning"
      score >= 0.7 -> "critical"
      score >= 0.5 -> "at_risk"
      score >= 0.3 -> "watch"
      true -> "healthy"
    end
  end

  @doc """
  Get the risk tier configuration for a given score.
  """
  def get_risk_tier(score) do
    Enum.find(@risk_tiers, List.last(@risk_tiers), fn tier ->
      score >= tier.min and score < tier.max
    end)
  end

  @doc """
  Select intervention strategy based on risk tier and user profile.
  Returns %{type, channels, message, offer} map.
  """
  def select_intervention(tier, profile) do
    case tier.status do
      "healthy" ->
        %{type: :none, channels: [], message: nil, offer: nil}

      "watch" ->
        %{
          type: :personalization,
          channels: [:in_app],
          message: "Increase content personalization",
          offer: nil
        }

      "at_risk" ->
        %{
          type: :re_engagement,
          channels: [:in_app, :email],
          message: we_miss_you_message(profile),
          offer: %{bux_bonus: 100}
        }

      "critical" ->
        %{
          type: :rescue,
          channels: [:in_app, :email],
          message: exclusive_offer_message(profile),
          offer: %{bux_bonus: 500, exclusive_content: true}
        }

      "churning" ->
        %{
          type: :all_out_save,
          channels: [:in_app, :email, :sms],
          message: last_chance_message(profile),
          offer: %{bux_bonus: 1000, free_rogue: 0.5, exclusive_discount: true}
        }
    end
  end

  @doc """
  Get users at or above a given risk level.
  Returns list of {user_id, profile} tuples.
  """
  def get_at_risk_users(min_score \\ 0.5) do
    from(p in UserProfile,
      where: p.churn_risk_score >= ^min_score,
      order_by: [desc: p.churn_risk_score],
      select: p
    )
    |> Repo.all()
  end

  @doc """
  Check if an intervention was already sent to a user recently.
  Returns true if an intervention notification was sent within the given days.
  """
  def intervention_sent_recently?(user_id, days \\ 7) do
    since = NaiveDateTime.utc_now() |> NaiveDateTime.add(-days * 86400, :second)

    from(n in Notification,
      where: n.user_id == ^user_id,
      where: n.type in ["re_engagement", "churn_intervention", "welcome"],
      where: n.inserted_at >= ^since
    )
    |> Repo.exists?()
  end

  @doc """
  Fire a churn intervention notification for a user.
  """
  def fire_intervention(user_id, prediction) do
    intervention = prediction.intervention

    if intervention.type == :none do
      :skip
    else
      attrs = %{
        type: "churn_intervention",
        category: "system",
        title: intervention_title(prediction.level),
        body: intervention.message || "We have something special for you!",
        metadata: %{
          churn_score: prediction.score,
          churn_level: prediction.level,
          intervention_type: Atom.to_string(intervention.type),
          offer: intervention.offer,
          signals: prediction.signals
        }
      }

      Notifications.create_notification(user_id, attrs)
    end
  end

  # ============ Individual Signal Calculations ============

  @doc false
  def frequency_decline_signal(profile) do
    sessions = profile.avg_sessions_per_week || 0.0
    days_inactive = profile.days_since_last_active || 0

    session_decline = max(1.0 - (sessions / 5.0), 0.0)
    inactivity = min(days_inactive / 21.0, 1.0)

    Float.round((session_decline * 0.5 + inactivity * 0.5), 2)
  end

  @doc false
  def session_shortening_signal(profile) do
    avg_duration = profile.avg_session_duration_ms || 0

    cond do
      avg_duration == 0 -> 0.5
      avg_duration < 30_000 -> 0.8
      avg_duration < 60_000 -> 0.5
      avg_duration < 180_000 -> 0.2
      true -> 0.0
    end
  end

  @doc false
  def email_engagement_signal(profile) do
    open_rate = profile.email_open_rate_30d || 0.0
    click_rate = profile.email_click_rate_30d || 0.0

    email_score = max(1.0 - open_rate, 0.0) * 0.6 + max(1.0 - click_rate, 0.0) * 0.4
    Float.round(min(email_score, 1.0), 2)
  end

  @doc false
  def discovery_stall_signal(profile) do
    preferred_hubs = profile.preferred_hubs || []

    cond do
      length(preferred_hubs) == 0 -> 0.8
      length(preferred_hubs) < 3 -> 0.4
      true -> 0.0
    end
  end

  @doc false
  def bux_earning_decline_signal(profile) do
    articles_7d = profile.articles_read_last_7d || 0
    articles_30d = profile.articles_read_last_30d || 0

    if articles_30d > 0 do
      weekly_avg = articles_30d / 4.3
      recent_ratio = if weekly_avg > 0, do: articles_7d / weekly_avg, else: 0.0

      decline = max(1.0 - recent_ratio, 0.0)
      Float.round(min(decline, 1.0), 2)
    else
      0.5
    end
  end

  @doc false
  def notification_fatigue_signal(profile) do
    Float.round(min(max(profile.notification_fatigue_score || 0.0, 0.0), 1.0), 2)
  end

  @doc false
  def no_purchases_signal(profile) do
    if (profile.purchase_count || 0) == 0, do: 0.3, else: 0.0
  end

  @doc false
  def no_referrals_signal(profile) do
    if (profile.referrals_converted || 0) == 0, do: 0.2, else: 0.0
  end

  # ============ Message Generation ============

  defp we_miss_you_message(profile) do
    days = profile.days_since_last_active || 0

    cond do
      days > 14 ->
        "It's been #{days} days! Your favorite hubs have published new content."
      days > 7 ->
        "We haven't seen you in a while. Check out what's new!"
      true ->
        "Your reading streak is at risk. Come back and keep it going!"
    end
  end

  defp exclusive_offer_message(profile) do
    cond do
      (profile.games_played_last_30d || 0) > 0 ->
        "Here's 500 free BUX and exclusive hub recommendations just for you."
      (profile.purchase_count || 0) > 0 ->
        "We saved 500 BUX for you, plus new products in the shop."
      true ->
        "Here's 500 free BUX to explore Blockster. New content awaits!"
    end
  end

  defp last_chance_message(profile) do
    cond do
      (profile.games_played_last_30d || 0) > 0 ->
        "We miss you! 1,000 BUX + 0.5 free ROGUE to play with. One last game?"
      (profile.purchase_count || 0) > 0 ->
        "Welcome back gift: 1,000 BUX + exclusive discount on your next purchase."
      true ->
        "We saved 1,000 BUX for you. Plus 0.5 free ROGUE to try BUX Booster!"
    end
  end

  defp intervention_title("churning"), do: "We really miss you!"
  defp intervention_title("critical"), do: "We have something special for you"
  defp intervention_title("at_risk"), do: "We miss you at Blockster"
  defp intervention_title("watch"), do: "Check out what's new"
  defp intervention_title(_), do: "Welcome back!"
end
