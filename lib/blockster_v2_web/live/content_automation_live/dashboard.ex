defmodule BlocksterV2Web.ContentAutomationLive.Dashboard do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.ContentAutomation.{FeedStore, Settings, ContentPublisher, TopicEngine}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "content_automation")
    end

    data = load_dashboard_data()

    {:ok,
     assign(socket,
       page_title: "Content Automation",
       pipeline_paused: Settings.paused?(),
       target_queue_size: Settings.get(:target_queue_size, 10),
       stats: data.stats,
       recent_queue: data.recent_queue,
       activity: data.activity
     )}
  end

  @impl true
  def handle_event("toggle_pause", _params, socket) do
    new_state = !socket.assigns.pipeline_paused
    Settings.set(:paused, new_state)
    {:noreply, assign(socket, pipeline_paused: new_state)}
  end

  def handle_event("quick_approve", %{"id" => id}, socket) do
    entry = FeedStore.get_queue_entry(id) |> BlocksterV2.Repo.preload(:author)

    case ContentPublisher.publish_queue_entry(entry) do
      {:ok, post} ->
        recent_queue = Enum.reject(socket.assigns.recent_queue, &(&1.id == id))
        stats = update_in(socket.assigns.stats || %{}, [:published_today], &((&1 || 0) + 1))
        stats = update_in(stats, [:pending], &max((&1 || 1) - 1, 0))

        {:noreply,
         socket
         |> assign(recent_queue: recent_queue, stats: stats)
         |> put_flash(:info, "Published: \"#{post.title}\"")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Publish failed: #{inspect(reason)}")}
    end
  end

  def handle_event("force_analyze", _params, socket) do
    case TopicEngine.force_analyze() do
      :ok ->
        {:noreply, put_flash(socket, :info, "Analysis triggered — articles will appear shortly")}

      {:error, :not_running} ->
        {:noreply, put_flash(socket, :error, "TopicEngine is not running (CONTENT_AUTOMATION_ENABLED=false?)")}
    end
  end

  def handle_event("increase_queue_size", _params, socket) do
    new_size = min(socket.assigns.target_queue_size + 1, 50)
    Settings.set(:target_queue_size, new_size)
    {:noreply, assign(socket, target_queue_size: new_size)}
  end

  def handle_event("decrease_queue_size", _params, socket) do
    new_size = max(socket.assigns.target_queue_size - 1, 1)
    Settings.set(:target_queue_size, new_size)
    {:noreply, assign(socket, target_queue_size: new_size)}
  end

  def handle_event("reject", %{"id" => id}, socket) do
    FeedStore.reject_queue_entry(id)
    recent_queue = Enum.reject(socket.assigns.recent_queue, &(&1.id == id))
    stats = update_in(socket.assigns.stats || %{}, [:rejected_today], &((&1 || 0) + 1))
    stats = update_in(stats, [:pending], &max((&1 || 1) - 1, 0))

    {:noreply,
     socket
     |> assign(recent_queue: recent_queue, stats: stats)
     |> put_flash(:info, "Article rejected")}
  end

  # PubSub handlers — debounce rapid updates, reload data in-place (no flash)
  @impl true
  def handle_info({:content_automation, _event, _data}, socket) do
    if socket.assigns[:reload_timer] do
      {:noreply, socket}
    else
      timer = Process.send_after(self(), :debounced_reload, 3_000)
      {:noreply, assign(socket, reload_timer: timer)}
    end
  end

  def handle_info(:debounced_reload, socket) do
    data = load_dashboard_data()

    {:noreply,
     assign(socket,
       reload_timer: nil,
       target_queue_size: Settings.get(:target_queue_size, 10),
       stats: data.stats,
       recent_queue: data.recent_queue,
       activity: data.activity
     )}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  defp load_dashboard_data do
    active_feeds = FeedStore.count_active_feeds()
    total_feeds = FeedStore.count_total_feeds()

    %{
      stats: %{
        pending: FeedStore.count_queued(),
        published_today: FeedStore.count_published_today(),
        rejected_today: FeedStore.count_rejected_today(),
        feeds_active: "#{active_feeds}/#{total_feeds}"
      },
      recent_queue: FeedStore.get_queue_entries(status: ["pending", "draft", "approved"], per_page: 5),
      activity: FeedStore.get_recent_activity(20)
    }
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

  defp status_icon("published"), do: "text-green-500"
  defp status_icon("rejected"), do: "text-red-500"
  defp status_icon("pending"), do: "text-yellow-500"
  defp status_icon("draft"), do: "text-blue-500"
  defp status_icon("approved"), do: "text-emerald-500"
  defp status_icon(_), do: "text-gray-500"

  defp status_label("published"), do: "Published"
  defp status_label("rejected"), do: "Rejected"
  defp status_label("pending"), do: "Pending"
  defp status_label("draft"), do: "Draft"
  defp status_label("approved"), do: "Scheduled"
  defp status_label(_), do: "Unknown"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="pt-24 px-4 md:px-8 max-w-7xl mx-auto pb-8">
      <%!-- Header --%>
      <div class="flex items-center justify-between mb-8">
        <div>
          <h1 class="text-2xl font-haas_medium_65 text-gray-900">Content Automation</h1>
          <p class="text-gray-500 text-sm mt-1">Pipeline overview and controls</p>
        </div>
        <div class="flex items-center gap-4">
          <.link navigate={~p"/admin/content/queue"} class="px-4 py-2 bg-gray-100 text-gray-700 rounded-lg text-sm hover:bg-gray-200 cursor-pointer">
            View Queue
          </.link>
          <button phx-click="force_analyze" class="px-4 py-2 bg-blue-600 text-white rounded-lg text-sm font-medium cursor-pointer hover:bg-blue-700">
            Force Analyze
          </button>
          <button phx-click="toggle_pause" class={"px-4 py-2 rounded-lg text-sm font-medium cursor-pointer #{if @pipeline_paused, do: "bg-red-600 text-white hover:bg-red-700", else: "bg-[#CAFC00] text-black hover:bg-[#b8e600]"}"}>
            <%= if @pipeline_paused, do: "Resume Pipeline", else: "Pause Pipeline" %>
          </button>
        </div>
      </div>

      <%= if @pipeline_paused do %>
        <div class="bg-red-50 border border-red-200 rounded-lg p-4 mb-6">
          <p class="text-red-700 text-sm font-medium">Pipeline is paused. Articles will not auto-publish until resumed.</p>
        </div>
      <% end %>

      <%!-- Stat Cards --%>
      <div class="grid grid-cols-2 md:grid-cols-4 gap-4 mb-8">
        <.link navigate={~p"/admin/content/queue"} class="bg-white rounded-lg shadow p-5 hover:shadow-md cursor-pointer">
          <p class="text-gray-500 text-xs uppercase tracking-wider">Pending Review</p>
          <p class="text-3xl font-haas_medium_65 text-gray-900 mt-2"><%= @stats.pending %></p>
        </.link>
        <div class="bg-white rounded-lg shadow p-5">
          <p class="text-gray-500 text-xs uppercase tracking-wider">Published Today</p>
          <p class="text-3xl font-haas_medium_65 text-green-600 mt-2"><%= @stats.published_today %></p>
        </div>
        <div class="bg-white rounded-lg shadow p-5">
          <p class="text-gray-500 text-xs uppercase tracking-wider">Rejected Today</p>
          <p class="text-3xl font-haas_medium_65 text-red-600 mt-2"><%= @stats.rejected_today %></p>
        </div>
        <.link navigate={~p"/admin/content/feeds"} class="bg-white rounded-lg shadow p-5 hover:shadow-md cursor-pointer">
          <p class="text-gray-500 text-xs uppercase tracking-wider">Feeds Active</p>
          <p class="text-3xl font-haas_medium_65 text-gray-900 mt-2"><%= @stats.feeds_active %></p>
        </.link>
      </div>

      <%!-- Queue Size Control --%>
      <div class="bg-white rounded-lg shadow p-5 mb-6 flex items-center justify-between">
        <div>
          <p class="text-gray-900 font-haas_medium_65 text-sm">Target Queue Size</p>
          <p class="text-gray-500 text-xs mt-0.5">Articles to keep pending in the queue</p>
        </div>
        <div class="flex items-center gap-3">
          <button phx-click="decrease_queue_size" class="w-8 h-8 rounded-lg bg-gray-100 text-gray-700 hover:bg-gray-200 flex items-center justify-center text-lg font-medium cursor-pointer">
            &minus;
          </button>
          <span class="text-2xl font-haas_medium_65 text-gray-900 w-10 text-center"><%= @target_queue_size %></span>
          <button phx-click="increase_queue_size" class="w-8 h-8 rounded-lg bg-gray-100 text-gray-700 hover:bg-gray-200 flex items-center justify-center text-lg font-medium cursor-pointer">
            +
          </button>
        </div>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <%!-- Recent Queue (2/3 width) --%>
        <div class="lg:col-span-2">
          <div class="flex items-center justify-between mb-4">
            <h2 class="text-lg font-haas_medium_65 text-gray-900">Recent Queue</h2>
            <.link navigate={~p"/admin/content/queue"} class="text-sm text-blue-600 hover:underline cursor-pointer">
              View All &rarr;
            </.link>
          </div>

          <%= if @recent_queue == [] do %>
            <div class="bg-white rounded-lg shadow p-8 text-center">
              <p class="text-gray-500">No articles pending review</p>
            </div>
          <% else %>
            <div id="recent-queue" class="space-y-3" phx-update="replace">
              <%= for entry <- @recent_queue do %>
                <div id={"queue-#{entry.id}"} class="bg-white rounded-lg shadow p-4">
                  <div class="flex items-start justify-between gap-4">
                    <div class="flex-1 min-w-0">
                      <h3 class="text-gray-900 font-medium truncate"><%= entry.article_data["title"] %></h3>
                      <div class="flex items-center gap-2 mt-1 text-xs text-gray-500">
                        <span><%= entry.article_data["author_username"] || "Unknown" %></span>
                        <span>&middot;</span>
                        <span><%= entry.article_data["category"] %></span>
                        <span>&middot;</span>
                        <span><%= time_ago(entry.inserted_at) %></span>
                      </div>
                      <p class="text-gray-500 text-sm mt-2 line-clamp-2"><%= entry.article_data["excerpt"] %></p>
                    </div>
                    <div class="flex items-center gap-2 shrink-0">
                      <.link navigate={~p"/admin/content/queue/#{entry.id}/edit"} class="px-3 py-1.5 bg-gray-100 text-gray-700 rounded text-xs hover:bg-gray-200 cursor-pointer">
                        Edit
                      </.link>
                      <button phx-click="quick_approve" phx-value-id={entry.id} class="px-3 py-1.5 bg-green-600 text-white rounded text-xs hover:bg-green-700 cursor-pointer">
                        Publish Now
                      </button>
                      <button phx-click="reject" phx-value-id={entry.id} class="px-3 py-1.5 bg-red-600 text-white rounded text-xs hover:bg-red-700 cursor-pointer">
                        Reject
                      </button>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>

        <%!-- Activity Log (1/3 width) --%>
        <div>
          <div class="flex items-center justify-between mb-4">
            <h2 class="text-lg font-haas_medium_65 text-gray-900">Activity</h2>
            <.link navigate={~p"/admin/content/history"} class="text-sm text-blue-600 hover:underline cursor-pointer">
              History &rarr;
            </.link>
          </div>

          <div id="activity-log" class="bg-white rounded-lg shadow divide-y divide-gray-100 max-h-[500px] overflow-y-auto" phx-update="replace">
            <%= if @activity == [] do %>
              <div id="activity-empty" class="p-4 text-center text-gray-500 text-sm">No activity yet</div>
            <% else %>
              <%= for entry <- @activity do %>
                <div id={"activity-#{entry.id}"} class="p-3 flex items-start gap-3">
                  <div class={"w-2 h-2 rounded-full mt-1.5 shrink-0 #{status_icon(entry.status)}"}></div>
                  <div class="min-w-0">
                    <p class="text-gray-900 text-sm truncate"><%= entry.article_data["title"] || "Untitled" %></p>
                    <p class="text-gray-500 text-xs mt-0.5">
                      <%= status_label(entry.status) %> &middot; <%= time_ago(entry.updated_at) %>
                    </p>
                  </div>
                </div>
              <% end %>
            <% end %>
          </div>

          <%!-- Quick Links --%>
          <div class="mt-4 space-y-2">
            <.link navigate={~p"/admin/content/feeds"} class="block bg-white rounded-lg shadow p-3 hover:shadow-md cursor-pointer">
              <span class="text-gray-700 text-sm">Feeds Management</span>
            </.link>
            <.link navigate={~p"/admin/content/authors"} class="block bg-white rounded-lg shadow p-3 hover:shadow-md cursor-pointer">
              <span class="text-gray-700 text-sm">Author Personas</span>
            </.link>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
