import { Connection, Keypair, PublicKey } from "@solana/web3.js";
import * as fs from "fs";
import * as path from "path";

// -------------------------------------------------------------------
// Environment
// -------------------------------------------------------------------

export const SOLANA_RPC_URL =
  process.env.SOLANA_RPC_URL ||
  "https://summer-sleek-shape.solana-devnet.quiknode.pro/92b7f51caa76f2981879528aee40a3e8e58cac60/";

export const SOLANA_NETWORK = process.env.SOLANA_NETWORK || "devnet";
export const PORT = parseInt(process.env.PORT || "3000", 10);
export const API_SECRET = process.env.SETTLER_API_SECRET || "dev-secret";

// -------------------------------------------------------------------
// Program IDs
// -------------------------------------------------------------------

export const BUX_MINT_ADDRESS = new PublicKey(
  process.env.BUX_MINT_ADDRESS ||
    "7CuRyw2YkqQhUUFbw6CCnoedHWT8tK2c9UzZQYDGmxVX"
);

export const BANKROLL_PROGRAM_ID = new PublicKey(
  process.env.BANKROLL_PROGRAM_ID ||
    "49up2uzZANpjTC3sgggbZazdHBii2vY9mVK3vk5dT2tm"
);

export const AIRDROP_PROGRAM_ID = new PublicKey(
  process.env.AIRDROP_PROGRAM_ID ||
    "wxiuLBuqxem5ETmGDndiW8MMkxKXp5jVsNCqdZgmjaG"
);

// -------------------------------------------------------------------
// Keypairs
// -------------------------------------------------------------------

function loadKeypair(envVar: string, fallbackPath: string): Keypair {
  // Try env var first (JSON array of secret key bytes)
  if (process.env[envVar]) {
    const raw = JSON.parse(process.env[envVar]!);
    return Keypair.fromSecretKey(Uint8Array.from(raw));
  }

  // Fall back to file
  const resolved = path.resolve(fallbackPath);
  if (fs.existsSync(resolved)) {
    const raw = JSON.parse(fs.readFileSync(resolved, "utf-8"));
    return Keypair.fromSecretKey(Uint8Array.from(raw));
  }

  throw new Error(
    `Keypair not found: set ${envVar} env var or provide ${fallbackPath}`
  );
}

export const MINT_AUTHORITY = loadKeypair(
  "MINT_AUTHORITY_KEYPAIR",
  path.join(__dirname, "..", "keypairs", "mint-authority.json")
);

// -------------------------------------------------------------------
// Shop payment intents
// -------------------------------------------------------------------

// HKDF seed for deterministic ephemeral keypair derivation per-order.
// Rotating this invalidates every outstanding unswept intent — only rotate
// after confirming all prior intents have been swept.
export const PAYMENT_INTENT_SEED =
  process.env.PAYMENT_INTENT_SEED || "dev-payment-intent-seed-do-not-use-in-prod";

// Treasury address that receives swept SOL from funded intents. In dev this
// falls back to the mint authority pubkey so the settler has somewhere valid
// to send test funds to.
export const SOL_TREASURY_ADDRESS = new PublicKey(
  process.env.SOL_TREASURY_ADDRESS || MINT_AUTHORITY.publicKey.toBase58()
);

// Keypair that pays fees for the sweep transaction. Defaults to the mint
// authority — swept amounts arrive at the treasury, minus ~5000 lamports of
// tx fee paid by this keypair.
export const SWEEP_FEE_PAYER = MINT_AUTHORITY;

// -------------------------------------------------------------------
// Connection
// -------------------------------------------------------------------

export const connection = new Connection(SOLANA_RPC_URL, "confirmed");

// -------------------------------------------------------------------
// Constants
// -------------------------------------------------------------------

export const BUX_DECIMALS = 9;
export const LAMPORTS_PER_BUX = 10 ** BUX_DECIMALS;
