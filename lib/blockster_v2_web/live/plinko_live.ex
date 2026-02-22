defmodule BlocksterV2Web.PlinkoLive do
  use BlocksterV2Web, :live_view
  require Logger

  alias BlocksterV2.{PlinkoGame, BuxMinter, EngagementTracker, PriceTracker, HubLogoCache}

  @payout_tables PlinkoGame.payout_tables()

  # ============ Mount ============

  @impl true
  def mount(_params, _session, socket) do
    current_user = socket.assigns[:current_user]

    if current_user do
      wallet_address = current_user.smart_wallet_address

      # Sync balances from blockchain on connected mount
      if wallet_address != nil and connected?(socket) do
        BuxMinter.sync_user_balances_async(current_user.id, wallet_address)
      end

      balances = EngagementTracker.get_user_token_balances(current_user.id)

      # Only initialize on-chain game on connected mount (double-mount protection)
      socket =
        if wallet_address != nil and connected?(socket) do
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
      default_config = 0

      token_logos = HubLogoCache.get_all_logos()

      socket =
        socket
        |> assign(page_title: "Plinko")
        |> assign(current_user: current_user)
        |> assign(balances: balances)
        |> assign(token_logos: token_logos)
        # Game config
        |> assign(selected_token: "BUX")
        |> assign(header_token: "BUX")
        |> assign(selected_rows: 8)
        |> assign(selected_risk: :low)
        |> assign(config_index: default_config)
        |> assign(bet_amount: 10)
        |> assign(current_bet: 10)
        |> assign(payout_table: Map.get(@payout_tables, default_config))
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
        |> assign(commitment_tx: nil)
        |> assign(nonce: nil)
        |> assign(bet_tx: nil)
        |> assign(bet_id: nil)
        |> assign(settlement_tx: nil)
        # House / balance
        |> assign(house_balance: 0.0)
        |> assign(max_bet: 0)
        |> assign(rogue_usd_price: get_rogue_price())
        # UI state
        |> assign(show_token_dropdown: false)
        |> assign(show_provably_fair: false)
        |> assign(show_fairness_modal: false)
        |> assign(fairness_game: nil)
        |> assign(recent_games: [])
        |> assign(games_offset: 0)
        |> assign(has_more_games: false)
        |> assign(games_loading: connected?(socket))
        |> stream_configure(:game_history, dom_id: &"game-#{&1.game_id}")
        |> stream(:game_history, [])

      # Async operations on connected mount
      socket =
        if connected?(socket) do
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
      {:ok, assign_defaults_for_guest(socket)}
    end
  end

  # ============ Render ============

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="plinko-game"
      class="min-h-screen"
      phx-hook="PlinkoOnchain"
      data-game-id={@onchain_game_id}
      data-commitment-hash={@commitment_hash}
    >
      <div class="max-w-2xl mx-auto px-3 sm:px-4 pt-6 sm:pt-24 pb-8">
        <!-- Main Game Card -->
        <div class="plinko-game-card">
          <!-- How It Works link -->
          <div class="flex justify-end px-3 pt-2">
            <a href="/plinko/how-it-works" class="text-gray-400 hover:text-gray-600 flex items-center gap-1 text-xs cursor-pointer">
              <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
              How it works
            </a>
          </div>

          <!-- Error Banner -->
          <div :if={@error_message} class="bg-red-50 border border-red-300 rounded-lg p-2 sm:p-3 text-red-700 text-xs sm:text-sm text-center mx-3 mt-3">
            <%= @error_message %>
            <button phx-click="clear_error" class="ml-2 text-red-600 hover:text-red-700 cursor-pointer">x</button>
          </div>

          <!-- Bet Controls (always rendered, disabled during dropping) -->
          <% bet_disabled = @game_state not in [:idle, :result] %>
          <div class={"px-3 sm:px-4 pt-3 pb-2 #{if bet_disabled, do: "opacity-50 pointer-events-none"}"}>
            <!-- Bet Stake -->
            <div class="mb-3 sm:mb-4">
              <label class="block text-base sm:text-lg font-bold text-gray-900 mb-1 sm:mb-2">Bet Stake</label>
              <div class="flex gap-1.5 sm:gap-2">
                <!-- Input with halve/double buttons -->
                <div class="flex-1 relative min-w-0">
                  <input
                    type="number"
                    value={@bet_amount}
                    phx-keyup="update_bet_amount"
                    phx-debounce="100"
                    name="value"
                    disabled={bet_disabled}
                    min="1"
                    max={@max_bet}
                    class={"w-full bg-white border border-gray-300 rounded-lg pl-3 sm:pl-4 py-2 sm:py-3 text-gray-900 text-base sm:text-lg font-medium focus:outline-none focus:border-gray-900 focus:ring-1 focus:ring-gray-900 [appearance:textfield] [&::-webkit-outer-spin-button]:appearance-none [&::-webkit-inner-spin-button]:appearance-none #{if @selected_token == "ROGUE" && @rogue_usd_price, do: "pr-[7.5rem] sm:pr-36", else: "pr-20 sm:pr-24"}"}
                  />
                  <div class="absolute right-2 top-1/2 -translate-y-1/2 flex items-center gap-1">
                    <%= if @selected_token == "ROGUE" && @rogue_usd_price do %>
                      <span class="text-gray-400 text-[10px] sm:text-xs mr-1">&asymp; <%= format_usd(@rogue_usd_price, @bet_amount) %></span>
                    <% end %>
                    <button
                      type="button"
                      phx-click="halve_bet"
                      disabled={bet_disabled}
                      class="px-1.5 sm:px-2 py-1 bg-gray-200 text-gray-700 rounded text-xs sm:text-sm font-medium hover:bg-gray-300 transition-all cursor-pointer"
                    >
                      &half;
                    </button>
                    <button
                      type="button"
                      phx-click="double_bet"
                      disabled={bet_disabled}
                      class="px-1.5 sm:px-2 py-1 bg-gray-200 text-gray-700 rounded text-xs sm:text-sm font-medium hover:bg-gray-300 transition-all cursor-pointer"
                    >
                      2&times;
                    </button>
                  </div>
                </div>
                <!-- Token Dropdown -->
                <div class="relative flex-shrink-0" id="token-dropdown-wrapper" phx-click-away="hide_token_dropdown">
                  <button
                    type="button"
                    phx-click="toggle_token_dropdown"
                    disabled={bet_disabled}
                    class="h-full px-2 sm:px-4 bg-gray-100 border border-gray-300 rounded-lg flex items-center gap-1 sm:gap-2 hover:bg-gray-200 transition-all cursor-pointer"
                  >
                    <img src={Map.get(@token_logos, @selected_token, "https://ik.imagekit.io/blockster/blockster-icon.png")} alt={@selected_token} class="w-4 sm:w-5 h-4 sm:h-5 rounded-full" />
                    <span class="font-medium text-gray-900 text-sm sm:text-base"><%= @selected_token %></span>
                    <svg class="w-3 sm:w-4 h-3 sm:h-4 text-gray-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
                    </svg>
                  </button>
                  <%= if @show_token_dropdown do %>
                    <div class="absolute right-0 top-full mt-1 bg-white border border-gray-200 rounded-lg shadow-lg z-50 w-max min-w-[180px] sm:min-w-[220px]">
                      <%= for token <- ["BUX", "ROGUE"] do %>
                        <button
                          type="button"
                          phx-click="select_token"
                          phx-value-token={token}
                          class={"w-full px-4 py-3 flex items-center gap-3 hover:bg-gray-50 cursor-pointer first:rounded-t-lg last:rounded-b-lg #{if @selected_token == token, do: "bg-gray-100"}"}
                        >
                          <img src={Map.get(@token_logos, token, "https://ik.imagekit.io/blockster/blockster-icon.png")} alt={token} class="w-5 h-5 rounded-full flex-shrink-0" />
                          <span class="font-medium flex-1 text-left whitespace-nowrap text-gray-900"><%= token %></span>
                          <span class="text-gray-500 text-sm whitespace-nowrap"><%= format_balance(Map.get(@balances, token, 0)) %></span>
                        </button>
                      <% end %>
                    </div>
                  <% end %>
                </div>
                <!-- Max button -->
                <button
                  type="button"
                  phx-click="set_max_bet"
                  disabled={bet_disabled}
                  class="hidden sm:flex px-4 py-2 bg-gray-100 text-gray-700 rounded-lg hover:bg-gray-200 transition-all cursor-pointer flex-col items-center flex-shrink-0"
                  title={"Max bet: #{@max_bet} #{@selected_token}"}
                >
                  <span class="text-xs text-gray-500 font-normal">Max</span>
                  <span class="text-sm font-medium"><%= format_integer(@max_bet) %></span>
                </button>
              </div>
              <!-- Mobile: Max button row -->
              <div class="flex sm:hidden gap-2 mt-2">
                <button
                  type="button"
                  phx-click="set_max_bet"
                  disabled={bet_disabled}
                  class="flex-1 py-2 bg-gray-100 text-gray-700 rounded-lg hover:bg-gray-200 transition-all cursor-pointer flex items-center justify-center gap-2"
                  title={"Max bet: #{@max_bet} #{@selected_token}"}
                >
                  <span class="text-xs text-gray-500">Max bet:</span>
                  <span class="text-sm font-medium"><%= format_integer(@max_bet) %> <%= @selected_token %></span>
                </button>
              </div>
              <!-- Balance info -->
              <div class="mt-1.5 sm:mt-2">
                <div class="flex items-center justify-between text-[10px] sm:text-sm">
                  <a href={"https://roguescan.io/address/#{@current_user.smart_wallet_address}"} target="_blank" class="text-blue-500 hover:underline flex items-center gap-0.5 sm:gap-1 cursor-pointer">
                    <%= format_balance(Map.get(@balances, @selected_token, 0)) %>
                    <img src={Map.get(@token_logos, @selected_token, "https://ik.imagekit.io/blockster/blockster-icon.png")} alt={@selected_token} class="w-3 h-3 sm:w-4 sm:h-4 rounded-full inline" />
                    <%= if @selected_token == "ROGUE" && @rogue_usd_price do %>
                      <span class="text-gray-400">(<%= format_usd(@rogue_usd_price, Map.get(@balances, @selected_token, 0)) %>)</span>
                    <% end %>
                  </a>
                  <div class="text-right">
                    <a href="/bankroll" class="text-blue-500 hover:underline text-[10px] sm:text-xs cursor-pointer">
                      House: <%= format_balance(@house_balance) %>
                    </a>
                  </div>
                </div>
              </div>
            </div>

            <!-- Rows & Risk -->
            <div class="flex items-center gap-3 sm:gap-4 mb-3">
              <div class="flex items-center gap-1.5">
                <span class="text-[10px] sm:text-xs text-gray-400 font-medium uppercase tracking-wide">Rows</span>
                <div class="flex gap-0.5">
                  <button
                    :for={rows <- [8, 12, 16]}
                    phx-click="select_rows"
                    phx-value-rows={rows}
                    disabled={@game_state not in [:idle, :result]}
                    class={"px-2 sm:px-2.5 py-0.5 text-[10px] sm:text-xs font-semibold rounded transition-all cursor-pointer #{if @selected_rows == rows, do: "bg-gray-900 text-white", else: "bg-gray-100 text-gray-500 hover:bg-gray-200"}"}
                  >
                    <%= rows %>
                  </button>
                </div>
              </div>
              <div class="flex items-center gap-1.5">
                <span class="text-[10px] sm:text-xs text-gray-400 font-medium uppercase tracking-wide">Risk</span>
                <div class="flex gap-0.5">
                  <button
                    :for={{risk, label} <- [{:low, "Low"}, {:medium, "Med"}, {:high, "High"}]}
                    phx-click="select_risk"
                    phx-value-risk={risk}
                    disabled={@game_state not in [:idle, :result]}
                    class={"px-2 sm:px-2.5 py-0.5 text-[10px] sm:text-xs font-semibold rounded transition-all cursor-pointer #{if @selected_risk == risk, do: "bg-gray-900 text-white", else: "bg-gray-100 text-gray-500 hover:bg-gray-200"}"}
                  >
                    <%= label %>
                  </button>
                </div>
              </div>
            </div>

            <!-- Potential Profit Display -->
            <% max_mult_bp = if @payout_table, do: Enum.max(@payout_table), else: 0 %>
            <% max_profit = @bet_amount * max_mult_bp / 10000 - @bet_amount %>
            <div class="bg-green-50 rounded-xl p-2 sm:p-3 mb-3 border border-green-200">
              <div class="flex items-center justify-between">
                <span class="text-gray-700 text-xs sm:text-sm">Max Profit (<%= format_multiplier(max_mult_bp) %>):</span>
                <div class="flex items-center gap-1 sm:gap-3">
                  <span class="text-base sm:text-xl font-bold text-green-600 flex items-center gap-1 sm:gap-2">
                    <img src={Map.get(@token_logos, @selected_token, "https://ik.imagekit.io/blockster/blockster-icon.png")} alt={@selected_token} class="w-4 sm:w-5 h-4 sm:h-5 rounded-full" />
                    +<%= format_balance(max_profit) %>
                  </span>
                  <%= if @selected_token == "ROGUE" && @rogue_usd_price do %>
                    <span class="text-xs sm:text-sm text-green-500">
                      (<%= format_usd(@rogue_usd_price, max_profit) %>)
                    </span>
                  <% end %>
                </div>
              </div>
            </div>
          </div>

          <!-- Plinko Board (SVG) -->
          <div class="flex justify-center px-2 relative">
            <!-- Result overlay on board -->
            <%= if @game_state == :result do %>
              <% is_win = @payout >= @current_bet %>
              <div class="absolute inset-0 z-10 flex items-center justify-center pointer-events-none">
                <div class={"rounded-2xl px-6 py-4 text-center backdrop-blur-sm #{if is_win, do: "bg-green-50/90 border border-green-300", else: "bg-red-50/90 border border-red-300"}"}>
                  <div class={"text-4xl sm:text-5xl font-black plinko-result-pop #{if is_win, do: "text-green-600", else: "text-red-500"}"}>
                    <%= if @payout_multiplier do %>
                      <%= format_multiplier(trunc(@payout_multiplier * 10000)) %>
                    <% end %>
                  </div>
                  <div class={"text-sm font-bold tracking-wide mt-1 #{if is_win, do: "text-green-600", else: "text-red-500"}"}>
                    <%= cond do %>
                      <% @payout > @current_bet -> %>
                        +<%= format_balance(@payout - @current_bet) %> <%= @selected_token %>
                      <% @payout == @current_bet -> %>
                        PUSH
                      <% @payout == 0 -> %>
                        -<%= format_balance(@current_bet) %> <%= @selected_token %>
                      <% true -> %>
                        -<%= format_balance(@current_bet - @payout) %> <%= @selected_token %>
                    <% end %>
                  </div>
                </div>
              </div>
            <% end %>

            <svg
              viewBox={"0 0 400 #{board_height(@selected_rows)}"}
              class="w-full max-w-md mx-auto"
              id="plinko-board"
              phx-hook="PlinkoBall"
              data-game-id={@onchain_game_id}
            >
              <defs>
                <radialGradient id="ball-gradient" cx="30%" cy="25%" r="70%">
                  <stop offset="0%" stop-color="#e8e8e8" />
                  <stop offset="30%" stop-color="#b0b0b0" />
                  <stop offset="60%" stop-color="#787878" />
                  <stop offset="100%" stop-color="#3a3a3a" />
                </radialGradient>
                <filter id="ball-shadow" x="-50%" y="-50%" width="200%" height="200%">
                  <feDropShadow dx="0" dy="1" stdDeviation="2" flood-color="#000" flood-opacity="0.5" />
                </filter>
                <filter id="slot-glow" x="-50%" y="-50%" width="200%" height="200%">
                  <feGaussianBlur stdDeviation="4" result="blur" />
                  <feMerge>
                    <feMergeNode in="blur" />
                    <feMergeNode in="SourceGraphic" />
                  </feMerge>
                </filter>
              </defs>

              <!-- Pegs -->
              <%= for {x, y} <- peg_positions(@selected_rows) do %>
                <circle class="plinko-peg" cx={x} cy={y} r={peg_radius(@selected_rows)} fill="#9ca3af" />
              <% end %>

              <!-- Landing slots (cup-shaped receptacles) -->
              <% slot_w = 380 / (@selected_rows + 1) %>
              <% slot_y = board_height(@selected_rows) - 50 %>
              <% slot_h = 32 %>
              <% slot_r = if @selected_rows == 16, do: slot_w / 2.5, else: slot_w / 3 %>
              <%= for {k, x, _y} <- slot_positions(@selected_rows) do %>
                <% bp = Enum.at(@payout_table, k) %>
                <% left = x - slot_w / 2 %>
                <% right = x + slot_w / 2 %>
                <% bottom = slot_y + slot_h %>
                <!-- Cup shape: straight sides, rounded bottom -->
                <path
                  class="plinko-slot"
                  d={"M #{left} #{slot_y} L #{left} #{bottom - slot_r} Q #{left} #{bottom} #{left + slot_r} #{bottom} L #{right - slot_r} #{bottom} Q #{right} #{bottom} #{right} #{bottom - slot_r} L #{right} #{slot_y} Z"}
                  fill={slot_color(bp)}
                />
                <!-- Darker inner shadow for depth -->
                <path
                  d={"M #{left + 1} #{slot_y} L #{left + 1} #{bottom - slot_r} Q #{left + 1} #{bottom - 1} #{left + slot_r} #{bottom - 1} L #{right - slot_r} #{bottom - 1} Q #{right - 1} #{bottom - 1} #{right - 1} #{bottom - slot_r} L #{right - 1} #{slot_y}"}
                  fill="none"
                  stroke="rgba(0,0,0,0.15)"
                  stroke-width="2"
                />
                <text
                  x={x}
                  y={slot_y + slot_h / 2 + 3}
                  text-anchor="middle"
                  fill={slot_text_color(bp)}
                  font-size={if @selected_rows == 16, do: "7", else: "10"}
                  font-weight="bold"
                  style="text-shadow: 0 0 4px rgba(0,0,0,0.5)"
                >
                  <%= format_multiplier(bp) %>
                </text>
                <!-- Divider walls between slots -->
                <rect
                  :if={k < @selected_rows}
                  x={right - 1.5}
                  y={slot_y - 6}
                  width="3"
                  height={slot_h / 2 + 6}
                  rx="1.5"
                  fill="#6b7280"
                />
              <% end %>

              <!-- Ball — wrapped in phx-update="ignore" so morphdom never
                   strips the client-side style.transform after landing -->
              <g id="plinko-ball-group" phx-update="ignore">
                <circle
                  id="plinko-ball"
                  cx="200"
                  cy="10"
                  r={ball_radius(@selected_rows)}
                  fill="url(#ball-gradient)"
                  filter="url(#ball-shadow)"
                />
              </g>
            </svg>
          </div>

          <!-- Action Button Area (always rendered to prevent layout shift) -->
          <div class="px-4 pb-1">
            <%= cond do %>
              <% @game_state == :idle -> %>
                <button
                  phx-click="drop_ball"
                  disabled={not @onchain_ready or @bet_amount <= 0 or @current_user == nil}
                  class={[
                    "w-full py-3 rounded-xl text-sm font-black tracking-wide transition-all cursor-pointer uppercase",
                    if(@onchain_ready and @bet_amount > 0 and @current_user,
                      do: "bg-gray-900 text-white hover:bg-black active:scale-[0.97]",
                      else: "bg-gray-200 text-gray-400 cursor-not-allowed")
                  ]}
                >
                  <%= cond do %>
                    <% @current_user == nil -> %>Login to Play
                    <% @onchain_initializing -> %>Initializing...
                    <% not @onchain_ready -> %>Game Not Ready
                    <% true -> %>Drop Ball
                  <% end %>
                </button>

              <% @game_state == :dropping -> %>
                <div class="w-full py-3 rounded-xl text-sm font-black tracking-wide bg-[#CAFC00] text-black cursor-not-allowed flex items-center justify-center gap-2 uppercase">
                  <div class="w-4 h-4 border-2 border-[#a8d600] border-t-black rounded-full animate-spin"></div>
                  Dropping...
                </div>

              <% @game_state == :result -> %>
                <button
                  phx-click="reset_game"
                  class="w-full py-3 rounded-xl bg-[#CAFC00] text-black text-sm font-black tracking-wide hover:bg-[#b8e600] active:scale-[0.97] cursor-pointer uppercase transition-all"
                >
                  Play Again
                </button>

                <!-- Confetti -->
                <div :for={piece <- @confetti_pieces} class="fixed pointer-events-none z-50"
                  style={"left: #{piece.x}%; top: -10px; animation: confetti-fall #{1.5 + piece.delay / 1000}s linear forwards; animation-delay: #{piece.delay}ms;"}>
                  <div style={"width: #{piece.size}px; height: #{piece.size}px; background: #{piece.color}; border-radius: 2px;"}></div>
                </div>

              <% true -> %>
                <div class="py-3"></div>
            <% end %>
          </div>

          <!-- Provably Fair / Verify link (always same position below button) -->
          <div class="px-4 pb-3 flex justify-center h-7">
            <%= if @game_state == :result and @settlement_tx do %>
              <button
                type="button"
                phx-click="show_fairness_modal"
                phx-value-game_id={@onchain_game_id}
                class="text-xs text-gray-500 hover:text-gray-700 flex items-center gap-1 cursor-pointer"
              >
                <svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
                </svg>
                Verify Fairness
              </button>
            <% else %>
              <%= if @commitment_hash do %>
                <button
                  type="button"
                  phx-click="toggle_provably_fair"
                  class="text-xs text-gray-500 cursor-pointer hover:text-gray-700 flex items-center gap-1"
                >
                  <svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
                  </svg>
                  Provably Fair
                </button>
              <% end %>
            <% end %>
          </div>

          <!-- Provably Fair pre-game modal -->
          <%= if @show_provably_fair and @commitment_hash do %>
            <div class="fixed inset-0 bg-black/50 flex items-end sm:items-center justify-center z-50 p-0 sm:p-4" phx-click="close_provably_fair">
              <div class="bg-white rounded-none sm:rounded-2xl w-full max-w-xs shadow-xl" phx-click="stop_propagation">
                <div class="p-3 sm:p-4 border-b flex items-center justify-between bg-gray-50 sm:rounded-t-2xl">
                  <div class="flex items-center gap-2">
                    <svg class="w-4 h-4 text-green-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
                    </svg>
                    <h3 class="text-sm font-bold text-gray-900">Provably Fair</h3>
                  </div>
                  <button type="button" phx-click="close_provably_fair" class="text-gray-400 hover:text-gray-600 cursor-pointer">
                    <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                    </svg>
                  </button>
                </div>
                <div class="p-3 sm:p-4">
                  <p class="text-[10px] sm:text-xs text-gray-600 mb-3">
                    This hash commits the server to a result BEFORE you place your bet.
                    After the game, you can verify the result was fair.
                  </p>
                  <label class="text-[10px] sm:text-xs font-medium text-gray-500 uppercase tracking-wide">Commitment Hash</label>
                  <a
                    href={"https://roguescan.io/tx/#{@commitment_tx}?tab=logs"}
                    target="_blank"
                    rel="noopener noreferrer"
                    class="mt-1 text-[10px] sm:text-xs font-mono bg-gray-50 px-2 py-1.5 rounded border border-gray-200 text-blue-500 hover:underline cursor-pointer block break-all"
                  >
                    <%= @commitment_hash %>
                  </a>
                  <p class="text-xs text-gray-400 mt-2">
                    Game #<%= @nonce %>
                  </p>
                </div>
              </div>
            </div>
          <% end %>
        </div>

        <!-- Fairness Modal (bottom-sheet on mobile) -->
        <%= if @show_fairness_modal and @fairness_game do %>
          <div class="fixed inset-0 bg-black/50 flex items-end sm:items-center justify-center z-50 p-0 sm:p-4" phx-click="hide_fairness_modal">
            <div class="bg-white rounded-none sm:rounded-2xl w-full sm:max-w-lg max-h-[100vh] sm:max-h-[90vh] overflow-y-auto shadow-xl" phx-click="stop_propagation">
              <!-- Header -->
              <div class="p-3 sm:p-4 border-b flex items-center justify-between bg-gray-50 sm:rounded-t-2xl sticky top-0 z-10">
                <div class="flex items-center gap-2">
                  <svg class="w-4 sm:w-5 h-4 sm:h-5 text-green-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
                  </svg>
                  <h2 class="text-base sm:text-lg font-bold text-gray-900">Provably Fair Verification</h2>
                </div>
                <button type="button" phx-click="hide_fairness_modal" class="text-gray-400 hover:text-gray-600 cursor-pointer">
                  <svg class="w-5 sm:w-6 h-5 sm:h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                  </svg>
                </button>
              </div>

              <!-- Content -->
              <div class="p-3 sm:p-4 space-y-3 sm:space-y-4">
                <!-- Bet Details -->
                <div class="bg-blue-50 rounded-lg p-2 sm:p-3 border border-blue-200">
                  <p class="text-xs sm:text-sm font-medium text-blue-800 mb-1 sm:mb-2">Your Bet Details</p>
                  <p class="text-[10px] sm:text-xs text-blue-600 mb-2">These player-controlled values derive your client seed:</p>
                  <div class="grid grid-cols-2 gap-1 sm:gap-2 text-xs sm:text-sm">
                    <div class="text-blue-600">User ID:</div>
                    <div class="font-mono text-[10px] sm:text-xs"><%= @fairness_game.user_id %></div>
                    <div class="text-blue-600">Bet Amount:</div>
                    <div class="text-xs sm:text-sm"><%= @fairness_game.bet_amount %> <%= @fairness_game.token %></div>
                    <div class="text-blue-600">Config:</div>
                    <div class="text-xs sm:text-sm"><%= @fairness_game.rows %> rows, <%= @fairness_game.risk_level %> risk (index <%= @fairness_game.config_index %>)</div>
                  </div>
                </div>

                <!-- Nonce -->
                <div class="bg-gray-50 rounded-lg p-2 sm:p-3">
                  <div class="flex justify-between items-center">
                    <span class="text-xs sm:text-sm text-gray-600">Game Nonce:</span>
                    <span class="font-mono text-xs sm:text-sm"><%= @fairness_game.nonce %></span>
                  </div>
                  <p class="text-[10px] sm:text-xs text-gray-500 mt-1">
                    Ensures unique results even for identical bets
                  </p>
                </div>

                <!-- Seeds -->
                <div class="space-y-2 sm:space-y-3">
                  <div>
                    <label class="text-xs sm:text-sm font-medium text-gray-700">Server Seed (revealed)</label>
                    <code class="mt-1 text-[10px] sm:text-xs font-mono bg-gray-100 px-2 py-1.5 sm:py-2 rounded break-all block overflow-x-auto">
                      <%= @fairness_game.server_seed %>
                    </code>
                  </div>

                  <div>
                    <label class="text-xs sm:text-sm font-medium text-gray-700">Server Commitment (shown before bet)</label>
                    <code class="mt-1 text-[10px] sm:text-xs font-mono bg-gray-100 px-2 py-1.5 sm:py-2 rounded break-all block overflow-x-auto">
                      <%= String.replace_leading(@fairness_game.commitment_hash || "", "0x", "") %>
                    </code>
                  </div>

                  <div>
                    <label class="text-xs sm:text-sm font-medium text-gray-700">Client Seed (derived from bet details)</label>
                    <code class="mt-1 text-[10px] sm:text-xs font-mono bg-gray-100 px-2 py-1.5 sm:py-2 rounded break-all block overflow-x-auto">
                      <%= @fairness_game.client_seed %>
                    </code>
                    <p class="text-[10px] sm:text-xs text-gray-500 mt-1 break-all">
                      = SHA256("<%= @fairness_game.client_seed_input %>")
                    </p>
                  </div>

                  <div>
                    <label class="text-xs sm:text-sm font-medium text-gray-700">Combined Seed</label>
                    <code class="mt-1 text-[10px] sm:text-xs font-mono bg-gray-100 px-2 py-1.5 sm:py-2 rounded break-all block overflow-x-auto">
                      <%= @fairness_game.combined_seed %>
                    </code>
                    <p class="text-[10px] sm:text-xs text-gray-500 mt-1">
                      = SHA256(server_seed + ":" + client_seed + ":" + nonce)
                    </p>
                  </div>
                </div>

                <!-- Verification Steps -->
                <div class="bg-green-50 rounded-lg p-2 sm:p-3 border border-green-200">
                  <p class="text-xs sm:text-sm font-medium text-green-800 mb-1 sm:mb-2">Verification Steps</p>
                  <ol class="text-[10px] sm:text-sm text-green-700 space-y-0.5 sm:space-y-1 list-decimal ml-4">
                    <li>SHA256(server_seed) = commitment</li>
                    <li>client_seed = SHA256(user_id:bet_amount:token:config_index)</li>
                    <li>combined_seed = SHA256(server:client:nonce)</li>
                    <li>First <%= @fairness_game.rows %> bytes of combined seed determine ball path</li>
                    <li>Each byte &lt; 128 = LEFT, &ge; 128 = RIGHT</li>
                    <li>Landing position = count of RIGHT bounces</li>
                  </ol>
                </div>

                <!-- Ball Path Breakdown -->
                <div>
                  <p class="text-xs sm:text-sm font-medium text-gray-700 mb-1 sm:mb-2">Ball Path (<%= @fairness_game.rows %> rows)</p>
                  <div class="space-y-1 sm:space-y-1.5">
                    <%= for i <- 0..(@fairness_game.rows - 1) do %>
                      <% byte = Enum.at(@fairness_game.bytes, i) %>
                      <% dir = if byte < 128, do: :left, else: :right %>
                      <div class="flex items-center justify-between text-xs sm:text-sm bg-gray-50 p-1.5 sm:p-2 rounded">
                        <span>Row <%= i + 1 %>:</span>
                        <div class="flex items-center gap-1 sm:gap-2">
                          <span class="font-mono text-[10px] sm:text-xs">byte[<%= i %>]=<%= byte %></span>
                          <span class={if dir == :left, do: "text-blue-600 font-semibold", else: "text-amber-600 font-semibold"}>
                            <%= if dir == :left, do: "LEFT", else: "RIGHT" %>
                          </span>
                          <span class="text-[10px] sm:text-xs text-gray-400 hidden sm:inline">
                            (<%= if byte < 128, do: "< 128", else: ">= 128" %>)
                          </span>
                        </div>
                      </div>
                    <% end %>
                  </div>
                  <div class="mt-2 bg-gray-50 rounded-lg p-2 sm:p-3">
                    <div class="flex justify-between items-center text-xs sm:text-sm">
                      <span class="text-gray-600">Landing Position:</span>
                      <span class="font-bold">Slot <%= @fairness_game.landing_position %> (<%= Enum.count(@fairness_game.ball_path || [], &(&1 == :right)) %> rights)</span>
                    </div>
                    <div class="flex justify-between items-center text-xs sm:text-sm mt-1">
                      <span class="text-gray-600">Payout Multiplier:</span>
                      <span class="font-bold"><%= format_multiplier(@fairness_game.payout_bp) %></span>
                    </div>
                    <div class="flex justify-between items-center text-xs sm:text-sm mt-1">
                      <span class="text-gray-600">Payout:</span>
                      <span class="font-bold"><%= format_balance(@fairness_game.payout) %> <%= @fairness_game.token %></span>
                    </div>
                  </div>
                </div>

                <!-- External Verification -->
                <div class="border-t pt-3 sm:pt-4">
                  <p class="text-xs sm:text-sm font-medium text-gray-700 mb-1 sm:mb-2">Verify Externally</p>
                  <p class="text-[10px] sm:text-xs text-gray-500 mb-2 sm:mb-3">
                    Click each link to verify using an online SHA256 calculator:
                  </p>
                  <div class="space-y-2 sm:space-y-3">
                    <div class="bg-gray-50 rounded-lg p-2 sm:p-3">
                      <p class="text-[10px] sm:text-xs text-gray-600 mb-1">1. Verify server commitment</p>
                      <a href={"https://md5calc.com/hash/sha256/#{@fairness_game.server_seed}"} target="_blank" class="text-blue-500 hover:underline text-[10px] sm:text-xs cursor-pointer">
                        SHA256(server_seed) &rarr; Click to verify
                      </a>
                      <p class="text-[10px] sm:text-xs text-gray-400 mt-1 font-mono break-all">Expected: <%= String.replace_leading(@fairness_game.commitment_hash || "", "0x", "") %></p>
                    </div>

                    <div class="bg-gray-50 rounded-lg p-2 sm:p-3">
                      <p class="text-[10px] sm:text-xs text-gray-600 mb-1">2. Derive client seed from bet details</p>
                      <a href={"https://md5calc.com/hash/sha256/#{@fairness_game.client_seed_input}"} target="_blank" class="text-blue-500 hover:underline text-[10px] sm:text-xs cursor-pointer">
                        SHA256(bet_details) &rarr; Click to verify
                      </a>
                      <p class="text-[10px] sm:text-xs text-gray-400 mt-1 font-mono break-all">Expected: <%= @fairness_game.client_seed %></p>
                    </div>

                    <div class="bg-gray-50 rounded-lg p-2 sm:p-3">
                      <p class="text-[10px] sm:text-xs text-gray-600 mb-1">3. Generate combined seed</p>
                      <a href={"https://md5calc.com/hash/sha256/#{@fairness_game.server_seed}:#{@fairness_game.client_seed}:#{@fairness_game.nonce}"} target="_blank" class="text-blue-500 hover:underline text-[10px] sm:text-xs cursor-pointer">
                        SHA256(server:client:nonce) &rarr; Click to verify
                      </a>
                      <p class="text-[10px] sm:text-xs text-gray-400 mt-1 font-mono break-all">Expected: <%= @fairness_game.combined_seed %></p>
                    </div>

                    <div class="bg-gray-50 rounded-lg p-2 sm:p-3">
                      <p class="text-[10px] sm:text-xs text-gray-600 mb-1">4. Convert hex to bytes for ball path</p>
                      <p class="text-[10px] sm:text-xs text-gray-500 mb-2">
                        First <%= @fairness_game.rows %> byte pairs from the combined seed:
                      </p>
                      <!-- Combined seed with highlighted byte pairs -->
                      <div class="bg-white rounded p-1.5 sm:p-2 border font-mono text-[10px] sm:text-xs leading-relaxed break-all">
                        <%= for i <- 0..(String.length(@fairness_game.combined_seed) |> div(2)) - 1 do %>
                          <% pair = String.slice(@fairness_game.combined_seed, i * 2, 2) %>
                          <% byte = Enum.at(@fairness_game.bytes, i) %>
                          <%= if i < @fairness_game.rows do %>
                            <span class={"inline-block px-0.5 rounded #{if byte < 128, do: "bg-blue-100 text-blue-700", else: "bg-amber-200 text-amber-700"}"} title={"Row #{i + 1}: #{pair} = #{byte} → #{if byte < 128, do: "LEFT", else: "RIGHT"}"}><%= pair %></span>
                          <% else %>
                            <span class="text-gray-300"><%= pair %></span>
                          <% end %>
                        <% end %>
                      </div>
                      <!-- Mapped results -->
                      <div class="mt-2 space-y-0.5">
                        <%= for {byte, i} <- Enum.with_index(@fairness_game.bytes) do %>
                          <div class="flex items-center gap-1.5 text-[10px] sm:text-xs">
                            <span class={"inline-block font-mono px-1 py-0.5 rounded #{if byte < 128, do: "bg-blue-100 text-blue-700", else: "bg-amber-200 text-amber-700"}"}>
                              <%= String.slice(@fairness_game.combined_seed, i * 2, 2) %>
                            </span>
                            <span class="text-gray-400">=</span>
                            <span class="font-mono text-gray-600"><%= byte %></span>
                            <span class={"font-mono text-[10px] sm:text-xs px-1 py-0.5 rounded #{if byte < 128, do: "bg-blue-50 text-blue-500", else: "bg-amber-50 text-amber-500"}"}>
                              <%= if byte < 128, do: "< 128", else: "≥ 128" %>
                            </span>
                            <span class="text-gray-400">&rarr;</span>
                            <span class={"font-bold #{if byte < 128, do: "text-blue-600", else: "text-amber-600"}"}>
                              <%= if byte < 128, do: "LEFT", else: "RIGHT" %>
                            </span>
                          </div>
                        <% end %>
                      </div>
                      <p class="text-[10px] sm:text-xs text-gray-400 mt-2">
                        Verify: <a href="https://www.rapidtables.com/convert/number/hex-to-decimal.html" target="_blank" class="text-blue-500 hover:underline cursor-pointer">Hex to Decimal converter</a>
                      </p>
                    </div>
                  </div>
                </div>
              </div>

              <!-- Footer -->
              <div class="p-3 sm:p-4 border-t bg-gray-50 sm:rounded-b-2xl">
                <button type="button" phx-click="hide_fairness_modal" class="w-full py-2 bg-gray-200 text-gray-700 rounded-lg hover:bg-gray-300 transition-all cursor-pointer">
                  Close
                </button>
              </div>
            </div>
          </div>
        <% end %>

        <!-- Game History Table -->
        <div class="mt-6">
          <div class="bg-white rounded-xl p-3 sm:p-4 shadow-sm border border-gray-200">
            <h3 class="text-[#141414] font-bold text-sm mb-2">Game History</h3>
            <div id="game-history-scroll" class="overflow-x-auto overflow-y-auto max-h-72 sm:max-h-96 relative" phx-hook="InfiniteScroll" data-event="load-more-games">
              <table class="w-full min-w-[600px] text-[10px] sm:text-xs">
                <thead class="sticky top-0 z-20 bg-white">
                  <tr class="text-gray-500 border-b-2 border-gray-200 bg-white">
                    <th class="text-left py-2 px-1 bg-white">ID</th>
                    <th class="text-left py-2 px-1 bg-white">Bet</th>
                    <th class="text-left py-2 px-1 bg-white">Config</th>
                    <th class="text-left py-2 px-1 bg-white">Landing</th>
                    <th class="text-left py-2 px-1 bg-white">Mult</th>
                    <th class="text-right py-2 px-1 bg-white">P/L</th>
                    <th class="text-right py-2 px-1 bg-white">Verify</th>
                  </tr>
                </thead>
                <tbody id="game-history" phx-update="stream">
                  <tr :for={{dom_id, game} <- @streams.game_history} id={dom_id} class={"border-b border-gray-100 #{if game.payout >= game.bet_amount, do: "bg-green-50/30", else: "bg-red-50/30"}"}>
                    <!-- Bet ID (nonce linked to commitment tx) -->
                    <td class="py-1.5 px-1">
                      <%= if game.commitment_tx do %>
                        <a href={"https://roguescan.io/tx/#{game.commitment_tx}?tab=logs"} target="_blank" class="text-blue-500 hover:underline cursor-pointer font-mono">
                          #<%= game.nonce %>
                        </a>
                      <% else %>
                        <span class="font-mono text-gray-500">#<%= game.nonce %></span>
                      <% end %>
                    </td>
                    <!-- Bet Amount (linked to bet placement tx) -->
                    <td class="py-1.5 px-1">
                      <%= if game.bet_tx do %>
                        <a href={"https://roguescan.io/tx/#{game.bet_tx}?tab=logs"} target="_blank" class="text-blue-500 hover:underline cursor-pointer flex items-center gap-1">
                          <img src={Map.get(@token_logos, game.token, "https://ik.imagekit.io/blockster/blockster-icon.png")} alt={game.token} class="w-3 sm:w-4 h-3 sm:h-4 rounded-full" />
                          <span><%= format_balance(game.bet_amount) %></span>
                        </a>
                      <% else %>
                        <div class="flex items-center gap-1">
                          <img src={Map.get(@token_logos, game.token, "https://ik.imagekit.io/blockster/blockster-icon.png")} alt={game.token} class="w-3 sm:w-4 h-3 sm:h-4 rounded-full" />
                          <span class="text-gray-900"><%= format_balance(game.bet_amount) %></span>
                        </div>
                      <% end %>
                    </td>
                    <td class="py-1.5 px-1 text-gray-500"><%= game.rows %>-<%= game.risk_level %></td>
                    <td class="py-1.5 px-1 text-gray-500"><%= game.landing_position %></td>
                    <td class="py-1.5 px-1 text-gray-500"><%= format_multiplier(game.payout_bp) %></td>
                    <!-- P/L (linked to settlement tx) -->
                    <td class="py-1.5 px-1 text-right whitespace-nowrap">
                      <% pl = game.payout - game.bet_amount %>
                      <% {pl_sign, pl_color} = if pl >= 0, do: {"+", "text-green-600"}, else: {"-", "text-red-600"} %>
                      <%= if game.settlement_tx do %>
                        <a href={"https://roguescan.io/tx/#{game.settlement_tx}?tab=logs"} target="_blank" class={"#{pl_color} hover:underline cursor-pointer font-medium"}>
                          <%= pl_sign %><%= format_balance(abs(pl)) %>
                        </a>
                      <% else %>
                        <span class={"#{pl_color} font-medium"}>
                          <%= pl_sign %><%= format_balance(abs(pl)) %>
                        </span>
                      <% end %>
                    </td>
                    <td class="py-1.5 px-1 text-right">
                      <button
                        phx-click="show_fairness_modal"
                        phx-value-game_id={game.game_id}
                        class="text-blue-500 hover:underline cursor-pointer"
                      >
                        Verify
                      </button>
                    </td>
                  </tr>
                </tbody>
              </table>
              <div :if={@games_loading} class="text-center py-4">
                <div class="flex items-center justify-center">
                  <div class="w-5 h-5 border-2 border-gray-300 border-t-[#CAFC00] rounded-full animate-spin"></div>
                  <span class="ml-2 text-gray-500 text-xs">Loading...</span>
                </div>
              </div>
            </div>

          </div>
        </div>
      </div>
    </div>
    """
  end

  # ============ Config Selection ============

  @impl true
  def handle_event("select_rows", %{"rows" => rows_str}, socket) do
    rows = String.to_integer(rows_str)
    risk = socket.assigns.selected_risk
    config_index = config_index_for(rows, risk)
    payout_table = Map.get(@payout_tables, config_index)

    socket =
      socket
      |> assign(selected_rows: rows, config_index: config_index, payout_table: payout_table, error_message: nil)
      |> maybe_update_max_bet(config_index)
      |> push_event("reset_ball", %{})

    socket = if socket.assigns.game_state == :result, do: reset_for_new_game(socket), else: socket

    {:noreply, socket}
  end

  def handle_event("select_risk", %{"risk" => risk_str}, socket) do
    risk = String.to_existing_atom(risk_str)
    rows = socket.assigns.selected_rows
    config_index = config_index_for(rows, risk)
    payout_table = Map.get(@payout_tables, config_index)

    socket =
      socket
      |> assign(selected_risk: risk, config_index: config_index, payout_table: payout_table, error_message: nil)
      |> maybe_update_max_bet(config_index)

    socket = if socket.assigns.game_state == :result, do: reset_for_new_game(socket), else: socket

    {:noreply, socket}
  end

  # ============ Bet Amount Controls ============

  def handle_event("update_bet_amount", %{"value" => value_str}, socket) do
    case Integer.parse(value_str) do
      {amount, _} ->
        clamped = amount |> max(0) |> min(socket.assigns.max_bet)
        socket = assign(socket, bet_amount: clamped, error_message: nil)
        socket = if socket.assigns.game_state == :result, do: reset_for_new_game(socket), else: socket
        {:noreply, socket}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("halve_bet", _params, socket) do
    new_amount = max(div(socket.assigns.bet_amount, 2), 1)
    socket = assign(socket, bet_amount: new_amount, error_message: nil)
    socket = if socket.assigns.game_state == :result, do: reset_for_new_game(socket), else: socket
    {:noreply, socket}
  end

  def handle_event("double_bet", _params, socket) do
    doubled = socket.assigns.bet_amount * 2
    new_amount = if socket.assigns.max_bet > 0, do: min(doubled, socket.assigns.max_bet), else: doubled
    socket = assign(socket, bet_amount: new_amount, error_message: nil)
    socket = if socket.assigns.game_state == :result, do: reset_for_new_game(socket), else: socket
    {:noreply, socket}
  end

  def handle_event("set_max_bet", _params, socket) do
    socket = assign(socket, bet_amount: socket.assigns.max_bet, error_message: nil)
    socket = if socket.assigns.game_state == :result, do: reset_for_new_game(socket), else: socket
    {:noreply, socket}
  end

  # ============ Token Selection ============

  def handle_event("toggle_token_dropdown", _params, socket) do
    {:noreply, assign(socket, show_token_dropdown: not socket.assigns.show_token_dropdown, error_message: nil)}
  end

  def handle_event("hide_token_dropdown", _params, socket) do
    {:noreply, assign(socket, show_token_dropdown: false)}
  end

  def handle_event("select_token", %{"token" => token}, socket) do
    socket =
      socket
      |> assign(selected_token: token, header_token: token, show_token_dropdown: false, error_message: nil)
      |> start_async(:fetch_house_balance, fn ->
        if token == "ROGUE" do
          BuxMinter.get_house_balance()
        else
          BuxMinter.bux_bankroll_house_info()
        end
      end)

    socket = if socket.assigns.game_state == :result, do: reset_for_new_game(socket), else: socket

    {:noreply, socket}
  end

  # ============ Main Action: Drop Ball ============

  def handle_event("drop_ball", _params, socket) do
    socket = assign(socket, error_message: nil)
    %{
      current_user: user,
      bet_amount: bet_amount,
      selected_token: token,
      config_index: config_index,
      onchain_ready: ready,
      onchain_game_id: game_id
    } = socket.assigns

    cond do
      not ready ->
        {:noreply, assign(socket, error_message: "Game not ready")}

      bet_amount <= 0 ->
        {:noreply, assign(socket, error_message: "Invalid bet")}

      get_balance(socket.assigns, token) < bet_amount ->
        {:noreply, assign(socket, error_message: "Insufficient balance")}

      token == "ROGUE" and bet_amount < 100 ->
        {:noreply, assign(socket, error_message: "Minimum ROGUE bet: 100")}

      true ->
        # Optimistic balance deduction
        wallet = socket.assigns.wallet_address
        EngagementTracker.deduct_user_token_balance(user.id, wallet, token, bet_amount)

        # Mark game so it won't be reused by get_or_init_game on next Play Again
        PlinkoGame.mark_game_playing(game_id)

        # Calculate result (uses stored server seed)
        {:ok, result} =
          PlinkoGame.calculate_game_result(game_id, config_index, bet_amount, token, user.id)

        # Start animation + push bet to JS
        socket =
          socket
          |> assign(game_state: :dropping, current_bet: bet_amount, show_provably_fair: false)
          |> assign(ball_path: result.ball_path, landing_position: result.landing_position)
          |> assign(payout: result.payout, payout_multiplier: result.payout_bp / 10000)
          |> assign(won: result.won)
          |> push_event("drop_ball", %{
            ball_path: Enum.map(result.ball_path, fn :left -> 0; :right -> 1 end),
            landing_position: result.landing_position,
            rows: socket.assigns.selected_rows
          })
          |> push_event("place_bet_background", %{
            game_id: game_id,
            commitment_hash: socket.assigns.commitment_hash,
            token: token,
            token_address: PlinkoGame.token_address(token),
            amount: bet_amount,
            config_index: config_index
          })

        {:noreply, socket}
    end
  end

  # ============ JS pushEvent Handlers ============

  def handle_event("bet_confirmed", %{"game_id" => game_id, "tx_hash" => tx_hash} = params, socket) do
    confirmation_time = Map.get(params, "confirmation_time_ms", 0)
    Logger.info("[PlinkoLive] Bet confirmed for #{game_id} in #{confirmation_time}ms: #{tx_hash}")

    # Update Mnesia with bet details
    {:ok, _result} =
      PlinkoGame.on_bet_placed(
        game_id,
        socket.assigns.commitment_hash,
        tx_hash,
        socket.assigns.current_bet,
        socket.assigns.selected_token,
        socket.assigns.config_index
      )

    # Schedule settlement to fire when animation should be done (safety net if page closes)
    # Animation: 8 rows = 2800ms, 12 rows = 3400ms, 16 rows = 4000ms, + 600ms landing bounce
    animation_ms = case socket.assigns.selected_rows do
      8 -> 3400
      12 -> 4000
      _ -> 4600
    end
    settle_timer = Process.send_after(self(), {:settle_after_animation, game_id}, animation_ms)

    {:noreply, assign(socket, bet_tx: tx_hash, bet_id: socket.assigns.commitment_hash, settle_timer: settle_timer)}
  end

  def handle_event("bet_failed", %{"game_id" => _game_id, "error" => error}, socket) do
    user = socket.assigns.current_user

    # Refund optimistic balance deduction
    EngagementTracker.credit_user_token_balance(
      user.id,
      socket.assigns.wallet_address,
      socket.assigns.selected_token,
      socket.assigns.current_bet
    )

    {:noreply,
     socket
     |> assign(game_state: :idle, error_message: error)
     |> assign(ball_path: [], landing_position: nil)
     |> push_event("reset_ball", %{})}
  end

  def handle_event("ball_landed", _params, socket) do
    # Animation complete - transition to result state
    confetti =
      if socket.assigns.payout_multiplier && socket.assigns.payout_multiplier >= 5.0 do
        generate_confetti(100)
      else
        []
      end

    # Cancel the safety timer and settle now
    if timer = socket.assigns[:settle_timer] do
      Process.cancel_timer(timer)
    end

    game_id = socket.assigns.onchain_game_id

    socket =
      socket
      |> assign(game_state: :result, confetti_pieces: confetti, settle_timer: nil)
      |> start_async(:settle_game, fn ->
        PlinkoGame.settle_game(game_id)
      end)

    {:noreply, socket}
  end

  # ============ Reset / Play Again ============

  def handle_event("reset_game", _params, socket) do
    {:noreply, reset_for_new_game(socket)}
  end

  defp reset_for_new_game(socket) do
    user = socket.assigns.current_user
    wallet = socket.assigns.wallet_address

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
      onchain_ready: false,
      onchain_initializing: true,
      bet_tx: nil,
      bet_id: nil,
      settlement_tx: nil
    )
    |> push_event("reset_ball", %{})
    |> start_async(:init_onchain_game, fn ->
      PlinkoGame.get_or_init_game(user.id, wallet)
    end)
    |> start_async(:fetch_house_balance, fn ->
      BuxMinter.bux_bankroll_house_info()
    end)
  end

  # ============ Fairness Modal ============

  def handle_event("toggle_provably_fair", _params, socket) do
    {:noreply, assign(socket, show_provably_fair: !socket.assigns.show_provably_fair)}
  end

  def handle_event("close_provably_fair", _params, socket) do
    {:noreply, assign(socket, show_provably_fair: false)}
  end

  def handle_event("show_fairness_modal", %{"game_id" => game_id}, socket) do
    case PlinkoGame.get_game(game_id) do
      {:ok, game} when game.status == :settled ->
        # Compute derived values for detailed verification display
        client_seed_input = "#{game.user_id}:#{game.bet_amount}:#{game.token}:#{game.config_index}"
        client_seed = :crypto.hash(:sha256, client_seed_input) |> Base.encode16(case: :lower)
        combined_seed = :crypto.hash(:sha256, "#{game.server_seed}:#{client_seed}:#{game.nonce}") |> Base.encode16(case: :lower)

        bytes =
          combined_seed
          |> Base.decode16!(case: :lower)
          |> :binary.bin_to_list()
          |> Enum.take(game.rows)

        fairness_game = Map.merge(game, %{
          client_seed_input: client_seed_input,
          client_seed: client_seed,
          combined_seed: combined_seed,
          bytes: bytes
        })

        {:noreply, assign(socket, show_fairness_modal: true, fairness_game: fairness_game)}

      {:ok, _game} ->
        {:noreply, assign(socket, error_message: "Game must be settled to verify fairness")}

      {:error, _} ->
        {:noreply, assign(socket, error_message: "Game not found")}
    end
  end

  def handle_event("hide_fairness_modal", _params, socket) do
    {:noreply, assign(socket, show_fairness_modal: false, fairness_game: nil)}
  end

  # ============ Game History ============

  def handle_event("load-more-games", _params, socket) do
    if socket.assigns.has_more_games do
      user = socket.assigns.current_user
      new_offset = socket.assigns.games_offset + 30

      socket =
        socket
        |> assign(games_loading: true, games_offset: new_offset)
        |> start_async(:load_more_games, fn ->
          PlinkoGame.load_recent_games(user.id, limit: 30, offset: new_offset)
        end)

      {:reply, %{}, socket}
    else
      {:reply, %{end_reached: true}, socket}
    end
  end

  # ============ Clear Error ============

  def handle_event("clear_error", _params, socket) do
    {:noreply, assign(socket, error_message: nil)}
  end

  def handle_event("stop_propagation", _params, socket) do
    {:noreply, socket}
  end

  # ============ Settlement Timer ============

  @impl true
  def handle_info({:settle_after_animation, game_id}, socket) do
    # Safety net: animation timer expired, settle if not already settling/settled
    if socket.assigns.onchain_game_id == game_id and socket.assigns.settlement_tx == nil do
      Logger.info("[PlinkoLive] Animation timer expired, settling #{game_id}")

      socket =
        socket
        |> assign(settle_timer: nil)
        |> start_async(:settle_game, fn ->
          PlinkoGame.settle_game(game_id)
        end)

      {:noreply, socket}
    else
      {:noreply, assign(socket, settle_timer: nil)}
    end
  end

  # ============ PubSub Messages ============

  @impl true
  def handle_info({:bux_balance_updated, balance}, socket) do
    updated_balances = Map.put(socket.assigns.balances, "BUX", balance)
    {:noreply, assign(socket, balances: updated_balances)}
  end

  def handle_info({:token_balances_updated, balances}, socket) do
    {:noreply, assign(socket, balances: balances)}
  end

  def handle_info({:plinko_settled, game_id, tx_hash}, socket) do
    socket =
      if socket.assigns.onchain_game_id == game_id do
        assign(socket, settlement_tx: tx_hash)
      else
        socket
      end

    case PlinkoGame.get_game(game_id) do
      {:ok, game} when game.status == :settled ->
        recent = [game | socket.assigns.recent_games]
        {:noreply,
         socket
         |> assign(recent_games: recent)
         |> stream_insert(:game_history, game, at: 0)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_info({:token_prices_updated, _prices}, socket) do
    {:noreply, assign(socket, rogue_usd_price: get_rogue_price())}
  end

  def handle_info(:retry_init, socket) do
    user = socket.assigns.current_user
    wallet = socket.assigns.wallet_address

    socket =
      socket
      |> start_async(:init_onchain_game, fn ->
        PlinkoGame.get_or_init_game(user.id, wallet)
      end)

    {:noreply, socket}
  end

  # Catch-all for unhandled messages
  def handle_info(_msg, socket), do: {:noreply, socket}

  # ============ Async Handlers ============

  # init_onchain_game — success
  @impl true
  def handle_async(:init_onchain_game, {:ok, {:ok, game_data}}, socket) do
    {:noreply,
     socket
     |> assign(
       onchain_ready: true,
       onchain_initializing: false,
       onchain_game_id: game_data.game_id,
       commitment_hash: game_data.commitment_hash,
       commitment_tx: game_data.commitment_tx,
       nonce: game_data.nonce
     )}
  end

  # init_onchain_game — error returned
  def handle_async(:init_onchain_game, {:ok, {:error, reason}}, socket) do
    Logger.error("[PlinkoLive] Init returned error: #{inspect(reason)}")
    handle_init_failure(socket, reason)
  end

  # init_onchain_game — task crashed
  def handle_async(:init_onchain_game, {:exit, reason}, socket) do
    Logger.error("[PlinkoLive] Init task crashed: #{inspect(reason)}")
    handle_init_failure(socket, reason)
  end

  # fetch_house_balance — success
  def handle_async(:fetch_house_balance, {:ok, {:ok, info}}, socket) do
    # totalBalance for display (matches bankroll page "Total BUX")
    display_balance =
      cond do
        is_map(info) and Map.has_key?(info, "totalBalance") ->
          String.to_integer(info["totalBalance"]) / 1.0e18

        is_map(info) and Map.has_key?(info, "houseBalance") ->
          String.to_integer(info["houseBalance"]) / 1.0e18

        true ->
          0.0
      end

    # netBalance for max bet calculation (available liquidity minus liability)
    available =
      cond do
        is_map(info) and Map.has_key?(info, "netBalance") ->
          String.to_integer(info["netBalance"]) / 1.0e18

        true ->
          display_balance
      end

    max_bet = calculate_max_bet(available, socket.assigns.config_index)

    {:noreply, assign(socket, house_balance: display_balance, max_bet: max_bet)}
  end

  def handle_async(:fetch_house_balance, {:ok, {:error, reason}}, socket) do
    Logger.warning("[PlinkoLive] Failed to fetch house balance: #{inspect(reason)}")
    {:noreply, socket}
  end

  def handle_async(:fetch_house_balance, {:exit, reason}, socket) do
    Logger.warning("[PlinkoLive] House balance task crashed: #{inspect(reason)}")
    {:noreply, socket}
  end

  # load_recent_games — success
  def handle_async(:load_recent_games, {:ok, games}, socket) do
    {:noreply,
     socket
     |> assign(recent_games: games, games_loading: false, has_more_games: length(games) >= 30)
     |> stream(:game_history, games)}
  end

  def handle_async(:load_recent_games, _, socket) do
    Logger.warning("[PlinkoLive] Failed to load recent games")
    {:noreply, assign(socket, games_loading: false)}
  end

  # load_more_games — append to existing
  def handle_async(:load_more_games, {:ok, new_games}, socket) do
    {:noreply,
     socket
     |> assign(recent_games: socket.assigns.recent_games ++ new_games, games_loading: false, has_more_games: length(new_games) >= 30)
     |> stream(:game_history, new_games)}
  end

  def handle_async(:load_more_games, _, socket) do
    {:noreply, assign(socket, games_loading: false)}
  end

  # settle_game — async settlement after bet confirmed
  def handle_async(:settle_game, {:ok, {:ok, %{tx_hash: tx_hash}}}, socket) do
    # Re-fetch house balance after settlement (bankroll changed)
    socket =
      socket
      |> assign(settlement_tx: tx_hash)
      |> start_async(:fetch_house_balance, fn ->
        BuxMinter.bux_bankroll_house_info()
      end)

    {:noreply, socket}
  end

  def handle_async(:settle_game, {:ok, {:error, reason}}, socket) do
    Logger.error("[PlinkoLive] Settlement failed: #{inspect(reason)}")
    {:noreply, socket}
  end

  def handle_async(:settle_game, {:exit, reason}, socket) do
    Logger.error("[PlinkoLive] Settlement task crashed: #{inspect(reason)}")
    {:noreply, socket}
  end

  # ============ Private Helpers ============

  defp handle_init_failure(socket, reason) do
    retry_count = socket.assigns.init_retry_count
    max_retries = 3

    if retry_count < max_retries do
      delay = :math.pow(2, retry_count) |> round() |> Kernel.*(1000)

      Logger.warning(
        "[PlinkoLive] Init failed (attempt #{retry_count + 1}), retrying in #{delay}ms: #{inspect(reason)}"
      )

      Process.send_after(self(), :retry_init, delay)
      {:noreply, assign(socket, init_retry_count: retry_count + 1)}
    else
      Logger.error("[PlinkoLive] Init failed after #{max_retries} retries")

      {:noreply,
       assign(socket,
         error_message: "Failed to initialize game. Please refresh.",
         onchain_initializing: false
       )}
    end
  end

  defp get_balance(assigns, "BUX"), do: Map.get(assigns.balances, "BUX", 0)
  defp get_balance(assigns, "ROGUE"), do: Map.get(assigns.balances, "ROGUE", 0)
  defp get_balance(assigns, token), do: Map.get(assigns.balances, token, 0)

  defp config_index_for(rows, risk) do
    row_offset =
      case rows do
        8 -> 0
        12 -> 3
        16 -> 6
      end

    risk_offset =
      case risk do
        :low -> 0
        :medium -> 1
        :high -> 2
      end

    row_offset + risk_offset
  end

  defp calculate_max_bet(available_liquidity, config_index) do
    payout_table = Map.get(@payout_tables, config_index)
    max_mult_bps = Enum.max(payout_table)

    if max_mult_bps > 0 do
      (available_liquidity * 10 / 10000 * 20000 / max_mult_bps)
      |> trunc()
      |> max(0)
    else
      0
    end
  end

  defp maybe_update_max_bet(socket, config_index) do
    max_bet = calculate_max_bet(socket.assigns.house_balance, config_index)
    bet_amount = socket.assigns.bet_amount |> min(max_bet) |> max(min(1, max_bet))
    assign(socket, max_bet: max_bet, bet_amount: bet_amount)
  end

  defp assign_defaults_for_guest(socket) do
    balances = %{"BUX" => 0, "ROGUE" => 0, "aggregate" => 0}
    default_config = 0

    if connected?(socket) do
      Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "token_prices")
    end

    token_logos = HubLogoCache.get_all_logos()

    socket
    |> assign(page_title: "Plinko")
    |> assign(current_user: nil)
    |> assign(balances: balances)
    |> assign(token_logos: token_logos)
    |> assign(selected_token: "BUX")
    |> assign(header_token: "BUX")
    |> assign(selected_rows: 8)
    |> assign(selected_risk: :low)
    |> assign(config_index: default_config)
    |> assign(bet_amount: 10)
    |> assign(current_bet: 10)
    |> assign(payout_table: Map.get(@payout_tables, default_config))
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
    |> assign(init_retry_count: 0)
    |> assign(onchain_game_id: nil)
    |> assign(commitment_hash: nil)
    |> assign(commitment_tx: nil)
    |> assign(nonce: nil)
    |> assign(wallet_address: nil)
    |> assign(bet_tx: nil)
    |> assign(bet_id: nil)
    |> assign(settlement_tx: nil)
    |> assign(house_balance: 0.0)
    |> assign(max_bet: 0)
    |> assign(rogue_usd_price: get_rogue_price())
    |> assign(show_token_dropdown: false)
    |> assign(show_provably_fair: false)
    |> assign(show_fairness_modal: false)
    |> assign(fairness_game: nil)
    |> assign(recent_games: [])
    |> assign(games_offset: 0)
    |> assign(has_more_games: false)
    |> assign(games_loading: false)
    |> stream_configure(:game_history, dom_id: &"game-#{&1.game_id}")
    |> stream(:game_history, [])
    |> start_async(:fetch_house_balance, fn ->
      BuxMinter.bux_bankroll_house_info()
    end)
  end

  # ============ SVG Board Helpers ============

  defp board_height(8), do: 340
  defp board_height(12), do: 460
  defp board_height(16), do: 580

  defp peg_radius(8), do: 5
  defp peg_radius(12), do: 4
  defp peg_radius(16), do: 3

  defp ball_radius(8), do: 9
  defp ball_radius(12), do: 7
  defp ball_radius(16), do: 6

  defp peg_positions(rows) do
    spacing = 380 / (rows + 1)
    top_margin = 30
    row_height = (board_height(rows) - top_margin - 50) / rows

    for row <- 0..(rows - 1), col <- 0..row do
      num_pegs = row + 1
      row_width = (num_pegs - 1) * spacing
      x = 200 - row_width / 2 + col * spacing
      y = top_margin + row * row_height
      {x, y}
    end
  end

  defp slot_positions(rows) do
    num_slots = rows + 1
    slot_width = 380 / num_slots
    y = board_height(rows) - 50

    for k <- 0..rows do
      x = 200 - (num_slots - 1) * slot_width / 2 + k * slot_width
      {k, x, y}
    end
  end

  # Slot colors — lime for jackpots, warm gradient through to deep red for losses
  defp slot_color(multiplier_bp) when multiplier_bp >= 100_000, do: "#CAFC00"
  defp slot_color(multiplier_bp) when multiplier_bp >= 30_000, do: "#4ade80"
  defp slot_color(multiplier_bp) when multiplier_bp >= 10_000, do: "#fbbf24"
  defp slot_color(multiplier_bp) when multiplier_bp >= 5_000, do: "#fb923c"
  defp slot_color(multiplier_bp) when multiplier_bp > 0, do: "#f87171"
  defp slot_color(0), do: "#991b1b"

  defp slot_text_color(multiplier_bp) when multiplier_bp >= 10_000, do: "#000000"
  defp slot_text_color(_), do: "#ffffff"

  defp format_multiplier(0), do: "0x"

  defp format_multiplier(bp) when bp >= 10000 do
    x = div(bp, 10000)
    rem_bp = rem(bp, 10000)
    if rem_bp == 0, do: "#{x}x", else: "#{x}.#{div(rem_bp, 1000)}x"
  end

  defp format_multiplier(bp) do
    "0.#{div(bp, 1000)}x"
  end

  defp generate_confetti(count) do
    for _i <- 1..count do
      %{
        x: :rand.uniform(100),
        delay: :rand.uniform(2000),
        color: Enum.random(["#CAFC00", "#22c55e", "#eab308", "#ef4444", "#3b82f6", "#a855f7"]),
        size: :rand.uniform(8) + 4
      }
    end
  end

  defp format_balance(amount) when is_number(amount) do
    whole = trunc(amount)
    frac = abs(amount - whole)
    decimal_part = frac * 100 |> round() |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{add_commas(Integer.to_string(whole))}.#{decimal_part}"
  end

  defp format_balance(_), do: "0.00"

  defp add_commas(str) when is_binary(str) do
    str
    |> String.reverse()
    |> String.replace(~r/(\d{3})/, "\\1,")
    |> String.reverse()
    |> String.trim_leading(",")
  end

  defp format_integer(amount) when is_integer(amount) do
    amount
    |> Integer.to_string()
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.map(&Enum.join/1)
    |> Enum.join(",")
    |> String.reverse()
  end

  defp format_integer(amount) when is_float(amount), do: format_integer(trunc(amount))
  defp format_integer(_), do: "0"

  defp format_usd(nil, _amount), do: nil
  defp format_usd(_price, nil), do: nil
  defp format_usd(price, amount) when is_number(price) and is_number(amount) do
    usd_value = price * amount
    cond do
      usd_value >= 1_000_000 -> "$#{:erlang.float_to_binary(usd_value / 1_000_000, decimals: 2)}M"
      usd_value >= 1_000 -> "$#{:erlang.float_to_binary(usd_value / 1_000, decimals: 2)}K"
      true -> "$#{:erlang.float_to_binary(usd_value, decimals: 2)}"
    end
  end
  defp format_usd(_, _), do: nil

  defp get_rogue_price do
    case PriceTracker.get_price("ROGUE") do
      {:ok, %{usd_price: price}} -> price
      {:error, _} -> nil
    end
  end
end
