const { ethers } = require("hardhat");

async function main() {
  const rewarder = await ethers.getContractAt(
    ["function pendingReward(uint256) view returns (uint256)",
     "function nftClaimedRewards(uint256) view returns (uint256)",
     "function nftRewardDebt(uint256) view returns (uint256)",
     "function rewardsPerMultiplierPoint() view returns (uint256)",
     "function nftMetadata(uint256) view returns (uint8 hostessIndex, bool registered, address owner)"],
    "0x96aB9560f1407586faE2b69Dc7f38a59BEACC594"
  );

  const tokenIds = [1860, 1918, 1919, 1920, 1921, 1922];
  const MULTIPLIERS = [100, 90, 80, 70, 60, 50, 40, 30];
  
  const rewardsPerPoint = await rewarder.rewardsPerMultiplierPoint();
  console.log("rewardsPerMultiplierPoint:", ethers.formatEther(rewardsPerPoint));
  
  for (const tokenId of tokenIds) {
    const pending = await rewarder.pendingReward(tokenId);
    const claimed = await rewarder.nftClaimedRewards(tokenId);
    const debt = await rewarder.nftRewardDebt(tokenId);
    const metadata = await rewarder.nftMetadata(tokenId);
    const multiplier = MULTIPLIERS[metadata.hostessIndex];
    
    console.log("\nToken " + tokenId + ":");
    console.log("  hostessIndex: " + metadata.hostessIndex + ", multiplier: " + multiplier);
    console.log("  pending: " + ethers.formatEther(pending) + " ROGUE");
    console.log("  claimed: " + ethers.formatEther(claimed) + " ROGUE");
    console.log("  debt: " + ethers.formatEther(debt));
    console.log("  total earned: " + ethers.formatEther(pending + claimed) + " ROGUE");
  }
}

main();
