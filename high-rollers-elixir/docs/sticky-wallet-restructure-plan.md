# High Rollers Site Restructure: Sticky Wallet LiveView

## Problem Statement

The current architecture wraps each tab's LiveView (MintLive, SalesLive, AffiliatesLive, etc.) in a `<Layouts.app>` component that contains:
- Header with wallet button/info
- Hero banner
- Tab navigation
- Footer
- Wallet modal

**Issues with current approach:**
1. **Wallet UI flashes on tab changes** - The entire layout re-renders when navigating between tabs, causing visible flicker
2. **Balance cannot be updated reactively** - Since the wallet display is in a function component (not a LiveView), it can't receive PubSub broadcasts or handle_info messages
3. **State duplication** - Each tab LiveView must pass wallet state (`@wallet_connected`, `@wallet_address`, `@wallet_balance`, etc.) to the layout
4. **WalletHook attaches to layout element** - When layout re-renders, the hook's DOM element is destroyed and recreated, breaking connection state

## Solution: Nested Sticky LiveView for Wallet

Use Phoenix LiveView's `live_render/3` with `sticky: true` to create a persistent wallet LiveView that:
- Survives navigation between tabs
- Manages its own state independently
- Receives PubSub broadcasts for balance updates
- Handles wallet events directly

### Architecture Overview

```
root.html.heex (static HTML)
└── live.html.heex (LiveView layout template)
    ├── WalletLive (sticky: true) - persistent wallet UI
    ├── Header (static - no wallet info)
    ├── Hero Banner (static)
    ├── Tab Navigation (static)
    └── @inner_content - tab LiveViews
        ├── MintLive
        ├── SalesLive
        ├── AffiliatesLive
        ├── MyNFTsLive
        └── RevenuesLive
```

## Implementation Plan

### Phase 1: Create WalletLive LiveView

Create a new LiveView specifically for wallet state and UI.

**File: `lib/high_rollers_web/live/wallet_live.ex`**

```elixir
defmodule HighRollersWeb.WalletLive do
  @moduledoc """
  Sticky LiveView for wallet state management.

  This LiveView persists across tab navigation and handles:
  - Wallet connection/disconnection
  - Balance display and updates
  - Chain switching
  - Wallet modal

  Communicates with JavaScript via WalletHook attached to this LiveView.
  """
  use HighRollersWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to balance update broadcasts
      Phoenix.PubSub.subscribe(HighRollers.PubSub, "wallet_events")
    end

    {:ok,
     socket
     |> assign(:wallet_address, nil)
     |> assign(:wallet_connected, false)
     |> assign(:wallet_balance, nil)
     |> assign(:wallet_type, nil)
     |> assign(:current_chain, "arbitrum")
     |> assign(:show_modal, false)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="wallet-section" phx-hook="WalletHook">
      <!-- Connect Button (shown when disconnected) -->
      <button
        :if={!@wallet_connected}
        id="connect-btn"
        class="bg-purple-600 hover:bg-purple-700 px-6 py-2 rounded-lg cursor-pointer transition-colors"
        phx-click="show_modal"
      >
        Connect Wallet
      </button>

      <!-- Wallet Info (shown when connected) -->
      <div
        :if={@wallet_connected}
        id="wallet-info"
        class="flex items-center gap-3 bg-gray-700 px-4 py-2 rounded-lg"
      >
        <img id="wallet-logo" src={wallet_logo(@wallet_type)} alt="" class="w-6 h-6" />
        <span id="wallet-address" class="text-gray-300 font-mono"><%= truncate_address(@wallet_address) %></span>
        <div class="flex items-baseline gap-1.5">
          <img id="chain-logo" src={chain_logo(@current_chain)} alt="" class="w-4 h-4 self-center" />
          <span id="wallet-balance" class="text-green-400 font-bold"><%= format_balance(@wallet_balance) %></span>
          <span id="wallet-currency" class="text-gray-400 text-sm"><%= chain_currency(@current_chain) %></span>
        </div>
        <button id="disconnect-btn" class="text-gray-400 hover:text-white ml-2 cursor-pointer" phx-click="disconnect">
          ✕
        </button>
      </div>

      <!-- Wallet Modal -->
      <.wallet_modal :if={@show_modal} />
    </div>
    """
  end

  # Event handlers for wallet_connected, wallet_disconnected, balance_updated, etc.
  # These are pushed from JavaScript WalletHook

  @impl true
  def handle_event("wallet_connected", params, socket) do
    # ... handle connection
  end

  @impl true
  def handle_event("wallet_disconnected", _params, socket) do
    # ... handle disconnection
  end

  @impl true
  def handle_event("balance_updated", %{"balance" => balance}, socket) do
    {:noreply, assign(socket, :wallet_balance, balance)}
  end

  @impl true
  def handle_event("show_modal", _params, socket) do
    {:noreply, assign(socket, :show_modal, true)}
  end

  @impl true
  def handle_event("hide_modal", _params, socket) do
    {:noreply, assign(socket, :show_modal, false)}
  end

  # Handle PubSub broadcasts for balance updates from other parts of the app
  @impl true
  def handle_info({:balance_updated, %{address: address, balance: balance}}, socket) do
    if socket.assigns.wallet_address == address do
      {:noreply, assign(socket, :wallet_balance, balance)}
    else
      {:noreply, socket}
    end
  end

  # Helper functions...
end
```

### Phase 2: Create `live.html.heex` Layout Template

Move the header, hero, and navigation from `Layouts.app` function component to a proper LiveView layout template.

**File: `lib/high_rollers_web/components/layouts/live.html.heex`**

```heex
<div id="app">
  <!-- Header with Sticky Wallet LiveView -->
  <header class="bg-gray-800 p-4 flex justify-between items-center">
    <a href="/" class="flex items-center gap-3 cursor-pointer">
      <h1 class="text-2xl font-bold text-purple-400">High Rollers NFTs</h1>
    </a>

    <!-- Sticky Wallet LiveView - survives navigation -->
    <%= live_render(@socket, HighRollersWeb.WalletLive,
      id: "wallet-liveview",
      session: %{},
      sticky: true
    ) %>
  </header>

  <!-- Hero Banner (static - no wallet state needed) -->
  <section class="relative h-96 overflow-hidden bg-gradient-to-r from-purple-900 to-pink-900">
    <!-- ... hero content ... -->
  </section>

  <!-- Navigation Tabs -->
  <nav class="bg-gray-800 border-b border-gray-700 sticky top-0 z-40">
    <div class="container mx-auto flex overflow-x-auto">
      <.tab_button path="/" label="Mint" current={@current_path} />
      <.tab_button path="/sales" label="Live Sales" current={@current_path} />
      <.tab_button path="/affiliates" label="Affiliates" current={@current_path} />
      <.tab_button path="/my-nfts" label="My NFTs" current={@current_path} />
      <.tab_button path="/revenues" label="My Earnings" current={@current_path} />
    </div>
  </nav>

  <!-- Main Content - Tab LiveViews render here -->
  <main>
    <%= @inner_content %>
  </main>

  <!-- Footer -->
  <footer class="bg-gray-800 border-t border-gray-700 mt-12 py-8">
    <!-- ... footer content ... -->
  </footer>

  <!-- Flash Messages -->
  <.flash_group flash={@flash} />

  <!-- Toast Container -->
  <div id="toast-container" class="fixed bottom-4 right-4 z-50 space-y-2"></div>
</div>
```

### Phase 3: Update Router Configuration

Update the router to use the new live layout and remove WalletHook from on_mount.

**File: `lib/high_rollers_web/router.ex`**

```elixir
scope "/", HighRollersWeb do
  pipe_through :browser

  # Use live.html.heex as the LiveView layout
  # Remove WalletHook from on_mount - wallet state now managed by WalletLive
  live_session :default,
    layout: {HighRollersWeb.Layouts, :live},
    on_mount: [{HighRollersWeb.Hooks.CurrentPath, :default}] do

    live "/", MintLive, :index
    live "/mint", MintLive, :index
    live "/sales", SalesLive, :index
    live "/affiliates", AffiliatesLive, :index
    live "/my-nfts", MyNFTsLive, :index
    live "/revenues", RevenuesLive, :index
  end
end
```

### Phase 4: Create CurrentPath Hook

Simple hook to set `@current_path` for tab highlighting.

**File: `lib/high_rollers_web/live/hooks/current_path.ex`**

```elixir
defmodule HighRollersWeb.Hooks.CurrentPath do
  @moduledoc """
  Sets @current_path for tab navigation highlighting.
  """
  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 2]

  def on_mount(:default, _params, _session, socket) do
    current_path = case socket.private[:live_view_module] do
      HighRollersWeb.MintLive -> "/"
      HighRollersWeb.SalesLive -> "/sales"
      HighRollersWeb.AffiliatesLive -> "/affiliates"
      HighRollersWeb.MyNFTsLive -> "/my-nfts"
      HighRollersWeb.RevenuesLive -> "/revenues"
      _ -> "/"
    end

    {:cont, assign(socket, :current_path, current_path)}
  end
end
```

### Phase 5: Update Tab LiveViews

Remove the `<Layouts.app>` wrapper from each tab's template since it's now in `live.html.heex`.

**Before (`mint_live.html.heex`):**
```heex
<Layouts.app flash={@flash} current_path={@current_path} wallet_connected={@wallet_connected} ...>
  <div class="container mx-auto p-6">
    <!-- content -->
  </div>
</Layouts.app>
```

**After (`mint_live.html.heex`):**
```heex
<div class="container mx-auto p-6">
  <!-- content -->
</div>
```

### Phase 6: Cross-LiveView Communication

Tab LiveViews may need to know wallet state (e.g., to show "Connect Wallet" prompts). Use PubSub for this.

**WalletLive broadcasts wallet state changes:**
```elixir
def handle_event("wallet_connected", params, socket) do
  address = String.downcase(params["address"])

  # Broadcast to all subscribers
  Phoenix.PubSub.broadcast(HighRollers.PubSub, "wallet_events",
    {:wallet_connected, %{address: address, type: params["type"]}})

  {:noreply,
   socket
   |> assign(:wallet_address, address)
   |> assign(:wallet_connected, true)
   |> assign(:wallet_type, params["type"])}
end
```

**Tab LiveViews subscribe and react:**
```elixir
def mount(_params, _session, socket) do
  if connected?(socket) do
    Phoenix.PubSub.subscribe(HighRollers.PubSub, "wallet_events")
  end

  {:ok, assign(socket, :wallet_address, nil)}
end

def handle_info({:wallet_connected, %{address: address}}, socket) do
  {:noreply, assign(socket, :wallet_address, address)}
end
```

### Phase 7: Update JavaScript WalletHook

The WalletHook no longer needs to manage DOM elements directly since WalletLive handles the UI. However, it still bridges ethers.js to LiveView.

Key changes:
- Remove DOM manipulation for showing/hiding wallet info
- Keep ethers.js integration
- Push events to the nested WalletLive instead of parent LiveView

```javascript
// The hook is now attached to WalletLive's root element
// Events go directly to WalletLive
this.pushEvent("wallet_connected", {
  address: this.address,
  type: wallet.type,
  chain: this.currentChain,
  balance: balance
})
```

## File Changes Summary

| File | Action | Description |
|------|--------|-------------|
| `lib/high_rollers_web/live/wallet_live.ex` | CREATE | New sticky LiveView for wallet |
| `lib/high_rollers_web/live/wallet_live.html.heex` | CREATE | Template for wallet UI |
| `lib/high_rollers_web/components/layouts/live.html.heex` | CREATE | LiveView layout with sticky wallet |
| `lib/high_rollers_web/live/hooks/current_path.ex` | CREATE | Simple hook for tab highlighting |
| `lib/high_rollers_web/router.ex` | MODIFY | Update live_session config |
| `lib/high_rollers_web/components/layouts.ex` | MODIFY | Add `:live` layout embed, simplify `app` |
| `lib/high_rollers_web/live/wallet_hook.ex` | DELETE | No longer needed (replaced by WalletLive) |
| `lib/high_rollers_web/live/mint_live.html.heex` | MODIFY | Remove `<Layouts.app>` wrapper |
| `lib/high_rollers_web/live/sales_live.html.heex` | MODIFY | Remove `<Layouts.app>` wrapper |
| `lib/high_rollers_web/live/affiliates_live.html.heex` | MODIFY | Remove `<Layouts.app>` wrapper |
| `lib/high_rollers_web/live/my_nfts_live.html.heex` | MODIFY | Remove `<Layouts.app>` wrapper |
| `lib/high_rollers_web/live/revenues_live.html.heex` | MODIFY | Remove `<Layouts.app>` wrapper |
| `assets/js/hooks/wallet_hook.js` | MODIFY | Remove DOM manipulation, keep ethers.js |

## Benefits

1. **No more flashing** - WalletLive persists across navigation
2. **Reactive balance updates** - WalletLive can receive PubSub broadcasts
3. **Cleaner tab LiveViews** - No need to pass wallet state to layout
4. **Better separation of concerns** - Wallet logic isolated in its own LiveView
5. **Simpler templates** - No `<Layouts.app>` wrapper needed

## Testing Checklist

- [ ] Wallet connects and shows balance
- [ ] Navigate between tabs - wallet stays connected, no flash
- [ ] Mint an NFT - balance updates without page refresh
- [ ] Withdraw rewards - balance updates
- [ ] Disconnect wallet - UI updates across all tabs
- [ ] Refresh page - wallet auto-reconnects
- [ ] Mobile deep linking still works
- [ ] Chain switching (Arbitrum ↔ Rogue) works

## Rollback Plan

If issues arise:
1. Revert to function component layout (`<Layouts.app>`)
2. Re-add WalletHook to on_mount
3. Re-add `<Layouts.app>` wrappers to tab templates

Keep the old `Layouts.app` function component until the new architecture is fully tested.
