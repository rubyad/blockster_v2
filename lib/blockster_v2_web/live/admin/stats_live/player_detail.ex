defmodule BlocksterV2Web.Admin.StatsLive.PlayerDetail do
  @moduledoc """
  Admin page showing detailed betting statistics for a single player.
  Displays BUX stats, ROGUE stats, and per-difficulty breakdown for both.

  Stats are fetched fresh from on-chain every time the page loads or Refresh is clicked.
  The result is cached in Mnesia for future reference.
  """
  use BlocksterV2Web, :live_view

  alias BlocksterV2.BuxBoosterStats

  # Difficulty level mapping (contract uses -4 to 5, skipping 0)
  # Array indices: 0-3 = Win One (-4 to -1), 4-8 = Win All (1 to 5)
  # Note: difficulty 1 = "Single Flip" (1 flip, must win) at 1.98x
  @difficulty_labels [
    {0, "Win One 5-flip", "1.02x"},    # difficulty -4
    {1, "Win One 4-flip", "1.05x"},    # difficulty -3
    {2, "Win One 3-flip", "1.13x"},    # difficulty -2
    {3, "Win One 2-flip", "1.32x"},    # difficulty -1
    {4, "Single Flip", "1.98x"},       # difficulty 1 (Win All 1-flip)
    {5, "Win All 2-flip", "3.96x"},    # difficulty 2
    {6, "Win All 3-flip", "7.92x"},    # difficulty 3
    {7, "Win All 4-flip", "15.84x"},   # difficulty 4
    {8, "Win All 5-flip", "31.68x"}    # difficulty 5
  ]

  @impl true
  def mount(%{"address" => address}, _session, socket) do
    socket =
      socket
      |> assign(
        page_title: "Player: #{short_address(address)}",
        wallet: address,
        stats: nil,
        loading: true
      )

    if connected?(socket) do
      send(self(), :load_stats)
    end

    {:ok, socket}
  end

  @impl true
  def handle_info(:load_stats, socket) do
    wallet = socket.assigns.wallet

    socket =
      start_async(socket, :load_stats, fn ->
        # Fetch fresh on-chain stats and cache in Mnesia
        BuxBoosterStats.refresh_and_cache_player_stats(wallet)
      end)

    {:noreply, socket}
  end

  @impl true
  def handle_async(:load_stats, {:ok, {:ok, stats}}, socket) do
    {:noreply, assign(socket, stats: stats, loading: false)}
  end

  def handle_async(:load_stats, {:ok, {:error, _reason}}, socket) do
    {:noreply, assign(socket, loading: false)}
  end

  def handle_async(:load_stats, {:exit, _reason}, socket) do
    {:noreply, assign(socket, loading: false)}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    # No need to invalidate - refresh_and_cache_player_stats always fetches fresh from on-chain
    send(self(), :load_stats)
    {:noreply, assign(socket, loading: true)}
  end

  # ============ Helper Functions ============

  defp format_token(wei) when is_integer(wei) do
    amount = wei / 1_000_000_000_000_000_000
    Number.Delimit.number_to_delimited(Float.round(amount, 2))
  end

  defp format_token(_), do: "0"

  defp format_pnl(pnl) when is_integer(pnl) do
    amount = pnl / 1_000_000_000_000_000_000
    formatted = Number.Delimit.number_to_delimited(Float.round(abs(amount), 2))
    if pnl >= 0, do: "+#{formatted}", else: "-#{formatted}"
  end

  defp format_pnl(_), do: "0"

  defp pnl_color(pnl) when is_integer(pnl) and pnl >= 0, do: "text-green-600"
  defp pnl_color(pnl) when is_integer(pnl) and pnl < 0, do: "text-red-600"
  defp pnl_color(_), do: ""

  defp short_address(address) when is_binary(address) do
    "#{String.slice(address, 0..5)}...#{String.slice(address, -4..-1)}"
  end

  defp short_address(_), do: ""

  defp difficulty_labels, do: @difficulty_labels

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 pt-24 max-w-6xl mx-auto">
      <!-- Header -->
      <div class="flex justify-between items-center mb-6">
        <div>
          <div class="flex items-center gap-2">
            <.link navigate={~p"/admin/stats/players"} class="text-blue-600 hover:underline cursor-pointer">
              ← Back to Players
            </.link>
          </div>
          <h1 class="text-2xl font-haas_medium_65 mt-2">Player Stats</h1>
          <p class="text-sm text-gray-500 font-mono">
            <a
              href={"https://roguescan.io/address/#{@wallet}"}
              target="_blank"
              class="text-blue-600 hover:underline cursor-pointer"
            >
              <%= @wallet %> ↗
            </a>
          </p>
        </div>
        <button
          phx-click="refresh"
          class="px-4 py-2 bg-gray-100 rounded-lg hover:bg-gray-200 cursor-pointer"
        >
          <%= if @loading do %>
            <span class="animate-spin inline-block">↻</span> Loading...
          <% else %>
            ↻ Refresh
          <% end %>
        </button>
      </div>

      <%= if @loading do %>
        <div class="bg-white rounded-lg shadow p-8 text-center">
          <div class="animate-spin inline-block w-8 h-8 border-4 border-blue-600 border-t-transparent rounded-full"></div>
          <p class="mt-2 text-gray-500">Loading player stats...</p>
        </div>
      <% else %>
        <%= if @stats do %>
          <!-- Stats Cards Grid -->
          <div class="grid grid-cols-1 md:grid-cols-2 gap-6 mb-6">

            <!-- BUX Stats Card -->
            <div class="bg-white rounded-lg shadow p-6">
              <div class="flex items-center gap-2 mb-4">
                <span class="text-2xl">🔵</span>
                <h2 class="text-lg font-haas_medium_65">BUX Stats</h2>
              </div>

              <dl class="space-y-3">
                <div class="grid grid-cols-3 gap-4 pb-3 border-b">
                  <div>
                    <dt class="text-xs text-gray-500 uppercase">Total Bets</dt>
                    <dd class="text-xl font-medium">
                      <%= Number.Delimit.number_to_delimited(@stats.bux.total_bets) %>
                    </dd>
                  </div>
                  <div>
                    <dt class="text-xs text-gray-500 uppercase">Wins</dt>
                    <dd class="text-xl font-medium text-green-600">
                      <%= Number.Delimit.number_to_delimited(@stats.bux.wins) %>
                    </dd>
                  </div>
                  <div>
                    <dt class="text-xs text-gray-500 uppercase">Losses</dt>
                    <dd class="text-xl font-medium text-red-600">
                      <%= Number.Delimit.number_to_delimited(@stats.bux.losses) %>
                    </dd>
                  </div>
                </div>

                <div class="flex justify-between items-center">
                  <dt class="text-gray-500">Win Rate</dt>
                  <dd class="font-medium"><%= @stats.bux.win_rate %>%</dd>
                </div>

                <div class="flex justify-between items-center">
                  <dt class="text-gray-500">Total Wagered</dt>
                  <dd class="font-medium"><%= format_token(@stats.bux.total_wagered) %> BUX</dd>
                </div>

                <div class="flex justify-between items-center">
                  <dt class="text-gray-500">Total Winnings</dt>
                  <dd class="font-medium text-green-600">
                    <%= format_token(@stats.bux.total_winnings) %> BUX
                  </dd>
                </div>

                <div class="flex justify-between items-center">
                  <dt class="text-gray-500">Total Losses</dt>
                  <dd class="font-medium text-red-600">
                    <%= format_token(@stats.bux.total_losses) %> BUX
                  </dd>
                </div>

                <div class="flex justify-between items-center pt-3 border-t">
                  <dt class="text-gray-500 font-medium">Net Profit/Loss</dt>
                  <dd class={"text-xl font-bold #{pnl_color(@stats.bux.net_pnl)}"}>
                    <%= format_pnl(@stats.bux.net_pnl) %> BUX
                  </dd>
                </div>
              </dl>
            </div>

            <!-- ROGUE Stats Card -->
            <div class="bg-white rounded-lg shadow p-6">
              <div class="flex items-center gap-2 mb-4">
                <span class="text-2xl">🟡</span>
                <h2 class="text-lg font-haas_medium_65">ROGUE Stats</h2>
              </div>

              <dl class="space-y-3">
                <div class="grid grid-cols-3 gap-4 pb-3 border-b">
                  <div>
                    <dt class="text-xs text-gray-500 uppercase">Total Bets</dt>
                    <dd class="text-xl font-medium">
                      <%= Number.Delimit.number_to_delimited(@stats.rogue.total_bets) %>
                    </dd>
                  </div>
                  <div>
                    <dt class="text-xs text-gray-500 uppercase">Wins</dt>
                    <dd class="text-xl font-medium text-green-600">
                      <%= Number.Delimit.number_to_delimited(@stats.rogue.wins) %>
                    </dd>
                  </div>
                  <div>
                    <dt class="text-xs text-gray-500 uppercase">Losses</dt>
                    <dd class="text-xl font-medium text-red-600">
                      <%= Number.Delimit.number_to_delimited(@stats.rogue.losses) %>
                    </dd>
                  </div>
                </div>

                <div class="flex justify-between items-center">
                  <dt class="text-gray-500">Win Rate</dt>
                  <dd class="font-medium"><%= @stats.rogue.win_rate %>%</dd>
                </div>

                <div class="flex justify-between items-center">
                  <dt class="text-gray-500">Total Wagered</dt>
                  <dd class="font-medium"><%= format_token(@stats.rogue.total_wagered) %> ROGUE</dd>
                </div>

                <div class="flex justify-between items-center">
                  <dt class="text-gray-500">Total Winnings</dt>
                  <dd class="font-medium text-green-600">
                    <%= format_token(@stats.rogue.total_winnings) %> ROGUE
                  </dd>
                </div>

                <div class="flex justify-between items-center">
                  <dt class="text-gray-500">Total Losses</dt>
                  <dd class="font-medium text-red-600">
                    <%= format_token(@stats.rogue.total_losses) %> ROGUE
                  </dd>
                </div>

                <div class="flex justify-between items-center pt-3 border-t">
                  <dt class="text-gray-500 font-medium">Net Profit/Loss</dt>
                  <dd class={"text-xl font-bold #{pnl_color(@stats.rogue.net_pnl)}"}>
                    <%= format_pnl(@stats.rogue.net_pnl) %> ROGUE
                  </dd>
                </div>
              </dl>
            </div>
          </div>

          <!-- Per-Difficulty Breakdowns -->
          <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
            <!-- BUX Per-Difficulty Breakdown -->
            <%= if @stats.bux.bets_per_difficulty do %>
              <div class="bg-white rounded-lg shadow p-6">
                <div class="flex items-center gap-2 mb-4">
                  <span class="text-xl">🔵</span>
                  <h2 class="text-lg font-haas_medium_65">BUX Per-Difficulty</h2>
                </div>

                <div class="overflow-x-auto">
                  <table class="w-full">
                    <thead class="bg-gray-50">
                      <tr>
                        <th class="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                          Difficulty
                        </th>
                        <th class="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                          Mult
                        </th>
                        <th class="px-3 py-2 text-right text-xs font-medium text-gray-500 uppercase">
                          Bets
                        </th>
                        <th class="px-3 py-2 text-right text-xs font-medium text-gray-500 uppercase">
                          P/L
                        </th>
                      </tr>
                    </thead>
                    <tbody class="divide-y divide-gray-200">
                      <%= for {index, label, multiplier} <- difficulty_labels() do %>
                        <% bets = Enum.at(@stats.bux.bets_per_difficulty, index, 0) %>
                        <% pnl = Enum.at(@stats.bux.pnl_per_difficulty, index, 0) %>
                        <tr class={if bets > 0, do: "bg-white", else: "bg-gray-50 text-gray-400"}>
                          <td class="px-3 py-2 text-sm"><%= label %></td>
                          <td class="px-3 py-2 text-sm"><%= multiplier %></td>
                          <td class="px-3 py-2 text-right font-medium">
                            <%= Number.Delimit.number_to_delimited(bets) %>
                          </td>
                          <td class={"px-3 py-2 text-right font-medium #{pnl_color(pnl)}"}>
                            <%= format_pnl(pnl) %>
                          </td>
                        </tr>
                      <% end %>
                    </tbody>
                  </table>
                </div>
              </div>
            <% end %>

            <!-- ROGUE Per-Difficulty Breakdown -->
            <%= if @stats.rogue.bets_per_difficulty do %>
              <div class="bg-white rounded-lg shadow p-6">
                <div class="flex items-center gap-2 mb-4">
                  <span class="text-xl">🟡</span>
                  <h2 class="text-lg font-haas_medium_65">ROGUE Per-Difficulty</h2>
                </div>

                <div class="overflow-x-auto">
                  <table class="w-full">
                    <thead class="bg-gray-50">
                      <tr>
                        <th class="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                          Difficulty
                        </th>
                        <th class="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                          Mult
                        </th>
                        <th class="px-3 py-2 text-right text-xs font-medium text-gray-500 uppercase">
                          Bets
                        </th>
                        <th class="px-3 py-2 text-right text-xs font-medium text-gray-500 uppercase">
                          P/L
                        </th>
                      </tr>
                    </thead>
                    <tbody class="divide-y divide-gray-200">
                      <%= for {index, label, multiplier} <- difficulty_labels() do %>
                        <% bets = Enum.at(@stats.rogue.bets_per_difficulty, index, 0) %>
                        <% pnl = Enum.at(@stats.rogue.pnl_per_difficulty, index, 0) %>
                        <tr class={if bets > 0, do: "bg-white", else: "bg-gray-50 text-gray-400"}>
                          <td class="px-3 py-2 text-sm"><%= label %></td>
                          <td class="px-3 py-2 text-sm"><%= multiplier %></td>
                          <td class="px-3 py-2 text-right font-medium">
                            <%= Number.Delimit.number_to_delimited(bets) %>
                          </td>
                          <td class={"px-3 py-2 text-right font-medium #{pnl_color(pnl)}"}>
                            <%= format_pnl(pnl) %>
                          </td>
                        </tr>
                      <% end %>
                    </tbody>
                  </table>
                </div>
              </div>
            <% end %>
          </div>

          <!-- Combined Summary -->
          <div class="mt-6 bg-gray-50 rounded-lg p-6">
            <h3 class="text-lg font-haas_medium_65 mb-4">Combined Summary</h3>
            <div class="grid grid-cols-3 gap-6">
              <div class="text-center">
                <dt class="text-sm text-gray-500">Total Bets</dt>
                <dd class="text-2xl font-bold">
                  <%= Number.Delimit.number_to_delimited(@stats.combined.total_bets) %>
                </dd>
              </div>
              <div class="text-center">
                <dt class="text-sm text-gray-500">Total Wins</dt>
                <dd class="text-2xl font-bold text-green-600">
                  <%= Number.Delimit.number_to_delimited(@stats.combined.total_wins) %>
                </dd>
              </div>
              <div class="text-center">
                <dt class="text-sm text-gray-500">Total Losses</dt>
                <dd class="text-2xl font-bold text-red-600">
                  <%= Number.Delimit.number_to_delimited(@stats.combined.total_losses) %>
                </dd>
              </div>
            </div>
          </div>
        <% else %>
          <div class="bg-white rounded-lg shadow p-8 text-center">
            <p class="text-gray-500">No stats found for this player.</p>
            <p class="text-sm text-gray-400 mt-2">
              This could mean the player has never placed a bet or there was an error fetching data.
            </p>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end
end
