# FateSwap — Implementation Plan

> **Status**: Planning
> **Source docs**: `fateswap_solana_architecture.md` (on-chain), `fateswap_liveview_research.md` (app)
> **Repo**: Standalone — separate from Blockster V2

---

## Version Requirements

All components use the latest stable versions as of February 2026. Versions are managed via **asdf** (`.tool-versions` files per project directory). Claude will install versions and create `.tool-versions` files during scaffold phases.

### Elixir / Phoenix App (fateswap)

| Dependency | Version |
|---|---|
| Elixir | 1.18.2 |
| Erlang/OTP | 27.2 |
| Phoenix | 1.7.20 |
| Phoenix LiveView | 1.1.0 |

**`fateswap/.tool-versions`** (created by Claude during Phase E1):
```
elixir 1.18.2-otp-27
erlang 27.2
nodejs 22.13.1
```

asdf setup (Claude runs during E1 scaffold):
```bash
asdf install erlang 27.2
asdf install elixir 1.18.2-otp-27
asdf install nodejs 22.13.1
```

### fate-settler (Node.js)

| Dependency | Version |
|---|---|
| Node.js | 22 LTS (22.13.1) |
| @coral-xyz/anchor | ^0.31 |
| @solana/web3.js | ^1.95 |

**`fate-settler/.tool-versions`** (created by Claude during Phase N1):
```
nodejs 22.13.1
```

### Anchor / Solana Programs

| Dependency | Version |
|---|---|
| Rust | 1.84.1 (via rustup, not asdf) |
| Anchor CLI | 0.31.1 |
| anchor-lang | 0.31.1 |
| Solana CLI | latest compatible with Anchor 0.31.1 |

**`programs/fateswap/rust-toolchain.toml`** (created by Claude during Phase S1):
```toml
[toolchain]
channel = "1.84.1"
```

> **Note**: Rust uses `rustup` + `rust-toolchain.toml` (standard in the Solana/Anchor ecosystem), not asdf. Anchor CLI and Solana CLI are installed via `cargo install` / `sh -c "$(curl ...)"` respectively.

---

## Progress Tracker

<!-- Update this section as phases complete -->

| Phase | Name | Status | Files | Tests |
|-------|------|--------|-------|-------|
| S1 | Anchor Program: ClearingHouse | NOT STARTED | — | — |
| S2 | Anchor Program: FateGame | NOT STARTED | — | — |
| S3 | Anchor Program: Referral (Two-Tier) + Admin + 5-Way Split | NOT STARTED | — | — |
| S3.5 | Anchor Program: NFTRewarder | NOT STARTED | — | — |
| S4 | Anchor Program: Devnet Deploy + Manual Test | NOT STARTED | — | — |
| N1 | fate-settler: Core Service | NOT STARTED | — | — |
| N2 | fate-settler: Settlement + Partial Signing | NOT STARTED | — | — |
| N3 | fate-settler: Account Reads + PDA Derivation | NOT STARTED | — | — |
| N4 | fate-settler: NFT Endpoints | NOT STARTED | — | — |
| E1 | Phoenix App Scaffold + Auth | NOT STARTED | — | — |
| E2 | Backend Services: Seed Manager + Settlement | NOT STARTED | — | — |
| E3 | Backend Services: Token Eligibility + Price Tracker | NOT STARTED | — | — |
| E4 | Backend Services: NFTOwnershipPoller | NOT STARTED | — | — |
| E5 | Backend Services: Share Cards + Social Infrastructure | NOT STARTED | — | — |
| E6 | Backend Services: Automated X + Telegram Content Engine | NOT STARTED | — | — |
| F1 | Frontend: Wallet Connection + Auth Flow | NOT STARTED | — | — |
| F2 | Frontend: Trading UI (Sell-Side) + Brand Language | NOT STARTED | — | — |
| F3 | Frontend: Buy-Side + Partial Signing | NOT STARTED | — | — |
| F4 | Frontend: LP Provider Interface | NOT STARTED | — | — |
| F5 | Frontend: Referral UI (Two-Tier) + Provably Fair + Share Overlay | NOT STARTED | — | — |
| F6 | Frontend: Live Feed + Token Selector | NOT STARTED | — | — |
| D1 | Devnet Integration Testing | NOT STARTED | — | — |
| D2 | Production Deploy (Mainnet-Beta) | NOT STARTED | — | — |
| | | | | |
| **FUTURE** | | | | |
| F7 | Frontend: NFT Page + Wallet Mapping | DEFERRED | — | — |

---

## Architecture Summary

```
Browser (LiveView + JS Hooks)
  ├── SolanaWallet Hook (Wallet Standard auto-detect)
  ├── FateSwapTrade Hook (Jupiter + Anchor TX building)
  └── FateSlider / ProbabilityRing / FeedScroll Hooks
        │
        │ WebSocket (LiveView)
        ▼
FateSwap Phoenix App (Elixir) — fateswap.com / Fly.io
  ├── Auth (Ed25519 SIWS, wallet-only)
  ├── SeedManager GenServer (CSPRNG + AES-256-GCM in PostgreSQL)
  ├── SettlementService (client-push + Oban poller)
  ├── TokenEligibility GenServer (Jupiter API → ETS cache)
  ├── PriceTracker GenServer (Jupiter Price API → ETS + PubSub)
  ├── NFTOwnershipPoller GenServer (Arbitrum → Solana bridge)
  ├── ShareCardGenerator (SVG EEx → PNG via Resvg)
  ├── ContentQualifier GenServer (tweet-worthiness rules)
  ├── Social: XPoster + TelegramPoster (Oban-scheduled)
  └── ChainReader module (Solana JSON-RPC via Req)
        │
        │ HTTP (HMAC-authenticated, Fly.io private network)
        ▼
fate-settler (Node.js) — internal only, no public access
  ├── POST /submit-commitment
  ├── POST /settle-fate-order
  ├── POST /build-settle-and-swap
  ├── POST /nft-register, /nft-update-ownership, /nft-batch-register
  ├── GET /clearing-house-state
  └── GET /player-state/:pubkey
        │
        ▼
Solana Mainnet-Beta
  ├── FateSwap Anchor Program
  │     ├── ClearingHouse (LP pool, vault, FATE-LP mint)
  │     └── FateGame (commit-reveal, fate orders, 5-way split)
  └── NFTRewarder Anchor Program (MasterChef-style NFT rewards)
```

---

## Phase S1: Anchor Program — ClearingHouse (LP Pool)

**Goal**: Implement the LP pool that holds SOL and mints/burns FATE-LP tokens. Direct port of ROGUEBankroll.sol mechanics.

**Prerequisites**: Anchor CLI installed, Rust toolchain, Solana CLI

### Tasks

1. **Project scaffold** (Claude handles version setup)
   - Install Rust 1.84.1 via `rustup`, install Anchor CLI 0.31.1 via `cargo install`
   - `anchor init fateswap` — creates project structure
   - Create `rust-toolchain.toml` with `channel = "1.84.1"`
   - `Cargo.toml`: `anchor-lang = "0.31.1"`, `anchor-spl = "0.31.1"`
   - Configure `Anchor.toml` for localnet + devnet
   - Set up `programs/fateswap/src/` module structure

2. **State accounts** (`src/state/`)
   - `clearing_house.rs` — `ClearingHouseState` struct (~716 bytes, includes `_reserved: [u8; 192]`; fields for 5-way split: `tier2_referral_bps`, `nft_reward_bps`, `platform_fee_bps`, `bonus_bps`, `platform_wallet`, `bonus_wallet`, `nft_rewarder`)
   - `mod.rs` — re-exports

3. **Instructions** (`src/instructions/`)
   - `initialize.rs` — creates ClearingHouseState PDA, vault PDA, LP mint PDA, LP authority PDA; validates config bounds (`fate_fee_bps <= 1000`, `max_bet_bps <= 500`, `min_bet > 0`, `bet_timeout >= 60`); sets `referral_bps = 0`, `tier2_referral_bps = 0`, `nft_reward_bps = 0`, `platform_fee_bps = 0`, `bonus_bps = 0`; accepts `platform_wallet`, `bonus_wallet`, `nft_rewarder` params
   - `deposit_sol.rs` — LP pricing math, SOL transfer to vault, mint FATE-LP via CPI; first-depositor protection burns `MINIMUM_LIQUIDITY` (10,000 lamports) to prevent donation attack
   - `withdraw_sol.rs` — burn FATE-LP, proportional SOL withdrawal, liability cap enforcement
   - Account context structs with full Anchor constraints for each instruction

4. **Math module** (`src/math.rs`)
   - `get_lp_price()` — 18-decimal fixed point, effective_balance / lp_supply; returns `Result<u64>` with `checked_mul` and `u64::try_from()` for overflow safety
   - `calculate_max_bet()` — inverse multiplier scaling (used later in S2 but defined here)

5. **Errors** (`src/errors.rs`)
   - `FateSwapError` enum — Paused, ZeroAmount, DepositTooSmall, WithdrawTooSmall, InsufficientLiquidity, MathOverflow, InvalidConfig

6. **Events** (`src/events.rs`)
   - `ClearingHouseInitialized`, `LiquidityDeposited`, `LiquidityWithdrawn`

7. **Tests** (`tests/clearing_house/`) — bankrun framework, ~55 test cases

   **`initialize.test.ts`** (~11 tests)
   - initializes ClearingHouseState with correct authority, settler, and config values
   - creates vault PDA with correct seeds and ownership
   - creates LP mint PDA with 9 decimals and correct authority
   - creates LP authority PDA
   - stores all bumps (vault, lp_mint, lp_authority) on state
   - sets referral_bps = 0, tier2_referral_bps = 0, nft_reward_bps = 0, platform_fee_bps = 0, bonus_bps = 0
   - stores platform_wallet, bonus_wallet, nft_rewarder from params
   - emits ClearingHouseInitialized event with correct fields
   - rejects double initialization (PDA already exists)
   - fate_fee_bps > 1000 → InvalidConfig error
   - max_bet_bps > 500 → InvalidConfig error
   - min_bet = 0 → InvalidConfig error
   - bet_timeout < 60 → InvalidConfig error

   **`deposit.test.ts`** (~15 tests)
   - first deposit burns MINIMUM_LIQUIDITY (10,000 lamports) — depositor receives LP minus burned amount
   - first deposit too small (≤ MINIMUM_LIQUIDITY) → DepositTooSmall error
   - second depositor not affected by MINIMUM_LIQUIDITY burn (only applies to first deposit)
   - second deposit mints proportional LP (vault has 2 SOL after wins, deposit 1 SOL → 50% of supply)
   - deposits 0 lamports → rejected with ZeroAmount error
   - deposit too small to mint any LP → rejected with DepositTooSmall
   - SOL actually transfers from depositor to vault (balance checks)
   - LP tokens appear in depositor's associated token account
   - vault lamport balance increases by exact deposit amount
   - lp_mint.supply increases by exact minted amount
   - multiple sequential deposits by same user accumulate correctly
   - multiple users depositing get proportional shares
   - deposit with pending liability correctly excludes liability from LP pricing
   - emits LiquidityDeposited event with correct depositor, amounts, balances

   **`withdraw.test.ts`** (~12 tests)
   - full withdrawal returns all SOL (minus rent-exempt minimum)
   - partial withdrawal returns proportional SOL
   - withdrawal of 0 LP tokens → rejected with ZeroAmount
   - withdrawal that would return 0 SOL → rejected with WithdrawTooSmall
   - withdrawal exceeding available liquidity (vault - rent - liability) → rejected with InsufficientLiquidity
   - LP tokens burned from withdrawer's account
   - SOL transfers from vault to withdrawer (balance checks)
   - vault balance decreases by exact withdrawal amount
   - lp_mint.supply decreases by exact burned amount
   - cannot withdraw more LP tokens than user owns (SPL token error)
   - withdrawal with outstanding liability correctly caps available balance
   - emits LiquidityWithdrawn event with correct withdrawer, amounts, balances

   **`lp_price.test.ts`** (~8 tests)
   - LP price starts at 1:1 (1e18) when supply > 0
   - LP price returns 1e18 when supply is 0
   - LP price increases when vault balance increases (simulating house wins)
   - LP price decreases when vault balance decreases (simulating payouts)
   - LP price correctly excludes total_liability from effective_balance
   - LP price correctly excludes rent-exempt minimum from effective_balance
   - LP price uses u128 intermediate to prevent overflow
   - LP price after 100 wins and 50 losses is within expected range

   **`pause.test.ts`** (~7 tests)
   - authority can set paused = true
   - authority can set paused = false (unpause)
   - non-authority cannot pause → rejected
   - deposit_sol blocked when paused → Paused error
   - withdraw_sol blocked when paused → Paused error
   - emits Paused event with correct authority and timestamp
   - paused state persists across multiple calls

### Files

```
programs/fateswap/
├── src/
│   ├── lib.rs
│   ├── state/
│   │   ├── mod.rs
│   │   └── clearing_house.rs
│   ├── instructions/
│   │   ├── mod.rs
│   │   ├── initialize.rs
│   │   ├── deposit_sol.rs
│   │   └── withdraw_sol.rs
│   ├── errors.rs
│   ├── events.rs
│   └── math.rs
├── Anchor.toml
├── Cargo.toml
tests/
├── clearing_house/
│   ├── initialize.test.ts
│   ├── deposit.test.ts
│   ├── withdraw.test.ts
│   ├── lp_price.test.ts
│   └── pause.test.ts
```

### Key Decisions
- Use `bankrun` (solana-bankrun) for tests — fast startup (~1s vs ~30s for full validator)
- Vault PDA uses direct lamport manipulation for withdrawals (cheaper than CPI `system_program::transfer`)
- Vault rent-exempt minimum uses `minimum_balance(8)` (8-byte discriminator), not `minimum_balance(0)`
- LP mint decimals = 9 (matches SOL)
- First deposit burns MINIMUM_LIQUIDITY (10,000 lamports) to prevent donation/rounding attack on LP pricing
- All arithmetic uses `checked_*` operations with `u128` intermediates; `get_lp_price()` returns `Result<u64>` with `try_from` conversion
- `potential_payout` uses `u64::try_from()` instead of `as u64` to prevent silent truncation

---

## Phase S2: Anchor Program — FateGame (Bet Logic)

**Goal**: Implement the commit-reveal betting system. Port of BuxBoosterGame's core logic with 210 discrete multiplier steps (1.01x–10.0x).

**Prerequisites**: S1 complete

### Tasks

1. **State accounts** (`src/state/`)
   - `fate_order.rs` — `FateOrder` struct (~180 bytes), `FateOrderStatus` enum (Pending, Filled, NotFilled, Expired)
   - `player_state.rs` — `PlayerState` struct (~242 bytes, includes `pending_commitment: [u8;32]`, `pending_nonce: u64`, `tier2_referrer: Pubkey`), persistent per-player

2. **Instructions** (`src/instructions/`)
   - `submit_commitment.rs` — settler submits `SHA256(server_seed)` to PlayerState; `init_if_needed` on PlayerState (settler pays rent for new players); sets `player_state.player = player` on first init
   - `place_fate_order.rs` — validates multiplier via `is_valid_multiplier()` (210 discrete steps across 6 tiers), nonce match, commitment exists, no active order; creates FateOrder PDA; transfers SOL to vault; updates global liability/stats
   - `settle_fate_order.rs` — settler provides `filled: bool` + `server_seed`; program verifies `SHA256(server_seed) == commitment_hash` on-chain (hybrid verification — seed authenticity on-chain, outcome off-chain); pays out if filled; on losses: 5-way non-blocking revenue split (tier-1 referrer, tier-2 referrer, NFT rewarder, platform wallet, bonus wallet — each with `RewardPaid` event emission); closes FateOrder PDA (rent → player); reads order fields into local vars before mutable borrows (borrow checker safe); context includes 13 accounts total
   - `reclaim_expired_order.rs` — player reclaims SOL after 5-min timeout; refunds full wager; closes FateOrder PDA

3. **Math additions** (`src/math.rs`)
   - `calculate_max_bet()` — `base_max * 200000 / multiplier_bps` (inverse scaling, 2x reference point)
   - `is_valid_multiplier()` — validates BPS is one of 210 discrete allowed values (6 tiers with different step sizes); `#[inline(always)]` for performance
   - Constants: `MIN_MULTIPLIER = 101_000`, `MAX_MULTIPLIER = 1_000_000`, `MULTIPLIER_BASE = 100_000`

4. **Error additions**
   - InvalidMultiplier, NonceMismatch, NoCommitment, ActiveOrderExists, BetTooSmall, BetTooLarge, InsufficientVaultBalance, OrderNotPending, OrderExpired, OrderNotExpired, UnauthorizedSettler, InvalidPlayer, InvalidServerSeed, InvalidReferrer

5. **Event additions**
   - `CommitmentSubmitted`, `FateOrderPlaced`, `FateOrderSettled`, `FateOrderReclaimed`

6. **Tests** (`tests/fate_game/`) — ~77 test cases

   **`commitment.test.ts`** (~10 tests)
   - settler can submit commitment hash (32 bytes stored on PlayerState)
   - commitment creates PlayerState via init_if_needed for new players
   - settler pays rent for new PlayerState accounts
   - pending_nonce on PlayerState matches submitted nonce
   - non-settler wallet cannot submit commitment → UnauthorizedSettler error
   - submitting new commitment overwrites previous pending commitment
   - commitment with paused protocol → Paused error
   - emits CommitmentSubmitted event with correct player, hash, nonce, timestamp
   - PlayerState.player field set correctly on first init
   - PlayerState.bump stored correctly

   **`place_order.test.ts`** (~15 tests)
   - valid order placement: SOL transfers to vault, FateOrder PDA created, stats updated
   - multiplier below MIN_MULTIPLIER (100000, below min of 101000) → InvalidMultiplier error
   - multiplier above MAX_MULTIPLIER (1001000) → InvalidMultiplier error
   - multiplier at exact MIN boundary (101000 = 1.01x) → accepted
   - multiplier at exact MAX boundary (1000000 = 10.0x) → accepted
   - multiplier between valid steps (101500 = 1.015x, not a valid step) → InvalidMultiplier error
   - nonce mismatch with pending_nonce → NonceMismatch error
   - no pending commitment (all zeros) → NoCommitment error
   - player already has active order → ActiveOrderExists error
   - bet below min_bet → BetTooSmall error
   - bet above dynamic max_bet → BetTooLarge error
   - vault can't cover potential_payout → InsufficientVaultBalance error
   - FateOrder fields set correctly (player, amount, multiplier_bps, potential_payout, commitment_hash, nonce, status=Pending, token_mint, token_amount, bump)
   - global state updated: total_liability += potential_payout, unsettled_count += 1
   - PlayerState updated: has_active_order=true, active_order=PDA key, nonce+=1, pending_commitment cleared
   - emits FateOrderPlaced event with all fields correct

   **`settle_filled.test.ts`** (~14 tests)
   - filled=true: player receives potential_payout SOL from vault
   - player SOL balance increases by exact payout amount
   - vault SOL balance decreases by exact payout amount
   - global state: total_liability decreased, unsettled_count decreased, total_bets incremented, total_filled incremented, total_volume updated, house_profit decreased by (payout - wager)
   - PlayerState: has_active_order=false, active_order=default, total_orders incremented, total_wagered updated, total_won updated (fill profit, not total payout), net_pnl increased by profit
   - FateOrder account closed (rent returned to player)
   - non-settler cannot settle → UnauthorizedSettler error
   - settling non-Pending order → OrderNotPending error
   - emits FateOrderSettled event with filled=true, correct payout, server_seed, all fields
   - player rent-exempt balance increases (FateOrder account closed)
   - **Commitment verification**: settle with wrong server_seed (SHA256 mismatch) → InvalidServerSeed error
   - **Commitment verification**: settle with correct server_seed (SHA256 matches commitment_hash) → succeeds
   - **Referrer validation**: settle with wrong referrer account (doesn't match PlayerState.referrer) → InvalidReferrer error
   - **Referrer validation**: settle with no referrer set (Pubkey::default on PlayerState) → any referrer account accepted

   **`settle_not_filled.test.ts`** (~10 tests)
   - filled=false: no SOL transfers (wager stays in vault)
   - vault balance unchanged (already has the wager)
   - global state: total_liability decreased, unsettled_count decreased, total_bets incremented, total_not_filled incremented, house_profit increased by wager amount
   - PlayerState: has_active_order=false, net_pnl decreased by wager amount, total_orders incremented
   - FateOrder account closed (rent returned to player)
   - emits FateOrderSettled with filled=false, payout=0
   - **Commitment verification**: not-filled settle with wrong server_seed → InvalidServerSeed error (same check as filled path)
   - **Referrer validation**: not-filled settle with wrong referrer → InvalidReferrer error
   - consecutive win then loss produces correct cumulative stats
   - consecutive loss then win produces correct cumulative stats

   **`expire_order.test.ts`** (~8 tests)
   - reclaim after timeout: player receives wager back from vault
   - reclaim before timeout elapsed → OrderNotExpired error
   - reclaim at exact timeout boundary (timestamp == order.timestamp + timeout) → OrderNotExpired (must be strictly greater)
   - reclaim at timeout + 1 second → accepted
   - global state: total_liability decreased, unsettled_count decreased (but total_bets NOT incremented)
   - PlayerState: has_active_order=false, active_order=default
   - FateOrder account closed (rent returned to player)
   - emits FateOrderReclaimed event with correct refund amount

   **`multiplier_range.test.ts`** (~14 tests)
   - **Tier 1**: 1.01x (101000) accepted, payout = amount * 101000 / 100000
   - **Tier 1**: 1.50x (150000) accepted, payout computed correctly
   - **Tier 1**: 1.99x (199000) accepted (last in tier 1)
   - **Tier 2**: 2.00x (200000) accepted, payout = 2x wager
   - **Tier 2**: 2.50x (250000) accepted
   - **Tier 3**: 3.00x (300000) accepted
   - **Tier 3**: 3.95x (395000) accepted (last in tier 3)
   - **Tier 4**: 4.0x (400000) accepted
   - **Tier 4**: 5.0x (500000) accepted, payout = 5x wager
   - **Tier 5**: 6.0x (600000) accepted
   - **Tier 5**: 9.8x (980000) accepted (last in tier 5)
   - **Tier 6**: 10.0x (1000000) accepted, payout = 10x wager
   - **Invalid steps**: 101500 (between 1.01x and 1.02x), 201000 (between 2.00x and 2.02x), 301000 (between 3.00x and 3.05x), 405000 (between 4.0x and 4.1x), 610000 (between 6.0x and 6.2x) → all InvalidMultiplier
   - **Out of range**: 100000 (1.0x, below min), 1020000 (10.2x, above max) → InvalidMultiplier

   **`max_bet.test.ts`** (~6 tests)
   - max_bet at 2x (200000) equals base_max (net_balance * max_bet_bps / 10000)
   - max_bet at 1.01x is ~2x the base_max (large bet, tiny profit)
   - max_bet at 10x is ~0.2x the base_max (small bet, large profit)
   - max_bet scales linearly with vault net_balance
   - max_bet with zero net_balance returns 0
   - max_bet * multiplier roughly constant across all multiplier values (within rounding)

### Files (new/modified)

```
programs/fateswap/src/state/
  ├── fate_order.rs          (NEW)
  └── player_state.rs        (NEW)
programs/fateswap/src/instructions/
  ├── submit_commitment.rs   (NEW)
  ├── place_fate_order.rs    (NEW)
  ├── settle_fate_order.rs   (NEW)
  └── reclaim_expired_order.rs (NEW)
tests/fate_game/
  ├── commitment.test.ts
  ├── place_order.test.ts
  ├── settle_filled.test.ts
  ├── settle_not_filled.test.ts
  ├── expire_order.test.ts
  ├── multiplier_range.test.ts
  └── max_bet.test.ts
```

### Key Decisions
- Settlement uses **hybrid verification**: `SHA256(server_seed) == commitment_hash` is verified on-chain (ensures seed authenticity), while `filled: bool` outcome is trusted from the settler. Verification data is also emitted in events for off-chain auditing.
- `token_mint` and `token_amount` on FateOrder are **metadata only** — the program never handles SPL tokens
- One active order per player (enforced by `has_active_order` flag on PlayerState)
- Commitment stored on PlayerState (not separate PDA) — saves rent since only one pending commitment at a time

---

## Phase S3: Anchor Program — Two-Tier Referral + 5-Way Split + Admin

**Goal**: Two-tier referral system, 5-way revenue split on losses (tier-1 referrer, tier-2 referrer, NFT rewarder, platform wallet, bonus wallet), and admin configuration for all 12 configurable fields.

**Prerequisites**: S2 complete

### Tasks

1. **State accounts** (`src/state/`)
   - `referral_state.rs` — `ReferralState` struct (~80 bytes): `referrer`, `total_referrals`, `total_earnings`, `bump`, `_reserved`
   - All 5 bps fields already on `ClearingHouseState` (initialized to 0 in S1): `referral_bps`, `tier2_referral_bps`, `nft_reward_bps`, `platform_fee_bps`, `bonus_bps`
   - All 3 wallet Pubkeys already on `ClearingHouseState` (set in S1 `initialize`): `platform_wallet`, `bonus_wallet`, `nft_rewarder`

2. **Instructions** (`src/instructions/`)
   - `set_referrer.rs` — player sets one-time referrer; creates `ReferralState` PDA if needed; self-referral blocked; **auto-resolves tier-2**: reads referrer's `PlayerState.referrer` and stores as `player_state.tier2_referrer` (one-time cost, zero reads at settlement); context includes optional `referrer_player_state: Option<Account<'info, PlayerState>>`
   - `pause.rs` — authority toggles `paused` flag
   - `update_config.rs` — authority updates any of 12 configurable fields (all optional): `fate_fee_bps`, `max_bet_bps`, `min_bet`, `bet_timeout`, `referral_bps`, `tier2_referral_bps`, `nft_reward_bps`, `platform_fee_bps`, `bonus_bps`, `platform_wallet`, `bonus_wallet`, `nft_rewarder`. Each per-tier bps capped at 100 (1%). Emits `ConfigUpdated` event per changed field.
   - `update_settler.rs` — authority changes the authorized settler wallet

3. **5-way revenue split in settlement** — modify `settle_fate_order.rs`:
   - On losses only, 5 non-blocking transfers from vault using shared `_send_reward()` helper:
     1. `wager * referral_bps / 10000` → tier-1 referrer (if set)
     2. `wager * tier2_referral_bps / 10000` → tier-2 referrer (if set)
     3. `wager * nft_reward_bps / 10000` → NFT rewarder program
     4. `wager * platform_fee_bps / 10000` → platform wallet
     5. `wager * bonus_bps / 10000` → bonus wallet
   - Each transfer emits `RewardPaid` event with `reward_type` (0=tier1_referral, 1=tier2_referral, 2=nft_reward, 3=platform_fee, 4=bonus)
   - Failure of any single transfer does NOT revert the settlement (non-blocking)
   - Update `ReferralState.total_earnings` for tier-1 referrer
   - SettleFateOrder context: 13 accounts total — adds `tier2_referrer`, `tier2_referral_state`, `nft_rewarder`, `platform_wallet`, `bonus_wallet` with constraint validations

4. **Error additions**
   - `InvalidNFTRewarder` (6023), `InvalidPlatformWallet` (6024), `InvalidBonusWallet` (6025)

5. **Event additions/modifications**
   - `ReferrerSet` — now includes `tier2_referrer: Pubkey`
   - `RewardPaid` — replaces old `ReferralRewardPaid`: `reward_type: u8`, `recipient: Pubkey`, `amount: u64`, `order: Pubkey`
   - `ConfigUpdated` — field IDs 0-8: fate_fee_bps (0), max_bet_bps (1), min_bet (2), bet_timeout (3), referral_bps (4), tier2_referral_bps (5), nft_reward_bps (6), platform_fee_bps (7), bonus_bps (8)

6. **Tests** — ~72 test cases

   **`referral/set_referrer.test.ts`** (~12 tests)
   - player sets referrer successfully, PlayerState.referrer updated
   - ReferralState PDA created via init_if_needed for new referrers
   - player pays rent for ReferralState creation
   - self-referral (player == referrer) → SelfReferral error
   - setting referrer twice → ReferrerAlreadySet error
   - ReferralState.total_referrals not incremented (tracked on-chain in settlement)
   - emits ReferrerSet event with player, referrer, AND tier2_referrer
   - referrer can be any valid pubkey (doesn't need to be an existing player)
   - **tier-2 auto-resolution**: referrer has a referrer → player's tier2_referrer set to referrer's referrer
   - **tier-2 auto-resolution**: referrer has NO referrer (default pubkey) → player's tier2_referrer = default
   - **tier-2 auto-resolution**: referrer_player_state is None (new referrer, no PlayerState) → tier2_referrer = default
   - **tier-2 auto-resolution**: PlayerState.tier2_referrer stored correctly and immutable after set

   **`referral/reward_payment.test.ts`** (~18 tests)
   - losing order with tier-1 referrer: referral reward paid from vault to referrer
   - tier-1 reward amount = wager * referral_bps / 10000 (e.g., 0.2% of wager at 20 bps)
   - losing order with tier-2 referrer: tier-2 reward paid from vault to tier-2 referrer
   - tier-2 reward amount = wager * tier2_referral_bps / 10000 (e.g., 0.1% at 10 bps)
   - losing order: NFT reward sent to nft_rewarder vault via direct lamport transfer (0.3% at 30 bps); NFTRewarder detects via sync_rewards crank
   - losing order: platform fee paid to platform_wallet (0.3% at 30 bps)
   - losing order: bonus paid to bonus_wallet (0.1% at 10 bps)
   - winning order: NO rewards paid (all 5 transfers skipped)
   - no tier-1 referrer set (default pubkey): tier-1 reward skipped, no error
   - no tier-2 referrer set (default pubkey): tier-2 reward skipped, no error
   - all bps = 0: no rewards paid regardless of referrer
   - ReferralState.total_earnings incremented by tier-1 reward amount only
   - vault balance decreased by sum of all 5 rewards
   - each recipient SOL balance increases by exact reward amount
   - very small wager where individual reward rounds to 0: no transfer, no error
   - individual reward failure does NOT revert the settlement (non-blocking)
   - all 5 rewards emit RewardPaid events with correct reward_type (0-4)
   - total deductions: sum of all 5 rewards = wager * (referral_bps + tier2_referral_bps + nft_reward_bps + platform_fee_bps + bonus_bps) / 10000

   **`admin/update_config.test.ts`** (~18 tests)
   - authority can update fate_fee_bps
   - authority can update max_bet_bps
   - authority can update min_bet
   - authority can update bet_timeout
   - authority can update referral_bps
   - authority can update tier2_referral_bps
   - authority can update nft_reward_bps
   - authority can update platform_fee_bps
   - authority can update bonus_bps
   - authority can update platform_wallet (Pubkey)
   - authority can update bonus_wallet (Pubkey)
   - authority can update nft_rewarder (Pubkey)
   - can update single field (others unchanged)
   - can update multiple fields in one call
   - per-tier bps > 100 (1%) → InvalidConfig error (applies to referral_bps, tier2_referral_bps, nft_reward_bps, platform_fee_bps, bonus_bps)
   - fate_fee_bps > 1000 (10%) → InvalidConfig error
   - max_bet_bps > 500 (5%) → InvalidConfig error
   - non-authority cannot update config

   **`admin/update_settler.test.ts`** (~4 tests)
   - authority can change settler to new pubkey
   - old settler can no longer submit commitments after change
   - new settler CAN submit commitments after change
   - non-authority cannot update settler
   - emits SettlerUpdated event with old and new settler

   **`security/access_control.test.ts`** (~8 tests)
   - random wallet cannot call pause → unauthorized
   - random wallet cannot call update_config → unauthorized
   - random wallet cannot call update_settler → unauthorized
   - random wallet cannot call submit_commitment → UnauthorizedSettler
   - random wallet cannot call settle_fate_order → UnauthorizedSettler
   - player cannot settle their own order (not settler)
   - cannot place order on behalf of another player (player must be signer)
   - cannot reclaim another player's expired order (player must match)

   **`security/double_settle.test.ts`** (~4 tests)
   - settling same order twice → OrderNotPending (first settle closes the PDA)
   - attempting to settle after reclaim → account doesn't exist (already closed)
   - attempting to reclaim after settle → account doesn't exist (already closed)
   - concurrent settlement attempts: second one fails

   **`security/overflow.test.ts`** (~4 tests)
   - deposit near u64::MAX lamports → handles gracefully (overflow in LP calc)
   - max multiplier (10x) with large wager → potential_payout overflow handled
   - total_volume at near u128::MAX → saturates, doesn't panic
   - house_profit extreme negative and positive values → doesn't panic

   **`integration/full_flow.test.ts`** (~8 tests)
   - complete flow: initialize → deposit LP → commit → place order → settle (win) → verify LP price decreased → withdraw LP
   - complete flow: initialize → deposit LP → commit → place order → settle (loss) → verify LP price increased → withdraw LP
   - multi-player: two players betting simultaneously, both settle correctly
   - LP deposits during active bets: new LP pricing reflects outstanding liability
   - full cycle with tier-1 referral: set referrer → lose → tier-1 reward paid → referrer withdraws
   - full cycle with tier-2 referral: Alice refers Bob, Bob refers Carol → Carol loses → both Alice and Bob receive rewards
   - full cycle with 5-way split: set all bps, lose → verify all 5 recipients receive correct amounts, vault balance reflects total deductions
   - stress test: 20 sequential bets (10 wins, 10 losses) → final LP price reflects net house profit minus all rewards

### Files (new/modified)

```
programs/fateswap/src/state/referral_state.rs     (NEW)
programs/fateswap/src/instructions/set_referrer.rs (NEW)
programs/fateswap/src/instructions/pause.rs        (NEW)
programs/fateswap/src/instructions/update_config.rs (NEW)
programs/fateswap/src/instructions/update_settler.rs (NEW)
tests/referral/
  ├── set_referrer.test.ts
  └── reward_payment.test.ts
tests/admin/
  ├── update_config.test.ts
  └── update_settler.test.ts
tests/security/
  ├── access_control.test.ts
  ├── overflow.test.ts
  └── double_settle.test.ts
tests/integration/full_flow.test.ts
```

---

## Phase S3.5: Anchor Program — NFTRewarder

**Goal**: Separate Anchor program for MasterChef-style proportional NFT reward distribution. Receives SOL from FateSwap settlement (the `nft_reward_bps` share) and distributes it to NFT holders proportional to their multiplier points.

**Prerequisites**: S3 complete

### Background

- 2,341 NFTs on Arbitrum (`0x7176d2edd83aD037bd94b7eE717bd9F661F560DD`)
- 8 types with multiplier weights: Standard(30x), Silver(40x), Gold(50x), Platinum(60x), Diamond(70x), Royal(80x), Mythic(90x), Legendary(100x)
- ~109,390 total multiplier points across all NFTs
- Ownership data bridged from Arbitrum by NFTOwnershipPoller GenServer (Phase E4) via fate-settler (Phase N4)

### Tasks

1. **Project scaffold**
   - Separate Anchor program in `programs/nft-rewarder/`
   - Shares Anchor workspace with fateswap program
   - `Cargo.toml`: `anchor-lang = "0.31.1"`

2. **State accounts** (`src/state/`)
   - `rewarder_state.rs` — `RewarderState` struct (~200 bytes): `authority`, `fateswap_program` (reference only), `total_points` (u64, sum of all multiplier weights), `accumulated_reward_per_point` (u128, 18-decimal fixed point), `total_distributed` (u64), `last_synced_balance` (u64, for sync_rewards crank), `bump`, `_reserved`
   - `nft_holder.rs` — `NFTHolder` struct (~120 bytes): `wallet` (Pubkey), `points` (u64, sum of multiplier weights for all NFTs owned), `reward_debt` (u128, MasterChef accounting), `pending_reward` (u64), `bump`

3. **Instructions** (`src/instructions/`)
   - `initialize.rs` — creates RewarderState PDA, sets authority and fateswap_program
   - `sync_rewards.rs` — permissionless crank that detects new SOL in vault by comparing `vault.lamports()` against `last_synced_balance`; computes delta and updates `accumulated_reward_per_point += delta * 1e18 / total_points`; updates `last_synced_balance`; anyone can call (no signer check needed — it only reads vault balance, can't drain)
   - `update_holder.rs` — admin updates an NFT holder's points (called by fate-settler when ownership changes detected); harvests pending reward before updating points; updates `total_points`; creates NFTHolder PDA if needed
   - `batch_update_holders.rs` — admin updates multiple holders in one TX (efficiency for initial registration and bulk changes); limited to ~5 holders per TX (account limits)
   - `claim_reward.rs` — NFT holder claims accumulated SOL reward; computes `pending = holder.points * accumulated_reward_per_point / 1e18 - holder.reward_debt`; transfers SOL from vault to holder; updates `reward_debt`

4. **MasterChef math** (`src/math.rs`)
   - `pending_reward(holder_points, acc_per_point, reward_debt) → u64` — uses u128 intermediate arithmetic
   - `update_acc_per_point(current_acc, reward_amount, total_points) → u128`

5. **Errors** (`src/errors.rs`)
   - `Unauthorized`, `ZeroPoints`, `NoRewardAvailable`, `MathOverflow`, `InvalidFateSwapProgram`

6. **Events** (`src/events.rs`)
   - `RewarderInitialized`, `RewardReceived`, `HolderUpdated`, `RewardClaimed`

7. **Tests** (`tests/nft_rewarder/`) — ~30 test cases

   **`initialize.test.ts`** (~4 tests)
   - initializes RewarderState with correct authority, fateswap_program, total_points=0
   - creates vault PDA
   - rejects double initialization
   - stores bump correctly

   **`sync_rewards.test.ts`** (~6 tests)
   - SOL deposited to vault → sync_rewards updates accumulated_reward_per_point correctly
   - multiple syncs accumulate correctly (deposit, sync, deposit again, sync again)
   - sync with no new SOL → no-op (last_synced_balance unchanged)
   - sync with total_points=0 → no-op (no div by zero)
   - permissionless: any signer can call sync_rewards
   - last_synced_balance tracks correctly after claims reduce vault balance
   - emits RewardReceived event with amount and new accumulated_reward_per_point

   **`update_holder.test.ts`** (~8 tests)
   - admin registers new holder with points → NFTHolder PDA created, total_points updated
   - admin updates existing holder's points → pending reward harvested first, then points updated
   - removing all points (points=0) → holder can still claim pending, total_points decreased
   - non-admin cannot update → Unauthorized error
   - total_points reflects sum of all active holder points
   - reward_debt set correctly after update (no double-counting)
   - emits HolderUpdated event with wallet, old_points, new_points
   - batch update: 5 holders updated in single TX

   **`claim_reward.test.ts`** (~8 tests)
   - holder claims correct pending reward amount
   - pending reward = points * acc_per_point / 1e18 - reward_debt
   - claim updates reward_debt (no double-claiming)
   - holder with 0 pending → NoRewardAvailable error
   - holder SOL balance increases by exact reward amount
   - vault balance decreases by exact reward amount
   - consecutive claims: first claim pays, second claim pays only new accumulated
   - emits RewardClaimed event with holder, amount

   **`integration.test.ts`** (~4 tests)
   - full flow: initialize → register 3 holders with different points → deposit SOL to vault → sync_rewards → all claim proportional amounts
   - holder with 2x points receives 2x reward
   - add new holder after rewards accumulated → new holder starts at 0 pending (no steal from existing)
   - remove holder points → remaining holders get larger share of future rewards

### Files

```
programs/nft-rewarder/
├── src/
│   ├── lib.rs
│   ├── state/
│   │   ├── mod.rs
│   │   ├── rewarder_state.rs
│   │   └── nft_holder.rs
│   ├── instructions/
│   │   ├── mod.rs
│   │   ├── initialize.rs
│   │   ├── sync_rewards.rs
│   │   ├── update_holder.rs
│   │   ├── batch_update_holders.rs
│   │   └── claim_reward.rs
│   ├── errors.rs
│   ├── events.rs
│   └── math.rs
├── Cargo.toml
tests/nft_rewarder/
├── initialize.test.ts
├── sync_rewards.test.ts
├── update_holder.test.ts
├── claim_reward.test.ts
└── integration.test.ts
```

### Key Decisions
- Separate program (not merged into FateSwap) — cleaner authority boundaries, independent upgradeability
- MasterChef algorithm avoids iteration over all holders during reward receipt — O(1) per receive, O(1) per claim
- `update_holder` harvests pending reward before modifying points to prevent reward loss
- Batch updates limited to ~5 per TX due to Solana account limits (each holder = 2 accounts)

---

## Phase S4: Anchor Program — Devnet Deploy + Manual Test

**Goal**: Deploy both programs to Solana devnet, verify all instructions work with real wallets.

**Prerequisites**: S3.5 complete, all tests passing

### Tasks

1. Generate program keypairs for devnet (FateSwap + NFTRewarder)
2. `anchor build` → `anchor deploy --provider.cluster devnet` (both programs)
3. Manual tests with Phantom wallet:
   - Initialize ClearingHouse (with platform_wallet, bonus_wallet, nft_rewarder)
   - Initialize NFTRewarder (with fateswap_program reference)
   - Deposit SOL → receive FATE-LP
   - Submit commitment → place fate order → settle
   - Reclaim expired order
   - Set referrer (verify tier-2 auto-resolution)
   - Settle losing bet → verify all 5 revenue split recipients receive correct amounts
   - NFTRewarder: register holder → deposit SOL to vault → sync_rewards → claim
   - Admin: pause, update config (all 12 fields), update settler
   - Withdraw SOL → burn FATE-LP
4. Record program IDs, all PDA addresses, and deployment TX hashes

---

## Phase N1: fate-settler — Core Service

**Goal**: Node.js microservice that holds the settler keypair, builds and signs Solana transactions for commitment submission and settlement.

**Prerequisites**: S3.5 complete (program IDL available from anchor build)

### Tasks

1. **Project scaffold** (Claude handles version setup)
   - `asdf install nodejs 22.13.1` if not already installed
   - Create `.tool-versions` with `nodejs 22.13.1`
   - Express.js (or Fastify) server on Node.js 22 LTS
   - `@solana/web3.js` ^1.95, `@coral-xyz/anchor` ^0.31, `@solana/spl-token`
   - `package.json`: `"engines": { "node": ">=22" }`
   - Fly.io `fly.toml` — **no `[[services]]`** (internal only), Dockerfile with `node:22-slim`
   - Environment: `SETTLER_PRIVATE_KEY`, `HMAC_SECRET`, `SOLANA_RPC_URL`, `PROGRAM_ID`

2. **HMAC authentication middleware**
   - Validate `x-hmac-signature` and `x-timestamp` headers on every request
   - Reject requests older than 30 seconds
   - Log all requests with origin, endpoint, and result

3. **Endpoints**
   - `POST /submit-commitment` — builds and signs `submit_commitment` instruction, submits TX
   - `POST /settle-fate-order` — builds and signs `settle_fate_order` instruction (server-only settlement), submits TX
   - Health check endpoint (internal only)

4. **Transaction management**
   - Recent blockhash caching (refresh every 30s)
   - Priority fee computation (dynamic, based on `getRecentPrioritizationFees`)
   - TX confirmation polling with timeout
   - Error handling: retry once on blockhash expiry

5. **Tests** (Jest or Vitest) — ~25 test cases

   **`tests/hmac.test.ts`** (~8 tests)
   - valid HMAC signature + fresh timestamp → request accepted (200)
   - invalid HMAC signature → rejected (401)
   - missing x-hmac-signature header → rejected (401)
   - missing x-timestamp header → rejected (401)
   - expired timestamp (>30 seconds old) → rejected (401)
   - future timestamp (>5 seconds ahead) → rejected (401)
   - empty body with valid HMAC → accepted
   - tampered body (valid sig for different body) → rejected (401)

   **`tests/commitment.test.ts`** (~6 tests)
   - POST /submit-commitment with valid params → returns txSignature
   - commitment_hash is 32 bytes → accepted
   - invalid commitment_hash (wrong length) → rejected (400)
   - invalid player pubkey (not base58) → rejected (400)
   - response includes txSignature as base58 string
   - request without HMAC auth → rejected (401)

   **`tests/settlement.test.ts`** (~7 tests)
   - POST /settle-fate-order with valid params → returns txSignature + filled + payout
   - server_seed is 32 bytes → accepted
   - invalid orderPda (not a valid PDA) → appropriate error
   - response includes filled boolean and payout amount
   - request without HMAC auth → rejected (401)
   - health check endpoint returns 200

   **`tests/solana-service.test.ts`** (~4 tests)
   - blockhash cache returns fresh blockhash (not expired)
   - blockhash refreshes after 30 seconds
   - priority fee computation returns reasonable value
   - connection uses configured RPC URL

### Files

```
fate-settler/
├── src/
│   ├── index.ts              # Express app entry
│   ├── middleware/
│   │   └── hmac-auth.ts      # HMAC-SHA256 verification
│   ├── routes/
│   │   ├── commitment.ts     # POST /submit-commitment
│   │   └── settlement.ts     # POST /settle-fate-order
│   ├── services/
│   │   ├── solana.ts         # Connection, blockhash cache, TX submission
│   │   └── anchor-client.ts  # Anchor program instance, IDL loading
│   └── config.ts             # Environment variables
├── idl/
│   └── fateswap.json         # Generated IDL from anchor build
├── fly.toml
├── package.json
├── tsconfig.json
└── tests/
    ├── hmac.test.ts
    ├── commitment.test.ts
    ├── settlement.test.ts
    └── solana-service.test.ts
```

---

## Phase N2: fate-settler — Settlement + Partial Signing

**Goal**: Add buy-side partial signing flow and full settlement strategies.

**Prerequisites**: N1 complete

### Tasks

1. **`POST /build-settle-and-swap`** — for buy-side fills (player online):
   - Fetch Jupiter quote: payout SOL → target token
   - Build combined TX: `settle_fate_order` instructions + Jupiter swap instructions
   - Partially sign with settler keypair (settlement instruction)
   - Return base64-serialized partially-signed TX to Elixir app
   - Elixir app pushes to JS hook → player co-signs → JS hook submits

2. **Jupiter integration in fate-settler**
   - Jupiter Quote API (`GET /quote`)
   - Jupiter Swap Instructions API (`GET /swap-instructions`)
   - Address Lookup Table fetching
   - VersionedTransaction construction with ALTs

3. **Settlement strategy logic**
   - Not Filled: server-only settle TX (N1 endpoint)
   - Filled + sell-side: server-only settle TX (player receives SOL)
   - Filled + buy-side + player online: partial-sign TX (this phase)
   - Filled + buy-side + player offline: fallback server-only settle TX

### Tests — ~12 test cases

   **`tests/settle-and-swap.test.ts`** (~8 tests)
   - POST /build-settle-and-swap with valid params → returns base64 partially-signed TX
   - returned TX contains settle_fate_order instruction (settler-signed)
   - returned TX contains Jupiter swap instructions (unsigned, awaiting player)
   - returned TX is a VersionedTransaction with Address Lookup Tables
   - returned TX can be deserialized and has correct number of signatures (1 of 2)
   - invalid outputMint → appropriate error
   - slippageBps passed to Jupiter quote correctly
   - request without HMAC auth → rejected (401)

   **`tests/jupiter.test.ts`** (~4 tests)
   - fetchQuote returns valid quote with outAmount
   - fetchSwapInstructions returns setup, swap, cleanup instructions
   - fetchSwapInstructions returns addressLookupTableAddresses
   - handles Jupiter API errors gracefully (500, rate limit)

### Files (new/modified)

```
fate-settler/src/routes/
  └── settle-and-swap.ts       (NEW)
fate-settler/src/services/
  └── jupiter.ts               (NEW) — quote + swap instruction fetching
fate-settler/tests/
  ├── settle-and-swap.test.ts  (NEW)
  └── jupiter.test.ts          (NEW)
```

---

## Phase N3: fate-settler — Account Reads + PDA Derivation

**Goal**: Endpoints for the Elixir app to read on-chain state without manual Borsh decoding.

**Prerequisites**: N1 complete

### Tasks

1. **`GET /clearing-house-state`** — returns decoded ClearingHouseState
2. **`GET /player-state/:pubkey`** — returns decoded PlayerState
3. **`GET /fate-order/:pubkey`** — returns decoded FateOrder (if exists)
4. **`GET /derive-pda`** — computes PDA addresses for given seeds + program ID (ETS-cached by Elixir)
5. **`GET /lp-balance/:wallet`** — returns user's FATE-LP token balance

### Tests — ~10 test cases

   **`tests/accounts.test.ts`** (~6 tests)
   - GET /clearing-house-state returns all decoded fields (authority, settler, fees, stats, paused)
   - GET /player-state/:pubkey returns decoded PlayerState for existing player
   - GET /player-state/:pubkey returns 404 for non-existent player
   - GET /fate-order/:pubkey returns decoded FateOrder for pending order
   - GET /fate-order/:pubkey returns 404 for settled/closed order
   - GET /lp-balance/:wallet returns correct FATE-LP token balance (0 if no ATA)

   **`tests/pda.test.ts`** (~4 tests)
   - GET /derive-pda with clearing_house seeds returns correct PDA + bump
   - GET /derive-pda with player seeds returns correct PDA + bump
   - GET /derive-pda with fate_order seeds (player + nonce) returns correct PDA + bump
   - PDA derivation matches `PublicKey.findProgramAddressSync()` output

### Files (new/modified)

```
fate-settler/src/routes/
  ├── accounts.ts              (NEW) — clearing-house-state, player-state, fate-order
  └── pda.ts                   (NEW) — PDA derivation
fate-settler/tests/
  ├── accounts.test.ts         (NEW)
  └── pda.test.ts              (NEW)
```

---

## Phase N4: fate-settler — NFT Endpoints

**Goal**: Admin endpoints for the NFTOwnershipPoller GenServer (Phase E4) to register and update NFT holder ownership on the Solana NFTRewarder program.

**Prerequisites**: N1 complete, S3.5 complete (NFTRewarder deployed)

### Tasks

1. **`POST /nft-register`** — registers a single NFT holder on the NFTRewarder program
   - Params: `wallet` (Solana pubkey), `points` (multiplier weight sum for all NFTs owned)
   - Builds and signs `update_holder` instruction on NFTRewarder program
   - Returns `txSignature`

2. **`POST /nft-batch-register`** — registers multiple NFT holders in one call
   - Params: `holders` array of `{ wallet, points }` (max ~5 per TX due to account limits)
   - Builds and signs `batch_update_holders` instruction
   - Returns `txSignature`

3. **`POST /nft-update-ownership`** — updates a holder's points when ownership changes
   - Params: `wallet` (Solana pubkey), `new_points` (updated multiplier weight sum)
   - Builds and signs `update_holder` instruction (harvests pending reward automatically)
   - Returns `txSignature`

4. **Anchor client additions**
   - Load NFTRewarder IDL (separate from FateSwap IDL)
   - PDA derivation for NFTHolder accounts
   - `NFT_REWARDER_PROGRAM_ID` from environment

### Tests — ~12 test cases

   **`tests/nft-register.test.ts`** (~5 tests)
   - POST /nft-register with valid wallet + points → returns txSignature
   - POST /nft-register with zero points → rejected (400)
   - POST /nft-register with invalid wallet (not base58) → rejected (400)
   - POST /nft-batch-register with 5 holders → returns txSignature
   - request without HMAC auth → rejected (401)

   **`tests/nft-update.test.ts`** (~4 tests)
   - POST /nft-update-ownership with valid wallet + new_points → returns txSignature
   - POST /nft-update-ownership updates existing holder's points
   - POST /nft-update-ownership with 0 new_points (holder sold all NFTs) → accepted
   - request without HMAC auth → rejected (401)

   **`tests/nft-pda.test.ts`** (~3 tests)
   - NFTHolder PDA derivation matches on-chain address
   - RewarderState PDA derivation correct
   - Multiple calls return consistent PDAs

### Files

```
fate-settler/src/routes/
  └── nft.ts                   (NEW) — /nft-register, /nft-batch-register, /nft-update-ownership
fate-settler/src/services/
  └── nft-rewarder-client.ts   (NEW) — NFTRewarder Anchor client, IDL, PDAs
fate-settler/idl/
  └── nft_rewarder.json        (NEW) — Generated IDL from anchor build
fate-settler/tests/
  ├── nft-register.test.ts     (NEW)
  ├── nft-update.test.ts       (NEW)
  └── nft-pda.test.ts          (NEW)
```

---

## Phase E1: Phoenix App — Scaffold + Auth

**Goal**: New Phoenix LiveView app with wallet-only authentication (Sign-In With Solana).

**Prerequisites**: None (can start in parallel with Solana program development)

### Tasks

1. **Project scaffold** (Claude handles version setup)
   - `asdf install erlang 27.2 && asdf install elixir 1.18.2-otp-27 && asdf install nodejs 22.13.1`
   - Create `.tool-versions` with `elixir 1.18.2-otp-27`, `erlang 27.2`, `nodejs 22.13.1`
   - `mix phx.new fateswap --live --database postgres` (Phoenix 1.7.20 generator)
   - `mix.exs`: `{:phoenix, "~> 1.7.20"}`, `{:phoenix_live_view, "~> 1.1.0"}`
   - Configure for Fly.io deployment (Dockerfile with Elixir 1.18.2 + OTP 27)
   - Add dependencies: `req`, `b58`, `oban`, `resvg` (SVG→PNG for share cards), `oauther` (OAuth 1.0a for X API)
   - esbuild config: `--format=esm --splitting` for code splitting

   > **UI Note**: All frontend phases (F1-F6) use `/frontend-design` skill for production-grade UI. Reference `docs/fateswap_branding_marketing.md` for brand identity, color system, and copy.

2. **Brand design system** (from `docs/fateswap_branding_marketing.md`)
   - TailwindCSS dark theme with brand colors:
     - Primary BG: `#0A0A0F` (near-black)
     - Card BG: `#14141A` with `border border-white/[0.06]`
     - Brand gradient: `#22C55E` → `#EAB308` → `#EF4444` (green → yellow → red)
     - Text primary: `#E8E4DD` (off-white)
     - Text secondary: `#6B7280` (muted)
     - Accent filled: `#22C55E` (green)
     - Accent not-filled: `#8B2500` (muted red, dramatic not punishing)
     - Data/fee text: `#9CA3AF` (cool gray)
   - Custom fonts via npm: Satoshi (display/wordmark), JetBrains Mono (data/monospace)
   - Dockerfile: copy fonts to `/usr/share/fonts/truetype/fateswap/`, `fc-cache -f -v` (for Resvg server-side rendering)
   - Tailwind config: extend with brand colors, font families, gradient utilities

3. **Database schema**
   - `players` table: `wallet_address` (primary), `created_at`, `last_seen_at`
   - `fate_orders` table: `id`, `wallet_address`, `nonce`, `server_seed_encrypted`, `commitment_hash`, `multiplier_bps`, `sol_amount`, `token_mint`, `token_symbol`, `status` (generated/committed/placed/settled/expired), `filled`, `payout`, `tx_signatures` (jsonb), `created_at`, `settled_at`
   - `referral_links` table: `id`, `referrer_wallet`, `code` (unique, three-word format: `adjective-participle-animal`), `created_at`

4. **Wallet authentication**
   - `FateSwap.Auth` module — Ed25519 signature verification via `:crypto.verify(:eddsa, ...)`
   - Challenge message generation (SIWS format) with server-generated nonce
   - Nonce storage in ETS (short-lived, 5-min expiry)
   - Phoenix session tied to `wallet_address` after verification
   - `FateSwapWeb.AuthPlug` — reads wallet from session, assigns to `conn`
   - `on_mount` hook for LiveView — reads wallet from session, assigns to socket

5. **Layout + root page**
   - Dark theme root layout (`bg-gray-950 text-white`)
   - Navigation: FateSwap logo, wallet connect button, mode toggle
   - Router: `/` (trade), `/pool` (LP), `/verify` (provably fair), `/referrals`, `/order/:order_id` (share page)

### Tests (ExUnit) — ~37 test cases

   **`test/fateswap/auth_test.exs`** (~12 tests)
   - `generate_challenge/1` returns SIWS-formatted message with wallet address and nonce
   - `generate_challenge/1` stores nonce in ETS with 5-min TTL
   - `verify_signature/3` accepts valid Ed25519 signature → returns :ok
   - `verify_signature/3` rejects invalid signature → returns :error
   - `verify_signature/3` rejects expired nonce (>5 min) → returns :error
   - `verify_signature/3` rejects already-used nonce (replay) → returns :error
   - `verify_signature/3` rejects wrong message content → returns :error
   - valid Base58 wallet address decoded correctly (32 bytes)
   - invalid Base58 string → decode error
   - nonce cleanup: expired nonces removed from ETS
   - challenge message includes correct domain, URI, timestamp
   - concurrent challenge generation for different wallets → unique nonces

   **`test/fateswap/accounts/player_test.exs`** (~5 tests)
   - create_player/1 with valid wallet_address → inserts player
   - create_player/1 with duplicate wallet_address → changeset error
   - get_player/1 returns player by wallet_address
   - get_or_create_player/1 creates if not exists, returns if exists
   - player timestamps (created_at, last_seen_at) set correctly

   **`test/fateswap/orders/fate_order_test.exs`** (~6 tests)
   - create_fate_order/1 with valid attrs → inserts order with status :generated
   - changeset validates required fields (wallet_address, nonce, commitment_hash, multiplier_bps, sol_amount)
   - changeset validates multiplier_bps is one of the 210 discrete allowed values (via `FateSwap.Multipliers.valid?/1`)
   - changeset validates sol_amount > 0
   - update_status/2 transitions :generated → :committed → :placed → :settled
   - list_stale_orders/1 returns orders with status :committed older than threshold

   **`test/fateswap_web/plugs/auth_plug_test.exs`** (~4 tests)
   - authenticated session → assigns wallet_address to conn
   - no session → wallet_address assign is nil
   - expired session → wallet_address assign is nil
   - session with invalid wallet → wallet_address assign is nil

   **`test/fateswap_web/live/page_live_test.exs`** (~4 tests)
   - GET / renders trade page (200 response)
   - GET /pool renders pool page
   - GET /verify renders verify page
   - GET /referrals renders referrals page

   **`test/fateswap/referrals/referral_link_test.exs`** (~6 tests)
   - create_referral_link/1 generates three-word code (adjective-participle-animal)
   - get_by_code/1 returns referral link with referrer_wallet
   - duplicate code generation → retries with new code
   - code format matches ~r/^[a-z]+-[a-z]+-[a-z]+$/
   - create_referral_link/1 returns existing code if wallet already has one
   - all three words come from curated word lists (no random strings)

### Files

```
fateswap/
├── lib/fateswap/
│   ├── auth.ex                    # Ed25519 SIWS verification
│   ├── accounts/player.ex         # Player schema
│   ├── orders/fate_order.ex       # FateOrder schema
│   ├── referrals/referral_link.ex # Referral link schema
│   └── referrals/code_generator.ex # Three-word code generator (word lists + collision retry)
├── lib/fateswap_web/
│   ├── plugs/auth_plug.ex         # Session → conn.assigns
│   ├── live/
│   │   └── hooks/auth_hook.ex     # on_mount LiveView hook
│   ├── components/
│   │   └── layouts.ex             # Dark theme root layout
│   └── router.ex
├── priv/repo/migrations/
│   ├── 001_create_players.exs
│   ├── 002_create_fate_orders.exs
│   └── 003_create_referral_links.exs
├── test/
│   ├── fateswap/
│   │   ├── auth_test.exs
│   │   ├── accounts/player_test.exs
│   │   ├── orders/fate_order_test.exs
│   │   └── referrals/referral_link_test.exs
│   ├── fateswap_web/
│   │   ├── plugs/auth_plug_test.exs
│   │   └── live/page_live_test.exs
│   └── support/
│       ├── fixtures.ex
│       └── conn_case.ex
├── assets/
│   ├── js/app.js
│   ├── css/app.css                # Dark theme + slider styles
│   └── tailwind.config.js
├── config/
│   ├── config.exs
│   ├── dev.exs
│   ├── prod.exs
│   └── runtime.exs
└── fly.toml
```

---

## Phase E2: Backend Services — Seed Manager + Settlement

**Goal**: Server-side seed generation, encrypted storage, and settlement orchestration.

**Prerequisites**: E1 complete, N1 complete (fate-settler running)

### Tasks

1. **SeedManager GenServer** (`lib/fateswap/seed_manager.ex`)
   - Generate 32-byte seeds via `:crypto.strong_rand_bytes(32)`
   - Compute commitment: `:crypto.hash(:sha256, server_seed)`
   - Encrypt seed with AES-256-GCM before PostgreSQL storage
   - Decrypt seed on settlement
   - Key management: encryption key from `SEED_ENCRYPTION_KEY` env var

2. **SettlerClient module** (`lib/fateswap/settler_client.ex`)
   - HTTP client for fate-settler endpoints
   - HMAC-SHA256 request signing (`:crypto.mac(:hmac, :sha256, ...)`)
   - Timestamp header for replay prevention
   - Connection to `fate-settler.internal:3000` (Fly.io private network)
   - Configurable to `localhost:3000` for dev

   > **Note**: All HTTP requests (to fate-settler, Jupiter API, Arbitrum RPC) must include explicit timeouts per project conventions (e.g., `receive_timeout: 30_000` for Req calls).

3. **SettlementService** (`lib/fateswap/settlement_service.ex`)
   - **Primary path**: `handle_event("order_placed", ...)` from LiveView client push
   - Look up stored seed → compute outcome off-chain:
     `SHA256(server_seed || player_pubkey || nonce)` → first 4 bytes → u32 → compare to threshold
   - Call fate-settler `/settle-fate-order` (or `/build-settle-and-swap` for buy-side fills)
   - Update PostgreSQL order status

4. **Settlement Oban worker** (`lib/fateswap/workers/settlement_worker.ex`)
   - **Safety net**: Scheduled every 5-10 seconds
   - Queries for orders with status `committed` older than 10 seconds
   - Checks on-chain if FateOrder PDA exists (via fate-settler account read)
   - Triggers settlement if found
   - Exponential backoff retries (max 3)
   - Stops retrying at 4.5 minutes (player can reclaim after 5-min timeout)

5. **Outcome computation module** (`lib/fateswap/provably_fair.ex`)
   - `compute_outcome(server_seed, player_pubkey, nonce, multiplier_bps, fate_fee_bps)` → `{:filled | :not_filled, roll}`
   - `verify_commitment(server_seed, commitment_hash)` → boolean
   - Deterministic: same inputs → same result
   - Fill chance: `fill_chance_bps = (100_000 * (10_000 - fate_fee_bps)) / multiplier_bps`
   - Threshold: `threshold = div(fill_chance_bps * 0xFFFFFFFF, 10_000)`
   - Roll: first 4 bytes of `SHA256(server_seed <> player_pubkey <> <<nonce::little-64>>)` as big-endian u32

### Tests (ExUnit) — ~45 test cases

   **`test/fateswap/seed_manager_test.exs`** (~10 tests)
   - generate_seed/0 returns {seed (32 bytes), commitment_hash (32 bytes)}
   - commitment_hash = SHA256(seed)
   - two calls return different seeds (CSPRNG)
   - store_seed/2 encrypts seed with AES-256-GCM before DB write
   - stored seed is NOT plaintext in the database (verify encrypted blob)
   - retrieve_seed/1 decrypts seed correctly (roundtrip)
   - retrieve_seed/1 with wrong encryption key → decryption error
   - retrieve_seed/1 for non-existent order → {:error, :not_found}
   - seed stored in fate_orders table with correct order_id
   - concurrent seed generation produces unique seeds

   **`test/fateswap/settler_client_test.exs`** (~8 tests, with Req mock/stub)
   - submit_commitment/3 sends correct payload with HMAC headers
   - submit_commitment/3 returns {:ok, tx_signature} on 200
   - submit_commitment/3 returns {:error, reason} on non-200
   - settle_fate_order/4 sends correct payload with HMAC headers
   - settle_fate_order/4 returns {:ok, %{tx_signature, filled, payout}} on 200
   - HMAC signature computed correctly: SHA256(shared_secret, timestamp <> "." <> body)
   - x-timestamp header is current unix timestamp as string
   - connection timeout (fate-settler down) → {:error, :timeout}

   **`test/fateswap/settlement_service_test.exs`** (~10 tests, with mocked settler_client)
   - handle_order_placed/1 looks up seed, computes outcome, calls settler
   - handle_order_placed/1 with filled=true outcome → calls settle (sell-side) or build-settle-and-swap (buy-side)
   - handle_order_placed/1 with filled=false outcome → calls settle (server-only)
   - handle_order_placed/1 updates fate_order status to :settled in DB
   - handle_order_placed/1 stores settlement TX signature in DB
   - handle_order_placed/1 for already-settled order → no-op (idempotent)
   - handle_order_placed/1 with settler_client failure → returns error (Oban retries)
   - broadcasts settlement result via PubSub ("fateswap:order:{wallet}")
   - broadcasts to live feed via PubSub ("fateswap:feed")
   - concurrent settlements for different players don't interfere

   **`test/fateswap/provably_fair_test.exs`** (~12 tests)
   - verify_commitment/2 returns true when SHA256(seed) == hash
   - verify_commitment/2 returns false when hash doesn't match
   - compute_outcome/5 returns {:filled, roll} when roll < threshold
   - compute_outcome/5 returns {:not_filled, roll} when roll >= threshold
   - compute_outcome/5 is deterministic (same inputs → same result, repeated 100x)
   - compute_outcome at 2x multiplier with 1.5% fee: fill_chance ~49.25%
   - compute_outcome at 1.01x multiplier: fill_chance ~97.5%
   - compute_outcome at 10x multiplier: fill_chance ~9.85%
   - statistical test: 10,000 outcomes at 2x → ~49-50% fill rate (within 3% tolerance)
   - roll computed as first 4 bytes of SHA256(seed || pubkey || nonce) big-endian u32
   - nonce encoded as little-endian 64-bit integer in hash input
   - fill_chance_bps formula: (100_000 * (10_000 - fee_bps)) / multiplier_bps

   **`test/fateswap/workers/settlement_worker_test.exs`** (~5 tests, Oban.Testing)
   - enqueues job when stale committed order detected
   - performs settlement via SettlementService
   - retries with exponential backoff on failure (max 3 attempts)
   - does not retry after 4.5 minutes (approaching 5-min timeout)
   - skips orders that were settled between detection and execution

### Files

```
lib/fateswap/
├── seed_manager.ex
├── settler_client.ex
├── settlement_service.ex
├── provably_fair.ex
├── workers/
│   └── settlement_worker.ex
test/fateswap/
├── seed_manager_test.exs
├── settler_client_test.exs
├── settlement_service_test.exs
├── provably_fair_test.exs
└── workers/settlement_worker_test.exs
```

---

## Phase E3: Backend Services — Token Eligibility + Price Tracker

**Goal**: Token validation and real-time price data from Jupiter APIs.

**Prerequisites**: E1 complete

### Tasks

1. **TokenEligibility GenServer** (`lib/fateswap/token_eligibility.ex`)
   - Poll Jupiter verified token list every 15 minutes
   - Check liquidity (>$50K) and price impact (<1% at $50K) via Jupiter Quote API
   - Store eligible tokens in ETS: `{mint_address, symbol, name, logo_url, decimals, liquidity_usd, price_usd}`
   - `Task.async_stream` with `max_concurrency: 10` for parallel liquidity checks
   - Public API: `list_tokens()`, `get_token(mint)`, `is_eligible?(mint)`, `search(query)`

2. **PriceTracker GenServer** (`lib/fateswap/price_tracker.ex`)
   - Poll Jupiter Price API every 60 seconds for SOL + top tokens
   - Store in ETS, broadcast via PubSub (`"fateswap:prices"`)
   - LiveView subscribes for real-time USD value display

3. **ChainReader module** (`lib/fateswap/chain_reader.ex`)
   - Solana JSON-RPC via Req: `getAccountInfo`, `getLatestBlockhash`, `getSignaturesForAddress`
   - Delegates Borsh decoding to fate-settler initially
   - PDA address caching in ETS (deterministic, compute once per player)

### Tests (ExUnit) — ~25 test cases

   **`test/fateswap/token_eligibility_test.exs`** (~10 tests, with Req mock)
   - list_tokens/0 returns list of eligible tokens from ETS
   - get_token/1 returns token by mint address
   - get_token/1 returns nil for unknown/ineligible mint
   - is_eligible?/1 returns true for eligible token
   - is_eligible?/1 returns false for unknown token
   - search/1 finds tokens by symbol (case-insensitive)
   - search/1 finds tokens by name (partial match)
   - search/1 returns empty list for no matches
   - token with <$50K liquidity excluded from eligible list
   - token with >1% price impact at $50K excluded from eligible list
   - refresh cycle updates ETS cache with fresh Jupiter data

   **`test/fateswap/price_tracker_test.exs`** (~8 tests, with Req mock)
   - start_link/1 starts GenServer and performs initial price fetch
   - get_price/1 returns cached price for known token
   - get_price/1 returns nil for unknown token
   - prices stored in ETS with correct format {token_id, price_usd, timestamp}
   - PubSub broadcast on price update ("fateswap:prices")
   - price refresh happens on schedule (60s interval)
   - handles Jupiter API failure gracefully (keeps stale cache)
   - SOL price always included in tracked tokens

   **`test/fateswap/chain_reader_test.exs`** (~7 tests, with Req mock)
   - get_clearing_house_state/0 calls fate-settler and returns decoded state
   - get_player_state/1 calls fate-settler with wallet pubkey
   - get_player_state/1 returns nil for non-existent player (404 from settler)
   - derive_pda/2 calls fate-settler and caches result in ETS
   - derive_pda/2 returns cached PDA on second call (no HTTP request)
   - get_latest_blockhash/0 returns valid blockhash string
   - handles fate-settler connection failure gracefully

### Files

```
lib/fateswap/
├── token_eligibility.ex
├── price_tracker.ex
└── chain_reader.ex
test/fateswap/
├── token_eligibility_test.exs
├── price_tracker_test.exs
└── chain_reader_test.exs
```

---

## Phase E4: Backend Services — NFTOwnershipPoller

**Goal**: GenServer that polls Arbitrum for NFT Transfer events and bridges ownership data to the Solana NFTRewarder program via fate-settler.

**Prerequisites**: E1 complete, N4 complete (NFT fate-settler endpoints)

### Background

The High Rollers NFT collection (2,341 NFTs, 8 types) lives on Arbitrum at `0x7176d2edd83aD037bd94b7eE717bd9F661F560DD`. FateSwap rewards are distributed on Solana. This poller bridges the ownership data cross-chain.

Pattern follows `BlocksterV2.ReferralRewardPoller` — GlobalSingleton, 1s polling, eth_getLogs, PostgreSQL block persistence, chunked backfill.

### Tasks

1. **Database migrations**
   - `nft_wallet_mappings` table: `id`, `ethereum_address` (string, indexed), `solana_address` (string, indexed), `created_at`, `updated_at`
   - `nft_ownership_cache` table: `id`, `token_id` (integer, indexed), `nft_type` (string), `multiplier` (integer), `owner_ethereum` (string), `owner_solana` (string), `last_transfer_block` (bigint), `created_at`, `updated_at`

2. **NFTOwnershipPoller GenServer** (`lib/fateswap/nft_ownership_poller.ex`)
   - Uses GlobalSingleton for single-instance across cluster
   - Polls Arbitrum RPC for ERC-721 `Transfer(address,address,uint256)` events on NFT contract
   - `@poll_interval_ms 5_000` (5 seconds — Arbitrum is fast, events are infrequent)
   - `@max_blocks_per_query 10_000`
   - PostgreSQL for last-processed-block persistence (table: `nft_poller_state`)
   - On transfer detected:
     1. Update `nft_ownership_cache` with new owner
     2. Look up owner's Solana address from `nft_wallet_mappings`
     3. If mapping exists, call fate-settler `POST /nft-update-ownership` with new points
   - Backfill from deploy block on first run (chunked, rate-limited)

3. **NFTWalletMapping context** (`lib/fateswap/nft/wallet_mapping.ex`)
   - `register_mapping(ethereum_address, solana_address)` — creates/updates mapping
   - `get_solana_address(ethereum_address)` — looks up mapping
   - `get_ethereum_address(solana_address)` — reverse lookup
   - Called from `/nft` page (Phase F7) when user connects both wallets

4. **NFT multiplier constants** (`lib/fateswap/nft/multipliers.ex`)
   - Map of token_id ranges → NFT type → multiplier weight
   - `get_multiplier(token_id)` → integer (30-100)
   - `calculate_points(token_ids)` → sum of multiplier weights

5. **SettlerClient additions** (`lib/fateswap/settler_client.ex`)
   - `nft_register(wallet, points)` — calls `POST /nft-register`
   - `nft_batch_register(holders)` — calls `POST /nft-batch-register`
   - `nft_update_ownership(wallet, new_points)` — calls `POST /nft-update-ownership`

### Tests (ExUnit) — ~30 test cases

   **`test/fateswap/nft_ownership_poller_test.exs`** (~10 tests, with mocked RPC + settler_client)
   - start_link starts GenServer with GlobalSingleton
   - polls Arbitrum for Transfer events on NFT contract
   - Transfer event parsed correctly: from, to, tokenId extracted
   - new transfer → updates nft_ownership_cache with new owner
   - transfer with existing wallet mapping → calls settler nft_update_ownership
   - transfer without wallet mapping → updates cache only (no settler call)
   - PostgreSQL block persistence: saves last processed block
   - backfill on first run: processes historical transfers in chunks
   - polling overlap prevention (polling: true flag)
   - handles Arbitrum RPC errors gracefully (continues polling)

   **`test/fateswap/nft/wallet_mapping_test.exs`** (~8 tests)
   - register_mapping creates new mapping with both addresses
   - register_mapping updates existing mapping (same ethereum, new solana)
   - get_solana_address returns correct Solana address for known Ethereum address
   - get_solana_address returns nil for unknown Ethereum address
   - get_ethereum_address reverse lookup works correctly
   - duplicate registration for same pair → no error (upsert)
   - Ethereum address stored lowercase (normalized)
   - Solana address validated as valid base58 pubkey

   **`test/fateswap/nft/multipliers_test.exs`** (~6 tests)
   - get_multiplier returns correct weight for each NFT type (30-100)
   - get_multiplier for unknown token_id → nil or default
   - calculate_points sums multiplier weights correctly
   - calculate_points with empty list → 0
   - calculate_points with mixed types → correct sum
   - all 2,341 token IDs map to valid types

   **`test/fateswap/settler_client_nft_test.exs`** (~6 tests, with Req mock)
   - nft_register sends correct payload with HMAC headers
   - nft_register returns {:ok, tx_signature} on 200
   - nft_batch_register sends array of holders
   - nft_update_ownership sends wallet + new_points
   - nft_update_ownership returns {:ok, tx_signature} on 200
   - connection timeout → {:error, :timeout}

### Files

```
lib/fateswap/
├── nft_ownership_poller.ex
├── nft/
│   ├── wallet_mapping.ex
│   └── multipliers.ex
├── settler_client.ex              (MODIFIED — add NFT endpoints)
priv/repo/migrations/
├── 00X_create_nft_wallet_mappings.exs
└── 00X_create_nft_ownership_cache.exs
test/fateswap/
├── nft_ownership_poller_test.exs
├── nft/
│   ├── wallet_mapping_test.exs
│   └── multipliers_test.exs
└── settler_client_nft_test.exs
```

### Key Decisions
- Arbitrum polling (not websocket) — simpler, matches proven ReferralRewardPoller pattern from Blockster
- GlobalSingleton ensures only one poller instance across multi-node deployment
- Wallet mapping is user-initiated (Phase F7) — users connect both Ethereum and Solana wallets on the /nft page
- Points recalculated per-owner on each transfer (sum all NFTs they own × multiplier weight)
- 5-second poll interval (vs 1s for ReferralRewardPoller) — NFT transfers are rare, no need for sub-second latency

---

## Phase E5: Backend Services — Share Cards + Social Infrastructure

**Goal**: "Fate Receipt" share card generation (SVG → PNG), order share pages with OG meta tags, and the social sharing foundation. Every settled order becomes a shareable marketing asset.

**Prerequisites**: E2 complete (settled orders exist)

> **Source**: `docs/fateswap_branding_marketing.md` Sections 4, 5, 6, 9

### Tasks

1. **ShareCardGenerator** (`lib/fateswap/social/share_card_generator.ex`)
   - SVG EEx templates for 3 card layouts:
     - Layout A: Filled order (sell-side) — green accent, "ORDER FILLED"
     - Layout B: Not-filled order — muted red, "NOT FILLED"
     - Layout C: Buy-side filled — green accent, "DISCOUNT FILLED"
   - Card dimensions: 1200 × 630 px (1.91:1, optimal for X `summary_large_image`)
   - Brand colors: `#0A0A0F` background, `#14141A` data boxes, brand gradient conviction bar
   - Typography: Satoshi (headings), JetBrains Mono (data values)
   - Data fields: status, side, token_symbol, token_amount, target_multiplier, fill_chance_percent, sol_amount, sol_usd_value, referral_code (three-word), conviction_label, dynamic quote
   - Conviction gradient bar: fill width proportional to multiplier position (0–209 steps)
   - Bottom CTA: `fateswap.com/?ref=greedy-hodling-otter` (three-word referral code baked into card image)
   - SVG → PNG via `Resvg.svg_string_to_png_buffer/1` (~5-15ms)

2. **Dynamic quotes module** (`lib/fateswap/social/quotes.ex`)
   - Quote selection based on outcome + multiplier (from branding doc Section 3):
     - Filled <1.5x: "Safe hands. Well played."
     - Filled 1.5x–2x: "Conviction rewarded."
     - Filled 2x–5x: "The market was wrong. You weren't."
     - Filled >5x: "Legendary fill. Fate bows to conviction."
     - Not-filled <2x: "Close one. The thread was thin."
     - Not-filled 2x–5x: "Fate has spoken."
     - Not-filled >5x: "Full degen. Full respect."
     - Buy filled: "Fate loves a bargain hunter."
     - Buy not-filled: "The discount wasn't meant to be."

3. **ShareCards context** (`lib/fateswap/social/share_cards.ex`)
   - `generate_and_upload(order)` — renders SVG, converts to PNG, uploads to ImageKit/S3
   - `get_card_url(order_id)` — returns CDN URL (or generates on-the-fly if missing)
   - CDN URL format: `https://cdn.fateswap.com/cards/{order_id}.png`
   - Cards are immutable after generation (order data never changes post-settlement)
   - Cache: ETS (5 min hot cache) → ImageKit CDN (permanent)

4. **ShareCardController** (`lib/fateswap_web/controllers/share_card_controller.ex`)
   - `GET /order/:order_id/card.png` — serves card PNG
   - Redirects to CDN if cached, generates on-the-fly if not
   - Response headers: `cache-control: public, max-age=31536000, immutable`

5. **Order share pages + OG meta tags**
   - `GET /order/:order_id` — LiveView page showing order details + result
   - `OrderOgMeta` plug — sets dynamic OG tags before LiveView mount:
     - `og:title`: "Order Filled — BONK at 2.4x market | FateSwap"
     - `og:description`: "Received 1.87 SOL. Fill chance was 41%. Trade at the price you believe in."
     - `og:image`: `/order/{order_id}/card.png`
     - `og:url`: includes `?ref=` parameter
   - Twitter card: `summary_large_image`
   - Root layout renders OG meta from assigns

6. **CopyToClipboard JS hook** (`assets/js/hooks/copy_to_clipboard.js`)
   - Reads `data-copy-text` attribute, copies to clipboard
   - Updates visual state on success (icon swap, text change)

### Tests (ExUnit) — ~30 test cases

   **`test/fateswap/social/share_card_generator_test.exs`** (~10 tests)
   - generate/1 returns PNG binary for filled sell-side order
   - generate/1 returns PNG binary for not-filled order
   - generate/1 returns PNG binary for buy-side filled order
   - card contains token symbol in SVG text
   - card contains multiplier value in SVG text
   - card contains fill chance percentage in SVG text
   - card contains referral code in bottom CTA
   - card contains dynamic quote matching outcome + multiplier
   - card dimensions are 1200 × 630 (parsed from PNG header)
   - card PNG is under 5 MB

   **`test/fateswap/social/share_cards_test.exs`** (~6 tests)
   - generate_and_upload/1 generates card and returns CDN URL
   - get_card_url/1 returns cached URL on second call (no regeneration)
   - get_card_url/1 for unknown order returns :error
   - cards cached in ETS with 5-min TTL
   - card URL format matches expected pattern
   - concurrent generation for same order → single generation (dedup)

   **`test/fateswap/social/quotes_test.exs`** (~6 tests)
   - quote_for filled <1.5x → "Safe hands. Well played."
   - quote_for filled 3x → "The market was wrong. You weren't."
   - quote_for not-filled >5x → "Full degen. Full respect."
   - quote_for buy-side filled → "Fate loves a bargain hunter."
   - all multiplier/outcome combinations return a non-empty string
   - quotes contain no casino language (no "bet", "win", "lose", "gamble")

   **`test/fateswap_web/controllers/share_card_controller_test.exs`** (~4 tests)
   - GET /order/:id/card.png returns 200 with content-type image/png
   - GET /order/:id/card.png returns cache-control immutable header
   - GET /order/unknown/card.png returns 404
   - card image is valid PNG (starts with PNG magic bytes)

   **`test/fateswap_web/plugs/order_og_meta_test.exs`** (~4 tests)
   - /order/:id path sets og_title assign with token + multiplier
   - /order/:id path sets og_image assign with card.png URL
   - /order/:id?ref=CODE sets og_url assign including ref parameter
   - non-order path does not set OG assigns

### Files

```
lib/fateswap/social/
├── share_card_generator.ex       # SVG template + Resvg rendering
├── share_cards.ex                # Cache management + CDN upload
└── quotes.ex                     # Dynamic quote selection
lib/fateswap_web/
├── controllers/
│   └── share_card_controller.ex  # GET /order/:id/card.png
├── plugs/
│   └── order_og_meta.ex          # Dynamic OG tags for order pages
├── live/
│   └── order_live.ex             # /order/:id share page
└── components/
    └── share_overlay.ex          # Share button overlay component (used in F5)
assets/js/hooks/
└── copy_to_clipboard.js          # Copy referral link to clipboard
priv/share_card_templates/
├── filled.svg.eex                # Filled order card template
├── not_filled.svg.eex            # Not-filled card template
└── buy_filled.svg.eex            # Buy-side filled card template
test/fateswap/social/
├── share_card_generator_test.exs
├── share_cards_test.exs
└── quotes_test.exs
test/fateswap_web/
├── controllers/share_card_controller_test.exs
└── plugs/order_og_meta_test.exs
```

---

## Phase E6: Backend Services — Automated X + Telegram Content Engine

**Goal**: Fully automated pipeline posting 10-30 tweets/day and mirrored Telegram channel posts from real on-chain activity. Zero manual effort.

**Prerequisites**: E5 complete (share cards), E2 complete (settlement service)

> **Source**: `docs/fateswap_branding_marketing.md` Sections 7, 8, 9.5

### Tasks

1. **ContentQualifier GenServer** (`lib/fateswap/social/content_qualifier.ex`)
   - Subscribes to PubSub `"fateswap:feed"` — evaluates every settled order
   - Trigger rules for tweet-worthy orders:
     - Big fill: >5 SOL value OR >3x multiplier
     - Big loss respect: >5x multiplier AND >2 SOL wagered
     - Streak: >3 consecutive fills by same wallet
     - Buy-side fill: >50% discount
   - Anti-spam safeguards:
     - Wallet cooldown: same wallet featured max once per 60 minutes
     - Token cooldown: same token in "big fill" tweets max once per 30 minutes
     - Volume floor: don't tweet orders below 0.5 SOL
     - Daily cap: hard limit of 30 tweets/day
     - Min gap: 10 minutes between any two tweets
     - Night mode: 50% frequency reduction 02:00-08:00 UTC
   - Privacy: never reveal wallet addresses in automated tweets ("Someone" as subject)

2. **XPoster module** (`lib/fateswap/social/x_poster.ex`)
   - X API v2 for tweet posting (OAuth 2.0 / Bearer token)
   - X API v1.1 for media upload (OAuth 1.0a via `oauther`)
   - `post_tweet(text, opts)` — uploads image if provided, then posts tweet
   - Rate limit handling: 429 → snooze Oban job 15 minutes
   - Environment: `X_API_KEY`, `X_API_SECRET`, `X_ACCESS_TOKEN`, `X_ACCESS_SECRET`, `X_BEARER_TOKEN`

3. **TelegramPoster module** (`lib/fateswap/social/telegram_poster.ex`)
   - Telegex library for channel posting
   - `post_fill_alert(order, card_image_url)` — photo + HTML-formatted caption
   - Channel: `@FateSwap` (or numeric ID from env)
   - Telegram-optimized formatting (shorter text, inline URL buttons)

4. **Content types & tweet templates**
   - Type 1: Big Fill Alert — "Someone just sold 25M $BONK at 3.2x market. Received: 4.8 SOL ($856)."
   - Type 2: Big Loss Respect — "Someone went for 7x on $WIF. Full degen. Full respect."
   - Type 3: Daily Stats Recap — orders, fills, volume, biggest fill, most popular token (Oban cron 00:05 UTC)
   - Type 4: Token Leaderboard — top 5 tokens by order count (Oban cron Monday 14:00 UTC)
   - Type 5: Streak Alert — "5-ORDER STREAK. Average target: 1.8x. Total received: 7.2 SOL."
   - Type 6: Milestone — every 10K orders, 10K SOL volume, 1K unique wallets
   - Type 7: "This Day in Fate" — highlight from 30 days ago (Oban cron daily)

5. **Oban workers** (`lib/fateswap/social/workers/`)
   - `PostTweet` — queue: `:social`, max_attempts: 3, snooze on 429
   - `DailyStats` — Oban cron `"5 0 * * *"` (00:05 UTC daily)
   - `WeeklyLeaderboard` — Oban cron `"0 14 * * 1"` (Monday 14:00 UTC)
   - `ThisDayInFate` — Oban cron daily, queries orders from 30 days ago

6. **Social stats tracking** — new DB table or query helpers
   - `social_posts` table: `id`, `type`, `order_id` (optional), `tweet_id` (optional), `telegram_msg_id` (optional), `posted_at`
   - Daily/weekly aggregate queries for stats and leaderboard content

### Tests (ExUnit) — ~30 test cases

   **`test/fateswap/social/content_qualifier_test.exs`** (~12 tests)
   - order > 5 SOL qualifies as big fill
   - order > 3x multiplier qualifies as big fill
   - order < 0.5 SOL does NOT qualify (volume floor)
   - filled order at 1.5x below 5 SOL does NOT qualify
   - not-filled at >5x and >2 SOL qualifies as big loss
   - not-filled at 3x does NOT qualify as big loss
   - same wallet within 60 min cooldown → rejected
   - same token within 30 min cooldown → rejected
   - daily count at 30 → rejected (cap reached)
   - min 10-min gap between posts enforced
   - night mode reduces threshold (02:00-08:00 UTC)
   - 4+ consecutive fills trigger streak alert

   **`test/fateswap/social/x_poster_test.exs`** (~6 tests, with Req mock)
   - post_tweet with text only → POST to v2/tweets with Bearer auth
   - post_tweet with image → uploads media via v1.1, posts tweet with media_id
   - post_tweet returns {:ok, tweet_id} on 201
   - post_tweet returns {:error, :rate_limited} on 429
   - media upload sends base64-encoded image
   - handles X API errors gracefully (returns {:error, reason})

   **`test/fateswap/social/telegram_poster_test.exs`** (~4 tests, with mock)
   - post_fill_alert sends photo with HTML caption to channel
   - caption contains token symbol, multiplier, SOL amount
   - caption contains dynamic quote from quotes module
   - handles Telegram API errors gracefully

   **`test/fateswap/social/workers/post_tweet_test.exs`** (~4 tests, Oban.Testing)
   - job performs tweet posting via XPoster
   - 429 response → job snoozed for 15 minutes
   - non-retryable error → job fails after max_attempts
   - job includes tweet_text and image_url in args

   **`test/fateswap/social/workers/daily_stats_test.exs`** (~4 tests, Oban.Testing)
   - generates correct stats from last 24h of orders
   - tweet includes: order count, fill count, fill %, volume in SOL + USD, biggest fill, most popular token
   - no orders in 24h → still posts with zero stats
   - enqueues PostTweet job with formatted text + no image

### Files

```
lib/fateswap/social/
├── content_qualifier.ex          # GenServer: tweet-worthiness rules
├── x_poster.ex                   # X API v2 posting + v1.1 media upload
├── telegram_poster.ex            # Telegex channel posting
└── workers/
    ├── post_tweet.ex             # Oban worker: scheduled tweet/telegram posting
    ├── daily_stats.ex            # Oban cron: 24h recap
    ├── weekly_leaderboard.ex     # Oban cron: weekly top tokens
    └── this_day_in_fate.ex       # Oban cron: 30-day-ago highlight
priv/repo/migrations/
└── 00X_create_social_posts.exs   # Social posting log
test/fateswap/social/
├── content_qualifier_test.exs
├── x_poster_test.exs
├── telegram_poster_test.exs
└── workers/
    ├── post_tweet_test.exs
    └── daily_stats_test.exs
```

### Key Decisions
- X API Free tier (500 posts/month) sufficient at launch; upgrade to Basic ($200/mo) at scale
- `oauther` for OAuth 1.0a signing (X media upload requires 1.0a, tweet posting uses Bearer)
- Oban for all scheduling — cron for recurring, standard jobs for event-triggered
- Share cards double as tweet images — same PNG used in user sharing and automated posts
- Privacy: automated tweets use "Someone", never wallet addresses
- Telegram mirrors X content with shorter formatting, no duplicate content creation needed

---

## Phase F1: Frontend — Wallet Connection + Auth Flow

**Goal**: SolanaWallet JS hook that connects to Phantom/Solflare/Backpack and completes SIWS authentication.

**Prerequisites**: E1 complete (auth backend)

### Tasks

1. **NPM dependencies**
   - `@solana/web3.js` ^1.95, `@wallet-standard/app`, `@coral-xyz/anchor` ^0.31, `@solana/spl-token`, `buffer`
   - Configure Buffer polyfill: `window.Buffer = Buffer`

2. **SolanaWallet JS hook** (`assets/js/hooks/solana_wallet.js`)
   - On mount: `getWallets()` from `@wallet-standard/app` → discover available wallets
   - Push wallet list to LiveView (`pushEvent("wallets_detected", {wallets})`)
   - On "Connect" click: `wallet.features['standard:connect'].connect()` → push pubkey
   - On auth challenge (from server): `wallet.features['solana:signMessage'].signMessage(...)` → push signature
   - On disconnect: `pushEvent("wallet_disconnected")`
   - On wallet switch: disconnect + reconnect (full re-auth)
   - Expose wallet ref on `window.__solanaWallet` for trade hook
   - Handle both desktop (injected provider) and mobile (deeplink) flows

3. **LiveView auth integration** (`lib/fateswap_web/live/trade_live.ex`)
   - `handle_event("wallets_detected", ...)` — store in assigns
   - `handle_event("wallet_connected", ...)` — generate SIWS challenge, push to JS hook
   - `handle_event("signature_submitted", ...)` — verify Ed25519, create session
   - `handle_event("wallet_disconnected", ...)` — clear session

4. **Wallet UI components**
   - Connect button (shows wallet list dropdown)
   - Connected state (truncated address, disconnect button)
   - Wallet selector modal (if multiple wallets available)

### Tests (ExUnit + LiveViewTest) — ~20 test cases

   **`test/fateswap_web/live/trade_live_auth_test.exs`** (~12 tests)
   - mount without session → renders "Connect Wallet" button, no wallet assigned
   - mount with valid session → wallet_address assigned, connected UI shown
   - "wallet_connected" event with valid pubkey → generates challenge, pushes to JS hook
   - "wallet_connected" event with invalid pubkey (not 32 bytes base58) → error flash
   - "signature_submitted" with valid signature → creates session, assigns wallet, flashes success
   - "signature_submitted" with invalid signature → error flash, no session created
   - "signature_submitted" with expired nonce → error flash
   - "wallet_disconnected" event → clears session, reverts to "Connect Wallet" state
   - authenticated user sees truncated wallet address in nav
   - page renders wallet connect button component
   - double mount (LiveView double-mount pattern) → only one challenge generated
   - session persists across page navigation (mount with existing session)

   **`test/fateswap_web/components/wallet_components_test.exs`** (~8 tests)
   - connect_button/1 renders "Connect Wallet" when not connected
   - connect_button/1 renders truncated address + disconnect when connected
   - wallet address truncated correctly: "Ab12...xY9z" format
   - wallet_selector_modal/1 renders wallet list when wallets available
   - wallet_selector_modal/1 shows "No wallets detected" when empty
   - disconnect button triggers "wallet_disconnected" event
   - connect button has cursor-pointer class
   - connected state shows wallet icon

### Files

```
assets/js/hooks/solana_wallet.js    (NEW)
assets/js/hooks/index.js            (NEW) — hook registry
lib/fateswap_web/live/trade_live.ex (NEW)
lib/fateswap_web/components/wallet_components.ex (NEW)
test/fateswap_web/live/trade_live_auth_test.exs (NEW)
test/fateswap_web/components/wallet_components_test.exs (NEW)
```

---

## Phase F2: Frontend — Trading UI (Sell-Side) + Brand Language

**Goal**: The main DEX-style swap card with fate slider, probability ring, sell-side transaction flow, and full brand language integration from `docs/fateswap_branding_marketing.md`.

**Prerequisites**: F1 complete, E2 complete, N1 complete, S4 complete (devnet program)

> **UI**: Use `/frontend-design` skill for all component design. Reference brand spec in `docs/fateswap_branding_marketing.md` Section 1 (Visual Identity) and Section 3 (In-Product Language).

### Tasks

1. **Swap card layout** (LiveView template — use `/frontend-design`)
   - Mode toggle: "Sell High" / "Buy Low" (`phx-click="toggle_mode"`)
   - Token selector trigger (shows current token + amount input)
   - Fate slider (target price / multiplier)
   - Probability ring (fill chance visualization)
   - Payout card (computed SOL output)
   - CTA button ("Submit Fate Order" — never "Place Bet")
   - Brand colors: card `bg-[#14141A] border border-white/[0.06]` on `bg-[#0A0A0F]` page
   - Typography: Satoshi for labels, JetBrains Mono for data values

2. **In-product language system** (from branding doc Section 3)
   - Core term mapping enforced in all copy — never use casino language:
     - "Set your price" not "Place your bet"
     - "Fill chance" not "Win chance"
     - "Fate fee" not "House edge"
     - "Order filled" not "You won"
     - "Not filled — tokens claimed by fate" not "You lost"
   - Slider personality tiers (dynamic copy as slider moves):
     - 1.01x–1.24x: "Safe Limit" / "Almost a regular swap."
     - 1.25x–1.49x: "Optimistic" / "You see something the market doesn't."
     - 1.50x–1.99x: "Conviction" / "Bold. Let's see if fate agrees."
     - 2.00x–4.99x: "Moonshot" / "This is what conviction looks like."
     - 5.00x–10.0x: "Full Degen" / "You're either a genius or a legend."

3. **FateSlider JS hook** (`assets/js/hooks/fate_slider.js`)
   - HTML `<input type="range" min="0" max="209" step="1">` — maps index 0–209 to the 210 allowed multiplier BPS values
   - JS lookup array: `MULTIPLIER_STEPS[index]` returns the BPS value for display + server push
   - Track gradient: brand gradient `#22C55E` → `#EAB308` → `#EF4444` (left to right, safe to risky)
   - Client-side updates on every `input` event (no server round-trip):
     - Multiplier label (1.01x → 10.0x, formatted per tier precision)
     - Fill chance percentage
     - Probability ring arc
     - Conviction tier label + subtitle (from personality tiers above)
   - Push final multiplier_bps to server on `change` (debounced 150ms)

4. **ProbabilityRing** (SVG, controlled by FateSlider)
   - Two `<circle>` elements: background track + filled arc
   - `stroke-dashoffset` driven by fill chance
   - HSL color interpolation: `hsl(120 - pct*120, 80%, 50%)` — green at safe, red at risky
   - Large center text: fill chance percentage

5. **FateSwapTrade JS hook** (`assets/js/hooks/fateswap_trade.js`)
   - Sell-side flow:
     1. Receive instruction data from LiveView (`handleEvent("build_and_sign_tx", ...)`)
     2. Deserialize Jupiter swap instructions
     3. Build `place_fate_order` instruction via Anchor client (IDL)
     4. Compose into single `VersionedTransaction` with Address Lookup Tables
     5. `wallet.features['solana:signTransaction'].signTransaction(tx)`
     6. `connection.sendRawTransaction(signedTx)`
     7. Push `{signature, status}` to LiveView (`pushEvent("tx_result", ...)`)

6. **Server-side trade handling** (`trade_live.ex`)
   - `handle_event("place_fate_order", ...)`:
     1. Validate inputs (amount, multiplier, token)
     2. Generate seed, compute commitment via SeedManager
     3. Submit commitment via fate-settler
     4. Fetch Jupiter quote + swap instructions (server-side via Req)
     5. Push instruction data to JS hook
   - `handle_event("tx_result", ...)`:
     1. Record order in PostgreSQL
     2. Trigger settlement via SettlementService
   - `handle_event("order_placed", ...)` — client confirms TX landed, trigger settlement

7. **Result overlay** (LiveView + CSS animations — use `/frontend-design`)
   - Filled: green `#22C55E` accent, "ORDER FILLED" + dynamic quote from branding doc
   - Not Filled: muted red `#8B2500` accent, "NOT FILLED — Tokens claimed by fate"
   - Stats row: SOL received/would-have, fill chance %, target multiplier
   - Dynamic quotes based on outcome + multiplier (see branding doc Section 3)
   - Share buttons: [Share on X] [Share on Telegram] [Copy Link] [Download Card] (implemented in F5)
   - Provably fair "Verify" link
   - CSS `@keyframes fadeInScale` for entrance

### Tests (ExUnit + LiveViewTest) — ~36 test cases

   **`test/fateswap_web/live/trade_live_sell_test.exs`** (~18 tests, with mocked settler_client + seed_manager)
   - mount renders swap card with "Sell High" mode active by default
   - "toggle_mode" event switches to "Buy Low" and back
   - swap card shows token selector trigger, amount input, fate slider, CTA button
   - "update_multiplier" event updates multiplier assign and recomputes fill_chance + payout
   - fill_chance computed correctly: (100000 * (10000 - 150)) / multiplier_bps / 100 as percentage
   - payout computed correctly: sol_amount * multiplier_bps / 100000
   - CTA button disabled when wallet not connected
   - CTA button disabled when amount is 0 or empty
   - CTA button disabled when no token selected
   - "place_fate_order" event with valid inputs → generates seed, submits commitment, pushes TX data to JS hook
   - "place_fate_order" event with amount below min_bet → error flash
   - "place_fate_order" event without wallet → error flash
   - "tx_result" event with success → records order in DB, triggers settlement
   - "tx_result" event with failure → error flash, no DB record
   - settlement result received via PubSub → shows result overlay
   - result overlay shows "ORDER FILLED" with payout and dynamic quote for wins
   - result overlay shows "NOT FILLED — Tokens claimed by fate" for losses
   - result overlay includes "Verify this order" link

   **`test/fateswap_web/live/trade_live_branding_test.exs`** (~6 tests)
   - slider at 1.10x shows "Safe Limit" conviction tier label
   - slider at 1.40x shows "Optimistic" conviction tier label
   - slider at 1.75x shows "Conviction" conviction tier label
   - slider at 3.00x shows "Moonshot" conviction tier label
   - slider at 7.00x shows "Full Degen" conviction tier label
   - CTA button text is "Submit Fate Order" (not "Place Bet")

   **`test/fateswap_web/live/trade_live_result_overlay_test.exs`** (~12 tests)
   - filled result shows green (#22C55E) accent
   - not-filled result shows muted red (#8B2500) accent
   - filled at 1.2x quote: "Safe hands. Well played."
   - filled at 1.8x quote: "Conviction rewarded."
   - filled at 3.5x quote: "The market was wrong. You weren't."
   - filled at 7x quote: "Legendary fill. Fate bows to conviction."
   - not-filled at 1.5x quote: "Close one. The thread was thin."
   - not-filled at 3x quote: "Fate has spoken."
   - not-filled at 8x quote: "Full degen. Full respect."
   - stats row shows SOL amount, fill chance %, target multiplier
   - share buttons placeholder rendered (X, Telegram, Copy, Download)
   - result overlay has fadeInScale animation class

   **`test/fateswap_web/components/trade_components_test.exs`** (~12 tests)
   - swap_card/1 renders all expected elements (token area, amount input, slider, payout, CTA)
   - payout_display/1 shows formatted SOL amount with correct decimals
   - payout_display/1 shows USD equivalent when price available
   - fate_slider/1 renders range input with min=0, max=209, step=1 (210 discrete positions)
   - probability_display/1 shows fill chance as percentage
   - cta_button/1 shows "Submit Fate Order" text
   - cta_button/1 shows loading spinner when processing
   - result_overlay/1 renders filled result with green accent
   - result_overlay/1 renders not_filled result with neutral tone
   - result_overlay/1 includes verify link with TX signature
   - mode_toggle/1 renders both "Sell High" and "Buy Low" tabs
   - mode_toggle/1 highlights active mode

### Files

```
assets/js/hooks/fate_slider.js       (NEW)
assets/js/hooks/fateswap_trade.js    (NEW)
assets/css/slider.css                (NEW) — custom range input styles
lib/fateswap_web/live/trade_live.ex  (MODIFIED)
lib/fateswap_web/live/trade_live.html.heex (NEW)
lib/fateswap_web/components/trade_components.ex (NEW)
test/fateswap_web/live/trade_live_sell_test.exs (NEW)
test/fateswap_web/components/trade_components_test.exs (NEW)
```

### Key Decisions
- Jupiter Quote API called server-side (rate limiting, caching, API key security)
- Anchor IDL loaded in browser from static asset (`/assets/fateswap.json`)
- `@solana/web3.js` v1.x (not v2) — Anchor requires v1.x
- VersionedTransaction + ALTs required for Jupiter's 20+ accounts to fit in 1232-byte TX limit

---

## Phase F3: Frontend — Buy-Side + Partial Signing

**Goal**: Buy-side flow where player deposits raw SOL. On win, player co-signs a combined settle+swap TX to receive tokens directly.

**Prerequisites**: F2 complete, N2 complete

> **UI**: Use `/frontend-design` skill for all component design. Reference brand spec in `docs/fateswap_branding_marketing.md`.

### Tasks

1. **Buy-side trade flow** (modifications to trade_live.ex + FateSwapTrade hook)
   - No Jupiter swap before bet — player deposits raw SOL
   - `token_mint` = target memecoin address (metadata only)
   - `token_amount` = 0 (no token involved yet)
   - Simpler TX: just `place_fate_order` instruction (no Jupiter instructions)

2. **Buy-side settlement — partial signing flow**
   - SettlementService detects filled buy-side order
   - Calls fate-settler `/build-settle-and-swap` → receives partially-signed TX
   - Pushes partially-signed TX to LiveView via PubSub
   - LiveView pushes to JS hook via `push_event("co_sign_settle", ...)`
   - JS hook deserializes TX, calls `wallet.signTransaction()` → Phantom pops up
   - JS hook submits fully-signed TX
   - Fallback: if player doesn't co-sign within 30 seconds, submit settle-only TX (server-only)

3. **Mode-dependent UI updates**
   - Sell High mode: token input on top, SOL output on bottom
   - Buy Low mode: SOL input on top, token output on bottom
   - CTA text changes: "Sell at [multiplier]x" / "Buy at [discount]% off"
   - Discount-to-multiplier mapping: `multiplier = 1 / (1 - discount)`, snapped to nearest valid discrete step

### Tests (ExUnit + LiveViewTest) — ~15 test cases

   **`test/fateswap_web/live/trade_live_buy_test.exs`** (~10 tests, with mocked settler_client)
   - in "Buy Low" mode: SOL input on top, token output on bottom
   - in "Buy Low" mode: CTA text shows "Buy at X% off"
   - discount-to-multiplier mapping: 50% discount → 2.00x multiplier (exact match)
   - discount-to-multiplier mapping: 1% discount → 1.01x multiplier (exact match)
   - discount-to-multiplier mapping: 90% discount → 10.0x multiplier (exact match)
   - discount-to-multiplier mapping: 33% discount → snaps to nearest valid step (1.50x or 1.49x)
   - "place_fate_order" in buy mode: token_amount = 0, token_mint = selected token
   - "place_fate_order" in buy mode: no Jupiter swap instructions in TX data (raw SOL)
   - settlement with filled=true + buy mode + player online → pushes co_sign_settle event
   - settlement with filled=true + buy mode + fallback (30s timeout) → server-only settle
   - settlement with filled=false + buy mode → same as sell mode (server-only settle)

   **`test/fateswap/settlement_service_buy_test.exs`** (~5 tests, with mocked settler_client)
   - filled buy-side order → calls build-settle-and-swap endpoint
   - build-settle-and-swap returns partially_signed_tx → broadcasts to LiveView
   - co-sign timeout (30s) → falls back to server-only settlement
   - filled sell-side order → does NOT call build-settle-and-swap (uses regular settle)
   - not-filled buy-side order → calls regular settle (same as sell-side)

### Files (modified)

```
lib/fateswap_web/live/trade_live.ex      (MODIFIED)
lib/fateswap_web/live/trade_live.html.heex (MODIFIED)
assets/js/hooks/fateswap_trade.js        (MODIFIED)
lib/fateswap/settlement_service.ex       (MODIFIED)
test/fateswap_web/live/trade_live_buy_test.exs (NEW)
test/fateswap/settlement_service_buy_test.exs (NEW)
```

---

## Phase F4: Frontend — LP Provider Interface

**Goal**: `/pool` page for LPs to deposit SOL and receive FATE-LP tokens, withdraw, and view pool stats.

**Prerequisites**: F1 complete (wallet connection), N3 complete (account reads)

> **UI**: Use `/frontend-design` skill for all component design. Reference brand spec in `docs/fateswap_branding_marketing.md`.

### Tasks

1. **Pool LiveView** (`lib/fateswap_web/live/pool_live.ex`)
   - Fetch ClearingHouse state via fate-settler (vault balance, liability, LP supply, stats)
   - Fetch user's FATE-LP balance via fate-settler
   - Display: vault balance, available liquidity, LP token price, LP supply, house P/L, APY estimate
   - Deposit form: SOL amount → computed LP tokens to receive
   - Withdraw form: LP amount → computed SOL to receive (or "Max" button)
   - Real-time updates via PubSub on deposit/withdraw/settlement events

2. **LP transaction hooks** (extend FateSwapTrade hook or new PoolTrade hook)
   - Deposit: build `deposit_sol` instruction via Anchor, sign and submit
   - Withdraw: build `withdraw_sol` instruction (includes LP token burn), sign and submit
   - Note: user may need ATA for FATE-LP token (create if not exists)

3. **APY calculation**
   - `APY = (house_profit_30d / effective_balance) * 12 * 100`
   - Requires tracking daily snapshots in PostgreSQL (optional: computed from on-chain stats)

### Tests (ExUnit + LiveViewTest) — ~20 test cases

   **`test/fateswap_web/live/pool_live_test.exs`** (~14 tests, with mocked chain_reader)
   - mount renders pool stats: vault balance, available liquidity, LP price, LP supply
   - mount with connected wallet → fetches and displays user's FATE-LP balance
   - mount without wallet → shows "Connect wallet to deposit/withdraw"
   - pool stats display: vault balance formatted as SOL with 4 decimals
   - pool stats display: LP price formatted with 6 decimals
   - pool stats display: house P/L formatted with +/- prefix
   - APY estimate displayed (or "N/A" if insufficient data)
   - deposit form: entering SOL amount → computes and displays LP tokens to receive
   - deposit form: LP preview updates reactively on amount change
   - withdraw form: entering LP amount → computes and displays SOL to receive
   - withdraw form: "Max" button fills user's full LP balance
   - "deposit" event with valid amount → pushes deposit_sol TX data to JS hook
   - "withdraw" event with valid amount → pushes withdraw_sol TX data to JS hook
   - PubSub update refreshes pool stats in real-time

   **`test/fateswap_web/live/pool_live_math_test.exs`** (~6 tests)
   - LP tokens to receive: first deposit 1:1
   - LP tokens to receive: proportional when pool has existing LPs
   - SOL to receive on withdrawal: proportional to LP share
   - available_liquidity = vault_balance - rent_exempt - total_liability
   - LP price = effective_balance * 1e18 / lp_supply
   - LP price = 1e18 when supply is 0

### Files

```
lib/fateswap_web/live/pool_live.ex        (NEW)
lib/fateswap_web/live/pool_live.html.heex (NEW)
assets/js/hooks/pool_trade.js             (NEW)
test/fateswap_web/live/pool_live_test.exs (NEW)
test/fateswap_web/live/pool_live_math_test.exs (NEW)
```

---

## Phase F5: Frontend — Referral UI (Two-Tier) + Provably Fair Verification + Share Overlay

**Goal**: Two-tier referral link generation, dashboard with tier-1/tier-2 earnings breakdown, `/verify` page for independent outcome verification, and share overlay with fate receipt cards.

**Prerequisites**: F1 complete, E2 complete, E5 complete (share cards)

> **UI**: Use `/frontend-design` skill for all component design. Reference brand spec in `docs/fateswap_branding_marketing.md`.

### Tasks

1. **Referral system (two-tier)**
   - `FateSwap.Referrals` context module — generate three-word codes (`adjective-participle-animal`), map to wallets
   - `FateSwap.Referrals.CodeGenerator` — picks random word from each of 3 curated crypto/degen lists (40 adjectives × 40 participles × 171 animals = 273,600 combinations), retries on collision
   - URL param capture: `?ref=greedy-hodling-otter` → store in `localStorage` + session
   - On first bet: if referral code present and `player_state.referrer == default`, resolve code → wallet, call `set_referrer` instruction (auto-resolves tier-2 on-chain)
   - `/referrals` page:
     - **Tier-1 section**: direct referrals count, tier-1 earnings (referral_bps share)
     - **Tier-2 section**: indirect referrals count, tier-2 earnings (tier2_referral_bps share)
     - **Total earnings**: combined tier-1 + tier-2
     - Generate/copy referral link
     - Referred player activity table (tier-1 referrals only)
     - Visual: Alice→Bob→Carol example showing how tier-2 works

2. **Provably fair verification** (`/verify`)
   - Input: Solana TX signature (from settled order)
   - Server fetches TX via `getTransaction` RPC, parses `FateOrderSettled` event
   - Fetches corresponding `FateOrderPlaced` event (linked by order PDA)
   - Performs verification:
     1. `SHA256(server_seed) == commitment_hash` → seed was pre-committed
     2. `SHA256(server_seed || player_pubkey || nonce)` → roll value
     3. Compare roll against fill_chance threshold → matches `filled` boolean
   - Display: step-by-step verification with pass/fail for each check
   - "How it works" collapsible explainer

3. **Verification link from result overlay**
   - Every order result screen includes "Verify this order" link
   - Pre-fills the TX signature in the `/verify` page

4. **Share overlay** (uses share card infrastructure from E5)
   - Result overlay includes "Share" button → opens share overlay modal
   - Share overlay displays the generated fate receipt card (from `ShareCardGenerator`)
   - 4 share buttons:
     - **Share to X** — pre-filled tweet with quote + card image + referral link
     - **Share to Telegram** — deep link to Telegram share with card + referral link
     - **Copy Link** — copies `/order/:order_id` share URL to clipboard (via `CopyToClipboard` hook from E5)
     - **Download Card** — downloads PNG fate receipt card directly
   - Share URL embeds referral code: `fateswap.com/order/:id?ref=CODE`
   - Dynamic share copy uses brand language ("My fate was sealed..." / "Order filled!")

### Tests (ExUnit + LiveViewTest) — ~48 test cases

   **`test/fateswap/referrals_test.exs`** (~8 tests)
   - generate_referral_link/1 creates three-word code for wallet (adjective-participle-animal)
   - generate_referral_link/1 returns existing code if wallet already has one
   - get_by_code/1 returns referral link with correct referrer_wallet
   - get_by_code/1 returns nil for unknown code
   - code matches format ~r/^[a-z]+-[a-z]+-[a-z]+$/ (three lowercase words, hyphen-separated)
   - all words come from curated lists (no random strings)
   - capture_referral/2 stores referral code in session
   - get_referral_from_session/1 returns stored code
   - should_set_referrer?/2 returns true when player has no referrer and code is present

   **`test/fateswap_web/live/referrals_live_test.exs`** (~14 tests)
   - mount without wallet → redirect or "Connect wallet" message
   - mount with wallet → displays referral stats (tier-1 and tier-2 sections)
   - referral link displayed with correct format: fateswap.com/?ref=adjective-participle-animal
   - "copy_link" event → link copied notification
   - "generate_link" creates new referral link if none exists
   - tier-1 referrals count and earnings fetched from on-chain ReferralState
   - tier-2 referrals count and earnings displayed separately
   - total earnings = tier-1 + tier-2 combined
   - displays "0 referrals, 0 SOL earned" for new referrer (both tiers)
   - visiting /?ref=greedy-hodling-otter stores referral code in session
   - referred player activity table shows tier-1 referrals only
   - tier-2 explainer text visible ("Earn from your referrals' referrals")
   - Alice→Bob→Carol example renders correctly
   - earnings breakdown shows correct bps rates (0.2% tier-1, 0.1% tier-2)

   **`test/fateswap_web/live/verify_live_test.exs`** (~10 tests, with mocked chain_reader)
   - mount renders TX signature input field + "Verify" button
   - "verify" event with valid TX signature → displays verification results
   - verification shows: commitment_hash, server_seed, nonce, player, multiplier
   - step 1: SHA256(server_seed) == commitment_hash → green checkmark
   - step 2: roll value computed and displayed
   - step 3: fill_chance threshold computed and displayed
   - step 4: roll vs threshold matches filled boolean → green checkmark
   - all steps pass → overall "Verified Fair" result
   - step fails (hypothetical tampered data) → red X with explanation
   - "verify" event with invalid TX signature → error message
   - "How it works" collapsible section renders

   **`test/fateswap/provably_fair_verify_test.exs`** (~4 tests)
   - verify_order/1 with known good data → all steps pass
   - verify_order/1 with wrong server_seed → commitment check fails
   - verify_order/1 with wrong filled value → outcome check fails
   - verify_order/1 returns structured result with each step's pass/fail

   **`test/fateswap_web/live/share_overlay_test.exs`** (~12 tests)
   - result overlay "Share" button opens share overlay modal
   - share overlay renders generated fate receipt card image
   - "Share to X" button opens X intent URL with pre-filled text + card + ref link
   - "Share to Telegram" button opens Telegram share deep link
   - "Copy Link" button copies order share URL with embedded referral code
   - "Download Card" button triggers PNG download
   - share URL format: fateswap.com/order/:id?ref=greedy-hodling-otter
   - filled order uses brand language ("Order filled!" copy)
   - not-filled order uses brand language ("My fate was sealed..." copy)
   - share overlay closes on outside click or close button
   - share overlay shows for both filled and not-filled results
   - share card image has correct dimensions and loads from CDN

### Files

```
lib/fateswap/referrals.ex                   (NEW — context module)
lib/fateswap_web/live/referrals_live.ex     (NEW)
lib/fateswap_web/live/referrals_live.html.heex (NEW)
lib/fateswap_web/live/verify_live.ex        (NEW)
lib/fateswap_web/live/verify_live.html.heex (NEW)
lib/fateswap_web/components/share_overlay.ex (NEW — share overlay component)
test/fateswap/referrals_test.exs            (NEW)
test/fateswap_web/live/referrals_live_test.exs (NEW)
test/fateswap_web/live/verify_live_test.exs (NEW)
test/fateswap/provably_fair_verify_test.exs (NEW)
test/fateswap_web/live/share_overlay_test.exs (NEW)
```

---

## Phase F6: Frontend — Live Feed + Token Selector

**Goal**: Real-time trade feed and token selection modal.

**Prerequisites**: F2 complete, E3 complete

> **UI**: Use `/frontend-design` skill for all component design. Reference brand spec in `docs/fateswap_branding_marketing.md`.

### Tasks

1. **Live feed component**
   - PubSub broadcast on every order settlement (`"fateswap:feed"`)
   - LiveView Streams: `stream(:trades, initial, dom_id: &"trade-#{&1.id}")`
   - `stream_insert(socket, :trades, trade, at: 0, limit: 50)` for new items
   - Display: player (truncated wallet), token, multiplier, amount, result (filled/not filled), time
   - FeedScroll JS hook: auto-scroll, pause on hover

2. **Token selector modal**
   - LiveView component (`FateSwap.Components.TokenSelector`)
   - Search input with `phx-change` → server-side fuzzy match from ETS
   - Popular tokens shortcut row (top 5-8 by volume)
   - Token row: logo, symbol, name, price, liquidity
   - User's balance per token (if wallet connected, fetched via `getTokenAccountsByOwner`)
   - Modal toggle via LiveView assign (`@show_token_selector`)

3. **FeedScroll JS hook** (`assets/js/hooks/feed_scroll.js`)
   - Auto-scroll on new items
   - Pause auto-scroll on hover/touch
   - Resume auto-scroll on leave

### Tests (ExUnit + LiveViewTest) — ~22 test cases

   **`test/fateswap_web/components/token_selector_test.exs`** (~10 tests, with ETS token data)
   - renders token list from ETS cache
   - search input filters tokens by symbol (case-insensitive)
   - search input filters tokens by name (partial match)
   - search with no matches shows "No tokens found"
   - clicking token row sends selected token to parent LiveView
   - popular tokens shortcut row renders top tokens
   - clicking popular token shortcut selects it
   - token row displays: logo, symbol, name, price, liquidity
   - token row displays user balance when wallet connected
   - modal closes on outside click or close button

   **`test/fateswap_web/live/trade_live_feed_test.exs`** (~8 tests)
   - live feed renders on trade page
   - live feed shows recent trades (from initial stream load)
   - new settlement broadcast via PubSub → appears in feed (stream_insert at: 0)
   - feed item displays: truncated wallet, token symbol, multiplier, amount, filled/not-filled, time
   - feed limited to 50 items (oldest dropped when new arrive)
   - filled orders shown with green indicator
   - not-filled orders shown with neutral indicator
   - feed updates in real-time without page refresh

   **`test/fateswap_web/live/trade_live_token_selector_test.exs`** (~4 tests)
   - clicking token selector trigger opens modal
   - selecting token from modal → updates selected_token assign, closes modal
   - selected token displayed in swap card with logo + symbol
   - amount input clears when token changed

### Files

```
assets/js/hooks/feed_scroll.js                    (NEW)
lib/fateswap_web/components/token_selector.ex     (NEW)
lib/fateswap_web/components/feed_components.ex    (NEW)
lib/fateswap_web/live/trade_live.ex               (MODIFIED — add feed + token selector)
test/fateswap_web/components/token_selector_test.exs (NEW)
test/fateswap_web/live/trade_live_feed_test.exs   (NEW)
test/fateswap_web/live/trade_live_token_selector_test.exs (NEW)
```

---

## Phase F7: Frontend — NFT Page + Wallet Mapping _(DEFERRED — Future Upgrade)_

> **Status: DEFERRED.** NFT reward payouts are active in the smart contract (S3.5 + E4), but the frontend wallet mapping UI is deferred to a future release. NFT holders will be registered via admin/settler tooling initially.

**Goal**: `/nft` page where NFT holders connect their Ethereum and Solana wallets to enable cross-chain reward distribution.

**Prerequisites**: F1 complete (wallet connection), E4 complete (NFTOwnershipPoller)

### Tasks

1. **NFT LiveView** (`lib/fateswap_web/live/nft_live.ex`)
   - Connect Solana wallet (existing auth flow from F1)
   - Connect Ethereum wallet (MetaMask/Rabby via JS hook — separate from Solana wallet)
   - Display user's NFTs (fetched from `nft_ownership_cache` by Ethereum address)
   - Show NFT type, multiplier weight, and total points
   - Register wallet mapping: user signs a message with Ethereum wallet proving ownership
   - Show pending/claimed rewards from NFTRewarder (via fate-settler account read)
   - "Claim Rewards" button → builds `claim_reward` instruction on NFTRewarder, signs with Solana wallet

2. **EthereumWallet JS hook** (`assets/js/hooks/ethereum_wallet.js`)
   - Detect injected Ethereum provider (`window.ethereum`)
   - `eth_requestAccounts` for connection
   - `personal_sign` for wallet mapping proof
   - Push connected address to LiveView

3. **Wallet mapping flow**
   - User connects Solana wallet (existing)
   - User connects Ethereum wallet (new hook)
   - Server generates challenge message: "Link {eth_address} to {sol_address} on FateSwap"
   - User signs with Ethereum wallet (proving Ethereum ownership)
   - Server verifies Ethereum signature, creates mapping in `nft_wallet_mappings`
   - NFTOwnershipPoller detects mapping → registers holder on Solana NFTRewarder

4. **NFT display components**
   - NFT card: type badge, multiplier weight, token ID
   - Total points summary
   - Reward balance and claim button
   - Wallet linking status indicator

5. **Router update**
   - Add `/nft` route

### Tests (ExUnit + LiveViewTest) — ~20 test cases

   **`test/fateswap_web/live/nft_live_test.exs`** (~14 tests, with mocked settler_client + DB)
   - mount without wallet → shows "Connect Solana wallet" prompt
   - mount with Solana wallet → shows "Connect Ethereum wallet" prompt
   - "ethereum_connected" event → displays Ethereum address, fetches NFTs
   - user with NFTs → NFT cards displayed with type, multiplier, token ID
   - user with no NFTs → "No High Rollers NFTs found" message
   - total points calculated and displayed correctly
   - "link_wallets" event with valid Ethereum signature → creates mapping
   - "link_wallets" with invalid signature → error flash
   - already-linked wallets → shows "Wallets linked" status
   - pending reward balance displayed (from fate-settler account read)
   - "claim_reward" event → pushes claim_reward TX data to JS hook
   - "claim_reward" with 0 pending → error flash
   - /nft route renders correctly
   - wallet mapping persists across page reloads

   **`test/fateswap_web/components/nft_components_test.exs`** (~6 tests)
   - nft_card/1 renders NFT type badge with correct color
   - nft_card/1 shows multiplier weight (e.g., "50x Gold")
   - total_points_display/1 shows sum with correct formatting
   - reward_display/1 shows pending SOL amount
   - claim_button/1 disabled when no pending reward
   - wallet_status/1 shows linked/unlinked state

### Files

```
assets/js/hooks/ethereum_wallet.js              (NEW)
lib/fateswap_web/live/nft_live.ex              (NEW)
lib/fateswap_web/live/nft_live.html.heex       (NEW)
lib/fateswap_web/components/nft_components.ex  (NEW)
lib/fateswap_web/router.ex                     (MODIFIED — add /nft route)
test/fateswap_web/live/nft_live_test.exs       (NEW)
test/fateswap_web/components/nft_components_test.exs (NEW)
```

---

## Phase D1: Devnet Integration Testing

**Goal**: End-to-end testing of all components on Solana devnet.

**Prerequisites**: All S/N/E/F phases complete (excluding deferred F7)

### Tasks

1. **Devnet test environment**
   - FateSwap + NFTRewarder programs deployed on devnet (S4)
   - fate-settler running locally or on Fly.io staging
   - Phoenix app running locally connected to devnet RPC + Arbitrum RPC

2. **Test scenarios**
   - Full sell-side flow: connect wallet → select token → set multiplier → place order → settlement → verify
   - Full buy-side flow: connect wallet → set SOL amount → place order → settlement (with co-sign) → verify
   - LP flow: deposit SOL → verify LP tokens → place trades → LP price changes → withdraw
   - Referral flow (tier-1): generate link → new user visits → first bet sets referrer → loss triggers tier-1 reward
   - Referral flow (tier-2): Alice refers Bob, Bob refers Carol → Carol loses → both Alice and Bob receive rewards
   - 5-way split verification: configure all bps → lose bet → verify all 5 recipients receive correct amounts
   - NFT flow: register wallet mapping → register NFT holder on NFTRewarder → lose bet → NFT reward deposited → sync_rewards → claim reward
   - Expired order: place order → wait 5 minutes → reclaim
   - Edge cases: max bet enforcement, minimum bet, paused protocol, double-settle attempt

3. **Performance testing**
   - Measure latency: commitment → place → settle round-trip
   - Verify compute unit consumption per instruction
   - Test under concurrent load (multiple simultaneous users)

---

## Phase D2: Production Deploy (Mainnet-Beta)

**Goal**: Launch on Solana mainnet-beta with conservative limits.

**Prerequisites**: D1 complete, security review

### Tasks

1. **Security review**
   - Internal code audit of both Anchor programs (FateSwap + NFTRewarder)
   - Review all PDA derivations, access controls, arithmetic
   - Verify 5-way split math: sum of all bps deductions matches expected total
   - Verify HMAC authentication between Elixir app and fate-settler
   - Review NFTOwnershipPoller cross-chain bridge for security edge cases
   - Test all error paths and edge cases
   - Consider external audit for the Anchor programs

2. **Mainnet deployment**
   - Generate production program keypairs (FateSwap + NFTRewarder)
   - Deploy both Anchor programs to mainnet-beta
   - Initialize ClearingHouse with platform_wallet, bonus_wallet, nft_rewarder
   - Initialize NFTRewarder with fateswap_program reference
   - Deploy fate-settler to Fly.io (internal-only, production secrets)
   - Deploy Phoenix app to Fly.io (public-facing, production domain)
   - Set up PostgreSQL production database
   - Configure NFTOwnershipPoller with Arbitrum RPC endpoint

3. **Conservative launch parameters**
   - `fate_fee_bps = 150` (1.5%)
   - `max_bet_bps = 10` (0.1% of net balance)
   - `min_bet = 10_000_000` (0.01 SOL)
   - `bet_timeout = 300` (5 minutes)
   - `referral_bps = 20` (0.2% tier-1)
   - `tier2_referral_bps = 10` (0.1% tier-2)
   - `nft_reward_bps = 30` (0.3% NFT holders)
   - `platform_fee_bps = 30` (0.3% platform)
   - `bonus_bps = 10` (0.1% bonuses)
   - Initial LP seed (house bankroll) — amount TBD
   - Start with curated token list (~50 popular memecoins)

4. **Monitoring**
   - Settler wallet SOL balance alerts
   - Vault balance tracking
   - Settlement latency monitoring
   - 5-way split distribution tracking (per-recipient totals)
   - NFTOwnershipPoller health (last polled block, Arbitrum RPC errors)
   - Error rate tracking
   - On-chain event indexing for analytics

5. **Post-launch hardening**
   - Gradually increase `max_bet_bps` as vault grows
   - Expand token list based on demand
   - Monitor LP price trajectory
   - Register existing NFT holders on NFTRewarder (bulk via fate-settler)
   - Upgrade authority → multisig (Squads Protocol)
   - Eventually: `set-upgrade-authority --final` (immutable)

---

## Dependency Graph

```
S1 (ClearingHouse) → S2 (FateGame) → S3 (Referral+5-Way+Admin) → S3.5 (NFTRewarder) → S4 (Devnet Deploy)
                                                                                              │
E1 (Scaffold+Auth) ──────────────────────────────────────────────────────────                  │
      │                                                                    │                   │
      ├── E2 (Seed+Settlement) ────────────────────────────────────────────┤                   │
      │         │                                                          │                   │
      ├── E3 (Token+Price) ───────────────────────────────────────────────┤                   │
      │                                                                    │                   │
      ├── E4 (NFTOwnershipPoller) ◄── N4 ─────────────────────────────────┤                   │
      │                                                                    │                   │
      ├── E5 (Share Cards+Social) ◄── E2 ────────────────────────────────┤                   │
      │                                                                    │                   │
      ├── E6 (X+Telegram Engine) ◄── E5 + E2 ───────────────────────────┤                   │
      │                                                                    │                   │
      └── F1 (Wallet Connection) ──────────────────────────────────────────┤                   │
              │                                                            │                   │
              ├── F2 (Sell-Side+Brand) ◄───────────────────────────────────┼───────────────────┤
              │         │                                                  │                   │
              │         ├── F3 (Buy-Side) ◄──── N2 (Partial Sign)          │                   │
              │         │                                                  │                   │
              │         └── F6 (Feed+TokenSelector) ◄── E3                 │                   │
              │                                                            │                   │
              ├── F4 (LP Interface) ◄── N3 (Account Reads)                 │                   │
              │                                                            │                   │
              ├── F5 (Referral+Verify+Share) ◄── E2 + E5                   │                   │
              │                                                            │                   │
              └── [F7 (NFT Page) — DEFERRED]                               │                   │
                                                                           │                   │
N1 (fate-settler Core) ◄──────────────────────────────────────── S4 ───────┘                   │
      │                                                                                        │
      ├── N2 (Settlement+Partial Sign)                                                         │
      │                                                                                        │
      ├── N3 (Account Reads+PDA)                                                               │
      │                                                                                        │
      └── N4 (NFT Endpoints) ◄── S3.5 (NFTRewarder deployed)                                  │
                                                                                               │
D1 (Devnet Integration) ◄── All above (excl. F7) ────────────────────────────────────────────┘
      │
D2 (Mainnet Deploy) ◄── D1
```

**Parallelizable work streams:**
- **Stream 1**: S1 → S2 → S3 → S3.5 → S4 (Solana programs: FateSwap + NFTRewarder)
- **Stream 2**: E1 → E2 / E3 / E5 / E6 / F1 (Phoenix app + backend services + social infrastructure)
- **Stream 3**: N1 → N2 / N3 / N4 (fate-settler, starts after S4; N4 also requires S3.5)
- **Stream 4**: E4 (NFT bridge, starts after N4 — no frontend F7 for now)
- **Stream 5**: E5 → E6 (share cards then content engine, starts after E2)

E1 can start immediately in parallel with S1. N1 requires S3.5 (needs program IDL from anchor build). N4 additionally requires S3.5 (NFTRewarder IDL). E4 requires N4 (NFT fate-settler endpoints). E5 requires E2 (settlement data for share cards). E6 requires E5 (share card generation for social posts). F5 share overlay requires E5 (share card infrastructure). F7 is deferred — NFT payouts still work on-chain without frontend UI.

---

## Cost Estimates

| Item | One-Time | Monthly |
|------|----------|---------|
| Solana program deployments (FateSwap + NFTRewarder, rent-exempt) | ~4 SOL (~$600) | — |
| ClearingHouseState + LP Mint + RewarderState accounts | ~0.01 SOL | — |
| Fly.io: Phoenix app (1 shared-cpu) | — | ~$5 |
| Fly.io: fate-settler (1 shared-cpu) | — | ~$3 |
| Fly.io: PostgreSQL (1GB) | — | ~$7 |
| Solana RPC (Helius/Triton free tier) | — | $0 |
| Domain name | ~$15/yr | — |
| Server gas (500 bets/day) | — | ~$30 |
| Server gas (10,000 bets/day) | — | ~$600 |
| **Total (launch)** | **~$620** | **~$45** |

---

## Test Summary

### Total Test Cases: ~652

| Phase | Framework | Tests | Focus |
|-------|-----------|-------|-------|
| **S1** | bankrun (TS) | ~55 | ClearingHouse: init (with 5-way split fields), deposit (with MINIMUM_LIQUIDITY), withdraw, LP price, pause |
| **S2** | bankrun (TS) | ~77 | FateGame: commitment, place, settle (win/loss with SHA256 verification + referrer validation), expire, discrete multiplier steps (210 values), max bet |
| **S3** | bankrun (TS) | ~72 | Two-tier referral, 5-way split, admin config (12 fields), access control, double settle, overflow, full integration |
| **S3.5** | bankrun (TS) | ~30 | NFTRewarder: init, sync rewards (crank), update holder, claim reward, MasterChef math integration |
| **N1** | Jest/Vitest | ~25 | HMAC auth, commitment endpoint, settlement endpoint, Solana service |
| **N2** | Jest/Vitest | ~12 | Partial signing, Jupiter integration |
| **N3** | Jest/Vitest | ~10 | Account reads, PDA derivation |
| **N4** | Jest/Vitest | ~12 | NFT register, NFT update ownership, NFT PDA derivation |
| **E1** | ExUnit | ~37 | Auth (Ed25519 SIWS), schemas, plugs, routes, brand design system, three-word code generator |
| **E2** | ExUnit | ~45 | Seed manager, settler client, settlement service, provably fair math, Oban worker |
| **E3** | ExUnit | ~25 | Token eligibility, price tracker, chain reader |
| **E4** | ExUnit | ~30 | NFTOwnershipPoller, wallet mapping, NFT multipliers, settler client NFT endpoints |
| **E5** | ExUnit | ~30 | ShareCardGenerator (SVG→PNG), share card layouts, ShareCards context, ShareCardController, OG meta tags |
| **E6** | ExUnit | ~30 | ContentQualifier, XPoster, TelegramPoster, Oban workers, anti-spam, social posts context |
| **F1** | ExUnit + LiveViewTest | ~20 | Wallet connection events, auth flow, wallet components |
| **F2** | ExUnit + LiveViewTest | ~36 | Sell-side trading, swap card, slider, result overlay, brand language, slider personality tiers |
| **F3** | ExUnit + LiveViewTest | ~15 | Buy-side flow, partial signing, discount mapping, settlement strategies |
| **F4** | ExUnit + LiveViewTest | ~20 | Pool page, deposit/withdraw forms, LP math, real-time stats |
| **F5** | ExUnit + LiveViewTest | ~49 | Referral context (two-tier, three-word codes), referral page, verify page, provably fair, share overlay (4 buttons) |
| **F6** | ExUnit + LiveViewTest | ~22 | Token selector, live feed, stream insert, search/filter |
| | | | |
| **FUTURE** | | | |
| **F7** | ExUnit + LiveViewTest | ~20 | _(Deferred)_ NFT page, wallet mapping, NFT display, reward claiming, Ethereum wallet hook |

### Test Infrastructure

**Solana (bankrun)**:
- `solana-bankrun` for fast in-process validator (~1s startup vs ~30s)
- `anchor-bankrun` provider for Anchor program interaction
- Time manipulation via `context.setClock()` for timeout tests
- TypeScript with Mocha or Jest

**fate-settler (Node.js)**:
- Jest or Vitest
- Mock Solana RPC for unit tests
- Devnet integration tests for endpoint validation
- HMAC middleware tested in isolation

**Phoenix/LiveView (ExUnit)**:
- `Req.Test` or `Mox` for HTTP client mocking (settler_client, Jupiter API)
- `Oban.Testing` for job queue assertions
- `Phoenix.LiveViewTest` for LiveView mount, events, and DOM assertions
- ETS setup in test helpers for token eligibility and price data
- Test fixtures module for common wallet addresses, seeds, and order params
- `DataCase` for database tests, `ConnCase` for HTTP tests, `LiveViewCase` for LiveView tests

### Testing Principles

1. **Every phase includes tests** — no code ships without corresponding test coverage
2. **Mock external dependencies** — fate-settler calls, Jupiter API, Solana RPC are all mocked in unit tests
3. **Integration tests use devnet** — phases D1/D2 test real on-chain interactions
4. **Provably fair math tested exhaustively** — statistical validation over 10,000+ iterations to verify fill rates match expected probabilities within tolerance
5. **Security tests are explicit** — access control, double-settle, overflow are dedicated test files, not afterthoughts
6. **LiveView tests cover the full event cycle** — mount → user event → server processing → push_event → DOM update

---

## Open Decisions

1. **Domain name** — `fateswap.com`? `fate.exchange`? TBD
2. **Token list strategy** — Start curated (~50 popular) or full Jupiter verified scan (~500)?
3. **Initial LP seed size** — How much SOL for the house bankroll at launch?
4. **External audit** — Before or after mainnet launch? Budget? (Now covers 2 programs)
5. **Mobile deeplink testing** — Need to test Phantom/Solflare mobile wallet connection flows thoroughly
6. **Solana RPC provider** — Free tier sufficient at launch? Helius vs Triton vs public?
7. **Arbitrum RPC provider** — Free tier for NFTOwnershipPoller? Alchemy vs Infura vs public?
8. **NFT holder bulk registration** — Register all 2,341 NFTs on launch day or incremental as holders map wallets?
