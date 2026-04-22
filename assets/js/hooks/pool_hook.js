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
import { getSigner, signAndConfirm, decodeBase64Tx } from "./signer.js";

// QuickNode RPC — public api.devnet.solana.com rate-limits to 429 within
// seconds of signAndConfirm's polling loop. Prod should wire
// window.__SOLANA_RPC_URL to the mainnet endpoint.
const RPC_URL =
  window.__SOLANA_RPC_URL ||
  "https://summer-sleek-shape.solana-devnet.quiknode.pro/92b7f51caa76f2981879528aee40a3e8e58cac60/";

export const PoolHook = {
  mounted() {
    this.connection = new Connection(RPC_URL, "confirmed");

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
      // signAndConfirm routes through the right method for each signer
      // source: Wallet Standard (Phantom et al) uses signTransaction +
      // own-submit with duplicate-handling for Phantom's silent-submit
      // quirk; Web3Auth uses signTransaction + own-submit cleanly. Both
      // poll for confirmation before resolving. Web3Auth's signer throws
      // on signAndSendTransaction by design — don't call it directly.
      const sig = await signAndConfirm(signer, this.connection, txBytes);
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
