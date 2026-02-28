const { ethers } = require("hardhat");

/**
 * Upgrade AirdropVault proxy to V2 implementation.
 * V2 adds a public deposit() function so users can deposit directly from their smart wallet.
 *
 * Steps:
 * 1. Deploy AirdropVaultV2 implementation
 * 2. Call proxy.upgradeToAndCall(v2Impl, "0x") from vault admin (owner)
 * 3. Call proxy.initializeV2() to mark reinitializer(2)
 *
 * Usage:
 *   npx hardhat run scripts/upgrade-airdrop-vault-v2.js --network roguechain
 */
async function main() {
  const PROXY_ADDRESS = "0x27049F96f8a00203fEC5f871e6DAa6Ee4c244F6c";

  const [deployer] = await ethers.getSigners();
  console.log("Upgrading AirdropVault with account:", deployer.address);

  const nonce = await deployer.getNonce();
  console.log("Current nonce:", nonce);

  // 1. Deploy V2 implementation
  console.log("\nDeploying AirdropVaultV2 implementation...");
  const AirdropVaultV2 = await ethers.getContractFactory("AirdropVaultV2");
  const v2Impl = await AirdropVaultV2.deploy({
    gasLimit: 5000000,
    nonce: nonce,
    maxFeePerGas: 2000000000000n,  // 2000 gwei
    maxPriorityFeePerGas: 0n
  });
  await v2Impl.waitForDeployment();
  const v2Address = await v2Impl.getAddress();
  console.log("V2 implementation deployed at:", v2Address);

  // 2. Upgrade proxy to V2
  console.log("\nUpgrading proxy to V2...");
  const proxy = await ethers.getContractAt("AirdropVault", PROXY_ADDRESS);

  try {
    const upgradeTx = await proxy.upgradeToAndCall(v2Address, "0x", {
      gasLimit: 5000000,
      nonce: nonce + 1,
      maxFeePerGas: 2000000000000n,
      maxPriorityFeePerGas: 0n
    });
    console.log("Upgrade tx submitted:", upgradeTx.hash);
    await upgradeTx.wait();
    console.log("Upgrade complete!");
  } catch (error) {
    console.error("Upgrade failed:", error.message);
    process.exit(1);
  }

  // 3. Initialize V2
  console.log("\nInitializing V2...");
  const upgraded = await ethers.getContractAt("AirdropVaultV2", PROXY_ADDRESS);

  try {
    const initTx = await upgraded.initializeV2({
      gasLimit: 500000,
      nonce: nonce + 2,
      maxFeePerGas: 2000000000000n,
      maxPriorityFeePerGas: 0n
    });
    console.log("InitializeV2 tx submitted:", initTx.hash);
    await initTx.wait();
    console.log("V2 initialized!");
  } catch (error) {
    console.error("InitializeV2 failed:", error.message);
    process.exit(1);
  }

  // Verify
  console.log("\nVerification:");
  console.log("  Version:", await upgraded.version());
  console.log("  Owner:", await upgraded.owner());
  console.log("  RoundId:", (await upgraded.roundId()).toString());
  console.log("\nAirdropVault V2 upgrade complete!");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
