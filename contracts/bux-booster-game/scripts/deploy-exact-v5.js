const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying with:", deployer.address);

  const nonce = await deployer.getNonce();
  console.log("Nonce:", nonce);

  const BuxBoosterGame = await ethers.getContractFactory("BuxBoosterGame");
  console.log("Bytecode size:", BuxBoosterGame.bytecode.length / 2, "bytes");
  
  // Use exact same gas settings as V5 deployment tx
  const contract = await BuxBoosterGame.deploy({
    gasLimit: 3878738,
    gasPrice: 1000000000000,  // 1000 gwei
    type: 0  // Legacy transaction
  });
  await contract.waitForDeployment();
  console.log("Deployed to:", await contract.getAddress());
}

main().catch(console.error);
