# Centralized Vault Bridge — Complete Design Document

> **Status:** Design Document
> **Date:** February 2026
> **Purpose:** Enable BUX Booster players to deposit ETH/USDC/USDT/ARB/SOL on Ethereum, Arbitrum, or Solana and instantly receive ROGUE on Rogue Chain. Withdraw converts ROGUE back to any supported token on any supported chain.
> **Companion docs:** [`vault_contract_specs.md`](vault_contract_specs.md) (full Solidity/Rust specs), [`layerzero_bridge_research.md`](layerzero_bridge_research.md) (research)

---

## Table of Contents

1. [Overview](#1-overview)
2. [Architecture](#2-architecture)
3. [Supported Tokens & Chains](#3-supported-tokens--chains)
4. [Deposit Flow](#4-deposit-flow)
5. [Withdrawal Flow](#5-withdrawal-flow)
6. [Relayer Backend Service](#6-relayer-backend-service)
7. [Smart Contracts Summary](#7-smart-contracts-summary)
8. [Elixir/LiveView Integration](#8-elixirliveview-integration)
9. [JavaScript Hooks](#9-javascript-hooks)
10. [Database Schema](#10-database-schema)
11. [UI/UX Design](#11-uiux-design)
12. [Security](#12-security)
13. [Cost Estimates](#13-cost-estimates)
14. [Implementation Phases](#14-implementation-phases)

---

## 1. Overview

### The Problem
Players must manually buy ROGUE on Uniswap, bridge it via roguetrader.io/bridge from Arbitrum to Rogue Chain, then transfer it to their Blockster wallet. This multi-step process loses users.

### The Solution
One-click "Add Funds" modal on `/play`. User picks a token, enters an amount, connects their external wallet, and confirms. ROGUE appears in their game balance within minutes (or instantly for small amounts). Withdrawals work in reverse — user sends ROGUE from their Blockster smart wallet and receives tokens on their chosen chain.

### Design Philosophy
- Feels like **Cash App / Venmo**, not DeFi
- No jargon: "Add Funds" not "Bridge", "Network fee" not "Gas"
- Users are non-crypto-native (email login, no MetaMask experience)
- Mobile-first
- Maximum 4-5 taps to complete any deposit or withdrawal

---

## 2. Architecture

```
ETHEREUM / ARBITRUM                YOUR BACKEND                   ROGUE CHAIN
┌──────────────────┐              ┌──────────────────┐            ┌──────────────────┐
│  EVM Vault       │              │  Vault Relayer    │            │  User's ERC-4337 │
│  Contract        │──Deposit──>  │  (Extended BUX    │──ROGUE──> │  Smart Wallet    │
│  (holds USDC,    │  Event       │   Minter)         │  Transfer  │                  │
│   ETH, USDT,     │              │                   │            │                  │
│   ARB)           │<──Release──  │  - Event workers  │<──Event──  │  RogueWithdrawal │
│                  │   Tokens     │  - Price service   │  Detected  │  Contract        │
└──────────────────┘              │  - Hot wallet mgmt│            └──────────────────┘
                                  │  - Rate limiter   │
SOLANA                            │  - Postgres DB    │
┌──────────────────┐              │  - Monitoring     │
│  Solana Vault    │──Deposit──>  │                   │
│  Program (PDA)   │  Event       │                   │
│                  │<──Release──  │                   │
└──────────────────┘              └──────────────────┘
```

### Key Decisions
- **Extend BUX Minter** (not new service) — already has signing keys, Fly.io deployment, ethers.js
- **Slide-up modal** (not separate page) — keeps user on `/play`, natural mobile UX
- **Instant credit** for deposits < $500 on 1 confirmation
- **0.5% spread** on conversions (0.2% for stablecoins)
- **UUPS proxy** for vault contracts (consistent with existing ROGUEBankroll pattern)
- **Separate wallet connections** — external wallet (MetaMask/Phantom) for deposits, existing Thirdweb smart wallet for withdrawals

---

## 3. Supported Tokens & Chains

| Chain | Tokens | Chain ID |
|-------|--------|----------|
| **Ethereum** | ETH, USDC, USDT | 1 |
| **Arbitrum One** | ETH, USDC, USDT, ARB | 42161 |
| **Solana** | SOL, USDC, USDT | — |

### Token Addresses

| Token | Ethereum | Arbitrum |
|-------|----------|----------|
| USDC | `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48` | `0xaf88d065e77c8cC2239327C5EDb3A432268e5831` |
| USDT | `0xdAC17F958D2ee523a2206206994597C13D831ec7` | `0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9` |
| ARB | — | `0x912CE59144191C1204E64559FE8253a0e49E6548` |

| Token | Solana |
|-------|--------|
| USDC | `EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v` |
| USDT | `Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB` |

---

## 4. Deposit Flow

### User Journey (4-5 taps)

1. **Tap "Add Funds"** on `/play` balance card
2. **Tap a token** (e.g., "USDC on Ethereum") — grouped by chain
3. **Enter amount** (USD input, live ROGUE conversion preview, quick $25/$50/$100/$250 buttons)
4. **Connect external wallet** (MetaMask / WalletConnect / Coinbase Wallet / Phantom) — skipped if already connected
5. **Confirm & sign** — see summary "You send X USDC → You receive Y ROGUE"
6. **Processing** — step tracker animates through: sent → confirming → crediting → complete
7. **Success** — new balance shown, "Start Playing" CTA

### Technical Flow

```
User taps "Confirm & Send"
  → LiveView creates Deposit record in Postgres (status: pending)
  → push_event("initiate_vault_deposit", params) to VaultDepositHook
  → JS hook: approve ERC-20 + transfer to vault contract (or send native ETH/SOL)
  → JS hook: pushEvent("vault_deposit_submitted", {tx_hash})
  → LiveView updates Deposit record with source_tx_hash
  → Relayer detects Deposit event on source chain
  → Relayer waits for confirmations (or instant credit if < $500)
  → Relayer converts amount: source token → USD → ROGUE (with 0.5% spread)
  → Relayer sends native ROGUE from hot wallet to user's smart_wallet_address
  → Relayer calls webhook: POST /api/vault/webhook/deposit-complete
  → Elixir updates Deposit status, syncs Mnesia balances, broadcasts PubSub
  → LiveView receives {:deposit_status_updated, deposit}, shows success
```

### Instant Credit

| Deposit Size | Behavior |
|-------------|----------|
| < $500 | Credit ROGUE on 1 confirmation (before full finality) |
| $500–$5,000 | Wait for full finality (12 min ETH, ~1 min ARB, ~30s SOL) |
| > $5,000 | Per-transaction limit — rejected |

If a source tx reverts after instant credit (extremely rare), the system creates a clawback record and debits ROGUE.

---

## 5. Withdrawal Flow

### User Journey (5 taps)

1. **Tap "Withdraw"** on `/play` balance card
2. **Enter ROGUE amount** (quick 25%/50%/75%/Max buttons, USD equivalent shown)
3. **Choose destination** (same chain+token picker as deposits)
4. **Enter destination address** (connect wallet to auto-fill, or paste manually, recent addresses shown)
5. **Confirm** — summary with warning "Withdrawals are final"
6. **Processing** — initiated → swapping → sending → complete
7. **Success** — remaining balance shown, destination tx hash

### Technical Flow

```
User taps "Confirm Withdrawal"
  → LiveView creates Withdrawal record (status: pending)
  → push_event("initiate_vault_withdrawal", {amount_wei, vault_address})
  → VaultWithdrawHook: sends native ROGUE from window.smartAccount to Rogue Chain vault
    (gasless via Paymaster — user signs UserOperation, no gas needed)
  → JS hook: pushEvent("vault_withdrawal_submitted", {tx_hash})
  → Relayer detects WithdrawalRequested event on Rogue Chain
  → Relayer converts ROGUE → destination token (with 0.5% spread)
  → Relayer calls vault.release() on destination chain
  → Relayer calls webhook: POST /api/vault/webhook/withdrawal-complete
  → Elixir broadcasts to LiveView, shows success
```

### Withdrawal Limits

| Amount | Behavior |
|--------|----------|
| < $1,000 | Processed immediately |
| $1,000–$5,000 | 24-hour delay (admin can cancel if suspicious) |
| > $5,000 | Per-transaction limit — rejected |
| Daily max per user | $20,000 |

---

## 6. Relayer Backend Service

### Build Decision: Extend BUX Minter

The existing BUX Minter at `bux-minter.fly.dev` is extended with vault relayer capabilities. Rationale:
- Already has Rogue Chain signing keys
- Already has ethers.js + provider setup
- Elixir app already has proven HTTP client pattern (Req, 60s timeout, 5 retries)
- Single deployment on Fly.io with secrets management

### New Components Added to BUX Minter

**Event Watchers** (one per chain, persistent loop):
- Ethereum: polls `eth_getLogs` every ~15s, 64-block finality
- Arbitrum: polls every ~5s, soft finality ~1 min
- Solana: `onLogs` subscription, "finalized" commitment (~30s)
- Rogue Chain: polls every ~2s, 1-block finality

**Deposit Processing Pipeline**:
1. Validate event (correct vault, known token, amount > 0, not duplicate)
2. Check limits (per-tx $5K, per-day $20K per user)
3. Price conversion (source token → USD → ROGUE, apply spread)
4. Instant credit check (< $500 → credit immediately)
5. Send ROGUE from hot wallet to user's `smart_wallet_address`
6. Record in Postgres, notify Elixir via webhook

**Withdrawal Processing Pipeline**:
1. Validate (amount, destination, limits)
2. Price conversion (ROGUE → destination token, apply spread)
3. Check vault balance on destination chain
4. Call `vault.release()` on destination chain
5. Record in Postgres, notify Elixir

**Price Conversion**:
- Primary: fetch from Elixir app's PriceTracker (`GET /api/internal/prices`)
- Fallback: direct CoinGecko call
- Stablecoins: fixed $1.00 price, 0.2% spread (not 0.5%)
- Staleness: pause conversions if prices > 15 min old
- Circuit breaker: pause if ROGUE swings > 10% in 5 min

**Hot/Cold Wallet Management**:
- Hot wallet on Rogue Chain: pre-funded with ROGUE for instant credits
- Threshold: alert if < 100K ROGUE, auto-request rebalance
- Cold wallet: bulk ROGUE, multi-sig, can only be released by 3-of-5

### New API Endpoints

```
POST /vault/process-deposit      — Relayer internal: credit ROGUE to user
POST /vault/process-withdrawal   — Relayer internal: release tokens on dest chain
GET  /vault/deposit/:id          — Deposit status
GET  /vault/withdrawal/:id       — Withdrawal status
GET  /vault/user/:userId/history — User's deposit/withdrawal history
GET  /vault/balances             — Vault balances across all chains
GET  /vault/health               — Health check (watchers, hot wallet, DB)
POST /vault/admin/pause          — Emergency pause
POST /vault/admin/resume         — Resume after pause
POST /vault/admin/review-withdrawal — Approve/cancel large withdrawals
```

---

## 7. Smart Contracts Summary

> Full specs in [`vault_contract_specs.md`](vault_contract_specs.md)

### EVM Vault (Ethereum + Arbitrum)
- UUPS proxy, OpenZeppelin upgradeable base
- `deposit(token, amount, destWallet)` — ERC-20 deposit (uses SafeERC20 for USDT)
- `depositETH(destWallet)` — native ETH deposit (payable)
- `release(token, amount, recipient, nonce)` — relayer-only, nonce replay protection
- `releaseETH(amount, recipient, nonce)` — relayer-only
- Access control: Owner (3-of-5 Gnosis Safe), Relayer (hot wallet), Guardian (pause-only)
- Emergency pause, token whitelist, per-token deposit/release limits
- 22 storage slots documented with UUPS append-only rule

### Rogue Chain Withdrawal Contract
- `requestWithdrawal(amount, destChainId, destToken, destAddress)` — user sends native ROGUE
- Callable gaslessly via ERC-4337 + Paymaster
- `creditUser(wallet, amount, nonce)` — relayer credits ROGUE for deposits (audit trail)
- Same access control pattern

### Solana Vault Program (Anchor/Rust)
- PDA-based vault authority
- `deposit_sol()` / `deposit_token()` instructions
- `release_sol()` / `release_token()` — relayer authority
- Per-nonce PDA for replay protection
- Squads multi-sig as upgrade authority

### Gas Costs
| Operation | Ethereum | Arbitrum | Rogue Chain | Solana |
|-----------|----------|----------|-------------|--------|
| ETH deposit | ~$4-8 | ~$0.03 | — | — |
| ERC-20 deposit | ~$8-20 | ~$0.05 | — | — |
| SOL deposit | — | — | — | ~$0.001 |
| ROGUE credit | — | — | ~free | — |
| Token release | ~$8-15 | ~$0.03 | — | ~$0.001 |

---

## 8. Elixir/LiveView Integration

### New Files

```
lib/blockster_v2/vault_bridge/
├── vault_bridge.ex            # Context module (CRUD for deposits/withdrawals)
├── deposit.ex                 # Ecto schema (binary_id PK)
├── withdrawal.ex              # Ecto schema (binary_id PK)
└── price_converter.ex         # Token→ROGUE conversion with spread

lib/blockster_v2_web/
├── live/vault_live/
│   ├── deposit_modal.ex       # Deposit modal LiveComponent
│   ├── withdraw_modal.ex      # Withdraw modal LiveComponent
│   ├── balance_card.ex        # Enhanced balance display
│   ├── transaction_history.ex # Full-page history at /wallet/history
│   └── shared_components.ex   # Chain selector, token pills, step tracker
├── controllers/
│   └── vault_webhook_controller.ex  # Receives relayer webhooks

assets/js/hooks/
├── vault_deposit.js           # External wallet + deposit tx signing
└── vault_withdraw.js          # ROGUE withdrawal via smart wallet
```

### Modified Files

- `router.ex` — add `/play/deposit`, `/play/withdraw`, `/wallet/history`, `/api/vault/webhook/*`
- `app.js` — register `VaultDepositHook`, `VaultWithdrawHook`
- `config/runtime.exs` — vault addresses, webhook secret
- `bux_booster_live.ex` — add balance card with "Add Funds" / "Withdraw" buttons

### Context Module

```elixir
defmodule BlocksterV2.VaultBridge do
  # create_deposit(attrs) / get_deposit(id) / list_user_deposits(user_id)
  # create_withdrawal(attrs) / get_withdrawal(id) / list_user_withdrawals(user_id)
  # update_deposit_status(id, status, attrs)
  # update_withdrawal_status(id, status, attrs)
  # list_user_history(user_id) — combined deposits + withdrawals, sorted by date
end
```

### Price Converter

```elixir
defmodule BlocksterV2.VaultBridge.PriceConverter do
  @spread Decimal.new("0.005")  # 0.5%

  def convert_to_rogue(source_token, source_amount)
  # Returns {:ok, %{source_amount, usd_value, rogue_amount, rogue_rate, spread_pct}}

  def convert_from_rogue(rogue_amount, dest_token)
  # Returns {:ok, %{rogue_amount, usd_value, dest_amount, rogue_rate, dest_rate, spread_pct}}

  # Stablecoins (USDC/USDT/DAI) use fixed $1.00 price
end
```

### PubSub Topics

| Topic | Message | Producer |
|-------|---------|----------|
| `"vault_deposit:{user_id}"` | `{:deposit_status_updated, %Deposit{}}` | Webhook controller |
| `"vault_withdrawal:{user_id}"` | `{:withdrawal_status_updated, %Withdrawal{}}` | Webhook controller |
| `"bux_balance:{user_id}"` | `{:token_balances_updated, balances}` | Existing (reused after ROGUE credit) |

### Webhook Controller

```elixir
# POST /api/vault/webhook/deposit-complete
def deposit_complete(conn, %{"deposit_id" => id, "rogue_tx_hash" => tx_hash, "secret" => secret})
  # 1. Verify shared secret
  # 2. Update deposit status to "completed"
  # 3. Trigger BuxMinter.sync_user_balances_async(user_id, smart_wallet, force: true)
  # 4. Broadcast {:deposit_status_updated, deposit} on "vault_deposit:{user_id}"

# POST /api/vault/webhook/withdrawal-complete
def withdrawal_complete(conn, params)
  # Same pattern
```

### External Wallet Connection

The deposit flow requires connecting an **external wallet** (MetaMask/Phantom) separate from the user's Blockster smart wallet. Both coexist:
- `window.smartAccount` — Blockster smart wallet on Rogue Chain (for withdrawals)
- `VaultDepositHook.account` — external wallet on source chain (for deposits)

The JS hook creates its own wallet instance, switches to the source chain (NOT Rogue Chain), and stores the reference locally.

---

## 9. JavaScript Hooks

### VaultDepositHook

Handles the deposit transaction on the source chain:

1. **`"connect_deposit_wallet"`** — connect MetaMask/Phantom, switch to source chain
2. **`"fetch_source_balance"`** — read user's balance on source chain
3. **`"initiate_vault_deposit"`** — for native tokens: `prepareTransaction` with value. For ERC-20: `prepareContractCall` on token's `transfer()` to vault address
4. **Pushes back:** `"vault_deposit_submitted"` (tx_hash) or `"vault_deposit_error"` (error message)

Error handling: "User rejected" → "Transaction cancelled", "insufficient" → "Insufficient balance for transfer + fees"

### VaultWithdrawHook

Handles withdrawal on Rogue Chain using existing smart wallet:

1. **`"initiate_vault_withdrawal"`** — uses `window.smartAccount` to send native ROGUE to vault contract. Gasless via Paymaster.
2. **Pushes back:** `"vault_withdrawal_submitted"` (tx_hash) or `"vault_withdrawal_error"`

---

## 10. Database Schema

### Migration: `create_vault_deposits_and_withdrawals`

```sql
-- vault_deposits
id              binary_id PK
user_id         references(:users)
source_chain    string (ethereum/arbitrum/solana)
source_chain_id integer
source_token    string (ETH/USDC/USDT/ARB/SOL)
source_token_address string
source_amount   decimal
source_tx_hash  string (unique per chain)
source_address  string
usd_value       decimal
rogue_rate      decimal
spread_pct      decimal (default 0.005)
rogue_amount    decimal
destination_address string (user's smart_wallet_address)
rogue_tx_hash   string
status          string (pending/source_confirmed/converting/rogue_sent/completed/failed/expired)
confirmed_at    utc_datetime
completed_at    utc_datetime
error_message   text
timestamps

Indexes: user_id, status, source_tx_hash, (source_chain + source_tx_hash) unique

-- vault_withdrawals
id              binary_id PK
user_id         references(:users)
rogue_amount    decimal
rogue_tx_hash   string
source_address  string (user's smart_wallet_address)
usd_value       decimal
rogue_rate      decimal
spread_pct      decimal
dest_amount     decimal
dest_chain      string
dest_chain_id   integer
dest_token      string
dest_token_address string
dest_address    string
dest_tx_hash    string
status          string (pending/rogue_confirmed/converting/dest_sent/completed/failed)
confirmed_at    utc_datetime
completed_at    utc_datetime
error_message   text
timestamps

Indexes: user_id, status, rogue_tx_hash, dest_tx_hash
```

### Relayer Database (separate Postgres on Fly.io)

Additional tables managed by the relayer service:
- `watcher_state` — last processed block per chain
- `vault_balances` — tracked balances per chain/token
- `price_snapshots` — audit trail of prices used
- `hot_wallet_state` — balance, thresholds, last rebalance
- `user_daily_limits` — rolling deposit/withdrawal totals

---

## 11. UI/UX Design

### Balance Card (on `/play` page)

Enhanced balance display with "Add Funds" and "Withdraw" buttons:

```
┌─────────────────────────────────────┐
│  ◉ ROGUE Balance                    │
│  125,430.50              ≈ $7.53    │
│                                     │
│  ┌──────────┐  ┌─────────────┐     │
│  │ + Add    │  │ ↑ Withdraw  │     │
│  │  Funds   │  │             │     │
│  └──────────┘  └─────────────┘     │
│                                     │
│  BUX: 2,340  ·  History →          │
└─────────────────────────────────────┘
```

- "Add Funds" button: `bg-[#CAFC00] text-black` (brand lime)
- "Withdraw" button: `bg-gray-100 text-gray-900`
- Zero balance: "Withdraw" disabled, "Add Funds" prominent
- Loading: pulsing skeleton bars

### Deposit Modal — 6 Steps

**Step 1: Select Token** — chain groups (Ethereum/Arbitrum/Solana) with token pills (ETH, USDC, USDT, ARB, SOL). Bottom sheet on mobile, centered modal on desktop.

**Step 2: Enter Amount** — Dollar input with live ROGUE conversion, quick-fill buttons ($25/$50/$100/$250), fee breakdown (send amount, network fee, spread, receive amount). Min $5, max $10,000.

**Step 3: Connect Wallet** — MetaMask / WalletConnect / Coinbase Wallet for EVM, Phantom / Solflare for Solana. Info callout: "This is a different wallet than your Blockster account." Skipped if already connected.

**Step 4: Confirm** — Visual card: "You Send: 100 USDC on Ethereum → You Receive: ~1,641,666 ROGUE on Blockster". From address, fee breakdown, estimated time.

**Step 5: Processing** — Animated step tracker: sent ✓ → confirming ◉ → crediting ○ → complete ○. Tx hash link. "You can close this and come back."

**Step 6: Success** — Green checkmark, "+1,641,666 ROGUE", new balance, "Start Playing" CTA.

### Withdrawal Modal — 6 Steps

**Step 1: Enter Amount** — ROGUE input, available balance shown, quick % buttons (25/50/75/Max), USD equivalent. Min 100,000 ROGUE.

**Step 2: Choose Destination** — Same chain+token picker as deposit.

**Step 3: Enter Address** — Connect wallet to auto-fill OR paste manually. Recent addresses dropdown. Chain-specific validation.

**Step 4: Confirm** — Same visual card style. Warning: "Withdrawals are final and cannot be reversed."

**Step 5: Processing** — Step tracker.

**Step 6: Success** — Remaining balance, destination tx hash.

### Transaction History (at `/wallet/history`)

List of deposits and withdrawals, grouped by day. Each row shows:
- Direction icon (green down arrow = deposit, blue up arrow = withdrawal)
- Amount (+/- ROGUE)
- Description ("from 100 USDC on Ethereum")
- Status badge: Pending (yellow), Confirmed (green), Failed (red)
- Timestamp

### Error States

- **Insufficient balance**: red text below input, button disabled
- **Invalid address**: red border on input, validation message
- **Tx rejected**: "Transaction cancelled — you rejected it in your wallet"
- **Tx failed on-chain**: red error card with tx hash link, "Try Again" button
- **Relayer timeout**: amber warning "Taking longer than usual — we'll notify you"
- **Service down**: "Withdrawals temporarily unavailable" message

### Toast Notifications

When deposit/withdrawal completes in background (user closed modal):
- Green toast slides in from right: "Deposit complete! 1,641,666 ROGUE added"
- Auto-dismiss after 5 seconds

---

## 12. Security

### Vault Contract Security
- 3-of-5 Gnosis Safe multi-sig as owner
- Guardian role: can emergency pause (cannot unpause — requires deliberation)
- Relayer: can only call `release()`, nothing else
- Per-token deposit/release limits
- Nonce-based replay protection on all releases
- SafeERC20 for USDT compatibility
- UUPS proxy for upgradeability

### Relayer Security
- Hot wallet private key as Fly.io secret
- API authenticated with Bearer token
- Webhook endpoints: shared secret verification
- Rate limiting: 10 req/s per IP

### Operational Security
- Hot wallet: $50K ROGUE operating balance
- Cold wallet: bulk funds, 3-of-5 multi-sig, time-locked
- Auto-rebalance alerts at thresholds
- Withdrawal delay for > $1K

### Circuit Breakers
| Trigger | Action |
|---------|--------|
| ROGUE price swings > 10% in 5 min | Pause all conversions |
| Any token price > 15 min stale | Pause that token |
| Hot wallet < 50K ROGUE | Pause deposits |
| > 10 failed credit txs in 1 hour | Pause + alert |
| Vault balance < 10% of expected | Pause withdrawals for that chain |

### Monitoring & Alerts (Telegram)
- Deposit/withdrawal processing latency
- Failed transactions (any)
- Hot wallet balance thresholds
- Price deviation alerts
- Watcher lag (blocks behind)

### Audit Requirements
- 2+ independent audits for vault contracts ($75K-$150K each)
- Solana program audit ($50K-$75K)
- Relayer code review

---

## 13. Implementation Phases

All chains (Ethereum, Arbitrum, Solana) and all tokens (ETH, USDC, USDT, ARB, SOL) from the start. Each phase is implementation-ready. Tests are written and run after each phase before moving to the next.

---

### Phase 1: Backend Foundation — Schemas, Context, Migration, PriceConverter

**New files:**
1. `priv/repo/migrations/YYYYMMDD_create_vault_deposits_and_withdrawals.exs`
2. `lib/blockster_v2/vault_bridge/vault_bridge.ex` — context module
3. `lib/blockster_v2/vault_bridge/deposit.ex` — Ecto schema
4. `lib/blockster_v2/vault_bridge/withdrawal.ex` — Ecto schema
5. `lib/blockster_v2/vault_bridge/price_converter.ex` — conversion logic
6. `lib/blockster_v2/vault_bridge/chain_config.ex` — supported chains/tokens config

**Migration (`create_vault_deposits_and_withdrawals`):**
```elixir
# vault_deposits table
:id             :binary_id, primary_key
:user_id        references(:users), null: false
:source_chain   :string, null: false          # "ethereum" | "arbitrum" | "solana"
:source_chain_id :integer                      # 1, 42161, nil (Solana)
:source_token   :string, null: false          # "ETH" | "USDC" | "USDT" | "ARB" | "SOL"
:source_token_address :string                  # ERC-20 address, nil for native
:source_amount  :decimal, null: false
:source_tx_hash :string
:source_address :string, null: false          # user's external wallet
:usd_value      :decimal, null: false
:rogue_rate     :decimal, null: false         # ROGUE/USD at time of deposit
:spread_pct     :decimal, default: 0.005
:rogue_amount   :decimal, null: false
:destination_address :string, null: false     # user's smart_wallet_address
:rogue_tx_hash  :string                       # credit tx on Rogue Chain
:status         :string, default: "pending"   # pending|source_confirmed|credited|completed|failed
:confirmed_at   :utc_datetime
:completed_at   :utc_datetime
:error_message  :text
timestamps(type: :utc_datetime)

indexes: [:user_id], [:status], [:source_tx_hash]
unique_index: [:source_chain, :source_tx_hash] where source_tx_hash IS NOT NULL

# vault_withdrawals table
:id             :binary_id, primary_key
:user_id        references(:users), null: false
:rogue_amount   :decimal, null: false
:rogue_tx_hash  :string
:source_address :string, null: false          # user's smart_wallet_address
:usd_value      :decimal, null: false
:rogue_rate     :decimal, null: false
:spread_pct     :decimal, default: 0.005
:dest_amount    :decimal, null: false
:dest_chain     :string, null: false
:dest_chain_id  :integer
:dest_token     :string, null: false
:dest_token_address :string
:dest_address   :string, null: false          # user's external wallet
:dest_tx_hash   :string
:status         :string, default: "pending"   # pending|rogue_confirmed|processing|completed|failed
:confirmed_at   :utc_datetime
:completed_at   :utc_datetime
:error_message  :text
timestamps(type: :utc_datetime)

indexes: [:user_id], [:status], [:rogue_tx_hash], [:dest_tx_hash]
```

**ChainConfig module** — central config for all supported chains/tokens:
```elixir
defmodule BlocksterV2.VaultBridge.ChainConfig do
  @chains %{
    "ethereum" => %{
      chain_id: 1,
      name: "Ethereum",
      native_token: "ETH",
      tokens: %{
        "ETH"  => %{address: nil, decimals: 18, type: :native},
        "USDC" => %{address: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", decimals: 6, type: :erc20},
        "USDT" => %{address: "0xdAC17F958D2ee523a2206206994597C13D831ec7", decimals: 6, type: :erc20}
      }
    },
    "arbitrum" => %{
      chain_id: 42161,
      name: "Arbitrum",
      native_token: "ETH",
      tokens: %{
        "ETH"  => %{address: nil, decimals: 18, type: :native},
        "USDC" => %{address: "0xaf88d065e77c8cC2239327C5EDb3A432268e5831", decimals: 6, type: :erc20},
        "USDT" => %{address: "0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9", decimals: 6, type: :erc20},
        "ARB"  => %{address: "0x912CE59144191C1204E64559FE8253a0e49E6548", decimals: 18, type: :erc20}
      }
    },
    "solana" => %{
      chain_id: nil,
      name: "Solana",
      native_token: "SOL",
      tokens: %{
        "SOL"  => %{address: nil, decimals: 9, type: :native},
        "USDC" => %{address: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v", decimals: 6, type: :spl},
        "USDT" => %{address: "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB", decimals: 6, type: :spl}
      }
    }
  }

  def chains(), do: @chains
  def get_chain(id), do: Map.get(@chains, id)
  def supported_chain?(id), do: Map.has_key?(@chains, id)
  def supported_token?(chain_id, token), do: ...
  def get_token_config(chain_id, token), do: ...
  def vault_address(chain_id), do: Application.get_env(:blockster_v2, :vault_addresses) |> Map.get(chain_id)
end
```

**VaultBridge context module:**
```elixir
def create_deposit(attrs)           # → {:ok, %Deposit{}} | {:error, changeset}
def get_deposit(id)                 # → %Deposit{} | nil
def list_user_deposits(user_id, opts \\ [])  # → [%Deposit{}]
def update_deposit_status(id, status, attrs \\ %{})
def create_withdrawal(attrs)
def get_withdrawal(id)
def list_user_withdrawals(user_id, opts \\ [])
def update_withdrawal_status(id, status, attrs \\ %{})
def list_user_history(user_id, opts \\ [])  # combined, sorted by date desc
```

**PriceConverter module:**
```elixir
@spread Decimal.new("0.005")           # 0.5% for volatile tokens
@stablecoin_spread Decimal.new("0.002") # 0.2% for stablecoins
@stablecoins ~w(USDC USDT DAI)

def convert_to_rogue(source_token, source_amount)
  # → {:ok, %{source_amount, usd_value, rogue_amount, rogue_rate, spread_pct}}
  # Stablecoins use fixed $1.00 price

def convert_from_rogue(rogue_amount, dest_token)
  # → {:ok, %{rogue_amount, usd_value, dest_amount, rogue_rate, dest_rate, spread_pct}}

defp get_token_price_usd(symbol)  # PriceTracker.get_price/1 wrapper
defp applicable_spread(token)     # 0.2% for stablecoins, 0.5% for others
```

**Deposit schema changeset validations:**
- `validate_inclusion(:source_chain, ["ethereum", "arbitrum", "solana"])`
- `validate_inclusion(:source_token, ["ETH", "USDC", "USDT", "ARB", "SOL"])`
- `validate_number(:source_amount, greater_than: 0)`
- `validate_number(:rogue_amount, greater_than: 0)`
- Custom: validate token is valid for the chosen chain (ARB only on arbitrum, SOL only on solana)

**Withdrawal schema changeset validations:**
- Same chain/token validations
- `validate_number(:rogue_amount, greater_than: 0)`

**Tests to write and run after Phase 1:**
- [ ] ChainConfig: all chains/tokens accessible, supported_chain?/supported_token? checks, vault_address lookup
- [ ] Deposit schema: valid changeset, required fields, chain/token validation, cross-chain token validation (ARB rejected on ethereum), status transitions
- [ ] Withdrawal schema: valid changeset, required fields, dest chain/token validation
- [ ] VaultBridge context: create_deposit, get_deposit, list_user_deposits, update_deposit_status, create_withdrawal, get_withdrawal, list_user_withdrawals, update_withdrawal_status, list_user_history (combined + sorted)
- [ ] PriceConverter: convert_to_rogue with ETH, convert_to_rogue with USDC (stablecoin spread), convert_from_rogue, handles price not found, handles zero/negative amounts, spread calculation accuracy
- [ ] Migration: tables created with correct columns and indexes

---

### Phase 2: Webhook Controller + PubSub Integration

**New files:**
1. `lib/blockster_v2_web/controllers/vault_webhook_controller.ex`

**Modified files:**
1. `lib/blockster_v2_web/router.ex` — add webhook routes
2. `config/runtime.exs` — add `vault_webhook_secret`, `vault_addresses` config

**Webhook controller:**
```elixir
defmodule BlocksterV2Web.VaultWebhookController do
  use BlocksterV2Web, :controller

  # POST /api/vault/webhook/deposit-complete
  def deposit_complete(conn, params)
    # 1. Verify shared secret from params["secret"]
    # 2. VaultBridge.update_deposit_status(id, "completed", %{rogue_tx_hash, completed_at})
    # 3. BuxMinter.sync_user_balances_async(user_id, smart_wallet, force: true)
    # 4. Phoenix.PubSub.broadcast("vault_deposit:#{user_id}", {:deposit_status_updated, deposit})
    # 5. json(conn, %{ok: true})

  # POST /api/vault/webhook/withdrawal-complete
  def withdrawal_complete(conn, params)
    # 1. Verify secret
    # 2. VaultBridge.update_withdrawal_status(id, "completed", %{dest_tx_hash, completed_at})
    # 3. Phoenix.PubSub.broadcast("vault_withdrawal:#{user_id}", {:withdrawal_status_updated, withdrawal})
    # 4. json(conn, %{ok: true})

  # POST /api/vault/webhook/status-update
  def status_update(conn, params)
    # Generic status update for intermediate states (source_confirmed, processing, etc.)
    # Broadcasts to appropriate PubSub topic
end
```

**Router additions:**
```elixir
scope "/api/vault", BlocksterV2Web do
  pipe_through :api
  post "/webhook/deposit-complete", VaultWebhookController, :deposit_complete
  post "/webhook/withdrawal-complete", VaultWebhookController, :withdrawal_complete
  post "/webhook/status-update", VaultWebhookController, :status_update
end
```

**Config additions (`runtime.exs`):**
```elixir
config :blockster_v2,
  vault_webhook_secret: System.get_env("VAULT_WEBHOOK_SECRET"),
  vault_addresses: %{
    "ethereum" => System.get_env("VAULT_ADDRESS_ETHEREUM"),
    "arbitrum" => System.get_env("VAULT_ADDRESS_ARBITRUM"),
    "solana"   => System.get_env("VAULT_ADDRESS_SOLANA"),
    "rogue"    => System.get_env("VAULT_ADDRESS_ROGUE")
  }
```

**Tests to write and run after Phase 2:**
- [ ] deposit_complete webhook: valid request creates completed deposit, updates Mnesia via sync, broadcasts PubSub, returns 200
- [ ] deposit_complete webhook: invalid secret returns 401
- [ ] deposit_complete webhook: missing deposit_id returns error
- [ ] withdrawal_complete webhook: valid request completes withdrawal, broadcasts PubSub
- [ ] withdrawal_complete webhook: invalid secret returns 401
- [ ] status_update webhook: updates intermediate statuses (source_confirmed, processing)
- [ ] PubSub integration: subscriber receives {:deposit_status_updated, deposit} on broadcast
- [ ] PubSub integration: subscriber receives {:withdrawal_status_updated, withdrawal} on broadcast

---

### Phase 3: Balance Card UI + "Add Funds" / "Withdraw" Buttons

**New files:**
1. `lib/blockster_v2_web/live/vault_live/balance_card.ex` — function component

**Modified files:**
1. `lib/blockster_v2_web/live/bux_booster_live.ex` — integrate balance card, add modal assigns
2. `lib/blockster_v2_web/live/bux_booster_live.html.heex` — render balance card above game

**Balance card component** (renders above the game card on `/play`):
```elixir
defmodule BlocksterV2Web.VaultLive.BalanceCard do
  use Phoenix.Component

  attr :rogue_balance, :float, required: true
  attr :rogue_usd_price, :float, required: true
  attr :bux_balance, :float, default: 0
  def balance_card(assigns) do
    ~H"""
    <div class="bg-zinc-800 rounded-2xl border border-zinc-700 p-4 sm:p-5 mb-4">
      <!-- ROGUE Balance label -->
      <!-- Balance amount + USD equivalent -->
      <!-- Add Funds (bg-[#CAFC00] text-black) + Withdraw (bg-zinc-700 text-white) buttons -->
      <!-- BUX balance + History link -->
    </div>
    """
  end
end
```

**BuxBoosterLive changes:**
- Add to assigns on mount: `:show_deposit_modal` (false), `:show_withdraw_modal` (false)
- Add event handlers: `"show_deposit_modal"`, `"show_withdraw_modal"`, `"close_deposit_modal"`, `"close_withdraw_modal"`
- Render balance card above game area
- Render empty modal containers (content in Phase 4/5)

**Note:** Dark theme (`bg-zinc-800/900`) — not the white theme from the UI spec. Match existing BUX Booster page styling.

**Tests to write and run after Phase 3:**
- [ ] Balance card renders ROGUE balance with correct formatting
- [ ] Balance card shows USD equivalent (balance * rogue_usd_price)
- [ ] Balance card shows BUX balance
- [ ] "Add Funds" button triggers show_deposit_modal event
- [ ] "Withdraw" button triggers show_withdraw_modal event
- [ ] Zero ROGUE balance: Withdraw button disabled
- [ ] History link points to /wallet/history
- [ ] BuxBoosterLive mounts with modal assigns false
- [ ] show_deposit_modal / close_deposit_modal toggles assign

---

### Phase 4: Deposit Modal — Full 6-Step Flow

**New files:**
1. `lib/blockster_v2_web/live/vault_live/deposit_modal.ex` — stateful LiveComponent
2. `assets/js/hooks/vault_deposit_hook.js` — external wallet connection + deposit tx

**Modified files:**
1. `lib/blockster_v2_web/live/bux_booster_live.ex` — render deposit modal component
2. `lib/blockster_v2_web/live/bux_booster_live.html.heex` — modal markup
3. `assets/js/app.js` — register VaultDepositHook

**DepositModal LiveComponent:**
```elixir
defmodule BlocksterV2Web.VaultLive.DepositModal do
  use BlocksterV2Web, :live_component

  # Assigns:
  # :step — :select_token | :enter_amount | :connect_wallet | :confirm | :processing | :success | :error
  # :selected_chain — "ethereum" | "arbitrum" | "solana" | nil
  # :selected_token — "ETH" | "USDC" | "USDT" | "ARB" | "SOL" | nil
  # :amount — Decimal | nil (USD amount)
  # :conversion — %{source_amount, usd_value, rogue_amount, rogue_rate, spread_pct} | nil
  # :external_wallet — %{address, provider} | nil
  # :source_balance — string | nil
  # :deposit — %Deposit{} | nil
  # :processing_step — 1..4 (for step tracker animation)
  # :error_message — string | nil

  def mount(socket) do
    {:ok, assign(socket,
      step: :select_token,
      selected_chain: nil,
      selected_token: nil,
      amount: nil,
      conversion: nil,
      external_wallet: nil,
      source_balance: nil,
      deposit: nil,
      processing_step: 0,
      error_message: nil
    )}
  end

  # Events:
  # "select_token" %{"chain" => chain, "token" => token} → set chain+token, advance to :enter_amount
  # "update_amount" %{"amount" => str} → parse, call PriceConverter, update conversion
  # "set_quick_amount" %{"amount" => "25"|"50"|"100"|"250"} → set amount
  # "continue_to_wallet" → advance to :connect_wallet (or :confirm if already connected)
  # "deposit_wallet_connected" %{"address" => addr, "provider" => p} → set wallet, advance to :confirm
  # "source_balance_fetched" %{"balance" => bal} → update source_balance
  # "confirm_deposit" → create Deposit record, push_event to JS hook, advance to :processing
  # "vault_deposit_submitted" %{"tx_hash" => hash} → update deposit record
  # "vault_deposit_error" %{"error" => msg} → show error state
  # "go_back" → step back one
  # "restart" → reset to :select_token

  # PubSub handler:
  # {:deposit_status_updated, deposit} → update processing_step, advance to :success when completed

  # Renders:
  # Step 1: Chain groups (Ethereum/Arbitrum/Solana) with token pill buttons
  # Step 2: USD amount input, quick buttons, live conversion preview, fee breakdown
  # Step 3: Wallet provider buttons (MetaMask/WalletConnect/Coinbase for EVM, Phantom/Solflare for Solana)
  # Step 4: Confirm card (You Send → You Receive), details, Confirm & Send button
  # Step 5: Spinner + step tracker (sent ✓ → confirming ◉ → crediting ○ → complete ○)
  # Step 6: Success — green check, +ROGUE amount, new balance, Start Playing CTA
end
```

**VaultDepositHook (JS):**
```javascript
export const VaultDepositHook = {
  mounted() {
    this.wallet = null;
    this.account = null;

    // "connect_deposit_wallet" → connect MetaMask/Phantom, switch to source chain
    // pushes back "deposit_wallet_connected" {address, provider}

    // "fetch_source_balance" → read balance on source chain
    // pushes back "source_balance_fetched" {balance}

    // "initiate_vault_deposit" → approve ERC-20 + transfer to vault (or send native ETH/SOL)
    // waits for receipt
    // pushes back "vault_deposit_submitted" {tx_hash, deposit_id}
    // or "vault_deposit_error" {error}
  },
  destroyed() {
    // disconnect external wallet
  }
};
```

**Key implementation details:**
- Modal is a bottom sheet on mobile (`fixed bottom-0 inset-x-0 rounded-t-2xl`), centered on desktop (`sm:max-w-md sm:rounded-2xl`)
- Close on backdrop click (`phx-click-away`), Escape key
- Dark theme: `bg-zinc-800` modal body, `bg-zinc-900` backdrop
- External wallet stays on source chain (NOT Rogue Chain)
- For ERC-20: `prepareContractCall` on token `transfer(vault_address, amount)` — NOT approve+deposit pattern, just direct transfer to vault
- For native tokens (ETH/SOL): `prepareTransaction` with value
- Subscribe to `"vault_deposit:#{user_id}"` in parent LiveView, forward to component
- Subscribe to `"token_prices"` to recalculate conversion when prices update

**Tests to write and run after Phase 4:**
- [ ] DepositModal mounts at :select_token step
- [ ] select_token event: sets chain + token, advances to :enter_amount
- [ ] Token validation: ARB only selectable on arbitrum, SOL only on solana
- [ ] update_amount: parses valid amounts, calls PriceConverter, updates conversion
- [ ] update_amount: rejects negative, zero, non-numeric
- [ ] set_quick_amount: sets predefined amounts
- [ ] Amount limits: below $5 shows error, above $10,000 shows error
- [ ] continue_to_wallet: advances to :connect_wallet
- [ ] continue_to_wallet: skips to :confirm if wallet already connected
- [ ] confirm_deposit: creates Deposit record with correct attrs
- [ ] confirm_deposit: deposit has status "pending"
- [ ] vault_deposit_submitted: updates deposit with source_tx_hash
- [ ] vault_deposit_error: sets error_message, returns to :enter_amount
- [ ] PubSub {:deposit_status_updated, %{status: "completed"}}: advances to :success
- [ ] go_back: navigates to previous step
- [ ] restart: resets to :select_token
- [ ] Conversion recalculates on token_prices_updated
- [ ] Stablecoin conversion uses 0.2% spread

---

### Phase 5: Withdrawal Modal — Full 6-Step Flow

**New files:**
1. `lib/blockster_v2_web/live/vault_live/withdrawal_modal.ex` — stateful LiveComponent
2. `assets/js/hooks/vault_withdraw_hook.js` — ROGUE transfer via smart wallet

**Modified files:**
1. `lib/blockster_v2_web/live/bux_booster_live.ex` — render withdrawal modal
2. `lib/blockster_v2_web/live/bux_booster_live.html.heex` — modal markup
3. `assets/js/app.js` — register VaultWithdrawHook

**WithdrawalModal LiveComponent:**
```elixir
defmodule BlocksterV2Web.VaultLive.WithdrawalModal do
  use BlocksterV2Web, :live_component

  # Assigns:
  # :step — :enter_amount | :select_destination | :enter_address | :confirm | :processing | :success | :error
  # :rogue_balance — float (user's current ROGUE)
  # :rogue_amount — Decimal | nil
  # :selected_chain — string | nil
  # :selected_token — string | nil
  # :dest_address — string | nil
  # :conversion — %{rogue_amount, usd_value, dest_amount, ...} | nil
  # :withdrawal — %Withdrawal{} | nil
  # :processing_step — 1..4
  # :error_message — string | nil
  # :address_valid — boolean

  # Events:
  # "update_rogue_amount" %{"amount" => str}
  # "set_percentage" %{"pct" => "0.25"|"0.5"|"0.75"|"1.0"} → calculate from balance
  # "select_destination" %{"chain" => c, "token" => t}
  # "update_dest_address" %{"address" => addr} → validate format per chain
  # "connect_withdraw_dest_wallet" → auto-fill address from external wallet
  # "confirm_withdrawal" → create Withdrawal record, push_event to JS hook
  # "vault_withdrawal_submitted" %{"tx_hash" => hash}
  # "vault_withdrawal_error" %{"error" => msg}
end
```

**VaultWithdrawHook (JS):**
```javascript
export const VaultWithdrawHook = {
  mounted() {
    // "initiate_vault_withdrawal" → uses window.smartAccount (existing Thirdweb smart wallet)
    // Sends native ROGUE to vault contract on Rogue Chain
    // Gasless via Paymaster — user just signs UserOperation
    // pushes back "vault_withdrawal_submitted" {tx_hash, withdrawal_id}
    // or "vault_withdrawal_error" {error}
  }
};
```

**Key implementation details:**
- ROGUE input (not USD) — show USD equivalent below
- Quick percentage buttons: 25%, 50%, 75%, Max
- Minimum withdrawal: 100,000 ROGUE
- Address validation: EVM = `^0x[0-9a-fA-F]{40}$`, Solana = base58, 32-44 chars
- Withdrawal uses existing `window.smartAccount` on Rogue Chain — NO external wallet needed
- Gasless via existing Paymaster
- Warning banner: "Withdrawals are final and cannot be reversed"
- Subscribe to `"vault_withdrawal:#{user_id}"` for status updates

**Tests to write and run after Phase 5:**
- [ ] WithdrawalModal mounts at :enter_amount step
- [ ] update_rogue_amount: parses valid amounts, calls PriceConverter.convert_from_rogue
- [ ] set_percentage: calculates correct ROGUE amount from balance
- [ ] Amount validation: below minimum shows error, above balance shows error
- [ ] select_destination: sets chain + token, shows converted dest_amount
- [ ] update_dest_address: validates EVM address format (0x + 40 hex chars)
- [ ] update_dest_address: validates Solana address format (base58)
- [ ] update_dest_address: rejects invalid addresses
- [ ] confirm_withdrawal: creates Withdrawal record with correct attrs
- [ ] confirm_withdrawal: withdrawal has status "pending"
- [ ] vault_withdrawal_submitted: updates withdrawal with rogue_tx_hash
- [ ] vault_withdrawal_error: sets error_message
- [ ] PubSub {:withdrawal_status_updated, %{status: "completed"}}: advances to :success
- [ ] Conversion uses correct spread (0.5% volatile, 0.2% stablecoin)
- [ ] go_back navigates correctly through steps

---

### Phase 6: Transaction History + Toast Notifications

**New files:**
1. `lib/blockster_v2_web/live/vault_live/transaction_history.ex` — LiveView at `/wallet/history`
2. `lib/blockster_v2_web/live/vault_live/transaction_history.html.heex`
3. `lib/blockster_v2_web/live/vault_live/toast_component.ex` — toast notification component

**Modified files:**
1. `lib/blockster_v2_web/router.ex` — add `/wallet/history` route
2. `lib/blockster_v2_web/live/bux_booster_live.ex` — subscribe to vault PubSub for toast notifications when modal is closed
3. `lib/blockster_v2_web/components/layouts.ex` — optional: add toast container to root layout

**TransactionHistory LiveView:**
```elixir
defmodule BlocksterV2Web.VaultLive.TransactionHistory do
  use BlocksterV2Web, :live_view

  # Mount: load user's combined deposit/withdrawal history
  # Subscribe to vault_deposit + vault_withdrawal PubSub for live updates
  # Display: grouped by date, each row shows direction icon, amount, description, status badge, time
  # Filter: All | Deposits | Withdrawals (tabs or dropdown)
  # Pagination: load more on scroll or "Load More" button
  # Empty state: "No transactions yet — Add funds to start playing"
end
```

**Toast component** (for background completion notifications):
```elixir
defmodule BlocksterV2Web.VaultLive.ToastComponent do
  use Phoenix.Component
  # Renders fixed-position toast in top-right
  # Green for success: "Deposit complete! X ROGUE added"
  # Red for failure: "Deposit failed — tap for details"
  # Auto-dismiss after 5 seconds (JS hook or phx-remove with animation)
end
```

**BuxBoosterLive toast integration:**
- When deposit/withdrawal completes AND modal is closed, show toast
- Track `show_toast` assign + `toast_message` + `toast_type`

**Tests to write and run after Phase 6:**
- [ ] TransactionHistory: loads user deposits + withdrawals sorted by date desc
- [ ] TransactionHistory: empty state renders correctly for user with no history
- [ ] TransactionHistory: deposits show green icon, positive ROGUE amount, source info
- [ ] TransactionHistory: withdrawals show blue icon, negative ROGUE amount, dest info
- [ ] TransactionHistory: status badges render correctly (pending=yellow, completed=green, failed=red)
- [ ] TransactionHistory: filter by deposits only
- [ ] TransactionHistory: filter by withdrawals only
- [ ] TransactionHistory: live updates via PubSub (new deposit appears)
- [ ] Toast: renders success message with correct ROGUE amount
- [ ] Toast: renders error message
- [ ] BuxBoosterLive: toast shown when deposit completes while modal is closed

---

### Phase 7: Rate Limiting, Validation & Error Handling

**Modified files:**
1. `lib/blockster_v2/vault_bridge/vault_bridge.ex` — add limit checking functions
2. `lib/blockster_v2/vault_bridge/price_converter.ex` — add staleness check, circuit breaker
3. `lib/blockster_v2_web/controllers/vault_webhook_controller.ex` — add error status handling
4. `lib/blockster_v2_web/live/vault_live/deposit_modal.ex` — integrate limit checks
5. `lib/blockster_v2_web/live/vault_live/withdrawal_modal.ex` — integrate limit checks

**VaultBridge limit functions:**
```elixir
# Deposit limits
@max_deposit_usd Decimal.new("10000")    # $10K per transaction
@max_daily_deposit_usd Decimal.new("20000") # $20K per day
@min_deposit_usd Decimal.new("5")        # $5 minimum

def check_deposit_limits(user_id, usd_value) do
  # 1. Check per-tx limit
  # 2. Sum today's deposits for user
  # 3. Check daily limit
  # Returns :ok | {:error, :per_tx_limit_exceeded} | {:error, :daily_limit_exceeded}
end

# Withdrawal limits
@max_withdrawal_usd Decimal.new("5000")
@max_daily_withdrawal_usd Decimal.new("20000")
@min_withdrawal_rogue Decimal.new("100000")
@large_withdrawal_usd Decimal.new("1000")  # delay threshold

def check_withdrawal_limits(user_id, usd_value) do
  # Same pattern
  # Also returns {:ok, :delayed} for amounts > $1K (24h delay)
end
```

**PriceConverter circuit breaker:**
```elixir
@max_price_age_seconds 900  # 15 minutes

def convert_to_rogue(source_token, source_amount) do
  with {:ok, source_price} <- get_fresh_price(source_token),
       {:ok, rogue_price} <- get_fresh_price("ROGUE") do
    # ... conversion logic
  end
end

defp get_fresh_price(symbol) do
  case PriceTracker.get_price(symbol) do
    {:ok, %{usd_price: price, last_updated: updated}} ->
      if DateTime.diff(DateTime.utc_now(), updated) > @max_price_age_seconds,
        do: {:error, :price_stale},
        else: {:ok, to_decimal(price)}
    {:error, _} -> {:error, {:price_not_found, symbol}}
  end
end
```

**Tests to write and run after Phase 7:**
- [ ] check_deposit_limits: allows deposits within limits
- [ ] check_deposit_limits: rejects deposits > $10K per tx
- [ ] check_deposit_limits: rejects when daily total would exceed $20K
- [ ] check_deposit_limits: rejects deposits < $5
- [ ] check_withdrawal_limits: allows withdrawals within limits
- [ ] check_withdrawal_limits: rejects > $5K per tx
- [ ] check_withdrawal_limits: returns {:ok, :delayed} for $1K-$5K
- [ ] check_withdrawal_limits: rejects below minimum ROGUE
- [ ] check_withdrawal_limits: rejects when daily total exceeded
- [ ] PriceConverter: returns {:error, :price_stale} when price > 15 min old
- [ ] PriceConverter: returns {:error, {:price_not_found, token}} for unknown token
- [ ] DepositModal: shows error when deposit exceeds limit
- [ ] WithdrawalModal: shows error when withdrawal exceeds limit
- [ ] WithdrawalModal: shows delay warning for large withdrawals

---

### Phase 8: Polish, Error States & Production Prep

**Modified files:**
1. `lib/blockster_v2_web/live/vault_live/deposit_modal.ex` — error state UI, timeout handling
2. `lib/blockster_v2_web/live/vault_live/withdrawal_modal.ex` — error state UI
3. `lib/blockster_v2_web/components/layouts.ex` — add "Add Funds" link in nav or footer
4. `assets/js/hooks/vault_deposit_hook.js` — error parsing, wallet not installed handling
5. `assets/js/hooks/vault_withdraw_hook.js` — error parsing

**Error states to implement:**
- Insufficient balance on source chain (from JS hook balance check)
- Transaction rejected by user in MetaMask/Phantom
- Transaction reverted on-chain
- Relayer timeout (>10 min for deposit, >30 min for withdrawal) — show amber "taking longer" state
- Wallet extension not installed — show install link
- Wrong network in MetaMask — prompt chain switch
- Price changed significantly during flow — show warning, recalculate

**Additional polish:**
- Modal slide-up animation (CSS `translate-y` transition)
- Toast slide-in animation
- Step tracker transitions (gray → spinning yellow → green check)
- Balance card: brief green flash on ROGUE balance when updated
- Loading skeletons for conversion preview
- `phx-debounce="300"` on amount inputs
- Format large ROGUE numbers with commas (e.g., 1,641,666)
- Format USD with 2 decimal places
- Truncate wallet addresses (0x1a2b...3c4d)
- Accessibility: `role="dialog"`, `aria-modal`, focus trap, Escape to close

**Tests to write and run after Phase 8:**
- [ ] Deposit error: "Transaction cancelled" displayed when user rejects in wallet
- [ ] Deposit error: "Insufficient balance" displayed correctly
- [ ] Deposit error: on-chain failure shows tx hash link
- [ ] Withdrawal error: "Insufficient ROGUE balance" validation
- [ ] Withdrawal error: invalid address format shows per-chain error message
- [ ] Timeout handling: after 10 min shows "taking longer than usual" state
- [ ] Amount formatting: large numbers display with commas
- [ ] Address formatting: truncated correctly
- [ ] Modal: closes on backdrop click
- [ ] Modal: closes on Escape key
- [ ] Navigation: "Add Funds" accessible from footer/nav

---

### Summary: Implementation Order

| Phase | Description | New Files | Modified Files | Tests |
|-------|-------------|-----------|----------------|-------|
| **1** | Backend foundation — schemas, context, migration, PriceConverter, ChainConfig | 6 | 0 | ~20 |
| **2** | Webhook controller + PubSub integration | 1 | 2 | ~10 |
| **3** | Balance card UI on /play page | 1 | 2 | ~10 |
| **4** | Deposit modal — full 6-step flow + JS hook | 2 | 3 | ~18 |
| **5** | Withdrawal modal — full 6-step flow + JS hook | 2 | 3 | ~15 |
| **6** | Transaction history page + toast notifications | 3 | 3 | ~12 |
| **7** | Rate limiting, validation, circuit breakers | 0 | 5 | ~15 |
| **8** | Polish, error states, production prep | 0 | 5 | ~12 |
| **Total** | | **15 new** | **~14 modified** | **~112 tests** |

Each phase is self-contained. Tests are written and run after each phase before proceeding to the next.

**Note:** Smart contracts (EVM Vault, Rogue Chain Withdrawal, Solana Vault Program) and the relayer service extension (BUX Minter) are separate workstreams that happen in parallel. Full specs in [`vault_contract_specs.md`](vault_contract_specs.md). The Elixir/LiveView phases above can be developed and tested with mock webhook calls before the contracts and relayer are deployed.
