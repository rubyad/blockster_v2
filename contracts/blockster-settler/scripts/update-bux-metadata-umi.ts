/**
 * One-shot: update the BUX SPL token's Metaplex metadata URI on mainnet.
 *
 * Why this exists: `update-token-metadata.ts` hand-rolls the v2 borsh
 * payload, which mismatches metadata accounts created by `createMetadataAccountV3`
 * (umi). This script uses umi's `updateV1` so the encoding is right.
 */
import { createUmi } from "@metaplex-foundation/umi-bundle-defaults";
import {
  updateV1,
  fetchMetadataFromSeeds,
} from "@metaplex-foundation/mpl-token-metadata";
import {
  publicKey as umiPublicKey,
  signerIdentity,
  createSignerFromKeypair as umiCreateSignerFromKeypair,
  some,
  none,
} from "@metaplex-foundation/umi";
import * as fs from "fs";
import * as path from "path";

const RPC_URL = process.env.SOLANA_RPC_URL;
if (!RPC_URL) {
  console.error("Set SOLANA_RPC_URL to the mainnet RPC.");
  process.exit(1);
}

const BUX_MINT = "7CuRyw2YkqQhUUFbw6CCnoedHWT8tK2c9UzZQYDGmxVX";
const KEYPAIR_PATH = path.join(__dirname, "..", "keypairs", "mint-authority.json");

async function main() {
  const umi = createUmi(RPC_URL!);
  const raw = JSON.parse(fs.readFileSync(KEYPAIR_PATH, "utf-8"));
  const kp = umi.eddsa.createKeypairFromSecretKey(Uint8Array.from(raw));
  const signer = umiCreateSignerFromKeypair(umi, kp);
  umi.use(signerIdentity(signer));

  const mint = umiPublicKey(BUX_MINT);
  const current = await fetchMetadataFromSeeds(umi, { mint });
  console.log("Current name:", current.name);
  console.log("Current symbol:", current.symbol);
  console.log("Current uri:", current.uri);

  const newUri = "https://blockster.com/bux-metadata.json";

  await updateV1(umi, {
    mint,
    authority: signer,
    data: some({
      name: "BUX",
      symbol: "BUX",
      uri: newUri,
      sellerFeeBasisPoints: 0,
      creators: none(),
    }),
  }).sendAndConfirm(umi);

  const after = await fetchMetadataFromSeeds(umi, { mint });
  console.log("\nUpdated successfully:");
  console.log("  name:", after.name);
  console.log("  symbol:", after.symbol);
  console.log("  uri:", after.uri);
}

main().catch((err) => {
  console.error("Fatal:", err);
  process.exit(1);
});
