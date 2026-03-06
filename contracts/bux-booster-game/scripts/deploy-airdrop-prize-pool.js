/**
 * Deploy AirdropPrizePool as UUPS proxy to Arbitrum One
 *
 * Usage:
 *   npx hardhat run scripts/deploy-airdrop-prize-pool.js --network arbitrumOne
 *
 * Prerequisites:
 *   - DEPLOYER_PRIVATE_KEY in .env
 *   - Deployer has ETH on Arbitrum for gas
 */

const { ethers, upgrades } = require("hardhat");

const USDT_ADDRESS = "0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9";
const VAULT_ADMIN = "0xBd16aB578D55374061A78Bb6Cca8CB4ddFaBd4C9";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying AirdropPrizePool with account:", deployer.address);
  console.log("Account balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "ETH");

  // Deploy UUPS proxy
  console.log("\nDeploying AirdropPrizePool (UUPS proxy)...");
  const AirdropPrizePool = await ethers.getContractFactory("AirdropPrizePool");

  const pool = await upgrades.deployProxy(AirdropPrizePool, [USDT_ADDRESS], {
    initializer: "initialize",
    kind: "uups",
    unsafeAllow: ["constructor", "state-variable-assignment", "state-variable-immutable"]
  });

  await pool.waitForDeployment();
  const proxyAddress = await pool.getAddress();
  console.log("AirdropPrizePool proxy deployed at:", proxyAddress);

  // Get implementation address
  const implAddress = await upgrades.erc1967.getImplementationAddress(proxyAddress);
  console.log("Implementation address:", implAddress);

  // Verify initialization
  console.log("\nVerifying initialization...");
  const usdtAddr = await pool.usdt();
  const roundId = await pool.roundId();
  console.log("USDT token:", usdtAddr);
  console.log("Round ID:", roundId.toString());
  console.log("Owner:", await pool.owner());

  if (usdtAddr.toLowerCase() !== USDT_ADDRESS.toLowerCase()) {
    throw new Error("USDT address mismatch!");
  }

  // Transfer ownership to vault admin
  console.log("\nTransferring ownership to vault admin:", VAULT_ADMIN);
  const tx = await pool.transferOwnership(VAULT_ADMIN);
  await tx.wait();
  console.log("Ownership transferred. New owner:", await pool.owner());

  // Summary
  console.log("\n========================================");
  console.log("AirdropPrizePool Deployment Summary");
  console.log("========================================");
  console.log("Network:        Arbitrum One (42161)");
  console.log("Proxy:         ", proxyAddress);
  console.log("Implementation:", implAddress);
  console.log("USDT Token:    ", USDT_ADDRESS);
  console.log("Owner:         ", VAULT_ADMIN);
  console.log("Round ID:      ", roundId.toString());
  console.log("========================================");
  console.log("\nVerify on Arbiscan:");
  console.log(`  https://arbiscan.io/address/${proxyAddress}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
