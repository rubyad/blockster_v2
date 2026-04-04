/**
 * Manual upgrade NFTRewarder to V6 (bypasses gas estimation issues)
 *
 * V6 Changes:
 * - Added getBatchTimeRewardRaw(uint256[]) - batch time reward info query
 * - Added getBatchNFTOwners(uint256[]) - batch owner query from nftMetadata
 *
 * These are read-only view functions — zero risk to existing state.
 */

const { ethers } = require("hardhat");

const PROXY_ADDRESS = "0x96aB9560f1407586faE2b69Dc7f38a59BEACC594";

async function main() {
  console.log("Manual upgrade NFTRewarder to V6...");
  console.log("Proxy address:", PROXY_ADDRESS);

  const [deployer] = await ethers.getSigners();
  console.log("Deployer address:", deployer.address);
  console.log("Deployer balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "ROGUE");

  // Get the contract factory
  const NFTRewarder = await ethers.getContractFactory("NFTRewarder");

  // Deploy new implementation
  console.log("\n1. Deploying new implementation...");
  const newImpl = await NFTRewarder.deploy({
    gasLimit: 10000000
  });
  await newImpl.waitForDeployment();
  const newImplAddress = await newImpl.getAddress();
  console.log("New implementation deployed at:", newImplAddress);

  // Upgrade proxy to new implementation
  console.log("\n2. Upgrading proxy to new implementation...");
  const proxyAbi = ["function upgradeToAndCall(address newImplementation, bytes memory data)"];
  const proxy = new ethers.Contract(PROXY_ADDRESS, proxyAbi, deployer);

  const tx = await proxy.upgradeToAndCall(newImplAddress, "0x", {
    gasLimit: 500000
  });
  console.log("Upgrade tx:", tx.hash);
  await tx.wait();
  console.log("Upgrade complete!");

  // Verify the new functions exist
  console.log("\n=== Verifying new functions ===");
  const upgraded = NFTRewarder.attach(PROXY_ADDRESS);

  // Test getBatchTimeRewardRaw with a special NFT
  try {
    const timeResult = await upgraded.getBatchTimeRewardRaw([2340, 2341, 2342]);
    console.log("getBatchTimeRewardRaw() works!");
    console.log("  startTimes:", timeResult.startTimes.map(t => t.toString()));
    console.log("  lastClaimTimes:", timeResult.lastClaimTimes.map(t => t.toString()));
    console.log("  totalClaimeds:", timeResult.totalClaimeds.map(t => ethers.formatEther(t)));
  } catch (e) {
    console.error("Error calling getBatchTimeRewardRaw:", e.message);
  }

  // Test getBatchNFTOwners
  try {
    const owners = await upgraded.getBatchNFTOwners([1, 2, 3]);
    console.log("getBatchNFTOwners() works!");
    console.log("  owners:", owners);
  } catch (e) {
    console.error("Error calling getBatchNFTOwners:", e.message);
  }

  console.log("\n=== UPDATE THESE VALUES ===");
  console.log("NFT_REWARDER_IMPL_ADDRESS:", newImplAddress);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
