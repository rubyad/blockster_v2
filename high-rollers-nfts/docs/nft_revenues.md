# NFT Revenue Sharing from ROGUE Betting - Implementation Plan

**Date**: January 4, 2026
**Status**: Planning
**Objective**: Enable High Rollers NFTs on Arbitrum One to receive real-time revenue sharing from ROGUE betting on BUX Booster (Rogue Chain).

---

## Executive Summary

High Rollers NFTs will earn a share of the house edge every time a player loses a ROGUE bet on BUX Booster. When a bet is lost:
1. ROGUEBankroll keeps the wager (house wins)
2. 20% of the ~1% house edge profit is sent to NFTRewarder contract
3. NFTRewarder distributes rewards proportionally based on NFT multipliers
4. NFT owners can view real-time earnings and withdraw accumulated rewards

**Key Value Proposition**: Passive income proportional to NFT rarity - a 100x Penelope Fatale earns 3.33x more than a 30x Vivienne Allure.

---

## System Architecture Overview

### Cross-Chain Design

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                              HIGH-LEVEL ARCHITECTURE                                  │
├─────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                       │
│  ROGUE CHAIN (560013)                       ARBITRUM ONE (42161)                     │
│  ┌─────────────────────┐                   ┌─────────────────────┐                   │
│  │   BuxBoosterGame    │                   │  High Rollers NFT   │                   │
│  │   (Existing V5)     │                   │  (Existing Contract)│                   │
│  └──────────┬──────────┘                   └──────────┬──────────┘                   │
│             │ settleBetROGUE()                        │ ownerOf(), multiplier        │
│             ▼                                         ▼                              │
│  ┌─────────────────────┐                   ┌─────────────────────┐                   │
│  │   ROGUEBankroll     │   ─ ─ ─ ─ ─ ─ ─   │    NFTRewarder      │                   │
│  │   (Modified V7)     │   Cross-Chain     │    (NEW CONTRACT)   │                   │
│  │                     │   Oracle/Bridge   │                     │                   │
│  │ settleBuxBooster    │   ─ ─ ─ ─ ─ ─ ─   │ receiveReward()     │                   │
│  │ LosingBet()         │─────────────────▶ │ withdraw()          │                   │
│  │   ↓                 │                   │ getEarnings()       │                   │
│  │ Calculate 20% of    │                   └──────────┬──────────┘                   │
│  │ house edge          │                              │                              │
│  │   ↓                 │                              ▼                              │
│  │ Send to NFTRewarder │                   ┌─────────────────────┐                   │
│  │ via bridge          │                   │   high-rollers-nfts │                   │
│  └─────────────────────┘                   │   Node.js App       │                   │
│                                            │   (Real-time UI)    │                   │
│                                            └─────────────────────┘                   │
│                                                                                       │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

### Option A: Same-Chain (Simpler - Recommended for V1)

Deploy NFTRewarder on **Rogue Chain** instead of Arbitrum. NFT ownership is mirrored via a registry that the high-rollers-nfts server maintains.

**Pros**:
- No cross-chain bridge complexity
- Instant, atomic payments
- Lower gas costs
- Simpler implementation

**Cons**:
- NFT holders must bridge ROGUE rewards to Arbitrum manually if they want ETH
- Requires NFT ownership registry on Rogue Chain

### Option B: Cross-Chain Bridge (More Complex)

Use a bridge/oracle to send rewards from Rogue Chain to Arbitrum.

**Pros**:
- Rewards arrive in same chain as NFTs
- Seamless user experience

**Cons**:
- Bridge security risks
- Higher gas costs
- More complex implementation
- Potential delays in reward distribution

**Recommendation**: Start with Option A (Same-Chain) for V1. The simplicity and reliability outweigh the inconvenience of users bridging rewards.

---

## Revenue Model & Economics

### House Edge Breakdown (All 9 Difficulties)

| Difficulty | Mode | Flips | Win Chance | Multiplier | House Edge |
|------------|------|-------|------------|------------|------------|
| -4 | Win One | 5 | 96.875% | 1.02x | 1.1875% |
| -3 | Win One | 4 | 93.75% | 1.05x | 1.5625% |
| -2 | Win One | 3 | 87.5% | 1.13x | 1.125% |
| -1 | Win One | 2 | 75% | 1.32x | 1% |
| 0 | Win All | 1 | 50% | 1.98x | 1% |
| 1 | Win All | 2 | 25% | 3.96x | 1% |
| 2 | Win All | 3 | 12.5% | 7.92x | 1% |
| 3 | Win All | 4 | 6.25% | 15.84x | 1% |
| 4 | Win All | 5 | 3.125% | 31.68x | 1% |

**House Edge Formula**: `1 - (Win Probability × Multiplier)`

### Revenue Split

**Fixed 20 BPS (0.20% of wager)** sent to NFT holders on every losing bet, regardless of difficulty.

This is approximately 20% of the ~1% house edge, simplified for gas efficiency.

| Difficulty | House Edge | Exact 20% | We Pay (Fixed) | Difference |
|------------|------------|-----------|----------------|------------|
| -4 | 1.1875% | 0.2375% | 0.20% | -0.0375% |
| -3 | 1.5625% | 0.3125% | 0.20% | -0.1125% |
| -2 | 1.125% | 0.225% | 0.20% | -0.025% |
| -1 to 4 | 1% | 0.20% | 0.20% | 0% |

**Trade-off**: Slightly under-pays NFTs on difficulties -4, -3, -2, but greatly simplifies contract logic.

### Examples with 100 ROGUE Bet

| Difficulty | House Edge | House Profit | NFT Payout (Fixed 20 BPS) |
|------------|------------|--------------|---------------------------|
| -4 | 1.1875% | 1.19 ROGUE | **0.20 ROGUE** |
| -3 | 1.5625% | 1.56 ROGUE | **0.20 ROGUE** |
| -2 | 1.125% | 1.13 ROGUE | **0.20 ROGUE** |
| -1 | 1% | 1.00 ROGUE | **0.20 ROGUE** |
| 0 | 1% | 1.00 ROGUE | **0.20 ROGUE** |
| 1 | 1% | 1.00 ROGUE | **0.20 ROGUE** |
| 2 | 1% | 1.00 ROGUE | **0.20 ROGUE** |
| 3 | 1% | 1.00 ROGUE | **0.20 ROGUE** |
| 4 | 1% | 1.00 ROGUE | **0.20 ROGUE** |

**Simplified Calculation**: `NFT_REWARD = WAGER_AMOUNT × 0.002` (20 basis points)

### Multiplier-Weighted Distribution

Total NFT multiplier sum (current supply of 2,341 NFTs as of Jan 5, 2026):

| NFT Type | Count | Multiplier | Total Points |
|----------|-------|------------|--------------|
| Penelope Fatale | 9 | 100x | 900 |
| Mia Siren | 21 | 90x | 1,890 |
| Cleo Enchante | 114 | 80x | 9,120 |
| Sophia Spark | 149 | 70x | 10,430 |
| Luna Mirage | 274 | 60x | 16,440 |
| Aurora Seductra | 581 | 50x | 29,050 |
| Scarlett Ember | 577 | 40x | 23,080 |
| Vivienne Allure | 616 | 30x | 18,480 |
| **TOTAL** | **2,341** | - | **109,390** |

> **Verified from**: Arbitrum contract `0x7176d2edd83aD037bd94b7eE717bd9F661F560DD`
> Production DB at `/data/highrollers.db` matches these counts.

**Per-Point Reward**: `NFT_REWARD ÷ 109,390`

**Example**: 2 ROGUE reward from a losing bet
- Per point: 2 ÷ 109,390 = 0.0000183 ROGUE
- Penelope Fatale (100x): 0.00183 ROGUE
- Vivienne Allure (30x): 0.000549 ROGUE

---

## Smart Contract: NFTRewarder.sol

### Contract Location

Deploy to: **Rogue Chain Mainnet (560013)**
Directory: `contracts/bux-booster-game/contracts/NFTRewarder.sol`
Pattern: **UUPS Upgradeable Proxy** (flattened, same structure as BuxBoosterGame.sol)

### UUPS Upgradeability

NFTRewarder follows the same flattened UUPS pattern as BuxBoosterGame:
- OpenZeppelin base contracts (Initializable, UUPSUpgradeable, OwnableUpgradeable) are copied inline
- No imports - entire contract is self-contained for Roguescan verification
- Uses `initialize()` instead of constructor
- Owner can call `upgradeToAndCall()` to upgrade implementation

**Deployment:**
1. Deploy NFTRewarder implementation via Hardhat
2. Hardhat-upgrades creates ERC1967Proxy automatically
3. Call `initialize(_rogueBankroll)` on proxy address
4. Verify flattened source on Roguescan

**Storage Layout Rules (CRITICAL):**
1. NEVER delete existing state variables
2. NEVER reorder existing state variables
3. ONLY append new variables at the END
4. Use `reinitializer(N)` for upgrade initialization

### Core State Variables

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// ============ Flattened OpenZeppelin Contracts ============
// (Same pattern as BuxBoosterGame.sol - copy Initializable, UUPSUpgradeable,
//  OwnableUpgradeable, ERC1967Utils inline for Roguescan verification)

// ... flattened base contracts here ...

// ============ NFTRewarder Contract ============

contract NFTRewarder is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    // ============ State Variables ============

    // Access Control
    // - owner: Can upgrade contract, set admin, set rogueBankroll (multisig/cold wallet)
    // - admin: Can register NFTs, update ownership, process withdrawals (server hot wallet)
    address public admin;
    address public rogueBankroll;  // Authorized to send rewards

    // NFT Registry
    struct NFTMetadata {
        uint8 hostessIndex;     // 0-7 (determines multiplier)
        bool registered;        // Has this tokenId been registered
        address owner;          // Current owner (synced from Arbitrum by server)
    }
    mapping(uint256 => NFTMetadata) public nftMetadata;  // tokenId => NFTMetadata
    uint256 public totalRegisteredNFTs;
    uint256 public totalMultiplierPoints;     // Sum of all registered NFT multipliers

    // Owner → TokenIds mapping (for batch view functions)
    // Updated by server via updateOwnership() when:
    // 1. Initial batch registration of 2,341 NFTs
    // 2. New mint detected by EventListener/OwnerSync
    // 3. Transfer detected by OwnerSync (every 30 min full sync)
    mapping(address => uint256[]) public ownerTokenIds;  // owner => array of tokenIds
    mapping(uint256 => uint256) private tokenIdToOwnerIndex;  // tokenId => index in ownerTokenIds array

    // Multipliers per hostess type (index 0-7)
    uint8[8] public MULTIPLIERS = [100, 90, 80, 70, 60, 50, 40, 30];

    // Reward Tracking
    uint256 public totalRewardsReceived;       // All-time rewards received
    uint256 public totalRewardsDistributed;    // All-time rewards claimed
    uint256 public rewardsPerMultiplierPoint;  // Accumulated rewards per point (scaled by 1e18)

    // Per-NFT reward tracking (for proportional distribution)
    mapping(uint256 => uint256) public nftRewardDebt;  // tokenId => already-accounted-for rewards
    mapping(uint256 => uint256) public nftClaimedRewards;  // tokenId => total claimed by this NFT

    // Per-User aggregated tracking (by recipient address from withdrawTo calls)
    mapping(address => uint256) public userTotalClaimed;

    // NOTE: 24-hour tracking is done OFF-CHAIN
    // The server listens for RewardReceived events and calculates 24h totals from SQLite
    // This avoids unbounded array growth and expensive on-chain iteration
    // See: EarningsSyncService in high-rollers-nfts/server/services/earningsSyncService.js

    // ============ Access Control ============

    modifier onlyAdmin() {
        require(msg.sender == admin || msg.sender == owner(), "Not admin");
        _;
    }

    // ============ Events ============

    event RewardReceived(bytes32 indexed betId, uint256 amount, uint256 timestamp);
    event RewardClaimed(address indexed user, uint256 amount, uint256[] tokenIds);
    event NFTRegistered(uint256 indexed tokenId, address indexed owner, uint8 hostessIndex);
    event AdminChanged(address indexed previousAdmin, address indexed newAdmin);
    event OwnershipUpdated(uint256 indexed tokenId, address indexed oldOwner, address indexed newOwner);
}
```

### Core Functions

```solidity
// ============ Reward Receiving (Called by ROGUEBankroll) ============

/**
 * @notice Receive ROGUE rewards from ROGUEBankroll when a BuxBooster bet is lost
 * @dev Only callable by authorized ROGUEBankroll contract
 * @param betId The commitment hash of the losing bet (for event tracking)
 */
function receiveReward(bytes32 betId) external payable {
    require(msg.sender == rogueBankroll, "Only ROGUEBankroll can send rewards");
    require(msg.value > 0, "No reward sent");
    require(totalMultiplierPoints > 0, "No NFTs registered");

    // Update global reward tracking
    totalRewardsReceived += msg.value;

    // Update rewards per multiplier point (scaled by 1e18 for precision)
    rewardsPerMultiplierPoint += (msg.value * 1e18) / totalMultiplierPoints;

    // Emit event with timestamp - server uses this for 24h tracking
    // No on-chain 24h tracking to avoid unbounded array growth
    emit RewardReceived(betId, msg.value, block.timestamp);
}

// ============ Reward Claiming ============

/**
 * @notice Calculate pending rewards for a specific NFT
 * @param tokenId The NFT token ID
 * @return Pending unclaimed rewards in wei
 */
function pendingReward(uint256 tokenId) public view returns (uint256) {
    NFTMetadata storage nft = nftMetadata[tokenId];
    if (!nft.registered) return 0;

    uint256 multiplier = MULTIPLIERS[nft.hostessIndex];
    uint256 accumulatedReward = (multiplier * rewardsPerMultiplierPoint) / 1e18;

    return accumulatedReward - nftRewardDebt[tokenId];
}

// ============ Batch View Functions (for UI verification links) ============

/**
 * @notice Get all token IDs owned by an address
 * @param owner The wallet address
 * @return Array of token IDs
 */
function getOwnerTokenIds(address owner) external view returns (uint256[] memory) {
    return ownerTokenIds[owner];
}

/**
 * @notice Get aggregated earnings for a wallet (all their NFTs combined)
 * @param owner The wallet address
 * @return totalPending Total unclaimed rewards across all NFTs
 * @return totalClaimed Total ever claimed by this wallet
 * @return tokenIds Array of owned token IDs
 *
 * Users can verify this on Roguescan: getOwnerEarnings(walletAddress)
 */
function getOwnerEarnings(address owner) external view returns (
    uint256 totalPending,
    uint256 totalClaimed,
    uint256[] memory tokenIds
) {
    tokenIds = ownerTokenIds[owner];
    totalClaimed = userTotalClaimed[owner];

    for (uint256 i = 0; i < tokenIds.length; i++) {
        totalPending += pendingReward(tokenIds[i]);
    }

    return (totalPending, totalClaimed, tokenIds);
}

/**
 * @notice Get detailed earnings for multiple token IDs
 * @param tokenIds Array of token IDs to query
 * @return pending Array of pending rewards (same order as input)
 * @return claimed Array of claimed rewards (same order as input)
 * @return multipliers Array of multipliers (same order as input)
 *
 * Users can verify individual NFTs on Roguescan: getTokenEarnings([tokenId1, tokenId2])
 */
function getTokenEarnings(uint256[] calldata tokenIds) external view returns (
    uint256[] memory pending,
    uint256[] memory claimed,
    uint8[] memory multipliers
) {
    pending = new uint256[](tokenIds.length);
    claimed = new uint256[](tokenIds.length);
    multipliers = new uint8[](tokenIds.length);

    for (uint256 i = 0; i < tokenIds.length; i++) {
        uint256 tokenId = tokenIds[i];
        NFTMetadata storage nft = nftMetadata[tokenId];

        if (nft.registered) {
            pending[i] = pendingReward(tokenId);
            claimed[i] = nftClaimedRewards[tokenId];
            multipliers[i] = MULTIPLIERS[nft.hostessIndex];
        }
    }

    return (pending, claimed, multipliers);
}

// ============ Ownership Management (Server-Only) ============

/**
 * @notice Update ownership of an NFT (called by server when transfer detected)
 * @dev Maintains ownerTokenIds arrays for efficient batch queries
 * @param tokenId The NFT token ID
 * @param newOwner The new owner address
 */
function updateOwnership(uint256 tokenId, address newOwner) external onlyAdmin {
    NFTMetadata storage nft = nftMetadata[tokenId];
    require(nft.registered, "NFT not registered");

    address oldOwner = nft.owner;
    if (oldOwner == newOwner) return;  // No change

    // Remove from old owner's array (if not zero address)
    if (oldOwner != address(0)) {
        _removeFromOwnerArray(oldOwner, tokenId);
    }

    // Add to new owner's array
    tokenIdToOwnerIndex[tokenId] = ownerTokenIds[newOwner].length;
    ownerTokenIds[newOwner].push(tokenId);

    // Update NFT metadata
    nft.owner = newOwner;

    emit OwnershipUpdated(tokenId, oldOwner, newOwner);
}

/**
 * @notice Batch update ownership for multiple NFTs
 * @dev Gas efficient for initial registration and full syncs
 */
function batchUpdateOwnership(
    uint256[] calldata tokenIds,
    address[] calldata newOwners
) external onlyAdmin {
    require(tokenIds.length == newOwners.length, "Length mismatch");

    for (uint256 i = 0; i < tokenIds.length; i++) {
        NFTMetadata storage nft = nftMetadata[tokenIds[i]];
        if (!nft.registered) continue;

        address oldOwner = nft.owner;
        address newOwner = newOwners[i];

        if (oldOwner == newOwner) continue;

        // Remove from old owner's array
        if (oldOwner != address(0)) {
            _removeFromOwnerArray(oldOwner, tokenIds[i]);
        }

        // Add to new owner's array
        tokenIdToOwnerIndex[tokenIds[i]] = ownerTokenIds[newOwner].length;
        ownerTokenIds[newOwner].push(tokenIds[i]);

        // Update NFT metadata
        nft.owner = newOwner;

        emit OwnershipUpdated(tokenIds[i], oldOwner, newOwner);
    }
}

/**
 * @dev Remove tokenId from owner's array using swap-and-pop
 */
function _removeFromOwnerArray(address owner, uint256 tokenId) private {
    uint256[] storage tokens = ownerTokenIds[owner];
    uint256 index = tokenIdToOwnerIndex[tokenId];
    uint256 lastIndex = tokens.length - 1;

    if (index != lastIndex) {
        // Swap with last element
        uint256 lastTokenId = tokens[lastIndex];
        tokens[index] = lastTokenId;
        tokenIdToOwnerIndex[lastTokenId] = index;
    }

    // Remove last element
    tokens.pop();
}

// ============ NFT Registry & Ownership Verification ============

/*
 * SECURITY MODEL: Server-Verified Withdrawals
 *
 * The contract does NOT store NFT ownership on-chain. This is intentional:
 * - NFTs are on Arbitrum, rewards are on Rogue Chain (cross-chain)
 * - Storing ownership on-chain would require constant cross-chain syncing
 * - Instead, the server verifies ownership off-chain before authorizing withdrawals
 *
 * Why no public claim() function?
 * - Without on-chain ownership, anyone could call claim(tokenIds) for any NFT
 * - The contract cannot verify msg.sender owns the NFTs on Arbitrum
 * - Therefore, ALL withdrawals go through withdrawTo() which is onlyOwner (server)
 *
 * The tradeoff is trusting the server to verify ownership correctly.
 * This is acceptable because:
 * 1. Server already manages the entire high-rollers-nfts application
 * 2. OwnerSyncService queries Arbitrum NFT contract for ground truth
 * 3. Users can verify their ownership on Arbiscan independently
 * 4. Any discrepancy would be immediately visible and fixable
 */

/*
 * OWNERSHIP VERIFICATION STRATEGY
 *
 * The high-rollers-nfts app already has an OwnerSyncService that:
 * - Syncs new mints from Arbitrum every 60 seconds
 * - Does full ownership sync every 30 minutes
 * - Stores accurate owner data in SQLite `nfts` table
 * - Has syncWalletNFTs(address) for on-demand verification before withdrawal
 *
 * Withdrawal Flow:
 * 1. User clicks "Withdraw" in UI
 * 2. Server calls ownerSync.syncWalletNFTs(userAddress) to get fresh ownership from Arbitrum
 * 3. Server verifies user owns the NFTs they're claiming for (checks local DB)
 * 4. Server calls NFTRewarder.withdrawTo(tokenIds, recipient) as admin
 * 5. ROGUE is sent directly to user's wallet
 *
 * This leverages existing infrastructure without adding complexity.
 * The server is trusted to verify ownership correctly before executing withdrawals.
 *
 * See: high-rollers-nfts/server/services/ownerSync.js
 */

// NFTMetadata struct and nftMetadata mapping defined in Core State Variables above

// ============ Initialization (UUPS) ============

/**
 * @notice Initialize the contract (replaces constructor for upgradeable contracts)
 * @param _rogueBankroll Address of ROGUEBankroll that will send rewards
 * @param _admin Address of admin (server wallet for daily operations)
 */
function initialize(address _rogueBankroll, address _admin) public initializer {
    __Ownable_init(msg.sender);
    __UUPSUpgradeable_init();
    rogueBankroll = _rogueBankroll;
    admin = _admin;
}

/**
 * @notice Required by UUPS - only owner can upgrade
 */
function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

// ============ Owner-Only Functions ============

/**
 * @notice Set new admin address (owner only)
 * @param _admin New admin address
 */
function setAdmin(address _admin) external onlyOwner {
    require(_admin != address(0), "Invalid admin");
    emit AdminChanged(admin, _admin);
    admin = _admin;
}

/**
 * @notice Set ROGUEBankroll address (owner only)
 * @param _rogueBankroll New ROGUEBankroll address
 */
function setRogueBankroll(address _rogueBankroll) external onlyOwner {
    require(_rogueBankroll != address(0), "Invalid address");
    rogueBankroll = _rogueBankroll;
}

// ============ Admin Functions (Server Wallet) ============

/**
 * @notice Register NFT with metadata and owner. Only needs to be done once per NFT.
 * @dev Hostess index determines multiplier and never changes after mint
 * @param tokenId The NFT token ID
 * @param hostessIndex 0-7 index into MULTIPLIERS array
 * @param owner Current owner address (from Arbitrum contract)
 */
function registerNFT(uint256 tokenId, uint8 hostessIndex, address owner) external onlyAdmin {
    require(hostessIndex < 8, "Invalid hostess index");
    require(!nftMetadata[tokenId].registered, "Already registered");

    nftMetadata[tokenId] = NFTMetadata({
        hostessIndex: hostessIndex,
        registered: true,
        owner: owner
    });

    // Add to owner's token array
    if (owner != address(0)) {
        ownerTokenIds[owner].push(tokenId);
    }

    uint256 multiplier = MULTIPLIERS[hostessIndex];
    totalMultiplierPoints += multiplier;
    totalRegisteredNFTs++;

    // Set initial reward debt so newly registered NFT doesn't claim past rewards
    nftRewardDebt[tokenId] = (multiplier * rewardsPerMultiplierPoint) / 1e18;

    emit NFTRegistered(tokenId, owner, hostessIndex);
}

/**
 * @notice Batch register multiple NFTs with metadata and owners in a single transaction
 * @dev CRITICAL: All 2,341 existing NFTs MUST be registered BEFORE enabling rewards
 *      in ROGUEBankroll. Otherwise totalMultiplierPoints will be wrong and early
 *      reward distributions will be incorrectly proportioned.
 *
 * Recommended batch size: 100-200 NFTs per transaction to avoid gas limits
 * Total batches needed: ~12-24 transactions for 2,341 NFTs
 *
 * @param tokenIds Array of NFT token IDs
 * @param hostessIndices Array of hostess indices (0-7)
 * @param owners Array of current owner addresses (from Arbitrum contract)
 */
function batchRegisterNFTs(
    uint256[] calldata tokenIds,
    uint8[] calldata hostessIndices,
    address[] calldata owners
) external onlyAdmin {
    require(tokenIds.length == hostessIndices.length, "Length mismatch");
    require(tokenIds.length == owners.length, "Owners length mismatch");

    for (uint256 i = 0; i < tokenIds.length; i++) {
        if (!nftMetadata[tokenIds[i]].registered) {
            uint8 hostessIndex = hostessIndices[i];
            require(hostessIndex < 8, "Invalid hostess index");

            address owner = owners[i];

            nftMetadata[tokenIds[i]] = NFTMetadata({
                hostessIndex: hostessIndex,
                registered: true,
                owner: owner
            });

            // Add to owner's token array
            if (owner != address(0)) {
                ownerTokenIds[owner].push(tokenId);
            }

            uint256 multiplier = MULTIPLIERS[hostessIndex];
            totalMultiplierPoints += multiplier;
            totalRegisteredNFTs++;
            nftRewardDebt[tokenIds[i]] = (multiplier * rewardsPerMultiplierPoint) / 1e18;
        }
    }
}

/**
 * @notice Withdraw rewards to a specific address (called by server after ownership verification)
 * @dev Only callable by owner (server). Server verifies ownership via OwnerSyncService.
 * @param tokenIds Array of token IDs to claim for
 * @param recipient Address to send ROGUE to (the verified NFT owner)
 * @return amount Total ROGUE withdrawn
 */
function withdrawTo(
    uint256[] calldata tokenIds,
    address recipient
) external onlyAdmin returns (uint256 amount) {
    require(recipient != address(0), "Invalid recipient");

    for (uint256 i = 0; i < tokenIds.length; i++) {
        uint256 tokenId = tokenIds[i];
        require(nftMetadata[tokenId].registered, "NFT not registered");

        uint256 pending = pendingReward(tokenId);
        if (pending > 0) {
            // Update reward debt
            uint8 hostessIndex = nftMetadata[tokenId].hostessIndex;
            uint256 multiplier = MULTIPLIERS[hostessIndex];
            nftRewardDebt[tokenId] = (multiplier * rewardsPerMultiplierPoint) / 1e18;

            // Track claimed amounts
            nftClaimedRewards[tokenId] += pending;
            amount += pending;
        }
    }

    require(amount > 0, "No rewards to claim");

    userTotalClaimed[recipient] += amount;
    totalRewardsDistributed += amount;

    // Transfer ROGUE to recipient
    (bool sent,) = payable(recipient).call{value: amount}("");
    require(sent, "ROGUE transfer failed");

    emit RewardClaimed(recipient, amount, tokenIds);
}

// ============ View Functions for UI ============

/*
 * NOTE: 24-hour earnings and APY are calculated OFF-CHAIN
 *
 * The contract only stores totalEarned and pendingAmount.
 * The server calculates last24Hours and APY using:
 *
 * 1. Query global 24h rewards ONCE from SQLite:
 *    SELECT SUM(amount) FROM reward_events WHERE timestamp > (now - 86400)
 *
 * 2. For each NFT, calculate proportional share:
 *    nft_24h = global_24h × (nft_multiplier / totalMultiplierPoints)
 *
 * 3. Calculate APY:
 *    apy = (nft_24h × 365 / nft_value_in_rogue) × 10000
 *
 * This avoids on-chain iteration and unbounded array growth.
 * See: EarningsSyncService in high-rollers-nfts/server/services/earningsSyncService.js
 */

/**
 * @notice Get earnings data for a specific NFT (on-chain data only)
 * @param tokenId The NFT token ID
 * @return totalEarned All-time earnings for this NFT
 * @return pendingAmount Unclaimed rewards
 * @return hostessIndex The hostess type (for off-chain multiplier lookup)
 *
 * NOTE: last24HoursEarned and APY are calculated off-chain by EarningsSyncService
 */
function getNFTEarnings(uint256 tokenId) external view returns (
    uint256 totalEarned,
    uint256 pendingAmount,
    uint8 hostessIndex
) {
    NFTMetadata storage nft = nftMetadata[tokenId];
    require(nft.registered, "NFT not registered");

    totalEarned = nftClaimedRewards[tokenId] + pendingReward(tokenId);
    pendingAmount = pendingReward(tokenId);
    hostessIndex = nft.hostessIndex;
}

/**
 * @notice Get earnings for multiple NFTs in a single call (for batch sync)
 * @param tokenIds Array of token IDs to query
 * @return earnings Array of NFTEarnings structs (on-chain data only)
 *
 * Used by EarningsSyncService to efficiently sync 100 NFTs at a time.
 * The service then calculates last24h and APY off-chain using proportional distribution.
 */
struct NFTEarningsData {
    uint256 totalEarned;
    uint256 pendingAmount;
    uint8 hostessIndex;
}

function getBatchNFTEarnings(uint256[] calldata tokenIds) external view returns (
    NFTEarningsData[] memory earnings
) {
    earnings = new NFTEarningsData[](tokenIds.length);

    for (uint256 i = 0; i < tokenIds.length; i++) {
        uint256 tokenId = tokenIds[i];
        NFTMetadata storage nft = nftMetadata[tokenId];

        if (!nft.registered) continue;

        uint256 pending = pendingReward(tokenId);

        earnings[i].totalEarned = nftClaimedRewards[tokenId] + pending;
        earnings[i].pendingAmount = pending;
        earnings[i].hostessIndex = nft.hostessIndex;
    }
}

/**
 * @notice Get aggregated earnings for all NFTs owned by an address
 * @param user The wallet address
 *
 * NOTE: last24HoursEarned, apyBasisPoints are calculated off-chain by the server
 * This function only returns on-chain data (totalEarned, pendingAmount)
 */
function getUserEarnings(address user) external view returns (
    uint256 totalEarned,
    uint256 pendingAmount,
    uint256 ownedNFTCount,
    uint256 totalMultiplierOwned
) {
    // Implementation: aggregate across all NFTs owned by user
    // Server adds last24h and APY calculations off-chain
}

/**
 * @notice Get global statistics for display (on-chain data only)
 *
 * NOTE: last24Hours and overallAPY are calculated off-chain from reward_events table
 * This function only returns on-chain totals
 */
function getGlobalStats() external view returns (
    uint256 totalRewards,
    uint256 totalDistributed,
    uint256 totalPending,
    uint256 registeredNFTs,
    uint256 totalPoints
) {
    totalRewards = totalRewardsReceived;
    totalDistributed = totalRewardsDistributed;
    totalPending = address(this).balance;
    registeredNFTs = totalRegisteredNFTs;
    totalPoints = totalMultiplierPoints;
    // last24Hours and overallAPY calculated off-chain by EarningsSyncService
}

/**
 * @notice Get per-hostess-type statistics (on-chain data only)
 * @param hostessIndex The hostess type (0-7)
 *
 * NOTE: last24HoursEarningsPerNFT and apyBasisPoints are calculated off-chain
 */
function getHostessTypeStats(uint8 hostessIndex) external view returns (
    uint256 nftCount,
    uint256 multiplier,
    uint256 totalPointsForType,
    uint256 shareOfRewardsBasisPoints
) {
    // Implementation: calculate stats for specific hostess type
    // Server adds last24h and APY calculations off-chain
}
```

---

## ROGUEBankroll.sol Modifications (V7 Upgrade)

### Storage Layout Preservation (CRITICAL for Proxy Upgradeability)

**IMPORTANT**: ROGUEBankroll uses UUPS proxy pattern. New state variables MUST be appended at the END of existing state variables to preserve storage slots.

Current state variable order (as of V6):
```solidity
// Existing state variables in ROGUEBankroll.sol (DO NOT MODIFY ORDER)
HouseBalance houseBalance;                                    // slot X
mapping(address => Player) players;                           // slot X+1
address rogueTrader;                                          // slot X+2
uint256 minimumBetSize;                                       // slot X+3
uint256 maximumBetSizeDivisor;                                // slot X+4
address public nftRoguePayer;                                 // slot X+5
address public rogueBotsBetSettler;                           // slot X+6
address public buxBoosterGame;                                // slot X+7
mapping(address => BuxBoosterPlayerStats) public buxBoosterPlayerStats;  // slot X+8
BuxBoosterAccounting public buxBoosterAccounting;             // slot X+9

// ===============================================================
// V7 NFT Revenue Sharing - APPEND AFTER buxBoosterAccounting
// ===============================================================
address public nftRewarder;                                   // slot X+10 (NEW)
uint256 public nftRewardBasisPoints;                          // slot X+11 (NEW)
```

**Rules for Proxy Upgradeability:**
1. NEVER delete existing state variables
2. NEVER reorder existing state variables
3. ONLY append new variables at the END
4. See `docs/contract_upgrades.md` for detailed upgrade process

### Changes to `settleBuxBoosterLosingBet()`

```solidity
// V7: Add state variables (MUST be appended after buxBoosterAccounting)
address public nftRewarder;  // NFTRewarder contract address
uint256 public nftRewardBasisPoints = 20;  // 0.20% of wager (20 basis points = 20% of 1% edge)

// Add setter function
function setNFTRewarder(address _nftRewarder) external onlyOwner {
    nftRewarder = _nftRewarder;
}

function setNFTRewardBasisPoints(uint256 _bps) external onlyOwner {
    require(_bps <= 100, "Max 1% of wager");
    nftRewardBasisPoints = _bps;
}

// Modify settleBuxBoosterLosingBet to send NFT rewards
function settleBuxBoosterLosingBet(
    address player,
    bytes32 commitmentHash,
    uint256 wagerAmount,
    int8 difficulty,
    uint8[] calldata predictions,
    uint8[] calldata results,
    uint256 nonce,
    uint256 maxPayout
) external onlyBuxBooster returns(bool) {
    // ... existing house balance updates ...

    // Calculate NFT reward (20% of 1% house edge = 0.2% of wager)
    uint256 nftReward = (wagerAmount * nftRewardBasisPoints) / 10000;

    // Send to NFTRewarder contract
    if (nftRewarder != address(0) && nftReward > 0) {
        try INFTRewarder(nftRewarder).receiveReward{value: nftReward}(commitmentHash) {
            totalNFTRewardsPaid += nftReward;  // Standalone variable (NOT struct field!)
            emit NFTRewardSent(commitmentHash, nftReward);
        } catch {
            totalNFTRewardsFailed += nftReward;
            emit NFTRewardFailed(commitmentHash, nftReward);
            // Don't revert - losing bet settlement should still succeed
        }
    }

    // ... rest of existing function ...
}

// Add new events
event NFTRewardSent(bytes32 indexed commitmentHash, uint256 amount);
event NFTRewardFailed(bytes32 indexed commitmentHash, uint256 amount);
```

### NFT Reward Tracking (Standalone Variables)

**IMPORTANT**: Do NOT modify the existing `BuxBoosterAccounting` struct. Adding fields to an existing struct breaks storage layout because struct fields are packed into consecutive slots.

Instead, add standalone state variables after all existing state:

```solidity
// Existing state (DO NOT MODIFY ORDER OR STRUCTURE)
BuxBoosterAccounting public buxBoosterAccounting;  // slot X+9

// V7 additions - MUST be appended AFTER buxBoosterAccounting
address public nftRewarder;                        // slot X+10
uint256 public nftRewardBasisPoints;               // slot X+11
uint256 public totalNFTRewardsPaid;                // slot X+12 (standalone counter)
uint256 public totalNFTRewardsFailed;              // slot X+13 (for failed sends)

/**
 * @notice Get all NFT reward statistics in one call
 * @return rewarder Address of NFTRewarder contract
 * @return basisPoints Current reward rate (20 = 0.20% of wager)
 * @return totalPaid Total ROGUE successfully sent to NFTRewarder
 * @return totalFailed Total ROGUE that failed to send (contract call reverted)
 */
function getNFTRewardStats() external view returns (
    address rewarder,
    uint256 basisPoints,
    uint256 totalPaid,
    uint256 totalFailed
) {
    return (nftRewarder, nftRewardBasisPoints, totalNFTRewardsPaid, totalNFTRewardsFailed);
}
```

Usage in `settleBuxBoosterLosingBet()`:
```solidity
if (nftRewarder != address(0) && nftReward > 0) {
    try INFTRewarder(nftRewarder).receiveReward{value: nftReward}(commitmentHash) {
        totalNFTRewardsPaid += nftReward;  // Standalone variable, not struct field
        emit NFTRewardSent(commitmentHash, nftReward);
    } catch {
        totalNFTRewardsFailed += nftReward;
        emit NFTRewardFailed(commitmentHash, nftReward);
    }
}
```

**Why not modify the struct?**
- `BuxBoosterAccounting` is stored as a single state variable (not a mapping)
- Its 8 uint256 fields occupy slots X+9.0 through X+9.7
- Adding a 9th field would shift `nftRewarder` (slot X+10) to X+11, corrupting storage
- Standalone variables avoid this problem entirely

---

## high-rollers-nfts App Changes

### New Database Schema

#### Stats Table for Cached Metrics

The app needs to efficiently track total multiplier points without repeatedly querying all NFTs. Following the existing `hostess_counts` pattern, we add a `stats` table for O(1) lookups:

```sql
-- Global stats cache (key-value store for computed values)
CREATE TABLE IF NOT EXISTS stats (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at INTEGER DEFAULT (strftime('%s', 'now'))
);

-- Initialize with default values
INSERT OR IGNORE INTO stats (key, value) VALUES ('total_multiplier_points', '0');
INSERT OR IGNORE INTO stats (key, value) VALUES ('total_nfts_registered', '0');
```

**Database Methods for Stats:**

```javascript
// server/services/database.js - Add these methods

// Get a stat value
getStat(key) {
  const result = this.db.prepare('SELECT value FROM stats WHERE key = ?').get(key);
  return result?.value || null;
}

// Set a stat value
setStat(key, value) {
  this.db.prepare(`
    INSERT OR REPLACE INTO stats (key, value, updated_at)
    VALUES (?, ?, strftime('%s', 'now'))
  `).run(key, value.toString());
}

// Increment multiplier points when NFT is registered
incrementMultiplierPoints(multiplier) {
  const current = parseInt(this.getStat('total_multiplier_points') || '0');
  this.setStat('total_multiplier_points', current + multiplier);
}

// Decrement multiplier points when NFT is unregistered
decrementMultiplierPoints(multiplier) {
  const current = parseInt(this.getStat('total_multiplier_points') || '0');
  this.setStat('total_multiplier_points', Math.max(0, current - multiplier));
}

// Get total multiplier points (O(1) lookup)
getTotalMultiplierPoints() {
  return parseInt(this.getStat('total_multiplier_points') || '0');
}

// Recalculate from scratch if cache gets out of sync
recalculateMultiplierPoints() {
  const MULTIPLIERS = [100, 90, 80, 70, 60, 50, 40, 30]; // hostess 0-7
  const counts = this.getAllHostessCounts();

  let total = 0;
  for (let i = 0; i < 8; i++) {
    total += (counts[i] || 0) * MULTIPLIERS[i];
  }

  this.setStat('total_multiplier_points', total);
  console.log(`[Database] Recalculated total_multiplier_points: ${total}`);
  return total;
}
```

**Usage in NFT Registration:**

```javascript
// In eventListener.js or nftRegistrySync.js when an NFT is registered

const MULTIPLIERS = [100, 90, 80, 70, 60, 50, 40, 30];

function registerNFT(tokenId, owner, hostessIndex) {
  // Insert NFT record
  db.insertNFT({ tokenId, owner, hostessIndex, ... });

  // Update cached counts (O(1) operations)
  db.incrementHostessCount(hostessIndex);
  db.incrementMultiplierPoints(MULTIPLIERS[hostessIndex]);

  console.log(`[NFT] Registered #${tokenId} - Total multiplier points: ${db.getTotalMultiplierPoints()}`);
}
```

**Startup Validation:**

```javascript
// On server startup, validate cache integrity
function validateCaches() {
  const cachedTotal = db.getTotalMultiplierPoints();
  const calculatedTotal = db.recalculateMultiplierPoints();

  if (cachedTotal !== calculatedTotal) {
    console.warn(`[Cache] Multiplier points mismatch: cached=${cachedTotal}, actual=${calculatedTotal}. Cache updated.`);
  }
}
```

#### NFT Earnings Tables

```sql
-- NFT earnings tracking (synced from blockchain)
CREATE TABLE nft_earnings (
    token_id INTEGER PRIMARY KEY,
    owner TEXT NOT NULL,
    hostess_index INTEGER NOT NULL,
    total_earned TEXT DEFAULT '0',           -- All-time earnings in wei
    pending_amount TEXT DEFAULT '0',         -- Current unclaimed balance
    last_24h_earned TEXT DEFAULT '0',        -- Rolling 24h earnings (calculated off-chain)
    apy_basis_points INTEGER DEFAULT 0,      -- Current APY (calculated off-chain)
    last_synced INTEGER DEFAULT 0            -- Timestamp of last sync
);

-- Reward events (for real-time updates and history)
-- This table is used to calculate global 24h rewards off-chain
CREATE TABLE reward_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    commitment_hash TEXT NOT NULL,
    amount TEXT NOT NULL,                     -- ROGUE amount in wei
    timestamp INTEGER NOT NULL,
    block_number INTEGER,
    tx_hash TEXT
);

-- Index for efficient 24h queries (critical for off-chain calculation)
CREATE INDEX IF NOT EXISTS idx_reward_events_timestamp ON reward_events(timestamp DESC);

-- Withdrawal history
CREATE TABLE withdrawals (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_address TEXT NOT NULL,
    amount TEXT NOT NULL,
    token_ids TEXT NOT NULL,                  -- JSON array of token IDs
    tx_hash TEXT NOT NULL,
    timestamp INTEGER NOT NULL
);

-- Global stats cache
CREATE TABLE global_stats (
    id INTEGER PRIMARY KEY DEFAULT 1,
    total_rewards_received TEXT DEFAULT '0',
    total_rewards_distributed TEXT DEFAULT '0',
    rewards_last_24h TEXT DEFAULT '0',        -- Calculated off-chain from reward_events
    overall_apy_basis_points INTEGER DEFAULT 0,
    last_updated INTEGER DEFAULT 0
);

-- Per-hostess stats cache
CREATE TABLE hostess_stats (
    hostess_index INTEGER PRIMARY KEY,
    nft_count INTEGER DEFAULT 0,
    total_points INTEGER DEFAULT 0,
    share_basis_points INTEGER DEFAULT 0,
    last_24h_per_nft TEXT DEFAULT '0',
    apy_basis_points INTEGER DEFAULT 0,
    last_updated INTEGER DEFAULT 0
);
```

#### Database Methods for Off-Chain 24h Calculation

```javascript
// server/services/database.js - Add these methods for 24h reward tracking

/**
 * Get total rewards received since a specific timestamp
 * Used to calculate global 24h rewards for proportional distribution
 *
 * @param {number} sinceTimestamp - Unix timestamp (seconds)
 * @returns {string} Total rewards in wei
 */
getRewardsSince(sinceTimestamp) {
  const result = this.db.prepare(`
    SELECT COALESCE(SUM(CAST(amount AS INTEGER)), 0) as total
    FROM reward_events
    WHERE timestamp >= ?
  `).get(sinceTimestamp);
  return result?.total?.toString() || '0';
}

/**
 * Insert a new reward event (called by RewardEventListener when RewardReceived emitted)
 */
insertRewardEvent(data) {
  const stmt = this.db.prepare(`
    INSERT INTO reward_events (commitment_hash, amount, timestamp, block_number, tx_hash)
    VALUES (?, ?, ?, ?, ?)
  `);
  return stmt.run(
    data.commitmentHash,
    data.amount,
    data.timestamp,
    data.blockNumber,
    data.txHash
  );
}

/**
 * Get recent reward events for display
 */
getRewardEvents(limit = 50, offset = 0) {
  return this.db.prepare(`
    SELECT * FROM reward_events ORDER BY timestamp DESC LIMIT ? OFFSET ?
  `).all(limit, offset);
}

/**
 * Update NFT earnings (called by EarningsSyncService)
 */
updateNFTEarnings(tokenId, data) {
  const stmt = this.db.prepare(`
    INSERT INTO nft_earnings (token_id, owner, hostess_index, total_earned, pending_amount, last_24h_earned, apy_basis_points, last_synced)
    VALUES (?, '', 0, ?, ?, ?, ?, strftime('%s', 'now'))
    ON CONFLICT(token_id) DO UPDATE SET
      total_earned = excluded.total_earned,
      pending_amount = excluded.pending_amount,
      last_24h_earned = excluded.last_24h_earned,
      apy_basis_points = excluded.apy_basis_points,
      last_synced = strftime('%s', 'now')
  `);
  return stmt.run(
    tokenId,
    data.totalEarned,
    data.pendingAmount,
    data.last24hEarned,
    data.apyBasisPoints
  );
}
```

### New API Endpoints

```javascript
// server/routes/revenues.js

// GET /api/revenues/stats - Global revenue statistics
router.get('/stats', async (req, res) => {
  const stats = db.getGlobalStats();
  const hostessStats = db.getAllHostessStats();

  res.json({
    totalRewardsReceived: formatROGUE(stats.total_rewards_received),
    totalRewardsDistributed: formatROGUE(stats.total_rewards_distributed),
    totalPending: formatROGUE(stats.total_pending),
    rewardsLast24Hours: formatROGUE(stats.rewards_last_24h),
    overallAPY: stats.overall_apy_basis_points / 100, // Convert to percentage
    hostessTypes: hostessStats.map(h => ({
      name: HOSTESSES[h.hostess_index].name,
      multiplier: HOSTESSES[h.hostess_index].multiplier,
      nftCount: h.nft_count,
      sharePercent: h.share_basis_points / 100,
      last24HPerNFT: formatROGUE(h.last_24h_per_nft),
      apy: h.apy_basis_points / 100
    })),
    lastUpdated: stats.last_updated
  });
});

// GET /api/revenues/nft/:tokenId - Earnings for specific NFT
router.get('/nft/:tokenId', async (req, res) => {
  const { tokenId } = req.params;
  const nftEarnings = db.getNFTEarnings(tokenId);

  if (!nftEarnings) {
    return res.status(404).json({ error: 'NFT not found' });
  }

  res.json({
    tokenId,
    hostessName: HOSTESSES[nftEarnings.hostess_index].name,
    multiplier: HOSTESSES[nftEarnings.hostess_index].multiplier,
    totalEarned: formatROGUE(nftEarnings.total_earned),
    pendingAmount: formatROGUE(nftEarnings.pending_amount),
    last24Hours: formatROGUE(nftEarnings.last_24h_earned),
    apy: nftEarnings.apy_basis_points / 100,
    owner: nftEarnings.owner
  });
});

// GET /api/revenues/user/:address - All earnings for a user's NFTs
router.get('/user/:address', async (req, res) => {
  const { address } = req.params;
  const userNFTs = db.getNFTsOwnedBy(address);

  let totalEarned = 0n;
  let totalPending = 0n;
  let totalLast24h = 0n;
  let totalMultiplier = 0;

  const nfts = userNFTs.map(nft => {
    totalEarned += BigInt(nft.total_earned);
    totalPending += BigInt(nft.pending_amount);
    totalLast24h += BigInt(nft.last_24h_earned);
    totalMultiplier += HOSTESSES[nft.hostess_index].multiplier;

    return {
      tokenId: nft.token_id,
      hostessName: HOSTESSES[nft.hostess_index].name,
      multiplier: HOSTESSES[nft.hostess_index].multiplier,
      totalEarned: formatROGUE(nft.total_earned),
      pendingAmount: formatROGUE(nft.pending_amount),
      last24Hours: formatROGUE(nft.last_24h_earned),
      apy: nft.apy_basis_points / 100
    };
  });

  // Calculate overall APY for this user's portfolio
  const overallAPY = calculatePortfolioAPY(nfts);

  res.json({
    address,
    nftCount: nfts.length,
    totalMultiplier,
    totalEarned: formatROGUE(totalEarned.toString()),
    totalPending: formatROGUE(totalPending.toString()),
    totalLast24Hours: formatROGUE(totalLast24h.toString()),
    overallAPY,
    nfts,
    canWithdraw: totalPending > 0n
  });
});

// GET /api/revenues/history - Recent reward events
router.get('/history', async (req, res) => {
  const { limit = 50, offset = 0 } = req.query;
  const events = db.getRewardEvents(limit, offset);

  res.json({
    events: events.map(e => ({
      commitmentHash: e.commitment_hash,
      amount: formatROGUE(e.amount),
      timestamp: e.timestamp,
      txHash: e.tx_hash
    })),
    total: db.getRewardEventCount()
  });
});
```

### NFT Registration Strategy

**Two existing services + reconciliation = triple redundancy:**

| Service | Frequency | Role | If Already Registered |
|---------|-----------|------|----------------------|
| **EventListener** | ~30s | Primary - fastest detection via `NFTMinted` event | Silently fails ("Already registered") |
| **OwnerSyncService** | ~60s | Backup - catches missed events | Silently fails ("Already registered") |
| **Reconciliation** | 5 min | Safety net - batch registers any missing | `batchRegisterNFTs()` skips registered |

**Why this is safe:** The contract prevents double-adds:
```solidity
function registerNFT(uint256 tokenId, uint8 hostessIndex) external onlyAdmin {
    require(!nftMetadata[tokenId].registered, "Already registered");  // ← Idempotent
}
```

#### Changes to eventListener.js (Primary - Fastest)

```javascript
// server/services/eventListener.js - ADD NFTRewarder registration

class EventListener {
  constructor(contractService, database, websocketServer) {
    // ... existing constructor ...

    // NEW: NFTRewarder contract on Rogue Chain (only if configured)
    if (config.NFT_REWARDER_ADDRESS && config.ROGUE_RPC_URL) {
      this.rogueProvider = new ethers.JsonRpcProvider(config.ROGUE_RPC_URL);
      this.rewarderContract = new ethers.Contract(
        config.NFT_REWARDER_ADDRESS,
        ['function registerNFT(uint256 tokenId, uint8 hostessIndex) external'],
        this.rogueProvider
      );
      this.rewarderEnabled = true;
      console.log('[EventListener] NFTRewarder integration enabled');
    }
  }

  handleMintComplete(requestId, recipient, price, tokenId, hostess, affiliate, affiliate2, event) {
    // ... existing handleMintComplete code ...

    // NEW: Register in NFTRewarder contract (primary path - ~30s after mint)
    if (this.rewarderEnabled) {
      this.registerNFTInRewarder(Number(tokenId), Number(hostess));
    }
  }

  /**
   * Register NFT in NFTRewarder contract on Rogue Chain
   * Called from handleMintComplete - fastest path (~30s after mint)
   */
  async registerNFTInRewarder(tokenId, hostessIndex) {
    if (!this.rewarderEnabled) return;

    try {
      const wallet = new ethers.Wallet(config.ADMIN_PRIVATE_KEY, this.rogueProvider);
      const rewarderWithSigner = this.rewarderContract.connect(wallet);

      const tx = await rewarderWithSigner.registerNFT(tokenId, hostessIndex);
      await tx.wait();

      console.log(`[EventListener] Registered NFT ${tokenId} in NFTRewarder: ${tx.hash}`);
    } catch (error) {
      // "Already registered" is expected if OwnerSync or reconciliation beat us
      if (!error.message?.includes('Already registered')) {
        console.error(`[EventListener] Failed to register NFT ${tokenId}:`, error.message);
      }
    }
  }
}
```

#### Changes to ownerSync.js (Backup + Reconciliation)

```javascript
// server/services/ownerSync.js - MODIFICATIONS FOR NFT REVENUE SHARING

const { ethers } = require('ethers');
const config = require('../config');

class OwnerSyncService {
  constructor(db, contractService) {
    this.db = db;
    this.contractService = contractService;
    this.isRunning = false;
    this.lastSyncedTokenId = 0;
    this.isSyncing = false;

    // NEW: NFTRewarder contract on Rogue Chain (only if configured)
    if (config.NFT_REWARDER_ADDRESS && config.ROGUE_RPC_URL) {
      this.rogueProvider = new ethers.JsonRpcProvider(config.ROGUE_RPC_URL);
      this.rewarderContract = new ethers.Contract(
        config.NFT_REWARDER_ADDRESS,
        ['function registerNFT(uint256 tokenId, uint8 hostessIndex) external',
         'function batchRegisterNFTs(uint256[] calldata tokenIds, uint8[] calldata hostessIndices) external',
         'function nftMetadata(uint256 tokenId) view returns (uint8 hostessIndex, bool registered)',
         'function totalRegisteredNFTs() view returns (uint256)'],
        this.rogueProvider
      );
      this.rewarderEnabled = true;
      console.log('[OwnerSync] NFTRewarder integration enabled');
    } else {
      this.rewarderEnabled = false;
    }
  }

  async start() {
    // ... existing start() code ...

    // NEW: Start reconciliation loop (every 5 minutes)
    if (this.rewarderEnabled) {
      this.reconcileInterval = setInterval(() => {
        this.reconcileNFTRewarder();
      }, 5 * 60 * 1000);

      // Run initial reconciliation after 30 seconds
      setTimeout(() => this.reconcileNFTRewarder(), 30000);
    }
  }

  /**
   * Quick sync: Only check for new mints since last check
   * Runs every 60 seconds
   * MODIFIED: Also registers new NFTs in NFTRewarder contract
   */
  async syncRecentMints() {
    try {
      const totalSupply = await this.contractService.getTotalSupply();
      const total = Number(totalSupply);

      if (total > this.lastSyncedTokenId) {
        console.log(`[OwnerSync] New mints detected: ${this.lastSyncedTokenId} -> ${total}`);

        for (let tokenId = this.lastSyncedTokenId + 1; tokenId <= total; tokenId++) {
          try {
            const owner = await this.contractService.getOwnerOf(tokenId);
            const hostessIndex = await this.contractService.getHostessIndex(tokenId);
            const hostessData = config.HOSTESSES[Number(hostessIndex)];

            if (owner) {
              // Existing: Update SQLite
              this.db.upsertNFT({
                tokenId,
                owner,
                hostessIndex: Number(hostessIndex),
                hostessName: hostessData?.name || 'Unknown'
              });

              // Also add to sales if not exists
              if (!this.db.saleExistsForToken(tokenId)) {
                this.db.insertSale({ /* ... existing code ... */ });
                this.db.incrementHostessCount(Number(hostessIndex));
              }

              // NEW: Register in NFTRewarder contract on Rogue Chain
              if (this.rewarderEnabled) {
                await this.registerNFTInRewarder(tokenId, Number(hostessIndex));
              }
            }

            await this.sleep(1000);
          } catch (error) {
            console.error(`[OwnerSync] Failed to sync token ${tokenId}:`, error.message);
          }
        }

        this.lastSyncedTokenId = total;
      }
    } catch (error) {
      if (!error.message?.includes('rate limit')) {
        console.error('[OwnerSync] Quick sync failed:', error.message);
      }
    }
  }

  /**
   * NEW: Register a single NFT in the NFTRewarder contract
   */
  async registerNFTInRewarder(tokenId, hostessIndex) {
    if (!this.rewarderEnabled) return;

    try {
      const wallet = new ethers.Wallet(config.ADMIN_PRIVATE_KEY, this.rogueProvider);
      const rewarderWithSigner = this.rewarderContract.connect(wallet);

      const tx = await rewarderWithSigner.registerNFT(tokenId, hostessIndex);
      await tx.wait();

      console.log(`[OwnerSync] Registered NFT ${tokenId} in NFTRewarder: ${tx.hash}`);
    } catch (error) {
      // "Already registered" is expected if reconciliation beat us to it
      if (!error.message?.includes('Already registered')) {
        console.error(`[OwnerSync] Failed to register NFT ${tokenId} in rewarder:`, error.message);
      }
    }
  }

  /**
   * NEW: Reconciliation - catch any NFTs that were missed
   * Runs every 5 minutes
   *
   * Safety: batchRegisterNFTs() silently skips already-registered NFTs
   * No risk of double-adding multiplier points
   */
  async reconcileNFTRewarder() {
    if (!this.rewarderEnabled || this.isSyncing) return;

    try {
      // Get total from Arbitrum
      const arbitrumTotal = await this.contractService.getTotalSupply();

      // Get registered count from NFTRewarder
      const rewarderTotal = await this.rewarderContract.totalRegisteredNFTs();

      if (Number(arbitrumTotal) === Number(rewarderTotal)) {
        console.log(`[OwnerSync] NFTRewarder reconciliation OK: ${arbitrumTotal} NFTs`);
        return;
      }

      console.log(`[OwnerSync] NFTRewarder MISMATCH: Arbitrum=${arbitrumTotal}, Rewarder=${rewarderTotal}`);

      // Find unregistered NFTs
      const missingNFTs = [];
      for (let tokenId = 1; tokenId <= Number(arbitrumTotal); tokenId++) {
        const metadata = await this.rewarderContract.nftMetadata(tokenId);
        if (!metadata.registered) {
          const hostessIndex = await this.contractService.getHostessIndex(tokenId);
          missingNFTs.push({ tokenId, hostessIndex: Number(hostessIndex) });
        }
      }

      if (missingNFTs.length === 0) {
        console.log(`[OwnerSync] No missing NFTs found`);
        return;
      }

      console.log(`[OwnerSync] Registering ${missingNFTs.length} missing NFTs`);

      // Batch register (100 at a time)
      const wallet = new ethers.Wallet(config.ADMIN_PRIVATE_KEY, this.rogueProvider);
      const rewarderWithSigner = this.rewarderContract.connect(wallet);

      const BATCH_SIZE = 100;
      for (let i = 0; i < missingNFTs.length; i += BATCH_SIZE) {
        const batch = missingNFTs.slice(i, i + BATCH_SIZE);
        const tokenIds = batch.map(n => n.tokenId);
        const hostessIndices = batch.map(n => n.hostessIndex);

        const tx = await rewarderWithSigner.batchRegisterNFTs(tokenIds, hostessIndices);
        await tx.wait();

        console.log(`[OwnerSync] Batch registered ${batch.length} NFTs: ${tx.hash}`);
      }

      const finalTotal = await this.rewarderContract.totalRegisteredNFTs();
      console.log(`[OwnerSync] Reconciliation complete: ${finalTotal} NFTs registered`);

    } catch (error) {
      console.error('[OwnerSync] NFTRewarder reconciliation failed:', error.message);
    }
  }

  stop() {
    this.isRunning = false;
    if (this.fullSyncInterval) clearInterval(this.fullSyncInterval);
    if (this.quickSyncInterval) clearInterval(this.quickSyncInterval);
    if (this.reconcileInterval) clearInterval(this.reconcileInterval);  // NEW
    console.log('[OwnerSync] Stopped');
  }
}
```

#### New Config Variables (config.js)

```javascript
// Add to server/config.js
module.exports = {
  // ... existing config ...

  // NFT Revenue Sharing (Rogue Chain)
  ROGUE_RPC_URL: process.env.ROGUE_RPC_URL || 'https://rpc.roguechain.io/rpc',
  NFT_REWARDER_ADDRESS: process.env.NFT_REWARDER_ADDRESS,  // Set after deployment
  ADMIN_PRIVATE_KEY: process.env.ADMIN_PRIVATE_KEY,       // For signing register txs
};
```

**Key Benefits of This Approach:**
1. **Triple redundancy** - EventListener (primary), OwnerSync (backup), Reconciliation (safety net)
2. **Fast registration** - EventListener registers ~30s after mint (vs 60s with OwnerSync alone)
3. **Backwards compatible** - If `NFT_REWARDER_ADDRESS` not set, existing behavior unchanged
4. **Idempotent** - Contract's `registerNFT()` reverts with "Already registered" - no double-adds possible
5. **No race conditions** - Contract handles concurrency, services can safely overlap

---

### Service Health Monitoring

Standard Node.js pattern for container platforms (Fly.io): services report health via heartbeats, container orchestrator handles restarts.

#### 1. Heartbeat Tracking in Services

```javascript
// eventListener.js - Add heartbeat tracking

class EventListener {
  constructor(...) {
    // ...existing code...
    this.lastHeartbeat = Date.now();  // Track last successful operation
  }

  startEventPolling() {
    this.pollInterval = setInterval(async () => {
      try {
        const currentBlock = await this.provider.getBlockNumber();

        // Update heartbeat on successful poll
        this.lastHeartbeat = Date.now();

        // ...existing polling code...

      } catch (error) {
        // Log but DON'T rethrow - keeps interval running
        if (!error.message?.includes('rate limit')) {
          console.error('[EventListener] Polling error:', error.message);
        }
      }
    }, this.pollIntervalMs);
  }
}
```

```javascript
// ownerSync.js - Add heartbeat tracking

class OwnerSyncService {
  constructor(...) {
    // ...existing code...
    this.lastHeartbeat = Date.now();
  }

  async syncRecentMints() {
    try {
      const totalSupply = await this.contractService.getTotalSupply();

      // Update heartbeat on successful sync
      this.lastHeartbeat = Date.now();

      // ...existing code...

    } catch (error) {
      // Log but DON'T rethrow - keeps interval running
      if (!error.message?.includes('rate limit')) {
        console.error('[OwnerSync] Quick sync failed:', error.message);
      }
    }
  }
}
```

#### 2. Two-Layer Health System

We need **both** internal watchdog AND Fly.io health checks because they catch different failures:

| Layer | What it catches | Example | Response |
|-------|-----------------|---------|----------|
| **Internal Watchdog** | Silent interval death | `setInterval` stops due to unhandled promise | Restart specific interval |
| **Fly.io Health Check** | Process crash | Out of memory, uncaught exception | Restart entire container |

##### Layer 1: Internal Watchdog (Self-Healing)

```javascript
// services/serviceWatchdog.js
//
// Monitors services and restarts their intervals if heartbeat goes stale

class ServiceWatchdog {
  constructor() {
    this.services = new Map();  // name → { service, maxStaleMs, restartFn }
  }

  register(name, service, maxStaleMs, restartFn) {
    this.services.set(name, { service, maxStaleMs, restartFn });
  }

  start() {
    // Check all services every 30 seconds
    this.watchInterval = setInterval(() => {
      const now = Date.now();

      for (const [name, { service, maxStaleMs, restartFn }] of this.services) {
        const staleTime = now - (service.lastHeartbeat || 0);

        if (staleTime > maxStaleMs) {
          console.warn(`[Watchdog] ${name} is stale (${Math.round(staleTime/1000)}s), restarting...`);
          try {
            restartFn();
            console.log(`[Watchdog] ${name} restarted successfully`);
          } catch (error) {
            console.error(`[Watchdog] Failed to restart ${name}:`, error.message);
          }
        }
      }
    }, 30000);
  }

  stop() {
    if (this.watchInterval) clearInterval(this.watchInterval);
  }
}
```

**Registration in index.js:**

```javascript
const watchdog = new ServiceWatchdog();

// Fast services (threshold = 2-3x interval)
watchdog.register('eventListener', eventListener, 90000, () => {       // 30s interval → 90s threshold
  eventListener.stop();
  eventListener.start();
});
watchdog.register('rewardListener', rewardEventListener, 60000, () => { // 10s interval → 60s threshold
  rewardEventListener.stop();
  rewardEventListener.start();
});
watchdog.register('ownerSyncQuick', ownerSync, 180000, () => {          // 60s interval → 180s threshold
  clearInterval(ownerSync.quickSyncInterval);
  ownerSync.quickSyncInterval = setInterval(() => ownerSync.syncRecentMints(), 60000);
});

// Slow services (threshold = 2x interval)
watchdog.register('reconciliation', eventListener, 720000, () => {      // 5min interval → 12min threshold
  clearInterval(eventListener.reconciliationInterval);
  eventListener.startReconciliation();
});
watchdog.register('ownerSyncFull', ownerSync, 3600000, () => {          // 30min interval → 60min threshold
  clearInterval(ownerSync.fullSyncInterval);
  ownerSync.fullSyncInterval = setInterval(() => ownerSync.syncAllOwners(), 30 * 60 * 1000);
});

watchdog.start();
```

##### Layer 2: Fly.io Health Check (Process Crash Recovery)

```javascript
// routes/api.js

router.get('/health', (req, res) => {
  const now = Date.now();

  // Report all service heartbeats for monitoring
  const services = {
    eventListener: Math.round((now - (eventListener.lastHeartbeat || 0)) / 1000) + 's ago',
    ownerSyncQuick: Math.round((now - (ownerSync.lastQuickHeartbeat || 0)) / 1000) + 's ago',
    rewardListener: Math.round((now - (rewardEventListener.lastHeartbeat || 0)) / 1000) + 's ago',
    reconciliation: Math.round((now - (eventListener.lastReconciliationHeartbeat || 0)) / 1000) + 's ago',
    ownerSyncFull: Math.round((now - (ownerSync.lastFullHeartbeat || 0)) / 1000) + 's ago'
  };

  // Only return 503 if internal watchdog also failed (all services dead >15 min)
  // This means the watchdog itself is broken - need full container restart
  const watchdogFailed = Object.keys(services).every(name => {
    const staleMs = now - (services[name].lastHeartbeat || 0);
    return staleMs > 900000;  // 15 minutes
  });

  res.status(watchdogFailed ? 503 : 200).json({
    status: watchdogFailed ? 'unhealthy' : 'healthy',
    services,
    watchdog: 'running',
    uptime: process.uptime()
  });
});
```

##### Fly.io Configuration

```toml
# fly.toml

[[services.http_checks]]
  interval = "60s"
  timeout = "10s"
  grace_period = "120s"
  method = "GET"
  path = "/api/health"
```

**Service Intervals vs Watchdog Thresholds:**

| Service | Interval | Watchdog Threshold | Watchdog Restarts? |
|---------|----------|--------------------|--------------------|
| RewardEventListener | 10s | 60s | ✅ Yes |
| EventListener | 30s | 90s | ✅ Yes |
| OwnerSync Quick | 60s | 180s | ✅ Yes |
| Reconciliation | 5 min | 12 min | ✅ Yes |
| OwnerSync Full | 30 min | 60 min | ✅ Yes |

**How it all works together:**
1. Services update `lastHeartbeat` on every successful poll
2. Internal watchdog checks heartbeats every 30s → restarts stale intervals
3. Fly.io checks `/api/health` every 60s → restarts container only if watchdog also failed
4. Result: Self-healing for interval failures, container restart for process crashes

**Why try-catch is critical:**
```javascript
// WITHOUT try-catch: one error kills the interval forever
setInterval(async () => {
  await riskyOperation();  // If this throws, interval stops silently
}, 30000);

// WITH try-catch: interval keeps running despite errors
setInterval(async () => {
  try {
    await riskyOperation();
  } catch (e) {
    console.error(e);  // Log and continue
  }
}, 30000);
```

---

#### 1. Reward Event Listener

```javascript
// server/services/rewardEventListener.js
//
// NOTE: Uses POLLING (queryFilter) instead of WebSocket subscriptions (contract.on)
// because Rogue Chain RPC causes "filter not found" errors with eth_getFilterChanges.
// This is the same pattern used by EventListener for Arbitrum NFT events.

class RewardEventListener {
  constructor(db, websocket, config) {
    this.db = db;
    this.ws = websocket;
    this.config = config;

    this.rogueProvider = new ethers.JsonRpcProvider(config.ROGUE_RPC_URL);
    this.rewarderContract = new ethers.Contract(
      config.NFT_REWARDER_ADDRESS,
      REWARDER_ABI,
      this.rogueProvider
    );

    this.lastProcessedBlock = 0;
    this.pollIntervalMs = 10000;  // 10 seconds (faster than EventListener since rewards are higher priority)
  }

  async start() {
    // Get current block number to start polling from
    try {
      this.lastProcessedBlock = await this.rogueProvider.getBlockNumber();
      console.log(`[RewardListener] Starting from block ${this.lastProcessedBlock}`);
    } catch (error) {
      console.error('[RewardListener] Failed to get block number:', error.message);
      this.lastProcessedBlock = 0;
    }

    // Start polling for events (NOT using contract.on() due to RPC filter issues)
    this.startEventPolling();
    console.log('[RewardListener] Started (using polling mode, 10s interval)');
  }

  /**
   * Poll for events using queryFilter instead of WebSocket subscriptions
   * This avoids "filter not found" errors on Rogue Chain RPC
   */
  startEventPolling() {
    this.pollInterval = setInterval(async () => {
      try {
        const currentBlock = await this.rogueProvider.getBlockNumber();

        // Only poll if there are new blocks
        if (currentBlock <= this.lastProcessedBlock) return;

        const fromBlock = this.lastProcessedBlock + 1;
        const toBlock = currentBlock;

        // Poll for RewardReceived events
        await this.pollRewardReceivedEvents(fromBlock, toBlock);

        // Poll for RewardClaimed events
        await this.pollRewardClaimedEvents(fromBlock, toBlock);

        this.lastProcessedBlock = toBlock;

      } catch (error) {
        if (!error.message?.includes('rate limit') && !error.message?.includes('coalesce')) {
          console.error('[RewardListener] Polling error:', error.message);
        }
      }
    }, this.pollIntervalMs);
  }

  async pollRewardReceivedEvents(fromBlock, toBlock) {
    try {
      const filter = this.rewarderContract.filters.RewardReceived();
      const events = await this.rewarderContract.queryFilter(filter, fromBlock, toBlock);

      for (const event of events) {
        const [betId, amount, timestamp] = event.args;
        console.log(`[RewardListener] Reward received: ${ethers.formatEther(amount)} ROGUE`);

        // Store in database
        this.db.insertRewardEvent({
          commitmentHash: betId.toString(),
          amount: amount.toString(),
          timestamp: Number(timestamp),
          blockNumber: event.blockNumber,
          txHash: event.transactionHash
        });

        // Update global stats
        await this.updateGlobalStats();

        // Update per-NFT earnings
        await this.updateNFTEarnings();

        // Broadcast to connected clients
        this.ws.broadcast({
          type: 'REWARD_RECEIVED',
          data: {
            amount: ethers.formatEther(amount),
            timestamp: Number(timestamp),
            txHash: event.transactionHash
          }
        });
      }
    } catch (error) {
      if (!error.message?.includes('rate limit')) {
        console.error('[RewardListener] RewardReceived poll error:', error.message);
      }
    }
  }

  async pollRewardClaimedEvents(fromBlock, toBlock) {
    try {
      const filter = this.rewarderContract.filters.RewardClaimed();
      const events = await this.rewarderContract.queryFilter(filter, fromBlock, toBlock);

      for (const event of events) {
        const [user, amount, tokenIds] = event.args;
        console.log(`[RewardListener] Claim by ${user}: ${ethers.formatEther(amount)} ROGUE`);

        // Update database
        this.db.recordWithdrawal({
          userAddress: user,
          amount: amount.toString(),
          tokenIds: JSON.stringify(tokenIds.map(t => Number(t))),
          txHash: event.transactionHash,
          timestamp: Math.floor(Date.now() / 1000)
        });

        // Update NFT earnings
        for (const tokenId of tokenIds) {
          await this.resetNFTPending(Number(tokenId));
        }

        // Broadcast to connected clients
        this.ws.broadcast({
          type: 'REWARD_CLAIMED',
          data: {
            user,
            amount: ethers.formatEther(amount),
            tokenIds: tokenIds.map(t => Number(t)),
            txHash: event.transactionHash
          }
        });
      }
    } catch (error) {
      if (!error.message?.includes('rate limit')) {
        console.error('[RewardListener] RewardClaimed poll error:', error.message);
      }
    }
  }

  async updateGlobalStats() {
    const stats = await this.rewarderContract.getGlobalStats();

    this.db.updateGlobalStats({
      totalRewardsReceived: stats.totalRewards.toString(),
      totalRewardsDistributed: stats.totalDistributed.toString(),
      rewardsLast24h: stats.last24Hours.toString(),
      overallAPY: Number(stats.overallAPY)
    });
  }

  stop() {
    if (this.pollInterval) clearInterval(this.pollInterval);
    console.log('[RewardListener] Stopped');
  }
}
```

#### 3. NFT Earnings Sync Service (Background Loop)

The contract stores `totalEarned` and `pendingAmount` per NFT. The server calculates `last24Hours` and `APY` off-chain using the proportional distribution formula. This avoids unbounded array growth on-chain.

**Key Insight**: Per-NFT 24h earnings is just a proportional share of global 24h rewards:
```
nft_24h = global_24h × (nft_multiplier / totalMultiplierPoints)
```

This is O(1) - one query for global 24h, then simple multiplication per NFT.

```javascript
// server/services/earningsSyncService.js

const MULTIPLIERS = [100, 90, 80, 70, 60, 50, 40, 30];  // hostess 0-7

class EarningsSyncService {
  constructor(db, config) {
    this.db = db;
    this.config = config;
    this.batchSize = 100;  // Fetch 100 NFTs per batch
    this.syncInterval = 30000;  // 30 seconds between full syncs
    this.isRunning = false;

    this.rogueProvider = new ethers.JsonRpcProvider(config.ROGUE_RPC_URL);
    this.rewarderContract = new ethers.Contract(
      config.NFT_REWARDER_ADDRESS,
      REWARDER_ABI,
      this.rogueProvider
    );
  }

  async start() {
    if (this.isRunning) return;
    this.isRunning = true;

    console.log('[EarningsSync] Starting background sync loop');

    // Initial sync
    await this.syncAllNFTEarnings();

    // Continuous loop
    this.syncLoop = setInterval(async () => {
      await this.syncAllNFTEarnings();
    }, this.syncInterval);
  }

  /**
   * Sync all NFT earnings from contract to SQLite in batches.
   * Contract provides: totalEarned, pendingAmount, hostessIndex
   * Server calculates: last24h (from reward_events), APY (from 24h and NFT value)
   */
  async syncAllNFTEarnings() {
    try {
      const allNFTs = this.db.getAllNFTs();
      const total = allNFTs.length;

      // ============================================================
      // STEP 1: Get global 24h rewards ONCE (O(1) query)
      // ============================================================
      const oneDayAgo = Math.floor(Date.now() / 1000) - 86400;
      const global24h = BigInt(this.db.getRewardsSince(oneDayAgo) || '0');
      const totalMultiplierPoints = BigInt(this.db.getTotalMultiplierPoints() || '109260');

      // Get NFT value in ROGUE for APY calculation (cached, updated periodically)
      const nftValueInRogue = BigInt(this.config.NFT_VALUE_IN_ROGUE || '9600000000000000000000000');  // 9.6M ROGUE default

      console.log(`[EarningsSync] Starting sync of ${total} NFTs in batches of ${this.batchSize}`);
      console.log(`[EarningsSync] Global 24h: ${ethers.formatEther(global24h)} ROGUE, Total points: ${totalMultiplierPoints}`);

      for (let i = 0; i < total; i += this.batchSize) {
        const batch = allNFTs.slice(i, i + this.batchSize);
        const tokenIds = batch.map(nft => nft.token_id);

        try {
          // ============================================================
          // STEP 2: Get on-chain earnings for batch (totalEarned, pendingAmount, hostessIndex)
          // ============================================================
          const earnings = await this.rewarderContract.getBatchNFTEarnings(tokenIds);

          // ============================================================
          // STEP 3: Calculate off-chain metrics for each NFT
          // ============================================================
          for (let j = 0; j < tokenIds.length; j++) {
            const tokenId = tokenIds[j];
            const earning = earnings[j];
            const multiplier = BigInt(MULTIPLIERS[Number(earning.hostessIndex)]);

            // Calculate this NFT's proportional share of global 24h
            // Formula: nft_24h = global_24h × multiplier / totalMultiplierPoints
            let last24hEarned = 0n;
            if (totalMultiplierPoints > 0n) {
              last24hEarned = (global24h * multiplier) / totalMultiplierPoints;
            }

            // Calculate APY: (annual_projection / nft_value) × 10000 basis points
            // Annual = last24h × 365
            let apyBasisPoints = 0;
            if (nftValueInRogue > 0n) {
              const annualProjection = last24hEarned * 365n;
              apyBasisPoints = Number((annualProjection * 10000n) / nftValueInRogue);
            }

            // Update SQLite with combined on-chain + off-chain data
            this.db.updateNFTEarnings(tokenId, {
              totalEarned: earning.totalEarned.toString(),
              pendingAmount: earning.pendingAmount.toString(),
              last24hEarned: last24hEarned.toString(),      // Calculated off-chain
              apyBasisPoints: apyBasisPoints                  // Calculated off-chain
            });
          }

          // Small delay between batches to avoid RPC rate limits
          await this.sleep(200);

        } catch (batchError) {
          console.error(`[EarningsSync] Batch ${i}-${i + this.batchSize} failed:`, batchError.message);
          // Continue with next batch
        }

        // Progress logging every 500 NFTs
        if ((i + this.batchSize) % 500 === 0 || i + this.batchSize >= total) {
          console.log(`[EarningsSync] Progress: ${Math.min(i + this.batchSize, total)}/${total}`);
        }
      }

      // Also sync global stats
      await this.syncGlobalStats(global24h);

      console.log(`[EarningsSync] Sync complete`);
    } catch (error) {
      console.error('[EarningsSync] Sync failed:', error.message);
    }
  }

  async syncGlobalStats(global24h) {
    // Get on-chain totals
    const totalRewardsReceived = await this.rewarderContract.totalRewardsReceived();
    const totalRewardsDistributed = await this.rewarderContract.totalRewardsDistributed();
    const totalMultiplierPoints = this.db.getTotalMultiplierPoints();

    // Calculate overall APY (average across all NFTs)
    const nftValueInRogue = BigInt(this.config.NFT_VALUE_IN_ROGUE || '9600000000000000000000000');
    let overallAPY = 0;
    if (nftValueInRogue > 0n && totalMultiplierPoints > 0) {
      // Average 24h per NFT = global24h / totalNFTs
      const totalNFTs = BigInt(this.db.getTotalNFTs());
      if (totalNFTs > 0n) {
        const avg24hPerNFT = global24h / totalNFTs;
        const annualProjection = avg24hPerNFT * 365n;
        overallAPY = Number((annualProjection * 10000n) / nftValueInRogue);
      }
    }

    this.db.updateGlobalStats({
      totalRewardsReceived: totalRewardsReceived.toString(),
      totalRewardsDistributed: totalRewardsDistributed.toString(),
      rewardsLast24h: global24h.toString(),      // Calculated off-chain from reward_events
      overallAPY: overallAPY                      // Calculated off-chain
    });
  }

  sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  stop() {
    this.isRunning = false;
    if (this.syncLoop) clearInterval(this.syncLoop);
    console.log('[EarningsSync] Stopped');
  }
}
```

### Frontend UI Changes

#### 1. New "Revenues" Tab

Add to navigation in `public/index.html`:

```html
<button data-tab="revenues" class="tab-btn px-6 py-4 text-gray-400 hover:text-white cursor-pointer whitespace-nowrap">
  Revenues
</button>
```

#### 2. Revenues Tab Content

```html
<!-- REVENUES TAB -->
<div id="tab-revenues" class="tab-panel">
  <div class="container mx-auto p-6">

    <!-- Global Stats Header -->
    <!-- All ROGUE amounts display USD value below in smaller gray text -->
    <section class="mb-8 grid grid-cols-1 md:grid-cols-4 gap-4">
      <div class="bg-gray-800 p-4 rounded-lg">
        <h3 class="text-gray-400 text-sm">Total Rewards Received</h3>
        <p id="total-rewards" class="text-2xl font-bold text-green-400">0 ROGUE</p>
        <p id="total-rewards-usd" class="text-sm text-gray-500">$0.00</p>
      </div>
      <div class="bg-gray-800 p-4 rounded-lg">
        <h3 class="text-gray-400 text-sm">Last 24 Hours</h3>
        <p id="last-24h-rewards" class="text-2xl font-bold text-yellow-400">0 ROGUE</p>
        <p id="last-24h-rewards-usd" class="text-sm text-gray-500">$0.00</p>
      </div>
      <div class="bg-gray-800 p-4 rounded-lg">
        <h3 class="text-gray-400 text-sm">Overall APY</h3>
        <p id="overall-apy" class="text-2xl font-bold text-purple-400">0%</p>
      </div>
      <div class="bg-gray-800 p-4 rounded-lg">
        <h3 class="text-gray-400 text-sm">Total Distributed</h3>
        <p id="total-distributed" class="text-2xl font-bold">0 ROGUE</p>
        <p id="total-distributed-usd" class="text-sm text-gray-500">$0.00</p>
      </div>
    </section>

    <!-- Per-Hostess Type Stats -->
    <section class="mb-8">
      <h2 class="text-xl font-bold mb-4">Revenue by NFT Type</h2>
      <div class="bg-gray-800 rounded-lg overflow-hidden">
        <table class="w-full">
          <thead class="bg-gray-700">
            <tr>
              <th class="p-3 text-left">NFT Type</th>
              <th class="p-3 text-left">Multiplier</th>
              <th class="p-3 text-left">Count</th>
              <th class="p-3 text-left">Share %</th>
              <th class="p-3 text-left">24h/NFT</th>
              <th class="p-3 text-left">APY</th>
            </tr>
          </thead>
          <tbody id="hostess-revenue-table">
            <!-- Populated by JavaScript -->
          </tbody>
        </table>
      </div>
    </section>

    <!-- My Revenue Section (only shown when wallet connected) -->
    <section id="my-revenue-section" class="mb-8 bg-gray-800 p-6 rounded-lg hidden">
      <h2 class="text-xl font-bold mb-4">My NFT Earnings</h2>

      <!-- Aggregated Stats -->
      <div class="grid grid-cols-1 md:grid-cols-5 gap-4 mb-6">
        <div class="bg-gray-700 p-4 rounded-lg">
          <h4 class="text-gray-400 text-sm">Total Earned</h4>
          <!-- Link to verify on-chain: userTotalClaimed(walletAddress) -->
          <a id="my-total-earned-link" href="#" target="_blank" class="text-xl font-bold text-green-400 hover:underline cursor-pointer">
            <span id="my-total-earned">0 ROGUE</span> ↗
          </a>
          <p id="my-total-earned-usd" class="text-sm text-gray-500">$0.00</p>
        </div>
        <div class="bg-gray-700 p-4 rounded-lg">
          <h4 class="text-gray-400 text-sm">Pending Balance</h4>
          <!-- Link to verify on-chain: pendingRewardsForOwner(walletAddress) -->
          <a id="my-pending-link" href="#" target="_blank" class="text-xl font-bold text-yellow-400 hover:underline cursor-pointer">
            <span id="my-pending">0 ROGUE</span> ↗
          </a>
          <p id="my-pending-usd" class="text-sm text-gray-500">$0.00</p>
        </div>
        <div class="bg-gray-700 p-4 rounded-lg">
          <h4 class="text-gray-400 text-sm">Last 24 Hours</h4>
          <p id="my-last-24h" class="text-xl font-bold">0 ROGUE</p>
          <p id="my-last-24h-usd" class="text-sm text-gray-500">$0.00</p>
        </div>
        <div class="bg-gray-700 p-4 rounded-lg">
          <h4 class="text-gray-400 text-sm">My Portfolio APY</h4>
          <p id="my-apy" class="text-xl font-bold text-purple-400">0%</p>
        </div>
        <div class="bg-gray-700 p-4 rounded-lg flex flex-col justify-center">
          <button id="withdraw-revenues-btn" class="bg-gradient-to-r from-green-600 to-emerald-600 hover:from-green-700 hover:to-emerald-700 py-3 px-6 rounded-lg font-bold cursor-pointer disabled:opacity-50">
            Withdraw All
          </button>
        </div>
      </div>

      <!-- Per-NFT Table -->
      <h3 class="font-bold mb-2">Earnings by NFT</h3>
      <div class="bg-gray-700 rounded-lg overflow-hidden max-h-96 overflow-y-auto">
        <table class="w-full text-sm">
          <thead class="bg-gray-600 sticky top-0">
            <tr>
              <th class="p-2 text-left">Token ID</th>
              <th class="p-2 text-left">Type</th>
              <th class="p-2 text-left">Mult</th>
              <th class="p-2 text-left">Total Earned ↗</th>
              <th class="p-2 text-left">Pending ↗</th>
              <th class="p-2 text-left">24h</th>
              <th class="p-2 text-left">APY</th>
            </tr>
          </thead>
          <tbody id="my-nft-revenues-table">
            <!-- Populated by JavaScript - each row links to contract verification -->
            <!-- Example row structure:
            <tr>
              <td>#1234</td>
              <td>Penelope Fatale</td>
              <td>100x</td>
              <td><a href="ROGUESCAN_LINK" target="_blank" class="text-green-400 hover:underline">0.5 ROGUE ↗</a></td>
              <td><a href="ROGUESCAN_LINK" target="_blank" class="text-yellow-400 hover:underline">0.02 ROGUE ↗</a></td>
              <td>0.001 ROGUE</td>
              <td>12.5%</td>
            </tr>
            -->
          </tbody>
        </table>
      </div>
    </section>

    <!-- Recent Reward Events -->
    <section class="mb-8">
      <h2 class="text-xl font-bold mb-4">Recent Rewards</h2>
      <div class="bg-gray-800 rounded-lg overflow-hidden">
        <table class="w-full">
          <thead class="bg-gray-700">
            <tr>
              <th class="p-3 text-left">Time</th>
              <th class="p-3 text-left">Amount</th>
              <th class="p-3 text-left">TX</th>
            </tr>
          </thead>
          <tbody id="reward-events-table">
            <!-- Populated by JavaScript - real-time updates -->
          </tbody>
        </table>
      </div>
    </section>

  </div>
</div>
```

#### 3. Gallery Tab Update - APY/24h Badges on NFT Cards

Add APY badge overlay to each NFT type card in the Gallery tab. The badge shows the current APY for that NFT type, helping users understand earning potential before buying.

```html
<!-- Gallery tab - NFT type card with APY badge overlay -->
<div class="nft-type-card bg-gray-800 rounded-lg overflow-hidden relative group cursor-pointer">
  <!-- APY Badge - top right overlay -->
  <div class="absolute top-2 right-2 bg-purple-600/90 backdrop-blur-sm px-2 py-1 rounded-md text-xs font-bold z-10">
    <span class="text-white">${hostess.apy}% APY</span>
  </div>

  <!-- 24h Earnings Badge - top left overlay (optional, shown on hover) -->
  <div class="absolute top-2 left-2 bg-green-600/90 backdrop-blur-sm px-2 py-1 rounded-md text-xs font-bold z-10 opacity-0 group-hover:opacity-100 transition-opacity">
    <span class="text-white">${hostess.last24hPerNFT} ROGUE/24h</span>
  </div>

  <img src="${getHostessImageUrl(hostess.index, 'card')}" alt="${hostess.name}" class="w-full">

  <div class="p-4">
    <p class="font-bold text-lg">${hostess.name}</p>
    <p class="text-sm text-gray-400">${hostess.multiplier}x Multiplier</p>
    <p class="text-xs text-gray-500">${hostess.count} minted</p>

    <!-- Earnings Stats (always visible) -->
    <div class="mt-3 pt-3 border-t border-gray-700 grid grid-cols-2 gap-2 text-xs">
      <div>
        <p class="text-gray-500">24h/NFT</p>
        <p class="text-green-400 font-medium">${hostess.last24hPerNFT} ROGUE</p>
        <p class="text-gray-600 text-[10px]">$${hostess.last24hPerNFTUsd}</p>
      </div>
      <div>
        <p class="text-gray-500">APY</p>
        <p class="text-purple-400 font-medium">${hostess.apy}%</p>
      </div>
    </div>
  </div>
</div>
```

#### 4. My NFTs Tab Update

Add earnings display to each owned NFT card with USD values:

```html
<!-- Updated NFT card in My NFTs tab -->
<div class="nft-card bg-gray-800 rounded-lg overflow-hidden relative">
  <!-- APY Badge - top right overlay -->
  <div class="absolute top-2 right-2 bg-purple-600/90 backdrop-blur-sm px-2 py-1 rounded-md text-xs font-bold">
    <span class="text-white">${nft.apy}% APY</span>
  </div>

  <img src="${getHostessImageUrl(nft.hostessIndex, 'card')}" alt="${nft.hostessName}" class="w-full">
  <div class="p-3">
    <p class="font-bold">${nft.hostessName}</p>
    <p class="text-sm text-gray-400">#${nft.tokenId}</p>
    <p class="text-xs text-gray-500">${nft.multiplier}x Multiplier</p>

    <!-- Earnings display with USD values -->
    <div class="mt-2 pt-2 border-t border-gray-700">
      <div class="flex justify-between text-xs">
        <span class="text-gray-400">Pending:</span>
        <div class="text-right">
          <span class="text-yellow-400">${nft.pending} ROGUE</span>
          <span class="text-gray-600 text-[10px] block">$${nft.pendingUsd}</span>
        </div>
      </div>
      <div class="flex justify-between text-xs mt-1">
        <span class="text-gray-400">24h:</span>
        <div class="text-right">
          <span class="text-green-400">${nft.last24Hours} ROGUE</span>
          <span class="text-gray-600 text-[10px] block">$${nft.last24HoursUsd}</span>
        </div>
      </div>
      <div class="flex justify-between text-xs mt-1">
        <span class="text-gray-400">Total Earned:</span>
        <div class="text-right">
          <span class="text-white">${nft.totalEarned} ROGUE</span>
          <span class="text-gray-600 text-[10px] block">$${nft.totalEarnedUsd}</span>
        </div>
      </div>
    </div>
  </div>
</div>
```

#### 5. ROGUE Price Service

The high-rollers-nfts app needs ROGUE/USD price for displaying USD values. We poll Blockster's PriceTracker API every 20 minutes.

##### 5a. Blockster API Endpoint (Add to main app)

Blockster already has a `PriceTracker` GenServer that polls CoinGecko every 10 minutes. We just need to expose it via a public API endpoint.

**File**: `lib/blockster_v2_web/controllers/price_controller.ex`

```elixir
defmodule BlocksterV2Web.PriceController do
  use BlocksterV2Web, :controller

  alias BlocksterV2.PriceTracker

  @doc """
  GET /api/prices/:symbol
  Returns the current USD price for a token symbol (e.g., ROGUE, ETH, BTC)
  """
  def show(conn, %{"symbol" => symbol}) do
    symbol_upper = String.upcase(symbol)

    case PriceTracker.get_price(symbol_upper) do
      {:ok, price_data} ->
        json(conn, %{
          symbol: price_data.symbol,
          usd_price: price_data.usd_price,
          usd_24h_change: price_data.usd_24h_change,
          last_updated: price_data.last_updated
        })

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Token not found", symbol: symbol_upper})
    end
  end
end
```

**File**: `lib/blockster_v2_web/router.ex` (add to existing `/api` scope)

```elixir
scope "/api", BlocksterV2Web do
  pipe_through :api

  # ... existing routes ...

  # Public price endpoint (no auth required)
  get "/prices/:symbol", PriceController, :show
end
```

**Response Format**:
```json
{
  "symbol": "ROGUE",
  "usd_price": 0.0000821,
  "usd_24h_change": 1.23,
  "last_updated": 1736100000
}
```

##### 5b. Server-Side Price Service (high-rollers-nfts)

Poll Blockster's API every 20 minutes and cache the price. Broadcast to WebSocket clients on update.

**File**: `server/services/priceService.js`

```javascript
/**
 * PriceService - Polls Blockster API for ROGUE/USD and ETH/USD prices every 10 minutes
 *
 * Architecture:
 * - Server polls Blockster API (which polls CoinGecko every 10 min)
 * - Both ROGUE and ETH prices cached in memory with timestamps
 * - ETH price used for NFT value calculation (0.32 ETH mint price)
 * - WebSocket broadcasts price updates to all connected clients
 * - API endpoint exposes prices to frontend
 */

class PriceService {
  constructor(websocketServer) {
    this.ws = websocketServer;

    // ROGUE price data
    this.roguePrice = 0;
    this.rogueUsd24hChange = 0;

    // ETH price data (for NFT value calculation)
    this.ethPrice = 0;
    this.ethUsd24hChange = 0;

    this.lastUpdated = 0;
    this.pollIntervalMs = 10 * 60 * 1000;  // 10 minutes (matches Blockster's CoinGecko poll interval)

    // Blockster's price API (uses PriceTracker which polls CoinGecko)
    this.blocksterApiBase = 'https://blockster-v2.fly.dev/api/prices';
  }

  async start() {
    // Fetch immediately on startup
    await this.fetchPrices();

    // Then poll every 10 minutes
    this.pollInterval = setInterval(async () => {
      await this.fetchPrices();
    }, this.pollIntervalMs);

    console.log('[PriceService] Started (polling Blockster API every 10 min)');
  }

  async fetchPrices() {
    try {
      // Fetch ROGUE and ETH prices in parallel
      const [rogueRes, ethRes] = await Promise.all([
        fetch(`${this.blocksterApiBase}/ROGUE`, {
          headers: { 'Accept': 'application/json' },
          timeout: 10000
        }),
        fetch(`${this.blocksterApiBase}/ETH`, {
          headers: { 'Accept': 'application/json' },
          timeout: 10000
        })
      ]);

      if (!rogueRes.ok) {
        throw new Error(`ROGUE HTTP ${rogueRes.status}`);
      }
      if (!ethRes.ok) {
        throw new Error(`ETH HTTP ${ethRes.status}`);
      }

      const rogueData = await rogueRes.json();
      const ethData = await ethRes.json();

      this.roguePrice = rogueData.usd_price || 0;
      this.rogueUsd24hChange = rogueData.usd_24h_change || 0;
      this.ethPrice = ethData.usd_price || 0;
      this.ethUsd24hChange = ethData.usd_24h_change || 0;
      this.lastUpdated = Date.now();

      console.log(`[PriceService] ROGUE: $${this.roguePrice} (${this.formatChange(this.rogueUsd24hChange)}), ETH: $${this.ethPrice} (${this.formatChange(this.ethUsd24hChange)})`);

      // Broadcast to all connected clients
      this.ws.broadcast({
        type: 'PRICE_UPDATE',
        data: {
          rogue: {
            symbol: 'ROGUE',
            usdPrice: this.roguePrice,
            usd24hChange: this.rogueUsd24hChange
          },
          eth: {
            symbol: 'ETH',
            usdPrice: this.ethPrice,
            usd24hChange: this.ethUsd24hChange
          },
          lastUpdated: this.lastUpdated
        }
      });

    } catch (error) {
      console.error('[PriceService] Failed to fetch prices:', error.message);
      // Keep using last known prices - don't reset to 0
    }
  }

  formatChange(change) {
    const sign = change >= 0 ? '+' : '';
    return `${sign}${change.toFixed(2)}%`;
  }

  getPrices() {
    return {
      rogue: {
        symbol: 'ROGUE',
        usdPrice: this.roguePrice,
        usd24hChange: this.rogueUsd24hChange
      },
      eth: {
        symbol: 'ETH',
        usdPrice: this.ethPrice,
        usd24hChange: this.ethUsd24hChange
      },
      lastUpdated: this.lastUpdated
    };
  }

  /**
   * Get NFT value in ROGUE based on 0.32 ETH mint price
   * @returns {number} NFT value in ROGUE
   */
  getNftValueInRogue() {
    if (!this.ethPrice || !this.roguePrice) return 0;
    const nftValueUsd = 0.32 * this.ethPrice;  // 0.32 ETH mint price
    return nftValueUsd / this.roguePrice;
  }

  /**
   * Format ROGUE amount to USD string
   * @param {number} rogueAmount - Amount in ROGUE
   * @returns {string} Formatted USD string (e.g., "$1.23", "$1.2k", "$1.2M")
   */
  formatUsd(rogueAmount) {
    if (!this.roguePrice || rogueAmount === 0) return '$0.00';

    const usd = rogueAmount * this.roguePrice;

    if (usd >= 1_000_000) {
      return `$${(usd / 1_000_000).toFixed(2)}M`;
    } else if (usd >= 1_000) {
      return `$${(usd / 1_000).toFixed(2)}k`;
    } else if (usd >= 1) {
      return `$${usd.toFixed(2)}`;
    } else if (usd >= 0.01) {
      return `$${usd.toFixed(2)}`;
    } else if (usd > 0) {
      return `<$0.01`;
    }
    return '$0.00';
  }

  stop() {
    if (this.pollInterval) {
      clearInterval(this.pollInterval);
    }
    console.log('[PriceService] Stopped');
  }
}

module.exports = PriceService;
```

##### 5c. Integration with Server (index.js)

```javascript
// server/index.js

const PriceService = require('./services/priceService');

// After WebSocket server is created
const priceService = new PriceService(wsServer);

// Start after other services
priceService.start();

// Graceful shutdown
process.on('SIGTERM', () => {
  priceService.stop();
  // ... other cleanup
});
```

##### 5d. API Endpoint for Prices

```javascript
// server/routes/api.js

// GET /api/prices - Current ROGUE and ETH prices
router.get('/prices', (req, res) => {
  const prices = priceService.getPrices();
  res.json(prices);
});

// GET /api/prices/nft-value - Get NFT value in ROGUE
router.get('/prices/nft-value', (req, res) => {
  const prices = priceService.getPrices();
  const nftValueRogue = priceService.getNftValueInRogue();
  res.json({
    nftValueRogue: nftValueRogue,
    ethPrice: prices.eth.usdPrice,
    roguePrice: prices.rogue.usdPrice,
    mintPriceEth: 0.32
  });
});

// GET /api/prices/format/:amount - Format ROGUE amount to USD
router.get('/prices/format/:amount', (req, res) => {
  const amount = parseFloat(req.params.amount) || 0;
  res.json({
    rogueAmount: amount,
    usdFormatted: priceService.formatUsd(amount),
    roguePrice: priceService.getPrices().rogue.usdPrice
  });
});
```

##### 5e. Client-Side Price Updates

```javascript
// public/js/priceService.js

class ClientPriceService {
  constructor() {
    this.roguePrice = 0;
    this.rogueUsd24hChange = 0;
    this.ethPrice = 0;
    this.ethUsd24hChange = 0;
    this.lastUpdated = 0;
  }

  // Initialize from API on page load
  async init() {
    try {
      const response = await fetch('/api/prices');
      const data = await response.json();
      this.updatePrices(data);
    } catch (error) {
      console.error('[PriceService] Failed to fetch initial prices:', error);
    }
  }

  // Called when WebSocket receives PRICE_UPDATE
  updatePrices(data) {
    this.roguePrice = data.rogue?.usdPrice || 0;
    this.rogueUsd24hChange = data.rogue?.usd24hChange || 0;
    this.ethPrice = data.eth?.usdPrice || 0;
    this.ethUsd24hChange = data.eth?.usd24hChange || 0;
    this.lastUpdated = data.lastUpdated || Date.now();

    // Update all USD displays on the page
    this.updateAllUsdDisplays();
  }

  // Get NFT value in ROGUE (0.32 ETH mint price)
  getNftValueInRogue() {
    if (!this.ethPrice || !this.roguePrice) return 0;
    const nftValueUsd = 0.32 * this.ethPrice;
    return nftValueUsd / this.roguePrice;
  }

  formatUsd(rogueAmount) {
    if (!this.roguePrice || rogueAmount === 0) return '$0.00';

    const usd = rogueAmount * this.roguePrice;

    if (usd >= 1_000_000) return `$${(usd / 1_000_000).toFixed(2)}M`;
    if (usd >= 1_000) return `$${(usd / 1_000).toFixed(2)}k`;
    if (usd >= 0.01) return `$${usd.toFixed(2)}`;
    if (usd > 0) return '<$0.01';
    return '$0.00';
  }

  updateAllUsdDisplays() {
    // Find all elements with data-rogue-amount attribute and update their USD displays
    document.querySelectorAll('[data-rogue-amount]').forEach(el => {
      const rogueAmount = parseFloat(el.dataset.rogueAmount) || 0;
      const usdEl = el.querySelector('.usd-value') || el.nextElementSibling;
      if (usdEl && usdEl.classList.contains('usd-value')) {
        usdEl.textContent = this.formatUsd(rogueAmount);
      }
    });
  }
}

// Global instance
const priceService = new ClientPriceService();

// Initialize on page load
document.addEventListener('DOMContentLoaded', () => {
  priceService.init();
});

// WebSocket handler (add to existing WebSocket setup)
// ws.on('PRICE_UPDATE', (data) => priceService.updatePrice(data));
```

##### 5f. Usage in HTML Templates

```html
<!-- ROGUE amount with auto-updating USD value -->
<div data-rogue-amount="1234.56">
  <span class="rogue-value">1,234.56 ROGUE</span>
  <span class="usd-value text-gray-500 text-sm">$0.10</span>
</div>

<!-- Or inline for simpler cases -->
<span class="text-green-400">500 ROGUE</span>
<span class="usd-value text-gray-500 text-xs" id="my-earnings-usd"></span>

<script>
  // Update specific USD display
  document.getElementById('my-earnings-usd').textContent = priceService.formatUsd(500);
</script>
```

##### 5g. Architecture Summary

```
┌─────────────────────────────────────────────────────────────────┐
│                         CoinGecko API                            │
│                    (Rate limited, external)                      │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼ (every 10 min)
┌─────────────────────────────────────────────────────────────────┐
│                 Blockster PriceTracker                           │
│            (Mnesia cache, PubSub broadcasts)                     │
│         GET /api/prices/ROGUE  |  GET /api/prices/ETH            │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼ (every 10 min)
┌─────────────────────────────────────────────────────────────────┐
│              high-rollers-nfts PriceService                      │
│        (Memory cache, WebSocket broadcasts)                      │
│    GET /api/prices  (returns ROGUE + ETH for APY calc)           │
└─────────────────────────────────────────────────────────────────┘
                               │
              ┌────────────────┼────────────────┐
              ▼                ▼                ▼
       ┌─────────────┐  ┌─────────────┐  ┌─────────────┐
       │  Revenues   │  │   Gallery   │  │   My NFTs   │
       │     Tab     │  │   (APY %)   │  │     Tab     │
       └─────────────┘  └─────────────┘  └─────────────┘
```

**Why poll Blockster instead of CoinGecko directly?**
1. **Rate limits**: CoinGecko free tier has 30 calls/min limit. Blockster already handles this.
2. **Single source of truth**: Same price displayed in BUX Booster and High Rollers
3. **Caching**: Blockster caches in Mnesia, reducing external API calls
4. **Reliability**: If CoinGecko is slow/down, Blockster returns cached price

#### 6. On-Chain Verification Links (Roguescan)

All earnings amounts link directly to Roguescan's read contract page so users can verify values on-chain.

**URL Format:**
```
https://roguescan.io/address/{NFT_REWARDER_ADDRESS}?tab=read_contract
```

**Contract View Functions for Verification:**

| Function | Parameters | Returns | Purpose |
|----------|------------|---------|---------|
| `getOwnerEarnings(address)` | wallet address | (totalPending, totalClaimed, tokenIds[]) | **Main verification** - all user earnings in one call |
| `getTokenEarnings(uint256[])` | array of tokenIds | (pending[], claimed[], multipliers[]) | Batch query for multiple NFTs |
| `getOwnerTokenIds(address)` | wallet address | uint256[] tokenIds | List all NFTs owned by wallet |
| `pendingReward(tokenId)` | uint256 tokenId | uint256 wei | Pending rewards for single NFT |
| `nftClaimedRewards(tokenId)` | uint256 tokenId | uint256 wei | Total ever claimed by NFT |
| `userTotalClaimed(address)` | address user | uint256 wei | Total ever claimed by user |
| `totalRewardsReceived()` | - | uint256 wei | All-time rewards to contract |
| `totalRewardsDistributed()` | - | uint256 wei | All-time claimed rewards |

**JavaScript URL Generator:**

```javascript
// public/js/config.js
const NFT_REWARDER_ADDRESS = '0x...';  // Set after deployment
const ROGUESCAN_BASE = 'https://roguescan.io';

// URL generators for verification links
const RoguescanLinks = {
  // Contract read page base URL
  readContract: () =>
    `${ROGUESCAN_BASE}/address/${NFT_REWARDER_ADDRESS}?tab=read_contract`,

  // Main verification - user enters wallet address, gets (totalPending, totalClaimed, tokenIds[])
  ownerEarnings: () =>
    `${ROGUESCAN_BASE}/address/${NFT_REWARDER_ADDRESS}?tab=read_contract#getOwnerEarnings`,

  // Batch verification - user enters array of tokenIds
  tokenEarnings: () =>
    `${ROGUESCAN_BASE}/address/${NFT_REWARDER_ADDRESS}?tab=read_contract#getTokenEarnings`,

  // Per-NFT pending reward (pendingReward function)
  nftPending: (tokenId) =>
    `${ROGUESCAN_BASE}/address/${NFT_REWARDER_ADDRESS}?tab=read_contract#pendingReward`,

  // Per-NFT total claimed (nftClaimedRewards function)
  nftTotalClaimed: (tokenId) =>
    `${ROGUESCAN_BASE}/address/${NFT_REWARDER_ADDRESS}?tab=read_contract#nftClaimedRewards`,

  // Global contract stats
  contractStats: () =>
    `${ROGUESCAN_BASE}/address/${NFT_REWARDER_ADDRESS}?tab=read_contract#totalRewardsReceived`
};
```

**Usage in UI:**

```javascript
// Update aggregated stats with verification links
function updateMyEarningsUI(earnings, walletAddress) {
  // Total Earned - links to getOwnerEarnings(walletAddress)
  document.getElementById('my-total-earned').textContent =
    `${formatRogue(earnings.totalClaimed)} ROGUE`;
  document.getElementById('my-total-earned-link').href =
    RoguescanLinks.ownerEarnings();  // User enters their wallet address

  // Pending Balance - links to getOwnerEarnings(walletAddress)
  document.getElementById('my-pending').textContent =
    `${formatRogue(earnings.totalPending)} ROGUE`;
  document.getElementById('my-pending-link').href =
    RoguescanLinks.ownerEarnings();  // Same function returns both values
}

// Generate per-NFT table row with verification links
function createNFTRevenueRow(nft) {
  return `
    <tr>
      <td class="p-2">#${nft.tokenId}</td>
      <td class="p-2">${nft.hostessName}</td>
      <td class="p-2">${nft.multiplier}x</td>
      <td class="p-2">
        <a href="${RoguescanLinks.nftTotalClaimed(nft.tokenId)}"
           target="_blank"
           class="text-green-400 hover:underline cursor-pointer"
           title="Verify on Roguescan: nftClaimedRewards(${nft.tokenId})">
          ${formatRogue(nft.totalClaimed)} ROGUE ↗
        </a>
      </td>
      <td class="p-2">
        <a href="${RoguescanLinks.nftPending(nft.tokenId)}"
           target="_blank"
           class="text-yellow-400 hover:underline cursor-pointer"
           title="Verify on Roguescan: pendingReward(${nft.tokenId})">
          ${formatRogue(nft.pending)} ROGUE ↗
        </a>
      </td>
      <td class="p-2">${formatRogue(nft.last24h)} ROGUE</td>
      <td class="p-2 text-purple-400">${nft.apy}%</td>
    </tr>
  `;
}
```

**Note**: Roguescan (Blockscout) uses anchor links like `#functionName` to scroll to specific read functions. User still needs to input parameters (tokenId or address) manually, but this gets them directly to the right function.

---

#### 5. Real-Time WebSocket Updates

```javascript
// public/js/revenues.js

class RevenueService {
  constructor(websocket) {
    this.ws = websocket;
    this.listeners = [];

    // Handle WebSocket messages
    websocket.on('REWARD_RECEIVED', (data) => {
      this.handleRewardReceived(data);
    });

    websocket.on('REWARD_CLAIMED', (data) => {
      this.handleRewardClaimed(data);
    });
  }

  handleRewardReceived(data) {
    // Update global stats display
    this.updateGlobalStats();

    // Add to recent events table
    this.prependRewardEvent(data);

    // Update per-hostess stats
    this.updateHostessStats();

    // If user is connected, update their earnings
    if (walletService.address) {
      this.updateMyEarnings();
    }

    // Flash animation on stats cards
    this.flashNewReward(data.amount);
  }

  handleRewardClaimed(data) {
    // Update global distributed amount
    this.updateGlobalStats();

    // If it's the current user, update their pending balance
    if (walletService.address?.toLowerCase() === data.user.toLowerCase()) {
      this.updateMyEarnings();
    }
  }

  async loadRevenueData() {
    const [globalStats, history] = await Promise.all([
      fetch('/api/revenues/stats').then(r => r.json()),
      fetch('/api/revenues/history?limit=20').then(r => r.json())
    ]);

    this.renderGlobalStats(globalStats);
    this.renderHostessTable(globalStats.hostessTypes);
    this.renderRecentEvents(history.events);

    if (walletService.address) {
      const userEarnings = await fetch(`/api/revenues/user/${walletService.address}`).then(r => r.json());
      this.renderMyEarnings(userEarnings);
    }
  }

  async withdraw() {
    if (!walletService.signer) {
      throw new Error('Please connect your wallet');
    }

    const rewarderContract = new ethers.Contract(
      NFT_REWARDER_ADDRESS,
      ['function claimAll() external returns (uint256)'],
      walletService.signer
    );

    const tx = await rewarderContract.claimAll();
    await tx.wait();

    // Refresh earnings display
    await this.updateMyEarnings();
  }
}
```

---

## APY Calculation

### Formula

```
APY = (Last 24h Earnings × 365 / NFT Value in ROGUE) × 100%
```

### NFT Value Calculation

NFT mint price: 0.32 ETH

To convert to ROGUE value:
1. Get ETH/USD price from Blockster API: `GET /api/prices/ETH`
2. Get ROGUE/USD price from Blockster API: `GET /api/prices/ROGUE`
3. NFT Value in ROGUE = (0.32 × ETH_USD) / ROGUE_USD

Both prices are fetched from Blockster's PriceTracker, which polls CoinGecko every 10 minutes.

**Example** (hypothetical prices):
- ETH = $3,000
- ROGUE = $0.0001
- NFT Value = (0.32 × 3000) / 0.0001 = 9,600,000 ROGUE

If NFT earns 100 ROGUE in 24h:
- Annual projection = 100 × 365 = 36,500 ROGUE
- APY = (36,500 / 9,600,000) × 100% = **0.38%**

### Caching Strategy

- Refresh prices from Blockster API every 10 minutes (matches Blockster's CoinGecko poll interval)
- Cache ETH/USD and ROGUE/USD prices in PriceService
- Update on each reward event for real-time accuracy

---

## Deployment Checklist

### Phase 0: Prerequisites (Blockster Main App)

1. [ ] Add `/api/prices/:symbol` endpoint to Blockster (see Section 5a)
2. [ ] Deploy Blockster with price endpoint
3. [ ] Verify endpoints return prices:
   - `curl https://blockster-v2.fly.dev/api/prices/ROGUE`
   - `curl https://blockster-v2.fly.dev/api/prices/ETH`

### Phase 1: Smart Contracts

4. [ ] Create `NFTRewarder.sol` in `contracts/bux-booster-game/contracts/`
5. [ ] Write comprehensive tests for NFTRewarder
6. [ ] Test multiplier-weighted distribution with edge cases
7. [ ] Modify `ROGUEBankroll.sol` for V7 upgrade
8. [ ] Test NFT reward sending in `settleBuxBoosterLosingBet`
9. [ ] Deploy NFTRewarder to Rogue Chain Mainnet
10. [ ] Deploy ROGUEBankroll V7 upgrade (but do NOT call setNFTRewarder yet!)
11. [ ] Verify all contracts on Roguescan
12. [ ] Set admin address on NFTRewarder: `setAdmin(serverWalletAddress)`

### Phase 1.5: Initial NFT Registration (BEFORE enabling rewards)

**CRITICAL**: All 2,341 NFTs must be registered before calling `setNFTRewarder()` on ROGUEBankroll.
Otherwise early rewards will be incorrectly distributed (fewer multiplier points = higher per-NFT payouts).

**Data Source**: `nfts` table in SQLite database (synced from Arbitrum via OwnerSyncService)

| Column | Description |
|--------|-------------|
| `token_id` | NFT token ID (1-2341) |
| `hostess_index` | 0-7 (Penelope=0, Vivienne=7) |
| `owner` | Current owner address |

**Registration Script** (`scripts/register-all-nfts.js`):

```javascript
const { ethers } = require('ethers');
const Database = require('better-sqlite3');

const BATCH_SIZE = 200;  // ~200 NFTs per tx to stay under gas limit
const db = new Database('/data/highrollers.db');

async function registerAllNFTs() {
  const provider = new ethers.JsonRpcProvider(process.env.ROGUE_RPC_URL);
  const wallet = new ethers.Wallet(process.env.ADMIN_PRIVATE_KEY, provider);

  const rewarder = new ethers.Contract(
    process.env.NFT_REWARDER_ADDRESS,
    ['function batchRegisterNFTs(uint256[] tokenIds, uint8[] hostessIndices, address[] owners) external',
     'function totalRegisteredNFTs() view returns (uint256)',
     'function totalMultiplierPoints() view returns (uint256)'],
    wallet
  );

  // Get all NFTs from database
  const nfts = db.prepare('SELECT token_id, hostess_index, owner FROM nfts ORDER BY token_id').all();
  console.log(`Found ${nfts.length} NFTs to register`);

  // Register in batches
  for (let i = 0; i < nfts.length; i += BATCH_SIZE) {
    const batch = nfts.slice(i, i + BATCH_SIZE);

    const tokenIds = batch.map(n => n.token_id);
    const hostessIndices = batch.map(n => n.hostess_index);
    const owners = batch.map(n => n.owner);

    console.log(`Registering batch ${Math.floor(i/BATCH_SIZE) + 1}: tokens ${tokenIds[0]}-${tokenIds[tokenIds.length-1]}`);

    const tx = await rewarder.batchRegisterNFTs(tokenIds, hostessIndices, owners);
    const receipt = await tx.wait();
    console.log(`  TX: ${tx.hash} (gas: ${receipt.gasUsed})`);
  }

  // Verify
  const totalNFTs = await rewarder.totalRegisteredNFTs();
  const totalPoints = await rewarder.totalMultiplierPoints();
  console.log(`\nRegistration complete:`);
  console.log(`  Total NFTs: ${totalNFTs} (expected: 2341)`);
  console.log(`  Total Points: ${totalPoints} (expected: 109390)`);
}

registerAllNFTs();
```

**Checklist:**

13. [ ] Create `scripts/register-all-nfts.js` registration script
14. [ ] Run registration script: `node scripts/register-all-nfts.js`
    - Expected: ~12 transactions (2341 ÷ 200 = 12 batches)
    - Verify output: `totalRegisteredNFTs = 2341`, `totalMultiplierPoints = 109390`
15. [ ] Verify on Roguescan: query `totalRegisteredNFTs()` and `totalMultiplierPoints()`
16. [ ] ONLY AFTER verification: Call `setNFTRewarder(NFTRewarderAddress)` on ROGUEBankroll

### Phase 2: Backend Services

17. [ ] Create database migrations for new tables
18. [ ] Implement PriceService (polls Blockster API every 10 min for ROGUE + ETH)
19. [ ] Implement RewardEventListener service
20. [ ] Create /api/revenues/* endpoints
21. [ ] Create /api/prices endpoint (ROGUE + ETH for APY calculation)
22. [ ] Add WebSocket broadcast for reward and price events
23. [ ] Test full flow: bet → lose → reward → display

### Phase 3: Frontend

24. [ ] Add client-side PriceService for USD formatting
25. [ ] Add Revenues tab to navigation
26. [ ] Create revenues tab UI with all sections and USD values
27. [ ] Add real-time WebSocket updates (rewards + prices)
28. [ ] Update My NFTs tab with earnings display and USD values
29. [ ] Update Gallery tab with APY badges and USD values
30. [ ] Implement withdraw functionality
31. [ ] Add APY calculation and display
32. [ ] Test responsive design

### Phase 4: Testing & Monitoring

33. [ ] End-to-end test with real ROGUE bets
34. [ ] Verify proportional distribution across multipliers
35. [ ] Test withdrawal flow
36. [ ] Verify USD values update when price changes
37. [ ] Monitor gas costs for reward sending
38. [ ] Set up alerts for failed reward sends
39. [ ] Document troubleshooting procedures

---

## Security Considerations

### Smart Contract Security

1. **Access Control**: Only ROGUEBankroll can call `receiveReward()`
2. **Reentrancy Protection**: Use reentrancy guards on claim functions
3. **Integer Overflow**: Use Solidity 0.8+ checked math
4. **Reward Debt Pattern**: Standard MasterChef-style reward calculation
5. **Ownership Verification**: Verify NFT ownership before allowing claims

### Backend Security

1. **API Rate Limiting**: Prevent abuse of revenue endpoints
2. **Input Validation**: Validate all addresses and token IDs
3. **Database Integrity**: Use transactions for multi-table updates
4. **Event Verification**: Confirm events match blockchain state

### Economic Security

1. **Reward Cap**: Maximum 0.2% of wager per losing bet
2. **Try/Catch**: Failed reward sends don't block bet settlement
3. **Accounting**: Track all rewards sent for audit trail
4. **Slashing**: No mechanism for slashing NFT holder rewards

---

## Configuration Constants

### Rogue Chain

| Constant | Value | Description |
|----------|-------|-------------|
| NFT_REWARD_BPS | 20 | Basis points of wager sent to NFTs (0.20%) |
| NFT_REWARDER_ADDRESS | TBD | NFTRewarder contract address |

### Arbitrum One

| Constant | Value | Description |
|----------|-------|-------------|
| NFT_CONTRACT_ADDRESS | `0x7176d2edd83aD037bd94b7eE717bd9F661F560DD` | High Rollers NFT |
| NFT_MINT_PRICE | 0.32 ETH | For APY calculation |

### NFT Multipliers

| Index | Name | Multiplier |
|-------|------|------------|
| 0 | Penelope Fatale | 100 |
| 1 | Mia Siren | 90 |
| 2 | Cleo Enchante | 80 |
| 3 | Sophia Spark | 70 |
| 4 | Luna Mirage | 60 |
| 5 | Aurora Seductra | 50 |
| 6 | Scarlett Ember | 40 |
| 7 | Vivienne Allure | 30 |

---

## Future Enhancements

1. **Cross-Chain Bridge**: Automatic ROGUE → ETH bridging for Arbitrum payouts
2. **Compound Rewards**: Option to auto-reinvest rewards into more NFTs
3. **Tiered Rewards**: Bonus multiplier for long-term holders
4. **Governance**: NFT holder voting on revenue split percentage
5. **Dashboard Analytics**: Historical charts of earnings over time
6. **Mobile App**: Push notifications for reward events

---

## References

- [High Rollers NFT Documentation](../high-rollers-nfts/docs/README.md)
- [ROGUE Betting Integration Plan](ROGUE_BETTING_INTEGRATION_PLAN.md)
- [ROGUEBankroll Contract](../contracts/bux-booster-game/contracts/ROGUEBankroll.sol)
- [V5 Upgrade Summary](v5_upgrade_summary.md)
- [BUX Minter Documentation](bux_minter.md)

---

*Last updated: January 5, 2026*
