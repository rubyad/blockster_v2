/**
 * Debug deployment - test what size works
 */

const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");
require("dotenv").config();

const RPC_URL = "https://rpc.roguechain.io/rpc";
const CHAIN_ID = 560013;

async function main() {
  const provider = new ethers.JsonRpcProvider(RPC_URL, CHAIN_ID);
  const wallet = new ethers.Wallet(process.env.DEPLOYER_PRIVATE_KEY, provider);

  console.log("Deploying with account:", wallet.address);
  const balance = await provider.getBalance(wallet.address);
  console.log("Account balance:", ethers.formatEther(balance), "ROGUE\n");

  // Load BuxBoosterGameTransparent artifact
  const artifactPath = path.join(__dirname, "../artifacts/contracts/BuxBoosterGameTransparent.sol/BuxBoosterGameTransparent.json");
  const artifact = JSON.parse(fs.readFileSync(artifactPath, "utf8"));

  const bytecode = artifact.bytecode;
  console.log("Full bytecode length:", bytecode.length, "chars");
  console.log("Full bytecode size:", (bytecode.length - 2) / 2, "bytes");

  // Build the full transaction to see its size
  const nonce = await provider.getTransactionCount(wallet.address);
  console.log("Current nonce:", nonce);

  const BuxContract = new ethers.ContractFactory(artifact.abi, artifact.bytecode, wallet);

  // Get deploy transaction to examine it
  const deployTx = await BuxContract.getDeployTransaction({
    gasLimit: 10000000,
    maxFeePerGas: 1000000000000n,
    maxPriorityFeePerGas: 1000000000n,
    nonce: nonce
  });

  console.log("\nDeploy transaction:");
  console.log("  data length:", deployTx.data.length, "chars");
  console.log("  data size:", (deployTx.data.length - 2) / 2, "bytes");

  // Sign the transaction to see the full signed payload
  const signedTx = await wallet.signTransaction(deployTx);
  console.log("  signed tx length:", signedTx.length, "chars");
  console.log("  signed tx size:", (signedTx.length - 2) / 2, "bytes");

  // The JSON-RPC payload would be even larger
  const jsonPayload = JSON.stringify({
    jsonrpc: "2.0",
    id: 1,
    method: "eth_sendRawTransaction",
    params: [signedTx]
  });
  console.log("  JSON-RPC payload size:", jsonPayload.length, "bytes");
  console.log("  JSON-RPC payload size:", (jsonPayload.length / 1024).toFixed(2), "KB");

  // Try sending it
  console.log("\nAttempting to broadcast...");
  try {
    const response = await provider.broadcastTransaction(signedTx);
    console.log("✓ Transaction sent! Hash:", response.hash);
    console.log("  Waiting for confirmation...");
    const receipt = await response.wait();
    console.log("✓ Confirmed in block:", receipt.blockNumber);
    console.log("✓ Contract address:", receipt.contractAddress);
  } catch (e) {
    console.log("✗ Failed:", e.message);
    if (e.info) {
      console.log("Response status:", e.info.responseStatus);
    }
  }
}

main().catch(console.error);
