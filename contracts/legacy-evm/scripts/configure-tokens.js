/**
 * Configure tokens and deposit house balance for BuxBoosterGame
 */

const { ethers } = require("hardhat");

const CONTRACT_ADDRESS = "0x97b6d6A8f2c6AF6e6fb40f8d36d60DF2fFE4f17B";

// ERC20 ABI for mint and approve
const ERC20_ABI = [
  "function mint(address to, uint256 amount) external",
  "function approve(address spender, uint256 amount) external returns (bool)",
  "function balanceOf(address account) external view returns (uint256)"
];

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Configuring with account:", deployer.address);

  // Get contract
  const BuxBoosterGame = await ethers.getContractFactory("BuxBoosterGame");
  const game = BuxBoosterGame.attach(CONTRACT_ADDRESS);

  // Tokens to configure
  const tokens = [
    { name: "BUX", address: "0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8" },
    { name: "moonBUX", address: "0x08F12025c1cFC4813F21c2325b124F6B6b5cfDF5" },
    { name: "neoBUX", address: "0x423656448374003C2cfEaFF88D5F64fb3A76487C" },
    { name: "rogueBUX", address: "0x56d271b1C1DCF597aA3ee454bCCb265d4Dee47b3" },
    { name: "flareBUX", address: "0xd27EcA9bc2401E8CEf92a14F5Ee9847508EDdaC8" },
    { name: "nftBUX", address: "0x9853e3Abea96985d55E9c6963afbAf1B0C9e49ED" },
    { name: "nolchaBUX", address: "0x4cE5C87FAbE273B58cb4Ef913aDEa5eE15AFb642" },
    { name: "solBUX", address: "0x92434779E281468611237d18AdE20A4f7F29DB38" },
    { name: "spaceBUX", address: "0xAcaCa77FbC674728088f41f6d978F0194cf3d55A" },
    { name: "tronBUX", address: "0x98eDb381281FA02b494FEd76f0D9F3AEFb2Db665" },
    { name: "tranBUX", address: "0xcDdE88C8bacB37Fc669fa6DECE92E3d8FE672d96" }
  ];

  const houseBalance = ethers.parseEther("1000000"); // 1M tokens

  console.log("\nConfiguring tokens, minting, and depositing house balance...");

  for (const token of tokens) {
    console.log(`\n  Processing ${token.name}...`);

    try {
      // 1. Configure token
      console.log(`    Configuring token...`);
      const configTx = await game.configureToken(token.address, true);
      await configTx.wait();
      console.log(`    ✓ Configured as enabled`);

      // 2. Mint tokens
      const tokenContract = new ethers.Contract(token.address, ERC20_ABI, deployer);
      try {
        console.log(`    Minting 1M tokens...`);
        const mintTx = await tokenContract.mint(deployer.address, houseBalance);
        await mintTx.wait();
        console.log(`    ✓ Minted 1,000,000 tokens`);
      } catch (error) {
        console.log(`    ⚠ Could not mint (already minted or no mint permission): ${error.message.slice(0, 50)}`);
        // Check existing balance
        const balance = await tokenContract.balanceOf(deployer.address);
        console.log(`    Current balance: ${ethers.formatEther(balance)}`);
        if (balance < houseBalance) {
          console.log(`    ✗ Insufficient balance for house deposit, skipping this token`);
          continue;
        }
      }

      // 3. Approve
      console.log(`    Approving game contract...`);
      const approveTx = await tokenContract.approve(CONTRACT_ADDRESS, houseBalance);
      await approveTx.wait();
      console.log(`    ✓ Approved game contract`);

      // 4. Deposit
      console.log(`    Depositing house balance...`);
      const depositTx = await game.depositHouseBalance(token.address, houseBalance);
      await depositTx.wait();
      console.log(`    ✓ Deposited 1,000,000 as house balance`);
    } catch (error) {
      console.log(`    ✗ Error: ${error.message.slice(0, 100)}`);
    }
  }

  console.log("\n=== Configuration Complete ===");
  console.log("Contract Address:", CONTRACT_ADDRESS);

  // Verify configuration
  console.log("\nVerifying token configurations...");
  for (const token of tokens) {
    try {
      const config = await game.tokenConfigs(token.address);
      console.log(`  ${token.name}: enabled=${config.enabled}, houseBalance=${ethers.formatEther(config.houseBalance)}`);
    } catch (e) {
      console.log(`  ${token.name}: error reading config`);
    }
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
