/**
 * Test deployment with minimal contract
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
  console.log("Account balance:", ethers.formatEther(balance), "ROGUE");

  // Load test contract artifact
  const artifactPath = path.join(__dirname, "../artifacts/contracts/TestContract.sol/TestContract.json");
  const artifact = JSON.parse(fs.readFileSync(artifactPath, "utf8"));

  console.log("\nBytecode length:", artifact.bytecode.length, "chars");
  console.log("Bytecode size:", (artifact.bytecode.length - 2) / 2, "bytes");

  const TestContract = new ethers.ContractFactory(artifact.abi, artifact.bytecode, wallet);

  console.log("\nDeploying TestContract...");
  try {
    const contract = await TestContract.deploy({
      gasLimit: 500000,
      maxFeePerGas: 1000000000000n,  // 1000 gwei
      maxPriorityFeePerGas: 1000000000n  // 1 gwei tip
    });

    console.log("Tx hash:", contract.deploymentTransaction().hash);
    console.log("Waiting for confirmation...");
    await contract.waitForDeployment();

    const address = await contract.getAddress();
    console.log("✓ Contract deployed at:", address);

    // Verify
    const value = await contract.value();
    console.log("✓ Verified value:", value.toString());
  } catch (e) {
    console.log("✗ Failed:", e.message);
    if (e.info) {
      console.log("Response:", e.info.responseBody?.substring(0, 500));
    }
  }
}

main().catch(console.error);
