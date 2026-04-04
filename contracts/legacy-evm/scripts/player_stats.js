const { ethers } = require("ethers");

const RPC_URL = "https://rpc.roguechain.io/rpc";
const PLAYER_ADDRESS = "0xb6b4cb36ce26d62fe02402ef43cb489183b2a137";

const BUX_BOOSTER_GAME_ADDRESS = "0x97b6d6A8f2c6AF6e6fb40f8d36d60DF2fFE4f17B";
const ROGUE_BANKROLL_ADDRESS = "0x51DB4eD2b69b598Fade1aCB5289C7426604AB2fd";

const BUX_ABI = [
  "function playerStats(address) external view returns (uint256 totalBets, uint256 totalStaked, int256 overallProfitLoss, uint256[9] betsPerDifficulty, int256[9] profitLossPerDifficulty)"
];

const ROGUE_ABI = [
  "function buxBoosterPlayerStats(address) external view returns (uint256 totalBets, uint256 wins, uint256 losses, uint256 totalWagered, uint256 totalWinnings, uint256 totalLosses)"
];

const DIFFICULTIES = [
  { level: -4, name: "Win One (5 flips)", mult: "1.02x" },
  { level: -3, name: "Win One (4 flips)", mult: "1.05x" },
  { level: -2, name: "Win One (3 flips)", mult: "1.13x" },
  { level: -1, name: "Win One (2 flips)", mult: "1.32x" },
  { level: 0, name: "Single Flip", mult: "1.98x" },
  { level: 1, name: "Win All (2 flips)", mult: "3.96x" },
  { level: 2, name: "Win All (3 flips)", mult: "7.92x" },
  { level: 3, name: "Win All (4 flips)", mult: "15.84x" },
  { level: 4, name: "Win All (5 flips)", mult: "31.68x" }
];

async function main() {
  const provider = new ethers.JsonRpcProvider(RPC_URL);
  
  console.log("\n=== Player Stats for " + PLAYER_ADDRESS + " ===\n");
  
  // BUX stats
  try {
    const buxBooster = new ethers.Contract(BUX_BOOSTER_GAME_ADDRESS, BUX_ABI, provider);
    const stats = await buxBooster.playerStats(PLAYER_ADDRESS);
    
    console.log("--- BUX Betting Stats ---");
    console.log("Total Bets:       ", stats.totalBets.toString());
    console.log("Total Staked:     ", ethers.formatEther(stats.totalStaked), "BUX");
    console.log("Net Profit/Loss:  ", ethers.formatEther(stats.overallProfitLoss), "BUX");
    console.log("");
    console.log("Per-Difficulty Breakdown:");
    for (let i = 0; i < 9; i++) {
      const bets = stats.betsPerDifficulty[i];
      const pnl = stats.profitLossPerDifficulty[i];
      if (bets > 0n) {
        console.log("  " + DIFFICULTIES[i].name + " (" + DIFFICULTIES[i].mult + "): " + bets + " bets, P/L: " + ethers.formatEther(pnl) + " BUX");
      }
    }
  } catch (err) {
    console.log("BUX Stats Error:", err.message);
  }
  
  console.log("");
  
  // ROGUE stats
  try {
    const rogueBankroll = new ethers.Contract(ROGUE_BANKROLL_ADDRESS, ROGUE_ABI, provider);
    const stats = await rogueBankroll.buxBoosterPlayerStats(PLAYER_ADDRESS);
    
    console.log("--- ROGUE Betting Stats ---");
    console.log("Total Bets:       ", stats.totalBets.toString());
    console.log("Wins:             ", stats.wins.toString());
    console.log("Losses:           ", stats.losses.toString());
    const winRate = stats.totalBets > 0 ? ((Number(stats.wins) / Number(stats.totalBets)) * 100).toFixed(2) + "%" : "N/A";
    console.log("Win Rate:         ", winRate);
    console.log("Total Wagered:    ", ethers.formatEther(stats.totalWagered), "ROGUE");
    console.log("Total Winnings:   ", ethers.formatEther(stats.totalWinnings), "ROGUE");
    console.log("Total Losses:     ", ethers.formatEther(stats.totalLosses), "ROGUE");
    const netPnL = BigInt(stats.totalWinnings) - BigInt(stats.totalLosses);
    console.log("Net Profit/Loss:  ", ethers.formatEther(netPnL), "ROGUE");
  } catch (err) {
    console.log("ROGUE Stats Error:", err.message);
  }
}

main();
