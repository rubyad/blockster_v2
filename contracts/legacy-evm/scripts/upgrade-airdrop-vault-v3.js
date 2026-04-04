const { ethers } = require("hardhat");

/**
 * Upgrade AirdropVault proxy to V3 implementation.
 * V3 simplifies drawWinners (no on-chain computation) and adds setWinner().
 *
 * Usage:
 *   npx hardhat run scripts/upgrade-airdrop-vault-v3.js --network rogueMainnet
 */
async function main() {
  const PROXY_ADDRESS = "0x27049F96f8a00203fEC5f871e6DAa6Ee4c244F6c";
  const EXPECTED_OWNER = "0xBd16aB578D55374061A78Bb6Cca8CB4ddFaBd4C9";

  const vaultAdminKey = process.env.VAULT_ADMIN_PRIVATE_KEY;
  if (!vaultAdminKey) {
    console.error("ERROR: VAULT_ADMIN_PRIVATE_KEY not set in .env");
    process.exit(1);
  }

  const provider = new ethers.JsonRpcProvider("https://rpc.roguechain.io/rpc", 560013);
  const vaultAdmin = new ethers.Wallet(vaultAdminKey, provider);

  console.log("Upgrading AirdropVault to V3 with Vault Admin:", vaultAdmin.address);
  if (vaultAdmin.address.toLowerCase() !== EXPECTED_OWNER.toLowerCase()) {
    console.error(`ERROR: Wallet ${vaultAdmin.address} does not match expected owner ${EXPECTED_OWNER}`);
    process.exit(1);
  }

  const balance = await provider.getBalance(vaultAdmin.address);
  console.log("ROGUE balance:", ethers.formatEther(balance), "ROGUE");

  const proxyCheck = new ethers.Contract(PROXY_ADDRESS, ["function owner() view returns (address)"], provider);
  const currentOwner = await proxyCheck.owner();
  console.log("Current proxy owner:", currentOwner);

  const nonce = await provider.getTransactionCount(vaultAdmin.address);
  console.log("Current nonce:", nonce);

  // 1. Deploy V3 implementation
  console.log("\nDeploying AirdropVaultV3 implementation...");
  const AirdropVaultV3 = await ethers.getContractFactory("AirdropVaultV3", vaultAdmin);
  const v3Impl = await AirdropVaultV3.deploy({
    gasLimit: 5000000,
    nonce: nonce,
    maxFeePerGas: 2000000000000n,
    maxPriorityFeePerGas: 0n
  });
  await v3Impl.waitForDeployment();
  const v3Address = await v3Impl.getAddress();
  console.log("V3 implementation deployed at:", v3Address);

  // 2. Upgrade proxy to V3
  console.log("\nUpgrading proxy to V3...");
  const proxy = new ethers.Contract(
    PROXY_ADDRESS,
    ["function upgradeToAndCall(address, bytes) external"],
    vaultAdmin
  );

  const upgradeTx = await proxy.upgradeToAndCall(v3Address, "0x", {
    gasLimit: 5000000,
    nonce: nonce + 1,
    maxFeePerGas: 2000000000000n,
    maxPriorityFeePerGas: 0n
  });
  console.log("Upgrade tx:", upgradeTx.hash);
  await upgradeTx.wait();
  console.log("Upgrade complete!");

  // 3. Initialize V3
  console.log("\nInitializing V3...");
  const upgraded = new ethers.Contract(
    PROXY_ADDRESS,
    [
      "function initializeV3() external",
      "function version() view returns (string)",
      "function owner() view returns (address)",
      "function roundId() view returns (uint256)",
      "function isDrawn() view returns (bool)"
    ],
    vaultAdmin
  );

  try {
    const initTx = await upgraded.initializeV3({
      gasLimit: 500000,
      nonce: nonce + 2,
      maxFeePerGas: 2000000000000n,
      maxPriorityFeePerGas: 0n
    });
    console.log("InitializeV3 tx:", initTx.hash);
    await initTx.wait();
    console.log("V3 initialized!");
  } catch (error) {
    console.log("InitializeV3 skipped (already initialized):", error.reason || error.message);
  }

  // Verify
  console.log("\nVerification:");
  console.log("  Version:", await upgraded.version());
  console.log("  Owner:", await upgraded.owner());
  console.log("  RoundId:", (await upgraded.roundId()).toString());
  console.log("  IsDrawn:", await upgraded.isDrawn());
  console.log("\n  V3 Impl:", v3Address);
  console.log("\nAirdropVault V3 upgrade complete!");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
