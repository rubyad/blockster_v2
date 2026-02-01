const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying BuxBoosterGame (V5 code) with:", deployer.address);

  const nonce = await deployer.getNonce();
  console.log("Nonce:", nonce);

  const BuxBoosterGame = await ethers.getContractFactory("BuxBoosterGame");
  console.log("Bytecode size:", BuxBoosterGame.bytecode.length / 2, "bytes");
  
  const contract = await BuxBoosterGame.deploy({
    gasLimit: 5000000,
    gasPrice: 1000000000000
  });
  await contract.waitForDeployment();
  console.log("BuxBoosterGame deployed to:", await contract.getAddress());
}

main().catch(console.error);
