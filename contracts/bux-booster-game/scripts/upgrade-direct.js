const { ethers } = require("hardhat");

async function main() {
  const PROXY_ADDRESS = "0x97b6d6A8f2c6AF6e6fb40f8d36d60DF2fFE4f17B";

  const [deployer] = await ethers.getSigners();
  console.log("Upgrading with account:", deployer.address);

  console.log("\nDeploying new implementation...");

  // Deploy new implementation
  const BuxBoosterGame = await ethers.getContractFactory("BuxBoosterGame");
  const implementation = await BuxBoosterGame.deploy();
  await implementation.waitForDeployment();

  const newImplAddress = await implementation.getAddress();
  console.log("New implementation deployed at:", newImplAddress);

  // Upgrade proxy to new implementation
  console.log("\nUpgrading proxy...");

  // Connect to proxy as UUPSUpgradeable
  const proxyAbi = [
    "function upgradeToAndCall(address newImplementation, bytes memory data) external"
  ];
  const proxy = new ethers.Contract(PROXY_ADDRESS, proxyAbi, deployer);

  // Upgrade to new implementation (empty data = no initializer call)
  const tx = await proxy.upgradeToAndCall(newImplAddress, "0x");
  console.log("Upgrade tx:", tx.hash);
  await tx.wait();

  console.log("\n=== Upgrade Complete ===");
  console.log("Proxy Address (unchanged):", PROXY_ADDRESS);
  console.log("New Implementation Address:", newImplAddress);

  // Verify arrays are still populated
  const upgraded = BuxBoosterGame.attach(PROXY_ADDRESS);
  console.log("\n=== Verifying State ===");
  console.log("FLIP_COUNTS[4]:", await upgraded.FLIP_COUNTS(4));
  console.log("MULTIPLIERS[4]:", await upgraded.MULTIPLIERS(4));
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
