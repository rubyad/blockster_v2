/**
 * Deploy AirdropVault as UUPS proxy to Rogue Chain Mainnet
 *
 * Usage:
 *   npx hardhat run scripts/deploy-airdrop-vault.js --network rogueMainnet
 *
 * Prerequisites:
 *   - DEPLOYER_PRIVATE_KEY in .env
 *   - Deployer has ROGUE for gas
 */

const { ethers, upgrades } = require("hardhat");

const BUX_TOKEN = "0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8";
const VAULT_ADMIN = "0xBd16aB578D55374061A78Bb6Cca8CB4ddFaBd4C9";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying AirdropVault with account:", deployer.address);
  console.log("Account balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "ROGUE");

  // Deploy UUPS proxy
  console.log("\nDeploying AirdropVault (UUPS proxy)...");
  const AirdropVault = await ethers.getContractFactory("AirdropVault");

  const vault = await upgrades.deployProxy(AirdropVault, [BUX_TOKEN], {
    initializer: "initialize",
    kind: "uups",
    unsafeAllow: ["constructor", "state-variable-assignment", "state-variable-immutable"],
    txOverrides: { gasLimit: 5000000, gasPrice: 1000000000000n }
  });

  await vault.waitForDeployment();
  const proxyAddress = await vault.getAddress();
  console.log("AirdropVault proxy deployed at:", proxyAddress);

  // Get implementation address
  const implAddress = await upgrades.erc1967.getImplementationAddress(proxyAddress);
  console.log("Implementation address:", implAddress);

  // Verify initialization
  console.log("\nVerifying initialization...");
  const buxToken = await vault.buxToken();
  console.log("BUX token:", buxToken);
  console.log("Owner:", await vault.owner());

  if (buxToken.toLowerCase() !== BUX_TOKEN.toLowerCase()) {
    throw new Error("BUX token address mismatch!");
  }

  // Transfer ownership to vault admin
  console.log("\nTransferring ownership to vault admin:", VAULT_ADMIN);
  const tx = await vault.transferOwnership(VAULT_ADMIN);
  await tx.wait();
  console.log("Ownership transferred. New owner:", await vault.owner());

  // Summary
  console.log("\n========================================");
  console.log("AirdropVault Deployment Summary");
  console.log("========================================");
  console.log("Network:        Rogue Chain (560013)");
  console.log("Proxy:         ", proxyAddress);
  console.log("Implementation:", implAddress);
  console.log("BUX Token:     ", BUX_TOKEN);
  console.log("Owner:         ", VAULT_ADMIN);
  console.log("========================================");
  console.log("\nVerify on RogueScan:");
  console.log(`  https://roguescan.io/address/${proxyAddress}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
