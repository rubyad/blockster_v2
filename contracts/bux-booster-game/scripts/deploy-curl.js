/**
 * Deploy using curl to bypass ethers.js and see raw errors
 */

const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");
const { execSync } = require("child_process");
require("dotenv").config();

const RPC_URL = "https://rpc.roguechain.io/rpc";
const CHAIN_ID = 560013;

async function main() {
  const provider = new ethers.JsonRpcProvider(RPC_URL, CHAIN_ID);
  const wallet = new ethers.Wallet(process.env.DEPLOYER_PRIVATE_KEY, provider);

  console.log("Deploying with account:", wallet.address);

  // Load artifact
  const artifactPath = path.join(__dirname, "../artifacts/contracts/BuxBoosterGameTransparent.sol/BuxBoosterGameTransparent.json");
  const artifact = JSON.parse(fs.readFileSync(artifactPath, "utf8"));

  const nonce = await provider.getTransactionCount(wallet.address);
  console.log("Current nonce:", nonce);

  const BuxContract = new ethers.ContractFactory(artifact.abi, artifact.bytecode, wallet);

  // Get deploy transaction
  const deployTx = await BuxContract.getDeployTransaction({
    gasLimit: 10000000,
    maxFeePerGas: 1000000000000n,
    maxPriorityFeePerGas: 1000000000n,
    nonce: nonce
  });

  // Sign it
  const signedTx = await wallet.signTransaction(deployTx);
  console.log("Signed tx length:", signedTx.length);

  // Create JSON-RPC payload
  const payload = JSON.stringify({
    jsonrpc: "2.0",
    id: 1,
    method: "eth_sendRawTransaction",
    params: [signedTx]
  });

  // Save to temp file
  const tmpFile = "/tmp/deploy_payload.json";
  fs.writeFileSync(tmpFile, payload);
  console.log("Payload saved to:", tmpFile);
  console.log("Payload size:", payload.length, "bytes");

  // Try curl
  console.log("\nSending via curl...");
  try {
    const result = execSync(`curl -X POST -H "Content-Type: application/json" -d @${tmpFile} ${RPC_URL} -v 2>&1`, {
      encoding: "utf8",
      maxBuffer: 50 * 1024 * 1024
    });
    console.log("Result:", result);
  } catch (e) {
    console.log("Curl error:", e.message);
    if (e.stdout) console.log("stdout:", e.stdout);
    if (e.stderr) console.log("stderr:", e.stderr);
  }
}

main().catch(console.error);
