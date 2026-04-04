const { ethers, upgrades } = require("hardhat");

async function main() {
  const PROXY_ADDRESS = "0x97b6d6A8f2c6AF6e6fb40f8d36d60DF2fFE4f17B";

  const [deployer] = await ethers.getSigners();
  console.log("Upgrading with account:", deployer.address);

  console.log("\nUpgrading BuxBoosterGame to V2...");
  console.log("Proxy Address:", PROXY_ADDRESS);

  const BuxBoosterGameV2 = await ethers.getContractFactory("BuxBoosterGame");

  // Upgrade without calling any initializer (V2 already initialized)
  // Force redeploy to ensure new implementation is deployed
  const upgraded = await upgrades.upgradeProxy(PROXY_ADDRESS, BuxBoosterGameV2, {
    kind: "uups",
    redeployImplementation: "always"
  });

  await upgraded.waitForDeployment();

  const newImplementation = await upgrades.erc1967.getImplementationAddress(PROXY_ADDRESS);

  console.log("\n=== Upgrade Complete ===");
  console.log("Proxy Address (unchanged):", PROXY_ADDRESS);
  console.log("New Implementation Address:", newImplementation);

  // Verify arrays are now populated
  console.log("\n=== Verifying Array Initialization ===");
  console.log("FLIP_COUNTS[4] (should be 1):", await upgraded.FLIP_COUNTS(4));
  console.log("MULTIPLIERS[4] (should be 19800):", await upgraded.MULTIPLIERS(4));
  console.log("GAME_MODES[4] (should be 0):", await upgraded.GAME_MODES(4));

  console.log("\nAll state (bets, balances, stats) preserved.");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
