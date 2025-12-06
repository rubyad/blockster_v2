defmodule BlocksterV2Web.HubLive.Index do
  use BlocksterV2Web, :live_view
  import BlocksterV2Web.SharedComponents, only: [lightning_icon: 1]

  alias BlocksterV2.Blog

  @impl true
  def mount(_params, _session, socket) do
    hubs = Blog.list_hubs_with_followers()

    {:ok,
     socket
     |> assign(:hubs, hubs)
     |> assign(:all_hubs, hubs)
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

  defp filter_hubs(hubs, ""), do: hubs
  defp filter_hubs(hubs, query) do
    query = String.downcase(query)

    Enum.filter(hubs, fn hub ->
      String.contains?(String.downcase(hub.name), query) ||
        (hub.description && String.contains?(String.downcase(hub.description), query))
    end)
  end
end
