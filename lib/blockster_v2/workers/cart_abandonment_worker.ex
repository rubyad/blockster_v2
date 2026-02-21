defmodule BlocksterV2.Workers.CartAbandonmentWorker do
  @moduledoc """
  Sends cart abandonment emails to users with idle carts.
  Scheduled via Oban cron every 30 minutes.
  Targets carts that have been idle for >2 hours.
  """

  use Oban.Worker, queue: :email_transactional, max_attempts: 3

  alias BlocksterV2.{Notifications, Repo, Mailer}
  alias BlocksterV2.Notifications.{RateLimiter, EmailBuilder}
  import Ecto.Query

  @idle_hours 2

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id}}) do
    send_cart_reminder(user_id)
  end

  def perform(%Oban.Job{args: _args}) do
    # Find users with abandoned carts
    users = get_users_with_abandoned_carts()

    Enum.each(users, fn user_id ->
      # Check we haven't already sent a cart abandonment email recently
      unless recently_notified?(user_id) do
        %{user_id: user_id}
        |> __MODULE__.new()
        |> Oban.insert()
      end
    end)

    :ok
  end

  defp send_cart_reminder(user_id) do
    case RateLimiter.can_send?(user_id, :email, "cart_abandonment") do
      :ok ->
        user = Repo.get(BlocksterV2.Accounts.User, user_id)

        if user && user.email do
          prefs = Notifications.get_preferences(user_id)
          token = if prefs, do: prefs.unsubscribe_token, else: ""

          items = get_cart_items(user_id)

          if items != [] do
            email =
              EmailBuilder.promotional(
                user.email,
                user.username || user.email,
                token,
                %{
                  title: "You left something in your cart",
                  body: "Your cart is waiting! Complete your order before items sell out.",
                  action_url: "https://blockster-v2.fly.dev/cart",
                  action_label: "Complete Order"
                }
              )

            case Mailer.deliver(email) do
              {:ok, _} ->
                Notifications.create_email_log(%{
                  user_id: user_id,
                  email_type: "cart_abandonment",
                  subject: email.subject,
                  sent_at: DateTime.utc_now() |> DateTime.truncate(:second)
                })

                # Also send in-app notification
                Notifications.create_notification(user_id, %{
                  type: "cart_abandonment",
                  category: "offers",
                  title: "You left something in your cart",
                  body: "Complete your order before items sell out.",
                  action_url: "/cart",
                  action_label: "View Cart"
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

      _other ->
        :ok
    end
  end

  defp get_users_with_abandoned_carts do
    cutoff = DateTime.utc_now() |> DateTime.add(-@idle_hours * 3600, :second)

    # Find carts with items that haven't been updated recently
    try do
      from(c in BlocksterV2.Cart.Cart,
        join: ci in BlocksterV2.Cart.CartItem,
        on: ci.cart_id == c.id,
        where: c.updated_at < ^cutoff,
        distinct: c.user_id,
        select: c.user_id
      )
      |> Repo.all()
    rescue
      _ -> []
    end
  end

  defp get_cart_items(user_id) do
    try do
      from(ci in BlocksterV2.Cart.CartItem,
        join: c in BlocksterV2.Cart.Cart,
        on: ci.cart_id == c.id,
        join: p in BlocksterV2.Shop.Product,
        on: ci.product_id == p.id,
        where: c.user_id == ^user_id,
        select: %{title: p.title, quantity: ci.quantity}
      )
      |> Repo.all()
    rescue
      _ -> []
    end
  end

  defp recently_notified?(user_id) do
    cutoff = DateTime.utc_now() |> DateTime.add(-24 * 3600, :second)

    from(el in BlocksterV2.Notifications.EmailLog,
      where: el.user_id == ^user_id,
      where: el.email_type == "cart_abandonment",
      where: el.sent_at > ^cutoff
    )
    |> Repo.exists?()
  rescue
    _ -> false
  end
end
