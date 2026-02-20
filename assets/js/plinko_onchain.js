/**
 * PlinkoOnchain Hook - Blockchain interactions for Plinko game
 *
 * Handles on-chain bet placement via Thirdweb smart wallet:
 * - BUX (ERC-20): check allowance → approve if needed → placeBet
 * - ROGUE (native): placeBetROGUE with value
 * - Error handling with contract error signature mapping
 *
 * Flow:
 * - Server submits commitment via BUX Minter (settler wallet)
 * - Frontend executes approve (if needed) then placeBet
 * - Server settles the bet via BUX Minter after animation
 */

import PlinkoGameABI from './PlinkoGame.json';

const PLINKO_CONTRACT_ADDRESS = "0x7E12c7077556B142F8Fb695F70aAe0359a8be10C";
const BUX_TOKEN_ADDRESS = "0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8";

// Map of known contract error signatures to human-readable messages
const CONTRACT_ERROR_MESSAGES = {
  '0x05d09e5f': 'Bet already settled',
  '0xd0d04f60': 'Token not enabled for betting',
  '0x3a51740d': 'Bet amount too low (minimum 1 token)',
  '0x3f45a891': 'Bet exceeds maximum allowed',
  '0x469bfa91': 'Bet not found on chain',
  '0xb3679761': 'Bet has expired',
  '0x9c220f03': 'Insufficient house balance for this bet',
  '0xeff9b19d': 'Invalid game configuration',
  '0xb6682ad2': 'Commitment not found',
  '0xb7c01e1e': 'Commitment already used',
  '0x28a4d615': 'Commitment belongs to different player',
};

function parseContractError(error) {
  const errorMessage = error?.message || error?.toString() || '';

  for (const [signature, message] of Object.entries(CONTRACT_ERROR_MESSAGES)) {
    if (errorMessage.includes(signature)) {
      return message;
    }
  }

  if (errorMessage.includes('insufficient funds')) {
    return 'Insufficient funds for transaction';
  }
  if (errorMessage.includes('user rejected') || errorMessage.includes('User rejected')) {
    return 'Transaction was cancelled';
  }
  if (errorMessage.includes('nonce')) {
    return 'Transaction nonce error - please try again';
  }
  if (errorMessage.includes('Encoded error signature')) {
    return 'Transaction failed - please check your bet amount and try again';
  }

  return errorMessage;
}

export const PlinkoOnchain = {
  mounted() {
    this.contractAddress = PLINKO_CONTRACT_ADDRESS;
    this.gameId = this.el.dataset.gameId;
    this.commitmentHash = this.el.dataset.commitmentHash;
    this.betConfirmed = false;
    this.betConfirmationTime = null;

    this.handleEvent("place_bet_background", async (params) => {
      this.betConfirmed = false;
      await this.placeBetBackground(params);
    });
  },

  updated() {
    const newGameId = this.el.dataset.gameId;
    const newCommitmentHash = this.el.dataset.commitmentHash;

    if (newGameId && newGameId !== this.gameId) {
      this.gameId = newGameId;
    }
    if (newCommitmentHash && newCommitmentHash !== this.commitmentHash) {
      this.commitmentHash = newCommitmentHash;
    }
  },

  async placeBetBackground({ game_id, commitment_hash, token, token_address, amount, config_index }) {
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

      const amountWei = BigInt(amount) * BigInt(10 ** 18);

      const isROGUE = !token_address ||
                      token_address === null ||
                      token_address === "0x0000000000000000000000000000000000000000";
      let result;

      if (isROGUE) {
        result = await this.executePlaceBetROGUE(
          wallet, amountWei, config_index, commitment_hash
        );
      } else {
        const needsApproval = await this.needsApproval(wallet, token_address, amountWei);

        if (needsApproval) {
          const approveResult = await this.executeApprove(wallet, token_address);
          if (!approveResult.success) {
            this.pushEvent("bet_failed", { game_id, error: approveResult.error });
            return;
          }
        }

        result = await this.executePlaceBet(
          wallet, amountWei, config_index, commitment_hash
        );
      }

      if (result.success) {
        this.betConfirmationTime = Date.now() - startTime;
        this.betConfirmed = true;

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
      console.error("[PlinkoOnchain] Background bet failed:", error);
      this.betConfirmed = false;

      this.pushEvent("bet_failed", {
        game_id: game_id,
        error: parseContractError(error)
      });
    }
  },

  async needsApproval(wallet, tokenAddress, amount) {
    const cacheKey = `plinko_approval_${wallet.address}_${tokenAddress}_${this.contractAddress}`;
    const cachedApproval = localStorage.getItem(cacheKey);

    if (cachedApproval === 'true') {
      return false;
    }

    try {
      const { readContract } = await import("thirdweb");
      const { getContract } = await import("thirdweb/contract");

      const client = window.thirdwebClient;
      const chain = window.rogueChain;

      const tokenContract = getContract({
        client, chain, address: tokenAddress
      });

      const currentAllowance = await readContract({
        contract: tokenContract,
        method: "function allowance(address owner, address spender) view returns (uint256)",
        params: [wallet.address, this.contractAddress]
      });

      const allowanceBigInt = BigInt(currentAllowance);
      const INFINITE_THRESHOLD = BigInt('0x8000000000000000000000000000000000000000000000000000000000000000');

      if (allowanceBigInt >= INFINITE_THRESHOLD) {
        localStorage.setItem(cacheKey, 'true');
        return false;
      }

      if (allowanceBigInt >= amount) {
        return false;
      }

      return true;

    } catch (error) {
      console.error("[PlinkoOnchain] Error checking allowance:", error);
      return true;
    }
  },

  async executeApprove(wallet, tokenAddress) {
    try {
      const { prepareContractCall, sendTransaction, waitForReceipt } = await import("thirdweb");
      const { getContract } = await import("thirdweb/contract");

      const client = window.thirdwebClient;
      const chain = window.rogueChain;

      const tokenContract = getContract({
        client, chain, address: tokenAddress
      });

      const INFINITE_APPROVAL = BigInt('0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff');
      const approveTx = prepareContractCall({
        contract: tokenContract,
        method: "function approve(address spender, uint256 amount) returns (bool)",
        params: [this.contractAddress, INFINITE_APPROVAL]
      });

      const result = await sendTransaction({
        transaction: approveTx,
        account: wallet
      });

      await waitForReceipt({
        client, chain,
        transactionHash: result.transactionHash
      });

      const cacheKey = `plinko_approval_${wallet.address}_${tokenAddress}_${this.contractAddress}`;
      localStorage.setItem(cacheKey, 'true');

      return { success: true, txHash: result.transactionHash };

    } catch (error) {
      console.error("[PlinkoOnchain] Approval transaction error:", error);
      return { success: false, error: parseContractError(error) };
    }
  },

  async executePlaceBet(wallet, amount, configIndex, commitmentHash) {
    try {
      const { prepareContractCall, sendTransaction } = await import("thirdweb");
      const { getContract } = await import("thirdweb/contract");

      const client = window.thirdwebClient;
      const chain = window.rogueChain;

      const gameContract = getContract({
        client, chain,
        address: this.contractAddress,
        abi: PlinkoGameABI.abi
      });

      const placeBetTx = prepareContractCall({
        contract: gameContract,
        method: "function placeBet(uint256 amount, uint8 configIndex, bytes32 commitmentHash) external",
        params: [amount, configIndex, commitmentHash]
      });

      console.log("[PlinkoOnchain] Executing placeBet...");
      const result = await sendTransaction({
        transaction: placeBetTx,
        account: wallet
      });

      console.log("[PlinkoOnchain] PlaceBet tx submitted:", result.transactionHash);
      return { success: true, txHash: result.transactionHash };

    } catch (error) {
      console.error("[PlinkoOnchain] PlaceBet error:", error);
      return { success: false, error: parseContractError(error) };
    }
  },

  async executePlaceBetROGUE(wallet, amount, configIndex, commitmentHash) {
    try {
      const { prepareContractCall, sendTransaction } = await import("thirdweb");
      const { getContract } = await import("thirdweb/contract");

      const client = window.thirdwebClient;
      const chain = window.rogueChain;

      const gameContract = getContract({
        client, chain,
        address: this.contractAddress,
        abi: PlinkoGameABI.abi
      });

      const placeBetTx = prepareContractCall({
        contract: gameContract,
        method: "function placeBetROGUE(uint256 amount, uint8 configIndex, bytes32 commitmentHash) external payable",
        params: [amount, configIndex, commitmentHash],
        value: amount,
        gas: 500000n
      });

      console.log("[PlinkoOnchain] Executing placeBetROGUE with value:", amount.toString());
      const result = await sendTransaction({
        transaction: placeBetTx,
        account: wallet
      });

      console.log("[PlinkoOnchain] PlaceBetROGUE tx submitted:", result.transactionHash);
      return { success: true, txHash: result.transactionHash };

    } catch (error) {
      console.error("[PlinkoOnchain] PlaceBetROGUE error:", error);
      return { success: false, error: parseContractError(error) };
    }
  }
};
