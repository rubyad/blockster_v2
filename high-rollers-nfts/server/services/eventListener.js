const { ethers } = require('ethers');
const config = require('../config');
const adminTxQueue = require('./adminTxQueue');

class EventListener {
  constructor(contractService, database, websocketServer) {
    this.contractService = contractService;
    this.db = database;
    this.ws = websocketServer;
    this.provider = new ethers.JsonRpcProvider(config.RPC_URL);
    this.contract = new ethers.Contract(
      config.CONTRACT_ADDRESS,
      config.CONTRACT_ABI,
      this.provider
    );

    // Track pending mints for fallback polling
    this.pendingMints = new Map(); // requestId -> { sender, timestamp, tokenId }
    this.lastKnownSupply = 0;

    // Track last processed block for polling
    this.lastProcessedBlock = 0;

    // Polling interval (in ms) - 30 seconds to reduce RPC load
    this.pollIntervalMs = 30000;

    // TimeRewardTracker - set by setTimeRewardTracker()
    this.timeRewardTracker = null;
  }

  /**
   * Set the TimeRewardTracker service (called from index.js after initialization)
   */
  setTimeRewardTracker(tracker) {
    this.timeRewardTracker = tracker;
    console.log('[EventListener] TimeRewardTracker attached');
  }

  async start() {
    // Get current block number to start polling from
    try {
      this.lastProcessedBlock = await this.provider.getBlockNumber();
      console.log(`[EventListener] Starting from block ${this.lastProcessedBlock}`);
    } catch (error) {
      console.error('[EventListener] Failed to get block number:', error.message);
      this.lastProcessedBlock = 0;
    }

    // Use polling instead of event filters (filters cause "filter not found" errors)
    this.startEventPolling();
    this.startFallbackPolling();
    console.log('[EventListener] Started (using polling mode)');
  }

  /**
   * Poll for events using getLogs instead of filters
   * This avoids the "filter not found" errors that occur with eth_getFilterChanges
   */
  startEventPolling() {
    this.pollInterval = setInterval(async () => {
      try {
        const currentBlock = await this.provider.getBlockNumber();

        // Only poll if there are new blocks
        if (currentBlock <= this.lastProcessedBlock) return;

        const fromBlock = this.lastProcessedBlock + 1;
        const toBlock = currentBlock;

        // Don't query more than 1000 blocks at a time
        const maxBlocks = 1000;
        const queryToBlock = Math.min(toBlock, fromBlock + maxBlocks - 1);

        // Query NFTRequested events
        await this.pollNFTRequestedEvents(fromBlock, queryToBlock);

        // Query NFTMinted events
        await this.pollNFTMintedEvents(fromBlock, queryToBlock);

        // Query Transfer events (non-mint only)
        await this.pollTransferEvents(fromBlock, queryToBlock);

        this.lastProcessedBlock = queryToBlock;

      } catch (error) {
        // Don't spam console with rate limit or coalesce errors
        if (!error.message?.includes('rate limit') && !error.message?.includes('coalesce')) {
          console.error('[EventListener] Polling error:', error.message);
        }
      }
    }, this.pollIntervalMs);
  }

  async pollNFTRequestedEvents(fromBlock, toBlock) {
    try {
      const filter = this.contract.filters.NFTRequested();
      const events = await this.contract.queryFilter(filter, fromBlock, toBlock);

      for (const event of events) {
        const [requestId, sender, price, tokenId] = event.args;
        console.log(`[Event] NFTRequested: requestId=${requestId}, sender=${sender}, tokenId=${tokenId}`);

        // Track pending mint for fallback
        this.pendingMints.set(requestId.toString(), {
          sender,
          tokenId: tokenId.toString(),
          price: price.toString(),
          timestamp: Date.now(),
          txHash: event.transactionHash
        });

        // Store in database
        this.db.insertPendingMint({
          requestId: requestId.toString(),
          sender,
          tokenId: tokenId.toString(),
          price: price.toString(),
          txHash: event.transactionHash
        });

        this.ws.broadcast({
          type: 'MINT_REQUESTED',
          data: {
            requestId: requestId.toString(),
            sender,
            price: price.toString(),
            tokenId: tokenId.toString(),
            txHash: event.transactionHash
          }
        });
      }
    } catch (error) {
      // Suppress rate limit errors
      if (!error.message?.includes('rate limit') && !error.message?.includes('coalesce')) {
        console.error('[EventListener] NFTRequested poll error:', error.message);
      }
    }
  }

  async pollNFTMintedEvents(fromBlock, toBlock) {
    try {
      const filter = this.contract.filters.NFTMinted();
      const events = await this.contract.queryFilter(filter, fromBlock, toBlock);

      for (const event of events) {
        const [requestId, recipient, price, tokenId, hostess, affiliate, affiliate2] = event.args;
        this.handleMintComplete(requestId, recipient, price, tokenId, hostess, affiliate, affiliate2, event);
      }
    } catch (error) {
      // Suppress rate limit errors
      if (!error.message?.includes('rate limit') && !error.message?.includes('coalesce')) {
        console.error('[EventListener] NFTMinted poll error:', error.message);
      }
    }
  }

  async pollTransferEvents(fromBlock, toBlock) {
    try {
      const filter = this.contract.filters.Transfer();
      const events = await this.contract.queryFilter(filter, fromBlock, toBlock);

      for (const event of events) {
        const [from, to, tokenId] = event.args;

        // Skip mint transfers (from zero address)
        if (from === ethers.ZeroAddress) continue;

        console.log(`[Event] Transfer: tokenId=${tokenId}, from=${from}, to=${to}`);

        this.db.updateNFTOwner(Number(tokenId), to);
        this.ws.broadcast({
          type: 'NFT_TRANSFERRED',
          data: {
            tokenId: tokenId.toString(),
            from,
            to,
            txHash: event.transactionHash
          }
        });

        // Update ownership in NFTRewarder on Rogue Chain (async, don't block)
        this.updateOwnershipOnRogueChain(Number(tokenId), to);
      }
    } catch (error) {
      // Suppress rate limit errors
      if (!error.message?.includes('rate limit') && !error.message?.includes('coalesce')) {
        console.error('[EventListener] Transfer poll error:', error.message);
      }
    }
  }

  /**
   * Update NFT ownership in the NFTRewarder contract on Rogue Chain
   * This ensures rewards go to the correct owner after a transfer
   *
   * @param {number} tokenId - NFT token ID
   * @param {string} newOwner - New owner wallet address
   */
  async updateOwnershipOnRogueChain(tokenId, newOwner) {
    try {
      const receipt = await adminTxQueue.updateOwnership(tokenId, newOwner);
      console.log(`[EventListener] Updated ownership for NFT #${tokenId} on Rogue Chain: ${receipt.hash}`);

      // Broadcast ownership update success
      this.ws.broadcast({
        type: 'NFT_OWNERSHIP_UPDATED_FOR_REWARDS',
        data: {
          tokenId,
          newOwner,
          txHash: receipt.hash
        }
      });

      // Update local time reward tracking if this is a special NFT
      if (this.timeRewardTracker) {
        this.timeRewardTracker.updateOwnership(tokenId, newOwner);
      }
    } catch (error) {
      console.error(`[EventListener] Failed to update ownership for NFT #${tokenId} on Rogue Chain:`, error.message);
      // Don't throw - this is non-critical and can be retried manually
    }
  }

  handleMintComplete(requestId, recipient, price, tokenId, hostess, affiliate, affiliate2, event) {
    console.log(`[Event] NFTMinted: tokenId=${tokenId}, hostess=${hostess}, recipient=${recipient}`);

    const hostessIndex = Number(hostess);
    const hostessData = config.HOSTESSES[hostessIndex];
    const hostessName = hostessData?.name || 'Unknown';
    const priceStr = price.toString();

    // Remove from pending mints
    this.pendingMints.delete(requestId.toString());
    this.db.deletePendingMint(requestId.toString());

    // Calculate affiliate earnings
    const tier1Earnings = (BigInt(priceStr) / 5n).toString(); // 20%
    const tier2Earnings = (BigInt(priceStr) / 20n).toString(); // 5%

    // Store NFT in database
    this.db.insertNFT({
      tokenId: Number(tokenId),
      owner: recipient,
      hostessIndex,
      hostessName,
      mintPrice: priceStr,
      mintTxHash: event.transactionHash,
      affiliate,
      affiliate2
    });

    // Store sale (upsert to update if OwnerSync created with fake tx_hash first)
    this.db.upsertSale({
      tokenId: Number(tokenId),
      buyer: recipient,
      hostessIndex,
      hostessName,
      price: priceStr,
      txHash: event.transactionHash,
      blockNumber: event.blockNumber,
      timestamp: Math.floor(Date.now() / 1000),
      affiliate,
      affiliate2
    });

    // Record affiliate earnings
    if (affiliate && affiliate !== ethers.ZeroAddress) {
      this.db.insertAffiliateEarning({
        tokenId: Number(tokenId),
        tier: 1,
        affiliate,
        earnings: tier1Earnings,
        txHash: event.transactionHash
      });
    }

    if (affiliate2 && affiliate2 !== ethers.ZeroAddress) {
      this.db.insertAffiliateEarning({
        tokenId: Number(tokenId),
        tier: 2,
        affiliate: affiliate2,
        earnings: tier2Earnings,
        txHash: event.transactionHash
      });
    }

    // Update hostess count
    this.db.incrementHostessCount(hostessIndex);

    // Broadcast to all connected clients
    this.ws.broadcast({
      type: 'NFT_MINTED',
      data: {
        requestId: requestId.toString(),
        recipient,
        tokenId: tokenId.toString(),
        hostessIndex,
        hostessName,
        hostessRarity: hostessData?.rarity,
        hostessMultiplier: hostessData?.multiplier,
        hostessImage: hostessData?.image,
        price: priceStr,
        priceETH: ethers.formatEther(price),
        txHash: event.transactionHash,
        affiliate,
        affiliate2,
        tier1Earnings,
        tier2Earnings
      }
    });

    // Register NFT in NFTRewarder on Rogue Chain (async, don't block)
    this.registerNFTOnRogueChain(Number(tokenId), hostessIndex, recipient);
  }

  /**
   * Register a newly minted NFT in the NFTRewarder contract on Rogue Chain
   * This enables the NFT to receive revenue sharing rewards
   * For special NFTs (2340-2700), this also starts time-based rewards automatically
   *
   * @param {number} tokenId - NFT token ID
   * @param {number} hostessIndex - Hostess type (0-7)
   * @param {string} owner - Owner wallet address
   */
  async registerNFTOnRogueChain(tokenId, hostessIndex, owner) {
    try {
      const receipt = await adminTxQueue.registerNFT(tokenId, hostessIndex, owner);
      console.log(`[EventListener] Registered NFT #${tokenId} on Rogue Chain: ${receipt.hash}`);

      // Broadcast registration success
      this.ws.broadcast({
        type: 'NFT_REGISTERED_FOR_REWARDS',
        data: {
          tokenId,
          hostessIndex,
          owner,
          txHash: receipt.hash
        }
      });

      // Track time rewards for special NFTs (2340-2700)
      // The contract automatically starts time rewards in registerNFT()
      // We just need to track the start time locally for UI calculations
      if (this.timeRewardTracker && this.timeRewardTracker.isSpecialNFT(tokenId)) {
        // Get the block timestamp from the registration transaction
        const block = await this.provider.getBlock(receipt.blockNumber);
        const blockTimestamp = block ? block.timestamp : Math.floor(Date.now() / 1000);

        // Track the special NFT in local database
        this.timeRewardTracker.handleNFTRegistered(tokenId, hostessIndex, owner, blockTimestamp);
      }
    } catch (error) {
      console.error(`[EventListener] Failed to register NFT #${tokenId} on Rogue Chain:`, error.message);
      // Don't throw - this is non-critical and can be retried manually
    }
  }

  /**
   * FALLBACK POLLING SYSTEM
   * If event listener misses an event, this catches it
   */
  startFallbackPolling() {
    // Poll every 5 seconds for pending mints
    this.fallbackInterval = setInterval(async () => {
      await this.checkPendingMints();
      await this.checkSupplyChanges();
    }, config.MINT_POLL_INTERVAL_MS);

    console.log('[EventListener] Fallback polling started');
  }

  async checkPendingMints() {
    const now = Date.now();

    for (const [requestId, mint] of this.pendingMints) {
      // If pending for more than 60 seconds, check contract directly
      if (now - mint.timestamp > 60000) {
        try {
          // Check if this token has been minted by querying ownership
          const tokenId = parseInt(mint.tokenId);
          const owner = await this.contract.ownerOf(tokenId);

          if (owner && owner !== ethers.ZeroAddress) {
            // NFT was minted but we missed the event
            console.log(`[Fallback] Detected missed mint for tokenId=${tokenId}`);

            const hostessIndex = await this.contract.s_tokenIdToHostess(tokenId);

            // Fetch the mint event from past blocks
            const filter = this.contract.filters.NFTMinted(requestId);
            const events = await this.contract.queryFilter(filter, -1000); // Last 1000 blocks

            if (events.length > 0) {
              const event = events[0];
              this.handleMintComplete(
                requestId,
                event.args[1], // recipient
                event.args[2], // price
                event.args[3], // tokenId
                event.args[4], // hostess
                event.args[5], // affiliate
                event.args[6], // affiliate2
                event
              );
            } else {
              // Event not found, construct from available data
              const hostessData = config.HOSTESSES[Number(hostessIndex)];
              this.pendingMints.delete(requestId);
              this.db.deletePendingMint(requestId);

              // Store NFT
              this.db.insertNFT({
                tokenId,
                owner,
                hostessIndex: Number(hostessIndex),
                hostessName: hostessData?.name || 'Unknown',
                mintPrice: mint.price,
                mintTxHash: mint.txHash
              });

              this.db.incrementHostessCount(Number(hostessIndex));

              this.ws.broadcast({
                type: 'NFT_MINTED',
                data: {
                  requestId,
                  recipient: owner,
                  tokenId: tokenId.toString(),
                  hostessIndex: Number(hostessIndex),
                  hostessName: hostessData?.name,
                  hostessRarity: hostessData?.rarity,
                  hostessMultiplier: hostessData?.multiplier,
                  hostessImage: hostessData?.image,
                  price: mint.price,
                  priceETH: ethers.formatEther(mint.price),
                  txHash: mint.txHash,
                  source: 'fallback'
                }
              });
            }
          }
        } catch (error) {
          // Token doesn't exist yet, keep waiting
          if (now - mint.timestamp > 300000) {
            // 5 minutes timeout - remove stale pending mint
            console.log(`[Fallback] Removing stale pending mint: ${requestId}`);
            this.pendingMints.delete(requestId);
            this.db.deletePendingMint(requestId);
          }
        }
      }
    }
  }

  async checkSupplyChanges() {
    try {
      const currentSupply = await this.contractService.getTotalSupply();
      const supply = Number(currentSupply);

      if (supply > this.lastKnownSupply && this.lastKnownSupply > 0) {
        // New NFTs minted that we might have missed
        console.log(`[Fallback] Supply changed: ${this.lastKnownSupply} -> ${supply}`);

        // Fetch recent Transfer events to catch any missed mints
        const filter = this.contract.filters.Transfer(ethers.ZeroAddress);
        const events = await this.contract.queryFilter(filter, -100);

        for (const event of events) {
          const tokenId = Number(event.args[2]);
          if (!this.db.nftExists(tokenId)) {
            // Missed this mint, add it now
            const hostessIndex = await this.contract.s_tokenIdToHostess(tokenId);
            const hostessData = config.HOSTESSES[Number(hostessIndex)];

            this.db.upsertNFT({
              tokenId,
              owner: event.args[1],
              hostessIndex: Number(hostessIndex),
              hostessName: hostessData?.name || 'Unknown'
            });
            this.db.incrementHostessCount(Number(hostessIndex));
          }
        }
      }

      this.lastKnownSupply = supply;
    } catch (error) {
      console.error('[Fallback] Supply check error:', error.message);
    }
  }

  stop() {
    if (this.pollInterval) clearInterval(this.pollInterval);
    if (this.fallbackInterval) clearInterval(this.fallbackInterval);
    console.log('[EventListener] Stopped');
  }
}

module.exports = EventListener;
