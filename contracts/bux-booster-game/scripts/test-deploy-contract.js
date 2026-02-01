const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Testing contract deployment with account:", deployer.address);
  
  const nonce = await deployer.getNonce();
  console.log("Nonce:", nonce);
  
  console.log("\nGetting contract factory...");
  const BuxBoosterGame = await ethers.getContractFactory("BuxBoosterGame");
  
  console.log("Deploying BuxBoosterGame...");
  try {
    const newImpl = await BuxBoosterGame.deploy({
      gasLimit: 3000000,
      gasPrice: 1000000000000,
      nonce: nonce
    });
    console.log("Deploy tx submitted");
    await newImpl.waitForDeployment();
    const address = await newImpl.getAddress();
    console.log("Contract deployed at:", address);
  } catch (error) {
    console.error("Deploy failed:", error.message);
    console.error("Full error:", error);
  }
}

main().catch(console.error);
