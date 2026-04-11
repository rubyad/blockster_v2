defmodule BlocksterV2Web.PoolDetailLive.Legacy.PreRedesign do
  @moduledoc """
  Preserved pre-redesign PoolDetailLive module. Kept in the tree for reference
  during the Solana migration redesign release — not routed, not referenced
  by any live_session. Delete once the redesign is deployed.
  """
  use BlocksterV2Web, :live_view
  require Logger

  alias BlocksterV2.EngagementTracker
  alias BlocksterV2.BuxMinter
  alias BlocksterV2.CoinFlipGame
  alias BlocksterV2.LpPriceHistory

  import BlocksterV2Web.PoolComponents

  @valid_vault_types ~w(sol bux)

  @impl true
  def mount(%{"vault_type" => vault_type}, _session, socket) when vault_type in @valid_vault_types do
    current_user = socket.assigns[:current_user]

    socket =
      socket
      |> assign(vault_type: vault_type)
      |> assign(page_title: "#{String.upcase(vault_type)} Pool")
      |> assign(header_token: String.upcase(vault_type))
      |> assign(pool_stats: nil)
      |> assign(pool_loading: true)
      |> assign(tab: :deposit)
      |> assign(amount: "")
      |> assign(processing: false)
      |> assign(timeframe: "24H")
      |> assign(chart_price_stats: nil)
      |> assign(activity_tab: :all)
      |> assign(activities: [])
      |> assign(show_fairness_modal: false)
      |> assign(fairness_game: nil)
      |> assign(lp_balances: %{bsol: 0.0, bbux: 0.0})
      |> assign(balances: %{"SOL" => 0.0, "BUX" => 0.0})
      |> assign(period_stats: %{total: 0, wins: 0, volume: 0.0, payout: 0.0, profit: 0.0})

    socket =
      if current_user do
        wallet_address = current_user.wallet_address

        if wallet_address && connected?(socket) do
          Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "bux_balance:#{current_user.id}")
        end

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
        Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "pool_activity:#{vault_type}")
        Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "pool_chart:#{vault_type}")

        # Fetch period stats and recent bet activity from Mnesia
        vault_atom = String.to_existing_atom(vault_type)
        period_stats = CoinFlipGame.period_stats(vault_atom, timeframe_seconds("24H"))
        socket = assign(socket, period_stats: period_stats)

        bet_activities = CoinFlipGame.get_recent_games_by_vault(vault_atom, 50)
                         |> Enum.map(&format_activity/1)

        # Fetch recent deposit/withdraw activity from Mnesia
        lp_activities = load_pool_activities(vault_type)

        # Merge and sort by time (most recent first)
        activities = (bet_activities ++ lp_activities)
                     |> Enum.sort_by(& &1["_created_at"], :desc)
                     |> Enum.take(50)

        socket = assign(socket, activities: activities)
        socket = start_async(socket, :fetch_pool_stats, fn -> BuxMinter.get_pool_stats() end)

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

  def mount(_params, _session, socket) do
    {:ok, push_navigate(socket, to: ~p"/pool")}
  end

  # ── Balance Update Broadcasts ──

  @impl true
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

  def handle_info({:pool_activity, activity}, socket) do
    activities = [activity | socket.assigns.activities] |> Enum.take(50)
    {:noreply, assign(socket, activities: activities)}
  end

  def handle_info({:chart_point, point}, socket) do
    {:noreply, push_event(socket, "chart_update", point)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ── Tab Switching ──

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, tab: String.to_existing_atom(tab), amount: "", processing: false)}
  end

  # ── Chart Events ──

  def handle_event("request_chart_data", _params, socket) do
    push_chart_data(socket, socket.assigns.timeframe)
  end

  def handle_event("set_chart_timeframe", %{"timeframe" => timeframe}, socket) do
    push_chart_data(socket, timeframe)
  end

  # ── Activity Tab ──

  def handle_event("set_activity_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, activity_tab: String.to_existing_atom(tab))}
  end

  # ── Fairness Modal ──

  def handle_event("show_fairness_modal", %{"game-id" => game_id}, socket) do
    case CoinFlipGame.get_game(game_id) do
      {:ok, game} when game.status == :settled ->
        predictions_str = game.predictions |> Enum.map(&Atom.to_string/1) |> Enum.join(",")
        vault_type_str = if is_atom(game.vault_type), do: Atom.to_string(game.vault_type), else: to_string(game.vault_type)

        client_seed_input = "#{game.user_id}:#{game.bet_amount}:#{vault_type_str}:#{game.difficulty}:#{predictions_str}"
        client_seed = :crypto.hash(:sha256, client_seed_input) |> Base.encode16(case: :lower)

        combined_input = "#{game.server_seed}:#{client_seed}:#{game.nonce}"
        combined_seed = :crypto.hash(:sha256, combined_input)
        combined_seed_hex = Base.encode16(combined_seed, case: :lower)

        bytes = for i <- 0..(length(game.results) - 1), do: :binary.at(combined_seed, i)

        fairness_game = %{
          game_id: game_id,
          user_id: game.user_id,
          bet_amount: game.bet_amount,
          vault_type: vault_type_str,
          difficulty: game.difficulty,
          predictions_str: predictions_str,
          client_seed_input: client_seed_input,
          nonce: game.nonce,
          server_seed: game.server_seed,
          server_seed_hash: game.commitment_hash,
          client_seed: client_seed,
          combined_seed: combined_seed_hex,
          results: game.results,
          predictions: game.predictions,
          bytes: bytes,
          won: game.won,
          payout: game.payout
        }

        {:noreply, assign(socket, show_fairness_modal: true, fairness_game: fairness_game)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("hide_fairness_modal", _params, socket) do
    {:noreply, assign(socket, show_fairness_modal: false)}
  end

  def handle_event("stop_propagation", _params, socket) do
    {:noreply, socket}
  end

  # ── Amount Input ──

  def handle_event("update_amount", %{"value" => val}, socket) do
    {:noreply, assign(socket, amount: val)}
  end

  def handle_event("set_max", _params, socket) do
    vault_type = socket.assigns.vault_type
    max =
      case {socket.assigns.tab, vault_type} do
        {:deposit, "sol"} -> socket.assigns.balances["SOL"]
        {:deposit, "bux"} -> socket.assigns.balances["BUX"]
        {:withdraw, "sol"} -> socket.assigns.lp_balances.bsol
        {:withdraw, "bux"} -> socket.assigns.lp_balances.bbux
      end

    {:noreply, assign(socket, amount: format_max(max))}
  end

  # ── Deposit / Withdraw Actions ──

  def handle_event("deposit", _params, socket) do
    handle_pool_action(socket, socket.assigns.vault_type, :deposit)
  end

  def handle_event("withdraw", _params, socket) do
    handle_pool_action(socket, socket.assigns.vault_type, :withdraw)
  end

  # ── Transaction Callbacks (from PoolHook JS) ──

  def handle_event("tx_confirmed", %{"vault_type" => vault_type, "action" => action, "signature" => sig}, socket) do
    Logger.info("[PoolDetailLive] #{action} #{vault_type} confirmed: #{sig}")

    action_label = if action == "deposit", do: "Deposit", else: "Withdrawal"
    token_label = String.upcase(vault_type)

    # Persist and broadcast pool activity for deposit/withdraw
    amount_raw = parse_amount(socket.assigns.amount)
    wallet = socket.assigns[:wallet_address] || ""
    now = System.system_time(:second)

    record = {:pool_activities, System.unique_integer([:monotonic, :positive]), action, vault_type, amount_raw, truncate_wallet(wallet), now}
    :mnesia.dirty_write(record)

    decimals = if vault_type == "sol", do: 4, else: 2
    amount_formatted = format_amount(amount_raw, decimals)
    activity = %{
      "type" => action,
      "game" => nil,
      "bet" => nil,
      "payout" => nil,
      "profit" => "#{amount_formatted} #{token_label}",
      "wallet" => truncate_wallet(wallet),
      "full_wallet" => wallet,
      "tx_sig" => sig,
      "time" => "just now",
      "_created_at" => now
    }
    Phoenix.PubSub.broadcast(BlocksterV2.PubSub, "pool_activity:#{vault_type}", {:pool_activity, activity})

    socket =
      socket
      |> assign(processing: false, amount: "")
      |> put_flash(:info, "#{action_label} #{token_label} confirmed!")
      |> start_async(:fetch_pool_stats, fn -> BuxMinter.get_pool_stats() end)

    socket =
      if socket.assigns[:current_user] do
        user_id = socket.assigns.current_user.id
        wallet = socket.assigns.wallet_address

        start_async(socket, :sync_post_tx, fn ->
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

    {:noreply, socket}
  end

  def handle_event("tx_failed", %{"vault_type" => _vault_type, "error" => error}, socket) do
    {:noreply,
     socket
     |> assign(processing: false)
     |> put_flash(:error, error)}
  end

  # ── Async Handlers ──

  @impl true
  def handle_async(:fetch_pool_stats, {:ok, {:ok, stats}}, socket) do
    vault_type = socket.assigns.vault_type
    lp_price = get_vault_stat(stats, vault_type, "lpPrice")

    # Record price snapshot (broadcasts via PubSub for chart_update)
    LpPriceHistory.record(vault_type, lp_price)

    {:noreply, assign(socket, pool_stats: stats, pool_loading: false)}
  end

  def handle_async(:fetch_pool_stats, {:ok, {:error, _reason}}, socket) do
    {:noreply, assign(socket, pool_loading: false)}
  end

  def handle_async(:fetch_pool_stats, {:exit, _reason}, socket) do
    {:noreply, assign(socket, pool_loading: false)}
  end

  def handle_async(task, {:ok, %{sol: sol, bux: bux, bsol: bsol, bbux: bbux}}, socket)
      when task in [:sync_post_tx, :sync_on_mount] do
    {:noreply,
     socket
     |> assign(balances: %{"SOL" => sol, "BUX" => bux})
     |> assign(lp_balances: %{bsol: bsol, bbux: bbux})}
  end

  def handle_async(:sync_on_mount, _, socket), do: {:noreply, socket}
  def handle_async(:sync_post_tx, _, socket), do: {:noreply, socket}

  def handle_async(:build_tx, {:ok, {:ok, tx_data}}, socket) do
    %{transaction: tx, vault_type: vault_type, action: action} = tx_data
    event = if action == :deposit, do: "sign_deposit", else: "sign_withdraw"
    {:noreply, push_event(socket, event, %{transaction: tx, vault_type: vault_type})}
  end

  def handle_async(:build_tx, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(processing: false)
     |> put_flash(:error, "Failed to build transaction: #{inspect(reason)}")}
  end

  def handle_async(:build_tx, {:exit, _reason}, socket) do
    {:noreply, assign(socket, processing: false)}
  end

  # ── Render ──

  @impl true
  def render(assigns) do
    is_sol = assigns.vault_type == "sol"
    lp_price = get_vault_stat(assigns.pool_stats, assigns.vault_type, "lpPrice")
    lp_supply = get_vault_stat(assigns.pool_stats, assigns.vault_type, "lpSupply")

    token = if is_sol, do: "SOL", else: "BUX"
    lp_token = if is_sol, do: "SOL-LP", else: "BUX-LP"
    user_lp = if is_sol, do: assigns.lp_balances.bsol, else: assigns.lp_balances.bbux

    deposit_token = if assigns.tab == :deposit, do: token, else: lp_token
    deposit_balance = if assigns.tab == :deposit do
      assigns.balances[token]
    else
      user_lp
    end

    output_token = if assigns.tab == :deposit, do: lp_token, else: token
    multiply = assigns.tab == :withdraw

    assigns =
      assigns
      |> assign(is_sol: is_sol)
      |> assign(lp_price: lp_price)
      |> assign(lp_supply: lp_supply)
      |> assign(token: token)
      |> assign(lp_token: lp_token)
      |> assign(user_lp: user_lp)
      |> assign(deposit_token: deposit_token)
      |> assign(deposit_balance: deposit_balance)
      |> assign(output_token: output_token)
      |> assign(multiply: multiply)

    ~H"""
    <div id="pool-detail-page" class="min-h-screen bg-[#F5F6FB]" phx-hook="PoolHook">
      <div class="max-w-6xl mx-auto px-4 sm:px-6 pt-8 sm:pt-16 pb-16">
        <%!-- Header --%>
        <div class="mb-6 sm:mb-8">
          <.link navigate={~p"/pool"} class="inline-flex items-center gap-1.5 text-sm text-gray-400 hover:text-gray-700 font-haas_roman_55 mb-3 transition-colors cursor-pointer">
            <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
              <path stroke-linecap="round" stroke-linejoin="round" d="M15 19l-7-7 7-7" />
            </svg>
            Back to Pools
          </.link>
          <div class="flex items-center gap-3">
            <img
              src={if @is_sol, do: "https://ik.imagekit.io/blockster/solana-sol-logo.png", else: "https://ik.imagekit.io/blockster/blockster-icon.png"}
              alt={if @is_sol, do: "SOL", else: "BUX"}
              class="w-10 h-10 rounded-xl shadow-sm"
            />
            <h1 class="text-2xl sm:text-3xl font-haas_bold_75 text-gray-900 tracking-tight">
              <%= @token %> Pool
            </h1>
          </div>
        </div>

        <%!-- Two-Column Layout --%>
        <div class="flex flex-col lg:flex-row gap-5">
          <%!-- Left: Order Form --%>
          <div class="w-full lg:w-[380px] flex-shrink-0">
            <div class="bg-white rounded-2xl border border-gray-200 shadow-[0_1px_3px_rgba(0,0,0,0.04)] overflow-hidden sticky top-6">
              <%!-- Balances --%>
              <div class="px-5 pt-5 pb-4">
                <div class="text-xs text-gray-400 font-haas_roman_55 uppercase tracking-wider mb-2.5">Your Balances</div>
                <div class="space-y-2">
                  <div class="flex items-center justify-between bg-gray-50/80 rounded-lg px-3 py-2.5 border border-gray-100/80">
                    <div class="flex items-center gap-2">
                      <img
                        src={if @is_sol, do: "https://ik.imagekit.io/blockster/solana-sol-logo.png", else: "https://ik.imagekit.io/blockster/blockster-icon.png"}
                        alt={@token}
                        class="w-6 h-6 rounded-full"
                      />
                      <span class="text-sm font-haas_medium_65 text-gray-900 tabular-nums"><%= format_balance(@balances[@token]) %></span>
                      <span class="text-xs text-gray-400"><%= @token %></span>
                    </div>
                  </div>
                  <div class="flex items-center justify-between bg-gray-50/80 rounded-lg px-3 py-2.5 border border-gray-100/80">
                    <div class="flex items-center gap-2">
                      <img
                        src={if @is_sol, do: "https://ik.imagekit.io/blockster/solana-sol-logo.png", else: "https://ik.imagekit.io/blockster/blockster-icon.png"}
                        alt={@lp_token}
                        class="w-6 h-6 rounded-full opacity-60"
                      />
                      <span class="text-sm font-haas_medium_65 text-gray-900 tabular-nums"><%= format_lp(@user_lp) %></span>
                      <span class="text-xs text-gray-400"><%= @lp_token %></span>
                    </div>
                  </div>
                </div>
              </div>

              <%!-- Deposit / Withdraw Tabs --%>
              <div class="flex border-b border-gray-100 px-5">
                <button
                  type="button"
                  phx-click="switch_tab"
                  phx-value-tab="deposit"
                  class={"flex-1 pb-3 text-center text-sm font-haas_medium_65 transition-all cursor-pointer border-b-2 #{if @tab == :deposit, do: "text-gray-900 border-gray-900", else: "text-gray-400 border-transparent hover:text-gray-600"}"}
                >
                  Deposit
                </button>
                <button
                  type="button"
                  phx-click="switch_tab"
                  phx-value-tab="withdraw"
                  class={"flex-1 pb-3 text-center text-sm font-haas_medium_65 transition-all cursor-pointer border-b-2 #{if @tab == :withdraw, do: "text-gray-900 border-gray-900", else: "text-gray-400 border-transparent hover:text-gray-600"}"}
                >
                  Withdraw
                </button>
              </div>

              <%!-- Form Content --%>
              <div class="px-5 pt-4 pb-5">
                <%!-- LP Price --%>
                <div class="flex items-center justify-between text-xs text-gray-400 font-haas_roman_55 mb-3">
                  <span><%= @lp_token %> Price</span>
                  <span class="font-haas_medium_65 text-gray-700 tabular-nums">
                    <%= if @pool_loading, do: "...", else: "#{format_lp_price(@lp_price)} #{@token}" %>
                  </span>
                </div>

                <%!-- Amount Input --%>
                <div>
                  <label class="block text-xs font-haas_medium_65 text-gray-500 mb-1.5">
                    <%= if @tab == :deposit, do: "Deposit #{@token}", else: "Withdraw #{@lp_token}" %>
                  </label>
                  <div class="relative">
                    <input
                      type="text"
                      inputmode="decimal"
                      name="amount"
                      value={@amount}
                      phx-keyup="update_amount"
                      phx-debounce="100"
                      placeholder="0.00"
                      autocomplete="off"
                      class="w-full bg-gray-50 border border-gray-200 rounded-xl pl-4 pr-24 py-3 text-gray-900 text-base font-haas_medium_65 focus:outline-none focus:border-gray-400 focus:ring-1 focus:ring-gray-400 transition-all"
                    />
                    <div class="absolute right-2 top-1/2 -translate-y-1/2 flex items-center gap-1.5">
                      <button type="button" phx-click="set_max" class="px-2 py-1 bg-gray-200 text-gray-600 rounded text-xs font-medium hover:bg-gray-300 transition-all cursor-pointer">MAX</button>
                      <span class="text-sm font-haas_medium_65 text-gray-400 min-w-[32px] text-right"><%= @deposit_token %></span>
                    </div>
                  </div>
                  <div class="mt-1.5 text-[11px] text-gray-400">
                    <span><%= if @tab == :deposit, do: "Balance", else: "LP Balance" %>: <%= format_balance(@deposit_balance) %> <%= @deposit_token %></span>
                  </div>
                </div>

                <%!-- Output Preview --%>
                <div class="mt-3 bg-gray-50 rounded-lg px-3 py-2.5 flex items-center justify-between">
                  <span class="text-xs text-gray-400">You receive</span>
                  <span class="text-sm font-haas_medium_65 text-gray-700 tabular-nums">
                    ≈ <%= estimate_output(@amount, @lp_price, @multiply) %> <%= @output_token %>
                  </span>
                </div>

                <%!-- Exchange Rate --%>
                <div class="mt-2 text-center text-[11px] text-gray-400 font-haas_roman_55">
                  1 <%= @lp_token %> = <%= format_lp_price(@lp_price) %> <%= @token %>
                </div>

                <%!-- Submit Button --%>
                <%= if @current_user do %>
                  <button
                    type="button"
                    phx-click={if @tab == :deposit, do: "deposit", else: "withdraw"}
                    disabled={@processing || !valid_amount?(@amount)}
                    class="w-full mt-4 py-3.5 rounded-xl font-haas_medium_65 text-sm transition-all cursor-pointer disabled:opacity-40 disabled:cursor-not-allowed bg-gray-900 text-white hover:bg-gray-800"
                  >
                    <%= if @processing do %>
                      Processing...
                    <% else %>
                      <%= if @tab == :deposit, do: "Deposit #{@token}", else: "Withdraw #{@token}" %>
                    <% end %>
                  </button>
                <% else %>
                  <button
                    type="button"
                    phx-click="show_wallet_selector"
                    class="w-full mt-4 py-3.5 rounded-xl font-haas_medium_65 text-sm transition-all cursor-pointer bg-gray-900 text-white hover:bg-gray-800"
                  >
                    Connect Wallet
                  </button>
                <% end %>

                <%!-- Pool Share --%>
                <%= if @user_lp > 0 do %>
                  <div class="mt-3 pt-3 border-t border-gray-100 flex items-center justify-between text-[11px] text-gray-400">
                    <span>Pool share</span>
                    <span class="font-haas_medium_65 text-gray-600"><%= pool_share(@user_lp, @lp_supply) %></span>
                  </div>
                <% end %>
              </div>
            </div>
          </div>

          <%!-- Right: Chart + Stats + Activity (Phase 3-5 content) --%>
          <div class="flex-1 min-w-0 space-y-5">
            <%!-- LP Price Chart --%>
            <.lp_price_chart
              vault_type={@vault_type}
              lp_price={@lp_price}
              lp_token={@lp_token}
              token={@token}
              timeframe={@timeframe}
              loading={@pool_loading}
              chart_price_stats={@chart_price_stats}
            />

            <%!-- Stats Grid --%>
            <.pool_stats_grid
              pool_stats={@pool_stats}
              loading={@pool_loading}
              vault_type={@vault_type}
              timeframe={@timeframe}
              period_stats={@period_stats}
            />

            <%!-- Activity Table --%>
            <.activity_table
              activity_tab={@activity_tab}
              vault_type={@vault_type}
              activities={filter_activities(@activities, @activity_tab)}
            />
          </div>
        </div>
      </div>
    </div>

    <.coin_flip_fairness_modal show={@show_fairness_modal} fairness_game={@fairness_game} />
    """
  end

  # ── Private Helpers ──

  defp handle_pool_action(socket, vault_type, action) do
    raw_amount = socket.assigns.amount

    cond do
      !socket.assigns[:current_user] ->
        {:noreply, put_flash(socket, :error, "Connect your wallet first")}

      !valid_amount?(raw_amount) ->
        {:noreply, put_flash(socket, :error, "Enter a valid amount")}

      true ->
        amount = parse_amount(raw_amount)
        wallet = socket.assigns.wallet_address

        socket = assign(socket, :processing, true)

        socket =
          start_async(socket, :build_tx, fn ->
            result =
              case action do
                :deposit -> BuxMinter.build_deposit_tx(wallet, amount, vault_type)
                :withdraw -> BuxMinter.build_withdraw_tx(wallet, amount, vault_type)
              end

            case result do
              {:ok, tx} -> {:ok, %{transaction: tx, vault_type: vault_type, action: action}}
              error -> error
            end
          end)

        {:noreply, socket}
    end
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

  defp format_lp_price(val) when is_number(val) and val > 0, do: :erlang.float_to_binary(val / 1.0, decimals: 6)
  defp format_lp_price(_), do: "1.000000"

  defp estimate_output(amount, lp_price, multiply) do
    case {parse_amount(amount), lp_price} do
      {a, p} when a > 0 and is_number(p) and p > 0 ->
        result = if multiply, do: a * p, else: a / p
        :erlang.float_to_binary(result, decimals: 4)
      _ ->
        "0"
    end
  end

  defp format_activity(%{type: type, game: game, game_id: game_id, bet_amount: bet_amount, payout: payout, wallet: wallet, vault_type: vault_type, difficulty: difficulty, predictions: predictions, results: results, commitment_sig: commitment_sig, bet_sig: bet_sig, settlement_sig: settlement_sig, status: status, created_at: created_at}) do
    token = String.upcase(vault_type)
    decimals = if vault_type == "sol", do: 4, else: 2

    bet_str = format_amount(bet_amount, decimals)
    payout_str = if type == "win" and is_number(payout), do: format_amount(payout, decimals), else: nil

    profit = cond do
      type == "win" and is_number(bet_amount) and is_number(payout) ->
        "+#{format_amount(payout - bet_amount, decimals)} #{token}"
      type == "loss" and is_number(bet_amount) ->
        "-#{format_amount(bet_amount, decimals)} #{token}"
      true -> ""
    end

    %{
      "type" => type,
      "game" => game,
      "game_id" => game_id,
      "commitment_sig" => commitment_sig,
      "bet_sig" => bet_sig,
      "settlement_sig" => settlement_sig,
      "settled" => status == :settled,
      "bet" => "#{bet_str} #{token}",
      "payout" => if(payout_str, do: "#{payout_str} #{token}"),
      "profit" => profit,
      "multiplier" => format_multiplier(difficulty),
      "predictions" => predictions,
      "results" => results,
      "wallet" => truncate_wallet(wallet || ""),
      "full_wallet" => wallet,
      "time" => time_ago(created_at),
      "_created_at" => created_at || 0
    }
  end

  defp load_pool_activities(vault_type) do
    :mnesia.dirty_index_read(:pool_activities, vault_type, :vault_type)
    |> Enum.sort_by(fn record -> elem(record, 1) end, :desc)
    |> Enum.take(50)
    |> Enum.map(fn {:pool_activities, _id, type, _vt, amount, wallet, created_at} ->
      token = String.upcase(vault_type)
      decimals = if vault_type == "sol", do: 4, else: 2
      amount_str = format_amount(amount, decimals)

      %{
        "type" => type,
        "game" => nil,
        "bet" => nil,
        "payout" => nil,
        "profit" => "#{amount_str} #{token}",
        "wallet" => wallet,
        "full_wallet" => nil,
        "tx_sig" => nil,
        "time" => time_ago(created_at),
        "_created_at" => created_at || 0
      }
    end)
  rescue
    _ -> []
  catch
    :exit, _ -> []
  end

  defp format_amount(nil, _), do: "0"
  defp format_amount(amount, decimals) when is_number(amount) do
    abs_val = abs(amount / 1.0)
    d = cond do
      abs_val >= 1.0 -> decimals
      abs_val >= 0.01 -> max(decimals, 4)
      abs_val >= 0.0001 -> max(decimals, 6)
      abs_val > 0 -> max(decimals, 8)
      true -> decimals
    end
    :erlang.float_to_binary(amount / 1.0, decimals: d) |> String.trim_trailing("0") |> String.trim_trailing(".")
  end
  defp format_amount(_, _), do: "0"

  @multiplier_map %{
    -4 => "1.02x", -3 => "1.05x", -2 => "1.13x", -1 => "1.32x",
    1 => "1.98x", 2 => "3.96x", 3 => "7.92x", 4 => "15.84x", 5 => "31.68x"
  }

  defp format_multiplier(difficulty) when is_integer(difficulty), do: Map.get(@multiplier_map, difficulty)
  defp format_multiplier(_), do: nil

  defp truncate_wallet(wallet) when byte_size(wallet) > 8 do
    "#{String.slice(wallet, 0, 4)}..#{String.slice(wallet, -4, 4)}"
  end
  defp truncate_wallet(wallet), do: wallet

  defp time_ago(nil), do: ""
  defp time_ago(unix) when is_integer(unix) do
    diff = System.system_time(:second) - unix
    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86400)}d ago"
    end
  end

  defp push_chart_data(socket, timeframe) do
    vault_type = socket.assigns.vault_type
    data = LpPriceHistory.get_price_history(vault_type, timeframe)
    chart_stats = LpPriceHistory.compute_stats(data)

    vault_atom = String.to_existing_atom(vault_type)
    period_stats = CoinFlipGame.period_stats(vault_atom, timeframe_seconds(timeframe))

    {:noreply,
     socket
     |> assign(timeframe: timeframe, chart_price_stats: chart_stats, period_stats: period_stats)
     |> push_event("chart_data", %{data: data})}
  end

  @timeframe_seconds %{
    "1H" => 3600,
    "24H" => 86400,
    "7D" => 7 * 86400,
    "30D" => 30 * 86400,
    "All" => nil
  }

  defp timeframe_seconds(tf), do: Map.get(@timeframe_seconds, tf, 86400)

  defp filter_activities(activities, :all), do: activities
  defp filter_activities(activities, :wins), do: Enum.filter(activities, &(&1["type"] == "win"))
  defp filter_activities(activities, :losses), do: Enum.filter(activities, &(&1["type"] == "loss"))
  defp filter_activities(activities, :liquidity), do: Enum.filter(activities, &(&1["type"] in ["deposit", "withdraw"]))

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
