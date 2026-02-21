defmodule BlocksterV2.Workers.ReferralPromptWorker do
  @moduledoc """
  Sends weekly referral prompt emails.
  Scheduled via Oban cron at 2:00 PM UTC on Wednesdays.
  """

  use Oban.Worker, queue: :email_marketing, max_attempts: 3

  alias BlocksterV2.{Notifications, Repo, Mailer}
  alias BlocksterV2.Notifications.{RateLimiter, EmailBuilder}
  import Ecto.Query

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id}}) do
    send_referral_prompt(user_id)
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

  defp send_referral_prompt(user_id) do
    case RateLimiter.can_send?(user_id, :email, "referral_prompt") do
      :ok ->
        user = Repo.get(BlocksterV2.Accounts.User, user_id)

        if user && user.email do
          prefs = Notifications.get_preferences(user_id)
          token = if prefs, do: prefs.unsubscribe_token, else: ""

          email =
            EmailBuilder.referral_prompt(
              user.email,
              user.username || user.email,
              token,
              %{
                referral_link: "#{base_url()}/?ref=#{user_id}",
                bux_reward: 500
              }
            )

          case Mailer.deliver(email) do
            {:ok, _} ->
              Notifications.create_email_log(%{
                user_id: user_id,
                email_type: "referral_prompt",
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
        prefs -> prefs.email_enabled && prefs.email_referral_prompts
      end
    end)
  end

  defp base_url, do: "https://blockster-v2.fly.dev"
end
