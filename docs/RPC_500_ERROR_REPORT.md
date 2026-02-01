# Rogue Chain RPC 500 Error Report

**Date**: January 31, 2026
**Issue**: Unable to deploy BuxBoosterGame V6 contract to Rogue Chain Mainnet
**Error**: HTTP 500 Internal Server Error from nginx/1.24.0

## Summary

Contract deployments fail with HTTP 500 errors from the Rogue Chain RPC endpoint (`https://rpc.roguechain.io/rpc`) when the contract bytecode exceeds approximately 4KB. The RPC returns a generic nginx 500 error instead of a proper JSON-RPC error response.

## Environment

- **Network**: Rogue Chain Mainnet (Chain ID: 560013)
- **RPC URL**: `https://rpc.roguechain.io/rpc`
- **Deployer Address**: `0x4BDC5602f2A3E04c6e3a9321A7AC5000e0A623e0`
- **Deployer Balance**: 99,240 ROGUE (sufficient for deployment)
- **Hardhat Version**: 2.26.0
- **ethers.js Version**: 6.16.0
- **Solidity Version**: 0.8.20

## Contract Details

- **Contract**: BuxBoosterGame.sol (V6 with referral system)
- **Proxy Address**: `0x97b6d6A8f2c6AF6e6fb40f8d36d60DF2fFE4f17B`
- **Current Implementation (V5)**: `0xb406d4965dd10918deac08355840f03e45ee661f`
- **V5 Bytecode Size**: 17,670 bytes (35,340 hex chars)
- **V6 Bytecode Size**: 20,632 bytes (41,264 hex chars)

## Error Details

```
HardhatError: HH110: Invalid JSON-RPC response received: <html>
<head><title>500 Internal Server Error</title></head>
<body>
<center><h1>500 Internal Server Error</h1></center>
<hr><center>nginx/1.24.0 (Ubuntu)</center>
</body>
</html>
```

The error occurs at `HardhatEthersSigner.sendTransaction` when attempting to broadcast the signed deployment transaction.

## Tests Performed

### 1. Basic RPC Connectivity
- ✅ `eth_blockNumber` - Works
- ✅ `eth_chainId` - Works (returns 0x88b8d = 560013)
- ✅ `eth_getBalance` - Works
- ✅ `eth_getTransactionCount` - Works
- ✅ `eth_gasPrice` - Works (returns 1000 gwei)
- ✅ Simple value transfer (nonce 77) - **SUCCEEDED**

### 2. Contract Deployment by Size
| Bytecode Size | Contract | Result |
|--------------|----------|--------|
| 161 bytes | TestDeploy | ✅ SUCCESS |
| 2,170 bytes | ERC20Upgradeable | ✅ SUCCESS |
| 3,957 bytes | SizeTest5000 | ✅ SUCCESS |
| 6,362 bytes | SizeTest8000 | ❌ 500 ERROR |
| 17,343 bytes | NFTRewarder | ❌ 500 ERROR |
| 17,670 bytes | BuxBoosterGame V5 | ❌ 500 ERROR |
| 20,632 bytes | BuxBoosterGame V6 | ❌ 500 ERROR |

**Conclusion**: The cutoff appears to be between 4KB and 6KB of bytecode.

### 3. Gas Parameter Variations
All failed with 500 error:
- `gasLimit: 5000000, gasPrice: 1000000000000` (1000 gwei)
- `gasLimit: 3878738` (exact V5 gas)
- `maxFeePerGas: 2000000000000, maxPriorityFeePerGas: 0` (EIP-1559)
- `type: 0` (legacy transaction)
- No explicit gas (let hardhat estimate)

### 4. Transaction Signing Methods
All failed with 500 error:
- Hardhat's `ContractFactory.deploy()`
- Direct ethers.js `ContractFactory.deploy()`
- Manual transaction signing via `wallet.signTransaction()` + `eth_sendRawTransaction`
- curl with explicit Content-Type and Content-Length headers

### 5. Raw Transaction Comparison

**V5 Deployment (SUCCEEDED on Dec 30, 2024)**:
- TX Hash: `0xadfda25ce898aa0209cf43bb7d1525c8ab880f92a1707073598bad74c5352932`
- Raw TX Size: 35,518 chars (17,759 bytes)
- Gas Limit: 3,878,738
- Gas Price: 1000 gwei
- Type: 0 (legacy)
- Nonce: 45

**V6 Deployment Attempt (FAILED)**:
- Raw TX Size: 41,442 chars (20,721 bytes)
- Gas Limit: 5,000,000
- Gas Price: 1000 gwei
- Type: 0 (legacy)
- Nonce: 78

### 6. eth_call Tests
Same 500 error pattern when sending bytecode via `eth_call`:
- 10,000 chars: OK
- 11,000 chars: 500 ERROR

This suggests the issue is in the nginx layer, not the RPC backend.

## Curl Verbose Output

```
> POST /rpc HTTP/1.1
> Host: rpc.roguechain.io
> Content-Type: application/json
> Content-Length: 41508
>
< HTTP/1.1 500 Internal Server Error
< Server: nginx/1.24.0 (Ubuntu)
< Content-Type: text/html
< Content-Length: 186
```

The response is immediate (not a timeout), indicating nginx rejects the request before processing.

## Hypothesis

The Rogue Chain RPC nginx proxy appears to have a `client_max_body_size` configuration that limits request bodies. Based on testing:
- Requests under ~5KB succeed
- Requests over ~6KB fail with 500

However, the V5 deployment on Dec 30, 2024 succeeded with a 17KB+ payload, suggesting either:
1. The nginx configuration changed since then
2. There's a different issue causing the 500 error
3. There's rate limiting or IP-based throttling

## What Has NOT Been Tried

1. Alternative RPC endpoints (none known)
2. VPN or different IP address
3. Contacting Rogue Chain team
4. Deploying from a different machine
5. Reducing contract size (would require removing features)

## Scripts Created for Debugging

All located in `contracts/bux-booster-game/scripts/`:
- `test-deploy.js` - Simple transfer test
- `test-deploy-contract.js` - Contract deploy test
- `deploy-v6-curl.js` - Deploy using curl bypass
- `deploy-exact-v5.js` - Deploy with V5 gas settings
- `deploy-legacy.js` - Deploy with legacy tx type
- `debug-deploy.js` - Transaction structure debugging
- `debug-deploy2.js` - eth_call simulation
- `debug-deploy3.js` - Gas limit testing
- `check-network.js` - Network parameters check

## Recommended Actions

1. **Contact Rogue Chain team** to investigate nginx configuration
2. **Check if there's an alternative RPC** endpoint for large transactions
3. **Verify no IP-based restrictions** were added since December
4. **Request nginx logs** to see actual error reason
5. **Test from different network** to rule out IP blocking

## Appendix: Successful Test Deploys

| Nonce | Contract | Address | TX Hash |
|-------|----------|---------|---------|
| 77 | TestDeploy | `0xFFb999fd4E5238F92575a3853D04766881Af7B94` | Self-transfer |
| 78 | ERC20Upgradeable | `0x3BebdeF27d28B1AdbC40A06F344655578C9573f1` | - |
| 79 | SizeTest5000 | `0x9B1F19F0A50B8BF6c20B414646999ebbc0584743` | - |
