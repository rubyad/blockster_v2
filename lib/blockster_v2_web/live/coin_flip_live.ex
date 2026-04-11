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

      socket =
        socket
        |> assign(:play_sidebar_left_banners, load_play_sidebar_banners(socket, "play_sidebar_left"))
        |> assign(:play_sidebar_right_banners, load_play_sidebar_banners(socket, "play_sidebar_right"))

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
        |> assign(:play_sidebar_left_banners, load_play_sidebar_banners(socket, "play_sidebar_left"))
        |> assign(:play_sidebar_right_banners, load_play_sidebar_banners(socket, "play_sidebar_right"))
        |> start_async(:fetch_house_balance, fn -> fetch_house_balance_async("SOL", 1) end)

      {:ok, socket}
    end
  end

  defp load_play_sidebar_banners(socket, placement) do
    if connected?(socket),
      do: BlocksterV2.Ads.list_active_banners_by_placement(placement),
      else: []
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="coin-flip-game"
      class="min-h-screen bg-[#fafaf9]"
      phx-hook="CoinFlipSolana"
      data-game-id={assigns[:onchain_game_id]}
      data-commitment-hash={assigns[:commitment_hash]}
    >
      <BlocksterV2Web.DesignSystem.header
        current_user={@current_user}
        active="play"
        bux_balance={Map.get(assigns, :bux_balance, 0)}
        token_balances={Map.get(assigns, :token_balances, %{})}
        cart_item_count={Map.get(assigns, :cart_item_count, 0)}
        unread_notification_count={Map.get(assigns, :unread_notification_count, 0)}
        notification_dropdown_open={Map.get(assigns, :notification_dropdown_open, false)}
        recent_notifications={Map.get(assigns, :recent_notifications, [])}
        search_query={Map.get(assigns, :search_query, "")}
        search_results={Map.get(assigns, :search_results, [])}
        show_search_results={Map.get(assigns, :show_search_results, false)}
        connecting={Map.get(assigns, :connecting, false)}
        show_why_earn_bux={true}
        display_token="SOL"
      />

      <main class="max-w-[1280px] mx-auto px-6">
        <%!-- ══════════════════════════════════════════════════════
             PAGE HEADER + LIVE STATS BAR
        ══════════════════════════════════════════════════════ --%>
        <section id="ds-play-hero" class="pt-12 pb-8">
          <div class="grid grid-cols-12 gap-8 items-end">
            <div class="col-span-12 md:col-span-7">
              <BlocksterV2Web.DesignSystem.eyebrow class="mb-3">
                Provably-fair · On-chain · Sub-1% house edge
              </BlocksterV2Web.DesignSystem.eyebrow>
              <h1 class="text-[60px] md:text-[80px] mb-3 leading-[0.96] font-bold tracking-[-0.022em] text-[#141414]">Coin Flip</h1>
              <p class="text-[16px] leading-[1.5] text-neutral-600 max-w-[520px]">
                Pick a side, place a bet, watch it settle on chain in under a second. Every flip is verifiable. Every payout is funded by the public bankroll.
              </p>
            </div>
            <div class="col-span-12 md:col-span-5">
              <div class="grid grid-cols-3 gap-3">
                <div class="bg-white rounded-2xl border border-neutral-200/70 p-4 text-right shadow-[0_1px_3px_rgba(0,0,0,0.04)]">
                  <div class="text-[9px] uppercase tracking-[0.14em] text-neutral-500 mb-1">SOL Pool</div>
                  <div class="font-mono font-bold text-[18px] text-[#141414]">
                    <%= if @selected_token == "SOL", do: format_balance(@house_balance), else: "—" %>
                  </div>
                  <.link navigate={~p"/pool/sol"} class="text-[10px] text-[#22C55E] font-mono hover:underline">View pool ↗</.link>
                </div>
                <div class="bg-white rounded-2xl border border-neutral-200/70 p-4 text-right shadow-[0_1px_3px_rgba(0,0,0,0.04)]">
                  <div class="text-[9px] uppercase tracking-[0.14em] text-neutral-500 mb-1">BUX Pool</div>
                  <div class="font-mono font-bold text-[18px] text-[#141414]">
                    <%= if @selected_token == "BUX", do: format_balance(@house_balance), else: "—" %>
                  </div>
                  <.link navigate={~p"/pool/bux"} class="text-[10px] text-[#22C55E] font-mono hover:underline">View pool ↗</.link>
                </div>
                <div class="bg-white rounded-2xl border border-neutral-200/70 p-4 text-right shadow-[0_1px_3px_rgba(0,0,0,0.04)]">
                  <div class="text-[9px] uppercase tracking-[0.14em] text-neutral-500 mb-1">House Edge</div>
                  <div class="font-mono font-bold text-[18px] text-[#141414]">0.92<span class="text-[12px] text-neutral-500">%</span></div>
                  <span class="text-[10px] text-neutral-500 font-mono">verified</span>
                </div>
              </div>
            </div>
          </div>
        </section>

        <%!-- Expired bet reclaim banner --%>
        <%= if @has_expired_bet do %>
          <div class="mb-6 bg-amber-50 border border-amber-200 rounded-2xl px-5 py-4 flex items-center justify-between gap-3">
            <div class="flex items-center gap-2 text-sm text-amber-800">
              <svg class="w-4 h-4 text-amber-500 shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" /></svg>
              <span>You have a stuck bet older than 5 minutes.</span>
            </div>
            <button type="button" phx-click="reclaim_stuck_bet" class="shrink-0 px-4 py-2 bg-[#0a0a0a] text-white text-xs font-bold rounded-full hover:bg-[#1a1a22] transition-all cursor-pointer">
              Reclaim
            </button>
          </div>
        <% end %>

        <%!-- ══════════════════════════════════════════════════════
             GAME CARD + SIDEBAR (3-state conditional)
        ══════════════════════════════════════════════════════ --%>
        <section id="ds-play-game" class="pb-8">
          <div class="grid grid-cols-12 gap-6 items-start">

            <%!-- ─── GAME CARD (col-span-8) ─── --%>
            <div class={[
              "col-span-12 lg:col-span-8 bg-white rounded-2xl overflow-hidden",
              cond do
                @game_state == :result and @won == true -> "border border-[#22C55E]/30 shadow-[0_30px_60px_-20px_rgba(34,197,94,0.20)] relative"
                @game_state == :result and @won == false -> "border border-[#EF4444]/25 shadow-[0_30px_60px_-20px_rgba(239,68,68,0.15)]"
                true -> "border border-neutral-200/70 shadow-[0_1px_3px_rgba(0,0,0,0.04)]"
              end
            ]}>

              <%= if @game_state == :idle do %>
                <%!-- STATE 1: Place bet --%>

                <%!-- Token selector + balance row --%>
                <div class="px-6 pt-5 pb-4 border-b border-neutral-100 flex items-center justify-between flex-wrap gap-3">
                  <div class="flex items-center gap-2">
                    <%= for token <- @tokens do %>
                      <button
                        type="button"
                        phx-click="select_token"
                        phx-value-token={token}
                        class={[
                          "flex items-center gap-2 px-3 py-2 rounded-full text-[12px] font-bold transition-colors cursor-pointer",
                          if(@selected_token == token, do: "bg-[#0a0a0a] text-white", else: "bg-white border border-neutral-200 text-neutral-500 hover:border-[#141414] hover:text-[#141414]")
                        ]}
                      >
                        <%= if token == "SOL" do %>
                          <div class="w-4 h-4 rounded-full grid place-items-center" style="background: linear-gradient(135deg, #00FFA3 0%, #00DC82 100%);">
                            <span class="text-black font-bold text-[6px]">SOL</span>
                          </div>
                        <% else %>
                          <img src="https://ik.imagekit.io/blockster/blockster-icon.png" alt="BUX" class="w-4 h-4 rounded-full" />
                        <% end %>
                        <%= token %>
                      </button>
                    <% end %>
                  </div>
                  <div class="flex items-center gap-4 text-[11px]">
                    <div>
                      <span class="text-neutral-500">Your balance: </span>
                      <span class="font-mono font-bold text-[#141414]">
                        <%= format_balance(Map.get(@balances, @selected_token, 0)) %> <%= @selected_token %>
                      </span>
                    </div>
                    <div>
                      <span class="text-neutral-500">House: </span>
                      <.link navigate={~p"/pool/#{String.downcase(@selected_token)}"} class="font-mono font-bold text-[#141414] hover:text-[#22C55E] transition-colors">
                        <%= format_balance(@house_balance) %> <%= @selected_token %> ↗
                      </.link>
                    </div>
                  </div>
                </div>

                <%!-- Difficulty selector --%>
                <div class="px-6 pt-5 pb-2">
                  <div class="flex items-center justify-between mb-3">
                    <div class="text-[10px] font-bold uppercase tracking-[0.14em] text-neutral-500">Difficulty</div>
                    <div class="text-[10px] text-neutral-500 hidden sm:block">Higher difficulty = bigger payout · lower odds</div>
                  </div>
                  <div id="difficulty-grid" class="grid grid-cols-5 md:grid-cols-9 gap-1.5">
                    <%= for opt <- @difficulty_options do %>
                      <% is_active = @selected_difficulty == opt.level %>
                      <button
                        type="button"
                        phx-click="select_difficulty"
                        phx-value-level={opt.level}
                        class={[
                          "py-2.5 px-1 rounded-xl border text-center transition-all cursor-pointer",
                          if(is_active, do: "bg-[#0a0a0a] border-[#0a0a0a] text-white", else: "bg-white border-neutral-200 text-neutral-500 hover:border-[#141414] hover:text-[#141414]")
                        ]}
                      >
                        <span class={["block text-[8px] tracking-[0.1em] uppercase mb-0.5", if(is_active, do: "opacity-55", else: "opacity-55")]}>
                          <%= if opt.mode == :win_one, do: "Win one", else: "Win all" %>
                        </span>
                        <span class="block font-mono text-[13px] font-bold">
                          <%= opt.multiplier %>×
                        </span>
                        <span class={["block font-mono text-[9px] mt-0.5", if(is_active, do: "text-[#CAFC00]", else: "text-neutral-400")]}>
                          <%= opt.predictions %> flip<%= if opt.predictions > 1, do: "s" %>
                        </span>
                      </button>
                    <% end %>
                  </div>
                </div>

                <%!-- Bet amount --%>
                <div class="px-6 pt-6 pb-2">
                  <div class="flex items-center justify-between mb-3">
                    <div class="text-[10px] font-bold uppercase tracking-[0.14em] text-neutral-500">Bet amount</div>
                    <div class="flex items-center gap-1.5">
                      <button type="button" phx-click="halve_bet" class="px-2.5 py-1 rounded-full bg-neutral-100 border border-neutral-200 font-mono text-[10px] font-bold text-neutral-500 hover:border-[#141414] hover:text-[#141414] hover:bg-white transition-all cursor-pointer">½</button>
                      <button type="button" phx-click="double_bet" class="px-2.5 py-1 rounded-full bg-neutral-100 border border-neutral-200 font-mono text-[10px] font-bold text-neutral-500 hover:border-[#141414] hover:text-[#141414] hover:bg-white transition-all cursor-pointer">2×</button>
                      <button type="button" phx-click="set_max_bet" class="px-2.5 py-1 rounded-full bg-[#0a0a0a] border border-[#0a0a0a] font-mono text-[10px] font-bold text-[#CAFC00] cursor-pointer">
                        MAX <%= format_bet_amount(@max_bet) %>
                      </button>
                    </div>
                  </div>
                  <div class="bg-neutral-50 border border-neutral-200 rounded-2xl px-5 py-4 flex items-center gap-3">
                    <input
                      type="text"
                      inputmode="decimal"
                      value={format_bet_amount(@bet_amount)}
                      phx-keyup="update_bet_amount"
                      phx-debounce="150"
                      autocomplete="off"
                      class="flex-1 min-w-0 bg-transparent border-0 font-mono text-[28px] font-bold text-[#141414] tracking-[-0.02em] focus:outline-none"
                    />
                    <div class="text-[14px] text-neutral-500"><%= @selected_token %></div>
                  </div>
                  <%!-- Quick presets --%>
                  <div class="flex items-center gap-2 mt-3 flex-wrap">
                    <%= for preset <- stake_presets(@selected_token) do %>
                      <button
                        type="button"
                        phx-click="set_preset"
                        phx-value-amount={preset}
                        class={[
                          "px-2.5 py-1 rounded-full border font-mono text-[10px] font-bold transition-all cursor-pointer",
                          if(@bet_amount == preset, do: "bg-[#0a0a0a] border-[#0a0a0a] text-white", else: "bg-neutral-100 border-neutral-200 text-neutral-500 hover:border-[#141414] hover:text-[#141414] hover:bg-white")
                        ]}
                      >
                        <%= format_bet_amount(preset) %>
                      </button>
                    <% end %>
                  </div>
                </div>

                <%!-- Potential profit --%>
                <div class="px-6 pt-5">
                  <div class="bg-[#22C55E]/[0.08] border border-[#22C55E]/25 rounded-2xl p-5 flex items-center justify-between">
                    <div>
                      <div class="text-[10px] font-bold uppercase tracking-[0.14em] text-[#15803d] mb-1">Potential profit</div>
                      <div class="font-mono font-bold text-[28px] text-[#15803d] leading-none">
                        + <%= format_balance(@bet_amount * get_multiplier(@selected_difficulty) - @bet_amount) %> <%= @selected_token %>
                      </div>
                      <div class="text-[11px] text-[#15803d]/70 mt-1">
                        Total payout: <%= format_balance(@bet_amount * get_multiplier(@selected_difficulty)) %> <%= @selected_token %>
                      </div>
                    </div>
                    <div class="text-right">
                      <div class="text-[10px] font-bold uppercase tracking-[0.14em] text-[#15803d]/70 mb-1">Multiplier</div>
                      <div class="font-mono font-bold text-[36px] text-[#15803d] leading-none"><%= get_multiplier(@selected_difficulty) %>×</div>
                    </div>
                  </div>
                </div>

                <%!-- Error message --%>
                <%= if @error_message do %>
                  <div class="px-6 pt-4">
                    <div class="bg-red-50 border border-red-200 rounded-xl p-3 text-red-700 text-xs">
                      <%= @error_message %>
                    </div>
                  </div>
                <% end %>

                <%!-- Prediction selectors --%>
                <div class="px-6 pt-6">
                  <div class="flex items-center justify-between mb-3 gap-2">
                    <div class="text-[10px] font-bold uppercase tracking-[0.14em] text-neutral-500">
                      Pick your side · <%= get_predictions_needed(@selected_difficulty) %> flip<%= if get_predictions_needed(@selected_difficulty) > 1, do: "s" %>
                      <%= if get_mode(@selected_difficulty) == :win_one, do: " · win one", else: " · win all" %>
                    </div>
                    <div class="text-[10px] text-neutral-500 max-w-[220px] text-right hidden sm:block">
                      Click a coin to cycle through 🚀 / 💩. SHA256(server:client:nonce) determines every flip.
                    </div>
                  </div>
                  <% num_flips = get_predictions_needed(@selected_difficulty) %>
                  <% sizes = get_prediction_size_classes(num_flips) %>
                  <div class="flex items-center justify-center gap-3 flex-wrap">
                    <%= for i <- 1..num_flips do %>
                      <button
                        type="button"
                        phx-click="toggle_prediction"
                        phx-value-index={i}
                        class={[
                          sizes.outer,
                          "rounded-full flex items-center justify-center transition-all cursor-pointer shadow-md",
                          case Enum.at(@predictions, i - 1) do
                            :heads -> "casino-chip-heads"
                            :tails -> "casino-chip-tails"
                            _ -> "bg-white border-2 border-dashed border-neutral-300 hover:border-[#141414]"
                          end
                        ]}
                      >
                        <%= case Enum.at(@predictions, i - 1) do %>
                          <% :heads -> %>
                            <div class={[sizes.inner, "rounded-full bg-coin-heads flex items-center justify-center border-2 border-white shadow-inner"]}>
                              <span class={sizes.emoji}>🚀</span>
                            </div>
                          <% :tails -> %>
                            <div class={[sizes.inner, "rounded-full bg-gray-700 flex items-center justify-center border-2 border-white shadow-inner"]}>
                              <span class={sizes.emoji}>💩</span>
                            </div>
                          <% _ -> %>
                            <span class="text-neutral-400 text-sm font-bold"><%= i %></span>
                        <% end %>
                      </button>
                    <% end %>
                  </div>
                </div>

                <%!-- Provably fair details --%>
                <div class="px-6 pt-5 pb-2">
                  <details class="bg-neutral-50 border border-neutral-200 rounded-xl">
                    <summary class="cursor-pointer px-4 py-3 flex items-center justify-between list-none">
                      <div class="flex items-center gap-2">
                        <div class="w-1.5 h-1.5 rounded-full bg-[#22C55E] pulse-dot"></div>
                        <span class="text-[11px] font-bold text-[#141414]">Provably fair · Server seed locked</span>
                      </div>
                      <span class="text-[10px] text-neutral-500">View commitment hash</span>
                    </summary>
                    <div class="px-4 pb-4 border-t border-neutral-200 mt-2 pt-3 space-y-2">
                      <div class="flex items-center justify-between text-[10px] font-mono gap-3">
                        <span class="text-neutral-500 shrink-0">Server commitment</span>
                        <%= if @server_seed_hash do %>
                          <span class="text-[#141414] truncate" title={@server_seed_hash}>
                            <%= String.slice(@server_seed_hash, 0, 8) %>…<%= String.slice(@server_seed_hash, -6, 6) %>
                          </span>
                          <button
                            type="button"
                            id="copy-server-hash"
                            phx-hook="CopyToClipboard"
                            data-copy-text={@server_seed_hash}
                            class="shrink-0 p-1 text-neutral-400 hover:text-neutral-600 hover:bg-neutral-100 rounded cursor-pointer transition-colors"
                            title="Copy hash"
                          >
                            <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z" />
                            </svg>
                          </button>
                        <% else %>
                          <span class="text-neutral-400 italic">locking...</span>
                        <% end %>
                      </div>
                      <div class="flex items-center justify-between text-[10px] font-mono">
                        <span class="text-neutral-500">Game nonce</span>
                        <span class="text-[#141414]">#<%= @nonce %></span>
                      </div>
                      <div class="text-[10px] text-neutral-500 mt-2">After settlement the server seed is revealed so you can independently verify the result.</div>
                    </div>
                  </details>
                </div>

                <%!-- Place bet button --%>
                <div class="p-6">
                  <button
                    type="button"
                    phx-click="start_game"
                    disabled={Enum.any?(@predictions, &is_nil/1)}
                    class="w-full bg-[#0a0a0a] text-white py-4 rounded-2xl text-[15px] font-bold hover:bg-[#1a1a22] transition-colors flex items-center justify-center gap-2 cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed"
                  >
                    <%= if Enum.all?(@predictions, &(!is_nil(&1))) do %>
                      Place Bet · <%= format_bet_amount(@bet_amount) %> <%= @selected_token %>
                      <svg class="w-4 h-4" viewBox="0 0 20 20" fill="none"><path d="M3 10h12m0 0l-4-4m4 4l-4 4" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>
                    <% else %>
                      <%= if get_predictions_needed(@selected_difficulty) == 1 do %>
                        Make your prediction
                      <% else %>
                        Select all <%= get_predictions_needed(@selected_difficulty) %> predictions
                      <% end %>
                    <% end %>
                  </button>
                </div>

              <% end %>

              <%= if @game_state in [:awaiting_tx, :flipping, :showing_result] do %>
                <%!-- STATE 2: Bet in progress --%>

                <%!-- Locked bet header --%>
                <div class="px-6 pt-5 pb-4 border-b border-neutral-100 flex items-center justify-between flex-wrap gap-3">
                  <div class="flex items-center gap-3">
                    <%= if @selected_token == "SOL" do %>
                      <div class="w-9 h-9 rounded-full grid place-items-center" style="background: linear-gradient(135deg, #00FFA3 0%, #00DC82 100%);">
                        <span class="text-black font-bold text-[10px]">SOL</span>
                      </div>
                    <% else %>
                      <img src="https://ik.imagekit.io/blockster/blockster-icon.png" alt="BUX" class="w-9 h-9 rounded-full" />
                    <% end %>
                    <div>
                      <div class="text-[10px] uppercase tracking-[0.14em] text-neutral-500">Bet placed</div>
                      <div class="font-mono font-bold text-[20px] text-[#141414] leading-none"><%= format_balance(@current_bet) %> <%= @selected_token %></div>
                    </div>
                  </div>
                  <div class="flex items-center gap-3 text-[11px]">
                    <div class="text-neutral-500">Multiplier <span class="font-mono font-bold text-[#141414]"><%= get_multiplier(@selected_difficulty) %>×</span></div>
                    <div class="text-neutral-500">Potential <span class="font-mono font-bold text-[#22C55E]">+ <%= format_balance(@current_bet * get_multiplier(@selected_difficulty) - @current_bet) %> <%= @selected_token %></span></div>
                  </div>
                </div>

                <%!-- Spinning coin area --%>
                <div class="px-6 pt-12 pb-8 grid place-items-center relative">
                  <div class="absolute inset-0 pointer-events-none">
                    <div class="absolute top-8 left-12 w-32 h-32 bg-[#facc15]/15 rounded-full blur-3xl"></div>
                    <div class="absolute bottom-8 right-12 w-40 h-40 bg-[#7D00FF]/10 rounded-full blur-3xl"></div>
                  </div>
                  <% num_flips = get_predictions_needed(@selected_difficulty) %>
                  <% big_sizes = get_coin_size_classes(1) %>
                  <div class="relative">
                    <%= if @game_state == :awaiting_tx do %>
                      <div class="w-44 h-44 rounded-full grid place-items-center bg-purple-100 animate-pulse">
                        <svg class="w-16 h-16 text-purple-600 animate-spin" fill="none" viewBox="0 0 24 24">
                          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                          <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                        </svg>
                      </div>
                    <% end %>
                    <%= if @game_state == :flipping do %>
                      <div class={["coin-container", big_sizes.outer, "relative perspective-1000"]} id={"coin-flip-#{@flip_id}"} phx-hook="CoinFlip" data-flip-index={@current_flip}>
                        <div class="coin w-full h-full absolute animate-flip-continuous" style="transform-style: preserve-3d;">
                          <div class="coin-face coin-heads absolute w-full h-full rounded-full flex items-center justify-center backface-hidden casino-chip-heads">
                            <div class={[big_sizes.inner, "rounded-full bg-coin-heads flex items-center justify-center border-2 border-white shadow-inner"]}>
                              <span class={big_sizes.emoji}>🚀</span>
                            </div>
                          </div>
                          <div class="coin-face coin-tails absolute w-full h-full rounded-full flex items-center justify-center backface-hidden rotate-y-180 casino-chip-tails">
                            <div class={[big_sizes.inner, "rounded-full bg-gray-700 flex items-center justify-center border-2 border-white shadow-inner"]}>
                              <span class={big_sizes.emoji}>💩</span>
                            </div>
                          </div>
                        </div>
                      </div>
                    <% end %>
                    <%= if @game_state == :showing_result do %>
                      <% result = Enum.at(@results, @current_flip - 1) %>
                      <div class={["coin-container", big_sizes.outer, "relative perspective-1000"]}>
                        <div class="w-full h-full absolute" style={"transform-style: preserve-3d; transform: rotateY(#{if result == :heads, do: "0deg", else: "180deg"});"}>
                          <div class="coin-face coin-heads absolute w-full h-full rounded-full flex items-center justify-center backface-hidden casino-chip-heads">
                            <div class={[big_sizes.inner, "rounded-full bg-coin-heads flex items-center justify-center border-2 border-white shadow-inner"]}>
                              <span class={big_sizes.emoji}>🚀</span>
                            </div>
                          </div>
                          <div class="coin-face coin-tails absolute w-full h-full rounded-full flex items-center justify-center backface-hidden rotate-y-180 casino-chip-tails">
                            <div class={[big_sizes.inner, "rounded-full bg-gray-700 flex items-center justify-center border-2 border-white shadow-inner"]}>
                              <span class={big_sizes.emoji}>💩</span>
                            </div>
                          </div>
                        </div>
                      </div>
                    <% end %>
                    <div class="absolute -inset-4 rounded-full border-2 border-dashed border-neutral-200 animate-spin" style="animation-duration: 8s;"></div>
                  </div>
                  <div class="mt-8 text-center">
                    <div class="text-[10px] font-bold uppercase tracking-[0.16em] text-[#141414] flex items-center justify-center gap-2">
                      <span class="w-1.5 h-1.5 rounded-full bg-[#22C55E] pulse-dot"></span>
                      <%= cond do %>
                        <% @game_state == :awaiting_tx -> %> Confirming transaction
                        <% @game_state == :showing_result -> %> Flip <%= @current_flip %> of <%= num_flips %>
                        <% true -> %> Flipping coin · <%= @current_flip %> of <%= num_flips %>
                      <% end %>
                    </div>
                    <div class="text-[12px] text-neutral-500 mt-1.5">Confirming on Solana · ~0.4s</div>
                  </div>
                </div>

                <%!-- Predictions / results stacked --%>
                <div class="px-6 pt-2 pb-6">
                  <div class="bg-neutral-50 border border-neutral-200 rounded-2xl p-5 space-y-5">
                    <% mini_sizes = %{outer: "w-12 h-12", inner: "w-8 h-8", emoji: "text-lg"} %>
                    <div>
                      <div class="text-[10px] font-bold uppercase tracking-[0.14em] text-neutral-500 mb-3 text-center">Your predictions</div>
                      <div class="flex items-center justify-center gap-3 flex-wrap">
                        <%= for i <- 1..num_flips do %>
                          <% pred = Enum.at(@predictions, i - 1) %>
                          <div class={[mini_sizes.outer, "rounded-full flex items-center justify-center shadow-md", if(pred == :heads, do: "casino-chip-heads", else: "casino-chip-tails")]}>
                            <div class={[mini_sizes.inner, "rounded-full flex items-center justify-center border-2 border-white shadow-inner", if(pred == :heads, do: "bg-coin-heads", else: "bg-gray-700")]}>
                              <span class={mini_sizes.emoji}><%= if pred == :heads, do: "🚀", else: "💩" %></span>
                            </div>
                          </div>
                        <% end %>
                      </div>
                    </div>
                    <div>
                      <div class="text-[10px] font-bold uppercase tracking-[0.14em] text-neutral-500 mb-3 text-center">Results</div>
                      <div class="flex items-center justify-center gap-3 flex-wrap">
                        <%= for i <- 1..num_flips do %>
                          <% result = Enum.at(@results, i - 1) %>
                          <% pred = Enum.at(@predictions, i - 1) %>
                          <% revealed = (i < @current_flip) or (i == @current_flip and @game_state == :showing_result) %>
                          <%= if revealed and result != nil do %>
                            <% matched = result == pred %>
                            <div class={[mini_sizes.outer, "rounded-full flex items-center justify-center shadow-md ring-2 ring-offset-2 ring-offset-neutral-50", if(result == :heads, do: "casino-chip-heads", else: "casino-chip-tails"), if(matched, do: "ring-[#22C55E]", else: "ring-[#EF4444]")]}>
                              <div class={[mini_sizes.inner, "rounded-full flex items-center justify-center border-2 border-white shadow-inner", if(result == :heads, do: "bg-coin-heads", else: "bg-gray-700")]}>
                                <span class={mini_sizes.emoji}><%= if result == :heads, do: "🚀", else: "💩" %></span>
                              </div>
                            </div>
                          <% else %>
                            <div class={[mini_sizes.outer, "rounded-full flex items-center justify-center bg-white border-2 border-dashed border-neutral-300"]}>
                              <span class="text-neutral-400 text-sm">?</span>
                            </div>
                          <% end %>
                        <% end %>
                      </div>
                    </div>
                  </div>
                </div>

                <%!-- Tx status strip --%>
                <div class="border-t border-neutral-100 bg-neutral-50/70 px-6 py-3">
                  <div class="flex items-center justify-between text-[10px] font-mono">
                    <div class="flex items-center gap-2">
                      <span class="w-1 h-1 rounded-full bg-[#22C55E]"></span>
                      <span class="text-neutral-500">Tx submitted </span>
                      <%= if @bet_sig do %>
                        <a href={"https://solscan.io/tx/#{@bet_sig}?cluster=devnet"} target="_blank" class="text-[#141414] hover:underline">· <%= String.slice(@bet_sig, 0, 4) %>…<%= String.slice(@bet_sig, -4, 4) %> ↗</a>
                      <% end %>
                    </div>
                    <div class="flex items-center gap-1.5">
                      <div class="w-1 h-1 rounded-full bg-[#22C55E]"></div>
                      <div class="w-1 h-1 rounded-full bg-[#22C55E]"></div>
                      <div class="w-1 h-1 rounded-full bg-neutral-300 pulse-dot"></div>
                      <span class="text-neutral-500 ml-1">Settling…</span>
                    </div>
                  </div>
                </div>

              <% end %>

              <%= if @game_state == :result do %>
                <%!-- STATE 3: Result (win or loss) --%>

                <%= if @won and length(@confetti_pieces) > 0 do %>
                  <div class="confetti-fullpage fixed inset-0 pointer-events-none z-50 overflow-hidden">
                    <%= for piece <- @confetti_pieces do %>
                      <div class="confetti-emoji" style={"--x-start: #{piece.x_start}%; --x-end: #{piece.x_end}%; --x-drift: #{piece.x_drift}vw; --rotation: #{piece.rotation}deg; --delay: #{piece.delay}ms; --duration: #{piece.duration}ms;"}><%= piece.emoji %></div>
                    <% end %>
                  </div>
                <% end %>

                <%!-- Win / Loss banner --%>
                <%= if @won do %>
                  <div class="bg-gradient-to-r from-[#22C55E]/12 via-[#CAFC00]/15 to-[#22C55E]/12 border-b border-[#22C55E]/25 px-6 py-6 text-center">
                    <div class="text-[10px] font-bold uppercase tracking-[0.18em] text-[#15803d] mb-2">You Won</div>
                    <div class="font-mono font-bold text-[56px] md:text-[64px] text-[#15803d] leading-none tracking-tight">
                      + <%= format_balance(@payout - @current_bet) %> <%= @selected_token %>
                    </div>
                    <div class="text-[12px] text-[#15803d]/70 mt-2">
                      Total payout <%= format_balance(@payout) %> <%= @selected_token %> · <%= get_multiplier(@selected_difficulty) %>× multiplier
                    </div>
                  </div>
                <% else %>
                  <div class="bg-gradient-to-r from-[#EF4444]/8 to-[#EF4444]/8 border-b border-[#EF4444]/20 px-6 py-6 text-center">
                    <div class="text-[10px] font-bold uppercase tracking-[0.18em] text-[#7f1d1d] mb-2">No win this time</div>
                    <div class="font-mono font-bold text-[40px] md:text-[48px] text-[#7f1d1d] leading-none tracking-tight">
                      − <%= format_balance(@current_bet) %> <%= @selected_token %>
                    </div>
                    <div class="text-[12px] text-[#7f1d1d]/70 mt-2">Stake returned to bankroll</div>
                  </div>
                <% end %>

                <%!-- Predictions vs Results grid (large) --%>
                <% num_flips = get_predictions_needed(@selected_difficulty) %>
                <% big_sizes = %{outer: "w-14 h-14 sm:w-16 sm:h-16", inner: "w-10 h-10 sm:w-12 sm:h-12", emoji: "text-xl sm:text-2xl"} %>
                <div class="px-6 pt-8 pb-6 space-y-6">
                  <div>
                    <div class="text-[10px] font-bold uppercase tracking-[0.14em] text-neutral-500 mb-3 text-center">Your predictions</div>
                    <div class="flex items-center justify-center gap-3 flex-wrap">
                      <%= for i <- 1..num_flips do %>
                        <% pred = Enum.at(@predictions, i - 1) %>
                        <div class={[big_sizes.outer, "rounded-full flex items-center justify-center shadow-md", if(pred == :heads, do: "casino-chip-heads", else: "casino-chip-tails")]}>
                          <div class={[big_sizes.inner, "rounded-full flex items-center justify-center border-2 border-white shadow-inner", if(pred == :heads, do: "bg-coin-heads", else: "bg-gray-700")]}>
                            <span class={big_sizes.emoji}><%= if pred == :heads, do: "🚀", else: "💩" %></span>
                          </div>
                        </div>
                      <% end %>
                    </div>
                  </div>
                  <div>
                    <div class={["text-[10px] font-bold uppercase tracking-[0.14em] mb-3 text-center", if(@won, do: "text-[#15803d]", else: "text-[#7f1d1d]")]}>
                      Results
                    </div>
                    <div class="flex items-center justify-center gap-3 flex-wrap">
                      <%= for i <- 1..num_flips do %>
                        <% result = Enum.at(@results, i - 1) %>
                        <% pred = Enum.at(@predictions, i - 1) %>
                        <%= if result do %>
                          <% matched = result == pred %>
                          <div class={[big_sizes.outer, "rounded-full flex items-center justify-center shadow-md ring-2 ring-offset-2 ring-offset-white", if(result == :heads, do: "casino-chip-heads", else: "casino-chip-tails"), if(matched, do: "ring-[#22C55E]", else: "ring-[#EF4444]")]}>
                            <div class={[big_sizes.inner, "rounded-full flex items-center justify-center border-2 border-white shadow-inner", if(result == :heads, do: "bg-coin-heads", else: "bg-gray-700")]}>
                              <span class={big_sizes.emoji}><%= if result == :heads, do: "🚀", else: "💩" %></span>
                            </div>
                          </div>
                        <% else %>
                          <div class={[big_sizes.outer, "rounded-full flex items-center justify-center bg-neutral-100"]}>
                            <span class="text-neutral-400">-</span>
                          </div>
                        <% end %>
                      <% end %>
                    </div>
                  </div>
                </div>

                <%!-- Settlement status + actions --%>
                <div class="px-6 pb-6">
                  <div class={[
                    "rounded-2xl p-5 flex items-center justify-between flex-wrap gap-3",
                    if(@won, do: "bg-[#22C55E]/[0.08] border border-[#22C55E]/25", else: "bg-neutral-50 border border-neutral-200")
                  ]}>
                    <div class="flex items-center gap-3">
                      <%= case @settlement_status do %>
                        <% :settled -> %>
                          <div class="w-9 h-9 rounded-full bg-[#22C55E] grid place-items-center">
                            <svg class="w-5 h-5 text-white" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>
                          </div>
                          <div>
                            <div class={["text-[10px] font-bold uppercase tracking-[0.14em] mb-0.5", if(@won, do: "text-[#15803d]", else: "text-neutral-500")]}>Settled on chain</div>
                            <%= if @settlement_sig do %>
                              <a href={"https://solscan.io/tx/#{@settlement_sig}?cluster=devnet"} target="_blank" class={["text-[12px] font-mono hover:underline", if(@won, do: "text-[#15803d]", else: "text-[#141414]")]}>
                                <%= String.slice(@settlement_sig, 0, 4) %>…<%= String.slice(@settlement_sig, -4, 4) %> ↗
                              </a>
                            <% end %>
                          </div>
                        <% :pending -> %>
                          <div class="w-9 h-9 rounded-full bg-neutral-200 grid place-items-center">
                            <svg class="w-5 h-5 text-neutral-600 animate-spin" fill="none" viewBox="0 0 24 24">
                              <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                              <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"></path>
                            </svg>
                          </div>
                          <div>
                            <div class="text-[10px] font-bold uppercase tracking-[0.14em] text-neutral-500 mb-0.5">Settling on chain</div>
                            <div class="text-[11px] text-neutral-500">This usually takes under a second</div>
                          </div>
                        <% :failed -> %>
                          <div class="w-9 h-9 rounded-full bg-amber-100 grid place-items-center">
                            <svg class="w-5 h-5 text-amber-600 animate-spin" fill="none" viewBox="0 0 24 24">
                              <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                              <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"></path>
                            </svg>
                          </div>
                          <div>
                            <div class="text-[10px] font-bold uppercase tracking-[0.14em] text-amber-700 mb-0.5">Retrying settlement</div>
                            <div class="text-[11px] text-amber-700/70">Auto-retry every 60s · reclaim available after 5 min</div>
                          </div>
                        <% _ -> %>
                      <% end %>
                    </div>
                    <div class="flex items-center gap-2">
                      <%= if @onchain_game_id do %>
                        <button type="button" phx-click="show_fairness_modal" phx-value-game-id={@onchain_game_id} class={[
                          "px-4 py-2.5 rounded-full text-[12px] font-bold transition-colors cursor-pointer border",
                          if(@won, do: "bg-white border-[#22C55E]/30 text-[#15803d] hover:border-[#15803d]", else: "bg-white border-neutral-300 text-neutral-700 hover:border-[#141414]")
                        ]}>
                          Verify fairness
                        </button>
                      <% end %>
                      <%= if @settlement_status == :settled do %>
                        <button type="button" phx-click="reset_game" class="bg-[#0a0a0a] text-white px-5 py-2.5 rounded-full text-[12px] font-bold hover:bg-[#1a1a22] transition-colors flex items-center gap-2 cursor-pointer">
                          <%= if @won, do: "Play again", else: "Try again" %>
                          <svg class="w-3.5 h-3.5" viewBox="0 0 20 20" fill="none"><path d="M3 10h12m0 0l-4-4m4 4l-4 4" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>
                        </button>
                      <% end %>
                    </div>
                  </div>
                </div>
              <% end %>

            </div>

            <%!-- ─── SIDEBAR (col-span-4) ─── --%>
            <div class="col-span-12 lg:col-span-4 space-y-4">

              <%= if @game_state == :idle do %>
                <%!-- Your stats card --%>
                <div class="bg-white rounded-2xl border border-neutral-200/70 shadow-[0_1px_3px_rgba(0,0,0,0.04)] p-5">
                  <div class="text-[10px] font-bold uppercase tracking-[0.14em] text-neutral-500 mb-4">Your stats</div>
                  <%= if @user_stats do %>
                    <div class="grid grid-cols-2 gap-3">
                      <div>
                        <div class="font-mono font-bold text-[20px] text-[#141414] leading-none"><%= @user_stats.total_games %></div>
                        <div class="text-[10px] text-neutral-500 mt-1 uppercase tracking-wider">Bets placed</div>
                      </div>
                      <div>
                        <div class="font-mono font-bold text-[20px] text-[#141414] leading-none">
                          <%= @user_stats.total_wins %><span class="text-[12px] text-neutral-400">/<%= @user_stats.total_games %></span>
                        </div>
                        <div class="text-[10px] text-neutral-500 mt-1 uppercase tracking-wider">
                          Win rate · <%= if @user_stats.total_games > 0, do: "#{round(@user_stats.total_wins / @user_stats.total_games * 100)}%", else: "—" %>
                        </div>
                      </div>
                      <div>
                        <% net = @user_stats.total_won - @user_stats.total_lost %>
                        <div class={["font-mono font-bold text-[20px] leading-none", if(net >= 0, do: "text-[#22C55E]", else: "text-[#EF4444]")]}>
                          <%= if net >= 0, do: "+ ", else: "− " %><%= format_balance(abs(net)) %>
                        </div>
                        <div class="text-[10px] text-neutral-500 mt-1 uppercase tracking-wider">Net <%= @selected_token %></div>
                      </div>
                      <div>
                        <div class="font-mono font-bold text-[20px] text-[#141414] leading-none"><%= format_balance(@user_stats.biggest_win) %></div>
                        <div class="text-[10px] text-neutral-500 mt-1 uppercase tracking-wider">Best win</div>
                      </div>
                    </div>
                  <% else %>
                    <div class="text-[11px] text-neutral-500">No stats yet. Place your first bet to start tracking.</div>
                  <% end %>
                </div>

                <%!-- Recent player activity (your own last 5) --%>
                <div class="bg-white rounded-2xl border border-neutral-200/70 shadow-[0_1px_3px_rgba(0,0,0,0.04)] overflow-hidden">
                  <div class="px-5 py-3 border-b border-neutral-100 flex items-center justify-between">
                    <div class="flex items-center gap-1.5">
                      <span class="w-1.5 h-1.5 rounded-full bg-[#22C55E] pulse-dot"></span>
                      <span class="text-[10px] font-bold uppercase tracking-[0.14em] text-neutral-500">Your recent games</span>
                    </div>
                    <span class="text-[9px] font-mono text-neutral-400">last 5</span>
                  </div>
                  <%= if Enum.empty?(@recent_games) do %>
                    <div class="px-5 py-8 text-[11px] text-neutral-400 text-center">No games yet</div>
                  <% else %>
                    <div class="divide-y divide-neutral-100">
                      <%= for game <- Enum.take(@recent_games, 5) do %>
                        <div class="px-5 py-3 flex items-center justify-between">
                          <div class="flex items-center gap-2">
                            <img src={if game.vault_type in ["sol", :sol], do: "https://ik.imagekit.io/blockster/solana-sol-logo.png", else: "https://ik.imagekit.io/blockster/blockster-icon.png"} class="w-5 h-5 rounded-full" />
                            <span class="text-[11px] font-mono text-neutral-500">
                              <%= format_balance(game.bet_amount) %> <%= String.upcase(to_string(game.vault_type)) %>
                            </span>
                          </div>
                          <div class="text-right">
                            <div class={["font-mono font-bold text-[12px]", if(game.won, do: "text-[#22C55E]", else: "text-[#EF4444]")]}>
                              <%= if game.won, do: "+ #{format_balance(game.payout - game.bet_amount)}", else: "− #{format_balance(game.bet_amount)}" %>
                            </div>
                            <div class="text-[9px] font-mono text-neutral-400"><%= game.multiplier %>×</div>
                          </div>
                        </div>
                      <% end %>
                    </div>
                  <% end %>
                </div>

                <%!-- Two modes legend --%>
                <div class="bg-neutral-50 border border-neutral-200/70 rounded-2xl p-5">
                  <div class="text-[10px] font-bold uppercase tracking-[0.14em] text-neutral-500 mb-3">Two modes</div>
                  <div class="space-y-3 text-[11px] text-neutral-600 leading-snug">
                    <div>
                      <div class="text-[#141414] font-bold text-[12px] mb-0.5">Win One</div>
                      <div>Win if <strong class="text-[#141414]">any one</strong> of N flips matches your prediction. Lower payout, much higher odds.</div>
                    </div>
                    <div>
                      <div class="text-[#141414] font-bold text-[12px] mb-0.5">Win All</div>
                      <div>Win only if <strong class="text-[#141414]">all N flips</strong> match. Higher payout, lower odds. 31.68× is a 5-in-a-row streak.</div>
                    </div>
                  </div>
                </div>

                <%!-- Sidebar ad banners (left + right merged into sidebar for redesign) --%>
                <%= for banner <- (@play_sidebar_left_banners ++ @play_sidebar_right_banners) do %>
                  <a href={banner.link_url} target="_blank" rel="noopener" class="block rounded-2xl overflow-hidden hover:shadow-lg transition-shadow cursor-pointer">
                    <img src={banner.image_url} alt={banner.name} class="w-full" loading="lazy" />
                  </a>
                <% end %>
              <% end %>

              <%= if @game_state in [:awaiting_tx, :flipping, :showing_result] do %>
                <%!-- This bet card --%>
                <div class="bg-white rounded-2xl border border-neutral-200/70 shadow-[0_1px_3px_rgba(0,0,0,0.04)] p-5">
                  <div class="text-[10px] font-bold uppercase tracking-[0.14em] text-neutral-500 mb-4">This bet</div>
                  <div class="space-y-3 text-[12px]">
                    <div class="flex items-center justify-between">
                      <span class="text-neutral-500">Token</span>
                      <span class="text-[#141414] font-bold"><%= @selected_token %></span>
                    </div>
                    <div class="flex items-center justify-between">
                      <span class="text-neutral-500">Stake</span>
                      <span class="font-mono font-bold text-[#141414]"><%= format_balance(@current_bet) %></span>
                    </div>
                    <div class="flex items-center justify-between">
                      <span class="text-neutral-500">Difficulty</span>
                      <span class="text-[#141414] font-bold">
                        <%= if get_mode(@selected_difficulty) == :win_one, do: "Win one", else: "Win all" %>
                        · <%= get_predictions_needed(@selected_difficulty) %> flip<%= if get_predictions_needed(@selected_difficulty) > 1, do: "s" %>
                      </span>
                    </div>
                    <div class="flex items-center justify-between">
                      <span class="text-neutral-500">Multiplier</span>
                      <span class="font-mono font-bold text-[#141414]"><%= get_multiplier(@selected_difficulty) %>×</span>
                    </div>
                    <div class="flex items-center justify-between pt-2 border-t border-neutral-100">
                      <span class="text-neutral-500">Potential payout</span>
                      <span class="font-mono font-bold text-[#22C55E]"><%= format_balance(@current_bet * get_multiplier(@selected_difficulty)) %> <%= @selected_token %></span>
                    </div>
                  </div>
                </div>

                <%!-- Provably fair live card --%>
                <div class="bg-white rounded-2xl border border-neutral-200/70 shadow-[0_1px_3px_rgba(0,0,0,0.04)] p-5">
                  <div class="flex items-center gap-1.5 mb-3">
                    <span class="w-1.5 h-1.5 rounded-full bg-[#22C55E] pulse-dot"></span>
                    <span class="text-[10px] font-bold uppercase tracking-[0.14em] text-neutral-500">Provably fair · Live</span>
                  </div>
                  <div class="space-y-2 text-[10px] font-mono">
                    <div class="flex items-center justify-between gap-3">
                      <span class="text-neutral-500 shrink-0">Commit hash</span>
                      <%= if @server_seed_hash do %>
                        <span class="text-[#141414] truncate" title={@server_seed_hash}>
                          <%= String.slice(@server_seed_hash, 0, 6) %>…<%= String.slice(@server_seed_hash, -4, 4) %>
                        </span>
                      <% else %>
                        <span class="text-neutral-400 italic">—</span>
                      <% end %>
                    </div>
                    <div class="flex items-center justify-between">
                      <span class="text-neutral-500">Game nonce</span>
                      <span class="text-[#141414]">#<%= @nonce %></span>
                    </div>
                    <div class="flex items-center justify-between">
                      <span class="text-neutral-500">Server seed</span>
                      <span class="text-neutral-400 italic">revealed at settlement</span>
                    </div>
                  </div>
                </div>
              <% end %>

              <%= if @game_state == :result do %>
                <div class="bg-white rounded-2xl border border-neutral-200/70 shadow-[0_1px_3px_rgba(0,0,0,0.04)] p-5">
                  <div class="text-[10px] font-bold uppercase tracking-[0.14em] text-neutral-500 mb-4">
                    <%= if @won, do: "Your stats updated", else: "Recap" %>
                  </div>
                  <%= if @won do %>
                    <%= if @user_stats do %>
                      <div class="space-y-3 text-[12px]">
                        <div class="flex items-center justify-between">
                          <span class="text-neutral-500">Net <%= @selected_token %></span>
                          <% net = @user_stats.total_won - @user_stats.total_lost %>
                          <span class={["font-mono font-bold", if(net >= 0, do: "text-[#22C55E]", else: "text-[#EF4444]")]}>
                            <%= if net >= 0, do: "+ ", else: "− " %><%= format_balance(abs(net)) %>
                          </span>
                        </div>
                        <div class="flex items-center justify-between">
                          <span class="text-neutral-500">Win streak</span>
                          <span class="font-mono font-bold text-[#141414]"><%= @user_stats.current_streak %></span>
                        </div>
                        <div class="flex items-center justify-between">
                          <span class="text-neutral-500">Bets placed</span>
                          <span class="font-mono font-bold text-[#141414]"><%= @user_stats.total_games %></span>
                        </div>
                        <div class="flex items-center justify-between">
                          <span class="text-neutral-500">Win rate</span>
                          <span class="font-mono font-bold text-[#141414]">
                            <%= if @user_stats.total_games > 0, do: "#{round(@user_stats.total_wins / @user_stats.total_games * 100)}%", else: "—" %>
                          </span>
                        </div>
                      </div>
                    <% end %>
                    <div class="mt-4 pt-4 border-t border-neutral-100">
                      <div class="text-[10px] uppercase tracking-[0.14em] text-neutral-500 mb-2">House contributed</div>
                      <div class="font-mono font-bold text-[14px] text-[#141414]">+ <%= format_balance(@payout - @current_bet) %> <%= @selected_token %> <span class="text-[10px] text-neutral-500">to your balance</span></div>
                    </div>
                  <% else %>
                    <p class="text-[12px] text-neutral-600 leading-[1.55]">
                      Your stake of <strong class="text-[#141414]"><%= format_balance(@current_bet) %> <%= @selected_token %></strong> was added to the bankroll. LP holders earn from your loss, just as you would earn from theirs if you held bSOL.
                    </p>
                    <.link navigate={~p"/pool"} class="inline-flex items-center gap-2 text-[11px] font-bold text-[#7D00FF] hover:text-[#5A00B8] transition-colors mt-3">
                      Become an LP →
                    </.link>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>
        </section>

        <%!-- ══════════════════════════════════════════════════════
             RECENT GAMES TABLE
        ══════════════════════════════════════════════════════ --%>
        <section id="ds-play-recent" class="pt-12 pb-12 border-t border-neutral-200/70 mt-8">
          <div class="flex items-baseline justify-between mb-6 flex-wrap gap-3">
            <div>
              <BlocksterV2Web.DesignSystem.eyebrow class="mb-1">Your last bets</BlocksterV2Web.DesignSystem.eyebrow>
              <h2 class="text-[28px] font-bold tracking-[-0.018em] text-[#141414]">Recent games</h2>
            </div>
          </div>

          <div class="bg-white rounded-2xl border border-neutral-200/70 shadow-[0_1px_3px_rgba(0,0,0,0.04)] overflow-hidden">
            <%= if assigns[:games_loading] do %>
              <div class="px-5 py-8 text-center text-neutral-400 text-[12px]">Loading games...</div>
            <% end %>
            <%= cond do %>
              <% !assigns[:games_loading] and Enum.empty?(@recent_games) -> %>
                <div class="px-5 py-8 text-center text-neutral-400 text-[12px]">No games played yet</div>
              <% length(@recent_games) > 0 -> %>
                <div id="recent-games-scroll" class="overflow-x-auto max-h-[520px] overflow-y-auto" phx-hook="InfiniteScroll">
                  <table class="w-full min-w-[720px]">
                    <thead class="sticky top-0 z-10 bg-neutral-50/70">
                      <tr class="border-b border-neutral-100 text-[10px] uppercase tracking-[0.14em] text-neutral-500 font-bold">
                        <th class="text-left px-5 py-3">#</th>
                        <th class="text-left px-5 py-3">Bet</th>
                        <th class="text-left px-5 py-3">Predictions</th>
                        <th class="text-left px-5 py-3">Results</th>
                        <th class="text-left px-5 py-3">Mult</th>
                        <th class="text-center px-5 py-3">W/L</th>
                        <th class="text-right px-5 py-3">P/L</th>
                        <th class="text-right px-5 py-3">Verify</th>
                      </tr>
                    </thead>
                    <tbody class="divide-y divide-neutral-100">
                      <%= for game <- @recent_games do %>
                        <tr id={"game-#{game.game_id}"} class={["hover:bg-neutral-50 transition-colors", if(game.won, do: "bg-[#22C55E]/[0.03]", else: "bg-[#EF4444]/[0.03]")]}>
                          <td class="px-5 py-3 font-mono text-[11px] text-neutral-500">
                            <%= if game.commitment_sig do %>
                              <a href={"https://solscan.io/tx/#{game.commitment_sig}?cluster=devnet"} target="_blank" class="hover:text-[#141414] hover:underline cursor-pointer">#<%= game.nonce %></a>
                            <% else %>
                              #<%= game.nonce %>
                            <% end %>
                          </td>
                          <td class="px-5 py-3">
                            <div class="flex items-center gap-1.5">
                              <img src={if game.vault_type in ["sol", :sol], do: "https://ik.imagekit.io/blockster/solana-sol-logo.png", else: "https://ik.imagekit.io/blockster/blockster-icon.png"} class="w-3.5 h-3.5 rounded-full" />
                              <span class="font-mono text-[12px] text-[#141414]"><%= format_balance(game.bet_amount) %></span>
                              <span class="text-[10px] text-neutral-500"><%= String.upcase(to_string(game.vault_type)) %></span>
                            </div>
                          </td>
                          <td class="px-5 py-3">
                            <div class="flex items-center gap-0.5">
                              <%= for pred <- (game.predictions || []) do %>
                                <span class="text-[14px]"><%= if pred == :heads, do: "🚀", else: "💩" %></span>
                              <% end %>
                            </div>
                          </td>
                          <td class="px-5 py-3">
                            <div class="flex items-center gap-0.5">
                              <%= for result <- (game.results || []) do %>
                                <span class="text-[14px]"><%= if result == :heads, do: "🚀", else: "💩" %></span>
                              <% end %>
                            </div>
                          </td>
                          <td class="px-5 py-3 font-mono text-[11px] text-[#141414]"><%= game.multiplier %>×</td>
                          <td class="px-5 py-3 text-center">
                            <%= if game.won do %>
                              <span class="bg-[#22C55E]/15 text-[#15803d] text-[10px] font-bold uppercase px-1.5 py-0.5 rounded-full">W</span>
                            <% else %>
                              <span class="bg-[#EF4444]/15 text-[#7f1d1d] text-[10px] font-bold uppercase px-1.5 py-0.5 rounded-full">L</span>
                            <% end %>
                          </td>
                          <td class="px-5 py-3 text-right">
                            <%= if game.settlement_sig do %>
                              <a href={"https://solscan.io/tx/#{game.settlement_sig}?cluster=devnet"} target="_blank" class={["font-mono font-bold text-[12px] hover:underline cursor-pointer", if(game.won, do: "text-[#22C55E]", else: "text-[#EF4444]")]}>
                                <%= if game.won, do: "+ #{format_balance(game.payout - game.bet_amount)}", else: "− #{format_balance(game.bet_amount)}" %> <%= String.upcase(to_string(game.vault_type)) %>
                              </a>
                            <% else %>
                              <span class={["font-mono font-bold text-[12px]", if(game.won, do: "text-[#22C55E]", else: "text-[#EF4444]")]}>
                                <%= if game.won, do: "+ #{format_balance(game.payout - game.bet_amount)}", else: "− #{format_balance(game.bet_amount)}" %> <%= String.upcase(to_string(game.vault_type)) %>
                              </span>
                            <% end %>
                          </td>
                          <td class="px-5 py-3 text-right">
                            <%= if game.server_seed && game.commitment_hash && game.nonce do %>
                              <button type="button" phx-click="show_fairness_modal" phx-value-game-id={game.game_id} class="text-[10px] text-neutral-400 hover:text-[#141414] font-mono cursor-pointer">✓</button>
                            <% else %>
                              <span class="text-[10px] text-neutral-300">—</span>
                            <% end %>
                          </td>
                        </tr>
                      <% end %>
                    </tbody>
                  </table>
                </div>
              <% true -> %>
            <% end %>
          </div>
        </section>
      </main>

      <BlocksterV2Web.DesignSystem.footer />
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
      @keyframes flip-continuous { 0% { transform: rotateY(0deg); } 100% { transform: rotateY(2520deg); } }
      .animate-flip-continuous { animation: flip-continuous 3s linear infinite; transform-style: preserve-3d; }
      @keyframes pulse-dot { 0%, 100% { opacity: 1; transform: scale(1); } 50% { opacity: 0.55; transform: scale(1.15); } }
      .pulse-dot { animation: pulse-dot 1.6s cubic-bezier(0.4, 0, 0.6, 1) infinite; }
      .confetti-fullpage { perspective: 1000px; }
      .confetti-emoji { position: absolute; font-size: 24px; left: var(--x-start); bottom: 40%; animation: confetti-burst var(--duration, 3s) cubic-bezier(0.25, 0.46, 0.45, 0.94) forwards; animation-delay: var(--delay, 0ms); opacity: 0; }
      @keyframes confetti-burst { 0% { opacity: 1; transform: translateY(0) translateX(0) rotate(0deg) scale(0.5); } 15% { opacity: 1; transform: translateY(-50vh) translateX(var(--x-drift)) rotate(calc(var(--rotation) * 0.4)) scale(1.2); } 100% { opacity: 1; transform: translateY(60vh) translateX(var(--x-drift)) rotate(var(--rotation)) scale(0.8); } }
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

  def handle_event("reclaim_stuck_bet", _params, socket) do
    user_id = socket.assigns.current_user.id
    wallet = socket.assigns.wallet_address
    bet_timeout = 300
    now = System.system_time(:second)

    # Find the expired placed bet
    expired_nonce = try do
      case :mnesia.dirty_index_read(:coin_flip_games, user_id, :user_id) do
        games when is_list(games) ->
          expired = games
          |> Enum.filter(fn record ->
            status = elem(record, 7)
            created_at = elem(record, 18)
            status == :placed and created_at != nil and (now - created_at) > bet_timeout
          end)
          |> Enum.sort_by(fn record -> elem(record, 18) end, :asc)
          |> List.first()

          if expired, do: elem(expired, 6), else: nil
        _ -> nil
      end
    rescue
      _ -> nil
    end

    if expired_nonce do
      Logger.info("[CoinFlip] Reclaiming stuck bet at nonce #{expired_nonce} for #{wallet}")
      {:noreply,
       socket
       |> assign(:error_message, "Building reclaim transaction...")
       |> start_async(:build_reclaim_tx, fn ->
         case BlocksterV2.BuxMinter.build_reclaim_expired_tx(wallet, expired_nonce, "bux") do
           {:ok, tx} -> {:ok, tx, expired_nonce}
           {:error, _} ->
             case BlocksterV2.BuxMinter.build_reclaim_expired_tx(wallet, expired_nonce, "sol") do
               {:ok, tx} -> {:ok, tx, expired_nonce}
               {:error, reason} -> {:error, reason}
             end
         end
       end)}
    else
      {:noreply, assign(socket, has_expired_bet: false, error_message: nil)}
    end
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

      socket = if wallet_address do
        socket
        |> assign(:onchain_ready, false)
        |> assign(:onchain_initializing, true)
        |> assign(:init_retry_count, 0)
        |> start_async(:init_game, fn -> CoinFlipGame.get_or_init_game(user_id, wallet_address) end)
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

    {:noreply, socket}
  end

  @impl true
  def handle_async(:sync_post_settle, {:ok, balances}, socket) do
    {:noreply, assign(socket, :balances, balances)}
  end

  def handle_async(:sync_post_settle, _, socket), do: {:noreply, socket}

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
      base = div(net_lamports * 100, 10000)
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
