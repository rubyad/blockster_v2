/**
 * Create BUX SPL Token on Solana Devnet
 *
 * This script:
 * 1. Loads or generates a mint authority keypair
 * 2. Creates the BUX token mint (9 decimals, no freeze authority)
 * 3. Uploads token metadata via Metaplex Token Metadata Standard
 *
 * Usage: npm run create-token
 *
 * Prerequisites:
 * - Mint authority keypair at keypairs/mint-authority.json (or it will be generated)
 * - Mint authority must be funded with SOL on devnet
 */

import {
  Connection,
  Keypair,
  clusterApiUrl,
  LAMPORTS_PER_SOL,
  PublicKey,
} from "@solana/web3.js";
import {
  createMint,
  getMint,
  getOrCreateAssociatedTokenAccount,
  mintTo,
} from "@solana/spl-token";
import { createUmi } from "@metaplex-foundation/umi-bundle-defaults";
import {
  createMetadataAccountV3,
  findMetadataPda,
} from "@metaplex-foundation/mpl-token-metadata";
import {
  publicKey as umiPublicKey,
  signerIdentity,
  createSignerFromKeypair as umiCreateSignerFromKeypair,
} from "@metaplex-foundation/umi";
import * as fs from "fs";
import * as path from "path";

// -------------------------------------------------------------------
// Configuration
// -------------------------------------------------------------------

const RPC_URL =
  process.env.SOLANA_RPC_URL ||
  "https://summer-sleek-shape.solana-devnet.quiknode.pro/92b7f51caa76f2981879528aee40a3e8e58cac60/";
const NETWORK = process.env.SOLANA_NETWORK || "devnet";
const KEYPAIR_DIR = path.join(__dirname, "..", "keypairs");
const MINT_AUTHORITY_PATH = path.join(KEYPAIR_DIR, "mint-authority.json");
const MINT_KEYPAIR_PATH = path.join(KEYPAIR_DIR, "bux-mint.json");
const OUTPUT_PATH = path.join(KEYPAIR_DIR, "token-config.json");

const TOKEN_CONFIG = {
  name: "BUX",
  symbol: "BUX",
  decimals: 9,
  uri: "https://ik.imagekit.io/blockster/bux-metadata.json", // Metadata JSON URI
  image: "https://ik.imagekit.io/blockster/blockster-icon.png",
};

// -------------------------------------------------------------------
// Helpers
// -------------------------------------------------------------------

function loadOrCreateKeypair(filepath: string, label: string): Keypair {
  if (fs.existsSync(filepath)) {
    const raw = JSON.parse(fs.readFileSync(filepath, "utf-8"));
    const kp = Keypair.fromSecretKey(Uint8Array.from(raw));
    console.log(`Loaded ${label}: ${kp.publicKey.toBase58()}`);
    return kp;
  }
  const kp = Keypair.generate();
  fs.writeFileSync(filepath, JSON.stringify(Array.from(kp.secretKey)));
  console.log(`Generated new ${label}: ${kp.publicKey.toBase58()}`);
  console.log(`  Saved to: ${filepath}`);
  return kp;
}

async function ensureFunded(
  connection: Connection,
  pubkey: PublicKey,
  label: string
): Promise<void> {
  const balance = await connection.getBalance(pubkey);
  const solBalance = balance / LAMPORTS_PER_SOL;
  console.log(`${label} balance: ${solBalance} SOL`);

  if (balance < 0.05 * LAMPORTS_PER_SOL) {
    if (NETWORK === "devnet") {
      console.log(`Requesting airdrop for ${label}...`);
      const sig = await connection.requestAirdrop(
        pubkey,
        2 * LAMPORTS_PER_SOL
      );
      await connection.confirmTransaction(sig, "confirmed");
      const newBalance = await connection.getBalance(pubkey);
      console.log(
        `${label} balance after airdrop: ${newBalance / LAMPORTS_PER_SOL} SOL`
      );
    } else {
      throw new Error(
        `${label} has insufficient SOL (${solBalance}). Fund it before running on ${NETWORK}.`
      );
    }
  }
}

// -------------------------------------------------------------------
// Main
// -------------------------------------------------------------------

async function main() {
  console.log("=".repeat(60));
  console.log("BUX SPL Token Creator");
  console.log(`Network: ${NETWORK}`);
  console.log(`RPC: ${RPC_URL}`);
  console.log("=".repeat(60));

  // 1. Connect
  const connection = new Connection(RPC_URL, "confirmed");
  const slot = await connection.getSlot();
  console.log(`Connected to ${NETWORK} (slot: ${slot})`);

  // 2. Load keypairs
  const mintAuthority = loadOrCreateKeypair(
    MINT_AUTHORITY_PATH,
    "Mint Authority"
  );
  const mintKeypair = loadOrCreateKeypair(MINT_KEYPAIR_PATH, "BUX Mint");

  // 3. Ensure funded
  await ensureFunded(connection, mintAuthority.publicKey, "Mint Authority");

  // 4. Check if mint already exists
  try {
    const existingMint = await getMint(connection, mintKeypair.publicKey);
    console.log("\nBUX mint already exists!");
    console.log(`  Mint: ${mintKeypair.publicKey.toBase58()}`);
    console.log(`  Decimals: ${existingMint.decimals}`);
    console.log(`  Supply: ${existingMint.supply.toString()}`);
    console.log(
      `  Mint Authority: ${existingMint.mintAuthority?.toBase58() || "none"}`
    );
    console.log(
      `  Freeze Authority: ${existingMint.freezeAuthority?.toBase58() || "none"}`
    );

    // Skip to metadata
    await createTokenMetadata(connection, mintAuthority, mintKeypair);
    saveConfig(mintKeypair.publicKey, mintAuthority.publicKey);
    return;
  } catch {
    // Mint doesn't exist yet — create it
  }

  // 5. Create mint
  console.log("\nCreating BUX token mint...");
  const mint = await createMint(
    connection,
    mintAuthority, // payer
    mintAuthority.publicKey, // mint authority
    null, // freeze authority (none — tokens freely transferable)
    TOKEN_CONFIG.decimals, // 9 decimals
    mintKeypair // use our pre-generated keypair
  );
  console.log(`BUX mint created: ${mint.toBase58()}`);

  // 6. Create metadata
  await createTokenMetadata(connection, mintAuthority, mintKeypair);

  // 7. Verify
  const mintInfo = await getMint(connection, mint);
  console.log("\nMint verification:");
  console.log(`  Address: ${mint.toBase58()}`);
  console.log(`  Decimals: ${mintInfo.decimals}`);
  console.log(`  Supply: ${mintInfo.supply.toString()}`);
  console.log(
    `  Mint Authority: ${mintInfo.mintAuthority?.toBase58() || "none"}`
  );
  console.log(
    `  Freeze Authority: ${mintInfo.freezeAuthority?.toBase58() || "none"}`
  );

  // 8. Save config
  saveConfig(mint, mintAuthority.publicKey);

  console.log("\n" + "=".repeat(60));
  console.log("BUX token creation complete!");
  console.log("=".repeat(60));
}

async function createTokenMetadata(
  connection: Connection,
  mintAuthority: Keypair,
  mintKeypair: Keypair
): Promise<void> {
  console.log("\nCreating token metadata...");

  const umi = createUmi(RPC_URL);

  // Convert web3.js keypair to umi signer
  const umiKeypair = umi.eddsa.createKeypairFromSecretKey(
    mintAuthority.secretKey
  );
  const umiSigner = umiCreateSignerFromKeypair(umi, umiKeypair);
  umi.use(signerIdentity(umiSigner));

  const mintPubkey = umiPublicKey(mintKeypair.publicKey.toBase58());
  const metadataPda = findMetadataPda(umi, { mint: mintPubkey });

  try {
    await createMetadataAccountV3(umi, {
      metadata: metadataPda,
      mint: mintPubkey,
      mintAuthority: umiSigner,
      payer: umiSigner,
      updateAuthority: umiSigner.publicKey,
      data: {
        name: TOKEN_CONFIG.name,
        symbol: TOKEN_CONFIG.symbol,
        uri: TOKEN_CONFIG.uri,
        sellerFeeBasisPoints: 0,
        creators: null,
        collection: null,
        uses: null,
      },
      isMutable: true,
      collectionDetails: null,
    }).sendAndConfirm(umi);

    console.log("Token metadata created successfully");
    console.log(`  Name: ${TOKEN_CONFIG.name}`);
    console.log(`  Symbol: ${TOKEN_CONFIG.symbol}`);
    console.log(`  URI: ${TOKEN_CONFIG.uri}`);
  } catch (err: any) {
    if (err.message?.includes("already in use")) {
      console.log("Token metadata already exists — skipping");
    } else {
      console.error("Failed to create metadata:", err.message);
      console.log("Token mint is still valid — metadata can be added later");
    }
  }
}

function saveConfig(mint: PublicKey, mintAuthority: PublicKey): void {
  const config = {
    network: NETWORK,
    rpcUrl: RPC_URL,
    buxMint: mint.toBase58(),
    mintAuthority: mintAuthority.toBase58(),
    decimals: TOKEN_CONFIG.decimals,
    createdAt: new Date().toISOString(),
  };

  fs.writeFileSync(OUTPUT_PATH, JSON.stringify(config, null, 2));
  console.log(`\nConfig saved to: ${OUTPUT_PATH}`);
}

main().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
