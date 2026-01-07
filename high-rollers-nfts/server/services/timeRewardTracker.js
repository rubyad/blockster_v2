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
    this.TIME_REWARD_DURATION = 180 * 24 * 60 * 60; // 180 days in seconds (15,552,000)
    this.SPECIAL_NFT_START_ID = 2340;
    this.SPECIAL_NFT_END_ID = 2700;

    // Time reward rates per second (in wei, with 18 decimals precision)
    // Index 0-7 = hostess types (Penelope to Vivienne)
    // Values from initializeV3() in NFTRewarder contract
    this.TIME_REWARD_RATES = [
      BigInt('2125029000000000000'),  // Penelope (100x) - 2.125029 ROGUE/sec
      BigInt('1912007000000000000'),  // Mia (90x) - 1.912007 ROGUE/sec
      BigInt('1700492000000000000'),  // Cleo (80x) - 1.700492 ROGUE/sec
      BigInt('1487470000000000000'),  // Sophia (70x) - 1.487470 ROGUE/sec
      BigInt('1274962000000000000'),  // Luna (60x) - 1.274962 ROGUE/sec
      BigInt('1062454000000000000'),  // Aurora (50x) - 1.062454 ROGUE/sec
      BigInt('849946000000000000'),   // Scarlett (40x) - 0.849946 ROGUE/sec
      BigInt('637438000000000000'),   // Vivienne (30x) - 0.637438 ROGUE/sec
    ];

    // Provider for contract calls (recovery/verification only)
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
   * Get time reward rate per second in wei
   * @param hostessIndex 0-7
   * @returns Rate in wei (BigInt)
   */
  getRatePerSecondWei(hostessIndex) {
    return this.TIME_REWARD_RATES[hostessIndex];
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
        pendingWei: '0',
        ratePerSecond: 0,
        timeRemaining: 0,
        totalFor180Days: 0,
        totalEarned: 0,
        totalClaimed: 0,
        startTime: 0,
        endTime: 0,
        isSpecial: this.isSpecialNFT(tokenId),
        hasStarted: false
      };
    }

    const hostessIndex = nft.hostess_index;
    const ratePerSecond = this.getRatePerSecond(hostessIndex);
    const ratePerSecondWei = this.getRatePerSecondWei(hostessIndex);

    const now = Math.floor(Date.now() / 1000);
    const startTime = nft.start_time;
    const endTime = startTime + this.TIME_REWARD_DURATION;
    const lastClaimTime = nft.last_claim_time || startTime;

    // Cap current time at end time
    const currentTime = Math.min(now, endTime);
    const timeRemaining = Math.max(0, endTime - now);

    // Time elapsed since last claim
    const timeElapsed = Math.max(0, currentTime - lastClaimTime);

    // Calculate pending in wei for precision
    const pendingWei = (ratePerSecondWei * BigInt(timeElapsed)) / BigInt(1e18);
    const pending = Number(pendingWei);

    // Total for 180 days
    const totalFor180DaysWei = (ratePerSecondWei * BigInt(this.TIME_REWARD_DURATION)) / BigInt(1e18);
    const totalFor180Days = Number(totalFor180DaysWei);

    // Calculate 24h earnings (overlap between [startTime, endTime] and [oneDayAgo, now])
    const oneDayAgo = now - 86400;
    const windowStart = Math.max(startTime, oneDayAgo);
    const windowEnd = Math.min(endTime, now);
    const last24h = windowEnd > windowStart ? ratePerSecond * (windowEnd - windowStart) : 0;

    // Total earned since start
    const totalEarned = ratePerSecond * Math.max(0, currentTime - startTime);

    return {
      pending,
      pendingWei: pendingWei.toString(),
      ratePerSecond,
      timeRemaining,
      totalFor180Days,
      last24h,
      totalEarned,
      totalClaimed: nft.total_claimed || 0,
      startTime,
      endTime,
      isSpecial: true,
      hasStarted: true,
      percentComplete: Math.min(100, ((now - startTime) / this.TIME_REWARD_DURATION) * 100)
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
      totalEarned: 0,
      totalClaimed: 0
    });

    // Update global stats
    this.incrementGlobalNFTsStarted();

    const ratePerSecond = this.getRatePerSecond(hostessIndex);
    const totalFor180Days = ratePerSecond * this.TIME_REWARD_DURATION;

    // Broadcast to connected clients
    this.ws.broadcast({
      type: 'SPECIAL_NFT_STARTED',
      data: {
        tokenId,
        hostessIndex,
        owner,
        startTime: blockTimestamp,
        ratePerSecond,
        totalFor180Days
      }
    });

    console.log(`[TimeRewardTracker] Special NFT ${tokenId} time rewards started at ${blockTimestamp}`);
  }

  /**
   * Increment the global NFTs started counter
   */
  incrementGlobalNFTsStarted() {
    const stats = this.db.getTimeRewardGlobalStats();
    if (stats) {
      this.db.updateTimeRewardGlobalStats({
        poolDeposited: stats.pool_deposited,
        poolRemaining: stats.pool_remaining,
        poolClaimed: stats.pool_claimed,
        nftsStarted: (stats.nfts_started || 0) + 1
      });
    }
  }

  /**
   * Sync time reward info from blockchain (for recovery/verification)
   * Queries the contract's getTimeRewardInfo() function
   */
  async syncFromBlockchain(tokenId) {
    try {
      const contract = new ethers.Contract(
        this.nftRewarderAddress,
        [
          'function getTimeRewardInfo(uint256) view returns (uint256 startTime, uint256 endTime, uint256 pending, uint256 claimed, uint256 ratePerSecond, uint256 timeRemaining, uint256 totalFor180Days, bool isActive)',
          'function nftMetadata(uint256) view returns (uint8 hostessIndex, bool registered, address owner)'
        ],
        this.provider
      );

      const [startTime, endTime, pending, claimed, ratePerSecond, timeRemaining, totalFor180Days, isActive] =
        await contract.getTimeRewardInfo(tokenId);

      if (startTime > 0n) {
        // Get metadata for hostess index and owner
        const [hostessIndex, registered, owner] = await contract.nftMetadata(tokenId);

        // Calculate last claim time from pending and rate
        // pending and ratePerSecond are both in wei, so division gives seconds
        // elapsedSinceClaim = pending / ratePerSecond
        // lastClaimTime = now - elapsedSinceClaim
        const pendingWei = Number(pending);
        const rateWei = Number(ratePerSecond);
        const elapsedSinceClaim = rateWei > 0 ? pendingWei / rateWei : 0;
        const now = Math.floor(Date.now() / 1000);
        const calculatedLastClaimTime = Math.floor(now - elapsedSinceClaim);

        // Ensure lastClaimTime is not before startTime (can happen due to timing)
        const lastClaimTime = Math.max(calculatedLastClaimTime, Number(startTime));

        this.db.insertTimeRewardNFT({
          tokenId,
          hostessIndex: Number(hostessIndex),
          owner,
          startTime: Number(startTime),
          lastClaimTime,
          totalEarned: 0,  // Let real-time calculation handle this
          totalClaimed: Number(claimed) / 1e18
        });

        console.log(`[TimeRewardTracker] Synced token ${tokenId} from blockchain: startTime=${startTime}, lastClaimTime=${lastClaimTime}, claimed=${ethers.formatEther(claimed)}`);
        return true;
      }

      return false;
    } catch (error) {
      console.error(`[TimeRewardTracker] Failed to sync ${tokenId} from blockchain:`, error.message);
      return false;
    }
  }

  /**
   * Sync global pool stats from blockchain
   */
  async syncPoolStatsFromBlockchain() {
    try {
      const contract = new ethers.Contract(
        this.nftRewarderAddress,
        [
          'function getTimeRewardPoolStats() view returns (uint256 deposited, uint256 remaining, uint256 claimed, uint256 specialNFTs)'
        ],
        this.provider
      );

      const [deposited, remaining, claimed, specialNFTs] = await contract.getTimeRewardPoolStats();

      this.db.updateTimeRewardGlobalStats({
        poolDeposited: ethers.formatEther(deposited),
        poolRemaining: ethers.formatEther(remaining),
        poolClaimed: ethers.formatEther(claimed),
        nftsStarted: Number(specialNFTs)
      });

      console.log(`[TimeRewardTracker] Synced pool stats: deposited=${ethers.formatEther(deposited)}, remaining=${ethers.formatEther(remaining)}, claimed=${ethers.formatEther(claimed)}, nfts=${specialNFTs}`);
      return true;
    } catch (error) {
      console.error('[TimeRewardTracker] Failed to sync pool stats:', error.message);
      return false;
    }
  }

  /**
   * Update database after successful claim
   */
  updateAfterClaim(tokenId, claimedAmount) {
    const now = Math.floor(Date.now() / 1000);
    this.db.updateTimeRewardClaim(tokenId, claimedAmount, now);

    // Update pool remaining
    const stats = this.db.getTimeRewardGlobalStats();
    if (stats) {
      const newRemaining = parseFloat(stats.pool_remaining || 0) - claimedAmount;
      const newClaimed = parseFloat(stats.pool_claimed || 0) + claimedAmount;
      this.db.updateTimeRewardGlobalStats({
        poolDeposited: stats.pool_deposited,
        poolRemaining: newRemaining.toString(),
        poolClaimed: newClaimed.toString(),
        nftsStarted: stats.nfts_started
      });
    }
  }

  /**
   * Broadcast TIME_REWARD_CLAIMED event to all connected clients
   */
  broadcastTimeRewardClaimed(data) {
    if (this.ws) {
      this.ws.broadcast({
        type: 'TIME_REWARD_CLAIMED',
        data: {
          tokenIds: data.tokenIds,
          recipient: data.recipient,
          totalAmount: data.totalAmount,
          txHash: data.txHash
        }
      });
      console.log(`[TimeRewardTracker] Broadcast TIME_REWARD_CLAIMED: ${data.tokenIds.length} NFTs, ${data.totalAmount.toFixed(2)} ROGUE`);
    }
  }

  /**
   * Update ownership in local database when NFT is transferred
   */
  updateOwnership(tokenId, newOwner) {
    if (!this.isSpecialNFT(tokenId)) return;

    const nft = this.db.getTimeRewardNFT(tokenId);
    if (nft) {
      this.db.updateTimeRewardNFTOwner(tokenId, newOwner.toLowerCase());
      console.log(`[TimeRewardTracker] Updated ownership for NFT ${tokenId} to ${newOwner}`);
    }
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
    let totalPendingWei = 0n;
    let totalEarned = 0;
    let totalClaimed = 0;
    let totalFor180Days = 0;

    for (const nft of nfts) {
      if (nft.timeReward.hasStarted) {
        totalPending += nft.timeReward.pending;
        totalPendingWei += BigInt(nft.timeReward.pendingWei);
        totalEarned += nft.timeReward.totalEarned;
        totalClaimed += nft.timeReward.totalClaimed;
        totalFor180Days += nft.timeReward.totalFor180Days;
      }
    }

    return {
      nftCount: nfts.filter(n => n.timeReward.hasStarted).length,
      totalPending,
      totalPendingWei: totalPendingWei.toString(),
      totalEarned,
      totalClaimed,
      totalFor180Days,
      nfts
    };
  }

  /**
   * Get global time reward stats
   */
  getGlobalStats() {
    const stats = this.db.getTimeRewardGlobalStats();

    return {
      totalPoolDeposited: parseFloat(stats?.pool_deposited || 0),
      totalPoolRemaining: parseFloat(stats?.pool_remaining || 0),
      totalPoolClaimed: parseFloat(stats?.pool_claimed || 0),
      totalSpecialNFTsStarted: stats?.nfts_started || 0,
      specialNFTRange: {
        start: this.SPECIAL_NFT_START_ID,
        end: this.SPECIAL_NFT_END_ID
      },
      rewardDurationDays: 180,
      lastUpdated: stats?.last_updated || 0
    };
  }

  /**
   * Get static data for client-side calculations (one DB query, cacheable)
   */
  getStaticData() {
    return this.db.getAllTimeRewardNFTs();
  }

  /**
   * Calculate 24h earnings for all special NFTs
   * Uses the overlap formula from the implementation doc
   */
  get24hEarnings() {
    const nfts = this.db.getAllTimeRewardNFTs();
    const now = Math.floor(Date.now() / 1000);
    const oneDayAgo = now - 86400;

    let global24h = 0;
    const hostess24h = new Array(8).fill(0);

    for (const nft of nfts) {
      // Note: getAllTimeRewardNFTs returns camelCase field names (startTime, hostessIndex)
      if (!nft.startTime) continue;

      const endTime = nft.startTime + this.TIME_REWARD_DURATION;
      const rate = this.getRatePerSecond(nft.hostessIndex);

      // Calculate overlap between [startTime, endTime] and [oneDayAgo, now]
      const windowStart = Math.max(nft.startTime, oneDayAgo);
      const windowEnd = Math.min(endTime, now);

      if (windowEnd > windowStart) {
        const nft24h = rate * (windowEnd - windowStart);
        global24h += nft24h;
        hostess24h[nft.hostessIndex] += nft24h;
      }
    }

    return { global: global24h, hostess: hostess24h };
  }
}

module.exports = TimeRewardTracker;
