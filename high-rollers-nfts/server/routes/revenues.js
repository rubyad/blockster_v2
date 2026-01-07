/**
 * Revenue API Routes - NFT revenue sharing endpoints
 */

const express = require('express');
const { ethers } = require('ethers');
const adminTxQueue = require('../services/adminTxQueue');

const HOSTESS_NAMES = [
  'Penelope Fatale', 'Mia Siren', 'Cleo Enchante', 'Sophia Spark',
  'Luna Mirage', 'Aurora Seductra', 'Scarlett Ember', 'Vivienne Allure'
];

const MULTIPLIERS = [100, 90, 80, 70, 60, 50, 40, 30];

/**
 * Format wei amount to ROGUE with proper decimals
 */
function formatROGUE(weiAmount) {
  if (!weiAmount || weiAmount === '0') return '0';
  return ethers.formatEther(weiAmount);
}

// TimeRewardTracker will be set by setTimeRewardTracker()
let timeRewardTracker = null;

module.exports = (db, priceService) => {
  const router = express.Router();

  /**
   * Set the TimeRewardTracker service (called from index.js after initialization)
   */
  router.setTimeRewardTracker = (tracker) => {
    timeRewardTracker = tracker;
    console.log('[Revenues] TimeRewardTracker attached');
  };

  // GET /api/revenues/stats - Global revenue statistics
  router.get('/stats', (req, res) => {
    try {
      const stats = db.getGlobalRevenueStats();
      const hostessStats = db.getAllHostessRevenueStats();

      // Get global time reward stats for combined totals
      let timeRewardTotal = '0';
      let timeReward24h = '0';
      if (timeRewardTracker) {
        const timeStats = timeRewardTracker.getGlobalStats();
        // Total earned = pool deposited - pool remaining
        const totalTimeEarned = (timeStats.totalPoolDeposited - timeStats.totalPoolRemaining) * 1e18;
        timeRewardTotal = BigInt(Math.floor(totalTimeEarned)).toString();

        // Get 24h time rewards
        const { global: global24h } = timeRewardTracker.get24hEarnings();
        timeReward24h = BigInt(Math.floor(global24h * 1e18)).toString();
      }

      // Calculate combined totals (revenue + time rewards)
      const revenueTotal = BigInt(stats?.total_rewards_received || '0');
      const revenue24h = BigInt(stats?.rewards_last_24h || '0');
      const combinedTotal = revenueTotal + BigInt(timeRewardTotal);
      const combined24h = revenue24h + BigInt(timeReward24h);

      res.json({
        // Revenue sharing only (for backwards compatibility)
        totalRewardsReceived: formatROGUE(stats?.total_rewards_received),
        totalRewardsDistributed: formatROGUE(stats?.total_rewards_distributed),
        rewardsLast24Hours: formatROGUE(stats?.rewards_last_24h),
        // Time rewards only
        timeRewardsTotal: formatROGUE(timeRewardTotal),
        timeRewards24Hours: formatROGUE(timeReward24h),
        // Combined totals (revenue + time)
        combinedTotal: formatROGUE(combinedTotal.toString()),
        combined24Hours: formatROGUE(combined24h.toString()),
        overallAPY: (stats?.overall_apy_basis_points || 0) / 100, // Convert to percentage
        hostessTypes: hostessStats.map(h => {
          const revenueApy = (h.apy_basis_points || 0) / 100;
          const timeApy = (h.time_apy_basis_points || 0) / 100;
          const revenueLast24h = formatROGUE(h.last_24h_per_nft);
          const timeLast24h = formatROGUE(h.time_24h_per_nft);

          return {
            index: h.hostess_index,
            name: HOSTESS_NAMES[h.hostess_index],
            multiplier: MULTIPLIERS[h.hostess_index],
            nftCount: h.nft_count,
            totalPoints: h.total_points,
            sharePercent: (h.share_basis_points || 0) / 100,
            // Revenue sharing stats
            last24HPerNFT: revenueLast24h,
            apy: revenueApy,
            // Time reward stats (special NFTs only)
            specialNftCount: h.special_nft_count || 0,
            timeLast24HPerNFT: timeLast24h,
            timeApy: timeApy,
            // Combined totals
            combinedLast24HPerNFT: formatROGUE(
              (BigInt(h.last_24h_per_nft || '0') + BigInt(h.time_24h_per_nft || '0')).toString()
            ),
            combinedApy: revenueApy + timeApy
          };
        }),
        lastUpdated: stats?.last_updated || 0
      });
    } catch (error) {
      console.error('[Revenues] /stats error:', error);
      res.status(500).json({ error: error.message });
    }
  });

  // GET /api/revenues/nft/:tokenId - Earnings for specific NFT
  router.get('/nft/:tokenId', (req, res) => {
    try {
      const tokenId = parseInt(req.params.tokenId);

      if (isNaN(tokenId) || tokenId < 1) {
        return res.status(400).json({ error: 'Invalid token ID' });
      }

      const nftEarnings = db.getNFTEarnings(tokenId);

      if (!nftEarnings) {
        // NFT exists but no earnings synced yet
        const nft = db.getNFT(tokenId);
        if (!nft) {
          return res.status(404).json({ error: 'NFT not found' });
        }

        // Return with zero earnings
        return res.json({
          tokenId,
          hostessName: nft.hostess_name,
          hostessIndex: nft.hostess_index,
          multiplier: MULTIPLIERS[nft.hostess_index],
          totalEarned: '0',
          pendingAmount: '0',
          last24Hours: '0',
          apy: 0,
          owner: nft.owner
        });
      }

      res.json({
        tokenId,
        hostessName: nftEarnings.hostess_name,
        hostessIndex: nftEarnings.hostess_index,
        multiplier: MULTIPLIERS[nftEarnings.hostess_index],
        totalEarned: formatROGUE(nftEarnings.total_earned),
        pendingAmount: formatROGUE(nftEarnings.pending_amount),
        last24Hours: formatROGUE(nftEarnings.last_24h_earned),
        apy: (nftEarnings.apy_basis_points || 0) / 100,
        owner: nftEarnings.owner
      });
    } catch (error) {
      console.error('[Revenues] /nft/:tokenId error:', error);
      res.status(500).json({ error: error.message });
    }
  });

  // GET /api/revenues/user/:address - All earnings for a user's NFTs
  router.get('/user/:address', (req, res) => {
    try {
      const { address } = req.params;

      if (!ethers.isAddress(address)) {
        return res.status(400).json({ error: 'Invalid address' });
      }

      const userNFTs = db.getNFTEarningsByOwner(address);

      let totalEarnedWei = 0n;
      let totalPendingWei = 0n;
      let totalLast24hWei = 0n;
      let totalMultiplier = 0;

      const nfts = userNFTs.map(nft => {
        const totalEarned = BigInt(nft.total_earned || '0');
        const pendingAmount = BigInt(nft.pending_amount || '0');
        const last24hEarned = BigInt(nft.last_24h_earned || '0');
        const multiplier = MULTIPLIERS[nft.hostess_index];

        totalEarnedWei += totalEarned;
        totalPendingWei += pendingAmount;
        totalLast24hWei += last24hEarned;
        totalMultiplier += multiplier;

        return {
          tokenId: nft.token_id,
          hostessName: nft.hostess_name,
          hostessIndex: nft.hostess_index,
          multiplier,
          totalEarned: formatROGUE(nft.total_earned),
          pendingAmount: formatROGUE(nft.pending_amount),
          last24Hours: formatROGUE(nft.last_24h_earned),
          apy: (nft.apy_basis_points || 0) / 100
        };
      });

      // Calculate weighted average APY
      let weightedAPY = 0;
      if (totalMultiplier > 0) {
        let apySum = 0;
        nfts.forEach(nft => {
          apySum += nft.apy * nft.multiplier;
        });
        weightedAPY = apySum / totalMultiplier;
      }

      res.json({
        address: address.toLowerCase(),
        nftCount: nfts.length,
        totalMultiplier,
        totalEarned: formatROGUE(totalEarnedWei.toString()),
        totalPending: formatROGUE(totalPendingWei.toString()),
        totalLast24Hours: formatROGUE(totalLast24hWei.toString()),
        overallAPY: weightedAPY,
        nfts,
        canWithdraw: totalPendingWei > 0n
      });
    } catch (error) {
      console.error('[Revenues] /user/:address error:', error);
      res.status(500).json({ error: error.message });
    }
  });

  // GET /api/revenues/history - Recent reward events
  router.get('/history', (req, res) => {
    try {
      const limit = Math.min(parseInt(req.query.limit) || 50, 100);
      const offset = parseInt(req.query.offset) || 0;
      const events = db.getRewardEvents(limit, offset);
      const totalCount = db.getRewardEventsCount();

      res.json({
        events: events.map(e => ({
          id: e.id,
          commitmentHash: e.commitment_hash,
          amount: formatROGUE(e.amount),
          amountWei: e.amount,
          timestamp: e.timestamp,
          blockNumber: e.block_number,
          txHash: e.tx_hash
        })),
        pagination: {
          limit,
          offset,
          total: totalCount,
          hasMore: offset + limit < totalCount
        }
      });
    } catch (error) {
      console.error('[Revenues] /history error:', error);
      res.status(500).json({ error: error.message });
    }
  });

  // GET /api/revenues/withdrawals/:address - User's withdrawal history
  router.get('/withdrawals/:address', (req, res) => {
    try {
      const { address } = req.params;

      if (!ethers.isAddress(address)) {
        return res.status(400).json({ error: 'Invalid address' });
      }

      const withdrawals = db.getRewardWithdrawals(address);

      res.json({
        address: address.toLowerCase(),
        withdrawals: withdrawals.map(w => ({
          id: w.id,
          amount: formatROGUE(w.amount),
          amountWei: w.amount,
          tokenIds: JSON.parse(w.token_ids),
          txHash: w.tx_hash,
          timestamp: w.timestamp
        }))
      });
    } catch (error) {
      console.error('[Revenues] /withdrawals/:address error:', error);
      res.status(500).json({ error: error.message });
    }
  });

  // GET /api/prices - Current ROGUE and ETH prices
  router.get('/prices', (req, res) => {
    try {
      if (!priceService) {
        return res.status(503).json({ error: 'Price service not available' });
      }

      const prices = priceService.getPrices();
      res.json(prices);
    } catch (error) {
      console.error('[Revenues] /prices error:', error);
      res.status(500).json({ error: error.message });
    }
  });

  // GET /api/prices/nft-value - NFT value in ROGUE and USD
  router.get('/prices/nft-value', (req, res) => {
    try {
      if (!priceService) {
        return res.status(503).json({ error: 'Price service not available' });
      }

      const prices = priceService.getPrices();
      const nftValueRogue = priceService.getNftValueInRogue();
      const nftValueUsd = priceService.getNftValueInUsd();

      res.json({
        nftValueRogue,
        nftValueUsd,
        mintPriceEth: 0.32,
        ethPrice: prices.eth.usdPrice,
        roguePrice: prices.rogue.usdPrice,
        lastUpdated: prices.lastUpdated
      });
    } catch (error) {
      console.error('[Revenues] /prices/nft-value error:', error);
      res.status(500).json({ error: error.message });
    }
  });

  // POST /api/revenues/recalculate-stats - Recalculate all stats (admin)
  router.post('/recalculate-stats', (req, res) => {
    try {
      const hostessStats = db.recalculateHostessRevenueStats();
      res.json({
        success: true,
        hostessStats: hostessStats.map(h => ({
          index: h.hostess_index,
          name: HOSTESS_NAMES[h.hostess_index],
          nftCount: h.nft_count,
          totalPoints: h.total_points,
          sharePercent: (h.share_basis_points || 0) / 100
        }))
      });
    } catch (error) {
      console.error('[Revenues] /recalculate-stats error:', error);
      res.status(500).json({ error: error.message });
    }
  });

  // POST /api/revenues/withdraw - Withdraw pending rewards
  router.post('/withdraw', async (req, res) => {
    try {
      const { address } = req.body;

      if (!address || !ethers.isAddress(address)) {
        return res.status(400).json({ error: 'Invalid wallet address' });
      }

      // Get user's NFTs and verify they have pending rewards
      const userNFTs = db.getNFTEarningsByOwner(address);

      if (!userNFTs || userNFTs.length === 0) {
        return res.status(400).json({ error: 'No NFTs found for this address' });
      }

      // Collect token IDs with pending rewards
      const tokenIdsWithPending = [];
      let totalPendingWei = 0n;

      for (const nft of userNFTs) {
        const pending = BigInt(nft.pending_amount || '0');
        if (pending > 0n) {
          tokenIdsWithPending.push(nft.token_id);
          totalPendingWei += pending;
        }
      }

      if (tokenIdsWithPending.length === 0) {
        return res.status(400).json({ error: 'No pending rewards to withdraw' });
      }

      // Verify ownership on Arbitrum (sync first)
      // The OwnerSyncService should have already synced, but let's verify
      console.log(`[Revenues] Withdraw request from ${address} for ${tokenIdsWithPending.length} NFTs, total: ${formatROGUE(totalPendingWei.toString())} ROGUE`);

      // Execute withdrawal via AdminTxQueue (serialized to prevent nonce conflicts)
      const receipt = await adminTxQueue.withdrawTo(tokenIdsWithPending, address);
      console.log(`[Revenues] Withdrawal confirmed: ${receipt.hash}`);

      // Record the withdrawal
      db.recordRewardWithdrawal({
        userAddress: address.toLowerCase(),
        amount: totalPendingWei.toString(),
        tokenIds: JSON.stringify(tokenIdsWithPending),
        txHash: receipt.hash,
        timestamp: Math.floor(Date.now() / 1000)
      });

      res.json({
        success: true,
        txHash: receipt.hash,
        amount: formatROGUE(totalPendingWei.toString()),
        amountWei: totalPendingWei.toString(),
        tokenIds: tokenIdsWithPending,
        recipient: address
      });
    } catch (error) {
      console.error('[Revenues] /withdraw error:', error);
      res.status(500).json({
        error: error.reason || error.message || 'Withdrawal failed'
      });
    }
  });

  // ============ Time-Based Rewards Endpoints (Phase 3) ============

  /**
   * GET /api/revenues/time-rewards/stats
   * Get global time reward statistics
   */
  router.get('/time-rewards/stats', (req, res) => {
    try {
      if (!timeRewardTracker) {
        return res.status(503).json({ error: 'Time reward service not available' });
      }

      const stats = timeRewardTracker.getGlobalStats();
      const earnings24h = timeRewardTracker.get24hEarnings();

      res.json({
        ...stats,
        global24h: earnings24h.global,
        hostess24h: earnings24h.hostess.map((amount, index) => ({
          hostessIndex: index,
          hostessName: HOSTESS_NAMES[index],
          amount24h: amount
        }))
      });
    } catch (error) {
      console.error('[Revenues] /time-rewards/stats error:', error);
      res.status(500).json({ error: error.message });
    }
  });

  /**
   * GET /api/revenues/time-rewards/nft/:tokenId
   * Get time reward info for a specific NFT
   */
  router.get('/time-rewards/nft/:tokenId', (req, res) => {
    try {
      if (!timeRewardTracker) {
        return res.status(503).json({ error: 'Time reward service not available' });
      }

      const tokenId = parseInt(req.params.tokenId);

      if (isNaN(tokenId) || tokenId < 1) {
        return res.status(400).json({ error: 'Invalid token ID' });
      }

      const info = timeRewardTracker.calculatePendingReward(tokenId);

      // Get NFT metadata for hostess name
      const nft = db.getNFT(tokenId);

      res.json({
        tokenId,
        hostessName: nft?.hostess_name || HOSTESS_NAMES[info.hostessIndex] || 'Unknown',
        hostessIndex: nft?.hostess_index,
        ...info
      });
    } catch (error) {
      console.error('[Revenues] /time-rewards/nft/:tokenId error:', error);
      res.status(500).json({ error: error.message });
    }
  });

  /**
   * GET /api/revenues/time-rewards/user/:address
   * Get time reward info for all special NFTs owned by a wallet
   */
  router.get('/time-rewards/user/:address', (req, res) => {
    try {
      if (!timeRewardTracker) {
        return res.status(503).json({ error: 'Time reward service not available' });
      }

      const address = req.params.address;

      if (!ethers.isAddress(address)) {
        return res.status(400).json({ error: 'Invalid address' });
      }

      const stats = timeRewardTracker.getWalletTimeRewardStats(address);

      res.json({
        address: address.toLowerCase(),
        ...stats,
        nfts: stats.nfts.map(nft => ({
          tokenId: nft.token_id,
          hostessName: nft.hostess_name || HOSTESS_NAMES[nft.hostess_index],
          hostessIndex: nft.hostess_index,
          owner: nft.owner,
          ...nft.timeReward
        }))
      });
    } catch (error) {
      console.error('[Revenues] /time-rewards/user/:address error:', error);
      res.status(500).json({ error: error.message });
    }
  });

  /**
   * GET /api/revenues/time-rewards/static-data
   * Returns ONLY static NFT data - no calculations
   * Client calculates everything from this + hardcoded constants
   * Response is cacheable - data only changes on mint/claim events
   */
  router.get('/time-rewards/static-data', (req, res) => {
    try {
      // Single database query - no joins, no calculations
      const nfts = db.getAllTimeRewardNFTs();

      // Cache for 60 seconds (data rarely changes)
      res.set('Cache-Control', 'public, max-age=60');
      res.json(nfts);
    } catch (error) {
      console.error('[Revenues] /time-rewards/static-data error:', error);
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
      if (!timeRewardTracker) {
        return res.status(503).json({ error: 'Time reward service not available' });
      }

      const { tokenIds, recipient } = req.body;

      if (!tokenIds || !Array.isArray(tokenIds) || tokenIds.length === 0) {
        return res.status(400).json({ error: 'tokenIds array required' });
      }

      if (!recipient || !ethers.isAddress(recipient)) {
        return res.status(400).json({ error: 'Valid recipient address required' });
      }

      // Calculate total pending before claiming
      let totalPending = 0;
      const validTokenIds = [];

      for (const tokenId of tokenIds) {
        const info = timeRewardTracker.calculatePendingReward(tokenId);
        if (info.hasStarted && info.pending > 0) {
          totalPending += info.pending;
          validTokenIds.push(tokenId);
        }
      }

      if (validTokenIds.length === 0) {
        return res.status(400).json({ error: 'No pending time rewards to claim' });
      }

      console.log(`[Revenues] Time rewards claim request: ${validTokenIds.length} NFTs, total: ${totalPending.toFixed(2)} ROGUE to ${recipient}`);

      // Queue the claim transaction via admin wallet
      const receipt = await adminTxQueue.claimTimeRewards(validTokenIds, recipient);
      console.log(`[Revenues] Time rewards claim confirmed: ${receipt.hash}`);

      // Update local database after successful claim
      for (const tokenId of validTokenIds) {
        const info = timeRewardTracker.calculatePendingReward(tokenId);
        timeRewardTracker.updateAfterClaim(tokenId, info.pending);

        // Record claim in claims table
        db.recordTimeRewardClaim({
          tokenId,
          recipient,
          amount: info.pending,
          txHash: receipt.hash
        });
      }

      // Broadcast TIME_REWARD_CLAIMED event to all connected clients
      timeRewardTracker.broadcastTimeRewardClaimed({
        tokenIds: validTokenIds,
        recipient,
        totalAmount: totalPending,
        txHash: receipt.hash
      });

      res.json({
        success: true,
        txHash: receipt.hash,
        amount: totalPending,
        tokenIds: validTokenIds,
        recipient
      });
    } catch (error) {
      console.error('[Revenues] /time-rewards/claim error:', error);
      res.status(500).json({
        error: error.reason || error.message || 'Time reward claim failed'
      });
    }
  });

  /**
   * POST /api/revenues/time-rewards/sync
   * Sync time reward data from blockchain (admin/recovery)
   * Body: { tokenIds?: number[] } - if empty, syncs pool stats only
   */
  router.post('/time-rewards/sync', async (req, res) => {
    try {
      if (!timeRewardTracker) {
        return res.status(503).json({ error: 'Time reward service not available' });
      }

      const { tokenIds } = req.body;
      const results = { poolStats: false, nfts: [] };

      // Always sync pool stats
      results.poolStats = await timeRewardTracker.syncPoolStatsFromBlockchain();

      // Sync specific NFTs if provided
      if (tokenIds && Array.isArray(tokenIds)) {
        for (const tokenId of tokenIds) {
          const success = await timeRewardTracker.syncFromBlockchain(tokenId);
          results.nfts.push({ tokenId, success });
        }
      }

      res.json({
        success: true,
        ...results
      });
    } catch (error) {
      console.error('[Revenues] /time-rewards/sync error:', error);
      res.status(500).json({ error: error.message });
    }
  });

  return router;
};
