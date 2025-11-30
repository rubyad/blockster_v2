defmodule BlocksterV2Web.EventLive.Index do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.Events

  @impl true
  def mount(_params, _session, socket) do
    # Load featured event for header (first published event)
    featured_event = Events.list_published_events() |> List.first()

    # Get all published events
    all_events = Events.list_published_events()

    # Extract unique cities from events
    cities = all_events
    |> Enum.map(& &1.city)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()

    {:ok,
     socket
     |> assign(:page_title, "Events")
     |> assign(:featured_event, featured_event)
     |> assign(:cities, cities)
     |> assign(:selected_city, "All")
     |> assign(:search_query, "")
     |> assign(:view_mode, "cards")
     |> assign(:show_all_events, true)
     |> assign(:show_my_tickets, false)}
  end

  @impl true
  def handle_event("filter_city", %{"city" => city}, socket) do
    {:noreply, assign(socket, :selected_city, city)}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    {:noreply, assign(socket, :search_query, query)}
  end

  @impl true
  def handle_event("toggle_view", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, :view_mode, mode)}
  end

  @impl true
  def handle_event("navigate", %{"direction" => _direction}, socket) do
    # Placeholder for navigation logic
    {:noreply, socket}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {show_all_events, show_my_tickets} =
      case tab do
        "all_events" -> {true, false}
        "my_tickets" -> {false, true}
        _ -> {true, false}
      end

    {:noreply,
     socket
     |> assign(:show_all_events, show_all_events)
     |> assign(:show_my_tickets, show_my_tickets)}
  end
end
