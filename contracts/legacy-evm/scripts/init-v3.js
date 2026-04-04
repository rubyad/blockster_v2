const { ethers } = require("hardhat");

async function main() {
  console.log("Calling initializeV3()...");

  const PROXY_ADDRESS = "0x97b6d6A8f2c6AF6e6fb40f8d36d60DF2fFE4f17B";

  // Get contract instance
  const contract = await ethers.getContractAt("BuxBoosterGame", PROXY_ADDRESS);

  console.log("Contract address:", PROXY_ADDRESS);

  try {
    // Call initializeV3
    const tx = await contract.initializeV3({
      gasLimit: 500000,
      gasPrice: ethers.parseUnits("1000", "gwei")
    });

    console.log("Transaction submitted:", tx.hash);
    console.log("Waiting for confirmation...");

    const receipt = await tx.wait();

    console.log("✅ initializeV3() called successfully!");
    console.log("Block number:", receipt.blockNumber);
    console.log("Gas used:", receipt.gasUsed.toString());

  } catch (error) {
    console.error("initializeV3() failed:", error.message);

    if (error.message.includes("InvalidInitialization")) {
      console.log("\n⚠️  Contract may already be initialized to V3");
      console.log("This is OK - the upgrade is complete");
    } else {
      throw error;
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
