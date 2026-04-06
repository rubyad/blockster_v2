defmodule BlocksterV2Web.CoinFlipLive do
  use BlocksterV2Web, :live_view
  require Logger

  alias BlocksterV2.EngagementTracker
  alias BlocksterV2.ProvablyFair
  alias BlocksterV2.CoinFlipGame
  alias BlocksterV2.BuxMinter

  import BlocksterV2Web.PoolComponents, only: [coin_flip_fairness_modal: 1]

  # Difficulty levels with house edge built into multipliers
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
    # SOL + BUX only (no ROGUE)
    tokens = ["SOL", "BUX"]

    if current_user do
      wallet_address = current_user.wallet_address

      # Sync Solana balances on connected mount
      if wallet_address != nil and connected?(socket) do
        BuxMinter.sync_user_balances_async(current_user.id, wallet_address)
      end

      # Get balances from Mnesia
      sol_balance = EngagementTracker.get_user_sol_balance(current_user.id)
      bux_balance = EngagementTracker.get_user_solana_bux_balance(current_user.id)
      balances = %{"BUX" => bux_balance, "SOL" => sol_balance}

      # Initialize game on connected mount only (LiveView mounts twice)
      socket = if wallet_address != nil and connected?(socket) do
        Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "bux_balance:#{current_user.id}")
        Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "coin_flip_settlement:#{current_user.id}")

        # Check for expired bets periodically (every 30s)
        Process.send_after(self(), :check_expired_bets, 1000)

        socket
        |> assign(:onchain_ready, false)
        |> assign(:wallet_address, wallet_address)
        |> assign(:onchain_initializing, true)
        |> assign(:init_retry_count, 0)
        |> start_async(:init_game, fn ->
          CoinFlipGame.get_or_init_game(current_user.id, wallet_address)
        end)
      else
        socket
        |> assign(:onchain_ready, false)
        |> assign(:wallet_address, wallet_address)
        |> assign(:onchain_initializing, false)
        |> assign(:init_retry_count, 0)
      end

      error_msg = if wallet_address, do: nil, else: "No wallet connected"

      socket =
        socket
        |> assign(page_title: "Coin Flip")
        |> assign(current_user: current_user)
        |> assign(balances: balances)
        |> assign(tokens: tokens)
        |> assign(difficulty_options: @difficulty_options)
        |> assign(selected_token: "SOL")
        |> assign(header_token: "SOL")
        |> assign(selected_difficulty: 1)
        |> assign(bet_amount: default_bet_amount(balances, "SOL"))
        |> assign(current_bet: default_bet_amount(balances, "SOL"))
        |> assign(house_balance: 0.0)
        |> assign(max_bet: 0.0)
        |> assign(predictions: [nil])
        |> assign(results: [])
        |> assign(game_state: :idle)
        |> assign(current_flip: 0)
        |> assign(won: nil)
        |> assign(payout: 0)
        |> assign(error_message: error_msg)
        |> assign(settlement_status: nil)
        |> assign(has_expired_bet: false)
        |> assign(show_token_dropdown: false)
        |> assign(show_provably_fair: false)
        |> assign(flip_id: 0)
        |> assign(confetti_pieces: [])
        |> assign(recent_games: [])
        |> assign(games_offset: 0)
        |> assign(games_loading: connected?(socket))
        |> assign(user_stats: load_user_stats(current_user.id))
        |> assign(server_seed: nil)
        |> assign(server_seed_hash: nil)
        |> assign(nonce: 0)
        |> assign(show_fairness_modal: false)
        |> assign(fairness_game: nil)
        |> assign(bet_sig: nil)
        |> assign(settlement_sig: nil)
        |> assign(next_game_session: nil)

      socket = if connected?(socket) do
        user_id = current_user.id
        socket
        |> start_async(:fetch_house_balance, fn -> fetch_house_balance_async("SOL", 1) end)
        |> start_async(:load_recent_games, fn -> load_recent_games(user_id, limit: 30) end)
      else
        socket
      end

      {:ok, socket}
    else
      # Not logged in
      balances = %{"BUX" => 0, "SOL" => 0}

      socket =
        socket
        |> assign(page_title: "Coin Flip")
        |> assign(current_user: nil)
        |> assign(balances: balances)
        |> assign(tokens: tokens)
        |> assign(difficulty_options: @difficulty_options)
        |> assign(selected_token: "SOL")
        |> assign(header_token: "SOL")
        |> assign(selected_difficulty: 1)
        |> assign(bet_amount: default_bet_amount(balances, "SOL"))
        |> assign(current_bet: default_bet_amount(balances, "SOL"))
        |> assign(house_balance: 0.0)
        |> assign(max_bet: 0.0)
        |> assign(predictions: [nil])
        |> assign(results: [])
        |> assign(game_state: :idle)
        |> assign(current_flip: 0)
        |> assign(won: nil)
        |> assign(payout: 0)
        |> assign(error_message: nil)
        |> assign(settlement_status: nil)
        |> assign(has_expired_bet: false)
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
        |> assign(bet_sig: nil)
        |> assign(settlement_sig: nil)
        |> assign(next_game_session: nil)
        |> start_async(:fetch_house_balance, fn -> fetch_house_balance_async("SOL", 1) end)

      {:ok, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="coin-flip-game"
      class="min-h-screen bg-gray-50"
      phx-hook="CoinFlipSolana"
      data-game-id={assigns[:onchain_game_id]}
      data-commitment-hash={assigns[:commitment_hash]}
    >
      <div class="max-w-2xl mx-auto px-3 sm:px-4 pt-6 sm:pt-24 pb-8">
        <!-- Main Game Area -->
        <div class="bg-white rounded-2xl shadow-sm border border-gray-200 h-[540px] sm:h-[580px] flex flex-col overflow-hidden">
          <!-- Difficulty Tabs -->
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

          <!-- Game Content Area -->
          <div class="flex-1 relative min-h-0">
            <div class="absolute inset-0 p-3 sm:p-6 flex flex-col overflow-y-auto">
            <%= if @game_state == :idle do %>
              <!-- Bet Stake with Token Dropdown -->
              <div class="mb-3 sm:mb-4">
                <label class="block text-base sm:text-lg font-bold text-gray-900 mb-1 sm:mb-2">Bet Stake</label>
                <div class="flex gap-1.5 sm:gap-2">
                  <div class="flex-1 relative min-w-0">
                    <input
                      type="text"
                      inputmode="decimal"
                      value={format_bet_amount(@bet_amount)}
                      phx-keyup="update_bet_amount"
                      phx-debounce="100"
                      autocomplete="off"
                      class="w-full bg-white border border-gray-300 rounded-lg pl-3 sm:pl-4 py-2 sm:py-3 text-gray-900 text-base sm:text-lg font-medium focus:outline-none focus:border-purple-500 focus:ring-1 focus:ring-purple-500 pr-20 sm:pr-24 [appearance:textfield] [&::-webkit-outer-spin-button]:appearance-none [&::-webkit-inner-spin-button]:appearance-none"
                    />
                    <div class="absolute right-2 top-1/2 -translate-y-1/2 flex items-center gap-1">
                      <button type="button" phx-click="halve_bet" class="px-1.5 sm:px-2 py-1 bg-gray-200 text-gray-700 rounded text-xs sm:text-sm font-medium hover:bg-gray-300 transition-all cursor-pointer">½</button>
                      <button type="button" phx-click="double_bet" class="px-1.5 sm:px-2 py-1 bg-gray-200 text-gray-700 rounded text-xs sm:text-sm font-medium hover:bg-gray-300 transition-all cursor-pointer">2×</button>
                    </div>
                  </div>
                  <!-- Token Dropdown -->
                  <div class="relative flex-shrink-0" id="token-dropdown-wrapper" phx-click-away="hide_token_dropdown">
                    <button
                      type="button"
                      phx-click="toggle_token_dropdown"
                      class="h-full px-2 sm:px-4 bg-gray-100 border border-gray-300 rounded-lg flex items-center gap-1 sm:gap-2 hover:bg-gray-200 transition-all cursor-pointer"
                    >
                      <span class="font-medium text-gray-900 text-sm sm:text-base"><%= @selected_token %></span>
                      <svg class="w-3 sm:w-4 h-3 sm:h-4 text-gray-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
                      </svg>
                    </button>
                    <%= if @show_token_dropdown do %>
                      <div class="absolute right-0 top-full mt-1 bg-white border border-gray-200 rounded-lg shadow-lg z-50 w-max min-w-[160px]">
                        <%= for token <- @tokens do %>
                          <button
                            type="button"
                            phx-click="select_token"
                            phx-value-token={token}
                            class={"w-full px-4 py-3 flex items-center gap-3 hover:bg-gray-50 cursor-pointer first:rounded-t-lg last:rounded-b-lg #{if @selected_token == token, do: "bg-gray-100"}"}
                          >
                            <span class={"font-medium flex-1 text-left #{if @selected_token == token, do: "text-gray-900", else: "text-gray-900"}"}><%= token %></span>
                            <span class="text-gray-500 text-sm"><%= format_balance(Map.get(@balances, token, 0)) %></span>
                          </button>
                        <% end %>
                      </div>
                    <% end %>
                  </div>
                  <!-- Max button -->
                  <button
                    type="button"
                    phx-click="set_max_bet"
                    class="hidden sm:flex px-4 py-2 bg-gray-100 text-gray-700 rounded-lg hover:bg-gray-200 transition-all cursor-pointer flex-col items-center flex-shrink-0"
                    title={"Max bet: #{format_bet_amount(@max_bet)} #{@selected_token}"}
                  >
                    <span class="text-xs text-gray-500 font-normal">Max</span>
                    <span class="text-sm font-medium"><%= format_bet_amount(@max_bet) %></span>
                  </button>
                </div>
                <!-- Preset stake buttons -->
                <div class="flex flex-wrap gap-1 mt-1.5">
                  <%= for preset <- stake_presets(@selected_token) do %>
                    <button
                      type="button"
                      phx-click="set_preset"
                      phx-value-amount={preset}
                      class={"px-2 sm:px-2.5 py-1 rounded-md text-[11px] sm:text-xs font-medium transition-all cursor-pointer #{if @bet_amount == preset, do: "bg-gray-900 text-white", else: "bg-gray-100 text-gray-700 hover:bg-gray-200"}"}
                    >
                      <%= format_bet_amount(preset) %>
                    </button>
                  <% end %>
                  <button
                    type="button"
                    phx-click="set_max_bet"
                    class={"sm:hidden px-2 sm:px-2.5 py-1 rounded-md text-[11px] sm:text-xs font-medium transition-all cursor-pointer #{if @bet_amount == @max_bet, do: "bg-gray-900 text-white", else: "bg-gray-100 text-gray-700 hover:bg-gray-200"}"}
                  >
                    Max (<%= format_bet_amount(@max_bet) %>)
                  </button>
                </div>
                <!-- Balance info -->
                <div class="mt-1.5 sm:mt-2">
                  <div class="flex items-center justify-between text-[10px] sm:text-sm">
                    <div class="text-gray-500">
                      <span class="flex items-center gap-0.5 sm:gap-1">
                        <%= format_balance(Map.get(@balances, @selected_token, 0)) %> <%= @selected_token %>
                      </span>
                    </div>
                    <.link navigate={~p"/pool/#{String.downcase(@selected_token)}"} class="text-gray-400 text-[10px] sm:text-xs hover:text-gray-600 transition-colors cursor-pointer">
                      House: <%= format_balance(@house_balance) %> <%= @selected_token %> ↗
                    </.link>
                  </div>
                </div>
              </div>

              <!-- Potential Profit -->
              <div class="bg-green-50 rounded-xl p-2 sm:p-3 mb-2 sm:mb-3 border border-green-200">
                <div class="flex items-center justify-between">
                  <span class="text-gray-700 text-xs sm:text-sm">Potential Profit:</span>
                  <span class="text-base sm:text-xl font-bold text-green-600">
                    +<%= format_balance(@bet_amount * get_multiplier(@selected_difficulty) - @bet_amount) %> <%= @selected_token %>
                  </span>
                </div>
              </div>

              <!-- Error Message -->
              <%= if @error_message do %>
                <div class="bg-red-50 border border-red-300 rounded-lg p-2 sm:p-3 mb-3 sm:mb-4 text-red-700 text-xs sm:text-sm">
                  <%= @error_message %>
                </div>
              <% end %>

              <!-- Prediction Selection -->
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
                    <button type="button" phx-click="toggle_provably_fair" class="text-xs text-gray-500 cursor-pointer hover:text-gray-700 flex items-center gap-1">
                      <svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
                      </svg>
                      Provably Fair
                    </button>
                    <%= if @show_provably_fair do %>
                      <div phx-click-away="close_provably_fair" class="absolute right-0 top-full mt-1 z-50 w-[calc(100vw-24px)] sm:w-80 max-w-80 bg-white rounded-lg p-2 sm:p-3 border border-gray-200 shadow-lg text-left overflow-hidden">
                        <p class="text-[10px] sm:text-xs text-gray-600 mb-2">
                          This hash commits the server to a result BEFORE you place your bet.
                        </p>
                        <div class="flex items-start gap-2 overflow-hidden">
                          <%= if @current_user do %>
                            <%= if @commitment_sig do %>
                              <a href={"https://solscan.io/tx/#{@commitment_sig}?cluster=devnet"} target="_blank" class="text-xs font-mono bg-gray-50 px-2 py-1.5 rounded border border-gray-200 text-blue-600 hover:text-blue-800 hover:underline cursor-pointer overflow-wrap-anywhere block" style="word-break: break-all;">
                                <%= @server_seed_hash %>
                              </a>
                            <% else %>
                              <code class="text-xs font-mono bg-gray-50 px-2 py-1.5 rounded border border-gray-200 text-gray-700 overflow-wrap-anywhere" style="word-break: break-all;">
                                <%= @server_seed_hash %>
                              </code>
                            <% end %>
                            <%= if @server_seed_hash do %>
                              <button type="button" id="copy-server-hash" phx-hook="CopyToClipboard" data-copy-text={@server_seed_hash}
                                class="shrink-0 p-1.5 text-gray-400 hover:text-gray-600 hover:bg-gray-100 rounded cursor-pointer transition-colors" title="Copy hash">
                                <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z" />
                                </svg>
                              </button>
                            <% end %>
                          <% else %>
                            <code class="text-xs font-mono bg-gray-50 px-2 py-1.5 rounded border border-gray-200 text-gray-500">
                              &lt;connect wallet to see commitment hash&gt;
                            </code>
                          <% end %>
                        </div>
                        <p class="text-xs text-gray-400 mt-2">Game #<%= @nonce %></p>
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
              <div class="mt-2 sm:mt-3 pb-3 sm:pb-4">
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
                        <div class={"#{sizes.outer} mx-auto rounded-full flex items-center justify-center mb-1 #{if Enum.at(@predictions, i - 1) == :heads, do: "casino-chip-heads", else: "casino-chip-tails"}"}>
                          <div class={"#{sizes.inner} rounded-full flex items-center justify-center border-2 border-white shadow-inner #{if Enum.at(@predictions, i - 1) == :heads, do: "bg-coin-heads", else: "bg-gray-700"}"}>
                            <span class={sizes.emoji}><%= if Enum.at(@predictions, i - 1) == :heads, do: "🚀", else: "💩" %></span>
                          </div>
                        </div>
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

                <!-- Bet Amount Display -->
                <%= if @game_state in [:flipping, :showing_result] do %>
                  <div class="mb-4 sm:mb-6 text-center">
                    <p class="text-gray-500 text-xs sm:text-sm">Bet</p>
                    <p class="text-lg sm:text-xl font-bold text-gray-900 flex items-center justify-center gap-1 sm:gap-2">
                      <span><%= format_balance(@current_bet) %> <%= @selected_token %></span>
                    </p>
                  </div>
                <% end %>

                <%= if @game_state == :awaiting_tx do %>
                  <div class="mb-4 sm:mb-6 text-center">
                    <div class="w-16 h-16 sm:w-24 sm:h-24 mx-auto rounded-full flex items-center justify-center bg-purple-100 animate-pulse mb-3 sm:mb-4">
                      <svg class="w-8 h-8 sm:w-12 sm:h-12 text-purple-600 animate-spin" fill="none" viewBox="0 0 24 24">
                        <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                        <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                      </svg>
                    </div>
                    <h3 class="text-base sm:text-lg font-bold text-gray-900 mb-1 sm:mb-2">Confirm Transaction</h3>
                    <p class="text-xs sm:text-sm text-gray-600 mb-3 sm:mb-4">Please approve the transaction in your wallet</p>
                  </div>
                <% end %>

                <%= if @game_state == :flipping do %>
                  <div class="mb-4 sm:mb-6" id={"coin-flip-#{@flip_id}"} phx-hook="CoinFlip" data-flip-index={@current_flip}>
                    <div class={"coin-container mx-auto #{sizes.outer} relative perspective-1000"}>
                      <div class="coin w-full h-full absolute animate-flip-continuous">
                        <div class="coin-face coin-heads absolute w-full h-full rounded-full flex items-center justify-center backface-hidden casino-chip-heads">
                          <div class={"#{sizes.inner} rounded-full bg-coin-heads flex items-center justify-center border-2 border-white shadow-inner"}>
                            <span class={sizes.emoji}>🚀</span>
                          </div>
                        </div>
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
                  <div class="mb-4 sm:mb-6">
                    <div class={"coin-container mx-auto #{sizes.outer} relative perspective-1000"}>
                      <div class="w-full h-full absolute" style={"transform-style: preserve-3d; transform: rotateY(#{if Enum.at(@results, @current_flip - 1) == :heads, do: "0deg", else: "180deg"})"}>
                        <div class="coin-face coin-heads absolute w-full h-full rounded-full flex items-center justify-center backface-hidden casino-chip-heads">
                          <div class={"#{sizes.inner} rounded-full bg-coin-heads flex items-center justify-center border-2 border-white shadow-inner"}>
                            <span class={sizes.emoji}>🚀</span>
                          </div>
                        </div>
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
                  <%= if @won and length(@confetti_pieces) > 0 do %>
                    <div class="confetti-fullpage fixed inset-0 pointer-events-none z-50 overflow-hidden">
                      <%= for piece <- @confetti_pieces do %>
                        <div class="confetti-emoji" style={"--x-start: #{piece.x_start}%; --x-end: #{piece.x_end}%; --x-drift: #{piece.x_drift}vw; --rotation: #{piece.rotation}deg; --delay: #{piece.delay}ms; --duration: #{piece.duration}ms;"}><%= piece.emoji %></div>
                      <% end %>
                    </div>
                  <% end %>

                  <div class="mb-4 sm:mb-6 relative">
                    <%= if @won do %>
                      <div class="win-celebration win-shake flex items-center justify-center gap-2 sm:gap-4">
                        <div class="animate-bounce text-3xl sm:text-[50px] leading-none">🎉</div>
                        <div class="text-center">
                          <h2 class="text-xl sm:text-3xl font-bold text-green-600 mb-1 animate-pulse">YOU WON!</h2>
                          <p class="text-lg sm:text-2xl text-gray-900 flex items-center justify-center gap-1 sm:gap-2">
                            <span class="text-green-600 font-bold"><%= format_balance(@payout) %></span>
                            <span><%= @selected_token %></span>
                          </p>
                        </div>
                        <div class="animate-bounce text-3xl sm:text-[50px] leading-none">🎉</div>
                      </div>
                    <% else %>
                      <div class="text-center">
                        <p class="text-lg sm:text-xl text-gray-900 flex items-center justify-center gap-1 sm:gap-2">
                          <span class="text-red-600 font-bold">-<%= format_balance(@bet_amount) %></span>
                          <span><%= @selected_token %></span>
                        </p>
                      </div>
                    <% end %>
                  </div>

                  <%!-- Settlement status --%>
                  <%= case @settlement_status do %>
                    <% :pending -> %>
                      <div class="text-center mb-3">
                        <div class="inline-flex items-center gap-2 px-4 py-2 bg-gray-900 rounded-lg text-xs font-haas_medium_65 text-white shadow-sm">
                          <svg class="w-3.5 h-3.5 text-[#CAFC00] animate-spin" fill="none" viewBox="0 0 24 24"><circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle><path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"></path></svg>
                          Settling on-chain...
                        </div>
                      </div>
                    <% :settled -> %>
                      <div class="text-center mb-3">
                        <a
                          href={"https://solscan.io/tx/#{assigns[:settlement_sig]}?cluster=devnet"}
                          target="_blank"
                          class="inline-flex items-center gap-2 px-4 py-2 bg-gray-900 rounded-lg text-xs font-haas_medium_65 text-white hover:bg-gray-800 transition-all cursor-pointer shadow-sm"
                        >
                          <svg class="w-3.5 h-3.5 text-[#CAFC00]" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M5 13l4 4L19 7" /></svg>
                          Settled on-chain
                          <svg class="w-3 h-3 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" /></svg>
                        </a>
                      </div>
                    <% :failed -> %>
                      <div class="text-center mb-3">
                        <div class="inline-flex flex-col items-center gap-1.5 px-4 py-2.5 bg-gray-900 rounded-lg text-xs font-haas_medium_65 text-white shadow-sm">
                          <div class="flex items-center gap-2">
                            <svg class="w-3.5 h-3.5 text-amber-400 animate-spin" fill="none" viewBox="0 0 24 24"><circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle><path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"></path></svg>
                            <span>Settlement failed — auto-retrying every 60s</span>
                          </div>
                          <span class="text-[10px] text-gray-400 font-haas_roman_55">Bet is reclaimable after 5 min if settlement keeps failing. Refresh to reclaim.</span>
                        </div>
                      </div>
                    <% _ -> %><% # nil — before settlement starts %>
                  <% end %>

                  <div class="mt-auto flex flex-col items-center gap-2">
                    <button type="button" phx-click="reset_game" class="px-6 sm:px-8 py-2.5 sm:py-3 bg-black text-white font-bold text-sm sm:text-base rounded-xl hover:bg-gray-800 transition-all cursor-pointer animate-fade-in">
                      Play Again
                    </button>
                    <%= if @onchain_game_id do %>
                      <button type="button" phx-click="show_fairness_modal" phx-value-game-id={@onchain_game_id} class="text-xs text-gray-500 hover:text-gray-700 flex items-center gap-1 cursor-pointer">
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

        <!-- Recent Games -->
        <div class="mt-4 sm:mt-6">
          <div class="bg-white rounded-xl p-3 sm:p-4 shadow-sm border border-gray-200">
            <h3 class="text-xs sm:text-sm font-bold text-gray-900 mb-2 sm:mb-3">Coin Flip Games</h3>
            <%= if assigns[:games_loading] do %>
              <div class="text-center py-4 text-gray-500 text-xs sm:text-sm">Loading games...</div>
            <% end %>
            <%= if length(@recent_games) > 0 do %>
              <div id="recent-games-scroll" class="overflow-x-auto overflow-y-auto max-h-72 sm:max-h-96 relative" phx-hook="InfiniteScroll">
                <table class="w-full text-[10px] sm:text-xs min-w-[600px]">
                  <thead class="sticky top-0 z-20 bg-white">
                    <tr class="border-b-2 border-gray-200 bg-white">
                      <th class="text-left py-1.5 sm:py-2 px-1.5 sm:px-2 text-gray-600 font-medium bg-white">ID</th>
                      <th class="text-left py-1.5 sm:py-2 px-1.5 sm:px-2 text-gray-600 font-medium bg-white">Bet</th>
                      <th class="text-left py-1.5 sm:py-2 px-1.5 sm:px-2 text-gray-600 font-medium bg-white">Pred</th>
                      <th class="text-left py-1.5 sm:py-2 px-1.5 sm:px-2 text-gray-600 font-medium bg-white">Result</th>
                      <th class="text-left py-1.5 sm:py-2 px-1.5 sm:px-2 text-gray-600 font-medium bg-white">Odds</th>
                      <th class="text-left py-1.5 sm:py-2 px-1.5 sm:px-2 text-gray-600 font-medium bg-white">W/L</th>
                      <th class="text-left py-1.5 sm:py-2 px-1.5 sm:px-2 text-gray-600 font-medium bg-white">P/L</th>
                      <th class="text-left py-1.5 sm:py-2 px-1.5 sm:px-2 text-gray-600 font-medium bg-white">Verify</th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for game <- @recent_games do %>
                      <tr id={"game-#{game.game_id}"} class={"border-b border-gray-100 #{if game.won, do: "bg-green-50/30", else: "bg-red-50/30"}"}>
                        <td class="py-1.5 sm:py-2 px-1.5 sm:px-2">
                          <%= if game.commitment_sig do %>
                            <a href={"https://solscan.io/tx/#{game.commitment_sig}?cluster=devnet"} target="_blank" class="font-mono text-gray-500 hover:text-gray-700 hover:underline cursor-pointer" title="View commitment tx">#<%= game.nonce %></a>
                          <% else %>
                            <span class="font-mono text-gray-500">#<%= game.nonce %></span>
                          <% end %>
                        </td>
                        <td class="py-1.5 sm:py-2 px-1.5 sm:px-2">
                          <%= if game.bet_sig do %>
                            <a href={"https://solscan.io/tx/#{game.bet_sig}?cluster=devnet"} target="_blank" class="text-gray-900 hover:text-gray-600 hover:underline cursor-pointer" title="View bet tx"><%= format_balance(game.bet_amount) %> <%= game.vault_type %></a>
                          <% else %>
                            <span class="text-gray-900"><%= format_balance(game.bet_amount) %> <%= game.vault_type %></span>
                          <% end %>
                        </td>
                        <td class="py-1.5 sm:py-2 px-1.5 sm:px-2">
                          <div class="flex gap-0">
                            <%= for pred <- (game.predictions || []) do %>
                              <span class="text-[10px] sm:text-xs"><%= if pred == :heads, do: "🚀", else: "💩" %></span>
                            <% end %>
                          </div>
                        </td>
                        <td class="py-1.5 sm:py-2 px-1.5 sm:px-2">
                          <div class="flex gap-0">
                            <%= for result <- (game.results || []) do %>
                              <span class="text-[10px] sm:text-xs"><%= if result == :heads, do: "🚀", else: "💩" %></span>
                            <% end %>
                          </div>
                        </td>
                        <td class="py-1.5 sm:py-2 px-1.5 sm:px-2 text-gray-900 font-medium"><%= game.multiplier %>x</td>
                        <td class="py-1.5 sm:py-2 px-1.5 sm:px-2">
                          <%= if game.won do %>
                            <span class="text-green-600 font-medium">W</span>
                          <% else %>
                            <span class="text-red-600 font-medium">L</span>
                          <% end %>
                        </td>
                        <td class="py-1.5 sm:py-2 px-1.5 sm:px-2">
                          <%= if game.settlement_sig do %>
                            <a href={"https://solscan.io/tx/#{game.settlement_sig}?cluster=devnet"} target="_blank" class={"font-medium hover:underline cursor-pointer #{if game.won, do: "text-green-600", else: "text-red-600"}"} title="View settlement tx">
                              <%= if game.won, do: "+#{format_balance(game.payout - game.bet_amount)}", else: "-#{format_balance(game.bet_amount)}" %>
                            </a>
                          <% else %>
                            <%= if game.won do %>
                              <span class="text-green-600 font-medium">+<%= format_balance(game.payout - game.bet_amount) %></span>
                            <% else %>
                              <span class="text-red-600 font-medium">-<%= format_balance(game.bet_amount) %></span>
                            <% end %>
                          <% end %>
                        </td>
                        <td class="py-1.5 sm:py-2 px-1.5 sm:px-2">
                          <%= if game.server_seed && game.commitment_hash && game.nonce do %>
                            <button type="button" phx-click="show_fairness_modal" phx-value-game-id={game.game_id} class="text-blue-500 hover:underline cursor-pointer">✓</button>
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

    <.coin_flip_fairness_modal show={@show_fairness_modal} fairness_game={@fairness_game} />

    <style>
      .perspective-1000 { perspective: 1000px; }
      .backface-hidden { backface-visibility: hidden; }
      .rotate-y-180 { transform: rotateY(180deg); }
      @keyframes flip-heads { 0% { transform: rotateY(0deg); } 100% { transform: rotateY(1800deg); } }
      @keyframes flip-tails { 0% { transform: rotateY(0deg); } 100% { transform: rotateY(1980deg); } }
      .animate-flip-heads { animation: flip-heads 3s ease-out forwards; transform-style: preserve-3d; }
      .animate-flip-tails { animation: flip-tails 3s ease-out forwards; transform-style: preserve-3d; }
      .confetti-fullpage { perspective: 1000px; }
      .confetti-emoji { position: absolute; font-size: 24px; left: var(--x-start); bottom: 40%; animation: confetti-burst var(--duration, 3s) cubic-bezier(0.25, 0.46, 0.45, 0.94) forwards; animation-delay: var(--delay, 0ms); opacity: 0; }
      @keyframes confetti-burst { 0% { opacity: 1; transform: translateY(0) translateX(0) rotate(0deg) scale(0.5); } 15% { opacity: 1; transform: translateY(-50vh) translateX(var(--x-drift)) rotate(calc(var(--rotation) * 0.4)) scale(1.2); } 100% { opacity: 1; transform: translateY(60vh) translateX(var(--x-drift)) rotate(var(--rotation)) scale(0.8); } }
      .win-celebration { animation: scale-in 0.5s ease-out forwards; }
      @keyframes scale-in { 0% { transform: scale(0.5); opacity: 0; } 50% { transform: scale(1.1); } 100% { transform: scale(1); opacity: 1; } }
      .win-shake { animation: shake 0.5s ease-out; }
      @keyframes shake { 0%, 100% { transform: translateX(0); } 10%, 30%, 50%, 70%, 90% { transform: translateX(-5px); } 20%, 40%, 60%, 80% { transform: translateX(5px); } }
      .animate-fade-in { animation: fade-in 0.5s ease-out 0.3s both; }
      @keyframes fade-in { 0% { opacity: 0; transform: translateY(10px); } 100% { opacity: 1; transform: translateY(0); } }
    </style>
    """
  end

  # ============ Event Handlers ============

  @impl true
  def handle_event("select_token", %{"token" => token}, socket) do
    user_stats = if socket.assigns.current_user, do: load_user_stats(socket.assigns.current_user.id, token), else: nil
    default_bet = default_bet_amount(socket.assigns.balances, token)
    difficulty = socket.assigns.selected_difficulty

    {:noreply,
     socket
     |> assign(selected_token: token, bet_amount: default_bet, user_stats: user_stats, show_token_dropdown: false, error_message: nil, header_token: token)
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
    selected_token = socket.assigns.selected_token
    user_id = if socket.assigns.current_user, do: socket.assigns.current_user.id, else: nil
    wallet_address = socket.assigns[:wallet_address]

    socket =
      socket
      |> assign(selected_difficulty: new_level, predictions: List.duplicate(nil, predictions_needed),
                results: [], game_state: :idle, current_flip: 0, won: nil, payout: 0,
                error_message: nil, confetti_pieces: [], show_fairness_modal: false, fairness_game: nil)
      |> start_async(:fetch_house_balance, fn -> fetch_house_balance_async(selected_token, new_level) end)

    socket = if wallet_address && user_id do
      socket
      |> assign(:onchain_ready, false)
      |> assign(:onchain_initializing, true)
      |> start_async(:init_game, fn -> CoinFlipGame.get_or_init_game(user_id, wallet_address) end)
    else
      assign(socket, :onchain_ready, false)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_prediction", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str) - 1
    predictions_needed = get_predictions_needed(socket.assigns.selected_difficulty)

    current_predictions =
      if length(socket.assigns.predictions) == predictions_needed,
        do: socket.assigns.predictions,
        else: List.duplicate(nil, predictions_needed)

    new_value = case Enum.at(current_predictions, index) do
      nil -> :heads
      :heads -> :tails
      :tails -> :heads
    end

    {:noreply, assign(socket, predictions: List.replace_at(current_predictions, index, new_value))}
  end

  @impl true
  def handle_event("update_bet_amount", %{"value" => value}, socket) do
    case Float.parse(value) do
      {amount, _} when amount > 0 -> {:noreply, assign(socket, bet_amount: amount, error_message: nil)}
      _ ->
        case Integer.parse(value) do
          {amount, _} when amount > 0 -> {:noreply, assign(socket, bet_amount: amount / 1.0, error_message: nil)}
          _ -> {:noreply, socket}
        end
    end
  end

  @impl true
  def handle_event("set_preset", %{"amount" => amount_str}, socket) do
    case Float.parse(amount_str) do
      {amount, _} when amount > 0 -> {:noreply, assign(socket, bet_amount: amount, error_message: nil)}
      _ -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("set_max_bet", _params, socket) do
    token = socket.assigns.selected_token
    min_b = min_bet(token)

    if socket.assigns.current_user do
      balance = Map.get(socket.assigns.balances, token, 0)
      max_allowed = min(socket.assigns.max_bet, balance)
      {:noreply, assign(socket, bet_amount: max(min_b, max_allowed), error_message: nil)}
    else
      {:noreply, assign(socket, bet_amount: max(min_b, socket.assigns.max_bet), error_message: nil)}
    end
  end

  @impl true
  def handle_event("halve_bet", _params, socket) do
    min_b = min_bet(socket.assigns.selected_token)
    {:noreply, assign(socket, bet_amount: max(min_b, socket.assigns.bet_amount / 2), error_message: nil)}
  end

  @impl true
  def handle_event("double_bet", _params, socket) do
    token = socket.assigns.selected_token
    min_b = min_bet(token)

    if socket.assigns.current_user do
      balance = Map.get(socket.assigns.balances, token, 0)
      new_amount = min(balance, socket.assigns.bet_amount * 2)
      {:noreply, assign(socket, bet_amount: max(min_b, new_amount), error_message: nil)}
    else
      new_amount = min(socket.assigns.max_bet, socket.assigns.bet_amount * 2)
      {:noreply, assign(socket, bet_amount: max(min_b, new_amount), error_message: nil)}
    end
  end

  @impl true
  def handle_event("start_game", _params, socket) do
    if socket.assigns.current_user == nil do
      {:noreply, push_navigate(socket, to: ~p"/")}
    else
      balance = Map.get(socket.assigns.balances, socket.assigns.selected_token, 0)
      bet_amount = socket.assigns.bet_amount
      predictions = socket.assigns.predictions
      predictions_needed = get_predictions_needed(socket.assigns.selected_difficulty)
      onchain_ready = Map.get(socket.assigns, :onchain_ready, false)

      all_predictions_made =
        length(predictions) == predictions_needed and
          Enum.all?(predictions, fn p -> p in [:heads, :tails] end)

      vault_type = token_to_vault_type(socket.assigns.selected_token)

      cond do
        not onchain_ready and Map.get(socket.assigns, :onchain_initializing, false) ->
          current_msg = socket.assigns[:error_message]
          msg = cond do
            current_msg && String.contains?(current_msg, "settlement") -> current_msg
            current_msg && String.contains?(current_msg, "stuck") -> current_msg
            true -> "Initializing game, please wait..."
          end
          {:noreply, assign(socket, error_message: msg)}

        not onchain_ready ->
          {:noreply, assign(socket, error_message: "Previous bet still settling. Please wait or refresh to reclaim.")}

        not all_predictions_made ->
          {:noreply, assign(socket, error_message: "Please make all #{predictions_needed} predictions")}

        bet_amount < min_bet(socket.assigns.selected_token) ->
          {:noreply, assign(socket, error_message: "Minimum bet is #{format_bet_amount(min_bet(socket.assigns.selected_token))} #{socket.assigns.selected_token}")}

        bet_amount > balance ->
          {:noreply, assign(socket, error_message: "Insufficient #{socket.assigns.selected_token} balance")}

        socket.assigns.max_bet > 0 and bet_amount > socket.assigns.max_bet ->
          {:noreply, assign(socket, error_message: "Bet exceeds max bet of #{format_bet_amount(socket.assigns.max_bet)} #{socket.assigns.selected_token} for this difficulty")}

        true ->
          user_id = socket.assigns.current_user.id
          wallet_address = socket.assigns.wallet_address
          game_id = socket.assigns.onchain_game_id
          difficulty = socket.assigns.selected_difficulty

          case CoinFlipGame.calculate_game_result(game_id, predictions, bet_amount, vault_type, difficulty) do
            {:ok, result} ->
              # Build unsigned place_bet tx for wallet signing
              nonce = socket.assigns.onchain_nonce
              vault_type_str = Atom.to_string(vault_type)
              diff_index = difficulty_to_diff_index(difficulty)

              socket =
                socket
                |> assign(current_bet: bet_amount, results: result.results,
                          won: result.won, payout: result.payout, game_state: :flipping,
                          current_flip: 1, flip_id: 1, bet_confirmed: false,
                          flip_start_time: System.monotonic_time(:millisecond), error_message: nil)
                |> start_async(:build_bet_tx, fn ->
                  BlocksterV2.BuxMinter.build_place_bet_tx(wallet_address, 1, nonce, bet_amount, diff_index, vault_type_str)
                end)

              {:noreply, socket}

            {:error, reason} ->
              {:noreply, assign(socket, error_message: "Failed to calculate result: #{inspect(reason)}")}
          end
      end
    end
  end

  @impl true
  def handle_event("flip_complete", _params, socket) do
    if socket.assigns.game_state == :flipping, do: send(self(), :flip_complete)
    {:noreply, socket}
  end

  @impl true
  def handle_event("bet_confirmed", %{"game_id" => _game_id, "tx_hash" => tx_hash} = params, socket) do
    user_id = socket.assigns.current_user.id
    wallet_address = socket.assigns.wallet_address
    token = socket.assigns.selected_token
    predictions = socket.assigns.predictions
    bet_amount = socket.assigns.current_bet
    vault_type = token_to_vault_type(token)
    difficulty = socket.assigns.selected_difficulty

    # Mark bet as placed in Mnesia
    CoinFlipGame.on_bet_placed(socket.assigns.onchain_game_id, tx_hash, predictions, bet_amount, vault_type, difficulty)

    # Deduct balance now that bet is confirmed on-chain
    deduct_balance(user_id, wallet_address, token, bet_amount)
    new_balance = Map.get(socket.assigns.balances, token, 0) - bet_amount
    balances = Map.put(socket.assigns.balances, token, max(0.0, new_balance))
    token_balances = Map.merge(socket.assigns[:token_balances] || %{}, balances)

    socket = assign(socket, bet_confirmed: true, balances: balances, token_balances: token_balances)

    # Reveal result immediately
    send(self(), :reveal_flip_result)

    {:noreply, socket}
  end

  @impl true
  def handle_event("bet_failed", %{"game_id" => _game_id, "error" => error_message}, socket) do
    Logger.error("[CoinFlip] Bet submission failed: #{error_message}")

    {:noreply,
     socket
     |> assign(game_state: :idle, results: [], won: nil, payout: 0,
               bet_confirmed: false, error_message: "Transaction failed: #{error_message}")}
  end

  @impl true
  def handle_event("bet_error", %{"error" => error}, socket) do
    Logger.error("[CoinFlip] Bet error: #{error}")
    {:noreply, assign(socket, error_message: error, game_state: :idle, results: [], won: nil, payout: 0, bet_confirmed: false)}
  end

  def handle_event("reclaim_confirmed", %{"signature" => sig}, socket) do
    Logger.info("[CoinFlip] Reclaim confirmed: #{sig}. Re-initializing game...")
    user_id = socket.assigns.current_user.id
    wallet = socket.assigns.wallet_address

    {:noreply,
     socket
     |> assign(:error_message, nil)
     |> assign(:init_retry_count, 0)
     |> assign(:has_expired_bet, false)
     |> start_async(:init_game, fn -> CoinFlipGame.get_or_init_game(user_id, wallet) end)}
  end

  def handle_event("reclaim_failed", %{"error" => error}, socket) do
    Logger.error("[CoinFlip] Reclaim failed: #{error}")
    {:noreply, assign(socket, onchain_initializing: false, error_message: "Reclaim failed: #{error}. Please refresh.")}
  end

  @impl true
  def handle_event("reset_game", _params, socket) do
    selected_token = socket.assigns.selected_token
    selected_difficulty = socket.assigns.selected_difficulty
    predictions_needed = get_predictions_needed(selected_difficulty)

    if socket.assigns.current_user == nil do
      socket =
        socket
        |> assign(game_state: :idle, current_flip: 0, predictions: List.duplicate(nil, predictions_needed),
                  results: [], won: nil, payout: 0, confetti_pieces: [], error_message: nil)
        |> start_async(:fetch_house_balance, fn -> fetch_house_balance_async(selected_token, selected_difficulty) end)

      {:noreply, socket}
    else
      user_id = socket.assigns.current_user.id
      wallet_address = socket.assigns.wallet_address

      # Refresh balances
      sol_balance = EngagementTracker.get_user_sol_balance(user_id)
      bux_balance = EngagementTracker.get_user_solana_bux_balance(user_id)
      balances = %{"BUX" => bux_balance, "SOL" => sol_balance}
      user_stats = load_user_stats(user_id, selected_token)

      socket =
        socket
        |> assign(game_state: :idle, current_flip: 0, predictions: List.duplicate(nil, predictions_needed),
                  results: [], won: nil, payout: 0, balances: balances, user_stats: user_stats,
                  server_seed: nil, confetti_pieces: [], show_fairness_modal: false, fairness_game: nil,
                  bet_sig: nil, settlement_sig: nil, error_message: nil)
        |> start_async(:fetch_house_balance, fn -> fetch_house_balance_async(selected_token, selected_difficulty) end)

      socket = cond do
        # Use pre-initialized game from bet_confirmed if available (instant)
        socket.assigns[:next_game_session] != nil ->
          game_session = socket.assigns.next_game_session
          Logger.info("[CoinFlip] Using pre-initialized game: nonce #{game_session.nonce}")
          socket
          |> assign(:onchain_game_id, game_session.game_id)
          |> assign(:commitment_hash, game_session.commitment_hash)
          |> assign(:commitment_sig, game_session[:commitment_sig])
          |> assign(:onchain_nonce, game_session.nonce)
          |> assign(:onchain_ready, true)
          |> assign(:onchain_initializing, false)
          |> assign(:init_retry_count, 0)
          |> assign(:server_seed_hash, game_session.commitment_hash)
          |> assign(:nonce, game_session.nonce)
          |> assign(:next_game_session, nil)

        wallet_address != nil ->
          socket
          |> assign(:onchain_ready, false)
          |> assign(:onchain_initializing, true)
          |> assign(:init_retry_count, 0)
          |> start_async(:init_game, fn -> CoinFlipGame.get_or_init_game(user_id, wallet_address) end)

        true ->
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
    # SECURITY: Only show server seed for SETTLED games
    case CoinFlipGame.get_game(game_id) do
      {:ok, game} when game.status == :settled ->
        predictions_str = game.predictions |> Enum.map(&Atom.to_string/1) |> Enum.join(",")
        vault_type_str = if is_atom(game.vault_type), do: Atom.to_string(game.vault_type), else: to_string(game.vault_type)

        client_seed_input = "#{game.user_id}:#{game.bet_amount}:#{vault_type_str}:#{game.difficulty}:#{predictions_str}"
        client_seed = :crypto.hash(:sha256, client_seed_input) |> Base.encode16(case: :lower)

        combined_input = "#{game.server_seed}:#{client_seed}:#{game.nonce}"
        combined_seed = :crypto.hash(:sha256, combined_input)
        combined_seed_hex = Base.encode16(combined_seed, case: :lower)

        bytes = for i <- 0..(length(game.results) - 1), do: :binary.at(combined_seed, i)

        fairness_game = %{
          game_id: game_id,
          user_id: game.user_id,
          bet_amount: game.bet_amount,
          vault_type: vault_type_str,
          difficulty: game.difficulty,
          predictions_str: predictions_str,
          client_seed_input: client_seed_input,
          nonce: game.nonce,
          server_seed: game.server_seed,
          server_seed_hash: game.commitment_hash,
          client_seed: client_seed,
          combined_seed: combined_seed_hex,
          results: game.results,
          predictions: game.predictions,
          bytes: bytes,
          won: game.won,
          payout: game.payout
        }

        {:noreply, assign(socket, show_fairness_modal: true, fairness_game: fairness_game)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("hide_fairness_modal", _params, socket) do
    {:noreply, assign(socket, show_fairness_modal: false)}
  end

  @impl true
  def handle_event("load-more-games", _params, socket) do
    if socket.assigns.current_user == nil do
      {:reply, %{end_reached: true}, socket}
    else
      user_id = socket.assigns.current_user.id
      offset = socket.assigns.games_offset
      new_games = load_recent_games(user_id, limit: 30, offset: offset)

      if Enum.empty?(new_games) do
        {:reply, %{end_reached: true}, socket}
      else
        existing_ids = MapSet.new(socket.assigns.recent_games, & &1.game_id)
        unique = Enum.reject(new_games, fn g -> MapSet.member?(existing_ids, g.game_id) end)

        {:noreply,
         socket
         |> assign(:recent_games, socket.assigns.recent_games ++ unique)
         |> assign(:games_offset, offset + length(unique))}
      end
    end
  end

  @impl true
  def handle_event("load-more", params, socket), do: handle_event("load-more-games", params, socket)

  @impl true
  def handle_event("stop_propagation", _params, socket), do: {:noreply, socket}

  # ============ Async Handlers ============

  @impl true
  def handle_async(:init_game, {:ok, {:ok, game_session}}, socket) do
    {:noreply,
     socket
     |> assign(:onchain_game_id, game_session.game_id)
     |> assign(:commitment_hash, game_session.commitment_hash)
     |> assign(:commitment_sig, game_session[:commitment_sig])
     |> assign(:onchain_nonce, game_session.nonce)
     |> assign(:onchain_ready, true)
     |> assign(:onchain_initializing, false)
     |> assign(:init_retry_count, 0)
     |> assign(:server_seed_hash, game_session.commitment_hash)
     |> assign(:nonce, game_session.nonce)
     |> assign(:error_message, nil)}
  end

  @impl true
  def handle_async(:init_game, {:ok, {:error, {:active_order, stuck_nonce}}}, socket) do
    wallet = socket.assigns.wallet_address
    retry_count = Map.get(socket.assigns, :init_retry_count, 0)

    # If we just finished a game, settlement may still be in progress — auto-retry
    if retry_count < 5 do
      delay = min(1000 * (retry_count + 1), 3000)
      Logger.info("[CoinFlip] Active order for #{wallet} at nonce #{stuck_nonce}, retrying init in #{delay}ms (attempt #{retry_count + 1})")
      Process.send_after(self(), :retry_init_game, delay)

      {:noreply,
       socket
       |> assign(:onchain_ready, false)
       |> assign(:onchain_initializing, true)
       |> assign(:init_retry_count, retry_count + 1)
       |> assign(:error_message, "Waiting for settlement...")}
    else
      # After retries exhausted, fall back to reclaim flow
      Logger.warning("[CoinFlip] Active order persists for #{wallet} at nonce #{stuck_nonce}, attempting reclaim")

      {:noreply,
       socket
       |> assign(:onchain_ready, false)
       |> assign(:onchain_initializing, true)
       |> assign(:error_message, "Clearing stuck bet...")
       |> start_async(:build_reclaim_tx, fn ->
         case BlocksterV2.BuxMinter.build_reclaim_expired_tx(wallet, stuck_nonce, "bux") do
           {:ok, tx} -> {:ok, tx, stuck_nonce}
           {:error, _} ->
             case BlocksterV2.BuxMinter.build_reclaim_expired_tx(wallet, stuck_nonce, "sol") do
               {:ok, tx} -> {:ok, tx, stuck_nonce}
               {:error, reason} -> {:error, reason}
             end
         end
       end)}
    end
  end

  def handle_async(:init_game, {:ok, {:error, reason}}, socket) do
    retry_count = Map.get(socket.assigns, :init_retry_count, 0)
    max_retries = 3

    if retry_count < max_retries do
      delay = :math.pow(2, retry_count) * 1000 |> round()
      Logger.warning("[CoinFlip] Init failed (attempt #{retry_count + 1}/#{max_retries}): #{inspect(reason)}. Retrying in #{delay}ms...")
      Process.send_after(self(), :retry_init_game, delay)

      {:noreply,
       socket
       |> assign(:onchain_ready, false)
       |> assign(:onchain_initializing, true)
       |> assign(:init_retry_count, retry_count + 1)
       |> assign(:error_message, "Initializing game... (attempt #{retry_count + 1}/#{max_retries})")}
    else
      Logger.error("[CoinFlip] Init failed after #{max_retries} attempts: #{inspect(reason)}")
      {:noreply,
       socket
       |> assign(:onchain_ready, false)
       |> assign(:onchain_initializing, false)
       |> assign(:init_retry_count, 0)
       |> assign(:error_message, "Failed to initialize game. Please refresh the page.")}
    end
  end

  @impl true
  def handle_async(:init_game, {:exit, reason}, socket) do
    retry_count = Map.get(socket.assigns, :init_retry_count, 0)
    if retry_count < 3 do
      delay = :math.pow(2, retry_count) * 1000 |> round()
      Process.send_after(self(), :retry_init_game, delay)
      {:noreply,
       socket
       |> assign(:onchain_ready, false)
       |> assign(:onchain_initializing, true)
       |> assign(:init_retry_count, retry_count + 1)}
    else
      {:noreply,
       socket
       |> assign(:onchain_ready, false)
       |> assign(:onchain_initializing, false)
       |> assign(:error_message, "Failed to initialize game.")}
    end
  end

  @impl true
  def handle_async(:fetch_house_balance, {:ok, {house_balance, max_bet}}, socket) do
    # Cap default bet to max_bet if needed
    bet_amount = socket.assigns.bet_amount
    token = socket.assigns.selected_token
    min_b = min_bet(token)

    adjusted_bet =
      if max_bet > 0 and bet_amount > max_bet do
        presets = stake_presets(token)
        Enum.filter(presets, &(&1 <= max_bet)) |> List.last() || min_b
      else
        bet_amount
      end

    {:noreply,
     socket
     |> assign(:house_balance, house_balance)
     |> assign(:max_bet, max_bet)
     |> assign(:bet_amount, adjusted_bet)}
  end

  @impl true
  def handle_async(:fetch_house_balance, {:exit, _reason}, socket), do: {:noreply, socket}

  @impl true
  def handle_async(:load_recent_games, {:ok, games}, socket) do
    {:noreply, assign(socket, :recent_games, games) |> assign(:games_offset, length(games)) |> assign(:games_loading, false)}
  end

  @impl true
  def handle_async(:load_recent_games, {:exit, _reason}, socket) do
    {:noreply, assign(socket, :games_loading, false)}
  end

  @impl true
  def handle_async(:build_bet_tx, {:ok, {:ok, tx}}, socket) do
    game_id = socket.assigns.onchain_game_id
    vault_type = token_to_vault_type(socket.assigns.selected_token) |> Atom.to_string()

    {:noreply,
     push_event(socket, "sign_place_bet", %{
       transaction: tx,
       game_id: game_id,
       vault_type: vault_type
     })}
  end

  @impl true
  def handle_async(:build_reclaim_tx, {:ok, {:ok, tx, _nonce}}, socket) do
    Logger.info("[CoinFlip] Reclaim tx built, pushing to wallet for signing")
    {:noreply,
     socket
     |> assign(:error_message, "Approve reclaim transaction in your wallet...")
     |> push_event("sign_reclaim", %{transaction: tx})}
  end

  @impl true
  def handle_async(:build_reclaim_tx, {:ok, {:error, reason}}, socket) do
    Logger.error("[CoinFlip] Failed to build reclaim tx: #{inspect(reason)}")
    {:noreply,
     socket
     |> assign(:onchain_initializing, false)
     |> assign(:error_message, "Stuck bet not yet expired. Please wait and refresh.")}
  end

  @impl true
  def handle_async(:build_reclaim_tx, {:exit, _reason}, socket) do
    {:noreply, socket |> assign(:onchain_initializing, false) |> assign(:error_message, "Failed to build reclaim transaction.")}
  end

  @impl true
  def handle_async(:build_bet_tx, {:ok, {:error, reason}}, socket) do
    Logger.error("[CoinFlip] Failed to build place bet tx: #{inspect(reason)}")
    # Refund the optimistically deducted balance
    if socket.assigns[:current_user] do
      user_id = socket.assigns.current_user.id
      wallet = socket.assigns.wallet_address
      credit_balance(user_id, wallet, socket.assigns.selected_token, socket.assigns.current_bet)
    end
    error_msg = parse_build_tx_error(reason)
    {:noreply, assign(socket, error_message: error_msg, game_state: :idle)}
  end

  @impl true
  def handle_async(:build_bet_tx, {:exit, reason}, socket) do
    Logger.error("[CoinFlip] Build bet tx crashed: #{inspect(reason)}")
    if socket.assigns[:current_user] do
      user_id = socket.assigns.current_user.id
      wallet = socket.assigns.wallet_address
      credit_balance(user_id, wallet, socket.assigns.selected_token, socket.assigns.current_bet)
    end
    {:noreply, assign(socket, error_message: "Failed to build bet transaction. Please try again.", game_state: :idle)}
  end

  # ============ Info Handlers ============

  @impl true
  def handle_info(:retry_init_game, socket) do
    user_id = socket.assigns.current_user.id
    wallet_address = socket.assigns.wallet_address
    {:noreply, start_async(socket, :init_game, fn -> CoinFlipGame.get_or_init_game(user_id, wallet_address) end)}
  end

  @impl true
  def handle_info(:reveal_flip_result, socket) do
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
    socket = assign(socket, game_state: :showing_result)
    Process.send_after(self(), :after_result_shown, 1000)
    {:noreply, socket}
  end

  @impl true
  def handle_info(:after_result_shown, socket) do
    current_flip = socket.assigns.current_flip
    predictions = socket.assigns.predictions
    results = socket.assigns.results
    predictions_needed = get_predictions_needed(socket.assigns.selected_difficulty)
    mode = get_mode(socket.assigns.selected_difficulty)

    correct = Enum.at(predictions, current_flip - 1) == Enum.at(results, current_flip - 1)

    case mode do
      :win_one ->
        if correct do
          send(self(), :show_final_result)
        else
          if current_flip >= predictions_needed,
            do: send(self(), :show_final_result),
            else: send(self(), :next_flip)
        end

      :win_all ->
        if not correct do
          send(self(), :show_final_result)
        else
          if current_flip >= predictions_needed,
            do: send(self(), :show_final_result),
            else: send(self(), :next_flip)
        end
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info(:next_flip, socket) do
    mode = get_mode(socket.assigns.selected_difficulty)
    new_current_bet = if mode == :win_all, do: socket.assigns.current_bet * 2, else: socket.assigns.current_bet

    # Reveal immediately — JS plays the 3s deceleration animation
    send(self(), :reveal_flip_result)

    {:noreply,
     socket
     |> assign(game_state: :flipping, current_flip: socket.assigns.current_flip + 1,
               flip_id: socket.assigns.flip_id + 1, current_bet: new_current_bet)}
  end

  @impl true
  def handle_info(:show_final_result, socket) do
    if not socket.assigns.bet_confirmed do
      # Bet not yet confirmed on-chain — wait and retry
      Process.send_after(self(), :show_final_result, 500)
      {:noreply, socket}
    else
      user_id = socket.assigns.current_user.id
      won = socket.assigns.won
      payout = socket.assigns.payout
      token_type = socket.assigns.selected_token

      multiplier = get_multiplier_for_difficulty(socket.assigns.selected_difficulty)
      BlocksterV2.UserEvents.track(user_id, "game_played", %{
        token: to_string(token_type), result: if(won, do: "win", else: "loss"),
        multiplier: multiplier, bet_amount: socket.assigns.current_bet, payout: payout
      })

      user_stats = load_user_stats(user_id, token_type)
      confetti_pieces = if won, do: generate_confetti_data(100), else: []

      # Settle in background
      game_id = socket.assigns.onchain_game_id
      liveview_pid = self()
      spawn(fn ->
        case CoinFlipGame.settle_game(game_id) do
          {:ok, %{signature: sig}} -> send(liveview_pid, {:settlement_complete, sig})
          {:error, reason} ->
            Logger.error("[CoinFlip] Settlement failed: #{inspect(reason)}")
            send(liveview_pid, {:settlement_failed, reason})
        end
      end)

      socket =
        socket
        |> assign(game_state: :result, won: won, payout: payout, user_stats: user_stats, confetti_pieces: confetti_pieces, settlement_status: :pending)
        |> push_event("bet_settled", %{won: won, payout: payout})

      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:settlement_complete, sig}, socket) do
    user_id = socket.assigns.current_user.id
    wallet_address = socket.assigns.wallet_address

    BuxMinter.sync_user_balances_async(user_id, wallet_address, force: true)

    # Broadcast settled game
    game_id = socket.assigns.onchain_game_id
    case CoinFlipGame.get_game(game_id) do
      {:ok, game} when game.status == :settled ->
        settled_game = %{
          game_id: game.game_id,
          vault_type: if(is_atom(game.vault_type), do: Atom.to_string(game.vault_type), else: to_string(game.vault_type)),
          bet_amount: game.bet_amount,
          multiplier: get_multiplier_for_difficulty(game.difficulty),
          predictions: game.predictions,
          results: game.results,
          won: game.won,
          payout: game.payout,
          commitment_hash: game.commitment_hash,
          server_seed: game.server_seed,
          nonce: game.nonce,
          commitment_sig: game.commitment_sig,
          bet_sig: game.bet_sig,
          settlement_sig: game.settlement_sig
        }

        Phoenix.PubSub.broadcast(BlocksterV2.PubSub, "coin_flip_settlement:#{user_id}", {:new_settled_game, settled_game})

      _ -> :ok
    end

    # Refresh house balance and user balances after settlement
    selected_token = socket.assigns.selected_token
    selected_difficulty = socket.assigns.selected_difficulty

    socket =
      socket
      |> assign(settlement_sig: sig, settlement_status: :settled)
      |> start_async(:fetch_house_balance, fn -> fetch_house_balance_async(selected_token, selected_difficulty) end)
      |> start_async(:sync_post_settle, fn ->
        BuxMinter.sync_user_balances(user_id, wallet_address)
        sol = EngagementTracker.get_user_sol_balance(user_id)
        bux = EngagementTracker.get_user_solana_bux_balance(user_id)
        %{"SOL" => sol, "BUX" => bux}
      end)

    # Pre-init next game commitment now that settlement is done (no playerState write conflict)
    socket = start_async(socket, :pre_init_next_game, fn ->
      CoinFlipGame.get_or_init_game(user_id, wallet_address)
    end)

    {:noreply, socket}
  end

  @impl true
  def handle_async(:sync_post_settle, {:ok, balances}, socket) do
    {:noreply, assign(socket, :balances, balances)}
  end

  def handle_async(:sync_post_settle, _, socket), do: {:noreply, socket}

  # Pre-init next game: cache the result so Play Again is instant
  @impl true
  def handle_async(:pre_init_next_game, {:ok, {:ok, game_session}}, socket) do
    Logger.info("[CoinFlip] Next game pre-initialized: nonce #{game_session.nonce}")
    {:noreply, assign(socket, :next_game_session, game_session)}
  end

  @impl true
  def handle_async(:pre_init_next_game, _result, socket) do
    # Failed to pre-init — no problem, reset_game will init normally
    {:noreply, socket}
  end

  @impl true
  def handle_info({:settlement_failed, reason}, socket) do
    # Timeouts don't mean the tx failed — it's likely still in flight on Solana.
    # The background BetSettler will pick it up. Keep status as :pending for timeouts.
    reason_str = if is_binary(reason), do: reason, else: inspect(reason)
    if String.contains?(reason_str, "timeout") or String.contains?(reason_str, "TransportError") do
      Logger.warning("[CoinFlip] Settlement timed out — tx likely still in flight, background settler will retry")
      {:noreply, socket}
    else
      {:noreply, assign(socket, settlement_status: :failed)}
    end
  end

  def handle_info({:bux_balance_updated, _new_balance}, socket), do: {:noreply, socket}

  def handle_info(:check_expired_bets, socket) do
    if socket.assigns.current_user && socket.assigns.wallet_address do
      user_id = socket.assigns.current_user.id
      wallet = socket.assigns.wallet_address

      bet_timeout = 300
      now = System.system_time(:second)

      has_expired = try do
        case :mnesia.dirty_index_read(:coin_flip_games, user_id, :user_id) do
          games when is_list(games) ->
            Enum.any?(games, fn record ->
              status = elem(record, 7)
              created_at = elem(record, 18)
              status == :placed and created_at != nil and (now - created_at) > bet_timeout
            end)
          _ -> false
        end
      rescue
        _ -> false
      end

      Process.send_after(self(), :check_expired_bets, 30_000)
      {:noreply, assign(socket, has_expired_bet: has_expired)}
    else
      Process.send_after(self(), :check_expired_bets, 30_000)
      {:noreply, socket}
    end
  end

  def handle_info({:new_settled_game, settled_game}, socket) do
    {:noreply, assign(socket, :recent_games, [settled_game | socket.assigns.recent_games])}
  end

  # ============ Helpers ============

  defp token_to_vault_type("SOL"), do: :sol
  defp token_to_vault_type(_), do: :bux

  # Maps difficulty level (-4..-1, 1..5) to on-chain diffIndex (0..8)
  # Matches EVM: difficulty < 0 ? uint8(4 + difficulty) : uint8(3 + difficulty)
  defp difficulty_to_diff_index(difficulty) when difficulty < 0, do: 4 + difficulty
  defp difficulty_to_diff_index(difficulty) when difficulty > 0, do: 3 + difficulty

  defp deduct_balance(user_id, wallet_address, "SOL", amount) do
    # For SOL, deduct from Solana balance tracking
    current = EngagementTracker.get_user_sol_balance(user_id)
    if current >= amount do
      EngagementTracker.update_user_sol_balance(user_id, wallet_address, current - amount)
      {:ok, current - amount}
    else
      {:error, "Insufficient SOL balance"}
    end
  end

  defp deduct_balance(user_id, wallet_address, "BUX", amount) do
    current = EngagementTracker.get_user_solana_bux_balance(user_id)
    if current >= amount do
      EngagementTracker.update_user_solana_bux_balance(user_id, wallet_address, current - amount)
      {:ok, current - amount}
    else
      {:error, "Insufficient BUX balance"}
    end
  end

  defp deduct_balance(user_id, wallet_address, token, amount) do
    EngagementTracker.deduct_user_token_balance(user_id, wallet_address, token, amount)
  end

  defp credit_balance(user_id, wallet_address, "SOL", amount) do
    current = EngagementTracker.get_user_sol_balance(user_id)
    EngagementTracker.update_user_sol_balance(user_id, wallet_address, current + amount)
    {:ok, current + amount}
  end

  defp credit_balance(user_id, wallet_address, "BUX", amount) do
    current = EngagementTracker.get_user_solana_bux_balance(user_id)
    EngagementTracker.update_user_solana_bux_balance(user_id, wallet_address, current + amount)
    {:ok, current + amount}
  end

  defp credit_balance(user_id, wallet_address, token, amount) do
    EngagementTracker.credit_user_token_balance(user_id, wallet_address, token, amount)
  end

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

  defp get_multiplier_for_difficulty(difficulty) do
    case Enum.find(@difficulty_options, fn opt -> opt.level == difficulty end) do
      nil -> 1.0
      opt -> opt.multiplier
    end
  end

  defp get_coin_size_classes(num_flips) do
    case num_flips do
      1 -> %{outer: "w-20 h-20 sm:w-24 sm:h-24", inner: "w-14 h-14 sm:w-16 sm:h-16", emoji: "text-3xl sm:text-4xl"}
      2 -> %{outer: "w-18 h-18 sm:w-20 sm:h-20", inner: "w-12 h-12 sm:w-14 sm:h-14", emoji: "text-2xl sm:text-3xl"}
      3 -> %{outer: "w-16 h-16 sm:w-20 sm:h-20", inner: "w-11 h-11 sm:w-14 sm:h-14", emoji: "text-2xl sm:text-3xl"}
      4 -> %{outer: "w-14 h-14 sm:w-18 sm:h-18", inner: "w-10 h-10 sm:w-12 sm:h-12", emoji: "text-xl sm:text-2xl"}
      _ -> %{outer: "w-12 h-12 sm:w-16 sm:h-16", inner: "w-8 h-8 sm:w-10 sm:h-10", emoji: "text-lg sm:text-2xl"}
    end
  end

  defp get_prediction_size_classes(num_flips) do
    case num_flips do
      1 -> %{outer: "w-20 h-20 sm:w-20 sm:h-20", inner: "w-14 h-14 sm:w-14 sm:h-14", emoji: "text-3xl sm:text-3xl"}
      2 -> %{outer: "w-18 h-18 sm:w-18 sm:h-18", inner: "w-12 h-12 sm:w-12 sm:h-12", emoji: "text-2xl sm:text-2xl"}
      3 -> %{outer: "w-16 h-16 sm:w-16 sm:h-16", inner: "w-11 h-11 sm:w-10 sm:h-10", emoji: "text-2xl sm:text-2xl"}
      4 -> %{outer: "w-14 h-14 sm:w-16 sm:h-16", inner: "w-10 h-10 sm:w-10 sm:h-10", emoji: "text-xl sm:text-2xl"}
      _ -> %{outer: "w-12 h-12 sm:w-16 sm:h-16", inner: "w-8 h-8 sm:w-10 sm:h-10", emoji: "text-xl sm:text-2xl"}
    end
  end

  defp format_balance(amount) when is_float(amount) and amount != 0.0 and amount > -1.0 and amount < 1.0 do
    # Use enough decimals so small PnL values (e.g. +0.0002 on a 0.01 bet) don't show as 0.00
    decimals = cond do
      abs(amount) >= 0.01 -> 4
      abs(amount) >= 0.0001 -> 6
      true -> 8
    end
    :erlang.float_to_binary(amount, decimals: decimals) |> String.trim_trailing("0") |> add_comma_delimiters()
  end
  defp format_balance(amount) when is_float(amount), do: :erlang.float_to_binary(amount, decimals: 2) |> add_comma_delimiters()
  defp format_balance(amount) when is_integer(amount), do: :erlang.float_to_binary(amount / 1, decimals: 2) |> add_comma_delimiters()
  defp format_balance(_), do: "0.00"

  defp format_integer(amount) when is_integer(amount) do
    amount |> Integer.to_string() |> String.reverse() |> String.graphemes()
    |> Enum.chunk_every(3) |> Enum.map(&Enum.join/1) |> Enum.join(",") |> String.reverse()
  end
  defp format_integer(amount) when is_float(amount), do: format_integer(trunc(amount))
  defp format_integer(_), do: "0"

  defp format_bet_amount(amount) when is_float(amount) and amount >= 1.0 do
    if amount == Float.floor(amount) do
      format_integer(trunc(amount))
    else
      :erlang.float_to_binary(amount, decimals: 2)
    end
  end
  defp format_bet_amount(amount) when is_float(amount) and amount > 0 do
    # Small values — show enough decimals to be meaningful
    :erlang.float_to_binary(amount, decimals: 4) |> String.trim_trailing("0")
  end
  defp format_bet_amount(amount) when is_float(amount), do: "0"
  defp format_bet_amount(amount) when is_integer(amount), do: format_integer(amount)
  defp format_bet_amount(_), do: "0"

  defp add_comma_delimiters(number_string) do
    [integer_part, decimal_part] = String.split(number_string, ".")
    integer_with_commas =
      integer_part |> String.reverse() |> String.graphemes() |> Enum.chunk_every(3)
      |> Enum.map(&Enum.join/1) |> Enum.join(",") |> String.reverse()
    "#{integer_with_commas}.#{decimal_part}"
  end

  @sol_presets [0.01, 0.05, 0.1, 0.25, 0.5, 1.0]
  @bux_presets [1, 5, 10, 25, 50, 100]

  defp default_bet_amount(balances, token) do
    balance = Map.get(balances, token, 0)
    target = balance * 0.1
    presets = if token == "SOL", do: @sol_presets, else: @bux_presets

    # Pick preset closest to 10% of balance
    closest = Enum.min_by(presets, &abs(&1 - target))
    # Don't exceed balance
    if closest > balance do
      Enum.filter(presets, &(&1 <= balance)) |> List.last() || List.first(presets)
    else
      closest
    end
  end

  defp stake_presets("SOL"), do: @sol_presets
  defp stake_presets(_), do: @bux_presets

  defp min_bet("SOL"), do: 0.01
  defp min_bet(_), do: 1

  defp parse_build_tx_error(reason) when is_binary(reason) do
    cond do
      String.contains?(reason, "BetExceedsMax") ->
        "Bet exceeds the maximum allowed for this difficulty. Try a smaller amount."
      String.contains?(reason, "PayoutExceedsMax") ->
        "Payout exceeds maximum. Try a slightly smaller bet."
      String.contains?(reason, "InsufficientVault") ->
        "Pool doesn't have enough liquidity for this bet."
      String.contains?(reason, "GamePaused") ->
        "Betting is temporarily paused."
      String.contains?(reason, "Simulation failed") ->
        "Transaction simulation failed. The bet may exceed on-chain limits."
      true ->
        "Failed to build bet transaction: #{String.slice(reason, 0, 100)}"
    end
  end

  defp parse_build_tx_error(reason), do: "Failed to build bet transaction: #{inspect(reason)}"

  defp fetch_house_balance_async(token, difficulty_level) do
    vault = if token == "SOL", do: :sol, else: :bux

    case BuxMinter.get_house_balance(token) do
      {:ok, balance} ->
        max_bet = calculate_max_bet(balance, difficulty_level)
        {balance, max_bet}
      {:error, _} ->
        {0.0, 0.0}
    end
  end

  defp calculate_max_bet(house_balance, difficulty_level) do
    # Must replicate on-chain integer math EXACTLY, including intermediate truncations.
    # Rust: base = (net_lamports * max_bet_bps) / 10000
    #        max_bet = (base * 20000) / multiplier_bps
    # Each div truncates. Float math skips intermediate truncation → off by 1+ lamport.
    difficulty = Enum.find(@difficulty_options, &(&1.level == difficulty_level))

    if difficulty do
      multiplier_bp = trunc(difficulty.multiplier * 10000)
      net_lamports = trunc(house_balance * 1.0e9)
      base = div(net_lamports * 10, 10000)
      max_bet_lamports = div(base * 20000, multiplier_bp)
      max_bet_lamports / 1.0e9
    else
      0.0
    end
  end

  defp load_user_stats(user_id, token_type \\ "BUX") do
    key = {user_id, token_type}
    case :mnesia.dirty_read({:bux_booster_user_stats, key}) do
      [] -> nil
      [record] ->
        %{
          total_games: elem(record, 4), total_wins: elem(record, 5), total_losses: elem(record, 6),
          total_wagered: elem(record, 7), total_won: elem(record, 8), total_lost: elem(record, 9),
          biggest_win: elem(record, 10), biggest_loss: elem(record, 11),
          current_streak: elem(record, 12), best_streak: elem(record, 13), worst_streak: elem(record, 14)
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

    # Query from coin_flip_games table
    :mnesia.dirty_index_read(:coin_flip_games, user_id, :user_id)
    |> Enum.filter(fn record -> elem(record, 7) == :settled end)
    |> Enum.sort_by(fn record -> elem(record, 19) end, :desc)  # settled_at
    |> Enum.drop(offset)
    |> Enum.take(limit)
    |> Enum.map(fn record ->
      %{
        game_id: elem(record, 1),
        vault_type: if(is_atom(elem(record, 8)), do: Atom.to_string(elem(record, 8)), else: to_string(elem(record, 8))),
        bet_amount: elem(record, 9),
        multiplier: get_multiplier_for_difficulty(elem(record, 10)),
        predictions: elem(record, 11),
        results: elem(record, 12),
        won: elem(record, 13),
        payout: elem(record, 14),
        commitment_hash: elem(record, 5),
        server_seed: elem(record, 4),
        nonce: elem(record, 6),
        commitment_sig: elem(record, 15),
        bet_sig: elem(record, 16),
        settlement_sig: elem(record, 17)
      }
    end)
  rescue
    _ -> []
  catch
    :exit, _ -> []
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
