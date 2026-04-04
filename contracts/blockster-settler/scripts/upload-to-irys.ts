/**
 * Upload token logos and metadata JSON to Irys (Arweave).
 * Same pattern as FateSwap fSOL token metadata.
 *
 * Steps:
 *   1. Upload logo PNGs → get Irys gateway URLs
 *   2. Update metadata JSON files with logo URLs
 *   3. Upload metadata JSON files → get Irys gateway URLs
 *   4. Print the URIs to paste into update-token-metadata.ts
 *
 * Usage: npx ts-node scripts/upload-to-irys.ts
 *
 * Prerequisites:
 *   - Token logo PNGs at priv/static/images/{bux,sol-lp,bux-lp}-token-256.png
 *   - Metadata JSON files at priv/static/{bux,sol-lp,bux-lp}-metadata.json
 *   - Funded keypair at keypairs/mint-authority.json (pays for Irys uploads)
 */

import Irys from "@irys/sdk";
import * as fs from "fs";
import * as path from "path";

// -------------------------------------------------------------------
// Configuration
// -------------------------------------------------------------------

const KEYPAIR_PATH = path.join(__dirname, "..", "keypairs", "mint-authority.json");
const PROJECT_ROOT = path.resolve(__dirname, "..", "..", "..");

const TOKENS = [
  {
    label: "BUX",
    logoPath: path.join(PROJECT_ROOT, "priv/static/images/bux-token-256.png"),
    metadataPath: path.join(PROJECT_ROOT, "priv/static/bux-metadata.json"),
  },
  {
    label: "SOL-LP",
    logoPath: path.join(PROJECT_ROOT, "priv/static/images/sol-lp-token-256.png"),
    metadataPath: path.join(PROJECT_ROOT, "priv/static/sol-lp-metadata.json"),
  },
  {
    label: "BUX-LP",
    logoPath: path.join(PROJECT_ROOT, "priv/static/images/bux-lp-token-256.png"),
    metadataPath: path.join(PROJECT_ROOT, "priv/static/bux-lp-metadata.json"),
  },
];

// -------------------------------------------------------------------
// Main
// -------------------------------------------------------------------

async function main() {
  console.log("=".repeat(60));
  console.log("Upload Token Logos & Metadata to Irys (Arweave)");
  console.log("=".repeat(60));

  // Load keypair
  const keypairData = JSON.parse(fs.readFileSync(KEYPAIR_PATH, "utf-8"));
  const secretKey = Uint8Array.from(keypairData);

  // Initialize Irys — use node2 for uploads (works with devnet SOL for payment)
  const irys = new Irys({
    url: "https://node2.irys.xyz",
    token: "solana",
    key: secretKey,
    config: {
      providerUrl: "https://api.devnet.solana.com",
    },
  });

  const balance = await irys.getLoadedBalance();
  console.log(`Irys balance: ${irys.utils.fromAtomic(balance).toString()} SOL`);

  // Fund Irys if balance is low (0.01 SOL should be enough for metadata)
  const minBalance = 0.005;
  if (parseFloat(irys.utils.fromAtomic(balance).toString()) < minBalance) {
    console.log(`Funding Irys with 0.01 SOL...`);
    await irys.fund(irys.utils.toAtomic(0.01));
    console.log("Funded!");
  }

  const results: Record<string, { logoUri: string; metadataUri: string }> = {};

  for (const token of TOKENS) {
    console.log(`\n--- ${token.label} ---`);

    // Step 1: Upload logo
    if (!fs.existsSync(token.logoPath)) {
      console.error(`  ✗ Logo not found: ${token.logoPath}`);
      continue;
    }

    console.log(`  Uploading logo: ${path.basename(token.logoPath)}`);
    const logoReceipt = await irys.uploadFile(token.logoPath, {
      tags: [
        { name: "Content-Type", value: "image/png" },
        { name: "App-Name", value: "Blockster" },
        { name: "Token", value: token.label },
      ],
    });
    const logoUri = `https://gateway.irys.xyz/${logoReceipt.id}`;
    console.log(`  ✓ Logo uploaded: ${logoUri}`);

    // Step 2: Update metadata JSON with logo URL
    const metadata = JSON.parse(fs.readFileSync(token.metadataPath, "utf-8"));
    metadata.image = logoUri;
    fs.writeFileSync(token.metadataPath, JSON.stringify(metadata, null, 2) + "\n");
    console.log(`  ✓ Updated ${path.basename(token.metadataPath)} with logo URL`);

    // Step 3: Upload metadata JSON
    console.log(`  Uploading metadata: ${path.basename(token.metadataPath)}`);
    const metadataReceipt = await irys.uploadFile(token.metadataPath, {
      tags: [
        { name: "Content-Type", value: "application/json" },
        { name: "App-Name", value: "Blockster" },
        { name: "Token", value: token.label },
      ],
    });
    const metadataUri = `https://gateway.irys.xyz/${metadataReceipt.id}`;
    console.log(`  ✓ Metadata uploaded: ${metadataUri}`);

    results[token.label] = { logoUri, metadataUri };
  }

  // Print summary for update-token-metadata.ts
  console.log("\n" + "=".repeat(60));
  console.log("All uploads complete! Paste these into update-token-metadata.ts:\n");
  console.log("const IRYS_URIS = {");
  if (results["BUX"]) console.log(`  bux: "${results["BUX"].metadataUri}",`);
  if (results["SOL-LP"]) console.log(`  solLp: "${results["SOL-LP"].metadataUri}",`);
  if (results["BUX-LP"]) console.log(`  buxLp: "${results["BUX-LP"].metadataUri}",`);
  console.log("};");
  console.log("\nThen run: npx ts-node scripts/update-token-metadata.ts");
  console.log("=".repeat(60));
}

main().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
