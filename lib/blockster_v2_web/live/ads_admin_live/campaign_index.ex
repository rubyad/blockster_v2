defmodule BlocksterV2Web.AdsAdminLive.CampaignIndex do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.AdsManager.CampaignManager

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Ad Campaigns")
     |> assign(:filter_status, nil)
     |> assign(:filter_platform, nil)
     |> load_campaigns()}
  end

  @impl true
  def handle_event("filter", params, socket) do
    status = if params["status"] == "", do: nil, else: params["status"]
    platform = if params["platform"] == "", do: nil, else: params["platform"]

    {:noreply,
     socket
     |> assign(:filter_status, status)
     |> assign(:filter_platform, platform)
     |> load_campaigns()}
  end

  def handle_event("approve", %{"id" => id}, socket) do
    campaign = CampaignManager.get_campaign!(String.to_integer(id))

    case CampaignManager.approve_campaign(campaign) do
      {:ok, _} -> {:noreply, socket |> load_campaigns() |> put_flash(:info, "Campaign approved")}
      {:error, msg} -> {:noreply, put_flash(socket, :error, msg)}
    end
  end

  def handle_event("pause", %{"id" => id}, socket) do
    campaign = CampaignManager.get_campaign!(String.to_integer(id))
    CampaignManager.pause_campaign(campaign, "admin")
    {:noreply, socket |> load_campaigns() |> put_flash(:info, "Campaign paused")}
  end

  def handle_event("resume", %{"id" => id}, socket) do
    campaign = CampaignManager.get_campaign!(String.to_integer(id))
    CampaignManager.resume_campaign(campaign)
    {:noreply, socket |> load_campaigns() |> put_flash(:info, "Campaign resumed")}
  end

  defp load_campaigns(socket) do
    opts = [limit: 50]
    opts = if socket.assigns.filter_status, do: Keyword.put(opts, :status, socket.assigns.filter_status), else: opts
    opts = if socket.assigns.filter_platform, do: Keyword.put(opts, :platform, socket.assigns.filter_platform), else: opts

    campaigns = CampaignManager.list_campaigns(opts)
    assign(socket, :campaigns, campaigns)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-[#F5F6FB]">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 pt-24 pb-12">
        <%!-- Header --%>
        <div class="flex items-center justify-between mb-8">
          <div class="flex items-center gap-4">
            <.link navigate={~p"/admin/ads"} class="w-10 h-10 bg-white rounded-xl flex items-center justify-center shadow-sm border border-gray-100 hover:bg-gray-50 cursor-pointer">
              <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 text-gray-600" viewBox="0 0 20 20" fill="currentColor"><path fill-rule="evenodd" d="M9.707 16.707a1 1 0 01-1.414 0l-6-6a1 1 0 010-1.414l6-6a1 1 0 011.414 1.414L5.414 9H17a1 1 0 110 2H5.414l4.293 4.293a1 1 0 010 1.414z" clip-rule="evenodd" /></svg>
            </.link>
            <h1 class="text-2xl font-haas_medium_65 text-[#141414]">Ad Campaigns</h1>
          </div>
          <.link navigate={~p"/admin/ads/campaigns/new"} class="px-5 py-2.5 bg-gray-900 rounded-xl text-sm font-haas_medium_65 text-white hover:bg-gray-800 cursor-pointer">
            New Campaign
          </.link>
        </div>

        <%!-- Filters --%>
        <div class="flex gap-3 mb-6">
          <form phx-change="filter" class="flex gap-3">
            <select name="status" class="px-4 py-2 bg-white border border-gray-200 rounded-xl text-sm font-haas_roman_55 focus:ring-2 focus:ring-gray-400">
              <option value="">All Statuses</option>
              <option value="draft" selected={@filter_status == "draft"}>Draft</option>
              <option value="pending_approval" selected={@filter_status == "pending_approval"}>Pending Approval</option>
              <option value="active" selected={@filter_status == "active"}>Active</option>
              <option value="paused" selected={@filter_status == "paused"}>Paused</option>
              <option value="completed" selected={@filter_status == "completed"}>Completed</option>
              <option value="failed" selected={@filter_status == "failed"}>Failed</option>
            </select>
            <select name="platform" class="px-4 py-2 bg-white border border-gray-200 rounded-xl text-sm font-haas_roman_55 focus:ring-2 focus:ring-gray-400">
              <option value="">All Platforms</option>
              <option value="x" selected={@filter_platform == "x"}>X</option>
              <option value="meta" selected={@filter_platform == "meta"}>Meta</option>
              <option value="tiktok" selected={@filter_platform == "tiktok"}>TikTok</option>
              <option value="telegram" selected={@filter_platform == "telegram"}>Telegram</option>
            </select>
          </form>
        </div>

        <%!-- Campaign List --%>
        <div class="bg-white rounded-2xl shadow-sm border border-gray-100">
          <%= if @campaigns == [] do %>
            <div class="p-12 text-center">
              <div class="w-16 h-16 bg-gray-100 rounded-2xl flex items-center justify-center mx-auto mb-4">
                <svg xmlns="http://www.w3.org/2000/svg" class="h-8 w-8 text-gray-400" viewBox="0 0 20 20" fill="currentColor"><path fill-rule="evenodd" d="M4 3a2 2 0 00-2 2v10a2 2 0 002 2h12a2 2 0 002-2V5a2 2 0 00-2-2H4zm12 12H4l4-8 3 6 2-4 3 6z" clip-rule="evenodd" /></svg>
              </div>
              <p class="text-sm text-gray-500 font-haas_roman_55">No campaigns yet</p>
            </div>
          <% else %>
            <div class="divide-y divide-gray-50">
              <%= for campaign <- @campaigns do %>
                <div class="flex items-center justify-between p-5 hover:bg-gray-50/50">
                  <div class="flex items-center gap-4 flex-1 min-w-0">
                    <div class={"w-10 h-10 rounded-xl flex items-center justify-center #{platform_bg(campaign.platform)}"}>
                      <span class="text-xs font-haas_medium_65 text-white"><%= platform_abbr(campaign.platform) %></span>
                    </div>
                    <div class="min-w-0 flex-1">
                      <.link navigate={~p"/admin/ads/campaigns/#{campaign.id}"} class="text-sm font-haas_medium_65 text-[#141414] hover:underline cursor-pointer truncate block">
                        <%= campaign.name %>
                      </.link>
                      <div class="flex items-center gap-2 mt-0.5">
                        <%= status_badge(campaign.status) %>
                        <span class="text-xs text-gray-400 font-haas_roman_55"><%= campaign.objective %></span>
                        <span class="text-xs text-gray-400 font-haas_roman_55">·</span>
                        <span class="text-xs text-gray-400 font-haas_roman_55"><%= campaign.created_by %></span>
                      </div>
                    </div>
                  </div>
                  <div class="flex items-center gap-6">
                    <div class="text-right">
                      <div class="text-sm font-haas_medium_65 text-[#141414]">$<%= format_decimal(campaign.budget_daily) %>/day</div>
                      <div class="text-xs text-gray-400 font-haas_roman_55">Spent: $<%= format_decimal(campaign.spend_total) %></div>
                    </div>
                    <div class="flex gap-2">
                      <%= if campaign.status == "pending_approval" do %>
                        <button phx-click="approve" phx-value-id={campaign.id} class="px-3 py-1.5 bg-green-50 border border-green-200 rounded-lg text-xs font-haas_medium_65 text-green-700 hover:bg-green-100 cursor-pointer">
                          Approve
                        </button>
                      <% end %>
                      <%= if campaign.status == "active" do %>
                        <button phx-click="pause" phx-value-id={campaign.id} class="px-3 py-1.5 bg-amber-50 border border-amber-200 rounded-lg text-xs font-haas_medium_65 text-amber-700 hover:bg-amber-100 cursor-pointer">
                          Pause
                        </button>
                      <% end %>
                      <%= if campaign.status == "paused" do %>
                        <button phx-click="resume" phx-value-id={campaign.id} class="px-3 py-1.5 bg-blue-50 border border-blue-200 rounded-lg text-xs font-haas_medium_65 text-blue-700 hover:bg-blue-100 cursor-pointer">
                          Resume
                        </button>
                      <% end %>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp format_decimal(nil), do: "0.00"
  defp format_decimal(%Decimal{} = d), do: Decimal.round(d, 2) |> Decimal.to_string()
  defp format_decimal(n), do: "#{n}"

  defp platform_bg("x"), do: "bg-gray-800"
  defp platform_bg("meta"), do: "bg-blue-600"
  defp platform_bg("tiktok"), do: "bg-pink-600"
  defp platform_bg("telegram"), do: "bg-sky-600"
  defp platform_bg(_), do: "bg-gray-400"

  defp platform_abbr("x"), do: "X"
  defp platform_abbr("meta"), do: "M"
  defp platform_abbr("tiktok"), do: "TT"
  defp platform_abbr("telegram"), do: "TG"
  defp platform_abbr(p), do: String.first(p || "?") |> String.upcase()

  defp status_badge("draft"), do: raw(~s(<span class="inline-flex px-2 py-0.5 rounded-md text-xs font-haas_medium_65 bg-gray-100 text-gray-600">Draft</span>))
  defp status_badge("pending_approval"), do: raw(~s(<span class="inline-flex px-2 py-0.5 rounded-md text-xs font-haas_medium_65 bg-amber-50 text-amber-700">Pending</span>))
  defp status_badge("active"), do: raw(~s(<span class="inline-flex px-2 py-0.5 rounded-md text-xs font-haas_medium_65 bg-green-50 text-green-700">Active</span>))
  defp status_badge("paused"), do: raw(~s(<span class="inline-flex px-2 py-0.5 rounded-md text-xs font-haas_medium_65 bg-blue-50 text-blue-700">Paused</span>))
  defp status_badge("completed"), do: raw(~s(<span class="inline-flex px-2 py-0.5 rounded-md text-xs font-haas_medium_65 bg-gray-50 text-gray-600">Completed</span>))
  defp status_badge("failed"), do: raw(~s(<span class="inline-flex px-2 py-0.5 rounded-md text-xs font-haas_medium_65 bg-red-50 text-red-700">Failed</span>))
  defp status_badge(_), do: raw(~s(<span class="inline-flex px-2 py-0.5 rounded-md text-xs font-haas_medium_65 bg-gray-100 text-gray-600">—</span>))
end
