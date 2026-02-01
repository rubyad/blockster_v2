const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying BuxBoosterGame with:", deployer.address);

  const nonce = await deployer.getNonce();
  console.log("Nonce:", nonce);

  const BuxBoosterGame = await ethers.getContractFactory("BuxBoosterGame");
  console.log("Bytecode size:", BuxBoosterGame.bytecode.length / 2, "bytes");
  
  console.log("Deploying (using hardhat.config gas settings)...");
  const contract = await BuxBoosterGame.deploy();  // No explicit gas params
  await contract.waitForDeployment();
  console.log("BuxBoosterGame deployed to:", await contract.getAddress());
}

main().catch(console.error);
