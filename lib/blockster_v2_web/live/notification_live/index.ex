defmodule BlocksterV2Web.NotificationLive.Index do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.Notifications

  @page_size 20

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns[:current_user]

    if user do
      notifications = Notifications.list_notifications(user.id, limit: @page_size, offset: 0)

      {:ok,
       socket
       |> assign(:page_title, "Notifications")
       |> assign(:active_filter, "all")
       |> assign(:notifications, notifications)
       |> assign(:offset, @page_size)
       |> assign(:end_reached, length(notifications) < @page_size)}
    else
      {:ok,
       socket
       |> assign(:page_title, "Notifications")
       |> assign(:active_filter, "all")
       |> assign(:notifications, [])
       |> assign(:offset, 0)
       |> assign(:end_reached, true)}
    end
  end

  @impl true
  def handle_event("filter_status", %{"status" => status}, socket) do
    {:noreply, reload_notifications(socket, status: status)}
  end

  def handle_event("mark_read", %{"id" => id}, socket) do
    notification_id = String.to_integer(id)
    Notifications.mark_as_read(notification_id)

    notifications =
      Enum.map(socket.assigns.notifications, fn n ->
        if n.id == notification_id do
          %{n | read_at: DateTime.utc_now() |> DateTime.truncate(:second)}
        else
          n
        end
      end)

    user_id = socket.assigns.current_user.id
    new_count = Notifications.unread_count(user_id)
    Notifications.broadcast_count_update(user_id, new_count)

    {:noreply, assign(socket, :notifications, notifications)}
  end

  def handle_event("click_notification", %{"id" => id} = params, socket) do
    notification_id = String.to_integer(id)
    Notifications.mark_as_clicked(notification_id)

    user_id = socket.assigns.current_user.id
    new_count = Notifications.unread_count(user_id)
    Notifications.broadcast_count_update(user_id, new_count)

    action_url = params["url"]

    if action_url && action_url != "" do
      if String.starts_with?(action_url, "http") do
        {:noreply, push_event(socket, "open_external_url", %{url: action_url})}
      else
        {:noreply, push_navigate(socket, to: action_url)}
      end
    else
      # Just mark as read in place
      notifications =
        Enum.map(socket.assigns.notifications, fn n ->
          if n.id == notification_id do
            now = DateTime.utc_now() |> DateTime.truncate(:second)
            %{n | read_at: now, clicked_at: now}
          else
            n
          end
        end)

      {:noreply, assign(socket, :notifications, notifications)}
    end
  end

  def handle_event("mark_all_read", _params, socket) do
    user_id = socket.assigns.current_user.id
    Notifications.mark_all_as_read(user_id)

    notifications =
      Enum.map(socket.assigns.notifications, fn n ->
        if is_nil(n.read_at) do
          %{n | read_at: DateTime.utc_now() |> DateTime.truncate(:second)}
        else
          n
        end
      end)

    {:noreply, assign(socket, :notifications, notifications)}
  end

  def handle_event("load-more-notifications", _params, socket) do
    user = socket.assigns.current_user

    if user do
      opts = build_query_opts(socket.assigns, socket.assigns.offset)
      batch = Notifications.list_notifications(user.id, opts)
      end_reached = length(batch) < @page_size

      {:reply, %{end_reached: end_reached},
       socket
       |> assign(:notifications, socket.assigns.notifications ++ batch)
       |> assign(:offset, socket.assigns.offset + @page_size)
       |> assign(:end_reached, end_reached)}
    else
      {:reply, %{end_reached: true}, socket}
    end
  end

  # ============ Private Helpers ============

  defp reload_notifications(socket, opts) do
    status = Keyword.get(opts, :status, socket.assigns.active_filter)
    user = socket.assigns.current_user

    query_opts = build_query_opts(%{active_filter: status}, 0)
    notifications = if user, do: Notifications.list_notifications(user.id, query_opts), else: []

    socket
    |> assign(:active_filter, status)
    |> assign(:notifications, notifications)
    |> assign(:offset, @page_size)
    |> assign(:end_reached, length(notifications) < @page_size)
  end

  defp build_query_opts(assigns, offset) do
    opts = [limit: @page_size, offset: offset]

    if assigns.active_filter == "unread" do
      Keyword.put(opts, :status, :unread)
    else
      if assigns.active_filter == "read" do
        Keyword.put(opts, :status, :read)
      else
        opts
      end
    end
  end

  # ============ Time Formatting (shared with layouts.ex) ============

  def format_time(nil), do: ""
  def format_time(%NaiveDateTime{} = ndt), do: format_time(DateTime.from_naive!(ndt, "Etc/UTC"))

  def format_time(datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      diff < 604_800 -> "#{div(diff, 86400)}d ago"
      true -> Calendar.strftime(datetime, "%b %d")
    end
  end

  # ============ Template ============

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-[#F5F6FB]">
      <div class="max-w-3xl mx-auto px-4 pt-24 md:pt-28 pb-6 md:pb-10">
        <%!-- Page Header --%>
        <div class="flex items-center justify-between mb-8">
          <div class="flex items-center gap-3">
            <div class="w-10 h-10 bg-[#CAFC00] rounded-xl flex items-center justify-center">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-5 h-5 text-black">
                <path fill-rule="evenodd" d="M5.25 9a6.75 6.75 0 0 1 13.5 0v.75c0 2.123.8 4.057 2.118 5.52a.75.75 0 0 1-.297 1.206c-1.544.57-3.16.99-4.831 1.243a3.75 3.75 0 1 1-7.48 0 24.585 24.585 0 0 1-4.831-1.244.75.75 0 0 1-.298-1.205A8.217 8.217 0 0 0 5.25 9.75V9Zm4.502 8.9a2.25 2.25 0 1 0 4.496 0 25.057 25.057 0 0 1-4.496 0Z" clip-rule="evenodd" />
              </svg>
            </div>
            <h1 class="text-2xl font-haas_medium_65 text-[#141414]">Notifications</h1>
          </div>
          <div class="flex items-center gap-3">
            <%= if Enum.any?(@notifications, &is_nil(&1.read_at)) do %>
              <button
                phx-click="mark_all_read"
                class="hidden sm:flex items-center gap-1.5 text-sm text-gray-500 hover:text-[#141414] font-haas_roman_55 cursor-pointer transition-colors"
              >
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-4 h-4">
                  <path fill-rule="evenodd" d="M19.916 4.626a.75.75 0 0 1 .208 1.04l-9 13.5a.75.75 0 0 1-1.154.114l-6-6a.75.75 0 0 1 1.06-1.06l5.353 5.353 8.493-12.74a.75.75 0 0 1 1.04-.207Z" clip-rule="evenodd" />
                </svg>
                Mark all read
              </button>
            <% end %>
            <a
              href="/notifications/referrals"
              class="flex items-center justify-center w-9 h-9 rounded-xl bg-white border border-gray-200 hover:border-gray-300 hover:shadow-sm transition-all cursor-pointer"
              title="Referral Dashboard"
            >
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-4 h-4 text-gray-500">
                <path d="M15.75 6a3.75 3.75 0 1 1-7.5 0 3.75 3.75 0 0 1 7.5 0ZM4.501 20.118a7.5 7.5 0 0 1 14.998 0A17.933 17.933 0 0 1 12 21.75c-2.676 0-5.216-.584-7.499-1.632Z" />
              </svg>
            </a>
            <a
              href="/notifications/settings"
              class="flex items-center justify-center w-9 h-9 rounded-xl bg-white border border-gray-200 hover:border-gray-300 hover:shadow-sm transition-all cursor-pointer"
              title="Notification Settings"
            >
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-4.5 h-4.5 text-gray-500">
                <path fill-rule="evenodd" d="M11.078 2.25c-.917 0-1.699.663-1.85 1.567L9.05 4.889c-.02.12-.115.26-.297.348a7.493 7.493 0 0 0-.986.57c-.166.115-.334.126-.45.083L6.3 5.508a1.875 1.875 0 0 0-2.282.819l-.922 1.597a1.875 1.875 0 0 0 .432 2.385l.84.692c.095.078.17.229.154.43a7.598 7.598 0 0 0 0 1.139c.015.2-.059.352-.153.43l-.841.692a1.875 1.875 0 0 0-.432 2.385l.922 1.597a1.875 1.875 0 0 0 2.282.818l1.019-.382c.115-.043.283-.031.45.082.312.214.641.405.985.57.182.088.277.228.297.35l.178 1.071c.151.904.933 1.567 1.85 1.567h1.844c.916 0 1.699-.663 1.85-1.567l.178-1.072c.02-.12.114-.26.297-.349.344-.165.673-.356.985-.57.167-.114.335-.125.45-.082l1.02.382a1.875 1.875 0 0 0 2.28-.819l.923-1.597a1.875 1.875 0 0 0-.432-2.385l-.84-.692c-.095-.078-.17-.229-.154-.43a7.614 7.614 0 0 0 0-1.139c-.016-.2.059-.352.153-.43l.84-.692c.708-.582.891-1.59.433-2.385l-.922-1.597a1.875 1.875 0 0 0-2.282-.818l-1.02.382c-.114.043-.282.031-.449-.083a7.49 7.49 0 0 0-.985-.57c-.183-.087-.277-.227-.297-.348l-.179-1.072a1.875 1.875 0 0 0-1.85-1.567h-1.843ZM12 15.75a3.75 3.75 0 1 0 0-7.5 3.75 3.75 0 0 0 0 7.5Z" clip-rule="evenodd" />
              </svg>
            </a>
          </div>
        </div>

        <%!-- Read/Unread Filter --%>
        <div class="flex items-center justify-between mb-5">
          <div class="flex gap-1">
            <%= for {value, label} <- [{"all", "All"}, {"unread", "Unread"}, {"read", "Read"}] do %>
              <button
                phx-click="filter_status"
                phx-value-status={value}
                class={"px-3 py-1 rounded-md text-xs font-haas_roman_55 transition-colors cursor-pointer #{if @active_filter == value, do: "bg-[#141414] text-white", else: "text-gray-400 hover:text-gray-600 hover:bg-white"}"}
              >
                <%= label %>
              </button>
            <% end %>
          </div>
          <%!-- Mobile mark all read --%>
          <%= if Enum.any?(@notifications, &is_nil(&1.read_at)) do %>
            <button
              phx-click="mark_all_read"
              class="sm:hidden text-xs text-gray-400 hover:text-[#141414] font-haas_roman_55 cursor-pointer transition-colors"
            >
              Mark all read
            </button>
          <% end %>
        </div>

        <%!-- Notification List --%>
        <div
          id="notifications-list"
          phx-hook="InfiniteScroll"
          data-event="load-more-notifications"
          class="space-y-2"
        >
          <%= if @notifications == [] do %>
            <%!-- Empty State --%>
            <div class="flex flex-col items-center justify-center py-24 text-center">
              <div class="relative mb-6">
                <div class="w-20 h-20 bg-[#CAFC00]/15 rounded-2xl flex items-center justify-center">
                  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-10 h-10 text-[#141414]/20">
                    <path fill-rule="evenodd" d="M5.25 9a6.75 6.75 0 0 1 13.5 0v.75c0 2.123.8 4.057 2.118 5.52a.75.75 0 0 1-.297 1.206c-1.544.57-3.16.99-4.831 1.243a3.75 3.75 0 1 1-7.48 0 24.585 24.585 0 0 1-4.831-1.244.75.75 0 0 1-.298-1.205A8.217 8.217 0 0 0 5.25 9.75V9Zm4.502 8.9a2.25 2.25 0 1 0 4.496 0 25.057 25.057 0 0 1-4.496 0Z" clip-rule="evenodd" />
                  </svg>
                </div>
                <div class="absolute -top-1 -right-1 w-6 h-6 bg-[#CAFC00] rounded-full flex items-center justify-center">
                  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-3.5 h-3.5 text-black">
                    <path fill-rule="evenodd" d="M19.916 4.626a.75.75 0 0 1 .208 1.04l-9 13.5a.75.75 0 0 1-1.154.114l-6-6a.75.75 0 0 1 1.06-1.06l5.353 5.353 8.493-12.74a.75.75 0 0 1 1.04-.207Z" clip-rule="evenodd" />
                  </svg>
                </div>
              </div>
              <p class="text-lg font-haas_medium_65 text-[#141414] mb-1">All caught up</p>
              <p class="text-sm text-gray-400 font-haas_roman_55 max-w-[240px]">Nothing new right now. We'll notify you when something happens.</p>
            </div>
          <% else %>
            <%= for notification <- @notifications do %>
              <div
                id={"notification-#{notification.id}"}
                class={"relative flex items-start gap-3 p-4 rounded-xl transition-all cursor-pointer group #{if is_nil(notification.read_at), do: "bg-white border border-gray-100 shadow-[0_1px_3px_rgba(0,0,0,0.04)]", else: "bg-white/50 border border-gray-100/60 hover:bg-white hover:border-gray-200"}"}
                phx-click="click_notification"
                phx-value-id={notification.id}
                phx-value-url={notification.action_url}
              >
                <%!-- Unread accent bar --%>
                <%= if is_nil(notification.read_at) do %>
                  <div class="absolute left-0 top-3 bottom-3 w-[3px] rounded-full bg-[#CAFC00]"></div>
                <% end %>

                <%!-- Image / Icon --%>
                <div class={"flex-shrink-0 #{if is_nil(notification.read_at), do: "ml-1", else: ""}"}>
                  <%= if notification.image_url do %>
                    <img
                      src={notification.image_url}
                      class={"w-11 h-11 rounded-xl object-cover #{if is_nil(notification.read_at), do: "", else: "opacity-75"}"}
                      loading="lazy"
                    />
                  <% else %>
                    <div class={"w-11 h-11 rounded-xl flex items-center justify-center #{if is_nil(notification.read_at), do: category_icon_bg(notification.category), else: "bg-gray-100"}"}>
                      <%= category_icon(notification.category) %>
                    </div>
                  <% end %>
                </div>

                <%!-- Content --%>
                <div class="flex-1 min-w-0">
                  <div class="flex items-start justify-between gap-2">
                    <p class={"text-sm leading-snug #{if is_nil(notification.read_at), do: "font-haas_medium_65 text-[#141414]", else: "font-haas_roman_55 text-gray-600"}"}>
                      <%= notification.title %>
                    </p>
                    <div class="flex items-center gap-2 flex-shrink-0">
                      <span class="text-[10px] whitespace-nowrap text-gray-400"><%= format_time(notification.inserted_at) %></span>
                      <%= if is_nil(notification.read_at) do %>
                        <div class="w-2 h-2 rounded-full bg-[#CAFC00] flex-shrink-0 shadow-[0_0_6px_rgba(202,252,0,0.4)]"></div>
                      <% end %>
                    </div>
                  </div>
                  <p class={"text-xs mt-0.5 line-clamp-2 #{if is_nil(notification.read_at), do: "text-gray-500", else: "text-gray-400"}"}><%= notification.body %></p>
                  <%= if notification.action_label do %>
                    <p class={"text-xs mt-1.5 font-haas_medium_65 group-hover:underline #{if is_nil(notification.read_at), do: "text-[#141414]", else: "text-gray-400"}"}><%= notification.action_label %></p>
                  <% end %>
                </div>

                <%!-- Mark read button (only for unread) --%>
                <%= if is_nil(notification.read_at) do %>
                  <button
                    phx-click="mark_read"
                    phx-value-id={notification.id}
                    class="flex-shrink-0 p-1.5 rounded-lg text-gray-300 hover:text-[#141414] hover:bg-gray-50 opacity-0 group-hover:opacity-100 transition-all cursor-pointer"
                    title="Mark as read"
                  >
                    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-4 h-4">
                      <path fill-rule="evenodd" d="M19.916 4.626a.75.75 0 0 1 .208 1.04l-9 13.5a.75.75 0 0 1-1.154.114l-6-6a.75.75 0 0 1 1.06-1.06l5.353 5.353 8.493-12.74a.75.75 0 0 1 1.04-.207Z" clip-rule="evenodd" />
                    </svg>
                  </button>
                <% end %>
              </div>
            <% end %>

            <%!-- Loading indicator --%>
            <%= unless @end_reached do %>
              <div class="flex justify-center py-6">
                <div class="w-6 h-6 border-2 border-gray-200 border-t-[#CAFC00] rounded-full animate-spin"></div>
              </div>
            <% end %>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # ============ Category Helpers ============

  defp category_icon_bg("content"), do: "bg-blue-50"
  defp category_icon_bg("offers"), do: "bg-[#CAFC00]/15"
  defp category_icon_bg("social"), do: "bg-purple-50"
  defp category_icon_bg("rewards"), do: "bg-amber-50"
  defp category_icon_bg("system"), do: "bg-gray-50"
  defp category_icon_bg(_), do: "bg-gray-50"

  defp category_icon("content") do
    Phoenix.HTML.raw("""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-6 h-6 text-blue-600">
      <path d="M11.25 4.533A9.707 9.707 0 0 0 6 3a9.735 9.735 0 0 0-3.25.555.75.75 0 0 0-.5.707v14.25a.75.75 0 0 0 1 .707A8.237 8.237 0 0 1 6 18.75c1.995 0 3.823.707 5.25 1.886V4.533ZM12.75 20.636A8.214 8.214 0 0 1 18 18.75c.966 0 1.89.166 2.75.47a.75.75 0 0 0 1-.708V4.262a.75.75 0 0 0-.5-.707A9.735 9.735 0 0 0 18 3a9.707 9.707 0 0 0-5.25 1.533v16.103Z" />
    </svg>
    """)
  end

  defp category_icon("offers") do
    Phoenix.HTML.raw("""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-6 h-6 text-[#8B8B00]">
      <path fill-rule="evenodd" d="M5.25 2.25a3 3 0 0 0-3 3v4.318a3 3 0 0 0 .879 2.121l9.58 9.581c.92.92 2.39.94 3.36.04l4.29-4.001a2.381 2.381 0 0 0 .04-3.36l-9.58-9.581a3 3 0 0 0-2.122-.879H5.25ZM6.375 7.5a1.125 1.125 0 1 0 0-2.25 1.125 1.125 0 0 0 0 2.25Z" clip-rule="evenodd" />
    </svg>
    """)
  end

  defp category_icon("social") do
    Phoenix.HTML.raw("""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-6 h-6 text-purple-600">
      <path d="M4.913 2.658c2.075-.27 4.19-.408 6.337-.408 2.147 0 4.262.139 6.337.408 1.922.25 3.291 1.861 3.405 3.727a4.403 4.403 0 0 0-1.032-.211 50.89 50.89 0 0 0-8.42 0c-2.358.196-4.04 2.19-4.04 4.434v4.286a4.47 4.47 0 0 0 2.433 3.984L7.28 21.53A.75.75 0 0 1 6 21v-2.995a3 3 0 0 1-1.087-5.347c-.03-.67 0-1.34.087-2.013.087-.673.24-1.34.453-1.987Z" />
      <path d="M15.75 7.5c-1.376 0-2.739.057-4.086.169C10.124 7.797 9 9.103 9 10.609v4.285c0 1.507 1.128 2.814 2.67 2.94 1.243.102 2.5.157 3.768.165l2.782 2.781a.75.75 0 0 0 1.28-.53v-2.39l.33-.026c1.542-.125 2.67-1.433 2.67-2.94v-4.286c0-1.505-1.125-2.811-2.664-2.94A49.392 49.392 0 0 0 15.75 7.5Z" />
    </svg>
    """)
  end

  defp category_icon("rewards") do
    Phoenix.HTML.raw("""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-6 h-6 text-amber-600">
      <path fill-rule="evenodd" d="M10.788 3.21c.448-1.077 1.976-1.077 2.424 0l2.082 5.006 5.404.434c1.164.093 1.636 1.545.749 2.305l-4.117 3.527 1.257 5.273c.271 1.136-.964 2.033-1.96 1.425L12 18.354 7.373 21.18c-.996.608-2.231-.29-1.96-1.425l1.257-5.273-4.117-3.527c-.887-.76-.415-2.212.749-2.305l5.404-.434 2.082-5.005Z" clip-rule="evenodd" />
    </svg>
    """)
  end

  defp category_icon("system") do
    Phoenix.HTML.raw("""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-6 h-6 text-gray-600">
      <path fill-rule="evenodd" d="M11.078 2.25c-.917 0-1.699.663-1.85 1.567L9.05 4.889c-.02.12-.115.26-.297.348a7.493 7.493 0 0 0-.986.57c-.166.115-.334.126-.45.083L6.3 5.508a1.875 1.875 0 0 0-2.282.819l-.922 1.597a1.875 1.875 0 0 0 .432 2.385l.84.692c.095.078.17.229.154.43a7.598 7.598 0 0 0 0 1.139c.015.2-.059.352-.153.43l-.841.692a1.875 1.875 0 0 0-.432 2.385l.922 1.597a1.875 1.875 0 0 0 2.282.818l1.019-.382c.115-.043.283-.031.45.082.312.214.641.405.985.57.182.088.277.228.297.35l.178 1.071c.151.904.933 1.567 1.85 1.567h1.844c.916 0 1.699-.663 1.85-1.567l.178-1.072c.02-.12.114-.26.297-.349.344-.165.673-.356.985-.57.167-.114.335-.125.45-.082l1.02.382a1.875 1.875 0 0 0 2.28-.819l.923-1.597a1.875 1.875 0 0 0-.432-2.385l-.84-.692c-.095-.078-.17-.229-.154-.43a7.614 7.614 0 0 0 0-1.139c-.016-.2.059-.352.153-.43l.84-.692c.708-.582.891-1.59.433-2.385l-.922-1.597a1.875 1.875 0 0 0-2.282-.818l-1.02.382c-.114.043-.282.031-.449-.083a7.49 7.49 0 0 0-.985-.57c-.183-.087-.277-.227-.297-.348l-.179-1.072a1.875 1.875 0 0 0-1.85-1.567h-1.843ZM12 15.75a3.75 3.75 0 1 0 0-7.5 3.75 3.75 0 0 0 0 7.5Z" clip-rule="evenodd" />
    </svg>
    """)
  end

  defp category_icon(_) do
    Phoenix.HTML.raw("""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-6 h-6 text-gray-600">
      <path fill-rule="evenodd" d="M5.25 9a6.75 6.75 0 0 1 13.5 0v.75c0 2.123.8 4.057 2.118 5.52a.75.75 0 0 1-.297 1.206c-1.544.57-3.16.99-4.831 1.243a3.75 3.75 0 1 1-7.48 0 24.585 24.585 0 0 1-4.831-1.244.75.75 0 0 1-.298-1.205A8.217 8.217 0 0 0 5.25 9.75V9Zm4.502 8.9a2.25 2.25 0 1 0 4.496 0 25.057 25.057 0 0 1-4.496 0Z" clip-rule="evenodd" />
    </svg>
    """)
  end
end
