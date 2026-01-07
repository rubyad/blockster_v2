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

    // Get current supply and check what's in the database
    try {
      const totalSupply = await this.contractService.getTotalSupply();
      const onChainSupply = Number(totalSupply);

      // Check what's the highest token ID in the database
      const dbMaxToken = this.db.getMaxTokenId() || 0;

      // Start from whichever is lower - ensures we catch any missing tokens
      this.lastSyncedTokenId = Math.min(dbMaxToken, onChainSupply - 1);

      console.log(`[OwnerSync] On-chain supply: ${onChainSupply}, DB max token: ${dbMaxToken}`);
      console.log(`[OwnerSync] Starting sync from token ${this.lastSyncedTokenId + 1}`);

      // Sync any tokens missing from sales table (data consistency fix)
      await this.syncMissingSales();

      // Sync any sales with missing affiliate info
      await this.syncMissingAffiliates();

      // Sync any new tokens not yet in the database
      if (dbMaxToken < onChainSupply) {
        console.log(`[OwnerSync] Missing ${onChainSupply - dbMaxToken} tokens in nfts table, syncing...`);
        await this.syncRecentMints();
      }

      // Quick sync for special NFTs (2340+) - these are most likely to have recent transfers
      console.log('[OwnerSync] Quick syncing special NFTs (2340+)...');
      await this.syncSpecialNFTOwners();

      // Full owner sync runs in background (takes ~15 min)
      console.log('[OwnerSync] Starting background full owner sync...');
      this.syncAllOwners(); // Don't await - runs in background
    } catch (error) {
      console.error('[OwnerSync] Failed to get initial supply:', error.message);
      this.lastSyncedTokenId = 2339; // Known total, skip initial sync
    }

    // Check for new mints every 30 seconds
    this.quickSyncInterval = setInterval(() => {
      this.syncRecentMints();
    }, 30000);

    // Full owner sync every 10 minutes for catching ownership transfers
    this.fullSyncInterval = setInterval(() => {
      if (this.lastSyncedTokenId > 0) {
        this.syncAllOwners();
      }
    }, 10 * 60 * 1000);

    console.log('[OwnerSync] Started');
  }

  /**
   * Quick sync for special NFTs (2340+) - runs on startup
   * These are most likely to have recent ownership transfers
   * Also updates time_reward_nfts table
   */
  async syncSpecialNFTOwners() {
    const SPECIAL_NFT_START = 2340;

    try {
      const totalSupply = await this.contractService.getTotalSupply();
      const total = Number(totalSupply);

      if (total < SPECIAL_NFT_START) {
        console.log('[OwnerSync] No special NFTs minted yet');
        return;
      }

      const specialCount = total - SPECIAL_NFT_START + 1;
      console.log(`[OwnerSync] Syncing ${specialCount} special NFTs (${SPECIAL_NFT_START}-${total})`);

      for (let tokenId = SPECIAL_NFT_START; tokenId <= total; tokenId++) {
        try {
          const onChainOwner = await this.contractService.getOwnerOf(tokenId);
          const dbNft = this.db.getNFT(tokenId);

          if (dbNft && dbNft.owner.toLowerCase() !== onChainOwner.toLowerCase()) {
            console.log(`[OwnerSync] Token ${tokenId} owner changed: ${dbNft.owner.slice(0,10)}... -> ${onChainOwner.slice(0,10)}...`);
            this.db.updateNFTOwner(tokenId, onChainOwner);
          }

          // Always update time_reward_nfts table (may be out of sync even if nfts is correct)
          this.db.updateTimeRewardNFTOwner(tokenId, onChainOwner);

          if (!dbNft) {
            console.log(`[OwnerSync] Token ${tokenId} not in DB, adding...`);
            const hostessIndex = await this.contractService.getHostessIndex(tokenId);
            const hostessData = config.HOSTESSES[Number(hostessIndex)];

            this.db.upsertNFT({
              tokenId,
              owner: onChainOwner,
              hostessIndex: Number(hostessIndex),
              hostessName: hostessData?.name || 'Unknown'
            });
          }

          // Small delay between calls
          await this.sleep(200);
        } catch (error) {
          console.error(`[OwnerSync] Failed to sync special NFT ${tokenId}:`, error.message);
        }
      }

      console.log('[OwnerSync] Special NFTs sync complete');
    } catch (error) {
      console.error('[OwnerSync] Failed to sync special NFTs:', error.message);
    }
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
   * Runs every 30 seconds
   */
  async syncRecentMints() {
    const { ethers } = require('ethers');

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
                // Get affiliate info from contract
                const buyerInfo = await this.contractService.getBuyerInfo(owner);
                const affiliate = buyerInfo.affiliate;
                const affiliate2 = buyerInfo.affiliate2;
                const zeroAddress = ethers.ZeroAddress;

                this.db.insertSale({
                  tokenId,
                  buyer: owner,
                  hostessIndex: Number(hostessIndex),
                  hostessName: hostessData?.name || 'Unknown',
                  price: config.MINT_PRICE,
                  txHash: `0x${tokenId.toString(16).padStart(64, '0')}`,
                  blockNumber: 0,
                  timestamp: Math.floor(Date.now() / 1000),
                  affiliate: affiliate !== zeroAddress ? affiliate : null,
                  affiliate2: affiliate2 !== zeroAddress ? affiliate2 : null
                });

                // Insert affiliate earnings if applicable
                const mintPriceWei = BigInt(config.MINT_PRICE);
                const tier1Earnings = (mintPriceWei * 20n / 100n).toString(); // 20%
                const tier2Earnings = (mintPriceWei * 5n / 100n).toString();  // 5%

                if (affiliate && affiliate !== zeroAddress) {
                  this.db.insertAffiliateEarning({
                    tokenId,
                    tier: 1,
                    affiliate,
                    earnings: tier1Earnings,
                    txHash: `0x${tokenId.toString(16).padStart(64, '0')}`
                  });
                }

                if (affiliate2 && affiliate2 !== zeroAddress) {
                  this.db.insertAffiliateEarning({
                    tokenId,
                    tier: 2,
                    affiliate: affiliate2,
                    earnings: tier2Earnings,
                    txHash: `0x${tokenId.toString(16).padStart(64, '0')}`
                  });
                }

                this.db.incrementHostessCount(Number(hostessIndex));
                console.log(`[OwnerSync] Synced new mint: token ${tokenId} (${hostessData?.name})`);
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

  /**
   * Sync tokens that exist in nfts table but not in sales table
   * Also syncs missing affiliate earnings
   * This fixes data inconsistency from previous sync issues
   */
  async syncMissingSales() {
    try {
      const missingTokens = this.db.getMissingSalesTokens();

      if (missingTokens.length === 0) {
        return;
      }

      console.log(`[OwnerSync] Found ${missingTokens.length} tokens missing from sales table: ${missingTokens.join(', ')}`);

      for (const tokenId of missingTokens) {
        try {
          const hostessIndex = await this.contractService.getHostessIndex(tokenId);
          const owner = await this.contractService.getOwnerOf(tokenId);
          const hostessData = config.HOSTESSES[Number(hostessIndex)];

          // Get affiliate info from contract
          const buyerInfo = await this.contractService.getBuyerInfo(owner);
          const affiliate = buyerInfo.affiliate;
          const affiliate2 = buyerInfo.affiliate2;

          // Insert sale with affiliate info
          this.db.insertSale({
            tokenId,
            buyer: owner,
            hostessIndex: Number(hostessIndex),
            hostessName: hostessData?.name || 'Unknown',
            price: config.MINT_PRICE,
            txHash: `0x${tokenId.toString(16).padStart(64, '0')}`,
            blockNumber: 0,
            timestamp: Math.floor(Date.now() / 1000),
            affiliate: affiliate !== '0x0000000000000000000000000000000000000000' ? affiliate : null,
            affiliate2: affiliate2 !== '0x0000000000000000000000000000000000000000' ? affiliate2 : null
          });

          // Insert affiliate earnings if applicable
          const { ethers } = require('ethers');
          const zeroAddress = ethers.ZeroAddress;
          const mintPriceWei = BigInt(config.MINT_PRICE);
          const tier1Earnings = (mintPriceWei * 20n / 100n).toString(); // 20%
          const tier2Earnings = (mintPriceWei * 5n / 100n).toString();  // 5%

          if (affiliate && affiliate !== zeroAddress) {
            this.db.insertAffiliateEarning({
              tokenId,
              tier: 1,
              affiliate,
              earnings: tier1Earnings,
              txHash: `0x${tokenId.toString(16).padStart(64, '0')}`
            });
          }

          if (affiliate2 && affiliate2 !== zeroAddress) {
            this.db.insertAffiliateEarning({
              tokenId,
              tier: 2,
              affiliate: affiliate2,
              earnings: tier2Earnings,
              txHash: `0x${tokenId.toString(16).padStart(64, '0')}`
            });
          }

          console.log(`[OwnerSync] Added missing sale for token ${tokenId} (${hostessData?.name}, affiliate: ${affiliate?.slice(0,10)}...)`);

          // Small delay between RPC calls
          await this.sleep(500);
        } catch (error) {
          console.error(`[OwnerSync] Failed to sync missing sale for token ${tokenId}:`, error.message);
        }
      }

      console.log(`[OwnerSync] Missing sales sync complete`);
    } catch (error) {
      console.error('[OwnerSync] Failed to sync missing sales:', error.message);
    }
  }

  /**
   * Sync affiliate info for sales that have missing affiliate data or missing affiliate_earnings records
   */
  async syncMissingAffiliates() {
    const { ethers } = require('ethers');

    try {
      // Find sales with missing affiliate info OR missing affiliate_earnings records
      const salesMissingAffiliates = this.db.getSalesMissingAffiliates();

      if (salesMissingAffiliates.length === 0) {
        return;
      }

      console.log(`[OwnerSync] Found ${salesMissingAffiliates.length} sales with missing affiliate info`);

      const zeroAddress = ethers.ZeroAddress;
      const mintPriceWei = BigInt(config.MINT_PRICE);
      const tier1Earnings = (mintPriceWei * 20n / 100n).toString();
      const tier2Earnings = (mintPriceWei * 5n / 100n).toString();

      for (const sale of salesMissingAffiliates) {
        try {
          // Get affiliate info from contract
          const buyerInfo = await this.contractService.getBuyerInfo(sale.buyer);
          const affiliate = buyerInfo.affiliate;
          const affiliate2 = buyerInfo.affiliate2;

          // Update sale with affiliate info if missing
          if (!sale.affiliate && affiliate && affiliate !== zeroAddress) {
            this.db.updateSaleAffiliates(sale.token_id, affiliate, affiliate2 !== zeroAddress ? affiliate2 : null);
          }

          // Add affiliate earnings if missing
          if (affiliate && affiliate !== zeroAddress) {
            if (!this.db.affiliateEarningExists(sale.token_id, 1)) {
              this.db.insertAffiliateEarning({
                tokenId: sale.token_id,
                tier: 1,
                affiliate,
                earnings: tier1Earnings,
                txHash: sale.tx_hash
              });
            }
          }

          if (affiliate2 && affiliate2 !== zeroAddress) {
            if (!this.db.affiliateEarningExists(sale.token_id, 2)) {
              this.db.insertAffiliateEarning({
                tokenId: sale.token_id,
                tier: 2,
                affiliate: affiliate2,
                earnings: tier2Earnings,
                txHash: sale.tx_hash
              });
            }
          }

          console.log(`[OwnerSync] Synced affiliates for token ${sale.token_id}`);
          await this.sleep(500);
        } catch (error) {
          console.error(`[OwnerSync] Failed to sync affiliates for token ${sale.token_id}:`, error.message);
        }
      }

      console.log(`[OwnerSync] Missing affiliates sync complete`);
    } catch (error) {
      console.error('[OwnerSync] Failed to sync missing affiliates:', error.message);
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
