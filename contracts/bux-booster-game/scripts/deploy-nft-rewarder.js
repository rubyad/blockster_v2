const { ethers, upgrades } = require("hardhat");

async function main() {
  // Configuration - set these after deployment via setter functions
  const ADMIN_ADDRESS = "0xa86256423DdAf710295f1E64fDE09a72Bed65113";
  const ROGUE_BANKROLL_ADDRESS = "0x51DB4eD2b69b598Fade1aCB5289C7426604AB2fd";

  const [deployer] = await ethers.getSigners();
  console.log("Deploying NFTRewarder with account:", deployer.address);
  console.log("Account balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "ROGUE");

  // Step 1: Deploy using OpenZeppelin upgrades plugin (UUPS proxy)
  console.log("\n=== Step 1: Deploy NFTRewarder Proxy ===");
  const NFTRewarder = await ethers.getContractFactory("NFTRewarder");

  const nftRewarder = await upgrades.deployProxy(NFTRewarder, [], {
    initializer: "initialize",
    kind: "uups",
    unsafeAllow: ["constructor", "state-variable-assignment", "state-variable-immutable"]
  });

  await nftRewarder.waitForDeployment();
  const proxyAddress = await nftRewarder.getAddress();
  console.log("✓ NFTRewarder proxy deployed at:", proxyAddress);

  // Get implementation address
  const implAddress = await upgrades.erc1967.getImplementationAddress(proxyAddress);
  console.log("✓ Implementation deployed at:", implAddress);

  // Step 2: Verify initialization
  console.log("\n=== Step 2: Verify Initialization ===");
  const owner = await nftRewarder.owner();
  console.log("Owner:", owner);
  console.log("Expected deployer:", deployer.address);
  console.log("Owner match:", owner.toLowerCase() === deployer.address.toLowerCase() ? "✓" : "✗");

  // Step 3: Set admin
  console.log("\n=== Step 3: Set Admin ===");
  const setAdminTx = await nftRewarder.setAdmin(ADMIN_ADDRESS);
  await setAdminTx.wait();
  const admin = await nftRewarder.admin();
  console.log("Admin set to:", admin);
  console.log("Admin match:", admin.toLowerCase() === ADMIN_ADDRESS.toLowerCase() ? "✓" : "✗");

  // Step 4: Set ROGUEBankroll
  console.log("\n=== Step 4: Set ROGUEBankroll ===");
  const setBankrollTx = await nftRewarder.setRogueBankroll(ROGUE_BANKROLL_ADDRESS);
  await setBankrollTx.wait();
  const bankroll = await nftRewarder.rogueBankroll();
  console.log("ROGUEBankroll set to:", bankroll);
  console.log("ROGUEBankroll match:", bankroll.toLowerCase() === ROGUE_BANKROLL_ADDRESS.toLowerCase() ? "✓" : "✗");

  // Step 5: Verify state
  console.log("\n=== Step 5: Verify State ===");
  const totalMultiplierPoints = await nftRewarder.totalMultiplierPoints();
  console.log("Total multiplier points:", totalMultiplierPoints.toString());

  const totalRegisteredNFTs = await nftRewarder.totalRegisteredNFTs();
  console.log("Total registered NFTs:", totalRegisteredNFTs.toString());

  const totalRewardsReceived = await nftRewarder.totalRewardsReceived();
  console.log("Total rewards received:", ethers.formatEther(totalRewardsReceived), "ROGUE");

  console.log("\n=== Deployment Summary ===");
  console.log("Implementation:", implAddress);
  console.log("Proxy (NFTRewarder):", proxyAddress);
  console.log("Owner:", owner);
  console.log("Admin:", admin);
  console.log("ROGUEBankroll:", bankroll);

  console.log("\n=== Next Steps ===");
  console.log("1. Verify implementation on Roguescan:");
  console.log(`   npx hardhat verify --network rogueMainnet ${implAddress}`);
  console.log("2. Register all NFTs via batchRegisterNFTs()");
  console.log("3. Upgrade ROGUEBankroll to V7");
  console.log("4. Call setNFTRewarder(" + proxyAddress + ") on ROGUEBankroll");
  console.log("5. Call setNFTRewardBasisPoints(20) on ROGUEBankroll");

  return { implementation: implAddress, proxy: proxyAddress };
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
