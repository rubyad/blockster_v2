defmodule BlocksterV2Web.EventLive.Show do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.Events
  alias BlocksterV2.Repo

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case Events.get_event_by_slug(slug) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Event not found")
         |> redirect(to: ~p"/events")}

      event ->
        # Preload associations
        event = Repo.preload(event, [:organizer, :hub, :attendees, :tags])

        # Get Google Maps API key from config
        google_maps_api_key = Application.get_env(:blockster_v2, :google_maps_api_key)

        {:ok,
         socket
         |> assign(:page_title, event.title)
         |> assign(:event, event)
         |> assign(:show_attendees_modal, false)
         |> assign(:google_maps_api_key, google_maps_api_key)
         |> assign(:ticket_quantity, 1)}
    end
  end

  @impl true
  def handle_event("open_attendees_modal", _params, socket) do
    {:noreply, assign(socket, :show_attendees_modal, true)}
  end

  @impl true
  def handle_event("close_attendees_modal", _params, socket) do
    {:noreply, assign(socket, :show_attendees_modal, false)}
  end

  @impl true
  def handle_event("buy_ticket", _params, socket) do
    quantity = socket.assigns.ticket_quantity
    # Placeholder for ticket purchase logic
    {:noreply,
     socket
     |> put_flash(:info, "Purchasing #{quantity} ticket(s)... Functionality coming soon!")
     |> push_navigate(to: ~p"/event/#{socket.assigns.event.slug}")}
  end

  @impl true
  def handle_event("increment_quantity", _params, socket) do
    current_quantity = socket.assigns.ticket_quantity
    max_quantity = get_available_tickets(socket.assigns.event)
    new_quantity = min(current_quantity + 1, max_quantity)
    {:noreply, assign(socket, :ticket_quantity, new_quantity)}
  end

  @impl true
  def handle_event("decrement_quantity", _params, socket) do
    current_quantity = socket.assigns.ticket_quantity
    new_quantity = max(current_quantity - 1, 1)
    {:noreply, assign(socket, :ticket_quantity, new_quantity)}
  end

  @impl true
  def handle_event("update_quantity", %{"quantity" => quantity_str}, socket) do
    max_quantity = get_available_tickets(socket.assigns.event)

    new_quantity =
      case Integer.parse(quantity_str) do
        {quantity, _} when quantity >= 1 -> min(quantity, max_quantity)
        _ -> 1
      end

    {:noreply, assign(socket, :ticket_quantity, new_quantity)}
  end

  defp format_date(date) do
    case date do
      %Date{} ->
        Calendar.strftime(date, "%B %d, %Y")

      _ ->
        "TBA"
    end
  end

  defp format_time(time) do
    case time do
      %Time{} ->
        {hour, am_pm} =
          if time.hour >= 12,
            do: {if(time.hour == 12, do: 12, else: time.hour - 12), "PM"},
            else: {if(time.hour == 0, do: 12, else: time.hour), "AM"}

        "#{hour}:#{String.pad_leading(Integer.to_string(time.minute), 2, "0")} #{am_pm}"

      _ ->
        "TBA"
    end
  end

  defp format_price(price) do
    case Decimal.to_float(price) do
      0.0 -> "Free"
      amount -> "$#{:erlang.float_to_binary(amount, decimals: 2)}"
    end
  end

  defp get_attendee_count(event) do
    length(event.attendees || [])
  end

  defp get_event_image(event) do
    # For now, use a default image
    # In the future, this could be based on event category or stored in the database
    "/images/nendorring.png"
  end

  defp get_available_tickets(event) do
    # If ticket_supply is nil, default to 100 available tickets
    # In a real app, this would also subtract the number of tickets already sold
    case event.ticket_supply do
      nil -> 100
      supply -> max(supply - get_attendee_count(event), 0)
    end
  end

  defp calculate_total_price(event, quantity) do
    Decimal.mult(event.price, Decimal.new(quantity))
  end

  defp format_total_price(total) do
    case Decimal.to_float(total) do
      0.0 -> "Free"
      amount -> "$#{:erlang.float_to_binary(amount, decimals: 2)}"
    end
  end
end
