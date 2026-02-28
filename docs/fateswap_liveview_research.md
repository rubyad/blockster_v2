# FateSwap Phoenix LiveView App — Research & Architecture

> FateSwap is a **standalone Elixir/Phoenix application** on its own domain — completely separate from Blockster V2. It shares no database, no deployment, and no runtime with Blockster. Patterns and learnings from BuxBooster are referenced as architectural inspiration only.

> Research compiled from 5 parallel investigation agents covering: Solana-Elixir integration, wallet/Jupiter frontend integration, existing codebase pattern analysis, DEX swap UI design, and wallet authentication.

### Version Requirements

Managed via **asdf** (`.tool-versions` per project). Claude installs versions and creates config files during scaffold phases.

| Component | Version | Manager |
|---|---|---|
| Elixir | 1.18.2 | asdf |
| Erlang/OTP | 27.2 | asdf |
| Phoenix | 1.7.20 | mix.exs |
| Phoenix LiveView | 1.1.0 | mix.exs |
| Node.js (fate-settler) | 22 LTS (22.13.1) | asdf |
| Rust (Anchor programs) | 1.84.1 | rustup |
| Anchor CLI | 0.31.1 | cargo install |

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Authentication: Wallet-Only (No Email)](#2-authentication-wallet-only-no-email)
3. [Backend: Elixir Services](#3-backend-elixir-services)
4. [Node.js Microservice: fate-settler (Secured)](#4-nodejs-microservice-fate-settler-secured)
5. [Frontend: LiveView + JS Hooks](#5-frontend-liveview--js-hooks)
6. [UI Components & Design](#6-ui-components--design)
7. [Reusable Patterns from Blockster (Reference Only)](#7-reusable-patterns-from-blockster-reference-only)
8. [NPM Dependencies](#8-npm-dependencies)
9. [Elixir Dependencies](#9-elixir-dependencies)
10. [Open Questions](#10-open-questions)
11. [Referral System](#11-referral-system)
12. [LP Provider Interface](#12-lp-provider-interface)
13. [Provably Fair Verification UI](#13-provably-fair-verification-ui)
14. [Token Selector Modal](#14-token-selector-modal)
15. [Mobile Strategy](#15-mobile-strategy)

---

## 1. Architecture Overview

FateSwap is a **standalone Phoenix LiveView application** deployed on its own domain (e.g., `fateswap.com`). It is completely independent from Blockster V2 — separate repo, separate database, separate Fly.io app, separate deployment pipeline. There is **no email login** — users authenticate exclusively by connecting a Solana wallet and signing a challenge message.

```
┌──────────────────────────────────────────────────────────┐
│  Browser (LiveView + JS Hooks)                           │
│  ┌────────────────────┐  ┌─────────────────────────────┐ │
│  │ SolanaWallet Hook  │  │ FateSwapTrade Hook          │ │
│  │ - Phantom/Solflare │  │ - Build VersionedTx         │ │
│  │ - Backpack/Glow    │  │ - Jupiter swap + FateSwap   │ │
│  │ - Sign message auth│  │ - Request wallet signature  │ │
│  │ - Push pubkey      │  │ - Send to Solana RPC        │ │
│  └────────────────────┘  │ - Push result to LiveView    │ │
│                          └─────────────────────────────┘ │
└──────────────────────┬───────────────────────────────────┘
                       │ WebSocket (LiveView)
                       ▼
┌──────────────────────────────────────────────────────────┐
│  FateSwap Phoenix App (Elixir) — fateswap.com            │
│  Own Fly.io app, own PostgreSQL, own domain              │
│                                                          │
│  FateSwap.Auth                                           │
│  - Wallet-only auth (Ed25519 signature verification)     │
│  - SIWS challenge/response flow                          │
│  - Phoenix sessions tied to wallet address               │
│                                                          │
│  FateSwapLive (LiveView)                                 │
│  - UI state, form handling, mode toggle                  │
│  - Push instruction data to JS hooks                     │
│  - Receive tx results, update UI                         │
│                                                          │
│  FateSwap.SeedManager (GenServer)                        │
│  - :crypto.strong_rand_bytes(32) for seeds               │
│  - SHA256 commitment hash                                │
│  - Store encrypted in PostgreSQL (AES-256-GCM)           │
│                                                          │
│  FateSwap.SettlementService                               │
│  - Receive FateOrderPlaced events                        │
│  - Look up stored seeds, call fate-settler               │
│  - Stale order checker (every 5-10s)                     │
│  - Retry with exponential backoff                        │
│                                                          │
│  FateSwap.TokenEligibility (GenServer)                   │
│  - Jupiter verified token list + liquidity checks        │
│  - ETS cache, refresh every 15 min                       │
│                                                          │
│  FateSwap.ChainReader (module)                           │
│  - Raw JSON-RPC via Req to Solana RPC                    │
│  - getAccountInfo + fate-settler RPC delegation          │
│  - ClearingHouse state, PlayerState, FateOrder           │
│                                                          │
│  FateSwap.PriceTracker (GenServer)                       │
│  - Jupiter Price API polling                             │
│  - ETS cache + PubSub broadcast                          │
│                                                          │
│  FateSwap.NFTOwnershipPoller (GenServer)                 │
│  - Polls Arbitrum RPC for High Rollers Transfer events   │
│  - Bridges NFT ownership data to Solana NFTRewarder      │
│  - Same pattern as BlocksterV2.ReferralRewardPoller      │
│  - PostgreSQL for last processed block persistence       │
└──────────────────────┬───────────────────────────────────┘
                       │ HTTP (Req) — SECURED
                       │ (shared secret + Fly.io private network)
                       ▼
┌──────────────────────────────────────────────────────────┐
│  fate-settler (Node.js on Fly.io) — INTERNAL ONLY        │
│  NOT publicly accessible — Fly.io private networking     │
│  Only accepts requests from the Elixir app               │
│                                                          │
│  Security:                                               │
│  - No public port / no public DNS                        │
│  - Shared HMAC secret for request authentication         │
│  - IP allowlisting via Fly.io internal network (.flycast)│
│  - Settler private key NEVER leaves this service         │
│                                                          │
│  - @solana/web3.js + @coral-xyz/anchor                   │
│  - POST /submit-commitment → Solana TX                   │
│  - POST /settle-fate-order → Solana TX                   │
│  - Priority fees, blockhash management                   │
└──────────────────────┬───────────────────────────────────┘
                       │
                       ▼
                Solana Mainnet-Beta
```

### Why This Architecture

**Standalone app**: FateSwap is its own product on its own domain. No coupling to Blockster V2's database, deployment, or runtime. Clean separation of concerns. Can be developed, deployed, and scaled independently.

**Elixir handles**: Orchestration, seed management, UI, real-time updates, business logic, token eligibility, account state reading, wallet authentication.

**Node.js handles**: Solana transaction building/signing (via Anchor SDK), event subscriptions. Runs as an **internal-only** microservice — not publicly accessible.

**Why not pure Elixir for Solana TX?** The only Elixir Solana library (`solana` on hex.pm) is abandoned (last updated 2021, 3,800 total downloads). No Anchor IDL support, no versioned transactions, no WebSocket subscriptions. The Anchor TypeScript SDK is canonical and well-maintained — one line of Anchor TS replaces 100+ lines of manual Borsh encoding in Elixir.

**Why not React/Next.js for frontend?** LiveView gives real-time updates for free, server-side state management, and eliminates an entire separate frontend deployment. The "hard part" (wallet signing, TX building) is ~200-300 lines of JS hook code regardless of framework. The wallet-via-JS-hook pattern is proven in the Blockster codebase.

**Why not Thirdweb for wallets?** Researched and rejected. Thirdweb's Solana support requires React (no vanilla JS API), bundles unnecessary features (email login, smart wallets, EVM chains), requires a Thirdweb API key, and adds ~150-300KB to the bundle. `@wallet-standard/app` is the modern Solana wallet standard — framework-agnostic, ~3KB, no API key, auto-discovers all compliant wallets.

---

## 2. Authentication: Wallet-Only (No Email)

FateSwap has **no email login, no account creation, no passwords**. Users authenticate exclusively by connecting a Solana wallet and signing a challenge message. Identity = wallet address.

### Auth Flow (Sign-In With Solana)

```
1. User clicks "Connect Wallet"
   → JS hook detects available wallets (Phantom, Solflare, Backpack, etc.)
   → User selects wallet, wallet adapter calls .connect()
   → JS hook receives publicKey, pushes to LiveView

2. Server generates challenge nonce
   → Random 32-byte nonce stored in Phoenix session (or short-lived ETS entry)
   → Server pushes challenge message to JS hook via handleEvent

3. User signs challenge message
   → JS hook calls wallet.signMessage(encodedMessage)
   → Wallet prompts user: "Sign in to FateSwap"
   → JS hook pushes {signature, publicKey, message} back to LiveView

4. Server verifies Ed25519 signature
   → :crypto.verify(:eddsa, :none, message, signature, [public_key, :ed25519])
   → If valid: create Phoenix session tied to wallet address
   → If invalid: reject, prompt retry

5. User is authenticated
   → Session stores wallet_address
   → LiveView reads wallet_address from session on mount
   → All subsequent actions are tied to this wallet
```

### Challenge Message Format

```
fateswap.com wants you to sign in with your Solana account:
<base58 wallet address>

Sign in to FateSwap

URI: https://fateswap.com
Nonce: <server-generated-nonce>
Issued At: 2025-05-20T12:00:00Z
```

The nonce prevents replay attacks. The timestamp can enforce a short validity window (e.g., 5 minutes).

### Ed25519 Verification in Elixir

Built into Erlang/OTP — no external library needed:

```elixir
# public_key = Base58-decoded wallet address (32 bytes)
# signature = raw Ed25519 signature from wallet (64 bytes)
:crypto.verify(:eddsa, :none, message, signature, [public_key, :ed25519])
# Returns true | false
```

Only external dependency: a Base58 decoder (`b58` hex package) for converting the wallet address.

### Session Management

- Store `wallet_address` in Phoenix session after verification
- Session expiry: 24 hours (configurable), then require re-signing
- On wallet disconnect (JS hook event): clear server-side session
- On wallet switch: treat as disconnect + new connect (re-auth required)
- No user table needed initially — wallet address IS the identity. A `players` table can be added later for stats/preferences.

### Wallet Connection Strategy (Critical — No React Available)

The official `@solana/wallet-adapter-*` ecosystem is **React-first**. The base classes are technically framework-agnostic TypeScript, but all documentation, lifecycle management, and UI components assume React context providers. Since we use LiveView + JS hooks (no React), we must choose a connection approach carefully.

**Recommended approach — Wallet Standard auto-detection (simplest, smallest bundle):**
- Use `@wallet-standard/app` (`getWallets()`) to auto-discover any Wallet Standard compliant wallet
- Modern wallets (Phantom, Solflare, Backpack) all implement Wallet Standard
- Framework-agnostic, ~8KB total, no wallet-specific adapters needed
- Manual lifecycle: listen for `register`/`unregister` events, call `wallet.features['standard:connect'].connect()` directly

**Alternative — Direct provider APIs (zero dependencies, wallet-specific):**
- Phantom: `window.phantom?.solana` → `.connect()`, `.signMessage()`, `.signTransaction()`
- Solflare: `window.solflare` → same API
- Each wallet exposes its own global provider — no npm packages needed at all
- Downside: must code each wallet's connection separately, handle edge cases per wallet

**NOT recommended for LiveView:**
- `@solana/wallet-adapter-react` / `-react-ui` — requires React, not applicable
- `@thirdweb-dev/*` — requires React, bundles unnecessary features (email login, smart wallets, EVM), requires API key
- Using `@solana/wallet-adapter-base` + individual adapters without React — the adapters work but you must manually wire up all lifecycle management (connect, disconnect, error handling, account changes) that React context normally handles. More code than Wallet Standard approach.

**Implementation plan for SolanaWallet JS Hook:**
```javascript
// 1. On mount: discover wallets via Wallet Standard
import { getWallets } from '@wallet-standard/app';
const { get, on } = getWallets();
const availableWallets = get(); // already registered wallets
on('register', (wallet) => { /* add to list */ });

// 2. User selects wallet → connect
const connectFeature = wallet.features['standard:connect'];
const { accounts } = await connectFeature.connect();
const pubkey = accounts[0].publicKey; // Uint8Array, 32 bytes

// 3. Sign message for auth
const signFeature = wallet.features['solana:signMessage'];
const { signature } = await signFeature.signMessage({ message: encodedChallenge, account: accounts[0] });

// 4. Sign transaction for trades
const signTxFeature = wallet.features['solana:signTransaction'];
const { signedTransaction } = await signTxFeature.signTransaction({ transaction: serializedTx, account: accounts[0] });
```

This approach needs thorough testing with each target wallet (Phantom, Solflare, Backpack) to verify Wallet Standard feature support and edge cases (disconnects, account switches, mobile deeplinks).

---

## 3. Backend: Elixir Services

### 3.1 Seed Manager

Generates, stores, and retrieves provably fair server seeds.

**Seed Generation** (identical to existing BuxBoosterOnchain):
```elixir
server_seed = :crypto.strong_rand_bytes(32)
commitment_hash = :crypto.hash(:sha256, server_seed)  # 32 bytes
```

**Storage**: PostgreSQL with AES-256-GCM encryption (not Mnesia — seeds are security-critical and need at-rest encryption + durability guarantees).

**Flow**:
1. Player requests game → generate seed + hash
2. Store encrypted seed in `fate_orders` table (status: `:generated`)
3. Call fate-settler `/submit-commitment` → Solana TX
4. Update status to `:committed`
5. Player places fate order (client-side)
6. Server detects order placed (client push or GenServer poller)
7. Server computes outcome locally: `SHA256(server_seed || player_pubkey || nonce)` → filled/not-filled
8. Call fate-settler `/settle-fate-order` with `{serverSeed, orderPda, player, nonce}` — fate-settler computes outcome and submits `filled: bool` + `server_seed` on-chain; program verifies `SHA256(server_seed) == commitment_hash` (hybrid verification)
9. Update status to `:settled`, store revealed seed

### 3.2 Settlement Service

GenServer that detects placed orders and triggers settlement. The Elixir app sends the server seed and order details to fate-settler, which computes the outcome (`filled: bool`) and submits both to chain. The on-chain program verifies `SHA256(server_seed) == commitment_hash` (prevents seed substitution) but trusts the settler's `filled` bool (outcome verification is off-chain). The server seed is revealed in the on-chain event for anyone to independently verify the outcome was fair.

**Order detection** (two-layered):

1. **Primary — Client push (instant)**: The JS hook knows when the `place_fate_order` TX confirms (it submitted it). It pushes `"order_placed"` to the LiveView immediately. The server triggers settlement with zero latency. Covers ~99% of cases.

2. **Safety net — GenServer poller (catches edge cases)**: A GenServer polls every 5-10 seconds for orders that were missed (client disconnected, browser crashed, network blip). Queries PostgreSQL for orders with status `:committed` older than 10 seconds, checks on-chain if the FateOrder PDA exists via `getAccountInfo`, and triggers settlement if found.

No WebSocket subscriptions (`logsSubscribe`) — they're unreliable (connections drop, events missed during reconnection, no delivery guarantees). The client-push + GenServer-poller combination is simpler and more robust.

**Pre-computed outcome determines settlement strategy**:

The fate-settler has `server_seed`, `player_pubkey`, `nonce`, `multiplier_bps`, and `fate_fee_bps`. It computes `SHA256(server_seed || player_pubkey || nonce)` to determine filled/not-filled. The on-chain program verifies `SHA256(server_seed) == commitment_hash` (seed authenticity) but trusts the settler's `filled: bool` (outcome). The server_seed is revealed in the on-chain event for anyone to verify the outcome off-chain.

| Outcome | Mode | Settlement Strategy |
|---------|------|---------------------|
| Not Filled | Either | Server-only TX: `settle_fate_order` (settler signs alone) |
| Filled | Sell-side | Server-only TX: `settle_fate_order` → player receives SOL (done) |
| Filled | Buy-side, player online | **1 TX partial-sign**: `settle_fate_order` + Jupiter swap → player receives tokens directly |
| Filled | Buy-side, player offline | Fallback server-only TX: `settle_fate_order` → player receives SOL, swaps manually later |

**Buy-side fill — 1 TX via partial signing**:
1. Server pre-computes outcome → Filled
2. Server fetches Jupiter quote for payout SOL → target token
3. Server builds combined TX: `settle_fate_order` (settler signs) + Jupiter swap (player signs)
4. Server partially signs with settler keypair via fate-settler
5. Server pushes partially-signed TX to JS hook via LiveView
6. Phantom pops up — player approves and co-signs
7. JS hook submits fully-signed TX → player ends up with tokens in 1 atomic TX
8. Fallback: if player doesn't respond within 30s, settle without swap (server-only TX)

This works because within a single Solana TX, state changes from instruction N are visible to instruction N+1 — when `settle_fate_order` credits SOL to the player, the subsequent Jupiter instructions can spend it.

**Settlement loop**:
- Exponential backoff retries on failure (500ms, 1s, 2s, 4s — max 3)
- Stop retrying at 4.5 minutes (player can reclaim after 5-min timeout)
- Idempotent: Solana program rejects duplicate settlements

### 3.3 Token Eligibility

GenServer polling Jupiter APIs every 15 minutes, storing results in ETS.

**Jupiter endpoints**:
- `GET https://api.jup.ag/tokens/v2/tag?query=verified` — verified token list
- `GET https://api.jup.ag/swap/v1/quote?inputMint=TOKEN&outputMint=SOL&amount=AMOUNT` — liquidity + price impact check

**Eligibility criteria** (off-chain only, not enforced on-chain):
- Must be on Jupiter's verified token list
- Must have >$50K DEX liquidity
- Must have <1% price impact at $50K trade size

**Rate limit**: Jupiter API allows ~300-600 req/min with API key. ~500 tokens × 1 quote each = ~33 req/min for full scan. Use `Task.async_stream(tokens, &check_eligibility/1, max_concurrency: 10)` to complete in ~50 seconds.

### 3.4 Chain Reader

Direct Solana JSON-RPC via `Req` (no Node.js needed for reads).

**Methods needed**:
- `getAccountInfo` → read ClearingHouse state, PlayerState, FateOrder PDAs
- `getLatestBlockhash` → for timeout calculations
- `getSignaturesForAddress` → polling fallback for event detection

**Account decoding**: Base64 → verify 8-byte Anchor discriminator (first 8 bytes of `SHA256("account:<AccountName>")`) → Borsh decode remaining bytes.

**Borsh decoding options** (Borsh is Solana's binary serialization format — all account state uses it):
- **`borsh_serializer` hex package** (~1.0): Exists but essentially unmaintained (zero recent downloads, last updated 2022). Risky for security-critical account state decoding.
- **Delegate to fate-settler** (recommended initially): Add `GET /account-state/:pubkey` endpoints to the Node.js service. Anchor provides automatic Borsh decoding — one line: `program.account.clearingHouseState.fetch(pubkey)`. Simplest and most reliable.
- **Manual Borsh decoder in Elixir** (~50-100 lines): Borsh is a simple sequential format (u8, u16, u32, u64, i64, i128, bool, Pubkey=32 bytes, etc.). Writing a decoder for the known FateSwap account schemas is straightforward and eliminates the third-party dependency.

**Recommendation**: Use fate-settler for account reads initially (accounts are read infrequently — mostly for settlement polling and LP stats). If latency matters, write a minimal Borsh decoder in Elixir for the 3 account types we need (ClearingHouseState, PlayerState, FateOrder).

**PDA derivation**: Used to compute account addresses for `getAccountInfo` queries without calling the Node.js service.

**Why PDA derivation is needed**: On Solana, account addresses for PDAs (like a player's `PlayerState` or `FateOrder`) are deterministically derived from seeds + program ID. To read a player's state via `getAccountInfo`, the Elixir app must know the account address. Without PDA derivation, every account lookup would require a round-trip to the Node.js service.

**Complexity warning**: PDA derivation is NOT trivially "SHA256 + find bump." The algorithm is:
1. Compute `SHA256(seeds || program_id || bump || "ProgramDerivedAddress")`
2. Check if the resulting 32 bytes are a valid Ed25519 curve point (must be OFF the curve for PDAs)
3. If ON the curve, decrement bump and retry (step 2 requires Ed25519 point decompression — modular arithmetic over the curve equation)

Erlang/OTP's `:crypto` module does NOT expose a raw "is this point on the Ed25519 curve?" function. Options:
- **Delegate to fate-settler** (simplest): Add a `GET /derive-pda` endpoint that uses `@solana/web3.js` `PublicKey.findProgramAddressSync()`. Cache results in ETS since PDAs are deterministic.
- **NIF binding**: Use a Rust NIF via `rustler` to call `solana_program::pubkey::Pubkey::find_program_address()` directly. ~50 lines of Rust, very fast.
- **Pure Elixir implementation**: Implement Ed25519 point decompression (~100-200 lines of modular arithmetic). Non-trivial but doable.

**Recommendation**: Delegate to fate-settler initially with ETS caching. PDA addresses for a given player never change, so they only need to be computed once per player. Migrate to NIF if the round-trip latency becomes an issue at scale.

### 3.5 Price Tracker

Same pattern as existing `PriceTracker` (CoinGecko). Replace with Jupiter Price API.

- `GET https://api.jup.ag/price/v2?ids=So11111111111111111111111111111111111111112,...` (Jupiter uses mint addresses, not symbols)
- Poll every 60 seconds
- Store in ETS, broadcast via PubSub
- LiveView subscribes for real-time USD value display

### 3.6 NFT Ownership Poller

GenServer that bridges High Rollers NFT ownership data from Arbitrum to the Solana NFTRewarder program. Direct copy of `BlocksterV2.ReferralRewardPoller` pattern (which was modeled on high-rollers-elixir's `RogueRewardPoller`).

**Pattern** (identical to `ReferralRewardPoller`):
- Registered globally via `GlobalSingleton` (single instance across cluster)
- Polls Arbitrum RPC `eth_getLogs` for `Transfer(from, to, tokenId)` events
- Contract: `0x7176d2edd83aD037bd94b7eE717bd9F661F560DD` (High Rollers NFT on Arbitrum)
- Poll interval: ~5 seconds (Arbitrum ~250ms blocks, no need for 1s)
- PostgreSQL for last processed block persistence
- Backfills from deploy block on first run (chunks of 10,000 blocks)
- Non-blocking with overlap prevention (`polling: true` guard)

**On Transfer event detected**:
1. Parse `Transfer(from, to, tokenId)` — extract `token_id` and new owner address
2. Look up new owner's registered Solana wallet from PostgreSQL `nft_wallet_mappings` table
3. If Solana wallet found: call fate-settler `POST /nft-update-ownership` → builds admin-signed `update_ownership` TX on Solana NFTRewarder
4. If no Solana wallet registered: queue the transfer, apply when owner registers their wallet on `/nft` page

**Initial bootstrap** (one-time):
- On first deploy, backfill all 2,341 NFTs via `register_nft` calls
- Batch via fate-settler `POST /nft-batch-register` to minimize TX costs

**Database**:
```
nft_wallet_mappings:
  - arbitrum_address (string, indexed)
  - solana_wallet (string)
  - created_at (timestamp)

nft_ownership_cache:
  - token_id (integer, PK)
  - nft_type (integer, 0-7)
  - arbitrum_owner (string)
  - solana_wallet (string, nullable)
  - synced_to_solana (boolean)
  - last_transfer_block (integer)
```

---

## 4. Node.js Microservice: fate-settler (Secured)

The fate-settler is an **internal-only** Node.js service that holds the settler wallet private key and builds/signs Solana transactions. It is the most security-critical component — if compromised, an attacker could drain the ClearingHouse vault by settling orders with manipulated seeds.

### Security Architecture

```
                    ┌─────────────────────────┐
                    │      Public Internet     │
                    │                          │
                    │   ✗ NO public access     │
                    │   ✗ NO public DNS        │
                    │   ✗ NO public port       │
                    └─────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│  Fly.io Private Network (.internal / .flycast)          │
│                                                         │
│  ┌─────────────────────┐     ┌────────────────────────┐ │
│  │ FateSwap Elixir App │────▶│ fate-settler (Node.js) │ │
│  │ (public-facing)     │     │ (internal only)        │ │
│  │                     │ HMAC│                        │ │
│  │ Authenticates every │ +   │ Validates HMAC sig     │ │
│  │ request with HMAC   │ TLS │ on every request       │ │
│  └─────────────────────┘     └────────────────────────┘ │
│                                                         │
│  Communication via: fate-settler.internal:3000           │
│  NOT accessible from outside Fly.io private network     │
└─────────────────────────────────────────────────────────┘
```

**Security layers (defense in depth)**:

1. **No public exposure**: fate-settler has no public IP, no public DNS, no `[[services]]` section in `fly.toml`. Only accessible via Fly.io's `.internal` private DNS (e.g., `fate-settler.internal:3000`).

2. **HMAC request authentication**: Every request from the Elixir app includes an HMAC-SHA256 signature computed over the request body + timestamp using a shared secret. The fate-settler verifies this signature before processing. Prevents any unauthorized caller — even from within the Fly.io network.

3. **Timestamp validation**: HMAC includes a timestamp. Requests older than 30 seconds are rejected (prevents replay attacks).

4. **Settler private key isolation**: The Ed25519 settler keypair NEVER leaves the fate-settler service. It's loaded from a Fly.io secret (`SETTLER_PRIVATE_KEY`) and exists only in memory. The Elixir app never sees or handles this key.

5. **Audit logging**: Every transaction submission is logged with the request origin, parameters, and Solana TX signature for forensic analysis.

### HMAC Authentication Flow

```
Elixir app:
  timestamp = System.system_time(:second) |> to_string()
  body = Jason.encode!(payload)
  signature = :crypto.mac(:hmac, :sha256, shared_secret, timestamp <> "." <> body)
  headers = [
    {"x-hmac-signature", Base.encode16(signature)},
    {"x-timestamp", timestamp}
  ]
  Req.post("http://fate-settler.internal:3000/settle-fate-order", body: body, headers: headers)

fate-settler (Node.js):
  const timestamp = req.headers['x-timestamp']
  if (Date.now()/1000 - parseInt(timestamp) > 30) reject("expired")
  const expectedSig = crypto.createHmac('sha256', SHARED_SECRET)
    .update(timestamp + '.' + req.body).digest('hex')
  // IMPORTANT: Use crypto.timingSafeEqual() for constant-time comparison to prevent timing attacks
  if (!crypto.timingSafeEqual(Buffer.from(expectedSig, 'hex'), Buffer.from(req.headers['x-hmac-signature'], 'hex'))) reject("unauthorized")
```

### Endpoints (Internal Only)

```
POST /submit-commitment
  Body: { commitmentHash: [u8;32], player: "base58", nonce: u64 }
  Auth: HMAC-SHA256 signature required
  Returns: { success: true, txSignature: "base58" }

POST /settle-fate-order
  Body: { serverSeed: [u8;32], orderPda: "base58", player: "base58", nonce: u64 }
  Auth: HMAC-SHA256 signature required
  Returns: { success: true, txSignature: "base58", filled: bool, payout: u64 }
  Note: fate-settler computes outcome (filled: bool) from serverSeed + player + nonce + on-chain order data,
        then submits both filled + serverSeed to the on-chain settle_fate_order instruction

POST /build-settle-and-swap
  Body: { serverSeed: [u8;32], orderPda: "base58", player: "base58", nonce: u64,
          outputMint: "base58", slippageBps: u16 }
  Auth: HMAC-SHA256 signature required
  Returns: { partiallySignedTx: "base64", filled: true }
  Note: For buy-side fills — builds settle + Jupiter swap TX, partially signs with
        settler keypair. Returns to Elixir app, which pushes to client for player co-sign.

GET /clearing-house-state
  Auth: HMAC-SHA256 signature required
  Returns: { vault_balance, total_liability, unsettled_count, lp_supply, ... }

GET /player-state/:pubkey
  Auth: HMAC-SHA256 signature required
  Returns: { nonce, has_active_order, active_order, total_orders, ... }

POST /nft-register
  Body: { wallet: "base58", points: u32 }
  Auth: HMAC-SHA256 signature required
  Returns: { success: true, txSignature: "base58" }
  Note: Admin updates a holder's aggregate points (per-wallet model, called by NFTOwnershipPoller)

POST /nft-update-ownership
  Body: { tokenId: u32, newOwner: "base58" }
  Auth: HMAC-SHA256 signature required
  Returns: { success: true, txSignature: "base58" }
  Note: Called by NFTOwnershipPoller when an NFT transfers on Arbitrum

POST /nft-batch-register
  Body: { holders: [{ wallet: "base58", points: u32 }, ...] }
  Auth: HMAC-SHA256 signature required
  Returns: { success: true, txSignatures: ["base58", ...] }
  Note: Initial bootstrap — register all holders with their aggregate points in batches
```

No event subscription / WebSocket monitoring. The fate-settler is a pure TX builder/signer. Order detection is handled by the Elixir app (client push + GenServer poller). NFT bridge operations are initiated by the Elixir app's `NFTOwnershipPoller` GenServer.

### Keypair Management

- Settler wallet private key stored as Fly.io secret (`SETTLER_PRIVATE_KEY`)
- Loaded on startup into memory only — never written to disk, never logged
- The Elixir app has NO access to this key — it only sends parameters and receives TX signatures
- If the fate-settler is compromised, the blast radius is limited to the settler wallet's authority (submit commitments + settle orders). The vault SOL is protected by the on-chain program logic.

### Estimated Gas Costs (SOL ~$178, moderate congestion)

**Server-paid transactions:**

| TX | Compute Units | Cost (SOL) | Cost (USD) |
|---|---|---|---|
| `submit_commitment` | ~15,000 | ~0.000005 | ~$0.001 |
| `settle_fate_order` (server-only) | ~15,000 | ~0.000005 | ~$0.001 |

**Player-paid transactions:**

| TX | Compute Units | Cost (SOL) | Cost (USD) |
|---|---|---|---|
| Sell-side: Jupiter swap + `place_fate_order` | ~425,000 | ~0.00001 | ~$0.002 |
| Buy-side: `place_fate_order` (SOL only) | ~25,000 | ~0.000005 | ~$0.001 |
| Buy-side fill: `settle + Jupiter swap` (co-signed 1 TX) | ~315,000 | ~0.000008 | ~$0.002 |
| `reclaim_expired_order` (timeout refund) | ~10,000 | ~0.000005 | ~$0.001 |
| LP `deposit_sol` | ~35,000 | ~0.000005 | ~$0.001 |
| LP `withdraw_sol` | ~35,000 | ~0.000005 | ~$0.001 |

**Full trade cost summary:**

| Scenario | Player Pays | Server Pays | Total |
|---|---|---|---|
| Sell-side (any outcome) | ~$0.002 | ~$0.002 | **~$0.004** |
| Buy-side, not filled | ~$0.001 | ~$0.002 | **~$0.003** |
| Buy-side, filled (1 TX with swap) | ~$0.003 | ~$0.001 | **~$0.004** |

**Server operating cost at scale:**

| Daily Bets | Server Gas/Day | Server Gas/Month |
|---|---|---|
| 500 | ~$1.00 | ~$30 |
| 2,000 | ~$4.00 | ~$120 |
| 10,000 | ~$20.00 | ~$600 |

Negligible relative to 1.5% fate fee revenue at those volumes.

---

## 5. Frontend: LiveView + JS Hooks

### 5.1 Wallet Connection + Auth (SolanaWallet Hook)

**Uses `@wallet-standard/app` directly — no React, no Thirdweb.** Modern Solana wallets (Phantom, Solflare, Backpack) implement the **Wallet Standard** protocol. Wallet Standard auto-detection provides a clean vanilla JS API:

```javascript
// Each adapter: .connect(), .disconnect(), .signTransaction(), .signMessage(), .publicKey
// Each emits 'connect', 'disconnect', 'error' events
// Or use Wallet Standard auto-detection for all compliant wallets
```

**Hook responsibilities**:
- On mount: detect available wallets via Wallet Standard auto-detection, push wallet list to server
- On connect: `wallet.connect()` → push pubkey to LiveView via `pushEvent("wallet_connected", {pubkey})`
- On auth challenge: receive challenge from server via `handleEvent`, call `wallet.signMessage(challenge)`, push signature back
- On disconnect: `pushEvent("wallet_disconnected")` → server clears session
- On wallet switch: treat as disconnect + reconnect (full re-auth)
- Expose wallet reference on `window.__solanaWallet` for the trade hook

### 5.2 Trade Transaction (FateSwapTrade Hook)

**The sell-side flow** (token → SOL → fate order):

1. User clicks "Place Fate Order" → LiveView `handle_event`
2. Server validates inputs, calls Jupiter Quote API (Elixir-side via Req)
3. Server calls Jupiter Swap Instructions API
4. Server pushes `"build_and_sign_tx"` event to JS hook with serialized instruction data
5. JS hook deserializes Jupiter instructions
6. JS hook builds FateSwap `place_fate_order` instruction via Anchor client
7. JS hook constructs `VersionedTransaction` with Address Lookup Tables
8. JS hook calls `wallet.signTransaction(tx)`
9. JS hook sends raw tx via `connection.sendRawTransaction()`
10. JS hook pushes `{signature, status}` back to LiveView
11. Server starts confirmation polling / receives Helius webhook

**Why Jupiter Quote API is called server-side**: Rate limiting control, caching, hiding API keys, server-side validation of swap parameters.

**Address Lookup Tables**: Essential for fitting Jupiter's 20+ accounts into the 1232-byte TX limit. Jupiter's `/swap-instructions` response includes `addressLookupTableAddresses` which must be fetched and passed to `compileToV0Message()`.

### 5.3 Buy-Side Flow

No Jupiter swap needed for bet placement — player deposits raw SOL:

1. Server generates seed, submits commitment
2. JS hook builds `place_fate_order` instruction (SOL only, no Jupiter)
3. Player approves in wallet, TX submitted

**On settlement (server pre-computes outcome):**

- **Not Filled**: Server submits settle TX alone. Player sees "Not Filled". Done.
- **Filled (player online)**: Server builds combined `settle + Jupiter swap` TX via fate-settler's `/build-settle-and-swap`, partially signs with settler key, pushes to JS hook. Phantom pops up — player co-signs. **1 atomic TX** — player ends up with tokens directly. No extra confirmation step.
- **Filled (player offline fallback)**: After 30s with no co-sign, server submits settle-only TX. Player receives SOL, can swap manually next visit.

### 5.4 Anchor Client in Browser

Use `@coral-xyz/anchor` to generate instruction data from the FateSwap IDL:

```javascript
const ix = await program.methods
  .placeFateOrder(nonce, multiplierBps, tokenMint, tokenAmount)
  .accounts({ player, state, vault, playerState, fateOrder, systemProgram })
  .instruction();  // Returns TransactionInstruction (doesn't send)
```

The `.instruction()` method returns a `TransactionInstruction` that composes with Jupiter instructions into a single `VersionedTransaction`.

**IDL management**: Generated from `anchor build` → `target/idl/fate_swap.json`. Include in JS assets at build time.

---

## 6. UI Components & Design

### Component Architecture

| Component | Implementation | Why |
|-----------|---------------|-----|
| Swap Card Layout | Pure LiveView | Standard form, no complex interaction |
| Token Selector Modal | LiveView component | Search/filter is server-side strength |
| **Fate Slider** | **JS Hook** | Must be smooth, can't round-trip per pixel |
| **Probability Ring** | **JS Hook** (synced with slider) | Must animate in lockstep with slider |
| Mode Toggle | Pure LiveView (`phx-click`) | Simple binary state |
| Payout Card | Pure LiveView | Read-only computed display |
| CTA Button | Pure LiveView | Dynamic text, standard button |
| Result Overlay | LiveView + CSS animations | Server decides outcome, CSS animates |
| Live Feed | LiveView Streams + JS hook | Streams for efficiency, hook for auto-scroll |

### JS Hooks Needed (3 total for UI)

1. **FateSlider** — slider input (210 discrete positions), track gradient (green→yellow→red), multiplier label, coordinates with probability ring
2. **ProbabilityRing** — receives updates from slider, animates SVG arc (could merge into FateSlider)
3. **FeedScroll** — auto-scrolls live feed, pauses on hover

### Design System

```
Dark theme foundation:
  bg-gray-950    — page background
  bg-gray-900    — card backgrounds
  bg-gray-800    — input fields, secondary surfaces
  bg-gray-700    — hover states, active toggles
  border-gray-800 — subtle borders
  text-white     — primary text
  text-gray-400  — secondary text
```

**Design principles** (from concept doc):
- NO casino imagery — no dice, cards, slot machines, neon
- Dark, minimal UI following Jupiter/Drift/Tensor aesthetic
- The slider IS the product — largest, most colorful element on the page
- Results feel like order fills: "Order Filled — You received 1.04 SOL"
- Numbers use `font-mono` / `tabular-nums` for proper alignment

### Fate Slider Implementation

- HTML `<input type="range" min="0" max="209" step="1">` — 210 discrete positions mapping to allowed multiplier values
- JS lookup array `MULTIPLIER_STEPS[index]` maps slider position → BPS value (built at module load from tier definitions)
- 6 tiers: 1.01–1.99 by 0.01 (99), 2.00–2.98 by 0.02 (50), 3.00–3.95 by 0.05 (20), 4.0–5.9 by 0.1 (20), 6.0–9.8 by 0.2 (20), 10.0 (1)
- Track gradient: `linear-gradient(to right, #22c55e 0%, #eab308 50%, #ef4444 100%)`
- JS hook updates label + probability ring on every `input` event (client-side, no server round-trip)
- Multiplier label formatted per tier precision: 2 decimals for tiers 1–3, 1 decimal for tiers 4–6
- Push final multiplier_bps to server on `change` event or debounced after 150ms
- Custom CSS in `assets/css/app.css` for slider track/thumb (existing pattern in codebase)

### Probability Ring Implementation

- SVG with two `<circle>` elements (background track + filled arc)
- `stroke-dasharray` = circumference, `stroke-dashoffset` = circumference × (1 - fillChance)
- Color matches slider position via HSL interpolation: `hsl(${120 - (pct * 120)}, 80%, 50%)`
- Animated by the FateSlider JS hook directly (no server round-trip)

### Live Feed

- Phoenix PubSub broadcast on every order settlement
- LiveView Streams (`socket |> stream(:trades, initial, dom_id: &"trade-#{&1.id}")`) — note: `limit:` option should be set here during stream initialization
- `stream_insert(socket, :trades, trade, at: 0)` for new items
- FeedScroll JS hook for auto-scroll behavior (pause on hover)

### Mode Toggle ("Sell High" / "Buy Low")

- Pure LiveView, `phx-click="toggle_mode"` with `@mode` assign (`:sell_high` / `:buy_low`)
- Active tab: `bg-gray-700 text-white rounded-lg`
- Inactive: `text-gray-400 hover:text-gray-300`
- Changes framing of entire card (labels, CTA text, input/output positions)

### Result Overlay

- `fixed inset-0 z-50 bg-black/80 backdrop-blur-md` overlay
- CSS `@keyframes fadeInScale` for entrance animation
- Success: green accent, "Order Filled — You received X SOL"
- Failure: neutral tone, "Not Filled — Fate rejected your order" (not dramatic)
- Provably fair verification link

---

## 7. Reusable Patterns from Blockster (Reference Only)

These patterns are from the Blockster V2 codebase and serve as **architectural inspiration** — FateSwap will reimplement them in its own repo, not import them directly.

### Pattern Reference

| Pattern | Blockster Source | FateSwap Adaptation |
|---------|-----------------|---------------------|
| Commit-reveal flow | `provably_fair.ex` + `bux_booster_onchain.ex` | Same CSPRNG + SHA256, change result mapping from coin flip to fill chance |
| Background settler | `bux_booster_bet_settler.ex` (120 lines) | Same poll-and-settle GenServer pattern, replace EVM calls with Solana |
| Price tracker | `price_tracker.ex` (295 lines) | Replace CoinGecko with Jupiter Price API |
| LiveView async pattern | `bux_booster_live.ex` | Extract values BEFORE `start_async`, same error/retry handling |
| JS hook → LiveView flow | `bux_booster_onchain.js` (465 lines) | Replace EVM wallet with Solana wallet-adapter/Anchor |
| PubSub real-time updates | Used throughout | Same topic pattern: `"fateswap:feed"`, `"fateswap:order:#{wallet}"` |
| HTTP timeout patterns | `bux_minter.ex` | 60s receive_timeout, 5s connect_timeout |

### Key File Paths

- **Provably Fair**: `lib/blockster_v2/provably_fair.ex`
- **On-Chain Game Logic**: `lib/blockster_v2/bux_booster_onchain.ex` (1,852 lines)
- **Settlement Worker**: `lib/blockster_v2/bux_booster_bet_settler.ex` (120 lines)
- **LiveView Game UI**: `lib/blockster_v2_web/live/bux_booster_live.ex` (~1,500 lines)
- **JS Hooks**: `assets/js/bux_booster_onchain.js` (465 lines)
- **Global Singleton**: `lib/blockster_v2/global_singleton.ex` (123 lines)
- **Price Tracker**: `lib/blockster_v2/price_tracker.ex` (295 lines)
- **Mnesia Init**: `lib/blockster_v2/mnesia_initializer.ex` (2,000+ lines)
- **Application Supervisor**: `lib/blockster_v2/application.ex` (130 lines)
- **BUX Minter Client**: `lib/blockster_v2/bux_minter.ex` (350+ lines)

### Critical Learnings (from BuxBooster production)

1. **Never expose server_seed before settlement** — commitment hash only until on-chain settle confirmed
2. **Server controls nonces** — prevents RPC timing attacks
3. **Always check idempotency** — order may already be settled on-chain before retry
4. **Extract values BEFORE start_async** — never access `socket.assigns` inside async closure
5. **Fire-and-forget TX pattern** — JS hook sends tx, immediately notifies LiveView; server polls for confirmation in background
6. **Approval caching** — localStorage for infinite token approvals (SPL token equivalent: delegate authority)

---

## 8. NPM Dependencies

### Required

**Important**: Must use `@solana/web3.js` v1.x (not v2.0/`@solana/kit`). Anchor (`@coral-xyz/anchor`) requires v1.x. The v2 rewrite has a completely different API and is not yet Anchor-compatible.

| Package | Purpose | Bundle Size |
|---------|---------|-------------|
| `@solana/web3.js` ^1.95 | Core Solana SDK (Connection, Transaction, PublicKey) | ~400KB |
| `@wallet-standard/app` | Wallet Standard auto-discovery (framework-agnostic) | ~3KB |
| `@coral-xyz/anchor` ^0.31 | Anchor client for FateSwap program IDL | ~300KB |
| `@solana/spl-token` | SPL token instructions (ATA creation for LP) | ~100KB |
| `buffer` | Buffer polyfill for browser (required by web3.js v1.x) | ~50KB |

**Total estimated**: ~850KB pre-minification, ~300-400KB gzipped.

**No individual wallet adapters needed**: Using Wallet Standard (`@wallet-standard/app`) auto-discovers Phantom, Solflare, Backpack, and any other compliant wallet without importing wallet-specific packages.

### Buffer Polyfill (Required for web3.js v1.x)

Must run before any Solana imports:
```javascript
import { Buffer } from 'buffer';
window.Buffer = Buffer;
```

When Anchor supports `@solana/kit` (v2), the Buffer polyfill and ~400KB of web3.js will no longer be needed.

### Code Splitting (Required for Bundle Size)

Phoenix's default esbuild configuration uses `--format=iife`, which does NOT support code splitting. To use dynamic `import()` for lazy-loading Solana JS:

1. Switch esbuild config to `--format=esm --splitting --chunk-names=chunks/[name]-[hash]`
2. Change the `<script>` tag in root layout to `type="module"`
3. Dynamic import in the JS hook: `const { Connection } = await import('@solana/web3.js')`

This ensures Solana JS (~400KB gzipped) is only loaded when the user visits the FateSwap page, not on every page load.

### NOT Needed

- `@solana/wallet-adapter-base` / `-phantom` / `-solflare` / `-backpack` — Not needed when using Wallet Standard (`@wallet-standard/app`) for auto-detection. The adapter packages are designed for React context wrappers.
- `@solana/wallet-adapter-react` / `-react-ui` — React-specific, not applicable to LiveView
- `@thirdweb-dev/*` — Requires React, bundles unnecessary features (email login, smart wallets, EVM), requires API key. Rejected after research.
- `@jup-ag/api` — call Jupiter REST API from Elixir server-side instead
- `@jup-ag/terminal` — React-only widget, not applicable to LiveView

---

## 9. Elixir Dependencies

### New Dependencies

Note: `borsh_serializer` is NOT included — it is essentially unmaintained. Account state decoding will initially be delegated to the fate-settler Node.js service (Anchor provides free Borsh decoding). If direct Elixir decoding is needed later, we will write a minimal custom decoder for the 3 FateSwap account types (~50-100 lines).

### Standard Phoenix Dependencies (included via `mix phx.new`)

- `phoenix` / `phoenix_live_view` — core framework
- `ecto_sql` / `postgrex` — PostgreSQL via Ecto
- `phoenix_pubsub` — real-time broadcasting
- `jason` — JSON encoding/decoding
- `bandit` — HTTP server (Phoenix 1.7+ default)
- `esbuild` / `tailwind` — asset pipeline

### Additional Dependencies

| Package | Purpose |
|---------|---------|
| `req` ~> 0.5 | HTTP client for Solana RPC, Jupiter API, fate-settler calls |
| `b58` ~> 1.0 | Base58 encoding/decoding for Solana addresses and wallet auth |
| `oban` ~> 2.20 | Job queue for settlement retries — survives restarts, configurable backoff, deduplication |
| `resvg` ~> 0.4 | SVG to PNG rendering for share card generation |
| `oauther` ~> 1.3 | OAuth 1.0a signing for X API integration |

### Built into Erlang/OTP (no dependency needed)

- `:crypto` — CSPRNG (`strong_rand_bytes`), SHA256, AES-256-GCM encryption, Ed25519 signature verification, HMAC

---

## 10. Open Questions

1. **Domain**: What domain will FateSwap live on? (e.g., `fateswap.com`, `fate.exchange`, etc.)

2. ~~**PostgreSQL vs. Mnesia?**~~ **RESOLVED**: PostgreSQL for everything. Standalone app, no distributed state needed, keep it simple.

3. ~~**Helius vs. self-managed WebSocket?**~~ **RESOLVED**: No WebSocket subscriptions (`logsSubscribe`). Use client push (primary) + GenServer/Oban poller (safety net). Simpler and more robust than managing reconnection logic.

4. ~~**2-TX vs. 3-TX?**~~ **RESOLVED**: Start with 3 TXs (commit, place, settle). Optimize to 2 later.

5. **Token eligibility — curated list or full scan?** Scanning all ~500 verified Jupiter tokens every 15 min works, but a curated list of ~50-100 popular memecoins would be faster and simpler. Can expand later.

6. ~~**Multi-node or single node?**~~ **RESOLVED**: Single node initially. No libcluster/Mnesia needed. Add horizontal scaling later if traffic justifies it.

---

## 11. Referral System (Two-Tier)

The referral system is enforced **on-chain** in the Solana program (see Solana architecture doc Section 9). FateSwap uses a **two-tier referral model**: tier-1 referrer earns 0.2% and tier-2 referrer (referrer's own referrer) earns 0.1% — both deducted only on losing orders.

### Revenue Split on Losses (1.0% total)

| Recipient | BPS | % of Wager |
|---|---|---|
| Tier-1 referrer | 20 | 0.2% |
| Tier-2 referrer | 10 | 0.1% |
| NFT holders (via NFTRewarder) | 30 | 0.3% |
| Platform/team wallet | 30 | 0.3% |
| Bonuses wallet | 10 | 0.1% |
| **Total** | **100** | **1.0%** |
| LP pool (house keeps) | 9900 | 99.0% |

### Backend: Referral Tracking

- **`FateSwap.Referrals` context module**: Tracks referral links, maps three-word codes to wallet addresses
- **`FateSwap.Referrals.CodeGenerator`**: Generates codes in `adjective-participle-animal` format from curated crypto/degen word lists (40 × 40 × 171 = 273k combinations). See `docs/fateswap_referral_words.md` for word lists.
- **Database**: `referral_links` table — `id`, `referrer_wallet`, `code` (unique, three-word format e.g. `greedy-hodling-otter`), `created_at`
- **On player's first bet**: If `player_state.referrer == Pubkey::default()` and a referral code is present in the session/URL, call `set_referrer` instruction via fate-settler before the first bet
  - `set_referrer` automatically resolves the tier-2 referrer by reading the referrer's `PlayerState.referrer`
  - Both tier-1 and tier-2 are stored on the player's `PlayerState` forever (one-time set)
- **Referral rewards**: Paid on-chain automatically during `settle_fate_order` (on losses only)
  - Tier-1: `referral_bps = 20` (0.2% of wager)
  - Tier-2: `tier2_referral_bps = 10` (0.1% of wager)
  - Both are non-blocking — failure doesn't revert settlement
- **Stats endpoint**: Referrers can view their direct referrals, tier-2 referrals, and combined earnings

### How Tier-2 Works

```
Alice refers Bob → Bob's PlayerState.referrer = Alice
                 → Bob's PlayerState.tier2_referrer = Alice's referrer (if any)

Bob refers Carol → Carol's PlayerState.referrer = Bob
                 → Carol's PlayerState.tier2_referrer = Alice (Bob's referrer)

Carol loses a bet:
  → Bob gets 0.2% (tier-1)
  → Alice gets 0.1% (tier-2, because she referred Bob who referred Carol)
```

The tier-2 referrer is resolved **once** during `set_referrer` (not computed at settlement time). This means:
- Zero additional account reads during settlement (both addresses are on PlayerState, which is already loaded)
- One additional account read during `set_referrer` (read referrer's PlayerState to get their referrer) — but this is a one-time operation per player

### Frontend: Referral UI

- **Referral link generation**: Authenticated users get a shareable link: `fateswap.com/?ref=greedy-hodling-otter` (three-word code auto-generated on first visit to `/referrals` or first share)
- **Referral landing**: When a user visits with `?ref=`, validate three-word format (`/^[a-z]+-[a-z]+-[a-z]+$/`), store in `localStorage` and Phoenix session. On first bet, resolve code → wallet, call `set_referrer` on-chain.
- **Referrer dashboard** (page at `/referrals`):

```
┌──────────────────────────────────────────────────────────┐
│  Your Referral Link                                      │
│  ┌──────────────────────────────────────┐ [Copy]         │
│  │ fateswap.com/?ref=greedy-hodling-otter │                │
│  └──────────────────────────────────────┘                │
│                                                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   │
│  │  Direct       │  │  Tier-2      │  │  Total       │   │
│  │  Referrals    │  │  Referrals   │  │  SOL Earned  │   │
│  │     12        │  │     34       │  │   2.45 SOL   │   │
│  └──────────────┘  └──────────────┘  └──────────────┘   │
│                                                          │
│  Earnings Breakdown                                      │
│  ┌──────────────────────────────────────────────────┐    │
│  │  Tier-1 (0.2% of referrals' losses)  1.89 SOL   │    │
│  │  Tier-2 (0.1% of sub-referrals)      0.56 SOL   │    │
│  └──────────────────────────────────────────────────┘    │
│                                                          │
│  How it works:                                           │
│  • You earn 0.2% of every losing order by players you   │
│    directly referred                                     │
│  • You also earn 0.1% from players referred by YOUR     │
│    referrals (tier-2)                                    │
│  • Rewards are paid automatically in SOL after each      │
│    losing order — no claiming needed                     │
└──────────────────────────────────────────────────────────┘
```

### Implementation

- **Direct referral count**: From on-chain `ReferralState.total_referrals`
- **Tier-2 referral count**: Tracked in PostgreSQL — when a new `set_referrer` TX is confirmed, the backend identifies the tier-2 and increments a counter
- **Earnings split**: Two separate `ReferralState` PDAs — one for the player as tier-1 referrer, one for the player as tier-2 referrer. The backend sums both for display.
  - Alternative: single `ReferralState` with `tier1_earnings` and `tier2_earnings` fields (saves one PDA per referrer)
- **Real-time updates**: PubSub broadcast on `RewardPaid` events — `/referrals` page subscribes to events where the recipient matches the current user

---

## 12. LP Provider Interface

Separate page at `/pool` — simpler than the main trading UI. Requires wallet connection.

### LP Deposit Flow

1. User connects wallet (same SolanaWallet hook as main page)
2. User enters SOL amount to deposit
3. LiveView computes LP tokens to receive: `lp_amount = (deposit * lp_supply) / effective_balance`
4. Display current LP token price, APY estimate (from recent house profit), and pool stats
5. User clicks "Deposit" → JS hook builds `deposit_sol` instruction via Anchor, signs with wallet
6. On confirmation: LiveView updates balances via PubSub

### LP Withdraw Flow

1. User sees their FATE-LP balance and current value in SOL
2. User enters LP amount to burn (or "Max")
3. LiveView computes SOL to receive: `sol_out = (lp_amount * effective_balance) / lp_supply`
4. User clicks "Withdraw" → JS hook builds `withdraw_sol` instruction (burn LP + receive SOL)
5. On confirmation: LiveView updates balances

### Pool Stats Display

- **Total vault balance** (SOL)
- **Total liability** (pending payouts)
- **Available liquidity** (vault - rent - liability)
- **LP token price** (current, computed from on-chain state)
- **Total LP supply**
- **24h volume** (from PostgreSQL order history)
- **House P/L** (lifetime, from `ClearingHouseState.house_profit`)
- **APY estimate**: `(house_profit_30d / effective_balance) * 12 * 100`

### Implementation

- Pure LiveView page (no complex JS hooks beyond wallet connection)
- Pool stats fetched via fate-settler `GET /clearing-house-state` endpoint
- LP balance fetched via `getTokenAccountsByOwner` RPC call (or fate-settler endpoint)
- Real-time updates via PubSub when deposits/withdrawals/settlements occur

---

## 13. Provably Fair Verification UI

Separate page at `/verify` — allows anyone to verify any past fate order was fair.

### Verification Flow

1. User enters a Solana transaction signature (from the `FateOrderSettled` event)
2. Backend fetches the transaction via `getTransaction` RPC call
3. Parse the `FateOrderSettled` event from transaction logs to extract:
   - `server_seed`, `nonce`, `player` (pubkey), `multiplier_bps`, `filled` (claimed result)
4. Parse the corresponding `FateOrderPlaced` event (from the placement TX, linked by order PDA) to extract:
   - `commitment_hash`
5. Server performs verification:
   - `SHA256(server_seed) == commitment_hash` → proves seed was committed before bet
   - `SHA256(server_seed || player_pubkey || nonce)` → take first 4 bytes as u32 (big-endian) → `roll`
   - `fill_chance_bps = (MULTIPLIER_BASE * (10000 - fate_fee_bps)) / multiplier_bps`
   - `threshold = (fill_chance_bps * u32::MAX) / 10000`
   - `roll < threshold` → should match `filled` boolean
6. Display results: green checkmark if all checks pass, red X with explanation if any fail

### UI Components

- **TX signature input**: Text field + "Verify" button
- **Verification result card**: Shows all inputs, intermediate values, and pass/fail for each step
- **"How it works" explainer**: Collapsible section explaining the commit-reveal mechanism
- **Link from result overlay**: Every order result screen includes a "Verify this order" link that pre-fills the TX signature

### Implementation

- Pure LiveView page, no JS hooks needed (verification is all server-side math)
- Uses `start_async` for the RPC call to fetch transaction data
- Consider caching recent verifications in PostgreSQL for fast lookups

---

## 14. Token Selector Modal

LiveView component for choosing which memecoin to sell (sell-side) or buy (buy-side).

### Data Source

- `FateSwap.TokenEligibility` GenServer maintains the eligible token list in ETS
- Tokens include: `mint_address`, `symbol`, `name`, `logo_url`, `decimals`, `liquidity_usd`, `price_usd`
- Refreshed every 15 minutes from Jupiter verified token list + liquidity checks

### UI Implementation

```
┌──────────────────────────────────┐
│  Select Token                  ✕ │
│  ┌──────────────────────────────┐│
│  │ 🔍 Search tokens...         ││
│  └──────────────────────────────┘│
│                                  │
│  Popular:                        │
│  [SOL] [BONK] [WIF] [JUP] [POPCAT]│
│                                  │
│  ┌──────────────────────────────┐│
│  │ 🐕 BONK         $0.00002   ││
│  │    Bonk          $1.2B liq  ││
│  ├──────────────────────────────┤│
│  │ 🐕 WIF          $2.34      ││
│  │    dogwifhat     $890M liq  ││
│  ├──────────────────────────────┤│
│  │ ...                         ││
│  └──────────────────────────────┘│
└──────────────────────────────────┘
```

### Implementation Details

- **LiveView component** (`FateSwap.Components.TokenSelector`), not a JS hook — search/filter is server-side
- `phx-change` on search input → server-side fuzzy match on symbol/name via ETS lookup
- `phx-click` on token row → pushes `{mint, symbol, decimals, logo_url}` to parent LiveView
- Token logos from Jupiter's CDN: `https://img.jup.ag/tokens/<mint_address>.png` (or fallback placeholder)
- **Popular tokens** shortcut row: hardcoded top 5-8 tokens by volume for quick selection
- **Balance display**: If wallet connected, show user's balance for each token (fetched via `getTokenAccountsByOwner` on wallet connect, cached in LiveView assigns)
- Modal opens via LiveView assign (`@show_token_selector`), closes on selection or outside click

---

## 15. Mobile Strategy

### Phase 1: Responsive PWA (Launch)

The dark DEX UI is inherently mobile-friendly — the swap card is a single column, `max-w-md` layout that works on any screen size.

**Mobile-specific considerations:**
- **Fate slider**: HTML `<input type="range">` natively supports touch events. No additional JS needed for basic touch. For a premium feel, add `touch-action: none` and handle `touchmove` in the JS hook for custom behavior.
- **Wallet connection on mobile**: Mobile wallets (Phantom, Solflare) use **deeplinks** / **universal links** for connection. When a user taps "Connect Wallet" on mobile:
  1. App opens `phantom://` or `https://phantom.app/ul/v1/connect?...` deeplink
  2. Phantom mobile app opens, user approves
  3. Phantom redirects back to the browser with pubkey in URL params
  4. JS hook extracts pubkey and resumes the SIWS auth flow
  - This is fundamentally different from desktop (desktop uses injected `window.phantom.solana`)
  - **Must implement both flows** in the SolanaWallet hook — detect mobile via `navigator.userAgentData.mobile` or screen width
- **Transaction signing on mobile**: Same deeplink pattern — serialize TX, open wallet app, user signs, redirect back with signed TX
- **Touch targets**: Ensure all buttons are at least 44x44px (Apple HIG minimum)
- **Viewport**: `<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">` to prevent zoom on input focus

### Phase 2: Capacitor PWA (Post-Launch)

Wrap the responsive web app in Capacitor for native-like experience:
- **Install prompt**: Add to homescreen via `manifest.json` (works without Capacitor)
- **Capacitor benefits**: Push notifications for order results, app store distribution, native splash screen
- **Capacitor wallet connection**: Uses same deeplink pattern as mobile web — Capacitor apps open wallet apps via `App.openUrl()` and receive callbacks via `App.addListener('appUrlOpen')`
- **Timeline**: Only after the web app is stable and has users. Capacitor wrapping is ~1 day of work.

---

*This document synthesizes research from 5 parallel agents analyzing: Solana-Elixir integration (libraries, RPC, TX building), frontend wallet/Jupiter integration (JS hooks, VersionedTransaction, Anchor client), wallet authentication (Thirdweb vs wallet-adapter, SIWS flow), existing Blockster codebase patterns (BuxBooster commit-reveal, settlement, LiveView, GenServers), and DEX swap UI design (slider, probability ring, live feed, dark theme).*
