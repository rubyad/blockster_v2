const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying NFTRewarder with:", deployer.address);

  const nonce = await deployer.getNonce();
  console.log("Nonce:", nonce);

  const NFTRewarder = await ethers.getContractFactory("NFTRewarder");
  console.log("Bytecode size:", NFTRewarder.bytecode.length / 2, "bytes");
  
  const contract = await NFTRewarder.deploy({
    gasLimit: 5000000,
    gasPrice: 1000000000000
  });
  await contract.waitForDeployment();
  console.log("Deployed to:", await contract.getAddress());
}

main().catch(console.error);
