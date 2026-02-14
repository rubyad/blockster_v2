defmodule BlocksterV2Web.ContentAutomationLive.History do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.ContentAutomation.FeedStore

  @per_page 25

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(page_title: "Content History")
      |> assign(filter_status: "all", filter_period: "7d", page: 1)
      |> assign(entries: [], total_count: 0, summary: nil, loading: true)
      |> start_async(:load_data, fn -> load_history("all", "7d", 1) end)

    {:ok, socket}
  end

  @impl true
  def handle_async(:load_data, {:ok, data}, socket) do
    {:noreply,
     assign(socket,
       entries: data.entries,
       total_count: data.total_count,
       summary: data.summary,
       loading: false
     )}
  end

  def handle_async(:load_data, {:exit, _reason}, socket) do
    {:noreply, assign(socket, loading: false)}
  end

  @impl true
  def handle_event("filter", params, socket) do
    status = params["status"] || socket.assigns.filter_status
    period = params["period"] || socket.assigns.filter_period

    socket =
      socket
      |> assign(filter_status: status, filter_period: period, page: 1, loading: true)
      |> start_async(:load_data, fn -> load_history(status, period, 1) end)

    {:noreply, socket}
  end

  def handle_event("load_page", %{"page" => page}, socket) do
    page = String.to_integer(page)

    socket =
      socket
      |> assign(page: page, loading: true)
      |> start_async(:load_data, fn ->
        load_history(socket.assigns.filter_status, socket.assigns.filter_period, page)
      end)

    {:noreply, socket}
  end

  defp load_history(status, period, page) do
    since = period_to_datetime(period)

    status_filter =
      case status do
        "all" -> ["published", "rejected"]
        s -> s
      end

    entries = FeedStore.get_queue_entries(
      status: status_filter,
      since: since,
      page: page,
      per_page: @per_page,
      order: :newest
    )

    total_count = FeedStore.count_queue_entries(
      status: status_filter,
      since: since
    )

    summary = FeedStore.get_history_summary(since)

    %{entries: entries, total_count: total_count, summary: summary}
  end

  defp period_to_datetime("24h"), do: DateTime.utc_now() |> DateTime.add(-86400, :second)
  defp period_to_datetime("7d"), do: DateTime.utc_now() |> DateTime.add(-7 * 86400, :second)
  defp period_to_datetime("30d"), do: DateTime.utc_now() |> DateTime.add(-30 * 86400, :second)
  defp period_to_datetime(_), do: DateTime.utc_now() |> DateTime.add(-7 * 86400, :second)

  defp total_pages(total_count) do
    max(1, ceil(total_count / @per_page))
  end

  defp time_ago(nil), do: ""
  defp time_ago(%NaiveDateTime{} = dt), do: time_ago(DateTime.from_naive!(dt, "Etc/UTC"))
  defp time_ago(datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)
    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86400)}d ago"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="pt-24 px-4 md:px-8 max-w-7xl mx-auto pb-8">
      <%!-- Header --%>
      <div class="flex items-center justify-between mb-6">
        <div>
          <h1 class="text-2xl font-haas_medium_65 text-gray-900">Content History</h1>
          <p class="text-gray-500 text-sm mt-1">Published and rejected articles</p>
        </div>
        <.link navigate={~p"/admin/content"} class="px-4 py-2 bg-gray-100 text-gray-700 rounded-lg text-sm hover:bg-gray-200 cursor-pointer">
          &larr; Dashboard
        </.link>
      </div>

      <%!-- Summary Cards --%>
      <%= if @summary do %>
        <div class="grid grid-cols-3 gap-4 mb-6">
          <div class="bg-white rounded-lg shadow p-4">
            <p class="text-gray-500 text-xs uppercase tracking-wider">Published</p>
            <p class="text-2xl font-haas_medium_65 text-green-600 mt-1"><%= @summary.published %></p>
          </div>
          <div class="bg-white rounded-lg shadow p-4">
            <p class="text-gray-500 text-xs uppercase tracking-wider">Rejected</p>
            <p class="text-2xl font-haas_medium_65 text-red-600 mt-1"><%= @summary.rejected %></p>
          </div>
          <div class="bg-white rounded-lg shadow p-4">
            <p class="text-gray-500 text-xs uppercase tracking-wider">Top Category</p>
            <p class="text-2xl font-haas_medium_65 text-gray-900 mt-1"><%= (@summary.top_category || "—") |> String.replace("_", " ") |> String.capitalize() %></p>
          </div>
        </div>
      <% end %>

      <%!-- Filters --%>
      <div class="flex items-center gap-4 mb-6">
        <select phx-change="filter" name="status" class="bg-white border border-gray-300 text-gray-700 rounded-lg px-3 py-2 text-sm cursor-pointer">
          <option value="all" selected={@filter_status == "all"}>All</option>
          <option value="published" selected={@filter_status == "published"}>Published</option>
          <option value="rejected" selected={@filter_status == "rejected"}>Rejected</option>
        </select>
        <select phx-change="filter" name="period" class="bg-white border border-gray-300 text-gray-700 rounded-lg px-3 py-2 text-sm cursor-pointer">
          <option value="24h" selected={@filter_period == "24h"}>Last 24 Hours</option>
          <option value="7d" selected={@filter_period == "7d"}>Last 7 Days</option>
          <option value="30d" selected={@filter_period == "30d"}>Last 30 Days</option>
        </select>
        <span class="text-gray-500 text-sm"><%= @total_count %> results</span>
      </div>

      <%!-- Table --%>
      <%= if @loading do %>
        <div class="bg-white rounded-lg shadow p-8 text-center">
          <p class="text-gray-500 animate-pulse">Loading...</p>
        </div>
      <% else %>
        <%= if @entries == [] do %>
          <div class="bg-white rounded-lg shadow p-8 text-center">
            <p class="text-gray-500">No articles found for this period</p>
          </div>
        <% else %>
          <div class="bg-white rounded-lg shadow overflow-hidden">
            <table class="w-full">
              <thead>
                <tr class="border-b border-gray-200">
                  <th class="text-left text-xs text-gray-500 uppercase tracking-wider px-4 py-3">Status</th>
                  <th class="text-left text-xs text-gray-500 uppercase tracking-wider px-4 py-3">Title</th>
                  <th class="text-left text-xs text-gray-500 uppercase tracking-wider px-4 py-3">Author</th>
                  <th class="text-left text-xs text-gray-500 uppercase tracking-wider px-4 py-3">Category</th>
                  <th class="text-left text-xs text-gray-500 uppercase tracking-wider px-4 py-3">When</th>
                </tr>
              </thead>
              <tbody>
                <%= for entry <- @entries do %>
                  <tr class="border-b border-gray-100 hover:bg-gray-50">
                    <td class="px-4 py-3">
                      <span class={"inline-block px-2 py-0.5 rounded text-xs font-medium #{if entry.status == "published", do: "bg-green-100 text-green-700", else: "bg-red-100 text-red-700"}"}>
                        <%= String.capitalize(entry.status) %>
                      </span>
                    </td>
                    <td class="px-4 py-3">
                      <p class="text-gray-900 text-sm truncate max-w-md"><%= entry.article_data["title"] %></p>
                    </td>
                    <td class="px-4 py-3 text-gray-500 text-sm">
                      <%= entry.article_data["author_username"] || "Unknown" %>
                    </td>
                    <td class="px-4 py-3 text-gray-500 text-sm">
                      <%= (entry.article_data["category"] || "") |> String.replace("_", " ") |> String.capitalize() %>
                    </td>
                    <td class="px-4 py-3 text-gray-500 text-sm">
                      <%= time_ago(entry.updated_at) %>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>

          <%!-- Pagination --%>
          <%= if total_pages(@total_count) > 1 do %>
            <div class="flex items-center justify-center gap-2 mt-6">
              <%= for p <- 1..total_pages(@total_count) do %>
                <button
                  phx-click="load_page"
                  phx-value-page={p}
                  class={"px-3 py-1.5 rounded text-sm cursor-pointer #{if p == @page, do: "bg-blue-600 text-white font-medium", else: "bg-gray-100 text-gray-700 hover:bg-gray-200"}"}
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
end
