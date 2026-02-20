/**
 * Set settler address on PlinkoGame
 *
 * Usage:
 *   npx hardhat run scripts/set-plinko-settler.js --network rogueMainnet
 */

const { ethers } = require("hardhat");

const PLINKO_GAME_PROXY = "0x7E12c7077556B142F8Fb695F70aAe0359a8be10C";
const PLINKO_SETTLER = "0x7700EFCCC54bD10B75E0d0C8B38881a61571A7d7";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("=== Set PlinkoGame Settler ===");
  console.log("Deployer:", deployer.address);

  const plinko = await ethers.getContractAt("PlinkoGame", PLINKO_GAME_PROXY);

  const owner = await plinko.owner();
  if (owner.toLowerCase() !== deployer.address.toLowerCase()) {
    console.error("ERROR: Deployer is not the owner.");
    process.exit(1);
  }

  const current = await plinko.settler();
  console.log("Current settler:", current);

  if (current.toLowerCase() === PLINKO_SETTLER.toLowerCase()) {
    console.log("Already set. Nothing to do.");
    return;
  }

  console.log("Setting settler to:", PLINKO_SETTLER);
  const tx = await plinko.setSettler(PLINKO_SETTLER);
  console.log("Tx:", tx.hash);
  await tx.wait();

  console.log("Updated settler:", await plinko.settler());
  console.log("Done.");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
