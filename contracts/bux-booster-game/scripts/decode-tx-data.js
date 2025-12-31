const { ethers } = require("hardhat");

async function main() {
  const txHash = "0x2a39ef49355ab1b9334d4656a7c358b340b40abd6ad65b8d0e48e0dd70653fac";

  const tx = await ethers.provider.getTransaction(txHash);

  console.log("=== Transaction Details ===");
  console.log("From (EntryPoint caller):", tx.from);
  console.log("To (EntryPoint):", tx.to);
  console.log("Value:", ethers.formatEther(tx.value), "ROGUE");

  // Decode the handleOps call
  const entryPointInterface = new ethers.Interface([
    "function handleOps((address sender, uint256 nonce, bytes initCode, bytes callData, uint256 callGasLimit, uint256 verificationGasLimit, uint256 preVerificationGas, uint256 maxFeePerGas, uint256 maxPriorityFeePerGas, bytes paymasterAndData, bytes signature)[] ops, address beneficiary)"
  ]);

  try {
    const decoded = entryPointInterface.parseTransaction({
      data: tx.data,
      value: tx.value
    });

    console.log("\n=== UserOperation ===");
    const userOp = decoded.args[0][0]; // First UserOp in the array
    console.log("Sender (Smart Wallet):", userOp.sender);
    console.log("Nonce:", userOp.nonce.toString());
    console.log("Call Gas Limit:", userOp.callGasLimit.toString());

    // Decode the callData (what the smart wallet is executing)
    console.log("\n=== Smart Wallet Execute Call ===");
    const smartWalletInterface = new ethers.Interface([
      "function execute(address dest, uint256 value, bytes calldata func)"
    ]);

    const executeCall = smartWalletInterface.parseTransaction({
      data: userOp.callData
    });

    console.log("Target Contract:", executeCall.args[0]);
    console.log("Value to send:", ethers.formatEther(executeCall.args[1]), "ROGUE");
    console.log("Function call data:", executeCall.args[2].slice(0, 10), "...");

    // Decode the BuxBoosterGame call
    const gameInterface = new ethers.Interface([
      "function placeBetROGUE(uint256 amount, int8 difficulty, uint8[] calldata predictions, bytes32 commitmentHash) external payable"
    ]);

    const gameCall = gameInterface.parseTransaction({
      data: executeCall.args[2]
    });

    console.log("\n=== placeBetROGUE Call ===");
    console.log("Amount:", ethers.formatEther(gameCall.args[0]), "ROGUE");
    console.log("Difficulty:", gameCall.args[1].toString());
    console.log("Predictions:", gameCall.args[2].toString());
    console.log("Commitment Hash:", gameCall.args[3]);

    // Check if value matches amount
    const amountWei = gameCall.args[0];
    const valueWei = executeCall.args[1];

    if (amountWei !== valueWei) {
      console.log("\n❌ MISMATCH: amount parameter doesn't match msg.value!");
      console.log("   Amount param:", ethers.formatEther(amountWei), "ROGUE");
      console.log("   msg.value:", ethers.formatEther(valueWei), "ROGUE");
    } else {
      console.log("\n✅ Amount and value match correctly");
    }
  } catch (error) {
    console.error("Error decoding:", error.message);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
