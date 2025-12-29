const { ethers, upgrades } = require("hardhat");

async function main() {
  const PROXY_ADDRESS = "0x97b6d6A8f2c6AF6e6fb40f8d36d60DF2fFE4f17B";

  const [deployer] = await ethers.getSigners();
  console.log("Upgrading with account:", deployer.address);

  // Deploy new implementation
  console.log("\nDeploying new implementation contract...");
  const BuxBoosterGame = await ethers.getContractFactory("BuxBoosterGame");
  const newImpl = await BuxBoosterGame.deploy();
  await newImpl.waitForDeployment();
  const newImplAddress = await newImpl.getAddress();
  
  console.log("New implementation deployed at:", newImplAddress);

  // Call upgradeToAndCall on the proxy
  console.log("\nUpgrading proxy to new implementation...");
  const proxy = await ethers.getContractAt("BuxBoosterGame", PROXY_ADDRESS);
  
  try {
    const tx = await proxy.upgradeToAndCall(newImplAddress, "0x", { gasLimit: 5000000 });
    console.log("Upgrade tx submitted:", tx.hash);
    await tx.wait();
    console.log("✅ Upgrade complete!");
  } catch (error) {
    console.error("Upgrade failed:", error.message);
    if (error.data) {
      console.error("Error data:", error.data);
    }
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
