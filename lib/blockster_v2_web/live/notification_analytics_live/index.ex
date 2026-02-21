defmodule BlocksterV2Web.NotificationAnalyticsLive.Index do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.Notifications
  alias BlocksterV2.Notifications.EngagementScorer

  @impl true
  def mount(_params, _session, socket) do
    period = 30

    {:ok,
     socket
     |> assign(:page_title, "Notification Analytics")
     |> assign(:period, period)
     |> load_analytics(period)}
  end

  @impl true
  def handle_event("set_period", %{"period" => period_str}, socket) do
    period = String.to_integer(period_str)

    {:noreply,
     socket
     |> assign(:period, period)
     |> load_analytics(period)}
  end

  defp load_analytics(socket, period) do
    stats = EngagementScorer.aggregate_stats(period)
    daily_volume = EngagementScorer.daily_email_volume(period)
    time_dist = EngagementScorer.send_time_distribution(period)
    channels = EngagementScorer.channel_comparison(period)
    top_campaigns = Notifications.top_campaigns(5)
    hub_stats = Notifications.hub_subscription_stats()

    socket
    |> assign(:stats, stats)
    |> assign(:daily_volume, daily_volume)
    |> assign(:time_distribution, time_dist)
    |> assign(:channels, channels)
    |> assign(:top_campaigns, top_campaigns)
    |> assign(:hub_stats, hub_stats)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-[#F5F6FB]">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 pt-24 pb-12">
        <%!-- Header --%>
        <div class="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 mb-8">
          <div>
            <h1 class="text-3xl font-haas_medium_65 text-[#141414]">Notification Analytics</h1>
            <p class="text-gray-500 mt-1 font-haas_roman_55">Engagement metrics and delivery performance</p>
          </div>
          <div class="flex gap-2">
            <% periods = [{7, "7d"}, {14, "14d"}, {30, "30d"}, {90, "90d"}] %>
            <%= for {days, label} <- periods do %>
              <button
                phx-click="set_period"
                phx-value-period={days}
                class={"px-4 py-2 rounded-xl text-sm font-haas_medium_65 cursor-pointer transition-colors #{if @period == days, do: "bg-[#141414] text-white", else: "bg-white text-gray-600 hover:bg-gray-50 border border-gray-200"}"}
              >
                <%= label %>
              </button>
            <% end %>
          </div>
        </div>

        <%!-- Overview Stats --%>
        <div class="grid grid-cols-2 md:grid-cols-4 gap-4 mb-8">
          <.stat_card label="Emails Sent" value={@stats.total_emails_sent} color="blue" />
          <.stat_card label="Open Rate" value={format_pct(@stats.overall_open_rate)} color="green" />
          <.stat_card label="Click Rate" value={format_pct(@stats.overall_click_rate)} color="indigo" />
          <.stat_card label="Bounce Rate" value={format_pct(@stats.overall_bounce_rate)} color="red" />
        </div>

        <div class="grid grid-cols-2 md:grid-cols-4 gap-4 mb-8">
          <.stat_card label="In-App Delivered" value={@stats.total_in_app_delivered} color="emerald" />
          <.stat_card label="In-App Read Rate" value={format_pct(@stats.in_app_read_rate)} color="teal" />
          <.stat_card label="Emails Bounced" value={@stats.total_emails_bounced} color="amber" />
          <.stat_card label="Unsubscribed" value={@stats.total_emails_unsubscribed} color="rose" />
        </div>

        <%!-- Channel Comparison + Daily Volume --%>
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-8">
          <%!-- Channel Comparison --%>
          <div class="bg-white rounded-2xl shadow-sm border border-gray-100 p-6">
            <h3 class="text-lg font-haas_medium_65 text-[#141414] mb-5">Channel Comparison</h3>
            <div class="space-y-5">
              <%= for ch <- @channels do %>
                <div>
                  <div class="flex items-center justify-between mb-2">
                    <div class="flex items-center gap-2">
                      <div class={"w-3 h-3 rounded-full #{channel_dot_color(ch.channel)}"}></div>
                      <span class="text-sm font-haas_medium_65 text-[#141414] capitalize"><%= ch.channel %></span>
                    </div>
                    <span class="text-sm font-haas_roman_55 text-gray-500"><%= format_number(ch.sent) %> sent · <%= format_pct(ch.rate) %> engagement</span>
                  </div>
                  <div class="w-full bg-gray-100 rounded-full h-3 overflow-hidden">
                    <div class={"h-full rounded-full transition-all #{channel_bar_color(ch.channel)}"} style={"width: #{max(ch.rate * 100, 1)}%"}></div>
                  </div>
                </div>
              <% end %>
            </div>
          </div>

          <%!-- Daily Volume Chart (ASCII bar chart) --%>
          <div class="bg-white rounded-2xl shadow-sm border border-gray-100 p-6">
            <h3 class="text-lg font-haas_medium_65 text-[#141414] mb-5">Daily Email Volume</h3>
            <%= if Enum.empty?(@daily_volume) do %>
              <div class="text-center py-8">
                <p class="text-sm text-gray-500 font-haas_roman_55">No email data for this period</p>
              </div>
            <% else %>
              <div class="space-y-2 max-h-64 overflow-y-auto">
                <% max_sent = Enum.max_by(@daily_volume, & &1.sent, fn -> %{sent: 1} end).sent %>
                <%= for day <- Enum.take(@daily_volume, -14) do %>
                  <div class="flex items-center gap-3">
                    <span class="text-xs font-haas_roman_55 text-gray-500 w-16 shrink-0"><%= format_short_date(day.date) %></span>
                    <div class="flex-1 bg-gray-100 rounded-full h-5 overflow-hidden relative">
                      <div class="h-full bg-blue-500 rounded-full transition-all" style={"width: #{bar_width(day.sent, max_sent)}%"}></div>
                      <div class="h-full bg-green-400 rounded-full absolute top-0 left-0" style={"width: #{bar_width(day.opened, max_sent)}%; opacity: 0.7"}></div>
                    </div>
                    <span class="text-xs font-haas_roman_55 text-gray-500 w-10 text-right shrink-0"><%= day.sent %></span>
                  </div>
                <% end %>
              </div>
              <div class="flex items-center gap-4 mt-4 pt-3 border-t border-gray-100">
                <div class="flex items-center gap-2"><div class="w-3 h-3 rounded-full bg-blue-500"></div><span class="text-xs font-haas_roman_55 text-gray-500">Sent</span></div>
                <div class="flex items-center gap-2"><div class="w-3 h-3 rounded-full bg-green-400"></div><span class="text-xs font-haas_roman_55 text-gray-500">Opened</span></div>
              </div>
            <% end %>
          </div>
        </div>

        <%!-- Send Time Heatmap + Top Campaigns --%>
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-8">
          <%!-- Send Time Heatmap --%>
          <div class="bg-white rounded-2xl shadow-sm border border-gray-100 p-6">
            <h3 class="text-lg font-haas_medium_65 text-[#141414] mb-5">Send Time Heatmap</h3>
            <%= if Enum.empty?(@time_distribution) do %>
              <div class="text-center py-8">
                <p class="text-sm text-gray-500 font-haas_roman_55">No send time data yet</p>
              </div>
            <% else %>
              <div class="grid grid-cols-6 gap-1.5">
                <% max_heat = Enum.max_by(@time_distribution, & &1.sent, fn -> %{sent: 1} end).sent %>
                <%= for hour <- 0..23 do %>
                  <% entry = Enum.find(@time_distribution, %{sent: 0, open_rate: 0.0}, &(&1.hour == hour)) %>
                  <div
                    class={"rounded-lg p-2 text-center cursor-default #{heat_color(entry.sent, max_heat)}"}
                    title={"#{hour}:00 — #{entry.sent} sent, #{format_pct(entry.open_rate)} open rate"}
                  >
                    <div class="text-xs font-haas_medium_65"><%= format_hour(hour) %></div>
                    <div class="text-[10px] font-haas_roman_55 opacity-75"><%= entry.sent %></div>
                  </div>
                <% end %>
              </div>
              <div class="flex items-center justify-between mt-4 pt-3 border-t border-gray-100">
                <span class="text-xs font-haas_roman_55 text-gray-400">Low volume</span>
                <div class="flex gap-1">
                  <div class="w-4 h-4 rounded bg-[#F5F6FB]"></div>
                  <div class="w-4 h-4 rounded bg-[#CAFC00]/20"></div>
                  <div class="w-4 h-4 rounded bg-[#CAFC00]/40"></div>
                  <div class="w-4 h-4 rounded bg-[#CAFC00]/70"></div>
                  <div class="w-4 h-4 rounded bg-[#CAFC00]"></div>
                </div>
                <span class="text-xs font-haas_roman_55 text-gray-400">High volume</span>
              </div>
            <% end %>
          </div>

          <%!-- Top Campaigns --%>
          <div class="bg-white rounded-2xl shadow-sm border border-gray-100 p-6">
            <h3 class="text-lg font-haas_medium_65 text-[#141414] mb-5">Top Campaigns</h3>
            <%= if Enum.empty?(@top_campaigns) do %>
              <div class="text-center py-8">
                <p class="text-sm text-gray-500 font-haas_roman_55">No sent campaigns yet</p>
              </div>
            <% else %>
              <div class="space-y-3">
                <%= for {campaign, idx} <- Enum.with_index(@top_campaigns) do %>
                  <.link navigate={~p"/admin/notifications/campaigns/#{campaign.id}"} class="flex items-center gap-4 p-3 rounded-xl hover:bg-[#F5F6FB] transition-colors cursor-pointer">
                    <div class={"w-8 h-8 rounded-lg flex items-center justify-center text-sm font-haas_medium_65 #{if idx == 0, do: "bg-[#CAFC00] text-black", else: "bg-gray-100 text-gray-600"}"}>
                      <%= idx + 1 %>
                    </div>
                    <div class="flex-1 min-w-0">
                      <div class="text-sm font-haas_medium_65 text-[#141414] truncate"><%= campaign.name %></div>
                      <div class="text-xs text-gray-500 font-haas_roman_55"><%= campaign.target_audience %> · <%= format_date(campaign.inserted_at) %></div>
                    </div>
                    <div class="text-right shrink-0">
                      <div class="text-sm font-haas_medium_65 text-green-600"><%= campaign.emails_opened %> opens</div>
                      <div class="text-xs text-gray-500 font-haas_roman_55"><%= open_rate(campaign) %> rate</div>
                    </div>
                  </.link>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>

        <%!-- Hub Subscription Analytics --%>
        <div class="bg-white rounded-2xl shadow-sm border border-gray-100 p-6">
          <h3 class="text-lg font-haas_medium_65 text-[#141414] mb-5">Hub Subscription Analytics</h3>
          <%= if Enum.empty?(@hub_stats) do %>
            <div class="text-center py-8">
              <p class="text-sm text-gray-500 font-haas_roman_55">No hub subscriptions yet</p>
            </div>
          <% else %>
            <div class="overflow-x-auto">
              <table class="min-w-full">
                <thead class="bg-[#F5F6FB]">
                  <tr>
                    <th class="px-4 py-3 text-left text-xs font-haas_medium_65 text-gray-500 uppercase tracking-wider">Hub</th>
                    <th class="px-4 py-3 text-right text-xs font-haas_medium_65 text-gray-500 uppercase tracking-wider">Followers</th>
                    <th class="px-4 py-3 text-right text-xs font-haas_medium_65 text-gray-500 uppercase tracking-wider">Notify Enabled</th>
                    <th class="px-4 py-3 text-right text-xs font-haas_medium_65 text-gray-500 uppercase tracking-wider">Opt-in Rate</th>
                    <th class="px-4 py-3 text-left text-xs font-haas_medium_65 text-gray-500 uppercase tracking-wider">Distribution</th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-gray-100">
                  <% max_followers = Enum.max_by(@hub_stats, & &1.follower_count, fn -> %{follower_count: 1} end).follower_count %>
                  <%= for hub <- @hub_stats do %>
                    <tr class="hover:bg-[#F5F6FB]/50 transition-colors">
                      <td class="px-4 py-3">
                        <span class="text-sm font-haas_medium_65 text-[#141414]"><%= hub.hub_name %></span>
                      </td>
                      <td class="px-4 py-3 text-right text-sm font-haas_roman_55 text-gray-900"><%= hub.follower_count %></td>
                      <td class="px-4 py-3 text-right text-sm font-haas_roman_55 text-green-600"><%= hub.notify_enabled %></td>
                      <td class="px-4 py-3 text-right text-sm font-haas_roman_55 text-gray-500"><%= hub_opt_in_rate(hub) %></td>
                      <td class="px-4 py-3">
                        <div class="w-full bg-gray-100 rounded-full h-2 max-w-[120px]">
                          <div class="h-full bg-[#CAFC00] rounded-full" style={"width: #{bar_width(hub.follower_count, max_followers)}%"}></div>
                        </div>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # ============ Components ============

  defp stat_card(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl shadow-sm border border-gray-100 p-5">
      <div class="flex items-center gap-2 mb-3">
        <div class={"w-2.5 h-2.5 rounded-full bg-#{@color}-500"}></div>
        <span class="text-xs text-gray-500 font-haas_medium_65 uppercase tracking-wider"><%= @label %></span>
      </div>
      <div class="text-2xl font-haas_medium_65 text-[#141414]">
        <%= if is_binary(@value), do: @value, else: format_number(@value) %>
      </div>
    </div>
    """
  end

  # ============ Helpers ============

  defp format_number(n) when is_integer(n) and n >= 10_000, do: "#{Float.round(n / 1000, 1)}k"
  defp format_number(n) when is_integer(n), do: Integer.to_string(n)
  defp format_number(n) when is_float(n), do: Float.round(n, 2) |> to_string()
  defp format_number(n), do: to_string(n)

  defp format_pct(rate) when is_float(rate), do: "#{Float.round(rate * 100, 1)}%"
  defp format_pct(_), do: "0%"

  defp format_date(nil), do: "—"
  defp format_date(dt), do: Calendar.strftime(dt, "%b %d")

  defp format_short_date(date) when is_struct(date, Date), do: Calendar.strftime(date, "%m/%d")
  defp format_short_date(date) when is_binary(date), do: date
  defp format_short_date(_), do: "—"

  defp format_hour(h) when h == 0, do: "12a"
  defp format_hour(h) when h < 12, do: "#{h}a"
  defp format_hour(12), do: "12p"
  defp format_hour(h), do: "#{h - 12}p"

  defp bar_width(_value, 0), do: 0
  defp bar_width(value, max), do: min(value / max * 100, 100) |> Float.round(1)

  defp channel_dot_color("email"), do: "bg-blue-500"
  defp channel_dot_color("in_app"), do: "bg-green-500"
  defp channel_dot_color("sms"), do: "bg-purple-500"
  defp channel_dot_color(_), do: "bg-gray-500"

  defp channel_bar_color("email"), do: "bg-blue-500"
  defp channel_bar_color("in_app"), do: "bg-green-500"
  defp channel_bar_color("sms"), do: "bg-purple-500"
  defp channel_bar_color(_), do: "bg-gray-400"

  defp heat_color(0, _max), do: "bg-[#F5F6FB] text-gray-400"
  defp heat_color(sent, max) when max > 0 do
    ratio = sent / max
    cond do
      ratio >= 0.75 -> "bg-[#CAFC00] text-black"
      ratio >= 0.50 -> "bg-[#CAFC00]/70 text-black"
      ratio >= 0.25 -> "bg-[#CAFC00]/40 text-gray-700"
      ratio > 0 -> "bg-[#CAFC00]/20 text-gray-600"
      true -> "bg-[#F5F6FB] text-gray-400"
    end
  end
  defp heat_color(_, _), do: "bg-[#F5F6FB] text-gray-400"

  defp open_rate(%{emails_sent: sent, emails_opened: opened}) when sent > 0 do
    "#{Float.round(opened / sent * 100, 1)}%"
  end
  defp open_rate(_), do: "0%"

  defp hub_opt_in_rate(%{follower_count: 0}), do: "0%"
  defp hub_opt_in_rate(%{follower_count: fc, notify_enabled: ne}) do
    "#{Float.round(ne / fc * 100, 1)}%"
  end
end
