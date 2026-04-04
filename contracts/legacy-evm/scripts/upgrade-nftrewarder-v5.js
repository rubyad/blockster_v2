/**
 * Upgrade NFTRewarder to V5
 *
 * V5 Changes:
 * - Added getUserPortfolioStats(address) - combined view function for user totals
 *   Returns: revenuePending, revenueClaimed, timePending, timeClaimed, totalPending, totalEarned, nftCount, specialNftCount
 */

const { ethers, upgrades } = require("hardhat");

const PROXY_ADDRESS = "0x96aB9560f1407586faE2b69Dc7f38a59BEACC594";

async function main() {
  console.log("Upgrading NFTRewarder to V5...");
  console.log("Proxy address:", PROXY_ADDRESS);

  const [deployer] = await ethers.getSigners();
  console.log("Deployer address:", deployer.address);
  console.log("Deployer balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "ROGUE");

  // Get the contract factory
  const NFTRewarder = await ethers.getContractFactory("NFTRewarder");

  // Force import the proxy if not already imported
  try {
    await upgrades.forceImport(PROXY_ADDRESS, NFTRewarder, { kind: 'uups' });
    console.log("Proxy imported successfully");
  } catch (e) {
    if (e.message.includes("already been used")) {
      console.log("Proxy already imported, continuing...");
    } else {
      throw e;
    }
  }

  // Upgrade the proxy
  console.log("\nUpgrading proxy...");
  const upgraded = await upgrades.upgradeProxy(PROXY_ADDRESS, NFTRewarder, {
    kind: 'uups',
    redeployImplementation: 'always'
  });

  await upgraded.waitForDeployment();

  const newImplAddress = await upgrades.erc1967.getImplementationAddress(PROXY_ADDRESS);
  console.log("\n=== Upgrade Complete ===");
  console.log("Proxy address:", PROXY_ADDRESS);
  console.log("New implementation:", newImplAddress);

  // Verify the new function exists
  console.log("\n=== Verifying new function ===");
  const testAddress = "0xb91b270212F0F7504ECBa6Ff1d9c1f58DfcEEa14"; // Test wallet
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
