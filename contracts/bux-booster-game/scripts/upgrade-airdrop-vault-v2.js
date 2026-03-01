const { ethers } = require("hardhat");

/**
 * Upgrade AirdropVault proxy to V2 implementation.
 * V2 adds a public deposit() function so users can deposit directly from their smart wallet.
 *
 * Steps:
 * 1. Deploy AirdropVaultV2 implementation
 * 2. Call proxy.upgradeToAndCall(v2Impl, "0x") from vault admin (owner)
 * 3. Call proxy.initializeV2() to mark reinitializer(2)
 *
 * Requires VAULT_ADMIN_PRIVATE_KEY in .env — this is the owner of the proxy.
 *
 * Usage:
 *   npx hardhat run scripts/upgrade-airdrop-vault-v2.js --network rogueMainnet
 */
async function main() {
  const PROXY_ADDRESS = "0x27049F96f8a00203fEC5f871e6DAa6Ee4c244F6c";
  const EXPECTED_OWNER = "0xBd16aB578D55374061A78Bb6Cca8CB4ddFaBd4C9";

  // Use VAULT_ADMIN_PRIVATE_KEY directly — the vault owner is NOT the deployer wallet
  const vaultAdminKey = process.env.VAULT_ADMIN_PRIVATE_KEY;
  if (!vaultAdminKey) {
    console.error("ERROR: VAULT_ADMIN_PRIVATE_KEY not set in .env");
    process.exit(1);
  }

  const provider = new ethers.JsonRpcProvider("https://rpc.roguechain.io/rpc", 560013);
  const vaultAdmin = new ethers.Wallet(vaultAdminKey, provider);

  console.log("Upgrading AirdropVault with Vault Admin:", vaultAdmin.address);
  if (vaultAdmin.address.toLowerCase() !== EXPECTED_OWNER.toLowerCase()) {
    console.error(`ERROR: Wallet ${vaultAdmin.address} does not match expected owner ${EXPECTED_OWNER}`);
    process.exit(1);
  }

  const balance = await provider.getBalance(vaultAdmin.address);
  console.log("ROGUE balance:", ethers.formatEther(balance), "ROGUE");
  if (balance === 0n) {
    console.error("ERROR: Vault Admin has no ROGUE for gas");
    process.exit(1);
  }

  // Verify on-chain owner matches
  const proxyCheck = new ethers.Contract(PROXY_ADDRESS, ["function owner() view returns (address)"], provider);
  const currentOwner = await proxyCheck.owner();
  console.log("Current proxy owner:", currentOwner);
  if (currentOwner.toLowerCase() !== vaultAdmin.address.toLowerCase()) {
    console.error(`ERROR: Proxy owner is ${currentOwner}, not ${vaultAdmin.address}`);
    process.exit(1);
  }

  const nonce = await provider.getTransactionCount(vaultAdmin.address);
  console.log("Current nonce:", nonce);

  // 1. Deploy V2 implementation
  console.log("\nDeploying AirdropVaultV2 implementation...");
  const AirdropVaultV2 = await ethers.getContractFactory("AirdropVaultV2", vaultAdmin);
  const v2Impl = await AirdropVaultV2.deploy({
    gasLimit: 5000000,
    nonce: nonce,
    maxFeePerGas: 2000000000000n,  // 2000 gwei
    maxPriorityFeePerGas: 0n
  });
  await v2Impl.waitForDeployment();
  const v2Address = await v2Impl.getAddress();
  console.log("V2 implementation deployed at:", v2Address);

  // 2. Upgrade proxy to V2
  console.log("\nUpgrading proxy to V2...");
  const proxy = new ethers.Contract(
    PROXY_ADDRESS,
    ["function upgradeToAndCall(address, bytes) external"],
    vaultAdmin
  );

  try {
    const upgradeTx = await proxy.upgradeToAndCall(v2Address, "0x", {
      gasLimit: 5000000,
      nonce: nonce + 1,
      maxFeePerGas: 2000000000000n,
      maxPriorityFeePerGas: 0n
    });
    console.log("Upgrade tx submitted:", upgradeTx.hash);
    await upgradeTx.wait();
    console.log("Upgrade complete!");
  } catch (error) {
    console.error("Upgrade failed:", error.message);
    process.exit(1);
  }

  // 3. Initialize V2
  console.log("\nInitializing V2...");
  const upgraded = new ethers.Contract(
    PROXY_ADDRESS,
    [
      "function initializeV2() external",
      "function version() view returns (string)",
      "function owner() view returns (address)",
      "function roundId() view returns (uint256)"
    ],
    vaultAdmin
  );

  try {
    const initTx = await upgraded.initializeV2({
      gasLimit: 500000,
      nonce: nonce + 2,
      maxFeePerGas: 2000000000000n,
      maxPriorityFeePerGas: 0n
    });
    console.log("InitializeV2 tx submitted:", initTx.hash);
    await initTx.wait();
    console.log("V2 initialized!");
  } catch (error) {
    console.error("InitializeV2 failed:", error.message);
    process.exit(1);
  }

  // Verify
  console.log("\nVerification:");
  console.log("  Version:", await upgraded.version());
  console.log("  Owner:", await upgraded.owner());
  console.log("  RoundId:", (await upgraded.roundId()).toString());
  console.log("\nAirdropVault V2 upgrade complete!");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
