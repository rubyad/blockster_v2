// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../AirdropPrizePool.sol";

/**
 * @title AirdropPrizePoolV2
 * @notice Mock V2 for testing UUPS upgrade preserves state
 */
contract AirdropPrizePoolV2 is AirdropPrizePool {
    uint256 public newV2Variable;

    function initializeV2() reinitializer(2) public {
        newV2Variable = 99;
    }

    function version() external pure returns (string memory) {
        return "v2";
    }
}
