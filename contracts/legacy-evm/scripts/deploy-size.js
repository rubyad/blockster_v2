const { ethers } = require("hardhat");

async function main() {
  const name = process.argv[2] || "SizeTest8000";
  const [deployer] = await ethers.getSigners();
  console.log(`Deploying ${name}...`);

  const C = await ethers.getContractFactory(name);
  console.log("Bytecode size:", C.bytecode.length / 2, "bytes");
  
  const contract = await C.deploy({
    gasLimit: 2000000,
    gasPrice: 1000000000000
  });
  await contract.waitForDeployment();
  console.log("Deployed to:", await contract.getAddress());
}

main().catch(e => console.log("FAILED:", e.message.split("\n")[0]));
