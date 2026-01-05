/**
 * RewardEventListener - Polls NFTRewarder contract for reward events
 *
 * Watches for:
 * - RewardReceived: When ROGUEBankroll sends rewards after losing bets
 * - RewardClaimed: When users withdraw their pending rewards
 *
 * Uses polling instead of WebSocket subscriptions due to Rogue Chain RPC filter issues.
 */

const { ethers } = require('ethers');

class RewardEventListener {
  constructor(db, websocket, config) {
    this.db = db;
    this.ws = websocket;
    this.config = config;

    this.rogueProvider = new ethers.JsonRpcProvider(config.ROGUE_RPC_URL);
    this.rewarderContract = new ethers.Contract(
      config.NFT_REWARDER_ADDRESS,
      config.NFT_REWARDER_ABI,
      this.rogueProvider
    );

    this.lastProcessedBlock = 0;
    this.pollIntervalMs = 10000;  // 10 seconds (faster than EventListener since rewards are higher priority)
    this.pollInterval = null;
    this.isRunning = false;
  }

  async start() {
    if (this.isRunning) return;
    this.isRunning = true;

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
      if (!this.isRunning) return;

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
        const amountFormatted = ethers.formatEther(amount);
        console.log(`[RewardListener] Reward received: ${amountFormatted} ROGUE (betId: ${betId.slice(0, 10)}...)`);

        // Store in database
        this.db.insertRewardEvent({
          commitmentHash: betId.toString(),
          amount: amount.toString(),
          timestamp: Number(timestamp),
          blockNumber: event.blockNumber,
          txHash: event.transactionHash
        });

        // Broadcast to connected clients
        if (this.ws) {
          this.ws.broadcast({
            type: 'REWARD_RECEIVED',
            data: {
              betId: betId.toString(),
              amount: amountFormatted,
              amountWei: amount.toString(),
              timestamp: Number(timestamp),
              txHash: event.transactionHash,
              blockNumber: event.blockNumber
            }
          });
        }
      }

      if (events.length > 0) {
        console.log(`[RewardListener] Processed ${events.length} RewardReceived events (blocks ${fromBlock}-${toBlock})`);
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
        const amountFormatted = ethers.formatEther(amount);
        const tokenIdNumbers = tokenIds.map(t => Number(t));

        console.log(`[RewardListener] Claim by ${user.slice(0, 10)}...: ${amountFormatted} ROGUE (${tokenIdNumbers.length} NFTs)`);

        // Record withdrawal in database
        this.db.recordRewardWithdrawal({
          userAddress: user,
          amount: amount.toString(),
          tokenIds: JSON.stringify(tokenIdNumbers),
          txHash: event.transactionHash,
          timestamp: Math.floor(Date.now() / 1000)
        });

        // Reset pending amounts for claimed NFTs
        for (const tokenId of tokenIdNumbers) {
          this.db.resetNFTPending(tokenId);
        }

        // Broadcast to connected clients
        if (this.ws) {
          this.ws.broadcast({
            type: 'REWARD_CLAIMED',
            data: {
              user,
              amount: amountFormatted,
              amountWei: amount.toString(),
              tokenIds: tokenIdNumbers,
              txHash: event.transactionHash
            }
          });
        }
      }

      if (events.length > 0) {
        console.log(`[RewardListener] Processed ${events.length} RewardClaimed events (blocks ${fromBlock}-${toBlock})`);
      }
    } catch (error) {
      if (!error.message?.includes('rate limit')) {
        console.error('[RewardListener] RewardClaimed poll error:', error.message);
      }
    }
  }

  /**
   * Get current on-chain stats from NFTRewarder contract
   */
  async getOnchainStats() {
    try {
      const [totalReceived, totalDistributed, totalNFTs, totalPoints] = await Promise.all([
        this.rewarderContract.totalRewardsReceived(),
        this.rewarderContract.totalRewardsDistributed(),
        this.rewarderContract.totalRegisteredNFTs(),
        this.rewarderContract.totalMultiplierPoints()
      ]);

      return {
        totalRewardsReceived: totalReceived.toString(),
        totalRewardsDistributed: totalDistributed.toString(),
        totalRegisteredNFTs: Number(totalNFTs),
        totalMultiplierPoints: Number(totalPoints)
      };
    } catch (error) {
      console.error('[RewardListener] Failed to get on-chain stats:', error.message);
      return null;
    }
  }

  stop() {
    this.isRunning = false;
    if (this.pollInterval) {
      clearInterval(this.pollInterval);
      this.pollInterval = null;
    }
    console.log('[RewardListener] Stopped');
  }
}

module.exports = RewardEventListener;
