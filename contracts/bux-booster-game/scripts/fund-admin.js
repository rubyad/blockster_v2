const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  const adminAddress = "0xa86256423DdAf710295f1E64fDE09a72Bed65113";

  console.log("Deployer:", deployer.address);
  console.log("Deployer balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "ROGUE");
  console.log("Admin balance:", ethers.formatEther(await ethers.provider.getBalance(adminAddress)), "ROGUE");

  // Send 500 ROGUE to admin for gas (enough for remaining ~72 batches)
  const amount = ethers.parseEther("500");
  console.log("\nSending 500 ROGUE to admin...");

  const tx = await deployer.sendTransaction({
    to: adminAddress,
    value: amount
  });
  console.log("TX:", tx.hash);
  await tx.wait();

  console.log("✓ Sent 500 ROGUE to admin");
  console.log("Admin new balance:", ethers.formatEther(await ethers.provider.getBalance(adminAddress)), "ROGUE");
}

main().catch(console.error);
