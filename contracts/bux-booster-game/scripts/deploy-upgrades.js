/**
 * Deploy using OpenZeppelin Upgrades plugin
 */

const { ethers, upgrades } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying with account:", deployer.address);
  console.log("Account balance:", (await ethers.provider.getBalance(deployer.address)).toString());

  const BuxBoosterGame = await ethers.getContractFactory("BuxBoosterGameTransparent");

  console.log("\nDeploying BuxBoosterGameTransparent...");

  const game = await upgrades.deployProxy(BuxBoosterGame, [], {
    initializer: "initialize",
    kind: "transparent",
    unsafeAllow: ["constructor"]
  });

  await game.waitForDeployment();

  const address = await game.getAddress();
  console.log("Contract deployed at:", address);

  // Set settler
  const settlerAddress = "0x4BBe1C90a0A6974d8d9A598d081309D8Ff27bb81";
  console.log("\nSetting settler to:", settlerAddress);
  const tx = await game.setSettler(settlerAddress);
  await tx.wait();
  console.log("Settler set successfully");

  // Verify
  console.log("\nVerifying...");
  console.log("Owner:", await game.owner());
  console.log("Settler:", await game.settler());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
