defmodule BlocksterV2Web.BuxBoosterLive do
  use BlocksterV2Web, :live_view
  require Logger

  alias BlocksterV2.EngagementTracker
  alias BlocksterV2.HubLogoCache
  alias BlocksterV2.ProvablyFair
  alias BlocksterV2.BuxBoosterOnchain
  alias BlocksterV2.BuxMinter
  alias BlocksterV2.PriceTracker

  # Difficulty levels with house edge built into multipliers
  # mode: :win_all = must win all flips (harder, higher payout)
  # mode: :win_one = only need to win one flip (easier, lower payout)
  @difficulty_options [
    %{level: -4, predictions: 5, multiplier: 1.02, label: "1.02x", mode: :win_one},
    %{level: -3, predictions: 4, multiplier: 1.05, label: "1.05x", mode: :win_one},
    %{level: -2, predictions: 3, multiplier: 1.13, label: "1.13x", mode: :win_one},
    %{level: -1, predictions: 2, multiplier: 1.32, label: "1.32x", mode: :win_one},
    %{level: 1, predictions: 1, multiplier: 1.98, label: "1.98x", mode: :win_all},
    %{level: 2, predictions: 2, multiplier: 3.96, label: "3.96x", mode: :win_all},
    %{level: 3, predictions: 3, multiplier: 7.92, label: "7.92x", mode: :win_all},
    %{level: 4, predictions: 4, multiplier: 15.84, label: "15.84x", mode: :win_all},
    %{level: 5, predictions: 5, multiplier: 31.68, label: "31.68x", mode: :win_all}
  ]

  @impl true
  def mount(_params, _session, socket) do
    current_user = socket.assigns[:current_user]
    token_logos = HubLogoCache.get_all_logos()
    tokens = ["ROGUE", "BUX"]

    if current_user do
      # User is logged in
      # Get user's smart wallet address for on-chain games
      wallet_address = current_user.smart_wallet_address

      # Sync balances from blockchain on connected mount (async, will broadcast when done)
      if wallet_address != nil and connected?(socket) do
        BuxMinter.sync_user_balances_async(current_user.id, wallet_address)
      end

      balances = EngagementTracker.get_user_token_balances(current_user.id)

      # IMPORTANT: Only initialize on-chain game on connected mount (not disconnected)
      # LiveView mounts twice - once disconnected, once connected via WebSocket
      # We only want to submit commitment hash to blockchain once per page load
      #
      # Strategy: Load page immediately, then async query contract for nonce and init game
      # This prevents blockchain RPC call from blocking page load
      socket = if wallet_address != nil and connected?(socket) do
        # Subscribe to balance updates for this user
        Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "bux_balance:#{current_user.id}")
        # Subscribe to game settlements for this user
        Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "bux_booster_settlement:#{current_user.id}")
        # Subscribe to token price updates
        Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "token_prices")

        socket
        |> assign(:onchain_ready, false)
        |> assign(:wallet_address, wallet_address)
        |> assign(:onchain_initializing, true)
        |> assign(:init_retry_count, 0)  # Initialize retry counter
        |> start_async(:init_onchain_game, fn ->
          BuxBoosterOnchain.get_or_init_game(current_user.id, wallet_address)
        end)
      else
        socket
        |> assign(:onchain_ready, false)
        |> assign(:wallet_address, wallet_address)
        |> assign(:onchain_initializing, false)
        |> assign(:init_retry_count, 0)
      end

      onchain_assigns = %{onchain_ready: false, wallet_address: wallet_address}
      error_msg = if wallet_address, do: nil, else: "No wallet connected"

      # Use the on-chain commitment hash for provably fair display
      server_seed_hash = Map.get(onchain_assigns, :commitment_hash) || ProvablyFair.generate_commitment(ProvablyFair.generate_server_seed())
      nonce = Map.get(onchain_assigns, :onchain_nonce) || get_user_nonce(current_user.id)

      socket =
        socket
        |> assign(page_title: "BUX Booster")
        |> assign(current_user: current_user)
        |> assign(balances: balances)
        |> assign(tokens: tokens)
        |> assign(token_logos: token_logos)
        |> assign(difficulty_options: @difficulty_options)
        |> assign(selected_token: "BUX")
        |> assign(header_token: "BUX")
        |> assign(selected_difficulty: 1)
        |> assign(bet_amount: 10)
        |> assign(current_bet: 10)
        |> assign(house_balance: 0.0)  # Default, will be updated async
        |> assign(max_bet: 0)  # Default, will be updated async
        |> assign(rogue_usd_price: get_rogue_price())  # USD price from PriceTracker
        |> assign(predictions: [nil])  # Initialize with 1 nil for default difficulty (1 flip)
        |> assign(results: [])
        |> assign(game_state: :idle)
        |> assign(current_flip: 0)
        |> assign(won: nil)
        |> assign(payout: 0)
        |> assign(error_message: error_msg)
        |> assign(show_token_dropdown: false)
        |> assign(show_provably_fair: false)
        |> assign(flip_id: 0)
        |> assign(confetti_pieces: [])
        |> assign(recent_games: [])  # Start empty, load async on connected mount
        |> assign(games_offset: 0)  # Track offset for pagination
        |> assign(games_loading: connected?(socket))  # Only show loading if connected (async will run)
        |> assign(user_stats: load_user_stats(current_user.id))
        # Provably fair assigns (commitment hash from on-chain)
        |> assign(server_seed: nil)  # Server seed is stored in Mnesia, not in socket
        |> assign(server_seed_hash: server_seed_hash)
        |> assign(nonce: nonce)
        |> assign(show_fairness_modal: false)
        |> assign(fairness_game: nil)
        # On-chain assigns
        |> assign(onchain_assigns)
        |> assign(bet_tx: nil)
        |> assign(bet_id: nil)
        |> assign(settlement_tx: nil)

      # Only start async operations on connected mount (not disconnected)
      socket = if connected?(socket) do
        user_id = current_user.id
        socket
        |> start_async(:fetch_house_balance, fn -> fetch_house_balance_async("BUX", 1) end)
        |> start_async(:load_recent_games, fn -> load_recent_games(user_id, limit: 30) end)
      else
        socket
      end

      {:ok, socket}
    else
      # Not logged in - allow viewing with zero balances
      balances = %{
        "BUX" => 0,
        "ROGUE" => 0,
        "aggregate" => 0
      }

      # Subscribe to token price updates for unauthenticated users too (on connected mount)
      if connected?(socket) do
        Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "token_prices")
      end

      socket =
        socket
        |> assign(page_title: "BUX Booster")
        |> assign(current_user: nil)
        |> assign(balances: balances)
        |> assign(tokens: tokens)
        |> assign(token_logos: token_logos)
        |> assign(difficulty_options: @difficulty_options)
        |> assign(selected_token: "BUX")
        |> assign(header_token: "BUX")
        |> assign(selected_difficulty: 1)
        |> assign(bet_amount: 10)
        |> assign(current_bet: 10)
        |> assign(house_balance: 0.0)
        |> assign(max_bet: 0)
        |> assign(rogue_usd_price: get_rogue_price())
        |> assign(predictions: [nil])  # Initialize with 1 nil for default difficulty (1 flip)
        |> assign(results: [])
        |> assign(game_state: :idle)
        |> assign(current_flip: 0)
        |> assign(won: nil)
        |> assign(payout: 0)
        |> assign(error_message: nil)
        |> assign(show_token_dropdown: false)
        |> assign(show_provably_fair: false)
        |> assign(flip_id: 0)
        |> assign(confetti_pieces: [])
        |> assign(recent_games: [])
        |> assign(games_offset: 0)
        |> assign(user_stats: nil)
        |> assign(server_seed: nil)
        |> assign(server_seed_hash: nil)
        |> assign(nonce: 0)
        |> assign(show_fairness_modal: false)
        |> assign(fairness_game: nil)
        |> assign(onchain_ready: false)
        |> assign(wallet_address: nil)
        |> assign(onchain_initializing: false)
        |> assign(bet_tx: nil)
        |> assign(bet_id: nil)
        |> assign(settlement_tx: nil)
        |> start_async(:fetch_house_balance, fn -> fetch_house_balance_async("BUX", 1) end)

      {:ok, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="bux-booster-game"
      class="min-h-screen bg-gray-50"
      phx-hook="BuxBoosterOnchain"
      data-game-id={assigns[:onchain_game_id]}
      data-commitment-hash={assigns[:commitment_hash]}
    >
      <div class="max-w-2xl mx-auto px-3 sm:px-4 pt-6 sm:pt-24 pb-8">
        <!-- Main Game Area -->
        <div class="bg-white rounded-2xl shadow-sm border border-gray-200 h-[480px] sm:h-[510px] flex flex-col overflow-hidden">
          <!-- Difficulty Tabs - scrollable on mobile (fixed height) -->
          <div id="difficulty-tabs" class="flex border-b border-gray-200 overflow-x-auto scrollbar-hide shrink-0" phx-hook="ScrollToCenter">
            <%= for {opt, idx} <- Enum.with_index(@difficulty_options) do %>
              <% is_first = idx == 0 %>
              <% is_last = idx == length(@difficulty_options) - 1 %>
              <button
                type="button"
                phx-click="select_difficulty"
                phx-value-level={opt.level}
                disabled={@game_state not in [:idle, :result]}
                data-selected={if @selected_difficulty == opt.level, do: "true", else: "false"}
                class={"flex-1 min-w-[60px] sm:min-w-0 py-2 sm:py-3 px-1 sm:px-2 text-center transition-all cursor-pointer disabled:cursor-not-allowed #{if is_first, do: "rounded-tl-2xl", else: ""} #{if is_last, do: "rounded-tr-2xl", else: ""} #{if @selected_difficulty == opt.level, do: "bg-black", else: "bg-gray-50 hover:bg-gray-100"}"}
              >
                <div class={"text-sm sm:text-lg font-bold #{if @selected_difficulty == opt.level, do: "text-white", else: "text-gray-900"}"}><%= opt.multiplier %>x</div>
                <div class={"text-[10px] sm:text-xs #{if @selected_difficulty == opt.level, do: "text-gray-300", else: "text-gray-500"}"}><%= opt.predictions %> flip<%= if opt.predictions > 1, do: "s" %></div>
              </button>
            <% end %>
          </div>

          <!-- Game Content Area - uses relative/absolute to prevent height changes -->
          <div class="flex-1 relative min-h-0">
            <div class="absolute inset-0 p-3 sm:p-6 flex flex-col overflow-hidden">
            <%= if @game_state == :idle do %>
              <!-- Bet Stake with Token Dropdown -->
              <div class="mb-3 sm:mb-4">
                <label class="block text-base sm:text-lg font-bold text-gray-900 mb-1 sm:mb-2">Bet Stake</label>
                <div class="flex gap-1.5 sm:gap-2">
                  <!-- Input with halve/double buttons and USD value -->
                  <div class="flex-1 relative min-w-0">
                    <input
                      type="number"
                      value={@bet_amount}
                      phx-keyup="update_bet_amount"
                      phx-debounce="100"
                      min="1"
                      class={"w-full bg-white border border-gray-300 rounded-lg pl-3 sm:pl-4 py-2 sm:py-3 text-gray-900 text-base sm:text-lg font-medium focus:outline-none focus:border-purple-500 focus:ring-1 focus:ring-purple-500 [appearance:textfield] [&::-webkit-outer-spin-button]:appearance-none [&::-webkit-inner-spin-button]:appearance-none #{if @selected_token == "ROGUE" && @rogue_usd_price, do: "pr-[7.5rem] sm:pr-36", else: "pr-20 sm:pr-24"}"}
                    />
                    <!-- USD value and Halve/Double buttons inside input -->
                    <div class="absolute right-2 top-1/2 -translate-y-1/2 flex items-center gap-1">
                      <%= if @selected_token == "ROGUE" && @rogue_usd_price do %>
                        <span class="text-gray-400 text-[10px] sm:text-xs mr-1">≈ <%= format_usd(@rogue_usd_price, @bet_amount) %></span>
                      <% end %>
                      <button
                        type="button"
                        phx-click="halve_bet"
                        class="px-1.5 sm:px-2 py-1 bg-gray-200 text-gray-700 rounded text-xs sm:text-sm font-medium hover:bg-gray-300 transition-all cursor-pointer"
                      >
                        ½
                      </button>
                      <button
                        type="button"
                        phx-click="double_bet"
                        class="px-1.5 sm:px-2 py-1 bg-gray-200 text-gray-700 rounded text-xs sm:text-sm font-medium hover:bg-gray-300 transition-all cursor-pointer"
                      >
                        2×
                      </button>
                    </div>
                  </div>
                  <!-- Token Dropdown -->
                  <div class="relative flex-shrink-0" id="token-dropdown-wrapper" phx-click-away="hide_token_dropdown">
                    <button
                      type="button"
                      phx-click="toggle_token_dropdown"
                      class="h-full px-2 sm:px-4 bg-gray-100 border border-gray-300 rounded-lg flex items-center gap-1 sm:gap-2 hover:bg-gray-200 transition-all cursor-pointer"
                    >
                      <img src={Map.get(@token_logos, @selected_token, "https://ik.imagekit.io/blockster/blockster-icon.png")} alt={@selected_token} class="w-4 sm:w-5 h-4 sm:h-5 rounded-full" />
                      <span class="font-medium text-gray-900 text-sm sm:text-base"><%= @selected_token %></span>
                      <svg class="w-3 sm:w-4 h-3 sm:h-4 text-gray-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
                      </svg>
                    </button>
                    <%= if @show_token_dropdown do %>
                      <div class="absolute right-0 top-full mt-1 bg-white border border-gray-200 rounded-lg shadow-lg z-50 w-max min-w-[180px] sm:min-w-[220px] max-h-[400px] overflow-y-auto">
                        <%= for token <- @tokens do %>
                          <button
                            type="button"
                            phx-click="select_token"
                            phx-value-token={token}
                            class={"w-full px-4 py-3 flex items-center gap-3 hover:bg-gray-50 cursor-pointer first:rounded-t-lg last:rounded-b-lg #{if @selected_token == token, do: "bg-gray-100"}"}
                          >
                            <img src={Map.get(@token_logos, token, "https://ik.imagekit.io/blockster/blockster-icon.png")} alt={token} class="w-5 h-5 rounded-full flex-shrink-0" />
                            <span class={"font-medium flex-1 text-left whitespace-nowrap #{if @selected_token == token, do: "text-gray-900", else: "text-gray-900"}"}><%= token %></span>
                            <%= if token == "ROGUE" and Map.get(@balances, "ROGUE", 0) == 0 do %>
                              <a href="https://app.uniswap.org/explore/pools/arbitrum/0x9876d52d698ffad55fef13f4d631c0300cf2dc8ef90c8dd70405dc06fa10b2ec" target="_blank" class="text-gray-600 text-xs hover:underline cursor-pointer" phx-click="hide_token_dropdown">Buy</a>
                            <% else %>
                              <span class="text-gray-500 text-sm whitespace-nowrap"><%= format_balance(Map.get(@balances, token, 0)) %></span>
                            <% end %>
                          </button>
                        <% end %>
                      </div>
                    <% end %>
                  </div>
                  <!-- Max button - hidden on mobile, shown on desktop -->
                  <button
                    type="button"
                    phx-click="set_max_bet"
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
                    class="flex-1 py-2 bg-gray-100 text-gray-700 rounded-lg hover:bg-gray-200 transition-all cursor-pointer flex items-center justify-center gap-2"
                    title={"Max bet: #{@max_bet} #{@selected_token}"}
                  >
                    <span class="text-xs text-gray-500">Max bet:</span>
                    <span class="text-sm font-medium"><%= format_integer(@max_bet) %> <%= @selected_token %></span>
                  </button>
                </div>
                <!-- Balance info - always on same line -->
                <div class="mt-1.5 sm:mt-2">
                  <div class="flex items-center justify-between text-[10px] sm:text-sm">
                    <div class="text-gray-500">
                      <%= if @selected_token == "ROGUE" do %>
                        <a href="https://roguescan.io/address/0xb6b4cb36ce26d62fe02402ef43cb489183b2a137?tab=coin_balance_history" target="_blank" class="flex items-center gap-0.5 sm:gap-1 text-blue-500 hover:underline cursor-pointer">
                          <%= format_balance(Map.get(@balances, @selected_token, 0)) %>
                          <img src={Map.get(@token_logos, @selected_token, "https://ik.imagekit.io/blockster/blockster-icon.png")} alt={@selected_token} class="w-3 h-3 sm:w-4 sm:h-4 rounded-full inline" />
                          <%= if @rogue_usd_price do %>
                            <span class="text-gray-400">(<%= format_usd(@rogue_usd_price, Map.get(@balances, @selected_token, 0)) %>)</span>
                          <% end %>
                        </a>
                      <% else %>
                        <a href="https://roguescan.io/address/0xb6b4cb36ce26d62fe02402ef43cb489183b2a137?tab=tokens" target="_blank" class="flex items-center gap-0.5 sm:gap-1 text-blue-500 hover:underline cursor-pointer">
                          <%= format_balance(Map.get(@balances, @selected_token, 0)) %>
                          <img src={Map.get(@token_logos, @selected_token, "https://ik.imagekit.io/blockster/blockster-icon.png")} alt={@selected_token} class="w-3 h-3 sm:w-4 sm:h-4 rounded-full inline" />
                        </a>
                      <% end %>
                    </div>
                    <div class="text-right">
                      <%= if @selected_token == "ROGUE" do %>
                        <a href="https://roguetrader.io/rogue-bankroll" target="_blank" class="text-blue-500 text-[10px] sm:text-xs hover:underline cursor-pointer">
                          House: <%= format_balance(@house_balance) %>
                          <%= if @rogue_usd_price do %>
                            <span class="text-gray-400">(<%= format_usd(@rogue_usd_price, @house_balance) %>)</span>
                          <% end %>
                        </a>
                      <% else %>
                        <span class="text-gray-400 text-[10px] sm:text-xs">
                          House: <%= format_balance(@house_balance) %>
                        </span>
                      <% end %>
                    </div>
                  </div>
                </div>
              </div>

              <!-- Potential Profit Display -->
              <div class="bg-green-50 rounded-xl p-2 sm:p-3 mb-3 sm:mb-4 border border-green-200">
                <div class="flex items-center justify-between">
                  <span class="text-gray-700 text-xs sm:text-sm">Potential Profit:</span>
                  <div class="flex items-center gap-1 sm:gap-3">
                    <span class="text-base sm:text-xl font-bold text-green-600 flex items-center gap-1 sm:gap-2">
                      <img src={Map.get(@token_logos, @selected_token, "https://ik.imagekit.io/blockster/blockster-icon.png")} alt={@selected_token} class="w-4 sm:w-5 h-4 sm:h-5 rounded-full" />
                      +<%= format_balance(@bet_amount * get_multiplier(@selected_difficulty) - @bet_amount) %>
                    </span>
                    <%= if @selected_token == "ROGUE" && @rogue_usd_price do %>
                      <span class="text-xs sm:text-sm text-green-500">
                        (<%= format_usd(@rogue_usd_price, @bet_amount * get_multiplier(@selected_difficulty) - @bet_amount) %>)
                      </span>
                    <% end %>
                  </div>
                </div>
              </div>

              <!-- Error Message -->
              <%= if @error_message do %>
                <div class="bg-red-50 border border-red-300 rounded-lg p-2 sm:p-3 mb-3 sm:mb-4 text-red-700 text-xs sm:text-sm">
                  <%= @error_message %>
                </div>
              <% end %>

              <!-- Prediction Selection Grid -->
              <div class="flex-1 flex flex-col">
                <div class="flex items-start sm:items-center justify-between mb-2 gap-2">
                  <label class="block text-xs sm:text-sm font-medium text-gray-700">
                    <%= if get_mode(@selected_difficulty) == :win_one do %>
                      <span class="hidden sm:inline">Make your prediction<%= if get_predictions_needed(@selected_difficulty) > 1, do: "s" %> (win if any of <%= get_predictions_needed(@selected_difficulty) %> flips match)</span>
                      <span class="sm:hidden">Predict (<%= get_predictions_needed(@selected_difficulty) %> flips, win any)</span>
                    <% else %>
                      <span class="hidden sm:inline">Make your prediction<%= if get_predictions_needed(@selected_difficulty) > 1, do: "s" %> (<%= get_predictions_needed(@selected_difficulty) %> flip<%= if get_predictions_needed(@selected_difficulty) > 1, do: "s" %>)</span>
                      <span class="sm:hidden">Predict (<%= get_predictions_needed(@selected_difficulty) %> flip<%= if get_predictions_needed(@selected_difficulty) > 1, do: "s" %>)</span>
                    <% end %>
                  </label>
                  <!-- Provably Fair -->
                  <div class="relative">
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
                    <%= if @show_provably_fair do %>
                      <div
                        phx-click-away="close_provably_fair"
                        class="absolute right-0 top-full mt-1 z-50 w-[calc(100vw-24px)] sm:w-80 max-w-80 bg-white rounded-lg p-2 sm:p-3 border border-gray-200 shadow-lg text-left overflow-hidden"
                      >
                        <p class="text-[10px] sm:text-xs text-gray-600 mb-2">
                          This hash commits the server to a result BEFORE you place your bet.
                          After the game, you can verify the result was fair.
                        </p>
                        <div class="flex items-start gap-2 overflow-hidden">
                          <%= if @current_user do %>
                            <%= if assigns[:commitment_tx] do %>
                              <a
                                href={"https://roguescan.io/tx/#{@commitment_tx}?tab=logs"}
                                target="_blank"
                                rel="noopener noreferrer"
                                class="text-xs font-mono bg-gray-50 px-2 py-1.5 rounded border border-gray-200 overflow-wrap-anywhere text-blue-500 hover:underline cursor-pointer"
                                style="word-break: break-all;"
                              >
                                <%= @server_seed_hash %>
                              </a>
                            <% else %>
                              <code class="text-xs font-mono bg-gray-50 px-2 py-1.5 rounded border border-gray-200 text-gray-700 overflow-wrap-anywhere" style="word-break: break-all;">
                                <%= @server_seed_hash %>
                              </code>
                            <% end %>
                            <button
                              type="button"
                              id="copy-server-hash"
                              phx-hook="CopyToClipboard"
                              data-copy-text={@server_seed_hash}
                              class="shrink-0 p-1.5 text-gray-400 hover:text-gray-600 hover:bg-gray-100 rounded cursor-pointer transition-colors"
                              title="Copy hash"
                            >
                              <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z" />
                              </svg>
                            </button>
                          <% else %>
                            <code class="text-xs font-mono bg-gray-50 px-2 py-1.5 rounded border border-gray-200 text-gray-500 overflow-wrap-anywhere" style="word-break: break-all;">
                              &lt;hashed_server_seed_displays_here_when_you_are_logged_in&gt;
                            </code>
                          <% end %>
                        </div>
                        <p class="text-xs text-gray-400 mt-2">
                          Game #<%= @nonce %>
                        </p>
                      </div>
                    <% end %>
                  </div>
                </div>
                <div class="flex-1 flex items-center justify-center">
                  <% num_flips = get_predictions_needed(@selected_difficulty) %>
                  <% sizes = get_prediction_size_classes(num_flips) %>
                  <div class="flex gap-1.5 sm:gap-2 justify-center flex-wrap">
                    <%= for i <- 1..num_flips do %>
                      <button
                        type="button"
                        phx-click="toggle_prediction"
                        phx-value-index={i}
                        class={"#{sizes.outer} rounded-full flex items-center justify-center transition-all cursor-pointer shadow-md #{case Enum.at(@predictions, i - 1) do
                          :heads -> "casino-chip-heads"
                          :tails -> "casino-chip-tails"
                          _ -> "bg-gray-200 text-gray-500 hover:bg-gray-300"
                        end}"}
                      >
                          <%= case Enum.at(@predictions, i - 1) do %>
                          <% :heads -> %>
                            <div class={"#{sizes.inner} rounded-full bg-coin-heads flex items-center justify-center border-2 border-white shadow-inner"}>
                              <span class={sizes.emoji}>🚀</span>
                            </div>
                          <% :tails -> %>
                            <div class={"#{sizes.inner} rounded-full bg-gray-700 flex items-center justify-center border-2 border-white shadow-inner"}>
                              <span class={sizes.emoji}>💩</span>
                            </div>
                          <% _ -> %><%= i %>
                        <% end %>
                      </button>
                    <% end %>
                  </div>
                </div>
              </div>

              <!-- Start Game Button -->
              <div class="mt-3 sm:mt-4">
                <button
                  type="button"
                  phx-click="start_game"
                  disabled={Enum.any?(@predictions, &is_nil/1)}
                  class="w-full py-3 sm:py-4 bg-black text-white font-bold text-base sm:text-lg rounded-xl hover:bg-gray-800 transition-all cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed"
                >
                <%= if Enum.all?(@predictions, &(!is_nil(&1))) do %>
                  Place Bet
                <% else %>
                  <%= if get_predictions_needed(@selected_difficulty) == 1 do %>
                    Make your prediction
                  <% else %>
                    Select all <%= get_predictions_needed(@selected_difficulty) %> predictions
                  <% end %>
                <% end %>
                </button>
              </div>

            <% else %>
              <!-- Game in Progress -->
              <div class="text-center flex-1 flex flex-col relative">
                <% num_flips = get_predictions_needed(@selected_difficulty) %>
                <% sizes = get_coin_size_classes(num_flips) %>
                <!-- Prediction vs Result Display -->
                <div class="mb-3 sm:mb-4">
                  <div class="flex justify-center gap-1 sm:gap-2 mb-2 flex-wrap">
                    <%= for i <- 1..num_flips do %>
                      <div class="text-center">
                        <!-- Prediction -->
                        <div class={"#{sizes.outer} mx-auto rounded-full flex items-center justify-center mb-1 #{if Enum.at(@predictions, i - 1) == :heads, do: "casino-chip-heads", else: "casino-chip-tails"}"}>
                          <div class={"#{sizes.inner} rounded-full flex items-center justify-center border-2 border-white shadow-inner #{if Enum.at(@predictions, i - 1) == :heads, do: "bg-coin-heads", else: "bg-gray-700"}"}>
                            <span class={sizes.emoji}><%= if Enum.at(@predictions, i - 1) == :heads, do: "🚀", else: "💩" %></span>
                          </div>
                        </div>
                        <!-- Result indicator -->
                        <%= cond do %>
                          <% (@game_state == :result and i <= @current_flip and Enum.at(@results, i - 1) != nil) or
                             (i < @current_flip) or (i == @current_flip and @game_state == :showing_result) -> %>
                            <% result = Enum.at(@results, i - 1) %>
                            <% matched = result == Enum.at(@predictions, i - 1) %>
                            <div class={"#{sizes.outer} mx-auto rounded-full flex items-center justify-center #{if result == :heads, do: "casino-chip-heads", else: "casino-chip-tails"} #{if matched, do: "ring-[3px] ring-green-500", else: "ring-[3px] ring-red-500"}"}>
                              <div class={"#{sizes.inner} rounded-full flex items-center justify-center border-2 border-white shadow-inner #{if result == :heads, do: "bg-coin-heads", else: "bg-gray-700"}"}>
                                <span class={sizes.emoji}><%= if result == :heads, do: "🚀", else: "💩" %></span>
                              </div>
                            </div>
                          <% i == @current_flip and @game_state == :flipping -> %>
                            <div class={"#{sizes.outer} mx-auto rounded-full flex items-center justify-center bg-purple-500 animate-pulse"}>
                              <span class={"text-white #{sizes.emoji} font-bold"}>?</span>
                            </div>
                          <% true -> %>
                            <div class={"#{sizes.outer} mx-auto rounded-full flex items-center justify-center bg-gray-100"}>
                              <span class="text-gray-400 text-lg sm:text-xl">-</span>
                            </div>
                        <% end %>
                      </div>
                    <% end %>
                  </div>
                </div>

                <!-- Bet Amount Display (shown during flipping/showing_result) -->
                <%= if @game_state in [:flipping, :showing_result] do %>
                  <div class="mb-3 sm:mb-4 text-center">
                    <p class="text-gray-500 text-xs sm:text-sm">Bet</p>
                    <p class="text-lg sm:text-xl font-bold text-gray-900 flex items-center justify-center gap-1 sm:gap-2">
                      <img src={Map.get(@token_logos, @selected_token, "https://ik.imagekit.io/blockster/blockster-icon.png")} alt={@selected_token} class="w-4 sm:w-5 h-4 sm:h-5 rounded-full" />
                      <span><%= format_balance(@current_bet) %></span>
                      <%= if @selected_token == "ROGUE" && @rogue_usd_price do %>
                        <span class="text-gray-400 text-sm sm:text-base font-normal">≈ <%= format_usd(@rogue_usd_price, @current_bet) %></span>
                      <% end %>
                    </p>
                  </div>
                <% end %>

                <%= if @game_state == :awaiting_tx do %>
                  <!-- Awaiting Transaction State -->
                  <div class="mb-4 sm:mb-6 text-center">
                    <div class="w-16 h-16 sm:w-24 sm:h-24 mx-auto rounded-full flex items-center justify-center bg-purple-100 animate-pulse mb-3 sm:mb-4">
                      <svg class="w-8 h-8 sm:w-12 sm:h-12 text-purple-600 animate-spin" fill="none" viewBox="0 0 24 24">
                        <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                        <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                      </svg>
                    </div>
                    <h3 class="text-base sm:text-lg font-bold text-gray-900 mb-1 sm:mb-2">Confirm Transaction</h3>
                    <p class="text-xs sm:text-sm text-gray-600 mb-3 sm:mb-4">Please approve the transaction in your wallet</p>
                    <p class="text-[10px] sm:text-xs text-gray-400">
                      Betting <%= format_balance(@current_bet) %> <%= @selected_token %>
                    </p>
                  </div>
                <% end %>

                <%= if @game_state == :flipping do %>
                  <!-- Coin Flip Animation -->
                  <div class="mb-4 sm:mb-6" id={"coin-flip-#{@flip_id}"} phx-hook="CoinFlip" data-result={Enum.at(@results, @current_flip - 1)} data-flip-index={@current_flip}>
                    <div class={"coin-container mx-auto #{sizes.outer} relative perspective-1000"}>
                      <div class="coin w-full h-full absolute animate-flip-continuous">
                        <!-- Heads chip -->
                        <div class="coin-face coin-heads absolute w-full h-full rounded-full flex items-center justify-center backface-hidden casino-chip-heads">
                          <div class={"#{sizes.inner} rounded-full bg-coin-heads flex items-center justify-center border-2 border-white shadow-inner"}>
                            <span class={sizes.emoji}>🚀</span>
                          </div>
                        </div>
                        <!-- Tails chip -->
                        <div class="coin-face coin-tails absolute w-full h-full rounded-full flex items-center justify-center backface-hidden rotate-y-180 casino-chip-tails">
                          <div class={"#{sizes.inner} rounded-full bg-gray-700 flex items-center justify-center border-2 border-white shadow-inner"}>
                            <span class={sizes.emoji}>💩</span>
                          </div>
                        </div>
                      </div>
                    </div>
                  </div>
                <% end %>

                <%= if @game_state == :showing_result do %>
                  <!-- Show coin result for 1 second -->
                  <div class="mb-4 sm:mb-6">
                    <div class={"coin-container mx-auto #{sizes.outer} relative perspective-1000"}>
                      <!-- Static coin showing the result -->
                      <div class="w-full h-full absolute" style={"transform-style: preserve-3d; transform: rotateY(#{if Enum.at(@results, @current_flip - 1) == :heads, do: "0deg", else: "180deg"})"}>
                        <!-- Heads chip -->
                        <div class="coin-face coin-heads absolute w-full h-full rounded-full flex items-center justify-center backface-hidden casino-chip-heads">
                          <div class={"#{sizes.inner} rounded-full bg-coin-heads flex items-center justify-center border-2 border-white shadow-inner"}>
                            <span class={sizes.emoji}>🚀</span>
                          </div>
                        </div>
                        <!-- Tails chip -->
                        <div class="coin-face coin-tails absolute w-full h-full rounded-full flex items-center justify-center backface-hidden rotate-y-180 casino-chip-tails">
                          <div class={"#{sizes.inner} rounded-full bg-gray-700 flex items-center justify-center border-2 border-white shadow-inner"}>
                            <span class={sizes.emoji}>💩</span>
                          </div>
                        </div>
                      </div>
                    </div>
                    <p class="mt-2 sm:mt-3 text-xs sm:text-sm">
                      <span class={if Enum.at(@results, @current_flip - 1) == Enum.at(@predictions, @current_flip - 1), do: "text-green-600 font-bold", else: "text-red-600 font-bold"}>
                        <%= if Enum.at(@results, @current_flip - 1) == Enum.at(@predictions, @current_flip - 1), do: "✓ Correct!", else: "✗ Wrong!" %>
                      </span>
                    </p>
                  </div>
                <% end %>

                <%= if @game_state == :result do %>
                  <!-- Full-page Confetti Container (only on win) -->
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

                  <!-- Final Result Display -->
                  <div class="mb-4 sm:mb-6 relative">
                    <%= if @won do %>
                      <!-- Win content with scale-in and shake animation - emoji on side -->
                      <div class="win-celebration win-shake flex items-center justify-center gap-2 sm:gap-4">
                        <div class="animate-bounce text-3xl sm:text-[50px] leading-none">🎉</div>
                        <div class="text-center">
                          <h2 class="text-xl sm:text-3xl font-bold text-green-600 mb-1 animate-pulse">YOU WON!</h2>
                          <p class="text-lg sm:text-2xl text-gray-900 flex items-center justify-center gap-1 sm:gap-2">
                            <img src={Map.get(@token_logos, @selected_token, "https://ik.imagekit.io/blockster/blockster-icon.png")} alt={@selected_token} class="w-5 sm:w-6 h-5 sm:h-6 rounded-full" />
                            <span class="text-green-600 font-bold"><%= format_balance(@payout) %></span>
                            <span><%= @selected_token %></span>
                          </p>
                          <%= if @selected_token == "ROGUE" && @rogue_usd_price do %>
                            <p class="text-xs sm:text-sm text-gray-500 mt-1">
                              ≈ <%= format_usd(@rogue_usd_price, @payout) %>
                            </p>
                          <% end %>
                        </div>
                        <div class="animate-bounce text-3xl sm:text-[50px] leading-none">🎉</div>
                      </div>
                    <% else %>
                      <!-- Loss content -->
                      <div class="text-center">
                        <p class="text-lg sm:text-xl text-gray-900 flex items-center justify-center gap-1 sm:gap-2">
                          <img src={Map.get(@token_logos, @selected_token, "https://ik.imagekit.io/blockster/blockster-icon.png")} alt={@selected_token} class="w-4 sm:w-5 h-4 sm:h-5 rounded-full" />
                          <span class="text-red-600 font-bold">-<%= format_balance(@bet_amount) %></span>
                          <span><%= @selected_token %></span>
                        </p>
                        <%= if @selected_token == "ROGUE" && @rogue_usd_price do %>
                          <p class="text-xs sm:text-sm text-gray-500 mt-1">
                            ≈ -<%= format_usd(@rogue_usd_price, @bet_amount) %>
                          </p>
                        <% end %>
                      </div>
                    <% end %>
                  </div>

                  <!-- Play Again & Verify Buttons -->
                  <div class="mt-auto flex flex-col items-center gap-2">
                    <button
                      type="button"
                      phx-click="reset_game"
                      class="px-6 sm:px-8 py-2.5 sm:py-3 bg-black text-white font-bold text-sm sm:text-base rounded-xl hover:bg-gray-800 transition-all cursor-pointer animate-fade-in"
                    >
                      Play Again
                    </button>
                    <%= if @onchain_game_id do %>
                      <button
                        type="button"
                        phx-click="show_fairness_modal"
                        phx-value-game-id={@onchain_game_id}
                        class="text-xs text-gray-500 hover:text-gray-700 flex items-center gap-1 cursor-pointer"
                      >
                        <svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
                        </svg>
                        Verify Fairness
                      </button>
                    <% end %>
                  </div>
                <% end %>
              </div>
            <% end %>

            </div>
          </div>
        </div>

        <!-- BUX Booster Games -->
        <div class="mt-4 sm:mt-6">
          <div class="bg-white rounded-xl p-3 sm:p-4 shadow-sm border border-gray-200">
            <h3 class="text-xs sm:text-sm font-bold text-gray-900 mb-2 sm:mb-3">BUX Booster Games</h3>
            <%= if assigns[:games_loading] do %>
              <div class="text-center py-4 text-gray-500 text-xs sm:text-sm">Loading games...</div>
            <% end %>
            <%= if length(@recent_games) > 0 do %>
              <div id="recent-games-scroll" class="overflow-x-auto overflow-y-auto max-h-72 sm:max-h-96 relative" phx-hook="InfiniteScroll">
                <table class="w-full text-[10px] sm:text-xs min-w-[600px]">
                  <thead class="sticky top-0 z-20 bg-white">
                    <tr class="border-b-2 border-gray-200 bg-white">
                      <th class="text-left py-1.5 sm:py-2 px-1.5 sm:px-2 text-gray-600 font-medium bg-white whitespace-nowrap">ID</th>
                      <th class="text-left py-1.5 sm:py-2 px-1.5 sm:px-2 text-gray-600 font-medium bg-white whitespace-nowrap">Bet</th>
                      <th class="text-left py-1.5 sm:py-2 px-1.5 sm:px-2 text-gray-600 font-medium bg-white whitespace-nowrap">Pred</th>
                      <th class="text-left py-1.5 sm:py-2 px-1.5 sm:px-2 text-gray-600 font-medium bg-white whitespace-nowrap">Result</th>
                      <th class="text-left py-1.5 sm:py-2 px-1.5 sm:px-2 text-gray-600 font-medium bg-white whitespace-nowrap">Odds</th>
                      <th class="text-left py-1.5 sm:py-2 px-1.5 sm:px-2 text-gray-600 font-medium bg-white whitespace-nowrap">W/L</th>
                      <th class="text-left py-1.5 sm:py-2 px-1.5 sm:px-2 text-gray-600 font-medium bg-white whitespace-nowrap">P/L</th>
                      <th class="text-left py-1.5 sm:py-2 px-1.5 sm:px-2 text-gray-600 font-medium bg-white whitespace-nowrap">Verify</th>
                    </tr>
                  </thead>
                    <tbody>
                      <%= for game <- @recent_games do %>
                        <tr id={"game-#{game.game_id}"} class={"border-b border-gray-100 #{if game.won, do: "bg-green-50/30", else: "bg-red-50/30"}"}>
                          <!-- Bet ID (nonce linked to commitment tx) -->
                          <td class="py-1.5 sm:py-2 px-1.5 sm:px-2">
                            <%= if game.commitment_tx do %>
                              <a href={"https://roguescan.io/tx/#{game.commitment_tx}?tab=logs"} target="_blank" class="text-blue-500 hover:underline cursor-pointer font-mono">
                                #<%= game.nonce %>
                              </a>
                            <% else %>
                              <span class="font-mono text-gray-500">#<%= game.nonce %></span>
                            <% end %>
                          </td>
                          <!-- Bet Amount (linked to bet placement tx) -->
                          <td class="py-1.5 sm:py-2 px-1.5 sm:px-2">
                            <%= if game.bet_tx do %>
                              <a href={"https://roguescan.io/tx/#{game.bet_tx}?tab=logs"} target="_blank" class="text-blue-500 hover:underline decoration-blue-500 cursor-pointer flex items-center gap-1">
                                <img src={Map.get(@token_logos, game.token_type, "https://ik.imagekit.io/blockster/blockster-icon.png")} alt={game.token_type} class="w-3 sm:w-4 h-3 sm:h-4 rounded-full" />
                                <span><%= format_integer(game.bet_amount) %></span>
                              </a>
                            <% else %>
                              <div class="flex items-center gap-1">
                                <img src={Map.get(@token_logos, game.token_type, "https://ik.imagekit.io/blockster/blockster-icon.png")} alt={game.token_type} class="w-3 sm:w-4 h-3 sm:h-4 rounded-full" />
                                <span class="text-gray-900"><%= format_integer(game.bet_amount) %></span>
                              </div>
                            <% end %>
                          </td>
                          <!-- Predictions -->
                          <td class="py-1.5 sm:py-2 px-1.5 sm:px-2">
                            <div class="flex gap-0">
                              <%= for pred <- (game.predictions || []) do %>
                                <span class="text-[10px] sm:text-xs"><%= if pred == :heads, do: "🚀", else: "💩" %></span>
                              <% end %>
                            </div>
                          </td>
                          <!-- Results -->
                          <td class="py-1.5 sm:py-2 px-1.5 sm:px-2">
                            <div class="flex gap-0">
                              <%= for result <- (game.results || []) do %>
                                <span class="text-[10px] sm:text-xs"><%= if result == :heads, do: "🚀", else: "💩" %></span>
                              <% end %>
                            </div>
                          </td>
                          <!-- Odds -->
                          <td class="py-1.5 sm:py-2 px-1.5 sm:px-2 text-gray-900 font-medium whitespace-nowrap"><%= game.multiplier %>x</td>
                          <!-- Win/Loss -->
                          <td class="py-1.5 sm:py-2 px-1.5 sm:px-2">
                            <%= if game.won do %>
                              <span class="text-green-600 font-medium">W</span>
                            <% else %>
                              <span class="text-red-600 font-medium">L</span>
                            <% end %>
                          </td>
                          <!-- P/L (profit for wins, loss for losses) -->
                          <td class="py-1.5 sm:py-2 px-1.5 sm:px-2 whitespace-nowrap">
                            <%= if game.won do %>
                              <% profit = game.payout - game.bet_amount %>
                              <%= if game.settlement_tx do %>
                                <a href={"https://roguescan.io/tx/#{game.settlement_tx}?tab=logs"} target="_blank" class="text-green-600 hover:underline cursor-pointer font-medium">
                                  +<%= format_balance(profit) %>
                                </a>
                              <% else %>
                                <span class="text-green-600 font-medium">
                                  +<%= format_balance(profit) %>
                                </span>
                              <% end %>
                            <% else %>
                              <% loss = game.bet_amount %>
                              <%= if game.settlement_tx do %>
                                <a href={"https://roguescan.io/tx/#{game.settlement_tx}?tab=logs"} target="_blank" class="text-red-600 hover:underline cursor-pointer font-medium">
                                  -<%= format_balance(loss) %>
                                </a>
                              <% else %>
                                <span class="text-red-600 font-medium">-<%= format_balance(loss) %></span>
                              <% end %>
                            <% end %>
                          </td>
                          <!-- Verify -->
                          <td class="py-1.5 sm:py-2 px-1.5 sm:px-2">
                            <%= if game.server_seed && game.server_seed_hash && game.nonce do %>
                              <button type="button" phx-click="show_fairness_modal" phx-value-game-id={game.game_id} class="text-blue-500 hover:underline cursor-pointer">
                                ✓
                              </button>
                            <% else %>
                              <span class="text-gray-400">-</span>
                            <% end %>
                          </td>
                        </tr>
                      <% end %>
                    </tbody>
                  </table>
                </div>
            <% else %>
              <%= if !assigns[:games_loading] do %>
                <p class="text-gray-500 text-[10px] sm:text-xs">No games played yet</p>
              <% end %>
            <% end %>
          </div>
        </div>
      </div>
    </div>

    <!-- Fairness Verification Modal -->
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
                <div class="text-xs sm:text-sm"><%= @fairness_game.bet_amount %></div>
                <div class="text-blue-600">Token:</div>
                <div class="text-xs sm:text-sm"><%= @fairness_game.token %></div>
                <div class="text-blue-600">Difficulty:</div>
                <div class="text-xs sm:text-sm"><%= @fairness_game.difficulty %></div>
                <div class="text-blue-600">Predictions:</div>
                <div class="text-xs sm:text-sm"><%= @fairness_game.predictions_str %></div>
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
                  <%= @fairness_game.server_seed_hash %>
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
                <li>client_seed = SHA256(bet_details)</li>
                <li>combined_seed = SHA256(server:client:nonce)</li>
                <li>Results from combined seed bytes</li>
              </ol>
            </div>

            <!-- Flip Results Breakdown -->
            <div>
              <p class="text-xs sm:text-sm font-medium text-gray-700 mb-1 sm:mb-2">Flip Results</p>
              <div class="space-y-1.5 sm:space-y-2">
                <%= for i <- 0..(length(@fairness_game.results) - 1) do %>
                  <% byte = Enum.at(@fairness_game.bytes, i) %>
                  <div class="flex items-center justify-between text-xs sm:text-sm bg-gray-50 p-1.5 sm:p-2 rounded">
                    <span>Flip <%= i + 1 %>:</span>
                    <div class="flex items-center gap-1 sm:gap-2">
                      <span class="font-mono text-[10px] sm:text-xs">byte[<%= i %>]=<%= byte %></span>
                      <span class={if byte < 128, do: "text-amber-600", else: "text-gray-600"}>
                        <%= if byte < 128, do: "🚀", else: "💩" %>
                      </span>
                      <span class="text-[10px] sm:text-xs text-gray-400 hidden sm:inline">
                        (<%= if byte < 128, do: "< 128", else: ">= 128" %>)
                      </span>
                    </div>
                  </div>
                <% end %>
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
                    SHA256(server_seed) → Click to verify
                  </a>
                  <p class="text-[10px] sm:text-xs text-gray-400 mt-1 font-mono break-all">Expected: <%= @fairness_game.server_seed_hash %></p>
                </div>

                <div class="bg-gray-50 rounded-lg p-2 sm:p-3">
                  <p class="text-[10px] sm:text-xs text-gray-600 mb-1">2. Derive client seed from bet details</p>
                  <a href={"https://md5calc.com/hash/sha256/#{@fairness_game.client_seed_input}"} target="_blank" class="text-blue-500 hover:underline text-[10px] sm:text-xs cursor-pointer">
                    SHA256(bet_details) → Click to verify
                  </a>
                  <p class="text-[10px] sm:text-xs text-gray-400 mt-1 font-mono break-all">Expected: <%= @fairness_game.client_seed %></p>
                </div>

                <div class="bg-gray-50 rounded-lg p-2 sm:p-3">
                  <p class="text-[10px] sm:text-xs text-gray-600 mb-1">3. Generate combined seed</p>
                  <a href={"https://md5calc.com/hash/sha256/#{@fairness_game.server_seed}:#{@fairness_game.client_seed}:#{@fairness_game.nonce}"} target="_blank" class="text-blue-500 hover:underline text-[10px] sm:text-xs cursor-pointer">
                    SHA256(server:client:nonce) → Click to verify
                  </a>
                  <p class="text-[10px] sm:text-xs text-gray-400 mt-1 font-mono break-all">Expected: <%= @fairness_game.combined_seed %></p>
                </div>

                <div class="bg-gray-50 rounded-lg p-2 sm:p-3">
                  <p class="text-[10px] sm:text-xs text-gray-600 mb-1">4. Convert hex to bytes for flip results</p>
                  <p class="text-[10px] sm:text-xs text-gray-500 mb-2">
                    Each pair of hex chars = 1 byte. First <%= length(@fairness_game.results) %> bytes determine flips:
                  </p>
                  <div class="bg-white rounded p-1.5 sm:p-2 border">
                    <%= for {byte, i} <- Enum.with_index(@fairness_game.bytes) do %>
                      <div class={"flex items-center justify-between text-[10px] sm:text-xs py-0.5 sm:py-1 #{if i > 0, do: "border-t border-gray-100"}"}>
                        <span class="font-mono text-gray-500">
                          byte[<%= i %>] = 0x<%= String.slice(@fairness_game.combined_seed, i * 2, 2) %> = <%= byte %>
                        </span>
                        <span class={if byte < 128, do: "text-amber-600", else: "text-gray-600"}>
                          <%= if byte < 128, do: "< 128 → 🚀", else: ">= 128 → 💩" %>
                        </span>
                      </div>
                    <% end %>
                  </div>
                  <p class="text-xs text-gray-400 mt-2">
                    Verify: <a href="https://www.rapidtables.com/convert/number/hex-to-decimal.html" target="_blank" class="text-blue-500 hover:underline cursor-pointer">Hex to Decimal converter</a>
                  </p>
                </div>
              </div>
            </div>
          </div>

          <!-- Footer -->
          <div class="p-4 border-t bg-gray-50 rounded-b-2xl">
            <button type="button" phx-click="hide_fairness_modal" class="w-full py-2 bg-gray-200 text-gray-700 rounded-lg hover:bg-gray-300 transition-all cursor-pointer">
              Close
            </button>
          </div>
        </div>
      </div>
    <% end %>

    <style>
      .perspective-1000 {
        perspective: 1000px;
      }
      .backface-hidden {
        backface-visibility: hidden;
      }
      .rotate-y-180 {
        transform: rotateY(180deg);
      }
      /* Heads animation - ends at 1800deg (5 full rotations, showing heads) */
      @keyframes flip-heads {
        0% { transform: rotateY(0deg); }
        100% { transform: rotateY(1800deg); }
      }
      /* Tails animation - ends at 1980deg (5 full rotations + 180, showing tails) */
      @keyframes flip-tails {
        0% { transform: rotateY(0deg); }
        100% { transform: rotateY(1980deg); }
      }
      .animate-flip-heads {
        animation: flip-heads 3s ease-out forwards;
        transform-style: preserve-3d;
      }
      .animate-flip-tails {
        animation: flip-tails 3s ease-out forwards;
        transform-style: preserve-3d;
      }

      /* Full-page emoji confetti burst animation */
      .confetti-fullpage {
        perspective: 1000px;
      }
      .confetti-emoji {
        position: absolute;
        font-size: 24px;
        left: var(--x-start);
        bottom: 40%;
        animation: confetti-burst var(--duration, 3s) cubic-bezier(0.25, 0.46, 0.45, 0.94) forwards;
        animation-delay: var(--delay, 0ms);
        opacity: 0;
        filter: drop-shadow(0 2px 4px rgba(0,0,0,0.3));
      }

      @keyframes confetti-burst {
        0% {
          opacity: 1;
          transform: translateY(0) translateX(0) rotate(0deg) scale(0.5);
        }
        15% {
          /* Peak of burst - already spread out */
          opacity: 1;
          transform: translateY(-50vh) translateX(var(--x-drift)) rotate(calc(var(--rotation) * 0.4)) scale(1.2);
        }
        100% {
          /* Fall straight down from spread position - stay solid */
          opacity: 1;
          transform: translateY(60vh) translateX(var(--x-drift)) rotate(var(--rotation)) scale(0.8);
        }
      }

      /* Win celebration animation */
      .win-celebration {
        animation: scale-in 0.5s ease-out forwards;
      }
      @keyframes scale-in {
        0% {
          transform: scale(0.5);
          opacity: 0;
        }
        50% {
          transform: scale(1.1);
        }
        100% {
          transform: scale(1);
          opacity: 1;
        }
      }

      /* Win shake animation */
      .win-shake {
        animation: shake 0.5s ease-out;
      }
      @keyframes shake {
        0%, 100% { transform: translateX(0); }
        10%, 30%, 50%, 70%, 90% { transform: translateX(-5px); }
        20%, 40%, 60%, 80% { transform: translateX(5px); }
      }

      /* Fade in for button */
      .animate-fade-in {
        animation: fade-in 0.5s ease-out 0.3s both;
      }
      @keyframes fade-in {
        0% { opacity: 0; transform: translateY(10px); }
        100% { opacity: 1; transform: translateY(0); }
      }
    </style>
    """
  end

  # Event Handlers

  @impl true
  def handle_event("select_token", %{"token" => token}, socket) do
    user_stats = if socket.assigns.current_user do
      load_user_stats(socket.assigns.current_user.id, token)
    else
      nil
    end

    # Set default bet amount based on token (ROGUE has much higher values)
    default_bet = if token == "ROGUE", do: 100_000, else: 10
    # Extract difficulty before start_async to avoid copying entire socket
    difficulty = socket.assigns.selected_difficulty

    {:noreply,
     socket
     |> assign(selected_token: token)
     |> assign(header_token: token)
     |> assign(bet_amount: default_bet)
     |> assign(user_stats: user_stats)
     |> assign(show_token_dropdown: false)
     |> assign(error_message: nil)
     |> start_async(:fetch_house_balance, fn -> fetch_house_balance_async(token, difficulty) end)}
  end

  @impl true
  def handle_event("toggle_token_dropdown", _params, socket) do
    {:noreply, assign(socket, show_token_dropdown: !socket.assigns.show_token_dropdown)}
  end

  @impl true
  def handle_event("hide_token_dropdown", _params, socket) do
    {:noreply, assign(socket, show_token_dropdown: false)}
  end

  @impl true
  def handle_event("toggle_provably_fair", _params, socket) do
    {:noreply, assign(socket, show_provably_fair: !socket.assigns.show_provably_fair)}
  end

  @impl true
  def handle_event("close_provably_fair", _params, socket) do
    {:noreply, assign(socket, show_provably_fair: false)}
  end

  @impl true
  def handle_event("select_difficulty", %{"level" => level}, socket) do
    new_level = String.to_integer(level)
    predictions_needed = get_predictions_needed(new_level)

    # Reset game state and predictions when difficulty changes
    # Also create new commitment hash asynchronously (same as Play Again)
    wallet_address = socket.assigns.wallet_address
    # Extract values before start_async to avoid copying entire socket
    selected_token = socket.assigns.selected_token
    user_id = if socket.assigns.current_user, do: socket.assigns.current_user.id, else: nil

    socket =
      socket
      |> assign(selected_difficulty: new_level)
      |> assign(predictions: List.duplicate(nil, predictions_needed))
      |> assign(results: [])
      |> assign(game_state: :idle)
      |> assign(current_flip: 0)
      |> assign(won: nil)
      |> assign(payout: 0)
      |> assign(error_message: nil)
      |> assign(confetti_pieces: [])
      |> assign(show_fairness_modal: false)
      |> assign(fairness_game: nil)
      |> start_async(:fetch_house_balance, fn -> fetch_house_balance_async(selected_token, new_level) end)

    # Initialize new on-chain game session asynchronously
    socket = if wallet_address && user_id do
      socket
      |> assign(:onchain_ready, false)
      |> assign(:onchain_initializing, true)
      |> start_async(:init_onchain_game, fn ->
        BuxBoosterOnchain.get_or_init_game(user_id, wallet_address)
      end)
    else
      socket
      |> assign(:onchain_ready, false)
      |> assign(:error_message, "No wallet connected")
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_prediction", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str) - 1
    predictions_needed = get_predictions_needed(socket.assigns.selected_difficulty)

    # Ensure predictions list is the right size
    current_predictions =
      if length(socket.assigns.predictions) == predictions_needed do
        socket.assigns.predictions
      else
        List.duplicate(nil, predictions_needed)
      end

    current_value = Enum.at(current_predictions, index)

    # Cycle through: nil -> :heads -> :tails -> :heads
    new_value =
      case current_value do
        nil -> :heads
        :heads -> :tails
        :tails -> :heads
      end

    new_predictions = List.replace_at(current_predictions, index, new_value)

    {:noreply, assign(socket, predictions: new_predictions)}
  end

  @impl true
  def handle_event("toggle_all_predictions", _params, socket) do
    # For win_one mode: toggle all predictions between heads and tails
    predictions_needed = get_predictions_needed(socket.assigns.selected_difficulty)
    current_value = Enum.at(socket.assigns.predictions, 0)

    # Cycle through: nil -> :heads -> :tails -> :heads
    new_value =
      case current_value do
        nil -> :heads
        :heads -> :tails
        :tails -> :heads
      end

    new_predictions = List.duplicate(new_value, predictions_needed)
    {:noreply, assign(socket, predictions: new_predictions)}
  end

  @impl true
  def handle_event("update_bet_amount", %{"value" => value}, socket) do
    case Integer.parse(value) do
      {amount, _} when amount > 0 ->
        {:noreply, assign(socket, bet_amount: amount, error_message: nil)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("set_max_bet", _params, socket) do
    if socket.assigns.current_user do
      # For logged in users: use the smaller of contract max bet or user balance
      balance = Map.get(socket.assigns.balances, socket.assigns.selected_token, 0)
      max_allowed = min(socket.assigns.max_bet, trunc(balance))
      {:noreply, assign(socket, bet_amount: max(1, max_allowed), error_message: nil)}
    else
      # For unauthenticated users: use the contract's max bet
      max_allowed = max(1, socket.assigns.max_bet)
      {:noreply, assign(socket, bet_amount: max_allowed, error_message: nil)}
    end
  end

  @impl true
  def handle_event("halve_bet", _params, socket) do
    new_amount = max(1, div(socket.assigns.bet_amount, 2))
    {:noreply, assign(socket, bet_amount: new_amount, error_message: nil)}
  end

  @impl true
  def handle_event("double_bet", _params, socket) do
    if socket.assigns.current_user do
      # For logged in users: cap at user balance
      balance = Map.get(socket.assigns.balances, socket.assigns.selected_token, 0)
      max_bet = trunc(balance)
      new_amount = min(max_bet, socket.assigns.bet_amount * 2)
      {:noreply, assign(socket, bet_amount: max(1, new_amount), error_message: nil)}
    else
      # For unauthenticated users: cap at contract max bet
      new_amount = min(socket.assigns.max_bet, socket.assigns.bet_amount * 2)
      {:noreply, assign(socket, bet_amount: max(1, new_amount), error_message: nil)}
    end
  end

  @impl true
  def handle_event("start_game", _params, socket) do
    # Redirect to login if not authenticated
    if socket.assigns.current_user == nil do
      {:noreply, push_navigate(socket, to: ~p"/login")}
    else
      balance = Map.get(socket.assigns.balances, socket.assigns.selected_token, 0)
      bet_amount = socket.assigns.bet_amount
      predictions = socket.assigns.predictions
      predictions_needed = get_predictions_needed(socket.assigns.selected_difficulty)
      onchain_ready = Map.get(socket.assigns, :onchain_ready, false)

      # Validate all predictions are made
      all_predictions_made =
        length(predictions) == predictions_needed and
          Enum.all?(predictions, fn p -> p in [:heads, :tails] end)

      # Minimum bet for ROGUE is 100 (set in ROGUEBankroll contract)
      min_rogue_bet = 100

      cond do
        not onchain_ready ->
          {:noreply, assign(socket, error_message: "Wallet not connected or game not initialized")}

        not all_predictions_made ->
          {:noreply, assign(socket, error_message: "Please make all #{predictions_needed} predictions")}

        bet_amount <= 0 ->
          {:noreply, assign(socket, error_message: "Bet amount must be greater than 0")}

        socket.assigns.selected_token == "ROGUE" and bet_amount < min_rogue_bet ->
          {:noreply, assign(socket, error_message: "Minimum bet for ROGUE is #{min_rogue_bet} ROGUE")}

        bet_amount > balance ->
          {:noreply, assign(socket, error_message: "Insufficient #{socket.assigns.selected_token} balance")}

        true ->
          # OPTIMISTIC FLOW: Deduct balance and start animation immediately
          user_id = socket.assigns.current_user.id
        wallet_address = socket.assigns.wallet_address
        token = socket.assigns.selected_token
        token_address = BuxBoosterOnchain.token_address(token)
        game_id = socket.assigns.onchain_game_id
        difficulty = socket.assigns.selected_difficulty

        # Convert predictions to contract format (0 = heads, 1 = tails)
        contract_predictions = Enum.map(predictions, fn
          :heads -> 0
          :tails -> 1
        end)

        # 1. Optimistically deduct balance from Mnesia
        case EngagementTracker.deduct_user_token_balance(user_id, wallet_address, token, bet_amount) do
          {:ok, new_balance} ->

            # 2. Calculate results immediately (server has seed already)
            case BuxBoosterOnchain.calculate_game_result(game_id, predictions, bet_amount, token, difficulty) do
              {:ok, result} ->
                # 3. Update balances in socket and broadcast
                balances = Map.put(socket.assigns.balances, token, new_balance)
                # Calculate aggregate by summing BUX-flavored tokens only (exclude "aggregate" and "ROGUE")
                aggregate_balance = balances
                |> Map.delete("aggregate")
                |> Map.delete("ROGUE")
                |> Map.values()
                |> Enum.sum()

                # Update the aggregate in the balances map
                balances = Map.put(balances, "aggregate", aggregate_balance)

                BlocksterV2Web.BuxBalanceHook.broadcast_balance_update(user_id, aggregate_balance)
                BlocksterV2Web.BuxBalanceHook.broadcast_token_balances_update(user_id, balances)

                # 4. Start animation IMMEDIATELY
                socket =
                  socket
                  |> assign(balances: balances)
                  |> assign(current_bet: bet_amount)
                  |> assign(results: result.results)
                  |> assign(won: result.won)
                  |> assign(payout: result.payout)
                  |> assign(game_state: :flipping)
                  |> assign(current_flip: 1)
                  |> assign(flip_id: 1)
                  |> assign(bet_confirmed: false)
                  |> assign(flip_start_time: System.monotonic_time(:millisecond))
                  |> assign(error_message: nil)

                # 5. Push background blockchain submission event
                socket =
                  push_event(socket, "place_bet_background", %{
                    game_id: game_id,
                    token_address: token_address,
                    amount: bet_amount,
                    difficulty: difficulty,
                    predictions: contract_predictions,
                    commitment_hash: socket.assigns.commitment_hash
                  })

                {:noreply, socket}

              {:error, reason} ->
                # Refund immediately if calculation fails
                EngagementTracker.credit_user_token_balance(user_id, wallet_address, token, bet_amount)
                {:noreply, assign(socket, error_message: "Failed to calculate result: #{inspect(reason)}")}
            end

          {:error, reason} ->
            {:noreply, assign(socket, error_message: "Failed to deduct balance: #{reason}")}
        end
      end
    end
  end

  @impl true
  def handle_event("flip_complete", _params, socket) do
    # Called from JavaScript when coin flip animation completes
    # Only process if we're actually in the flipping state
    if socket.assigns.game_state == :flipping do
      send(self(), :flip_complete)
    end
    {:noreply, socket}
  end

  @impl true
  def handle_event("bet_confirmed", %{"game_id" => _game_id, "tx_hash" => tx_hash, "confirmation_time_ms" => _conf_time}, socket) do

    # Mark bet as placed in Mnesia (now that blockchain confirms it)
    # Use the USER'S predictions, not the results!
    predictions = socket.assigns.predictions

    # Use commitment hash as bet_id (simpler than parsing events)
    bet_id = socket.assigns.commitment_hash
    bet_amount = socket.assigns.current_bet
    token = socket.assigns.selected_token
    difficulty = socket.assigns.selected_difficulty

    case BuxBoosterOnchain.on_bet_placed(socket.assigns.onchain_game_id, bet_id, tx_hash, predictions, bet_amount, token, difficulty) do
      {:ok, _result} ->
        :ok

      {:error, reason} ->
        Logger.error("[BuxBooster] Failed to mark bet as placed: #{inspect(reason)}")
    end

    # Calculate how long the flip has been spinning
    flip_start = socket.assigns[:flip_start_time]
    elapsed_ms = if flip_start do
      System.monotonic_time(:millisecond) - flip_start
    else
      0
    end

    min_spin_time = 3000  # Minimum 3 seconds for UX
    remaining_spin_time = max(0, min_spin_time - elapsed_ms)

    # Mark as confirmed
    socket = assign(socket, bet_confirmed: true)

    if remaining_spin_time > 0 do
      # Still need to spin longer for minimum UX time
      Process.send_after(self(), :reveal_flip_result, remaining_spin_time)
    else
      # Minimum time already passed, reveal immediately
      send(self(), :reveal_flip_result)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("bet_failed", %{"game_id" => game_id, "error" => error_message}, socket) do
    Logger.error("[BuxBooster] Bet submission failed: #{error_message}")

    # Refund the bet amount
    user_id = socket.assigns.current_user.id
    wallet_address = socket.assigns.wallet_address
    token = socket.assigns.selected_token
    bet_amount = socket.assigns.current_bet

    case EngagementTracker.credit_user_token_balance(user_id, wallet_address, token, bet_amount) do
      {:ok, new_balance} ->
        balances = Map.put(socket.assigns.balances, token, new_balance)
        # Calculate aggregate by summing BUX-flavored tokens only (exclude "aggregate" and "ROGUE")
        aggregate_balance = balances
        |> Map.delete("aggregate")
        |> Map.delete("ROGUE")
        |> Map.values()
        |> Enum.sum()
        # Update aggregate in the map
        balances = Map.put(balances, "aggregate", aggregate_balance)

        BlocksterV2Web.BuxBalanceHook.broadcast_balance_update(user_id, aggregate_balance)
        BlocksterV2Web.BuxBalanceHook.broadcast_token_balances_update(user_id, balances)

        {:noreply,
         socket
         |> assign(balances: balances)
         |> assign(game_state: :idle)
         |> assign(results: [])
         |> assign(won: nil)
         |> assign(payout: 0)
         |> assign(bet_confirmed: false)
         |> assign(error_message: "Transaction failed: #{error_message}. Bet refunded.")}

      {:error, _reason} ->
        {:noreply, assign(socket, error_message: "Transaction and refund failed - please contact support")}
    end
  end

  @impl true
  def handle_event("bet_placed", params, socket) do
    # Frontend successfully placed the bet on-chain (optimistic or confirmed)
    game_id = Map.get(params, "game_id")
    bet_id = Map.get(params, "bet_id")
    tx_hash = Map.get(params, "tx_hash")
    pending = Map.get(params, "pending", false)


    predictions = socket.assigns.predictions
    bet_amount = socket.assigns.bet_amount
    token = socket.assigns.selected_token
    difficulty = socket.assigns.selected_difficulty

    # Update the game record in Mnesia and calculate result
    # This works the same whether pending or confirmed
    case BuxBoosterOnchain.on_bet_placed(game_id, bet_id, tx_hash, predictions, bet_amount, token, difficulty) do
      {:ok, result} ->
        # Start the coin flip animation with pre-calculated results
        socket =
          socket
          |> assign(bet_tx: tx_hash)
          |> assign(bet_id: bet_id)
          |> assign(results: result.results)
          |> assign(game_state: :flipping)
          |> assign(current_flip: 1)
          |> assign(flip_id: 1)
          |> assign(won: result.won)
          |> assign(payout: result.payout)
          |> assign(bet_pending: pending)

        {:noreply, socket}

      {:error, reason} ->
        Logger.error("[BuxBooster] Failed to process bet: #{inspect(reason)}")
        {:noreply, assign(socket, error_message: "Failed to process bet: #{inspect(reason)}", game_state: :idle)}
    end
  end

  # Handle async result from on-chain game initialization
  @impl true
  def handle_async(:init_onchain_game, {:ok, {:ok, game_session}}, socket) do

    {:noreply,
     socket
     |> assign(:onchain_game_id, game_session.game_id)
     |> assign(:commitment_hash, game_session.commitment_hash)
     |> assign(:commitment_tx, game_session.commitment_tx)
     |> assign(:onchain_nonce, game_session.nonce)
     |> assign(:onchain_ready, true)
     |> assign(:onchain_initializing, false)
     |> assign(:init_retry_count, 0)  # Reset retry counter on success
     |> assign(:server_seed_hash, game_session.commitment_hash)
     |> assign(:nonce, game_session.nonce)
     |> assign(:error_message, nil)}  # Clear any error messages
  end

  @impl true
  def handle_async(:init_onchain_game, {:ok, {:error, reason}}, socket) do
    retry_count = Map.get(socket.assigns, :init_retry_count, 0)
    max_retries = 3

    if retry_count < max_retries do
      # Retry with exponential backoff: 1s, 2s, 4s
      delay = :math.pow(2, retry_count) * 1000 |> round()
      Logger.warning("[BuxBooster] Failed to init on-chain game (attempt #{retry_count + 1}/#{max_retries}): #{inspect(reason)}. Retrying in #{delay}ms...")

      Process.send_after(self(), :retry_init_onchain_game, delay)

      {:noreply,
       socket
       |> assign(:onchain_ready, false)
       |> assign(:onchain_initializing, true)
       |> assign(:init_retry_count, retry_count + 1)
       |> assign(:error_message, "Initializing game... (attempt #{retry_count + 1}/#{max_retries})")}
    else
      Logger.error("[BuxBooster] Failed to init on-chain game after #{max_retries} attempts: #{inspect(reason)}")

      {:noreply,
       socket
       |> assign(:onchain_ready, false)
       |> assign(:onchain_initializing, false)
       |> assign(:init_retry_count, 0)
       |> assign(:error_message, "Failed to initialize on-chain game. Please refresh the page.")}
    end
  end

  @impl true
  def handle_async(:init_onchain_game, {:exit, reason}, socket) do
    retry_count = Map.get(socket.assigns, :init_retry_count, 0)
    max_retries = 3

    if retry_count < max_retries do
      # Retry with exponential backoff: 1s, 2s, 4s
      delay = :math.pow(2, retry_count) * 1000 |> round()
      Logger.warning("[BuxBooster] On-chain game init crashed (attempt #{retry_count + 1}/#{max_retries}): #{inspect(reason)}. Retrying in #{delay}ms...")

      Process.send_after(self(), :retry_init_onchain_game, delay)

      {:noreply,
       socket
       |> assign(:onchain_ready, false)
       |> assign(:onchain_initializing, true)
       |> assign(:init_retry_count, retry_count + 1)
       |> assign(:error_message, "Initializing game... (attempt #{retry_count + 1}/#{max_retries})")}
    else
      Logger.error("[BuxBooster] On-chain game init crashed after #{max_retries} attempts: #{inspect(reason)}")

      {:noreply,
       socket
       |> assign(:onchain_ready, false)
       |> assign(:onchain_initializing, false)
       |> assign(:init_retry_count, 0)
       |> assign(:error_message, "Failed to initialize on-chain game. Please refresh the page.")}
    end
  end

  @impl true
  def handle_async(:fetch_house_balance, {:ok, {house_balance, max_bet}}, socket) do

    {:noreply,
     socket
     |> assign(:house_balance, house_balance)
     |> assign(:max_bet, max_bet)}
  end

  @impl true
  def handle_async(:fetch_house_balance, {:exit, reason}, socket) do
    Logger.warning("[BuxBooster] Failed to fetch house balance (async): #{inspect(reason)}")

    {:noreply, socket}
  end

  @impl true
  def handle_async(:load_recent_games, {:ok, games}, socket) do
    {:noreply,
     socket
     |> assign(:recent_games, games)
     |> assign(:games_offset, length(games))
     |> assign(:games_loading, false)}
  end

  @impl true
  def handle_async(:load_recent_games, {:exit, reason}, socket) do
    Logger.warning("[BuxBooster] Failed to load recent games (async): #{inspect(reason)}")
    {:noreply, assign(socket, :games_loading, false)}
  end

  # Handle confirmed betId from background polling (if different from commitment)
  def handle_event("bet_confirmed", %{"game_id" => _game_id, "bet_id" => bet_id, "tx_hash" => _tx_hash}, socket) do

    # Update the bet_id if it changed
    socket =
      socket
      |> assign(bet_id: bet_id)
      |> assign(bet_pending: false)

    {:noreply, socket}
  end

  @impl true
  def handle_event("bet_error", %{"error" => error}, socket) do
    # Frontend encountered an error placing the bet
    Logger.error("[BuxBooster] Bet error from frontend: #{error}")
    {:noreply, assign(socket, error_message: error, game_state: :idle)}
  end

  @impl true
  def handle_event("reset_game", _params, socket) do
    # Extract values before start_async to avoid copying entire socket
    selected_token = socket.assigns.selected_token
    selected_difficulty = socket.assigns.selected_difficulty
    predictions_needed = get_predictions_needed(selected_difficulty)

    # For unauthenticated users, just reset UI state
    if socket.assigns.current_user == nil do
      socket =
        socket
        |> assign(game_state: :idle)
        |> assign(current_flip: 0)
        |> assign(predictions: List.duplicate(nil, predictions_needed))
        |> assign(results: [])
        |> assign(won: nil)
        |> assign(payout: 0)
        |> assign(confetti_pieces: [])
        |> assign(error_message: nil)
        |> start_async(:fetch_house_balance, fn -> fetch_house_balance_async(selected_token, selected_difficulty) end)

      {:noreply, socket}
    else
      # Refresh balances and stats for logged in users
      user_id = socket.assigns.current_user.id
      balances = EngagementTracker.get_user_token_balances(user_id)
      user_stats = load_user_stats(user_id, selected_token)
      wallet_address = socket.assigns.wallet_address

      # Reset UI state immediately
      socket =
        socket
        |> assign(game_state: :idle)
        |> assign(current_flip: 0)
        |> assign(predictions: List.duplicate(nil, predictions_needed))
        |> assign(results: [])
        |> assign(won: nil)
        |> assign(payout: 0)
        |> assign(balances: balances)
        |> assign(user_stats: user_stats)
        # Keep existing recent_games list - don't reload
        |> assign(server_seed: nil)
        |> assign(confetti_pieces: [])
        |> assign(show_fairness_modal: false)
        |> assign(fairness_game: nil)
        |> assign(bet_tx: nil)
        |> assign(bet_id: nil)
        |> assign(settlement_tx: nil)
        |> assign(error_message: nil)
        |> start_async(:fetch_house_balance, fn -> fetch_house_balance_async(selected_token, selected_difficulty) end)

      # Initialize new on-chain game session asynchronously (non-blocking)
      socket = if wallet_address do
        socket
        |> assign(:onchain_ready, false)
        |> assign(:onchain_initializing, true)
        |> assign(:init_retry_count, 0)  # Reset retry counter on manual reset
        |> start_async(:init_onchain_game, fn ->
          BuxBoosterOnchain.get_or_init_game(user_id, wallet_address)
        end)
      else
        socket
        |> assign(:onchain_ready, false)
        |> assign(:init_retry_count, 0)
        |> assign(:error_message, "No wallet connected")
      end

      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("show_fairness_modal", %{"game-id" => game_id}, socket) do
    # CRITICAL SECURITY: Fetch ONLY settled games from Mnesia
    # NEVER show server seed for upcoming/pending games - this would allow players to predict results!
    case :mnesia.dirty_read({:bux_booster_onchain_games, game_id}) do
      [{:bux_booster_onchain_games, ^game_id, user_id, _wallet, server_seed, commitment_hash, nonce,
        status, _bet_id, token, _token_addr, bet_amount, difficulty, predictions, results, won,
        payout, _commitment_tx, bet_tx, settlement_tx, _created_at, _settled_at}] when status == :settled ->

        # Only show verification for SETTLED games where server seed has been revealed
        # Build the bet details string (same format used for hashing)
        predictions_str = predictions |> Enum.map(&Atom.to_string/1) |> Enum.join(",")

        client_seed_input = ProvablyFair.build_client_seed_input(
          user_id,
          bet_amount,
          token,
          difficulty,
          predictions
        )

        # Derive client seed from bet details
        client_seed = ProvablyFair.generate_client_seed(
          user_id,
          bet_amount,
          token,
          difficulty,
          predictions
        )

        # Build fairness game data for this SETTLED game
        combined_seed = ProvablyFair.generate_combined_seed(server_seed, client_seed, nonce)
        bytes = ProvablyFair.get_result_bytes(combined_seed, length(results))

        fairness_game = %{
          game_id: game_id,
          # Bet details (player-controlled only)
          user_id: user_id,
          bet_amount: bet_amount,
          token: token,
          difficulty: difficulty,
          predictions_str: predictions_str,
          nonce: nonce,
          # Seeds (ONLY revealed after settlement!)
          server_seed: server_seed,
          server_seed_hash: commitment_hash,
          client_seed_input: client_seed_input,
          client_seed: client_seed,
          combined_seed: combined_seed,
          # Results
          results: results,
          bytes: bytes,
          won: won,
          payout: payout,
          bet_tx: bet_tx,
          settlement_tx: settlement_tx
        }

        {:noreply,
         socket
         |> assign(show_fairness_modal: true)
         |> assign(fairness_game: fairness_game)}

      _ ->
        # Game not found or not settled - don't show modal
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("hide_fairness_modal", _params, socket) do
    {:noreply, assign(socket, show_fairness_modal: false)}
  end

  @impl true
  def handle_event("load-more-games", _params, socket) do
    # Only load games for logged in users
    if socket.assigns.current_user == nil do
      {:reply, %{end_reached: true}, socket}
    else
      # Load next 30 games
      user_id = socket.assigns.current_user.id
      offset = socket.assigns.games_offset

      new_games = load_recent_games(user_id, limit: 30, offset: offset)

      # If no more games, signal end reached
      if Enum.empty?(new_games) do
        {:reply, %{end_reached: true}, socket}
      else
        # Filter out duplicates (in case offset got out of sync due to prepends)
        existing_game_ids = MapSet.new(socket.assigns.recent_games, & &1.game_id)
        unique_new_games = Enum.reject(new_games, fn game -> MapSet.member?(existing_game_ids, game.game_id) end)

        # Append unique new games to existing list
        updated_games = socket.assigns.recent_games ++ unique_new_games

        # Update offset based on how many unique games we actually added
        new_offset = offset + length(unique_new_games)

        {:noreply,
         socket
         |> assign(:recent_games, updated_games)
         |> assign(:games_offset, new_offset)}
      end
    end
  end

  @impl true
  def handle_event("load-more", _params, socket) do
    # Fallback handler for load-more (same as load-more-games)
    handle_event("load-more-games", _params, socket)
  end

  @impl true
  def handle_event("stop_propagation", _params, socket) do
    # This event stops click propagation to prevent modal backdrop from closing
    {:noreply, socket}
  end

  @impl true
  def handle_info(:retry_init_onchain_game, socket) do
    # Retry game initialization after a failure
    user_id = socket.assigns.current_user.id
    wallet_address = socket.assigns.wallet_address

    {:noreply,
     socket
     |> start_async(:init_onchain_game, fn ->
       BuxBoosterOnchain.get_or_init_game(user_id, wallet_address)
     end)}
  end

  @impl true
  def handle_info(:reveal_flip_result, socket) do
    # Called after bet confirmation + minimum spin time
    # Push event to frontend to reveal the result
    if socket.assigns.game_state == :flipping and socket.assigns.bet_confirmed do
      socket = push_event(socket, "reveal_result", %{
        flip_index: socket.assigns.current_flip - 1,
        result: Enum.at(socket.assigns.results, socket.assigns.current_flip - 1) |> Atom.to_string()
      })

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:flip_complete, socket) do
    # After flip animation, show coin result for 1 second
    socket = assign(socket, game_state: :showing_result)

    # After 1 second showing coin result, move to pause state
    Process.send_after(self(), :after_result_shown, 1000)

    {:noreply, socket}
  end

  @impl true
  def handle_info(:after_result_shown, socket) do
    # Result has been shown for 1 second, now proceed immediately
    current_flip = socket.assigns.current_flip
    predictions = socket.assigns.predictions
    results = socket.assigns.results
    predictions_needed = get_predictions_needed(socket.assigns.selected_difficulty)
    mode = get_mode(socket.assigns.selected_difficulty)

    # Check if current prediction was correct
    current_prediction = Enum.at(predictions, current_flip - 1)
    current_result = Enum.at(results, current_flip - 1)
    correct = current_prediction == current_result

    # Proceed based on game mode
    case mode do
      :win_one ->
        # Win One mode: player wins if ANY flip is correct
        if correct do
          # Won! Show final result immediately
          send(self(), :show_final_result)
        else
          if current_flip >= predictions_needed do
            # Lost all flips - show final result
            send(self(), :show_final_result)
          else
            # More flips to go - continue to next flip
            send(self(), :next_flip)
          end
        end

      :win_all ->
        # Win All mode: player must win ALL flips
        if not correct do
          # Lost - show final result immediately
          send(self(), :show_final_result)
        else
          if current_flip >= predictions_needed do
            # Won all - show final result immediately
            send(self(), :show_final_result)
          else
            # More flips to go - start next flip immediately
            send(self(), :next_flip)
          end
        end
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info(:next_flip, socket) do
    # Start the next flip with incremented flip_id to force hook remount
    # For win_all mode (4x, 8x, 16x, 32x), double the current bet after each winning flip
    mode = get_mode(socket.assigns.selected_difficulty)
    new_current_bet = if mode == :win_all do
      socket.assigns.current_bet * 2
    else
      socket.assigns.current_bet
    end

    # Schedule reveal_result for this flip (3 second minimum spin time)
    Process.send_after(self(), :reveal_flip_result, 3000)

    {:noreply,
     socket
     |> assign(game_state: :flipping)
     |> assign(current_flip: socket.assigns.current_flip + 1)
     |> assign(flip_id: socket.assigns.flip_id + 1)
     |> assign(current_bet: new_current_bet)}
  end

  @impl true
  def handle_info(:show_final_result, socket) do
    predictions = socket.assigns.predictions
    results = socket.assigns.results
    current_flip = socket.assigns.current_flip
    user_id = socket.assigns.current_user.id
    token_type = socket.assigns.selected_token
    _mode = get_mode(socket.assigns.selected_difficulty)

    # For on-chain games, won/payout were already calculated in on_bet_placed
    won = socket.assigns.won
    payout = socket.assigns.payout

    # Save game result to local Mnesia tables for stats/history
    if won do
      save_game_result(socket, true, payout)
    else
      save_game_result(socket, false)
    end

    # Track game played event for notification triggers
    multiplier = get_multiplier_for_difficulty(socket.assigns.selected_difficulty)
    BlocksterV2.UserEvents.track(user_id, "game_played", %{
      token: to_string(token_type),
      result: if(won, do: "win", else: "loss"),
      multiplier: multiplier,
      bet_amount: socket.assigns.current_bet,
      payout: payout
    })

    # Refresh stats (recent_games will be updated via PubSub broadcast after settlement)
    user_stats = load_user_stats(user_id, token_type)

    # Generate confetti for wins
    confetti_pieces = if won, do: generate_confetti_data(100), else: []

    # Settle the bet on-chain in background (player already sees result)
    game_id = socket.assigns.onchain_game_id
    liveview_pid = self()  # Capture LiveView PID before spawning
    spawn(fn ->
      case BuxBoosterOnchain.settle_game(game_id) do
        {:ok, %{tx_hash: settlement_tx_hash, player_balance: _balance}} ->
          # Send settlement confirmation back to LiveView
          send(liveview_pid, {:settlement_complete, settlement_tx_hash})

        {:error, reason} ->
          Logger.error("[BuxBooster] Settlement failed: #{inspect(reason)}")
          send(liveview_pid, {:settlement_failed, reason})
      end
    end)

    # Push settlement event to frontend to update balance
    socket =
      socket
      |> assign(game_state: :result)
      |> assign(won: won)
      |> assign(payout: payout)
      |> assign(user_stats: user_stats)
      # Keep existing recent_games list - will be updated via PubSub after settlement
      |> assign(confetti_pieces: confetti_pieces)
      |> push_event("bet_settled", %{won: won, payout: payout})

    {:noreply, socket}
  end

  @impl true
  def handle_info({:settlement_complete, tx_hash}, socket) do
    user_id = socket.assigns.current_user.id
    wallet_address = socket.assigns.wallet_address
    game_id = socket.assigns.onchain_game_id

    # Sync balances from blockchain (async - will broadcast when complete)
    # This fetches latest on-chain balances including the payout and broadcasts to all LiveViews
    # Force bypasses dedup cooldown since balance MUST update after settlement
    BuxMinter.sync_user_balances_async(user_id, wallet_address, force: true)

    # Get the settled game and broadcast it to all /play pages for this user
    case :mnesia.dirty_read({:bux_booster_onchain_games, game_id}) do
      [record] when elem(record, 7) == :settled ->
        settled_game = %{
          game_id: elem(record, 1),
          token_type: elem(record, 9),
          bet_amount: elem(record, 11),
          multiplier: get_multiplier_for_difficulty(elem(record, 12)),
          predictions: elem(record, 13),
          results: elem(record, 14),
          won: elem(record, 15),
          payout: elem(record, 16),
          commitment_hash: elem(record, 5),
          commitment_tx: elem(record, 17),
          bet_tx: elem(record, 18),
          settlement_tx: elem(record, 19),
          server_seed: elem(record, 4),
          server_seed_hash: elem(record, 5),
          nonce: elem(record, 6)
        }

        # Broadcast to all /play pages for this user
        Phoenix.PubSub.broadcast(
          BlocksterV2.PubSub,
          "bux_booster_settlement:#{user_id}",
          {:new_settled_game, settled_game}
        )

      _ ->
        Logger.warning("[BuxBooster] Could not find settled game #{game_id} in Mnesia")
    end

    {:noreply, assign(socket, settlement_tx: tx_hash)}
  end

  @impl true
  def handle_info({:settlement_failed, reason}, socket) do
    Logger.error("[BuxBooster] Settlement failed: #{inspect(reason)}")
    # The game result is already shown - settlement failure is a backend issue
    # Player's tokens are still locked in contract until manual intervention
    {:noreply, assign(socket, error_message: "Settlement pending - please contact support")}
  end

  # Handle balance updates broadcast from BuxBalanceHook
  def handle_info({:bux_balance_updated, _new_balance}, socket) do
    # The aggregate balance is maintained in the header component, we don't need it here
    {:noreply, socket}
  end

  # Handle new settled game broadcast - prepend to recent games list
  def handle_info({:new_settled_game, settled_game}, socket) do
    recent_games = [settled_game | socket.assigns.recent_games]
    {:noreply, assign(socket, :recent_games, recent_games)}
  end

  # Handle token price updates from PriceTracker
  def handle_info({:token_prices_updated, prices}, socket) do
    rogue_price = case Map.get(prices, "ROGUE") do
      %{usd_price: price} -> price
      nil -> socket.assigns.rogue_usd_price
    end
    {:noreply, assign(socket, :rogue_usd_price, rogue_price)}
  end

  # Helper Functions

  defp get_multiplier(difficulty) do
    case Enum.find(@difficulty_options, fn opt -> opt.level == difficulty end) do
      nil -> 2
      opt -> opt.multiplier
    end
  end

  defp get_predictions_needed(difficulty) do
    case Enum.find(@difficulty_options, fn opt -> opt.level == difficulty end) do
      nil -> 1
      opt -> opt.predictions
    end
  end

  defp get_mode(difficulty) do
    case Enum.find(@difficulty_options, fn opt -> opt.level == difficulty end) do
      nil -> :win_all
      opt -> Map.get(opt, :mode, :win_all)
    end
  end

  # Dynamic coin sizing based on number of flips - bigger coins for fewer flips
  # Returns {outer_size, inner_size, emoji_size} for mobile and desktop
  defp get_coin_size_classes(num_flips) do
    case num_flips do
      1 -> %{outer: "w-20 h-20 sm:w-24 sm:h-24", inner: "w-14 h-14 sm:w-16 sm:h-16", emoji: "text-3xl sm:text-4xl"}
      2 -> %{outer: "w-18 h-18 sm:w-20 sm:h-20", inner: "w-12 h-12 sm:w-14 sm:h-14", emoji: "text-2xl sm:text-3xl"}
      3 -> %{outer: "w-16 h-16 sm:w-20 sm:h-20", inner: "w-11 h-11 sm:w-14 sm:h-14", emoji: "text-2xl sm:text-3xl"}
      4 -> %{outer: "w-14 h-14 sm:w-18 sm:h-18", inner: "w-10 h-10 sm:w-12 sm:h-12", emoji: "text-xl sm:text-2xl"}
      _ -> %{outer: "w-12 h-12 sm:w-16 sm:h-16", inner: "w-8 h-8 sm:w-10 sm:h-10", emoji: "text-lg sm:text-2xl"}
    end
  end

  # Same for prediction buttons in idle state
  defp get_prediction_size_classes(num_flips) do
    case num_flips do
      1 -> %{outer: "w-20 h-20 sm:w-20 sm:h-20", inner: "w-14 h-14 sm:w-14 sm:h-14", emoji: "text-3xl sm:text-3xl"}
      2 -> %{outer: "w-18 h-18 sm:w-18 sm:h-18", inner: "w-12 h-12 sm:w-12 sm:h-12", emoji: "text-2xl sm:text-2xl"}
      3 -> %{outer: "w-16 h-16 sm:w-16 sm:h-16", inner: "w-11 h-11 sm:w-10 sm:h-10", emoji: "text-2xl sm:text-2xl"}
      4 -> %{outer: "w-14 h-14 sm:w-16 sm:h-16", inner: "w-10 h-10 sm:w-10 sm:h-10", emoji: "text-xl sm:text-2xl"}
      _ -> %{outer: "w-12 h-12 sm:w-16 sm:h-16", inner: "w-8 h-8 sm:w-10 sm:h-10", emoji: "text-xl sm:text-2xl"}
    end
  end

  defp format_balance(amount) when is_float(amount) do
    amount
    |> :erlang.float_to_binary(decimals: 2)
    |> add_comma_delimiters()
  end

  defp format_balance(amount) when is_integer(amount) do
    (amount / 1)
    |> :erlang.float_to_binary(decimals: 2)
    |> add_comma_delimiters()
  end

  defp format_balance(_), do: "0.00"

  # Format USD value for display (always 2 decimal places)
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

  # Get ROGUE price from PriceTracker
  defp get_rogue_price do
    case PriceTracker.get_price("ROGUE") do
      {:ok, %{usd_price: price}} -> price
      {:error, _} -> nil
    end
  end

  defp add_comma_delimiters(number_string) do
    [integer_part, decimal_part] = String.split(number_string, ".")

    integer_with_commas =
      integer_part
      |> String.reverse()
      |> String.graphemes()
      |> Enum.chunk_every(3)
      |> Enum.map(&Enum.join/1)
      |> Enum.join(",")
      |> String.reverse()

    "#{integer_with_commas}.#{decimal_part}"
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

  defp format_profit(amount) when amount >= 0, do: "+#{format_balance(amount)}"
  defp format_profit(amount), do: format_balance(amount)

  defp calculate_win_rate(%{total_games: 0}), do: 0
  defp calculate_win_rate(%{total_games: total, total_wins: wins}) do
    Float.round(wins / total * 100, 1)
  end

  # Mnesia functions for game persistence

  defp save_game_result(socket, won, payout \\ 0) do
    user_id = socket.assigns.current_user.id
    token_type = socket.assigns.selected_token
    bet_amount = socket.assigns.bet_amount
    difficulty = socket.assigns.selected_difficulty
    multiplier = get_multiplier(difficulty)
    predictions = socket.assigns.predictions
    results = socket.assigns.results

    # For on-chain games, get the server seed from the Mnesia game record
    onchain_game_id = Map.get(socket.assigns, :onchain_game_id)
    {server_seed, server_seed_hash, nonce} = if onchain_game_id do
      case BuxBoosterOnchain.get_game(onchain_game_id) do
        {:ok, game} -> {game.server_seed, game.commitment_hash, game.nonce}
        _ -> {nil, socket.assigns.server_seed_hash, socket.assigns.nonce}
      end
    else
      {nil, socket.assigns.server_seed_hash, socket.assigns.nonce}
    end

    game_id = "#{user_id}_#{System.system_time(:millisecond)}"
    now = System.system_time(:second)

    # Save game record with provably fair fields
    game_record = {
      :bux_booster_games,
      game_id,
      user_id,
      token_type,
      bet_amount,
      difficulty,
      multiplier,
      predictions,
      results,
      won,
      payout,
      now,
      # Provably fair fields:
      server_seed,
      server_seed_hash,
      nonce
    }

    :mnesia.dirty_write(game_record)

    # Update user stats
    update_user_stats(user_id, token_type, bet_amount, won, payout)
  end

  defp update_user_stats(user_id, token_type, bet_amount, won, payout) do
    key = {user_id, token_type}
    now = System.system_time(:second)

    case :mnesia.dirty_read({:bux_booster_user_stats, key}) do
      [] ->
        # Create new stats record
        new_stats = {
          :bux_booster_user_stats,
          key,
          user_id,
          token_type,
          1,                                    # total_games
          if(won, do: 1, else: 0),              # total_wins
          if(won, do: 0, else: 1),              # total_losses
          bet_amount,                           # total_wagered
          if(won, do: payout, else: 0),         # total_won
          if(won, do: 0, else: bet_amount),     # total_lost
          if(won, do: payout, else: 0),         # biggest_win
          if(won, do: 0, else: bet_amount),     # biggest_loss
          if(won, do: 1, else: -1),             # current_streak
          if(won, do: 1, else: 0),              # best_streak
          if(won, do: 0, else: -1),             # worst_streak
          now                                   # updated_at
        }
        :mnesia.dirty_write(new_stats)

      [record] ->
        # Update existing stats
        total_games = elem(record, 4) + 1
        total_wins = elem(record, 5) + if(won, do: 1, else: 0)
        total_losses = elem(record, 6) + if(won, do: 0, else: 1)
        total_wagered = elem(record, 7) + bet_amount
        total_won = elem(record, 8) + if(won, do: payout, else: 0)
        total_lost = elem(record, 9) + if(won, do: 0, else: bet_amount)
        biggest_win = max(elem(record, 10), if(won, do: payout, else: 0))
        biggest_loss = max(elem(record, 11), if(won, do: 0, else: bet_amount))

        # Update streak
        current_streak = elem(record, 12)
        new_streak =
          cond do
            won and current_streak >= 0 -> current_streak + 1
            won -> 1
            not won and current_streak <= 0 -> current_streak - 1
            true -> -1
          end

        best_streak = max(elem(record, 13), new_streak)
        worst_streak = min(elem(record, 14), new_streak)

        updated_stats = {
          :bux_booster_user_stats,
          key,
          user_id,
          token_type,
          total_games,
          total_wins,
          total_losses,
          total_wagered,
          total_won,
          total_lost,
          biggest_win,
          biggest_loss,
          new_streak,
          best_streak,
          worst_streak,
          now
        }
        :mnesia.dirty_write(updated_stats)
    end
  end

  defp load_user_stats(user_id, token_type \\ "BUX") do
    key = {user_id, token_type}

    case :mnesia.dirty_read({:bux_booster_user_stats, key}) do
      [] ->
        nil

      [record] ->
        %{
          total_games: elem(record, 4),
          total_wins: elem(record, 5),
          total_losses: elem(record, 6),
          total_wagered: elem(record, 7),
          total_won: elem(record, 8),
          total_lost: elem(record, 9),
          biggest_win: elem(record, 10),
          biggest_loss: elem(record, 11),
          current_streak: elem(record, 12),
          best_streak: elem(record, 13),
          worst_streak: elem(record, 14)
        }
    end
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  defp load_recent_games(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)
    offset = Keyword.get(opts, :offset, 0)

    # Query recent on-chain games from Mnesia using dirty index read
    # Get settled games with pagination
    onchain_games = :mnesia.dirty_index_read(:bux_booster_onchain_games, user_id, :user_id)
    |> Enum.filter(fn record -> elem(record, 7) == :settled end)  # status field
    |> Enum.sort_by(fn record -> elem(record, 21) end, :desc)  # settled_at field
    |> Enum.drop(offset)  # Skip offset games
    |> Enum.take(limit)  # Take limit games
    |> Enum.map(fn record ->
      %{
        game_id: elem(record, 1),
        token_type: elem(record, 9),  # token field
        bet_amount: elem(record, 11),  # bet_amount field
        multiplier: get_multiplier_for_difficulty(elem(record, 12)),  # difficulty field
        predictions: elem(record, 13),  # predictions field
        results: elem(record, 14),  # results field
        won: elem(record, 15),  # won field
        payout: elem(record, 16),  # payout field
        commitment_hash: elem(record, 5),  # commitment_hash field
        commitment_tx: elem(record, 17),  # commitment_tx field
        bet_tx: elem(record, 18),  # bet_tx field
        settlement_tx: elem(record, 19),  # settlement_tx field
        # Provably fair fields
        server_seed: elem(record, 4),  # server_seed field
        server_seed_hash: elem(record, 5),  # commitment_hash is the server_seed_hash
        nonce: elem(record, 6)  # nonce field
      }
    end)

    onchain_games
  rescue
    _ -> []
  catch
    :exit, _ -> []
  end

  # Helper to get multiplier from difficulty level
  defp get_multiplier_for_difficulty(difficulty) do
    case Enum.find(@difficulty_options, fn opt -> opt.level == difficulty end) do
      nil -> 1.0
      opt -> opt.multiplier
    end
  end

  # Safe tuple element access for backwards compatibility with old records
  defp safe_elem(tuple, index) when tuple_size(tuple) > index, do: elem(tuple, index)
  defp safe_elem(_tuple, _index), do: nil

  # Calculate max bet based on house balance and difficulty
  # Fetch house balance and calculate max bet asynchronously
  defp fetch_house_balance_async(token, difficulty_level) do
    # ROGUE uses ROGUEBankroll contract, other tokens use BuxBoosterGame
    case token do
      "ROGUE" ->
        case BuxMinter.get_rogue_house_balance() do
          {:ok, balance} ->
            max_bet = calculate_max_bet(balance, difficulty_level, @difficulty_options)
            {balance, max_bet}

          {:error, reason} ->
            Logger.warning("[BuxBooster] Failed to fetch ROGUE house balance: #{inspect(reason)}")
            {0.0, 0}
        end

      _ ->
        case BuxMinter.get_house_balance(token) do
          {:ok, balance} ->
            max_bet = calculate_max_bet(balance, difficulty_level, @difficulty_options)
            {balance, max_bet}

          {:error, reason} ->
            Logger.warning("[BuxBooster] Failed to fetch house balance for #{token}: #{inspect(reason)}")
            {0.0, 0}
        end
    end
  end

  # Formula: maxBet = (houseBalance * 0.001 * 20000) / multiplier
  # This ensures max payout is consistent at 0.2% of house balance
  defp calculate_max_bet(house_balance, difficulty_level, difficulty_options) do
    difficulty = Enum.find(difficulty_options, &(&1.level == difficulty_level))

    if difficulty do
      # Multiplier is already in display format (e.g., 1.98, 3.96)
      # Convert to basis points for calculation (multiply by 10000)
      multiplier_bp = trunc(difficulty.multiplier * 10000)

      # 0.1% of house balance
      base_max_bet = house_balance * 0.001

      # Scale by multiplier to get consistent max payout
      max_bet = (base_max_bet * 20000) / multiplier_bp

      # Round down to nearest integer (bets must be whole tokens)
      trunc(max_bet)
    else
      0
    end
  end

  # Get user's next nonce (game counter) for provably fair system
  defp get_user_nonce(user_id) do
    # Count existing games for this user to determine next nonce
    games = :mnesia.dirty_index_read(:bux_booster_games, user_id, :user_id)
    length(games)
  rescue
    _ -> 0
  catch
    :exit, _ -> 0
  end

  # Load a specific game for fairness verification
  defp load_game_for_fairness(game_id) do
    case :mnesia.dirty_read({:bux_booster_games, game_id}) do
      [] -> nil
      [record] ->
        %{
          game_id: elem(record, 1),
          user_id: elem(record, 2),
          token: elem(record, 3),
          bet_amount: elem(record, 4),
          difficulty: elem(record, 5),
          predictions: elem(record, 7),
          results: elem(record, 8),
          won: elem(record, 9),
          server_seed: safe_elem(record, 12),
          server_seed_hash: safe_elem(record, 13),
          nonce: safe_elem(record, 14)
        }
    end
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  @confetti_emojis ["❤️", "🧡", "💛", "💚", "💙", "💜", "🩷", "⭐", "🌟", "✨", "⚡", "🌈", "🍀", "💎", "🎉", "🎊", "💫", "🔥", "💖", "💝"]

  defp generate_confetti_data(count) do
    Enum.map(1..count, fn i ->
      %{
        id: i,
        x_start: 40 + :rand.uniform(20),
        x_end: :rand.uniform(100),
        x_drift: :rand.uniform(60) - 30,
        rotation: :rand.uniform(720) - 360,
        delay: rem(i * 23, 400),
        duration: 4000 + :rand.uniform(2000),
        emoji: Enum.at(@confetti_emojis, rem(i + :rand.uniform(20), length(@confetti_emojis)))
      }
    end)
  end
end
