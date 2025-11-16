# Deploy AccountExtension to Rogue Chain Testnet

## Overview
The AccountExtension contract provides the `execute()` and `executeBatch()` functions that ManagedAccount needs. Once deployed, we'll register it with the ManagedAccountFactory so all managed accounts can use these functions.

## Files Location
All thirdweb contract dependencies have been copied to:
```
scripts/account-extension/contracts/
```

## Deployment Steps

### 1. Deploy AccountExtension

You can deploy this using any method you prefer:
- Thirdweb Deploy CLI
- Hardhat
- Remix
- Foundry

**Contract to deploy**: `scripts/account-extension/contracts/prebuilts/account/utils/AccountExtension.sol`

**Constructor**: No constructor arguments needed (it has a default constructor)

**Network**: Rogue Chain Testnet
- Chain ID: 71499284269
- RPC: https://testnet-rpc.roguechain.io

### 2. Get the Function Selectors

After deployment, you'll need to register these function selectors with the ManagedAccountFactory:

**execute** function:
```
Selector: 0xb61d27f6
Function: execute(address,uint256,bytes)
```

**executeBatch** function:
```
Selector: 0x18dfb3c7
Function: executeBatch(address[],uint256[],bytes[])
```

### 3. Register with ManagedAccountFactory

After deploying AccountExtension, call `addExtension` on the ManagedAccountFactory at:
`0x39CeCF786830d1E073e737870E2A6e66fE92FDE9`

**From address**: `0xc2eF57fA90094731E216201417C2DA308C2E474B` (factory owner)

The `addExtension` function expects an Extension struct:
```solidity
struct Extension {
    bytes4[] selectors;      // [0xb61d27f6, 0x18dfb3c7]
    address implementation;  // <deployed AccountExtension address>
    string name;            // "AccountExtension"
    string metadataURI;     // "ipfs://AccountExtension" or ""
}
```

### 4. Verify Registration

After calling `addExtension`, verify by querying the Router on any managed account:

```javascript
// Call getImplementationForFunction(0xb61d27f6) on a managed account
// Should return the AccountExtension address instead of 0x0000...0000
```

## Quick Deploy with Thirdweb

```bash
cd scripts/account-extension
npx thirdweb deploy contracts/prebuilts/account/utils/AccountExtension.sol
```

Then select:
- Network: Custom (Rogue Chain Testnet)
- RPC URL: https://testnet-rpc.roguechain.io
- Chain ID: 71499284269

## After Deployment

Once AccountExtension is registered with the factory:
1. All existing managed accounts will instantly have access to `execute()` and `executeBatch()`
2. The paymaster test should work correctly
3. Users can execute transactions through their smart wallets

## Key Functions in AccountExtension

- `execute(address _target, uint256 _value, bytes calldata _calldata)` - Execute a single transaction
- `executeBatch(address[] calldata _target, uint256[] calldata _value, bytes[] calldata _calldata)` - Execute multiple transactions
- Both are restricted to `onlyAdminOrEntrypoint` modifier

## Notes

- The AccountExtension has dependencies on OpenZeppelin and other thirdweb contracts
- All dependencies are included in the `scripts/account-extension/contracts/` directory
- Make sure to deploy with Solidity compiler version ^0.8.11 or higher
