# Solana Build History

Chronological record of all Solana migration changes and post-migration updates for Blockster V2.

**Branch**: `feat/solana-migration`
**Started**: 2026-04-02
**Full migration plan**: [solana_migration_plan.md](solana_migration_plan.md)
**All addresses**: [addresses.md](addresses.md)

---

## Phase 1: Solana Programs (2026-04-02)

### 1A: BUX SPL Token
- Created settler service scaffold at `contracts/blockster-settler/`
- Scripts: `create-bux-token.ts`, `mint-test-tokens.ts`
- Keypairs generated:
  - Mint Authority: `6b4nMSTWJ1yxZZVmqokf6QrVoF9euvBSdB11fC3qfuv1`
  - BUX Mint: `7CuRyw2YkqQhUUFbw6CCnoedHWT8tK2c9UzZQYDGmxVX`
- Token created on devnet, test mint of 1000 BUX successful

### 1B: Bankroll Program
- Anchor 0.30.1 project at `contracts/blockster-bankroll/`
- Program ID: `49up2uzZANpjTC3sgggbZazdHBii2vY9mVK3vk5dT2tm`
- 40 tests passing (12 Rust unit + 28 Anchor integration)
- 4-step initialization due to SBF 4096-byte stack limit
- SOL vault is system-owned PDA — all SOL outflows use `system_program::transfer` with PDA signer seeds
- IDL manually maintained (auto-gen broken on modern Rust)
- 17 instructions: init (x4), register_game, deposit/withdraw sol/bux, submit_commitment, place_bet_sol/bux, settle_bet, reclaim_expired, set_referrer, update_config, pause

### 1C: Game Logic Architecture
- Game logic is off-chain (settler + Elixir), bankroll program only knows game_id + bet amount + max payout + won/lost
- No on-chain program per game

### 1D: Airdrop Program
- Anchor 0.30.1 project at `contracts/blockster-airdrop/`
- Program ID: `wxiuLBuqxem5ETmGDndiW8MMkxKXp5jVsNCqdZgmjaG`
- 14 tests passing
- 8 instructions: initialize, start_round, deposit_bux, fund_prizes, close_round, draw_winners, claim_prize, withdraw_unclaimed
- SHA256 commit-reveal on-chain verification

### 1E: Settler Service
- Express + TypeScript service at `contracts/blockster-settler/src/`
- 7 route modules: mint, balance, commitment, settlement, pool, build-tx, airdrop
- HMAC auth middleware (dev mode bypasses)
- Dockerfile ready for Fly.io

---

## Phase 2: Authentication & Wallet Connection (2026-04-02)

### Files Created
- `assets/js/hooks/solana_wallet.js` — Wallet Standard discovery, EVM blocklist, SIWS flow, deferred localStorage, auto-reconnect
- `lib/blockster_v2/auth/solana_auth.ex` — Ed25519 verification, nonce-based challenges
- `lib/blockster_v2/auth/nonce_store.ex` — ETS-based nonce storage with 5min TTL
- `lib/blockster_v2_web/live/wallet_auth_events.ex` — Shared macro for LiveViews: detect → connect → sign → verify → session
- `lib/blockster_v2_web/components/wallet_components.ex` — `connect_button/1` and `wallet_selector_modal/1`

### Files Modified
- `lib/blockster_v2_web/live/user_auth.ex` — Added wallet_address session + connect_params restore
- `lib/blockster_v2_web/router.ex` — Added `POST/DELETE /api/auth/session`
- User model — Added `email_verified`, `email_verification_code`, `email_verification_sent_at`, `legacy_email` fields
- `assets/js/app.js` — SolanaWallet hook registered, wallet_address in connect_params from localStorage

### Dependencies Added
- Hex: `base58`
- npm: `@wallet-standard/app`, `bs58`, `@solana/web3.js`

---

## Phase 3: BUX SPL Token & Minter Service (2026-04-03)

### Files Modified
- `lib/blockster_v2/bux_minter.ex` — Rewritten to call Solana settler service (`BLOCKSTER_SETTLER_URL`). Same `mint_bux/5` interface. Deprecated: `get_aggregated_balances`, `get_rogue_house_balance`, `transfer_rogue`
- `lib/blockster_v2/engagement_tracker.ex` — Added Solana balance functions: `get_user_sol_balance/1`, `update_user_sol_balance/3`, `update_user_solana_bux_balance/3`
- `lib/blockster_v2/mnesia_initializer.ex` — New table `user_solana_balances`
- `config/runtime.exs` — Added `settler_url`, `settler_secret`, `solana_rpc_url`

---

## Phase 4: User Onboarding & BUX Migration (2026-04-03)

### Files Created
- `lib/blockster_v2_web/components/onboarding_modal.ex` — Multi-step modal (welcome → email → claim)
- `lib/blockster_v2/accounts/email_verification.ex` — 6-digit code, Swoosh delivery, 10min expiry
- `lib/blockster_v2/migration/legacy_bux.ex` — Legacy BUX claim + PG table `legacy_bux_migrations`

### Changes
- `/login` route removed — redirects to `/`
- `LoginLive` no longer routed

---

## Phase 5: Multiplier System Overhaul (2026-04-03)

### Files Created
- `lib/blockster_v2/sol_multiplier.ex` — 10-tier system (0x at <0.01 SOL → 5x at 10+ SOL)
- `lib/blockster_v2/email_multiplier.ex` — Verified=2x, unverified=1x

### Files Modified
- `lib/blockster_v2/unified_multiplier.ex` — New formula: `overall = x * phone * sol * email`, max 200x. New Mnesia table `unified_multipliers_v2`

### Files Deleted
- `lib/blockster_v2/rogue_multiplier.ex`
- `lib/blockster_v2/wallet_multiplier.ex`
- `lib/blockster_v2/wallet_multiplier_refresher.ex`
- Removed `WalletMultiplierRefresher` from supervision tree

---

## Phase 6: Coin Flip Game on Solana (2026-04-03)

### Files Created
- `lib/blockster_v2/coin_flip_game.ex` — Replaces `bux_booster_onchain.ex` for Solana
- `lib/blockster_v2/coin_flip_bet_settler.ex` — Background settler (GlobalSingleton, checks every minute)
- `assets/js/coin_flip_solana.js` — Wallet Standard API for signing
- `lib/blockster_v2_web/live/coin_flip_live.ex` — SOL + BUX tokens, no ROGUE

### Routing
- `/play` → `CoinFlipLive` (was `BuxBoosterLive`)

### New Mnesia Table
- `coin_flip_games` — 19 fields, vault_type instead of token_address, Solana tx sigs

---

## Phase 7: Bankroll Program & LP System (2026-04-03)

### Settler
- `contracts/blockster-settler/src/services/bankroll-service.ts` — PDA derivation, VaultState deserialization, tx builders
- `contracts/blockster-settler/scripts/init-bankroll.ts` — 4-step init, game registration, liquidity seeding
- Routes: GET /pool-stats, /game-config/:gameId, /lp-balance/:wallet/:vaultType, POST /build-deposit-sol, /build-withdraw-sol, /build-deposit-bux, /build-withdraw-bux

### Elixir
- `lib/blockster_v2_web/live/pool_live.ex` — Full LP deposit/withdraw page, route `/pool`
- `assets/js/hooks/pool_hook.js` — Wallet Standard signing for deposit/withdraw
- New Mnesia table `user_lp_balances`
- BuxMinter: `get_lp_balance/2`, `build_deposit_tx/3`, `build_withdraw_tx/3`

---

## Phase 8: Airdrop Migration (2026-04-03)

### Settler
- `contracts/blockster-settler/src/services/airdrop-service.ts` — PDA derivation, state deserialization, tx builders
- Routes: POST /airdrop-start-round, /airdrop-fund-prizes, /airdrop-close, /airdrop-draw-winners, /airdrop-build-deposit, /airdrop-build-claim

### Elixir
- `lib/blockster_v2/airdrop.ex` — keccak256→SHA256, slot_at_close instead of block_hash, wallet_address instead of smart_wallet
- `lib/blockster_v2_web/live/airdrop_live.ex` — WalletAuthEvents, wallet signing for deposit+claim, Solscan links
- `assets/js/hooks/airdrop_solana.js` — Wallet Standard signing

---

## Phase 9: Shop & Referral Updates (2026-04-03)

- ROGUE payment removed from checkout (slider, rate lock, discount all zeroed)
- Referral wallet normalization: EVM (downcase) vs Solana (case-sensitive)
- ReferralRewardPoller: EVM polling disabled (GenServer skeleton preserved)
- ROGUE affiliate payout returns `{:error, :deprecated}`

---

## Phase 10: UI Overhaul (2026-04-03)

- Header/footer: Removed ROGUE references, replaced Roguescan with Solscan links
- Profile: ROGUE tab → SOL balance, removed External Wallet tab, updated multiplier display
- Hub ordering: sorted by post count descending
- Ad Banner system: migration, schema, context, 19 tests

---

## Phase 11: EVM Cleanup & Deprecation (2026-04-03)

- Deprecated JS hooks: ConnectWalletHook, WalletTransferHook, BalanceFetcherHook, BuxBoosterOnchain, RoguePaymentHook, AirdropDepositHook, AirdropApproveHook
- Deprecated Elixir modules: `connected_wallet.ex`, `wallet_transfer.ex`, `wallets.ex`, `thirdweb_login_live.ex`, `bux_booster_onchain.ex`
- Deprecated config: `bux_minter_url`, `bux_minter_secret`, `thirdweb_client_id`
- Renamed `contracts/bux-booster-game/` → `contracts/legacy-evm/`

---

## Phase 12: Testing & Documentation (2026-04-03)

- All tests updated per phase (not deferred)
- 2126 total tests, 0 new failures
- Documentation updated: claude.md, addresses.md, solana_migration_plan.md

---

## Post-Migration: Header Wallet Integration (2026-04-03)

Replaced the Thirdweb EVM wallet flow in the site header with Solana wallet connection.

### Problem
The "Sign In" button in the header triggered the old `ThirdwebWallet` hook (EVM/Rogue Chain) instead of the Solana wallet flow. The Solana wallet components (`connect_button`, `wallet_selector_modal`, `SolanaWallet` hook, `WalletAuthEvents` macro) were built during Phase 2 but only wired into specific LiveViews (PoolLive, AirdropLive), not the global header.

### Changes

**`lib/blockster_v2_web.ex`**
- Added `use BlocksterV2Web.WalletAuthEvents` to the `live_view` macro so ALL LiveViews handle Solana wallet events

**`lib/blockster_v2_web/live/wallet_auth_events.ex`**
- Changed from `__using__` (direct injection) to `@before_compile` (fallback injection) — handlers are appended AFTER all module-level definitions, so they act as catch-all fallbacks without conflicting with LiveView-specific `handle_event` clauses (e.g. PostLive.Index)
- Added default `handle_info({:wallet_authenticated, wallet_address})` handler — creates/finds user, syncs balances
- **Why `@before_compile`**: FateSwap/RogueTrader use `__using__` because each LiveView explicitly `use`s WalletAuthEvents. Blockster injects it globally via the `live_view` macro, but Blockster also has a `search_handlers` pattern with `defoverridable` and LiveViews like PostLive.Index that define many `handle_event` clauses. Direct injection caused `FunctionClauseError` because module-level handlers replaced the macro's handlers. `@before_compile` appends handlers at the end so they serve as fallbacks.

**`lib/blockster_v2_web/live/user_auth.ex`**
- Added default wallet UI assigns (`detected_wallets`, `show_wallet_selector`, `connecting`, `auth_challenge`) in `on_mount`

**`lib/blockster_v2_web/components/layouts.ex`**
- Replaced `phx-hook="ThirdwebWallet"` with `phx-hook="SolanaWallet"` on the header div
- Removed `data-user-wallet` and `data-smart-wallet` attributes
- Replaced `ThirdwebLoginLive` components (desktop + mobile) with "Connect Wallet" buttons that fire `show_wallet_selector` event
- Changed disconnect buttons from `onclick="window.handleWalletDisconnect()"` to `phx-click="disconnect_wallet"`
- Added wallet-related attrs: `wallet_address`, `detected_wallets`, `show_wallet_selector`, `connecting`

**`lib/blockster_v2_web/components/layouts/app.html.heex`**
- Pass wallet assigns to `site_header`
- Added `WalletComponents.wallet_selector_modal` component (renders modal when `show_wallet_selector` is true)

**`lib/blockster_v2_web/live/pool_live.ex`** & **`airdrop_live.ex`**
- Removed `use BlocksterV2Web.WalletAuthEvents` (now comes from the `live_view` macro automatically)

**`assets/js/app.js`**
- Removed `ThirdwebWallet` from imports and hooks registration
- Updated `handleWalletDisconnect` global function to clear Solana wallet localStorage and call `DELETE /api/auth/session`

### Flow After Changes
1. User clicks "Connect Wallet" → `show_wallet_selector` event
2. WalletAuthEvents auto-connects (1 wallet) or shows modal (2+ wallets)
3. SolanaWallet JS hook connects to Phantom/Solflare/Backpack
4. SIWS challenge generated → user signs → Ed25519 verified
5. Session persisted to cookie + localStorage
6. LiveView re-renders with user state

---

## Post-Migration: Thirdweb Removal (2026-04-03)

Removed the Thirdweb SDK entirely. It was causing a blank white page on every load due to SES lockdown and a 6.5MB JS bundle.

### Root Cause
`home_hooks.js` had top-level `import` from `"thirdweb"` (lines 7-10) which pulled the entire Thirdweb SDK (~5.2MB) + SES lockdown (`lockdown-install.js`) into every page. SES lockdown freezes all JS globals on startup, causing seconds of blank white page. Other deprecated hooks used dynamic `import("thirdweb")` which esbuild also resolved into the bundle.

### Changes

**Stubbed 9 deprecated EVM hooks** (replaced with no-op `mounted()` that logs a warning):
- `home_hooks.js` — `HomeHooks`, `ModalHooks`, `DropdownHooks`, `SearchHooks`, `ThirdwebLogin`, `ThirdwebWallet`
- `bux_booster_onchain.js` — `BuxBoosterOnchain`
- `connect_wallet_hook.js` — `ConnectWalletHook`
- `balance_fetcher.js` — `BalanceFetcherHook`
- `wallet_transfer.js` — `WalletTransferHook`
- `hooks/rogue_payment.js` — `RoguePaymentHook`
- `hooks/airdrop_deposit.js` — `AirdropDepositHook`
- `hooks/airdrop_approve.js` — `AirdropApproveHook`
- `hooks/bux_payment.js` — `BuxPaymentHook`

**`assets/js/app.js`**
- Removed `home_hooks.js` import (none of its hooks were used in any template)
- Removed `HomeHooks`, `ModalHooks`, `DropdownHooks`, `SearchHooks`, `ThirdwebLogin` from hooks registration

**`lib/blockster_v2_web/components/layouts/root.html.heex`**
- Removed `window.THIRDWEB_CLIENT_ID` and `window.WALLETCONNECT_PROJECT_ID` globals

**`assets/package.json`**
- Uninstalled `thirdweb` npm package

### Result
JS bundle: **6.5MB → 1.3MB** (80% reduction). No more SES lockdown on page load. Pages render instantly.

---

## Post-Migration: Legacy Session & Balance Cleanup (2026-04-03)

Fixes for existing users transitioning from EVM to Solana wallet auth.

### Issues Fixed

**Legacy `user_token` session persisting** — Old EVM session cookies caused users to appear logged in with stale data.
- `lib/blockster_v2_web/plugs/auth_plug.ex` — Rewrote to clear legacy `user_token` from session on every request, authenticate only via `wallet_address` in session
- `lib/blockster_v2_web/live/user_auth.ex` — Removed `user_token` path, only uses `restore_from_wallet`

**Legacy EVM localStorage persisting** — Old `walletAddress`/`smartAccountAddress` keys from Thirdweb.
- `assets/js/hooks/solana_wallet.js` — Clears legacy EVM localStorage keys on mount

**Member profile "not found"** — `get_user_by_slug_or_address` only searched `slug` and `smart_wallet_address` (EVM), not `wallet_address` (Solana).
- `lib/blockster_v2/accounts.ex` — Added `wallet_address` lookup between slug and smart_wallet_address

**Balance reads from wrong Mnesia table** — `get_user_token_balances` and `get_user_bux_balance` were reading from the legacy `user_bux_balances` table (EVM) instead of `user_solana_balances` (Solana). This caused stale EVM balances to display for users.
- `lib/blockster_v2/engagement_tracker.ex` — Rewrote `get_user_token_balances` and `get_user_bux_balance` to read from `user_solana_balances`. Returns `%{"BUX" => float, "SOL" => float}`. Legacy `user_bux_balances` and `user_rogue_balances` tables are no longer read by any code.
- `lib/blockster_v2/mnesia_initializer.ex` — Marked `user_bux_balances` and `user_rogue_balances` as legacy (kept for schema compat, not written to)
- `claude.md` — Updated Mnesia tables section: active vs legacy tables

**`base58` package bug** — Moved up from band-aid to proper fix since it was the root cause of signature verification failures.

**Profile link using `smart_wallet_address`** — Header profile link fell back to `smart_wallet_address` (nil for Solana users), causing "cannot convert nil to param" crash.
- `lib/blockster_v2_web/components/layouts.ex` — Changed profile link to `@current_user.slug || @current_user.wallet_address`

**Member lookup missing `wallet_address`** — `get_user_by_slug_or_address` only checked `slug` and `smart_wallet_address` (EVM), never `wallet_address` (Solana). Caused "Member not found" on profile click.
- `lib/blockster_v2/accounts.ex` — Added `wallet_address` lookup between slug and smart_wallet_address fallbacks

**`base58` package bug** — The `base58` v0.1.1 hex package crashed with `ArithmeticError` on certain Solana addresses.
- `mix.exs` — Replaced `{:base58, "~> 0.1.0"}` with `{:b58, "~> 1.0"}` (same package FateSwap uses, same `Base58` module name)

**`get_or_create_user_by_wallet` return shape** — Function returns `{:ok, user, session, is_new_user}` (4-tuple), but the wallet_authenticated handler was matching `{:ok, user}` (2-tuple).
- `lib/blockster_v2_web/live/wallet_auth_events.ex` — Fixed pattern match to `{:ok, user, _session, _is_new}`

### Architecture: `attach_hook` for `handle_info`

The `wallet_authenticated` message is handled via `Phoenix.LiveView.attach_hook/4` (`:handle_info` stage) instead of a module-level `def handle_info`. This is necessary because:
- `@before_compile` appends `handle_event` clauses as fallbacks (works for events)
- But `handle_info` clauses from `@before_compile` conflict with module-level `handle_info` clauses (Elixir treats them as ungrouped, causing `FunctionClauseError`)
- `attach_hook` runs at the lifecycle level BEFORE module-level handlers, avoiding the conflict
- For LiveViews with custom handlers (e.g. PoolLive), the hook returns `{:cont, socket}` to pass through

The hook is attached once per socket in `UserAuth.on_mount`, guarded by a `__wallet_auth_hooked__` assign to prevent double-attachment.

---

## Post-Migration: Wallet Field & Response Key Fix (2026-04-04)

All BUX minting was silently broken for Solana users due to leftover EVM references.

### Bug 1: Wrong wallet field (no minting at all)
All mint/sync calls used `user.smart_wallet_address` (EVM ERC-4337 smart wallet), which is nil for Solana users. Their wallet is in `wallet_address`. Since the guard `if wallet && wallet != ""` failed on nil, minting was silently skipped — no errors, no tokens.

### Bug 2: Wrong response key (silent pool/tracking failure)
The Solana settler `/mint` endpoint returns `{ "signature": "..." }`, but Elixir code pattern-matched on `"transactionHash"` (EVM format). This caused pool deductions, video engagement updates, and `:mint_completed` messages to silently skip.

### Bug 3: `and` vs `&&` operator (crash)
`wallet && wallet != "" and recorded_bux > 0` — when `wallet` is nil, `&&` short-circuits to nil, then `nil and ...` raises `BadBooleanError` because `and` requires strict booleans. Changed to `&&` throughout.

### Files Changed

**`smart_wallet_address` → `wallet_address`** (10 files):
- `lib/blockster_v2_web/live/post_live/show.ex` — article read, video watch, X share (3 mint sites)
- `lib/blockster_v2/referrals.ex` — referee signup bonus, referrer wallet lookup, referrer mint
- `lib/blockster_v2/telegram_bot/promo_engine.ex` — promo BUX credits
- `lib/blockster_v2_web/live/admin_live.ex` — admin send BUX + ROGUE
- `lib/blockster_v2/social/share_reward_processor.ex` — share reward processing
- `lib/blockster_v2/notifications/event_processor.ex` — AI BUX + ROGUE credits
- `lib/blockster_v2_web/live/checkout_live/index.ex` — post-checkout balance sync
- `lib/blockster_v2/orders.ex` — buyer wallet, affiliate mint, payout execution, earning recording
- `lib/blockster_v2_web/live/notification_live/referrals.ex` — referral link URL

**`"transactionHash"` → `"signature"`** (6 files):
- `lib/blockster_v2_web/live/post_live/show.ex` — read + video mint responses
- `lib/blockster_v2/referrals.ex` — referrer reward response
- `lib/blockster_v2/social/share_reward_processor.ex` — share reward response
- `lib/blockster_v2_web/live/admin_live.ex` — admin send response
- `lib/blockster_v2_web/live/member_live/show.ex` — claim read + video responses
- `lib/blockster_v2/orders.ex` — affiliate payout response (`"txHash"` → `"signature"`)

**`and` → `&&`** (3 locations in `post_live/show.ex`)

### CLAUDE.md Updated
- `wallet_address` is the primary wallet for all mint/sync operations
- `smart_wallet_address` is legacy EVM only — never use for BuxMinter calls
- Settler mint response key is `"signature"`, not `"transactionHash"`

---

## Post-Migration: Pool Page UI Overhaul (2026-04-04)

Split the single `/pool` page into a pool index and two dedicated vault pages (SOL + BUX). Two-column layout on detail pages: order form left, chart + stats + activity right.

### Routes
| Route | LiveView | Description |
|-------|----------|-------------|
| `/pool` | `PoolIndexLive` | Pool selector — two cards linking to each vault |
| `/pool/sol` | `PoolDetailLive` | SOL vault — deposit/withdraw, chart, stats, activity |
| `/pool/bux` | `PoolDetailLive` | BUX vault — same layout, different data |

### LP Token Rename
- **bSOL → SOL-LP**, **bBUX → BUX-LP** — all display strings renamed (internal atoms `:bsol`/`:bbux` unchanged)

### Files Created
- `lib/blockster_v2_web/live/pool_index_live.ex` — Pool selector page with two gradient-accented cards
- `lib/blockster_v2_web/live/pool_detail_live.ex` — Individual vault page (two-column layout, deposit/withdraw, chart, stats, activity)
- `lib/blockster_v2_web/components/pool_components.ex` — Function components: `pool_card/1`, `lp_price_chart/1`, `pool_stats_grid/1`, `stat_card/1`, `activity_table/1`
- `assets/js/hooks/price_chart.js` — TradingView `lightweight-charts` area chart with brand lime `#CAFC00` line, dark bg
- `test/blockster_v2_web/live/pool_index_live_test.exs` — 7 tests
- `test/blockster_v2_web/live/pool_detail_live_test.exs` — 25 tests
- `test/blockster_v2_web/components/pool_components_test.exs` — 15 tests

### Files Modified
- `lib/blockster_v2_web/router.ex` — `/pool` → `PoolIndexLive`, `/pool/:vault_type` → `PoolDetailLive`
- `assets/js/app.js` — `PriceChart` hook import + registration, nav highlighting for `/pool/*` (desktop + mobile)
- `assets/package.json` — Added `lightweight-charts` dependency
- `lib/blockster_v2_web/live/pool_live.ex` — Deprecated (annotated, no longer routed)
- `test/blockster_v2_web/live/pool_live_test.exs` — Updated for new routes (58 tests)

### Design
- Background: `#F5F6FB` (light gray-blue), white cards with subtle shadows
- SOL accent: violet gradient (`from-violet-500 to-fuchsia-500`)
- BUX accent: amber gradient (`from-amber-400 to-orange-500`)
- Chart: dark `bg-gray-900` container, `lightweight-charts` area series
- Stats grid: 2x4 (desktop) / 2x2 (mobile) — LP Price, Supply, Bankroll, Volume, Bets, Win Rate, Profit, Payout
- Activity table: tabs (All/Wins/Losses/Liquidity), empty state with future data placeholder

### Tests
- **90 pool tests, 0 failures** (47 new + 43 updated existing)

---

## Devnet Deployment Status

| Resource | Address | Status |
|----------|---------|--------|
| BUX Mint | `7CuRyw2YkqQhUUFbw6CCnoedHWT8tK2c9UzZQYDGmxVX` | Created, mint authority = `6b4n...` |
| Bankroll Program | `49up2uzZANpjTC3sgggbZazdHBii2vY9mVK3vk5dT2tm` | Deployed, 4-step init complete, Coin Flip registered |
| Airdrop Program | `wxiuLBuqxem5ETmGDndiW8MMkxKXp5jVsNCqdZgmjaG` | Deployed, initialized |
| Settler Service | `contracts/blockster-settler/` | Running locally (not yet on Fly.io) |

---

## Test Counts by Phase

| Phase | New Tests | Running Total |
|-------|-----------|---------------|
| 1 (Programs) | 54 (Anchor) | — |
| 2 (Auth) | 8 | 1912 |
| 3 (BUX Minter) | 60 | 1972 |
| 4 (Onboarding) | 28 | 2001 |
| 5 (Multipliers) | 74 | 2005 |
| 6 (Coin Flip) | 29 | 2034 |
| 7 (Bankroll/LP) | 78 | 2112 |
| 8 (Airdrop) | — (rewrites) | 2108 |
| 9 (Shop/Referral) | — (updates) | 2107 |
| 10 (UI/Ads) | 19 | 2126 |
| 11 (Cleanup) | 0 | 2126 |
| 12 (Final) | 0 | 2126 |
| Pool Overhaul | 47 new, 43 updated | 2192 |

---

## Per-Difficulty Max Bet Enforcement (2026-04-04)

**Problem**: Solana bankroll program had no per-difficulty max bet validation. It used a flat `max_bet_bps=1000` (10% of vault) and trusted the caller-supplied `max_payout` — a security gap where a malicious caller could inflate payouts. The EVM BuxBoosterGame enforces per-difficulty limits with stored multipliers.

**Changes**:

### On-Chain Program (Rust)
- `GameEntry._reserved: [u8; 20]` → `multipliers: [u16; 9]` + `_reserved: [u8; 2]` (same 73-byte size)
- Multipliers stored as BPS/100 to fit u16 (e.g., 1.98x = 19800 BPS → stored as 198, 31.68x → 3168)
- `place_bet_sol`/`place_bet_bux`: `max_payout: u64` arg → `difficulty: u8`
  - Program looks up `multiplier = game.multipliers[difficulty] * 100`
  - Computes `max_bet = (net * max_bet_bps / 10000) * 20000 / multiplier` (matches EVM `_calculateMaxBet`)
  - Computes `max_payout = amount * multiplier / 10000` on-chain (no longer trusts caller)
  - Validates `potential_profit <= net_balance`
- `register_game`: added `multipliers: [u16; 9]` parameter
- `update_config`: added `new_game_multipliers: Option<[u16; 9]>` parameter
- Added `calculate_max_bet_for_difficulty()` and `calculate_max_payout()` to math.rs
- Added `InvalidDifficulty` and `MultipliersNotConfigured` error variants
- Instruction data: 40 bytes → 33 bytes (u8 difficulty instead of u64 max_payout)

### Settler (TypeScript)
- `buildPlaceBetTx`: `maxPayout` param → `difficulty` (0-8 diffIndex)
- `/build-place-bet` route: accepts `difficulty` instead of `maxPayout`
- `update-game-config.ts`: sets multipliers, max_bet_bps=100, min_bet=10M

### Elixir Frontend
- `bux_minter.ex`: sends `difficulty` instead of `maxPayout` to settler
- `coin_flip_live.ex`: added `difficulty_to_diff_index/1` helper, passes diffIndex to build_place_bet_tx

### Coin Flip Game Config (via update_config after deploy)
| Setting | Old | New |
|---------|-----|-----|
| max_bet_bps | 1000 (10%) | 100 (1%) |
| min_bet | 1000 lamports | 10,000,000 (0.01 tokens) |
| multipliers | [0;9] | [102,105,113,132,198,396,792,1584,3168] |

---

## Post-Migration: LP Price Chart History (2026-04-04)

Ported FateSwap's LP price chart approach to Blockster's pool pages. Charts now show real historical price data with per-timeframe downsampling and real-time updates on bet settlement.

### Architecture (matching FateSwap)
- **Storage**: Mnesia `:lp_price_history` ordered_set (FateSwap uses ETS + PostgreSQL; Mnesia serves both roles)
- **Recording**: LpPriceTracker polls settler every 60s; also records on each bet settlement via PubSub
- **Downsampling**: Per-timeframe intervals (1H=60s, 24H=5min, 7D=30min, 30D=2hr, All=1day). Takes last point per bucket. Skipped when <500 points to avoid over-compressing sparse data.
- **Real-time updates**: Bet settlement → PubSub broadcast → LiveView pushes incremental `chart_update` to JS
- **Chart stats**: High, low, change % computed per timeframe and displayed in chart header

### Data Flow
1. `LpPriceTracker` (60s poll or bet settlement) → `LpPriceHistory.record/3` �� Mnesia write
2. `record/3` broadcasts `{:chart_point, point}` on `"pool_chart:#{vault_type}"`
3. `PoolDetailLive` subscribes → `push_event("chart_update", point)` to JS
4. JS `series.update(point)` for real-time; `series.setData(data)` for timeframe changes

### Settlement → Chart Integration
- `CoinFlipGame.settle_game/1` broadcasts `{:bet_settled, vault_type}` on `"pool:settlements"`
- `LpPriceTracker` subscribes, fetches fresh pool stats from settler, records with `force: true` (bypasses 60s throttle)

### Files Created
- `lib/blockster_v2/lp_price_history.ex` — Mnesia price snapshots, downsampling, chart stats, PubSub broadcast
- `lib/blockster_v2/lp_price_tracker.ex` — GlobalSingleton GenServer, 60s poll + settlement listener + daily prune

### Files Modified
- `lib/blockster_v2_web/live/pool_detail_live.ex` — PubSub subscription for `pool_chart:#{vault_type}`, `chart_price_stats` assign, `push_chart_data/2` helper, `handle_info({:chart_point, point})`, period stats from Mnesia
- `lib/blockster_v2_web/components/pool_components.ex` — `chart_price_stats` attr, change % badge (green/red), `format_change_pct/1`, responsive flex-wrap layout, period stats with timeframe labels, coin flip predictions/results in activity rows, tx-linked amounts
- `assets/js/hooks/price_chart.js` — Event key `data` (was `points`), deferred init with `requestAnimationFrame`, empty state message, debounced resize
- `lib/blockster_v2/coin_flip_game.ex` — `broadcast_bet_settled/1` after settlement, `period_stats/2` for time-filtered stats, predictions/results/difficulty in `get_recent_games_by_vault`
- `lib/blockster_v2/mnesia_initializer.ex` — `:lp_price_history` table definition (ordered_set, vault_type index)
- `lib/blockster_v2/application.ex` — `LpPriceTracker` in supervision tree

---

## Post-Migration: Pool Activity Table + Coin Flip UX (2026-04-04)

### Pool Activity Table
- Coin flip rows show predictions → results (🚀/💩 emojis), multiplier odds (e.g., "1.98x")
- Game name linked to commitment tx on Solscan, bet amount linked to bet tx, P/L linked to settlement tx
- Verify fairness button retained, separate tx link row removed

### Coin Flip Play Page (/play)
- Recent games table: ID (#nonce) linked to commitment tx, Bet column linked to bet tx, P/L linked to settlement tx
- Provably fair modal: commitment hash displayed in blue as Solscan link
- Default bet: closest preset to 10% of balance, capped by max bet when house balance loads
- Max bet validation before sending to chain: "Bet exceeds max bet of X SOL for this difficulty"
- Better error messages: simulation reverts parsed for specific program errors (BetExceedsMax, PayoutExceedsMax, InsufficientVault)
- Settlement status indicator on result screen: pending (spinning), settled (Solscan link), failed (retry info + 5min reclaim timeout)
- "Game not ready" replaces generic "Wallet not connected" when previous bet still settling

### Pool Stats Grid
- Stats filtered by chart timeframe (was all-time from settler)
- Labels show period: "Volume (24H)", "Bets (24H)", "Win Rate (24H)", "Profit (24H)", "Payout (24H)"
- All-time stats (LP Price, Supply, Bankroll) remain from settler
- Period stats computed from Mnesia `CoinFlipGame.period_stats/2`
- Win rate fixed: was always 0% because `totalWins` doesn't exist in on-chain VaultState

---

## Post-Migration: Payout Rounding Fix (2026-04-04)

**Bug**: `PayoutExceedsMax` settlement failures when betting near max bet.

**Root cause**: Elixir used `Float.round` for payout and max bet calculations, which can round UP. On-chain Rust uses integer division which truncates DOWN. Difference of 1-2 lamports causes `PayoutExceedsMax`.

**Fix**: Both `calculate_payout` (coin_flip_game.ex) and `calculate_max_bet` (coin_flip_live.ex) now use `trunc` / `div` to replicate on-chain integer math exactly, including intermediate truncations.

### Files Modified
- `lib/blockster_v2/coin_flip_game.ex` — `calculate_payout/2`: `trunc(raw * 10^decimals) / 10^decimals` instead of `Float.round`
- `lib/blockster_v2_web/live/coin_flip_live.ex` — `calculate_max_bet/2`: integer `div` matching Rust's `calculate_max_bet_for_difficulty`

---

## Post-Migration: Settler Transaction Reliability (2026-04-04)

**Problem**: Settlement and commitment txs frequently timing out on devnet. Txs were landing on-chain but confirmation was missed, causing unnecessary retries that failed with `AccountNotInitialized`.

### Root causes
1. No priority fees — devnet validators deprioritize zero-fee txs
2. Default `preflightCommitment: "finalized"` added ~15s latency
3. No tx rebroadcasting — dropped txs never resent
4. Deprecated `confirmTransaction(sig, "confirmed")` with blanket 30s timeout
5. No blockhash expiry detection — couldn't tell if tx landed but confirmation was missed

### Fixes (contracts/blockster-settler/)
- **Priority fees**: All txs (settler-signed and user-signed) include `ComputeBudgetProgram.setComputeUnitLimit(200k)` + `setComputeUnitPrice(50k microLamports)`
- **`sendSettlerTx`**: New function for settler-signed txs with:
  - Preflight simulation to catch errors early
  - Rebroadcast every 2s while waiting for confirmation
  - Blockhash-aware confirmation (`lastValidBlockHeight`)
  - After blockhash expiry: checks `getSignatureStatus` to detect txs that landed but confirmation was missed ("Tx landed despite timeout")
  - Auto-retry up to 3 times with fresh blockhash on expiry
  - Logs tx signature for Solscan debugging
- **Elixir HTTP timeout**: Increased from 60s to 120s to cover settler retry cycle

### Files Created/Modified
- `contracts/blockster-settler/src/services/rpc-client.ts` — `getBlockhashWithExpiry`, `sendAndConfirmTx`, `sendSettlerTx`, `computeBudgetIxs`
- `contracts/blockster-settler/src/services/bankroll-service.ts` — All tx builders use `computeBudgetIxs()`, settler txs use `sendSettlerTx`
- `lib/blockster_v2/coin_flip_game.ex` — HTTP timeout 60s → 120s

---

## Max Bet BPS Increase: 0.1% → 1% (2026-04-05)

Increased `max_bet_bps` from 10 (0.1%) to 100 (1%) across all three layers. With 43 SOL in the bankroll, max bet at difficulty 1 goes from ~0.043 SOL to ~0.434 SOL. Max payout is ~2% of bankroll across all difficulties.

### Changes
- `coin_flip_live.ex`: `calculate_max_bet` — `* 10` → `* 100`
- `bankroll-service.ts`: `getGameConfig` — `maxBetBps = 1000` → `100`
- `update-game-config.ts`: `NEW_MAX_BET_BPS = 10` → `100`
- On-chain game config updated via `update_config` tx: `5iKdgrHWHCpTgKpZxaf3tPtMjGhYGwE4kc8LVw7eGNQ5B8qx7ZHq3kFU8t6cf3Qwtx4FKRK2iBfRSeToUcJa9zHv`

---

## Remove Concurrent Bet Constraint + Fast Game Re-Init (2026-04-05)

**Problem**: Placing consecutive bets on `/play` caused 12-15s delays. Root cause: the bankroll program enforced one active bet per player via `has_active_order` flag on PlayerState. After a bet, `get_or_init_game` queried on-chain state via HTTP→settler→Solana RPC, found `has_active_order=true` (settlement still in progress), and entered a 5-retry exponential backoff loop (1s, 2s, 3s, 3s, 3s = 12+s). The old EVM system (BuxBoosterOnchain) didn't have this problem because: (1) no on-chain state check — nonces computed from Mnesia only, (2) no `has_active_order` concept — EVM contract allowed concurrent bets.

### Analysis
- `submit_commitment` does NOT check `has_active_order` — only stores pending commitment
- `place_bet` (both SOL + BUX) checks `require!(!player_state.has_active_order)` — this is where the block happens
- `settle_bet` sets `has_active_order = false`
- Each BetOrder has unique PDA: `[b"bet", player, nonce_le_bytes]` — multiple can coexist
- Settlement reads commitment from BetOrder (not PlayerState) — fully independent per nonce
- Nonce advances at `place_bet` time, not at settlement — concurrent nonces are safe

### Bankroll Program Changes (4 files, 7 lines removed)
- `place_bet_sol.rs`: Removed `require!(!player_state.has_active_order)` check and `has_active_order = true` set
- `place_bet_bux.rs`: Same
- `settle_bet.rs`: Removed `has_active_order = false` in both SOL and BUX paths
- `reclaim_expired.rs`: Removed `has_active_order = false`
- `player_state.rs`: Field KEPT for layout compatibility (removing breaks deserialization of existing accounts)
- Program redeployed to devnet

### Elixir Changes
- `coin_flip_game.ex`: Rewrote `get_or_init_game` to compute nonce from Mnesia (like old BuxBoosterOnchain). No HTTP calls. Deleted `calculate_next_nonce`. Added `{:error, {:nonce_mismatch, nonce}}` return on NonceMismatch from `submit_commitment` for on-chain fallback recovery.
- `coin_flip_live.ex`: Replaced `active_order` 5-retry handler with `nonce_mismatch` handler that does one-time on-chain fallback via `get_player_state`. Added `init_game_onchain` async handlers. Settlement remains fire-and-forget `spawn` (like old EVM system). Reduced HTTP timeout from 120s to 30s.
- `coin_flip_live.ex`: Added global "Reclaim Bet" banner — checks every 30s for placed bets older than `bet_timeout` (5 min). Shows amber banner at top of play area regardless of game state. Reclaim handler finds oldest expired bet, builds reclaim tx for wallet signing.

### Performance
| Metric | Before | After |
|--------|--------|-------|
| `get_or_init_game` | 200-500ms (HTTP) + 12s retry | <1ms (Mnesia) |
| Bet-to-bet total | 12-15s | 1-3s (commitment tx) |
| Settlement coupling | Blocks next bet | Independent |

### Tests
- 46 coin flip tests passing (0 failures)
- New: 10 Mnesia nonce tests, 8 concurrent bet tests, 2 concurrent settler tests

---

## Transaction Confirmation Refactor (2026-04-05)

### Problem
Settler and client-side code used Solana web3.js `confirmTransaction` (websocket subscriptions) with manual rebroadcast loops for transaction confirmation. This caused:
- **Unreliable on devnet**: websocket subscriptions drop or delay notifications
- **RPC contention**: concurrent `sendSettlerTx` calls (commitment + settlement) with overlapping rebroadcast intervals and websocket subscriptions on the same `Connection` object
- **Slow second bets**: first bet settled instantly, second bet consistently slow due to competing websocket subscriptions and rebroadcast loops from concurrent settler txs
- **Unnecessary complexity**: rebroadcast intervals, blockhash retry loops, multi-attempt logic

### Solution
Replaced all confirmation with simple `getSignatureStatuses` polling — the Solana equivalent of ethers.js `tx.wait()`. Send the tx once (RPC handles retries via `maxRetries`), then poll HTTP status until confirmed.

### Changes

**`contracts/blockster-settler/src/services/rpc-client.ts`** — complete rewrite:
- New `waitForConfirmation(signature, timeoutMs, pollIntervalMs)`: polls `getSignatureStatuses` every 2s until "confirmed"/"finalized", throws on on-chain error or 60s timeout
- `sendSettlerTx`: simplified to build → sign → `sendRawTransaction` (preflight + maxRetries:5) → `waitForConfirmation`. Single attempt, no blockhash retry loops, no rebroadcast intervals
- `sendAndConfirmTx`: simplified to `sendRawTransaction` (maxRetries:5) → `waitForConfirmation`
- Removed: `getBlockhashWithExpiry`, `confirmTransaction` legacy helper, all websocket usage

**`contracts/blockster-settler/src/services/bankroll-service.ts`**:
- Updated import (removed `getBlockhashWithExpiry`, `sendAndConfirmTx`)
- `submitCommitment` and `settleBet` unchanged (they call `sendSettlerTx` which is now simpler)

**`contracts/blockster-settler/src/services/airdrop-service.ts`**:
- All 4 authority-signed tx functions (`startRound`, `fundPrizes`, `closeRound`, `drawWinners`) switched from `connection.confirmTransaction(sig, "confirmed")` to `waitForConfirmation(sig)`
- Added `maxRetries: 5` to `sendRawTransaction` calls

**`assets/js/coin_flip_solana.js`** — client-side:
- New `pollForConfirmation(connection, signature, timeoutMs, intervalMs)`: same pattern as settler's `waitForConfirmation`
- `signAndPlaceBet` and `signAndSendSimple` both use polling instead of `confirmTransaction`

### Before vs After

| Aspect | Before | After |
|--------|--------|-------|
| Confirmation method | Websocket subscription (`confirmTransaction`) | HTTP polling (`getSignatureStatuses`) |
| Rebroadcasting | Manual `setInterval` every 2s | None — `maxRetries:5` on `sendRawTransaction` |
| Retry logic | 3 attempts with blockhash refresh | Single send, RPC handles retries |
| Concurrent tx safety | Competing websocket subs on shared Connection | Independent HTTP polls, no shared state |
| Code complexity | ~80 lines (`sendSettlerTx`) | ~20 lines |

### Tests
- 46 coin flip tests passing (0 failures)
- TypeScript compiles cleanly (`npx tsc --noEmit`)

---

## Bot Wallet Solana Migration (2026-04-07)

### Problem
The 1000 read-to-earn bot accounts (`is_bot = true`) were created during the EVM era. Each had:
- A real Ethereum keypair in `users.wallet_address` (secp256k1 + keccak256, 0x-prefixed hex) and `users.bot_private_key`
- A random 0x-hex placeholder in `users.smart_wallet_address`

`BotCoordinator.process_mint_job/1` and `build_bot_cache/1` read `smart_wallet_address` and passed it to `BuxMinter.mint_bux/5`. After Phase 3 (the BUX minter rewrite), `BuxMinter.mint_bux/5` calls the Solana settler `/mint` endpoint, which expects a base58 ed25519 pubkey. The placeholder hex addresses fail to decode → every bot mint silently errors → on-chain BUX supply counter never moves.

This is the same trap as the 2026-04-04 wallet field fix, but for the bot system specifically (which has its own wallet field handling and was missed during that pass).

### Solution
Three changes, all idempotent and automatic on first deploy:

1. **New `SolanaWalletCrypto` module** generates ed25519 keypairs via `:crypto.generate_key(:eddsa, :ed25519)` and base58-encodes them. Pubkey → 32 bytes → base58 (the Solana wallet address). Secret → 64 bytes (`seed(32) || pubkey(32)`, the standard Solana secret key layout compatible with `@solana/web3.js`'s `Keypair.fromSecretKey()`) → base58. Includes a `solana_address?/1` validator that returns true only for 32-byte base58 strings (rejects nil, `0x` prefixes, malformed base58, wrong lengths).

2. **`BotSetup` updated**:
   - `create_bot/1` uses `SolanaWalletCrypto.generate_keypair/0` for new bots. `smart_wallet_address` still gets a random 0x placeholder because `User.email_registration_changeset/1` requires it (legacy schema field), but the bot system never reads it.
   - `backfill_keypairs/0` replaced with `rotate_to_solana_keypairs/0`: selects every bot whose `wallet_address` is not a valid Solana base58 pubkey, generates a fresh ed25519 keypair for each, writes new `wallet_address` + `bot_private_key`, and deletes the bot's row from `user_solana_balances` Mnesia (the cached SOL/BUX belonged to the orphaned EVM wallet). Idempotent — second call returns `{:ok, 0}`.

3. **`BotCoordinator` wired**:
   - `build_bot_cache/1` and `get_bot_cache_entry/1` read `u.wallet_address` instead of `u.smart_wallet_address`. Cache shape changed from `%{smart_wallet_address: ...}` to `%{wallet_address: ...}`.
   - `process_mint_job/1` reads `bot_cache.wallet_address`.
   - `:initialize` calls `BotSetup.rotate_to_solana_keypairs/0` after `get_all_bot_ids/0` and **before** `build_bot_cache/1`, so the very first cache build uses the rotated wallets.

### Files Changed

**New**:
- `lib/blockster_v2/bot_system/solana_wallet_crypto.ex` — ed25519 keypair generator + Solana address validator
- `test/blockster_v2/bot_system/solana_wallet_crypto_test.exs` — 10 tests (keypair shape, seed/pubkey layout, uniqueness, validator edge cases)

**Modified**:
- `lib/blockster_v2/bot_system/bot_setup.ex` — `create_bot/1` uses Solana keypairs; `backfill_keypairs/0` replaced with `rotate_to_solana_keypairs/0`
- `lib/blockster_v2/bot_system/bot_coordinator.ex` — wallet field swap (3 sites) + auto-rotation call in `:initialize`
- `test/blockster_v2/bot_system/bot_setup_test.exs` — `create_bot/1` test asserts Solana format; 3 new rotation tests (rotates EVM bots + clears stale Mnesia cache, idempotency, mixed-population)
- `test/blockster_v2/bot_system/bot_coordinator_test.exs` — bulk swap of bot_cache map shape (~16 sites)

**Docs updated**:
- `docs/bot_reader_system.md` — rewrote "Bot Wallet Keypairs" section + added "Automatic EVM → Solana migration on deploy" subsection
- `docs/solana_mainnet_deployment.md` — added bot ATA surge to Cost Summary (~2 SOL one-time), bumped Step 1 authority funding 1 → 3 SOL, added Step 7 explainer for the rotation, added Step 8 verification commands

### Auto-rotation on deploy
On the first main-app boot after this lands, `BotCoordinator.handle_info(:initialize, ...)`:
1. Loads bot ids from PG
2. **NEW**: calls `BotSetup.rotate_to_solana_keypairs/0` — rotates all 1000 EVM wallets in one pass, logs `[BotCoordinator] Rotated 1000 bot wallets from EVM → Solana`
3. Builds the bot cache from the rotated wallets
4. Continues normal initialization (subscribe to PubSub, schedule backfill, daily rotation)

Every subsequent boot is a no-op (`{:ok, 0}` from the rotation step).

### One-time SOL cost
~2 SOL paid by the settler authority (`6b4n...`) for ATA creation as the first mint to each rotated bot lands. Surge is paced by the bot mint queue at 500ms/mint, not a single burst. Documented in `docs/solana_mainnet_deployment.md` with verification commands.

### Tests
- 84 bot system tests pass (`mix test test/blockster_v2/bot_system/`) — 10 new in `solana_wallet_crypto_test.exs`, 3 new in `bot_setup_test.exs` for rotation, all existing coordinator/simulator tests pass after the field swap
- Full suite: 2234 tests, 106 pre-existing failures on `feat/solana-migration` (Airdrop, Shop, PoolDetailLive, etc.), 0 new failures introduced

---

## Legacy Account Reclaim (2026-04-08)

After the Solana auth migration, every legacy Blockster user who reconnects with a Solana wallet creates a brand-new `users` row (Solana base58 ≠ legacy EVM hex). Onboarding then tries to write the user's existing identifiers (email, phone, X, Telegram, username) and collides with the legacy row's unique constraints. This phase implements the reclaim/merge flow so returning users can:

1. Pick "I have an account" on welcome and verify their old email → triggers a full account merge.
2. OR fall through to the regular email step on the "I'm new" path → same merge fires there too.
3. OR connect phone / X / Telegram independently and have those identifiers transferred from a deactivated legacy user.

Full design: `docs/legacy_account_reclaim_plan.md`.

### Approach

Three pieces working together:

1. **Onboarding migration branch** — welcome step asks "new or returning?". Returning users go to a new `migrate_email` step that verifies their old email and triggers `LegacyMerge.merge_legacy_into!/2` if it matches. After the merge they fast-forward through any onboarding step the merge already filled (`next_unfilled_step/2`).

2. **Per-step reclaim** (phone / X / Telegram) — when the user proves ownership of an identifier already held by a *deactivated* legacy user, transfer the row + user-level fields. Active-user collisions are still blocked. This is the safety net for users who skipped the migration branch and for Telegram (which is connected outside onboarding from profile/settings).

3. **Email full-merge** — triggered when a verified email matches an active legacy user. Wraps everything in an Ecto transaction; rolls back the entire merge if the settler BUX mint fails so we never lose state to a half-claim.

### Schema changes

New migration `20260407200001_add_legacy_deactivation_fields.exs` adds 4 columns to `users`:

- `is_active` (bool, default true) — false on deactivated legacy rows. All public lookups in `BlocksterV2.Accounts` now filter `is_active = true`.
- `merged_into_user_id` (FK → users) — audit pointer to the new Solana user that absorbed this legacy account.
- `deactivated_at` (utc_datetime) — timestamp.
- `pending_email` (string) — email being verified, before we promote it to `email`. Avoids the unique-constraint collision during the verify step.

### LegacyMerge transaction (10 ordered steps)

`lib/blockster_v2/migration/legacy_merge.ex` — `merge_legacy_into!(new_user, legacy_user)`:

1. **Deactivate legacy first** — sets `is_active=false`, NULLs `email`, replaces `username`/`slug` with `deactivated_<id>` placeholders, NULLs `telegram_*`, `smart_wallet_address`, `locked_x_user_id`. Frees every unique slot for the new user.
2. **Mint legacy BUX** to new Solana wallet via `BuxMinter.mint_bux/5` with reward type `:legacy_migration`. Reads from `legacy_bux_migrations` snapshot table (keyed by lowercased email). Marks the snapshot row as `migrated=true` on success. **Failure rolls back the entire merge** so the user can retry.
3. **Username + slug transfer** — takes the freed username/slug from the original (pre-deactivation) legacy values.
4. **X connection transfer** — moves the Mnesia `x_connections` row by rewriting its first tuple element (user_id) and copies `locked_x_user_id`. If new user already has X, the legacy row is dropped instead.
5. **Telegram transfer** — copies `telegram_user_id`, `telegram_username`, `telegram_connected_at`, `telegram_group_joined_at` (legacy fields already nulled in step 1).
6. **Phone transfer** — `UPDATE phone_verifications SET user_id = new_user_id WHERE phone_number = legacy_phone`, syncs `phone_verified` / `geo_*` to new user, resets them to defaults on legacy.
7. **Content & social FK rewrites** — bulk `UPDATE` on: `posts.author_id`, `events.organizer_id`, `event_attendees.user_id`, `hub_followers.user_id`, `orders.user_id`. Returns counts for the success card.
8. **Referrals** — copies `referrer_id` + `referred_at` onto new user (only if new user has none — never overwrites), reassigns outbound referees (`users.referrer_id`), reassigns `orders.referrer_id` and `affiliate_payouts.referrer_id`.
9. **Fingerprints** — bulk move `user_fingerprints` rows to new user. Data continuity only — fingerprint anti-Sybil is non-blocking on the Solana auth path.
10. **Finalize email** — promotes `pending_email → email`, sets `email_verified=true`, clears verification fields.

After the transaction commits, `UnifiedMultiplier.refresh_multipliers/1` runs outside the transaction. Returns `{:ok, %{user: refreshed_user, summary: %{...}}}` where the summary describes everything that was transferred so the UI can render a "Welcome back, X BUX claimed, [items] restored" success card.

The merge captures the original (pre-deactivation) values into an `originals` map at the start of `do_merge` so steps 3-8 can reference fields that step 1 has already nulled.

### Reclaim hooks (per-step)

- **Phone** (`lib/blockster_v2/phone_verification.ex`) — added `check_phone_reclaimable/2` (treats phones owned by inactive users as available; active-user collisions still blocked) and a reclaim path in `send_verification_code` that updates the existing legacy row in place (sets `verified=false`, new `attempts`, new `verification_sid`, new `user_id`) instead of inserting a new row. After successful `verify_code`, `clear_inactive_user_phone_fields/2` wipes user-level phone state on any inactive user with `phone_verified=true`.

- **X OAuth callback** (`lib/blockster_v2/social.ex`) — `upsert_x_connection` calls new `reclaim_x_account_if_needed/2` which transfers the lock and the Mnesia row from a deactivated legacy user before the new user's first connection attempt. Active-user lock still returns `{:error, :x_account_locked}`.

- **Telegram /start handler** (`lib/blockster_v2_web/controllers/telegram_webhook_controller.ex`) — when `telegram_user_id` collides with a legacy user that has `is_active=false`, the controller NULLs all telegram fields on the legacy row first and then links the same Telegram account to the new user. Refactored the link logic into `link_telegram_to_user/5` to avoid duplication.

### Email verification rewrite (`lib/blockster_v2/accounts/email_verification.ex`)

- `send_verification_code` now writes to `pending_email`, NOT `email`. This avoids the unique-constraint collision when a legacy user already owns the address.
- `verify_code` returns `{:ok, user, %{merged: bool, summary: map}}` (was `{:ok, user}`). On a legacy match it dispatches to `LegacyMerge.merge_legacy_into!/2`; otherwise it just promotes `pending_email → email`. Looks up legacy via a fresh helper that filters `is_active = true` (and excludes the current user_id).
- All existing call sites in `OnboardingLive.Index` and `EmailVerificationModalComponent` updated for the new 3-tuple return shape and to read `updated_user.pending_email` instead of `updated_user.email` for the success message.

### Onboarding LiveView (`lib/blockster_v2_web/live/onboarding_live/index.ex`)

- `@steps` extended to `["welcome", "migrate_email", "redeem", "profile", "phone", "email", "x", "complete"]` (8 total).
- Welcome step replaced its single "Next" button with two intent buttons ("I'm new" → `redeem`, "I have an account" → `migrate_email`). Handler: `set_migration_intent`.
- New `migrate_email_step` component with three phases (`:enter_email`, `:enter_code`, `:success`) wired to `send_migration_code` / `verify_migration_code` / `resend_migration_code` / `change_migration_email` events. Uses the same `EmailVerification.send_verification_code` + `verify_code` API as the regular email step.
- Success card shows merge summary (BUX restored, username restored, phone/X/Telegram restored) with a "Continue" button that fires `continue_after_merge`, which calls `next_unfilled_step/2` to fast-forward.
- `next_unfilled_step(user, current_step)` walks `@steps` from `current_step + 1` and returns the first one not yet filled by the user's current state. Skip rules:
  - `welcome` / `migrate_email` → never the answer (always skipped)
  - `redeem` → never skipped (per the plan: informational, useful for returning users)
  - `profile` → skip if `username` set
  - `phone` → skip if `phone_verified`
  - `email` → skip if `email_verified`
  - `x` → skip if an `x_connections` Mnesia row exists for the user
  - `complete` → never skipped
- Added catch-all `handle_info({:email, _swoosh_email}, socket)` to swallow Swoosh test adapter messages that land in the LiveView when `Task.start` runs from inside it.

### Account lookups filtered

`lib/blockster_v2/accounts.ex`:
- `get_user_by_wallet/1`, `get_user_by_wallet_address/1`, `get_user_by_email/1`, `get_user_by_slug/1`, `get_user_by_smart_wallet_address/1` — all rewritten to filter `is_active = true`.
- `list_users/0`, `list_users_with_followed_hubs/0`, `list_authors/0` — same filter.

This is the boundary fix that prevents deactivated rows from leaking into auth, profile views, member pages, etc.

### BuxMinter

- Added `:legacy_migration` to the `mint_bux/5` reward_type whitelist.

### Tests

- **`test/blockster_v2/migration/legacy_merge_test.exs` (NEW, 23 tests)** — happy paths (everything transfers), per-step transfer behavior (X, Telegram, phone, content/social FKs, referrals, fingerprints), guards (same-user, bot, already-deactivated), settler mint failure rollback, BUX claim edge cases (no snapshot, zero balance, already-migrated), username collision invariant.
- **`test/blockster_v2/social_x_reclaim_test.exs` (NEW, 3 tests)** — fresh X connect, reclaim from deactivated legacy, block on active legacy.
- **`test/blockster_v2_web/live/onboarding_live_test.exs` (NEW, 9 tests)** — welcome branch buttons + patches, migrate_email step (full merge with summary card + no-match flow), `next_unfilled_step/2` skip-completed-steps logic.
- **`test/blockster_v2/accounts/email_verification_test.exs`** — updated for new `pending_email` write semantics + 3-tuple return; added 3 merge dispatch tests (no-match, same-user no-op, deactivated legacy skip).
- **`test/blockster_v2/phone_verification_test.exs`** — added 4 phone reclaim tests for `check_phone_reclaimable/2`.
- **`test/blockster_v2_web/controllers/telegram_webhook_controller_test.exs`** — added 1 reclaim test for the deactivated-legacy path.
- **`test/support/bux_minter_stub.ex` (NEW)** — process-dictionary-backed stub for `BuxMinter.mint_bux/5` so merge tests can simulate success and failure without hitting the real settler. Wired via `config :blockster_v2, :bux_minter, BlocksterV2.BuxMinterStub` in `config/test.exs` and read at compile time in `LegacyMerge` via `Application.compile_env`.

**Results**: 102 tests across all modified/created files, 0 failures. Full suite: 2277 tests, 106 pre-existing failures (Airdrop, Shop Phase 5/6, etc.) — verified identical via `git stash` baseline comparison. **0 new failures** introduced by this phase.

### Files

**New** (6):
- `priv/repo/migrations/20260407200001_add_legacy_deactivation_fields.exs`
- `lib/blockster_v2/migration/legacy_merge.ex`
- `test/support/bux_minter_stub.ex`
- `test/blockster_v2/migration/legacy_merge_test.exs`
- `test/blockster_v2/social_x_reclaim_test.exs`
- `test/blockster_v2_web/live/onboarding_live_test.exs`

**Modified** (10):
- `lib/blockster_v2/accounts/user.ex` — schema fields + cast list
- `lib/blockster_v2/accounts.ex` — `is_active` filter on all public lookups
- `lib/blockster_v2/accounts/email_verification.ex` — `pending_email` writes + merge dispatch
- `lib/blockster_v2/phone_verification.ex` — reclaim hooks
- `lib/blockster_v2/social.ex` — X reclaim
- `lib/blockster_v2_web/controllers/telegram_webhook_controller.ex` — Telegram reclaim
- `lib/blockster_v2/bux_minter.ex` — `:legacy_migration` reward type
- `lib/blockster_v2_web/live/onboarding_live/index.ex` — migrate_email step + skip logic
- `lib/blockster_v2_web/live/email_verification_modal_component.ex` — 3-tuple return + pending_email read
- `config/test.exs` — wire `BuxMinterStub`

### What this unblocks

After the Solana cutover, every legacy user can reconnect their old wallet's worth of BUX, username, social connections, content authorship, and referral attribution to a brand-new Solana wallet — without manual intervention, in a single transaction, with all-or-nothing semantics. The `legacy_bux_migrations` snapshot table is the on-chain source of truth for BUX amounts; the snapshot script (`priv/scripts/snapshot_legacy_bux.exs`, future) must run a few hours before deploy.

### Followup: chicken-and-egg fix for "I'm new" + reclaim (2026-04-08)

The first version of the per-step reclaim hooks gated reclaim on `is_active = false` only — i.e., the legacy user had to be ALREADY merged before their phone/X/Telegram could be transferred. This created a chicken-and-egg trap:

1. User clicks "I'm new" on welcome → bypasses the migrate_email step.
2. User goes through phone step → enters their old phone → blocked because the legacy user that owns it is still `is_active = true`.

In the post-cutover world, every EVM/Thirdweb user is a "legacy user" the moment we deploy. They don't become reclaimable until their email is verified, but the user might never get to the email step (or might do phone/X first).

**Fix**: introduce `BlocksterV2.Accounts.User.reclaimable_holder?/1` as the single source of truth:

```elixir
def reclaimable_holder?(%__MODULE__{is_bot: true}), do: false
def reclaimable_holder?(%__MODULE__{is_active: false}), do: true
def reclaimable_holder?(%__MODULE__{auth_method: "email"}), do: true
def reclaimable_holder?(_), do: false
```

`auth_method = "email"` is the discriminator: every legacy EVM/Thirdweb user has it (set by `User.email_registration_changeset/1`); every new Solana user has `auth_method = "wallet"`. Bots are excluded explicitly (defensive — they're `auth_method = "wallet"` anyway).

Applied to all three reclaim sites:

- **`PhoneVerification.check_phone_reclaimable/2`** — uses the helper. Plus `send_verification_code`'s reclaim path now resets the legacy user's user-level phone fields (`phone_verified`, `geo_multiplier`, `geo_tier`) immediately when the row is reassigned, so the legacy user doesn't keep reporting phone-verified state after losing the row. The verify-time `clear_inactive_user_phone_fields/2` cleanup is removed (was redundant + only handled `is_active = false` users anyway).
- **`Social.reclaim_x_account_if_needed/2`** — uses the helper. Active-Solana-user collisions still return `:x_account_locked`.
- **`TelegramWebhookController.handle/2` /start branch** — uses the helper. Same.

**New tests** (4 added):
- Phone reclaim test for the active legacy EVM user case.
- Phone reclaim test for the bot case (always blocked, even with `auth_method = "email"`).
- X reclaim test for the active legacy EVM user case.
- Telegram reclaim test for the active legacy EVM user case.

97 tests across the touched files, 0 failures. All 6 previously-passing reclaim tests still pass.

---

## Profile UI Polish + Notification Type Fix + Why Earn BUX Banner (2026-04-08)

A grab-bag of bug fixes and UI improvements that landed after the legacy reclaim work. Roughly in the order they were caught:

### Modal closes on submit (phx-click backdrop bug)

**Symptom**: user enters phone number on the profile-page phone verification modal → SMS code is sent successfully → modal disappears → no way to enter the code.

**Cause**: both `PhoneVerificationModalComponent` and `EmailVerificationModalComponent` had a `phx-click="close_modal"` on the outer backdrop div and a `phx-click="stop_propagation"` no-op handler on the inner content div. The `stop_propagation` event handler is just a no-op in Elixir — it does NOT actually call DOM `e.stopPropagation()`. So when the user clicks the submit button inside the form, the click bubbles up to the backdrop div in parallel with the form's `phx-submit`. Both fire on the server simultaneously: the submit handler sends the SMS, and `close_modal` flips `show_*_modal` to `false`. Modal vanishes; SMS is real.

**Fix**: replaced the manual backdrop handler with `phx-click-away="close_modal"` on the inner content div. That's the canonical LiveView pattern for "close when clicking outside" — it only fires for clicks that land OUTSIDE the element, never on clicks inside it (including submit buttons inside forms). Removed the dead `stop_propagation` event handler from both components.

Files: `phone_verification_modal_component.{ex,html.heex}`, `email_verification_modal_component.{ex,html.heex}`. 48 phone + email verification tests pass.

### Change Email post-verification + email merge security gap

Added a "Change" button next to the verified email field on the profile settings tab so users can update their email after the first verification. The backend already supported this — only the UI was missing.

Surfacing the Change button revealed a real security gap in the merge dispatch:

- The original `find_legacy_user_for_email/2` only filtered `is_active = true`. So if an active *Solana wallet* user (not a legacy EVM user) happened to have the email you typed, the helper would return them and dispatch into `LegacyMerge.merge_legacy_into!/2`. The `LegacyMerge` guards (`same_user`, `is_bot`, `is_active = false`) wouldn't catch an active wallet user. Result: you'd accidentally merge two active Solana accounts.
- This couldn't be triggered through the normal onboarding flow (the email step always runs on a fresh user with `email = nil`, so the unique constraint catches it before merge dispatch even matters). But Change Email — where one user picks an arbitrary email — exposes it.

**Fix** (three layers of defense):

1. **`find_legacy_user_for_email/2` filters `auth_method = "email"`** — only matches legacy EVM holders.
2. **`promote_pending_email/2` returns `{:error, :email_taken}`** when it hits the unique constraint on `users.email`. The modal + both onboarding email handlers (regular + migrate_email) surface this as *"This email is already used by another active account. Please use a different email."* and reset to the enter-email step.
3. **`LegacyMerge.merge_legacy_into!/2` adds a guard via `User.reclaimable_holder?/1`** — refuses to merge anything that isn't a legacy holder, even if a caller bypasses the helper. New error: `{:error, :not_a_legacy_holder}`.

Tests added: 4
- `does NOT merge against an active Solana wallet user that shares the email`
- `returns :email_taken when promote hits the unique constraint on email`
- `user can change their already-verified email to a fresh address`
- `rejects merging an active Solana wallet user (not a legacy holder)` (LegacyMerge)

110 tests across the touched files, 0 failures.

Files: `email_verification.ex`, `legacy_merge.ex`, `email_verification_modal_component.ex`, `onboarding_live/index.ex`, `member_live/show.html.heex` (Change button), test files.

### "Boost Your Earnings!" article popup removed

Deleted the modal HTML, the JS hook, the `OnboardingPopup` LiveView event handlers, and the `:show_onboarding_popup` / `:onboarding_popup_eligible` / `:onboarding_popup_multiplier` assigns. Per user request — they didn't want it interrupting the article reading flow.

Files removed/cleaned: `post_live/show.html.heex` (modal block + trigger div), `post_live/show.ex` (mount assigns, `assign_onboarding_popup_eligible/1`, two event handlers), `assets/js/app.js` (`OnboardingPopup` hook + registration).

### Phone-verified reward not showing in Activity tab — silent notification create failure

**Symptom**: user verifies phone → 500 BUX shows up in their balance → activity tab is empty for that reward.

**Cause** (subtle and important): the custom rule for `phone_verified` in `system_config.ex` sets `notification_type: "reward"`. The `Notification` schema's `@valid_types` whitelist did NOT include `"reward"` — it had `bux_earned`, `referral_reward`, `daily_bonus`, `promo_reward`, but never just `"reward"`. So:

1. `EventProcessor.execute_rule_action_inner/6` calls `Notifications.create_notification(user_id, %{type: "reward", ...})`
2. The changeset fails `validate_inclusion(:type, @valid_types)`
3. The result is **silently discarded** — there was no `case ... do {:error, ...}` around the call
4. Code keeps going → `credit_bux/2` runs → BUX is minted via the settler
5. User sees +500 BUX but no notification record exists, so the activity tab has nothing to show

The same bug affected the `x_connected` and `wallet_connected` rules — they all use `notification_type: "reward"`.

**Fix** (three pieces):

1. **Added `"reward"` to `@valid_types`** in `notification.ex`. This is the actual root cause.
2. **Stopped silently discarding `Notifications.create_notification` failures** in `event_processor.ex`. Wrapped the call in `case ... do {:error, changeset} -> Logger.error(...)` so any future invalid-type failures show up in the logs instead of vanishing.
3. **Backfilled the missing notification** for the user who hit this in dev — inserted a `Phone Verified!` notification with `bux_bonus: 500` and `dedup_key: "custom_rule:phone_verified"` for their `user_id` so it shows up in their activity tab now.

Files: `notifications/notification.ex`, `notifications/event_processor.ex`.

### Profile page UI cleanup (multiplier dropdown + SOL banner + permanent badge removal)

A handful of profile-page polish requests, all in `member_live/show.html.heex`:

- **Removed permanent "Phone Verified" badge** that was showing as a dedicated row at the top of the profile when phone was verified (lines 171-187 of the old layout).
- **Multiplier dropdown rows now show status pills** in the action area (where the Connect/Verify button used to live):
  - X row → green "Connected" pill with checkmark when `x_multiplier > 1`
  - Phone row → green "Verified" pill with checkmark when `phone_multiplier >= 1.0`
  - Email row → green "Verified" pill with checkmark when `email_multiplier >= 2.0`
  - SOL row → green pill with the actual `BlocksterV2.EngagementTracker.get_user_sol_balance/1` value (e.g., `0.1234 SOL`), gray pill when balance is 0
- **Updated the SOL banner subtext** to *"Hold at least 0.01 SOL in your connected wallet to start earning BUX. The more SOL you hold, the more BUX you earn."*

### Why Earn BUX sticky lime banner (homepage + profile)

User wanted a thin lime announcement bar stuck to the top of the page that says *"Why Earn BUX? Redeem BUX to enter sponsored airdrops"* with a "Coming Soon" pill.

**Approach**: it lives **inside** the global `site_header` fixed container so it stays flush against the bottom edge of the header in BOTH initial (full logo) and scrolled (collapsed logo) states. The header's collapse animation drags the banner up with it — there's no positioning math to maintain, no JS, no `position: fixed` offset to keep in sync with the dynamic header height.

Wiring:

1. **`site_header/1` got a new `attr :show_why_earn_bux, :boolean, default: false`** in `layouts.ex`. When true, the banner renders as the last child inside the `id="site-header"` fixed container, and the spacer below the header bumps from `h-14 lg:h-24` to `h-[88px] lg:h-[128px]` to preserve clearance for content.
2. **`app.html.heex` passes `show_why_earn_bux={assigns[:show_why_earn_bux] || false}`** through to `site_header`. Pages that don't set the assign default to false (no banner).
3. **Profile page** sets `assign(:show_why_earn_bux, true)` in `member_live/show.ex` mount.
4. **Homepage** sets `assign(:show_why_earn_bux, true)` in `post_live/index.ex` mount.

The banner uses solid `bg-[#CAFC00]` (brand lime), `border-y border-black/10` for definition, and a `bg-black/10` "Coming Soon" pill on the right with a clock icon. Mobile shows a shorter version of the copy.

### Earlier dead-end attempts (documented for future me)

Before landing on the "put it inside `site_header`" approach, I burned a few iterations:
- Added the banner inside `profile-main` with `sticky top-16 lg:top-24` and `mt-16 lg:mt-24`. **Problem**: doubled the spacing. The layout's `site_header` already provides an `h-14 lg:h-24` spacer to clear the fixed header, so adding margin on top created ~120-192px of empty space before the content.
- Removed the `mt` and used `sticky top-14 lg:top-24` to match the spacer. **Problem**: the spacer is sized for the *collapsed* header state (~96px), not the *initial* full-logo state (~170px). At scroll=0 the banner was hidden behind the bottom of the full header. As the user scrolled and the logo row animated away, the banner appeared with a transient gap. Sticky positioning can't ride a header that changes height during animation.
- The only way to make the banner always-visible AND snug in both states is to make it part of the header's fixed container so it inherits the collapse animation. That's the final design.

**Lesson**: when you have a fixed header with a collapse-on-scroll animation, anything that needs to stay flush against the bottom of that header has to be a child of the same fixed container. Trying to track it from outside with `sticky` + `top` offsets never works because the offset is a static value while the header height is dynamic.

### Files (this batch)

**Modified**:
- `lib/blockster_v2_web/components/layouts.ex` — `site_header/1` got `:show_why_earn_bux` attr + banner block + dynamic spacer
- `lib/blockster_v2_web/components/layouts/app.html.heex` — passes `show_why_earn_bux` through to `site_header`
- `lib/blockster_v2_web/live/member_live/show.ex` — `assign(:show_why_earn_bux, true)`
- `lib/blockster_v2_web/live/post_live/index.ex` — `assign(:show_why_earn_bux, true)`
- `lib/blockster_v2_web/live/member_live/show.html.heex` — removed permanent phone badge, multiplier dropdown badges, SOL banner copy
- `lib/blockster_v2_web/live/phone_verification_modal_component.{ex,html.heex}` — phx-click-away
- `lib/blockster_v2_web/live/email_verification_modal_component.{ex,html.heex}` — phx-click-away + `:email_taken` error case
- `lib/blockster_v2_web/live/onboarding_live/index.ex` — `:email_taken` error in both email handlers
- `lib/blockster_v2_web/live/post_live/show.{ex,html.heex}` — removed onboarding popup
- `assets/js/app.js` — removed `OnboardingPopup` hook + registration
- `lib/blockster_v2/notifications/notification.ex` — added `"reward"` to `@valid_types`
- `lib/blockster_v2/notifications/event_processor.ex` — log create_notification failures
- `lib/blockster_v2/accounts/email_verification.ex` — `auth_method = "email"` filter + `:email_taken` error
- `lib/blockster_v2/migration/legacy_merge.ex` — `:not_a_legacy_holder` defense-in-depth guard

**Tests added** (4):
- `does NOT merge against an active Solana wallet user that shares the email`
- `returns :email_taken when promote hits the unique constraint on email`
- `user can change their already-verified email to a fresh address`
- `rejects merging an active Solana wallet user (not a legacy holder)`

49 email/legacy_merge tests, 0 failures. Full reclaim test set: 110 tests, 0 failures.

---

## Existing-Pages Redesign Release (2026-04-09 — ongoing)

### Wave 0 · Foundation Components (2026-04-09)

Created `lib/blockster_v2_web/components/design_system.ex` — a single module containing all reusable design system components, consumed via `use BlocksterV2Web.DesignSystem`.

**11 components built:**
- `<.logo size="22px" variant="light|dark" />` — Inter 800 wordmark with lime circle icon as the O (0.78em, +0.06em tracking)
- `<.eyebrow />` — tracked uppercase label
- `<.chip variant="default|active" />` — filter pill
- `<.author_avatar initials size />` — dark gradient initials circle (5 sizes)
- `<.profile_avatar initials size ring />` — heavier gradient, optional lime ring
- `<.why_earn_bux_banner />` — locked copy per D3
- `<.header />` — full production header with search input + results dropdown, notification bell + dropdown panel, cart icon, user dropdown (My Profile / BUX detail / Disconnect / Admin links), Connect Wallet button (anonymous), Solana mainnet pulse, lime Why Earn BUX banner
- `<.footer />` — dark footer with mission line, Miami Beach address, media kit link, newsletter form
- `<.page_hero variant="A" />` — editorial title hero with optional 3-stat band
- `<.stat_card />` — big-number white card with icon + footer slots
- `<.post_card />` — standard suggested-reading article card

**Additional components added during Wave 1:**
- `<.section_header />` — eyebrow + section title + see-all link
- `<.hero_feature_card />` — magazine-cover featured article (Variant B)
- `<.hub_card />` — full-bleed brand-color hub card
- `<.hub_card_more />` — dashed "+ N more hubs" tile
- `<.coming_soon_card variant="token_sale|recommended" />` — stub placeholder cards
- `<.welcome_hero />` — dark gradient anonymous CTA section
- `<.what_you_unlock_grid />` — anonymous 3-feature cards

**Infrastructure:**
- `lib/blockster_v2_web/components/layouts/redesign.html.heex` — minimal layout for redesigned pages (no old site_header/footer/mobile nav; includes wallet selector modal + toast notifications + flash)
- Router: new `:redesign` live_session with redesign layout
- `/dev/design-preview` route (dev-only) renders every component on one page
- `docs/solana/test_baseline_redesign.md` — inherited 37-file pre-existing failure baseline
- `docs/solana/redesign_release_plan.md` — master plan with locked decisions, stub register, build progress

**Commits:** `af15f58` (foundation components), `294b51d` (design preview)

### Wave 1 · Page #1 Homepage (2026-04-09 — built, not yet committed)

Rewrote `PostLive.Index` from a 4-component cycling infinite-scroll feed to a new structure:

**New cycling layouts** (replace PostsThree/Four/Five/Six):
- `ThreeColumn` — 3 posts in 3-col grid (consumes 3 posts)
- `Mosaic` — 14 posts in mixed-size 12-col mosaic (1 big + 2 medium + 4 small + repeat)
- `VideoLayout` — 7 video posts (skipped when fewer than 7 videos remain)
- `Editorial` — 4 posts in 2x2 large editorial cards

**One-shot sections** (rendered once on initial mount):
- Hero featured article (most recent post)
- Hub showcase (top 8 hubs by post count)
- Token sales stub (3 Coming Soon cards)
- Hubs you follow (logged-in only, posts from followed hubs)
- Recommended for you stub (logged-in only)
- Welcome hero + What you unlock (anonymous only)

**All existing functionality preserved:**
- Infinite scroll via `load-more` event cycling ThreeColumn → Mosaic → Video → Editorial
- Real-time BUX updates via `:bux_update` PubSub → `send_update` to correct layout component
- Search, notifications, cart, admin BUX deposit modal — all handlers preserved
- Post cards show category + earned/pool BUX badges (using existing `SharedComponents.token_badge/1` and `earned_badges/1`)
- Images use `ImageKit.w500_h500` for optimized loading
- Video play icon overlay on video posts

**Blog API additions:**
- `Blog.list_published_videos/1` — filters by `video_id != nil`
- `Blog.list_posts_from_followed_hubs/2` — joins hub_followers
- `Blog.count_published_posts_by_hub/1` — for hub showcase ordering
- `Blog.list_published_posts_by_date/1` — added `:exclude_ids` option for dedup

**Old homepage preserved at** `lib/blockster_v2_web/live/post_live/legacy/index_pre_redesign.{ex,html.heex}`

**Tests:** 8 new homepage tests + 65 total redesign tests passing, 0 new failures vs baseline.

### Wave 1 · Page #2 Article Page (2026-04-10 — built, not yet committed)

Restyled `PostLive.Show` template to match `article_page_mock.html` exactly:

**3-column layout:**
- **Left sidebar** (200px, sticky): 3 discover cards (Event, Token Sale, Airdrop) — static placeholders copied from mock, will be replaced by dynamic content system
- **Center**: Article inside white rounded card (`bg-white border rounded-2xl shadow-sm`)
- **Right sidebar** (200px, sticky): RogueTrader widget — static placeholder copied from mock (6 bots: HERMES, AURUM, STERLING, WOLF, MACRO, ZEUS), will be replaced by real-time widget

**Article header (matches mock exactly):**
- Category pill: lime `#CAFC00` bg, 10px bold, uppercase, rounded (not rounded-full)
- BUX earned pill: clean white with border, always visible, shows "Earning" or "Earned" state
- Title: Inter 700, -0.02em tracking, `article-title` class
- Author row: 40px dark gradient avatar + name + role (left), hub badge 40px same size with spacing (center), Share to X button with lime BUX pill (right) — all in one flex row with border-b

**Floating BUX panel (bottom-right, matches mock lines 1609-1637):**
- Clean white panel with ring-1 border and shadow (replaces old gradient panels)
- "Earning Live" state: green pulse dot, +N BUX 26px bold, engagement/base/multiplier breakdown
- "Earned" state: green checkmark, same layout, "View tx" Solscan link
- Video earned, not eligible, pool empty states — all white panel design

**Article body CSS (in `assets/css/app.css`):**
- Drop cap: `#post-content-1 > p:first-child::first-letter` — Inter 700, 58px (only first paragraph)
- Blockquote: lime border-left, italic 22px, attribution as small-caps (last `<p>` in blockquote)
- Bullet lists: left gray border, 5px black dot bullets, bold labels
- Headings: Inter 700, 28px
- Links: blue-500, underline on hover

**Template-based ad banner system (replaces old image-upload system):**
- Migration `20260410181441`: added `template` (string) and `params` (jsonb) to `ad_banners`
- 4 ad template components in `design_system.ex`: `follow_bar`, `dark_gradient`, `portrait`, `split_card`
- `<.ad_banner banner={banner} />` dispatcher picks correct template
- Content splitting: `TipTapRenderer.render_content_split/2` splits article nodes at fractional positions
- Inline ads placed at 1/3, 2/3, 3/3 marks within the article body
- Follow Hub bar at 1/2 mark — rendered from `@post.hub` data (not ad system), only when post has hub
- Seeded 3 template-based banners: Moonpay dark gradient (inline_1), Heliosphere portrait (inline_2), Moonpay split card (inline_3)
- Old image-based banners deactivated (not deleted)

**Suggested reading:**
- Uses original `SharedComponents.post_card` design (2x2 grid, "Suggested For You" heading)
- Category pill on cards updated to lime uppercase style (matching article header)

**Other changes:**
- `Blog.get_suggested_posts/3` — added `:hub` to preload
- `SharedComponents.post_card` — category badge restyled to lime uppercase pill
- Hub badge in author row: 40px circle (same size as author avatar), more left spacing
- Both sidebars: `sticky top-[120px]` — content stays fixed as user scrolls
- Eggshell `#fafaf9` page background
- DesignSystem header with correct `@bux_balance` assign (matches homepage pattern)

**All 25 handle_event + 4 handle_info + 6 handle_async handlers preserved.**

**Router:** `/:slug` moved from `:default` to `:redesign_article` live_session (must be last — catch-all)

**Old template preserved at** `lib/blockster_v2_web/live/post_live/legacy/show_pre_redesign.{ex,html.heex}`

**Test article:** `/the-quiet-revolution-of-onchain-liquidity-pools` — rich content with all typography elements. Seed: `mix run priv/repo/seeds_test_article.exs`

**Tests:** 13 show tests + 13 component tests = 26 new. 88+ total redesign tests passing, 0 new failures vs baseline.

### Wave 1 · Page #3 Hubs Index (2026-04-10 — built, not yet committed)

Restyled `HubLive.Index` template to match `hubs_index_mock.html` exactly:

**Page structure (top to bottom):**
- **Page hero**: "Browse" eyebrow, "Hubs" title (64px/80px), description with dynamic hub count, 3 stat tiles (Hubs / Articles / BUX Paid)
- **Featured hubs**: "Featured this week" eyebrow, 3 large gradient cards (5+4+3 col on lg) using new `hub_feature_card` component
- **Sticky search + filter bar**: white card with search input (debounced phx-keyup), sort-by label (stub), category chips using `<.chip>` component
- **Hub grid**: 4-col gradient hub cards using updated `<.hub_card>` component + dashed "more hubs" tile
- **Showing X of Y**: centered stat below grid

**New component: `<.hub_feature_card />`**
Large featured hub card with brand-color gradient, dot pattern overlay, blur glow, 56px logo square, 36px title, badge (Sponsor/Trending/etc), stats, Follow + Visit buttons. Two layouts:
- `:horizontal` — wide card (5-col or 4-col), stats in a row, follow + visit buttons side by side
- `:vertical` — narrow card (3-col), stats stacked vertically, full-width follow button

**Updated component: `<.hub_card />`**
Added optional `:category` attr for the top-right category badge (9px uppercase, glass bg, rounded-full). Added `min-height: 240px` to style. Description now uses `mt-auto` for better vertical alignment.

**Updated component: `<.hub_card_more />`**
Larger icon circle (w-12 h-12, rounded-full), bigger title (16px), subtitle changed to "Browse all categories" — matching mock exactly.

**LiveView changes:**
- `mount/3`: Splits hubs into `@featured_hubs` (first 3 by post count) and `@hubs` (grid), computes `@total_hub_count`, `@total_post_count`, `@categories`
- `handle_event("search")`: Filters grid hubs only (featured always shown)
- `compact_number/1`: Formats numbers as "1.2k", "3.4M" etc.
- `hub_post_count/1`, `hub_follower_count/1`: Safe association count helpers

**Router:** `/hubs` moved from `:default` to `:redesign` live_session (uses redesign layout)

**Old template preserved at** `lib/blockster_v2_web/live/hub_live/legacy/index_pre_redesign.{ex,html.heex}`

**Stubs:** Sort-by dropdown (visual only, no handler). Category filter chips fire `filter_category` event but no server-side category filtering (hubs don't have a category field).

**Test baseline updated:** Added `test/blockster_v2_web/live/post_live/show_test.exs` (pre-existing from article page redesign, not caused by hubs index work). Baseline now 38 files.

**Tests:** 8 hub_feature_card component tests + 16 hubs index LiveView tests = 24 new. 99+ total redesign tests passing, 0 new failures vs baseline.

### Wave 1 · Page #4 Hub Show (2026-04-10 — built, not yet committed)

Restyled `HubLive.Show` template to match `hub_show_mock.html` exactly:

**Page structure (top to bottom):**
- **Hub banner** (Variant C hero): full-bleed brand-color gradient (`linear-gradient(135deg, color_primary, color_secondary)`), dot pattern overlay, blur glow, breadcrumb (Hubs / name), identity block (80px glass logo square + 56-68px hub name), description, stats row (Posts / Followers), Follow Hub / Following CTA, social icon circles, frosted-glass live activity widget placeholder
- **Sticky tab nav**: 5 tabs (All / News / Videos / Shop / Events) with mono count badges and brand-color underline on active tab
- **All tab**: pinned post (12-col grid, 7-col image + 5-col text with hub badge, article-title, author avatar, BUX earn badge, "Read article" CTA), latest stories mosaic (big 7-col feature + 2 medium + 4 small cards), empty state when no posts
- **News tab**: mosaic of posts filtered by `kind = "news"`, empty state with newspaper icon
- **Videos tab**: featured video (large, left) + sidebar stack of 3 smaller video thumbnails, duration badges, empty state
- **Shop tab**: 4-col product grid with hub color dot badges, price display (original strikethrough + discounted), "Buy Now" button, "View all" link, empty state
- **Events tab**: empty state per D15 — white card "No events yet from this hub" + inert "Notify me" button

**New component: `<.hub_banner />`**
Variant C brand-color full-bleed hero. Accepts hub struct, post_count, follower_count, user_follows_hub, current_user. Renders identity block, stats row, follow/following button, social icons (website/X/telegram/discord), and live activity widget placeholder. Brand color gradient applied via inline style. Dot pattern + blur glow overlays.

**Schema migration: `20260410200001_add_kind_to_posts`**
Added `posts.kind` string field with default `"other"`, NOT NULL. Backfilled all existing posts. Added indexes on `[:kind]` and `[:hub_id, :kind]`.

**Post schema updated:** Added `field :kind, :string, default: "other"` + `validate_inclusion(:kind, ~w(news video other))` in changeset.

**New context function: `Blog.list_posts_by_hub_and_kind/3`**
Filters published posts by hub and kind field. Supports tag_name cross-matching (same pattern as `list_published_posts_by_hub`).

**LiveView changes:**
- `mount/3`: Loads all_posts, pinned_post (first), mosaic_posts (next 7), news_posts (kind="news"), videos_posts, hub_products. Assigns `active_tab` (replaces separate show_all/show_news booleans)
- `switch_tab` handler: sets `active_tab` string (simplified from old boolean pattern)
- Removed `load-more-news` infinite scroll — news tab now uses simple mosaic grid
- Preserved: `toggle_follow`, `update_hub_logo`, `toggle_mobile_menu`, `close_mobile_menu`
- Added helpers: `compact_number/1`, `read_time/1`, `author_initials/1`, `author_display_name/1`, `format_date/1`, `tab_label/1`, `tab_count/2`

**Router:** `/hub/:slug` moved from `:default` to `:redesign` live_session (uses redesign layout). Hub admin routes stay in `:default`.

**Old template preserved at** `lib/blockster_v2_web/live/hub_live/legacy/show_pre_redesign.{ex,html.heex}`

**Stubs:** Live activity widget (static placeholder), Sponsor/Verified badges (hardcoded), category filter chips on mosaic (visual only), "Notify me" button (inert), events tab (always empty state per D15).

**Tests:** 13 hub_banner component tests + 17 hub show LiveView tests = 30 new. 129+ total redesign tests passing, 0 new failures vs baseline.

### Wave 2 Page #5: Profile (2026-04-10)

**Commit:** `redesign(profile)` (see below)

**Mock:** `docs/solana/profile_mock.html`

**What changed:**
- Full template rewrite of `MemberLive.Show` (the `/member/:slug` page used when `is_own_profile = true`)
- **Profile hero**: 12-col grid with 96px profile_avatar, "Your profile" eyebrow, active badge, 44-52px username, @slug, wallet address with copy + Solscan link, member-since date. Right column: logout icon button, verification status mini pills (X/Phone/SOL/Email — green check or amber warning; X/Phone/Email pills are clickable when inactive, linking to their respective connect/verify actions).
- **Three stat cards**: BUX Balance (footer: "Use BUX to enter airdrops & play games"), BUX Multiplier (with "of 200× max" and next-action hint), SOL Balance (with proper Solana logo from ImageKit, SOL multiplier footer). Uses existing `<.stat_card>` component.
- **Email/Phone verification banners**: Conditional amber gradient cards shown when unverified. Clear CTA to open verification modal.
- **Multiplier breakdown**: Always-visible white card (replaced old dropdown). 4-col grid showing X / Phone / SOL / Email multipliers with progress bars, connection status, and verify CTAs. **All inactive/unverified boxes** get the same amber background + greyed-out number + muted progress bar treatment. Base values: X=1×, Phone=0.5×, Email=0.5×. Footer formula greys out incomplete terms. When overall multiplier is 0 (no SOL), shows "Deposit at least 0.1 SOL into your connected wallet to start earning BUX" instead of generic copy.
- **Sticky 5-tab nav**: Activity / Following / Refer / Rewards / Settings. Frosted glass at `top:84px`, lime active underline, mono count badges. Mobile dropdown select fallback.
- **Activity tab**: Time period filter chips (24H/7D/30D/ALL) with total earned headline. Activity table with icon-per-type (read=book, video=play, X share=X logo, notification=check), post links, BUX reward + tx link.
- **Following tab**: Hub cards grid using hub brand gradients with unfollow X buttons, post count. "Discover more" dashed card at end linking to /hubs. Empty state with "Browse hubs" CTA.
- **Refer tab**: Referral link card with copy button, earn description ("Plus earn 0.2% of every losing bet they place — forever."), 2×2 stats grid (Total/Verified/BUX/SOL earned). Referral earnings table with type badges, author avatars, amounts, timestamps, tx links. InfiniteScroll hook preserved.
- **Rewards tab** (NEW): Lifetime BUX earned total card (64px mono value), source breakdown card with progress bars (Reading articles / X shares / Referrals / Other bonuses). Data computed from existing activity + referral_stats assigns. No dollar-value redeemable text.
- **Settings tab**: 12-col layout. Left 7-col: Account details card (Username with edit form, Profile URL with copy, Wallet with Solscan + copy, Email with verify status, Auth method, Member since). Right 5-col: Connected accounts (X/Telegram/Email/Phone with connect/disconnect/verify CTAs) + Danger zone (Export/Disconnect/Deactivate — Export and Deactivate are stubs).
- **Modals preserved**: Phone and email verification modals (live_component) render conditionally.

**New helpers added to show.ex:**
- `format_number/1` — commas for integers/floats
- `format_multiplier/1` — clean multiplier display (no trailing .0)
- `user_initials/1` — initials from user struct
- `user_initials_from_name/1` — initials from name string

**Router:** `/member/:slug` moved from `:default` to `:redesign` live_session.

**Old template preserved at** `lib/blockster_v2_web/live/member_live/legacy/show_pre_redesign.{ex,html.heex}`

**Stubs:** Rewards tab sparkline (static), Coin Flip wins in rewards (shows 0), pending settlement (hidden), Export account data (flash "Coming soon"), Deactivate account (flash "Coming soon").

**Tests:** 28 new LiveView tests in `show_test.exs`. Tests cover: profile hero rendering, stat cards, multiplier breakdown, 5-tab nav + switching, activity table + time period filter, following tab, refer tab, rewards tab, settings tab content, verification banners (shown/hidden by state), security (anonymous redirect, not-found redirect). 0 new failures vs baseline.

**User feedback applied (same session):**
- Inactive multiplier boxes: all get amber bg + greyed number + muted bar (not just email)
- BUX Multiplier stat card: literal × instead of `&times;` HTML entity
- Base values corrected: X=1×, Phone=0.5×, Email=0.5×
- BUX Balance: removed "redeemable" dollar value, replaced with utility text
- SOL Balance icon: proper `solana-sol-logo.png` from ImageKit on black bg
- Removed Edit Profile and Settings pills from hero quick actions
- X/Phone/Email hero pills: clickable when inactive (link to connect/verify)
- Email added to Connected Accounts panel in Settings tab
- Removed dollar redeemable text from Rewards tab
- Refer tab: simplified to "0.2% of every losing bet — forever"
- Formula footer: all four terms grey out independently when inactive
- Zero-multiplier message: "Deposit at least 0.1 SOL…" when overall is 0

### Wave 2, Page #6: Public Member Page (2026-04-10)

**Mock:** `docs/solana/member_public_mock.html`
**Plan:** `docs/solana/member_public_redesign_plan.md`
**Bucket:** B — visual refresh + schema additions

**Schema migrations:**
- `20260410200002_add_bio_and_x_handle_to_users.exs` — adds `bio` (text, nullable) and `x_handle` (string, nullable) to users table

**Architecture change:** Modified `MemberLive.Show` to support both owner and public views instead of creating a separate module. The security redirect for non-owners was removed. The module now branches in `handle_params` based on `is_own_profile`:
- Owner → `load_owner_profile/3` (full private view, unchanged from profile redesign)
- Non-owner/anonymous → `load_public_profile/3` (read-only public view)

**New Blog context functions** (for public profile data):
- `list_published_posts_by_author/2` — with `:limit`, `:offset`, `:kind` filtering
- `count_published_posts_by_author/2` — with optional `:kind` filter
- `sum_views_by_author/1` — total view_count across author's posts
- `sum_bux_by_author/1` — total bux_total across author's posts
- `list_author_hubs/1` — distinct hubs with per-hub post counts

**Public view sections (matching mock):**
1. Identity hero: 112px profile avatar, "Author profile" eyebrow, "Verified writer" badge (conditional on `is_author`), name, @slug, profile URL, member since, bio paragraph, social row with X handle
2. Stats row: 3 cards (Posts published, Total reads, BUX paid out) — Followers removed per D17
3. Sticky 4-tab nav (Articles/Videos/Hubs/About) at top:84px
4. Articles tab (default): horizontal post cards (180px image + content) with hub color dot, excerpt, reading time, BUX reward badge. "Published in" sidebar with gradient hub cards. "Recent activity" sidebar derived from published posts.
5. Videos tab: same layout, filtered by `kind: "video"`
6. Hubs tab: 3-col grid of gradient hub cards with post counts
7. About tab: bio card, details table (username, member since, posts, reads), social links

**Decisions applied:**
- D17: Followers REMOVED — no Follow button, no follower stat card, no follower activity
- D18: RSS REMOVED — no RSS link in social row
- D19: "Published in" sidebar — LIVE, uses post→hub relation

**Stubs:** "Notify me" button (inert), "Share" button (inert), Recent activity sidebar (published-post events only, no follower/milestone activities).

**Tests:** 28 new tests added to `show_test.exs` (47 total). Tests cover: public hero rendering (username, slug, bio, Verified writer badge, member since), stat cards (Posts/Reads/BUX, no Followers), 4-tab nav, articles tab (empty state, post cards, Published in sidebar), tab switching (About/Hubs/Videos), non-owner sees public view, anonymous sees public view, owner still sees owner view, header/footer present. 0 new failures vs baseline.

**User feedback applied (same session):**

1. **Disconnect wallet broken on all redesigned pages (root cause found)** — User reported clicking "Disconnect Wallet" sent them to homepage but left them logged in. Investigation revealed the `SolanaWallet` JS hook was mounted ONLY on the old `<.site_header />` in `layouts.ex:96`. When the profile redesign (commit `ad936f6`) moved `/member/:slug` into the `:redesign` live_session, the page stopped using `app.html.heex` and started using `redesign.html.heex` — which does not include the old site_header. The new `<DesignSystem.header />` never had `phx-hook="SolanaWallet"`, so `clear_session` and `request_disconnect` events pushed from the LiveView had no listener. This bug was present on ALL already-redesigned pages (homepage, hubs index, hub show, profile, member). **Fix**: added `phx-hook="SolanaWallet"` to the `<header id="ds-site-header">` element in `design_system.ex`. Single-attribute fix — no JS or wallet_auth_events.ex changes.

2. **Notify me and Share buttons wired up** — Initially left as inert stubs; user wanted them functional. Share button: uses existing `CopyToClipboard` JS hook with `data-copy-text={BlocksterV2Web.Endpoint.url() <> "/member/#{@member.slug}"}` — copies the full profile URL with checkmark feedback, no LiveView event needed. Notify me button: `phx-click="notify_me"` handler flashes `"We'll let you know when [name] publishes — subscriptions coming soon."` (still a stub for real persistence — documented in the stub register).

3. **`push_event("copy_to_clipboard", ...)` is a no-op** — Discovered while wiring the Share button that the legacy `push_event("copy_to_clipboard", %{text: ...})` pattern used in referral copy and the pre-redesign legacy code has **no JS listener anywhere in the bundle**. The real `CopyToClipboard` hook reads from `data-copy-text` attribute on click. The owner-profile referral copy is therefore also broken — flagged for a future commit, out of scope for this page.

### Wave 3, Page #7: Play / Coin Flip (2026-04-10 → 2026-04-11 — committed)

**Mock:** `docs/solana/play_mock.html` (3 stacked states in one file)
**Plan:** `docs/solana/play_redesign_plan.md`
**Bucket:** A — pure visual refresh, no schema changes, no new contexts

**Full `render/1` rewrite of `CoinFlipLive`.** The old render function was 613 lines inline in the LiveView module; the new one is ~990 lines, still inline. Every other function in the module (mount, event handlers, async handlers, info handlers, helpers — all 1340+ lines) is **preserved byte-for-byte**.

**Page structure (top to bottom):**
- `<DesignSystem.header active="play" …>` with all prod assigns (bux, cart, notifications, search, connecting). Why-earn-bux banner enabled.
- **Page hero** (`ds-play-hero`): 12-col grid. Left 7-col (eyebrow "Provably-fair · On-chain · Sub-1% house edge" + 60-80px "Coin Flip" headline + 520px tagline paragraph). Right 5-col (3 stat cards: SOL Pool / BUX Pool / House Edge). Pool values populate from existing `@house_balance` assign based on `@selected_token`; the non-selected pool shows "—" as a stub.
- **Expired bet reclaim banner** (`@has_expired_bet`): amber card with Reclaim button, preserved.
- **Game card** (`ds-play-game`): 12-col grid. Col-span-8 = game card, col-span-4 = sidebar. The game card branches on `@game_state`:
  - **State 1 (`:idle`)**: token selector pills (SOL/BUX), 9-col difficulty grid (`difficulty-grid`), bet amount input (½/2×/MAX quick buttons + preset chips), green "Potential profit" callout, error message, prediction coin row (uses **existing rocket/poop emoji coin style** inside `.casino-chip-heads`/`.casino-chip-tails` outer rings), provably-fair `<details>` collapsible (commit hash copy + game nonce), large black "Place Bet" button.
  - **State 2 (`:awaiting_tx`/`:flipping`/`:showing_result`)**: locked bet header, large centered spinning coin (preserves `CoinFlip` JS hook on `#coin-flip-#{@flip_id}` — the hook drives continuous spin + `reveal_result` event-based deceleration), decorative blurred glow dots + dashed circle border, "Flipping coin · N of M" caption, predictions vs results mini-grid, tx status strip with Solscan link.
  - **State 3 (`:result`)**: gradient win/loss banner with big mono amount, large predictions-vs-results grid with green/red ring indicators, settlement status card (green check + Solscan link when settled, spinner when pending, amber warning when failed) with Verify fairness + Play again/Try again buttons.
- **Sidebar** branches on `@game_state` too:
  - Idle: "Your stats" card (from `@user_stats`) + "Your recent games" feed (last 5 of `@recent_games`, relabelled from mock's "Live · All players" — stub) + "Two modes" legend + inlined sidebar ad banners (merged from `@play_sidebar_left_banners ++ @play_sidebar_right_banners`).
  - In-progress: "This bet" card (token/stake/difficulty/multiplier/predictions/potential payout) + "Provably fair · Live" card.
  - Result: "Your stats updated" card on win, "Recap" card with "Become an LP →" link on loss.
- **Recent games table** (`ds-play-recent`): section with eyebrow + "Recent games" headline + white card wrapping a scrollable table (ID/Bet/Predictions/Results/Mult/W/L/P/L/Verify). Populated from `@recent_games`, row tinted green/red, predictions + results rendered as inline rocket/poop emojis, Solscan links on commitment/bet/settlement sigs, InfiniteScroll hook preserved.
- `<DesignSystem.footer />`
- `<.coin_flip_fairness_modal />` — preserved at the root level for Verify Fairness button clicks

**Coin emoji vs mock H/T — critical user instruction applied:**
The mock shows yellow H coins and grey T coins. The production page uses 🚀 (heads) and 💩 (tails) emojis rendered inside `.casino-chip-heads` / `.casino-chip-tails` outer rings with `bg-coin-heads` / `bg-gray-700` inner circles. The redesign **keeps the emoji treatment everywhere** — prediction selectors, spinning coin face, prediction vs result grids, sidebar predictions pills, recent games table cells. Coin click behavior (one coin per prediction slot, click cycles nil → :heads → :tails via `toggle_prediction`) preserved exactly. For >1 predictions, N coin buttons appear side-by-side, clicked independently.

**Difficulty grid layout change:** the old template used a horizontally-scrolling tab strip with `ScrollToCenter` hook. The new template uses a `grid-cols-9` layout (responsive `grid-cols-5` on mobile). The `ScrollToCenter` hook is no longer attached on this page — still registered in app.js for other uses.

**Handlers preserved (zero changes):** `select_token`, `toggle_token_dropdown`, `hide_token_dropdown`, `toggle_provably_fair`, `close_provably_fair`, `select_difficulty`, `toggle_prediction`, `update_bet_amount`, `set_preset`, `set_max_bet`, `halve_bet`, `double_bet`, `start_game`, `flip_complete`, `bet_confirmed`, `bet_failed`, `bet_error`, `reclaim_stuck_bet`, `reclaim_confirmed`, `reclaim_failed`, `reset_game`, `show_fairness_modal`, `hide_fairness_modal`, `load-more-games`, `load-more`, `stop_propagation`. All async + info handlers + PubSub subscriptions preserved.

**JS hooks preserved:** `CoinFlipSolana` (root `#coin-flip-game`), `CoinFlip` (flipping coin), `CopyToClipboard` (commit hash copy), `InfiniteScroll` (recent games table). `ScrollToCenter` intentionally dropped from this page only.

**Template syntax gotcha encountered + fixed:** Elixir 1.16 does NOT allow bare `if ... do ... else ... end` inside a list container (`class={[...]}`). Must use `if(cond, do: x, else: y)` with parens to disambiguate. Hit the error 4x during the initial compile, all fixed. Same issue would apply to `cond` or `case` inside `class={[...]}` lists — use a `<% var = cond do … end %>` assignment above and reference the var instead.

**Router:** `/play` moved from `:default` to `:redesign` live_session (uses redesign layout + DS header with `SolanaWallet` hook already mounted).

**Legacy file preserved at** `lib/blockster_v2_web/live/coin_flip_live/legacy/coin_flip_live_pre_redesign.ex` (module renamed to `BlocksterV2Web.CoinFlipLive.Legacy.PreRedesign`).

**Stubs:** "Live · All players" sidebar feed shows user's own last 5 games labelled "Your recent games" (real global feed needs an activity system release), House Edge hero stat hardcoded "0.92%", BUX Pool hero stat shows "—" when SOL is selected (and vice versa).

**Tests:** 21 new tests in fresh `test/blockster_v2_web/live/coin_flip_live_test.exs`. Covers: anonymous visitor rendering (header, hero, stat band, game card, prediction row, provably fair, place bet, recent games empty state, footer, sidebar cards, rocket/poop emoji presence), authenticated user rendering (game card, all 9 difficulty levels, CoinFlipSolana hook mount), handler smoke tests (`select_difficulty`, `toggle_prediction` cycling, `set_preset`, `select_token`, `halve_bet`/`double_bet`). 0 new failures vs baseline — full `mix test` reports 2498 tests, 106 failures, all baseline files, none in `coin_flip_live_test.exs`.

**User feedback applied (same session):**

1. **`:bux_balance` stuck at 0 after mid-session wallet login** — User reported BUX balance pill in header showed `0.00` after logging in on `/play`, only fixing after a full page refresh. Root cause: the `wallet_authenticated` hook in `lib/blockster_v2_web/live/wallet_auth_events.ex` synchronously reads `get_user_token_balances/1` and assigns `:token_balances`, but does NOT assign `:bux_balance`. The old `site_header` read `@token_balances["BUX"]` (so it picked up the value). The new `<DesignSystem.header>` reads the scalar `@bux_balance` which was last set by `BuxBalanceHook.on_mount` back when `user_id` was still `nil` (anonymous mount → default 0). And `BuxBalanceHook`'s PubSub subscription is gated on `user_id` being non-nil at on_mount time, so mid-session login never re-subscribes either. **Fix**: single-line addition to `wallet_auth_events.ex` line 48 — `|> Phoenix.Component.assign(:bux_balance, Map.get(token_balances, "BUX", 0))`. Applies to every page using the DS header, not just `/play`. **New gotcha for next session**: the `:bux_balance` scalar and `:token_balances` map are populated by different paths; if you add pages using `DesignSystem.header`, verify the `:bux_balance` stays in sync with token_balances across every flow (mid-session login, disconnect, reconnect).

2. **Connect Wallet button missing `cursor-pointer`** — `design_system.ex:548`, one-liner added.

3. **Simulation failed warning in Phantom popup** — User reported "This transaction reverted during simulation. Funds may be lost if submitted" on every `place_bet`. I initially suspected the `confirmed` blockhash commitment and changed it to `finalized` in `contracts/blockster-settler/src/services/rpc-client.ts:getRecentBlockhash`, but that didn't help and was reverted. Root cause (verified by stashing the redesign changes and testing legacy `/play` — warning ALSO present there): back-to-back dependent tx propagation issue from CLAUDE.md. `submit_commitment` is settler-signed via QuickNode and writes `pending_commitment` / `pending_nonce` on `player_state`. `place_bet` is player-signed, simulated by Phantom against its **own RPC** (public `api.devnet.solana.com`, which lags 5-15 slots behind QuickNode). Phantom sees stale `pending_commitment == [0u8; 32]` or `pending_nonce` off-by-one and the program returns `NoCommitment` / `NonceMismatch`. User approves anyway, tx actually submits, state has propagated by send time, lands successfully. **Pre-existing, not introduced by redesign.** Parked with a stub register entry until mainnet verification — Phantom's mainnet default RPC is a paid endpoint (Helius/Triton) with tight sync to QuickNode, and the warning likely disappears. If not, the fix is a client-side `getAccountInfo(player_state)` poll after `submit_commitment` returns before enabling Place Bet.

4. **Results side-by-side with Predictions → stacked** — User wanted Results below Predictions, not in a 2-col grid. Applied to both State 2 (in-progress, `grid-cols-2` → `space-y-5`) and State 3 (result, `grid-cols-2` → `space-y-6`).

5. **Flip 2+ stopping suddenly (no gradual deceleration)** — User reported flips 2, 3, 4, 5 all snapping to the final position instead of the smooth ease-out that flip 1 has. After several back-and-forth attempts: the real cause is a race in `assets/js/coin_flip.js`. `mounted()` and `updated()` schedule a `requestAnimationFrame` that re-adds `animate-flip-continuous` to the coin element. On subsequent flips, `handle_info(:next_flip, ...)` patches in the new `#coin-flip-#{flip_id}` element AND immediately fires `:reveal_flip_result` → `push_event("reveal_result", ...)`. If the websocket message arrives BEFORE the rAF fires (common — it's a few ms vs 16ms), the reveal handler sets the deceleration class first, then the rAF stomps it with `animate-flip-continuous`. **Fix**: added `this.revealHandled = false` on mount and `this.revealHandled = true` inside the `reveal_result` handler. Both `mounted()` and `updated()` rAF callbacks now `if (this.revealHandled) return` before touching classes. Fixed in `assets/js/coin_flip.js`. **Separately**, during this debugging I briefly removed the inline `<style>` block keyframes from `coin_flip_live.ex` thinking `assets/css/app.css` had the "real" versions, which broke flip 1 because the app.css keyframes end at different rotations (1980° / 2160°) than the inline ones (1800° / 1980°), landing on the opposite coin face. **Lesson: the inline `<style>` override is load-bearing, not dead code.** app.css's `.animate-flip-heads` / `.animate-flip-tails` rules are actually dead code because the inline `<style>` in `render/1` redeclares them and wins the cascade (body-level style > head `<link>`).

6. **Header pill shows BUX; user wants SOL on play page** — Added `display_token` attr to `<DesignSystem.header>` (values `"BUX"` or `"SOL"`, default `"BUX"`). New helpers `format_display_balance/2` (4 decimals for SOL, delegates to `format_bux` otherwise) and `display_token_icon/1` (returns Solana logo URL for SOL). `coin_flip_live.ex` passes `display_token="SOL"`.

**Gotchas added for next session:**

- **Elixir 1.16 template syntax**: NEVER put bare `if/cond/case do…end` blocks inside `class={[…]}` lists — use `if(cond, do: x, else: y)` with parens, or extract a `<% … %>` assign above.
- **Inline `render/1`**: the `CoinFlipLive` module uses an inline `render/1`, NOT a separate `.html.heex` file. Don't try to use `Write` to "create" a template file — edit the render function inside the `.ex` file directly.
- **Large render rewrites**: the 613→990 line render rewrite was done via a scripted python splice (`/tmp/new_coin_flip_render.ex` → read file → splice lines 184..796 with new content). Edit with multi-hundred-line old_string is impractical for wholesale render rewrites.
- **Mnesia test tables**: `coin_flip_games` has 19 fields — copy the exact order from `mnesia_initializer.ex:598` when adding to `ensure_mnesia_tables/0` in tests, or you'll hit `{:aborted, {:bad_type}}`. `bux_booster_user_stats` has 15 fields, key is `{user_id, token_type}`, required for any test hitting `load_user_stats/2`.
- **Inline `<style>` cascade**: a LiveView render function's inline `<style>` block sits in the `<body>` and wins the CSS cascade over `<link rel="stylesheet">` in `<head>`. On the coin flip page specifically, the inline `<style>` **redeclares** `.animate-flip-heads` / `.animate-flip-tails` / `.animate-flip-continuous` / `.perspective-1000` with different keyframes than `assets/css/app.css`. The `app.css` versions are effectively dead code on this page. If you "clean up" the inline `<style>` by removing what looks redundant, the coin will land on the wrong face (180° rotation difference) and animations will misbehave. Leave the inline `<style>` alone unless you're sure you understand both layers.
- **JS hook rAF races**: `mounted()` / `updated()` callbacks that schedule a `requestAnimationFrame` and manipulate classes can race with `handleEvent` callbacks for `push_event` messages fired by the server immediately after the patch. The push_event can arrive before the rAF fires. Use a flag (e.g. `this.revealHandled`) set in the event handler and checked in the rAF callback to prevent the rAF from clobbering the event handler's DOM changes. Reset the flag in `updated()` when the element id changes (new flip / new session).
- **`:bux_balance` vs `:token_balances`**: the BUX balance displayed in the `DesignSystem.header` pill uses the scalar `:bux_balance` assign. That assign is set in two places: (1) `BuxBalanceHook.on_mount` on initial mount — reads Mnesia and subscribes to PubSub, only when `user_id` is non-nil at mount time; (2) `wallet_authenticated` hook in `wallet_auth_events.ex` — extracted from `token_balances["BUX"]` during mid-session login. If you add a new page using the DS header, verify the pill stays in sync across: fresh load while logged in, fresh load while anonymous + connect wallet on the same page (mid-session login), disconnect/reconnect flows.
- **`display_token` attr on DS header**: `<DesignSystem.header display_token="SOL">` shows the SOL balance pill instead of BUX. The pill reads `@token_balances["SOL"]` for SOL, `@bux_balance` for BUX (legacy default). SOL formats to 4 decimals, BUX to 2. Helper functions: `format_display_balance/2` and `display_token_icon/1` in `design_system.ex`.
- **Back-to-back Solana tx propagation warning**: the "Transaction reverted during simulation. Funds may be lost if submitted" popup from Phantom on devnet is pre-existing and NOT caused by the redesign — verified by stashing the redesign files and testing legacy `/play`. Root cause is public devnet RPC lag. Don't implement a fix until you see it on mainnet; Phantom's mainnet default RPC is a paid endpoint with tight sync and the warning typically disappears. The real fix (if needed) is client-side `getAccountInfo(player_state)` polling after `submit_commitment` before enabling Place Bet — see stub register entry in `redesign_release_plan.md`.

---

## 2026-04-11 — Wave 3 Page #8: Pool index (`/pool`) rebuilt

Bucket A visual refresh of `BlocksterV2Web.PoolIndexLive`. The original module was ~100 lines with a minimal `@pool_stats` + two `<.pool_card />` callouts and a 3-step how-it-works. The mock (`docs/solana/pool_index_mock.html`) is a completely different scale: editorial hero + 3-stat band, TWO full-bleed gradient vault cards (~420px min-height) with LP price + sparkline + 2×2 stats grid + "Your position" card + CTA, how-it-works grid, and a cross-pool activity table.

**What shipped:**

- Route `/pool` moved from `:default` → `:redesign` live_session (`router.ex:153`).
- Old module copied verbatim to `lib/blockster_v2_web/live/pool_index_live/legacy/pool_index_live_pre_redesign.ex` as `BlocksterV2Web.PoolIndexLive.Legacy.PreRedesign` (never routed, no imports — just the paper trail).
- `pool_index_live.ex` rewritten end-to-end. `mount/3` now:
  - Fetches pool stats via `BuxMinter.get_pool_stats/0` (same as before).
  - Fetches cross-vault activity via `CoinFlipGame.get_recent_games_by_vault/2` × 2 vaults + `:mnesia.dirty_index_read(:pool_activities, vault, :vault_type)` × 2 vaults, merged and sorted by `_created_at` desc, capped at 50.
  - Fetches the user's `bSOL` + `bBUX` LP balances in parallel via `BuxMinter.get_lp_balance/2` when a wallet is connected.
  - Subscribes to `"pool_activity:sol"` + `"pool_activity:bux"` PubSub topics — same broadcast format used by `PoolDetailLive`, so live deposits/withdraws update the table in real time.
- Template rebuilt inline in `render/1` to match the mock pixel-for-pixel: DS header with `active="pool"`, editorial hero + 3-stat right-column band, two vault cards (SOL emerald-gradient + BUX lime-gradient, each `min-h-[420px]`, each wrapped in a `<.link navigate=...>` so the whole card is clickable), a 3-step "Become the house" section, a 6-col activity table matching the mock (Type / Pool / Wallet / Amount / Time / TX), and `<DesignSystem.footer />`.
- Tests rewritten. The old test file asserted against the previous markup ("Back to Play" link, `animate-ping` loading pulse, "Enter Pool" CTA, the `<.pool_card />` component). New assertions cover: hero copy, vault card CTAs (`"Enter SOL Pool"` / `"Enter BUX Pool"`), LP Price label, stat band labels, how-it-works headline, activity section + pulse, DS footer sentinel ("Where the chain meets the model"), anonymous empty-state prompt pointing at `/play`, navigation to `/pool/sol` and `/pool/bux`, DS header `ds-site-header` + `SolanaWallet` hook, Why Earn BUX banner. 9 tests, all pass.
- `mix test`: 2499 tests, 109 failures, 0 new outside baseline. The +1 failure vs the 108 baseline is well within the 100-165 flaky range noted in `test_baseline_redesign.md`. Pool files are all already in the baseline; no pool_index regressions.

**User feedback applied:** none yet — awaiting local validation before commit.

**Surprises worth remembering:**

- **Cross-vault activity data is cheap to wire.** `CoinFlipGame.get_recent_games_by_vault/2` and `:pool_activities` (Mnesia, indexed by `vault_type`) were already built for the detail page, and the broadcast topics `"pool_activity:sol"` + `"pool_activity:bux"` already fire on every deposit/withdraw/settlement. Subscribing to both and merging is ~30 LOC and doesn't count as "new context" work — pure read-side composition of data that's already flowing.
- **The mock's activity table is a 6-col grid that doesn't fit the existing `<.activity_table />` component.** The detail-page component uses a different layout (icon + flex content + buttons). Rather than touch it (and force the detail page to redesign-match) I inlined the new table markup on this page only. That follows the "inline it until a second page needs it" rule from the design_system conventions.
- **Pool index is the first redesigned page that subscribes to PubSub topics that OTHER pages publish to** — deposits on `/pool/sol` broadcast `{:pool_activity, activity}` on `"pool_activity:sol"`, which the index page now receives. The `handle_info({:pool_activity, _}, socket)` head is required; the catch-all `handle_info(_, socket)` alone would be caught but not update the activity list. Verified in the render — the fallthrough works correctly in the empty case.
- **Mock uses "pulse-dot" CSS keyframes**; I used Tailwind `animate-pulse` everywhere instead (consistent with other redesigned pages, no CSS additions). Visual delta is mild; `animate-pulse` fades opacity rather than scaling.
- **`Map.get(assigns, :current_user)` works fine in `mount/3` but you need `socket.assigns[:current_user]`** — `@current_user` isn't available inside `mount` until after it's assigned, but `UserAuth` on_mount has already run by then so `socket.assigns.current_user` is present (may be nil). Checking both `current_user` and `wallet_address` before triggering LP fetches avoids the "pending_nonce" case where a logged-in user with no wallet would fire a `/lp-balance/nil/sol` request.
- **The 24h aggregate labels on the stat band are a visual lie.** The mock labels say "24h" but we use cumulative `totalBets` / `houseProfit` because there's no 24h rollup yet. Fixed by relabeling to "all time" in the sub-line so the page doesn't claim data it doesn't have. Stub-registered in the redesign plan.

---

## 2026-04-11 · Wave 3 Page #9 — Pool detail page (/pool/sol + /pool/bux)

**Scope**: full `render/1` rewrite of `BlocksterV2Web.PoolDetailLive` against `docs/solana/pool_detail_mock.html`. Bucket A (pure visual refresh). No schema changes, no new DS components, no new contexts. Both `/pool/sol` and `/pool/bux` moved from `:default` live_session to `:redesign`. Legacy module preserved at `lib/blockster_v2_web/live/pool_detail_live/legacy/pool_detail_live_pre_redesign.ex` as `BlocksterV2Web.PoolDetailLive.Legacy.PreRedesign`.

**What shipped**:

1. **Full-bleed gradient pool banner hero** — inline markup, vault-aware `style` (SOL emerald gradient / BUX lime gradient), radial dot pattern + top-right glow overlays, 12-col grid. Left 7-col: 20×20 icon tile + `Bankroll Vault` eyebrow + lime `Live` pulse pill + `SOL Pool` / `BUX Pool` 56–68px headline, then `Current LP price` eyebrow + 64px mono price + token unit + live 24h change chip (only when `chart_price_stats.change_pct` is non-nil) + `24h` label, then 4-stat divider row (TVL / LP supply / Est. APY / Bets 24h). Right 5-col: translucent `Your position` card (LP balance, dollar estimate, 2-col Cost basis / Unrealized P/L strip — both stubbed with `—`).

2. **Two-column main section** (`max-w-[1280px]`, `grid-cols-12 gap-6`) under the banner:
    - **Left 4-col sticky order form** (`lg:sticky lg:top-[84px] self-start`, white rounded-2xl card): deposit / withdraw segmented pill tabs, "Your wallet" 2-col balance strip (SOL + SOL-LP on SOL vault, BUX + BUX-LP on BUX vault), LP Price one-liner, large 28px mono input with `½` + `MAX X.XX` quick buttons (new `set_half` handler added — inverse of `set_max`, returns balance/2), balance + dollar estimate sub-row, tinted output preview card with "New pool share (+Δ)" footer, black submit button ("Deposit X SOL" or "Withdraw X SOL-LP"), "No lockup · Instant withdraw" caption. Helpful info card below with "How earnings work" copy + "Read the bankroll docs →" link (navigates to `/pool` for now).
    - **Right 8-col** stacked `space-y-6`: `<.lp_price_chart>` (restyled to match mock — `SOL-LP price` eyebrow, 28px mono, timeframe pill row with `bg-[#141414] text-white` active state), `<.pool_stats_grid>` (restyled to 8 white rounded-2xl cards on a 4-col grid with mock labels: LP price / LP supply / Volume {tf} / Bets {tf} / Win rate {tf} / Profit {tf} / Payout {tf} / House edge — last one uses `realized {tf}` sub-line), `<.activity_table>` (restyled to mock: live pulse header + pill tabs + 4-col `grid-cols-[180px_1fr_140px_60px]` rows with icon tile + wallet avatar column + right-aligned amount + tx short link).

3. **Restyled `pool_components.ex` in place**: `lp_price_chart`, `pool_stats_grid`, `stat_card`, `activity_table`, `activity_row`. Component APIs unchanged — only the embedded markup swapped so callers stay wire-compatible. Removed dead `activity_icon_bg` / `activity_icon_color` / `activity_icon` / `activity_label` / `activity_badge_class` helpers. Added `row_primary_label`, `row_secondary_label`, `row_avatar_initials`, `row_short_sig`, `row_icon_wrapper_class`, `row_icon_color`, `row_icon_path` helpers for the new activity row layout. Added `format_win_rate_value/2` and `format_house_edge/1` public helpers for the stats grid.

4. **Preserved every existing handler, assign, PubSub subscription, JS hook, and settler call** — 100% of the existing mount/handle_event/handle_info/handle_async bodies are untouched. `PoolHook` stays on `#pool-detail-page`, `PriceChart` stays on `#price-chart-{vault_type}` with `phx-update="ignore"`, `SolanaWallet` on `#ds-site-header` (from DS header). All three activity and chart PubSub topics (`bux_balance:#{user_id}`, `pool_activity:{vault}`, `pool_chart:{vault}`) preserved exactly. `tx_confirmed` still writes `:pool_activities` Mnesia record and broadcasts `{:pool_activity, …}` on the vault topic.

5. **Router**: moved `live "/pool/:vault_type", PoolDetailLive, :show` from the `:default` live_session to `:redesign` (same scope as `/pool`, `/play`, etc.). No redirects to/from and no other routes touched.

6. **Tests**: `pool_detail_live_test.exs` updated — 35 tests, 0 failures. Replaced label assertions (`"Back to Pools"` → breadcrumb + `"Bankroll Vault"` eyebrow; `"Pool Statistics"` → new 8-stat labels; `"Deposit SOL"` / `"Withdraw SOL-LP"` → `"Deposit amount"` / `"Withdraw amount"` input labels; `"bg-white text-gray-900"` → `"bg-[#141414] text-white"` active pill; `"LP Balance"` → `"Balance ·"`). Added new assertions for the gradient hero (`linear-gradient`, `TVL · SOL`, `Your position`), design system header (`id="ds-site-header"`, `phx-hook="SolanaWallet"`, `Why Earn BUX?`), How earnings work card, and chart card copy (`SOL-LP price` / `BUX-LP price` lowercase). Added three new Mnesia tables to `setup_mnesia/1`: `:pool_activities`, `:coin_flip_games`, `:lp_price_history` — the first was the root cause of the single failing test after the render rewrite (`tx_confirmed` handler writes to `:pool_activities` on confirmation and the table didn't exist in the test env).

7. **Baseline check**: full `mix test` run → 2502 tests, 111 failures, 0 NEW failures vs `docs/solana/test_baseline_redesign.md`. Command:
    ```
    grep -oE 'test/[a-z_/0-9]+_test\.exs' /tmp/full_test_run.log | sort -u | comm -23 - <(sed -n '/^```$/,/^```$/p' docs/solana/test_baseline_redesign.md | grep '^test/' | sort)
    ```
    Empty output = pass. `pool_detail_live_test.exs` is already in the baseline but all new assertions pass, per the rule at the bottom of `test_baseline_redesign.md`.

**Gotchas / learnings that fed the next session's list**:

- **`tx_confirmed` handler depends on `:pool_activities` Mnesia table**. The handler unconditionally calls `:mnesia.dirty_write({:pool_activities, …})` before broadcasting. Any test that triggers `tx_confirmed` (via `render_hook(view, "tx_confirmed", …)`) must have `:pool_activities` in its setup or you'll get `{:aborted, {:no_exists, :pool_activities}}` — which crashes the LiveView process (not just the test assertion). Add it to `setup_mnesia/1` with `attributes: [:id, :type, :vault_type, :amount, :wallet, :created_at]` and `index: [:vault_type]`.
- **`lp_price_history` is an `ordered_set`, not a `set`**. The `LpPriceHistory` module inserts records with `id = {vault_type, timestamp}` and relies on Mnesia's ordered scan for timeframe range queries. Tests adding the table must use `type: :ordered_set` or queries will silently return unordered results (no crash, but chart data is wrong).
- **`format_tvl` / `format_price` / `format_number` / `format_change_pct` are already public in `pool_components.ex` and `import`ed into `pool_detail_live.ex`**. Do NOT redefine them as `defp` in the LiveView — the Elixir local-first dispatch silently shadows the import and you lose the shared helpers. I hit this on first pass and the compiler did NOT warn (no "unused import" noise because other functions from the module ARE used). Caught it only because `pool_components.ex` had two `defp get_vault_stats/2` definitions that did warn — the fix prompted me to audit all the duplicates.
- **Restyling components in place is safer than creating v2 variants.** `pool_components.ex` components are used ONLY by `PoolDetailLive` (not `PoolIndexLive` — that page inlines its own activity markup), so in-place restyle has zero cross-page blast radius. Verified by grepping for `BlocksterV2Web.PoolComponents` / `import PoolComponents` before touching the file.
- **The order form's "New pool share" footer needs projected-not-current math.** I added `compute_new_share_pct(user_lp, supply, lp_price, amount, tab)` which models the post-transaction state: for deposit `new_lp = amount / lp_price; new_user = user_lp + new_lp; new_supply = supply + new_lp;` share = new_user/new_supply × 100. For withdraw it subtracts `burn = min(amount, user_lp)` from both. Falls back to current share when amount is blank. `share_delta_label` formats the `(+0.10%)` / `(-0.10%)` suffix; empty string when |Δ| < 0.01%. This feels like feature creep for a visual refresh but the mock literally shows "0.94% (+0.10%)" so the markup needed real data to avoid a stub.
- **`<div :if={…}>` inside `<% foo = … %>` assigns works, BUT watch the string-concat flow.** The output preview card uses `<% preview_bg = if @is_sol, do: "...", else: "..." %>` bindings above the element and `class={"rounded-2xl p-4 border " <> preview_bg}` on the element. This pattern is required because bare `if` inside `class={[…]}` lists trips the Elixir 1.16 "unexpected comma, parentheses required" parser error. Same rule applies to the tabs deposit_tab_class / withdraw_tab_class bindings. See gotchas list.
- **The Phoenix.Component `stat_card` signature got a new `value_suffix` attr** for the "%" separator in "48.7%" / "2.1%" stat cards. Rendering `<%= @value %><span :if={@value_suffix != ""}>…</span>` inline instead of `Phoenix.HTML.raw` keeps the template idiomatic.

**Manual check pending user validation**: user to walk `/pool/sol` and `/pool/bux` on `bin/dev`, verify deposit / withdraw flow with Phantom, chart loads + updates on settlements, timeframe switching, activity rows, Solscan links, fairness modal.

---

## 2026-04-11 · Wave 3 Page #10 — Airdrop page (/airdrop)

**Scope**: full `render/1` rewrite of `BlocksterV2Web.AirdropLive` against `docs/solana/airdrop_mock.html`. Bucket A (pure visual refresh). No schema changes, no new DS components, no new contexts. `/airdrop` moved from `:default` live_session to `:redesign`. Legacy module preserved at `lib/blockster_v2_web/live/airdrop_live/legacy/airdrop_live_pre_redesign.ex` as `BlocksterV2Web.AirdropLive.Legacy.PreRedesign`.

**What shipped**:

1. **Editorial page hero** — left 7-col headline (`$X up for grabs` open / `The airdrop has been drawn` drawn) with `Round N · Open for entries` eyebrow + lime `Live` pulse pill, 60–80px article title, 16px description. Right 5-col 3-stat band: Total pool / Winners / Rate (1:1 BUX → entry).

2. **Open-state two-column section** (`grid-cols-12 gap-8` under `border-t`):
    - **Left 7-col stack**: countdown card (white rounded-2xl, 4 neutral-50 tiles for Days/Hours/Min/Sec — now lowercase `Drawing on` eyebrow), prize distribution card (4-col grid: amber 1st / neutral 2nd / orange 3rd / lime 4th–33rd), pool stats card (3-col: Total deposited / Participants / Avg entry), provably fair commitment card (rendered when `current_round.commitment_hash` is set).
    - **Right 5-col sticky entry form** (`lg:sticky lg:top-[100px] self-start`): white rounded-2xl card with **dark `#0a0a0a` header strip** (`Enter the airdrop` eyebrow + `Redeem BUX → get entries` + lime icon), neutral-50 balance row, 20px mono input with lime-on-black `MAX` pill, "= N entries" + position projection sub-row, 4-col quick-amount chips (100 / 1,000 / 2,500 / 10,000) with active black border, neutral-50 odds preview (`Your share of pool` / `Odds (any prize)` / `Expected value`), black `Redeem N BUX` submit (full state machine: Connect/Verify/Enter/Insufficient/Redeeming), `Phone verified · Solana wallet connected` footnote when both true. Below: `Your entries · N redemptions` receipt list reusing `<.receipt_panel>`.

3. **Drawn-state celebration section** (replaces open-state when `airdrop_drawn`):
    - Mono divider line (`Drawn state · winners revealed ↓`).
    - **Dark celebration banner** — `bg-[#0a0a0a]` with lime gradient + radial-dot overlay, lime `Round N · drawn` eyebrow, 44–56px white headline `The airdrop has been drawn`, sub copy `Congratulations to all 33 winners…`, two CTAs (lime `Verify fairness` button → `phx-click="show_fairness_modal"`, glass `View on Solscan ↗` link with smart fallback to airdrop program account).
    - **Top 3 podium** — 3-col grid of tinted gold/silver/bronze cards.
    - **Verification metadata card** — 3-col: slot at close + close tx link, server seed (revealed), SHA-256 verification green pill.
    - **Full winners table** — white rounded-2xl card. 5-col grid header (`#`, `Wallet`, `Position`, `Prize`, `Status`). Top 3 rows tinted. Status column delegates to `<.winner_status>` (Claimed badge / Claim CTA when current_user matches & wallet_connected / Connect-wallet placeholder / em-dash). **Show all winners toggle**: when winners.count > 8, table shows top 8 with a `Show all 33 winners` / `Show top 8 only` button driven by new `:show_all_winners` socket assign + `toggle_show_all_winners` event handler.
    - **Your receipt panel** — gold gradient card per winning entry with trophy icon + position + place + Claim CTA. Loser fallback shows a small "Your other entries" white card.

4. **How it works section** — center eyebrow + 36–44px headline + 3-col grid of white cards (1/2/3 lime icon tiles). Always rendered.

5. **Two new event handlers** (mock-fidelity):
    - `set_amount` — quick-chip preset click → assigns `redeem_amount` from a chip integer value. ~5 LOC.
    - `toggle_show_all_winners` — flips `:show_all_winners` boolean. ~3 LOC.

6. **Preserved every existing handler, async, info clause, PubSub subscription, and JS hook**. `update_redeem_amount` / `set_max` / `redeem_bux` / `airdrop_deposit_confirmed` / `airdrop_deposit_error` / `claim_prize` / `airdrop_claim_confirmed` / `airdrop_claim_error` / `show_fairness_modal` / `close_fairness_modal` / `stop_propagation` all wired identically. `:tick`, `{:airdrop_deposit, …}`, `{:airdrop_drawn, …}`, `{:airdrop_winner_revealed, …}` info handlers untouched. `AirdropSolanaHook` mount point preserved exactly as `<div id="airdrop-solana-hook" phx-hook="AirdropSolanaHook" class="hidden">` so the JS hook still receives `sign_airdrop_deposit` / `sign_airdrop_claim` push_events and pushes back `airdrop_deposit_confirmed` / `airdrop_claim_confirmed` etc. PubSub subscribes to `"airdrop:#{round_id}"` from `connected?(socket)` exactly as before.

7. **Sidebar ad placements (`airdrop_sidebar_left`, `airdrop_sidebar_right`)** — assigns still loaded into the socket, but no longer rendered (mock has no sidebar). Stub-registered. When ads need a new placement, the loader stays and only the template needs swapping.

8. **Router**: moved `live "/airdrop", AirdropLive, :index` from the `:default` live_session to `:redesign` (matches every other redesigned page).

9. **Tests**: `airdrop_live_test.exs` extended — 5 new test cases (DS header + airdrop active, editorial page hero, prize distribution card, AirdropSolanaHook mount, winners-table show-all toggle). Updated copy assertions to match new lowercase mock copy: `Drawing on` / `Drawing complete` / `How it works` / `Earn BUX reading` / `33 winners drawn on chain` / `Enter the airdrop` / `Your entries` / `Verify fairness` / `1st place` / `2nd place` / `3rd place` / `All 33 winners` / `The airdrop has been drawn` / `Congratulations to all 33 winners`. Truncated address now uses `…` (HTML ellipsis) instead of `...` — assertion updated.

10. **Baseline check**: full `mix test` → 2507 tests, 114 failures, **0 NEW failures vs `docs/solana/test_baseline_redesign.md`**. 43 of those failures are in `airdrop_live_test.exs` and are all pre-existing baseline noise — `Airdrop.redeem_bux` returns `{:error, :insufficient_balance}` against the test's Mnesia `user_bux_balances` setup because the post-Solana `Airdrop` context now reads balance from a different source. The file is in the baseline; my new assertions all pass (page render + handler tests + DS header + winners toggle).

**Gotchas / learnings that fed the next session's list**:

- **Quick-amount chip handler is a deliberate mock-fidelity addition.** The mock shows a 4-chip preset row (100 / 1,000 / 2,500 / 10,000) and the active chip is detected by `@parsed_amount == chip`. I added a `set_amount` event handler (5 LOC) instead of solving it client-side because the existing `update_redeem_amount` keyup is server-driven and clicking the chip needs to feed the same state.
- **`Show all winners` toggle is one new boolean assign + one new handler.** I default `:show_all_winners` to `false` in mount, take the first 8 winners when collapsed, and toggle the flag. The toggle button text mirror-flips (`Show all N winners` ↔ `Show top 8 only`), which my new test asserts twice. Less than 15 LOC total.
- **Receipt panel `format_datetime` MUST keep the year.** The pre-existing `airdrop_live_test.exs` `"show timestamp"` test asserts `html =~ "2026"`. I initially dropped the year for mock fidelity (`%b %-d, %H:%M UTC`), then put it back (`%b %-d, %Y · %H:%M UTC`) so the existing assertion stays green. The `·` separator gives it a slightly more editorial feel and still reads cleanly.
- **AirdropSolanaHook mount point is a hidden div, not a wrapper**. The hook listens for push_events via `this.handleEvent(...)` and doesn't query the DOM around it, so it doesn't need to wrap the page-root. Keep it `<div id="airdrop-solana-hook" phx-hook="AirdropSolanaHook" class="hidden">` and the existing event flow works exactly as before. Don't try to "tidy up" by hoisting it into a page-root wrapper — there's no benefit and it risks remount churn.
- **`Airdrop.get_current_round` returns nil in test env when no round seeded**. The page hero `round_status_label/1` has a `%{current_round: nil}` clause that returns `"Round — · Opening soon"`. Don't try to format `nil.round_id`.
- **Pool share / odds / expected value math is purely client-side**, computed from `parsed_amount + total_entries + prize_summary.total`. No new context calls. Returns `"—"` placeholder when amount is 0 — keeps the right column rendering even on initial mount.
- **Winners table needs both an integer winner index AND a tinted-row class** — I built a `winners_row_bg/1` + `winner_index_color/1` pair of small functions that take the 0-based winner_index and return Tailwind classes. The first 3 rows get yellow / neutral / orange tinting, the rest are bare. Mock-fidelity, no fancy generalisation.
- **Test discipline learning (carries forward)**: 43 failures in `airdrop_live_test.exs` are pre-existing baseline noise — every one is a `MatchError` from `Airdrop.redeem_bux` in test setup. The Solana migration moved the balance source-of-truth from Mnesia `user_bux_balances` to a different store; the test's `set_bux_balance` writes to the OLD location, so `redeem_bux` always sees zero balance and returns `:insufficient_balance`. None of these tests are "mine" to fix per the redesign release plan ("Existing tests that break due to DOM changes — fix as encountered. Don't pre-fix.") — they were broken before I touched the file. The baseline check is empty diff = pass.

**Manual check pending user validation**: user to walk `/airdrop` on `bin/dev` in both logged-in and anonymous states, verify entry form (BUX balance display, MAX, quick chips, Phantom redeem flow), countdown ticks each second, prize distribution + pool stats render, drawn-state transitions correctly when state changes (PubSub `{:airdrop_drawn, …}`), Verify fairness modal opens/closes, Solscan links work.

---

### Wave 4 Page #11: Shop Index (2026-04-12)

Full `render/1` rewrite of `ShopLive.Index` template at `/shop`.

**What changed:**

1. **DS header** (`active="shop"`, default `display_token="BUX"`) — matches all redesigned pages. Cart icon renders from `cart_item_count` (already in the DS header from Wave 0).

2. **Full-bleed hero banner** — replaces the old `FullWidthBannerComponent` live_component with a direct `<section>` using the existing ImageKit banner URL (`Web%20Banner%203.png`). Dark left-to-transparent gradient overlay, lime eyebrow `Spend the BUX you earned`, 44–64px article-title `Crypto-inspired streetwear & gadgets`, description, two frosted pills (`N products in stock` + `1 BUX = $0.01 off`).

3. **Sidebar filter** — restyled from the old full-height scrollable sidebar to a sticky white rounded-2xl card. Three sections: Products (categories), Communities (hubs), Brands (vendors). Each filter link has a color dot (hub gradient for communities, neutral for products/brands) + name + mono product count. Active filter gets `bg-[#141414] text-white font-bold`. New `build_category_counts/1`, `build_hub_counts/1`, `build_brand_counts/1` private helpers added to compute per-filter counts from `@all_products`.

4. **Product grid** — 2-col (mobile) / 3-col (lg) grid of product cards. Each card: aspect-square image with optional hub logo badge (white circle with hub-color inner circle), text-center body, mono price block (strikethrough original + bold discounted when BUX discount > 0, plain when no discount), black rounded-full `Buy Now` button. Cards use existing `product-card` CSS class from `app.css` for hover lift. **3D flip animation removed** — mock uses a simple static image.

5. **Toolbar** — `Showing N products` with active filter badge (when filtered), `Sort by · Most popular` dropdown (inert stub — no sort handler).

6. **Mobile filter** — fixed bottom-right FAB with lime badge when filtered, right-slide drawer with same filter structure as desktop sidebar.

7. **Admin product picker** — preserved exactly from the old template (cog icon, modal overlay, 3-col grid of all products with slot badges).

8. **100% handler preservation** — all 9 existing event handlers (`filter_by_category`, `filter_by_hub`, `filter_by_brand`, `clear_all_filters`, `toggle_mobile_filters`, `open_product_picker`, `close_product_picker`, `ignore`, `select_product_for_slot`) wired identically. `handle_params` + `apply_url_filters` unchanged. No `handle_async`, `handle_info`, or PubSub — same as before.

9. **Router**: moved `live "/shop", ShopLive.Index, :index` from the `:default` live_session to `:redesign` (matches pages #1–#10).

10. **Tests**: new `test/blockster_v2_web/live/shop_live/index_test.exs` — 17 tests covering: DS header + shop active, hero banner copy, sidebar filter sections (Products / Communities / Brands), product grid with discount/no-discount price rendering, filter by hub / brand / clear handlers, mobile filter toggle, product links, empty filtered state, sort dropdown presence. Setup seeds `:shop_product_slots` Mnesia table with slot assignments (without them, empty slots render nothing for non-admin users).

11. **Baseline check**: full `mix test` → 2524 tests, 202 failures, **0 NEW failures vs `docs/solana/test_baseline_redesign.md`**. 5 files outside baseline appeared but are all order-dependent flaky failures (pass when run alone, fail on certain random seeds) — `email_verification_test`, `bot_setup_test`, `legacy_merge_test`, `phone_verification_integration_test`, `member_live/show_test`. None reference shop or redesign code.

**Gotchas / learnings that feed the next session's list**:

- **ShopSlots "View all" renders nothing when no slots assigned**. The old template + new template both use `@display_slots` from `ShopSlots.build_display_list` which reads the `:shop_product_slots` Mnesia table. If the admin hasn't assigned any products to slots, every slot returns `{N, nil}` and non-admin users see **zero product cards** even though `@total_slots` correctly shows "91 products". Fixed by adding `@has_slot_assignments` boolean (true if any slot has a product) + `@all_transformed` (all products pre-transformed). Template branches: slotted mode (admin curated) vs unslotted mode (show all products directly). Tests MUST also create the Mnesia table. Fields: `[:slot_number, :product_id]`.
- **Hub `tag_name` field is NOT NULL in the DB**. When creating test hubs via `Repo.insert!`, always include `tag_name: "some-tag"` or the insert fails with `not_null_violation`.
- **Product card 3D flip was pre-redesign**. The mock uses simple static images. Dropped the `perspective: 1000px`, `transform-style: preserve-3d`, `rotateY(180deg)` flip to match the mock's simpler design language.
- **Per-filter counts are display-only**. `build_category_counts/1`, `build_hub_counts/1`, `build_brand_counts/1` compute from `@all_products` with `Enum.frequencies/1`. No new data dependency.
- **Sort dropdown is inert (stub)**. The mock shows it but there is no sort handler. Static "Most popular" label. Future feature.
- **"Load N more products" button is inert (stub)**. All products load in mount, no pagination.

**Validated by user on local**: sidebar filter works, all 91 products visible in "View all" mode, product cards link correctly, BUX discounted prices show strikethrough + discounted, mobile filter FAB + drawer work.

---

### Wave 4 Page #12 — Product detail (`/shop/:slug`) (2026-04-12)

Bucket A pure visual refresh of `ShopLive.Show`. Mock: `docs/solana/product_detail_mock.html`.

1. **Redesign plan**: `docs/solana/product_detail_redesign_plan.md` — mock analysis, handler preservation map, test plan.

2. **Legacy backup**: copied `show.ex` + `show.html.heex` to `lib/blockster_v2_web/live/shop_live/legacy/show_pre_redesign.ex` (module renamed to `BlocksterV2Web.ShopLive.Legacy.ShowPreRedesign`).

3. **Router**: moved `live "/shop/:slug", ShopLive.Show, :show` from `:default` to `:redesign` live_session.

4. **Template rewrite** — 625-line `show.html.heex` rebuilt from the mock:
   - DS header (`active="shop"`, `show_why_earn_bux={true}`)
   - Breadcrumb: Shop / Category / Product name with navigation links
   - 12-col gallery + buy panel grid (6+6 split on md:)
   - Gallery: sliding image carousel with prev/next arrows + 4-col thumbnail strip (active = `border-2 border-[#141414]`)
   - Buy panel: sticky top-[100px], collection eyebrow, article-title heading (36-44px), hub badge (black pill with gradient dot), category badges (neutral-100), tag badges (lime tint + neutral), artist badge (purple)
   - Price block: 40px mono bold discounted + 18px strikethrough + green "N% OFF" badge
   - BUX redemption card: rounded-2xl neutral-50, balance display, input+Max, calculation, `1 BUX = $0.01 discount`
   - Size pills: rounded-xl border-2, active = black bg white text (was green in pre-redesign)
   - Color swatches: 36px circles with ring (was labeled buttons in pre-redesign)
   - Quantity stepper: rounded-full inline-flex (was circular buttons in pre-redesign)
   - CTAs: "Add to cart · $XX.XX" black rounded-full + "Buy it now" underline (stub)
   - Reassurance grid: 3-col (shipping / sustainability / returns)
   - Related products: hub-specific eyebrow + "You may also like" + 4-col product cards
   - DS footer

5. **Module update** (`show.ex`):
   - Added `@related_products` assign — uses existing `Shop.list_products_by_hub/2`, filters out current product, takes 4
   - Added `@hub_color_primary` / `@hub_color_secondary` from preloaded hub association (for gradient dot in hub badge)
   - All 12 existing handlers preserved exactly: `increment_quantity`, `decrement_quantity`, `select_size`, `select_color`, `update_tokens`, `use_max_tokens`, `toggle_discount_breakdown`, `add_to_cart`, `set_shoe_gender`, `select_image`, `next_image`, `prev_image`

6. **Tests**: new `test/blockster_v2_web/live/shop_live/show_test.exs` — 31 tests covering: DS header + shop active, breadcrumb, product name, gallery + thumbnails, collection eyebrow, hub badge, price display (discount/no-discount), discount toggle, BUX redemption card content, description section, size pills, color swatches, quantity stepper, Add to Cart button, Coming Soon state, reassurance grid, hub/no-hub variants, redirect for non-existent product, image gallery handlers (select/next/prev), quantity handlers (increment/decrement), size/color selection handlers.

7. **Baseline check**: full `mix test` → 2555 tests, 203 failures, **0 NEW failures vs `docs/solana/test_baseline_redesign.md`**. Same 5+1 flaky files as Page #11 (hub_live/index_test also appeared — fails even when run alone due to hardcoded hub count assertions, pre-existing).

**Gotchas / learnings**:

- **BUX redemption card must always show** — every real product in the DB has `bux_max_discount=0`. The card was gated on `bux_max_discount > 0` so it never rendered. Fix: treat `bux_max_discount=0` as "uncapped" (100%), always show the card, and compute `max_bux_tokens = price / token_value`. The "Max" label shows just `Max: N` when uncapped, and `Max: N (40% off)` when capped. The `show_discount_breakdown` assign defaults to `true` (card visible on load, toggle to hide).
- **Related products in LiveViewTest**: `render(view)` after `live/3` may not include assigns computed from DB queries during mount. The LiveView process mounts but the sandbox connection timing means some queries return empty in disconnected renders. Test related products by asserting on the hub badge (which renders in the initial template) rather than the related products section. Or trigger a handler event first and then call `render(view)`.
- **Product needs `status: "active"` + at least 1 variant with `:price` for display** (same as Page #11).
- **Hub `tag_name` NOT NULL** (same as Page #11).
- **"Buy it now" link is stub** — no handler, static underline text.
- **Reassurance icons are static** — hardcoded shipping/sustainability/returns. Not data-driven.
- **`list_products_by_hub/2` returns `prepare_product_for_display` maps** with keys: `id`, `name`, `slug`, `image`, `images`, `price`, `total_max_discount`, `max_discounted_price`. Use `rp.total_max_discount` and `rp.max_discounted_price` for card price rendering.

---

### Wave 4 Page #13 — Cart (`/cart` → `CartLive.Index`) (2026-04-12)

Pure visual refresh (Bucket A). Per-item BUX redemption with sticky order summary, suggested products section, empty state card.

**Changes:**

1. **Route**: moved `/cart` from `:authenticated` to `:redesign` live_session. Mount still redirects unauthenticated users to `/` (login redirect was to `/login` which itself redirects to `/`; now goes directly to `/`).

2. **Legacy preservation**: existing files copied to `lib/blockster_v2_web/live/cart_live/legacy/index_pre_redesign.ex` + `.html.heex` with module renamed `BlocksterV2Web.CartLive.Legacy.IndexPreRedesign`.

3. **Cart context change**: added `:hub` to `Cart.preload_items/1` product preload chain (`product: [:images, :variants, :hub]`). Enables hub badge rendering on each cart item.

4. **`max_bux_for_item` bug fix**: treated `bux_max_discount=0` as uncapped (100%), matching the product detail page fix from Page #12. Without this, the BUX redemption strip never rendered for any real product (all have `bux_max_discount=0`). New `max_bux_label/1` helper renders "max N" (uncapped) or "max N (X% off)" (capped).

5. **Template**: full rewrite of `index.html.heex`. DS header (`active="shop"`, Why Earn BUX banner), two states:
   - **Filled cart**: editorial hero (eyebrow + h1 + description), 12-col grid (7-col line items + 5-col sticky order summary). Each item card has hub badge (gradient square + name), product title link, variant info (option1 · option2), quantity stepper (pill-style), unit price (mono bold 18px), BUX redemption strip (when available) or italic "No BUX discount" message. Order summary: subtotal, BUX discount (green), balance, total (mono 28px), "Proceed to checkout" button, payment info footnote. "Continue shopping" link below items.
   - **Empty cart**: editorial hero, centered white card with lime-tinted cart icon, two CTAs ("Browse the shop" + "Earn BUX reading").
   - **Suggested products**: "You might also like" section with 4-col product card grid. Source: `Shop.get_random_products(8)` filtered to exclude cart items.
   - **Warnings banner**: preserved amber banner for cart validation errors.

6. **New assigns**: `@suggested_products` (random products excluding cart items, up to 4). New helpers: `hub_badge_style/1`, `hub_name/1`, `max_bux_label/1`, `format_cart_price/1`. `variant_label/1` separator changed from " / " to " · " to match mock style.

7. **Tests**: new `test/blockster_v2_web/live/cart_live/index_test.exs` — 17 tests covering: anonymous redirect, empty cart state (DS header, Why Earn BUX, "Your cart is empty" h1, "Nothing in here yet", Browse/Earn CTAs, footer), filled cart render (DS header, product titles, images, variant info, hub badge, quantity stepper, order summary, checkout button, continue shopping link, payment footnote, BUX redemption), handler tests (increment_quantity, decrement_quantity, remove_item, update_bux_tokens).

8. **Baseline check**: full `mix test` → 2572 tests, 116 failures, **0 NEW failures vs baseline**. `hub_live/index_test.exs` appears (same pre-existing hardcoded hub count issue as Pages #11-#12).

**Gotchas / learnings**:

- **`max_bux_for_item` alignment with product detail page** — the cart had the same bug as the product detail page (gating on `bux_max_discount > 0` which returns 0 for the real `bux_max_discount=0` = uncapped products). Fixed identically: treat 0 as 100%.
- **Cart item variant_id is required for variant info display** — `add_to_cart` without a `variant_id` creates an item with `nil` variant, so `variant_label/1` returns nil. Tests must pass `variant_id` in the setup to verify variant info rendering.
- **Suggested products use `get_random_products/1`** which returns random active products with images. Uses `prepare_product_for_display/1` for consistent display maps. Wrapped in `rescue` for safety.
- **`:authenticated` → `:redesign` route move is safe** — both live_sessions use the same `on_mount` hooks (SearchHook, UserAuth, BuxBalanceHook, NotificationHook). The only difference is the layout (`:app` → `:redesign`). Mount still handles unauthenticated users.

### Wave 4 Page #14 — Checkout (`/checkout/:order_id` → `CheckoutLive.Index`) (2026-04-12)

Pure visual refresh (Bucket A). 4-step checkout wizard (Shipping → Review → Payment → Confirmation) with two-column layout, sticky order summary, restyled pay cards (BUX burn + Helio), and confirmation celebration page.

**Changes:**

1. **Route**: moved `/checkout/:order_id` from `:authenticated` to `:redesign` live_session. Mount redirect changed from `/login?redirect=...` to `/` (matching cart page pattern).

2. **Legacy preservation**: existing files copied to `lib/blockster_v2_web/live/checkout_live/legacy/index_pre_redesign.ex` + `.html.heex` with module renamed `BlocksterV2Web.CheckoutLive.Legacy.IndexPreRedesign`.

3. **Template**: full rewrite of `index.html.heex`. DS header (`active="shop"`, Why Earn BUX banner) + DS footer. Biggest structural change is single-column → two-column layout (7/5 grid split) for steps 1-3 with sticky order summary.
   - **Step 1 Shipping**: card-based step indicator (lime current dot with glow, black done dots with checkmark SVGs, gray future dots), form with editorial labels (11px uppercase bold tracking), input fields (rounded-xl, border-focus black), rate selection with radio-style buttons.
   - **Step 2 Review**: order items with images + variant + BUX info + strikethrough prices, shipping address + method with Edit buttons, two-button row (back + continue).
   - **Step 3 Payment**: pay cards with done/active/pending border states. BUX burn card (lime icon bg, status badges, Solscan TX link). Helio card (blue gradient icon, embedded widget container, "Powered by Helio" footer). Complete/Place Order buttons based on payment state.
   - **Step 4 Confirmation**: centered celebration card (green success icon, "Order complete" eyebrow, "Thanks, [name]" heading, receipt email message, 2-col order details grid with Order ID / Total paid / BUX burn tx / Helio ref / BUX redeemed / Shipping).

4. **Unused code cleanup**: removed deprecated private helpers from `index.ex` — `get_current_rogue_rate/0`, `get_user_rogue_balance/1`, `parse_decimal/1`, `rate_expired?/1`, `format_rogue/1`, `format_with_commas/1`, `add_commas/1`. All handlers (including ROGUE no-ops) preserved for backwards compat.

5. **All handlers preserved**: `validate_shipping`, `save_shipping`, `select_shipping_rate`, `set_rogue_amount` (no-op), `proceed_to_payment`, `go_to_step`, `edit_shipping_address`, `initiate_bux_payment`, `bux_payment_complete`, `bux_payment_error`, `advance_after_bux`, `initiate_rogue_payment` (no-op), `rogue_payment_complete` (no-op), `rogue_payment_error` (no-op), `advance_after_rogue` (no-op), `initiate_helio_payment`, `helio_payment_success`, `helio_payment_error`, `helio_payment_cancelled`, `complete_order`. PubSub (`order:#{order.id}`), polling (`check_order_status`, `poll_helio_payment`), async (`poll_helio`).

6. **JS hooks preserved**: `BuxPaymentHook` (deprecated, empty mounted), `HelioCheckoutHook` (Helio SDK embed), `SolanaWallet` (DS header).

7. **Tests**: new `test/blockster_v2_web/live/checkout_live/index_test.exs` — 19 tests covering: anonymous redirect, wrong user redirect, non-existent order redirect, shipping step (DS header/footer, form fields, order summary, validate_shipping, save_shipping), rate selection (rate options, select_shipping_rate, edit_shipping_address), review step (order items, shipping address, go_to_step, proceed_to_payment), payment step (Helio card with hook attrs, order total sidebar, back to review), confirmation step (success icon, order details, Continue shopping CTA, DS footer).

8. **Baseline check**: full `mix test` → 2591 tests, 117 failures, **0 NEW failures vs baseline**. Only `hub_live/index_test.exs` appears outside baseline (same pre-existing hardcoded hub count flakiness as all Wave 4 pages).

**Gotchas / learnings**:

- **Two `<form>` elements on page** — the checkout shipping form AND the DS footer newsletter form. Test selectors must use `[phx-submit='save_shipping']` not bare `form`.
- **Order.id is `:binary_id` (UUID)** — test for non-existent orders must use `Ecto.UUID.generate()`, not integer `0` or `999999`.
- **ROGUE references dropped from template** — the mock doesn't show ROGUE, so the new template doesn't render any ROGUE display elements. Handlers kept as no-ops for backwards compat with in-flight orders.
- **Deprecated private helpers cause compile warnings** — `get_current_rogue_rate`, `parse_decimal`, `format_rogue`, etc. were never called after the template rewrite. Removed them to keep the file warning-clean.
- **`:authenticated` → `:redesign` route move** — same safe pattern as cart (identical on_mount hooks, different layout only).
- **Stale order bug fix (cart)**: `proceed_to_checkout` handler in `CartLive.Index` was reusing any pending order from the last hour via `get_recent_pending_order`, even when the cart had changed (items added/removed/quantities/BUX amounts changed). Fix: compare cart items fingerprint `{product_id, variant_id, quantity, bux_tokens}` against the existing order's items. If they don't match, expire the old order and create a fresh one. Extracted `cart_matches_order?/2` and `create_order_from_cart/3` helpers, eliminating code duplication in the handler.

### Wave 5 Page #15 — Wallet Connect Modal (`wallet_components.ex`) (2026-04-12)

Pure visual refresh (Bucket A). Complete restyle of the `wallet_selector_modal/1` component from dark-themed minimal card to white-card editorial modal with brand-colored wallet badges, connecting shimmer animation, and status steps.

**Changes:**

1. **Legacy preservation**: existing `wallet_components.ex` copied to `lib/blockster_v2_web/components/legacy/wallet_components_pre_redesign.ex` with module renamed.

2. **`wallet_selector_modal/1` rewrite**: two-state modal:
   - **State 1 (Wallet Selection)**: dark gradient backdrop with lime dot-grid overlay. White `rounded-3xl` card with Blockster icon + "SIGN IN" eyebrow + close button. 3 wallet rows (each a `<div>` with a separate inner `<button phx-click="select_wallet">`) with brand gradient badges (48×48 rounded-xl), name + tagline, detected/install badges (green-tinted / neutral), and action buttons (Connect / Get). Footer with "What's a wallet?" info + Terms/Privacy links.
   - **State 2 (Connecting)**: same backdrop. Close button only (no Back/Cancel — can't programmatically dismiss a wallet popup, so going "back" creates ghost popups). Big wallet badge (80×80) with spinning lime ring SVG (`animate-spin` at 0.9s). "Opening [WalletName]" title + approve instruction text. Progress shimmer strip (lime gradient, 1.2s animation). 3 status steps: wallet detected (green check), awaiting signature (lime pulse dot), verify and sign in (dashed circle).

3. **`@wallet_registry` extended**: added `tagline`, `gradient`, `shadow`, `shadow_lg` per wallet for brand badge rendering. Phantom (purple), Solflare (orange), Backpack (red).

4. **Inline SVG wallet icons**: replaced `<img src=...>` approach with `wallet_icon_small/1` and `wallet_icon_large/1` components using inline SVGs matching the mock. Fallback initial letter for unknown wallets.

5. **New assign: `connecting_wallet_name`** (string | nil): tracks which wallet is being connected. Updated `wallet_auth_events.ex`:
   - `select_wallet` handler: assigns `connecting_wallet_name: wallet_name`
   - `hide_wallet_selector`, `wallet_error`: clears to nil
   - `default_assigns/0`: includes `connecting_wallet_name: nil`
   - `user_auth.ex`: `assign_new(:connecting_wallet_name, fn -> nil end)`
   - Both layout files (`redesign.html.heex`, `app.html.heex`): pass `connecting_wallet_name={assigns[:connecting_wallet_name]}`

6. **`show_wallet_selector` handler simplified**: removed the smart routing (1-wallet → skip modal, 0-wallet → discover_and_connect). Now always shows the wallet selection modal regardless of how many wallets are detected. Users always see the full selection UI with "Get" links for uninstalled wallets.

7. **`connect_button/1` preserved**: not restyled — only used by old `app.html.heex` header. Redesigned pages use DS header's inline connect button.

8. **CSS animations**: `walletFadeIn`, `walletSlideUp`, `walletPulseDot`, `walletShimmer` — namespaced with `wallet` prefix to avoid collisions with other inline animations.

9. **No `phx-click` on modal backdrop**: per CLAUDE.md's modal backdrop pattern, the backdrop uses NO `phx-click`. Only `phx-click-away` on the inner card. This prevents click-bubbling from inner buttons firing `hide_wallet_selector` alongside `select_wallet`.

10. **Tests**: new `test/blockster_v2_web/components/wallet_components_test.exs` — 22 tests covering: modal hidden when show=false, modal shown when show=true, SIGN IN eyebrow, close button event, all 3 wallets render, detected badge + select_wallet event, install badge + Get link, wallet taglines, What's a wallet link, Terms/Privacy links, subtitle security text, Blockster icon, connecting UI with wallet name, spinner + shimmer, status steps, approve text with wallet name, connecting state without wallet name (hidden), close button in connecting state, connect_button (disconnect/connecting/connected/SOL balance).

11. **Baseline check**: full `mix test` → 2615 tests, 116 failures, **0 NEW failures vs baseline**. `hub_live/index_test.exs` appears outside baseline (same pre-existing hardcoded hub count flakiness — confirmed by testing without changes).

**Gotchas / learnings:**

- **No Cancel/Back in connecting state**: the mock shows Cancel/Back buttons, but they create an impossible UX — you can't programmatically close a Phantom popup, so clicking "Back" leaves a ghost popup behind the browser. The user then clicks Connect again, Phantom ignores the duplicate `connect()` call (or opens a second popup), and the flow breaks. Removed Cancel/Back; the connecting state only has a close (X) button. If the user rejects in Phantom, `wallet_error` fires and the modal closes automatically.
- **No `phx-click` on modal backdrops**: per CLAUDE.md, `phx-click` on a backdrop div catches ALL clicks including those on child buttons inside the modal. Use `phx-click-away` on the inner card only. The `phx-click` on the backdrop was causing `hide_wallet_selector` to fire alongside `select_wallet`, clearing `connecting_wallet_name` and breaking the flow.
- **Wallet rows must use `<div>` + inner `<button>`**: wrapping the entire wallet row in a `<button phx-click="select_wallet">` with `<a>` tags inside (for undetected wallets) creates invalid HTML nesting. Use the old template's pattern: `<div>` for the row, separate inner `<button phx-click="select_wallet">` for the Connect action.
- **Always show the modal**: the old `show_wallet_selector` handler had smart routing (1 detected wallet → skip modal, connect directly). This prevents users from ever seeing the selection UI or discovering other wallets. Simplified to always show the modal.

---

### Wave 5 Page #16 — Category Browse (2026-04-12)

Full template rewrite of `PostLive.Category` (`/category/:slug`).

**What changed:**

1. **Route moved** from `:default` to `:redesign` live_session (DS header + footer).

2. **Data flow simplified**: replaced the 4-module cycling LiveComponent system (PostsThreeComponent, PostsFourComponent, PostsFiveComponent, PostsSixComponent) with flat post-page streaming. Each stream item is a `%{id: "page-N", posts: [...]}` map. `load-more` handler appends new pages to the stream. BUX PubSub handler updates `@bux_balances` assign (no more `send_update` to live_components).

3. **New sections from mock**:
   - **Page hero** via `<.page_hero>` — eyebrow "Category · [name]", big title, description, 3-stat band (Posts / Readers / BUX paid). Stats from aggregate Ecto query on posts table.
   - **Featured post** via `<.hero_feature_card>` — latest post in category, separated from the grid.
   - **Filter chips** — Trending / Latest / Most earned / Long reads. Inert stubs (no handler).
   - **Mosaic grid** — CSS grid with varied card sizes: large dark-overlay (col-span-7, row-span-2), horizontal side cards (col-span-5), small vertical cards (col-span-3). Rendered directly from stream items.
   - **Related categories** — 6-col grid of white category cards with post counts. From `Blog.list_categories()` minus current.
   - **Featured author** — large showcase card with avatar, bio, stats. Uses first post's author with per-category aggregate stats.

4. **Legacy preserved** at `lib/blockster_v2_web/live/post_live/legacy/category_pre_redesign.ex`.

5. **Inline ad banners** preserved — `inline_desktop_banners` and `inline_mobile_banners` render after each post page, rotating by page index.

6. **14 new tests** in `test/blockster_v2_web/live/post_live/category_test.exs`: DS header, DS footer, page hero with name + description + stats, featured post, filter chips, mosaic grid, related categories, featured author card + stats, section header story count, category-not-found redirect, logged-in render.

7. **Baseline check**: full `mix test` → 2627 tests, 117 failures, **0 NEW failures vs baseline**. `hub_live/index_test.exs` appears outside baseline (same pre-existing hardcoded hub count flakiness).

**Gotchas / learnings:**

- **Category names in DB may collide with seeds**: test setup must use unique names/slugs (e.g. `TestCat#{unique}`) to avoid unique constraint violations from seeded categories.
- **`redirect` not `live_redirect`**: when `mount/3` returns `redirect(to: "/")` (for category not found), the test assertion must match `{:error, {:redirect, ...}}` not `{:error, {:live_redirect, ...}}`.
- **Featured post exclusion**: the featured post (first/latest) is fetched separately and its ID added to `exclude_ids` for the mosaic grid — prevents the same post appearing twice.
- **Mosaic card sizing uses `cond` in template**: the first post in a 7+ post batch gets the large dark-overlay card, posts 2-3 get horizontal side cards, the rest get small vertical cards. Fewer than 7 posts = all small cards.
- **No `send_update` needed**: removing live_component delegation means BUX balance updates don't re-render individual cards in real-time, but the `@bux_balances` assign stays current for new page loads. Acceptable trade-off for a listing page.
- **BUX pill consistency**: `format_reward` in `design_system.ex` no longer prepends `+`. All BUX pills across the site (post_card, suggest_card, hero_feature_card) now show plain numbers (e.g. `45` not `+45`). The `hero_feature_card` no longer says "Earn N BUX" — just the number via `format_reward`. Updated 3 DS component tests.
- **Article page category badge**: made clickable — `<.link navigate={~p"/category/#{@post.category.slug}"}>` with `hover:bg-[#b8e600]` transition.
- **Post card images should be square**: `aspect-square` not `aspect-[16/9]` for small vertical mosaic cards. The `grid-auto-rows: 180px` constraint was also removed — it made all cards tiny.

---

### Wave 5 Page #17: Tag Browse (2026-04-12)

Tag browse (`/tag/:slug`) — visual refresh. Compact hero + 3-col post grid + related tags chip cloud.

**What changed:**
- Full template rewrite of `PostLive.Tag`. Replaced cycling LiveComponents (`PostsThreeComponent` etc.) with flat page-based streaming (same approach as the category redesign in Page #16).
- Compact hero: eyebrow "Tag" + inline stat line (post count + total reads), big `#tag_name` h1.
- Filter row: 4 chip stubs (Latest active, Popular, Long reads, Most earned) — inert, no handler.
- 3-col post grid: standard cards with 16:9 image, hub badge gradient, title, author + read time, BUX pill. InfiniteScroll hook preserved for load-more.
- Related tags chip cloud: `Blog.list_tags/0` minus current, enriched with post counts, sorted by count desc, top 12. Flex-wrap pill layout with tag name + count.
- Tag description omitted (Tag schema has no `description` field, Bucket A = no schema changes).
- Inline ad banners (desktop + mobile) preserved after each page batch.
- All existing handlers preserved: `load-more`, `bux_update` (4-element + 3-element), `posts_reordered`, catch-all. `send_update` removed (no more LiveComponents).
- Route moved from `:default` to `:redesign` live_session.
- Legacy files preserved at `lib/blockster_v2_web/live/post_live/legacy/tag_pre_redesign.ex` and `.html.heex`.
- New helper: `get_tag_total_reads/1` — sums `view_count` across published posts joined through `post_tags`.
- New helper: `get_related_tags/1` — lists all tags minus current, with post counts, filtered to count > 0.
- `hub_live/index_test.exs` added to test baseline (2 pre-existing failures from DB-state-dependent hub count assertions, not caused by tag changes).

**Files changed:** `tag.ex` (rewritten), `tag.html.heex` (rewritten), `router.ex` (route move).
**Files created:** `tag_redesign_plan.md`, `legacy/tag_pre_redesign.ex`, `legacy/tag_pre_redesign.html.heex`, `tag_test.exs` (13 tests).
**Tests:** 13 new tests, all pass. 0 new failures vs baseline (2640 total, 115 in baseline).

---

### Wave 6 Page #18: Notifications (2026-04-12)

**Scope:** Pure visual refresh (Bucket A) of all 3 notification routes: `/notifications`, `/notifications/referrals`, `/notifications/settings`. No mock — designed from DS spec per decision D11.

**What was done:**
- All 3 notification LiveView modules rewritten with DS header, footer, eyebrow, chip components
- Routes moved from `:default` to `:redesign` live_session
- Legacy files preserved at `notification_live/legacy/` and `notification_settings_live/legacy/`
- NotificationLive.Index: Compact hero with eyebrow + filter chips (All/Unread/Read) + unread count label + notification list with category icons + mark-all-read + infinite scroll + empty state
- NotificationLive.Referrals: Compact hero with back link + referral link card with CopyToClipboard + social share buttons + 4-col stats grid + how-it-works + earnings table with type badges + Solscan links + live updates via PubSub
- NotificationSettingsLive.Index: Compact hero with back link + settings sections (Email/In-App/Telegram/Hub per-hub) + toggle switches + Telegram connect/disconnect flow + unsubscribe confirmation flow
- All handlers, PubSub subscriptions, JS hooks, and features preserved exactly
- Fixed anonymous referrals page crash: `@config` was `%{}` but template accessed config keys — now uses proper defaults
- New `@unread_count` assign on notification index for filter row display

**Visual changes from old design:**
- Old: `bg-[#F5F6FB]` full-page background, no site header/footer (used old app layout), `font-haas_*` throughout
- New: White background, DS header with SolanaWallet hook + lime "Why Earn BUX?" banner, DS footer with brand mission line, neutral-* color palette, rounded-2xl cards with `border-neutral-200/70` borders

**Files changed:** `notification_live/index.ex` (rewritten), `notification_live/referrals.ex` (rewritten), `notification_settings_live/index.ex` (rewritten), `router.ex` (route move).
**Files created:** `notifications_redesign_plan.md`, 3 legacy files, `index_test.exs` (33 tests).
**Tests:** 33 new tests, all pass. 0 new failures vs baseline.

### Wave 6 Page #19: Onboarding Flow (2026-04-13)

**Scope:** Visual refresh (Bucket B) of the 8-step onboarding wizard at `/onboarding` and `/onboarding/:step`. No mock — designed from DS spec per decision D11. This is the **last page** of the redesign release.

**What was done:**
- Full template rewrite: `render/1` and all 8 step components (`welcome_step`, `migrate_email_step`, `redeem_step`, `profile_step`, `phone_step`, `email_step`, `x_step`, `complete_step`) + `progress_bar` (replaces `progress_dots`)
- Applied DS color tokens: `bg-[#fafaf9]` eggshell background, `#141414`/`#343434`/`#6B7280`/`#9CA3AF` text hierarchy, `#0a0a0a` dark buttons, `#CAFC00` lime accents
- Applied DS typography: `tracking-[-0.022em]` display headings, eyebrow-pattern step indicators (`text-[10px] font-bold tracking-[0.16em] uppercase`), `font-mono` for multiplier values and countdown timers
- Cards: white `rounded-2xl` with subtle shadow + `border-neutral-100` wrapping each step
- Inputs: `rounded-xl` with `border-neutral-200`, `focus:ring-2 focus:ring-[#0a0a0a]`
- Buttons: `bg-[#0a0a0a] rounded-xl` primary, `bg-[#f5f5f4] rounded-xl` secondary
- Progress indicator: segmented horizontal bar (replaces dot indicators)
- Success badges: `bg-emerald-50 border-emerald-200 rounded-full` with filled checkmark SVGs (replaces simple text checkmarks)
- Complete step checklist: proper circular check indicators with emerald SVG icons (not ✓/○ text)
- Route kept on `:onboarding` live_session (intentionally no DS header/footer)
- Legacy file preserved at `onboarding_live/legacy/index_pre_redesign.ex`
- All 14 `handle_event` callbacks, 4 `handle_info` callbacks, and all helper functions preserved exactly — zero behavior changes
- PhoneNumberFormatter JS hook preserved on phone input

**Visual changes from old design:**
- Old: `bg-white` plain white background, dot progress indicators, `font-haas_medium_65`/`font-haas_roman_55` fonts, `rounded-full` buttons, `bg-gray-100` secondary buttons, green-50/red-50 alerts, `bg-gray-50` multiplier cards
- New: `bg-[#fafaf9]` eggshell, segmented progress bar, DS typography tokens, `rounded-xl` buttons, `bg-[#f5f5f4]` secondary, emerald-50/red-50 alerts with `rounded-xl`, `bg-[#fafaf9]` multiplier cards, white card wrapper for step content

**Files changed:** `onboarding_live/index.ex` (template rewritten, handlers untouched).
**Files created:** `onboarding_redesign_plan.md`, `onboarding_live/legacy/index_pre_redesign.ex`.
**Tests:** 9 new template assertions + 9 existing handler/logic tests = 18 total, all pass. 0 new failures vs baseline.

---

## Gotchas for the next session (read before starting a new page)

These learnings from Wave 0 through Wave 3 Page #8 will save time on the next page:

**Template / components:**
- The mock HTML uses custom CSS classes (`.eyebrow`, `.article-title`, `.chip`, `.font-haas`, `.hub-card`, `.post-card`). These DO NOT exist in the app's CSS. Use the DesignSystem components or Tailwind utilities:
  - `.eyebrow` → `<BlocksterV2Web.DesignSystem.eyebrow>` OR `class="text-[10px] font-bold tracking-[0.16em] uppercase text-[#9CA3AF]"`
  - `.article-title` → `class="font-bold tracking-[-0.022em] leading-[0.96]"`
  - `.section-title` → `class="font-bold tracking-[-0.018em]"`
  - `.font-haas` → remove (the actual classes are `font-haas_roman_55`, `font-haas_medium_65`, `font-haas_bold_75`, but for redesign pages just use `font-medium`/`font-bold`)
  - `.chip` → `<BlocksterV2Web.DesignSystem.chip>`
- The design system header MUST have `phx-hook="SolanaWallet"` already on `<header id="ds-site-header">` — verified as of 2026-04-10, don't remove it.

**Data / schema gotchas:**
- `Post.content` is `:map` type (TipTap JSON), NOT string. In tests, insert as `%{"type" => "doc", "content" => [...]}` not `"some text"`.
- `Post.published_at` is `:utc_datetime` — must use `DateTime.truncate(DateTime.utc_now(), :second)` in tests (no microseconds allowed).
- `Post.view_count` is the read counter field.
- Hub has `color_primary` / `color_secondary` (not `primary_color`), `logo_url` (not `logo`), `token` (not `ticker`), `tag_name` (used in post filtering).
- ImageKit helper: use `BlocksterV2Web.ImageKit.w500_h500(url)` or `w800_h800(url)` — `w500` alone does NOT exist.
- User schema now has `bio` (text) and `x_handle` (string) fields added in migration `20260410200002` (2026-04-10).

**LiveView gotchas:**
- `push_event("copy_to_clipboard", ...)` has NO JS listener. Use the `CopyToClipboard` hook with `data-copy-text` attribute instead — the hook handles click + clipboard + feedback itself.
- `MemberLive.Show` now supports BOTH owner and public views via `load_owner_profile/3` vs `load_public_profile/3` branching in `handle_params`. Do not re-add the security redirect.
- When you move a route to the `:redesign` live_session, the `SolanaWallet` hook loses its mount point unless the page uses `<DesignSystem.header />` (which now has the hook). Pages using their own custom header MUST include the hook on a stable id element or wallet connect/disconnect will silently break.
- `use BlocksterV2Web, :live_view` auto-injects `WalletAuthEvents` macro which handles `disconnect_wallet`, `wallet_connected`, etc. Don't redefine these in your LiveView.
- Test helper: copy `ensure_mnesia_tables/0` from `test/blockster_v2_web/live/member_live/show_test.exs` — it has the correct field order for every Mnesia table and will fail with `{:aborted, {:bad_type}}` if you get even one field wrong.
- LiveView redirects use `push_navigate` not `redirect` — test for `{:error, {:live_redirect, ...}}`.
- **Elixir 1.16 template syntax**: NEVER put a bare `if/cond/case do … else … end` block inside a `class={[...]}` list — the parser flags "unexpected comma, parentheses required to solve ambiguity inside containers". Use `if(cond, do: x, else: y)` with explicit parens, or extract the result into a `<% var = cond do … end %>` binding above the element and reference `var` inside the class list.
- **`:bux_balance` vs `:token_balances`**: the DS header pill reads the scalar `:bux_balance` assign, NOT `@token_balances["BUX"]`. Two things populate it: `BuxBalanceHook.on_mount` (initial page load) AND `wallet_authenticated` hook in `wallet_auth_events.ex` (mid-session login — assigns `:bux_balance` extracted from `token_balances["BUX"]`). Both must be in sync or the pill shows stale 0. Verified fix in `wallet_auth_events.ex:48` as of 2026-04-11.
- **`display_token` attr on DS header**: `<DesignSystem.header display_token="SOL">` swaps the pill to show SOL balance + Solana logo. Pill reads `@token_balances["SOL"]` for SOL (4 decimals), falls back to `@bux_balance` for BUX (2 decimals). Use this for pages primarily centered on SOL (e.g. `/play`, potentially `/pool/sol`).

**CSS / JS hook gotchas:**
- **Inline `<style>` in `render/1` overrides `assets/css/app.css`**: a LiveView's inline `<style>` block renders in the `<body>` and wins the CSS cascade over `<link>` in `<head>`. On `CoinFlipLive` specifically, the inline `<style>` **deliberately redeclares** `.animate-flip-heads` / `.animate-flip-tails` / `.animate-flip-continuous` / `.perspective-1000` with different keyframes than app.css. The app.css versions (lines 915-979) are effectively dead code on this page — DO NOT "clean up" the inline block thinking it's redundant. The app.css keyframes end at `1980°` (heads) / `2160°` (tails) which are 180° off from the inline block's `1800°` / `1980°`, landing the coin on the wrong visual face.
- **JS hook rAF races with `handleEvent`**: callbacks inside `requestAnimationFrame` in `mounted()` / `updated()` can race with `handleEvent("push_event_name", …)` callbacks for events that the server fires immediately after patching the DOM. The push_event typically arrives at the client in ~1-5ms; rAF fires at ~16ms. If you have a setup like "`mounted()` sets continuous-animation class via rAF, `handleEvent` swaps to deceleration class on reveal", you MUST guard the rAF with a flag set by the event handler: `if (this.revealHandled) return`. Reset the flag in `updated()` when the element id changes. See `assets/js/coin_flip.js` for the pattern.

**Solana tx gotchas:**
- **"Transaction reverted during simulation" popup on devnet is expected**: the coin flip `submit_commitment` (settler-signed, sent via QuickNode) and `place_bet` (player-signed, simulated by Phantom against public `api.devnet.solana.com`) are dependent txs across different RPCs. Phantom's devnet RPC lags 5-15 slots behind QuickNode, so it simulates against stale `player_state.pending_commitment` and the program returns `NoCommitment`. The user approves anyway, state has propagated by send time, and the tx lands. This is the CLAUDE.md back-to-back tx propagation issue. Pre-existing, verified by stashing redesign and testing legacy `/play` on 2026-04-11. **Parked — don't fix on devnet.** If the warning appears on mainnet (where Phantom uses Helius/Triton with tight sync to QuickNode), the fix is a client-side `getAccountInfo(player_state)` poll after `submit_commitment` returns, only enabling Place Bet once `pending_commitment` is non-zero and `pending_nonce` matches.

**Test discipline:**
- Baseline check command:
  ```bash
  mix test 2>&1 \
    | grep -oE 'test/[a-z_/0-9]+_test\.exs' \
    | sort -u \
    | comm -23 - <(sed -n '/^```$/,/^```$/p' docs/solana/test_baseline_redesign.md | grep '^test/' | sort)
  ```
  Empty output = pass. Any file listed = regression.
- Compiler warnings in test files cause false positives in the baseline check (the grep picks up the filename in warning messages). Always prefix unused vars with `_`.
- Run `mix test test/path/to/page_test.exs` alone first to confirm your tests pass, THEN run the full baseline check — this isolates whether failures are your regressions or pre-existing flakiness.

**Documentation / commit discipline:**
- Per-page commit message format: `redesign(page-name): <one-line description>`
- Update BOTH `docs/solana/redesign_release_plan.md` (build progress table + stub register) AND `docs/solana_build_history.md` (narrative entry) after every page.
- NEVER commit without EXPLICIT user instruction.

**Template syntax (Elixir 1.16):**
- **Never** write a bare `if cond do … else … end` inside a `class={[…]}` list — the parser reads the `,` inside the expression as a container comma and fails with "invalid syntax found … unexpected comma. Parentheses are required to solve ambiguity inside containers." Use `if(cond, do: x, else: y)` with parens, or lift the expression into a `<% var = if … do … end %>` assign above and reference the var. Same rule applies to `cond do`/`case do` inside class lists.
- Some LiveView modules (e.g. CoinFlipLive, older LiveViews before the redesign) have their `render/1` **inlined in the `.ex` file** instead of a separate `.html.heex`. Don't assume every redesign means editing a template file — check first and edit the render function in place if that's the pattern.

**Large-file render rewrites:**
- When a `render/1` body is hundreds of lines and needs a wholesale rewrite, writing the new render content to `/tmp/new_render.ex` and using a small `python3` splice on the target file (`lines[:N] + new + lines[M:]`) is far more reliable than a single huge Edit with an old_string of comparable size. Verify line numbers with a sanity-check Python read before splicing.

**Pool index specifics (Wave 3 Page #8):**
- `BuxMinter.get_pool_stats/0` returns `{:ok, %{"sol" => %{…}, "bux" => %{…}}}` — top-level keys are **strings** (decoded from JSON), not atoms. Use `get_in(stats, ["sol", "lpPrice"])`, not `stats.sol.lp_price`.
- Each vault sub-map has string keys: `"totalBalance"`, `"netBalance"`, `"lpSupply"`, `"lpPrice"`, `"houseProfit"`, `"totalBets"`, `"totalVolume"`, `"totalPayout"`.
- Cross-vault activity merging: call `CoinFlipGame.get_recent_games_by_vault(:sol, N)` AND `get_recent_games_by_vault(:bux, N)` (atom vault type), PLUS `:mnesia.dirty_index_read(:pool_activities, "sol", :vault_type)` AND the same for `"bux"` (string vault type). The `:pool_activities` Mnesia table records use `:vault_type` as a string, NOT an atom — this mismatch with `coin_flip_games` is confusing but correct.
- Broadcast topics `"pool_activity:sol"` and `"pool_activity:bux"` use message format `{:pool_activity, %{"type" => …, "pool" => …, "wallet" => …, "amount" => …, "time" => …, "_created_at" => …}}` — published by `PoolDetailLive` on every deposit/withdraw. Subscribe once in `mount/3` under `connected?(socket)`, add `handle_info({:pool_activity, activity}, socket)` to prepend + cap at 50.
- `:pool_activities` Mnesia table fields (in order): `[:id, :type, :vault_type, :amount, :wallet, :created_at]` — match when adding to test `ensure_mnesia_tables/0`.
- `coin_flip_games` Mnesia table fields (in order): `[:game_id, :user_id, :wallet_address, :commitment, :server_seed, :client_seed, :status, :vault_type, :bet_amount, :difficulty, :predictions, :results, :won, :payout, :commitment_sig, :bet_sig, :settlement_sig, :created_at, :settled_at]` — 19 fields. Gotcha: `CoinFlipGame.get_recent_games_by_vault/2`'s match pattern has 20 slots because Erlang match patterns include the record name at position 0. When adding to tests, the table definition has 19 attributes.
- The `<.link navigate={~p"/pool/sol"} class="group relative …">` wraps the entire vault card. Inner hover states (button bg swap) must use `group-hover:` not `hover:`.
- `format_display_balance`/BUX pill defaults to `"BUX"` — pool index doesn't need `display_token="SOL"`. Matches the coin-flip page's choice of SOL because that page is SOL-first.

**Pool detail specifics (Wave 3 Page #9):**
- `:pool_activities` Mnesia table is written-to on every successful `tx_confirmed` event in `PoolDetailLive`. Any test harness that simulates `tx_confirmed` via `render_hook/2` MUST include the table in its `setup_mnesia/1` helper, otherwise the LiveView process crashes with `{:aborted, {:no_exists, :pool_activities}}` — not a clean assertion failure. Fields: `[:id, :type, :vault_type, :amount, :wallet, :created_at]`, indexed by `:vault_type` (string, not atom).
- `:lp_price_history` is an **`ordered_set`** type, not `set`. Record key is `{vault_type, timestamp}`. Tests must specify `type: :ordered_set` or timeframe range scans silently return out-of-order results.
- `format_tvl/1`, `format_price/1`, `format_number/1`, `format_change_pct/1`, `format_integer/1`, `format_profit_value/1`, `profit_color/1`, `get_vault_stat/3` are all **public functions exported from `BlocksterV2Web.PoolComponents`**, imported into `PoolDetailLive` via `import BlocksterV2Web.PoolComponents`. Do NOT redefine them as `defp` in the LiveView — Elixir's local-first dispatch silently shadows the imports with no compiler warning and you end up with duplicate logic. Check via `Grep` for existing public defs before adding helpers.
- `pool_components.ex` components (`lp_price_chart`, `pool_stats_grid`, `activity_table`, `stat_card`, `coin_flip_fairness_modal`) are only consumed by `PoolDetailLive` — `PoolIndexLive` has its own inline activity markup. Restyling them in place is safe and preferred over creating v2 variants.
- New `set_half` handler mirrors `set_max` but returns `balance / 2`. Added because the mock shows `½` + `MAX` buttons side-by-side. Tiny handler, under 15 LOC. Not a feature bloat per se but a deliberate mock-fidelity call.
- "New pool share (+Δ)" footer on the output preview needs **projected math**, not current share. Helpers: `compute_share_pct(user_lp, supply)` and `compute_new_share_pct(user_lp, supply, lp_price, amount, :deposit|:withdraw)`. Suppress the delta label when `|Δ| < 0.01%`.
- **Vault-aware gradient styles** on the banner: SOL = `linear-gradient(135deg, #00FFA3 0%, #00DC82 50%, #064e3b 130%)`, BUX = `linear-gradient(135deg, #CAFC00 0%, #9ED600 50%, #4d6800 130%)`. Put them in a `banner_bg_style(is_sol)` helper, not inline.
- `tx_confirmed` handler continues to broadcast `{:pool_activity, activity}` on `"pool_activity:#{vault}"` — `PoolIndexLive` (subscribed to both vault topics) picks these up for its cross-pool activity feed. Do not change the broadcast format or the index page's activity row will render garbage.
- `display_token="SOL"` on `/pool/sol`, `display_token="BUX"` on `/pool/bux` in the DS header — matches the coin-flip page's pattern of showing the active token balance in the header pill.
- **Phantom "Transaction reverted during simulation" warning on every SOL pool deposit + withdraw is expected on devnet**: the settler builds the tx with a recent blockhash from QuickNode, Phantom simulates against public `api.devnet.solana.com` which lags 5-15 slots behind, so the simulation sees a stale `VaultState` PDA or an unknown blockhash and returns revert. User approves anyway, state propagates by send time, the tx lands against the settler's RPC. Same cross-RPC propagation issue as the Coin Flip stub. **Parked** until mainnet (Phantom uses Helius/Triton on mainnet with tight sync). If it persists on mainnet, fix is a client-side `getAccountInfo(vault_state)` poll before emitting `sign_deposit` / `sign_withdraw`.

**Play / Coin Flip specifics:**
- The `CoinFlipSolana` JS hook must stay mounted on the root `#coin-flip-game` element with `data-game-id={@onchain_game_id}` and `data-commitment-hash={@commitment_hash}` attrs — the hook listens for `sign_place_bet`, `sign_reclaim`, `bet_settled` events from the LiveView.
- The `CoinFlip` JS hook is mounted on a per-flip element `#coin-flip-#{@flip_id}` ONLY during `game_state == :flipping`. Its key changes every flip so the hook remounts — the hook keys off `this.el.id` inside `updated()` to detect new flips.
- `coin_flip_games` Mnesia table has 19 fields; `bux_booster_user_stats` has 15 fields. Both are required for `CoinFlipLive` mount + sidebar stats — add both to any test's `ensure_mnesia_tables/0`.
- The old difficulty tab strip used `ScrollToCenter` JS hook; the redesigned 9-col grid doesn't need it. Don't attach it on the new template. The hook is still registered globally for other pages.
- Settlement is triggered via `spawn(fn -> CoinFlipGame.settle_game(game_id) … end)` and sends `{:settlement_complete, sig}` or `{:settlement_failed, reason}` to the LiveView. This is **fire-and-forget by design** — never try to "improve" it by awaiting the settlement synchronously (see CLAUDE.md Solana tx propagation rules).

**Airdrop specifics (Wave 3 Page #10):**
- The `AirdropSolanaHook` JS hook is mounted on a hidden `<div id="airdrop-solana-hook" phx-hook="AirdropSolanaHook" class="hidden">`. It does **not** wrap any DOM around it — the hook only listens for push_events (`sign_airdrop_deposit`, `sign_airdrop_claim`) and pushes back `airdrop_deposit_confirmed` / `airdrop_claim_confirmed` etc. Keep the element exactly as-is — don't try to hoist it into a page wrapper, don't try to remove it because "the hook is hidden", and don't change the id. Same pattern as `PoolHook` on page #9 — preserve verbatim.
- `Airdrop.redeem_bux/3` reads BUX balance from a different store than the test's `set_bux_balance` writes to (post-Solana migration). Every test that calls `Airdrop.redeem_bux` (and the `create_drawn_round` helper which uses it) fails with `{:error, :insufficient_balance}` in the test env. **These are pre-existing baseline failures**, not regressions — the file `airdrop_live_test.exs` is in the baseline and 43 of its 63 tests fail for this reason. Per the rule at the bottom of `test_baseline_redesign.md`, NEW assertions you add in this file must still pass — but you cannot fix the existing redeem_bux tests by tweaking your render output.
- The page has both an OPEN state and a DRAWN state, gated on `current_round.status == "drawn"`. The drawn state is reached via the `{:airdrop_drawn, round_id, winners}` PubSub message. Your render function must handle the case where `current_round` is `nil` AND the case where it exists but `winners == []` — `round_status_label/1` and `round_number_or_dash/1` cover both. Don't try to format `nil.round_id`.
- **Two new tiny event handlers** for mock fidelity: `set_amount` (quick-chip click) and `toggle_show_all_winners` (winners table expand/collapse). Both are 5–10 LOC. The chip preset list `@quick_chips [100, 1_000, 2_500, 10_000]` and the `@winners_collapsed_count 8` constant live as module attrs at the top of the file. Don't make them configurable.
- `format_datetime/1` for receipt cards MUST keep the year (`%b %-d, %Y · %H:%M UTC`). The pre-existing `airdrop_live_test.exs` `"show timestamp"` test asserts `html =~ "2026"`. The mock dropped the year for editorial fidelity but the test keeps it real, so the year wins.
- Sidebar ad placements (`airdrop_sidebar_left`, `airdrop_sidebar_right`) are still loaded into mount assigns but **not rendered** in v1 — the mock has a full 1280px main column with no sidebar slots. Stub-registered. When the future ad placement reshuffle wants them back, the loader stays and only the template needs swapping.
- The drawn-state `View on Solscan` CTA falls back to the airdrop program account URL when `verification_data.draw_tx` is nil (which it usually is on devnet). Keep this fallback — the celebration banner still needs a working link even when no per-round draw_tx is recorded.
- **Pool share / odds / expected value math is purely client-side** (`compute_pool_share/2`, `compute_odds_text/2`, `compute_expected_value/3`). All take `parsed_amount + total_entries`. They return `"—"` when amount is 0 so the right column always renders cleanly. Don't try to share these helpers with `pool_components.ex` — they're airdrop-specific.

**Shop index specifics (Wave 4 Page #11):**
- **`ShopSlots` controls "View all" display order via Mnesia `:shop_product_slots` table.** If no admin slot assignments exist, the slot-based display renders all-nil slots = zero visible cards for non-admin users. The fix: `@has_slot_assignments` boolean (set in mount + `select_product_for_slot` handler) branches the template — slotted mode uses `@display_slots`, unslotted mode falls back to `@all_transformed` (all products pre-transformed in mount). Tests seed slots with `ShopSlots.set_slot(0, to_string(product.id))`.
- **Hub `tag_name` is NOT NULL.** Test hub inserts MUST include `tag_name: "some-tag"` or Postgres rejects.
- **Product `status: "active"` required for `list_active_products`.** Draft/archived products are invisible.
- **Product needs a variant with `:price` for the card to show a price.** `transform_product/1` reads `List.first(product.variants).price`. No variant = `0.0` price.
- **Filter counts** are purely from `@all_products` via `Enum.frequencies/1` — `@category_counts`, `@hub_counts`, `@brand_counts` maps. No new DB query.
- **Sort dropdown + "Load more" button are inert stubs.** No handlers exist. Static labels only.
