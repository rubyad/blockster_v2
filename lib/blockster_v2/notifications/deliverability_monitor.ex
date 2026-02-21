defmodule BlocksterV2.Notifications.DeliverabilityMonitor do
  @moduledoc """
  Monitors email deliverability metrics: bounce rates, open rates,
  click rates, and complaint rates. Fires alerts when thresholds are exceeded.
  """

  import Ecto.Query
  alias BlocksterV2.Repo
  alias BlocksterV2.Notifications.{EmailLog, Notification}

  require Logger

  @bounce_alert_threshold 0.05
  @low_open_rate_threshold 0.10
  @high_complaint_threshold 0.01

  @doc """
  Calculate email deliverability metrics for a given time period.
  Returns %{sent, delivered, bounced, opened, clicked, bounce_rate, open_rate, click_rate}.
  """
  def calculate_metrics(days \\ 7) do
    since = DateTime.utc_now() |> DateTime.add(-days, :day) |> DateTime.truncate(:second)

    stats =
      from(l in EmailLog,
        where: l.sent_at >= ^since,
        select: %{
          sent: count(l.id),
          bounced: filter(count(l.id), l.bounced == true),
          opened: count(l.opened_at),
          clicked: count(l.clicked_at)
        }
      )
      |> Repo.one()

    sent = stats.sent || 0
    bounced = stats.bounced || 0
    opened = stats.opened || 0
    clicked = stats.clicked || 0

    %{
      sent: sent,
      delivered: sent - bounced,
      bounced: bounced,
      opened: opened,
      clicked: clicked,
      bounce_rate: safe_rate(bounced, sent),
      open_rate: safe_rate(opened, sent),
      click_rate: safe_rate(clicked, sent)
    }
  end

  @doc """
  Calculate metrics broken down by email type.
  Returns list of %{email_type, sent, opened, clicked, bounce_rate, open_rate}.
  """
  def metrics_by_type(days \\ 7) do
    since = DateTime.utc_now() |> DateTime.add(-days, :day) |> DateTime.truncate(:second)

    from(l in EmailLog,
      where: l.sent_at >= ^since,
      group_by: l.email_type,
      select: %{
        email_type: l.email_type,
        sent: count(l.id),
        bounced: filter(count(l.id), l.bounced == true),
        opened: count(l.opened_at),
        clicked: count(l.clicked_at)
      }
    )
    |> Repo.all()
    |> Enum.map(fn row ->
      Map.merge(row, %{
        bounce_rate: safe_rate(row.bounced, row.sent),
        open_rate: safe_rate(row.opened, row.sent),
        click_rate: safe_rate(row.clicked, row.sent)
      })
    end)
  end

  @doc """
  Check for deliverability issues and return list of alerts.
  Each alert is %{type, severity, message, value, threshold}.
  """
  def check_alerts(days \\ 7) do
    metrics = calculate_metrics(days)
    alerts = []

    alerts =
      if metrics.sent > 0 && metrics.bounce_rate > @bounce_alert_threshold do
        [%{
          type: "high_bounce_rate",
          severity: if(metrics.bounce_rate > 0.10, do: "critical", else: "warning"),
          message: "Bounce rate is #{format_pct(metrics.bounce_rate)} (threshold: #{format_pct(@bounce_alert_threshold)})",
          value: metrics.bounce_rate,
          threshold: @bounce_alert_threshold
        } | alerts]
      else
        alerts
      end

    alerts =
      if metrics.sent > 10 && metrics.open_rate < @low_open_rate_threshold do
        [%{
          type: "low_open_rate",
          severity: "warning",
          message: "Open rate is #{format_pct(metrics.open_rate)} (threshold: #{format_pct(@low_open_rate_threshold)})",
          value: metrics.open_rate,
          threshold: @low_open_rate_threshold
        } | alerts]
      else
        alerts
      end

    Enum.reverse(alerts)
  end

  @doc """
  Get the daily send volume for the last N days.
  Returns list of %{date, count}.
  """
  def daily_send_volume(days \\ 30) do
    since = DateTime.utc_now() |> DateTime.add(-days, :day) |> DateTime.truncate(:second)

    from(l in EmailLog,
      where: l.sent_at >= ^since,
      group_by: fragment("DATE(?)", l.sent_at),
      order_by: [asc: fragment("DATE(?)", l.sent_at)],
      select: %{
        date: fragment("DATE(?)", l.sent_at),
        count: count(l.id)
      }
    )
    |> Repo.all()
  end

  @doc """
  Get bounce details — list of recent bounced emails.
  """
  def recent_bounces(limit \\ 20) do
    from(l in EmailLog,
      where: l.bounced == true,
      order_by: [desc: l.sent_at],
      limit: ^limit,
      select: %{
        id: l.id,
        user_id: l.user_id,
        email_type: l.email_type,
        sent_at: l.sent_at
      }
    )
    |> Repo.all()
  end

  @doc """
  Get overall deliverability health score (0-100).
  Factors in bounce rate, open rate, and click rate.
  """
  def health_score(days \\ 7) do
    metrics = calculate_metrics(days)

    if metrics.sent == 0 do
      100.0
    else
      bounce_score = max(1.0 - metrics.bounce_rate * 10, 0.0) * 40
      open_score = min(metrics.open_rate * 2, 1.0) * 35
      click_score = min(metrics.click_rate * 5, 1.0) * 25

      Float.round(bounce_score + open_score + click_score, 1)
    end
  end

  # ============ Private Helpers ============

  defp safe_rate(_numerator, 0), do: 0.0
  defp safe_rate(numerator, denominator) do
    Float.round(numerator / denominator, 4)
  end

  defp format_pct(rate) do
    "#{Float.round(rate * 100, 1)}%"
  end
end
