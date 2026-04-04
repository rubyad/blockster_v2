import { PublicKey } from "@solana/web3.js";
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
 * Confirm a transaction signature.
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
