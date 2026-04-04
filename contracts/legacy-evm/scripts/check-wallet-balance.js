const { ethers } = require("hardhat");

async function main() {
  const wallet = "0xB6B4cb36ce26D62fE02402EF43cB489183B2A137";
  const balance = await ethers.provider.getBalance(wallet);
  console.log("Wallet ROGUE balance:", ethers.formatEther(balance), "ROGUE");
  console.log("Bet amount needed: 160.0 ROGUE");
  console.log("Sufficient?", balance >= ethers.parseEther("160") ? "✅ YES" : "❌ NO");

  if (balance < ethers.parseEther("160")) {
    console.log("\n❌ INSUFFICIENT BALANCE - This is why the bet failed!");
    console.log("The smart wallet needs ROGUE to place ROGUE bets.");
    console.log("You need to send ROGUE to the smart wallet address:", wallet);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
