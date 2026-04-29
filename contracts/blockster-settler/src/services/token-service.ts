import { PublicKey, TransactionInstruction } from "@solana/web3.js";
import {
  getAccount,
  createTransferInstruction,
  createAssociatedTokenAccountIdempotentInstruction,
  createMintToInstruction,
  TOKEN_PROGRAM_ID,
  getAssociatedTokenAddress,
} from "@solana/spl-token";
import {
  connection,
  MINT_AUTHORITY,
  BUX_MINT_ADDRESS,
  BUX_DECIMALS,
} from "../config";
import { sendSettlerTx } from "./rpc-client";

/**
 * Mint BUX tokens to a wallet.
 *
 * Combines ATA-create (idempotent) + MintTo into a SINGLE atomic transaction.
 * This eliminates the cross-tx race that produced `InvalidAccountData` errors
 * under concurrent mints: previously the @solana/spl-token helpers submitted
 * the ATA-create as one tx and waited for confirmation, then submitted MintTo
 * as a second tx — but RPC replicas don't always have the new ATA visible to
 * the MintTo preflight simulation. Atomic = no race.
 *
 * Returns { signature, ataCreated } — ataCreated is true if the ATA didn't
 * exist before this call.
 */
export async function mintBux(
  walletAddress: string,
  amount: number
): Promise<{ signature: string; ataCreated: boolean }> {
  const recipient = new PublicKey(walletAddress);
  const rawAmount = BigInt(Math.floor(amount * 10 ** BUX_DECIMALS));

  const ata = await getAssociatedTokenAddress(BUX_MINT_ADDRESS, recipient);

  let ataExistedBefore = false;
  try {
    await getAccount(connection, ata);
    ataExistedBefore = true;
  } catch {
    // ATA does not exist — will be created in the same tx as the mint
  }

  const signature = await sendSettlerTx(
    () => [
      createAssociatedTokenAccountIdempotentInstruction(
        MINT_AUTHORITY.publicKey, // payer
        ata,
        recipient,
        BUX_MINT_ADDRESS
      ),
      createMintToInstruction(
        BUX_MINT_ADDRESS,
        ata,
        MINT_AUTHORITY.publicKey, // mint authority
        rawAmount
      ),
    ],
    MINT_AUTHORITY
  );

  return { signature, ataCreated: !ataExistedBefore };
}

/**
 * Get BUX balance for a wallet.
 */
export async function getBuxBalance(walletAddress: string): Promise<number> {
  try {
    const wallet = new PublicKey(walletAddress);
    const ata = await getAssociatedTokenAddress(BUX_MINT_ADDRESS, wallet);
    const account = await getAccount(connection, ata);
    return Number(account.amount) / 10 ** BUX_DECIMALS;
  } catch {
    return 0; // ATA doesn't exist = 0 balance
  }
}

/**
 * Get SOL balance for a wallet (in SOL, not lamports).
 */
export async function getSolBalance(walletAddress: string): Promise<number> {
  const wallet = new PublicKey(walletAddress);
  const lamports = await connection.getBalance(wallet);
  return lamports / 1e9;
}

/**
 * Build an unsigned transfer instruction (BUX from user to treasury).
 * User must sign this transaction client-side.
 */
export async function buildBuxTransferInstruction(
  fromWallet: string,
  toWallet: string,
  amount: number
): Promise<TransactionInstruction> {
  const from = new PublicKey(fromWallet);
  const to = new PublicKey(toWallet);
  const rawAmount = BigInt(Math.floor(amount * 10 ** BUX_DECIMALS));

  const fromAta = await getAssociatedTokenAddress(BUX_MINT_ADDRESS, from);
  const toAta = await getAssociatedTokenAddress(BUX_MINT_ADDRESS, to);

  return createTransferInstruction(
    fromAta,
    toAta,
    from,
    rawAmount,
    [],
    TOKEN_PROGRAM_ID
  );
}
