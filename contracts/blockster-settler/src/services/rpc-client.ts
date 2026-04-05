import { PublicKey, ComputeBudgetProgram, Transaction, TransactionInstruction, Keypair, type BlockhashWithExpiryBlockHeight } from "@solana/web3.js";
import { connection } from "../config";

/**
 * Get SOL balance in lamports.
 */
export async function getBalanceLamports(wallet: string): Promise<number> {
  return connection.getBalance(new PublicKey(wallet));
}

/**
 * Get recent blockhash with expiry for transaction building + confirmation.
 */
export async function getRecentBlockhash(): Promise<string> {
  const { blockhash } = await connection.getLatestBlockhash("confirmed");
  return blockhash;
}

/**
 * Get blockhash with lastValidBlockHeight (needed for proper confirmation).
 */
export async function getBlockhashWithExpiry(): Promise<BlockhashWithExpiryBlockHeight> {
  return connection.getLatestBlockhash("confirmed");
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
 * Send a signed transaction with retry-friendly options and confirm with blockhash expiry.
 * This replaces the raw sendRawTransaction + confirmTransaction pattern.
 */
/**
 * Send a signed transaction with rebroadcast and blockhash-aware confirmation.
 * If the blockhash expires, rebuilds with a fresh blockhash and retries (up to 3 times).
 *
 * @param buildTx - function that builds and signs a Transaction given a blockhash.
 *                  Called on each retry with a fresh blockhash.
 */
export async function sendAndConfirmTx(
  serializedTx: Buffer | Uint8Array,
  blockhashInfo: BlockhashWithExpiryBlockHeight
): Promise<string> {
  const sig = await connection.sendRawTransaction(serializedTx, {
    skipPreflight: true,
    maxRetries: 5,
  });

  // Resend the tx every 2s while waiting for confirmation.
  // Devnet leaders sometimes drop transactions; rebroadcasting ensures delivery.
  const resendInterval = setInterval(() => {
    connection.sendRawTransaction(serializedTx, { skipPreflight: true }).catch(() => {});
  }, 2000);

  try {
    await connection.confirmTransaction(
      {
        signature: sig,
        blockhash: blockhashInfo.blockhash,
        lastValidBlockHeight: blockhashInfo.lastValidBlockHeight,
      },
      "confirmed"
    );
  } finally {
    clearInterval(resendInterval);
  }

  return sig;
}

/**
 * Build, send, and confirm a settler-signed transaction with automatic retry on blockhash expiry.
 * Use this instead of sendAndConfirmTx for settler-signed txs where we can rebuild.
 *
 * @param buildIxs - function returning the instruction(s) to include
 * @param signer - the settler Keypair
 * @param maxAttempts - number of attempts (default 3)
 */
export async function sendSettlerTx(
  buildIxs: () => TransactionInstruction[],
  signer: { publicKey: PublicKey; secretKey: Uint8Array },
  maxAttempts = 3
): Promise<string> {
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    const bhInfo = await getBlockhashWithExpiry();
    const tx = new Transaction({
      recentBlockhash: bhInfo.blockhash,
      feePayer: signer.publicKey,
    });
    tx.add(...computeBudgetIxs(), ...buildIxs());
    tx.sign(Keypair.fromSecretKey(signer.secretKey));

    const raw = tx.serialize();

    // First send WITH preflight to catch simulation errors early
    let sig: string;
    try {
      sig = await connection.sendRawTransaction(raw, {
        skipPreflight: false,
        preflightCommitment: "confirmed",
        maxRetries: 5,
      });
    } catch (preflightErr: any) {
      console.error(`[sendSettlerTx] Preflight failed (attempt ${attempt}/${maxAttempts}):`, preflightErr.message?.slice(0, 200));
      throw preflightErr;
    }

    console.log(`[sendSettlerTx] Sent tx (attempt ${attempt}/${maxAttempts}): ${sig}`);

    const resendInterval = setInterval(() => {
      connection.sendRawTransaction(raw, { skipPreflight: true }).catch(() => {});
    }, 2000);

    try {
      await connection.confirmTransaction(
        {
          signature: sig,
          blockhash: bhInfo.blockhash,
          lastValidBlockHeight: bhInfo.lastValidBlockHeight,
        },
        "confirmed"
      );
      clearInterval(resendInterval);
      return sig;
    } catch (err: any) {
      clearInterval(resendInterval);
      const msg = err?.message || "";

      // If blockhash expired, check if the tx actually landed before retrying
      if (msg.includes("block height exceeded") || msg.includes("Blockhash not found")) {
        // Give the RPC a moment to index the tx
        await new Promise(r => setTimeout(r, 2000));
        try {
          const status = await connection.getSignatureStatus(sig);
          if (status?.value?.confirmationStatus === "confirmed" || status?.value?.confirmationStatus === "finalized") {
            console.log(`[sendSettlerTx] Tx landed despite timeout: ${sig}`);
            return sig;
          }
          if (status?.value?.err) {
            console.error(`[sendSettlerTx] Tx failed on-chain: ${sig}`, status.value.err);
            throw new Error(`Transaction failed on-chain: ${JSON.stringify(status.value.err)}`);
          }
        } catch (statusErr: any) {
          // getSignatureStatus failed, fall through to retry
          if (statusErr.message?.includes("failed on-chain")) throw statusErr;
        }

        if (attempt < maxAttempts) {
          console.log(`[sendSettlerTx] Blockhash expired, tx not found, retrying (attempt ${attempt + 1}/${maxAttempts})`);
          continue;
        }
      }
      throw err;
    }
  }
  throw new Error("sendSettlerTx: max attempts exceeded");
}

/**
 * Confirm a transaction signature (legacy, for backwards compat).
 */
export async function confirmTransaction(signature: string): Promise<boolean> {
  try {
    const result = await connection.confirmTransaction(signature, "confirmed");
    return !result.value.err;
  } catch {
    return false;
  }
}

/**
 * Get current slot.
 */
export async function getCurrentSlot(): Promise<number> {
  return connection.getSlot("confirmed");
}
