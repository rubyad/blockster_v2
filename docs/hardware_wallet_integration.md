# Hardware Wallet Integration with Thirdweb

## Overview

Allow Blockster users to connect external hardware wallets (MetaMask, Ledger, Trezor, etc.) to their email-based accounts for:
1. **Token transfers** between hardware wallet and Blockster smart wallet
2. **Balance reading** across multiple chains and tokens
3. **Wallet Multiplier boosts** based on ETH + other token holdings (NOT ROGUE - see note below)
4. **Direct transactions** from hardware wallet (non-AA) with user confirmation

> **Important V2 Change (Jan 2026)**: The multiplier system has been refactored into a **Unified Multiplier System** with 4 separate components:
> - **X Multiplier** (1.0x - 10.0x): Based on X account quality score
> - **Phone Multiplier** (0.5x - 2.0x): Based on phone verification + geo tier
> - **ROGUE Multiplier** (1.0x - 5.0x): Based on ROGUE in **Blockster smart wallet only** (NOT external wallet)
> - **Wallet Multiplier** (1.0x - 3.6x): Based on ETH + other tokens in **external wallet** (NO ROGUE)
>
> See `docs/unified_multiplier_system_v2.md` for complete details on the unified system.

## Table of Contents
- [Architecture](#architecture)
- [Thirdweb Integration](#thirdweb-integration)
- [Wallet Setup](#wallet-setup)
- [Multiplier System](#multiplier-system)
- [Balance Reading](#balance-reading)
- [Token Transfers](#token-transfers)
- [Database Schema](#database-schema)
- [UI Components](#ui-components)
- [Security Considerations](#security-considerations)
- [Implementation Plan](#implementation-plan)

---

## Architecture

### Wallet Types in Blockster

| Wallet Type | Purpose | Account Abstraction | Gas Fees |
|-------------|---------|---------------------|----------|
| **Blockster Smart Wallet** | Primary account (email-based) | Yes (ERC-4337) | Gasless (Paymaster) |
| **Connected Hardware Wallet** | External EOA for transfers/holdings | No | User pays gas |

### Key Principle
- **Blockster wallet** = User's primary identity (email, username, profile)
- **Hardware wallet** = Optional enhancement for transfers, holdings verification, and direct blockchain interactions

---

## Thirdweb Integration

### Wallet Connection Flow

**Note**: We use the vanilla JavaScript Thirdweb SDK (same as the existing smart wallet system), NOT the React SDK.

```javascript
// File: assets/js/connect_wallet_hook.js

import { createWallet } from "thirdweb/wallets";
import { defineChain } from "thirdweb/chains";

// Use the global thirdwebClient initialized in home_hooks.js
// Use the global rogueChain defined in home_hooks.js

export const ConnectWalletHook = {
  mounted() {
    this.connectedWallet = null;
    this.connectedAccount = null;

    // Listen for wallet connection request from LiveView
    this.handleEvent("connect_wallet", async ({ provider }) => {
      try {
        console.log("[ConnectWallet] Connecting to:", provider);

        // Create wallet instance based on provider
        let wallet;

        switch(provider) {
          case "metamask":
            wallet = createWallet("io.metamask");
            break;
          case "coinbase":
            wallet = createWallet("com.coinbase.wallet");
            break;
          case "walletconnect":
            wallet = createWallet("walletConnect", {
              projectId: window.WALLETCONNECT_PROJECT_ID // Set in root.html.heex
            });
            break;
          case "phantom":
            wallet = createWallet("app.phantom");
            break;
          default:
            throw new Error(`Unknown provider: ${provider}`);
        }

        // Connect wallet
        const account = await wallet.connect({
          client: window.thirdwebClient
        });

        // Switch to Rogue Chain (will add network if not present)
        await wallet.switchChain(window.rogueChain);

        this.connectedWallet = wallet;
        this.connectedAccount = account;

        console.log("[ConnectWallet] Connected:", account.address);

        // Setup Rogue Chain network and import ROGUE token on Arbitrum
        await this.setupWalletNetworksAndTokens(wallet, provider);

        // Send wallet address to Phoenix
        this.pushEvent("wallet_connected", {
          address: account.address,
          provider: provider,
          chain_id: window.rogueChain.id
        });

      } catch (error) {
        console.error("[ConnectWallet] Connection failed:", error);

        // Parse user-friendly error message
        let errorMessage = error.message;
        if (error.message.includes("User rejected")) {
          errorMessage = "Connection cancelled by user";
        } else if (error.message.includes("No injected provider")) {
          errorMessage = `${provider} wallet not found. Please install the extension.`;
        }

        this.pushEvent("wallet_connection_error", {
          error: errorMessage,
          provider: provider
        });
      }
    });

    // Disconnect wallet
    this.handleEvent("disconnect_wallet", async () => {
      try {
        if (this.connectedWallet) {
          await this.connectedWallet.disconnect();
          this.connectedWallet = null;
          this.connectedAccount = null;
        }
        this.pushEvent("wallet_disconnected", {});
      } catch (error) {
        console.error("[ConnectWallet] Disconnect failed:", error);
      }
    });
  },

  /**
   * Setup wallet networks and import tokens
   * - Adds Rogue Chain network if not already present
   * - Imports ROGUE token on Arbitrum One if not already added
   */
  async setupWalletNetworksAndTokens(wallet, provider) {
    try {
      // MetaMask and Coinbase Wallet support wallet_addEthereumChain
      const supportsNetworkManagement = provider === "metamask" || provider === "coinbase";

      if (!supportsNetworkManagement) {
        console.log("[ConnectWallet] Wallet doesn't support network management");
        return;
      }

      // 1. Add Rogue Chain network if not present
      await this.ensureRogueChainNetwork(wallet);

      // 2. Import ROGUE token on Arbitrum One
      await this.importROGUETokenOnArbitrum(wallet);

    } catch (error) {
      console.warn("[ConnectWallet] Network/token setup failed (non-critical):", error);
      // Don't fail the connection if network setup fails
    }
  },

  /**
   * Ensure Rogue Chain network is added to the wallet
   */
  async ensureRogueChainNetwork(wallet) {
    try {
      const rogueChainParams = {
        chainId: "0x88CED", // 560013 in hex
        chainName: "Rogue Chain Mainnet",
        nativeCurrency: {
          name: "ROGUE",
          symbol: "ROGUE",
          decimals: 18
        },
        rpcUrls: ["https://rpc.roguechain.io/rpc"],
        blockExplorerUrls: ["https://roguescan.io"]
      };

      // Try to switch to Rogue Chain
      try {
        await wallet.switchChain(window.rogueChain);
        console.log("[ConnectWallet] Rogue Chain already added");
      } catch (switchError) {
        // If switch fails, network doesn't exist - add it
        if (switchError.code === 4902) {
          console.log("[ConnectWallet] Adding Rogue Chain network...");

          await window.ethereum.request({
            method: "wallet_addEthereumChain",
            params: [rogueChainParams]
          });

          console.log("[ConnectWallet] Rogue Chain network added successfully");
        } else {
          throw switchError;
        }
      }
    } catch (error) {
      console.error("[ConnectWallet] Failed to add Rogue Chain:", error);
      throw error;
    }
  },

  /**
   * Import ROGUE token on Arbitrum One
   */
  async importROGUETokenOnArbitrum(wallet) {
    try {
      const ROGUE_ARBITRUM = "0x88b8d272b9f1bab7d7896f5f88f8825ce14b05bd";

      console.log("[ConnectWallet] Importing ROGUE token on Arbitrum One...");

      await window.ethereum.request({
        method: "wallet_watchAsset",
        params: {
          type: "ERC20",
          options: {
            address: ROGUE_ARBITRUM,
            symbol: "ROGUE",
            decimals: 18,
            image: "https://roguechain.io/rogue-logo.png" // Optional: add actual logo URL
          }
        }
      });

      console.log("[ConnectWallet] ROGUE token import requested");
    } catch (error) {
      // User may reject token import - this is non-critical
      if (error.code === 4001) {
        console.log("[ConnectWallet] User rejected ROGUE token import");
      } else {
        console.error("[ConnectWallet] Failed to import ROGUE token:", error);
      }
    }
  },

  destroyed() {
    // Clean up on unmount
    if (this.connectedWallet) {
      this.connectedWallet.disconnect();
    }
  }
};
```

### Multi-Chain Support

```javascript
// File: assets/js/chain_config.js

import { defineChain } from "thirdweb/chains";
import { ethereum, arbitrum } from "thirdweb/chains";

// Rogue Chain is already defined in home_hooks.js and exposed as window.rogueChain
// We can import standard chains from thirdweb

export const SUPPORTED_CHAINS = {
  ethereum: ethereum,           // ETH mainnet - for ETH balance
  arbitrum: arbitrum,           // Arbitrum One - for ROGUE ERC-20
  rogueChain: window.rogueChain // Rogue Chain - for ROGUE native (already defined)
};

// Token addresses on different chains
export const TOKEN_ADDRESSES = {
  ROGUE_ARBITRUM: "0x...", // TODO: Add ROGUE ERC-20 contract address on Arbitrum One
  USDC_ETHEREUM: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
  USDT_ETHEREUM: "0xdAC17F958D2ee523a2206206994597C13D831ec7",
  // Add more as needed
};
```

---

## Wallet Setup

### Automatic Network and Token Configuration

When a user connects a hardware wallet (MetaMask or Coinbase Wallet), Blockster automatically:

1. **Adds Rogue Chain network** if not already present in the wallet
2. **Imports ROGUE token** on Arbitrum One for easy balance viewing

This ensures a seamless user experience without requiring manual network/token configuration.

#### Rogue Chain Network Parameters

```javascript
{
  chainId: "0x88CED",  // 560013 in hex
  chainName: "Rogue Chain Mainnet",
  nativeCurrency: {
    name: "ROGUE",
    symbol: "ROGUE",
    decimals: 18
  },
  rpcUrls: ["https://rpc.roguechain.io/rpc"],
  blockExplorerUrls: ["https://roguescan.io"]
}
```

#### ROGUE Token on Arbitrum One

```javascript
{
  type: "ERC20",
  address: "0x88b8d272b9f1bab7d7896f5f88f8825ce14b05bd",
  symbol: "ROGUE",
  decimals: 18
}
```

#### User Experience Flow

1. User clicks "Connect Wallet" → selects MetaMask/Coinbase
2. Wallet connection popup appears
3. User approves connection
4. **If Rogue Chain not in wallet**: Automatic popup to add network → User approves
5. **If ROGUE token not imported on Arbitrum**: Automatic popup to add token → User can approve or skip
6. Connection completes, balances are fetched

#### Supported Wallets for Auto-Setup

| Wallet | Network Auto-Add | Token Import |
|--------|------------------|--------------|
| MetaMask | ✅ Yes | ✅ Yes |
| Coinbase Wallet | ✅ Yes | ✅ Yes |
| WalletConnect | ❌ No (manual) | ❌ No (manual) |
| Phantom | ❌ No (manual) | ❌ No (manual) |

**Note**: WalletConnect and Phantom users need to manually add Rogue Chain and import ROGUE token. The app will still work, but balances won't display until networks are configured.

#### Manual Setup Instructions for WalletConnect Users

When a WalletConnect user successfully connects, show a dismissible banner with setup instructions:

```
┌─────────────────────────────────────────────────────────────┐
│  ℹ️  Setup Required                                  [Copy] │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  │
│                                                              │
│  Your wallet connected successfully! To see all balances,   │
│  add Rogue Chain in your wallet app:                        │
│                                                              │
│  Network Name: Rogue Chain Mainnet                          │
│  RPC URL: https://rpc.roguechain.io/rpc                    │
│  Chain ID: 560013                                           │
│  Currency Symbol: ROGUE                                     │
│  Block Explorer: https://roguescan.io                       │
│                                                              │
│  Then add ROGUE token on Arbitrum One:                      │
│  Token Address: 0x88b8d272b9f1bab7d7896f5f88f8825ce14b05bd │
│                                                              │
│  [Dismiss]                                                  │
└─────────────────────────────────────────────────────────────┘
```

**Implementation**:

```elixir
# In LiveView - handle wallet connection
def handle_event("wallet_connected", %{"provider" => provider} = params, socket) do
  # ... existing connection logic ...

  show_manual_setup = provider in ["walletconnect", "phantom"]

  {:noreply,
   socket
   |> assign(:wallet_connected, true)
   |> assign(:show_manual_setup_banner, show_manual_setup)}
end
```

**Template** (show conditionally):

```heex
<%= if @show_manual_setup_banner do %>
  <div class="bg-blue-50 border-l-4 border-blue-500 p-4 mb-4" id="manual-setup-banner">
    <div class="flex justify-between items-start">
      <div class="flex">
        <div class="flex-shrink-0">
          <svg class="h-5 w-5 text-blue-400" fill="currentColor" viewBox="0 0 20 20">
            <path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clip-rule="evenodd"/>
          </svg>
        </div>
        <div class="ml-3">
          <h3 class="text-sm font-medium text-blue-800">Manual Setup Required</h3>
          <div class="mt-2 text-sm text-blue-700">
            <p class="mb-2">Your wallet connected successfully! To see all balances, add Rogue Chain in your wallet app:</p>

            <div class="bg-white p-3 rounded border border-blue-200 font-mono text-xs space-y-1">
              <div><span class="text-gray-600">Network Name:</span> Rogue Chain Mainnet</div>
              <div><span class="text-gray-600">RPC URL:</span> https://rpc.roguechain.io/rpc</div>
              <div><span class="text-gray-600">Chain ID:</span> 560013</div>
              <div><span class="text-gray-600">Currency Symbol:</span> ROGUE</div>
              <div><span class="text-gray-600">Block Explorer:</span> https://roguescan.io</div>
            </div>

            <p class="mt-3 mb-1">Then add ROGUE token on Arbitrum One:</p>
            <div class="bg-white p-2 rounded border border-blue-200 font-mono text-xs">
              <span class="text-gray-600">Token Address:</span> 0x88b8d272b9f1bab7d7896f5f88f8825ce14b05bd
            </div>

            <button
              phx-click="copy_network_details"
              class="mt-3 text-blue-600 hover:text-blue-800 font-medium text-sm cursor-pointer">
              📋 Copy All Details
            </button>
          </div>
        </div>
      </div>
      <button
        phx-click="dismiss_setup_banner"
        class="ml-3 flex-shrink-0 cursor-pointer">
        <svg class="h-5 w-5 text-blue-400 hover:text-blue-600" fill="currentColor" viewBox="0 0 20 20">
          <path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd"/>
        </svg>
      </button>
    </div>
  </div>
<% end %>
```

**Event Handlers**:

```elixir
def handle_event("copy_network_details", _params, socket) do
  details = """
  Rogue Chain Mainnet Configuration:

  Network Name: Rogue Chain Mainnet
  RPC URL: https://rpc.roguechain.io/rpc
  Chain ID: 560013
  Currency Symbol: ROGUE
  Block Explorer: https://roguescan.io

  ROGUE Token on Arbitrum One:
  Token Address: 0x88b8d272b9f1bab7d7896f5f88f8825ce14b05bd
  Symbol: ROGUE
  Decimals: 18
  """

  {:noreply,
   socket
   |> push_event("copy_to_clipboard", %{text: details})
   |> put_flash(:info, "Network details copied to clipboard!")}
end

def handle_event("dismiss_setup_banner", _params, socket) do
  {:noreply, assign(socket, :show_manual_setup_banner, false)}
end
```

**JavaScript Hook** (for clipboard):

```javascript
// In app.js hooks
let ClipboardHook = {
  mounted() {
    this.handleEvent("copy_to_clipboard", ({text}) => {
      navigator.clipboard.writeText(text).then(() => {
        console.log("[Clipboard] Copied to clipboard");
      }).catch(err => {
        console.error("[Clipboard] Failed to copy:", err);
      });
    });
  }
}
```

#### Error Handling

- If user **rejects** network addition → Connection continues but Rogue Chain balances won't be available
- If user **rejects** token import → Connection continues but ROGUE balance on Arbitrum won't show in wallet UI (still tracked by Blockster)
- Both operations are **non-critical** and won't block wallet connection

---

## Multiplier System

> **V2 Update (Jan 2026)**: The multiplier system has been refactored. ROGUE is now a **separate multiplier component** that only counts ROGUE in the **Blockster smart wallet**. External wallet ROGUE does NOT count toward multipliers.
>
> See `docs/unified_multiplier_system_v2.md` for the complete unified multiplier system.

### External Wallet Multiplier (V2)

**Range**: 1.0x - 3.6x

The external wallet multiplier is now based on **ETH + other tokens only** (NO ROGUE).

| Factor | Multiplier Boost | Notes |
|--------|------------------|-------|
| **Base** | 1.0x | Always applied |
| **Hardware Wallet Connected** | +0.1x | Boost for connecting |
| **ETH Holdings (Mainnet + Arbitrum)** | +0.0x to +1.5x | Combined balance |
| **Other Tokens (USD Value)** | +0.0x to +1.0x | USDC, USDT, ARB - based on total USD value |

**Maximum**: 1.0 + 0.1 + 1.5 + 1.0 = **3.6x**

### ROGUE Multiplier (Separate - Smart Wallet Only)

> **Important**: ROGUE in your external/hardware wallet does NOT count toward the ROGUE multiplier. Only ROGUE held in your **Blockster smart wallet** counts.

The ROGUE multiplier is now a separate component of the Unified Multiplier System:

| ROGUE Balance (Smart Wallet) | Boost | Total ROGUE Multiplier |
|------------------------------|-------|------------------------|
| 0 - 99,999 | +0.0x | 1.0x |
| 100k - 199k | +0.4x | 1.4x |
| 200k - 299k | +0.8x | 1.8x |
| 300k - 399k | +1.2x | 2.2x |
| 400k - 499k | +1.6x | 2.6x |
| 500k - 599k | +2.0x | 3.0x |
| 600k - 699k | +2.4x | 3.4x |
| 700k - 799k | +2.8x | 3.8x |
| 800k - 899k | +3.2x | 4.2x |
| 900k - 999k | +3.6x | 4.6x |
| 1M+ | +4.0x | 5.0x (maximum) |

**Note**: This is handled by `BlocksterV2.RogueMultiplier` module, NOT the `WalletMultiplier` module.

### ETH Multiplier Tiers (Combined Mainnet + Arbitrum)

**Note**: ETH is a strong quality indicator. We combine ETH from both Ethereum mainnet and Arbitrum One with equal weight (no L2 discount).

| Combined ETH Balance | Boost | Notes |
|----------------------|-------|-------|
| 0 - 0.009 | +0.0x | No ETH |
| 0.01 - 0.09 | +0.1x | Small holder |
| 0.1 - 0.49 | +0.3x | Regular user |
| 0.5 - 0.99 | +0.5x | Committed user |
| 1.0 - 2.49 | +0.7x | Strong engagement |
| 2.5 - 4.99 | +0.9x | High-value user |
| 5.0 - 9.99 | +1.1x | Premium user |
| 10.0+ | +1.5x | Whale tier (maximum) |

**Why Equal Weight for L2?**
- Users who bridge to Arbitrum are often MORE sophisticated (understand L2s, gas optimization)
- Arbitrum ETH is just as liquid and valuable as mainnet ETH
- Penalizing L2 holdings discourages smart user behavior

### Other Tokens Multiplier (USD Value Based)

**All other tokens are treated equally** - only their **combined USD value** matters.

**Formula**: `multiplier = min(combined_usd_value / 10000, 1.0)`

| Combined USD Value | Multiplier | Calculation |
|--------------------|------------|-------------|
| $100 | +0.01x | $100 / $10,000 |
| $500 | +0.05x | $500 / $10,000 |
| $1,000 | +0.10x | $1,000 / $10,000 |
| $2,500 | +0.25x | $2,500 / $10,000 |
| $5,000 | +0.50x | $5,000 / $10,000 |
| $7,500 | +0.75x | $7,500 / $10,000 |
| $10,000 | +1.00x | $10,000 / $10,000 (capped) |
| $15,000 | +1.00x | Capped at 1.0x |
| $50,000+ | +1.00x | Capped at 1.0x |

**Default Tracked Tokens:**
- **USDC**: Ethereum + Arbitrum One
- **USDT**: Ethereum + Arbitrum One
- **ARB**: Arbitrum One

**Easy to add more tokens later:**
- DeFi: UNI, AAVE, LINK, CRV, MKR
- L2 Governance: OP
- Stablecoins: DAI, USDE
- Others: Any ERC-20 token we choose to track

**Note**: This is the **combined USD value** of ALL tracked tokens (excluding ETH and ROGUE which have their own tiers).

**V2 Implementation** (see `lib/blockster_v2/wallet_multiplier.ex`):

```elixir
defmodule BlocksterV2.WalletMultiplier do
  @moduledoc """
  Calculates external wallet multiplier based on token holdings.

  **IMPORTANT**: As of V2, this module handles ETH + other tokens ONLY.
  ROGUE is now handled separately by `BlocksterV2.RogueMultiplier` (smart wallet only).

  ## Multiplier Range: 1.0x - 3.6x

  ### Components:
  - **Base** (wallet connected): 1.0x
  - **Connection boost**: +0.1x (just for connecting)
  - **ETH** (Mainnet + Arbitrum combined): +0.1x to +1.5x
  - **Other tokens** (USD value): +0.0x to +1.0x
  """

  @eth_tiers [
    {10.0, 1.5}, {5.0, 1.1}, {2.5, 0.9}, {1.0, 0.7},
    {0.5, 0.5}, {0.1, 0.3}, {0.01, 0.1}, {0.0, 0.0}
  ]

  @base_multiplier 1.0
  @max_multiplier 3.6

  def calculate_hardware_wallet_multiplier(user_id) do
    case Wallets.get_connected_wallet(user_id) do
      nil ->
        # No wallet connected - return base multiplier of 1.0x
        %{total_multiplier: @base_multiplier, connection_boost: 0.0, ...}

      wallet ->
        # Base connection boost
        connection_boost = 0.1

        # Calculate ETH multiplier (combined mainnet + Arbitrum)
        # NOTE: ROGUE is NOT included - handled by RogueMultiplier
        eth_mainnet = get_balance(balances, "ETH", "ethereum")
        eth_arbitrum = get_balance(balances, "ETH", "arbitrum")
        combined_eth = eth_mainnet + eth_arbitrum
        eth_multiplier = calculate_eth_tier_multiplier(combined_eth)

        # Calculate other tokens multiplier (USD value based)
        other_tokens_usd = calculate_other_tokens_usd_value(balances)
        other_tokens_multiplier = min(other_tokens_usd / 10_000, 1.0)

        # Total: 1.0 + connection + ETH + other tokens
        # Range: 1.0 to 3.6 (NO ROGUE)
        total = @base_multiplier + connection_boost + eth_multiplier + other_tokens_multiplier

        %{
          total_multiplier: total,
          connection_boost: connection_boost,
          eth_multiplier: eth_multiplier,
          other_tokens_multiplier: other_tokens_multiplier,
          breakdown: %{...}
        }
    end
  end
end
```

**ROGUE Multiplier** (separate - see `lib/blockster_v2/rogue_multiplier.ex`):

```elixir
defmodule BlocksterV2.RogueMultiplier do
  @moduledoc """
  Calculates ROGUE multiplier based on Blockster smart wallet balance ONLY.

  **IMPORTANT**: Only ROGUE held in the user's **Blockster smart wallet** counts.
  ROGUE in external wallets (MetaMask, Ledger, etc.) does NOT count.

  ## Multiplier Range: 1.0x - 5.0x
  """

  @rogue_tiers [
    {1_000_000, 4.0}, {900_000, 3.6}, {800_000, 3.2}, {700_000, 2.8},
    {600_000, 2.4}, {500_000, 2.0}, {400_000, 1.6}, {300_000, 1.2},
    {200_000, 0.8}, {100_000, 0.4}, {0, 0.0}
  ]

  def calculate_rogue_multiplier(user_id) do
    # Get ROGUE balance from SMART WALLET only (Mnesia user_rogue_balances table)
    balance = get_smart_wallet_rogue_balance(user_id)

    # Cap at 1M ROGUE for multiplier calculation
    capped_balance = min(balance, 1_000_000)

    # Get boost from tier
    boost = get_rogue_boost(capped_balance)

    %{
      total_multiplier: 1.0 + boost,
      boost: boost,
      balance: balance,
      capped_balance: capped_balance
    }
  end
end
```

**Unified Multiplier** (combines all 4 - see `lib/blockster_v2/unified_multiplier.ex`):

```elixir
defmodule BlocksterV2.UnifiedMultiplier do
  @moduledoc """
  Overall = X Multiplier × Phone Multiplier × ROGUE Multiplier × Wallet Multiplier

  Range: 0.5x to 360.0x
  """

  def get_overall_multiplier(user_id) do
    # Reads from unified_multipliers Mnesia table
    # Returns product of all 4 components
  end
end
```

### Token Configuration

Create `lib/blockster_v2/hardware_wallet/token_config.ex`:

```elixir
defmodule BlocksterV2.HardwareWallet.TokenConfig do
  @moduledoc """
  Configuration for tokens tracked for hardware wallet balance and multiplier calculation.
  """

  @doc """
  Returns map of all tracked tokens with their chain addresses.

  Format:
  %{
    "SYMBOL" => %{
      name: "Token Name",
      chains: [%{chain_id: 1, address: "0x..." | nil}],
      decimals: 18,
      coingecko_id: "token-id"  # For USD price fetching
    }
  }
  """
  def tracked_tokens do
    %{
      # Native tokens - already handled separately, but listed for reference
      "ETH" => %{
        name: "Ethereum",
        chains: [
          %{chain_id: 1, address: nil},      # Ethereum mainnet (native)
          %{chain_id: 42161, address: nil}   # Arbitrum One (native)
        ],
        decimals: 18,
        coingecko_id: "ethereum"
      },

      # NOTE (V2): ROGUE is tracked for display/transfer purposes, but external wallet
      # ROGUE does NOT count toward multipliers. Only smart wallet ROGUE counts.
      # See RogueMultiplier module and unified_multiplier_system_v2.md
      "ROGUE" => %{
        name: "Rogue",
        chains: [
          %{chain_id: 560013, address: nil},                                    # Rogue Chain (native)
          %{chain_id: 42161, address: "0x88b8d272b9f1bab7d7896f5f88f8825ce14b05bd"}  # Arbitrum One (ERC-20)
        ],
        decimals: 18,
        coingecko_id: "rogue"  # TODO: Verify CoinGecko ID when listed
      },

      # Stablecoins - Default tracked tokens
      "USDC" => %{
        name: "USD Coin",
        chains: [
          %{chain_id: 1, address: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"},      # Ethereum
          %{chain_id: 42161, address: "0xaf88d065e77c8cC2239327C5EDb3A432268e5831"}   # Arbitrum
        ],
        decimals: 6,
        coingecko_id: "usd-coin"
      },

      "USDT" => %{
        name: "Tether USD",
        chains: [
          %{chain_id: 1, address: "0xdAC17F958D2ee523a2206206994597C13D831ec7"},      # Ethereum
          %{chain_id: 42161, address: "0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9"}   # Arbitrum
        ],
        decimals: 6,
        coingecko_id: "tether"
      },

      # Governance tokens - Default tracked tokens
      "ARB" => %{
        name: "Arbitrum",
        chains: [
          %{chain_id: 1, address: "0xB50721BCf8d664c30412Cfbc6cf7a15145935f0D"},      # Ethereum (ERC-20)
          %{chain_id: 42161, address: "0x912CE59144191C1204E64559FE8253a0e49E6548"}   # Arbitrum (ERC-20)
        ],
        decimals: 18,
        coingecko_id: "arbitrum"
      }

      # Add more tokens here as needed:
      # "UNI" => %{...},
      # "AAVE" => %{...},
      # "LINK" => %{...},
    }
  end

  @doc """
  Get all chains where a token should be tracked.
  Returns list of chain IDs.
  """
  def get_token_chains(token_symbol) do
    case Map.get(tracked_tokens(), token_symbol) do
      nil -> []
      token_config -> Enum.map(token_config.chains, & &1.chain_id)
    end
  end

  @doc """
  Get token contract address for a specific chain.
  Returns nil for native tokens.
  """
  def get_token_address(token_symbol, chain_id) do
    with %{chains: chains} <- Map.get(tracked_tokens(), token_symbol),
         chain_config <- Enum.find(chains, fn c -> c.chain_id == chain_id end) do
      chain_config.address
    else
      _ -> nil
    end
  end

  @doc """
  Get token decimals.
  """
  def get_token_decimals(token_symbol) do
    case Map.get(tracked_tokens(), token_symbol) do
      nil -> 18  # Default to 18 if not found
      token_config -> token_config.decimals
    end
  end

  @doc """
  Get CoinGecko ID for price fetching.
  """
  def get_coingecko_id(token_symbol) do
    case Map.get(tracked_tokens(), token_symbol) do
      nil -> nil
      token_config -> token_config.coingecko_id
    end
  end

  @doc """
  Get list of all tokens that contribute to multiplier (excludes ETH and ROGUE).
  """
  def get_multiplier_tokens do
    tracked_tokens()
    |> Map.keys()
    |> Enum.reject(&(&1 in ["ETH", "ROGUE"]))
  end
end
```

### Multiplier Storage in Mnesia (V2)

The unified multiplier system uses a **new table** (`unified_multipliers`) that stores all 4 components:

```elixir
# V2: Unified multipliers table (replaces legacy user_multipliers for new system)
:mnesia.create_table(:unified_multipliers, [
  attributes: [
    :user_id,                # PRIMARY KEY
    :x_score,                # Raw X score (0-100)
    :x_multiplier,           # Calculated (1.0-10.0)
    :phone_multiplier,       # From phone verification (0.5-2.0)
    :rogue_multiplier,       # From smart wallet ROGUE (1.0-5.0) - NOT external wallet
    :wallet_multiplier,      # From external wallet ETH + other tokens (1.0-3.6)
    :overall_multiplier,     # Product of all four (0.5-360.0)
    :last_updated,           # Unix timestamp
    :created_at              # Unix timestamp
  ],
  disc_copies: [node()],
  type: :set,
  index: [:overall_multiplier]
])
```

**Note**: The legacy `user_multipliers` table still exists and is updated in parallel for backward compatibility. New code should use `UnifiedMultiplier.get_overall_multiplier/1`.

See `docs/unified_multiplier_system_v2.md` for complete storage details.

---

## Balance Reading

### Native Token Balances (ETH, ROGUE)

```javascript
// File: assets/js/balance_fetcher.js

import { getRpcClient } from "thirdweb/rpc";
import { ethereum } from "thirdweb/chains";

/**
 * Get native token balance (ETH, ROGUE, etc.)
 * @param {string} walletAddress - 0x-prefixed address
 * @param {Object} chain - Chain object from thirdweb/chains
 * @returns {Promise<number>} - Balance as float
 */
async function getNativeBalance(walletAddress, chain) {
  const rpcRequest = getRpcClient({
    client: window.thirdwebClient,
    chain
  });

  const balanceWei = await rpcRequest({
    method: "eth_getBalance",
    params: [walletAddress, "latest"]
  });

  // Convert wei to ether
  const balanceEther = Number(balanceWei) / 1e18;
  return balanceEther;
}

// Usage examples
export async function fetchNativeBalances(walletAddress) {
  const [ethMainnetBalance, ethArbitrumBalance, rogueBalance] = await Promise.all([
    getNativeBalance(walletAddress, ethereum),
    getNativeBalance(walletAddress, arbitrum),
    getNativeBalance(walletAddress, window.rogueChain)
  ]);

  return {
    eth_mainnet: ethMainnetBalance,
    eth_arbitrum: ethArbitrumBalance,
    eth_combined: ethMainnetBalance + ethArbitrumBalance,  // Combined for multiplier
    rogue_native: rogueBalance
  };
}
```

### ERC-20 Token Balances

```javascript
// File: assets/js/balance_fetcher.js (continued)

import { getContract, readContract } from "thirdweb";
import { arbitrum } from "thirdweb/chains";

/**
 * Get ERC-20 token balance
 * @param {string} walletAddress - 0x-prefixed address
 * @param {string} tokenAddress - 0x-prefixed token contract address
 * @param {Object} chain - Chain object from thirdweb/chains
 * @returns {Promise<number>} - Balance as float
 */
async function getTokenBalance(walletAddress, tokenAddress, chain) {
  const contract = getContract({
    client: window.thirdwebClient,
    address: tokenAddress,
    chain
  });

  // Read balance
  const balanceWei = await readContract({
    contract,
    method: "function balanceOf(address) view returns (uint256)",
    params: [walletAddress]
  });

  // Read decimals
  const decimals = await readContract({
    contract,
    method: "function decimals() view returns (uint8)",
    params: []
  });

  // Convert to human-readable format
  const balance = Number(balanceWei) / Math.pow(10, Number(decimals));
  return balance;
}

// ROGUE on Arbitrum One (ERC-20)
const ROGUE_ARBITRUM = "0x..."; // TODO: Add actual ROGUE token contract on Arbitrum

export async function fetchROGUEArbitrumBalance(walletAddress) {
  try {
    const balance = await getTokenBalance(
      walletAddress,
      ROGUE_ARBITRUM,
      arbitrum
    );
    return balance;
  } catch (error) {
    console.error("[BalanceFetcher] Failed to fetch ROGUE on Arbitrum:", error);
    return 0;
  }
}
```

### Multi-Token Balance Reading

```javascript
// File: assets/js/balance_fetcher.js (continued)

/**
 * Complete balance fetcher for hardware wallet
 * Fetches balances across all supported chains and tokens
 */
export const BalanceFetcherHook = {
  mounted() {
    this.handleEvent("fetch_hardware_wallet_balances", async ({ address }) => {
      try {
        console.log("[BalanceFetcher] Fetching balances for:", address);

        // Fetch all balances in parallel
        const [
          ethMainnetBalance,
          ethArbitrumBalance,
          rogueNativeBalance,
          rogueArbitrumBalance,
          usdcEthBalance,
          usdcArbBalance,
          usdtEthBalance,
          usdtArbBalance,
          arbEthBalance,
          arbArbBalance
        ] = await Promise.all([
          // Native tokens
          this.getNativeBalance(address, window.SUPPORTED_CHAINS.ethereum),
          this.getNativeBalance(address, window.SUPPORTED_CHAINS.arbitrum),
          this.getNativeBalance(address, window.rogueChain),

          // ROGUE ERC-20 on Arbitrum
          this.getROGUEArbitrumBalance(address),

          // USDC (ERC-20)
          this.getTokenBalance(address, "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", 1, 6),     // USDC Ethereum
          this.getTokenBalance(address, "0xaf88d065e77c8cC2239327C5EDb3A432268e5831", 42161, 6), // USDC Arbitrum

          // USDT (ERC-20)
          this.getTokenBalance(address, "0xdAC17F958D2ee523a2206206994597C13D831ec7", 1, 6),     // USDT Ethereum
          this.getTokenBalance(address, "0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9", 42161, 6), // USDT Arbitrum

          // ARB (ERC-20 on both chains)
          this.getTokenBalance(address, "0xB50721BCf8d664c30412Cfbc6cf7a15145935f0D", 1, 18),     // ARB Ethereum
          this.getTokenBalance(address, "0x912CE59144191C1204E64559FE8253a0e49E6548", 42161, 18) // ARB Arbitrum
        ]);

        console.log("[BalanceFetcher] Balances:", {
          eth_mainnet: ethMainnetBalance,
          eth_arbitrum: ethArbitrumBalance,
          eth_combined: ethMainnetBalance + ethArbitrumBalance,
          rogue_native: rogueNativeBalance,
          rogue_arbitrum: rogueArbitrumBalance,
          usdc_eth: usdcEthBalance,
          usdc_arb: usdcArbBalance,
          usdt_eth: usdtEthBalance,
          usdt_arb: usdtArbBalance,
          arb_eth: arbEthBalance,
          arb_arb: arbArbBalance
        });

        // Send to Phoenix - will be stored in Mnesia hardware_wallet_balances table
        this.pushEvent("hardware_wallet_balances_fetched", {
          balances: [
            // ETH balances (native on both chains)
            {symbol: "ETH", chain_id: 1, balance: ethMainnetBalance, address: null, decimals: 18},
            {symbol: "ETH", chain_id: 42161, balance: ethArbitrumBalance, address: null, decimals: 18},

            // ROGUE balances
            {symbol: "ROGUE", chain_id: 560013, balance: rogueNativeBalance, address: null, decimals: 18},
            {symbol: "ROGUE", chain_id: 42161, balance: rogueArbitrumBalance, address: "0x88b8d272b9f1bab7d7896f5f88f8825ce14b05bd", decimals: 18},

            // USDC balances (ERC-20 on both chains)
            {symbol: "USDC", chain_id: 1, balance: usdcEthBalance, address: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", decimals: 6},
            {symbol: "USDC", chain_id: 42161, balance: usdcArbBalance, address: "0xaf88d065e77c8cC2239327C5EDb3A432268e5831", decimals: 6},

            // USDT balances (ERC-20 on both chains)
            {symbol: "USDT", chain_id: 1, balance: usdtEthBalance, address: "0xdAC17F958D2ee523a2206206994597C13D831ec7", decimals: 6},
            {symbol: "USDT", chain_id: 42161, balance: usdtArbBalance, address: "0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9", decimals: 6},

            // ARB balances (ERC-20 on both chains)
            {symbol: "ARB", chain_id: 1, balance: arbEthBalance, address: "0xB50721BCf8d664c30412Cfbc6cf7a15145935f0D", decimals: 18},
            {symbol: "ARB", chain_id: 42161, balance: arbArbBalance, address: "0x912CE59144191C1204E64559FE8253a0e49E6548", decimals: 18}
          ]
        });

      } catch (error) {
        console.error("[BalanceFetcher] Fetch failed:", error);
        this.pushEvent("balance_fetch_error", {
          error: error.message || "Failed to fetch balances"
        });
      }
    });
  },

  async getNativeBalance(address, chain) {
    const { getRpcClient } = await import("thirdweb/rpc");

    const rpcRequest = getRpcClient({
      client: window.thirdwebClient,
      chain
    });

    const balanceWei = await rpcRequest({
      method: "eth_getBalance",
      params: [address, "latest"]
    });

    return Number(balanceWei) / 1e18;
  },

  async getROGUEArbitrumBalance(address) {
    const ROGUE_ARBITRUM = "0x88b8d272b9f1bab7d7896f5f88f8825ce14b05bd";
    return this.getTokenBalance(address, ROGUE_ARBITRUM, 42161, 18);
  },

  /**
   * Generic ERC-20 token balance fetcher
   * @param {string} address - Wallet address
   * @param {string} tokenAddress - Token contract address
   * @param {number} chainId - Chain ID (1 = Ethereum, 42161 = Arbitrum)
   * @param {number} decimals - Token decimals (6 for USDC/USDT, 18 for most others)
   */
  async getTokenBalance(address, tokenAddress, chainId, decimals) {
    try {
      const { getContract, readContract } = await import("thirdweb");

      // Get chain object
      let chain;
      if (chainId === 1) {
        const { ethereum } = await import("thirdweb/chains");
        chain = ethereum;
      } else if (chainId === 42161) {
        const { arbitrum } = await import("thirdweb/chains");
        chain = arbitrum;
      } else {
        console.warn(`[BalanceFetcher] Unsupported chain ID: ${chainId}`);
        return 0;
      }

      const contract = getContract({
        client: window.thirdwebClient,
        address: tokenAddress,
        chain: chain
      });

      const balanceWei = await readContract({
        contract,
        method: "function balanceOf(address) view returns (uint256)",
        params: [address]
      });

      return Number(balanceWei) / Math.pow(10, decimals);
    } catch (error) {
      console.warn(`[BalanceFetcher] Token balance fetch failed for ${tokenAddress} on chain ${chainId}:`, error);
      return 0;
    }
  }
};
```

---

## Token Transfers

### Transfer Flow Architecture

```
┌─────────────────┐
│ Hardware Wallet │
│  (MetaMask)     │
└────────┬────────┘
         │
         │ 1. User initiates transfer
         │    (Send ROGUE to Blockster)
         │
         ▼
┌─────────────────────────┐
│ Thirdweb SDK            │
│ - Prepare transaction   │
│ - Request signature     │
└────────┬────────────────┘
         │
         │ 2. User confirms in wallet
         │
         ▼
┌─────────────────────────┐
│ Rogue Chain RPC         │
│ - Execute transfer      │
│ - From: Hardware wallet │
│ - To: Blockster smart   │
│      wallet address     │
└────────┬────────────────┘
         │
         │ 3. Monitor transaction
         │
         ▼
┌─────────────────────────┐
│ Phoenix LiveView        │
│ - Update UI             │
│ - Sync Mnesia balances  │
│ - Update BUX Booster    │
└─────────────────────────┘
```

### Send ROGUE from Hardware Wallet to Blockster

```javascript
// File: assets/js/wallet_transfer.js

/**
 * Transfer ROGUE from connected hardware wallet to Blockster smart wallet
 * This follows the same pattern as BuxBoosterOnchain transfers
 */
export const WalletTransferHook = {
  mounted() {
    this.connectedWallet = null; // Set during wallet connection

    this.handleEvent("transfer_to_blockster", async ({
      amount,
      blockster_wallet,
      connected_wallet
    }) => {
      try {
        console.log("[WalletTransfer] Transferring", amount, "ROGUE to", blockster_wallet);

        // Dynamic imports (same pattern as BuxBoosterOnchain)
        const { prepareTransaction, sendTransaction, waitForReceipt } = await import("thirdweb");

        // Get the active account from connected wallet
        if (!this.connectedWallet) {
          throw new Error("No wallet connected");
        }

        const account = this.connectedWallet.getAccount();

        // Prepare native ROGUE transfer
        const amountWei = BigInt(Math.floor(amount * 1e18));

        const transaction = prepareTransaction({
          to: blockster_wallet,
          value: amountWei,
          chain: window.rogueChain
        });

        // Send transaction (user confirms in wallet)
        const { transactionHash } = await sendTransaction({
          transaction,
          account
        });

        console.log("[WalletTransfer] Transaction sent:", transactionHash);

        // Notify Phoenix that tx was submitted
        this.pushEvent("transfer_submitted", {
          tx_hash: transactionHash,
          amount: amount,
          direction: "to_blockster"
        });

        // Wait for confirmation in background
        const receipt = await waitForReceipt({
          client: window.thirdwebClient,
          chain: window.rogueChain,
          transactionHash
        });

        console.log("[WalletTransfer] Transaction confirmed:", receipt);

        // Notify Phoenix of confirmation
        this.pushEvent("transfer_confirmed", {
          tx_hash: transactionHash,
          block_number: Number(receipt.blockNumber),
          gas_used: Number(receipt.gasUsed),
          amount: amount,
          direction: "to_blockster",
          status: receipt.status === "success" ? "confirmed" : "failed"
        });

      } catch (error) {
        console.error("[WalletTransfer] Transfer failed:", error);

        // Parse user-friendly error
        let errorMessage = error.message;
        if (error.message.includes("User rejected")) {
          errorMessage = "Transfer cancelled by user";
        } else if (error.message.includes("insufficient funds")) {
          errorMessage = "Insufficient ROGUE balance for transfer";
        }

        this.pushEvent("transfer_error", {
          error: errorMessage
        });
      }
    });
  }
};
```

### Send ROGUE from Blockster to Hardware Wallet

```elixir
# In LiveView
def handle_event("transfer_from_blockster", %{"amount" => amount, "to_address" => to_address}, socket) do
  user = socket.assigns.current_user
  wallet_address = user.smart_wallet_address

  # Validate user has sufficient balance
  balances = EngagementTracker.get_user_token_balances(user.id)
  rogue_balance = Map.get(balances, "ROGUE", 0.0)

  if amount <= rogue_balance do
    # Use BUX Minter to send ROGUE (account abstracted)
    case BuxMinter.transfer_rogue(wallet_address, to_address, amount) do
      {:ok, tx_hash} ->
        # Update Mnesia balance
        EngagementTracker.update_user_rogue_balance(user.id, rogue_balance - amount, "rogue_chain")

        {:noreply,
         socket
         |> put_flash(:info, "Transfer initiated: #{tx_hash}")
         |> push_event("transfer_complete", %{tx_hash: tx_hash})}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Transfer failed: #{reason}")}
    end
  else
    {:noreply, put_flash(socket, :error, "Insufficient ROGUE balance")}
  end
end
```

### BUX Minter Transfer Endpoint

```javascript
// bux-minter/index.js

app.post('/transfer-rogue', async (req, res) => {
  try {
    const { from, to, amount } = req.body;

    // Validate inputs
    if (!ethers.isAddress(from) || !ethers.isAddress(to)) {
      return res.status(400).json({ error: 'Invalid address' });
    }

    const amountWei = ethers.parseEther(amount.toString());

    // Execute transfer via smart wallet
    const tx = await smartWallet.sendTransaction({
      to: to,
      value: amountWei
    });

    await tx.wait();

    res.json({
      success: true,
      tx_hash: tx.hash,
      amount: amount,
      from: from,
      to: to
    });
  } catch (error) {
    console.error('Transfer failed:', error);
    res.status(500).json({ error: error.message });
  }
});
```

---

## Database Schema

### PostgreSQL Tables (Persistent Data)

#### New Table: `connected_wallets`

Stores wallet connection metadata in PostgreSQL for persistence and auditability.

```sql
CREATE TABLE connected_wallets (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  wallet_address VARCHAR(42) NOT NULL,  -- 0x-prefixed, lowercase
  wallet_type VARCHAR(50) NOT NULL,     -- 'metamask', 'coinbase', 'walletconnect', 'phantom'
  chain_id INTEGER NOT NULL,            -- Chain ID where wallet was connected
  is_active BOOLEAN DEFAULT true,
  multiplier_boost DECIMAL(10,2) DEFAULT 0.0,  -- Cached multiplier (recalculated periodically)
  connected_at TIMESTAMP NOT NULL DEFAULT NOW(),
  last_used_at TIMESTAMP NOT NULL DEFAULT NOW(),
  inserted_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW(),

  CONSTRAINT unique_user_wallet UNIQUE(user_id),
  CONSTRAINT unique_wallet_address UNIQUE(wallet_address)
);

CREATE INDEX idx_connected_wallets_user_id ON connected_wallets(user_id);
CREATE INDEX idx_connected_wallets_address ON connected_wallets(wallet_address);
```

#### Schema Module

```elixir
defmodule BlocksterV2.Accounts.ConnectedWallet do
  use Ecto.Schema
  import Ecto.Changeset

  schema "connected_wallets" do
    field :wallet_address, :string
    field :wallet_type, :string
    field :chain_id, :integer
    field :is_active, :boolean, default: true
    field :multiplier_boost, :decimal
    field :connected_at, :utc_datetime
    field :last_used_at, :utc_datetime

    belongs_to :user, BlocksterV2.Accounts.User

    timestamps()
  end

  def changeset(wallet, attrs) do
    wallet
    |> cast(attrs, [:user_id, :wallet_address, :wallet_type, :chain_id, :is_active, :multiplier_boost, :last_used_at])
    |> validate_required([:user_id, :wallet_address, :wallet_type, :chain_id])
    |> validate_format(:wallet_address, ~r/^0x[a-fA-F0-9]{40}$/)
    |> validate_inclusion(:wallet_type, ["metamask", "coinbase", "walletconnect", "phantom"])
    |> unique_constraint(:user_id)
    |> unique_constraint(:wallet_address)
    |> update_change(:wallet_address, &String.downcase/1)
  end
end
```

### Mnesia Tables (Fast Balance Cache)

#### New Table: `hardware_wallet_balances`

Caches token balances for connected hardware wallets. Refreshed periodically or on-demand.

```elixir
# Tuple structure:
{
  :hardware_wallet_balances,  # 0 - table name
  {user_id, token_symbol, chain_id},  # 1 - composite key {integer, string, integer}
  balance,                    # 2 - float
  token_address,              # 3 - string (0x-prefixed for ERC-20, nil for native)
  decimals,                   # 4 - integer (18 for ETH/ROGUE, varies for ERC-20)
  last_updated                # 5 - unix timestamp (seconds)
}
```

**Primary Key**: `{user_id, token_symbol, chain_id}` (composite key)

**Secondary Index**: None needed (composite key is efficient for lookups)

**Examples**:
```elixir
# ETH on Ethereum mainnet
{:hardware_wallet_balances, {65, "ETH", 1}, 0.5, nil, 18, 1704067200}

# ETH on Arbitrum One
{:hardware_wallet_balances, {65, "ETH", 42161}, 0.1, nil, 18, 1704067200}

# ROGUE on Rogue Chain (native)
{:hardware_wallet_balances, {65, "ROGUE", 560013}, 1000000.0, nil, 18, 1704067200}

# ROGUE on Arbitrum One (ERC-20)
{:hardware_wallet_balances, {65, "ROGUE", 42161}, 50000.0, "0x...", 18, 1704067200}

# USDC on Ethereum
{:hardware_wallet_balances, {65, "USDC", 1}, 1000.0, "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", 6, 1704067200}

# ARB on Arbitrum One
{:hardware_wallet_balances, {65, "ARB", 42161}, 250.0, "0x912ce59144191c1204e64559fe8253a0e49e6548", 18, 1704067200}
```

### New Table: `wallet_transfers`

```elixir
# Tuple structure:
{
  :wallet_transfers,    # 0 - table name
  transfer_id,          # 1 - string (UUID, primary key)
  user_id,              # 2 - integer (secondary index)
  from_address,         # 3 - string (0x-prefixed)
  to_address,           # 4 - string (0x-prefixed)
  amount,               # 5 - float
  token,                # 6 - string ("ROGUE", "ETH", etc.)
  chain_id,             # 7 - integer
  direction,            # 8 - atom (:to_blockster, :from_blockster)
  tx_hash,              # 9 - string (0x-prefixed, secondary index)
  block_number,         # 10 - integer or nil
  status,               # 11 - atom (:pending, :confirmed, :failed)
  gas_used,             # 12 - integer or nil
  gas_price,            # 13 - integer or nil (in wei)
  inserted_at,          # 14 - unix timestamp (seconds)
  confirmed_at          # 15 - unix timestamp (seconds) or nil
}
```

**Primary Key**: `transfer_id` (UUID string)

**Secondary Indexes**:
- `user_id` (query transfers by user)
- `tx_hash` (lookup by transaction hash)

### Mnesia Table Initialization

Add to `lib/blockster_v2/mnesia_initializer.ex`:

```elixir
defmodule BlocksterV2.MnesiaInitializer do
  # ... existing code ...

  defp create_tables do
    # ... existing tables ...

    # Connected Wallets table
    :mnesia.create_table(:connected_wallets, [
      attributes: [
        :user_id,
        :wallet_address,
        :wallet_type,
        :chain_id,
        :last_balance_check,
        :eth_mainnet_balance,
        :eth_arbitrum_balance,
        :rogue_native_balance,
        :rogue_arbitrum_balance,
        :multiplier_boost,
        :is_active,
        :connected_at,
        :last_used_at
      ],
      disc_copies: [node()],
      type: :set,
      index: [:wallet_address]  # Secondary index for reverse lookup
    ])

    # Wallet Transfers table
    :mnesia.create_table(:wallet_transfers, [
      attributes: [
        :transfer_id,
        :user_id,
        :from_address,
        :to_address,
        :amount,
        :token,
        :chain_id,
        :direction,
        :tx_hash,
        :block_number,
        :status,
        :gas_used,
        :gas_price,
        :inserted_at,
        :confirmed_at
      ],
      disc_copies: [node()],
      type: :set,
      index: [:user_id, :tx_hash]  # Secondary indexes
    ])
  end
end
```

### Helper Module: `BlocksterV2.ConnectedWallets`

```elixir
defmodule BlocksterV2.ConnectedWallets do
  @moduledoc """
  Manages hardware wallet connections in Mnesia.
  """

  require Logger

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Connect a hardware wallet for a user.
  """
  def connect_wallet(user_id, wallet_address, wallet_type, chain_id) do
    now = :os.system_time(:second)

    record = {
      :connected_wallets,
      user_id,
      String.downcase(wallet_address),
      wallet_type,
      chain_id,
      nil,      # last_balance_check
      0.0,      # eth_balance
      0.0,      # rogue_native_balance
      0.0,      # rogue_arbitrum_balance
      0.0,      # multiplier_boost
      true,     # is_active
      now,      # connected_at
      now       # last_used_at
    }

    case :mnesia.dirty_write(record) do
      :ok ->
        Logger.info("[ConnectedWallets] User #{user_id} connected wallet #{wallet_address}")
        {:ok, wallet_address}

      error ->
        Logger.error("[ConnectedWallets] Failed to connect wallet: #{inspect(error)}")
        {:error, "Failed to connect wallet"}
    end
  end

  @doc """
  Disconnect wallet for a user.
  """
  def disconnect_wallet(user_id) do
    case :mnesia.dirty_delete({:connected_wallets, user_id}) do
      :ok ->
        Logger.info("[ConnectedWallets] User #{user_id} disconnected wallet")
        :ok

      error ->
        Logger.error("[ConnectedWallets] Failed to disconnect wallet: #{inspect(error)}")
        {:error, "Failed to disconnect wallet"}
    end
  end

  @doc """
  Get connected wallet for a user.
  Returns {:ok, wallet_map} or {:error, :not_found}
  """
  def get_wallet(user_id) do
    case :mnesia.dirty_read({:connected_wallets, user_id}) do
      [record] ->
        {:ok, record_to_map(record)}

      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  Update wallet balances and recalculate multiplier.
  """
  def update_balances(user_id, eth_balance, rogue_native, rogue_arbitrum) do
    case :mnesia.dirty_read({:connected_wallets, user_id}) do
      [record] ->
        now = :os.system_time(:second)
        multiplier = calculate_multiplier(eth_balance, rogue_native, rogue_arbitrum)

        updated_record = record
        |> put_elem(5, now)                # last_balance_check
        |> put_elem(6, eth_balance)        # eth_balance
        |> put_elem(7, rogue_native)       # rogue_native_balance
        |> put_elem(8, rogue_arbitrum)     # rogue_arbitrum_balance
        |> put_elem(9, multiplier)         # multiplier_boost
        |> put_elem(12, now)               # last_used_at

        :mnesia.dirty_write(updated_record)

        # Update user_multipliers table
        BlocksterV2.EngagementTracker.update_hardware_wallet_multiplier(user_id, multiplier)

        Logger.info("[ConnectedWallets] Updated balances for user #{user_id}: multiplier=#{multiplier}")
        {:ok, multiplier}

      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  Record a transfer.
  """
  def record_transfer(user_id, from_address, to_address, amount, token, chain_id, direction, tx_hash) do
    transfer_id = UUID.uuid4()
    now = :os.system_time(:second)

    record = {
      :wallet_transfers,
      transfer_id,
      user_id,
      String.downcase(from_address),
      String.downcase(to_address),
      amount,
      token,
      chain_id,
      direction,
      String.downcase(tx_hash),
      nil,        # block_number
      :pending,   # status
      nil,        # gas_used
      nil,        # gas_price
      now,        # inserted_at
      nil         # confirmed_at
    }

    case :mnesia.dirty_write(record) do
      :ok ->
        Logger.info("[ConnectedWallets] Recorded transfer #{transfer_id} for user #{user_id}")
        {:ok, transfer_id}

      error ->
        Logger.error("[ConnectedWallets] Failed to record transfer: #{inspect(error)}")
        {:error, "Failed to record transfer"}
    end
  end

  @doc """
  Update transfer status when confirmed.
  """
  def confirm_transfer(tx_hash, block_number, gas_used, gas_price) do
    case :mnesia.dirty_index_read(:wallet_transfers, String.downcase(tx_hash), :tx_hash) do
      [record] ->
        now = :os.system_time(:second)

        updated_record = record
        |> put_elem(10, block_number)   # block_number
        |> put_elem(11, :confirmed)     # status
        |> put_elem(12, gas_used)       # gas_used
        |> put_elem(13, gas_price)      # gas_price
        |> put_elem(15, now)            # confirmed_at

        :mnesia.dirty_write(updated_record)
        Logger.info("[ConnectedWallets] Confirmed transfer #{tx_hash}")
        :ok

      [] ->
        Logger.warn("[ConnectedWallets] Transfer not found: #{tx_hash}")
        {:error, :not_found}
    end
  end

  @doc """
  Get recent transfers for a user (limit 20).
  """
  def get_recent_transfers(user_id, limit \\ 20) do
    :mnesia.dirty_index_read(:wallet_transfers, user_id, :user_id)
    |> Enum.sort_by(fn record -> elem(record, 14) end, :desc)  # Sort by inserted_at
    |> Enum.take(limit)
    |> Enum.map(&transfer_record_to_map/1)
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp calculate_multiplier(eth_balance, rogue_native, rogue_arbitrum) do
    base = 0.1  # Base connection boost

    # ROGUE multiplier - combine balances with Arbitrum counting at 75%
    weighted_rogue_total = rogue_native + (rogue_arbitrum * 0.5)
    rogue_multi = calculate_rogue_tier_multiplier(weighted_rogue_total)

    # ETH multiplier
    eth_multi = calculate_eth_multiplier(eth_balance)

    total = base + rogue_multi + eth_multi
    min(total, 10.0)  # Cap at 10x
  end

  defp calculate_rogue_tier_multiplier(balance) do
    cond do
      balance >= 1_000_000 -> 4.0
      balance >= 900_000 -> 3.6
      balance >= 800_000 -> 3.2
      balance >= 700_000 -> 2.8
      balance >= 600_000 -> 2.4
      balance >= 500_000 -> 2.0
      balance >= 400_000 -> 1.6
      balance >= 300_000 -> 1.2
      balance >= 200_000 -> 0.8
      balance >= 100_000 -> 0.4
      true -> 0.0
    end
  end

  defp calculate_eth_multiplier(balance) do
    cond do
      balance >= 10.0 -> 0.3
      balance >= 5.0 -> 0.2
      balance >= 1.0 -> 0.1
      balance >= 0.1 -> 0.05
      true -> 0.0
    end
  end

  defp record_to_map(record) do
    %{
      user_id: elem(record, 1),
      wallet_address: elem(record, 2),
      wallet_type: elem(record, 3),
      chain_id: elem(record, 4),
      last_balance_check: elem(record, 5),
      eth_balance: elem(record, 6),
      rogue_native_balance: elem(record, 7),
      rogue_arbitrum_balance: elem(record, 8),
      multiplier_boost: elem(record, 9),
      is_active: elem(record, 10),
      connected_at: elem(record, 11),
      last_used_at: elem(record, 12)
    }
  end

  defp transfer_record_to_map(record) do
    %{
      transfer_id: elem(record, 1),
      user_id: elem(record, 2),
      from_address: elem(record, 3),
      to_address: elem(record, 4),
      amount: elem(record, 5),
      token: elem(record, 6),
      chain_id: elem(record, 7),
      direction: elem(record, 8),
      tx_hash: elem(record, 9),
      block_number: elem(record, 10),
      status: elem(record, 11),
      gas_used: elem(record, 12),
      gas_price: elem(record, 13),
      inserted_at: elem(record, 14),
      confirmed_at: elem(record, 15)
    }
  end
end
```

### Update `user_multipliers` Table

Add `hardware_wallet_multiplier` field to existing Mnesia table:

```elixir
# In MnesiaInitializer - update user_multipliers table
:mnesia.create_table(:user_multipliers, [
  attributes: [
    :user_id,
    :x_multiplier,
    :geo_multiplier,
    :hardware_wallet_multiplier,  # NEW FIELD - add to END
    :total_multiplier,
    :updated_at
  ],
  disc_copies: [node()],
  type: :set,
  index: []
])
```

### EngagementTracker Integration

```elixir
# In BlocksterV2.EngagementTracker

def update_hardware_wallet_multiplier(user_id, hw_multiplier) do
  case :mnesia.dirty_read({:user_multipliers, user_id}) do
    [record] ->
      x_multi = elem(record, 1)
      geo_multi = elem(record, 2)

      total = calculate_total_multiplier(x_multi, geo_multi, hw_multiplier)

      updated_record = record
      |> put_elem(3, hw_multiplier)  # hardware_wallet_multiplier
      |> put_elem(4, total)          # total_multiplier
      |> put_elem(5, :os.system_time(:second))  # updated_at

      :mnesia.dirty_write(updated_record)
      {:ok, total}

    [] ->
      # Create new record
      now = :os.system_time(:second)
      total = 1.0 + hw_multiplier

      record = {
        :user_multipliers,
        user_id,
        1.0,           # x_multiplier
        1.0,           # geo_multiplier
        hw_multiplier, # hardware_wallet_multiplier
        total,         # total_multiplier
        now            # updated_at
      }

      :mnesia.dirty_write(record)
      {:ok, total}
  end
end

defp calculate_total_multiplier(x_multi, geo_multi, hw_multi) do
  # Multiplicative stacking
  x_multi * geo_multi * (1.0 + hw_multi)
end
```

---

## UI Components

### Settings Tab - Connect Wallet Section

```heex
<!-- lib/blockster_v2_web/live/member_live/settings.html.heex -->

<div class="bg-white rounded-lg shadow p-6">
  <h3 class="text-lg font-haas_medium_65 mb-4">Hardware Wallet</h3>

  <%= if @connected_wallet do %>
    <!-- Wallet Connected -->
    <div class="space-y-4">
      <div class="flex items-center justify-between p-4 bg-green-50 rounded-lg">
        <div>
          <p class="text-sm text-gray-600">Connected Wallet</p>
          <p class="font-mono text-sm">
            <%= String.slice(@connected_wallet.wallet_address, 0..5) %>...
            <%= String.slice(@connected_wallet.wallet_address, -4..-1) %>
          </p>
          <p class="text-xs text-gray-500 mt-1">
            <%= @connected_wallet.wallet_type |> String.capitalize() %>
          </p>
        </div>
        <button
          phx-click="disconnect_wallet"
          class="px-4 py-2 text-sm text-red-600 hover:bg-red-50 rounded-lg cursor-pointer"
        >
          Disconnect
        </button>
      </div>

      <!-- Multiplier Boost -->
      <div class="p-4 bg-blue-50 rounded-lg">
        <p class="text-sm font-haas_medium_65 text-blue-900">
          Wallet Multiplier Boost: +<%= :erlang.float_to_binary(@connected_wallet.multiplier_boost, decimals: 2) %>x
        </p>
        <p class="text-xs text-blue-700 mt-1">
          Your total BUX earnings multiplier is now <%= :erlang.float_to_binary(@total_multiplier, decimals: 2) %>x
        </p>
      </div>

      <!-- Balances -->
      <div class="space-y-2">
        <h4 class="font-haas_medium_65 text-sm">Wallet Balances</h4>

        <%= if @wallet_balances do %>
          <div class="space-y-1 text-sm">
            <%= if @wallet_balances.rogue_native > 0 do %>
              <div class="flex justify-between">
                <span class="text-gray-600">ROGUE (Rogue Chain):</span>
                <span class="font-mono"><%= format_number(@wallet_balances.rogue_native) %></span>
              </div>
            <% end %>

            <%= if @wallet_balances.rogue_arbitrum > 0 do %>
              <div class="flex justify-between">
                <span class="text-gray-600">ROGUE (Arbitrum):</span>
                <span class="font-mono"><%= format_number(@wallet_balances.rogue_arbitrum) %></span>
              </div>
            <% end %>

            <%= if @wallet_balances.eth > 0 do %>
              <div class="flex justify-between">
                <span class="text-gray-600">ETH:</span>
                <span class="font-mono"><%= format_number(@wallet_balances.eth) %></span>
              </div>
            <% end %>
          </div>
        <% else %>
          <button
            phx-click="fetch_wallet_balances"
            class="text-sm text-blue-600 hover:underline cursor-pointer"
          >
            Load balances
          </button>
        <% end %>
      </div>

      <!-- Transfer Section -->
      <div class="border-t pt-4">
        <h4 class="font-haas_medium_65 text-sm mb-3">Transfer ROGUE</h4>

        <div class="space-y-3">
          <!-- Send to Blockster -->
          <div>
            <label class="text-xs text-gray-600">Amount to send to Blockster wallet</label>
            <div class="flex gap-2 mt-1">
              <input
                type="number"
                phx-hook="NumberInput"
                id="transfer-to-blockster-amount"
                class="flex-1 px-3 py-2 border rounded-lg text-sm"
                placeholder="0.00"
                min="0"
                step="0.01"
              />
              <button
                phx-click="transfer_to_blockster"
                phx-value-amount={js_value("transfer-to-blockster-amount")}
                class="px-4 py-2 bg-blue-600 text-white rounded-lg text-sm hover:bg-blue-700 cursor-pointer"
              >
                Send →
              </button>
            </div>
            <p class="text-xs text-gray-500 mt-1">
              Available: <%= format_number(@wallet_balances.rogue_native || 0) %> ROGUE
            </p>
          </div>

          <!-- Send from Blockster -->
          <div>
            <label class="text-xs text-gray-600">Amount to send from Blockster wallet</label>
            <div class="flex gap-2 mt-1">
              <input
                type="number"
                phx-hook="NumberInput"
                id="transfer-from-blockster-amount"
                class="flex-1 px-3 py-2 border rounded-lg text-sm"
                placeholder="0.00"
                min="0"
                step="0.01"
              />
              <button
                phx-click="transfer_from_blockster"
                phx-value-amount={js_value("transfer-from-blockster-amount")}
                class="px-4 py-2 bg-gray-600 text-white rounded-lg text-sm hover:bg-gray-700 cursor-pointer"
              >
                ← Send
              </button>
            </div>
            <p class="text-xs text-gray-500 mt-1">
              Available: <%= format_number(@blockster_rogue_balance || 0) %> ROGUE
            </p>
          </div>
        </div>
      </div>

      <!-- Transfer History -->
      <%= if length(@recent_transfers) > 0 do %>
        <div class="border-t pt-4">
          <h4 class="font-haas_medium_65 text-sm mb-2">Recent Transfers</h4>
          <div class="space-y-2">
            <%= for transfer <- @recent_transfers do %>
              <div class="flex items-center justify-between text-xs p-2 bg-gray-50 rounded">
                <div>
                  <span class={[
                    "font-haas_medium_65",
                    transfer.direction == "to_blockster" && "text-green-600",
                    transfer.direction == "from_blockster" && "text-blue-600"
                  ]}>
                    <%= if transfer.direction == "to_blockster", do: "→ To Blockster", else: "← From Blockster" %>
                  </span>
                  <span class="ml-2 font-mono"><%= format_number(transfer.amount) %> ROGUE</span>
                </div>
                <a
                  href={"https://roguescan.io/tx/#{transfer.tx_hash}"}
                  target="_blank"
                  class="text-blue-600 hover:underline cursor-pointer"
                >
                  View ↗
                </a>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
  <% else %>
    <!-- Wallet Not Connected -->
    <div class="space-y-4">
      <p class="text-sm text-gray-600">
        Connect your hardware wallet to increase your BUX earnings multiplier and transfer ROGUE tokens.
      </p>

      <div class="p-4 bg-blue-50 rounded-lg">
        <h4 class="font-haas_medium_65 text-sm text-blue-900 mb-2">Benefits</h4>
        <ul class="text-xs text-blue-800 space-y-1">
          <li>✓ +0.1x base multiplier for connecting</li>
          <li>✓ Up to +2.0x for holding 1M+ ROGUE</li>
          <li>✓ Up to +0.3x for ETH holdings</li>
          <li>✓ Transfer ROGUE to play BUX Booster</li>
          <li>✓ Use wallet for direct transactions</li>
        </ul>
      </div>

      <button
        phx-click="show_connect_wallet_modal"
        class="w-full px-4 py-3 bg-blue-600 text-white rounded-lg font-haas_medium_65 hover:bg-blue-700 cursor-pointer"
      >
        Connect Hardware Wallet
      </button>
    </div>
  <% end %>
</div>
```

### Connect Wallet Modal

```heex
<!-- lib/blockster_v2_web/live/member_live/connect_wallet_modal.html.heex -->

<div
  id="connect-wallet-modal"
  phx-hook="ConnectWalletModal"
  class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50"
>
  <div class="bg-white rounded-lg p-6 max-w-md w-full mx-4">
    <div class="flex justify-between items-center mb-4">
      <h3 class="text-lg font-haas_medium_65">Connect Wallet</h3>
      <button
        phx-click="close_modal"
        class="text-gray-400 hover:text-gray-600 cursor-pointer"
      >
        ✕
      </button>
    </div>

    <p class="text-sm text-gray-600 mb-4">
      Choose your wallet provider to connect
    </p>

    <div class="space-y-2">
      <!-- MetaMask -->
      <button
        phx-click="connect_wallet"
        phx-value-provider="metamask"
        class="w-full flex items-center gap-3 p-4 border rounded-lg hover:bg-gray-50 cursor-pointer"
      >
        <img src="/images/wallets/metamask.svg" alt="MetaMask" class="w-8 h-8" />
        <span class="font-haas_medium_65">MetaMask</span>
      </button>

      <!-- Coinbase Wallet -->
      <button
        phx-click="connect_wallet"
        phx-value-provider="coinbase"
        class="w-full flex items-center gap-3 p-4 border rounded-lg hover:bg-gray-50 cursor-pointer"
      >
        <img src="/images/wallets/coinbase.svg" alt="Coinbase" class="w-8 h-8" />
        <span class="font-haas_medium_65">Coinbase Wallet</span>
      </button>

      <!-- WalletConnect -->
      <button
        phx-click="connect_wallet"
        phx-value-provider="walletconnect"
        class="w-full flex items-center gap-3 p-4 border rounded-lg hover:bg-gray-50 cursor-pointer"
      >
        <img src="/images/wallets/walletconnect.svg" alt="WalletConnect" class="w-8 h-8" />
        <span class="font-haas_medium_65">WalletConnect</span>
      </button>

      <!-- Phantom (for Solana users) -->
      <button
        phx-click="connect_wallet"
        phx-value-provider="phantom"
        class="w-full flex items-center gap-3 p-4 border rounded-lg hover:bg-gray-50 cursor-pointer"
      >
        <img src="/images/wallets/phantom.svg" alt="Phantom" class="w-8 h-8" />
        <span class="font-haas_medium_65">Phantom</span>
      </button>
    </div>

    <p class="text-xs text-gray-500 mt-4">
      By connecting, you agree to share your wallet address and allow balance reading across supported chains.
    </p>
  </div>
</div>
```

### JavaScript Hook

```javascript
// assets/js/connect_wallet_modal.js

import {
  createThirdwebClient,
  metamaskWallet,
  coinbaseWallet,
  walletConnect,
  phantomWallet
} from "thirdweb/wallets";
import { defineChain } from "thirdweb/chains";

const thirdwebClient = createThirdwebClient({
  clientId: window.THIRDWEB_CLIENT_ID
});

const rogueChain = defineChain({
  id: 560013,
  name: "Rogue Chain",
  rpc: "https://rpc.roguechain.io/rpc",
  nativeCurrency: {
    name: "ROGUE",
    symbol: "ROGUE",
    decimals: 18,
  }
});

const WALLET_PROVIDERS = {
  metamask: metamaskWallet(),
  coinbase: coinbaseWallet(),
  walletconnect: walletConnect(),
  phantom: phantomWallet()
};

export const ConnectWalletModal = {
  mounted() {
    this.handleEvent("connect_wallet", async ({ provider }) => {
      try {
        const wallet = WALLET_PROVIDERS[provider];

        if (!wallet) {
          throw new Error(`Unknown wallet provider: ${provider}`);
        }

        // Connect wallet
        const account = await wallet.connect({ client: thirdwebClient });

        // Get address
        const address = account.address;

        // Switch to Rogue Chain
        await wallet.switchChain(rogueChain);

        // Send to Phoenix
        this.pushEvent("wallet_connected", {
          address: address,
          provider: provider,
          chain_id: rogueChain.id
        });

      } catch (error) {
        console.error("Wallet connection failed:", error);

        this.pushEvent("wallet_connection_error", {
          error: error.message,
          provider: provider
        });
      }
    });

    // Fetch balances
    this.handleEvent("fetch_balances", async ({ address }) => {
      try {
        const balances = await this.fetchAllBalances(address);

        this.pushEvent("balances_fetched", {
          address: address,
          balances: balances
        });
      } catch (error) {
        console.error("Balance fetch failed:", error);
        this.pushEvent("balance_fetch_error", { error: error.message });
      }
    });

    // Transfer to Blockster
    this.handleEvent("execute_transfer_to_blockster", async ({
      amount,
      blockster_wallet
    }) => {
      try {
        const account = await wallet.getAccount();

        const tx = await account.sendTransaction({
          to: blockster_wallet,
          value: ethers.parseEther(amount.toString()),
          chain: rogueChain
        });

        const receipt = await tx.wait();

        this.pushEvent("transfer_confirmed", {
          tx_hash: receipt.transactionHash,
          amount: amount,
          direction: "to_blockster"
        });
      } catch (error) {
        console.error("Transfer failed:", error);
        this.pushEvent("transfer_error", { error: error.message });
      }
    });
  },

  async fetchAllBalances(address) {
    // Implementation from Balance Reading section
    // Returns { eth, rogue_native, rogue_arbitrum, tokens }
  }
};
```

---

## Security Considerations

### 1. Address Ownership Verification

When a user connects a wallet, verify they actually own it:

```elixir
defmodule BlocksterV2.WalletVerification do
  @verification_message "Sign this message to verify you own this wallet address.\n\nBlockster Account: {email}\nTimestamp: {timestamp}\nNonce: {nonce}"

  def generate_verification_challenge(user) do
    nonce = :crypto.strong_rand_bytes(32) |> Base.encode16()
    timestamp = DateTime.utc_now() |> DateTime.to_unix()

    message = @verification_message
    |> String.replace("{email}", user.email)
    |> String.replace("{timestamp}", to_string(timestamp))
    |> String.replace("{nonce}", nonce)

    # Store challenge in session or database
    {:ok, %{message: message, nonce: nonce, expires_at: timestamp + 300}} # 5 min expiry
  end

  def verify_signature(message, signature, expected_address) do
    # Use Thirdweb SDK on client to sign, verify on server
    # Ensure recovered address matches expected_address
  end
end
```

Client-side signature:

```javascript
import { signMessage } from "thirdweb/wallets";

async function signVerificationMessage(account, message) {
  const signature = await signMessage({
    account,
    message
  });

  return signature;
}
```

### 2. Rate Limiting

Limit wallet connection attempts and balance fetches:

```elixir
defmodule BlocksterV2Web.WalletRateLimiter do
  use Plug.Builder

  plug :check_rate_limit

  defp check_rate_limit(conn, _opts) do
    user_id = get_session(conn, :user_id)

    case Hammer.check_rate("wallet_connect:#{user_id}", 60_000, 5) do
      {:allow, _count} -> conn
      {:deny, _limit} ->
        conn
        |> put_status(:too_many_requests)
        |> Phoenix.Controller.put_flash(:error, "Too many wallet connection attempts")
        |> halt()
    end
  end
end
```

### 3. Transfer Limits

Implement daily/weekly transfer limits:

```elixir
defmodule BlocksterV2.TransferLimits do
  @daily_limit 1_000_000 # 1M ROGUE
  @weekly_limit 5_000_000 # 5M ROGUE

  def check_transfer_limit(user_id, amount) do
    daily_total = get_daily_transfer_total(user_id)
    weekly_total = get_weekly_transfer_total(user_id)

    cond do
      daily_total + amount > @daily_limit ->
        {:error, "Daily transfer limit exceeded"}

      weekly_total + amount > @weekly_limit ->
        {:error, "Weekly transfer limit exceeded"}

      true ->
        :ok
    end
  end
end
```

### 4. Wallet Disconnection Protection

Require password confirmation for wallet disconnection:

```elixir
def handle_event("disconnect_wallet", %{"password" => password}, socket) do
  user = socket.assigns.current_user

  if Bcrypt.verify_pass(password, user.hashed_password) do
    # Disconnect wallet
    BlocksterV2.Wallets.disconnect_wallet(user.id)

    {:noreply,
     socket
     |> assign(:connected_wallet, nil)
     |> put_flash(:info, "Wallet disconnected successfully")}
  else
    {:noreply, put_flash(socket, :error, "Incorrect password")}
  end
end
```

### 5. Phishing Protection

Display clear warnings about wallet signatures:

```heex
<div class="p-4 bg-yellow-50 border border-yellow-200 rounded-lg mb-4">
  <p class="text-sm font-haas_medium_65 text-yellow-900 mb-2">
    ⚠️ Security Notice
  </p>
  <ul class="text-xs text-yellow-800 space-y-1">
    <li>• Never share your private keys or seed phrase</li>
    <li>• Only sign messages from trusted sources</li>
    <li>• Blockster will NEVER ask for your password in wallet</li>
    <li>• Double-check transaction details before confirming</li>
  </ul>
</div>
```

---

## Implementation Plan

**Overall Progress**: 3 of 6 phases complete (50%)

| Phase | Status | Description |
|-------|--------|-------------|
| Phase 1 | ✅ Complete | Basic wallet connection with Thirdweb |
| Phase 2 | ✅ Complete | Multi-chain balance reading (ETH, ROGUE, ERC-20s) |
| Phase 3 | ✅ Complete | Hardware wallet multiplier system |
| Phase 4 | ✅ Complete | Token transfers between wallets (Jan 2026) |
| Phase 5 | 🔜 Next | Security & polish |
| Phase 6 | ⏳ Pending | Advanced features (multi-wallet, NFTs, DeFi) |

**Last Updated**: January 28, 2026 - Phase 4 complete!

---

### Phase 1: Basic Connection (Week 1) ✅ COMPLETE
- [x] Add `connected_wallets` and `wallet_transfers` tables
- [x] Create Thirdweb client setup in assets/js
- [x] Implement wallet connection UI (in Wallet tab)
- [x] Add connect/disconnect functionality
- [x] Store wallet address in database
- [x] Display connected wallet in Wallet tab

**Implementation Details (Jan 28, 2026)**:

**Database Schema**:
- Created migration `20260128204500_create_connected_wallets_and_transfers.exs`
- `connected_wallets` table: stores one wallet per user with provider, chain_id, verification status
- `wallet_transfers` table: ready for Phase 4 (supports uint256 amounts with 78 precision)
- Unique constraint on `user_id` ensures only one wallet per user currently

**Backend Implementation**:
- [ConnectedWallet schema](lib/blockster_v2/connected_wallet.ex): validates Ethereum addresses, enforces supported providers
- [WalletTransfer schema](lib/blockster_v2/wallet_transfer.ex): tracks bidirectional transfers with status
- [Wallets context](lib/blockster_v2/wallets.ex): full CRUD + helper functions (mark_balance_synced, confirm/fail transfers)

**Frontend JavaScript**:
- [ConnectWalletHook](assets/js/connect_wallet_hook.js): Thirdweb vanilla SDK integration
- Supports: MetaMask, Coinbase Wallet, WalletConnect, Phantom
- Auto-adds Rogue Chain network via `wallet_addEthereumChain`
- Auto-imports ROGUE token on Arbitrum via `wallet_watchAsset`
- Graceful error handling with user-friendly messages

**UI/UX**:
- Added new "Wallet" tab to member profile page (6 tabs total, changed from w-1/5 to w-1/6)
- Tab positioned between "Events" and "Airdrop"
- **Connected State**: Shows wallet address (truncated + full), provider icon, disconnect button, copy-to-clipboard
- **Disconnected State**: Beautiful provider selection grid with hover effects
- **Placeholder UI**: "Send to Blockster" and "Receive from Blockster" cards (ready for Phase 4)

**Event Handling** ([MemberLive.Show](lib/blockster_v2_web/live/member_live/show.ex)):
- `connect_metamask/coinbase/walletconnect/phantom` → triggers JS hook
- `wallet_connected` → saves to DB, updates assigns, shows success flash
- `wallet_connection_error` → displays user-friendly error
- `disconnect_wallet` → removes from DB, notifies JS to disconnect, clears assigns
- `copy_address` → flash message confirmation (clipboard handled by JS)
- Only loads connected_wallet when viewing own profile (privacy)

**Configuration**:
- Added `window.WALLETCONNECT_PROJECT_ID` to [root.html.heex](lib/blockster_v2_web/components/layouts/root.html.heex:32)
- **TODO**: Replace placeholder with actual WalletConnect project ID from https://cloud.walletconnect.com

**Branch**: `feature/hardware-wallet-integration`

**Testing Notes**:
- Migration runs successfully
- UI renders correctly on member profile page
- Wallet tab only shown to authenticated users viewing their own profile
- Next: Test actual wallet connection with MetaMask in browser

### Phase 2: Balance Reading (Week 1-2) - ✅ COMPLETE
- [x] Implement native balance reading (ETH, ROGUE)
- [x] Implement ERC-20 balance reading (ROGUE on Arbitrum)
- [x] Add major token balance support (USDC, USDT, ARB)
- [ ] Create background job to refresh balances periodically
- [x] Display balances in UI

**Status**: Core balance reading implementation complete (Jan 28, 2026)

**Files Created/Modified**:
- [assets/js/balance_fetcher.js](assets/js/balance_fetcher.js) - NEW: Balance fetching hook
- [lib/blockster_v2/wallets.ex](lib/blockster_v2/wallets.ex) - MODIFIED: Added Mnesia balance operations
- [lib/blockster_v2/mnesia_initializer.ex](lib/blockster_v2/mnesia_initializer.ex#L388-L405) - MODIFIED: Added `hardware_wallet_balances` table
- [lib/blockster_v2_web/live/member_live/show.ex](lib/blockster_v2_web/live/member_live/show.ex) - MODIFIED: Added balance fetch event handlers
- [lib/blockster_v2_web/live/member_live/show.html.heex](lib/blockster_v2_web/live/member_live/show.html.heex#L1443-L1520) - MODIFIED: Added balance display UI
- [assets/js/app.js](assets/js/app.js#L54,L317) - MODIFIED: Registered BalanceFetcherHook

**Components Implemented**:

1. **BalanceFetcherHook** (JavaScript)
   - Fetches native token balances (ETH, ROGUE) via `eth_getBalance`
   - Fetches ERC-20 balances via `balanceOf` contract calls
   - Supports Ethereum Mainnet (1), Arbitrum One (42161), Rogue Chain (560013)
   - Parallel fetching for optimal performance
   - Returns structured balance data to Phoenix

2. **Mnesia Table: `hardware_wallet_balances`**
   ```elixir
   attributes: [
     :key,                      # {user_id, symbol, chain_id} - PRIMARY KEY
     :user_id,
     :wallet_address,
     :symbol,                   # Token symbol (ETH, ROGUE, USDC, etc.)
     :chain_id,                 # Chain ID
     :balance,                  # Token balance as float
     :token_address,            # Contract address (null for native)
     :decimals,                 # Token decimals
     :last_fetched_at,          # Unix timestamp
     :updated_at
   ]
   index: [:user_id, :wallet_address, :symbol]
   ```

3. **Wallets Context Functions**:
   - `store_balances/3` - Store fetched balances in Mnesia
   - `get_user_balances/1` - Get grouped balances by symbol with combined totals
   - `get_token_balances/2` - Get per-chain breakdown for specific token
   - `get_last_fetch_time/1` - Get timestamp of last balance fetch
   - `clear_balances/1` - Clear all balances on wallet disconnect

4. **LiveView Event Handlers**:
   - `wallet_connected` - Auto-triggers balance fetch on connection
   - `refresh_balances` - Manual refresh button
   - `hardware_wallet_balances_fetched` - Stores balances in Mnesia
   - `balance_fetch_error` - Handles fetch errors
   - `disconnect_wallet` - Clears balances from Mnesia

5. **UI Components**:
   - Token balance display with grouped totals across chains
   - Per-chain breakdown for multi-chain tokens
   - Refresh button for manual updates
   - Last updated timestamp
   - Empty state prompt for first-time fetch

**Supported Tokens**:

| Token | Chains | Type | Contract Address |
|-------|--------|------|------------------|
| **ETH** | Ethereum, Arbitrum | Native | N/A |
| **ROGUE** | Rogue Chain (native) | Native | N/A |
| **ROGUE** | Arbitrum One | ERC-20 | `0x88b8d272b9f1bab7d7896f5f88f8825ce14b05bd` |
| **USDC** | Ethereum, Arbitrum | ERC-20 | `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48`, `0xaf88d065e77c8cC2239327C5EDb3A432268e5831` |
| **USDT** | Ethereum, Arbitrum | ERC-20 | `0xdAC17F958D2ee523a2206206994597C13D831ec7`, `0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9` |
| **ARB** | Ethereum, Arbitrum | ERC-20 | `0xB50721BCf8d664c30412Cfbc6cf7a15145935f0D`, `0x912CE59144191C1204E64559FE8253a0e49E6548` |

**Balance Fetch Flow**:
1. User connects wallet → `wallet_connected` event
2. Phoenix pushes `fetch_hardware_wallet_balances` event to JavaScript
3. BalanceFetcherHook fetches all token balances in parallel
4. JavaScript pushes `hardware_wallet_balances_fetched` back to Phoenix with data
5. Phoenix stores balances in Mnesia via `Wallets.store_balances/3`
6. Updates `last_balance_sync_at` in Postgres
7. UI updates with grouped balances from `Wallets.get_user_balances/1`

**Auto-Reconnect on Page Load** (✅ Implemented Jan 28, 2026):

Connection persistence now matches the email-based smart wallet experience:

1. **On Mount** ([member_live/show.ex:46-59](lib/blockster_v2_web/live/member_live/show.ex#L46-L59)):
   - Check if user has `connected_wallet` record in Postgres
   - If yes, push `auto_reconnect_wallet` event to JavaScript with provider + expected address

2. **Auto-Reconnect** ([connect_wallet_hook.js:17-66](assets/js/connect_wallet_hook.js#L17-L66)):
   - Create wallet instance for saved provider
   - Call `wallet.connect()` (auto-connects if already authorized)
   - **Verify address** matches database (security check)
   - If mismatch → disconnect and warn user
   - If match → notify Phoenix with `wallet_reconnected` event

3. **Post-Reconnect** ([member_live/show.ex:258-260](lib/blockster_v2_web/live/member_live/show.ex#L258-L260)):
   - Automatically trigger balance fetch
   - Load cached balances from Mnesia immediately
   - Refresh from blockchain in background

**Security Measures**:
- Address verification prevents wallet switching attacks
- Mismatch detection: warns user and auto-disconnects
- Silent failure for auto-reconnect (user can manually reconnect)
- No sensitive data stored in JavaScript

**User Experience**:
- ✅ Connect once → stays connected across sessions (like email wallet)
- ✅ Page refresh → auto-reconnects silently
- ✅ Balances load from Mnesia cache instantly
- ✅ Background refresh updates balances
- ✅ No "please reconnect" prompts

**Files Modified for Auto-Reconnect**:
- [assets/js/connect_wallet_hook.js](assets/js/connect_wallet_hook.js#L17-L127) - Auto-reconnect handler + address verification
- [lib/blockster_v2_web/live/member_live/show.ex](lib/blockster_v2_web/live/member_live/show.ex#L46-L285) - Trigger auto-reconnect, handle events

**Testing Notes**:
- Next: Test actual balance fetching with MetaMask connection
- Verify balances display correctly for multi-chain tokens
- Test manual refresh button
- ✅ Verify balances persist across page refreshes (Mnesia + auto-reconnect)
- Test disconnect clears balances from Mnesia
- Test address mismatch detection (switch MetaMask account)
- Test auto-reconnect with different providers

**Deferred**:
- Background job for periodic balance refresh (will implement in Phase 3 or later)

### Phase 3: Multiplier System (Week 2) ✅ COMPLETE (Updated Jan 29, 2026)
- [x] Implement multiplier calculation logic
- [x] Add `hardware_wallet_multiplier` to Mnesia `user_multipliers` table
- [x] Create background job to recalculate multipliers daily
- [x] Update engagement rewards to use combined multiplier
- [x] Display multiplier boost in UI
- [x] **V2 Refactor (Jan 29, 2026)**: Separated ROGUE from wallet multiplier into unified system

**Completed**: January 28, 2026
**V2 Update**: January 29, 2026 - Refactored into Unified Multiplier System

**Key Files**:
- [lib/blockster_v2/wallet_multiplier.ex](../lib/blockster_v2/wallet_multiplier.ex) - Wallet multiplier (ETH + other tokens ONLY)
- [lib/blockster_v2/rogue_multiplier.ex](../lib/blockster_v2/rogue_multiplier.ex) - **NEW**: ROGUE multiplier (smart wallet only)
- [lib/blockster_v2/unified_multiplier.ex](../lib/blockster_v2/unified_multiplier.ex) - **NEW**: Combines all 4 multipliers
- [lib/blockster_v2/wallet_multiplier_refresher.ex](../lib/blockster_v2/wallet_multiplier_refresher.ex) - Daily refresh GenServer
- [lib/blockster_v2/engagement_tracker.ex](../lib/blockster_v2/engagement_tracker.ex#L442-L470) - Multiplier details function
- [lib/blockster_v2_web/live/member_live/show.html.heex](../lib/blockster_v2_web/live/member_live/show.html.heex#L1442-L1530) - UI display
- [lib/blockster_v2/application.ex](../lib/blockster_v2/application.ex#L45) - Supervision tree

#### Implementation Details (V2 - January 29, 2026)

> **V2 Change**: ROGUE is now a **separate multiplier** that only counts ROGUE in the Blockster smart wallet.
> The wallet multiplier now only handles ETH + other tokens (1.0x - 3.6x range).
> See `docs/unified_multiplier_system_v2.md` for complete V2 documentation.

**1. WalletMultiplier Module** ([lib/blockster_v2/wallet_multiplier.ex](../lib/blockster_v2/wallet_multiplier.ex))

Core module for calculating external wallet multipliers based on **ETH + other token** holdings only.

**V2 Multiplier Calculation Logic**:
```elixir
# V2: ROGUE removed - now in separate RogueMultiplier module
total_multiplier = 1.0 + connection_boost + eth_multiplier + other_tokens_multiplier

# Where:
# - 1.0 = base multiplier
# - connection_boost = 0.1 (fixed)
# - eth_multiplier = tiered based on combined ETH (mainnet + Arbitrum)
# - other_tokens_multiplier = min(total_usd_value / 10000, 1.0)
# Range: 1.0 to 3.6 (NO ROGUE)
```

**2. RogueMultiplier Module** ([lib/blockster_v2/rogue_multiplier.ex](../lib/blockster_v2/rogue_multiplier.ex)) - **NEW**

Separate module for ROGUE-based multiplier using **smart wallet balance only**.

```elixir
# ROGUE multiplier is based on Blockster smart wallet balance ONLY
# External wallet ROGUE does NOT count
total_multiplier = 1.0 + rogue_boost

# Where rogue_boost is tiered (0.4x per 100k ROGUE, max 4.0x at 1M+)
# Range: 1.0 to 5.0
```

**3. UnifiedMultiplier Module** ([lib/blockster_v2/unified_multiplier.ex](../lib/blockster_v2/unified_multiplier.ex)) - **NEW**

Combines all 4 multiplier components using multiplicative formula:

```elixir
overall = x_multiplier × phone_multiplier × rogue_multiplier × wallet_multiplier

# Range: 0.5 to 360.0
```

**Key Functions**:
- `WalletMultiplier.calculate_hardware_wallet_multiplier/1` - ETH + other tokens (1.0-3.6x)
- `RogueMultiplier.calculate_rogue_multiplier/1` - Smart wallet ROGUE (1.0-5.0x)
- `UnifiedMultiplier.get_overall_multiplier/1` - Combined product (0.5-360.0x)
- `UnifiedMultiplier.get_user_multipliers/1` - All components + overall

**Mnesia Tables**:
- `user_multipliers` (legacy) - Still updated for backward compatibility
- `unified_multipliers` (V2) - New table with all 4 components + overall

**Tracked Token Contracts** (V2 - ROGUE removed from wallet multiplier):
```elixir
# ROGUE contract removed - now handled by RogueMultiplier using smart wallet balance
@usdc_mainnet "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"
@usdc_arbitrum "0xaf88d065e77c8cc2239327c5edb3a432268e5831"
@usdt_mainnet "0xdac17f958d2ee523a2206206994597c13d831ec7"
@usdt_arbitrum "0xfd086bc7cd5c481dcc9c85ebe478a1c0b69fcbb9"
@arb_mainnet "0xb50721bcf8d664c30412cfbc6cf7a15145935f0d"
@arb_arbitrum "0x912ce59144191c1204e64559fe8253a0e49e6548"
```

**2. WalletMultiplierRefresher GenServer** ([lib/blockster_v2/wallet_multiplier_refresher.ex](../lib/blockster_v2/wallet_multiplier_refresher.ex))

Background service that automatically recalculates multipliers for all users with connected wallets.

**Features**:
- Runs daily at 3:00 AM UTC
- Uses `GlobalSingleton` for safe multi-node deployment (prevents duplicate runs)
- Calculates next run time dynamically (handles server restarts gracefully)
- Provides manual refresh: `WalletMultiplierRefresher.refresh_all_multipliers()`
- Returns detailed results: `%{total_users: N, successes: N, failures: N, timestamp: T}`

**Scheduling Logic**:
```elixir
# Calculates milliseconds until next 3:00 AM UTC
# If past 3 AM today, schedules for 3 AM tomorrow
# Uses Process.send_after for precise timing
```

**Error Handling**:
- Wraps each user update in try/rescue
- Logs failures but continues processing other users
- Returns summary with success/failure counts

**Added to Supervision Tree**: [lib/blockster_v2/application.ex](../lib/blockster_v2/application.ex#L45)

**3. EngagementTracker Integration** ([lib/blockster_v2/engagement_tracker.ex](../lib/blockster_v2/engagement_tracker.ex))

Updated to include hardware wallet multiplier in reward calculations.

**Changes**:
- `get_user_multiplier_details/1` now returns `hardware_wallet_multiplier` field (index 8)
- Default value when no multiplier: `hardware_wallet_multiplier: 0`
- Existing `calculate_bux_earned/4` already uses `overall_multiplier` which now includes wallet boost

**Reward Formula** (unchanged, automatically includes wallet boost):
```elixir
bux_earned = (engagement_score / 10) * base_bux_reward * overall_multiplier * geo_multiplier
```

**4. UI Display** ([lib/blockster_v2_web/live/member_live/show.html.heex](../lib/blockster_v2_web/live/member_live/show.html.heex#L1442-L1530))

Added multiplier boost cards in the Wallet tab on member profile page.

**Active Multiplier Card** (shown when `wallet_multiplier > 1.0`):
- Green gradient background with lightning icon
- Shows total multiplier boost (e.g., "+1.6x")
- Breakdown of components:
  - Base connection boost: +0.10x (always shown)
  - ETH holdings boost (conditional)
  - Other tokens boost (conditional)
- **V2 Note**: ROGUE boost is now shown separately in the ROGUE Multiplier section
- Educational message about daily updates at 3:00 AM UTC

**Info Card** (shown when `wallet_multiplier == 1.0` but wallet connected):
- Blue gradient background with info icon
- Educational content about earning multipliers
- Examples of tier thresholds:
  - 💎 10+ ETH = +1.5x boost
  - 💰 Stablecoins & DeFi tokens = up to +1.0x boost
- **V2 Note**: ROGUE multiplier info is shown separately (smart wallet only)

**Location**: Between "Connected Wallet Display" and "Token Balances" sections

**5. Price Integration**

Multiplier calculation uses `PriceTracker` module for USD value conversion:
- Fetches prices from CoinGecko (via existing PriceTracker GenServer)
- Returns `0.0` if price not available (graceful degradation)
- Used for "other tokens" multiplier calculation (USDC, USDT, ARB)

**6. Testing & Verification (V2)**

**Manual Testing**:
```elixir
# In IEx console
alias BlocksterV2.{WalletMultiplier, RogueMultiplier, UnifiedMultiplier}

# V2: Calculate wallet multiplier (ETH + other tokens ONLY)
wallet_data = WalletMultiplier.calculate_hardware_wallet_multiplier(65)
# Should return:
# %{
#   total_multiplier: 1.6,  # Range: 1.0 - 3.6 (NO ROGUE)
#   connection_boost: 0.1,
#   eth_multiplier: 0.5,
#   other_tokens_multiplier: 0.0,
#   breakdown: %{
#     eth_mainnet: 0.5,
#     eth_arbitrum: 0.3,
#     combined_eth: 0.8,
#     other_tokens_usd: 0
#   }
# }

# V2: Calculate ROGUE multiplier (smart wallet ONLY)
rogue_data = RogueMultiplier.calculate_rogue_multiplier(65)
# Should return:
# %{
#   total_multiplier: 3.0,  # Range: 1.0 - 5.0
#   boost: 2.0,
#   balance: 500_000.0,
#   capped_balance: 500_000.0,
#   next_tier: %{threshold: 600_000, boost: 2.4, rogue_needed: 100_000}
# }

# V2: Get unified multiplier (all 4 components)
overall = UnifiedMultiplier.get_overall_multiplier(65)
# Returns: 42.0 (product of X × Phone × ROGUE × Wallet)

# V2: Get full breakdown
multipliers = UnifiedMultiplier.get_user_multipliers(65)
# Returns:
# %{
#   x_score: 75,
#   x_multiplier: 7.5,
#   phone_multiplier: 2.0,
#   rogue_multiplier: 3.0,
#   wallet_multiplier: 1.6,
#   overall_multiplier: 72.0
# }
```

**Legacy Testing** (for backward compatibility):
```elixir
# Old WalletMultiplier still works but NO ROGUE:
multiplier_data = WalletMultiplier.calculate_hardware_wallet_multiplier(65)

# Old return format (V1 - NO LONGER INCLUDES ROGUE):
# %{
#   total_multiplier: 1.6,
#   connection_boost: 0.1,
#   eth_multiplier: 0.5,
#   other_tokens_multiplier: 0.0,
#   breakdown: %{
#     eth_mainnet: 0.5,
#     eth_arbitrum: 0.3,
#     combined_eth: 0.8,
#     other_tokens_usd: 7_500
#   }
# }

# Update user's multiplier in Mnesia
WalletMultiplier.update_user_multiplier(65)

# Verify Mnesia record
:mnesia.dirty_read({:user_multipliers, 65})
```

**Deployment Notes**:
- Both nodes must be restarted for changes to take effect
- WalletMultiplierRefresher will start on both nodes but only one will run (GlobalSingleton)
- First refresh happens at next 3:00 AM UTC
- Manual refresh available: `WalletMultiplierRefresher.refresh_all_multipliers()`

**Known Limitations**:
- V2: ROGUE multiplier is now separate from wallet multiplier (see `RogueMultiplier` module)
- Multiplier breakdown not stored in Mnesia - only calculated on demand
- UI currently shows basic breakdown - could be enhanced to show tier details
- Price data dependency - if PriceTracker fails, other tokens multiplier will be 0

**Future Enhancements**:
- Store detailed breakdown in Mnesia for faster UI rendering
- Add historical multiplier tracking for analytics
- Support more DeFi tokens (UNI, AAVE, LINK, etc.)
- Add multiplier preview before wallet connection
- V2: Update UI to show all 4 unified multiplier components

### Phase 4: Token Transfers (Week 3) ✅ COMPLETE
- [x] Implement "Send to Blockster" flow (hardware → smart wallet)
- [x] Implement "Send from Blockster" flow (smart wallet → hardware)
- [x] Add transfer history tracking
- [x] ~~Create BUX Minter transfer endpoint~~ (Not needed - Thirdweb SDK handles both directions)
- [x] Add transaction monitoring and confirmations
- [x] Display transfer UI and history

#### Implementation Details (Jan 2026)

**Architecture Decision**: Both transfer directions use Thirdweb SDK directly from the frontend, eliminating the need for a BUX Minter transfer endpoint.

**Key Files Created/Modified**:
- `assets/js/wallet_transfer.js` - WalletTransferHook for both transfer directions
- `lib/blockster_v2/wallet_transfer.ex` - Ecto schema (Postgres) for transfer persistence
- `lib/blockster_v2/wallets.ex` - Context module for transfer CRUD operations (already existed)
- `lib/blockster_v2_web/live/member_live/show.ex` - Event handlers for transfer initiation and completion
- `lib/blockster_v2_web/live/member_live/show.html.heex` - Transfer UI and history display
- `assets/js/balance_fetcher.js` - Added post-transfer balance refresh

**Transfer Flow Implementation**:

1. **Hardware → Blockster (EOA Transfer)**:
   ```javascript
   // Uses window.connectedWallet (MetaMask, Coinbase, etc.)
   const transaction = prepareTransaction({
     to: blockster_wallet,
     value: amountWei,
     chain: window.rogueChain
   });

   const { transactionHash } = await sendTransaction({
     transaction,
     account: connectedWallet.getAccount()
   });
   ```
   - User pays gas fees
   - Requires wallet confirmation
   - Direct native ROGUE transfer

2. **Blockster → Hardware (Smart Wallet Transfer)**:
   ```javascript
   // Uses window.smartAccount (Thirdweb account abstraction)
   const transaction = prepareTransaction({
     to: hardware_wallet,
     value: amountWei,
     chain: window.rogueChain
   });

   const { transactionHash } = await sendTransaction({
     transaction,
     account: smartWallet
   });
   ```
   - **Gasless via Paymaster** (no user gas fees!)
   - No wallet confirmation required (seamless UX)
   - Direct native ROGUE transfer

**Event Flow**:
```
User submits form
  ↓
LiveView: initiate_transfer_to_blockster | initiate_transfer_from_blockster
  ↓
push_event → JavaScript: transfer_to_blockster | transfer_from_blockster
  ↓
Thirdweb SDK: sendTransaction
  ↓
pushEvent → LiveView: transfer_submitted (create DB record, show pending)
  ↓
Thirdweb SDK: waitForReceipt
  ↓
pushEvent → LiveView: transfer_confirmed (update DB, sync balances, reload history)
```

**Balance Synchronization**:
- **Hardware wallet**: Trigger `refresh_balances_after_transfer` event → BalanceFetcherHook refetches
- **Blockster wallet**: Direct Mnesia update via `EngagementTracker.update_user_rogue_balance/3`
- **Transfer history**: Reload from Postgres via `Wallets.list_user_transfers/2`

**Database Schema** (Postgres):
```elixir
schema "wallet_transfers" do
  belongs_to :user, User
  field :direction, :string          # "to_blockster" | "from_blockster"
  field :from_address, :string       # 0x-prefixed
  field :to_address, :string         # 0x-prefixed
  field :token_symbol, :string       # "ROGUE"
  field :amount, :decimal            # Transfer amount
  field :chain_id, :integer          # 560013 (Rogue Chain)
  field :tx_hash, :string            # 0x-prefixed
  field :status, :string             # "pending" | "confirmed" | "failed"
  field :block_number, :integer
  field :gas_used, :integer
  field :confirmed_at, :utc_datetime
  field :error_message, :string
  timestamps()
end
```

**UI Components**:
- **Send to Blockster Card**: Blue gradient, shows hardware wallet balance, amount input with max validation
- **Receive from Blockster Card**: Green gradient, shows Blockster balance, amount input with max validation
- **Transfer History Table**: Direction icons, status badges (pending/confirmed/failed), clickable tx links to Roguescan, formatted timestamps

**Error Handling**:
- User rejection: "Transfer cancelled by user"
- Insufficient funds: "Insufficient ROGUE balance in [wallet type] wallet"
- No wallet: Clear error messages
- All errors logged and displayed to user via flash messages

**Performance**:
- Blockster → Hardware transfers are **gasless** (Paymaster sponsors)
- No backend RPC calls needed (Thirdweb SDK handles all blockchain interaction)
- Balance refresh is async (doesn't block UI)

### Phase 5: Security & Polish (Week 4)
- [ ] Add address ownership verification (signature challenge)
- [ ] Implement rate limiting on wallet operations
- [ ] Add transfer limits (daily/weekly)
- [ ] Add password confirmation for disconnection
- [ ] Add phishing protection warnings
- [ ] Write comprehensive tests

### Phase 6: Advanced Features (Future)
- [ ] Multi-wallet support (connect multiple wallets)
- [ ] NFT holdings display
- [ ] DeFi position tracking (Uniswap LP, Aave deposits, etc.)
- [ ] Wallet activity feed (all transactions)
- [ ] Custom token watchlist
- [ ] Price alerts and notifications

---

## Testing Checklist

### Connection Flow
- [ ] User can connect MetaMask wallet
- [ ] User can connect Coinbase wallet
- [ ] User can connect via WalletConnect
- [ ] User can connect Phantom wallet
- [ ] Connection persists across page refreshes (auto-reconnect)
- [ ] Auto-reconnect happens silently on page load
- [ ] Balances load from cache immediately after reconnect
- [ ] Address verification prevents wallet switching
- [ ] Mismatch warning shown if wallet address changed
- [ ] User can disconnect wallet
- [ ] Only one wallet can be connected at a time
- [ ] Disconnect clears both Postgres and Mnesia data

### Balance Reading
- [ ] Native ROGUE balance (Rogue Chain) displays correctly
- [ ] ERC-20 ROGUE balance (Arbitrum) displays correctly
- [ ] Native ETH balance (Ethereum + Arbitrum) displays correctly
- [ ] USDC/USDT balances display correctly
- [ ] ARB token balances display correctly
- [ ] Multi-chain balances show combined totals
- [ ] Per-chain breakdown displays correctly
- [ ] Balances refresh when "Refresh" button clicked
- [ ] Zero balances display properly
- [ ] Last updated timestamp displays correctly
- [ ] Balances persist across page refreshes (from Mnesia)
- [ ] Disconnect clears balances from display and Mnesia

### Multiplier System (V2)
- [ ] Connecting wallet adds +0.1x base multiplier to **wallet multiplier**
- [ ] ETH holdings add appropriate multiplier (tiers 0.01 → +0.1x to 10.0+ → +1.5x)
- [ ] Other tokens add multiplier based on USD value (up to +1.0x at $10k)
- [ ] Multiplier updates when balances change
- [ ] Multiplier affects BUX earnings in engagement tracking

**V2 Note**: ROGUE is now a **separate multiplier** that only counts smart wallet balance:
- [ ] ROGUE in Blockster smart wallet increases ROGUE multiplier (all tiers)
- [ ] ROGUE in external wallet is displayed but does NOT count toward ROGUE multiplier
- [ ] Overall multiplier = X × Phone × ROGUE × Wallet

### Transfers
- [ ] User can send ROGUE from hardware wallet to Blockster
- [ ] User can send ROGUE from Blockster to hardware wallet
- [ ] Transaction confirmations display correctly
- [ ] Transfer history updates in real-time
- [ ] Balance updates after transfer completes
- [ ] Gas estimation works correctly

### Security
- [ ] Signature verification works correctly
- [ ] Rate limiting prevents abuse
- [ ] Transfer limits enforced
- [ ] Password required for disconnection
- [ ] No private keys stored on server

---

## FAQ

### Q: Can users connect wallets from multiple chains?
**A:** Yes, but only one wallet address can be connected at a time. The multiplier calculation will read balances across all supported chains for that single address.

### Q: What happens if a user loses access to their connected wallet?
**A:** They can disconnect it from Settings (with password confirmation) and connect a different wallet. The multiplier will recalculate based on the new wallet's holdings.

### Q: Are hardware wallet transactions gasless?
**A:** No. Transactions from the connected hardware wallet are standard EOA transactions where the user pays gas fees. Only the Blockster smart wallet (email-based) has gasless transactions via Paymaster.

### Q: How often are balances refreshed?
**A:** Balances are cached and refreshed:
- On-demand when user clicks "Refresh"
- Automatically every 10 minutes while user is active
- After each transfer completes
- When user reconnects wallet

### Q: Can users use their hardware wallet for in-app purchases?
**A:** Yes, but purchases will be separate transactions from their hardware wallet (not account abstracted). The user must confirm each transaction in their wallet app.

### Q: What tokens count toward the external wallet multiplier?
**A:** As of V2, the **external wallet multiplier** (1.0x - 3.6x) is based on:
- ETH (Mainnet + Arbitrum combined) - up to +1.5x
- Major stablecoins (USDC, USDT) - based on USD value
- ARB token - based on USD value
- Other tracked tokens - based on combined USD value (up to +1.0x)

**ROGUE does NOT count** toward the external wallet multiplier. ROGUE has its own separate multiplier (1.0x - 5.0x) based on your **Blockster smart wallet** balance only.

### Q: Does ROGUE in my hardware wallet count toward the ROGUE multiplier?
**A:** **No.** As of V2, only ROGUE held in your **Blockster smart wallet** counts toward the ROGUE multiplier. ROGUE in external wallets (MetaMask, Ledger, etc.) is displayed but does not contribute to multipliers.

This encourages users to hold ROGUE within the Blockster ecosystem.

### Q: Is there a minimum holding requirement?
**A:**
- **ROGUE multiplier**: Starts at 100k ROGUE in your Blockster smart wallet
- **ETH multiplier**: Starts at 0.01 ETH combined (Mainnet + Arbitrum)
- **Other tokens**: Any USD value provides proportional boost (up to $10,000 for +1.0x)

### Q: How is the overall multiplier calculated?
**A:** The overall multiplier uses a **multiplicative formula**:

`Overall = X Multiplier × Phone Multiplier × ROGUE Multiplier × Wallet Multiplier`

| Component | Range |
|-----------|-------|
| X Multiplier | 1.0x - 10.0x |
| Phone Multiplier | 0.5x - 2.0x |
| ROGUE Multiplier | 1.0x - 5.0x |
| Wallet Multiplier | 1.0x - 3.6x |
| **Overall** | **0.5x - 360.0x** |

See `docs/unified_multiplier_system_v2.md` for complete details.

---

## References

- [Thirdweb Documentation](https://portal.thirdweb.com/)
- [Thirdweb React SDK](https://portal.thirdweb.com/react)
- [ERC-4337 Account Abstraction](https://eips.ethereum.org/EIPS/eip-4337)
- [Rogue Chain Documentation](https://docs.roguechain.io/)
- [Phoenix LiveView Documentation](https://hexdocs.pm/phoenix_live_view/)
