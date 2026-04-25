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
  attr :connecting_provider, :any, default: nil
  attr :social_login_enabled, :boolean, default: true
  attr :email_prefill, :any, default: nil
  attr :email_otp_stage, :any, default: nil
  attr :email_otp_error, :any, default: nil
  attr :email_otp_resend_cooldown, :integer, default: 0
  attr :web3auth_config, :map, default: %{}

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
    <%!-- Web3Auth hook mount point — lazy-loads the SDK on first login attempt.
         Receives config via data attributes; handles start_web3auth_login +
         request_disconnect events from LiveView; pushes web3auth_authenticated
         back with { wallet_address, id_token, verifier, ... }. --%>
    <%= if @social_login_enabled and Map.get(@web3auth_config, :client_id, "") != "" do %>
      <div
        id="web3auth-root"
        phx-hook="Web3Auth"
        data-client-id={@web3auth_config[:client_id]}
        data-rpc-url={@web3auth_config[:rpc_url]}
        data-chain-id={@web3auth_config[:chain_id]}
        data-network={@web3auth_config[:network]}
        data-telegram-verifier-id={@web3auth_config[:telegram_verifier_id]}
        data-telegram-bot-username={@web3auth_config[:telegram_bot_username]}
        data-telegram-bot-id={@web3auth_config[:telegram_bot_id]}
        class="hidden"
      ></div>
    <% end %>

    <%!-- Modal visible when: wallet selector open OR connecting to wallet OR connecting to web3auth --%>
    <%= if @show || (@connecting && (@connecting_wallet_name || @connecting_provider)) do %>
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

        <%= cond do %>
          <% @connecting and @connecting_wallet -> %>
            <%!-- ── STATE B: Connecting to wallet ── --%>
            <div
              phx-click-away="hide_wallet_selector"
              class="relative w-full max-w-[440px] bg-white rounded-3xl overflow-hidden ring-1 ring-black/5"
              style="box-shadow: 0 30px 80px -15px rgba(0,0,0,0.4); animation: walletSlideUp 200ms ease-out;"
            >
              <div class="flex items-center justify-end px-6 pt-6 pb-2">
                <button
                  phx-click="hide_wallet_selector"
                  class="w-8 h-8 rounded-full bg-neutral-100 hover:bg-neutral-200 grid place-items-center transition-colors cursor-pointer"
                  aria-label="Close"
                >
                  <svg class="w-3.5 h-3.5 text-neutral-600" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
                </button>
              </div>

              <div class="px-6 pt-6 pb-4 flex flex-col items-center text-center">
                <div class="relative mb-5">
                  <div class={"w-20 h-20 rounded-2xl grid place-items-center ring-1 ring-white/40 bg-gradient-to-br #{@connecting_wallet.gradient} #{@connecting_wallet.shadow_lg}"}>
                    <.wallet_icon_large name={@connecting_wallet.name} />
                  </div>
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

              <div class="px-6 pt-2 pb-1">
                <div class="h-1 rounded-full bg-neutral-100 overflow-hidden">
                  <div class="h-full w-full rounded-full wallet-progress-shimmer"></div>
                </div>
              </div>

              <div class="px-6 py-5">
                <div class="space-y-3 text-[12px] font-medium">
                  <div class="flex items-center gap-3">
                    <div class="w-5 h-5 rounded-full bg-[#22C55E] grid place-items-center shrink-0">
                      <svg class="w-3 h-3 text-white" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>
                    </div>
                    <span class="text-[#141414]">Wallet detected</span>
                    <span class="ml-auto text-[10px] font-mono text-neutral-400">0.2s</span>
                  </div>
                  <div class="flex items-center gap-3">
                    <div class="w-5 h-5 rounded-full bg-[#CAFC00] grid place-items-center shrink-0">
                      <div class="w-2 h-2 rounded-full bg-black wallet-pulse-dot"></div>
                    </div>
                    <span class="text-[#141414] font-bold">Awaiting signature…</span>
                    <span class="ml-auto text-[10px] font-mono text-neutral-400">live</span>
                  </div>
                  <div class="flex items-center gap-3 opacity-50">
                    <div class="w-5 h-5 rounded-full border-2 border-dashed border-neutral-300 shrink-0"></div>
                    <span class="text-neutral-500">Verify and sign in</span>
                  </div>
                </div>
              </div>

              <div class="pb-6"></div>
            </div>

          <% @connecting and @connecting_provider -> %>
            <%!-- ── STATE C: Signing in via Web3Auth ─────────────────
                 Provider-aware copy — email goes through a CUSTOM JWT
                 flow with NO popup; OAuth (X/Google) opens a provider
                 popup; Telegram uses its widget. Helpers at the bottom
                 of this module pick the right headline/subline/steps. --%>
            <div
              phx-click-away="hide_wallet_selector"
              class="relative w-full max-w-[440px] bg-white rounded-3xl overflow-hidden ring-1 ring-black/5"
              style="box-shadow: 0 30px 80px -15px rgba(0,0,0,0.4); animation: walletSlideUp 200ms ease-out;"
            >
              <%!-- Atmospheric accent: brand glow bleeds in from the top-right
                   corner. No emphasis, just depth. --%>
              <div
                class="pointer-events-none absolute -top-16 -right-16 w-48 h-48"
                style="background: radial-gradient(circle, rgba(202,252,0,0.16), transparent 65%);"
              ></div>

              <%!-- Top bar — matches State A so the transition feels continuous --%>
              <div class="relative flex items-center justify-between px-6 pt-6 pb-2">
                <div class="flex items-center gap-2">
                  <img src="https://ik.imagekit.io/blockster/blockster-icon.png" alt="" class="w-6 h-6 rounded-md" />
                  <span class="text-[11px] uppercase tracking-[0.16em] text-neutral-500 font-bold">
                    Signing in
                  </span>
                </div>
                <button
                  phx-click="hide_wallet_selector"
                  class="w-8 h-8 rounded-full bg-neutral-100 hover:bg-neutral-200 grid place-items-center transition-colors cursor-pointer"
                  aria-label="Cancel"
                >
                  <svg class="w-3.5 h-3.5 text-neutral-600" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
                </button>
              </div>

              <%!-- Header: asymmetric, badge-left / text-right --%>
              <div class="relative px-6 pt-7 pb-5">
                <div class="flex items-start gap-4">
                  <div class={"relative w-14 h-14 rounded-2xl grid place-items-center flex-shrink-0 ring-1 ring-white/40 " <> provider_badge_class(@connecting_provider)}>
                    <.provider_icon_medium provider={@connecting_provider} />
                  </div>
                  <div class="flex-1 min-w-0 pt-0.5">
                    <div class="text-[10px] uppercase tracking-[0.2em] text-neutral-400 font-bold mb-1.5">
                      <%= connecting_eyebrow(@connecting_provider) %>
                    </div>
                    <h2 class="text-[22px] font-bold tracking-tight text-[#141414] leading-[1.1] mb-1.5"
                        style="letter-spacing: -0.024em;">
                      <%= connecting_headline(@connecting_provider) %>
                    </h2>
                    <p class="text-[12.5px] text-neutral-500 font-medium leading-relaxed">
                      <%= connecting_subline(@connecting_provider) %>
                    </p>
                  </div>
                </div>
              </div>

              <%!-- Progress: single thin bar with a dark traversing shimmer.
                   Indeterminate — we don't pretend to know step timing. --%>
              <div class="relative px-6 pb-3">
                <div class="relative h-[2px] bg-neutral-200/80 overflow-hidden rounded-full">
                  <div
                    class="absolute inset-y-0 left-[-40%] w-[40%] rounded-full wallet-traverse-bar"
                    style="background: linear-gradient(90deg, transparent, #141414 45%, #141414 55%, transparent);"
                  ></div>
                </div>
              </div>

              <%!-- Step labels — slash-separated, mono. Current step bold.
                   No checkmarks, no pulse dots; just editorial rhythm. --%>
              <div class="px-6 pb-5">
                <div class="flex items-center text-[10.5px] font-mono tracking-tight">
                  <%= for {label, idx} <- Enum.with_index(connecting_steps(@connecting_provider)) do %>
                    <%= if idx > 0 do %>
                      <span class="px-2 text-neutral-300" aria-hidden="true">/</span>
                    <% end %>
                    <span class={if(idx == 0, do: "text-[#141414] font-bold", else: "text-neutral-400")}>
                      <%= label %>
                    </span>
                  <% end %>
                </div>
              </div>

              <%!-- Footer: signal indicator + visible cancel, so the modal
                   is never a dead-end if something stalls. --%>
              <div class="relative px-6 py-4 border-t border-neutral-100 flex items-center justify-between bg-neutral-50/60">
                <div class="flex items-center gap-2 text-[10.5px] text-neutral-500 font-mono">
                  <span class="w-1.5 h-1.5 rounded-full bg-[#141414] wallet-signal-dot"></span>
                  <span>secure channel</span>
                </div>
                <button
                  phx-click="hide_wallet_selector"
                  class="text-[11px] text-neutral-600 hover:text-[#141414] font-bold transition-colors cursor-pointer"
                >
                  Cancel
                </button>
              </div>
            </div>

          <% true -> %>
            <%!-- ── STATE A: Selection (social + wallet) ── --%>
            <div
              phx-click-away="hide_wallet_selector"
              class="relative w-full max-w-[440px] bg-white rounded-3xl overflow-hidden ring-1 ring-black/5"
              style="box-shadow: 0 30px 80px -15px rgba(0,0,0,0.4); animation: walletSlideUp 200ms ease-out;"
            >
              <%!-- Top bar --%>
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
                  <%= if @social_login_enabled, do: "Sign in to Blockster", else: "Connect a Solana wallet" %>
                </h2>
                <p class="text-[13px] text-neutral-500 font-medium leading-relaxed">
                  <%= if @social_login_enabled do %>
                    Sign in with your email or a social account — or connect your Solana wallet.
                  <% else %>
                    Pick the wallet you want to use to sign in. Blockster never sees your seed phrase or private keys.
                  <% end %>
                </p>
              </div>

              <%= if @social_login_enabled do %>
                <%= if @email_otp_stage == :enter_code do %>
                  <%!-- Email OTP — inline, two-step: email collected,
                       now awaiting code. No popup, user stays in our modal. --%>
                  <div class="px-6 pb-3">
                    <div class="flex items-center justify-between mb-3">
                      <div class="min-w-0 flex-1">
                        <div class="text-[10px] uppercase tracking-[0.14em] text-neutral-500 font-bold mb-0.5">
                          Check your inbox
                        </div>
                        <div class="text-[12.5px] text-[#141414] font-medium truncate" title={@email_prefill}>
                          Code sent to {@email_prefill}
                        </div>
                      </div>
                      <button
                        type="button"
                        phx-click="email_otp_back"
                        class="ml-3 shrink-0 inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-[10.5px] text-neutral-500 hover:text-[#141414] bg-neutral-100 hover:bg-neutral-200 transition-colors cursor-pointer"
                        aria-label="Change email"
                      >
                        <svg class="w-3 h-3" viewBox="0 0 20 20" fill="none">
                          <path d="M17 10H5m0 0l4-4m-4 4l4 4" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
                        </svg>
                        Change
                      </button>
                    </div>
                    <form phx-submit="verify_email_otp" class="group">
                      <div class="flex items-stretch rounded-2xl border border-neutral-200 bg-white transition-all duration-150 group-focus-within:border-[#141414] group-focus-within:ring-4 group-focus-within:ring-[#CAFC00]/20">
                        <div class="pl-4 pr-1 grid place-items-center text-neutral-400 group-focus-within:text-[#141414] transition-colors">
                          <svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round">
                            <rect x="3" y="11" width="18" height="10" rx="2"/>
                            <path d="M7 11V7a5 5 0 0 1 10 0v4"/>
                          </svg>
                        </div>
                        <input
                          type="text"
                          inputmode="numeric"
                          pattern="[0-9]*"
                          name="code"
                          placeholder="6-digit code"
                          autocomplete="one-time-code"
                          autofocus
                          maxlength="6"
                          required
                          class="flex-1 min-w-0 bg-transparent px-2.5 py-3.5 text-[14px] text-[#141414] placeholder-neutral-400 outline-none border-0 focus:ring-0 font-mono tracking-[0.22em]"
                        />
                        <button
                          type="submit"
                          class="shrink-0 my-1 mr-1 px-3.5 inline-flex items-center gap-1.5 rounded-xl bg-[#0a0a0a] text-white text-[12px] font-bold hover:bg-[#1a1a22] active:scale-[0.98] transition-all cursor-pointer"
                        >
                          Sign in
                          <svg class="w-3 h-3" viewBox="0 0 20 20" fill="none">
                            <path d="M3 10h12m0 0l-4-4m4 4l-4 4" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
                          </svg>
                        </button>
                      </div>
                      <%= if @email_otp_error do %>
                        <p class="mt-2 pl-1 text-[10.5px] text-[#c0392b] font-mono flex items-center gap-1.5">
                          <span class="w-1 h-1 rounded-full bg-[#c0392b] inline-block"></span>
                          <%= @email_otp_error %>
                        </p>
                      <% else %>
                        <p class="mt-2 pl-1 text-[10.5px] text-neutral-500 font-mono flex items-center gap-1.5">
                          <span class="w-1 h-1 rounded-full bg-[#CAFC00] inline-block"></span>
                          Expires in 10 minutes · check spam if you don't see it
                        </p>
                      <% end %>
                    </form>
                    <div class="mt-2 flex items-center justify-between px-1">
                      <%= if @email_otp_resend_cooldown > 0 do %>
                        <span class="text-[10.5px] text-neutral-400 font-mono">
                          Resend in {@email_otp_resend_cooldown}s
                        </span>
                      <% else %>
                        <button
                          type="button"
                          phx-click="resend_email_otp"
                          class="text-[10.5px] text-neutral-600 hover:text-[#141414] underline underline-offset-2 font-medium cursor-pointer"
                        >
                          Resend code
                        </button>
                      <% end %>
                    </div>
                  </div>
                <% else %>
                  <%!-- Email form: input + flush dark Continue button --%>
                  <div class="px-6 pb-3">
                    <form phx-submit="start_email_login" class="group">
                      <div class="flex items-stretch rounded-2xl border border-neutral-200 bg-white transition-all duration-150 group-focus-within:border-[#141414] group-focus-within:ring-4 group-focus-within:ring-[#CAFC00]/20">
                        <div class="pl-4 pr-1 grid place-items-center text-neutral-400 group-focus-within:text-[#141414] transition-colors">
                          <svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round">
                            <rect x="3" y="5" width="18" height="14" rx="2"/>
                            <path d="M3 7l9 6 9-6"/>
                          </svg>
                        </div>
                        <input
                          type="email"
                          name="email"
                          value={@email_prefill}
                          placeholder="you@email.com"
                          autocomplete="email"
                          required
                          class="flex-1 min-w-0 bg-transparent px-2.5 py-3.5 text-[14px] text-[#141414] placeholder-neutral-400 outline-none border-0 focus:ring-0"
                        />
                        <button
                          type="submit"
                          class="shrink-0 my-1 mr-1 px-3.5 inline-flex items-center gap-1.5 rounded-xl bg-[#0a0a0a] text-white text-[12px] font-bold hover:bg-[#1a1a22] active:scale-[0.98] transition-all cursor-pointer"
                        >
                          Continue
                          <svg class="w-3 h-3" viewBox="0 0 20 20" fill="none">
                            <path d="M3 10h12m0 0l-4-4m4 4l-4 4" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
                          </svg>
                        </button>
                      </div>
                      <%= if @email_otp_error do %>
                        <p class="mt-2 pl-1 text-[10.5px] text-[#c0392b] font-mono flex items-center gap-1.5">
                          <span class="w-1 h-1 rounded-full bg-[#c0392b] inline-block"></span>
                          <%= @email_otp_error %>
                        </p>
                      <% else %>
                        <p class="mt-2 pl-1 text-[10.5px] text-neutral-500 font-mono flex items-center gap-1.5">
                          <span class="w-1 h-1 rounded-full bg-[#CAFC00] inline-block"></span>
                          We'll send a one-time code. No password, no SOL needed.
                        </p>
                      <% end %>
                    </form>
                  </div>
                <% end %>

                <%!-- Social tiles: 3 providers, flat row on all breakpoints --%>
                <div class="px-6 pb-4">
                  <div class="grid grid-cols-3 gap-2">
                    <button
                      type="button"
                      phx-click="start_x_login"
                      class="flex flex-col items-center justify-center gap-1.5 px-2 py-3 rounded-2xl border border-neutral-200 bg-white hover:border-[#141414] hover:bg-neutral-50 active:scale-[0.98] transition-all cursor-pointer"
                      aria-label="Continue with X"
                    >
                      <.provider_icon_small provider="twitter" />
                      <span class="text-[11px] font-bold text-[#141414]">X</span>
                    </button>
                    <button
                      type="button"
                      phx-click="start_google_login"
                      class="flex flex-col items-center justify-center gap-1.5 px-2 py-3 rounded-2xl border border-neutral-200 bg-white hover:border-[#141414] hover:bg-neutral-50 active:scale-[0.98] transition-all cursor-pointer"
                      aria-label="Continue with Google"
                    >
                      <.provider_icon_small provider="google" />
                      <span class="text-[11px] font-bold text-[#141414]">Google</span>
                    </button>
                    <button
                      type="button"
                      phx-click="start_telegram_login"
                      class="flex flex-col items-center justify-center gap-1.5 px-2 py-3 rounded-2xl border border-neutral-200 bg-white hover:border-[#141414] hover:bg-neutral-50 active:scale-[0.98] transition-all cursor-pointer"
                      aria-label="Continue with Telegram"
                    >
                      <.provider_icon_small provider="telegram" />
                      <span class="text-[11px] font-bold text-[#141414]">Telegram</span>
                    </button>
                  </div>
                </div>

                <%!-- Divider --%>
                <div class="px-6 pb-3">
                  <div class="relative flex items-center">
                    <div class="flex-grow border-t border-neutral-200"></div>
                    <span class="mx-3 text-[10px] uppercase tracking-[0.14em] text-neutral-400 font-bold">or connect a wallet</span>
                    <div class="flex-grow border-t border-neutral-200"></div>
                  </div>
                </div>
              <% end %>

              <%!-- Mobile: deeplinks into wallet in-app browsers --%>
              <div class="md:hidden px-4 pb-3">
                <%= if !@social_login_enabled do %>
                  <p class="text-[11px] text-neutral-500 font-medium mb-3 px-1">
                    Open this page inside your wallet's in-app browser to connect.
                  </p>
                <% end %>
                <div class="space-y-2">
                  <%= for wallet <- @wallets, wallet.browse_url do %>
                    <button
                      type="button"
                      id={"open-in-wallet-#{String.downcase(wallet.name)}"}
                      phx-hook="OpenInWallet"
                      data-browse-url={wallet.browse_url}
                      class="w-full flex items-center gap-3 p-3 rounded-2xl border border-neutral-200 hover:border-black/[0.12] bg-white transition-colors cursor-pointer"
                    >
                      <div class={"w-10 h-10 rounded-xl shrink-0 grid place-items-center ring-1 ring-white/30 bg-gradient-to-br #{wallet.gradient} #{wallet.shadow}"}>
                        <.wallet_icon_small name={wallet.name} />
                      </div>
                      <div class="flex-1 text-left min-w-0">
                        <div class="text-[13px] font-bold text-[#141414]">Open in {wallet.name}</div>
                        <div class="text-[11px] text-neutral-500 truncate">{wallet.tagline}</div>
                      </div>
                      <svg class="w-4 h-4 text-neutral-400 shrink-0" viewBox="0 0 20 20" fill="none">
                        <path d="M3 10h12m0 0l-4-4m4 4l-4 4" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
                      </svg>
                    </button>
                  <% end %>
                </div>
              </div>

              <%!-- Desktop wallet rows --%>
              <div class="hidden md:block px-4 pb-2 space-y-2">
                <%= for wallet <- @wallets do %>
                  <div class={"w-full flex items-center gap-4 p-3 rounded-2xl border bg-white text-left transition-all duration-150 " <> if(wallet.detected, do: "border-neutral-200 hover:bg-[#fafaf9] hover:border-black/[0.12] hover:-translate-y-px cursor-pointer", else: "border-neutral-200 opacity-60")}>
                    <div class={"w-12 h-12 rounded-xl shrink-0 grid place-items-center ring-1 ring-white/30 bg-gradient-to-br #{wallet.gradient} #{wallet.shadow}"}>
                      <.wallet_icon_small name={wallet.name} />
                    </div>
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

              <%!-- Footer: condensed trust line --%>
              <div class="px-6 pt-5 pb-6 mt-2 border-t border-neutral-100">
                <div class="flex items-start gap-2.5">
                  <div class="w-5 h-5 rounded-full bg-[#CAFC00]/15 border border-[#CAFC00]/30 grid place-items-center shrink-0 mt-px">
                    <svg class="w-2.5 h-2.5 text-[#141414]" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round"><path d="M9 12l2 2 4-4"/><circle cx="12" cy="12" r="9"/></svg>
                  </div>
                  <div class="text-[10.5px] text-neutral-500 font-medium leading-relaxed">
                    Blockster never sees your seed phrase or private keys. By continuing you agree to our <a href="/terms" class="underline hover:text-[#141414] transition-colors">Terms</a> and <a href="/privacy" class="underline hover:text-[#141414] transition-colors">Privacy</a>.
                  </div>
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
      @keyframes walletTraverse {
        0%   { transform: translateX(0); }
        100% { transform: translateX(350%); }
      }
      .wallet-traverse-bar {
        animation: walletTraverse 1.6s cubic-bezier(0.6, 0, 0.3, 1) infinite;
      }
      @keyframes walletSignalBreathe {
        0%, 100% { opacity: 1; transform: scale(1); }
        50%      { opacity: 0.35; transform: scale(0.8); }
      }
      .wallet-signal-dot {
        animation: walletSignalBreathe 2.2s cubic-bezier(0.4, 0, 0.6, 1) infinite;
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

  # ── Web3Auth Provider Icons (small, for social tile grid) ────

  defp provider_icon_small(%{provider: "twitter"} = assigns) do
    ~H"""
    <svg class="w-5 h-5 text-[#141414]" viewBox="0 0 24 24" fill="currentColor">
      <path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z"/>
    </svg>
    """
  end

  defp provider_icon_small(%{provider: "google"} = assigns) do
    ~H"""
    <svg class="w-5 h-5" viewBox="0 0 24 24">
      <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"/>
      <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/>
      <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"/>
      <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"/>
    </svg>
    """
  end

  defp provider_icon_small(%{provider: "telegram"} = assigns) do
    ~H"""
    <svg class="w-5 h-5" viewBox="0 0 24 24" fill="none">
      <circle cx="12" cy="12" r="11" fill="#229ED9"/>
      <path d="M5.5 11.5l12.4-4.8c.6-.2 1.1.1.9.9l-2.1 9.9c-.1.5-.5.7-1 .4l-2.9-2.1-1.4 1.3c-.2.2-.3.3-.6.3l.2-3.2 5.8-5.2c.3-.2-.1-.3-.4-.1L9.2 12.6l-3.1-1c-.7-.2-.7-.7.4-1.1z" fill="white"/>
    </svg>
    """
  end

  defp provider_icon_small(assigns) do
    ~H"""
    <span class="text-sm font-bold text-[#141414]">?</span>
    """
  end

  # Medium provider icons — sized for the 56×56 badge in State C.
  # Keep the glyph inset (≈24px) so the badge's color carries most of the weight.

  defp provider_icon_medium(%{provider: "email"} = assigns) do
    ~H"""
    <svg class="w-6 h-6 text-white" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round">
      <rect x="3" y="5" width="18" height="14" rx="2"/>
      <path d="M3 7l9 6 9-6"/>
    </svg>
    """
  end

  defp provider_icon_medium(%{provider: "twitter"} = assigns) do
    ~H"""
    <svg class="w-6 h-6 text-white" viewBox="0 0 24 24" fill="currentColor">
      <path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z"/>
    </svg>
    """
  end

  defp provider_icon_medium(%{provider: "google"} = assigns) do
    ~H"""
    <svg class="w-6 h-6" viewBox="0 0 24 24">
      <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"/>
      <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/>
      <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"/>
      <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"/>
    </svg>
    """
  end

  defp provider_icon_medium(%{provider: "telegram"} = assigns) do
    ~H"""
    <svg class="w-7 h-7" viewBox="0 0 24 24" fill="none">
      <path d="M5.5 11.5l12.4-4.8c.6-.2 1.1.1.9.9l-2.1 9.9c-.1.5-.5.7-1 .4l-2.9-2.1-1.4 1.3c-.2.2-.3.3-.6.3l.2-3.2 5.8-5.2c.3-.2-.1-.3-.4-.1L9.2 12.6l-3.1-1c-.7-.2-.7-.7.4-1.1z" fill="white"/>
    </svg>
    """
  end

  defp provider_icon_medium(assigns) do
    ~H"""
    <span class="text-2xl font-bold text-white/80">?</span>
    """
  end

  defp provider_badge_class("email"),
    do: "bg-gradient-to-br from-neutral-800 to-neutral-900 shadow-[0_8px_24px_rgba(20,20,20,0.35)]"

  defp provider_badge_class("twitter"),
    do: "bg-gradient-to-br from-[#141414] to-[#0a0a0a] shadow-[0_8px_24px_rgba(0,0,0,0.4)]"

  defp provider_badge_class("google"),
    do: "bg-white shadow-[0_8px_24px_rgba(66,133,244,0.25)] ring-1 ring-neutral-200"

  defp provider_badge_class("telegram"),
    do: "bg-gradient-to-br from-[#37BBE4] to-[#1C93D1] shadow-[0_8px_24px_rgba(34,158,217,0.4)]"

  defp provider_badge_class(_),
    do: "bg-gradient-to-br from-neutral-700 to-neutral-800"

  # Eyebrow / headline / subline / steps for State C.
  # Each provider takes a different path — the email flow uses a CUSTOM JWT
  # so it NEVER opens a popup, while OAuth providers do. The copy reflects
  # that so users aren't hunting for a popup that'll never appear.

  defp connecting_eyebrow("email"), do: "Email sign-in"
  defp connecting_eyebrow("twitter"), do: "Sign in via X"
  defp connecting_eyebrow("google"), do: "Sign in via Google"
  defp connecting_eyebrow("telegram"), do: "Sign in via Telegram"
  defp connecting_eyebrow(_), do: "Signing in"

  defp connecting_headline("email"), do: "Signing you in"
  defp connecting_headline("twitter"), do: "Opening X"
  defp connecting_headline("google"), do: "Opening Google"
  defp connecting_headline("telegram"), do: "Opening Telegram"
  defp connecting_headline(_), do: "One moment"

  defp connecting_subline("email"),
    do: "No popup — we're finishing things up here. Stay on this tab."

  defp connecting_subline("twitter"),
    do: "Approve the sign-in in the X popup that just opened. We'll bring you back when it's done."

  defp connecting_subline("google"),
    do: "Approve the sign-in in the Google popup. We'll bring you back when it's done."

  defp connecting_subline("telegram"),
    do: "Approve the Blockster login in Telegram's confirmation widget."

  defp connecting_subline(_),
    do: "Hang on — we're finishing up."

  defp connecting_steps("email"), do: ["Verifying", "Generating keys", "Finishing up"]
  defp connecting_steps("twitter"), do: ["Popup open", "Awaiting approval", "Finishing up"]
  defp connecting_steps("google"), do: ["Popup open", "Awaiting approval", "Finishing up"]
  defp connecting_steps("telegram"), do: ["Widget open", "Awaiting approval", "Finishing up"]
  defp connecting_steps(_), do: ["Starting", "Working", "Finishing"]

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
