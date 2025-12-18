defmodule BlocksterV2Web.HubLive.Index do
  use BlocksterV2Web, :live_view
  import BlocksterV2Web.SharedComponents, only: [lightning_icon: 1]

  alias BlocksterV2.Blog
  alias BlocksterV2.EngagementTracker

  @impl true
  def mount(_params, _session, socket) do
    hubs = Blog.list_hubs_with_followers()

    # Subscribe to all hub BUX updates for real-time updates
    if connected?(socket) do
      EngagementTracker.subscribe_to_all_hub_bux_updates()
    end

    # Fetch BUX balances for all hubs from Mnesia
    hub_ids = Enum.map(hubs, & &1.id)
    hub_bux_balances = EngagementTracker.get_hub_bux_balances(hub_ids)

    {:ok,
     socket
     |> assign(:hubs, hubs)
     |> assign(:all_hubs, hubs)
     |> assign(:hub_bux_balances, hub_bux_balances)
     |> assign(:search_query, "")
     |> assign(:active_category, "all")
     |> assign(:page_title, "Business Hubs")}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("search", %{"value" => query}, socket) do
    filtered_hubs = filter_hubs(socket.assigns.all_hubs, query)

    {:noreply,
     socket
     |> assign(:search_query, query)
     |> assign(:hubs, filtered_hubs)}
  end

  @impl true
  def handle_event("filter_category", %{"category" => category}, socket) do
    {:noreply, assign(socket, :active_category, category)}
  end

  @impl true
  def handle_info({:hub_bux_update, hub_id, new_balance}, socket) do
    # Update the hub_bux_balances map with the new balance
    updated_balances = Map.put(socket.assigns.hub_bux_balances, hub_id, new_balance)
    {:noreply, assign(socket, :hub_bux_balances, updated_balances)}
  end

  defp filter_hubs(hubs, ""), do: hubs
  defp filter_hubs(hubs, query) do
    query = String.downcase(query)

    Enum.filter(hubs, fn hub ->
      String.contains?(String.downcase(hub.name), query) ||
        (hub.description && String.contains?(String.downcase(hub.description), query))
    end)
  end

  # Helper function to get BUX balance for a hub
  def get_hub_bux(hub_bux_balances, hub_id) do
    Map.get(hub_bux_balances, hub_id, 0)
  end
end
