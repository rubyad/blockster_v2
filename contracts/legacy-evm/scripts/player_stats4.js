const { ethers } = require("ethers");

const RPC_URL = "https://rpc.roguechain.io/rpc";
const PLAYER_ADDRESS = "0xb6b4cb36ce26d62fe02402ef43cb489183b2a137";

const BUX_BOOSTER_GAME_ADDRESS = "0x97b6d6A8f2c6AF6e6fb40f8d36d60DF2fFE4f17B";
const ROGUE_BANKROLL_ADDRESS = "0x51DB4eD2b69b598Fade1aCB5289C7426604AB2fd";

const COMBINED_ABI = [
  "function getPlayerStats(address player) external view returns (uint256 totalBets, uint256 totalStaked, int256 overallProfitLoss, uint256[9] betsPerDifficulty, int256[9] profitLossPerDifficulty)"
];

const ROGUE_ABI = [
  "function buxBoosterPlayerStats(address) external view returns (uint256 totalBets, uint256 wins, uint256 losses, uint256 totalWagered, uint256 totalWinnings, uint256 totalLosses)"
];

async function main() {
  const provider = new ethers.JsonRpcProvider(RPC_URL);
  
  console.log("\n=== Player Stats for " + PLAYER_ADDRESS + " ===\n");
  
  // Get combined stats
  const buxBooster = new ethers.Contract(BUX_BOOSTER_GAME_ADDRESS, COMBINED_ABI, provider);
  const combined = await buxBooster.getPlayerStats(PLAYER_ADDRESS);
  
  // Get ROGUE-only stats
  const rogueBankroll = new ethers.Contract(ROGUE_BANKROLL_ADDRESS, ROGUE_ABI, provider);
  const rogue = await rogueBankroll.buxBoosterPlayerStats(PLAYER_ADDRESS);
  
  // Calculate BUX-only stats by subtracting ROGUE from combined
  const buxBets = BigInt(combined.totalBets) - BigInt(rogue.totalBets);
  const buxStaked = BigInt(combined.totalStaked) - BigInt(rogue.totalWagered);
  
  // For P/L: ROGUE net = totalWinnings - totalLosses
  const rogueNetPnL = BigInt(rogue.totalWinnings) - BigInt(rogue.totalLosses);
  const buxPnL = BigInt(combined.overallProfitLoss) - rogueNetPnL;
  
  console.log("--- BUX Stats (calculated: combined minus ROGUE) ---");
  console.log("Total Bets:       ", buxBets.toString());
  console.log("Total Staked:     ", ethers.formatEther(buxStaked), "BUX");
  console.log("Net Profit/Loss:  ", ethers.formatEther(buxPnL), "BUX");
  
  console.log("\n");
  
  console.log("--- ROGUE Stats (from ROGUEBankroll) ---");
  console.log("Total Bets:       ", rogue.totalBets.toString());
  console.log("Wins:             ", rogue.wins.toString());
  console.log("Losses:           ", rogue.losses.toString());
  const winRate = rogue.totalBets > 0 ? ((Number(rogue.wins) / Number(rogue.totalBets)) * 100).toFixed(2) + "%" : "N/A";
  console.log("Win Rate:         ", winRate);
  console.log("Total Wagered:    ", ethers.formatEther(rogue.totalWagered), "ROGUE");
  console.log("Total Winnings:   ", ethers.formatEther(rogue.totalWinnings), "ROGUE");
  console.log("Total Losses:     ", ethers.formatEther(rogue.totalLosses), "ROGUE");
  console.log("Net Profit/Loss:  ", ethers.formatEther(rogueNetPnL), "ROGUE");
  
  console.log("\n");
  
  console.log("--- Combined Stats (from BuxBoosterGame) ---");
  console.log("Total Bets:       ", combined.totalBets.toString());
  console.log("Total Staked:     ", ethers.formatEther(combined.totalStaked));
  console.log("Net Profit/Loss:  ", ethers.formatEther(combined.overallProfitLoss));
}

main();
