const { ethers } = require("hardhat");

async function main() {
  // Error selectors from the logs
  const errors = [
    { selector: "0xb3679761", context: "First bet settlement failure" },
    { selector: "0x469bfa91", context: "Second bet settlement failure" }
  ];
  
  // Common error signatures
  const errorSignatures = {
    "0xb3679761": "BetNotFound()",
    "0x469bfa91": "BetAlreadySettled()",
    "0x3ee5aeb5": "MathOverflowedMulDiv()",
    "0x2f4e9ee8": "InvalidServerSeed()",
    "0x8baa579f": "InsufficientBalance()",
    "0xf4d678b8": "InsufficientHouseBalance()",
    "0xcd786059": "Unauthorized()"
  };
  
  console.log("Error Selector Decoding:\n");
  for (const error of errors) {
    const decoded = errorSignatures[error.selector] || "Unknown error";
    console.log("Selector: " + error.selector);
    console.log("  Error: " + decoded);
    console.log("  Context: " + error.context);
    console.log("");
  }
  
  // Let's also check the contract for error definitions
  const BuxBoosterGame = await ethers.getContractFactory("BuxBoosterGame");
  const interface = BuxBoosterGame.interface;
  
  console.log("BuxBoosterGame Error Definitions:");
  for (const [name, fragment] of Object.entries(interface.fragments)) {
    if (fragment.type === "error") {
      const selector = interface.getError(fragment.name).selector;
      console.log("  " + fragment.name + ": " + selector);
    }
  }
}

main().catch(console.error);
