const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  const nonce = await deployer.getNonce();
  console.log("Nonce:", nonce);
  
  const chainId = (await ethers.provider.getNetwork()).chainId;
  console.log("Chain ID:", chainId);
  
  const feeData = await ethers.provider.getFeeData();
  console.log("Gas price:", feeData.gasPrice?.toString());
  console.log("Max fee:", feeData.maxFeePerGas?.toString());
  console.log("Max priority fee:", feeData.maxPriorityFeePerGas?.toString());
}

main().catch(console.error);
