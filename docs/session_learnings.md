# Session Learnings Archive

Historical bug fixes, feature implementations, and debugging notes moved from CLAUDE.md to reduce system prompt size. These are preserved for reference but rarely needed in day-to-day development.

For active reference material, see the main [CLAUDE.md](../CLAUDE.md).

---

## Table of Contents
- [Number Formatting in Templates](#number-formatting-in-templates)
- [Product Variants](#product-variants)
- [X Share Success State](#x-share-success-state)
- [Tailwind Typography Plugin](#tailwind-typography-plugin)
- [Libcluster Configuration](#libcluster-configuration-dev-only)
- [Upgradeable Smart Contract Storage Layout](#upgradeable-smart-contract-storage-layout---critical)
- [Account Abstraction Performance Optimizations](#account-abstraction-performance-optimizations-dec-2024)
- [BUX Booster Smart Contract Upgrades (V3-V7)](#bux-booster-smart-contract-upgrades-dec-2024)
- [BUX Booster Balance Update After Settlement](#bux-booster-balance-update-after-settlement-dec-2024)
- [Multi-Flip Coin Reveal Bug](#multi-flip-coin-reveal-bug-dec-2024)
- [House Balance & Max Bet Display](#house-balance--max-bet-display-dec-2025)
- [Infinite Scroll for Scrollable Divs](#infinite-scroll-for-scrollable-divs-dec-2024)
- [Mnesia Pagination Pattern](#mnesia-pagination-pattern-dec-2024)
- [Recent Games Table Implementation](#recent-games-table-implementation-dec-2024)
- [Unauthenticated User Access to BUX Booster](#unauthenticated-user-access-to-bux-booster-dec-2024)
- [Recent Games Table Live Update on Settlement](#recent-games-table-live-update-on-settlement-dec-2024)
- [Aggregate Balance ROGUE Exclusion Fix](#aggregate-balance-rogue-exclusion-fix-dec-2024)
- [Provably Fair Verification Fix](#provably-fair-verification-fix-dec-30-2024)
- [Contract V4 Upgrade](#contract-v4-upgrade---removed-server-seed-verification-dec-30-2024)
- [ROGUE Betting Integration Bug Fixes](#rogue-betting-integration---bug-fixes-and-improvements-dec-30-2024)
- [BetSettler Bug Fix & Stale Bet Cleanup](#betsettler-bug-fix--stale-bet-cleanup-dec-30-2024)
- [BetSettler Premature Settlement Bug](#betsettler-premature-settlement-bug-dec-31-2024)
- [Token Price Tracker](#token-price-tracker-dec-31-2024)
- [Contract Error Handling](#contract-error-handling-dec-31-2024)
- [GlobalSingleton for Safe Rolling Deploys](#globalsingleton-for-safe-rolling-deploys-jan-2-2026)
- [NFT Revenue Sharing System](#nft-revenue-sharing-system-jan-5-2026)
- [BuxBooster Performance Fixes](#buxbooster-performance-fixes-jan-29-2026)
- [BuxBooster Stats Module](#buxbosterstats-module-feb-3-2026)
- [BuxBooster Player Index](#buxbooster-player-index-feb-3-2026)
- [BuxBooster Stats Cache](#buxbooster-stats-cache-feb-3-2026)
- [BuxBooster Admin Stats Dashboard](#buxbooster-admin-stats-dashboard-feb-3-2026)

---

## Number Formatting in Templates
Use `:erlang.float_to_binary/2` to avoid scientific notation in number inputs:
```elixir
value={:erlang.float_to_binary(@tokens_to_redeem / 1, decimals: 2)}
```

## Product Variants
- Sizes come from `option1` field on variants, colors from `option2`
- No fallback defaults - if a product has no variants, sizes/colors lists are empty

## X Share Success State
After a successful retweet, check `@share_reward` to show success UI in `post_live/show.html.heex`.

## Tailwind Typography Plugin
- Required for `prose` class to style HTML content
- Installed via npm: `@tailwindcss/typography`
- Enabled in app.css: `@plugin "@tailwindcss/typography";`

## Libcluster Configuration (Dev Only)
Added December 2024. Uses Epmd strategy for dev-only automatic cluster discovery. Configured in `config/dev.exs`. Production uses DNSCluster unchanged.

## Upgradeable Smart Contract Storage Layout - CRITICAL

When upgrading UUPS or Transparent proxy contracts:
1. **NEVER change the order of state variables**
2. **NEVER remove state variables**
3. **ONLY add new variables at the END**
4. **Inline array initialization doesn't work with proxies** - Use `reinitializer(N)` functions

**Stack Too Deep Errors**: NEVER enable `viaIR: true`. Instead use helper functions, cache struct fields, split events.

## Account Abstraction Performance Optimizations (Dec 2024)

- Batch transactions don't work (state changes don't propagate between calls)
- Infinite Approval + Caching: ~3.5s savings on repeat bets
- Sequential Transactions with Receipt Waiting: current approach
- Optimistic UI Updates: deduct balance immediately, sync after settlement
- NEVER use `Process.sleep()` after async operations
- Use PubSub broadcasts for cross-LiveView updates

See [docs/AA_PERFORMANCE_OPTIMIZATIONS.md](AA_PERFORMANCE_OPTIMIZATIONS.md).

## BUX Booster Smart Contract Upgrades (Dec 2024)

**Proxy Address**: `0x97b6d6A8f2c6AF6e6fb40f8d36d60DF2fFE4f17B` (UUPS)

**Upgrade Process**:
```bash
cd contracts/bux-booster-game
npx hardhat compile
npx hardhat run scripts/force-import.js --network rogueMainnet
npx hardhat run scripts/upgrade-manual.js --network rogueMainnet
npx hardhat run scripts/init-vN.js --network rogueMainnet
npx hardhat run scripts/verify-upgrade.js --network rogueMainnet
```

**V3**: Server calculates results, sends to contract. CommitmentHash as betId.
**V4**: Removed on-chain server seed verification for player transparency.
**V5**: Added ROGUE native token betting via ROGUEBankroll.
**V6**: Added referral reward system (1% of losing BUX bets).
**V7**: Separated BUX-only stats tracking (buxPlayerStats, buxAccounting).

See [docs/contract_upgrades.md](contract_upgrades.md) for full details.

## BUX Booster Balance Update After Settlement (Dec 2024)

When using `attach_hook` with `{:halt, ...}`, the hook intercepts the message and prevents it from reaching the LiveView's `handle_info`. Update all needed assigns in the hook handler.

## Multi-Flip Coin Reveal Bug (Dec 2024)

Must schedule `Process.send_after(self(), :reveal_flip_result, 3000)` in `:next_flip` handler, not just on initial bet confirmation.

## House Balance & Max Bet Display (Dec 2025)

Max Bet Formula: `base_max_bet = house_balance * 0.001`, scaled by `20000 / multiplier_bp`. All fetches async via `start_async`. See [docs/bux_minter.md](bux_minter.md).

## Infinite Scroll for Scrollable Divs (Dec 2024)

IntersectionObserver `root` option: `null` = window scroll, `this.el` = element scroll. Must attach/cleanup scroll listener to correct target.

## Mnesia Pagination Pattern (Dec 2024)

Use `Enum.drop(offset) |> Enum.take(limit)` for Mnesia pagination. Track offset in socket assigns.

## Recent Games Table Implementation (Dec 2024)

Nonce as bet ID, transaction links with `?tab=logs`, sticky header with `sticky top-0 bg-white z-10`. Ensure `phx-hook="InfiniteScroll"` is on the scrollable div itself.

## Unauthenticated User Access to BUX Booster (Dec 2024)

Non-logged-in users can interact with full UI. Guard all `current_user.id` access with nil check. "Place Bet" redirects to `/login`. See [docs/bux_booster_onchain.md](bux_booster_onchain.md).

## Recent Games Table Live Update on Settlement (Dec 2024)

Added `load_recent_games()` to `:settlement_complete` handler so settled bets appear immediately.

## Aggregate Balance ROGUE Exclusion Fix (Dec 2024)

When calculating aggregate balance, exclude both `"aggregate"` and `"ROGUE"` keys. ROGUE is native gas token, not part of BUX economy.

## Provably Fair Verification Fix (Dec 30, 2024)

Fixed three issues: template deriving results from byte values (not stored results), client seed using user_id (not wallet_address), commitment hash using hex string (not binary). Old games before fix cannot be externally verified.

## Contract V4 Upgrade - Removed Server Seed Verification (Dec 30, 2024)

Removed `sha256(abi.encodePacked(serverSeed)) != bet.commitmentHash` check. Server is trusted source (V3 model). Allows player verification with standard SHA256 tools. See [docs/v4_upgrade_summary.md](v4_upgrade_summary.md).

## ROGUE Betting Integration - Bug Fixes and Improvements (Dec 30, 2024)

1. **ROGUE Balance Not Updating**: Added broadcast after `update_user_rogue_balance()`
2. **Out of Gas**: Set explicit `gas: 500000n` for ROGUE bets (ROGUEBankroll external call)
3. **ROGUE Payouts Not Sent**: BUX Minter now detects `token == address(0)` and calls `settleBetROGUE()`
4. **ABI Mismatch**: Solidity auto-generated getters exclude dynamic arrays (`uint8[] predictions`)
5. **ROGUEBankroll V6**: Added accounting system
6. **ROGUEBankroll V9**: Added per-difficulty stats (`getBuxBoosterPlayerStats`)
7. **BuxBoosterBetSettler**: Auto-settles stuck bets every minute

See [docs/ROGUE_BETTING_INTEGRATION_PLAN.md](ROGUE_BETTING_INTEGRATION_PLAN.md).

## BetSettler Bug Fix & Stale Bet Cleanup (Dec 30, 2024)

Fixed BetSettler calling wrong function. Cleaned up 9 stale orphaned bets.

**bux_booster_onchain_games Table Schema** (22 fields):
| Index | Field | Description |
|-------|-------|-------------|
| 0 | table name | :bux_booster_onchain_games |
| 1 | game_id | UUID |
| 2 | user_id | Integer |
| 3 | wallet_address | Hex string |
| 4 | server_seed | 64-char hex |
| 5 | commitment_hash | 0x-prefixed |
| 6 | nonce | Integer |
| 7 | status | :pending/:committed/:placed/:settled/:expired |
| 8-16 | bet details | bet_id, token, amount, difficulty, predictions, bytes, results, won, payout |
| 17-19 | tx hashes | commitment_tx, bet_tx, settlement_tx |
| 20-21 | timestamps | created_at, settled_at (Unix ms) |

Match pattern tuple size MUST exactly match table arity (22 elements).

## BetSettler Premature Settlement Bug (Dec 31, 2024)

Reused game sessions kept original `created_at`, making BetSettler think bet was "stuck". Fix: update `created_at` to NOW in `on_bet_placed()`.

## Token Price Tracker (Dec 31, 2024)

PriceTracker GenServer polls CoinGecko every 10 min for 41 tokens. Stores in Mnesia `token_prices` table. Broadcasts via PubSub topic `token_prices`. See [docs/ROGUE_PRICE_DISPLAY_PLAN.md](ROGUE_PRICE_DISPLAY_PLAN.md).

## Contract Error Handling (Dec 31, 2024)

Error signatures mapped in `assets/js/bux_booster_onchain.js` (`CONTRACT_ERROR_MESSAGES`). Key errors: `0xf2c2fd8b` BetAmountTooLow, `0x54f3089e` BetAmountTooHigh, `0x05d09e5f` BetAlreadySettled, `0x469bfa91` BetNotFound.

## GlobalSingleton for Safe Rolling Deploys (Jan 2, 2026)

Custom conflict resolver keeps existing process, rejects new one. Uses distributed `Process.alive?` via RPC. Applied to MnesiaInitializer, PriceTracker, BuxBoosterBetSettler, TimeTracker. See [docs/mnesia_setup.md](mnesia_setup.md).

## NFT Revenue Sharing System (Jan 5, 2026)

NFTRewarder at `0x96aB9560f1407586faE2b69Dc7f38a59BEACC594` (Rogue Chain). 0.2% of losing ROGUE bets distributed to 2,341 NFT holders weighted by multiplier (30x-100x). Backend services in high-rollers-nfts. See [high-rollers-nfts/docs/nft_revenues.md](../high-rollers-nfts/docs/nft_revenues.md).

## BuxBooster Performance Fixes (Jan 29, 2026)

1. Added HTTP timeouts to `:httpc.request()` calls
2. Made `load_recent_games()` async in mount
3. Fixed socket copying in `start_async` (extract assigns before async)

Result: page load 30s → <2s.

## BuxBoosterStats Module (Feb 3, 2026)

Backend module at `lib/blockster_v2/bux_booster_stats.ex`. Direct JSON-RPC calls to BuxBoosterGame and ROGUEBankroll contracts. See [docs/bux_booster_stats.md](bux_booster_stats.md).

## BuxBooster Player Index (Feb 3, 2026)

Indexes players by scanning BetPlaced/BuxBoosterBetPlaced events. Mnesia table `:bux_booster_players`. Incremental updates every 5 min. See [docs/bux_booster_stats.md](bux_booster_stats.md).

## BuxBooster Stats Cache (Feb 3, 2026)

ETS cache at `:bux_booster_stats_cache`. TTLs: global 5min, house 5min, player 1min.

## BuxBooster Admin Stats Dashboard (Feb 3, 2026)

Routes: `/admin/stats`, `/admin/stats/players`, `/admin/stats/players/:address`. Protected by AdminAuth. See [docs/bux_booster_stats.md](bux_booster_stats.md).
