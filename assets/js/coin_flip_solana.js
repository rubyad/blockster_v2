/**
 * CoinFlipSolana Hook — Solana wallet signing for Coin Flip game
 *
 * Handles on-chain interactions for the Coin Flip game on Solana:
 * 1. Receives unsigned place_bet transaction from LiveView
 * 2. Signs with connected Solana wallet via Wallet Standard API
 * 3. Confirms on-chain, reports real signature back to LiveView
 *
 * Flow:
 * - Server submits commitment via settler (settler wallet signs)
 * - Server builds unsigned place_bet tx via settler
 * - Frontend signs tx with user wallet, sends to RPC, confirms
 * - Server settles the bet via settler after animation
 *
 * Events from LiveView:
 * - "sign_place_bet" { transaction, game_id, vault_type } → sign & send
 *
 * Events to LiveView:
 * - "bet_confirmed" { game_id, tx_hash, confirmation_time_ms }
 * - "bet_error" { error }
 */

import { Connection } from "@solana/web3.js";

const DEVNET_RPC = "https://api.devnet.solana.com";

export const CoinFlipSolana = {
  mounted() {
    this.gameId = this.el.dataset.gameId;
    this.commitmentHash = this.el.dataset.commitmentHash;
    this.betConfirmed = false;
    this.connection = new Connection(DEVNET_RPC, "confirmed");

    // Listen for unsigned tx from LiveView
    this.handleEvent("sign_place_bet", async (params) => {
      this.betConfirmed = false;
      await this.signAndPlaceBet(params);
    });

    // Listen for reclaim tx (clear stuck bet)
    this.handleEvent("sign_reclaim", async ({ transaction }) => {
      await this.signAndSendSimple(transaction, "reclaim_confirmed", "reclaim_failed");
    });

    // Listen for settlement complete
    this.handleEvent("bet_settled", () => {
      // Settlement complete — UI already updated by LiveView
    });
  },

  async signAndSendSimple(base64Tx, successEvent, failEvent) {
    try {
      const wallet = window.__solanaWallet;
      if (!wallet) { this.pushEvent(failEvent, { error: "No wallet connected" }); return; }

      const txBytes = Uint8Array.from(atob(base64Tx), c => c.charCodeAt(0));
      const signAndSend = wallet.features["solana:signAndSendTransaction"];
      if (!signAndSend) { this.pushEvent(failEvent, { error: "Wallet does not support signing" }); return; }

      const account = wallet.accounts[0];
      if (!account) { this.pushEvent(failEvent, { error: "No account in wallet" }); return; }

      const [{ signature }] = await signAndSend.signAndSendTransaction({
        account, transaction: txBytes, chain: "solana:devnet"
      });

      const { default: bs58 } = await import("bs58");
      const sig = bs58.encode(new Uint8Array(signature));

      console.log(`[CoinFlipSolana] ${successEvent} tx submitted, confirming: ${sig}`);
      await this.connection.confirmTransaction(sig, "confirmed");
      console.log(`[CoinFlipSolana] ${successEvent} confirmed: ${sig}`);

      this.pushEvent(successEvent, { signature: sig });
    } catch (error) {
      console.error(`[CoinFlipSolana] ${failEvent}:`, error);
      this.pushEvent(failEvent, { error: parseError(error) });
    }
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

  async signAndPlaceBet({ transaction, game_id, vault_type }) {
    const startTime = Date.now();

    try {
      const wallet = window.__solanaWallet;
      if (!wallet) {
        this.pushEvent("bet_error", {
          error: "No Solana wallet connected. Please connect your wallet and try again."
        });
        return;
      }

      // Decode base64 transaction
      const txBytes = Uint8Array.from(atob(transaction), c => c.charCodeAt(0));

      // Sign and send via Wallet Standard
      const signAndSend = wallet.features["solana:signAndSendTransaction"];
      if (!signAndSend) {
        this.pushEvent("bet_error", { error: "Wallet does not support signAndSendTransaction" });
        return;
      }

      const account = wallet.accounts[0];
      if (!account) {
        this.pushEvent("bet_error", { error: "No account available in wallet" });
        return;
      }

      const [{ signature }] = await signAndSend.signAndSendTransaction({
        account,
        transaction: txBytes,
        chain: "solana:devnet"
      });

      // Convert signature to base58
      const { default: bs58 } = await import("bs58");
      const sig = bs58.encode(new Uint8Array(signature));

      // Wait for on-chain confirmation
      console.log(`[CoinFlipSolana] Bet tx submitted, confirming: ${sig}`);
      await this.connection.confirmTransaction(sig, "confirmed");

      const confirmationTime = Date.now() - startTime;
      console.log(`[CoinFlipSolana] Bet confirmed in ${confirmationTime}ms: ${sig}`);

      this.betConfirmed = true;
      this.pushEvent("bet_confirmed", {
        game_id: game_id,
        tx_hash: sig,
        confirmation_time_ms: confirmationTime
      });

    } catch (error) {
      console.error("[CoinFlipSolana] Bet failed:", error);
      this.betConfirmed = false;

      this.pushEvent("bet_error", {
        error: parseError(error)
      });
    }
  }
};

function parseError(error) {
  const msg = error?.message || error?.toString() || "Unknown error";

  if (msg.includes("user rejected") || msg.includes("User rejected")) {
    return "Transaction was cancelled";
  }
  if (msg.includes("insufficient funds") || msg.includes("Insufficient")) {
    return "Insufficient funds for transaction";
  }
  if (msg.includes("not connected") || msg.includes("No wallet")) {
    return "Wallet not connected. Please connect your wallet.";
  }
  if (msg.includes("timeout") || msg.includes("Timeout")) {
    return "Transaction confirmation timed out. Please refresh and try again.";
  }
  if (msg.includes("simulation") || msg.includes("Simulation") || msg.includes("simulate")) {
    // Try to extract the program error from simulation logs
    const maxBetMatch = msg.match(/BetExceedsMax|MaxBetExceeded/i);
    if (maxBetMatch) {
      return "Bet exceeds the maximum allowed for this difficulty. Try a smaller amount.";
    }
    const payoutMatch = msg.match(/PayoutExceedsMax/i);
    if (payoutMatch) {
      return "Payout exceeds maximum. Try a smaller bet amount.";
    }
    const fundsMatch = msg.match(/insufficient|InsufficientFunds/i);
    if (fundsMatch) {
      return "Insufficient funds for this bet (including transaction fees).";
    }
    return "Transaction failed during simulation. The bet may exceed on-chain limits or funds are insufficient.";
  }

  return msg;
}
