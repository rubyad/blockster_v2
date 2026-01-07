/**
 * EarningsSyncService - Background service to sync NFT earnings from contract
 *
 * The contract stores totalEarned and pendingAmount per NFT.
 * The server calculates last24Hours and APY off-chain using the proportional
 * distribution formula. This avoids unbounded array growth on-chain.
 *
 * Key Insight: Per-NFT 24h earnings is just a proportional share of global 24h rewards:
 *   nft_24h = global_24h × (nft_multiplier / totalMultiplierPoints)
 *
 * This is O(1) - one query for global 24h, then simple multiplication per NFT.
 */

const { ethers } = require('ethers');

const MULTIPLIERS = [100, 90, 80, 70, 60, 50, 40, 30];  // hostess 0-7
const HOSTESS_NAMES = [
  'Penelope Fatale', 'Mia Siren', 'Cleo Enchante', 'Sophia Spark',
  'Luna Mirage', 'Aurora Seductra', 'Scarlett Ember', 'Vivienne Allure'
];

class EarningsSyncService {
  constructor(db, priceService, config, websocket = null, timeRewardTracker = null) {
    this.db = db;
    this.priceService = priceService;
    this.config = config;
    this.ws = websocket;
    this.timeRewardTracker = timeRewardTracker;
    this.batchSize = 100;  // Fetch 100 NFTs per batch
    this.syncIntervalMs = 60000;  // 60 seconds between full syncs
    this.syncInterval = null;
    this.isRunning = false;
    this.isSyncing = false;  // Mutex to prevent concurrent syncs

    // Special NFT constants
    this.SPECIAL_NFT_START_ID = 2340;
    this.SPECIAL_NFT_END_ID = 2700;

    this.rogueProvider = new ethers.JsonRpcProvider(config.ROGUE_RPC_URL);
    this.rewarderContract = new ethers.Contract(
      config.NFT_REWARDER_ADDRESS,
      config.NFT_REWARDER_ABI,
      this.rogueProvider
    );
  }

  /**
   * Set TimeRewardTracker reference (for combined earnings calculations)
   */
  setTimeRewardTracker(tracker) {
    this.timeRewardTracker = tracker;
  }

  /**
   * Check if a token ID is a special NFT (has time rewards)
   */
  isSpecialNFT(tokenId) {
    return tokenId >= this.SPECIAL_NFT_START_ID && tokenId <= this.SPECIAL_NFT_END_ID;
  }

  /**
   * Set WebSocket server reference (for broadcasting sync completion)
   */
  setWebSocket(websocket) {
    this.ws = websocket;
  }

  async start() {
    if (this.isRunning) return;
    this.isRunning = true;

    console.log('[EarningsSync] Starting background sync loop');

    // Initial sync
    await this.syncAllNFTEarnings();

    // Continuous loop
    this.syncInterval = setInterval(async () => {
      if (this.isRunning) {
        await this.syncAllNFTEarnings();
      }
    }, this.syncIntervalMs);
  }

  /**
   * Sync all NFT earnings from contract to SQLite in batches.
   * Contract provides: totalEarned, pendingAmount, hostessIndex
   * Server calculates: last24h (from reward_events), APY (from 24h and NFT value)
   */
  async syncAllNFTEarnings() {
    // Mutex: Skip if already syncing (prevents overlapping syncs)
    if (this.isSyncing) {
      return;
    }
    this.isSyncing = true;

    try {
      const allNFTs = this.db.getAllNFTs(10000, 0);  // Get all NFTs
      const total = allNFTs.length;

      if (total === 0) {
        console.log('[EarningsSync] No NFTs to sync');
        return;
      }

      // ============================================================
      // STEP 1: Get global 24h rewards ONCE (O(1) query)
      // ============================================================
      const oneDayAgo = Math.floor(Date.now() / 1000) - 86400;
      const global24hWei = BigInt(this.db.getRewardsSince(oneDayAgo) || '0');
      const totalMultiplierPoints = BigInt(this.db.getTotalMultiplierPoints() || '109390');

      // Get NFT value in ROGUE for APY calculation
      const nftValueInRogue = this.priceService?.getNftValueInRogue() || 0;
      const nftValueInRogueWei = nftValueInRogue > 0
        ? BigInt(Math.floor(nftValueInRogue * 1e18))
        : BigInt('9600000000000000000000000');  // 9.6M ROGUE default

      console.log(`[EarningsSync] Starting sync of ${total} NFTs in batches of ${this.batchSize}`);
      console.log(`[EarningsSync] Global 24h: ${ethers.formatEther(global24hWei)} ROGUE, Total points: ${totalMultiplierPoints}`);

      for (let i = 0; i < total; i += this.batchSize) {
        const batch = allNFTs.slice(i, i + this.batchSize);
        const tokenIds = batch.map(nft => nft.token_id);

        try {
          // ============================================================
          // STEP 2: Get on-chain earnings for batch (returns 3 separate arrays)
          // ============================================================
          const [totalEarnedArr, pendingAmountsArr, hostessIndicesArr] = await this.rewarderContract.getBatchNFTEarnings(tokenIds);

          // ============================================================
          // STEP 3: Calculate off-chain metrics for each NFT
          // ============================================================
          for (let j = 0; j < tokenIds.length; j++) {
            const tokenId = tokenIds[j];
            const totalEarned = totalEarnedArr[j];
            const pendingAmount = pendingAmountsArr[j];
            const hostessIndex = Number(hostessIndicesArr[j]);
            const multiplier = BigInt(MULTIPLIERS[hostessIndex] || 30);

            // Calculate this NFT's proportional share of global 24h
            // Formula: nft_24h = global_24h × multiplier / totalMultiplierPoints
            let last24hEarned = 0n;
            if (totalMultiplierPoints > 0n) {
              last24hEarned = (global24hWei * multiplier) / totalMultiplierPoints;
            }

            // Calculate APY: (annual_projection / nft_value) × 10000 basis points
            // Annual = last24h × 365
            let apyBasisPoints = 0;
            if (nftValueInRogueWei > 0n) {
              const annualProjection = last24hEarned * 365n;
              apyBasisPoints = Number((annualProjection * 10000n) / nftValueInRogueWei);
            }

            // Update SQLite with combined on-chain + off-chain data
            this.db.updateNFTEarnings(tokenId, {
              totalEarned: totalEarned.toString(),
              pendingAmount: pendingAmount.toString(),
              last24hEarned: last24hEarned.toString(),      // Calculated off-chain
              apyBasisPoints: apyBasisPoints                 // Calculated off-chain
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

      // Recalculate global 24h before syncing stats (may have changed during batch sync)
      const finalGlobal24hWei = BigInt(this.db.getRewardsSince(oneDayAgo) || '0');

      // If global 24h changed during sync, update all NFT last24h values
      if (finalGlobal24hWei !== global24hWei) {
        console.log(`[EarningsSync] Rewards changed during sync (${ethers.formatEther(global24hWei)} → ${ethers.formatEther(finalGlobal24hWei)}), updating per-NFT 24h`);
        this.updateAllNFTLast24h(finalGlobal24hWei, totalMultiplierPoints, nftValueInRogueWei);
      }

      // Also sync global stats
      await this.syncGlobalStats(finalGlobal24hWei, nftValueInRogueWei);

      // Update hostess revenue stats
      this.syncHostessStats(finalGlobal24hWei, totalMultiplierPoints, nftValueInRogueWei);

      console.log(`[EarningsSync] Sync complete`);

      // Broadcast sync completion to all connected clients
      if (this.ws) {
        const globalStats = this.db.getGlobalRevenueStats();
        const hostessStats = this.db.getAllHostessRevenueStats();
        this.ws.broadcast({
          type: 'EARNINGS_SYNCED',
          data: {
            totalRewardsReceived: globalStats?.total_rewards_received || '0',
            totalRewardsDistributed: globalStats?.total_rewards_distributed || '0',
            rewardsLast24h: globalStats?.rewards_last_24h || '0',
            overallAPY: globalStats?.overall_apy_basis_points || 0,
            hostessStats: hostessStats,
            timestamp: Date.now()
          }
        });
      }
    } catch (error) {
      console.error('[EarningsSync] Sync failed:', error.message);
    } finally {
      this.isSyncing = false;  // Release mutex
    }
  }

  async syncGlobalStats(global24hWei, nftValueInRogueWei) {
    try {
      // Get on-chain totals
      const [totalRewardsReceived, totalRewardsDistributed] = await Promise.all([
        this.rewarderContract.totalRewardsReceived(),
        this.rewarderContract.totalRewardsDistributed()
      ]);

      const totalNFTs = BigInt(this.db.getTotalNFTs());
      const totalMultiplierPoints = this.db.getTotalMultiplierPoints();

      // Calculate overall APY (average across all NFTs weighted by multiplier)
      let overallAPY = 0;
      if (nftValueInRogueWei > 0n && totalNFTs > 0n) {
        // Average 24h per NFT = global24h / totalNFTs
        const avg24hPerNFT = global24hWei / totalNFTs;
        const annualProjection = avg24hPerNFT * 365n;
        overallAPY = Number((annualProjection * 10000n) / nftValueInRogueWei);
      }

      this.db.updateGlobalRevenueStats({
        totalRewardsReceived: totalRewardsReceived.toString(),
        totalRewardsDistributed: totalRewardsDistributed.toString(),
        rewardsLast24h: global24hWei.toString(),
        overallAPY: overallAPY
      });
    } catch (error) {
      console.error('[EarningsSync] Failed to sync global stats:', error.message);
    }
  }

  /**
   * Quick update of all NFT last24h/APY when global 24h changes mid-sync
   * Uses SQL UPDATE with CASE for each hostess type - much faster than individual updates
   */
  updateAllNFTLast24h(global24hWei, totalMultiplierPoints, nftValueInRogueWei) {
    // Calculate last24h and APY for each hostess type (0-7)
    for (let hostessIndex = 0; hostessIndex < 8; hostessIndex++) {
      const multiplier = BigInt(MULTIPLIERS[hostessIndex]);

      let last24hEarned = 0n;
      if (totalMultiplierPoints > 0n) {
        last24hEarned = (global24hWei * multiplier) / totalMultiplierPoints;
      }

      let apyBasisPoints = 0;
      if (nftValueInRogueWei > 0n) {
        const annualProjection = last24hEarned * 365n;
        apyBasisPoints = Number((annualProjection * 10000n) / nftValueInRogueWei);
      }

      // Update all NFTs of this hostess type in one query
      this.db.updateNFTLast24hByHostess(hostessIndex, last24hEarned.toString(), apyBasisPoints);
    }
  }

  syncHostessStats(global24hWei, totalMultiplierPoints, nftValueInRogueWei) {
    try {
      // First recalculate counts
      this.db.recalculateHostessRevenueStats();

      // Get time reward 24h per hostess (for combined calculations)
      const hostessTime24h = this.getHostessTime24h();

      // Then update 24h and APY for each hostess type
      const hostessStats = this.db.getAllHostessRevenueStats();

      for (const stats of hostessStats) {
        const hostessIndex = stats.hostess_index;
        const multiplier = BigInt(MULTIPLIERS[hostessIndex]);

        // ========== Revenue Sharing 24h/APY ==========
        let revenue24hPerNft = 0n;
        if (totalMultiplierPoints > 0n) {
          revenue24hPerNft = (global24hWei * multiplier) / totalMultiplierPoints;
        }

        let revenueApyBasisPoints = 0;
        if (nftValueInRogueWei > 0n) {
          const annualProjection = revenue24hPerNft * 365n;
          revenueApyBasisPoints = Number((annualProjection * 10000n) / nftValueInRogueWei);
        }

        // ========== Time Rewards 24h/APY (for special NFTs only) ==========
        let time24hPerNft = 0n;
        let timeApyBasisPoints = 0;

        // Count how many special NFTs of this hostess type exist
        const specialNFTs = this.db.getSpecialNFTsByHostess(hostessIndex);
        const specialCount = specialNFTs.length;

        if (specialCount > 0 && this.timeRewardTracker) {
          // Time 24h per NFT (same for all NFTs of this hostess type since rate is constant)
          const totalHostessTime24h = BigInt(hostessTime24h[hostessIndex] || '0');
          time24hPerNft = specialCount > 0 ? totalHostessTime24h / BigInt(specialCount) : 0n;

          // Time APY (based on 180-day earning rate annualized)
          timeApyBasisPoints = this.calculateTimeAPY(hostessIndex, nftValueInRogueWei);
        }

        // Store revenue and time values separately
        // UI/API will calculate combined totals when needed
        this.db.updateHostessRevenueStats(hostessIndex, {
          nftCount: stats.nft_count,
          totalPoints: stats.total_points,
          shareBasisPoints: stats.share_basis_points,
          // Revenue sharing values
          last24hPerNft: revenue24hPerNft.toString(),
          apyBasisPoints: revenueApyBasisPoints,
          // Time reward values (for special NFTs)
          time24hPerNft: time24hPerNft.toString(),
          timeApyBasisPoints: timeApyBasisPoints,
          specialNftCount: specialCount
        });
      }
    } catch (error) {
      console.error('[EarningsSync] Failed to sync hostess stats:', error.message);
    }
  }

  sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  /**
   * Calculate time-based 24h earnings for an NFT
   * Time rewards are constant rate, so 24h = rate × 86400 (if within active period)
   *
   * @param tokenId NFT token ID
   * @param hostessIndex Hostess type (0-7)
   * @returns 24h earnings in wei (BigInt string)
   */
  calculateTime24hEarnings(tokenId, hostessIndex) {
    if (!this.timeRewardTracker || !this.isSpecialNFT(tokenId)) {
      return '0';
    }

    const nft = this.db.getTimeRewardNFT(tokenId);
    if (!nft || !nft.start_time) return '0';

    const now = Math.floor(Date.now() / 1000);
    const oneDayAgo = now - 86400;
    const endTime = nft.start_time + (180 * 24 * 60 * 60);  // 180 days

    // Calculate overlap between [startTime, endTime] and [oneDayAgo, now]
    const windowStart = Math.max(nft.start_time, oneDayAgo);
    const windowEnd = Math.min(endTime, now);

    if (windowEnd <= windowStart) return '0';

    const secondsInWindow = windowEnd - windowStart;
    const rateWei = this.timeRewardTracker.getRatePerSecondWei(hostessIndex);

    // earnings = rate × seconds
    const earnings = (rateWei * BigInt(secondsInWindow)) / BigInt(1e18);
    return earnings.toString();
  }

  /**
   * Get time reward pending amount for an NFT (in wei string)
   */
  getTimePending(tokenId) {
    if (!this.timeRewardTracker || !this.isSpecialNFT(tokenId)) {
      return '0';
    }

    const timeReward = this.timeRewardTracker.calculatePendingReward(tokenId);
    return timeReward.pendingWei || '0';
  }

  /**
   * Get total time reward earned (pending + claimed) for an NFT (in wei string)
   */
  getTimeTotalEarned(tokenId) {
    if (!this.timeRewardTracker || !this.isSpecialNFT(tokenId)) {
      return '0';
    }

    const nft = this.db.getTimeRewardNFT(tokenId);
    if (!nft || !nft.start_time) return '0';

    const timeReward = this.timeRewardTracker.calculatePendingReward(tokenId);
    // totalEarned = pending + claimed
    const totalWei = BigInt(Math.floor(timeReward.totalEarned * 1e18));
    return totalWei.toString();
  }

  /**
   * Calculate time-based APY for a hostess type
   * Formula: (totalFor180Days × 365/180) / nftValue × 10000 (basis points)
   *
   * @param hostessIndex Hostess type (0-7)
   * @param nftValueInRogueWei NFT value in wei
   * @returns APY in basis points (10000 = 100%)
   */
  calculateTimeAPY(hostessIndex, nftValueInRogueWei) {
    if (!this.timeRewardTracker || nftValueInRogueWei === 0n) {
      return 0;
    }

    const rateWei = this.timeRewardTracker.getRatePerSecondWei(hostessIndex);
    const duration = BigInt(180 * 24 * 60 * 60);  // 180 days in seconds

    // Total for 180 days
    const totalFor180Days = (rateWei * duration) / BigInt(1e18);

    // Annualize: × 365/180 ≈ × 2.0278
    const annualized = (totalFor180Days * 365n) / 180n;

    // APY = annualized / nftValue × 10000
    const apyBasisPoints = Number((annualized * 10000n * BigInt(1e18)) / nftValueInRogueWei);
    return apyBasisPoints;
  }

  /**
   * Get global time reward 24h earnings (sum across all special NFTs)
   */
  getGlobalTime24h() {
    if (!this.timeRewardTracker) return '0';

    const { global } = this.timeRewardTracker.get24hEarnings();
    return BigInt(Math.floor(global * 1e18)).toString();
  }

  /**
   * Get time reward 24h earnings per hostess type
   * Returns array of BigInt strings indexed by hostess (0-7)
   */
  getHostessTime24h() {
    if (!this.timeRewardTracker) {
      return new Array(8).fill('0');
    }

    const { hostess } = this.timeRewardTracker.get24hEarnings();
    return hostess.map(h => BigInt(Math.floor(h * 1e18)).toString());
  }

  stop() {
    this.isRunning = false;
    if (this.syncInterval) {
      clearInterval(this.syncInterval);
      this.syncInterval = null;
    }
    console.log('[EarningsSync] Stopped');
  }
}

module.exports = EarningsSyncService;
