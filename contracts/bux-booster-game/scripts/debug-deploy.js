const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Debug deployment with account:", deployer.address);
  
  const nonce = await deployer.getNonce();
  console.log("Nonce:", nonce);
  
  const BuxBoosterGame = await ethers.getContractFactory("BuxBoosterGame");
  
  // Get the deployment transaction data without sending
  const deployTx = await BuxBoosterGame.getDeployTransaction({
    gasLimit: 3000000,
    gasPrice: 1000000000000,
    nonce: nonce
  });
  
  console.log("Deploy tx data length:", deployTx.data.length);
  console.log("Gas limit:", deployTx.gasLimit?.toString());
  console.log("Gas price:", deployTx.gasPrice?.toString());
  console.log("Nonce:", deployTx.nonce);
  console.log("To:", deployTx.to);  // Should be null for contract creation
  
  // Try to send via raw provider to see actual error
  console.log("\nSending raw transaction...");
  try {
    const signedTx = await deployer.signTransaction(deployTx);
    console.log("Signed TX length:", signedTx.length);
    console.log("First 100 chars:", signedTx.substring(0, 100));
    
    const result = await ethers.provider.send("eth_sendRawTransaction", [signedTx]);
    console.log("Result:", result);
  } catch (error) {
    console.error("Error:", error.message);
    if (error.info) {
      console.error("Info:", JSON.stringify(error.info, null, 2));
    }
    if (error.error) {
      console.error("Inner error:", error.error);
    }
  }
}

main().catch(console.error);
