/**
 * Update on-chain token metadata URIs after Irys upload.
 * Calls Metaplex UpdateMetadataAccountV2 directly (update authority = deployer).
 *
 * Same pattern as FateSwap's update-lp-metadata.js.
 *
 * Usage:
 *   npx ts-node scripts/update-token-metadata.ts
 *
 * Before running, fill in the Irys gateway URIs below after uploading:
 *   1. Upload logo PNGs to Irys
 *   2. Create metadata JSON files with the logo URLs
 *   3. Upload metadata JSON files to Irys
 *   4. Paste the metadata JSON Irys URIs below
 */

import {
  Connection,
  Keypair,
  PublicKey,
  TransactionMessage,
  VersionedTransaction,
  TransactionInstruction,
} from "@solana/web3.js";
import * as fs from "fs";
import * as path from "path";

// -------------------------------------------------------------------
// Configuration
// -------------------------------------------------------------------

const RPC_URL =
  process.env.SOLANA_RPC_URL ||
  "https://summer-sleek-shape.solana-devnet.quiknode.pro/92b7f51caa76f2981879528aee40a3e8e58cac60/";

const TOKEN_METADATA_PROGRAM_ID = new PublicKey(
  "metaqbxxUerdq28cj1RbAWkYQm3ybzjb6a8bt518x1s"
);

const BANKROLL_PROGRAM_ID = new PublicKey(
  "49up2uzZANpjTC3sgggbZazdHBii2vY9mVK3vk5dT2tm"
);

const KEYPAIR_DIR = path.join(__dirname, "..", "keypairs");

// =====================================================================
// FILL THESE IN after uploading metadata JSON to Irys
// =====================================================================
const IRYS_URIS = {
  bux: "", // e.g. "https://gateway.irys.xyz/abc123..."
  solLp: "", // e.g. "https://gateway.irys.xyz/def456..."
  buxLp: "", // e.g. "https://gateway.irys.xyz/ghi789..."
};

// Token details (must match what was set in create-token-metadata.ts)
const TOKENS = [
  {
    label: "BUX",
    name: "BUX",
    symbol: "BUX",
    mint: new PublicKey("7CuRyw2YkqQhUUFbw6CCnoedHWT8tK2c9UzZQYDGmxVX"),
    uri: IRYS_URIS.bux,
  },
  {
    label: "SOL-LP",
    name: "Blockster SOL LP",
    symbol: "SOL-LP",
    mint: PublicKey.findProgramAddressSync(
      [Buffer.from("bsol_mint")],
      BANKROLL_PROGRAM_ID
    )[0],
    uri: IRYS_URIS.solLp,
  },
  {
    label: "BUX-LP",
    name: "Blockster BUX LP",
    symbol: "BUX-LP",
    mint: PublicKey.findProgramAddressSync(
      [Buffer.from("bbux_mint")],
      BANKROLL_PROGRAM_ID
    )[0],
    uri: IRYS_URIS.buxLp,
  },
];

// -------------------------------------------------------------------
// Helpers
// -------------------------------------------------------------------

function loadKeypair(filepath: string): Keypair {
  const resolved = filepath.replace("~", process.env.HOME || "");
  const raw = JSON.parse(fs.readFileSync(resolved, "utf-8"));
  return Keypair.fromSecretKey(Uint8Array.from(raw));
}

function borshString(parts: Buffer[], s: string): void {
  const bytes = Buffer.from(s, "utf-8");
  const len = Buffer.alloc(4);
  len.writeUInt32LE(bytes.length);
  parts.push(len, bytes);
}

function deriveMetadataPDA(mint: PublicKey): PublicKey {
  const [pda] = PublicKey.findProgramAddressSync(
    [
      Buffer.from("metadata"),
      TOKEN_METADATA_PROGRAM_ID.toBuffer(),
      mint.toBuffer(),
    ],
    TOKEN_METADATA_PROGRAM_ID
  );
  return pda;
}

/**
 * Build UpdateMetadataAccountV2 instruction (discriminator 15).
 * Exact same pattern as FateSwap's update-lp-metadata.js.
 */
function buildUpdateMetadataIx(
  metadataPDA: PublicKey,
  updateAuthority: PublicKey,
  name: string,
  symbol: string,
  uri: string
): TransactionInstruction {
  const parts: Buffer[] = [];

  // Discriminator: 15 (UpdateMetadataAccountV2)
  parts.push(Buffer.from([15]));

  // data: Option<DataV2> = Some
  parts.push(Buffer.from([1]));

  // DataV2:
  borshString(parts, name);
  borshString(parts, symbol);
  borshString(parts, uri);
  // seller_fee_basis_points: u16 = 0
  const feeBps = Buffer.alloc(2);
  feeBps.writeUInt16LE(0);
  parts.push(feeBps);
  // creators: None, collection: None, uses: None
  parts.push(Buffer.from([0, 0, 0]));

  // update_authority: Option<Pubkey> = None (keep current)
  parts.push(Buffer.from([0]));

  // primary_sale_happened: Option<bool> = None
  parts.push(Buffer.from([0]));

  // is_mutable: Option<bool> = Some(true)
  parts.push(Buffer.from([1, 1]));

  const data = Buffer.concat(parts);

  return new TransactionInstruction({
    programId: TOKEN_METADATA_PROGRAM_ID,
    keys: [
      { pubkey: metadataPDA, isSigner: false, isWritable: true },
      { pubkey: updateAuthority, isSigner: true, isWritable: false },
    ],
    data,
  });
}

// -------------------------------------------------------------------
// Main
// -------------------------------------------------------------------

async function main() {
  console.log("=".repeat(60));
  console.log("Update Token Metadata URIs (Metaplex UpdateMetadataAccountV2)");
  console.log("=".repeat(60));

  const connection = new Connection(RPC_URL, "confirmed");
  const authority = loadKeypair(path.join(KEYPAIR_DIR, "mint-authority.json"));
  console.log(`Update Authority: ${authority.publicKey.toBase58()}`);

  let updated = 0;

  for (const token of TOKENS) {
    if (!token.uri) {
      console.log(`\n[${token.label}] Skipping — no Irys URI set`);
      continue;
    }

    const metadataPDA = deriveMetadataPDA(token.mint);

    console.log(`\n[${token.label}] Updating metadata...`);
    console.log(`  Mint:         ${token.mint.toBase58()}`);
    console.log(`  Metadata PDA: ${metadataPDA.toBase58()}`);
    console.log(`  URI:          ${token.uri}`);

    const ix = buildUpdateMetadataIx(
      metadataPDA,
      authority.publicKey,
      token.name,
      token.symbol,
      token.uri
    );

    const { blockhash } = await connection.getLatestBlockhash("confirmed");
    const message = new TransactionMessage({
      payerKey: authority.publicKey,
      recentBlockhash: blockhash,
      instructions: [ix],
    }).compileToV0Message();

    const tx = new VersionedTransaction(message);
    tx.sign([authority]);

    const sig = await connection.sendTransaction(tx, { skipPreflight: false });
    const confirmation = await connection.confirmTransaction(sig, "confirmed");

    if (confirmation.value.err) {
      console.error(`  ✗ Failed:`, confirmation.value.err);
    } else {
      console.log(`  ✓ Updated: ${sig}`);
      updated++;
    }
  }

  console.log("\n" + "=".repeat(60));
  console.log(`Updated ${updated}/${TOKENS.filter((t) => t.uri).length} tokens`);

  if (TOKENS.some((t) => !t.uri)) {
    console.log("\nTokens with empty URIs were skipped.");
    console.log("Fill in IRYS_URIS in this script after uploading to Irys.");
  }
  console.log("=".repeat(60));
}

main().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
