const { ethers, upgrades } = require("hardhat");

async function main() {
  console.log("Upgrading BuxBoosterGame to V3...");

  const PROXY_ADDRESS = "0x97b6d6A8f2c6AF6e6fb40f8d36d60DF2fFE4f17B";

  // Get the V3 contract factory
  const BuxBoosterGameV3 = await ethers.getContractFactory("BuxBoosterGame");

  console.log("Upgrading proxy at:", PROXY_ADDRESS);

  try {
    // Upgrade the proxy to V3
    const upgraded = await upgrades.upgradeProxy(PROXY_ADDRESS, BuxBoosterGameV3, {
      timeout: 120000,
      pollingInterval: 5000
    });

    await upgraded.waitForDeployment();

    const implAddress = await upgrades.erc1967.getImplementationAddress(PROXY_ADDRESS);

    console.log("✅ Upgrade successful!");
    console.log("Proxy address:", PROXY_ADDRESS);
    console.log("New implementation address:", implAddress);

    console.log("\nNext step: Call initializeV3() to complete the upgrade");
    console.log("Run: npx hardhat run scripts/init-v3.js --network rogueMainnet");

  } catch (error) {
    console.error("Upgrade failed:", error.message);

    if (error.message.includes("gas")) {
      console.log("\nTrying manual upgrade with explicit gas limits...");
      console.log("Run: npx hardhat run scripts/upgrade-manual.js --network rogueMainnet");
    }

    throw error;
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
