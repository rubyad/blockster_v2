# High Rollers NFT Minting Application

A standalone Node.js application for the Rogue High Rollers NFT collection on Arbitrum One. Users connect their wallet, mint NFTs for 0.32 ETH, and see real-time updates of their minted NFT type (determined by Chainlink VRF).

**Key Value Proposition**: High Rollers NFTs earn a share of ROGUE betting losses on BUX Booster - passive income proportional to NFT rarity. 🟢 **Revenue sharing is LIVE!**

## Smart Contract Details

| Property | Value |
|----------|-------|
| Contract Address | `0x7176d2edd83aD037bd94b7eE717bd9F661F560DD` |
| Network | Arbitrum One (Chain ID: 42161) |
| Current Price | 0.32 ETH |
| Contract Max Supply | 10,000 NFTs (hardcoded) |
| App Max Supply | 2,700 NFTs (we stop minting after this) |
| VRF Callback Gas Limit | 2,500,000 |
| RPC URL | QuickNode (Arbitrum Mainnet) |

## NFT Types (8 Hostesses)

| Index | Name | Rarity | Multiplier | Description |
|-------|------|--------|------------|-------------|
| 0 | Penelope Fatale | 0.5% | 100x | The rarest of them all |
| 1 | Mia Siren | 1% | 90x | Her song lures the luckiest players |
| 2 | Cleo Enchante | 3.5% | 80x | Egyptian royalty meets casino glamour |
| 3 | Sophia Spark | 7.5% | 70x | Electrifying presence at every table |
| 4 | Luna Mirage | 12.5% | 60x | Mysterious as the moonlit casino floor |
| 5 | Aurora Seductra | 25% | 50x | Lights up every room she enters |
| 6 | Scarlett Ember | 25% | 40x | Red hot luck follows her everywhere |
| 7 | Vivienne Allure | 25% | 30x | Classic elegance with a winning touch |

**How Rarity Works**: Chainlink VRF generates a random number to determine NFT type at mint time.

**Multiplier**: Revenue share weight - higher multiplier = larger share of the revenue pool.

## Two-Tier Affiliate System

| Tier | Commission | Per Mint |
|------|------------|----------|
| Tier 1 | 20% | 0.064 ETH |
| Tier 2 | 5% | 0.016 ETH |

### Affiliate Link Format
```
https://highrollers.fly.dev/?ref=0xAFFILIATE_WALLET_ADDRESS
```

### How Affiliate Linking Works

1. User visits site with referral link (`?ref=0x...`)
2. `AffiliateService` stores the affiliate address in localStorage
3. User connects wallet
4. **Server calls `linkAffiliate(buyer, affiliate)` on-chain** using the `affiliateLinker` wallet
5. First referrer always wins - subsequent referral links don't override
6. On mint, the affiliate automatically receives commission

### Role-Based Access Control

The contract requires a special `affiliateLinker` role to call `linkAffiliate`:

| Role | Address |
|------|---------|
| affiliateLinker | `0x01436e73C4B4df2FEDA37f967C8eca1E510a7E73` |
| Default Affiliate | `0xb91b270212F0F7504ECBa6Ff1d9c1f58DfcEEa14` |

Regular users cannot call `linkAffiliate` directly - the server handles this using the affiliateLinker's private key.

## Project Structure

```
high-rollers-nfts/
├── server/
│   ├── index.js              # Express server entry point
│   ├── config.js             # Network, contract config, hostess data
│   ├── routes/
│   │   ├── api.js            # REST API endpoints
│   │   └── revenues.js       # Revenue sharing API endpoints
│   └── services/
│       ├── database.js       # SQLite operations
│       ├── contractService.js # Contract read operations
│       ├── eventListener.js  # Blockchain event polling + NFT registration
│       ├── ownerSync.js      # NFT ownership sync service
│       ├── websocket.js      # WebSocket server for real-time updates
│       ├── adminTxQueue.js   # Serialized admin tx queue (Rogue Chain)
│       ├── priceService.js   # ROGUE/ETH price fetching
│       ├── rewardEventListener.js  # Reward event polling (Rogue Chain)
│       └── earningsSyncService.js  # NFT earnings sync + APY calculation
├── public/
│   ├── index.html            # Main HTML page with tab navigation
│   ├── css/
│   │   └── styles.css        # Tailwind CSS styling
│   └── js/
│       ├── app.js            # Main application logic + routing
│       ├── config.js         # Frontend configuration (+ Rogue Chain config)
│       ├── wallet.js         # Multi-wallet connection (MetaMask, Coinbase, etc.)
│       ├── mint.js           # Minting functionality with fallback polling
│       ├── affiliate.js      # Affiliate tracking & referral links
│       ├── ui.js             # UI updates & rendering (+ revenue displays)
│       └── revenues.js       # Revenue service + price formatting
├── data/
│   └── highrollers.db        # SQLite database
├── docs/
│   └── AFFILIATE_GAS_ISSUE.md # Known issue documentation
├── cleanup-duplicate-2341.js  # One-time cleanup script
├── import-csv-data.js         # CSV import tool
├── fly.toml                   # Fly.io configuration
├── Dockerfile                 # Docker build configuration
└── PLAN.md                    # Detailed implementation plan
```

## Environment Variables

```bash
# Required
AFFILIATE_LINKER_PRIVATE_KEY=  # Private key for affiliateLinker wallet

# Optional
PORT=3001                      # Server port (default: 3001)
DB_PATH=/data/highrollers.db   # Database path (default: ./data/highrollers.db)
```

## API Endpoints

### Public Endpoints

| Method | Endpoint | Description | Data Source |
|--------|----------|-------------|-------------|
| GET | `/api/stats` | Collection stats, hostess counts, remaining supply | `nfts` table |
| GET | `/api/hostesses` | All hostesses with mint counts | `nfts` table |
| GET | `/api/sales` | Recent sales (paginated: `?limit=50&offset=0`) | `sales` table |
| GET | `/api/nfts/:owner` | NFTs owned by address | `nfts` table |
| GET | `/api/affiliates/:address` | Affiliate earnings and referrals | `affiliate_earnings` table |
| GET | `/api/buyer-affiliate/:buyer` | Get buyer's linked affiliate | `buyer_affiliates` table |

#### Data Source: `nfts` vs `sales` Tables

- **`nfts` table**: Ground truth for NFT ownership and counts. Synced directly from Arbitrum contract via `OwnerSyncService`.
- **`sales` table**: Historical transaction records (who bought, when, tx hash, affiliates). May have gaps if events were missed.

**Important**: `/api/stats` and `/api/hostesses` query from the `nfts` table to ensure accurate counts. The `sales` table is only used for historical transaction display.

**Fix (Jan 5, 2026)**: Changed `/api/stats` and `/api/hostesses` from querying `sales` table to `nfts` table. This fixed a bug where token ID 1942 (Cleo Enchante) was missing from `sales` but present in `nfts`, causing incorrect counts (2,340 vs 2,341).

### Protected Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/link-affiliate` | Link buyer to affiliate (on-chain + DB) |
| POST | `/api/sync-historical-events` | Re-sync from blockchain events |
| POST | `/api/sync-owners` | Trigger full owner sync (catches transfers) |
| POST | `/api/import-sales-csv` | Import sales from CSV |

## Database Schema

### Tables

```sql
-- NFT ownership
CREATE TABLE nfts (
  token_id INTEGER PRIMARY KEY,
  owner TEXT NOT NULL,
  hostess_index INTEGER,
  hostess_name TEXT,
  mint_price TEXT,
  mint_tx_hash TEXT,
  affiliate TEXT,
  affiliate2 TEXT
);

-- Sales history
CREATE TABLE sales (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  token_id INTEGER NOT NULL,
  buyer TEXT NOT NULL,
  hostess_index INTEGER,
  hostess_name TEXT,
  price TEXT,
  tx_hash TEXT,
  block_number INTEGER,
  timestamp INTEGER,
  affiliate TEXT,
  affiliate2 TEXT
);

-- Affiliate earnings
CREATE TABLE affiliate_earnings (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  token_id INTEGER,
  tier INTEGER,
  affiliate TEXT,
  earnings TEXT,
  tx_hash TEXT,
  timestamp INTEGER DEFAULT (strftime('%s', 'now'))
);

-- Buyer-affiliate permanent links
CREATE TABLE buyer_affiliates (
  buyer TEXT PRIMARY KEY,
  affiliate TEXT NOT NULL,
  linked_at INTEGER DEFAULT (strftime('%s', 'now'))
);

-- Hostess mint counts
CREATE TABLE hostess_counts (
  hostess_index INTEGER PRIMARY KEY,
  count INTEGER DEFAULT 0
);
```

## Event Handling

### EventListener Service

- Polls blockchain every 30 seconds for events (avoids "filter not found" errors)
- Handles: `NFTRequested`, `NFTMinted`, `Transfer`
- Uses `upsertSale()` to update fake tx_hash with real one from on-chain events

### OwnerSync Service

Enhanced sync service that ensures data consistency across `nfts`, `sales`, and `affiliate_earnings` tables.

**Startup Sequence** (runs once on server start):
1. `syncMissingSales()` - Finds NFTs in `nfts` table but not in `sales`, fetches affiliate info from contract, inserts complete records
2. `syncMissingAffiliates()` - Finds sales with NULL affiliate or missing `affiliate_earnings` records, fetches from contract
3. `syncAllOwners()` - Updates all NFT owners to catch any ownership transfers

**Periodic Sync**:
- **Quick sync**: Every 30 seconds for new mints (includes affiliate info)
- **Full sync**: Every 10 minutes for ownership transfers

**Key Features**:
- Compares `nfts` table max token ID vs on-chain `totalSupply()` to detect new mints
- Uses `getBuyerInfo(address)` contract call to fetch affiliate addresses
- Calculates affiliate earnings (20% tier 1, 5% tier 2) from mint price
- Logs all sync activity for debugging

### Duplicate Prevention

| Data Type | Prevention Method |
|-----------|-------------------|
| Sales | `upsertSale()` - updates fake tx_hash with real one |
| Affiliate Earnings | `INSERT OR IGNORE` |
| Buyer Links | Primary key on buyer address |

---

## NFT Sync Systems - Complete Technical Breakdown

The High Rollers NFT app uses **three independent sync services** that work together to ensure data consistency:

| Service | Network | Purpose | Interval |
|---------|---------|---------|----------|
| **EventListener** | Arbitrum | Real-time mints & transfers | 30s polling |
| **OwnerSync** | Arbitrum | Fallback ownership sync + data consistency | 30s quick / 10m full |
| **RewardListener** | Rogue Chain | Revenue sharing events | 10s polling |

### 1. EventListener (Primary Real-Time System)

**File**: `server/services/eventListener.js`
**Network**: Arbitrum One (Chain ID: 42161)

EventListener polls for blockchain events every **30 seconds** instead of using WebSocket subscriptions (which cause "filter not found" errors on Arbitrum RPC).

#### Events Watched

| Event | Description | Action |
|-------|-------------|--------|
| `NFTRequested` | User initiated mint (VRF pending) | Store pending mint, broadcast to UI |
| `NFTMinted` | Chainlink VRF completed, NFT created | Insert into `nfts`, `sales`, `affiliate_earnings` tables |
| `Transfer` | NFT transferred (non-mint) | Update owner in `nfts`, trigger Rogue Chain ownership update |

#### Polling Flow (every 30s)

```
┌─────────────────────────────────────────────────────────────────────┐
│                    EVENT LISTENER POLLING CYCLE                      │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  1. Get current block number from Arbitrum RPC                       │
│                                                                      │
│  2. If new blocks since last check:                                  │
│     ├── Query NFTRequested events (fromBlock → currentBlock)         │
│     │   └── Store in pendingMints Map + broadcast MINT_REQUESTED     │
│     │                                                                │
│     ├── Query NFTMinted events                                       │
│     │   └── handleMintComplete():                                    │
│     │       ├── Insert into nfts table                               │
│     │       ├── Insert into sales table (upsert)                     │
│     │       ├── Insert affiliate_earnings (tier 1 & 2)               │
│     │       ├── Broadcast NFT_MINTED to WebSocket clients            │
│     │       └── registerNFTOnRogueChain() (async)                    │
│     │                                                                │
│     └── Query Transfer events (exclude mints)                        │
│         └── Update owner in nfts table                               │
│         └── updateOwnershipOnRogueChain() (async)                    │
│                                                                      │
│  3. Update lastProcessedBlock                                        │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

#### Fallback Polling (every 5s)

Catches missed events by:

1. **checkPendingMints()**: If a mint has been pending >60s, queries contract directly via `ownerOf(tokenId)` to check if it completed
2. **checkSupplyChanges()**: Compares on-chain `totalSupply()` vs `lastKnownSupply` to detect missed mints

#### Cross-Chain Actions

When an NFT is minted or transferred, EventListener triggers actions on Rogue Chain:

| Arbitrum Event | Rogue Chain Action |
|----------------|-------------------|
| NFTMinted | `registerNFT(tokenId, hostessIndex, owner)` on NFTRewarder |
| Transfer | `updateOwnership(tokenId, newOwner)` on NFTRewarder |

These are executed via `adminTxQueue` to serialize transactions and prevent nonce conflicts.

### 2. OwnerSync Service (Fallback & Data Consistency)

**File**: `server/services/ownerSync.js`
**Network**: Arbitrum One

OwnerSync is a **safety net** that:
1. Catches any mints/transfers EventListener missed
2. Ensures data consistency across `nfts`, `sales`, and `affiliate_earnings` tables
3. Keeps special NFTs (2340+) and their time rewards in sync

#### Startup Sequence (runs once on server start)

```
┌─────────────────────────────────────────────────────────────────────┐
│                     OWNERSYNC STARTUP SEQUENCE                       │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  1. Get on-chain totalSupply() and DB max token_id                   │
│     └── Log: "On-chain supply: 2342, DB max token: 2342"             │
│                                                                      │
│  2. syncMissingSales() - Data consistency fix                        │
│     └── SELECT from nfts LEFT JOIN sales WHERE sales.token_id IS NULL│
│     └── For each missing token:                                      │
│         ├── Fetch hostessIndex, owner from Arbitrum contract         │
│         ├── Fetch affiliate, affiliate2 via getBuyerInfo(owner)      │
│         ├── Insert into sales table                                  │
│         └── Insert into affiliate_earnings (tier 1 & 2)              │
│                                                                      │
│  3. syncMissingAffiliates() - Fix incomplete affiliate data          │
│     └── SELECT sales with NULL affiliate OR missing affiliate_earnings│
│     └── For each:                                                    │
│         ├── Fetch affiliate info from contract                       │
│         ├── Update sales.affiliate, sales.affiliate2                 │
│         └── Insert missing affiliate_earnings records                │
│                                                                      │
│  4. If dbMaxToken < onChainSupply:                                   │
│     └── syncRecentMints() - Add missing NFTs to nfts table           │
│                                                                      │
│  5. syncSpecialNFTOwners() - Quick sync for tokens 2340+             │
│     └── For each special NFT:                                        │
│         ├── Get on-chain owner via getOwnerOf(tokenId)               │
│         ├── Update nfts table if owner changed                       │
│         └── ALWAYS update time_reward_nfts table (may be stale)      │
│                                                                      │
│  6. syncAllOwners() - Background full sync (non-blocking)            │
│     └── Takes ~15 minutes, updates all 2342 NFTs                     │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

#### Periodic Sync Intervals

| Method | Interval | Purpose |
|--------|----------|---------|
| `syncRecentMints()` | 30 seconds | Detect new mints via totalSupply() comparison |
| `syncAllOwners()` | 10 minutes | Full owner sync for all NFTs |

#### Quick Sync (`syncRecentMints`) - Every 30s

```javascript
// Compare lastSyncedTokenId vs current totalSupply
if (total > this.lastSyncedTokenId) {
  // New mints detected! Sync tokens from lastSyncedTokenId+1 to total
  for (let tokenId = this.lastSyncedTokenId + 1; tokenId <= total; tokenId++) {
    // Get owner, hostessIndex from Arbitrum contract
    // Get affiliate info via getBuyerInfo(owner)
    // Insert into nfts, sales, affiliate_earnings tables
  }
  this.lastSyncedTokenId = total;
}
```

#### Full Sync (`syncAllOwners`) - Every 10 minutes

- Batches of 5 tokens per RPC call
- 2 second delay between batches (rate limit protection)
- Updates all NFT owners in `nfts` table
- Takes ~15 minutes to complete

#### Special NFT Sync (`syncSpecialNFTOwners`) - On startup only

- Specifically targets tokens 2340+ (time reward NFTs)
- Much faster than full sync (~1s for 3 NFTs)
- Updates BOTH `nfts` and `time_reward_nfts` tables
- Runs before starting background full sync

### 3. RewardEventListener (Rogue Chain)

**File**: `server/services/rewardEventListener.js`
**Network**: Rogue Chain (560013)

Watches NFTRewarder contract for revenue sharing events when BUX Booster bets are lost.

#### Events Watched

| Event | Description | Action |
|-------|-------------|--------|
| `RewardReceived` | ROGUEBankroll sent rewards to NFTRewarder | Store in `reward_events`, broadcast |
| `RewardClaimed` | User withdrew pending rewards | Store in `reward_withdrawals`, reset pending |

#### Polling Flow (every 10s)

```
┌─────────────────────────────────────────────────────────────────────┐
│                  REWARD LISTENER POLLING CYCLE                       │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  1. Get current block from Rogue Chain RPC                           │
│                                                                      │
│  2. Query RewardReceived events (fromBlock → currentBlock)           │
│     └── For each event:                                              │
│         ├── Insert into reward_events table                          │
│         └── Broadcast REWARD_RECEIVED via WebSocket                  │
│                                                                      │
│  3. Query RewardClaimed events                                       │
│     └── For each event:                                              │
│         ├── Insert into reward_withdrawals table                     │
│         ├── Reset pending amounts for claimed NFTs                   │
│         └── Broadcast REWARD_CLAIMED via WebSocket                   │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

#### Historical Backfill (on startup)

On server start, backfills all historical `RewardReceived` events from block 109350000 (contract deployment) to current block. This ensures 24h calculations are accurate after server restarts.

### 4. Database Tables Updated by Sync Systems

| Table | EventListener | OwnerSync | RewardListener |
|-------|--------------|-----------|----------------|
| `nfts` | ✅ Insert/Update | ✅ Upsert/Update | - |
| `sales` | ✅ Upsert | ✅ Insert | - |
| `affiliate_earnings` | ✅ Insert | ✅ Insert | - |
| `pending_mints` | ✅ Insert/Delete | - | - |
| `time_reward_nfts` | - | ✅ Update owner | - |
| `reward_events` | - | - | ✅ Insert |
| `reward_withdrawals` | - | - | ✅ Insert |

### 5. Timing Summary

| Service | Method | Interval | Duration |
|---------|--------|----------|----------|
| EventListener | Event polling | 30s | ~1s |
| EventListener | Fallback polling | 5s | ~1s |
| OwnerSync | syncRecentMints | 30s | ~1s per new mint |
| OwnerSync | syncAllOwners | 10 min | ~15 min |
| OwnerSync | syncSpecialNFTOwners | Startup only | ~1s |
| RewardListener | Event polling | 10s | ~1s |

### 6. Data Flow Diagram

```
                    ARBITRUM ONE                              ROGUE CHAIN
                    ────────────                              ───────────
┌──────────────────────────────────────┐          ┌──────────────────────────────┐
│         HIGH ROLLERS NFT             │          │        NFT REWARDER          │
│         (ERC-721 Contract)           │          │        (UUPS Proxy)          │
├──────────────────────────────────────┤          ├──────────────────────────────┤
│                                      │          │                              │
│  Events:                             │   ───►   │  registerNFT()               │
│  - NFTRequested                      │ Async    │  updateOwnership()           │
│  - NFTMinted                         │ Calls    │                              │
│  - Transfer                          │          │  Events:                     │
│                                      │          │  - RewardReceived            │
└───────────────┬──────────────────────┘          │  - RewardClaimed             │
                │                                 └──────────────┬───────────────┘
                │ Polling (30s)                                  │ Polling (10s)
                ▼                                                ▼
┌───────────────────────────────────────────────────────────────────────────────┐
│                              NODE.JS SERVER                                    │
├───────────────────────────────────────────────────────────────────────────────┤
│                                                                                │
│  ┌─────────────────┐   ┌──────────────────┐   ┌────────────────────────────┐  │
│  │  EventListener  │   │   OwnerSync      │   │    RewardEventListener     │  │
│  │                 │   │                  │   │                            │  │
│  │ • 30s event poll│   │ • 30s quick sync │   │ • 10s event poll           │  │
│  │ • 5s fallback   │   │ • 10m full sync  │   │ • Startup backfill         │  │
│  │ • Triggers      │   │ • Startup data   │   │                            │  │
│  │   Rogue calls   │   │   consistency    │   │                            │  │
│  └────────┬────────┘   └────────┬─────────┘   └──────────────┬─────────────┘  │
│           │                     │                            │                 │
│           └─────────────────────┼────────────────────────────┘                 │
│                                 ▼                                              │
│                     ┌──────────────────────┐                                   │
│                     │    SQLite Database   │                                   │
│                     │    (highrollers.db)  │                                   │
│                     ├──────────────────────┤                                   │
│                     │ • nfts               │                                   │
│                     │ • sales              │                                   │
│                     │ • affiliate_earnings │                                   │
│                     │ • time_reward_nfts   │                                   │
│                     │ • reward_events      │                                   │
│                     │ • reward_withdrawals │                                   │
│                     └──────────────────────┘                                   │
│                                                                                │
└────────────────────────────────────────────────────────────────────────────────┘
```

### 7. Why Multiple Systems?

| Challenge | Solution |
|-----------|----------|
| RPC "filter not found" errors | Use `queryFilter()` polling instead of `contract.on()` |
| Missed events due to RPC issues | OwnerSync fallback compares DB vs on-chain supply |
| Data inconsistency (nfts exists but not in sales) | `syncMissingSales()` at startup |
| Missing affiliate data | `syncMissingAffiliates()` at startup |
| Stale owners after transfers | Full sync every 10 min + special NFT quick sync |
| Time reward owners out of sync | `syncSpecialNFTOwners()` updates `time_reward_nfts` table |

---

### Nonce Conflict Handling

When multiple services call `linkAffiliate` simultaneously:
- 3-attempt retry with 2-second delay between attempts
- Detects nonce errors by checking for "nonce" or "replacement" in error message
- Still saves to database even if on-chain linking fails

## Frontend Navigation

Tab-based navigation with URL routing:

| Tab | Route | Description |
|-----|-------|-------------|
| Mint | `/` or `/mint` | Main minting interface with countdown to 2700 |
| Gallery | `/gallery` | All 8 NFT types with mint counts + APY/24h badges |
| Sales | `/sales` | Live sales table with real-time updates |
| Affiliates | `/affiliates` | Affiliate earnings table & user's referral link |
| My NFTs | `/my-nfts` | User's owned NFTs with earnings display |
| Revenues | `/revenues` | 🟢 **NEW**: Revenue sharing stats, earnings, withdrawals |

## Multi-Wallet Support

Supported wallets with automatic detection:

- MetaMask
- Coinbase Wallet
- Rabby
- Trust Wallet
- Brave Wallet

## Deployment

### Fly.io

```bash
# Set secrets
flyctl secrets set AFFILIATE_LINKER_PRIVATE_KEY="0x..." --app high-rollers-nfts

# Deploy
flyctl deploy --app high-rollers-nfts

# SSH into container
flyctl ssh console --app high-rollers-nfts
```

### Volume Configuration

- **Path**: `/data`
- **Contains**: `highrollers.db` (SQLite database)
- **Region**: Frankfurt (fra)

## Known Issues

### 1. Affiliate Array Gas Limit

Large affiliate arrays can cause VRF callback failures (out of gas error).

**Symptoms**:
- User pays 0.32 ETH but receives no NFT
- VRF callback fails with "out of gas: not enough gas for reentrancy sentry"

**Root Cause**: Contract updates affiliate arrays during minting. When arrays exceed ~500 elements, gas exceeds 2.5M limit.

**Mitigation**: Changed default affiliate to fresh address with no history.

See [docs/AFFILIATE_GAS_ISSUE.md](docs/AFFILIATE_GAS_ISSUE.md) for details.

### 2. Duplicate Sales Entries

**Cause**: Race condition between OwnerSync and EventListener services.

**Solution**:
- OwnerSync uses `saleExistsForToken()` check before inserting
- EventListener uses `upsertSale()` to update fake tx_hash with real one
- Real tx_hash from EventListener takes priority over fake `0x000...` from OwnerSync

## Maintenance Scripts

### Cleanup Duplicate Sales

```bash
# SSH into Fly and run
flyctl ssh console --app high-rollers-nfts -C "node cleanup-duplicate-2341.js"
```

### Import from CSV (Local Only)

```bash
node import-csv-data.js
```

## Contract Functions

### Read Functions

```solidity
function totalSupply() view returns (uint256)
function getCurrentPrice() view returns (uint256)
function getMaxSupply() view returns (uint256)
function ownerOf(uint256 tokenId) view returns (address)
function s_tokenIdToHostess(uint256 tokenId) view returns (uint256)
function getHostessByTokenId(uint256 tokenId) view returns (string)
function getTokenIdsByWallet(address buyer) view returns (uint256[])
function getBuyerInfo(address buyer) view returns (nftCount, spent, affiliate, affiliate2, tokenIds[])
function getAffiliateInfo(address affiliate) view returns (buyerCount, referreeCount, referredAffiliatesCount, totalSpent, earnings, balance, buyers[], referrees[], referredAffiliates[], tokenIds[])
function getAffiliate2Info(address affiliate) view returns (buyerCount2, referreeCount2, referredAffiliatesCount, totalSpent2, earnings2, balance, buyers2[], referrees2[], referredAffiliates[], tokenIds2[])
function getTotalSalesVolume() view returns (uint256)
function getTotalAffiliatesBalance() view returns (uint256)
```

### Write Functions

```solidity
function requestNFT() payable returns (uint256 requestId)
function linkAffiliate(address buyer, address affiliate) returns (address)
function withdrawFromAffiliate() external
```

### Events

```solidity
event NFTRequested(uint256 requestId, address sender, uint256 currentPrice, uint256 tokenId)
event NFTMinted(uint256 requestId, address recipient, uint256 currentPrice, uint256 tokenId, uint8 hostess, address affiliate, address affiliate2)
event Transfer(address indexed from, address indexed to, uint256 indexed tokenId)
```

## NFT Revenue Sharing (🟢 LIVE - Jan 5, 2026)

High Rollers NFTs earn passive income from ROGUE betting on BUX Booster. When players lose ROGUE bets, 0.2% of the wager is distributed to NFT holders proportionally based on their multiplier.

### Revenue Sharing Contracts (Rogue Chain)

| Contract | Address | Status |
|----------|---------|--------|
| NFTRewarder Proxy | `0x96aB9560f1407586faE2b69Dc7f38a59BEACC594` | ✅ LIVE |
| NFTRewarder V5 Impl | `0x51F7f2b0Ac9e4035b3A14d8Ea4474a0cf62751Bb` | Current |
| ROGUEBankroll | `0x51DB4eD2b69b598Fade1aCB5289C7426604AB2fd` | ✅ LIVE |

### How Revenue Sharing Works

1. Player loses a ROGUE bet on BUX Booster
2. ROGUEBankroll sends 0.2% of the wager to NFTRewarder
3. NFTRewarder distributes rewards proportionally by multiplier
4. NFT holders can view earnings and withdraw via the Revenues tab

### Backend Services

| Service | Interval | Purpose |
|---------|----------|---------|
| PriceService | 10 min | ROGUE/ETH prices (Blockster API primary, CoinGecko fallback) |
| RewardEventListener | 10 sec | Polls for RewardReceived/RewardClaimed events |
| EarningsSyncService | 30 sec | Syncs NFT earnings, calculates 24h and APY |
| AdminTxQueue | On-demand | Serializes admin transactions (registerNFT, updateOwnership, withdrawTo, claimTimeRewards) |
| TimeRewardTracker | On-demand | Tracks special NFT time rewards locally (zero blockchain calls) |

### Revenue API Endpoints

| Endpoint | Description |
|----------|-------------|
| `GET /api/revenues/stats` | Global stats + per-hostess breakdown (combined revenue + time rewards) |
| `GET /api/revenues/nft/:tokenId` | Individual NFT earnings |
| `GET /api/revenues/user/:address` | All NFT earnings for a wallet |
| `GET /api/revenues/history` | Recent reward events |
| `GET /api/revenues/prices` | ROGUE + ETH prices |
| `POST /api/revenues/withdraw` | Withdraw pending rewards (revenue + time) |

### Environment Variables (Revenue Sharing)

```bash
ADMIN_PRIVATE_KEY=    # Admin wallet for NFTRewarder operations
```

### Documentation

See [nft_revenues.md](nft_revenues.md) for complete implementation details.

---

## Time-Based Rewards (🟢 LIVE - Jan 6, 2026)

**Special NFTs** (token IDs 2340-2700) earn additional time-based ROGUE rewards over a 180-day period. This is **separate from** revenue sharing - special NFTs earn both!

### Key Numbers

| Property | Value |
|----------|-------|
| Total ROGUE Pool | 5,614,272,000 ROGUE |
| NFT Range | Token IDs 2340-2700 (361 NFTs) |
| Distribution Period | 180 days per NFT |
| ROGUE per NFT (average) | ~15,552,000 ROGUE |
| USD Value per NFT | ~$1,024 (at $0.0001/ROGUE) |
| ETH Equivalent | ~0.32 ETH per NFT |

### Per-Hostess ROGUE Rates

| Multiplier | Hostess | ROGUE/Day | ROGUE/180 Days | Rate/Second |
|------------|---------|-----------|----------------|-------------|
| 100x | Penelope Fatale | 183,580 | 33,044,567 | 2.125 |
| 90x | Mia Siren | 165,222 | 29,740,111 | 1.912 |
| 80x | Cleo Enchante | 146,864 | 26,435,654 | 1.700 |
| 70x | Sophia Spark | 128,506 | 23,131,197 | 1.487 |
| 60x | Luna Mirage | 110,148 | 19,826,740 | 1.275 |
| 50x | Aurora Seductra | 91,790 | 16,522,284 | 1.062 |
| 40x | Scarlett Ember | 73,432 | 13,217,827 | 0.850 |
| 30x | Vivienne Allure | 55,074 | 9,913,370 | 0.637 |

### How Time Rewards Work

1. User mints NFT on Arbitrum (Chainlink VRF determines type)
2. EventListener detects `NFTMinted` event
3. Server calls `registerNFT()` on NFTRewarder (Rogue Chain)
4. **180-day countdown starts at `block.timestamp`**
5. NFT earns ROGUE every second based on hostess type
6. User can claim anytime; unclaimed rewards accumulate
7. After 180 days, time rewards stop but revenue sharing continues

### Time Reward API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/revenues/time-rewards/stats` | GET | Global time reward pool statistics |
| `/api/revenues/time-rewards/nft/:tokenId` | GET | Single NFT time reward info |
| `/api/revenues/time-rewards/user/:address` | GET | All time rewards for wallet |
| `/api/revenues/time-rewards/static-data` | GET | Static data for client calculations (cacheable) |
| `/api/revenues/time-rewards/claim` | POST | Claim time rewards |
| `/api/revenues/time-rewards/sync` | POST | Sync from blockchain (admin) |

### Real-Time Counter (TimeRewardCounter)

The frontend displays real-time counting earnings with **zero database queries**:

- `public/js/timeRewardCounter.js` - Client-side counter class
- 8 hardcoded rates matching contract exactly
- 1-second UI update loop
- Methods: `initialize()`, `getPending()`, `getTotals()`, `get24hEarnings()`

### Live Earnings Updates (My NFTs Tab)

NFT cards on the My NFTs tab auto-update their Betting Rewards (pending + total) when rewards are received:

- Data attributes: `data-nft-pending`, `data-nft-total`, `data-nft-pending-usd`, `data-nft-total-usd`
- WebSocket event: `EARNINGS_SYNCED` triggers `updateMyNFTsEarnings()` in app.js
- Update interval: Every ~10 seconds (same as My Earnings tab)
- No full re-render - only updates affected elements for smooth UX

### Special NFT Visual Treatment

- Golden animated glow border (CSS `.special-nft-glow`)
- "⭐ SPECIAL" badge on card
- Sorted by token_id descending (newest first)
- Time remaining display (days/hours/minutes)

### Combined Withdrawals

The withdraw button claims **both** revenue sharing AND time rewards in one transaction.

### Documentation

See `/docs/NFT_TIME_BASED_REWARDS_IMPLEMENTATION.md` in the main blockster_v2 repo for complete implementation details.

---

## Wallet Network Switching (Multi-Chain Support)

The frontend automatically switches between **Arbitrum One** (for minting) and **Rogue Chain** (for revenues) based on the active tab.

### Network Configuration

| Property | Arbitrum One | Rogue Chain |
|----------|--------------|-------------|
| Chain ID | 42161 | 560013 |
| Chain ID Hex | `0xa4b1` | `0x88b8d` |
| RPC URL | `https://arb1.arbitrum.io/rpc` | `https://rpc.roguechain.io/rpc` |
| Explorer | `https://arbiscan.io` | `https://roguescan.io` |
| Currency | ETH | ROGUE |

> **Important**: Rogue Chain ID `560013` = `0x88b8d` (not `0x88b0d`). Verify with `(560013).toString(16)`.

### Tab-Based Switching

| Tab | Network | Balance Displayed |
|-----|---------|-------------------|
| Mint | Arbitrum | ETH |
| Gallery | Rogue Chain | ROGUE |
| My NFTs | Rogue Chain | ROGUE |
| Revenues | Rogue Chain | ROGUE |

### WalletService Methods

```javascript
// Switch to Arbitrum (Mint tab)
await window.walletService.switchToArbitrum();

// Switch to Rogue Chain (other tabs)
await window.walletService.switchToRogueChain();

// Generic switch
await window.walletService.switchNetwork('arbitrum' | 'rogue');

// Get ROGUE balance (uses Rogue RPC directly, no wallet switch needed)
const balance = await window.walletService.getROGUEBalance();
```

### Error Handling

| Code | Meaning | Action |
|------|---------|--------|
| `4902` | Chain not added to wallet | Auto-add via `wallet_addEthereumChain` |
| `4001` | User rejected switch | Log and continue (non-blocking) |
| `-32002` | Request pending in wallet | Log and continue (non-blocking) |

### Database Sync Warning

When withdrawing time rewards, the **on-chain `lastClaimTime`** is the source of truth. If you withdraw from the same wallet on both production and local servers, the local database will have stale data.

**Symptoms**: Frontend shows higher pending than actually received.

**Solution**:
```bash
# Sync specific NFT
curl -X POST http://localhost:3000/api/revenues/time-rewards/sync \
  -H "Content-Type: application/json" \
  -d '{"tokenIds": [2341]}'

# Or run full sync
node server/scripts/sync-time-rewards.js
```

---

## NFT Distribution Analysis (Jan 5, 2026)

| Type | Expected % | Actual Count | Actual % | Multiplier | Total Points |
|------|------------|--------------|----------|------------|--------------|
| Penelope Fatale | 0.5% | 9 | 0.38% | 100x | 900 |
| Mia Siren | 1.0% | 21 | 0.90% | 90x | 1,890 |
| Cleo Enchante | 3.5% | 114 | 4.87% | 80x | 9,120 |
| Sophia Spark | 7.5% | 149 | 6.37% | 70x | 10,430 |
| Luna Mirage | 12.5% | 274 | 11.70% | 60x | 16,440 |
| Aurora Seductra | 25.0% | 581 | 24.82% | 50x | 29,050 |
| Scarlett Ember | 25.0% | 577 | 24.65% | 40x | 23,080 |
| Vivienne Allure | 25.0% | 616 | 26.32% | 30x | 18,480 |
| **Total** | - | **2,341** | 100% | - | **109,390** |

> **Data Source**: Verified from Arbitrum contract `0x7176d2edd83aD037bd94b7eE717bd9F661F560DD`.
> Query: `s_tokenIdToHostess(tokenId)` for each token 1-2341.

**Total Multiplier Points (109,390)**: Used for proportional revenue distribution. Higher multiplier NFTs earn larger shares of the reward pool.

**Note**: First 1060 NFTs were airdrops to Digitex holders (may have different distribution than random mints).

## ImageKit Image Optimization

All NFT images are served through ImageKit for optimized delivery:

```
https://ik.imagekit.io/blockster/{hostess}.jpg
```

Transform examples:
- Thumbnail: `tr:w-48,h-48`
- Card: `tr:w-200,h-200`
- Large: `tr:w-400,h-400`

---

*Last updated: January 7, 2026 - Live earnings updates on My NFTs tab*
