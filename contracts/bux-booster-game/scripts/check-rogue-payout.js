const { ethers } = require("hardhat");

async function main() {
  const BANKROLL = "0x51DB4eD2b69b598Fade1aCB5289C7426604AB2fd";
  const WALLET = "0xB6B4cb36ce26D62fE02402EF43cB489183B2A137";

  console.log("=== Checking ROGUE Payouts ===\n");

  const bankroll = await ethers.getContractAt("ROGUEBankroll", BANKROLL);

  // Check if there's any credited balance (from failed payouts)
  try {
    const playerInfo = await bankroll.players(WALLET);
    const creditedBalance = playerInfo.rogue_balance;
    console.log("Credited balance (from failed payouts):", ethers.formatEther(creditedBalance), "ROGUE");

    if (creditedBalance > 0) {
      console.log("⚠️  You have unclaimed winnings! Call withdrawRogueBalance() to claim.");
    }
  } catch (error) {
    console.log("Could not read player info:", error.message.slice(0, 100));
  }

  // Get recent events
  console.log("\n=== Recent BuxBooster Events (last 1000 blocks) ===");

  const currentBlock = await ethers.provider.getBlockNumber();
  const fromBlock = currentBlock - 1000;

  // Check for winning payouts
  const winningFilter = bankroll.filters.BuxBoosterWinningPayout(WALLET);
  const winningEvents = await bankroll.queryFilter(winningFilter, fromBlock);

  console.log(`\nWinning Payouts: ${winningEvents.length}`);
  for (const event of winningEvents) {
    console.log(`  Block ${event.blockNumber}:`);
    console.log(`    Commitment: ${event.args.commitmentHash}`);
    console.log(`    Bet Amount: ${ethers.formatEther(event.args.betAmount)} ROGUE`);
    console.log(`    Payout: ${ethers.formatEther(event.args.payout)} ROGUE`);
    console.log(`    Profit: ${ethers.formatEther(event.args.profit)} ROGUE`);
    console.log(`    TX: ${event.transactionHash}`);
  }

  // Check for failed payouts
  const failedFilter = bankroll.filters.BuxBoosterPayoutFailed(WALLET);
  const failedEvents = await bankroll.queryFilter(failedFilter, fromBlock);

  console.log(`\nFailed Payouts (credited to balance): ${failedEvents.length}`);
  for (const event of failedEvents) {
    console.log(`  Block ${event.blockNumber}:`);
    console.log(`    Commitment: ${event.args.commitmentHash}`);
    console.log(`    Payout: ${ethers.formatEther(event.args.payout)} ROGUE`);
    console.log(`    TX: ${event.transactionHash}`);
    console.log(`    ⚠️  Payout was credited to your bankroll balance - call withdrawRogueBalance()`);
  }

  // Check wallet balance
  console.log("\n=== Wallet Balance ===");
  const walletBalance = await ethers.provider.getBalance(WALLET);
  console.log("Current ROGUE balance:", ethers.formatEther(walletBalance), "ROGUE");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
