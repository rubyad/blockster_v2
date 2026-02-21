defmodule BlocksterV2Web.NotificationSettingsLive.Index do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.Notifications
  alias BlocksterV2.Blog

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns[:current_user]

    if user do
      {:ok, prefs} = Notifications.get_or_create_preferences(user.id)
      followed_hubs = Blog.get_user_followed_hubs_with_settings(user.id)

      {:ok,
       socket
       |> assign(:page_title, "Notification Settings")
       |> assign(:preferences, prefs)
       |> assign(:followed_hubs, followed_hubs)
       |> assign(:show_unsubscribe_confirm, false)
       |> assign(:saved, false)}
    else
      {:ok,
       socket
       |> assign(:page_title, "Notification Settings")
       |> assign(:preferences, nil)
       |> assign(:followed_hubs, [])
       |> assign(:show_unsubscribe_confirm, false)
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

  def handle_event("update_max_emails", %{"value" => value}, socket) do
    user = socket.assigns.current_user
    if user do
      max_emails = String.to_integer(value)

      case Notifications.update_preferences(user.id, %{max_emails_per_day: max_emails}) do
        {:ok, updated_prefs} ->
          {:noreply,
           socket
           |> assign(:preferences, updated_prefs)
           |> assign(:saved, true)
           |> then(&schedule_saved_clear/1)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to update email limit")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("update_quiet_hours", %{"start" => start_str, "end" => end_str}, socket) do
    user = socket.assigns.current_user
    if user do
      quiet_start = parse_time(start_str)
      quiet_end = parse_time(end_str)

      attrs = %{quiet_hours_start: quiet_start, quiet_hours_end: quiet_end}

      case Notifications.update_preferences(user.id, attrs) do
        {:ok, updated_prefs} ->
          {:noreply,
           socket
           |> assign(:preferences, updated_prefs)
           |> assign(:saved, true)
           |> then(&schedule_saved_clear/1)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to update quiet hours")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("update_timezone", %{"timezone" => tz}, socket) do
    user = socket.assigns.current_user
    if user do
      case Notifications.update_preferences(user.id, %{timezone: tz}) do
        {:ok, updated_prefs} ->
          {:noreply,
           socket
           |> assign(:preferences, updated_prefs)
           |> assign(:saved, true)
           |> then(&schedule_saved_clear/1)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to update timezone")}
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

  # ============ Private Helpers ============

  defp schedule_saved_clear(socket) do
    if connected?(socket), do: Process.send_after(self(), :clear_saved, 2000)
    socket
  end

  defp parse_time(""), do: nil
  defp parse_time(nil), do: nil
  defp parse_time(str) do
    case Time.from_iso8601(str <> ":00") do
      {:ok, time} -> time
      _ -> nil
    end
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
          <%!-- Global Email Toggle --%>
          <.section title="Email Notifications" subtitle="Control which emails you receive">
            <.toggle
              label="Email notifications"
              description="Receive email notifications"
              field="email_enabled"
              checked={@preferences.email_enabled}
            />

            <%= if @preferences.email_enabled do %>
              <div class="mt-3 pt-3 border-t border-gray-100 space-y-1">
                <.toggle label="New articles" description="Articles from hubs you follow" field="email_hub_posts" checked={@preferences.email_hub_posts} />
                <.toggle label="Trending articles" description="Popular and featured content" field="email_new_articles" checked={@preferences.email_new_articles} />
                <.toggle label="Special offers" description="Shop deals and promotions" field="email_special_offers" checked={@preferences.email_special_offers} />
                <.toggle label="Daily digest" description="Morning summary of top content" field="email_daily_digest" checked={@preferences.email_daily_digest} />
                <.toggle label="Weekly roundup" description="Best of the week email" field="email_weekly_roundup" checked={@preferences.email_weekly_roundup} />
                <.toggle label="Referral prompts" description="Invitations to invite friends" field="email_referral_prompts" checked={@preferences.email_referral_prompts} />
                <.toggle label="Reward alerts" description="BUX milestones and earnings" field="email_reward_alerts" checked={@preferences.email_reward_alerts} />
                <.toggle label="Shop deals" description="New products and restocks" field="email_shop_deals" checked={@preferences.email_shop_deals} />
                <.toggle label="Account updates" description="Security and account notifications" field="email_account_updates" checked={@preferences.email_account_updates} />
                <.toggle label="Re-engagement" description="Content you may have missed" field="email_re_engagement" checked={@preferences.email_re_engagement} />
              </div>
            <% end %>
          </.section>

          <%!-- SMS Section --%>
          <.section title="SMS Notifications" subtitle="High-value alerts only — used sparingly">
            <.toggle
              label="SMS notifications"
              description="Receive text message alerts"
              field="sms_enabled"
              checked={@preferences.sms_enabled}
            />

            <%= if @preferences.sms_enabled do %>
              <div class="mt-3 pt-3 border-t border-gray-100 space-y-1">
                <.toggle label="Special offers" description="Flash sales and exclusive deals" field="sms_special_offers" checked={@preferences.sms_special_offers} />
                <.toggle label="Account alerts" description="Security and order updates" field="sms_account_alerts" checked={@preferences.sms_account_alerts} />
                <.toggle label="Milestone rewards" description="BUX milestone celebrations" field="sms_milestone_rewards" checked={@preferences.sms_milestone_rewards} />
              </div>
            <% end %>
          </.section>

          <%!-- In-App Section --%>
          <.section title="In-App Notifications" subtitle="Control how notifications appear while browsing">
            <.toggle label="In-app notifications" description="Show notification bell and dropdown" field="in_app_enabled" checked={@preferences.in_app_enabled} />
            <.toggle label="Toast pop-ups" description="Slide-in notifications for new alerts" field="in_app_toast_enabled" checked={@preferences.in_app_toast_enabled} />
            <.toggle label="Sound" description="Play a sound for new notifications" field="in_app_sound_enabled" checked={@preferences.in_app_sound_enabled} />
          </.section>

          <%!-- Frequency & Timing --%>
          <.section title="Frequency & Timing" subtitle="Control how often and when you're contacted">
            <%!-- Max emails per day slider --%>
            <div class="py-3">
              <div class="flex items-center justify-between mb-3">
                <div>
                  <p class="text-sm font-haas_medium_65 text-[#141414]">Max emails per day</p>
                  <p class="text-xs text-gray-400 font-haas_roman_55">Limit daily email volume</p>
                </div>
                <span class="text-sm font-haas_medium_65 text-black bg-[#CAFC00] w-8 h-8 rounded-lg flex items-center justify-center">
                  <%= @preferences.max_emails_per_day %>
                </span>
              </div>
              <input
                type="range"
                min="1"
                max="10"
                value={@preferences.max_emails_per_day}
                phx-change="update_max_emails"
                name="value"
                class="w-full h-2 bg-gray-200 rounded-lg appearance-none cursor-pointer accent-[#CAFC00]"
              />
              <div class="flex justify-between text-[10px] text-gray-300 font-haas_roman_55 mt-1.5">
                <span>1</span>
                <span>5</span>
                <span>10</span>
              </div>
            </div>

            <%!-- Quiet Hours --%>
            <div class="py-4 border-t border-gray-100">
              <div class="flex items-center gap-2 mb-3">
                <div class="w-7 h-7 rounded-lg bg-[#141414] flex items-center justify-center">
                  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-3.5 h-3.5 text-[#CAFC00]">
                    <path fill-rule="evenodd" d="M9.528 1.718a.75.75 0 0 1 .162.819A8.97 8.97 0 0 0 9 6a9 9 0 0 0 9 9 8.97 8.97 0 0 0 3.463-.69.75.75 0 0 1 .981.98 10.503 10.503 0 0 1-9.694 6.46c-5.799 0-10.5-4.701-10.5-10.5 0-4.368 2.667-8.112 6.46-9.694a.75.75 0 0 1 .818.162Z" clip-rule="evenodd" />
                  </svg>
                </div>
                <div>
                  <p class="text-sm font-haas_medium_65 text-[#141414]">Quiet hours</p>
                  <p class="text-xs text-gray-400 font-haas_roman_55">No notifications during these hours</p>
                </div>
              </div>
              <div class="bg-[#F5F6FB] rounded-xl p-4">
                <div class="flex items-center gap-3">
                  <div class="flex-1">
                    <label class="text-[10px] text-gray-400 uppercase tracking-wider font-haas_medium_65">From</label>
                    <input
                      type="time"
                      value={format_time_input(@preferences.quiet_hours_start)}
                      phx-blur="update_quiet_hours"
                      name="start"
                      phx-value-end={format_time_input(@preferences.quiet_hours_end)}
                      class="w-full mt-1 px-3 py-2.5 text-sm bg-white border border-gray-200 rounded-xl focus:ring-1 focus:ring-gray-400 focus:border-gray-400 outline-none font-haas_roman_55"
                    />
                  </div>
                  <div class="flex items-center justify-center w-8 h-8 mt-4">
                    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-4 h-4 text-gray-300">
                      <path fill-rule="evenodd" d="M16.72 7.72a.75.75 0 0 1 1.06 0l3.75 3.75a.75.75 0 0 1 0 1.06l-3.75 3.75a.75.75 0 1 1-1.06-1.06l2.47-2.47H3a.75.75 0 0 1 0-1.5h16.19l-2.47-2.47a.75.75 0 0 1 0-1.06Z" clip-rule="evenodd" />
                    </svg>
                  </div>
                  <div class="flex-1">
                    <label class="text-[10px] text-gray-400 uppercase tracking-wider font-haas_medium_65">To</label>
                    <input
                      type="time"
                      value={format_time_input(@preferences.quiet_hours_end)}
                      phx-blur="update_quiet_hours"
                      name="end"
                      phx-value-start={format_time_input(@preferences.quiet_hours_start)}
                      class="w-full mt-1 px-3 py-2.5 text-sm bg-white border border-gray-200 rounded-xl focus:ring-1 focus:ring-gray-400 focus:border-gray-400 outline-none font-haas_roman_55"
                    />
                  </div>
                </div>
              </div>
            </div>

            <%!-- Timezone --%>
            <div class="py-3 border-t border-gray-100">
              <p class="text-sm font-haas_medium_65 text-[#141414] mb-1">Timezone</p>
              <select
                phx-change="update_timezone"
                name="timezone"
                class="w-full mt-1 px-3 py-2.5 text-sm border border-gray-200 rounded-xl focus:ring-1 focus:ring-gray-400 focus:border-gray-400 outline-none bg-white cursor-pointer font-haas_roman_55"
              >
                <%= for tz <- common_timezones() do %>
                  <option value={tz} selected={@preferences.timezone == tz}><%= tz %></option>
                <% end %>
              </select>
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

  # ============ Helpers ============

  defp format_time_input(nil), do: ""
  defp format_time_input(%Time{} = time), do: Calendar.strftime(time, "%H:%M")
  defp format_time_input(_), do: ""

  defp common_timezones do
    [
      "UTC",
      "US/Eastern",
      "US/Central",
      "US/Mountain",
      "US/Pacific",
      "US/Alaska",
      "US/Hawaii",
      "Europe/London",
      "Europe/Paris",
      "Europe/Berlin",
      "Europe/Moscow",
      "Asia/Dubai",
      "Asia/Kolkata",
      "Asia/Singapore",
      "Asia/Tokyo",
      "Asia/Shanghai",
      "Australia/Sydney",
      "Pacific/Auckland"
    ]
  end
end
