const { ethers } = require("hardhat");

async function main() {
  const PROXY_ADDRESS = "0x97b6d6A8f2c6AF6e6fb40f8d36d60DF2fFE4f17B";
  const COMMITMENT_HASH = "0xe9c40ea12c8a65f28abb5c43f75c1f20e7908a88991e36073e82fcef6d24c16a";
  const SMART_WALLET = "0xB6B4cb36ce26D62fE02402EF43cB489183B2A137";

  console.log("=== Debugging CommitmentWrongPlayer Error ===\n");

  const game = await ethers.getContractAt("BuxBoosterGame", PROXY_ADDRESS);

  // Get commitment details
  const commitment = await game.commitments(COMMITMENT_HASH);
  console.log("Commitment details:");
  console.log("  Player (from commitment):", commitment.player);
  console.log("  Smart Wallet (expected):", SMART_WALLET);
  console.log("  Match?", commitment.player.toLowerCase() === SMART_WALLET.toLowerCase() ? "✅" : "❌");

  console.log("\n=== Analysis ===");
  console.log("When placeBetROGUE() is called:");
  console.log("1. EntryPoint (0x5FF137...) calls SmartWallet.execute()");
  console.log("2. SmartWallet (0xB6B4cb...) calls BuxBoosterGame.placeBetROGUE()");
  console.log("3. In placeBetROGUE(), msg.sender should be:", SMART_WALLET);
  console.log("4. Commitment.player is:", commitment.player);
  console.log("5. They should match for validation to pass");

  if (commitment.player.toLowerCase() === SMART_WALLET.toLowerCase()) {
    console.log("\n✅ Addresses match - CommitmentWrongPlayer should NOT occur!");
    console.log("\nPossible explanations:");
    console.log("- The failed transaction might have been from a different address");
    console.log("- There might be multiple transactions trying to use the same commitment");
    console.log("- The smart wallet might be delegating the call differently");
  } else {
    console.log("\n❌ Addresses DON'T match - this IS the problem!");
    console.log("The commitment was submitted for a different player address.");
  }

  // Check the actual failed transaction's from address
  console.log("\n=== Failed Transaction Details ===");
  const tx = await ethers.provider.getTransaction("0x2a39ef49355ab1b9334d4656a7c358b340b40abd6ad65b8d0e48e0dd70653fac");
  const smartWalletInterface = new ethers.Interface([
    "function execute(address dest, uint256 value, bytes calldata func)"
  ]);

  const executeCall = smartWalletInterface.parseTransaction({
    data: tx.callData || tx.data.slice(138) // Skip handleOps selector and offset
  });

  // Actually, we need to decode the UserOp first
  // Let me just check if there's a newer commitment
  console.log("\nLet me check if there's a newer commitment for this player...");

  // Get player's nonce from contract
  const playerState = await game.getPlayerState(SMART_WALLET);
  console.log("Player nonce (on-chain):", playerState.nonce.toString());
  console.log("Commitment nonce:", commitment.nonce.toString());

  if (playerState.nonce > commitment.nonce) {
    console.log("\n⚠️  Player's nonce has advanced! This commitment is outdated.");
    console.log("A newer commitment may have been submitted.");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
