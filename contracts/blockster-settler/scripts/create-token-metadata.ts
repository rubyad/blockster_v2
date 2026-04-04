/**
 * Create Token Metadata for BUX, SOL-LP, and BUX-LP on Solana Devnet
 *
 * Step 1: Create on-chain metadata with empty URI (this script)
 * Step 2: Upload logos + metadata JSON to Irys/Arweave (manual)
 * Step 3: Update on-chain metadata with Irys URI (update-token-metadata.ts)
 *
 * - BUX: Direct Metaplex call (we own the mint authority keypair)
 * - SOL-LP/BUX-LP: Via bankroll program CPI (mint authority is PDA)
 *
 * Usage:
 *   npx ts-node scripts/create-token-metadata.ts              # All three
 *   npx ts-node scripts/create-token-metadata.ts --bux-only   # Just BUX
 *   npx ts-node scripts/create-token-metadata.ts --lp-only    # Just LP tokens
 */

import {
  Connection,
  Keypair,
  PublicKey,
  SystemProgram,
  Transaction,
  TransactionInstruction,
  sendAndConfirmTransaction,
  SYSVAR_RENT_PUBKEY,
} from "@solana/web3.js";
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
import * as crypto from "crypto";
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

const BUX_MINT = new PublicKey("7CuRyw2YkqQhUUFbw6CCnoedHWT8tK2c9UzZQYDGmxVX");

const TOKEN_METADATA_PROGRAM_ID = new PublicKey(
  "metaqbxxUerdq28cj1RbAWkYQm3ybzjb6a8bt518x1s"
);

const KEYPAIR_DIR = path.join(__dirname, "..", "keypairs");

// On-chain metadata — URI left empty, updated after Irys upload
const TOKENS = {
  bux: { name: "BUX", symbol: "BUX", uri: "" },
  solLp: { name: "Blockster SOL LP", symbol: "SOL-LP", uri: "" },
  buxLp: { name: "Blockster BUX LP", symbol: "BUX-LP", uri: "" },
};

// -------------------------------------------------------------------
// PDA helpers
// -------------------------------------------------------------------

function deriveBankrollPDA(seed: string): [PublicKey, number] {
  return PublicKey.findProgramAddressSync(
    [Buffer.from(seed)],
    BANKROLL_PROGRAM_ID
  );
}

const [BSOL_MINT] = deriveBankrollPDA("bsol_mint");
const [BSOL_MINT_AUTHORITY] = deriveBankrollPDA("bsol_mint_authority");
const [BBUX_MINT] = deriveBankrollPDA("bbux_mint");
const [BBUX_MINT_AUTHORITY] = deriveBankrollPDA("bbux_mint_authority");
const [GAME_REGISTRY] = deriveBankrollPDA("game_registry");

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

// -------------------------------------------------------------------
// Helpers
// -------------------------------------------------------------------

function loadKeypair(filepath: string): Keypair {
  const raw = JSON.parse(fs.readFileSync(filepath, "utf-8"));
  return Keypair.fromSecretKey(Uint8Array.from(raw));
}

function anchorDiscriminator(name: string): Buffer {
  return crypto
    .createHash("sha256")
    .update(`global:${name}`)
    .digest()
    .subarray(0, 8);
}

function borshString(parts: Buffer[], s: string): void {
  const bytes = Buffer.from(s, "utf-8");
  const len = Buffer.alloc(4);
  len.writeUInt32LE(bytes.length);
  parts.push(len, bytes);
}

// -------------------------------------------------------------------
// BUX Metadata (direct Metaplex — we own the mint authority)
// -------------------------------------------------------------------

async function createBuxMetadata(
  connection: Connection,
  mintAuthority: Keypair
): Promise<void> {
  console.log("\n[BUX] Creating on-chain metadata...");
  console.log(`  Mint: ${BUX_MINT.toBase58()}`);

  const umi = createUmi(RPC_URL);
  const umiKeypair = umi.eddsa.createKeypairFromSecretKey(
    mintAuthority.secretKey
  );
  const umiSigner = umiCreateSignerFromKeypair(umi, umiKeypair);
  umi.use(signerIdentity(umiSigner));

  const mintPubkey = umiPublicKey(BUX_MINT.toBase58());
  const metadataPda = findMetadataPda(umi, { mint: mintPubkey });

  try {
    await createMetadataAccountV3(umi, {
      metadata: metadataPda,
      mint: mintPubkey,
      mintAuthority: umiSigner,
      payer: umiSigner,
      updateAuthority: umiSigner.publicKey,
      data: {
        name: TOKENS.bux.name,
        symbol: TOKENS.bux.symbol,
        uri: TOKENS.bux.uri,
        sellerFeeBasisPoints: 0,
        creators: null,
        collection: null,
        uses: null,
      },
      isMutable: true,
      collectionDetails: null,
    }).sendAndConfirm(umi);

    console.log(`  ✓ BUX metadata created (name=${TOKENS.bux.name}, symbol=${TOKENS.bux.symbol})`);
    console.log(`  URI empty — update after Irys upload with update-token-metadata.ts`);
  } catch (err: any) {
    if (err.message?.includes("already in use")) {
      console.log("  ⊘ BUX metadata already exists — use update-token-metadata.ts to set URI");
    } else {
      console.error("  ✗ Failed:", err.message);
      throw err;
    }
  }
}

// -------------------------------------------------------------------
// LP Token Metadata (via bankroll program CPI)
// -------------------------------------------------------------------

function buildCreateLpMetadataIx(
  authority: PublicKey,
  vaultType: number, // 0=sol, 1=bux
  mint: PublicKey,
  mintAuthority: PublicKey,
  name: string,
  symbol: string,
  uri: string
): TransactionInstruction {
  const metadataPDA = deriveMetadataPDA(mint);
  const disc = anchorDiscriminator("create_lp_metadata");

  const parts: Buffer[] = [disc];
  parts.push(Buffer.from([vaultType])); // VaultType enum
  borshString(parts, name);
  borshString(parts, symbol);
  borshString(parts, uri);
  const data = Buffer.concat(parts);

  return new TransactionInstruction({
    keys: [
      { pubkey: authority, isSigner: true, isWritable: true },
      { pubkey: GAME_REGISTRY, isSigner: false, isWritable: false },
      { pubkey: mint, isSigner: false, isWritable: false },
      { pubkey: mintAuthority, isSigner: false, isWritable: false },
      { pubkey: metadataPDA, isSigner: false, isWritable: true },
      { pubkey: TOKEN_METADATA_PROGRAM_ID, isSigner: false, isWritable: false },
      { pubkey: SystemProgram.programId, isSigner: false, isWritable: false },
      { pubkey: SYSVAR_RENT_PUBKEY, isSigner: false, isWritable: false },
    ],
    programId: BANKROLL_PROGRAM_ID,
    data,
  });
}

async function createLpMetadata(
  connection: Connection,
  authority: Keypair,
  vaultType: "sol" | "bux"
): Promise<void> {
  const isSol = vaultType === "sol";
  const label = isSol ? "SOL-LP" : "BUX-LP";
  const meta = isSol ? TOKENS.solLp : TOKENS.buxLp;
  const mint = isSol ? BSOL_MINT : BBUX_MINT;
  const mintAuth = isSol ? BSOL_MINT_AUTHORITY : BBUX_MINT_AUTHORITY;

  console.log(`\n[${label}] Creating on-chain metadata via bankroll program...`);
  console.log(`  Mint: ${mint.toBase58()}`);

  const ix = buildCreateLpMetadataIx(
    authority.publicKey,
    isSol ? 0 : 1,
    mint,
    mintAuth,
    meta.name,
    meta.symbol,
    meta.uri
  );

  const tx = new Transaction().add(ix);

  try {
    const sig = await sendAndConfirmTransaction(connection, tx, [authority], {
      commitment: "confirmed",
    });
    console.log(`  ✓ ${label} metadata created: ${sig}`);
    console.log(`  Name: ${meta.name}, Symbol: ${meta.symbol}`);
    console.log(`  URI empty — update after Irys upload with update-token-metadata.ts`);
  } catch (err: any) {
    if (
      err.message?.includes("already in use") ||
      err.logs?.some((l: string) => l.includes("already in use"))
    ) {
      console.log(`  ⊘ ${label} metadata already exists — use update-token-metadata.ts to set URI`);
    } else {
      console.error(`  ✗ ${label} failed:`, err.message);
      if (err.logs) console.error("  Logs:", err.logs.join("\n  "));
      throw err;
    }
  }
}

// -------------------------------------------------------------------
// Main
// -------------------------------------------------------------------

async function main() {
  const buxOnly = process.argv.includes("--bux-only");
  const lpOnly = process.argv.includes("--lp-only");

  console.log("=".repeat(60));
  console.log("Step 1: Create On-Chain Token Metadata (empty URI)");
  console.log("=".repeat(60));

  const connection = new Connection(RPC_URL, "confirmed");
  const authority = loadKeypair(path.join(KEYPAIR_DIR, "mint-authority.json"));
  console.log(`Authority: ${authority.publicKey.toBase58()}`);

  const balance = await connection.getBalance(authority.publicKey);
  console.log(`Balance: ${(balance / 1e9).toFixed(4)} SOL`);

  console.log("\nToken mints:");
  console.log(`  BUX:    ${BUX_MINT.toBase58()}`);
  console.log(`  SOL-LP: ${BSOL_MINT.toBase58()}`);
  console.log(`  BUX-LP: ${BBUX_MINT.toBase58()}`);

  if (!lpOnly) await createBuxMetadata(connection, authority);
  if (!buxOnly) {
    await createLpMetadata(connection, authority, "sol");
    await createLpMetadata(connection, authority, "bux");
  }

  console.log("\n" + "=".repeat(60));
  console.log("Done! Next steps:");
  console.log("  1. Upload token logos to Irys: npx ts-node scripts/upload-to-irys.ts");
  console.log("  2. Upload metadata JSON to Irys (with logo URLs filled in)");
  console.log("  3. Update on-chain URI: npx ts-node scripts/update-token-metadata.ts");
  console.log("=".repeat(60));
}

main().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
