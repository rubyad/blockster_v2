/**
 * Upgrade ROGUEBankroll to V11
 *
 * V11 Changes:
 * - Added Plinko integration: plinkoGame address, onlyPlinko modifier
 * - New state: PlinkoPlayerStats, PlinkoAccounting, plinkoBetsPerConfig, plinkoPnLPerConfig
 * - New functions: setPlinkoGame, updateHouseBalancePlinkoBetPlaced,
 *   settlePlinkoWinningBet, settlePlinkoLosingBet
 * - New view functions: getPlinkoAccounting, getPlinkoPlayerStats
 * - New events: PlinkoBetPlaced, PlinkoWinningPayout, PlinkoWinDetails,
 *   PlinkoLosingBet, PlinkoLossDetails, PlinkoPayoutFailed
 *
 * No reinitializer needed — only new storage (defaults to zero) and new functions.
 * setPlinkoGame must be called after PlinkoGame is deployed.
 */
// npx hardhat run scripts/upgrade-roguebankroll-v11.js --network rogueMainnet

const { ethers, upgrades } = require("hardhat");

const PROXY_ADDRESS = "0x51DB4eD2b69b598Fade1aCB5289C7426604AB2fd";

async function main() {
    console.log("=== Upgrading ROGUEBankroll to V11 (Plinko Integration) ===");
    console.log("Proxy address:", PROXY_ADDRESS);

    const [deployer] = await ethers.getSigners();
    console.log("Deployer:", deployer.address);

    const balance = await ethers.provider.getBalance(deployer.address);
    console.log("Balance:", ethers.formatEther(balance), "ROGUE");

    // Get current implementation
    const currentImpl = await upgrades.erc1967.getImplementationAddress(PROXY_ADDRESS);
    console.log("Current implementation:", currentImpl);

    // Pre-flight: check existing state
    const proxy = await ethers.getContractAt("contracts/ROGUEBankroll.sol:ROGUEBankroll", PROXY_ADDRESS);
    const owner = await proxy.owner();
    console.log("Owner:", owner);

    if (owner.toLowerCase() !== deployer.address.toLowerCase()) {
        console.error("ERROR: Deployer is NOT the proxy owner.");
        process.exit(1);
    }

    // Deploy new implementation and upgrade
    const ROGUEBankroll = await ethers.getContractFactory("contracts/ROGUEBankroll.sol:ROGUEBankroll");

    console.log("\nDeploying new implementation and upgrading proxy...");
    const upgraded = await upgrades.upgradeProxy(PROXY_ADDRESS, ROGUEBankroll, {
        timeout: 300000,
        pollingInterval: 5000,
    });

    await upgraded.waitForDeployment();

    const newImpl = await upgrades.erc1967.getImplementationAddress(PROXY_ADDRESS);
    console.log("New implementation:", newImpl);

    // Post-upgrade verification
    console.log("\n--- Post-upgrade Verification ---");

    const postOwner = await proxy.owner();
    console.log("  Owner:", postOwner, postOwner === owner ? "(unchanged)" : "CHANGED!");

    try {
        const plinkoGame = await proxy.plinkoGame();
        console.log("  plinkoGame():", plinkoGame, "(new V11 function works)");
    } catch (e) {
        console.error("  ERROR: plinkoGame() failed:", e.message);
    }

    try {
        const acc = await proxy.getPlinkoAccounting();
        console.log("  getPlinkoAccounting() totalBets:", acc.totalBets.toString(), "(new V11 function works)");
    } catch (e) {
        console.error("  ERROR: getPlinkoAccounting() failed:", e.message);
    }

    console.log("\n========================================");
    console.log("=== ROGUEBankroll V11 Upgrade Complete ===");
    console.log("========================================");
    console.log("Proxy:              ", PROXY_ADDRESS);
    console.log("Old implementation: ", currentImpl);
    console.log("New implementation: ", newImpl);
    console.log("");
    console.log("NEXT STEPS:");
    console.log("1. Deploy PlinkoGame");
    console.log("2. Call setPlinkoGame(plinkoGameAddress) on ROGUEBankroll");
    console.log("");
    console.log("SAVE: ROGUE_BANKROLL_NEW_IMPL=" + newImpl);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
