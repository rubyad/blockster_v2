const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Debug deployment with account:", deployer.address);
  
  const nonce = await deployer.getNonce();
  console.log("Nonce:", nonce);
  
  const BuxBoosterGame = await ethers.getContractFactory("BuxBoosterGame");
  
  // Get bytecode
  const bytecode = BuxBoosterGame.bytecode;
  console.log("Bytecode length:", bytecode.length);
  console.log("Bytecode size (bytes):", bytecode.length / 2);
  
  // Check if bytecode contains 0x prefix and is valid hex
  console.log("Starts with 0x:", bytecode.startsWith("0x"));
  console.log("Valid hex:", /^0x[0-9a-fA-F]*$/.test(bytecode));
  
  // Try eth_call to simulate the deployment
  console.log("\nSimulating deployment via eth_call...");
  try {
    const result = await ethers.provider.send("eth_call", [{
      from: deployer.address,
      data: bytecode,
      gas: "0x2DC6C0"  // 3000000 in hex
    }, "latest"]);
    console.log("eth_call result length:", result.length);
  } catch (error) {
    console.error("eth_call error:", error.message);
    if (error.data) {
      console.error("Error data:", error.data);
    }
  }
}

main().catch(console.error);
