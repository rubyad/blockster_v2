const { ethers } = require("hardhat");

async function main() {
  const PROXY_ADDRESS = "0x97b6d6A8f2c6AF6e6fb40f8d36d60DF2fFE4f17B";
  
  const [deployer] = await ethers.getSigners();
  console.log("Checking with account:", deployer.address);

  const contract = await ethers.getContractAt("BuxBoosterGame", PROXY_ADDRESS);
  
  const owner = await contract.owner();
  console.log("\nContract owner:", owner);
  console.log("Deployer address:", deployer.address);
  console.log("Is deployer owner?", owner.toLowerCase() === deployer.address.toLowerCase());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
