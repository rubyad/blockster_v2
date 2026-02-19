// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ROGUEBankroll V10 Additions — Plinko Integration
 * @notice New state variables, modifier, functions, and events to add to ROGUEBankroll.
 *         All new storage MUST be added at END of existing storage layout.
 *         ROGUEBankroll is a Transparent Proxy — no reinitializer function needed
 *         since we're only adding new state and functions, not reinitializing existing state.
 *
 * EXISTING V9 STORAGE (for reference — DO NOT modify):
 *   HouseBalance houseBalance
 *   mapping(address => Player) players
 *   address rogueTrader
 *   uint256 minimumBetSize
 *   uint256 maximumBetSizeDivisor
 *   address nftRoguePayer
 *   address rogueBotsBetSettler
 *   address buxBoosterGame
 *   mapping(address => BuxBoosterPlayerStats) buxBoosterPlayerStats
 *   BuxBoosterAccounting buxBoosterAccounting
 *   address nftRewarder
 *   uint256 nftRewardBasisPoints
 *   uint256 totalNFTRewardsPaid
 *   uint256 referralBasisPoints
 *   mapping(address => address) playerReferrers
 *   uint256 totalReferralRewardsPaid
 *   mapping(address => uint256) referrerTotalEarnings
 *   address referralAdmin
 *   mapping(address => uint256[9]) buxBoosterBetsPerDifficulty
 *   mapping(address => int256[9]) buxBoosterPnLPerDifficulty
 *
 * ADD AFTER buxBoosterPnLPerDifficulty:
 */

// ============================================================
// ===================== NEW STATE VARIABLES ==================
// ============================================================
// Add these at the END of existing storage, after buxBoosterPnLPerDifficulty

// V10: Plinko Integration
// address public plinkoGame;

// struct PlinkoPlayerStats {
//     uint256 totalBets;
//     uint256 wins;
//     uint256 losses;
//     uint256 pushes;
//     uint256 totalWagered;
//     uint256 totalWinnings;
//     uint256 totalLosses;
// }
// mapping(address => PlinkoPlayerStats) public plinkoPlayerStats;
// mapping(address => uint256[9]) public plinkoBetsPerConfig;
// mapping(address => int256[9]) public plinkoPnLPerConfig;

// struct PlinkoAccounting {
//     uint256 totalBets;
//     uint256 totalWins;
//     uint256 totalLosses;
//     uint256 totalPushes;
//     uint256 totalVolumeWagered;
//     uint256 totalPayouts;
//     int256 totalHouseProfit;
//     uint256 largestWin;
//     uint256 largestBet;
// }
// PlinkoAccounting public plinkoAccounting;


// ============================================================
// ===================== NEW EVENTS ===========================
// ============================================================

contract ROGUEBankroll_V10_Additions {

    // Placeholder types for compilation reference (these exist in actual contract)
    struct HouseBalance {
        uint256 total_balance;
        uint256 liability;
        uint256 unsettled_bets;
        uint256 net_balance;
        uint256 actual_balance;
        uint256 pool_token_supply;
        uint256 pool_token_price;
    }

    struct PlinkoPlayerStats {
        uint256 totalBets;
        uint256 wins;
        uint256 losses;
        uint256 pushes;
        uint256 totalWagered;
        uint256 totalWinnings;
        uint256 totalLosses;
    }

    struct PlinkoAccounting {
        uint256 totalBets;
        uint256 totalWins;
        uint256 totalLosses;
        uint256 totalPushes;
        uint256 totalVolumeWagered;
        uint256 totalPayouts;
        int256 totalHouseProfit;
        uint256 largestWin;
        uint256 largestBet;
    }

    // ============ Events ============

    event PlinkoBetPlaced(
        address indexed player,
        bytes32 indexed commitmentHash,
        uint256 amount,
        uint8 configIndex,
        uint256 nonce,
        uint256 timestamp
    );

    event PlinkoWinningPayout(
        address indexed winner,
        bytes32 indexed commitmentHash,
        uint256 betAmount,
        uint256 payout,
        uint256 profit
    );

    event PlinkoWinDetails(
        bytes32 indexed commitmentHash,
        uint8 configIndex,
        uint8 landingPosition,
        uint8[] path,
        uint256 nonce
    );

    event PlinkoLosingBet(
        address indexed player,
        bytes32 indexed commitmentHash,
        uint256 wagerAmount,
        uint256 partialPayout
    );

    event PlinkoLossDetails(
        bytes32 indexed commitmentHash,
        uint8 configIndex,
        uint8 landingPosition,
        uint8[] path,
        uint256 nonce
    );

    event PlinkoPayoutFailed(
        address indexed winner,
        bytes32 indexed commitmentHash,
        uint256 payout
    );

    // ============ NEW MODIFIER ============

    // modifier onlyPlinko() {
    //     require(msg.sender == plinkoGame, "Only Plinko can call this function");
    //     _;
    // }

    // ============ NEW ADMIN FUNCTION ============

    // function setPlinkoGame(address _plinkoGame) external onlyOwner {
    //     plinkoGame = _plinkoGame;
    // }

    // ============ NEW FUNCTIONS ============

    /**
     * @notice Update house balance when Plinko bet is placed
     * @dev Called by PlinkoGame contract with ROGUE sent as msg.value
     *      Same pattern as updateHouseBalanceBuxBoosterBetPlaced but for Plinko
     * @param commitmentHash Bet identifier
     * @param configIndex Plinko config (0-8)
     * @param nonce Player's nonce
     * @param maxPayout Maximum possible payout (based on max multiplier)
     * @return success True if update successful
     */
    function updateHouseBalancePlinkoBetPlaced(
        bytes32 commitmentHash,
        uint8 configIndex,
        uint256 nonce,
        uint256 maxPayout
    ) external payable /* onlyPlinko */ returns(bool) {
        // NOTE: In the actual contract, use the existing minimumBetSize and maximumBetSizeDivisor
        // require(msg.value >= minimumBetSize, "Bet below minimum");
        // require(msg.value <= (houseBalance.net_balance / maximumBetSizeDivisor), "Bet above maximum");

        // houseBalance.total_balance += msg.value;
        // houseBalance.liability += maxPayout;
        // houseBalance.unsettled_bets += msg.value;
        // houseBalance.net_balance = houseBalance.total_balance - houseBalance.liability;
        // houseBalance.actual_balance = address(this).balance;

        // // Update Plinko global accounting
        // plinkoAccounting.totalBets++;
        // plinkoAccounting.totalVolumeWagered += msg.value;
        // if (msg.value > plinkoAccounting.largestBet) {
        //     plinkoAccounting.largestBet = msg.value;
        // }

        // emit PlinkoBetPlaced(
        //     tx.origin,  // Player address (msg.sender is PlinkoGame contract)
        //     commitmentHash,
        //     msg.value,
        //     configIndex,
        //     nonce,
        //     block.timestamp
        // );

        return true;
    }

    /**
     * @notice Settle a winning Plinko bet — sends ROGUE payout to winner
     * @dev Same pattern as settleBuxBoosterWinningBet but with Plinko-specific stats + events
     * @param winner Player who won
     * @param commitmentHash Bet identifier
     * @param betAmount Original wager
     * @param payout Total payout (betAmount + profit)
     * @param configIndex Plinko config (0-8)
     * @param landingPosition Slot ball landed in
     * @param path Ball path array
     * @param nonce Player's nonce
     * @param maxPayout Max possible payout (for liability release)
     * @return success True if settlement succeeded
     */
    function settlePlinkoWinningBet(
        address winner,
        bytes32 commitmentHash,
        uint256 betAmount,
        uint256 payout,
        uint8 configIndex,
        uint8 landingPosition,
        uint8[] calldata path,
        uint256 nonce,
        uint256 maxPayout
    ) external /* onlyPlinko */ returns(bool) {
        // uint256 profit = payout - betAmount;

        // // Update player stats
        // PlinkoPlayerStats storage stats = plinkoPlayerStats[winner];
        // stats.totalBets++;
        // stats.wins++;
        // stats.totalWagered += betAmount;
        // stats.totalWinnings += profit;
        // plinkoBetsPerConfig[winner][configIndex]++;
        // plinkoPnLPerConfig[winner][configIndex] += int256(profit);

        // // Update global accounting
        // plinkoAccounting.totalWins++;
        // plinkoAccounting.totalPayouts += payout;
        // plinkoAccounting.totalHouseProfit -= int256(profit);
        // if (profit > plinkoAccounting.largestWin) {
        //     plinkoAccounting.largestWin = profit;
        // }

        // // Update house balance (same pattern as _updateHouseBalanceWinning)
        // houseBalance.total_balance -= payout;
        // houseBalance.liability -= maxPayout;
        // houseBalance.unsettled_bets -= betAmount;
        // houseBalance.net_balance = houseBalance.total_balance - houseBalance.liability;
        // houseBalance.pool_token_supply = this.totalSupply();
        // houseBalance.pool_token_price = ((houseBalance.total_balance - houseBalance.unsettled_bets) * 1e18) / houseBalance.pool_token_supply;
        // houseBalance.actual_balance = address(this).balance;

        // // Send payout to winner
        // (bool sent,) = payable(winner).call{value: payout}("");
        // if (sent) {
        //     emit PlinkoWinningPayout(winner, commitmentHash, betAmount, payout, profit);
        //     emit PlinkoWinDetails(commitmentHash, configIndex, landingPosition, path, nonce);
        // } else {
        //     players[winner].rogue_balance += payout;
        //     emit PlinkoPayoutFailed(winner, commitmentHash, payout);
        // }

        return true;
    }

    /**
     * @notice Settle a losing Plinko bet — house keeps ROGUE, sends partial payout + rewards
     * @dev Same pattern as settleBuxBoosterLosingBet but with:
     *      - Partial payout support (for multipliers between 0x and 1x)
     *      - Plinko-specific stats + events
     *      - NFT rewards and referral rewards on loss portion
     * @param player Player who lost
     * @param commitmentHash Bet identifier
     * @param wagerAmount Original wager
     * @param partialPayout Amount to return (0 for 0x, or partial for < 1x)
     * @param configIndex Plinko config (0-8)
     * @param landingPosition Slot ball landed in
     * @param path Ball path array
     * @param nonce Player's nonce
     * @param maxPayout Max possible payout (for liability release)
     * @return success True if settlement succeeded
     */
    function settlePlinkoLosingBet(
        address player,
        bytes32 commitmentHash,
        uint256 wagerAmount,
        uint256 partialPayout,
        uint8 configIndex,
        uint8 landingPosition,
        uint8[] calldata path,
        uint256 nonce,
        uint256 maxPayout
    ) external /* onlyPlinko */ returns(bool) {
        // uint256 lossAmount = wagerAmount - partialPayout;

        // // Send partial payout if > 0
        // if (partialPayout > 0) {
        //     (bool sent,) = payable(player).call{value: partialPayout}("");
        //     if (!sent) {
        //         players[player].rogue_balance += partialPayout;
        //     }
        // }

        // // Release liability
        // houseBalance.liability -= maxPayout;
        // houseBalance.unsettled_bets -= wagerAmount;
        // houseBalance.net_balance = houseBalance.total_balance - houseBalance.liability;
        // houseBalance.actual_balance = address(this).balance;
        // houseBalance.pool_token_supply = this.totalSupply();
        // houseBalance.pool_token_price = ((houseBalance.total_balance - houseBalance.unsettled_bets) * 1e18) / houseBalance.pool_token_supply;

        // // Update player stats
        // PlinkoPlayerStats storage stats = plinkoPlayerStats[player];
        // stats.totalBets++;
        // stats.losses++;
        // stats.totalWagered += wagerAmount;
        // stats.totalLosses += lossAmount;
        // plinkoBetsPerConfig[player][configIndex]++;
        // plinkoPnLPerConfig[player][configIndex] -= int256(lossAmount);

        // // Update global accounting
        // plinkoAccounting.totalLosses++;
        // plinkoAccounting.totalHouseProfit += int256(lossAmount);
        // if (partialPayout > 0) {
        //     plinkoAccounting.totalPayouts += partialPayout;
        // }

        // // V7: Send NFT rewards on loss portion (non-blocking)
        // if (lossAmount > 0) {
        //     _sendNFTReward(commitmentHash, lossAmount);
        // }

        // // V8: Send referral rewards on loss portion (non-blocking)
        // if (lossAmount > 0) {
        //     _sendReferralReward(commitmentHash, player, lossAmount);
        // }

        // // Emit events
        // emit PlinkoLosingBet(player, commitmentHash, wagerAmount, partialPayout);
        // emit PlinkoLossDetails(commitmentHash, configIndex, landingPosition, path, nonce);

        return true;
    }

    // ============ NEW VIEW FUNCTIONS ============

    /**
     * @notice Get Plinko global accounting
     */
    function getPlinkoAccounting() external view returns (
        uint256 totalBets,
        uint256 totalWins,
        uint256 totalLosses,
        uint256 totalPushes,
        uint256 totalVolumeWagered,
        uint256 totalPayouts,
        int256 totalHouseProfit,
        uint256 largestWin,
        uint256 largestBet,
        uint256 winRate,
        int256 houseEdge
    ) {
        // PlinkoAccounting storage acc = plinkoAccounting;

        // totalBets = acc.totalBets;
        // totalWins = acc.totalWins;
        // totalLosses = acc.totalLosses;
        // totalPushes = acc.totalPushes;
        // totalVolumeWagered = acc.totalVolumeWagered;
        // totalPayouts = acc.totalPayouts;
        // totalHouseProfit = acc.totalHouseProfit;
        // largestWin = acc.largestWin;
        // largestBet = acc.largestBet;

        // if (acc.totalBets > 0) {
        //     winRate = (acc.totalWins * 10000) / acc.totalBets;
        // }

        // if (acc.totalVolumeWagered > 0) {
        //     houseEdge = (acc.totalHouseProfit * 10000) / int256(acc.totalVolumeWagered);
        // }
    }

    /**
     * @notice Get full Plinko player stats including per-config breakdown
     * @param player Player address to query
     */
    function getPlinkoPlayerStats(address player) external view returns (
        uint256 totalBets,
        uint256 wins,
        uint256 losses,
        uint256 pushes,
        uint256 totalWagered,
        uint256 totalWinnings,
        uint256 totalLosses,
        uint256[9] memory betsPerConfig,
        int256[9] memory pnlPerConfig
    ) {
        // PlinkoPlayerStats storage stats = plinkoPlayerStats[player];

        // totalBets = stats.totalBets;
        // wins = stats.wins;
        // losses = stats.losses;
        // pushes = stats.pushes;
        // totalWagered = stats.totalWagered;
        // totalWinnings = stats.totalWinnings;
        // totalLosses = stats.totalLosses;
        // betsPerConfig = plinkoBetsPerConfig[player];
        // pnlPerConfig = plinkoPnLPerConfig[player];
        player; // suppress warning
    }
}
