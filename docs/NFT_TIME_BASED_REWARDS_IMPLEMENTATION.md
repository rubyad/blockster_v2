# NFT Time-Based Rewards Implementation Plan

**Date**: January 6, 2026
**Status**: ✅ Phase 1, 2, 3, 4, 5, 6 & 7 Complete - Live on Mainnet
**Objective**: Implement time-based ROGUE token distribution to 361 newly minted NFTs (token IDs 2340-2700) over 180 days.

---

## Deployment Status (January 6, 2026)

### Completed ✅

| Step | Status | Details |
|------|--------|---------|
| Phase 1: Smart Contract | ✅ Complete | NFTRewarder V3 implementation with all time reward functions |
| Unit Tests | ✅ 74 Passing | All V2 + V3 tests passing |
| V3 Upgrade | ✅ Deployed | Implementation: `0xd0d97034E6ebf0A839F9EDbE213eb0B26B8f9Ef6` |
| initializeV3() | ✅ Called | All 8 hostess time reward rates set |
| Time Pool Deposit | ✅ 5.6B ROGUE | Full pool deposited (5,614,272,000 ROGUE) |
| Pre-registered NFTs | ✅ Started | NFTs 2340-2342 time rewards active |
| Phase 3: Backend Services | ✅ Complete | TimeRewardTracker, API endpoints, EventListener integration |
| Phase 4: Frontend UI | ✅ Complete | Real-time counters, special NFT styling, combined withdrawals |

### Contract Addresses

| Contract | Address | Network |
|----------|---------|---------|
| NFTRewarder Proxy | `0x96aB9560f1407586faE2b69Dc7f38a59BEACC594` | Rogue Chain (560013) |
| NFTRewarder V3 Impl | `0xd0d97034E6ebf0A839F9EDbE213eb0B26B8f9Ef6` | Rogue Chain (560013) |
| NFTRewarder V4 Impl | `0xD41D2BD654cD15d691bD7037b0bA8050477D1386` | Rogue Chain (560013) |
| NFTRewarder V5 Impl | `0x51F7f2b0Ac9e4035b3A14d8Ea4474a0cf62751Bb` | Rogue Chain (560013) |

### Key Transactions

| Action | TX Hash | Block |
|--------|---------|-------|
| V3 Upgrade | `0x3b7968c7e61ad5563df23a1e48ad93a76d0b51e66e7124cb7d57793510f11d08` | 109571305 |
| V4 Upgrade (bug fix) | `0x6c8dbabb9c213cf33df2eb45971d5b67f25f12eb491e6c6a010917b24a8bdc91` | 109614643 |
| Deposit 1B ROGUE | `0x11bc818e422008ba07349f3ffd8a2bea88f53f0184c9f5ff05525a7b2473e8a8` | 109573488 |
| Deposit 3.5B ROGUE | `0xd94787f7a8956d2cfbcf68ba6e1782e7e781ef0c7167c7a5efe498f1a896b3c0` | 109574083 |
| Deposit 1K ROGUE (test) | `0x3a20c4e23509f9a66bf7abc2fed7a0b1ce75f31626ae27e5e1bafcde0a52ea17` | 109601993 |
| Deposit 1.1B ROGUE (final) | `0x06b9dc5f07b55276874e8d66b86430f5ec9b5974744f0cf8c4fb94acfd45c644` | 109602065 |
| Start NFT #2340 | `0x981ffad09fbabab13969d7e1a98a3fbc2c7638d02066b85e2ae36f40207e67cc` | 109574708 |
| Start NFT #2341 | `0xa8851fec1992f1385930389f41d673f34f0c5755eb67a61bf9e777869e63edda` | 109574711 |
| Start NFT #2342 | `0x20635e258f856aff4b9d9ebabb57ab08fdf53a2426b26a3b5d1eb6cb70c86d85` | 109574712 |

### Current Pool Status

- **Pool Deposited**: 5,614,272,000 ROGUE ✅
- **Pool Remaining**: 5,614,272,000 ROGUE
- **Target Pool**: 5,614,272,000 ROGUE ✅ **FULLY FUNDED**

### Active Time Rewards

| NFT | Hostess | Start Time | End Time | Status |
|-----|---------|------------|----------|--------|
| #2340 | Cleo (80x) | Jan 6, 2026 21:52 UTC | Jul 5, 2026 21:52 UTC | ✅ Active |
| #2341 | Aurora (50x) | Jan 6, 2026 21:52 UTC | Jul 5, 2026 21:52 UTC | ✅ Active |
| #2342 | Scarlett (40x) | Jan 6, 2026 21:52 UTC | Jul 5, 2026 21:52 UTC | ✅ Active |

### Pending Tasks

- [x] Deposit remaining 1,114,272,000 ROGUE to reach full pool ✅ (Jan 6, 2026)
- [x] Phase 3: Backend services for event listening and auto-registration
- [x] Phase 4: Frontend UI for time reward display
- [x] Run sync script: `node server/scripts/sync-time-rewards.js` ✅ (Jan 6, 2026)
- [x] Phase 5: Aggregate Totals Integration - Backend ✅ (Jan 6, 2026)
- [x] Phase 5: Update revenues API to return time reward stats ✅ (Jan 6, 2026)
- [x] Phase 5: Update UI to show combined APY/24h in Gallery tab ✅ (Jan 6, 2026)
- [x] Phase 6: Latest Payouts Table UI clarifications ✅ (Jan 6, 2026)
- [x] Phase 7: WebSocket broadcasts for SPECIAL_NFT_STARTED and TIME_REWARD_CLAIMED ✅ (Jan 6, 2026)
- [x] V4 Bug Fix: pendingTimeReward() division error ✅ (Jan 6, 2026)
- [x] Data Consistency: OwnerSyncService now syncs missing sales/affiliates on startup ✅ (Jan 7, 2026)

### V4 Bug Fix (January 6, 2026)

**Problem**: `pendingTimeReward()` was returning ~1e18 times smaller values than expected.

**Root Cause**: The function was incorrectly dividing by `1e18`:
```solidity
// WRONG - was dividing when it shouldn't
pending = (ratePerSecond * timeElapsed) / 1e18;

// CORRECT - ratePerSecond is already in wei, so just multiply
pending = ratePerSecond * timeElapsed;
```

The `ratePerSecond` is stored in wei (e.g., `1.062454e18` for Aurora). Multiplying by `timeElapsed` (seconds) gives wei directly. The `/1e18` was incorrect.

**Impact**: Token 2341 showed `0.000000000000018 ROGUE` pending instead of `18,424 ROGUE`.

**Files Fixed** (4 locations in NFTRewarder.sol):
- Line 599: `pendingTimeReward()` - removed `/1e18`
- Line 1289: `getTimeRewardInfo()` totalFor180Days - removed `/1e18`
- Line 1341: `getEarningsBreakdown()` pendingNow - removed `/1e18`
- Line 1350: `getEarningsBreakdown()` totalAllocation - removed `/1e18`

**Deployment**:
- New Implementation: `0xD41D2BD654cD15d691bD7037b0bA8050477D1386`
- Upgrade TX: `0x6c8dbabb9c213cf33df2eb45971d5b67f25f12eb491e6c6a010917b24a8bdc91`
- Script: `contracts/bux-booster-game/scripts/upgrade-nftrewarder-v4.js`

### V5 Upgrade (January 6, 2026)

**New Function**: Added `getUserPortfolioStats(address _owner)` - Combined view function for user totals across all NFT types.

**Purpose**: Links from "Total Earned" and "Pending Balance" boxes in My Earnings tab now go to this function on Roguescan, showing combined totals (revenue + time rewards) instead of just revenue share.

**Returns**:
- `revenuePending` - Total pending revenue share rewards
- `revenueClaimed` - Total claimed revenue share rewards
- `timePending` - Total pending time-based rewards (special NFTs)
- `timeClaimed` - Total claimed time-based rewards
- `totalPending` - Combined pending (revenue + time)
- `totalEarned` - Total earned across all reward types
- `nftCount` - Number of NFTs owned
- `specialNftCount` - Number of special NFTs (with time rewards)

**Deployment**:
- New Implementation: `0x51F7f2b0Ac9e4035b3A14d8Ea4474a0cf62751Bb`
- Function Selector: `0xd8824b05`
- Script: `contracts/bux-booster-game/scripts/upgrade-nftrewarder-v5-manual.js`

**Frontend Updates**:
- Updated `NFT_REWARDER_IMPL_ADDRESS` in `high-rollers-nfts/public/js/config.js`
- Added `getUserPortfolioStats: '0xd8824b05'` to `NFT_REWARDER_SELECTORS`
- Updated top box links in `revenues.js` to use this new function for deep linking

### Data Consistency Fix (January 7, 2026)

**Problem**: The app was not picking up latest NFT mints and ownership transfers. Specifically:
- Token #2342 was missing from the `nfts` table
- Tokens #2340, #2341 ownership not updated after transfers
- Tokens #1942, #2340, #2341 were in `nfts` table but missing from `sales` table
- Tokens #2340, #2341, #2342 were missing affiliate earnings records

**Root Cause**: The `OwnerSyncService` had several issues:
1. **Off-by-one bug**: Started sync at `totalSupply` (2342) instead of checking from DB max token (2341), so token 2342 was never synced
2. **No startup data consistency checks**: Missing tokens in related tables were never detected
3. **Full sync only ran every 30 minutes**: Too slow to catch recent transfers

**Solution**: Comprehensive startup data consistency checks added to `OwnerSyncService`:

1. **On startup**, service now:
   - Gets on-chain supply and compares to DB max token
   - Syncs any missing tokens to `nfts` table
   - Runs `syncMissingSales()` - finds tokens in `nfts` but not in `sales`, fetches affiliate info from contract
   - Runs `syncMissingAffiliates()` - finds sales with NULL affiliate or missing `affiliate_earnings` records
   - Runs full owner sync for recent transfers

2. **New database methods** (`server/services/database.js`):
   - `getMaxTokenId()` - returns highest token_id in nfts table
   - `getMissingSalesTokens()` - LEFT JOIN to find tokens in nfts but not sales
   - `getSalesMissingAffiliates()` - finds sales with missing affiliate data
   - `updateSaleAffiliates(tokenId, affiliate, affiliate2)` - updates sale with affiliate addresses
   - `affiliateEarningExists(tokenId, tier)` - checks if affiliate earning record exists

3. **New API endpoint** (`server/routes/api.js`):
   - `POST /api/sync-owners` - triggers manual full owner sync (runs in background)

4. **Interval changes**:
   - Quick sync (new mints): Every 30 seconds
   - Full owner sync: Every 10 minutes (was 30 minutes)

**Files Modified**:
- `server/services/ownerSync.js` - Added `syncMissingSales()`, `syncMissingAffiliates()`, updated startup sequence
- `server/services/database.js` - Added 5 new methods
- `server/routes/api.js` - Added `/api/sync-owners` endpoint

**Result**: App now automatically syncs:
- Missing NFTs from `nfts` table
- Missing sales records from `sales` table
- Missing affiliate info (both in `sales` and `affiliate_earnings` tables)
- Ownership transfers via full sync every 10 minutes

### Mint Tab Real-Time Updates (January 6, 2026)

**Problem**: Mint tab stats boxes ("Total Rewards Received", "Last 24 Hours") only showed revenue sharing, not combined with time rewards. Also, they only updated on page load and WebSocket sync (~10 seconds), not in real-time.

**Solution**:

**Backend Changes** (`server/routes/revenues.js`):
- `/stats` endpoint now returns combined totals:
  - `combinedTotal` - revenue + time rewards total
  - `combined24Hours` - revenue + time 24h
  - `timeRewardsTotal` - time rewards only total
  - `timeRewards24Hours` - time rewards only 24h

**Frontend Changes**:

1. **app.js** (`loadMintRevenueStats()`):
   - Stores revenue-only values in data attributes (`data-revenue-total`, `data-revenue-24h`)
   - Displays combined values from API on initial load
   - TimeRewardCounter updates these in real-time

2. **timeRewardCounter.js**:
   - Added `getGlobalTotalEarned(now)` - calculates total time rewards earned since start
   - Added `updateMintTabStats(globalTimeTotal, global24h)` - updates Mint tab boxes every second
   - `updateUI()` now calls `updateMintTabStats()` to update Mint tab in real-time

**Result**: Mint tab stats boxes now:
- Show combined revenue + time rewards
- Update every second (real-time counting)
- No flashing between revenue-only and combined values

### Phase 7 Implementation Details (January 6, 2026)

**Server-Side Changes:**
- `server/services/timeRewardTracker.js` - Added `broadcastTimeRewardClaimed()` method
- `server/routes/revenues.js` - Added broadcast call after successful time reward claim

**Client-Side Changes:**
- `public/js/app.js` - Added WebSocket handlers for:
  - `SPECIAL_NFT_STARTED` - Refreshes stats and My NFTs when a new special NFT is registered
  - `TIME_REWARD_CLAIMED` - Refreshes earnings and updates time reward counter when claim succeeds

### Phase 5 Implementation Details (January 6, 2026)

**Backend Changes - Complete:**

**Files Modified:**
- `server/services/earningsSyncService.js` - Added time reward integration:
  - Constructor now accepts `timeRewardTracker` parameter
  - Added `isSpecialNFT()` helper method
  - Added `calculateTime24hEarnings()` - calculates 24h time earnings per NFT
  - Added `getTimePending()` - gets pending time rewards for NFT
  - Added `getTimeTotalEarned()` - gets total time rewards earned for NFT
  - Added `calculateTimeAPY()` - calculates annualized APY from 180-day rate
  - Added `getGlobalTime24h()` - sum of all special NFT 24h earnings
  - Added `getHostessTime24h()` - 24h earnings per hostess type
  - Updated `syncHostessStats()` to calculate and store time reward values separately

- `server/services/database.js` - Added new columns to `hostess_revenue_stats`:
  - `time_24h_per_nft` - Time reward 24h earnings per NFT
  - `time_apy_basis_points` - Time reward APY in basis points
  - `special_nft_count` - Count of special NFTs for this hostess type
  - Added migration for existing databases (ALTER TABLE)

- `server/index.js` - Wired up TimeRewardTracker to EarningsSyncService

**Design Decision:** Revenue sharing and time reward values are stored **separately** in the database. Combined totals are calculated on-the-fly by the API/UI when needed. This keeps data normalized and avoids storing redundant calculated values.

### Phase 3 Implementation Details (January 6, 2026)

**Files Created:**
- `server/services/timeRewardTracker.js` - Main service for time-based rewards
- `server/scripts/sync-time-rewards.js` - Script to sync existing special NFTs from blockchain

**Files Modified:**
- `server/services/database.js` - Added 3 new tables and 11 database methods
- `server/routes/revenues.js` - Added 6 new API endpoints for time rewards
- `server/services/eventListener.js` - Auto-track time rewards after NFT registration
- `server/services/adminTxQueue.js` - Added `claimTimeRewards` method
- `server/config.js` - Added time reward ABI functions
- `server/index.js` - Initialize and wire up TimeRewardTracker

**New Database Tables:**
| Table | Purpose |
|-------|---------|
| `time_reward_nfts` | Tracks special NFTs with start time, claim history |
| `time_reward_claims` | Records each claim transaction |
| `time_reward_global_stats` | Pool statistics (deposited, remaining, claimed) |

**New API Endpoints:**
| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/revenues/time-rewards/stats` | GET | Global time reward statistics |
| `/api/revenues/time-rewards/nft/:tokenId` | GET | Single NFT time reward info |
| `/api/revenues/time-rewards/user/:address` | GET | All time rewards for wallet |
| `/api/revenues/time-rewards/static-data` | GET | Static data for client calculations (cacheable 60s) |
| `/api/revenues/time-rewards/claim` | POST | Claim time rewards |
| `/api/revenues/time-rewards/sync` | POST | Sync from blockchain (admin) |

**Key Features:**
1. **Zero blockchain calls at runtime** - TimeRewardTracker calculates earnings locally using stored `startTime` and hardcoded rates
2. **Automatic tracking** - EventListener auto-tracks special NFTs (2340-2700) after `registerNFT()` succeeds
3. **Ownership sync** - When NFT is transferred, local database is updated for accurate wallet queries
4. **WebSocket broadcasts** - `SPECIAL_NFT_STARTED` event sent when new special NFT registered

**Sync Script Usage:**
```bash
# Sync all existing special NFTs from blockchain
cd high-rollers-nfts
node server/scripts/sync-time-rewards.js

# Sync pool stats only
node server/scripts/sync-time-rewards.js --pool-only

# Sync specific token
node server/scripts/sync-time-rewards.js --token 2340

# Sync range
node server/scripts/sync-time-rewards.js --range 2340-2345
```

### Phase 4 Implementation Details (January 6, 2026)

**Files Created:**
- `public/js/timeRewardCounter.js` - Client-side real-time counter class with zero database queries

**Files Modified:**
- `public/js/revenues.js` - Updated Roguescan deep links, combined withdrawal, special NFTs section rendering
- `public/js/ui.js` - Added special NFT visual treatment, `isSpecialNFT()`, `formatTimeRewardAmount()`, `formatTimeRemaining()`
- `public/js/app.js` - Added sorting by token_id descending, TimeRewardCounter initialization, wallet event handlers
- `public/css/styles.css` - Added `.special-nft-glow` class with animated golden border
- `public/index.html` - Added special NFTs section HTML, included timeRewardCounter.js script
- `docs/nft_revenues.md` - Added NFTRewarder Impl V3 address

**Key Features:**

1. **Special NFT Visual Treatment**
   - Golden animated glow border (CSS animation)
   - "⭐ SPECIAL" badge on card
   - Purple glow on hover disabled for special cards (to not interfere with golden glow)
   - Sorting: My NFTs grid and Earnings table sorted by token_id descending (newest first)

2. **Real-Time Counter Animation (TimeRewardCounter class)**
   - Zero database queries at runtime - pure client-side math
   - 8 hardcoded rates matching contract exactly (2.125, 1.912, 1.700, 1.487, 1.275, 1.062, 0.850, 0.637 ROGUE/sec)
   - Methods: `initialize()`, `getPending()`, `getTotals()`, `get24hEarnings()`, `updateUI()`, `onClaimed()`
   - 1-second UI update loop for real-time counters
   - Helper functions: `formatROGUE()` (K/M suffixes), `formatTimeRemaining()` (days/hours/minutes)

3. **UI Integration**
   - Time rewards display on NFT cards (pending, rate, remaining, 180d total)
   - Special NFTs section in My Earnings (Total Earned, Pending, 24h, 180d Total, APY with USD values)
   - Combined withdrawal claims both revenue sharing AND time rewards
   - Data attributes for counter updates: `data-time-reward-token`, `data-time-remaining-token`

4. **Roguescan Deep Links Fixed**
   - Updated `source_address` parameter from old impl `0x2634727150cf1B3d4D63Cd4716b9B19Ef1798240` to new impl `0xd0d97034E6ebf0A839F9EDbE213eb0B26B8f9Ef6`

---

## Executive Summary

This document outlines the implementation of a new time-based reward system for High Rollers NFTs. When a new NFT is minted (token IDs 2340-2700), it begins a **180-day countdown at the exact moment `registerNFT()` is called** on the NFTRewarder contract on Rogue Chain. During this period, the NFT passively earns ROGUE tokens every second based on its multiplier tier. This system is **separate from** the existing revenue sharing from BUX Booster losses, which continues to operate for all NFTs.

### Key Design Decision: Start Time = registerNFT() Call

The 180-day countdown starts when:
1. User mints an NFT on Arbitrum (via Chainlink VRF)
2. EventListener detects the `NFTMinted` event
3. Server calls `registerNFT(tokenId, hostessIndex, owner)` on NFTRewarder (Rogue Chain)
4. **At this exact `block.timestamp`, the countdown begins**

This approach:
- Reuses the existing `registerNFT()` function (minimal contract changes)
- Guarantees consistency between registration and time reward start
- Avoids race conditions or separate admin calls

### Key Numbers

| Property | Value |
|----------|-------|
| Total ROGUE to Deposit | 5,614,272,000 ROGUE |
| NFT Range | Token IDs 2340-2700 (361 NFTs) |
| Distribution Period | 180 days (15,552,000 seconds) |
| ROGUE per NFT (average) | ~15,552,000 ROGUE |
| Approx USD Value per NFT | ~$1,024 (at $0.0001/ROGUE) |
| ETH Equivalent per NFT | ~0.32 ETH |

### Per-Hostess ROGUE Distribution

Based on expected probability distribution:

| Multiplier | Hostess | Rarity | Expected Count | ROGUE/NFT | Total ROGUE |
|------------|---------|--------|----------------|-----------|-------------|
| 100x | Penelope Fatale | 0.5% | 2 | 33,044,567 | 66,089,135 |
| 90x | Mia Siren | 1.0% | 4 | 29,740,111 | 118,960,443 |
| 80x | Cleo Enchante | 3.5% | 13 | 26,435,654 | 343,663,501 |
| 70x | Sophia Spark | 7.5% | 27 | 23,131,197 | 624,542,324 |
| 60x | Luna Mirage | 12.5% | 45 | 19,826,740 | 892,203,320 |
| 50x | Aurora Seductra | 25.0% | 90 | 16,522,284 | 1,487,005,533 |
| 40x | Scarlett Ember | 25.0% | 90 | 13,217,827 | 1,189,604,426 |
| 30x | Vivienne Allure (Ember) | 25.0% | 90 | 9,913,370 | 892,203,320 |
| | **TOTAL** | | **361** | | **5,614,272,000** |

**Note**: Actual distribution will vary based on Chainlink VRF randomness during minting.

---

## System Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                          TIME-BASED REWARDS ARCHITECTURE                                 │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                          │
│  ROGUE CHAIN (560013)                          ARBITRUM ONE (42161)                     │
│                                                                                          │
│  ┌─────────────────────────────┐               ┌─────────────────────────────┐          │
│  │    NFTRewarder.sol V3       │               │    High Rollers NFT         │          │
│  │    (UUPS Proxy)             │               │    (Existing Contract)      │          │
│  │                             │               │                             │          │
│  │  NEW: Time-Based Rewards    │   ◄────────   │    NFTMinted event          │          │
│  │  - depositTimeRewards()     │   Server      │    (Chainlink VRF)          │          │
│  │  - startTimeReward()        │   Sync        │                             │          │
│  │  - claimTimeReward()        │               └─────────────────────────────┘          │
│  │  - getTimeRewardEarnings()  │                                                        │
│  │                             │                                                        │
│  │  EXISTING: Revenue Sharing  │               ┌─────────────────────────────┐          │
│  │  - receiveReward()          │               │    high-rollers-nfts        │          │
│  │  - withdrawTo()             │               │    Node.js App              │          │
│  │                             │               │                             │          │
│  └─────────────────────────────┘               │  NEW Services:              │          │
│                                                │  - TimeRewardTracker        │          │
│  ┌─────────────────────────────┐               │  - Real-time earnings UI    │          │
│  │    Admin Wallet             │               │  - Countdown displays       │          │
│  │    (Hot Wallet)             │               │  - Withdrawal handler       │          │
│  │                             │               │                             │          │
│  │  Calls:                     │               └─────────────────────────────┘          │
│  │  - depositTimeRewards()     │                                                        │
│  │  - startTimeReward()        │                                                        │
│  │                             │                                                        │
│  └─────────────────────────────┘                                                        │
│                                                                                          │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## Phase 1: Smart Contract Modifications

### 1.1 New State Variables for NFTRewarder.sol V3

Add to the existing contract (UUPS upgrade). **CRITICAL**: Add ALL new variables at the END of existing state variables to preserve storage layout.

**Current V2 Storage Layout** (from NFTRewarder.sol lines 321-346):
```solidity
// Existing V2 State Variables (DO NOT MODIFY ORDER)
address public admin;                                      // slot from OwnableUpgradeable
address public rogueBankroll;                              // slot 1
mapping(uint256 => NFTMetadata) public nftMetadata;        // slot 2
uint256 public totalRegisteredNFTs;                        // slot 3
uint256 public totalMultiplierPoints;                      // slot 4
mapping(address => uint256[]) public ownerTokenIds;        // slot 5
mapping(uint256 => uint256) private tokenIdToOwnerIndex;   // slot 6
uint256 public totalRewardsReceived;                       // slot 7
uint256 public totalRewardsDistributed;                    // slot 8
uint256 public rewardsPerMultiplierPoint;                  // slot 9
mapping(uint256 => uint256) public nftRewardDebt;          // slot 10
mapping(uint256 => uint256) public nftClaimedRewards;      // slot 11
mapping(address => uint256) public userTotalClaimed;       // slot 12
```

**New V3 State Variables** (append after existing):
```solidity
// ============ Time-Based Rewards State Variables (V3) ============
// IMPORTANT: These MUST be added at the END to preserve storage layout

// Configuration constants (no storage slot - compile-time)
uint256 public constant TIME_REWARD_DURATION = 180 days;  // 15,552,000 seconds
uint256 public constant SPECIAL_NFT_START_ID = 2340;      // First special NFT
uint256 public constant SPECIAL_NFT_END_ID = 2700;        // Last special NFT (inclusive)

// Time reward rates per second for each hostess type (scaled by 1e18)
// Set during initializeV3() - values calculated from ROGUE_PER_NFT / DURATION
uint256[8] public timeRewardRatesPerSecond;               // slot 13

// Pool tracking
uint256 public timeRewardPoolDeposited;                   // slot 14 - Total ROGUE deposited
uint256 public timeRewardPoolRemaining;                   // slot 15 - Available for claims
uint256 public timeRewardPoolClaimed;                     // slot 16 - Total claimed

// Per-NFT time reward tracking
struct TimeRewardInfo {
    uint256 startTime;        // When 180-day countdown started (set in registerNFT)
    uint256 lastClaimTime;    // Last time rewards were claimed
    uint256 totalClaimed;     // Total time-based rewards claimed for this NFT
}
mapping(uint256 => TimeRewardInfo) public timeRewardInfo; // slot 17

// Counters
uint256 public totalSpecialNFTsRegistered;                // slot 18

// ============ New Events ============
event TimeRewardDeposited(uint256 amount);
event TimeRewardStarted(uint256 indexed tokenId, uint256 startTime, uint256 ratePerSecond);
event TimeRewardClaimed(uint256 indexed tokenId, address indexed recipient, uint256 amount);
event TimeRewardRatesSet(uint256[8] rates);

// ============ New Errors ============
error InsufficientTimeRewardPool();
error TimeRewardNotStarted();
error TimeRewardAlreadyEnded();
```

### 1.2 Modified registerNFT Function

The key change is modifying the existing `registerNFT()` function to **automatically start time rewards** for special NFTs (2340-2700). This ensures the countdown begins at the exact moment of registration.

**Modified registerNFT()** (replaces existing at lines 478-502):
```solidity
/**
 * @notice Register NFT with metadata and owner. Only needs to be done once per NFT.
 * @dev Hostess index determines multiplier and never changes after mint.
 *      For special NFTs (2340-2700), this also starts the 180-day time reward countdown.
 * @param tokenId The NFT token ID
 * @param hostessIndex 0-7 index into MULTIPLIERS array
 * @param _owner Current owner address (from Arbitrum contract)
 */
function registerNFT(uint256 tokenId, uint8 hostessIndex, address _owner) external onlyAdmin {
    if (hostessIndex >= 8) revert InvalidHostessIndex();
    if (nftMetadata[tokenId].registered) revert AlreadyRegistered();

    nftMetadata[tokenId] = NFTMetadata({
        hostessIndex: hostessIndex,
        registered: true,
        owner: _owner
    });

    // Add to owner's token array
    if (_owner != address(0)) {
        tokenIdToOwnerIndex[tokenId] = ownerTokenIds[_owner].length;
        ownerTokenIds[_owner].push(tokenId);
    }

    uint256 multiplier = _getMultiplier(hostessIndex);
    totalMultiplierPoints += multiplier;
    totalRegisteredNFTs++;

    // Set initial reward debt so newly registered NFT doesn't claim past rewards
    nftRewardDebt[tokenId] = (multiplier * rewardsPerMultiplierPoint) / 1e18;

    emit NFTRegistered(tokenId, _owner, hostessIndex);

    // ============ V3 ADDITION: Auto-start time rewards for special NFTs ============
    if (tokenId >= SPECIAL_NFT_START_ID && tokenId <= SPECIAL_NFT_END_ID) {
        // Start the 180-day countdown at this exact block.timestamp
        timeRewardInfo[tokenId] = TimeRewardInfo({
            startTime: block.timestamp,
            lastClaimTime: block.timestamp,
            totalClaimed: 0
        });

        totalSpecialNFTsRegistered++;

        uint256 ratePerSecond = timeRewardRatesPerSecond[hostessIndex];
        emit TimeRewardStarted(tokenId, block.timestamp, ratePerSecond);
    }
}
```

**Note**: The `batchRegisterNFTs()` function should also be updated similarly, but since all existing NFTs (1-2339) are already registered, batch registration will only be used if we need to re-register or fix data. The primary flow for new mints (2340+) uses `registerNFT()`.

### 1.3 New Functions for NFTRewarder.sol V3

```solidity
// ============ Initialization ============

/**
 * @notice Initialize V3 with time-based reward rates
 * @dev Only called once during upgrade via upgradeToAndCall
 *      Rates are pre-calculated: ROGUE_PER_NFT_TYPE / 15,552,000 seconds * 1e18
 */
function initializeV3() external reinitializer(3) {
    // Time reward rates per second (scaled by 1e18 for precision)
    // Formula: (ROGUE_PER_NFT / 180 days in seconds) * 1e18

    timeRewardRatesPerSecond[0] = 2_125_029_000_000_000_000;   // Penelope (100x): 33,044,567 / 15,552,000 * 1e18
    timeRewardRatesPerSecond[1] = 1_912_007_000_000_000_000;   // Mia (90x): 29,740,111 / 15,552,000 * 1e18
    timeRewardRatesPerSecond[2] = 1_700_492_000_000_000_000;   // Cleo (80x): 26,435,654 / 15,552,000 * 1e18
    timeRewardRatesPerSecond[3] = 1_487_470_000_000_000_000;   // Sophia (70x): 23,131,197 / 15,552,000 * 1e18
    timeRewardRatesPerSecond[4] = 1_274_962_000_000_000_000;   // Luna (60x): 19,826,740 / 15,552,000 * 1e18
    timeRewardRatesPerSecond[5] = 1_062_454_000_000_000_000;   // Aurora (50x): 16,522,284 / 15,552,000 * 1e18
    timeRewardRatesPerSecond[6] = 849_946_000_000_000_000;     // Scarlett (40x): 13,217,827 / 15,552,000 * 1e18
    timeRewardRatesPerSecond[7] = 637_438_000_000_000_000;     // Vivienne (30x): 9,913,370 / 15,552,000 * 1e18

    emit TimeRewardRatesSet(timeRewardRatesPerSecond);
}

// ============ Pool Management (Owner Only) ============

/**
 * @notice Deposit ROGUE for time-based rewards pool
 * @dev Must be called before any special NFTs are minted
 */
function depositTimeRewards() external payable onlyOwner {
    if (msg.value == 0) revert NoRewardsToClaim();

    timeRewardPoolDeposited += msg.value;
    timeRewardPoolRemaining += msg.value;

    emit TimeRewardDeposited(msg.value);
}

/**
 * @notice Withdraw unused time reward pool (emergency only)
 * @dev Only callable by owner, should only be used if minting stops before 2700
 */
function withdrawUnusedTimeRewardPool(uint256 amount) external onlyOwner {
    if (amount > timeRewardPoolRemaining) revert InsufficientTimeRewardPool();

    timeRewardPoolRemaining -= amount;

    (bool success, ) = payable(owner()).call{value: amount}("");
    if (!success) revert TransferFailed();
}

// ============ Time Reward Calculation ============

/**
 * @notice Calculate pending time-based rewards for an NFT
 * @param tokenId The token ID
 * @return pending Pending unclaimed time rewards in wei
 * @return ratePerSecond Current earning rate per second (scaled by 1e18)
 * @return timeRemaining Seconds remaining in 180-day period (0 if ended)
 */
function pendingTimeReward(uint256 tokenId) public view returns (
    uint256 pending,
    uint256 ratePerSecond,
    uint256 timeRemaining
) {
    TimeRewardInfo storage info = timeRewardInfo[tokenId];

    // Not started (either not special NFT or not registered yet)
    if (info.startTime == 0) {
        return (0, 0, 0);
    }

    NFTMetadata storage nft = nftMetadata[tokenId];
    ratePerSecond = timeRewardRatesPerSecond[nft.hostessIndex];

    uint256 endTime = info.startTime + TIME_REWARD_DURATION;
    uint256 currentTime = block.timestamp;

    // Cap at end time
    if (currentTime > endTime) {
        currentTime = endTime;
        timeRemaining = 0;
    } else {
        timeRemaining = endTime - currentTime;
    }

    // Calculate time elapsed since last claim
    uint256 timeElapsed = currentTime - info.lastClaimTime;

    // Calculate pending rewards: (rate * time) / 1e18
    pending = (ratePerSecond * timeElapsed) / 1e18;

    return (pending, ratePerSecond, timeRemaining);
}

// ============ Time Reward Claiming ============

/**
 * @notice Claim time-based rewards for multiple NFTs
 * @dev Separate from withdrawTo() which handles revenue sharing rewards.
 *      Both can be called together for combined withdrawal.
 * @param tokenIds Array of token IDs to claim for
 * @param recipient Address to receive the rewards
 * @return totalAmount Total ROGUE claimed
 */
function claimTimeRewards(
    uint256[] calldata tokenIds,
    address recipient
) external onlyAdmin nonReentrant returns (uint256 totalAmount) {
    if (tokenIds.length == 0) revert LengthMismatch();
    if (recipient == address(0)) revert InvalidAddress();

    for (uint256 i = 0; i < tokenIds.length; i++) {
        uint256 tokenId = tokenIds[i];
        TimeRewardInfo storage info = timeRewardInfo[tokenId];

        // Skip NFTs without active time rewards
        if (info.startTime == 0) continue;

        (uint256 pending, , ) = pendingTimeReward(tokenId);

        if (pending > 0) {
            // Update last claim time
            info.lastClaimTime = block.timestamp;
            info.totalClaimed += pending;
            totalAmount += pending;

            emit TimeRewardClaimed(tokenId, recipient, pending);
        }
    }

    if (totalAmount == 0) revert NoRewardsToClaim();
    if (totalAmount > timeRewardPoolRemaining) revert InsufficientTimeRewardPool();

    timeRewardPoolRemaining -= totalAmount;
    timeRewardPoolClaimed += totalAmount;

    // Transfer ROGUE to recipient
    (bool success, ) = payable(recipient).call{value: totalAmount}("");
    if (!success) revert TransferFailed();

    return totalAmount;
}

// ============ Combined Withdrawal (Convenience Function) ============

/**
 * @notice Withdraw BOTH revenue sharing AND time-based rewards in one transaction
 * @dev Combines withdrawTo() and claimTimeRewards() for gas efficiency
 * @param tokenIds Array of token IDs to claim for
 * @param recipient Address to receive the rewards
 * @return revenueAmount Revenue sharing rewards claimed
 * @return timeAmount Time-based rewards claimed
 */
function withdrawAll(
    uint256[] calldata tokenIds,
    address recipient
) external onlyAdmin nonReentrant returns (uint256 revenueAmount, uint256 timeAmount) {
    if (tokenIds.length == 0) revert LengthMismatch();
    if (recipient == address(0)) revert InvalidAddress();

    // Process each NFT for both reward types
    for (uint256 i = 0; i < tokenIds.length; i++) {
        uint256 tokenId = tokenIds[i];

        // ---- Revenue Sharing Rewards ----
        if (nftMetadata[tokenId].registered) {
            uint256 revenuePending = pendingReward(tokenId);
            if (revenuePending > 0) {
                uint8 hostessIndex = nftMetadata[tokenId].hostessIndex;
                uint256 multiplier = _getMultiplier(hostessIndex);
                nftRewardDebt[tokenId] = (multiplier * rewardsPerMultiplierPoint) / 1e18;
                nftClaimedRewards[tokenId] += revenuePending;
                revenueAmount += revenuePending;
            }
        }

        // ---- Time-Based Rewards ----
        TimeRewardInfo storage info = timeRewardInfo[tokenId];
        if (info.startTime != 0) {
            (uint256 timePending, , ) = pendingTimeReward(tokenId);
            if (timePending > 0) {
                info.lastClaimTime = block.timestamp;
                info.totalClaimed += timePending;
                timeAmount += timePending;

                emit TimeRewardClaimed(tokenId, recipient, timePending);
            }
        }
    }

    uint256 totalAmount = revenueAmount + timeAmount;
    if (totalAmount == 0) revert NoRewardsToClaim();

    // Verify time reward pool has sufficient balance
    if (timeAmount > timeRewardPoolRemaining) revert InsufficientTimeRewardPool();

    // Update tracking
    if (revenueAmount > 0) {
        userTotalClaimed[recipient] += revenueAmount;
        totalRewardsDistributed += revenueAmount;
    }
    if (timeAmount > 0) {
        timeRewardPoolRemaining -= timeAmount;
        timeRewardPoolClaimed += timeAmount;
    }

    // Single transfer for both reward types
    (bool success, ) = payable(recipient).call{value: totalAmount}("");
    if (!success) revert TransferFailed();

    // Emit revenue sharing event
    if (revenueAmount > 0) {
        emit RewardClaimed(recipient, revenueAmount, tokenIds);
    }

    return (revenueAmount, timeAmount);
}

// ============ View Functions ============

/**
 * @notice Get comprehensive time reward info for a single NFT
 * @param tokenId The token ID
 * @return startTime When countdown started (0 if not special NFT)
 * @return endTime When countdown ends
 * @return pending Current pending rewards
 * @return claimed Total claimed so far
 * @return ratePerSecond Earning rate (scaled by 1e18)
 * @return timeRemaining Seconds left in countdown
 * @return totalFor180Days Total ROGUE this NFT will earn
 * @return isActive True if currently earning
 */
function getTimeRewardInfo(uint256 tokenId) external view returns (
    uint256 startTime,
    uint256 endTime,
    uint256 pending,
    uint256 claimed,
    uint256 ratePerSecond,
    uint256 timeRemaining,
    uint256 totalFor180Days,
    bool isActive
) {
    TimeRewardInfo storage info = timeRewardInfo[tokenId];
    startTime = info.startTime;
    claimed = info.totalClaimed;

    if (startTime == 0) {
        return (0, 0, 0, 0, 0, 0, 0, false);
    }

    endTime = startTime + TIME_REWARD_DURATION;
    (pending, ratePerSecond, timeRemaining) = pendingTimeReward(tokenId);
    totalFor180Days = (ratePerSecond * TIME_REWARD_DURATION) / 1e18;
    isActive = block.timestamp < endTime;

    return (startTime, endTime, pending, claimed, ratePerSecond, timeRemaining, totalFor180Days, isActive);
}

/**
 * @notice Check if a token ID is in the special NFT range
 * @param tokenId The token ID to check
 * @return isSpecial True if token ID is 2340-2700
 * @return hasStarted True if time rewards have started
 */
function isSpecialNFT(uint256 tokenId) external view returns (bool isSpecial, bool hasStarted) {
    isSpecial = tokenId >= SPECIAL_NFT_START_ID && tokenId <= SPECIAL_NFT_END_ID;
    hasStarted = timeRewardInfo[tokenId].startTime != 0;
    return (isSpecial, hasStarted);
}

/**
 * @notice Get complete earnings breakdown for an NFT - FOR OWNER VERIFICATION
 * @dev Returns all information an owner needs to verify their rewards on-chain
 *      This is the primary function for owners to check their NFT earnings status
 * @param tokenId The token ID
 * @return pendingNow Current unclaimed balance (withdrawable right now)
 * @return alreadyClaimed Total ROGUE already withdrawn to date
 * @return totalEarnedSoFar Total earned up to now (pending + claimed)
 * @return futureEarnings ROGUE still to be earned (remaining time * rate)
 * @return totalAllocation Total ROGUE allocated for full 180 days
 * @return ratePerSecond Earning rate in wei per second
 * @return percentComplete Percentage of 180-day period completed (basis points, 10000 = 100%)
 * @return secondsRemaining Seconds left until 180-day period ends
 */
function getEarningsBreakdown(uint256 tokenId) external view returns (
    uint256 pendingNow,
    uint256 alreadyClaimed,
    uint256 totalEarnedSoFar,
    uint256 futureEarnings,
    uint256 totalAllocation,
    uint256 ratePerSecond,
    uint256 percentComplete,
    uint256 secondsRemaining
) {
    TimeRewardInfo storage info = timeRewardInfo[tokenId];

    // Not a special NFT or not started
    if (info.startTime == 0) {
        return (0, 0, 0, 0, 0, 0, 0, 0);
    }

    NFTMetadata storage nft = nftMetadata[tokenId];
    ratePerSecond = timeRewardRatesPerSecond[nft.hostessIndex];

    uint256 endTime = info.startTime + TIME_REWARD_DURATION;
    uint256 currentTime = block.timestamp;

    // Calculate seconds remaining
    if (currentTime >= endTime) {
        secondsRemaining = 0;
        currentTime = endTime;
    } else {
        secondsRemaining = endTime - currentTime;
    }

    // Calculate pending (unclaimed balance) - what owner can withdraw NOW
    uint256 timeElapsedSinceClaim = currentTime - info.lastClaimTime;
    pendingNow = (ratePerSecond * timeElapsedSinceClaim) / 1e18;

    // Already claimed - total withdrawn to owner's wallet
    alreadyClaimed = info.totalClaimed;

    // Total earned so far = pending + claimed
    totalEarnedSoFar = pendingNow + alreadyClaimed;

    // Total allocation for full 180 days - this is the max this NFT will ever earn
    totalAllocation = (ratePerSecond * TIME_REWARD_DURATION) / 1e18;

    // Future earnings = what's left to earn after today
    if (totalAllocation > totalEarnedSoFar) {
        futureEarnings = totalAllocation - totalEarnedSoFar;
    } else {
        futureEarnings = 0;
    }

    // Percent complete (basis points: 10000 = 100%, 5000 = 50%)
    uint256 totalTimeElapsed = currentTime - info.startTime;
    percentComplete = (totalTimeElapsed * 10000) / TIME_REWARD_DURATION;
    if (percentComplete > 10000) {
        percentComplete = 10000;
    }

    return (
        pendingNow,
        alreadyClaimed,
        totalEarnedSoFar,
        futureEarnings,
        totalAllocation,
        ratePerSecond,
        percentComplete,
        secondsRemaining
    );
}

/**
 * @notice Get time reward stats for all NFTs owned by an address
 * @param _owner The wallet address
 * @return totalPending Combined pending time rewards
 * @return totalClaimed Combined claimed time rewards
 * @return specialNFTCount Number of special NFTs owned
 */
function getOwnerTimeRewardStats(address _owner) external view returns (
    uint256 totalPending,
    uint256 totalClaimed,
    uint256 specialNFTCount
) {
    uint256[] memory tokenIds = ownerTokenIds[_owner];

    for (uint256 i = 0; i < tokenIds.length; i++) {
        TimeRewardInfo storage info = timeRewardInfo[tokenIds[i]];
        if (info.startTime != 0) {
            specialNFTCount++;
            totalClaimed += info.totalClaimed;
            (uint256 pending, , ) = pendingTimeReward(tokenIds[i]);
            totalPending += pending;
        }
    }

    return (totalPending, totalClaimed, specialNFTCount);
}

/**
 * @notice Get global time reward pool statistics
 * @return deposited Total ROGUE deposited
 * @return remaining Available for claims
 * @return claimed Total claimed so far
 * @return specialNFTs Number of special NFTs registered
 */
function getTimeRewardPoolStats() external view returns (
    uint256 deposited,
    uint256 remaining,
    uint256 claimed,
    uint256 specialNFTs
) {
    return (
        timeRewardPoolDeposited,
        timeRewardPoolRemaining,
        timeRewardPoolClaimed,
        totalSpecialNFTsRegistered
    );
}
```

### 1.4 Manual Start Function for Pre-Registered NFTs

For NFTs that were already registered before the V3 upgrade (e.g., 2340, 2341, 2342), we need a function to manually start their time rewards:

```solidity
/**
 * @notice Manually start time rewards for a special NFT that was registered before V3
 * @dev Only needed for NFTs 2340-2700 that were registered before the V3 upgrade
 *      New registrations after V3 will auto-start in registerNFT()
 * @param tokenId The NFT token ID (must be 2340-2700 and already registered)
 */
function startTimeRewardManual(uint256 tokenId) external onlyAdmin {
    // Must be in special NFT range
    if (tokenId < SPECIAL_NFT_START_ID || tokenId > SPECIAL_NFT_END_ID) {
        revert InvalidTokenId();
    }

    // Must be registered
    if (!nftMetadata[tokenId].registered) {
        revert NotRegistered();
    }

    // Must not have already started
    if (timeRewardInfo[tokenId].startTime != 0) {
        revert TimeRewardAlreadyStarted();
    }

    // Start the 180-day countdown
    timeRewardInfo[tokenId] = TimeRewardInfo({
        startTime: block.timestamp,
        lastClaimTime: block.timestamp,
        totalClaimed: 0
    });

    totalSpecialNFTsRegistered++;

    uint8 hostessIndex = nftMetadata[tokenId].hostessIndex;
    uint256 ratePerSecond = timeRewardRatesPerSecond[hostessIndex];

    emit TimeRewardStarted(tokenId, block.timestamp, ratePerSecond);
}

/**
 * @notice Batch start time rewards for multiple pre-registered special NFTs
 * @dev Convenience function for starting multiple NFTs at once
 * @param tokenIds Array of token IDs to start (must all be 2340-2700 and registered)
 */
function batchStartTimeRewardManual(uint256[] calldata tokenIds) external onlyAdmin {
    for (uint256 i = 0; i < tokenIds.length; i++) {
        uint256 tokenId = tokenIds[i];

        // Skip invalid or already started
        if (tokenId < SPECIAL_NFT_START_ID || tokenId > SPECIAL_NFT_END_ID) continue;
        if (!nftMetadata[tokenId].registered) continue;
        if (timeRewardInfo[tokenId].startTime != 0) continue;

        // Start time rewards
        timeRewardInfo[tokenId] = TimeRewardInfo({
            startTime: block.timestamp,
            lastClaimTime: block.timestamp,
            totalClaimed: 0
        });

        totalSpecialNFTsRegistered++;

        uint8 hostessIndex = nftMetadata[tokenId].hostessIndex;
        uint256 ratePerSecond = timeRewardRatesPerSecond[hostessIndex];

        emit TimeRewardStarted(tokenId, block.timestamp, ratePerSecond);
    }
}
```

**New Error**:
```solidity
error TimeRewardAlreadyStarted();
error InvalidTokenId();
error NotRegistered();
```

**Usage for NFTs 2340, 2341, 2342**:
```bash
# After V3 upgrade, run this script to start time rewards for pre-registered NFTs
npx hardhat run scripts/start-time-rewards-manual.js --network rogueMainnet
```

**Script** (`scripts/start-time-rewards-manual.js`):
```javascript
const { ethers } = require("hardhat");

async function main() {
  const NFTREWARDER_PROXY = "0x96aB9560f1407586faE2b69Dc7f38a59BEACC594";
  const PRE_REGISTERED_NFTS = [2340, 2341, 2342];

  const [admin] = await ethers.getSigners();
  console.log("Starting time rewards from:", admin.address);

  const NFTRewarder = await ethers.getContractAt("NFTRewarder", NFTREWARDER_PROXY);

  console.log("Starting time rewards for pre-registered NFTs:", PRE_REGISTERED_NFTS);

  const tx = await NFTRewarder.batchStartTimeRewardManual(PRE_REGISTERED_NFTS);
  console.log("TX Hash:", tx.hash);

  const receipt = await tx.wait();
  console.log("Confirmed in block:", receipt.blockNumber);

  // Verify each NFT
  for (const tokenId of PRE_REGISTERED_NFTS) {
    const info = await NFTRewarder.getTimeRewardInfo(tokenId);
    console.log(`NFT ${tokenId}: startTime=${info.startTime}, rate=${ethers.formatEther(info.ratePerSecond)}/sec`);
  }
}

main().catch(console.error);
```

---

### 1.5 Summary of Contract Changes

| Change Type | Function/Variable | Description |
|-------------|-------------------|-------------|
| **Modified** | `registerNFT()` | Added auto-start time rewards for token IDs 2340-2700 |
| **New** | `startTimeRewardManual()` | Manually start time rewards for pre-registered special NFTs |
| **New** | `batchStartTimeRewardManual()` | Batch start time rewards for multiple pre-registered NFTs |
| **New** | `initializeV3()` | Sets time reward rates per hostess type |
| **New** | `depositTimeRewards()` | Owner deposits ROGUE pool |
| **New** | `withdrawUnusedTimeRewardPool()` | Emergency withdrawal of unused pool |
| **New** | `pendingTimeReward()` | Calculate pending time-based rewards |
| **New** | `claimTimeRewards()` | Claim time rewards only |
| **New** | `withdrawAll()` | Claim both revenue sharing + time rewards |
| **New** | `getTimeRewardInfo()` | View function for UI |
| **New** | `getEarningsBreakdown()` | **Owner verification** - complete earnings breakdown |
| **New** | `isSpecialNFT()` | Check if token is in special range |
| **New** | `getOwnerTimeRewardStats()` | Aggregated stats for wallet |
| **New** | `getTimeRewardPoolStats()` | Global pool statistics |
| **New State** | `timeRewardRatesPerSecond[8]` | Per-hostess rates |
| **New State** | `timeRewardPoolDeposited/Remaining/Claimed` | Pool tracking |
| **New State** | `timeRewardInfo` mapping | Per-NFT tracking |
| **New State** | `totalSpecialNFTsRegistered` | Counter |

---

## Phase 2: Contract Deployment Steps

### 2.1 Pre-Deployment Checklist

- [ ] Verify current NFTRewarder V2 storage layout matches expected
- [ ] Write comprehensive unit tests for new functions
- [ ] Verify time reward rate calculations are correct
- [ ] Prepare upgrade script with safety checks

### 2.2 Deployment Commands

```bash
cd contracts/bux-booster-game

# 1. Compile the new contract
npx hardhat compile

# 2. Run tests
npx hardhat test test/NFTRewarder.test.js

# 3. Deploy V3 implementation
npx hardhat run scripts/deploy-nftrewarder-v3.js --network rogueMainnet

# 4. Upgrade proxy to V3 (calls initializeV3 automatically)
npx hardhat run scripts/upgrade-nftrewarder-v3.js --network rogueMainnet

# 5. Verify on Roguescan
npx hardhat run scripts/verify-nftrewarder-v3.js --network rogueMainnet

# 6. Test deposit with small amount first (1000 ROGUE)
npx hardhat run scripts/deposit-time-rewards.js --network rogueMainnet
# Pass amount as argument: node scripts/deposit-time-rewards.js 1000

# 7. Test withdrawal works (CRITICAL - verify before depositing full amount!)
npx hardhat run scripts/withdraw-time-rewards.js --network rogueMainnet

# 8. Once deposit/withdraw verified, deposit full pool (5,614,272,000 ROGUE)
npx hardhat run scripts/deposit-time-rewards.js --network rogueMainnet
# Pass amount as argument: node scripts/deposit-time-rewards.js 5614272000
```

### 2.3 Deposit Time Rewards Script

```javascript
// scripts/deposit-time-rewards.js
const { ethers } = require("hardhat");

async function main() {
  const NFTREWARDER_PROXY = "0x96aB9560f1407586faE2b69Dc7f38a59BEACC594";
  const FULL_POOL_AMOUNT = "5614272000"; // 5.6B ROGUE for full deployment

  // Get amount from command line args, default to 1000 ROGUE for testing
  const args = process.argv.slice(2);
  const amountStr = args[0] || "1000";
  const DEPOSIT_AMOUNT = ethers.parseEther(amountStr);

  console.log("=".repeat(60));
  console.log("NFTRewarder Time Rewards Deposit");
  console.log("=".repeat(60));
  console.log("Amount to deposit:", amountStr, "ROGUE");
  if (amountStr !== FULL_POOL_AMOUNT) {
    console.log("⚠️  TEST MODE - not the full pool amount");
    console.log("   Full pool amount is:", FULL_POOL_AMOUNT, "ROGUE");
  }
  console.log("");

  const [deployer] = await ethers.getSigners();
  console.log("Depositing from:", deployer.address);

  // Check balance
  const balance = await ethers.provider.getBalance(deployer.address);
  console.log("Deployer balance:", ethers.formatEther(balance), "ROGUE");

  if (balance < DEPOSIT_AMOUNT) {
    throw new Error(`Insufficient balance. Need ${amountStr} ROGUE, have ${ethers.formatEther(balance)} ROGUE`);
  }

  const NFTRewarder = await ethers.getContractAt("NFTRewarder", NFTREWARDER_PROXY);

  // Show current pool state before deposit
  try {
    const poolBefore = await NFTRewarder.timeRewardPoolRemaining();
    console.log("Pool before deposit:", ethers.formatEther(poolBefore), "ROGUE");
  } catch (e) {
    console.log("Pool before deposit: 0 ROGUE (not initialized yet)");
  }

  console.log("");
  console.log("Depositing", amountStr, "ROGUE for time rewards...");

  const tx = await NFTRewarder.depositTimeRewards({ value: DEPOSIT_AMOUNT });
  console.log("TX Hash:", tx.hash);

  const receipt = await tx.wait();
  console.log("✅ Deposit confirmed in block:", receipt.blockNumber);

  // Verify deposit
  const poolAfter = await NFTRewarder.timeRewardPoolRemaining();
  console.log("Pool after deposit:", ethers.formatEther(poolAfter), "ROGUE");
  console.log("");
  console.log("=".repeat(60));
}

main().catch(console.error);
```

### 2.4 Withdraw Time Rewards Script (For Testing)

```javascript
// scripts/withdraw-time-rewards.js
const { ethers } = require("hardhat");

async function main() {
  const NFTREWARDER_PROXY = "0x96aB9560f1407586faE2b69Dc7f38a59BEACC594";

  console.log("=".repeat(60));
  console.log("NFTRewarder Time Rewards Withdrawal Test");
  console.log("=".repeat(60));

  const [deployer] = await ethers.getSigners();
  console.log("Withdrawing to:", deployer.address);

  const NFTRewarder = await ethers.getContractAt("NFTRewarder", NFTREWARDER_PROXY);

  // Check current pool state
  const poolRemaining = await NFTRewarder.timeRewardPoolRemaining();
  console.log("Pool remaining:", ethers.formatEther(poolRemaining), "ROGUE");

  if (poolRemaining === 0n) {
    console.log("⚠️  Pool is empty, nothing to withdraw");
    return;
  }

  // Check deployer balance before
  const balanceBefore = await ethers.provider.getBalance(deployer.address);
  console.log("Wallet balance before:", ethers.formatEther(balanceBefore), "ROGUE");

  console.log("");
  console.log("Withdrawing unused pool...");

  const tx = await NFTRewarder.withdrawUnusedTimeRewardPool();
  console.log("TX Hash:", tx.hash);

  const receipt = await tx.wait();
  console.log("✅ Withdrawal confirmed in block:", receipt.blockNumber);

  // Verify withdrawal
  const poolAfter = await NFTRewarder.timeRewardPoolRemaining();
  const balanceAfter = await ethers.provider.getBalance(deployer.address);

  console.log("");
  console.log("Pool after withdrawal:", ethers.formatEther(poolAfter), "ROGUE");
  console.log("Wallet balance after:", ethers.formatEther(balanceAfter), "ROGUE");

  const received = balanceAfter - balanceBefore;
  // Note: received will be slightly less than poolRemaining due to gas costs
  console.log("Approximate ROGUE received:", ethers.formatEther(received), "(minus gas)");

  console.log("");
  console.log("=".repeat(60));
  console.log("✅ WITHDRAWAL TEST SUCCESSFUL");
  console.log("   You can now safely deposit the full pool amount.");
  console.log("=".repeat(60));
}

main().catch(console.error);
```

---

## Phase 3: Backend Service Updates

### 3.1 New Service: TimeRewardTracker

Create `high-rollers-nfts/server/services/timeRewardTracker.js`:

```javascript
/**
 * TimeRewardTracker Service
 *
 * Tracks time-based rewards for special NFTs (2340-2700).
 * Provides real-time earnings calculations for UI without blockchain calls.
 *
 * NOTE: Time rewards are automatically started in registerNFT() on-chain.
 * This service just tracks the start time locally for UI calculations.
 */

const { ethers } = require('ethers');
const config = require('../config');

class TimeRewardTracker {
  constructor(db, adminTxQueue, websocket) {
    this.db = db;
    this.adminTxQueue = adminTxQueue;
    this.ws = websocket;

    // Constants matching smart contract
    this.TIME_REWARD_DURATION = 180 * 24 * 60 * 60; // 180 days in seconds
    this.SPECIAL_NFT_START_ID = 2340;
    this.SPECIAL_NFT_END_ID = 2700;

    // Time reward rates per second (in wei, with 18 decimals precision)
    // Index 0-7 = hostess types (Penelope to Vivienne)
    this.TIME_REWARD_RATES = [
      BigInt("2125000000000000000"),  // Penelope (100x) - 2.125 ROGUE/sec
      BigInt("1912000000000000000"),  // Mia (90x) - 1.912 ROGUE/sec
      BigInt("1700000000000000000"),  // Cleo (80x) - 1.700 ROGUE/sec
      BigInt("1487000000000000000"),  // Sophia (70x) - 1.487 ROGUE/sec
      BigInt("1275000000000000000"),  // Luna (60x) - 1.275 ROGUE/sec
      BigInt("1062000000000000000"),  // Aurora (50x) - 1.062 ROGUE/sec
      BigInt("850000000000000000"),   // Scarlett (40x) - 0.850 ROGUE/sec
      BigInt("637000000000000000"),   // Vivienne (30x) - 0.637 ROGUE/sec
    ];

    // Provider for contract calls
    this.provider = new ethers.JsonRpcProvider(config.ROGUE_RPC_URL);
    this.nftRewarderAddress = config.NFT_REWARDER_ADDRESS;
  }

  /**
   * Check if a token ID is a special NFT
   */
  isSpecialNFT(tokenId) {
    return tokenId >= this.SPECIAL_NFT_START_ID && tokenId <= this.SPECIAL_NFT_END_ID;
  }

  /**
   * Get time reward rate per second for a hostess type
   * @param hostessIndex 0-7
   * @returns Rate in ROGUE per second (as float)
   */
  getRatePerSecond(hostessIndex) {
    const rate = this.TIME_REWARD_RATES[hostessIndex];
    return Number(rate) / 1e18;
  }

  /**
   * Calculate pending time rewards for an NFT
   * Uses local calculation to avoid blockchain calls
   *
   * @param tokenId Token ID
   * @returns Object with pending, ratePerSecond, timeRemaining, totalFor180Days
   */
  calculatePendingReward(tokenId) {
    // Get NFT info from database
    const nft = this.db.getTimeRewardNFT(tokenId);

    if (!nft || !nft.start_time || nft.start_time === 0) {
      return {
        pending: 0,
        ratePerSecond: 0,
        timeRemaining: 0,
        totalFor180Days: 0,
        isSpecial: this.isSpecialNFT(tokenId),
        hasStarted: false
      };
    }

    const hostessIndex = nft.hostess_index;
    const ratePerSecond = this.getRatePerSecond(hostessIndex);

    const now = Math.floor(Date.now() / 1000);
    const startTime = nft.start_time;
    const endTime = startTime + this.TIME_REWARD_DURATION;
    const lastClaimTime = nft.last_claim_time || startTime;

    // Cap current time at end time
    const currentTime = Math.min(now, endTime);
    const timeRemaining = Math.max(0, endTime - now);

    // Time elapsed since last claim
    const timeElapsed = currentTime - lastClaimTime;

    // Calculate pending
    const pending = ratePerSecond * timeElapsed;

    // Total for 180 days
    const totalFor180Days = ratePerSecond * this.TIME_REWARD_DURATION;

    return {
      pending,
      ratePerSecond,
      timeRemaining,
      totalFor180Days,
      totalEarned: nft.total_earned || 0,
      totalClaimed: nft.total_claimed || 0,
      startTime,
      endTime,
      isSpecial: true,
      hasStarted: true
    };
  }

  /**
   * Handle new NFT registration - called AFTER registerNFT() succeeds on-chain
   * The contract already started time rewards in registerNFT() for special NFTs.
   * This method just tracks the start time locally for UI calculations.
   *
   * @param tokenId Token ID that was just registered
   * @param hostessIndex Hostess type (0-7)
   * @param owner Current owner address
   * @param blockTimestamp The block.timestamp when registerNFT was called
   */
  handleNFTRegistered(tokenId, hostessIndex, owner, blockTimestamp) {
    if (!this.isSpecialNFT(tokenId)) {
      // Not a special NFT - no time rewards tracking needed
      return;
    }

    console.log(`[TimeRewardTracker] Special NFT ${tokenId} registered, tracking time rewards`);

    // Store in database using the exact block timestamp from registerNFT
    // This ensures UI calculations match the smart contract exactly
    this.db.insertTimeRewardNFT({
      tokenId,
      hostessIndex,
      owner,
      startTime: blockTimestamp,
      lastClaimTime: blockTimestamp,
      totalClaimed: 0
    });

    // Broadcast to connected clients
    this.ws.broadcast({
      type: 'SPECIAL_NFT_STARTED',
      data: {
        tokenId,
        hostessIndex,
        owner,
        startTime: blockTimestamp,
        ratePerSecond: this.getRatePerSecond(hostessIndex),
        totalFor180Days: this.getRatePerSecond(hostessIndex) * this.TIME_REWARD_DURATION
      }
    });

    console.log(`[TimeRewardTracker] Special NFT ${tokenId} time rewards started at ${blockTimestamp}`);
  }

  /**
   * Sync time reward info from blockchain (for recovery/verification)
   * Queries the contract's getTimeRewardInfo() function
   */
  async syncFromBlockchain(tokenId) {
    try {
      const contract = new ethers.Contract(
        this.nftRewarderAddress,
        ['function getTimeRewardInfo(uint256) view returns (uint256,uint256,uint256,uint256,uint256,uint256,uint256,bool)'],
        this.provider
      );

      const [startTime, endTime, pending, claimed, ratePerSecond, timeRemaining, totalFor180Days, isActive] =
        await contract.getTimeRewardInfo(tokenId);

      if (startTime > 0) {
        // NFT has time rewards - update local DB
        const nft = this.db.getNFT(tokenId);
        this.db.insertTimeRewardNFT({
          tokenId,
          hostessIndex: nft?.hostess_index || 0,
          owner: nft?.owner || '',
          startTime: Number(startTime),
          lastClaimTime: Number(startTime) + (this.TIME_REWARD_DURATION - Number(timeRemaining)) - (Number(pending) / (Number(ratePerSecond) / 1e18)),
          totalClaimed: Number(claimed) / 1e18
        });

        console.log(`[TimeRewardTracker] Synced token ${tokenId} from blockchain`);
      }
    } catch (error) {
      console.error(`[TimeRewardTracker] Failed to sync ${tokenId} from blockchain:`, error);
    }
  }

  /**
   * Update database after successful claim
   */
  updateAfterClaim(tokenId, claimedAmount) {
    const now = Math.floor(Date.now() / 1000);
    this.db.updateTimeRewardClaim(tokenId, claimedAmount, now);
  }

  /**
   * Get all special NFTs for a wallet with time reward calculations
   */
  getWalletSpecialNFTs(walletAddress) {
    const nfts = this.db.getOwnerSpecialNFTs(walletAddress);

    return nfts.map(nft => ({
      ...nft,
      timeReward: this.calculatePendingReward(nft.token_id)
    }));
  }

  /**
   * Get aggregated time reward stats for a wallet
   */
  getWalletTimeRewardStats(walletAddress) {
    const nfts = this.getWalletSpecialNFTs(walletAddress);

    let totalPending = 0;
    let totalEarned = 0;
    let totalClaimed = 0;
    let totalFor180Days = 0;

    for (const nft of nfts) {
      if (nft.timeReward.hasStarted) {
        totalPending += nft.timeReward.pending;
        totalEarned += nft.timeReward.totalEarned + nft.timeReward.pending;
        totalClaimed += nft.timeReward.totalClaimed;
        totalFor180Days += nft.timeReward.totalFor180Days;
      }
    }

    return {
      nftCount: nfts.length,
      totalPending,
      totalEarned,
      totalClaimed,
      totalFor180Days,
      nfts
    };
  }

  /**
   * Get global time reward stats
   */
  async getGlobalStats() {
    // Query from database
    const stats = this.db.getTimeRewardGlobalStats();

    return {
      totalPoolDeposited: stats.pool_deposited,
      totalPoolRemaining: stats.pool_remaining,
      totalPoolClaimed: stats.pool_claimed,
      totalSpecialNFTsStarted: stats.nfts_started,
      specialNFTRange: {
        start: this.SPECIAL_NFT_START_ID,
        end: this.SPECIAL_NFT_END_ID
      }
    };
  }
}

module.exports = TimeRewardTracker;
```

### 3.2 Database Schema Updates

Add to `high-rollers-nfts/server/services/database.js`:

```javascript
// ============ Time Reward Tables ============

// Create time_reward_nfts table
db.exec(`
  CREATE TABLE IF NOT EXISTS time_reward_nfts (
    token_id INTEGER PRIMARY KEY,
    hostess_index INTEGER NOT NULL,
    owner TEXT NOT NULL,
    start_time INTEGER DEFAULT 0,
    last_claim_time INTEGER DEFAULT 0,
    total_earned REAL DEFAULT 0,
    total_claimed REAL DEFAULT 0,
    is_special INTEGER DEFAULT 1,
    created_at INTEGER DEFAULT (strftime('%s', 'now'))
  )
`);

// Create time_reward_claims table
db.exec(`
  CREATE TABLE IF NOT EXISTS time_reward_claims (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    token_id INTEGER NOT NULL,
    recipient TEXT NOT NULL,
    amount REAL NOT NULL,
    tx_hash TEXT,
    claimed_at INTEGER DEFAULT (strftime('%s', 'now')),
    FOREIGN KEY (token_id) REFERENCES time_reward_nfts(token_id)
  )
`);

// Create time_reward_global_stats table
db.exec(`
  CREATE TABLE IF NOT EXISTS time_reward_global_stats (
    id INTEGER PRIMARY KEY DEFAULT 1,
    pool_deposited REAL DEFAULT 0,
    pool_remaining REAL DEFAULT 0,
    pool_claimed REAL DEFAULT 0,
    nfts_started INTEGER DEFAULT 0,
    last_updated INTEGER DEFAULT (strftime('%s', 'now'))
  )
`);

// Initialize global stats row
db.exec(`
  INSERT OR IGNORE INTO time_reward_global_stats (id) VALUES (1)
`);

// ============ Time Reward Database Methods ============

insertTimeRewardNFT(data) {
  const stmt = this.db.prepare(`
    INSERT OR REPLACE INTO time_reward_nfts
    (token_id, hostess_index, owner, start_time, last_claim_time, total_earned, total_claimed)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  `);
  stmt.run(
    data.tokenId,
    data.hostessIndex,
    data.owner.toLowerCase(),
    data.startTime,
    data.lastClaimTime,
    data.totalEarned,
    data.totalClaimed
  );
}

getTimeRewardNFT(tokenId) {
  return this.db.prepare(`
    SELECT * FROM time_reward_nfts WHERE token_id = ?
  `).get(tokenId);
}

updateTimeRewardClaim(tokenId, claimedAmount, claimTime) {
  const stmt = this.db.prepare(`
    UPDATE time_reward_nfts
    SET last_claim_time = ?,
        total_earned = total_earned + ?,
        total_claimed = total_claimed + ?
    WHERE token_id = ?
  `);
  stmt.run(claimTime, claimedAmount, claimedAmount, tokenId);
}

getOwnerSpecialNFTs(owner) {
  return this.db.prepare(`
    SELECT tr.*, n.hostess_name
    FROM time_reward_nfts tr
    JOIN nfts n ON tr.token_id = n.token_id
    WHERE tr.owner = ?
    ORDER BY tr.token_id ASC
  `).all(owner.toLowerCase());
}

getTimeRewardGlobalStats() {
  return this.db.prepare(`
    SELECT * FROM time_reward_global_stats WHERE id = 1
  `).get();
}

updateTimeRewardGlobalStats(stats) {
  const stmt = this.db.prepare(`
    UPDATE time_reward_global_stats
    SET pool_deposited = ?,
        pool_remaining = ?,
        pool_claimed = ?,
        nfts_started = ?,
        last_updated = ?
    WHERE id = 1
  `);
  stmt.run(
    stats.poolDeposited,
    stats.poolRemaining,
    stats.poolClaimed,
    stats.nftsStarted,
    Math.floor(Date.now() / 1000)
  );
}
```

### 3.3 API Endpoints Updates

Add to `high-rollers-nfts/server/routes/revenues.js`:

```javascript
// ============ Time-Based Rewards Endpoints ============

/**
 * GET /api/revenues/time-rewards/stats
 * Get global time reward statistics
 */
router.get('/time-rewards/stats', async (req, res) => {
  try {
    const stats = await timeRewardTracker.getGlobalStats();
    res.json(stats);
  } catch (error) {
    console.error('[TimeRewards] Error getting global stats:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /api/revenues/time-rewards/nft/:tokenId
 * Get time reward info for a specific NFT
 */
router.get('/time-rewards/nft/:tokenId', async (req, res) => {
  try {
    const tokenId = parseInt(req.params.tokenId);
    const info = timeRewardTracker.calculatePendingReward(tokenId);
    res.json({ tokenId, ...info });
  } catch (error) {
    console.error('[TimeRewards] Error getting NFT info:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /api/revenues/time-rewards/user/:address
 * Get time reward info for all special NFTs owned by a wallet
 */
router.get('/time-rewards/user/:address', async (req, res) => {
  try {
    const address = req.params.address.toLowerCase();
    const stats = timeRewardTracker.getWalletTimeRewardStats(address);
    res.json(stats);
  } catch (error) {
    console.error('[TimeRewards] Error getting user time rewards:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * POST /api/revenues/time-rewards/claim
 * Claim time-based rewards for user's special NFTs
 * Body: { tokenIds: number[], recipient: string }
 */
router.post('/time-rewards/claim', async (req, res) => {
  try {
    const { tokenIds, recipient } = req.body;

    if (!tokenIds || !Array.isArray(tokenIds) || tokenIds.length === 0) {
      return res.status(400).json({ error: 'tokenIds array required' });
    }

    if (!recipient) {
      return res.status(400).json({ error: 'recipient address required' });
    }

    // Queue the claim transaction
    const result = await adminTxQueue.queueTransaction('claimTimeRewards', [tokenIds, recipient]);

    // Update local database
    for (const tokenId of tokenIds) {
      const pending = timeRewardTracker.calculatePendingReward(tokenId).pending;
      if (pending > 0) {
        timeRewardTracker.updateAfterClaim(tokenId, pending);
      }
    }

    res.json({ success: true, txHash: result.txHash });

  } catch (error) {
    console.error('[TimeRewards] Error claiming rewards:', error);
    res.status(500).json({ error: error.message });
  }
});
```

### 3.4 EventListener Updates

Modify `high-rollers-nfts/server/services/eventListener.js` to track time rewards after registration:

```javascript
// In the existing handleNFTMinted method, where registerNFT is called:

async handleNFTMinted(tokenId, hostessIndex, recipient, txHash, blockNumber) {
  // ... existing code to detect NFT mint ...

  // Register NFT on Rogue Chain (existing code)
  // This also auto-starts time rewards for special NFTs (2340-2700) in the contract
  const receipt = await this.adminTxQueue.queueTransaction('registerNFT', [
    tokenId,
    hostessIndex,
    recipient
  ]);

  // Get the block timestamp from the registration transaction
  const block = await this.rogueProvider.getBlock(receipt.blockNumber);
  const blockTimestamp = block.timestamp;

  // Track time rewards locally for UI (uses exact on-chain timestamp)
  // This only stores data for special NFTs, no-op for regular NFTs
  this.timeRewardTracker.handleNFTRegistered(tokenId, hostessIndex, recipient, blockTimestamp);

  // ... rest of existing code ...
}
```

**Key Points**:
1. `registerNFT()` on-chain already starts time rewards (V3 contract)
2. EventListener gets the exact `block.timestamp` from the registration tx receipt
3. `handleNFTRegistered()` stores this timestamp for UI calculations
4. No separate `startTimeReward()` call needed - fully integrated into registration

---

## Phase 4: Frontend UI Updates

### 4.1 Special NFT Visual Treatment

In `high-rollers-nfts/public/js/ui.js`, modify NFT card rendering for My NFTs tab:

**Sort Order:**
- **My NFTs grid**: Sort by `token_id` descending (newest/highest ID on left)
- **Earnings by NFT table**: Sort by `token_id` descending (newest at top)

In `high-rollers-nfts/public/js/app.js`, modify `loadMyNFTs()` around line 570:

```javascript
// After fetching nfts, sort descending by token_id (newest first)
nfts.sort((a, b) => b.token_id - a.token_id);

grid.innerHTML = nfts.map(nft =>
  UI.renderNFTCard(nft, earningsMap[nft.token_id])
).join('');
```

In `high-rollers-nfts/public/js/revenues.js`, when rendering Earnings by NFT table:

```javascript
// Sort earnings by token_id descending (newest at top)
earnings.nfts.sort((a, b) => b.tokenId - a.tokenId);
```

**Visual Distinction Strategy:**
- **Regular NFTs**: Purple hover glow (existing `hover:scale-1.05` + violet shadow)
- **Special NFTs**: Permanent animated golden glow border + "⭐ SPECIAL" badge (no size change to avoid confusion with hover)

The key difference: special NFTs have a **permanent animated golden glow** that's always visible, not just on hover. This clearly distinguishes them from regular NFTs which only glow purple on hover.

```javascript
/**
 * Render an NFT card with special treatment for time-reward NFTs
 */
function renderNFTCard(nft, isMyNFT = false) {
  const isSpecial = nft.token_id >= 2340 && nft.token_id <= 2700;

  // Special NFTs get golden animated border (always visible, not just on hover)
  // Regular NFTs keep standard styling with purple hover effect
  const cardClasses = isSpecial
    ? 'nft-card special-nft-glow bg-gray-800 rounded-xl overflow-hidden cursor-pointer'
    : 'nft-card bg-gray-800 rounded-xl overflow-hidden cursor-pointer';

  return `
    <div class="${cardClasses}" data-token-id="${nft.token_id}">

      <!-- Special NFT Badge - Golden star to match golden glow -->
      ${isSpecial ? `
        <div class="absolute top-2 right-2 z-10">
          <span class="bg-gradient-to-r from-yellow-500 to-amber-500 text-black text-xs px-2 py-1 rounded-full font-bold shadow-lg">
            ⭐ SPECIAL
          </span>
        </div>
      ` : ''}

      <!-- NFT Image -->
      <div class="relative">
        <img src="${getHostessImageUrl(nft.hostess_index, 'card')}"
             alt="${nft.hostess_name}"
             class="w-full aspect-square object-cover">

        <!-- Multiplier Badge -->
        <div class="absolute bottom-2 left-2">
          <span class="bg-black/70 text-white text-xs px-2 py-1 rounded">
            ${config.HOSTESSES[nft.hostess_index].multiplier}x
          </span>
        </div>
      </div>

      <!-- Card Info -->
      <div class="p-3">
        <p class="font-bold text-sm">#${nft.token_id}</p>
        <p class="text-xs text-gray-400">${nft.hostess_name}</p>

        <!-- Earnings Display -->
        ${isMyNFT ? renderNFTEarnings(nft, isSpecial) : ''}
      </div>
    </div>
  `;
}
```

### 4.1.1 Special NFT CSS Styling

Add to `high-rollers-nfts/public/css/styles.css`:

```css
/* Special NFT animated golden glow - always visible, not just on hover */
.special-nft-glow {
  position: relative;
  border: 2px solid transparent;
  background:
    linear-gradient(#1f2937, #1f2937) padding-box,
    linear-gradient(135deg, #f59e0b, #fbbf24, #f59e0b) border-box;
  animation: golden-pulse 2s ease-in-out infinite;
}

@keyframes golden-pulse {
  0%, 100% {
    box-shadow: 0 0 15px rgba(251, 191, 36, 0.4),
                0 0 30px rgba(245, 158, 11, 0.2);
  }
  50% {
    box-shadow: 0 0 25px rgba(251, 191, 36, 0.6),
                0 0 50px rgba(245, 158, 11, 0.3);
  }
}

/* Special NFTs still scale on hover, but have different base state */
.special-nft-glow:hover {
  transform: scale(1.05);
  box-shadow: 0 0 35px rgba(251, 191, 36, 0.7),
              0 0 60px rgba(245, 158, 11, 0.4);
}

/* Regular NFT cards - purple glow on hover only (existing behavior) */
.nft-card {
  transition: transform 0.2s ease, box-shadow 0.2s ease;
}

.nft-card:hover:not(.special-nft-glow) {
  transform: scale(1.05);
  box-shadow: 0 10px 30px rgba(139, 92, 246, 0.4);
}
```

**Visual Summary:**
| NFT Type | Default State | Hover State |
|----------|---------------|-------------|
| Regular | No border/glow | Purple glow + scale |
| Special | **Golden animated glow** + golden border | Brighter golden glow + scale |

```javascript
/**
 * Render earnings section for My NFTs tab
 */
function renderNFTEarnings(nft, isSpecial) {
  // Revenue sharing earnings (all NFTs)
  const revenueEarnings = `
    <div class="mt-2 text-xs space-y-1">
      <div class="flex justify-between">
        <span class="text-gray-500">Pending:</span>
        <span class="text-green-400">${formatROGUE(nft.pending_reward)} ROGUE</span>
      </div>
      <div class="flex justify-between">
        <span class="text-gray-500">24h:</span>
        <span class="text-blue-400">${formatROGUE(nft.last_24h_earned)} ROGUE</span>
      </div>
      <div class="flex justify-between">
        <span class="text-gray-500">Total:</span>
        <span class="text-white">${formatROGUE(nft.total_earned)} ROGUE</span>
      </div>
    </div>
  `;

  // Time-based earnings (special NFTs only)
  if (isSpecial && nft.timeReward && nft.timeReward.hasStarted) {
    const tr = nft.timeReward;
    return `
      ${revenueEarnings}

      <!-- Time-Based Rewards Section -->
      <div class="mt-3 pt-3 border-t border-violet-500/30">
        <p class="text-violet-400 text-xs font-bold mb-2">Time Rewards</p>

        <!-- Real-time counter -->
        <div class="flex justify-between">
          <span class="text-gray-500">Earning:</span>
          <span class="text-violet-400 time-reward-counter"
                data-token-id="${nft.token_id}"
                data-rate="${tr.ratePerSecond}"
                data-pending="${tr.pending}">
            ${formatROGUE(tr.pending)} ROGUE
          </span>
        </div>

        <div class="flex justify-between">
          <span class="text-gray-500">Rate:</span>
          <span class="text-violet-300">${tr.ratePerSecond.toFixed(3)}/sec</span>
        </div>

        <div class="flex justify-between">
          <span class="text-gray-500">Remaining:</span>
          <span class="text-gray-400">${formatTimeRemaining(tr.timeRemaining)}</span>
        </div>

        <div class="flex justify-between">
          <span class="text-gray-500">180d Total:</span>
          <span class="text-violet-200">${formatROGUE(tr.totalFor180Days)} ROGUE</span>
        </div>
      </div>
    `;
  }

  return revenueEarnings;
}
```

### 4.2 Real-Time Counter Animation (Efficient Design)

**Design Principles:**
1. **Zero database queries at runtime** - All calculations done client-side using constants
2. **Zero contract reads** - Only read contract on claim/sync events
3. **Single API call** - Fetch static data once, calculate everything client-side
4. **Minimal data transfer** - Only send startTime + hostessIndex per NFT (no pending calculations server-side)

**Key Insight:** Time rewards are deterministic. Given `startTime`, `hostessIndex`, and current time, we can calculate exact pending amount client-side without any server queries.

**Data Flow:**
```
1. Page Load → Fetch static data (one API call, cached)
   API returns: [{ tokenId, hostessIndex, startTime, owner }]
   NO pending calculations - just raw data

2. Client-side → Calculate everything from constants
   - Rate per second: RATES[hostessIndex] (hardcoded constant)
   - Pending: (now - lastClaimTime) * rate
   - All aggregates computed locally

3. Every Second → Pure math, no network calls
   pending += rate (for each active NFT)

4. On Claim → Single contract call, then update local state
```

Add to `high-rollers-nfts/public/js/timeRewardCounter.js`:

```javascript
/**
 * TimeRewardCounter - Efficient client-side real-time updates
 *
 * ZERO database queries at runtime - all math done client-side
 * ZERO contract reads during normal operation
 * Single API call on init to get static NFT data
 */
class TimeRewardCounter {
  constructor() {
    // Hardcoded constants (match smart contract exactly)
    this.TIME_REWARD_DURATION = 180 * 24 * 60 * 60; // 180 days in seconds
    this.SPECIAL_NFT_START = 2340;
    this.SPECIAL_NFT_END = 2700;

    // Rates per second for each hostess (ROGUE, not wei)
    // These are constants - never need to query
    this.RATES = [
      2.125,  // Penelope (100x)
      1.912,  // Mia (90x)
      1.700,  // Cleo (80x)
      1.487,  // Sophia (70x)
      1.275,  // Luna (60x)
      1.062,  // Aurora (50x)
      0.850,  // Scarlett (40x)
      0.637,  // Vivienne (30x)
    ];

    // NFT data: Map<tokenId, { hostessIndex, startTime, lastClaimTime, owner }>
    this.nfts = new Map();

    // Cached aggregates (recalculated only when NFT data changes)
    this.cache = {
      globalRate: 0,        // Sum of all active rates
      myRate: 0,            // Sum of my NFT rates
      hostessRates: new Array(8).fill(0),  // Per-hostess active rates
      lastUpdate: 0,        // Timestamp of last full recalc
    };

    this.myWallet = null;
    this.intervalId = null;
    this.initialized = false;
  }

  /**
   * Initialize with static NFT data (ONE database query, cached)
   * @param {Array} nftData - [{ tokenId, hostessIndex, startTime, lastClaimTime, owner }]
   * @param {string} myWallet - Current user's wallet address
   */
  async initialize(myWallet) {
    this.myWallet = myWallet?.toLowerCase();

    // Single API call - returns only static data, no calculations
    const response = await fetch('/api/revenues/time-rewards/static-data');
    const nftData = await response.json();

    this.nfts.clear();
    const now = Math.floor(Date.now() / 1000);

    for (const nft of nftData) {
      // Skip if not started or already ended
      if (!nft.startTime) continue;
      const endTime = nft.startTime + this.TIME_REWARD_DURATION;
      if (now >= endTime) continue; // Already ended

      this.nfts.set(nft.tokenId, {
        hostessIndex: nft.hostessIndex,
        startTime: nft.startTime,
        lastClaimTime: nft.lastClaimTime || nft.startTime,
        owner: nft.owner?.toLowerCase(),
        endTime: endTime,
      });
    }

    // Calculate aggregate rates (once)
    this.recalculateCache();
    this.initialized = true;

    console.log(`[TimeRewardCounter] Initialized: ${this.nfts.size} active NFTs, global rate: ${this.cache.globalRate.toFixed(3)}/sec`);
  }

  /**
   * Recalculate cached aggregates (only on data change, not every tick)
   */
  recalculateCache() {
    this.cache.globalRate = 0;
    this.cache.myRate = 0;
    this.cache.hostessRates = new Array(8).fill(0);

    const now = Math.floor(Date.now() / 1000);

    for (const [tokenId, data] of this.nfts) {
      // Skip ended NFTs
      if (now >= data.endTime) continue;

      const rate = this.RATES[data.hostessIndex];
      this.cache.globalRate += rate;
      this.cache.hostessRates[data.hostessIndex] += rate;

      if (this.myWallet && data.owner === this.myWallet) {
        this.cache.myRate += rate;
      }
    }

    this.cache.lastUpdate = now;
  }

  /**
   * Calculate pending for a single NFT (pure math, no queries)
   */
  getPending(tokenId) {
    const data = this.nfts.get(tokenId);
    if (!data) return 0;

    const now = Math.floor(Date.now() / 1000);
    const effectiveNow = Math.min(now, data.endTime);
    const elapsed = effectiveNow - data.lastClaimTime;

    return elapsed * this.RATES[data.hostessIndex];
  }

  /**
   * Calculate all pending totals (pure math, no queries)
   */
  getTotals() {
    const now = Math.floor(Date.now() / 1000);
    let globalPending = 0;
    let myPending = 0;
    const hostessPending = new Array(8).fill(0);

    for (const [tokenId, data] of this.nfts) {
      const effectiveNow = Math.min(now, data.endTime);
      const elapsed = effectiveNow - data.lastClaimTime;
      const pending = elapsed * this.RATES[data.hostessIndex];

      globalPending += pending;
      hostessPending[data.hostessIndex] += pending;

      if (this.myWallet && data.owner === this.myWallet) {
        myPending += pending;
      }
    }

    return { globalPending, myPending, hostessPending };
  }

  /**
   * Get 24h earnings - handles edge cases accurately
   *
   * KEY INSIGHT: For time-based rewards, the 24h calculation is simple:
   *
   * For ACTIVE NFTs in steady state (started > 24h ago, ending > 24h from now):
   *   24h = rate × 86400 (CONSTANT - same amount enters and exits the window)
   *
   * Edge cases that need special handling:
   *   - NFT started < 24h ago: 24h = rate × seconds_since_start (growing)
   *   - NFT ending within 24h: 24h = rate × seconds_remaining (shrinking)
   *   - NFT ended < 24h ago: 24h = rate × overlap_with_24h_window (shrinking)
   *   - NFT ended > 24h ago: 24h = 0
   *
   * Formula: 24h = rate × (min(endTime, now) - max(startTime, oneDayAgo))
   *          Clamped to 0 if result is negative
   */
  get24hEarnings() {
    const now = Math.floor(Date.now() / 1000);
    const oneDayAgo = now - 86400;

    let global24h = 0;
    let my24h = 0;
    const hostess24h = new Array(8).fill(0);

    for (const [tokenId, data] of this.nfts) {
      const rate = this.RATES[data.hostessIndex];

      // Calculate the overlap between [startTime, endTime] and [oneDayAgo, now]
      const windowStart = Math.max(data.startTime, oneDayAgo);
      const windowEnd = Math.min(data.endTime, now);

      let nft24h = 0;
      if (windowEnd > windowStart) {
        // NFT was active for this many seconds in the last 24 hours
        nft24h = rate * (windowEnd - windowStart);
      }

      global24h += nft24h;
      hostess24h[data.hostessIndex] += nft24h;

      if (this.myWallet && data.owner === this.myWallet) {
        my24h += nft24h;
      }
    }

    return { global: global24h, my: my24h, hostess: hostess24h };
  }

  /*
   * ═══════════════════════════════════════════════════════════════════
   * 24H CALCULATION EXAMPLES (for understanding)
   * ═══════════════════════════════════════════════════════════════════
   *
   * Example 1: STEADY STATE (most common)
   * ─────────────────────────────────────
   * NFT started 30 days ago, ends in 150 days
   * Rate: 2.125 ROGUE/sec
   *
   *   oneDayAgo ────────────────────────── now
   *        |◄─────── 86400 seconds ───────►|
   *   ════════════════════════════════════════════  (NFT active entire period)
   *   startTime                               endTime
   *   (30 days ago)                          (150 days from now)
   *
   *   windowStart = max(startTime, oneDayAgo) = oneDayAgo
   *   windowEnd = min(endTime, now) = now
   *   activeSeconds = now - oneDayAgo = 86400
   *   24h = 2.125 × 86400 = 183,600 ROGUE ✓
   *
   *
   * Example 2: NFT JUST STARTED (12 hours ago)
   * ──────────────────────────────────────────
   *   oneDayAgo ──────── startTime ────────── now
   *        |               |◄─── 12 hours ───►|
   *                   ════════════════════════════  (NFT only active 12h)
   *
   *   windowStart = max(startTime, oneDayAgo) = startTime
   *   windowEnd = min(endTime, now) = now
   *   activeSeconds = now - startTime = 43200 (12 hours)
   *   24h = 2.125 × 43200 = 91,800 ROGUE (half of full day)
   *
   *   Next hour: activeSeconds = 46800, 24h = 99,450 ROGUE (growing!)
   *
   *
   * Example 3: NFT ENDING SOON (6 hours remaining)
   * ───────────────────────────────────────────────
   *   oneDayAgo ─────────────────── now ── endTime
   *        |◄────── 86400 sec ──────►|      |
   *   ═══════════════════════════════════════      (only 6h left to earn)
   *                                    ◄─6h─►
   *
   *   windowStart = max(startTime, oneDayAgo) = oneDayAgo
   *   windowEnd = min(endTime, now) = now (endTime is in future)
   *   activeSeconds = 86400 (still full day - endTime hasn't hit yet)
   *   24h = 183,600 ROGUE
   *
   *   But 6 hours later (endTime reached):
   *   windowEnd = min(endTime, now) = endTime
   *   activeSeconds = endTime - oneDayAgo = 86400 + 21600 - 86400 = 21600? No wait...
   *
   *   Actually let me redo this. After endTime:
   *   oneDayAgo' ─────────── endTime ─────── now'
   *        |                    |◄──── X ────►|
   *   ═════════════════════════════
   *        ◄── still in window ──►
   *
   *   windowStart = oneDayAgo'
   *   windowEnd = endTime (capped because NFT ended)
   *   activeSeconds = endTime - oneDayAgo' (shrinking as oneDayAgo' moves forward!)
   *
   *
   * Example 4: NFT ENDED 12 HOURS AGO
   * ─────────────────────────────────
   *   oneDayAgo ──── endTime ─────────────── now
   *        |◄── 12h ──►|                      |
   *   ═════════════════
   *        ◄─ overlap ─►
   *
   *   windowStart = oneDayAgo
   *   windowEnd = endTime
   *   activeSeconds = endTime - oneDayAgo = 43200 (12 hours of overlap)
   *   24h = 2.125 × 43200 = 91,800 ROGUE (and shrinking every second!)
   *
   *
   * Example 5: NFT ENDED > 24 HOURS AGO
   * ────────────────────────────────────
   *   endTime ──── oneDayAgo ─────────────── now
   *      |              |                     |
   *   ═══               (no overlap)
   *
   *   windowStart = max(startTime, oneDayAgo) = oneDayAgo
   *   windowEnd = min(endTime, now) = endTime
   *   windowEnd < windowStart → activeSeconds = 0
   *   24h = 0 ROGUE ✓
   *
   * ═══════════════════════════════════════════════════════════════════
   */

  /**
   * Start 1-second UI update loop
   */
  start() {
    if (this.intervalId) return;

    this.intervalId = setInterval(() => {
      this.updateUI();
    }, 1000);
  }

  /**
   * Update all UI elements (no queries, just display cached/calculated values)
   */
  updateUI() {
    if (!this.initialized) return;

    const totals = this.getTotals();
    const earnings24h = this.get24hEarnings();

    // ---- Global Stats (Mint Tab, Revenues Tab) ----
    this.updateElement('mint-total-time-rewards', totals.globalPending);
    this.updateElement('global-time-rewards-pending', totals.globalPending);
    this.updateElement('global-time-rewards-24h', earnings24h.global);

    // ---- My Earnings ----
    this.updateElement('my-time-rewards-pending', totals.myPending);
    this.updateElement('my-time-rewards-24h', earnings24h.my);

    // Combined pending (revenue + time)
    const combinedEl = document.getElementById('my-total-pending');
    if (combinedEl) {
      const revenuePending = parseFloat(combinedEl.dataset.revenuePending || 0);
      combinedEl.textContent = formatROGUE(revenuePending + totals.myPending) + ' ROGUE';
    }

    // ---- Per-NFT Cards (My NFTs Tab) ----
    document.querySelectorAll('[data-time-reward-token]').forEach(el => {
      const tokenId = parseInt(el.dataset.timeRewardToken);
      const pending = this.getPending(tokenId);
      el.textContent = formatROGUE(pending) + ' ROGUE';
    });

    // ---- Countdown Timers ----
    const now = Math.floor(Date.now() / 1000);
    document.querySelectorAll('[data-time-remaining-token]').forEach(el => {
      const tokenId = parseInt(el.dataset.timeRemainingToken);
      const data = this.nfts.get(tokenId);
      if (data) {
        const remaining = Math.max(0, data.endTime - now);
        el.textContent = formatTimeRemaining(remaining);
      }
    });

    // ---- Per-Hostess (Gallery Tab) ----
    for (let i = 0; i < 8; i++) {
      this.updateElement(`hostess-${i}-time-24h`, earnings24h.hostess[i]);
      this.updateElement(`hostess-${i}-time-pending`, totals.hostessPending[i]);
    }
  }

  updateElement(id, value) {
    const el = document.getElementById(id);
    if (el) el.textContent = formatROGUE(value);
  }

  /**
   * Called after successful claim - update local state (no API call)
   */
  onClaimed(tokenIds) {
    const now = Math.floor(Date.now() / 1000);
    for (const tokenId of tokenIds) {
      const data = this.nfts.get(tokenId);
      if (data) {
        data.lastClaimTime = now;
      }
    }
    // No need to recalculate cache - rates don't change on claim
  }

  /**
   * Called when new special NFT is registered (WebSocket event)
   */
  onNewNFT(nft) {
    const endTime = nft.startTime + this.TIME_REWARD_DURATION;

    this.nfts.set(nft.tokenId, {
      hostessIndex: nft.hostessIndex,
      startTime: nft.startTime,
      lastClaimTime: nft.startTime,
      owner: nft.owner?.toLowerCase(),
      endTime: endTime,
    });

    // Recalculate cache since rates changed
    this.recalculateCache();
  }

  /**
   * Called when wallet connects/disconnects
   */
  setMyWallet(wallet) {
    this.myWallet = wallet?.toLowerCase();
    this.recalculateCache();
  }
}

// Global instance
const timeRewardCounter = new TimeRewardCounter();

// Initialize on page load
document.addEventListener('DOMContentLoaded', async () => {
  await timeRewardCounter.initialize(walletService.address);
  timeRewardCounter.start();
});

// Re-calculate "my" totals when wallet connects
walletService.on('connected', (address) => {
  timeRewardCounter.setMyWallet(address);
});

walletService.on('disconnected', () => {
  timeRewardCounter.setMyWallet(null);
});
```

### 4.3 API Endpoint - Static Data Only (One Query, Cached)

Add to `high-rollers-nfts/server/routes/revenues.js`:

```javascript
/**
 * GET /api/revenues/time-rewards/static-data
 * Returns ONLY static NFT data - no calculations
 * Client calculates everything from this + hardcoded constants
 *
 * Response is cacheable - data only changes on mint/claim events
 */
router.get('/time-rewards/static-data', async (req, res) => {
  try {
    // Single database query - no joins, no calculations
    const nfts = db.prepare(`
      SELECT token_id as tokenId,
             hostess_index as hostessIndex,
             start_time as startTime,
             last_claim_time as lastClaimTime,
             owner
      FROM time_reward_nfts
      WHERE start_time > 0
    `).all();

    // Cache for 60 seconds (data rarely changes)
    res.set('Cache-Control', 'public, max-age=60');
    res.json(nfts);

  } catch (error) {
    console.error('[TimeRewards] Error getting static data:', error);
    res.status(500).json({ error: error.message });
  }
});
```

### 4.4 Performance Summary

| Operation | Database Queries | Contract Reads | Frequency |
|-----------|-----------------|----------------|-----------|
| Page load | 1 (static data) | 0 | Once |
| Every second tick | 0 | 0 | 1/sec |
| Wallet connect | 0 | 0 | On connect |
| New NFT (WebSocket) | 0 | 0 | On event |
| Claim rewards | 0 | 1 (tx) | On claim |

**Why This is Efficient:**
1. **Deterministic math** - Given `startTime` and `hostessIndex`, pending amount is calculable without queries
2. **Constants hardcoded** - Rates are fixed in contract, no need to query
3. **Cache aggregates** - Only recalculate sums when NFT list changes
4. **60-second HTTP cache** - Static data rarely changes

**Helper Function:**
```javascript
function formatROGUE(amount) {
  if (amount >= 1_000_000) {
    return (amount / 1_000_000).toFixed(2) + 'M';
  } else if (amount >= 1_000) {
    return (amount / 1_000).toFixed(2) + 'K';
  } else {
    return amount.toFixed(2);
  }
}

function formatTimeRemaining(seconds) {
  if (seconds <= 0) return 'Ended';
  const days = Math.floor(seconds / 86400);
  const hours = Math.floor((seconds % 86400) / 3600);
  if (days > 0) return `${days}d ${hours}h`;
  const minutes = Math.floor((seconds % 3600) / 60);
  return hours > 0 ? `${hours}h ${minutes}m` : `${minutes}m`;
}
```

### 4.3 My Earnings Section Updates

Modify the My Earnings section to show combined earnings with Special NFTs section.

#### 4.3.1 Special NFTs Section HTML Structure

The Special NFTs section displays time-based rewards for NFTs #2340-2700 with the following field order:
1. **Total Earned** - Total time rewards earned since start
2. **Pending** - Unclaimed rewards
3. **24h** - Earnings in last 24 hours
4. **180d Total** - Total allocation for the full 180-day period
5. **APY** - Annualized percentage yield

Each ROGUE value (except APY) includes a USD value displayed below it.

**HTML Structure** (`public/index.html`):
```html
<div id="special-nfts-section" class="mb-6 hidden">
  <div class="bg-gradient-to-r from-amber-900/30 to-yellow-900/30 border border-amber-500/50 p-4 rounded-lg">
    <div class="flex items-center gap-2 mb-3">
      <span class="text-xl">⭐</span>
      <h3 class="font-bold text-amber-400">Special NFTs (<span id="special-nfts-count">0</span>) - Time-Based Rewards</h3>
    </div>
    <div class="grid grid-cols-2 md:grid-cols-5 gap-4 text-sm">
      <div>
        <p class="text-gray-400">Total Earned</p>
        <p id="my-time-rewards-total" class="text-lg font-bold text-green-400 flex items-baseline gap-1">0 <span class="text-sm text-gray-400 font-normal">ROGUE</span></p>
        <p id="my-time-rewards-total-usd" class="text-xs text-gray-500">$0.00</p>
      </div>
      <div>
        <p class="text-gray-400">Pending</p>
        <p id="my-time-rewards-pending" class="text-lg font-bold text-yellow-400 flex items-baseline gap-1">0 <span class="text-sm text-gray-400 font-normal">ROGUE</span></p>
        <p id="my-time-rewards-pending-usd" class="text-xs text-gray-500">$0.00</p>
      </div>
      <div>
        <p class="text-gray-400">24h</p>
        <p id="my-time-rewards-24h" class="text-lg font-bold text-purple-400 flex items-baseline gap-1">0 <span class="text-sm text-gray-400 font-normal">ROGUE</span></p>
        <p id="my-time-rewards-24h-usd" class="text-xs text-gray-500">$0.00</p>
      </div>
      <div>
        <p class="text-gray-400">180d Total</p>
        <p id="special-nfts-180d" class="text-lg font-bold text-white flex items-baseline gap-1">0 <span class="text-sm text-gray-400 font-normal">ROGUE</span></p>
        <p id="special-nfts-180d-usd" class="text-xs text-gray-500">$0.00</p>
      </div>
      <div>
        <p class="text-gray-400">APY</p>
        <p id="my-special-nfts-apy" class="text-lg font-bold text-purple-400">0%</p>
      </div>
    </div>
    <p class="text-xs text-gray-500 mt-3">Special NFTs (#2340-2700) earn additional time-based rewards for 180 days from registration.</p>
  </div>
</div>
```

#### 4.3.2 Real-Time Updates via TimeRewardCounter

The `updateSpecialNFTsSection()` method in `timeRewardCounter.js` updates all Special NFTs section values every second with USD values. ROGUE values are displayed without decimal places using `Math.floor().toLocaleString('en-US')`:

```javascript
/**
 * Update Special NFTs section in My Earnings tab
 * Called from updateUI() every second for real-time counters
 */
updateSpecialNFTsSection(totals, earnings24h, now) {
  const roguePrice = window.revenueService?.priceService?.roguePrice || 0;

  let myTimeTotal = 0;
  let myTotal180d = 0;
  let myNftCount = 0;
  for (const [tokenId, data] of this.nfts) {
    if (this.myWallet && data.owner === this.myWallet) {
      const effectiveNow = Math.min(now, data.endTime);
      myTimeTotal += Math.max(0, effectiveNow - data.startTime) * this.RATES[data.hostessIndex];
      myTotal180d += this.RATES[data.hostessIndex] * this.TIME_REWARD_DURATION;
      myNftCount++;
    }
  }

  // Total Earned (no decimals)
  const totalEl = document.getElementById('my-time-rewards-total');
  const totalUsdEl = document.getElementById('my-time-rewards-total-usd');
  if (totalEl) {
    totalEl.innerHTML = `${Math.floor(myTimeTotal).toLocaleString('en-US')} <span class="text-sm text-gray-400 font-normal">ROGUE</span>`;
    if (totalUsdEl) totalUsdEl.textContent = this.formatUSD(myTimeTotal, roguePrice);
  }

  // Pending (no decimals)
  const pendingEl = document.getElementById('my-time-rewards-pending');
  const pendingUsdEl = document.getElementById('my-time-rewards-pending-usd');
  if (pendingEl) {
    pendingEl.innerHTML = `${Math.floor(totals.myPending).toLocaleString('en-US')} <span class="text-sm text-gray-400 font-normal">ROGUE</span>`;
    if (pendingUsdEl) pendingUsdEl.textContent = this.formatUSD(totals.myPending, roguePrice);
  }

  // 24h (no decimals)
  const h24El = document.getElementById('my-time-rewards-24h');
  const h24UsdEl = document.getElementById('my-time-rewards-24h-usd');
  if (h24El) {
    h24El.innerHTML = `${Math.floor(earnings24h.my).toLocaleString('en-US')} <span class="text-sm text-gray-400 font-normal">ROGUE</span>`;
    if (h24UsdEl) h24UsdEl.textContent = this.formatUSD(earnings24h.my, roguePrice);
  }

  // 180d Total (no decimals)
  const total180dEl = document.getElementById('special-nfts-180d');
  const total180dUsdEl = document.getElementById('special-nfts-180d-usd');
  if (total180dEl) {
    total180dEl.innerHTML = `${Math.floor(myTotal180d).toLocaleString('en-US')} <span class="text-sm text-gray-400 font-normal">ROGUE</span>`;
    if (total180dUsdEl) total180dUsdEl.textContent = this.formatUSD(myTotal180d, roguePrice);
  }

  // NFT Count (in header title)
  const countEl = document.getElementById('special-nfts-count');
  if (countEl) countEl.textContent = myNftCount;
}
```

This method is called in `updateUI()`:
```javascript
updateUI() {
  // ... existing code ...

  if (this.myWallet && this.hasMySpecialNFTs()) {
    this.updateMyEarningsStats(totals, earnings24h);
    this.updateSpecialNFTsSection(totals, earnings24h, now);
  }
}
```

#### 4.3.3 Show/Hide Logic in revenues.js

The `renderSpecialNFTsSection()` method controls visibility based on API data:

```javascript
renderSpecialNFTsSection() {
  const section = document.getElementById('special-nfts-section');
  if (!section) return;

  const data = this.userTimeRewards;
  if (!data || !data.nfts || data.nfts.length === 0) {
    section.classList.add('hidden');
    return;
  }

  section.classList.remove('hidden');
  document.getElementById('special-nfts-count').textContent = data.nftCount || data.nfts.length;

  // Trigger APY calculation update
  window.timeRewardCounter?.updateMySpecialNFTsAPY();
}
```

#### 4.3.4 Loading User Earnings

```javascript
/**
 * Load and display user's combined earnings (revenue sharing + time rewards)
 */
async function loadMyEarnings(walletAddress) {
  // Get revenue sharing earnings
  const revenueResponse = await fetch(`/api/revenues/user/${walletAddress}`);
  const revenueData = await revenueResponse.json();

  // Get time reward earnings
  const timeResponse = await fetch(`/api/revenues/time-rewards/user/${walletAddress}`);
  const timeData = await timeResponse.json();

  // Combine totals
  const combinedPending = revenueData.totalPending + timeData.totalPending;
  const combinedEarned = revenueData.totalEarned + timeData.totalEarned;
  const combinedClaimed = revenueData.totalClaimed + timeData.totalClaimed;

  // Update UI
  document.getElementById('my-total-pending').textContent = formatROGUE(combinedPending);
  document.getElementById('my-total-earned').textContent = formatROGUE(combinedEarned);
  document.getElementById('my-total-claimed').textContent = formatROGUE(combinedClaimed);

  // Show special NFTs section if user has any
  if (timeData.nftCount > 0) {
    document.getElementById('special-nfts-section').classList.remove('hidden');
    document.getElementById('special-nfts-count').textContent = timeData.nftCount;
    // Real-time values updated by TimeRewardCounter.updateSpecialNFTsSection()
  }

  return { revenueData, timeData };
}
```

### 4.4 Withdrawal UI

The withdrawal flow should claim BOTH revenue sharing rewards AND time rewards:

```javascript
/**
 * Handle withdraw all button click
 * Claims both revenue sharing and time-based rewards
 */
async function handleWithdrawAll() {
  const walletAddress = walletService.address;

  try {
    setWithdrawLoading(true);

    // Get all user's NFTs
    const myNFTs = await fetch(`/api/nfts/${walletAddress}`).then(r => r.json());
    const tokenIds = myNFTs.map(n => n.token_id);

    // Claim revenue sharing rewards
    const revenueResult = await fetch('/api/revenues/withdraw', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ tokenIds, recipient: walletAddress })
    }).then(r => r.json());

    // Get special NFT token IDs
    const specialTokenIds = tokenIds.filter(id => id >= 2340 && id <= 2700);

    // Claim time-based rewards if user has special NFTs
    if (specialTokenIds.length > 0) {
      const timeResult = await fetch('/api/revenues/time-rewards/claim', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ tokenIds: specialTokenIds, recipient: walletAddress })
      }).then(r => r.json());

      showSuccess(`Claimed both revenue sharing and time rewards!`);
    } else {
      showSuccess(`Claimed revenue sharing rewards!`);
    }

    // Refresh earnings display
    await loadMyEarnings(walletAddress);

  } catch (error) {
    showError(error.message);
  } finally {
    setWithdrawLoading(false);
  }
}
```

---

## Phase 5: Aggregate Totals Integration

### 5.1 Earnings Calculation Updates

The existing revenue sharing earnings calculations need to include time-based rewards in their totals:

**EarningsSyncService Updates** (`earningsSyncService.js`):

```javascript
/**
 * Calculate total earnings including both revenue sharing AND time rewards
 */
async calculateNFTEarnings(tokenId) {
  // Get revenue sharing earnings (existing logic)
  const revenueEarnings = await this.calculateRevenueEarnings(tokenId);

  // Get time-based earnings if special NFT
  let timeEarnings = { pending: 0, total: 0, last24h: 0 };

  if (tokenId >= 2340 && tokenId <= 2700) {
    const timeInfo = this.timeRewardTracker.calculatePendingReward(tokenId);
    timeEarnings = {
      pending: timeInfo.pending,
      total: timeInfo.totalEarned + timeInfo.pending,
      last24h: this.calculateTime24hEarnings(tokenId, timeInfo.ratePerSecond)
    };
  }

  return {
    tokenId,
    // Revenue sharing
    revenuePending: revenueEarnings.pending,
    revenueTotalEarned: revenueEarnings.total,
    revenueLast24h: revenueEarnings.last24h,
    // Time-based
    timePending: timeEarnings.pending,
    timeTotalEarned: timeEarnings.total,
    timeLast24h: timeEarnings.last24h,
    // Combined
    totalPending: revenueEarnings.pending + timeEarnings.pending,
    totalEarned: revenueEarnings.total + timeEarnings.total,
    totalLast24h: revenueEarnings.last24h + timeEarnings.last24h
  };
}

/**
 * Calculate 24h time-based earnings
 * Since rate is constant, just multiply rate by 86400 (if within active period)
 */
calculateTime24hEarnings(tokenId, ratePerSecond) {
  const nft = this.db.getTimeRewardNFT(tokenId);
  if (!nft || !nft.start_time) return 0;

  const now = Math.floor(Date.now() / 1000);
  const endTime = nft.start_time + (180 * 24 * 60 * 60);

  // If reward period has ended
  if (now >= endTime) {
    // Check if ended within last 24 hours
    const yesterday = now - 86400;
    if (yesterday >= endTime) return 0;

    // Partial day
    return ratePerSecond * (endTime - yesterday);
  }

  // Full 24 hours of earnings
  return ratePerSecond * 86400;
}
```

### 5.2 Global Stats Updates

**Modify Gallery Tab APY/24h Calculations**:

```javascript
/**
 * Calculate per-hostess stats including time rewards
 */
async calculateHostessStats(hostessIndex) {
  const count = this.db.getHostessCount(hostessIndex);
  const multiplier = config.HOSTESSES[hostessIndex].multiplier;

  // Revenue sharing stats (existing)
  const revenueStats = await this.calculateRevenueStats(hostessIndex);

  // Time reward stats for this hostess type
  const specialNFTs = this.db.getSpecialNFTsByHostess(hostessIndex);
  let timeTotal24h = 0;
  let timeApy = 0;

  if (specialNFTs.length > 0) {
    const ratePerSecond = this.timeRewardTracker.getRatePerSecond(hostessIndex);

    // Calculate 24h from active special NFTs
    for (const nft of specialNFTs) {
      timeTotal24h += this.calculateTime24hEarnings(nft.token_id, ratePerSecond);
    }

    // APY for time rewards (simple: total180d / 180 * 365 / nftPrice)
    const totalFor180Days = ratePerSecond * 180 * 86400;
    const annualized = totalFor180Days * (365 / 180);
    const nftPriceInROGUE = 10_400_000; // ~0.32 ETH in ROGUE
    timeApy = (annualized / nftPriceInROGUE) * 100;
  }

  return {
    hostessIndex,
    hostessName: config.HOSTESSES[hostessIndex].name,
    multiplier,
    count,
    // Revenue sharing
    revenue24h: revenueStats.last24h,
    revenueApy: revenueStats.apy,
    // Time rewards
    time24h: timeTotal24h,
    timeApy: specialNFTs.length > 0 ? timeApy : 0,
    // Combined
    total24h: revenueStats.last24h + timeTotal24h,
    totalApy: revenueStats.apy + (specialNFTs.length > 0 ? timeApy : 0)
  };
}
```

---

## Phase 6: Latest Payouts Table

### 6.1 Keeping Revenue Sharing Payouts Separate

The "Latest Payouts to NFTs" table should **ONLY** show rewards from ROGUEBankroll (game losses), NOT time-based rewards:

```javascript
/**
 * Get recent payouts - ONLY revenue sharing from game losses
 * Time-based rewards are NOT included in this list
 */
async getRecentPayouts(limit = 50) {
  // Only query reward_events table (populated by RewardEventListener)
  // Time reward claims are stored in time_reward_claims table (separate)

  const payouts = this.db.prepare(`
    SELECT
      re.bet_id,
      re.amount,
      re.timestamp,
      n.token_id,
      n.hostess_name,
      n.owner
    FROM reward_events re
    JOIN nfts n ON n.owner IS NOT NULL
    ORDER BY re.timestamp DESC
    LIMIT ?
  `).all(limit);

  return payouts.map(p => ({
    ...p,
    type: 'REVENUE_SHARING',  // Always revenue sharing in this table
    source: 'BUX Booster Loss'
  }));
}
```

### 6.2 UI Clarification

Add clear labels to distinguish reward types:

```html
<!-- Latest Payouts Table -->
<section class="mb-8">
  <div class="flex justify-between items-center mb-4">
    <h2 class="text-xl font-bold">Latest Payouts to NFTs</h2>
    <span class="text-xs text-gray-500">From BUX Booster game losses only</span>
  </div>

  <div class="bg-gray-800 rounded-lg overflow-hidden">
    <table class="w-full text-sm">
      <thead class="bg-gray-700">
        <tr>
          <th class="p-3 text-left">Time</th>
          <th class="p-3 text-left">Bet ID</th>
          <th class="p-3 text-left">Amount</th>
          <th class="p-3 text-left">Source</th>
        </tr>
      </thead>
      <tbody id="recent-payouts-body">
        <!-- Populated by JavaScript -->
      </tbody>
    </table>
  </div>

  <!-- Note about time rewards -->
  <p class="text-xs text-gray-500 mt-2">
    Time-based rewards for special NFTs (2340-2700) accrue automatically and are not shown here.
  </p>
</section>
```

---

## Phase 7: WebSocket Updates

### 7.1 New Broadcast Events

Add these broadcast types to `websocket.js`:

```javascript
// Broadcast when special NFT time rewards start
ws.broadcast({
  type: 'SPECIAL_NFT_STARTED',
  data: {
    tokenId,
    hostessIndex,
    owner,
    startTime,
    ratePerSecond,
    totalFor180Days
  }
});

// Broadcast when time rewards are claimed
ws.broadcast({
  type: 'TIME_REWARD_CLAIMED',
  data: {
    tokenIds,
    recipient,
    totalAmount,
    txHash
  }
});
```

### 7.2 Client-Side Handlers

```javascript
// Handle WebSocket messages
ws.onmessage = (event) => {
  const message = JSON.parse(event.data);

  switch (message.type) {
    case 'SPECIAL_NFT_STARTED':
      // Update UI for new special NFT
      handleSpecialNFTStarted(message.data);
      break;

    case 'TIME_REWARD_CLAIMED':
      // Refresh earnings display
      if (message.data.recipient.toLowerCase() === walletService.address?.toLowerCase()) {
        loadMyEarnings(walletService.address);
      }
      break;

    // ... existing handlers
  }
};
```

---

## Phase 8: Testing Plan

### 8.1 Smart Contract Tests

Create `contracts/bux-booster-game/test/NFTRewarderV3.test.js`:

```javascript
describe("NFTRewarder V3 - Time-Based Rewards", function() {

  describe("depositTimeRewards", function() {
    it("should accept ROGUE deposit from owner", async function() {
      const depositAmount = ethers.parseEther("1000000");
      await nftRewarder.connect(owner).depositTimeRewards({ value: depositAmount });

      expect(await nftRewarder.timeRewardPoolDeposited()).to.equal(depositAmount);
      expect(await nftRewarder.timeRewardPoolRemaining()).to.equal(depositAmount);
    });

    it("should reject deposit from non-owner", async function() {
      await expect(
        nftRewarder.connect(admin).depositTimeRewards({ value: ethers.parseEther("1000") })
      ).to.be.revertedWith("Ownable: caller is not the owner");
    });
  });

  describe("registerNFT (with auto time rewards)", function() {
    it("should auto-start time rewards for special NFT (2340-2700)", async function() {
      const tokenId = 2340;
      await nftRewarder.connect(admin).registerNFT(tokenId, 0, user1.address); // Penelope

      // Verify time reward started
      const info = await nftRewarder.timeRewardInfo(tokenId);
      expect(info.startTime).to.be.gt(0);
      expect(info.lastClaimTime).to.equal(info.startTime);

      // Verify NFT is registered
      const metadata = await nftRewarder.nftMetadata(tokenId);
      expect(metadata.registered).to.be.true;
      expect(metadata.hostessIndex).to.equal(0);

      // Verify special NFT counter increased
      expect(await nftRewarder.totalSpecialNFTsRegistered()).to.equal(1);
    });

    it("should NOT start time rewards for non-special NFT", async function() {
      const tokenId = 2339; // Just before special range
      await nftRewarder.connect(admin).registerNFT(tokenId, 7, user1.address);

      // Time rewards should NOT be started
      const info = await nftRewarder.timeRewardInfo(tokenId);
      expect(info.startTime).to.equal(0);

      // But NFT should still be registered normally
      const metadata = await nftRewarder.nftMetadata(tokenId);
      expect(metadata.registered).to.be.true;
    });

    it("should emit TimeRewardStarted for special NFT", async function() {
      const tokenId = 2341;
      const tx = await nftRewarder.connect(admin).registerNFT(tokenId, 1, user1.address); // Mia

      await expect(tx).to.emit(nftRewarder, "TimeRewardStarted")
        .withArgs(tokenId, anyValue, timeRewardRatesPerSecond[1]);
    });
  });

  describe("pendingTimeReward", function() {
    it("should calculate correct pending rewards", async function() {
      const tokenId = 2340; // Penelope (100x) - 2.125 ROGUE/sec
      // Register starts time rewards automatically
      await nftRewarder.connect(admin).registerNFT(tokenId, 0, user1.address);

      // Fast forward 1 hour
      await ethers.provider.send("evm_increaseTime", [3600]);
      await ethers.provider.send("evm_mine");

      const [pending, rate, remaining] = await nftRewarder.pendingTimeReward(tokenId);

      // Expected: 2.125 * 3600 = 7650 ROGUE
      expect(pending).to.be.closeTo(ethers.parseEther("7650"), ethers.parseEther("1"));
    });

    it("should cap at 180 days", async function() {
      const tokenId = 2340;
      await nftRewarder.connect(admin).registerNFT(tokenId, 0, user1.address);

      // Fast forward 200 days
      await ethers.provider.send("evm_increaseTime", [200 * 86400]);
      await ethers.provider.send("evm_mine");

      const [pending, rate, remaining] = await nftRewarder.pendingTimeReward(tokenId);

      // Should be capped at 180 days worth
      // 2.125 * 180 * 86400 = 33,048,000 ROGUE
      expect(pending).to.be.closeTo(ethers.parseEther("33048000"), ethers.parseEther("1000"));
      expect(remaining).to.equal(0);
    });
  });

  describe("claimTimeRewards", function() {
    it("should transfer rewards to recipient", async function() {
      const tokenId = 2340;
      const recipient = user1.address;

      // Register starts time rewards automatically
      await nftRewarder.connect(admin).registerNFT(tokenId, 0, recipient);

      // Fast forward 1 day
      await ethers.provider.send("evm_increaseTime", [86400]);
      await ethers.provider.send("evm_mine");

      const balanceBefore = await ethers.provider.getBalance(recipient);
      await nftRewarder.connect(admin).claimTimeRewards([tokenId], recipient);
      const balanceAfter = await ethers.provider.getBalance(recipient);

      // Expected: 2.125 * 86400 = 183,600 ROGUE
      expect(balanceAfter - balanceBefore).to.be.closeTo(
        ethers.parseEther("183600"),
        ethers.parseEther("100")
      );
    });

    it("should update lastClaimTime", async function() {
      const tokenId = 2340;

      await nftRewarder.connect(admin).registerNFT(tokenId, 0, user1.address);
      await ethers.provider.send("evm_increaseTime", [3600]);
      await nftRewarder.connect(admin).claimTimeRewards([tokenId], user1.address);

      const info = await nftRewarder.timeRewardInfo(tokenId);
      expect(info.lastClaimTime).to.be.gt(info.startTime);
    });

    it("should reset pending to 0 after claim", async function() {
      const tokenId = 2341;
      await nftRewarder.connect(admin).registerNFT(tokenId, 1, user1.address); // Mia

      // Earn some rewards
      await ethers.provider.send("evm_increaseTime", [3600]);
      await ethers.provider.send("evm_mine");

      // Claim
      await nftRewarder.connect(admin).claimTimeRewards([tokenId], user1.address);

      // Pending should be ~0 (may be a few wei from block time)
      const [pending] = await nftRewarder.pendingTimeReward(tokenId);
      expect(pending).to.be.lt(ethers.parseEther("0.001"));
    });
  });
});
```

### 8.2 Integration Tests

```javascript
describe("Integration: Time Rewards + Revenue Sharing", function() {

  it("should track both reward types separately", async function() {
    const tokenId = 2340;

    // Register NFT - this auto-starts time rewards for special NFTs
    await nftRewarder.connect(admin).registerNFT(tokenId, 0, user1.address);

    // Fast forward to accumulate time rewards
    await ethers.provider.send("evm_increaseTime", [3600]);
    await ethers.provider.send("evm_mine");

    // Simulate game loss (revenue sharing)
    await rogueBankroll.connect(buxBooster).settleBuxBoosterLosingBet(
      betId,
      user2.address,  // Loser
      ethers.parseEther("100")
    );

    // Get both reward types
    const [timePending] = await nftRewarder.pendingTimeReward(tokenId);
    const revenuePending = await nftRewarder.pendingReward(tokenId);

    expect(timePending).to.be.gt(0);  // ~7650 ROGUE from 1 hour
    expect(revenuePending).to.be.gt(0);  // Share of 0.2 ROGUE from the bet
  });

  it("should not affect revenue sharing when claiming time rewards", async function() {
    const tokenId = 2340;

    // Register and earn both types of rewards
    await nftRewarder.connect(admin).registerNFT(tokenId, 0, user1.address);
    await ethers.provider.send("evm_increaseTime", [3600]);
    await rogueBankroll.connect(buxBooster).settleBuxBoosterLosingBet(...);

    const revenueBeforeClaim = await nftRewarder.pendingReward(tokenId);

    // Claim ONLY time rewards
    await nftRewarder.connect(admin).claimTimeRewards([tokenId], user1.address);

    const revenueAfterClaim = await nftRewarder.pendingReward(tokenId);

    // Revenue sharing should be unchanged
    expect(revenueAfterClaim).to.equal(revenueBeforeClaim);
  });

  it("should withdraw both reward types with withdrawAll", async function() {
    const tokenId = 2340;

    // Register and earn both types
    await nftRewarder.connect(admin).registerNFT(tokenId, 0, user1.address);
    await ethers.provider.send("evm_increaseTime", [3600]);
    await rogueBankroll.connect(buxBooster).settleBuxBoosterLosingBet(...);

    const balanceBefore = await ethers.provider.getBalance(user1.address);

    // Withdraw both in one transaction
    const tx = await nftRewarder.connect(admin).withdrawAll([tokenId], user1.address);
    const receipt = await tx.wait();

    const balanceAfter = await ethers.provider.getBalance(user1.address);

    // Should have received both time rewards (~7650 ROGUE) + revenue share
    expect(balanceAfter - balanceBefore).to.be.gt(ethers.parseEther("7650"));
  });
});
```

---

## Phase 9: Deployment Checklist

### 9.1 Pre-Deployment

- [ ] All unit tests passing
- [ ] Integration tests passing
- [ ] Storage layout verified (no conflicts with V2)
- [ ] Time reward rates calculated and verified
- [ ] 5,614,272,000 ROGUE available for deposit
- [ ] Admin wallet has sufficient ROGUE for gas

### 9.2 Deployment Steps

1. **Deploy NFTRewarder V3 Implementation**
   ```bash
   npx hardhat run scripts/deploy-nftrewarder-v3-impl.js --network rogueMainnet
   ```

2. **Upgrade Proxy to V3**
   ```bash
   npx hardhat run scripts/upgrade-nftrewarder-v3.js --network rogueMainnet
   ```

3. **Verify on Roguescan**
   ```bash
   npx hardhat run scripts/verify-nftrewarder-v3.js --network rogueMainnet
   ```

4. **Deposit Time Reward Pool**
   ```bash
   npx hardhat run scripts/deposit-time-rewards.js --network rogueMainnet
   ```

5. **Deploy Backend Updates**
   ```bash
   cd high-rollers-nfts
   flyctl deploy --app high-rollers-nfts
   ```

6. **Verify Database Migrations**
   ```bash
   flyctl ssh console --app high-rollers-nfts -C "sqlite3 /data/highrollers.db '.tables'"
   ```

### 9.3 Post-Deployment Verification

- [ ] Contract upgrade successful (check Roguescan)
- [ ] Time reward pool deposited (check `timeRewardPoolRemaining`)
- [ ] Backend services running (check logs)
- [ ] API endpoints responding (`/api/revenues/time-rewards/stats`)
- [ ] WebSocket broadcasting events
- [ ] UI displaying correctly

### 9.4 Monitoring

Set up alerts for:
- Time reward pool balance falling below threshold
- Failed `startTimeReward` transactions
- Failed `claimTimeRewards` transactions
- EventListener missing NFTMinted events

---

## Appendix A: Rate Calculation Details

### Per-Hostess Rate Derivation

Given:
- Total ROGUE: 5,614,272,000
- Duration: 180 days = 15,552,000 seconds
- Distribution follows rarity percentages

| Hostess | Rarity | Expected Count | Total ROGUE | Per NFT | Per Second |
|---------|--------|----------------|-------------|---------|------------|
| Penelope (100x) | 0.5% | 1.8 → 2 | 66,089,135 | 33,044,567 | 2.125 |
| Mia (90x) | 1.0% | 3.6 → 4 | 118,960,443 | 29,740,111 | 1.912 |
| Cleo (80x) | 3.5% | 12.6 → 13 | 343,663,501 | 26,435,654 | 1.700 |
| Sophia (70x) | 7.5% | 27.1 → 27 | 624,542,324 | 23,131,197 | 1.487 |
| Luna (60x) | 12.5% | 45.1 → 45 | 892,203,320 | 19,826,740 | 1.275 |
| Aurora (50x) | 25.0% | 90.3 → 90 | 1,487,005,533 | 16,522,284 | 1.062 |
| Scarlett (40x) | 25.0% | 90.3 → 90 | 1,189,604,426 | 13,217,827 | 0.850 |
| Vivienne (30x) | 25.0% | 90.3 → 90 | 892,203,320 | 9,913,370 | 0.637 |

**Formula**: `ROGUE_PER_SECOND = ROGUE_PER_NFT / 15,552,000`

### Handling Rarity Variance

Since actual mint distribution depends on Chainlink VRF randomness:
- More rare NFTs than expected → Pool depletes faster
- Fewer rare NFTs than expected → Pool lasts longer
- Edge case: All 361 mint as Penelope → Would need 11.9B ROGUE (not possible)
- Expected case: Distribution follows probabilities → Pool exactly sufficient

**Safety**: The contract enforces `timeRewardPoolRemaining >= claimAmount` to prevent over-distribution.

---

## Appendix B: Security Considerations

### Access Control

| Function | Caller | Notes |
|----------|--------|-------|
| `depositTimeRewards` | Owner only | Cold wallet multisig |
| `startTimeReward` | Admin only | Server hot wallet |
| `claimTimeRewards` | Admin only | Server hot wallet |
| `pendingTimeReward` | Public | View function |
| `getTimeRewardInfo` | Public | View function |

### Attack Vectors Mitigated

1. **Reentrancy**: Claims use CEI pattern and transfer last
2. **Over-claiming**: Pool balance check before transfer
3. **Double-start**: `AlreadyStarted` error if `startTime != 0`
4. **Invalid NFT**: `InvalidTokenId` error for non-special NFTs
5. **Unauthorized access**: `onlyAdmin` and `onlyOwner` modifiers

### Upgrade Safety

- UUPS pattern with `_authorizeUpgrade` restricted to owner
- Storage layout preserved with new variables appended only
- `reinitializer(3)` prevents re-initialization

---

## Appendix C: Gas Estimates

| Function | Estimated Gas | Notes |
|----------|---------------|-------|
| `depositTimeRewards` | ~50,000 | Single SSTORE |
| `startTimeReward` | ~80,000 | Multiple SSTOREs |
| `claimTimeRewards` (1 NFT) | ~100,000 | Transfer + updates |
| `claimTimeRewards` (10 NFTs) | ~400,000 | Batched |
| `pendingTimeReward` | ~30,000 | View function |
| `getTimeRewardInfo` | ~50,000 | View function |

---

## Appendix D: Wallet Network Switching

The High Rollers NFT frontend automatically switches the user's wallet between **Arbitrum One** (for minting) and **Rogue Chain** (for revenues) depending on which tab is active.

### Network Configuration (`public/js/config.js`)

```javascript
const CONFIG = {
  // Arbitrum One (for NFT minting)
  CHAIN_ID: 42161,
  CHAIN_ID_HEX: '0xa4b1',
  CHAIN_NAME: 'Arbitrum One',
  RPC_URL: 'https://arb1.arbitrum.io/rpc',
  EXPLORER_URL: 'https://arbiscan.io',

  // Rogue Chain (for NFT Revenues)
  ROGUE_CHAIN_ID: 560013,
  ROGUE_CHAIN_ID_HEX: '0x88b8d',  // IMPORTANT: 560013 = 0x88b8d (not 0x88b0d)
  ROGUE_CHAIN_NAME: 'Rogue Chain',
  ROGUE_RPC_URL: 'https://rpc.roguechain.io/rpc',
  ROGUE_EXPLORER_URL: 'https://roguescan.io',
  ROGUE_CURRENCY: { name: 'ROGUE', symbol: 'ROGUE', decimals: 18 },
  NFT_REWARDER_ADDRESS: '0x96aB9560f1407586faE2b69Dc7f38a59BEACC594',
};
```

### WalletService Methods (`public/js/wallet.js`)

#### `switchToArbitrum(provider)`

Switches the user's wallet to Arbitrum One network. Used when the Mint tab is active.

```javascript
async switchToArbitrum(provider) {
  provider = provider || window.ethereum;
  if (!provider) return;

  try {
    await provider.request({
      method: 'wallet_switchEthereumChain',
      params: [{ chainId: CONFIG.CHAIN_ID_HEX }]
    });
  } catch (error) {
    if (error.code === 4902) {
      // Chain not added - add it first
      await provider.request({
        method: 'wallet_addEthereumChain',
        params: [{
          chainId: CONFIG.CHAIN_ID_HEX,
          chainName: 'Arbitrum One',
          nativeCurrency: { name: 'Ether', symbol: 'ETH', decimals: 18 },
          rpcUrls: [CONFIG.RPC_URL],
          blockExplorerUrls: [CONFIG.EXPLORER_URL]
        }]
      });
    } else if (error.code === 4001) {
      // User rejected - that's okay
      console.log('User rejected network switch to Arbitrum');
      return;
    } else if (error.code === -32002) {
      // Request already pending
      console.log('Network switch request already pending');
      return;
    } else {
      throw error;
    }
  }

  // Update provider after switch
  if (this.address) {
    this.provider = new ethers.BrowserProvider(provider);
    this.signer = await this.provider.getSigner();
  }
  this.currentChain = 'arbitrum';
}
```

#### `switchToRogueChain(provider)`

Switches the user's wallet to Rogue Chain network. Used for Gallery, My NFTs, and Revenues tabs.

```javascript
async switchToRogueChain(provider) {
  provider = provider || window.ethereum;
  if (!provider) return;

  try {
    await provider.request({
      method: 'wallet_switchEthereumChain',
      params: [{ chainId: CONFIG.ROGUE_CHAIN_ID_HEX }]
    });
  } catch (error) {
    if (error.code === 4902) {
      // Chain not added - add it first
      await provider.request({
        method: 'wallet_addEthereumChain',
        params: [{
          chainId: CONFIG.ROGUE_CHAIN_ID_HEX,
          chainName: CONFIG.ROGUE_CHAIN_NAME,
          nativeCurrency: CONFIG.ROGUE_CURRENCY,
          rpcUrls: [CONFIG.ROGUE_RPC_URL],
          blockExplorerUrls: [CONFIG.ROGUE_EXPLORER_URL]
        }]
      });
    } else if (error.code === 4001) {
      console.log('User rejected network switch to Rogue Chain');
      return;
    } else if (error.code === -32002) {
      console.log('Network switch request already pending');
      return;
    } else {
      throw error;
    }
  }

  if (this.address) {
    this.provider = new ethers.BrowserProvider(provider);
    this.signer = await this.provider.getSigner();
  }
  this.currentChain = 'rogue';
}
```

#### `switchNetwork(targetChain)`

Generic method to switch between networks:

```javascript
async switchNetwork(targetChain) {
  if (!window.ethereum || !this.address) return;

  if (targetChain === 'arbitrum') {
    await this.switchToArbitrum();
  } else if (targetChain === 'rogue') {
    await this.switchToRogueChain();
  }
}
```

#### `getROGUEBalance()` and `refreshROGUEBalance()`

Fetches ROGUE balance using the Rogue Chain RPC directly (without requiring wallet to be on that network):

```javascript
async getROGUEBalance() {
  if (!this.address) return '0';
  try {
    const rogueProvider = new ethers.JsonRpcProvider(CONFIG.ROGUE_RPC_URL);
    const balance = await rogueProvider.getBalance(this.address);
    this.rogueBalance = ethers.formatEther(balance);
    return this.rogueBalance;
  } catch (error) {
    console.error('Failed to get ROGUE balance:', error);
    return '0';
  }
}

async refreshROGUEBalance() {
  const balance = await this.getROGUEBalance();
  this.onBalanceUpdateCallbacks.forEach(cb => cb());
  return balance;
}
```

### Tab-Based Network Switching (`public/js/app.js`)

The `showTab()` function automatically switches networks based on which tab is activated:

```javascript
async showTab(tabName, skipNavUpdate = false) {
  // ... tab switching logic ...

  // Switch network based on tab
  if (window.walletService && window.walletService.isConnected()) {
    if (tabName === 'mint') {
      // Mint tab needs Arbitrum for NFT contract
      await window.walletService.switchNetwork('arbitrum');
    } else {
      // Gallery, My NFTs, Revenues tabs need Rogue Chain
      await window.walletService.switchNetwork('rogue');
    }
  }
}
```

### Balance Display Based on Chain

The wallet button shows different balances based on the current chain:

| Tab | Network | Balance Displayed | Logo |
|-----|---------|-------------------|------|
| Mint | Arbitrum | ETH balance | Arbitrum logo |
| Gallery | Rogue Chain | ROGUE balance | Rogue logo |
| My NFTs | Rogue Chain | ROGUE balance | Rogue logo |
| Revenues | Rogue Chain | ROGUE balance | Rogue logo |

### Error Codes Reference

| Code | Meaning | Handling |
|------|---------|----------|
| `4902` | Chain not added to wallet | Call `wallet_addEthereumChain` to add it |
| `4001` | User rejected the switch | Log and continue (non-blocking) |
| `-32002` | Request already pending in wallet | Log and continue (non-blocking) |

### Chain ID Validation

**IMPORTANT**: Rogue Chain ID is `560013`, which in hex is `0x88b8d`:

```javascript
// CORRECT
560013 → 0x88b8d

// WRONG (common mistake)
560013 → 0x88b0d  // Missing the 8!
```

Verify with: `(560013).toString(16)` → `"88b8d"`

### Database Sync Warning

When withdrawing time rewards, the **on-chain `lastClaimTime`** is the source of truth, not the local database. If you withdraw from the same wallet on multiple servers (e.g., production and local), the local database's `lastClaimTime` will be stale.

**Symptoms**: Frontend shows higher pending amount than actually received.

**Solution**: Sync time reward data from blockchain:
```bash
curl -X POST http://localhost:3000/api/revenues/time-rewards/sync \
  -H "Content-Type: application/json" \
  -d '{"tokenIds": [2341]}'
```

Or run the full sync script:
```bash
node server/scripts/sync-time-rewards.js
```

---

*Document created: January 6, 2026*
*Last updated: January 7, 2026 - Added Appendix D: Wallet Network Switching*
