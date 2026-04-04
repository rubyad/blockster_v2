const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying ERC20Upgradeable with:", deployer.address);

  const nonce = await deployer.getNonce();
  console.log("Nonce:", nonce);

  const C = await ethers.getContractFactory("ERC20Upgradeable");
  console.log("Bytecode size:", C.bytecode.length / 2, "bytes");
  
  const contract = await C.deploy({
    gasLimit: 1000000,
    gasPrice: 1000000000000
  });
  await contract.waitForDeployment();
  console.log("Deployed to:", await contract.getAddress());
}

main().catch(console.error);
