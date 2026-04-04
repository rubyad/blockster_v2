const { ethers } = require("hardhat");

/**
 * Deposit ROGUE to NFTRewarder time reward pool
 *
 * Usage:
 *   AMOUNT=1000 npx hardhat run scripts/deposit-time-rewards.js --network rogueMainnet
 *   AMOUNT=5614272000 npx hardhat run scripts/deposit-time-rewards.js --network rogueMainnet
 *
 * Environment Variables:
 *   AMOUNT: Amount of ROGUE to deposit (default: 1000 for testing)
 *
 * Full pool amount: 5,614,272,000 ROGUE
 */
async function main() {
  const NFTREWARDER_PROXY = "0x96aB9560f1407586faE2b69Dc7f38a59BEACC594";
  const FULL_POOL_AMOUNT = "5614272000"; // 5.6B ROGUE for full deployment

  // Get amount from environment variable, default to 1000 ROGUE for testing
  const amountStr = process.env.AMOUNT || "1000";
  const DEPOSIT_AMOUNT = ethers.parseEther(amountStr);

  console.log("=".repeat(60));
  console.log("NFTRewarder Time Rewards Deposit");
  console.log("=".repeat(60));
  console.log("Amount to deposit:", amountStr, "ROGUE");
  if (amountStr !== FULL_POOL_AMOUNT) {
    console.log("⚠️  TEST MODE - not the full pool amount");
    console.log("   Full pool amount is:", FULL_POOL_AMOUNT, "ROGUE");
  } else {
    console.log("🎯 FULL POOL DEPOSIT - 5.6B ROGUE");
  }
  console.log("");

  const [deployer] = await ethers.getSigners();
  console.log("Depositing from:", deployer.address);

  // Check balance
  const balance = await ethers.provider.getBalance(deployer.address);
  console.log("Deployer balance:", ethers.formatEther(balance), "ROGUE");

  if (balance < DEPOSIT_AMOUNT) {
    throw new Error(`Insufficient balance. Need ${amountStr} ROGUE, have ${ethers.formatEther(balance)} ROGUE`);
  }

  const NFTRewarder = await ethers.getContractAt("NFTRewarder", NFTREWARDER_PROXY);

  // Check owner
  const owner = await NFTRewarder.owner();
  if (owner.toLowerCase() !== deployer.address.toLowerCase()) {
    throw new Error(`Only owner can deposit. Owner: ${owner}, Deployer: ${deployer.address}`);
  }
  console.log("✅ Deployer is contract owner");
  console.log("");

  // Show current pool state before deposit
  try {
    const poolBefore = await NFTRewarder.timeRewardPoolRemaining();
    console.log("Pool before deposit:", ethers.formatEther(poolBefore), "ROGUE");
  } catch (e) {
    console.log("Pool before deposit: 0 ROGUE (not initialized yet or error:", e.message, ")");
  }

  console.log("");
  console.log("Depositing", amountStr, "ROGUE for time rewards...");

  // For large amounts (>100M), micro-eth-signer has a hardcoded limit
  // We bypass it by sending a raw transaction directly
  const functionData = NFTRewarder.interface.encodeFunctionData("depositTimeRewards", []);

  const txRequest = {
    to: NFTREWARDER_PROXY,
    data: functionData,
    value: DEPOSIT_AMOUNT,
    gasLimit: 100000n,
    gasPrice: 1000000000000n, // 1000 gwei - Rogue Chain base fee
  };

  // Get nonce
  const nonce = await ethers.provider.getTransactionCount(deployer.address);
  txRequest.nonce = nonce;
  txRequest.chainId = 560013n;

  // Sign and send raw transaction to bypass micro-eth-signer value limit
  const wallet = new ethers.Wallet(process.env.DEPLOYER_PRIVATE_KEY, ethers.provider);
  const signedTx = await wallet.signTransaction(txRequest);
  const txResponse = await ethers.provider.broadcastTransaction(signedTx);

  console.log("TX Hash:", txResponse.hash);

  const receipt = await txResponse.wait();
  console.log("✅ Deposit confirmed in block:", receipt.blockNumber);

  // Verify deposit
  const poolAfter = await NFTRewarder.timeRewardPoolRemaining();
  console.log("Pool after deposit:", ethers.formatEther(poolAfter), "ROGUE");
  console.log("");
  console.log("=".repeat(60));
  console.log("Deposit Complete!");
  console.log("=".repeat(60));

  if (amountStr !== FULL_POOL_AMOUNT) {
    console.log("");
    console.log("Next steps:");
    console.log("1. Test withdrawal to verify it works:");
    console.log("   npx hardhat run scripts/withdraw-time-rewards.js --network rogueMainnet");
    console.log("");
    console.log("2. After verifying withdrawal works, deposit full pool:");
    console.log("   npx hardhat run scripts/deposit-time-rewards.js --network rogueMainnet -- 5614272000");
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
