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
      const wallet = window.__solanaWallet;
      if (!wallet) {
        this.pushEvent("tx_failed", {
          vault_type: vaultType,
          action: action,
          error: "No Solana wallet connected. Please connect your wallet."
        });
        return;
      }

      // Decode base64 transaction
      const txBytes = Uint8Array.from(atob(base64Tx), c => c.charCodeAt(0));

      // Use Wallet Standard signAndSendTransaction
      const signAndSend = wallet.features["solana:signAndSendTransaction"];
      if (!signAndSend) {
        this.pushEvent("tx_failed", {
          vault_type: vaultType,
          action: action,
          error: "Wallet does not support signAndSendTransaction"
        });
        return;
      }

      const account = wallet.accounts[0];
      if (!account) {
        this.pushEvent("tx_failed", {
          vault_type: vaultType,
          action: action,
          error: "No account available in wallet"
        });
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

      // Wait for transaction confirmation before notifying LiveView
      console.log(`[PoolHook] ${action} submitted, confirming: ${sig}`);
      await this.connection.confirmTransaction(sig, "confirmed");
      console.log(`[PoolHook] ${action} confirmed: ${sig}`);

      this.pushEvent("tx_confirmed", {
        vault_type: vaultType,
        action: action,
        signature: sig
      });

    } catch (error) {
      console.error(`[PoolHook] ${action} failed:`, error);

      this.pushEvent("tx_failed", {
        vault_type: vaultType,
        action: action,
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
