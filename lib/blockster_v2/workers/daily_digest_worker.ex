defmodule BlocksterV2.Workers.DailyDigestWorker do
  @moduledoc """
  Sends a daily digest email with the 5 most recent posts.
  Cron-triggered batch job finds eligible users, enqueues per-user jobs.
  Deduplicates by tracking sent post IDs in email_log metadata.
  """

  use Oban.Worker, queue: :email_digest, max_attempts: 3

  alias BlocksterV2.{Blog, Notifications, Repo, Mailer}
  alias BlocksterV2.Notifications.{RateLimiter, EmailBuilder, EmailLog}
  alias BlocksterV2.Accounts.User
  import Ecto.Query

  @doc """
  Public function to manually trigger a digest batch.
  """
  def enqueue_digest do
    %{}
    |> __MODULE__.new()
    |> Oban.insert()
  end

  # ============ Batch perform (cron trigger, no user_id) ============

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "post_ids" => post_ids}}) do
    send_digest_to_user(user_id, post_ids)
  end

  def perform(%Oban.Job{args: args}) when not is_map_key(args, "user_id") do
    posts = Blog.list_published_posts_by_date(limit: 5)

    if length(posts) < 1 do
      :ok
    else
      post_ids = Enum.map(posts, & &1.id)
      eligible_users = get_eligible_users()

      Enum.each(eligible_users, fn user ->
        %{user_id: user.id, post_ids: post_ids}
        |> __MODULE__.new()
        |> Oban.insert()
      end)

      :ok
    end
  end

  # ============ Per-user send ============

  defp send_digest_to_user(user_id, post_ids) do
    case RateLimiter.can_send?(user_id, :email, "daily_digest") do
      :defer ->
        %{user_id: user_id, post_ids: post_ids}
        |> __MODULE__.new(schedule_in: 3600)
        |> Oban.insert()

        :ok

      :ok ->
        do_send(user_id, post_ids)

      {:error, _} ->
        :ok
    end
  end

  defp do_send(user_id, post_ids) do
    user = Repo.get(User, user_id)

    if user && user.email do
      # Dedup: find last digest and filter out already-sent post IDs
      last_sent_ids = get_last_digest_post_ids(user_id)
      new_post_ids = Enum.reject(post_ids, &(&1 in last_sent_ids))

      if new_post_ids == [] do
        :ok
      else
        posts = load_posts_by_ids(new_post_ids)
        prefs = Notifications.get_preferences(user_id)
        token = if prefs, do: prefs.unsubscribe_token, else: ""

        articles =
          Enum.map(posts, fn post ->
            hub_name = if post.hub, do: post.hub.name, else: nil

            image_url =
              if post.featured_image do
                "#{post.featured_image}?tr=w-200,h-200,fo-auto"
              else
                nil
              end

            %{
              title: post.title,
              slug: post.slug,
              image_url: image_url,
              hub_name: hub_name,
              excerpt: post.excerpt
            }
          end)

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
              sent_at: DateTime.utc_now() |> DateTime.truncate(:second),
              metadata: %{"post_ids" => new_post_ids}
            })

            :ok

          {:error, reason} ->
            {:error, reason}
        end
      end
    else
      :ok
    end
  end

  # ============ Helpers ============

  defp get_eligible_users do
    from(u in User, where: not is_nil(u.email))
    |> Repo.all()
    |> Enum.filter(fn user ->
      case Notifications.get_or_create_preferences(user.id) do
        {:ok, prefs} -> prefs.email_enabled && prefs.email_daily_digest
        _ -> false
      end
    end)
  end

  defp get_last_digest_post_ids(user_id) do
    case Repo.one(
           from(el in EmailLog,
             where: el.user_id == ^user_id and el.email_type == "daily_digest",
             order_by: [desc: el.sent_at],
             limit: 1
           )
         ) do
      nil -> []
      log -> Map.get(log.metadata || %{}, "post_ids", [])
    end
  end

  defp load_posts_by_ids(ids) do
    from(p in BlocksterV2.Blog.Post,
      where: p.id in ^ids,
      preload: [:hub],
      order_by: [desc: p.published_at]
    )
    |> Repo.all()
  end
end
