import {
  Keypair,
  PublicKey,
  SystemProgram,
  Transaction,
  TransactionInstruction,
  LAMPORTS_PER_SOL,
} from "@solana/web3.js";
import { hkdfSync, createHash } from "crypto";
import {
  connection,
  PAYMENT_INTENT_SEED,
  SOL_TREASURY_ADDRESS,
  SWEEP_FEE_PAYER,
} from "../config";

/**
 * Deterministically derives an Ed25519 keypair for a given order ID.
 * Using HKDF-SHA256 with the server-side master seed + the order_id as
 * context means we never need to store secret keys — derive on demand,
 * sign, forget.
 */
export function derivePaymentIntentKeypair(orderId: string): Keypair {
  // HKDF(IKM = PAYMENT_INTENT_SEED, salt = "blockster-shop-intent",
  //      info = order_id, length = 32)
  const seedBuf = hkdfSync(
    "sha256",
    Buffer.from(PAYMENT_INTENT_SEED, "utf8"),
    Buffer.from("blockster-shop-intent", "utf8"),
    Buffer.from(orderId, "utf8"),
    32,
  );
  return Keypair.fromSeed(new Uint8Array(seedBuf));
}

/**
 * Returns current balance on a payment intent pubkey plus whether it has
 * reached the buyer's expected amount. Uses `getBalance` for the balance and
 * `getSignaturesForAddress` for the most recent inbound tx (so we can record
 * which signature funded the intent).
 */
export async function getPaymentIntentStatus(
  pubkey: PublicKey,
  expectedLamports: number,
): Promise<{
  balance_lamports: number;
  funded: boolean;
  funded_tx_sig: string | null;
}> {
  const balance = await connection.getBalance(pubkey, "confirmed");
  const funded = balance >= expectedLamports;
  let fundedTxSig: string | null = null;

  if (funded) {
    try {
      const sigs = await connection.getSignaturesForAddress(pubkey, { limit: 1 });
      if (sigs[0]) fundedTxSig = sigs[0].signature;
    } catch (_) {
      // Signature lookup is best-effort; lack of sig is not fatal
    }
  }

  return { balance_lamports: balance, funded, funded_tx_sig: fundedTxSig };
}

/**
 * Sweeps the entire balance of a payment intent pubkey to the configured
 * treasury. The ephemeral keypair signs; a separate fee payer pays rent so
 * the treasury receives the full funded amount minus a tiny bit of rent
 * reserve (sufficient to zero out the account cleanly).
 *
 * Returns the sweep tx signature.
 */
export async function sweepPaymentIntent(orderId: string): Promise<string> {
  const kp = derivePaymentIntentKeypair(orderId);
  const balance = await connection.getBalance(kp.publicKey, "confirmed");

  if (balance === 0) {
    throw new Error("Cannot sweep empty intent");
  }

  // Transfer balance − minimum rent; 890880 lamports (0.00089 SOL) is the
  // Solana rent minimum to keep an account alive, but since the ephemeral
  // account has no data it should just be closed. We transfer the full
  // balance and let the system program close the account.
  const transferIx: TransactionInstruction = SystemProgram.transfer({
    fromPubkey: kp.publicKey,
    toPubkey: SOL_TREASURY_ADDRESS,
    lamports: balance,
  });

  const tx = new Transaction().add(transferIx);
  const blockhash = await connection.getLatestBlockhash("confirmed");
  tx.recentBlockhash = blockhash.blockhash;
  tx.feePayer = SWEEP_FEE_PAYER.publicKey;

  // The intent keypair signs as sender; the fee payer signs for fees.
  tx.partialSign(kp);
  tx.partialSign(SWEEP_FEE_PAYER);

  const sig = await connection.sendRawTransaction(tx.serialize(), {
    skipPreflight: false,
    maxRetries: 3,
  });

  // Confirm via getSignatureStatuses polling (per project rules — no
  // confirmTransaction websocket).
  await pollConfirmation(sig);

  return sig;
}

async function pollConfirmation(sig: string, timeoutMs = 60_000): Promise<void> {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    const resp = await connection.getSignatureStatuses([sig]);
    const status = resp.value[0];
    if (status?.confirmationStatus === "confirmed" || status?.confirmationStatus === "finalized") {
      if (status.err) throw new Error(`Sweep failed: ${JSON.stringify(status.err)}`);
      return;
    }
    await new Promise((r) => setTimeout(r, 2_000));
  }
  throw new Error("Sweep confirmation timed out");
}

/**
 * Returns just the pubkey for an order ID (no tx submitted). Used by the
 * Elixir side when an order is created — it needs somewhere to tell the
 * buyer to send SOL.
 */
export function getPaymentIntentPubkey(orderId: string): string {
  return derivePaymentIntentKeypair(orderId).publicKey.toBase58();
}

/** Pubkey of the treasury that will receive swept funds (for display/ops). */
export function getTreasuryAddress(): string {
  return SOL_TREASURY_ADDRESS.toBase58();
}

/** SOL in human units for any lamports value. */
export function lamportsToSol(lamports: number): number {
  return lamports / LAMPORTS_PER_SOL;
}
