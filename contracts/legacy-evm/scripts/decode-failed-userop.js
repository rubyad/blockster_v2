const { ethers } = require("hardhat");

async function main() {
  const txHash = "0x2a39ef49355ab1b9334d4656a7c358b340b40abd6ad65b8d0e48e0dd70653fac";

  console.log("=== Analyzing Failed UserOp ===");

  const receipt = await ethers.provider.getTransactionReceipt(txHash);

  console.log("\nTransaction Status:", receipt.status === 1 ? "Success" : "Failed");
  console.log("Gas Used:", receipt.gasUsed.toString());

  // Look for UserOperationRevertReason event
  const entryPointInterface = new ethers.Interface([
    "event UserOperationRevertReason(bytes32 indexed userOpHash, address indexed sender, uint256 nonce, bytes revertReason)",
    "event UserOperationEvent(bytes32 indexed userOpHash, address indexed sender, address indexed paymaster, uint256 nonce, bool success, uint256 actualGasCost, uint256 actualGasUsed)"
  ]);

  console.log("\n=== Events ===");
  for (const log of receipt.logs) {
    try {
      const parsed = entryPointInterface.parseLog({
        topics: log.topics,
        data: log.data
      });

      if (parsed) {
        console.log("\nEvent:", parsed.name);
        if (parsed.name === "UserOperationRevertReason") {
          console.log("UserOpHash:", parsed.args.userOpHash);
          console.log("Sender:", parsed.args.sender);
          console.log("Nonce:", parsed.args.nonce.toString());
          console.log("Revert Reason (raw):", parsed.args.revertReason);

          // Try to decode the revert reason
          try {
            const reason = ethers.toUtf8String(parsed.args.revertReason);
            console.log("Revert Reason (decoded):", reason);
          } catch (e) {
            // Try to decode as error selector
            const selector = parsed.args.revertReason.slice(0, 10);
            console.log("Error Selector:", selector);

            // Common BuxBoosterGame errors
            const errors = {
              "0x82b42900": "InvalidToken()",
              "0x3e237976": "BetAmountTooLow()",
              "0x356680b7": "BetAmountTooHigh()",
              "0x0a76b6e2": "InvalidDifficulty()",
              "0x1c72346d": "InvalidPredictions()",
              "0xc3d22d4e": "BetNotFound()",
              "0xd81b2f2e": "CommitmentNotFound()",
              "0x8baa579f": "UnauthorizedSettler()"
            };

            if (errors[selector]) {
              console.log("Decoded Error:", errors[selector]);
            }
          }
        } else if (parsed.name === "UserOperationEvent") {
          console.log("UserOpHash:", parsed.args.userOpHash);
          console.log("Sender:", parsed.args.sender);
          console.log("Paymaster:", parsed.args.paymaster);
          console.log("Success:", parsed.args.success);
          console.log("Gas Cost:", ethers.formatEther(parsed.args.actualGasCost), "ROGUE");
          console.log("Gas Used:", parsed.args.actualGasUsed.toString());
        }
      }
    } catch (e) {
      // Skip logs that don't match our interface
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
