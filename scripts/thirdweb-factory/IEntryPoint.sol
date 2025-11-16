// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

/**
 * Interface for ERC-4337 EntryPoint v0.6.0
 */
interface IEntryPoint {
    function getNonce(address sender, uint192 key) external view returns (uint256 nonce);
}
