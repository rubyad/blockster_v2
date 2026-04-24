defmodule BlocksterV2.Orders.Fulfillment do
  @moduledoc """
  Coordinates order fulfillment notifications.
  Runs email and Telegram notifications concurrently, then stamps the order.
  """

  require Logger

  alias BlocksterV2.{OrderMailer, TelegramNotifier, Mailer, Notifications}
  alias BlocksterV2.Notifications.EmailBuilder
  alias BlocksterV2.Orders

  @timeout 15_000

  def notify(order) do
    tasks = [
      Task.async(fn ->
        try do
          OrderMailer.fulfillment_notification(order) |> Mailer.deliver()
        rescue
          e -> {:error, {:email, e}}
        end
      end),
      Task.async(fn ->
        try do
          TelegramNotifier.send_order_notification(order)
        rescue
          e -> {:error, {:telegram, e}}
        end
      end),
      Task.async(fn ->
        try do
          send_customer_confirmation(order)
        rescue
          e -> {:error, {:customer_email, e}}
        end
      end)
    ]

    results = Task.await_many(tasks, @timeout)

    Enum.each(results, fn
      {:ok, _} -> :ok
      {:error, {:email, e}} -> Logger.error("[Fulfillment] Email failed: #{inspect(e)}")
      {:error, {:customer_email, e}} -> Logger.error("[Fulfillment] Customer email failed: #{inspect(e)}")
      {:error, {:telegram, e}} -> Logger.error("[Fulfillment] Telegram failed: #{inspect(e)}")
      {:error, :not_configured} -> Logger.warning("[Fulfillment] Telegram not configured")
      other -> Logger.warning("[Fulfillment] Unexpected result: #{inspect(other)}")
    end)

    Orders.update_order(order, %{
      fulfillment_notified_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
  end

  # Sends the "Thanks, your order is confirmed" email to the buyer's
  # shipping_email. Transactional — no opt-in check (opt-outs only apply
  # to marketing). Email template: EmailBuilder.order_update/4 with
  # status="confirmed".
  defp send_customer_confirmation(order) do
    cond do
      is_nil(order.shipping_email) or order.shipping_email == "" ->
        {:ok, :no_email_on_file}

      true ->
        prefs = Notifications.get_preferences(order.user_id)
        token = if prefs, do: prefs.unsubscribe_token, else: ""
        to_name = order.shipping_name || ""

        email = EmailBuilder.order_confirmed(order.shipping_email, to_name, token, order)

        case Mailer.deliver(email) do
          {:ok, _} = ok ->
            Notifications.create_email_log(%{
              user_id: order.user_id,
              email_type: "order_confirmed",
              subject: email.subject,
              sent_at: DateTime.utc_now() |> DateTime.truncate(:second)
            })

            ok

          {:error, _reason} = err ->
            err
        end
    end
  end
end
