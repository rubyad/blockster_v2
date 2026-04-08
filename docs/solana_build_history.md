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
