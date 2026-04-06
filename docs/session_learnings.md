# Session Learnings Archive

Historical bug fixes, feature implementations, and debugging notes moved from CLAUDE.md to reduce system prompt size. These are preserved for reference but rarely needed in day-to-day development.

For active reference material, see the main [CLAUDE.md](../CLAUDE.md).

---

## Table of Contents
- [Solana RPC State Propagation: Never Chain Dependent Txs Back-to-Back](#solana-rpc-state-propagation-never-chain-dependent-txs-back-to-back-apr-2026)
- [Solana Tx Reliability: Priority Fees + Confirmation Recovery](#solana-tx-reliability-priority-fees--confirmation-recovery-apr-2026)
- [Payout Rounding: Float.round vs On-Chain Integer Truncation](#payout-rounding-floatround-vs-on-chain-integer-truncation-apr-2026)
- [LP Price Chart History Implementation](#lp-price-chart-history-implementation-apr-2026)
- [Solana Wallet Field Migration Bug](#solana-wallet-field-migration-bug-apr-2026)
- [Non-Blocking Fingerprint Verification](#non-blocking-fingerprint-verification-mar-2026)
- [FateSwap Solana Wallet Tab](#fateswap-solana-wallet-tab-mar-2026)
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
- [AirdropVault V2 Upgrade](#airdropvault-v2-upgrade--client-side-deposits-feb-28-2026)
- [NFTRewarder V6 & RPC Batching](#nftrewarder-v6--rpc-batching-mar-2026)

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

## AirdropVault V2 Upgrade — Client-Side Deposits (Feb 28, 2026)

### Problem
AirdropVault V1 only had `depositFor()` as `onlyOwner`, meaning deposits required the vault admin (BUX Minter backend) to execute. This created an unnecessary server-side dependency for what should be a direct user→contract interaction.

### Solution
Created AirdropVaultV2 inheriting from V1, adding a public `deposit(externalWallet, amount)` function. The user's smart wallet calls `BUX.approve()` + `vault.deposit()` entirely client-side — no minter backend needed for deposits.

### Key Details
- **V2 contract**: `contracts/bux-booster-game/contracts/AirdropVaultV2.sol` — inherits V1, adds `deposit()` using `msg.sender` as blocksterWallet
- **JS hook**: `assets/js/hooks/airdrop_deposit.js` — `needsApproval()` + `executeApprove()` + `executeDeposit()` (same pattern as BuxBooster's `bux_booster_onchain.js`)
- **LiveView flow**: `redeem_bux` → pushes `airdrop_deposit` to JS hook → hook does on-chain tx → pushes `airdrop_deposit_complete` back → LiveView records entry in Postgres
- **Deploy script**: `contracts/bux-booster-game/scripts/upgrade-airdrop-vault-v2.js`
- **`using SafeERC20 for IERC20`**: Must be declared in V2 even though V1 has it — Solidity `using` directives don't automatically apply to child contract functions
- **Mock conflict**: Deleted `contracts/mocks/AirdropVaultV2.sol` (test mock) because it had the same contract name as the real V2

### Settler GenServer
`lib/blockster_v2/airdrop/settler.ex` — GlobalSingleton that auto-settles rounds:
- On startup: recovers state from DB (handles restarts)
- On `create_round`: schedules timer for `end_time`
- On timer: close round (on-chain or RPC fallback) → draw winners → register prizes on Arbitrum
- Uses `Process.send_after` for precise scheduling (not polling)

### Test Fixes
Many airdrop tests were failing because `Airdrop.redeem_bux` calls `deduct_user_token_balance` in Mnesia, but tests never set up a Mnesia balance. Fixed by adding `setup_mnesia` + `set_bux_balance` helpers to both `airdrop_live_test.exs` and `airdrop_integration_test.exs`. Also updated prize amount assertions from old values ($250/$150/$100/$50) to current test pool ($0.65/$0.40/$0.35/$0.12).

---

## NFTRewarder V6 & RPC Batching (Mar 2026)

### Problem
Two background processes in `high-rollers-elixir` made individual RPC calls per NFT, burning ~29,000 Arbitrum RPC calls/hour (QuickNode) and ~21,600 Rogue Chain calls/hour:
- **OwnershipReconciler**: `ownerOf(tokenId)` × 2,414 NFTs every 5 min
- **EarningsSyncer**: `timeRewardInfo(tokenId)` × ~361 special NFTs every 60 sec

### Solution: Two-Pronged Approach

**Arbitrum**: Multicall3 (canonical at `0xcA11bde05977b3631167028862bE2a173976CA11`) wraps N `ownerOf` calls into 1 `eth_call`.

**Rogue Chain**: Upgraded NFTRewarder to V6 with native batch view functions (Multicall3 is NOT on Rogue Chain).

### NFTRewarder V6 Contract Changes
- Added `getBatchTimeRewardRaw(uint256[])` — returns 3 parallel uint256 arrays (startTimes, lastClaimTimes, totalClaimeds)
- Added `getBatchNFTOwners(uint256[])` — returns address array from nftMetadata mapping
- Both are read-only view functions, zero state risk
- **Implementation**: `0xC2Fb3A92C785aF4DB22D58FD8714C43B3063F3B1`
- **Upgrade tx**: `0xed2b7aeeca1e02610d042b4f2d7abb206bf6e4d358c6f351d0e444b8e1899db2`

### Elixir Implementation (high-rollers-elixir)

| File | Change |
|------|--------|
| `lib/high_rollers/contracts/multicall3.ex` | New module — Multicall3 ABI encoding/decoding, aggregate3, aggregate3_batched |
| `lib/high_rollers/contracts/nft_contract.ex` | Added `get_batch_owners/1` via Multicall3 |
| `lib/high_rollers/contracts/nft_rewarder.ex` | Added `get_batch_time_reward_raw/1` and `get_batch_nft_owners/1` |
| `lib/high_rollers/ownership_reconciler.ex` | Refactored `reconcile_batch` to use batch owners; added `maybe_update_rewarder_batch` |
| `lib/high_rollers/earnings_syncer.ex` | Refactored `sync_time_reward_claim_times` to use batch time reward queries |

### Expected Impact

| Process | Before | After (50/batch) | Reduction |
|---------|-------:|------------------:|----------:|
| OwnershipReconciler (Arbitrum) | 2,414 calls/cycle | 49 | 98% |
| EarningsSyncer time rewards (Rogue) | ~361 calls/cycle | 8 | 98% |
| **Hourly total (Arbitrum)** | **~29,000** | **~588** | **98%** |

### Key Learnings
- Rogue Chain RPC intermittently returns 500 on large contract deploys — retry after a few minutes
- Multicall3 ABI encoding requires careful offset calculations for dynamic types (Call3 contains `bytes callData`)
- Old per-NFT functions kept as fallbacks — `reconcile_single_nft/1`, `sync_single_time_reward/1`, `get_owner_of/1`, `get_time_reward_raw/1`

---

## Solana RPC State Propagation: Never Chain Dependent Txs Back-to-Back (Apr 2026)

**Problem**: Coin flip bets were failing with `NonceMismatch` on `PlaceBetSol` even though the on-chain `PlayerState` showed correct values (`nonce`, `pending_nonce`, and `pending_commitment` all matched). The error occurred intermittently, especially on rapid consecutive games.

**Root cause**: Solana RPC state propagation lag between dependent transactions. The flow was:
1. `settle_bet` tx confirms (modifies `PlayerState.nonce`, closes `BetOrder`)
2. Immediately after, `submit_commitment` tx confirms (modifies `PlayerState.pending_nonce`, `PlayerState.pending_commitment`)
3. Player places next bet → wallet sends `place_bet` tx
4. Wallet's RPC (Phantom/Backpack use their own RPCs like Triton) hasn't seen both state changes yet
5. `place_bet` simulation fails because it reads stale `PlayerState`

The critical insight: even the **settler's own QuickNode RPC** showed correct state via `getAccountInfo`, but `simulateTransaction` on the same RPC returned `NonceMismatch`. The simulation engine may resolve to a different slot than `getAccountInfo`, especially when `replaceRecentBlockhash: true` is used.

**What we tried (and failed)**:
- 2s Process.sleep after `submit_commitment` — still failed
- 4s Process.sleep — still failed
- Preflight simulation on settler RPC before returning tx — confirmed NonceMismatch but didn't fix it
- JS retry loop (3 retries, 2s apart) — all 3 attempts failed over 6 seconds

**Fix**: Removed the `pre_init_next_game` pattern that submitted the next commitment immediately after settlement. Instead, `submit_commitment` now only happens when the player clicks "Play Again" (triggers `init_game` async). The natural UI delay (player picking predictions, choosing bet amount) gives all RPCs time to propagate state from the previous settlement + commitment.

**Rule**: On Solana, NEVER chain dependent transactions back-to-back and expect the next operation to see updated state immediately — even on the same RPC endpoint. If tx B reads state modified by tx A, ensure there is meaningful time (user interaction, explicit delay, or a fresh user action trigger) between A's confirmation and B's submission. This applies to ALL Solana code: settler services, client-side JS, scripts.

**Also fixed in this session**:
- `calculate_max_bet`: was using `net_lamports * 10 / 10000` (0.1%) instead of `net_lamports * 100 / 10000` (1%) — max bet was 10x too low
- Play Again button now hidden until `settlement_status == :settled`
- Token icons (SOL/BUX) and capitalized labels restored in game history table
- Expired bet reclaim banner and `reclaim_stuck_bet` handler added

---

## Solana Tx Reliability: Priority Fees + Confirmation Recovery (Apr 2026)

**Symptom**: Settler txs (commitments and settlements) frequently timing out on devnet. Bets would show results but settlement got stuck. After 3-4 bets, game init would block.

**Investigation path**: Initially assumed devnet RPC congestion. User correctly pushed back — bet placements (via wallet) worked fine while settlements (via settler) failed. The difference: wallets have their own well-provisioned RPC; the settler was using QuickNode devnet with no priority fees.

**Root causes found (in order)**:
1. **No priority fees** — all settler and user-signed txs had zero compute unit price. Devnet validators routinely drop zero-fee txs.
2. **Default preflight used "finalized" commitment** — added ~15s latency before the tx was even sent to the leader.
3. **No rebroadcasting** — if a leader dropped the tx, it was never resent.
4. **Deprecated confirmation API** — `confirmTransaction(sig, "confirmed")` has a blanket 30s timeout with no blockhash expiry awareness.
5. **Txs landing but confirmation missed** — the most insidious issue. The tx would land on-chain during the rebroadcast window, but `confirmTransaction` would time out. On retry, the settler rebuilt the SAME instruction with a fresh blockhash — but the bet_order PDA was already closed by the first (successful) tx, so attempt 2 failed with `AccountNotInitialized`.

**Fix**: `sendSettlerTx` in rpc-client.ts — builds fresh blockhash per attempt, rebroadcasts every 2s, and critically: after blockhash expiry, checks `getSignatureStatus` on the original signature before retrying. If the tx landed ("Tx landed despite timeout"), returns success instead of retrying with a stale instruction.

**Key learning**: On Solana, "transaction not confirmed" ≠ "transaction failed." Always check signature status before retrying write operations that modify/close accounts.

---

## Payout Rounding: Float.round vs On-Chain Integer Truncation (Apr 2026)

**Symptom**: `PayoutExceedsMax` error during settlement when betting near max bet. Also, wallet simulation revert when clicking the max bet button.

**Root cause**: Elixir's `Float.round(bet * multiplier / 10000, decimals)` can round UP, producing a value 1-2 lamports above what the on-chain Rust program computes with integer division (which always truncates DOWN).

Example: bet = 0.123456789 SOL, multiplier = 10200 BPS
- **Rust**: `(123456789 * 10200) / 10000 = 125,925,924` lamports (truncated)
- **Elixir Float.round**: `0.125926` → 125,926,000 lamports (**exceeds by 76 lamports**)

**Two locations affected**:
1. `calculate_payout` in coin_flip_game.ex — payout sent to settle_bet exceeded on-chain max_payout
2. `calculate_max_bet` in coin_flip_live.ex — max bet displayed to user exceeded on-chain per-difficulty limit. Had an additional subtlety: on-chain does TWO integer divisions (base then max_bet), each truncating. Single float operation skips the intermediate truncation.

**Fix**: Both functions now replicate on-chain integer math exactly — convert to lamports, use `div` for each step, convert back. Verified with test: old = 125,926,000 (exceeds), new = 125,925,924 (matches Rust exactly).

---

## LP Price Chart History Implementation (Apr 2026)

Ported FateSwap's LP price chart approach to Blockster pool pages. Key decisions and learnings:

**Architecture choice**: FateSwap uses ETS ordered_set (in-memory, fast range queries) + PostgreSQL (persistence). Blockster uses Mnesia ordered_set which serves both roles (in-memory + persistent). The `dirty_index_read` on `:vault_type` secondary index returns all records for a vault, then filters in Elixir — acceptable at current scale (~1 record/min = ~43k/month).

**Downsampling**: Copied FateSwap's exact approach — group by time bucket (`div(timestamp, interval)`), take last point per bucket. Timeframes: 1H=60s, 24H=5min, 7D=30min, 30D=2hr, All=1day. Added a guard to skip downsampling when <500 raw points — without this, a fresh chart with only minutes of data gets collapsed to 1-2 points on the 24H view.

**Real-time chart updates on settlement**: FateSwap computes LP price incrementally from settlement data (vault_delta = amount - payout - fees). Blockster instead fetches fresh pool stats from the settler HTTP endpoint after each settlement — simpler, one extra HTTP call to localhost, acceptable latency. The `LpPriceHistory.record/3` accepts `force: true` to bypass the 60s throttle for settlement-triggered updates.

**PubSub chain**: `CoinFlipGame.settle_game` → broadcasts `{:bet_settled, vault_type}` on `"pool:settlements"` → `LpPriceTracker` receives, fetches stats, records price → broadcasts `{:chart_point, point}` on `"pool_chart:#{vault_type}"` → `PoolDetailLive` receives, pushes `"chart_update"` to JS → `series.update(point)`.

**JS changes**: Event key changed from `points` to `data` to match FateSwap. Added deferred init with `requestAnimationFrame` + retry if container width=0 (race condition on mount). Debounced resize observer (100ms).

**Restart required**: LpPriceTracker GenServer must restart to subscribe to the new `"pool:settlements"` PubSub topic (subscription happens in `:registered` handler, not hot-reloadable).

---

## Solana Wallet Field Migration Bug (Apr 2026)

**Problem**: BUX tokens were never minted for Solana users despite engagement tracking recording rewards correctly. Users earned BUX from reading but balance stayed at 0.

**Root cause (3 bugs)**:
1. **Wrong wallet field** (main cause): All mint/sync calls across the codebase used `smart_wallet_address` (EVM ERC-4337 smart wallet), which is nil for Solana users. Solana users' wallet lives in `wallet_address`. Since the field was nil, the `if wallet && wallet != ""` guard failed and minting was silently skipped.

2. **Wrong response key**: The Solana settler service returns `{ "signature": "..." }` in mint responses, but Elixir code pattern-matched on `"transactionHash"` (EVM format). This caused pool deductions, video engagement updates, and `:mint_completed` messages to silently skip even if a mint somehow succeeded.

3. **`and` vs `&&` operator**: Line 568 in `show.ex` used `wallet && wallet != "" and recorded_bux > 0`. When `wallet` is nil, `wallet && wallet != ""` short-circuits to `nil`, then `nil and ...` raises `BadBooleanError` because `and` requires strict booleans. Fixed by using `&&` throughout.

**Files fixed (wallet field — `smart_wallet_address` → `wallet_address`)**:
- `post_live/show.ex` — article read, video watch, X share minting (3 locations)
- `referrals.ex` — referee signup bonus, referrer reward lookup and mint
- `telegram_bot/promo_engine.ex` — promo BUX credits
- `admin_live.ex` — admin send BUX/ROGUE
- `share_reward_processor.ex` — share reward processing
- `event_processor.ex` — AI notification BUX credits
- `checkout_live/index.ex` — post-checkout balance sync
- `orders.ex` — buyer wallet, affiliate payout minting, affiliate earning recording
- `notification_live/referrals.ex` — referral link URL

**Files fixed (response key — `"transactionHash"` → `"signature"`)**:
- `post_live/show.ex` — article read and video watch mint responses
- `referrals.ex` — referrer reward mint response
- `share_reward_processor.ex` — share reward mint response
- `admin_live.ex` — admin send BUX response
- `member_live/show.ex` — claim read/video reward responses
- `orders.ex` — affiliate payout tx hash (`"txHash"` → `"signature"`)

**Key lesson**: When migrating from EVM to Solana, the wallet field name changes (`smart_wallet_address` → `wallet_address`) and API response keys change (`transactionHash` → `signature`). A global search for the old field/key names should be part of any chain migration checklist.

**Note**: `smart_wallet_address` references in schema definitions, account creation, auth controllers, admin display templates, bot system, and DB queries were intentionally left as-is — those are either EVM-specific code paths, display-only, or schema fields that must match the DB column.

---

## Non-Blocking Fingerprint Verification (Mar 2026)

**Problem**: Users on Safari, Firefox, Brave, or with ad blockers got a hard block error ("Unable to verify device. Please use Chrome or Edge browser to sign up.") during signup because FingerprintJS Pro couldn't load or execute.

**Root cause**: The client-side JS in `home_hooks.js` required a successful fingerprint before proceeding with wallet connection and signup. If `getFingerprint()` returned null (FingerprintJS blocked), the user was stopped with an alert and could not sign up at all.

**Fix (Mar 25, 2026)**:
- **Client-side** (`assets/js/home_hooks.js`): Removed hard block — fingerprint failure now logs a warning and proceeds. Used optional chaining (`fingerprintData?.visitorId`) for safe property access when sending null to server.
- **Server-side** (`lib/blockster_v2/accounts.ex`): Made `fingerprint_id` and `fingerprint_confidence` optional in `authenticate_email_with_fingerprint`. When no fingerprint data is provided, all device verification is skipped and signup proceeds normally.
- **Config** (`config/runtime.exs`): Added `:test` to `skip_fingerprint_check` environments so test env skips FingerprintJS HTTP calls like dev does.
- **Refactored skip logic**: `SKIP_FINGERPRINT_CHECK` now only skips the HTTP call to FingerprintJS API — fingerprint DB operations (conflict detection, device tracking) still run when fingerprint data is present.

**Result**: All browsers can sign up. Anti-sybil protection still applies when FingerprintJS works (Chrome, Edge, no ad blockers). Users whose browsers block FingerprintJS sign up without device tracking.

**Also fixed**: 71 pre-existing test failures across shop (order.total_amount → total_paid), notifications (missing category validation/filtering, stale defaults), referrals (reward amounts 100→500), and telegram (env check ordering).

---

## FateSwap Solana Wallet Tab (Mar 2026)

Added a new "FateSwap" tab to the High Rollers site that lets NFT holders register their Solana wallet address for cross-chain revenue sharing from FateSwap.io.

### Mnesia Schema: Separate Table vs Field Addition
Adding a field to an existing Mnesia table (`hr_users`) is problematic:
- Existing records on disk have N elements; new schema expects N+1
- `mnesia:transform_table/3` can fail with `:bad_type` if disc_copies and schema mismatch
- `dirty_write` of records with extra fields fails if table definition hasn't been updated

**Solution**: Use a separate Mnesia table (`hr_solana_wallets`) for new data. Zero migration risk, no schema conflicts.

### MnesiaCase Test Infrastructure Fix
LiveView tests using both `MnesiaCase` + `ConnCase` were failing (16 tests) because `MnesiaCase.setup` called `:mnesia.stop()` which crashed the supervision tree (MnesiaInitializer → cascade → Endpoint dies → ETS table gone).

**Fix**: `MnesiaCase` now detects if the application is running and uses non-destructive setup — `mnesia:clear_table` instead of stop/restart. This preserves the supervision tree while still isolating test data.

### Sales Module Bug Fixes
- `get_sales/2` was filtering on `mint_price` instead of `mint_tx_hash` — unminted NFTs with default price passed the filter
- Sorting was by `token_id` desc instead of `created_at` desc — pagination tests expected chronological order
- `format_eth/1` used `decimals: 3` instead of `decimals: 6`

### Solana Transaction Confirmation — Websockets vs Polling (2026-04-05)

**Problem**: The settler's `sendSettlerTx` and client-side `coin_flip_solana.js` used Solana web3.js `confirmTransaction` which relies on websocket subscriptions internally. This caused:
1. Second bet settlement consistently slower than first — concurrent `sendSettlerTx` calls (commitment + settlement) created competing websocket subscriptions and rebroadcast `setInterval` loops on the same shared `Connection` object
2. Unreliable on devnet — websocket connections drop, delay, or miss notifications
3. Unnecessary complexity — rebroadcast every 2s, 3-attempt blockhash retry loops, signature status checks on expiry

**Root cause**: In EVM, `tx.wait()` uses simple HTTP polling (`eth_getTransactionReceipt`). The Solana code was doing something fundamentally different — websocket subscriptions + manual rebroadcasting — which is fragile and creates contention when multiple txs are in flight.

**Fix**: Replaced all confirmation with `getSignatureStatuses` polling — the Solana equivalent of `tx.wait()`:
- `rpc-client.ts`: new `waitForConfirmation()` polls every 2s, 60s timeout. `sendSettlerTx` simplified to single send + poll. Removed `getBlockhashWithExpiry`, rebroadcast intervals, multi-attempt retry logic
- `airdrop-service.ts`: 4 functions switched from `confirmTransaction` to `waitForConfirmation`
- `coin_flip_solana.js`: new `pollForConfirmation()` replaces `confirmTransaction` for bet placement and reclaim

**Key insight**: `sendRawTransaction` with `maxRetries: 5` already tells the RPC node to handle delivery retries. Application-level rebroadcasting on top of that is redundant and creates RPC contention.
