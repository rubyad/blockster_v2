const { ethers, upgrades } = require("hardhat");

async function main() {
  const PROXY_ADDRESS = "0x96aB9560f1407586faE2b69Dc7f38a59BEACC594";

  const [deployer] = await ethers.getSigners();
  console.log("Upgrading with account:", deployer.address);

  // Deploy new implementation
  console.log("\nDeploying new implementation contract...");
  const NFTRewarder = await ethers.getContractFactory("NFTRewarder");
  const newImpl = await NFTRewarder.deploy();
  await newImpl.waitForDeployment();
  const newImplAddress = await newImpl.getAddress();

  console.log("New implementation deployed at:", newImplAddress);

  // Call upgradeToAndCall on the proxy
  console.log("\nUpgrading proxy to new implementation...");
  const proxy = await ethers.getContractAt("NFTRewarder", PROXY_ADDRESS);

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
