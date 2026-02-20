/**
 * Set PlinkoGame address on ROGUEBankroll
 *
 * Usage:
 *   npx hardhat run scripts/set-plinko-on-roguebankroll.js --network rogueMainnet
 *
 * Prerequisites:
 *   - DEPLOYER_PRIVATE_KEY in .env must be ROGUEBankroll owner (0xc2eF...)
 */

const { ethers } = require("hardhat");

const ROGUE_BANKROLL_PROXY = "0x51DB4eD2b69b598Fade1aCB5289C7426604AB2fd";
const PLINKO_GAME_PROXY = "0x7E12c7077556B142F8Fb695F70aAe0359a8be10C";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("=== Set PlinkoGame on ROGUEBankroll ===");
  console.log("Deployer:", deployer.address);

  const rogueBankroll = await ethers.getContractAt(
    "contracts/ROGUEBankroll.sol:ROGUEBankroll",
    ROGUE_BANKROLL_PROXY
  );

  const owner = await rogueBankroll.owner();
  console.log("Owner:", owner);

  if (owner.toLowerCase() !== deployer.address.toLowerCase()) {
    console.error("ERROR: Deployer is not the owner.");
    process.exit(1);
  }

  const current = await rogueBankroll.plinkoGame();
  console.log("Current plinkoGame:", current);

  if (current.toLowerCase() === PLINKO_GAME_PROXY.toLowerCase()) {
    console.log("Already set. Nothing to do.");
    return;
  }

  console.log("Setting plinkoGame to:", PLINKO_GAME_PROXY);
  const tx = await rogueBankroll.setPlinkoGame(PLINKO_GAME_PROXY);
  console.log("Tx:", tx.hash);
  await tx.wait();

  const updated = await rogueBankroll.plinkoGame();
  console.log("Updated plinkoGame:", updated);
  console.log("Done.");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
