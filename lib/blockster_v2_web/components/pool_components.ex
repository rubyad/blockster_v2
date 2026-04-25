defmodule BlocksterV2Web.PoolComponents do
  @moduledoc """
  Function components for the pool index and detail pages.
  Clean financial dashboard aesthetic — Bloomberg meets modern DeFi.
  """

  use Phoenix.Component
  use BlocksterV2Web, :verified_routes

  # ── Pool Card (Index Page) ──────────────────────────────────────────────────

  attr :vault_type, :string, required: true
  attr :pool_stats, :map, default: nil
  attr :loading, :boolean, default: false

  def pool_card(assigns) do
    assigns =
      assigns
      |> assign(:is_sol, assigns.vault_type == "sol")
      |> assign(:vault_stats, get_vault_stats(assigns.pool_stats, assigns.vault_type))

    ~H"""
    <div class={[
      "group relative bg-white rounded-2xl border overflow-hidden transition-all duration-300",
      "shadow-[0_1px_3px_rgba(0,0,0,0.04),0_1px_2px_rgba(0,0,0,0.06)]",
      "hover:shadow-[0_4px_16px_rgba(0,0,0,0.08),0_2px_4px_rgba(0,0,0,0.04)]",
      "hover:-translate-y-0.5",
      if(@is_sol,
        do: "border-gray-200 ring-1 ring-violet-100/60",
        else: "border-gray-200 ring-1 ring-amber-100/60"
      )
    ]}>
      <%!-- Accent gradient bar at top --%>
      <div class={[
        "h-[3px] w-full",
        if(@is_sol,
          do: "bg-gradient-to-r from-violet-500 via-fuchsia-500 to-violet-400",
          else: "bg-gradient-to-r from-amber-400 via-orange-500 to-amber-400"
        )
      ]} />

      <%!-- Card Header --%>
      <div class="px-6 pt-5 pb-4">
        <div class="flex items-center gap-3.5">
          <%!-- Pool Icon --%>
          <div class={[
            "w-11 h-11 rounded-xl flex items-center justify-center shadow-sm",
            "ring-1 ring-inset",
            if(@is_sol,
              do: "bg-gradient-to-br from-violet-500 to-fuchsia-500 ring-white/20",
              else: "bg-gradient-to-br from-amber-400 to-orange-500 ring-white/20"
            )
          ]}>
            <img
              src={if @is_sol, do: "https://ik.imagekit.io/blockster/solana-sol-logo.png", else: "https://ik.imagekit.io/blockster/blockster-icon.png"}
              alt={if @is_sol, do: "SOL", else: "BUX"}
              class="w-6 h-6 rounded-full"
            />
          </div>

          <div class="flex-1 min-w-0">
            <h2 class="text-lg font-haas_medium_65 text-gray-900 tracking-tight">
              <%= if @is_sol, do: "SOL Pool", else: "BUX Pool" %>
            </h2>
            <p class="text-xs text-gray-400 font-haas_roman_55 mt-0.5">
              <%= if @is_sol, do: "Earn from SOL wagers", else: "Earn from BUX wagers" %>
            </p>
          </div>

          <%!-- Live indicator dot --%>
          <div class="flex items-center gap-1.5">
            <span class="relative flex h-2 w-2">
              <span class={"absolute inline-flex h-full w-full rounded-full opacity-75 animate-ping #{if @is_sol, do: "bg-violet-400", else: "bg-amber-400"}"} />
              <span class={"relative inline-flex rounded-full h-2 w-2 #{if @is_sol, do: "bg-violet-500", else: "bg-amber-500"}"} />
            </span>
            <span class="text-[10px] text-gray-400 font-haas_roman_55 uppercase tracking-wider">Live</span>
          </div>
        </div>
      </div>

      <%!-- Stats Grid --%>
      <div class="px-6 pb-5">
        <%= if @loading do %>
          <div class="grid grid-cols-2 gap-3">
            <.skeleton_stat />
            <.skeleton_stat />
            <.skeleton_stat />
            <.skeleton_stat />
          </div>
        <% else %>
          <div class="grid grid-cols-2 gap-3">
            <.pool_stat_cell
              label="Total Value Locked"
              value={format_tvl(Map.get(@vault_stats, "totalBalance", 0))}
              suffix={if @is_sol, do: "SOL", else: "BUX"}
            />
            <.pool_stat_cell
              label="LP Price"
              value={format_price(Map.get(@vault_stats, "lpPrice", 1.0))}
              suffix={if @is_sol, do: "SOL", else: "BUX"}
            />
            <.pool_stat_cell
              label="LP Supply"
              value={format_number(Map.get(@vault_stats, "lpSupply", 0))}
              suffix={if @is_sol, do: "SOL-LP", else: "BUX-LP"}
            />
            <.pool_stat_cell
              label="House Profit"
              value={format_profit_value(Map.get(@vault_stats, "houseProfit", 0))}
              suffix={if @is_sol, do: "SOL", else: "BUX"}
              color={profit_color(Map.get(@vault_stats, "houseProfit", 0))}
            />
          </div>
        <% end %>
      </div>

      <%!-- CTA Button --%>
      <div class="px-6 pb-6">
        <.link
          navigate={if @is_sol, do: ~p"/pool/sol", else: ~p"/pool/bux"}
          class={[
            "flex items-center justify-center gap-2 w-full py-3.5 rounded-xl",
            "font-haas_medium_65 text-sm tracking-wide transition-all duration-200 cursor-pointer",
            "bg-gray-900 text-white hover:bg-gray-800",
            "group-hover:shadow-[0_2px_8px_rgba(0,0,0,0.15)]"
          ]}
        >
          <span>Enter Pool</span>
          <svg class="w-4 h-4 transition-transform duration-200 group-hover:translate-x-0.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M13 7l5 5m0 0l-5 5m5-5H6" />
          </svg>
        </.link>
      </div>
    </div>
    """
  end

  # ── LP Price Chart ───────────────────────────────────────────────────────────

  attr :vault_type, :string, required: true
  attr :lp_price, :float, default: 1.0
  attr :lp_token, :string, default: "SOL-LP"
  attr :token, :string, default: "SOL"
  attr :timeframe, :string, default: "24H"
  attr :loading, :boolean, default: false
  attr :chart_price_stats, :map, default: nil

  def lp_price_chart(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl border border-neutral-200/70 shadow-[0_1px_3px_rgba(0,0,0,0.04)] overflow-hidden">
      <%!-- Chart Header --%>
      <div class="px-6 py-4 border-b border-neutral-100 flex items-center justify-between flex-wrap gap-3">
        <div class="min-w-0">
          <div class="text-[10px] uppercase tracking-[0.14em] text-neutral-500 font-bold mb-1"><%= @lp_token %> price</div>
          <div class="flex items-baseline gap-2 flex-wrap">
            <span class="font-mono font-bold text-[28px] text-[#141414] leading-none tracking-tight tabular-nums">
              <%= if @loading, do: "...", else: format_price(@lp_price) %>
            </span>
            <span class="text-[12px] text-neutral-500"><%= @token %></span>
            <span
              :if={@chart_price_stats && @chart_price_stats.change_pct}
              class={"text-[12px] font-mono font-bold ml-2 tabular-nums " <>
                if(@chart_price_stats.change_pct >= 0, do: "text-[#22C55E]", else: "text-[#EF4444]")}
            >
              <%= format_change_pct(@chart_price_stats.change_pct) %>
            </span>
            <span class="text-[10px] text-neutral-400 font-mono">24h</span>
          </div>
        </div>
        <%!-- Timeframe Selector --%>
        <div class="flex items-center gap-1 shrink-0">
          <%= for tf <- ~w(1H 24H 7D 30D All) do %>
            <button
              type="button"
              phx-click="set_chart_timeframe"
              phx-value-timeframe={tf}
              class={"px-3 py-1.5 rounded-full font-mono text-[10px] font-bold tracking-[0.04em] transition-colors cursor-pointer " <> if(@timeframe == tf, do: "bg-[#141414] text-white", else: "text-neutral-500 hover:text-[#141414]")}
            >
              <%= tf %>
            </button>
          <% end %>
        </div>
      </div>
      <%!-- Chart Container --%>
      <div
        id={"price-chart-#{@vault_type}"}
        phx-hook="PriceChart"
        phx-update="ignore"
        class="h-64 sm:h-72 bg-white"
        data-vault-type={@vault_type}
      />
    </div>
    """
  end

  # ── Pool Stat Cell ──────────────────────────────────────────────────────────

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :suffix, :string, default: ""
  attr :color, :string, default: nil

  defp pool_stat_cell(assigns) do
    ~H"""
    <div class="bg-gray-50/80 rounded-lg px-3.5 py-3 border border-gray-100/80">
      <div class="text-[10px] text-gray-400 font-haas_roman_55 uppercase tracking-wider mb-1.5">
        <%= @label %>
      </div>
      <div class="flex items-baseline gap-1">
        <span class={[
          "text-base font-haas_medium_65 tabular-nums tracking-tight",
          @color || "text-gray-900"
        ]}>
          <%= @value %>
        </span>
        <span class="text-[10px] text-gray-400 font-haas_roman_55"><%= @suffix %></span>
      </div>
    </div>
    """
  end

  # ── Loading Skeleton ────────────────────────────────────────────────────────

  defp skeleton_stat(assigns) do
    ~H"""
    <div class="bg-gray-50/80 rounded-lg px-3.5 py-3 border border-gray-100/80">
      <div class="h-2.5 w-16 bg-gray-200/70 rounded animate-pulse mb-2.5" />
      <div class="h-5 w-24 bg-gray-200/70 rounded animate-pulse" />
    </div>
    """
  end

  # ── Pool Stats Grid ──────────────────────────────────────────────────────────

  attr :pool_stats, :map, default: nil
  attr :loading, :boolean, default: false
  attr :vault_type, :string, required: true
  attr :timeframe, :string, default: "24H"
  attr :period_stats, :map, default: %{total: 0, wins: 0, volume: 0.0, payout: 0.0, profit: 0.0}

  def pool_stats_grid(assigns) do
    is_sol = assigns.vault_type == "sol"
    token = if is_sol, do: "SOL", else: "BUX"
    lp_token = if is_sol, do: "SOL-LP", else: "BUX-LP"
    vault = assigns.vault_type
    tf = assigns.timeframe

    lp_price_val = get_vault_stat(assigns.pool_stats, vault, "lpPrice")
    lp_supply_val = get_vault_stat(assigns.pool_stats, vault, "lpSupply")
    vol = assigns.period_stats.volume
    total = assigns.period_stats.total
    wins = assigns.period_stats.wins
    profit = assigns.period_stats.profit
    payout = assigns.period_stats.payout
    house_edge_pct = if is_number(vol) and vol > 0 and is_number(profit), do: profit / vol * 100, else: 0.0

    assigns =
      assigns
      |> assign(token: token)
      |> assign(lp_token: lp_token)
      |> assign(vault: vault)
      |> assign(tf: tf)
      |> assign(lp_price_val: lp_price_val)
      |> assign(lp_supply_val: lp_supply_val)
      |> assign(vol: vol)
      |> assign(total: total)
      |> assign(wins: wins)
      |> assign(profit: profit)
      |> assign(payout: payout)
      |> assign(house_edge_pct: house_edge_pct)

    ~H"""
    <div class="grid grid-cols-2 md:grid-cols-4 gap-3">
      <.stat_card
        label="LP price"
        value={if @loading, do: nil, else: format_price(@lp_price_val)}
        sub_line={@token <> " per LP"}
        loading={@loading}
      />
      <.stat_card
        label="LP supply"
        value={if @loading, do: nil, else: format_number(@lp_supply_val)}
        sub_line={@lp_token <> " issued"}
        loading={@loading}
      />
      <.stat_card
        label={"Volume " <> String.downcase(@tf)}
        value={if @loading, do: nil, else: format_tvl(@vol)}
        sub_line={@token <> " wagered"}
        loading={@loading}
      />
      <.stat_card
        label={"Bets " <> String.downcase(@tf)}
        value={if @loading, do: nil, else: format_integer(@total)}
        sub_line={"#{format_integer(@total)} total"}
        loading={@loading}
      />
      <.stat_card
        label={"Win rate " <> String.downcase(@tf)}
        value={if @loading, do: nil, else: format_win_rate_value(@total, @wins)}
        value_suffix="%"
        sub_line={format_integer(@wins) <> " of " <> format_integer(@total)}
        loading={@loading}
      />
      <.stat_card
        label={"Profit " <> String.downcase(@tf)}
        value={if @loading, do: nil, else: format_profit_value(@profit)}
        sub_line={@token <> " to LPs"}
        color={profit_color(@profit)}
        loading={@loading}
      />
      <.stat_card
        label={"Payout " <> String.downcase(@tf)}
        value={if @loading, do: nil, else: format_tvl(@payout)}
        sub_line={@token <> " to winners"}
        loading={@loading}
      />
      <.stat_card
        label="House edge"
        value={if @loading, do: nil, else: format_house_edge(@house_edge_pct)}
        value_suffix="%"
        sub_line={"realized " <> String.downcase(@tf)}
        loading={@loading}
      />
    </div>
    """
  end

  # ── Stat Card ───────────────────────────────────────────────────────────────

  attr :label, :string, required: true
  attr :value, :string, default: nil
  attr :value_suffix, :string, default: ""
  attr :sub_line, :string, default: ""
  attr :color, :string, default: nil
  attr :loading, :boolean, default: false

  def stat_card(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl border border-neutral-200/70 p-4 shadow-[0_1px_3px_rgba(0,0,0,0.04)]">
      <div class="text-[9px] uppercase tracking-[0.12em] text-neutral-500 font-medium mb-1.5"><%= @label %></div>
      <%= if @loading do %>
        <div class="h-5 w-20 bg-gray-200/70 rounded animate-pulse" />
      <% else %>
        <div class={[
          "font-mono font-bold text-[18px] leading-none tabular-nums",
          @color || "text-[#141414]"
        ]}>
          <%= @value %><span :if={@value_suffix != ""} class="text-[12px]"><%= @value_suffix %></span>
        </div>
      <% end %>
      <div :if={@sub_line != ""} class="text-[10px] text-neutral-500 font-mono mt-1"><%= @sub_line %></div>
    </div>
    """
  end

  # ── Activity Table ───────────────────────────────────────────────────────────

  attr :activity_tab, :atom, default: :all
  attr :vault_type, :string, required: true
  attr :activities, :list, default: []

  attr :total_count, :integer, default: nil

  def activity_table(assigns) do
    shown = length(assigns.activities)
    total = assigns[:total_count] || shown
    assigns = assigns |> assign(shown: shown) |> assign(total: total)

    ~H"""
    <div class="bg-white rounded-2xl border border-neutral-200/70 shadow-[0_1px_3px_rgba(0,0,0,0.04)] overflow-hidden">
      <%!-- Header row --%>
      <div class="px-5 py-3 border-b border-neutral-100 flex items-center justify-between flex-wrap gap-3">
        <div class="flex items-center gap-2">
          <span class="w-1.5 h-1.5 rounded-full bg-[#22C55E] animate-pulse"></span>
          <span class="text-[10px] uppercase tracking-[0.14em] text-neutral-500 font-bold">Activity · Live</span>
        </div>
        <div class="flex items-center gap-1.5">
          <%= for {tab, label} <- [{:all, "All"}, {:wins, "Wins"}, {:losses, "Losses"}, {:liquidity, "Liquidity"}] do %>
            <button
              type="button"
              phx-click="set_activity_tab"
              phx-value-tab={Atom.to_string(tab)}
              class={"px-3 py-1.5 rounded-full font-mono text-[10px] font-bold tracking-[0.04em] transition-colors cursor-pointer " <> if(@activity_tab == tab, do: "bg-[#141414] text-white", else: "text-neutral-500 hover:text-[#141414]")}
            >
              <%= label %>
            </button>
          <% end %>
        </div>
      </div>

      <%!-- Table content --%>
      <%= if @activities == [] do %>
        <div class="text-center py-10 px-5">
          <div class="w-10 h-10 mx-auto mb-3 rounded-full bg-neutral-100 flex items-center justify-center">
            <svg class="w-5 h-5 text-neutral-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.5">
              <path stroke-linecap="round" stroke-linejoin="round" d="M12 6v6h4.5m4.5 0a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
          </div>
          <div class="text-neutral-500 text-sm">No activity yet</div>
          <div class="text-neutral-400 text-xs mt-1">Bets and liquidity events will appear here</div>
        </div>
      <% else %>
        <div class="divide-y divide-neutral-100">
          <%= for activity <- @activities do %>
            <.activity_row activity={activity} vault_type={@vault_type} />
          <% end %>
        </div>
      <% end %>

      <%!-- Footer --%>
      <div class="px-5 py-3 border-t border-neutral-100 flex items-center justify-between">
        <div class="text-[11px] text-neutral-500">Showing <%= @shown %> of <%= @total %> events</div>
        <button type="button" class="text-[12px] font-bold text-[#141414] hover:text-[#7D00FF] transition-colors cursor-pointer">Load more →</button>
      </div>
    </div>
    """
  end

  attr :activity, :map, required: true
  attr :vault_type, :string, required: true

  defp activity_row(assigns) do
    ~H"""
    <div class="px-4 md:px-5 py-3 grid grid-cols-[110px_1fr_70px_50px] md:grid-cols-[180px_1fr_140px_60px] items-center gap-2 hover:bg-black/[0.02] transition-colors">
      <%!-- Col 1: icon tile + label --%>
      <div class="flex items-center gap-2.5">
        <div class={[
          "w-7 h-7 rounded-lg border grid place-items-center",
          row_icon_wrapper_class(@activity["type"])
        ]}>
          <svg class={["w-3.5 h-3.5", row_icon_color(@activity["type"])]} fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
            <%= row_icon_path(@activity["type"]) %>
          </svg>
        </div>
        <div class="min-w-0">
          <%= if @activity["game"] && valid_sig?(@activity["commitment_sig"]) do %>
            <a href={BlocksterV2Web.Solscan.tx_url(@activity["commitment_sig"])} target="_blank" class="text-[12px] font-bold text-[#141414] leading-tight hover:underline cursor-pointer block truncate" title="View commitment tx">
              <%= row_primary_label(@activity) %>
            </a>
          <% else %>
            <div class="text-[12px] font-bold text-[#141414] leading-tight truncate">
              <%= row_primary_label(@activity) %>
            </div>
          <% end %>
          <div class="text-[10px] text-neutral-500 truncate">
            <%= row_secondary_label(@activity) %>
          </div>
        </div>
      </div>

      <%!-- Col 2: wallet avatar + short wallet --%>
      <div class="flex items-center gap-2 min-w-0">
        <%= if @activity["full_wallet"] do %>
          <a href={BlocksterV2Web.Solscan.account_url(@activity["full_wallet"])} target="_blank" class="flex items-center gap-2 hover:opacity-80 cursor-pointer min-w-0">
            <div class="w-6 h-6 rounded-full grid place-items-center text-[8px] font-bold text-[#E8E4DD] shrink-0" style="background: linear-gradient(135deg, #1a1a22 0%, #2a2a35 100%);">
              <%= row_avatar_initials(@activity["wallet"]) %>
            </div>
            <span class="text-[11px] font-mono text-neutral-500 truncate"><%= @activity["wallet"] %></span>
          </a>
        <% else %>
          <div class="flex items-center gap-2 min-w-0">
            <div class="w-6 h-6 rounded-full grid place-items-center text-[8px] font-bold text-[#E8E4DD] shrink-0" style="background: linear-gradient(135deg, #1a1a22 0%, #2a2a35 100%);">
              <%= row_avatar_initials(@activity["wallet"]) %>
            </div>
            <span class="text-[11px] font-mono text-neutral-500 truncate"><%= @activity["wallet"] %></span>
          </div>
        <% end %>
      </div>

      <%!-- Col 3: profit + bet sub-line --%>
      <div class="text-right">
        <%= if @activity["game_id"] && valid_sig?(@activity["settlement_sig"]) do %>
          <a href={BlocksterV2Web.Solscan.tx_url(@activity["settlement_sig"])} target="_blank" title="View settlement tx" class={[
            "font-mono font-bold text-[13px] tabular-nums hover:underline cursor-pointer",
            profit_text_color(@activity["type"])
          ]}>
            <%= @activity["profit"] %>
          </a>
        <% else %>
          <div class={[
            "font-mono font-bold text-[13px] tabular-nums",
            profit_text_color(@activity["type"])
          ]}>
            <%= @activity["profit"] %>
          </div>
        <% end %>
        <%= cond do %>
          <% @activity["bet"] && valid_sig?(@activity["bet_sig"]) -> %>
            <a href={BlocksterV2Web.Solscan.tx_url(@activity["bet_sig"])} target="_blank" title="View bet tx" class="text-[10px] text-neutral-500 font-mono hover:underline cursor-pointer block mt-0.5">
              bet <%= @activity["bet"] %>
            </a>
          <% @activity["bet"] -> %>
            <div class="text-[10px] text-neutral-500 font-mono mt-0.5">bet <%= @activity["bet"] %></div>
          <% @activity["type"] == "deposit" -> %>
            <div class="text-[10px] text-neutral-500 font-mono mt-0.5">to vault</div>
          <% @activity["type"] == "withdraw" -> %>
            <div class="text-[10px] text-neutral-500 font-mono mt-0.5">to wallet</div>
          <% true -> %>
            <%= if @activity["time"] do %>
              <div class="text-[10px] text-neutral-500 font-mono mt-0.5"><%= @activity["time"] %></div>
            <% end %>
        <% end %>
      </div>

      <%!-- Col 4: tx short link + optional fairness verify --%>
      <div class="text-right">
        <%= if @activity["tx_sig"] && !@activity["game_id"] do %>
          <a href={BlocksterV2Web.Solscan.tx_url(@activity["tx_sig"])} target="_blank" class="text-[10px] font-mono text-neutral-400 hover:text-[#141414] cursor-pointer">
            <%= row_short_sig(@activity["tx_sig"]) %>
          </a>
        <% end %>
        <%= if @activity["game_id"] && valid_sig?(@activity["settlement_sig"]) do %>
          <a href={BlocksterV2Web.Solscan.tx_url(@activity["settlement_sig"])} target="_blank" class="text-[10px] font-mono text-neutral-400 hover:text-[#141414] cursor-pointer block">
            <%= row_short_sig(@activity["settlement_sig"]) %>
          </a>
        <% end %>
        <%= if @activity["game_id"] && @activity["settled"] do %>
          <button
            type="button"
            phx-click="show_fairness_modal"
            phx-value-game-id={@activity["game_id"]}
            class="text-[10px] text-neutral-400 hover:text-[#22C55E] cursor-pointer mt-1"
            title="Verify fairness"
          >
            Verify
          </button>
        <% end %>
      </div>
    </div>
    """
  end

  defp row_primary_label(%{"type" => "win", "multiplier" => mult}) when is_binary(mult), do: "Win #{mult}"
  defp row_primary_label(%{"type" => "loss", "multiplier" => mult}) when is_binary(mult), do: "Loss #{mult}"
  defp row_primary_label(%{"type" => "deposit"}), do: "Deposit"
  defp row_primary_label(%{"type" => "withdraw"}), do: "Withdraw"
  defp row_primary_label(%{"game" => game}) when is_binary(game), do: game
  defp row_primary_label(_), do: "Activity"

  defp row_secondary_label(%{"type" => type, "predictions" => preds, "results" => results}) when type in ["win", "loss"] and is_list(preds) and is_list(results) do
    wins = Enum.zip(preds, results) |> Enum.count(fn {p, r} -> p == r end)
    "Coin flip · #{wins} of #{length(preds)}"
  end
  defp row_secondary_label(%{"type" => "deposit", "profit" => p}) when is_binary(p), do: "#{p} minted"
  defp row_secondary_label(%{"type" => "withdraw", "profit" => p}) when is_binary(p), do: "#{p} burned"
  defp row_secondary_label(%{"time" => time}) when is_binary(time), do: time
  defp row_secondary_label(_), do: ""

  defp row_avatar_initials(nil), do: "—"
  defp row_avatar_initials(""), do: "—"
  defp row_avatar_initials(wallet) when is_binary(wallet) do
    wallet
    |> String.replace(~r/[^a-zA-Z0-9]/, "")
    |> String.slice(0, 2)
  end

  defp row_short_sig(nil), do: ""
  defp row_short_sig(sig) when is_binary(sig) and byte_size(sig) >= 4, do: "#{String.slice(sig, 0, 4)}…"
  defp row_short_sig(sig), do: sig

  defp row_icon_wrapper_class("win"), do: "bg-[#22C55E]/12 border-[#22C55E]/25"
  defp row_icon_wrapper_class("loss"), do: "bg-[#EF4444]/12 border-[#EF4444]/25"
  defp row_icon_wrapper_class("deposit"), do: "bg-[#7D00FF]/15 border-[#7D00FF]/30"
  defp row_icon_wrapper_class("withdraw"), do: "bg-[#facc15]/15 border-[#facc15]/30"
  defp row_icon_wrapper_class(_), do: "bg-neutral-100 border-neutral-200"

  defp row_icon_color("win"), do: "text-[#15803d]"
  defp row_icon_color("loss"), do: "text-[#7f1d1d]"
  defp row_icon_color("deposit"), do: "text-[#7D00FF]"
  defp row_icon_color("withdraw"), do: "text-[#a16207]"
  defp row_icon_color(_), do: "text-neutral-500"

  defp row_icon_path("win") do
    assigns = %{}
    ~H"""
    <polyline points="18 15 12 9 6 15" />
    """
  end
  defp row_icon_path("loss") do
    assigns = %{}
    ~H"""
    <polyline points="6 9 12 15 18 9" />
    """
  end
  defp row_icon_path("deposit") do
    assigns = %{}
    ~H"""
    <line x1="12" y1="5" x2="12" y2="19" />
    <line x1="5" y1="12" x2="19" y2="12" />
    """
  end
  defp row_icon_path("withdraw") do
    assigns = %{}
    ~H"""
    <line x1="12" y1="5" x2="12" y2="19" />
    <polyline points="19 12 12 19 5 12" />
    """
  end
  defp row_icon_path(_) do
    assigns = %{}
    ~H"""
    <circle cx="12" cy="12" r="9" />
    """
  end

  defp valid_sig?(nil), do: false
  defp valid_sig?(""), do: false
  defp valid_sig?("failed_no_onchain_order"), do: false
  defp valid_sig?("already_settled_on_chain"), do: false
  defp valid_sig?(_), do: true

  defp profit_text_color("win"), do: "text-[#22C55E]"
  defp profit_text_color("loss"), do: "text-[#EF4444]"
  defp profit_text_color("deposit"), do: "text-[#7D00FF]"
  defp profit_text_color("withdraw"), do: "text-[#a16207]"
  defp profit_text_color(_), do: "text-[#141414]"

  # ── Format Helpers ──────────────────────────────────────────────────────────

  @doc false
  def format_tvl(val) when is_number(val) and val >= 1_000_000 do
    "#{:erlang.float_to_binary(val / 1_000_000, decimals: 2)}M"
  end

  def format_tvl(val) when is_number(val) and val >= 1_000 do
    "#{:erlang.float_to_binary(val / 1_000, decimals: 2)}k"
  end

  def format_tvl(val) when is_number(val) and val > 0 do
    :erlang.float_to_binary(val / 1.0, decimals: 2)
  end

  def format_tvl(_), do: "0.00"

  @doc false
  def format_price(val) when is_number(val) and val > 0 do
    :erlang.float_to_binary(val / 1.0, decimals: 6)
  end

  def format_price(_), do: "1.000000"

  @doc false
  def format_change_pct(pct) when is_number(pct) and pct >= 0 do
    "+#{:erlang.float_to_binary(pct / 1.0, decimals: 2)}%"
  end

  def format_change_pct(pct) when is_number(pct) do
    "#{:erlang.float_to_binary(pct / 1.0, decimals: 2)}%"
  end

  def format_change_pct(_), do: nil

  @doc false
  def format_number(val) when is_number(val) and val >= 1_000_000 do
    "#{:erlang.float_to_binary(val / 1.0 / 1_000_000, decimals: 2)}M"
  end

  def format_number(val) when is_number(val) and val >= 1_000 do
    "#{:erlang.float_to_binary(val / 1.0 / 1_000, decimals: 2)}k"
  end

  def format_number(val) when is_number(val) and val > 0 do
    :erlang.float_to_binary(val / 1.0, decimals: 2)
  end

  def format_number(_), do: "0"

  @doc false
  def format_profit_value(val) when is_number(val) and val > 0 do
    "+#{:erlang.float_to_binary(val / 1.0, decimals: 4)}"
  end

  def format_profit_value(val) when is_number(val) and val < 0 do
    :erlang.float_to_binary(val / 1.0, decimals: 4)
  end

  def format_profit_value(_), do: "0.0000"

  @doc false
  def format_integer(val) when is_number(val) and val >= 1_000_000 do
    "#{:erlang.float_to_binary(val / 1.0 / 1_000_000, decimals: 1)}M"
  end

  def format_integer(val) when is_number(val) and val >= 1_000 do
    "#{:erlang.float_to_binary(val / 1.0 / 1_000, decimals: 1)}k"
  end

  def format_integer(val) when is_number(val), do: "#{trunc(val)}"
  def format_integer(_), do: "0"

  @doc false
  def format_win_rate(total_bets, total_wins) when is_number(total_bets) and total_bets > 0 and is_number(total_wins) do
    pct = total_wins / total_bets * 100
    "#{:erlang.float_to_binary(pct / 1.0, decimals: 1)}%"
  end

  def format_win_rate(_, _), do: "0.0%"

  @doc false
  def format_win_rate_value(total_bets, total_wins) when is_number(total_bets) and total_bets > 0 and is_number(total_wins) do
    pct = total_wins / total_bets * 100
    :erlang.float_to_binary(pct / 1.0, decimals: 1)
  end

  def format_win_rate_value(_, _), do: "0.0"

  @doc false
  def format_house_edge(pct) when is_number(pct) do
    :erlang.float_to_binary(pct / 1.0, decimals: 1)
  end

  def format_house_edge(_), do: "0.0"

  @doc false
  def profit_color(val) when is_number(val) and val > 0, do: "text-emerald-500"
  def profit_color(val) when is_number(val) and val < 0, do: "text-red-500"
  def profit_color(_), do: "text-gray-500"

  @doc false
  def get_vault_stat(nil, _vault, _key), do: 0

  def get_vault_stat(stats, vault, key) do
    case stats[vault] do
      nil -> 0
      vault_stats -> vault_stats[key] || 0
    end
  end

  defp get_vault_stats(nil, _vault_type), do: %{}

  defp get_vault_stats(stats, vault_type) do
    stats[vault_type] || %{}
  end

  # ── Coin Flip Fairness Modal ────────────────────────────────────────────────

  attr :fairness_game, :map, required: true
  attr :show, :boolean, default: false

  def coin_flip_fairness_modal(assigns) do
    ~H"""
    <%= if @show and @fairness_game do %>
      <div class="fixed inset-0 bg-black/60 flex items-end sm:items-center justify-center z-50 p-0 sm:p-4" phx-click="hide_fairness_modal">
        <div class="bg-white rounded-none sm:rounded-2xl w-full sm:max-w-xl max-h-[100vh] sm:max-h-[90vh] overflow-y-auto shadow-2xl" phx-click="stop_propagation">

          <%!-- Header --%>
          <div class="p-3 sm:p-4 border-b border-gray-200 flex items-center justify-between bg-gray-50 sm:rounded-t-2xl sticky top-0 z-10">
            <div class="flex items-center gap-2">
              <div class="w-7 h-7 rounded-lg bg-emerald-100 flex items-center justify-center">
                <svg class="w-4 h-4 text-emerald-600" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
                </svg>
              </div>
              <h2 class="text-base sm:text-lg font-bold text-gray-900">Provably Fair Verification</h2>
            </div>
            <button type="button" phx-click="hide_fairness_modal" class="w-8 h-8 flex items-center justify-center rounded-lg hover:bg-gray-200 text-gray-400 hover:text-gray-600 cursor-pointer transition-colors">
              <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>

          <div class="p-3 sm:p-4 space-y-3 sm:space-y-4">

            <%!-- Bet Details --%>
            <div class="bg-blue-50 rounded-xl p-3 sm:p-4 border border-blue-200">
              <p class="text-xs sm:text-sm font-semibold text-blue-900 mb-1">Your Bet Details</p>
              <p class="text-[10px] sm:text-xs text-blue-600 mb-2.5">These player-controlled values derive your client seed:</p>
              <div class="grid grid-cols-[auto_1fr] gap-x-3 gap-y-1.5 text-xs sm:text-sm">
                <span class="text-blue-500">User ID:</span>
                <span class="font-mono text-[10px] sm:text-xs text-blue-800"><%= @fairness_game.user_id %></span>
                <span class="text-blue-500">Bet:</span>
                <span class="font-semibold text-blue-800"><%= format_fairness_amount(@fairness_game.bet_amount) %> <%= String.upcase(@fairness_game.vault_type) %></span>
                <span class="text-blue-500">Difficulty:</span>
                <span class="text-blue-800"><%= fairness_difficulty_label(@fairness_game.difficulty) %></span>
                <span class="text-blue-500">Predictions:</span>
                <span class="text-blue-800">
                  <%= for pred <- (@fairness_game.predictions || []) do %>
                    <span class="inline-block"><%= if pred == :heads, do: "🚀", else: "💩" %></span>
                  <% end %>
                  <span class="text-[10px] text-blue-500 ml-1">(<%= @fairness_game.predictions_str %>)</span>
                </span>
              </div>
            </div>

            <%!-- Nonce --%>
            <div class="bg-gray-50 rounded-xl p-3 sm:p-4">
              <div class="flex justify-between items-center">
                <span class="text-xs sm:text-sm text-gray-600">Game Nonce:</span>
                <span class="font-mono text-sm sm:text-base font-semibold text-gray-900"><%= @fairness_game.nonce %></span>
              </div>
              <p class="text-[10px] sm:text-xs text-gray-400 mt-1">
                Sequential counter — ensures unique results even for identical bets
              </p>
            </div>

            <%!-- Seeds --%>
            <div class="space-y-2.5 sm:space-y-3">
              <div>
                <label class="text-xs sm:text-sm font-semibold text-gray-700">Server Seed <span class="font-normal text-gray-400">(revealed after settlement)</span></label>
                <code class="mt-1 text-[10px] sm:text-xs font-mono bg-gray-100 px-2.5 py-2 rounded-lg break-all block border border-gray-200"><%= @fairness_game.server_seed %></code>
              </div>
              <div>
                <label class="text-xs sm:text-sm font-semibold text-gray-700">Server Commitment <span class="font-normal text-gray-400">(shown before bet)</span></label>
                <code class="mt-1 text-[10px] sm:text-xs font-mono bg-gray-100 px-2.5 py-2 rounded-lg break-all block border border-gray-200"><%= @fairness_game.server_seed_hash %></code>
              </div>
              <div>
                <label class="text-xs sm:text-sm font-semibold text-gray-700">Client Seed <span class="font-normal text-gray-400">(derived from your bet)</span></label>
                <code class="mt-1 text-[10px] sm:text-xs font-mono bg-gray-100 px-2.5 py-2 rounded-lg break-all block border border-gray-200"><%= @fairness_game.client_seed %></code>
                <p class="text-[10px] sm:text-xs text-gray-400 mt-1 font-mono break-all">
                  = SHA256("<%= @fairness_game.client_seed_input %>")
                </p>
              </div>
              <div>
                <label class="text-xs sm:text-sm font-semibold text-gray-700">Combined Seed</label>
                <code class="mt-1 text-[10px] sm:text-xs font-mono bg-gray-100 px-2.5 py-2 rounded-lg break-all block border border-gray-200"><%= @fairness_game.combined_seed %></code>
                <p class="text-[10px] sm:text-xs text-gray-400 mt-1">
                  = SHA256(server_seed + ":" + client_seed + ":" + nonce)
                </p>
              </div>
            </div>

            <%!-- How It Works --%>
            <div class="bg-emerald-50 rounded-xl p-3 sm:p-4 border border-emerald-200">
              <p class="text-xs sm:text-sm font-semibold text-emerald-900 mb-2">How the Result is Determined</p>
              <ol class="text-[10px] sm:text-xs text-emerald-700 space-y-1 list-decimal ml-4">
                <li><span class="font-mono">SHA256(server_seed)</span> = commitment hash (locked before you bet)</li>
                <li><span class="font-mono">client_seed = SHA256(user_id:bet_amount:token:difficulty:predictions)</span></li>
                <li><span class="font-mono">combined_seed = SHA256(server_seed:client_seed:nonce)</span></li>
                <li>First <strong><%= length(@fairness_game.results) %></strong> bytes of combined seed determine the coin flips</li>
                <li>Each byte <strong>&lt; 128</strong> = 🚀 HEADS &nbsp;|&nbsp; <strong>&ge; 128</strong> = 💩 TAILS</li>
                <li>
                  <%= if @fairness_game.difficulty < 0 do %>
                    <strong>Win One</strong> mode: any flip matching your prediction = WIN
                  <% else %>
                    <strong>Win All</strong> mode: all flips must match your predictions = WIN
                  <% end %>
                </li>
              </ol>
            </div>

            <%!-- Flip-by-Flip Breakdown --%>
            <div>
              <p class="text-xs sm:text-sm font-semibold text-gray-700 mb-2">Flip Results (<%= length(@fairness_game.results) %> flips)</p>
              <div class="space-y-1.5">
                <%= for i <- 0..(length(@fairness_game.results) - 1) do %>
                  <% byte = Enum.at(@fairness_game.bytes, i) %>
                  <% result = Enum.at(@fairness_game.results, i) %>
                  <% prediction = Enum.at(@fairness_game.predictions, i) %>
                  <% matched = result == prediction %>
                  <div class={"flex items-center justify-between text-xs sm:text-sm p-2 sm:p-2.5 rounded-lg border #{if matched, do: "bg-emerald-50/60 border-emerald-200", else: "bg-red-50/60 border-red-200"}"}>
                    <div class="flex items-center gap-2">
                      <span class="text-gray-500 text-[10px] sm:text-xs w-12">Flip <%= i + 1 %></span>
                      <span class="font-mono text-[10px] sm:text-xs text-gray-500">byte[<%= i %>]=<%= byte %></span>
                    </div>
                    <div class="flex items-center gap-2 sm:gap-3">
                      <span class={"text-[10px] sm:text-xs px-1.5 py-0.5 rounded font-mono #{if byte < 128, do: "bg-blue-100 text-blue-700", else: "bg-amber-100 text-amber-700"}"}>
                        <%= if byte < 128, do: "< 128", else: ">= 128" %>
                      </span>
                      <span class="text-base"><%= if result == :heads, do: "🚀", else: "💩" %></span>
                      <span class={"text-[10px] sm:text-xs font-semibold #{if matched, do: "text-emerald-600", else: "text-red-500"}"}>
                        <%= if matched, do: "MATCH", else: "MISS" %>
                      </span>
                    </div>
                  </div>
                <% end %>
              </div>

              <%!-- Result Summary --%>
              <div class={"mt-3 rounded-xl p-3 sm:p-4 border #{if @fairness_game.won, do: "bg-emerald-50 border-emerald-200", else: "bg-red-50 border-red-200"}"}>
                <div class="flex justify-between items-center text-sm">
                  <span class="text-gray-600 font-medium">Result:</span>
                  <span class={"text-lg font-bold #{if @fairness_game.won, do: "text-emerald-600", else: "text-red-600"}"}>
                    <%= if @fairness_game.won, do: "WIN", else: "LOSS" %>
                  </span>
                </div>
                <div class="flex justify-between items-center text-xs sm:text-sm mt-1.5">
                  <span class="text-gray-500">Payout:</span>
                  <span class="font-semibold text-gray-900">
                    <%= format_fairness_amount(@fairness_game.payout) %> <%= String.upcase(@fairness_game.vault_type) %>
                  </span>
                </div>
              </div>
            </div>

            <%!-- External Verification --%>
            <div class="border-t border-gray-200 pt-3 sm:pt-4">
              <p class="text-xs sm:text-sm font-semibold text-gray-700 mb-1">Verify Externally</p>
              <p class="text-[10px] sm:text-xs text-gray-400 mb-3">
                Click each link to verify using an online SHA256 calculator:
              </p>
              <div class="space-y-2.5">
                <%!-- Step 1: Verify commitment --%>
                <div class="bg-gray-50 rounded-lg p-2.5 sm:p-3 border border-gray-100">
                  <p class="text-[10px] sm:text-xs text-gray-600 font-medium mb-1">1. Verify server commitment</p>
                  <a href={"https://md5calc.com/hash/sha256/#{@fairness_game.server_seed}"} target="_blank" class="text-blue-500 hover:underline text-[10px] sm:text-xs cursor-pointer">
                    SHA256(server_seed) &rarr; Click to verify
                  </a>
                  <p class="text-[10px] text-gray-400 mt-1 font-mono break-all">Expected: <%= @fairness_game.server_seed_hash %></p>
                </div>

                <%!-- Step 2: Derive client seed --%>
                <div class="bg-gray-50 rounded-lg p-2.5 sm:p-3 border border-gray-100">
                  <p class="text-[10px] sm:text-xs text-gray-600 font-medium mb-1">2. Derive client seed from bet details</p>
                  <a href={"https://md5calc.com/hash/sha256/#{@fairness_game.client_seed_input}"} target="_blank" class="text-blue-500 hover:underline text-[10px] sm:text-xs cursor-pointer">
                    SHA256(bet_details) &rarr; Click to verify
                  </a>
                  <p class="text-[10px] text-gray-400 mt-1 font-mono break-all">Expected: <%= @fairness_game.client_seed %></p>
                </div>

                <%!-- Step 3: Generate combined seed --%>
                <div class="bg-gray-50 rounded-lg p-2.5 sm:p-3 border border-gray-100">
                  <p class="text-[10px] sm:text-xs text-gray-600 font-medium mb-1">3. Generate combined seed</p>
                  <a href={"https://md5calc.com/hash/sha256/#{@fairness_game.server_seed}:#{@fairness_game.client_seed}:#{@fairness_game.nonce}"} target="_blank" class="text-blue-500 hover:underline text-[10px] sm:text-xs cursor-pointer">
                    SHA256(server:client:nonce) &rarr; Click to verify
                  </a>
                  <p class="text-[10px] text-gray-400 mt-1 font-mono break-all">Expected: <%= @fairness_game.combined_seed %></p>
                </div>

                <%!-- Step 4: Hex bytes visualization --%>
                <div class="bg-gray-50 rounded-lg p-2.5 sm:p-3 border border-gray-100">
                  <p class="text-[10px] sm:text-xs text-gray-600 font-medium mb-1">4. Convert hex bytes to flip results</p>
                  <p class="text-[10px] text-gray-400 mb-2">
                    First <%= length(@fairness_game.results) %> byte pairs from combined seed:
                  </p>
                  <%!-- Hex pairs with highlighting --%>
                  <div class="bg-white rounded-lg p-2 border border-gray-200 font-mono text-[10px] sm:text-xs leading-relaxed break-all">
                    <%= for i <- 0..(div(String.length(@fairness_game.combined_seed), 2) - 1) do %>
                      <% pair = String.slice(@fairness_game.combined_seed, i * 2, 2) %>
                      <%= if i < length(@fairness_game.bytes) do %>
                        <% byte = Enum.at(@fairness_game.bytes, i) %>
                        <span class={"inline-block px-0.5 rounded #{if byte < 128, do: "bg-blue-100 text-blue-700", else: "bg-amber-200 text-amber-700"}"} title={"Flip #{i + 1}: #{pair} = #{byte} → #{if byte < 128, do: "HEADS 🚀", else: "TAILS 💩"}"}><%= pair %></span>
                      <% else %>
                        <span class="text-gray-300"><%= pair %></span>
                      <% end %>
                    <% end %>
                  </div>
                  <%!-- Byte-to-result mapping --%>
                  <div class="mt-2 space-y-0.5">
                    <%= for {byte, i} <- Enum.with_index(@fairness_game.bytes) do %>
                      <div class="flex items-center gap-1.5 text-[10px] sm:text-xs">
                        <span class={"inline-block font-mono px-1 py-0.5 rounded #{if byte < 128, do: "bg-blue-100 text-blue-700", else: "bg-amber-200 text-amber-700"}"}>
                          <%= String.slice(@fairness_game.combined_seed, i * 2, 2) %>
                        </span>
                        <span class="text-gray-400">=</span>
                        <span class="font-mono text-gray-600"><%= byte %></span>
                        <span class={"font-mono px-1 py-0.5 rounded #{if byte < 128, do: "bg-blue-50 text-blue-500", else: "bg-amber-50 text-amber-500"}"}>
                          <%= if byte < 128, do: "< 128", else: ">= 128" %>
                        </span>
                        <span class="text-gray-400">&rarr;</span>
                        <span class={"font-bold #{if byte < 128, do: "text-blue-600", else: "text-amber-600"}"}>
                          <%= if byte < 128, do: "🚀 HEADS", else: "💩 TAILS" %>
                        </span>
                      </div>
                    <% end %>
                  </div>
                  <p class="text-[10px] text-gray-400 mt-2">
                    Verify: <a href="https://www.rapidtables.com/convert/number/hex-to-decimal.html" target="_blank" class="text-blue-500 hover:underline cursor-pointer">Hex to Decimal converter</a>
                  </p>
                </div>
              </div>
            </div>

          </div>

          <%!-- Footer --%>
          <div class="p-3 sm:p-4 border-t border-gray-200 bg-gray-50 sm:rounded-b-2xl sticky bottom-0">
            <button type="button" phx-click="hide_fairness_modal" class="w-full py-2.5 bg-gray-900 text-white rounded-xl hover:bg-gray-800 transition-all cursor-pointer text-sm font-medium">
              Close
            </button>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  defp format_fairness_amount(nil), do: "0"
  defp format_fairness_amount(amount) when is_number(amount) and amount == 0, do: "0"
  defp format_fairness_amount(amount) when is_number(amount) and amount < 1.0 do
    :erlang.float_to_binary(amount / 1.0, decimals: 4) |> String.trim_trailing("0")
  end
  defp format_fairness_amount(amount) when is_number(amount) do
    :erlang.float_to_binary(amount / 1.0, decimals: 2)
  end
  defp format_fairness_amount(_), do: "0"

  defp fairness_difficulty_label(d) when d < 0, do: "Win One (#{abs(d) + 1} flips, any match wins)"
  defp fairness_difficulty_label(1), do: "Classic (1 flip)"
  defp fairness_difficulty_label(d) when d > 1, do: "Win All (#{d} flips, all must match)"
  defp fairness_difficulty_label(_), do: "Unknown"
end
