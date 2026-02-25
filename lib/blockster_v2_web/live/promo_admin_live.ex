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

    {:ok, socket |> load_state() |> assign(:preview, nil)}
  end

  @impl true
  def handle_event("preview_template", %{"name" => name, "category" => category}, socket) do
    cat = String.to_existing_atom(category)
    templates = PromoEngine.all_templates()[cat] || []
    template = Enum.find(templates, &(&1.name == name))

    if template do
      {:noreply, assign(socket, :preview, %{template: template, category: cat})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("close_preview", _params, socket) do
    {:noreply, assign(socket, :preview, nil)}
  end

  def handle_event("toggle_bot", _params, socket) do
    current = SystemConfig.get("hourly_promo_enabled", false)
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

  def handle_event("clear_bot_rules", _params, socket) do
    PromoEngine.cleanup_all_bot_rules()
    {:noreply,
     socket
     |> put_flash(:info, "All bot rules cleared")}
  end

  def handle_event("run_now", _params, socket) do
    case HourlyPromoScheduler.run_now() do
      :ok ->
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
    bot_enabled = SystemConfig.get("hourly_promo_enabled", false)
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
            <%= cond do %>
              <% @scheduler_running and @bot_enabled -> %>
                <span class="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-full text-sm font-medium bg-green-100 text-green-700">
                  <span class="w-2 h-2 rounded-full bg-green-500" /> Running
                </span>
                <button
                  phx-click="toggle_bot"
                  class="px-4 py-2 rounded-lg text-sm font-medium cursor-pointer transition bg-red-600 text-white hover:bg-red-700"
                >
                  Pause Bot
                </button>
              <% @scheduler_running and !@bot_enabled -> %>
                <span class="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-full text-sm font-medium bg-yellow-100 text-yellow-700">
                  <span class="w-2 h-2 rounded-full bg-yellow-500" /> Paused
                </span>
                <button
                  phx-click="toggle_bot"
                  class="px-4 py-2 rounded-lg text-sm font-medium cursor-pointer transition bg-gray-900 text-white hover:bg-gray-800"
                >
                  Resume Bot
                </button>
              <% true -> %>
                <span class="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-full text-sm font-medium bg-red-100 text-red-700">
                  <span class="w-2 h-2 rounded-full bg-red-500" /> Scheduler Not Running
                </span>
            <% end %>
          </div>
        </div>

        <%!-- Stats Cards --%>
        <div class="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
          <div class="bg-white rounded-lg shadow p-5">
            <div class="text-sm font-medium text-gray-500">Promos Sent</div>
            <div class="mt-1 text-2xl font-bold text-gray-900">
              <%= length(@history) %>
            </div>
            <div class="mt-1 text-xs text-gray-500">today</div>
          </div>

          <div class="bg-white rounded-lg shadow p-5">
            <div class="text-sm font-medium text-gray-500">Budget Today</div>
            <div class="mt-1 text-2xl font-bold text-gray-900">
              <%= Number.Delimit.number_to_delimited(@daily_state.total_bux_given, precision: 0) %> / 100,000
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
              <%= Number.Delimit.number_to_delimited(@budget_remaining, precision: 0) %> BUX
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
              <div class="ml-auto flex items-center gap-2">
                <button
                  phx-click="clear_bot_rules"
                  data-confirm="Delete all telegram bot custom rules?"
                  class="px-4 py-2 text-sm font-medium rounded-lg bg-red-100 text-red-700 hover:bg-red-200 cursor-pointer transition"
                >
                  Clear Bot Rules
                </button>
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
                  <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider"></th>
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
                      <td class="px-6 py-3 text-right">
                        <button
                          phx-click="preview_template"
                          phx-value-name={template.name}
                          phx-value-category={category}
                          class="text-sm text-blue-600 hover:text-blue-800 cursor-pointer font-medium"
                        >
                          Preview
                        </button>
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
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Started</th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Expires</th>
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
                      <td class="px-6 py-3 whitespace-nowrap text-sm text-gray-500"><%= format_datetime(entry[:started_at]) %></td>
                      <td class="px-6 py-3 whitespace-nowrap text-sm text-gray-500"><%= format_datetime(entry[:expires_at]) %></td>
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
        <%!-- Preview Modal --%>
        <%= if @preview do %>
          <div class="fixed inset-0 z-50 overflow-y-auto" phx-window-keydown="close_preview" phx-key="Escape">
            <div class="flex items-start justify-center min-h-screen px-4 pt-20 pb-8">
              <div class="fixed inset-0 bg-black/50 transition-opacity" phx-click="close_preview" />
              <div class="relative bg-white rounded-xl shadow-2xl max-w-2xl w-full">
                <%!-- Modal Header --%>
                <div class="flex items-center justify-between px-6 py-4 border-b border-gray-200">
                  <div class="flex items-center gap-2">
                    <span class="text-xl"><%= category_emoji(@preview.category) %></span>
                    <h3 class="text-lg font-semibold text-gray-900"><%= @preview.template.name %></h3>
                  </div>
                  <button phx-click="close_preview" class="text-gray-400 hover:text-gray-600 cursor-pointer">
                    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                    </svg>
                  </button>
                </div>

                <%!-- Telegram Message Preview --%>
                <div class="px-6 py-4 border-b border-gray-200">
                  <div class="text-xs font-medium text-gray-500 uppercase tracking-wider mb-3">Telegram Message</div>
                  <div class="bg-[#1B2836] rounded-xl p-4 text-sm text-gray-100 leading-relaxed font-sans [&_b]:font-bold [&_a]:text-blue-400 [&_a]:no-underline">
                    <%= raw(telegram_to_html(get_announcement_text(@preview.template))) %>
                  </div>
                </div>

                <%!-- Rules Explanation --%>
                <div class="px-6 py-4">
                  <div class="text-xs font-medium text-gray-500 uppercase tracking-wider mb-3">How It Works</div>
                  <div class="space-y-3 text-sm text-gray-700">
                    <%= raw(explain_rules(@preview.template, @preview.category)) %>
                  </div>
                </div>

                <%!-- Close --%>
                <div class="px-6 py-4 border-t border-gray-200 flex justify-end">
                  <button
                    phx-click="close_preview"
                    class="px-4 py-2 text-sm font-medium rounded-lg bg-gray-100 text-gray-900 hover:bg-gray-200 cursor-pointer transition"
                  >
                    Close
                  </button>
                </div>
              </div>
            </div>
          </div>
        <% end %>
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
    dt |> DateTime.add(-5 * 3600) |> Calendar.strftime("%H:%M EST")
  end

  defp format_datetime(nil), do: "--"
  defp format_datetime(%DateTime{} = dt) do
    dt |> DateTime.add(-5 * 3600) |> Calendar.strftime("%b %d %H:%M EST")
  end

  defp template_detail(%{rule: %{"bux_bonus_formula" => formula}}) do
    "Formula: #{formula}"
  end

  defp template_detail(%{boost: boost}) do
    "Referrer: #{boost.referrer_signup_bux} / Referee: #{boost.referee_signup_bux} / Phone: #{boost.phone_verify_bux}"
  end

  defp template_detail(%{type: :new_members, prize_amount: amount}) do
    "New members — #{amount} BUX each"
  end

  defp template_detail(%{type: type, winner_count: count}) do
    "#{type} — #{count} winners"
  end

  defp template_detail(%{metric: metric, prize_pool: pool}) do
    "#{metric} — #{pool} BUX pool"
  end

  defp template_detail(_), do: ""

  # ======== Preview Helpers ========

  defp get_announcement_text(%{announcement: text}) when is_binary(text), do: text
  defp get_announcement_text(%{name: name}), do: "<b>#{name}</b>\n\nNo announcement text configured."

  defp telegram_to_html(text) do
    String.replace(text, "\n", "<br>")
  end

  defp explain_rules(%{rule: rule} = template, :bux_booster_rule) do
    formula = rule["bux_bonus_formula"] || "unknown"
    every_n = rule["every_n_formula"]
    conditions = rule["conditions"]

    # Parse the bonus percentage from the formula
    {bonus_desc, examples} = explain_formula(formula)

    freq_desc = explain_frequency(every_n)

    condition_desc = explain_conditions(conditions)

    """
    <div class="space-y-4">
      <div>
        <div class="font-semibold text-gray-900 mb-1">Bonus Reward</div>
        <p>#{bonus_desc}</p>
      </div>

      <div>
        <div class="font-semibold text-gray-900 mb-1">Trigger Frequency</div>
        <p>#{freq_desc}</p>
      </div>

      #{condition_desc}

      <div>
        <div class="font-semibold text-gray-900 mb-1">Examples (1,000 BUX stake)</div>
        <table class="w-full text-xs">
          <thead><tr class="text-gray-500">
            <th class="text-left py-1">Outcome</th>
            <th class="text-right py-1">Profit/Loss</th>
            <th class="text-right py-1">Bonus</th>
          </tr></thead>
          <tbody class="font-mono">
            #{examples}
          </tbody>
        </table>
      </div>

      <div>
        <div class="font-semibold text-gray-900 mb-1">Budget Limits</div>
        <p>Daily cap: 100,000 BUX across all promos. Max 10 rewards per user per day.</p>
      </div>

      <div>
        <div class="font-semibold text-gray-900 mb-1">Raw Formula</div>
        <code class="text-xs bg-gray-100 px-2 py-1 rounded block break-all">#{formula}</code>
      </div>
    </div>
    """
  end

  defp explain_rules(%{boost: boost, original: original}, :referral_boost) do
    """
    <div class="space-y-4">
      <div>
        <div class="font-semibold text-gray-900 mb-1">Boosted Referral Rates</div>
        <p>During this promo, referral rewards are temporarily increased:</p>
      </div>

      <table class="w-full text-sm">
        <thead><tr class="text-gray-500 text-xs">
          <th class="text-left py-1">Reward</th>
          <th class="text-right py-1">Normal</th>
          <th class="text-right py-1">Boosted</th>
        </tr></thead>
        <tbody>
          <tr class="border-t border-gray-100">
            <td class="py-1.5">Referrer signup bonus</td>
            <td class="text-right text-gray-500">#{Number.Delimit.number_to_delimited(original.referrer_signup_bux, precision: 0)} BUX</td>
            <td class="text-right font-semibold text-green-700">#{Number.Delimit.number_to_delimited(boost.referrer_signup_bux, precision: 0)} BUX</td>
          </tr>
          <tr class="border-t border-gray-100">
            <td class="py-1.5">New user welcome bonus</td>
            <td class="text-right text-gray-500">#{Number.Delimit.number_to_delimited(original.referee_signup_bux, precision: 0)} BUX</td>
            <td class="text-right font-semibold text-green-700">#{Number.Delimit.number_to_delimited(boost.referee_signup_bux, precision: 0)} BUX</td>
          </tr>
          <tr class="border-t border-gray-100">
            <td class="py-1.5">Phone verification bonus</td>
            <td class="text-right text-gray-500">#{Number.Delimit.number_to_delimited(original.phone_verify_bux, precision: 0)} BUX</td>
            <td class="text-right font-semibold text-green-700">#{Number.Delimit.number_to_delimited(boost.phone_verify_bux, precision: 0)} BUX</td>
          </tr>
        </tbody>
      </table>

      <div>
        <div class="font-semibold text-gray-900 mb-1">How It Works</div>
        <p>The bot temporarily overwrites the referral config in SystemConfig. When the promo ends, original rates are restored automatically.</p>
      </div>
    </div>
    """
  end

  defp explain_rules(%{type: :activity_based, event_type: event, winner_count: count, prize_range: {min_p, max_p}}, :giveaway) do
    activity = if event == "article_view", do: "reading an article", else: event

    """
    <div class="space-y-4">
      <div>
        <div class="font-semibold text-gray-900 mb-1">Activity-Based Giveaway</div>
        <p>Users enter by #{activity} on blockster.com during the promo hour.</p>
      </div>

      <div>
        <div class="font-semibold text-gray-900 mb-1">Prize Details</div>
        <ul class="list-disc pl-4 space-y-1">
          <li><strong>#{count}</strong> random winners selected at end of hour</li>
          <li>Each winner gets <strong>#{min_p}-#{max_p} BUX</strong> (random within range)</li>
          <li>Must have a linked Telegram account and smart wallet</li>
        </ul>
      </div>

      <div>
        <div class="font-semibold text-gray-900 mb-1">Settlement</div>
        <p>At the end of the hour, the system queries UserEvent for all "#{event}" events during the promo window, randomly picks #{count} users, and mints BUX to their wallets.</p>
      </div>
    </div>
    """
  end

  defp explain_rules(%{type: :auto_entry, winner_count: count, prize_range: {min_p, max_p}}, :giveaway) do
    """
    <div class="space-y-4">
      <div>
        <div class="font-semibold text-gray-900 mb-1">Auto-Entry Giveaway</div>
        <p>All linked Telegram group members are automatically entered. No action needed.</p>
      </div>

      <div>
        <div class="font-semibold text-gray-900 mb-1">Prize Details</div>
        <ul class="list-disc pl-4 space-y-1">
          <li><strong>#{count}</strong> random winners drawn at end of hour</li>
          <li>Each winner gets <strong>#{min_p}-#{max_p} BUX</strong></li>
          <li>Must have Telegram linked + smart wallet</li>
        </ul>
      </div>
    </div>
    """
  end

  defp explain_rules(%{type: :new_members, prize_amount: amount}, :giveaway) do
    """
    <div class="space-y-4">
      <div>
        <div class="font-semibold text-gray-900 mb-1">New Member Welcome Drop</div>
        <p>Anyone who joined the Telegram group during this promo hour gets rewarded automatically.</p>
      </div>

      <div>
        <div class="font-semibold text-gray-900 mb-1">Prize Details</div>
        <ul class="list-disc pl-4 space-y-1">
          <li>Every new member gets <strong>#{Number.Delimit.number_to_delimited(amount, precision: 0)} BUX</strong></li>
          <li>Based on <code>telegram_group_joined_at</code> timestamp</li>
          <li>Must have a smart wallet to receive BUX</li>
        </ul>
      </div>
    </div>
    """
  end

  defp explain_rules(%{metric: metric, event_type: event, prize_pool: pool, top_n: top_n, distribution: dist}, :competition) do
    metric_desc = case metric do
      :articles_read -> "most articles read"
      :bet_count -> "most BUX Booster bets placed"
      _ -> to_string(metric)
    end

    prizes = PromoEngine.distribute_prizes(pool, dist, top_n, top_n)
    medals = ["1st", "2nd", "3rd"]
    prize_rows = prizes
      |> Enum.with_index()
      |> Enum.map(fn {prize, idx} ->
        place = Enum.at(medals, idx, "#{idx + 1}th")
        "<tr class=\"border-t border-gray-100\"><td class=\"py-1\">#{place}</td><td class=\"text-right font-semibold\">#{trunc(prize)} BUX</td></tr>"
      end)
      |> Enum.join("\n")

    """
    <div class="space-y-4">
      <div>
        <div class="font-semibold text-gray-900 mb-1">Hourly Competition</div>
        <p>The users with the <strong>#{metric_desc}</strong> during the promo hour win prizes.</p>
      </div>

      <div>
        <div class="font-semibold text-gray-900 mb-1">Prizes (#{Number.Delimit.number_to_delimited(pool, precision: 0)} BUX pool)</div>
        <table class="w-full text-sm">
          <thead><tr class="text-gray-500 text-xs"><th class="text-left py-1">Place</th><th class="text-right py-1">Prize</th></tr></thead>
          <tbody>#{prize_rows}</tbody>
        </table>
      </div>

      <div>
        <div class="font-semibold text-gray-900 mb-1">How It's Tracked</div>
        <p>Counts <code>#{event}</code> events per user during the promo window. Only users with a linked Telegram account and smart wallet are eligible. If fewer than #{top_n} users participate, prizes are redistributed to fewer winners.</p>
      </div>
    </div>
    """
  end

  defp explain_rules(_template, _category) do
    "<p class=\"text-gray-500\">No detailed rules for this template type.</p>"
  end

  # Parse bonus formula into human-readable description + example rows
  defp explain_formula(formula) do
    cond do
      String.contains?(formula, "random(") ->
        # Extract the random range, e.g. random(10, 50)
        case Regex.run(~r/random\((\d+),\s*(\d+)\)/, formula) do
          [_, low, high] ->
            mid = (String.to_integer(low) + String.to_integer(high)) / 2
            desc = "Random #{low}-#{high}% of your profit (on wins) or stake (on losses), plus a small ROGUE holder bonus (0.01% of your ROGUE balance)."
            examples = bonus_examples(mid / 100)
            {desc, examples}
          _ ->
            {"Custom formula with random element.", bonus_examples(0.25)}
        end

      true ->
        # Extract fixed percentage, e.g. * 0.2
        case Regex.run(~r/\*\s*(0\.\d+)/, formula) do
          [_, pct_str] ->
            pct = String.to_float(pct_str)
            pct_int = trunc(pct * 100)
            desc = "#{pct_int}% of your profit (on wins) or stake (on losses), plus a small ROGUE holder bonus (0.01% of your ROGUE balance)."
            examples = bonus_examples(pct)
            {desc, examples}
          _ ->
            {"Custom bonus formula.", bonus_examples(0.2)}
        end
    end
  end

  defp bonus_examples(pct) do
    stake = 1000
    multipliers = [
      {1.05, "1.05x win"},
      {1.32, "1.32x win"},
      {1.98, "1.98x win"},
      {3.96, "3.96x win"},
      {7.92, "7.92x win"},
      {31.68, "31.68x win"},
      {0, "Loss"}
    ]

    multipliers
    |> Enum.map(fn {mult, label} ->
      if mult == 0 do
        bonus = trunc(stake * pct)
        "<tr class=\"border-t border-gray-100\"><td class=\"py-1\">#{label}</td><td class=\"text-right\">-#{stake}</td><td class=\"text-right font-semibold text-green-700\">+#{bonus} BUX</td></tr>"
      else
        profit = trunc(stake * mult - stake)
        bonus = trunc(profit * pct)
        "<tr class=\"border-t border-gray-100\"><td class=\"py-1\">#{label}</td><td class=\"text-right text-green-700\">+#{Number.Delimit.number_to_delimited(profit, precision: 0)}</td><td class=\"text-right font-semibold text-green-700\">+#{Number.Delimit.number_to_delimited(bonus, precision: 0)} BUX</td></tr>"
      end
    end)
    |> Enum.join("\n")
  end

  defp explain_frequency(nil), do: "Triggers on every qualifying bet."
  defp explain_frequency(formula) do
    cond do
      String.contains?(formula, "random(") ->
        case Regex.scan(~r/(\d+)/, formula) |> List.flatten() do
          nums when length(nums) >= 2 ->
            "Triggers randomly every few bets (varies by formula). Holding more ROGUE makes it trigger more often."
          _ ->
            "Variable trigger frequency. ROGUE holders trigger more often."
        end

      true ->
        case Regex.run(~r/max\((\d+)/, formula) do
          [_, base] ->
            "Starts at every ~#{base} bets with 0 ROGUE. Holding more ROGUE reduces the interval (triggers more often)."
          _ ->
            "Trigger frequency scales with ROGUE balance."
        end
    end
  end

  defp explain_conditions(nil), do: ""
  defp explain_conditions(conditions) when map_size(conditions) == 0, do: ""
  defp explain_conditions(conditions) do
    lines = Enum.map(conditions, fn {field, rule} ->
      cond do
        is_map(rule) and Map.has_key?(rule, "$gte") ->
          "<li><strong>#{field}</strong> must be >= #{rule["$gte"]}</li>"
        is_map(rule) and Map.has_key?(rule, "$lte") ->
          "<li><strong>#{field}</strong> must be <= #{rule["$lte"]}</li>"
        true ->
          "<li><strong>#{field}</strong>: #{inspect(rule)}</li>"
      end
    end) |> Enum.join("\n")

    """
    <div>
      <div class="font-semibold text-gray-900 mb-1">Conditions</div>
      <ul class="list-disc pl-4 space-y-1">#{lines}</ul>
    </div>
    """
  end
end
