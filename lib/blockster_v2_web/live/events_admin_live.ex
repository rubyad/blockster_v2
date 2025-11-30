defmodule BlocksterV2Web.EventsAdminLive do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.Events
  alias BlocksterV2.Blog
  alias BlocksterV2.Repo

  @impl true
  def mount(_params, _session, socket) do
    # Check if user is admin
    if socket.assigns.current_user && socket.assigns.current_user.is_admin do
      events = Events.list_all_events() |> Repo.preload([:organizer, :hub, :tags])
      hubs = Blog.list_hubs()
      tags = Blog.list_tags()

      {:ok,
       socket
       |> assign(:events, events)
       |> assign(:hubs, hubs)
       |> assign(:tags, tags)
       |> assign(:page_title, "Manage Events")}
    else
      {:ok,
       socket
       |> put_flash(:error, "You must be an admin to access this page.")
       |> redirect(to: ~p"/")}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    event = Events.get_event!(id)
    {:ok, _} = Events.delete_event(event)

    events = Events.list_all_events() |> Repo.preload([:organizer, :hub, :tags])

    {:noreply,
     socket
     |> assign(:events, events)
     |> put_flash(:info, "Event deleted successfully.")}
  end

  @impl true
  def handle_event("toggle_status", %{"id" => id}, socket) do
    event = Events.get_event!(id)

    new_status =
      case event.status do
        "published" -> "draft"
        "draft" -> "published"
        _ -> "published"
      end

    case Events.update_event(event, %{status: new_status}) do
      {:ok, _updated_event} ->
        events = Events.list_all_events() |> Repo.preload([:organizer, :hub, :tags])

        {:noreply,
         socket
         |> assign(:events, events)
         |> put_flash(:info, "Event status updated successfully.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update event status.")}
    end
  end

  defp format_date(nil), do: "N/A"

  defp format_date(date) do
    Calendar.strftime(date, "%b %d, %Y")
  end

  defp format_price(nil), do: "Free"

  defp format_price(price) do
    case Decimal.to_float(price) do
      0.0 -> "Free"
      amount -> "$#{:erlang.float_to_binary(amount, decimals: 2)}"
    end
  end

  defp status_badge(status) do
    case status do
      "published" ->
        assigns = %{}

        ~H"""
        <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800">
          Published
        </span>
        """

      "cancelled" ->
        assigns = %{}

        ~H"""
        <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-red-100 text-red-800">
          Cancelled
        </span>
        """

      _ ->
        assigns = %{}

        ~H"""
        <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800">
          Draft
        </span>
        """
    end
  end
end
