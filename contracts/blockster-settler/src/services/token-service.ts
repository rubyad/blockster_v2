import { PublicKey, TransactionInstruction } from "@solana/web3.js";
import {
  getOrCreateAssociatedTokenAccount,
  mintTo,
  getAccount,
  createTransferInstruction,
  TOKEN_PROGRAM_ID,
  ASSOCIATED_TOKEN_PROGRAM_ID,
  getAssociatedTokenAddress,
} from "@solana/spl-token";
import {
  connection,
  MINT_AUTHORITY,
  BUX_MINT_ADDRESS,
  BUX_DECIMALS,
} from "../config";

/**
 * Mint BUX tokens to a wallet.
 * Returns { signature, ataCreated } — ataCreated is true if a new ATA was created.
 */
export async function mintBux(
  walletAddress: string,
  amount: number
): Promise<{ signature: string; ataCreated: boolean }> {
  const recipient = new PublicKey(walletAddress);
  const rawAmount = BigInt(Math.floor(amount * 10 ** BUX_DECIMALS));

  // Check if ATA already exists before getOrCreate
  const expectedAta = await getAssociatedTokenAddress(BUX_MINT_ADDRESS, recipient);
  let ataExistedBefore = false;
  try {
    await getAccount(connection, expectedAta);
    ataExistedBefore = true;
  } catch {
    // ATA does not exist yet — will be created
  }

  // Get or create ATA
  const ata = await getOrCreateAssociatedTokenAccount(
    connection,
    MINT_AUTHORITY,
    BUX_MINT_ADDRESS,
    recipient
  );

  // Mint
  const sig = await mintTo(
    connection,
    MINT_AUTHORITY,
    BUX_MINT_ADDRESS,
    ata.address,
    MINT_AUTHORITY,
    rawAmount
  );

  return { signature: sig, ataCreated: !ataExistedBefore };
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
