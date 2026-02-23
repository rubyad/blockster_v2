defmodule BlocksterV2Web.NotificationLive.Referrals do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.{Referrals, Notifications.SystemConfig}

  @page_size 20

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns[:current_user]

    if user do
      stats = Referrals.get_referrer_stats(user.id)
      earnings = Referrals.list_referral_earnings(user.id, limit: @page_size, offset: 0)
      config = load_referral_config()
      referral_link = build_referral_link(user)

      if connected?(socket) do
        Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "referral:#{user.id}")
      end

      {:ok,
       socket
       |> assign(:page_title, "Referral Dashboard")
       |> assign(:stats, stats)
       |> assign(:earnings, earnings)
       |> assign(:config, config)
       |> assign(:referral_link, referral_link)
       |> assign(:offset, @page_size)
       |> assign(:end_reached, length(earnings) < @page_size)}
    else
      {:ok,
       socket
       |> assign(:page_title, "Referral Dashboard")
       |> assign(:stats, %{total_referrals: 0, verified_referrals: 0, total_bux_earned: 0.0, total_rogue_earned: 0.0})
       |> assign(:earnings, [])
       |> assign(:config, %{})
       |> assign(:referral_link, nil)
       |> assign(:offset, 0)
       |> assign(:end_reached, true)}
    end
  end

  @impl true
  def handle_event("load_more_earnings", _params, socket) do
    user = socket.assigns.current_user

    if user do
      batch = Referrals.list_referral_earnings(user.id, limit: @page_size, offset: socket.assigns.offset)
      end_reached = length(batch) < @page_size

      {:reply, %{end_reached: end_reached},
       socket
       |> assign(:earnings, socket.assigns.earnings ++ batch)
       |> assign(:offset, socket.assigns.offset + @page_size)
       |> assign(:end_reached, end_reached)}
    else
      {:reply, %{end_reached: true}, socket}
    end
  end

  @impl true
  def handle_info({:referral_earning, earning_data}, socket) do
    # Real-time earning from PubSub
    stats = Referrals.get_referrer_stats(socket.assigns.current_user.id)

    new_earning = %{
      id: earning_data[:id] || Ecto.UUID.generate(),
      earning_type: earning_data.type,
      amount: earning_data.amount,
      token: earning_data.token,
      tx_hash: earning_data[:tx_hash],
      timestamp: DateTime.from_unix!(earning_data.timestamp),
      referee_wallet: earning_data.referee_wallet
    }

    {:noreply,
     socket
     |> assign(:stats, stats)
     |> assign(:earnings, [new_earning | socket.assigns.earnings])}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  # ============ Data Loading ============

  defp load_referral_config do
    try do
      config = SystemConfig.get_all()

      %{
        referrer_signup_bux: config["referrer_signup_bux"] || 500,
        referee_signup_bux: config["referee_signup_bux"] || 250,
        phone_verify_bux: config["phone_verify_bux"] || 500
      }
    rescue
      _ -> %{referrer_signup_bux: 500, referee_signup_bux: 250, phone_verify_bux: 500}
    end
  end

  defp build_referral_link(user) do
    if user.smart_wallet_address do
      "https://blockster.com?ref=#{user.smart_wallet_address}"
    else
      nil
    end
  end

  # ============ Template ============

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-[#F5F6FB]">
      <div class="max-w-3xl mx-auto px-4 pt-24 md:pt-28 pb-6 md:pb-10">
        <%!-- Header --%>
        <div class="flex items-center justify-between mb-6">
          <div class="flex items-center gap-3">
            <div class="w-10 h-10 bg-[#CAFC00] rounded-xl flex items-center justify-center">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-5 h-5 text-black">
                <path d="M15.75 6a3.75 3.75 0 1 1-7.5 0 3.75 3.75 0 0 1 7.5 0ZM4.501 20.118a7.5 7.5 0 0 1 14.998 0A17.933 17.933 0 0 1 12 21.75c-2.676 0-5.216-.584-7.499-1.632Z" />
              </svg>
            </div>
            <div>
              <h1 class="text-2xl font-haas_medium_65 text-[#141414]">Referral Dashboard</h1>
              <p class="text-sm text-gray-500 font-haas_roman_55">Track your referrals and earnings</p>
            </div>
          </div>
          <.link
            navigate={~p"/notifications"}
            class="flex items-center justify-center w-9 h-9 rounded-xl bg-white border border-gray-200 hover:border-gray-300 hover:shadow-sm transition-all cursor-pointer"
            title="Back to Notifications"
          >
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-4 h-4 text-gray-500">
              <path fill-rule="evenodd" d="M7.72 12.53a.75.75 0 0 1 0-1.06l7.5-7.5a.75.75 0 1 1 1.06 1.06L9.31 12l6.97 6.97a.75.75 0 1 1-1.06 1.06l-7.5-7.5Z" clip-rule="evenodd" />
            </svg>
          </.link>
        </div>

        <%!-- Referral Link Card --%>
        <%= if @referral_link do %>
          <div class="bg-white rounded-2xl shadow-sm border border-gray-100 p-5 sm:p-6 mb-6">
            <h3 class="text-base font-haas_medium_65 text-[#141414] mb-2">Your Referral Link</h3>
            <p class="text-xs text-gray-500 font-haas_roman_55 mb-4">
              You earn <span class="font-haas_medium_65 text-[#141414]"><%= @config.referrer_signup_bux %> BUX</span> per signup.
              Your friend gets <span class="font-haas_medium_65 text-[#141414]"><%= @config.referee_signup_bux %> BUX</span> too!
            </p>

            <div class="flex flex-col sm:flex-row gap-2 mb-4">
              <input
                type="text"
                readonly
                value={@referral_link}
                class="flex-1 px-4 py-2.5 bg-[#F5F6FB] border-0 rounded-xl text-xs font-mono text-gray-600 min-w-0"
              />
              <button
                id="copy-referral-link"
                phx-hook="CopyToClipboard"
                data-copy-text={@referral_link}
                class="cursor-pointer px-5 py-2.5 bg-[#141414] text-white rounded-xl text-sm font-haas_medium_65 hover:bg-gray-800 transition-colors flex items-center justify-center gap-2 flex-shrink-0"
              >
                <span class="copy-text">Copy Link</span>
                <svg class="copy-icon w-4 h-4 hidden text-white" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"></polyline></svg>
              </button>
            </div>

            <%!-- Share Buttons --%>
            <div class="flex items-center gap-2">
              <span class="text-xs text-gray-400 font-haas_roman_55">Share via:</span>
              <a
                href={"https://x.com/intent/tweet?text=Join+me+on+Blockster+and+earn+#{@config.referee_signup_bux}+BUX!&url=#{URI.encode(@referral_link)}"}
                target="_blank"
                rel="noopener noreferrer"
                class="flex items-center justify-center w-8 h-8 rounded-lg bg-[#F5F6FB] hover:bg-gray-200 transition-colors cursor-pointer"
                title="Share on X"
              >
                <svg class="w-3.5 h-3.5 text-gray-700" viewBox="0 0 24 24" fill="currentColor"><path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z"/></svg>
              </a>
              <a
                href={"https://wa.me/?text=Join+me+on+Blockster+and+earn+#{@config.referee_signup_bux}+BUX!+#{URI.encode(@referral_link)}"}
                target="_blank"
                rel="noopener noreferrer"
                class="flex items-center justify-center w-8 h-8 rounded-lg bg-[#F5F6FB] hover:bg-gray-200 transition-colors cursor-pointer"
                title="Share on WhatsApp"
              >
                <svg class="w-4 h-4 text-gray-700" viewBox="0 0 24 24" fill="currentColor"><path d="M17.472 14.382c-.297-.149-1.758-.867-2.03-.967-.273-.099-.471-.148-.67.15-.197.297-.767.966-.94 1.164-.173.199-.347.223-.644.075-.297-.15-1.255-.463-2.39-1.475-.883-.788-1.48-1.761-1.653-2.059-.173-.297-.018-.458.13-.606.134-.133.298-.347.446-.52.149-.174.198-.298.298-.497.099-.198.05-.371-.025-.52-.075-.149-.669-1.612-.916-2.207-.242-.579-.487-.5-.669-.51-.173-.008-.371-.01-.57-.01-.198 0-.52.074-.792.372-.272.297-1.04 1.016-1.04 2.479 0 1.462 1.065 2.875 1.213 3.074.149.198 2.096 3.2 5.077 4.487.709.306 1.262.489 1.694.625.712.227 1.36.195 1.871.118.571-.085 1.758-.719 2.006-1.413.248-.694.248-1.289.173-1.413-.074-.124-.272-.198-.57-.347m-5.421 7.403h-.004a9.87 9.87 0 01-5.031-1.378l-.361-.214-3.741.982.998-3.648-.235-.374a9.86 9.86 0 01-1.51-5.26c.001-5.45 4.436-9.884 9.888-9.884 2.64 0 5.122 1.03 6.988 2.898a9.825 9.825 0 012.893 6.994c-.003 5.45-4.437 9.884-9.885 9.884m8.413-18.297A11.815 11.815 0 0012.05 0C5.495 0 .16 5.335.157 11.892c0 2.096.547 4.142 1.588 5.945L.057 24l6.305-1.654a11.882 11.882 0 005.683 1.448h.005c6.554 0 11.89-5.335 11.893-11.893a11.821 11.821 0 00-3.48-8.413z"/></svg>
              </a>
              <a
                href={"https://t.me/share/url?url=#{URI.encode(@referral_link)}&text=Join+me+on+Blockster+and+earn+#{@config.referee_signup_bux}+BUX!"}
                target="_blank"
                rel="noopener noreferrer"
                class="flex items-center justify-center w-8 h-8 rounded-lg bg-[#F5F6FB] hover:bg-gray-200 transition-colors cursor-pointer"
                title="Share on Telegram"
              >
                <svg class="w-4 h-4 text-gray-700" viewBox="0 0 24 24" fill="currentColor"><path d="M11.944 0A12 12 0 0 0 0 12a12 12 0 0 0 12 12 12 12 0 0 0 12-12A12 12 0 0 0 12 0a12 12 0 0 0-.056 0zm4.962 7.224c.1-.002.321.023.465.14a.506.506 0 0 1 .171.325c.016.093.036.306.02.472-.18 1.898-.962 6.502-1.36 8.627-.168.9-.499 1.201-.82 1.23-.696.065-1.225-.46-1.9-.902-1.056-.693-1.653-1.124-2.678-1.8-1.185-.78-.417-1.21.258-1.91.177-.184 3.247-2.977 3.307-3.23.007-.032.014-.15-.056-.212s-.174-.041-.249-.024c-.106.024-1.793 1.14-5.061 3.345-.479.33-.913.49-1.302.48-.428-.008-1.252-.241-1.865-.44-.752-.245-1.349-.374-1.297-.789.027-.216.325-.437.893-.663 3.498-1.524 5.83-2.529 6.998-3.014 3.332-1.386 4.025-1.627 4.476-1.635z"/></svg>
              </a>
              <a
                href={"mailto:?subject=Join+Blockster&body=Join+me+on+Blockster+and+earn+#{@config.referee_signup_bux}+BUX!+#{URI.encode(@referral_link)}"}
                class="flex items-center justify-center w-8 h-8 rounded-lg bg-[#F5F6FB] hover:bg-gray-200 transition-colors cursor-pointer"
                title="Share via Email"
              >
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-4 h-4 text-gray-700">
                  <path d="M1.5 8.67v8.58a3 3 0 0 0 3 3h15a3 3 0 0 0 3-3V8.67l-8.928 5.493a3 3 0 0 1-3.144 0L1.5 8.67Z" />
                  <path d="M22.5 6.908V6.75a3 3 0 0 0-3-3h-15a3 3 0 0 0-3 3v.158l9.714 5.978a1.5 1.5 0 0 0 1.572 0L22.5 6.908Z" />
                </svg>
              </a>
            </div>

            <p class="mt-4 text-[10px] text-gray-400 font-haas_roman_55">
              Plus earn <span class="font-haas_medium_65">1%</span> of losing BUX bets and
              <span class="font-haas_medium_65">0.2%</span> of losing ROGUE bets from your referrals!
            </p>
          </div>
        <% else %>
          <div class="bg-white rounded-2xl shadow-sm border border-gray-100 p-6 mb-6 text-center">
            <p class="text-sm text-gray-500 font-haas_roman_55">
              <.link navigate={~p"/login"} class="text-[#141414] font-haas_medium_65 hover:underline cursor-pointer">Log in</.link>
              to see your referral link and earnings.
            </p>
          </div>
        <% end %>

        <%!-- Stats Cards --%>
        <div class="grid grid-cols-2 md:grid-cols-4 gap-3 mb-6">
          <div class="bg-white rounded-2xl shadow-sm border border-gray-100 p-4">
            <div class="flex items-center gap-2 mb-2">
              <div class="w-2.5 h-2.5 rounded-full bg-blue-500"></div>
              <span class="text-[10px] text-gray-500 font-haas_medium_65 uppercase tracking-wider">Referrals</span>
            </div>
            <div class="text-2xl font-haas_medium_65 text-[#141414]"><%= @stats.total_referrals %></div>
          </div>
          <div class="bg-white rounded-2xl shadow-sm border border-gray-100 p-4">
            <div class="flex items-center gap-2 mb-2">
              <div class="w-2.5 h-2.5 rounded-full bg-emerald-500"></div>
              <span class="text-[10px] text-gray-500 font-haas_medium_65 uppercase tracking-wider">Verified</span>
            </div>
            <div class="text-2xl font-haas_medium_65 text-[#141414]"><%= @stats.verified_referrals %></div>
          </div>
          <div class="bg-white rounded-2xl shadow-sm border border-gray-100 p-4">
            <div class="flex items-center gap-2 mb-2">
              <div class="w-2.5 h-2.5 rounded-full bg-amber-500"></div>
              <span class="text-[10px] text-gray-500 font-haas_medium_65 uppercase tracking-wider">BUX Earned</span>
            </div>
            <div class="text-2xl font-haas_medium_65 text-[#141414]"><%= format_number(@stats.total_bux_earned) %></div>
          </div>
          <div class="bg-white rounded-2xl shadow-sm border border-gray-100 p-4">
            <div class="flex items-center gap-2 mb-2">
              <div class="w-2.5 h-2.5 rounded-full bg-purple-500"></div>
              <span class="text-[10px] text-gray-500 font-haas_medium_65 uppercase tracking-wider">ROGUE Earned</span>
            </div>
            <div class="text-2xl font-haas_medium_65 text-[#141414]"><%= format_number(@stats.total_rogue_earned) %></div>
          </div>
        </div>

        <%!-- Reward Info --%>
        <div class="bg-white rounded-2xl shadow-sm border border-gray-100 p-5 mb-6">
          <h3 class="text-sm font-haas_medium_65 text-[#141414] mb-3">How Referral Rewards Work</h3>
          <div class="grid grid-cols-1 sm:grid-cols-3 gap-3">
            <div class="flex items-center gap-3 p-3 bg-[#F5F6FB] rounded-xl">
              <div class="w-8 h-8 bg-[#CAFC00] rounded-lg flex items-center justify-center flex-shrink-0">
                <span class="text-xs font-haas_medium_65 text-black">1</span>
              </div>
              <div>
                <p class="text-xs font-haas_medium_65 text-[#141414]">Friend signs up</p>
                <p class="text-[10px] text-gray-500">You get <%= @config.referrer_signup_bux %> BUX, they get <%= @config.referee_signup_bux %> BUX</p>
              </div>
            </div>
            <div class="flex items-center gap-3 p-3 bg-[#F5F6FB] rounded-xl">
              <div class="w-8 h-8 bg-[#CAFC00] rounded-lg flex items-center justify-center flex-shrink-0">
                <span class="text-xs font-haas_medium_65 text-black">2</span>
              </div>
              <div>
                <p class="text-xs font-haas_medium_65 text-[#141414]">Friend verifies phone</p>
                <p class="text-[10px] text-gray-500">You get <%= @config.phone_verify_bux %> BUX</p>
              </div>
            </div>
            <div class="flex items-center gap-3 p-3 bg-[#F5F6FB] rounded-xl">
              <div class="w-8 h-8 bg-[#CAFC00] rounded-lg flex items-center justify-center flex-shrink-0">
                <span class="text-xs font-haas_medium_65 text-black">3</span>
              </div>
              <div>
                <p class="text-xs font-haas_medium_65 text-[#141414]">Friend plays games</p>
                <p class="text-[10px] text-gray-500">1% BUX / 0.2% ROGUE from losing bets</p>
              </div>
            </div>
          </div>
        </div>

        <%!-- Earnings Table --%>
        <div class="bg-white rounded-2xl shadow-sm border border-gray-100 overflow-hidden">
          <div class="px-5 py-4 border-b border-gray-100 flex items-center justify-between">
            <h3 class="text-sm font-haas_medium_65 text-[#141414]">Earnings History</h3>
            <span class="text-xs text-gray-400 flex items-center gap-1.5 font-haas_roman_55">
              <span class="w-2 h-2 bg-emerald-500 rounded-full animate-pulse"></span>
              Live updates
            </span>
          </div>

          <div
            id="referral-earnings-list"
            phx-hook="InfiniteScroll"
            data-event="load_more_earnings"
            class="overflow-x-auto overflow-y-auto max-h-[500px]"
          >
            <%= if @earnings == [] do %>
              <div class="flex flex-col items-center justify-center py-16 text-center">
                <div class="w-16 h-16 bg-[#CAFC00]/15 rounded-2xl flex items-center justify-center mb-4">
                  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-8 h-8 text-[#141414]/20">
                    <path d="M15.75 6a3.75 3.75 0 1 1-7.5 0 3.75 3.75 0 0 1 7.5 0ZM4.501 20.118a7.5 7.5 0 0 1 14.998 0A17.933 17.933 0 0 1 12 21.75c-2.676 0-5.216-.584-7.499-1.632Z" />
                  </svg>
                </div>
                <p class="text-sm font-haas_medium_65 text-[#141414] mb-1">No earnings yet</p>
                <p class="text-xs text-gray-400 font-haas_roman_55 max-w-[240px]">Share your referral link to start earning BUX and ROGUE.</p>
              </div>
            <% else %>
              <table class="w-full text-sm min-w-[500px]">
                <thead class="sticky top-0 bg-[#F5F6FB] z-10">
                  <tr>
                    <th class="px-5 py-3 text-left text-[10px] uppercase tracking-wider font-haas_medium_65 text-gray-500">Type</th>
                    <th class="px-5 py-3 text-left text-[10px] uppercase tracking-wider font-haas_medium_65 text-gray-500">From</th>
                    <th class="px-5 py-3 text-right text-[10px] uppercase tracking-wider font-haas_medium_65 text-gray-500">Amount</th>
                    <th class="px-5 py-3 text-left text-[10px] uppercase tracking-wider font-haas_medium_65 text-gray-500">Time</th>
                    <th class="px-5 py-3 text-left text-[10px] uppercase tracking-wider font-haas_medium_65 text-gray-500">TX</th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-gray-50">
                  <%= for earning <- @earnings do %>
                    <tr class={"hover:bg-[#F5F6FB]/50 transition-colors #{if recent?(earning.timestamp), do: "bg-[#CAFC00]/5"}"}>
                      <td class="px-5 py-3.5">
                        <span class={"inline-flex items-center px-2 py-0.5 rounded-lg text-[10px] font-haas_medium_65 #{type_style(earning.earning_type)}"}>
                          <%= type_label(earning.earning_type) %>
                        </span>
                      </td>
                      <td class="px-5 py-3.5 text-xs font-mono text-gray-400">
                        <%= truncate_wallet(earning.referee_wallet) %>
                      </td>
                      <td class="px-5 py-3.5 text-right">
                        <span class="text-sm font-haas_medium_65 text-[#141414]"><%= format_amount(earning.amount) %></span>
                        <span class="text-[10px] text-gray-400 ml-1"><%= earning.token %></span>
                      </td>
                      <td class="px-5 py-3.5 text-xs text-gray-400 font-haas_roman_55">
                        <%= format_time(earning.timestamp) %>
                      </td>
                      <td class="px-5 py-3.5">
                        <%= if earning.tx_hash do %>
                          <a
                            href={"https://roguescan.io/tx/#{earning.tx_hash}"}
                            target="_blank"
                            rel="noopener noreferrer"
                            class="text-xs text-gray-400 hover:text-[#141414] transition-colors cursor-pointer"
                          >
                            View
                          </a>
                        <% else %>
                          <span class="text-xs text-gray-300">-</span>
                        <% end %>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>

              <%= unless @end_reached do %>
                <div class="flex justify-center py-4">
                  <div class="w-5 h-5 border-2 border-gray-200 border-t-[#CAFC00] rounded-full animate-spin"></div>
                </div>
              <% end %>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ============ Helpers ============

  defp format_number(n) when is_float(n) and n >= 10_000, do: "#{Float.round(n / 1000, 1)}k"
  defp format_number(n) when is_float(n), do: Float.round(n, 2) |> to_string()
  defp format_number(n) when is_integer(n) and n >= 10_000, do: "#{Float.round(n / 1000, 1)}k"
  defp format_number(n) when is_integer(n), do: Integer.to_string(n)
  defp format_number(n), do: to_string(n)

  defp format_amount(n) when is_float(n) and n < 0.01, do: "<0.01"
  defp format_amount(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 2)
  defp format_amount(n) when is_integer(n), do: Integer.to_string(n)
  defp format_amount(n), do: to_string(n)

  defp format_time(nil), do: ""
  defp format_time(datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      diff < 604_800 -> "#{div(diff, 86400)}d ago"
      true -> Calendar.strftime(datetime, "%b %d")
    end
  end

  defp truncate_wallet(nil), do: "-"
  defp truncate_wallet(w) when byte_size(w) > 10 do
    "#{String.slice(w, 0..5)}...#{String.slice(w, -4..-1)}"
  end
  defp truncate_wallet(w), do: w

  defp recent?(datetime) do
    DateTime.diff(DateTime.utc_now(), datetime, :second) < 60
  end

  defp type_label(:signup), do: "Signup"
  defp type_label(:phone_verified), do: "Phone Verify"
  defp type_label(:bux_bet_loss), do: "BUX Game"
  defp type_label(:rogue_bet_loss), do: "ROGUE Game"
  defp type_label(:shop_purchase), do: "Shop"
  defp type_label(type), do: to_string(type)

  defp type_style(:signup), do: "bg-blue-50 text-blue-700"
  defp type_style(:phone_verified), do: "bg-emerald-50 text-emerald-700"
  defp type_style(:bux_bet_loss), do: "bg-amber-50 text-amber-700"
  defp type_style(:rogue_bet_loss), do: "bg-purple-50 text-purple-700"
  defp type_style(:shop_purchase), do: "bg-pink-50 text-pink-700"
  defp type_style(_), do: "bg-gray-50 text-gray-700"
end
