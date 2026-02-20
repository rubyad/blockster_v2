// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IBUXBankroll
 * @notice Interface for BUXBankroll LP contract used by PlinkoGame (and future BUX games)
 * @dev PlinkoGame calls these functions to place bets and settle outcomes.
 *      BUXBankroll holds all BUX house funds and manages LP-BUX tokens.
 */
interface IBUXBankroll {
    /**
     * @notice Called by PlinkoGame when player places a BUX bet.
     *         BUX is transferred from player to BUXBankroll by PlinkoGame before calling this.
     * @param commitmentHash Bet identifier
     * @param player Player address
     * @param wagerAmount Amount of BUX wagered
     * @param configIndex Plinko config (0-8)
     * @param nonce Player's nonce for this bet
     * @param maxPayout Maximum possible payout based on max multiplier
     * @return success True if update succeeded
     */
    function updateHouseBalancePlinkoBetPlaced(
        bytes32 commitmentHash,
        address player,
        uint256 wagerAmount,
        uint8 configIndex,
        uint256 nonce,
        uint256 maxPayout
    ) external returns (bool);

    /**
     * @notice Settle a winning Plinko bet. Sends payout (> betAmount) to winner.
     * @param winner Player who won
     * @param commitmentHash Bet identifier
     * @param betAmount Original wager amount
     * @param payout Total payout to winner (betAmount + profit)
     * @param configIndex Plinko config (0-8)
     * @param landingPosition Slot the ball landed in (0 to rows)
     * @param path Ball path array (0=left, 1=right at each peg)
     * @param nonce Player's nonce
     * @param maxPayout Maximum possible payout (for liability release)
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
    ) external returns (bool);

    /**
     * @notice Settle a losing Plinko bet. House keeps BUX. Sends partial payout if multiplier > 0.
     * @param player Player who lost
     * @param commitmentHash Bet identifier
     * @param wagerAmount Original wager amount
     * @param partialPayout Amount to return to player (0 if 0x multiplier, or partial for < 1x)
     * @param configIndex Plinko config (0-8)
     * @param landingPosition Slot the ball landed in
     * @param path Ball path array
     * @param nonce Player's nonce
     * @param maxPayout Maximum possible payout (for liability release)
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
    ) external returns (bool);

    /**
     * @notice Settle a push Plinko bet (payout == betAmount). Returns exact wager.
     * @param player Player
     * @param commitmentHash Bet identifier
     * @param betAmount Original wager (returned exactly)
     * @param configIndex Plinko config (0-8)
     * @param landingPosition Slot the ball landed in
     * @param path Ball path array
     * @param nonce Player's nonce
     * @param maxPayout Maximum possible payout (for liability release)
     * @return success True if settlement succeeded
     */
    function settlePlinkoPushBet(
        address player,
        bytes32 commitmentHash,
        uint256 betAmount,
        uint8 configIndex,
        uint8 landingPosition,
        uint8[] calldata path,
        uint256 nonce,
        uint256 maxPayout
    ) external returns (bool);

    /**
     * @notice Get max allowed BUX bet for a given Plinko config
     * @param configIndex Plinko config (0-8)
     * @param maxMultiplierBps Highest multiplier in the config's payout table (in basis points)
     * @return maxBet Maximum BUX bet amount
     */
    function getMaxBet(uint8 configIndex, uint32 maxMultiplierBps) external view returns (uint256);

    /**
     * @notice Get comprehensive house balance info
     * @return totalBalance Total BUX in pool
     * @return liability Outstanding max payouts for active bets
     * @return unsettledBets Sum of wager amounts for unsettled bets
     * @return netBalance totalBalance - liability
     * @return poolTokenSupply Total LP-BUX supply
     * @return poolTokenPrice LP-BUX price (18 decimals)
     */
    function getHouseInfo() external view returns (
        uint256 totalBalance,
        uint256 liability,
        uint256 unsettledBets,
        uint256 netBalance,
        uint256 poolTokenSupply,
        uint256 poolTokenPrice
    );

    /**
     * @notice Get current LP-BUX price
     * @return price LP-BUX price in BUX (18 decimals, 1e18 = 1:1)
     */
    function getLPPrice() external view returns (uint256);
}
