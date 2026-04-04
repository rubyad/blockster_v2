/**
 * Approve and deposit BUX into BuxBoosterGame house balance.
 *
 * PRE-REQUISITE: Mint BUX to the deployer address first via minter service:
 *   curl -X POST https://bux-minter.fly.dev/mint \
 *     -H "Content-Type: application/json" \
 *     -d '{"walletAddress":"0x4BDC5602f2A3E04c6e3a9321A7AC5000e0A623e0","amount":50000,"userId":0,"postId":null,"rewardType":"signup","secret":"..."}'
 *
 * Run with: npx hardhat run scripts/deposit-bux-house.js --network rogueMainnet
 */

const { ethers } = require("hardhat");

const GAME_CONTRACT = "0x97b6d6A8f2c6AF6e6fb40f8d36d60DF2fFE4f17B";
const BUX_TOKEN = "0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8";
const DEPOSIT_AMOUNT = ethers.parseEther("10000000"); // 10M BUX

const ERC20_ABI = [
  "function approve(address spender, uint256 amount) external returns (bool)",
  "function balanceOf(address account) external view returns (uint256)"
];

const GAME_ABI = [
  "function depositHouseBalance(address token, uint256 amount) external",
  "function tokenConfigs(address) external view returns (bool enabled, uint256 houseBalance)",
  "function owner() external view returns (address)"
];

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deployer:", deployer.address);

  const bux = new ethers.Contract(BUX_TOKEN, ERC20_ABI, deployer);
  const game = new ethers.Contract(GAME_CONTRACT, GAME_ABI, deployer);

  // Verify deployer is game owner
  const gameOwner = await game.owner();
  console.log("Game owner:", gameOwner);
  if (gameOwner.toLowerCase() !== deployer.address.toLowerCase()) {
    throw new Error("Deployer is not the game owner! Cannot deposit.");
  }
  console.log("✅ Deployer is game owner");

  // Check current state
  const config = await game.tokenConfigs(BUX_TOKEN);
  console.log("\nCurrent house balance:", ethers.formatEther(config.houseBalance), "BUX");

  const balance = await bux.balanceOf(deployer.address);
  console.log("Deployer BUX balance:", ethers.formatEther(balance), "BUX");

  if (balance < DEPOSIT_AMOUNT) {
    throw new Error(`Insufficient BUX balance. Have ${ethers.formatEther(balance)}, need ${ethers.formatEther(DEPOSIT_AMOUNT)}. Mint first via minter service.`);
  }

  // 1. Approve game contract
  console.log("\nApproving game contract for 50,000 BUX...");
  const approveTx = await bux.approve(GAME_CONTRACT, DEPOSIT_AMOUNT);
  await approveTx.wait();
  console.log("✅ Approved.");

  // 2. Deposit into house balance
  console.log("Depositing 50,000 BUX as house balance...");
  const depositTx = await game.depositHouseBalance(BUX_TOKEN, DEPOSIT_AMOUNT);
  await depositTx.wait();
  console.log("✅ Deposited.");

  // Verify
  const newConfig = await game.tokenConfigs(BUX_TOKEN);
  console.log("\n🎉 New house balance:", ethers.formatEther(newConfig.houseBalance), "BUX");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
