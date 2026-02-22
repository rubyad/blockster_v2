defmodule BlocksterV2Web.AIManagerLive.Index do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.Notifications.{AIManager, SystemConfig}

  @starter_prompts [
    "Show me the current system configuration",
    "How are notifications performing this week?",
    "Increase referral rewards to 750 BUX",
    "What are the referral stats?",
    "Create a re-engagement campaign for dormant users",
    "Disable the cart abandonment trigger"
  ]

  @impl true
  def mount(_params, _session, socket) do
    config = load_config()
    recent_logs = load_recent_logs()

    {:ok,
     socket
     |> assign(:page_title, "AI Manager")
     |> assign(:chat_messages, [])
     |> assign(:chat_input, "")
     |> assign(:chat_loading, false)
     |> assign(:system_config, config)
     |> assign(:recent_logs, recent_logs)
     |> assign(:starter_prompts, @starter_prompts)
     |> assign(:config_expanded, true)}
  end

  @impl true
  def handle_event("send_message", %{"message" => message}, socket) when message != "" do
    user = socket.assigns.current_user
    admin_id = if user, do: user.id

    messages =
      socket.assigns.chat_messages ++
        [%{role: :user, content: message, timestamp: DateTime.utc_now()}]

    history =
      Enum.map(socket.assigns.chat_messages, fn msg ->
        %{role: msg.role, content: msg.content}
      end)

    {:noreply,
     socket
     |> assign(:chat_messages, messages)
     |> assign(:chat_input, "")
     |> assign(:chat_loading, true)
     |> start_async(:ai_response, fn ->
       AIManager.process_message(message, history, admin_id)
     end)}
  end

  def handle_event("send_message", _params, socket), do: {:noreply, socket}

  def handle_event("use_prompt", %{"prompt" => prompt}, socket) do
    handle_event("send_message", %{"message" => prompt}, socket)
  end

  def handle_event("toggle_config", _params, socket) do
    {:noreply, assign(socket, :config_expanded, !socket.assigns.config_expanded)}
  end

  def handle_event("clear_chat", _params, socket) do
    {:noreply, assign(socket, :chat_messages, [])}
  end

  @impl true
  def handle_async(:ai_response, {:ok, {:ok, response_text, tool_results}}, socket) do
    messages =
      socket.assigns.chat_messages ++
        [%{role: :assistant, content: response_text, tool_results: tool_results, timestamp: DateTime.utc_now()}]

    config = load_config()
    recent_logs = load_recent_logs()

    {:noreply,
     socket
     |> assign(:chat_messages, messages)
     |> assign(:chat_loading, false)
     |> assign(:system_config, config)
     |> assign(:recent_logs, recent_logs)}
  end

  def handle_async(:ai_response, {:ok, {:error, reason}}, socket) do
    messages =
      socket.assigns.chat_messages ++
        [%{role: :error, content: "Error: #{reason}", timestamp: DateTime.utc_now()}]

    {:noreply,
     socket
     |> assign(:chat_messages, messages)
     |> assign(:chat_loading, false)}
  end

  def handle_async(:ai_response, {:exit, reason}, socket) do
    messages =
      socket.assigns.chat_messages ++
        [%{role: :error, content: "Request failed: #{inspect(reason)}", timestamp: DateTime.utc_now()}]

    {:noreply,
     socket
     |> assign(:chat_messages, messages)
     |> assign(:chat_loading, false)}
  end

  # ============ Data Loading ============

  defp load_config do
    try do
      SystemConfig.get_all()
    rescue
      _ -> %{}
    end
  end

  defp load_recent_logs do
    import Ecto.Query

    try do
      from(l in "ai_manager_logs",
        order_by: [desc: l.inserted_at],
        limit: 5,
        select: %{
          review_type: l.review_type,
          output_summary: l.output_summary,
          inserted_at: l.inserted_at
        }
      )
      |> BlocksterV2.Repo.all()
    rescue
      _ -> []
    end
  end

  # ============ Template ============

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-[#F5F6FB]">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 pt-24 pb-12">
        <%!-- Header --%>
        <div class="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 mb-6">
          <div class="flex items-center gap-3">
            <div class="w-10 h-10 bg-[#CAFC00] rounded-xl flex items-center justify-center">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-5 h-5 text-black">
                <path d="M16.5 7.5h-9v9h9v-9Z" />
                <path fill-rule="evenodd" d="M8.25 2.25A.75.75 0 0 1 9 3v.75h2.25V3a.75.75 0 0 1 1.5 0v.75H15V3a.75.75 0 0 1 1.5 0v.75h.75a3 3 0 0 1 3 3v.75H21A.75.75 0 0 1 21 9h-.75v2.25H21a.75.75 0 0 1 0 1.5h-.75V15H21a.75.75 0 0 1 0 1.5h-.75v.75a3 3 0 0 1-3 3h-.75V21a.75.75 0 0 1-1.5 0v-.75h-2.25V21a.75.75 0 0 1-1.5 0v-.75H9V21a.75.75 0 0 1-1.5 0v-.75h-.75a3 3 0 0 1-3-3v-.75H3A.75.75 0 0 1 3 15h.75v-2.25H3a.75.75 0 0 1 0-1.5h.75V9H3a.75.75 0 0 1 0-1.5h.75v-.75a3 3 0 0 1 3-3h.75V3a.75.75 0 0 1 .75-.75ZM6 6.75A.75.75 0 0 1 6.75 6h10.5a.75.75 0 0 1 .75.75v10.5a.75.75 0 0 1-.75.75H6.75a.75.75 0 0 1-.75-.75V6.75Z" clip-rule="evenodd" />
              </svg>
            </div>
            <div>
              <h1 class="text-2xl font-haas_medium_65 text-[#141414]">AI Manager</h1>
              <p class="text-sm text-gray-500 font-haas_roman_55">Opus 4.6-powered notification system controller</p>
            </div>
          </div>
          <div class="flex items-center gap-2">
            <%= if @chat_messages != [] do %>
              <button
                phx-click="clear_chat"
                class="px-4 py-2 rounded-xl text-sm font-haas_medium_65 bg-white text-gray-600 hover:bg-gray-50 border border-gray-200 cursor-pointer transition-colors"
              >
                Clear Chat
              </button>
            <% end %>
            <.link
              navigate={~p"/admin/notifications/analytics"}
              class="px-4 py-2 rounded-xl text-sm font-haas_medium_65 bg-white text-gray-600 hover:bg-gray-50 border border-gray-200 cursor-pointer transition-colors"
            >
              Analytics
            </.link>
          </div>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
          <%!-- Chat Panel (2/3) --%>
          <div class="lg:col-span-2">
            <div class="bg-white rounded-2xl shadow-sm border border-gray-100 flex flex-col" style="min-height: 600px;">
              <%!-- Chat Messages --%>
              <div id="chat-messages" phx-hook="ScrollToBottom" class="flex-1 overflow-y-auto p-6 space-y-4">
                <%= if @chat_messages == [] do %>
                  <%!-- Empty State with Starter Prompts --%>
                  <div class="flex flex-col items-center justify-center py-12 text-center">
                    <div class="w-16 h-16 bg-[#CAFC00]/15 rounded-2xl flex items-center justify-center mb-4">
                      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-8 h-8 text-[#141414]/30">
                        <path d="M16.5 7.5h-9v9h9v-9Z" />
                        <path fill-rule="evenodd" d="M8.25 2.25A.75.75 0 0 1 9 3v.75h2.25V3a.75.75 0 0 1 1.5 0v.75H15V3a.75.75 0 0 1 1.5 0v.75h.75a3 3 0 0 1 3 3v.75H21A.75.75 0 0 1 21 9h-.75v2.25H21a.75.75 0 0 1 0 1.5h-.75V15H21a.75.75 0 0 1 0 1.5h-.75v.75a3 3 0 0 1-3 3h-.75V21a.75.75 0 0 1-1.5 0v-.75h-2.25V21a.75.75 0 0 1-1.5 0v-.75H9V21a.75.75 0 0 1-1.5 0v-.75h-.75a3 3 0 0 1-3-3v-.75H3A.75.75 0 0 1 3 15h.75v-2.25H3a.75.75 0 0 1 0-1.5h.75V9H3a.75.75 0 0 1 0-1.5h.75v-.75a3 3 0 0 1 3-3h.75V3a.75.75 0 0 1 .75-.75ZM6 6.75A.75.75 0 0 1 6.75 6h10.5a.75.75 0 0 1 .75.75v10.5a.75.75 0 0 1-.75.75H6.75a.75.75 0 0 1-.75-.75V6.75Z" clip-rule="evenodd" />
                      </svg>
                    </div>
                    <p class="text-lg font-haas_medium_65 text-[#141414] mb-1">AI Manager</p>
                    <p class="text-sm text-gray-400 font-haas_roman_55 max-w-sm mb-6">
                      Ask me about notification performance, adjust referral rewards, create campaigns, or manage triggers.
                    </p>
                    <div class="grid grid-cols-1 sm:grid-cols-2 gap-2 w-full max-w-lg">
                      <%= for prompt <- @starter_prompts do %>
                        <button
                          phx-click="use_prompt"
                          phx-value-prompt={prompt}
                          class="px-4 py-3 text-left text-sm font-haas_roman_55 text-gray-600 bg-[#F5F6FB] hover:bg-gray-100 rounded-xl transition-colors cursor-pointer"
                        >
                          <%= prompt %>
                        </button>
                      <% end %>
                    </div>
                  </div>
                <% else %>
                  <%= for msg <- @chat_messages do %>
                    <.chat_message msg={msg} />
                  <% end %>

                  <%!-- Loading indicator --%>
                  <%= if @chat_loading do %>
                    <div class="flex items-start gap-3">
                      <div class="w-8 h-8 bg-[#CAFC00] rounded-lg flex items-center justify-center flex-shrink-0">
                        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-4 h-4 text-black">
                          <path d="M16.5 7.5h-9v9h9v-9Z" />
                        </svg>
                      </div>
                      <div class="bg-[#F5F6FB] rounded-xl px-4 py-3">
                        <div class="flex items-center gap-1.5">
                          <div class="w-2 h-2 bg-gray-400 rounded-full animate-bounce" style="animation-delay: 0ms"></div>
                          <div class="w-2 h-2 bg-gray-400 rounded-full animate-bounce" style="animation-delay: 150ms"></div>
                          <div class="w-2 h-2 bg-gray-400 rounded-full animate-bounce" style="animation-delay: 300ms"></div>
                        </div>
                      </div>
                    </div>
                  <% end %>
                <% end %>
              </div>

              <%!-- Input --%>
              <div class="border-t border-gray-100 p-4">
                <form phx-submit="send_message" class="flex items-center gap-3">
                  <input
                    type="text"
                    name="message"
                    value={@chat_input}
                    placeholder="Ask the AI Manager..."
                    autocomplete="off"
                    disabled={@chat_loading}
                    class="flex-1 px-4 py-3 bg-[#F5F6FB] border-0 rounded-xl text-sm font-haas_roman_55 text-[#141414] placeholder-gray-400 focus:ring-2 focus:ring-[#CAFC00]/50 focus:outline-none disabled:opacity-50"
                  />
                  <button
                    type="submit"
                    disabled={@chat_loading}
                    class="px-5 py-3 bg-[#141414] text-white rounded-xl text-sm font-haas_medium_65 hover:bg-gray-800 transition-colors cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed flex-shrink-0"
                  >
                    Send
                  </button>
                </form>
              </div>
            </div>
          </div>

          <%!-- Sidebar (1/3) --%>
          <div class="space-y-6">
            <%!-- System Config Panel --%>
            <div class="bg-white rounded-2xl shadow-sm border border-gray-100 overflow-hidden">
              <button
                phx-click="toggle_config"
                class="w-full flex items-center justify-between p-5 cursor-pointer hover:bg-gray-50/50 transition-colors"
              >
                <h3 class="text-sm font-haas_medium_65 text-[#141414] uppercase tracking-wider">System Config</h3>
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  viewBox="0 0 24 24"
                  fill="currentColor"
                  class={"w-4 h-4 text-gray-400 transition-transform #{if @config_expanded, do: "rotate-180", else: ""}"}
                >
                  <path fill-rule="evenodd" d="M12.53 16.28a.75.75 0 0 1-1.06 0l-7.5-7.5a.75.75 0 0 1 1.06-1.06L12 14.69l6.97-6.97a.75.75 0 1 1 1.06 1.06l-7.5 7.5Z" clip-rule="evenodd" />
                </svg>
              </button>
              <%= if @config_expanded do %>
                <div class="px-5 pb-5 space-y-4">
                  <%!-- Referral Rewards --%>
                  <div>
                    <p class="text-xs font-haas_medium_65 text-gray-400 uppercase tracking-wider mb-2">Referral Rewards</p>
                    <div class="space-y-1.5">
                      <.config_row label="Referrer signup" value={"#{@system_config["referrer_signup_bux"] || 500} BUX"} />
                      <.config_row label="Referee signup" value={"#{@system_config["referee_signup_bux"] || 250} BUX"} />
                      <.config_row label="Phone verify" value={"#{@system_config["phone_verify_bux"] || 100} BUX"} />
                    </div>
                  </div>

                  <%!-- Trigger States --%>
                  <div>
                    <p class="text-xs font-haas_medium_65 text-gray-400 uppercase tracking-wider mb-2">Triggers</p>
                    <div class="space-y-1.5">
                      <.trigger_row label="BUX milestone" enabled={@system_config["trigger_bux_milestone_enabled"] != false} />
                      <.trigger_row label="Reading streak" enabled={@system_config["trigger_reading_streak_enabled"] != false} />
                      <.trigger_row label="Hub recommendation" enabled={@system_config["trigger_hub_recommendation_enabled"] != false} />
                      <.trigger_row label="Dormancy" enabled={@system_config["trigger_dormancy_enabled"] != false} />
                      <.trigger_row label="Referral opp" enabled={@system_config["trigger_referral_opportunity_enabled"] != false} />
                    </div>
                  </div>

                  <%!-- Rate Limits --%>
                  <div>
                    <p class="text-xs font-haas_medium_65 text-gray-400 uppercase tracking-wider mb-2">Rate Limits</p>
                    <div class="space-y-1.5">
                      <.config_row label="Max emails/day" value={@system_config["default_max_emails_per_day"] || 3} />
                      <.config_row label="Global max/hour" value={@system_config["global_max_per_hour"] || 500} />
                    </div>
                  </div>
                </div>
              <% end %>
            </div>

            <%!-- Recent AI Reviews --%>
            <div class="bg-white rounded-2xl shadow-sm border border-gray-100 p-5">
              <h3 class="text-sm font-haas_medium_65 text-[#141414] uppercase tracking-wider mb-4">Recent Reviews</h3>
              <%= if @recent_logs == [] do %>
                <p class="text-sm text-gray-400 font-haas_roman_55">No autonomous reviews yet. Daily reviews run at 6 AM UTC.</p>
              <% else %>
                <div class="space-y-3">
                  <%= for log <- @recent_logs do %>
                    <div class="p-3 bg-[#F5F6FB] rounded-xl">
                      <div class="flex items-center gap-2 mb-1">
                        <span class={"text-[10px] font-haas_medium_65 uppercase px-2 py-0.5 rounded-full #{if log.review_type == "daily", do: "bg-blue-100 text-blue-700", else: "bg-purple-100 text-purple-700"}"}>
                          <%= log.review_type %>
                        </span>
                        <span class="text-[10px] text-gray-400 font-haas_roman_55">
                          <%= if log.inserted_at, do: format_log_time(log.inserted_at), else: "" %>
                        </span>
                      </div>
                      <p class="text-xs text-gray-600 font-haas_roman_55 line-clamp-3">
                        <%= String.slice(log.output_summary || "", 0..200) %>
                      </p>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ============ Components ============

  defp chat_message(%{msg: %{role: :user}} = assigns) do
    ~H"""
    <div class="flex items-start gap-3 justify-end">
      <div class="bg-[#141414] text-white rounded-xl px-4 py-3 max-w-[80%]">
        <p class="text-sm font-haas_roman_55 whitespace-pre-wrap"><%= @msg.content %></p>
      </div>
    </div>
    """
  end

  defp chat_message(%{msg: %{role: :assistant}} = assigns) do
    ~H"""
    <div class="flex items-start gap-3">
      <div class="w-8 h-8 bg-[#CAFC00] rounded-lg flex items-center justify-center flex-shrink-0">
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-4 h-4 text-black">
          <path d="M16.5 7.5h-9v9h9v-9Z" />
        </svg>
      </div>
      <div class="max-w-[85%] space-y-2">
        <%!-- Tool Results --%>
        <%= if @msg[:tool_results] && @msg.tool_results != [] do %>
          <div class="space-y-1.5">
            <%= for tr <- @msg.tool_results do %>
              <div class="flex items-center gap-2 px-3 py-1.5 bg-emerald-50 border border-emerald-100 rounded-lg">
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-3.5 h-3.5 text-emerald-600">
                  <path fill-rule="evenodd" d="M19.916 4.626a.75.75 0 0 1 .208 1.04l-9 13.5a.75.75 0 0 1-1.154.114l-6-6a.75.75 0 0 1 1.06-1.06l5.353 5.353 8.493-12.74a.75.75 0 0 1 1.04-.207Z" clip-rule="evenodd" />
                </svg>
                <span class="text-xs font-haas_medium_65 text-emerald-700"><%= format_tool_name(tr.tool) %></span>
              </div>
            <% end %>
          </div>
        <% end %>

        <%!-- Response Text --%>
        <div class="bg-[#F5F6FB] rounded-xl px-4 py-3">
          <p class="text-sm font-haas_roman_55 text-[#141414] whitespace-pre-wrap"><%= @msg.content %></p>
        </div>
      </div>
    </div>
    """
  end

  defp chat_message(%{msg: %{role: :error}} = assigns) do
    ~H"""
    <div class="flex items-start gap-3">
      <div class="w-8 h-8 bg-red-100 rounded-lg flex items-center justify-center flex-shrink-0">
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-4 h-4 text-red-600">
          <path fill-rule="evenodd" d="M9.401 3.003c1.155-2 4.043-2 5.197 0l7.355 12.748c1.154 2-.29 4.5-2.599 4.5H4.645c-2.309 0-3.752-2.5-2.598-4.5L9.4 3.003ZM12 8.25a.75.75 0 0 1 .75.75v3.75a.75.75 0 0 1-1.5 0V9a.75.75 0 0 1 .75-.75Zm0 8.25a.75.75 0 1 0 0-1.5.75.75 0 0 0 0 1.5Z" clip-rule="evenodd" />
        </svg>
      </div>
      <div class="bg-red-50 border border-red-100 rounded-xl px-4 py-3 max-w-[80%]">
        <p class="text-sm font-haas_roman_55 text-red-700"><%= @msg.content %></p>
      </div>
    </div>
    """
  end

  defp config_row(assigns) do
    ~H"""
    <div class="flex items-center justify-between">
      <span class="text-xs text-gray-500 font-haas_roman_55"><%= @label %></span>
      <span class="text-xs font-haas_medium_65 text-[#141414]"><%= @value %></span>
    </div>
    """
  end

  defp trigger_row(assigns) do
    ~H"""
    <div class="flex items-center justify-between">
      <span class="text-xs text-gray-500 font-haas_roman_55"><%= @label %></span>
      <span class={"text-[10px] font-haas_medium_65 uppercase px-2 py-0.5 rounded-full #{if @enabled, do: "bg-emerald-100 text-emerald-700", else: "bg-gray-100 text-gray-500"}"}>
        <%= if @enabled, do: "on", else: "off" %>
      </span>
    </div>
    """
  end

  # ============ Helpers ============

  defp format_tool_name(name) when is_binary(name) do
    name
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp format_tool_name(_), do: "Tool"

  defp format_log_time(%NaiveDateTime{} = dt) do
    Calendar.strftime(dt, "%b %d, %H:%M")
  end

  defp format_log_time(_), do: ""
end
