defmodule BlocksterV2Web.PoolIndexLive do
  use BlocksterV2Web, :live_view
  require Logger

  alias BlocksterV2.BuxMinter
  alias BlocksterV2.CoinFlipGame
  alias BlocksterV2.PriceTracker

  @impl true
  def mount(_params, _session, socket) do
    current_user = socket.assigns[:current_user]
    wallet_address = Map.get(socket.assigns, :wallet_address)

    socket =
      socket
      |> assign(page_title: "Liquidity Pools")
      |> assign(pool_stats: nil)
      |> assign(pool_loading: true)
      |> assign(activities: [])
      |> assign(user_sol_lp: 0.0)
      |> assign(user_bux_lp: 0.0)
      |> assign(sol_pool_share: 0.0)
      |> assign(bux_pool_share: 0.0)
      |> assign(sol_usd_price: fetch_sol_usd_price())

    socket =
      if connected?(socket) do
        Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "pool_activity:sol")
        Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "pool_activity:bux")

        socket
        |> start_async(:fetch_pool_stats, fn -> BuxMinter.get_pool_stats() end)
        |> start_async(:fetch_activities, fn -> load_cross_vault_activity() end)
        |> maybe_fetch_lp_balances(current_user, wallet_address)
      else
        socket
      end

    {:ok, socket}
  end

  defp maybe_fetch_lp_balances(socket, nil, _wallet), do: socket
  defp maybe_fetch_lp_balances(socket, _user, nil), do: socket
  defp maybe_fetch_lp_balances(socket, _user, ""), do: socket

  defp maybe_fetch_lp_balances(socket, _user, wallet) when is_binary(wallet) do
    start_async(socket, :fetch_user_lp_balances, fn ->
      sol_task = Task.async(fn -> BuxMinter.get_lp_balance(wallet, "sol") end)
      bux_task = Task.async(fn -> BuxMinter.get_lp_balance(wallet, "bux") end)
      {Task.await(sol_task, 8_000), Task.await(bux_task, 8_000)}
    end)
  end

  # ── Async handlers ───────────────────────────────────────────────────────────

  @impl true
  def handle_async(:fetch_pool_stats, {:ok, {:ok, stats}}, socket) do
    {sol_share, bux_share} = compute_pool_shares(stats, socket.assigns.user_sol_lp, socket.assigns.user_bux_lp)

    socket =
      socket
      |> assign(pool_stats: stats)
      |> assign(pool_loading: false)
      |> assign(sol_pool_share: sol_share)
      |> assign(bux_pool_share: bux_share)

    {:noreply, socket}
  end

  def handle_async(:fetch_pool_stats, {:ok, {:error, reason}}, socket) do
    Logger.warning("[PoolIndexLive] fetch_pool_stats error: #{inspect(reason)}")
    {:noreply, assign(socket, pool_loading: false)}
  end

  def handle_async(:fetch_pool_stats, {:exit, reason}, socket) do
    Logger.warning("[PoolIndexLive] fetch_pool_stats exit: #{inspect(reason)}")
    {:noreply, assign(socket, pool_loading: false)}
  end

  def handle_async(:fetch_activities, {:ok, activities}, socket) when is_list(activities) do
    {:noreply, assign(socket, activities: activities)}
  end

  def handle_async(:fetch_activities, _result, socket) do
    {:noreply, socket}
  end

  def handle_async(:fetch_user_lp_balances, {:ok, {{:ok, sol}, {:ok, bux}}}, socket) do
    sol_f = to_float(sol)
    bux_f = to_float(bux)

    {sol_share, bux_share} =
      compute_pool_shares(socket.assigns.pool_stats, sol_f, bux_f)

    socket =
      socket
      |> assign(user_sol_lp: sol_f)
      |> assign(user_bux_lp: bux_f)
      |> assign(sol_pool_share: sol_share)
      |> assign(bux_pool_share: bux_share)

    {:noreply, socket}
  end

  def handle_async(:fetch_user_lp_balances, _other, socket), do: {:noreply, socket}

  # ── Info handlers ────────────────────────────────────────────────────────────

  @impl true
  def handle_info({:pool_activity, activity}, socket) do
    merged = [activity | socket.assigns.activities] |> Enum.take(50)
    {:noreply, assign(socket, activities: merged)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ── Helpers ──────────────────────────────────────────────────────────────────

  defp load_cross_vault_activity do
    bet_sol = CoinFlipGame.get_recent_games_by_vault(:sol, 25) |> Enum.map(&format_bet_activity/1)
    bet_bux = CoinFlipGame.get_recent_games_by_vault(:bux, 25) |> Enum.map(&format_bet_activity/1)
    lp_sol = load_pool_activities("sol")
    lp_bux = load_pool_activities("bux")

    (bet_sol ++ bet_bux ++ lp_sol ++ lp_bux)
    |> Enum.sort_by(fn a -> Map.get(a, "_created_at", 0) end, :desc)
    |> Enum.take(50)
  rescue
    _ -> []
  catch
    :exit, _ -> []
  end

  defp load_pool_activities(vault_type) do
    :mnesia.dirty_index_read(:pool_activities, vault_type, :vault_type)
    |> Enum.sort_by(fn record -> elem(record, 1) end, :desc)
    |> Enum.take(25)
    |> Enum.map(fn {:pool_activities, _id, type, _vt, amount, wallet, created_at} ->
      %{
        "type" => type,
        "pool" => vault_type,
        "wallet" => wallet,
        "amount_raw" => amount,
        "amount" => format_lp_amount(amount, type, vault_type),
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

  defp format_bet_activity(%{type: type, game_id: game_id, bet_amount: bet, payout: payout, wallet: wallet, vault_type: vt, difficulty: difficulty, created_at: created_at, bet_sig: bet_sig, settlement_sig: settlement_sig}) do
    token = String.upcase(vt)
    decimals = if vt == "sol", do: 4, else: 0
    mult = format_multiplier(difficulty)

    amount_str =
      cond do
        type == "win" and is_number(bet) and is_number(payout) ->
          "− #{format_amount(payout - bet, decimals)} #{token}"

        type == "loss" and is_number(bet) ->
          "+ #{format_amount(bet, decimals)} #{token}"

        true ->
          ""
      end

    %{
      "type" => type,
      "multiplier" => mult,
      "pool" => vt,
      "wallet" => wallet,
      "wallet_short" => truncate_wallet(wallet || ""),
      "amount" => amount_str,
      "tx_sig" => settlement_sig || bet_sig,
      "time" => time_ago(created_at),
      "_created_at" => created_at || 0,
      "game_id" => game_id
    }
  end

  defp compute_pool_shares(nil, _sol_lp, _bux_lp), do: {0.0, 0.0}

  defp compute_pool_shares(stats, sol_lp, bux_lp) do
    sol_supply = get_in(stats, ["sol", "lpSupply"]) || 0
    bux_supply = get_in(stats, ["bux", "lpSupply"]) || 0

    sol_share =
      if is_number(sol_supply) and sol_supply > 0 and is_number(sol_lp) and sol_lp > 0 do
        sol_lp / sol_supply * 100
      else
        0.0
      end

    bux_share =
      if is_number(bux_supply) and bux_supply > 0 and is_number(bux_lp) and bux_lp > 0 do
        bux_lp / bux_supply * 100
      else
        0.0
      end

    {sol_share, bux_share}
  end

  defp to_float(v) when is_number(v), do: v / 1.0
  defp to_float(_), do: 0.0

  defp fetch_sol_usd_price do
    case PriceTracker.get_price("SOL") do
      {:ok, %{usd_price: price}} when is_number(price) and price > 0 -> price * 1.0
      _ -> 0.0
    end
  rescue
    _ -> 0.0
  end

  defp format_amount(val, decimals) when is_number(val) do
    :erlang.float_to_binary(val * 1.0, decimals: decimals)
  end

  defp format_amount(_, _), do: "0"

  defp format_lp_amount(amount, type, vault_type) do
    token = String.upcase(vault_type)
    decimals = if vault_type == "sol", do: 4, else: 0
    sign = if type == "withdraw", do: "−", else: "+"
    "#{sign} #{format_amount(amount, decimals)} #{token}"
  end

  defp format_multiplier(nil), do: ""
  defp format_multiplier(d) when is_integer(d) and d < 0 do
    # win-one: probability 1 − (0.5)^n, payout = 1/P
    flips = abs(d) + 1
    prob = 1.0 - :math.pow(0.5, flips)
    :erlang.float_to_binary(1.0 / prob, decimals: 2) <> "×"
  end
  defp format_multiplier(1), do: "1.98×"
  defp format_multiplier(d) when is_integer(d) and d > 1 do
    # win-all: payout = 2^n * 0.99
    :erlang.float_to_binary(:math.pow(2.0, d) * 0.99, decimals: 2) <> "×"
  end
  defp format_multiplier(_), do: ""

  defp truncate_wallet(nil), do: ""
  defp truncate_wallet(""), do: ""

  defp truncate_wallet(wallet) when is_binary(wallet) and byte_size(wallet) > 8 do
    head = String.slice(wallet, 0, 4)
    tail = String.slice(wallet, -4, 4)
    "#{head}…#{tail}"
  end

  defp truncate_wallet(wallet), do: wallet

  defp time_ago(nil), do: "—"

  defp time_ago(ts) when is_integer(ts) do
    now = System.system_time(:second)
    delta = max(now - ts, 0)

    cond do
      delta < 10 -> "just now"
      delta < 60 -> "#{delta}s ago"
      delta < 3_600 -> "#{div(delta, 60)}m ago"
      delta < 86_400 -> "#{div(delta, 3_600)}h ago"
      true -> "#{div(delta, 86_400)}d ago"
    end
  end

  defp time_ago(_), do: "—"

  # ── View-level formatting helpers ────────────────────────────────────────────

  defp vault_total_balance(stats, vault) when is_map(stats) do
    get_in(stats, [vault, "netBalance"]) || get_in(stats, [vault, "totalBalance"]) || 0.0
  end

  defp vault_total_balance(_, _), do: 0.0

  defp vault_lp_supply(stats, vault) when is_map(stats) do
    get_in(stats, [vault, "lpSupply"]) || 0.0
  end

  defp vault_lp_supply(_, _), do: 0.0

  defp vault_lp_price(stats, vault) when is_map(stats) do
    get_in(stats, [vault, "lpPrice"]) || 1.0
  end

  defp vault_lp_price(_, _), do: 1.0

  defp vault_total_bets(stats, vault) when is_map(stats) do
    get_in(stats, [vault, "totalBets"]) || 0
  end

  defp vault_total_bets(_, _), do: 0

  defp vault_total_volume(stats, vault) when is_map(stats) do
    get_in(stats, [vault, "totalVolume"]) || 0.0
  end

  defp vault_total_volume(_, _), do: 0.0

  defp vault_house_profit(stats, vault) when is_map(stats) do
    get_in(stats, [vault, "houseProfit"]) || 0.0
  end

  defp vault_house_profit(_, _), do: 0.0

  defp fmt_sol(val) when is_number(val) do
    cond do
      val >= 1_000 -> :erlang.float_to_binary(val / 1.0, decimals: 0)
      val >= 1 -> :erlang.float_to_binary(val / 1.0, decimals: 2)
      val > 0 -> :erlang.float_to_binary(val / 1.0, decimals: 4)
      true -> "0.00"
    end
  end

  defp fmt_sol(_), do: "0.00"

  defp fmt_bux_full(val) when is_number(val) do
    val |> round() |> commafy()
  end

  defp fmt_bux_full(_), do: "0"

  defp fmt_bux_signed(val) when is_number(val) do
    rounded = round(val)
    sign = if rounded >= 0, do: "+", else: "−"
    "#{sign}#{commafy(abs(rounded))}"
  end

  defp fmt_bux_signed(_), do: "+0"

  defp commafy(int) when is_integer(int) do
    int
    |> Integer.to_string()
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.map(&Enum.join/1)
    |> Enum.join(",")
    |> String.reverse()
  end

  defp fmt_usd(val) when is_number(val) and val > 0 do
    rounded = round(val)
    if rounded >= 1, do: "$" <> commafy(rounded), else: "$" <> :erlang.float_to_binary(val / 1.0, decimals: 2)
  end

  defp fmt_usd(_), do: "$0"

  defp fmt_price(val) when is_number(val) do
    :erlang.float_to_binary(val / 1.0, decimals: 4)
  end

  defp fmt_price(_), do: "1.0000"

  defp fmt_house_profit_sol(stats) when is_map(stats) do
    profit = vault_house_profit(stats, "sol")
    sign = if profit >= 0, do: "+", else: "−"
    "#{sign}#{fmt_sol(abs(profit))}"
  end

  defp fmt_house_profit_sol(_), do: "+0.00"

  defp profit_color_class(val) when is_number(val) and val < 0, do: "text-[#b91c1c]"
  defp profit_color_class(_), do: "text-[#15803d]"

  defp fmt_lifetime_return(lp_price) when is_number(lp_price) do
    pct = (lp_price - 1.0) * 100.0
    sign = if pct >= 0, do: "+", else: "−"
    "#{sign}#{:erlang.float_to_binary(abs(pct), decimals: 2)}%"
  end

  defp fmt_lifetime_return(_), do: "+0.00%"

  defp lifetime_return_text_class(lp_price, _default) when is_number(lp_price) and lp_price < 1.0,
    do: "text-[#dc2626]"

  defp lifetime_return_text_class(_, default), do: default

  defp activity_pool_dot_class("sol"), do: "bg-gradient-to-br from-[#00FFA3] to-[#00DC82]"
  defp activity_pool_dot_class("bux"), do: "bg-[#CAFC00]"
  defp activity_pool_dot_class(_), do: "bg-neutral-300"

  defp activity_pool_label("sol"), do: "SOL Pool"
  defp activity_pool_label("bux"), do: "BUX Pool"
  defp activity_pool_label(_), do: ""

  defp activity_badge_class("win"), do: "bg-[#22C55E]/15 text-[#15803d]"
  defp activity_badge_class("loss"), do: "bg-[#EF4444]/15 text-[#7f1d1d]"
  defp activity_badge_class("deposit"), do: "bg-[#7D00FF]/15 text-[#7D00FF]"
  defp activity_badge_class("withdraw"), do: "bg-[#facc15]/20 text-[#a16207]"
  defp activity_badge_class(_), do: "bg-neutral-100 text-neutral-500"

  defp activity_badge_label("win", mult), do: "Win #{mult}"
  defp activity_badge_label("loss", mult), do: "Loss #{mult}"
  defp activity_badge_label("deposit", _), do: "Deposit"
  defp activity_badge_label("withdraw", _), do: "Withdraw"
  defp activity_badge_label(type, _), do: String.capitalize(to_string(type || ""))

  defp activity_amount_class("win"), do: "text-[#EF4444]"
  defp activity_amount_class("loss"), do: "text-[#22C55E]"
  defp activity_amount_class("deposit"), do: "text-[#7D00FF]"
  defp activity_amount_class("withdraw"), do: "text-[#a16207]"
  defp activity_amount_class(_), do: "text-neutral-500"

  defp wallet_initials(nil), do: "—"
  defp wallet_initials(""), do: "—"

  defp wallet_initials(wallet) when is_binary(wallet) do
    String.slice(wallet, 0, 2)
  end

  defp short_sig(nil), do: ""

  defp short_sig(sig) when is_binary(sig) and byte_size(sig) > 4 do
    String.slice(sig, 0, 4) <> "…"
  end

  defp short_sig(sig), do: sig

  # ── Render ───────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-[#fafaf9]">
      <BlocksterV2Web.DesignSystem.header
        current_user={@current_user}
        active="pool"
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

      <main class="max-w-[1280px] mx-auto px-6">
        <%!-- ══════════════════════════════════════════════════════
             PAGE HEADER + STATS
        ══════════════════════════════════════════════════════ --%>
        <section class="pt-4 pb-5 md:pt-12 md:pb-10">
          <%!-- Mobile: compact header + one-line paragraph; single "How pools work ↗" link.
               Desktop keeps the full editorial treatment. --%>
          <div class="md:hidden mb-4">
            <div class="flex items-end justify-between gap-3 mb-2">
              <h1 class="text-[28px] leading-[0.96] font-bold tracking-[-0.022em] text-[#141414]">
                Liquidity Pools
              </h1>
              <.link navigate={~p"/docs/pools"} class="text-[10px] font-mono text-neutral-500 hover:text-[#141414] shrink-0 pb-1 cursor-pointer">
                How pools work ↗
              </.link>
            </div>
            <p class="text-[12px] leading-[1.45] text-neutral-600">
              Deposit SOL or BUX into the bankroll. Earn from every losing bet, withdraw anytime.
            </p>
          </div>

          <div class="hidden md:block">
            <BlocksterV2Web.DesignSystem.eyebrow class="mb-3">
              Earn from every bet · On-chain settlement
            </BlocksterV2Web.DesignSystem.eyebrow>
            <h1 class="text-[80px] mb-3 leading-[0.96] font-bold tracking-[-0.022em] text-[#141414]">
              Liquidity Pools
            </h1>
            <p class="text-[16px] leading-[1.5] text-neutral-600 max-w-[680px]">
              Deposit SOL or BUX into the bankroll. Earn from every losing bet, get paid in real time, withdraw anytime.
            </p>
            <div class="mt-3 flex items-center gap-4 text-[12px] font-mono">
              <.link navigate={~p"/docs/pools"} class="text-neutral-500 hover:text-[#141414] transition-colors cursor-pointer">How pools work ↗</.link>
              <.link navigate={~p"/docs/smart-contracts"} class="text-neutral-500 hover:text-[#141414] transition-colors cursor-pointer">Smart contracts ↗</.link>
              <.link navigate={~p"/docs/security-audit"} class="text-neutral-500 hover:text-[#141414] transition-colors cursor-pointer">Security audit ↗</.link>
            </div>
          </div>
        </section>

        <%!-- ══════════════════════════════════════════════════════
             TWO BIG VAULT CARDS
        ══════════════════════════════════════════════════════ --%>
        <section class="pb-6 md:pb-12">
          <div class="grid grid-cols-1 lg:grid-cols-2 gap-4 md:gap-6">
            <%!-- ───── SOL POOL ───── --%>
            <.link
              navigate={~p"/pool/sol"}
              class="group relative rounded-2xl md:rounded-3xl p-5 md:p-8 text-white overflow-hidden min-h-0 md:min-h-[420px] transition-all duration-300 md:hover:-translate-y-1 md:hover:shadow-[0_30px_60px_-20px_rgba(0,0,0,0.35)] block cursor-pointer"
              style="background: linear-gradient(135deg, #00FFA3 0%, #00DC82 50%, #064e3b 130%);"
            >
              <div class="absolute inset-0 opacity-[0.12] pointer-events-none" style="background-image: radial-gradient(circle at 30% 30%, white 1.5px, transparent 1.5px); background-size: 28px 28px;"></div>
              <div class="absolute -top-32 -right-32 w-96 h-96 bg-white/10 rounded-full blur-3xl pointer-events-none"></div>

              <div class="relative h-full flex flex-col">
                <%!-- Top: identity + live indicator --%>
                <div class="flex items-start justify-between mb-4 md:mb-10">
                  <div class="flex items-center gap-2.5 md:gap-3">
                    <div class="w-10 h-10 md:w-14 md:h-14 rounded-xl md:rounded-2xl bg-black grid place-items-center ring-1 ring-white/25 shadow-2xl overflow-hidden shrink-0">
                      <img src="https://ik.imagekit.io/blockster/solana-sol-logo.png" alt="SOL" class="w-6 h-6 md:w-9 md:h-9 rounded-full" />
                    </div>
                    <div>
                      <div class="text-[9px] md:text-[10px] uppercase tracking-[0.16em] text-white/80 font-bold mb-0.5">Vault</div>
                      <div class="font-bold text-[22px] md:text-[28px] tracking-tight leading-none">SOL Pool</div>
                    </div>
                  </div>
                  <div class="flex items-center gap-1.5 bg-black/25 backdrop-blur ring-1 ring-white/15 rounded-full px-2.5 py-1">
                    <span class="w-1.5 h-1.5 rounded-full bg-[#CAFC00] animate-pulse"></span>
                    <span class="text-[10px] font-bold uppercase tracking-[0.12em] text-white">Live</span>
                  </div>
                </div>

                <%!-- Big LP price --%>
                <div class="mb-1">
                  <div class="text-[9px] md:text-[10px] uppercase tracking-[0.14em] text-white/80 font-bold mb-0.5 md:mb-1">LP Price</div>
                  <div class="flex items-baseline gap-2 flex-wrap">
                    <span class="font-mono font-bold text-[34px] md:text-[48px] text-white leading-none tracking-tight tabular-nums">
                      {fmt_price(vault_lp_price(@pool_stats, "sol"))}
                    </span>
                    <span class="text-[12px] md:text-[14px] text-white/80">SOL</span>
                    <span class="text-[10px] text-white/70 font-mono">since launch</span>
                  </div>
                </div>

                <div class="mt-3 md:mt-4 mb-3 md:mb-6"></div>

                <%!-- Stats grid (2x2) --%>
                <div class="grid grid-cols-2 gap-2 md:gap-3 mb-3 md:mb-6">
                  <div class="bg-white/95 backdrop-blur rounded-xl p-2.5 md:p-3 ring-1 ring-black/5 shadow-sm">
                    <div class="text-[9px] uppercase tracking-[0.12em] text-neutral-500 mb-0.5 md:mb-1">TVL</div>
                    <div class="font-mono font-bold text-[14px] md:text-[16px] text-[#141414] tabular-nums truncate">
                      {fmt_sol(vault_total_balance(@pool_stats, "sol"))} SOL
                    </div>
                    <div class="text-[10px] text-neutral-500 font-mono">
                      ≈ {fmt_usd(vault_total_balance(@pool_stats, "sol") * @sol_usd_price)}
                    </div>
                  </div>
                  <div class="bg-white/95 backdrop-blur rounded-xl p-2.5 md:p-3 ring-1 ring-black/5 shadow-sm">
                    <div class="text-[9px] uppercase tracking-[0.12em] text-neutral-500 mb-0.5 md:mb-1">Supply</div>
                    <div class="font-mono font-bold text-[14px] md:text-[16px] text-[#141414] tabular-nums truncate">
                      {fmt_sol(vault_lp_supply(@pool_stats, "sol"))}
                    </div>
                    <div class="text-[10px] text-neutral-500 font-mono">SOL-LP</div>
                  </div>
                  <div class="bg-white/95 backdrop-blur rounded-xl p-2.5 md:p-3 ring-1 ring-black/5 shadow-sm">
                    <div class="text-[9px] uppercase tracking-[0.12em] text-neutral-500 mb-0.5 md:mb-1">Volume</div>
                    <div class="font-mono font-bold text-[14px] md:text-[16px] text-[#141414] tabular-nums truncate">
                      {fmt_sol(vault_total_volume(@pool_stats, "sol"))} SOL
                    </div>
                    <div class="text-[10px] text-neutral-500 font-mono">
                      {vault_total_bets(@pool_stats, "sol")} bets
                    </div>
                  </div>
                  <div class="bg-white/95 backdrop-blur rounded-xl p-2.5 md:p-3 ring-1 ring-black/5 shadow-sm">
                    <div class="text-[9px] uppercase tracking-[0.12em] text-neutral-500 mb-0.5 md:mb-1">Profit</div>
                    <div class={[
                      "font-mono font-bold text-[14px] md:text-[16px] tabular-nums truncate",
                      profit_color_class(vault_house_profit(@pool_stats, "sol"))
                    ]}>
                      {fmt_house_profit_sol(@pool_stats)} SOL
                    </div>
                    <div class="text-[10px] text-neutral-500 font-mono">house edge 1%</div>
                  </div>
                </div>

                <%!-- Your position --%>
                <div class="bg-white/95 backdrop-blur rounded-xl p-3 md:p-4 ring-1 ring-black/5 shadow-sm mb-3 md:mb-5">
                  <div class="flex items-center justify-between mb-1">
                    <div class="text-[9px] uppercase tracking-[0.12em] text-neutral-500 font-bold">Your position</div>
                    <div class="text-[9px] font-mono text-neutral-500">
                      {if(@sol_pool_share > 0, do: :erlang.float_to_binary(@sol_pool_share / 1.0, decimals: 2) <> "% pool share", else: "— pool share")}
                    </div>
                  </div>
                  <div class="flex items-baseline gap-2 flex-wrap">
                    <span class="font-mono font-bold text-[18px] md:text-[22px] text-[#141414] leading-none tabular-nums">
                      {fmt_sol(@user_sol_lp)}
                    </span>
                    <span class="text-[11px] text-neutral-500">SOL-LP</span>
                    <span class="text-[11px] font-mono text-neutral-500 ml-auto">
                      {if(@user_sol_lp > 0, do: "deposited", else: "no deposits yet")}
                    </span>
                  </div>
                </div>

                <%!-- CTA --%>
                <div class="mt-auto flex items-center gap-2">
                  <div class="flex-1 bg-white text-[#064e3b] px-4 py-3 md:px-5 md:py-3.5 rounded-full text-[13px] font-bold text-center group-hover:bg-[#CAFC00] group-hover:text-black transition-colors">
                    Enter SOL Pool →
                  </div>
                  <div class="text-[10px] font-mono text-white/80">
                    return <span class={["font-bold", lifetime_return_text_class(vault_lp_price(@pool_stats, "sol"), "text-white")]}>{fmt_lifetime_return(vault_lp_price(@pool_stats, "sol"))}</span>
                  </div>
                </div>
              </div>
            </.link>

            <%!-- ───── BUX POOL ───── --%>
            <.link
              navigate={~p"/pool/bux"}
              class="group relative rounded-2xl md:rounded-3xl p-5 md:p-8 text-black overflow-hidden min-h-0 md:min-h-[420px] transition-all duration-300 md:hover:-translate-y-1 md:hover:shadow-[0_30px_60px_-20px_rgba(0,0,0,0.35)] block cursor-pointer"
              style="background: linear-gradient(135deg, #CAFC00 0%, #9ED600 50%, #4d6800 130%);"
            >
              <div class="absolute inset-0 opacity-[0.15] pointer-events-none" style="background-image: radial-gradient(circle at 30% 30%, black 1px, transparent 1px); background-size: 28px 28px;"></div>
              <div class="absolute -top-32 -right-32 w-96 h-96 bg-black/10 rounded-full blur-3xl pointer-events-none"></div>

              <div class="relative h-full flex flex-col">
                <div class="flex items-start justify-between mb-4 md:mb-10">
                  <div class="flex items-center gap-2.5 md:gap-3">
                    <div class="w-10 h-10 md:w-14 md:h-14 rounded-xl md:rounded-2xl bg-black grid place-items-center ring-1 ring-black/30 shadow-2xl overflow-hidden shrink-0">
                      <img src="https://ik.imagekit.io/blockster/blockster-icon.png" alt="BUX" class="w-6 h-6 md:w-9 md:h-9 rounded-full" />
                    </div>
                    <div>
                      <div class="text-[9px] md:text-[10px] uppercase tracking-[0.16em] text-black/75 font-bold mb-0.5">Vault</div>
                      <div class="font-bold text-[22px] md:text-[28px] tracking-tight leading-none">BUX Pool</div>
                    </div>
                  </div>
                  <div class="flex items-center gap-1.5 bg-black/15 backdrop-blur ring-1 ring-black/15 rounded-full px-2.5 py-1">
                    <span class="w-1.5 h-1.5 rounded-full bg-[#0a0a0a] animate-pulse"></span>
                    <span class="text-[10px] font-bold uppercase tracking-[0.12em] text-black">Live</span>
                  </div>
                </div>

                <div class="mb-1">
                  <div class="text-[9px] md:text-[10px] uppercase tracking-[0.14em] text-black/75 font-bold mb-0.5 md:mb-1">LP Price</div>
                  <div class="flex items-baseline gap-2 flex-wrap">
                    <span class="font-mono font-bold text-[34px] md:text-[48px] text-black leading-none tracking-tight tabular-nums">
                      {fmt_price(vault_lp_price(@pool_stats, "bux"))}
                    </span>
                    <span class="text-[12px] md:text-[14px] text-black/75">BUX</span>
                    <span class="text-[10px] text-black/60 font-mono">since launch</span>
                  </div>
                </div>

                <div class="mt-3 md:mt-4 mb-3 md:mb-6"></div>

                <div class="grid grid-cols-2 gap-2 md:gap-3 mb-3 md:mb-6">
                  <div class="bg-white/95 backdrop-blur rounded-xl p-2.5 md:p-3 ring-1 ring-black/5 shadow-sm">
                    <div class="text-[9px] uppercase tracking-[0.12em] text-neutral-500 mb-0.5 md:mb-1">TVL</div>
                    <div class="font-mono font-bold text-[14px] md:text-[16px] text-[#141414] tabular-nums truncate">
                      {fmt_bux_full(vault_total_balance(@pool_stats, "bux"))} BUX
                    </div>
                    <div class="text-[10px] text-neutral-500 font-mono">in vault</div>
                  </div>
                  <div class="bg-white/95 backdrop-blur rounded-xl p-2.5 md:p-3 ring-1 ring-black/5 shadow-sm">
                    <div class="text-[9px] uppercase tracking-[0.12em] text-neutral-500 mb-0.5 md:mb-1">Supply</div>
                    <div class="font-mono font-bold text-[14px] md:text-[16px] text-[#141414] tabular-nums truncate">
                      {fmt_bux_full(vault_lp_supply(@pool_stats, "bux"))}
                    </div>
                    <div class="text-[10px] text-neutral-500 font-mono">BUX-LP</div>
                  </div>
                  <div class="bg-white/95 backdrop-blur rounded-xl p-2.5 md:p-3 ring-1 ring-black/5 shadow-sm">
                    <div class="text-[9px] uppercase tracking-[0.12em] text-neutral-500 mb-0.5 md:mb-1">Volume</div>
                    <div class="font-mono font-bold text-[14px] md:text-[16px] text-[#141414] tabular-nums truncate">
                      {fmt_bux_full(vault_total_volume(@pool_stats, "bux"))} BUX
                    </div>
                    <div class="text-[10px] text-neutral-500 font-mono">
                      {vault_total_bets(@pool_stats, "bux")} bets
                    </div>
                  </div>
                  <div class="bg-white/95 backdrop-blur rounded-xl p-2.5 md:p-3 ring-1 ring-black/5 shadow-sm">
                    <div class="text-[9px] uppercase tracking-[0.12em] text-neutral-500 mb-0.5 md:mb-1">Profit</div>
                    <div class={[
                      "font-mono font-bold text-[14px] md:text-[16px] tabular-nums truncate",
                      profit_color_class(vault_house_profit(@pool_stats, "bux"))
                    ]}>
                      {fmt_bux_signed(vault_house_profit(@pool_stats, "bux"))} BUX
                    </div>
                    <div class="text-[10px] text-neutral-500 font-mono">house edge 1%</div>
                  </div>
                </div>

                <div class="bg-white/95 backdrop-blur rounded-xl p-3 md:p-4 ring-1 ring-black/5 shadow-sm mb-3 md:mb-5">
                  <div class="flex items-center justify-between mb-1">
                    <div class="text-[9px] uppercase tracking-[0.12em] text-neutral-500 font-bold">Your position</div>
                    <div class="text-[9px] font-mono text-neutral-500">
                      {if(@bux_pool_share > 0, do: :erlang.float_to_binary(@bux_pool_share / 1.0, decimals: 2) <> "% pool share", else: "— pool share")}
                    </div>
                  </div>
                  <div class="flex items-baseline gap-2 flex-wrap">
                    <span class="font-mono font-bold text-[18px] md:text-[22px] text-[#141414] leading-none tabular-nums">
                      {fmt_bux_full(@user_bux_lp)}
                    </span>
                    <span class="text-[11px] text-neutral-500">BUX-LP</span>
                    <span class="text-[11px] font-mono text-neutral-500 ml-auto italic">
                      {if(@user_bux_lp > 0, do: "deposited", else: "no deposits yet")}
                    </span>
                  </div>
                </div>

                <div class="mt-auto flex items-center gap-2">
                  <div class="flex-1 bg-[#0a0a0a] text-[#CAFC00] px-4 py-3 md:px-5 md:py-3.5 rounded-full text-[13px] font-bold text-center group-hover:bg-white group-hover:text-black transition-colors">
                    Enter BUX Pool →
                  </div>
                  <div class="text-[10px] font-mono text-black/75">
                    return <span class={["font-bold", lifetime_return_text_class(vault_lp_price(@pool_stats, "bux"), "text-black")]}>{fmt_lifetime_return(vault_lp_price(@pool_stats, "bux"))}</span>
                  </div>
                </div>
              </div>
            </.link>
          </div>
        </section>

        <%!-- ══════════════════════════════════════════════════════
             HOW IT WORKS
        ══════════════════════════════════════════════════════ --%>
        <section class="py-12 border-t border-neutral-200/70">
          <div class="text-center mb-8">
            <BlocksterV2Web.DesignSystem.eyebrow class="mb-2">3 steps · No lockup</BlocksterV2Web.DesignSystem.eyebrow>
            <h2 class="text-[36px] md:text-[44px] font-bold tracking-[-0.022em] leading-[0.96] text-[#141414]">Become the house</h2>
          </div>
          <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
            <div class="bg-white rounded-2xl border border-neutral-200/70 p-7 shadow-[0_1px_3px_rgba(0,0,0,0.04)]">
              <div class="flex items-center gap-3 mb-4">
                <div class="w-9 h-9 rounded-full bg-[#0a0a0a] grid place-items-center text-[#CAFC00] font-bold text-[14px]">1</div>
                <div class="text-[10px] uppercase tracking-[0.14em] text-neutral-500 font-bold">Deposit</div>
              </div>
              <h3 class="font-bold text-[18px] text-[#141414] mb-2">Add liquidity to a vault</h3>
              <p class="text-[13px] text-neutral-600 leading-relaxed">
                Deposit SOL or BUX into the bankroll and receive LP tokens (SOL-LP or BUX-LP) representing your share of the pool. No lockup, no minimums.
              </p>
            </div>
            <div class="bg-white rounded-2xl border border-neutral-200/70 p-7 shadow-[0_1px_3px_rgba(0,0,0,0.04)]">
              <div class="flex items-center gap-3 mb-4">
                <div class="w-9 h-9 rounded-full bg-[#0a0a0a] grid place-items-center text-[#CAFC00] font-bold text-[14px]">2</div>
                <div class="text-[10px] uppercase tracking-[0.14em] text-neutral-500 font-bold">Earn</div>
              </div>
              <h3 class="font-bold text-[18px] text-[#141414] mb-2">Collect from every losing bet</h3>
              <p class="text-[13px] text-neutral-600 leading-relaxed">
                Players bet against the bankroll. When they lose, the LP price increases. When they win, it decreases by their payout. Over time, the sub-1% house edge accrues to LPs.
              </p>
            </div>
            <div class="bg-white rounded-2xl border border-neutral-200/70 p-7 shadow-[0_1px_3px_rgba(0,0,0,0.04)]">
              <div class="flex items-center gap-3 mb-4">
                <div class="w-9 h-9 rounded-full bg-[#0a0a0a] grid place-items-center text-[#CAFC00] font-bold text-[14px]">3</div>
                <div class="text-[10px] uppercase tracking-[0.14em] text-neutral-500 font-bold">Withdraw</div>
              </div>
              <h3 class="font-bold text-[18px] text-[#141414] mb-2">Cash out anytime</h3>
              <p class="text-[13px] text-neutral-600 leading-relaxed">
                Burn your LP tokens to redeem your share of the vault at the current price. Withdrawals settle in one Solana transaction. No queues, no waiting.
              </p>
            </div>
          </div>
        </section>

        <%!-- ══════════════════════════════════════════════════════
             POOL ACTIVITY
        ══════════════════════════════════════════════════════ --%>
        <section class="py-10 border-t border-neutral-200/70">
          <div class="flex items-baseline justify-between mb-5 flex-wrap gap-3">
            <div>
              <BlocksterV2Web.DesignSystem.eyebrow class="mb-1">Real-time</BlocksterV2Web.DesignSystem.eyebrow>
              <h2 class="text-[28px] font-bold tracking-[-0.018em] text-[#141414]">Pool activity</h2>
            </div>
            <div class="flex items-center gap-1.5 bg-white border border-neutral-200/70 rounded-full px-2.5 py-1">
              <span class="w-1.5 h-1.5 rounded-full bg-[#22C55E] animate-pulse"></span>
              <span class="text-[10px] uppercase tracking-[0.12em] text-neutral-500 font-bold">Live across both pools</span>
            </div>
          </div>

          <div class="bg-white rounded-2xl border border-neutral-200/70 shadow-[0_1px_3px_rgba(0,0,0,0.04)] overflow-hidden">
            <div class="hidden sm:grid grid-cols-[110px_140px_1fr_160px_110px_70px] px-5 py-3 bg-neutral-50/70 border-b border-neutral-100 text-[10px] uppercase tracking-[0.14em] text-neutral-500 font-bold">
              <div>Type</div>
              <div>Pool</div>
              <div>Wallet</div>
              <div class="text-right">Amount</div>
              <div class="text-right">Time</div>
              <div class="text-right">TX</div>
            </div>

            <%= if @activities == [] do %>
              <div class="px-5 py-10 text-center">
                <div class="text-[12px] text-neutral-500">
                  No pool activity yet. Place a bet on
                  <.link navigate={~p"/play"} class="text-[#141414] font-bold hover:underline">/play</.link>
                  to get the first event on the board.
                </div>
              </div>
            <% else %>
              <div class="divide-y divide-neutral-100">
                <%= for activity <- Enum.take(@activities, 6) do %>
                  <% pool = Map.get(activity, "pool", "") %>
                  <% type = Map.get(activity, "type", "") %>
                  <% mult = Map.get(activity, "multiplier", "") %>
                  <% wallet_full = Map.get(activity, "wallet", "") %>
                  <% wallet_short = Map.get(activity, "wallet_short") || truncate_wallet(wallet_full) %>
                  <% amount = Map.get(activity, "amount", "") %>
                  <% time_str = Map.get(activity, "time", "") %>
                  <% tx_sig = Map.get(activity, "tx_sig") %>
                  <div class="grid grid-cols-2 sm:grid-cols-[110px_140px_1fr_160px_110px_70px] px-5 py-3 items-center gap-y-2 hover:bg-black/[0.02] transition-colors">
                    <div>
                      <span class={[
                        "text-[9px] font-bold uppercase tracking-wider px-2 py-1 rounded-full",
                        activity_badge_class(type)
                      ]}>
                        {activity_badge_label(type, mult)}
                      </span>
                    </div>
                    <div class="flex items-center gap-2">
                      <div class={["w-4 h-4 rounded-full", activity_pool_dot_class(pool)]}></div>
                      <span class="text-[12px] font-bold text-[#141414]">{activity_pool_label(pool)}</span>
                    </div>
                    <div class="flex items-center gap-2 col-span-2 sm:col-span-1">
                      <BlocksterV2Web.DesignSystem.author_avatar initials={wallet_initials(wallet_full)} size="xs" />
                      <span class="text-[11px] font-mono text-neutral-500">{wallet_short}</span>
                    </div>
                    <div class={[
                      "text-right font-mono font-bold text-[13px] tabular-nums",
                      activity_amount_class(type)
                    ]}>
                      {amount}
                    </div>
                    <div class="text-right text-[11px] font-mono text-neutral-500">{time_str}</div>
                    <div class="text-right">
                      <%= if tx_sig do %>
                        <a href={BlocksterV2Web.Solscan.tx_url(tx_sig)} target="_blank" rel="noopener" class="text-[10px] font-mono text-neutral-400 hover:text-[#141414] transition-colors">
                          {short_sig(tx_sig)}
                        </a>
                      <% else %>
                        <span class="text-[10px] font-mono text-neutral-300">—</span>
                      <% end %>
                    </div>
                  </div>
                <% end %>
              </div>
            <% end %>

            <div class="px-5 py-4 border-t border-neutral-100 flex items-center justify-between flex-wrap gap-3">
              <div class="text-[11px] text-neutral-500">
                Showing {min(length(@activities), 6)} of {length(@activities)} recent events
              </div>
              <.link navigate={~p"/pool/sol"} class="text-[12px] font-bold text-[#141414] hover:text-[#7D00FF] transition-colors">
                Open SOL pool details →
              </.link>
            </div>
          </div>
        </section>
      </main>

      <BlocksterV2Web.DesignSystem.footer />
    </div>
    """
  end
end
