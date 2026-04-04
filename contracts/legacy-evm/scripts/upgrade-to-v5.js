const { ethers } = require("hardhat");

async function main() {
  const PROXY_ADDRESS = "0x97b6d6A8f2c6AF6e6fb40f8d36d60DF2fFE4f17B";
  const ROGUE_BANKROLL_ADDRESS = "0x51DB4eD2b69b598Fade1aCB5289C7426604AB2fd";

  const [deployer] = await ethers.getSigners();
  console.log("Upgrading BuxBoosterGame to V5 with account:", deployer.address);
  console.log("Proxy address:", PROXY_ADDRESS);
  console.log("ROGUEBankroll address:", ROGUE_BANKROLL_ADDRESS);

  // Step 1: Deploy new implementation
  console.log("\n=== Step 1: Deploy New Implementation ===");
  const BuxBoosterGame = await ethers.getContractFactory("BuxBoosterGame");
  const newImpl = await BuxBoosterGame.deploy();
  await newImpl.waitForDeployment();
  const newImplAddress = await newImpl.getAddress();

  console.log("✓ New V5 implementation deployed at:", newImplAddress);

  // Step 2: Upgrade proxy to new implementation
  console.log("\n=== Step 2: Upgrade Proxy ===");
  const proxy = await ethers.getContractAt("BuxBoosterGame", PROXY_ADDRESS);

  try {
    const upgradeTx = await proxy.upgradeToAndCall(newImplAddress, "0x", { gasLimit: 5000000 });
    console.log("Upgrade transaction:", upgradeTx.hash);
    await upgradeTx.wait();
    console.log("✓ Proxy upgraded to V5 implementation");
  } catch (error) {
    console.error("✗ Upgrade failed:", error.message);
    if (error.data) {
      console.error("Error data:", error.data);
    }
    process.exit(1);
  }

  // Step 3: Initialize V5
  console.log("\n=== Step 3: Initialize V5 ===");

  // Check current rogueBankroll value
  const currentBankroll = await proxy.rogueBankroll();
  console.log("Current rogueBankroll address:", currentBankroll);

  if (currentBankroll.toLowerCase() === ROGUE_BANKROLL_ADDRESS.toLowerCase()) {
    console.log("✓ ROGUEBankroll already initialized!");
  } else {
    console.log("Calling initializeV5...");
    try {
      const initTx = await proxy.initializeV5(ROGUE_BANKROLL_ADDRESS);
      console.log("Initialize transaction:", initTx.hash);
      await initTx.wait();

      const newBankroll = await proxy.rogueBankroll();
      console.log("✓ ROGUEBankroll set to:", newBankroll);
    } catch (error) {
      console.error("✗ Initialization failed:", error.message);
      if (error.data) {
        console.error("Error data:", error.data);
      }
      process.exit(1);
    }
  }

  // Step 4: Verify configuration
  console.log("\n=== Verification ===");
  const rogueBankroll = await proxy.rogueBankroll();
  console.log("BuxBoosterGame.rogueBankroll:", rogueBankroll);

  if (rogueBankroll.toLowerCase() === ROGUE_BANKROLL_ADDRESS.toLowerCase()) {
    console.log("\n✅ BuxBoosterGame V5 upgrade complete and configured!");
    console.log("\nNext steps:");
    console.log("1. Test ROGUE betting on testnet/local");
    console.log("2. Update BUX Minter service with new contract ABIs");
    console.log("3. Update frontend to support ROGUE betting");
  } else {
    console.log("\n✗ Configuration mismatch - please verify manually");
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
