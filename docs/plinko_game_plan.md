# Plinko Game - Implementation Plan

> **Purpose**: Complete implementation plan for a provably fair Plinko gambling game on Rogue Chain, using the same infrastructure as BUX Booster (commit-reveal, ERC-4337, BUX Minter). This document provides everything needed to build the game from scratch.

## Implementation Progress

### Phase P1: ROGUEBankroll V11 (Plinko Integration) — COMPLETE (Feb 19, 2026)
- **Note**: Originally planned as "V10" in the plan, but the existing V10 upgrade was a per-difficulty stats fix. Plinko additions are V11.
- **Worktree**: `../blockster-v2-bankroll` on branch `feat/bux-bankroll`
- **Files modified**:
  - `contracts/bux-booster-game/contracts/ROGUEBankroll.sol` — Added Plinko state variables, functions, events at END of contract
  - New state: `plinkoGame`, `PlinkoPlayerStats`, `PlinkoAccounting`, `plinkoBetsPerConfig`, `plinkoPnLPerConfig`
  - New functions: `setPlinkoGame`, `updateHouseBalancePlinkoBetPlaced`, `settlePlinkoWinningBet`, `settlePlinkoLosingBet`
  - New view functions: `getPlinkoAccounting`, `getPlinkoPlayerStats`
  - New events: `PlinkoBetPlaced`, `PlinkoWinningPayout`, `PlinkoWinDetails`, `PlinkoLosingBet`, `PlinkoLossDetails`, `PlinkoPayoutFailed`
- **On-chain upgrade**:
  - Script: `scripts/upgrade-roguebankroll-v11.js` (Hardhat `upgrades.upgradeProxy` pattern)
  - Deployer: `0xc2eF57fA90094731E216201417C2DA308C2E474B` (ROGUEBankroll owner)
  - New implementation: `0xDB234Bc265645ec198Ba1fFbBFD7a83f4B0caF5E`
  - Proxy unchanged: `0x51DB4eD2b69b598Fade1aCB5289C7426604AB2fd`
- **No reinitializer needed** — only new storage (defaults to zero) and new functions

### Phase P2: PlinkoGame.sol — COMPLETE (Feb 19, 2026)
- **Worktree**: `../blockster-v2-bankroll` on branch `feat/bux-bankroll`
- **Files created**:
  - `contracts/bux-booster-game/contracts/PlinkoGame.sol` — flattened UUPS proxy contract (all OZ v5 deps inlined)
  - `contracts/bux-booster-game/test/PlinkoGame.test.js` — 102 tests, all passing
- **Source**: Copied from `docs/PlinkoGame_full.sol`
- **Test fixes applied** (from initial 14 failures → 0):
  - Reduced bet amounts from 100/50 BUX to 10 BUX (5 BUX for config 2) to stay within max bet limits
  - Fixed BUXBankroll stats property access: trailing underscores (`totalBets_`, `wins_`, `totalWagered_`, `largestBet_`)
  - Rewrote UUPS upgrade tests to use direct `upgradeToAndCall` (OZ v5 removed standalone `upgradeTo`)
- **Compiler**: Compiles clean
- **Max bet formula**: `maxBet = (netBalance * MAX_BET_BPS / 10000) * 20000 / maxMultiplierBps`
  - For 100k house, config 0 (56000 maxMult): ≈35.71 BUX max
  - For 100k house, config 2 (360000 maxMult): ≈5.56 BUX max
  - For 100k house, config 8 (10000000 maxMult): ≈0.20 BUX max

### Phase P3: Deploy PlinkoGame + Wire Contracts — COMPLETE (Feb 19, 2026)
- **PlinkoGame deployed to Rogue Chain Mainnet** (Chain ID: 560013):
  - Script: `scripts/deploy-plinko-game.js`
  - Proxy: `0x7E12c7077556B142F8Fb695F70aAe0359a8be10C`
  - Implementation: `0x92dCB1081B71B8F5E771DdaF44b8a43Aadca4b4C`
  - Owner: `0x4BDC5602f2A3E04c6e3a9321A7AC5000e0A623e0`
- **BUXBankroll upgraded** with Plinko additions:
  - Script: `scripts/upgrade-bux-bankroll.js` (Hardhat `upgrades.upgradeProxy`)
  - New implementation: `0x5C4A9a699C6846ed6e9bB557C4342fA99c58f3E6`
  - Upgrade tx: `0xed9836a2d6e3071c8e038c2f4bbd304217d11a2398d0f909b93d96b6843a3906` (block 117775048)
- **All contract wiring complete**:
  - BUXBankroll → plinkoGame: `0x7E12c7077556B142F8Fb695F70aAe0359a8be10C` (set during deploy)
  - ROGUEBankroll → plinkoGame: `0x7E12c7077556B142F8Fb695F70aAe0359a8be10C` (script: `set-plinko-on-roguebankroll.js`, run by ROGUEBankroll owner `0xc2eF...`)
  - PlinkoGame → buxBankroll: `0xED7B00Ab2aDE39AC06d4518d16B465C514ba8630`
  - PlinkoGame → rogueBankroll: `0x51DB4eD2b69b598Fade1aCB5289C7426604AB2fd`
  - PlinkoGame → buxToken: `0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8`
  - PlinkoGame → settler: `0x7700EFCCC54bD10B75E0d0C8B38881a61571A7d7` (script: `set-plinko-settler.js`)
  - All 9 payout tables set
  - BUX token enabled via `configureToken`
- **Scripts created**:
  - `scripts/deploy-plinko-game.js` — full deploy + setup (proxy, 9 payout tables, link bankrolls, enable BUX, wire setPlinkoGame)
  - `scripts/upgrade-bux-bankroll.js` — UUPS upgrade via Hardhat
  - `scripts/upgrade-roguebankroll-v11.js` — Transparent proxy upgrade via Hardhat
  - `scripts/set-plinko-on-roguebankroll.js` — setPlinkoGame for ROGUEBankroll (different owner)
  - `scripts/set-plinko-settler.js` — setSettler on PlinkoGame
- **Two deployer wallets**:
  - `0x4BDC5602f2A3E04c6e3a9321A7AC5000e0A623e0` — owns BUXBankroll and PlinkoGame (DEPLOYER_PRIVATE_KEY)
  - `0xc2eF57fA90094731E216201417C2DA308C2E474B` — owns ROGUEBankroll (separate key)
- **Known gap**: BUXBankroll has no house liquidity deposited yet (getMaxBet returns 0 for all configs). BUX bets won't work until liquidity is deposited.

### Phase P4: BUX Minter Plinko Endpoints — COMPLETE (Feb 19, 2026)
- **File modified**: `bux-minter/index.js`
- **PlinkoGame contract setup**:
  - Added `PLINKO_SETTLER_PRIVATE_KEY` env var (already set as Fly secret)
  - Added `PLINKO_CONTRACT_ADDRESS = '0x7E12c7077556B142F8Fb695F70aAe0359a8be10C'`
  - Added `PLINKO_ABI` with all needed functions/events
  - Created dedicated `plinkoSettlerWallet` and `plinkoContract` (write) + `plinkoReadContract` (read-only)
  - Created `txQueues.plinkoSettler` transaction queue (separate from BuxBooster settler to avoid nonce conflicts)
- **New endpoints** (all behind `authenticate` middleware):
  - `POST /plinko/submit-commitment` — submit commitment hash to PlinkoGame contract
  - `POST /plinko/settle-bet` — settle bet (auto-detects BUX vs ROGUE from on-chain bet.token, calls `settleBet` or `settleBetROGUE`)
  - `GET /plinko/player-nonce/:address` — player's on-chain nonce
  - `GET /plinko/player-state/:address` — player's current state
  - `GET /plinko/config/:configIndex` — config details + payout table + max bet
  - `GET /plinko/stats` — global totalBetsPlaced/totalBetsSettled
  - `GET /plinko/bet/:commitmentHash` — bet details by commitment hash
  - `GET /bux-bankroll/max-bet/:configIndex` — max bet from BUXBankroll (was TODO from Phase B3)
- **Updated queue-status**: includes PlinkoGame contract address
- **Updated startup logs**: shows PlinkoGame and plinko settler info
- **Deployed to Fly.io**: `flyctl deploy --app bux-minter` — successful
- **Plinko settler wallet**: `0x7700EFCCC54bD10B75E0d0C8B38881a61571A7d7` (1M ROGUE gas funded)

### Phase P5: Mnesia + Backend — COMPLETE (Feb 19, 2026)
- **Worktree**: `../blockster-v2-bankroll` on branch `feat/bux-bankroll`
- **Files created**:
  - `lib/blockster_v2/plinko_game.ex` — Game orchestration module (~380 lines)
    - Module attributes: `@configs` (9 entries), `@token_addresses`, `@payout_tables` (9 tables with exact basis point values)
    - Public accessors: `configs/0`, `payout_tables/0`, `plinko_contract_address/0`, `token_address/1`
    - Game lifecycle: `get_or_init_game/2`, `init_game_with_nonce/3`, `on_bet_placed/6`, `settle_game/1`, `mark_game_settled/3`
    - Result calculation: `calculate_result/6`, `calculate_game_result/5`
    - Mnesia reads: `get_game/1`, `get_pending_game/1`, `load_recent_games/2`
    - Private helpers: `update_user_betting_stats/5`, `game_tuple_to_map/1`, `is_bet_already_settled_error?/1`, `to_wei/1`
  - `lib/blockster_v2/plinko_settler.ex` — Background settlement GenServer (~95 lines)
    - GlobalSingleton pattern (same as BuxBoosterBetSettler)
    - Checks every 60s for `:placed` games older than 120s
    - Uses `dirty_index_read(:plinko_games, :placed, :status)` + age filter
    - Calls `PlinkoGame.settle_game/1` for each stuck bet
  - `test/blockster_v2/plinko/plinko_math_test.exs` — 54 tests (async: true)
    - Payout table integrity, symmetry, exact value matching, calculate_result determinism, house edge verification
  - `test/blockster_v2/plinko/plinko_game_test.exs` — 26 tests
    - get_game, get_pending_game, on_bet_placed, mark_game_settled, load_recent_games
  - `test/blockster_v2/plinko/plinko_settler_test.exs` — 9 tests
    - Stuck bet detection, GenServer lifecycle
- **Files modified**:
  - `lib/blockster_v2/mnesia_initializer.ex` — Added `:plinko_games` table (24 attributes, ordered_set, indexes on user_id/wallet_address/status/created_at)
  - `lib/blockster_v2/bux_minter.ex` — Added 7 Plinko API functions:
    - `plinko_submit_commitment/3`, `plinko_settle_bet/4` (single endpoint, auto-detects BUX/ROGUE)
    - `plinko_player_nonce/1`, `plinko_config/1`, `plinko_stats/0`, `plinko_bet/1`, `bux_bankroll_max_bet/1`
  - `lib/blockster_v2/application.ex` — Added `{BlocksterV2.PlinkoSettler, []}` to genserver_children
- **Tests**: 89/89 passing (`mix test test/blockster_v2/plinko/`)
- **Key design decisions**:
  - `plinko_settle_bet/4` is a single function (not separate BUX/ROGUE) because the minter's `/plinko/settle-bet` endpoint auto-detects token from on-chain bet data
  - `update_user_betting_stats/5` duplicated from BuxBoosterOnchain (writes to shared `:user_betting_stats` Mnesia table)
  - Mnesia tuple is 25 elements (1 table name + 24 data fields), matching Section 9 spec
- **Bugs fixed during testing**:
  - `write_committed_game` test helper had 24-element tuple (missing `nil` for `:won` field) → `{:bad_type}` Mnesia error
  - `ensure_mnesia_table` test helper used `rescue` (doesn't catch Erlang `:exit` signals) → `{:no_exists}` error
  - `binomial_coeff` in math tests needed `1..k//1` step syntax to prevent Elixir descending range iteration
  - Duplicate `dirty_read` pattern match: `[{record}]` vs correct `[record]`

### Phase P6: Frontend (PlinkoLive + JS Hooks) — COMPLETE (Feb 19, 2026)
- **Worktree**: `../blockster-v2-bankroll` on branch `feat/bux-bankroll`
- **Files created**:
  - `lib/blockster_v2_web/live/plinko_live.ex` — Full LiveView module (~1090 lines)
    - Inline HEEx template following BuxBoosterLive monolithic pattern
    - Mount: guest (defaults), no-wallet (error), authenticated (async init with retry)
    - SVG Plinko board with dynamic peg/slot generation for all 9 configs (8/12/16 rows × Low/Med/High)
    - Config selector (rows + risk level tabs), bet controls (input, /2, x2, MAX), token selector (BUX/ROGUE dropdown)
    - Event handlers: select_rows, select_risk, update_bet_amount, halve_bet, double_bet, set_max_bet, select_token, toggle_token_dropdown, drop_ball, bet_confirmed, bet_failed, ball_landed, reset_game, show_fairness_modal, hide_fairness_modal, clear_error, load-more-games
    - Async handlers: init_onchain_game (with 3-retry exponential backoff), fetch_house_balance, load_recent_games
    - PubSub handlers: bux_balance_updated, token_balances_updated, plinko_settled, token_prices_updated
    - Game history table with LiveView streams (`stream_configure` with `dom_id: &"game-#{&1.game_id}"`)
    - Optimistic balance deduction via `EngagementTracker.deduct_user_token_balance/4` (refund on failure)
    - Provably fair modal (only reveals server seed for settled games)
    - Confetti animation on wins, result display with payout multiplier
  - `assets/js/plinko_ball.js` — PlinkoBall SVG animation hook (~220 lines)
    - Row-by-row ball drop animation with cubic ease-out easing
    - Dynamic layout calculation matching LiveView SVG coordinates
    - Trail effects, peg flash on bounce, slot highlight on landing
    - 6-second total animation, configurable for 8/12/16 row boards
    - Methods: getLayout, getPegPosition, getBallPositionAfterBounce, getSlotPosition, animateDrop, animateToRow, animateLanding, calculateTimings, addTrail, flashPeg, getPegIndex, highlightSlot, clearTrails, resetBall
  - `assets/js/plinko_onchain.js` — PlinkoOnchain blockchain hook (~280 lines)
    - Thirdweb smart wallet integration (ERC-4337 Account Abstraction)
    - ERC-20 approval flow with localStorage caching (`plinko_bux_approved`)
    - `placeBetBackground`: orchestrates needsApproval → executeApprove → executePlaceBet/executePlaceBetROGUE
    - Error parsing with contract error signature matching
    - Contract: `0x7E12c7077556B142F8Fb695F70aAe0359a8be10C`
    - BUX Token: `0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8`
  - `assets/js/PlinkoGame.json` — Contract ABI (copied from Hardhat artifacts)
  - `test/blockster_v2_web/live/plinko_live_test.exs` — 51 tests (~530 lines)
    - Mount tests: guest (4), no-wallet (2), authenticated (3)
    - Config selection: rows (1), risk (1)
    - Bet controls: update (2), halve (2), double (1), max (1)
    - Token selection (2), drop_ball validation (4), JS events (3)
    - Reset (1), fairness modal (3), clear error (1)
    - PubSub handlers (5), async handlers (3)
    - SVG rendering (3), game state rendering (3), game history (4)
    - Format helpers (6)
- **Files modified**:
  - `assets/js/app.js` — Added `PlinkoBall` and `PlinkoOnchain` hook imports and registration
  - `lib/blockster_v2_web/router.ex` — Added `live "/plinko", PlinkoLive, :index` in `:default` live_session
  - `assets/css/app.css` — Added Plinko CSS: `confetti-fall` keyframe, `.plinko-peg`, `#plinko-ball`, `.plinko-trail`, `.plinko-slot`, `.plinko-slot-hit`, `slot-pulse` keyframe, `.config-tab`, `.plinko-game-card`, `.plinko-win-text`, `plinko-scale-in` keyframe
- **Tests**: 51/51 passing (`mix test test/blockster_v2_web/live/plinko_live_test.exs`)
- **Compilation**: Zero warnings from Plinko files (pre-existing warnings in other files only)
- **Bugs fixed during development**:
  - `@configs` module attribute unused → removed (configs accessed via `PlinkoGame.configs()` directly in mount)
  - `EngagementTracker.deduct_user_token_balance/3` doesn't exist → needs 4 args `(user_id, wallet_address, token, amount)`. Same for `credit_user_token_balance/4`
  - `PriceTracker.get_rogue_price/0` doesn't exist → added private `get_rogue_price/0` helper calling `PriceTracker.get_price("ROGUE")`
  - `format_integer/1` defined but unused → removed
  - Stream `:game_history` missing initialization in mount → added `stream_configure` + `stream(:game_history, [])`
  - Stream dom_id error: game maps use `:game_id` not `:id` → `stream_configure(:game_history, dom_id: &"game-#{&1.game_id}")`
  - Guest cond ordering: `not @onchain_ready` checked before `@current_user == nil` → reordered so guests see "Login to Play"
  - `double_bet` handler: `min(doubled, max_bet)` when `max_bet=0` clamps to 0 → skip clamping when `max_bet <= 0`
  - Test `user_no_wallet` fixture: both `slug` and `smart_wallet_address` nil causes layout crash (`cannot convert nil to param` at `layouts.ex:196`) → gave test user a slug
  - Test Mnesia setup: `:token_prices` table missing → added to `ensure_mnesia_tables/0`

## Review Notes (Feb 2026)

> **Status**: Plan reviewed and fleshed out by multi-agent team. All code sections now contain complete, production-ready implementations. All 9 payout tables verified mathematically correct.
>
> **Latest review pass** (added complete implementations for all previously missing pieces):
> - `init_game_with_nonce/3`: Complete with seed generation, commitment submission, full 25-element Mnesia tuple (Section 5.1)
> - `get_pending_game/1`: Complete Mnesia index read matching BuxBoosterOnchain pattern (Section 5.1)
> - `mark_game_settled/3`: Complete Mnesia write with all 25 tuple positions (Section 5.1)
> - `update_user_betting_stats/5`: Delegates to EngagementTracker (Section 5.1)
> - `token_address/1` and `@token_addresses`: Added to module attributes (Section 5.1)
> - `payout_tables/0` and `configs/0`: Public accessors added (Section 5.1)
> - All 16 event handlers: Complete implementations for select_rows, select_risk, update_bet_amount, halve_bet, double_bet, set_max_bet, select_token, toggle_token_dropdown, bet_confirmed, bet_failed, ball_landed, reset_game, show_fairness_modal, hide_fairness_modal, load-more-games (Section 7.6)
> - All 4 PubSub handlers: bux_balance_updated, token_balances_updated, plinko_settled, token_prices_updated (Section 7.6)
> - All 6 async handlers: init_onchain_game (success/error/crash), fetch_house_balance, load_recent_games, load_more_games, settle_game (Section 7.6)
> - `assign_defaults_for_guest/1`: Complete guest socket assigns (Section 7.6)
> - Helper functions: get_balance/2, config_index_for/2, calculate_max_bet/2, maybe_update_max_bet/2, generate_confetti/1, format_balance/1, format_usd/2, format_integer/1, add_commas/1 (Section 7.6)
> - Complete HEEx render template: Full page layout, config selector, bet controls, SVG board, commitment display, drop button, result display, fairness modal, game history table with infinite scroll (Section 7.7)
>
> **Math**: All house edges confirmed (0.94% - 1.15% range). All payout tables symmetric. All max multipliers correct.
>
> **Contract fixes applied** (inline below):
> - `receive() external payable {}` added (Section 3)
> - Path validation in `settleBet` added (Section 3)
> - `PayoutTableNotSet` check in `placeBet` added (Section 3)
> - ROGUEBankroll V10 upgrade notes updated (Section 4)
>
> **Backend fixes applied** (inline below):
> - `settle_game` branches on `game.token` for BUX vs ROGUE (Section 5.1)
> - Full 25-element Mnesia tuple in `on_bet_placed` (Section 5.1)
> - EngagementTracker integration for optimistic balance deduction/refund (Section 7.6)
> - BUX Minter HTTP functions with full Req config (Section 5.3)
> - Plinko functions added to existing `bux_minter.ex` (Section 5.3)
>
> **Frontend fixes applied** (inline below):
> - All socket assigns documented with types and defaults (Section 7.2)
> - PlinkoBall hook complete with animateToRow(), animateLanding(), SVG coordinate math (Section 8.1)
> - PlinkoOnchain hook complete with approval flow, error handling (Section 8.2)
> - handle_info for all PubSub messages, retry logic, loading states (Section 7.6)
>
> **Known remaining placeholder**: Error signature hex values in `plinko_onchain.js` (Section 8.2) marked `"0x..."` for InvalidConfigIndex, InsufficientHouseBalance, CommitmentNotFound, CommitmentAlreadyUsed, CommitmentWrongPlayer, PayoutTableNotSet. Must be computed from compiled ABI: `ethers.id("ErrorName()").slice(0,10)`.
>
> **BUXBankroll architecture** (Feb 2026):
> - PlinkoGame delegates all BUX money movement to BUXBankroll (LP token, centralized BUX pool)
> - ROGUE path unchanged (uses ROGUEBankroll)
> - BUXBankroll built and deployed BEFORE PlinkoGame
> - Full BUXBankroll spec: `docs/bux_bankroll_plan.md`

---

## Table of Contents

1. [Game Overview](#1-game-overview)
2. [Payout Tables & Game Math](#2-payout-tables--game-math)
3. [Smart Contract: PlinkoGame.sol](#3-smart-contract-plinkogamesol)
4. [Smart Contract: ROGUEBankroll Modifications](#4-smart-contract-roguebankroll-modifications)
5. [Backend: Elixir Modules](#5-backend-elixir-modules)
6. [BUX Minter Service Changes](#6-bux-minter-service-changes)
7. [UI: LiveView & Frontend](#7-ui-liveview--frontend)
8. [JavaScript Hooks](#8-javascript-hooks)
9. [Database: Mnesia Tables](#9-database-mnesia-tables)
10. [Admin & Stats](#10-admin--stats)
11. [Provably Fair System](#11-provably-fair-system)
12. [Animation & Timing](#12-animation--timing)
13. [Implementation Order](#13-implementation-order)
14. [File List](#14-file-list)
15. [Testing Plan](#15-testing-plan)

---

## 1. Game Overview

### What Is Plinko?

A ball drops through a triangular peg board with N rows. At each peg, the ball bounces either left or right (50/50). After N bounces, the ball lands in one of N+1 slots. The landing slot determines the payout multiplier.

### Configurations

9 game configurations: 3 row counts x 3 risk levels.

| Config Index | Rows | Risk | Landing Slots | Description |
|-------------|------|------|---------------|-------------|
| 0 | 8 | Low | 9 | Low variance, most outcomes near 1x |
| 1 | 8 | Medium | 9 | Moderate spread |
| 2 | 8 | High | 9 | Extreme spread, center pays 0x |
| 3 | 12 | Low | 13 | Low variance, more granular |
| 4 | 12 | Medium | 13 | Moderate spread |
| 5 | 12 | High | 13 | Extreme, center 0x, edges 405x |
| 6 | 16 | Low | 17 | Very flat, most near 1x |
| 7 | 16 | Medium | 17 | Moderate spread |
| 8 | 16 | High | 17 | Maximum variance, edges 1000x |

### Key Differences from BUX Booster

| Aspect | BUX Booster | Plinko |
|--------|-------------|--------|
| Player chooses | Difficulty + predictions (heads/tails per flip) | Config only (rows + risk) |
| Outcome type | Binary win/lose | Variable payout (0x to 1000x) |
| Result | Array of heads/tails matched against predictions | Ball path + landing position -> payout lookup |
| Animation | Sequential coin flips (3s per flip) | Single ball drop (5-7s total) |
| State machine | idle -> flipping -> showing_result -> result (per flip) | idle -> dropping -> landed -> result |

### Supported Tokens

Same as BUX Booster: **BUX** (ERC-20) and **ROGUE** (native).

---

## 2. Payout Tables & Game Math

### Probability Distribution

Landing position follows a binomial distribution: P(position = k) = C(N, k) / 2^N

The distribution is symmetric: position k has the same probability as position N-k.

### Payout Tables (Basis Points, 10000 = 1.0x)

#### 8 Rows (9 positions)

**LOW** (House Edge: ~1.0%):
```
[56000, 21000, 11000, 10000, 5000, 10000, 11000, 21000, 56000]
```
| Pos | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|-----|---|---|---|---|---|---|---|---|---|
| Prob | 0.39% | 3.13% | 10.94% | 21.88% | 27.34% | 21.88% | 10.94% | 3.13% | 0.39% |
| Mult | 5.6x | 2.1x | 1.1x | 1.0x | 0.5x | 1.0x | 1.1x | 2.1x | 5.6x |

**MEDIUM** (House Edge: ~1.1%):
```
[130000, 30000, 13000, 7000, 4000, 7000, 13000, 30000, 130000]
```
| Pos | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|-----|---|---|---|---|---|---|---|---|---|
| Mult | 13.0x | 3.0x | 1.3x | 0.7x | 0.4x | 0.7x | 1.3x | 3.0x | 13.0x |

**HIGH** (House Edge: ~0.9%):
```
[360000, 40000, 15000, 3000, 0, 3000, 15000, 40000, 360000]
```
| Pos | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|-----|---|---|---|---|---|---|---|---|---|
| Mult | 36.0x | 4.0x | 1.5x | 0.3x | 0.0x | 0.3x | 1.5x | 4.0x | 36.0x |

#### 12 Rows (13 positions)

**LOW** (House Edge: ~1.0%):
```
[110000, 30000, 16000, 14000, 11000, 10000, 5000, 10000, 11000, 14000, 16000, 30000, 110000]
```

**MEDIUM** (House Edge: ~1.0%):
```
[330000, 110000, 40000, 20000, 11000, 6000, 3000, 6000, 11000, 20000, 40000, 110000, 330000]
```

**HIGH** (House Edge: ~1.0%):
```
[4050000, 180000, 70000, 20000, 7000, 2000, 0, 2000, 7000, 20000, 70000, 180000, 4050000]
```

#### 16 Rows (17 positions)

**LOW** (House Edge: ~1.0%):
```
[160000, 90000, 20000, 14000, 14000, 12000, 11000, 10000, 5000, 10000, 11000, 12000, 14000, 14000, 20000, 90000, 160000]
```

**MEDIUM** (House Edge: ~1.0%):
```
[1100000, 410000, 100000, 50000, 30000, 15000, 10000, 5000, 3000, 5000, 10000, 15000, 30000, 50000, 100000, 410000, 1100000]
```

**HIGH** (House Edge: ~1.2%):
```
[10000000, 1500000, 330000, 100000, 33000, 20000, 3000, 2000, 0, 2000, 3000, 20000, 33000, 100000, 330000, 1500000, 10000000]
```

### Max Multiplier Per Config

| Config | Max Multiplier | Max Basis Points |
|--------|---------------|-----------------|
| 8-Low | 5.6x | 56,000 |
| 8-Med | 13.0x | 130,000 |
| 8-High | 36.0x | 360,000 |
| 12-Low | 11.0x | 110,000 |
| 12-Med | 33.0x | 330,000 |
| 12-High | 405.0x | 4,050,000 |
| 16-Low | 16.0x | 160,000 |
| 16-Med | 110.0x | 1,100,000 |
| 16-High | 1000.0x | 10,000,000 |

### Max Bet Formula

Same as BUX Booster, using the max multiplier per config:
```
maxBet = (availableLiquidity * MAX_BET_BPS / 10000) * 20000 / maxMultiplierBps
```
Where `MAX_BET_BPS = 10` (0.1% of available bankroll liquidity). For BUX, `availableLiquidity` comes from `BUXBankroll.getAvailableLiquidity()`. For ROGUE, from ROGUEBankroll.

### Edge Hit Frequencies

| Rows | Edge Probability | ~1 in N drops |
|------|-----------------|---------------|
| 8 | 0.39% | 256 |
| 12 | 0.024% | 4,096 |
| 16 | 0.0015% | 65,536 |

---

## 3. Smart Contract: PlinkoGame.sol

### Overview

New UUPS Proxy contract. Fresh V1 deployment (not an upgrade of BuxBoosterGame). Same commit-reveal pattern, same settler role. BUX settlement is delegated to BUXBankroll (see `docs/bux_bankroll_plan.md`). ROGUE settlement is delegated to ROGUEBankroll. PlinkoGame does NOT hold house balance directly for either token.

### Inheritance

```solidity
PlinkoGame is Initializable, UUPSUpgradeable, OwnableUpgradeable,
               ReentrancyGuardUpgradeable, PausableUpgradeable
```

### Structs

```solidity
struct TokenConfig { bool enabled; }  // No houseBalance — held by BUXBankroll/ROGUEBankroll

struct PlinkoBet {
    address player;
    address token;
    uint256 amount;
    uint8 configIndex;        // 0-8
    bytes32 commitmentHash;
    uint256 nonce;
    uint256 timestamp;
    BetStatus status;         // Pending, Won, Lost, Push, Expired
}

struct Commitment {
    address player;
    uint256 nonce;
    uint256 timestamp;
    bool used;
    bytes32 serverSeed;       // Revealed after settlement
}

struct PlinkoConfig {
    uint8 rows;               // 8, 12, or 16
    uint8 riskLevel;          // 0=Low, 1=Medium, 2=High
    uint8 numPositions;       // rows + 1
    uint32 maxMultiplierBps;  // Highest multiplier in payout table
}

struct PlayerStats {
    uint256 totalBets; uint256 wins; uint256 losses; uint256 pushes;
    uint256 totalWagered; uint256 totalWinnings; uint256 totalLosses;
    uint256[9] betsPerConfig; int256[9] profitLossPerConfig;
}

struct GlobalAccounting {
    uint256 totalBets; uint256 totalWins; uint256 totalLosses; uint256 totalPushes;
    uint256 totalVolumeWagered; uint256 totalPayouts;
    int256 totalHouseProfit; uint256 largestWin; uint256 largestBet;
}

enum BetStatus { Pending, Won, Lost, Push, Expired }
```

### Constants

```solidity
BET_EXPIRY = 1 hours
MIN_BET = 1e18 (1 token, 18 decimals)
MAX_BET_BPS = 10 (0.1% of available bankroll liquidity)
MULTIPLIER_DENOMINATOR = 10000
```

### Storage Layout (UUPS - only add at END)

> **NOTE**: BUX player stats and accounting are tracked in BUXBankroll, not here.
> BUX referral system is also in BUXBankroll. PlinkoGame only tracks game lifecycle.

```
PlinkoConfig[9] plinkoConfigs
mapping(uint8 => uint32[]) payoutTables          // configIndex -> multiplier array
mapping(bytes32 => PlinkoBet) bets
mapping(address => uint256) playerNonces
mapping(address => bytes32[]) playerBetHistory
mapping(bytes32 => Commitment) commitments
mapping(address => mapping(uint256 => bytes32)) playerCommitments
address settler
uint256 totalBetsPlaced
uint256 totalBetsSettled
address rogueBankroll
address buxBankroll                               // NEW: BUXBankroll LP contract
address buxToken                                  // NEW: BUX ERC-20 address
```

### Events (Descriptive for Roguescan)

```solidity
// Pre-game
event CommitmentSubmitted(bytes32 indexed commitmentHash, address indexed player, uint256 nonce);

// Bet placed - clear game info
event PlinkoBetPlaced(
    bytes32 indexed commitmentHash, address indexed player, address indexed token,
    uint256 amount, uint8 configIndex, uint8 rows, uint8 riskLevel, uint256 nonce
);

// PRIMARY settlement event - full outcome story
event PlinkoBetSettled(
    bytes32 indexed commitmentHash, address indexed player,
    bool profited,                  // did player get more than they bet?
    uint8 landingPosition,          // which slot (0 to rows)
    uint32 payoutMultiplierBps,     // multiplier applied
    uint256 betAmount,              // amount wagered
    uint256 payoutAmount,           // amount paid out
    int256 profitLoss,              // positive = player profit, negative = loss
    bytes32 serverSeed              // revealed for verification
);

// Ball path details - how the ball bounced
event PlinkoBallPath(
    bytes32 indexed commitmentHash,
    uint8 configIndex,
    uint8[] path,                   // 0=left, 1=right at each peg
    uint8 landingPosition,
    string configLabel              // "8-Low", "16-High", etc.
);

// Token and timing details (split to avoid stack-too-deep)
event PlinkoBetDetails(
    bytes32 indexed commitmentHash, address indexed token,
    uint256 amount, uint8 configIndex, uint256 nonce, uint256 timestamp
);

event PlinkoBetExpired(bytes32 indexed betId, address indexed player);
event TokenConfigured(address indexed token, bool enabled);
// No HouseDeposit/HouseWithdraw events — PlinkoGame does not hold house balance
// House deposits/withdrawals happen in BUXBankroll and ROGUEBankroll
event PayoutTableUpdated(uint8 indexed configIndex, uint8 rows, uint8 riskLevel);
event ReferralRewardPaid(bytes32 indexed commitmentHash, address indexed referrer,
                         address indexed player, address token, uint256 amount);
event ReferrerSet(address indexed player, address indexed referrer);
```

### Key Functions

**Settler (onlySettler = settler address OR owner):**
- `submitCommitment(bytes32 commitmentHash, address player, uint256 nonce)`
- `settleBet(bytes32 commitmentHash, bytes32 serverSeed, uint8[] path, uint8 landingPosition)` - BUX settlement
- `settleBetROGUE(bytes32 commitmentHash, bytes32 serverSeed, uint8[] path, uint8 landingPosition)` - ROGUE settlement

**Player:**
- `placeBet(address token, uint256 amount, uint8 configIndex, bytes32 commitmentHash)` - ERC-20 bet
- `placeBetROGUE(uint256 amount, uint8 configIndex, bytes32 commitmentHash)` payable - Native bet

**Admin (onlyOwner):**
- `setPayoutTable(uint8 configIndex, uint32[] multipliers)` - Set/update payout table (auto-updates maxMultiplierBps)
- `configureToken(address token, bool enabled)`
- `setSettler(address)` / `setROGUEBankroll(address)` / `setBUXBankroll(address)` / `setPaused(bool)`
- NOTE: BUX referral admin functions (`setReferralBasisPoints`, `setReferralAdmin`, `setPlayerReferrer`, `setPlayerReferrersBatch`) live on **BUXBankroll**, not PlinkoGame. ROGUE referral functions live on **ROGUEBankroll**.

**View:**
- `getBet(bytes32)`, `getPayoutTable(uint8)`, `getPlinkoConfig(uint8)`
- `getBuxPlayerStats(address)`, `getBuxAccounting()`
- `getMaxBet(uint8)` (queries BUXBankroll), `getMaxBetROGUE(uint8)` (queries ROGUEBankroll)
- `calculateMaxPayout(uint256, uint8)`, `getPlayerBetHistory(address, uint256, uint256)`
- `getCommitment(bytes32)`, `refundExpiredBet(bytes32)` (public, anyone after 1hr)

### Settlement Flow

> **NOTE**: PlinkoGame does NOT hold BUX house funds. All BUX is held by BUXBankroll.
> PlinkoGame handles game logic (commitments, bets, stats, path validation) and delegates
> money movement to BUXBankroll. See `docs/bux_bankroll_plan.md` for full BUXBankroll spec.

**BUX (ERC-20) — via BUXBankroll:**
1. Look up `payoutTables[configIndex][landingPosition]` -> `multiplierBps`
2. Calculate `payout = (amount * multiplierBps) / 10000`
3. If `payout > amount`: Won -- call `BUXBankroll.settlePlinkoWinningBet(player, payout, ...)` -- sends BUX to winner, deducts from pool
4. If `payout < amount`: Lost -- call `BUXBankroll.settlePlinkoLosingBet(player, partialPayout, ...)` -- pool keeps BUX, sends partial payout if > 0, pays referral from pool
5. If `payout == amount`: Push -- call `BUXBankroll.settlePlinkoPushBet(player, ...)` -- returns exact bet
6. BUXBankroll updates stats (plinkoPlayerStats, plinkoAccounting) — NOT tracked in PlinkoGame
7. PlinkoGame emits `PlinkoBetSettled`, `PlinkoBallPath`, `PlinkoBetDetails`

**BUX placeBet flow:**
1. Player approves BUXBankroll (not PlinkoGame) to spend BUX
2. `placeBet` calls `safeTransferFrom(player -> BUXBankroll)` then `BUXBankroll.updateHouseBalancePlinkoBetPlaced()`
3. BUXBankroll tracks liability for the bet's max payout

**ROGUE (native) — unchanged:**
1. Same multiplier lookup
2. If won: call `ROGUEBankroll.settlePlinkoWinningBet()` -- sends ROGUE to winner
3. If lost: call `ROGUEBankroll.settlePlinkoLosingBet()` -- keeps ROGUE, sends NFT + referral rewards

### Initialization

```solidity
function initialize() initializer public {
    __Ownable_init(msg.sender);
    __ReentrancyGuard_init();
    __Pausable_init();
    __UUPSUpgradeable_init();

    // Set up 9 configs (payout tables set via setPayoutTable after deployment)
    plinkoConfigs[0] = PlinkoConfig(8, 0, 9, 0);    // 8-Low
    plinkoConfigs[1] = PlinkoConfig(8, 1, 9, 0);    // 8-Medium
    plinkoConfigs[2] = PlinkoConfig(8, 2, 9, 0);    // 8-High
    plinkoConfigs[3] = PlinkoConfig(12, 0, 13, 0);   // 12-Low
    plinkoConfigs[4] = PlinkoConfig(12, 1, 13, 0);   // 12-Medium
    plinkoConfigs[5] = PlinkoConfig(12, 2, 13, 0);   // 12-High
    plinkoConfigs[6] = PlinkoConfig(16, 0, 17, 0);   // 16-Low
    plinkoConfigs[7] = PlinkoConfig(16, 1, 17, 0);   // 16-Medium
    plinkoConfigs[8] = PlinkoConfig(16, 2, 17, 0);   // 16-High
}
```

Post-deployment: call `setPayoutTable()` for all 9 configs, then `configureToken()` for BUX, `setSettler()`, `setROGUEBankroll()`.

### Path Validation (in settleBet / settleBetROGUE)

```solidity
// CRITICAL: Must validate path integrity before settlement
require(path.length == plinkoConfigs[bet.configIndex].rows, InvalidPath());
for (uint8 i = 0; i < path.length; i++) {
    require(path[i] == 0 || path[i] == 1, InvalidPath());
}
// Verify landing position = count of right bounces (1s in path)
uint8 rightCount = 0;
for (uint8 i = 0; i < path.length; i++) {
    if (path[i] == 1) rightCount++;
}
require(rightCount == landingPosition, InvalidLandingPosition());
require(landingPosition < plinkoConfigs[bet.configIndex].numPositions, InvalidLandingPosition());
```

### Receive Function (Required for ROGUE)

```solidity
// Required to receive ROGUE refunds from ROGUEBankroll
receive() external payable {}
```

### Payout Table Guard (in placeBet / placeBetROGUE)

```solidity
// Prevent bets before payout tables are configured
require(payoutTables[configIndex].length > 0, PayoutTableNotSet());
require(plinkoConfigs[configIndex].maxMultiplierBps > 0, PayoutTableNotSet());
```

### Errors

```solidity
error TokenNotEnabled();
error BetAmountTooLow();
error BetAmountTooHigh();
error InvalidConfigIndex();
error BetNotFound();
error BetAlreadySettled();       // 0x05d09e5f (same sig for graceful handling)
error BetExpiredError();
error InsufficientHouseBalance();
error UnauthorizedSettler();
error BetNotExpired();
error CommitmentNotFound();
error CommitmentAlreadyUsed();
error CommitmentWrongPlayer();
error InvalidToken();
error InvalidPath();             // path.length != rows OR path element not 0/1
error InvalidLandingPosition();  // landingPosition != count(1s in path)
error PayoutTableNotSet();       // payout table not configured for this config
```

---

## 4. Smart Contract: ROGUEBankroll Modifications

### New Version: V10

Add state variables at END of existing storage. New modifier `onlyPlinko`.

### New State Variables

```solidity
address public plinkoGame;

struct PlinkoPlayerStats {
    uint256 totalBets; uint256 wins; uint256 losses; uint256 pushes;
    uint256 totalWagered; uint256 totalWinnings; uint256 totalLosses;
}
mapping(address => PlinkoPlayerStats) public plinkoPlayerStats;
mapping(address => uint256[9]) public plinkoBetsPerConfig;
mapping(address => int256[9]) public plinkoPnLPerConfig;

struct PlinkoAccounting {
    uint256 totalBets; uint256 totalWins; uint256 totalLosses; uint256 totalPushes;
    uint256 totalVolumeWagered; uint256 totalPayouts;
    int256 totalHouseProfit; uint256 largestWin; uint256 largestBet;
}
PlinkoAccounting public plinkoAccounting;
```

### New Functions

```solidity
function setPlinkoGame(address _plinkoGame) external onlyOwner;

function updateHouseBalancePlinkoBetPlaced(
    bytes32 commitmentHash, uint8 configIndex, uint256 nonce, uint256 maxPayout
) external payable onlyPlinko returns(bool);
// Receives ROGUE, updates liability by maxPayout, emits PlinkoBetPlaced

function settlePlinkoWinningBet(
    address winner, bytes32 commitmentHash, uint256 betAmount, uint256 payout,
    uint8 configIndex, uint8 landingPosition, uint8[] calldata path,
    uint256 nonce, uint256 maxPayout
) external onlyPlinko returns(bool);
// Sends payout to winner, updates stats + house balance

function settlePlinkoLosingBet(
    address player, bytes32 commitmentHash, uint256 wagerAmount, uint256 partialPayout,
    uint8 configIndex, uint8 landingPosition, uint8[] calldata path,
    uint256 nonce, uint256 maxPayout
) external onlyPlinko returns(bool);
// Keeps ROGUE, sends partial payout if >0, sends NFT rewards (0.2%) + referral rewards (0.2%) on loss portion

// View functions
function getPlinkoAccounting() external view returns (...);
function getPlinkoPlayerStats(address) external view returns (...);
```

### New Events

```solidity
event PlinkoBetPlaced(address indexed player, bytes32 indexed commitmentHash,
                      uint256 amount, uint8 configIndex, uint256 nonce, uint256 timestamp);
event PlinkoWinningPayout(address indexed winner, bytes32 indexed commitmentHash,
                          uint256 betAmount, uint256 payout, uint256 profit);
event PlinkoWinDetails(bytes32 indexed commitmentHash, uint8 configIndex,
                       uint8 landingPosition, uint8[] path, uint256 nonce);
event PlinkoLosingBet(address indexed player, bytes32 indexed commitmentHash,
                      uint256 wagerAmount, uint256 partialPayout);
event PlinkoLossDetails(bytes32 indexed commitmentHash, uint8 configIndex,
                        uint8 landingPosition, uint8[] path, uint256 nonce);
event PlinkoPayoutFailed(address indexed winner, bytes32 indexed commitmentHash, uint256 payout);
```

### Reward Chain (Same Pattern as BuxBooster)

On every losing ROGUE Plinko bet, calculated on the **loss portion** (betAmount - partialPayout):
1. NFT Reward: `loss * nftRewardBasisPoints / 10000` (0.2%) -> NFTRewarder
2. Referral Reward: `loss * referralBasisPoints / 10000` (0.2%) -> referrer wallet
3. Both non-blocking (failures don't revert settlement)

### Deployment

> **NOTE**: ROGUEBankroll uses `initialize()` only (no reinitializer history like BuxBoosterGame).
> It's a Transparent Proxy (not UUPS). Before upgrading, verify the current initializer version
> on-chain. The upgrade adds new storage at END only — no reinitializer function needed since
> we're not reinitializing existing state, just adding new state variables and functions.

**Manual upgrade** -- ROGUEBankroll will be upgraded manually by the developer.
Focus here is on ensuring the contract code is correct (new state variables at END only,
new functions with proper modifiers, new events). The deployment script is not needed.

Post-upgrade steps:
```bash
# After manual upgrade, call:
setPlinkoGame(<plinko_proxy_address>)
```

---

## 5. Backend: Elixir Modules

### 5.1 PlinkoGame (`lib/blockster_v2/plinko_game.ex`)

Main orchestration module. Follows `BuxBoosterOnchain` patterns exactly.

**Module Attributes:**
```elixir
@plinko_contract_address "0x<DEPLOYED>"  # Set after deployment

@configs %{
  0 => {8, :low},    1 => {8, :medium},  2 => {8, :high},
  3 => {12, :low},   4 => {12, :medium}, 5 => {12, :high},
  6 => {16, :low},   7 => {16, :medium}, 8 => {16, :high}
}

# Public accessor for configs (used by PlinkoLive)
def configs, do: @configs

# Token contract addresses
@token_addresses %{
  "BUX" => "0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8",
  "ROGUE" => "0x0000000000000000000000000000000000000000"
}

def token_address("ROGUE"), do: "0x0000000000000000000000000000000000000000"
def token_address(token), do: Map.get(@token_addresses, token, token)

# Payout tables in basis points - MUST match contract exactly
@payout_tables %{
  0 => [56000, 21000, 11000, 10000, 5000, 10000, 11000, 21000, 56000],                                                              # 8-Low
  1 => [130000, 30000, 13000, 7000, 4000, 7000, 13000, 30000, 130000],                                                              # 8-Med
  2 => [360000, 40000, 15000, 3000, 0, 3000, 15000, 40000, 360000],                                                                 # 8-High
  3 => [110000, 30000, 16000, 14000, 11000, 10000, 5000, 10000, 11000, 14000, 16000, 30000, 110000],                                # 12-Low
  4 => [330000, 110000, 40000, 20000, 11000, 6000, 3000, 6000, 11000, 20000, 40000, 110000, 330000],                                # 12-Med
  5 => [4050000, 180000, 70000, 20000, 7000, 2000, 0, 2000, 7000, 20000, 70000, 180000, 4050000],                                   # 12-High
  6 => [160000, 90000, 20000, 14000, 14000, 12000, 11000, 10000, 5000, 10000, 11000, 12000, 14000, 14000, 20000, 90000, 160000],     # 16-Low
  7 => [1100000, 410000, 100000, 50000, 30000, 15000, 10000, 5000, 3000, 5000, 10000, 15000, 30000, 50000, 100000, 410000, 1100000], # 16-Med
  8 => [10000000, 1500000, 330000, 100000, 33000, 20000, 3000, 2000, 0, 2000, 3000, 20000, 33000, 100000, 330000, 1500000, 10000000] # 16-High
}

# Public accessor for payout tables (used by PlinkoLive)
def payout_tables, do: @payout_tables

defp bux_minter_url do
  Application.get_env(:blockster_v2, :bux_minter_url) || "https://bux-minter.fly.dev"
end

defp generate_game_id do
  :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
end
```

**Key Functions:**

| Function | Purpose |
|----------|---------|
| `get_or_init_game/2` | Reuse committed game or create new (same nonce logic as BuxBooster) |
| `init_game_with_nonce/3` | Generate server seed, submit commitment via BUX Minter, write Mnesia `:committed` |
| `calculate_game_result/4` | Pre-calculate ball path + landing + payout from stored server seed |
| `on_bet_placed/6` | Update Mnesia after blockchain confirms (no predictions field) |
| `settle_game/1` | Settle via BUX Minter `/plinko/settle-bet`, update Mnesia + stats |
| `mark_game_settled/3` | Write `:settled` to Mnesia |
| `get_game/1` | Mnesia dirty_read |
| `get_pending_game/1` | Mnesia dirty_index_read for `:committed` games |

**Result Calculation (Plinko-specific):**

> **Note**: SHA256 produces 32 bytes. Max rows = 16, so we always have enough bytes.
> Client seed uses `user_id:bet_amount:token:config_index` — no predictions field (Plinko has none).
> If same user bets same amount/config/token, client seed is identical — but server_seed
> is unique per game, so results always differ. This is documented in the verification modal.

```elixir
def calculate_result(server_seed, nonce, config_index, bet_amount, token, user_id) do
  {rows, _risk_level} = Map.get(@configs, config_index)

  # Client seed - deterministic from player-controlled values
  # No predictions field (unlike BuxBooster) since Plinko has no player choices
  input = "#{user_id}:#{bet_amount}:#{token}:#{config_index}"
  client_seed = :crypto.hash(:sha256, input) |> Base.encode16(case: :lower)

  # Combined seed (matches BuxBooster pattern: SHA256("server_hex:client_hex:nonce"))
  combined = :crypto.hash(:sha256, "#{server_seed}:#{client_seed}:#{nonce}")

  # Ball path: first `rows` bytes (SHA256 = 32 bytes, max rows = 16, always enough)
  ball_path = for i <- 0..(rows - 1) do
    byte = :binary.at(combined, i)
    if byte < 128, do: :left, else: :right
  end

  # Landing position = count of :right bounces
  landing_position = Enum.count(ball_path, &(&1 == :right))

  # Payout lookup
  payout_table = Map.get(@payout_tables, config_index)
  payout_bp = Enum.at(payout_table, landing_position)
  payout = div(bet_amount * payout_bp, 10000)

  # Determine outcome: won (profit), lost, or push (break even)
  outcome = cond do
    payout > bet_amount -> :won
    payout == bet_amount -> :push
    true -> :lost
  end

  {:ok, %{
    ball_path: ball_path,
    landing_position: landing_position,
    payout: payout,
    payout_bp: payout_bp,
    won: payout > bet_amount,
    outcome: outcome,
    server_seed: server_seed
  }}
end
```

**Wrapper `calculate_game_result/5` (called from LiveView, reads game from Mnesia):**
```elixir
def calculate_game_result(game_id, config_index, bet_amount, token, user_id) do
  case get_game(game_id) do
    {:ok, game} ->
      calculate_result(game.server_seed, game.nonce, config_index, bet_amount, token, user_id)
    {:error, reason} ->
      {:error, reason}
  end
end
```

**Complete `settle_game/1` (must branch on token for BUX vs ROGUE):**
```elixir
def settle_game(game_id) do
  case get_game(game_id) do
    {:ok, game} when game.status == :settled ->
      Logger.debug("[PlinkoGame] Game #{game_id} already settled, skipping")
      {:ok, %{tx_hash: game.settlement_tx, player_balance: nil, already_settled: true}}

    {:ok, game} when game.bet_id != nil ->
      server_seed_hex = "0x" <> game.server_seed

      # Branch on token type — BUX and ROGUE use different contract functions
      settle_fn = case game.token do
        "ROGUE" -> &BuxMinter.plinko_settle_bet_rogue/4
        _ -> &BuxMinter.plinko_settle_bet/4
      end

      case settle_fn.(game.commitment_hash, server_seed_hex, game.ball_path, game.landing_position) do
        {:ok, tx_hash, player_balance} ->
          mark_game_settled(game_id, game, tx_hash)
          update_user_betting_stats(game.user_id, game.token, game.bet_amount, game.won, game.payout)

          # Sync balances and broadcast
          if game.wallet_address do
            BuxMinter.sync_user_balances_async(game.user_id, game.wallet_address)
          end

          Phoenix.PubSub.broadcast(
            BlocksterV2.PubSub,
            "plinko_settlement:#{game.user_id}",
            {:plinko_settled, game_id, tx_hash}
          )

          Logger.info("[PlinkoGame] Game #{game_id} settled: #{tx_hash}")
          {:ok, %{tx_hash: tx_hash, player_balance: player_balance}}

        {:error, reason} ->
          if is_bet_already_settled_error?(reason) do
            Logger.info("[PlinkoGame] Game #{game_id} already settled on-chain")
            mark_game_settled(game_id, game, "already_settled_on_chain")
            update_user_betting_stats(game.user_id, game.token, game.bet_amount, game.won, game.payout)
            {:ok, %{tx_hash: "already_settled_on_chain", player_balance: nil, already_settled: true}}
          else
            Logger.error("[PlinkoGame] Failed to settle game #{game_id}: #{inspect(reason)}")
            {:error, reason}
          end
      end

    {:ok, _game} ->
      {:error, :bet_not_placed}

    {:error, reason} ->
      {:error, reason}
  end
end

defp is_bet_already_settled_error?(reason) when is_binary(reason) do
  String.contains?(reason, "0x05d09e5f")
end
defp is_bet_already_settled_error?(_), do: false
```

**Complete `on_bet_placed/6` (Mnesia tuple construction):**
```elixir
def on_bet_placed(game_id, bet_id, bet_tx, bet_amount, token, config_index) do
  case get_game(game_id) do
    {:ok, game} ->
      token_address = Map.get(@token_addresses, token, token)
      {rows, risk_level} = Map.get(@configs, config_index)

      # Calculate result locally (we have the server seed)
      {:ok, result} = calculate_result(
        game.server_seed, game.nonce, config_index, bet_amount, token, game.user_id
      )

      now = System.system_time(:second)

      # Full Mnesia tuple (25 positions: table name + 24 fields)
      updated_record = {
        :plinko_games,
        game_id,                    # 1: game_id (PK)
        game.user_id,               # 2: user_id
        game.wallet_address,        # 3: wallet_address
        game.server_seed,           # 4: server_seed
        game.commitment_hash,       # 5: commitment_hash
        game.nonce,                 # 6: nonce
        :placed,                    # 7: status
        bet_id,                     # 8: bet_id
        token,                      # 9: token
        token_address,              # 10: token_address
        bet_amount,                 # 11: bet_amount
        config_index,               # 12: config_index
        rows,                       # 13: rows
        risk_level,                 # 14: risk_level
        result.ball_path,           # 15: ball_path
        result.landing_position,    # 16: landing_position
        result.payout_bp,           # 17: payout_bp
        result.payout,              # 18: payout
        result.won,                 # 19: won
        game.commitment_tx,         # 20: commitment_tx
        bet_tx,                     # 21: bet_tx
        nil,                        # 22: settlement_tx
        now,                        # 23: created_at (updated to bet time)
        nil                         # 24: settled_at
      }
      :mnesia.dirty_write(updated_record)

      {:ok, result}

    {:error, reason} ->
      {:error, reason}
  end
end
```

**Complete `get_game/1` (Mnesia dirty_read with pattern match):**
```elixir
def get_game(game_id) do
  case :mnesia.dirty_read({:plinko_games, game_id}) do
    [{:plinko_games, ^game_id, user_id, wallet_address, server_seed, commitment_hash,
      nonce, status, bet_id, token, token_address, bet_amount, config_index, rows,
      risk_level, ball_path, landing_position, payout_bp, payout, won,
      commitment_tx, bet_tx, settlement_tx, created_at, settled_at}] ->
      {:ok, %{
        game_id: game_id, user_id: user_id, wallet_address: wallet_address,
        server_seed: server_seed, commitment_hash: commitment_hash,
        nonce: nonce, status: status, bet_id: bet_id, token: token,
        token_address: token_address, bet_amount: bet_amount,
        config_index: config_index, rows: rows, risk_level: risk_level,
        ball_path: ball_path, landing_position: landing_position,
        payout_bp: payout_bp, payout: payout, won: won,
        commitment_tx: commitment_tx, bet_tx: bet_tx,
        settlement_tx: settlement_tx, created_at: created_at,
        settled_at: settled_at
      }}

    [] ->
      {:error, :not_found}
  end
end
```

**Complete `get_or_init_game/2` (nonce management matching BuxBooster):**
```elixir
def get_or_init_game(user_id, wallet_address) do
  # Calculate next nonce from Mnesia based on placed/settled games
  next_nonce = case :mnesia.dirty_match_object({:plinko_games, :_, user_id, wallet_address, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}) do
    [] -> 0
    games ->
      placed_games = Enum.filter(games, fn game -> elem(game, 7) in [:placed, :settled] end)
      case placed_games do
        [] -> 0
        _ ->
          placed_games
          |> Enum.map(fn game -> elem(game, 6) end)  # nonce at position 6
          |> Enum.max()
          |> Kernel.+(1)
      end
  end

  # Check for reusable committed game with correct nonce
  case get_pending_game(user_id) do
    %{wallet_address: ^wallet_address, commitment_tx: tx, nonce: nonce} = existing
        when tx != nil and nonce == next_nonce ->
      Logger.info("[PlinkoGame] Reusing existing game: #{existing.game_id}")
      {:ok, %{
        game_id: existing.game_id,
        commitment_hash: existing.commitment_hash,
        commitment_tx: existing.commitment_tx,
        nonce: existing.nonce
      }}

    _ ->
      Logger.info("[PlinkoGame] Creating new game with nonce #{next_nonce}")
      init_game_with_nonce(user_id, wallet_address, next_nonce)
  end
end
```

**Complete `init_game_with_nonce/3` (generate seed, submit commitment, write Mnesia):**
```elixir
def init_game_with_nonce(user_id, wallet_address, nonce) do
  # Generate server seed (32 bytes as hex string without 0x prefix)
  server_seed = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)

  # Calculate commitment hash: SHA256 of the hex string (matches BuxBooster pattern)
  commitment_hash_bytes = :crypto.hash(:sha256, server_seed)
  commitment_hash = "0x" <> Base.encode16(commitment_hash_bytes, case: :lower)

  # Generate unique game ID (primary key)
  game_id = generate_game_id()
  now = System.system_time(:second)

  # Submit commitment to contract via BUX Minter
  case BuxMinter.plinko_submit_commitment(commitment_hash, wallet_address, nonce) do
    {:ok, tx_hash} ->
      Logger.info("[PlinkoGame] Commitment submitted - TX: #{tx_hash}, Player: #{wallet_address}, Nonce: #{nonce}")

      # Write :committed game to Mnesia (25-element tuple: table name + 24 fields)
      game_record = {
        :plinko_games,
        game_id,                    # 1: game_id (PK)
        user_id,                    # 2: user_id
        wallet_address,             # 3: wallet_address
        server_seed,                # 4: server_seed
        commitment_hash,            # 5: commitment_hash
        nonce,                      # 6: nonce
        :committed,                 # 7: status
        nil,                        # 8: bet_id
        nil,                        # 9: token
        nil,                        # 10: token_address
        nil,                        # 11: bet_amount
        nil,                        # 12: config_index
        nil,                        # 13: rows
        nil,                        # 14: risk_level
        nil,                        # 15: ball_path
        nil,                        # 16: landing_position
        nil,                        # 17: payout_bp
        nil,                        # 18: payout
        nil,                        # 19: won
        tx_hash,                    # 20: commitment_tx
        nil,                        # 21: bet_tx
        nil,                        # 22: settlement_tx
        now,                        # 23: created_at
        nil                         # 24: settled_at
      }
      :mnesia.dirty_write(game_record)

      {:ok, %{
        game_id: game_id,
        commitment_hash: commitment_hash,
        commitment_tx: tx_hash,
        nonce: nonce
      }}

    {:error, reason} ->
      Logger.error("[PlinkoGame] Failed to submit commitment: #{inspect(reason)}")
      {:error, reason}
  end
end
```

**Complete `get_pending_game/1` (find reusable committed game):**
```elixir
def get_pending_game(user_id) do
  case :mnesia.dirty_index_read(:plinko_games, user_id, :user_id) do
    games when is_list(games) and length(games) > 0 ->
      # Find most recent :committed game (unused commitment)
      pending_game = games
      |> Enum.filter(fn record ->
        status = elem(record, 7)  # status at position 7
        status == :committed
      end)
      |> Enum.sort_by(fn record -> elem(record, 23) end, :desc)  # created_at descending
      |> List.first()

      case pending_game do
        nil -> nil
        record ->
          %{
            game_id: elem(record, 1),
            user_id: elem(record, 2),
            wallet_address: elem(record, 3),
            server_seed: elem(record, 4),
            commitment_hash: elem(record, 5),
            nonce: elem(record, 6),
            status: elem(record, 7),
            commitment_tx: elem(record, 20),
            created_at: elem(record, 23)
          }
      end

    _ ->
      nil
  end
end
```

**Complete `mark_game_settled/3` (write settlement to Mnesia):**
```elixir
def mark_game_settled(game_id, game, tx_hash) do
  now = System.system_time(:second)

  settled_record = {
    :plinko_games,
    game_id,                    # 1: game_id
    game.user_id,               # 2: user_id
    game.wallet_address,        # 3: wallet_address
    game.server_seed,           # 4: server_seed
    game.commitment_hash,       # 5: commitment_hash
    game.nonce,                 # 6: nonce
    :settled,                   # 7: status
    game.bet_id,                # 8: bet_id
    game.token,                 # 9: token
    game.token_address,         # 10: token_address
    game.bet_amount,            # 11: bet_amount
    game.config_index,          # 12: config_index
    game.rows,                  # 13: rows
    game.risk_level,            # 14: risk_level
    game.ball_path,             # 15: ball_path
    game.landing_position,      # 16: landing_position
    game.payout_bp,             # 17: payout_bp
    game.payout,                # 18: payout
    game.won,                   # 19: won
    game.commitment_tx,         # 20: commitment_tx
    game.bet_tx,                # 21: bet_tx
    tx_hash,                    # 22: settlement_tx
    game.created_at,            # 23: created_at
    now                         # 24: settled_at
  }
  :mnesia.dirty_write(settled_record)
end
```

**`update_user_betting_stats/5` (updates shared Mnesia stats table):**
```elixir
defp update_user_betting_stats(user_id, token, bet_amount, won, payout) do
  # Reuse existing EngagementTracker function (same as BuxBooster)
  EngagementTracker.update_user_betting_stats(user_id, %{
    token: token,
    bet_amount: bet_amount,
    won: won,
    payout: payout
  })
end
```

**Optimistic Balance Integration (called from LiveView):**
```elixir
# In PlinkoLive event handler, before calculate + animate:
EngagementTracker.deduct_user_token_balance(user_id, token, bet_amount)

# On bet_failed (JS pushEvent), refund:
EngagementTracker.credit_user_token_balance(user_id, token, bet_amount)
```

**`load_recent_games/2` for game history:**
```elixir
def load_recent_games(user_id, opts \\ []) do
  limit = Keyword.get(opts, :limit, 30)
  offset = Keyword.get(opts, :offset, 0)

  games = :mnesia.dirty_index_read(:plinko_games, user_id, :user_id)
  |> Enum.filter(fn game -> elem(game, 7) == :settled end)
  |> Enum.sort_by(fn game -> elem(game, 23) end, :desc)  # created_at descending
  |> Enum.drop(offset)
  |> Enum.take(limit)
  |> Enum.map(&game_tuple_to_map/1)

  games
end

defp game_tuple_to_map({:plinko_games, game_id, user_id, wallet_address, server_seed,
    commitment_hash, nonce, status, bet_id, token, token_address, bet_amount,
    config_index, rows, risk_level, ball_path, landing_position, payout_bp,
    payout, won, commitment_tx, bet_tx, settlement_tx, created_at, settled_at}) do
  %{
    game_id: game_id, user_id: user_id, wallet_address: wallet_address,
    server_seed: server_seed, commitment_hash: commitment_hash,
    nonce: nonce, status: status, bet_id: bet_id, token: token,
    token_address: token_address, bet_amount: bet_amount,
    config_index: config_index, rows: rows, risk_level: risk_level,
    ball_path: ball_path, landing_position: landing_position,
    payout_bp: payout_bp, payout: payout, won: won,
    commitment_tx: commitment_tx, bet_tx: bet_tx,
    settlement_tx: settlement_tx, created_at: created_at,
    settled_at: settled_at
  }
end
```

### 5.2 PlinkoSettler (`lib/blockster_v2/plinko_settler.ex`)

Identical pattern to `BuxBoosterBetSettler`:
- Global singleton via `GlobalSingleton`
- Checks every 60 seconds for `:placed` games older than 120 seconds
- Calls `PlinkoGame.settle_game/1` for each stuck bet
- Register in `application.ex` alongside `BuxBoosterBetSettler`

```elixir
defmodule BlocksterV2.PlinkoSettler do
  use GenServer
  require Logger

  @check_interval 60_000  # 60 seconds
  @stuck_threshold 120    # seconds

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    Logger.info("[PlinkoSettler] Started")
    schedule_check()
    {:ok, state}
  end

  @impl true
  def handle_info(:check_unsettled_bets, state) do
    check_and_settle_stuck_bets()
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check_unsettled_bets, @check_interval)
  end

  defp check_and_settle_stuck_bets do
    now = System.system_time(:second)
    cutoff = now - @stuck_threshold

    # Find all :placed games
    case :mnesia.dirty_index_read(:plinko_games, :placed, :status) do
      games when is_list(games) ->
        stuck = Enum.filter(games, fn game ->
          elem(game, 7) == :placed and elem(game, 23) < cutoff
        end)

        if length(stuck) > 0 do
          Logger.info("[PlinkoSettler] Found #{length(stuck)} stuck Plinko bets, settling...")
        end

        Enum.each(stuck, fn game ->
          game_id = elem(game, 1)
          Logger.info("[PlinkoSettler] Settling stuck Plinko bet: #{game_id}")
          case BlocksterV2.PlinkoGame.settle_game(game_id) do
            {:ok, _} -> Logger.info("[PlinkoSettler] Successfully settled #{game_id}")
            {:error, reason} -> Logger.warning("[PlinkoSettler] Failed to settle #{game_id}: #{inspect(reason)}")
          end
        end)

      _ -> :ok
    end
  end
end
```

**application.ex addition** (add alongside BuxBoosterBetSettler):
```elixir
# In children list:
{BlocksterV2.GlobalSingleton, {BlocksterV2.PlinkoSettler, []}},
```

### 5.3 BuxMinter Integration

Add Plinko-specific functions to `lib/blockster_v2/bux_minter.ex` (same file, not separate):

```elixir
# ============ Plinko Game API Calls ============

@doc "Submit commitment hash for Plinko game"
def plinko_submit_commitment(commitment_hash, player, nonce) do
  url = "#{bux_minter_url()}/plinko/submit-commitment"
  body = Jason.encode!(%{
    "commitmentHash" => commitment_hash,
    "player" => player,
    "nonce" => nonce
  })

  case Req.post(url,
    body: body,
    headers: [{"content-type", "application/json"}, {"authorization", "Bearer #{bux_minter_secret()}"}],
    receive_timeout: 60_000,
    retry: :transient,
    max_retries: 5
  ) do
    {:ok, %{status: 200, body: %{"success" => true, "txHash" => tx_hash}}} ->
      {:ok, tx_hash}
    {:ok, %{body: body}} ->
      {:error, body["error"] || "Unknown error"}
    {:error, reason} ->
      {:error, inspect(reason)}
  end
end

@doc "Settle Plinko bet on-chain (BUX path)"
def plinko_settle_bet(commitment_hash, server_seed, path, landing_position) do
  url = "#{bux_minter_url()}/plinko/settle-bet"
  body = Jason.encode!(%{
    "commitmentHash" => commitment_hash,
    "serverSeed" => server_seed,
    "path" => Enum.map(path, fn :left -> 0; :right -> 1 end),
    "landingPosition" => landing_position
  })

  case Req.post(url,
    body: body,
    headers: [{"content-type", "application/json"}, {"authorization", "Bearer #{bux_minter_secret()}"}],
    receive_timeout: 60_000,
    retry: :transient,
    max_retries: 5
  ) do
    {:ok, %{status: 200, body: %{"success" => true, "txHash" => tx_hash}}} ->
      {:ok, tx_hash, body["playerBalance"]}
    {:ok, %{body: body}} ->
      {:error, body["error"] || "Unknown error"}
    {:error, reason} ->
      {:error, inspect(reason)}
  end
end

@doc "Settle Plinko ROGUE bet on-chain"
def plinko_settle_bet_rogue(commitment_hash, server_seed, path, landing_position) do
  url = "#{bux_minter_url()}/plinko/settle-bet-rogue"
  body = Jason.encode!(%{
    "commitmentHash" => commitment_hash,
    "serverSeed" => server_seed,
    "path" => Enum.map(path, fn :left -> 0; :right -> 1 end),
    "landingPosition" => landing_position
  })

  case Req.post(url,
    body: body,
    headers: [{"content-type", "application/json"}, {"authorization", "Bearer #{bux_minter_secret()}"}],
    receive_timeout: 60_000,
    retry: :transient,
    max_retries: 5
  ) do
    {:ok, %{status: 200, body: %{"success" => true, "txHash" => tx_hash}}} ->
      {:ok, tx_hash, body["playerBalance"]}
    {:ok, %{body: body}} ->
      {:error, body["error"] || "Unknown error"}
    {:error, reason} ->
      {:error, inspect(reason)}
  end
end

@doc "Get BUX bankroll house info (balance, LP supply, available liquidity)"
def bux_bankroll_house_info do
  url = "#{bux_minter_url()}/bux-bankroll/house-info"

  case Req.get(url,
    headers: [{"authorization", "Bearer #{bux_minter_secret()}"}],
    receive_timeout: 30_000,
    retry: :transient,
    max_retries: 3
  ) do
    {:ok, %{status: 200, body: body}} -> {:ok, body}
    {:ok, %{body: body}} -> {:error, body["error"] || "Unknown error"}
    {:error, reason} -> {:error, inspect(reason)}
  end
end

@doc "Get Plinko max bet for a config (BUX — queries BUXBankroll available liquidity)"
def plinko_get_max_bet(config_index) do
  url = "#{bux_minter_url()}/plinko/max-bet/#{config_index}"

  case Req.get(url,
    headers: [{"authorization", "Bearer #{bux_minter_secret()}"}],
    receive_timeout: 30_000,
    retry: :transient,
    max_retries: 3
  ) do
    {:ok, %{status: 200, body: %{"maxBet" => max_bet}}} -> {:ok, max_bet}
    {:ok, %{body: body}} -> {:error, body["error"] || "Unknown error"}
    {:error, reason} -> {:error, inspect(reason)}
  end
end
```

---

## 6. BUX Minter Service Changes

### New Endpoints

| Method | Endpoint | Body | Purpose |
|--------|----------|------|---------|
| POST | `/plinko/submit-commitment` | `{commitmentHash, player, nonce}` | Submit commitment to PlinkoGame |
| POST | `/plinko/settle-bet` | `{commitmentHash, serverSeed, path, landingPosition}` | Settle Plinko bet |
| GET | `/bux-bankroll/house-info` | -- | BUXBankroll balance, LP supply, available liquidity |
| GET | `/bux-bankroll/lp-price` | -- | Current LP-BUX token price |
| GET | `/plinko/max-bet/:configIndex` | -- | Max bet for config (queries BUXBankroll) |

### Requirements

1. Add `PLINKO_CONTRACT_ADDRESS` and `BUX_BANKROLL_ADDRESS` env vars
2. Add PlinkoGame ABI JSON and BUXBankroll ABI JSON to the service
3. Implement new Express routes pointing to PlinkoGame and BUXBankroll contracts
4. Reuse existing wallet/signing infrastructure, nonce management, gas estimation

### Express Route Implementations

```javascript
// routes/plinko.js
const express = require('express');
const router = express.Router();
const { ethers } = require('ethers');
const PlinkoGameABI = require('../PlinkoGame.json');

const plinkoContract = new ethers.Contract(
  process.env.PLINKO_CONTRACT_ADDRESS,
  PlinkoGameABI,
  wallet  // reuse existing settler wallet
);

// POST /plinko/submit-commitment
router.post('/submit-commitment', async (req, res) => {
  const { commitmentHash, player, nonce } = req.body;
  try {
    const tx = await plinkoContract.submitCommitment(commitmentHash, player, nonce);
    const receipt = await tx.wait();
    res.json({ success: true, txHash: receipt.hash });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /plinko/settle-bet (BUX)
router.post('/settle-bet', async (req, res) => {
  const { commitmentHash, serverSeed, path, landingPosition } = req.body;
  try {
    const tx = await plinkoContract.settleBet(commitmentHash, serverSeed, path, landingPosition);
    const receipt = await tx.wait();
    res.json({ success: true, txHash: receipt.hash });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /plinko/settle-bet-rogue (ROGUE)
router.post('/settle-bet-rogue', async (req, res) => {
  const { commitmentHash, serverSeed, path, landingPosition } = req.body;
  try {
    const tx = await plinkoContract.settleBetROGUE(commitmentHash, serverSeed, path, landingPosition);
    const receipt = await tx.wait();
    res.json({ success: true, txHash: receipt.hash });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /bux-bankroll/house-info — BUXBankroll balance, LP supply, available liquidity
router.get('/bux-bankroll/house-info', async (req, res) => {
  try {
    // getHouseInfo() returns: (totalBalance, liability, unsettledBets, netBalance, poolTokenSupply, poolTokenPrice)
    const [totalBalance, liability, unsettledBets, netBalance, lpSupply, lpPrice] =
      await buxBankrollContract.getHouseInfo();
    res.json({
      totalBalance: totalBalance.toString(),
      liability: liability.toString(),
      unsettledBets: unsettledBets.toString(),
      netBalance: netBalance.toString(),
      lpSupply: lpSupply.toString(),
      lpPrice: lpPrice.toString()
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// GET /plinko/max-bet/:configIndex — Max BUX bet for config (queries PlinkoGame which queries BUXBankroll)
// NOTE: For ROGUE max bet, use GET /plinko/max-bet-rogue/:configIndex (separate endpoint)
router.get('/max-bet/:configIndex', async (req, res) => {
  const configIndex = parseInt(req.params.configIndex);
  try {
    // PlinkoGame.getMaxBet(configIndex) queries BUXBankroll.getMaxBet(configIndex, maxMultiplierBps)
    const maxBet = await plinkoContract.getMaxBet(configIndex);
    res.json({ maxBet: maxBet.toString() });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// GET /plinko/max-bet-rogue/:configIndex — Max ROGUE bet for config (queries ROGUEBankroll)
router.get('/max-bet-rogue/:configIndex', async (req, res) => {
  const configIndex = parseInt(req.params.configIndex);
  try {
    const maxBet = await plinkoContract.getMaxBetROGUE(configIndex);
    res.json({ maxBet: maxBet.toString() });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

module.exports = router;
```

Register in main app:
```javascript
const plinkoRoutes = require('./routes/plinko');
app.use('/plinko', authMiddleware, plinkoRoutes);
```

---

## 7. UI: LiveView & Frontend

### 7.1 PlinkoLive (`lib/blockster_v2_web/live/plinko_live.ex`)

**Route:** `live "/plinko", PlinkoLive, :index`

**Mount (complete, matching BuxBoosterLive pattern):**
```elixir
defmodule BlocksterV2Web.PlinkoLive do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.{PlinkoGame, BuxMinter, EngagementTracker, PriceTracker}
  alias BlocksterV2.HubLogoCache

  @payout_tables PlinkoGame.payout_tables()
  @configs PlinkoGame.configs()

  def mount(_params, _session, socket) do
    current_user = socket.assigns[:current_user]

    if current_user do
      wallet_address = current_user.smart_wallet_address

      # Sync balances on connected mount
      if wallet_address != nil and connected?(socket) do
        BuxMinter.sync_user_balances_async(current_user.id, wallet_address)
      end

      balances = EngagementTracker.get_user_token_balances(current_user.id)

      # Init on-chain game on connected mount only (double-mount protection)
      socket = if wallet_address != nil and connected?(socket) do
        Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "bux_balance:#{current_user.id}")
        Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "plinko_settlement:#{current_user.id}")
        Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "token_prices")

        socket
        |> assign(:onchain_ready, false)
        |> assign(:wallet_address, wallet_address)
        |> assign(:onchain_initializing, true)
        |> assign(:init_retry_count, 0)
        |> start_async(:init_onchain_game, fn ->
          PlinkoGame.get_or_init_game(current_user.id, wallet_address)
        end)
      else
        socket
        |> assign(:onchain_ready, false)
        |> assign(:wallet_address, wallet_address)
        |> assign(:onchain_initializing, false)
        |> assign(:init_retry_count, 0)
      end

      error_msg = if wallet_address, do: nil, else: "No wallet connected"
      default_config = 0  # 8-Low

      socket =
        socket
        |> assign(page_title: "Plinko")
        |> assign(current_user: current_user)
        |> assign(balances: balances)
        # Game config
        |> assign(selected_token: "BUX")
        |> assign(header_token: "BUX")
        |> assign(selected_rows: 8)
        |> assign(selected_risk: :low)
        |> assign(config_index: default_config)
        |> assign(bet_amount: 10)
        |> assign(current_bet: 10)
        |> assign(payout_table: Map.get(@payout_tables, default_config))
        # Game state
        |> assign(game_state: :idle)
        |> assign(ball_path: [])
        |> assign(landing_position: nil)
        |> assign(payout: 0)
        |> assign(payout_multiplier: nil)
        |> assign(won: nil)
        |> assign(confetti_pieces: [])
        |> assign(error_message: error_msg)
        # On-chain state
        |> assign(onchain_game_id: nil)
        |> assign(commitment_hash: nil)
        |> assign(bet_tx: nil)
        |> assign(bet_id: nil)
        |> assign(settlement_tx: nil)
        # House / balance
        |> assign(house_balance: 0.0)
        |> assign(max_bet: 0)
        |> assign(rogue_usd_price: PriceTracker.get_rogue_price())
        # UI state
        |> assign(show_token_dropdown: false)
        |> assign(show_fairness_modal: false)
        |> assign(fairness_game: nil)
        |> assign(recent_games: [])
        |> assign(games_offset: 0)
        |> assign(games_loading: connected?(socket))

      # Async operations on connected mount
      socket = if connected?(socket) do
        user_id = current_user.id
        socket
        |> start_async(:fetch_house_balance, fn ->
          BuxMinter.bux_bankroll_house_info()
        end)
        |> start_async(:load_recent_games, fn ->
          PlinkoGame.load_recent_games(user_id, limit: 30)
        end)
      else
        socket
      end

      {:ok, socket}
    else
      # Not logged in
      {:ok, assign_defaults_for_guest(socket)}
    end
  end

  # ... render, event handlers, async handlers ...
end
```

### 7.2 Socket Assigns

> **Updated**: Added ~15 missing assigns found during review by comparing with BuxBoosterLive.

**Game Config:**
| Assign | Type | Default | Description |
|--------|------|---------|-------------|
| `selected_token` | string | "BUX" | BUX or ROGUE |
| `selected_rows` | integer | 8 | 8, 12, or 16 |
| `selected_risk` | atom | :low | :low, :medium, :high |
| `config_index` | integer | 0 | 0-8 (derived from rows + risk) |
| `bet_amount` | integer | 10 | Current bet |
| `current_bet` | integer | 10 | Bet amount at time of placement (frozen) |
| `payout_table` | list | [] | Current config's multiplier array |

**Game State:**
| Assign | Type | Default | Description |
|--------|------|---------|-------------|
| `game_state` | atom | :idle | :idle, :awaiting_tx, :dropping, :landed, :result |
| `ball_path` | list | [] | [:left, :right, ...] |
| `landing_position` | integer | nil | 0 to rows |
| `payout` | number | 0 | Payout amount |
| `payout_multiplier` | float | nil | e.g., 5.6 |
| `won` | boolean | nil | payout > bet |
| `confetti_pieces` | list | [] | Win confetti data (100 pieces on >= 5x) |
| `error_message` | string | nil | Error display |

**On-Chain State:**
| Assign | Type | Default | Description |
|--------|------|---------|-------------|
| `onchain_ready` | boolean | false | Commitment submitted successfully |
| `onchain_initializing` | boolean | false | Init in progress |
| `init_retry_count` | integer | 0 | Retry counter for init failures |
| `onchain_game_id` | string | nil | Current game ID |
| `commitment_hash` | string | nil | Current commitment |
| `wallet_address` | string | nil | User's smart wallet |
| `bet_tx` | string | nil | Bet placement TX hash |
| `bet_id` | string | nil | On-chain bet ID |
| `settlement_tx` | string | nil | Settlement TX hash |

**Balances & House:**
| Assign | Type | Default | Description |
|--------|------|---------|-------------|
| `balances` | map | %{} | User token balances from EngagementTracker |
| `house_balance` | number | 0 | Available bankroll liquidity (from BUXBankroll or ROGUEBankroll) |
| `max_bet` | number | 0 | Max bet for current config + token |
| `rogue_usd_price` | float | 0.0 | ROGUE USD price from PriceTracker |

**UI State:**
| Assign | Type | Default | Description |
|--------|------|---------|-------------|
| `show_token_dropdown` | boolean | false | Token selector dropdown |
| `show_fairness_modal` | boolean | false | Verification modal open |
| `fairness_game` | map | nil | Game data for fairness modal |
| `recent_games` | list | [] | Last N settled games |
| `games_offset` | integer | 0 | Pagination offset |
| `games_loading` | boolean | false | Loading state for history |
| `header_token` | string | "BUX" | Token shown in header |

**Note**: `game_state` adds `:awaiting_tx` between `:idle` and `:dropping` (not in BuxBooster).
This state is active after bet validation passes but before blockchain confirms. The ball
animation starts in `:dropping` state (optimistic, runs during blockchain wait).

### 7.3 UI Layout

```
+------------------------------------------------------+
|  [ 8 Rows ]  [ 12 Rows ]  [ 16 Rows ]               |
|  [  Low   ]  [ Medium  ]  [  High   ]               |
+------------------------------------------------------+
|                                                        |
|  Game Card (fixed height)                              |
|                                                        |
|  [IDLE STATE]                                          |
|    Bet: [___10___] [/2] [x2]  Token: [BUX v]          |
|    Balance: 1,234 BUX    House: 50,000 BUX             |
|    Max Potential: +55.00 BUX (5.6x edge)               |
|                                                        |
|    +------ Plinko Board (SVG) ------+                  |
|    |          o (ball)              |                  |
|    |         . .                    |                  |
|    |        . . .                   |                  |
|    |       . . . .                  |                  |
|    |      . . . . .                 |                  |
|    |     . . . . . .                |                  |
|    |    . . . . . . .               |                  |
|    |   . . . . . . . .              |                  |
|    |  . . . . . . . . .             |                  |
|    | [5.6] [2.1] [1.1] [1.0] [0.5]  |                  |
|    | [1.0] [1.1] [2.1] [5.6]        |                  |
|    +--------------------------------+                  |
|                                                        |
|    Commitment: 0x1234...abcd                           |
|    [========= DROP BALL =========]                     |
|                                                        |
|  [RESULT STATE]                                        |
|    Landed on position 1 - 2.1x                         |
|    +21.00 BUX PROFIT                                   |
|    [Play Again] [Verify Fairness]                      |
|                                                        |
+------------------------------------------------------+
|  Game History Table (infinite scroll)                  |
|  ID | Bet | Config | Landing | Mult | P/L | Verify   |
+------------------------------------------------------+
```

### 7.4 Config Selector UI

Two-row tab system (cleaner than 9 flat tabs):
- **Top row:** `8 Rows` / `12 Rows` / `16 Rows` buttons
- **Bottom row:** `Low` / `Medium` / `High` buttons
- Selected state highlighted with brand color

When either changes: update `config_index`, recalculate `payout_table`, `max_bet`, re-init on-chain game if needed.

### 7.5 Plinko Board Rendering (SVG)

**Approach:** SVG with viewBox for automatic scaling. Board generated in LiveView render.

**Coordinate System:**
```
viewBox = "0 0 400 {height}"
height:  8 rows = 340,  12 rows = 460,  16 rows = 580
topMargin = 30
bottomMargin = 50
boardHeight = height - topMargin - bottomMargin
rowHeight = boardHeight / rows
pegSpacing = 340 / (rows + 1)

Peg position (row i, col j where j = 0..i):
  numPegsInRow = i + 1
  rowWidth = (numPegsInRow - 1) * pegSpacing
  x = 200 - rowWidth/2 + j * pegSpacing
  y = topMargin + i * rowHeight

Landing slot position (slot k where k = 0..rows):
  numSlots = rows + 1
  slotWidth = 340 / numSlots
  x = 200 - (numSlots-1) * slotWidth/2 + k * slotWidth
  y = height - bottomMargin
```

**Elixir helper functions for SVG generation:**
```elixir
defp board_height(8), do: 340
defp board_height(12), do: 460
defp board_height(16), do: 580

defp peg_radius(8), do: 4
defp peg_radius(12), do: 3
defp peg_radius(16), do: 2.5

defp ball_radius(8), do: 8
defp ball_radius(12), do: 6
defp ball_radius(16), do: 5

defp peg_positions(rows) do
  spacing = 340 / (rows + 1)
  top_margin = 30
  row_height = (board_height(rows) - top_margin - 50) / rows

  for row <- 0..(rows - 1), col <- 0..row do
    num_pegs = row + 1
    row_width = (num_pegs - 1) * spacing
    x = 200 - row_width / 2 + col * spacing
    y = top_margin + row * row_height
    {x, y}
  end
end

defp slot_positions(rows) do
  num_slots = rows + 1
  slot_width = 340 / num_slots
  y = board_height(rows) - 50

  for k <- 0..(rows) do
    x = 200 - (num_slots - 1) * slot_width / 2 + k * slot_width
    {k, x, y}
  end
end

defp slot_color(multiplier_bp) when multiplier_bp >= 100_000, do: "#22c55e"  # >= 10x
defp slot_color(multiplier_bp) when multiplier_bp >= 30_000, do: "#4ade80"   # >= 3x
defp slot_color(multiplier_bp) when multiplier_bp >= 10_000, do: "#eab308"   # >= 1x
defp slot_color(multiplier_bp) when multiplier_bp > 0, do: "#ef4444"         # < 1x
defp slot_color(0), do: "#991b1b"                                            # 0x

defp format_multiplier(0), do: "0x"
defp format_multiplier(bp) when bp >= 10000 do
  x = div(bp, 10000)
  rem_bp = rem(bp, 10000)
  if rem_bp == 0, do: "#{x}x", else: "#{x}.#{div(rem_bp, 1000)}x"
end
defp format_multiplier(bp) do
  "0.#{div(bp, 1000)}x"
end
```

**HEEx template for SVG board** (standalone reference — full render template in Section 7.7):
```heex
<svg
  viewBox={"0 0 400 #{board_height(@selected_rows)}"}
  class="w-full max-w-md mx-auto"
  id="plinko-board"
  phx-hook="PlinkoBall"
  data-game-id={@onchain_game_id}
>
  <!-- Glow filter -->
  <defs>
    <filter id="ball-glow" x="-50%" y="-50%" width="200%" height="200%">
      <feGaussianBlur stdDeviation="3" result="blur" />
      <feMerge>
        <feMergeNode in="blur" />
        <feMergeNode in="SourceGraphic" />
      </feMerge>
    </filter>
  </defs>

  <!-- Pegs -->
  <%= for {x, y} <- peg_positions(@selected_rows) do %>
    <circle class="plinko-peg" cx={x} cy={y} r={peg_radius(@selected_rows)} fill="#6b7280" />
  <% end %>

  <!-- Landing slots -->
  <%= for {k, x, y} <- slot_positions(@selected_rows) do %>
    <% bp = Enum.at(@payout_table, k) %>
    <% slot_w = 340 / (@selected_rows + 1) - 2 %>
    <rect
      class="plinko-slot"
      x={x - slot_w / 2}
      y={y}
      width={slot_w}
      height="30"
      fill={slot_color(bp)}
      rx="4"
    />
    <text
      x={x}
      y={y + 18}
      text-anchor="middle"
      fill="white"
      font-size={if @selected_rows == 16, do: "8", else: "10"}
      font-weight="bold"
    >
      <%= format_multiplier(bp) %>
    </text>
  <% end %>

  <!-- Ball (hidden until drop) -->
  <circle
    id="plinko-ball"
    cx="200"
    cy="10"
    r={ball_radius(@selected_rows)}
    fill="#CAFC00"
    filter="url(#ball-glow)"
    style="display:none"
  />
</svg>
```

**Peg Sizes (responsive):**
- 8 rows: peg r=4, ball r=8
- 12 rows: peg r=3, ball r=6
- 16 rows: peg r=2.5, ball r=5

**Landing Slot Colors:**
- >= 10x: `#22c55e` (bright green)
- >= 3x: `#4ade80` (green)
- >= 1x: `#eab308` (yellow)
- < 1x: `#ef4444` (red)
- 0x: `#991b1b` (dark red)

### 7.6 Event Handlers

**User Events (handle_event):**
| Event | Trigger | Description |
|-------|---------|-------------|
| `select_rows` | Row tab | Change rows, update config, payout table, max bet |
| `select_risk` | Risk tab | Change risk, update config, payout table, max bet |
| `update_bet_amount` | Input (debounce 100ms) | Update bet amount, clamp to max |
| `halve_bet` / `double_bet` / `set_max_bet` | Buttons | Bet shortcuts |
| `select_token` | Dropdown | Switch BUX/ROGUE, re-fetch bankroll balance from respective bankroll contract |
| `toggle_token_dropdown` | Token button | Show/hide dropdown |
| `drop_ball` | "Drop Ball" button | Main action (see flow below) |
| `ball_landed` | JS pushEvent | Animation done, transition to :result |
| `bet_confirmed` | JS pushEvent | Blockchain confirmed, start animation |
| `bet_failed` | JS pushEvent | Refund balance, reset to :idle |
| `reset_game` | "Play Again" | Re-init game, sync balances |
| `show_fairness_modal` | "Verify" link | Open modal (settled games only) |
| `hide_fairness_modal` | Close button | Close modal |
| `load-more-games` | InfiniteScroll | Load next page of history |

**PubSub Messages (handle_info):**
| Message | Source | Handler |
|---------|--------|---------|
| `{:bux_balance_updated, balance}` | BuxBalanceHook | Update balances assign |
| `{:token_balances_updated, balances}` | BuxMinter.sync | Update all token balances |
| `{:plinko_settled, game_id, tx_hash}` | PlinkoGame.settle | Update UI if current game |
| `{:token_prices_updated, prices}` | PriceTracker | Update rogue_usd_price |

**Async Handlers (handle_async):**
| Name | Success | Error |
|------|---------|-------|
| `:init_onchain_game` | Set game_id, commitment, `onchain_ready: true` | Retry 3x with backoff (1s, 2s, 4s), then show error |
| `:fetch_house_balance` | Set house_balance from bankroll, calculate max_bet | Log warning, keep defaults |
| `:load_recent_games` | Set recent_games list | Log warning, keep empty |

**`drop_ball` Flow (the main action):**
```elixir
def handle_event("drop_ball", _params, socket) do
  %{current_user: user, bet_amount: bet_amount, selected_token: token,
    config_index: config_index, onchain_ready: ready, onchain_game_id: game_id} = socket.assigns

  # 1. Validations
  cond do
    not ready -> {:noreply, assign(socket, error_message: "Game not ready")}
    bet_amount <= 0 -> {:noreply, assign(socket, error_message: "Invalid bet")}
    get_balance(socket, token) < bet_amount -> {:noreply, assign(socket, error_message: "Insufficient balance")}
    token == "ROGUE" and bet_amount < 100 -> {:noreply, assign(socket, error_message: "Minimum ROGUE bet: 100")}
    true ->
      # 2. Optimistic balance deduction
      EngagementTracker.deduct_user_token_balance(user.id, token, bet_amount)

      # 3. Calculate result (uses stored server seed)
      # calculate_game_result/5 reads server_seed from Mnesia, delegates to calculate_result/6
      {:ok, result} = PlinkoGame.calculate_game_result(
        game_id, config_index, bet_amount, token, user.id
      )

      # 4. Start animation + push bet to JS
      socket = socket
      |> assign(game_state: :dropping, current_bet: bet_amount)
      |> assign(ball_path: result.ball_path, landing_position: result.landing_position)
      |> assign(payout: result.payout, payout_multiplier: result.payout_bp / 10000)
      |> assign(won: result.won)
      |> push_event("drop_ball", %{
          ball_path: Enum.map(result.ball_path, fn :left -> 0; :right -> 1 end),
          landing_position: result.landing_position,
          rows: socket.assigns.selected_rows
        })
      |> push_event("place_bet_background", %{
          game_id: game_id,
          commitment_hash: socket.assigns.commitment_hash,
          token: token,
          token_address: PlinkoGame.token_address(token),
          amount: bet_amount,
          config_index: config_index
        })

      {:noreply, socket}
  end
end
```

**Complete event handlers (all handle_event callbacks):**

```elixir
# ============ Config Selection ============

def handle_event("select_rows", %{"rows" => rows_str}, socket) do
  rows = String.to_integer(rows_str)
  risk = socket.assigns.selected_risk
  config_index = config_index_for(rows, risk)
  payout_table = Map.get(@payout_tables, config_index)

  {:noreply,
    socket
    |> assign(selected_rows: rows, config_index: config_index, payout_table: payout_table)
    |> maybe_update_max_bet(config_index)}
end

def handle_event("select_risk", %{"risk" => risk_str}, socket) do
  risk = String.to_existing_atom(risk_str)
  rows = socket.assigns.selected_rows
  config_index = config_index_for(rows, risk)
  payout_table = Map.get(@payout_tables, config_index)

  {:noreply,
    socket
    |> assign(selected_risk: risk, config_index: config_index, payout_table: payout_table)
    |> maybe_update_max_bet(config_index)}
end

# ============ Bet Amount Controls ============

def handle_event("update_bet_amount", %{"value" => value_str}, socket) do
  case Integer.parse(value_str) do
    {amount, _} ->
      clamped = amount |> max(0) |> min(socket.assigns.max_bet)
      {:noreply, assign(socket, bet_amount: clamped)}
    :error ->
      {:noreply, socket}
  end
end

def handle_event("halve_bet", _params, socket) do
  new_amount = max(div(socket.assigns.bet_amount, 2), 1)
  {:noreply, assign(socket, bet_amount: new_amount)}
end

def handle_event("double_bet", _params, socket) do
  new_amount = min(socket.assigns.bet_amount * 2, socket.assigns.max_bet)
  {:noreply, assign(socket, bet_amount: new_amount)}
end

def handle_event("set_max_bet", _params, socket) do
  {:noreply, assign(socket, bet_amount: socket.assigns.max_bet)}
end

# ============ Token Selection ============

def handle_event("toggle_token_dropdown", _params, socket) do
  {:noreply, assign(socket, show_token_dropdown: not socket.assigns.show_token_dropdown)}
end

def handle_event("select_token", %{"token" => token}, socket) do
  socket = socket
  |> assign(selected_token: token, header_token: token, show_token_dropdown: false)
  |> start_async(:fetch_house_balance, fn ->
    if token == "ROGUE" do
      BuxMinter.get_house_balance()  # ROGUEBankroll balance
    else
      BuxMinter.bux_bankroll_house_info()  # BUXBankroll balance
    end
  end)

  {:noreply, socket}
end

# ============ Main Action: Drop Ball ============
# (drop_ball handler already defined in Section 7.6 above)

# ============ JS pushEvent Handlers ============

def handle_event("bet_confirmed", %{"game_id" => game_id, "tx_hash" => tx_hash} = params, socket) do
  confirmation_time = Map.get(params, "confirmation_time_ms", 0)
  Logger.info("[PlinkoLive] Bet confirmed for #{game_id} in #{confirmation_time}ms: #{tx_hash}")

  # Update Mnesia with bet details (triggers result calculation)
  {:ok, _result} = PlinkoGame.on_bet_placed(
    game_id,
    socket.assigns.commitment_hash,  # bet_id = commitment_hash
    tx_hash,
    socket.assigns.current_bet,
    socket.assigns.selected_token,
    socket.assigns.config_index
  )

  # Start async settlement (ball is already animating)
  socket = socket
  |> assign(bet_tx: tx_hash, bet_id: socket.assigns.commitment_hash)
  |> start_async(:settle_game, fn ->
    PlinkoGame.settle_game(game_id)
  end)

  {:noreply, socket}
end

def handle_event("bet_failed", %{"game_id" => _game_id, "error" => error}, socket) do
  user = socket.assigns.current_user

  # Refund optimistic balance deduction
  EngagementTracker.credit_user_token_balance(
    user.id, socket.assigns.selected_token, socket.assigns.current_bet
  )

  {:noreply,
    socket
    |> assign(game_state: :idle, error_message: error)
    |> assign(ball_path: [], landing_position: nil)
    |> push_event("reset_ball", %{})}
end

def handle_event("ball_landed", _params, socket) do
  # Animation complete - transition to result state
  confetti = if socket.assigns.payout_multiplier && socket.assigns.payout_multiplier >= 5.0 do
    generate_confetti(100)
  else
    []
  end

  {:noreply, assign(socket, game_state: :result, confetti_pieces: confetti)}
end

# ============ Reset / Play Again ============

def handle_event("reset_game", _params, socket) do
  user = socket.assigns.current_user
  wallet = socket.assigns.wallet_address

  socket = socket
  |> assign(
    game_state: :idle,
    ball_path: [],
    landing_position: nil,
    payout: 0,
    payout_multiplier: nil,
    won: nil,
    confetti_pieces: [],
    error_message: nil,
    onchain_ready: false,
    onchain_initializing: true,
    bet_tx: nil,
    bet_id: nil,
    settlement_tx: nil
  )
  |> push_event("reset_ball", %{})
  |> start_async(:init_onchain_game, fn ->
    PlinkoGame.get_or_init_game(user.id, wallet)
  end)

  {:noreply, socket}
end

# ============ Fairness Modal ============

def handle_event("show_fairness_modal", %{"game_id" => game_id}, socket) do
  case PlinkoGame.get_game(game_id) do
    {:ok, game} when game.status == :settled ->
      {:noreply, assign(socket, show_fairness_modal: true, fairness_game: game)}
    {:ok, _game} ->
      # Don't show server seed for unsettled games (CRITICAL security rule)
      {:noreply, assign(socket, error_message: "Game must be settled to verify fairness")}
    {:error, _} ->
      {:noreply, assign(socket, error_message: "Game not found")}
  end
end

def handle_event("hide_fairness_modal", _params, socket) do
  {:noreply, assign(socket, show_fairness_modal: false, fairness_game: nil)}
end

# ============ Game History ============

def handle_event("load-more-games", _params, socket) do
  user = socket.assigns.current_user
  new_offset = socket.assigns.games_offset + 30

  socket = socket
  |> assign(games_loading: true, games_offset: new_offset)
  |> start_async(:load_more_games, fn ->
    PlinkoGame.load_recent_games(user.id, limit: 30, offset: new_offset)
  end)

  {:noreply, socket}
end
```

**Complete PubSub handlers (handle_info):**

```elixir
# ============ PubSub Messages ============

def handle_info({:bux_balance_updated, balance}, socket) do
  updated_balances = Map.put(socket.assigns.balances, "BUX", balance)
  {:noreply, assign(socket, balances: updated_balances)}
end

def handle_info({:token_balances_updated, balances}, socket) do
  {:noreply, assign(socket, balances: balances)}
end

def handle_info({:plinko_settled, game_id, tx_hash}, socket) do
  if socket.assigns.onchain_game_id == game_id do
    {:noreply, assign(socket, settlement_tx: tx_hash)}
  else
    {:noreply, socket}
  end
end

def handle_info({:token_prices_updated, _prices}, socket) do
  {:noreply, assign(socket, rogue_usd_price: PriceTracker.get_rogue_price())}
end

def handle_info(:retry_init, socket) do
  user = socket.assigns.current_user
  wallet = socket.assigns.wallet_address

  socket = socket
  |> start_async(:init_onchain_game, fn ->
    PlinkoGame.get_or_init_game(user.id, wallet)
  end)

  {:noreply, socket}
end
```

**Complete async handlers (handle_async):**

```elixir
# ============ Async Handlers ============

# init_onchain_game — success
def handle_async(:init_onchain_game, {:ok, {:ok, game_data}}, socket) do
  {:noreply,
    socket
    |> assign(
      onchain_ready: true,
      onchain_initializing: false,
      onchain_game_id: game_data.game_id,
      commitment_hash: game_data.commitment_hash
    )}
end

# init_onchain_game — error returned
def handle_async(:init_onchain_game, {:ok, {:error, reason}}, socket) do
  Logger.error("[PlinkoLive] Init returned error: #{inspect(reason)}")
  handle_init_failure(socket, reason)
end

# init_onchain_game — task crashed
def handle_async(:init_onchain_game, {:exit, reason}, socket) do
  Logger.error("[PlinkoLive] Init task crashed: #{inspect(reason)}")
  handle_init_failure(socket, reason)
end

defp handle_init_failure(socket, reason) do
  retry_count = socket.assigns.init_retry_count
  max_retries = 3

  if retry_count < max_retries do
    delay = :math.pow(2, retry_count) |> round() |> Kernel.*(1000)
    Logger.warning("[PlinkoLive] Init failed (attempt #{retry_count + 1}), retrying in #{delay}ms: #{inspect(reason)}")

    Process.send_after(self(), :retry_init, delay)
    {:noreply, assign(socket, init_retry_count: retry_count + 1)}
  else
    Logger.error("[PlinkoLive] Init failed after #{max_retries} retries")
    {:noreply, assign(socket,
      error_message: "Failed to initialize game. Please refresh.",
      onchain_initializing: false)}
  end
end

# fetch_house_balance — success
def handle_async(:fetch_house_balance, {:ok, {:ok, info}}, socket) do
  # BUXBankroll returns: %{"netBalance" => ..., "totalBalance" => ..., ...}
  # ROGUEBankroll returns: %{"houseBalance" => ...}
  available = cond do
    is_map(info) and Map.has_key?(info, "netBalance") ->
      String.to_integer(info["netBalance"]) / 1.0e18
    is_map(info) and Map.has_key?(info, "houseBalance") ->
      String.to_integer(info["houseBalance"]) / 1.0e18
    true -> 0.0
  end

  max_bet = calculate_max_bet(available, socket.assigns.config_index)

  {:noreply, assign(socket, house_balance: available, max_bet: max_bet)}
end

def handle_async(:fetch_house_balance, {:ok, {:error, reason}}, socket) do
  Logger.warning("[PlinkoLive] Failed to fetch house balance: #{inspect(reason)}")
  {:noreply, socket}
end

def handle_async(:fetch_house_balance, {:exit, reason}, socket) do
  Logger.warning("[PlinkoLive] House balance task crashed: #{inspect(reason)}")
  {:noreply, socket}
end

# load_recent_games — success
def handle_async(:load_recent_games, {:ok, games}, socket) do
  {:noreply, assign(socket, recent_games: games, games_loading: false)}
end

def handle_async(:load_recent_games, _, socket) do
  Logger.warning("[PlinkoLive] Failed to load recent games")
  {:noreply, assign(socket, games_loading: false)}
end

# load_more_games — append to existing
def handle_async(:load_more_games, {:ok, new_games}, socket) do
  {:noreply, assign(socket,
    recent_games: socket.assigns.recent_games ++ new_games,
    games_loading: false)}
end

def handle_async(:load_more_games, _, socket) do
  {:noreply, assign(socket, games_loading: false)}
end

# settle_game — async settlement after bet confirmed
def handle_async(:settle_game, {:ok, {:ok, %{tx_hash: tx_hash}}}, socket) do
  {:noreply, assign(socket, settlement_tx: tx_hash)}
end

def handle_async(:settle_game, {:ok, {:error, reason}}, socket) do
  Logger.error("[PlinkoLive] Settlement failed: #{inspect(reason)}")
  {:noreply, socket}
end

def handle_async(:settle_game, {:exit, reason}, socket) do
  Logger.error("[PlinkoLive] Settlement task crashed: #{inspect(reason)}")
  {:noreply, socket}
end
```

**Helper functions:**

```elixir
# ============ Helpers ============

defp get_balance(socket, "BUX"), do: Map.get(socket.assigns.balances, "BUX", 0)
defp get_balance(socket, "ROGUE"), do: Map.get(socket.assigns.balances, "ROGUE", 0)
defp get_balance(socket, token), do: Map.get(socket.assigns.balances, token, 0)

defp config_index_for(rows, risk) do
  row_offset = case rows do
    8 -> 0
    12 -> 3
    16 -> 6
  end
  risk_offset = case risk do
    :low -> 0
    :medium -> 1
    :high -> 2
  end
  row_offset + risk_offset
end

defp calculate_max_bet(available_liquidity, config_index) do
  # maxBet = (availableLiquidity * MAX_BET_BPS / 10000) * 20000 / maxMultiplierBps
  payout_table = Map.get(@payout_tables, config_index)
  max_mult_bps = Enum.max(payout_table)

  if max_mult_bps > 0 do
    (available_liquidity * 10 / 10000 * 20000 / max_mult_bps)
    |> trunc()
    |> max(0)
  else
    0
  end
end

defp maybe_update_max_bet(socket, config_index) do
  max_bet = calculate_max_bet(socket.assigns.house_balance, config_index)
  bet_amount = min(socket.assigns.bet_amount, max_bet)
  assign(socket, max_bet: max_bet, bet_amount: bet_amount)
end

defp generate_confetti(count) do
  for _i <- 1..count do
    %{
      x: :rand.uniform(100),
      delay: :rand.uniform(2000),
      color: Enum.random(["#CAFC00", "#22c55e", "#eab308", "#ef4444", "#3b82f6", "#a855f7"]),
      size: :rand.uniform(8) + 4
    }
  end
end

# Format helpers (same as BuxBoosterLive)
defp format_balance(amount) when is_number(amount) do
  amount |> trunc() |> Integer.to_string() |> add_commas()
end
defp format_balance(_), do: "0"

defp format_usd(amount, price) when is_number(amount) and is_number(price) do
  usd = amount * price
  "$#{:erlang.float_to_binary(usd, decimals: 2)}"
end
defp format_usd(_, _), do: "$0.00"

defp format_integer(n) when is_integer(n), do: Integer.to_string(n) |> add_commas()
defp format_integer(n) when is_float(n), do: trunc(n) |> format_integer()
defp format_integer(_), do: "0"

defp add_commas(str) when is_binary(str) do
  str
  |> String.reverse()
  |> String.replace(~r/(\d{3})/, "\\1,")
  |> String.reverse()
  |> String.trim_leading(",")
end
```

**`assign_defaults_for_guest/1` (not-logged-in user):**

```elixir
defp assign_defaults_for_guest(socket) do
  balances = %{"BUX" => 0, "ROGUE" => 0, "aggregate" => 0}
  default_config = 0

  # Subscribe to token price updates for unauthenticated users too
  if connected?(socket) do
    Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "token_prices")
  end

  socket
  |> assign(page_title: "Plinko")
  |> assign(current_user: nil)
  |> assign(balances: balances)
  # Game config
  |> assign(selected_token: "BUX")
  |> assign(header_token: "BUX")
  |> assign(selected_rows: 8)
  |> assign(selected_risk: :low)
  |> assign(config_index: default_config)
  |> assign(bet_amount: 10)
  |> assign(current_bet: 10)
  |> assign(payout_table: Map.get(@payout_tables, default_config))
  # Game state
  |> assign(game_state: :idle)
  |> assign(ball_path: [])
  |> assign(landing_position: nil)
  |> assign(payout: 0)
  |> assign(payout_multiplier: nil)
  |> assign(won: nil)
  |> assign(confetti_pieces: [])
  |> assign(error_message: nil)
  # On-chain state
  |> assign(onchain_ready: false)
  |> assign(onchain_initializing: false)
  |> assign(init_retry_count: 0)
  |> assign(onchain_game_id: nil)
  |> assign(commitment_hash: nil)
  |> assign(wallet_address: nil)
  |> assign(bet_tx: nil)
  |> assign(bet_id: nil)
  |> assign(settlement_tx: nil)
  # House / balance
  |> assign(house_balance: 0.0)
  |> assign(max_bet: 0)
  |> assign(rogue_usd_price: PriceTracker.get_rogue_price())
  # UI state
  |> assign(show_token_dropdown: false)
  |> assign(show_fairness_modal: false)
  |> assign(fairness_game: nil)
  |> assign(recent_games: [])
  |> assign(games_offset: 0)
  |> assign(games_loading: false)
  |> start_async(:fetch_house_balance, fn ->
    BuxMinter.bux_bankroll_house_info()
  end)
end
```

### 7.7 Complete Render Template (`render/1`)

```elixir
@impl true
def render(assigns) do
  ~H"""
  <div
    id="plinko-game"
    class="min-h-screen bg-gray-50"
    phx-hook="PlinkoOnchain"
    data-game-id={@onchain_game_id}
    data-commitment-hash={@commitment_hash}
  >
    <div class="max-w-2xl mx-auto px-3 sm:px-4 pt-6 sm:pt-24 pb-8">
      <!-- Config Selector: Rows -->
      <div class="flex justify-center gap-2 mb-2">
        <button
          :for={rows <- [8, 12, 16]}
          phx-click="select_rows"
          phx-value-rows={rows}
          class={"config-tab #{if @selected_rows == rows, do: "active"}"}
        >
          <%= rows %> Rows
        </button>
      </div>

      <!-- Config Selector: Risk -->
      <div class="flex justify-center gap-2 mb-4">
        <button
          :for={{risk, label} <- [{:low, "Low"}, {:medium, "Medium"}, {:high, "High"}]}
          phx-click="select_risk"
          phx-value-risk={risk}
          class={"config-tab #{if @selected_risk == risk, do: "active"}"}
        >
          <%= label %>
        </button>
      </div>

      <!-- Main Game Card -->
      <div class="plinko-game-card">
        <!-- Error Banner -->
        <div :if={@error_message} class="bg-red-900/80 text-red-200 px-4 py-2 text-sm text-center">
          <%= @error_message %>
          <button phx-click="clear_error" class="ml-2 text-red-400 hover:text-red-200 cursor-pointer">x</button>
        </div>

        <!-- Bet Controls (shown in :idle and :result states) -->
        <div :if={@game_state in [:idle, :result]} class="px-4 pt-3 pb-2">
          <div class="flex items-center gap-2 mb-2">
            <!-- Bet Amount Input -->
            <div class="flex items-center bg-zinc-800 rounded-lg px-2 py-1.5 flex-1">
              <span class="text-zinc-500 text-xs mr-1">BET</span>
              <input
                type="number"
                value={@bet_amount}
                phx-change="update_bet_amount"
                phx-debounce="100"
                name="value"
                class="bg-transparent text-white text-sm w-full outline-none [appearance:textfield] [&::-webkit-inner-spin-button]:appearance-none"
                min="1"
                max={@max_bet}
              />
            </div>
            <!-- Halve / Double / Max -->
            <button phx-click="halve_bet" class="bg-zinc-800 text-zinc-400 hover:text-white px-2 py-1.5 rounded-lg text-xs cursor-pointer">/2</button>
            <button phx-click="double_bet" class="bg-zinc-800 text-zinc-400 hover:text-white px-2 py-1.5 rounded-lg text-xs cursor-pointer">x2</button>
            <button phx-click="set_max_bet" class="bg-zinc-800 text-zinc-400 hover:text-white px-2 py-1.5 rounded-lg text-xs cursor-pointer">MAX</button>

            <!-- Token Selector -->
            <div class="relative">
              <button phx-click="toggle_token_dropdown" class="flex items-center bg-zinc-800 rounded-lg px-2 py-1.5 cursor-pointer">
                <span class="text-white text-sm"><%= @selected_token %></span>
                <svg class="w-3 h-3 ml-1 text-zinc-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
                </svg>
              </button>
              <div :if={@show_token_dropdown} class="absolute right-0 mt-1 bg-zinc-800 rounded-lg shadow-xl z-50 min-w-[80px]">
                <button
                  :for={token <- ["BUX", "ROGUE"]}
                  phx-click="select_token"
                  phx-value-token={token}
                  class="block w-full text-left px-3 py-2 text-sm text-white hover:bg-zinc-700 cursor-pointer first:rounded-t-lg last:rounded-b-lg"
                >
                  <%= token %>
                </button>
              </div>
            </div>
          </div>

          <!-- Balance & Max Info -->
          <div class="flex justify-between text-xs text-zinc-500 mb-2">
            <span>Balance: <%= format_balance(get_balance(assigns, @selected_token)) %> <%= @selected_token %></span>
            <span>House: <%= format_balance(@house_balance) %> <%= @selected_token %></span>
          </div>

          <!-- Max Potential Payout -->
          <% max_mult_bp = if @payout_table, do: Enum.max(@payout_table), else: 0 %>
          <% max_payout = @bet_amount * max_mult_bp / 10000 %>
          <div class="text-xs text-zinc-500 mb-2">
            Max Potential: +<%= format_balance(max_payout - @bet_amount) %> <%= @selected_token %>
            (<%= format_multiplier(max_mult_bp) %> edge)
          </div>
        </div>

        <!-- Plinko Board (SVG) -->
        <div class="flex justify-center px-2">
          <svg
            viewBox={"0 0 400 #{board_height(@selected_rows)}"}
            class="w-full max-w-md mx-auto"
            id="plinko-board"
            phx-hook="PlinkoBall"
            data-game-id={@onchain_game_id}
          >
            <defs>
              <filter id="ball-glow" x="-50%" y="-50%" width="200%" height="200%">
                <feGaussianBlur stdDeviation="3" result="blur" />
                <feMerge>
                  <feMergeNode in="blur" />
                  <feMergeNode in="SourceGraphic" />
                </feMerge>
              </filter>
            </defs>

            <!-- Pegs -->
            <%= for {x, y} <- peg_positions(@selected_rows) do %>
              <circle class="plinko-peg" cx={x} cy={y} r={peg_radius(@selected_rows)} fill="#6b7280" />
            <% end %>

            <!-- Landing slots -->
            <%= for {k, x, y} <- slot_positions(@selected_rows) do %>
              <% bp = Enum.at(@payout_table, k) %>
              <% slot_w = 340 / (@selected_rows + 1) - 2 %>
              <rect
                class="plinko-slot"
                x={x - slot_w / 2}
                y={y}
                width={slot_w}
                height="30"
                fill={slot_color(bp)}
                rx="4"
              />
              <text
                x={x}
                y={y + 18}
                text-anchor="middle"
                fill="white"
                font-size={if @selected_rows == 16, do: "8", else: "10"}
                font-weight="bold"
              >
                <%= format_multiplier(bp) %>
              </text>
            <% end %>

            <!-- Ball (hidden until drop) -->
            <circle
              id="plinko-ball"
              cx="200"
              cy="10"
              r={ball_radius(@selected_rows)}
              fill="#CAFC00"
              filter="url(#ball-glow)"
              style="display:none"
            />
          </svg>
        </div>

        <!-- Commitment Display (idle state) -->
        <div :if={@game_state == :idle and @commitment_hash} class="px-4 py-1 text-center">
          <span class="text-[10px] text-zinc-600 font-mono">
            Commitment: <%= String.slice(@commitment_hash, 0..13) %>...<%= String.slice(@commitment_hash, -4..-1) %>
          </span>
        </div>

        <!-- Drop Ball Button (idle state) -->
        <div :if={@game_state == :idle} class="px-4 pb-3">
          <button
            phx-click="drop_ball"
            disabled={not @onchain_ready or @bet_amount <= 0 or @current_user == nil}
            class={[
              "w-full py-3 rounded-xl text-sm font-bold transition-all cursor-pointer",
              if(@onchain_ready and @bet_amount > 0 and @current_user,
                do: "bg-[#CAFC00] text-black hover:bg-[#b8e600] active:scale-[0.98]",
                else: "bg-zinc-700 text-zinc-500 cursor-not-allowed")
            ]}
          >
            <%= cond do %>
              <% @onchain_initializing -> %>Initializing...
              <% not @onchain_ready -> %>Game Not Ready
              <% @current_user == nil -> %>Login to Play
              <% true -> %>DROP BALL
            <% end %>
          </button>
        </div>

        <!-- Dropping State (animation in progress) -->
        <div :if={@game_state == :dropping} class="px-4 pb-3 text-center">
          <div class="text-zinc-400 text-sm animate-pulse">Dropping...</div>
        </div>

        <!-- Result State -->
        <div :if={@game_state == :result} class="px-4 pb-3">
          <!-- Win / Loss Display -->
          <div class="text-center mb-3">
            <div class={"text-2xl font-bold plinko-win-text #{if @won, do: "text-green-400", else: "text-red-400"}"}>
              <%= if @payout_multiplier do %>
                <%= format_multiplier(trunc(@payout_multiplier * 10000)) %>
              <% end %>
            </div>
            <div class={"text-sm #{if @won, do: "text-green-400", else: "text-red-400"}"}>
              <%= cond do %>
                <% @payout > @current_bet -> %>
                  +<%= format_balance(@payout - @current_bet) %> <%= @selected_token %> PROFIT
                <% @payout == @current_bet -> %>
                  PUSH (break even)
                <% @payout == 0 -> %>
                  -<%= format_balance(@current_bet) %> <%= @selected_token %>
                <% true -> %>
                  -<%= format_balance(@current_bet - @payout) %> <%= @selected_token %>
              <% end %>
            </div>
            <div class="text-xs text-zinc-500 mt-1">
              Landed on position <%= @landing_position %>
            </div>
          </div>

          <!-- Action Buttons -->
          <div class="flex gap-2">
            <button
              phx-click="reset_game"
              class="flex-1 py-2.5 rounded-xl bg-[#CAFC00] text-black text-sm font-bold hover:bg-[#b8e600] cursor-pointer"
            >
              Play Again
            </button>
            <button
              :if={@settlement_tx}
              phx-click="show_fairness_modal"
              phx-value-game_id={@onchain_game_id}
              class="px-4 py-2.5 rounded-xl bg-zinc-800 text-zinc-400 text-sm hover:text-white cursor-pointer"
            >
              Verify
            </button>
          </div>

          <!-- Confetti -->
          <div :for={piece <- @confetti_pieces} class="fixed pointer-events-none z-50"
            style={"left: #{piece.x}%; top: -10px; animation: confetti-fall #{1.5 + piece.delay/1000}s linear forwards; animation-delay: #{piece.delay}ms;"}>
            <div style={"width: #{piece.size}px; height: #{piece.size}px; background: #{piece.color}; border-radius: 2px;"}></div>
          </div>
        </div>
      </div>

      <!-- Fairness Modal -->
      <div :if={@show_fairness_modal and @fairness_game} class="fixed inset-0 bg-black/70 z-50 flex items-center justify-center p-4">
        <div class="bg-zinc-900 rounded-2xl max-w-lg w-full max-h-[80vh] overflow-y-auto p-6">
          <div class="flex justify-between items-center mb-4">
            <h3 class="text-white font-bold text-lg">Verify Fairness</h3>
            <button phx-click="hide_fairness_modal" class="text-zinc-500 hover:text-white cursor-pointer">
              <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>

          <div class="space-y-3 text-xs font-mono">
            <div>
              <span class="text-zinc-500">Server Seed:</span>
              <p class="text-white break-all"><%= @fairness_game.server_seed %></p>
            </div>
            <div>
              <span class="text-zinc-500">Commitment (SHA256 of Server Seed):</span>
              <p class="text-white break-all"><%= @fairness_game.commitment_hash %></p>
            </div>
            <div>
              <span class="text-zinc-500">Client Seed:</span>
              <% client_input = "#{@fairness_game.user_id}:#{@fairness_game.bet_amount}:#{@fairness_game.token}:#{@fairness_game.config_index}" %>
              <p class="text-zinc-400">SHA256("<%= client_input %>")</p>
            </div>
            <div>
              <span class="text-zinc-500">Nonce:</span>
              <p class="text-white"><%= @fairness_game.nonce %></p>
            </div>
            <div>
              <span class="text-zinc-500">Ball Path (<%= @fairness_game.rows %> rows):</span>
              <div class="text-white">
                <%= for {dir, i} <- Enum.with_index(@fairness_game.ball_path || []) do %>
                  <div>Row <%= i %>: <%= if dir == :right, do: "RIGHT", else: "LEFT" %></div>
                <% end %>
              </div>
            </div>
            <div>
              <span class="text-zinc-500">Landing Position:</span>
              <p class="text-white"><%= @fairness_game.landing_position %></p>
            </div>
            <div>
              <span class="text-zinc-500">Config:</span>
              <p class="text-white"><%= @fairness_game.rows %>-<%= @fairness_game.risk_level %></p>
            </div>
            <div>
              <span class="text-zinc-500">Payout:</span>
              <p class="text-white"><%= format_multiplier(@fairness_game.payout_bp) %> = <%= format_balance(@fairness_game.payout) %> <%= @fairness_game.token %></p>
            </div>
          </div>

          <div class="mt-4 text-xs text-zinc-500">
            <p>To verify: compute SHA256(server_seed) and confirm it matches the commitment shown before your bet.
            Then compute SHA256("server_seed:client_seed:nonce") and check the first <%= @fairness_game.rows %> bytes.</p>
            <a href="https://emn178.github.io/online-tools/sha256.html" target="_blank" class="text-blue-500 hover:underline mt-1 inline-block">
              External SHA256 Calculator
            </a>
          </div>
        </div>
      </div>

      <!-- Game History Table -->
      <div class="mt-6">
        <h3 class="text-white font-bold text-sm mb-2">Game History</h3>
        <div class="overflow-x-auto">
          <table class="w-full min-w-[600px] text-[10px] sm:text-xs">
            <thead>
              <tr class="text-zinc-500 border-b border-zinc-800">
                <th class="text-left py-2 px-1">ID</th>
                <th class="text-left py-2 px-1">Bet</th>
                <th class="text-left py-2 px-1">Config</th>
                <th class="text-left py-2 px-1">Landing</th>
                <th class="text-left py-2 px-1">Mult</th>
                <th class="text-right py-2 px-1">P/L</th>
                <th class="text-right py-2 px-1">Verify</th>
              </tr>
            </thead>
            <tbody id="game-history" phx-update="append">
              <tr :for={game <- @recent_games} id={"game-#{game.game_id}"} class="border-b border-zinc-800/50">
                <td class="py-1.5 px-1 text-zinc-500 font-mono"><%= String.slice(game.game_id, 0..5) %></td>
                <td class="py-1.5 px-1 text-white"><%= format_balance(game.bet_amount) %> <%= game.token %></td>
                <td class="py-1.5 px-1 text-zinc-400"><%= game.rows %>-<%= game.risk_level %></td>
                <td class="py-1.5 px-1 text-zinc-400"><%= game.landing_position %></td>
                <td class="py-1.5 px-1 text-zinc-400"><%= format_multiplier(game.payout_bp) %></td>
                <td class={"py-1.5 px-1 text-right #{if game.won, do: "text-green-400", else: "text-red-400"}"}>
                  <%= if game.won do %>+<%= format_balance(game.payout - game.bet_amount) %><% else %>-<%= format_balance(game.bet_amount - game.payout) %><% end %>
                </td>
                <td class="py-1.5 px-1 text-right">
                  <button
                    phx-click="show_fairness_modal"
                    phx-value-game_id={game.game_id}
                    class="text-blue-500 hover:underline cursor-pointer"
                  >
                    Verify
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div :if={@games_loading} class="text-center py-4">
          <span class="text-zinc-500 text-xs animate-pulse">Loading...</span>
        </div>

        <!-- Infinite scroll trigger -->
        <div
          :if={length(@recent_games) > 0 and rem(length(@recent_games), 30) == 0}
          id="infinite-scroll-games"
          phx-hook="InfiniteScroll"
          phx-click="load-more-games"
          class="h-4"
        />
      </div>
    </div>
  </div>
  """
end
```

### 7.8 CSS & Animations (`assets/css/app.css` additions)

> **Note**: Confetti keyframe animation (for wins >= 5x) — add to `app.css`:
```css
@keyframes confetti-fall {
  0% { transform: translateY(0) rotate(0deg); opacity: 1; }
  100% { transform: translateY(100vh) rotate(720deg); opacity: 0; }
}
```

```css
/* Plinko Board */
.plinko-board {
  @apply w-full max-w-md mx-auto;
}

.plinko-peg {
  fill: #6b7280;
  transition: fill 0.2s, r 0.2s;
}

.plinko-peg.flash {
  fill: #ffffff;
}

/* Ball */
#plinko-ball {
  filter: drop-shadow(0 0 6px #CAFC00) drop-shadow(0 0 12px rgba(202, 252, 0, 0.4));
}

.plinko-trail {
  transition: opacity 0.5s ease-out;
}

/* Landing Slots */
.plinko-slot {
  transition: transform 0.3s, filter 0.3s;
}

.plinko-slot-hit {
  animation: slot-pulse 0.5s ease-in-out 3;
  filter: brightness(1.5);
}

@keyframes slot-pulse {
  0%, 100% { transform: scaleY(1); }
  50% { transform: scaleY(1.15); }
}

/* Slot colors by multiplier (applied via Tailwind classes in template) */
.slot-extreme { fill: #22c55e; }   /* >= 10x: bright green */
.slot-high    { fill: #4ade80; }   /* >= 3x: green */
.slot-even    { fill: #eab308; }   /* >= 1x: yellow */
.slot-low     { fill: #ef4444; }   /* < 1x: red */
.slot-zero    { fill: #991b1b; }   /* 0x: dark red */

/* Config selector tabs */
.config-tab {
  @apply px-4 py-2 rounded-lg text-sm font-medium cursor-pointer
         transition-colors duration-200;
}
.config-tab.active {
  @apply bg-[#CAFC00] text-black;
}
.config-tab:not(.active) {
  @apply bg-zinc-800 text-zinc-400 hover:bg-zinc-700;
}

/* Game card (taller than BuxBooster to fit board) */
.plinko-game-card {
  @apply relative bg-zinc-900 rounded-2xl overflow-hidden;
  height: 520px;
}
@media (min-width: 640px) {
  .plinko-game-card { height: 580px; }
}

/* Win celebration - reuse BuxBooster confetti */
.plinko-win-text {
  animation: scale-in 0.5s ease-out;
}

@keyframes scale-in {
  0% { transform: scale(0.5); opacity: 0; }
  80% { transform: scale(1.1); }
  100% { transform: scale(1); opacity: 1; }
}
```

### 7.9 Mobile Responsiveness

- SVG board scales automatically via viewBox
- Config selectors: buttons wrap naturally with flexbox
- Landing slot text: `text-[8px] sm:text-xs` for multiplier labels
- Game card: `h-[520px] sm:h-[580px]` (taller than BuxBooster to fit board)
- History table: horizontal scroll with `min-w-[600px]`, `text-[10px] sm:text-xs`
- Peg sizes (responsive per config):
  - 8 rows: peg r=4, ball r=8
  - 12 rows: peg r=3, ball r=6
  - 16 rows: peg r=2.5, ball r=5

---

## 8. JavaScript Hooks

### 8.1 PlinkoBall (`assets/js/plinko_ball.js`)

Controls ball drop animation. Complete implementation:

```javascript
export const PlinkoBall = {
  mounted() {
    this.ball = this.el.querySelector('#plinko-ball');
    this.pegs = this.el.querySelectorAll('.plinko-peg');
    this.slots = this.el.querySelectorAll('.plinko-slot');
    this.trails = [];

    this.handleEvent("drop_ball", ({ ball_path, landing_position, rows }) => {
      this.animateDrop(ball_path, landing_position, rows);
    });
    this.handleEvent("reset_ball", () => this.resetBall());
  },

  updated() {
    // Re-cache elements after LiveView re-renders
    this.ball = this.el.querySelector('#plinko-ball');
    this.pegs = this.el.querySelectorAll('.plinko-peg');
    this.slots = this.el.querySelectorAll('.plinko-slot');
  },

  // ============ SVG Coordinate System ============
  // ViewBox: 0 0 400 {height} where height depends on rows
  // Board is centered at x=200, pegs arranged in triangle
  //
  // Row i has (i + 1) pegs spaced evenly.
  // For N rows total: peg spacing = 400 / (N + 2)
  // Row i: first peg at x = 200 - (i * spacing / 2), y = topMargin + i * rowHeight
  // Landing slots: N+1 slots at bottom

  getLayout(rows) {
    const viewHeight = rows === 8 ? 340 : rows === 12 ? 460 : 580;
    const topMargin = 30;
    const bottomMargin = 50;
    const boardHeight = viewHeight - topMargin - bottomMargin;
    const rowHeight = boardHeight / rows;
    const spacing = 340 / (rows + 1);  // horizontal spacing between pegs

    return { viewHeight, topMargin, rowHeight, spacing };
  },

  getPegPosition(row, col, rows) {
    const { topMargin, rowHeight, spacing } = this.getLayout(rows);
    const numPegsInRow = row + 1;
    const rowWidth = (numPegsInRow - 1) * spacing;
    const startX = 200 - rowWidth / 2;

    return {
      x: startX + col * spacing,
      y: topMargin + row * rowHeight
    };
  },

  getBallPositionAfterBounce(row, pathSoFar, rows) {
    // After bouncing at row i, ball is between row i and row i+1
    // Position = count of rights so far determines column
    const rightCount = pathSoFar.filter(d => d === 1).length;
    const { topMargin, rowHeight, spacing } = this.getLayout(rows);

    // Ball sits between pegs of the NEXT row
    const nextRow = row + 1;
    if (nextRow >= rows) {
      // Landing zone
      return this.getSlotPosition(rightCount, rows);
    }

    const numPegsNext = nextRow + 1;
    const rowWidthNext = (numPegsNext - 1) * spacing;
    const startXNext = 200 - rowWidthNext / 2;

    return {
      x: startXNext + rightCount * spacing,
      y: topMargin + row * rowHeight + rowHeight / 2
    };
  },

  getSlotPosition(index, rows) {
    const { viewHeight, spacing } = this.getLayout(rows);
    const numSlots = rows + 1;
    const slotWidth = 340 / numSlots;
    const startX = 200 - (numSlots - 1) * slotWidth / 2;

    return {
      x: startX + index * slotWidth,
      y: viewHeight - 25  // slot center
    };
  },

  // ============ Animation ============

  async animateDrop(ballPath, landingPosition, rows) {
    this.clearTrails();
    this.ball.style.display = 'block';
    this.ball.setAttribute('cx', '200');
    this.ball.setAttribute('cy', '10');

    const timings = this.calculateTimings(rows);

    for (let i = 0; i < ballPath.length; i++) {
      const pathSoFar = ballPath.slice(0, i + 1);
      await this.animateToRow(i, ballPath[i], pathSoFar, rows, timings[i]);
    }

    await this.animateLanding(landingPosition, rows, 800);
    this.pushEvent("ball_landed", {});
  },

  animateToRow(rowIndex, direction, pathSoFar, rows, duration) {
    return new Promise(resolve => {
      const startX = parseFloat(this.ball.getAttribute('cx'));
      const startY = parseFloat(this.ball.getAttribute('cy'));
      const target = this.getBallPositionAfterBounce(rowIndex, pathSoFar, rows);
      const startTime = performance.now();

      // Add trail at current position
      this.addTrail(startX, startY);

      // Flash the peg we're bouncing off
      this.flashPeg(rowIndex, pathSoFar, rows);

      const animate = (now) => {
        const elapsed = now - startTime;
        const progress = Math.min(elapsed / duration, 1);
        // Ease-out cubic for natural deceleration
        const eased = 1 - Math.pow(1 - progress, 3);

        const currentX = startX + (target.x - startX) * eased;
        const currentY = startY + (target.y - startY) * eased;

        this.ball.setAttribute('cx', currentX);
        this.ball.setAttribute('cy', currentY);

        if (progress < 1) {
          requestAnimationFrame(animate);
        } else {
          resolve();
        }
      };

      requestAnimationFrame(animate);
    });
  },

  animateLanding(landingPosition, rows, duration) {
    return new Promise(resolve => {
      const startX = parseFloat(this.ball.getAttribute('cx'));
      const startY = parseFloat(this.ball.getAttribute('cy'));
      const target = this.getSlotPosition(landingPosition, rows);
      const startTime = performance.now();

      const animate = (now) => {
        const elapsed = now - startTime;
        const progress = Math.min(elapsed / duration, 1);
        // Bounce ease for landing
        const eased = 1 - Math.pow(1 - progress, 2);

        this.ball.setAttribute('cx', startX + (target.x - startX) * eased);
        this.ball.setAttribute('cy', startY + (target.y - startY) * eased);

        if (progress < 1) {
          requestAnimationFrame(animate);
        } else {
          // Highlight landing slot
          this.highlightSlot(landingPosition);
          resolve();
        }
      };

      requestAnimationFrame(animate);
    });
  },

  calculateTimings(rows) {
    const totalMs = 6000;
    const ratio = 2.5;
    const minTime = 2 * (totalMs / rows) / (1 + ratio);
    return Array.from({length: rows}, (_, i) =>
      minTime + (minTime * ratio - minTime) * (i / (rows - 1))
    );
  },

  // ============ Visual Effects ============

  addTrail(x, y) {
    const trail = document.createElementNS("http://www.w3.org/2000/svg", "circle");
    trail.setAttribute('cx', x);
    trail.setAttribute('cy', y);
    trail.setAttribute('r', '3');
    trail.setAttribute('fill', '#CAFC00');
    trail.setAttribute('opacity', '0.4');
    trail.classList.add('plinko-trail');
    this.el.appendChild(trail);
    this.trails.push(trail);

    // Fade out trail
    setTimeout(() => {
      trail.setAttribute('opacity', '0.15');
    }, 300);
  },

  flashPeg(rowIndex, pathSoFar, rows) {
    // Find the peg that was hit based on row and column
    const rightsBefore = pathSoFar.slice(0, -1).filter(d => d === 1).length;
    const col = rightsBefore;  // column in the current row
    const pegIndex = this.getPegIndex(rowIndex, col, rows);

    if (this.pegs[pegIndex]) {
      const peg = this.pegs[pegIndex];
      const origFill = peg.getAttribute('fill');
      peg.setAttribute('fill', '#ffffff');
      peg.setAttribute('r', parseFloat(peg.getAttribute('r')) * 1.5);
      setTimeout(() => {
        peg.setAttribute('fill', origFill);
        peg.setAttribute('r', parseFloat(peg.getAttribute('r')) / 1.5);
      }, 200);
    }
  },

  getPegIndex(row, col, rows) {
    // Pegs are rendered sequentially in the SVG: row 0 has 1 peg, row 1 has 2, etc.
    // Row i has (i + 1) pegs — MUST match Elixir peg_positions() which uses the same formula.
    // Index into the flat peg NodeList by summing previous rows' peg counts.
    let index = 0;
    for (let r = 0; r < row; r++) {
      index += (r + 1);  // pegs per row = row + 1
    }
    return index + col;
  },

  highlightSlot(position) {
    if (this.slots[position]) {
      this.slots[position].classList.add('plinko-slot-hit');
    }
  },

  clearTrails() {
    this.trails.forEach(t => t.remove());
    this.trails = [];
    this.el.querySelectorAll('.plinko-slot-hit').forEach(s => {
      s.classList.remove('plinko-slot-hit');
    });
  },

  resetBall() {
    if (this.ball) {
      this.ball.style.display = 'none';
      this.ball.setAttribute('cx', '200');
      this.ball.setAttribute('cy', '10');
    }
    this.clearTrails();
  }
};
```

**Timing per config (6 second total):**
- 8 rows: ~430ms to ~1070ms per row
- 12 rows: ~286ms to ~714ms per row
- 16 rows: ~214ms to ~536ms per row

### 8.2 PlinkoOnchain (`assets/js/plinko_onchain.js`)

Same pattern as `bux_booster_onchain.js`. Complete implementation:

```javascript
import { getContract, prepareContractCall, sendTransaction, readContract } from "thirdweb";
import { approve } from "thirdweb/extensions/erc20";
import PlinkoGameABI from "./PlinkoGame.json";

const PLINKO_CONTRACT_ADDRESS = "0x<DEPLOYED>";       // Set after deployment
const BUX_BANKROLL_ADDRESS = "0x<BUX_BANKROLL>";      // Set after deployment — BUX approval target
const BUX_TOKEN_ADDRESS = "0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8";
const APPROVAL_CACHE_KEY = "plinko_approved_";

// ============================================================
// IMPORTANT: Error selector hex values marked "0x..." below are PLACEHOLDERS.
// They MUST be computed from the compiled PlinkoGame ABI before deployment.
// How to compute: ethers.id("ErrorName()").slice(0,10)
// Example: ethers.id("BetAlreadySettled()").slice(0,10) => "0x05d09e5f"
// Run this script after Hardhat compile to generate all selectors:
//   const iface = new ethers.Interface(PlinkoGameABI);
//   iface.forEachError((error) => console.log(error.name, error.selector));
// DO NOT deploy with placeholder values — transactions will fail silently.
// ============================================================
const ERROR_MESSAGES = {
  "0x05d09e5f": "Bet already settled",           // BetAlreadySettled()
  "0xd0d04f60": "Token not enabled for betting",  // TokenNotEnabled()
  "0x3a51740d": "Bet amount too low (minimum 1 token)", // BetAmountTooLow()
  "0x3f45a891": "Bet exceeds maximum allowed",    // BetAmountTooHigh()
  // PLACEHOLDERS — compute after compile:
  "0x...": "Invalid game configuration",          // InvalidConfigIndex()
  "0x...": "House balance insufficient for this bet", // InsufficientHouseBalance()
  "0x...": "Game commitment not found",           // CommitmentNotFound()
  "0x...": "Game commitment already used",        // CommitmentAlreadyUsed()
  "0x...": "Commitment belongs to different player", // CommitmentWrongPlayer()
  "0x...": "Payout table not configured",         // PayoutTableNotSet()
};

export const PlinkoOnchain = {
  mounted() {
    this.gameId = this.el.dataset.gameId;
    this.commitmentHash = this.el.dataset.commitmentHash;

    this.handleEvent("place_bet_background", (data) => {
      this.placeBet(data);
    });
  },

  updated() {
    this.gameId = this.el.dataset.gameId;
    this.commitmentHash = this.el.dataset.commitmentHash;
  },

  async placeBet({ game_id, commitment_hash, token, token_address, amount, config_index }) {
    try {
      if (!window.smartAccount) {
        this.pushEvent("bet_failed", { game_id, error: "Wallet not connected" });
        return;
      }

      const startTime = Date.now();
      const amountWei = BigInt(amount) * BigInt(10 ** 18);

      const plinkoContract = getContract({
        client: window.thirdwebClient,
        chain: window.rogueChain,
        address: PLINKO_CONTRACT_ADDRESS,
        abi: PlinkoGameABI,
      });

      let tx;
      if (token === "ROGUE") {
        // Native token bet
        tx = prepareContractCall({
          contract: plinkoContract,
          method: "placeBetROGUE",
          params: [amountWei, config_index, commitment_hash],
          value: amountWei,
        });
      } else {
        // ERC-20 bet - check approval first
        await this.ensureApproval(token_address, amountWei);

        tx = prepareContractCall({
          contract: plinkoContract,
          method: "placeBet",
          params: [token_address, amountWei, config_index, commitment_hash],
        });
      }

      const receipt = await sendTransaction({
        transaction: tx,
        account: window.smartAccount,
      });

      const confirmationTime = Date.now() - startTime;
      console.log(`[PlinkoOnchain] Bet confirmed in ${confirmationTime}ms: ${receipt.transactionHash}`);

      this.pushEvent("bet_confirmed", {
        game_id,
        tx_hash: receipt.transactionHash,
        confirmation_time_ms: confirmationTime,
      });

    } catch (error) {
      console.error("[PlinkoOnchain] Bet failed:", error);
      const errorMsg = this.parseError(error);
      this.pushEvent("bet_failed", { game_id, error: errorMsg });
    }
  },

  async ensureApproval(tokenAddress, amount) {
    const cacheKey = APPROVAL_CACHE_KEY + tokenAddress;

    // Check localStorage cache first
    if (localStorage.getItem(cacheKey) === "true") {
      return;
    }

    // Check on-chain allowance
    // NOTE: BUX approval is for BUX_BANKROLL_ADDRESS (not PlinkoGame).
    // placeBet calls safeTransferFrom(player -> BUXBankroll), so BUXBankroll needs the allowance.
    const tokenContract = getContract({
      client: window.thirdwebClient,
      chain: window.rogueChain,
      address: tokenAddress,
    });

    const allowance = await readContract({
      contract: tokenContract,
      method: "function allowance(address owner, address spender) view returns (uint256)",
      params: [window.smartAccount.address, BUX_BANKROLL_ADDRESS],
    });

    if (BigInt(allowance) < amount) {
      console.log("[PlinkoOnchain] Approving BUX for BUXBankroll...");
      const approveTx = approve({
        contract: tokenContract,
        spender: BUX_BANKROLL_ADDRESS,
        amountWei: BigInt("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"),
      });

      await sendTransaction({
        transaction: approveTx,
        account: window.smartAccount,
      });

      localStorage.setItem(cacheKey, "true");
      console.log("[PlinkoOnchain] Token approved (infinite)");
    } else {
      localStorage.setItem(cacheKey, "true");
    }
  },

  parseError(error) {
    const errorStr = error?.message || error?.toString() || "Unknown error";

    // Check for known contract error signatures
    for (const [sig, msg] of Object.entries(ERROR_MESSAGES)) {
      if (errorStr.includes(sig)) return msg;
    }

    // User rejection
    if (errorStr.includes("rejected") || errorStr.includes("denied")) {
      return "Transaction cancelled";
    }

    // Gas / bundler errors
    if (errorStr.includes("insufficient funds")) {
      return "Insufficient gas funds";
    }

    return `Transaction failed: ${errorStr.slice(0, 100)}`;
  },
};
```

### 8.3 Hook Registration (`assets/js/app.js`)

Add to hooks object:
```javascript
import { PlinkoBall } from "./plinko_ball";
import { PlinkoOnchain } from "./plinko_onchain";

let hooks = {
  // ...existing hooks...
  PlinkoBall,
  PlinkoOnchain,
};
```

---

## 9. Database: Mnesia Tables

### 9.1 New Table: `:plinko_games`

Add to `@tables` in `lib/blockster_v2/mnesia_initializer.ex`.

> **Tuple structure**: Position 0 = table name atom, positions 1-24 = 24 data fields.
> Total tuple size = 25 elements. Matches BuxBooster's pattern (which has 22 elements = table name + 21 fields).

**Schema (24 data fields + table name = 25 tuple positions):**

| Pos | Field | Type | Description |
|-----|-------|------|-------------|
| 0 | (table name) | atom | `:plinko_games` |
| 1 | `game_id` | string | 32-char hex, PRIMARY KEY |
| 2 | `user_id` | integer | PostgreSQL user ID |
| 3 | `wallet_address` | string | Smart wallet address |
| 4 | `server_seed` | string | 64-char hex (revealed after settlement) |
| 5 | `commitment_hash` | string | 0x-prefixed SHA256 |
| 6 | `nonce` | integer | Player's game counter |
| 7 | `status` | atom | `:committed`, `:placed`, `:settled`, `:expired` |
| 8 | `bet_id` | string | On-chain bet ID (commitment hash) |
| 9 | `token` | string | "BUX" or "ROGUE" |
| 10 | `token_address` | string | Token contract address |
| 11 | `bet_amount` | integer | Amount wagered |
| 12 | `config_index` | integer | 0-8 |
| 13 | `rows` | integer | 8, 12, or 16 |
| 14 | `risk_level` | atom | :low, :medium, :high |
| 15 | `ball_path` | list | [:left, :right, ...] |
| 16 | `landing_position` | integer | 0 to rows |
| 17 | `payout_bp` | integer | Payout multiplier in basis points |
| 18 | `payout` | number | Actual payout amount |
| 19 | `won` | boolean | Net profit (payout > bet) |
| 20 | `commitment_tx` | string | TX hash for submitCommitment |
| 21 | `bet_tx` | string | TX hash for placeBet |
| 22 | `settlement_tx` | string | TX hash for settleBet |
| 23 | `created_at` | integer | Unix timestamp |
| 24 | `settled_at` | integer | Unix timestamp (nil until settled) |

- **Type:** `:ordered_set`
- **Indexes:** `[:user_id, :wallet_address, :status, :created_at]`

**MnesiaInitializer entry (exact code to add to `@tables`):**
```elixir
%{
  name: :plinko_games,
  type: :ordered_set,
  attributes: [
    :game_id,            # PRIMARY KEY - 32-char hex
    :user_id,            # PostgreSQL user ID
    :wallet_address,     # Smart wallet address
    :server_seed,        # 64-char hex (revealed after settlement)
    :commitment_hash,    # 0x-prefixed SHA256
    :nonce,              # Player's game counter
    :status,             # :committed | :placed | :settled | :expired
    :bet_id,             # On-chain bet ID (commitment hash)
    :token,              # "BUX" or "ROGUE"
    :token_address,      # Token contract address
    :bet_amount,         # Amount wagered (integer tokens)
    :config_index,       # 0-8
    :rows,               # 8, 12, or 16
    :risk_level,         # :low, :medium, :high
    :ball_path,          # [:left, :right, ...] list
    :landing_position,   # 0 to rows (integer)
    :payout_bp,          # Payout multiplier in basis points
    :payout,             # Actual payout amount
    :won,                # Boolean (payout > bet)
    :commitment_tx,      # TX hash for submitCommitment
    :bet_tx,             # TX hash for placeBet
    :settlement_tx,      # TX hash for settleBet
    :created_at,         # Unix timestamp (updated to bet placement time)
    :settled_at          # Unix timestamp (nil until settled)
  ],
  index: [:user_id, :wallet_address, :status, :created_at]
},
```

**`dirty_match_object` wildcard pattern (25 elements):**
```elixir
# For get_or_init_game nonce calculation:
:mnesia.dirty_match_object({:plinko_games, :_, user_id, wallet_address,
  :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_,
  :_, :_, :_, :_, :_})
```

### 9.2 Stats Tables

**Reuse `:user_betting_stats`** -- the existing table tracks BUX and ROGUE totals generically. Plinko settlements call the same `update_user_betting_stats/5` function. Admin dashboard shows combined stats across all games.

### 9.3 State Transitions

```
[init_game_with_nonce] --> :committed  (server seed generated, commitment on-chain)
[on_bet_placed]        --> :placed     (bet details, ball path, landing calculated)
[settle_game]          --> :settled    (settlement TX, stats updated)
```

---

## 10. Admin & Stats

### Extend Existing Admin Pages

Since `:user_betting_stats` is shared, `/admin/stats/players` automatically includes Plinko wagers.

**Add to `/admin/stats`:**
- New "Plinko" section with stats from PlinkoGame contract (`getBuxAccounting()`) and ROGUEBankroll (`getPlinkoAccounting()`)
- Per-config breakdown (most popular configs, highest payouts)

**Player Detail (`/admin/stats/players/:address`):**
- Add Plinko per-config stats from contracts (`getBuxPlayerStats()`, `getPlinkoPlayerStats()`)

---

## 11. Provably Fair System

### Identical to BUX Booster, Adapted for Plinko

1. **Server seed:** `crypto.strong_rand_bytes(32)` -> 64-char hex
2. **Commitment:** `SHA256(server_seed)` as 0x-prefixed hex, submitted on-chain BEFORE bet
3. **Client seed:** `SHA256("#{user_id}:#{bet_amount}:#{token}:#{config_index}")` (no predictions)
4. **Combined seed:** `SHA256("#{server_seed}:#{client_seed}:#{nonce}")`
5. **Ball path:** First N bytes of combined seed: `byte < 128 = left, byte >= 128 = right`
6. **Landing position:** Count of right bounces (0 to N)
7. **Payout:** Lookup from payout table

### Verification Modal Content

```
Server Seed: a1b2c3d4... (64 chars, revealed after settlement)
Commitment:  0x7f8e... = SHA256(server_seed) (shown before bet)
Client Seed: SHA256("42:100:BUX:2") = e5f6...
Combined:    SHA256("a1b2...:e5f6...:7") = 4af21b...
Nonce:       7

Ball Path (8 rows):
  Row 0: byte 0x4a = 74  < 128 -> LEFT
  Row 1: byte 0xf2 = 242 >= 128 -> RIGHT
  Row 2: byte 0x1b = 27  < 128 -> LEFT
  Row 3: byte 0x83 = 131 >= 128 -> RIGHT
  Row 4: byte 0x0f = 15  < 128 -> LEFT
  Row 5: byte 0xa7 = 167 >= 128 -> RIGHT
  Row 6: byte 0x55 = 85  < 128 -> LEFT
  Row 7: byte 0xc1 = 193 >= 128 -> RIGHT

Landing Position: 3 (3 right bounces)
Config: 8-High
Payout Table[3]: 3000 bp = 0.3x
```

### Trust Model

Same as BuxBoosterGame V3+: contract does NOT verify `SHA256(serverSeed) == commitmentHash` on-chain. Server is trusted. Seeds stored on-chain for transparency.

---

## 12. Animation & Timing

### Critical Constraint

Account Abstraction transaction confirmation takes ~3 seconds. The ball animation runs DURING the blockchain wait (optimistic UI). Total animation must be 5-7 seconds.

### Timing Per Config (6 second total)

**8 Rows:**
| Row | Time (ms) | Cumulative |
|-----|-----------|------------|
| 0 | 429 | 429 |
| 1 | 520 | 949 |
| 2 | 612 | 1,561 |
| 3 | 704 | 2,265 |
| 4 | 796 | 3,061 |
| 5 | 888 | 3,949 |
| 6 | 980 | 4,929 |
| 7 | 1,071 | 6,000 |
+ landing animation: 800ms = **6.8s total**

**12 Rows:**
| Row | Time (ms) | Cumulative |
|-----|-----------|------------|
| 0 | 286 | 286 |
| 1-5 | 325-481 | 2,301 |
| 6-11 | 519-714 | 6,000 |
+ landing: 800ms = **6.8s total**

**16 Rows:**
| Row | Time (ms) | Cumulative |
|-----|-----------|------------|
| 0 | 214 | 214 |
| 1-7 | 236-364 | 2,314 |
| 8-15 | 386-536 | 6,000 |
+ landing: 800ms = **6.8s total**

### Deceleration Formula

```
minTime = 2 * (totalMs / rows) / (1 + 2.5)
maxTime = 2.5 * minTime
rowTime(i) = minTime + (maxTime - minTime) * (i / (rows - 1))
```

### Visual Effects

- **Ball:** `#CAFC00` (brand lime) with white glow shadow
- **Peg flash:** Brief white pulse when ball bounces off peg
- **Trail:** Fading opacity circles at previous positions
- **Landing slot:** Pulse animation + color intensification on arrival
- **Win celebration (>= 5x):** 100-piece confetti burst (same as BUX Booster)
- **Big win (>= 10x):** Extra large confetti + shake animation

---

## 13. Implementation Order

Each phase includes its own tests. Run tests after each phase before moving to the next. See Section 15 for Plinko test specs and `docs/bux_bankroll_plan.md` Section 10 for BUXBankroll test specs.

**BUXBankroll phases (build FIRST — PlinkoGame depends on it):**

| Phase | What | Tests | Run Command |
|-------|------|-------|-------------|
| B1 | **BUXBankroll.sol** — Write LP token bankroll contract | `BUXBankroll.test.js` (~60 tests) | `npx hardhat test test/BUXBankroll.test.js` |
| B2 | **Deploy BUXBankroll** — Deploy proxy, seed initial BUX | `verify-bux-bankroll.js` (~40 assertions) | `npx hardhat run scripts/verify-bux-bankroll.js --network rogue` |
| B3 | **BUX Minter bankroll endpoints** — `/bux-bankroll/*` | Route tests in bux-minter repo | `npm test -- --grep Bankroll` |
| B4 | **Backend** — LPBuxPriceTracker, Mnesia candles, BuxMinter additions | `bux_bankroll_test.exs` (~25 tests) | `mix test test/blockster_v2/plinko/bux_bankroll_test.exs` |
| B5 | **BankrollLive** — Deposit/withdraw UI, candlestick charts | `bankroll_live_test.exs` (~30 tests) | `mix test test/blockster_v2_web/live/bankroll_live_test.exs` |

**Plinko phases (PlinkoGame depends on BOTH BUXBankroll AND ROGUEBankroll — both must exist first):**

| Phase | What | Tests | Run Command |
|-------|------|-------|-------------|
| P1 | **ROGUEBankroll V10** — Add Plinko storage + functions at END of existing contract | ROGUE Plinko tests in `PlinkoGame.test.js` (Section 15.2) | `npx hardhat test` |
| P2 | **PlinkoGame.sol** — Write, compile (BUX via BUXBankroll, ROGUE via ROGUEBankroll) | `PlinkoGame.test.js` (Section 15.1) | `npx hardhat test test/PlinkoGame.test.js` |
| P3 | **Deploy PlinkoGame + upgrade ROGUEBankroll** — Link all contracts | `verify-plinko-deployment.js` (Section 15.3) | `npx hardhat run scripts/verify-plinko-deployment.js --network rogue` |
| P4 | **BUX Minter Plinko endpoints** — `/plinko/*` | `test/plinko.test.js` in bux-minter repo (Section 15.4) | `npm test -- --grep Plinko` |
| P5 | **Mnesia + Backend** — Table, PlinkoGame.ex, PlinkoSettler.ex, BuxMinter.ex | `plinko_math_test.exs`, `plinko_game_test.exs`, `plinko_settler_test.exs` (Section 15.5) | `mix test test/blockster_v2/plinko/` |
| P6 | **Frontend** — PlinkoLive.ex, JS hooks, CSS, routing | `plinko_live_test.exs` (Section 15.6) | `mix test test/blockster_v2_web/live/plinko_live_test.exs` |
| P7 | **Integration** — Wire LiveView events + JS + backend + provably fair + admin | `plinko_integration_test.exs` (Section 15.7) | `mix test test/blockster_v2/plinko/plinko_integration_test.exs` |

---

## 14. File List

| File | Action | Description |
|------|--------|-------------|
| **Smart Contracts** | | |
| `contracts/bux-booster-game/contracts/PlinkoGame.sol` | NEW | Main Plinko smart contract (UUPS proxy) |
| `contracts/bux-booster-game/contracts/ROGUEBankroll.sol` | MODIFY | Add Plinko integration (manual upgrade) |
| `contracts/bux-booster-game/scripts/deploy-plinko.js` | NEW | PlinkoGame deployment script |
| `contracts/bux-booster-game/test/PlinkoGame.test.js` | NEW | Hardhat tests for PlinkoGame |
| **Backend** | | |
| `lib/blockster_v2/plinko_game.ex` | NEW | Game orchestration (commit, place, settle, result calc) |
| `lib/blockster_v2/plinko_settler.ex` | NEW | Background settlement GenServer (global singleton) |
| `lib/blockster_v2/bux_minter.ex` | MODIFY | Add Plinko endpoints (submit, settle BUX/ROGUE, max bet) + BUXBankroll endpoints (house-info, lp-price) |
| `lib/blockster_v2/mnesia_initializer.ex` | MODIFY | Add `:plinko_games` table (24 fields + table name) |
| `lib/blockster_v2/application.ex` | MODIFY | Add `{GlobalSingleton, {PlinkoSettler, []}}` to children |
| **Frontend** | | |
| `lib/blockster_v2_web/live/plinko_live.ex` | NEW | LiveView (mount, events, render — monolithic with inline HEEx) |
| `assets/js/plinko_ball.js` | NEW | Ball drop animation hook (SVG coordinate math + timing) |
| `assets/js/plinko_onchain.js` | NEW | Blockchain interaction hook (approval, placeBet, error handling) |
| `assets/js/PlinkoGame.json` | NEW | Contract ABI (generated by Hardhat compile) |
| `assets/js/app.js` | MODIFY | Register PlinkoBall + PlinkoOnchain hooks |
| `assets/css/app.css` | MODIFY | Add plinko board, slot, trail, animation styles |
| **Routing** | | |
| `lib/blockster_v2_web/router.ex` | MODIFY | Add `live "/plinko", PlinkoLive, :index` |
| **Admin** | | |
| `lib/blockster_v2_web/live/admin/stats_live/index.ex` | MODIFY | Add Plinko stats section |
| **Tests — Smart Contracts** | | |
| `contracts/bux-booster-game/test/PlinkoGame.test.js` | NEW | Hardhat tests: init, payout tables, placeBet, settleBet, path validation, ROGUE flow |
| `contracts/bux-booster-game/scripts/verify-plinko-deployment.js` | NEW | Post-deploy verification script (all 9 configs, settler, tokens, max bets) |
| **Tests — Backend** | | |
| `test/blockster_v2/plinko/plinko_math_test.exs` | NEW | Payout tables, result calculation, symmetry, edge cases |
| `test/blockster_v2/plinko/plinko_game_test.exs` | NEW | Mnesia state transitions, nonce mgmt, get/init/settle game |
| `test/blockster_v2/plinko/plinko_settler_test.exs` | NEW | Settler worker: stuck bet detection, settlement, scheduling |
| `test/blockster_v2/plinko/plinko_integration_test.exs` | NEW | Full flow: init -> bet -> settle -> stats, balance sync, PubSub |
| **Tests — Frontend** | | |
| `test/blockster_v2_web/live/plinko_live_test.exs` | NEW | LiveView mount, event handlers, assigns, config switching |
| **Tests — BUX Minter** | | |
| `test/plinko.test.js` (in bux-minter repo) | NEW | Express route tests: submit-commitment, settle-bet, max-bet |

### Router Change

```elixir
# In router.ex, add inside the authenticated scope (alongside /play):
live "/plinko", PlinkoLive, :index
```

### app.js Hook Registration

```javascript
import { PlinkoBall } from "./plinko_ball";
import { PlinkoOnchain } from "./plinko_onchain";

let hooks = {
  // ...existing hooks (BuxBoosterOnchain, CoinFlip, etc.)...
  PlinkoBall,
  PlinkoOnchain,
};
```

---

## 15. Testing Plan

Tests are written and run after each implementation phase. Every phase must be green before starting the next.

### 15.1 Phase 1: PlinkoGame.sol — Hardhat Tests

**File:** `contracts/bux-booster-game/test/PlinkoGame.test.js`
**Run:** `npx hardhat test test/PlinkoGame.test.js`
**Pattern:** Follows `BuxBoosterGame.v7.test.js` — deploy proxy, mock ERC-20, deploy BUXBankroll, link contracts.

```javascript
describe("PlinkoGame", function () {

  // ============ Setup ============
  // Deploy PlinkoGame as UUPS proxy
  // Deploy BUXBankroll as UUPS proxy (LP token for BUX)
  // Deploy MockERC20 for BUX
  // Mint tokens to players + owner
  // Set settler, configure token, link BUXBankroll ↔ PlinkoGame
  // Deposit BUX house balance into BUXBankroll (not PlinkoGame)
  // Set all 9 payout tables via setPayoutTable()

  // ============ Initialization ============
  describe("Initialization", function () {
    it("should initialize all 9 PlinkoConfigs correctly");
    // Verify: configs[0..8] have correct (rows, riskLevel, numPositions, maxMultiplierBps=0 before tables set)
    it("should set owner correctly");
    it("should reject double initialization");
  });

  // ============ Payout Tables ============
  describe("Payout Table Configuration", function () {
    it("should set 8-Low payout table (9 values) and update maxMultiplierBps to 56000");
    it("should set 8-Medium payout table and update maxMultiplierBps to 130000");
    it("should set 8-High payout table and update maxMultiplierBps to 360000");
    it("should set 12-Low payout table (13 values) and update maxMultiplierBps to 110000");
    it("should set 12-Medium payout table and update maxMultiplierBps to 330000");
    it("should set 12-High payout table and update maxMultiplierBps to 4050000");
    it("should set 16-Low payout table (17 values) and update maxMultiplierBps to 160000");
    it("should set 16-Medium payout table and update maxMultiplierBps to 1100000");
    it("should set 16-High payout table and update maxMultiplierBps to 10000000");
    it("should reject setPayoutTable from non-owner");
    it("should reject invalid configIndex >= 9");
    it("should reject payout table with wrong number of values for config");
    it("should emit PayoutTableUpdated event");
    it("should allow overwriting an existing payout table");
  });

  // ============ Payout Table Symmetry ============
  describe("Payout Table Symmetry", function () {
    // For each of the 9 configs, verify table[k] == table[N-k]
    it("should have symmetric payouts for all 9 configs");
  });

  // ============ Token Configuration ============
  describe("Token Configuration", function () {
    it("should enable a token");
    it("should disable a token");
    it("should reject configureToken from non-owner");
    it("should emit TokenConfigured event");
  });

  // ============ BUXBankroll Integration ============
  describe("BUXBankroll Integration", function () {
    it("should have BUXBankroll address set correctly");
    it("should query max bet from BUXBankroll available liquidity");
    it("should delegate BUX settlement to BUXBankroll on win");
    it("should delegate BUX settlement to BUXBankroll on loss");
    it("should reject bet when BUXBankroll has insufficient liquidity");
  });

  // ============ Commitment ============
  describe("Commitment Submission", function () {
    it("should submit commitment from settler");
    it("should reject commitment from non-settler");
    it("should reject duplicate commitment hash");
    it("should emit CommitmentSubmitted event");
    it("should store commitment with correct player, nonce, timestamp");
  });

  // ============ Place Bet (BUX) ============
  describe("placeBet (BUX)", function () {
    it("should place bet with valid params and transfer tokens to BUXBankroll");
    it("should reject bet below MIN_BET (1e18)");
    it("should reject bet above max bet for config");
    it("should reject bet with disabled token — TokenNotEnabled");
    it("should reject bet with invalid configIndex >= 9 — InvalidConfigIndex");
    it("should reject bet before payout table is set — PayoutTableNotSet");
    it("should reject bet with unused commitment — CommitmentNotFound");
    it("should reject bet with already-used commitment — CommitmentAlreadyUsed");
    it("should reject bet with wrong player for commitment — CommitmentWrongPlayer");
    it("should reject bet when BUXBankroll has insufficient liquidity — InsufficientHouseBalance");
    it("should emit PlinkoBetPlaced event with correct fields");
    it("should mark commitment as used after bet placement");
    it("should increment totalBetsPlaced counter");
  });

  // ============ Max Bet Calculations ============
  describe("Max Bet (BUX via BUXBankroll)", function () {
    it("should calculate correct max bet for 8-Low (maxMult=5.6x) from BUXBankroll liquidity");
    it("should calculate correct max bet for 16-High (maxMult=1000x) from BUXBankroll liquidity");
    it("should return 0 when BUXBankroll has no liquidity");
    it("should decrease as BUXBankroll available liquidity decreases");
    // Formula: maxBet based on BUXBankroll.getAvailableLiquidity() and maxMultiplierBps
  });

  // ============ Settlement (BUX) ============
  describe("settleBet (BUX)", function () {

    describe("Win (payout > bet)", function () {
      it("should settle winning bet: BUXBankroll pays payout to player");
      it("should set bet status to Won");
      it("should update buxPlayerStats (wins, totalWinnings)");
      it("should update buxAccounting (totalWins, totalPayouts, totalHouseProfit)");
      it("should emit PlinkoBetSettled with profited=true");
      it("should emit PlinkoBallPath with correct path and configLabel");
      it("should emit PlinkoBetDetails");
      it("should reveal serverSeed in Commitment struct");
    });

    describe("Loss (payout < bet)", function () {
      it("should settle losing bet: add loss to house, transfer partial payout if > 0");
      it("should handle 0x payout (no transfer, full loss to house)");
      it("should set bet status to Lost");
      it("should update buxPlayerStats (losses, totalLosses)");
      it("should emit PlinkoBetSettled with profited=false");
      it("should pay referral reward on loss portion if referrer set");
    });

    describe("Push (payout == bet)", function () {
      it("should settle push bet: return exact bet amount, no house movement");
      it("should set bet status to Push");
      it("should update buxPlayerStats (pushes)");
    });

    describe("Edge cases", function () {
      it("should reject settlement of non-existent bet — BetNotFound");
      it("should reject double settlement — BetAlreadySettled (0x05d09e5f)");
      it("should reject settlement from non-settler — UnauthorizedSettler");
      it("should increment totalBetsSettled counter");
    });
  });

  // ============ Path Validation ============
  describe("Path Validation", function () {
    it("should reject path with wrong length (path.length != rows)");
    it("should reject path with invalid element (not 0 or 1)");
    it("should reject path where landing position != count of 1s — InvalidLandingPosition");
    it("should reject landing position >= numPositions — InvalidLandingPosition");
    it("should accept valid path for 8-row config (8 elements, all 0/1)");
    it("should accept valid path for 12-row config");
    it("should accept valid path for 16-row config");
    it("should accept all-left path (landing=0) for edge slot");
    it("should accept all-right path (landing=rows) for edge slot");
  });

  // ============ Bet Expiry ============
  describe("Bet Expiry & Refund", function () {
    it("should allow refund after BET_EXPIRY (1 hour)");
    it("should reject refund before expiry — BetNotExpired");
    it("should return bet amount to player on refund");
    it("should set bet status to Expired");
    it("should emit PlinkoBetExpired event");
    it("should allow anyone to call refundExpiredBet (public)");
  });

  // ============ Player Stats ============
  describe("Player Stats Tracking", function () {
    it("should track betsPerConfig[configIndex] correctly across multiple bets");
    it("should track profitLossPerConfig as signed int (positive wins, negative losses)");
    it("should accumulate totalWagered across all bets");
    it("should track largestWin in global accounting");
    it("should track largestBet in global accounting");
  });

  // ============ Referral System ============
  describe("Referral Rewards", function () {
    it("should set player referrer via referralAdmin");
    it("should batch-set referrers via setPlayerReferrersBatch");
    it("should pay BUX referral reward on losing bet (buxReferralBasisPoints)");
    it("should not pay referral on winning or push bets");
    it("should track totalReferralRewardsPaid per referrer");
    it("should emit ReferralRewardPaid event");
  });

  // ============ Receive Function ============
  describe("Receive", function () {
    it("should accept raw ROGUE transfers (for bankroll refunds)");
  });

  // ============ UUPS ============
  describe("UUPS Upgrade", function () {
    it("should allow owner to upgrade implementation");
    it("should reject upgrade from non-owner");
  });
});
```

**Expected test count:** ~70-80 tests

---

### 15.2 Phase 2: ROGUEBankroll V10 — Hardhat Tests

**File:** Add to `contracts/bux-booster-game/test/PlinkoGame.test.js` (same file, new describe block)
**Run:** `npx hardhat test test/PlinkoGame.test.js`

```javascript
describe("PlinkoGame — ROGUE Path (via ROGUEBankroll)", function () {

  // ============ Setup ============
  // Deploy PlinkoGame proxy + ROGUEBankroll proxy
  // Link: plinkoGame.setROGUEBankroll(bankroll) + bankroll.setPlinkoGame(plinko)
  // Fund ROGUEBankroll with native ROGUE
  // Set payout tables on PlinkoGame

  // ============ ROGUEBankroll V10 State ============
  describe("ROGUEBankroll Plinko State", function () {
    it("should set plinkoGame address via setPlinkoGame");
    it("should reject setPlinkoGame from non-owner");
    it("should start with zero plinkoAccounting");
    it("should start with zero plinkoPlayerStats for any address");
  });

  // ============ placeBetROGUE ============
  describe("placeBetROGUE", function () {
    it("should accept native ROGUE bet with msg.value == amount");
    it("should forward ROGUE to ROGUEBankroll via updateHouseBalancePlinkoBetPlaced");
    it("should reject bet when msg.value != amount");
    it("should reject bet below MIN_BET");
    it("should reject bet above getMaxBetROGUE for config");
    it("should reject bet before payout table set — PayoutTableNotSet");
    it("should emit PlinkoBetPlaced event on ROGUEBankroll");
  });

  // ============ settleBetROGUE — Win ============
  describe("settleBetROGUE — Win", function () {
    it("should call ROGUEBankroll.settlePlinkoWinningBet");
    it("should send ROGUE payout to winner");
    it("should update plinkoPlayerStats (wins, totalWinnings)");
    it("should update plinkoAccounting (totalWins, totalPayouts)");
    it("should reduce ROGUEBankroll house balance by profit amount");
    it("should emit PlinkoWinningPayout and PlinkoWinDetails events");
  });

  // ============ settleBetROGUE — Loss ============
  describe("settleBetROGUE — Loss", function () {
    it("should call ROGUEBankroll.settlePlinkoLosingBet");
    it("should keep ROGUE in bankroll");
    it("should send partial payout if multiplier > 0");
    it("should send no payout for 0x multiplier");
    it("should send NFT reward (0.2% of loss portion) to NFTRewarder");
    it("should send referral reward (0.2% of loss portion) to referrer");
    it("should not revert if NFT reward transfer fails (non-blocking)");
    it("should not revert if referral reward transfer fails (non-blocking)");
    it("should update plinkoPlayerStats (losses, totalLosses)");
    it("should emit PlinkoLosingBet and PlinkoLossDetails events");
  });

  // ============ settleBetROGUE — Push ============
  describe("settleBetROGUE — Push", function () {
    it("should return exact bet amount in ROGUE");
    it("should not pay NFT or referral rewards on push");
    it("should update plinkoPlayerStats (pushes)");
  });

  // ============ ROGUE Max Bet ============
  describe("getMaxBetROGUE", function () {
    it("should calculate max bet based on ROGUEBankroll balance and config maxMultiplier");
    it("should return different values for different configs");
    it("should return 0 when bankroll is empty");
  });

  // ============ Cross-contract Accounting ============
  describe("Accounting Consistency", function () {
    it("should track plinkoBetsPerConfig[configIndex] in ROGUEBankroll");
    it("should track plinkoPnLPerConfig as signed int in ROGUEBankroll");
    it("should keep plinkoAccounting.totalHouseProfit consistent with actual balance changes");
  });

  // ============ Access Control ============
  describe("Access Control", function () {
    it("should reject settlePlinkoWinningBet from non-plinko address");
    it("should reject settlePlinkoLosingBet from non-plinko address");
    it("should reject updateHouseBalancePlinkoBetPlaced from non-plinko address");
  });
});
```

**Expected test count:** ~35-40 tests

---

### 15.3 Phase 3: Deploy Verification — Post-Deployment Script

**File:** `contracts/bux-booster-game/scripts/verify-plinko-deployment.js`
**Run:** `npx hardhat run scripts/verify-plinko-deployment.js --network rogue`

This is NOT a Hardhat test — it's a verification script that reads from the live deployed contracts and asserts correctness. Exits with code 1 on any failure.

```javascript
// verify-plinko-deployment.js
// Runs against live Rogue Chain contracts after deployment.
// Verifies every configurable parameter is set correctly.

const { ethers } = require("hardhat");

const PLINKO_ADDRESS = process.env.PLINKO_CONTRACT_ADDRESS;
const ROGUE_BANKROLL_ADDRESS = "0x51DB4eD2b69b598Fade1aCB5289C7426604AB2fd";
const BUX_TOKEN_ADDRESS = "0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8";
const SETTLER_ADDRESS = process.env.SETTLER_ADDRESS;

// Expected payout tables (basis points) — must match Section 2 exactly
const EXPECTED_TABLES = {
  0: [56000, 21000, 11000, 10000, 5000, 10000, 11000, 21000, 56000],
  1: [130000, 30000, 13000, 7000, 4000, 7000, 13000, 30000, 130000],
  2: [360000, 40000, 15000, 3000, 0, 3000, 15000, 40000, 360000],
  3: [110000, 30000, 16000, 14000, 11000, 10000, 5000, 10000, 11000, 14000, 16000, 30000, 110000],
  4: [330000, 110000, 40000, 20000, 11000, 6000, 3000, 6000, 11000, 20000, 40000, 110000, 330000],
  5: [4050000, 180000, 70000, 20000, 7000, 2000, 0, 2000, 7000, 20000, 70000, 180000, 4050000],
  6: [160000, 90000, 20000, 14000, 14000, 12000, 11000, 10000, 5000, 10000, 11000, 12000, 14000, 14000, 20000, 90000, 160000],
  7: [1100000, 410000, 100000, 50000, 30000, 15000, 10000, 5000, 3000, 5000, 10000, 15000, 30000, 50000, 100000, 410000, 1100000],
  8: [10000000, 1500000, 330000, 100000, 33000, 20000, 3000, 2000, 0, 2000, 3000, 20000, 33000, 100000, 330000, 1500000, 10000000],
};

const EXPECTED_CONFIGS = [
  { rows: 8,  risk: 0, positions: 9,  maxMult: 56000 },
  { rows: 8,  risk: 1, positions: 9,  maxMult: 130000 },
  { rows: 8,  risk: 2, positions: 9,  maxMult: 360000 },
  { rows: 12, risk: 0, positions: 13, maxMult: 110000 },
  { rows: 12, risk: 1, positions: 13, maxMult: 330000 },
  { rows: 12, risk: 2, positions: 13, maxMult: 4050000 },
  { rows: 16, risk: 0, positions: 17, maxMult: 160000 },
  { rows: 16, risk: 1, positions: 17, maxMult: 1100000 },
  { rows: 16, risk: 2, positions: 17, maxMult: 10000000 },
];

async function main() {
  let failures = 0;
  const assert = (condition, msg) => {
    if (!condition) { console.error(`FAIL: ${msg}`); failures++; }
    else { console.log(`PASS: ${msg}`); }
  };

  const plinko = await ethers.getContractAt("PlinkoGame", PLINKO_ADDRESS);
  const bankroll = await ethers.getContractAt("ROGUEBankroll", ROGUE_BANKROLL_ADDRESS);

  // 1. Verify all 9 PlinkoConfigs
  for (let i = 0; i < 9; i++) {
    const config = await plinko.getPlinkoConfig(i);
    const expected = EXPECTED_CONFIGS[i];
    assert(config.rows === expected.rows, `Config ${i} rows = ${expected.rows}`);
    assert(config.riskLevel === expected.risk, `Config ${i} risk = ${expected.risk}`);
    assert(config.numPositions === expected.positions, `Config ${i} positions = ${expected.positions}`);
    assert(Number(config.maxMultiplierBps) === expected.maxMult, `Config ${i} maxMult = ${expected.maxMult}`);
  }

  // 2. Verify all 9 payout tables (value-by-value)
  for (let i = 0; i < 9; i++) {
    const table = await plinko.getPayoutTable(i);
    const expected = EXPECTED_TABLES[i];
    assert(table.length === expected.length, `Table ${i} length = ${expected.length}`);
    for (let j = 0; j < expected.length; j++) {
      assert(Number(table[j]) === expected[j], `Table ${i}[${j}] = ${expected[j]}`);
    }
    // Verify symmetry: table[k] === table[N-k]
    for (let k = 0; k < expected.length; k++) {
      assert(Number(table[k]) === Number(table[expected.length - 1 - k]),
        `Table ${i} symmetry: [${k}] == [${expected.length - 1 - k}]`);
    }
  }

  // 3. Verify BUX token is enabled + BUXBankroll has liquidity
  const buxConfig = await plinko.tokenConfigs(BUX_TOKEN_ADDRESS);
  assert(buxConfig.enabled === true, "BUX token enabled");
  const buxBankrollInfo = await buxBankroll.buxBalances();
  assert(buxBankrollInfo.totalBalance > 0n, `BUXBankroll has balance (got ${ethers.formatEther(buxBankrollInfo.totalBalance)})`);

  // 4. Verify settler is set
  const settler = await plinko.settler();
  assert(settler.toLowerCase() === SETTLER_ADDRESS.toLowerCase(), `Settler = ${SETTLER_ADDRESS}`);

  // 5. Verify ROGUEBankroll link (bidirectional)
  const bankrollAddr = await plinko.rogueBankroll();
  assert(bankrollAddr.toLowerCase() === ROGUE_BANKROLL_ADDRESS.toLowerCase(), "ROGUEBankroll linked in PlinkoGame");
  const plinkoInBankroll = await bankroll.plinkoGame();
  assert(plinkoInBankroll.toLowerCase() === PLINKO_ADDRESS.toLowerCase(), "PlinkoGame linked in ROGUEBankroll");

  // 6. Verify max bet returns non-zero for each config (BUX via BUXBankroll)
  for (let i = 0; i < 9; i++) {
    const maxBet = await plinko.getMaxBet(i);
    assert(maxBet > 0n, `MaxBet BUX config ${i} > 0 (got ${ethers.formatEther(maxBet)})`);
  }

  // 7. Verify max bet returns non-zero for each config (ROGUE)
  for (let i = 0; i < 9; i++) {
    const maxBet = await plinko.getMaxBetROGUE(i);
    assert(maxBet > 0n, `MaxBet ROGUE config ${i} > 0 (got ${ethers.formatEther(maxBet)})`);
  }

  // 8. Verify global accounting starts clean
  const accounting = await plinko.getBuxAccounting();
  assert(accounting[0] === 0n, "Initial totalBets = 0");

  // Summary
  console.log(`\n=== ${failures === 0 ? 'ALL PASSED' : failures + ' FAILURES'} ===`);
  if (failures > 0) process.exit(1);
}

main().catch(console.error);
```

**Expected checks:** ~90+ assertions (9 tables x ~10 values each + configs + links + max bets)

---

### 15.4 Phase 4: BUX Minter — Express Route Tests

**File:** `test/plinko.test.js` (in bux-minter repo, alongside existing tests)
**Run:** `npm test -- --grep Plinko`
**Framework:** Mocha + Chai + Supertest (match existing bux-minter test patterns)

```javascript
const request = require("supertest");
const { expect } = require("chai");
const app = require("../app");

describe("Plinko API Routes", function () {

  const AUTH_HEADER = `Bearer ${process.env.MINTER_SECRET}`;

  // ============ Auth ============
  describe("Authentication", function () {
    it("POST /plinko/submit-commitment should reject without auth header — 401");
    it("POST /plinko/settle-bet should reject without auth header — 401");
    it("POST /plinko/settle-bet-rogue should reject without auth header — 401");
    it("GET /bux-bankroll/house-info should reject without auth header — 401");
    it("GET /plinko/max-bet/0 should reject without auth header — 401");
  });

  // ============ Submit Commitment ============
  describe("POST /plinko/submit-commitment", function () {
    it("should submit commitment and return txHash on success");
    it("should return 500 with error message on contract revert");
    it("should reject missing commitmentHash field — 400");
    it("should reject missing player field — 400");
    it("should reject missing nonce field — 400");
    it("should reject invalid commitment hash format");
  });

  // ============ Settle Bet (BUX) ============
  describe("POST /plinko/settle-bet", function () {
    it("should settle bet and return txHash on success");
    it("should include playerBalance in response if available");
    it("should return 500 with error on contract revert");
    it("should handle BetAlreadySettled error (0x05d09e5f) gracefully");
    it("should reject missing commitmentHash — 400");
    it("should reject missing serverSeed — 400");
    it("should reject missing path — 400");
    it("should reject missing landingPosition — 400");
    it("should reject path with non-integer elements — 400");
  });

  // ============ Settle Bet (ROGUE) ============
  describe("POST /plinko/settle-bet-rogue", function () {
    it("should call settleBetROGUE on contract and return txHash");
    it("should handle BetAlreadySettled gracefully");
    it("should return error on revert");
  });

  // ============ BUXBankroll House Info ============
  describe("GET /bux-bankroll/house-info", function () {
    it("should return totalBalance, liability, unsettledBets, netBalance");
    it("should return lpSupply and lpPrice");
    it("should return all values as strings (BigInt-safe)");
    it("should handle contract read error gracefully — 500");
  });

  // ============ Max Bet ============
  describe("GET /plinko/max-bet/:configIndex", function () {
    it("should return maxBet as string for BUX config 0 (from BUXBankroll liquidity)");
    it("should return different maxBet for different configs");
    it("should handle invalid configIndex >= 9 — 500 with error");
  });

  // ============ Contract ABI Loading ============
  describe("Contract Setup", function () {
    it("should load PlinkoGame ABI without errors");
    it("should load BUXBankroll ABI without errors");
    it("should connect to PLINKO_CONTRACT_ADDRESS env var");
    it("should connect to BUX_BANKROLL_ADDRESS env var");
  });
});
```

**Expected test count:** ~35 tests

---

### 15.5 Phase 5: Backend Elixir — Math, Game Logic, Settler

Three test files in `test/blockster_v2/plinko/`.

#### 15.5.1 `plinko_math_test.exs` — Payout Tables & Result Calculation

**File:** `test/blockster_v2/plinko/plinko_math_test.exs`
**Run:** `mix test test/blockster_v2/plinko/plinko_math_test.exs`

```elixir
defmodule BlocksterV2.Plinko.PlinkoMathTest do
  use ExUnit.Case, async: true

  alias BlocksterV2.PlinkoGame

  # ============ Payout Table Integrity ============
  describe "payout tables" do
    test "all 9 tables are defined"
    test "8-Low has exactly 9 values"
    test "8-Medium has exactly 9 values"
    test "8-High has exactly 9 values"
    test "12-Low has exactly 13 values"
    test "12-Medium has exactly 13 values"
    test "12-High has exactly 13 values"
    test "16-Low has exactly 17 values"
    test "16-Medium has exactly 17 values"
    test "16-High has exactly 17 values"
  end

  describe "payout table symmetry" do
    # For each config: table[k] must equal table[N-k]
    test "all 9 tables are symmetric"
    # Loop through all 9, compare position k with position (length-1-k)
  end

  describe "payout table values match contract" do
    test "8-Low: [56000, 21000, 11000, 10000, 5000, 10000, 11000, 21000, 56000]"
    test "8-Medium: [130000, 30000, 13000, 7000, 4000, 7000, 13000, 30000, 130000]"
    test "8-High: [360000, 40000, 15000, 3000, 0, 3000, 15000, 40000, 360000]"
    test "12-Low: [110000, 30000, 16000, 14000, 11000, 10000, 5000, ...]"
    test "12-Medium: [330000, 110000, 40000, 20000, 11000, 6000, 3000, ...]"
    test "12-High: [4050000, 180000, 70000, 20000, 7000, 2000, 0, ...]"
    test "16-Low: [160000, 90000, 20000, 14000, 14000, 12000, 11000, 10000, 5000, ...]"
    test "16-Medium: [1100000, 410000, 100000, 50000, 30000, 15000, 10000, 5000, 3000, ...]"
    test "16-High: [10000000, 1500000, 330000, 100000, 33000, 20000, 3000, 2000, 0, ...]"
  end

  describe "max multiplier per config" do
    test "8-Low max = 56000 (5.6x)"
    test "8-Med max = 130000 (13x)"
    test "8-High max = 360000 (36x)"
    test "12-Low max = 110000 (11x)"
    test "12-Med max = 330000 (33x)"
    test "12-High max = 4050000 (405x)"
    test "16-Low max = 160000 (16x)"
    test "16-Med max = 1100000 (110x)"
    test "16-High max = 10000000 (1000x)"
  end

  # ============ Result Calculation (Deterministic) ============
  describe "calculate_result/6" do
    test "produces deterministic results for same inputs"
    # Call twice with identical params, assert identical output

    test "produces different results for different server seeds"

    test "ball_path length equals rows for 8-row config"
    test "ball_path length equals rows for 12-row config"
    test "ball_path length equals rows for 16-row config"

    test "ball_path contains only :left and :right atoms"

    test "landing_position equals count of :right in ball_path"

    test "landing_position is between 0 and rows (inclusive)"

    test "payout_bp matches payout_table lookup at landing_position"

    test "payout = (bet_amount * payout_bp) / 10000"

    test "outcome is :won when payout > bet_amount"
    test "outcome is :lost when payout < bet_amount"
    test "outcome is :push when payout == bet_amount"

    test "won is true when payout > bet_amount"
    test "won is false when payout <= bet_amount"
  end

  describe "calculate_result edge cases" do
    test "all-left path (all bytes < 128) lands at position 0"
    # Use a server seed that produces bytes all < 128 for first N bytes

    test "all-right path lands at position = rows"

    test "0x payout (8-High center) returns payout = 0 and outcome = :lost"

    test "1000x payout (16-High edge) returns correct large payout"

    test "different user_id produces different client_seed and different result"

    test "different bet_amount produces different client_seed and different result"

    test "different config_index produces different result for same seed"

    test "same user+amount+token+config but different server_seed gives different path"
  end

  # ============ Byte-to-Direction Mapping ============
  describe "byte threshold" do
    test "byte 0 (0x00) maps to :left"
    test "byte 127 (0x7F) maps to :left"
    test "byte 128 (0x80) maps to :right"
    test "byte 255 (0xFF) maps to :right"
  end

  # ============ House Edge Verification ============
  describe "house edge (statistical)" do
    # For each config, compute expected value by summing:
    #   probability(position_k) * multiplier(position_k)
    # Expected value should be between 0.98 and 0.995 (house edge 0.5% to 2%)
    test "8-Low expected value is between 0.98 and 1.0 (house edge ~1%)"
    test "8-Med expected value is between 0.98 and 1.0"
    test "8-High expected value is between 0.98 and 1.0"
    test "12-Low expected value is between 0.98 and 1.0"
    test "12-Med expected value is between 0.98 and 1.0"
    test "12-High expected value is between 0.98 and 1.0"
    test "16-Low expected value is between 0.98 and 1.0"
    test "16-Med expected value is between 0.98 and 1.0"
    test "16-High expected value is between 0.98 and 1.0"
  end

  # ============ Config Mapping ============
  describe "configs" do
    test "config 0 = {8, :low}"
    test "config 1 = {8, :medium}"
    test "config 2 = {8, :high}"
    test "config 3 = {12, :low}"
    test "config 4 = {12, :medium}"
    test "config 5 = {12, :high}"
    test "config 6 = {16, :low}"
    test "config 7 = {16, :medium}"
    test "config 8 = {16, :high}"
    test "invalid config index returns nil"
  end
end
```

**Expected test count:** ~60 tests

#### 15.5.2 `plinko_game_test.exs` — Mnesia State Transitions & Game Logic

**File:** `test/blockster_v2/plinko/plinko_game_test.exs`
**Run:** `mix test test/blockster_v2/plinko/plinko_game_test.exs`

> **Note**: Requires Mnesia running with `:plinko_games` table. Tests use `setup` to create
> the table if not present and clear it between tests. Not `async: true` (Mnesia is global).

```elixir
defmodule BlocksterV2.Plinko.PlinkoGameTest do
  use ExUnit.Case

  alias BlocksterV2.PlinkoGame

  setup do
    # Clear plinko_games table between tests
    :mnesia.clear_table(:plinko_games)
    :ok
  end

  # ============ init_game_with_nonce ============
  describe "init_game_with_nonce/3" do
    test "creates game with :committed status in Mnesia"
    test "generates 64-char hex server seed"
    test "generates 0x-prefixed commitment hash"
    test "stores correct user_id, wallet_address, nonce"
    test "returns game_id, commitment_hash, commitment_tx, nonce"
    test "calls BuxMinter.plinko_submit_commitment (mock or verify side effect)"
  end

  # ============ get_or_init_game ============
  describe "get_or_init_game/2" do
    test "creates new game when no existing games for user"
    test "reuses existing :committed game with correct nonce and commitment_tx"
    test "creates new game when existing committed game has wrong nonce"
    test "creates new game when existing committed game has nil commitment_tx"
    test "calculates next nonce as max(placed/settled nonces) + 1"
    test "nonce starts at 0 for first game"
    test "nonce increments after each placed game"
    test "ignores :committed games in nonce calculation (only counts placed/settled)"
  end

  # ============ get_game ============
  describe "get_game/1" do
    test "returns {:ok, game_map} for existing game"
    test "returns {:error, :not_found} for missing game"
    test "game map has all 24 fields"
    test "correctly destructures Mnesia tuple into map"
  end

  # ============ get_pending_game ============
  describe "get_pending_game/1" do
    test "returns committed game for user_id"
    test "returns nil when no committed games exist"
    test "does not return placed or settled games"
  end

  # ============ on_bet_placed ============
  describe "on_bet_placed/6" do
    test "updates game status from :committed to :placed"
    test "stores bet_id, token, token_address, bet_amount, config_index"
    test "calculates and stores ball_path, landing_position, payout_bp, payout, won"
    test "stores rows and risk_level from config lookup"
    test "stores bet_tx hash"
    test "returns {:ok, result} with calculated result"
    test "returns {:error, :not_found} for invalid game_id"
    test "Mnesia tuple has exactly 25 elements after update"
  end

  # ============ calculate_game_result ============
  describe "calculate_game_result/5" do
    test "reads game from Mnesia and delegates to calculate_result/6"
    test "returns {:error, :not_found} for invalid game_id"
    test "result matches direct calculate_result/6 call with same params"
  end

  # ============ settle_game ============
  describe "settle_game/1" do
    test "settles a :placed game and transitions to :settled"
    test "stores settlement_tx hash"
    test "stores settled_at timestamp"
    test "returns {:ok, %{tx_hash: ..., player_balance: ...}}"
    test "skips already-settled games (returns {:ok, ..., already_settled: true})"
    test "handles BetAlreadySettled error (0x05d09e5f) gracefully"
    test "returns {:error, :bet_not_placed} for :committed games"
    test "returns {:error, :not_found} for missing games"
    test "broadcasts plinko_settlement PubSub message on success"
    test "calls sync_user_balances_async on success"
    test "calls update_user_betting_stats on success"
  end

  # ============ mark_game_settled ============
  describe "mark_game_settled/3" do
    test "writes :settled status to Mnesia"
    test "stores settlement_tx"
    test "stores settled_at as Unix timestamp"
  end

  # ============ load_recent_games ============
  describe "load_recent_games/2" do
    test "returns only :settled games"
    test "returns games sorted by created_at descending (newest first)"
    test "respects limit option"
    test "respects offset option"
    test "returns empty list for user with no games"
    test "returns maps (not tuples)"
    test "default limit is 30"
  end

  # ============ Token Address Mapping ============
  describe "token_address/1" do
    test "BUX returns 0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8"
    test "ROGUE returns zero address (0x0000...)"
  end

  # ============ is_bet_already_settled_error? ============
  describe "is_bet_already_settled_error?/1" do
    test "returns true for string containing 0x05d09e5f"
    test "returns false for other error strings"
    test "returns false for non-string input"
  end
end
```

**Expected test count:** ~45 tests

#### 15.5.3 `plinko_settler_test.exs` — Background Settlement Worker

**File:** `test/blockster_v2/plinko/plinko_settler_test.exs`
**Run:** `mix test test/blockster_v2/plinko/plinko_settler_test.exs`

```elixir
defmodule BlocksterV2.Plinko.PlinkoSettlerTest do
  use ExUnit.Case

  alias BlocksterV2.PlinkoSettler

  setup do
    :mnesia.clear_table(:plinko_games)
    :ok
  end

  # ============ Stuck Bet Detection ============
  describe "check_and_settle_stuck_bets" do
    test "finds :placed games older than 120 seconds"
    test "ignores :placed games newer than 120 seconds"
    test "ignores :committed games (not yet placed)"
    test "ignores :settled games"
    test "settles each stuck bet via PlinkoGame.settle_game/1"
    test "logs info when stuck bets are found"
    test "handles settlement failure gracefully (logs warning, continues)"
    test "does nothing when no stuck bets exist"
  end

  # ============ Scheduling ============
  describe "scheduling" do
    test "schedules first check on init"
    test "reschedules after each check (60 second interval)"
    test "handles :check_unsettled_bets message"
  end

  # ============ GenServer Lifecycle ============
  describe "lifecycle" do
    test "starts successfully via start_link"
    test "logs startup message"
  end
end
```

**Expected test count:** ~13 tests

---

### 15.6 Phase 6: Frontend — LiveView Tests

**File:** `test/blockster_v2_web/live/plinko_live_test.exs`
**Run:** `mix test test/blockster_v2_web/live/plinko_live_test.exs`

> **Pattern**: Uses `Phoenix.ConnTest` + `Phoenix.LiveViewTest`. Mount via `live(conn, "/plinko")`.
> Since on-chain operations are external, mock `PlinkoGame.get_or_init_game` and `BuxMinter`
> functions. Focus on LiveView assigns, event handling, and rendering.

```elixir
defmodule BlocksterV2Web.PlinkoLiveTest do
  use BlocksterV2Web.ConnCase
  import Phoenix.LiveViewTest

  # ============ Mount ============
  describe "mount — guest (not logged in)" do
    test "renders page with login prompt"
    test "does not start async operations"
    test "sets page_title to Plinko"
  end

  describe "mount — authenticated user without wallet" do
    test "renders with error_message 'No wallet connected'"
    test "sets onchain_ready to false"
    test "does not subscribe to PubSub channels"
  end

  describe "mount — authenticated user with wallet" do
    test "sets default assigns (selected_token=BUX, selected_rows=8, selected_risk=:low)"
    test "sets config_index to 0 (8-Low)"
    test "sets bet_amount to 10"
    test "sets game_state to :idle"
    test "loads payout_table for config 0"
    test "subscribes to bux_balance PubSub channel"
    test "subscribes to plinko_settlement PubSub channel"
    test "subscribes to token_prices PubSub channel"
    test "starts init_onchain_game async task"
    test "starts fetch_house_balance async task (queries BUXBankroll)"
    test "starts load_recent_games async task"
    test "sets onchain_initializing to true"
  end

  # ============ Config Selection ============
  describe "select_rows event" do
    test "switching to 12 rows updates selected_rows assign"
    test "switching to 16 rows updates selected_rows assign"
    test "updates config_index based on rows + current risk"
    test "updates payout_table to match new config"
    test "12 rows + medium risk = config_index 4"
    test "16 rows + high risk = config_index 8"
  end

  describe "select_risk event" do
    test "switching to :medium updates selected_risk assign"
    test "switching to :high updates selected_risk assign"
    test "updates config_index based on current rows + risk"
    test "updates payout_table to match new config"
  end

  # ============ Bet Amount Controls ============
  describe "update_bet_amount event" do
    test "sets bet_amount to provided value"
    test "clamps negative values to 0"
    test "clamps values above max_bet"
    test "handles non-numeric input gracefully"
  end

  describe "halve_bet event" do
    test "halves bet_amount (20 -> 10)"
    test "rounds down for odd amounts (15 -> 7)"
    test "does not go below 1"
  end

  describe "double_bet event" do
    test "doubles bet_amount (10 -> 20)"
    test "clamps to max_bet if doubled exceeds it"
  end

  describe "set_max_bet event" do
    test "sets bet_amount to max_bet value"
  end

  # ============ Token Selection ============
  describe "toggle_token_dropdown event" do
    test "toggles show_token_dropdown between true and false"
  end

  describe "select_token event" do
    test "switches to ROGUE token"
    test "switches back to BUX token"
    test "closes token dropdown"
    test "updates header_token assign"
    test "triggers bankroll balance re-fetch for new token (BUXBankroll or ROGUEBankroll)"
  end

  # ============ Drop Ball ============
  describe "drop_ball event — validations" do
    test "rejects when onchain_ready is false — error: 'Game not ready'"
    test "rejects when bet_amount <= 0 — error: 'Invalid bet'"
    test "rejects when balance < bet_amount — error: 'Insufficient balance'"
    test "rejects ROGUE bet below 100 — error: 'Minimum ROGUE bet: 100'"
  end

  describe "drop_ball event — success" do
    test "sets game_state to :dropping"
    test "freezes current_bet to bet_amount at time of placement"
    test "stores ball_path, landing_position, payout, payout_multiplier, won"
    test "pushes drop_ball event to JS with path, landing_position, rows"
    test "pushes place_bet_background event to JS with game/token/amount data"
    test "calls EngagementTracker.deduct_user_token_balance"
  end

  # ============ JS pushEvent Handlers ============
  describe "bet_confirmed event (from JS)" do
    test "stores bet_tx hash"
    test "does not change game_state (animation continues)"
  end

  describe "bet_failed event (from JS)" do
    test "resets game_state to :idle"
    test "refunds balance via EngagementTracker.credit_user_token_balance"
    test "sets error_message with failure reason"
    test "clears ball_path and landing_position"
  end

  describe "ball_landed event (from JS)" do
    test "transitions game_state from :dropping to :result"
    test "generates confetti_pieces for wins >= 5x (100 pieces)"
    test "no confetti for wins < 5x"
    test "no confetti for losses"
  end

  # ============ Reset ============
  describe "reset_game event" do
    test "transitions game_state to :idle"
    test "clears ball_path, landing_position, payout, won"
    test "clears error_message"
    test "pushes reset_ball event to JS"
    test "starts new init_onchain_game async task"
  end

  # ============ Fairness Modal ============
  describe "show_fairness_modal event" do
    test "sets show_fairness_modal to true"
    test "loads fairness_game data for given game_id"
    test "only shows server_seed for :settled games"
    test "hides server_seed for non-settled games"
  end

  describe "hide_fairness_modal event" do
    test "sets show_fairness_modal to false"
    test "clears fairness_game assign"
  end

  # ============ Game History ============
  describe "load-more-games event" do
    test "increments games_offset"
    test "appends new games to recent_games list"
    test "sets games_loading during fetch"
  end

  # ============ Async Handlers ============
  describe "handle_async :init_onchain_game — success" do
    test "sets onchain_ready to true"
    test "sets onchain_game_id"
    test "sets commitment_hash"
    test "sets onchain_initializing to false"
  end

  describe "handle_async :init_onchain_game — failure" do
    test "retries up to 3 times with exponential backoff (1s, 2s, 4s)"
    test "increments init_retry_count on each failure"
    test "sets error_message after 3 failed retries"
    test "sets onchain_initializing to false after final failure"
  end

  describe "handle_async :fetch_house_balance" do
    test "sets house_balance from BUXBankroll available liquidity on success"
    test "calculates max_bet from bankroll liquidity and config maxMultiplier"
    test "keeps defaults on failure (logs warning)"
  end

  describe "handle_async :load_recent_games" do
    test "sets recent_games list on success"
    test "sets games_loading to false"
    test "keeps empty list on failure"
  end

  # ============ PubSub Handlers ============
  describe "handle_info PubSub messages" do
    test "{:bux_balance_updated, balance} updates balances assign"
    test "{:token_balances_updated, balances} updates all token balances"
    test "{:plinko_settled, game_id, tx_hash} updates settlement_tx for current game"
    test "{:plinko_settled, ...} is ignored for non-current game"
    test "{:token_prices_updated, prices} updates rogue_usd_price"
  end

  # ============ Rendering ============
  describe "SVG board rendering" do
    test "renders correct number of pegs for 8 rows (sum 1..8 = 36 pegs)"
    test "renders correct number of pegs for 12 rows (sum 1..12 = 78 pegs)"
    test "renders correct number of pegs for 16 rows (sum 1..16 = 136 pegs)"
    test "renders correct number of landing slots (rows + 1)"
    test "landing slot labels show formatted multipliers"
    test "renders SVG viewBox with correct height per row count"
  end

  describe "game state rendering" do
    test ":idle state shows Drop Ball button"
    test ":dropping state shows animation (button disabled)"
    test ":result state shows payout and Play Again button"
    test ":result state shows Verify Fairness link for settled games"
    test "error_message renders in error banner"
  end
end
```

**Expected test count:** ~80 tests

---

### 15.7 Phase 7: Integration Tests

**File:** `test/blockster_v2/plinko/plinko_integration_test.exs`
**Run:** `mix test test/blockster_v2/plinko/plinko_integration_test.exs`

> **Purpose**: End-to-end flow tests exercising the full pipeline from game init through
> settlement. These test the interaction between PlinkoGame, PlinkoSettler, BuxMinter (mocked),
> EngagementTracker, PubSub, and Mnesia. Not `async: true`.

```elixir
defmodule BlocksterV2.Plinko.PlinkoIntegrationTest do
  use ExUnit.Case

  alias BlocksterV2.{PlinkoGame, PlinkoSettler, EngagementTracker}

  setup do
    :mnesia.clear_table(:plinko_games)
    :ok
  end

  # ============ Full Game Lifecycle ============
  describe "complete game flow: init -> place -> settle" do
    test "BUX win flow: init game, place bet, settle winning bet, verify Mnesia state" do
      # 1. get_or_init_game -> returns game_id, commitment_hash
      # 2. on_bet_placed -> calculates result, writes :placed to Mnesia
      # 3. settle_game -> writes :settled, stores settlement_tx
      # 4. Verify: status == :settled, settled_at != nil, settlement_tx != nil
      # 5. Verify: ball_path, landing_position, payout all populated
    end

    test "BUX loss flow: verify house receives profit"

    test "BUX push flow: verify no house movement"

    test "ROGUE win flow: uses plinko_settle_bet_rogue (different BuxMinter call)"

    test "ROGUE loss flow: uses plinko_settle_bet_rogue"

    test "0x payout flow (8-High center): payout=0, outcome=:lost, status=:settled"
  end

  # ============ Multi-Game Sequences ============
  describe "sequential games" do
    test "nonce increments correctly across 3 sequential games"
    # game1 nonce=0, game2 nonce=1, game3 nonce=2

    test "game reuse: uncommitted game gets reused on second init call"

    test "game NOT reused when nonce is stale (previous game settled, nonce advanced)"

    test "different configs in sequence: 8-Low then 16-High then 12-Med"
  end

  # ============ Balance Integration ============
  describe "balance tracking" do
    test "optimistic deduction: balance decreases by bet_amount before settlement"
    # EngagementTracker.deduct_user_token_balance

    test "refund on failure: balance restored via credit_user_token_balance"

    test "after settlement: sync_user_balances_async called with correct user_id + wallet"

    test "balance not double-deducted if same game settled twice (idempotent)"
  end

  # ============ PubSub Broadcasting ============
  describe "PubSub integration" do
    test "settlement broadcasts {:plinko_settled, game_id, tx_hash} on plinko_settlement channel"
    # Subscribe to "plinko_settlement:#{user_id}", settle game, assert_receive

    test "balance sync broadcasts on bux_balance channel after settlement"
  end

  # ============ Settler Integration ============
  describe "PlinkoSettler integration" do
    test "settler finds and settles :placed game older than 120 seconds" do
      # 1. Create game, advance to :placed
      # 2. Backdate created_at by 130 seconds
      # 3. Call check_and_settle_stuck_bets
      # 4. Verify game is now :settled
    end

    test "settler ignores :placed game newer than 120 seconds"

    test "settler settles multiple stuck games in one pass"

    test "settler handles settlement error on one game without affecting others"
  end

  # ============ Provably Fair Verification ============
  describe "provably fair" do
    test "SHA256(server_seed) matches commitment_hash stored on-chain" do
      # 1. Init game -> get server_seed and commitment_hash
      # 2. Compute: "0x" <> (sha256(hex_decode(server_seed)) |> hex_encode)
      # 3. Assert matches commitment_hash
    end

    test "result is reproducible: same inputs produce identical ball_path and landing"

    test "different server_seed produces different result for same player/bet/config"

    test "client_seed is deterministic from user_id:bet_amount:token:config_index"

    test "combined_seed = SHA256(server_seed:client_seed:nonce)"

    test "ball path byte[i] < 128 = :left, >= 128 = :right for all rows"

    test "landing_position = count(:right in ball_path) for all configs"

    test "full verification chain: seed -> commitment -> path -> landing -> payout"
    # Complete end-to-end verification that a third party could reproduce
  end

  # ============ User Betting Stats ============
  describe "betting stats integration" do
    test "update_user_betting_stats called with correct (user_id, token, amount, won, payout)"

    test "stats accumulate across multiple games for same user"

    test "BUX and ROGUE stats tracked separately"
  end

  # ============ Edge Cases & Error Handling ============
  describe "error handling" do
    test "settle_game with :committed game returns {:error, :bet_not_placed}"

    test "settle_game with missing game returns {:error, :not_found}"

    test "double settlement returns {:ok, ..., already_settled: true}"

    test "on_bet_placed with missing game returns {:error, :not_found}"

    test "get_or_init_game with nil wallet still calculates nonce correctly"
  end

  # ============ Game History ============
  describe "game history" do
    test "load_recent_games returns settled games only, sorted newest first"

    test "load_recent_games pagination: offset=0 limit=5 returns first 5"

    test "load_recent_games pagination: offset=5 limit=5 returns next 5"

    test "load_recent_games returns empty list for user with no settled games"

    test "game history includes all fields needed for fairness modal"
    # game_id, server_seed, commitment_hash, ball_path, landing_position,
    # config_index, bet_amount, payout, status
  end

  # ============ Concurrent Safety ============
  describe "concurrent games" do
    test "two different users can play simultaneously without interference"
    # Init + place + settle for user A and user B concurrently

    test "same user cannot have two :committed games (reuse prevents duplicates)"
  end

  # ============ Config Consistency ============
  describe "config consistency between backend and contract" do
    test "all 9 payout tables in PlinkoGame.ex match Section 2 of plan exactly"
    # This is a compile-time check — read @payout_tables module attribute

    test "config mapping (index -> {rows, risk}) covers all 9 combinations"

    test "no duplicate config indexes"

    test "every config has a corresponding payout table"
  end
end
```

**Expected test count:** ~50 tests

---

### 15.8 Test Summary

| Phase | Test File | Location | Tests | Type |
|-------|-----------|----------|-------|------|
| 1 | `PlinkoGame.test.js` | `contracts/bux-booster-game/test/` | ~75 | Hardhat (Solidity) |
| 2 | `PlinkoGame.test.js` (added section) | `contracts/bux-booster-game/test/` | ~40 | Hardhat (Solidity) |
| 3 | `verify-plinko-deployment.js` | `contracts/bux-booster-game/scripts/` | ~90 assertions | Verification script |
| 4 | `plinko.test.js` | bux-minter repo `test/` | ~35 | Mocha + Supertest |
| 5a | `plinko_math_test.exs` | `test/blockster_v2/plinko/` | ~60 | ExUnit |
| 5b | `plinko_game_test.exs` | `test/blockster_v2/plinko/` | ~45 | ExUnit + Mnesia |
| 5c | `plinko_settler_test.exs` | `test/blockster_v2/plinko/` | ~13 | ExUnit + Mnesia |
| 6 | `plinko_live_test.exs` | `test/blockster_v2_web/live/` | ~80 | ConnCase + LiveViewTest |
| 7 | `plinko_integration_test.exs` | `test/blockster_v2/plinko/` | ~50 | ExUnit + Mnesia + PubSub |
| **Total** | | | **~490** | |

### 15.9 Running All Plinko Tests

```bash
# Elixir backend + frontend tests (phases 5, 6, 7)
mix test test/blockster_v2/plinko/ test/blockster_v2_web/live/plinko_live_test.exs

# Smart contract tests (phases 1, 2)
cd contracts/bux-booster-game && npx hardhat test test/PlinkoGame.test.js

# Deploy verification (phase 3)
cd contracts/bux-booster-game && npx hardhat run scripts/verify-plinko-deployment.js --network rogue

# BUX Minter tests (phase 4)
cd ../bux-minter && npm test -- --grep Plinko
```
