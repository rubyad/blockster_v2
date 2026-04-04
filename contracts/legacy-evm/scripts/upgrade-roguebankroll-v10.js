/**
 * Upgrade ROGUEBankroll to V10
 *
 * V10 Changes:
 * - Fixed per-difficulty stats index calculation to match BuxBoosterGame
 * - Old formula: diffIndex = difficulty + 4 (wrong for positive difficulties)
 * - New formula: diffIndex = difficulty < 0 ? difficulty + 4 : difficulty + 3
 *
 * Note: Historical per-difficulty data for positive difficulties (Win All modes)
 * will be at wrong indices. This fix only affects new bets going forward.
 */

const { ethers, upgrades } = require("hardhat");

const PROXY_ADDRESS = "0x51DB4eD2b69b598Fade1aCB5289C7426604AB2fd";

async function main() {
    console.log("Upgrading ROGUEBankroll to V10...");
    console.log("Proxy address:", PROXY_ADDRESS);

    const [deployer] = await ethers.getSigners();
    console.log("Deployer:", deployer.address);

    // Get current implementation
    const currentImpl = await upgrades.erc1967.getImplementationAddress(PROXY_ADDRESS);
    console.log("Current implementation:", currentImpl);

    // Deploy new implementation
    const ROGUEBankroll = await ethers.getContractFactory("ROGUEBankroll");

    console.log("\nDeploying new implementation...");
    const upgraded = await upgrades.upgradeProxy(PROXY_ADDRESS, ROGUEBankroll, {
        timeout: 300000,
        pollingInterval: 5000,
    });

    await upgraded.waitForDeployment();

    const newImpl = await upgrades.erc1967.getImplementationAddress(PROXY_ADDRESS);
    console.log("New implementation:", newImpl);

    console.log("\n✅ ROGUEBankroll V10 upgrade complete!");
    console.log("Note: Historical per-difficulty stats for Win All modes are at wrong indices.");
    console.log("New bets will use correct index calculation.");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
