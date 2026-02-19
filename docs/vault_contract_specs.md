# Vault Smart Contract Specifications — Centralized Bridge System

> **Status:** Design Document (Phase 2 from `layerzero_bridge_research.md`)
> **Date:** February 2026
> **Purpose:** Enable users to deposit ETH/USDC/USDT/ARB on Ethereum or Arbitrum One (and SOL/USDC/USDT on Solana) and receive ROGUE on Rogue Chain. Also supports withdrawing ROGUE back to any supported token/chain.

---

## Table of Contents

1. [System Overview](#1-system-overview)
2. [EVM Vault Contract](#2-evm-vault-contract-ethereum--arbitrum-one)
3. [Rogue Chain Withdrawal Contract](#3-rogue-chain-withdrawal-contract)
4. [Solana Vault Program](#4-solana-vault-program)
5. [Cross-Contract Event Flow](#5-cross-contract-event-flow)
6. [Security Model](#6-security-model)
7. [Upgrade Strategy](#7-upgrade-strategy)
8. [Gas Cost Estimates](#8-gas-cost-estimates)
9. [Deployment Checklist](#9-deployment-checklist)

---

## 1. System Overview

### Architecture

```
 [Ethereum/Arbitrum]          [Relayer Service]           [Rogue Chain]
 ┌──────────────┐             ┌──────────────┐            ┌──────────────────┐
 │  EVMVault    │──Deposit──> │  Backend     │──ROGUE──>  │  User's Smart    │
 │  Contract    │  Event      │  Relayer     │  Transfer  │  Wallet (ERC4337)│
 │              │             │              │            │                  │
 │              │<──Release── │              │<──Event──  │  RogueWithdrawal │
 │              │   Tokens    │              │  Detected  │  Contract        │
 └──────────────┘             └──────────────┘            └──────────────────┘

 [Solana]
 ┌──────────────┐
 │  SolanaVault │──Deposit──> (same Relayer) ──ROGUE──>  User's Smart Wallet
 │  Program     │  Event
 │              │<──Release── (same Relayer) <──Event──  RogueWithdrawal
 └──────────────┘
```

### Roles

| Role | Description |
|------|-------------|
| **Owner** | Multi-sig (3-of-5 Gnosis Safe). Can update relayer, pause, manage whitelist, set limits. |
| **Relayer** | Hot wallet operated by backend service. Can call `release()` / `releaseETH()` to fulfill withdrawals. |
| **Guardian** | Can ONLY pause the contract in emergencies. Cannot unpause (owner-only). Separate key from relayer. |
| **User** | Deposits tokens to vault on source chain, or requests withdrawal on Rogue Chain. |

### Supported Tokens

| Chain | Token | Address | Decimals |
|-------|-------|---------|----------|
| Ethereum | ETH | Native | 18 |
| Ethereum | USDC | `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48` | 6 |
| Ethereum | USDT | `0xdAC17F958D2ee523a2206206994597C13D831ec7` | 6 |
| Arbitrum One | ETH | Native | 18 |
| Arbitrum One | USDC | `0xaf88d065e77c8cC2239327C5EDb3A432268e5831` | 6 |
| Arbitrum One | USDT | `0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9` | 6 |
| Arbitrum One | ARB | `0x912CE59144191C1204E64559FE8253a0e49E6548` | 18 |
| Solana | SOL | Native | 9 |
| Solana | USDC | `EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v` | 6 |
| Solana | USDT | `Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB` | 6 |

---

## 2. EVM Vault Contract (Ethereum + Arbitrum One)

Deploy the same contract on both Ethereum Mainnet and Arbitrum One with chain-specific token whitelists.

### 2.1 Full Solidity Interface

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title BlocksterVault
 * @author Blockster Team
 * @notice Custodial vault for the Blockster cross-chain bridge. Users deposit
 *         ERC-20 tokens or native ETH on this chain and receive ROGUE on Rogue
 *         Chain (Arbitrum Orbit L3, chain ID 560013). Withdrawals from Rogue
 *         Chain are fulfilled by the relayer calling release functions.
 *
 * @dev Deployed behind a UUPS proxy. Owner is a Gnosis Safe multi-sig.
 *      The relayer is a hot wallet with limited permissions (release only).
 *      A separate guardian key can pause but not unpause.
 *
 * Security model:
 *  - ReentrancyGuard on all state-changing external functions
 *  - Pausable with guardian emergency pause
 *  - Nonce-based replay protection on releases
 *  - Per-token and global deposit/withdrawal limits
 *  - Cooldown period on large withdrawals
 *  - Token whitelist (only approved tokens accepted)
 */
contract BlocksterVault is
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;

    // =========================================================================
    // Constants
    // =========================================================================

    /// @notice Maximum basis points (100%)
    uint256 public constant MAX_BPS = 10_000;

    /// @notice Absolute maximum spread the owner can set (5%)
    uint256 public constant MAX_SPREAD_BPS = 500;

    // =========================================================================
    // Storage — append-only, never reorder or remove (UUPS upgrade safety)
    // =========================================================================

    // --- Access control ---

    /// @notice Address authorized to call release functions
    address public relayer;

    /// @notice Address authorized to call emergencyPause (cannot unpause)
    address public guardian;

    // --- Token whitelist ---

    /// @notice token address => whether it is accepted for deposits
    mapping(address => bool) public whitelistedTokens;

    /// @notice Ordered list of whitelisted token addresses (for enumeration)
    address[] public tokenList;

    // --- Nonce tracking (replay protection for releases) ---

    /// @notice Monotonically increasing nonce for release operations
    uint256 public releaseNonce;

    /// @notice nonce => whether it has been consumed
    mapping(uint256 => bool) public usedNonces;

    // --- Deposit limits ---

    /// @notice token address => minimum deposit amount (in token's native decimals)
    mapping(address => uint256) public minDeposit;

    /// @notice token address => maximum deposit amount per transaction
    mapping(address => uint256) public maxDepositPerTx;

    /// @notice Global daily deposit cap in USD (scaled by 1e6, i.e. $1 = 1_000_000)
    uint256 public dailyDepositCapUsd;

    /// @notice Tracks total USD deposited in current day
    uint256 public dailyDepositTotalUsd;

    /// @notice Timestamp when the current daily window started
    uint256 public dailyDepositWindowStart;

    // --- Withdrawal / release limits ---

    /// @notice Per-release cap in USD (scaled by 1e6). Releases above this
    ///         require owner (multi-sig) approval via a separate queue.
    uint256 public maxReleasePerTxUsd;

    /// @notice Global daily release cap in USD (scaled by 1e6)
    uint256 public dailyReleaseCapUsd;

    /// @notice Tracks total USD released in current day
    uint256 public dailyReleaseTotalUsd;

    /// @notice Timestamp when the current daily release window started
    uint256 public dailyReleaseWindowStart;

    // --- Spread ---

    /// @notice Bridge spread in basis points (e.g. 50 = 0.5%). Applied by
    ///         the relayer off-chain when computing ROGUE amount. Stored here
    ///         for transparency / on-chain reference.
    uint256 public spreadBps;

    // --- Accounting ---

    /// @notice token address => total deposited (lifetime)
    mapping(address => uint256) public totalDeposited;

    /// @notice token address => total released (lifetime)
    mapping(address => uint256) public totalReleased;

    /// @notice Total ETH deposited (lifetime)
    uint256 public totalETHDeposited;

    /// @notice Total ETH released (lifetime)
    uint256 public totalETHReleased;

    /// @notice Global deposit counter
    uint256 public depositCount;

    /// @notice Global release counter
    uint256 public releaseCount;

    // =========================================================================
    // Events
    // =========================================================================

    /**
     * @notice Emitted when a user deposits an ERC-20 token into the vault.
     * @param depositor          The address that sent the tokens
     * @param token              The ERC-20 token contract address
     * @param amount             Amount deposited (in token's native decimals)
     * @param destinationWallet  The user's smart wallet on Rogue Chain that
     *                           should receive ROGUE
     * @param depositId          Monotonically increasing deposit counter
     */
    event Deposit(
        address indexed depositor,
        address indexed token,
        uint256 amount,
        address destinationWallet,
        uint256 indexed depositId
    );

    /**
     * @notice Emitted when a user deposits native ETH into the vault.
     * @param depositor          The address that sent ETH
     * @param amount             Amount of ETH deposited (in wei)
     * @param destinationWallet  The user's smart wallet on Rogue Chain
     * @param depositId          Monotonically increasing deposit counter
     */
    event DepositETH(
        address indexed depositor,
        uint256 amount,
        address destinationWallet,
        uint256 indexed depositId
    );

    /**
     * @notice Emitted when the relayer releases ERC-20 tokens for a withdrawal.
     * @param recipient          Address receiving the tokens
     * @param token              The ERC-20 token contract address
     * @param amount             Amount released
     * @param nonce              Unique nonce preventing replay
     * @param rogueChainTxHash   The withdrawal request tx hash on Rogue Chain
     */
    event Release(
        address indexed recipient,
        address indexed token,
        uint256 amount,
        uint256 indexed nonce,
        bytes32 rogueChainTxHash
    );

    /**
     * @notice Emitted when the relayer releases native ETH for a withdrawal.
     * @param recipient          Address receiving ETH
     * @param amount             Amount of ETH released (in wei)
     * @param nonce              Unique nonce preventing replay
     * @param rogueChainTxHash   The withdrawal request tx hash on Rogue Chain
     */
    event ReleaseETH(
        address indexed recipient,
        uint256 amount,
        uint256 indexed nonce,
        bytes32 rogueChainTxHash
    );

    /// @notice Emitted when the relayer address is changed
    event RelayerUpdated(address indexed previousRelayer, address indexed newRelayer);

    /// @notice Emitted when the guardian address is changed
    event GuardianUpdated(address indexed previousGuardian, address indexed newGuardian);

    /// @notice Emitted when a token is added to or removed from the whitelist
    event TokenWhitelistUpdated(address indexed token, bool allowed);

    /// @notice Emitted when deposit limits are changed for a token
    event DepositLimitsUpdated(address indexed token, uint256 minAmount, uint256 maxPerTx);

    /// @notice Emitted when the guardian triggers an emergency pause
    event EmergencyPaused(address indexed triggeredBy);

    /// @notice Emitted when the owner unpauses the contract
    event Unpaused(address indexed triggeredBy);

    /// @notice Emitted when the owner withdraws tokens for rebalancing
    event OwnerWithdraw(address indexed token, uint256 amount, address indexed to);

    /// @notice Emitted when the owner withdraws ETH for rebalancing
    event OwnerWithdrawETH(uint256 amount, address indexed to);

    // =========================================================================
    // Errors
    // =========================================================================

    error TokenNotWhitelisted(address token);
    error BelowMinimumDeposit(uint256 amount, uint256 minimum);
    error AboveMaximumDeposit(uint256 amount, uint256 maximum);
    error DailyDepositCapExceeded();
    error DailyReleaseCapExceeded();
    error ReleaseExceedsPerTxCap(uint256 amountUsd, uint256 cap);
    error NonceAlreadyUsed(uint256 nonce);
    error NotRelayer();
    error NotGuardian();
    error NotRelayerOrOwner();
    error ZeroAddress();
    error ZeroAmount();
    error InsufficientVaultBalance(uint256 requested, uint256 available);
    error ETHTransferFailed();
    error InvalidSpread(uint256 bps);

    // =========================================================================
    // Modifiers
    // =========================================================================

    modifier onlyRelayer() {
        if (msg.sender != relayer) revert NotRelayer();
        _;
    }

    modifier onlyRelayerOrOwner() {
        if (msg.sender != relayer && msg.sender != owner()) revert NotRelayerOrOwner();
        _;
    }

    modifier onlyGuardian() {
        if (msg.sender != guardian) revert NotGuardian();
        _;
    }

    // =========================================================================
    // Initializer (replaces constructor for UUPS proxy)
    // =========================================================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the vault contract.
     * @param _owner     Multi-sig address that will own the contract
     * @param _relayer   Hot wallet address for the relayer service
     * @param _guardian  Emergency pause key
     */
    function initialize(
        address _owner,
        address _relayer,
        address _guardian
    ) external initializer {
        if (_owner == address(0) || _relayer == address(0) || _guardian == address(0))
            revert ZeroAddress();

        __Ownable_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        _transferOwnership(_owner);
        relayer = _relayer;
        guardian = _guardian;

        // Sensible defaults
        spreadBps = 50; // 0.5%
        dailyDepositCapUsd = 500_000 * 1e6; // $500K per day
        dailyReleaseCapUsd = 250_000 * 1e6; // $250K per day
        maxReleasePerTxUsd = 10_000 * 1e6;  // $10K per release without multi-sig
    }

    // =========================================================================
    // Deposit Functions (called by users)
    // =========================================================================

    /**
     * @notice Deposit an ERC-20 token into the vault.
     * @dev User must have already approved this contract for `amount`.
     *      Emits a {Deposit} event that the relayer watches to credit ROGUE.
     *
     * @param token               Address of the ERC-20 token to deposit
     * @param amount              Amount to deposit (in token's native decimals)
     * @param destinationWallet   User's smart wallet address on Rogue Chain (ERC-4337)
     */
    function deposit(
        address token,
        uint256 amount,
        address destinationWallet
    ) external nonReentrant whenNotPaused {
        if (!whitelistedTokens[token]) revert TokenNotWhitelisted(token);
        if (amount == 0) revert ZeroAmount();
        if (destinationWallet == address(0)) revert ZeroAddress();
        if (amount < minDeposit[token]) revert BelowMinimumDeposit(amount, minDeposit[token]);
        if (maxDepositPerTx[token] > 0 && amount > maxDepositPerTx[token])
            revert AboveMaximumDeposit(amount, maxDepositPerTx[token]);

        // Transfer tokens from user to vault (SafeERC20 handles non-standard returns)
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        // Update accounting
        totalDeposited[token] += amount;
        depositCount++;

        emit Deposit(msg.sender, token, amount, destinationWallet, depositCount);
    }

    /**
     * @notice Deposit native ETH into the vault.
     * @dev Emits a {DepositETH} event that the relayer watches to credit ROGUE.
     *
     * @param destinationWallet   User's smart wallet address on Rogue Chain (ERC-4337)
     */
    function depositETH(
        address destinationWallet
    ) external payable nonReentrant whenNotPaused {
        if (msg.value == 0) revert ZeroAmount();
        if (destinationWallet == address(0)) revert ZeroAddress();

        // ETH-specific limits use address(0) as the token key
        uint256 minETH = minDeposit[address(0)];
        uint256 maxETH = maxDepositPerTx[address(0)];
        if (msg.value < minETH && minETH > 0) revert BelowMinimumDeposit(msg.value, minETH);
        if (maxETH > 0 && msg.value > maxETH) revert AboveMaximumDeposit(msg.value, maxETH);

        // Update accounting
        totalETHDeposited += msg.value;
        depositCount++;

        emit DepositETH(msg.sender, msg.value, destinationWallet, depositCount);
    }

    // =========================================================================
    // Release Functions (called by relayer to fulfill Rogue Chain withdrawals)
    // =========================================================================

    /**
     * @notice Release ERC-20 tokens to a recipient as part of a withdrawal.
     * @dev Only callable by the relayer. Uses nonce for replay protection.
     *
     * @param token              ERC-20 token to release
     * @param amount             Amount to release
     * @param recipient          Address to receive the tokens
     * @param nonce              Unique nonce (must not have been used before)
     * @param rogueChainTxHash   Transaction hash of the withdrawal request on Rogue Chain
     */
    function release(
        address token,
        uint256 amount,
        address recipient,
        uint256 nonce,
        bytes32 rogueChainTxHash
    ) external nonReentrant whenNotPaused onlyRelayer {
        if (!whitelistedTokens[token]) revert TokenNotWhitelisted(token);
        if (amount == 0) revert ZeroAmount();
        if (recipient == address(0)) revert ZeroAddress();
        if (usedNonces[nonce]) revert NonceAlreadyUsed(nonce);

        // Check vault has sufficient balance
        uint256 vaultBalance = IERC20(token).balanceOf(address(this));
        if (amount > vaultBalance) revert InsufficientVaultBalance(amount, vaultBalance);

        // Mark nonce as used
        usedNonces[nonce] = true;
        releaseNonce++;

        // Transfer tokens to recipient
        IERC20(token).safeTransfer(recipient, amount);

        // Update accounting
        totalReleased[token] += amount;
        releaseCount++;

        emit Release(recipient, token, amount, nonce, rogueChainTxHash);
    }

    /**
     * @notice Release native ETH to a recipient as part of a withdrawal.
     * @dev Only callable by the relayer. Uses nonce for replay protection.
     *
     * @param amount             Amount of ETH to release (in wei)
     * @param recipient          Address to receive ETH
     * @param nonce              Unique nonce (must not have been used before)
     * @param rogueChainTxHash   Transaction hash of the withdrawal request on Rogue Chain
     */
    function releaseETH(
        uint256 amount,
        address recipient,
        uint256 nonce,
        bytes32 rogueChainTxHash
    ) external nonReentrant whenNotPaused onlyRelayer {
        if (amount == 0) revert ZeroAmount();
        if (recipient == address(0)) revert ZeroAddress();
        if (usedNonces[nonce]) revert NonceAlreadyUsed(nonce);

        // Check vault has sufficient ETH
        if (amount > address(this).balance) revert InsufficientVaultBalance(amount, address(this).balance);

        // Mark nonce as used
        usedNonces[nonce] = true;
        releaseNonce++;

        // Transfer ETH
        (bool success, ) = payable(recipient).call{value: amount}("");
        if (!success) revert ETHTransferFailed();

        // Update accounting
        totalETHReleased += amount;
        releaseCount++;

        emit ReleaseETH(recipient, amount, nonce, rogueChainTxHash);
    }

    // =========================================================================
    // Admin Functions (owner = multi-sig only)
    // =========================================================================

    /**
     * @notice Update the relayer hot wallet address.
     * @param _relayer  New relayer address
     */
    function setRelayer(address _relayer) external onlyOwner {
        if (_relayer == address(0)) revert ZeroAddress();
        emit RelayerUpdated(relayer, _relayer);
        relayer = _relayer;
    }

    /**
     * @notice Update the guardian address.
     * @param _guardian  New guardian address
     */
    function setGuardian(address _guardian) external onlyOwner {
        if (_guardian == address(0)) revert ZeroAddress();
        emit GuardianUpdated(guardian, _guardian);
        guardian = _guardian;
    }

    /**
     * @notice Add or remove a token from the whitelist.
     * @param token    ERC-20 token address
     * @param allowed  Whether deposits of this token are accepted
     */
    function setTokenWhitelist(address token, bool allowed) external onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        whitelistedTokens[token] = allowed;
        if (allowed) {
            // Add to list if not already present
            bool found = false;
            for (uint256 i = 0; i < tokenList.length; i++) {
                if (tokenList[i] == token) { found = true; break; }
            }
            if (!found) tokenList.push(token);
        }
        emit TokenWhitelistUpdated(token, allowed);
    }

    /**
     * @notice Set deposit limits for a token.
     * @dev Use address(0) for native ETH limits.
     * @param token       Token address (or address(0) for ETH)
     * @param _minDeposit Minimum deposit amount (0 = no minimum)
     * @param _maxPerTx   Maximum deposit per transaction (0 = no maximum)
     */
    function setDepositLimits(
        address token,
        uint256 _minDeposit,
        uint256 _maxPerTx
    ) external onlyOwner {
        minDeposit[token] = _minDeposit;
        maxDepositPerTx[token] = _maxPerTx;
        emit DepositLimitsUpdated(token, _minDeposit, _maxPerTx);
    }

    /**
     * @notice Set the daily deposit cap in USD.
     * @param _capUsd  Daily cap in USD scaled by 1e6 (e.g. 500_000 * 1e6 = $500K)
     */
    function setDailyDepositCap(uint256 _capUsd) external onlyOwner {
        dailyDepositCapUsd = _capUsd;
    }

    /**
     * @notice Set the daily release cap in USD.
     * @param _capUsd  Daily cap in USD scaled by 1e6
     */
    function setDailyReleaseCap(uint256 _capUsd) external onlyOwner {
        dailyReleaseCapUsd = _capUsd;
    }

    /**
     * @notice Set the per-transaction release cap in USD.
     * @param _capUsd  Per-tx cap in USD scaled by 1e6
     */
    function setMaxReleasePerTx(uint256 _capUsd) external onlyOwner {
        maxReleasePerTxUsd = _capUsd;
    }

    /**
     * @notice Set the bridge spread in basis points.
     * @param _bps  Spread in basis points (max 500 = 5%)
     */
    function setSpread(uint256 _bps) external onlyOwner {
        if (_bps > MAX_SPREAD_BPS) revert InvalidSpread(_bps);
        spreadBps = _bps;
    }

    /**
     * @notice Owner can withdraw tokens for rebalancing between vaults.
     * @dev This is for operational rebalancing, not fund extraction.
     *      Multi-sig provides the safety layer.
     *
     * @param token   ERC-20 token to withdraw
     * @param amount  Amount to withdraw
     * @param to      Destination address
     */
    function ownerWithdraw(
        address token,
        uint256 amount,
        address to
    ) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        IERC20(token).safeTransfer(to, amount);
        emit OwnerWithdraw(token, amount, to);
    }

    /**
     * @notice Owner can withdraw ETH for rebalancing.
     * @param amount  Amount of ETH to withdraw
     * @param to      Destination address
     */
    function ownerWithdrawETH(
        uint256 amount,
        address to
    ) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        (bool success, ) = payable(to).call{value: amount}("");
        if (!success) revert ETHTransferFailed();
        emit OwnerWithdrawETH(amount, to);
    }

    // =========================================================================
    // Pause / Unpause
    // =========================================================================

    /**
     * @notice Guardian can pause the contract in an emergency.
     * @dev Guardian can ONLY pause, not unpause. This is intentional:
     *      pausing is time-critical, unpausing requires deliberation.
     */
    function emergencyPause() external onlyGuardian {
        _pause();
        emit EmergencyPaused(msg.sender);
    }

    /**
     * @notice Owner (multi-sig) can also pause.
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Only owner (multi-sig) can unpause after review.
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    // =========================================================================
    // View Functions
    // =========================================================================

    /**
     * @notice Get the vault's current balance of a specific token.
     * @param token  ERC-20 token address
     * @return balance  Current balance held in the vault
     */
    function getTokenBalance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    /**
     * @notice Get the vault's current ETH balance.
     * @return balance  Current ETH balance
     */
    function getETHBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @notice Get the total number of whitelisted tokens.
     * @return count  Number of tokens in the whitelist
     */
    function getWhitelistedTokenCount() external view returns (uint256) {
        return tokenList.length;
    }

    /**
     * @notice Check if a nonce has been used.
     * @param nonce  The nonce to check
     * @return used  Whether the nonce has been consumed
     */
    function isNonceUsed(uint256 nonce) external view returns (bool) {
        return usedNonces[nonce];
    }

    // =========================================================================
    // UUPS Upgrade Authorization
    // =========================================================================

    /**
     * @dev Only owner (multi-sig) can authorize upgrades.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // =========================================================================
    // Receive ETH
    // =========================================================================

    /// @notice Allow the contract to receive ETH directly (for owner top-ups)
    receive() external payable {}
}
```

### 2.2 Storage Layout Summary

| Slot | Variable | Type | Notes |
|------|----------|------|-------|
| Inherited | OwnableUpgradeable._owner | address | Multi-sig |
| Inherited | PausableUpgradeable._paused | bool | Pause state |
| Inherited | ReentrancyGuardUpgradeable._status | uint256 | Reentrancy lock |
| 0 | relayer | address | Hot wallet for releases |
| 1 | guardian | address | Emergency pause key |
| 2 | whitelistedTokens | mapping(address => bool) | Token whitelist |
| 3 | tokenList | address[] | Enumerable whitelist |
| 4 | releaseNonce | uint256 | Monotonic counter |
| 5 | usedNonces | mapping(uint256 => bool) | Replay protection |
| 6 | minDeposit | mapping(address => uint256) | Per-token min |
| 7 | maxDepositPerTx | mapping(address => uint256) | Per-token max |
| 8 | dailyDepositCapUsd | uint256 | Daily cap |
| 9 | dailyDepositTotalUsd | uint256 | Running total |
| 10 | dailyDepositWindowStart | uint256 | Window timestamp |
| 11 | maxReleasePerTxUsd | uint256 | Per-tx release cap |
| 12 | dailyReleaseCapUsd | uint256 | Daily release cap |
| 13 | dailyReleaseTotalUsd | uint256 | Running total |
| 14 | dailyReleaseWindowStart | uint256 | Window timestamp |
| 15 | spreadBps | uint256 | Bridge spread |
| 16 | totalDeposited | mapping(address => uint256) | Lifetime deposits |
| 17 | totalReleased | mapping(address => uint256) | Lifetime releases |
| 18 | totalETHDeposited | uint256 | Lifetime ETH in |
| 19 | totalETHReleased | uint256 | Lifetime ETH out |
| 20 | depositCount | uint256 | Deposit counter |
| 21 | releaseCount | uint256 | Release counter |

**UUPS upgrade rule:** Only append new storage variables at the end. Never reorder or remove.

### 2.3 Deployment Configuration

**Ethereum Mainnet Vault:**
```
Whitelisted tokens: USDC (0xA0b8...), USDT (0xdAC1...)
ETH deposits: enabled via depositETH()
Min deposit: $10 equivalent
Max deposit per tx: $50,000 equivalent
Daily deposit cap: $500,000
Daily release cap: $250,000
Max release per tx: $10,000 (above requires multi-sig queue)
Spread: 50 bps (0.5%)
```

**Arbitrum One Vault:**
```
Whitelisted tokens: USDC (0xaf88...), USDT (0xFd08...), ARB (0x912C...)
ETH deposits: enabled via depositETH()
Min deposit: $5 equivalent (lower gas)
Max deposit per tx: $50,000 equivalent
Daily deposit cap: $500,000
Daily release cap: $250,000
Max release per tx: $10,000
Spread: 30 bps (0.3%, lower because Arbitrum is closer to Rogue Chain)
```

---

## 3. Rogue Chain Withdrawal Contract

Deployed on Rogue Chain (chain ID 560013). Users send native ROGUE to this contract to request a withdrawal to an external chain. The relayer watches the `WithdrawalRequested` event and fulfills it on the destination chain.

### 3.1 Solidity Interface

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title RogueWithdrawal
 * @author Blockster Team
 * @notice Withdrawal request contract on Rogue Chain. Users send native ROGUE
 *         to this contract specifying which chain, token, and address they want
 *         to receive on the destination. The backend relayer detects the event
 *         and fulfills the withdrawal from the appropriate EVM/Solana vault.
 *
 * @dev ROGUE is the native gas token on Rogue Chain, so withdrawals are
 *      received as msg.value (payable functions). This contract is callable
 *      via ERC-4337 UserOperations through the Paymaster, meaning users
 *      pay zero gas.
 *
 *      The relayer also uses this contract to forward ROGUE from deposits
 *      (when users deposit on external chains and need ROGUE credited).
 *      For deposits, the relayer simply sends native ROGUE to the user's
 *      smart wallet — no contract needed. But this contract provides a
 *      `creditUser` function for audit trail and accounting purposes.
 */
contract RogueWithdrawal is
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    // =========================================================================
    // Storage
    // =========================================================================

    /// @notice Relayer address (can call creditUser and withdrawRelayerBalance)
    address public relayer;

    /// @notice Guardian address (can emergency pause)
    address public guardian;

    /// @notice Monotonically increasing withdrawal request counter
    uint256 public withdrawalNonce;

    /// @notice Minimum withdrawal amount in ROGUE (wei)
    uint256 public minWithdrawalAmount;

    /// @notice Maximum withdrawal amount per transaction in ROGUE (wei)
    uint256 public maxWithdrawalPerTx;

    /// @notice Supported destination chain IDs
    mapping(uint256 => bool) public supportedDestChains;

    /// @notice Supported destination token symbols per chain
    /// @dev chainId => tokenSymbol (keccak256) => supported
    mapping(uint256 => mapping(bytes32 => bool)) public supportedDestTokens;

    /// @notice Lifetime total ROGUE received for withdrawals
    uint256 public totalWithdrawalsReceived;

    /// @notice Lifetime total ROGUE credited to users (from deposits)
    uint256 public totalCreditsIssued;

    /// @notice Credit nonce tracking for replay protection
    mapping(uint256 => bool) public usedCreditNonces;

    // =========================================================================
    // Events
    // =========================================================================

    /**
     * @notice Emitted when a user requests a withdrawal from Rogue Chain.
     * @dev The relayer watches this event to fulfill the withdrawal on the
     *      destination chain.
     *
     * @param user              The user's address on Rogue Chain
     * @param rogueAmount       Amount of ROGUE sent (in wei)
     * @param destChainId       Destination chain ID (1 = Ethereum, 42161 = Arbitrum, etc.)
     * @param destToken         Destination token symbol (e.g. "USDC", "ETH", "ARB")
     * @param destAddress       Address to receive tokens on the destination chain
     * @param nonce             Unique withdrawal request nonce
     */
    event WithdrawalRequested(
        address indexed user,
        uint256 rogueAmount,
        uint256 indexed destChainId,
        string destToken,
        address destAddress,
        uint256 indexed nonce
    );

    /**
     * @notice Emitted when the relayer credits ROGUE to a user (deposit fulfillment).
     * @param user              User's smart wallet that received ROGUE
     * @param amount            Amount of ROGUE credited (in wei)
     * @param sourceChainId     Chain where the deposit originated
     * @param sourceToken       Token that was deposited (e.g. "USDC", "ETH")
     * @param creditNonce       Unique credit nonce for replay protection
     * @param sourceDepositId   Deposit ID from the source chain vault
     */
    event UserCredited(
        address indexed user,
        uint256 amount,
        uint256 indexed sourceChainId,
        string sourceToken,
        uint256 indexed creditNonce,
        uint256 sourceDepositId
    );

    /// @notice Emitted when the relayer withdraws accumulated ROGUE
    event RelayerWithdrawal(address indexed relayer, uint256 amount, address indexed to);

    // =========================================================================
    // Errors
    // =========================================================================

    error ZeroAmount();
    error ZeroAddress();
    error BelowMinimumWithdrawal(uint256 amount, uint256 minimum);
    error AboveMaximumWithdrawal(uint256 amount, uint256 maximum);
    error UnsupportedDestChain(uint256 chainId);
    error UnsupportedDestToken(uint256 chainId, string token);
    error NotRelayer();
    error NotGuardian();
    error CreditNonceUsed(uint256 nonce);
    error ETHTransferFailed();

    // =========================================================================
    // Modifiers
    // =========================================================================

    modifier onlyRelayer() {
        if (msg.sender != relayer) revert NotRelayer();
        _;
    }

    modifier onlyGuardian() {
        if (msg.sender != guardian) revert NotGuardian();
        _;
    }

    // =========================================================================
    // Initializer
    // =========================================================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the withdrawal contract.
     * @param _owner     Multi-sig owner
     * @param _relayer   Relayer hot wallet
     * @param _guardian  Emergency pause key
     */
    function initialize(
        address _owner,
        address _relayer,
        address _guardian
    ) external initializer {
        if (_owner == address(0) || _relayer == address(0) || _guardian == address(0))
            revert ZeroAddress();

        __Ownable_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        _transferOwnership(_owner);
        relayer = _relayer;
        guardian = _guardian;

        // Default limits
        minWithdrawalAmount = 1000 ether; // 1,000 ROGUE minimum
        maxWithdrawalPerTx = 100_000_000 ether; // 100M ROGUE max per tx

        // Enable default destination chains
        supportedDestChains[1] = true;      // Ethereum
        supportedDestChains[42161] = true;  // Arbitrum One

        // Enable default destination tokens
        // Ethereum
        supportedDestTokens[1][keccak256("ETH")] = true;
        supportedDestTokens[1][keccak256("USDC")] = true;
        supportedDestTokens[1][keccak256("USDT")] = true;
        // Arbitrum
        supportedDestTokens[42161][keccak256("ETH")] = true;
        supportedDestTokens[42161][keccak256("USDC")] = true;
        supportedDestTokens[42161][keccak256("USDT")] = true;
        supportedDestTokens[42161][keccak256("ARB")] = true;
    }

    // =========================================================================
    // User Functions
    // =========================================================================

    /**
     * @notice Request a withdrawal: send ROGUE and specify destination.
     * @dev This function is payable — the user sends ROGUE as msg.value.
     *      Can be called via ERC-4337 UserOperation (gasless via Paymaster).
     *
     * @param destChainId    Destination chain ID (1, 42161, etc.)
     * @param destToken      Destination token symbol ("ETH", "USDC", "USDT", "ARB")
     * @param destAddress    Address on destination chain to receive tokens
     */
    function requestWithdrawal(
        uint256 destChainId,
        string calldata destToken,
        address destAddress
    ) external payable nonReentrant whenNotPaused {
        if (msg.value == 0) revert ZeroAmount();
        if (destAddress == address(0)) revert ZeroAddress();
        if (msg.value < minWithdrawalAmount)
            revert BelowMinimumWithdrawal(msg.value, minWithdrawalAmount);
        if (maxWithdrawalPerTx > 0 && msg.value > maxWithdrawalPerTx)
            revert AboveMaximumWithdrawal(msg.value, maxWithdrawalPerTx);
        if (!supportedDestChains[destChainId])
            revert UnsupportedDestChain(destChainId);
        if (!supportedDestTokens[destChainId][keccak256(bytes(destToken))])
            revert UnsupportedDestToken(destChainId, destToken);

        // Increment nonce
        withdrawalNonce++;

        // Update accounting
        totalWithdrawalsReceived += msg.value;

        emit WithdrawalRequested(
            msg.sender,
            msg.value,
            destChainId,
            destToken,
            destAddress,
            withdrawalNonce
        );
    }

    // =========================================================================
    // Relayer Functions
    // =========================================================================

    /**
     * @notice Credit ROGUE to a user's wallet (deposit fulfillment).
     * @dev Called by the relayer after detecting a deposit on an external chain.
     *      Provides an audit trail via the UserCredited event.
     *      The relayer sends ROGUE as msg.value which is forwarded to the user.
     *
     * @param user              User's smart wallet on Rogue Chain
     * @param sourceChainId     Chain where the deposit originated
     * @param sourceToken       Token symbol that was deposited
     * @param creditNonce       Unique nonce for replay protection
     * @param sourceDepositId   Deposit ID from the source vault contract
     */
    function creditUser(
        address user,
        uint256 sourceChainId,
        string calldata sourceToken,
        uint256 creditNonce,
        uint256 sourceDepositId
    ) external payable nonReentrant whenNotPaused onlyRelayer {
        if (user == address(0)) revert ZeroAddress();
        if (msg.value == 0) revert ZeroAmount();
        if (usedCreditNonces[creditNonce]) revert CreditNonceUsed(creditNonce);

        // Mark nonce as used
        usedCreditNonces[creditNonce] = true;

        // Forward ROGUE to user
        (bool success, ) = payable(user).call{value: msg.value}("");
        if (!success) revert ETHTransferFailed();

        // Update accounting
        totalCreditsIssued += msg.value;

        emit UserCredited(
            user,
            msg.value,
            sourceChainId,
            sourceToken,
            creditNonce,
            sourceDepositId
        );
    }

    /**
     * @notice Relayer withdraws accumulated ROGUE (from withdrawal requests)
     *         for rebalancing or operational needs.
     * @param amount  Amount to withdraw
     * @param to      Destination address
     */
    function withdrawRelayerBalance(
        uint256 amount,
        address to
    ) external nonReentrant onlyRelayer {
        if (amount == 0) revert ZeroAmount();
        if (to == address(0)) revert ZeroAddress();
        if (amount > address(this).balance) revert ETHTransferFailed();

        (bool success, ) = payable(to).call{value: amount}("");
        if (!success) revert ETHTransferFailed();

        emit RelayerWithdrawal(msg.sender, amount, to);
    }

    // =========================================================================
    // Admin Functions
    // =========================================================================

    /// @notice Update the relayer address
    function setRelayer(address _relayer) external onlyOwner {
        if (_relayer == address(0)) revert ZeroAddress();
        relayer = _relayer;
    }

    /// @notice Update the guardian address
    function setGuardian(address _guardian) external onlyOwner {
        if (_guardian == address(0)) revert ZeroAddress();
        guardian = _guardian;
    }

    /// @notice Set minimum withdrawal amount
    function setMinWithdrawalAmount(uint256 _amount) external onlyOwner {
        minWithdrawalAmount = _amount;
    }

    /// @notice Set maximum withdrawal per transaction
    function setMaxWithdrawalPerTx(uint256 _amount) external onlyOwner {
        maxWithdrawalPerTx = _amount;
    }

    /// @notice Enable or disable a destination chain
    function setSupportedDestChain(uint256 chainId, bool supported) external onlyOwner {
        supportedDestChains[chainId] = supported;
    }

    /// @notice Enable or disable a destination token for a specific chain
    function setSupportedDestToken(
        uint256 chainId,
        string calldata tokenSymbol,
        bool supported
    ) external onlyOwner {
        supportedDestTokens[chainId][keccak256(bytes(tokenSymbol))] = supported;
    }

    /// @notice Guardian emergency pause
    function emergencyPause() external onlyGuardian {
        _pause();
    }

    /// @notice Owner pause
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Owner unpause
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Owner can withdraw all ROGUE (emergency recovery)
    function ownerWithdraw(uint256 amount, address to) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        (bool success, ) = payable(to).call{value: amount}("");
        if (!success) revert ETHTransferFailed();
    }

    // =========================================================================
    // UUPS
    // =========================================================================

    function _authorizeUpgrade(address) internal override onlyOwner {}

    // =========================================================================
    // Receive
    // =========================================================================

    /// @notice Accept ROGUE transfers (for relayer top-ups)
    receive() external payable {}
}
```

### 3.2 ERC-4337 Integration Notes

The `requestWithdrawal` function is designed to be called through ERC-4337 UserOperations:

1. User opens withdrawal UI in the Blockster app
2. Frontend constructs a UserOperation that calls `requestWithdrawal()` with ROGUE as value
3. The Paymaster at `0x804cA06a85083eF01C9aE94bAE771446c25269a6` sponsors the gas
4. The Bundler at `rogue-bundler-mainnet.fly.dev` submits the UserOp
5. EntryPoint at `0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789` executes it
6. User pays zero gas — the Paymaster covers it

This means **withdrawals are gasless for users** on Rogue Chain.

---

## 4. Solana Vault Program

High-level Anchor/Rust design for the Solana vault. Deposits SOL, USDC, or USDT; relayer fulfills by sending ROGUE on Rogue Chain.

### 4.1 Program Architecture

```
Program ID: <to be deployed>

Accounts:
  ┌─────────────────────────────────────────┐
  │  VaultConfig (PDA)                       │
  │  seeds: ["vault_config"]                 │
  │                                          │
  │  - authority: Pubkey (multi-sig)         │
  │  - relayer: Pubkey (hot wallet)          │
  │  - guardian: Pubkey (pause key)          │
  │  - paused: bool                          │
  │  - deposit_count: u64                    │
  │  - release_nonce: u64                    │
  │  - min_deposit_lamports: u64             │
  │  - max_deposit_lamports: u64             │
  │  - min_deposit_usdc: u64                 │
  │  - max_deposit_usdc: u64                 │
  │  - spread_bps: u16                       │
  │  - total_sol_deposited: u64              │
  │  - total_sol_released: u64               │
  │  - bump: u8                              │
  └─────────────────────────────────────────┘

  ┌─────────────────────────────────────────┐
  │  TokenVault (PDA, per token mint)        │
  │  seeds: ["token_vault", mint.key()]      │
  │                                          │
  │  - Associated Token Account owned by     │
  │    VaultConfig PDA                       │
  │  - Holds USDC or USDT deposits           │
  └─────────────────────────────────────────┘

  ┌─────────────────────────────────────────┐
  │  SOL Vault (PDA)                         │
  │  seeds: ["sol_vault"]                    │
  │                                          │
  │  - Holds SOL deposits                    │
  │  - Authority: VaultConfig PDA            │
  └─────────────────────────────────────────┘

  ┌─────────────────────────────────────────┐
  │  NonceTracker (PDA)                      │
  │  seeds: ["nonce", nonce_value.to_le_bytes()]│
  │                                          │
  │  - used: bool                            │
  │  - One PDA per nonce (existence = used)  │
  └─────────────────────────────────────────┘
```

### 4.2 Instructions

```rust
use anchor_lang::prelude::*;
use anchor_spl::token::{self, Token, TokenAccount, Transfer};

declare_id!("VAULT_PROGRAM_ID");

#[program]
pub mod blockster_vault {
    use super::*;

    /// Initialize the vault configuration
    pub fn initialize(
        ctx: Context<Initialize>,
        relayer: Pubkey,
        guardian: Pubkey,
    ) -> Result<()> { /* ... */ }

    /// User deposits SOL to the vault
    /// Emits DepositSOL event for the relayer to detect
    pub fn deposit_sol(
        ctx: Context<DepositSOL>,
        amount: u64,                          // lamports
        destination_wallet: [u8; 20],         // EVM address (20 bytes) on Rogue Chain
    ) -> Result<()> { /* ... */ }

    /// User deposits SPL token (USDC/USDT) to the vault
    /// Emits DepositToken event for the relayer to detect
    pub fn deposit_token(
        ctx: Context<DepositToken>,
        amount: u64,                          // token amount in smallest unit
        destination_wallet: [u8; 20],         // EVM address on Rogue Chain
    ) -> Result<()> { /* ... */ }

    /// Relayer releases SOL to a recipient (withdrawal fulfillment)
    pub fn release_sol(
        ctx: Context<ReleaseSOL>,
        amount: u64,
        nonce: u64,
        rogue_chain_tx_hash: [u8; 32],
    ) -> Result<()> { /* ... */ }

    /// Relayer releases SPL token to a recipient (withdrawal fulfillment)
    pub fn release_token(
        ctx: Context<ReleaseToken>,
        amount: u64,
        nonce: u64,
        rogue_chain_tx_hash: [u8; 32],
    ) -> Result<()> { /* ... */ }

    /// Guardian pauses the vault
    pub fn emergency_pause(ctx: Context<GuardianAction>) -> Result<()> { /* ... */ }

    /// Authority unpauses the vault
    pub fn unpause(ctx: Context<AuthorityAction>) -> Result<()> { /* ... */ }

    /// Authority updates relayer
    pub fn set_relayer(ctx: Context<AuthorityAction>, new_relayer: Pubkey) -> Result<()> { /* ... */ }

    /// Authority updates deposit limits
    pub fn set_deposit_limits(
        ctx: Context<AuthorityAction>,
        min_sol: u64,
        max_sol: u64,
        min_usdc: u64,
        max_usdc: u64,
    ) -> Result<()> { /* ... */ }

    /// Authority withdraws tokens for rebalancing
    pub fn authority_withdraw_sol(ctx: Context<AuthorityAction>, amount: u64) -> Result<()> { /* ... */ }
    pub fn authority_withdraw_token(ctx: Context<AuthorityWithdrawToken>, amount: u64) -> Result<()> { /* ... */ }
}

// =========================================================================
// Events
// =========================================================================

#[event]
pub struct DepositSOL {
    pub depositor: Pubkey,
    pub amount: u64,
    pub destination_wallet: [u8; 20], // EVM address
    pub deposit_id: u64,
    pub timestamp: i64,
}

#[event]
pub struct DepositToken {
    pub depositor: Pubkey,
    pub token_mint: Pubkey,
    pub amount: u64,
    pub destination_wallet: [u8; 20],
    pub deposit_id: u64,
    pub timestamp: i64,
}

#[event]
pub struct ReleaseSOLEvent {
    pub recipient: Pubkey,
    pub amount: u64,
    pub nonce: u64,
    pub rogue_chain_tx_hash: [u8; 32],
}

#[event]
pub struct ReleaseTokenEvent {
    pub recipient: Pubkey,
    pub token_mint: Pubkey,
    pub amount: u64,
    pub nonce: u64,
    pub rogue_chain_tx_hash: [u8; 32],
}

#[event]
pub struct EmergencyPaused {
    pub triggered_by: Pubkey,
}

// =========================================================================
// Error Codes
// =========================================================================

#[error_code]
pub enum VaultError {
    #[msg("Vault is paused")]
    Paused,
    #[msg("Deposit below minimum")]
    BelowMinimumDeposit,
    #[msg("Deposit above maximum")]
    AboveMaximumDeposit,
    #[msg("Not authorized")]
    Unauthorized,
    #[msg("Nonce already used")]
    NonceAlreadyUsed,
    #[msg("Insufficient vault balance")]
    InsufficientBalance,
    #[msg("Invalid destination wallet")]
    InvalidDestination,
}
```

### 4.3 Solana-Specific Design Decisions

| Decision | Rationale |
|----------|-----------|
| PDA-based vault authority | Standard Solana pattern; no private key needed for the vault itself |
| Per-nonce PDA for replay protection | Existence of PDA = nonce used; cheaper than a large mapping |
| `[u8; 20]` for destination wallet | Rogue Chain is EVM, so addresses are 20 bytes |
| Separate SOL vault PDA | SOL is native, not an SPL token; needs its own account |
| Anchor events | Standard for off-chain indexing; relayer uses `getProgramAccounts` + event parsing |
| Multi-sig via Squads | Solana equivalent of Gnosis Safe; controls the authority key |

### 4.4 Supported Tokens on Solana

| Token | Mint Address | Decimals |
|-------|-------------|----------|
| SOL | Native (lamports) | 9 |
| USDC | `EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v` | 6 |
| USDT | `Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB` | 6 |

---

## 5. Cross-Contract Event Flow

### 5.1 Deposit Flow (User deposits on external chain, receives ROGUE)

```
STEP 1: User calls deposit() on BlocksterVault (Ethereum/Arbitrum)
        or deposit_sol()/deposit_token() on Solana
        ↓
STEP 2: Contract emits Deposit/DepositETH/DepositSOL/DepositToken event
        Contains: depositor, amount, token, destinationWallet, depositId
        ↓
STEP 3: Relayer service detects event
        - EVM: ethers.js contract.on("Deposit", ...)
        - Solana: WebSocket subscription on program logs
        - Waits for finality:
          - Ethereum: 2 blocks (~24 seconds)
          - Arbitrum: 1 block (~250ms, but wait for L1 confirmation ~1 min)
          - Solana: finalized commitment (~12 seconds)
        ↓
STEP 4: Relayer computes ROGUE amount
        - Fetches token price from CoinGecko / token_prices Mnesia table
        - Fetches ROGUE price
        - rogueAmount = (depositAmountUsd / roguePrice) * (1 - spreadBps/10000)
        ↓
STEP 5: Relayer sends ROGUE to user's smart wallet on Rogue Chain
        Option A: Direct native transfer (simplest, no contract needed)
        Option B: Call RogueWithdrawal.creditUser() (for audit trail)
        ↓
STEP 6: User sees ROGUE balance in Blockster UI
        - Balance sync detects new ROGUE via getBalance()
        - Updates user_rogue_balances Mnesia table
        - Broadcasts to all LiveViews via PubSub
```

### 5.2 Withdrawal Flow (User sends ROGUE, receives tokens on external chain)

```
STEP 1: User calls RogueWithdrawal.requestWithdrawal() on Rogue Chain
        - Sends ROGUE as msg.value
        - Specifies: destChainId, destToken, destAddress
        - Gasless via ERC-4337 Paymaster
        ↓
STEP 2: Contract emits WithdrawalRequested event
        Contains: user, rogueAmount, destChainId, destToken, destAddress, nonce
        ↓
STEP 3: Relayer service detects event
        - ethers.js listening on Rogue Chain RPC
        - Waits for 1 block confirmation on Rogue Chain
        ↓
STEP 4: Relayer computes destination amount
        - rogueAmountUsd = rogueAmount * roguePrice
        - destAmount = rogueAmountUsd / destTokenPrice * (1 - spreadBps/10000)
        - Adjusts for token decimals
        ↓
STEP 5: Relayer calls release() or releaseETH() on BlocksterVault (EVM)
        or release_sol()/release_token() on Solana vault
        - Uses unique nonce for replay protection
        - Passes rogueChainTxHash for cross-reference
        ↓
STEP 6: User receives tokens on destination chain
```

### 5.3 Relayer Service Architecture

The relayer is an extension of the existing BUX Minter service (`bux-minter.fly.dev`):

```
BUX Minter Service (Extended)
├── Existing endpoints (mint, balance, etc.)
├── NEW: Deposit event listeners
│   ├── Ethereum BlocksterVault listener
│   ├── Arbitrum BlocksterVault listener
│   └── Solana vault program listener
├── NEW: Withdrawal event listener
│   └── Rogue Chain RogueWithdrawal listener
├── NEW: Price conversion engine
│   ├── CoinGecko price feeds
│   ├── Spread calculation
│   └── Decimal normalization
├── NEW: Release execution
│   ├── EVM release() caller (ethers.js)
│   └── Solana release instruction sender
└── Existing: ROGUE sender (for crediting users)
```

---

## 6. Security Model

### 6.1 Key Separation

| Key | Holder | Permissions | Storage |
|-----|--------|-------------|---------|
| **Owner** | Gnosis Safe 3-of-5 multi-sig | All admin functions, upgrade, unpause | Hardware wallets (Ledger) |
| **Relayer** | Backend service hot wallet | `release()`, `releaseETH()`, `creditUser()` | Encrypted in Fly.io secrets |
| **Guardian** | Separate individual (not in multi-sig) | `emergencyPause()` only | Hardware wallet |

### 6.2 Threat Model

| Threat | Mitigation |
|--------|------------|
| **Relayer key compromised** | Can only release, not deposit or change config. Daily release cap limits damage. Guardian can pause. Owner can replace relayer. |
| **Guardian key compromised** | Can only pause (DoS). Owner can unpause and replace guardian. |
| **Multi-sig compromise (1-2 keys)** | 3-of-5 required. No single key can authorize changes. |
| **Replay attack** | Nonce tracking on all releases. Each nonce can only be used once. |
| **Reentrancy** | OpenZeppelin ReentrancyGuard on all external state-changing functions. |
| **Flash loan attack** | Not applicable — vault holds real assets, no price oracle manipulation possible. |
| **Front-running deposits** | Deposits go to specific destinationWallet; front-running cannot redirect funds. |
| **Malicious token (fee-on-transfer)** | Only whitelisted tokens accepted. SafeERC20 handles non-standard returns. USDT is known to have non-standard behavior — SafeERC20 handles this. |
| **ROGUE price manipulation** | Spread (0.3-0.5%) provides buffer. Large withdrawals (>$10K) require manual review. Price sourced from CoinGecko with sanity checks. |

### 6.3 Invariants

These must always hold. Monitor in production:

1. **Vault balance >= outstanding obligations.** Sum of all deposits minus all releases should equal vault balance.
2. **Every release has a unique nonce.** `usedNonces[nonce]` is checked before every release.
3. **Every credit has a unique nonce.** `usedCreditNonces[nonce]` checked on Rogue Chain.
4. **Paused state blocks all deposits and releases.** Only owner can unpause.
5. **Only whitelisted tokens accepted.** `whitelistedTokens[token]` checked on every deposit.

### 6.4 Monitoring Requirements

| Monitor | Alert Threshold | Action |
|---------|----------------|--------|
| Vault balance vs deposits | >5% discrepancy | Investigate, pause if growing |
| Release rate | >$50K/hour | Alert team |
| Single large release | >$10K | Require multi-sig approval |
| Failed releases | Any | Investigate immediately |
| Relayer wallet balance | <0.1 ETH (Ethereum), <0.01 ETH (Arbitrum) | Auto-refill from operations wallet |
| Contract pause events | Any | Immediate team notification |
| Unusual deposit patterns | >10 deposits/minute from same address | Rate limit investigation |

---

## 7. Upgrade Strategy

All contracts use UUPS proxy pattern (consistent with existing ROGUEBankroll):

### 7.1 EVM Contracts

1. Deploy implementation contract
2. Deploy UUPS proxy pointing to implementation
3. Initialize via proxy
4. Owner (multi-sig) holds upgrade authority

**Upgrade process:**
```bash
# 1. Compile new implementation
npx hardhat compile

# 2. Validate upgrade safety (checks storage layout)
npx hardhat run scripts/validate-upgrade.js

# 3. Deploy new implementation
npx hardhat run scripts/deploy-implementation.js

# 4. Multi-sig proposes upgrade
# (via Gnosis Safe UI or CLI)

# 5. Multi-sig signers approve (3 of 5)

# 6. Upgrade executes
```

**Critical rules (from CLAUDE.md):**
- NEVER change order or remove state variables — ONLY add at END
- NEVER enable `viaIR: true` — use helper functions for stack depth
- Test upgrade on fork first

### 7.2 Solana Program

- Use Squads multi-sig as upgrade authority
- `anchor upgrade` with multi-sig approval
- Can make program immutable after battle-testing

---

## 8. Gas Cost Estimates

### 8.1 Ethereum Mainnet

| Operation | Estimated Gas | Cost @ 30 gwei | Cost @ 100 gwei |
|-----------|-------------|-----------------|------------------|
| `deposit(USDC)` | ~80,000 | ~$6 | ~$20 |
| `deposit(USDT)` | ~80,000 | ~$6 | ~$20 |
| `depositETH()` | ~50,000 | ~$4 | ~$12 |
| `release(USDC)` (relayer) | ~70,000 | ~$5 | ~$17 |
| `release(USDT)` (relayer) | ~70,000 | ~$5 | ~$17 |
| `releaseETH()` (relayer) | ~45,000 | ~$3 | ~$10 |
| `emergencyPause()` | ~30,000 | ~$2 | ~$7 |

### 8.2 Arbitrum One

| Operation | Estimated Gas | Cost (typical) |
|-----------|-------------|----------------|
| `deposit(USDC)` | ~80,000 | ~$0.05 |
| `depositETH()` | ~50,000 | ~$0.03 |
| `release()` (relayer) | ~70,000 | ~$0.04 |
| `releaseETH()` (relayer) | ~45,000 | ~$0.03 |

### 8.3 Rogue Chain (Chain ID 560013)

| Operation | Estimated Gas | Cost @ 100 gwei |
|-----------|-------------|------------------|
| `requestWithdrawal()` | ~60,000 | ~0.006 ROGUE ($0.00000036) |
| `creditUser()` (relayer) | ~50,000 | ~0.005 ROGUE |

**Note:** Gas on Rogue Chain is effectively free (~$0.000001 per tx). User withdrawals are gasless via Paymaster.

### 8.4 Solana

| Operation | Estimated Cost |
|-----------|---------------|
| `deposit_sol()` | ~0.000005 SOL (~$0.001) |
| `deposit_token()` | ~0.000005 SOL (~$0.001) |
| `release_sol()` | ~0.000005 SOL (~$0.001) |
| `release_token()` | ~0.000005 SOL (~$0.001) |

### 8.5 Relayer Operational Costs

| Item | Monthly Estimate |
|------|-----------------|
| Ethereum relayer gas (100 releases/day) | ~$300-1,000 |
| Arbitrum relayer gas (200 releases/day) | ~$5-15 |
| Rogue Chain relayer gas | <$1 |
| Solana relayer gas | <$5 |
| Price feed API (CoinGecko Pro) | $130 |
| **Total monthly relayer costs** | **~$450-1,150** |

---

## 9. Deployment Checklist

### Phase 2A: EVM Vaults (Ethereum + Arbitrum)

- [ ] Deploy BlocksterVault implementation on Ethereum
- [ ] Deploy UUPS proxy on Ethereum
- [ ] Initialize with multi-sig, relayer, guardian addresses
- [ ] Whitelist USDC, USDT tokens
- [ ] Set deposit limits
- [ ] Deploy BlocksterVault implementation on Arbitrum
- [ ] Deploy UUPS proxy on Arbitrum
- [ ] Initialize with multi-sig, relayer, guardian addresses
- [ ] Whitelist USDC, USDT, ARB tokens
- [ ] Set deposit limits
- [ ] Deploy RogueWithdrawal on Rogue Chain
- [ ] Initialize with multi-sig, relayer, guardian addresses
- [ ] Verify all contracts on Etherscan/Arbiscan/Roguescan
- [ ] Extend BUX Minter service with event listeners
- [ ] Test deposit flow end-to-end on testnets
- [ ] Test withdrawal flow end-to-end on testnets
- [ ] Security audit (minimum 1 independent audit)
- [ ] Deploy to mainnet
- [ ] Fund relayer wallets
- [ ] Monitor for 48 hours before opening to users

### Phase 2B: Solana Vault

- [ ] Develop and test Anchor program locally
- [ ] Deploy to Solana devnet
- [ ] Test deposit/release flows
- [ ] Security audit
- [ ] Deploy to Solana mainnet
- [ ] Add Solana listener to relayer service
- [ ] Enable Solana destination in RogueWithdrawal contract
