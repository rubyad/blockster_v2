/**
 * AdminTxQueue - Serialized transaction queue for NFTRewarder admin operations
 *
 * All admin wallet transactions (registerNFT, updateOwnership, withdrawTo) must go through
 * this queue to prevent nonce conflicts. The queue processes transactions sequentially,
 * waiting for each to confirm before sending the next.
 *
 * Usage:
 *   const adminTxQueue = require('./services/adminTxQueue');
 *   await adminTxQueue.registerNFT(tokenId, hostessIndex, owner);
 *   await adminTxQueue.updateOwnership(tokenId, newOwner);
 *   await adminTxQueue.withdrawTo(tokenIds, recipient);
 */

const { ethers } = require('ethers');
const config = require('../config');

class AdminTxQueue {
  constructor() {
    this.queue = [];
    this.processing = false;
    this.provider = null;
    this.wallet = null;
    this.contract = null;
    this.initialized = false;
  }

  /**
   * Initialize the admin wallet and contract connection
   * Called lazily on first transaction to allow config to load
   */
  init() {
    if (this.initialized) return true;

    if (!config.ADMIN_PRIVATE_KEY) {
      console.error('[AdminTxQueue] ADMIN_PRIVATE_KEY not configured');
      return false;
    }

    try {
      this.provider = new ethers.JsonRpcProvider(config.ROGUE_RPC_URL);
      this.wallet = new ethers.Wallet(config.ADMIN_PRIVATE_KEY, this.provider);
      this.contract = new ethers.Contract(
        config.NFT_REWARDER_ADDRESS,
        config.NFT_REWARDER_ABI,
        this.wallet
      );
      this.initialized = true;
      console.log(`[AdminTxQueue] Initialized with admin wallet: ${this.wallet.address}`);
      return true;
    } catch (error) {
      console.error('[AdminTxQueue] Failed to initialize:', error.message);
      return false;
    }
  }

  /**
   * Add a transaction to the queue and process
   * @param {string} method - Contract method name
   * @param {Array} args - Method arguments
   * @param {Object} options - Transaction options (gasLimit, etc.)
   * @returns {Promise<Object>} Transaction receipt
   */
  async enqueue(method, args, options = {}) {
    return new Promise((resolve, reject) => {
      this.queue.push({
        method,
        args,
        options,
        resolve,
        reject,
        timestamp: Date.now()
      });

      console.log(`[AdminTxQueue] Enqueued ${method} (queue length: ${this.queue.length})`);
      this.processQueue();
    });
  }

  /**
   * Process the transaction queue sequentially
   */
  async processQueue() {
    if (this.processing || this.queue.length === 0) return;

    if (!this.init()) {
      // Reject all pending transactions if initialization fails
      while (this.queue.length > 0) {
        const tx = this.queue.shift();
        tx.reject(new Error('AdminTxQueue not initialized - ADMIN_PRIVATE_KEY missing'));
      }
      return;
    }

    this.processing = true;

    while (this.queue.length > 0) {
      const tx = this.queue.shift();
      const { method, args, options, resolve, reject, timestamp } = tx;

      const waitTime = Date.now() - timestamp;
      console.log(`[AdminTxQueue] Processing ${method} (waited ${waitTime}ms)`);

      try {
        // Get current nonce to ensure we're using the latest
        const nonce = await this.wallet.getNonce();

        // Execute the contract method
        const txResponse = await this.contract[method](...args, {
          ...options,
          nonce,
          gasLimit: options.gasLimit || 200000
        });

        console.log(`[AdminTxQueue] ${method} tx sent: ${txResponse.hash}`);

        // Wait for confirmation
        const receipt = await txResponse.wait();
        console.log(`[AdminTxQueue] ${method} confirmed in block ${receipt.blockNumber}`);

        resolve(receipt);
      } catch (error) {
        console.error(`[AdminTxQueue] ${method} failed:`, error.message);

        // Check for specific errors
        if (error.message.includes('nonce')) {
          console.error('[AdminTxQueue] Nonce error - this should not happen with sequential processing');
        }

        reject(error);
      }

      // Small delay between transactions to avoid RPC rate limiting
      await new Promise(r => setTimeout(r, 100));
    }

    this.processing = false;
  }

  /**
   * Register a new NFT in the NFTRewarder contract
   * Called when a new NFT is minted on Arbitrum
   *
   * @param {number} tokenId - NFT token ID
   * @param {number} hostessIndex - Hostess type (0-7)
   * @param {string} owner - Owner wallet address
   * @returns {Promise<Object>} Transaction receipt
   */
  async registerNFT(tokenId, hostessIndex, owner) {
    console.log(`[AdminTxQueue] Queueing registerNFT: tokenId=${tokenId}, hostess=${hostessIndex}, owner=${owner}`);
    return this.enqueue('registerNFT', [tokenId, hostessIndex, owner]);
  }

  /**
   * Update NFT ownership in the NFTRewarder contract
   * Called when an NFT is transferred on Arbitrum
   *
   * @param {number} tokenId - NFT token ID
   * @param {string} newOwner - New owner wallet address
   * @returns {Promise<Object>} Transaction receipt
   */
  async updateOwnership(tokenId, newOwner) {
    console.log(`[AdminTxQueue] Queueing updateOwnership: tokenId=${tokenId}, newOwner=${newOwner}`);
    return this.enqueue('updateOwnership', [tokenId, newOwner]);
  }

  /**
   * Withdraw pending rewards for multiple NFTs to a recipient
   * Called when a user requests withdrawal from the UI
   *
   * @param {number[]} tokenIds - Array of NFT token IDs
   * @param {string} recipient - Recipient wallet address
   * @returns {Promise<Object>} Transaction receipt with withdrawn amount
   */
  async withdrawTo(tokenIds, recipient) {
    console.log(`[AdminTxQueue] Queueing withdrawTo: ${tokenIds.length} NFTs to ${recipient}`);
    return this.enqueue('withdrawTo', [tokenIds, recipient], {
      // Base gas + per-NFT gas for reward calculation + extra buffer for ROGUE transfer
      // Each NFT needs ~50k gas for pendingReward calculation and state updates
      // The native ROGUE transfer at the end needs additional gas
      gasLimit: 500000 + (tokenIds.length * 50000)
    });
  }

  /**
   * Claim time-based rewards for special NFTs (2340-2700)
   * Called when a user requests time reward withdrawal
   *
   * @param {number[]} tokenIds - Array of special NFT token IDs
   * @param {string} recipient - Recipient wallet address
   * @returns {Promise<Object>} Transaction receipt
   */
  async claimTimeRewards(tokenIds, recipient) {
    console.log(`[AdminTxQueue] Queueing claimTimeRewards: ${tokenIds.length} special NFTs to ${recipient}`);
    return this.enqueue('claimTimeRewards', [tokenIds, recipient], {
      // Base gas + per-NFT gas for time reward calculation
      // Time rewards are simpler than revenue sharing (just elapsed time * rate)
      gasLimit: 600000 + (tokenIds.length * 60000)
    });
  }

  /**
   * Get queue status for monitoring
   * @returns {Object} Queue status
   */
  getStatus() {
    return {
      initialized: this.initialized,
      processing: this.processing,
      queueLength: this.queue.length,
      walletAddress: this.wallet?.address || null
    };
  }
}

// Export singleton instance
module.exports = new AdminTxQueue();
