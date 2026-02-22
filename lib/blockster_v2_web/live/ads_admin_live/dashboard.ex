defmodule BlocksterV2Web.AdsAdminLive.Dashboard do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.AdsManager.{CampaignManager, BudgetManager, SafetyGuards, DecisionLogger, Config}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      :timer.send_interval(30_000, self(), :refresh)
    end

    {:ok,
     socket
     |> assign(:page_title, "AI Ads Manager")
     |> assign(:instruction_text, "")
     |> load_dashboard_data()}
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply, load_dashboard_data(socket)}
  end

  @impl true
  def handle_event("toggle_ads", _params, socket) do
    current = Config.ai_ads_enabled?()
    BlocksterV2.Notifications.SystemConfig.put("ai_ads_enabled", !current, "admin:#{socket.assigns.current_user.id}")
    {:noreply, load_dashboard_data(socket)}
  end

  def handle_event("submit_instruction", %{"instruction" => text}, socket) do
    if String.trim(text) != "" do
      BlocksterV2.AdsManager.submit_instruction(text, socket.assigns.current_user.id)
      {:noreply,
       socket
       |> assign(:instruction_text, "")
       |> put_flash(:info, "Instruction submitted to AI Manager")}
    else
      {:noreply, socket}
    end
  end

  def handle_event("update_instruction", %{"instruction" => text}, socket) do
    {:noreply, assign(socket, :instruction_text, text)}
  end

  def handle_event("emergency_stop", _params, socket) do
    SafetyGuards.emergency_stop!("Admin triggered emergency stop")
    {:noreply,
     socket
     |> load_dashboard_data()
     |> put_flash(:error, "Emergency stop activated — all campaigns paused")}
  end

  defp load_dashboard_data(socket) do
    status_counts = CampaignManager.campaign_count_by_status()
    today_budgets = BudgetManager.today_budgets()
    recent_decisions = DecisionLogger.recent_decisions(8)
    pending = CampaignManager.list_campaigns(status: "pending_approval", limit: 10)

    today_spend = SafetyGuards.total_spend_today()
    month_spend = SafetyGuards.total_spend_this_month()

    active_count = Map.get(status_counts, "active", 0)
    daily_limit = Config.daily_budget_limit()
    enabled = Config.ai_ads_enabled?()
    autonomy = Config.autonomy_level()

    socket
    |> assign(:enabled, enabled)
    |> assign(:autonomy_level, autonomy)
    |> assign(:active_count, active_count)
    |> assign(:status_counts, status_counts)
    |> assign(:today_spend, today_spend)
    |> assign(:month_spend, month_spend)
    |> assign(:daily_limit, daily_limit)
    |> assign(:today_budgets, today_budgets)
    |> assign(:recent_decisions, recent_decisions)
    |> assign(:pending_approvals, pending)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-[#F5F6FB]">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 pt-24 pb-12">
        <%!-- Header --%>
        <div class="flex items-center justify-between mb-8">
          <div>
            <h1 class="text-2xl font-haas_medium_65 text-[#141414]">AI Ads Manager</h1>
            <div class="flex items-center gap-3 mt-1">
              <span class={"inline-flex items-center px-2.5 py-1 rounded-lg text-xs font-haas_medium_65 #{if @enabled, do: "bg-green-50 text-green-700", else: "bg-red-50 text-red-700"}"}>
                <%= if @enabled, do: "Active", else: "Disabled" %>
              </span>
              <span class="text-sm text-gray-500 font-haas_roman_55">Mode: <%= String.capitalize(@autonomy_level) %></span>
            </div>
          </div>
          <div class="flex gap-3">
            <button phx-click="toggle_ads" class={"px-4 py-2.5 rounded-xl text-sm font-haas_medium_65 cursor-pointer #{if @enabled, do: "bg-red-50 border border-red-200 text-red-700 hover:bg-red-100", else: "bg-green-50 border border-green-200 text-green-700 hover:bg-green-100"}"}>
              <%= if @enabled, do: "Pause AI", else: "Enable AI" %>
            </button>
            <button phx-click="emergency_stop" data-confirm="This will pause ALL campaigns immediately. Continue?" class="px-4 py-2.5 bg-red-600 rounded-xl text-sm font-haas_medium_65 text-white hover:bg-red-700 cursor-pointer">
              Emergency Stop
            </button>
          </div>
        </div>

        <%!-- KPI Cards --%>
        <div class="grid grid-cols-2 md:grid-cols-4 gap-4 mb-8">
          <div class="bg-white rounded-2xl shadow-sm border border-gray-100 p-5">
            <div class="text-xs text-gray-500 font-haas_medium_65 uppercase tracking-wider mb-2">Daily Spend</div>
            <div class="text-2xl font-haas_medium_65 text-[#141414]">$<%= format_decimal(@today_spend) %></div>
            <div class="text-xs text-gray-400 font-haas_roman_55 mt-1">of $<%= @daily_limit %>/day</div>
          </div>
          <div class="bg-white rounded-2xl shadow-sm border border-gray-100 p-5">
            <div class="text-xs text-gray-500 font-haas_medium_65 uppercase tracking-wider mb-2">Monthly Spend</div>
            <div class="text-2xl font-haas_medium_65 text-[#141414]">$<%= format_decimal(@month_spend) %></div>
          </div>
          <div class="bg-white rounded-2xl shadow-sm border border-gray-100 p-5">
            <div class="text-xs text-gray-500 font-haas_medium_65 uppercase tracking-wider mb-2">Active Campaigns</div>
            <div class="text-2xl font-haas_medium_65 text-[#141414]"><%= @active_count %></div>
          </div>
          <div class="bg-white rounded-2xl shadow-sm border border-gray-100 p-5">
            <div class="text-xs text-gray-500 font-haas_medium_65 uppercase tracking-wider mb-2">Pending Approval</div>
            <div class="text-2xl font-haas_medium_65 text-[#141414]"><%= length(@pending_approvals) %></div>
          </div>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
          <%!-- Left Column: Platform Budgets + Instruction Box --%>
          <div class="lg:col-span-2 space-y-6">
            <%!-- Platform Budgets --%>
            <div class="bg-white rounded-2xl shadow-sm border border-gray-100 p-6">
              <h2 class="text-lg font-haas_medium_65 text-[#141414] mb-4">Platform Budgets (Today)</h2>
              <div class="space-y-3">
                <%= for budget <- Enum.filter(@today_budgets, & &1.platform) do %>
                  <div class="flex items-center gap-4">
                    <div class="w-20 text-sm font-haas_medium_65 text-[#141414]"><%= platform_label(budget.platform) %></div>
                    <div class="flex-1 bg-gray-100 rounded-full h-4 overflow-hidden">
                      <div class={"h-full rounded-full #{platform_color(budget.platform)}"} style={"width: #{budget_pct(budget)}%"}></div>
                    </div>
                    <div class="w-32 text-xs font-haas_roman_55 text-gray-500 text-right">
                      $<%= format_decimal(budget.spent_amount) %> / $<%= format_decimal(budget.allocated_amount) %>
                    </div>
                  </div>
                <% end %>
                <%= if Enum.filter(@today_budgets, & &1.platform) == [] do %>
                  <p class="text-sm text-gray-400 font-haas_roman_55">No budgets allocated yet. Enable the AI manager to start.</p>
                <% end %>
              </div>
            </div>

            <%!-- Talk to AI Manager --%>
            <div class="bg-white rounded-2xl shadow-sm border border-gray-100 p-6">
              <h2 class="text-lg font-haas_medium_65 text-[#141414] mb-4">Talk to AI Manager</h2>
              <form phx-submit="submit_instruction" phx-change="update_instruction" class="flex gap-3">
                <input
                  type="text"
                  name="instruction"
                  value={@instruction_text}
                  placeholder="e.g. 'Focus more on TikTok this week' or 'Pause all Meta campaigns'"
                  class="flex-1 px-4 py-2.5 bg-[#F5F6FB] border-0 rounded-xl text-sm font-haas_roman_55 focus:ring-2 focus:ring-gray-400"
                />
                <button type="submit" class="px-5 py-2.5 bg-gray-900 rounded-xl text-sm font-haas_medium_65 text-white hover:bg-gray-800 cursor-pointer">
                  Send
                </button>
              </form>
            </div>

            <%!-- Pending Approvals --%>
            <%= if @pending_approvals != [] do %>
              <div class="bg-white rounded-2xl shadow-sm border border-gray-100 p-6">
                <h2 class="text-lg font-haas_medium_65 text-[#141414] mb-4">Pending Approvals</h2>
                <div class="space-y-3">
                  <%= for campaign <- @pending_approvals do %>
                    <div class="flex items-center justify-between p-4 bg-amber-50 rounded-xl border border-amber-100">
                      <div>
                        <div class="text-sm font-haas_medium_65 text-[#141414]"><%= campaign.name %></div>
                        <div class="text-xs text-gray-500 font-haas_roman_55 mt-0.5">
                          <%= String.capitalize(campaign.platform) %> · $<%= campaign.budget_daily %>/day
                        </div>
                      </div>
                      <div class="flex gap-2">
                        <.link navigate={~p"/admin/ads/campaigns/#{campaign.id}"} class="px-3 py-1.5 bg-white border border-gray-200 rounded-lg text-xs font-haas_medium_65 text-gray-600 hover:bg-gray-50 cursor-pointer">
                          Review
                        </.link>
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>

          <%!-- Right Column: Recent Decisions + Quick Links --%>
          <div class="space-y-6">
            <%!-- Quick Links --%>
            <div class="bg-white rounded-2xl shadow-sm border border-gray-100 p-6">
              <h2 class="text-lg font-haas_medium_65 text-[#141414] mb-4">Quick Actions</h2>
              <div class="space-y-2">
                <.link navigate={~p"/admin/ads/campaigns/new"} class="block w-full px-4 py-3 bg-gray-900 rounded-xl text-sm font-haas_medium_65 text-white text-center hover:bg-gray-800 cursor-pointer">
                  Create Campaign
                </.link>
                <.link navigate={~p"/admin/ads/campaigns"} class="block w-full px-4 py-3 bg-[#F5F6FB] rounded-xl text-sm font-haas_medium_65 text-[#141414] text-center hover:bg-gray-200 cursor-pointer">
                  All Campaigns
                </.link>
              </div>
            </div>

            <%!-- Recent AI Decisions --%>
            <div class="bg-white rounded-2xl shadow-sm border border-gray-100 p-6">
              <div class="flex items-center justify-between mb-4">
                <h2 class="text-lg font-haas_medium_65 text-[#141414]">Recent AI Decisions</h2>
              </div>
              <div class="space-y-3">
                <%= if @recent_decisions == [] do %>
                  <p class="text-sm text-gray-400 font-haas_roman_55">No decisions yet.</p>
                <% end %>
                <%= for decision <- @recent_decisions do %>
                  <div class="p-3 bg-[#F5F6FB] rounded-xl">
                    <div class="flex items-center gap-2 mb-1">
                      <span class={"w-2 h-2 rounded-full #{decision_dot_color(decision.outcome)}"}></span>
                      <span class="text-xs font-haas_medium_65 text-[#141414]"><%= humanize_decision_type(decision.decision_type) %></span>
                    </div>
                    <p class="text-xs text-gray-500 font-haas_roman_55 line-clamp-2"><%= String.slice(decision.reasoning || "", 0, 120) %></p>
                    <div class="text-xs text-gray-400 font-haas_roman_55 mt-1"><%= relative_time(decision.inserted_at) %></div>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ============ Helpers ============

  defp format_decimal(nil), do: "0.00"
  defp format_decimal(%Decimal{} = d), do: Decimal.round(d, 2) |> Decimal.to_string()
  defp format_decimal(n), do: "#{n}"

  defp platform_label("x"), do: "X"
  defp platform_label("meta"), do: "Meta"
  defp platform_label("tiktok"), do: "TikTok"
  defp platform_label("telegram"), do: "Telegram"
  defp platform_label(p), do: p

  defp platform_color("x"), do: "bg-gray-800"
  defp platform_color("meta"), do: "bg-blue-500"
  defp platform_color("tiktok"), do: "bg-pink-500"
  defp platform_color("telegram"), do: "bg-sky-500"
  defp platform_color(_), do: "bg-gray-400"

  defp budget_pct(%{allocated_amount: alloc, spent_amount: spent}) do
    if Decimal.compare(alloc, Decimal.new(0)) == :gt do
      Decimal.div(spent, alloc) |> Decimal.mult(Decimal.new(100)) |> Decimal.round(0) |> Decimal.to_float() |> min(100)
    else
      0
    end
  end

  defp decision_dot_color("success"), do: "bg-green-500"
  defp decision_dot_color("failure"), do: "bg-red-500"
  defp decision_dot_color("pending_approval"), do: "bg-amber-500"
  defp decision_dot_color("skipped"), do: "bg-gray-400"
  defp decision_dot_color(_), do: "bg-gray-400"

  defp humanize_decision_type("create_campaign"), do: "Created Campaign"
  defp humanize_decision_type("pause_campaign"), do: "Paused Campaign"
  defp humanize_decision_type("resume_campaign"), do: "Resumed Campaign"
  defp humanize_decision_type("adjust_budget"), do: "Adjusted Budget"
  defp humanize_decision_type("evaluate_post"), do: "Evaluated Post"
  defp humanize_decision_type("anomaly_detected"), do: "Anomaly Detected"
  defp humanize_decision_type("performance_check"), do: "Performance Check"
  defp humanize_decision_type(type), do: String.replace(type, "_", " ") |> String.capitalize()

  defp relative_time(nil), do: ""
  defp relative_time(dt) do
    diff = DateTime.diff(DateTime.utc_now(), dt, :second)
    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86400)}d ago"
    end
  end
end
