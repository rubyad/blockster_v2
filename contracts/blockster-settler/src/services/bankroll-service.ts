/**
 * Bankroll Program Service
 *
 * Reads on-chain state from the Blockster Bankroll Solana program.
 * Handles PDA derivation, account deserialization, and transaction building
 * for LP deposits, withdrawals, and bet placement.
 */

import {
  PublicKey,
  SystemProgram,
  Transaction,
  TransactionInstruction,
  LAMPORTS_PER_SOL,
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
  BANKROLL_PROGRAM_ID,
  BUX_MINT_ADDRESS,
  BUX_DECIMALS,
  MINT_AUTHORITY,
} from "../config";
import { getRecentBlockhash, getBlockhashWithExpiry, sendAndConfirmTx, sendSettlerTx, computeBudgetIxs } from "./rpc-client";

const SYSVAR_RENT = new PublicKey(
  "SysvarRent111111111111111111111111111111111"
);

// -------------------------------------------------------------------
// PDA Seeds (must match the Anchor program)
// -------------------------------------------------------------------

const GAME_REGISTRY_SEED = Buffer.from("game_registry");
const SOL_VAULT_SEED = Buffer.from("sol_vault");
const SOL_VAULT_STATE_SEED = Buffer.from("sol_vault_state");
const BUX_VAULT_STATE_SEED = Buffer.from("bux_vault_state");
const BSOL_MINT_SEED = Buffer.from("bsol_mint");
const BSOL_MINT_AUTHORITY_SEED = Buffer.from("bsol_mint_authority");
const BBUX_MINT_SEED = Buffer.from("bbux_mint");
const BBUX_MINT_AUTHORITY_SEED = Buffer.from("bbux_mint_authority");
const BUX_VAULT_TOKEN_SEED = Buffer.from("bux_token_account");
const PLAYER_STATE_SEED = Buffer.from("player");
const BET_ORDER_SEED = Buffer.from("bet");

// -------------------------------------------------------------------
// PDA Derivation
// -------------------------------------------------------------------

export function deriveGameRegistry(): [PublicKey, number] {
  return PublicKey.findProgramAddressSync(
    [GAME_REGISTRY_SEED],
    BANKROLL_PROGRAM_ID
  );
}

export function deriveSolVault(): [PublicKey, number] {
  return PublicKey.findProgramAddressSync(
    [SOL_VAULT_SEED],
    BANKROLL_PROGRAM_ID
  );
}

export function deriveSolVaultState(): [PublicKey, number] {
  return PublicKey.findProgramAddressSync(
    [SOL_VAULT_STATE_SEED],
    BANKROLL_PROGRAM_ID
  );
}

export function deriveBuxVaultState(): [PublicKey, number] {
  return PublicKey.findProgramAddressSync(
    [BUX_VAULT_STATE_SEED],
    BANKROLL_PROGRAM_ID
  );
}

export function deriveBsolMint(): [PublicKey, number] {
  return PublicKey.findProgramAddressSync(
    [BSOL_MINT_SEED],
    BANKROLL_PROGRAM_ID
  );
}

export function deriveBsolMintAuthority(): [PublicKey, number] {
  return PublicKey.findProgramAddressSync(
    [BSOL_MINT_AUTHORITY_SEED],
    BANKROLL_PROGRAM_ID
  );
}

export function deriveBbuxMint(): [PublicKey, number] {
  return PublicKey.findProgramAddressSync(
    [BBUX_MINT_SEED],
    BANKROLL_PROGRAM_ID
  );
}

export function deriveBbuxMintAuthority(): [PublicKey, number] {
  return PublicKey.findProgramAddressSync(
    [BBUX_MINT_AUTHORITY_SEED],
    BANKROLL_PROGRAM_ID
  );
}

export function deriveBuxVaultToken(): [PublicKey, number] {
  return PublicKey.findProgramAddressSync(
    [BUX_VAULT_TOKEN_SEED],
    BANKROLL_PROGRAM_ID
  );
}

export function derivePlayerState(player: PublicKey): [PublicKey, number] {
  return PublicKey.findProgramAddressSync(
    [PLAYER_STATE_SEED, player.toBuffer()],
    BANKROLL_PROGRAM_ID
  );
}

export function deriveBetOrder(
  player: PublicKey,
  nonce: bigint
): [PublicKey, number] {
  const nonceBuf = Buffer.alloc(8);
  nonceBuf.writeBigUInt64LE(nonce);
  return PublicKey.findProgramAddressSync(
    [BET_ORDER_SEED, player.toBuffer(), nonceBuf],
    BANKROLL_PROGRAM_ID
  );
}

// -------------------------------------------------------------------
// Account Layout Offsets (manual deserialization)
// -------------------------------------------------------------------

// Anchor discriminator = 8 bytes at offset 0
const DISCRIMINATOR_SIZE = 8;

// SolVaultState / BuxVaultState layout (from Rust struct):
//   discriminator:      8 bytes  @ offset 0
//   total_deposited:    u64      @ offset 8
//   total_withdrawn:    u64      @ offset 16
//   total_liability:    u64      @ offset 24
//   unsettled_count:    u64      @ offset 32
//   unsettled_bets:     u64      @ offset 40
//   house_profit:       i64      @ offset 48
//   total_bets:         u64      @ offset 56
//   total_volume:       u64      @ offset 64
//   total_payout:       u64      @ offset 72
//   largest_bet:        u64      @ offset 80
//   largest_payout:     u64      @ offset 88
//   lp_deposits_count:  u64      @ offset 96
//   lp_withdrawals_count: u64    @ offset 104
//   total_referral_paid: u64     @ offset 112
//   _reserved:          128 bytes @ offset 120
//
// NOTE: lp_supply is NOT in VaultState — it's tracked by the bSOL/bBUX SPL mint account.
// totalBalance = total_deposited - total_withdrawn (accounting, not direct vault read).

interface VaultStats {
  totalDeposited: number;
  totalWithdrawn: number;
  totalBalance: number;
  totalLiability: number;
  unsettledCount: number;
  unsettledBets: number;
  houseProfit: number;
  totalBets: number;
  totalVolume: number;
  totalPayout: number;
  largestBet: number;
  largestPayout: number;
  lpDepositsCount: number;
  lpWithdrawalsCount: number;
  totalReferralPaid: number;
}

function deserializeVaultState(data: Buffer, decimals: number): VaultStats {
  const divisor = 10 ** decimals;
  const totalDeposited = Number(data.readBigUInt64LE(DISCRIMINATOR_SIZE)) / divisor;
  const totalWithdrawn = Number(data.readBigUInt64LE(DISCRIMINATOR_SIZE + 8)) / divisor;
  const totalLiability = Number(data.readBigUInt64LE(DISCRIMINATOR_SIZE + 16)) / divisor;
  const unsettledCount = Number(data.readBigUInt64LE(DISCRIMINATOR_SIZE + 24));
  const unsettledBets = Number(data.readBigUInt64LE(DISCRIMINATOR_SIZE + 32)) / divisor;
  const houseProfit = Number(data.readBigInt64LE(DISCRIMINATOR_SIZE + 40)) / divisor;
  const totalBets = Number(data.readBigUInt64LE(DISCRIMINATOR_SIZE + 48));
  const totalVolume = Number(data.readBigUInt64LE(DISCRIMINATOR_SIZE + 56)) / divisor;
  const totalPayout = Number(data.readBigUInt64LE(DISCRIMINATOR_SIZE + 64)) / divisor;
  const largestBet = Number(data.readBigUInt64LE(DISCRIMINATOR_SIZE + 72)) / divisor;
  const largestPayout = Number(data.readBigUInt64LE(DISCRIMINATOR_SIZE + 80)) / divisor;
  const lpDepositsCount = Number(data.readBigUInt64LE(DISCRIMINATOR_SIZE + 88));
  const lpWithdrawalsCount = Number(data.readBigUInt64LE(DISCRIMINATOR_SIZE + 96));
  const totalReferralPaid = Number(data.readBigUInt64LE(DISCRIMINATOR_SIZE + 104)) / divisor;

  return {
    totalDeposited,
    totalWithdrawn,
    totalBalance: totalDeposited - totalWithdrawn,
    totalLiability,
    unsettledCount,
    unsettledBets,
    houseProfit,
    totalBets,
    totalVolume,
    totalPayout,
    largestBet,
    largestPayout,
    lpDepositsCount,
    lpWithdrawalsCount,
    totalReferralPaid,
  };
}

// -------------------------------------------------------------------
// Read On-Chain State
// -------------------------------------------------------------------

export interface VaultPoolStats {
  totalBalance: number;
  liability: number;
  netBalance: number;
  lpSupply: number;
  lpPrice: number;
  unsettledBets: number;
  houseProfit: number;
  totalBets: number;
  totalVolume: number;
  totalPayout: number;
}

export interface PoolStats {
  sol: VaultPoolStats;
  bux: VaultPoolStats;
}

export async function getPoolStats(): Promise<PoolStats> {
  const [solVaultStatePDA] = deriveSolVaultState();
  const [buxVaultStatePDA] = deriveBuxVaultState();
  const [bsolMint] = deriveBsolMint();
  const [bbuxMint] = deriveBbuxMint();

  const [solVaultPDA] = deriveSolVault();
  const [buxTokenPDA] = deriveBuxVaultToken();

  // Fetch vault state accounts, LP mint accounts, AND actual vault balances in parallel
  const [solAcct, buxAcct, bsolMintAcct, bbuxMintAcct, solVaultAcct, buxTokenAcct] = await Promise.all([
    connection.getAccountInfo(solVaultStatePDA),
    connection.getAccountInfo(buxVaultStatePDA),
    connection.getAccountInfo(bsolMint),
    connection.getAccountInfo(bbuxMint),
    connection.getAccountInfo(solVaultPDA),
    connection.getAccountInfo(buxTokenPDA),
  ]);

  const defaultVault: VaultPoolStats = {
    totalBalance: 0,
    liability: 0,
    netBalance: 0,
    lpSupply: 0,
    lpPrice: 1.0,
    unsettledBets: 0,
    houseProfit: 0,
    totalBets: 0,
    totalVolume: 0,
    totalPayout: 0,
  };

  let solStats = { ...defaultVault };
  let buxStats = { ...defaultVault };

  // Read bSOL LP supply from mint account (SPL Token mint layout: supply is u64 LE at offset 36)
  const bsolSupply = bsolMintAcct?.data
    ? Number(bsolMintAcct.data.readBigUInt64LE(36)) / LAMPORTS_PER_SOL
    : 0;

  const bbuxSupply = bbuxMintAcct?.data
    ? Number(bbuxMintAcct.data.readBigUInt64LE(36)) / (10 ** BUX_DECIMALS)
    : 0;

  if (solAcct?.data) {
    const v = deserializeVaultState(solAcct.data, 9);
    // Use actual SOL vault lamport balance for LP price (includes house profit from bets)
    const rent = 890880; // rent-exempt minimum for 0-data account
    const actualBalance = solVaultAcct
      ? (solVaultAcct.lamports - rent) / LAMPORTS_PER_SOL
      : v.totalBalance;
    const effectiveBalance = actualBalance - v.unsettledBets;
    solStats = {
      totalBalance: actualBalance,
      liability: v.totalLiability,
      netBalance: actualBalance - v.totalLiability,
      lpSupply: bsolSupply,
      lpPrice: bsolSupply > 0 ? effectiveBalance / bsolSupply : 1.0,
      unsettledBets: v.unsettledBets,
      houseProfit: v.houseProfit,
      totalBets: v.totalBets,
      totalVolume: v.totalVolume,
      totalPayout: v.totalPayout,
    };
  }

  if (buxAcct?.data) {
    const v = deserializeVaultState(buxAcct.data, BUX_DECIMALS);
    // Use actual BUX token account balance for LP price (includes house profit from bets)
    // SPL Token account: amount is u64 LE at offset 64
    const actualBalance = buxTokenAcct?.data
      ? Number(buxTokenAcct.data.readBigUInt64LE(64)) / (10 ** BUX_DECIMALS)
      : v.totalBalance;
    const effectiveBalance = actualBalance - v.unsettledBets;
    buxStats = {
      totalBalance: actualBalance,
      liability: v.totalLiability,
      netBalance: actualBalance - v.totalLiability,
      lpSupply: bbuxSupply,
      lpPrice: bbuxSupply > 0 ? effectiveBalance / bbuxSupply : 1.0,
      unsettledBets: v.unsettledBets,
      houseProfit: v.houseProfit,
      totalBets: v.totalBets,
      totalVolume: v.totalVolume,
      totalPayout: v.totalPayout,
    };
  }

  return { sol: solStats, bux: buxStats };
}

export interface GameConfig {
  gameId: number;
  minBet: number;
  maxBetBps: number;
  feeBps: number;
  active: boolean;
  houseBalanceSol: number;
  houseBalanceBux: number;
  maxBetSol: number;
  maxBetBux: number;
}

export async function getGameConfig(gameId: number): Promise<GameConfig> {
  // Fetch pool stats to calculate house balances and max bets
  const stats = await getPoolStats();

  // GameRegistry stores game entries — for now use stats-based calculation
  // Max bet = 0.1% of total balance, adjusted by game's maxBetBps
  const maxBetBps = 1000; // 10% default — overridden by on-chain game entry when deployed
  const houseBalanceSol = stats.sol.netBalance;
  const houseBalanceBux = stats.bux.netBalance;

  return {
    gameId,
    minBet: 0,
    maxBetBps,
    feeBps: 200, // 2% default
    active: true,
    houseBalanceSol,
    houseBalanceBux,
    maxBetSol: houseBalanceSol * (maxBetBps / 10000),
    maxBetBux: houseBalanceBux * (maxBetBps / 10000),
  };
}

// -------------------------------------------------------------------
// Transaction Builders
// -------------------------------------------------------------------

// Anchor instruction discriminators — must match target/idl/blockster_bankroll.json
const DISCRIMINATORS = {
  depositSol: Buffer.from([108, 81, 78, 117, 125, 155, 56, 200]),
  withdrawSol: Buffer.from([145, 131, 74, 136, 65, 137, 42, 38]),
  depositBux: Buffer.from([73, 179, 247, 139, 203, 107, 36, 142]),
  withdrawBux: Buffer.from([76, 16, 106, 233, 233, 104, 165, 46]),
  placeBetSol: Buffer.from([137, 137, 247, 253, 233, 243, 48, 170]),
  placeBetBux: Buffer.from([90, 51, 110, 237, 175, 213, 18, 137]),
  submitCommitment: Buffer.from([48, 171, 16, 125, 219, 133, 58, 87]),
  settleBet: Buffer.from([115, 55, 234, 177, 227, 4, 10, 67]),
  reclaimExpired: Buffer.from([0x7d, 0xb9, 0x30, 0x4b, 0x00, 0x47, 0x5d, 0x62]),
};

/**
 * Build unsigned deposit SOL transaction.
 * User deposits SOL → receives bSOL LP tokens.
 */
export async function buildDepositSolTx(
  wallet: string,
  amount: number
): Promise<string> {
  const player = new PublicKey(wallet);
  const lamports = BigInt(Math.floor(amount * LAMPORTS_PER_SOL));

  const [gameRegistry] = deriveGameRegistry();
  const [solVault] = deriveSolVault();
  const [solVaultState] = deriveSolVaultState();
  const [bsolMint] = deriveBsolMint();
  const [bsolMintAuthority] = deriveBsolMintAuthority();

  // Player's bSOL ATA
  const playerBsolAta = await getAssociatedTokenAddress(bsolMint, player);

  // Build instruction data: discriminator + amount (u64 LE)
  const data = Buffer.alloc(16);
  DISCRIMINATORS.depositSol.copy(data, 0);
  data.writeBigUInt64LE(lamports, 8);

  // Account order must match Anchor DepositSol struct:
  // depositor, game_registry, sol_vault, sol_vault_state, bsol_mint,
  // bsol_mint_authority, depositor_bsol_account, system_program,
  // token_program, associated_token_program, rent
  const keys = [
    { pubkey: player, isSigner: true, isWritable: true },
    { pubkey: gameRegistry, isSigner: false, isWritable: false },
    { pubkey: solVault, isSigner: false, isWritable: true },
    { pubkey: solVaultState, isSigner: false, isWritable: true },
    { pubkey: bsolMint, isSigner: false, isWritable: true },
    { pubkey: bsolMintAuthority, isSigner: false, isWritable: false },
    { pubkey: playerBsolAta, isSigner: false, isWritable: true },
    { pubkey: SystemProgram.programId, isSigner: false, isWritable: false },
    { pubkey: TOKEN_PROGRAM_ID, isSigner: false, isWritable: false },
    { pubkey: ASSOCIATED_TOKEN_PROGRAM_ID, isSigner: false, isWritable: false },
    { pubkey: SYSVAR_RENT, isSigner: false, isWritable: false },
  ];

  const ix = new TransactionInstruction({
    keys,
    programId: BANKROLL_PROGRAM_ID,
    data,
  });

  // Check if bSOL ATA exists — if not, create it
  const ataIxs: TransactionInstruction[] = [];
  try {
    await getAccount(connection, playerBsolAta);
  } catch {
    ataIxs.push(
      createAssociatedTokenAccountInstruction(
        player,
        playerBsolAta,
        player,
        bsolMint
      )
    );
  }

  const blockhash = await getRecentBlockhash();
  const tx = new Transaction({
    recentBlockhash: blockhash,
    feePayer: player,
  });
  tx.add(...computeBudgetIxs(), ...ataIxs, ix);

  return tx
    .serialize({ requireAllSignatures: false, verifySignatures: false })
    .toString("base64");
}

/**
 * Build unsigned withdraw SOL transaction.
 * User burns bSOL LP tokens → receives SOL.
 */
export async function buildWithdrawSolTx(
  wallet: string,
  lpAmount: number
): Promise<string> {
  const player = new PublicKey(wallet);
  const [bsolMint] = deriveBsolMint();
  // LP token amount in raw units (9 decimals like SOL)
  const rawLpAmount = BigInt(Math.floor(lpAmount * 1e9));

  const [gameRegistry] = deriveGameRegistry();
  const [solVault, solVaultBump] = deriveSolVault();
  const [solVaultState] = deriveSolVaultState();

  const playerBsolAta = await getAssociatedTokenAddress(bsolMint, player);

  // Build instruction data: discriminator + lp_amount (u64 LE)
  const data = Buffer.alloc(16);
  DISCRIMINATORS.withdrawSol.copy(data, 0);
  data.writeBigUInt64LE(rawLpAmount, 8);

  const keys = [
    { pubkey: player, isSigner: true, isWritable: true },
    { pubkey: gameRegistry, isSigner: false, isWritable: false },
    { pubkey: solVault, isSigner: false, isWritable: true },
    { pubkey: solVaultState, isSigner: false, isWritable: true },
    { pubkey: bsolMint, isSigner: false, isWritable: true },
    { pubkey: playerBsolAta, isSigner: false, isWritable: true },
    { pubkey: SystemProgram.programId, isSigner: false, isWritable: false },
    { pubkey: TOKEN_PROGRAM_ID, isSigner: false, isWritable: false },
  ];

  const ix = new TransactionInstruction({
    keys,
    programId: BANKROLL_PROGRAM_ID,
    data,
  });

  const blockhash = await getRecentBlockhash();
  const tx = new Transaction({
    recentBlockhash: blockhash,
    feePayer: player,
  });
  tx.add(...computeBudgetIxs(), ix);

  return tx
    .serialize({ requireAllSignatures: false, verifySignatures: false })
    .toString("base64");
}

/**
 * Build unsigned deposit BUX transaction.
 * User deposits BUX → receives bBUX LP tokens.
 */
export async function buildDepositBuxTx(
  wallet: string,
  amount: number
): Promise<string> {
  const player = new PublicKey(wallet);
  const rawAmount = BigInt(Math.floor(amount * 10 ** BUX_DECIMALS));

  const [gameRegistry] = deriveGameRegistry();
  const [buxVaultState] = deriveBuxVaultState();
  const [bbuxMint] = deriveBbuxMint();
  const [bbuxMintAuthority] = deriveBbuxMintAuthority();
  const [buxVaultToken] = deriveBuxVaultToken();

  // Player's BUX ATA (source)
  const playerBuxAta = await getAssociatedTokenAddress(BUX_MINT_ADDRESS, player);
  // Player's bBUX ATA (destination LP tokens)
  const playerBbuxAta = await getAssociatedTokenAddress(bbuxMint, player);

  // Build instruction data: discriminator + amount (u64 LE)
  const data = Buffer.alloc(16);
  DISCRIMINATORS.depositBux.copy(data, 0);
  data.writeBigUInt64LE(rawAmount, 8);

  // Account order must match Anchor DepositBux struct:
  // depositor, game_registry, bux_vault_state, bux_token_account,
  // bbux_mint, bbux_mint_authority, depositor_bux_account,
  // depositor_bbux_account, system_program, token_program,
  // associated_token_program, rent
  const keys = [
    { pubkey: player, isSigner: true, isWritable: true },
    { pubkey: gameRegistry, isSigner: false, isWritable: false },
    { pubkey: buxVaultState, isSigner: false, isWritable: true },
    { pubkey: buxVaultToken, isSigner: false, isWritable: true },
    { pubkey: bbuxMint, isSigner: false, isWritable: true },
    { pubkey: bbuxMintAuthority, isSigner: false, isWritable: false },
    { pubkey: playerBuxAta, isSigner: false, isWritable: true },
    { pubkey: playerBbuxAta, isSigner: false, isWritable: true },
    { pubkey: SystemProgram.programId, isSigner: false, isWritable: false },
    { pubkey: TOKEN_PROGRAM_ID, isSigner: false, isWritable: false },
    { pubkey: ASSOCIATED_TOKEN_PROGRAM_ID, isSigner: false, isWritable: false },
    { pubkey: SYSVAR_RENT, isSigner: false, isWritable: false },
  ];

  const ix = new TransactionInstruction({
    keys,
    programId: BANKROLL_PROGRAM_ID,
    data,
  });

  // Check if bBUX ATA exists — if not, create it
  const ataIxs: TransactionInstruction[] = [];
  try {
    await getAccount(connection, playerBbuxAta);
  } catch {
    ataIxs.push(
      createAssociatedTokenAccountInstruction(
        player,
        playerBbuxAta,
        player,
        bbuxMint
      )
    );
  }

  const blockhash = await getRecentBlockhash();
  const tx = new Transaction({
    recentBlockhash: blockhash,
    feePayer: player,
  });
  tx.add(...computeBudgetIxs(), ...ataIxs, ix);

  return tx
    .serialize({ requireAllSignatures: false, verifySignatures: false })
    .toString("base64");
}

/**
 * Build unsigned withdraw BUX transaction.
 * User burns bBUX LP tokens → receives BUX.
 */
export async function buildWithdrawBuxTx(
  wallet: string,
  lpAmount: number
): Promise<string> {
  const player = new PublicKey(wallet);
  const rawLpAmount = BigInt(Math.floor(lpAmount * 10 ** BUX_DECIMALS));

  const [gameRegistry] = deriveGameRegistry();
  const [buxVaultState] = deriveBuxVaultState();
  const [bbuxMint] = deriveBbuxMint();
  const [buxVaultToken] = deriveBuxVaultToken();

  const playerBuxAta = await getAssociatedTokenAddress(BUX_MINT_ADDRESS, player);
  const playerBbuxAta = await getAssociatedTokenAddress(bbuxMint, player);

  // Build instruction data: discriminator + lp_amount (u64 LE)
  const data = Buffer.alloc(16);
  DISCRIMINATORS.withdrawBux.copy(data, 0);
  data.writeBigUInt64LE(rawLpAmount, 8);

  // Account order must match Anchor WithdrawBux struct:
  // withdrawer, game_registry, bux_vault_state, bux_token_account,
  // bbux_mint, withdrawer_bux_account, withdrawer_bbux_account, token_program
  const keys = [
    { pubkey: player, isSigner: true, isWritable: true },
    { pubkey: gameRegistry, isSigner: false, isWritable: false },
    { pubkey: buxVaultState, isSigner: false, isWritable: true },
    { pubkey: buxVaultToken, isSigner: false, isWritable: true },
    { pubkey: bbuxMint, isSigner: false, isWritable: true },
    { pubkey: playerBuxAta, isSigner: false, isWritable: true },
    { pubkey: playerBbuxAta, isSigner: false, isWritable: true },
    { pubkey: TOKEN_PROGRAM_ID, isSigner: false, isWritable: false },
  ];

  const ix = new TransactionInstruction({
    keys,
    programId: BANKROLL_PROGRAM_ID,
    data,
  });

  const blockhash = await getRecentBlockhash();
  const tx = new Transaction({
    recentBlockhash: blockhash,
    feePayer: player,
  });
  tx.add(...computeBudgetIxs(), ix);

  return tx
    .serialize({ requireAllSignatures: false, verifySignatures: false })
    .toString("base64");
}

/**
 * Build unsigned place bet transaction (SOL or BUX).
 */
export async function buildPlaceBetTx(
  wallet: string,
  gameId: number,
  nonce: number,
  amount: number,
  difficulty: number,
  vaultType: "sol" | "bux"
): Promise<string> {
  const player = new PublicKey(wallet);
  const nonceBigint = BigInt(nonce);

  const [gameRegistry] = deriveGameRegistry();
  const [playerState] = derivePlayerState(player);
  const [betOrder] = deriveBetOrder(player, nonceBigint);

  const isSol = vaultType === "sol";
  const discriminator = isSol
    ? DISCRIMINATORS.placeBetSol
    : DISCRIMINATORS.placeBetBux;
  const decimals = isSol ? 9 : BUX_DECIMALS;
  const rawAmount = BigInt(Math.floor(amount * 10 ** decimals));

  // Instruction data: discriminator(8) + game_id(u64) + nonce(u64) + amount(u64) + difficulty(u8)
  const data = Buffer.alloc(33);
  discriminator.copy(data, 0);
  data.writeBigUInt64LE(BigInt(gameId), 8);
  data.writeBigUInt64LE(nonceBigint, 16);
  data.writeBigUInt64LE(rawAmount, 24);
  data.writeUInt8(difficulty, 32);

  // Account order MUST match Anchor struct exactly.
  // PlaceBetSol: player, game_registry, sol_vault, sol_vault_state, player_state, bet_order, system_program
  // PlaceBetBux: player, game_registry, bux_vault_state, bux_token_account, player_bux_account, player_state, bet_order, system_program, token_program
  const keys: { pubkey: PublicKey; isSigner: boolean; isWritable: boolean }[] = [
    { pubkey: player, isSigner: true, isWritable: true },
    { pubkey: gameRegistry, isSigner: false, isWritable: false },
  ];

  if (isSol) {
    const [solVault] = deriveSolVault();
    const [solVaultState] = deriveSolVaultState();
    keys.push(
      { pubkey: solVault, isSigner: false, isWritable: true },
      { pubkey: solVaultState, isSigner: false, isWritable: true },
      { pubkey: playerState, isSigner: false, isWritable: true },
      { pubkey: betOrder, isSigner: false, isWritable: true },
      { pubkey: SystemProgram.programId, isSigner: false, isWritable: false }
    );
  } else {
    const [buxVaultState] = deriveBuxVaultState();
    const [buxVaultToken] = deriveBuxVaultToken();
    const playerBuxAta = await getAssociatedTokenAddress(
      BUX_MINT_ADDRESS,
      player
    );
    keys.push(
      { pubkey: buxVaultState, isSigner: false, isWritable: true },
      { pubkey: buxVaultToken, isSigner: false, isWritable: true },
      { pubkey: playerBuxAta, isSigner: false, isWritable: true },
      { pubkey: playerState, isSigner: false, isWritable: true },
      { pubkey: betOrder, isSigner: false, isWritable: true },
      { pubkey: SystemProgram.programId, isSigner: false, isWritable: false },
      { pubkey: TOKEN_PROGRAM_ID, isSigner: false, isWritable: false }
    );
  }

  const ix = new TransactionInstruction({
    keys,
    programId: BANKROLL_PROGRAM_ID,
    data,
  });

  const blockhash = await getRecentBlockhash();
  const tx = new Transaction({
    recentBlockhash: blockhash,
    feePayer: player,
  });
  tx.add(...computeBudgetIxs(), ix);

  return tx
    .serialize({ requireAllSignatures: false, verifySignatures: false })
    .toString("base64");
}

/**
 * Build unsigned reclaim_expired transaction.
 * Player reclaims a stuck bet that has exceeded the bet timeout.
 * Player must sign this transaction (not the settler).
 *
 * ReclaimExpired accounts (from Rust struct):
 *   player (Signer, mut), game_registry, sol_vault (mut), sol_vault_state (mut),
 *   bux_vault_state (mut), bux_token_account (mut), player_state (mut),
 *   bet_order (mut, close=player), player_bux_account (Option, mut),
 *   system_program, token_program
 *
 * Args: nonce (u64)
 */
export async function buildReclaimExpiredTx(
  wallet: string,
  nonce: number,
  vaultType: "sol" | "bux"
): Promise<string> {
  const player = new PublicKey(wallet);
  const nonceBigint = BigInt(nonce);

  const [gameRegistry] = deriveGameRegistry();
  const [solVault] = deriveSolVault();
  const [solVaultState] = deriveSolVaultState();
  const [buxVaultState] = deriveBuxVaultState();
  const [buxTokenAccount] = deriveBuxVaultToken();
  const [playerState] = derivePlayerState(player);
  const [betOrder] = deriveBetOrder(player, nonceBigint);

  // Instruction data: discriminator (8) + nonce (u64 LE, 8) = 16 bytes
  const data = Buffer.alloc(16);
  DISCRIMINATORS.reclaimExpired.copy(data, 0);
  data.writeBigUInt64LE(nonceBigint, 8);

  // For BUX bets, we need the player's BUX token account for refund.
  // For SOL bets, pass program ID as None sentinel for the Option<Account>.
  const isBux = vaultType === "bux";
  let playerBuxAta: PublicKey;
  if (isBux) {
    playerBuxAta = await getAssociatedTokenAddress(BUX_MINT_ADDRESS, player);
  } else {
    playerBuxAta = BANKROLL_PROGRAM_ID; // None sentinel for Anchor Option<Account>
  }

  // Account order must match Anchor ReclaimExpired struct exactly:
  // 1. player (Signer, mut)
  // 2. game_registry (read-only)
  // 3. sol_vault (mut)
  // 4. sol_vault_state (mut)
  // 5. bux_vault_state (mut)
  // 6. bux_token_account (mut)
  // 7. player_state (mut)
  // 8. bet_order (mut, close=player)
  // 9. player_bux_account (Option, mut)
  // 10. system_program
  // 11. token_program
  const keys = [
    { pubkey: player, isSigner: true, isWritable: true },
    { pubkey: gameRegistry, isSigner: false, isWritable: false },
    { pubkey: solVault, isSigner: false, isWritable: true },
    { pubkey: solVaultState, isSigner: false, isWritable: true },
    { pubkey: buxVaultState, isSigner: false, isWritable: true },
    { pubkey: buxTokenAccount, isSigner: false, isWritable: true },
    { pubkey: playerState, isSigner: false, isWritable: true },
    { pubkey: betOrder, isSigner: false, isWritable: true },
    { pubkey: playerBuxAta, isSigner: false, isWritable: true },
    { pubkey: SystemProgram.programId, isSigner: false, isWritable: false },
    { pubkey: TOKEN_PROGRAM_ID, isSigner: false, isWritable: false },
  ];

  const ix = new TransactionInstruction({
    keys,
    programId: BANKROLL_PROGRAM_ID,
    data,
  });

  const blockhash = await getRecentBlockhash();
  const tx = new Transaction({
    recentBlockhash: blockhash,
    feePayer: player,
  });
  tx.add(...computeBudgetIxs(), ix);

  return tx
    .serialize({ requireAllSignatures: false, verifySignatures: false })
    .toString("base64");
}

// -------------------------------------------------------------------
// Commitment & Settlement (settler-signed transactions)
// -------------------------------------------------------------------

/**
 * Submit a commitment hash to the bankroll program.
 * Settler signs and sends this transaction.
 *
 * Accounts: settler (signer), gameRegistry, playerState, systemProgram
 * Args: player_key (Pubkey), nonce (u64), commitment_hash ([u8;32])
 */
export async function submitCommitment(
  player: string,
  nonce: number,
  commitmentHash: string
): Promise<string> {
  const settler = MINT_AUTHORITY;
  const playerKey = new PublicKey(player);
  const nonceBigint = BigInt(nonce);

  const [gameRegistry] = deriveGameRegistry();
  const [playerState] = derivePlayerState(playerKey);

  // Parse commitment hash from hex string to 32 bytes
  const hashBytes = Buffer.from(commitmentHash, "hex");
  if (hashBytes.length !== 32) {
    throw new Error(`Invalid commitment hash length: ${hashBytes.length}, expected 32`);
  }

  // Instruction data: discriminator (8) + player_key (32) + nonce (8) + commitment_hash (32) = 80
  const data = Buffer.alloc(80);
  DISCRIMINATORS.submitCommitment.copy(data, 0);
  playerKey.toBuffer().copy(data, 8);
  data.writeBigUInt64LE(nonceBigint, 40);
  hashBytes.copy(data, 48);

  const keys = [
    { pubkey: settler.publicKey, isSigner: true, isWritable: true },
    { pubkey: gameRegistry, isSigner: false, isWritable: false },
    { pubkey: playerState, isSigner: false, isWritable: true },
    { pubkey: SystemProgram.programId, isSigner: false, isWritable: false },
  ];

  const ix = new TransactionInstruction({
    keys,
    programId: BANKROLL_PROGRAM_ID,
    data,
  });

  return sendSettlerTx(() => [ix], settler);
}

/**
 * Settle a bet on the bankroll program by revealing the server seed.
 * Settler signs and sends this transaction.
 *
 * Accounts: settler (signer), gameRegistry, solVault, solVaultState, buxVaultState,
 *           buxTokenAccount, player, playerState, betOrder, [optional: playerBuxAccount],
 *           systemProgram, tokenProgram
 * Args: nonce (u64), server_seed ([u8;32]), won (bool), payout (u64)
 */
export async function settleBet(
  player: string,
  nonce: number,
  serverSeed: string,
  won: boolean,
  payout: number,
  vaultType: string
): Promise<string> {
  const settler = MINT_AUTHORITY;
  const playerKey = new PublicKey(player);
  const nonceBigint = BigInt(nonce);

  const [gameRegistry] = deriveGameRegistry();
  const [solVault] = deriveSolVault();
  const [solVaultState] = deriveSolVaultState();
  const [buxVaultState] = deriveBuxVaultState();
  const [buxTokenAccount] = deriveBuxVaultToken();
  const [playerState] = derivePlayerState(playerKey);
  const [betOrder] = deriveBetOrder(playerKey, nonceBigint);

  // Parse server seed from hex string to 32 bytes
  const seedBytes = Buffer.from(serverSeed, "hex");
  if (seedBytes.length !== 32) {
    throw new Error(`Invalid server seed length: ${seedBytes.length}, expected 32`);
  }

  // Payout in raw units
  const isSol = vaultType === "sol";
  const decimals = isSol ? 9 : BUX_DECIMALS;
  const rawPayout = BigInt(Math.floor(payout * 10 ** decimals));

  // Instruction data: discriminator (8) + nonce (8) + server_seed (32) + won (1) + payout (8) = 57
  const data = Buffer.alloc(57);
  DISCRIMINATORS.settleBet.copy(data, 0);
  data.writeBigUInt64LE(nonceBigint, 8);
  seedBytes.copy(data, 16);
  data.writeUInt8(won ? 1 : 0, 48);
  data.writeBigUInt64LE(rawPayout, 49);

  // For BUX payouts, we need the player's BUX token account; otherwise pass program ID as None
  let playerBuxAta: PublicKey;
  if (!isSol && won && payout > 0) {
    playerBuxAta = await getAssociatedTokenAddress(BUX_MINT_ADDRESS, playerKey);
  } else {
    playerBuxAta = BANKROLL_PROGRAM_ID; // None sentinel for Anchor Option<Account>
  }

  // All 18 accounts in exact Anchor order. Optional accounts use program ID for None.
  const NONE = BANKROLL_PROGRAM_ID;
  const keys: { pubkey: PublicKey; isSigner: boolean; isWritable: boolean }[] = [
    { pubkey: settler.publicKey, isSigner: true, isWritable: true },       // 1. settler
    { pubkey: gameRegistry, isSigner: false, isWritable: false },          // 2. game_registry
    { pubkey: solVault, isSigner: false, isWritable: true },               // 3. sol_vault
    { pubkey: solVaultState, isSigner: false, isWritable: true },          // 4. sol_vault_state
    { pubkey: buxVaultState, isSigner: false, isWritable: true },          // 5. bux_vault_state
    { pubkey: buxTokenAccount, isSigner: false, isWritable: true },        // 6. bux_token_account
    { pubkey: playerKey, isSigner: false, isWritable: true },              // 7. player
    { pubkey: playerState, isSigner: false, isWritable: true },            // 8. player_state
    { pubkey: betOrder, isSigner: false, isWritable: true },               // 9. bet_order
    { pubkey: playerBuxAta, isSigner: false, isWritable: true },           // 10. player_bux_account (Option)
    { pubkey: NONE, isSigner: false, isWritable: false },                  // 11. tier1_referrer (Option)
    { pubkey: NONE, isSigner: false, isWritable: false },                  // 12. tier1_referrer_bux_account (Option)
    { pubkey: NONE, isSigner: false, isWritable: false },                  // 13. tier2_referrer (Option)
    { pubkey: NONE, isSigner: false, isWritable: false },                  // 14. tier2_referrer_bux_account (Option)
    { pubkey: NONE, isSigner: false, isWritable: false },                  // 15. tier1_referral_state (Option)
    { pubkey: NONE, isSigner: false, isWritable: false },                  // 16. tier2_referral_state (Option)
    { pubkey: SystemProgram.programId, isSigner: false, isWritable: false }, // 17. system_program
    { pubkey: TOKEN_PROGRAM_ID, isSigner: false, isWritable: false },      // 18. token_program
  ];

  const ix = new TransactionInstruction({
    keys,
    programId: BANKROLL_PROGRAM_ID,
    data,
  });

  return sendSettlerTx(() => [ix], settler);
}

/**
 * Get LP token balance for a wallet (bSOL or bBUX).
 */
export async function getLpBalance(
  wallet: string,
  vaultType: "sol" | "bux"
): Promise<number> {
  const player = new PublicKey(wallet);
  const [lpMint] =
    vaultType === "sol" ? deriveBsolMint() : deriveBbuxMint();

  try {
    const ata = await getAssociatedTokenAddress(lpMint, player);
    const account = await getAccount(connection, ata);
    const decimals = vaultType === "sol" ? 9 : BUX_DECIMALS;
    return Number(account.amount) / 10 ** decimals;
  } catch {
    return 0; // ATA doesn't exist
  }
}
