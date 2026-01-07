const { ethers } = require("hardhat");

const NFT_REWARDER_ADDRESS = "0x96aB9560f1407586faE2b69Dc7f38a59BEACC594";
const NFT_REWARDER_ABI = [
  "function registerNFT(uint256 tokenId, uint8 hostessIndex, address owner) external",
  "function nftData(uint256 tokenId) view returns (address owner, uint8 hostessType, uint256 pendingAmount, uint256 totalEarned)",
  "function totalRegisteredNFTs() view returns (uint256)",
  "function totalMultiplierPoints() view returns (uint256)"
];

async function main() {
  const [signer] = await ethers.getSigners();
  console.log("Admin wallet:", signer.address);

  const nftRewarder = new ethers.Contract(NFT_REWARDER_ADDRESS, NFT_REWARDER_ABI, signer);

  // NFT 2342: Scarlett Ember, hostessIndex 6, owner 0x551F96D689B365D8Abbc4ef20101d4332832e576
  const tokenId = 2342;
  const hostessIndex = 6; // Scarlett Ember
  const owner = "0x551F96D689B365D8Abbc4ef20101d4332832e576";

  console.log(`\nRegistering NFT #${tokenId}...`);
  console.log(`  Hostess: Scarlett Ember (index ${hostessIndex})`);
  console.log(`  Owner: ${owner}`);

  const tx = await nftRewarder.registerNFT(tokenId, hostessIndex, owner);
  console.log(`  TX Hash: ${tx.hash}`);
  
  const receipt = await tx.wait();
  console.log(`  Confirmed in block ${receipt.blockNumber}`);

  // Verify registration
  const data = await nftRewarder.nftData(tokenId);
  console.log(`\nVerification:`);
  console.log(`  Owner: ${data.owner}`);
  console.log(`  Hostess Type: ${data.hostessType}`);
  
  const totalNFTs = await nftRewarder.totalRegisteredNFTs();
  const totalPoints = await nftRewarder.totalMultiplierPoints();
  console.log(`\nTotal Registered: ${totalNFTs} NFTs`);
  console.log(`Total Multiplier Points: ${totalPoints}`);
}

main().catch(console.error);
