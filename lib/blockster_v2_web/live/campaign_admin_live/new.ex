defmodule BlocksterV2Web.CampaignAdminLive.New do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.{Notifications, Blog}

  @steps ["content", "audience", "channels", "schedule", "review"]

  @impl true
  def mount(_params, _session, socket) do
    hubs = Blog.list_hubs()

    {:ok,
     socket
     |> assign(:page_title, "New Campaign")
     |> assign(:step, "content")
     |> assign(:steps, @steps)
     |> assign(:hubs, hubs)
     |> assign(:form_data, %{
       "name" => "",
       "type" => "email_blast",
       "subject" => "",
       "title" => "",
       "body" => "",
       "plain_text_body" => "",
       "image_url" => "",
       "action_url" => "",
       "action_label" => "Learn More",
       "target_audience" => "all",
       "target_hub_id" => nil,
       "send_email" => true,
       "send_in_app" => true,
       "send_sms" => false,
       "scheduled_at" => nil,
       "send_now" => true,
       "balance_operator" => "above",
       "balance_threshold" => "",
       "wallet_provider" => "metamask",
       "multiplier_operator" => "above",
       "multiplier_threshold" => ""
     })
     |> assign(:estimated_recipients, 0)
     |> assign(:selected_users, [])
     |> assign(:user_search_results, [])
     |> assign(:user_search_query, "")
     |> update_recipient_count()}
  end

  @impl true
  def handle_event("noop", _params, socket), do: {:noreply, socket}

  def handle_event("set_step", %{"step" => step}, socket) when step in @steps do
    {:noreply, assign(socket, :step, step)}
  end

  def handle_event("next_step", _params, socket) do
    current_idx = Enum.find_index(@steps, &(&1 == socket.assigns.step))
    next_step = Enum.at(@steps, current_idx + 1, socket.assigns.step)
    {:noreply, assign(socket, :step, next_step)}
  end

  def handle_event("prev_step", _params, socket) do
    current_idx = Enum.find_index(@steps, &(&1 == socket.assigns.step))
    prev_step = Enum.at(@steps, max(current_idx - 1, 0), socket.assigns.step)
    {:noreply, assign(socket, :step, prev_step)}
  end

  def handle_event("update_form", params, socket) do
    form_data = Map.merge(socket.assigns.form_data, sanitize_params(params))
    socket = assign(socket, :form_data, form_data)

    # Recalculate recipient count if audience-related fields changed
    audience_fields = ~w(target_audience target_hub_id balance_operator balance_threshold wallet_provider multiplier_operator multiplier_threshold)
    socket = if Enum.any?(audience_fields, &Map.has_key?(params, &1)) do
      update_recipient_count(socket)
    else
      socket
    end

    {:noreply, socket}
  end

  def handle_event("search_users", %{"query" => query}, socket) do
    results = if String.length(query) >= 2 do
      Notifications.search_users(query, 10)
      |> Enum.reject(fn u -> u.id in Enum.map(socket.assigns.selected_users, & &1.id) end)
    else
      []
    end

    {:noreply, assign(socket, user_search_results: results, user_search_query: query)}
  end

  def handle_event("add_user", %{"id" => id_str}, socket) do
    id = String.to_integer(id_str)
    user = Enum.find(socket.assigns.user_search_results, &(&1.id == id))

    if user do
      selected = socket.assigns.selected_users ++ [user]
      {:noreply,
       socket
       |> assign(:selected_users, selected)
       |> assign(:user_search_results, [])
       |> assign(:user_search_query, "")
       |> update_recipient_count()}
    else
      {:noreply, socket}
    end
  end

  def handle_event("remove_user", %{"id" => id_str}, socket) do
    id = String.to_integer(id_str)
    selected = Enum.reject(socket.assigns.selected_users, &(&1.id == id))

    {:noreply,
     socket
     |> assign(:selected_users, selected)
     |> update_recipient_count()}
  end

  def handle_event("create_campaign", _params, socket) do
    fd = socket.assigns.form_data

    target_criteria = build_target_criteria(fd, socket.assigns.selected_users)

    attrs = %{
      name: fd["name"],
      type: fd["type"],
      subject: fd["subject"],
      title: fd["title"],
      body: fd["body"],
      plain_text_body: fd["plain_text_body"],
      image_url: if(fd["image_url"] != "", do: fd["image_url"]),
      action_url: if(fd["action_url"] != "", do: fd["action_url"]),
      action_label: fd["action_label"],
      target_audience: fd["target_audience"],
      target_hub_id: if(fd["target_hub_id"] && fd["target_hub_id"] != "", do: String.to_integer(fd["target_hub_id"])),
      target_criteria: target_criteria,
      send_email: fd["send_email"],
      send_in_app: fd["send_in_app"],
      send_sms: fd["send_sms"],
      created_by_id: socket.assigns.current_user.id,
      status: if(fd["send_now"], do: "draft", else: "scheduled"),
      scheduled_at: parse_scheduled_at(fd["scheduled_at"])
    }

    case Notifications.create_campaign(attrs) do
      {:ok, campaign} ->
        if fd["send_now"] do
          BlocksterV2.Workers.PromoEmailWorker.enqueue_campaign(campaign.id)
        end

        {:noreply,
         socket
         |> put_flash(:info, if(fd["send_now"], do: "Campaign sent!", else: "Campaign scheduled!"))
         |> push_navigate(to: ~p"/admin/notifications/campaigns")}

      {:error, changeset} ->
        errors = format_errors(changeset)
        {:noreply, put_flash(socket, :error, "Failed: #{errors}")}
    end
  end

  def handle_event("send_test", _params, socket) do
    fd = socket.assigns.form_data
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
            title: fd["title"] || fd["subject"] || "Test",
            body: fd["body"] || fd["plain_text_body"] || "",
            image_url: if(fd["image_url"] != "", do: fd["image_url"]),
            action_url: if(fd["action_url"] != "", do: fd["action_url"]),
            action_label: fd["action_label"]
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
      <div class="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 pt-24 pb-12">
        <%!-- Header --%>
        <div class="flex items-center gap-4 mb-8">
          <.link navigate={~p"/admin/notifications/campaigns"} class="w-10 h-10 bg-white rounded-xl flex items-center justify-center shadow-sm border border-gray-100 hover:bg-gray-50 cursor-pointer">
            <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 text-gray-600" viewBox="0 0 20 20" fill="currentColor"><path fill-rule="evenodd" d="M9.707 16.707a1 1 0 01-1.414 0l-6-6a1 1 0 010-1.414l6-6a1 1 0 011.414 1.414L5.414 9H17a1 1 0 110 2H5.414l4.293 4.293a1 1 0 010 1.414z" clip-rule="evenodd" /></svg>
          </.link>
          <div>
            <h1 class="text-2xl font-haas_medium_65 text-[#141414]">New Campaign</h1>
            <p class="text-sm text-gray-500 font-haas_roman_55">Step <%= step_index(@step) + 1 %> of <%= length(@steps) %></p>
          </div>
        </div>

        <%!-- Step Indicator --%>
        <div class="flex items-center gap-2 mb-8">
          <%= for {step, idx} <- Enum.with_index(@steps) do %>
            <button
              phx-click="set_step"
              phx-value-step={step}
              class={"flex items-center gap-2 px-4 py-2 rounded-xl text-sm font-haas_medium_65 cursor-pointer transition-all #{cond do
                step == @step -> "bg-gray-900 text-white"
                idx < step_index(@step) -> "bg-[#141414] text-white"
                true -> "bg-white text-gray-400 border border-gray-200"
              end}"}
            >
              <span class="w-5 h-5 rounded-full flex items-center justify-center text-xs bg-black/10"><%= idx + 1 %></span>
              <span class="hidden sm:inline"><%= String.capitalize(step) %></span>
            </button>
            <%= if idx < length(@steps) - 1 do %>
              <div class={"w-8 h-0.5 #{if idx < step_index(@step), do: "bg-[#141414]", else: "bg-gray-200"}"}></div>
            <% end %>
          <% end %>
        </div>

        <%!-- Step Content --%>
        <div class="bg-white rounded-2xl shadow-sm border border-gray-100 p-8">
          <form phx-change="update_form" phx-submit="noop">
            <%= case @step do %>
              <% "content" -> %>
                <.step_content form_data={@form_data} />
              <% "audience" -> %>
                <.step_audience form_data={@form_data} hubs={@hubs} estimated_recipients={@estimated_recipients} selected_users={@selected_users} user_search_results={@user_search_results} user_search_query={@user_search_query} />
              <% "channels" -> %>
                <.step_channels form_data={@form_data} />
              <% "schedule" -> %>
                <.step_schedule form_data={@form_data} />
              <% "review" -> %>
                <.step_review form_data={@form_data} estimated_recipients={@estimated_recipients} />
            <% end %>
          </form>

          <%!-- Navigation --%>
          <div class="flex justify-between items-center mt-8 pt-6 border-t border-gray-100">
            <button
              :if={@step != "content"}
              phx-click="prev_step"
              class="px-5 py-2.5 bg-gray-100 rounded-xl text-sm font-haas_medium_65 text-gray-600 hover:bg-gray-200 cursor-pointer"
            >
              Back
            </button>
            <div :if={@step == "content"} />

            <div class="flex gap-3">
              <%= if @step == "review" do %>
                <button phx-click="send_test" class="px-5 py-2.5 bg-white border border-gray-200 rounded-xl text-sm font-haas_medium_65 text-gray-600 hover:bg-gray-50 cursor-pointer">
                  Send Test
                </button>
                <button phx-click="create_campaign" class="px-5 py-2.5 bg-gray-900 rounded-xl text-sm font-haas_medium_65 text-white hover:bg-gray-800 cursor-pointer">
                  <%= if @form_data["send_now"], do: "Send Campaign", else: "Schedule Campaign" %>
                </button>
              <% else %>
                <button phx-click="next_step" class="px-5 py-2.5 bg-gray-900 rounded-xl text-sm font-haas_medium_65 text-white hover:bg-gray-800 cursor-pointer">
                  Next Step
                </button>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ============ Step Components ============

  defp step_content(assigns) do
    ~H"""
    <div class="space-y-5">
      <h2 class="text-lg font-haas_medium_65 text-[#141414] mb-4">Campaign Content</h2>
      <div>
        <label class="block text-sm font-haas_medium_65 text-gray-700 mb-1">Campaign Name</label>
        <input type="text" name="name" value={@form_data["name"]} class="w-full px-4 py-2.5 bg-[#F5F6FB] border-0 rounded-xl text-sm font-haas_roman_55 focus:ring-2 focus:ring-gray-400" placeholder="e.g. February Flash Sale" />
      </div>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div>
          <label class="block text-sm font-haas_medium_65 text-gray-700 mb-1">Email Subject</label>
          <input type="text" name="subject" value={@form_data["subject"]} class="w-full px-4 py-2.5 bg-[#F5F6FB] border-0 rounded-xl text-sm font-haas_roman_55 focus:ring-2 focus:ring-gray-400" placeholder="Subject line..." />
        </div>
        <div>
          <label class="block text-sm font-haas_medium_65 text-gray-700 mb-1">Notification Title</label>
          <input type="text" name="title" value={@form_data["title"]} class="w-full px-4 py-2.5 bg-[#F5F6FB] border-0 rounded-xl text-sm font-haas_roman_55 focus:ring-2 focus:ring-gray-400" placeholder="In-app title..." />
        </div>
      </div>
      <div>
        <label class="block text-sm font-haas_medium_65 text-gray-700 mb-1">Body</label>
        <textarea name="body" rows="4" class="w-full px-4 py-2.5 bg-[#F5F6FB] border-0 rounded-xl text-sm font-haas_roman_55 focus:ring-2 focus:ring-gray-400" placeholder="Campaign message..."><%= @form_data["body"] %></textarea>
      </div>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div>
          <label class="block text-sm font-haas_medium_65 text-gray-700 mb-1">Image URL</label>
          <input type="url" name="image_url" value={@form_data["image_url"]} class="w-full px-4 py-2.5 bg-[#F5F6FB] border-0 rounded-xl text-sm font-haas_roman_55 focus:ring-2 focus:ring-gray-400" placeholder="https://..." />
        </div>
        <div>
          <label class="block text-sm font-haas_medium_65 text-gray-700 mb-1">Action URL</label>
          <input type="url" name="action_url" value={@form_data["action_url"]} class="w-full px-4 py-2.5 bg-[#F5F6FB] border-0 rounded-xl text-sm font-haas_roman_55 focus:ring-2 focus:ring-gray-400" placeholder="https://..." />
        </div>
      </div>
      <div>
        <label class="block text-sm font-haas_medium_65 text-gray-700 mb-1">Button Label</label>
        <input type="text" name="action_label" value={@form_data["action_label"]} class="w-full px-4 py-2.5 bg-[#F5F6FB] border-0 rounded-xl text-sm font-haas_roman_55 focus:ring-2 focus:ring-gray-400" placeholder="Learn More" />
      </div>
    </div>
    """
  end

  defp step_audience(assigns) do
    ~H"""
    <div class="space-y-5">
      <h2 class="text-lg font-haas_medium_65 text-[#141414] mb-4">Target Audience</h2>
      <div class="grid grid-cols-2 md:grid-cols-3 gap-3">
        <% audiences = [
          {"all", "All Users", "Everyone with an email"},
          {"hub_followers", "Hub Followers", "Followers of a specific hub"},
          {"active_users", "Active Users", "Active in last 7 days"},
          {"dormant_users", "Dormant Users", "Inactive 30+ days"},
          {"phone_verified", "Phone Verified", "Verified phone number"},
          {"not_phone_verified", "Not Phone Verified", "Haven't verified phone yet"},
          {"x_connected", "X Connected", "Connected X account"},
          {"not_x_connected", "No X Account", "Haven't connected X"},
          {"has_external_wallet", "Has Wallet", "Connected an external wallet"},
          {"no_external_wallet", "No Wallet", "No external wallet connected"},
          {"wallet_provider", "Wallet Provider", "Specific wallet type"},
          {"multiplier", "Multiplier", "Above or below a threshold"},
          {"custom", "Custom Selection", "Search & select specific users"},
          {"bux_gamers", "BUX Gamers", "Played BUX Booster with BUX"},
          {"rogue_gamers", "ROGUE Gamers", "Played BUX Booster with ROGUE"},
          {"bux_balance", "BUX Balance", "Above or below a threshold"},
          {"rogue_holders", "ROGUE Balance", "Above or below a threshold"}
        ] %>
        <%= for {value, label, desc} <- audiences do %>
          <label class={"block p-4 rounded-xl border-2 cursor-pointer transition-all #{if @form_data["target_audience"] == value, do: "border-gray-900 bg-gray-50", else: "border-gray-100 hover:border-gray-200"}"}>
            <input type="radio" name="target_audience" value={value} checked={@form_data["target_audience"] == value} class="hidden" />
            <div class="font-haas_medium_65 text-sm text-[#141414]"><%= label %></div>
            <div class="text-xs text-gray-500 font-haas_roman_55 mt-0.5"><%= desc %></div>
          </label>
        <% end %>
      </div>

      <%!-- Hub Selector --%>
      <%= if @form_data["target_audience"] == "hub_followers" do %>
        <div>
          <label class="block text-sm font-haas_medium_65 text-gray-700 mb-1">Select Hub</label>
          <select name="target_hub_id" class="w-full px-4 py-2.5 bg-[#F5F6FB] border-0 rounded-xl text-sm font-haas_roman_55 focus:ring-2 focus:ring-gray-400">
            <option value="">Choose a hub...</option>
            <%= for hub <- @hubs do %>
              <option value={hub.id} selected={to_string(hub.id) == @form_data["target_hub_id"]}><%= hub.name %></option>
            <% end %>
          </select>
        </div>
      <% end %>

      <%!-- Custom User Selection --%>
      <%= if @form_data["target_audience"] == "custom" do %>
        <div class="space-y-3">
          <label class="block text-sm font-haas_medium_65 text-gray-700">Search Users</label>
          <div class="relative">
            <input
              type="text"
              phx-keyup="search_users"
              phx-debounce="300"
              name="query"
              value={@user_search_query}
              placeholder="Search by email, username, or wallet..."
              class="w-full px-4 py-2.5 bg-[#F5F6FB] border-0 rounded-xl text-sm font-haas_roman_55 focus:ring-2 focus:ring-gray-400"
              autocomplete="off"
            />
            <%= if @user_search_results != [] do %>
              <div class="absolute z-10 w-full mt-1 bg-white border border-gray-200 rounded-xl shadow-lg max-h-48 overflow-y-auto">
                <%= for user <- @user_search_results do %>
                  <button
                    type="button"
                    phx-click="add_user"
                    phx-value-id={user.id}
                    class="w-full px-4 py-2.5 text-left hover:bg-gray-50 cursor-pointer flex items-center justify-between border-b border-gray-50 last:border-0"
                  >
                    <div>
                      <div class="text-sm font-haas_medium_65 text-[#141414]"><%= user.email %></div>
                      <div class="text-xs text-gray-500 font-haas_roman_55"><%= user.username || "—" %></div>
                    </div>
                    <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4 text-gray-400" viewBox="0 0 20 20" fill="currentColor"><path fill-rule="evenodd" d="M10 3a1 1 0 011 1v5h5a1 1 0 110 2h-5v5a1 1 0 11-2 0v-5H4a1 1 0 110-2h5V4a1 1 0 011-1z" clip-rule="evenodd" /></svg>
                  </button>
                <% end %>
              </div>
            <% end %>
          </div>
          <%= if @selected_users != [] do %>
            <div class="flex flex-wrap gap-2">
              <%= for user <- @selected_users do %>
                <span class="inline-flex items-center gap-1.5 px-3 py-1.5 bg-gray-100 rounded-lg text-sm font-haas_roman_55">
                  <%= user.email %>
                  <button type="button" phx-click="remove_user" phx-value-id={user.id} class="text-gray-400 hover:text-gray-600 cursor-pointer">
                    <svg xmlns="http://www.w3.org/2000/svg" class="h-3.5 w-3.5" viewBox="0 0 20 20" fill="currentColor"><path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd" /></svg>
                  </button>
                </span>
              <% end %>
            </div>
          <% end %>
        </div>
      <% end %>

      <%!-- Balance Filter --%>
      <%= if @form_data["target_audience"] in ["bux_balance", "rogue_holders"] do %>
        <div class="flex items-end gap-3">
          <div class="flex-1">
            <label class="block text-sm font-haas_medium_65 text-gray-700 mb-1">Operator</label>
            <select name="balance_operator" class="w-full px-4 py-2.5 bg-[#F5F6FB] border-0 rounded-xl text-sm font-haas_roman_55 focus:ring-2 focus:ring-gray-400">
              <option value="above" selected={@form_data["balance_operator"] == "above"}>Above or equal to</option>
              <option value="below" selected={@form_data["balance_operator"] == "below"}>Below</option>
            </select>
          </div>
          <div class="flex-1">
            <label class="block text-sm font-haas_medium_65 text-gray-700 mb-1"><%= if @form_data["target_audience"] == "rogue_holders", do: "ROGUE Threshold", else: "BUX Threshold" %></label>
            <input type="number" name="balance_threshold" value={@form_data["balance_threshold"]} placeholder="e.g. 1000" class="w-full px-4 py-2.5 bg-[#F5F6FB] border-0 rounded-xl text-sm font-haas_roman_55 focus:ring-2 focus:ring-gray-400" />
          </div>
        </div>
      <% end %>

      <%!-- Wallet Provider Selector --%>
      <%= if @form_data["target_audience"] == "wallet_provider" do %>
        <div>
          <label class="block text-sm font-haas_medium_65 text-gray-700 mb-1">Wallet Provider</label>
          <select name="wallet_provider" class="w-full px-4 py-2.5 bg-[#F5F6FB] border-0 rounded-xl text-sm font-haas_roman_55 focus:ring-2 focus:ring-gray-400">
            <option value="metamask" selected={@form_data["wallet_provider"] == "metamask"}>MetaMask</option>
            <option value="phantom" selected={@form_data["wallet_provider"] == "phantom"}>Phantom</option>
            <option value="coinbase" selected={@form_data["wallet_provider"] == "coinbase"}>Coinbase Wallet</option>
            <option value="walletconnect" selected={@form_data["wallet_provider"] == "walletconnect"}>WalletConnect</option>
          </select>
        </div>
      <% end %>

      <%!-- Multiplier Filter --%>
      <%= if @form_data["target_audience"] == "multiplier" do %>
        <div class="flex items-end gap-3">
          <div class="flex-1">
            <label class="block text-sm font-haas_medium_65 text-gray-700 mb-1">Operator</label>
            <select name="multiplier_operator" class="w-full px-4 py-2.5 bg-[#F5F6FB] border-0 rounded-xl text-sm font-haas_roman_55 focus:ring-2 focus:ring-gray-400">
              <option value="above" selected={@form_data["multiplier_operator"] == "above"}>Above or equal to</option>
              <option value="below" selected={@form_data["multiplier_operator"] == "below"}>Below</option>
            </select>
          </div>
          <div class="flex-1">
            <label class="block text-sm font-haas_medium_65 text-gray-700 mb-1">Multiplier Threshold</label>
            <input type="number" name="multiplier_threshold" value={@form_data["multiplier_threshold"]} step="0.1" placeholder="e.g. 5.0" class="w-full px-4 py-2.5 bg-[#F5F6FB] border-0 rounded-xl text-sm font-haas_roman_55 focus:ring-2 focus:ring-gray-400" />
          </div>
        </div>
      <% end %>

      <div class="p-4 bg-[#F5F6FB] rounded-xl">
        <div class="flex items-center gap-3">
          <div class="w-10 h-10 bg-[#CAFC00] rounded-lg flex items-center justify-center">
            <span class="font-haas_medium_65 text-sm text-black"><%= @estimated_recipients %></span>
          </div>
          <div>
            <div class="text-sm font-haas_medium_65 text-[#141414]">Estimated Recipients</div>
            <div class="text-xs text-gray-500 font-haas_roman_55">Based on current targeting</div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp step_channels(assigns) do
    ~H"""
    <div class="space-y-5">
      <h2 class="text-lg font-haas_medium_65 text-[#141414] mb-4">Delivery Channels</h2>
      <div class="space-y-4">
        <label class="flex items-center justify-between p-4 bg-[#F5F6FB] rounded-xl cursor-pointer">
          <div class="flex items-center gap-3">
            <div class="w-10 h-10 bg-blue-100 rounded-lg flex items-center justify-center">
              <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 text-blue-600" viewBox="0 0 20 20" fill="currentColor"><path d="M2.003 5.884L10 9.882l7.997-3.998A2 2 0 0016 4H4a2 2 0 00-1.997 1.884z" /><path d="M18 8.118l-8 4-8-4V14a2 2 0 002 2h12a2 2 0 002-2V8.118z" /></svg>
            </div>
            <div>
              <div class="font-haas_medium_65 text-sm text-[#141414]">Email</div>
              <div class="text-xs text-gray-500 font-haas_roman_55">Send branded email to recipients</div>
            </div>
          </div>
          <input type="hidden" name="send_email" value="false" />
          <input type="checkbox" name="send_email" value="true" checked={@form_data["send_email"]} class="w-5 h-5 rounded border-gray-300 text-gray-900 focus:ring-gray-400" />
        </label>

        <label class="flex items-center justify-between p-4 bg-[#F5F6FB] rounded-xl cursor-pointer">
          <div class="flex items-center gap-3">
            <div class="w-10 h-10 bg-green-100 rounded-lg flex items-center justify-center">
              <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 text-green-600" viewBox="0 0 20 20" fill="currentColor"><path d="M10 2a6 6 0 00-6 6v3.586l-.707.707A1 1 0 004 14h12a1 1 0 00.707-1.707L16 11.586V8a6 6 0 00-6-6z" /><path d="M10 18a3 3 0 01-3-3h6a3 3 0 01-3 3z" /></svg>
            </div>
            <div>
              <div class="font-haas_medium_65 text-sm text-[#141414]">In-App</div>
              <div class="text-xs text-gray-500 font-haas_roman_55">Bell notification + toast popup</div>
            </div>
          </div>
          <input type="hidden" name="send_in_app" value="false" />
          <input type="checkbox" name="send_in_app" value="true" checked={@form_data["send_in_app"]} class="w-5 h-5 rounded border-gray-300 text-gray-900 focus:ring-gray-400" />
        </label>

        <label class="flex items-center justify-between p-4 bg-[#F5F6FB] rounded-xl cursor-pointer">
          <div class="flex items-center gap-3">
            <div class="w-10 h-10 bg-purple-100 rounded-lg flex items-center justify-center">
              <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 text-purple-600" viewBox="0 0 20 20" fill="currentColor"><path d="M2 3a1 1 0 011-1h2.153a1 1 0 01.986.836l.74 4.435a1 1 0 01-.54 1.06l-1.548.773a11.037 11.037 0 006.105 6.105l.774-1.548a1 1 0 011.059-.54l4.435.74a1 1 0 01.836.986V17a1 1 0 01-1 1h-2C7.82 18 2 12.18 2 5V3z" /></svg>
            </div>
            <div>
              <div class="font-haas_medium_65 text-sm text-[#141414]">SMS</div>
              <div class="text-xs text-gray-500 font-haas_roman_55">Text message (phone verified users only)</div>
            </div>
          </div>
          <input type="hidden" name="send_sms" value="false" />
          <input type="checkbox" name="send_sms" value="true" checked={@form_data["send_sms"]} class="w-5 h-5 rounded border-gray-300 text-gray-900 focus:ring-gray-400" />
        </label>
      </div>
    </div>
    """
  end

  defp step_schedule(assigns) do
    ~H"""
    <div class="space-y-5">
      <h2 class="text-lg font-haas_medium_65 text-[#141414] mb-4">Schedule</h2>
      <div class="grid grid-cols-2 gap-4">
        <label class={"block p-4 rounded-xl border-2 cursor-pointer transition-all #{if @form_data["send_now"], do: "border-gray-900 bg-gray-50", else: "border-gray-100"}"}>
          <input type="radio" name="send_now" value="true" checked={@form_data["send_now"]} class="hidden" />
          <div class="font-haas_medium_65 text-sm text-[#141414]">Send Now</div>
          <div class="text-xs text-gray-500 font-haas_roman_55 mt-0.5">Deliver immediately to all recipients</div>
        </label>
        <label class={"block p-4 rounded-xl border-2 cursor-pointer transition-all #{if !@form_data["send_now"], do: "border-gray-900 bg-gray-50", else: "border-gray-100"}"}>
          <input type="radio" name="send_now" value="false" checked={!@form_data["send_now"]} class="hidden" />
          <div class="font-haas_medium_65 text-sm text-[#141414]">Schedule</div>
          <div class="text-xs text-gray-500 font-haas_roman_55 mt-0.5">Choose a specific date and time</div>
        </label>
      </div>

      <%= if !@form_data["send_now"] do %>
        <div>
          <label class="block text-sm font-haas_medium_65 text-gray-700 mb-1">Send Date & Time (UTC)</label>
          <input type="datetime-local" name="scheduled_at" value={@form_data["scheduled_at"]} class="w-full px-4 py-2.5 bg-[#F5F6FB] border-0 rounded-xl text-sm font-haas_roman_55 focus:ring-2 focus:ring-gray-400" />
        </div>
      <% end %>
    </div>
    """
  end

  defp step_review(assigns) do
    ~H"""
    <div class="space-y-6">
      <h2 class="text-lg font-haas_medium_65 text-[#141414] mb-4">Review Campaign</h2>

      <div class="grid grid-cols-2 gap-4">
        <div class="p-4 bg-[#F5F6FB] rounded-xl">
          <div class="text-xs text-gray-500 font-haas_roman_55 mb-1">Campaign Name</div>
          <div class="text-sm font-haas_medium_65 text-[#141414]"><%= @form_data["name"] || "Untitled" %></div>
        </div>
        <div class="p-4 bg-[#F5F6FB] rounded-xl">
          <div class="text-xs text-gray-500 font-haas_roman_55 mb-1">Recipients</div>
          <div class="text-sm font-haas_medium_65 text-[#141414]"><%= @estimated_recipients %> users (<%= @form_data["target_audience"] %>)</div>
        </div>
        <div class="p-4 bg-[#F5F6FB] rounded-xl">
          <div class="text-xs text-gray-500 font-haas_roman_55 mb-1">Channels</div>
          <div class="flex gap-2 mt-1">
            <%= if @form_data["send_email"] do %><span class="px-2 py-0.5 bg-blue-50 text-blue-700 text-xs rounded-md font-haas_medium_65">Email</span><% end %>
            <%= if @form_data["send_in_app"] do %><span class="px-2 py-0.5 bg-green-50 text-green-700 text-xs rounded-md font-haas_medium_65">In-App</span><% end %>
            <%= if @form_data["send_sms"] do %><span class="px-2 py-0.5 bg-purple-50 text-purple-700 text-xs rounded-md font-haas_medium_65">SMS</span><% end %>
          </div>
        </div>
        <div class="p-4 bg-[#F5F6FB] rounded-xl">
          <div class="text-xs text-gray-500 font-haas_roman_55 mb-1">Delivery</div>
          <div class="text-sm font-haas_medium_65 text-[#141414]"><%= if @form_data["send_now"], do: "Send Now", else: "Scheduled: #{@form_data["scheduled_at"]}" %></div>
        </div>
      </div>

      <div class="p-4 bg-[#F5F6FB] rounded-xl">
        <div class="text-xs text-gray-500 font-haas_roman_55 mb-1">Subject</div>
        <div class="text-sm font-haas_medium_65 text-[#141414]"><%= @form_data["subject"] || "—" %></div>
        <div class="text-xs text-gray-500 font-haas_roman_55 mb-1 mt-3">Title</div>
        <div class="text-sm font-haas_medium_65 text-[#141414]"><%= @form_data["title"] || "—" %></div>
        <div class="text-xs text-gray-500 font-haas_roman_55 mb-1 mt-3">Body</div>
        <div class="text-sm font-haas_roman_55 text-gray-700"><%= @form_data["body"] || "—" %></div>
      </div>
    </div>
    """
  end

  # ============ Helpers ============

  defp step_index(step), do: Enum.find_index(@steps, &(&1 == step)) || 0

  defp update_recipient_count(socket) do
    fd = socket.assigns.form_data

    # Build a temp campaign struct for counting
    count =
      try do
        target_criteria = build_target_criteria(fd, socket.assigns.selected_users)

        campaign = %Notifications.Campaign{
          target_audience: fd["target_audience"] || "all",
          target_hub_id: if(fd["target_hub_id"] && fd["target_hub_id"] != "", do: String.to_integer(fd["target_hub_id"])),
          target_criteria: target_criteria
        }
        Notifications.campaign_recipient_count(campaign)
      rescue
        _ -> 0
      end

    assign(socket, :estimated_recipients, count)
  end

  defp build_target_criteria(fd, selected_users) do
    case fd["target_audience"] do
      "custom" ->
        %{"user_ids" => Enum.map(selected_users, & &1.id)}

      audience when audience in ["bux_balance", "rogue_holders"] ->
        %{
          "operator" => fd["balance_operator"] || "above",
          "threshold" => fd["balance_threshold"] || "0"
        }

      "wallet_provider" ->
        %{"provider" => fd["wallet_provider"] || "metamask"}

      "multiplier" ->
        %{
          "operator" => fd["multiplier_operator"] || "above",
          "threshold" => fd["multiplier_threshold"] || "0"
        }

      _ ->
        %{}
    end
  end

  defp sanitize_params(params) do
    params
    |> Map.delete("_target")
    |> Map.delete("_csrf_token")
    |> Enum.map(fn
      {k, "true"} -> {k, true}
      {k, "false"} -> {k, false}
      pair -> pair
    end)
    |> Map.new()
  end

  defp parse_scheduled_at(nil), do: nil
  defp parse_scheduled_at(""), do: nil
  defp parse_scheduled_at(dt_string) do
    case NaiveDateTime.from_iso8601(dt_string <> ":00") do
      {:ok, naive} -> DateTime.from_naive!(naive, "Etc/UTC") |> DateTime.truncate(:second)
      _ -> nil
    end
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map(fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)
    |> Enum.join("; ")
  end
end
