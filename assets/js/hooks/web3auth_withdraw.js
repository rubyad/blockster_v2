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

import {
  Connection,
  PublicKey,
  SystemProgram,
  Transaction,
  TransactionInstruction,
} from "@solana/web3.js";
import { getSigner, signAndConfirm } from "./signer.js";

const RPC_URL =
  window.__SOLANA_RPC_URL ||
  "https://summer-sleek-shape.solana-devnet.quiknode.pro/92b7f51caa76f2981879528aee40a3e8e58cac60/";

// Reserve this many lamports for fee + rent exemption minimum. Matches the
// LiveView's conservative 0.001 SOL reserve.
const FEE_RESERVE_LAMPORTS = 1_000_000;

// SPL Token + Associated Token Account programs. Same on every network.
const TOKEN_PROGRAM_ID = new PublicKey(
  "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA",
);
const ASSOCIATED_TOKEN_PROGRAM_ID = new PublicKey(
  "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL",
);

// Derive a user's Associated Token Account for a given mint. PDA of
// [owner, token_program, mint] under the ATA program.
function deriveAta(owner, mint) {
  const [ata] = PublicKey.findProgramAddressSync(
    [owner.toBuffer(), TOKEN_PROGRAM_ID.toBuffer(), mint.toBuffer()],
    ASSOCIATED_TOKEN_PROGRAM_ID,
  );
  return ata;
}

// Build an Idempotent "CreateAssociatedTokenAccount" ix. The idempotent
// variant (discriminator 1) is safe to include even if the ATA already
// exists — matches spl-token's `createAssociatedTokenAccountIdempotent`.
function buildCreateAtaIdempotentIx({ funder, ata, owner, mint }) {
  return new TransactionInstruction({
    programId: ASSOCIATED_TOKEN_PROGRAM_ID,
    keys: [
      { pubkey: funder, isSigner: true,  isWritable: true  },
      { pubkey: ata,    isSigner: false, isWritable: true  },
      { pubkey: owner,  isSigner: false, isWritable: false },
      { pubkey: mint,   isSigner: false, isWritable: false },
      { pubkey: SystemProgram.programId, isSigner: false, isWritable: false },
      { pubkey: TOKEN_PROGRAM_ID,         isSigner: false, isWritable: false },
    ],
    data: Buffer.from([1]),
  });
}

// Hand-roll a TransferChecked instruction. Layout (10 bytes):
//   [0]   discriminator = 12 (TransferChecked)
//   [1-8] amount as u64 little-endian
//   [9]   decimals as u8
// Accounts (per SPL Token spec):
//   [0] writable source_ata
//   [1] readonly mint
//   [2] writable dest_ata
//   [3] signer    owner
function buildTransferCheckedIx({ sourceAta, mint, destAta, owner, amountRaw, decimals }) {
  const data = new Uint8Array(10);
  data[0] = 12;
  const view = new DataView(data.buffer);
  const lo = Number(amountRaw & 0xffffffffn);
  const hi = Number((amountRaw >> 32n) & 0xffffffffn);
  view.setUint32(1, lo, true);
  view.setUint32(5, hi, true);
  data[9] = decimals;

  return new TransactionInstruction({
    programId: TOKEN_PROGRAM_ID,
    keys: [
      { pubkey: sourceAta, isSigner: false, isWritable: true  },
      { pubkey: mint,      isSigner: false, isWritable: false },
      { pubkey: destAta,   isSigner: false, isWritable: true  },
      { pubkey: owner,     isSigner: true,  isWritable: false },
    ],
    data: data,
  });
}

export const Web3AuthWithdraw = {
  mounted() {
    this._connection = new Connection(RPC_URL, "confirmed");

    this.handleEvent("web3auth_withdraw_sign",       (payload) => this._sign(payload));
    this.handleEvent("web3auth_withdraw_token_sign", (payload) => this._signToken(payload));
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

  // ── SPL token transfer path ──────────────────────────────────────────
  // Handles BUX, SOL-LP (bSOL), BUX-LP (bBUX). Payload:
  //   { to, amount, token, mint, decimals }
  // Builds:
  //   1. createAssociatedTokenAccountIdempotent (recipient ATA) — safe
  //      to include every time; costs nothing if the ATA already exists,
  //      pays ~0.002 SOL rent if it doesn't.
  //   2. transferChecked from sender's ATA to recipient's ATA.
  // Signs with the connected wallet and submits via signAndConfirm.
  async _signToken({ to, amount, token, mint, decimals }) {
    try {
      const signer = getSigner();
      if (!signer) {
        this.pushEvent("withdrawal_error", {
          error: "No wallet connected. Please sign in again.",
        });
        return;
      }

      // Amount → base units (u64 bigint)
      const amountFloat = parseFloat(amount);
      if (!Number.isFinite(amountFloat) || amountFloat <= 0) {
        this.pushEvent("withdrawal_error", { error: "Invalid amount" });
        return;
      }
      const scale = BigInt(10) ** BigInt(decimals);
      // Avoid floating-point drift: parse the string, multiply by scale as
      // strings where possible. For typical UI inputs (≤ 9 decimals) this is
      // safe via Math.floor(float * scale); we keep integer math on-chain.
      const amountRaw = BigInt(Math.floor(amountFloat * Number(scale)));
      if (amountRaw <= 0n) {
        this.pushEvent("withdrawal_error", { error: "Amount is too small" });
        return;
      }

      // Parse recipient
      let toPubkey;
      try {
        toPubkey = new PublicKey(to);
      } catch (_) {
        this.pushEvent("withdrawal_error", {
          error: "Destination is not a valid Solana address",
        });
        return;
      }

      // Footgun guard: if the user pasted a token account (not a wallet),
      // creating an ATA under it would fail or write to the wrong owner.
      // Require the recipient to be a System-owned account OR not yet
      // initialized (brand-new wallets are also fine).
      const destInfo = await this._connection.getAccountInfo(toPubkey, "confirmed");
      if (destInfo && !destInfo.owner.equals(SystemProgram.programId)) {
        this.pushEvent("withdrawal_error", {
          error: "Destination looks like a token account, not a wallet. Use the wallet address instead.",
        });
        return;
      }

      const fromPubkey = new PublicKey(signer.pubkey);
      const mintPubkey = new PublicKey(mint);
      const sourceAta  = deriveAta(fromPubkey, mintPubkey);
      const destAta    = deriveAta(toPubkey,   mintPubkey);

      // Pre-flight: confirm source ATA exists + has enough balance. Avoids
      // tossing the tx on chain just to watch it fail.
      const sourceInfo = await this._connection.getTokenAccountBalance(sourceAta).catch(() => null);
      if (!sourceInfo || !sourceInfo.value) {
        this.pushEvent("withdrawal_error", {
          error: `You have no ${token} balance to send`,
        });
        return;
      }
      const sourceRaw = BigInt(sourceInfo.value.amount);
      if (sourceRaw < amountRaw) {
        this.pushEvent("withdrawal_error", {
          error: `Amount exceeds your ${token} balance`,
        });
        return;
      }

      // Also pre-flight SOL for fees + (possibly) ATA rent. Conservative
      // estimate — leaves the user clear feedback instead of a chain error.
      const solBalance = await this._connection.getBalance(fromPubkey, "confirmed");
      if (solBalance < FEE_RESERVE_LAMPORTS) {
        this.pushEvent("withdrawal_error", {
          error: "Not enough SOL for transaction fees (need ~0.001 SOL)",
        });
        return;
      }

      // Build tx. We always include the Idempotent ATA-create for the
      // recipient — ~0 cost when it exists, ~0.002 SOL rent when it
      // doesn't. Cheaper than doing a separate getAccountInfo round-trip
      // that might race with someone else funding the ATA first.
      const { blockhash } = await this._connection.getLatestBlockhash("confirmed");

      const tx = new Transaction({
        feePayer: fromPubkey,
        recentBlockhash: blockhash,
      })
        .add(
          buildCreateAtaIdempotentIx({
            funder: fromPubkey,
            ata: destAta,
            owner: toPubkey,
            mint: mintPubkey,
          }),
        )
        .add(
          buildTransferCheckedIx({
            sourceAta,
            mint: mintPubkey,
            destAta,
            owner: fromPubkey,
            amountRaw,
            decimals,
          }),
        );

      const serialized = tx.serialize({
        requireAllSignatures: false,
        verifySignatures: false,
      });

      const signature = await signAndConfirm(
        signer,
        this._connection,
        new Uint8Array(serialized),
      );

      this.pushEvent("withdrawal_submitted", { signature });
    } catch (err) {
      console.error("[Web3AuthWithdraw] token sign error:", err);
      let msg = err?.message || "Transaction failed";

      if (msg.includes("User rejected") || msg.includes("user rejected")) {
        msg = "Transaction cancelled";
      } else if (msg.toLowerCase().includes("insufficient")) {
        msg = "Insufficient balance";
      } else if (msg.toLowerCase().includes("blockhash")) {
        msg = "Blockhash expired — please try again";
      }

      this.pushEvent("withdrawal_error", { error: msg });
    }
  },
};
