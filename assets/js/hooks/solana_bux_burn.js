/**
 * SolanaBuxBurn — burns BUX from the buyer's ATA to apply a shop discount.
 *
 * Flow:
 *   1. Checkout LiveView pushes `initiate_bux_payment_client` with { amount, order_id }
 *      after deducting from Mnesia + flipping order to `bux_pending`.
 *   2. Hook builds an SPL BurnChecked instruction (hand-rolled — no spl-token
 *      dep), asks `window.__signer` to sign + submit via the shared
 *      `signAndConfirm` helper (polls `getSignatureStatuses` per CLAUDE.md,
 *      never `confirmTransaction`).
 *   3. Hook pushes `bux_burn_confirmed { sig }` on success — server updates
 *      order to `bux_paid` + sets `bux_burn_tx_hash`. On failure, pushes
 *      `bux_payment_error { error }` — server refunds Mnesia + flips order
 *      back to `pending`.
 *
 * Replaces the EVM-era `BuxPaymentHook` (deprecated stub at
 * hooks/bux_payment.js). Works for both Wallet Standard and Web3Auth signers
 * because `signAndConfirm` handles the sign-and-own-submit dance uniformly.
 */

import {
  Connection,
  PublicKey,
  Transaction,
  TransactionInstruction,
} from "@solana/web3.js"
import { getSigner, signAndConfirm } from "./signer.js"

const RPC_URL =
  window.__SOLANA_RPC_URL ||
  "https://summer-sleek-shape.solana-devnet.quiknode.pro/92b7f51caa76f2981879528aee40a3e8e58cac60/"

// SPL Token program + Associated Token Account program. Constants —
// identical across all networks.
const TOKEN_PROGRAM_ID = new PublicKey(
  "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA",
)
const ASSOCIATED_TOKEN_PROGRAM_ID = new PublicKey(
  "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL",
)

const BUX_DECIMALS = 9

// Derive a user's Associated Token Account for a given mint. PDA of
// [owner, token_program, mint] under the ATA program. Matches what
// `getAssociatedTokenAddress` from @solana/spl-token computes.
function deriveAta(owner, mint) {
  const [ata] = PublicKey.findProgramAddressSync(
    [owner.toBuffer(), TOKEN_PROGRAM_ID.toBuffer(), mint.toBuffer()],
    ASSOCIATED_TOKEN_PROGRAM_ID,
  )
  return ata
}

// Hand-roll a BurnChecked instruction. Layout (10 bytes):
//   [0]   discriminator = 15 (BurnChecked)
//   [1-8] amount as u64 little-endian
//   [9]   decimals as u8
// Accounts (per SPL Token spec):
//   [0] writable source_ata
//   [1] writable mint
//   [2] signer  owner
function buildBurnCheckedIx({ ata, mint, owner, amountRaw, decimals }) {
  const data = new Uint8Array(10)
  data[0] = 15
  const view = new DataView(data.buffer)
  // BigInt → two u32 writes (DataView has setBigUint64 but not on all
  // runtimes; explicit low/high is safest).
  const lo = Number(amountRaw & 0xffffffffn)
  const hi = Number((amountRaw >> 32n) & 0xffffffffn)
  view.setUint32(1, lo, true)
  view.setUint32(5, hi, true)
  data[9] = decimals

  return new TransactionInstruction({
    programId: TOKEN_PROGRAM_ID,
    keys: [
      { pubkey: ata, isSigner: false, isWritable: true },
      { pubkey: mint, isSigner: false, isWritable: true },
      { pubkey: owner, isSigner: true, isWritable: false },
    ],
    data: data,
  })
}

export const SolanaBuxBurn = {
  mounted() {
    this._connection = new Connection(RPC_URL, "confirmed")
    const mintAddr = this.el.dataset.buxMint
    if (!mintAddr) {
      console.error("[SolanaBuxBurn] missing data-bux-mint")
      return
    }
    this._mint = new PublicKey(mintAddr)
    this._decimals = Number(this.el.dataset.buxDecimals || BUX_DECIMALS)

    this.handleEvent("initiate_bux_payment_client", (payload) =>
      this._burn(payload),
    )
  },

  async _burn({ amount, order_id }) {
    try {
      const signer = getSigner()
      if (!signer) {
        this.pushEvent("bux_payment_error", {
          error: "No Solana wallet connected. Please reconnect.",
        })
        return
      }

      const owner = new PublicKey(signer.pubkey)
      const ata = deriveAta(owner, this._mint)

      // Human-units → raw. Use BigInt throughout; integer amounts up to 2^53
      // would overflow Number before we hit the mint's supply cap, and
      // BigInt is free here since we only read it once.
      const amountRaw = BigInt(amount) * BigInt(10) ** BigInt(this._decimals)

      const { blockhash } = await this._connection.getLatestBlockhash("confirmed")

      const tx = new Transaction({
        feePayer: owner,
        recentBlockhash: blockhash,
      }).add(
        buildBurnCheckedIx({
          ata,
          mint: this._mint,
          owner,
          amountRaw,
          decimals: this._decimals,
        }),
      )

      const serialized = tx.serialize({
        requireAllSignatures: false,
        verifySignatures: false,
      })

      const sig = await signAndConfirm(
        signer,
        this._connection,
        new Uint8Array(serialized),
      )

      this.pushEvent("bux_burn_confirmed", { sig, order_id })
    } catch (err) {
      console.error("[SolanaBuxBurn] error:", err)
      let msg = err?.message || "Burn failed"
      if (/user rejected/i.test(msg)) msg = "Signature cancelled"
      else if (/insufficient/i.test(msg) || /0x1$/.test(msg))
        msg = "Insufficient BUX balance on chain"
      this.pushEvent("bux_payment_error", { error: msg })
    }
  },
}
