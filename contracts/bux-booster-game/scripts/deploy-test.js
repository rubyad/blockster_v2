const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying TestDeploy with:", deployer.address);

  const nonce = await deployer.getNonce();
  console.log("Nonce:", nonce);

  const TestDeploy = await ethers.getContractFactory("TestDeploy");
  const contract = await TestDeploy.deploy({
    gasLimit: 500000,
    gasPrice: 1000000000000
  });
  await contract.waitForDeployment();
  console.log("TestDeploy deployed to:", await contract.getAddress());
}

main().catch(console.error);
