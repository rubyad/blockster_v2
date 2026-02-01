const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Testing with account:", deployer.address);
  
  const balance = await ethers.provider.getBalance(deployer.address);
  console.log("Balance:", ethers.formatEther(balance), "ROGUE");
  
  const nonce = await deployer.getNonce();
  console.log("Nonce:", nonce);
  
  // Try sending a simple transaction to self
  console.log("\nSending test transaction...");
  try {
    const tx = await deployer.sendTransaction({
      to: deployer.address,
      value: 0,
      gasLimit: 21000,
      gasPrice: 1000000000000,
      nonce: nonce
    });
    console.log("TX hash:", tx.hash);
    await tx.wait();
    console.log("Test transaction succeeded!");
  } catch (error) {
    console.error("Test tx failed:", error.message);
    if (error.data) {
      console.error("Error data:", error.data);
    }
  }
}

main().catch(console.error);
