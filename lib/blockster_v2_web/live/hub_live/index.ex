defmodule BlocksterV2Web.HubLive.Index do
  @moduledoc """
  Hubs index LiveView — redesigned per `docs/solana/hubs_index_redesign_plan.md`.

  Displays all hubs in a 4-column gradient card grid with:
  - Page hero with stats (total hubs, total articles, total BUX paid)
  - Featured hubs section (top 3 by post count)
  - Sticky search + category filter bar
  - All hubs grid (4-col on desktop)
  """

  use BlocksterV2Web, :live_view

  alias BlocksterV2.Blog

  # Number of featured hubs shown in the top section
  @featured_count 3

  # Categories for the filter chips (matching mock exactly)
  @categories [
    "All",
    "Layer 1",
    "Layer 2",
    "DeFi",
    "NFTs",
    "Wallets",
    "Exchanges",
    "Infrastructure",
    "AI × Crypto"
  ]

  @impl true
  def mount(_params, _session, socket) do
    all_hubs = Blog.list_hubs_with_followers()

    {featured, grid_hubs} = Enum.split(all_hubs, @featured_count)

    total_post_count =
      Enum.reduce(all_hubs, 0, fn hub, acc ->
        acc + if Ecto.assoc_loaded?(hub.posts), do: length(hub.posts), else: 0
      end)

    {:ok,
     socket
     |> assign(:all_hubs, all_hubs)
     |> assign(:hubs, grid_hubs)
     |> assign(:featured_hubs, featured)
     |> assign(:search_query, "")
     |> assign(:active_category, "all")
     |> assign(:total_hub_count, length(all_hubs))
     |> assign(:total_post_count, total_post_count)
     |> assign(:categories, @categories)
     |> assign(:page_title, "Hubs")}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("search", %{"value" => query}, socket) do
    # Filter from all_hubs minus featured (grid_hubs only)
    {_featured, rest} = Enum.split(socket.assigns.all_hubs, @featured_count)
    filtered_hubs = filter_hubs(rest, query)

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

  @doc false
  def compact_number(n) when is_integer(n) and n >= 1_000_000 do
    "#{Float.round(n / 1_000_000, 1)}M"
  end

  def compact_number(n) when is_integer(n) and n >= 1_000 do
    "#{Float.round(n / 1_000, 1)}k"
  end

  def compact_number(n) when is_integer(n), do: Integer.to_string(n)
  def compact_number(_), do: "0"

  @doc false
  def hub_post_count(hub) do
    if Ecto.assoc_loaded?(hub.posts), do: length(hub.posts), else: 0
  end

  @doc false
  def hub_follower_count(hub) do
    if Ecto.assoc_loaded?(hub.followers), do: length(hub.followers), else: 0
  end
end
