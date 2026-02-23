defmodule BlocksterV2Web.CampaignAdminLive.Index do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.{Notifications, Blog}

  @impl true
  def mount(_params, _session, socket) do
    campaigns = Notifications.list_campaigns()
    hubs = Blog.list_hubs()

    {:ok,
     socket
     |> assign(:page_title, "Notification Campaigns")
     |> assign(:campaigns, campaigns)
     |> assign(:hubs, hubs)
     |> assign(:status_filter, "all")
     |> assign(:show_quick_send, false)
     |> assign(:quick_send_form, %{})}
  end

  @impl true
  def handle_event("filter_status", %{"status" => status}, socket) do
    opts = if status == "all", do: [], else: [status: status]
    campaigns = Notifications.list_campaigns(opts)
    {:noreply, assign(socket, campaigns: campaigns, status_filter: status)}
  end

  def handle_event("delete_campaign", %{"id" => id}, socket) do
    campaign = Notifications.get_campaign!(id)

    case Notifications.delete_campaign(campaign) do
      {:ok, _} ->
        campaigns = Notifications.list_campaigns()
        {:noreply, socket |> assign(:campaigns, campaigns) |> put_flash(:info, "Campaign deleted.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete campaign.")}
    end
  end

  def handle_event("cancel_campaign", %{"id" => id}, socket) do
    campaign = Notifications.get_campaign!(id)

    case Notifications.update_campaign_status(campaign, "cancelled") do
      {:ok, _} ->
        campaigns = Notifications.list_campaigns()
        {:noreply, socket |> assign(:campaigns, campaigns) |> put_flash(:info, "Campaign cancelled.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to cancel campaign.")}
    end
  end

  def handle_event("toggle_quick_send", _params, socket) do
    {:noreply, assign(socket, :show_quick_send, !socket.assigns.show_quick_send)}
  end

  def handle_event("quick_send", params, socket) do
    attrs = %{
      name: "Quick: #{params["title"]}",
      type: "email_blast",
      title: params["title"],
      subject: params["title"],
      body: params["body"],
      plain_text_body: params["body"],
      target_audience: params["audience"] || "all",
      send_email: params["send_email"] == "true",
      send_in_app: params["send_in_app"] == "true",
      send_sms: params["send_sms"] == "true",
      created_by_id: socket.assigns.current_user.id,
      status: "draft"
    }

    case Notifications.create_campaign(attrs) do
      {:ok, campaign} ->
        # Auto-send immediately
        BlocksterV2.Workers.PromoEmailWorker.enqueue_campaign(campaign.id)

        campaigns = Notifications.list_campaigns()

        {:noreply,
         socket
         |> assign(:campaigns, campaigns)
         |> assign(:show_quick_send, false)
         |> put_flash(:info, "Quick notification sent!")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create notification.")}
    end
  end

  def handle_event("send_test", %{"id" => id}, socket) do
    campaign = Notifications.get_campaign!(id)
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
        <div class="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 mb-8">
          <div>
            <h1 class="text-3xl font-haas_medium_65 text-[#141414]">Campaigns</h1>
            <p class="text-gray-500 mt-1 font-haas_roman_55">Manage notification campaigns and sends</p>
          </div>
          <div class="flex gap-3">
            <button phx-click="toggle_quick_send" class="px-4 py-2.5 bg-white border border-gray-200 rounded-xl text-sm font-haas_medium_65 text-[#141414] hover:bg-gray-50 cursor-pointer transition-colors">
              Quick Send
            </button>
            <.link navigate={~p"/admin/notifications/rules"} class="px-4 py-2.5 bg-white rounded-xl text-sm font-haas_roman_55 text-gray-600 hover:bg-gray-50 border border-gray-200 cursor-pointer transition-all">
              Custom Rules
            </.link>
            <.link navigate={~p"/admin/ai-manager"} class="px-4 py-2.5 bg-white rounded-xl text-sm font-haas_roman_55 text-gray-600 hover:bg-gray-50 border border-gray-200 cursor-pointer transition-all">
              Ask AI Manager
            </.link>
            <.link navigate={~p"/admin/notifications/campaigns/new"} class="px-4 py-2.5 bg-gray-900 rounded-xl text-sm font-haas_medium_65 text-white hover:bg-gray-800 cursor-pointer transition-all">
              + New Campaign
            </.link>
          </div>
        </div>

        <%!-- Quick Send Form --%>
        <%= if @show_quick_send do %>
          <div class="bg-white rounded-2xl shadow-sm border border-gray-100 p-6 mb-8">
            <div class="flex items-center gap-3 mb-5">
              <div class="w-8 h-8 bg-[#CAFC00] rounded-lg flex items-center justify-center">
                <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4 text-black" viewBox="0 0 20 20" fill="currentColor">
                  <path d="M10.894 2.553a1 1 0 00-1.788 0l-7 14a1 1 0 001.169 1.409l5-1.429A1 1 0 009 15.571V11a1 1 0 112 0v4.571a1 1 0 00.725.962l5 1.428a1 1 0 001.17-1.408l-7-14z" />
                </svg>
              </div>
              <h2 class="text-lg font-haas_medium_65 text-[#141414]">Quick Send</h2>
            </div>
            <form phx-submit="quick_send" class="space-y-4">
              <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div>
                  <label class="block text-sm font-haas_medium_65 text-gray-700 mb-1">Title</label>
                  <input type="text" name="title" required class="w-full px-4 py-2.5 bg-[#F5F6FB] border-0 rounded-xl text-sm font-haas_roman_55 focus:ring-2 focus:ring-gray-400" placeholder="Notification title..." />
                </div>
                <div>
                  <label class="block text-sm font-haas_medium_65 text-gray-700 mb-1">Audience</label>
                  <select name="audience" class="w-full px-4 py-2.5 bg-[#F5F6FB] border-0 rounded-xl text-sm font-haas_roman_55 focus:ring-2 focus:ring-gray-400">
                    <option value="all">All Users</option>
                    <option value="active_users">Active Users (7d)</option>
                    <option value="dormant_users">Dormant Users (30d+)</option>
                    <option value="phone_verified">Phone Verified</option>
                    <option value="not_phone_verified">Not Phone Verified</option>
                    <option value="x_connected">X Connected</option>
                    <option value="not_x_connected">No X Account</option>
                    <option value="has_external_wallet">Has External Wallet</option>
                    <option value="no_external_wallet">No External Wallet</option>
                    <option value="bux_gamers">BUX Gamers</option>
                    <option value="rogue_gamers">ROGUE Gamers</option>
                  </select>
                </div>
              </div>
              <div>
                <label class="block text-sm font-haas_medium_65 text-gray-700 mb-1">Message</label>
                <textarea name="body" rows="2" required class="w-full px-4 py-2.5 bg-[#F5F6FB] border-0 rounded-xl text-sm font-haas_roman_55 focus:ring-2 focus:ring-gray-400" placeholder="Write your message..."></textarea>
              </div>
              <div class="flex items-center gap-6">
                <label class="flex items-center gap-2 cursor-pointer">
                  <input type="hidden" name="send_email" value="false" />
                  <input type="checkbox" name="send_email" value="true" checked class="w-4 h-4 rounded border-gray-300 text-gray-900 focus:ring-gray-400" />
                  <span class="text-sm font-haas_roman_55 text-gray-700">Email</span>
                </label>
                <label class="flex items-center gap-2 cursor-pointer">
                  <input type="hidden" name="send_in_app" value="false" />
                  <input type="checkbox" name="send_in_app" value="true" checked class="w-4 h-4 rounded border-gray-300 text-gray-900 focus:ring-gray-400" />
                  <span class="text-sm font-haas_roman_55 text-gray-700">In-App</span>
                </label>
                <label class="flex items-center gap-2 cursor-pointer">
                  <input type="hidden" name="send_sms" value="false" />
                  <input type="checkbox" name="send_sms" value="true" class="w-4 h-4 rounded border-gray-300 text-gray-900 focus:ring-gray-400" />
                  <span class="text-sm font-haas_roman_55 text-gray-700">SMS</span>
                </label>
              </div>
              <div class="flex gap-3 pt-2">
                <button type="submit" class="px-5 py-2.5 bg-gray-900 rounded-xl text-sm font-haas_medium_65 text-white hover:bg-gray-800 cursor-pointer">Send Now</button>
                <button type="button" phx-click="toggle_quick_send" class="px-5 py-2.5 bg-gray-100 rounded-xl text-sm font-haas_medium_65 text-gray-600 hover:bg-gray-200 cursor-pointer">Cancel</button>
              </div>
            </form>
          </div>
        <% end %>

        <%!-- Status Filters --%>
        <div class="flex gap-2 mb-6">
          <% statuses = [{"all", "All"}, {"draft", "Draft"}, {"scheduled", "Scheduled"}, {"sending", "Sending"}, {"sent", "Sent"}, {"cancelled", "Cancelled"}] %>
          <%= for {value, label} <- statuses do %>
            <button
              phx-click="filter_status"
              phx-value-status={value}
              class={"px-4 py-2 rounded-xl text-sm font-haas_medium_65 cursor-pointer transition-colors #{if @status_filter == value, do: "bg-[#141414] text-white", else: "bg-white text-gray-600 hover:bg-gray-50 border border-gray-200"}"}
            >
              <%= label %>
            </button>
          <% end %>
        </div>

        <%!-- Campaigns Table --%>
        <div class="bg-white rounded-2xl shadow-sm border border-gray-100 overflow-hidden">
          <%= if Enum.empty?(@campaigns) do %>
            <div class="text-center py-16">
              <div class="w-16 h-16 bg-[#F5F6FB] rounded-2xl flex items-center justify-center mx-auto mb-4">
                <svg xmlns="http://www.w3.org/2000/svg" class="h-8 w-8 text-gray-400" viewBox="0 0 20 20" fill="currentColor">
                  <path d="M2.003 5.884L10 9.882l7.997-3.998A2 2 0 0016 4H4a2 2 0 00-1.997 1.884z" />
                  <path d="M18 8.118l-8 4-8-4V14a2 2 0 002 2h12a2 2 0 002-2V8.118z" />
                </svg>
              </div>
              <h3 class="text-lg font-haas_medium_65 text-[#141414] mb-1">No campaigns yet</h3>
              <p class="text-sm text-gray-500 font-haas_roman_55">Create your first notification campaign to get started.</p>
            </div>
          <% else %>
            <table class="min-w-full">
              <thead class="bg-[#F5F6FB]">
                <tr>
                  <th class="px-6 py-3.5 text-left text-xs font-haas_medium_65 text-gray-500 uppercase tracking-wider">Campaign</th>
                  <th class="px-6 py-3.5 text-left text-xs font-haas_medium_65 text-gray-500 uppercase tracking-wider">Status</th>
                  <th class="px-6 py-3.5 text-left text-xs font-haas_medium_65 text-gray-500 uppercase tracking-wider">Channels</th>
                  <th class="px-6 py-3.5 text-left text-xs font-haas_medium_65 text-gray-500 uppercase tracking-wider">Recipients</th>
                  <th class="px-6 py-3.5 text-left text-xs font-haas_medium_65 text-gray-500 uppercase tracking-wider">Performance</th>
                  <th class="px-6 py-3.5 text-left text-xs font-haas_medium_65 text-gray-500 uppercase tracking-wider">Created</th>
                  <th class="px-6 py-3.5 text-right text-xs font-haas_medium_65 text-gray-500 uppercase tracking-wider">Actions</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-gray-100">
                <%= for campaign <- @campaigns do %>
                  <tr class="hover:bg-[#F5F6FB]/50 transition-colors">
                    <td class="px-6 py-4">
                      <.link navigate={~p"/admin/notifications/campaigns/#{campaign.id}"} class="cursor-pointer">
                        <div class="font-haas_medium_65 text-sm text-[#141414] hover:text-blue-600"><%= campaign.name %></div>
                        <div class="text-xs text-gray-500 font-haas_roman_55 mt-0.5"><%= campaign.type %> · <%= campaign.target_audience %></div>
                      </.link>
                    </td>
                    <td class="px-6 py-4"><%= status_badge(campaign.status) %></td>
                    <td class="px-6 py-4">
                      <div class="flex gap-1.5">
                        <%= if campaign.send_email do %><span class="px-2 py-0.5 bg-blue-50 text-blue-700 text-xs rounded-md font-haas_medium_65">Email</span><% end %>
                        <%= if campaign.send_in_app do %><span class="px-2 py-0.5 bg-green-50 text-green-700 text-xs rounded-md font-haas_medium_65">In-App</span><% end %>
                        <%= if campaign.send_sms do %><span class="px-2 py-0.5 bg-purple-50 text-purple-700 text-xs rounded-md font-haas_medium_65">SMS</span><% end %>
                      </div>
                    </td>
                    <td class="px-6 py-4 text-sm font-haas_roman_55 text-gray-900"><%= campaign.total_recipients %></td>
                    <td class="px-6 py-4">
                      <%= if campaign.total_recipients > 0 do %>
                        <div class="text-xs font-haas_roman_55 text-gray-500">
                          <span class="text-green-600 font-haas_medium_65"><%= campaign.emails_opened %></span> opens ·
                          <span class="text-blue-600 font-haas_medium_65"><%= campaign.emails_clicked %></span> clicks
                        </div>
                      <% else %>
                        <span class="text-xs text-gray-400">—</span>
                      <% end %>
                    </td>
                    <td class="px-6 py-4 text-sm font-haas_roman_55 text-gray-500"><%= format_date(campaign.inserted_at) %></td>
                    <td class="px-6 py-4 text-right">
                      <div class="flex items-center justify-end gap-2">
                        <button phx-click="send_test" phx-value-id={campaign.id} class="text-xs text-blue-600 hover:text-blue-800 font-haas_medium_65 cursor-pointer">Test</button>
                        <%= if campaign.status in ["draft", "scheduled"] do %>
                          <.link navigate={~p"/admin/notifications/campaigns/#{campaign.id}/edit"} class="text-xs text-gray-600 hover:text-gray-800 font-haas_medium_65 cursor-pointer">Edit</.link>
                          <button phx-click="cancel_campaign" phx-value-id={campaign.id} data-confirm="Cancel this campaign?" class="text-xs text-amber-600 hover:text-amber-800 font-haas_medium_65 cursor-pointer">Cancel</button>
                        <% end %>
                        <%= if campaign.status in ["draft", "cancelled"] do %>
                          <button phx-click="delete_campaign" phx-value-id={campaign.id} data-confirm="Delete this campaign permanently?" class="text-xs text-red-600 hover:text-red-800 font-haas_medium_65 cursor-pointer">Delete</button>
                        <% end %>
                      </div>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp status_badge("draft"), do: raw(~s(<span class="inline-flex items-center px-2.5 py-1 rounded-lg text-xs font-haas_medium_65 bg-gray-100 text-gray-700">Draft</span>))
  defp status_badge("scheduled"), do: raw(~s(<span class="inline-flex items-center px-2.5 py-1 rounded-lg text-xs font-haas_medium_65 bg-amber-50 text-amber-700">Scheduled</span>))
  defp status_badge("sending"), do: raw(~s(<span class="inline-flex items-center px-2.5 py-1 rounded-lg text-xs font-haas_medium_65 bg-blue-50 text-blue-700">Sending</span>))
  defp status_badge("sent"), do: raw(~s(<span class="inline-flex items-center px-2.5 py-1 rounded-lg text-xs font-haas_medium_65 bg-green-50 text-green-700">Sent</span>))
  defp status_badge("cancelled"), do: raw(~s(<span class="inline-flex items-center px-2.5 py-1 rounded-lg text-xs font-haas_medium_65 bg-red-50 text-red-700">Cancelled</span>))
  defp status_badge(_), do: raw(~s(<span class="inline-flex items-center px-2.5 py-1 rounded-lg text-xs font-haas_medium_65 bg-gray-100 text-gray-700">Unknown</span>))

  defp format_date(nil), do: "—"
  defp format_date(dt), do: Calendar.strftime(dt, "%b %d, %Y")
end
