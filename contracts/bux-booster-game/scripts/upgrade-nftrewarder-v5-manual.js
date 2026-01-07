/**
 * Manual upgrade NFTRewarder to V5 (bypasses gas estimation issues)
 *
 * V5 Changes:
 * - Added getUserPortfolioStats(address) - combined view function for user totals
 */

const { ethers, upgrades } = require("hardhat");

const PROXY_ADDRESS = "0x96aB9560f1407586faE2b69Dc7f38a59BEACC594";

async function main() {
  console.log("Manual upgrade NFTRewarder to V5...");
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

  // Verify the new function exists
  console.log("\n=== Verifying new function ===");
  const upgraded = NFTRewarder.attach(PROXY_ADDRESS);
  const testAddress = "0xb91b270212F0F7504ECBa6Ff1d9c1f58DfcEEa14";

  try {
    const stats = await upgraded.getUserPortfolioStats(testAddress);
    console.log("getUserPortfolioStats() works!");
    console.log("  Revenue Pending:", ethers.formatEther(stats.revenuePending), "ROGUE");
    console.log("  Revenue Claimed:", ethers.formatEther(stats.revenueClaimed), "ROGUE");
    console.log("  Time Pending:", ethers.formatEther(stats.timePending), "ROGUE");
    console.log("  Time Claimed:", ethers.formatEther(stats.timeClaimed), "ROGUE");
    console.log("  Total Pending:", ethers.formatEther(stats.totalPending), "ROGUE");
    console.log("  Total Earned:", ethers.formatEther(stats.totalEarned), "ROGUE");
    console.log("  NFT Count:", stats.nftCount.toString());
    console.log("  Special NFT Count:", stats.specialNftCount.toString());
  } catch (e) {
    console.error("Error calling getUserPortfolioStats:", e.message);
  }

  console.log("\n=== UPDATE THESE VALUES ===");
  console.log("NFT_REWARDER_IMPL_ADDRESS:", newImplAddress);
  console.log("getUserPortfolioStats selector: 0xd8824b05");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
