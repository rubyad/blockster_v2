// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../AirdropVault.sol";

/**
 * @title AirdropVaultV2
 * @notice Mock V2 for testing UUPS upgrade preserves state
 */
contract AirdropVaultV2 is AirdropVault {
    uint256 public newV2Variable;

    function initializeV2() reinitializer(2) public {
        newV2Variable = 42;
    }

    function version() external pure returns (string memory) {
        return "v2";
    }
}
