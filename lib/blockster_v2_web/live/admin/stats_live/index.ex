defmodule BlocksterV2Web.Admin.StatsLive.Index do
  @moduledoc """
  Admin dashboard for BuxBooster global betting statistics.
  Displays BUX and ROGUE global stats, house balances, and player counts.
  """
  use BlocksterV2Web, :live_view

  alias BlocksterV2.BuxBoosterStats
  alias BlocksterV2.AuthorityGasTracker

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(
        page_title: "BuxBooster Stats",
        bux_stats: nil,
        rogue_stats: nil,
        house_balances: nil,
        player_count: 0,
        loading: true,
        last_updated: nil,
        authority_balance: nil,
        gas_stats_today: nil,
        gas_stats_weekly: nil
      )

    if connected?(socket) do
      send(self(), :load_stats)
      # Refresh authority balance every 60 seconds
      :timer.send_interval(60_000, self(), :refresh_authority)
    end

    {:ok, socket}
  end

  @impl true
  def handle_info(:load_stats, socket) do
    socket =
      socket
      |> start_async(:fetch_bux_global, fn ->
        bux = BuxBoosterStats.get_bux_global_stats()
        rogue = BuxBoosterStats.get_rogue_global_stats()
        case {bux, rogue} do
          {{:ok, b}, {:ok, r}} -> {:ok, %{bux: b, rogue: r}}
          {{:error, e}, _} -> {:error, e}
          {_, {:error, e}} -> {:error, e}
        end
      end)
      |> start_async(:fetch_house_balances, fn -> BuxBoosterStats.get_house_balances() end)
      |> start_async(:fetch_player_count, fn -> BuxBoosterStats.get_player_count() end)
      |> start_async(:fetch_authority_stats, fn ->
        balance = AuthorityGasTracker.get_authority_balance()
        today = AuthorityGasTracker.get_today()
        weekly = AuthorityGasTracker.get_daily_stats(7)
        {balance, today, weekly}
      end)

    {:noreply, socket}
  end

  @impl true
  def handle_info(:refresh_authority, socket) do
    socket =
      socket
      |> start_async(:fetch_authority_balance, fn ->
        AuthorityGasTracker.get_authority_balance()
      end)

    {:noreply, socket}
  end

  @impl true
  def handle_async(:fetch_bux_global, {:ok, {:ok, %{bux: bux_stats, rogue: rogue_stats}}}, socket) do
    {:noreply,
     socket
     |> assign(bux_stats: bux_stats, rogue_stats: rogue_stats, loading: false, last_updated: DateTime.utc_now())}
  end

  def handle_async(:fetch_bux_global, {:ok, {:error, _reason}}, socket) do
    {:noreply, assign(socket, loading: false)}
  end

  def handle_async(:fetch_bux_global, {:exit, _reason}, socket) do
    {:noreply, assign(socket, loading: false)}
  end

  @impl true
  def handle_async(:fetch_house_balances, {:ok, {:ok, balances}}, socket) do
    {:noreply, assign(socket, house_balances: balances)}
  end

  def handle_async(:fetch_house_balances, {:ok, {:error, _reason}}, socket) do
    {:noreply, socket}
  end

  def handle_async(:fetch_house_balances, {:exit, _reason}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_async(:fetch_player_count, {:ok, count}, socket) do
    {:noreply, assign(socket, player_count: count)}
  end

  def handle_async(:fetch_player_count, {:exit, _reason}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_async(:fetch_authority_stats, {:ok, {balance_result, today, weekly}}, socket) do
    {authority_balance, balance_lamports} =
      case balance_result do
        {:ok, lamports} -> {lamports, lamports}
        _ -> {nil, nil}
      end

    # Update today's record with the fetched balance
    if balance_lamports, do: AuthorityGasTracker.update_authority_balance(balance_lamports)

    {:noreply,
     socket
     |> assign(
       authority_balance: authority_balance,
       gas_stats_today: today,
       gas_stats_weekly: weekly
     )}
  end

  def handle_async(:fetch_authority_stats, {:ok, _}, socket), do: {:noreply, socket}
  def handle_async(:fetch_authority_stats, {:exit, _reason}, socket), do: {:noreply, socket}

  @impl true
  def handle_async(:fetch_authority_balance, {:ok, {:ok, lamports}}, socket) do
    AuthorityGasTracker.update_authority_balance(lamports)
    # Refresh today's stats to pick up the updated balance
    today = AuthorityGasTracker.get_today()
    {:noreply, assign(socket, authority_balance: lamports, gas_stats_today: today)}
  end

  def handle_async(:fetch_authority_balance, {:ok, _}, socket), do: {:noreply, socket}
  def handle_async(:fetch_authority_balance, {:exit, _reason}, socket), do: {:noreply, socket}

  @impl true
  def handle_event("refresh", _params, socket) do
    send(self(), :load_stats)
    {:noreply, assign(socket, loading: true)}
  end

  # ============ Helper Functions ============

  # Format wei value to human-readable token amount with commas
  defp format_token(wei) when is_integer(wei) do
    amount = wei / 1_000_000_000_000_000_000
    Number.Delimit.number_to_delimited(Float.round(amount, 2))
  end

  defp format_token(_), do: "0"

  # Format win rate as percentage
  defp win_rate(wins, total) when total > 0, do: Float.round(wins / total * 100, 2)
  defp win_rate(_, _), do: 0.0

  # Format lamports to SOL string with 4 decimal places
  defp format_sol(nil), do: "—"
  defp format_sol(lamports) when is_integer(lamports) do
    sol = lamports / 1_000_000_000
    :erlang.float_to_binary(sol, decimals: 4)
  end
  defp format_sol(_), do: "—"

  # Color class for authority SOL balance
  defp balance_color(nil), do: "text-gray-400"
  defp balance_color(lamports) when is_integer(lamports) do
    sol = lamports / 1_000_000_000
    cond do
      sol >= 1.0 -> "text-green-600"
      sol >= 0.5 -> "text-yellow-600"
      true -> "text-red-600"
    end
  end
  defp balance_color(_), do: "text-gray-400"

  # Format a Date struct as "Apr 03" style
  defp format_date(%Date{} = date) do
    month = date |> Map.get(:month) |> month_abbr()
    day = date |> Map.get(:day) |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{month} #{day}"
  end
  defp format_date(_), do: "—"

  defp month_abbr(1), do: "Jan"
  defp month_abbr(2), do: "Feb"
  defp month_abbr(3), do: "Mar"
  defp month_abbr(4), do: "Apr"
  defp month_abbr(5), do: "May"
  defp month_abbr(6), do: "Jun"
  defp month_abbr(7), do: "Jul"
  defp month_abbr(8), do: "Aug"
  defp month_abbr(9), do: "Sep"
  defp month_abbr(10), do: "Oct"
  defp month_abbr(11), do: "Nov"
  defp month_abbr(12), do: "Dec"

  # Format relative time
  defp time_ago(nil), do: ""

  defp time_ago(datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      diff < 60 -> "#{diff} seconds ago"
      diff < 3600 -> "#{div(diff, 60)} minutes ago"
      diff < 86400 -> "#{div(diff, 3600)} hours ago"
      true -> "#{div(diff, 86400)} days ago"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 pt-24 max-w-6xl mx-auto">
      <!-- Header -->
      <div class="flex justify-between items-center mb-6">
        <div>
          <h1 class="text-2xl font-haas_medium_65">BuxBooster Admin Stats</h1>
          <%= if @last_updated do %>
            <p class="text-sm text-gray-500">Last updated: <%= time_ago(@last_updated) %></p>
          <% end %>
        </div>
        <div class="flex items-center gap-4">
          <.link navigate={~p"/admin/stats/players"} class="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 cursor-pointer">
            View All Players
          </.link>
          <button phx-click="refresh" class="px-4 py-2 bg-gray-100 rounded-lg hover:bg-gray-200 cursor-pointer">
            <%= if @loading do %>
              <span class="animate-spin inline-block">↻</span> Loading...
            <% else %>
              ↻ Refresh
            <% end %>
          </button>
        </div>
      </div>

      <!-- Player Count Summary -->
      <div class="mb-6 p-4 bg-gray-50 rounded-lg">
        <p class="text-sm text-gray-600">
          <span class="font-medium text-gray-900"><%= Number.Delimit.number_to_delimited(@player_count, precision: 0) %></span> indexed players
        </p>
      </div>

      <!-- Solana Authority Wallet -->
      <div class="bg-white rounded-lg shadow p-6 mb-6">
        <div class="flex items-center gap-2 mb-4">
          <h2 class="text-lg font-haas_medium_65">Solana Authority Wallet</h2>
          <span class="text-xs text-gray-400 font-mono">6b4n...uv1</span>
        </div>

        <!-- Balance -->
        <div class="mb-4 p-4 bg-gray-50 rounded-lg">
          <dt class="text-xs text-gray-500 uppercase mb-1">SOL Balance</dt>
          <dd class={"text-2xl font-bold #{balance_color(@authority_balance)}"}>
            <%= if @authority_balance do %>
              <%= format_sol(@authority_balance) %> SOL
            <% else %>
              <span class="text-gray-400">Loading...</span>
            <% end %>
          </dd>
        </div>

        <!-- Today's Gas -->
        <%= if @gas_stats_today do %>
          <div class="mb-4">
            <h3 class="text-sm font-medium text-gray-700 mb-2">Today's Gas Spend</h3>
            <div class="grid grid-cols-5 gap-3">
              <div class="p-3 bg-blue-50 rounded-lg">
                <dt class="text-xs text-blue-600 uppercase">Mints</dt>
                <dd class="text-lg font-bold text-blue-800"><%= @gas_stats_today.mint_count %></dd>
              </div>
              <div class="p-3 bg-purple-50 rounded-lg">
                <dt class="text-xs text-purple-600 uppercase">ATAs</dt>
                <dd class="text-lg font-bold text-purple-800"><%= @gas_stats_today.ata_creations %></dd>
              </div>
              <div class="p-3 bg-gray-50 rounded-lg">
                <dt class="text-xs text-gray-500 uppercase">TX Fees</dt>
                <dd class="text-lg font-bold"><%= format_sol(@gas_stats_today.total_tx_fees_lamports) %></dd>
              </div>
              <div class="p-3 bg-gray-50 rounded-lg">
                <dt class="text-xs text-gray-500 uppercase">ATA Rent</dt>
                <dd class="text-lg font-bold"><%= format_sol(@gas_stats_today.total_ata_rent_lamports) %></dd>
              </div>
              <div class="p-3 bg-red-50 rounded-lg">
                <dt class="text-xs text-red-600 uppercase">Total</dt>
                <dd class="text-lg font-bold text-red-800">
                  <%= format_sol(@gas_stats_today.total_tx_fees_lamports + @gas_stats_today.total_ata_rent_lamports) %>
                </dd>
              </div>
            </div>
          </div>
        <% end %>

        <!-- 7-Day History -->
        <%= if @gas_stats_weekly && @gas_stats_weekly != [] do %>
          <div>
            <h3 class="text-sm font-medium text-gray-700 mb-2">7-Day History</h3>
            <div class="overflow-x-auto">
              <table class="w-full text-sm">
                <thead>
                  <tr class="border-b text-left text-xs text-gray-500 uppercase">
                    <th class="pb-2 pr-4">Date</th>
                    <th class="pb-2 pr-4 text-right">Mints</th>
                    <th class="pb-2 pr-4 text-right">ATAs</th>
                    <th class="pb-2 pr-4 text-right">Fees (SOL)</th>
                    <th class="pb-2 pr-4 text-right">Rent (SOL)</th>
                    <th class="pb-2 pr-4 text-right">Total (SOL)</th>
                    <th class="pb-2 text-right">Balance (SOL)</th>
                  </tr>
                </thead>
                <tbody>
                  <%= for stat <- @gas_stats_weekly do %>
                    <tr class="border-b border-gray-100">
                      <td class="py-2 pr-4 font-medium"><%= format_date(stat.date) %></td>
                      <td class="py-2 pr-4 text-right"><%= stat.mint_count %></td>
                      <td class="py-2 pr-4 text-right"><%= stat.ata_creations %></td>
                      <td class="py-2 pr-4 text-right"><%= format_sol(stat.total_tx_fees_lamports) %></td>
                      <td class="py-2 pr-4 text-right"><%= format_sol(stat.total_ata_rent_lamports) %></td>
                      <td class="py-2 pr-4 text-right font-medium">
                        <%= format_sol(stat.total_tx_fees_lamports + stat.total_ata_rent_lamports) %>
                      </td>
                      <td class={"py-2 text-right #{balance_color(stat.authority_balance_lamports)}"}>
                        <%= format_sol(stat.authority_balance_lamports) %>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          </div>
        <% end %>
      </div>

      <!-- Stats Cards Grid -->
      <div class="grid grid-cols-1 md:grid-cols-2 gap-6 mb-6">

        <!-- BUX Stats Card -->
        <div class="bg-white rounded-lg shadow p-6">
          <div class="flex items-center gap-2 mb-4">
            <span class="text-2xl">🔵</span>
            <h2 class="text-lg font-haas_medium_65">BUX Betting</h2>
          </div>

          <%= if @bux_stats do %>
            <dl class="space-y-3">
              <div class="grid grid-cols-3 gap-4 pb-3 border-b">
                <div>
                  <dt class="text-xs text-gray-500 uppercase">Total Bets</dt>
                  <dd class="text-xl font-medium"><%= Number.Delimit.number_to_delimited(@bux_stats.total_bets, precision: 0) %></dd>
                </div>
                <div>
                  <dt class="text-xs text-gray-500 uppercase">Wins</dt>
                  <dd class="text-xl font-medium text-green-600"><%= Number.Delimit.number_to_delimited(@bux_stats.total_wins, precision: 0) %></dd>
                </div>
                <div>
                  <dt class="text-xs text-gray-500 uppercase">Losses</dt>
                  <dd class="text-xl font-medium text-red-600"><%= Number.Delimit.number_to_delimited(@bux_stats.total_losses, precision: 0) %></dd>
                </div>
              </div>

              <div class="flex justify-between items-center">
                <dt class="text-gray-500">Player Win Rate</dt>
                <dd class="font-medium"><%= win_rate(@bux_stats.total_wins, @bux_stats.total_bets) %>%</dd>
              </div>

              <div class="flex justify-between items-center">
                <dt class="text-gray-500">Volume Wagered</dt>
                <dd class="font-medium"><%= format_token(@bux_stats.total_volume_wagered) %> BUX</dd>
              </div>

              <div class="flex justify-between items-center">
                <dt class="text-gray-500">Total Payouts</dt>
                <dd class="font-medium"><%= format_token(@bux_stats.total_payouts) %> BUX</dd>
              </div>

              <div class="flex justify-between items-center pt-3 border-t">
                <dt class="text-gray-500 font-medium">House Profit</dt>
                <dd class={"text-xl font-bold #{if @bux_stats.total_house_profit >= 0, do: "text-green-600", else: "text-red-600"}"}>
                  <%= if @bux_stats.total_house_profit >= 0, do: "+", else: "" %><%= format_token(@bux_stats.total_house_profit) %> BUX
                </dd>
              </div>

              <div class="grid grid-cols-2 gap-4 pt-3 border-t">
                <div>
                  <dt class="text-xs text-gray-500 uppercase">Largest Bet</dt>
                  <dd class="font-medium"><%= format_token(@bux_stats.largest_bet) %> BUX</dd>
                </div>
                <div>
                  <dt class="text-xs text-gray-500 uppercase">Largest Win</dt>
                  <dd class="font-medium"><%= format_token(@bux_stats.largest_win) %> BUX</dd>
                </div>
              </div>
            </dl>
          <% else %>
            <div class="animate-pulse space-y-3">
              <div class="h-8 bg-gray-200 rounded w-1/2"></div>
              <div class="h-4 bg-gray-200 rounded w-3/4"></div>
              <div class="h-4 bg-gray-200 rounded w-2/3"></div>
            </div>
          <% end %>
        </div>

        <!-- ROGUE Stats Card -->
        <div class="bg-white rounded-lg shadow p-6">
          <div class="flex items-center gap-2 mb-4">
            <span class="text-2xl">🟡</span>
            <h2 class="text-lg font-haas_medium_65">ROGUE Betting</h2>
          </div>

          <%= if @rogue_stats do %>
            <dl class="space-y-3">
              <div class="grid grid-cols-3 gap-4 pb-3 border-b">
                <div>
                  <dt class="text-xs text-gray-500 uppercase">Total Bets</dt>
                  <dd class="text-xl font-medium"><%= Number.Delimit.number_to_delimited(@rogue_stats.total_bets, precision: 0) %></dd>
                </div>
                <div>
                  <dt class="text-xs text-gray-500 uppercase">Wins</dt>
                  <dd class="text-xl font-medium text-green-600"><%= Number.Delimit.number_to_delimited(@rogue_stats.total_wins, precision: 0) %></dd>
                </div>
                <div>
                  <dt class="text-xs text-gray-500 uppercase">Losses</dt>
                  <dd class="text-xl font-medium text-red-600"><%= Number.Delimit.number_to_delimited(@rogue_stats.total_losses, precision: 0) %></dd>
                </div>
              </div>

              <div class="flex justify-between items-center">
                <dt class="text-gray-500">Player Win Rate</dt>
                <dd class="font-medium"><%= win_rate(@rogue_stats.total_wins, @rogue_stats.total_bets) %>%</dd>
              </div>

              <div class="flex justify-between items-center">
                <dt class="text-gray-500">Volume Wagered</dt>
                <dd class="font-medium"><%= format_token(@rogue_stats.total_volume_wagered) %> ROGUE</dd>
              </div>

              <div class="flex justify-between items-center">
                <dt class="text-gray-500">Total Payouts</dt>
                <dd class="font-medium"><%= format_token(@rogue_stats.total_payouts) %> ROGUE</dd>
              </div>

              <div class="flex justify-between items-center pt-3 border-t">
                <dt class="text-gray-500 font-medium">House Profit</dt>
                <dd class={"text-xl font-bold #{if @rogue_stats.total_house_profit >= 0, do: "text-green-600", else: "text-red-600"}"}>
                  <%= if @rogue_stats.total_house_profit >= 0, do: "+", else: "" %><%= format_token(@rogue_stats.total_house_profit) %> ROGUE
                </dd>
              </div>

              <div class="grid grid-cols-2 gap-4 pt-3 border-t">
                <div>
                  <dt class="text-xs text-gray-500 uppercase">Largest Bet</dt>
                  <dd class="font-medium"><%= format_token(@rogue_stats.largest_bet) %> ROGUE</dd>
                </div>
                <div>
                  <dt class="text-xs text-gray-500 uppercase">Largest Win</dt>
                  <dd class="font-medium"><%= format_token(@rogue_stats.largest_win) %> ROGUE</dd>
                </div>
              </div>
            </dl>
          <% else %>
            <div class="animate-pulse space-y-3">
              <div class="h-8 bg-gray-200 rounded w-1/2"></div>
              <div class="h-4 bg-gray-200 rounded w-3/4"></div>
              <div class="h-4 bg-gray-200 rounded w-2/3"></div>
            </div>
          <% end %>
        </div>
      </div>

      <!-- House Balances -->
      <div class="bg-white rounded-lg shadow p-6">
        <h2 class="text-lg font-haas_medium_65 mb-4">House Balances</h2>
        <%= if @house_balances do %>
          <div class="grid grid-cols-2 gap-6">
            <div class="p-4 bg-blue-50 rounded-lg">
              <dt class="text-sm text-blue-600 uppercase">BUX House Balance</dt>
              <dd class="text-2xl font-bold text-blue-800"><%= format_token(@house_balances.bux) %> BUX</dd>
            </div>
            <div class="p-4 bg-yellow-50 rounded-lg">
              <dt class="text-sm text-yellow-600 uppercase">ROGUE House Balance</dt>
              <dd class="text-2xl font-bold text-yellow-800"><%= format_token(@house_balances.rogue) %> ROGUE</dd>
            </div>
          </div>
        <% else %>
          <div class="animate-pulse grid grid-cols-2 gap-6">
            <div class="h-24 bg-gray-200 rounded"></div>
            <div class="h-24 bg-gray-200 rounded"></div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
