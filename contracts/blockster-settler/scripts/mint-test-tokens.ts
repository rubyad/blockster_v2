/**
 * Mint test BUX tokens to a wallet on devnet
 *
 * Usage: npm run mint-test -- <wallet_address> [amount]
 *   wallet_address: Solana public key (base58)
 *   amount: BUX to mint (default: 10000, in human-readable units)
 *
 * Example: npm run mint-test -- 7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU 5000
 */

import { Connection, Keypair, PublicKey, LAMPORTS_PER_SOL } from "@solana/web3.js";
import {
  getMint,
  getOrCreateAssociatedTokenAccount,
  mintTo,
  getAccount,
} from "@solana/spl-token";
import * as fs from "fs";
import * as path from "path";

const KEYPAIR_DIR = path.join(__dirname, "..", "keypairs");

async function main() {
  // Parse args
  const walletArg = process.argv[2];
  const amountArg = process.argv[3] || "10000";

  if (!walletArg) {
    console.error("Usage: npm run mint-test -- <wallet_address> [amount]");
    console.error("  wallet_address: Solana public key (base58)");
    console.error("  amount: BUX to mint (default: 10000)");
    process.exit(1);
  }

  // Load config
  const configPath = path.join(KEYPAIR_DIR, "token-config.json");
  if (!fs.existsSync(configPath)) {
    console.error("token-config.json not found. Run create-token first.");
    process.exit(1);
  }
  const config = JSON.parse(fs.readFileSync(configPath, "utf-8"));

  // Load mint authority
  const mintAuthorityPath = path.join(KEYPAIR_DIR, "mint-authority.json");
  const mintAuthority = Keypair.fromSecretKey(
    Uint8Array.from(JSON.parse(fs.readFileSync(mintAuthorityPath, "utf-8")))
  );

  // Parse inputs
  const recipientPubkey = new PublicKey(walletArg);
  const buxMint = new PublicKey(config.buxMint);
  const decimals = config.decimals as number;
  const humanAmount = parseFloat(amountArg);
  const rawAmount = BigInt(Math.floor(humanAmount * 10 ** decimals));

  // Connect
  const connection = new Connection(config.rpcUrl, "confirmed");

  console.log("=".repeat(60));
  console.log("BUX Test Mint");
  console.log(`Network: ${config.network}`);
  console.log(`BUX Mint: ${buxMint.toBase58()}`);
  console.log(`Recipient: ${recipientPubkey.toBase58()}`);
  console.log(`Amount: ${humanAmount} BUX (${rawAmount.toString()} raw)`);
  console.log("=".repeat(60));

  // Get or create ATA for recipient
  console.log("\nGetting/creating Associated Token Account...");
  const ata = await getOrCreateAssociatedTokenAccount(
    connection,
    mintAuthority, // payer
    buxMint,
    recipientPubkey
  );
  console.log(`ATA: ${ata.address.toBase58()}`);
  console.log(`Current balance: ${ata.amount.toString()} raw`);

  // Mint
  console.log(`\nMinting ${humanAmount} BUX...`);
  const sig = await mintTo(
    connection,
    mintAuthority, // payer
    buxMint,
    ata.address,
    mintAuthority, // mint authority
    rawAmount
  );
  console.log(`Mint tx: ${sig}`);

  // Verify
  const updatedAta = await getAccount(connection, ata.address);
  const newBalance = Number(updatedAta.amount) / 10 ** decimals;
  console.log(`\nNew balance: ${newBalance} BUX`);

  // Check total supply
  const mintInfo = await getMint(connection, buxMint);
  const totalSupply = Number(mintInfo.supply) / 10 ** decimals;
  console.log(`Total BUX supply: ${totalSupply}`);

  const explorerUrl =
    config.network === "devnet"
      ? `https://explorer.solana.com/tx/${sig}?cluster=devnet`
      : `https://explorer.solana.com/tx/${sig}`;
  console.log(`\nExplorer: ${explorerUrl}`);
}

main().catch((err) => {
  console.error("Error:", err);
  process.exit(1);
});
