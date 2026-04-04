/**
 * Initialize Airdrop Program on Devnet
 *
 * This script initializes the Blockster Airdrop program:
 * 1. initialize — creates AirdropState PDA with authority, BUX mint, and treasury
 *
 * Optionally starts a test round with --test-round flag.
 *
 * Usage: npx ts-node scripts/init-airdrop.ts [--test-round]
 *
 * Prerequisites:
 * - Airdrop program deployed to devnet at wxiuLBuqxem5ETmGDndiW8MMkxKXp5jVsNCqdZgmjaG
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
  getAssociatedTokenAddress,
} from "@solana/spl-token";
import * as fs from "fs";
import * as path from "path";
import * as crypto from "crypto";

// -------------------------------------------------------------------
// Configuration
// -------------------------------------------------------------------

const RPC_URL =
  process.env.SOLANA_RPC_URL ||
  "https://summer-sleek-shape.solana-devnet.quiknode.pro/92b7f51caa76f2981879528aee40a3e8e58cac60/";

const AIRDROP_PROGRAM_ID = new PublicKey(
  process.env.AIRDROP_PROGRAM_ID ||
    "wxiuLBuqxem5ETmGDndiW8MMkxKXp5jVsNCqdZgmjaG"
);

const BUX_MINT_ADDRESS = new PublicKey(
  process.env.BUX_MINT_ADDRESS ||
    "7CuRyw2YkqQhUUFbw6CCnoedHWT8tK2c9UzZQYDGmxVX"
);

// -------------------------------------------------------------------
// Helpers
// -------------------------------------------------------------------

function loadKeypair(filepath: string): Keypair {
  const raw = JSON.parse(fs.readFileSync(filepath, "utf-8"));
  return Keypair.fromSecretKey(Uint8Array.from(raw));
}

// IDL discriminators
const DISCRIMINATORS = {
  initialize: Buffer.from([175, 175, 109, 31, 13, 152, 155, 237]),
  startRound: Buffer.from([144, 144, 43, 7, 193, 42, 217, 215]),
  fundPrizes: Buffer.from([163, 225, 193, 125, 144, 171, 29, 241]),
};

// PDA derivation
function deriveAirdropState(): [PublicKey, number] {
  return PublicKey.findProgramAddressSync(
    [Buffer.from("airdrop")],
    AIRDROP_PROGRAM_ID
  );
}

function deriveRound(roundId: number): [PublicKey, number] {
  const buf = Buffer.alloc(8);
  buf.writeBigUInt64LE(BigInt(roundId));
  return PublicKey.findProgramAddressSync(
    [Buffer.from("round"), buf],
    AIRDROP_PROGRAM_ID
  );
}

function derivePrizeVault(roundId: number): [PublicKey, number] {
  const buf = Buffer.alloc(8);
  buf.writeBigUInt64LE(BigInt(roundId));
  return PublicKey.findProgramAddressSync(
    [Buffer.from("prize_vault"), buf],
    AIRDROP_PROGRAM_ID
  );
}

// -------------------------------------------------------------------
// Main
// -------------------------------------------------------------------

async function main() {
  const conn = new Connection(RPC_URL, "confirmed");
  const keypairPath = path.join(__dirname, "..", "keypairs", "mint-authority.json");

  if (!fs.existsSync(keypairPath)) {
    console.error(`Keypair not found at ${keypairPath}`);
    process.exit(1);
  }

  const authority = loadKeypair(keypairPath);
  console.log("Authority:", authority.publicKey.toBase58());
  console.log("Airdrop Program:", AIRDROP_PROGRAM_ID.toBase58());
  console.log("BUX Mint:", BUX_MINT_ADDRESS.toBase58());

  const balance = await conn.getBalance(authority.publicKey);
  console.log(`Balance: ${balance / LAMPORTS_PER_SOL} SOL`);

  if (balance < 0.01 * LAMPORTS_PER_SOL) {
    console.error("Insufficient SOL balance. Need at least 0.01 SOL.");
    process.exit(1);
  }

  // Treasury = authority for simplicity (receives BUX entries)
  const treasury = authority.publicKey;

  // Step 1: Initialize
  const [airdropStatePDA] = deriveAirdropState();
  console.log("\n--- Step 1: Initialize ---");
  console.log("AirdropState PDA:", airdropStatePDA.toBase58());

  const existingAcct = await conn.getAccountInfo(airdropStatePDA);
  if (existingAcct) {
    console.log("AirdropState already exists, skipping initialization.");
  } else {
    const data = Buffer.alloc(8);
    DISCRIMINATORS.initialize.copy(data, 0);

    const keys = [
      { pubkey: authority.publicKey, isSigner: true, isWritable: true },
      { pubkey: BUX_MINT_ADDRESS, isSigner: false, isWritable: false },
      { pubkey: treasury, isSigner: false, isWritable: false },
      { pubkey: airdropStatePDA, isSigner: false, isWritable: true },
      { pubkey: SystemProgram.programId, isSigner: false, isWritable: false },
    ];

    const ix = new TransactionInstruction({
      keys,
      programId: AIRDROP_PROGRAM_ID,
      data,
    });

    const tx = new Transaction().add(ix);
    const sig = await sendAndConfirmTransaction(conn, tx, [authority]);
    console.log("Initialize tx:", sig);
  }

  // Optional: Start a test round
  if (process.argv.includes("--test-round")) {
    console.log("\n--- Starting Test Round ---");

    // Generate test server seed and commitment
    const serverSeed = crypto.randomBytes(32);
    const commitmentHash = crypto.createHash("sha256").update(serverSeed).digest();
    const endTime = Math.floor(Date.now() / 1000) + 3600; // 1 hour from now

    // Round 1
    const [roundPDA] = deriveRound(1);
    console.log("Round PDA:", roundPDA.toBase58());
    console.log("Server Seed:", serverSeed.toString("hex"));
    console.log("Commitment:", commitmentHash.toString("hex"));
    console.log("End Time:", new Date(endTime * 1000).toISOString());

    // Start round instruction
    const startData = Buffer.alloc(8 + 32 + 8);
    DISCRIMINATORS.startRound.copy(startData, 0);
    commitmentHash.copy(startData, 8);
    startData.writeBigInt64LE(BigInt(endTime), 40);

    const startKeys = [
      { pubkey: authority.publicKey, isSigner: true, isWritable: true },
      { pubkey: airdropStatePDA, isSigner: false, isWritable: true },
      { pubkey: SystemProgram.programId, isSigner: false, isWritable: false }, // prize_mint = SOL
      { pubkey: roundPDA, isSigner: false, isWritable: true },
      { pubkey: SystemProgram.programId, isSigner: false, isWritable: false },
    ];

    const startIx = new TransactionInstruction({
      keys: startKeys,
      programId: AIRDROP_PROGRAM_ID,
      data: startData,
    });

    const startTx = new Transaction().add(startIx);
    const startSig = await sendAndConfirmTransaction(conn, startTx, [authority]);
    console.log("Start round tx:", startSig);

    // Fund prizes with 0.1 SOL
    const [prizeVaultPDA] = derivePrizeVault(1);
    console.log("Prize Vault PDA:", prizeVaultPDA.toBase58());

    const fundData = Buffer.alloc(8 + 8 + 8);
    DISCRIMINATORS.fundPrizes.copy(fundData, 0);
    fundData.writeBigUInt64LE(1n, 8); // roundId = 1
    fundData.writeBigUInt64LE(BigInt(0.1 * LAMPORTS_PER_SOL), 16); // 0.1 SOL

    const fundKeys = [
      { pubkey: authority.publicKey, isSigner: true, isWritable: true },
      { pubkey: airdropStatePDA, isSigner: false, isWritable: false },
      { pubkey: roundPDA, isSigner: false, isWritable: true },
      { pubkey: prizeVaultPDA, isSigner: false, isWritable: true },
      { pubkey: AIRDROP_PROGRAM_ID, isSigner: false, isWritable: false }, // None: authority_token_account
      { pubkey: AIRDROP_PROGRAM_ID, isSigner: false, isWritable: false }, // None: prize_vault_token_account
      { pubkey: SystemProgram.programId, isSigner: false, isWritable: false },
      { pubkey: TOKEN_PROGRAM_ID, isSigner: false, isWritable: false },
    ];

    const fundIx = new TransactionInstruction({
      keys: fundKeys,
      programId: AIRDROP_PROGRAM_ID,
      data: fundData,
    });

    const fundTx = new Transaction().add(fundIx);
    const fundSig = await sendAndConfirmTransaction(conn, fundTx, [authority]);
    console.log("Fund prizes tx:", fundSig);

    console.log("\nTest round started! Server seed saved — use it for draw_winners later.");
    console.log("Server seed (save this):", serverSeed.toString("hex"));
  }

  console.log("\nDone!");
}

main().catch((err) => {
  console.error("Fatal:", err);
  process.exit(1);
});
