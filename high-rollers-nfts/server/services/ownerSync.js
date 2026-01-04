const config = require('../config');

class OwnerSyncService {
  constructor(db, contractService) {
    this.db = db;
    this.contractService = contractService;
    this.isRunning = false;
    this.lastSyncedTokenId = 0;
  }

  start() {
    if (this.isRunning) return;
    this.isRunning = true;

    // Full sync every 5 minutes
    this.fullSyncInterval = setInterval(() => {
      this.syncAllOwners();
    }, config.OWNER_SYNC_INTERVAL_MS);

    // Quick check for new mints every 30 seconds
    this.quickSyncInterval = setInterval(() => {
      this.syncRecentMints();
    }, config.POLL_INTERVAL_MS);

    // Initial sync on startup
    this.syncAllOwners();

    console.log('[OwnerSync] Started owner polling service');
  }

  /**
   * Full sync: Update all NFT owners in batches
   * Runs every 5 minutes to catch any missed transfers
   * Uses small batches with delays to stay under RPC rate limits (100/sec)
   */
  async syncAllOwners() {
    try {
      const totalSupply = await this.contractService.getTotalSupply();
      const total = Number(totalSupply);

      console.log(`[OwnerSync] Starting full sync of ${total} NFTs`);

      // Small batch size to stay under rate limits (each token = 2 calls)
      const batchSize = 20;
      let updated = 0;
      let errors = 0;

      for (let i = 1; i <= total; i += batchSize) {
        const batch = [];
        for (let j = i; j < Math.min(i + batchSize, total + 1); j++) {
          batch.push(j);
        }

        try {
          // Fetch owners in parallel with error handling per call
          const owners = await Promise.all(
            batch.map(tokenId =>
              this.contractService.getOwnerOf(tokenId).catch(() => null)
            )
          );

          // Fetch hostess indices for new NFTs
          const hostessIndices = await Promise.all(
            batch.map(tokenId =>
              this.contractService.getHostessIndex(tokenId).catch(() => null)
            )
          );

          // Update database
          batch.forEach((tokenId, index) => {
            if (owners[index] && hostessIndices[index] !== null) {
              const hostessIndex = Number(hostessIndices[index]);
              const hostessData = config.HOSTESSES[hostessIndex];

              this.db.upsertNFT({
                tokenId,
                owner: owners[index],
                hostessIndex,
                hostessName: hostessData?.name || 'Unknown'
              });
              updated++;
            }
          });
        } catch (batchError) {
          errors++;
          // Continue with next batch instead of failing entirely
        }

        // Rate limiting: 500ms delay = ~40 calls/sec (well under 100/sec limit)
        await this.sleep(500);

        // Progress logging every 200 tokens
        if ((i - 1) % 200 === 0) {
          console.log(`[OwnerSync] Progress: ${Math.min(i + batchSize - 1, total)}/${total}`);
        }
      }

      // Recalculate hostess counts after full sync
      this.db.recalculateHostessCounts();

      console.log(`[OwnerSync] Full sync complete: ${updated} NFTs updated, ${errors} batch errors`);
      this.lastSyncedTokenId = total;
    } catch (error) {
      console.error('[OwnerSync] Full sync failed:', error.message);
    }
  }

  /**
   * Quick sync: Only check for new mints since last check
   * Runs every 30 seconds
   */
  async syncRecentMints() {
    try {
      const totalSupply = await this.contractService.getTotalSupply();
      const total = Number(totalSupply);

      if (total > this.lastSyncedTokenId) {
        console.log(`[OwnerSync] New mints detected: ${this.lastSyncedTokenId} -> ${total}`);

        // Sync new tokens
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
            }
          } catch (error) {
            console.error(`[OwnerSync] Failed to sync token ${tokenId}:`, error.message);
          }
        }

        this.lastSyncedTokenId = total;
      }
    } catch (error) {
      console.error('[OwnerSync] Quick sync failed:', error);
    }
  }

  /**
   * Sync a specific wallet's NFTs
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
      }

      return tokenIds.map(id => Number(id));
    } catch (error) {
      console.error(`[OwnerSync] Failed to sync wallet ${walletAddress}:`, error);
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
