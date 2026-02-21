defmodule BlocksterV2.Notifications.EngagementScorer do
  @moduledoc """
  Calculates notification engagement scores for users.
  Used to personalize future sends and identify high/low engagement users.
  """

  import Ecto.Query
  alias BlocksterV2.Repo
  alias BlocksterV2.Notifications.{EmailLog, Notification}

  @doc """
  Calculate comprehensive engagement score for a user over the last 30 days.
  Returns a map with rates, preferred time, and preferred categories.
  """
  def calculate_score(user_id) do
    thirty_days_ago = DateTime.utc_now() |> DateTime.add(-30, :day) |> DateTime.truncate(:second)

    email_stats = email_engagement(user_id, thirty_days_ago)
    in_app_stats = in_app_engagement(user_id, thirty_days_ago)
    preferred_hour = most_active_hour(user_id, thirty_days_ago)
    top_categories = top_clicked_categories(user_id, thirty_days_ago)

    %{
      email_open_rate: email_stats.open_rate,
      email_click_rate: email_stats.click_rate,
      emails_sent: email_stats.sent,
      emails_opened: email_stats.opened,
      emails_clicked: email_stats.clicked,
      in_app_read_rate: in_app_stats.read_rate,
      in_app_click_rate: in_app_stats.click_rate,
      in_app_delivered: in_app_stats.delivered,
      in_app_read: in_app_stats.read,
      preferred_hour: preferred_hour,
      preferred_categories: top_categories,
      engagement_tier: classify_tier(email_stats.open_rate, in_app_stats.read_rate)
    }
  end

  @doc """
  Classify user into engagement tier based on rates.
  """
  def classify_tier(email_open_rate, in_app_read_rate) do
    avg = (email_open_rate + in_app_read_rate) / 2

    cond do
      avg >= 0.6 -> :highly_engaged
      avg >= 0.3 -> :moderately_engaged
      avg >= 0.1 -> :low_engagement
      true -> :dormant
    end
  end

  @doc """
  Get aggregate engagement stats for all users (for admin dashboard).
  """
  def aggregate_stats(days \\ 30) do
    since = DateTime.utc_now() |> DateTime.add(-days, :day) |> DateTime.truncate(:second)

    email_totals = email_totals(since)
    in_app_totals = in_app_totals(since)

    %{
      total_emails_sent: email_totals.sent,
      total_emails_opened: email_totals.opened,
      total_emails_clicked: email_totals.clicked,
      total_emails_bounced: email_totals.bounced,
      total_emails_unsubscribed: email_totals.unsubscribed,
      overall_open_rate: safe_rate(email_totals.opened, email_totals.sent),
      overall_click_rate: safe_rate(email_totals.clicked, email_totals.sent),
      overall_bounce_rate: safe_rate(email_totals.bounced, email_totals.sent),
      total_in_app_delivered: in_app_totals.delivered,
      total_in_app_read: in_app_totals.read,
      total_in_app_clicked: in_app_totals.clicked,
      in_app_read_rate: safe_rate(in_app_totals.read, in_app_totals.delivered),
      period_days: days
    }
  end

  @doc """
  Get daily email volume for charting (last N days).
  Returns list of %{date: Date, sent: integer, opened: integer, clicked: integer}.
  """
  def daily_email_volume(days \\ 30) do
    since = DateTime.utc_now() |> DateTime.add(-days, :day) |> DateTime.truncate(:second)

    from(l in EmailLog,
      where: l.sent_at >= ^since and l.email_type != "sms",
      group_by: fragment("DATE(?)", l.sent_at),
      select: %{
        date: fragment("DATE(?)", l.sent_at),
        sent: count(l.id),
        opened: count(l.opened_at),
        clicked: count(l.clicked_at)
      },
      order_by: fragment("DATE(?)", l.sent_at)
    )
    |> Repo.all()
  end

  @doc """
  Get send time distribution (hour of day) for heatmap.
  """
  def send_time_distribution(days \\ 30) do
    since = DateTime.utc_now() |> DateTime.add(-days, :day) |> DateTime.truncate(:second)

    from(l in EmailLog,
      where: l.sent_at >= ^since and l.email_type != "sms",
      group_by: fragment("EXTRACT(HOUR FROM ?)", l.sent_at),
      select: %{
        hour: fragment("EXTRACT(HOUR FROM ?)::integer", l.sent_at),
        sent: count(l.id),
        opened: count(l.opened_at),
        open_rate: fragment("CASE WHEN COUNT(*) > 0 THEN COUNT(?)::float / COUNT(*)::float ELSE 0 END", l.opened_at)
      },
      order_by: fragment("EXTRACT(HOUR FROM ?)", l.sent_at)
    )
    |> Repo.all()
  end

  @doc """
  Get engagement by notification type/channel.
  """
  def channel_comparison(days \\ 30) do
    since = DateTime.utc_now() |> DateTime.add(-days, :day) |> DateTime.truncate(:second)

    email_stats = email_totals(since)

    sms_sent =
      from(l in EmailLog, where: l.sent_at >= ^since and l.email_type == "sms")
      |> Repo.aggregate(:count, :id)

    in_app_stats = in_app_totals(since)

    [
      %{channel: "email", sent: email_stats.sent, engaged: email_stats.opened, rate: safe_rate(email_stats.opened, email_stats.sent)},
      %{channel: "in_app", sent: in_app_stats.delivered, engaged: in_app_stats.read, rate: safe_rate(in_app_stats.read, in_app_stats.delivered)},
      %{channel: "sms", sent: sms_sent, engaged: 0, rate: 0.0}
    ]
  end

  # ============ Private ============

  defp email_engagement(user_id, since) do
    stats =
      from(l in EmailLog,
        where: l.user_id == ^user_id and l.sent_at >= ^since and l.email_type != "sms",
        select: %{
          sent: count(l.id),
          opened: count(l.opened_at),
          clicked: count(l.clicked_at)
        }
      )
      |> Repo.one()

    %{
      sent: stats.sent,
      opened: stats.opened,
      clicked: stats.clicked,
      open_rate: safe_rate(stats.opened, stats.sent),
      click_rate: safe_rate(stats.clicked, stats.sent)
    }
  end

  defp in_app_engagement(user_id, since) do
    stats =
      from(n in Notification,
        where: n.user_id == ^user_id and n.inserted_at >= ^since,
        select: %{
          delivered: count(n.id),
          read: count(n.read_at),
          clicked: count(n.clicked_at)
        }
      )
      |> Repo.one()

    %{
      delivered: stats.delivered,
      read: stats.read,
      clicked: stats.clicked,
      read_rate: safe_rate(stats.read, stats.delivered),
      click_rate: safe_rate(stats.clicked, stats.delivered)
    }
  end

  defp email_totals(since) do
    stats =
      from(l in EmailLog,
        where: l.sent_at >= ^since and l.email_type != "sms",
        select: %{
          sent: count(l.id),
          opened: count(l.opened_at),
          clicked: count(l.clicked_at),
          bounced: filter(count(l.id), l.bounced == true),
          unsubscribed: filter(count(l.id), l.unsubscribed == true)
        }
      )
      |> Repo.one()

    stats || %{sent: 0, opened: 0, clicked: 0, bounced: 0, unsubscribed: 0}
  end

  defp in_app_totals(since) do
    stats =
      from(n in Notification,
        where: n.inserted_at >= ^since,
        select: %{
          delivered: count(n.id),
          read: count(n.read_at),
          clicked: count(n.clicked_at)
        }
      )
      |> Repo.one()

    stats || %{delivered: 0, read: 0, clicked: 0}
  end

  defp most_active_hour(user_id, since) do
    result =
      from(n in Notification,
        where: n.user_id == ^user_id and n.clicked_at >= ^since,
        group_by: fragment("EXTRACT(HOUR FROM ?)", n.clicked_at),
        order_by: [desc: count(n.id)],
        limit: 1,
        select: fragment("EXTRACT(HOUR FROM ?)::integer", n.clicked_at)
      )
      |> Repo.one()

    result || 9
  end

  defp top_clicked_categories(user_id, since) do
    from(n in Notification,
      where: n.user_id == ^user_id and not is_nil(n.clicked_at) and n.inserted_at >= ^since,
      group_by: n.category,
      order_by: [desc: count(n.id)],
      limit: 3,
      select: n.category
    )
    |> Repo.all()
  end

  defp safe_rate(_numerator, 0), do: 0.0
  defp safe_rate(numerator, denominator), do: Float.round(numerator / denominator, 4)
  end
