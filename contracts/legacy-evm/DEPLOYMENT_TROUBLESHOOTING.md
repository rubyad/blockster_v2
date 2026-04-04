# BuxBoosterGame Deployment Troubleshooting Guide

This document describes the issues encountered while deploying the BuxBoosterGame smart contract to Rogue Chain and the solutions that fixed them.

## Environment

- **Network**: Rogue Chain Mainnet (Chain ID: 560013)
- **RPC URL**: `https://rpc.roguechain.io/rpc`
- **Gas Price**: 1000 gwei (1000000000000 wei) - this is the base fee on Rogue Chain
- **Tooling**: Hardhat + OpenZeppelin Upgrades Plugin

## Issues Encountered

### 1. Stack Too Deep Error

**Error:**
```
CompilerError: Stack too deep. Try compiling with `--via-ir` (cli) or the equivalent `viaIR: true`
```

**Cause:** The `placeBet` and `settleBet` functions had too many local variables, exceeding the EVM's stack limit of 16 variables.

**Solution:** Refactor large functions into smaller helper functions to reduce stack usage:

```solidity
// BEFORE - too many local variables in one function
function placeBet(...) {
    Commitment storage commitment = commitments[commitmentHash];
    // ... many more local variables
    TokenConfig storage config = tokenConfigs[token];
    uint256 expectedNonce = playerNonces[msg.sender];
    uint8 diffIndex = ...;
    uint256 maxBet = ...;
    // etc.
}

// AFTER - split into helper functions
function placeBet(...) {
    _validateCommitment(commitmentHash);
    uint8 diffIndex = _validateBetParams(token, amount, difficulty, predictions);
    IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    betId = _createBet(token, amount, difficulty, predictions, commitmentHash);
}

function _validateCommitment(bytes32 commitmentHash) internal { ... }
function _validateBetParams(...) internal view returns (uint8 diffIndex) { ... }
function _createBet(...) internal returns (bytes32 betId) { ... }
```

**Note:** While `viaIR: true` in hardhat.config.js can fix this, it increases bytecode size and may cause other issues. Refactoring is the preferred solution.

### 2. nginx 500 Internal Server Error

**Error:**
```
server response 500 Internal Server Error
responseBody: "<html>...<h1>500 Internal Server Error</h1>...</html>"
```

**Cause:** Multiple potential causes:
1. **Wrong gas price**: Using 1 gwei instead of 1000 gwei (Rogue Chain's base fee)
2. **Incorrect gas limit**: Too low for contract deployment
3. **Direct ethers.js deployment**: Some issues with how ethers.js handles the RPC

**Key Discovery:** Simple transactions (0-value transfers, small contracts <500 bytes) worked fine. Large contract deployments (>10KB) failed with generic 500 errors - the RPC server was returning 500 for various transaction errors without proper error messages.

**Solution:** Use OpenZeppelin's `upgrades.deployProxy()` instead of direct deployment:

```javascript
// This FAILED with 500 errors
const impl = await BuxBoosterGame.deploy({
  gasLimit: 3000000,
  maxFeePerGas: 1000000000000n,
  maxPriorityFeePerGas: 1000000000n
});

// This WORKED
const game = await upgrades.deployProxy(BuxBoosterGame, [], {
  initializer: "initialize",
  kind: "uups",
  unsafeAllow: ["constructor", "state-variable-assignment", "state-variable-immutable"]
});
```

### 3. Contract Not Upgrade Safe

**Error:**
```
Error: Contract is not upgrade safe

contracts/BuxBoosterGame.sol:417: Variable `MULTIPLIERS` is assigned an initial value
contracts/BuxBoosterGame.sol:334: Variable `__self` is immutable
```

**Cause:** OpenZeppelin's upgrades plugin validates contracts for upgrade safety. State variables with initial values and immutable variables are flagged as unsafe.

**Solution:** Add `unsafeAllow` options to bypass these checks (when you understand the implications):

```javascript
const game = await upgrades.deployProxy(BuxBoosterGame, [], {
  initializer: "initialize",
  kind: "uups",
  unsafeAllow: [
    "constructor",
    "state-variable-assignment",  // For MULTIPLIERS, FLIP_COUNTS, GAME_MODES
    "state-variable-immutable"    // For __self in UUPS
  ]
});
```

**Warning:** These values will be stored in the implementation contract, not the proxy. This is fine for constants like multipliers that won't change.

### 4. Initialize Function Parameters

**Error:** Deployment succeeded but initialization failed.

**Cause:** The original `initialize(address _settler, address _treasury)` function had parameters, which made deployment more complex and could cause issues.

**Solution:** Use a parameter-less `initialize()` function and set values via separate setter functions:

```solidity
// BEFORE
function initialize(address _settler, address _treasury) external initializer {
    settler = _settler;
    treasury = _treasury;
    ...
}

// AFTER
function initialize() initializer public {
    __Ownable_init(msg.sender);
    __ReentrancyGuard_init();
    __Pausable_init();
    __UUPSUpgradeable_init();
}

// Then call setSettler() after deployment
```

## Correct Hardhat Configuration

```javascript
// hardhat.config.js
module.exports = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 1  // Optimize for size when dealing with large contracts
      }
    }
  },
  networks: {
    rogueMainnet: {
      url: "https://rpc.roguechain.io/rpc",
      chainId: 560013,
      accounts: process.env.DEPLOYER_PRIVATE_KEY ? [process.env.DEPLOYER_PRIVATE_KEY] : [],
      gas: 5000000,
      gasPrice: 1000000000000,  // 1000 gwei - Rogue Chain base fee
      timeout: 120000
    }
  }
};
```

## Correct Contract Pattern

```solidity
contract BuxBoosterGame is Initializable, OwnableUpgradeable, ... {

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() initializer public {
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
    }
}
```

## Correct Deployment Script

```javascript
const { ethers, upgrades } = require("hardhat");

async function main() {
  const BuxBoosterGame = await ethers.getContractFactory("BuxBoosterGame");

  const game = await upgrades.deployProxy(BuxBoosterGame, [], {
    initializer: "initialize",
    kind: "uups",
    unsafeAllow: ["constructor", "state-variable-assignment", "state-variable-immutable"]
  });

  await game.waitForDeployment();
  console.log("Contract deployed at:", await game.getAddress());

  // Set settler after deployment
  const tx = await game.setSettler("0x...");
  await tx.wait();
}
```

## Lessons Learned

1. **Always use the correct gas price**: Check the network's base fee. Rogue Chain uses 1000 gwei.

2. **Use OpenZeppelin Upgrades Plugin**: It handles proxy deployment correctly and works better with Rogue Chain's RPC.

3. **Refactor large functions**: Split functions with many local variables into smaller helpers to avoid stack-too-deep errors.

4. **Keep initialize() simple**: Use parameter-less initialization and set values via setters.

5. **Understand unsafe allows**: When using `unsafeAllow`, understand the implications for upgradeability.

6. **RPC errors may be misleading**: A 500 error doesn't always mean the RPC is down - it could be a transaction error that's poorly reported.

## Deployed Contracts

| Contract | Address | Type |
|----------|---------|------|
| BuxBoosterGame (UUPS) | `0x97b6d6A8f2c6AF6e6fb40f8d36d60DF2fFE4f17B` | Proxy |
| Owner | `0x4BDC5602f2A3E04c6e3a9321A7AC5000e0A623e0` | EOA |
| Settler | `0x4BBe1C90a0A6974d8d9A598d081309D8Ff27bb81` | EOA |
