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
      icon: "/images/wallets/phantom.svg"
    },
    %{
      name: "Solflare",
      url: "https://solflare.com",
      browse_url: "https://solflare.com/ul/v1/browse/",
      icon: "/images/wallets/solflare.svg"
    },
    %{
      name: "Backpack",
      url: "https://backpack.app",
      browse_url: nil,
      icon: "/images/wallets/backpack.png"
    }
  ]

  # ── Connect Button ──────────────────────────────────────────

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

  def wallet_selector_modal(assigns) do
    detected_names =
      Enum.map(assigns.detected_wallets, fn w ->
        (w["name"] || w[:name] || "") |> String.downcase()
      end)

    wallets =
      Enum.map(@wallet_registry, fn w ->
        Map.put(w, :detected, String.downcase(w.name) in detected_names)
      end)

    assigns = assign(assigns, :wallets, wallets)

    ~H"""
    <%= if @show do %>
      <%!-- Backdrop --%>
      <div
        phx-click="hide_wallet_selector"
        class="fixed inset-0 z-50 flex items-center justify-center p-4
               bg-black/60 backdrop-blur-sm
               animate-in fade-in duration-150"
        style="animation: fadeIn 150ms ease-out;"
      >
        <%!-- Modal card --%>
        <div
          phx-click-away="hide_wallet_selector"
          class="relative w-full max-w-sm
                 bg-gray-900 border border-gray-700/60 rounded-2xl
                 shadow-2xl shadow-black/40
                 overflow-hidden"
          style="animation: slideUp 200ms ease-out;"
        >
          <%!-- Header --%>
          <div class="flex items-center justify-between px-6 pt-6 pb-4">
            <h3 class="text-lg font-haas_medium_65 text-white tracking-tight">
              Connect Wallet
            </h3>
            <button
              phx-click="hide_wallet_selector"
              class="p-1.5 rounded-lg text-white/40 hover:text-white/80 hover:bg-white/5
                     transition-colors cursor-pointer"
            >
              <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>

          <%!-- Subtitle --%>
          <p class="px-6 pb-5 text-sm font-haas_roman_55 text-white/40 -mt-1">
            Choose a Solana wallet to sign in
          </p>

          <%!-- Wallet options --%>
          <div class="px-4 pb-5 space-y-2">
            <%= for wallet <- @wallets do %>
              <div class={"flex items-center gap-4 p-3.5 rounded-xl transition-all duration-150
                          #{if wallet.detected, do: "bg-white/[0.04] hover:bg-white/[0.07] cursor-pointer", else: "opacity-50"}"}>
                <%!-- Icon --%>
                <div class="w-10 h-10 rounded-xl overflow-hidden flex-shrink-0 bg-gray-800 flex items-center justify-center">
                  <img
                    src={wallet.icon}
                    alt={wallet.name}
                    class="w-8 h-8 rounded-lg"
                    onerror={"this.style.display='none'; this.parentElement.innerHTML='<span class=\"text-lg font-bold text-white/60\">#{String.first(wallet.name)}</span>'"}
                  />
                </div>

                <%!-- Name + status --%>
                <div class="flex-1 min-w-0">
                  <div class="font-haas_medium_65 text-white text-sm"><%= wallet.name %></div>
                  <%= if wallet.detected do %>
                    <div class="text-xs font-haas_roman_55 text-emerald-400/70 flex items-center gap-1 mt-0.5">
                      <span class="w-1.5 h-1.5 rounded-full bg-emerald-400/80 inline-block"></span>
                      Detected
                    </div>
                  <% else %>
                    <div class="text-xs font-haas_roman_55 text-white/30 mt-0.5">Not installed</div>
                  <% end %>
                </div>

                <%!-- Action button --%>
                <%= if wallet.detected do %>
                  <button
                    phx-click="select_wallet"
                    phx-value-name={wallet.name}
                    disabled={@connecting}
                    class="px-4 py-1.5 rounded-lg text-xs font-haas_medium_65
                           bg-white text-gray-900
                           hover:bg-gray-100 active:scale-[0.96]
                           disabled:opacity-40 disabled:cursor-not-allowed
                           transition-all duration-150 cursor-pointer"
                  >
                    Connect
                  </button>
                <% else %>
                  <%!-- Desktop: link to website. Mobile: deep link if available --%>
                  <a
                    href={wallet.url}
                    target="_blank"
                    rel="noopener"
                    class="px-4 py-1.5 rounded-lg text-xs font-haas_medium_65
                           border border-gray-600 text-white/60
                           hover:border-gray-500 hover:text-white/80
                           transition-all duration-150"
                  >
                    Install
                  </a>
                <% end %>
              </div>
            <% end %>
          </div>

          <%!-- Footer --%>
          <div class="px-6 pb-5 pt-1 border-t border-white/[0.04]">
            <p class="text-[11px] font-haas_roman_55 text-white/20 text-center leading-relaxed mt-3">
              By connecting, you agree to our Terms of Service
            </p>
          </div>
        </div>
      </div>
    <% end %>

    <style>
      @keyframes fadeIn {
        from { opacity: 0; }
        to { opacity: 1; }
      }
      @keyframes slideUp {
        from { opacity: 0; transform: translateY(12px) scale(0.97); }
        to { opacity: 1; transform: translateY(0) scale(1); }
      }
    </style>
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
