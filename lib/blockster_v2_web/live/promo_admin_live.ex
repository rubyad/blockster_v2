defmodule BlocksterV2Web.PromoAdminLive do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.TelegramBot.{PromoEngine, HourlyPromoScheduler}
  alias BlocksterV2.Notifications.SystemConfig

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Refresh every 30 seconds
      :timer.send_interval(30_000, self(), :refresh)
    end

    {:ok, load_state(socket)}
  end

  @impl true
  def handle_event("toggle_bot", _params, socket) do
    current = SystemConfig.get("hourly_promo_enabled", true)
    SystemConfig.put("hourly_promo_enabled", !current, "admin_dashboard")

    {:noreply,
     socket
     |> assign(:bot_enabled, !current)
     |> put_flash(:info, if(!current, do: "Bot resumed", else: "Bot paused"))}
  end

  def handle_event("force_next", %{"category" => category}, socket) do
    cat = String.to_existing_atom(category)

    case HourlyPromoScheduler.force_next(cat) do
      :ok ->
        {:noreply,
         socket
         |> assign(:forced_category, cat)
         |> put_flash(:info, "Next promo forced to: #{category}")}

      {:error, :not_running} ->
        {:noreply, put_flash(socket, :error, "Scheduler is not running")}
    end
  end

  def handle_event("run_now", _params, socket) do
    case HourlyPromoScheduler.run_now() do
      :run_promo ->
        {:noreply,
         socket
         |> load_state()
         |> put_flash(:info, "Promo cycle triggered")}

      {:error, :not_running} ->
        {:noreply, put_flash(socket, :error, "Scheduler is not running")}
    end
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply, load_state(socket)}
  end

  defp load_state(socket) do
    bot_enabled = SystemConfig.get("hourly_promo_enabled", true)
    daily_state = PromoEngine.get_daily_state()
    remaining = PromoEngine.remaining_budget()

    scheduler_state =
      case HourlyPromoScheduler.get_state() do
        {:ok, info} -> info
        _ -> nil
      end

    current_promo =
      if scheduler_state, do: scheduler_state.current_promo, else: nil

    history =
      if scheduler_state, do: scheduler_state[:history] || [], else: []

    socket
    |> assign(:bot_enabled, bot_enabled)
    |> assign(:scheduler_running, scheduler_state != nil)
    |> assign(:current_promo, current_promo)
    |> assign(:history, history)
    |> assign(:daily_state, daily_state)
    |> assign(:budget_remaining, remaining)
    |> assign(:users_rewarded, map_size(daily_state.user_reward_counts))
    |> assign(:forced_category, nil)
    |> assign(:categories, [:bux_booster_rule, :referral_boost, :giveaway, :competition])
    |> assign(:template_counts, %{
      bux_booster_rule: length(PromoEngine.all_templates()[:bux_booster_rule] || []),
      referral_boost: length(PromoEngine.all_templates()[:referral_boost] || []),
      giveaway: length(PromoEngine.all_templates()[:giveaway] || []),
      competition: length(PromoEngine.all_templates()[:competition] || [])
    })
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50 pt-24 pb-8">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <%!-- Header --%>
        <div class="flex items-center justify-between mb-6">
          <div>
            <h1 class="text-2xl font-bold text-gray-900">Telegram Bot Promos</h1>
            <p class="mt-1 text-sm text-gray-600">Hourly engagement system for the Telegram group</p>
          </div>
          <div class="flex items-center gap-3">
            <span class={[
              "inline-flex items-center gap-1.5 px-3 py-1.5 rounded-full text-sm font-medium",
              if(@scheduler_running, do: "bg-green-100 text-green-700", else: "bg-red-100 text-red-700")
            ]}>
              <span class={[
                "w-2 h-2 rounded-full",
                if(@scheduler_running, do: "bg-green-500", else: "bg-red-500")
              ]} />
              <%= if @scheduler_running, do: "Scheduler Running", else: "Scheduler Stopped" %>
            </span>
            <button
              phx-click="toggle_bot"
              class={[
                "px-4 py-2 rounded-lg text-sm font-medium cursor-pointer transition",
                if(@bot_enabled, do: "bg-red-600 text-white hover:bg-red-700", else: "bg-gray-900 text-white hover:bg-gray-800")
              ]}
            >
              <%= if @bot_enabled, do: "Pause Bot", else: "Resume Bot" %>
            </button>
          </div>
        </div>

        <%!-- Stats Cards --%>
        <div class="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
          <div class="bg-white rounded-lg shadow p-5">
            <div class="text-sm font-medium text-gray-500">Status</div>
            <div class={[
              "mt-1 text-2xl font-bold",
              if(@bot_enabled, do: "text-green-600", else: "text-red-600")
            ]}>
              <%= if @bot_enabled, do: "RUNNING", else: "PAUSED" %>
            </div>
          </div>

          <div class="bg-white rounded-lg shadow p-5">
            <div class="text-sm font-medium text-gray-500">Budget Today</div>
            <div class="mt-1 text-2xl font-bold text-gray-900">
              <%= Number.Delimited.number_to_delimited(@daily_state.total_bux_given, precision: 0) %> / 100,000
            </div>
            <div class="mt-1">
              <div class="w-full bg-gray-200 rounded-full h-2">
                <div
                  class="bg-gray-900 h-2 rounded-full transition-all"
                  style={"width: #{min(@daily_state.total_bux_given / 1000, 100)}%"}
                />
              </div>
            </div>
          </div>

          <div class="bg-white rounded-lg shadow p-5">
            <div class="text-sm font-medium text-gray-500">Remaining</div>
            <div class="mt-1 text-2xl font-bold text-gray-900">
              <%= Number.Delimited.number_to_delimited(@budget_remaining, precision: 0) %> BUX
            </div>
          </div>

          <div class="bg-white rounded-lg shadow p-5">
            <div class="text-sm font-medium text-gray-500">Users Rewarded</div>
            <div class="mt-1 text-2xl font-bold text-gray-900">
              <%= @users_rewarded %>
            </div>
            <div class="mt-1 text-xs text-gray-500">today</div>
          </div>
        </div>

        <%!-- Current Promo --%>
        <div class="bg-white rounded-lg shadow mb-6">
          <div class="px-6 py-4 border-b border-gray-200">
            <h2 class="text-lg font-semibold text-gray-900">Current Promo</h2>
          </div>
          <div class="px-6 py-5">
            <%= if @current_promo do %>
              <div class="flex items-center justify-between">
                <div>
                  <div class="flex items-center gap-3">
                    <span class="text-2xl"><%= category_emoji(@current_promo.category) %></span>
                    <div>
                      <div class="text-lg font-semibold text-gray-900"><%= @current_promo.name %></div>
                      <div class="text-sm text-gray-500">
                        <%= format_category(@current_promo.category) %>
                        <span class="mx-1">&middot;</span>
                        Started <%= format_time(@current_promo.started_at) %>
                        <span class="mx-1">&middot;</span>
                        Expires <%= format_time(@current_promo.expires_at) %>
                      </div>
                    </div>
                  </div>
                </div>
                <span class="inline-flex items-center px-3 py-1 rounded-full text-xs font-medium bg-green-100 text-green-700">
                  Active
                </span>
              </div>
            <% else %>
              <p class="text-gray-500 text-sm">No promo currently active</p>
            <% end %>
          </div>
        </div>

        <%!-- Force Next + Run Now --%>
        <div class="bg-white rounded-lg shadow mb-6">
          <div class="px-6 py-4 border-b border-gray-200">
            <h2 class="text-lg font-semibold text-gray-900">Controls</h2>
          </div>
          <div class="px-6 py-5">
            <div class="flex flex-wrap items-center gap-3">
              <span class="text-sm font-medium text-gray-700">Force next:</span>
              <%= for cat <- @categories do %>
                <button
                  phx-click="force_next"
                  phx-value-category={cat}
                  class="px-3 py-1.5 text-sm font-medium rounded-lg bg-gray-100 text-gray-900 hover:bg-gray-200 cursor-pointer transition"
                >
                  <%= category_emoji(cat) %> <%= format_category(cat) %>
                  <span class="text-xs text-gray-500">(<%= @template_counts[cat] %>)</span>
                </button>
              <% end %>
              <div class="ml-auto">
                <button
                  phx-click="run_now"
                  class="px-4 py-2 text-sm font-medium rounded-lg bg-gray-900 text-white hover:bg-gray-800 cursor-pointer transition"
                >
                  Run Promo Now
                </button>
              </div>
            </div>
            <%= if @forced_category do %>
              <div class="mt-3 text-sm text-amber-600">
                Next promo forced to: <%= format_category(@forced_category) %>
              </div>
            <% end %>
          </div>
        </div>

        <%!-- Template Library --%>
        <div class="bg-white rounded-lg shadow mb-6">
          <div class="px-6 py-4 border-b border-gray-200">
            <h2 class="text-lg font-semibold text-gray-900">Template Library (15 templates)</h2>
          </div>
          <div class="overflow-x-auto">
            <table class="min-w-full divide-y divide-gray-200">
              <thead class="bg-gray-50">
                <tr>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Template</th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Category</th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Details</th>
                </tr>
              </thead>
              <tbody class="bg-white divide-y divide-gray-200">
                <%= for {category, templates} <- PromoEngine.all_templates() do %>
                  <%= for template <- templates do %>
                    <tr class="hover:bg-gray-50">
                      <td class="px-6 py-3 whitespace-nowrap">
                        <div class="text-sm font-medium text-gray-900"><%= template.name %></div>
                      </td>
                      <td class="px-6 py-3 whitespace-nowrap">
                        <span class="inline-flex items-center gap-1 text-sm text-gray-600">
                          <%= category_emoji(category) %> <%= format_category(category) %>
                        </span>
                      </td>
                      <td class="px-6 py-3 text-sm text-gray-500">
                        <%= template_detail(template) %>
                      </td>
                    </tr>
                  <% end %>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>

        <%!-- History --%>
        <div class="bg-white rounded-lg shadow">
          <div class="px-6 py-4 border-b border-gray-200">
            <h2 class="text-lg font-semibold text-gray-900">Recent History</h2>
          </div>
          <%= if length(@history) > 0 do %>
            <div class="overflow-x-auto">
              <table class="min-w-full divide-y divide-gray-200">
                <thead class="bg-gray-50">
                  <tr>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">#</th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Promo</th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Category</th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">ID</th>
                  </tr>
                </thead>
                <tbody class="bg-white divide-y divide-gray-200">
                  <%= for {entry, idx} <- Enum.with_index(@history) do %>
                    <tr class="hover:bg-gray-50">
                      <td class="px-6 py-3 whitespace-nowrap text-sm text-gray-400"><%= idx + 1 %></td>
                      <td class="px-6 py-3 whitespace-nowrap text-sm font-medium text-gray-900"><%= entry.name %></td>
                      <td class="px-6 py-3 whitespace-nowrap text-sm text-gray-600">
                        <%= category_emoji(entry.category) %> <%= format_category(entry.category) %>
                      </td>
                      <td class="px-6 py-3 whitespace-nowrap text-xs text-gray-400 font-mono"><%= entry.id %></td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          <% else %>
            <div class="px-6 py-8 text-center text-sm text-gray-500">
              No promo history yet. The bot hasn't run any promos.
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # ======== Helpers ========

  defp category_emoji(:bux_booster_rule), do: "🎰"
  defp category_emoji(:referral_boost), do: "🔥"
  defp category_emoji(:giveaway), do: "🎊"
  defp category_emoji(:competition), do: "🏆"
  defp category_emoji(_), do: "📢"

  defp format_category(:bux_booster_rule), do: "BUX Booster"
  defp format_category(:referral_boost), do: "Referral Boost"
  defp format_category(:giveaway), do: "Giveaway"
  defp format_category(:competition), do: "Competition"
  defp format_category(cat), do: to_string(cat)

  defp format_time(nil), do: "--"
  defp format_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M UTC")
  end

  defp template_detail(%{rule: %{"bux_bonus_formula" => formula}}) do
    "Formula: #{formula}"
  end

  defp template_detail(%{boost: boost}) do
    "Referrer: #{boost.referrer_signup_bux} / Referee: #{boost.referee_signup_bux} / Phone: #{boost.phone_verify_bux}"
  end

  defp template_detail(%{type: type, winner_count: count}) do
    "#{type} — #{count} winners"
  end

  defp template_detail(%{type: :new_members, prize_amount: amount}) do
    "New members — #{amount} BUX each"
  end

  defp template_detail(%{metric: metric, prize_pool: pool}) do
    "#{metric} — #{pool} BUX pool"
  end

  defp template_detail(_), do: ""
end
