/**
 * Initialize Bankroll Program on Devnet
 *
 * This script performs the 4-step initialization of the bankroll program:
 * 1. initializeRegistry — creates GameRegistry + SolVaultState + BuxVaultState
 * 2. initializeSolPool — creates bSOL LP mint
 * 3. initializeBuxPool — creates bBUX LP mint
 * 4. initializeBuxVault — creates BUX token account
 *
 * Then registers the Coin Flip game (game_id=1) and optionally seeds initial liquidity.
 *
 * Usage: npx ts-node scripts/init-bankroll.ts [--seed-liquidity]
 *
 * Prerequisites:
 * - Bankroll program deployed to devnet at 49up2uzZANpjTC3sgggbZazdHBii2vY9mVK3vk5dT2tm
 * - Deploy wallet keypair at keypairs/mint-authority.json (same authority)
 * - Deploy wallet funded with SOL on devnet
 */

import {
  Connection,
  Keypair,
  PublicKey,
  SystemProgram,
  Transaction,
  TransactionInstruction,
  LAMPORTS_PER_SOL,
  sendAndConfirmTransaction,
} from "@solana/web3.js";
import {
  TOKEN_PROGRAM_ID,
  ASSOCIATED_TOKEN_PROGRAM_ID,
} from "@solana/spl-token";
import * as fs from "fs";
import * as path from "path";

// -------------------------------------------------------------------
// Configuration
// -------------------------------------------------------------------

const RPC_URL =
  process.env.SOLANA_RPC_URL ||
  "https://summer-sleek-shape.solana-devnet.quiknode.pro/92b7f51caa76f2981879528aee40a3e8e58cac60/";

const BANKROLL_PROGRAM_ID = new PublicKey(
  process.env.BANKROLL_PROGRAM_ID ||
    "49up2uzZANpjTC3sgggbZazdHBii2vY9mVK3vk5dT2tm"
);

const BUX_MINT_ADDRESS = new PublicKey(
  process.env.BUX_MINT_ADDRESS ||
    "7CuRyw2YkqQhUUFbw6CCnoedHWT8tK2c9UzZQYDGmxVX"
);

const KEYPAIR_DIR = path.join(__dirname, "..", "keypairs");
const BET_TIMEOUT = 300; // 5 minutes

// -------------------------------------------------------------------
// PDA Seeds (must match bankroll-service.ts)
// -------------------------------------------------------------------

function derivePDA(seed: string): [PublicKey, number] {
  return PublicKey.findProgramAddressSync(
    [Buffer.from(seed)],
    BANKROLL_PROGRAM_ID
  );
}

const [GAME_REGISTRY] = derivePDA("game_registry");
const [SOL_VAULT] = derivePDA("sol_vault");
const [SOL_VAULT_STATE] = derivePDA("sol_vault_state");
const [BUX_VAULT_STATE] = derivePDA("bux_vault_state");
const [BSOL_MINT] = derivePDA("bsol_mint");
const [BSOL_MINT_AUTHORITY] = derivePDA("bsol_mint_authority");
const [BBUX_MINT] = derivePDA("bbux_mint");
const [BBUX_MINT_AUTHORITY] = derivePDA("bbux_mint_authority");
const [BUX_VAULT_TOKEN] = derivePDA("bux_token_account");
const SYSVAR_RENT = new PublicKey("SysvarRent111111111111111111111111111111111");

// -------------------------------------------------------------------
// IDL Discriminators
// -------------------------------------------------------------------

const DISCRIMINATORS = {
  initializeRegistry: Buffer.from([189, 181, 20, 17, 174, 57, 249, 59]),
  initializeSolPool: Buffer.from([40, 228, 232, 17, 163, 139, 84, 165]),
  initializeBuxPool: Buffer.from([205, 68, 136, 203, 134, 107, 87, 146]),
  initializeBuxVault: Buffer.from([93, 189, 232, 183, 203, 188, 26, 212]),
  registerGame: Buffer.from([122, 44, 95, 58, 89, 33, 40, 59]),
  depositSol: Buffer.from([108, 81, 78, 117, 125, 155, 56, 200]),
};

// -------------------------------------------------------------------
// Helpers
// -------------------------------------------------------------------

function loadKeypair(filepath: string): Keypair {
  const raw = JSON.parse(fs.readFileSync(filepath, "utf-8"));
  return Keypair.fromSecretKey(Uint8Array.from(raw));
}

async function sendTx(
  connection: Connection,
  authority: Keypair,
  ix: TransactionInstruction,
  label: string
): Promise<string> {
  const tx = new Transaction().add(ix);
  console.log(`  Sending ${label}...`);
  try {
    const sig = await sendAndConfirmTransaction(connection, tx, [authority], {
      commitment: "confirmed",
    });
    console.log(`  ✓ ${label}: ${sig}`);
    return sig;
  } catch (err: any) {
    if (
      err.message?.includes("already in use") ||
      err.logs?.some((l: string) => l.includes("already in use"))
    ) {
      console.log(`  ⊘ ${label}: already initialized — skipping`);
      return "already-initialized";
    }
    throw err;
  }
}

// -------------------------------------------------------------------
// Step 1: Initialize Registry
// -------------------------------------------------------------------

async function initializeRegistry(
  connection: Connection,
  authority: Keypair
): Promise<void> {
  console.log("\n[Step 1/4] Initialize Registry");

  const data = Buffer.alloc(16);
  DISCRIMINATORS.initializeRegistry.copy(data, 0);
  // bet_timeout: i64 LE
  data.writeBigInt64LE(BigInt(BET_TIMEOUT), 8);

  const ix = new TransactionInstruction({
    keys: [
      { pubkey: authority.publicKey, isSigner: true, isWritable: true },
      { pubkey: authority.publicKey, isSigner: false, isWritable: false }, // settler
      { pubkey: BUX_MINT_ADDRESS, isSigner: false, isWritable: false },
      { pubkey: GAME_REGISTRY, isSigner: false, isWritable: true },
      { pubkey: SOL_VAULT, isSigner: false, isWritable: true },
      { pubkey: SOL_VAULT_STATE, isSigner: false, isWritable: true },
      { pubkey: BUX_VAULT_STATE, isSigner: false, isWritable: true },
      {
        pubkey: SystemProgram.programId,
        isSigner: false,
        isWritable: false,
      },
    ],
    programId: BANKROLL_PROGRAM_ID,
    data,
  });

  await sendTx(connection, authority, ix, "initializeRegistry");
}

// -------------------------------------------------------------------
// Step 2: Initialize SOL Pool
// -------------------------------------------------------------------

async function initializeSolPool(
  connection: Connection,
  authority: Keypair
): Promise<void> {
  console.log("\n[Step 2/4] Initialize SOL Pool");

  const data = Buffer.from(DISCRIMINATORS.initializeSolPool);

  const ix = new TransactionInstruction({
    keys: [
      { pubkey: authority.publicKey, isSigner: true, isWritable: true },
      { pubkey: GAME_REGISTRY, isSigner: false, isWritable: true },
      { pubkey: BSOL_MINT, isSigner: false, isWritable: true },
      { pubkey: BSOL_MINT_AUTHORITY, isSigner: false, isWritable: false },
      { pubkey: SystemProgram.programId, isSigner: false, isWritable: false },
      { pubkey: TOKEN_PROGRAM_ID, isSigner: false, isWritable: false },
      { pubkey: SYSVAR_RENT, isSigner: false, isWritable: false },
    ],
    programId: BANKROLL_PROGRAM_ID,
    data,
  });

  await sendTx(connection, authority, ix, "initializeSolPool");
}

// -------------------------------------------------------------------
// Step 3: Initialize BUX Pool
// -------------------------------------------------------------------

async function initializeBuxPool(
  connection: Connection,
  authority: Keypair
): Promise<void> {
  console.log("\n[Step 3/4] Initialize BUX Pool");

  const data = Buffer.from(DISCRIMINATORS.initializeBuxPool);

  const ix = new TransactionInstruction({
    keys: [
      { pubkey: authority.publicKey, isSigner: true, isWritable: true },
      { pubkey: GAME_REGISTRY, isSigner: false, isWritable: true },
      { pubkey: BBUX_MINT, isSigner: false, isWritable: true },
      { pubkey: BBUX_MINT_AUTHORITY, isSigner: false, isWritable: false },
      { pubkey: SystemProgram.programId, isSigner: false, isWritable: false },
      { pubkey: TOKEN_PROGRAM_ID, isSigner: false, isWritable: false },
      { pubkey: SYSVAR_RENT, isSigner: false, isWritable: false },
    ],
    programId: BANKROLL_PROGRAM_ID,
    data,
  });

  await sendTx(connection, authority, ix, "initializeBuxPool");
}

// -------------------------------------------------------------------
// Step 4: Initialize BUX Vault
// -------------------------------------------------------------------

async function initializeBuxVault(
  connection: Connection,
  authority: Keypair
): Promise<void> {
  console.log("\n[Step 4/4] Initialize BUX Vault");

  const data = Buffer.from(DISCRIMINATORS.initializeBuxVault);

  const ix = new TransactionInstruction({
    keys: [
      { pubkey: authority.publicKey, isSigner: true, isWritable: true },
      { pubkey: GAME_REGISTRY, isSigner: false, isWritable: true },
      { pubkey: BUX_MINT_ADDRESS, isSigner: false, isWritable: false },
      { pubkey: BUX_VAULT_TOKEN, isSigner: false, isWritable: true },
      { pubkey: SystemProgram.programId, isSigner: false, isWritable: false },
      { pubkey: TOKEN_PROGRAM_ID, isSigner: false, isWritable: false },
      { pubkey: SYSVAR_RENT, isSigner: false, isWritable: false },
    ],
    programId: BANKROLL_PROGRAM_ID,
    data,
  });

  await sendTx(connection, authority, ix, "initializeBuxVault");
}

// -------------------------------------------------------------------
// Register Coin Flip Game (game_id=1)
// -------------------------------------------------------------------

async function registerCoinFlipGame(
  connection: Connection,
  authority: Keypair
): Promise<void> {
  console.log("\n[Register Game] Coin Flip (game_id=1)");

  // Anchor signature: register_game(game_id: u64, name: [u8; 32], min_bet: u64, max_bet_bps: u16, fee_bps: u16)
  const gameId = BigInt(1);
  const name = Buffer.alloc(32);
  Buffer.from("Coin Flip").copy(name);
  const minBet = BigInt(1000); // 0.000001 SOL minimum
  const maxBetBps = 1000; // 10% of vault
  const feeBps = 200; // 2% house edge

  // Data layout: discriminator(8) + game_id(8) + name(32) + min_bet(8) + max_bet_bps(2) + fee_bps(2)
  const data = Buffer.alloc(8 + 8 + 32 + 8 + 2 + 2);
  DISCRIMINATORS.registerGame.copy(data, 0);
  data.writeBigUInt64LE(gameId, 8);
  name.copy(data, 16);
  data.writeBigUInt64LE(minBet, 48);
  data.writeUInt16LE(maxBetBps, 56);
  data.writeUInt16LE(feeBps, 58);

  // RegisterGame struct: authority (signer, mut), game_registry (mut)
  const ix = new TransactionInstruction({
    keys: [
      { pubkey: authority.publicKey, isSigner: true, isWritable: true },
      { pubkey: GAME_REGISTRY, isSigner: false, isWritable: true },
    ],
    programId: BANKROLL_PROGRAM_ID,
    data,
  });

  try {
    await sendTx(connection, authority, ix, "registerGame (Coin Flip)");
  } catch (err: any) {
    // GameAlreadyRegistered (error code 6001) — idempotent, just skip
    if (
      err.message?.includes("GameAlreadyRegistered") ||
      err.message?.includes("0x1771") ||
      err.logs?.some((l: string) => l.includes("GameAlreadyRegistered"))
    ) {
      console.log("  ⊘ registerGame (Coin Flip): game already registered — skipping");
      return;
    }
    throw err;
  }
}

// -------------------------------------------------------------------
// Seed Initial Liquidity
// -------------------------------------------------------------------

async function seedLiquidity(
  connection: Connection,
  authority: Keypair,
  solAmount: number
): Promise<void> {
  console.log(`\n[Seed Liquidity] Depositing ${solAmount} SOL`);

  const lamports = BigInt(Math.floor(solAmount * LAMPORTS_PER_SOL));

  const data = Buffer.alloc(16);
  DISCRIMINATORS.depositSol.copy(data, 0);
  data.writeBigUInt64LE(lamports, 8);

  const { getAssociatedTokenAddress, createAssociatedTokenAccountInstruction, getAccount } =
    require("@solana/spl-token");

  const playerBsolAta = await getAssociatedTokenAddress(BSOL_MINT, authority.publicKey);

  const tx = new Transaction();

  // Create bSOL ATA if needed
  try {
    await getAccount(connection, playerBsolAta);
  } catch {
    tx.add(
      createAssociatedTokenAccountInstruction(
        authority.publicKey,
        playerBsolAta,
        authority.publicKey,
        BSOL_MINT
      )
    );
  }

  // Account order must match Anchor DepositSol struct exactly:
  // 1. depositor (signer, mut)
  // 2. game_registry (read-only)
  // 3. sol_vault (mut)
  // 4. sol_vault_state (mut)
  // 5. bsol_mint (mut)
  // 6. bsol_mint_authority (read-only)
  // 7. depositor_bsol_account (mut)
  // 8. system_program
  // 9. token_program
  // 10. associated_token_program
  // 11. rent
  const ix = new TransactionInstruction({
    keys: [
      { pubkey: authority.publicKey, isSigner: true, isWritable: true },
      { pubkey: GAME_REGISTRY, isSigner: false, isWritable: false },
      { pubkey: SOL_VAULT, isSigner: false, isWritable: true },
      { pubkey: SOL_VAULT_STATE, isSigner: false, isWritable: true },
      { pubkey: BSOL_MINT, isSigner: false, isWritable: true },
      { pubkey: BSOL_MINT_AUTHORITY, isSigner: false, isWritable: false },
      { pubkey: playerBsolAta, isSigner: false, isWritable: true },
      { pubkey: SystemProgram.programId, isSigner: false, isWritable: false },
      { pubkey: TOKEN_PROGRAM_ID, isSigner: false, isWritable: false },
      { pubkey: ASSOCIATED_TOKEN_PROGRAM_ID, isSigner: false, isWritable: false },
      { pubkey: SYSVAR_RENT, isSigner: false, isWritable: false },
    ],
    programId: BANKROLL_PROGRAM_ID,
    data,
  });

  tx.add(ix);

  const sig = await sendAndConfirmTransaction(connection, tx, [authority], {
    commitment: "confirmed",
  });
  console.log(`  ✓ Seed deposit: ${sig}`);
}

// -------------------------------------------------------------------
// Main
// -------------------------------------------------------------------

async function main() {
  const shouldSeed = process.argv.includes("--seed-liquidity");

  console.log("=".repeat(60));
  console.log("Bankroll Program Initialization");
  console.log(`RPC: ${RPC_URL}`);
  console.log(`Program: ${BANKROLL_PROGRAM_ID.toBase58()}`);
  console.log(`BUX Mint: ${BUX_MINT_ADDRESS.toBase58()}`);
  console.log("=".repeat(60));

  const connection = new Connection(RPC_URL, "confirmed");
  const slot = await connection.getSlot();
  console.log(`Connected (slot: ${slot})`);

  // Load authority keypair
  const authorityPath = path.join(KEYPAIR_DIR, "mint-authority.json");
  if (!fs.existsSync(authorityPath)) {
    throw new Error(`Authority keypair not found: ${authorityPath}`);
  }
  const authority = loadKeypair(authorityPath);
  console.log(`Authority: ${authority.publicKey.toBase58()}`);

  const balance = await connection.getBalance(authority.publicKey);
  console.log(`Balance: ${balance / LAMPORTS_PER_SOL} SOL`);

  if (balance < 0.1 * LAMPORTS_PER_SOL) {
    throw new Error("Insufficient SOL — need at least 0.1 SOL for init");
  }

  // Print PDAs
  console.log("\nDerived PDAs:");
  console.log(`  GameRegistry:   ${GAME_REGISTRY.toBase58()}`);
  console.log(`  SOL Vault:      ${SOL_VAULT.toBase58()}`);
  console.log(`  SOL Vault State: ${SOL_VAULT_STATE.toBase58()}`);
  console.log(`  BUX Vault State: ${BUX_VAULT_STATE.toBase58()}`);
  console.log(`  bSOL Mint:      ${BSOL_MINT.toBase58()}`);
  console.log(`  bBUX Mint:      ${BBUX_MINT.toBase58()}`);
  console.log(`  BUX Vault Token: ${BUX_VAULT_TOKEN.toBase58()}`);

  // 4-step initialization
  await initializeRegistry(connection, authority);
  await initializeSolPool(connection, authority);
  await initializeBuxPool(connection, authority);
  await initializeBuxVault(connection, authority);

  // Register Coin Flip game
  await registerCoinFlipGame(connection, authority);

  // Optionally seed liquidity
  if (shouldSeed) {
    await seedLiquidity(connection, authority, 1.0); // 1 SOL seed
  }

  console.log("\n" + "=".repeat(60));
  console.log("Bankroll initialization complete!");
  console.log("=".repeat(60));
}

main().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
