defmodule BlocksterV2Web.ContentAutomationLive.Feeds do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.ContentAutomation.{FeedConfig, FeedPoller, FeedStore, Settings}

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(page_title: "Feed Management")
      |> assign(feeds: [], feed_stats: %{}, disabled_feeds: [], loading: true)
      |> assign(feed_items: [], total_items: 0, filter_source: nil, items_page: 1)
      |> start_async(:load_data, fn -> load_feed_data() end)

    {:ok, socket}
  end

  @impl true
  def handle_async(:load_data, {:ok, data}, socket) do
    {:noreply,
     assign(socket,
       feeds: data.feeds,
       feed_stats: data.feed_stats,
       disabled_feeds: data.disabled_feeds,
       feed_items: data.feed_items,
       total_items: data.total_items,
       loading: false
     )}
  end

  def handle_async(:load_data, {:exit, _reason}, socket) do
    {:noreply, assign(socket, loading: false)}
  end

  @impl true
  def handle_event("toggle_feed", %{"source" => source}, socket) do
    disabled = socket.assigns.disabled_feeds

    new_disabled =
      if source in disabled do
        List.delete(disabled, source)
      else
        [source | disabled]
      end

    Settings.set(:disabled_feeds, new_disabled)
    {:noreply, assign(socket, disabled_feeds: new_disabled)}
  end

  def handle_event("force_poll", _params, socket) do
    case FeedPoller.force_poll() do
      :ok ->
        {:noreply, put_flash(socket, :info, "Feed poll triggered")}

      {:error, :not_running} ->
        {:noreply, put_flash(socket, :error, "Pipeline not enabled (set CONTENT_AUTOMATION_ENABLED=true)")}
    end
  end

  def handle_event("filter_source", %{"source" => source}, socket) do
    source = if source == "", do: nil, else: source
    items = FeedStore.get_recent_feed_items(source: source, page: 1)
    total = FeedStore.count_feed_items(source: source)
    {:noreply, assign(socket, feed_items: items, total_items: total, filter_source: source, items_page: 1)}
  end

  def handle_event("items_page", %{"page" => page}, socket) do
    page = String.to_integer(page)
    items = FeedStore.get_recent_feed_items(source: socket.assigns.filter_source, page: page)
    {:noreply, assign(socket, feed_items: items, items_page: page)}
  end

  defp load_feed_data do
    feed_items = FeedStore.get_recent_feed_items()
    total_items = FeedStore.count_feed_items()

    %{
      feeds: FeedConfig.all_feeds(),
      feed_stats: FeedStore.get_feed_item_counts_by_source(),
      disabled_feeds: Settings.get(:disabled_feeds, []),
      feed_items: feed_items,
      total_items: total_items
    }
  end

  defp feed_active?(feed, disabled_feeds) do
    feed.status == :active and feed.source not in disabled_feeds
  end

  defp format_time(nil), do: "—"
  defp format_time(dt) do
    Calendar.strftime(dt, "%b %d, %H:%M")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="pt-24 px-4 md:px-8 max-w-7xl mx-auto pb-8">
      <%!-- Header --%>
      <div class="flex items-center justify-between mb-6">
        <div>
          <h1 class="text-2xl font-haas_medium_65 text-gray-900">Feed Management</h1>
          <p class="text-gray-500 text-sm mt-1"><%= length(@feeds) %> configured feeds</p>
        </div>
        <div class="flex items-center gap-3">
          <button phx-click="force_poll" class="px-4 py-2 bg-[#CAFC00] text-black rounded-lg text-sm font-medium cursor-pointer hover:bg-[#b8e600]">
            Force Poll Now
          </button>
          <.link navigate={~p"/admin/content"} class="px-4 py-2 bg-gray-100 text-gray-700 rounded-lg text-sm hover:bg-gray-200 cursor-pointer">
            &larr; Dashboard
          </.link>
        </div>
      </div>

      <%= if @loading do %>
        <div class="bg-white rounded-lg shadow p-8 text-center">
          <p class="text-gray-500 animate-pulse">Loading feeds...</p>
        </div>
      <% else %>
        <%!-- Premium Feeds --%>
        <h2 class="text-lg font-haas_medium_65 text-gray-900 mb-3">Premium Tier (2x weight)</h2>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-3 mb-8">
          <%= for feed <- Enum.filter(@feeds, &(&1.tier == :premium)) do %>
            <.feed_card feed={feed} stats={@feed_stats} disabled_feeds={@disabled_feeds} />
          <% end %>
        </div>

        <%!-- Standard Feeds --%>
        <h2 class="text-lg font-haas_medium_65 text-gray-900 mb-3">Standard Tier</h2>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-3 mb-8">
          <%= for feed <- Enum.filter(@feeds, &(&1.tier == :standard)) do %>
            <.feed_card feed={feed} stats={@feed_stats} disabled_feeds={@disabled_feeds} />
          <% end %>
        </div>

        <%!-- Feed Items Table --%>
        <div class="flex items-center justify-between mb-3">
          <h2 class="text-lg font-haas_medium_65 text-gray-900">
            Feed Items
            <span class="text-gray-400 text-sm font-normal">(<%= @total_items %> total)</span>
          </h2>
          <form phx-change="filter_source">
            <select name="source" class="text-sm border border-gray-300 rounded-lg px-3 py-1.5 text-gray-700 bg-white cursor-pointer">
              <option value="">All Sources</option>
              <%= for {source, _count} <- Enum.sort(@feed_stats) do %>
                <option value={source} selected={@filter_source == source}><%= source %></option>
              <% end %>
            </select>
          </form>
        </div>

        <%= if @feed_items == [] do %>
          <div class="bg-white rounded-lg shadow p-8 text-center">
            <p class="text-gray-500">No feed items yet. Try clicking "Force Poll Now" above.</p>
          </div>
        <% else %>
          <div class="bg-white rounded-lg shadow overflow-hidden">
            <table class="w-full">
              <thead>
                <tr class="border-b border-gray-200">
                  <th class="text-left text-xs text-gray-500 uppercase tracking-wider px-4 py-3">Title</th>
                  <th class="text-left text-xs text-gray-500 uppercase tracking-wider px-4 py-3">Source</th>
                  <th class="text-left text-xs text-gray-500 uppercase tracking-wider px-4 py-3">Fetched</th>
                  <th class="text-center text-xs text-gray-500 uppercase tracking-wider px-4 py-3">Processed</th>
                </tr>
              </thead>
              <tbody>
                <%= for item <- @feed_items do %>
                  <tr class="border-b border-gray-100 hover:bg-gray-50">
                    <td class="px-4 py-2.5 max-w-md">
                      <a href={item.url} target="_blank" class="text-gray-900 text-sm hover:text-blue-600 line-clamp-1"><%= item.title %></a>
                    </td>
                    <td class="px-4 py-2.5">
                      <span class="text-gray-600 text-xs"><%= item.source %></span>
                    </td>
                    <td class="px-4 py-2.5">
                      <span class="text-gray-500 text-xs"><%= format_time(item.fetched_at) %></span>
                    </td>
                    <td class="px-4 py-2.5 text-center">
                      <%= if item.processed do %>
                        <span class="px-1.5 py-0.5 bg-green-100 text-green-700 rounded text-xs">Yes</span>
                      <% else %>
                        <span class="px-1.5 py-0.5 bg-gray-100 text-gray-500 rounded text-xs">No</span>
                      <% end %>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>

          <%!-- Pagination --%>
          <% total_pages = max(ceil(@total_items / 50), 1) %>
          <%= if total_pages > 1 do %>
            <div class="flex justify-center gap-2 mt-4">
              <%= for p <- max(@items_page - 2, 1)..min(@items_page + 2, total_pages) do %>
                <button
                  phx-click="items_page"
                  phx-value-page={p}
                  class={"px-3 py-1 rounded text-sm cursor-pointer #{if p == @items_page, do: "bg-blue-600 text-white", else: "bg-gray-100 text-gray-700 hover:bg-gray-200"}"}
                >
                  <%= p %>
                </button>
              <% end %>
            </div>
          <% end %>
        <% end %>
      <% end %>
    </div>
    """
  end

  defp feed_card(assigns) do
    active = feed_active?(assigns.feed, assigns.disabled_feeds)
    blocked = assigns.feed.status == :blocked
    items_24h = Map.get(assigns.stats, assigns.feed.source, 0)

    assigns = assign(assigns, active: active, blocked: blocked, items_24h: items_24h)

    ~H"""
    <div class={"bg-white rounded-lg shadow p-4 flex items-center justify-between #{if @blocked, do: "opacity-50", else: if(!@active, do: "ring-1 ring-red-200", else: "")}"}>
      <div class="min-w-0">
        <div class="flex items-center gap-2">
          <h3 class="text-gray-900 text-sm font-medium"><%= @feed.source %></h3>
          <%= if @blocked do %>
            <span class="px-1.5 py-0.5 bg-gray-100 text-gray-500 rounded text-xs">Blocked</span>
          <% end %>
          <%= if !@active and !@blocked do %>
            <span class="px-1.5 py-0.5 bg-red-100 text-red-600 rounded text-xs">Disabled</span>
          <% end %>
        </div>
        <p class="text-gray-400 text-xs mt-1 truncate"><%= @feed.url %></p>
        <p class="text-gray-500 text-xs mt-1"><%= @items_24h %> items (24h)</p>
      </div>

      <%= unless @blocked do %>
        <button
          phx-click="toggle_feed"
          phx-value-source={@feed.source}
          class={"relative inline-flex h-6 w-11 items-center rounded-full cursor-pointer transition-colors #{if @active, do: "bg-green-500", else: "bg-gray-300"}"}
        >
          <span class={"inline-block h-4 w-4 transform rounded-full bg-white transition-transform #{if @active, do: "translate-x-6", else: "translate-x-1"}"}></span>
        </button>
      <% end %>
    </div>
    """
  end
end
