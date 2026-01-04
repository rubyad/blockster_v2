const config = require('../config');

class OwnerSyncService {
  constructor(db, contractService) {
    this.db = db;
    this.contractService = contractService;
    this.isRunning = false;
    this.lastSyncedTokenId = 0;
    this.isSyncing = false;
  }

  async start() {
    if (this.isRunning) return;
    this.isRunning = true;

    // Get current supply to track new mints only
    try {
      const totalSupply = await this.contractService.getTotalSupply();
      this.lastSyncedTokenId = Number(totalSupply);
      console.log(`[OwnerSync] Starting at token ${this.lastSyncedTokenId}`);
    } catch (error) {
      console.error('[OwnerSync] Failed to get initial supply:', error.message);
      this.lastSyncedTokenId = 2339; // Known total, skip initial sync
    }

    // Only check for new mints every 60 seconds (not 30 to reduce load)
    this.quickSyncInterval = setInterval(() => {
      this.syncRecentMints();
    }, 60000);

    // Full sync every 30 minutes (not 5 to reduce load), but only if needed
    // This is mainly for catching ownership transfers
    this.fullSyncInterval = setInterval(() => {
      // Only run full sync if there are NFTs that might need owner updates
      // Skip if we haven't synced any NFTs yet
      if (this.lastSyncedTokenId > 0) {
        this.syncAllOwners();
      }
    }, 30 * 60 * 1000);

    console.log('[OwnerSync] Started (minimal mode - syncs new mints only)');
  }

  /**
   * Full sync: Update all NFT owners in batches
   * Uses very small batches with long delays to stay way under RPC rate limits
   * This is for catching ownership transfers, not initial population
   */
  async syncAllOwners() {
    if (this.isSyncing) {
      console.log('[OwnerSync] Sync already in progress, skipping');
      return;
    }

    this.isSyncing = true;

    try {
      const totalSupply = await this.contractService.getTotalSupply();
      const total = Number(totalSupply);

      console.log(`[OwnerSync] Starting owner sync of ${total} NFTs`);

      // Very small batch size - 5 tokens per batch = 10 calls
      const batchSize = 5;
      let updated = 0;

      for (let i = 1; i <= total; i += batchSize) {
        const batch = [];
        for (let j = i; j < Math.min(i + batchSize, total + 1); j++) {
          batch.push(j);
        }

        try {
          // Fetch owners with error handling per call
          const owners = await Promise.all(
            batch.map(tokenId =>
              this.contractService.getOwnerOf(tokenId).catch(() => null)
            )
          );

          // Update database (owner changes only)
          batch.forEach((tokenId, index) => {
            if (owners[index]) {
              this.db.updateNFTOwner(tokenId, owners[index]);
              updated++;
            }
          });
        } catch (batchError) {
          // Continue with next batch
        }

        // Very slow: 2 second delay between batches = ~5 calls/sec max
        await this.sleep(2000);

        // Progress logging every 500 tokens
        if ((i - 1) % 500 === 0 && i > 1) {
          console.log(`[OwnerSync] Progress: ${Math.min(i + batchSize - 1, total)}/${total}`);
        }
      }

      console.log(`[OwnerSync] Owner sync complete: ${updated} NFTs checked`);
    } catch (error) {
      console.error('[OwnerSync] Owner sync failed:', error.message);
    } finally {
      this.isSyncing = false;
    }
  }

  /**
   * Quick sync: Only check for new mints since last check
   * Runs every 60 seconds
   */
  async syncRecentMints() {
    try {
      const totalSupply = await this.contractService.getTotalSupply();
      const total = Number(totalSupply);

      if (total > this.lastSyncedTokenId) {
        console.log(`[OwnerSync] New mints detected: ${this.lastSyncedTokenId} -> ${total}`);

        // Sync new tokens one at a time with delays
        for (let tokenId = this.lastSyncedTokenId + 1; tokenId <= total; tokenId++) {
          try {
            const owner = await this.contractService.getOwnerOf(tokenId);
            const hostessIndex = await this.contractService.getHostessIndex(tokenId);
            const hostessData = config.HOSTESSES[Number(hostessIndex)];

            if (owner) {
              this.db.upsertNFT({
                tokenId,
                owner,
                hostessIndex: Number(hostessIndex),
                hostessName: hostessData?.name || 'Unknown'
              });

              // Also add to sales if not exists (check by token_id to avoid duplicates with real tx_hash from EventListener)
              if (!this.db.saleExistsForToken(tokenId)) {
                this.db.insertSale({
                  tokenId,
                  buyer: owner,
                  hostessIndex: Number(hostessIndex),
                  hostessName: hostessData?.name || 'Unknown',
                  price: config.MINT_PRICE,
                  txHash: `0x${tokenId.toString(16).padStart(64, '0')}`,
                  blockNumber: 0,
                  timestamp: Math.floor(Date.now() / 1000)
                });
                this.db.incrementHostessCount(Number(hostessIndex));
              }
            }

            // 1 second delay between each new mint
            await this.sleep(1000);
          } catch (error) {
            console.error(`[OwnerSync] Failed to sync token ${tokenId}:`, error.message);
          }
        }

        this.lastSyncedTokenId = total;
      }
    } catch (error) {
      // Don't spam logs for rate limit errors
      if (!error.message?.includes('rate limit') && !error.message?.includes('coalesce')) {
        console.error('[OwnerSync] Quick sync failed:', error.message);
      }
    }
  }

  /**
   * Sync a specific wallet's NFTs (on-demand only)
   */
  async syncWalletNFTs(walletAddress) {
    try {
      const tokenIds = await this.contractService.getTokenIdsByWallet(walletAddress);

      for (const tokenIdBigInt of tokenIds) {
        const tokenId = Number(tokenIdBigInt);
        const hostessIndex = await this.contractService.getHostessIndex(tokenId);
        const hostessData = config.HOSTESSES[Number(hostessIndex)];

        this.db.upsertNFT({
          tokenId,
          owner: walletAddress,
          hostessIndex: Number(hostessIndex),
          hostessName: hostessData?.name || 'Unknown'
        });

        // Small delay between calls
        await this.sleep(200);
      }

      return tokenIds.map(id => Number(id));
    } catch (error) {
      console.error(`[OwnerSync] Failed to sync wallet ${walletAddress}:`, error.message);
      return [];
    }
  }

  sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  stop() {
    this.isRunning = false;
    if (this.fullSyncInterval) clearInterval(this.fullSyncInterval);
    if (this.quickSyncInterval) clearInterval(this.quickSyncInterval);
    console.log('[OwnerSync] Stopped');
  }
}

module.exports = OwnerSyncService;
