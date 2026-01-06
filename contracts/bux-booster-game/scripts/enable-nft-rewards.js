/**
 * Enable NFT rewards on ROGUEBankroll by:
 * 1. Setting the NFTRewarder contract address
 * 2. Setting the NFT reward basis points to 20 (0.2%)
 */

const { ethers } = require("hardhat");

const ROGUE_BANKROLL_ADDRESS = "0x51DB4eD2b69b598Fade1aCB5289C7426604AB2fd";
const NFT_REWARDER_ADDRESS = "0x96aB9560f1407586faE2b69Dc7f38a59BEACC594";
const NFT_REWARD_BASIS_POINTS = 20;  // 0.2%

const ROGUE_BANKROLL_ABI = [
  "function setNFTRewarder(address _nftRewarder) external",
  "function setNFTRewardBasisPoints(uint256 _basisPoints) external",
  "function getNFTRewarder() external view returns (address)",
  "function getNFTRewardBasisPoints() external view returns (uint256)",
  "function owner() external view returns (address)"
];

async function main() {
  console.log("=== Enabling NFT Rewards on ROGUEBankroll ===\n");

  const [deployer] = await ethers.getSigners();
  console.log("Owner:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "ROGUE\n");

  // Connect to ROGUEBankroll
  const rogueBankroll = new ethers.Contract(ROGUE_BANKROLL_ADDRESS, ROGUE_BANKROLL_ABI, deployer);

  // Check owner
  const owner = await rogueBankroll.owner();
  console.log("ROGUEBankroll owner:", owner);
  console.log("Deployer is owner:", owner.toLowerCase() === deployer.address.toLowerCase() ? "✓ Yes" : "✗ No");

  if (owner.toLowerCase() !== deployer.address.toLowerCase()) {
    console.error("\n✗ ERROR: Deployer is not the owner. Cannot configure NFT rewards.");
    process.exit(1);
  }

  // Check current state
  console.log("\nCurrent state:");
  const currentNFTRewarder = await rogueBankroll.getNFTRewarder();
  const currentBasisPoints = await rogueBankroll.getNFTRewardBasisPoints();
  console.log("  NFTRewarder:", currentNFTRewarder);
  console.log("  NFTRewardBasisPoints:", currentBasisPoints.toString());

  // Set NFTRewarder address
  if (currentNFTRewarder.toLowerCase() !== NFT_REWARDER_ADDRESS.toLowerCase()) {
    console.log("\nSetting NFTRewarder...");
    const tx1 = await rogueBankroll.setNFTRewarder(NFT_REWARDER_ADDRESS, { gasLimit: 100000 });
    console.log("TX:", tx1.hash);
    await tx1.wait();
    console.log("✓ NFTRewarder set to", NFT_REWARDER_ADDRESS);
  } else {
    console.log("\n✓ NFTRewarder already set correctly");
  }

  // Set NFTRewardBasisPoints
  if (Number(currentBasisPoints) !== NFT_REWARD_BASIS_POINTS) {
    console.log("\nSetting NFTRewardBasisPoints...");
    const tx2 = await rogueBankroll.setNFTRewardBasisPoints(NFT_REWARD_BASIS_POINTS, { gasLimit: 100000 });
    console.log("TX:", tx2.hash);
    await tx2.wait();
    console.log("✓ NFTRewardBasisPoints set to", NFT_REWARD_BASIS_POINTS, "(0.2%)");
  } else {
    console.log("\n✓ NFTRewardBasisPoints already set correctly");
  }

  // Verify final state
  console.log("\n=== Final State ===");
  const finalNFTRewarder = await rogueBankroll.getNFTRewarder();
  const finalBasisPoints = await rogueBankroll.getNFTRewardBasisPoints();
  console.log("NFTRewarder:", finalNFTRewarder);
  console.log("NFTRewardBasisPoints:", finalBasisPoints.toString(), "(0.2%)");
  console.log("\n✅ NFT rewards enabled! Losing ROGUE bets will now send 0.2% to NFT holders.");
}

main().catch(console.error);
