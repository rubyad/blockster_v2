defmodule BlocksterV2Web.PlinkoLive do
  use BlocksterV2Web, :live_view
  require Logger

  alias BlocksterV2.{PlinkoGame, BuxMinter, EngagementTracker, PriceTracker}

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

      socket =
        socket
        |> assign(page_title: "Plinko")
        |> assign(current_user: current_user)
        |> assign(balances: balances)
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
        |> assign(bet_tx: nil)
        |> assign(bet_id: nil)
        |> assign(settlement_tx: nil)
        # House / balance
        |> assign(house_balance: 0.0)
        |> assign(max_bet: 0)
        |> assign(rogue_usd_price: get_rogue_price())
        # UI state
        |> assign(show_token_dropdown: false)
        |> assign(show_fairness_modal: false)
        |> assign(fairness_game: nil)
        |> assign(recent_games: [])
        |> assign(games_offset: 0)
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
      class="min-h-screen bg-gray-50"
      phx-hook="PlinkoOnchain"
      data-game-id={@onchain_game_id}
      data-commitment-hash={@commitment_hash}
    >
      <div class="max-w-2xl mx-auto px-3 sm:px-4 pt-6 sm:pt-24 pb-8">
        <!-- Config Selector: Rows -->
        <div class="flex justify-center gap-2 mb-2">
          <button
            :for={rows <- [8, 12, 16]}
            phx-click="select_rows"
            phx-value-rows={rows}
            disabled={@game_state not in [:idle, :result]}
            class={"config-tab #{if @selected_rows == rows, do: "active"}"}
          >
            <%= rows %> Rows
          </button>
        </div>

        <!-- Config Selector: Risk -->
        <div class="flex justify-center gap-2 mb-4">
          <button
            :for={{risk, label} <- [{:low, "Low"}, {:medium, "Medium"}, {:high, "High"}]}
            phx-click="select_risk"
            phx-value-risk={risk}
            disabled={@game_state not in [:idle, :result]}
            class={"config-tab #{if @selected_risk == risk, do: "active"}"}
          >
            <%= label %>
          </button>
        </div>

        <!-- Main Game Card -->
        <div class="plinko-game-card">
          <!-- Error Banner -->
          <div :if={@error_message} class="bg-red-900/80 text-red-200 px-4 py-2 text-sm text-center">
            <%= @error_message %>
            <button phx-click="clear_error" class="ml-2 text-red-400 hover:text-red-200 cursor-pointer">x</button>
          </div>

          <!-- Bet Controls (shown in :idle and :result states) -->
          <div :if={@game_state in [:idle, :result]} class="px-4 pt-3 pb-2">
            <div class="flex items-center gap-2 mb-2">
              <!-- Bet Amount Input -->
              <div class="flex items-center bg-zinc-800 rounded-lg px-2 py-1.5 flex-1">
                <span class="text-zinc-500 text-xs mr-1">BET</span>
                <input
                  type="number"
                  value={@bet_amount}
                  phx-change="update_bet_amount"
                  phx-debounce="100"
                  name="value"
                  class="bg-transparent text-white text-sm w-full outline-none [appearance:textfield] [&::-webkit-inner-spin-button]:appearance-none"
                  min="1"
                  max={@max_bet}
                />
              </div>
              <!-- Halve / Double / Max -->
              <button phx-click="halve_bet" class="bg-zinc-800 text-zinc-400 hover:text-white px-2 py-1.5 rounded-lg text-xs cursor-pointer">/2</button>
              <button phx-click="double_bet" class="bg-zinc-800 text-zinc-400 hover:text-white px-2 py-1.5 rounded-lg text-xs cursor-pointer">x2</button>
              <button phx-click="set_max_bet" class="bg-zinc-800 text-zinc-400 hover:text-white px-2 py-1.5 rounded-lg text-xs cursor-pointer">MAX</button>

              <!-- Token Selector -->
              <div class="relative">
                <button phx-click="toggle_token_dropdown" class="flex items-center bg-zinc-800 rounded-lg px-2 py-1.5 cursor-pointer">
                  <span class="text-white text-sm"><%= @selected_token %></span>
                  <svg class="w-3 h-3 ml-1 text-zinc-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
                  </svg>
                </button>
                <div :if={@show_token_dropdown} class="absolute right-0 mt-1 bg-zinc-800 rounded-lg shadow-xl z-50 min-w-[80px]">
                  <button
                    :for={token <- ["BUX", "ROGUE"]}
                    phx-click="select_token"
                    phx-value-token={token}
                    class="block w-full text-left px-3 py-2 text-sm text-white hover:bg-zinc-700 cursor-pointer first:rounded-t-lg last:rounded-b-lg"
                  >
                    <%= token %>
                  </button>
                </div>
              </div>
            </div>

            <!-- Balance & Max Info -->
            <div class="flex justify-between text-xs text-zinc-500 mb-2">
              <span>Balance: <%= format_balance(get_balance(assigns, @selected_token)) %> <%= @selected_token %></span>
              <span>House: <%= format_balance(@house_balance) %> <%= @selected_token %></span>
            </div>

            <!-- Max Potential Payout -->
            <% max_mult_bp = if @payout_table, do: Enum.max(@payout_table), else: 0 %>
            <% max_payout = @bet_amount * max_mult_bp / 10000 %>
            <div class="text-xs text-zinc-500 mb-2">
              Max Potential: +<%= format_balance(max_payout - @bet_amount) %> <%= @selected_token %>
              (<%= format_multiplier(max_mult_bp) %> edge)
            </div>
          </div>

          <!-- Plinko Board (SVG) -->
          <div class="flex justify-center px-2">
            <svg
              viewBox={"0 0 400 #{board_height(@selected_rows)}"}
              class="w-full max-w-md mx-auto"
              id="plinko-board"
              phx-hook="PlinkoBall"
              data-game-id={@onchain_game_id}
            >
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
              <%= for {x, y} <- peg_positions(@selected_rows) do %>
                <circle class="plinko-peg" cx={x} cy={y} r={peg_radius(@selected_rows)} fill="#6b7280" />
              <% end %>

              <!-- Landing slots -->
              <%= for {k, x, y} <- slot_positions(@selected_rows) do %>
                <% bp = Enum.at(@payout_table, k) %>
                <% slot_w = 340 / (@selected_rows + 1) - 2 %>
                <rect
                  class="plinko-slot"
                  x={x - slot_w / 2}
                  y={y}
                  width={slot_w}
                  height="30"
                  fill={slot_color(bp)}
                  rx="4"
                />
                <text
                  x={x}
                  y={y + 18}
                  text-anchor="middle"
                  fill="white"
                  font-size={if @selected_rows == 16, do: "8", else: "10"}
                  font-weight="bold"
                >
                  <%= format_multiplier(bp) %>
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
          </div>

          <!-- Commitment Display (idle state) -->
          <div :if={@game_state == :idle and @commitment_hash} class="px-4 py-1 text-center">
            <span class="text-[10px] text-zinc-600 font-mono">
              Commitment: <%= String.slice(@commitment_hash, 0..13) %>...<%= String.slice(@commitment_hash, -4..-1//1) %>
            </span>
          </div>

          <!-- Drop Ball Button (idle state) -->
          <div :if={@game_state == :idle} class="px-4 pb-3">
            <button
              phx-click="drop_ball"
              disabled={not @onchain_ready or @bet_amount <= 0 or @current_user == nil}
              class={[
                "w-full py-3 rounded-xl text-sm font-bold transition-all cursor-pointer",
                if(@onchain_ready and @bet_amount > 0 and @current_user,
                  do: "bg-[#CAFC00] text-black hover:bg-[#b8e600] active:scale-[0.98]",
                  else: "bg-zinc-700 text-zinc-500 cursor-not-allowed")
              ]}
            >
              <%= cond do %>
                <% @current_user == nil -> %>Login to Play
                <% @onchain_initializing -> %>Initializing...
                <% not @onchain_ready -> %>Game Not Ready
                <% true -> %>DROP BALL
              <% end %>
            </button>
          </div>

          <!-- Dropping State (animation in progress) -->
          <div :if={@game_state == :dropping} class="px-4 pb-3 text-center">
            <div class="text-zinc-400 text-sm animate-pulse">Dropping...</div>
          </div>

          <!-- Result State -->
          <div :if={@game_state == :result} class="px-4 pb-3">
            <!-- Win / Loss Display -->
            <div class="text-center mb-3">
              <div class={"text-2xl font-bold plinko-win-text #{if @won, do: "text-green-400", else: "text-red-400"}"}>
                <%= if @payout_multiplier do %>
                  <%= format_multiplier(trunc(@payout_multiplier * 10000)) %>
                <% end %>
              </div>
              <div class={"text-sm #{if @won, do: "text-green-400", else: "text-red-400"}"}>
                <%= cond do %>
                  <% @payout > @current_bet -> %>
                    +<%= format_balance(@payout - @current_bet) %> <%= @selected_token %> PROFIT
                  <% @payout == @current_bet -> %>
                    PUSH (break even)
                  <% @payout == 0 -> %>
                    -<%= format_balance(@current_bet) %> <%= @selected_token %>
                  <% true -> %>
                    -<%= format_balance(@current_bet - @payout) %> <%= @selected_token %>
                <% end %>
              </div>
              <div class="text-xs text-zinc-500 mt-1">
                Landed on position <%= @landing_position %>
              </div>
            </div>

            <!-- Action Buttons -->
            <div class="flex gap-2">
              <button
                phx-click="reset_game"
                class="flex-1 py-2.5 rounded-xl bg-[#CAFC00] text-black text-sm font-bold hover:bg-[#b8e600] cursor-pointer"
              >
                Play Again
              </button>
              <button
                :if={@settlement_tx}
                phx-click="show_fairness_modal"
                phx-value-game_id={@onchain_game_id}
                class="px-4 py-2.5 rounded-xl bg-zinc-800 text-zinc-400 text-sm hover:text-white cursor-pointer"
              >
                Verify
              </button>
            </div>

            <!-- Confetti -->
            <div :for={piece <- @confetti_pieces} class="fixed pointer-events-none z-50"
              style={"left: #{piece.x}%; top: -10px; animation: confetti-fall #{1.5 + piece.delay / 1000}s linear forwards; animation-delay: #{piece.delay}ms;"}>
              <div style={"width: #{piece.size}px; height: #{piece.size}px; background: #{piece.color}; border-radius: 2px;"}></div>
            </div>
          </div>
        </div>

        <!-- Fairness Modal -->
        <div :if={@show_fairness_modal and @fairness_game} class="fixed inset-0 bg-black/70 z-50 flex items-center justify-center p-4">
          <div class="bg-zinc-900 rounded-2xl max-w-lg w-full max-h-[80vh] overflow-y-auto p-6">
            <div class="flex justify-between items-center mb-4">
              <h3 class="text-white font-bold text-lg">Verify Fairness</h3>
              <button phx-click="hide_fairness_modal" class="text-zinc-500 hover:text-white cursor-pointer">
                <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            </div>

            <div class="space-y-3 text-xs font-mono">
              <div>
                <span class="text-zinc-500">Server Seed:</span>
                <p class="text-white break-all"><%= @fairness_game.server_seed %></p>
              </div>
              <div>
                <span class="text-zinc-500">Commitment (SHA256 of Server Seed):</span>
                <p class="text-white break-all"><%= @fairness_game.commitment_hash %></p>
              </div>
              <div>
                <span class="text-zinc-500">Client Seed:</span>
                <% client_input = "#{@fairness_game.user_id}:#{@fairness_game.bet_amount}:#{@fairness_game.token}:#{@fairness_game.config_index}" %>
                <p class="text-zinc-400">SHA256("<%= client_input %>")</p>
              </div>
              <div>
                <span class="text-zinc-500">Nonce:</span>
                <p class="text-white"><%= @fairness_game.nonce %></p>
              </div>
              <div>
                <span class="text-zinc-500">Ball Path (<%= @fairness_game.rows %> rows):</span>
                <div class="text-white">
                  <%= for {dir, i} <- Enum.with_index(@fairness_game.ball_path || []) do %>
                    <div>Row <%= i %>: <%= if dir == :right, do: "RIGHT", else: "LEFT" %></div>
                  <% end %>
                </div>
              </div>
              <div>
                <span class="text-zinc-500">Landing Position:</span>
                <p class="text-white"><%= @fairness_game.landing_position %></p>
              </div>
              <div>
                <span class="text-zinc-500">Config:</span>
                <p class="text-white"><%= @fairness_game.rows %>-<%= @fairness_game.risk_level %></p>
              </div>
              <div>
                <span class="text-zinc-500">Payout:</span>
                <p class="text-white"><%= format_multiplier(@fairness_game.payout_bp) %> = <%= format_balance(@fairness_game.payout) %> <%= @fairness_game.token %></p>
              </div>
            </div>

            <div class="mt-4 text-xs text-zinc-500">
              <p>To verify: compute SHA256(server_seed) and confirm it matches the commitment shown before your bet.
              Then compute SHA256("server_seed:client_seed:nonce") and check the first <%= @fairness_game.rows %> bytes.</p>
              <a href="https://emn178.github.io/online-tools/sha256.html" target="_blank" class="text-blue-500 hover:underline mt-1 inline-block">
                External SHA256 Calculator
              </a>
            </div>
          </div>
        </div>

        <!-- Game History Table -->
        <div class="mt-6">
          <h3 class="text-white font-bold text-sm mb-2">Game History</h3>
          <div class="overflow-x-auto">
            <table class="w-full min-w-[600px] text-[10px] sm:text-xs">
              <thead>
                <tr class="text-zinc-500 border-b border-zinc-800">
                  <th class="text-left py-2 px-1">ID</th>
                  <th class="text-left py-2 px-1">Bet</th>
                  <th class="text-left py-2 px-1">Config</th>
                  <th class="text-left py-2 px-1">Landing</th>
                  <th class="text-left py-2 px-1">Mult</th>
                  <th class="text-right py-2 px-1">P/L</th>
                  <th class="text-right py-2 px-1">Verify</th>
                </tr>
              </thead>
              <tbody id="game-history" phx-update="stream">
                <tr :for={{dom_id, game} <- @streams.game_history} id={dom_id} class="border-b border-zinc-800/50">
                  <td class="py-1.5 px-1 text-zinc-500 font-mono"><%= String.slice(game.game_id, 0..5) %></td>
                  <td class="py-1.5 px-1 text-white"><%= format_balance(game.bet_amount) %> <%= game.token %></td>
                  <td class="py-1.5 px-1 text-zinc-400"><%= game.rows %>-<%= game.risk_level %></td>
                  <td class="py-1.5 px-1 text-zinc-400"><%= game.landing_position %></td>
                  <td class="py-1.5 px-1 text-zinc-400"><%= format_multiplier(game.payout_bp) %></td>
                  <td class={"py-1.5 px-1 text-right #{if game.won, do: "text-green-400", else: "text-red-400"}"}>
                    <%= if game.won do %>+<%= format_balance(game.payout - game.bet_amount) %><% else %>-<%= format_balance(game.bet_amount - game.payout) %><% end %>
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
          </div>

          <div :if={@games_loading} class="text-center py-4">
            <span class="text-zinc-500 text-xs animate-pulse">Loading...</span>
          </div>

          <!-- Infinite scroll trigger -->
          <div
            :if={length(@recent_games) > 0 and rem(length(@recent_games), 30) == 0}
            id="infinite-scroll-games"
            phx-hook="InfiniteScroll"
            phx-click="load-more-games"
            class="h-4"
          />
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

    {:noreply,
     socket
     |> assign(selected_rows: rows, config_index: config_index, payout_table: payout_table)
     |> maybe_update_max_bet(config_index)}
  end

  def handle_event("select_risk", %{"risk" => risk_str}, socket) do
    risk = String.to_existing_atom(risk_str)
    rows = socket.assigns.selected_rows
    config_index = config_index_for(rows, risk)
    payout_table = Map.get(@payout_tables, config_index)

    {:noreply,
     socket
     |> assign(selected_risk: risk, config_index: config_index, payout_table: payout_table)
     |> maybe_update_max_bet(config_index)}
  end

  # ============ Bet Amount Controls ============

  def handle_event("update_bet_amount", %{"value" => value_str}, socket) do
    case Integer.parse(value_str) do
      {amount, _} ->
        clamped = amount |> max(0) |> min(socket.assigns.max_bet)
        {:noreply, assign(socket, bet_amount: clamped)}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("halve_bet", _params, socket) do
    new_amount = max(div(socket.assigns.bet_amount, 2), 1)
    {:noreply, assign(socket, bet_amount: new_amount)}
  end

  def handle_event("double_bet", _params, socket) do
    doubled = socket.assigns.bet_amount * 2
    new_amount = if socket.assigns.max_bet > 0, do: min(doubled, socket.assigns.max_bet), else: doubled
    {:noreply, assign(socket, bet_amount: new_amount)}
  end

  def handle_event("set_max_bet", _params, socket) do
    {:noreply, assign(socket, bet_amount: socket.assigns.max_bet)}
  end

  # ============ Token Selection ============

  def handle_event("toggle_token_dropdown", _params, socket) do
    {:noreply, assign(socket, show_token_dropdown: not socket.assigns.show_token_dropdown)}
  end

  def handle_event("select_token", %{"token" => token}, socket) do
    socket =
      socket
      |> assign(selected_token: token, header_token: token, show_token_dropdown: false)
      |> start_async(:fetch_house_balance, fn ->
        if token == "ROGUE" do
          BuxMinter.get_house_balance()
        else
          BuxMinter.bux_bankroll_house_info()
        end
      end)

    {:noreply, socket}
  end

  # ============ Main Action: Drop Ball ============

  def handle_event("drop_ball", _params, socket) do
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

        # Calculate result (uses stored server seed)
        {:ok, result} =
          PlinkoGame.calculate_game_result(game_id, config_index, bet_amount, token, user.id)

        # Start animation + push bet to JS
        socket =
          socket
          |> assign(game_state: :dropping, current_bet: bet_amount)
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

    # Start async settlement (ball is already animating)
    socket =
      socket
      |> assign(bet_tx: tx_hash, bet_id: socket.assigns.commitment_hash)
      |> start_async(:settle_game, fn ->
        PlinkoGame.settle_game(game_id)
      end)

    {:noreply, socket}
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

    {:noreply, assign(socket, game_state: :result, confetti_pieces: confetti)}
  end

  # ============ Reset / Play Again ============

  def handle_event("reset_game", _params, socket) do
    user = socket.assigns.current_user
    wallet = socket.assigns.wallet_address

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

    {:noreply, socket}
  end

  # ============ Fairness Modal ============

  def handle_event("show_fairness_modal", %{"game_id" => game_id}, socket) do
    case PlinkoGame.get_game(game_id) do
      {:ok, game} when game.status == :settled ->
        {:noreply, assign(socket, show_fairness_modal: true, fairness_game: game)}

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
    user = socket.assigns.current_user
    new_offset = socket.assigns.games_offset + 30

    socket =
      socket
      |> assign(games_loading: true, games_offset: new_offset)
      |> start_async(:load_more_games, fn ->
        PlinkoGame.load_recent_games(user.id, limit: 30, offset: new_offset)
      end)

    {:noreply, socket}
  end

  # ============ Clear Error ============

  def handle_event("clear_error", _params, socket) do
    {:noreply, assign(socket, error_message: nil)}
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
    if socket.assigns.onchain_game_id == game_id do
      {:noreply, assign(socket, settlement_tx: tx_hash)}
    else
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
       commitment_hash: game_data.commitment_hash
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
    available =
      cond do
        is_map(info) and Map.has_key?(info, "netBalance") ->
          String.to_integer(info["netBalance"]) / 1.0e18

        is_map(info) and Map.has_key?(info, "houseBalance") ->
          String.to_integer(info["houseBalance"]) / 1.0e18

        true ->
          0.0
      end

    max_bet = calculate_max_bet(available, socket.assigns.config_index)

    {:noreply, assign(socket, house_balance: available, max_bet: max_bet)}
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
     |> assign(recent_games: games, games_loading: false)
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
     |> assign(recent_games: socket.assigns.recent_games ++ new_games, games_loading: false)
     |> stream(:game_history, new_games)}
  end

  def handle_async(:load_more_games, _, socket) do
    {:noreply, assign(socket, games_loading: false)}
  end

  # settle_game — async settlement after bet confirmed
  def handle_async(:settle_game, {:ok, {:ok, %{tx_hash: tx_hash}}}, socket) do
    {:noreply, assign(socket, settlement_tx: tx_hash)}
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
    bet_amount = min(socket.assigns.bet_amount, max_bet)
    assign(socket, max_bet: max_bet, bet_amount: bet_amount)
  end

  defp assign_defaults_for_guest(socket) do
    balances = %{"BUX" => 0, "ROGUE" => 0, "aggregate" => 0}
    default_config = 0

    if connected?(socket) do
      Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "token_prices")
    end

    socket
    |> assign(page_title: "Plinko")
    |> assign(current_user: nil)
    |> assign(balances: balances)
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
    |> assign(wallet_address: nil)
    |> assign(bet_tx: nil)
    |> assign(bet_id: nil)
    |> assign(settlement_tx: nil)
    |> assign(house_balance: 0.0)
    |> assign(max_bet: 0)
    |> assign(rogue_usd_price: get_rogue_price())
    |> assign(show_token_dropdown: false)
    |> assign(show_fairness_modal: false)
    |> assign(fairness_game: nil)
    |> assign(recent_games: [])
    |> assign(games_offset: 0)
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

  defp peg_radius(8), do: 4
  defp peg_radius(12), do: 3
  defp peg_radius(16), do: 2.5

  defp ball_radius(8), do: 8
  defp ball_radius(12), do: 6
  defp ball_radius(16), do: 5

  defp peg_positions(rows) do
    spacing = 340 / (rows + 1)
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
    slot_width = 340 / num_slots
    y = board_height(rows) - 50

    for k <- 0..rows do
      x = 200 - (num_slots - 1) * slot_width / 2 + k * slot_width
      {k, x, y}
    end
  end

  defp slot_color(multiplier_bp) when multiplier_bp >= 100_000, do: "#22c55e"
  defp slot_color(multiplier_bp) when multiplier_bp >= 30_000, do: "#4ade80"
  defp slot_color(multiplier_bp) when multiplier_bp >= 10_000, do: "#eab308"
  defp slot_color(multiplier_bp) when multiplier_bp > 0, do: "#ef4444"
  defp slot_color(0), do: "#991b1b"

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
    amount |> trunc() |> Integer.to_string() |> add_commas()
  end

  defp format_balance(_), do: "0"

  defp add_commas(str) when is_binary(str) do
    str
    |> String.reverse()
    |> String.replace(~r/(\d{3})/, "\\1,")
    |> String.reverse()
    |> String.trim_leading(",")
  end

  defp get_rogue_price do
    case PriceTracker.get_price("ROGUE") do
      {:ok, %{usd_price: price}} -> price
      {:error, _} -> nil
    end
  end
end
