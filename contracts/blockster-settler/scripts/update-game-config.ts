/**
 * Update Coin Flip game config on-chain to match BuxBoosterGame production settings.
 *
 * Changes:
 * - max_bet_bps: 1000 (10%) → 10 (0.1%)  — matches EVM MAX_BET_BPS
 * - min_bet: 1000 lamports → 10_000_000 (0.01 SOL / 0.01 BUX in 9-decimal tokens)
 * - multipliers: [0;9] → [102, 105, 113, 132, 198, 396, 792, 1584, 3168]
 *   (stored as BPS/100: e.g. 1.98x = 19800 BPS → stored as 198)
 *
 * Usage: npx ts-node scripts/update-game-config.ts
 *
 * Requires: keypairs/mint-authority.json (program authority)
 */

import {
  Connection,
  Keypair,
  PublicKey,
  Transaction,
  TransactionInstruction,
  sendAndConfirmTransaction,
} from "@solana/web3.js";
import * as fs from "fs";
import * as path from "path";

const RPC_URL =
  process.env.SOLANA_RPC_URL ||
  "https://summer-sleek-shape.solana-devnet.quiknode.pro/92b7f51caa76f2981879528aee40a3e8e58cac60/";

const BANKROLL_PROGRAM_ID = new PublicKey(
  process.env.BANKROLL_PROGRAM_ID ||
    "49up2uzZANpjTC3sgggbZazdHBii2vY9mVK3vk5dT2tm"
);

const KEYPAIR_DIR = path.join(__dirname, "..", "keypairs");

function derivePDA(seed: string): [PublicKey, number] {
  return PublicKey.findProgramAddressSync(
    [Buffer.from(seed)],
    BANKROLL_PROGRAM_ID
  );
}

const [GAME_REGISTRY] = derivePDA("game_registry");

// update_config discriminator from IDL
const UPDATE_CONFIG_DISC = Buffer.from([29, 158, 252, 191, 10, 83, 219, 99]);

/**
 * Encode an Option<T> for Borsh serialization.
 * None = [0], Some(value) = [1, ...value_bytes]
 */
function encodeOptionPubkey(value: PublicKey | null): Buffer {
  if (value === null) return Buffer.from([0]);
  return Buffer.concat([Buffer.from([1]), value.toBuffer()]);
}

function encodeOptionI64(value: bigint | null): Buffer {
  if (value === null) return Buffer.from([0]);
  const buf = Buffer.alloc(9);
  buf[0] = 1;
  buf.writeBigInt64LE(value, 1);
  return buf;
}

function encodeOptionU16(value: number | null): Buffer {
  if (value === null) return Buffer.from([0]);
  const buf = Buffer.alloc(3);
  buf[0] = 1;
  buf.writeUInt16LE(value, 1);
  return buf;
}

function encodeOptionU64(value: bigint | null): Buffer {
  if (value === null) return Buffer.from([0]);
  const buf = Buffer.alloc(9);
  buf[0] = 1;
  buf.writeBigUInt64LE(value, 1);
  return buf;
}

function encodeOptionBool(value: boolean | null): Buffer {
  if (value === null) return Buffer.from([0]);
  return Buffer.from([1, value ? 1 : 0]);
}

function encodeOptionMultipliers(value: number[] | null): Buffer {
  if (value === null) return Buffer.from([0]);
  // Option Some prefix + 9 x u16 LE = 1 + 18 = 19 bytes
  const buf = Buffer.alloc(19);
  buf[0] = 1;
  for (let i = 0; i < 9; i++) {
    buf.writeUInt16LE(value[i], 1 + i * 2);
  }
  return buf;
}

async function main() {
  const connection = new Connection(RPC_URL, "confirmed");

  const authorityPath = path.join(KEYPAIR_DIR, "mint-authority.json");
  if (!fs.existsSync(authorityPath)) {
    console.error("ERROR: keypairs/mint-authority.json not found");
    process.exit(1);
  }
  const authority = Keypair.fromSecretKey(
    Uint8Array.from(JSON.parse(fs.readFileSync(authorityPath, "utf-8")))
  );

  console.log("=== Update Coin Flip Game Config ===");
  console.log("Authority:", authority.publicKey.toBase58());
  console.log("Game Registry:", GAME_REGISTRY.toBase58());
  console.log();

  // New values matching BuxBoosterGame production settings:
  const GAME_ID = 1; // Coin Flip
  const NEW_MAX_BET_BPS = 100; // 1% of vault
  const NEW_MIN_BET = BigInt(10_000_000); // 0.01 SOL/BUX (9 decimals)

  // Multipliers stored as BPS / 100 (fits in u16)
  // EVM: [10200, 10500, 11300, 13200, 19800, 39600, 79200, 158400, 316800]
  // Stored: [102, 105, 113, 132, 198, 396, 792, 1584, 3168]
  const MULTIPLIERS = [102, 105, 113, 132, 198, 396, 792, 1584, 3168];

  console.log("Changes:");
  console.log(`  game_id: ${GAME_ID}`);
  console.log(`  max_bet_bps: 1000 → ${NEW_MAX_BET_BPS} (0.1% of vault)`);
  console.log(`  min_bet: 1000 → ${NEW_MIN_BET} (0.01 tokens)`);
  console.log(`  multipliers: ${MULTIPLIERS.map((m, i) => `idx${i}=${m} (${m*100/10000}x)`).join(", ")}`);
  console.log();

  // Build instruction data:
  // discriminator(8) + option<pubkey> + option<i64> + option<u16> + option<u16>
  //                   + option<u64> + option<bool> + option<u64> + option<u16> + option<u16>
  //                   + option<[u16; 9]>
  const data = Buffer.concat([
    UPDATE_CONFIG_DISC,
    encodeOptionPubkey(null),            // new_settler: None
    encodeOptionI64(null),               // new_bet_timeout: None
    encodeOptionU16(null),               // new_referral_bps: None
    encodeOptionU16(null),               // new_tier2_referral_bps: None
    encodeOptionU64(BigInt(GAME_ID)),    // game_id: Some(1)
    encodeOptionBool(null),              // new_game_active: None
    encodeOptionU64(NEW_MIN_BET),        // new_game_min_bet: Some(10_000_000)
    encodeOptionU16(NEW_MAX_BET_BPS),    // new_game_max_bet_bps: Some(10)
    encodeOptionU16(null),               // new_game_fee_bps: None
    encodeOptionMultipliers(MULTIPLIERS), // new_game_multipliers: Some([102, 105, ...])
  ]);

  const ix = new TransactionInstruction({
    programId: BANKROLL_PROGRAM_ID,
    keys: [
      { pubkey: authority.publicKey, isSigner: true, isWritable: false },
      { pubkey: GAME_REGISTRY, isSigner: false, isWritable: true },
    ],
    data,
  });

  const tx = new Transaction().add(ix);
  tx.feePayer = authority.publicKey;

  try {
    const sig = await sendAndConfirmTransaction(connection, tx, [authority], {
      commitment: "confirmed",
    });
    console.log("Game config updated successfully!");
    console.log("   Signature:", sig);
  } catch (err: any) {
    console.error("Failed to update config:", err.message);
    if (err.logs) {
      console.error("Logs:", err.logs.join("\n"));
    }
    process.exit(1);
  }
}

main().catch(console.error);
