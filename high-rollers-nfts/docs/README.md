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

- **Quick sync**: Every 5 seconds for new mints
- **Full sync**: Every 5 minutes for ownership changes
- Uses `saleExistsForToken()` check before inserting to prevent duplicates

### Duplicate Prevention

| Data Type | Prevention Method |
|-----------|-------------------|
| Sales | `upsertSale()` - updates fake tx_hash with real one |
| Affiliate Earnings | `INSERT OR IGNORE` |
| Buyer Links | Primary key on buyer address |

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
| NFTRewarder | `0x96aB9560f1407586faE2b69Dc7f38a59BEACC594` | ✅ LIVE |
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
| AdminTxQueue | On-demand | Serializes admin transactions (registerNFT, updateOwnership, withdrawTo) |

### Revenue API Endpoints

| Endpoint | Description |
|----------|-------------|
| `GET /api/revenues/stats` | Global stats + per-hostess breakdown |
| `GET /api/revenues/nft/:tokenId` | Individual NFT earnings |
| `GET /api/revenues/user/:address` | All NFT earnings for a wallet |
| `GET /api/revenues/history` | Recent reward events |
| `GET /api/revenues/prices` | ROGUE + ETH prices |
| `POST /api/revenues/withdraw` | Withdraw pending rewards |

### Environment Variables (Revenue Sharing)

```bash
ADMIN_PRIVATE_KEY=    # Admin wallet for NFTRewarder operations
```

### Documentation

See [nft_revenues.md](nft_revenues.md) for complete implementation details.

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

*Last updated: January 5, 2026*
