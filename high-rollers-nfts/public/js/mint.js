// High Rollers NFT - Mint Service

class MintService {
  constructor() {
    this.pendingMint = null;
    this.pollInterval = null;
    this.maxPollAttempts = 60;  // 5 minutes at 5-second intervals
    this.pollAttempts = 0;
    this.onMintRequestedCallbacks = [];
    this.onMintCompleteCallbacks = [];
    this.onMintErrorCallbacks = [];
  }

  /**
   * Mint a new NFT
   */
  async mint() {
    if (!walletService.isConnected()) {
      throw new Error('Please connect your wallet first');
    }

    const contract = walletService.getContract();

    // Note: Affiliate linking is now handled server-side when wallet connects
    // The server calls linkAffiliate using the affiliateLinker wallet
    // This ensures proper on-chain linking with the authorized wallet

    // Send mint transaction
    const tx = await contract.requestNFT({
      value: CONFIG.MINT_PRICE
    });

    console.log('Mint transaction sent:', tx.hash);

    // Wait for confirmation
    const receipt = await tx.wait();
    console.log('Transaction confirmed:', receipt);

    // Parse the NFTRequested event from the receipt
    let requestId, tokenId;

    for (const log of receipt.logs) {
      try {
        const parsed = contract.interface.parseLog({
          topics: log.topics,
          data: log.data
        });
        if (parsed && parsed.name === 'NFTRequested') {
          requestId = parsed.args[0].toString();
          tokenId = parsed.args[3].toString();
          break;
        }
      } catch (e) {
        // Not our event, skip
      }
    }

    if (requestId) {
      this.pendingMint = {
        requestId,
        tokenId,
        txHash: tx.hash,
        timestamp: Date.now()
      };

      // Start fallback polling in case we miss the event
      this.startFallbackPolling();

      this.onMintRequestedCallbacks.forEach(cb => cb({
        requestId,
        tokenId,
        txHash: tx.hash
      }));
    }

    return {
      txHash: tx.hash,
      requestId,
      tokenId
    };
  }

  /**
   * Fallback polling: Check if our NFT was minted even if we miss the WebSocket event
   */
  startFallbackPolling() {
    this.pollAttempts = 0;

    this.pollInterval = setInterval(async () => {
      this.pollAttempts++;

      if (this.pollAttempts > this.maxPollAttempts) {
        this.stopFallbackPolling();
        console.error('Mint polling timeout - check Arbiscan for status');
        this.onMintErrorCallbacks.forEach(cb => cb(new Error('Mint confirmation timeout')));
        return;
      }

      try {
        // Check if our pending NFT has been minted
        const tokenId = parseInt(this.pendingMint.tokenId);
        const contract = walletService.getReadOnlyContract();

        const owner = await contract.ownerOf(tokenId);

        if (owner && owner.toLowerCase() === walletService.address.toLowerCase()) {
          // Our NFT was minted!
          console.log(`[Fallback Poll] NFT ${tokenId} minted successfully`);

          const hostessIndex = await contract.s_tokenIdToHostess(tokenId);
          this.handleMintComplete(this.pendingMint.requestId, tokenId, Number(hostessIndex));
          this.stopFallbackPolling();
        }
      } catch (error) {
        // Token doesn't exist yet, keep polling
        console.log(`[Fallback Poll] Attempt ${this.pollAttempts}: waiting for mint...`);
      }
    }, 5000); // Poll every 5 seconds
  }

  stopFallbackPolling() {
    if (this.pollInterval) {
      clearInterval(this.pollInterval);
      this.pollInterval = null;
    }
  }

  handleMintComplete(requestId, tokenId, hostessIndex) {
    this.stopFallbackPolling();

    const hostess = CONFIG.HOSTESSES[hostessIndex];

    const result = {
      requestId: requestId.toString(),
      tokenId: tokenId.toString(),
      hostessIndex,
      hostessName: hostess?.name || 'Unknown',
      hostessRarity: hostess?.rarity || 'Unknown',
      hostessMultiplier: hostess?.multiplier || 0,
      hostessImage: hostess?.image || '',
      txHash: this.pendingMint?.txHash
    };

    this.onMintCompleteCallbacks.forEach(cb => cb(result));
    this.pendingMint = null;
  }

  /**
   * Handle WebSocket mint event
   */
  handleWebSocketMintEvent(data) {
    // Check if this is our mint
    if (this.pendingMint &&
        data.recipient.toLowerCase() === walletService.address?.toLowerCase()) {
      this.handleMintComplete(data.requestId, data.tokenId, data.hostessIndex);
    }
  }

  /**
   * Register callbacks
   */
  onMintRequested(callback) {
    this.onMintRequestedCallbacks.push(callback);
  }

  onMintComplete(callback) {
    this.onMintCompleteCallbacks.push(callback);
  }

  onMintError(callback) {
    this.onMintErrorCallbacks.push(callback);
  }

  /**
   * Check if currently minting
   */
  isMinting() {
    return this.pendingMint !== null;
  }
}

// Global mint service instance
window.mintService = new MintService();
