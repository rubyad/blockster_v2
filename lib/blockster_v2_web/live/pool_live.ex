defmodule BlocksterV2Web.PoolLive do
  @moduledoc """
  @deprecated Use PoolIndexLive (/pool) and PoolDetailLive (/pool/:vault_type) instead.
  This module is no longer routed. Kept for reference during migration.
  """
  use BlocksterV2Web, :live_view
  require Logger

  alias BlocksterV2.EngagementTracker
  alias BlocksterV2.BuxMinter

  @impl true
  def mount(_params, _session, socket) do
    current_user = socket.assigns[:current_user]

    socket =
      socket
      |> assign(page_title: "Liquidity Pools")
      |> assign(pool_stats: nil)
      |> assign(pool_loading: true)
      |> assign(sol_tab: :deposit)
      |> assign(bux_tab: :deposit)
      |> assign(sol_amount: "")
      |> assign(bux_amount: "")
      |> assign(sol_processing: false)
      |> assign(bux_processing: false)
      |> assign(lp_balances: %{bsol: 0.0, bbux: 0.0})
      |> assign(balances: %{"SOL" => 0.0, "BUX" => 0.0})

    socket =
      if current_user do
        wallet_address = current_user.wallet_address

        if wallet_address && connected?(socket) do
          Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "bux_balance:#{current_user.id}")
        end

        # Read from Mnesia for fast initial render
        sol_balance = EngagementTracker.get_user_sol_balance(current_user.id)
        bux_balance = EngagementTracker.get_user_solana_bux_balance(current_user.id)
        lp_balances = EngagementTracker.get_user_lp_balances(current_user.id)

        socket
        |> assign(wallet_address: wallet_address)
        |> assign(balances: %{"SOL" => sol_balance, "BUX" => bux_balance})
        |> assign(lp_balances: lp_balances)
      else
        socket
        |> assign(Keyword.new(BlocksterV2Web.WalletAuthEvents.default_assigns()))
      end

    socket =
      if connected?(socket) do
        socket =
          socket
          |> start_async(:fetch_pool_stats, fn -> BuxMinter.get_pool_stats() end)

        # Sync all balances from on-chain (updates Mnesia + socket)
        if current_user && current_user.wallet_address do
          user_id = current_user.id
          wallet = current_user.wallet_address

          start_async(socket, :sync_on_mount, fn ->
            BuxMinter.sync_user_balances(user_id, wallet)

            bsol = case BuxMinter.get_lp_balance(wallet, "sol") do
              {:ok, v} -> v
              _ -> 0.0
            end
            bbux = case BuxMinter.get_lp_balance(wallet, "bux") do
              {:ok, v} -> v
              _ -> 0.0
            end
            EngagementTracker.update_user_bsol_balance(user_id, wallet, bsol)
            EngagementTracker.update_user_bbux_balance(user_id, wallet, bbux)

            sol = EngagementTracker.get_user_sol_balance(user_id)
            bux = EngagementTracker.get_user_solana_bux_balance(user_id)

            %{sol: sol, bux: bux, bsol: bsol, bbux: bbux}
          end)
        else
          socket
        end
      else
        socket
      end

    {:ok, socket}
  end

  # ── Balance Update Broadcasts ──

  def handle_info({:bux_balance_update, _user_id, _bux_balance}, socket) do
    if socket.assigns[:current_user] do
      user_id = socket.assigns.current_user.id
      sol = EngagementTracker.get_user_sol_balance(user_id)
      bux = EngagementTracker.get_user_solana_bux_balance(user_id)
      lp = EngagementTracker.get_user_lp_balances(user_id)

      {:noreply,
       socket
       |> assign(balances: %{"SOL" => sol, "BUX" => bux})
       |> assign(lp_balances: lp)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:token_balances_update, _user_id, balances}, socket) do
    sol = balances["SOL"] || socket.assigns.balances["SOL"]
    bux = balances["BUX"] || socket.assigns.balances["BUX"]
    {:noreply, assign(socket, balances: %{"SOL" => sol, "BUX" => bux})}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ── Tab Switching ──

  @impl true
  def handle_event("switch_sol_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, sol_tab: String.to_existing_atom(tab), sol_amount: "", sol_processing: false)}
  end

  def handle_event("switch_bux_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, bux_tab: String.to_existing_atom(tab), bux_amount: "", bux_processing: false)}
  end

  # ── Amount Inputs ──

  def handle_event("update_sol_amount", %{"value" => val}, socket) do
    {:noreply, assign(socket, sol_amount: val)}
  end

  def handle_event("update_bux_amount", %{"value" => val}, socket) do
    {:noreply, assign(socket, bux_amount: val)}
  end

  def handle_event("set_max_sol", _params, socket) do
    max =
      case socket.assigns.sol_tab do
        :deposit -> socket.assigns.balances["SOL"]
        :withdraw -> socket.assigns.lp_balances.bsol
      end

    {:noreply, assign(socket, sol_amount: format_max(max))}
  end

  def handle_event("set_max_bux", _params, socket) do
    max =
      case socket.assigns.bux_tab do
        :deposit -> socket.assigns.balances["BUX"]
        :withdraw -> socket.assigns.lp_balances.bbux
      end

    {:noreply, assign(socket, bux_amount: format_max(max))}
  end

  # ── Deposit / Withdraw Actions ──

  def handle_event("deposit_sol", _params, socket) do
    handle_pool_action(socket, "sol", :deposit)
  end

  def handle_event("withdraw_sol", _params, socket) do
    handle_pool_action(socket, "sol", :withdraw)
  end

  def handle_event("deposit_bux", _params, socket) do
    handle_pool_action(socket, "bux", :deposit)
  end

  def handle_event("withdraw_bux", _params, socket) do
    handle_pool_action(socket, "bux", :withdraw)
  end

  # ── Transaction Callbacks (from PoolHook JS) ──

  def handle_event("tx_confirmed", %{"vault_type" => vault_type, "action" => action, "signature" => sig}, socket) do
    Logger.info("[PoolLive] #{action} #{vault_type} confirmed: #{sig}")

    action_label = if action == "deposit", do: "Deposit", else: "Withdrawal"
    token_label = if vault_type == "sol", do: "SOL", else: "BUX"
    processing_key = if vault_type == "sol", do: :sol_processing, else: :bux_processing
    amount_key = if vault_type == "sol", do: :sol_amount, else: :bux_amount

    socket =
      socket
      |> assign([{processing_key, false}, {amount_key, ""}])
      |> put_flash(:info, "#{action_label} #{token_label} confirmed!")
      |> start_async(:fetch_pool_stats, fn -> BuxMinter.get_pool_stats() end)

    # Sync all balances and update socket when done
    socket =
      if socket.assigns[:current_user] do
        user_id = socket.assigns.current_user.id
        wallet = socket.assigns.wallet_address

        start_async(socket, :sync_post_tx, fn ->
          # Sync SOL + BUX balances
          BuxMinter.sync_user_balances(user_id, wallet)

          # Sync LP balances
          bsol = case BuxMinter.get_lp_balance(wallet, "sol") do
            {:ok, v} -> v
            _ -> 0.0
          end
          bbux = case BuxMinter.get_lp_balance(wallet, "bux") do
            {:ok, v} -> v
            _ -> 0.0
          end
          EngagementTracker.update_user_bsol_balance(user_id, wallet, bsol)
          EngagementTracker.update_user_bbux_balance(user_id, wallet, bbux)

          sol = EngagementTracker.get_user_sol_balance(user_id)
          bux = EngagementTracker.get_user_solana_bux_balance(user_id)

          %{sol: sol, bux: bux, bsol: bsol, bbux: bbux}
        end)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_event("tx_failed", %{"vault_type" => vault_type, "error" => error}, socket) do
    Logger.warning("[PoolLive] tx failed (#{vault_type}): #{error}")
    processing_key = if vault_type == "sol", do: :sol_processing, else: :bux_processing

    {:noreply,
     socket
     |> assign(processing_key, false)
     |> put_flash(:error, error)}
  end

  # ── Refresh ──

  def handle_event("refresh_stats", _params, socket) do
    {:noreply,
     socket
     |> assign(pool_loading: true)
     |> start_async(:fetch_pool_stats, fn -> BuxMinter.get_pool_stats() end)}
  end

  # ── Async Handlers ──

  @impl true
  def handle_async(:fetch_pool_stats, {:ok, {:ok, stats}}, socket) do
    {:noreply, assign(socket, pool_stats: stats, pool_loading: false)}
  end

  def handle_async(:fetch_pool_stats, {:ok, {:error, _reason}}, socket) do
    {:noreply, assign(socket, pool_loading: false)}
  end

  def handle_async(task, {:ok, %{sol: sol, bux: bux, bsol: bsol, bbux: bbux}}, socket)
      when task in [:sync_post_tx, :sync_on_mount] do
    {:noreply,
     socket
     |> assign(balances: %{"SOL" => sol, "BUX" => bux})
     |> assign(lp_balances: %{bsol: bsol, bbux: bbux})}
  end

  def handle_async(:sync_post_tx, _, socket), do: {:noreply, socket}

  def handle_async(:fetch_pool_stats, {:exit, _reason}, socket) do
    {:noreply, assign(socket, pool_loading: false)}
  end

  def handle_async(:build_tx, {:ok, {:ok, tx_data}}, socket) do
    %{transaction: tx, vault_type: vault_type, action: action} = tx_data
    event = if action == :deposit, do: "sign_deposit", else: "sign_withdraw"

    {:noreply, push_event(socket, event, %{transaction: tx, vault_type: vault_type})}
  end

  def handle_async(:build_tx, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(sol_processing: false, bux_processing: false)
     |> put_flash(:error, "Failed to build transaction: #{inspect(reason)}")}
  end

  def handle_async(:build_tx, {:exit, _reason}, socket) do
    {:noreply, assign(socket, sol_processing: false, bux_processing: false)}
  end

  # ── Render ──

  @impl true
  def render(assigns) do
    ~H"""
    <div id="pool-page" class="min-h-screen bg-gray-50" phx-hook="PoolHook">
      <div class="max-w-4xl mx-auto px-3 sm:px-6 pt-6 sm:pt-16 pb-12">
        <!-- Header -->
        <div class="mb-6 sm:mb-8">
          <.link navigate={~p"/play"} class="inline-flex items-center gap-1 text-sm text-gray-500 hover:text-gray-900 font-haas_roman_55 mb-3 cursor-pointer">
            <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
              <path stroke-linecap="round" stroke-linejoin="round" d="M15 19l-7-7 7-7" />
            </svg>
            Back to Play
          </.link>
          <h1 class="text-2xl sm:text-3xl font-haas_bold_75 text-gray-900 tracking-tight">Liquidity Pools</h1>
          <p class="text-sm text-gray-500 mt-1 font-haas_roman_55">Deposit liquidity, earn from house edge</p>
        </div>

        <!-- Pool Cards -->
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-4 sm:gap-6">
          <!-- SOL Pool Card -->
          <div class="bg-white rounded-2xl shadow-sm border border-gray-200 overflow-hidden ring-1 ring-violet-100">
            <!-- Card Header -->
            <div class="px-5 pt-5 pb-3 border-b border-violet-100 bg-gradient-to-r from-violet-50/50 to-transparent">
              <div class="flex items-center justify-between">
                <div class="flex items-center gap-2.5">
                  <div class="w-9 h-9 rounded-full bg-gradient-to-br from-violet-500 to-fuchsia-500 flex items-center justify-center shadow-sm">
                    <span class="text-white text-sm font-bold">S</span>
                  </div>
                  <div>
                    <h2 class="text-base font-haas_medium_65 text-gray-900">SOL Pool</h2>
                    <p class="text-[11px] text-gray-400">Earn from SOL bets</p>
                  </div>
                </div>
                <div class="text-right">
                  <div class="text-[11px] text-gray-400">Your LP</div>
                  <div class="text-sm font-haas_medium_65 text-gray-900"><%= format_lp(@lp_balances.bsol) %> SOL-LP</div>
                </div>
              </div>
              <!-- Pool stats inline -->
              <div class="flex items-center gap-4 mt-3 pt-2.5 border-t border-violet-100/60">
                <div>
                  <div class="text-[10px] text-gray-400 uppercase tracking-wide">Pool Balance</div>
                  <div class="text-sm font-haas_medium_65 text-gray-900">
                    <%= if @pool_loading, do: "...", else: "#{format_tvl(get_vault_stat(@pool_stats, "sol", "totalBalance"))} SOL" %>
                  </div>
                </div>
                <div class="w-px h-6 bg-gray-200"></div>
                <div>
                  <div class="text-[10px] text-gray-400 uppercase tracking-wide">SOL-LP Price</div>
                  <div class="text-sm font-haas_medium_65 text-gray-900">
                    <%= if @pool_loading, do: "...", else: "#{format_price(get_vault_stat(@pool_stats, "sol", "lpPrice"))} SOL" %>
                  </div>
                </div>
              </div>
            </div>

            <!-- Tabs -->
            <div class="flex border-b border-gray-100">
              <button
                type="button"
                phx-click="switch_sol_tab"
                phx-value-tab="deposit"
                class={"flex-1 py-2.5 text-center text-sm font-haas_medium_65 transition-all cursor-pointer #{if @sol_tab == :deposit, do: "text-gray-900 border-b-2 border-gray-900", else: "text-gray-400 hover:text-gray-600"}"}
              >
                Deposit
              </button>
              <button
                type="button"
                phx-click="switch_sol_tab"
                phx-value-tab="withdraw"
                class={"flex-1 py-2.5 text-center text-sm font-haas_medium_65 transition-all cursor-pointer #{if @sol_tab == :withdraw, do: "text-gray-900 border-b-2 border-gray-900", else: "text-gray-400 hover:text-gray-600"}"}
              >
                Withdraw
              </button>
            </div>

            <!-- Content -->
            <div class="p-5">
              <%= if @sol_tab == :deposit do %>
                <.pool_input
                  amount={@sol_amount}
                  token="SOL"
                  balance={@balances["SOL"]}
                  on_change="update_sol_amount"
                  on_max="set_max_sol"
                  label="Deposit SOL"
                  balance_label="Balance"
                />
                <.output_preview
                  amount={@sol_amount}
                  lp_price={get_vault_stat(@pool_stats, "sol", "lpPrice")}
                  lp_token="SOL-LP"
                  action="receive"
                />
                <button
                  type="button"
                  phx-click="deposit_sol"
                  disabled={@sol_processing || !valid_amount?(@sol_amount) || !@current_user}
                  class="w-full mt-4 py-3 rounded-xl font-haas_medium_65 text-sm transition-all cursor-pointer disabled:opacity-40 disabled:cursor-not-allowed bg-gray-900 text-white hover:bg-gray-800"
                >
                  <%= if @sol_processing, do: "Processing...", else: "Deposit SOL" %>
                </button>
              <% else %>
                <.pool_input
                  amount={@sol_amount}
                  token="SOL-LP"
                  balance={@lp_balances.bsol}
                  on_change="update_sol_amount"
                  on_max="set_max_sol"
                  label="Withdraw SOL-LP"
                  balance_label="LP Balance"
                />
                <.output_preview
                  amount={@sol_amount}
                  lp_price={get_vault_stat(@pool_stats, "sol", "lpPrice")}
                  lp_token="SOL"
                  action="receive"
                  multiply={true}
                />
                <button
                  type="button"
                  phx-click="withdraw_sol"
                  disabled={@sol_processing || !valid_amount?(@sol_amount) || !@current_user}
                  class="w-full mt-4 py-3 rounded-xl font-haas_medium_65 text-sm transition-all cursor-pointer disabled:opacity-40 disabled:cursor-not-allowed bg-gray-900 text-white hover:bg-gray-800"
                >
                  <%= if @sol_processing, do: "Processing...", else: "Withdraw SOL" %>
                </button>
              <% end %>

              <!-- Pool Share -->
              <%= if @lp_balances.bsol > 0 do %>
                <div class="mt-3 pt-3 border-t border-gray-100 flex items-center justify-between text-[11px] text-gray-400">
                  <span>Pool share</span>
                  <span class="font-haas_medium_65 text-gray-600"><%= pool_share(@lp_balances.bsol, get_vault_stat(@pool_stats, "sol", "lpSupply")) %></span>
                </div>
              <% end %>
            </div>
          </div>

          <!-- BUX Pool Card -->
          <div class="bg-white rounded-2xl shadow-sm border border-gray-200 overflow-hidden ring-1 ring-amber-100">
            <!-- Card Header -->
            <div class="px-5 pt-5 pb-3 border-b border-amber-100 bg-gradient-to-r from-amber-50/50 to-transparent">
              <div class="flex items-center justify-between">
                <div class="flex items-center gap-2.5">
                  <div class="w-9 h-9 rounded-full bg-gradient-to-br from-amber-400 to-orange-500 flex items-center justify-center shadow-sm">
                    <img src="https://ik.imagekit.io/blockster/blockster-icon.png" alt="BUX" class="w-5 h-5" />
                  </div>
                  <div>
                    <h2 class="text-base font-haas_medium_65 text-gray-900">BUX Pool</h2>
                    <p class="text-[11px] text-gray-400">Earn from BUX bets</p>
                  </div>
                </div>
                <div class="text-right">
                  <div class="text-[11px] text-gray-400">Your LP</div>
                  <div class="text-sm font-haas_medium_65 text-gray-900"><%= format_lp(@lp_balances.bbux) %> BUX-LP</div>
                </div>
              </div>
              <!-- Pool stats inline -->
              <div class="flex items-center gap-4 mt-3 pt-2.5 border-t border-amber-100/60">
                <div>
                  <div class="text-[10px] text-gray-400 uppercase tracking-wide">Pool Balance</div>
                  <div class="text-sm font-haas_medium_65 text-gray-900">
                    <%= if @pool_loading, do: "...", else: "#{format_tvl(get_vault_stat(@pool_stats, "bux", "totalBalance"))} BUX" %>
                  </div>
                </div>
                <div class="w-px h-6 bg-gray-200"></div>
                <div>
                  <div class="text-[10px] text-gray-400 uppercase tracking-wide">BUX-LP Price</div>
                  <div class="text-sm font-haas_medium_65 text-gray-900">
                    <%= if @pool_loading, do: "...", else: "#{format_price(get_vault_stat(@pool_stats, "bux", "lpPrice"))} BUX" %>
                  </div>
                </div>
              </div>
            </div>

            <!-- Tabs -->
            <div class="flex border-b border-gray-100">
              <button
                type="button"
                phx-click="switch_bux_tab"
                phx-value-tab="deposit"
                class={"flex-1 py-2.5 text-center text-sm font-haas_medium_65 transition-all cursor-pointer #{if @bux_tab == :deposit, do: "text-gray-900 border-b-2 border-gray-900", else: "text-gray-400 hover:text-gray-600"}"}
              >
                Deposit
              </button>
              <button
                type="button"
                phx-click="switch_bux_tab"
                phx-value-tab="withdraw"
                class={"flex-1 py-2.5 text-center text-sm font-haas_medium_65 transition-all cursor-pointer #{if @bux_tab == :withdraw, do: "text-gray-900 border-b-2 border-gray-900", else: "text-gray-400 hover:text-gray-600"}"}
              >
                Withdraw
              </button>
            </div>

            <!-- Content -->
            <div class="p-5">
              <%= if @bux_tab == :deposit do %>
                <.pool_input
                  amount={@bux_amount}
                  token="BUX"
                  balance={@balances["BUX"]}
                  on_change="update_bux_amount"
                  on_max="set_max_bux"
                  label="Deposit BUX"
                  balance_label="Balance"
                />
                <.output_preview
                  amount={@bux_amount}
                  lp_price={get_vault_stat(@pool_stats, "bux", "lpPrice")}
                  lp_token="BUX-LP"
                  action="receive"
                />
                <button
                  type="button"
                  phx-click="deposit_bux"
                  disabled={@bux_processing || !valid_amount?(@bux_amount) || !@current_user}
                  class="w-full mt-4 py-3 rounded-xl font-haas_medium_65 text-sm transition-all cursor-pointer disabled:opacity-40 disabled:cursor-not-allowed bg-gray-900 text-white hover:bg-gray-800"
                >
                  <%= if @bux_processing, do: "Processing...", else: "Deposit BUX" %>
                </button>
              <% else %>
                <.pool_input
                  amount={@bux_amount}
                  token="BUX-LP"
                  balance={@lp_balances.bbux}
                  on_change="update_bux_amount"
                  on_max="set_max_bux"
                  label="Withdraw BUX-LP"
                  balance_label="LP Balance"
                />
                <.output_preview
                  amount={@bux_amount}
                  lp_price={get_vault_stat(@pool_stats, "bux", "lpPrice")}
                  lp_token="BUX"
                  action="receive"
                  multiply={true}
                />
                <button
                  type="button"
                  phx-click="withdraw_bux"
                  disabled={@bux_processing || !valid_amount?(@bux_amount) || !@current_user}
                  class="w-full mt-4 py-3 rounded-xl font-haas_medium_65 text-sm transition-all cursor-pointer disabled:opacity-40 disabled:cursor-not-allowed bg-gray-900 text-white hover:bg-gray-800"
                >
                  <%= if @bux_processing, do: "Processing...", else: "Withdraw BUX" %>
                </button>
              <% end %>

              <!-- Pool Share -->
              <%= if @lp_balances.bbux > 0 do %>
                <div class="mt-3 pt-3 border-t border-gray-100 flex items-center justify-between text-[11px] text-gray-400">
                  <span>Pool share</span>
                  <span class="font-haas_medium_65 text-gray-600"><%= pool_share(@lp_balances.bbux, get_vault_stat(@pool_stats, "bux", "lpSupply")) %></span>
                </div>
              <% end %>
            </div>
          </div>
        </div>

        <!-- Connect Wallet Prompt -->
        <%= unless @current_user do %>
          <div class="mt-6 bg-white rounded-2xl shadow-sm border border-gray-200 p-6 text-center">
            <p class="text-sm text-gray-500 mb-3 font-haas_roman_55">Connect your wallet to deposit or withdraw liquidity</p>
            <button
              type="button"
              phx-click="show_wallet_selector"
              class="px-6 py-2.5 bg-gray-900 text-white rounded-xl font-haas_medium_65 text-sm hover:bg-gray-800 transition-all cursor-pointer"
            >
              Connect Wallet
            </button>
          </div>
        <% end %>

        <!-- How It Works -->
        <div class="mt-8 sm:mt-10">
          <h3 class="text-sm font-haas_medium_65 text-gray-900 mb-3">How it works</h3>
          <div class="grid grid-cols-1 sm:grid-cols-3 gap-3">
            <div class="bg-white rounded-xl border border-gray-200 p-4">
              <div class="w-7 h-7 rounded-lg bg-gray-100 flex items-center justify-center mb-2.5">
                <span class="text-sm">1</span>
              </div>
              <h4 class="text-sm font-haas_medium_65 text-gray-900 mb-1">Deposit</h4>
              <p class="text-xs text-gray-500 font-haas_roman_55">Add SOL or BUX to the pool and receive LP tokens (SOL-LP or BUX-LP) representing your share.</p>
            </div>
            <div class="bg-white rounded-xl border border-gray-200 p-4">
              <div class="w-7 h-7 rounded-lg bg-gray-100 flex items-center justify-center mb-2.5">
                <span class="text-sm">2</span>
              </div>
              <h4 class="text-sm font-haas_medium_65 text-gray-900 mb-1">Earn</h4>
              <p class="text-xs text-gray-500 font-haas_roman_55">When players bet and lose, the pool grows. Your LP tokens increase in value over time.</p>
            </div>
            <div class="bg-white rounded-xl border border-gray-200 p-4">
              <div class="w-7 h-7 rounded-lg bg-gray-100 flex items-center justify-center mb-2.5">
                <span class="text-sm">3</span>
              </div>
              <h4 class="text-sm font-haas_medium_65 text-gray-900 mb-1">Withdraw</h4>
              <p class="text-xs text-gray-500 font-haas_roman_55">Burn your LP tokens anytime to receive your share of the pool, including accumulated profits.</p>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ── Function Components ──

  defp stat_card(assigns) do
    assigns = assign_new(assigns, :loading, fn -> false end)

    ~H"""
    <div class="bg-white rounded-xl border border-gray-200 p-3 sm:p-4">
      <div class="text-[11px] text-gray-400 font-haas_roman_55 mb-1"><%= @label %></div>
      <%= if @loading do %>
        <div class="h-6 w-16 bg-gray-100 rounded animate-pulse"></div>
      <% else %>
        <div class="flex items-baseline gap-1">
          <span class="text-lg sm:text-xl font-haas_bold_75 text-gray-900"><%= @value %></span>
          <span class="text-[10px] text-gray-400"><%= @suffix %></span>
        </div>
      <% end %>
    </div>
    """
  end

  defp pool_input(assigns) do
    ~H"""
    <div>
      <label class="block text-xs font-haas_medium_65 text-gray-500 mb-1.5"><%= @label %></label>
      <div class="relative">
        <input
          type="number"
          value={@amount}
          phx-keyup={@on_change}
          phx-debounce="100"
          min="0"
          step="any"
          placeholder="0.00"
          class="w-full bg-gray-50 border border-gray-200 rounded-xl pl-4 pr-24 py-3 text-gray-900 text-base font-haas_medium_65 focus:outline-none focus:border-gray-400 focus:ring-1 focus:ring-gray-400 transition-all [appearance:textfield] [&::-webkit-outer-spin-button]:appearance-none [&::-webkit-inner-spin-button]:appearance-none"
        />
        <div class="absolute right-2 top-1/2 -translate-y-1/2 flex items-center gap-1.5">
          <button type="button" phx-click={@on_max} class="px-2 py-1 bg-gray-200 text-gray-600 rounded text-xs font-medium hover:bg-gray-300 transition-all cursor-pointer">MAX</button>
          <span class="text-sm font-haas_medium_65 text-gray-400 min-w-[32px] text-right"><%= @token %></span>
        </div>
      </div>
      <div class="mt-1.5 text-[11px] text-gray-400">
        <span><%= @balance_label %>: <%= format_balance(@balance) %> <%= @token %></span>
      </div>
    </div>
    """
  end

  defp output_preview(assigns) do
    assigns = assign_new(assigns, :multiply, fn -> false end)

    ~H"""
    <div class="mt-3 bg-gray-50 rounded-lg px-3 py-2.5 flex items-center justify-between">
      <span class="text-xs text-gray-400">You'll <%= @action %></span>
      <span class="text-sm font-haas_medium_65 text-gray-700">
        ≈ <%= estimate_output(@amount, @lp_price, @multiply) %> <%= @lp_token %>
      </span>
    </div>
    """
  end

  # ── Private Helpers ──

  defp handle_pool_action(socket, vault_type, action) do
    amount_key = if vault_type == "sol", do: :sol_amount, else: :bux_amount
    processing_key = if vault_type == "sol", do: :sol_processing, else: :bux_processing
    raw_amount = Map.get(socket.assigns, amount_key, "")

    cond do
      !socket.assigns[:current_user] ->
        {:noreply, put_flash(socket, :error, "Connect your wallet first")}

      !valid_amount?(raw_amount) ->
        {:noreply, put_flash(socket, :error, "Enter a valid amount")}

      true ->
        amount = parse_amount(raw_amount)
        wallet = socket.assigns.wallet_address
        fee_payer_mode = BuxMinter.fee_payer_mode_for_user(socket.assigns.current_user)

        socket = assign(socket, processing_key, true)

        socket =
          start_async(socket, :build_tx, fn ->
            result =
              case action do
                :deposit ->
                  BuxMinter.build_deposit_tx(wallet, amount, vault_type,
                    fee_payer_mode: fee_payer_mode
                  )

                :withdraw ->
                  BuxMinter.build_withdraw_tx(wallet, amount, vault_type,
                    fee_payer_mode: fee_payer_mode
                  )
              end

            case result do
              {:ok, tx} -> {:ok, %{transaction: tx, vault_type: vault_type, action: action}}
              error -> error
            end
          end)

        {:noreply, socket}
    end
  end

  defp sync_lp_balances(user_id, wallet_address) do
    Task.start(fn ->
      with {:ok, bsol} <- BuxMinter.get_lp_balance(wallet_address, "sol"),
           {:ok, bbux} <- BuxMinter.get_lp_balance(wallet_address, "bux") do
        EngagementTracker.update_user_bsol_balance(user_id, wallet_address, bsol)
        EngagementTracker.update_user_bbux_balance(user_id, wallet_address, bbux)
      end
    end)
  end

  defp valid_amount?(amount) when is_binary(amount) do
    case Float.parse(amount) do
      {val, _} -> val > 0
      :error -> false
    end
  end

  defp valid_amount?(_), do: false

  defp parse_amount(amount) when is_binary(amount) do
    case Float.parse(amount) do
      {val, _} -> val
      :error -> 0.0
    end
  end

  defp parse_amount(_), do: 0.0

  defp format_max(val) when is_float(val) and val > 0, do: :erlang.float_to_binary(val, decimals: 4)
  defp format_max(val) when is_integer(val) and val > 0, do: Integer.to_string(val)
  defp format_max(_), do: "0"

  defp format_balance(val) when is_float(val) and val >= 1000, do: "#{:erlang.float_to_binary(val / 1000, decimals: 2)}k"
  defp format_balance(val) when is_float(val) and val >= 1, do: :erlang.float_to_binary(val, decimals: 2)
  defp format_balance(val) when is_float(val) and val > 0, do: :erlang.float_to_binary(val, decimals: 4)
  defp format_balance(val) when is_integer(val), do: Integer.to_string(val)
  defp format_balance(_), do: "0"

  defp format_lp(val) when is_float(val) and val >= 1000, do: "#{:erlang.float_to_binary(val / 1000, decimals: 2)}k"
  defp format_lp(val) when is_float(val) and val > 0, do: :erlang.float_to_binary(val, decimals: 4)
  defp format_lp(val) when is_integer(val), do: Integer.to_string(val)
  defp format_lp(_), do: "0"

  defp format_tvl(val) when is_number(val) and val >= 1_000_000, do: "#{:erlang.float_to_binary(val / 1_000_000, decimals: 2)}M"
  defp format_tvl(val) when is_number(val) and val >= 1000, do: "#{:erlang.float_to_binary(val / 1000, decimals: 2)}k"
  defp format_tvl(val) when is_number(val) and val > 0, do: :erlang.float_to_binary(val / 1.0, decimals: 2)
  defp format_tvl(_), do: "0"

  defp format_price(val) when is_number(val) and val > 0, do: :erlang.float_to_binary(val / 1.0, decimals: 4)
  defp format_price(_), do: "1.0000"

  defp get_vault_stat(nil, _vault, _key), do: 0
  defp get_vault_stat(stats, vault, key) do
    case stats[vault] do
      nil -> 0
      vault_stats -> vault_stats[key] || 0
    end
  end

  defp estimate_output(amount, lp_price, multiply) do
    case {parse_amount(amount), lp_price} do
      {a, p} when a > 0 and is_number(p) and p > 0 ->
        result = if multiply, do: a * p, else: a / p
        :erlang.float_to_binary(result, decimals: 4)

      _ ->
        "0"
    end
  end

  defp pool_share(user_lp, total_supply) when is_number(user_lp) and is_number(total_supply) and total_supply > 0 do
    pct = user_lp / total_supply * 100

    cond do
      pct >= 1 -> "#{:erlang.float_to_binary(pct, decimals: 2)}%"
      pct > 0 -> "<1%"
      true -> "0%"
    end
  end

  defp pool_share(_, _), do: "0%"
end
