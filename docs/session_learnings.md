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
- [BUXBankroll Deployment (Phase B2)](#buxbankroll-deployment-phase-b2-feb-18-2026)
- [Phase B4: Backend Implementation](#phase-b4-backend-implementation-feb-18-2026)
- [Phase B5: BankrollLive UI](#phase-b5-bankrolllive-ui-feb-18-2026)
- [Phase P5: Plinko Mnesia + Backend](#phase-p5-plinko-mnesia--backend-feb-19-2026)

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

## Mnesia Stale Node Fix - CRITICAL (Feb 16, 2026)

### The Problem
After the content automation deploy (v292/v293), Mnesia on node 865d lost all table replicas. Every table showed `storage=unknown, local=false`. The `token_prices` table was crashing with `{:aborted, {:no_exists, ...}}`.

### Root Cause
On Fly.io, each deploy creates machines with new internal IPs, which means new Erlang node names. When a node is replaced, the OLD node name stays in the Mnesia schema's `disc_copies` list as a stale reference. When a new node tries to `add_table_copy(table, node(), :disc_copies)`, Mnesia runs a schema merge across ALL nodes in `db_nodes` — including the dead one. The dead node "has no disc" so the merge fails with `{:combine_error, table, "has no disc", dead_node}`. This also prevents `change_table_copy_type(:schema, node(), :disc_copies)`, leaving the schema as `ram_copies` — which then causes ALL subsequent `add_table_copy` calls to fail.

### Diagnosis
```
# On broken node:
:mnesia.table_info(:schema, :storage_type)  # => :ram_copies (should be :disc_copies)
:mnesia.system_info(:db_nodes)              # => includes dead node name
:mnesia.system_info(:running_db_nodes)      # => does NOT include dead node
:mnesia.table_info(:token_prices, :storage_type)  # => :unknown
```

### Manual Fix Applied
1. Backed up all Mnesia data: `:mnesia.dump_to_textfile('/data/mnesia_backup_20260216.txt')` on healthy node (17817). Also downloaded to local machine at `mnesia_backup_20260216.txt`.
2. Removed stale node from schema on healthy node: `:mnesia.del_table_copy(:schema, stale_node)` — this only removes the reference, does NOT touch data.
3. Deleted corrupted Mnesia directory on broken node (865d) — it had zero usable data anyway (all tables `storage=unknown`).
4. Restarted broken node — it joined the cluster fresh, got `disc_copies` for all 29 tables.
5. Verified: 38,787 records, exact match on both nodes.

### Code Fix (mnesia_initializer.ex)
Added `cleanup_stale_nodes/0` function that runs BEFORE `ensure_schema_disc_copies/0` in all three cluster join paths (`safe_join_preserving_local_data`, `join_cluster_fresh`, `use_local_data_and_retry_cluster`).

```elixir
defp cleanup_stale_nodes do
  db_nodes = :mnesia.system_info(:db_nodes)
  running = :mnesia.system_info(:running_db_nodes)
  stale = db_nodes -- running
  # For each stale node: :mnesia.del_table_copy(:schema, stale_node)
end
```

**Why it's safe:** Only removes nodes in `db_nodes` but NOT in `running_db_nodes`. A live node is always in `running_db_nodes`. On Fly.io, old node names (with old IPs) will never come back.

### Recovery (if code fix causes issues)
1. Restore backup: `:mnesia.load_textfile('/data/mnesia_backup_20260216.txt')` on any node
2. Local backup at: `mnesia_backup_20260216.txt` in project root
3. Or revert the code change — the `cleanup_stale_nodes` and `ensure_schema_disc_copies` functions are additive; removing them restores old behavior

### Key Lesson
The MnesiaInitializer already handled node name changes for the PRIMARY node path (`migrate_from_old_node`), but NOT for the JOINING node path. The gap existed since the MnesiaInitializer was written but only triggered when a deploy happened to create the right conditions (stale node + joining node path).

---

## BUXBankroll Deployment (Phase B2) — Feb 18, 2026

### Context
BUXBankroll is the ERC-20 LP token bankroll that holds all BUX house funds for Plinko (and future BUX games). Users deposit BUX to receive LP-BUX tokens and share in house profit/loss. Part of the broader BUX Bankroll + Plinko build.

### Build Order
**B1 (Contract — DONE)** → **B2 (Deploy — DONE)** → **B3 (BUX Minter — DONE)** → **B4 (Backend — DONE)** → **B5 (BankrollLive UI — DONE)** → P1 (ROGUEBankroll V10) → P2 (PlinkoGame.sol) → P3-P7 (Deploy → Minter → Backend → UI → Integration)

### Deployed Contracts
| Contract | Address | Tx Hash |
|----------|---------|---------|
| BUXBankroll Implementation | `0xb66db6C2815A4DF6Fe3915bd8323B2e7D54A5830` | `0xb6c4fd6c5abde7182b5e2f6980d404cff4afe8ee4b69cdfb4693d72e6ba5d078` |
| BUXBankroll Proxy (ERC1967) | `0xED7B00Ab2aDE39AC06d4518d16B465C514ba8630` | `0x10ba32cb37f95c3bf76060a0d7fcbd922bfd87a29b26fd957cd7df0acc24741d` |

**Deployer/Owner**: `0x4BDC5602f2A3E04c6e3a9321A7AC5000e0A623e0`

### Post-Deploy Configuration
| Setting | Value | Tx Hash |
|---------|-------|---------|
| referralAdmin | `0xbD6feD8fEeec6f405657d0cA4A004f89F81B04ad` (same as BuxBoosterGame) | `0x9c2d01b83a271214b6fea1c7534b5279ec4f1fe3d1a409da4b1c1f67597d36fd` |
| referralBasisPoints | 20 (0.2%) | Set during initialize() |
| maximumBetSizeDivisor | 1000 (0.1%) | Set during initialize() |
| Initial LP price | 1e18 (1:1) | Set during initialize() |
| plinkoGame | Not yet set — Phase P3 | — |
| House deposit | Not yet done — TBD amount | — |

### Verification Results
19/19 assertions passed: owner, buxToken, name ("BUX Bankroll"), symbol ("LP-BUX"), decimals (18), totalSupply (0), lpPrice (1e18), houseBalance all zeros, maximumBetSizeDivisor (1000), referralBasisPoints (20), referralAdmin set, plinkoGame (zero), paused (false).

### Scripts Created
| Script | Purpose |
|--------|---------|
| `scripts/deploy-bux-bankroll.js` | Direct ethers.js deployment (impl + ERC1967Proxy) |
| `scripts/verify-bux-bankroll.js` | 19-assertion state verification |
| `scripts/setup-bux-bankroll.js` | Set referral admin, basis points, optional house deposit |

### Deployment Lessons

**Rogue Chain RPC 500 errors**: The Hardhat HTTP provider consistently fails with 500s on `eth_sendRawTransaction` for large contract deployments. Simple reads (`eth_blockNumber`, `eth_getTransactionCount`) work fine. Root cause: nginx proxy on the RPC node.

**Solution**: Use direct ethers.js deployment (bypass Hardhat's provider). Pattern from `deploy-direct.js`:
- `new ethers.JsonRpcProvider(RPC_URL, CHAIN_ID)` instead of Hardhat's provider
- `new ethers.Wallet(privateKey, provider)` for signing
- `new ethers.ContractFactory(abi, bytecode, wallet)` for deployment
- Explicit `gasLimit` to skip `eth_estimateGas`
- `retryWithBackoff()` for transient RPC failures
- ERC1967Proxy artifact from `@openzeppelin/upgrades-core/artifacts/`

**If nginx is restarted on Rogue Chain**, the Hardhat-based approach (`upgrades.deployProxy`) may work. But the direct approach is more reliable.

### Referral Admin Architecture Decision
- BUXBankroll uses the same referral admin address as BuxBoosterGame (`0xbD6f...`)
- In the new architecture, referrals are managed at the bankroll level (BUXBankroll stores `playerReferrers` mapping), not in individual game contracts
- The BUX Minter already has separate `txQueues.referralBB` queue for this wallet
- In Phase B3, the minter's `/set-player-referrer` endpoint will be updated to also call BUXBankroll.setPlayerReferrer using the existing BB queue — no new wallet needed

### Files on Branch `feat/bux-bankroll`
```
# Phase B1: Contract
contracts/bux-booster-game/contracts/BUXBankroll.sol    # Flattened UUPS contract (1335 lines)
contracts/bux-booster-game/contracts/IBUXBankroll.sol    # Interface
contracts/bux-booster-game/test/BUXBankroll.test.js      # 87 passing tests
contracts/bux-booster-game/scripts/deploy-bux-bankroll.js
contracts/bux-booster-game/scripts/verify-bux-bankroll.js
contracts/bux-booster-game/scripts/setup-bux-bankroll.js

# Phase B3: BUX Minter
bux-minter/index.js                                      # Added bankroll endpoints + referral update

# Phase B4: Backend
lib/blockster_v2/bux_minter.ex                           # +5 bankroll API functions
lib/blockster_v2/lp_bux_price_tracker.ex                 # NEW: GlobalSingleton GenServer (OHLC candles)
lib/blockster_v2/mnesia_initializer.ex                   # +:lp_bux_candles table
lib/blockster_v2/application.ex                          # +LPBuxPriceTracker child
lib/blockster_v2_web/router.ex                           # +/bankroll route
test/blockster_v2/lp_bux_price_tracker_test.exs          # NEW: 15 tests (NOT YET RUN — needs PostgreSQL)

# Docs
CLAUDE.md                                                # Updated contract addresses table
docs/bux_bankroll_plan.md                                # Updated progress
docs/session_learnings.md                                # This file
```

---

## Phase B4: Backend Implementation (Feb 18, 2026)

### BuxMinter Pattern for Bankroll Functions
The 5 new BuxMinter functions follow the exact same pattern as existing functions (`get_house_balance`, `get_rogue_house_balance`):
- Check `api_secret` is configured, return `{:error, :not_configured}` if not
- Build headers with `Authorization: Bearer` only (no Content-Type needed for GET)
- Use `http_get/2` (which handles Req vs httpc fallback, retries, timeouts)
- Return `{:ok, data}` or `{:error, reason}` tuples
- For endpoints returning a single value (lp_price, lp_balance): extract the specific key from JSON
- For endpoints returning multiple fields (house_info, player_stats, accounting): return the full decoded map

### LPBuxPriceTracker GlobalSingleton Pattern
Follows PriceTracker exactly:
1. `start_link` → `GlobalSingleton.start_link(__MODULE__, [])` → on success, `send(pid, :registered)`; on `{:already_registered, _}` → `:ignore`
2. `init` → minimal state, `registered: false`
3. `handle_info(:registered, ...)` → sets `registered: true`, starts `:wait_for_mnesia` loop
4. `handle_info(:wait_for_mnesia, ...)` → checks `table_ready?/1`, retries up to 30 times (60s), checks global ownership on each attempt
5. `handle_info(:poll_price, ...)` → checks global ownership, fetches price, updates candle, broadcasts, schedules next
6. `handle_cast(:poll_price, ...)` → same but for manual `refresh_price/0` calls

### Candle Aggregation Logic
- Base interval: 300 seconds (5 minutes)
- `update_candle/2`: Groups by candle boundary (`div(now, 300) * 300`). If same boundary, updates high/low/close. If new boundary, saves previous to Mnesia and starts new candle.
- `get_candles/2`: Reads base candles from Mnesia via `dirty_select` with timestamp cutoff, then `aggregate_candles/2` groups by target timeframe (`div(ts, target) * target`), picks first open and last close within each group.
- `get_stats/0`: Returns `%{price_1h, price_24h, price_7d, price_30d, price_all}` each with `%{high, low}` or `%{high: nil, low: nil}`.

### Mnesia Table: :lp_bux_candles
- Type: `:ordered_set` (timestamps are naturally ordered)
- Attributes: `[:timestamp, :open, :high, :low, :close]`
- No indexes needed (primary key timestamp queries via `dirty_select` with guard conditions)
- Tuple format: `{:lp_bux_candles, timestamp, open, high, low, close}`

### Tests
B4 tests run and passing: 13/13 (`mix test test/blockster_v2/lp_bux_price_tracker_test.exs`).
PostgreSQL must be running locally (test_helper.exs starts Ecto sandbox even for Mnesia-only tests).

The code lives on branch `feat/bux-bankroll` in worktree `../blockster-v2-bankroll` — it does NOT exist in the main app until merged.

---

## Phase B5: BankrollLive UI (Feb 18, 2026)

### Files Created
- `lib/blockster_v2_web/live/bankroll_live.ex` — 813-line LiveView module with inline HEEx template
- `assets/js/lp_bux_chart.js` — LPBuxChart hook (91 lines, TradingView lightweight-charts)
- `assets/js/bankroll_onchain.js` — BankrollOnchain hook (121 lines, Thirdweb deposit/withdraw)
- `test/blockster_v2_web/live/bankroll_live_test.exs` — 24 tests, all passing
- `assets/js/app.js` — Modified: imported and registered both new hooks

### npm Package Added
`lightweight-charts` — TradingView's open-source charting library for candlestick charts.

### Key Patterns

**Async pool data loading**: Pool stats load via `start_async(:fetch_pool_info, ...)`. Initial render shows a loading spinner. After async completes (success or error), `pool_loading: false` reveals the stats grid. In tests, a 300ms sleep + re-render is needed to assert on loaded stats.

**Disabled button testing**: Deposit/withdraw buttons use HTML `disabled` attribute when amount is 0/"". Phoenix LiveViewTest refuses to click disabled elements. Solution: use `render_hook(view, "deposit_bux", %{})` to send the event directly, bypassing the DOM disabled check while still testing server-side validation logic.

**PriceTracker crash in tests**: `PriceTracker.get_price("ROGUE")` uses `dirty_index_read` on `:token_prices` Mnesia table. In test env, this table may not exist, causing `{:no_exists, {:token_prices, :attributes}}`. Fix: wrap in `rescue/catch` in `get_rogue_price/0`.

**LP price preview formulas**:
- Deposit: `lp_out = amount * lp_supply / effective_balance` where `effective = totalBalance - unsettledBets`
- Withdraw: `bux_out = lp_amount * net_balance / lp_supply` where `net = totalBalance - liability`
- First deposit (lp_supply == 0): 1:1 ratio

### Tests Summary (24 total)
| Group | Count | Description |
|-------|-------|-------------|
| Mount (unauth) | 4 | Title, loading→stats, login prompt, How It Works |
| Mount (auth) | 3 | Tabs, deposit form, BUX balance |
| Timeframe | 2 | Tab click, all buttons rendered |
| Deposit flow | 5 | LP preview, zero validation, confirmed, failed, max |
| Withdraw flow | 4 | Tab switch, zero validation, confirmed, failed |
| PubSub | 1 | Price update broadcast |
| Chart | 2 | Hook present, phx-update=ignore |
| Tab switching | 3 | Default, switch, error clears |

### Files on Branch `feat/bux-bankroll` (All Phases)
```
# Phase B1: Contract
contracts/bux-booster-game/contracts/BUXBankroll.sol
contracts/bux-booster-game/contracts/IBUXBankroll.sol
contracts/bux-booster-game/test/BUXBankroll.test.js
contracts/bux-booster-game/scripts/deploy-bux-bankroll.js
contracts/bux-booster-game/scripts/verify-bux-bankroll.js
contracts/bux-booster-game/scripts/setup-bux-bankroll.js

# Phase B3: BUX Minter
bux-minter/index.js

# Phase B4: Backend
lib/blockster_v2/bux_minter.ex
lib/blockster_v2/lp_bux_price_tracker.ex
lib/blockster_v2/mnesia_initializer.ex
lib/blockster_v2/application.ex
lib/blockster_v2_web/router.ex
test/blockster_v2/lp_bux_price_tracker_test.exs

# Phase B5: Frontend
lib/blockster_v2_web/live/bankroll_live.ex
assets/js/lp_bux_chart.js
assets/js/bankroll_onchain.js
assets/js/app.js
test/blockster_v2_web/live/bankroll_live_test.exs

# Docs
CLAUDE.md
docs/bux_bankroll_plan.md
docs/session_learnings.md
```

---

## Phase P5: Plinko Mnesia + Backend (Feb 19, 2026)

### PlinkoGame Module (`lib/blockster_v2/plinko_game.ex`)

Game orchestration module following `BuxBoosterOnchain` patterns. Key architecture:

**Module Attributes**:
- `@configs` — 9 entries: `%{index => %{rows, risk_level, max_multiplier_bps}}`
- `@token_addresses` — `%{"BUX" => "0x8E3F...", "ROGUE" => :native}`
- `@payout_tables` — 9 tables: `%{{rows, risk_level} => [basis_point_values]}`
- `@plinko_contract_address` — `"0x7E12c7077556B142F8Fb695F70aAe0359a8be10C"`

**Game Lifecycle**:
1. `get_or_init_game/2` — reuses existing `:committed` game or creates new via `init_game_with_nonce/3`
2. `on_bet_placed/6` — calculates result (ball_path, landing, payout), transitions `:committed` → `:placed`
3. `settle_game/1` — calls BuxMinter to settle on-chain, transitions `:placed` → `:settled`
4. `mark_game_settled/3` — writes `:settled` status + settlement_tx to Mnesia

**Result Calculation** (`calculate_result/6`):
- `combined_seed = SHA256(server_seed <> ":" <> client_seed <> ":" <> nonce)`
- `client_seed = "#{user_id}:#{bet_amount}:#{token}:#{config_index}"`
- Ball path: `byte[i] < 128 = :left, >= 128 = :right` for each row
- Landing position = count of `:right` bounces
- Payout from lookup table in basis points (10000 = 1.0x)

**Key Design Decision**: Single `plinko_settle_bet/4` function (no separate BUX/ROGUE) because the minter's `/plinko/settle-bet` endpoint auto-detects token type from on-chain bet data.

### PlinkoSettler Module (`lib/blockster_v2/plinko_settler.ex`)

GlobalSingleton GenServer (same pattern as `BuxBoosterBetSettler`):
- Checks every 60s for `:placed` games older than 120s
- Uses `dirty_index_read(:plinko_games, :placed, :status)` then filters by `elem(game, 23) < cutoff` (created_at)
- Calls `PlinkoGame.settle_game/1` for each stuck bet

### BuxMinter Additions

7 new functions added to `lib/blockster_v2/bux_minter.ex`:
| Function | Endpoint | Returns |
|----------|----------|---------|
| `plinko_submit_commitment/3` | `POST /plinko/submit-commitment` | `{:ok, tx_hash}` |
| `plinko_settle_bet/4` | `POST /plinko/settle-bet` | `{:ok, %{tx_hash, payout, profited, multiplier_bps}}` |
| `plinko_player_nonce/1` | `GET /plinko/player-nonce/:addr` | `{:ok, nonce}` |
| `plinko_config/1` | `GET /plinko/config/:index` | `{:ok, config_map}` |
| `plinko_stats/0` | `GET /plinko/stats` | `{:ok, stats_map}` |
| `plinko_bet/1` | `GET /plinko/bet/:hash` | `{:ok, bet_map}` |
| `bux_bankroll_max_bet/1` | `GET /bux-bankroll/max-bet/:index` | `{:ok, max_bet}` |

### Mnesia Table: `:plinko_games`

25-element tuple (table name + 24 data fields):
| Pos | Attribute | Type | Notes |
|-----|-----------|------|-------|
| 1 | (table name) | atom | `:plinko_games` |
| 2 | game_id | string | 32-char hex (primary key) |
| 3 | user_id | integer | indexed |
| 4 | wallet_address | string | indexed |
| 5 | server_seed | string | 64-char hex, revealed after settlement |
| 6 | commitment_hash | string | 0x-prefixed SHA256 of server_seed |
| 7 | nonce | integer | per-player sequential |
| 8 | status | atom | `:committed` / `:placed` / `:settled` (indexed) |
| 9 | bet_id | string | commitment hash from contract |
| 10 | token | string | "BUX" or "ROGUE" |
| 11 | token_address | string | hex address |
| 12 | bet_amount | integer | in token units (not wei) |
| 13 | config_index | integer | 0-8 |
| 14 | rows | integer | 8, 12, or 16 |
| 15 | risk_level | atom | `:low`, `:medium`, `:high` |
| 16 | ball_path | list | `[:left, :right, ...]` (length = rows) |
| 17 | landing_position | integer | 0 to rows |
| 18 | payout_bp | integer | basis points (10000 = 1.0x) |
| 19 | payout | integer | in token units |
| 20 | won | boolean | `true` / `false` |
| 21 | commitment_tx | string | tx hash |
| 22 | bet_tx | string | tx hash |
| 23 | settlement_tx | string | tx hash |
| 24 | created_at | integer | Unix seconds (indexed) |
| 25 | settled_at | integer | Unix seconds |

### Tests (89 total, all passing)

**plinko_math_test.exs** (54 tests, async: true):
- Payout table integrity: 9 tables defined, correct sizes per row count
- Symmetry: each table is palindromic
- Exact values match contract spec
- Max multiplier per config
- `calculate_result/6`: deterministic, correct byte→direction mapping, edge cases
- House edge: ≤2% for all configs (verified via binomial probability)
- Config mapping and token address lookup

**plinko_game_test.exs** (26 tests):
- `get_game/1`: returns game map with all 24 fields, handles not_found
- `get_pending_game/1`: finds committed games, ignores placed/settled, returns most recent
- `on_bet_placed/6`: transitions to :placed, stores all bet fields, calculates result, 25-element tuple
- `mark_game_settled/3`: writes :settled status, settlement_tx, settled_at
- `load_recent_games/2`: settled only, descending order, limit/offset, default limit 30

**plinko_settler_test.exs** (9 tests):
- Finds :placed games older than 120s
- Ignores new, committed, and settled games
- GenServer module exports (start_link/1, init/1)

### Debugging Notes

**Mnesia `{:bad_type}` error**: The `write_committed_game` test helper had 24-element tuple instead of 25 — missing `nil` for the `:won` field at position 20. Mnesia reports this as `{:bad_type}` (tuple size mismatch), not a descriptive error. Always count tuple elements carefully when writing Mnesia records.

**Mnesia `{:no_exists}` in tests**: Test helpers used `rescue` to catch table creation failures, but Mnesia signals use Erlang's `:exit` mechanism, not Elixir exceptions. Fix: use `try/catch :exit` pattern:
```elixir
try do
  :mnesia.table_info(:plinko_games, :type)
catch
  :exit, _ ->
    :mnesia.create_table(:plinko_games, ...)
end
```

**Elixir descending range gotcha**: `1..0` in Elixir is a valid range that iterates `[1, 0]` (descending). Use `1..k//1` step syntax to force ascending-only iteration:
```elixir
# BAD: 1..0 iterates [1, 0], causes div-by-zero
Enum.reduce(1..k, 1, fn i, acc -> div(acc * (n - i + 1), i) end)

# GOOD: 1..0//1 is empty range, returns initial accumulator
Enum.reduce(1..k//1, 1, fn i, acc -> div(acc * (n - i + 1), i) end)
```

### Files Added/Modified in Phase P5
```
# New files
lib/blockster_v2/plinko_game.ex
lib/blockster_v2/plinko_settler.ex
test/blockster_v2/plinko/plinko_math_test.exs
test/blockster_v2/plinko/plinko_game_test.exs
test/blockster_v2/plinko/plinko_settler_test.exs

# Modified files
lib/blockster_v2/mnesia_initializer.ex     # +:plinko_games table
lib/blockster_v2/bux_minter.ex             # +7 Plinko API functions
lib/blockster_v2/application.ex            # +PlinkoSettler child
```
