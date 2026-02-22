defmodule BlocksterV2Web.PlinkoHowItWorksLive do
  use BlocksterV2Web, :live_view

  @sections [
    {"how-to-play", "How to Play"},
    {"tokens", "BUX & ROGUE"},
    {"on-chain", "On-Chain"},
    {"self-custody", "Self-Custody"},
    {"provably-fair", "Provably Fair"},
    {"multipliers", "Multipliers"},
    {"bankroll", "The Bankroll"},
    {"contracts", "Contracts"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Plinko - How It Works")
     |> assign(active_section: "how-to-play")
     |> assign(sections: @sections)
     |> assign(mobile_nav_open: false)}
  end

  @impl true
  def handle_event("nav", %{"section" => section}, socket) do
    {:noreply, assign(socket, active_section: section, mobile_nav_open: false)}
  end

  def handle_event("toggle_mobile_nav", _params, socket) do
    {:noreply, assign(socket, mobile_nav_open: !socket.assigns.mobile_nav_open)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-white flex flex-col">
      <%!-- Top bar --%>
      <div class="border-b border-gray-200 bg-white pt-6 sm:pt-24">
        <div class="max-w-6xl mx-auto px-4 sm:px-6 flex items-center justify-between h-12">
          <div class="flex items-center gap-3">
            <a href="/plinko" class="text-gray-400 hover:text-gray-600 cursor-pointer transition-colors">
              <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M15 19l-7-7 7-7" /></svg>
            </a>
            <div class="w-px h-5 bg-gray-200"></div>
            <span class="font-haas_bold_75 text-gray-900 text-sm">Plinko</span>
            <span class="text-gray-300 text-sm">/</span>
            <span class="font-haas_roman_55 text-gray-500 text-sm">How It Works</span>
          </div>
          <a href="/plinko" class="hidden sm:inline-flex items-center gap-1.5 bg-[#CAFC00] text-black font-haas_medium_65 px-4 py-1.5 rounded-lg text-xs hover:bg-[#d4ff33] transition-colors cursor-pointer">
            Play Plinko
            <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M17 8l4 4m0 0l-4 4m4-4H3" /></svg>
          </a>
          <%!-- Mobile nav toggle --%>
          <button phx-click="toggle_mobile_nav" class="sm:hidden text-gray-500 cursor-pointer p-1">
            <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
              <path :if={!@mobile_nav_open} stroke-linecap="round" stroke-linejoin="round" d="M4 6h16M4 12h16M4 18h16" />
              <path :if={@mobile_nav_open} stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>
      </div>

      <%!-- Mobile nav dropdown --%>
      <div :if={@mobile_nav_open} class="sm:hidden border-b border-gray-200 bg-gray-50">
        <nav class="px-4 py-2 space-y-0.5">
          <button
            :for={{id, label} <- @sections}
            phx-click="nav"
            phx-value-section={id}
            class={"w-full text-left px-3 py-2 rounded-lg text-sm cursor-pointer transition-colors #{if @active_section == id, do: "bg-white text-gray-900 font-haas_medium_65 shadow-sm", else: "text-gray-500 font-haas_roman_55 hover:text-gray-700"}"}
          >
            <%= label %>
          </button>
        </nav>
      </div>

      <%!-- Main layout: sidebar + content --%>
      <div class="flex-1 flex max-w-6xl mx-auto w-full">
        <%!-- Sidebar (desktop) --%>
        <aside class="hidden sm:block w-44 flex-shrink-0 border-r border-gray-100">
          <nav class="sticky top-[120px] py-5 px-3 space-y-0.5">
            <button
              :for={{id, label} <- @sections}
              phx-click="nav"
              phx-value-section={id}
              class={"w-full text-left px-2.5 py-1.5 rounded-md text-xs cursor-pointer transition-all #{if @active_section == id, do: "bg-gray-100 text-gray-900 font-haas_medium_65", else: "text-gray-400 font-haas_roman_55 hover:text-gray-600 hover:bg-gray-50"}"}
            >
              <%= label %>
            </button>
          </nav>
        </aside>

        <%!-- Content pane --%>
        <main class="flex-1 min-w-0 px-5 sm:px-8 lg:px-12 py-6 sm:py-10">
          <div class="max-w-2xl">
            <%= case @active_section do %>
              <% "how-to-play" -> %>
                <.section_how_to_play />
              <% "tokens" -> %>
                <.section_tokens />
              <% "on-chain" -> %>
                <.section_on_chain />
              <% "self-custody" -> %>
                <.section_self_custody />
              <% "provably-fair" -> %>
                <.section_provably_fair />
              <% "multipliers" -> %>
                <.section_multipliers />
              <% "bankroll" -> %>
                <.section_bankroll />
              <% "contracts" -> %>
                <.section_contracts />
              <% _ -> %>
                <.section_how_to_play />
            <% end %>
          </div>
        </main>
      </div>
    </div>
    """
  end

  # ─── Section: How to Play ───

  defp section_how_to_play(assigns) do
    ~H"""
    <h1 class="text-2xl font-haas_bold_75 text-gray-900 mb-2">How to Play</h1>
    <p class="text-gray-400 font-haas_roman_55 text-sm mb-8">Drop a ball through a field of pegs. Where it lands determines your payout.</p>

    <div class="space-y-6">
      <%!-- Step 1 --%>
      <div class="flex gap-4">
        <div class="flex-shrink-0 w-7 h-7 bg-gray-900 rounded-lg flex items-center justify-center">
          <span class="text-[#CAFC00] font-haas_bold_75 text-xs">1</span>
        </div>
        <div class="flex-1">
          <h3 class="font-haas_medium_65 text-gray-900 text-sm mb-1">Configure your bet</h3>
          <p class="text-sm text-gray-500 font-haas_roman_55 leading-relaxed mb-1">Choose your token (BUX or ROGUE), bet amount, number of rows (8, 12, or 16), and risk level (Low, Med, High).</p>
          <p class="text-sm text-gray-500 font-haas_roman_55 leading-relaxed mb-3">Rows and risk together select a specific payout table that's hardcoded in the PlinkoGame smart contract. This determines the multiplier for each landing slot. Your max bet is capped by the bankroll's available liquidity &mdash; the contract won't accept a bet it can't fully cover at the highest possible multiplier.</p>
          <%!-- Mini UI mockup --%>
          <div class="bg-gray-50 rounded-xl p-4 border border-gray-100 max-w-xs">
            <div class="flex items-center gap-2 mb-2.5">
              <div class="w-6 h-6 bg-[#CAFC00] rounded-full flex items-center justify-center"><span class="text-[9px] font-bold text-black">B</span></div>
              <div class="flex-1 h-7 bg-white border border-gray-200 rounded-md flex items-center px-2">
                <span class="text-xs text-gray-700 font-haas_medium_65">100</span>
              </div>
            </div>
            <div class="flex gap-3">
              <div class="flex gap-1 items-center">
                <span class="text-[10px] text-gray-400">Rows</span>
                <div class="flex gap-0.5">
                  <div class="px-1.5 py-0.5 bg-gray-900 rounded text-[9px] text-white font-haas_medium_65">8</div>
                  <div class="px-1.5 py-0.5 bg-white border border-gray-200 rounded text-[9px] text-gray-400">12</div>
                  <div class="px-1.5 py-0.5 bg-white border border-gray-200 rounded text-[9px] text-gray-400">16</div>
                </div>
              </div>
              <div class="flex gap-1 items-center">
                <span class="text-[10px] text-gray-400">Risk</span>
                <div class="flex gap-0.5">
                  <div class="px-1.5 py-0.5 bg-gray-900 rounded text-[9px] text-white font-haas_medium_65">Low</div>
                  <div class="px-1.5 py-0.5 bg-white border border-gray-200 rounded text-[9px] text-gray-400">Med</div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      <%!-- Step 2 --%>
      <div class="flex gap-4">
        <div class="flex-shrink-0 w-7 h-7 bg-gray-900 rounded-lg flex items-center justify-center">
          <span class="text-[#CAFC00] font-haas_bold_75 text-xs">2</span>
        </div>
        <div class="flex-1">
          <h3 class="font-haas_medium_65 text-gray-900 text-sm mb-1">Drop the ball</h3>
          <p class="text-sm text-gray-500 font-haas_roman_55 leading-relaxed mb-1">When you click "Drop Ball", two things happen on-chain in sequence. First, the server has already submitted a commitment &mdash; a SHA256 hash of a secret random seed &mdash; to the PlinkoGame contract. This is locked in before you bet.</p>
          <p class="text-sm text-gray-500 font-haas_roman_55 leading-relaxed mb-3">Then your bet is submitted as an ERC-4337 UserOperation. The Paymaster sponsors the gas fee, so you pay nothing. Your smart wallet calls <code class="bg-gray-100 px-1 py-0.5 rounded text-[11px]">placeBet()</code> on the PlinkoGame contract, transferring your tokens to the bankroll and recording the bet details on-chain.</p>
          <div class="bg-gray-50 rounded-xl p-4 border border-gray-100 max-w-xs">
            <div class="flex items-center gap-3">
              <div class="w-8 h-8 bg-gray-200 rounded-lg flex items-center justify-center">
                <svg class="w-4 h-4 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M13 10V3L4 14h7v7l9-11h-7z" /></svg>
              </div>
              <div class="flex-1 h-1.5 bg-gray-200 rounded-full overflow-hidden">
                <div class="h-full bg-[#CAFC00] rounded-full w-4/5"></div>
              </div>
              <div class="w-8 h-8 bg-gray-900 rounded-lg flex items-center justify-center">
                <svg class="w-4 h-4 text-[#CAFC00]" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M5 13l4 4L19 7" /></svg>
              </div>
            </div>
            <p class="text-[10px] text-gray-400 mt-2 font-mono">tx: 0x7f3a...c41b confirmed</p>
          </div>
        </div>
      </div>

      <%!-- Step 3 --%>
      <div class="flex gap-4">
        <div class="flex-shrink-0 w-7 h-7 bg-gray-900 rounded-lg flex items-center justify-center">
          <span class="text-[#CAFC00] font-haas_bold_75 text-xs">3</span>
        </div>
        <div class="flex-1">
          <h3 class="font-haas_medium_65 text-gray-900 text-sm mb-1">Watch it bounce</h3>
          <p class="text-sm text-gray-500 font-haas_roman_55 leading-relaxed mb-1">Once the bet is confirmed, the server reveals the original seed and the contract calculates the result. The combined seed <code class="bg-gray-100 px-1 py-0.5 rounded text-[11px]">SHA256(server_seed + client_seed + nonce)</code> produces a hash. The first N bytes (one per row) determine the ball's path &mdash; each byte below 128 sends it left, 128 or above sends it right.</p>
          <p class="text-sm text-gray-500 font-haas_roman_55 leading-relaxed mb-3">The animation you see in the browser replays this deterministic path. The ball's final position maps to a slot in the payout table, giving you your multiplier.</p>
          <%!-- Mini board --%>
          <div class="bg-gray-50 rounded-xl p-4 border border-gray-100 flex justify-center">
            <svg viewBox="0 0 120 90" class="w-32 h-auto">
              <circle :for={{cx, cy} <- [{60,10},{40,25},{80,25},{20,40},{60,40},{100,40},{40,55},{80,55},{20,70},{60,70},{100,70}]} cx={cx} cy={cy} r="3" fill="#d1d5db" />
              <path d="M 60 6 L 45 22 L 62 37 L 45 52 L 62 67" fill="none" stroke="#CAFC00" stroke-width="1.5" stroke-dasharray="3 2" />
              <circle cx="60" cy="6" r="5" fill="#CAFC00" />
              <circle cx="62" cy="67" r="4" fill="#CAFC00" opacity="0.5" />
              <rect :for={{x, fill} <- [{6,"#6b7280"},{24,"#6b7280"},{42,"#CAFC00"},{60,"#6b7280"},{78,"#6b7280"},{96,"#6b7280"}]} x={x} y="80" width="14" height="7" rx="2" fill={fill} opacity="0.5" />
            </svg>
          </div>
        </div>
      </div>

      <%!-- Step 4 --%>
      <div class="flex gap-4">
        <div class="flex-shrink-0 w-7 h-7 bg-gray-900 rounded-lg flex items-center justify-center">
          <span class="text-[#CAFC00] font-haas_bold_75 text-xs">4</span>
        </div>
        <div class="flex-1">
          <h3 class="font-haas_medium_65 text-gray-900 text-sm mb-1">Instant payout</h3>
          <p class="text-sm text-gray-500 font-haas_roman_55 leading-relaxed mb-1">The server calls <code class="bg-gray-100 px-1 py-0.5 rounded text-[11px]">settleBet()</code> on the PlinkoGame contract, passing the revealed server seed. The contract independently verifies the seed matches the commitment hash, calculates the outcome, and transfers your payout from the bankroll directly to your wallet &mdash; all in a single transaction.</p>
          <p class="text-sm text-gray-500 font-haas_roman_55 leading-relaxed mb-3">There is no withdrawal step. The contract pays you immediately. If you won, the payout is your bet multiplied by the slot's multiplier. If you lost, the bankroll keeps your bet.</p>
          <div class="bg-green-50 rounded-xl p-4 border border-green-200 max-w-xs">
            <div class="flex items-center justify-between mb-1">
              <span class="text-xs text-green-600 font-haas_medium_65">Payout</span>
              <span class="text-xs text-green-600 font-haas_bold_75">5.2x</span>
            </div>
            <div class="flex items-center gap-2">
              <div class="w-6 h-6 bg-[#CAFC00] rounded-full flex items-center justify-center"><span class="text-[9px] font-bold text-black">B</span></div>
              <span class="text-lg font-haas_bold_75 text-green-700">+520 BUX</span>
            </div>
            <div class="flex items-center gap-1 mt-2">
              <svg class="w-3.5 h-3.5 text-green-500" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M5 13l4 4L19 7" /></svg>
              <span class="text-[11px] text-green-600 font-haas_roman_55">Settled on-chain</span>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ─── Section: Tokens ───

  defp section_tokens(assigns) do
    ~H"""
    <h1 class="text-2xl font-haas_bold_75 text-gray-900 mb-2">BUX & ROGUE</h1>
    <p class="text-gray-400 font-haas_roman_55 text-sm mb-8">Two tokens, two ways to play. Both use identical provably fair mechanics and on-chain settlement.</p>

    <div class="space-y-6">
      <%!-- BUX --%>
      <div class="border border-gray-200 rounded-xl p-5">
        <div class="flex items-center gap-3 mb-4">
          <div class="w-9 h-9 bg-[#CAFC00] rounded-lg flex items-center justify-center">
            <span class="font-haas_bold_75 text-black text-sm">B</span>
          </div>
          <div>
            <h3 class="font-haas_bold_75 text-gray-900 text-sm">BUX</h3>
            <p class="text-xs text-gray-400 font-haas_roman_55">Blockster reward token</p>
          </div>
        </div>

        <p class="text-sm text-gray-500 font-haas_roman_55 leading-relaxed mb-4">
          Earned for free by reading articles, watching videos, and sharing content on Blockster. Playing Plinko with BUX lets you try the game risk-free with tokens you earned through engagement.
        </p>

        <div class="bg-gray-50 rounded-lg p-3">
          <p class="text-[10px] text-gray-400 font-haas_medium_65 uppercase tracking-wider mb-2">Earn BUX by</p>
          <div class="flex gap-4">
            <div class="flex items-center gap-1.5">
              <svg class="w-3.5 h-3.5 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.5"><path stroke-linecap="round" stroke-linejoin="round" d="M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253" /></svg>
              <span class="text-xs text-gray-500 font-haas_roman_55">Reading</span>
            </div>
            <div class="flex items-center gap-1.5">
              <svg class="w-3.5 h-3.5 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.5"><path stroke-linecap="round" stroke-linejoin="round" d="M14.752 11.168l-3.197-2.132A1 1 0 0010 9.87v4.263a1 1 0 001.555.832l3.197-2.132a1 1 0 000-1.664z" /><path stroke-linecap="round" stroke-linejoin="round" d="M21 12a9 9 0 11-18 0 9 9 0 0118 0z" /></svg>
              <span class="text-xs text-gray-500 font-haas_roman_55">Watching</span>
            </div>
            <div class="flex items-center gap-1.5">
              <svg class="w-3.5 h-3.5 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.5"><path stroke-linecap="round" stroke-linejoin="round" d="M8.684 13.342C8.886 12.938 9 12.482 9 12c0-.482-.114-.938-.316-1.342m0 2.684a3 3 0 110-2.684m0 2.684l6.632 3.316m-6.632-6l6.632-3.316m0 0a3 3 0 105.367-2.684 3 3 0 00-5.367 2.684zm0 9.316a3 3 0 105.368 2.684 3 3 0 00-5.368-2.684z" /></svg>
              <span class="text-xs text-gray-500 font-haas_roman_55">Sharing</span>
            </div>
          </div>
        </div>
      </div>

      <%!-- ROGUE --%>
      <div class="border border-gray-200 rounded-xl p-5 bg-gray-950">
        <div class="flex items-center gap-3 mb-4">
          <div class="w-9 h-9 bg-white/10 rounded-lg flex items-center justify-center border border-white/10">
            <span class="font-haas_bold_75 text-[#CAFC00] text-sm">R</span>
          </div>
          <div>
            <h3 class="font-haas_bold_75 text-white text-sm">ROGUE</h3>
            <p class="text-xs text-white/40 font-haas_roman_55">Native gas token</p>
          </div>
        </div>

        <p class="text-sm text-white/50 font-haas_roman_55 leading-relaxed mb-4">
          The native currency of Rogue Chain, like ETH on Ethereum. ROGUE has real market value and is tradeable. Playing Plinko with ROGUE is real-money gaming.
        </p>

        <div class="bg-white/5 rounded-lg p-3 border border-white/10">
          <div class="flex items-center gap-2">
            <div class="flex items-center gap-1.5 bg-white/10 rounded px-2 py-1">
              <div class="w-3.5 h-3.5 bg-blue-500 rounded-full flex items-center justify-center"><span class="text-[7px] font-bold text-white">E</span></div>
              <span class="text-[11px] text-white/60 font-haas_medium_65">ETH</span>
            </div>
            <span class="text-white/20 text-xs">is to Ethereum what</span>
            <div class="flex items-center gap-1.5 bg-[#CAFC00]/10 rounded px-2 py-1">
              <div class="w-3.5 h-3.5 bg-[#CAFC00] rounded-full flex items-center justify-center"><span class="text-[7px] font-bold text-black">R</span></div>
              <span class="text-[11px] text-[#CAFC00] font-haas_medium_65">ROGUE</span>
            </div>
            <span class="text-white/20 text-xs">is to Rogue Chain</span>
          </div>
        </div>
      </div>

      <div class="bg-gray-50 rounded-lg p-4 border border-gray-100 text-sm text-gray-500 font-haas_roman_55">
        The bankroll pools are separate &mdash; BUX bets draw from the BUX Bankroll, ROGUE bets from the ROGUE Bankroll. You can switch tokens anytime using the selector in the game.
      </div>
    </div>
    """
  end

  # ─── Section: On-Chain ───

  defp section_on_chain(assigns) do
    ~H"""
    <h1 class="text-2xl font-haas_bold_75 text-gray-900 mb-2">On-Chain Transparency</h1>
    <p class="text-gray-400 font-haas_roman_55 text-sm mb-3">Every bet is a real blockchain transaction on Rogue Chain. No backend databases, no hidden state.</p>
    <p class="text-sm text-gray-500 font-haas_roman_55 leading-relaxed mb-8">The PlinkoGame contract manages the entire game lifecycle: accepting commitments, recording bets, verifying seeds, and executing payouts. The bankroll contracts (BUXBankroll and ROGUEBankroll) hold the liquidity pools. All three are independent smart contracts with publicly viewable source code.</p>

    <%!-- Architecture diagram --%>
    <div class="bg-gray-50 rounded-xl p-6 border border-gray-100 mb-8">
      <p class="text-[10px] text-gray-400 font-haas_medium_65 uppercase tracking-wider mb-5">Transaction flow</p>
      <div class="flex items-center justify-between gap-2 sm:gap-4">
        <div class="text-center flex-shrink-0">
          <div class="w-12 h-12 sm:w-14 sm:h-14 bg-white rounded-xl border border-gray-200 flex items-center justify-center mx-auto mb-1.5">
            <svg class="w-5 h-5 sm:w-6 sm:h-6 text-gray-600" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.5"><path stroke-linecap="round" stroke-linejoin="round" d="M21 12a2.25 2.25 0 00-2.25-2.25H15a3 3 0 110-6h5.25A2.25 2.25 0 0121 6v6zm0 0v6a2.25 2.25 0 01-2.25 2.25H5.25A2.25 2.25 0 013 18V6a2.25 2.25 0 012.25-2.25h13.5" /></svg>
          </div>
          <p class="text-[11px] font-haas_medium_65 text-gray-600">Wallet</p>
        </div>
        <svg class="w-4 h-4 text-gray-300 flex-shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M17 8l4 4m0 0l-4 4m4-4H3" /></svg>
        <div class="text-center flex-shrink-0">
          <div class="w-12 h-12 sm:w-14 sm:h-14 bg-gray-900 rounded-xl flex items-center justify-center mx-auto mb-1.5">
            <svg class="w-5 h-5 sm:w-6 sm:h-6 text-[#CAFC00]" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.5"><path stroke-linecap="round" stroke-linejoin="round" d="M14.25 9.75L16.5 12l-2.25 2.25m-4.5 0L7.5 12l2.25-2.25M6 20.25h12A2.25 2.25 0 0020.25 18V6A2.25 2.25 0 0018 3.75H6A2.25 2.25 0 003.75 6v12A2.25 2.25 0 006 20.25z" /></svg>
          </div>
          <p class="text-[11px] font-haas_medium_65 text-gray-600">Contract</p>
        </div>
        <svg class="w-4 h-4 text-gray-300 flex-shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M17 8l4 4m0 0l-4 4m4-4H3" /></svg>
        <div class="text-center flex-shrink-0">
          <div class="w-12 h-12 sm:w-14 sm:h-14 bg-white rounded-xl border border-[#CAFC00]/30 flex items-center justify-center mx-auto mb-1.5">
            <svg class="w-5 h-5 sm:w-6 sm:h-6 text-gray-600" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.5"><path stroke-linecap="round" stroke-linejoin="round" d="M20.25 6.375c0 2.278-3.694 4.125-8.25 4.125S3.75 8.653 3.75 6.375m16.5 0c0-2.278-3.694-4.125-8.25-4.125S3.75 4.097 3.75 6.375m16.5 0v11.25c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125V6.375" /></svg>
          </div>
          <p class="text-[11px] font-haas_medium_65 text-gray-600">Bankroll</p>
        </div>
      </div>
    </div>

    <div class="space-y-4 mb-8">
      <div class="flex gap-3">
        <svg class="w-4 h-4 text-[#CAFC00] flex-shrink-0 mt-0.5" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd" /></svg>
        <p class="text-sm text-gray-600 font-haas_roman_55"><span class="font-haas_medium_65 text-gray-900">Real transactions.</span> Every bet and payout is a verifiable transaction on Rogue Chain. You can look up any game by its transaction hash on RogueScan and see the exact amounts, addresses, and contract calls.</p>
      </div>
      <div class="flex gap-3">
        <svg class="w-4 h-4 text-[#CAFC00] flex-shrink-0 mt-0.5" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd" /></svg>
        <p class="text-sm text-gray-600 font-haas_roman_55"><span class="font-haas_medium_65 text-gray-900">Non-custodial.</span> The bankroll contracts hold the liquidity pool. Neither Blockster nor any individual has the ability to withdraw funds from the pool &mdash; only the smart contract logic can move tokens, and only to pay out legitimate game results.</p>
      </div>
      <div class="flex gap-3">
        <svg class="w-4 h-4 text-[#CAFC00] flex-shrink-0 mt-0.5" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd" /></svg>
        <p class="text-sm text-gray-600 font-haas_roman_55"><span class="font-haas_medium_65 text-gray-900">Contract-executed payouts.</span> When a bet is settled, the PlinkoGame contract calls the bankroll contract's payout function. The bankroll transfers the winnings directly to your wallet address. No server, no admin, no manual step.</p>
      </div>
      <div class="flex gap-3">
        <svg class="w-4 h-4 text-[#CAFC00] flex-shrink-0 mt-0.5" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd" /></svg>
        <p class="text-sm text-gray-600 font-haas_roman_55"><span class="font-haas_medium_65 text-gray-900">Zero gas fees.</span> All transactions use ERC-4337 Account Abstraction. A Paymaster contract sponsors gas fees for every bet and settlement, so you never pay transaction costs to play.</p>
      </div>
    </div>
    """
  end

  # ─── Section: Self-Custody ───

  defp section_self_custody(assigns) do
    ~H"""
    <h1 class="text-2xl font-haas_bold_75 text-gray-900 mb-2">Self-Custody</h1>
    <p class="text-gray-400 font-haas_roman_55 text-sm mb-8">Your tokens stay in your wallet. No deposits, no lock-ups, no withdrawal queues.</p>

    <%!-- Comparison table --%>
    <div class="border border-gray-200 rounded-xl overflow-hidden mb-8">
      <div class="grid grid-cols-3 bg-gray-50 border-b border-gray-200">
        <div class="px-4 py-2.5"></div>
        <div class="px-4 py-2.5 text-center border-l border-gray-200">
          <span class="text-xs font-haas_medium_65 text-gray-400">Traditional</span>
        </div>
        <div class="px-4 py-2.5 text-center border-l border-gray-200">
          <span class="text-xs font-haas_medium_65 text-gray-900">Plinko</span>
        </div>
      </div>
      <div :for={{label, trad, plinko} <- [
        {"Custody", "Casino holds funds", "Your wallet"},
        {"Identity", "KYC required", "None needed"},
        {"Withdrawals", "Request + wait", "Instant on-chain"},
        {"Account freeze", "Possible", "Impossible"},
        {"Gas fees", "N/A", "Sponsored"}
      ]} class="grid grid-cols-3 border-b border-gray-100 last:border-b-0">
        <div class="px-4 py-3 text-xs font-haas_medium_65 text-gray-600"><%= label %></div>
        <div class="px-4 py-3 text-xs text-gray-400 font-haas_roman_55 border-l border-gray-100 flex items-center gap-1.5">
          <svg class="w-3 h-3 text-red-300 flex-shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" /></svg>
          <%= trad %>
        </div>
        <div class="px-4 py-3 text-xs text-gray-700 font-haas_roman_55 border-l border-gray-100 flex items-center gap-1.5">
          <svg class="w-3 h-3 text-[#CAFC00] flex-shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M5 13l4 4L19 7" /></svg>
          <%= plinko %>
        </div>
      </div>
    </div>

    <h3 class="text-sm font-haas_medium_65 text-gray-900 mt-8 mb-2">How your wallet works</h3>
    <p class="text-sm text-gray-500 font-haas_roman_55 leading-relaxed mb-3">
      When you sign up with your email, an ERC-4337 smart wallet is created for you automatically. This is a real on-chain wallet on Rogue Chain &mdash; it has its own address, holds your tokens, and signs transactions on your behalf.
    </p>
    <p class="text-sm text-gray-500 font-haas_roman_55 leading-relaxed mb-3">
      Unlike a traditional casino where you deposit into their system, your BUX and ROGUE tokens are always in your wallet. When you place a bet, the PlinkoGame contract pulls tokens from your wallet. When you win, the bankroll pushes tokens back to your wallet. There's no intermediate "balance" you need to withdraw.
    </p>
    <p class="text-sm text-gray-500 font-haas_roman_55 leading-relaxed">
      Blockster cannot freeze, lock, or access your wallet. The smart wallet is controlled by your login credentials via Account Abstraction &mdash; only you can authorize transactions from it.
    </p>
    """
  end

  # ─── Section: Provably Fair ───

  defp section_provably_fair(assigns) do
    ~H"""
    <h1 class="text-2xl font-haas_bold_75 text-gray-900 mb-2">Provably Fair</h1>
    <p class="text-gray-400 font-haas_roman_55 text-sm mb-8">A commit-reveal scheme ensures the result is locked before you bet. Neither side can manipulate it.</p>

    <%!-- Timeline diagram --%>
    <div class="space-y-0 mb-8">
      <%!-- Step 1 --%>
      <div class="flex gap-4">
        <div class="flex flex-col items-center">
          <div class="w-8 h-8 bg-gray-900 rounded-lg flex items-center justify-center flex-shrink-0">
            <svg class="w-4 h-4 text-[#CAFC00]" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" /></svg>
          </div>
          <div class="w-px h-full bg-gray-200 min-h-[16px]"></div>
        </div>
        <div class="pb-5">
          <h3 class="text-sm font-haas_medium_65 text-gray-900 mb-1">Server commits a seed</h3>
          <p class="text-xs text-gray-400 font-haas_roman_55 leading-relaxed mb-2">A random server seed is generated. Its SHA256 hash is published on-chain as a commitment. You can see this hash before you bet.</p>
          <div class="bg-gray-50 rounded-lg px-3 py-2 border border-gray-100 inline-block">
            <p class="text-[10px] text-gray-400 font-haas_roman_55">Commitment hash (visible before bet)</p>
            <p class="text-xs font-mono text-gray-600 mt-0.5">0x8a4f2e...b7c103</p>
          </div>
        </div>
      </div>

      <%!-- Step 2 --%>
      <div class="flex gap-4">
        <div class="flex flex-col items-center">
          <div class="w-8 h-8 bg-[#CAFC00] rounded-lg flex items-center justify-center flex-shrink-0">
            <svg class="w-4 h-4 text-black" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M15 15l-2 5L9 9l11 4-5 2zm0 0l5 5" /></svg>
          </div>
          <div class="w-px h-full bg-gray-200 min-h-[16px]"></div>
        </div>
        <div class="pb-5">
          <h3 class="text-sm font-haas_medium_65 text-gray-900 mb-1">You place your bet</h3>
          <p class="text-xs text-gray-400 font-haas_roman_55 leading-relaxed mb-2">Your bet details (user ID, amount, token, game config) form the client seed. This ties the result to your specific bet.</p>
          <div class="bg-gray-50 rounded-lg px-3 py-2 border border-gray-100 inline-block">
            <p class="text-[10px] text-gray-400 font-haas_roman_55">Client seed (from your bet)</p>
            <p class="text-xs font-mono text-gray-600 mt-0.5">user_42 + 100 BUX + config_0</p>
          </div>
        </div>
      </div>

      <%!-- Step 3 --%>
      <div class="flex gap-4">
        <div class="flex flex-col items-center">
          <div class="w-8 h-8 bg-gray-900 rounded-lg flex items-center justify-center flex-shrink-0">
            <svg class="w-4 h-4 text-[#CAFC00]" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M9 7h6m0 10v-3m-3 3h.01M9 17h.01M9 14h.01M12 14h.01M15 11h.01M12 11h.01M9 11h.01M7 21h10a2 2 0 002-2V5a2 2 0 00-2-2H7a2 2 0 00-2 2v14a2 2 0 002 2z" /></svg>
          </div>
          <div class="w-px h-full bg-gray-200 min-h-[16px]"></div>
        </div>
        <div class="pb-5">
          <h3 class="text-sm font-haas_medium_65 text-gray-900 mb-1">Result is calculated</h3>
          <p class="text-xs text-gray-400 font-haas_roman_55 leading-relaxed mb-2">The combined seed <code class="bg-gray-100 px-1 py-0.5 rounded text-[11px]">SHA256(server_seed + client_seed + nonce)</code> produces a hash. Each byte determines a peg bounce.</p>
          <div class="bg-gray-50 rounded-lg px-3 py-2 border border-gray-100 inline-flex items-center gap-1.5 flex-wrap">
            <span class="text-[10px] text-gray-400 font-haas_roman_55">Path:</span>
            <span :for={dir <- ["L","R","L","L","R","R","L","R"]} class={"text-[10px] font-mono px-1 py-0.5 rounded #{if dir == "L", do: "bg-blue-50 text-blue-500", else: "bg-amber-50 text-amber-600"}"}><%= dir %></span>
          </div>
          <p class="text-[11px] text-gray-400 font-haas_roman_55 mt-2">Byte &lt; 128 = LEFT, byte &ge; 128 = RIGHT</p>
        </div>
      </div>

      <%!-- Step 4 --%>
      <div class="flex gap-4">
        <div class="flex flex-col items-center">
          <div class="w-8 h-8 bg-green-500 rounded-lg flex items-center justify-center flex-shrink-0">
            <svg class="w-4 h-4 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M5 13l4 4L19 7" /></svg>
          </div>
        </div>
        <div>
          <h3 class="text-sm font-haas_medium_65 text-gray-900 mb-1">Verify the result</h3>
          <p class="text-xs text-gray-400 font-haas_roman_55 leading-relaxed mb-2">After settlement, the server seed is revealed. Compute <code class="bg-gray-100 px-1 py-0.5 rounded text-[11px]">SHA256(revealed_seed)</code> and confirm it matches the original commitment.</p>
          <div class="bg-green-50 rounded-lg px-3 py-2 border border-green-200 inline-flex items-center gap-1.5">
            <svg class="w-3 h-3 text-green-500" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M5 13l4 4L19 7" /></svg>
            <span class="text-xs text-green-700 font-haas_medium_65">Hash matches &mdash; result was fair</span>
          </div>
        </div>
      </div>
    </div>

    <h3 class="text-sm font-haas_medium_65 text-gray-900 mt-8 mb-2">Why this makes cheating impossible</h3>
    <div class="space-y-3 text-sm text-gray-500 font-haas_roman_55 leading-relaxed">
      <p><span class="font-haas_medium_65 text-gray-700">Server can't cheat:</span> The commitment hash is published on-chain before you bet. If the server tried to change the seed after seeing your bet, the hash wouldn't match &mdash; and settlement would fail.</p>
      <p><span class="font-haas_medium_65 text-gray-700">Player can't cheat:</span> Your bet details (user ID, amount, config) are included in the combined seed. You can't influence the outcome by changing your bet after the commitment, because the commitment is already locked.</p>
      <p><span class="font-haas_medium_65 text-gray-700">No replay attacks:</span> A nonce (incrementing counter) is included in each seed calculation. Even identical bets produce different results because the nonce is always unique.</p>
      <p><span class="font-haas_medium_65 text-gray-700">You can verify any game:</span> After settlement, click any game in your history to see the server seed, client seed, and commitment hash. Run SHA256 yourself to confirm the result was legitimate.</p>
    </div>
    """
  end

  # ─── Section: Multipliers ───

  defp section_multipliers(assigns) do
    ~H"""
    <h1 class="text-2xl font-haas_bold_75 text-gray-900 mb-2">Multipliers</h1>
    <p class="text-gray-400 font-haas_roman_55 text-sm mb-3">Payout tables are hardcoded in the smart contract. They cannot be changed after deployment.</p>
    <p class="text-sm text-gray-500 font-haas_roman_55 leading-relaxed mb-8">Each combination of rows (8, 12, 16) and risk (Low, Med, High) maps to a specific payout table stored as an array of basis-point values in the PlinkoGame contract. A value of 10000 = 1.0x (break even), 5600 = 0.56x (loss), 21000 = 2.1x (win). These values were set at deployment and cannot be modified.</p>

    <h3 class="text-sm font-haas_medium_65 text-gray-900 mb-3">Rows affect distribution width</h3>
    <p class="text-xs text-gray-500 font-haas_roman_55 mb-4">More rows means more peg bounces. With 8 rows, the ball makes 8 left/right decisions, creating 9 possible landing slots. With 16 rows, it makes 16 decisions across 17 slots, producing a wider bell curve of outcomes.</p>

    <div class="grid grid-cols-2 gap-4 mb-8">
      <div class="bg-gray-50 rounded-xl p-4 border border-gray-100">
        <p class="text-[11px] text-gray-400 font-haas_medium_65 mb-2">8 rows &mdash; narrow</p>
        <div class="flex items-end gap-px h-10 justify-center">
          <div :for={h <- [4, 8, 16, 26, 40, 26, 16, 8, 4]} class="w-3 bg-gray-300 rounded-t-sm" style={"height: #{h}px"}></div>
        </div>
      </div>
      <div class="bg-gray-50 rounded-xl p-4 border border-gray-100">
        <p class="text-[11px] text-gray-400 font-haas_medium_65 mb-2">16 rows &mdash; wide</p>
        <div class="flex items-end gap-px h-10 justify-center">
          <div :for={h <- [1, 2, 4, 6, 10, 16, 24, 34, 40, 34, 24, 16, 10, 6, 4, 2, 1]} class="w-[6px] bg-[#CAFC00] rounded-t-sm" style={"height: #{h}px"}></div>
        </div>
      </div>
    </div>

    <h3 class="text-sm font-haas_medium_65 text-gray-900 mb-3">Risk affects multiplier extremes</h3>
    <p class="text-xs text-gray-500 font-haas_roman_55 mb-4">Low risk produces a tight bell curve &mdash; most outcomes cluster near 1.0x, with modest wins and losses. High risk creates a U-shaped distribution &mdash; edge slots have large multipliers (10x+) but the center slots pay almost nothing. The expected value remains the same; only the variance changes.</p>

    <div class="grid grid-cols-2 gap-4 mb-8">
      <div class="bg-gray-50 rounded-xl p-4 border border-gray-100">
        <p class="text-[11px] text-gray-400 font-haas_medium_65 mb-2">Low risk &mdash; bell curve</p>
        <div class="flex items-end gap-px h-10 justify-center">
          <div :for={h <- [10, 18, 26, 34, 40, 34, 26, 18, 10]} class="w-3 bg-green-300 rounded-t-sm" style={"height: #{h}px"}></div>
        </div>
      </div>
      <div class="bg-gray-50 rounded-xl p-4 border border-gray-100">
        <p class="text-[11px] text-gray-400 font-haas_medium_65 mb-2">High risk &mdash; U-shaped</p>
        <div class="flex items-end gap-px h-10 justify-center">
          <div :for={h <- [40, 10, 4, 2, 1, 2, 4, 10, 40]} class="w-3 bg-red-300 rounded-t-sm" style={"height: #{h}px"}></div>
        </div>
      </div>
    </div>

    <div class="bg-gray-900 rounded-xl p-4 text-[11px] font-mono text-white/60 leading-relaxed">
      <p class="text-white/30 mb-1">// Example: 8 rows, low risk (basis points)</p>
      <p>payouts = [<span class="text-[#CAFC00]">5600</span>, 21000, 11000, 14000, 14000, 11000, 21000, <span class="text-[#CAFC00]">5600</span>]</p>
      <p class="text-white/30 mt-1">// 10000 = 1.0x | 5600 = 0.56x | 21000 = 2.1x</p>
    </div>
    """
  end

  # ─── Section: Bankroll ───

  defp section_bankroll(assigns) do
    ~H"""
    <h1 class="text-2xl font-haas_bold_75 text-gray-900 mb-2">The Bankroll</h1>
    <p class="text-gray-400 font-haas_roman_55 text-sm mb-8">Community-funded liquidity pools power every payout.</p>

    <%!-- LP flow --%>
    <div class="bg-gray-50 rounded-xl p-5 border border-gray-100 mb-8">
      <p class="text-[10px] text-gray-400 font-haas_medium_65 uppercase tracking-wider mb-4">How the bankroll works</p>
      <div class="flex items-center justify-between gap-2 sm:gap-4">
        <div class="text-center flex-shrink-0">
          <div class="w-11 h-11 bg-white rounded-lg border border-gray-200 flex items-center justify-center mx-auto mb-1">
            <svg class="w-5 h-5 text-gray-500" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.5"><path stroke-linecap="round" stroke-linejoin="round" d="M15 19.128a9.38 9.38 0 002.625.372 9.337 9.337 0 004.121-.952 4.125 4.125 0 00-7.533-2.493M15 19.128v-.003c0-1.113-.285-2.16-.786-3.07M15 19.128v.106A12.318 12.318 0 018.624 21c-2.331 0-4.512-.645-6.374-1.766l-.001-.109a6.375 6.375 0 0111.964-3.07M12 6.375a3.375 3.375 0 11-6.75 0 3.375 3.375 0 016.75 0zm8.25 2.25a2.625 2.625 0 11-5.25 0 2.625 2.625 0 015.25 0z" /></svg>
          </div>
          <p class="text-[10px] font-haas_medium_65 text-gray-500">LPs</p>
        </div>
        <div class="text-center">
          <svg class="w-4 h-4 text-gray-300 mx-auto" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M17 8l4 4m0 0l-4 4m4-4H3" /></svg>
          <p class="text-[9px] text-gray-300 mt-0.5">deposit</p>
        </div>
        <div class="text-center flex-shrink-0">
          <div class="w-11 h-11 bg-[#CAFC00] rounded-lg flex items-center justify-center mx-auto mb-1">
            <svg class="w-5 h-5 text-black" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.5"><path stroke-linecap="round" stroke-linejoin="round" d="M20.25 6.375c0 2.278-3.694 4.125-8.25 4.125S3.75 8.653 3.75 6.375m16.5 0c0-2.278-3.694-4.125-8.25-4.125S3.75 4.097 3.75 6.375m16.5 0v11.25c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125V6.375" /></svg>
          </div>
          <p class="text-[10px] font-haas_medium_65 text-gray-500">Pool</p>
        </div>
        <div class="text-center">
          <svg class="w-4 h-4 text-gray-300 mx-auto" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M17 8l4 4m0 0l-4 4m4-4H3" /></svg>
          <p class="text-[9px] text-gray-300 mt-0.5">payout</p>
        </div>
        <div class="text-center flex-shrink-0">
          <div class="w-11 h-11 bg-white rounded-lg border border-gray-200 flex items-center justify-center mx-auto mb-1">
            <svg class="w-5 h-5 text-gray-500" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.5"><path stroke-linecap="round" stroke-linejoin="round" d="M15.75 6a3.75 3.75 0 11-7.5 0 3.75 3.75 0 017.5 0zM4.501 20.118a7.5 7.5 0 0114.998 0A17.933 17.933 0 0112 21.75c-2.676 0-5.216-.584-7.499-1.632z" /></svg>
          </div>
          <p class="text-[10px] font-haas_medium_65 text-gray-500">Players</p>
        </div>
      </div>
    </div>

    <div class="space-y-4 mb-8">
      <div>
        <h3 class="text-sm font-haas_medium_65 text-gray-900 mb-1">Liquidity providers fund the pool</h3>
        <p class="text-sm text-gray-500 font-haas_roman_55 leading-relaxed">Anyone can deposit tokens into the bankroll smart contract by calling <code class="bg-gray-100 px-1 py-0.5 rounded text-[11px]">deposit()</code>. In return, you receive LP shares that represent your proportion of the pool. These shares track your ownership as the pool grows or shrinks from game outcomes.</p>
      </div>
      <div>
        <h3 class="text-sm font-haas_medium_65 text-gray-900 mb-1">House edge accrues over time</h3>
        <p class="text-sm text-gray-500 font-haas_roman_55 leading-relaxed">The payout tables are designed with a small house edge built in. Over a large number of games, the pool statistically grows. When a player loses, their tokens stay in the pool. When a player wins, their payout is drawn from the pool. LP providers earn when the expected house edge plays out across many bets.</p>
      </div>
      <div>
        <h3 class="text-sm font-haas_medium_65 text-gray-900 mb-1">Separate pools per token</h3>
        <p class="text-sm text-gray-500 font-haas_roman_55 leading-relaxed">BUX bets draw from the BUX Bankroll contract at <code class="bg-gray-100 px-1 py-0.5 rounded text-[11px]">0xED7B...a8630</code>. ROGUE bets draw from the ROGUE Bankroll at <code class="bg-gray-100 px-1 py-0.5 rounded text-[11px]">0x51DB...B2fd</code>. Each operates independently with its own LP shares and pool balance.</p>
      </div>
    </div>

    <a href="/bankroll" class="inline-flex items-center gap-2 bg-gray-900 text-white font-haas_medium_65 px-5 py-2.5 rounded-lg text-sm hover:bg-black transition-colors cursor-pointer">
      Become a liquidity provider
      <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M17 8l4 4m0 0l-4 4m4-4H3" /></svg>
    </a>
    """
  end

  # ─── Section: Contracts ───

  defp section_contracts(assigns) do
    ~H"""
    <h1 class="text-2xl font-haas_bold_75 text-gray-900 mb-2">Contracts</h1>
    <p class="text-gray-400 font-haas_roman_55 text-sm mb-8">All contracts are deployed on Rogue Chain (Chain ID: 560013) and viewable on RogueScan.</p>

    <div class="border border-gray-200 rounded-xl overflow-hidden">
      <div :for={{label, addr} <- [
        {"PlinkoGame", "0x7E12c7077556B142F8Fb695F70aAe0359a8be10C"},
        {"BUX Bankroll", "0xED7B00Ab2aDE39AC06d4518d16B465C514ba8630"},
        {"ROGUE Bankroll", "0x51DB4eD2b69b598Fade1aCB5289C7426604AB2fd"},
        {"BUX Token", "0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8"}
      ]} class="flex flex-col sm:flex-row sm:items-center justify-between px-4 py-3 border-b border-gray-100 last:border-b-0 gap-1">
        <span class="text-sm font-haas_medium_65 text-gray-700"><%= label %></span>
        <a href={"https://roguescan.io/address/#{addr}"} target="_blank" rel="noopener noreferrer" class="text-xs text-blue-500 hover:underline font-mono cursor-pointer break-all"><%= addr %></a>
      </div>
    </div>

    <div class="mt-8 space-y-3">
      <div>
        <h3 class="text-sm font-haas_medium_65 text-gray-900 mb-1">Rogue Chain</h3>
        <p class="text-xs text-gray-400 font-haas_roman_55 leading-relaxed">An EVM-compatible blockchain. RPC: <code class="bg-gray-100 px-1 py-0.5 rounded text-[11px]">https://rpc.roguechain.io/rpc</code></p>
      </div>
      <div>
        <h3 class="text-sm font-haas_medium_65 text-gray-900 mb-1">Explorer</h3>
        <p class="text-xs text-gray-400 font-haas_roman_55 leading-relaxed">
          <a href="https://roguescan.io" target="_blank" rel="noopener noreferrer" class="text-blue-500 hover:underline cursor-pointer">roguescan.io</a>
          &mdash; verify any transaction, contract, or address.
        </p>
      </div>
    </div>
    """
  end
end
