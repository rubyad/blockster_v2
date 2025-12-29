/**
 * BuxBoosterOnchain Hook - OPTIMIZED FOR SPEED
 *
 * Handles on-chain interactions for the BUX Booster game with performance optimizations:
 * 1. Sequential approve + placeBet transactions (with receipt waiting)
 * 2. Infinite approval with localStorage caching
 * 3. Optimistic UI updates (don't wait for placeBet receipt)
 * 4. Background receipt polling for betId
 *
 * Optimizations reduce transaction time on repeat bets from ~6s to ~2-3s via approval caching
 *
 * Flow:
 * - Server submits commitment via BUX Minter (settler wallet)
 * - Frontend executes approve (if needed) then placeBet in separate transactions
 * - Server settles the bet via BUX Minter after animation
 */

import BuxBoosterGameArtifact from './BuxBoosterGame.json';

export const BuxBoosterOnchain = {
  mounted() {
    this.contractAddress = "0x97b6d6A8f2c6AF6e6fb40f8d36d60DF2fFE4f17B";

    // Get game_id and commitment_hash from data attributes (set by LiveView)
    this.gameId = this.el.dataset.gameId;
    this.commitmentHash = this.el.dataset.commitmentHash;
    console.log("[BuxBoosterOnchain] Mounted with game:", this.gameId, "commitment:", this.commitmentHash);

    // Track bet confirmation status
    this.betConfirmed = false;
    this.betConfirmationTime = null;

    // Listen for BACKGROUND place_bet request (non-blocking)
    this.handleEvent("place_bet_background", async (params) => {
      console.log("[BuxBoosterOnchain] Background bet submission:", params);
      this.betConfirmed = false;
      await this.placeBetBackground(params);
    });

    // Listen for settlement complete
    this.handleEvent("bet_settled", ({ won, payout }) => {
      console.log("[BuxBoosterOnchain] Bet settled:", { won, payout });
    });
  },

  updated() {
    // Update game_id and commitment_hash when LiveView updates
    const newGameId = this.el.dataset.gameId;
    const newCommitmentHash = this.el.dataset.commitmentHash;

    // Log when these values become available
    if (newGameId && newGameId !== this.gameId) {
      console.log("[BuxBoosterOnchain] Game ID updated:", newGameId);
      this.gameId = newGameId;
    }

    if (newCommitmentHash && newCommitmentHash !== this.commitmentHash) {
      console.log("[BuxBoosterOnchain] Commitment hash updated:", newCommitmentHash);
      this.commitmentHash = newCommitmentHash;
    }
  },

  async placeBetBackground({ game_id, token_address, amount, difficulty, predictions, commitment_hash }) {
    const startTime = Date.now();

    try {
      const wallet = window.smartAccount;
      if (!wallet) {
        this.pushEvent("bet_failed", {
          game_id: game_id,
          error: "No wallet connected. Please refresh and try again."
        });
        return;
      }

      const walletAddress = wallet.address;
      console.log("[BuxBoosterOnchain] Wallet address:", walletAddress);

      // Convert amount to wei (18 decimals)
      const amountWei = BigInt(amount) * BigInt(10 ** 18);

      // predictions are already uint8 (0 = heads, 1 = tails) from server
      const predictionsArray = predictions.map(p => Number(p));
      console.log("[BuxBoosterOnchain] Predictions (as numbers):", predictionsArray);

      // Check if we need approval (with cache optimization)
      console.log("[BuxBoosterOnchain] Checking approval status...");
      const needsApproval = await this.needsApproval(wallet, token_address, amountWei);

      let result;
      if (needsApproval) {
        // Execute approve first, then placeBet (sequential transactions)
        console.log("[BuxBoosterOnchain] Executing approval transaction...");
        const approveResult = await this.executeApprove(wallet, token_address);

        if (!approveResult.success) {
          this.pushEvent("bet_error", { error: approveResult.error });
          return;
        }

        console.log("[BuxBoosterOnchain] ✅ Approval confirmed, now placing bet...");
        result = await this.executePlaceBet(
          wallet,
          token_address,
          amountWei,
          difficulty,
          predictionsArray,
          commitment_hash
        );
      } else {
        // Already approved, just place bet
        console.log("[BuxBoosterOnchain] Already approved, placing bet...");
        result = await this.executePlaceBet(
          wallet,
          token_address,
          amountWei,
          difficulty,
          predictionsArray,
          commitment_hash
        );
      }

      if (result.success) {
        // Calculate confirmation time
        this.betConfirmationTime = Date.now() - startTime;
        this.betConfirmed = true;

        console.log(`[BuxBoosterOnchain] ✅ Bet confirmed in ${this.betConfirmationTime}ms`);

        // Notify backend that bet is confirmed
        this.pushEvent("bet_confirmed", {
          game_id: game_id,
          tx_hash: result.txHash,
          confirmation_time_ms: this.betConfirmationTime
        });
      } else {
        this.pushEvent("bet_failed", {
          game_id: game_id,
          error: result.error
        });
      }

    } catch (error) {
      console.error("[BuxBoosterOnchain] Background bet failed:", error);
      this.betConfirmed = false;

      this.pushEvent("bet_failed", {
        game_id: game_id,
        error: error.message || "Transaction failed"
      });
    }
  },

  /**
   * Check if approval is needed using localStorage cache + on-chain verification
   * Uses infinite approval strategy to minimize future approvals
   */
  async needsApproval(wallet, tokenAddress, amount) {
    const cacheKey = `approval_${wallet.address}_${tokenAddress}_${this.contractAddress}`;
    const cachedApproval = localStorage.getItem(cacheKey);

    // If cached as approved, skip on-chain check
    if (cachedApproval === 'true') {
      console.log("[BuxBoosterOnchain] Using cached approval ✅");
      return false;
    }

    // Check on-chain allowance
    try {
      const { readContract } = await import("thirdweb");
      const { getContract } = await import("thirdweb/contract");

      const client = window.thirdwebClient;
      const chain = window.rogueChain;

      const tokenContract = getContract({
        client,
        chain,
        address: tokenAddress
      });

      const currentAllowance = await readContract({
        contract: tokenContract,
        method: "function allowance(address owner, address spender) view returns (uint256)",
        params: [wallet.address, this.contractAddress]
      });

      const allowanceBigInt = BigInt(currentAllowance);
      const INFINITE_THRESHOLD = BigInt('0x8000000000000000000000000000000000000000000000000000000000000000'); // Half of max uint256

      // If allowance is effectively infinite, cache it
      if (allowanceBigInt >= INFINITE_THRESHOLD) {
        console.log("[BuxBoosterOnchain] Infinite approval detected, caching ✅");
        localStorage.setItem(cacheKey, 'true');
        return false;
      }

      // Check if current allowance is enough
      if (allowanceBigInt >= amount) {
        console.log("[BuxBoosterOnchain] Sufficient allowance:", allowanceBigInt.toString());
        // Don't cache limited approvals as they may be consumed
        return false;
      }

      console.log("[BuxBoosterOnchain] Need approval:", {
        current: allowanceBigInt.toString(),
        needed: amount.toString()
      });
      return true;

    } catch (error) {
      console.error("[BuxBoosterOnchain] Error checking allowance:", error);
      // Assume approval needed on error
      return true;
    }
  },

  /**
   * Execute approve transaction separately
   * Uses infinite approval to avoid future approval transactions
   * Waits for receipt to ensure approval is confirmed before proceeding
   */
  async executeApprove(wallet, tokenAddress) {
    try {
      const { prepareContractCall, sendTransaction, waitForReceipt } = await import("thirdweb");
      const { getContract } = await import("thirdweb/contract");

      const client = window.thirdwebClient;
      const chain = window.rogueChain;

      const tokenContract = getContract({
        client,
        chain,
        address: tokenAddress
      });

      const INFINITE_APPROVAL = BigInt('0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff');
      const approveTx = prepareContractCall({
        contract: tokenContract,
        method: "function approve(address spender, uint256 amount) returns (bool)",
        params: [this.contractAddress, INFINITE_APPROVAL]
      });

      console.log("[BuxBoosterOnchain] Sending approve transaction...");
      const result = await sendTransaction({
        transaction: approveTx,
        account: wallet
      });

      console.log("[BuxBoosterOnchain] Approve tx submitted:", result.transactionHash);
      console.log("[BuxBoosterOnchain] Waiting for approval confirmation...");

      // Wait for approval to be confirmed
      await waitForReceipt({
        client,
        chain,
        transactionHash: result.transactionHash
      });

      console.log("[BuxBoosterOnchain] ✅ Approval confirmed");

      // Cache the infinite approval
      const cacheKey = `approval_${wallet.address}_${tokenAddress}_${this.contractAddress}`;
      localStorage.setItem(cacheKey, 'true');

      return {
        success: true,
        txHash: result.transactionHash
      };

    } catch (error) {
      console.error("[BuxBoosterOnchain] Approval transaction error:", error);
      return {
        success: false,
        error: error.message || "Approval failed"
      };
    }
  },

  /**
   * Execute placeBet only (approval already done)
   */
  async executePlaceBet(wallet, tokenAddress, amount, difficulty, predictions, commitmentHash) {
    try {
      const { prepareContractCall, sendTransaction } = await import("thirdweb");
      const { getContract } = await import("thirdweb/contract");

      const client = window.thirdwebClient;
      const chain = window.rogueChain;

      const gameContract = getContract({
        client,
        chain,
        address: this.contractAddress,
        abi: BuxBoosterGameArtifact.abi
      });

      const placeBetTx = prepareContractCall({
        contract: gameContract,
        method: "function placeBet(address token, uint256 amount, int8 difficulty, uint8[] calldata predictions, bytes32 commitmentHash) external",
        params: [tokenAddress, amount, difficulty, predictions, commitmentHash]
      });

      console.log("[BuxBoosterOnchain] Executing placeBet...");
      const result = await sendTransaction({
        transaction: placeBetTx,
        account: wallet
      });

      console.log("[BuxBoosterOnchain] ✅ PlaceBet tx submitted:", result.transactionHash);

      return {
        success: true,
        txHash: result.transactionHash
      };

    } catch (error) {
      console.error("[BuxBoosterOnchain] PlaceBet error:", error);
      return {
        success: false,
        error: error.message || "PlaceBet failed"
      };
    }
  },

  /**
   * Poll for transaction receipt in background to get actual betId
   * This doesn't block the UI - betId is sent to server when ready
   */
  async pollForBetId(txHash) {
    try {
      const { waitForReceipt } = await import("thirdweb");
      const client = window.thirdwebClient;
      const chain = window.rogueChain;

      console.log("[BuxBoosterOnchain] Polling for receipt...");
      const receipt = await waitForReceipt({
        client,
        chain,
        transactionHash: txHash
      });

      // Parse the BetPlaced event to get the actual betId
      // Event: BetPlaced(bytes32 indexed betId, address indexed player, address indexed token, ...)
      let betId = this.commitmentHash; // fallback

      if (receipt.logs && receipt.logs.length > 0) {
        for (const log of receipt.logs) {
          // BetPlaced has 4 topics (event sig + 3 indexed params)
          if (log.topics && log.topics.length === 4 &&
              log.address?.toLowerCase() === this.contractAddress.toLowerCase()) {
            betId = log.topics[1];
            console.log("[BuxBoosterOnchain] ✅ Found BetPlaced event, betId:", betId);
            break;
          }
        }
      }

      // Send confirmed betId to server (if different from commitment)
      if (betId !== this.commitmentHash) {
        this.pushEvent("bet_confirmed", {
          game_id: this.gameId,
          bet_id: betId,
          tx_hash: txHash
        });
      }

    } catch (error) {
      console.error("[BuxBoosterOnchain] Error polling for betId:", error);
      // Not critical - server can use commitment hash as betId
    }
  }
};
