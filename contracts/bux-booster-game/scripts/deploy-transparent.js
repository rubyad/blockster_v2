/**
 * Deploy script for BuxBoosterGameTransparent (Transparent Proxy version)
 */

const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");
require("dotenv").config();

const RPC_URL = "https://rpc.roguechain.io/rpc";
const CHAIN_ID = 560013;

async function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function retryWithBackoff(fn, maxRetries = 10, baseDelay = 3000) {
  for (let i = 0; i < maxRetries; i++) {
    try {
      return await fn();
    } catch (error) {
      if (i === maxRetries - 1) throw error;
      const delay = baseDelay * Math.pow(1.5, i);
      console.log(`  Attempt ${i + 1} failed: ${error.message}`);
      console.log(`  Retrying in ${delay / 1000}s...`);
      await sleep(delay);
    }
  }
}

// ERC20 ABI for mint and approve
const ERC20_ABI = [
  "function mint(address to, uint256 amount) external",
  "function approve(address spender, uint256 amount) external returns (bool)",
  "function balanceOf(address account) external view returns (uint256)"
];

async function main() {
  // Setup provider and wallet
  const provider = new ethers.JsonRpcProvider(RPC_URL, CHAIN_ID);
  const wallet = new ethers.Wallet(process.env.DEPLOYER_PRIVATE_KEY, provider);

  console.log("Deploying with account:", wallet.address);
  const balance = await provider.getBalance(wallet.address);
  console.log("Account balance:", ethers.formatEther(balance), "ROGUE");

  // Settler Address (set after deployment)
  const settlerAddress = "0x4BBe1C90a0A6974d8d9A598d081309D8Ff27bb81";

  console.log("\n=== Configuration ===");
  console.log("Settler:", settlerAddress);

  // Load contract artifact
  const artifactPath = path.join(__dirname, "../artifacts/contracts/BuxBoosterGameTransparent.sol/BuxBoosterGameTransparent.json");
  const artifact = JSON.parse(fs.readFileSync(artifactPath, "utf8"));

  const BuxBoosterGame = new ethers.ContractFactory(artifact.abi, artifact.bytecode, wallet);

  // Deploy implementation with explicit gas limit
  console.log("\nDeploying BuxBoosterGameTransparent implementation...");
  const implementation = await retryWithBackoff(async () => {
    const nonce = await provider.getTransactionCount(wallet.address);
    console.log(`  Using nonce: ${nonce}`);

    // Deploy with sufficient gas limit for 11KB contract
    const impl = await BuxBoosterGame.deploy({
      gasLimit: 3000000
    });

    console.log(`  Tx hash: ${impl.deploymentTransaction().hash}`);
    console.log("  Waiting for confirmation...");
    await impl.waitForDeployment();

    const address = await impl.getAddress();
    console.log(`  Deployed at: ${address}`);

    return impl;
  });

  const implementationAddress = await implementation.getAddress();
  console.log("Implementation deployed at:", implementationAddress);

  // Initialize the contract
  console.log("\nInitializing contract...");
  await retryWithBackoff(async () => {
    const tx = await implementation.initialize({
      gasLimit: 500000
    });
    console.log(`  Tx hash: ${tx.hash}`);
    await tx.wait();
    console.log("  Initialized successfully");
  });

  // Set settler address
  console.log("\nSetting settler address...");
  await retryWithBackoff(async () => {
    const tx = await implementation.setSettler(settlerAddress, {
      gasLimit: 100000
    });
    console.log(`  Tx hash: ${tx.hash}`);
    await tx.wait();
    console.log("  Settler set successfully");
  });

  // Verify initialization
  console.log("\nVerifying initialization...");
  const owner = await implementation.owner();
  const settler = await implementation.settler();
  console.log("Owner:", owner);
  console.log("Settler:", settler);

  // Tokens to configure
  const tokens = [
    { name: "BUX", address: "0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8" },
    { name: "moonBUX", address: "0x08F12025c1cFC4813F21c2325b124F6B6b5cfDF5" },
    { name: "neoBUX", address: "0x423656448374003C2cfEaFF88D5F64fb3A76487C" },
    { name: "rogueBUX", address: "0x56d271b1C1DCF597aA3ee454bCCb265d4Dee47b3" },
    { name: "flareBUX", address: "0xd27EcA9bc2401E8CEf92a14F5Ee9847508EDdaC8" },
    { name: "nftBUX", address: "0x9853e3Abea96985d55E9c6963afbAf1B0C9e49ED" },
    { name: "nolchaBUX", address: "0x4cE5C87FAbE273B58cb4Ef913aDEa5eE15AFb642" },
    { name: "solBUX", address: "0x92434779E281468611237d18AdE20A4f7F29DB38" },
    { name: "spaceBUX", address: "0xAcaCa77FbC674728088f41f6d978F0194cf3d55A" },
    { name: "tronBUX", address: "0x98eDb381281FA02b494FEd76f0D9F3AEFb2Db665" },
    { name: "tranBUX", address: "0xcDdE88C8bacB37Fc669fa6DECE92E3d8FE672d96" }
  ];

  const houseBalance = ethers.parseEther("1000000"); // 1M tokens

  console.log("\nConfiguring tokens, minting, and depositing house balance...");

  for (const token of tokens) {
    console.log(`\n  Processing ${token.name}...`);

    // 1. Configure token
    await retryWithBackoff(async () => {
      const tx = await implementation.configureToken(token.address, true, {
        gasLimit: 100000
      });
      await tx.wait();
      console.log(`    Configured as enabled`);
    });

    // 2. Mint tokens
    const tokenContract = new ethers.Contract(token.address, ERC20_ABI, wallet);
    try {
      await retryWithBackoff(async () => {
        const tx = await tokenContract.mint(wallet.address, houseBalance, {
          gasLimit: 100000
        });
        await tx.wait();
        console.log(`    Minted 1,000,000 tokens`);
      });
    } catch (error) {
      console.log(`    Note: Could not mint: ${error.message}`);
      continue;
    }

    // 3. Approve
    await retryWithBackoff(async () => {
      const tx = await tokenContract.approve(implementationAddress, houseBalance, {
        gasLimit: 100000
      });
      await tx.wait();
      console.log(`    Approved game contract`);
    });

    // 4. Deposit
    await retryWithBackoff(async () => {
      const tx = await implementation.depositHouseBalance(token.address, houseBalance, {
        gasLimit: 200000
      });
      await tx.wait();
      console.log(`    Deposited 1,000,000 as house balance`);
    });
  }

  console.log("\n=== Deployment Complete ===");
  console.log("Contract Address:", implementationAddress);
  console.log("Owner:", wallet.address);
  console.log("Settler:", settlerAddress);
  console.log("Treasury:", treasuryAddress);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
