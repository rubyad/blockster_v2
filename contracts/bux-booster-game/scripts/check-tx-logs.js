const { ethers } = require("hardhat");

async function main() {
  const txHash = "0x2a39ef49355ab1b9334d4656a7c358b340b40abd6ad65b8d0e48e0dd70653fac";

  console.log("=== Analyzing Transaction Logs ===\n");

  const receipt = await ethers.provider.getTransactionReceipt(txHash);

  console.log("Total logs:", receipt.logs.length);

  for (let i = 0; i < receipt.logs.length; i++) {
    const log = receipt.logs[i];
    console.log(`\nLog ${i}:`);
    console.log("  Address:", log.address);
    console.log("  Topics:", log.topics.length);
    console.log("  Topic[0] (event signature):", log.topics[0]);

    // Try to decode with various interfaces
    // EntryPoint events
    const entryPointInterface = new ethers.Interface([
      "event UserOperationEvent(bytes32 indexed userOpHash, address indexed sender, address indexed paymaster, uint256 nonce, bool success, uint256 actualGasCost, uint256 actualGasUsed)",
      "event UserOperationRevertReason(bytes32 indexed userOpHash, address indexed sender, uint256 nonce, bytes revertReason)"
    ]);

    // BuxBoosterGame events
    const gameInterface = new ethers.Interface([
      "event BetPlaced(bytes32 indexed betId, address indexed player, address indexed token, uint256 amount, int8 difficulty, uint8[] predictions, uint256 nonce)",
      "event CommitmentSubmitted(bytes32 indexed commitmentHash, address indexed player, uint256 nonce, uint256 timestamp)"
    ]);

    // ROGUEBankroll events
    const bankrollInterface = new ethers.Interface([
      "event BuxBoosterBetPlaced(address indexed player, bytes32 indexed commitmentHash, uint256 wagerAmount, int8 difficulty, uint8[] predictions, uint256 nonce, uint256 timestamp)"
    ]);

    try {
      const parsed = entryPointInterface.parseLog(log);
      if (parsed) {
        console.log("  ✅ EntryPoint event:", parsed.name);
        if (parsed.name === "UserOperationEvent") {
          console.log("     Success:", parsed.args.success);
          console.log("     Gas used:", parsed.args.actualGasUsed.toString());
        }
      }
    } catch (e) {}

    try {
      const parsed = gameInterface.parseLog(log);
      if (parsed) {
        console.log("  ✅ BuxBoosterGame event:", parsed.name);
      }
    } catch (e) {}

    try {
      const parsed = bankrollInterface.parseLog(log);
      if (parsed) {
        console.log("  ✅ ROGUEBankroll event:", parsed.name);
      }
    } catch (e) {}
  }

  console.log("\n=== Analysis ===");
  console.log("If no BetPlaced or BuxBoosterBetPlaced events, the transaction reverted before reaching that point.");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
