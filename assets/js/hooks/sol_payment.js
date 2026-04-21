/**
 * SolPaymentHook — lets a buyer send SOL directly from their connected
 * Solana wallet to the order's unique payment intent pubkey.
 *
 * Flow:
 *   1. Checkout LiveView pushes `send_sol_payment` with { to, lamports, order_id }.
 *   2. Hook builds a SystemProgram.transfer, asks the wallet to sign+send.
 *   3. Hook reports `sol_payment_submitted` (signature) or `sol_payment_error`.
 *   4. Server-side PaymentIntentWatcher polls the settler and flips the
 *      order to "paid" once the balance lands on chain.
 *
 * Also handles the `#intent-countdown` display — a simple ticker that
 * counts down to the intent's expiry timestamp.
 */

import {
  Connection,
  PublicKey,
  SystemProgram,
  Transaction,
} from "@solana/web3.js";
import bs58 from "bs58";
import { getSigner } from "./signer.js";

const RPC_URL =
  window.__SOLANA_RPC_URL ||
  "https://summer-sleek-shape.solana-devnet.quiknode.pro/92b7f51caa76f2981879528aee40a3e8e58cac60/";

export const SolPaymentHook = {
  mounted() {
    this._connection = new Connection(RPC_URL, "confirmed");
    this._countdownTimer = null;
    this._startCountdown();

    this.handleEvent("send_sol_payment", (payload) => this._sendPayment(payload));
  },

  updated() {
    // Re-attach the countdown timer if the DOM node for it was re-rendered.
    this._startCountdown();
  },

  destroyed() {
    if (this._countdownTimer) clearInterval(this._countdownTimer);
  },

  async _sendPayment({ to, lamports, order_id }) {
    try {
      const signer = getSigner();
      if (!signer) {
        this.pushEvent("sol_payment_error", {
          error: "No Solana wallet connected. Please reconnect.",
        });
        return;
      }

      const fromPubkey = new PublicKey(signer.pubkey);
      const toPubkey = new PublicKey(to);

      const { blockhash } = await this._connection.getLatestBlockhash("confirmed");

      const tx = new Transaction({
        feePayer: fromPubkey,
        recentBlockhash: blockhash,
      }).add(
        SystemProgram.transfer({
          fromPubkey,
          toPubkey,
          lamports: Number(lamports),
        }),
      );

      const serialized = tx.serialize({
        requireAllSignatures: false,
        verifySignatures: false,
      });

      const { signature } = await signer.signAndSendTransaction(new Uint8Array(serialized));
      const sig = bs58.encode(new Uint8Array(signature));

      this.pushEvent("sol_payment_submitted", {
        signature: sig,
        order_id,
      });
    } catch (err) {
      console.error("[SolPayment] error:", err);
      let msg = err.message || "Transaction failed";
      if (msg.includes("User rejected") || msg.includes("user rejected")) {
        msg = "Transaction cancelled";
      } else if (msg.includes("insufficient")) {
        msg = "Insufficient SOL balance";
      }
      this.pushEvent("sol_payment_error", { error: msg });
    }
  },

  _startCountdown() {
    const el = document.getElementById("intent-countdown");
    if (!el || el.dataset.hooked === "1") return;
    el.dataset.hooked = "1";

    const target = el.dataset.expiresAt;
    if (!target) return;

    const tick = () => {
      const remaining = new Date(target).getTime() - Date.now();
      if (remaining <= 0) {
        el.textContent = "expired";
        if (this._countdownTimer) clearInterval(this._countdownTimer);
        return;
      }
      const mins = Math.floor(remaining / 60000);
      const secs = Math.floor((remaining % 60000) / 1000);
      el.textContent = `${mins}m ${secs.toString().padStart(2, "0")}s`;
    };

    tick();
    if (this._countdownTimer) clearInterval(this._countdownTimer);
    this._countdownTimer = setInterval(tick, 1000);
  },
};
