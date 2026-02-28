// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./AirdropVault.sol";

/**
 * @title AirdropVaultV2
 * @notice Adds public deposit() function so users can deposit directly from their smart wallet.
 * @dev Inherits all V1 logic. The new deposit() uses msg.sender as blocksterWallet,
 *      removing the onlyOwner restriction. safeTransferFrom already ensures only
 *      approved tokens can be moved, so no security benefit from the owner gate.
 *
 *      This matches the BuxBooster pattern: user does approve + deposit entirely client-side.
 *      The old depositFor() remains for backward compatibility but is no longer used.
 */
contract AirdropVaultV2 is AirdropVault {
    using SafeERC20 for IERC20;

    // No new state variables needed — slot-compatible with V1

    /// @notice Initialize V2 (no-op, required for reinitializer pattern)
    function initializeV2() reinitializer(2) public {
        // No new state to initialize
    }

    /// @notice Returns the contract version
    function version() external pure returns (string memory) {
        return "v2";
    }

    /**
     * @notice Public deposit function — anyone can deposit their own BUX.
     * @dev Uses msg.sender as the blocksterWallet. The caller must have
     *      approved this vault to spend their BUX via BUX.approve(vault, amount).
     * @param externalWallet The user's connected external wallet (prize destination)
     * @param amount The amount of BUX to deposit (in wei, 18 decimals)
     */
    function deposit(
        address externalWallet,
        uint256 amount
    ) external {
        RoundState storage round = _rounds[roundId];
        require(round.isOpen, "Round not open");
        require(amount > 0, "Zero amount");
        require(externalWallet != address(0), "Invalid external wallet");

        address blocksterWallet = _msgSender();

        // Transfer BUX from caller to this contract
        buxToken.safeTransferFrom(blocksterWallet, address(this), amount);

        // Calculate position block (1-indexed)
        uint256 startPosition = round.totalEntries + 1;
        uint256 endPosition = round.totalEntries + amount;
        round.totalEntries = endPosition;

        _deposits[roundId].push(Deposit({
            blocksterWallet: blocksterWallet,
            externalWallet: externalWallet,
            startPosition: startPosition,
            endPosition: endPosition,
            amount: amount
        }));

        _totalDeposited[roundId][blocksterWallet] += amount;

        emit BuxDeposited(roundId, blocksterWallet, externalWallet, amount, startPosition, endPosition);
    }
}
