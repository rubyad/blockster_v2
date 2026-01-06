const { ethers } = require("hardhat");

async function main() {
  const abi = [
    "function getBatchNFTEarnings(uint256[] calldata tokenIds) external view returns (tuple(uint256 totalEarned, uint256 pendingAmount, uint8 hostessIndex)[] memory)"
  ];
  
  const rewarder = new ethers.Contract(
    "0x96aB9560f1407586faE2b69Dc7f38a59BEACC594",
    abi,
    new ethers.JsonRpcProvider("https://rpc.roguechain.io/rpc")
  );

  const tokenIds = [1860, 1918, 1919, 1920, 1921, 1922];
  
  const earnings = await rewarder.getBatchNFTEarnings(tokenIds);
  
  for (let i = 0; i < tokenIds.length; i++) {
    console.log("\nToken " + tokenIds[i] + ":");
    console.log("  totalEarned: " + earnings[i].totalEarned.toString());
    console.log("  pendingAmount: " + earnings[i].pendingAmount.toString());
    console.log("  hostessIndex: " + earnings[i].hostessIndex);
  }
}

main();
