const { ethers } = require("hardhat");

async function main() {
  const BANKROLL = "0x51DB4eD2b69b598Fade1aCB5289C7426604AB2fd";

  console.log("=== BuxBooster Accounting Snapshot ===\n");

  const bankroll = await ethers.getContractAt("ROGUEBankroll", BANKROLL);

  try {
    const accounting = await bankroll.getBuxBoosterAccounting();

    console.log("📊 Overall Statistics:");
    console.log("  Total Bets:", accounting.totalBets.toString());
    console.log("  Total Wins:", accounting.totalWins.toString());
    console.log("  Total Losses:", accounting.totalLosses.toString());
    console.log("  Win Rate:", (Number(accounting.winRate) / 100).toFixed(2) + "%");

    console.log("\n💰 Volume & Payouts:");
    console.log("  Total Volume Wagered:", ethers.formatEther(accounting.totalVolumeWagered), "ROGUE");
    console.log("  Total Payouts:", ethers.formatEther(accounting.totalPayouts), "ROGUE");

    console.log("\n🏦 House Performance:");
    const houseProfit = accounting.totalHouseProfit;
    const isProfitable = houseProfit >= 0;
    console.log("  House Profit/Loss:", (isProfitable ? "+" : "") + ethers.formatEther(houseProfit), "ROGUE");
    console.log("  House Edge:", (Number(accounting.houseEdge) / 100).toFixed(2) + "%");
    console.log("  Status:", isProfitable ? "✅ Profitable" : "⚠️  In Loss");

    console.log("\n🎯 Records:");
    console.log("  Largest Win:", ethers.formatEther(accounting.largestWin), "ROGUE");
    console.log("  Largest Bet:", ethers.formatEther(accounting.largestBet), "ROGUE");

    // Calculate some additional stats
    if (accounting.totalBets > 0) {
      const avgBetSize = accounting.totalVolumeWagered / accounting.totalBets;
      console.log("\n📈 Averages:");
      console.log("  Average Bet Size:", ethers.formatEther(avgBetSize), "ROGUE");

      if (accounting.totalWins > 0) {
        const avgPayout = accounting.totalPayouts / accounting.totalWins;
        console.log("  Average Payout:", ethers.formatEther(avgPayout), "ROGUE");
      }
    }

    // ROI for house
    if (accounting.totalVolumeWagered > 0) {
      const roi = (Number(accounting.totalHouseProfit) * 100) / Number(accounting.totalVolumeWagered);
      console.log("\n💹 House ROI:", roi.toFixed(4) + "%");
    }

  } catch (error) {
    console.error("Error fetching accounting:", error.message);
    console.log("\nNote: This function may not exist if the contract hasn't been upgraded yet.");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
