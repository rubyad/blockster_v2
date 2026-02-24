defmodule BlocksterV2Web.CampaignAdminLive.Show do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.Notifications

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    campaign = Notifications.get_campaign!(id)
    stats = Notifications.get_campaign_stats(campaign.id)
    recipients = Notifications.get_campaign_recipients(campaign.id)

    if connected?(socket) do
      :timer.send_interval(30_000, self(), :refresh_stats)
    end

    {:ok,
     socket
     |> assign(:page_title, campaign.name)
     |> assign(:campaign, campaign)
     |> assign(:stats, stats)
     |> assign(:recipients, recipients)
     |> assign(:tab, "overview")}
  end

  @impl true
  def handle_info(:refresh_stats, socket) do
    stats = Notifications.get_campaign_stats(socket.assigns.campaign.id)
    campaign = Notifications.get_campaign!(socket.assigns.campaign.id)
    recipients = Notifications.get_campaign_recipients(campaign.id)
    {:noreply, assign(socket, stats: stats, campaign: campaign, recipients: recipients)}
  end

  @impl true
  def handle_event("set_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :tab, tab)}
  end

  def handle_event("send_campaign", _params, socket) do
    campaign = socket.assigns.campaign

    if campaign.status in ["draft", "scheduled"] do
      BlocksterV2.Workers.PromoEmailWorker.enqueue_campaign(campaign.id)
      campaign = Notifications.get_campaign!(campaign.id)

      {:noreply,
       socket
       |> assign(:campaign, campaign)
       |> put_flash(:info, "Campaign is being sent to all recipients!")}
    else
      {:noreply, put_flash(socket, :error, "Campaign has already been sent.")}
    end
  end

  def handle_event("cancel_campaign", _params, socket) do
    case Notifications.update_campaign_status(socket.assigns.campaign, "cancelled") do
      {:ok, campaign} ->
        {:noreply, socket |> assign(:campaign, campaign) |> put_flash(:info, "Campaign cancelled.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to cancel campaign.")}
    end
  end

  def handle_event("send_test", _params, socket) do
    campaign = socket.assigns.campaign
    user = socket.assigns.current_user

    if user.email do
      prefs = Notifications.get_preferences(user.id)
      token = if prefs, do: prefs.unsubscribe_token, else: ""

      email =
        BlocksterV2.Notifications.EmailBuilder.promotional(
          user.email,
          user.username || user.email,
          token,
          %{
            title: campaign.title || campaign.subject,
            body: campaign.body || campaign.plain_text_body || "",
            image_url: campaign.image_url,
            action_url: campaign.action_url,
            action_label: campaign.action_label
          }
        )

      case BlocksterV2.Mailer.deliver(email) do
        {:ok, _} -> {:noreply, put_flash(socket, :info, "Test email sent to #{user.email}")}
        {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to send test email")}
      end
    else
      {:noreply, put_flash(socket, :error, "No email address on your account")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-[#F5F6FB]">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 pt-24 pb-12">
        <%!-- Header --%>
        <div class="flex items-start justify-between mb-8">
          <div class="flex items-center gap-4">
            <.link navigate={~p"/admin/notifications/campaigns"} class="w-10 h-10 bg-white rounded-xl flex items-center justify-center shadow-sm border border-gray-100 hover:bg-gray-50 cursor-pointer">
              <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 text-gray-600" viewBox="0 0 20 20" fill="currentColor"><path fill-rule="evenodd" d="M9.707 16.707a1 1 0 01-1.414 0l-6-6a1 1 0 010-1.414l6-6a1 1 0 011.414 1.414L5.414 9H17a1 1 0 110 2H5.414l4.293 4.293a1 1 0 010 1.414z" clip-rule="evenodd" /></svg>
            </.link>
            <div>
              <h1 class="text-2xl font-haas_medium_65 text-[#141414]"><%= @campaign.name %></h1>
              <div class="flex items-center gap-3 mt-1">
                <%= status_badge(@campaign.status) %>
                <span class="text-sm text-gray-500 font-haas_roman_55"><%= @campaign.type %> · <%= @campaign.target_audience %></span>
              </div>
            </div>
          </div>
          <div class="flex gap-3">
            <button phx-click="send_test" class="px-4 py-2.5 bg-white border border-gray-200 rounded-xl text-sm font-haas_medium_65 text-gray-600 hover:bg-gray-50 cursor-pointer">
              Send Test
            </button>
            <%= if @campaign.status in ["draft", "scheduled"] do %>
              <button phx-click="send_campaign" data-confirm="Send this campaign to all recipients now?" class="px-4 py-2.5 bg-gray-900 rounded-xl text-sm font-haas_medium_65 text-white hover:bg-gray-800 cursor-pointer">
                Send Now
              </button>
              <.link navigate={~p"/admin/notifications/campaigns/#{@campaign.id}/edit"} class="px-4 py-2.5 bg-white border border-gray-200 rounded-xl text-sm font-haas_medium_65 text-gray-600 hover:bg-gray-50 cursor-pointer">
                Edit
              </.link>
              <button phx-click="cancel_campaign" data-confirm="Cancel this campaign?" class="px-4 py-2.5 bg-red-50 border border-red-200 rounded-xl text-sm font-haas_medium_65 text-red-700 hover:bg-red-100 cursor-pointer">
                Cancel
              </button>
            <% end %>
          </div>
        </div>

        <%!-- Stats Cards --%>
        <div class="grid grid-cols-2 md:grid-cols-4 gap-4 mb-8">
          <.stat_card label="Recipients" value={@campaign.total_recipients} icon="users" />
          <.stat_card label="Emails Sent" value={@stats.email.sent} icon="email" />
          <.stat_card label="Emails Opened" value={@stats.email.opened} icon="open" suffix={open_rate_text(@stats.email.opened, @stats.email.sent)} />
          <.stat_card label="Emails Clicked" value={@stats.email.clicked} icon="click" suffix={click_rate_text(@stats.email.clicked, @stats.email.sent)} />
        </div>

        <%!-- Tabs --%>
        <div class="flex gap-2 mb-6">
          <% tabs = [{"overview", "Overview"}, {"email", "Email Stats"}, {"in_app", "In-App Stats"}, {"recipients", "Recipients (#{length(@recipients)})"}, {"content", "Content"}] %>
          <%= for {value, label} <- tabs do %>
            <button
              phx-click="set_tab"
              phx-value-tab={value}
              class={"px-4 py-2 rounded-xl text-sm font-haas_medium_65 cursor-pointer transition-colors #{if @tab == value, do: "bg-[#141414] text-white", else: "bg-white text-gray-600 hover:bg-gray-50 border border-gray-200"}"}
            >
              <%= label %>
            </button>
          <% end %>
        </div>

        <%!-- Tab Content --%>
        <div class="bg-white rounded-2xl shadow-sm border border-gray-100 p-8">
          <%= case @tab do %>
            <% "overview" -> %>
              <.tab_overview campaign={@campaign} stats={@stats} />
            <% "email" -> %>
              <.tab_email stats={@stats} campaign={@campaign} />
            <% "in_app" -> %>
              <.tab_in_app stats={@stats} />
            <% "recipients" -> %>
              <.tab_recipients recipients={@recipients} />
            <% "content" -> %>
              <.tab_content campaign={@campaign} />
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # ============ Components ============

  defp stat_card(assigns) do
    assigns = assign_new(assigns, :suffix, fn -> nil end)

    ~H"""
    <div class="bg-white rounded-2xl shadow-sm border border-gray-100 p-5">
      <div class="flex items-center gap-3 mb-3">
        <div class={"w-10 h-10 rounded-lg flex items-center justify-center #{icon_bg(@icon)}"}>
          <.stat_icon name={@icon} />
        </div>
        <span class="text-xs text-gray-500 font-haas_medium_65 uppercase tracking-wider"><%= @label %></span>
      </div>
      <div class="text-2xl font-haas_medium_65 text-[#141414]"><%= format_number(@value) %></div>
      <%= if @suffix do %>
        <div class="text-xs text-gray-500 font-haas_roman_55 mt-1"><%= @suffix %></div>
      <% end %>
    </div>
    """
  end

  defp tab_overview(assigns) do
    ~H"""
    <div class="space-y-8">
      <div>
        <h3 class="text-lg font-haas_medium_65 text-[#141414] mb-4">Campaign Details</h3>
        <div class="grid grid-cols-2 md:grid-cols-3 gap-4">
          <div class="p-4 bg-[#F5F6FB] rounded-xl">
            <div class="text-xs text-gray-500 font-haas_roman_55 mb-1">Status</div>
            <%= status_badge(@campaign.status) %>
          </div>
          <div class="p-4 bg-[#F5F6FB] rounded-xl">
            <div class="text-xs text-gray-500 font-haas_roman_55 mb-1">Type</div>
            <div class="text-sm font-haas_medium_65 text-[#141414]"><%= @campaign.type %></div>
          </div>
          <div class="p-4 bg-[#F5F6FB] rounded-xl">
            <div class="text-xs text-gray-500 font-haas_roman_55 mb-1">Audience</div>
            <div class="text-sm font-haas_medium_65 text-[#141414]"><%= @campaign.target_audience %></div>
          </div>
          <div class="p-4 bg-[#F5F6FB] rounded-xl">
            <div class="text-xs text-gray-500 font-haas_roman_55 mb-1">Channels</div>
            <div class="flex gap-1.5 mt-1">
              <%= if @campaign.send_email do %><span class="px-2 py-0.5 bg-blue-50 text-blue-700 text-xs rounded-md font-haas_medium_65">Email</span><% end %>
              <%= if @campaign.send_in_app do %><span class="px-2 py-0.5 bg-green-50 text-green-700 text-xs rounded-md font-haas_medium_65">In-App</span><% end %>
              <%= if @campaign.send_sms do %><span class="px-2 py-0.5 bg-purple-50 text-purple-700 text-xs rounded-md font-haas_medium_65">SMS</span><% end %>
            </div>
          </div>
          <div class="p-4 bg-[#F5F6FB] rounded-xl">
            <div class="text-xs text-gray-500 font-haas_roman_55 mb-1">Created</div>
            <div class="text-sm font-haas_medium_65 text-[#141414]"><%= format_datetime(@campaign.inserted_at) %></div>
          </div>
          <div class="p-4 bg-[#F5F6FB] rounded-xl">
            <div class="text-xs text-gray-500 font-haas_roman_55 mb-1"><%= if @campaign.sent_at, do: "Sent At", else: "Scheduled For" %></div>
            <div class="text-sm font-haas_medium_65 text-[#141414]"><%= format_datetime(@campaign.sent_at || @campaign.scheduled_at) %></div>
          </div>
        </div>
      </div>

      <div>
        <h3 class="text-lg font-haas_medium_65 text-[#141414] mb-4">Performance Summary</h3>
        <div class="grid grid-cols-3 gap-4">
          <div class="p-4 bg-[#F5F6FB] rounded-xl text-center">
            <div class="text-2xl font-haas_medium_65 text-[#141414]"><%= format_rate(@stats.email.opened, @stats.email.sent) %></div>
            <div class="text-xs text-gray-500 font-haas_roman_55 mt-1">Open Rate</div>
          </div>
          <div class="p-4 bg-[#F5F6FB] rounded-xl text-center">
            <div class="text-2xl font-haas_medium_65 text-[#141414]"><%= format_rate(@stats.email.clicked, @stats.email.sent) %></div>
            <div class="text-xs text-gray-500 font-haas_roman_55 mt-1">Click Rate</div>
          </div>
          <div class="p-4 bg-[#F5F6FB] rounded-xl text-center">
            <div class="text-2xl font-haas_medium_65 text-[#141414]"><%= format_rate(@stats.email.bounced, @stats.email.sent) %></div>
            <div class="text-xs text-gray-500 font-haas_roman_55 mt-1">Bounce Rate</div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp tab_email(assigns) do
    ~H"""
    <div class="space-y-6">
      <h3 class="text-lg font-haas_medium_65 text-[#141414]">Email Performance</h3>

      <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
        <div class="p-4 bg-[#F5F6FB] rounded-xl">
          <div class="text-xs text-gray-500 font-haas_roman_55 mb-1">Sent</div>
          <div class="text-xl font-haas_medium_65 text-[#141414]"><%= format_number(@stats.email.sent) %></div>
        </div>
        <div class="p-4 bg-[#F5F6FB] rounded-xl">
          <div class="text-xs text-gray-500 font-haas_roman_55 mb-1">Opened</div>
          <div class="text-xl font-haas_medium_65 text-green-600"><%= format_number(@stats.email.opened) %></div>
          <div class="text-xs text-gray-500 font-haas_roman_55"><%= format_rate(@stats.email.opened, @stats.email.sent) %></div>
        </div>
        <div class="p-4 bg-[#F5F6FB] rounded-xl">
          <div class="text-xs text-gray-500 font-haas_roman_55 mb-1">Clicked</div>
          <div class="text-xl font-haas_medium_65 text-blue-600"><%= format_number(@stats.email.clicked) %></div>
          <div class="text-xs text-gray-500 font-haas_roman_55"><%= format_rate(@stats.email.clicked, @stats.email.sent) %></div>
        </div>
        <div class="p-4 bg-[#F5F6FB] rounded-xl">
          <div class="text-xs text-gray-500 font-haas_roman_55 mb-1">Bounced</div>
          <div class="text-xl font-haas_medium_65 text-red-600"><%= format_number(@stats.email.bounced) %></div>
          <div class="text-xs text-gray-500 font-haas_roman_55"><%= format_rate(@stats.email.bounced, @stats.email.sent) %></div>
        </div>
      </div>

      <%!-- Email Funnel --%>
      <div>
        <h4 class="text-sm font-haas_medium_65 text-gray-600 mb-3">Delivery Funnel</h4>
        <div class="space-y-3">
          <.funnel_bar label="Sent" value={@stats.email.sent} max={max(@campaign.total_recipients, 1)} color="bg-gray-400" />
          <.funnel_bar label="Opened" value={@stats.email.opened} max={max(@stats.email.sent, 1)} color="bg-green-500" />
          <.funnel_bar label="Clicked" value={@stats.email.clicked} max={max(@stats.email.sent, 1)} color="bg-blue-500" />
        </div>
      </div>
    </div>
    """
  end

  defp tab_in_app(assigns) do
    ~H"""
    <div class="space-y-6">
      <h3 class="text-lg font-haas_medium_65 text-[#141414]">In-App Notifications</h3>

      <div class="grid grid-cols-3 gap-4">
        <div class="p-4 bg-[#F5F6FB] rounded-xl">
          <div class="text-xs text-gray-500 font-haas_roman_55 mb-1">Delivered</div>
          <div class="text-xl font-haas_medium_65 text-[#141414]"><%= format_number(@stats.in_app.delivered) %></div>
        </div>
        <div class="p-4 bg-[#F5F6FB] rounded-xl">
          <div class="text-xs text-gray-500 font-haas_roman_55 mb-1">Read</div>
          <div class="text-xl font-haas_medium_65 text-green-600"><%= format_number(@stats.in_app.read) %></div>
          <div class="text-xs text-gray-500 font-haas_roman_55"><%= format_rate(@stats.in_app.read, @stats.in_app.delivered) %></div>
        </div>
        <div class="p-4 bg-[#F5F6FB] rounded-xl">
          <div class="text-xs text-gray-500 font-haas_roman_55 mb-1">Clicked</div>
          <div class="text-xl font-haas_medium_65 text-blue-600"><%= format_number(@stats.in_app.clicked) %></div>
          <div class="text-xs text-gray-500 font-haas_roman_55"><%= format_rate(@stats.in_app.clicked, @stats.in_app.delivered) %></div>
        </div>
      </div>

      <%!-- In-App Funnel --%>
      <div>
        <h4 class="text-sm font-haas_medium_65 text-gray-600 mb-3">Engagement Funnel</h4>
        <div class="space-y-3">
          <.funnel_bar label="Delivered" value={@stats.in_app.delivered} max={max(@campaign.total_recipients, 1)} color="bg-gray-400" />
          <.funnel_bar label="Read" value={@stats.in_app.read} max={max(@stats.in_app.delivered, 1)} color="bg-green-500" />
          <.funnel_bar label="Clicked" value={@stats.in_app.clicked} max={max(@stats.in_app.delivered, 1)} color="bg-blue-500" />
        </div>
      </div>
    </div>
    """
  end

  defp tab_content(assigns) do
    ~H"""
    <div class="space-y-6">
      <h3 class="text-lg font-haas_medium_65 text-[#141414]">Campaign Content</h3>

      <div class="space-y-4">
        <div class="p-4 bg-[#F5F6FB] rounded-xl">
          <div class="text-xs text-gray-500 font-haas_roman_55 mb-1">Subject</div>
          <div class="text-sm font-haas_medium_65 text-[#141414]"><%= @campaign.subject || "—" %></div>
        </div>
        <div class="p-4 bg-[#F5F6FB] rounded-xl">
          <div class="text-xs text-gray-500 font-haas_roman_55 mb-1">Title</div>
          <div class="text-sm font-haas_medium_65 text-[#141414]"><%= @campaign.title || "—" %></div>
        </div>
        <div class="p-4 bg-[#F5F6FB] rounded-xl">
          <div class="text-xs text-gray-500 font-haas_roman_55 mb-1">Body</div>
          <div class="text-sm font-haas_roman_55 text-gray-700 whitespace-pre-wrap"><%= @campaign.body || @campaign.plain_text_body || "—" %></div>
        </div>
        <%= if @campaign.image_url do %>
          <div class="p-4 bg-[#F5F6FB] rounded-xl">
            <div class="text-xs text-gray-500 font-haas_roman_55 mb-2">Image</div>
            <img src={@campaign.image_url} class="max-w-xs rounded-lg" />
          </div>
        <% end %>
        <%= if @campaign.action_url do %>
          <div class="p-4 bg-[#F5F6FB] rounded-xl">
            <div class="text-xs text-gray-500 font-haas_roman_55 mb-1">Action</div>
            <div class="text-sm font-haas_roman_55 text-blue-600"><%= @campaign.action_label || "Learn More" %> → <%= @campaign.action_url %></div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp tab_recipients(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex items-center justify-between">
        <h3 class="text-lg font-haas_medium_65 text-[#141414]">Recipients</h3>
        <span class="text-sm text-gray-500 font-haas_roman_55"><%= length(@recipients) %> emails sent</span>
      </div>

      <%= if @recipients == [] do %>
        <div class="text-center py-12">
          <svg xmlns="http://www.w3.org/2000/svg" class="h-12 w-12 text-gray-300 mx-auto mb-3" viewBox="0 0 20 20" fill="currentColor"><path d="M9 6a3 3 0 11-6 0 3 3 0 016 0zM17 6a3 3 0 11-6 0 3 3 0 016 0zM12.93 17c.046-.327.07-.66.07-1a6.97 6.97 0 00-1.5-4.33A5 5 0 0119 16v1h-6.07zM6 11a5 5 0 015 5v1H1v-1a5 5 0 015-5z" /></svg>
          <p class="text-sm text-gray-500 font-haas_roman_55">No emails sent yet</p>
        </div>
      <% else %>
        <div class="overflow-x-auto">
          <table class="w-full text-sm">
            <thead>
              <tr class="border-b border-gray-100">
                <th class="text-left py-3 px-3 text-xs text-gray-500 font-haas_medium_65 uppercase tracking-wider">User</th>
                <th class="text-left py-3 px-3 text-xs text-gray-500 font-haas_medium_65 uppercase tracking-wider">Email</th>
                <th class="text-left py-3 px-3 text-xs text-gray-500 font-haas_medium_65 uppercase tracking-wider">Sent</th>
                <th class="text-left py-3 px-3 text-xs text-gray-500 font-haas_medium_65 uppercase tracking-wider">Status</th>
              </tr>
            </thead>
            <tbody>
              <%= for r <- @recipients do %>
                <tr class="border-b border-gray-50 hover:bg-[#F5F6FB]">
                  <td class="py-3 px-3 font-haas_medium_65 text-[#141414]"><%= r.username || "—" %></td>
                  <td class="py-3 px-3 font-haas_roman_55 text-gray-600"><%= r.email %></td>
                  <td class="py-3 px-3 font-haas_roman_55 text-gray-500"><%= format_datetime(r.sent_at) %></td>
                  <td class="py-3 px-3">
                    <%= cond do %>
                      <% r.bounced -> %>
                        <span class="inline-flex items-center px-2 py-0.5 rounded-md text-xs font-haas_medium_65 bg-red-50 text-red-700">Bounced</span>
                      <% r.clicked_at -> %>
                        <span class="inline-flex items-center px-2 py-0.5 rounded-md text-xs font-haas_medium_65 bg-blue-50 text-blue-700">Clicked</span>
                      <% r.opened_at -> %>
                        <span class="inline-flex items-center px-2 py-0.5 rounded-md text-xs font-haas_medium_65 bg-green-50 text-green-700">Opened</span>
                      <% true -> %>
                        <span class="inline-flex items-center px-2 py-0.5 rounded-md text-xs font-haas_medium_65 bg-gray-100 text-gray-600">Delivered</span>
                    <% end %>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      <% end %>
    </div>
    """
  end

  defp funnel_bar(assigns) do
    pct = if assigns.max > 0, do: min(assigns.value / assigns.max * 100, 100), else: 0

    assigns = assign(assigns, :pct, pct)

    ~H"""
    <div class="flex items-center gap-4">
      <div class="w-20 text-xs font-haas_medium_65 text-gray-600 text-right"><%= @label %></div>
      <div class="flex-1 bg-gray-100 rounded-full h-6 overflow-hidden">
        <div class={"h-full rounded-full #{@color} transition-all"} style={"width: #{@pct}%"}></div>
      </div>
      <div class="w-16 text-xs font-haas_roman_55 text-gray-500 text-right"><%= format_number(@value) %></div>
    </div>
    """
  end

  defp stat_icon(%{name: "users"} = assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 text-black" viewBox="0 0 20 20" fill="currentColor"><path d="M9 6a3 3 0 11-6 0 3 3 0 016 0zM17 6a3 3 0 11-6 0 3 3 0 016 0zM12.93 17c.046-.327.07-.66.07-1a6.97 6.97 0 00-1.5-4.33A5 5 0 0119 16v1h-6.07zM6 11a5 5 0 015 5v1H1v-1a5 5 0 015-5z" /></svg>
    """
  end

  defp stat_icon(%{name: "email"} = assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 text-blue-600" viewBox="0 0 20 20" fill="currentColor"><path d="M2.003 5.884L10 9.882l7.997-3.998A2 2 0 0016 4H4a2 2 0 00-1.997 1.884z" /><path d="M18 8.118l-8 4-8-4V14a2 2 0 002 2h12a2 2 0 002-2V8.118z" /></svg>
    """
  end

  defp stat_icon(%{name: "open"} = assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 text-green-600" viewBox="0 0 20 20" fill="currentColor"><path d="M2.003 5.884L10 9.882l7.997-3.998A2 2 0 0016 4H4a2 2 0 00-1.997 1.884z" /><path d="M18 8.118l-8 4-8-4V14a2 2 0 002 2h12a2 2 0 002-2V8.118z" /></svg>
    """
  end

  defp stat_icon(%{name: "click"} = assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 text-blue-600" viewBox="0 0 20 20" fill="currentColor"><path fill-rule="evenodd" d="M6.672 1.911a1 1 0 10-1.932.518l.259.966a1 1 0 001.932-.518l-.26-.966zM2.429 4.74a1 1 0 10-.517 1.932l.966.259a1 1 0 00.517-1.932l-.966-.26zm8.814-.569a1 1 0 00-1.415-1.414l-.707.707a1 1 0 101.415 1.415l.707-.708zm-7.071 7.072l.707-.707A1 1 0 003.465 9.12l-.708.707a1 1 0 001.415 1.415zm3.2-5.171a1 1 0 00-1.3 1.3l4 10a1 1 0 001.823.075l1.38-2.759 3.018 3.02a1 1 0 001.414-1.415l-3.019-3.02 2.76-1.379a1 1 0 00-.076-1.822l-10-4z" clip-rule="evenodd" /></svg>
    """
  end

  defp stat_icon(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 text-gray-600" viewBox="0 0 20 20" fill="currentColor"><path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clip-rule="evenodd" /></svg>
    """
  end

  # ============ Helpers ============

  defp icon_bg("users"), do: "bg-[#CAFC00]"
  defp icon_bg("email"), do: "bg-blue-100"
  defp icon_bg("open"), do: "bg-green-100"
  defp icon_bg("click"), do: "bg-blue-100"
  defp icon_bg(_), do: "bg-gray-100"

  defp status_badge("draft"), do: raw(~s(<span class="inline-flex items-center px-2.5 py-1 rounded-lg text-xs font-haas_medium_65 bg-gray-100 text-gray-700">Draft</span>))
  defp status_badge("scheduled"), do: raw(~s(<span class="inline-flex items-center px-2.5 py-1 rounded-lg text-xs font-haas_medium_65 bg-amber-50 text-amber-700">Scheduled</span>))
  defp status_badge("sending"), do: raw(~s(<span class="inline-flex items-center px-2.5 py-1 rounded-lg text-xs font-haas_medium_65 bg-blue-50 text-blue-700">Sending</span>))
  defp status_badge("sent"), do: raw(~s(<span class="inline-flex items-center px-2.5 py-1 rounded-lg text-xs font-haas_medium_65 bg-green-50 text-green-700">Sent</span>))
  defp status_badge("cancelled"), do: raw(~s(<span class="inline-flex items-center px-2.5 py-1 rounded-lg text-xs font-haas_medium_65 bg-red-50 text-red-700">Cancelled</span>))
  defp status_badge(_), do: raw(~s(<span class="inline-flex items-center px-2.5 py-1 rounded-lg text-xs font-haas_medium_65 bg-gray-100 text-gray-700">Unknown</span>))

  defp format_number(n) when is_integer(n) and n >= 1000, do: "#{Float.round(n / 1000, 1)}k"
  defp format_number(n), do: to_string(n)

  defp format_datetime(nil), do: "—"
  defp format_datetime(dt), do: Calendar.strftime(dt, "%b %d, %Y %I:%M %p")

  defp format_rate(_numerator, 0), do: "0%"
  defp format_rate(numerator, denominator), do: "#{Float.round(numerator / denominator * 100, 1)}%"

  defp open_rate_text(opened, sent) when sent > 0, do: "#{Float.round(opened / sent * 100, 1)}% open rate"
  defp open_rate_text(_, _), do: nil

  defp click_rate_text(clicked, sent) when sent > 0, do: "#{Float.round(clicked / sent * 100, 1)}% click rate"
  defp click_rate_text(_, _), do: nil
end
