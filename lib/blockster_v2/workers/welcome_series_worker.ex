defmodule BlocksterV2.Workers.WelcomeSeriesWorker do
  @moduledoc """
  Sends a 4-email welcome series to new users.
  Triggered on user registration. Emails sent on days 0, 3, 5, 7.
  """

  use Oban.Worker, queue: :email_transactional, max_attempts: 3

  alias BlocksterV2.{Notifications, Repo, Mailer}
  alias BlocksterV2.Notifications.{RateLimiter, EmailBuilder}

  @schedule_days [0, 3, 5, 7]

  @doc """
  Enqueue the full welcome series for a user.
  Called from Accounts on user registration.
  """
  def enqueue_series(user_id) do
    Enum.each(@schedule_days, fn day ->
      schedule_in_seconds = day * 24 * 60 * 60

      %{user_id: user_id, day: day}
      |> __MODULE__.new(schedule_in: schedule_in_seconds)
      |> Oban.insert()
    end)
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "day" => day}}) do
    case RateLimiter.can_send?(user_id, :email, "welcome") do
      :ok -> send_welcome_email(user_id, day)
      :defer ->
        %{user_id: user_id, day: day}
        |> __MODULE__.new(schedule_in: 3600)
        |> Oban.insert()
        :ok
      {:error, _} -> :ok
    end
  end

  defp send_welcome_email(user_id, day) do
    user = Repo.get(BlocksterV2.Accounts.User, user_id)

    if user && user.email do
      prefs = Notifications.get_preferences(user_id)
      token = if prefs, do: prefs.unsubscribe_token, else: ""
      name = user.username || user.email

      email =
        case day do
          0 ->
            EmailBuilder.welcome(user.email, name, token, %{username: name})

          3 ->
            EmailBuilder.single_article(user.email, name, token, %{
              title: "You're earning BUX by reading",
              body: "Every article you read on Blockster earns you BUX tokens. The more you read, the more you earn. Check your balance and keep exploring!",
              slug: "how-it-works",
              hub_name: nil
            })

          5 ->
            EmailBuilder.single_article(user.email, name, token, %{
              title: "Discover your hubs",
              body: "Hubs are topic-focused content channels on Blockster. Follow hubs you love to get personalized content in your feed.",
              slug: "hubs",
              hub_name: nil
            })

          7 ->
            EmailBuilder.referral_prompt(user.email, name, token, %{
              referral_link: "#{base_url()}/?ref=#{user_id}",
              bux_reward: 500
            })
        end

      case Mailer.deliver(email) do
        {:ok, _} ->
          Notifications.create_email_log(%{
            user_id: user_id,
            email_type: "welcome_series_day_#{day}",
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
  end

  defp base_url, do: "https://blockster-v2.fly.dev"
end
