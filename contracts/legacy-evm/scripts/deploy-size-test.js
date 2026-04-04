const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();

  const C = await ethers.getContractFactory("SizeTest5000");
  console.log("Bytecode:", C.bytecode.length / 2, "bytes");
  
  const contract = await C.deploy({
    gasLimit: 2000000,
    gasPrice: 1000000000000
  });
  await contract.waitForDeployment();
  console.log("SUCCESS! Deployed to:", await contract.getAddress());
}

main().catch(e => console.log("FAILED"));
