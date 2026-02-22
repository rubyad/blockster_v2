defmodule BlocksterV2Web.BankrollLive do
  use BlocksterV2Web, :live_view
  require Logger

  alias BlocksterV2.{BuxMinter, EngagementTracker, LPBuxPriceTracker, PriceTracker}
  alias BlocksterV2.HubLogoCache

  @timeframe_configs %{
    "1h"  => %{candle_seconds: 300,   count: 12, label: "1H"},
    "24h" => %{candle_seconds: 3600,  count: 24, label: "24H"},
    "7d"  => %{candle_seconds: 14400, count: 42, label: "7D"},
    "30d" => %{candle_seconds: 86400, count: 30, label: "30D"},
    "all" => %{candle_seconds: 86400, count: 0,  label: "ALL"}
  }

  @impl true
  def mount(_params, _session, socket) do
    current_user = socket.assigns[:current_user]
    token_logos = HubLogoCache.get_all_logos()

    if connected?(socket) do
      Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "lp_bux_price")
      Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "token_prices")
      if current_user do
        Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "bux_balance:#{current_user.id}")
      end
    end

    balances = if current_user do
      EngagementTracker.get_user_token_balances(current_user.id)
    else
      %{"BUX" => 0, "ROGUE" => 0}
    end

    wallet_address = if current_user, do: current_user.smart_wallet_address, else: nil

    # Sync balances on connected mount
    if current_user && wallet_address && connected?(socket) do
      BuxMinter.sync_user_balances_async(current_user.id, wallet_address)
    end

    socket =
      socket
      |> assign(page_title: "BUX Bankroll")
      |> assign(current_user: current_user)
      |> assign(balances: balances)
      |> assign(token_logos: token_logos)
      |> assign(wallet_address: wallet_address)
      |> assign(header_token: "BUX")
      # Pool info (from BUXBankroll contract)
      |> assign(pool_total: 0)
      |> assign(pool_net: 0)
      |> assign(pool_liability: 0)
      |> assign(pool_unsettled: 0)
      |> assign(lp_supply: 0)
      |> assign(lp_price: 1.0)
      |> assign(lp_user_balance: 0)
      |> assign(pool_loading: true)
      # Chart
      |> assign(selected_timeframe: "24h")
      |> assign(candles: [])
      |> assign(chart_loading: true)
      # Price stats
      |> assign(price_change_24h: nil)
      |> assign(price_high_24h: nil)
      |> assign(price_low_24h: nil)
      |> assign(rogue_usd_price: get_rogue_price())
      # Deposit/Withdraw
      |> assign(active_tab: :deposit)
      |> assign(deposit_amount: "")
      |> assign(withdraw_amount: "")
      |> assign(action_loading: false)
      |> assign(action_error: nil)
      |> assign(action_success: nil)

    # Async fetches on connected mount
    socket = if connected?(socket) do
      socket
      |> start_async(:fetch_pool_info, fn -> BuxMinter.bux_bankroll_house_info() end)
      |> start_async(:fetch_candles, fn ->
        config = @timeframe_configs["24h"]
        LPBuxPriceTracker.get_candles(config.candle_seconds, config.count)
      end)
      |> maybe_fetch_lp_balance(current_user, wallet_address)
    else
      socket
    end

    {:ok, socket}
  end

  defp maybe_fetch_lp_balance(socket, nil, _), do: socket
  defp maybe_fetch_lp_balance(socket, _, nil), do: socket
  defp maybe_fetch_lp_balance(socket, _user, wallet_address) do
    start_async(socket, :fetch_lp_balance, fn ->
      BuxMinter.bux_bankroll_lp_balance(wallet_address)
    end)
  end

  # ============================================================
  # Render
  # ============================================================

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :timeframe_configs, @timeframe_configs)

    ~H"""
    <div
      id="bankroll-page"
      phx-hook="BankrollOnchain"
      data-wallet={@wallet_address}
      class="min-h-screen"
    >
      <div class="max-w-5xl mx-auto px-3 sm:px-4 pt-6 sm:pt-24 pb-8">
        <!-- Page Title -->
        <div class="mb-6">
          <h1 class="text-2xl sm:text-3xl font-haas_medium_65 text-[#141414]">BUX Bankroll</h1>
          <p class="text-sm text-[#515B70] mt-1">Provide liquidity to the BUX house pool. Earn when the house wins.</p>
        </div>

        <!-- Pool Stats Bar -->
        <div class="bg-white shadow-sm rounded-2xl border border-gray-200 p-4 mb-6">
          <%= if @pool_loading do %>
            <div class="flex items-center justify-center py-4">
              <div class="w-5 h-5 border-2 border-gray-300 border-t-[#CAFC00] rounded-full animate-spin"></div>
              <span class="ml-2 text-sm text-gray-500">Loading pool data...</span>
            </div>
          <% else %>
            <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-4">
              <div>
                <p class="text-[10px] sm:text-xs text-gray-500 uppercase tracking-wide">Total BUX</p>
                <p class="text-base sm:text-lg font-haas_medium_65 text-[#141414]"><%= format_balance(@pool_total) %></p>
              </div>
              <div>
                <p class="text-[10px] sm:text-xs text-gray-500 uppercase tracking-wide">Net Balance</p>
                <p class="text-base sm:text-lg font-haas_medium_65 text-[#141414]"><%= format_balance(@pool_net) %></p>
              </div>
              <div>
                <p class="text-[10px] sm:text-xs text-gray-500 uppercase tracking-wide">Outstanding Bets</p>
                <p class="text-base sm:text-lg font-haas_medium_65 text-amber-600"><%= format_balance(@pool_liability) %></p>
              </div>
              <div>
                <p class="text-[10px] sm:text-xs text-gray-500 uppercase tracking-wide">LP-BUX Supply</p>
                <p class="text-base sm:text-lg font-haas_medium_65 text-[#141414]"><%= format_balance(@lp_supply) %></p>
              </div>
              <div>
                <p class="text-[10px] sm:text-xs text-gray-500 uppercase tracking-wide">LP-BUX Price</p>
                <p class="text-base sm:text-lg font-haas_medium_65 text-[#141414] font-bold">
                  <%= format_lp_price(@lp_price) %> BUX
                  <%= if @price_change_24h do %>
                    <span class={"text-xs #{if @price_change_24h >= 0, do: "text-green-600", else: "text-red-500"}"}>
                      (<%= if @price_change_24h >= 0, do: "+" %><%= Float.round(@price_change_24h, 2) %>%)
                    </span>
                  <% end %>
                </p>
              </div>
            </div>
          <% end %>
        </div>

        <!-- Two Column Layout: Chart left, Deposit/Withdraw right -->
        <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">

          <!-- LEFT: Chart (2/3 width on desktop) -->
          <div class="lg:col-span-2">
            <div class="bg-white shadow-sm rounded-2xl border border-gray-200 overflow-hidden">
              <!-- Timeframe Tabs -->
              <div class="flex items-center gap-1 p-3 border-b border-gray-200">
                <%= for {key, config} <- Enum.sort(@timeframe_configs, fn {a, _}, {b, _} -> timeframe_order(a) <= timeframe_order(b) end) do %>
                  <button
                    type="button"
                    phx-click="select_timeframe"
                    phx-value-timeframe={key}
                    class={"px-3 py-1.5 rounded-lg text-xs font-medium cursor-pointer transition-colors #{if @selected_timeframe == key, do: "bg-black text-white", else: "bg-gray-100 text-gray-500 hover:bg-gray-200 hover:text-gray-700"}"}
                  >
                    <%= config.label %>
                  </button>
                <% end %>
                <!-- Price range info -->
                <div class="ml-auto flex items-center gap-3 text-[10px] sm:text-xs text-gray-500">
                  <%= if @price_high_24h do %>
                    <span>H: <span class="text-green-600"><%= format_lp_price(@price_high_24h) %></span></span>
                    <span>L: <span class="text-red-500"><%= format_lp_price(@price_low_24h) %></span></span>
                  <% end %>
                </div>
              </div>
              <!-- Chart Container -->
              <div
                id="lp-bux-chart"
                phx-hook="LPBuxChart"
                phx-update="ignore"
                class="w-full"
                style="height: 400px;"
              >
                <%= if @chart_loading do %>
                  <div class="flex items-center justify-center h-full">
                    <div class="w-5 h-5 border-2 border-gray-300 border-t-[#CAFC00] rounded-full animate-spin"></div>
                    <span class="ml-2 text-sm text-gray-500">Loading chart...</span>
                  </div>
                <% end %>
              </div>
            </div>
          </div>

          <!-- RIGHT: Deposit / Withdraw Panel (1/3 width on desktop) -->
          <div class="lg:col-span-1">
            <div class="bg-white shadow-sm rounded-2xl border border-gray-200">
              <%= if @current_user do %>
                <!-- Tab Switcher -->
                <div class="flex border-b border-gray-200">
                  <button
                    type="button"
                    phx-click="set_action_tab"
                    phx-value-tab="deposit"
                    class={"flex-1 py-3 text-sm font-haas_medium_65 text-center cursor-pointer transition-colors #{if @active_tab == :deposit, do: "bg-black text-white rounded-t-lg", else: "text-gray-500 hover:text-gray-700"}"}
                  >
                    Deposit
                  </button>
                  <button
                    type="button"
                    phx-click="set_action_tab"
                    phx-value-tab="withdraw"
                    class={"flex-1 py-3 text-sm font-haas_medium_65 text-center cursor-pointer transition-colors #{if @active_tab == :withdraw, do: "bg-black text-white rounded-t-lg", else: "text-gray-500 hover:text-gray-700"}"}
                  >
                    Withdraw
                  </button>
                </div>

                <div class="p-4">
                  <%= if @active_tab == :deposit do %>
                    <!-- DEPOSIT FORM -->
                    <div>
                      <div class="flex items-center justify-between mb-2">
                        <label class="text-xs text-gray-500">Deposit BUX</label>
                        <button
                          type="button"
                          phx-click="set_max_deposit"
                          class="text-[10px] text-gray-500 hover:text-[#141414] cursor-pointer"
                        >
                          Balance: <span class="text-gray-700"><%= format_balance(Map.get(@balances, "BUX", 0)) %></span>
                        </button>
                      </div>
                      <div class="relative">
                        <input
                          type="number"
                          value={@deposit_amount}
                          phx-keyup="update_deposit_amount"
                          phx-debounce="100"
                          min="1"
                          placeholder="0"
                          class="w-full bg-white border border-gray-300 rounded-lg px-3 py-3 text-gray-900 text-lg font-medium focus:outline-none focus:border-gray-900 focus:ring-1 focus:ring-gray-900 [appearance:textfield] [&::-webkit-outer-spin-button]:appearance-none [&::-webkit-inner-spin-button]:appearance-none"
                        />
                        <div class="absolute right-3 top-1/2 -translate-y-1/2 flex items-center gap-1.5">
                          <img src={Map.get(@token_logos, "BUX", "https://ik.imagekit.io/blockster/blockster-icon.png")} alt="BUX" class="w-5 h-5 rounded-full" />
                          <span class="text-sm text-gray-500 font-medium">BUX</span>
                        </div>
                      </div>

                      <!-- Preview -->
                      <div class="mt-3 bg-gray-50 rounded-lg p-3">
                        <div class="flex items-center justify-between text-sm">
                          <span class="text-gray-500">You receive</span>
                          <span class="text-[#141414] font-medium">
                            ~<%= preview_lp_tokens(@deposit_amount, @lp_price, @lp_supply, @pool_total, @pool_unsettled) %> LP-BUX
                          </span>
                        </div>
                        <div class="flex items-center justify-between text-xs mt-1">
                          <span class="text-gray-500">LP Price</span>
                          <span class="text-gray-500"><%= format_lp_price(@lp_price) %> BUX</span>
                        </div>
                      </div>

                      <!-- Error / Success Messages -->
                      <%= if @action_error do %>
                        <div class="mt-3 bg-red-50 border border-red-300 rounded-lg p-2 text-red-600 text-xs">
                          <%= @action_error %>
                        </div>
                      <% end %>
                      <%= if @action_success do %>
                        <div class="mt-3 bg-green-50 border border-green-200 rounded-lg p-2 text-green-600 text-xs">
                          <%= @action_success %>
                        </div>
                      <% end %>

                      <!-- Deposit Button -->
                      <button
                        type="button"
                        phx-click="deposit_bux"
                        disabled={@action_loading or @deposit_amount == "" or parse_amount(@deposit_amount) <= 0}
                        class="w-full mt-4 py-3 bg-black text-white font-haas_medium_65 text-sm rounded-lg hover:bg-gray-800 transition-colors cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed"
                      >
                        <%= if @action_loading do %>
                          <span class="flex items-center justify-center gap-2">
                            <div class="w-4 h-4 border-2 border-black/30 border-t-black rounded-full animate-spin"></div>
                            Confirming...
                          </span>
                        <% else %>
                          Deposit BUX
                        <% end %>
                      </button>
                    </div>

                  <% else %>
                    <!-- WITHDRAW FORM -->
                    <div>
                      <div class="flex items-center justify-between mb-2">
                        <label class="text-xs text-gray-500">Withdraw LP-BUX</label>
                        <button
                          type="button"
                          phx-click="set_max_withdraw"
                          class="text-[10px] text-gray-500 hover:text-[#141414] cursor-pointer"
                        >
                          LP Balance: <span class="text-gray-700"><%= format_balance(@lp_user_balance) %></span>
                        </button>
                      </div>
                      <div class="relative">
                        <input
                          type="number"
                          value={@withdraw_amount}
                          phx-keyup="update_withdraw_amount"
                          phx-debounce="100"
                          min="1"
                          placeholder="0"
                          class="w-full bg-white border border-gray-300 rounded-lg px-3 py-3 text-gray-900 text-lg font-medium focus:outline-none focus:border-gray-900 focus:ring-1 focus:ring-gray-900 [appearance:textfield] [&::-webkit-outer-spin-button]:appearance-none [&::-webkit-inner-spin-button]:appearance-none"
                        />
                        <div class="absolute right-3 top-1/2 -translate-y-1/2 flex items-center gap-1.5">
                          <span class="text-sm text-gray-500 font-medium">LP-BUX</span>
                        </div>
                      </div>

                      <!-- Preview -->
                      <div class="mt-3 bg-gray-50 rounded-lg p-3">
                        <div class="flex items-center justify-between text-sm">
                          <span class="text-gray-500">You receive</span>
                          <span class="text-[#141414] font-medium flex items-center gap-1">
                            ~<%= preview_bux_out(@withdraw_amount, @lp_price, @lp_supply, @pool_net) %> BUX
                          </span>
                        </div>
                        <div class="flex items-center justify-between text-xs mt-1">
                          <span class="text-gray-500">Withdrawal Price</span>
                          <span class="text-gray-500"><%= format_withdrawal_price(@pool_net, @lp_supply) %> BUX</span>
                        </div>
                      </div>

                      <!-- Error / Success Messages -->
                      <%= if @action_error do %>
                        <div class="mt-3 bg-red-50 border border-red-300 rounded-lg p-2 text-red-600 text-xs">
                          <%= @action_error %>
                        </div>
                      <% end %>
                      <%= if @action_success do %>
                        <div class="mt-3 bg-green-50 border border-green-200 rounded-lg p-2 text-green-600 text-xs">
                          <%= @action_success %>
                        </div>
                      <% end %>

                      <!-- Withdraw Button -->
                      <button
                        type="button"
                        phx-click="withdraw_bux"
                        disabled={@action_loading or @withdraw_amount == "" or parse_amount(@withdraw_amount) <= 0}
                        class="w-full mt-4 py-3 bg-black text-white font-haas_medium_65 text-sm rounded-lg hover:bg-gray-800 transition-colors cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed"
                      >
                        <%= if @action_loading do %>
                          <span class="flex items-center justify-center gap-2">
                            <div class="w-4 h-4 border-2 border-black/30 border-t-black rounded-full animate-spin"></div>
                            Confirming...
                          </span>
                        <% else %>
                          Withdraw BUX
                        <% end %>
                      </button>
                    </div>
                  <% end %>

                  <!-- Your Position -->
                  <%= if @lp_user_balance > 0 do %>
                    <div class="mt-4 pt-4 border-t border-gray-200">
                      <p class="text-xs text-gray-500 uppercase tracking-wide mb-2">Your Position</p>
                      <div class="space-y-1.5">
                        <div class="flex items-center justify-between text-sm">
                          <span class="text-gray-500">LP-BUX Held</span>
                          <span class="text-[#141414] font-medium"><%= format_balance(@lp_user_balance) %></span>
                        </div>
                        <div class="flex items-center justify-between text-sm">
                          <span class="text-gray-500">Value in BUX</span>
                          <span class="text-[#141414] font-bold">
                            ~<%= format_balance(Float.round(@lp_user_balance * @lp_price, 2)) %>
                          </span>
                        </div>
                        <div class="flex items-center justify-between text-sm">
                          <span class="text-gray-500">Pool Share</span>
                          <span class="text-gray-700">
                            <%= if @lp_supply > 0, do: Float.round(@lp_user_balance / @lp_supply * 100, 2), else: 0 %>%
                          </span>
                        </div>
                      </div>
                    </div>
                  <% end %>

                  <!-- How it works -->
                  <div class="mt-4 pt-4 border-t border-gray-200">
                    <p class="text-xs text-gray-500 uppercase tracking-wide mb-2">How It Works</p>
                    <ul class="space-y-1.5 text-xs text-gray-500">
                      <li class="flex gap-2">
                        <span class="text-[#141414] font-bold shrink-0">1.</span>
                        <span>Deposit BUX to receive LP-BUX tokens</span>
                      </li>
                      <li class="flex gap-2">
                        <span class="text-[#141414] font-bold shrink-0">2.</span>
                        <span>LP-BUX price rises when the house wins bets</span>
                      </li>
                      <li class="flex gap-2">
                        <span class="text-[#141414] font-bold shrink-0">3.</span>
                        <span>Withdraw anytime to redeem BUX at current LP price</span>
                      </li>
                    </ul>
                  </div>
                </div>

              <% else %>
                <!-- Unauthenticated: Login prompt -->
                <div class="p-6 text-center">
                  <p class="text-gray-500 text-sm mb-4">Log in to deposit BUX and earn LP rewards</p>
                  <.link
                    navigate={~p"/login"}
                    class="inline-block px-6 py-3 bg-black text-white font-haas_medium_65 text-sm rounded-lg hover:bg-gray-800 transition-colors cursor-pointer"
                  >
                    Connect Wallet
                  </.link>

                  <!-- How it works (also shown for unauth) -->
                  <div class="mt-6 pt-4 border-t border-gray-200 text-left">
                    <p class="text-xs text-gray-500 uppercase tracking-wide mb-2">How It Works</p>
                    <ul class="space-y-1.5 text-xs text-gray-500">
                      <li class="flex gap-2">
                        <span class="text-[#141414] font-bold shrink-0">1.</span>
                        <span>Deposit BUX to receive LP-BUX tokens</span>
                      </li>
                      <li class="flex gap-2">
                        <span class="text-[#141414] font-bold shrink-0">2.</span>
                        <span>LP-BUX price rises when the house wins bets</span>
                      </li>
                      <li class="flex gap-2">
                        <span class="text-[#141414] font-bold shrink-0">3.</span>
                        <span>Withdraw anytime to redeem BUX at current LP price</span>
                      </li>
                    </ul>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ============================================================
  # Event Handlers
  # ============================================================

  @impl true
  def handle_event("select_timeframe", %{"timeframe" => tf}, socket) do
    config = Map.get(@timeframe_configs, tf, @timeframe_configs["24h"])

    socket =
      socket
      |> assign(selected_timeframe: tf, chart_loading: true)
      |> start_async(:fetch_candles, fn ->
        LPBuxPriceTracker.get_candles(config.candle_seconds, config.count)
      end)

    {:noreply, socket}
  end

  def handle_event("set_action_tab", %{"tab" => tab}, socket) do
    tab_atom = if tab == "withdraw", do: :withdraw, else: :deposit
    {:noreply, assign(socket, active_tab: tab_atom, action_error: nil, action_success: nil)}
  end

  def handle_event("update_deposit_amount", %{"value" => val}, socket) do
    {:noreply, assign(socket, deposit_amount: val, action_error: nil, action_success: nil)}
  end

  def handle_event("update_withdraw_amount", %{"value" => val}, socket) do
    {:noreply, assign(socket, withdraw_amount: val, action_error: nil, action_success: nil)}
  end

  def handle_event("set_max_deposit", _params, socket) do
    bux_balance = Map.get(socket.assigns.balances, "BUX", 0)
    amount = trunc(bux_balance)
    {:noreply, assign(socket, deposit_amount: to_string(amount))}
  end

  def handle_event("set_max_withdraw", _params, socket) do
    amount = trunc(socket.assigns.lp_user_balance)
    {:noreply, assign(socket, withdraw_amount: to_string(amount))}
  end

  def handle_event("deposit_bux", _params, socket) do
    amount = parse_amount(socket.assigns.deposit_amount)
    bux_balance = Map.get(socket.assigns.balances, "BUX", 0)

    cond do
      amount <= 0 ->
        {:noreply, assign(socket, action_error: "Enter a valid amount")}
      amount > bux_balance ->
        {:noreply, assign(socket, action_error: "Insufficient BUX balance")}
      true ->
        socket =
          socket
          |> assign(action_loading: true, action_error: nil, action_success: nil)
          |> push_event("deposit_bux", %{amount: amount})
        {:noreply, socket}
    end
  end

  def handle_event("withdraw_bux", _params, socket) do
    lp_amount = parse_amount(socket.assigns.withdraw_amount)

    cond do
      lp_amount <= 0 ->
        {:noreply, assign(socket, action_error: "Enter a valid amount")}
      lp_amount > socket.assigns.lp_user_balance ->
        {:noreply, assign(socket, action_error: "Insufficient LP-BUX balance")}
      true ->
        socket =
          socket
          |> assign(action_loading: true, action_error: nil, action_success: nil)
          |> push_event("withdraw_bux", %{lp_amount: lp_amount})
        {:noreply, socket}
    end
  end

  # JS hook pushEvents for on-chain confirmations
  def handle_event("deposit_confirmed", %{"tx_hash" => tx_hash}, socket) do
    Logger.info("[BankrollLive] Deposit confirmed: #{tx_hash}")

    user = socket.assigns.current_user
    wallet = socket.assigns.wallet_address

    if user && wallet do
      BuxMinter.sync_user_balances_async(user.id, wallet, force: true)
    end

    socket =
      socket
      |> assign(action_loading: false, deposit_amount: "")
      |> assign(action_success: "Deposit confirmed! TX: #{String.slice(tx_hash, 0..13)}...")
      |> start_async(:fetch_pool_info, fn -> BuxMinter.bux_bankroll_house_info() end)
      |> maybe_fetch_lp_balance(user, wallet)

    {:noreply, socket}
  end

  def handle_event("deposit_failed", %{"error" => error}, socket) do
    {:noreply, assign(socket, action_loading: false, action_error: error)}
  end

  def handle_event("withdraw_confirmed", %{"tx_hash" => tx_hash}, socket) do
    Logger.info("[BankrollLive] Withdrawal confirmed: #{tx_hash}")

    user = socket.assigns.current_user
    wallet = socket.assigns.wallet_address

    if user && wallet do
      BuxMinter.sync_user_balances_async(user.id, wallet, force: true)
    end

    socket =
      socket
      |> assign(action_loading: false, withdraw_amount: "")
      |> assign(action_success: "Withdrawal confirmed! TX: #{String.slice(tx_hash, 0..13)}...")
      |> start_async(:fetch_pool_info, fn -> BuxMinter.bux_bankroll_house_info() end)
      |> maybe_fetch_lp_balance(user, wallet)

    {:noreply, socket}
  end

  def handle_event("withdraw_failed", %{"error" => error}, socket) do
    {:noreply, assign(socket, action_loading: false, action_error: error)}
  end

  # ============================================================
  # Async Handlers
  # ============================================================

  @impl true
  def handle_async(:fetch_pool_info, {:ok, result}, socket) do
    case result do
      {:ok, info} ->
        total = parse_pool_value(info, "totalBalance")
        net = parse_pool_value(info, "netBalance")
        liability = parse_pool_value(info, "liability")
        unsettled = parse_pool_value(info, "unsettledBets")
        supply = parse_pool_value(info, "poolTokenSupply")
        price = parse_pool_float(info, "poolTokenPrice", 1.0)

        {:noreply,
         assign(socket,
           pool_total: total,
           pool_net: net,
           pool_liability: liability,
           pool_unsettled: unsettled,
           lp_supply: supply,
           lp_price: price,
           pool_loading: false
         )}

      _ ->
        Logger.warning("[BankrollLive] Failed to fetch pool info: #{inspect(result)}")
        {:noreply, assign(socket, pool_loading: false)}
    end
  end

  def handle_async(:fetch_pool_info, {:exit, reason}, socket) do
    Logger.warning("[BankrollLive] Pool info fetch crashed: #{inspect(reason)}")
    {:noreply, assign(socket, pool_loading: false)}
  end

  def handle_async(:fetch_candles, {:ok, candles}, socket) when is_list(candles) do
    socket =
      socket
      |> assign(chart_loading: false, candles: candles)
      |> push_event("set_candles", %{candles: candles})

    {high, low} = extract_price_range(candles)
    {:noreply, assign(socket, price_high_24h: high, price_low_24h: low)}
  end

  def handle_async(:fetch_candles, {:ok, _other}, socket) do
    {:noreply, assign(socket, chart_loading: false)}
  end

  def handle_async(:fetch_candles, {:exit, _reason}, socket) do
    {:noreply, assign(socket, chart_loading: false)}
  end

  def handle_async(:fetch_lp_balance, {:ok, result}, socket) do
    case result do
      {:ok, balance_str} when is_binary(balance_str) ->
        balance = parse_lp_balance(balance_str)
        {:noreply, assign(socket, lp_user_balance: balance)}
      {:ok, balance} when is_number(balance) ->
        {:noreply, assign(socket, lp_user_balance: balance / 1.0)}
      _ ->
        {:noreply, socket}
    end
  end

  def handle_async(:fetch_lp_balance, {:exit, _reason}, socket) do
    {:noreply, socket}
  end

  # ============================================================
  # PubSub Handlers
  # ============================================================

  @impl true
  def handle_info({:lp_bux_price_updated, data}, socket) do
    socket =
      socket
      |> assign(lp_price: data.price)
      |> push_event("update_candle", %{candle: data.candle})

    {:noreply, socket}
  end

  def handle_info({:bux_balance_updated, _balance}, socket) do
    user = socket.assigns.current_user
    if user do
      balances = EngagementTracker.get_user_token_balances(user.id)
      {:noreply, assign(socket, balances: balances)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:token_balances_updated, balances}, socket) do
    {:noreply, assign(socket, balances: balances)}
  end

  def handle_info({:token_prices_updated, _prices}, socket) do
    {:noreply, assign(socket, rogue_usd_price: get_rogue_price())}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ============================================================
  # Helpers
  # ============================================================

  defp format_balance(amount) when is_float(amount) do
    Number.Currency.number_to_currency(amount, unit: "", precision: 2)
  end

  defp format_balance(amount) when is_integer(amount) do
    Number.Currency.number_to_currency(amount, unit: "", precision: 0)
  end

  defp format_balance(_), do: "0"

  defp format_lp_price(price) when is_float(price) do
    :erlang.float_to_binary(price, decimals: 4)
  end

  defp format_lp_price(_), do: "1.0000"

  defp format_withdrawal_price(pool_net, lp_supply) when is_number(pool_net) and is_number(lp_supply) and lp_supply > 0 do
    price = pool_net / lp_supply
    :erlang.float_to_binary(price / 1.0, decimals: 4)
  end

  defp format_withdrawal_price(_, _), do: "1.0000"

  defp parse_amount(""), do: 0
  defp parse_amount(val) when is_binary(val) do
    case Float.parse(val) do
      {num, _} -> trunc(num)
      :error -> 0
    end
  end

  defp parse_amount(val) when is_number(val), do: trunc(val)
  defp parse_amount(_), do: 0

  defp preview_lp_tokens("", _, _, _, _), do: "0"
  defp preview_lp_tokens(amount_str, _lp_price, lp_supply, pool_total, pool_unsettled) do
    amount = parse_amount(amount_str)
    cond do
      amount <= 0 -> "0"
      lp_supply == 0 -> format_balance(amount)  # 1:1 for first deposit
      true ->
        effective = max(pool_total - pool_unsettled, 1)
        lp_out = amount * lp_supply / effective
        format_balance(Float.round(lp_out / 1.0, 2))
    end
  end

  defp preview_bux_out("", _, _, _), do: "0"
  defp preview_bux_out(lp_str, _lp_price, lp_supply, pool_net) do
    lp_amount = parse_amount(lp_str)
    cond do
      lp_amount <= 0 -> "0"
      lp_supply == 0 -> "0"
      true ->
        bux_out = lp_amount * pool_net / lp_supply
        format_balance(Float.round(bux_out / 1.0, 2))
    end
  end

  defp extract_price_range([]), do: {nil, nil}
  defp extract_price_range(candles) do
    highs = Enum.map(candles, fn c -> Map.get(c, :high, 0) end)
    lows = Enum.map(candles, fn c -> Map.get(c, :low, 0) end)
    {Enum.max(highs), Enum.min(lows)}
  end

  # All on-chain values come back as wei strings (18 decimals).
  # Convert to human-readable token amounts.
  @wei 1.0e18

  defp parse_pool_value(info, key) do
    case Map.get(info, key) do
      nil -> 0
      val when is_integer(val) -> val
      val when is_float(val) -> trunc(val)
      val when is_binary(val) ->
        case Float.parse(val) do
          {num, _} -> trunc(num / @wei)
          :error -> 0
        end
    end
  end

  defp parse_pool_float(info, key, default) do
    case Map.get(info, key) do
      nil -> default
      val when is_float(val) -> val
      val when is_integer(val) -> val / 1.0
      val when is_binary(val) ->
        case Float.parse(val) do
          {num, _} -> num / @wei
          :error -> default
        end
    end
  end

  defp parse_lp_balance(balance_str) when is_binary(balance_str) do
    case Float.parse(balance_str) do
      {num, _} -> num / @wei
      :error -> 0.0
    end
  end

  defp get_rogue_price do
    case PriceTracker.get_price("ROGUE") do
      {:ok, %{usd_price: price}} -> price
      _ -> nil
    end
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  # Timeframe sorting order
  defp timeframe_order("1h"), do: 0
  defp timeframe_order("24h"), do: 1
  defp timeframe_order("7d"), do: 2
  defp timeframe_order("30d"), do: 3
  defp timeframe_order("all"), do: 4
  defp timeframe_order(_), do: 5
end
