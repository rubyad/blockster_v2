/**
 * Fund AirdropPrizePool with USDT on Arbitrum One
 *
 * Usage:
 *   npx hardhat run scripts/fund-airdrop-prize-pool.js --network arbitrumOne
 *
 * Uses VAULT_ADMIN_PRIVATE_KEY from contracts/.env
 */

const PRIZE_POOL_ADDRESS = "0x919149CA8DB412541D2d8B3F150fa567fEFB58e1";
const USDT_ADDRESS = "0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9"; // USDT on Arbitrum One
const AMOUNT_USD = 5; // $5 USDT
const AMOUNT_RAW = BigInt(AMOUNT_USD) * BigInt(1e6); // USDT has 6 decimals

const ERC20_ABI = [
  "function approve(address spender, uint256 amount) external returns (bool)",
  "function allowance(address owner, address spender) external view returns (uint256)",
  "function balanceOf(address account) external view returns (uint256)",
  "function decimals() external view returns (uint8)"
];

const PRIZE_POOL_ABI = [
  "function fundPrizePool(uint256 amount) external",
  "function getPoolBalance() external view returns (uint256)",
  "function owner() external view returns (address)"
];

async function main() {
  const vaultKey = process.env.VAULT_ADMIN_PRIVATE_KEY;
  if (!vaultKey) {
    console.error("ERROR: VAULT_ADMIN_PRIVATE_KEY not set in .env");
    process.exit(1);
  }
  const signer = new ethers.Wallet(vaultKey, ethers.provider);
  console.log("Wallet:", signer.address);

  const usdt = new ethers.Contract(USDT_ADDRESS, ERC20_ABI, signer);
  const pool = new ethers.Contract(PRIZE_POOL_ADDRESS, PRIZE_POOL_ABI, signer);

  // Check ownership
  const owner = await pool.owner();
  console.log("PrizePool owner:", owner);
  if (owner.toLowerCase() !== signer.address.toLowerCase()) {
    console.error("ERROR: Signer is not the contract owner. Use the Vault Admin key.");
    process.exit(1);
  }

  // Check USDT balance
  const balance = await usdt.balanceOf(signer.address);
  console.log("USDT balance:", ethers.formatUnits(balance, 6), "USDT");

  if (balance < AMOUNT_RAW) {
    console.error(`ERROR: Insufficient USDT. Need ${AMOUNT_USD} USDT but have ${ethers.formatUnits(balance, 6)}`);
    process.exit(1);
  }

  // Check current pool balance
  const poolBefore = await pool.getPoolBalance();
  console.log("Pool balance before:", ethers.formatUnits(poolBefore, 6), "USDT");

  // Approve
  console.log(`\nApproving ${AMOUNT_USD} USDT for PrizePool...`);
  const approveTx = await usdt.approve(PRIZE_POOL_ADDRESS, AMOUNT_RAW);
  console.log("Approve tx:", approveTx.hash);
  await approveTx.wait();
  console.log("Approved.");

  // Fund
  console.log(`Funding PrizePool with ${AMOUNT_USD} USDT...`);
  const fundTx = await pool.fundPrizePool(AMOUNT_RAW);
  console.log("Fund tx:", fundTx.hash);
  await fundTx.wait();
  console.log("Funded.");

  // Verify
  const poolAfter = await pool.getPoolBalance();
  console.log("\nPool balance after:", ethers.formatUnits(poolAfter, 6), "USDT");
  console.log("Done!");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
