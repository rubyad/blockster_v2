defmodule BlocksterV2Web.BuxBoosterLive do
  use BlocksterV2Web, :live_view
  require Logger

  alias BlocksterV2.EngagementTracker
  alias BlocksterV2.HubLogoCache
  alias BlocksterV2.ProvablyFair

  # Difficulty levels with true odds payouts (zero house edge)
  # mode: :win_all = must win all flips (harder, higher payout)
  # mode: :win_one = only need to win one flip (easier, lower payout)
  # Win one fair odds: 1 / (1 - 0.5^n) where n = number of flips
  # Win all fair odds: 2^n where n = number of flips
  @difficulty_options [
    %{level: -4, predictions: 5, multiplier: 1.03, label: "1.03x", mode: :win_one},
    %{level: -3, predictions: 4, multiplier: 1.06, label: "1.06x", mode: :win_one},
    %{level: -2, predictions: 3, multiplier: 1.14, label: "1.14x", mode: :win_one},
    %{level: -1, predictions: 2, multiplier: 1.33, label: "1.33x", mode: :win_one},
    %{level: 1, predictions: 1, multiplier: 2, label: "2x", mode: :win_all},
    %{level: 2, predictions: 2, multiplier: 4, label: "4x", mode: :win_all},
    %{level: 3, predictions: 3, multiplier: 8, label: "8x", mode: :win_all},
    %{level: 4, predictions: 4, multiplier: 16, label: "16x", mode: :win_all},
    %{level: 5, predictions: 5, multiplier: 32, label: "32x", mode: :win_all}
  ]

  @impl true
  def mount(_params, _session, socket) do
    current_user = socket.assigns[:current_user]

    if current_user do
      # User is logged in
      balances = EngagementTracker.get_user_token_balances(current_user.id)
      token_logos = HubLogoCache.get_all_logos()

      # Dynamically get tokens from HubLogoCache, sorted by user's balance descending
      # ROGUE always at top, then other tokens sorted by balance
      other_tokens =
        token_logos
        |> Map.keys()
        |> Enum.reject(fn token -> token == "ROGUE" end)
        |> Enum.sort_by(fn token -> Map.get(balances, token, 0) end, :desc)

      tokens = ["ROGUE" | other_tokens]

      # Generate initial server seed for provably fair system
      server_seed = ProvablyFair.generate_server_seed()
      server_seed_hash = ProvablyFair.generate_commitment(server_seed)
      nonce = get_user_nonce(current_user.id)

      socket =
        socket
        |> assign(page_title: "BUX Booster")
        |> assign(current_user: current_user)
        |> assign(balances: balances)
        |> assign(tokens: tokens)
        |> assign(token_logos: token_logos)
        |> assign(difficulty_options: @difficulty_options)
        |> assign(selected_token: "BUX")
        |> assign(selected_difficulty: 1)
        |> assign(bet_amount: 10)
        |> assign(current_bet: 10)
        |> assign(predictions: [])
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
        |> assign(recent_games: load_recent_games(current_user.id))
        |> assign(user_stats: load_user_stats(current_user.id))
        # Provably fair assigns
        |> assign(server_seed: server_seed)
        |> assign(server_seed_hash: server_seed_hash)
        |> assign(nonce: nonce)
        |> assign(show_fairness_modal: false)
        |> assign(fairness_game: nil)

      {:ok, socket}
    else
      # Not logged in - redirect to login
      {:ok, push_navigate(socket, to: ~p"/login")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <div class="max-w-2xl mx-auto px-4 pt-24 pb-8">
        <!-- Header -->
        <div class="text-center mb-6">
          <h1 class="text-3xl font-bold text-gray-900 font-haas_medium_65">BUX Booster</h1>
          <p class="text-gray-600 text-sm">Predict coin flips to multiply your tokens</p>
        </div>

        <!-- Main Game Area -->
        <div class="bg-white rounded-2xl shadow-sm border border-gray-200 h-[500px] flex flex-col">
          <!-- Difficulty Tabs -->
          <div class="flex border-b border-gray-200">
            <%= for {opt, idx} <- Enum.with_index(@difficulty_options) do %>
              <% is_first = idx == 0 %>
              <% is_last = idx == length(@difficulty_options) - 1 %>
              <button
                type="button"
                phx-click="select_difficulty"
                phx-value-level={opt.level}
                disabled={@game_state not in [:idle, :result]}
                class={"flex-1 py-3 px-2 text-center transition-all cursor-pointer disabled:cursor-not-allowed #{if is_first, do: "rounded-tl-2xl", else: ""} #{if is_last, do: "rounded-tr-2xl", else: ""} #{if @selected_difficulty == opt.level, do: "bg-black", else: "bg-gray-50 hover:bg-gray-100"}"}
              >
                <div class={"text-lg font-bold #{if @selected_difficulty == opt.level, do: "text-white", else: "text-gray-900"}"}><%= opt.multiplier %>x</div>
                <div class={"text-xs #{if @selected_difficulty == opt.level, do: "text-gray-300", else: "text-gray-500"}"}><%= opt.predictions %> flip<%= if opt.predictions > 1, do: "s" %></div>
              </button>
            <% end %>
          </div>

          <!-- Game Content Area -->
          <div class="p-6 flex-1 flex flex-col min-h-0">
            <%= if @game_state == :idle do %>
              <!-- Bet Stake with Token Dropdown -->
              <div class="mb-4">
                <label class="block text-sm font-medium text-gray-700 mb-2">Bet Stake</label>
                <div class="flex gap-2">
                  <!-- Input with halve/double buttons -->
                  <div class="flex-1 relative">
                    <input
                      type="number"
                      value={@bet_amount}
                      phx-keyup="update_bet_amount"
                      phx-debounce="100"
                      min="1"
                      class="w-full bg-white border border-gray-300 rounded-lg pl-4 pr-24 py-3 text-gray-900 text-lg font-medium focus:outline-none focus:border-purple-500 focus:ring-1 focus:ring-purple-500 [appearance:textfield] [&::-webkit-outer-spin-button]:appearance-none [&::-webkit-inner-spin-button]:appearance-none"
                    />
                    <!-- Halve/Double buttons inside input -->
                    <div class="absolute right-2 top-1/2 -translate-y-1/2 flex gap-1">
                      <button
                        type="button"
                        phx-click="halve_bet"
                        class="px-2 py-1 bg-gray-200 text-gray-700 rounded text-sm font-medium hover:bg-gray-300 transition-all cursor-pointer"
                      >
                        ½
                      </button>
                      <button
                        type="button"
                        phx-click="double_bet"
                        class="px-2 py-1 bg-gray-200 text-gray-700 rounded text-sm font-medium hover:bg-gray-300 transition-all cursor-pointer"
                      >
                        2×
                      </button>
                    </div>
                  </div>
                  <!-- Token Dropdown -->
                  <div class="relative" id="token-dropdown-wrapper" phx-click-away="hide_token_dropdown">
                    <button
                      type="button"
                      phx-click="toggle_token_dropdown"
                      class="h-full px-4 bg-gray-100 border border-gray-300 rounded-lg flex items-center gap-2 hover:bg-gray-200 transition-all cursor-pointer min-w-[140px]"
                    >
                      <img src={Map.get(@token_logos, @selected_token, "https://ik.imagekit.io/blockster/blockster-icon.png")} alt={@selected_token} class="w-5 h-5 rounded-full" />
                      <span class="font-medium text-gray-900"><%= @selected_token %></span>
                      <svg class="w-4 h-4 text-gray-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
                      </svg>
                    </button>
                    <%= if @show_token_dropdown do %>
                      <div class="absolute right-0 top-full mt-1 bg-white border border-gray-200 rounded-lg shadow-lg z-50 w-max min-w-[220px] max-h-[400px] overflow-y-auto">
                        <%= for token <- @tokens do %>
                          <button
                            type="button"
                            phx-click="select_token"
                            phx-value-token={token}
                            class={"w-full px-4 py-3 flex items-center gap-3 hover:bg-gray-50 cursor-pointer first:rounded-t-lg last:rounded-b-lg #{if @selected_token == token, do: "bg-purple-50"}"}
                          >
                            <img src={Map.get(@token_logos, token, "https://ik.imagekit.io/blockster/blockster-icon.png")} alt={token} class="w-5 h-5 rounded-full flex-shrink-0" />
                            <span class={"font-medium flex-1 text-left whitespace-nowrap #{if @selected_token == token, do: "text-purple-600", else: "text-gray-900"}"}><%= token %></span>
                            <%= if token == "ROGUE" and Map.get(@balances, "ROGUE", 0) == 0 do %>
                              <a href="https://app.uniswap.org/explore/pools/arbitrum/0x9876d52d698ffad55fef13f4d631c0300cf2dc8ef90c8dd70405dc06fa10b2ec" target="_blank" class="text-purple-600 text-xs hover:underline cursor-pointer" phx-click="hide_token_dropdown">Buy</a>
                            <% else %>
                              <span class="text-gray-500 text-sm whitespace-nowrap"><%= format_balance(Map.get(@balances, token, 0)) %></span>
                            <% end %>
                          </button>
                        <% end %>
                      </div>
                    <% end %>
                  </div>
                  <button
                    type="button"
                    phx-click="set_max_bet"
                    class="px-4 py-3 bg-gray-100 text-gray-700 rounded-lg hover:bg-gray-200 transition-all cursor-pointer font-medium"
                  >
                    MAX
                  </button>
                </div>
                <p class="text-gray-500 text-sm mt-2 flex items-center gap-1">
                  Balance: <%= format_balance(Map.get(@balances, @selected_token, 0)) %>
                  <img src={Map.get(@token_logos, @selected_token, "https://ik.imagekit.io/blockster/blockster-icon.png")} alt={@selected_token} class="w-4 h-4 rounded-full inline" />
                  <%= @selected_token %>
                </p>
              </div>

              <!-- Potential Win Display -->
              <div class="bg-green-50 rounded-xl p-3 mb-4 border border-green-200">
                <div class="flex items-center justify-between">
                  <span class="text-gray-700 text-sm">Potential Win:</span>
                  <span class="text-xl font-bold text-green-600 flex items-center gap-2">
                    <img src={Map.get(@token_logos, @selected_token, "https://ik.imagekit.io/blockster/blockster-icon.png")} alt={@selected_token} class="w-5 h-5 rounded-full" />
                    <%= format_balance(@bet_amount * get_multiplier(@selected_difficulty)) %> <%= @selected_token %>
                  </span>
                </div>
              </div>

              <!-- Error Message -->
              <%= if @error_message do %>
                <div class="bg-red-50 border border-red-300 rounded-lg p-3 mb-4 text-red-700 text-sm">
                  <%= @error_message %>
                </div>
              <% end %>

              <!-- Prediction Selection Grid -->
              <div class="flex-1 flex flex-col">
                <div class="flex items-center justify-between mb-2">
                  <label class="block text-sm font-medium text-gray-700">
                    <%= if get_mode(@selected_difficulty) == :win_one do %>
                      Make your predictions (win if any of <%= get_predictions_needed(@selected_difficulty) %> flips match)
                    <% else %>
                      Make your predictions (<%= get_predictions_needed(@selected_difficulty) %> flip<%= if get_predictions_needed(@selected_difficulty) > 1, do: "s" %>)
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
                        class="absolute right-0 top-full mt-1 z-50 w-80 bg-white rounded-lg p-3 border border-gray-200 shadow-lg text-left overflow-hidden"
                      >
                        <p class="text-xs text-gray-600 mb-2">
                          This hash commits the server to a result BEFORE you place your bet.
                          After the game, you can verify the result was fair.
                        </p>
                        <div class="flex items-start gap-2 overflow-hidden">
                          <code class="text-xs font-mono bg-gray-50 px-2 py-1.5 rounded border border-gray-200 text-gray-700 overflow-wrap-anywhere" style="word-break: break-all;">
                            <%= @server_seed_hash %>
                          </code>
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
                        </div>
                        <p class="text-xs text-gray-400 mt-2">
                          Game #<%= @nonce %>
                        </p>
                      </div>
                    <% end %>
                  </div>
                </div>
                <div class="flex-1 flex items-center justify-center">
                  <div class="flex gap-2 justify-center">
                    <%= for i <- 1..get_predictions_needed(@selected_difficulty) do %>
                      <button
                        type="button"
                        phx-click="toggle_prediction"
                        phx-value-index={i}
                        class={"w-16 h-16 rounded-full flex items-center justify-center transition-all cursor-pointer shadow-md #{case Enum.at(@predictions, i - 1) do
                          :heads -> "casino-chip-heads"
                          :tails -> "casino-chip-tails"
                          _ -> "bg-gray-200 text-gray-500 hover:bg-gray-300"
                        end}"}
                      >
                          <%= case Enum.at(@predictions, i - 1) do %>
                          <% :heads -> %>
                            <div class="w-10 h-10 rounded-full bg-coin-heads flex items-center justify-center border-2 border-white shadow-inner">
                              <span class="text-2xl">🚀</span>
                            </div>
                          <% :tails -> %>
                            <div class="w-10 h-10 rounded-full bg-gray-700 flex items-center justify-center border-2 border-white shadow-inner">
                              <span class="text-2xl">💩</span>
                            </div>
                          <% _ -> %><%= i %>
                        <% end %>
                      </button>
                    <% end %>
                  </div>
                </div>
              </div>

              <!-- Start Game Button -->
              <div class="mt-4">
                <button
                  type="button"
                  phx-click="start_game"
                  disabled={length(@predictions) != get_predictions_needed(@selected_difficulty)}
                  class="w-full py-4 bg-black text-white font-bold text-lg rounded-xl hover:bg-gray-800 transition-all cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed"
                >
                <%= if length(@predictions) == get_predictions_needed(@selected_difficulty) do %>
                  Place Bet
                <% else %>
                  <%= if get_mode(@selected_difficulty) == :win_one do %>
                    Select Heads or Tails
                  <% else %>
                    Select all <%= get_predictions_needed(@selected_difficulty) %> predictions
                  <% end %>
                <% end %>
                </button>
              </div>

            <% else %>
              <!-- Game in Progress -->
              <div class="text-center flex-1 flex flex-col">
                <!-- Prediction vs Result Display -->
                <div class="mb-4">
                  <div class="flex justify-center gap-2 mb-2">
                    <%= for i <- 1..get_predictions_needed(@selected_difficulty) do %>
                      <div class="text-center">
                        <!-- Prediction -->
                        <div class={"w-20 h-20 mx-auto rounded-full flex items-center justify-center mb-1 #{if Enum.at(@predictions, i - 1) == :heads, do: "casino-chip-heads", else: "casino-chip-tails"}"}>
                          <div class={"w-12 h-12 rounded-full flex items-center justify-center border-2 border-white shadow-inner #{if Enum.at(@predictions, i - 1) == :heads, do: "bg-coin-heads", else: "bg-gray-700"}"}>
                            <span class="text-3xl"><%= if Enum.at(@predictions, i - 1) == :heads, do: "🚀", else: "💩" %></span>
                          </div>
                        </div>
                        <!-- Result indicator -->
                        <%= cond do %>
                          <% (@game_state == :result and i <= @current_flip and Enum.at(@results, i - 1) != nil) or
                             (i < @current_flip) or (i == @current_flip and @game_state == :showing_result) -> %>
                            <% result = Enum.at(@results, i - 1) %>
                            <% matched = result == Enum.at(@predictions, i - 1) %>
                            <div class={"w-20 h-20 mx-auto rounded-full flex items-center justify-center #{if result == :heads, do: "casino-chip-heads", else: "casino-chip-tails"} #{if matched, do: "ring-[3px] ring-green-500", else: "ring-[3px] ring-red-500"}"}>
                              <div class={"w-12 h-12 rounded-full flex items-center justify-center border-2 border-white shadow-inner #{if result == :heads, do: "bg-coin-heads", else: "bg-gray-700"}"}>
                                <span class="text-3xl"><%= if result == :heads, do: "🚀", else: "💩" %></span>
                              </div>
                            </div>
                          <% i == @current_flip and @game_state == :flipping -> %>
                            <div class="w-20 h-20 mx-auto rounded-full flex items-center justify-center bg-purple-500 animate-pulse">
                              <span class="text-white text-3xl font-bold">?</span>
                            </div>
                          <% true -> %>
                            <div class="w-20 h-20 mx-auto rounded-full flex items-center justify-center bg-gray-100">
                              <span class="text-gray-400 text-xl">-</span>
                            </div>
                        <% end %>
                      </div>
                    <% end %>
                  </div>
                </div>

                <!-- Bet Amount Display (shown during flipping/showing_result) -->
                <%= if @game_state in [:flipping, :showing_result] do %>
                  <div class="mb-4 text-center">
                    <p class="text-gray-500 text-sm">Bet</p>
                    <p class="text-xl font-bold text-gray-900 flex items-center justify-center gap-2">
                      <img src={Map.get(@token_logos, @selected_token, "https://ik.imagekit.io/blockster/blockster-icon.png")} alt={@selected_token} class="w-5 h-5 rounded-full" />
                      <span><%= format_balance(@current_bet) %></span>
                      <span class="text-gray-600"><%= @selected_token %></span>
                    </p>
                  </div>
                <% end %>

                <%= if @game_state == :flipping do %>
                  <!-- Coin Flip Animation -->
                  <div class="mb-6" id={"coin-flip-#{@flip_id}"} phx-hook="CoinFlip" data-result={Enum.at(@results, @current_flip - 1)}>
                    <div class="coin-container mx-auto w-24 h-24 relative perspective-1000">
                      <div class={"coin w-full h-full absolute #{if Enum.at(@results, @current_flip - 1) == :heads, do: "animate-flip-heads", else: "animate-flip-tails"}"}>
                        <!-- Heads chip -->
                        <div class="coin-face coin-heads absolute w-full h-full rounded-full flex items-center justify-center backface-hidden casino-chip-heads">
                          <div class="w-16 h-16 rounded-full bg-coin-heads flex items-center justify-center border-4 border-white shadow-inner">
                            <span class="text-4xl">🚀</span>
                          </div>
                        </div>
                        <!-- Tails chip -->
                        <div class="coin-face coin-tails absolute w-full h-full rounded-full flex items-center justify-center backface-hidden rotate-y-180 casino-chip-tails">
                          <div class="w-16 h-16 rounded-full bg-gray-700 flex items-center justify-center border-4 border-white shadow-inner">
                            <span class="text-4xl">💩</span>
                          </div>
                        </div>
                      </div>
                    </div>
                  </div>
                <% end %>

                <%= if @game_state == :showing_result do %>
                  <!-- Show coin result for 1 second -->
                  <div class="mb-6">
                    <div class="coin-container mx-auto w-24 h-24 relative perspective-1000">
                      <!-- Static coin showing the result -->
                      <div class="w-full h-full absolute" style={"transform-style: preserve-3d; transform: rotateY(#{if Enum.at(@results, @current_flip - 1) == :heads, do: "0deg", else: "180deg"})"}>
                        <!-- Heads chip -->
                        <div class="coin-face coin-heads absolute w-full h-full rounded-full flex items-center justify-center backface-hidden casino-chip-heads">
                          <div class="w-16 h-16 rounded-full bg-coin-heads flex items-center justify-center border-4 border-white shadow-inner">
                            <span class="text-4xl">🚀</span>
                          </div>
                        </div>
                        <!-- Tails chip -->
                        <div class="coin-face coin-tails absolute w-full h-full rounded-full flex items-center justify-center backface-hidden rotate-y-180 casino-chip-tails">
                          <div class="w-16 h-16 rounded-full bg-gray-700 flex items-center justify-center border-4 border-white shadow-inner">
                            <span class="text-4xl">💩</span>
                          </div>
                        </div>
                      </div>
                    </div>
                    <p class="mt-3 text-sm">
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
                  <div class="mb-6 relative">
                    <%= if @won do %>
                      <!-- Win content with scale-in and shake animation - emoji on side -->
                      <div class="win-celebration win-shake flex items-center justify-center gap-4">
                        <div class="animate-bounce" style="font-size: 50px; line-height: 1;">🎉</div>
                        <div class="text-center">
                          <h2 class="text-3xl font-bold text-green-600 mb-1 animate-pulse">YOU WON!</h2>
                          <p class="text-2xl text-gray-900 flex items-center justify-center gap-2">
                            <img src={Map.get(@token_logos, @selected_token, "https://ik.imagekit.io/blockster/blockster-icon.png")} alt={@selected_token} class="w-6 h-6 rounded-full" />
                            <span class="text-green-600 font-bold"><%= format_balance(@payout) %></span>
                            <span><%= @selected_token %></span>
                          </p>
                        </div>
                        <div class="animate-bounce" style="font-size: 50px; line-height: 1;">🎉</div>
                      </div>
                    <% else %>
                      <!-- Loss content -->
                      <div>
                        <p class="text-xl text-gray-900 flex items-center justify-center gap-2">
                          <img src={Map.get(@token_logos, @selected_token, "https://ik.imagekit.io/blockster/blockster-icon.png")} alt={@selected_token} class="w-5 h-5 rounded-full" />
                          <span class="text-red-600 font-bold">-<%= format_balance(@bet_amount) %></span>
                          <span><%= @selected_token %></span>
                        </p>
                      </div>
                    <% end %>
                  </div>

                  <!-- Play Again & Verify Buttons -->
                  <div class="mt-auto flex flex-col items-center gap-2">
                    <button
                      type="button"
                      phx-click="reset_game"
                      class="px-8 py-3 bg-black text-white font-bold rounded-xl hover:bg-gray-800 transition-all cursor-pointer animate-fade-in"
                    >
                      Play Again
                    </button>
                    <button
                      type="button"
                      phx-click="show_fairness_modal"
                      class="text-xs text-gray-500 hover:text-gray-700 flex items-center gap-1 cursor-pointer"
                    >
                      <svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
                      </svg>
                      Verify Fairness
                    </button>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>

        <!-- Stats & History -->
        <div class="grid md:grid-cols-2 gap-4 mt-6">
          <!-- User Stats -->
          <div class="bg-white rounded-xl p-4 shadow-sm border border-gray-200">
            <h3 class="text-sm font-bold text-gray-900 mb-3">Your Stats (<%= @selected_token %>)</h3>
            <%= if @user_stats do %>
              <div class="space-y-1 text-xs">
                <div class="flex justify-between">
                  <span class="text-gray-600">Total Games</span>
                  <span class="text-gray-900"><%= @user_stats.total_games %></span>
                </div>
                <div class="flex justify-between">
                  <span class="text-gray-600">Win Rate</span>
                  <span class="text-gray-900"><%= calculate_win_rate(@user_stats) %>%</span>
                </div>
                <div class="flex justify-between">
                  <span class="text-gray-600">Net Profit/Loss</span>
                  <span class={if @user_stats.total_won - @user_stats.total_lost >= 0, do: "text-green-600", else: "text-red-600"}>
                    <%= format_profit(@user_stats.total_won - @user_stats.total_lost) %>
                  </span>
                </div>
                <div class="flex justify-between">
                  <span class="text-gray-600">Biggest Win</span>
                  <span class="text-green-600"><%= format_balance(@user_stats.biggest_win) %></span>
                </div>
              </div>
            <% else %>
              <p class="text-gray-500 text-xs">No games played yet with <%= @selected_token %></p>
            <% end %>
          </div>

          <!-- Recent Games -->
          <div class="bg-white rounded-xl p-4 shadow-sm border border-gray-200">
            <h3 class="text-sm font-bold text-gray-900 mb-3">Recent Games</h3>
            <%= if length(@recent_games) > 0 do %>
              <div class="space-y-1 text-xs max-h-32 overflow-y-auto">
                <%= for game <- @recent_games do %>
                  <div class={"flex justify-between items-center p-1.5 rounded #{if game.won, do: "bg-green-50", else: "bg-red-50"}"}>
                    <div class="flex items-center gap-1.5">
                      <img src={Map.get(@token_logos, game.token_type, "https://ik.imagekit.io/blockster/blockster-icon.png")} alt={game.token_type} class="w-4 h-4 rounded-full" />
                      <span class="text-gray-600"><%= game.token_type %></span>
                      <span class="text-gray-900"><%= game.multiplier %>x</span>
                    </div>
                    <span class={"flex items-center gap-1 #{if game.won, do: "text-green-600", else: "text-red-600"}"}>
                      <%= if game.won, do: "+", else: "-" %><%= format_balance(if game.won, do: game.payout, else: game.bet_amount) %>
                      <img src={Map.get(@token_logos, game.token_type, "https://ik.imagekit.io/blockster/blockster-icon.png")} alt={game.token_type} class="w-3.5 h-3.5 rounded-full" />
                    </span>
                  </div>
                <% end %>
              </div>
            <% else %>
              <p class="text-gray-500 text-xs">No games played yet</p>
            <% end %>
          </div>
        </div>
      </div>
    </div>

    <!-- Fairness Verification Modal -->
    <%= if @show_fairness_modal and @fairness_game do %>
      <div class="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4" phx-click="hide_fairness_modal">
        <div class="bg-white rounded-2xl max-w-lg w-full max-h-[90vh] overflow-y-auto shadow-xl" phx-click="stop_propagation">
          <!-- Header -->
          <div class="p-4 border-b flex items-center justify-between bg-gray-50 rounded-t-2xl">
            <div class="flex items-center gap-2">
              <svg class="w-5 h-5 text-green-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
              </svg>
              <h2 class="text-lg font-bold text-gray-900">Provably Fair Verification</h2>
            </div>
            <button type="button" phx-click="hide_fairness_modal" class="text-gray-400 hover:text-gray-600 cursor-pointer">
              <svg class="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>

          <!-- Content -->
          <div class="p-4 space-y-4">
            <!-- Bet Details -->
            <div class="bg-blue-50 rounded-lg p-3 border border-blue-200">
              <p class="text-sm font-medium text-blue-800 mb-2">Your Bet Details</p>
              <p class="text-xs text-blue-600 mb-2">These player-controlled values derive your client seed:</p>
              <div class="grid grid-cols-2 gap-2 text-sm">
                <div class="text-blue-600">User ID:</div>
                <div class="font-mono text-xs"><%= @fairness_game.user_id %></div>
                <div class="text-blue-600">Bet Amount:</div>
                <div><%= @fairness_game.bet_amount %></div>
                <div class="text-blue-600">Token:</div>
                <div><%= @fairness_game.token %></div>
                <div class="text-blue-600">Difficulty:</div>
                <div><%= @fairness_game.difficulty %></div>
                <div class="text-blue-600">Predictions:</div>
                <div><%= @fairness_game.predictions_str %></div>
              </div>
            </div>

            <!-- Nonce -->
            <div class="bg-gray-50 rounded-lg p-3">
              <div class="flex justify-between items-center">
                <span class="text-sm text-gray-600">Game Nonce:</span>
                <span class="font-mono text-sm"><%= @fairness_game.nonce %></span>
              </div>
              <p class="text-xs text-gray-500 mt-1">
                Ensures unique results even for identical bets
              </p>
            </div>

            <!-- Seeds -->
            <div class="space-y-3">
              <div>
                <label class="text-sm font-medium text-gray-700">Server Seed (revealed)</label>
                <code class="mt-1 text-xs font-mono bg-gray-100 px-2 py-2 rounded break-all block">
                  <%= @fairness_game.server_seed %>
                </code>
              </div>

              <div>
                <label class="text-sm font-medium text-gray-700">Server Commitment (shown before bet)</label>
                <code class="mt-1 text-xs font-mono bg-gray-100 px-2 py-2 rounded break-all block">
                  <%= @fairness_game.server_seed_hash %>
                </code>
              </div>

              <div>
                <label class="text-sm font-medium text-gray-700">Client Seed (derived from bet details)</label>
                <code class="mt-1 text-xs font-mono bg-gray-100 px-2 py-2 rounded break-all block">
                  <%= @fairness_game.client_seed %>
                </code>
                <p class="text-xs text-gray-500 mt-1">
                  = SHA256("<%= @fairness_game.client_seed_input %>")
                </p>
              </div>

              <div>
                <label class="text-sm font-medium text-gray-700">Combined Seed</label>
                <code class="mt-1 text-xs font-mono bg-gray-100 px-2 py-2 rounded break-all block">
                  <%= @fairness_game.combined_seed %>
                </code>
                <p class="text-xs text-gray-500 mt-1">
                  = SHA256(server_seed + ":" + client_seed + ":" + nonce)
                </p>
              </div>
            </div>

            <!-- Verification Steps -->
            <div class="bg-green-50 rounded-lg p-3 border border-green-200">
              <p class="text-sm font-medium text-green-800 mb-2">Verification Steps</p>
              <ol class="text-sm text-green-700 space-y-1 list-decimal ml-4">
                <li>SHA256(server_seed) = commitment</li>
                <li>client_seed = SHA256(bet_details)</li>
                <li>combined_seed = SHA256(server_seed:client_seed:nonce)</li>
                <li>Results derived from combined seed bytes</li>
              </ol>
            </div>

            <!-- Flip Results Breakdown -->
            <div>
              <p class="text-sm font-medium text-gray-700 mb-2">Flip Results</p>
              <div class="space-y-2">
                <%= for {result, i} <- Enum.with_index(@fairness_game.results) do %>
                  <div class="flex items-center justify-between text-sm bg-gray-50 p-2 rounded">
                    <span>Flip <%= i + 1 %>:</span>
                    <div class="flex items-center gap-2">
                      <span class="font-mono text-xs">byte[<%= i %>] = <%= Enum.at(@fairness_game.bytes, i) %></span>
                      <span class={if Enum.at(@fairness_game.bytes, i) < 128, do: "text-amber-600", else: "text-gray-600"}>
                        <%= if result == :heads, do: "🚀 Heads", else: "💩 Tails" %>
                      </span>
                      <span class="text-xs text-gray-400">
                        (<%= if Enum.at(@fairness_game.bytes, i) < 128, do: "< 128", else: ">= 128" %>)
                      </span>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>

            <!-- External Verification -->
            <div class="border-t pt-4">
              <p class="text-sm font-medium text-gray-700 mb-2">Verify Externally</p>
              <p class="text-xs text-gray-500 mb-3">
                Click each link to verify using an online SHA256 calculator:
              </p>
              <div class="space-y-3">
                <div class="bg-gray-50 rounded-lg p-3">
                  <p class="text-xs text-gray-600 mb-1">1. Verify server commitment</p>
                  <a href={"https://md5calc.com/hash/sha256/#{@fairness_game.server_seed}"} target="_blank" class="text-blue-500 hover:underline text-xs cursor-pointer">
                    SHA256(server_seed) → Click to verify
                  </a>
                  <p class="text-xs text-gray-400 mt-1 font-mono break-all">Expected: <%= @fairness_game.server_seed_hash %></p>
                </div>

                <div class="bg-gray-50 rounded-lg p-3">
                  <p class="text-xs text-gray-600 mb-1">2. Derive client seed from bet details</p>
                  <a href={"https://md5calc.com/hash/sha256/#{@fairness_game.client_seed_input}"} target="_blank" class="text-blue-500 hover:underline text-xs cursor-pointer">
                    SHA256(bet_details) → Click to verify
                  </a>
                  <p class="text-xs text-gray-400 mt-1 font-mono break-all">Expected: <%= @fairness_game.client_seed %></p>
                </div>

                <div class="bg-gray-50 rounded-lg p-3">
                  <p class="text-xs text-gray-600 mb-1">3. Generate combined seed</p>
                  <a href={"https://md5calc.com/hash/sha256/#{@fairness_game.server_seed}:#{@fairness_game.client_seed}:#{@fairness_game.nonce}"} target="_blank" class="text-blue-500 hover:underline text-xs cursor-pointer">
                    SHA256(server:client:nonce) → Click to verify
                  </a>
                  <p class="text-xs text-gray-400 mt-1 font-mono break-all">Expected: <%= @fairness_game.combined_seed %></p>
                </div>

                <div class="bg-gray-50 rounded-lg p-3">
                  <p class="text-xs text-gray-600 mb-1">4. Convert hex to bytes for flip results</p>
                  <p class="text-xs text-gray-500 mb-2">
                    Each pair of hex chars = 1 byte. First <%= length(@fairness_game.results) %> bytes determine flips:
                  </p>
                  <div class="bg-white rounded p-2 border">
                    <%= for {byte, i} <- Enum.with_index(@fairness_game.bytes) do %>
                      <div class={"flex items-center justify-between text-xs py-1 #{if i > 0, do: "border-t border-gray-100"}"}>
                        <span class="font-mono text-gray-500">
                          byte[<%= i %>] = 0x<%= String.slice(@fairness_game.combined_seed, i * 2, 2) %> = <%= byte %>
                        </span>
                        <span class={if byte < 128, do: "text-amber-600", else: "text-gray-600"}>
                          <%= if byte < 128, do: "< 128 → Heads", else: ">= 128 → Tails" %>
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
    user_stats = load_user_stats(socket.assigns.current_user.id, token)

    {:noreply,
     socket
     |> assign(selected_token: token)
     |> assign(user_stats: user_stats)
     |> assign(show_token_dropdown: false)
     |> assign(error_message: nil)}
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
    {:noreply,
     socket
     |> assign(selected_difficulty: new_level)
     |> assign(predictions: List.duplicate(nil, predictions_needed))
     |> assign(results: [])
     |> assign(game_state: :idle)
     |> assign(current_flip: 0)
     |> assign(won: nil)
     |> assign(payout: 0)
     |> assign(error_message: nil)
     |> assign(confetti_pieces: [])}
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
    balance = Map.get(socket.assigns.balances, socket.assigns.selected_token, 0)
    max_bet = trunc(balance)
    {:noreply, assign(socket, bet_amount: max(1, max_bet), error_message: nil)}
  end

  @impl true
  def handle_event("halve_bet", _params, socket) do
    new_amount = max(1, div(socket.assigns.bet_amount, 2))
    {:noreply, assign(socket, bet_amount: new_amount, error_message: nil)}
  end

  @impl true
  def handle_event("double_bet", _params, socket) do
    balance = Map.get(socket.assigns.balances, socket.assigns.selected_token, 0)
    max_bet = trunc(balance)
    new_amount = min(max_bet, socket.assigns.bet_amount * 2)
    {:noreply, assign(socket, bet_amount: max(1, new_amount), error_message: nil)}
  end

  @impl true
  def handle_event("start_game", _params, socket) do
    balance = Map.get(socket.assigns.balances, socket.assigns.selected_token, 0)
    bet_amount = socket.assigns.bet_amount
    predictions = socket.assigns.predictions
    predictions_needed = get_predictions_needed(socket.assigns.selected_difficulty)

    # Validate all predictions are made
    all_predictions_made =
      length(predictions) == predictions_needed and
        Enum.all?(predictions, fn p -> p in [:heads, :tails] end)

    cond do
      not all_predictions_made ->
        {:noreply, assign(socket, error_message: "Please make all #{predictions_needed} predictions")}

      bet_amount <= 0 ->
        {:noreply, assign(socket, error_message: "Bet amount must be greater than 0")}

      bet_amount > balance ->
        {:noreply, assign(socket, error_message: "Insufficient #{socket.assigns.selected_token} balance")}

      true ->
        # Generate client seed DETERMINISTICALLY from player's bet choices
        client_seed = ProvablyFair.generate_client_seed(
          socket.assigns.current_user.id,
          bet_amount,
          socket.assigns.selected_token,
          socket.assigns.selected_difficulty,
          predictions
        )

        # Generate results using provably fair method
        combined_seed = ProvablyFair.generate_combined_seed(
          socket.assigns.server_seed,
          client_seed,
          socket.assigns.nonce
        )
        results = ProvablyFair.generate_results(combined_seed, predictions_needed)

        # Start the sequential flip process with flip_id starting at 1
        # current_bet tracks the doubling bet for win_all mode (4x, 8x, 16x, 32x)
        socket =
          socket
          |> assign(results: results)
          |> assign(game_state: :flipping)
          |> assign(current_flip: 1)
          |> assign(flip_id: 1)
          |> assign(won: nil)
          |> assign(payout: 0)
          |> assign(current_bet: bet_amount)
          |> assign(error_message: nil)

        {:noreply, socket}
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
  def handle_event("reset_game", _params, socket) do
    # Refresh balances and stats
    balances = EngagementTracker.get_user_token_balances(socket.assigns.current_user.id)
    user_stats = load_user_stats(socket.assigns.current_user.id, socket.assigns.selected_token)
    recent_games = load_recent_games(socket.assigns.current_user.id)
    predictions_needed = get_predictions_needed(socket.assigns.selected_difficulty)

    # Generate fresh server seed for next game
    server_seed = ProvablyFair.generate_server_seed()
    server_seed_hash = ProvablyFair.generate_commitment(server_seed)
    new_nonce = socket.assigns.nonce + 1

    {:noreply,
     socket
     |> assign(game_state: :idle)
     |> assign(current_flip: 0)
     |> assign(predictions: List.duplicate(nil, predictions_needed))
     |> assign(results: [])
     |> assign(won: nil)
     |> assign(payout: 0)
     |> assign(balances: balances)
     |> assign(user_stats: user_stats)
     |> assign(recent_games: recent_games)
     |> assign(server_seed: server_seed)
     |> assign(server_seed_hash: server_seed_hash)
     |> assign(nonce: new_nonce)
     |> assign(confetti_pieces: [])
     |> assign(show_fairness_modal: false)
     |> assign(fairness_game: nil)}
  end

  @impl true
  def handle_event("show_fairness_modal", _params, socket) do
    # Build the bet details string (same format used for hashing)
    predictions_str =
      socket.assigns.predictions
      |> Enum.map(&Atom.to_string/1)
      |> Enum.join(",")

    client_seed_input = ProvablyFair.build_client_seed_input(
      socket.assigns.current_user.id,
      socket.assigns.bet_amount,
      socket.assigns.selected_token,
      socket.assigns.selected_difficulty,
      socket.assigns.predictions
    )

    # Derive client seed from bet details
    client_seed = ProvablyFair.generate_client_seed(
      socket.assigns.current_user.id,
      socket.assigns.bet_amount,
      socket.assigns.selected_token,
      socket.assigns.selected_difficulty,
      socket.assigns.predictions
    )

    # Build fairness game data for current game
    combined_seed = ProvablyFair.generate_combined_seed(
      socket.assigns.server_seed,
      client_seed,
      socket.assigns.nonce
    )

    bytes = ProvablyFair.get_result_bytes(combined_seed, length(socket.assigns.results))

    fairness_game = %{
      game_id: "#{socket.assigns.current_user.id}_#{socket.assigns.nonce}",
      # Bet details (player-controlled only)
      user_id: socket.assigns.current_user.id,
      bet_amount: socket.assigns.bet_amount,
      token: socket.assigns.selected_token,
      difficulty: socket.assigns.selected_difficulty,
      predictions_str: predictions_str,
      nonce: socket.assigns.nonce,
      # Seeds
      server_seed: socket.assigns.server_seed,
      server_seed_hash: socket.assigns.server_seed_hash,
      client_seed_input: client_seed_input,
      client_seed: client_seed,
      combined_seed: combined_seed,
      # Results
      results: socket.assigns.results,
      bytes: bytes,
      won: socket.assigns.won
    }

    {:noreply,
     socket
     |> assign(show_fairness_modal: true)
     |> assign(fairness_game: fairness_game)}
  end

  @impl true
  def handle_event("hide_fairness_modal", _params, socket) do
    {:noreply, assign(socket, show_fairness_modal: false)}
  end

  @impl true
  def handle_event("stop_propagation", _params, socket) do
    # This event stops click propagation to prevent modal backdrop from closing
    {:noreply, socket}
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
    mode = get_mode(socket.assigns.selected_difficulty)

    Logger.info("[BuxBooster] show_final_result - mode: #{mode}, predictions: #{inspect(predictions)}, results: #{inspect(results)}")

    # Determine win based on mode
    # Only check results up to current_flip (not pre-generated future results)
    results_to_check = Enum.take(results, current_flip)
    predictions_to_check = Enum.take(predictions, current_flip)

    won = case mode do
      :win_one ->
        # Player wins if ANY flip was correct
        Enum.zip(predictions_to_check, results_to_check)
        |> Enum.any?(fn {pred, res} -> pred == res end)

      :win_all ->
        # Player wins only if ALL flips were correct
        Enum.zip(predictions_to_check, results_to_check)
        |> Enum.all?(fn {pred, res} -> pred == res end)
    end

    Logger.info("[BuxBooster] won: #{won}")

    if won do
      # Player wins
      multiplier = get_multiplier(socket.assigns.selected_difficulty)
      payout = socket.assigns.bet_amount * multiplier
      save_game_result(socket, true, payout)

      # Refresh stats and recent games immediately
      user_stats = load_user_stats(user_id, token_type)
      recent_games = load_recent_games(user_id)

      # Generate confetti data for the win animation
      confetti_pieces = generate_confetti_data(100)

      {:noreply,
       socket
       |> assign(game_state: :result)
       |> assign(won: true)
       |> assign(payout: payout)
       |> assign(user_stats: user_stats)
       |> assign(recent_games: recent_games)
       |> assign(confetti_pieces: confetti_pieces)}
    else
      # Player loses
      save_game_result(socket, false)

      # Refresh stats and recent games immediately
      user_stats = load_user_stats(user_id, token_type)
      recent_games = load_recent_games(user_id)

      {:noreply,
       socket
       |> assign(game_state: :result)
       |> assign(won: false)
       |> assign(payout: 0)
       |> assign(user_stats: user_stats)
       |> assign(recent_games: recent_games)}
    end
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

  defp format_balance(amount) when is_float(amount), do: :erlang.float_to_binary(amount, decimals: 2)
  defp format_balance(amount) when is_integer(amount), do: Integer.to_string(amount)
  defp format_balance(_), do: "0"

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
      socket.assigns.server_seed,
      socket.assigns.server_seed_hash,
      socket.assigns.nonce
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

  defp load_recent_games(user_id) do
    # Query recent games from Mnesia using dirty index read
    # Get last 10 games
    :mnesia.dirty_index_read(:bux_booster_games, user_id, :user_id)
    |> Enum.sort_by(fn record -> elem(record, 11) end, :desc)
    |> Enum.take(10)
    |> Enum.map(fn record ->
      %{
        game_id: elem(record, 1),
        token_type: elem(record, 3),
        bet_amount: elem(record, 4),
        multiplier: elem(record, 6),
        won: elem(record, 9),
        payout: elem(record, 10),
        # Provably fair fields (may be nil for old games)
        server_seed: safe_elem(record, 12),
        server_seed_hash: safe_elem(record, 13),
        nonce: safe_elem(record, 14)
      }
    end)
  rescue
    _ -> []
  catch
    :exit, _ -> []
  end

  # Safe tuple element access for backwards compatibility with old records
  defp safe_elem(tuple, index) when tuple_size(tuple) > index, do: elem(tuple, index)
  defp safe_elem(_tuple, _index), do: nil

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
