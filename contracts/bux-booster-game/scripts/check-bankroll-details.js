const { ethers } = require("hardhat");

async function main() {
  const ROGUE_BANKROLL = "0x51DB4eD2b69b598Fade1aCB5289C7426604AB2fd";
  
  const abi = [
    'event BuxBoosterBetPlaced(address indexed player, uint256 betAmount, uint256 timestamp)',
    'event BuxBoosterWinningPayout(address indexed player, uint256 amount)',
    'event BuxBoosterLosingBet(address indexed player, uint256 amount)',
    'function getBuxBoosterAccounting() external view returns (uint256 totalBets, uint256 totalWins, uint256 totalLosses, uint256 totalVolumeWagered, uint256 totalPayouts, int256 totalHouseProfit, uint256 largestWin, uint256 largestBet, uint256 winRate, int256 houseEdge)'
  ];
  
  const [signer] = await ethers.getSigners();
  const contract = new ethers.Contract(ROGUE_BANKROLL, abi, signer);
  
  // Get accounting data
  const accounting = await contract.getBuxBoosterAccounting();
  console.log("ROGUEBankroll Accounting:");
  console.log("  Total Bets: " + accounting.totalBets.toString());
  console.log("  Total Wins: " + accounting.totalWins.toString());
  console.log("  Total Losses: " + accounting.totalLosses.toString());
  console.log("  Unsettled: " + (Number(accounting.totalBets) - Number(accounting.totalWins) - Number(accounting.totalLosses)));
  console.log("  Volume Wagered: " + ethers.formatEther(accounting.totalVolumeWagered) + " ROGUE");
  console.log("  Total Payouts: " + ethers.formatEther(accounting.totalPayouts) + " ROGUE");
  console.log("  House Profit: " + ethers.formatEther(accounting.totalHouseProfit) + " ROGUE");
  console.log("");
  
  // Get BetPlaced events
  const betFilter = contract.filters.BuxBoosterBetPlaced();
  const betEvents = await contract.queryFilter(betFilter, 0, "latest");
  console.log("BuxBoosterBetPlaced events: " + betEvents.length);
  
  for (const event of betEvents) {
    const player = event.args.player;
    const amount = ethers.formatEther(event.args.betAmount);
    console.log("  Block " + event.blockNumber + ": " + player.substring(0, 10) + "... bet " + amount + " ROGUE");
  }
  
  // Get WinningPayout events
  const winFilter = contract.filters.BuxBoosterWinningPayout();
  const winEvents = await contract.queryFilter(winFilter, 0, "latest");
  console.log("\nBuxBoosterWinningPayout events: " + winEvents.length);
  
  for (const event of winEvents) {
    const player = event.args.player;
    const amount = ethers.formatEther(event.args.amount);
    console.log("  Block " + event.blockNumber + ": " + player.substring(0, 10) + "... won " + amount + " ROGUE");
  }
  
  // Get LosingBet events
  const lossFilter = contract.filters.BuxBoosterLosingBet();
  const lossEvents = await contract.queryFilter(lossFilter, 0, "latest");
  console.log("\nBuxBoosterLosingBet events: " + lossEvents.length);
  
  for (const event of lossEvents) {
    const player = event.args.player;
    const amount = ethers.formatEther(event.args.amount);
    console.log("  Block " + event.blockNumber + ": " + player.substring(0, 10) + "... lost " + amount + " ROGUE");
  }
}

main().catch(console.error);
