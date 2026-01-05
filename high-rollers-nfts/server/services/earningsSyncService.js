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
  constructor(db, priceService, config, websocket = null) {
    this.db = db;
    this.priceService = priceService;
    this.config = config;
    this.ws = websocket;
    this.batchSize = 100;  // Fetch 100 NFTs per batch
    this.syncIntervalMs = 10000;  // 10 seconds between full syncs (for real-time updates)
    this.syncInterval = null;
    this.isRunning = false;

    this.rogueProvider = new ethers.JsonRpcProvider(config.ROGUE_RPC_URL);
    this.rewarderContract = new ethers.Contract(
      config.NFT_REWARDER_ADDRESS,
      config.NFT_REWARDER_ABI,
      this.rogueProvider
    );
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

      // Then update 24h and APY for each hostess type
      const hostessStats = this.db.getAllHostessRevenueStats();

      for (const stats of hostessStats) {
        const multiplier = BigInt(MULTIPLIERS[stats.hostess_index]);

        // Calculate 24h per NFT for this hostess type
        let last24hPerNft = 0n;
        if (totalMultiplierPoints > 0n) {
          last24hPerNft = (global24hWei * multiplier) / totalMultiplierPoints;
        }

        // Calculate APY
        let apyBasisPoints = 0;
        if (nftValueInRogueWei > 0n) {
          const annualProjection = last24hPerNft * 365n;
          apyBasisPoints = Number((annualProjection * 10000n) / nftValueInRogueWei);
        }

        this.db.updateHostessRevenueStats(stats.hostess_index, {
          nftCount: stats.nft_count,
          totalPoints: stats.total_points,
          shareBasisPoints: stats.share_basis_points,
          last24hPerNft: last24hPerNft.toString(),
          apyBasisPoints: apyBasisPoints
        });
      }
    } catch (error) {
      console.error('[EarningsSync] Failed to sync hostess stats:', error.message);
    }
  }

  sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
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
