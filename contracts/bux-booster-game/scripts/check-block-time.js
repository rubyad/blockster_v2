const { ethers } = require("hardhat");

async function main() {
  const provider = new ethers.JsonRpcProvider("https://rpc.roguechain.io/rpc");
  
  // Check recent block
  const block = await provider.getBlock("latest");
  console.log("Latest block:", block.number);
  console.log("Block timestamp:", block.timestamp);
  console.log("Block date:", new Date(block.timestamp * 1000).toISOString());
  console.log("System date:", new Date().toISOString());
  
  // Check the specific block from the event
  const eventBlock = await provider.getBlock(109375026);
  console.log("\nEvent block 109375026:");
  console.log("Block timestamp:", eventBlock.timestamp);
  console.log("Block date:", new Date(eventBlock.timestamp * 1000).toISOString());
}

main();
