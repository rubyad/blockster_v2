# BuxBoosterGame Contract Upgrades

This document covers the upgrade process for the BuxBoosterGame UUPS proxy contract and troubleshooting common issues.

## Contract Information

- **Proxy Address**: `0x97b6d6A8f2c6AF6e6fb40f8d36d60DF2fFE4f17B` (never changes)
- **Pattern**: UUPS (Universal Upgradeable Proxy Standard)
- **Network**: Rogue Chain Mainnet (Chain ID: 560013)
- **Owner**: `0x4BDC5602f2A3E04c6e3a9321A7AC5000e0A623e0`

## Standard Upgrade Process

### Prerequisites
1. Make code changes to `contracts/BuxBoosterGame.sol`
2. **CRITICAL**: Never remove or reorder state variables - only add new ones at the end
3. Test changes locally

### Upgrade Commands

```bash
cd contracts/bux-booster-game

# 1. Force import proxy (if .openzeppelin metadata is stale)
npx hardhat run scripts/force-import.js --network rogueMainnet

# 2. Upgrade to new implementation
npx hardhat run scripts/upgrade.js --network rogueMainnet
```

## Common Issues and Solutions

### Issue 1: "Deployment at address X is not registered"

**Error Message:**
```
Error: Deployment at address 0x8D7ab3486B8B71720F66Cb09291e5191d197c8AC is not registered
To register a previously deployed proxy for upgrading, use the forceImport function.
```

**Cause**: OpenZeppelin's upgrades plugin lost track of the implementation address in `.openzeppelin/unknown-560013.json`

**Solution**: Use `force-import.js` before upgrading
```bash
npx hardhat run scripts/force-import.js --network rogueMainnet
npx hardhat run scripts/upgrade.js --network rogueMainnet
```

### Issue 2: "execution reverted" during upgrade

**Error**: Transaction reverts when calling `upgradeProxy()`

**Cause**: OpenZeppelin plugin's gas estimation may fail on Rogue Chain

**Solution**: Use manual upgrade with explicit gas limit
```bash
npx hardhat run scripts/upgrade-manual.js --network rogueMainnet
```

The manual upgrade script:
1. Deploys new implementation contract directly
2. Calls `upgradeToAndCall()` on the proxy with `gasLimit: 5000000`
3. Bypasses OpenZeppelin's gas estimation issues

### Issue 3: Deleting .openzeppelin directory doesn't help

**Why**: The plugin queries the on-chain implementation address via the proxy's ERC1967 storage slot. Deleting local metadata doesn't affect this.

**Solution**: Always use `forceImport` to re-register the proxy in plugin metadata.

## Storage Layout Safety

### CRITICAL RULES

1. **Never remove state variables** - This shifts storage slots and corrupts data
2. **Never reorder state variables** - Same issue as removal
3. **Only add new variables at the END** - After all existing variables
4. **Keep unused variables** - If you stop using a variable, leave it in place with a comment

### Example: Nonce Simplification Upgrade (Dec 2024)

We removed nonce validation from the contract but **kept the `playerNonces` mapping** to preserve storage layout:

```solidity
// Line 436 - KEPT even though no longer used for validation
mapping(address => uint256) public playerNonces;
```

**What we changed:**
- Removed: `playerNonces[player] = nonce` from `submitCommitment()`
- Removed: `if (commitment.nonce != playerNonces[msg.sender])` from `_validateCommitment()`
- Removed: `nonce` parameter from `placeBet()` function signature

**Storage layout preserved:**
- All state variables remain in same slots
- Safe to upgrade without data migration

## Verification After Upgrade

```bash
npx hardhat run scripts/verify-upgrade.js --network rogueMainnet
```

Checks:
- Arrays are initialized correctly
- Basic functions work
- State preserved from previous version

## Implementation Addresses (Historical)

| Date | Implementation Address | Changes |
|------|----------------------|---------|
| Dec 28, 2024 | `0x766B68bf3CB02C19296c8e8e7C1394bb51ab5e6B` | Removed nonce validation |
| Dec 27, 2024 | `0x8D7ab3486B8B71720F66Cb09291e5191d197c8AC` | Added array initialization |
| Earlier | `0x4263630a5Aa170b349d144c43881C6872bE302Bc` | Initial deployment |

## Useful Scripts

All located in `contracts/bux-booster-game/scripts/`:

- `force-import.js` - Register proxy in OpenZeppelin metadata
- `upgrade.js` - Standard upgrade using OpenZeppelin plugin
- `upgrade-manual.js` - Manual upgrade with explicit gas (use if standard fails)
- `verify-upgrade.js` - Verify upgrade succeeded
- `check-owner.js` - Verify deployer is contract owner

## Network Configuration

From `hardhat.config.js`:

```javascript
networks: {
  rogueMainnet: {
    url: "https://rpc.roguechain.io/rpc",
    chainId: 560013,
    accounts: [process.env.DEPLOYER_PRIVATE_KEY],
    gas: 5000000,
    gasPrice: 1000000000000,  // 1000 gwei
    timeout: 120000
  }
}
```

## Troubleshooting Checklist

Before upgrading:
- [ ] Storage variables only added at end, none removed/reordered
- [ ] Deployer wallet has ROGUE for gas
- [ ] `.openzeppelin/unknown-560013.json` exists or will use `force-import.js`
- [ ] Contract compiles: `npx hardhat compile`
- [ ] Verified you're on correct network in hardhat.config.js

If upgrade fails:
1. Check if deployer is owner: `npx hardhat run scripts/check-owner.js --network rogueMainnet`
2. Try force import: `npx hardhat run scripts/force-import.js --network rogueMainnet`
3. Try manual upgrade: `npx hardhat run scripts/upgrade-manual.js --network rogueMainnet`
4. Check RPC is responsive: `curl https://rpc.roguechain.io/rpc`

## References

- OpenZeppelin UUPS: https://docs.openzeppelin.com/contracts/4.x/api/proxy#UUPSUpgradeable
- Hardhat Upgrades: https://docs.openzeppelin.com/upgrades-plugins/1.x/
