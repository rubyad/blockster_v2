defmodule BlocksterV2Web.RulesAdminLive.Index do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.Notifications.SystemConfig

  @channel_options [
    {"in_app", "In-App"},
    {"email", "Email"},
    {"telegram", "Telegram"},
    {"both", "In-App + Email"},
    {"all", "All Channels"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    rules = SystemConfig.get("custom_rules", [])

    {:ok,
     socket
     |> assign(:page_title, "Custom Notification Rules")
     |> assign(:rules, rules)
     |> assign(:editing, nil)
     |> assign(:form_data, %{})
     |> assign(:form_errors, %{})}
  end

  @impl true
  def handle_event("add_rule", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing, :new)
     |> assign(:form_data, default_form())
     |> assign(:form_errors, %{})}
  end

  def handle_event("edit_rule", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)
    rule = Enum.at(socket.assigns.rules, index)

    if rule do
      form_data = %{
        "event_type" => rule["event_type"] || "",
        "title" => rule["title"] || "",
        "body" => rule["body"] || "",
        "channel" => rule["channel"] || "in_app",
        "notification_type" => rule["notification_type"] || "special_offer",
        "subject" => rule["subject"] || "",
        "action_url" => rule["action_url"] || "",
        "action_label" => rule["action_label"] || "",
        "bux_bonus" => to_string(rule["bux_bonus"] || ""),
        "rogue_bonus" => to_string(rule["rogue_bonus"] || ""),
        "bux_bonus_formula" => rule["bux_bonus_formula"] || "",
        "rogue_bonus_formula" => rule["rogue_bonus_formula"] || "",
        "recurring" => if(rule["recurring"] == true, do: "true", else: "false"),
        "every_n" => to_string(rule["every_n"] || ""),
        "every_n_formula" => rule["every_n_formula"] || "",
        "count_field" => rule["count_field"] || "total_bets",
        "conditions" => format_conditions(rule["conditions"])
      }

      {:noreply,
       socket
       |> assign(:editing, index)
       |> assign(:form_data, form_data)
       |> assign(:form_errors, %{})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing, nil)
     |> assign(:form_data, %{})
     |> assign(:form_errors, %{})}
  end

  def handle_event("save_rule", params, socket) do
    case validate_form(params) do
      {:ok, rule} ->
        rules = socket.assigns.rules
        editing = socket.assigns.editing
        user_email = socket.assigns.current_user.email || "admin"

        updated_rules =
          if editing == :new do
            rules ++ [rule]
          else
            List.replace_at(rules, editing, rule)
          end

        SystemConfig.put("custom_rules", updated_rules, "admin:#{user_email}")

        action_text = if editing == :new, do: "created", else: "updated"

        {:noreply,
         socket
         |> assign(:rules, updated_rules)
         |> assign(:editing, nil)
         |> assign(:form_data, %{})
         |> assign(:form_errors, %{})
         |> put_flash(:info, "Rule #{action_text} successfully.")}

      {:error, errors} ->
        {:noreply, assign(socket, :form_errors, errors)}
    end
  end

  def handle_event("delete_rule", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)
    rules = socket.assigns.rules
    user_email = socket.assigns.current_user.email || "admin"

    if index >= 0 and index < length(rules) do
      updated_rules = List.delete_at(rules, index)
      SystemConfig.put("custom_rules", updated_rules, "admin:#{user_email}")

      # Adjust editing index if needed
      editing =
        cond do
          socket.assigns.editing == nil -> nil
          socket.assigns.editing == :new -> :new
          socket.assigns.editing == index -> nil
          is_integer(socket.assigns.editing) and socket.assigns.editing > index -> socket.assigns.editing - 1
          true -> socket.assigns.editing
        end

      {:noreply,
       socket
       |> assign(:rules, updated_rules)
       |> assign(:editing, editing)
       |> put_flash(:info, "Rule deleted.")}
    else
      {:noreply, put_flash(socket, :error, "Invalid rule index.")}
    end
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :channel_options, @channel_options)

    ~H"""
    <div class="min-h-screen bg-[#F5F6FB]">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 pt-24 pb-12">
        <%!-- Header --%>
        <div class="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 mb-8">
          <div>
            <div class="flex items-center gap-3 mb-1">
              <.link navigate={~p"/admin/notifications/campaigns"} class="text-gray-400 hover:text-gray-600 cursor-pointer">
                <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
                  <path fill-rule="evenodd" d="M9.707 16.707a1 1 0 01-1.414 0l-6-6a1 1 0 010-1.414l6-6a1 1 0 011.414 1.414L5.414 9H17a1 1 0 110 2H5.414l4.293 4.293a1 1 0 010 1.414z" clip-rule="evenodd" />
                </svg>
              </.link>
              <h1 class="text-3xl font-haas_medium_65 text-[#141414]">Custom Rules</h1>
            </div>
            <p class="text-gray-500 mt-1 font-haas_roman_55">Event-driven notification rules with optional BUX/ROGUE bonuses</p>
          </div>
          <div class="flex gap-3">
            <.link navigate={~p"/admin/ai-manager"} class="px-4 py-2.5 bg-white rounded-xl text-sm font-haas_roman_55 text-gray-600 hover:bg-gray-50 border border-gray-200 cursor-pointer transition-all">
              AI Manager
            </.link>
            <button phx-click="add_rule" class="px-4 py-2.5 bg-gray-900 rounded-xl text-sm font-haas_medium_65 text-white hover:bg-gray-800 cursor-pointer transition-all">
              + New Rule
            </button>
          </div>
        </div>

        <%!-- Inline Form --%>
        <%= if @editing != nil do %>
          <div class="bg-white rounded-2xl shadow-sm border border-gray-100 p-6 mb-8">
            <div class="flex items-center gap-3 mb-5">
              <div class="w-8 h-8 bg-[#CAFC00] rounded-lg flex items-center justify-center">
                <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4 text-black" viewBox="0 0 20 20" fill="currentColor">
                  <path fill-rule="evenodd" d="M11.49 3.17c-.38-1.56-2.6-1.56-2.98 0a1.532 1.532 0 01-2.286.948c-1.372-.836-2.942.734-2.106 2.106.54.886.061 2.042-.947 2.287-1.561.379-1.561 2.6 0 2.978a1.532 1.532 0 01.947 2.287c-.836 1.372.734 2.942 2.106 2.106a1.532 1.532 0 012.287.947c.379 1.561 2.6 1.561 2.978 0a1.533 1.533 0 012.287-.947c1.372.836 2.942-.734 2.106-2.106a1.533 1.533 0 01.947-2.287c1.561-.379 1.561-2.6 0-2.978a1.532 1.532 0 01-.947-2.287c.836-1.372-.734-2.942-2.106-2.106a1.532 1.532 0 01-2.287-.947zM10 13a3 3 0 100-6 3 3 0 000 6z" clip-rule="evenodd" />
                </svg>
              </div>
              <h2 class="text-lg font-haas_medium_65 text-[#141414]">
                <%= if @editing == :new, do: "New Rule", else: "Edit Rule ##{@editing + 1}" %>
              </h2>
            </div>

            <form phx-submit="save_rule" class="space-y-4">
              <%!-- Row 1: Event Type + Channel --%>
              <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
                <div>
                  <label class="block text-sm font-haas_medium_65 text-gray-700 mb-1">Event Type *</label>
                  <input type="text" name="event_type" value={@form_data["event_type"]} required
                    placeholder="e.g. bet_settled, signup, phone_verified"
                    class={"w-full px-4 py-2.5 bg-[#F5F6FB] border-0 rounded-xl text-sm font-haas_roman_55 focus:ring-2 focus:ring-gray-400 #{if @form_errors["event_type"], do: "ring-2 ring-red-400"}"} />
                  <%= if @form_errors["event_type"] do %>
                    <p class="text-xs text-red-500 mt-1"><%= @form_errors["event_type"] %></p>
                  <% end %>
                </div>
                <div>
                  <label class="block text-sm font-haas_medium_65 text-gray-700 mb-1">Channel</label>
                  <select name="channel" class="w-full px-4 py-2.5 bg-[#F5F6FB] border-0 rounded-xl text-sm font-haas_roman_55 focus:ring-2 focus:ring-gray-400 cursor-pointer">
                    <%= for {value, label} <- @channel_options do %>
                      <option value={value} selected={@form_data["channel"] == value}><%= label %></option>
                    <% end %>
                  </select>
                </div>
                <div>
                  <label class="block text-sm font-haas_medium_65 text-gray-700 mb-1">Notification Type</label>
                  <input type="text" name="notification_type" value={@form_data["notification_type"]}
                    placeholder="special_offer"
                    class="w-full px-4 py-2.5 bg-[#F5F6FB] border-0 rounded-xl text-sm font-haas_roman_55 focus:ring-2 focus:ring-gray-400" />
                </div>
              </div>

              <%!-- Row 2: Title + Subject --%>
              <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div>
                  <label class="block text-sm font-haas_medium_65 text-gray-700 mb-1">Title *</label>
                  <input type="text" name="title" value={@form_data["title"]} required
                    placeholder="Notification title"
                    class={"w-full px-4 py-2.5 bg-[#F5F6FB] border-0 rounded-xl text-sm font-haas_roman_55 focus:ring-2 focus:ring-gray-400 #{if @form_errors["title"], do: "ring-2 ring-red-400"}"} />
                  <%= if @form_errors["title"] do %>
                    <p class="text-xs text-red-500 mt-1"><%= @form_errors["title"] %></p>
                  <% end %>
                </div>
                <div>
                  <label class="block text-sm font-haas_medium_65 text-gray-700 mb-1">Email Subject</label>
                  <input type="text" name="subject" value={@form_data["subject"]}
                    placeholder="Subject line for email notifications"
                    class="w-full px-4 py-2.5 bg-[#F5F6FB] border-0 rounded-xl text-sm font-haas_roman_55 focus:ring-2 focus:ring-gray-400" />
                </div>
              </div>

              <%!-- Row 3: Body --%>
              <div>
                <label class="block text-sm font-haas_medium_65 text-gray-700 mb-1">Body *</label>
                <textarea name="body" rows="2" required
                  placeholder={"Notification body text. Use {username}, {amount}, etc. for interpolation."}
                  class={"w-full px-4 py-2.5 bg-[#F5F6FB] border-0 rounded-xl text-sm font-haas_roman_55 focus:ring-2 focus:ring-gray-400 #{if @form_errors["body"], do: "ring-2 ring-red-400"}"}><%= @form_data["body"] %></textarea>
                <%= if @form_errors["body"] do %>
                  <p class="text-xs text-red-500 mt-1"><%= @form_errors["body"] %></p>
                <% end %>
              </div>

              <%!-- Row 4: Action URL + Label --%>
              <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div>
                  <label class="block text-sm font-haas_medium_65 text-gray-700 mb-1">Action URL</label>
                  <input type="text" name="action_url" value={@form_data["action_url"]}
                    placeholder="/play or https://..."
                    class="w-full px-4 py-2.5 bg-[#F5F6FB] border-0 rounded-xl text-sm font-haas_roman_55 focus:ring-2 focus:ring-gray-400" />
                </div>
                <div>
                  <label class="block text-sm font-haas_medium_65 text-gray-700 mb-1">Action Label</label>
                  <input type="text" name="action_label" value={@form_data["action_label"]}
                    placeholder="e.g. Play Now, View Rewards"
                    class="w-full px-4 py-2.5 bg-[#F5F6FB] border-0 rounded-xl text-sm font-haas_roman_55 focus:ring-2 focus:ring-gray-400" />
                </div>
              </div>

              <%!-- Row 5: BUX + ROGUE bonuses (static) --%>
              <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div>
                  <label class="block text-sm font-haas_medium_65 text-gray-700 mb-1">BUX Bonus (static)</label>
                  <input type="number" name="bux_bonus" value={@form_data["bux_bonus"]} min="0" step="1"
                    placeholder="0"
                    class="w-full px-4 py-2.5 bg-[#F5F6FB] border-0 rounded-xl text-sm font-haas_roman_55 focus:ring-2 focus:ring-gray-400" />
                </div>
                <div>
                  <label class="block text-sm font-haas_medium_65 text-gray-700 mb-1">ROGUE Bonus (static)</label>
                  <input type="number" name="rogue_bonus" value={@form_data["rogue_bonus"]} min="0" step="any"
                    placeholder="0"
                    class="w-full px-4 py-2.5 bg-[#F5F6FB] border-0 rounded-xl text-sm font-haas_roman_55 focus:ring-2 focus:ring-gray-400" />
                </div>
              </div>

              <%!-- Row 5b: BUX + ROGUE formula bonuses --%>
              <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div>
                  <label class="block text-sm font-haas_medium_65 text-gray-700 mb-1">BUX Bonus Formula</label>
                  <input type="text" name="bux_bonus_formula" value={@form_data["bux_bonus_formula"]}
                    placeholder="e.g. total_bets * 10, random(100, 500)"
                    class={"w-full px-4 py-2.5 bg-[#F5F6FB] border-0 rounded-xl text-sm font-mono focus:ring-2 focus:ring-gray-400 #{if @form_errors["bux_bonus_formula"], do: "ring-2 ring-red-400"}"} />
                  <%= if @form_errors["bux_bonus_formula"] do %>
                    <p class="text-xs text-red-500 mt-1"><%= @form_errors["bux_bonus_formula"] %></p>
                  <% end %>
                </div>
                <div>
                  <label class="block text-sm font-haas_medium_65 text-gray-700 mb-1">ROGUE Bonus Formula</label>
                  <input type="text" name="rogue_bonus_formula" value={@form_data["rogue_bonus_formula"]}
                    placeholder="e.g. rogue_balance * 0.0001"
                    class={"w-full px-4 py-2.5 bg-[#F5F6FB] border-0 rounded-xl text-sm font-mono focus:ring-2 focus:ring-gray-400 #{if @form_errors["rogue_bonus_formula"], do: "ring-2 ring-red-400"}"} />
                  <%= if @form_errors["rogue_bonus_formula"] do %>
                    <p class="text-xs text-red-500 mt-1"><%= @form_errors["rogue_bonus_formula"] %></p>
                  <% end %>
                </div>
              </div>
              <p class="text-xs text-gray-400 font-haas_roman_55 -mt-2">Formulas take precedence over static bonuses. Use metadata variables: <code class="bg-gray-100 px-1 rounded">total_bets</code>, <code class="bg-gray-100 px-1 rounded">bux_balance</code>, <code class="bg-gray-100 px-1 rounded">rogue_balance</code>, etc. Functions: <code class="bg-gray-100 px-1 rounded">random(min, max)</code>, <code class="bg-gray-100 px-1 rounded">min(a, b)</code>, <code class="bg-gray-100 px-1 rounded">max(a, b)</code></p>

              <%!-- Row 5c: Recurring rule settings --%>
              <div class="border-t border-gray-100 pt-4 mt-2">
                <div class="flex items-center gap-3 mb-3">
                  <label class="flex items-center gap-2 cursor-pointer">
                    <input type="hidden" name="recurring" value="false" />
                    <input type="checkbox" name="recurring" value="true" checked={@form_data["recurring"] == "true"}
                      class="w-4 h-4 rounded border-gray-300 text-gray-900 focus:ring-gray-400 cursor-pointer" />
                    <span class="text-sm font-haas_medium_65 text-gray-700">Recurring Rule</span>
                  </label>
                  <span class="text-xs text-gray-400 font-haas_roman_55">Fires repeatedly at intervals instead of once</span>
                </div>

                <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
                  <div>
                    <label class="block text-sm font-haas_medium_65 text-gray-700 mb-1">Every N (static)</label>
                    <input type="number" name="every_n" value={@form_data["every_n"]} min="1" step="1"
                      placeholder="e.g. 10"
                      class={"w-full px-4 py-2.5 bg-[#F5F6FB] border-0 rounded-xl text-sm font-haas_roman_55 focus:ring-2 focus:ring-gray-400 #{if @form_errors["every_n"], do: "ring-2 ring-red-400"}"} />
                    <%= if @form_errors["every_n"] do %>
                      <p class="text-xs text-red-500 mt-1"><%= @form_errors["every_n"] %></p>
                    <% end %>
                  </div>
                  <div>
                    <label class="block text-sm font-haas_medium_65 text-gray-700 mb-1">Every N Formula</label>
                    <input type="text" name="every_n_formula" value={@form_data["every_n_formula"]}
                      placeholder="e.g. random(5, 15)"
                      class={"w-full px-4 py-2.5 bg-[#F5F6FB] border-0 rounded-xl text-sm font-mono focus:ring-2 focus:ring-gray-400 #{if @form_errors["every_n_formula"], do: "ring-2 ring-red-400"}"} />
                    <%= if @form_errors["every_n_formula"] do %>
                      <p class="text-xs text-red-500 mt-1"><%= @form_errors["every_n_formula"] %></p>
                    <% end %>
                  </div>
                  <div>
                    <label class="block text-sm font-haas_medium_65 text-gray-700 mb-1">Count Field</label>
                    <select name="count_field" class="w-full px-4 py-2.5 bg-[#F5F6FB] border-0 rounded-xl text-sm font-haas_roman_55 focus:ring-2 focus:ring-gray-400 cursor-pointer">
                      <%= for {value, label} <- count_field_options() do %>
                        <option value={value} selected={@form_data["count_field"] == value}><%= label %></option>
                      <% end %>
                    </select>
                  </div>
                </div>
              </div>

              <%!-- Row 6: Conditions --%>
              <div>
                <label class="block text-sm font-haas_medium_65 text-gray-700 mb-1">Conditions (JSON, optional)</label>
                <textarea name="conditions" rows="2"
                  placeholder={"e.g. {\"result\": \"win\", \"multiplier\": {\"$gte\": 10}}"}
                  class={"w-full px-4 py-2.5 bg-[#F5F6FB] border-0 rounded-xl text-sm font-mono focus:ring-2 focus:ring-gray-400 #{if @form_errors["conditions"], do: "ring-2 ring-red-400"}"}><%= @form_data["conditions"] %></textarea>
                <%= if @form_errors["conditions"] do %>
                  <p class="text-xs text-red-500 mt-1"><%= @form_errors["conditions"] %></p>
                <% end %>
              </div>

              <%!-- Buttons --%>
              <div class="flex gap-3 pt-2">
                <button type="submit" class="px-5 py-2.5 bg-gray-900 rounded-xl text-sm font-haas_medium_65 text-white hover:bg-gray-800 cursor-pointer transition-colors">
                  <%= if @editing == :new, do: "Create Rule", else: "Save Changes" %>
                </button>
                <button type="button" phx-click="cancel_edit" class="px-5 py-2.5 bg-gray-100 rounded-xl text-sm font-haas_medium_65 text-gray-600 hover:bg-gray-200 cursor-pointer transition-colors">
                  Cancel
                </button>
              </div>
            </form>
          </div>
        <% end %>

        <%!-- Rules Table --%>
        <div class="bg-white rounded-2xl shadow-sm border border-gray-100 overflow-hidden">
          <%= if Enum.empty?(@rules) do %>
            <div class="text-center py-16">
              <div class="w-16 h-16 bg-[#F5F6FB] rounded-2xl flex items-center justify-center mx-auto mb-4">
                <svg xmlns="http://www.w3.org/2000/svg" class="h-8 w-8 text-gray-400" viewBox="0 0 20 20" fill="currentColor">
                  <path fill-rule="evenodd" d="M11.49 3.17c-.38-1.56-2.6-1.56-2.98 0a1.532 1.532 0 01-2.286.948c-1.372-.836-2.942.734-2.106 2.106.54.886.061 2.042-.947 2.287-1.561.379-1.561 2.6 0 2.978a1.532 1.532 0 01.947 2.287c-.836 1.372.734 2.942 2.106 2.106a1.532 1.532 0 012.287.947c.379 1.561 2.6 1.561 2.978 0a1.533 1.533 0 012.287-.947c1.372.836 2.942-.734 2.106-2.106a1.533 1.533 0 01.947-2.287c1.561-.379 1.561-2.6 0-2.978a1.532 1.532 0 01-.947-2.287c.836-1.372-.734-2.942-2.106-2.106a1.532 1.532 0 01-2.287-.947zM10 13a3 3 0 100-6 3 3 0 000 6z" clip-rule="evenodd" />
                </svg>
              </div>
              <h3 class="text-lg font-haas_medium_65 text-[#141414] mb-1">No custom rules</h3>
              <p class="text-sm text-gray-500 font-haas_roman_55">Create rules to trigger notifications on specific events.</p>
            </div>
          <% else %>
            <div class="overflow-x-auto">
              <table class="min-w-full">
                <thead class="bg-[#F5F6FB]">
                  <tr>
                    <th class="px-6 py-3.5 text-left text-xs font-haas_medium_65 text-gray-500 uppercase tracking-wider">#</th>
                    <th class="px-6 py-3.5 text-left text-xs font-haas_medium_65 text-gray-500 uppercase tracking-wider">Event Type</th>
                    <th class="px-6 py-3.5 text-left text-xs font-haas_medium_65 text-gray-500 uppercase tracking-wider">Title</th>
                    <th class="px-6 py-3.5 text-left text-xs font-haas_medium_65 text-gray-500 uppercase tracking-wider">Channel</th>
                    <th class="px-6 py-3.5 text-left text-xs font-haas_medium_65 text-gray-500 uppercase tracking-wider">Bonuses</th>
                    <th class="px-6 py-3.5 text-left text-xs font-haas_medium_65 text-gray-500 uppercase tracking-wider">Conditions</th>
                    <th class="px-6 py-3.5 text-right text-xs font-haas_medium_65 text-gray-500 uppercase tracking-wider">Actions</th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-gray-100">
                  <%= for {rule, index} <- Enum.with_index(@rules) do %>
                    <tr class={"hover:bg-[#F5F6FB]/50 transition-colors #{if @editing == index, do: "bg-blue-50/50"}"}>
                      <td class="px-6 py-4 text-sm font-haas_roman_55 text-gray-400"><%= index + 1 %></td>
                      <td class="px-6 py-4">
                        <span class="inline-flex items-center px-2.5 py-1 rounded-lg text-xs font-haas_medium_65 bg-gray-100 text-gray-700">
                          <%= rule["event_type"] %>
                        </span>
                      </td>
                      <td class="px-6 py-4">
                        <div class="font-haas_medium_65 text-sm text-[#141414]"><%= rule["title"] %></div>
                        <div class="text-xs text-gray-500 font-haas_roman_55 mt-0.5 max-w-xs truncate"><%= rule["body"] %></div>
                      </td>
                      <td class="px-6 py-4">
                        <%= channel_badge(rule["channel"]) %>
                      </td>
                      <td class="px-6 py-4">
                        <div class="flex flex-col gap-0.5 text-xs font-haas_roman_55">
                          <%= if rule["bux_bonus_formula"] && rule["bux_bonus_formula"] != "" do %>
                            <span class="text-amber-600 font-mono"><%= rule["bux_bonus_formula"] %> BUX</span>
                          <% end %>
                          <%= if rule["bux_bonus"] && rule["bux_bonus"] > 0 && (!rule["bux_bonus_formula"] || rule["bux_bonus_formula"] == "") do %>
                            <span class="text-amber-600"><%= rule["bux_bonus"] %> BUX</span>
                          <% end %>
                          <%= if rule["rogue_bonus_formula"] && rule["rogue_bonus_formula"] != "" do %>
                            <span class="text-blue-600 font-mono"><%= rule["rogue_bonus_formula"] %> ROGUE</span>
                          <% end %>
                          <%= if rule["rogue_bonus"] && rule["rogue_bonus"] > 0 && (!rule["rogue_bonus_formula"] || rule["rogue_bonus_formula"] == "") do %>
                            <span class="text-blue-600"><%= rule["rogue_bonus"] %> ROGUE</span>
                          <% end %>
                          <%= if no_bonus?(rule) do %>
                            <span class="text-gray-400">None</span>
                          <% end %>
                          <%= if rule["recurring"] == true do %>
                            <span class="text-purple-600 mt-0.5">
                              Recurring: every <%= rule["every_n_formula"] || rule["every_n"] || "?" %> (<%= rule["count_field"] || "total_bets" %>)
                            </span>
                          <% end %>
                        </div>
                      </td>
                      <td class="px-6 py-4">
                        <%= if rule["conditions"] && rule["conditions"] != %{} do %>
                          <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-mono bg-gray-50 text-gray-600 max-w-[200px] truncate">
                            <%= Jason.encode!(rule["conditions"]) %>
                          </span>
                        <% else %>
                          <span class="text-xs text-gray-400">Always</span>
                        <% end %>
                      </td>
                      <td class="px-6 py-4 text-right">
                        <div class="flex items-center justify-end gap-2">
                          <button phx-click="edit_rule" phx-value-index={index} class="text-xs text-gray-600 hover:text-gray-800 font-haas_medium_65 cursor-pointer">Edit</button>
                          <button phx-click="delete_rule" phx-value-index={index} data-confirm="Delete this rule?" class="text-xs text-red-600 hover:text-red-800 font-haas_medium_65 cursor-pointer">Delete</button>
                        </div>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          <% end %>
        </div>

        <%!-- Help text --%>
        <div class="mt-6 bg-white rounded-2xl border border-gray-100 p-5">
          <h3 class="text-sm font-haas_medium_65 text-[#141414] mb-2">How Rules Work</h3>
          <ul class="text-xs font-haas_roman_55 text-gray-500 space-y-1">
            <li>Rules trigger when a matching <strong>event_type</strong> is processed (e.g. game_played, signup, phone_verified, hub_followed)</li>
            <li><strong>Conditions</strong> filter by event metadata using exact match or operators: <code class="bg-gray-100 px-1 rounded"><%= ~s({"$gte": 10}) %></code>, <code class="bg-gray-100 px-1 rounded"><%= ~s({"$lte": 5}) %></code></li>
            <li><strong>Static bonuses</strong> award a fixed amount. <strong>Formula bonuses</strong> compute amounts from metadata (e.g. <code class="bg-gray-100 px-1 rounded">total_bets * 10</code>)</li>
            <li><strong>Formulas</strong> support: <code class="bg-gray-100 px-1 rounded">+</code> <code class="bg-gray-100 px-1 rounded">-</code> <code class="bg-gray-100 px-1 rounded">*</code> <code class="bg-gray-100 px-1 rounded">/</code> <code class="bg-gray-100 px-1 rounded">()</code> and functions <code class="bg-gray-100 px-1 rounded">random(min, max)</code>, <code class="bg-gray-100 px-1 rounded">min(a, b)</code>, <code class="bg-gray-100 px-1 rounded">max(a, b)</code></li>
            <li><strong>Available variables</strong> for game_played: <code class="bg-gray-100 px-1 rounded">total_bets</code>, <code class="bg-gray-100 px-1 rounded">bux_win_rate</code>, <code class="bg-gray-100 px-1 rounded">bux_net_pnl</code>, <code class="bg-gray-100 px-1 rounded">bux_total_wagered</code>, etc. All events get <code class="bg-gray-100 px-1 rounded">bux_balance</code> and <code class="bg-gray-100 px-1 rounded">rogue_balance</code></li>
            <li><strong>Recurring rules</strong> fire at intervals (every Nth event) instead of once. The interval can be static or formula-based</li>
            <li>Rules are also manageable via the <.link navigate={~p"/admin/ai-manager"} class="text-blue-600 hover:underline cursor-pointer">AI Manager</.link></li>
          </ul>
        </div>
      </div>
    </div>
    """
  end

  # ============ Helpers ============

  defp default_form do
    %{
      "event_type" => "",
      "title" => "",
      "body" => "",
      "channel" => "in_app",
      "notification_type" => "special_offer",
      "subject" => "",
      "action_url" => "",
      "action_label" => "",
      "bux_bonus" => "",
      "rogue_bonus" => "",
      "bux_bonus_formula" => "",
      "rogue_bonus_formula" => "",
      "recurring" => "false",
      "every_n" => "",
      "every_n_formula" => "",
      "count_field" => "total_bets",
      "conditions" => ""
    }
  end

  defp validate_form(params) do
    alias BlocksterV2.Notifications.FormulaEvaluator

    errors = %{}

    errors = if blank?(params["event_type"]), do: Map.put(errors, "event_type", "required"), else: errors
    errors = if blank?(params["title"]), do: Map.put(errors, "title", "required"), else: errors
    errors = if blank?(params["body"]), do: Map.put(errors, "body", "required"), else: errors

    # Validate formula syntax (test with dummy metadata)
    test_metadata = %{"total_bets" => 10, "bux_balance" => 1000.0, "rogue_balance" => 50000.0}

    errors =
      if not blank?(params["bux_bonus_formula"]) do
        case FormulaEvaluator.evaluate(params["bux_bonus_formula"], test_metadata) do
          {:ok, _} -> errors
          :error -> Map.put(errors, "bux_bonus_formula", "invalid formula syntax")
        end
      else
        errors
      end

    errors =
      if not blank?(params["rogue_bonus_formula"]) do
        case FormulaEvaluator.evaluate(params["rogue_bonus_formula"], test_metadata) do
          {:ok, _} -> errors
          :error -> Map.put(errors, "rogue_bonus_formula", "invalid formula syntax")
        end
      else
        errors
      end

    # Validate recurring settings
    is_recurring = params["recurring"] == "true"

    errors =
      if is_recurring do
        has_every_n = not blank?(params["every_n"])
        has_every_n_formula = not blank?(params["every_n_formula"])

        errors =
          if not has_every_n and not has_every_n_formula do
            Map.put(errors, "every_n", "recurring rules require every_n or every_n_formula")
          else
            errors
          end

        errors =
          if has_every_n do
            case Integer.parse(params["every_n"] || "") do
              {n, _} when n >= 1 -> errors
              _ -> Map.put(errors, "every_n", "must be a positive integer")
            end
          else
            errors
          end

        errors =
          if has_every_n_formula do
            case FormulaEvaluator.evaluate(params["every_n_formula"], test_metadata) do
              {:ok, _} -> errors
              :error -> Map.put(errors, "every_n_formula", "invalid formula syntax")
            end
          else
            errors
          end

        errors
      else
        errors
      end

    # Parse conditions JSON
    {conditions, errors} =
      if blank?(params["conditions"]) do
        {nil, errors}
      else
        case Jason.decode(params["conditions"]) do
          {:ok, parsed} when is_map(parsed) -> {parsed, errors}
          {:ok, _} -> {nil, Map.put(errors, "conditions", "must be a JSON object")}
          {:error, _} -> {nil, Map.put(errors, "conditions", "invalid JSON")}
        end
      end

    if map_size(errors) > 0 do
      {:error, errors}
    else
      rule =
        %{
          "action" => "notification",
          "event_type" => String.trim(params["event_type"]),
          "title" => String.trim(params["title"]),
          "body" => String.trim(params["body"]),
          "channel" => params["channel"] || "in_app",
          "notification_type" => non_blank(params["notification_type"], "special_offer"),
          "subject" => non_blank(params["subject"]),
          "action_url" => non_blank(params["action_url"]),
          "action_label" => non_blank(params["action_label"]),
          "bux_bonus" => parse_number(params["bux_bonus"]),
          "rogue_bonus" => parse_number(params["rogue_bonus"]),
          "bux_bonus_formula" => non_blank(params["bux_bonus_formula"]),
          "rogue_bonus_formula" => non_blank(params["rogue_bonus_formula"]),
          "recurring" => if(is_recurring, do: true, else: nil),
          "every_n" => if(is_recurring, do: parse_integer(params["every_n"]), else: nil),
          "every_n_formula" => if(is_recurring, do: non_blank(params["every_n_formula"]), else: nil),
          "count_field" => if(is_recurring and params["count_field"] != "total_bets", do: params["count_field"], else: nil),
          "conditions" => conditions
        }
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)
        |> Map.new()

      {:ok, rule}
    end
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(s) when is_binary(s), do: String.trim(s) == ""
  defp blank?(_), do: false

  defp non_blank(val, default \\ nil) do
    if blank?(val), do: default, else: String.trim(val)
  end

  defp parse_number(nil), do: nil
  defp parse_number(""), do: nil
  defp parse_number(s) when is_binary(s) do
    case Float.parse(s) do
      {n, _} ->
        if n == Float.floor(n), do: trunc(n), else: n
      :error -> nil
    end
  end
  defp parse_number(n) when is_number(n), do: n

  defp parse_integer(nil), do: nil
  defp parse_integer(""), do: nil
  defp parse_integer(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, _} when n >= 1 -> n
      _ -> nil
    end
  end
  defp parse_integer(n) when is_integer(n), do: n

  defp count_field_options do
    [
      {"total_bets", "total_bets (combined)"},
      {"bux_total_bets", "bux_total_bets"},
      {"rogue_total_bets", "rogue_total_bets"},
      {"net_deposits", "net_deposits (ROGUE)"},
      {"bux_total_wagered", "bux_total_wagered"},
      {"rogue_total_wagered", "rogue_total_wagered"}
    ]
  end

  defp no_bonus?(rule) do
    no_static = (!rule["bux_bonus"] || rule["bux_bonus"] == 0) && (!rule["rogue_bonus"] || rule["rogue_bonus"] == 0)
    no_formula = (!rule["bux_bonus_formula"] || rule["bux_bonus_formula"] == "") && (!rule["rogue_bonus_formula"] || rule["rogue_bonus_formula"] == "")
    no_static && no_formula
  end

  defp format_conditions(nil), do: ""
  defp format_conditions(conditions) when is_map(conditions) and map_size(conditions) == 0, do: ""
  defp format_conditions(conditions) when is_map(conditions), do: Jason.encode!(conditions, pretty: true)
  defp format_conditions(_), do: ""

  defp channel_badge("email"), do: raw(~s(<span class="px-2 py-0.5 bg-blue-50 text-blue-700 text-xs rounded-md font-haas_medium_65">Email</span>))
  defp channel_badge("telegram"), do: raw(~s(<span class="px-2 py-0.5 bg-cyan-50 text-cyan-700 text-xs rounded-md font-haas_medium_65">Telegram</span>))
  defp channel_badge("both"), do: raw(~s(<span class="px-2 py-0.5 bg-green-50 text-green-700 text-xs rounded-md font-haas_medium_65">In-App + Email</span>))
  defp channel_badge("all"), do: raw(~s(<span class="px-2 py-0.5 bg-purple-50 text-purple-700 text-xs rounded-md font-haas_medium_65">All</span>))
  defp channel_badge(_), do: raw(~s(<span class="px-2 py-0.5 bg-gray-100 text-gray-700 text-xs rounded-md font-haas_medium_65">In-App</span>))
end
