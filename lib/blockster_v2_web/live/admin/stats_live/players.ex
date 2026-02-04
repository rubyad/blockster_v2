defmodule BlocksterV2Web.Admin.StatsLive.Players do
  @moduledoc """
  Admin page listing all BuxBooster players with their betting statistics.
  Supports pagination, sorting, and search by wallet address.
  """
  use BlocksterV2Web, :live_view

  alias BlocksterV2.BuxBoosterStats

  @per_page 50

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(
        page_title: "Player Stats",
        players: [],
        page: 1,
        total_pages: 1,
        total_count: 0,
        sort_by: :total_bets,
        sort_order: :desc,
        search: "",
        loading: true
      )

    if connected?(socket) do
      send(self(), :load_players)
    end

    {:ok, socket}
  end

  @impl true
  def handle_info(:load_players, socket) do
    socket = load_players_async(socket)
    {:noreply, socket}
  end

  @impl true
  def handle_async(:load_players, {:ok, {:ok, result}}, socket) do
    {:noreply,
     socket
     |> assign(
       players: result.players,
       total_count: result.total_count,
       total_pages: result.total_pages,
       loading: false
     )}
  end

  def handle_async(:load_players, {:ok, {:error, _reason}}, socket) do
    {:noreply, assign(socket, loading: false)}
  end

  def handle_async(:load_players, {:exit, _reason}, socket) do
    {:noreply, assign(socket, loading: false)}
  end

  @impl true
  def handle_event("sort", %{"field" => field}, socket) do
    field_atom = String.to_existing_atom(field)

    # Toggle sort order if clicking same field, otherwise default to desc
    new_order =
      if socket.assigns.sort_by == field_atom do
        if socket.assigns.sort_order == :desc, do: :asc, else: :desc
      else
        :desc
      end

    socket =
      socket
      |> assign(sort_by: field_atom, sort_order: new_order, loading: true)
      |> load_players_async()

    {:noreply, socket}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    socket =
      socket
      |> assign(search: query, page: 1, loading: true)
      |> load_players_async()

    {:noreply, socket}
  end

  @impl true
  def handle_event("page", %{"page" => page}, socket) do
    page_num = String.to_integer(page)

    socket =
      socket
      |> assign(page: page_num, loading: true)
      |> load_players_async()

    {:noreply, socket}
  end

  defp load_players_async(socket) do
    %{page: page, sort_by: sort_by, sort_order: sort_order, search: _search} = socket.assigns

    start_async(socket, :load_players, fn ->
      BuxBoosterStats.get_all_player_stats(
        page: page,
        per_page: @per_page,
        sort_by: sort_by,
        sort_order: sort_order
      )
    end)
  end

  # ============ Helper Functions ============

  # Format wei to human-readable with abbreviation
  defp format_token(wei) when is_integer(wei) do
    amount = wei / 1_000_000_000_000_000_000

    cond do
      amount >= 1_000_000_000 -> "#{Float.round(amount / 1_000_000_000, 2)}B"
      amount >= 1_000_000 -> "#{Float.round(amount / 1_000_000, 2)}M"
      amount >= 1_000 -> "#{Float.round(amount / 1_000, 2)}K"
      true -> Number.Delimit.number_to_delimited(Float.round(amount, 2))
    end
  end

  defp format_token(_), do: "0"

  # Format P/L with + or - prefix and color class
  defp format_pnl(pnl) when is_integer(pnl) do
    amount = pnl / 1_000_000_000_000_000_000

    formatted =
      cond do
        abs(amount) >= 1_000_000 -> "#{Float.round(amount / 1_000_000, 2)}M"
        abs(amount) >= 1_000 -> "#{Float.round(amount / 1_000, 2)}K"
        true -> Number.Delimit.number_to_delimited(Float.round(amount, 2))
      end

    if pnl >= 0, do: "+#{formatted}", else: formatted
  end

  defp format_pnl(_), do: "0"

  defp pnl_color(pnl) when is_integer(pnl) and pnl >= 0, do: "text-green-600"
  defp pnl_color(pnl) when is_integer(pnl) and pnl < 0, do: "text-red-600"
  defp pnl_color(_), do: ""

  # Short wallet address display
  defp short_address(address) when is_binary(address) do
    "#{String.slice(address, 0..5)}...#{String.slice(address, -4..-1)}"
  end

  defp short_address(_), do: ""

  # Sort indicator arrow
  defp sort_indicator(current_field, current_order, field) when current_field == field do
    if current_order == :asc, do: "↑", else: "↓"
  end

  defp sort_indicator(_, _, _), do: ""

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 pt-24 max-w-7xl mx-auto">
      <!-- Header -->
      <div class="flex justify-between items-center mb-6">
        <div>
          <h1 class="text-2xl font-haas_medium_65">Player Stats</h1>
          <p class="text-sm text-gray-500">
            Showing <%= length(@players) %> of <%= Number.Delimit.number_to_delimited(@total_count) %> players
          </p>
        </div>
        <div class="flex items-center gap-4">
          <.link navigate={~p"/admin/stats"} class="text-blue-600 hover:underline cursor-pointer">
            ← Back to Global Stats
          </.link>
        </div>
      </div>

      <!-- Search (commented out for now - would need player list filtering)
      <form phx-change="search" phx-debounce="300" class="mb-6">
        <input
          type="text"
          name="query"
          value={@search}
          placeholder="Search wallet address..."
          class="px-4 py-2 border rounded-lg w-64"
        />
      </form>
      -->

      <!-- Table -->
      <div class="bg-white rounded-lg shadow overflow-hidden">
        <%= if @loading do %>
          <div class="p-8 text-center">
            <div class="animate-spin inline-block w-8 h-8 border-4 border-blue-600 border-t-transparent rounded-full"></div>
            <p class="mt-2 text-gray-500">Loading player stats...</p>
          </div>
        <% else %>
          <div class="overflow-x-auto">
            <table class="w-full">
              <thead class="bg-gray-50">
                <tr>
                  <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                    Wallet
                  </th>
                  <th
                    class="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase cursor-pointer hover:bg-gray-100"
                    phx-click="sort"
                    phx-value-field="total_bets"
                  >
                    Total Bets <%= sort_indicator(@sort_by, @sort_order, :total_bets) %>
                  </th>
                  <th
                    class="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase cursor-pointer hover:bg-gray-100"
                    phx-click="sort"
                    phx-value-field="bux_wagered"
                  >
                    BUX Wagered <%= sort_indicator(@sort_by, @sort_order, :bux_wagered) %>
                  </th>
                  <th
                    class="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase cursor-pointer hover:bg-gray-100"
                    phx-click="sort"
                    phx-value-field="bux_pnl"
                  >
                    BUX P/L <%= sort_indicator(@sort_by, @sort_order, :bux_pnl) %>
                  </th>
                  <th
                    class="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase cursor-pointer hover:bg-gray-100"
                    phx-click="sort"
                    phx-value-field="rogue_wagered"
                  >
                    ROGUE Wagered <%= sort_indicator(@sort_by, @sort_order, :rogue_wagered) %>
                  </th>
                  <th
                    class="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase cursor-pointer hover:bg-gray-100"
                    phx-click="sort"
                    phx-value-field="rogue_pnl"
                  >
                    ROGUE P/L <%= sort_indicator(@sort_by, @sort_order, :rogue_pnl) %>
                  </th>
                  <th class="px-4 py-3"></th>
                </tr>
              </thead>
              <tbody class="divide-y divide-gray-200">
                <%= for player <- @players do %>
                  <tr class="hover:bg-gray-50">
                    <td class="px-4 py-3">
                      <a
                        href={"https://roguescan.io/address/#{player.wallet}"}
                        target="_blank"
                        class="text-blue-600 hover:underline font-mono text-sm cursor-pointer"
                      >
                        <%= short_address(player.wallet) %>
                      </a>
                    </td>
                    <td class="px-4 py-3 text-right font-medium">
                      <%= Number.Delimit.number_to_delimited(player.combined.total_bets, precision: 0) %>
                    </td>
                    <td class="px-4 py-3 text-right">
                      <%= format_token(player.bux.total_wagered) %>
                    </td>
                    <td class={"px-4 py-3 text-right font-medium #{pnl_color(player.bux.net_pnl)}"}>
                      <%= format_pnl(player.bux.net_pnl) %>
                    </td>
                    <td class="px-4 py-3 text-right">
                      <%= format_token(player.rogue.total_wagered) %>
                    </td>
                    <td class={"px-4 py-3 text-right font-medium #{pnl_color(player.rogue.net_pnl)}"}>
                      <%= format_pnl(player.rogue.net_pnl) %>
                    </td>
                    <td class="px-4 py-3 text-right">
                      <.link
                        navigate={~p"/admin/stats/players/#{player.wallet}"}
                        class="text-blue-600 hover:underline cursor-pointer"
                      >
                        Details →
                      </.link>
                    </td>
                  </tr>
                <% end %>

                <%= if Enum.empty?(@players) do %>
                  <tr>
                    <td colspan="7" class="px-4 py-8 text-center text-gray-500">
                      No players found. The player index may still be building.
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        <% end %>
      </div>

      <!-- Pagination -->
      <%= if @total_pages > 1 do %>
        <div class="mt-4 flex justify-center items-center gap-2">
          <%= if @page > 1 do %>
            <button
              phx-click="page"
              phx-value-page={@page - 1}
              class="px-3 py-1 rounded bg-gray-200 hover:bg-gray-300 cursor-pointer"
            >
              ← Prev
            </button>
          <% end %>

          <%= for page_num <- pagination_range(@page, @total_pages) do %>
            <%= if page_num == :ellipsis do %>
              <span class="px-2">...</span>
            <% else %>
              <button
                phx-click="page"
                phx-value-page={page_num}
                class={"px-3 py-1 rounded cursor-pointer #{if page_num == @page, do: "bg-blue-600 text-white", else: "bg-gray-200 hover:bg-gray-300"}"}
              >
                <%= page_num %>
              </button>
            <% end %>
          <% end %>

          <%= if @page < @total_pages do %>
            <button
              phx-click="page"
              phx-value-page={@page + 1}
              class="px-3 py-1 rounded bg-gray-200 hover:bg-gray-300 cursor-pointer"
            >
              Next →
            </button>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  # Generate pagination range with ellipsis for large page counts
  defp pagination_range(current, total) when total <= 7 do
    1..total |> Enum.to_list()
  end

  defp pagination_range(current, total) do
    cond do
      current <= 4 ->
        [1, 2, 3, 4, 5, :ellipsis, total]

      current >= total - 3 ->
        [1, :ellipsis, total - 4, total - 3, total - 2, total - 1, total]

      true ->
        [1, :ellipsis, current - 1, current, current + 1, :ellipsis, total]
    end
  end
end
