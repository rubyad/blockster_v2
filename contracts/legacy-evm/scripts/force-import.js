const { ethers, upgrades } = require("hardhat");

async function main() {
  const PROXY_ADDRESS = "0x97b6d6A8f2c6AF6e6fb40f8d36d60DF2fFE4f17B";

  const [deployer] = await ethers.getSigners();
  console.log("Force importing with account:", deployer.address);

  const BuxBoosterGame = await ethers.getContractFactory("BuxBoosterGame");

  console.log("\nForce importing proxy at:", PROXY_ADDRESS);
  await upgrades.forceImport(PROXY_ADDRESS, BuxBoosterGame, { kind: "uups" });

  console.log("✅ Proxy imported successfully");
  console.log("\nYou can now run upgrade.js");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
