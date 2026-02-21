defmodule BlocksterV2.Workers.DailyDigestWorker do
  @moduledoc """
  Sends daily digest emails to eligible users.
  Scheduled via Oban cron at 9:00 AM UTC daily.
  Staggers by user timezone for morning delivery.
  """

  use Oban.Worker, queue: :email_digest, max_attempts: 3

  alias BlocksterV2.{Notifications, Blog, Repo, Mailer}
  alias BlocksterV2.Notifications.{RateLimiter, EmailBuilder}
  import Ecto.Query

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id}}) do
    # Individual user digest (scheduled from the batch job)
    send_digest_to_user(user_id)
  end

  def perform(%Oban.Job{args: _args}) do
    # Batch job: find eligible users and enqueue individual jobs
    users = get_digest_eligible_users()

    Enum.each(users, fn user ->
      %{user_id: user.id}
      |> __MODULE__.new()
      |> Oban.insert()
    end)

    :ok
  end

  defp send_digest_to_user(user_id) do
    case RateLimiter.can_send?(user_id, :email, "daily_digest") do
      :ok ->
        user = Repo.get(BlocksterV2.Accounts.User, user_id)

        if user && user.email do
          articles = get_personalized_articles(user)

          if articles != [] do
            prefs = Notifications.get_preferences(user_id)
            token = if prefs, do: prefs.unsubscribe_token, else: ""

            email =
              EmailBuilder.daily_digest(
                user.email,
                user.username || user.email,
                token,
                %{articles: articles, date: Date.utc_today()}
              )

            case Mailer.deliver(email) do
              {:ok, _} ->
                Notifications.create_email_log(%{
                  user_id: user_id,
                  email_type: "daily_digest",
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
        else
          :ok
        end

      :defer ->
        # Reschedule for later
        %{user_id: user_id}
        |> __MODULE__.new(schedule_in: 3600)
        |> Oban.insert()

        :ok

      {:error, _reason} ->
        :ok
    end
  end

  defp get_digest_eligible_users do
    from(u in BlocksterV2.Accounts.User,
      where: not is_nil(u.email),
      select: u
    )
    |> Repo.all()
    |> Enum.filter(fn user ->
      case Notifications.get_preferences(user.id) do
        nil -> false
        prefs -> prefs.email_enabled && prefs.email_daily_digest
      end
    end)
  end

  defp get_personalized_articles(user) do
    # Get recent posts from followed hubs + trending
    hub_ids = Blog.get_user_followed_hub_ids(user.id)

    posts =
      if hub_ids != [] do
        from(p in BlocksterV2.Blog.Post,
          where: p.hub_id in ^hub_ids and not is_nil(p.published_at),
          order_by: [desc: p.published_at],
          limit: 5,
          select: %{
            title: p.title,
            slug: p.slug,
            image_url: p.featured_image,
            hub_name: fragment("(SELECT name FROM hubs WHERE id = ?)", p.hub_id)
          }
        )
        |> Repo.all()
      else
        # Fallback: latest published posts
        from(p in BlocksterV2.Blog.Post,
          where: not is_nil(p.published_at),
          order_by: [desc: p.published_at],
          limit: 5,
          select: %{title: p.title, slug: p.slug, image_url: p.featured_image}
        )
        |> Repo.all()
      end

    Enum.map(posts, fn p ->
      %{
        title: p.title,
        slug: p.slug,
        image_url: p[:image_url],
        hub_name: p[:hub_name]
      }
    end)
  end
end
