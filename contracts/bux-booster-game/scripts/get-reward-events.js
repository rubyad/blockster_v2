const { ethers } = require("hardhat");

async function main() {
  const provider = new ethers.JsonRpcProvider("https://rpc.roguechain.io/rpc");
  
  const rewarder = new ethers.Contract(
    "0x96aB9560f1407586faE2b69Dc7f38a59BEACC594",
    [
      "event RewardReceived(bytes32 indexed betId, uint256 amount, uint256 timestamp)",
      "function totalRewardsReceived() view returns (uint256)"
    ],
    provider
  );

  // Get total rewards on-chain
  const totalRewards = await rewarder.totalRewardsReceived();
  console.log("Total rewards on-chain:", ethers.formatEther(totalRewards), "ROGUE");

  // Get all RewardReceived events from contract deployment
  const filter = rewarder.filters.RewardReceived();
  const events = await rewarder.queryFilter(filter, 0, "latest");
  
  console.log("\nFound", events.length, "RewardReceived events:");
  
  let total = 0n;
  for (const event of events) {
    const [betId, amount, timestamp] = event.args;
    total += amount;
    console.log({
      betId: betId,
      amount: ethers.formatEther(amount) + " ROGUE",
      timestamp: new Date(Number(timestamp) * 1000).toISOString(),
      blockNumber: event.blockNumber,
      txHash: event.transactionHash
    });
  }
  
  console.log("\nTotal from events:", ethers.formatEther(total), "ROGUE");
}

main();
