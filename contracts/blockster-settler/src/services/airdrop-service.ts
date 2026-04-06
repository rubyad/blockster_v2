/**
 * Airdrop Program Service
 *
 * Reads on-chain state from the Blockster Airdrop Solana program.
 * Handles PDA derivation, account deserialization, and transaction building
 * for airdrop round lifecycle: start, deposit, fund prizes, close, draw, claim.
 */

import {
  PublicKey,
  SystemProgram,
  Transaction,
  TransactionInstruction,
} from "@solana/web3.js";
import {
  TOKEN_PROGRAM_ID,
  ASSOCIATED_TOKEN_PROGRAM_ID,
  getAssociatedTokenAddress,
  createAssociatedTokenAccountInstruction,
  getAccount,
} from "@solana/spl-token";
import {
  connection,
  AIRDROP_PROGRAM_ID,
  BUX_MINT_ADDRESS,
  BUX_DECIMALS,
  MINT_AUTHORITY,
} from "../config";
import { getRecentBlockhash, waitForConfirmation } from "./rpc-client";

// -------------------------------------------------------------------
// PDA Seeds (must match the Anchor program)
// -------------------------------------------------------------------

const AIRDROP_STATE_SEED = Buffer.from("airdrop");
const ROUND_SEED = Buffer.from("round");
const ENTRY_SEED = Buffer.from("entry");
const PRIZE_VAULT_SEED = Buffer.from("prize_vault");

// -------------------------------------------------------------------
// PDA Derivation
// -------------------------------------------------------------------

export function deriveAirdropState(): [PublicKey, number] {
  return PublicKey.findProgramAddressSync(
    [AIRDROP_STATE_SEED],
    AIRDROP_PROGRAM_ID
  );
}

function roundIdToBuffer(roundId: number | bigint): Buffer {
  const buf = Buffer.alloc(8);
  buf.writeBigUInt64LE(BigInt(roundId));
  return buf;
}

export function deriveRound(roundId: number | bigint): [PublicKey, number] {
  return PublicKey.findProgramAddressSync(
    [ROUND_SEED, roundIdToBuffer(roundId)],
    AIRDROP_PROGRAM_ID
  );
}

export function deriveEntry(
  roundId: number | bigint,
  depositor: PublicKey,
  entryIndex: number | bigint
): [PublicKey, number] {
  return PublicKey.findProgramAddressSync(
    [
      ENTRY_SEED,
      roundIdToBuffer(roundId),
      depositor.toBuffer(),
      roundIdToBuffer(entryIndex),
    ],
    AIRDROP_PROGRAM_ID
  );
}

export function derivePrizeVault(
  roundId: number | bigint
): [PublicKey, number] {
  return PublicKey.findProgramAddressSync(
    [PRIZE_VAULT_SEED, roundIdToBuffer(roundId)],
    AIRDROP_PROGRAM_ID
  );
}

// -------------------------------------------------------------------
// Account Layout (manual deserialization)
// -------------------------------------------------------------------

const DISCRIMINATOR_SIZE = 8;

// AirdropState layout:
//   discriminator: 8 bytes
//   authority: Pubkey (32) @ offset 8
//   bux_mint: Pubkey (32) @ offset 40
//   treasury: Pubkey (32) @ offset 72
//   current_round_id: u64 (8) @ offset 104
//   bump: u8 (1) @ offset 112
//   _reserved: [u8; 64] @ offset 113

export interface AirdropStateData {
  authority: string;
  buxMint: string;
  treasury: string;
  currentRoundId: number;
  bump: number;
}

function deserializeAirdropState(data: Buffer): AirdropStateData {
  return {
    authority: new PublicKey(data.subarray(DISCRIMINATOR_SIZE, DISCRIMINATOR_SIZE + 32)).toBase58(),
    buxMint: new PublicKey(data.subarray(DISCRIMINATOR_SIZE + 32, DISCRIMINATOR_SIZE + 64)).toBase58(),
    treasury: new PublicKey(data.subarray(DISCRIMINATOR_SIZE + 64, DISCRIMINATOR_SIZE + 96)).toBase58(),
    currentRoundId: Number(data.readBigUInt64LE(DISCRIMINATOR_SIZE + 96)),
    bump: data.readUInt8(DISCRIMINATOR_SIZE + 104),
  };
}

// AirdropRound layout:
//   discriminator: 8 bytes
//   round_id: u64 (8) @ offset 8
//   commitment_hash: [u8; 32] (32) @ offset 16
//   status: enum (1) @ offset 48
//   end_time: i64 (8) @ offset 49
//   total_entries: u64 (8) @ offset 57
//   deposit_count: u64 (8) @ offset 65
//   prize_mint: Pubkey (32) @ offset 73
//   prize_amount: u64 (8) @ offset 105
//   server_seed: [u8; 32] (32) @ offset 113
//   slot_at_close: u64 (8) @ offset 145
//   winner_count: u8 (1) @ offset 153
//   winners: [WinnerInfo; 33] @ offset 154
//     WinnerInfo = wallet(32) + amount(u64=8) + claimed(bool=1) = 41 bytes each
//     33 * 41 = 1353 bytes
//   drawn_at: i64 (8) @ offset 1507
//   bump: u8 (1) @ offset 1515
//   _reserved: [u8; 64] @ offset 1516

const ROUND_STATUS_MAP: Record<number, string> = {
  0: "open",
  1: "closed",
  2: "drawn",
};

export interface WinnerInfoData {
  wallet: string;
  amount: number;
  claimed: boolean;
}

export interface AirdropRoundData {
  roundId: number;
  commitmentHash: string;
  status: string;
  endTime: number;
  totalEntries: number;
  depositCount: number;
  prizeMint: string;
  prizeAmount: number;
  serverSeed: string;
  slotAtClose: number;
  winnerCount: number;
  winners: WinnerInfoData[];
  drawnAt: number;
  bump: number;
}

function deserializeAirdropRound(data: Buffer): AirdropRoundData {
  const roundId = Number(data.readBigUInt64LE(DISCRIMINATOR_SIZE));
  const commitmentHash = data
    .subarray(DISCRIMINATOR_SIZE + 8, DISCRIMINATOR_SIZE + 40)
    .toString("hex");
  const status = ROUND_STATUS_MAP[data.readUInt8(DISCRIMINATOR_SIZE + 40)] || "unknown";
  const endTime = Number(data.readBigInt64LE(DISCRIMINATOR_SIZE + 41));
  const totalEntries = Number(data.readBigUInt64LE(DISCRIMINATOR_SIZE + 49));
  const depositCount = Number(data.readBigUInt64LE(DISCRIMINATOR_SIZE + 57));
  const prizeMint = new PublicKey(
    data.subarray(DISCRIMINATOR_SIZE + 65, DISCRIMINATOR_SIZE + 97)
  ).toBase58();
  const prizeAmount = Number(data.readBigUInt64LE(DISCRIMINATOR_SIZE + 97));
  const serverSeed = data
    .subarray(DISCRIMINATOR_SIZE + 105, DISCRIMINATOR_SIZE + 137)
    .toString("hex");
  const slotAtClose = Number(data.readBigUInt64LE(DISCRIMINATOR_SIZE + 137));
  const winnerCount = data.readUInt8(DISCRIMINATOR_SIZE + 145);

  // Parse winners array (33 entries, each 41 bytes)
  const winnersOffset = DISCRIMINATOR_SIZE + 146;
  const winners: WinnerInfoData[] = [];
  for (let i = 0; i < winnerCount; i++) {
    const base = winnersOffset + i * 41;
    const wallet = new PublicKey(data.subarray(base, base + 32)).toBase58();
    const amount = Number(data.readBigUInt64LE(base + 32));
    const claimed = data.readUInt8(base + 40) !== 0;
    winners.push({ wallet, amount, claimed });
  }

  const drawnAt = Number(
    data.readBigInt64LE(DISCRIMINATOR_SIZE + 146 + 33 * 41)
  );
  const bump = data.readUInt8(DISCRIMINATOR_SIZE + 146 + 33 * 41 + 8);

  return {
    roundId,
    commitmentHash,
    status,
    endTime,
    totalEntries,
    depositCount,
    prizeMint,
    prizeAmount,
    serverSeed,
    slotAtClose,
    winnerCount,
    winners,
    drawnAt,
    bump,
  };
}

// -------------------------------------------------------------------
// Read On-Chain State
// -------------------------------------------------------------------

export async function getAirdropState(): Promise<AirdropStateData | null> {
  const [statePDA] = deriveAirdropState();
  const acct = await connection.getAccountInfo(statePDA);
  if (!acct?.data) return null;
  return deserializeAirdropState(acct.data);
}

export async function getRoundInfo(
  roundId: number
): Promise<AirdropRoundData | null> {
  const [roundPDA] = deriveRound(roundId);
  const acct = await connection.getAccountInfo(roundPDA);
  if (!acct?.data) return null;
  return deserializeAirdropRound(acct.data);
}

export async function getCurrentRoundId(): Promise<number> {
  const state = await getAirdropState();
  return state?.currentRoundId ?? 0;
}

// -------------------------------------------------------------------
// Anchor Instruction Discriminators
// (from IDL: first 8 bytes)
// -------------------------------------------------------------------

const DISCRIMINATORS = {
  initialize: Buffer.from([175, 175, 109, 31, 13, 152, 155, 237]),
  startRound: Buffer.from([144, 144, 43, 7, 193, 42, 217, 215]),
  depositBux: Buffer.from([73, 179, 247, 139, 203, 107, 36, 142]),
  fundPrizes: Buffer.from([163, 225, 193, 125, 144, 171, 29, 241]),
  closeRound: Buffer.from([149, 14, 81, 88, 230, 226, 234, 37]),
  drawWinners: Buffer.from([43, 87, 86, 4, 32, 104, 203, 209]),
  claimPrize: Buffer.from([157, 233, 139, 121, 246, 62, 234, 235]),
  withdrawUnclaimed: Buffer.from([243, 12, 129, 222, 63, 137, 199, 70]),
};

// -------------------------------------------------------------------
// Authority Transactions (signed by settler)
// -------------------------------------------------------------------

/**
 * Start a new airdrop round.
 * Sends the transaction directly (authority = MINT_AUTHORITY).
 */
export async function startRound(
  commitmentHash: Buffer,
  endTime: number,
  prizeMint: PublicKey
): Promise<string> {
  const authority = MINT_AUTHORITY;
  const [airdropStatePDA] = deriveAirdropState();

  // Read current round ID to derive next round PDA
  const state = await getAirdropState();
  if (!state) throw new Error("Airdrop program not initialized");
  const nextRoundId = state.currentRoundId + 1;
  const [roundPDA] = deriveRound(nextRoundId);

  // Instruction data: discriminator + commitment_hash ([u8;32]) + end_time (i64 LE)
  const data = Buffer.alloc(8 + 32 + 8);
  DISCRIMINATORS.startRound.copy(data, 0);
  commitmentHash.copy(data, 8);
  data.writeBigInt64LE(BigInt(endTime), 40);

  const keys = [
    { pubkey: authority.publicKey, isSigner: true, isWritable: true },
    { pubkey: airdropStatePDA, isSigner: false, isWritable: true },
    { pubkey: prizeMint, isSigner: false, isWritable: false },
    { pubkey: roundPDA, isSigner: false, isWritable: true },
    { pubkey: SystemProgram.programId, isSigner: false, isWritable: false },
  ];

  const ix = new TransactionInstruction({
    keys,
    programId: AIRDROP_PROGRAM_ID,
    data,
  });

  const blockhash = await getRecentBlockhash();
  const tx = new Transaction({ recentBlockhash: blockhash, feePayer: authority.publicKey });
  tx.add(ix);
  tx.sign(authority);

  const sig = await connection.sendRawTransaction(tx.serialize(), { maxRetries: 5 });
  await waitForConfirmation(sig);
  return sig;
}

/**
 * Fund prizes for a round (SOL or SPL).
 * Sends the transaction directly (authority = MINT_AUTHORITY).
 */
export async function fundPrizes(
  roundId: number,
  amount: bigint,
  isSolPrize: boolean
): Promise<string> {
  const authority = MINT_AUTHORITY;
  const [airdropStatePDA] = deriveAirdropState();
  const [roundPDA] = deriveRound(roundId);
  const [prizeVaultPDA] = derivePrizeVault(roundId);

  // Instruction data: discriminator + round_id (u64 LE) + amount (u64 LE)
  const data = Buffer.alloc(8 + 8 + 8);
  DISCRIMINATORS.fundPrizes.copy(data, 0);
  data.writeBigUInt64LE(BigInt(roundId), 8);
  data.writeBigUInt64LE(amount, 16);

  const keys = [
    { pubkey: authority.publicKey, isSigner: true, isWritable: true },
    { pubkey: airdropStatePDA, isSigner: false, isWritable: false },
    { pubkey: roundPDA, isSigner: false, isWritable: true },
    { pubkey: prizeVaultPDA, isSigner: false, isWritable: true },
  ];

  if (isSolPrize) {
    // No optional token accounts for SOL prizes
    keys.push(
      { pubkey: AIRDROP_PROGRAM_ID, isSigner: false, isWritable: false }, // None for authority_token_account
      { pubkey: AIRDROP_PROGRAM_ID, isSigner: false, isWritable: false }  // None for prize_vault_token_account
    );
  } else {
    // SPL prize funding — get round info for prize mint
    const roundInfo = await getRoundInfo(roundId);
    if (!roundInfo) throw new Error(`Round ${roundId} not found`);
    const prizeMint = new PublicKey(roundInfo.prizeMint);

    const authorityTokenAccount = await getAssociatedTokenAddress(prizeMint, authority.publicKey);
    const prizeVaultTokenAccount = await getAssociatedTokenAddress(prizeMint, prizeVaultPDA, true);

    keys.push(
      { pubkey: authorityTokenAccount, isSigner: false, isWritable: true },
      { pubkey: prizeVaultTokenAccount, isSigner: false, isWritable: true }
    );
  }

  keys.push(
    { pubkey: SystemProgram.programId, isSigner: false, isWritable: false },
    { pubkey: TOKEN_PROGRAM_ID, isSigner: false, isWritable: false },
  );

  const ix = new TransactionInstruction({
    keys,
    programId: AIRDROP_PROGRAM_ID,
    data,
  });

  const blockhash = await getRecentBlockhash();
  const tx = new Transaction({ recentBlockhash: blockhash, feePayer: authority.publicKey });
  tx.add(ix);
  tx.sign(authority);

  const sig = await connection.sendRawTransaction(tx.serialize(), { maxRetries: 5 });
  await waitForConfirmation(sig);
  return sig;
}

/**
 * Close a round (captures slot).
 * Sends the transaction directly (authority = MINT_AUTHORITY).
 */
export async function closeRound(roundId: number): Promise<string> {
  const authority = MINT_AUTHORITY;
  const [airdropStatePDA] = deriveAirdropState();
  const [roundPDA] = deriveRound(roundId);

  // Instruction data: discriminator + round_id (u64 LE)
  const data = Buffer.alloc(8 + 8);
  DISCRIMINATORS.closeRound.copy(data, 0);
  data.writeBigUInt64LE(BigInt(roundId), 8);

  const keys = [
    { pubkey: authority.publicKey, isSigner: true, isWritable: false },
    { pubkey: airdropStatePDA, isSigner: false, isWritable: false },
    { pubkey: roundPDA, isSigner: false, isWritable: true },
  ];

  const ix = new TransactionInstruction({
    keys,
    programId: AIRDROP_PROGRAM_ID,
    data,
  });

  const blockhash = await getRecentBlockhash();
  const tx = new Transaction({ recentBlockhash: blockhash, feePayer: authority.publicKey });
  tx.add(ix);
  tx.sign(authority);

  const sig = await connection.sendRawTransaction(tx.serialize(), { maxRetries: 5 });
  await waitForConfirmation(sig);
  return sig;
}

/**
 * Draw winners for a closed round.
 * Sends the transaction directly (authority = MINT_AUTHORITY).
 */
export async function drawWinners(
  roundId: number,
  serverSeed: Buffer,
  winners: { wallet: string; amount: bigint }[]
): Promise<string> {
  const authority = MINT_AUTHORITY;
  const [airdropStatePDA] = deriveAirdropState();
  const [roundPDA] = deriveRound(roundId);

  // Instruction data: discriminator + round_id (u64) + server_seed ([u8;32]) + winners vec
  // Vec<WinnerInfo> is serialized as: length (u32 LE) + entries
  // WinnerInfo = wallet (32) + amount (u64=8) + claimed (bool=1) = 41 bytes
  const winnersLen = winners.length;
  const dataSize = 8 + 8 + 32 + 4 + winnersLen * 41;
  const data = Buffer.alloc(dataSize);

  let offset = 0;
  DISCRIMINATORS.drawWinners.copy(data, offset);
  offset += 8;
  data.writeBigUInt64LE(BigInt(roundId), offset);
  offset += 8;
  serverSeed.copy(data, offset);
  offset += 32;
  data.writeUInt32LE(winnersLen, offset);
  offset += 4;

  for (const w of winners) {
    const walletPubkey = new PublicKey(w.wallet);
    walletPubkey.toBuffer().copy(data, offset);
    offset += 32;
    data.writeBigUInt64LE(w.amount, offset);
    offset += 8;
    data.writeUInt8(0, offset); // claimed = false
    offset += 1;
  }

  const keys = [
    { pubkey: authority.publicKey, isSigner: true, isWritable: false },
    { pubkey: airdropStatePDA, isSigner: false, isWritable: false },
    { pubkey: roundPDA, isSigner: false, isWritable: true },
  ];

  const ix = new TransactionInstruction({
    keys,
    programId: AIRDROP_PROGRAM_ID,
    data,
  });

  const blockhash = await getRecentBlockhash();
  const tx = new Transaction({ recentBlockhash: blockhash, feePayer: authority.publicKey });
  tx.add(ix);
  tx.sign(authority);

  const sig = await connection.sendRawTransaction(tx.serialize(), { maxRetries: 5 });
  await waitForConfirmation(sig);
  return sig;
}

// -------------------------------------------------------------------
// User Transaction Builders (returns unsigned base64 tx for wallet signing)
// -------------------------------------------------------------------

/**
 * Build unsigned deposit BUX transaction.
 * User transfers BUX to treasury and creates an AirdropEntry PDA.
 */
export async function buildDepositBuxTx(
  wallet: string,
  roundId: number,
  entryIndex: number,
  amount: number
): Promise<string> {
  const depositor = new PublicKey(wallet);
  const rawAmount = BigInt(Math.floor(amount * 10 ** BUX_DECIMALS));

  const [airdropStatePDA] = deriveAirdropState();
  const [roundPDA] = deriveRound(roundId);
  const [entryPDA] = deriveEntry(roundId, depositor, entryIndex);

  // Read treasury from airdrop state
  const state = await getAirdropState();
  if (!state) throw new Error("Airdrop program not initialized");
  const treasury = new PublicKey(state.treasury);

  // Depositor's BUX ATA
  const depositorBuxAta = await getAssociatedTokenAddress(BUX_MINT_ADDRESS, depositor);
  // Treasury's BUX ATA
  const treasuryBuxAta = await getAssociatedTokenAddress(BUX_MINT_ADDRESS, treasury);

  // Instruction data: discriminator + round_id (u64) + entry_index (u64) + amount (u64)
  const data = Buffer.alloc(8 + 8 + 8 + 8);
  DISCRIMINATORS.depositBux.copy(data, 0);
  data.writeBigUInt64LE(BigInt(roundId), 8);
  data.writeBigUInt64LE(BigInt(entryIndex), 16);
  data.writeBigUInt64LE(rawAmount, 24);

  const keys = [
    { pubkey: depositor, isSigner: true, isWritable: true },
    { pubkey: airdropStatePDA, isSigner: false, isWritable: false },
    { pubkey: roundPDA, isSigner: false, isWritable: true },
    { pubkey: entryPDA, isSigner: false, isWritable: true },
    { pubkey: depositorBuxAta, isSigner: false, isWritable: true },
    { pubkey: treasuryBuxAta, isSigner: false, isWritable: true },
    { pubkey: SystemProgram.programId, isSigner: false, isWritable: false },
    { pubkey: TOKEN_PROGRAM_ID, isSigner: false, isWritable: false },
  ];

  const ix = new TransactionInstruction({
    keys,
    programId: AIRDROP_PROGRAM_ID,
    data,
  });

  const blockhash = await getRecentBlockhash();
  const tx = new Transaction({ recentBlockhash: blockhash, feePayer: depositor });
  tx.add(ix);

  return tx
    .serialize({ requireAllSignatures: false, verifySignatures: false })
    .toString("base64");
}

/**
 * Build unsigned claim prize transaction.
 * Winner claims prize from prize vault (SOL or SPL).
 */
export async function buildClaimPrizeTx(
  wallet: string,
  roundId: number,
  winnerIndex: number
): Promise<string> {
  const winner = new PublicKey(wallet);

  const [airdropStatePDA] = deriveAirdropState();
  const [roundPDA] = deriveRound(roundId);
  const [prizeVaultPDA] = derivePrizeVault(roundId);

  // Read round to determine prize type
  const roundInfo = await getRoundInfo(roundId);
  if (!roundInfo) throw new Error(`Round ${roundId} not found`);

  const isSolPrize =
    roundInfo.prizeMint === SystemProgram.programId.toBase58() ||
    roundInfo.prizeMint === "11111111111111111111111111111111";

  // Instruction data: discriminator + round_id (u64) + winner_index (u8)
  const data = Buffer.alloc(8 + 8 + 1);
  DISCRIMINATORS.claimPrize.copy(data, 0);
  data.writeBigUInt64LE(BigInt(roundId), 8);
  data.writeUInt8(winnerIndex, 16);

  const keys = [
    { pubkey: winner, isSigner: true, isWritable: true },
    { pubkey: airdropStatePDA, isSigner: false, isWritable: false },
    { pubkey: roundPDA, isSigner: false, isWritable: true },
    { pubkey: prizeVaultPDA, isSigner: false, isWritable: true },
  ];

  const ataIxs: TransactionInstruction[] = [];

  if (isSolPrize) {
    // No token accounts needed for SOL prize
    keys.push(
      { pubkey: AIRDROP_PROGRAM_ID, isSigner: false, isWritable: false }, // None for prize_vault_token_account
      { pubkey: AIRDROP_PROGRAM_ID, isSigner: false, isWritable: false }  // None for winner_token_account
    );
  } else {
    const prizeMint = new PublicKey(roundInfo.prizeMint);
    const prizeVaultTokenAccount = await getAssociatedTokenAddress(prizeMint, prizeVaultPDA, true);
    const winnerTokenAccount = await getAssociatedTokenAddress(prizeMint, winner);

    keys.push(
      { pubkey: prizeVaultTokenAccount, isSigner: false, isWritable: true },
      { pubkey: winnerTokenAccount, isSigner: false, isWritable: true }
    );

    // Ensure winner's ATA exists
    try {
      await getAccount(connection, winnerTokenAccount);
    } catch {
      ataIxs.push(
        createAssociatedTokenAccountInstruction(winner, winnerTokenAccount, winner, prizeMint)
      );
    }
  }

  keys.push(
    { pubkey: SystemProgram.programId, isSigner: false, isWritable: false },
    { pubkey: TOKEN_PROGRAM_ID, isSigner: false, isWritable: false },
  );

  const ix = new TransactionInstruction({
    keys,
    programId: AIRDROP_PROGRAM_ID,
    data,
  });

  const blockhash = await getRecentBlockhash();
  const tx = new Transaction({ recentBlockhash: blockhash, feePayer: winner });
  tx.add(...ataIxs, ix);

  return tx
    .serialize({ requireAllSignatures: false, verifySignatures: false })
    .toString("base64");
}
