defmodule BlocksterV2Web.Admin.StatsLive.Index do
  @moduledoc """
  Admin dashboard for BuxBooster global betting statistics.
  Displays BUX and ROGUE global stats, house balances, and player counts.
  """
  use BlocksterV2Web, :live_view

  alias BlocksterV2.BuxBoosterStats

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
        last_updated: nil
      )

    if connected?(socket) do
      send(self(), :load_stats)
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
          <span class="font-medium text-gray-900"><%= Number.Delimit.number_to_delimited(@player_count) %></span> indexed players
        </p>
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
                  <dd class="text-xl font-medium"><%= Number.Delimit.number_to_delimited(@bux_stats.total_bets) %></dd>
                </div>
                <div>
                  <dt class="text-xs text-gray-500 uppercase">Wins</dt>
                  <dd class="text-xl font-medium text-green-600"><%= Number.Delimit.number_to_delimited(@bux_stats.total_wins) %></dd>
                </div>
                <div>
                  <dt class="text-xs text-gray-500 uppercase">Losses</dt>
                  <dd class="text-xl font-medium text-red-600"><%= Number.Delimit.number_to_delimited(@bux_stats.total_losses) %></dd>
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
                  <dd class="text-xl font-medium"><%= Number.Delimit.number_to_delimited(@rogue_stats.total_bets) %></dd>
                </div>
                <div>
                  <dt class="text-xs text-gray-500 uppercase">Wins</dt>
                  <dd class="text-xl font-medium text-green-600"><%= Number.Delimit.number_to_delimited(@rogue_stats.total_wins) %></dd>
                </div>
                <div>
                  <dt class="text-xs text-gray-500 uppercase">Losses</dt>
                  <dd class="text-xl font-medium text-red-600"><%= Number.Delimit.number_to_delimited(@rogue_stats.total_losses) %></dd>
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
