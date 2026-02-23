defmodule BlocksterV2Web.NotificationHook do
  @moduledoc """
  LiveView on_mount hook for real-time notification delivery.

  - Fetches unread notification count asynchronously on mount
  - Subscribes to PubSub for real-time notification updates
  - Manages notification dropdown state and recent notifications list
  - Handles toast notifications for new incoming notifications
  - Handles notification UI events (toggle dropdown, mark read, click, dismiss toast)
  """
  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 3, update: 3]
  alias BlocksterV2.Notifications

  @pubsub BlocksterV2.PubSub
  @topic_prefix "notifications:"

  def on_mount(:default, _params, _session, socket) do
    user_id = get_user_id(socket)

    socket =
      socket
      |> assign(:unread_notification_count, 0)
      |> assign(:notification_dropdown_open, false)
      |> assign(:recent_notifications, [])
      |> assign(:toast_notification, nil)
      |> attach_hook(:notification_handler, :handle_info, &handle_notification_info/2)
      |> attach_hook(:notification_events, :handle_event, &handle_notification_event/3)

    # Fetch notifications async only when connected (skip static render)
    if connected?(socket) && user_id do
      Phoenix.PubSub.subscribe(@pubsub, "#{@topic_prefix}#{user_id}")

      pid = self()

      Task.start(fn ->
        count = Notifications.unread_count(user_id)
        recent = Notifications.list_recent_notifications(user_id, 10)
        send(pid, {:notification_data_loaded, count, recent})
      end)
    end

    {:cont, socket}
  end

  # ============ Handle Info (PubSub + async load) ============

  defp handle_notification_info({:notification_data_loaded, count, recent}, socket) do
    {:halt,
     socket
     |> assign(:unread_notification_count, count)
     |> assign(:recent_notifications, recent)}
  end

  defp handle_notification_info({:new_notification, notification}, socket) do
    {:halt,
     socket
     |> update(:unread_notification_count, &(&1 + 1))
     |> assign(:toast_notification, notification)
     |> update(:recent_notifications, &[notification | Enum.take(&1, 9)])}
  end

  defp handle_notification_info({:notification_count_updated, count}, socket) do
    {:halt, assign(socket, :unread_notification_count, count)}
  end

  defp handle_notification_info(_other, socket), do: {:cont, socket}

  # ============ Handle Events (UI) ============

  defp handle_notification_event("toggle_notification_dropdown", _params, socket) do
    new_state = !socket.assigns.notification_dropdown_open

    socket =
      if new_state do
        # Refresh recent notifications when opening
        user_id = get_user_id(socket)

        recent =
          if user_id,
            do: Notifications.list_recent_notifications(user_id, 10),
            else: []

        socket
        |> assign(:notification_dropdown_open, true)
        |> assign(:recent_notifications, recent)
      else
        assign(socket, :notification_dropdown_open, false)
      end

    {:halt, socket}
  end

  defp handle_notification_event("close_notification_dropdown", _params, socket) do
    {:halt, assign(socket, :notification_dropdown_open, false)}
  end

  defp handle_notification_event("mark_all_notifications_read", _params, socket) do
    user_id = get_user_id(socket)

    if user_id do
      Notifications.mark_all_as_read(user_id)

      # Refresh recent notifications to reflect read state
      recent = Notifications.list_recent_notifications(user_id, 10)

      {:halt,
       socket
       |> assign(:unread_notification_count, 0)
       |> assign(:recent_notifications, recent)}
    else
      {:halt, socket}
    end
  end

  defp handle_notification_event("click_notification", params, socket) do
    notification_id = params["id"]
    action_url = params["url"]

    if notification_id do
      Notifications.mark_as_clicked(String.to_integer(notification_id))
    end

    socket = assign(socket, :notification_dropdown_open, false)

    if action_url && action_url != "" do
      if String.starts_with?(action_url, "http") do
        {:halt, push_event(socket, "open_external_url", %{url: action_url})}
      else
        {:halt, push_navigate(socket, to: action_url)}
      end
    else
      {:halt, socket}
    end
  end

  defp handle_notification_event("dismiss_toast", _params, socket) do
    {:halt, assign(socket, :toast_notification, nil)}
  end

  defp handle_notification_event(_event, _params, socket), do: {:cont, socket}

  # ============ Helpers ============

  defp get_user_id(socket) do
    case socket.assigns[:current_user] do
      nil -> nil
      user -> user.id
    end
  end
end
