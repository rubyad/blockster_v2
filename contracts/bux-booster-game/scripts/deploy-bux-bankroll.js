/**
 * Deploy BUXBankroll — direct ethers.js deployment (bypasses Hardhat HTTP provider)
 *
 * Deploys:
 *   1. BUXBankroll implementation contract
 *   2. ERC1967Proxy pointing to implementation with initialize(BUX_TOKEN) calldata
 *
 * Usage:
 *   node scripts/deploy-bux-bankroll.js
 *
 * Prerequisites:
 *   - DEPLOYER_PRIVATE_KEY set in .env
 *   - Deployer has ROGUE for gas
 *   - npx hardhat compile (artifacts must exist)
 */

const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");
require("dotenv").config();

const RPC_URL = "https://rpc.roguechain.io/rpc";
const CHAIN_ID = 560013;
const BUX_TOKEN = "0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8";

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function retryWithBackoff(fn, label, maxRetries = 10, baseDelay = 3000) {
  for (let i = 0; i < maxRetries; i++) {
    try {
      return await fn();
    } catch (error) {
      const msg = error.message || "";
      const isRpcError = msg.includes("500") ||
        msg.includes("Internal Server Error") ||
        msg.includes("ETIMEDOUT") ||
        msg.includes("ECONNRESET") ||
        msg.includes("ECONNREFUSED") ||
        msg.includes("bad response");

      if (!isRpcError || i === maxRetries - 1) throw error;

      const delay = baseDelay * Math.pow(1.5, i);
      console.log(`  [${label}] Attempt ${i + 1} failed: ${msg.slice(0, 100)}`);
      console.log(`  Retrying in ${(delay / 1000).toFixed(1)}s...`);
      await sleep(delay);
    }
  }
}

async function main() {
  if (!process.env.DEPLOYER_PRIVATE_KEY) {
    console.error("ERROR: DEPLOYER_PRIVATE_KEY not set in .env");
    process.exit(1);
  }

  const provider = new ethers.JsonRpcProvider(RPC_URL, CHAIN_ID);
  const wallet = new ethers.Wallet(process.env.DEPLOYER_PRIVATE_KEY, provider);

  console.log("=== BUXBankroll Deployment (Direct) ===");
  console.log("Deployer:", wallet.address);
  const balance = await provider.getBalance(wallet.address);
  console.log("Balance:", ethers.formatEther(balance), "ROGUE");
  console.log("BUX Token:", BUX_TOKEN);
  console.log("Chain ID:", CHAIN_ID);

  // Load artifacts
  const implArtifactPath = path.join(__dirname, "../artifacts/contracts/BUXBankroll.sol/BUXBankroll.json");
  const proxyArtifactPath = path.join(__dirname,
    "../node_modules/@openzeppelin/upgrades-core/artifacts/@openzeppelin/contracts-v5/proxy/ERC1967/ERC1967Proxy.sol/ERC1967Proxy.json");

  if (!fs.existsSync(implArtifactPath)) {
    console.error("ERROR: BUXBankroll artifact not found. Run 'npx hardhat compile' first.");
    process.exit(1);
  }

  const implArtifact = JSON.parse(fs.readFileSync(implArtifactPath, "utf8"));
  const proxyArtifact = JSON.parse(fs.readFileSync(proxyArtifactPath, "utf8"));

  // --- Step 1: Deploy Implementation ---
  console.log("\n--- Step 1: Deploy BUXBankroll Implementation ---");

  const ImplFactory = new ethers.ContractFactory(implArtifact.abi, implArtifact.bytecode, wallet);

  const impl = await retryWithBackoff(async () => {
    const nonce = await provider.getTransactionCount(wallet.address);
    console.log("  Nonce:", nonce);

    const contract = await ImplFactory.deploy({ gasLimit: 5000000, nonce });
    console.log("  Tx hash:", contract.deploymentTransaction().hash);
    console.log("  Waiting for confirmation...");
    await contract.waitForDeployment();
    return contract;
  }, "impl");

  const implAddress = await impl.getAddress();
  console.log("  Implementation deployed at:", implAddress);

  // --- Step 2: Deploy ERC1967Proxy ---
  console.log("\n--- Step 2: Deploy ERC1967Proxy ---");

  // Encode initialize(BUX_TOKEN) calldata
  const iface = new ethers.Interface(implArtifact.abi);
  const initData = iface.encodeFunctionData("initialize", [BUX_TOKEN]);
  console.log("  Init calldata:", initData.slice(0, 20) + "...");

  const ProxyFactory = new ethers.ContractFactory(proxyArtifact.abi, proxyArtifact.bytecode, wallet);

  const proxy = await retryWithBackoff(async () => {
    const nonce = await provider.getTransactionCount(wallet.address);
    console.log("  Nonce:", nonce);

    const contract = await ProxyFactory.deploy(implAddress, initData, { gasLimit: 1000000, nonce });
    console.log("  Tx hash:", contract.deploymentTransaction().hash);
    console.log("  Waiting for confirmation...");
    await contract.waitForDeployment();
    return contract;
  }, "proxy");

  const proxyAddress = await proxy.getAddress();
  console.log("  Proxy deployed at:", proxyAddress);

  // --- Step 3: Quick Verification ---
  console.log("\n--- Step 3: Quick Verification ---");
  const bankroll = new ethers.Contract(proxyAddress, implArtifact.abi, provider);

  const owner = await retryWithBackoff(() => bankroll.owner(), "owner");
  const buxToken = await retryWithBackoff(() => bankroll.buxToken(), "buxToken");
  const lpName = await retryWithBackoff(() => bankroll.name(), "name");
  const lpSymbol = await retryWithBackoff(() => bankroll.symbol(), "symbol");
  const lpPrice = await retryWithBackoff(() => bankroll.getLPPrice(), "lpPrice");

  console.log("  Owner:", owner);
  console.log("  BUX Token:", buxToken);
  console.log("  LP Name:", lpName);
  console.log("  LP Symbol:", lpSymbol);
  console.log("  LP Price:", lpPrice.toString(), "(1e18 = 1:1)");

  // --- Summary ---
  console.log("\n========================================");
  console.log("=== BUXBankroll Deployment Complete ===");
  console.log("========================================");
  console.log("Proxy address:          ", proxyAddress);
  console.log("Implementation address: ", implAddress);
  console.log("Owner:                  ", owner);
  console.log("BUX Token:              ", buxToken);
  console.log("");
  console.log("NEXT STEPS:");
  console.log("1. Run verify script:  BUX_BANKROLL_PROXY=" + proxyAddress + " npx hardhat run scripts/verify-bux-bankroll.js --network rogueMainnet");
  console.log("2. Run setup script:   BUX_BANKROLL_PROXY=" + proxyAddress + " npx hardhat run scripts/setup-bux-bankroll.js --network rogueMainnet");
  console.log("");
  console.log("SAVE THESE ADDRESSES:");
  console.log("  BUX_BANKROLL_PROXY=" + proxyAddress);
  console.log("  BUX_BANKROLL_IMPL=" + implAddress);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
