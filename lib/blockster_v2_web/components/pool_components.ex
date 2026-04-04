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

  def lp_price_chart(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl border border-gray-200 shadow-[0_1px_3px_rgba(0,0,0,0.04)] overflow-hidden">
      <%!-- Chart Header --%>
      <div class="px-6 py-5 border-b border-gray-100">
        <div class="flex items-center justify-between">
          <div>
            <div class="text-xs text-gray-400 font-haas_roman_55 uppercase tracking-wider mb-1"><%= @lp_token %> Price</div>
            <div class="flex items-baseline gap-2">
              <span class="text-2xl font-haas_bold_75 text-gray-900 tabular-nums">
                <%= if @loading, do: "...", else: format_price(@lp_price) %>
              </span>
              <span class="text-sm text-gray-400 font-haas_roman_55"><%= @token %></span>
            </div>
          </div>
          <%!-- Timeframe Selector --%>
          <div class="flex items-center gap-1 bg-gray-100 rounded-lg p-0.5">
            <%= for tf <- ~w(1H 24H 7D 30D All) do %>
              <button
                type="button"
                phx-click="set_chart_timeframe"
                phx-value-timeframe={tf}
                class={"px-2.5 py-1 text-[11px] font-haas_medium_65 rounded-md transition-all cursor-pointer #{if @timeframe == tf, do: "bg-white text-gray-900 shadow-sm", else: "text-gray-500 hover:text-gray-700"}"}
              >
                <%= tf %>
              </button>
            <% end %>
          </div>
        </div>
      </div>
      <%!-- Chart Container --%>
      <div
        id={"price-chart-#{@vault_type}"}
        phx-hook="PriceChart"
        class="h-64 sm:h-72 bg-gray-900"
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
  attr :timeframe, :string, default: "All"

  def pool_stats_grid(assigns) do
    is_sol = assigns.vault_type == "sol"
    token = if is_sol, do: "SOL", else: "BUX"
    lp_token = if is_sol, do: "SOL-LP", else: "BUX-LP"
    vault = assigns.vault_type

    assigns =
      assigns
      |> assign(token: token)
      |> assign(lp_token: lp_token)
      |> assign(vault: vault)

    ~H"""
    <div class="bg-white rounded-2xl border border-gray-200 shadow-[0_1px_3px_rgba(0,0,0,0.04)] p-5">
      <div class="flex items-center justify-between mb-3">
        <div class="text-xs text-gray-400 font-haas_roman_55 uppercase tracking-wider">Pool Statistics</div>
        <div class="text-[10px] text-gray-400 font-haas_roman_55"><%= @timeframe %></div>
      </div>
      <div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
        <.stat_card
          label="LP Price"
          value={if @loading, do: nil, else: format_price(get_vault_stat(@pool_stats, @vault, "lpPrice"))}
          suffix={@token}
          loading={@loading}
        />
        <.stat_card
          label="LP Supply"
          value={if @loading, do: nil, else: format_number(get_vault_stat(@pool_stats, @vault, "lpSupply"))}
          suffix={@lp_token}
          loading={@loading}
        />
        <.stat_card
          label="Bankroll"
          value={if @loading, do: nil, else: format_tvl(get_vault_stat(@pool_stats, @vault, "totalBalance"))}
          suffix={@token}
          loading={@loading}
        />
        <.stat_card
          label="Volume"
          value={if @loading, do: nil, else: format_tvl(get_vault_stat(@pool_stats, @vault, "totalVolume"))}
          suffix={@token}
          loading={@loading}
        />
        <.stat_card
          label="Total Bets"
          value={if @loading, do: nil, else: format_integer(get_vault_stat(@pool_stats, @vault, "totalBets"))}
          loading={@loading}
        />
        <.stat_card
          label="Win Rate"
          value={if @loading, do: nil, else: format_win_rate(get_vault_stat(@pool_stats, @vault, "totalBets"), get_vault_stat(@pool_stats, @vault, "totalWins"))}
          loading={@loading}
        />
        <.stat_card
          label="House Profit"
          value={if @loading, do: nil, else: format_profit_value(get_vault_stat(@pool_stats, @vault, "houseProfit"))}
          suffix={@token}
          color={profit_color(get_vault_stat(@pool_stats, @vault, "houseProfit"))}
          loading={@loading}
        />
        <.stat_card
          label="Total Payout"
          value={if @loading, do: nil, else: format_tvl(get_vault_stat(@pool_stats, @vault, "totalPayout"))}
          suffix={@token}
          loading={@loading}
        />
      </div>
    </div>
    """
  end

  # ── Stat Card ───────────────────────────────────────────────────────────────

  attr :label, :string, required: true
  attr :value, :string, default: nil
  attr :suffix, :string, default: ""
  attr :color, :string, default: nil
  attr :loading, :boolean, default: false

  def stat_card(assigns) do
    ~H"""
    <div class="bg-gray-50/80 rounded-lg px-3 py-2.5 border border-gray-100/80">
      <div class="text-[10px] text-gray-400 font-haas_roman_55 uppercase tracking-wider mb-1"><%= @label %></div>
      <%= if @loading do %>
        <div class="h-5 w-20 bg-gray-200/70 rounded animate-pulse" />
      <% else %>
        <div class="flex items-baseline gap-1">
          <span class={[
            "text-sm font-haas_medium_65 tabular-nums tracking-tight",
            @color || "text-gray-900"
          ]}>
            <%= @value %>
          </span>
          <%= if @suffix != "" do %>
            <span class="text-[10px] text-gray-400 font-haas_roman_55"><%= @suffix %></span>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  # ── Activity Table ───────────────────────────────────────────────────────────

  attr :activity_tab, :atom, default: :all
  attr :vault_type, :string, required: true
  attr :activities, :list, default: []

  def activity_table(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl border border-gray-200 shadow-[0_1px_3px_rgba(0,0,0,0.04)] overflow-hidden">
      <%!-- Tabs --%>
      <div class="flex items-center gap-1 px-5 pt-4 pb-3 border-b border-gray-100">
        <div class="text-xs text-gray-400 font-haas_roman_55 uppercase tracking-wider mr-3">Activity</div>
        <%= for {tab, label} <- [{:all, "All"}, {:wins, "Wins"}, {:losses, "Losses"}, {:liquidity, "Liquidity"}] do %>
          <button
            type="button"
            phx-click="set_activity_tab"
            phx-value-tab={Atom.to_string(tab)}
            class={"px-2.5 py-1 text-[11px] font-haas_medium_65 rounded-md transition-all cursor-pointer #{if @activity_tab == tab, do: "bg-gray-900 text-white", else: "text-gray-500 hover:text-gray-700 hover:bg-gray-100"}"}
          >
            <%= label %>
          </button>
        <% end %>
      </div>

      <%!-- Table Content --%>
      <%= if @activities == [] do %>
        <div class="text-center py-10 px-5">
          <div class="w-10 h-10 mx-auto mb-3 rounded-full bg-gray-100 flex items-center justify-center">
            <svg class="w-5 h-5 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.5">
              <path stroke-linecap="round" stroke-linejoin="round" d="M12 6v6h4.5m4.5 0a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
          </div>
          <div class="text-gray-400 text-sm font-haas_roman_55">No activity yet</div>
          <div class="text-gray-400/60 text-xs mt-1 font-haas_roman_55">Bets and liquidity events will appear here</div>
        </div>
      <% else %>
        <div class="divide-y divide-gray-100">
          <%= for activity <- @activities do %>
            <.activity_row activity={activity} vault_type={@vault_type} />
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  attr :activity, :map, required: true
  attr :vault_type, :string, required: true

  defp activity_row(assigns) do
    ~H"""
    <div class="flex items-center justify-between px-5 py-3 text-sm">
      <div class="flex items-center gap-3 min-w-0">
        <span class={[
          "inline-flex items-center px-2 py-0.5 rounded text-[10px] font-haas_medium_65 uppercase tracking-wider",
          activity_badge_class(@activity["type"])
        ]}>
          <%= @activity["type"] %>
        </span>
        <span class="text-gray-900 font-haas_medium_65 tabular-nums"><%= @activity["amount"] %></span>
      </div>
      <div class="flex items-center gap-3 text-xs text-gray-400 font-haas_roman_55">
        <span class="truncate max-w-[80px]"><%= @activity["wallet"] %></span>
        <span><%= @activity["time"] %></span>
      </div>
    </div>
    """
  end

  defp activity_badge_class("win"), do: "bg-emerald-50 text-emerald-600"
  defp activity_badge_class("loss"), do: "bg-red-50 text-red-600"
  defp activity_badge_class("deposit"), do: "bg-blue-50 text-blue-600"
  defp activity_badge_class("withdraw"), do: "bg-amber-50 text-amber-600"
  defp activity_badge_class(_), do: "bg-gray-100 text-gray-600"

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
  def format_number(val) when is_number(val) and val >= 1_000_000 do
    "#{:erlang.float_to_binary(val / 1_000_000, decimals: 2)}M"
  end

  def format_number(val) when is_number(val) and val >= 1_000 do
    "#{:erlang.float_to_binary(val / 1_000, decimals: 2)}k"
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
    "#{:erlang.float_to_binary(val / 1_000_000, decimals: 1)}M"
  end

  def format_integer(val) when is_number(val) and val >= 1_000 do
    "#{:erlang.float_to_binary(val / 1_000, decimals: 1)}k"
  end

  def format_integer(val) when is_number(val), do: "#{trunc(val)}"
  def format_integer(_), do: "0"

  @doc false
  def format_win_rate(total_bets, total_wins) when is_number(total_bets) and total_bets > 0 and is_number(total_wins) do
    pct = total_wins / total_bets * 100
    "#{:erlang.float_to_binary(pct, decimals: 1)}%"
  end

  def format_win_rate(_, _), do: "0.0%"

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
end
