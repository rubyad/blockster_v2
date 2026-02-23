defmodule BlocksterV2Web.NotificationSettingsLive.Index do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.{Notifications, Blog, Accounts, Repo}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns[:current_user]

    if user do
      {:ok, prefs} = Notifications.get_or_create_preferences(user.id)
      followed_hubs = Blog.get_user_followed_hubs_with_settings(user.id)
      # Reload user to get telegram fields
      fresh_user = Repo.get!(Accounts.User, user.id)

      {:ok,
       socket
       |> assign(:page_title, "Notification Settings")
       |> assign(:preferences, prefs)
       |> assign(:followed_hubs, followed_hubs)
       |> assign(:show_unsubscribe_confirm, false)
       |> assign(:telegram_connected, fresh_user.telegram_user_id != nil)
       |> assign(:telegram_username, fresh_user.telegram_username)
       |> assign(:telegram_group_joined, fresh_user.telegram_group_joined_at != nil)
       |> assign(:telegram_bot_url, nil)
       |> assign(:telegram_polling, false)
       |> assign(:show_telegram_disconnect, false)
       |> assign(:saved, false)}
    else
      {:ok,
       socket
       |> assign(:page_title, "Notification Settings")
       |> assign(:preferences, nil)
       |> assign(:followed_hubs, [])
       |> assign(:show_unsubscribe_confirm, false)
       |> assign(:telegram_connected, false)
       |> assign(:telegram_username, nil)
       |> assign(:telegram_group_joined, false)
       |> assign(:telegram_bot_url, nil)
       |> assign(:telegram_polling, false)
       |> assign(:show_telegram_disconnect, false)
       |> assign(:saved, false)}
    end
  end

  @impl true
  def handle_event("toggle_preference", %{"field" => field}, socket) do
    user = socket.assigns.current_user
    if user do
      current_value = Map.get(socket.assigns.preferences, String.to_existing_atom(field))
      attrs = %{String.to_existing_atom(field) => !current_value}

      case Notifications.update_preferences(user.id, attrs) do
        {:ok, updated_prefs} ->
          {:noreply,
           socket
           |> assign(:preferences, updated_prefs)
           |> assign(:saved, true)
           |> then(&schedule_saved_clear/1)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to update preference")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("toggle_hub_notification", %{"hub-id" => hub_id_str, "field" => field}, socket) do
    user = socket.assigns.current_user
    if user do
      hub_id = String.to_integer(hub_id_str)
      field_atom = String.to_existing_atom(field)

      # Find current value in followed_hubs
      hub_entry = Enum.find(socket.assigns.followed_hubs, fn h -> h.hub.id == hub_id end)

      if hub_entry do
        current_value = Map.get(hub_entry.follower, field_atom)
        attrs = %{field_atom => !current_value}

        case Blog.update_hub_follow_notifications(user.id, hub_id, attrs) do
          {:ok, _} ->
            # Refresh hub list
            followed_hubs = Blog.get_user_followed_hubs_with_settings(user.id)

            {:noreply,
             socket
             |> assign(:followed_hubs, followed_hubs)
             |> assign(:saved, true)
             |> then(&schedule_saved_clear/1)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to update hub notification")}
        end
      else
        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("connect_telegram", _params, socket) do
    user = socket.assigns.current_user
    if user do
      # Generate a unique connect token
      token = Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)

      case Accounts.update_user(Repo.get!(Accounts.User, user.id), %{telegram_connect_token: token}) do
        {:ok, _} ->
          bot_url = "https://t.me/BlocksterV2Bot?start=#{token}"
          # Start polling for connection (webhook will update the user record)
          if connected?(socket), do: Process.send_after(self(), :check_telegram_connected, 3_000)

          {:noreply,
           socket
           |> assign(:telegram_bot_url, bot_url)
           |> assign(:telegram_polling, true)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to generate Telegram link")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("show_telegram_disconnect", _params, socket) do
    {:noreply, assign(socket, :show_telegram_disconnect, true)}
  end

  def handle_event("cancel_telegram_disconnect", _params, socket) do
    {:noreply, assign(socket, :show_telegram_disconnect, false)}
  end

  def handle_event("confirm_telegram_disconnect", _params, socket) do
    user = socket.assigns.current_user
    if user do
      fresh_user = Repo.get!(Accounts.User, user.id)

      case Accounts.update_user(fresh_user, %{
        telegram_user_id: nil,
        telegram_username: nil,
        telegram_connect_token: nil,
        telegram_connected_at: nil,
        telegram_group_joined_at: nil
      }) do
        {:ok, _} ->
          {:noreply,
           socket
           |> assign(:telegram_connected, false)
           |> assign(:telegram_username, nil)
           |> assign(:telegram_group_joined, false)
           |> assign(:show_telegram_disconnect, false)
           |> put_flash(:info, "Telegram disconnected")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to disconnect Telegram")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("show_unsubscribe_confirm", _params, socket) do
    {:noreply, assign(socket, :show_unsubscribe_confirm, true)}
  end

  def handle_event("cancel_unsubscribe", _params, socket) do
    {:noreply, assign(socket, :show_unsubscribe_confirm, false)}
  end

  def handle_event("confirm_unsubscribe_all", _params, socket) do
    user = socket.assigns.current_user
    if user do
      case Notifications.update_preferences(user.id, %{email_enabled: false, sms_enabled: false}) do
        {:ok, updated_prefs} ->
          {:noreply,
           socket
           |> assign(:preferences, updated_prefs)
           |> assign(:show_unsubscribe_confirm, false)
           |> put_flash(:info, "You have been unsubscribed from all notifications")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to unsubscribe")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:clear_saved, socket) do
    {:noreply, assign(socket, :saved, false)}
  end

  def handle_info(:check_telegram_connected, socket) do
    user = socket.assigns.current_user

    if user do
      fresh_user = Repo.get!(Accounts.User, user.id)

      if fresh_user.telegram_user_id do
        {:noreply,
         socket
         |> assign(:telegram_connected, true)
         |> assign(:telegram_username, fresh_user.telegram_username)
         |> assign(:telegram_group_joined, fresh_user.telegram_group_joined_at != nil)
         |> assign(:telegram_bot_url, nil)
         |> assign(:telegram_polling, false)
         |> put_flash(:info, "Telegram connected successfully!")}
      else
        # Keep polling (up to ~60s)
        Process.send_after(self(), :check_telegram_connected, 3_000)
        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  # ============ Private Helpers ============

  defp schedule_saved_clear(socket) do
    if connected?(socket), do: Process.send_after(self(), :clear_saved, 2000)
    socket
  end

  # ============ Template ============

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-[#F5F6FB]">
      <div class="max-w-2xl mx-auto px-4 pt-24 md:pt-28 pb-6 md:pb-10">
        <%!-- Header --%>
        <div class="flex items-center gap-3 mb-8">
          <a href="/notifications" class="flex items-center justify-center w-9 h-9 rounded-xl bg-white border border-gray-200 hover:border-gray-300 hover:shadow-sm transition-all cursor-pointer">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-4.5 h-4.5 text-gray-500">
              <path fill-rule="evenodd" d="M7.72 12.53a.75.75 0 0 1 0-1.06l7.5-7.5a.75.75 0 1 1 1.06 1.06L9.31 12l6.97 6.97a.75.75 0 1 1-1.06 1.06l-7.5-7.5Z" clip-rule="evenodd" />
            </svg>
          </a>
          <h1 class="text-2xl font-haas_medium_65 text-[#141414]">Notification Settings</h1>
          <%= if @saved do %>
            <span class="ml-auto flex items-center gap-1 text-xs font-haas_medium_65 text-white bg-gray-900 px-2.5 py-1 rounded-lg">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-3 h-3">
                <path fill-rule="evenodd" d="M19.916 4.626a.75.75 0 0 1 .208 1.04l-9 13.5a.75.75 0 0 1-1.154.114l-6-6a.75.75 0 0 1 1.06-1.06l5.353 5.353 8.493-12.74a.75.75 0 0 1 1.04-.207Z" clip-rule="evenodd" />
              </svg>
              Saved
            </span>
          <% end %>
        </div>

        <%= if @preferences do %>
          <%!-- Email Toggle --%>
          <.section title="Email Notifications" subtitle="Receive emails for articles, rewards, and updates">
            <.toggle
              label="Email notifications"
              description="Enable or disable all email notifications"
              field="email_enabled"
              checked={@preferences.email_enabled}
            />
          </.section>

          <%!-- In-App Toggle --%>
          <.section title="In-App Notifications" subtitle="See notifications in the bell icon while browsing">
            <.toggle label="In-app notifications" description="Show notification bell and alerts" field="in_app_enabled" checked={@preferences.in_app_enabled} />
          </.section>

          <%!-- Telegram --%>
          <.section title="Telegram" subtitle="Get new posts delivered to your Telegram">
            <div class="py-2 space-y-4">
              <%!-- Connect Account --%>
              <div class="flex items-start gap-4">
                <div class="w-10 h-10 rounded-xl bg-[#2AABEE] flex items-center justify-center flex-shrink-0">
                  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="white" class="w-5 h-5">
                    <path d="M11.944 0A12 12 0 0 0 0 12a12 12 0 0 0 12 12 12 12 0 0 0 12-12A12 12 0 0 0 12 0a12 12 0 0 0-.056 0zm4.962 7.224c.1-.002.321.023.465.14a.506.506 0 0 1 .171.325c.016.093.036.306.02.472-.18 1.898-.962 6.502-1.36 8.627-.168.9-.499 1.201-.82 1.23-.696.065-1.225-.46-1.9-.902-1.056-.693-1.653-1.124-2.678-1.8-1.185-.78-.417-1.21.258-1.91.177-.184 3.247-2.977 3.307-3.23.007-.032.014-.15-.056-.212s-.174-.041-.249-.024c-.106.024-1.793 1.14-5.061 3.345-.48.33-.913.49-1.302.48-.428-.008-1.252-.241-1.865-.44-.752-.245-1.349-.374-1.297-.789.027-.216.325-.437.893-.663 3.498-1.524 5.83-2.529 6.998-3.014 3.332-1.386 4.025-1.627 4.476-1.635z"/>
                  </svg>
                </div>
                <div class="flex-1">
                  <%= if @telegram_connected do %>
                    <div class="flex items-center gap-2 mb-1">
                      <p class="text-sm font-haas_medium_65 text-[#141414]">Telegram Connected</p>
                      <span class="inline-flex items-center gap-1 px-2 py-0.5 bg-green-50 text-green-600 text-[10px] font-haas_medium_65 rounded-full">
                        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-3 h-3">
                          <path fill-rule="evenodd" d="M19.916 4.626a.75.75 0 0 1 .208 1.04l-9 13.5a.75.75 0 0 1-1.154.114l-6-6a.75.75 0 0 1 1.06-1.06l5.353 5.353 8.493-12.74a.75.75 0 0 1 1.04-.207Z" clip-rule="evenodd" />
                        </svg>
                        Connected
                      </span>
                    </div>
                    <p class="text-xs text-gray-400 font-haas_roman_55 mb-2">
                      Linked as <span class="text-gray-600 font-haas_medium_65">@<%= @telegram_username || "unknown" %></span>
                    </p>
                    <%= if @show_telegram_disconnect do %>
                      <div class="flex items-center gap-2">
                        <button
                          phx-click="confirm_telegram_disconnect"
                          class="px-3 py-1.5 bg-red-600 text-white text-xs font-haas_medium_65 rounded-lg hover:bg-red-700 transition-colors cursor-pointer"
                        >
                          Yes, disconnect
                        </button>
                        <button
                          phx-click="cancel_telegram_disconnect"
                          class="px-3 py-1.5 bg-gray-100 text-gray-600 text-xs font-haas_roman_55 rounded-lg hover:bg-gray-200 transition-colors cursor-pointer"
                        >
                          Cancel
                        </button>
                      </div>
                    <% else %>
                      <button
                        phx-click="show_telegram_disconnect"
                        class="text-xs text-red-400 hover:text-red-600 font-haas_medium_65 cursor-pointer transition-colors"
                      >
                        Disconnect
                      </button>
                    <% end %>
                  <% else %>
                    <p class="text-sm font-haas_medium_65 text-[#141414] mb-1">Connect your Telegram</p>
                    <p class="text-xs text-gray-400 font-haas_roman_55 mb-3">
                      Link your Telegram account to Blockster and earn <span class="text-[#141414] font-haas_medium_65">500 BUX</span>.
                    </p>
                    <%= if @telegram_bot_url do %>
                      <a
                        href={@telegram_bot_url}
                        target="_blank"
                        rel="noopener noreferrer"
                        class="inline-flex items-center gap-2 px-4 py-2.5 bg-[#2AABEE] text-white text-sm font-haas_medium_65 rounded-xl hover:bg-[#229ED9] transition-colors cursor-pointer"
                      >
                        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-4 h-4">
                          <path d="M11.944 0A12 12 0 0 0 0 12a12 12 0 0 0 12 12 12 12 0 0 0 12-12A12 12 0 0 0 12 0a12 12 0 0 0-.056 0zm4.962 7.224c.1-.002.321.023.465.14a.506.506 0 0 1 .171.325c.016.093.036.306.02.472-.18 1.898-.962 6.502-1.36 8.627-.168.9-.499 1.201-.82 1.23-.696.065-1.225-.46-1.9-.902-1.056-.693-1.653-1.124-2.678-1.8-1.185-.78-.417-1.21.258-1.91.177-.184 3.247-2.977 3.307-3.23.007-.032.014-.15-.056-.212s-.174-.041-.249-.024c-.106.024-1.793 1.14-5.061 3.345-.48.33-.913.49-1.302.48-.428-.008-1.252-.241-1.865-.44-.752-.245-1.349-.374-1.297-.789.027-.216.325-.437.893-.663 3.498-1.524 5.83-2.529 6.998-3.014 3.332-1.386 4.025-1.627 4.476-1.635z"/>
                        </svg>
                        Open Telegram Bot
                      </a>
                      <p class="text-xs text-gray-400 font-haas_roman_55 mt-2 flex items-center gap-1.5">
                        <span class="inline-block w-2 h-2 bg-[#CAFC00] rounded-full animate-pulse"></span>
                        Waiting for connection — click Start in Telegram
                      </p>
                    <% else %>
                      <button
                        phx-click="connect_telegram"
                        class="inline-flex items-center gap-2 px-4 py-2.5 bg-[#2AABEE] text-white text-sm font-haas_medium_65 rounded-xl hover:bg-[#229ED9] transition-colors cursor-pointer"
                      >
                        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-4 h-4">
                          <path d="M11.944 0A12 12 0 0 0 0 12a12 12 0 0 0 12 12 12 12 0 0 0 12-12A12 12 0 0 0 12 0a12 12 0 0 0-.056 0zm4.962 7.224c.1-.002.321.023.465.14a.506.506 0 0 1 .171.325c.016.093.036.306.02.472-.18 1.898-.962 6.502-1.36 8.627-.168.9-.499 1.201-.82 1.23-.696.065-1.225-.46-1.9-.902-1.056-.693-1.653-1.124-2.678-1.8-1.185-.78-.417-1.21.258-1.91.177-.184 3.247-2.977 3.307-3.23.007-.032.014-.15-.056-.212s-.174-.041-.249-.024c-.106.024-1.793 1.14-5.061 3.345-.48.33-.913.49-1.302.48-.428-.008-1.252-.241-1.865-.44-.752-.245-1.349-.374-1.297-.789.027-.216.325-.437.893-.663 3.498-1.524 5.83-2.529 6.998-3.014 3.332-1.386 4.025-1.627 4.476-1.635z"/>
                        </svg>
                        Connect Telegram — Earn 500 BUX
                      </button>
                    <% end %>
                  <% end %>
                </div>
              </div>

              <%!-- Join Group --%>
              <div class="pt-3 border-t border-gray-100">
                <div class="flex items-center gap-2 mb-1">
                  <p class="text-sm font-haas_medium_65 text-[#141414]">Blockster V2 Group</p>
                  <%= if @telegram_group_joined do %>
                    <span class="inline-flex items-center gap-1 px-2 py-0.5 bg-green-50 text-green-600 text-[10px] font-haas_medium_65 rounded-full">
                      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-3 h-3">
                        <path fill-rule="evenodd" d="M19.916 4.626a.75.75 0 0 1 .208 1.04l-9 13.5a.75.75 0 0 1-1.154.114l-6-6a.75.75 0 0 1 1.06-1.06l5.353 5.353 8.493-12.74a.75.75 0 0 1 1.04-.207Z" clip-rule="evenodd" />
                      </svg>
                      Joined
                    </span>
                  <% end %>
                </div>
                <%= if @telegram_group_joined do %>
                  <p class="text-xs text-gray-400 font-haas_roman_55 mb-3">You're a member of the Blockster Telegram group.</p>
                <% else %>
                  <p class="text-xs text-gray-400 font-haas_roman_55 mb-3">Join our Telegram group and earn <span class="text-[#141414] font-haas_medium_65">500 BUX</span>.</p>
                <% end %>
                <a
                  href="https://t.me/+7bIzOyrYBEc3OTdh"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="inline-flex items-center gap-2 px-4 py-2.5 bg-gray-900 text-white text-sm font-haas_medium_65 rounded-xl hover:bg-gray-800 transition-colors cursor-pointer"
                >
                  <%= if @telegram_group_joined, do: "Open Telegram Group", else: "Join & Earn 500 BUX" %>
                </a>
              </div>
            </div>
          </.section>

          <%!-- Per-Hub Settings --%>
          <%= if @followed_hubs != [] do %>
            <.section title="Hub Notifications" subtitle="Control notifications per hub you follow">
              <div class="space-y-3">
                <%= for entry <- @followed_hubs do %>
                  <div class="p-4 bg-[#F5F6FB] rounded-xl">
                    <div class="flex items-center gap-3 mb-3">
                      <%= if entry.hub.logo_url do %>
                        <img src={entry.hub.logo_url} class="w-9 h-9 rounded-xl object-cover" loading="lazy" />
                      <% else %>
                        <div class="w-9 h-9 rounded-xl bg-[#CAFC00] flex items-center justify-center">
                          <span class="text-sm font-haas_medium_65 text-black"><%= String.first(entry.hub.name) %></span>
                        </div>
                      <% end %>
                      <p class="text-sm font-haas_medium_65 text-[#141414]"><%= entry.hub.name %></p>
                    </div>
                    <div class="grid grid-cols-2 gap-2">
                      <.hub_toggle label="New posts" field="notify_new_posts" hub_id={entry.hub.id} checked={entry.follower.notify_new_posts} />
                      <.hub_toggle label="Events" field="notify_events" hub_id={entry.hub.id} checked={entry.follower.notify_events} />
                      <.hub_toggle label="Emails" field="email_notifications" hub_id={entry.hub.id} checked={entry.follower.email_notifications} />
                      <.hub_toggle label="In-app" field="in_app_notifications" hub_id={entry.hub.id} checked={entry.follower.in_app_notifications} />
                    </div>
                  </div>
                <% end %>
              </div>
            </.section>
          <% end %>

          <%!-- Unsubscribe All --%>
          <div class="mt-6 mb-8 p-5 bg-white rounded-xl border border-gray-100">
            <%= if @show_unsubscribe_confirm do %>
              <div class="flex items-start gap-3">
                <div class="w-9 h-9 rounded-xl bg-red-50 flex items-center justify-center flex-shrink-0">
                  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-5 h-5 text-red-500">
                    <path fill-rule="evenodd" d="M9.401 3.003c1.155-2 4.043-2 5.197 0l7.355 12.748c1.154 2-.29 4.5-2.599 4.5H4.645c-2.309 0-3.752-2.5-2.598-4.5L9.4 3.003ZM12 8.25a.75.75 0 0 1 .75.75v3.75a.75.75 0 0 1-1.5 0V9a.75.75 0 0 1 .75-.75Zm0 8.25a.75.75 0 1 0 0-1.5.75.75 0 0 0 0 1.5Z" clip-rule="evenodd" />
                  </svg>
                </div>
                <div class="flex-1">
                  <p class="text-sm font-haas_medium_65 text-red-600 mb-1">Are you sure?</p>
                  <p class="text-xs text-gray-400 font-haas_roman_55 mb-4">This will disable all email and SMS notifications. You can re-enable them later.</p>
                  <div class="flex gap-2">
                    <button
                      phx-click="confirm_unsubscribe_all"
                      class="px-4 py-2 bg-red-600 text-white text-xs font-haas_medium_65 rounded-lg hover:bg-red-700 transition-colors cursor-pointer"
                    >
                      Yes, unsubscribe
                    </button>
                    <button
                      phx-click="cancel_unsubscribe"
                      class="px-4 py-2 bg-gray-100 text-gray-600 text-xs font-haas_roman_55 rounded-lg hover:bg-gray-200 transition-colors cursor-pointer"
                    >
                      Cancel
                    </button>
                  </div>
                </div>
              </div>
            <% else %>
              <div class="flex items-center justify-between">
                <div>
                  <p class="text-sm font-haas_roman_55 text-gray-500">Want to stop all notifications?</p>
                </div>
                <button
                  phx-click="show_unsubscribe_confirm"
                  class="text-xs text-red-400 hover:text-red-600 font-haas_medium_65 cursor-pointer transition-colors"
                >
                  Unsubscribe all
                </button>
              </div>
            <% end %>
          </div>
        <% else %>
          <div class="flex flex-col items-center justify-center py-24 text-center">
            <div class="w-16 h-16 bg-gray-100 rounded-2xl flex items-center justify-center mb-4">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-8 h-8 text-gray-300">
                <path fill-rule="evenodd" d="M12 1.5a5.25 5.25 0 0 0-5.25 5.25v3a3 3 0 0 0-3 3v6.75a3 3 0 0 0 3 3h10.5a3 3 0 0 0 3-3v-6.75a3 3 0 0 0-3-3v-3c0-2.9-2.35-5.25-5.25-5.25Zm3.75 8.25v-3a3.75 3.75 0 1 0-7.5 0v3h7.5Z" clip-rule="evenodd" />
              </svg>
            </div>
            <p class="text-gray-400 font-haas_roman_55">Please log in to manage your notification settings.</p>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # ============ Components ============

  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  slot :inner_block, required: true

  defp section(assigns) do
    ~H"""
    <div class="mb-5 bg-white rounded-xl border border-gray-100 overflow-hidden">
      <div class="p-5">
        <div class="flex items-center gap-2 mb-0.5">
          <div class="w-1 h-4 bg-[#CAFC00] rounded-full"></div>
          <h2 class="text-base font-haas_medium_65 text-[#141414]"><%= @title %></h2>
        </div>
        <%= if @subtitle do %>
          <p class="text-xs text-gray-400 font-haas_roman_55 ml-3 mb-4"><%= @subtitle %></p>
        <% end %>
        <%= render_slot(@inner_block) %>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :description, :string, default: nil
  attr :field, :string, required: true
  attr :checked, :boolean, required: true

  defp toggle(assigns) do
    ~H"""
    <div class="flex items-center justify-between py-2.5 group/toggle">
      <div>
        <p class="text-sm font-haas_roman_55 text-[#141414]"><%= @label %></p>
        <%= if @description do %>
          <p class="text-[11px] text-gray-400 font-haas_roman_55"><%= @description %></p>
        <% end %>
      </div>
      <button
        phx-click="toggle_preference"
        phx-value-field={@field}
        class={"relative inline-flex h-7 w-12 items-center rounded-full transition-colors duration-200 cursor-pointer #{if @checked, do: "bg-gray-900", else: "bg-gray-200 group-hover/toggle:bg-gray-300"}"}
        role="switch"
        aria-checked={to_string(@checked)}
      >
        <span class={"inline-block h-5 w-5 transform rounded-full bg-white shadow-[0_1px_3px_rgba(0,0,0,0.1)] transition-transform duration-200 #{if @checked, do: "translate-x-6", else: "translate-x-0.5"}"}></span>
      </button>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :field, :string, required: true
  attr :hub_id, :integer, required: true
  attr :checked, :boolean, required: true

  defp hub_toggle(assigns) do
    ~H"""
    <button
      phx-click="toggle_hub_notification"
      phx-value-hub-id={@hub_id}
      phx-value-field={@field}
      class={"flex items-center gap-2 px-3 py-2 rounded-xl text-xs font-haas_roman_55 transition-all cursor-pointer #{if @checked, do: "bg-white text-[#141414] shadow-[0_1px_2px_rgba(0,0,0,0.04)]", else: "bg-transparent text-gray-400 hover:bg-white/50"}"}
    >
      <div class={"w-3.5 h-3.5 rounded-md border-2 transition-colors #{if @checked, do: "border-gray-900 bg-gray-900", else: "border-gray-300"}"}></div>
      <%= @label %>
    </button>
    """
  end

end
