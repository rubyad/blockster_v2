# PlinkoLive UI Specification

> Complete implementation spec for the Plinko game page.
> Includes LiveView module, HEEx template, ball animation JS hook, and on-chain JS hook.
> Follows BUX Booster patterns exactly — same family of games, same dark zinc theme.

---

## 1. LiveView Module: `lib/blockster_v2_web/live/plinko_live.ex`

```elixir
defmodule BlocksterV2Web.PlinkoLive do
  use BlocksterV2Web, :live_view
  require Logger

  alias BlocksterV2.{PlinkoGame, BuxMinter, EngagementTracker, PriceTracker}
  alias BlocksterV2.HubLogoCache

  @payout_tables PlinkoGame.payout_tables()

  # 9 configs: {rows, risk} -> config_index
  @config_map %{
    {8, :low} => 0, {8, :medium} => 1, {8, :high} => 2,
    {12, :low} => 3, {12, :medium} => 4, {12, :high} => 5,
    {16, :low} => 6, {16, :medium} => 7, {16, :high} => 8
  }

  @row_options [8, 12, 16]
  @risk_options [:low, :medium, :high]

  # ============================================================
  # Mount
  # ============================================================

  @impl true
  def mount(_params, _session, socket) do
    current_user = socket.assigns[:current_user]
    token_logos = HubLogoCache.get_all_logos()
    tokens = ["ROGUE", "BUX"]

    if current_user do
      wallet_address = current_user.smart_wallet_address

      # Sync balances on connected mount
      if wallet_address != nil and connected?(socket) do
        BuxMinter.sync_user_balances_async(current_user.id, wallet_address)
      end

      balances = EngagementTracker.get_user_token_balances(current_user.id)

      # Init on-chain game on connected mount only (double-mount protection)
      socket = if wallet_address != nil and connected?(socket) do
        Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "bux_balance:#{current_user.id}")
        Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "plinko_settlement:#{current_user.id}")
        Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "token_prices")

        socket
        |> assign(:onchain_ready, false)
        |> assign(:wallet_address, wallet_address)
        |> assign(:onchain_initializing, true)
        |> assign(:init_retry_count, 0)
        |> start_async(:init_onchain_game, fn ->
          PlinkoGame.get_or_init_game(current_user.id, wallet_address)
        end)
      else
        socket
        |> assign(:onchain_ready, false)
        |> assign(:wallet_address, wallet_address)
        |> assign(:onchain_initializing, false)
        |> assign(:init_retry_count, 0)
      end

      error_msg = if wallet_address, do: nil, else: "No wallet connected"
      default_config = 0  # 8-Low

      socket =
        socket
        |> assign(page_title: "Plinko")
        |> assign(current_user: current_user)
        |> assign(balances: balances)
        |> assign(tokens: tokens)
        |> assign(token_logos: token_logos)
        # Game config
        |> assign(selected_token: "BUX")
        |> assign(header_token: "BUX")
        |> assign(selected_rows: 8)
        |> assign(selected_risk: :low)
        |> assign(config_index: default_config)
        |> assign(bet_amount: 10)
        |> assign(current_bet: 10)
        |> assign(payout_table: Map.get(@payout_tables, default_config, []))
        # Game state
        |> assign(game_state: :idle)
        |> assign(ball_path: [])
        |> assign(landing_position: nil)
        |> assign(payout: 0)
        |> assign(payout_multiplier: nil)
        |> assign(won: nil)
        |> assign(confetti_pieces: [])
        |> assign(error_message: error_msg)
        # On-chain state
        |> assign(onchain_game_id: nil)
        |> assign(commitment_hash: nil)
        |> assign(bet_tx: nil)
        |> assign(bet_id: nil)
        |> assign(settlement_tx: nil)
        # House / balance
        |> assign(house_balance: 0.0)
        |> assign(max_bet: 0)
        |> assign(rogue_usd_price: PriceTracker.get_rogue_price())
        # UI state
        |> assign(show_token_dropdown: false)
        |> assign(show_fairness_modal: false)
        |> assign(fairness_game: nil)
        |> assign(recent_games: [])
        |> assign(games_offset: 0)
        |> assign(games_loading: connected?(socket))
        |> assign(show_provably_fair: false)
        |> assign(nonce: 0)
        |> assign(server_seed_hash: nil)

      # Async operations on connected mount
      socket = if connected?(socket) do
        user_id = current_user.id
        socket
        |> start_async(:fetch_house_balance, fn ->
          BuxMinter.bux_bankroll_house_info()
        end)
        |> start_async(:load_recent_games, fn ->
          PlinkoGame.load_recent_games(user_id, limit: 30)
        end)
      else
        socket
      end

      {:ok, socket}
    else
      # Not logged in — guest view with zero balances
      socket =
        socket
        |> assign(page_title: "Plinko")
        |> assign(current_user: nil)
        |> assign(balances: %{"BUX" => 0, "ROGUE" => 0})
        |> assign(tokens: tokens)
        |> assign(token_logos: token_logos)
        |> assign(selected_token: "BUX")
        |> assign(header_token: "BUX")
        |> assign(selected_rows: 8)
        |> assign(selected_risk: :low)
        |> assign(config_index: 0)
        |> assign(bet_amount: 10)
        |> assign(current_bet: 10)
        |> assign(payout_table: Map.get(@payout_tables, 0, []))
        |> assign(game_state: :idle)
        |> assign(ball_path: [])
        |> assign(landing_position: nil)
        |> assign(payout: 0)
        |> assign(payout_multiplier: nil)
        |> assign(won: nil)
        |> assign(confetti_pieces: [])
        |> assign(error_message: nil)
        |> assign(onchain_ready: false)
        |> assign(onchain_initializing: false)
        |> assign(onchain_game_id: nil)
        |> assign(commitment_hash: nil)
        |> assign(wallet_address: nil)
        |> assign(init_retry_count: 0)
        |> assign(bet_tx: nil)
        |> assign(bet_id: nil)
        |> assign(settlement_tx: nil)
        |> assign(house_balance: 0.0)
        |> assign(max_bet: 0)
        |> assign(rogue_usd_price: PriceTracker.get_rogue_price())
        |> assign(show_token_dropdown: false)
        |> assign(show_fairness_modal: false)
        |> assign(fairness_game: nil)
        |> assign(recent_games: [])
        |> assign(games_offset: 0)
        |> assign(games_loading: false)
        |> assign(show_provably_fair: false)
        |> assign(nonce: 0)
        |> assign(server_seed_hash: nil)

      # Subscribe to prices for guests too
      if connected?(socket) do
        Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "token_prices")
      end

      socket = start_async(socket, :fetch_house_balance, fn ->
        BuxMinter.bux_bankroll_house_info()
      end)

      {:ok, socket}
    end
  end

  # ============================================================
  # Render
  # ============================================================

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="plinko-game"
      class="min-h-screen bg-zinc-950"
      phx-hook="PlinkoOnchain"
      data-game-id={@onchain_game_id}
      data-commitment-hash={@commitment_hash}
    >
      <div class="max-w-2xl mx-auto px-3 sm:px-4 pt-6 sm:pt-24 pb-8">

        <!-- Config Selector: Rows + Risk -->
        <div class="bg-zinc-900 rounded-xl border border-zinc-800 mb-4 p-3">
          <!-- Row Selector -->
          <div class="flex items-center gap-2 mb-2">
            <span class="text-xs text-zinc-500 w-12 shrink-0">Rows</span>
            <div class="flex gap-1.5 flex-1">
              <%= for rows <- [8, 12, 16] do %>
                <button
                  type="button"
                  phx-click="select_rows"
                  phx-value-rows={rows}
                  disabled={@game_state not in [:idle, :result]}
                  class={"flex-1 py-2 rounded-lg text-sm font-medium cursor-pointer transition-colors disabled:cursor-not-allowed #{if @selected_rows == rows, do: "bg-[#CAFC00] text-black", else: "bg-zinc-800 text-zinc-400 hover:bg-zinc-700"}"}
                >
                  <%= rows %>
                </button>
              <% end %>
            </div>
          </div>
          <!-- Risk Selector -->
          <div class="flex items-center gap-2">
            <span class="text-xs text-zinc-500 w-12 shrink-0">Risk</span>
            <div class="flex gap-1.5 flex-1">
              <%= for risk <- [:low, :medium, :high] do %>
                <button
                  type="button"
                  phx-click="select_risk"
                  phx-value-risk={Atom.to_string(risk)}
                  disabled={@game_state not in [:idle, :result]}
                  class={"flex-1 py-2 rounded-lg text-sm font-medium cursor-pointer transition-colors disabled:cursor-not-allowed #{if @selected_risk == risk, do: "bg-[#CAFC00] text-black", else: "bg-zinc-800 text-zinc-400 hover:bg-zinc-700"}"}
                >
                  <%= String.capitalize(Atom.to_string(risk)) %>
                </button>
              <% end %>
            </div>
          </div>
        </div>

        <!-- Main Game Card -->
        <div class={"bg-zinc-900 rounded-2xl border border-zinc-800 overflow-hidden #{game_card_height(@selected_rows)}"}>

          <%= if @game_state == :idle do %>
            <!-- ========== IDLE STATE ========== -->
            <div class="p-3 sm:p-4 flex flex-col h-full">

              <!-- Bet Stake Input -->
              <div class="mb-3">
                <label class="block text-sm font-haas_medium_65 text-white mb-1.5">Bet Stake</label>
                <div class="flex gap-1.5">
                  <!-- Amount Input -->
                  <div class="flex-1 relative min-w-0">
                    <input
                      type="number"
                      value={@bet_amount}
                      phx-keyup="update_bet_amount"
                      phx-debounce="100"
                      min="1"
                      class={"w-full bg-zinc-800 border border-zinc-700 rounded-lg pl-3 py-2.5 text-white text-lg font-medium focus:outline-none focus:border-[#CAFC00] focus:ring-1 focus:ring-[#CAFC00] [appearance:textfield] [&::-webkit-outer-spin-button]:appearance-none [&::-webkit-inner-spin-button]:appearance-none #{if @selected_token == "ROGUE" && @rogue_usd_price, do: "pr-32", else: "pr-20"}"}
                    />
                    <div class="absolute right-2 top-1/2 -translate-y-1/2 flex items-center gap-1">
                      <%= if @selected_token == "ROGUE" && @rogue_usd_price do %>
                        <span class="text-zinc-500 text-[10px] mr-1">~<%= format_usd(@rogue_usd_price, @bet_amount) %></span>
                      <% end %>
                      <button type="button" phx-click="halve_bet" class="px-1.5 py-1 bg-zinc-700 text-zinc-300 rounded text-xs font-medium hover:bg-zinc-600 cursor-pointer">1/2</button>
                      <button type="button" phx-click="double_bet" class="px-1.5 py-1 bg-zinc-700 text-zinc-300 rounded text-xs font-medium hover:bg-zinc-600 cursor-pointer">2x</button>
                    </div>
                  </div>
                  <!-- Token Dropdown -->
                  <div class="relative flex-shrink-0" id="token-dropdown-wrapper" phx-click-away="hide_token_dropdown">
                    <button
                      type="button"
                      phx-click="toggle_token_dropdown"
                      class="h-full px-3 bg-zinc-800 border border-zinc-700 rounded-lg flex items-center gap-1.5 hover:bg-zinc-700 transition-all cursor-pointer"
                    >
                      <img src={Map.get(@token_logos, @selected_token, "https://ik.imagekit.io/blockster/blockster-icon.png")} alt={@selected_token} class="w-4 h-4 rounded-full" />
                      <span class="font-medium text-white text-sm"><%= @selected_token %></span>
                      <svg class="w-3 h-3 text-zinc-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
                      </svg>
                    </button>
                    <%= if @show_token_dropdown do %>
                      <div class="absolute right-0 top-full mt-1 bg-zinc-800 border border-zinc-700 rounded-lg shadow-lg z-50 w-max min-w-[180px]">
                        <%= for token <- @tokens do %>
                          <button
                            type="button"
                            phx-click="select_token"
                            phx-value-token={token}
                            class={"w-full px-4 py-3 flex items-center gap-3 hover:bg-zinc-700 cursor-pointer first:rounded-t-lg last:rounded-b-lg #{if @selected_token == token, do: "bg-zinc-700"}"}
                          >
                            <img src={Map.get(@token_logos, token, "https://ik.imagekit.io/blockster/blockster-icon.png")} alt={token} class="w-5 h-5 rounded-full" />
                            <span class="font-medium text-white text-sm flex-1 text-left"><%= token %></span>
                            <span class="text-zinc-400 text-sm"><%= format_balance(Map.get(@balances, token, 0)) %></span>
                          </button>
                        <% end %>
                      </div>
                    <% end %>
                  </div>
                </div>
                <!-- Balance & Max Info -->
                <div class="mt-1.5 flex items-center justify-between text-[10px] sm:text-xs">
                  <span class="text-zinc-500">
                    <%= format_balance(Map.get(@balances, @selected_token, 0)) %>
                    <img src={Map.get(@token_logos, @selected_token, "https://ik.imagekit.io/blockster/blockster-icon.png")} alt="" class="w-3 h-3 rounded-full inline ml-0.5" />
                  </span>
                  <button type="button" phx-click="set_max_bet" class="text-zinc-500 hover:text-[#CAFC00] cursor-pointer">
                    Max: <span class="text-zinc-400"><%= format_integer(@max_bet) %></span>
                  </button>
                </div>
              </div>

              <!-- Error Message -->
              <%= if @error_message do %>
                <div class="bg-red-900/30 border border-red-800 rounded-lg p-2 mb-3 text-red-400 text-xs">
                  <%= @error_message %>
                </div>
              <% end %>

              <!-- Plinko Board (SVG) -->
              <div class="flex-1 flex items-center justify-center min-h-0">
                <%= render_plinko_board(assigns) %>
              </div>

              <!-- Provably Fair + Drop Button -->
              <div class="mt-3">
                <!-- Provably Fair Link -->
                <div class="flex items-center justify-between mb-2">
                  <div class="relative">
                    <button
                      type="button"
                      phx-click="toggle_provably_fair"
                      class="text-xs text-zinc-500 cursor-pointer hover:text-zinc-300 flex items-center gap-1"
                    >
                      <svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
                      </svg>
                      Provably Fair
                    </button>
                    <%= if @show_provably_fair do %>
                      <div
                        phx-click-away="close_provably_fair"
                        class="absolute left-0 bottom-full mb-1 z-50 w-72 bg-zinc-800 rounded-lg p-3 border border-zinc-700 shadow-lg"
                      >
                        <p class="text-[10px] text-zinc-400 mb-2">
                          This hash commits the server to a result BEFORE you place your bet.
                        </p>
                        <code class="text-[10px] font-mono bg-zinc-900 px-2 py-1.5 rounded border border-zinc-700 text-zinc-300 block break-all">
                          <%= @server_seed_hash || "Loading..." %>
                        </code>
                        <p class="text-[10px] text-zinc-500 mt-1">Game #<%= @nonce %></p>
                      </div>
                    <% end %>
                  </div>
                  <!-- Potential payout preview -->
                  <div class="text-xs text-zinc-500">
                    Max win: <span class="text-[#CAFC00] font-medium"><%= format_max_payout(@bet_amount, @payout_table) %></span>
                  </div>
                </div>
                <!-- Drop Ball Button -->
                <button
                  type="button"
                  phx-click="drop_ball"
                  disabled={!@onchain_ready or @onchain_initializing or !@current_user}
                  class="w-full py-3.5 bg-[#CAFC00] text-black font-haas_medium_65 text-base rounded-xl hover:bg-[#b8e600] transition-all cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  <%= cond do %>
                    <% @onchain_initializing -> %>
                      <span class="flex items-center justify-center gap-2">
                        <div class="w-4 h-4 border-2 border-black/30 border-t-black rounded-full animate-spin"></div>
                        Initializing...
                      </span>
                    <% !@current_user -> %>
                      Sign In to Play
                    <% true -> %>
                      Drop Ball
                  <% end %>
                </button>
              </div>
            </div>

          <% else %>
            <!-- ========== ACTIVE GAME STATES (dropping / result) ========== -->
            <div class="p-3 sm:p-4 flex flex-col h-full">

              <!-- Bet info bar -->
              <div class="flex items-center justify-between mb-2 text-xs text-zinc-400">
                <span>
                  <span class="text-zinc-500">Bet:</span>
                  <span class="text-white font-medium"><%= format_balance(@current_bet) %></span>
                  <img src={Map.get(@token_logos, @selected_token, "https://ik.imagekit.io/blockster/blockster-icon.png")} alt="" class="w-3 h-3 rounded-full inline ml-0.5" />
                </span>
                <span>
                  <span class="text-zinc-500">Config:</span>
                  <span class="text-white"><%= @selected_rows %>-<%= String.capitalize(Atom.to_string(@selected_risk)) %></span>
                </span>
              </div>

              <!-- Plinko Board with ball animation -->
              <div class="flex-1 flex items-center justify-center min-h-0">
                <%= render_plinko_board(assigns) %>
              </div>

              <%= if @game_state == :dropping do %>
                <!-- Awaiting animation -->
                <div class="mt-3 text-center">
                  <p class="text-sm text-zinc-400 animate-pulse">Ball dropping...</p>
                </div>
              <% end %>

              <%= if @game_state == :result do %>
                <!-- Full-page Confetti (win only) -->
                <%= if @won and length(@confetti_pieces) > 0 do %>
                  <div class="confetti-fullpage fixed inset-0 pointer-events-none z-50 overflow-hidden">
                    <%= for piece <- @confetti_pieces do %>
                      <div
                        class="confetti-emoji"
                        style={"--x-start: #{piece.x_start}%; --x-end: #{piece.x_end}%; --x-drift: #{piece.x_drift}vw; --rotation: #{piece.rotation}deg; --delay: #{piece.delay}ms; --duration: #{piece.duration}ms;"}
                      ><%= piece.emoji %></div>
                    <% end %>
                  </div>
                <% end %>

                <!-- Result Display -->
                <div class="mt-3">
                  <div class="text-center mb-3">
                    <%= if @won do %>
                      <div class="flex items-center justify-center gap-3">
                        <span class="text-2xl animate-bounce">🎉</span>
                        <div>
                          <p class="text-xl font-haas_medium_65 text-[#CAFC00]"><%= format_multiplier_display(@payout_multiplier) %></p>
                          <p class="text-lg text-green-400 font-medium flex items-center justify-center gap-1">
                            <img src={Map.get(@token_logos, @selected_token, "https://ik.imagekit.io/blockster/blockster-icon.png")} alt="" class="w-4 h-4 rounded-full" />
                            +<%= format_balance(@payout - @current_bet) %>
                          </p>
                        </div>
                        <span class="text-2xl animate-bounce">🎉</span>
                      </div>
                    <% else %>
                      <p class="text-xl font-haas_medium_65 text-zinc-400"><%= format_multiplier_display(@payout_multiplier) %></p>
                      <p class="text-lg text-red-400 font-medium flex items-center justify-center gap-1">
                        <img src={Map.get(@token_logos, @selected_token, "https://ik.imagekit.io/blockster/blockster-icon.png")} alt="" class="w-4 h-4 rounded-full" />
                        -<%= format_balance(@current_bet - @payout) %>
                      </p>
                    <% end %>
                  </div>

                  <!-- Action Buttons -->
                  <div class="flex items-center justify-center gap-3">
                    <button
                      type="button"
                      phx-click="reset_game"
                      class="px-6 py-2.5 bg-[#CAFC00] text-black font-haas_medium_65 text-sm rounded-xl hover:bg-[#b8e600] transition-all cursor-pointer"
                    >
                      Play Again
                    </button>
                    <button
                      type="button"
                      phx-click="show_fairness_modal"
                      phx-value-game-id={@onchain_game_id}
                      class="px-4 py-2.5 bg-zinc-800 text-zinc-300 text-sm rounded-xl hover:bg-zinc-700 cursor-pointer flex items-center gap-1"
                    >
                      <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
                      </svg>
                      Verify
                    </button>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>

        <!-- Game History Table -->
        <div class="mt-4 sm:mt-6">
          <div class="bg-zinc-900 rounded-xl border border-zinc-800 p-3 sm:p-4">
            <h3 class="text-xs sm:text-sm font-haas_medium_65 text-white mb-2 sm:mb-3">Plinko Games</h3>
            <%= if @games_loading do %>
              <div class="text-center py-4 text-zinc-500 text-xs">Loading games...</div>
            <% end %>
            <%= if length(@recent_games) > 0 do %>
              <div id="plinko-games-scroll" class="overflow-x-auto overflow-y-auto max-h-72 sm:max-h-96 relative" phx-hook="InfiniteScroll">
                <table class="w-full text-[10px] sm:text-xs min-w-[550px]">
                  <thead class="sticky top-0 z-20 bg-zinc-900">
                    <tr class="border-b-2 border-zinc-700">
                      <th class="text-left py-1.5 px-1.5 text-zinc-500 font-medium">ID</th>
                      <th class="text-left py-1.5 px-1.5 text-zinc-500 font-medium">Bet</th>
                      <th class="text-left py-1.5 px-1.5 text-zinc-500 font-medium">Config</th>
                      <th class="text-left py-1.5 px-1.5 text-zinc-500 font-medium">Landing</th>
                      <th class="text-left py-1.5 px-1.5 text-zinc-500 font-medium">Mult</th>
                      <th class="text-left py-1.5 px-1.5 text-zinc-500 font-medium">P/L</th>
                      <th class="text-left py-1.5 px-1.5 text-zinc-500 font-medium">Verify</th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for game <- @recent_games do %>
                      <tr class={"border-b border-zinc-800 #{if game.won, do: "bg-green-900/10", else: "bg-red-900/10"}"}>
                        <td class="py-1.5 px-1.5">
                          <%= if game.commitment_tx do %>
                            <a href={"https://roguescan.io/tx/#{game.commitment_tx}?tab=logs"} target="_blank" class="text-blue-400 hover:underline cursor-pointer font-mono">
                              #<%= game.nonce %>
                            </a>
                          <% else %>
                            <span class="font-mono text-zinc-500">#<%= game.nonce %></span>
                          <% end %>
                        </td>
                        <td class="py-1.5 px-1.5">
                          <div class="flex items-center gap-1">
                            <img src={Map.get(@token_logos, game.token_type, "https://ik.imagekit.io/blockster/blockster-icon.png")} alt="" class="w-3 h-3 rounded-full" />
                            <span class="text-white"><%= format_integer(game.bet_amount) %></span>
                          </div>
                        </td>
                        <td class="py-1.5 px-1.5 text-zinc-400"><%= game.rows %>-<%= String.capitalize(to_string(game.risk)) %></td>
                        <td class="py-1.5 px-1.5 text-zinc-400">Slot <%= game.landing_position %></td>
                        <td class="py-1.5 px-1.5 text-white font-medium"><%= game.multiplier %>x</td>
                        <td class="py-1.5 px-1.5">
                          <%= if game.won do %>
                            <span class="text-green-400 font-medium">+<%= format_balance(game.payout - game.bet_amount) %></span>
                          <% else %>
                            <span class="text-red-400 font-medium">-<%= format_balance(game.bet_amount - (game.payout || 0)) %></span>
                          <% end %>
                        </td>
                        <td class="py-1.5 px-1.5">
                          <%= if game.server_seed do %>
                            <button type="button" phx-click="show_fairness_modal" phx-value-game-id={game.game_id} class="text-blue-400 hover:underline cursor-pointer">
                              &#10003;
                            </button>
                          <% else %>
                            <span class="text-zinc-600">-</span>
                          <% end %>
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            <% else %>
              <%= if !@games_loading do %>
                <p class="text-zinc-500 text-xs">No games played yet</p>
              <% end %>
            <% end %>
          </div>
        </div>
      </div>
    </div>

    <!-- Fairness Verification Modal -->
    <%= if @show_fairness_modal and @fairness_game do %>
      <div class="fixed inset-0 bg-black/60 flex items-end sm:items-center justify-center z-50 p-0 sm:p-4" phx-click="hide_fairness_modal">
        <div class="bg-zinc-900 rounded-none sm:rounded-2xl w-full sm:max-w-lg max-h-[100vh] sm:max-h-[90vh] overflow-y-auto shadow-xl border border-zinc-800" phx-click="stop_propagation">
          <!-- Header -->
          <div class="p-3 sm:p-4 border-b border-zinc-800 flex items-center justify-between sticky top-0 z-10 bg-zinc-900 sm:rounded-t-2xl">
            <div class="flex items-center gap-2">
              <svg class="w-4 h-4 text-[#CAFC00]" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
              </svg>
              <h2 class="text-base font-haas_medium_65 text-white">Provably Fair Verification</h2>
            </div>
            <button type="button" phx-click="hide_fairness_modal" class="text-zinc-500 hover:text-zinc-300 cursor-pointer">
              <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>
          <!-- Content -->
          <div class="p-3 sm:p-4 space-y-3">
            <!-- Bet Details -->
            <div class="bg-zinc-800/50 rounded-lg p-3 border border-zinc-700">
              <p class="text-xs font-medium text-zinc-300 mb-2">Bet Details</p>
              <div class="grid grid-cols-2 gap-1.5 text-xs">
                <span class="text-zinc-500">Config:</span>
                <span class="text-white"><%= @fairness_game.config_label %></span>
                <span class="text-zinc-500">Bet Amount:</span>
                <span class="text-white"><%= @fairness_game.bet_amount %> <%= @fairness_game.token %></span>
                <span class="text-zinc-500">Landing:</span>
                <span class="text-white">Slot <%= @fairness_game.landing_position %></span>
                <span class="text-zinc-500">Multiplier:</span>
                <span class="text-[#CAFC00]"><%= @fairness_game.multiplier %>x</span>
              </div>
            </div>
            <!-- Seeds -->
            <div class="space-y-2">
              <div>
                <label class="text-xs font-medium text-zinc-400">Server Seed (revealed)</label>
                <code class="mt-1 text-[10px] font-mono bg-zinc-800 px-2 py-1.5 rounded border border-zinc-700 text-zinc-300 block break-all">
                  <%= @fairness_game.server_seed %>
                </code>
              </div>
              <div>
                <label class="text-xs font-medium text-zinc-400">Server Commitment</label>
                <code class="mt-1 text-[10px] font-mono bg-zinc-800 px-2 py-1.5 rounded border border-zinc-700 text-zinc-300 block break-all">
                  <%= @fairness_game.server_seed_hash %>
                </code>
              </div>
              <div>
                <label class="text-xs font-medium text-zinc-400">Client Seed</label>
                <code class="mt-1 text-[10px] font-mono bg-zinc-800 px-2 py-1.5 rounded border border-zinc-700 text-zinc-300 block break-all">
                  <%= @fairness_game.client_seed %>
                </code>
              </div>
              <div>
                <label class="text-xs font-medium text-zinc-400">Combined Seed</label>
                <code class="mt-1 text-[10px] font-mono bg-zinc-800 px-2 py-1.5 rounded border border-zinc-700 text-zinc-300 block break-all">
                  <%= @fairness_game.combined_seed %>
                </code>
              </div>
            </div>
            <!-- Ball Path -->
            <div>
              <label class="text-xs font-medium text-zinc-400">Ball Path (from combined seed bytes)</label>
              <div class="mt-1 flex flex-wrap gap-1">
                <%= for {dir, i} <- Enum.with_index(@fairness_game.ball_path || []) do %>
                  <span class={"px-1.5 py-0.5 rounded text-[10px] font-mono #{if dir == :left, do: "bg-blue-900/30 text-blue-400", else: "bg-amber-900/30 text-amber-400"}"}>
                    <%= i %>:<%= if dir == :left, do: "L", else: "R" %>
                  </span>
                <% end %>
              </div>
            </div>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  # ============================================================
  # SVG Board Rendering
  # ============================================================

  defp render_plinko_board(assigns) do
    assigns = assign(assigns, :board_data, board_data(assigns.selected_rows, assigns.payout_table))

    ~H"""
    <svg
      viewBox={"0 0 400 #{board_height(@selected_rows)}"}
      class="w-full max-w-md"
      id="plinko-board"
      phx-hook="PlinkoBall"
      data-rows={@selected_rows}
      data-game-state={@game_state}
    >
      <!-- Glow filter for ball -->
      <defs>
        <filter id="ball-glow" x="-50%" y="-50%" width="200%" height="200%">
          <feGaussianBlur stdDeviation="3" result="blur" />
          <feMerge>
            <feMergeNode in="blur" />
            <feMergeNode in="SourceGraphic" />
          </feMerge>
        </filter>
      </defs>

      <!-- Pegs -->
      <%= for {x, y} <- @board_data.pegs do %>
        <circle class="plinko-peg" cx={x} cy={y} r={peg_radius(@selected_rows)} fill="#52525b" />
      <% end %>

      <!-- Landing Slots -->
      <%= for {k, x, y, bp} <- @board_data.slots do %>
        <% slot_w = 340 / (@selected_rows + 1) - 2 %>
        <rect
          class="plinko-slot"
          x={x - slot_w / 2}
          y={y}
          width={slot_w}
          height="28"
          fill={slot_color(bp)}
          rx="3"
        />
        <text
          x={x}
          y={y + 17}
          text-anchor="middle"
          fill="white"
          font-size={slot_font_size(@selected_rows)}
          font-weight="bold"
        >
          <%= format_multiplier_bp(bp) %>
        </text>
      <% end %>

      <!-- Ball (hidden until drop) -->
      <circle
        id="plinko-ball"
        cx="200"
        cy="10"
        r={ball_radius(@selected_rows)}
        fill="#CAFC00"
        filter="url(#ball-glow)"
        style="display:none"
      />
    </svg>
    """
  end

  # ============================================================
  # Board Geometry Helpers
  # ============================================================

  defp board_height(8), do: 340
  defp board_height(12), do: 460
  defp board_height(16), do: 580

  defp peg_radius(8), do: 4
  defp peg_radius(12), do: 3
  defp peg_radius(16), do: 2.5

  defp ball_radius(8), do: 8
  defp ball_radius(12), do: 6
  defp ball_radius(16), do: 5

  defp slot_font_size(8), do: "10"
  defp slot_font_size(12), do: "9"
  defp slot_font_size(16), do: "7"

  defp game_card_height(8), do: "h-[520px] sm:h-[560px]"
  defp game_card_height(12), do: "h-[620px] sm:h-[680px]"
  defp game_card_height(16), do: "h-[720px] sm:h-[780px]"

  defp board_data(rows, payout_table) do
    spacing = 340 / (rows + 1)
    top_margin = 30
    row_height = (board_height(rows) - top_margin - 50) / rows

    pegs =
      for row <- 0..(rows - 1), col <- 0..row do
        num_pegs = row + 1
        row_width = (num_pegs - 1) * spacing
        x = 200 - row_width / 2 + col * spacing
        y = top_margin + row * row_height
        {Float.round(x, 1), Float.round(y, 1)}
      end

    num_slots = rows + 1
    slot_width = 340 / num_slots
    slot_y = board_height(rows) - 50

    slots =
      for k <- 0..rows do
        x = 200 - (num_slots - 1) * slot_width / 2 + k * slot_width
        bp = Enum.at(payout_table, k, 0)
        {k, Float.round(x, 1), slot_y, bp}
      end

    %{pegs: pegs, slots: slots}
  end

  defp slot_color(bp) when bp >= 100_000, do: "#22c55e"   # >= 10x: bright green
  defp slot_color(bp) when bp >= 30_000,  do: "#4ade80"   # >= 3x: green
  defp slot_color(bp) when bp >= 10_000,  do: "#eab308"   # >= 1x: yellow
  defp slot_color(bp) when bp > 0,        do: "#ef4444"   # < 1x: red
  defp slot_color(0),                      do: "#991b1b"   # 0x: dark red

  defp format_multiplier_bp(0), do: "0x"
  defp format_multiplier_bp(bp) when bp >= 10_000 do
    x = div(bp, 10_000)
    rem_bp = rem(bp, 10_000)
    if rem_bp == 0, do: "#{x}x", else: "#{x}.#{div(rem_bp, 1000)}x"
  end
  defp format_multiplier_bp(bp), do: "0.#{div(bp, 1000)}x"

  # ============================================================
  # Event Handlers
  # ============================================================

  @impl true
  def handle_event("select_rows", %{"rows" => rows_str}, socket) do
    rows = String.to_integer(rows_str)
    config_index = Map.get(@config_map, {rows, socket.assigns.selected_risk}, 0)
    payout_table = Map.get(@payout_tables, config_index, [])

    socket =
      socket
      |> assign(selected_rows: rows, config_index: config_index, payout_table: payout_table)
      |> recalculate_max_bet()

    {:noreply, socket}
  end

  def handle_event("select_risk", %{"risk" => risk_str}, socket) do
    risk = String.to_existing_atom(risk_str)
    config_index = Map.get(@config_map, {socket.assigns.selected_rows, risk}, 0)
    payout_table = Map.get(@payout_tables, config_index, [])

    socket =
      socket
      |> assign(selected_risk: risk, config_index: config_index, payout_table: payout_table)
      |> recalculate_max_bet()

    {:noreply, socket}
  end

  def handle_event("update_bet_amount", %{"value" => val}, socket) do
    case Integer.parse(val) do
      {amount, _} -> {:noreply, assign(socket, bet_amount: max(amount, 0), error_message: nil)}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("halve_bet", _params, socket) do
    {:noreply, assign(socket, bet_amount: max(div(socket.assigns.bet_amount, 2), 1))}
  end

  def handle_event("double_bet", _params, socket) do
    new_amount = min(socket.assigns.bet_amount * 2, socket.assigns.max_bet)
    {:noreply, assign(socket, bet_amount: max(new_amount, 1))}
  end

  def handle_event("set_max_bet", _params, socket) do
    max = socket.assigns.max_bet
    balance = trunc(Map.get(socket.assigns.balances, socket.assigns.selected_token, 0))
    {:noreply, assign(socket, bet_amount: min(max, balance))}
  end

  def handle_event("select_token", %{"token" => token}, socket) do
    socket =
      socket
      |> assign(selected_token: token, header_token: token, show_token_dropdown: false)
      |> start_async(:fetch_house_balance, fn ->
        if token == "ROGUE" do
          BuxMinter.rogue_bankroll_house_balance()
        else
          BuxMinter.bux_bankroll_house_info()
        end
      end)

    {:noreply, socket}
  end

  def handle_event("toggle_token_dropdown", _params, socket) do
    {:noreply, assign(socket, show_token_dropdown: !socket.assigns.show_token_dropdown)}
  end

  def handle_event("hide_token_dropdown", _params, socket) do
    {:noreply, assign(socket, show_token_dropdown: false)}
  end

  def handle_event("toggle_provably_fair", _params, socket) do
    {:noreply, assign(socket, show_provably_fair: !socket.assigns.show_provably_fair)}
  end

  def handle_event("close_provably_fair", _params, socket) do
    {:noreply, assign(socket, show_provably_fair: false)}
  end

  # ---- Main Action: Drop Ball ----

  def handle_event("drop_ball", _params, socket) do
    %{
      current_user: user,
      bet_amount: bet_amount,
      selected_token: token,
      config_index: config_index,
      onchain_ready: ready,
      onchain_game_id: game_id,
      commitment_hash: commitment_hash,
      max_bet: max_bet
    } = socket.assigns

    cond do
      !ready ->
        {:noreply, assign(socket, error_message: "Game not ready — please wait")}

      bet_amount <= 0 ->
        {:noreply, assign(socket, error_message: "Invalid bet amount")}

      get_balance(socket, token) < bet_amount ->
        {:noreply, assign(socket, error_message: "Insufficient #{token} balance")}

      bet_amount > max_bet ->
        {:noreply, assign(socket, error_message: "Bet exceeds maximum (#{format_integer(max_bet)} #{token})")}

      token == "ROGUE" and bet_amount < 100 ->
        {:noreply, assign(socket, error_message: "Minimum ROGUE bet: 100")}

      true ->
        # 1. Optimistic balance deduction
        EngagementTracker.deduct_user_token_balance(user.id, token, bet_amount)

        # 2. Calculate result (reads server_seed from Mnesia)
        {:ok, result} = PlinkoGame.calculate_game_result(
          game_id, config_index, bet_amount, token, user.id
        )

        # 3. Generate confetti if big win (>= 5x)
        confetti = if result.won and result.payout_bp >= 50_000 do
          generate_confetti()
        else
          []
        end

        # 4. Start animation + push bet to JS
        socket =
          socket
          |> assign(
            game_state: :dropping,
            current_bet: bet_amount,
            ball_path: result.ball_path,
            landing_position: result.landing_position,
            payout: result.payout,
            payout_multiplier: result.payout_bp / 10_000,
            won: result.won,
            confetti_pieces: confetti,
            error_message: nil
          )
          |> push_event("drop_ball", %{
            ball_path: Enum.map(result.ball_path, fn :left -> 0; :right -> 1 end),
            landing_position: result.landing_position,
            rows: socket.assigns.selected_rows
          })
          |> push_event("place_bet_background", %{
            game_id: game_id,
            commitment_hash: commitment_hash,
            token: token,
            token_address: PlinkoGame.token_address(token),
            amount: bet_amount,
            config_index: config_index
          })

        {:noreply, socket}
    end
  end

  # JS hook callbacks
  def handle_event("ball_landed", _params, socket) do
    {:noreply, assign(socket, game_state: :result)}
  end

  def handle_event("bet_confirmed", %{"game_id" => _game_id, "tx_hash" => tx_hash} = params, socket) do
    Logger.info("[PlinkoLive] Bet confirmed: #{tx_hash}")
    confirmation_time = Map.get(params, "confirmation_time_ms", 0)
    Logger.info("[PlinkoLive] Confirmation time: #{confirmation_time}ms")
    {:noreply, assign(socket, bet_tx: tx_hash)}
  end

  def handle_event("bet_failed", %{"error" => error} = params, socket) do
    Logger.error("[PlinkoLive] Bet failed: #{error}")
    game_id = Map.get(params, "game_id")

    # Refund optimistic balance deduction
    user = socket.assigns.current_user
    if user do
      EngagementTracker.credit_user_token_balance(user.id, socket.assigns.selected_token, socket.assigns.current_bet)
    end

    socket =
      socket
      |> assign(game_state: :idle, error_message: "Bet failed: #{error}")

    {:noreply, socket}
  end

  def handle_event("reset_game", _params, socket) do
    user = socket.assigns.current_user
    wallet = socket.assigns.wallet_address

    # Re-init on-chain game for next bet
    socket =
      socket
      |> assign(
        game_state: :idle,
        ball_path: [],
        landing_position: nil,
        payout: 0,
        payout_multiplier: nil,
        won: nil,
        confetti_pieces: [],
        error_message: nil,
        bet_tx: nil,
        settlement_tx: nil,
        onchain_ready: false,
        onchain_initializing: true
      )
      |> push_event("reset_ball", %{})
      |> start_async(:init_onchain_game, fn ->
        PlinkoGame.get_or_init_game(user.id, wallet)
      end)

    # Sync balances
    if user && wallet do
      BuxMinter.sync_user_balances_async(user.id, wallet)
    end

    {:noreply, socket}
  end

  def handle_event("show_fairness_modal", %{"game-id" => game_id}, socket) do
    # Load game data for fairness verification
    case PlinkoGame.get_fairness_data(game_id) do
      {:ok, data} ->
        {:noreply, assign(socket, show_fairness_modal: true, fairness_game: data)}
      _ ->
        {:noreply, assign(socket, error_message: "Could not load game data")}
    end
  end

  def handle_event("hide_fairness_modal", _params, socket) do
    {:noreply, assign(socket, show_fairness_modal: false, fairness_game: nil)}
  end

  def handle_event("stop_propagation", _params, socket), do: {:noreply, socket}

  def handle_event("load-more-games", _params, socket) do
    user = socket.assigns.current_user
    if user do
      new_offset = socket.assigns.games_offset + 30
      socket = start_async(socket, :load_more_games, fn ->
        PlinkoGame.load_recent_games(user.id, limit: 30, offset: new_offset)
      end)
      {:noreply, assign(socket, games_offset: new_offset)}
    else
      {:noreply, socket}
    end
  end

  # ============================================================
  # Async Handlers
  # ============================================================

  @impl true
  def handle_async(:init_onchain_game, {:ok, result}, socket) do
    case result do
      {:ok, %{game_id: game_id, commitment_hash: commitment_hash, nonce: nonce, server_seed_hash: hash}} ->
        {:noreply,
         assign(socket,
           onchain_ready: true,
           onchain_initializing: false,
           onchain_game_id: game_id,
           commitment_hash: commitment_hash,
           nonce: nonce,
           server_seed_hash: hash
         )}

      {:error, reason} ->
        Logger.warning("[PlinkoLive] Init failed: #{inspect(reason)}")
        {:noreply, assign(socket, onchain_initializing: false, error_message: "Failed to initialize game")}
    end
  end

  def handle_async(:init_onchain_game, {:exit, reason}, socket) do
    retry_count = socket.assigns.init_retry_count
    max_retries = 3

    if retry_count < max_retries do
      delay = :math.pow(2, retry_count) |> round() |> Kernel.*(1000)
      Logger.warning("[PlinkoLive] Init crashed (attempt #{retry_count + 1}), retrying in #{delay}ms: #{inspect(reason)}")
      Process.send_after(self(), :retry_init, delay)
      {:noreply, assign(socket, init_retry_count: retry_count + 1)}
    else
      Logger.error("[PlinkoLive] Init failed after #{max_retries} retries")
      {:noreply, assign(socket, error_message: "Failed to initialize game. Please refresh.", onchain_initializing: false)}
    end
  end

  def handle_async(:fetch_house_balance, {:ok, result}, socket) do
    case result do
      {:ok, info} ->
        net = Map.get(info, :net_balance, 0)
        socket = socket
        |> assign(house_balance: net)
        |> recalculate_max_bet()
        {:noreply, socket}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_async(:fetch_house_balance, {:exit, _reason}, socket) do
    {:noreply, socket}
  end

  def handle_async(:load_recent_games, {:ok, result}, socket) do
    case result do
      {:ok, games} ->
        {:noreply, assign(socket, recent_games: games, games_loading: false)}
      _ ->
        {:noreply, assign(socket, games_loading: false)}
    end
  end

  def handle_async(:load_recent_games, {:exit, _reason}, socket) do
    {:noreply, assign(socket, games_loading: false)}
  end

  def handle_async(:load_more_games, {:ok, {:ok, games}}, socket) do
    {:noreply, assign(socket, recent_games: socket.assigns.recent_games ++ games)}
  end

  def handle_async(:load_more_games, _, socket), do: {:noreply, socket}

  # ============================================================
  # PubSub / Info Handlers
  # ============================================================

  @impl true
  def handle_info(:retry_init, socket) do
    user = socket.assigns.current_user
    wallet = socket.assigns.wallet_address

    socket = start_async(socket, :init_onchain_game, fn ->
      PlinkoGame.get_or_init_game(user.id, wallet)
    end)

    {:noreply, socket}
  end

  def handle_info({:bux_balance_updated, _balance}, socket) do
    user = socket.assigns.current_user
    if user do
      balances = EngagementTracker.get_user_token_balances(user.id)
      {:noreply, assign(socket, balances: balances)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:token_balances_updated, balances}, socket) do
    {:noreply, assign(socket, balances: balances)}
  end

  def handle_info({:plinko_settled, game_id, tx_hash}, socket) do
    if game_id == socket.assigns.onchain_game_id do
      {:noreply, assign(socket, settlement_tx: tx_hash)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:token_prices_updated, _prices}, socket) do
    {:noreply, assign(socket, rogue_usd_price: PriceTracker.get_rogue_price())}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ============================================================
  # Helpers
  # ============================================================

  defp get_balance(socket, token) do
    Map.get(socket.assigns.balances, token, 0)
  end

  defp recalculate_max_bet(socket) do
    # max_bet = (net_balance * 0.001) * 20000 / max_multiplier_bps
    net = socket.assigns.house_balance
    payout_table = socket.assigns.payout_table
    max_mult_bps = Enum.max(payout_table ++ [10_000])

    base_max = net * 10 / 10_000  # 0.1% (MAX_BET_BPS = 10)
    max_bet = trunc(base_max * 20_000 / max(max_mult_bps, 1))

    # Also cap at user balance
    balance = trunc(Map.get(socket.assigns.balances, socket.assigns.selected_token, 0))
    effective_max = min(max_bet, balance)

    assign(socket, max_bet: max(effective_max, 0))
  end

  defp format_balance(amount) when is_float(amount) do
    Number.Currency.number_to_currency(amount, unit: "", precision: 2)
  end

  defp format_balance(amount) when is_integer(amount) do
    Number.Currency.number_to_currency(amount, unit: "", precision: 0)
  end

  defp format_balance(_), do: "0"

  defp format_integer(amount) when is_number(amount) do
    Number.Currency.number_to_currency(trunc(amount), unit: "", precision: 0)
  end

  defp format_integer(_), do: "0"

  defp format_usd(price, amount) when is_number(price) and is_number(amount) do
    usd = price * amount
    "$#{Number.Currency.number_to_currency(usd, unit: "", precision: 2)}"
  end

  defp format_usd(_, _), do: ""

  defp format_multiplier_display(nil), do: "0x"
  defp format_multiplier_display(mult) when is_float(mult) do
    if mult == trunc(mult) do
      "#{trunc(mult)}x"
    else
      "#{Float.round(mult, 1)}x"
    end
  end
  defp format_multiplier_display(mult), do: "#{mult}x"

  defp format_max_payout(bet_amount, payout_table) do
    max_bp = Enum.max(payout_table ++ [0])
    payout = bet_amount * max_bp / 10_000
    format_balance(payout)
  end

  defp generate_confetti do
    emojis = ["🎉", "⭐", "💰", "🔥", "✨", "🎊", "💎", "🚀"]
    for _ <- 1..100 do
      %{
        emoji: Enum.random(emojis),
        x_start: :rand.uniform(100),
        x_end: :rand.uniform(100),
        x_drift: :rand.uniform(40) - 20,
        rotation: :rand.uniform(360),
        delay: :rand.uniform(2000),
        duration: 2000 + :rand.uniform(3000)
      }
    end
  end
end
```

---

## 2. Ball Animation Hook: `assets/js/plinko_ball.js`

```javascript
/**
 * PlinkoBall Hook
 *
 * Controls the Plinko ball drop animation. Receives ball_path and
 * landing_position from LiveView, animates the ball through pegs
 * row by row with physics-inspired easing, then notifies LiveView
 * when the ball has landed.
 *
 * Coordinate system matches the Elixir SVG generation exactly:
 * - ViewBox: 0 0 400 {height}
 * - Board centered at x=200
 * - Peg at (row, col): x = 200 - rowWidth/2 + col * spacing
 * - Row i has (i + 1) pegs, spacing = 340 / (rows + 1)
 */

export const PlinkoBall = {
  mounted() {
    this.ball = this.el.querySelector('#plinko-ball');
    this.pegs = this.el.querySelectorAll('.plinko-peg');
    this.slots = this.el.querySelectorAll('.plinko-slot');
    this.trails = [];

    // Listen for drop command from LiveView
    this.handleEvent("drop_ball", ({ ball_path, landing_position, rows }) => {
      this.animateDrop(ball_path, landing_position, rows);
    });

    // Listen for reset command
    this.handleEvent("reset_ball", () => this.resetBall());
  },

  updated() {
    // Re-cache elements after LiveView DOM patches
    this.ball = this.el.querySelector('#plinko-ball');
    this.pegs = this.el.querySelectorAll('.plinko-peg');
    this.slots = this.el.querySelectorAll('.plinko-slot');
  },

  // ============ Layout Calculations ============

  getLayout(rows) {
    const viewHeight = rows === 8 ? 340 : rows === 12 ? 460 : 580;
    const topMargin = 30;
    const bottomMargin = 50;
    const boardHeight = viewHeight - topMargin - bottomMargin;
    const rowHeight = boardHeight / rows;
    const spacing = 340 / (rows + 1);

    return { viewHeight, topMargin, bottomMargin, boardHeight, rowHeight, spacing };
  },

  getPegPosition(row, col, rows) {
    const { topMargin, rowHeight, spacing } = this.getLayout(rows);
    const numPegsInRow = row + 1;
    const rowWidth = (numPegsInRow - 1) * spacing;
    return {
      x: 200 - rowWidth / 2 + col * spacing,
      y: topMargin + row * rowHeight
    };
  },

  getBallPositionAfterBounce(row, pathSoFar, rows) {
    const rightCount = pathSoFar.filter(d => d === 1).length;
    const { topMargin, rowHeight, spacing } = this.getLayout(rows);

    const nextRow = row + 1;
    if (nextRow >= rows) {
      return this.getSlotPosition(rightCount, rows);
    }

    const numPegsNext = nextRow + 1;
    const rowWidthNext = (numPegsNext - 1) * spacing;
    return {
      x: 200 - rowWidthNext / 2 + rightCount * spacing,
      y: topMargin + row * rowHeight + rowHeight / 2
    };
  },

  getSlotPosition(index, rows) {
    const { viewHeight } = this.getLayout(rows);
    const numSlots = rows + 1;
    const slotWidth = 340 / numSlots;
    return {
      x: 200 - (numSlots - 1) * slotWidth / 2 + index * slotWidth,
      y: viewHeight - 25
    };
  },

  // ============ Animation ============

  async animateDrop(ballPath, landingPosition, rows) {
    this.clearTrails();

    if (!this.ball) {
      this.ball = this.el.querySelector('#plinko-ball');
    }
    if (!this.ball) return;

    this.ball.style.display = 'block';
    this.ball.setAttribute('cx', '200');
    this.ball.setAttribute('cy', '10');

    const timings = this.calculateTimings(rows);

    // Animate through each row
    for (let i = 0; i < ballPath.length; i++) {
      const pathSoFar = ballPath.slice(0, i + 1);
      await this.animateToRow(i, ballPath[i], pathSoFar, rows, timings[i]);
    }

    // Final landing animation
    await this.animateLanding(landingPosition, rows, 800);

    // Notify LiveView
    this.pushEvent("ball_landed", {});
  },

  animateToRow(rowIndex, direction, pathSoFar, rows, duration) {
    return new Promise(resolve => {
      const startX = parseFloat(this.ball.getAttribute('cx'));
      const startY = parseFloat(this.ball.getAttribute('cy'));
      const target = this.getBallPositionAfterBounce(rowIndex, pathSoFar, rows);
      const startTime = performance.now();

      // Visual: trail at current position
      this.addTrail(startX, startY);

      // Visual: flash the peg being hit
      this.flashPeg(rowIndex, pathSoFar, rows);

      const animate = (now) => {
        const elapsed = now - startTime;
        const progress = Math.min(elapsed / duration, 1);
        // Ease-out cubic for natural bounce deceleration
        const eased = 1 - Math.pow(1 - progress, 3);

        const currentX = startX + (target.x - startX) * eased;
        const currentY = startY + (target.y - startY) * eased;

        this.ball.setAttribute('cx', currentX);
        this.ball.setAttribute('cy', currentY);

        if (progress < 1) {
          requestAnimationFrame(animate);
        } else {
          resolve();
        }
      };

      requestAnimationFrame(animate);
    });
  },

  animateLanding(landingPosition, rows, duration) {
    return new Promise(resolve => {
      const startX = parseFloat(this.ball.getAttribute('cx'));
      const startY = parseFloat(this.ball.getAttribute('cy'));
      const target = this.getSlotPosition(landingPosition, rows);
      const startTime = performance.now();

      const animate = (now) => {
        const elapsed = now - startTime;
        const progress = Math.min(elapsed / duration, 1);
        const eased = 1 - Math.pow(1 - progress, 2);

        this.ball.setAttribute('cx', startX + (target.x - startX) * eased);
        this.ball.setAttribute('cy', startY + (target.y - startY) * eased);

        if (progress < 1) {
          requestAnimationFrame(animate);
        } else {
          this.highlightSlot(landingPosition);
          resolve();
        }
      };

      requestAnimationFrame(animate);
    });
  },

  calculateTimings(rows) {
    // Total animation ~6 seconds, rows get progressively slower (gravity)
    const totalMs = 6000;
    const ratio = 2.5;  // last row takes 2.5x longer than first
    const minTime = 2 * (totalMs / rows) / (1 + ratio);
    return Array.from({ length: rows }, (_, i) =>
      minTime + (minTime * ratio - minTime) * (i / (rows - 1))
    );
  },

  // ============ Visual Effects ============

  addTrail(x, y) {
    const ns = "http://www.w3.org/2000/svg";
    const trail = document.createElementNS(ns, "circle");
    trail.setAttribute('cx', x);
    trail.setAttribute('cy', y);
    trail.setAttribute('r', '3');
    trail.setAttribute('fill', '#CAFC00');
    trail.setAttribute('opacity', '0.4');
    trail.classList.add('plinko-trail');
    this.el.appendChild(trail);
    this.trails.push(trail);

    // Fade trail
    setTimeout(() => { trail.setAttribute('opacity', '0.1'); }, 400);
  },

  flashPeg(rowIndex, pathSoFar, rows) {
    const rightsBefore = pathSoFar.slice(0, -1).filter(d => d === 1).length;
    const col = rightsBefore;
    const pegIndex = this.getPegIndex(rowIndex, col);

    if (this.pegs[pegIndex]) {
      const peg = this.pegs[pegIndex];
      const origFill = peg.getAttribute('fill');
      const origR = parseFloat(peg.getAttribute('r'));

      peg.setAttribute('fill', '#ffffff');
      peg.setAttribute('r', origR * 1.5);

      setTimeout(() => {
        peg.setAttribute('fill', origFill);
        peg.setAttribute('r', origR);
      }, 200);
    }
  },

  getPegIndex(row, col) {
    // Pegs rendered sequentially: row 0 has 1, row 1 has 2, etc.
    let index = 0;
    for (let r = 0; r < row; r++) {
      index += (r + 1);
    }
    return index + col;
  },

  highlightSlot(position) {
    if (this.slots[position]) {
      this.slots[position].classList.add('plinko-slot-hit');
    }
  },

  clearTrails() {
    this.trails.forEach(t => t.remove());
    this.trails = [];
    if (this.el) {
      this.el.querySelectorAll('.plinko-slot-hit').forEach(s => {
        s.classList.remove('plinko-slot-hit');
      });
    }
  },

  resetBall() {
    if (this.ball) {
      this.ball.style.display = 'none';
      this.ball.setAttribute('cx', '200');
      this.ball.setAttribute('cy', '10');
    }
    this.clearTrails();
  }
};
```

---

## 3. On-Chain Hook: `assets/js/plinko_onchain.js`

```javascript
/**
 * PlinkoOnchain Hook
 *
 * Same pattern as BuxBoosterOnchain. Handles:
 * - BUX approval (infinite, cached in localStorage)
 * - placeBet for BUX (ERC-20 through BUXBankroll)
 * - placeBetROGUE for ROGUE (native token through ROGUEBankroll)
 *
 * NOTE: BUX approval target is BUX_BANKROLL_ADDRESS (not PlinkoGame).
 * PlinkoGame calls safeTransferFrom(player -> BUXBankroll).
 */

import PlinkoGameABI from './PlinkoGame.json';

const PLINKO_CONTRACT_ADDRESS = "0x<DEPLOYED>";           // Set after deployment
const BUX_BANKROLL_ADDRESS = "0x<BUX_BANKROLL_DEPLOYED>"; // Set after deployment
const BUX_TOKEN_ADDRESS = "0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8";
const APPROVAL_CACHE_KEY = "plinko_bux_approved";

// Error signature map — compute from compiled ABI post-deployment
// Use: ethers.id("ErrorName()").slice(0,10)
const ERROR_MESSAGES = {
  "0x05d09e5f": "Bet already settled",
  "0xd0d04f60": "Token not enabled for betting",
  "0x3a51740d": "Bet amount too low",
  "0x3f45a891": "Bet exceeds maximum allowed",
};

function parseError(error) {
  const msg = error?.message || error?.toString() || "";

  for (const [sig, message] of Object.entries(ERROR_MESSAGES)) {
    if (msg.includes(sig)) return message;
  }

  if (msg.includes("insufficient funds")) return "Insufficient funds for transaction";
  if (msg.includes("user rejected") || msg.includes("User rejected")) return "Transaction cancelled";
  if (msg.includes("nonce")) return "Transaction nonce error — please try again";
  if (msg.includes("Encoded error signature")) return "Transaction failed — check bet amount";

  return msg.slice(0, 200) || "Transaction failed";
}

export const PlinkoOnchain = {
  mounted() {
    this.gameId = this.el.dataset.gameId;
    this.commitmentHash = this.el.dataset.commitmentHash;

    this.handleEvent("place_bet_background", async (params) => {
      await this.placeBet(params);
    });
  },

  updated() {
    const newGameId = this.el.dataset.gameId;
    const newCommitmentHash = this.el.dataset.commitmentHash;
    if (newGameId && newGameId !== this.gameId) this.gameId = newGameId;
    if (newCommitmentHash && newCommitmentHash !== this.commitmentHash) this.commitmentHash = newCommitmentHash;
  },

  async placeBet({ game_id, commitment_hash, token, token_address, amount, config_index }) {
    const startTime = Date.now();

    try {
      const wallet = window.smartAccount;
      if (!wallet) {
        this.pushEvent("bet_failed", { game_id, error: "No wallet connected. Please refresh." });
        return;
      }

      const { getContract, prepareContractCall, sendTransaction, readContract, waitForReceipt } = await import("thirdweb");
      const client = window.thirdwebClient;
      const chain = window.rogueChain;
      const amountWei = BigInt(amount) * BigInt(10 ** 18);

      const plinkoContract = getContract({
        client, chain,
        address: PLINKO_CONTRACT_ADDRESS,
        abi: PlinkoGameABI.abi || PlinkoGameABI,
      });

      const isROGUE = !token_address ||
                       token_address === "0x0000000000000000000000000000000000000000";

      let result;

      if (isROGUE) {
        // Native ROGUE bet — no approval needed
        const tx = prepareContractCall({
          contract: plinkoContract,
          method: "function placeBetROGUE(uint256 amount, uint8 configIndex, bytes32 commitmentHash) external payable",
          params: [amountWei, config_index, commitment_hash],
          value: amountWei,
          gas: 500000n,
        });

        console.log("[PlinkoOnchain] Placing ROGUE bet...");
        const receipt = await sendTransaction({ transaction: tx, account: wallet });
        result = { success: true, txHash: receipt.transactionHash };

      } else {
        // ERC-20 BUX bet — check/do approval first
        await this.ensureBUXApproval(wallet, amountWei, client, chain);

        const tx = prepareContractCall({
          contract: plinkoContract,
          method: "function placeBet(uint256 amount, uint8 configIndex, bytes32 commitmentHash) external",
          params: [amountWei, config_index, commitment_hash],
        });

        console.log("[PlinkoOnchain] Placing BUX bet...");
        const receipt = await sendTransaction({ transaction: tx, account: wallet });
        result = { success: true, txHash: receipt.transactionHash };
      }

      if (result.success) {
        const confirmationTime = Date.now() - startTime;
        console.log(`[PlinkoOnchain] Bet confirmed in ${confirmationTime}ms: ${result.txHash}`);

        this.pushEvent("bet_confirmed", {
          game_id,
          tx_hash: result.txHash,
          confirmation_time_ms: confirmationTime,
        });
      }

    } catch (error) {
      console.error("[PlinkoOnchain] Bet failed:", error);
      this.pushEvent("bet_failed", { game_id, error: parseError(error) });
    }
  },

  async ensureBUXApproval(wallet, amount, client, chain) {
    // Check localStorage cache first
    if (localStorage.getItem(APPROVAL_CACHE_KEY) === "true") {
      return;
    }

    const { getContract: gc, readContract: rc, prepareContractCall: pcc, sendTransaction: st, waitForReceipt: wfr } = await import("thirdweb");

    const buxContract = gc({ client, chain, address: BUX_TOKEN_ADDRESS });

    const allowance = await rc({
      contract: buxContract,
      method: "function allowance(address owner, address spender) view returns (uint256)",
      params: [wallet.address, BUX_BANKROLL_ADDRESS],
    });

    const INFINITE_THRESHOLD = BigInt('0x8000000000000000000000000000000000000000000000000000000000000000');

    if (BigInt(allowance) >= INFINITE_THRESHOLD) {
      localStorage.setItem(APPROVAL_CACHE_KEY, "true");
      return;
    }

    if (BigInt(allowance) >= amount) {
      return;
    }

    // Execute infinite approval
    console.log("[PlinkoOnchain] Approving BUX for BUXBankroll...");
    const INFINITE = BigInt("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff");

    const approveTx = pcc({
      contract: buxContract,
      method: "function approve(address spender, uint256 amount) returns (bool)",
      params: [BUX_BANKROLL_ADDRESS, INFINITE],
    });

    const approveResult = await st({ transaction: approveTx, account: wallet });
    await wfr({ client, chain, transactionHash: approveResult.transactionHash });

    localStorage.setItem(APPROVAL_CACHE_KEY, "true");
    console.log("[PlinkoOnchain] BUX approved:", approveResult.transactionHash);
  },
};
```

---

## 4. Register Hooks in `assets/js/app.js`

```javascript
import { PlinkoBall } from "./plinko_ball";
import { PlinkoOnchain } from "./plinko_onchain";

let hooks = {
  // ...existing hooks...
  PlinkoBall,
  PlinkoOnchain,
};
```

---

## 5. Route in `router.ex`

```elixir
# Inside the live scope:
live "/plinko", PlinkoLive, :index
```

---

## 6. CSS Additions (`assets/css/app.css`)

```css
/* Plinko Board */
.plinko-peg {
  transition: fill 0.15s, r 0.15s;
}

.plinko-trail {
  transition: opacity 0.5s ease-out;
}

/* Landing Slot Hit */
.plinko-slot {
  transition: transform 0.3s, filter 0.3s;
}

.plinko-slot-hit {
  animation: slot-pulse 0.5s ease-in-out 3;
  filter: brightness(1.5);
}

@keyframes slot-pulse {
  0%, 100% { transform: scaleY(1); }
  50% { transform: scaleY(1.15); }
}

/* Ball glow */
#plinko-ball {
  filter: drop-shadow(0 0 6px #CAFC00) drop-shadow(0 0 12px rgba(202, 252, 0, 0.4));
}

/* Plinko win text */
.plinko-win-text {
  animation: scale-in 0.5s ease-out;
}

@keyframes scale-in {
  0% { transform: scale(0.5); opacity: 0; }
  80% { transform: scale(1.1); }
  100% { transform: scale(1); opacity: 1; }
}
```

---

## 7. Design Notes

**Theme**: Dark zinc (matches the broader game family)
- Background: `zinc-950` (page), `zinc-900` (cards)
- Borders: `zinc-800`
- Text: `white` (primary), `zinc-400` (secondary), `zinc-500` (muted)
- Accent: `#CAFC00` (brand lime) on backgrounds only, never as text
- Fonts: `font-haas_medium_65` for headings, `font-haas_roman_55` for body

**Layout**: Single column, `max-w-2xl` centered (same as BUX Booster)
- Config selector: two rows of tabs (rows + risk)
- Game card: dynamic height based on row count
- SVG board scales with viewBox
- History table below game card

**Mobile**:
- SVG scales automatically
- Config buttons wrap naturally
- Slot text sizes decrease: 10px / 9px / 7px for 8/12/16 rows
- Game card height adjusts: 520/620/720px mobile, 560/680/780px desktop
- History table horizontal scroll with `min-w-[550px]`

**Animation Timing**:
- Total drop: ~6 seconds for all row counts
- Per-row timing: accelerates (gravity effect)
  - 8 rows: ~430ms to ~1070ms per row
  - 12 rows: ~286ms to ~714ms per row
  - 16 rows: ~214ms to ~536ms per row
- Landing: 800ms ease-out
- Slot hit: 3x pulse animation (500ms each)
- Confetti: on wins >= 5x multiplier

**Peg & Ball Sizes**:
| Rows | Peg r | Ball r |
|------|-------|--------|
| 8    | 4     | 8      |
| 12   | 3     | 6      |
| 16   | 2.5   | 5      |

**Slot Colors**:
| Multiplier | Color | Hex |
|-----------|-------|-----|
| >= 10x | Bright green | #22c55e |
| >= 3x | Green | #4ade80 |
| >= 1x | Yellow | #eab308 |
| < 1x | Red | #ef4444 |
| 0x | Dark red | #991b1b |
