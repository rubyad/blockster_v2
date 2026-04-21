/**
 * PoolHook — Solana wallet signing for bankroll LP deposits and withdrawals
 *
 * Handles:
 * 1. Receives unsigned transaction (base64) from LiveView
 * 2. Signs with connected Solana wallet via Wallet Standard API
 * 3. Confirms transaction on Solana before notifying LiveView
 * 4. Reports signature back to LiveView
 *
 * Events from LiveView:
 * - "sign_deposit" { transaction, vault_type } → sign deposit tx
 * - "sign_withdraw" { transaction, vault_type } → sign withdraw tx
 *
 * Events to LiveView:
 * - "tx_confirmed" { vault_type, action, signature } → tx confirmed on-chain
 * - "tx_failed" { vault_type, action, error } → tx failed
 */

import { Connection } from "@solana/web3.js";
import bs58 from "bs58";
import { getSigner, pollForConfirmation, decodeBase64Tx } from "./signer.js";

const DEVNET_RPC = "https://api.devnet.solana.com";

export const PoolHook = {
  mounted() {
    this.connection = new Connection(DEVNET_RPC, "confirmed");

    this.handleEvent("sign_deposit", async (params) => {
      await this.signAndSubmit(params.transaction, params.vault_type, "deposit");
    });

    this.handleEvent("sign_withdraw", async (params) => {
      await this.signAndSubmit(params.transaction, params.vault_type, "withdraw");
    });
  },

  async signAndSubmit(base64Tx, vaultType, action) {
    try {
      const signer = getSigner();
      if (!signer) {
        this.pushEvent("tx_failed", {
          vault_type: vaultType,
          action,
          error: "No Solana wallet connected. Please connect your wallet."
        });
        return;
      }

      const txBytes = decodeBase64Tx(base64Tx);
      // signAndSendTransaction preserves settler partial sigs per Wallet
      // Standard spec. Avoid signTransaction+sendRawTransaction because
      // Phantom's signTransaction silently submits in some versions.
      const { signature } = await signer.signAndSendTransaction(txBytes);
      const sig = bs58.encode(new Uint8Array(signature));

      console.log(`[PoolHook] ${action} submitted, confirming: ${sig}`);
      await pollForConfirmation(this.connection, sig);
      console.log(`[PoolHook] ${action} confirmed: ${sig}`);

      this.pushEvent("tx_confirmed", {
        vault_type: vaultType,
        action,
        signature: sig
      });

    } catch (error) {
      console.error(`[PoolHook] ${action} failed:`, error);

      this.pushEvent("tx_failed", {
        vault_type: vaultType,
        action,
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
    return "Transaction confirmation timed out. Please check your wallet and refresh.";
  }

  return msg;
}
