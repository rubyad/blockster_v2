defmodule BlocksterV2.Workers.SmsNotificationWorker do
  @moduledoc """
  Oban worker for sending SMS notifications.
  Handles flash sales, BUX milestones, order shipped, and account security alerts.
  Respects rate limits and user preferences.
  """

  use Oban.Worker, queue: :sms, max_attempts: 3

  alias BlocksterV2.{Repo, Notifications}
  alias BlocksterV2.Notifications.{RateLimiter, SmsNotifier}
  alias BlocksterV2.Accounts.User
  import Ecto.Query

  require Logger

  @doc """
  Enqueue an SMS notification for a single user.
  sms_type: :flash_sale | :bux_milestone | :order_shipped | :account_security | :special_offer | :exclusive_drop
  data: map with message-specific fields (title, url, amount, order_ref, etc.)
  """
  def enqueue(user_id, sms_type, data \\ %{}) do
    %{user_id: user_id, sms_type: to_string(sms_type), data: data}
    |> __MODULE__.new()
    |> Oban.insert()
  end

  @doc """
  Enqueue SMS notifications for all eligible users (e.g., flash sale broadcast).
  """
  def enqueue_broadcast(sms_type, data \\ %{}) do
    eligible_users()
    |> Enum.each(fn user ->
      enqueue(user.id, sms_type, data)
    end)
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "sms_type" => sms_type, "data" => data}}) do
    user = Repo.get(User, user_id)

    cond do
      is_nil(user) ->
        Logger.warning("[SmsWorker] User #{user_id} not found, skipping")
        :ok

      !SmsNotifier.can_send_to_user?(user) ->
        Logger.info("[SmsWorker] User #{user_id} not eligible for SMS")
        :ok

      true ->
        send_sms_to_user(user, sms_type, data)
    end
  end

  defp send_sms_to_user(user, sms_type, data) do
    case RateLimiter.can_send?(user.id, :sms, sms_type) do
      :ok ->
        phone = SmsNotifier.get_user_phone(user.id)

        if phone do
          message = SmsNotifier.build_message(String.to_existing_atom(sms_type), atomize_keys(data))

          case SmsNotifier.send_sms(phone, message) do
            {:ok, _sid} ->
              log_sms_sent(user.id, sms_type)
              :ok

            {:error, :not_configured} ->
              :ok

            {:error, reason} ->
              Logger.error("[SmsWorker] Failed to send SMS to user #{user.id}: #{inspect(reason)}")
              {:error, reason}
          end
        else
          Logger.info("[SmsWorker] No phone number for user #{user.id}")
          :ok
        end

      :defer ->
        # In quiet hours — reschedule for 1 hour later
        %{user_id: user.id, sms_type: sms_type, data: data}
        |> __MODULE__.new(schedule_in: 3600)
        |> Oban.insert()

        :ok

      {:error, reason} ->
        Logger.info("[SmsWorker] Rate limited for user #{user.id}: #{inspect(reason)}")
        :ok
    end
  end

  defp log_sms_sent(user_id, sms_type) do
    Notifications.create_email_log(%{
      user_id: user_id,
      email_type: "sms",
      subject: "SMS: #{sms_type}",
      sent_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
  end

  defp eligible_users do
    from(u in User,
      where: u.phone_verified == true and u.sms_opt_in == true
    )
    |> Repo.all()
  end

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_binary(k) -> {String.to_existing_atom(k), v}
      {k, v} -> {k, v}
    end)
  rescue
    ArgumentError -> map
  end
end
