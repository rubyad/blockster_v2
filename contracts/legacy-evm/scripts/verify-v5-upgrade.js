const { ethers } = require("hardhat");

async function main() {
  const PROXY = "0x97b6d6A8f2c6AF6e6fb40f8d36d60DF2fFE4f17B";
  const game = await ethers.getContractAt("BuxBoosterGame", PROXY);

  console.log("=== Checking if V5 functions exist ===\n");

  // Check if rogueBankroll is set
  try {
    const rogueBankroll = await game.rogueBankroll();
    console.log("✅ rogueBankroll() callable - returns:", rogueBankroll);

    if (rogueBankroll === "0x0000000000000000000000000000000000000000") {
      console.log("❌ ROGUEBankroll not initialized (zero address)!");
    } else {
      console.log("✅ ROGUEBankroll initialized correctly");
    }
  } catch (error) {
    console.log("❌ rogueBankroll() NOT callable:", error.message.slice(0, 100));
    console.log("   This means V5 upgrade may not have been deployed correctly!");
  }

  // Check if placeBetROGUE function exists in the ABI
  try {
    const functionFragment = game.interface.getFunction("placeBetROGUE");
    console.log("\n✅ placeBetROGUE function exists in ABI");
    console.log("   Selector:", functionFragment.selector);
    console.log("   Signature:", functionFragment.format());
  } catch (error) {
    console.log("\n❌ placeBetROGUE function NOT in ABI:", error.message);
  }

  // Check ROGUE_TOKEN constant
  try {
    const rogueToken = await game.ROGUE_TOKEN();
    console.log("\n✅ ROGUE_TOKEN:", rogueToken);
    console.log("   Correct zero address?", rogueToken === "0x0000000000000000000000000000000000000000" ? "✅" : "❌");
  } catch (error) {
    console.log("\n❌ ROGUE_TOKEN not accessible:", error.message.slice(0, 100));
  }

  // Check getMaxBetROGUE function
  try {
    const maxBet = await game.getMaxBetROGUE(1);
    console.log("\n✅ getMaxBetROGUE(1):", ethers.formatEther(maxBet), "ROGUE");
  } catch (error) {
    console.log("\n❌ getMaxBetROGUE() failed:", error.message.slice(0, 100));
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
