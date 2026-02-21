defmodule BlocksterV2.Workers.ReEngagementWorker do
  @moduledoc """
  Sends re-engagement emails to inactive users.
  Scheduled via Oban cron at 11:00 AM UTC daily.
  Targets users inactive for 3, 7, 14, or 30 days.
  """

  use Oban.Worker, queue: :email_marketing, max_attempts: 3

  alias BlocksterV2.{Notifications, Repo, Mailer}
  alias BlocksterV2.Notifications.{RateLimiter, EmailBuilder}
  import Ecto.Query

  @inactivity_tiers [3, 7, 14, 30]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "days_inactive" => days}}) do
    # Individual user re-engagement
    send_re_engagement(user_id, days)
  end

  def perform(%Oban.Job{args: _args}) do
    # Batch job: find inactive users per tier
    Enum.each(@inactivity_tiers, fn days ->
      users = get_inactive_users(days)

      Enum.each(users, fn user ->
        %{user_id: user.id, days_inactive: days}
        |> __MODULE__.new()
        |> Oban.insert()
      end)
    end)

    :ok
  end

  defp send_re_engagement(user_id, days) do
    case RateLimiter.can_send?(user_id, :email, "re_engagement") do
      :ok ->
        user = Repo.get(BlocksterV2.Accounts.User, user_id)

        if user && user.email do
          prefs = Notifications.get_preferences(user_id)
          token = if prefs, do: prefs.unsubscribe_token, else: ""

          articles = get_recent_articles(5)

          special_offer =
            if days >= 30, do: "Your favorite hubs have new content — pick up where you left off!", else: nil

          email =
            EmailBuilder.re_engagement(
              user.email,
              user.username || user.email,
              token,
              %{
                days_inactive: days,
                articles: articles,
                special_offer: special_offer
              }
            )

          case Mailer.deliver(email) do
            {:ok, _} ->
              Notifications.create_email_log(%{
                user_id: user_id,
                email_type: "re_engagement_#{days}d",
                subject: email.subject,
                sent_at: DateTime.utc_now() |> DateTime.truncate(:second)
              })
              :ok

            {:error, reason} ->
              {:error, reason}
          end
        else
          :ok
        end

      :defer ->
        %{user_id: user_id, days_inactive: days}
        |> __MODULE__.new(schedule_in: 3600)
        |> Oban.insert()
        :ok

      {:error, _} ->
        :ok
    end
  end

  defp get_inactive_users(days) do
    cutoff = DateTime.utc_now() |> DateTime.add(-days * 24 * 3600, :second)
    # Exact day match (e.g., inactive for exactly 7 days, ±1 day)
    cutoff_end = DateTime.add(cutoff, 24 * 3600, :second)

    from(u in BlocksterV2.Accounts.User,
      where: not is_nil(u.email),
      where: u.last_seen_at < ^cutoff and u.last_seen_at >= ^cutoff_end,
      select: u
    )
    |> Repo.all()
    |> Enum.filter(fn user ->
      case Notifications.get_preferences(user.id) do
        nil -> false
        prefs -> prefs.email_enabled && prefs.email_re_engagement
      end
    end)
  rescue
    # last_seen_at may not exist yet
    _ -> []
  end

  defp get_recent_articles(limit) do
    from(p in BlocksterV2.Blog.Post,
      where: not is_nil(p.published_at),
      order_by: [desc: p.published_at],
      limit: ^limit,
      select: %{title: p.title, slug: p.slug}
    )
    |> Repo.all()
  rescue
    _ -> []
  end
end
