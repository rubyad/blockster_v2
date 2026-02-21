defmodule BlocksterV2Web.SendgridWebhookController do
  @moduledoc """
  Handles SendGrid Event Webhook callbacks.
  Processes email events: open, click, bounce, spam_report, unsubscribe.
  Updates email_log records and auto-suppresses bad addresses.
  """

  use BlocksterV2Web, :controller

  alias BlocksterV2.{Notifications, Repo}
  alias BlocksterV2.Notifications.{EmailLog, NotificationPreference}
  import Ecto.Query

  require Logger

  @doc """
  Handle incoming SendGrid event webhook.
  SendGrid sends an array of event objects as JSON.
  """
  def handle(conn, %{"_json" => events}) when is_list(events) do
    Enum.each(events, &process_event/1)

    conn
    |> put_status(200)
    |> json(%{status: "ok", processed: length(events)})
  end

  def handle(conn, params) when is_list(params) do
    # SendGrid sometimes sends raw array
    Enum.each(params, &process_event/1)

    conn
    |> put_status(200)
    |> json(%{status: "ok", processed: length(params)})
  end

  def handle(conn, _params) do
    conn
    |> put_status(200)
    |> json(%{status: "ok", processed: 0})
  end

  defp process_event(%{"event" => event_type} = event) do
    sg_message_id = extract_message_id(event["sg_message_id"])

    case event_type do
      "open" -> handle_open(sg_message_id, event)
      "click" -> handle_click(sg_message_id, event)
      "bounce" -> handle_bounce(sg_message_id, event)
      "spam_report" -> handle_spam_report(sg_message_id, event)
      "unsubscribe" -> handle_unsubscribe(sg_message_id, event)
      "dropped" -> handle_bounce(sg_message_id, event)
      _ -> :ok
    end
  end

  defp process_event(_), do: :ok

  defp handle_open(nil, _), do: :ok
  defp handle_open(sg_message_id, event) do
    now = event_timestamp(event)

    case find_email_log(sg_message_id) do
      nil -> :ok
      log ->
        # Only set opened_at if not already set (first open)
        if is_nil(log.opened_at) do
          log
          |> Ecto.Changeset.change(%{opened_at: now})
          |> Repo.update()

          # Increment campaign stats if linked
          if log.campaign_id do
            increment_campaign_stat(log.campaign_id, :emails_opened)
          end
        end
    end
  end

  defp handle_click(nil, _), do: :ok
  defp handle_click(sg_message_id, event) do
    now = event_timestamp(event)

    case find_email_log(sg_message_id) do
      nil -> :ok
      log ->
        changes = %{clicked_at: now}
        # Also mark as opened if not yet
        changes = if is_nil(log.opened_at), do: Map.put(changes, :opened_at, now), else: changes

        log
        |> Ecto.Changeset.change(changes)
        |> Repo.update()

        if log.campaign_id do
          increment_campaign_stat(log.campaign_id, :emails_clicked)
          # Also increment opened if we just set it
          if is_nil(log.opened_at) do
            increment_campaign_stat(log.campaign_id, :emails_opened)
          end
        end
    end
  end

  defp handle_bounce(nil, _), do: :ok
  defp handle_bounce(sg_message_id, _event) do
    case find_email_log(sg_message_id) do
      nil -> :ok
      log ->
        log
        |> Ecto.Changeset.change(%{bounced: true})
        |> Repo.update()

        # Auto-suppress: disable email for this user
        if log.user_id do
          suppress_user_email(log.user_id, :bounce)
        end
    end
  end

  defp handle_spam_report(nil, _), do: :ok
  defp handle_spam_report(sg_message_id, _event) do
    case find_email_log(sg_message_id) do
      nil -> :ok
      log ->
        log
        |> Ecto.Changeset.change(%{bounced: true, unsubscribed: true})
        |> Repo.update()

        # Auto-unsubscribe from ALL marketing on spam report
        if log.user_id do
          suppress_user_email(log.user_id, :spam)
        end
    end
  end

  defp handle_unsubscribe(nil, _), do: :ok
  defp handle_unsubscribe(sg_message_id, _event) do
    case find_email_log(sg_message_id) do
      nil -> :ok
      log ->
        log
        |> Ecto.Changeset.change(%{unsubscribed: true})
        |> Repo.update()

        if log.user_id do
          Notifications.update_preferences(log.user_id, %{email_enabled: false})
        end
    end
  end

  defp find_email_log(sg_message_id) when is_binary(sg_message_id) do
    Repo.one(from l in EmailLog, where: l.sendgrid_message_id == ^sg_message_id, limit: 1)
  end

  defp find_email_log(_), do: nil

  defp suppress_user_email(user_id, reason) do
    updates =
      case reason do
        :bounce -> %{email_enabled: false}
        :spam -> %{email_enabled: false, email_special_offers: false, email_daily_digest: false, email_re_engagement: false}
      end

    Notifications.update_preferences(user_id, updates)
    Logger.info("[SendGridWebhook] Suppressed email for user #{user_id} due to #{reason}")
  end

  defp increment_campaign_stat(campaign_id, field) do
    from(c in Notifications.Campaign,
      where: c.id == ^campaign_id,
      update: [inc: [{^field, 1}]]
    )
    |> Repo.update_all([])
  end

  defp event_timestamp(%{"timestamp" => ts}) when is_integer(ts) do
    DateTime.from_unix!(ts) |> DateTime.truncate(:second)
  end

  defp event_timestamp(_), do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp extract_message_id(nil), do: nil
  defp extract_message_id(id) when is_binary(id) do
    # SendGrid message IDs sometimes have ".filter..." suffix
    id |> String.split(".") |> List.first()
  end
end
