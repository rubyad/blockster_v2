const { ethers } = require("hardhat");

/**
 * Withdraw unused time reward pool from NFTRewarder
 *
 * IMPORTANT: This withdraws the UNUSED portion of the time reward pool.
 * It should be tested with a small deposit first before depositing the full 5.6B ROGUE.
 *
 * Usage:
 *   npx hardhat run scripts/withdraw-time-rewards.js --network rogueMainnet
 */
async function main() {
  const NFTREWARDER_PROXY = "0x96aB9560f1407586faE2b69Dc7f38a59BEACC594";

  console.log("=".repeat(60));
  console.log("NFTRewarder Time Rewards Withdrawal Test");
  console.log("=".repeat(60));

  const [deployer] = await ethers.getSigners();
  console.log("Withdrawing to:", deployer.address);

  const NFTRewarder = await ethers.getContractAt("NFTRewarder", NFTREWARDER_PROXY);

  // Check owner
  const owner = await NFTRewarder.owner();
  if (owner.toLowerCase() !== deployer.address.toLowerCase()) {
    throw new Error(`Only owner can withdraw. Owner: ${owner}, Deployer: ${deployer.address}`);
  }
  console.log("✅ Deployer is contract owner");
  console.log("");

  // Check current pool state
  const poolRemaining = await NFTRewarder.timeRewardPoolRemaining();
  console.log("Pool remaining:", ethers.formatEther(poolRemaining), "ROGUE");

  if (poolRemaining === 0n) {
    console.log("⚠️  Pool is empty, nothing to withdraw");
    return;
  }

  // Check deployer balance before
  const balanceBefore = await ethers.provider.getBalance(deployer.address);
  console.log("Wallet balance before:", ethers.formatEther(balanceBefore), "ROGUE");

  console.log("");
  console.log("Withdrawing unused pool:", ethers.formatEther(poolRemaining), "ROGUE...");

  const tx = await NFTRewarder.withdrawUnusedTimeRewardPool({ gasLimit: 100000 });
  console.log("TX Hash:", tx.hash);

  const receipt = await tx.wait();
  console.log("✅ Withdrawal confirmed in block:", receipt.blockNumber);

  // Verify withdrawal
  const poolAfter = await NFTRewarder.timeRewardPoolRemaining();
  const balanceAfter = await ethers.provider.getBalance(deployer.address);

  console.log("");
  console.log("Pool after withdrawal:", ethers.formatEther(poolAfter), "ROGUE");
  console.log("Wallet balance after:", ethers.formatEther(balanceAfter), "ROGUE");

  const received = balanceAfter - balanceBefore;
  // Note: received will be less than withdrawn amount due to gas costs
  console.log("");
  console.log("=".repeat(60));
  console.log("Withdrawal Complete!");
  console.log("=".repeat(60));
  console.log("");
  console.log("If withdrawal was successful, you can now deposit the full pool:");
  console.log("  npx hardhat run scripts/deposit-time-rewards.js --network rogueMainnet -- 5614272000");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
