const { ethers } = require("hardhat");

async function main() {
  const txHash = "0x6e53240e6fdb6fc871e946419a4a720c3bc0158d4f609b97e75454c4551370c6";

  console.log("=== Analyzing Settlement Transaction ===\n");

  const receipt = await ethers.provider.getTransactionReceipt(txHash);

  console.log("Status:", receipt.status === 1 ? "✅ Success" : "❌ Failed");
  console.log("Block:", receipt.blockNumber);
  console.log("Gas Used:", receipt.gasUsed.toString());
  console.log("\nLogs:", receipt.logs.length);

  console.log("\n=== All Logs ===");
  for (let i = 0; i < receipt.logs.length; i++) {
    console.log(`\nLog ${i}:`);
    console.log("  Address:", receipt.logs[i].address);
    console.log("  Topics:", receipt.logs[i].topics.length);
    console.log("  Data length:", receipt.logs[i].data.length);
  }

  // ROGUEBankroll events
  const bankrollInterface = new ethers.Interface([
    "event BuxBoosterWinningPayout(address indexed winner, bytes32 indexed commitmentHash, uint256 betAmount, uint256 payout, uint256 profit)",
    "event BuxBoosterPayoutFailed(address indexed player, bytes32 indexed commitmentHash, uint256 payout)",
    "event BuxBoosterLosingBet(address indexed player, bytes32 indexed commitmentHash, uint256 wagerAmount)"
  ]);

  // BuxBoosterGame events
  const gameInterface = new ethers.Interface([
    "event BetSettled(bytes32 indexed betId, address indexed player, bool won, uint8[] results, uint256 payout, bytes32 serverSeed)"
  ]);

  let foundPayout = false;
  let payoutAmount = "0";

  for (const log of receipt.logs) {
    try {
      const parsed = bankrollInterface.parseLog(log);
      if (parsed) {
        console.log(`\n✅ ROGUEBankroll Event: ${parsed.name}`);
        if (parsed.name === "BuxBoosterWinningPayout") {
          console.log("   Winner:", parsed.args.winner);
          console.log("   Bet Amount:", ethers.formatEther(parsed.args.betAmount), "ROGUE");
          console.log("   Payout:", ethers.formatEther(parsed.args.payout), "ROGUE");
          console.log("   Profit:", ethers.formatEther(parsed.args.profit), "ROGUE");
          foundPayout = true;
          payoutAmount = ethers.formatEther(parsed.args.payout);
        } else if (parsed.name === "BuxBoosterPayoutFailed") {
          console.log("   ❌ Payout FAILED - amount credited to bankroll balance");
          console.log("   Player:", parsed.args.player);
          console.log("   Payout:", ethers.formatEther(parsed.args.payout), "ROGUE");
        } else if (parsed.name === "BuxBoosterLosingBet") {
          console.log("   Player lost this bet");
        }
      }
    } catch (e) {}

    try {
      const parsed = gameInterface.parseLog(log);
      if (parsed) {
        console.log(`\n✅ BuxBoosterGame Event: ${parsed.name}`);
        console.log("   Won:", parsed.args.won);
        console.log("   Payout:", ethers.formatEther(parsed.args.payout), "ROGUE");
      }
    } catch (e) {}
  }

  if (foundPayout) {
    console.log(`\n✅ Payout of ${payoutAmount} ROGUE was sent successfully!`);
    console.log("\nThe payout was sent to your smart wallet.");
    console.log("Check your balance at: https://roguescan.io/address/0xB6B4cb36ce26D62fE02402EF43cB489183B2A137");
  } else {
    console.log("\n❌ No payout event found - check if this was a losing bet");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
