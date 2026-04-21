/**
 * AirdropSolanaHook — Solana wallet signing for airdrop deposits and claims
 *
 * Handles:
 * 1. Receives unsigned transaction (base64) from LiveView
 * 2. Signs with connected Solana wallet via Wallet Standard API
 * 3. Sends to RPC and reports signature back to LiveView
 *
 * Events from LiveView:
 * - "sign_airdrop_deposit" { transaction, amount, round_id } → sign deposit tx
 * - "sign_airdrop_claim" { transaction, round_id, winner_index } → sign claim tx
 *
 * Events to LiveView:
 * - "airdrop_deposit_confirmed" { signature, amount, round_id } → deposit succeeded
 * - "airdrop_deposit_error" { error } → deposit failed
 * - "airdrop_claim_confirmed" { signature, winner_index } → claim succeeded
 * - "airdrop_claim_error" { error } → claim failed
 */

import { Connection } from "@solana/web3.js";
import bs58 from "bs58";
import { getSigner, decodeBase64Tx } from "./signer.js";

const DEVNET_RPC = "https://api.devnet.solana.com";

export const AirdropSolanaHook = {
  mounted() {
    this.connection = new Connection(DEVNET_RPC, "confirmed");

    this.handleEvent("sign_airdrop_deposit", async (params) => {
      await this.signAndSubmit(params.transaction, "deposit", {
        amount: params.amount,
        round_id: params.round_id
      });
    });

    this.handleEvent("sign_airdrop_claim", async (params) => {
      await this.signAndSubmit(params.transaction, "claim", {
        round_id: params.round_id,
        winner_index: params.winner_index
      });
    });
  },

  async signAndSubmit(base64Tx, action, metadata) {
    try {
      const signer = getSigner();
      if (!signer) {
        this.pushEvent(`airdrop_${action}_error`, {
          error: "No Solana wallet connected. Please connect your wallet."
        });
        return;
      }

      const txBytes = decodeBase64Tx(base64Tx);
      // signAndSendTransaction preserves settler partial sigs per spec.
      const { signature } = await signer.signAndSendTransaction(txBytes);
      const sig = bs58.encode(new Uint8Array(signature));

      if (action === "deposit") {
        this.pushEvent("airdrop_deposit_confirmed", {
          signature: sig,
          amount: metadata.amount,
          round_id: metadata.round_id
        });
      } else if (action === "claim") {
        this.pushEvent("airdrop_claim_confirmed", {
          signature: sig,
          winner_index: metadata.winner_index
        });
      }

    } catch (error) {
      console.error(`[AirdropSolana] ${action} error:`, error);
      let msg = error.message || "Transaction failed";
      if (msg.includes("User rejected") || msg.includes("user rejected")) {
        msg = "Transaction cancelled";
      } else if (msg.includes("insufficient")) {
        msg = "Insufficient balance";
      }
      this.pushEvent(`airdrop_${action}_error`, { error: msg });
    }
  }
};
