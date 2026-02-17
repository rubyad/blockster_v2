defmodule BlocksterV2.Orders.Fulfillment do
  @moduledoc """
  Coordinates order fulfillment notifications.
  Runs email and Telegram notifications concurrently, then stamps the order.
  """

  require Logger

  alias BlocksterV2.{OrderMailer, TelegramNotifier, Mailer}
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
      end)
    ]

    results = Task.await_many(tasks, @timeout)

    Enum.each(results, fn
      {:ok, _} -> :ok
      {:error, {:email, e}} -> Logger.error("[Fulfillment] Email failed: #{inspect(e)}")
      {:error, {:telegram, e}} -> Logger.error("[Fulfillment] Telegram failed: #{inspect(e)}")
      {:error, :not_configured} -> Logger.warning("[Fulfillment] Telegram not configured")
      other -> Logger.warning("[Fulfillment] Unexpected result: #{inspect(other)}")
    end)

    Orders.update_order(order, %{
      fulfillment_notified_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
  end
end
