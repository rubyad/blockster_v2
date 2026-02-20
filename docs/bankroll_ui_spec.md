# BankrollLive UI Specification

> Complete implementation spec for the BUX Bankroll dashboard page.
> Includes LiveView module, HEEx template, chart JS hook, and on-chain JS hook.

---

## 1. LiveView Module: `lib/blockster_v2_web/live/bankroll_live.ex`

```elixir
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
      |> assign(rogue_usd_price: PriceTracker.get_rogue_price())
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
    ~H"""
    <div
      id="bankroll-page"
      phx-hook="BankrollOnchain"
      data-wallet={@wallet_address}
      class="min-h-screen bg-zinc-950"
    >
      <div class="max-w-5xl mx-auto px-3 sm:px-4 pt-6 sm:pt-24 pb-8">
        <!-- Page Title -->
        <div class="mb-6">
          <h1 class="text-2xl sm:text-3xl font-haas_medium_65 text-white">BUX Bankroll</h1>
          <p class="text-sm text-zinc-400 mt-1">Provide liquidity to the BUX house pool. Earn when the house wins.</p>
        </div>

        <!-- Pool Stats Bar -->
        <div class="bg-zinc-900 rounded-xl border border-zinc-800 p-4 mb-6">
          <%= if @pool_loading do %>
            <div class="flex items-center justify-center py-4">
              <div class="w-5 h-5 border-2 border-zinc-600 border-t-[#CAFC00] rounded-full animate-spin"></div>
              <span class="ml-2 text-sm text-zinc-500">Loading pool data...</span>
            </div>
          <% else %>
            <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-4">
              <div>
                <p class="text-[10px] sm:text-xs text-zinc-500 uppercase tracking-wide">Total BUX</p>
                <p class="text-base sm:text-lg font-haas_medium_65 text-white"><%= format_balance(@pool_total) %></p>
              </div>
              <div>
                <p class="text-[10px] sm:text-xs text-zinc-500 uppercase tracking-wide">Net Balance</p>
                <p class="text-base sm:text-lg font-haas_medium_65 text-white"><%= format_balance(@pool_net) %></p>
              </div>
              <div>
                <p class="text-[10px] sm:text-xs text-zinc-500 uppercase tracking-wide">Outstanding Bets</p>
                <p class="text-base sm:text-lg font-haas_medium_65 text-amber-400"><%= format_balance(@pool_liability) %></p>
              </div>
              <div>
                <p class="text-[10px] sm:text-xs text-zinc-500 uppercase tracking-wide">LP-BUX Supply</p>
                <p class="text-base sm:text-lg font-haas_medium_65 text-white"><%= format_balance(@lp_supply) %></p>
              </div>
              <div>
                <p class="text-[10px] sm:text-xs text-zinc-500 uppercase tracking-wide">LP-BUX Price</p>
                <p class="text-base sm:text-lg font-haas_medium_65 text-[#CAFC00]">
                  <%= format_lp_price(@lp_price) %> BUX
                  <%= if @price_change_24h do %>
                    <span class={"text-xs #{if @price_change_24h >= 0, do: "text-green-400", else: "text-red-400"}"}>
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
            <div class="bg-zinc-900 rounded-xl border border-zinc-800 overflow-hidden">
              <!-- Timeframe Tabs -->
              <div class="flex items-center gap-1 p-3 border-b border-zinc-800">
                <%= for {key, config} <- @timeframe_configs do %>
                  <button
                    type="button"
                    phx-click="select_timeframe"
                    phx-value-timeframe={key}
                    class={"px-3 py-1.5 rounded-lg text-xs font-medium cursor-pointer transition-colors #{if @selected_timeframe == key, do: "bg-[#CAFC00] text-black", else: "bg-zinc-800 text-zinc-400 hover:bg-zinc-700 hover:text-zinc-300"}"}
                  >
                    <%= config.label %>
                  </button>
                <% end %>
                <!-- Price range info -->
                <div class="ml-auto flex items-center gap-3 text-[10px] sm:text-xs text-zinc-500">
                  <%= if @price_high_24h do %>
                    <span>H: <span class="text-green-400"><%= format_lp_price(@price_high_24h) %></span></span>
                    <span>L: <span class="text-red-400"><%= format_lp_price(@price_low_24h) %></span></span>
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
                    <div class="w-5 h-5 border-2 border-zinc-600 border-t-[#CAFC00] rounded-full animate-spin"></div>
                    <span class="ml-2 text-sm text-zinc-500">Loading chart...</span>
                  </div>
                <% end %>
              </div>
            </div>
          </div>

          <!-- RIGHT: Deposit / Withdraw Panel (1/3 width on desktop) -->
          <div class="lg:col-span-1">
            <div class="bg-zinc-900 rounded-xl border border-zinc-800">
              <!-- Tab Switcher -->
              <div class="flex border-b border-zinc-800">
                <button
                  type="button"
                  phx-click="set_action_tab"
                  phx-value-tab="deposit"
                  class={"flex-1 py-3 text-sm font-haas_medium_65 text-center cursor-pointer transition-colors #{if @active_tab == :deposit, do: "text-[#CAFC00] border-b-2 border-[#CAFC00]", else: "text-zinc-500 hover:text-zinc-300"}"}
                >
                  Deposit
                </button>
                <button
                  type="button"
                  phx-click="set_action_tab"
                  phx-value-tab="withdraw"
                  class={"flex-1 py-3 text-sm font-haas_medium_65 text-center cursor-pointer transition-colors #{if @active_tab == :withdraw, do: "text-[#CAFC00] border-b-2 border-[#CAFC00]", else: "text-zinc-500 hover:text-zinc-300"}"}
                >
                  Withdraw
                </button>
              </div>

              <div class="p-4">
                <%= if @active_tab == :deposit do %>
                  <!-- DEPOSIT FORM -->
                  <div>
                    <div class="flex items-center justify-between mb-2">
                      <label class="text-xs text-zinc-400">Deposit BUX</label>
                      <button
                        type="button"
                        phx-click="set_max_deposit"
                        class="text-[10px] text-zinc-500 hover:text-[#CAFC00] cursor-pointer"
                      >
                        Balance: <span class="text-zinc-300"><%= format_balance(Map.get(@balances, "BUX", 0)) %></span>
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
                        class="w-full bg-zinc-800 border border-zinc-700 rounded-lg px-3 py-3 text-white text-lg font-medium focus:outline-none focus:border-[#CAFC00] focus:ring-1 focus:ring-[#CAFC00] [appearance:textfield] [&::-webkit-outer-spin-button]:appearance-none [&::-webkit-inner-spin-button]:appearance-none"
                      />
                      <div class="absolute right-3 top-1/2 -translate-y-1/2 flex items-center gap-1.5">
                        <img src={Map.get(@token_logos, "BUX", "https://ik.imagekit.io/blockster/blockster-icon.png")} alt="BUX" class="w-5 h-5 rounded-full" />
                        <span class="text-sm text-zinc-400 font-medium">BUX</span>
                      </div>
                    </div>

                    <!-- Preview -->
                    <div class="mt-3 bg-zinc-800/50 rounded-lg p-3">
                      <div class="flex items-center justify-between text-sm">
                        <span class="text-zinc-500">You receive</span>
                        <span class="text-white font-medium">
                          ~<%= preview_lp_tokens(@deposit_amount, @lp_price, @lp_supply, @pool_total, @pool_unsettled) %> LP-BUX
                        </span>
                      </div>
                      <div class="flex items-center justify-between text-xs mt-1">
                        <span class="text-zinc-500">LP Price</span>
                        <span class="text-zinc-400"><%= format_lp_price(@lp_price) %> BUX</span>
                      </div>
                    </div>

                    <!-- Error / Success Messages -->
                    <%= if @action_error do %>
                      <div class="mt-3 bg-red-900/30 border border-red-800 rounded-lg p-2 text-red-400 text-xs">
                        <%= @action_error %>
                      </div>
                    <% end %>
                    <%= if @action_success do %>
                      <div class="mt-3 bg-green-900/30 border border-green-800 rounded-lg p-2 text-green-400 text-xs">
                        <%= @action_success %>
                      </div>
                    <% end %>

                    <!-- Deposit Button -->
                    <button
                      type="button"
                      phx-click="deposit_bux"
                      disabled={@action_loading or !@current_user or @deposit_amount == "" or parse_amount(@deposit_amount) <= 0}
                      class="w-full mt-4 py-3 bg-[#CAFC00] text-black font-haas_medium_65 text-sm rounded-lg hover:bg-[#b8e600] transition-colors cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed"
                    >
                      <%= if @action_loading do %>
                        <span class="flex items-center justify-center gap-2">
                          <div class="w-4 h-4 border-2 border-black/30 border-t-black rounded-full animate-spin"></div>
                          Confirming...
                        </span>
                      <% else %>
                        <%= if @current_user, do: "Deposit BUX", else: "Connect Wallet" %>
                      <% end %>
                    </button>
                  </div>

                <% else %>
                  <!-- WITHDRAW FORM -->
                  <div>
                    <div class="flex items-center justify-between mb-2">
                      <label class="text-xs text-zinc-400">Withdraw LP-BUX</label>
                      <button
                        type="button"
                        phx-click="set_max_withdraw"
                        class="text-[10px] text-zinc-500 hover:text-[#CAFC00] cursor-pointer"
                      >
                        LP Balance: <span class="text-zinc-300"><%= format_balance(@lp_user_balance) %></span>
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
                        class="w-full bg-zinc-800 border border-zinc-700 rounded-lg px-3 py-3 text-white text-lg font-medium focus:outline-none focus:border-[#CAFC00] focus:ring-1 focus:ring-[#CAFC00] [appearance:textfield] [&::-webkit-outer-spin-button]:appearance-none [&::-webkit-inner-spin-button]:appearance-none"
                      />
                      <div class="absolute right-3 top-1/2 -translate-y-1/2 flex items-center gap-1.5">
                        <span class="text-sm text-zinc-400 font-medium">LP-BUX</span>
                      </div>
                    </div>

                    <!-- Preview -->
                    <div class="mt-3 bg-zinc-800/50 rounded-lg p-3">
                      <div class="flex items-center justify-between text-sm">
                        <span class="text-zinc-500">You receive</span>
                        <span class="text-white font-medium flex items-center gap-1">
                          ~<%= preview_bux_out(@withdraw_amount, @lp_price, @lp_supply, @pool_net) %> BUX
                        </span>
                      </div>
                      <div class="flex items-center justify-between text-xs mt-1">
                        <span class="text-zinc-500">Withdrawal Price</span>
                        <span class="text-zinc-400"><%= format_withdrawal_price(@pool_net, @lp_supply) %> BUX</span>
                      </div>
                    </div>

                    <!-- Error / Success Messages -->
                    <%= if @action_error do %>
                      <div class="mt-3 bg-red-900/30 border border-red-800 rounded-lg p-2 text-red-400 text-xs">
                        <%= @action_error %>
                      </div>
                    <% end %>
                    <%= if @action_success do %>
                      <div class="mt-3 bg-green-900/30 border border-green-800 rounded-lg p-2 text-green-400 text-xs">
                        <%= @action_success %>
                      </div>
                    <% end %>

                    <!-- Withdraw Button -->
                    <button
                      type="button"
                      phx-click="withdraw_bux"
                      disabled={@action_loading or !@current_user or @withdraw_amount == "" or parse_amount(@withdraw_amount) <= 0}
                      class="w-full mt-4 py-3 bg-[#CAFC00] text-black font-haas_medium_65 text-sm rounded-lg hover:bg-[#b8e600] transition-colors cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed"
                    >
                      <%= if @action_loading do %>
                        <span class="flex items-center justify-center gap-2">
                          <div class="w-4 h-4 border-2 border-black/30 border-t-black rounded-full animate-spin"></div>
                          Confirming...
                        </span>
                      <% else %>
                        <%= if @current_user, do: "Withdraw BUX", else: "Connect Wallet" %>
                      <% end %>
                    </button>
                  </div>
                <% end %>

                <!-- Your Position -->
                <%= if @current_user && @lp_user_balance > 0 do %>
                  <div class="mt-4 pt-4 border-t border-zinc-800">
                    <p class="text-xs text-zinc-500 uppercase tracking-wide mb-2">Your Position</p>
                    <div class="space-y-1.5">
                      <div class="flex items-center justify-between text-sm">
                        <span class="text-zinc-400">LP-BUX Held</span>
                        <span class="text-white font-medium"><%= format_balance(@lp_user_balance) %></span>
                      </div>
                      <div class="flex items-center justify-between text-sm">
                        <span class="text-zinc-400">Value in BUX</span>
                        <span class="text-[#CAFC00] font-medium">
                          ~<%= format_balance(Float.round(@lp_user_balance * @lp_price, 2)) %>
                        </span>
                      </div>
                      <div class="flex items-center justify-between text-sm">
                        <span class="text-zinc-400">Pool Share</span>
                        <span class="text-zinc-300">
                          <%= if @lp_supply > 0, do: Float.round(@lp_user_balance / @lp_supply * 100, 2), else: 0 %>%
                        </span>
                      </div>
                    </div>
                  </div>
                <% end %>

                <!-- How it works -->
                <div class="mt-4 pt-4 border-t border-zinc-800">
                  <p class="text-xs text-zinc-500 uppercase tracking-wide mb-2">How It Works</p>
                  <ul class="space-y-1.5 text-xs text-zinc-400">
                    <li class="flex gap-2">
                      <span class="text-[#CAFC00] shrink-0">1.</span>
                      <span>Deposit BUX to receive LP-BUX tokens</span>
                    </li>
                    <li class="flex gap-2">
                      <span class="text-[#CAFC00] shrink-0">2.</span>
                      <span>LP-BUX price rises when the house wins bets</span>
                    </li>
                    <li class="flex gap-2">
                      <span class="text-[#CAFC00] shrink-0">3.</span>
                      <span>Withdraw anytime to redeem BUX at current LP price</span>
                    </li>
                  </ul>
                </div>
              </div>
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

    # Refresh pool info and user balances
    user = socket.assigns.current_user
    wallet = socket.assigns.wallet_address

    if user && wallet do
      BuxMinter.sync_user_balances_async(user.id, wallet)
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
      BuxMinter.sync_user_balances_async(user.id, wallet)
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
        # info = %{total_balance: int, liability: int, unsettled_bets: int,
        #          net_balance: int, pool_token_supply: int, pool_token_price: float}
        total = Map.get(info, :total_balance, 0)
        net = Map.get(info, :net_balance, 0)
        liability = Map.get(info, :liability, 0)
        unsettled = Map.get(info, :unsettled_bets, 0)
        supply = Map.get(info, :pool_token_supply, 0)
        price = Map.get(info, :pool_token_price, 1.0)

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

  def handle_async(:fetch_candles, {:ok, result}, socket) do
    case result do
      {:ok, candles} ->
        # Push candles to JS chart hook
        socket =
          socket
          |> assign(chart_loading: false, candles: candles)
          |> push_event("set_candles", %{candles: candles})

        # Extract price range stats
        {high, low} = extract_price_range(candles)

        {:noreply, assign(socket, price_high_24h: high, price_low_24h: low)}

      _ ->
        {:noreply, assign(socket, chart_loading: false)}
    end
  end

  def handle_async(:fetch_candles, {:exit, _reason}, socket) do
    {:noreply, assign(socket, chart_loading: false)}
  end

  def handle_async(:fetch_lp_balance, {:ok, result}, socket) do
    case result do
      {:ok, balance} -> {:noreply, assign(socket, lp_user_balance: balance)}
      _ -> {:noreply, socket}
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
    # data = %{price: float, candle: %{time: int, open: float, high: float, low: float, close: float}}
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
    {:noreply, assign(socket, rogue_usd_price: PriceTracker.get_rogue_price())}
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

  defp format_withdrawal_price(pool_net, lp_supply) when lp_supply > 0 do
    price = pool_net / lp_supply
    :erlang.float_to_binary(price, decimals: 4)
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
  defp preview_lp_tokens(amount_str, lp_price, lp_supply, pool_total, pool_unsettled) do
    amount = parse_amount(amount_str)
    cond do
      amount <= 0 -> "0"
      lp_supply == 0 -> format_balance(amount)  # 1:1 for first deposit
      true ->
        effective = max(pool_total - pool_unsettled, 1)
        lp_out = amount * lp_supply / effective
        format_balance(Float.round(lp_out, 2))
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
        format_balance(Float.round(bux_out, 2))
    end
  end

  defp extract_price_range([]), do: {nil, nil}
  defp extract_price_range(candles) do
    highs = Enum.map(candles, & &1.high)
    lows = Enum.map(candles, & &1.low)
    {Enum.max(highs), Enum.min(lows)}
  end
end
```

---

## 2. Chart Hook: `assets/js/lp_bux_chart.js`

```javascript
import { createChart, CandlestickSeries } from 'lightweight-charts';

export const LPBuxChart = {
  mounted() {
    this.initChart();

    // Handle initial candle data from LiveView
    this.handleEvent("set_candles", ({ candles }) => {
      if (!this.candleSeries) return;

      const data = candles.map(c => ({
        time: c.time,
        open: c.open,
        high: c.high,
        low: c.low,
        close: c.close,
      }));
      this.candleSeries.setData(data);
      this.chart.timeScale().fitContent();
    });

    // Handle real-time candle updates via PubSub
    this.handleEvent("update_candle", ({ candle }) => {
      if (!this.candleSeries) return;

      this.candleSeries.update({
        time: candle.time,
        open: candle.open,
        high: candle.high,
        low: candle.low,
        close: candle.close,
      });
    });

    // Responsive resize
    this.resizeObserver = new ResizeObserver(entries => {
      if (!this.chart) return;
      const { width } = entries[0].contentRect;
      this.chart.applyOptions({ width });
    });
    this.resizeObserver.observe(this.el);
  },

  initChart() {
    this.chart = createChart(this.el, {
      width: this.el.clientWidth,
      height: 400,
      layout: {
        background: { color: '#18181b' },     // zinc-900
        textColor: '#a1a1aa',                  // zinc-400
        fontFamily: "'Neue Haas Grotesk Display Pro 55 Roman', system-ui, sans-serif",
      },
      grid: {
        vertLines: { color: '#27272a' },       // zinc-800
        horzLines: { color: '#27272a' },
      },
      crosshair: {
        mode: 0,  // Normal crosshair
        vertLine: { color: '#52525b', labelBackgroundColor: '#3f3f46' },
        horzLine: { color: '#52525b', labelBackgroundColor: '#3f3f46' },
      },
      timeScale: {
        timeVisible: true,
        secondsVisible: false,
        borderColor: '#3f3f46',                // zinc-700
      },
      rightPriceScale: {
        borderColor: '#3f3f46',
        scaleMargins: { top: 0.1, bottom: 0.1 },
      },
      handleScroll: { mouseWheel: true, pressedMouseMove: true },
      handleScale: { mouseWheel: true, pinch: true },
    });

    this.candleSeries = this.chart.addSeries(CandlestickSeries, {
      upColor: '#CAFC00',                     // brand lime for up candles
      downColor: '#ef4444',                   // red for down candles
      borderUpColor: '#CAFC00',
      borderDownColor: '#ef4444',
      wickUpColor: '#CAFC00',
      wickDownColor: '#ef4444',
    });
  },

  destroyed() {
    if (this.resizeObserver) this.resizeObserver.disconnect();
    if (this.chart) this.chart.remove();
    this.chart = null;
    this.candleSeries = null;
  }
};
```

---

## 3. On-Chain Hook: `assets/js/bankroll_onchain.js`

```javascript
import { getContract, prepareContractCall, sendTransaction, readContract, waitForReceipt } from "thirdweb";

const BUX_BANKROLL_ADDRESS = "0x<DEPLOYED>";  // Set after deployment
const BUX_TOKEN_ADDRESS = "0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8";

export const BankrollOnchain = {
  mounted() {
    // Listen for deposit command from LiveView
    this.handleEvent("deposit_bux", async ({ amount }) => {
      await this.deposit(amount);
    });

    // Listen for withdraw command from LiveView
    this.handleEvent("withdraw_bux", async ({ lp_amount }) => {
      await this.withdraw(lp_amount);
    });
  },

  async deposit(amount) {
    try {
      const wallet = window.smartAccount;
      if (!wallet) {
        this.pushEvent("deposit_failed", { error: "No wallet connected. Please refresh." });
        return;
      }

      const amountWei = BigInt(amount) * BigInt(10 ** 18);
      const client = window.thirdwebClient;
      const chain = window.rogueChain;

      // 1. Check BUX approval for BUXBankroll
      const buxContract = getContract({ client, chain, address: BUX_TOKEN_ADDRESS });

      const allowance = await readContract({
        contract: buxContract,
        method: "function allowance(address owner, address spender) view returns (uint256)",
        params: [wallet.address, BUX_BANKROLL_ADDRESS],
      });

      if (BigInt(allowance) < amountWei) {
        console.log("[BankrollOnchain] Approving BUX for BUXBankroll...");
        const INFINITE = BigInt("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff");

        const approveTx = prepareContractCall({
          contract: buxContract,
          method: "function approve(address spender, uint256 amount) returns (bool)",
          params: [BUX_BANKROLL_ADDRESS, INFINITE],
        });

        const approveResult = await sendTransaction({ transaction: approveTx, account: wallet });
        await waitForReceipt({ client, chain, transactionHash: approveResult.transactionHash });
        console.log("[BankrollOnchain] BUX approved:", approveResult.transactionHash);
      }

      // 2. Call depositBUX on BUXBankroll
      const bankrollContract = getContract({ client, chain, address: BUX_BANKROLL_ADDRESS });

      const depositTx = prepareContractCall({
        contract: bankrollContract,
        method: "function depositBUX(uint256 amount)",
        params: [amountWei],
      });

      console.log("[BankrollOnchain] Depositing BUX...");
      const receipt = await sendTransaction({ transaction: depositTx, account: wallet });
      console.log("[BankrollOnchain] Deposit confirmed:", receipt.transactionHash);

      this.pushEvent("deposit_confirmed", { tx_hash: receipt.transactionHash });

    } catch (error) {
      console.error("[BankrollOnchain] Deposit failed:", error);
      const msg = this.parseError(error);
      this.pushEvent("deposit_failed", { error: msg });
    }
  },

  async withdraw(lpAmount) {
    try {
      const wallet = window.smartAccount;
      if (!wallet) {
        this.pushEvent("withdraw_failed", { error: "No wallet connected. Please refresh." });
        return;
      }

      const lpAmountWei = BigInt(lpAmount) * BigInt(10 ** 18);
      const client = window.thirdwebClient;
      const chain = window.rogueChain;

      const bankrollContract = getContract({ client, chain, address: BUX_BANKROLL_ADDRESS });

      const withdrawTx = prepareContractCall({
        contract: bankrollContract,
        method: "function withdrawBUX(uint256 lpAmount)",
        params: [lpAmountWei],
      });

      console.log("[BankrollOnchain] Withdrawing LP-BUX...");
      const receipt = await sendTransaction({ transaction: withdrawTx, account: wallet });
      console.log("[BankrollOnchain] Withdrawal confirmed:", receipt.transactionHash);

      this.pushEvent("withdraw_confirmed", { tx_hash: receipt.transactionHash });

    } catch (error) {
      console.error("[BankrollOnchain] Withdrawal failed:", error);
      const msg = this.parseError(error);
      this.pushEvent("withdraw_failed", { error: msg });
    }
  },

  parseError(error) {
    const msg = error?.message || error?.toString() || "";
    if (msg.includes("insufficient funds")) return "Insufficient funds for transaction";
    if (msg.includes("user rejected") || msg.includes("User rejected")) return "Transaction cancelled";
    if (msg.includes("InsufficientBalance")) return "Insufficient LP-BUX balance";
    if (msg.includes("InsufficientLiquidity")) return "Insufficient pool liquidity for withdrawal";
    if (msg.includes("ZeroAmount")) return "Amount must be greater than zero";
    return msg.slice(0, 200) || "Transaction failed";
  },
};
```

---

## 4. Register Hooks in `assets/js/app.js`

```javascript
import { LPBuxChart } from "./lp_bux_chart";
import { BankrollOnchain } from "./bankroll_onchain";

let hooks = {
  // ...existing hooks...
  LPBuxChart,
  BankrollOnchain,
};
```

---

## 5. Route in `router.ex`

```elixir
# Inside the authenticated scope:
live "/bankroll", BankrollLive, :index
```

---

## 6. Nav Link in `layouts.ex`

Add between "Play" and other nav items:

```elixir
<.link navigate={~p"/bankroll"} data-nav-path="/bankroll" class="...">Bankroll</.link>
```

---

## 7. CSS Additions (`assets/css/app.css`)

```css
/* LP-BUX Chart container */
#lp-bux-chart {
  background: #18181b;
}

/* Bankroll page dark theme overrides */
.bankroll-action-input:focus {
  border-color: #CAFC00;
  box-shadow: 0 0 0 1px #CAFC00;
}
```

---

## 8. Install Dependency

```bash
cd assets && npm install lightweight-charts
```

---

## 9. Design Notes

**Color Palette:**
- Background: `zinc-950` (page), `zinc-900` (cards)
- Borders: `zinc-800`
- Text primary: `white`
- Text secondary: `zinc-400`
- Text muted: `zinc-500`
- Accent: `#CAFC00` (brand lime)
- Up candles: `#CAFC00`
- Down candles: `#ef4444`
- Success: `green-400`
- Error: `red-400`
- Warning: `amber-400`

**Layout:**
- `max-w-5xl` centered container (wider than game pages)
- Desktop: 2/3 chart + 1/3 deposit/withdraw panel
- Mobile: stacked single column
- Pool stats bar spans full width above

**Mobile:**
- Pool stats: 2-col grid on mobile, 5-col on desktop
- Chart: full width, 400px height
- Deposit/Withdraw: full width below chart
- Tab switcher for deposit vs withdraw (saves space)
