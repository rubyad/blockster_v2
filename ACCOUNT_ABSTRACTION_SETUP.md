# Account Abstraction (ERC-4337) Implementation Guide

## Overview

This document details the complete implementation of Account Abstraction (ERC-4337) on Rogue Chain testnet, enabling gasless smart wallet transactions with paymaster gas sponsorship.

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Components](#components)
3. [Implementation Steps](#implementation-steps)
4. [Troubleshooting Journey](#troubleshooting-journey)
5. [Final Configuration](#final-configuration)
6. [Testing](#testing)
7. [Key Learnings](#key-learnings)

---

## Architecture Overview

The ERC-4337 Account Abstraction stack consists of:

```
User → Frontend (Thirdweb SDK) → Smart Wallet → Bundler → EntryPoint → Paymaster
                                      ↓
                              ManagedAccountFactory
                                      ↓
                              AccountExtension (execute functions)
```

### Flow:
1. User initiates transaction via frontend
2. Thirdweb SDK creates UserOperation
3. Paymaster sponsors gas (adds paymasterAndData)
4. UserOperation sent to Bundler
5. Bundler validates and submits to EntryPoint on-chain
6. EntryPoint executes transaction via Smart Wallet
7. Paymaster pays for gas

---

## Components

### 1. EntryPoint Contract
- **Address**: `0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789`
- **Version**: v0.6.0 (Standard)
- **Purpose**: Core ERC-4337 contract that validates and executes UserOperations
- **Network**: Rogue Chain Testnet (Chain ID: 71499284269)

### 2. Bundler Service
- **URL**: `https://rogue-bundler.fly.dev`
- **Implementation**: Alchemy Rundler v0.9.2
- **Deployment**: Fly.io
- **Configuration**:
  - `--unsafe` flag: Bypasses strict paymaster signature validation
  - `--disable_entry_point_v0_7`: Only uses EntryPoint v0.6.0
  - Pool settings for unstaked entities
  - CORS enabled via Caddy reverse proxy

#### Bundler Files:
- `bundler/Dockerfile`: Container definition
- `bundler/entrypoint.sh`: Rundler startup script
- `bundler/chain-spec.json`: Rogue Chain configuration
- `bundler/Caddyfile`: CORS proxy configuration

### 3. ManagedAccountFactory
- **Address**: `0x39CeCF786830d1E073e737870E2A6e66fE92FDE9`
- **Type**: Thirdweb ManagedAccountFactory
- **Purpose**: Deploys smart wallet accounts using CREATE2
- **Features**:
  - Deterministic account addresses
  - Dynamic extension system (Router pattern)
  - Admin-controlled capabilities for all child accounts
  - Staked on EntryPoint (1 ROGUE)

### 4. AccountExtension (RogueAccountExtension)
- **Address**: `0xdDd603b68BC40D16F4570A33198241991c56D304`
- **Type**: Thirdweb AccountExtension (custom deployment)
- **Purpose**: Provides execute functionality for ManagedAccounts
- **Functions**:
  - `execute(address, uint256, bytes)` - Execute single transaction
  - `executeBatch(address[], uint256[], bytes[])` - Execute multiple transactions
  - EIP-1271 signature validation
  - Account permissions management
  - ERC721/ERC1155 token receiving

### 5. SimplePaymaster (EIP7702Paymaster)
- **Address**: `0xd4ECb9C22e0c7495e167698cb8D0D9c84F65c02a`
- **Type**: Simple paymaster (no signature validation)
- **Purpose**: Sponsors gas for all UserOperations
- **Features**:
  - No signature required (just 20-byte address)
  - Funded with ROGUE tokens
  - Staked on EntryPoint (1 ROGUE)

### 6. FactoryStakeExtension
- **Address**: `0x4601eec01fc3f51ec6459a15f79d5ec1d4e7a344`
- **Purpose**: Allows factory to manage EntryPoint stake
- **Functions**:
  - `addStake(address, uint32)`
  - `unlockStake(address)`
  - `withdrawStake(address, address)`

---

## Implementation Steps

### Step 1: Deploy Core Contracts

#### 1.1 Deploy EntryPoint v0.6.0
The standard EntryPoint was already deployed at `0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789` on Rogue Chain testnet.

#### 1.2 Deploy ManagedAccountFactory
Using Thirdweb Deploy:
```bash
# Deploy ManagedAccountFactory via Thirdweb dashboard
# Network: Rogue Chain Testnet
# EntryPoint: 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789
```

Result: `0x39CeCF786830d1E073e737870E2A6e66fE92FDE9`

#### 1.3 Deploy SimplePaymaster
Using Thirdweb Deploy:
```bash
# Deploy SimplePaymaster (EIP7702Paymaster)
# No constructor arguments needed
```

Result: `0xd4ECb9C22e0c7495e167698cb8D0D9c84F65c02a`

### Step 2: Stake Contracts on EntryPoint

Both the factory and paymaster need to be staked on the EntryPoint to be able to participate in UserOperations.

#### 2.1 Deploy FactoryStakeExtension
This extension allows the factory to manage its stake programmatically.

```bash
# Deploy FactoryStakeExtension
# Add to factory via addExtension()
```

Result: `0x4601eec01fc3f51ec6459a15f79d5ec1d4e7a344`

#### 2.2 Add FactoryStakeExtension to Factory
```javascript
// Call addExtension on ManagedAccountFactory
// Parameters:
{
  metadata: {
    name: "FactoryStakeExtension",
    metadataURI: "ipfs://FactoryStakeExtension",
    implementation: "0x4601eec01fc3f51ec6459a15f79d5ec1d4e7a344"
  },
  functions: [
    { functionSelector: "0x45171159", functionSignature: "addStake(address,uint32)" },
    { functionSelector: "0x4a1ce599", functionSignature: "unlockStake(address)" },
    { functionSelector: "0xb36f9705", functionSignature: "withdrawStake(address,address)" }
  ]
}
```

Transaction: `0x132f5f55855273611a754daa05f52c9800c304b45f72c61db9d0d60bfe564b1e`

#### 2.3 Stake Factory on EntryPoint
```javascript
// Call addStake via the factory's extension
factory.addStake(entryPoint, unstakeDelaySec)
// Send 1 ROGUE with transaction
```

Transaction: `0x132f5f55855273611a754daa05f52c9800c304b45f72c61db9d0d60bfe564b1e`

#### 2.4 Stake Paymaster on EntryPoint
```javascript
// Call addStake directly on EntryPoint
entryPoint.addStake(unstakeDelaySec)
// From paymaster address
// Send 1 ROGUE with transaction
```

### Step 3: Deploy and Configure Bundler

#### 3.0 Get Latest Rundler Version

Rundler is Alchemy's ERC-4337 bundler implementation written in Rust. We use pre-compiled binaries for faster deployment.

**Check Latest Version**:
```bash
# Visit GitHub releases page
open https://github.com/alchemyplatform/rundler/releases

# Or use API to get latest version
curl -s https://api.github.com/repos/alchemyplatform/rundler/releases/latest | grep tag_name
```

**Current Version Used**: v0.9.2

**Download Pre-built Binary**:
```bash
# For Linux x86_64 (used in Docker)
wget https://github.com/alchemyplatform/rundler/releases/download/v0.9.2/rundler-v0.9.2-x86_64-unknown-linux-gnu.tar.gz

# Extract
tar -xzf rundler-v0.9.2-x86_64-unknown-linux-gnu.tar.gz

# Test
./rundler --version
# Output: rundler 0.9.2
```

**Alternative: Build from Source** (takes ~30 minutes):
```bash
git clone https://github.com/alchemyplatform/rundler.git
cd rundler
git checkout v0.9.2
cargo build --release
# Binary will be in target/release/rundler
```

**Rundler CLI Arguments Reference**:
```bash
rundler node --help

# Key arguments we use:
# --node_http <URL>                  Ethereum node RPC URL
# --chain_spec <FILE>                Chain specification file
# --signer.private_keys <KEY>        Private key for signing bundles
# --rpc.port <PORT>                  RPC server port (default: 3000)
# --rpc.host <HOST>                  RPC server host (default: 127.0.0.1)
# --disable_entry_point_v0_7         Only use EntryPoint v0.6.0
# --pool.same_sender_mempool_count   Max UserOps per sender in mempool
# --pool.throttled_entity_mempool_count  Max UserOps for throttled entities
# --pool.throttled_entity_live_blocks    Blocks to keep throttled entities
# --unsafe                           Disable certain validations (use with caution)
```

**Version-Specific Notes**:

- **v0.9.2**: Latest stable with paymaster bug fixes
  - Stricter paymaster signature validation (requires `--unsafe` for simple paymasters)
  - Better mempool management
  - Improved gas estimation
  - Fixed reputation scoring issues

- **v0.4.0**: Previous version (not recommended)
  - Less strict validation
  - Gas estimation issues on some chains
  - Missing some ERC-4337 compliance fixes

**Upgrading Rundler**:
```bash
# 1. Update version in Dockerfile
RUN wget https://github.com/alchemyplatform/rundler/releases/download/v0.X.X/rundler-v0.X.X-x86_64-unknown-linux-gnu.tar.gz && \
    tar -xzf rundler-v0.X.X-x86_64-unknown-linux-gnu.tar.gz && \
    mv rundler /usr/local/bin/rundler && \
    chmod +x /usr/local/bin/rundler && \
    rm rundler-v0.X.X-x86_64-unknown-linux-gnu.tar.gz

# 2. Update cache bust comment
# Cache bust: 2025-11-15-v9-upgrade-to-vX.X.X

# 3. Test new CLI arguments
./rundler node --help

# 4. Deploy
flyctl deploy -a rogue-bundler
```

#### 3.1 Create Bundler Configuration

**bundler/chain-spec.json**:
```json
{
  "id": 71499284269,
  "entry_point_addresses": {
    "v0_6": "0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789"
  },
  "supports_eip1559": true
}
```

**bundler/Caddyfile**:
```
{
    auto_https off
}

:3000 {
    reverse_proxy localhost:3001

    header {
        Access-Control-Allow-Origin *
        Access-Control-Allow-Methods "GET, POST, OPTIONS"
        Access-Control-Allow-Headers "Content-Type, Authorization"
    }

    @options method OPTIONS
    respond @options 204
}

:8080 {
    reverse_proxy localhost:8081
}
```

**bundler/entrypoint.sh**:
```bash
#!/bin/bash
set -ex

echo "=== Starting Rundler v0.9.2 Deployment ==="
echo "Rundler version:"
rundler --version || echo "Warning: Could not get rundler version"

# Start Caddy in the background
caddy run --config /app/Caddyfile &
CADDY_PID=$!
echo "Started Caddy with PID: $CADDY_PID"

sleep 2

# Check if BUILDER_PRIVATE_KEY is set
if [ -z "$BUILDER_PRIVATE_KEY" ]; then
  echo "ERROR: BUILDER_PRIVATE_KEY environment variable is not set!"
  exit 1
fi

# Start Rundler with configuration
export RUST_LOG=rundler_pool=trace,rundler_sim=trace,rundler_builder=trace,debug
echo "=== Launching Rundler ==="
echo "RUST_LOG=$RUST_LOG"

exec rundler node \
  --node_http "https://testnet-rpc.roguechain.io" \
  --chain_spec "/app/chain-spec.json" \
  --signer.private_keys "$BUILDER_PRIVATE_KEY" \
  --rpc.port 3001 \
  --rpc.host "0.0.0.0" \
  --disable_entry_point_v0_7 \
  --pool.same_sender_mempool_count 100 \
  --pool.throttled_entity_mempool_count 100 \
  --pool.throttled_entity_live_blocks 100 \
  --unsafe
```

**bundler/Dockerfile**:
```dockerfile
FROM debian:bookworm-slim

WORKDIR /app

# Install runtime dependencies including Caddy
RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    curl \
    wget \
    bash \
    debian-keyring \
    debian-archive-keyring \
    apt-transport-https \
    && curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg \
    && curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list \
    && apt-get update \
    && apt-get install -y caddy \
    && rm -rf /var/lib/apt/lists/*

# Download pre-built Rundler binary
RUN wget https://github.com/alchemyplatform/rundler/releases/download/v0.9.2/rundler-v0.9.2-x86_64-unknown-linux-gnu.tar.gz && \
    tar -xzf rundler-v0.9.2-x86_64-unknown-linux-gnu.tar.gz && \
    mv rundler /usr/local/bin/rundler && \
    chmod +x /usr/local/bin/rundler && \
    rm rundler-v0.9.2-x86_64-unknown-linux-gnu.tar.gz

# Copy configuration files
COPY chain-spec.json /app/chain-spec.json
COPY Caddyfile /app/Caddyfile
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

# Expose ports
EXPOSE 3000 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:3000/health || exit 1

ENTRYPOINT ["/app/entrypoint.sh"]
```

#### 3.2 Deploy Bundler to Fly.io

```bash
# Set secrets
flyctl secrets set BUILDER_PRIVATE_KEY="0x..." -a rogue-bundler

# Deploy
flyctl deploy -a rogue-bundler

# Verify
curl https://rogue-bundler.fly.dev/health
# Should return: "ok"
```

### Step 4: Deploy AccountExtension

The ManagedAccount uses a Router pattern where function calls are delegated to registered extension contracts. The `execute()` and `executeBatch()` functions needed to be added via AccountExtension.

#### 4.1 Get AccountExtension Source Code

```bash
cd /tmp
git clone --depth 1 https://github.com/thirdweb-dev/contracts.git thirdweb-contracts

# Copy to project
mkdir -p scripts/account-extension
cp -r thirdweb-contracts/contracts scripts/account-extension/
```

The AccountExtension includes:
- `execute(address, uint256, bytes)` function
- `executeBatch(address[], uint256[], bytes[])` function
- EIP-1271 signature validation
- Permission management
- Token receiving (ERC721/ERC1155)

#### 4.2 Deploy AccountExtension

Using Thirdweb Deploy:
```bash
cd scripts/account-extension
npx thirdweb deploy contracts/prebuilts/account/utils/AccountExtension.sol
```

Deployed to: `0xdDd603b68BC40D16F4570A33198241991c56D304`

Contract name: `RogueAccountExtension`

#### 4.3 Register AccountExtension with Factory

The factory needs to map function selectors to the AccountExtension implementation.

```javascript
// Call addExtension on ManagedAccountFactory
// Parameters:
{
  metadata: {
    name: "RogueAccountExtension",
    metadataURI: "ipfs://RogueAccountExtension",
    implementation: "0xdDd603b68BC40D16F4570A33198241991c56D304"
  },
  functions: [
    {
      functionSelector: "0xb61d27f6",
      functionSignature: "execute(address,uint256,bytes)"
    },
    {
      functionSelector: "0x18dfb3c7",
      functionSignature: "executeBatch(address[],uint256[],bytes[])"
    }
  ]
}
```

Transaction: `0xa3ec5090ad728a66c9f304a9fed74ccf5ecfd5224171df7f9a643b55f5866769`

**Verification**:
```bash
# Query factory for execute() implementation
curl -X POST https://testnet-rpc.roguechain.io \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "eth_call",
    "params": [{
      "to": "0x39CeCF786830d1E073e737870E2A6e66fE92FDE9",
      "data": "0xce0b6013b61d27f600000000000000000000000000000000000000000000000000000000"
    }, "latest"],
    "id": 1
  }'

# Should return: "0x000000000000000000000000ddd603b68bc40d16f4570a33198241991c56d304"
# (the AccountExtension address)
```

### Step 5: Configure Frontend (Thirdweb SDK)

**assets/js/home_hooks.js**:

```javascript
// Network configuration
const id = 71499284269;
const rpc = "https://testnet-rpc.roguechain.io";
const factoryAddress = "0x39CeCF786830d1E073e737870E2A6e66fE92FDE9";
const paymasterAddress = "0xd4ECb9C22e0c7495e167698cb8D0D9c84F65c02a";
const entryPoint = "0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789";

// Define Rogue Chain
const rogueChain = defineChain({
  id: id,
  name: "Rogue Chain",
  nativeCurrency: { name: "Rogue", symbol: "ROGUE", decimals: 18 },
  rpc: rpc,
  blockExplorer: "https://testnet-explorer.roguechain.io/"
});

// Smart wallet configuration
const walletConfig = {
  chain: rogueChain,
  factoryAddress: factoryAddress,
  gasless: true,
  overrides: {
    entryPoint: entryPoint,
    bundlerUrl: "https://rogue-bundler.fly.dev",

    paymaster: async (userOp) => {
      console.log('💰 Paymaster function called');

      // Fill in gas values
      if (!userOp.preVerificationGas || userOp.preVerificationGas === '0x0') {
        userOp.preVerificationGas = '0xb708'; // 46856
      }

      const hasInitCode = userOp.initCode && userOp.initCode !== '0x' && userOp.initCode.length > 2;

      if (!userOp.verificationGasLimit || userOp.verificationGasLimit === '0x0') {
        userOp.verificationGasLimit = hasInitCode ? '0x061a80' : '0x0186a0'; // 400k for deployment, 100k otherwise
      }

      if (!userOp.callGasLimit || userOp.callGasLimit === '0x0') {
        userOp.callGasLimit = '0x1d4c0'; // 120000
      }

      // Return paymaster data (simple 20-byte address)
      return {
        paymasterAndData: paymasterAddress,
        callGasLimit: userOp.callGasLimit,
        verificationGasLimit: userOp.verificationGasLimit,
        preVerificationGas: userOp.preVerificationGas,
      };
    },
  },
  sponsorGas: true,
};

// Create smart wallet
this.wallet = smartWallet(walletConfig);
```

---

## Troubleshooting Journey

### Issue 1: AA23 "Invalid UserOp signature or paymaster signature"

**Problem**: Rundler v0.9.2 has stricter validation than v0.4.0 and was rejecting our SimplePaymaster because it doesn't provide a signature.

**Solution**: Added `--unsafe` flag to Rundler configuration to bypass strict paymaster signature validation.

```bash
# In entrypoint.sh
exec rundler node \
  --node_http "https://testnet-rpc.roguechain.io" \
  --unsafe  # <-- This flag bypasses strict validation
```

### Issue 2: "Router: function does not exist" Error

**Problem**: When UserOperations tried to execute transactions, the smart wallet returned "Router: function does not exist" for the `execute()` function.

**Root Cause**: ManagedAccount uses a Router pattern where function calls are delegated to registered extension contracts. The factory had no extension registered for the `execute()` function selector (`0xb61d27f6`).

**Investigation**:
```bash
# Querying factory for execute() implementation
curl -X POST https://testnet-rpc.roguechain.io \
  -d '{"jsonrpc":"2.0","method":"eth_call","params":[{
    "to":"0x39CeCF786830d1E073e737870E2A6e66fE92FDE9",
    "data":"0xce0b6013b61d27f600000000000000000000000000000000000000000000000000000000"
  },"latest"],"id":1}'

# Returned: 0x0000000000000000000000000000000000000000000000000000000000000000
# (zero address = not registered)
```

**Solution**:
1. Deployed AccountExtension contract
2. Registered it with the factory via `addExtension()`
3. This mapped `execute()` and `executeBatch()` selectors to the AccountExtension implementation

**After Fix**:
```bash
# Same query now returns:
# 0x000000000000000000000000ddd603b68bc40d16f4570a33198241991c56d304
# (AccountExtension address)
```

### Issue 3: Address Checksum Mismatch (False Positive)

**Problem**: Debug logs showed "MISMATCH DETECTED" between Thirdweb SDK sender and factory return address.

**Example**:
```
Thirdweb SDK sender: 0xE4Da2B1Fd0a18B28B3610ed916C940Fdf5A355CD
Factory will return: 0xe4da2b1fd0a18b28b3610ed916c940fdf5a355cd
```

**Root Cause**: This was just a checksum difference (uppercase vs lowercase) - the addresses are identical. This is NOT an actual mismatch and doesn't cause AA14 errors.

**Learning**: EVM addresses are case-insensitive. The checksum (mixed case) is just a validation mechanism defined in EIP-55.

### Issue 4: CORS Errors

**Problem**: Browser couldn't call bundler RPC endpoint due to CORS restrictions.

**Solution**: Added Caddy reverse proxy in front of Rundler to add CORS headers.

```
# Caddyfile
:3000 {
    reverse_proxy localhost:3001

    header {
        Access-Control-Allow-Origin *
        Access-Control-Allow-Methods "GET, POST, OPTIONS"
        Access-Control-Allow-Headers "Content-Type, Authorization"
    }

    @options method OPTIONS
    respond @options 204
}
```

---

## Final Configuration

### Network Details
- **Name**: Rogue Chain Testnet
- **Chain ID**: 71499284269
- **RPC**: https://testnet-rpc.roguechain.io
- **Explorer**: https://testnet-explorer.roguechain.io/

### Deployed Contracts

| Contract | Address | Purpose |
|----------|---------|---------|
| EntryPoint v0.6.0 | `0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789` | Core ERC-4337 contract |
| ManagedAccountFactory | `0x39CeCF786830d1E073e737870E2A6e66fE92FDE9` | Deploys smart wallets |
| RogueAccountExtension | `0xdDd603b68BC40D16F4570A33198241991c56D304` | Execute functions |
| FactoryStakeExtension | `0x4601eec01fc3f51ec6459a15f79d5ec1d4e7a344` | Factory staking |
| SimplePaymaster | `0xd4ECb9C22e0c7495e167698cb8D0D9c84F65c02a` | Gas sponsorship |

### Services

| Service | URL | Version |
|---------|-----|---------|
| Bundler | https://rogue-bundler.fly.dev | Rundler v0.9.2 |

### Bundler Configuration

```bash
rundler node \
  --node_http "https://testnet-rpc.roguechain.io" \
  --chain_spec "/app/chain-spec.json" \
  --signer.private_keys "$BUILDER_PRIVATE_KEY" \
  --rpc.port 3001 \
  --rpc.host "0.0.0.0" \
  --disable_entry_point_v0_7 \
  --pool.same_sender_mempool_count 100 \
  --pool.throttled_entity_mempool_count 100 \
  --pool.throttled_entity_live_blocks 100 \
  --unsafe
```

**Key Flags**:
- `--unsafe`: Bypasses strict paymaster signature validation
- `--disable_entry_point_v0_7`: Only uses EntryPoint v0.6.0
- Pool settings: Allow unstaked entities for testing

---

## Testing

### Test Paymaster Flow

1. **Clear browser cache**:
```javascript
const keysToRemove = [];
for (let i = 0; i < localStorage.length; i++) {
  const key = localStorage.key(i);
  if (key && (key.includes('thirdweb') || key.includes('walletconnect') || key.includes('smartAccount'))) {
    keysToRemove.push(key);
  }
}
keysToRemove.forEach(key => localStorage.removeItem(key));
location.reload();
```

2. **Login** with a new email address

3. **Click "Test Paymaster"** button

4. **Expected flow**:
   - Smart account address calculated via CREATE2
   - UserOperation created with `initCode` (for deployment)
   - Paymaster adds `paymasterAndData`
   - Bundler validates and submits to EntryPoint
   - Account deployed via factory
   - Transaction executed via AccountExtension
   - Gas paid by paymaster

5. **Verify success**:
   - Check console logs for transaction hash
   - Verify on explorer: https://testnet-explorer.roguechain.io/
   - Check account was deployed
   - Check transaction succeeded (status: 0x1)

### Example Successful Transaction

**Transaction**: `0x2e7df8bc3d383a3eb5b36fd834d94f77559da1887109dd4585458cf41a00d283`

**Smart Account**: `0xE4Da2B1Fd0a18B28B3610ed916C940Fdf5A355CD`

**Gas Used**: 438,637 gas (paid by paymaster)

**Events**:
1. Account admin set
2. Factory account created
3. Account initialized
4. Factory account added
5. EntryPoint deposit
6. Signature aggregator changed
7. UserOperation event
8. Paymaster UserOperation sponsored

---

## Key Learnings

### 1. ManagedAccount Router Pattern

ManagedAccounts don't have functions hardcoded in their bytecode. Instead, they use a Router pattern:

- Account is a minimal proxy (EIP-1167) pointing to an implementation
- Implementation has a `getImplementationForFunction(bytes4 selector)` function
- Function calls are delegated to registered extension contracts
- Extensions are registered in the **factory**, not individual accounts
- When factory's extension registry is updated, **all child accounts** instantly get the new functionality

**Key Insight**: This is why we had to deploy and register AccountExtension - the `execute()` function wasn't available until we registered it with the factory.

### 2. Rundler v0.9.2 Strict Validation

Rundler v0.9.2 has much stricter validation than v0.4.0:

- Validates paymaster signatures by default
- Our SimplePaymaster doesn't provide signatures (just 20-byte address)
- Solution: `--unsafe` flag bypasses this validation
- **For production**: Use a proper paymaster with signature validation

### 3. EVM Address Checksums

Addresses like these are **identical**:
- `0xE4Da2B1Fd0a18B28B3610ed916C940Fdf5A355CD`
- `0xe4da2b1fd0a18b28b3610ed916c940fdf5a355cd`

The mixed case is just a checksum (EIP-55) for validation. Don't treat case differences as mismatches.

### 4. Gas Estimation Challenges

Rogue Chain RPC sometimes has issues with gas estimation for UserOperations:
- Fixed gas values work better than dynamic estimation
- Different gas limits needed for deployment vs regular transactions
- `verificationGasLimit`: 400k for deployment, 100k otherwise
- `callGasLimit`: 120k
- `preVerificationGas`: 46856

### 5. Staking Requirements

Both factory and paymaster must be staked on EntryPoint:
- Minimum stake: implementation-dependent (we used 1 ROGUE)
- Unstake delay: prevents instant withdrawal after malicious behavior
- Factory needs special extension to manage stake programmatically

### 6. CREATE2 Deterministic Addresses

Smart wallet addresses are deterministic based on:
- Factory address
- Owner address (admin)
- Salt (usually derived from admin address)

Same inputs → same address, even before deployment.

### 7. CORS for Bundler

Browsers require CORS headers for cross-origin RPC calls:
- Rundler doesn't provide CORS headers by default
- Solution: Caddy reverse proxy adds headers
- Must handle OPTIONS preflight requests

---

## Maintenance

### Update Bundler

```bash
# Update entrypoint.sh or Dockerfile
# Increment cache bust version
# bundler/Dockerfile line 33:
# Cache bust: 2025-11-15-v9-description

# Deploy
flyctl deploy -a rogue-bundler
```

### Add New Extensions to Factory

```javascript
// 1. Deploy extension contract
// 2. Call addExtension on factory:

factory.addExtension({
  metadata: {
    name: "ExtensionName",
    metadataURI: "ipfs://...",
    implementation: "0x..."
  },
  functions: [
    {
      functionSelector: "0x12345678",
      functionSignature: "functionName(type1,type2)"
    }
  ]
});
```

### Fund Paymaster

```bash
# Send ROGUE tokens to paymaster address
# Paymaster needs balance to pay for gas
```

### Monitor Bundler

```bash
# Check health
curl https://rogue-bundler.fly.dev/health

# View logs
flyctl logs -a rogue-bundler

# Check status
flyctl status -a rogue-bundler
```

---

## Resources

- [ERC-4337 Specification](https://eips.ethereum.org/EIPS/eip-4337)
- [Alchemy Rundler](https://github.com/alchemyplatform/rundler)
- [Thirdweb Smart Wallets](https://portal.thirdweb.com/wallets/smart-wallet)
- [Thirdweb Contracts](https://github.com/thirdweb-dev/contracts)
- [Rogue Chain Explorer](https://testnet-explorer.roguechain.io/)

---

## Success Criteria

✅ Users can create smart wallets without needing ROGUE tokens

✅ Paymaster sponsors gas for all transactions

✅ Account deployment works via UserOperations

✅ Execute and executeBatch functions work correctly

✅ No AA14, AA23, or Router errors

✅ Bundler processes UserOperations successfully

✅ Transactions confirmed on-chain

---

**Status**: ✅ COMPLETE - All Account Abstraction features working on Rogue Chain testnet

**Last Updated**: November 15, 2025

**Version**: 1.0
