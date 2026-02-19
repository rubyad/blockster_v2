# BUX Booster Game - Comprehensive Technical Documentation

> **Purpose**: This document exhaustively describes every aspect of the BUX Booster provably fair gambling game -- smart contracts, Elixir backend, database layer, UI/UX, and integrations. It is intended as the reference blueprint for building new gambling games on the same infrastructure.

---

## Table of Contents

1. [Overview & Game Mechanics](#1-overview--game-mechanics)
2. [Architecture](#2-architecture)
3. [Complete Game Flow (Step-by-Step)](#3-complete-game-flow-step-by-step)
4. [Provably Fair System](#4-provably-fair-system)
5. [Smart Contracts](#5-smart-contracts)
6. [Backend Implementation (Elixir)](#6-backend-implementation-elixir)
7. [Database Layer (Mnesia)](#7-database-layer-mnesia)
8. [BUX Minter Service](#8-bux-minter-service)
9. [UI / LiveView / Frontend](#9-ui--liveview--frontend)
10. [JavaScript Hooks](#10-javascript-hooks)
11. [Account Abstraction & Gasless Transactions](#11-account-abstraction--gasless-transactions)
12. [Admin & Stats](#12-admin--stats)
13. [Key Design Decisions & Patterns](#13-key-design-decisions--patterns)
14. [Contract Addresses & Infrastructure](#14-contract-addresses--infrastructure)
15. [Error Handling & Recovery](#15-error-handling--recovery)

---

## 1. Overview & Game Mechanics

### What Is BUX Booster?

A **provably fair coin flip gambling game** where users bet BUX (ERC-20) or ROGUE (native token) on a series of coin flips. The game runs on Rogue Chain (Chain ID: 560013) with **gasless transactions** via ERC-4337 Account Abstraction.

### Core Mechanics

- **Coin Flips**: 1-5 flips per game, determined by the chosen difficulty level
- **Predictions**: Player predicts each flip as **Heads** (rocket emoji) or **Tails** (poop emoji)
- **Two Modes**:
  - **Win All** (difficulty 1-5): Player must predict ALL flips correctly to win. Higher risk, higher reward.
  - **Win One** (difficulty -1 to -4): Player only needs to predict ONE flip correctly. Lower risk, lower reward.

### Difficulty Levels & Multipliers

| Difficulty | Flips | Mode | Multiplier | Win Probability | Multiplier (basis points) |
|-----------|-------|------|------------|-----------------|---------------------------|
| -4 | 5 | Win One | 1.02x | ~96.9% | 10,200 |
| -3 | 4 | Win One | 1.05x | ~93.8% | 10,500 |
| -2 | 3 | Win One | 1.13x | ~87.5% | 11,300 |
| -1 | 2 | Win One | 1.32x | ~75.0% | 13,200 |
| 1 | 1 | Win All | 1.98x | ~50.0% | 19,800 |
| 2 | 2 | Win All | 3.96x | ~25.0% | 39,600 |
| 3 | 3 | Win All | 7.92x | ~12.5% | 79,200 |
| 4 | 4 | Win All | 15.84x | ~6.25% | 158,400 |
| 5 | 5 | Win All | 31.68x | ~3.13% | 316,800 |

Note: All multipliers include a ~1% house edge (e.g., true 50/50 would pay 2.0x, but the game pays 1.98x).

### Supported Tokens

| Token | Type | Contract Address | Default Bet | Min Bet |
|-------|------|-----------------|-------------|---------|
| BUX | ERC-20 | `0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8` | 10 | 1 (1e18 wei) |
| ROGUE | Native | N/A (address(0)) | 100,000 | 100 (100e18 wei) |

Hub tokens (moonBUX, neoBUX, etc.) have contract addresses configured but are **not shown in the UI** and are effectively deprecated for betting.

### Max Bet Formula

```
maxBet = (houseBalance * 0.001 * 20000) / multiplier_bp
```

This ensures the maximum potential payout is approximately 0.2% of the house balance, preventing any single bet from significantly impacting the house.

---

## 2. Architecture

```
                        +-------------------+
                        |     Browser UI    |
                        | (LiveView + Hooks)|
                        +--------+----------+
                                 |
                    +------------+------------+
                    |                         |
            Phoenix LiveView           JS/Thirdweb SDK
            (Elixir Backend)          (Smart Wallet Txs)
                    |                         |
              +-----+-----+            +-----+-----+
              |            |            |           |
          Mnesia DB    BUX Minter   EntryPoint   Bundler
         (Game State)  (Node.js)    (ERC-4337)   (Fly.io)
              |            |            |           |
              |      +-----+-----+     +-----+-----+
              |      |           |           |
              |  submit-      settle-     Paymaster
              |  commitment   bet        (Gas Sponsor)
              |      |           |           |
              +------+-----------+-----------+
                           |
                    +------+------+
                    | Rogue Chain |
                    |  (560013)   |
                    +------+------+
                           |
              +------------+------------+
              |                         |
        BuxBoosterGame           ROGUEBankroll
        (UUPS Proxy)            (LP Pool + Native)
        0x97b6...17B            0x51DB...2fd
```

### Data Flow Summary

1. **Server** generates server seed and submits commitment hash on-chain (via BUX Minter)
2. **Player** places bet on-chain (via Thirdweb smart wallet through bundler/paymaster)
3. **Server** calculates results deterministically from seeds, settles bet on-chain (via BUX Minter)
4. **Mnesia** stores game state locally for fast reads; blockchain is source of truth for funds

### Key Principle: Optimistic UI

The game calculates results and starts animations **before** the blockchain transaction confirms. If the tx fails, the bet is refunded. This gives instant feedback while maintaining on-chain settlement integrity.

---

## 3. Complete Game Flow (Step-by-Step)

### Phase 1: Page Load & Game Initialization

1. User navigates to `/play`
2. LiveView mounts twice (Phoenix standard: disconnected + connected)
3. On connected mount:
   - Subscribes to PubSub: `bux_balance:{user_id}`, `bux_booster_settlement:{user_id}`, `token_prices`
   - Syncs user balances from blockchain via `BuxMinter.sync_user_balances_async()`
   - Starts 3 async operations:
     - `init_onchain_game`: Generates server seed, submits commitment hash to blockchain
     - `fetch_house_balance`: Gets house balance from BUX Minter service
     - `load_recent_games`: Loads last 30 settled games from Mnesia

4. `init_onchain_game` flow (`BuxBoosterOnchain.get_or_init_game/2`):
   - Calculates next nonce: max nonce from `:placed`/`:settled` games in Mnesia + 1
   - Checks for reusable `:committed` game with correct nonce
   - If none exists, calls `init_game_with_nonce/3`:
     - Generates `server_seed`: `crypto.strong_rand_bytes(32)` -> 64-char hex
     - Calculates `commitment_hash`: `SHA256(server_seed)` as `0x`-prefixed hex
     - Generates `game_id`: `crypto.strong_rand_bytes(16)` -> 32-char hex
     - Calls BUX Minter `POST /submit-commitment` -> submits to BuxBoosterGame contract
     - Writes game to Mnesia with status `:committed`
   - Returns `{game_id, commitment_hash, commitment_tx, nonce}` to LiveView

5. LiveView sets `onchain_ready: true`, commitment hash shown in UI

### Phase 2: User Configures Bet

1. **Select Difficulty**: 9 tabs (1.02x to 31.68x) -- resets predictions, re-inits on-chain game if nonce changes
2. **Enter Bet Amount**: Number input with halve/double/max buttons + USD conversion display
3. **Select Token**: BUX or ROGUE dropdown (re-fetches house balance on change)
4. **Make Predictions**: Click casino chip buttons to toggle nil -> heads -> tails -> heads for each flip position
5. "Place Bet" button enables when all predictions are made

### Phase 3: Bet Placement (Optimistic)

1. User clicks "Place Bet" -> `handle_event("start_game", ...)`
2. **Validations**:
   - All prediction slots filled
   - Bet amount > 0
   - Sufficient user balance
   - ROGUE minimum bet (100) check
   - `onchain_ready == true`
3. **Optimistic execution** (before blockchain confirms):
   - Deducts balance from Mnesia via `EngagementTracker.deduct_user_token_balance()`
   - Calculates results via `BuxBoosterOnchain.calculate_game_result()` (uses stored server seed)
   - Sets `game_state: :flipping`, starts coin animation
   - Pushes `place_bet_background` event to JavaScript hook with bet parameters

4. **JavaScript hook** (`BuxBoosterOnchain`):
   - For BUX: Checks ERC-20 approval (localStorage cache + on-chain fallback), approves if needed (infinite approval), then calls `placeBet(token, amount, difficulty, predictions, commitmentHash)` on BuxBoosterGame contract
   - For ROGUE: Calls `placeBetROGUE(amount, difficulty, predictions, commitmentHash)` with `msg.value`
   - Transaction goes through Thirdweb smart wallet -> Bundler -> EntryPoint -> Paymaster (gasless)
   - On success: pushes `bet_confirmed` event to LiveView with `{game_id, tx_hash, confirmation_time_ms}`

5. **LiveView receives** `bet_confirmed`:
   - Calls `BuxBoosterOnchain.on_bet_placed()` to update Mnesia (status -> `:placed`, adds bet details)
   - Ensures minimum 3 seconds of spin animation for good UX
   - Schedules `:reveal_flip_result` after spin time elapses

### Phase 4: Animation Sequence

For each flip (1 to N):

1. **Spinning**: 3D coin rotates continuously (CSS `flip-continuous` animation, 3s loop)
2. **Reveal trigger**: After bet confirmed + 3s min spin, `reveal_result` event pushed to CoinFlip JS hook
3. **Reveal animation**: CoinFlip hook waits for `animationiteration` (loop at 0deg), switches to `flip-to-heads` or `flip-to-tails` deceleration animation (3s ease-out)
4. **Flip complete**: JS pushes `flip_complete` -> LiveView transitions to `:showing_result`
5. **Result shown**: Static coin displayed for 1 second with "Correct!" or "Wrong!" text
6. **Mode check**:
   - **Win All mode**: If wrong -> show final loss. If right and more flips -> next flip.
   - **Win One mode**: If right -> show final win. If wrong and more flips -> next flip.
7. For multi-flip: `:next_flip` increments counter, repeats from step 1

### Phase 5: Result & Settlement

1. **Final result shown**:
   - **Win**: "YOU WON!" text, payout amount, 100-piece confetti burst animation, shake animation
   - **Loss**: Red "-amount" display
2. **Background settlement**: `spawn(fn -> BuxBoosterOnchain.settle_game(game_id) end)`
   - Reads game from Mnesia, verifies status `:placed`
   - Calls BUX Minter `POST /settle-bet` with `{commitmentHash, serverSeed, results, won}`
   - BUX Minter calls `settleBet()` or `settleBetROGUE()` on contract
   - On success: marks game `:settled` in Mnesia, updates `user_betting_stats`
   - Syncs balances from blockchain, broadcasts via PubSub
3. **Post-game options**: "Play Again" (resets and inits new game), "Verify Fairness" (opens verification modal)

### Phase 6: Background Safety Net

- `BuxBoosterBetSettler` GenServer (global singleton, one per cluster)
- Runs every 60 seconds
- Finds all games with status `:placed` older than 120 seconds
- Re-attempts settlement via `BuxBoosterOnchain.settle_game()`
- Prevents bets from getting permanently stuck due to server restarts or network issues

---

## 4. Provably Fair System

### Overview

The game uses a **commit-reveal** scheme to ensure fairness. The server commits to the outcome BEFORE the player places their bet, making it impossible for the server to cheat.

### Step-by-Step Verification

#### 1. Server Seed Generation
```
server_seed = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
# Result: 64-character hex string (e.g., "a1b2c3d4...64 chars")
```

#### 2. Commitment (Before Bet)
```
commitment_hash = "0x" <> (:crypto.hash(:sha256, server_seed) |> Base.encode16(case: :lower))
# SHA256 hash of the raw server seed string
# Submitted on-chain via submitCommitment() BEFORE player bets
```

#### 3. Client Seed (Deterministic from Bet Parameters)
```
input = "#{user_id}:#{bet_amount}:#{token}:#{difficulty}:#{predictions_joined}"
# predictions_joined = Enum.join(predictions, ",") -- e.g., "heads,tails,heads"
client_seed = :crypto.hash(:sha256, input) |> Base.encode16(case: :lower)
```
All values are player-controlled. No server-controlled values in the client seed.

#### 4. Combined Seed & Results
```
combined_input = "#{server_seed_hex}:#{client_seed_hex}:#{nonce}"
combined_seed = :crypto.hash(:sha256, combined_input) |> Base.encode16(case: :lower)

# For each flip i (0 to num_flips - 1):
#   Take byte i of the combined seed (as integer 0-255)
#   If byte < 128 -> heads
#   If byte >= 128 -> tails
```

#### 5. Win Determination
- **Win All** (difficulty > 0): ALL predictions must match results
- **Win One** (difficulty < 0): ANY prediction matching wins

#### 6. Post-Settlement Verification
After settlement, the server seed is stored on-chain (in the `Commitment` struct's `serverSeed` field) and in Mnesia. Players can verify:
1. `SHA256(server_seed) == commitment_hash` (proves server didn't change the seed)
2. Recalculate combined seed from server_seed + client_seed + nonce
3. Derive flip results from combined seed bytes

### Security Rules
- **NEVER** display the server seed for unsettled games
- The fairness modal only shows data for games with `status == :settled`
- External verification links provided (SHA256 calculators)

### Trust Model (V3+)
As of V3, the smart contract does **NOT** verify `SHA256(serverSeed) == commitmentHash` on-chain. The contract trusts the settler (server). The commitment and server seed are stored on-chain for **transparency** -- players can verify off-chain. This was a deliberate design decision to simplify gas costs and avoid on-chain SHA256 computation.

---

## 5. Smart Contracts

### 5.1 BuxBoosterGame (UUPS Proxy)

**File**: `contracts/bux-booster-game/contracts/BuxBoosterGame.sol`
**Proxy Address**: `0x97b6d6A8f2c6AF6e6fb40f8d36d60DF2fFE4f17B`
**Solidity**: `^0.8.20`
**Current Version**: V7 (reinitializer 7)

#### Inheritance
```
BuxBoosterGame is Initializable, UUPSUpgradeable, OwnableUpgradeable,
                   ReentrancyGuardUpgradeable, PausableUpgradeable
```

#### Upgrade History
| Version | Function | Changes |
|---------|----------|---------|
| V1 | `initialize()` | Basic setup (Ownable, ReentrancyGuard, Pausable, UUPS) |
| V2 | `initializeV2()` | Set MULTIPLIERS, FLIP_COUNTS, GAME_MODES arrays |
| V3 | `initializeV3()` | Server-side result calculation (removed on-chain result generation) |
| V5 | `initializeV5(_rogueBankroll)` | ROGUE (native token) betting via ROGUEBankroll |
| V6 | `initializeV6()` | Referral system (1% of losing BUX bets to referrer) |
| V7 | `initializeV7()` | Separated BUX stats from ROGUE stats (new `buxPlayerStats` + `buxAccounting`) |

#### Structs

```solidity
struct TokenConfig {
    bool enabled;
    uint256 houseBalance;
}

struct Bet {
    address player;
    address token;
    uint256 amount;
    int8 difficulty;
    uint8[] predictions;
    bytes32 commitmentHash;
    uint256 nonce;
    uint256 timestamp;
    BetStatus status;           // Pending, Won, Lost, Expired
}

struct Commitment {
    address player;
    uint256 nonce;
    uint256 timestamp;
    bool used;
    bytes32 serverSeed;         // Revealed after settlement
}

struct BuxPlayerStats {         // V7 - BUX-only per-player
    uint256 totalBets;
    uint256 wins;
    uint256 losses;
    uint256 totalWagered;
    uint256 totalWinnings;
    uint256 totalLosses;
    uint256[9] betsPerDifficulty;
    int256[9] profitLossPerDifficulty;
}

struct BuxAccounting {          // V7 - BUX global
    uint256 totalBets;
    uint256 totalWins;
    uint256 totalLosses;
    uint256 totalVolumeWagered;
    uint256 totalPayouts;
    int256 totalHouseProfit;
    uint256 largestWin;
    uint256 largestBet;
}
```

#### Game Constants
```
MULTIPLIERS[9]:  [10200, 10500, 11300, 13200, 19800, 39600, 79200, 158400, 316800]
FLIP_COUNTS[9]:  [5, 4, 3, 2, 1, 2, 3, 4, 5]
GAME_MODES[9]:   [1, 1, 1, 1, 0, 0, 0, 0, 0]  // 0 = Win All, 1 = Win One

BET_EXPIRY:      1 hour
MIN_BET:         1e18 (1 token in wei)
MAX_BET_BPS:     10 (0.1% of house balance)
```

**Difficulty Index Formula**: `diffIndex = difficulty < 0 ? uint8(int8(4) + difficulty) : uint8(int8(3) + difficulty)`

#### Storage Layout (Slot Order)
```
// Inherited: _initialized, _initializing, _owner, _status, _paused
MULTIPLIERS                                    // slot 3
FLIP_COUNTS                                    // slot 5
GAME_MODES                                     // slot 6
mapping(address => TokenConfig) tokenConfigs   // slot 7
mapping(bytes32 => Bet) bets                   // slot 8
mapping(address => uint256) playerNonces       // slot 9
mapping(address => bytes32[]) playerBetHistory // slot 10
mapping(address => PlayerStats) playerStats    // slot 11 (legacy combined)
mapping(bytes32 => Commitment) commitments     // slot 12
mapping(address => mapping(uint256 => bytes32)) playerCommitments // slot 13
address settler                                // slot 14
uint256 totalBetsPlaced                        // slot 15
uint256 totalBetsSettled                       // slot 16
// V5:
address rogueBankroll                          // slot 17
// V6:
uint256 buxReferralBasisPoints                 // slot 18
mapping(address => address) playerReferrers    // slot 19
mapping(address => uint256) totalReferralRewardsPaid // slot 20
mapping(address => mapping(address => uint256)) referrerTokenEarnings // slot 21
address referralAdmin                          // slot 22
// V7:
mapping(address => BuxPlayerStats) buxPlayerStats // slot 23
BuxAccounting buxAccounting                    // slot 24
```

**CRITICAL UUPS RULE**: State variables are ONLY added at the END. Never change order or remove existing variables.

#### Key Functions

**Settler-Only (settler address OR owner):**
```solidity
submitCommitment(bytes32 commitmentHash, address player, uint256 nonce)
settleBet(bytes32 commitmentHash, bytes32 serverSeed, uint8[] results, bool won)
settleBetROGUE(bytes32 commitmentHash, bytes32 serverSeed, uint8[] results, bool won)
```

**Player Functions:**
```solidity
placeBet(address token, uint256 amount, int8 difficulty, uint8[] predictions, bytes32 commitmentHash)
placeBetROGUE(uint256 amount, int8 difficulty, uint8[] predictions, bytes32 commitmentHash) payable
```

**Admin (onlyOwner):**
```solidity
configureToken(address token, bool enabled)
depositHouseBalance(address token, uint256 amount)
withdrawHouseBalance(address token, uint256 amount)
setSettler(address)
setROGUEBankroll(address)
setPaused(bool)
setBuxReferralBasisPoints(uint256)              // max 100 = 1%
setReferralAdmin(address)
setPlayerReferrer(address player, address referrer)
setPlayerReferrersBatch(address[] players, address[] referrers)
```

**View Functions:**
```solidity
getBet(bytes32) -> Bet
getBuxPlayerStats(address) -> BuxPlayerStats
getBuxAccounting() -> BuxAccounting
getMaxBet(address token, int8 difficulty) -> uint256
getMaxBetROGUE(int8 difficulty) -> uint256
calculatePotentialPayout(uint256 amount, int8 difficulty) -> uint256
getPlayerBetHistory(address, uint256 offset, uint256 limit) -> bytes32[]
getPlayerCurrentCommitment(address) -> bytes32
getCommitmentByNonce(address, uint256) -> bytes32
getCommitment(bytes32) -> Commitment
refundExpiredBet(bytes32 betId)                 // public, anyone can call after 1hr
```

#### Max Bet Calculation (On-Chain)
```solidity
function _calculateMaxBet(uint256 houseBalance, uint8 diffIndex) -> uint256 {
    uint256 baseMaxBet = houseBalance * 10 / 10000;  // 0.1% of house
    return baseMaxBet * 20000 / MULTIPLIERS[diffIndex];
}
```

#### BUX Settlement Flow (`_processSettlement`)
1. Updates `buxPlayerStats` (V7) -- wins/losses/wagered/P&L per difficulty
2. Updates `buxAccounting` global stats
3. **Win**: `payout = (amount * MULTIPLIERS[diffIndex]) / 10000`; deducts profit from `houseBalance`; transfers payout to player via SafeERC20
4. **Loss**: Adds bet amount to `houseBalance`; calls `_sendBuxReferralReward()` (1% of losing bet to referrer, non-blocking)

#### ROGUE Settlement Flow
1. Updates legacy `playerStats` (not V7 BuxPlayerStats)
2. **Win**: Calls `ROGUEBankroll.settleBuxBoosterWinningBet()` -- sends native ROGUE to winner
3. **Loss**: Calls `ROGUEBankroll.settleBuxBoosterLosingBet()` -- keeps ROGUE, sends NFT/referral rewards

#### Events
```solidity
event CommitmentSubmitted(bytes32 indexed commitmentHash, address indexed player, uint256 nonce);
event BetPlaced(bytes32 indexed commitmentHash, address indexed player, address indexed token,
                uint256 amount, int8 difficulty, uint8[] predictions, uint256 nonce);
event BetSettled(bytes32 indexed commitmentHash, address indexed player, bool won,
                uint8[] results, uint256 payout, bytes32 serverSeed);
event BetDetails(bytes32 indexed commitmentHash, address indexed token, uint256 amount,
                int8 difficulty, uint8[] predictions, uint256 nonce, uint256 timestamp);
event BetExpired(bytes32 indexed betId, address indexed player);
event TokenConfigured(address indexed token, bool enabled);
event HouseDeposit(address indexed token, uint256 amount);
event HouseWithdraw(address indexed token, uint256 amount);
event ReferralRewardPaid(bytes32 indexed commitmentHash, address indexed referrer,
                        address indexed player, address token, uint256 amount);
event ReferrerSet(address indexed player, address indexed referrer);
```

---

### 5.2 ROGUEBankroll (Transparent Proxy)

**File**: `contracts/bux-booster-game/contracts/ROGUEBankroll.sol`
**Address**: `0x51DB4eD2b69b598Fade1aCB5289C7426604AB2fd`
**Solidity**: `0.8.20`

#### Core Concept

A **liquidity pool** where providers deposit ROGUE and receive LP tokens ("LP-ROGUE", ERC-20). The BuxBooster game uses this pool for native ROGUE bets. LP token price tracks house profit/loss.

#### Inheritance
```
ROGUEBankroll is ERC20Upgradeable, OwnableUpgradeable
```

#### LP Token Mechanics

- **Deposit**: `depositROGUE()` payable -- mints LP tokens proportional to deposit/pool ratio
- **Withdraw**: `withdrawROGUE(uint256 lpAmount)` -- burns LP tokens, sends proportional ROGUE
- **Price**: `(total_balance - unsettled_bets) * 1e18 / pool_token_supply`
- When house profits: LP price goes UP. When house loses: LP price goes DOWN.

#### HouseBalance Struct
```solidity
struct HouseBalance {
    uint256 total_balance;      // All ROGUE in contract
    uint256 liability;          // Total potential payouts for unsettled bets
    uint256 unsettled_bets;     // Total wagered on unsettled bets
    uint256 net_balance;        // total_balance - liability
    uint256 actual_balance;     // address(this).balance (sanity check)
    uint256 pool_token_supply;  // Total LP-ROGUE supply
    uint256 pool_token_price;   // Price per LP token (1e18 scaled)
}
```

#### BuxBooster Integration (onlyBuxBooster modifier)
```solidity
updateHouseBalanceBuxBoosterBetPlaced(...) payable  // Receives ROGUE, updates liability
settleBuxBoosterWinningBet(...)                     // Sends payout to winner
settleBuxBoosterLosingBet(...)                      // Keeps ROGUE, sends NFT + referral rewards
```

#### Losing Bet Reward Chain
On every losing ROGUE bet:
1. **NFT Reward**: `wagerAmount * nftRewardBasisPoints / 10000` (0.2%) sent to NFTRewarder via `receiveReward(bytes32)` -- non-blocking
2. **Referral Reward**: `wagerAmount * referralBasisPoints / 10000` (0.2%) sent directly to referrer wallet -- non-blocking
3. Both rewards deducted from house balance, failures never revert settlement

#### Key State Variables
```
minimumBetSize:          100e18 (100 ROGUE)
maximumBetSizeDivisor:   1000 (0.1% of house)
nftRewardBasisPoints:    20 (0.2%)
referralBasisPoints:     20 (0.2%)
buxBoosterGame:          Authorized BuxBoosterGame contract address
nftRewarder:             NFTRewarder contract address
```

---

### 5.3 NFTRewarder (UUPS Proxy)

**File**: `contracts/bux-booster-game/contracts/NFTRewarder.sol`
**Address**: `0x96aB9560f1407586faE2b69Dc7f38a59BEACC594`
**Current Version**: V3

Revenue sharing contract for "High Rollers" NFTs (Arbitrum chain, `0x7176d2edd83aD037bd94b7eE717bd9F661F560DD`).

#### NFT Multipliers (8 Types)
| Index | Name | Multiplier |
|-------|------|-----------|
| 0 | Penelope Fatale | 100x |
| 1 | Mia Siren | 90x |
| 2 | Cleo Enchante | 80x |
| 3 | Sophia Spark | 70x |
| 4 | Luna Mirage | 60x |
| 5 | Aurora Seductra | 50x |
| 6 | Scarlett Ember | 40x |
| 7 | Vivienne Allure | 30x |

#### Revenue Distribution (MasterChef-style)
- `receiveReward(bytes32 betId)` called by ROGUEBankroll with 0.2% of losing bets
- Reward distributed proportionally: `rewardsPerMultiplierPoint += (msg.value * 1e18) / totalMultiplierPoints`
- Per-NFT pending = `(multiplier * rewardsPerMultiplierPoint / 1e18) - nftRewardDebt[tokenId]`

#### V3: Time-Based Rewards
- 180-day countdown per NFT on registration
- Fixed ROGUE per second per NFT type (e.g., Penelope: 2.125e18 wei/sec)
- Pre-funded pool via `depositTimeRewards()`
- Separate from revenue sharing rewards

#### Ownership Model
- NFTs live on Arbitrum, ownership synced to Rogue Chain by admin server
- Admin manages: `registerNFT()`, `batchRegisterNFTs()`, `updateOwnership()`, `batchUpdateOwnership()`
- Withdrawals: `withdrawTo()`, `claimTimeRewards()`, `withdrawAll()` (admin-executed after verification)

---

### 5.4 BuxBoosterGameTransparent.sol (Legacy/Unused)

**File**: `contracts/bux-booster-game/contracts/BuxBoosterGameTransparent.sol`

An earlier version using Transparent Proxy with on-chain result generation. Key differences from current:
- Has on-chain `_generateClientSeed`, `_generateResults`, `_checkWin` functions
- Validates nonces strictly on-chain
- No ROGUE betting, referrals, or separated BUX stats
- **Superseded** by the UUPS version (BuxBoosterGame.sol)

---

## 6. Backend Implementation (Elixir)

### 6.1 BuxBoosterOnchain (`lib/blockster_v2/bux_booster_onchain.ex`, ~851 lines)

The **main orchestration module** for the entire game lifecycle.

#### Key Functions

| Function | Line | Purpose |
|----------|------|---------|
| `get_or_init_game/2` | ~480 | Entry point: creates or reuses game for a user |
| `init_game_with_nonce/3` | ~61 | Generates seed, submits commitment, writes to Mnesia |
| `calculate_game_result/5` | ~204 | Pre-calculates flip results from seeds |
| `calculate_result/5` | ~204 | Core result calculation (client seed, combined seed, byte checks) |
| `on_bet_placed/7` | ~155 | Updates Mnesia after blockchain bet confirmation |
| `settle_game/1` | ~241 | Settles bet on-chain via BUX Minter |
| `mark_game_settled/3` | ~280 | Updates Mnesia to `:settled`, updates betting stats |
| `get_game/1` | -- | Mnesia dirty_read by game_id |
| `get_pending_game/1` | ~438 | Mnesia dirty_index_read by user_id for `:committed` games |
| `update_user_betting_stats/5` | -- | Updates `user_betting_stats` Mnesia table |

#### Nonce Management
- Nonces managed entirely in Mnesia (NOT queried from contract)
- Next nonce = max nonce from `:placed`/`:settled` games + 1
- Abandoned `:committed` games don't consume nonces (nonce reusable)

#### Token Address Map
```elixir
@token_addresses %{
  "BUX"      => "0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8",
  "moonBUX"  => "0x...", "neoBUX" => "0x...",  # ... 9 more hub tokens
}
```

#### Result Calculation Detail
```elixir
# Client seed (deterministic from bet params)
input = "#{user_id}:#{bet_amount}:#{token}:#{difficulty}:#{predictions_str}"
client_seed = :crypto.hash(:sha256, input) |> Base.encode16(case: :lower)

# Combined seed
combined = :crypto.hash(:sha256, "#{server_seed}:#{client_seed}:#{nonce}")

# Each flip
for i <- 0..(num_flips - 1) do
  byte = :binary.at(combined, i)
  if byte < 128, do: :heads, else: :tails
end
```

---

### 6.2 BuxBoosterBetSettler (`lib/blockster_v2/bux_booster_bet_settler.ex`, ~119 lines)

**Global singleton GenServer** for background bet recovery.

- Started via `BlocksterV2.GlobalSingleton` in `application.ex`
- Ticks every 60 seconds (`:check_unsettled_bets`)
- Finds games with status `:placed` AND `created_at` > 120 seconds ago
- Calls `BuxBoosterOnchain.settle_game()` for each
- Handles `BetAlreadySettled` error gracefully

---

### 6.3 ProvablyFair (`lib/blockster_v2/provably_fair.ex`, ~128 lines)

Utility functions for provably fair verification:
- `generate_server_seed/0` -- 32 random bytes -> hex
- `generate_commitment/1` -- SHA256 of server seed
- `verify_commitment/2` -- Check hash matches
- `generate_combined_seed/3` -- SHA256 of "server:client:nonce"
- `calculate_results/2` -- Byte-to-flip mapping

---

### 6.4 BuxMinter (`lib/blockster_v2/bux_minter.ex`, ~540 lines)

HTTP client for the BUX Minter Node.js service. Uses `Req` library with retry.

| Function | Endpoint | Purpose |
|----------|----------|---------|
| `submit_commitment/3` | `POST /submit-commitment` | Submit commitment hash on-chain |
| `settle_bet/4` | `POST /settle-bet` | Settle bet with server seed + results |
| `get_balance/2` | `GET /balance/:address` | Get token balance |
| `get_aggregated_balances/1` | `GET /aggregated-balances/:address` | All token balances |
| `get_house_balance/1` | `GET /game-token-config/:token` | House balance + token config |
| `get_rogue_house_balance/0` | `GET /rogue-house-balance` | ROGUE house info |
| `sync_user_balances_async/3` | Multiple | Async balance sync from blockchain |
| `mint_bux/5` | `POST /mint` | Mint BUX tokens |

**Auth**: Bearer token via `BUX_MINTER_SECRET` environment variable
**Timeouts**: POST 60s, GET 30s, with Req transient retries (up to 5, exponential backoff)

---

### 6.5 BuxBoosterStats (`lib/blockster_v2/bux_booster_stats.ex`, ~643 lines)

Hybrid stats module reading from both Mnesia and on-chain contracts.

- `get_global_stats/0` -- Reads `getBuxAccounting()` and `buxBoosterAccounting()` from contracts
- `get_all_player_stats/0` -- Reads all `user_betting_stats` from Mnesia
- `get_player_detail/1` -- Reads per-difficulty stats from contracts, caches in Mnesia
- On-chain reads use direct RPC calls (`:httpc`) to Rogue Chain RPC

---

### 6.6 BuxBoosterStats.Backfill (`lib/blockster_v2/bux_booster_stats/backfill.ex`, ~265 lines)

One-time migration utility to populate `user_betting_stats` from historical `bux_booster_onchain_games`.

- `run/0` -- Backfills all users
- `create_for_user/1` -- Single user backfill

---

### 6.7 BuxBalanceHook (`lib/blockster_v2_web/live/bux_balance_hook.ex`, ~93 lines)

LiveView `on_mount` hook for the site-wide header BUX balance display.

- Subscribes to `bux_balance:{user_id}` PubSub
- Handles `{:bux_balance_updated, balance}` messages
- Broadcasts via `broadcast_balance_update/2` and `broadcast_token_balances_update/2`

---

## 7. Database Layer (Mnesia)

### Overview

All game data is stored in Mnesia. There are **NO PostgreSQL tables** for game data. Users are in PostgreSQL (Ecto), games/stats are in Mnesia exclusively.

### Table Definitions

All tables defined in `lib/blockster_v2/mnesia_initializer.ex`.

#### 7.1 `:bux_booster_onchain_games` (Primary Active Table)

| Position | Field | Type | Description |
|----------|-------|------|-------------|
| 0 | (table name) | atom | `:bux_booster_onchain_games` |
| 1 | `game_id` | string | 32-char hex, PRIMARY KEY |
| 2 | `user_id` | integer | PostgreSQL user ID |
| 3 | `wallet_address` | string | Player's smart wallet address |
| 4 | `server_seed` | string | 64-char hex (revealed after settlement) |
| 5 | `commitment_hash` | string | 0x-prefixed SHA256 of server_seed |
| 6 | `nonce` | integer | Player's game counter |
| 7 | `status` | atom | `:pending`, `:committed`, `:placed`, `:settled`, `:expired` |
| 8 | `bet_id` | string | On-chain bet ID (0x-prefixed bytes32) |
| 9 | `token` | string | Token name ("BUX", "ROGUE") |
| 10 | `token_address` | string | Token contract address |
| 11 | `bet_amount` | integer | Amount wagered |
| 12 | `difficulty` | integer | -4 to 5 (skipping 0) |
| 13 | `predictions` | list | `[:heads, :tails, ...]` |
| 14 | `results` | list | `[:heads, :tails, ...]` (calculated after bet) |
| 15 | `won` | boolean | Win/loss result |
| 16 | `payout` | float/integer | Amount won (0 if lost) |
| 17 | `commitment_tx` | string | TX hash for submitCommitment |
| 18 | `bet_tx` | string | TX hash for placeBet |
| 19 | `settlement_tx` | string | TX hash for settleBet |
| 20 | `created_at` | integer | Unix timestamp (updated to bet placement time) |
| 21 | `settled_at` | integer | Unix timestamp (nil until settled) |

- **Type**: `:ordered_set`
- **Indexes**: `[:user_id, :wallet_address, :status, :created_at]`

#### 7.2 `:user_betting_stats` (Admin Dashboard Stats)

| Position | Field | Type | Description |
|----------|-------|------|-------------|
| 0 | (table name) | atom | `:user_betting_stats` |
| 1 | `user_id` | integer | PRIMARY KEY |
| 2 | `wallet_address` | string | Stored to avoid PG joins |
| 3 | `bux_total_bets` | integer | Total BUX bets count |
| 4 | `bux_wins` | integer | BUX wins count |
| 5 | `bux_losses` | integer | BUX losses count |
| 6 | `bux_total_wagered` | integer | BUX total wagered (wei) |
| 7 | `bux_total_winnings` | integer | BUX total winnings (wei) |
| 8 | `bux_total_losses` | integer | BUX total losses (wei) |
| 9 | `bux_net_pnl` | integer | BUX net profit/loss (wei) |
| 10 | `rogue_total_bets` | integer | ROGUE bets count |
| 11 | `rogue_wins` | integer | ROGUE wins count |
| 12 | `rogue_losses` | integer | ROGUE losses count |
| 13 | `rogue_total_wagered` | integer | ROGUE total wagered (wei) |
| 14 | `rogue_total_winnings` | integer | ROGUE total winnings (wei) |
| 15 | `rogue_total_losses` | integer | ROGUE total losses (wei) |
| 16 | `rogue_net_pnl` | integer | ROGUE net P/L (wei) |
| 17 | `first_bet_at` | integer | Unix ms timestamp (nil until first bet) |
| 18 | `last_bet_at` | integer | Unix ms timestamp |
| 19 | `updated_at` | integer | Unix ms timestamp |
| 20 | `onchain_stats_cache` | map/nil | Per-difficulty data (cached when admin views) |

- **Type**: `:set`
- **Indexes**: `[:bux_total_wagered, :rogue_total_wagered]`
- **Created on user signup** (`Accounts.create_user_betting_stats/2`, all zeros)
- **Updated after every settlement** (`BuxBoosterOnchain.update_user_betting_stats/5`)

#### 7.3 `:bux_booster_games` (Legacy Local History)

| Position | Field | Type | Description |
|----------|-------|------|-------------|
| 1 | `game_id` | string | "userId_timestamp" format, PRIMARY KEY |
| 2 | `user_id` | integer | |
| 3 | `token_type` | string | |
| 4 | `bet_amount` | number | |
| 5 | `difficulty` | integer | |
| 6 | `multiplier` | float | |
| 7 | `predictions` | list | |
| 8 | `results` | list | |
| 9 | `won` | boolean | |
| 10 | `payout` | number | |
| 11 | `created_at` | integer | |
| 12 | `server_seed` | string | |
| 13 | `server_seed_hash` | string | |
| 14 | `nonce` | integer | |

- **Type**: `:ordered_set`
- **Indexes**: `[:user_id, :token_type, :won, :created_at]`
- **Still used**: For `get_user_nonce` and `load_game_for_fairness` (legacy games only)

#### 7.4 `:bux_booster_user_stats` (Legacy Per-Token Stats)

| Position | Field | Type | Description |
|----------|-------|------|-------------|
| 1 | `key` | tuple | `{user_id, token_type}`, PRIMARY KEY |
| 2-14 | stats fields | various | total_games, wins, losses, wagered, won, lost, biggest_win, biggest_loss, current_streak, best_streak, worst_streak, updated_at |

- **Type**: `:set`
- **Indexes**: `[:user_id, :total_games, :total_won]`
- **Still used**: `load_user_stats/2` in LiveView for the game page stats panel

### Game State Transitions in Mnesia

```
[init_game_with_nonce] --> :committed  (server seed generated, commitment on-chain)
[on_bet_placed]        --> :placed     (bet details added, results pre-calculated)
[settle_game]          --> :settled    (settlement TX recorded, stats updated)
```

Abandoned `:committed` games persist indefinitely (no cleanup). Nonces can be reused for abandoned games.

---

## 8. BUX Minter Service

### Overview

An external **Node.js + Express + ethers.js** service deployed at `https://bux-minter.fly.dev`. It holds the private key for the settler wallet and submits server-side transactions to Rogue Chain.

### Endpoints Used by BUX Booster

| Method | Endpoint | Body | Returns | Purpose |
|--------|----------|------|---------|---------|
| POST | `/submit-commitment` | `{commitmentHash, player, nonce}` | `{success, txHash}` | Submit commitment hash to contract |
| POST | `/settle-bet` | `{commitmentHash, serverSeed, results: [0\|1], won}` | `{success, txHash, payout}` | Settle bet on-chain |
| GET | `/balance/:address?token=TOKEN` | -- | `{balance}` | Get token balance |
| GET | `/aggregated-balances/:address` | -- | `{balances}` | All token balances |
| GET | `/game-token-config/:token` | -- | `{enabled, houseBalance}` | House balance + config |
| GET | `/rogue-house-balance` | -- | `{houseInfo}` | ROGUE house balance |

### Authentication
Bearer token via `BUX_MINTER_SECRET` environment variable.

### Why a Separate Service?
- Holds the settler private key securely (separate from the main app)
- Can be restarted/updated independently
- Handles ethers.js transaction management (nonce tracking, gas estimation)
- Used by both BUX Booster and other platform features (minting rewards, etc.)

---

## 9. UI / LiveView / Frontend

### 9.1 Main LiveView (`lib/blockster_v2_web/live/bux_booster_live.ex`, ~2545 lines)

The entire game UI is a **single monolithic LiveView module** with inline HEEx template (~926 lines of render). No extracted components.

#### Route
```elixir
live "/play", BuxBoosterLive, :index  # router.ex line 114
```

#### Socket Assigns (Key State)

| Assign | Type | Description |
|--------|------|-------------|
| `selected_token` | string | "BUX" or "ROGUE" |
| `selected_difficulty` | integer | -4 to 5 |
| `bet_amount` | integer | Current bet amount |
| `game_state` | atom | `:idle`, `:awaiting_tx`, `:flipping`, `:showing_result`, `:result` |
| `predictions` | list | `[nil \| :heads \| :tails, ...]` |
| `results` | list | `[:heads \| :tails, ...]` (post-calculation) |
| `won` | boolean/nil | Win/loss result |
| `payout` | number | Payout amount |
| `onchain_ready` | boolean | Commitment submitted successfully |
| `onchain_initializing` | boolean | Init in progress |
| `onchain_game_id` | string | Current game ID |
| `commitment_hash` | string | Current commitment hash |
| `recent_games` | list | Last N settled games |
| `house_balance` | number | Current house balance |
| `max_bet` | number | Current max bet for difficulty |
| `confetti_pieces` | list | Generated confetti data (100 pieces on win) |
| `show_fairness_modal` | boolean | Verification modal open |

#### Event Handlers

| Event | Trigger | Description |
|-------|---------|-------------|
| `select_difficulty` | Tab click | Changes difficulty, resets predictions, re-fetches house balance |
| `toggle_prediction` | Chip click | Cycles nil -> heads -> tails -> heads |
| `update_bet_amount` | Input (debounce 100ms) | Updates bet amount |
| `halve_bet` / `double_bet` / `set_max_bet` | Buttons | Bet amount shortcuts |
| `select_token` | Dropdown | Switches BUX/ROGUE, re-fetches house balance |
| `start_game` | "Place Bet" | **Main action** -- validates, optimistic deduct, calculate, animate, push to JS |
| `bet_confirmed` | JS pushEvent | Blockchain tx confirmed, schedule reveal |
| `bet_failed` | JS pushEvent | Tx failed, refund balance, reset |
| `flip_complete` | JS pushEvent | Animation done, transition state |
| `reset_game` | "Play Again" | Re-init everything |
| `show_fairness_modal` | "Verify" link | Open verification modal (settled games only) |
| `load-more-games` | InfiniteScroll | Load next 30 games |

#### Async Handlers

| Name | Success | Error |
|------|---------|-------|
| `:init_onchain_game` | Sets game_id, commitment, onchain_ready=true | Retries 3x with exponential backoff (1s, 2s, 4s) |
| `:fetch_house_balance` | Sets house_balance, max_bet | Logs warning, keeps defaults |
| `:load_recent_games` | Sets recent_games list | Logs warning |

### 9.2 UI Layout

```
+--------------------------------------------------+
| Difficulty Tabs (horizontally scrollable)          |
| [-4] [-3] [-2] [-1] [1] [2] [3] [4] [5]         |
+--------------------------------------------------+
|                                                    |
| Game Card (fixed height 480/510px)                 |
|                                                    |
| [IDLE STATE]                                       |
|   Bet Input: [___10___] [/2] [x2]   Token: [BUX] |
|   Balance: 1,234 BUX  House: 50,000 BUX          |
|   Potential Profit: +9.80 BUX (1.98x)            |
|                                                    |
|   Predictions:  [?]  (casino chips, tap to flip)  |
|   Commitment: 0x1234...abcd (link to explorer)    |
|                                                    |
|   [====== PLACE BET ======]                       |
|                                                    |
| [FLIPPING STATE]                                   |
|   Predictions: [H] [T]                            |
|   Results:     [spinning coin...]                 |
|                                                    |
| [RESULT STATE]                                     |
|   YOU WON! +19.80 BUX  (with confetti)            |
|   [Play Again] [Verify Fairness]                  |
|                                                    |
+--------------------------------------------------+
|                                                    |
| Game History Table (infinite scroll)               |
| ID | Bet | Pred | Result | Odds | W/L | P/L      |
+--------------------------------------------------+
```

### 9.3 CSS & Animations

**Casino Chip Styles** (`app.css`):
- `.casino-chip-heads`: Conic gradient (amber + white alternating 30deg), 3px amber border
- `.casino-chip-tails`: Conic gradient (gray + white alternating), 3px gray border

**Coin Flip Animations** (inline `<style>` in LiveView):
- `flip-continuous`: 7 rotations (2520deg), 3s linear infinite loop
- `flip-to-heads`: 5.5 rotations (1980deg) with deceleration keyframes, 3s
- `flip-to-tails`: 6 rotations (2160deg) with deceleration, 3s

**Win Celebration**:
- `confetti-burst`: 100 emoji pieces, random positions, burst up then fall, variable timing
- `scale-in`: 0.5 -> 1.1 -> 1.0 scale for "YOU WON!" text
- `shake`: Alternating translateX for emphasis
- `fade-in`: Delayed appearance for "Play Again" button

**3D Coin**:
- `perspective-1000` on container
- `preserve-3d` transform-style on coin
- `backface-visibility: hidden` on each face
- Heads face: `rotateY(0deg)`, Tails face: `rotateY(180deg)`

### 9.4 Mobile Responsiveness

- Container: `px-3 sm:px-4 pt-6 sm:pt-24` (less top padding on mobile)
- Game card: `h-[480px] sm:h-[510px]`
- Difficulty tabs: Horizontally scrollable with `scrollbar-hide`, `ScrollToCenter` hook
- Max button: `hidden sm:flex` on desktop, separate row below input on mobile
- Prediction chips: Dynamic sizing via `get_prediction_size_classes(num_flips)` -- 5 size tiers
- Coin animation: Dynamic sizing via `get_coin_size_classes(num_flips)`
- History table: `min-w-[600px]` with horizontal scroll, `text-[10px] sm:text-xs`
- Fairness modal: Full-screen bottom sheet on mobile, centered card on desktop

---

## 10. JavaScript Hooks

### 10.1 BuxBoosterOnchain (`assets/js/bux_booster_onchain.js`, 465 lines)

The critical hook handling all blockchain interactions from the browser.

#### Lifecycle
- **mounted()**: Reads `data-game-id` and `data-commitment-hash` from element, listens for `place_bet_background` and `bet_settled` events
- **updated()**: Re-reads data attributes when LiveView re-renders

#### Bet Flow
```
1. place_bet_background event received from LiveView
2. Check window.smartAccount exists (Thirdweb wallet)
3. Convert amounts to wei (BigInt)
4. If BUX (ERC-20):
   a. Check approval: localStorage cache -> on-chain allowance
   b. If needed: infinite approve (max uint256), cache in localStorage
   c. Call placeBet(token, amount, difficulty, predictions, commitmentHash)
5. If ROGUE (native):
   a. Call placeBetROGUE(amount, difficulty, predictions, commitmentHash) with msg.value
6. Wait for transaction receipt
7. Poll for BetPlaced event to extract betId
8. Push "bet_confirmed" event to LiveView: {game_id, tx_hash, confirmation_time_ms}
```

#### Error Handling
18 known contract error signatures mapped to human-readable messages:
```javascript
const ERROR_MESSAGES = {
  "0x05d09e5f": "Bet already settled",
  "0x2d0a3f8e": "Invalid difficulty",
  "0x8baa579f": "Invalid predictions",
  // ... 15 more
};
```

#### Wallet Integration
- Uses `window.smartAccount` (set by ThirdwebLogin hook during authentication)
- Uses `window.thirdwebClient` for contract interactions
- Uses `window.rogueChain` for chain configuration
- All transactions are UserOperations through ERC-4337 bundler (gasless)

### 10.2 CoinFlip (`assets/js/coin_flip.js`, 131 lines)

Controls the coin flip animation sequence.

#### Flow
```
1. mounted(): Find .coin element, read data-result and data-flip-index
   - Flip 1: Start continuous spin, wait for "reveal_result" event
   - Flip 2+: Go straight to reveal (result already displayed by LiveView)

2. reveal_result event:
   - Wait for animationiteration (CSS loop reaches 0deg = safe rotation point)
   - Remove continuous animation, add result-specific animation:
     - data-result="heads" -> class "animate-flip-to-heads"
     - data-result="tails" -> class "animate-flip-to-tails"
   - After 3s animation: push "flip_complete" event to LiveView

3. updated(): When element ID changes (new flip), reset state
```

### 10.3 Supporting Hooks

| Hook | Purpose |
|------|---------|
| `ScrollToCenter` | Auto-scrolls difficulty tab container to center selected tab |
| `CopyToClipboard` | Copies commitment hash to clipboard with visual feedback |
| `InfiniteScroll` | Intersection observer-based pagination for history table (200px rootMargin) |

### Hook Registration (`assets/js/app.js`, line ~587)
All hooks registered in a single `hooks` object passed to LiveSocket.

---

## 11. Account Abstraction & Gasless Transactions

### How It Works

Players use **ERC-4337 smart wallets** created by Thirdweb on registration. All game transactions are gasless -- the Paymaster sponsors gas fees.

### Architecture

```
Player (Browser)
  -> Thirdweb SDK creates UserOperation
  -> Signs with EOA wallet (wallet_address)
  -> Sends to Bundler (https://rogue-bundler-mainnet.fly.dev)
  -> Bundler validates and submits to EntryPoint
  -> EntryPoint calls Paymaster for gas sponsorship
  -> Paymaster verifies and pays gas
  -> EntryPoint executes via Smart Wallet
  -> Smart Wallet calls BuxBoosterGame.placeBet()
```

### Key Addresses

| Component | Address |
|-----------|---------|
| EntryPoint v0.6.0 | `0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789` |
| ManagedAccountFactory | `0xfbbe1193496752e99BA6Ad74cdd641C33b48E0C3` |
| Paymaster | `0x804cA06a85083eF01C9aE94bAE771446c25269a6` |
| Bundler | `https://rogue-bundler-mainnet.fly.dev` |

### User Model

| Field | Description |
|-------|-------------|
| `wallet_address` | EOA wallet (used for login/signing) |
| `smart_wallet_address` | ERC-4337 smart wallet (receives tokens, places bets) |

### Who Pays Gas?

- **Player transactions** (placeBet, approve): Gasless via Paymaster
- **Server transactions** (submitCommitment, settleBet): BUX Minter service pays gas from settler wallet

---

## 12. Admin & Stats

### Admin Routes

| Route | Module | Purpose |
|-------|--------|---------|
| `/admin/stats` | `StatsLive.Index` | Global game stats |
| `/admin/stats/players` | `StatsLive.Players` | Player leaderboard |
| `/admin/stats/players/:address` | `StatsLive.PlayerDetail` | Per-player detail |

### Global Stats (`/admin/stats`)
Reads directly from on-chain contracts:
- `BuxBoosterGame.getBuxAccounting()` -- BUX total bets, volume, wins, losses, house profit
- `ROGUEBankroll.buxBoosterAccounting()` -- ROGUE total bets, volume, wins, losses
- `ROGUEBankroll.getHouseInfo()` -- LP pool stats, house balance

### Player List (`/admin/stats/players`)
Reads ALL `user_betting_stats` from Mnesia:
- Sortable by: total wagered, net P/L, total bets, wins, losses
- Separate BUX and ROGUE stats columns
- Paginated in memory

### Player Detail (`/admin/stats/players/:address`)
Fetches per-difficulty breakdown from contracts:
- `BuxBoosterGame.getBuxPlayerStats(address)` -- BUX per-difficulty bets and P/L
- `ROGUEBankroll.getBuxBoosterPlayerStats(address)` -- ROGUE per-difficulty data
- Caches in `onchain_stats_cache` field of `user_betting_stats` Mnesia table

---

## 13. Key Design Decisions & Patterns

### 13.1 Optimistic UI
Balance is deducted and results are calculated BEFORE blockchain confirmation. If the blockchain tx fails, the balance is refunded. This gives instant feedback (~0ms) instead of waiting for block confirmation (~2-5s). The animation runs during the blockchain wait, so the user never perceives latency.

### 13.2 Server as Source of Truth (V3+)
The smart contract does NOT verify `SHA256(serverSeed) == commitmentHash` on-chain. The server calculates results and submits them. This was deliberate:
- Saves gas (no on-chain SHA256)
- Simplifies contract logic
- Server seed is stored on-chain for transparency/auditability
- Players verify off-chain

### 13.3 Commitment Hash as Bet ID
The commitment hash doubles as the bet identifier throughout the system. This is gas-efficient and simplifies the data model -- no need for a separate bet ID generation.

### 13.4 Dual Settlement Paths
BUX (ERC-20) and ROGUE (native) have completely separate settlement flows:
- BUX: BuxBoosterGame handles directly (house balance in contract)
- ROGUE: BuxBoosterGame forwards to ROGUEBankroll (LP pool model with depositor rewards)

### 13.5 Background Settlement Safety Net
The `BuxBoosterBetSettler` GenServer ensures no bet stays in `:placed` state permanently. It runs every 60s and retries settlement for bets older than 120s. This handles:
- Server restarts during settlement
- Network timeouts
- BUX Minter service outages

### 13.6 Non-blocking Rewards
Both NFT rewards (0.2% of losing ROGUE bets) and referral rewards (1% BUX / 0.2% ROGUE of losing bets) use try/catch patterns in Solidity. Failed rewards never revert bet settlement.

### 13.7 UUPS Proxy Upgrade Pattern
State variables are ONLY added at the END of storage. Never change order or remove. Each upgrade uses `reinitializer(N)`. Stack-too-deep errors are solved with helper functions (NOT `viaIR: true`).

### 13.8 Mnesia for Game State, PostgreSQL for Users
Game data lives in Mnesia for fast, distributed access without PostgreSQL load. User accounts are in PostgreSQL (Ecto). The `user_betting_stats` table stores `wallet_address` to avoid cross-database joins.

### 13.9 LP Pool for ROGUE
ROGUE uses a liquidity pool model (ROGUEBankroll) where external depositors provide house funds and earn/lose based on game outcomes. BUX uses a simpler direct house balance in the contract.

### 13.10 Global Singleton GenServers
Critical processes like `BuxBoosterBetSettler` use `BlocksterV2.GlobalSingleton` to ensure exactly one instance runs across the cluster. This prevents duplicate settlements in multi-node deployments.

### 13.11 Fixed-Height Game Card
The game card uses `h-[480px]/h-[510px]` with `relative/absolute` positioning to prevent layout shifts during state transitions. This ensures the page doesn't jump when switching between idle/flipping/result states.

### 13.12 Infinite Approval Strategy
The JS hook uses infinite ERC-20 approval (max uint256) cached in localStorage. This means players only approve once per token, reducing future transaction count to just the bet placement.

---

## 14. Contract Addresses & Infrastructure

### Smart Contracts (Rogue Chain Mainnet, Chain ID: 560013)

| Contract | Address | Type |
|----------|---------|------|
| BuxBoosterGame | `0x97b6d6A8f2c6AF6e6fb40f8d36d60DF2fFE4f17B` | UUPS Proxy |
| ROGUEBankroll | `0x51DB4eD2b69b598Fade1aCB5289C7426604AB2fd` | Transparent Proxy |
| NFTRewarder | `0x96aB9560f1407586faE2b69Dc7f38a59BEACC594` | UUPS Proxy |
| BUX Token | `0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8` | ERC-20 |
| EntryPoint v0.6.0 | `0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789` | Standard |
| ManagedAccountFactory | `0xfbbe1193496752e99BA6Ad74cdd641C33b48E0C3` | Thirdweb |
| Paymaster | `0x804cA06a85083eF01C9aE94bAE771446c25269a6` | Thirdweb |
| Referral Admin | `0xbD6feD8fEeec6f405657d0cA4A004f89F81B04ad` | EOA |
| High Rollers NFT (Arbitrum) | `0x7176d2edd83aD037bd94b7eE717bd9F661F560DD` | ERC-721 |

### Infrastructure

| Service | URL |
|---------|-----|
| Main App | `https://blockster-v2.fly.dev` |
| BUX Minter | `https://bux-minter.fly.dev` |
| Bundler | `https://rogue-bundler-mainnet.fly.dev` |
| Rogue Chain RPC | `https://rpc.roguechain.io/rpc` |
| Block Explorer | `https://roguescan.io` |

### Contract ABIs

| Location | Used By |
|----------|---------|
| `assets/js/BuxBoosterGame.json` | Frontend JS hooks |
| `bux-minter/BuxBoosterGame.json` | BUX Minter Node.js service |

### Deployment

**Contracts**: Hardhat with `@openzeppelin/hardhat-upgrades`
- Config: `contracts/bux-booster-game/hardhat.config.js`
- Optimizer: 200 runs
- Network: rogueMainnet (gas: 1000 gwei)
- Manifest: `.openzeppelin/unknown-560013.json`

**Application**: Fly.io (`flyctl deploy --app blockster-v2`)

---

## 15. Error Handling & Recovery

### On-Chain Game Initialization
- Retries up to 3 times with exponential backoff (1s, 2s, 4s)
- After max retries: shows error message to user
- File: `bux_booster_live.ex:1577-1635`

### Bet Placement Failure
- JS hook catches tx errors, maps 18 known error signatures to messages
- Pushes `bet_failed` event to LiveView
- LiveView refunds balance via `EngagementTracker.credit_user_token_balance()`
- Resets game state to `:idle`
- File: `bux_booster_live.ex:1481-1518`

### Settlement Failure
- `BetAlreadySettled` error (0x05d09e5f): Gracefully marks as settled without tx hash
- Other failures: Shows "Settlement pending - please contact support"
- Background settler retries every 60s for stuck bets
- File: `bux_booster_onchain.ex:264-269`

### BUX Minter Communication
- POST requests: 60s timeout with Req retry (transient errors, up to 5 retries, exponential backoff)
- GET requests: 30s timeout with same retry config
- Bearer token auth via `BUX_MINTER_SECRET` env var

### Bet Expiry
- On-chain: `BET_EXPIRY = 1 hour` -- anyone can call `refundExpiredBet(betId)` after expiry
- This is a safety valve for bets that are never settled

### PubSub Resilience
- Balance updates, settlement notifications, and price updates all flow through PubSub
- Missing a PubSub message is non-critical -- next action will sync state
- Balances are re-synced from blockchain on every game reset ("Play Again")

---

## Appendix: File Reference

| File | Lines | Purpose |
|------|-------|---------|
| `lib/blockster_v2/bux_booster_onchain.ex` | ~851 | Game orchestration, CRUD, settlement |
| `lib/blockster_v2/bux_booster_bet_settler.ex` | ~119 | Background settlement worker |
| `lib/blockster_v2/bux_booster_stats.ex` | ~643 | Admin stats (Mnesia + on-chain hybrid) |
| `lib/blockster_v2/bux_booster_stats/backfill.ex` | ~265 | Historical stats migration |
| `lib/blockster_v2/provably_fair.ex` | ~128 | Seed generation & verification utilities |
| `lib/blockster_v2/bux_minter.ex` | ~540 | BUX Minter HTTP client |
| `lib/blockster_v2/mnesia_initializer.ex` | ~1977 | All Mnesia table definitions |
| `lib/blockster_v2/accounts.ex` | -- | User signup creates betting stats (line 612-628) |
| `lib/blockster_v2_web/live/bux_booster_live.ex` | ~2545 | Main game LiveView (mount, events, render) |
| `lib/blockster_v2_web/live/bux_balance_hook.ex` | ~93 | Header balance PubSub hook |
| `lib/blockster_v2_web/live/admin/stats_live/index.ex` | -- | Global stats admin page |
| `lib/blockster_v2_web/live/admin/stats_live/players.ex` | -- | Player list admin page |
| `lib/blockster_v2_web/live/admin/stats_live/player_detail.ex` | -- | Player detail admin page |
| `assets/js/bux_booster_onchain.js` | ~465 | Frontend blockchain interactions |
| `assets/js/coin_flip.js` | ~131 | Coin flip animation controller |
| `assets/js/BuxBoosterGame.json` | -- | Contract ABI for frontend |
| `assets/css/app.css` | 865-1000 | Casino chip styles, animations |
| `contracts/bux-booster-game/contracts/BuxBoosterGame.sol` | -- | Main game contract (UUPS) |
| `contracts/bux-booster-game/contracts/ROGUEBankroll.sol` | -- | LP pool for ROGUE bets |
| `contracts/bux-booster-game/contracts/NFTRewarder.sol` | -- | NFT revenue sharing |
| `contracts/bux-booster-game/hardhat.config.js` | -- | Hardhat deployment config |
