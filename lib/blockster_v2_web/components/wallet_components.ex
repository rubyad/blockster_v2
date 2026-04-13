defmodule BlocksterV2Web.WalletComponents do
  @moduledoc """
  Solana wallet UI components — connect button and wallet selector modal.
  """
  use Phoenix.Component

  @wallet_registry [
    %{
      name: "Phantom",
      url: "https://phantom.com",
      browse_url: "https://phantom.app/ul/browse/",
      icon: "/images/wallets/phantom.svg",
      tagline: "The friendly crypto wallet",
      gradient: "from-[#AB9FF2] to-[#534BB1]",
      shadow: "shadow-[0_4px_12px_rgba(83,75,177,0.35)]",
      shadow_lg: "shadow-[0_8px_24px_rgba(83,75,177,0.4)]"
    },
    %{
      name: "Solflare",
      url: "https://solflare.com",
      browse_url: "https://solflare.com/ul/v1/browse/",
      icon: "/images/wallets/solflare.svg",
      tagline: "Solana's most secure wallet",
      gradient: "from-[#FFA500] to-[#FF6B00]",
      shadow: "shadow-[0_4px_12px_rgba(255,107,0,0.35)]",
      shadow_lg: "shadow-[0_8px_24px_rgba(255,107,0,0.4)]"
    },
    %{
      name: "Backpack",
      url: "https://backpack.app",
      browse_url: nil,
      icon: "/images/wallets/backpack.png",
      tagline: "A home for your xNFTs",
      gradient: "from-[#E33E3F] to-[#B91C1C]",
      shadow: "shadow-[0_4px_12px_rgba(185,28,28,0.35)]",
      shadow_lg: "shadow-[0_8px_24px_rgba(185,28,28,0.4)]"
    }
  ]

  # ── Connect Button ──────────────────────────────────────────
  # Used by the old app.html.heex header only — NOT restyled.
  # Redesigned pages use the DS header's inline connect button.

  attr :wallet_address, :string, default: nil
  attr :sol_balance, :any, default: nil
  attr :bux_balance, :any, default: nil
  attr :connecting, :boolean, default: false

  def connect_button(assigns) do
    assigns =
      assigns
      |> assign(:truncated, truncate_address(assigns.wallet_address))
      |> assign(:sol_display, format_sol(assigns.sol_balance))

    ~H"""
    <%= if @wallet_address do %>
      <%!-- Connected state --%>
      <button
        phx-click="show_profile_dropdown"
        class="group flex items-center gap-2 px-3 py-1.5 rounded-full
               bg-gray-800/60 border border-gray-700/50 backdrop-blur-sm
               hover:bg-gray-700/60 hover:border-gray-600/50
               transition-all duration-200 cursor-pointer"
      >
        <%!-- Address avatar — deterministic gradient from pubkey --%>
        <div class="w-6 h-6 rounded-full bg-gradient-to-br from-emerald-400 via-cyan-500 to-violet-500 flex-shrink-0
                    ring-1 ring-white/10"></div>

        <div class="flex flex-col items-start leading-none">
          <span class="text-[11px] text-white/90 font-haas_medium_65 tracking-wide">
            <%= @truncated %>
          </span>
          <%= if @sol_display do %>
            <span class="text-[10px] text-white/40 font-haas_roman_55">
              <%= @sol_display %> SOL
            </span>
          <% end %>
        </div>

        <%!-- Dropdown chevron --%>
        <svg class="w-3.5 h-3.5 text-white/30 group-hover:text-white/50 transition-colors" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
          <path stroke-linecap="round" stroke-linejoin="round" d="M19 9l-7 7-7-7" />
        </svg>
      </button>
    <% else %>
      <%!-- Disconnected state --%>
      <button
        phx-click="show_wallet_selector"
        disabled={@connecting}
        class={"flex items-center gap-2 px-4 py-2 rounded-full font-haas_medium_65 text-sm
               transition-all duration-200 cursor-pointer
               #{if @connecting, do: "bg-gray-700 text-white/50", else: "bg-gray-900 text-white hover:bg-gray-800 hover:shadow-lg hover:shadow-black/20 active:scale-[0.97]"}"}
      >
        <%= if @connecting do %>
          <svg class="w-4 h-4 animate-spin" fill="none" viewBox="0 0 24 24">
            <circle class="opacity-20" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="3"></circle>
            <path class="opacity-80" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"></path>
          </svg>
          <span>Connecting...</span>
        <% else %>
          <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.5">
            <path stroke-linecap="round" stroke-linejoin="round" d="M21 12a2.25 2.25 0 00-2.25-2.25H15a3 3 0 110-6h5.25A2.25 2.25 0 0121 6v6zm0 0v6a2.25 2.25 0 01-2.25 2.25H5.25A2.25 2.25 0 013 18V6a2.25 2.25 0 012.25-2.25h13.5A2.25 2.25 0 0121 6" />
          </svg>
          <span>Connect Wallet</span>
        <% end %>
      </button>
    <% end %>
    """
  end

  # ── Wallet Selector Modal ───────────────────────────────────

  attr :show, :boolean, default: false
  attr :detected_wallets, :list, default: []
  attr :connecting, :boolean, default: false
  attr :connecting_wallet_name, :any, default: nil

  def wallet_selector_modal(assigns) do
    detected_names =
      Enum.map(assigns.detected_wallets, fn w ->
        (w["name"] || w[:name] || "") |> String.downcase()
      end)

    wallets =
      Enum.map(@wallet_registry, fn w ->
        Map.put(w, :detected, String.downcase(w.name) in detected_names)
      end)

    connecting_wallet =
      if assigns.connecting_wallet_name do
        Enum.find(@wallet_registry, fn w ->
          String.downcase(w.name) == String.downcase(assigns.connecting_wallet_name)
        end)
      end

    assigns =
      assigns
      |> assign(:wallets, wallets)
      |> assign(:connecting_wallet, connecting_wallet)

    ~H"""
    <%!-- Modal visible when: wallet selector is open OR connecting to a wallet --%>
    <%= if @show or (@connecting and @connecting_wallet_name) do %>
      <%!-- Backdrop --%>
      <div
        id="wallet-modal-backdrop"
        class="fixed inset-0 z-50 flex items-center justify-center p-4"
        style="background: linear-gradient(180deg, rgba(20, 20, 20, 0.78), rgba(20, 20, 20, 0.85)); backdrop-filter: blur(8px); -webkit-backdrop-filter: blur(8px); animation: walletFadeIn 150ms ease-out;"
      >
        <%!-- Dot grid overlay --%>
        <div
          class="absolute inset-0 pointer-events-none"
          style="background-image: radial-gradient(circle at 30% 30%, rgba(202, 252, 0, 0.06) 1.5px, transparent 1.5px); background-size: 28px 28px;"
        ></div>

        <%= if @connecting and @connecting_wallet do %>
          <%!-- ── STATE 2: Connecting ── --%>
          <div
            phx-click-away="hide_wallet_selector"
            class="relative w-full max-w-[440px] bg-white rounded-3xl overflow-hidden ring-1 ring-black/5"
            style="box-shadow: 0 30px 80px -15px rgba(0,0,0,0.4); animation: walletSlideUp 200ms ease-out;"
          >
            <%!-- Top bar: Close only (no Back — can't cancel a pending wallet popup) --%>
            <div class="flex items-center justify-end px-6 pt-6 pb-2">
              <button
                phx-click="hide_wallet_selector"
                class="w-8 h-8 rounded-full bg-neutral-100 hover:bg-neutral-200 grid place-items-center transition-colors cursor-pointer"
                aria-label="Close"
              >
                <svg class="w-3.5 h-3.5 text-neutral-600" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
              </button>
            </div>

            <%!-- Big wallet badge with spinning ring --%>
            <div class="px-6 pt-6 pb-4 flex flex-col items-center text-center">
              <div class="relative mb-5">
                <div class={"w-20 h-20 rounded-2xl grid place-items-center ring-1 ring-white/40 bg-gradient-to-br #{@connecting_wallet.gradient} #{@connecting_wallet.shadow_lg}"}>
                  <.wallet_icon_large name={@connecting_wallet.name} />
                </div>
                <%!-- Spinning lime ring --%>
                <svg class="absolute -inset-2 w-24 h-24 text-[#CAFC00] animate-spin" style="animation-duration: 0.9s;" viewBox="0 0 100 100" fill="none">
                  <circle cx="50" cy="50" r="46" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-dasharray="60 220" stroke-dashoffset="0"/>
                </svg>
              </div>
              <h2 class="text-[24px] font-bold tracking-tight text-[#141414] leading-[1.1] mb-2" style="letter-spacing: -0.022em;">
                Opening <%= @connecting_wallet.name %>
              </h2>
              <p class="text-[13px] text-neutral-500 font-medium leading-relaxed max-w-[300px]">
                Approve the connection in your <%= @connecting_wallet.name %> popup. We'll bring you back here once you sign.
              </p>
            </div>

            <%!-- Progress shimmer strip --%>
            <div class="px-6 pt-2 pb-1">
              <div class="h-1 rounded-full bg-neutral-100 overflow-hidden">
                <div class="h-full w-full rounded-full wallet-progress-shimmer"></div>
              </div>
            </div>

            <%!-- Status steps --%>
            <div class="px-6 py-5">
              <div class="space-y-3 text-[12px] font-medium">
                <%!-- Step 1: Wallet detected (done) --%>
                <div class="flex items-center gap-3">
                  <div class="w-5 h-5 rounded-full bg-[#22C55E] grid place-items-center shrink-0">
                    <svg class="w-3 h-3 text-white" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>
                  </div>
                  <span class="text-[#141414]">Wallet detected</span>
                  <span class="ml-auto text-[10px] font-mono text-neutral-400">0.2s</span>
                </div>
                <%!-- Step 2: Awaiting signature (in progress) --%>
                <div class="flex items-center gap-3">
                  <div class="w-5 h-5 rounded-full bg-[#CAFC00] grid place-items-center shrink-0">
                    <div class="w-2 h-2 rounded-full bg-black wallet-pulse-dot"></div>
                  </div>
                  <span class="text-[#141414] font-bold">Awaiting signature…</span>
                  <span class="ml-auto text-[10px] font-mono text-neutral-400">live</span>
                </div>
                <%!-- Step 3: Verify and sign in (pending) --%>
                <div class="flex items-center gap-3 opacity-50">
                  <div class="w-5 h-5 rounded-full border-2 border-dashed border-neutral-300 shrink-0"></div>
                  <span class="text-neutral-500">Verify and sign in</span>
                </div>
              </div>
            </div>

            <%!-- Bottom padding --%>
            <div class="pb-6"></div>
          </div>
        <% else %>
          <%!-- ── STATE 1: Wallet Selection ── --%>
          <div
            phx-click-away="hide_wallet_selector"
            class="relative w-full max-w-[440px] bg-white rounded-3xl overflow-hidden ring-1 ring-black/5"
            style="box-shadow: 0 30px 80px -15px rgba(0,0,0,0.4); animation: walletSlideUp 200ms ease-out;"
          >
            <%!-- Top bar: Blockster icon + SIGN IN + Close --%>
            <div class="flex items-center justify-between px-6 pt-6 pb-2">
              <div class="flex items-center gap-2">
                <img src="https://ik.imagekit.io/blockster/blockster-icon.png" alt="" class="w-6 h-6 rounded-md" />
                <span class="text-[11px] uppercase tracking-[0.16em] text-neutral-500 font-bold">Sign in</span>
              </div>
              <button
                phx-click="hide_wallet_selector"
                class="w-8 h-8 rounded-full bg-neutral-100 hover:bg-neutral-200 grid place-items-center transition-colors cursor-pointer"
                aria-label="Close"
              >
                <svg class="w-3.5 h-3.5 text-neutral-600" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
              </button>
            </div>

            <%!-- Title --%>
            <div class="px-6 pb-5">
              <h2 class="text-[26px] font-bold tracking-tight text-[#141414] leading-[1.1] mb-2" style="letter-spacing: -0.022em;">
                Connect a Solana wallet
              </h2>
              <p class="text-[13px] text-neutral-500 font-medium leading-relaxed">
                Pick the wallet you want to use to sign in. Blockster never sees your seed phrase or private keys.
              </p>
            </div>

            <%!-- Wallet rows --%>
            <div class="px-4 pb-2 space-y-2">
              <%= for wallet <- @wallets do %>
                <div class={"w-full flex items-center gap-4 p-3 rounded-2xl border bg-white text-left transition-all duration-150 " <> if(wallet.detected, do: "border-neutral-200 hover:bg-[#fafaf9] hover:border-black/[0.12] hover:-translate-y-px cursor-pointer", else: "border-neutral-200 opacity-60")}>
                  <%!-- Brand badge --%>
                  <div class={"w-12 h-12 rounded-xl shrink-0 grid place-items-center ring-1 ring-white/30 bg-gradient-to-br #{wallet.gradient} #{wallet.shadow}"}>
                    <.wallet_icon_small name={wallet.name} />
                  </div>

                  <%!-- Name + status --%>
                  <div class="flex-1 min-w-0">
                    <div class="flex items-center gap-2">
                      <span class="font-bold text-[15px] text-[#141414]"><%= wallet.name %></span>
                      <%= if wallet.detected do %>
                        <span class="inline-flex items-center gap-1 bg-[#22C55E]/10 text-[#15803d] border border-[#22C55E]/25 px-1.5 py-0.5 rounded-full text-[9px] font-bold uppercase tracking-wider">
                          <span class="w-1 h-1 rounded-full bg-[#22C55E]"></span>
                          Detected
                        </span>
                      <% else %>
                        <span class="inline-flex items-center gap-1 bg-neutral-100 text-neutral-600 border border-neutral-200 px-1.5 py-0.5 rounded-full text-[9px] font-bold uppercase tracking-wider">
                          Install
                        </span>
                      <% end %>
                    </div>
                    <div class="text-[11px] text-neutral-500 font-medium mt-0.5"><%= wallet.tagline %></div>
                  </div>

                  <%!-- Action --%>
                  <%= if wallet.detected do %>
                    <button
                      phx-click="select_wallet"
                      phx-value-name={wallet.name}
                      class="inline-flex items-center gap-1 bg-[#0a0a0a] text-white px-3.5 py-1.5 rounded-full text-[11px] font-bold hover:bg-[#1a1a22] transition-colors cursor-pointer"
                    >
                      Connect
                      <svg class="w-3 h-3" viewBox="0 0 20 20" fill="none"><path d="M3 10h12m0 0l-4-4m4 4l-4 4" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>
                    </button>
                  <% else %>
                    <a
                      href={wallet.url}
                      target="_blank"
                      rel="noopener"
                      class="inline-flex items-center gap-1 bg-white border border-neutral-200 text-[#141414] px-3.5 py-1.5 rounded-full text-[11px] font-bold hover:border-[#141414] transition-colors"
                    >
                      Get
                      <svg class="w-3 h-3" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/><polyline points="15 3 21 3 21 9"/><line x1="10" y1="14" x2="21" y2="3"/></svg>
                    </a>
                  <% end %>
                </div>
              <% end %>
            </div>

            <%!-- Footer --%>
            <div class="px-6 pt-5 pb-6 mt-2 border-t border-neutral-100">
              <div class="flex items-start gap-3 mb-4">
                <div class="w-7 h-7 rounded-full bg-[#CAFC00]/15 border border-[#CAFC00]/30 grid place-items-center shrink-0 mt-0.5">
                  <svg class="w-3.5 h-3.5 text-[#141414]" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><line x1="12" y1="16" x2="12" y2="12"/><line x1="12" y1="8" x2="12.01" y2="8"/></svg>
                </div>
                <div class="text-[11px] text-neutral-600 font-medium leading-relaxed">
                  <a href="https://phantom.com" target="_blank" rel="noopener" class="font-bold text-[#141414] hover:underline">What's a wallet?</a>
                  <span class="text-neutral-500"> — A Solana wallet is your account on the network. Blockster uses it to sign in and pay you BUX. Free, takes a minute.</span>
                </div>
              </div>
              <div class="text-[10px] text-neutral-400 font-medium leading-relaxed">
                By connecting, you agree to Blockster's <a href="/terms" class="underline hover:text-neutral-700">Terms</a> and <a href="/privacy" class="underline hover:text-neutral-700">Privacy Policy</a>. We never see your seed phrase or private keys.
              </div>
            </div>
          </div>
        <% end %>
      </div>
    <% end %>

    <style>
      @keyframes walletFadeIn {
        from { opacity: 0; }
        to { opacity: 1; }
      }
      @keyframes walletSlideUp {
        from { opacity: 0; transform: translateY(12px) scale(0.97); }
        to { opacity: 1; transform: translateY(0) scale(1); }
      }
      @keyframes walletPulseDot {
        0%, 100% { opacity: 1; transform: scale(1); }
        50%      { opacity: 0.55; transform: scale(1.15); }
      }
      .wallet-pulse-dot {
        animation: walletPulseDot 1.6s cubic-bezier(0.4, 0, 0.6, 1) infinite;
      }
      .wallet-progress-shimmer {
        background: linear-gradient(90deg, transparent, rgba(202, 252, 0, 0.6), transparent);
        background-size: 200% 100%;
        animation: walletShimmer 1.2s linear infinite;
      }
      @keyframes walletShimmer {
        0%   { background-position: 200% 0; }
        100% { background-position: -200% 0; }
      }
    </style>
    """
  end

  # ── Wallet Icon Components (inline SVGs matching mock) ─────

  defp wallet_icon_small(%{name: "Phantom"} = assigns) do
    ~H"""
    <svg class="w-7 h-7 text-white" viewBox="0 0 128 128" fill="currentColor">
      <path d="M64 16c-24.3 0-44 19.7-44 44 0 24.3 19.7 44 44 44 4.4 0 8-3.6 8-8v-8c0-2.2 1.8-4 4-4s4 1.8 4 4v8c0 4.4 3.6 8 8 8 16.6 0 28-13.4 28-30 0-32.6-26.4-58-52-58zM44 60c-3.3 0-6 2.7-6 6s2.7 6 6 6 6-2.7 6-6-2.7-6-6-6zm32 0c-3.3 0-6 2.7-6 6s2.7 6 6 6 6-2.7 6-6-2.7-6-6-6z"/>
    </svg>
    """
  end

  defp wallet_icon_small(%{name: "Solflare"} = assigns) do
    ~H"""
    <svg class="w-7 h-7 text-white" viewBox="0 0 24 24" fill="currentColor">
      <circle cx="12" cy="12" r="4"/>
      <path d="M12 2v3M12 19v3M2 12h3M19 12h3M4.93 4.93l2.12 2.12M16.95 16.95l2.12 2.12M4.93 19.07l2.12-2.12M16.95 7.05l2.12-2.12" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>
    </svg>
    """
  end

  defp wallet_icon_small(%{name: "Backpack"} = assigns) do
    ~H"""
    <svg class="w-7 h-7 text-white" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
      <path d="M5 8a4 4 0 014-4h6a4 4 0 014 4v9a3 3 0 01-3 3H8a3 3 0 01-3-3V8z"/>
      <path d="M9 4V2.5M15 4V2.5M9 12h6"/>
    </svg>
    """
  end

  defp wallet_icon_small(assigns) do
    ~H"""
    <span class="text-lg font-bold text-white/80"><%= String.first(@name) %></span>
    """
  end

  defp wallet_icon_large(%{name: "Phantom"} = assigns) do
    ~H"""
    <svg class="w-12 h-12 text-white" viewBox="0 0 128 128" fill="currentColor">
      <path d="M64 16c-24.3 0-44 19.7-44 44 0 24.3 19.7 44 44 44 4.4 0 8-3.6 8-8v-8c0-2.2 1.8-4 4-4s4 1.8 4 4v8c0 4.4 3.6 8 8 8 16.6 0 28-13.4 28-30 0-32.6-26.4-58-52-58zM44 60c-3.3 0-6 2.7-6 6s2.7 6 6 6 6-2.7 6-6-2.7-6-6-6zm32 0c-3.3 0-6 2.7-6 6s2.7 6 6 6 6-2.7 6-6-2.7-6-6-6z"/>
    </svg>
    """
  end

  defp wallet_icon_large(%{name: "Solflare"} = assigns) do
    ~H"""
    <svg class="w-12 h-12 text-white" viewBox="0 0 24 24" fill="currentColor">
      <circle cx="12" cy="12" r="4"/>
      <path d="M12 2v3M12 19v3M2 12h3M19 12h3M4.93 4.93l2.12 2.12M16.95 16.95l2.12 2.12M4.93 19.07l2.12-2.12M16.95 7.05l2.12-2.12" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>
    </svg>
    """
  end

  defp wallet_icon_large(%{name: "Backpack"} = assigns) do
    ~H"""
    <svg class="w-12 h-12 text-white" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
      <path d="M5 8a4 4 0 014-4h6a4 4 0 014 4v9a3 3 0 01-3 3H8a3 3 0 01-3-3V8z"/>
      <path d="M9 4V2.5M15 4V2.5M9 12h6"/>
    </svg>
    """
  end

  defp wallet_icon_large(assigns) do
    ~H"""
    <span class="text-3xl font-bold text-white/80"><%= String.first(@name) %></span>
    """
  end

  # ── Helpers ─────────────────────────────────────────────────

  defp truncate_address(nil), do: nil
  defp truncate_address(addr) when byte_size(addr) < 8, do: addr
  defp truncate_address(addr) do
    "#{String.slice(addr, 0..3)}...#{String.slice(addr, -4..-1)}"
  end

  defp format_sol(nil), do: nil
  defp format_sol(balance) when is_number(balance) do
    cond do
      balance >= 1000 -> "#{Float.round(balance / 1000, 1)}k"
      balance >= 1 -> "#{Float.round(balance * 1.0, 2)}"
      balance > 0 -> "#{Float.round(balance * 1.0, 4)}"
      true -> "0"
    end
  end
  defp format_sol(_), do: nil
end
