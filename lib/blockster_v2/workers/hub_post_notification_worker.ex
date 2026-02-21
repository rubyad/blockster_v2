defmodule BlocksterV2.Workers.HubPostNotificationWorker do
  @moduledoc """
  Sends batched hub post notification emails to followers.
  Triggered when a post is published in a hub, batches and sends after a delay.
  """

  use Oban.Worker, queue: :email_marketing, max_attempts: 3

  alias BlocksterV2.{Notifications, Blog, Repo, Mailer}
  alias BlocksterV2.Notifications.{RateLimiter, EmailBuilder}

  @doc """
  Enqueue a hub post notification job for a specific user.
  """
  def enqueue(user_id, post_id, hub_id) do
    %{user_id: user_id, post_id: post_id, hub_id: hub_id}
    |> __MODULE__.new(schedule_in: 60)
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "post_id" => post_id, "hub_id" => hub_id}}) do
    case RateLimiter.can_send?(user_id, :email, "hub_post") do
      :ok ->
        user = Repo.get(BlocksterV2.Accounts.User, user_id)

        if user && user.email do
          post = Blog.get_post(post_id)
          hub = Blog.get_hub(hub_id)

          if post && hub do
            prefs = Notifications.get_preferences(user_id)
            token = if prefs, do: prefs.unsubscribe_token, else: ""

            email =
              EmailBuilder.single_article(
                user.email,
                user.username || user.email,
                token,
                %{
                  title: post.title,
                  body: post.excerpt || "",
                  image_url: post.featured_image,
                  slug: post.slug,
                  hub_name: hub.name
                }
              )

            case Mailer.deliver(email) do
              {:ok, _} ->
                Notifications.create_email_log(%{
                  user_id: user_id,
                  email_type: "hub_post",
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
        %{user_id: user_id, post_id: post_id, hub_id: hub_id}
        |> __MODULE__.new(schedule_in: 3600)
        |> Oban.insert()
        :ok

      {:error, _} ->
        :ok
    end
  end

end
