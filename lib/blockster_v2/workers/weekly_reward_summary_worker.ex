defmodule BlocksterV2.Workers.WeeklyRewardSummaryWorker do
  @moduledoc """
  Sends weekly BUX earnings summary emails.
  Scheduled via Oban cron at 10:00 AM UTC on Mondays.
  """

  use Oban.Worker, queue: :email_marketing, max_attempts: 3

  alias BlocksterV2.{Notifications, Repo, Mailer}
  alias BlocksterV2.Notifications.{RateLimiter, EmailBuilder}
  import Ecto.Query

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id}}) do
    send_weekly_summary(user_id)
  end

  def perform(%Oban.Job{args: _args}) do
    users = get_eligible_users()

    Enum.each(users, fn user ->
      %{user_id: user.id}
      |> __MODULE__.new()
      |> Oban.insert()
    end)

    :ok
  end

  defp send_weekly_summary(user_id) do
    case RateLimiter.can_send?(user_id, :email, "reward_summary") do
      :ok ->
        user = Repo.get(BlocksterV2.Accounts.User, user_id)

        if user && user.email do
          prefs = Notifications.get_preferences(user_id)
          token = if prefs, do: prefs.unsubscribe_token, else: ""
          stats = get_user_weekly_stats(user_id)

          email =
            EmailBuilder.weekly_reward_summary(
              user.email,
              user.username || user.email,
              token,
              stats
            )

          case Mailer.deliver(email) do
            {:ok, _} ->
              Notifications.create_email_log(%{
                user_id: user_id,
                email_type: "weekly_reward_summary",
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
        %{user_id: user_id}
        |> __MODULE__.new(schedule_in: 3600)
        |> Oban.insert()
        :ok

      {:error, _} ->
        :ok
    end
  end

  defp get_eligible_users do
    from(u in BlocksterV2.Accounts.User,
      where: not is_nil(u.email),
      select: u
    )
    |> Repo.all()
    |> Enum.filter(fn user ->
      case Notifications.get_preferences(user.id) do
        nil -> false
        prefs -> prefs.email_enabled && prefs.email_reward_alerts
      end
    end)
  end

  defp get_user_weekly_stats(_user_id) do
    # TODO: Pull actual stats from Mnesia engagement tracking
    # For now return placeholder structure
    %{
      total_bux_earned: 0,
      articles_read: 0,
      days_active: 0,
      top_hub: nil
    }
  end
end
