import { PublicKey, ComputeBudgetProgram, Transaction, TransactionInstruction, Keypair } from "@solana/web3.js";
import { connection } from "../config";

/**
 * Get SOL balance in lamports.
 */
export async function getBalanceLamports(wallet: string): Promise<number> {
  return connection.getBalance(new PublicKey(wallet));
}

/**
 * Get recent blockhash for transaction building.
 */
export async function getRecentBlockhash(): Promise<string> {
  const { blockhash } = await connection.getLatestBlockhash("confirmed");
  return blockhash;
}

/**
 * Create compute budget instructions for priority fees.
 * Helps transactions land on devnet (and mainnet) by incentivizing validators.
 */
export function computeBudgetIxs(units = 200_000, microLamports = 50_000) {
  return [
    ComputeBudgetProgram.setComputeUnitLimit({ units }),
    ComputeBudgetProgram.setComputeUnitPrice({ microLamports }),
  ];
}

/**
 * Poll getSignatureStatuses until a transaction reaches "confirmed" or "finalized".
 * This is the Solana equivalent of ethers.js tx.wait() — simple HTTP polling,
 * no websockets, no rebroadcasting. Predictable and reliable.
 *
 * @param signature - Transaction signature to poll for
 * @param timeoutMs - Maximum time to wait (default 60s)
 * @param pollIntervalMs - Time between polls (default 2s)
 */
export async function waitForConfirmation(
  signature: string,
  timeoutMs = 60_000,
  pollIntervalMs = 1_000
): Promise<string> {
  const start = Date.now();

  while (Date.now() - start < timeoutMs) {
    const response = await connection.getSignatureStatuses([signature]);
    const status = response?.value?.[0];

    if (status) {
      if (status.err) {
        throw new Error(`Transaction failed on-chain: ${JSON.stringify(status.err)}`);
      }
      if (status.confirmationStatus === "confirmed" || status.confirmationStatus === "finalized") {
        return signature;
      }
    }

    await new Promise(r => setTimeout(r, pollIntervalMs));
  }

  throw new Error(`Transaction confirmation timed out after ${timeoutMs}ms: ${signature}`);
}

/**
 * Send a signed transaction and wait for confirmation via polling.
 * Use for pre-signed transactions (e.g. user-signed txs forwarded by settler).
 */
export async function sendAndConfirmTx(
  serializedTx: Buffer | Uint8Array
): Promise<string> {
  const sig = await connection.sendRawTransaction(serializedTx, {
    skipPreflight: true,
    maxRetries: 5,
  });

  return waitForConfirmation(sig);
}

/**
 * Build, send, and confirm a settler-signed transaction.
 * Simple pattern: build tx → sign → send with preflight → poll for confirmation.
 * No websockets, no rebroadcast loops. maxRetries on sendRawTransaction handles delivery.
 *
 * @param buildIxs - function returning the instruction(s) to include
 * @param signer - the settler Keypair
 */
export async function sendSettlerTx(
  buildIxs: () => TransactionInstruction[],
  signer: { publicKey: PublicKey; secretKey: Uint8Array }
): Promise<string> {
  const { blockhash } = await connection.getLatestBlockhash("confirmed");
  const tx = new Transaction({
    recentBlockhash: blockhash,
    feePayer: signer.publicKey,
  });
  tx.add(...computeBudgetIxs(), ...buildIxs());
  tx.sign(Keypair.fromSecretKey(signer.secretKey));

  const sig = await connection.sendRawTransaction(tx.serialize(), {
    skipPreflight: false,
    preflightCommitment: "confirmed",
    maxRetries: 5,
  });

  console.log(`[sendSettlerTx] Sent tx: ${sig}`);
  return waitForConfirmation(sig);
}

/**
 * Get current slot.
 */
export async function getCurrentSlot(): Promise<number> {
  return connection.getSlot("confirmed");
}
