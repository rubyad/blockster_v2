defmodule BlocksterV2Web.PoolDetailLive do
  @moduledoc """
  Individual vault page — deposit/withdraw, chart, stats, activity.
  Parameterized by vault_type ("sol" or "bux").
  Stub for Phase 1; fully implemented in Phase 2.
  """
  use BlocksterV2Web, :live_view
  require Logger

  alias BlocksterV2.EngagementTracker
  alias BlocksterV2.BuxMinter
  alias BlocksterV2.CoinFlipGame
  alias BlocksterV2.LpPriceHistory
  alias BlocksterV2.PoolPositions

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

  # Two payload shapes: the phx-keyup (%{"value" => ...}) fires per-keystroke
  # from the <input>; the phx-change on the wrapping <form> (POOL-01 fix)
  # fires with the form's name map (%{"amount" => ...}).
  def handle_event("update_amount", %{"value" => val}, socket),
    do: {:noreply, assign(socket, amount: val)}

  def handle_event("update_amount", %{"amount" => val}, socket),
    do: {:noreply, assign(socket, amount: val)}

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

  def handle_event("set_half", _params, socket) do
    vault_type = socket.assigns.vault_type
    max =
      case {socket.assigns.tab, vault_type} do
        {:deposit, "sol"} -> socket.assigns.balances["SOL"]
        {:deposit, "bux"} -> socket.assigns.balances["BUX"]
        {:withdraw, "sol"} -> socket.assigns.lp_balances.bsol
        {:withdraw, "bux"} -> socket.assigns.lp_balances.bbux
      end

    half = if is_number(max) and max > 0, do: max / 2, else: 0
    {:noreply, assign(socket, amount: format_max(half))}
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

    # Update the user's cost-basis row. Uses pre-tx lp_price from socket
    # assigns — accurate within sub-second of the tx landing on chain (close
    # enough for ACB accounting). For deposit, amount_raw is the token
    # amount deposited. For withdraw, amount_raw is the LP burned.
    if socket.assigns[:current_user] && amount_raw > 0 do
      user_id = socket.assigns.current_user.id
      lp_price = socket.assigns[:lp_price]

      if is_number(lp_price) and lp_price > 0 do
        case action do
          "deposit" -> PoolPositions.record_deposit(user_id, vault_type, amount_raw, lp_price)
          "withdraw" -> PoolPositions.record_withdraw(user_id, vault_type, amount_raw, lp_price)
          _ -> :ok
        end
      end
    end

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

    # POOL-03/06: also persist lp_price to the socket so tx_confirmed/3
    # can read it. render/1 does its own recompute inside the function-
    # component assigns map, but that local assign never reaches
    # socket.assigns outside the render — so before this commit
    # socket.assigns[:lp_price] was always nil at tx_confirmed time and
    # PoolPositions.record_withdraw/4 silently no-op'd on the
    # `is_number(lp_price) and lp_price > 0` guard.
    {:noreply, assign(socket, pool_stats: stats, pool_loading: false, lp_price: lp_price)}
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
    tvl_val = get_vault_stat(assigns.pool_stats, assigns.vault_type, "netBalance")
    tvl = if is_number(tvl_val) and tvl_val > 0, do: tvl_val, else: get_vault_stat(assigns.pool_stats, assigns.vault_type, "totalBalance")

    token = if is_sol, do: "SOL", else: "BUX"
    lp_token = if is_sol, do: "SOL-LP", else: "BUX-LP"
    user_lp = if is_sol, do: assigns.lp_balances.bsol, else: assigns.lp_balances.bbux

    deposit_token = if assigns.tab == :deposit, do: token, else: lp_token
    deposit_balance =
      if assigns.tab == :deposit do
        assigns.balances[token]
      else
        user_lp
      end

    output_token = if assigns.tab == :deposit, do: lp_token, else: token
    multiply = assigns.tab == :withdraw

    current_share_pct = compute_share_pct(user_lp, lp_supply)
    new_share_pct = compute_new_share_pct(user_lp, lp_supply, lp_price, assigns.amount, assigns.tab)

    est_apy = if is_sol, do: "14.2", else: "18.7"
    display_token = if is_sol, do: "SOL", else: "BUX"
    bets_24h = assigns.period_stats.total

    # Cost basis + unrealized P/L. Seed pre-existing LP holders on first
    # render so they see real numbers instead of dashes (treats "now" as
    # basis — accurate from next tx forward).
    position_summary =
      cond do
        is_nil(assigns[:current_user]) ->
          nil

        not is_number(lp_price) or lp_price <= 0 ->
          nil

        true ->
          user_id = assigns.current_user.id
          PoolPositions.seed_if_missing(user_id, assigns.vault_type, user_lp, lp_price)
          PoolPositions.summary(user_id, assigns.vault_type, user_lp, lp_price)
      end

    assigns =
      assigns
      |> assign(is_sol: is_sol)
      |> assign(lp_price: lp_price)
      |> assign(lp_supply: lp_supply)
      |> assign(tvl: tvl)
      |> assign(token: token)
      |> assign(lp_token: lp_token)
      |> assign(user_lp: user_lp)
      |> assign(deposit_token: deposit_token)
      |> assign(deposit_balance: deposit_balance)
      |> assign(output_token: output_token)
      |> assign(multiply: multiply)
      |> assign(current_share_pct: current_share_pct)
      |> assign(new_share_pct: new_share_pct)
      |> assign(est_apy: est_apy)
      |> assign(display_token: display_token)
      |> assign(bets_24h: bets_24h)
      |> assign(position_summary: position_summary)

    ~H"""
    <div id="pool-detail-page" phx-hook="PoolHook" class="min-h-screen bg-[#fafaf9]">
      <BlocksterV2Web.DesignSystem.header
        current_user={@current_user}
        active="pool"
        display_token={@display_token}
        bux_balance={Map.get(assigns, :bux_balance, 0)}
        token_balances={Map.get(assigns, :token_balances, %{})}
        cart_item_count={Map.get(assigns, :cart_item_count, 0)}
        unread_notification_count={Map.get(assigns, :unread_notification_count, 0)}
        notification_dropdown_open={Map.get(assigns, :notification_dropdown_open, false)}
        recent_notifications={Map.get(assigns, :recent_notifications, [])}
        search_query={Map.get(assigns, :search_query, "")}
        search_results={Map.get(assigns, :search_results, [])}
        show_search_results={Map.get(assigns, :show_search_results, false)}
        show_search_modal={Map.get(assigns, :show_search_modal, false)}
        connecting={Map.get(assigns, :connecting, false)}
        show_why_earn_bux={true}
  announcement_banner={assigns[:announcement_banner]}
      />

      <%!-- ══════════════════════════════════════════════════════
           POOL BANNER — full-bleed gradient hero
      ══════════════════════════════════════════════════════ --%>
      <section class="relative text-white overflow-hidden" style={banner_bg_style(@is_sol)}>
        <div class="absolute inset-0 opacity-[0.10] pointer-events-none" style="background-image: radial-gradient(circle at 30% 30%, white 1.5px, transparent 1.5px); background-size: 32px 32px;"></div>
        <div class="absolute top-0 right-0 w-1/2 h-full pointer-events-none" style="background: radial-gradient(ellipse at top right, rgba(255,255,255,0.15), transparent 60%);"></div>

        <div class="max-w-[1280px] mx-auto px-4 py-5 md:px-6 md:py-12 relative">
          <%!-- Breadcrumb --%>
          <div class="mb-4 md:mb-8 flex items-center gap-2 text-[11px] text-white/75">
            <.link navigate={~p"/pool"} class="hover:text-white transition-colors cursor-pointer">Pool</.link>
            <span>/</span>
            <span class="text-white"><%= @token %> Pool</span>
          </div>

          <div class="grid grid-cols-12 gap-4 md:gap-8 items-start">
            <%!-- Left 7 col: identity + hero LP price + stats row --%>
            <div class="col-span-12 md:col-span-7">
              <div class="flex items-center gap-3 md:gap-5 mb-4 md:mb-6">
                <div class="w-12 h-12 md:w-20 md:h-20 rounded-xl md:rounded-2xl bg-black grid place-items-center ring-1 ring-white/25 shadow-2xl overflow-hidden shrink-0">
                  <img
                    src={if @token == "SOL", do: "https://ik.imagekit.io/blockster/solana-sol-logo.png", else: "https://ik.imagekit.io/blockster/blockster-icon.png"}
                    alt={@token}
                    class="w-7 h-7 md:w-12 md:h-12 rounded-full"
                  />
                </div>
                <div>
                  <div class="flex items-center gap-2 mb-0.5 md:mb-1">
                    <span class="text-[9px] md:text-[10px] uppercase tracking-[0.16em] text-white font-bold">Bankroll Vault</span>
                    <span class="inline-flex items-center gap-1 bg-[#CAFC00] text-black px-2 py-0.5 rounded-full text-[9px] md:text-[10px] font-bold">
                      <span class="w-1.5 h-1.5 rounded-full bg-black animate-pulse"></span>
                      Live
                    </span>
                  </div>
                  <h1 class="font-bold text-[32px] md:text-[68px] tracking-[-0.025em] leading-[0.95]"><%= @token %> Pool</h1>
                </div>
              </div>

              <%!-- LP price hero --%>
              <div class="mb-4 md:mb-7">
                <div class="text-[9px] md:text-[10px] uppercase tracking-[0.14em] text-white font-bold mb-1 md:mb-2">Current LP price</div>
                <div class="flex items-baseline gap-2 md:gap-3 flex-wrap">
                  <span class="font-mono font-bold text-[38px] md:text-[64px] text-white leading-none tracking-tight tabular-nums">
                    <%= if @pool_loading, do: "—", else: format_lp_price(@lp_price) %>
                  </span>
                  <span class="text-[14px] md:text-[18px] text-white/90"><%= @token %></span>
                  <span
                    :if={@chart_price_stats && @chart_price_stats.change_pct}
                    class={"ml-1 md:ml-2 inline-flex items-center gap-1 text-[12px] md:text-[14px] font-mono font-bold " <> if(@chart_price_stats.change_pct >= 0, do: "text-[#CAFC00]", else: "text-red-200")}
                  >
                    <%= change_arrow(@chart_price_stats.change_pct) %> <%= format_change_pct(@chart_price_stats.change_pct) %>
                  </span>
                  <span class="text-[10px] md:text-[11px] text-white/85 font-mono">24h</span>
                </div>
              </div>

              <%!-- Stats row — on mobile render as a 2×2 grid of dark pills so
                   numbers have strong contrast against the bright vault color.
                   Desktop keeps the airy divider layout. --%>
              <div class="md:hidden grid grid-cols-2 gap-2">
                <div class="bg-black/25 backdrop-blur ring-1 ring-white/15 rounded-xl px-3 py-2">
                  <div class="font-mono font-bold text-[18px] text-white leading-none tabular-nums"><%= format_tvl(@tvl) %></div>
                  <div class="text-[9px] uppercase tracking-[0.14em] text-white/80 mt-1">TVL · <%= @token %></div>
                </div>
                <div class="bg-black/25 backdrop-blur ring-1 ring-white/15 rounded-xl px-3 py-2">
                  <div class="font-mono font-bold text-[18px] text-white leading-none tabular-nums"><%= format_number(@lp_supply) %></div>
                  <div class="text-[9px] uppercase tracking-[0.14em] text-white/80 mt-1"><%= @lp_token %> supply</div>
                </div>
                <div class="bg-black/25 backdrop-blur ring-1 ring-white/15 rounded-xl px-3 py-2">
                  <div class="font-mono font-bold text-[18px] text-[#CAFC00] leading-none tabular-nums"><%= @est_apy %><span class="text-[12px]">%</span></div>
                  <div class="text-[9px] uppercase tracking-[0.14em] text-white/80 mt-1">Est. APY</div>
                </div>
                <div class="bg-black/25 backdrop-blur ring-1 ring-white/15 rounded-xl px-3 py-2">
                  <div class="font-mono font-bold text-[18px] text-white leading-none tabular-nums"><%= @bets_24h %></div>
                  <div class="text-[9px] uppercase tracking-[0.14em] text-white/80 mt-1">Bets · 24h</div>
                </div>
              </div>
              <div class="hidden md:flex items-center flex-wrap gap-x-8 gap-y-3">
                <div>
                  <div class="font-mono font-bold text-[24px] text-white leading-none tabular-nums"><%= format_tvl(@tvl) %></div>
                  <div class="text-[10px] uppercase tracking-[0.14em] text-white/90 mt-1.5">TVL · <%= @token %></div>
                </div>
                <div class="w-px h-10 bg-white/30"></div>
                <div>
                  <div class="font-mono font-bold text-[24px] text-white leading-none tabular-nums"><%= format_number(@lp_supply) %></div>
                  <div class="text-[10px] uppercase tracking-[0.14em] text-white/90 mt-1.5"><%= @lp_token %> supply</div>
                </div>
                <div class="w-px h-10 bg-white/30"></div>
                <div>
                  <div class="font-mono font-bold text-[24px] text-[#CAFC00] leading-none tabular-nums"><%= @est_apy %><span class="text-[14px]">%</span></div>
                  <div class="text-[10px] uppercase tracking-[0.14em] text-white/90 mt-1.5">Est. APY</div>
                </div>
                <div class="w-px h-10 bg-white/30"></div>
                <div>
                  <div class="font-mono font-bold text-[24px] text-white leading-none tabular-nums"><%= @bets_24h %></div>
                  <div class="text-[10px] uppercase tracking-[0.14em] text-white/90 mt-1.5">Bets · 24h</div>
                </div>
              </div>
            </div>

            <%!-- Right 5 col: your position card --%>
            <div class="col-span-12 md:col-span-5 mt-3 md:mt-2">
              <div class="bg-white/95 backdrop-blur rounded-2xl p-3.5 md:p-5 ring-1 ring-black/5 shadow-2xl">
                <div class="flex items-center justify-between mb-2 md:mb-3">
                  <div class="text-[10px] font-bold uppercase tracking-[0.14em] text-neutral-500">Your position</div>
                  <span class="text-[9px] font-mono text-neutral-500">
                    <%= if @current_share_pct > 0, do: :erlang.float_to_binary(@current_share_pct, decimals: 2) <> "% pool share", else: "— pool share" %>
                  </span>
                </div>
                <div class="flex items-baseline gap-2 mb-0.5 md:mb-1">
                  <span class="font-mono font-bold text-[26px] md:text-[36px] text-[#141414] leading-none tabular-nums"><%= format_lp(@user_lp) %></span>
                  <span class="text-[11px] md:text-[12px] text-neutral-500"><%= @lp_token %></span>
                </div>
                <div class="text-[10px] md:text-[11px] text-neutral-500 font-mono mb-3 md:mb-4">
                  <%= position_value_line(@user_lp, @lp_price, @token) %>
                </div>
                <div class="grid grid-cols-3 gap-2 pt-2.5 md:pt-3 border-t border-neutral-200">
                  <div>
                    <div class="text-[9px] uppercase tracking-[0.12em] text-neutral-500">Cost basis</div>
                    <div class="font-mono font-bold text-[13px] md:text-[14px] text-[#141414] whitespace-nowrap overflow-hidden text-ellipsis">
                      <%= format_cost_basis(@position_summary, @token) %>
                    </div>
                  </div>
                  <div>
                    <div class="text-[9px] uppercase tracking-[0.12em] text-neutral-500">Unrealized P/L</div>
                    <div class={"font-mono font-bold text-[13px] md:text-[14px] whitespace-nowrap overflow-hidden text-ellipsis " <> pnl_color(@position_summary)}>
                      <%= format_pnl(@position_summary, @token) %>
                    </div>
                  </div>
                  <div>
                    <div class="text-[9px] uppercase tracking-[0.12em] text-neutral-500">Realized P/L</div>
                    <div class={"font-mono font-bold text-[13px] md:text-[14px] whitespace-nowrap overflow-hidden text-ellipsis " <> realized_color(@position_summary)}>
                      <%= format_realized_gain(@position_summary, @token) %>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      <%!-- ══════════════════════════════════════════════════════
           TWO-COLUMN: ORDER FORM + CHART/STATS/ACTIVITY
      ══════════════════════════════════════════════════════ --%>
      <main class="max-w-[1280px] mx-auto px-6">
        <section class="pt-10 pb-12">
          <div class="grid grid-cols-12 gap-6 items-start">

            <%!-- LEFT: sticky order form --%>
            <div class="col-span-12 lg:col-span-4 lg:sticky lg:top-[84px] self-start">
              <div class="bg-white rounded-2xl border border-neutral-200/70 shadow-[0_1px_3px_rgba(0,0,0,0.04)] overflow-hidden">
                <%!-- Deposit / Withdraw tabs --%>
                <div class="p-2">
                  <div class="flex bg-neutral-100 rounded-full p-1 gap-1">
                    <% deposit_tab_class = if @tab == :deposit, do: "bg-white text-[#141414] shadow-[0_2px_8px_rgba(0,0,0,0.06)]", else: "text-neutral-500 hover:text-[#141414]" %>
                    <% withdraw_tab_class = if @tab == :withdraw, do: "bg-white text-[#141414] shadow-[0_2px_8px_rgba(0,0,0,0.06)]", else: "text-neutral-500 hover:text-[#141414]" %>
                    <button
                      type="button"
                      phx-click="switch_tab"
                      phx-value-tab="deposit"
                      class={"flex-1 py-3 text-center font-bold text-[13px] rounded-full transition-all cursor-pointer " <> deposit_tab_class}
                    >
                      Deposit
                    </button>
                    <button
                      type="button"
                      phx-click="switch_tab"
                      phx-value-tab="withdraw"
                      class={"flex-1 py-3 text-center font-bold text-[13px] rounded-full transition-all cursor-pointer " <> withdraw_tab_class}
                    >
                      Withdraw
                    </button>
                  </div>
                </div>

                <%!-- Your wallet balances --%>
                <div class="px-5 pt-2 pb-4 border-b border-neutral-100">
                  <div class="text-[10px] font-bold uppercase tracking-[0.14em] text-neutral-500 mb-3">Your wallet</div>
                  <div class="grid grid-cols-2 gap-3">
                    <div class="bg-neutral-50 border border-neutral-200/70 rounded-xl p-3">
                      <div class="flex items-center gap-2 mb-1">
                        <div class="w-4 h-4 rounded-full grid place-items-center" style={wallet_icon_bg(@is_sol)}>
                          <span class="font-bold text-[6px] text-black"><%= @token %></span>
                        </div>
                        <span class="text-[10px] text-neutral-500"><%= @token %></span>
                      </div>
                      <div class="font-mono font-bold text-[16px] text-[#141414] tabular-nums"><%= format_balance(@balances[@token]) %></div>
                    </div>
                    <div class="bg-neutral-50 border border-neutral-200/70 rounded-xl p-3">
                      <div class="flex items-center gap-2 mb-1">
                        <div class="w-4 h-4 rounded-full grid place-items-center opacity-60" style={wallet_icon_bg(@is_sol)}>
                          <span class="font-bold text-[6px] text-black"><%= @token %></span>
                        </div>
                        <span class="text-[10px] text-neutral-500"><%= @lp_token %></span>
                      </div>
                      <div class="font-mono font-bold text-[16px] text-[#141414] tabular-nums"><%= format_lp(@user_lp) %></div>
                    </div>
                  </div>
                </div>

                <%!-- LP Price line --%>
                <div class="px-5 pt-4 pb-2 flex items-center justify-between">
                  <div class="text-[10px] font-bold uppercase tracking-[0.14em] text-neutral-500"><%= @lp_token %> Price</div>
                  <div class="font-mono text-[12px] text-[#141414]">1 <%= @lp_token %> = <span class="font-bold"><%= format_lp_price(@lp_price) %> <%= @token %></span></div>
                </div>

                <%!-- Amount input --%>
                <div class="px-5 pt-3">
                  <div class="flex items-center justify-between mb-2">
                    <div class="text-[10px] font-bold uppercase tracking-[0.14em] text-neutral-500">
                      <%= if @tab == :deposit, do: "Deposit amount", else: "Withdraw amount" %>
                    </div>
                    <div class="flex items-center gap-1.5">
                      <button
                        type="button"
                        phx-click="set_half"
                        class="px-2.5 py-1 rounded-full bg-neutral-100 border border-neutral-200 font-mono text-[10px] font-bold text-neutral-500 hover:text-[#141414] hover:border-[#141414] hover:bg-white transition-colors cursor-pointer"
                      >
                        ½
                      </button>
                      <button
                        type="button"
                        phx-click="set_max"
                        class="px-2.5 py-1 rounded-full bg-[#064e3b] border border-[#064e3b] font-mono text-[10px] font-bold text-white hover:opacity-90 transition-opacity cursor-pointer"
                      >
                        MAX <%= format_max_display(@deposit_balance) %>
                      </button>
                    </div>
                  </div>
                  <%!-- POOL-01: phx-keyup alone on a bare <input> doesn't fire the
                       LiveView event in LV 1.x without a form wrapper. Wrap so the
                       phx-change on the form is the primary binding and phx-keyup
                       stays as the instant-feedback secondary. --%>
                  <form phx-change="update_amount" class="bg-neutral-50 border border-neutral-200 rounded-2xl px-5 py-4 flex items-center gap-3">
                    <input
                      type="text"
                      inputmode="decimal"
                      name="amount"
                      value={@amount}
                      phx-keyup="update_amount"
                      phx-debounce="100"
                      placeholder="0.00"
                      autocomplete="off"
                      class="flex-1 bg-transparent border-0 outline-none font-mono font-bold text-[28px] text-[#141414] tracking-tight w-full focus:outline-none"
                    />
                    <div class="text-[14px] text-neutral-500 shrink-0"><%= @deposit_token %></div>
                  </form>
                  <div class="flex items-center justify-between mt-2 text-[10px] font-mono text-neutral-400">
                    <span>Balance · <%= format_balance(@deposit_balance) %> <%= @deposit_token %></span>
                    <span><%= estimate_dollar_value(@amount, @deposit_token) %></span>
                  </div>
                </div>

                <%!-- Output preview --%>
                <div class="px-5 pt-5">
                  <% preview_bg = if @is_sol, do: "bg-[#00DC82]/8 border-[#00DC82]/25", else: "bg-[#CAFC00]/10 border-[#CAFC00]/40" %>
                  <% preview_label = if @is_sol, do: "text-[#064e3b]", else: "text-[#4d6800]" %>
                  <% preview_muted = if @is_sol, do: "text-[#064e3b]/70", else: "text-[#4d6800]/70" %>
                  <% preview_border = if @is_sol, do: "border-[#00DC82]/20", else: "border-[#CAFC00]/30" %>
                  <div class={"rounded-2xl p-4 border " <> preview_bg}>
                    <div class="flex items-center justify-between mb-1.5">
                      <div class={"text-[10px] font-bold uppercase tracking-[0.14em] " <> preview_label}>You receive ≈</div>
                      <div class={"text-[10px] font-mono " <> preview_muted}>est.</div>
                    </div>
                    <div class="flex items-baseline gap-2">
                      <span class={"font-mono font-bold text-[28px] leading-none tabular-nums " <> preview_label}><%= estimate_output(@amount, @lp_price, @multiply) %></span>
                      <span class={"text-[12px] " <> preview_muted}><%= @output_token %></span>
                    </div>
                    <div :if={@tab == :deposit} class={"mt-2 pt-2 border-t flex items-center justify-between text-[10px] font-mono " <> preview_border <> " " <> preview_muted}>
                      <span>New pool share</span>
                      <span class={"font-bold " <> preview_label}><%= format_pool_share(@new_share_pct) %> <%= share_delta_label(@current_share_pct, @new_share_pct) %></span>
                    </div>
                  </div>
                </div>

                <%!-- Submit --%>
                <div class="p-5 pt-4">
                  <%= if @current_user do %>
                    <button
                      type="button"
                      phx-click={if @tab == :deposit, do: "deposit", else: "withdraw"}
                      disabled={@processing || !valid_amount?(@amount)}
                      class="w-full bg-[#0a0a0a] text-white py-3.5 rounded-2xl text-[14px] font-bold hover:bg-[#1a1a22] transition-colors flex items-center justify-center gap-2 disabled:opacity-40 disabled:cursor-not-allowed cursor-pointer"
                    >
                      <%= cond do %>
                        <% @processing -> %>
                          Processing...
                        <% @tab == :deposit -> %>
                          <%= "Deposit " <> format_submit_amount(@amount) <> " " <> @token %>
                          <svg class="w-4 h-4" viewBox="0 0 20 20" fill="none"><path d="M3 10h12m0 0l-4-4m4 4l-4 4" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>
                        <% true -> %>
                          <%= "Withdraw " <> format_submit_amount(@amount) <> " " <> @lp_token %>
                          <svg class="w-4 h-4" viewBox="0 0 20 20" fill="none"><path d="M3 10h12m0 0l-4-4m4 4l-4 4" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>
                      <% end %>
                    </button>
                  <% else %>
                    <button
                      type="button"
                      phx-click="show_wallet_selector"
                      class="w-full bg-[#0a0a0a] text-white py-3.5 rounded-2xl text-[14px] font-bold hover:bg-[#1a1a22] transition-colors cursor-pointer"
                    >
                      Connect Wallet
                    </button>
                  <% end %>
                  <div class="mt-2.5 text-[10px] text-neutral-500 text-center">No lockup · Instant withdraw · Solana fee ~0.0001 SOL</div>
                </div>
              </div>

              <%!-- Helpful info card --%>
              <div class="mt-4 bg-neutral-50 border border-neutral-200/70 rounded-2xl p-5">
                <div class="text-[10px] font-bold uppercase tracking-[0.14em] text-neutral-500 mb-2">How earnings work</div>
                <p class="text-[11px] text-neutral-600 leading-[1.55] mb-3">
                  Every losing bet adds to the <%= @token %> vault. Every winning bet pays out from it. Over time, the sub-1% house edge grows the LP price.
                </p>
                <div class="flex flex-wrap items-center gap-x-4 gap-y-1 text-[11px] font-mono">
                  <.link navigate={~p"/docs/pools"} class="text-neutral-600 hover:text-[#141414] transition-colors cursor-pointer">How pools work ↗</.link>
                  <.link navigate={~p"/docs/smart-contracts"} class="text-neutral-600 hover:text-[#141414] transition-colors cursor-pointer">Smart contracts ↗</.link>
                  <.link navigate={~p"/docs/security-audit"} class="text-neutral-600 hover:text-[#141414] transition-colors cursor-pointer">Security audit ↗</.link>
                </div>
              </div>

              <%= if @current_user && @user_lp > 0 do %>
                <div class="mt-4 bg-white border border-neutral-200/70 rounded-2xl p-4">
                  <div class="flex items-center justify-between text-[11px] text-neutral-500">
                    <span>Pool share</span>
                    <span class="font-bold text-[#141414]"><%= format_pool_share(@current_share_pct) %></span>
                  </div>
                </div>
              <% end %>
            </div>

            <%!-- RIGHT: chart + stats + activity --%>
            <div class="col-span-12 lg:col-span-8 space-y-6">
              <.lp_price_chart
                vault_type={@vault_type}
                lp_price={@lp_price}
                lp_token={@lp_token}
                token={@token}
                timeframe={@timeframe}
                loading={@pool_loading}
                chart_price_stats={@chart_price_stats}
              />

              <.pool_stats_grid
                pool_stats={@pool_stats}
                loading={@pool_loading}
                vault_type={@vault_type}
                timeframe={@timeframe}
                period_stats={@period_stats}
              />

              <.activity_table
                activity_tab={@activity_tab}
                vault_type={@vault_type}
                activities={filter_activities(@activities, @activity_tab)}
              />
            </div>
          </div>
        </section>
      </main>

      <BlocksterV2Web.DesignSystem.footer />

      <.coin_flip_fairness_modal show={@show_fairness_modal} fairness_game={@fairness_game} />
    </div>
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
        fee_payer_mode = BuxMinter.fee_payer_mode_for_user(socket.assigns.current_user)

        socket = assign(socket, :processing, true)

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

  # Format helpers accept both integer and float. PubSub payloads
  # (e.g. `{:bux_balance_updated, 1_000}`) deliver integer balances, so
  # `is_float`-only guards used to silently skip the decimal branches and
  # render integers as "1000" instead of "1.00k". Coerce `val / 1.0`
  # inside every clause.
  defp format_max(val) when is_number(val) and val > 0,
    do: :erlang.float_to_binary(val / 1.0, decimals: 4)

  defp format_max(_), do: "0"

  defp format_balance(val) when is_number(val) and val >= 1000,
    do: "#{:erlang.float_to_binary(val / 1.0 / 1000, decimals: 2)}k"

  defp format_balance(val) when is_number(val) and val >= 1,
    do: :erlang.float_to_binary(val / 1.0, decimals: 2)

  defp format_balance(val) when is_number(val) and val > 0,
    do: :erlang.float_to_binary(val / 1.0, decimals: 4)

  defp format_balance(_), do: "0"

  defp format_lp(val) when is_number(val) and val >= 1000,
    do: "#{:erlang.float_to_binary(val / 1.0 / 1000, decimals: 2)}k"

  defp format_lp(val) when is_number(val) and val > 0,
    do: :erlang.float_to_binary(val / 1.0, decimals: 4)

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

  # ── Render helpers for redesigned template ──

  defp banner_bg_style(true),
    do: "background: linear-gradient(135deg, #00FFA3 0%, #00DC82 50%, #064e3b 130%);"

  defp banner_bg_style(false),
    do: "background: linear-gradient(135deg, #CAFC00 0%, #9ED600 50%, #4d6800 130%);"

  defp wallet_icon_bg(true), do: "background: linear-gradient(135deg, #00FFA3, #00DC82);"
  defp wallet_icon_bg(false), do: "background: linear-gradient(135deg, #CAFC00, #9ED600);"

  defp change_arrow(pct) when is_number(pct) and pct >= 0, do: "▲"
  defp change_arrow(_), do: "▼"

  defp format_max_display(val) when is_number(val) and val >= 1000 do
    "#{:erlang.float_to_binary(val / 1000, decimals: 1)}k"
  end

  defp format_max_display(val) when is_number(val) and val >= 1,
    do: :erlang.float_to_binary(val / 1.0, decimals: 2)

  defp format_max_display(val) when is_number(val) and val > 0,
    do: :erlang.float_to_binary(val / 1.0, decimals: 4)

  defp format_max_display(_), do: "0"

  defp format_submit_amount(amount) do
    val = parse_amount(amount)

    cond do
      val <= 0 -> "0"
      val >= 1 -> :erlang.float_to_binary(val / 1.0, decimals: 2)
      true -> :erlang.float_to_binary(val / 1.0, decimals: 4)
    end
  end

  defp estimate_dollar_value(amount, token) do
    val = parse_amount(amount)

    usd =
      case token do
        "SOL" -> val * 160.0
        "SOL-LP" -> val * 160.0
        "BUX" -> val * 0.01
        "BUX-LP" -> val * 0.01
        _ -> 0.0
      end

    cond do
      usd >= 1_000_000 -> "≈ $#{:erlang.float_to_binary(usd / 1_000_000, decimals: 2)}M"
      usd >= 1_000 -> "≈ $#{:erlang.float_to_binary(usd / 1_000, decimals: 2)}k"
      usd > 0 -> "≈ $#{:erlang.float_to_binary(usd, decimals: 2)}"
      true -> "≈ $0.00"
    end
  end

  defp format_cost_basis(%{cost_basis: tc}, token) when is_number(tc) and tc > 0 do
    "#{format_position_amount(tc, token)} #{token}"
  end

  defp format_cost_basis(_, _), do: "—"

  defp format_pnl(%{unrealized_pnl: pnl}, token) when is_number(pnl) do
    sign = cond do
      pnl > 0.0001 -> "+ "
      pnl < -0.0001 -> "− "
      true -> ""
    end

    "#{sign}#{format_position_amount(abs(pnl), token)} #{token}"
  end

  defp format_pnl(_, _), do: "—"

  defp format_realized_gain(%{realized_gain: gain}, token) when is_number(gain) do
    sign = cond do
      gain > 0.0001 -> "+ "
      gain < -0.0001 -> "− "
      true -> ""
    end

    "#{sign}#{format_position_amount(abs(gain), token)} #{token}"
  end

  defp format_realized_gain(_, _), do: "—"

  defp realized_color(%{realized_gain: gain}) when is_number(gain) do
    cond do
      gain > 0.0001 -> "text-[#16A34A]"
      gain < -0.0001 -> "text-[#DC2626]"
      true -> "text-[#141414]"
    end
  end

  defp realized_color(_), do: "text-[#141414]"

  defp pnl_color(%{unrealized_pnl: pnl}) when is_number(pnl) do
    cond do
      pnl > 0.0001 -> "text-[#15803d]"
      pnl < -0.0001 -> "text-[#b91c1c]"
      true -> "text-[#141414]"
    end
  end

  defp pnl_color(_), do: "text-[#141414]"

  defp format_position_amount(val, "SOL"), do: :erlang.float_to_binary(val / 1.0, decimals: 4)
  defp format_position_amount(val, "BUX"), do: :erlang.float_to_binary(val / 1.0, decimals: 2)
  defp format_position_amount(val, _), do: :erlang.float_to_binary(val / 1.0, decimals: 4)

  defp position_value_line(user_lp, lp_price, token) when is_number(user_lp) and user_lp > 0 and is_number(lp_price) and lp_price > 0 do
    worth = user_lp * lp_price

    usd =
      case token do
        "SOL" -> worth * 160.0
        "BUX" -> worth * 0.01
        _ -> 0.0
      end

    # SHOP/POOL: coerce to float before `:erlang.float_to_binary` — `worth`
    # can be an integer if `user_lp` and `lp_price` are both integer-typed
    # (never true today, but cheap insurance against PubSub integer payloads).
    worth_str =
      cond do
        worth >= 1000 -> "#{:erlang.float_to_binary(worth / 1.0 / 1000, decimals: 2)}k"
        worth >= 1 -> :erlang.float_to_binary(worth / 1.0, decimals: 3)
        true -> :erlang.float_to_binary(worth / 1.0, decimals: 4)
      end

    usd_str =
      cond do
        usd >= 1_000_000 -> "$#{:erlang.float_to_binary(usd / 1_000_000, decimals: 2)}M"
        usd >= 1_000 -> "$#{:erlang.float_to_binary(usd / 1_000, decimals: 2)}k"
        usd > 0 -> "$#{:erlang.float_to_binary(usd, decimals: 2)}"
        true -> "$0"
      end

    "≈ #{worth_str} #{token} · #{usd_str}"
  end

  defp position_value_line(_, _, _), do: "≈ —"

  defp compute_share_pct(user_lp, supply) when is_number(user_lp) and user_lp > 0 and is_number(supply) and supply > 0 do
    user_lp / supply * 100
  end

  defp compute_share_pct(_, _), do: 0.0

  defp compute_new_share_pct(user_lp, supply, lp_price, amount, :deposit) when is_number(supply) and supply > 0 and is_number(lp_price) and lp_price > 0 do
    a = parse_amount(amount)

    if a > 0 do
      new_lp = a / lp_price
      new_user = (user_lp || 0.0) + new_lp
      new_supply = supply + new_lp
      if new_supply > 0, do: new_user / new_supply * 100, else: 0.0
    else
      compute_share_pct(user_lp, supply)
    end
  end

  defp compute_new_share_pct(user_lp, supply, _lp_price, amount, :withdraw) when is_number(supply) and supply > 0 do
    a = parse_amount(amount)

    if a > 0 do
      burn = min(a, user_lp || 0.0)
      new_user = max((user_lp || 0.0) - burn, 0.0)
      new_supply = max(supply - burn, 0.0)
      if new_supply > 0, do: new_user / new_supply * 100, else: 0.0
    else
      compute_share_pct(user_lp, supply)
    end
  end

  defp compute_new_share_pct(user_lp, supply, _lp_price, _amount, _tab), do: compute_share_pct(user_lp, supply)

  defp format_pool_share(pct) when is_number(pct) and pct >= 1,
    do: "#{:erlang.float_to_binary(pct / 1.0, decimals: 2)}%"

  defp format_pool_share(pct) when is_number(pct) and pct > 0, do: "<1%"
  defp format_pool_share(_), do: "0%"

  defp share_delta_label(current, new) when is_number(current) and is_number(new) do
    delta = new - current

    cond do
      abs(delta) < 0.01 -> ""
      delta > 0 -> "(+#{:erlang.float_to_binary(delta / 1.0, decimals: 2)}%)"
      true -> "(#{:erlang.float_to_binary(delta / 1.0, decimals: 2)}%)"
    end
  end

  defp share_delta_label(_, _), do: ""
end
