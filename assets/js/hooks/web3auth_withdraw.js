/**
 * Web3AuthWithdraw — user-initiated SOL withdrawal from the /wallet panel.
 *
 * Flow:
 *   1. LiveView pushes `web3auth_withdraw_sign` with { to, amount }.
 *   2. Hook validates destination (real SystemProgram-owned account, not a
 *      token account), builds a SystemProgram.transfer tx, signs + submits.
 *   3. Reports back:
 *        * `withdrawal_submitted` { signature } on success
 *        * `withdrawal_error`     { error }     on failure
 *
 * Despite the name this hook works for BOTH signer sources (Web3Auth MPC or
 * Wallet Standard) since it routes through window.__signer. That's fine —
 * the /wallet page is only rendered for Web3Auth users, but the hook staying
 * source-agnostic means we can reuse it if we ever let wallet users on too.
 *
 * Security posture: no key material touches this hook directly. signer.js
 * owns the key-pull + sign-and-zero lifecycle.
 */

import { Connection, PublicKey, SystemProgram, Transaction } from "@solana/web3.js";
import { getSigner, signAndConfirm } from "./signer.js";

const RPC_URL =
  window.__SOLANA_RPC_URL ||
  "https://summer-sleek-shape.solana-devnet.quiknode.pro/92b7f51caa76f2981879528aee40a3e8e58cac60/";

// Reserve this many lamports for fee + rent exemption minimum. Matches the
// LiveView's conservative 0.001 SOL reserve.
const FEE_RESERVE_LAMPORTS = 1_000_000;

export const Web3AuthWithdraw = {
  mounted() {
    this._connection = new Connection(RPC_URL, "confirmed");

    this.handleEvent("web3auth_withdraw_sign", (payload) => this._sign(payload));
  },

  async _sign({ to, amount }) {
    try {
      const signer = getSigner();
      if (!signer) {
        this.pushEvent("withdrawal_error", {
          error: "No wallet connected. Please sign in again.",
        });
        return;
      }

      // Parse + sanity-check the amount
      const amountFloat = parseFloat(amount);
      if (!Number.isFinite(amountFloat) || amountFloat <= 0) {
        this.pushEvent("withdrawal_error", { error: "Invalid amount" });
        return;
      }
      const lamports = Math.floor(amountFloat * 1_000_000_000);
      if (lamports <= 0) {
        this.pushEvent("withdrawal_error", {
          error: "Amount is below 1 lamport",
        });
        return;
      }

      // Decode the destination. Rejects malformed pubkeys (wrong length, bad
      // base58, etc) via PublicKey constructor throw.
      let toPubkey;
      try {
        toPubkey = new PublicKey(to);
      } catch (_) {
        this.pushEvent("withdrawal_error", {
          error: "Destination is not a valid Solana address",
        });
        return;
      }

      // Common footgun: user pastes a token account (ATA) instead of a
      // wallet. SystemProgram.transfer to an ATA succeeds but the SOL sits
      // unusable inside the token account — effectively a burn. We detect
      // by checking the on-chain owner. A wallet has owner == SystemProgram
      // (or doesn't exist yet, in which case the transfer creates it).
      const destInfo = await this._connection.getAccountInfo(toPubkey, "confirmed");
      if (destInfo && !destInfo.owner.equals(SystemProgram.programId)) {
        this.pushEvent("withdrawal_error", {
          error:
            "Destination looks like a token account, not a wallet. Use the wallet address instead.",
        });
        return;
      }

      // From pubkey
      const fromPubkey = new PublicKey(signer.pubkey);

      // Pre-flight balance check. The LiveView's validation is advisory —
      // re-check here so we catch races (a bet settling between click and
      // sign).
      const balance = await this._connection.getBalance(fromPubkey, "confirmed");
      if (balance < lamports + FEE_RESERVE_LAMPORTS) {
        this.pushEvent("withdrawal_error", {
          error: "Balance changed — amount plus fee exceeds available SOL",
        });
        return;
      }

      // Build + sign + send
      const { blockhash } = await this._connection.getLatestBlockhash("confirmed");

      const tx = new Transaction({
        feePayer: fromPubkey,
        recentBlockhash: blockhash,
      }).add(
        SystemProgram.transfer({
          fromPubkey,
          toPubkey,
          lamports,
        }),
      );

      const serialized = tx.serialize({
        requireAllSignatures: false,
        verifySignatures: false,
      });

      // signAndConfirm handles both Wallet Standard + Web3Auth signers,
      // polls for confirmation via getSignatureStatuses (never websocket),
      // and swallows Phantom's silent auto-submit race.
      const signature = await signAndConfirm(
        signer,
        this._connection,
        new Uint8Array(serialized),
      );

      this.pushEvent("withdrawal_submitted", { signature });
    } catch (err) {
      console.error("[Web3AuthWithdraw] sign error:", err);
      let msg = err?.message || "Transaction failed";

      if (msg.includes("User rejected") || msg.includes("user rejected")) {
        msg = "Transaction cancelled";
      } else if (msg.toLowerCase().includes("insufficient")) {
        msg = "Insufficient SOL balance";
      } else if (msg.toLowerCase().includes("blockhash")) {
        msg = "Blockhash expired — please try again";
      }

      this.pushEvent("withdrawal_error", { error: msg });
    }
  },
};
