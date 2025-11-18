# 🎉 Account Abstraction Mainnet Configuration Complete

**Configuration Date**: November 16, 2025
**Status**: ✅ **PRODUCTION READY - Both Testnet and Mainnet**

---

## 📋 Executive Summary

Account Abstraction (ERC-4337) has been successfully configured for **both Rogue Testnet and Rogue Mainnet** with automatic environment detection. The system seamlessly switches between testnet (localhost:4000) and mainnet (production) configurations.

### ✅ Verification Results

```
🚀 Account Abstraction Deployment Verification
📅 2025-11-16

Testnet: ✅ PASSED - All 10 checks passed
Mainnet: ✅ PASSED - All 10 checks passed

🎉 All networks are ready for Account Abstraction!
```

---

## 🌐 Network Configurations

### Rogue Testnet (Localhost Development)
**Triggered when**: `window.location.origin == "http://localhost:4000"`

| Component | Address | Status |
|-----------|---------|--------|
| **Chain ID** | `71499284269` | Active |
| **RPC URL** | `https://testnet-rpc.roguechain.io` | ✅ |
| **Explorer** | `https://testnet-explorer.roguechain.io/` | ✅ |
| **EntryPoint** | `0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789` | ✅ Canonical v0.6.0 |
| **ManagedAccountFactory** | `0x39CeCF786830d1E073e737870E2A6e66fE92FDE9` | ✅ Staked: 1.0 ROGUE |
| **Paymaster** | `0xd4ECb9C22e0c7495e167698cb8D0D9c84F65c02a` | ✅ Deposit: 9,998.12 ROGUE |
| **AccountExtension** | `0xdDd603b68BC40D16F4570A33198241991c56D304` | ✅ Registered |
| **Bundler Wallet** | `0xd75A64aDf49E180e6f4B1f1723ed4bdA16AFA06f` | ✅ Balance: 10,000 ROGUE |
| **Bundler URL** | `https://rogue-bundler.fly.dev` | Environment: `testnet` |

### Rogue Mainnet (Production)
**Triggered when**: `window.location.origin != "http://localhost:4000"`

| Component | Address | Status |
|-----------|---------|--------|
| **Chain ID** | `560013` | Active |
| **RPC URL** | `https://rpc.roguechain.io/rpc` | ✅ |
| **Explorer** | `https://roguescan.io` | ✅ |
| **EntryPoint** | `0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789` | ✅ Canonical v0.6.0 |
| **ManagedAccountFactory** | `0xfbbe1193496752e99BA6Ad74cdd641C33b48E0C3` | ✅ Staked: 1.0 ROGUE |
| **Paymaster** | `0x804cA06a85083eF01C9aE94bAE771446c25269a6` | ✅ Deposit: 1,000,000 ROGUE |
| **AccountExtension** | `0xB447e3dBcf25f5C9E2894b9d9f1207c8B13DdFfd` | ✅ Registered |
| **Bundler Wallet** | `0xd75A64aDf49E180e6f4B1f1723ed4bdA16AFA06f` | ✅ Balance: 1,000,000 ROGUE |
| **Bundler URL** | `https://rogue-bundler.fly.dev` | Environment: `mainnet` |

---

## 🔧 Configuration Files Updated

### 1. Frontend Configuration
**File**: [`assets/js/home_hooks.js`](assets/js/home_hooks.js#L25-L42)

```javascript
if (window.location.origin != "http://localhost:4000") {
    // Mainnet (Production) - Chain ID: 560013
    id = 560013
    blockExplorer = "https://roguescan.io"
    rpc = "https://rpc.roguechain.io/rpc"
    factoryAddress = "0xfbbe1193496752e99BA6Ad74cdd641C33b48E0C3"
    paymasterAddress = "0x804cA06a85083eF01C9aE94bAE771446c25269a6"
    entryPoint = "0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789"
} else {
    // Testnet (Localhost) - Chain ID: 71499284269
    id = 71499284269
    blockExplorer = "https://testnet-explorer.roguechain.io/"
    rpc = "https://testnet-rpc.roguechain.io"
    factoryAddress = "0x39CeCF786830d1E073e737870E2A6e66fE92FDE9"
    paymasterAddress = "0xd4ECb9C22e0c7495e167698cb8D0D9c84F65c02a"
    entryPoint = "0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789"
}
```

### 2. Bundler Chain Specifications

#### Testnet Chain Spec
**File**: [`bundler/chain-spec.json`](bundler/chain-spec.json)
```json
{
  "id": 71499284269,
  "entry_point_addresses": {
    "v0_6": "0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789"
  },
  "supports_eip1559": true
}
```

#### Mainnet Chain Spec
**File**: [`bundler/chain-spec-mainnet.json`](bundler/chain-spec-mainnet.json)
```json
{
  "id": 560013,
  "entry_point_addresses": {
    "v0_6": "0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789"
  },
  "supports_eip1559": true
}
```

### 3. Bundler Entrypoint Script
**File**: [`bundler/entrypoint.sh`](bundler/entrypoint.sh#L22-L38)

```bash
# Determine environment and set RPC URL and chain spec accordingly
# Default to testnet if ROGUE_ENV is not set
ROGUE_ENV=${ROGUE_ENV:-testnet}

if [ "$ROGUE_ENV" = "mainnet" ]; then
  echo "=== MAINNET CONFIGURATION ==="
  NODE_RPC="https://rpc.roguechain.io/rpc"
  CHAIN_SPEC="/app/chain-spec-mainnet.json"
else
  echo "=== TESTNET CONFIGURATION ==="
  NODE_RPC="https://testnet-rpc.roguechain.io"
  CHAIN_SPEC="/app/chain-spec.json"
fi
```

### 4. Bundler Dockerfile
**File**: [`bundler/Dockerfile`](bundler/Dockerfile#L32-L38)

```dockerfile
# Copy chain specs (testnet and mainnet), Caddyfile, and entrypoint script
# Cache bust: 2025-11-16-mainnet-support
COPY chain-spec.json /app/chain-spec.json
COPY chain-spec-mainnet.json /app/chain-spec-mainnet.json
COPY Caddyfile /app/Caddyfile
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh
```

---

## 🚀 Deployment Instructions

### For Fly.io Bundler Deployment

#### Deploy to Testnet (Default)
```bash
# No environment variable needed - defaults to testnet
flyctl deploy
```

#### Deploy to Mainnet
```bash
# Set environment variable for mainnet
flyctl secrets set ROGUE_ENV=mainnet

# Deploy
flyctl deploy
```

#### Switch Between Environments
```bash
# Switch to mainnet
flyctl secrets set ROGUE_ENV=mainnet
flyctl deploy

# Switch back to testnet
flyctl secrets unset ROGUE_ENV
flyctl deploy
```

### Local Testing

#### Test with Testnet
```bash
# Build the image
docker build -t rogue-bundler:latest ./bundler

# Run with testnet config (default)
docker run -p 3000:3000 \
  -e BUILDER_PRIVATE_KEY="your_private_key" \
  rogue-bundler:latest
```

#### Test with Mainnet
```bash
# Run with mainnet config
docker run -p 3000:3000 \
  -e BUILDER_PRIVATE_KEY="your_private_key" \
  -e ROGUE_ENV=mainnet \
  rogue-bundler:latest
```

---

## 🔍 Verification

### Automated Verification Script
**File**: [`scripts/verify-aa-deployment.js`](scripts/verify-aa-deployment.js)

Run verification for both networks:
```bash
node scripts/verify-aa-deployment.js
```

**Output**:
```
🚀 Account Abstraction Deployment Verification
📅 2025-11-16T18:50:48.743Z

Testnet: ✅ PASSED
Mainnet: ✅ PASSED

🎉 All networks are ready for Account Abstraction!
```

### Manual Verification Checklist

#### Testnet Verification
- [ ] Frontend uses testnet addresses when on localhost:4000
- [ ] Bundler connects to testnet RPC when ROGUE_ENV is not set
- [ ] Factory stake confirmed: 1.0 ROGUE
- [ ] Paymaster deposit confirmed: 9,998+ ROGUE
- [ ] AccountExtension registered with factory
- [ ] Bundler wallet has sufficient balance (10,000 ROGUE)

#### Mainnet Verification
- [ ] Frontend uses mainnet addresses when NOT on localhost:4000
- [ ] Bundler connects to mainnet RPC when ROGUE_ENV=mainnet
- [ ] Factory stake confirmed: 1.0 ROGUE
- [ ] Paymaster deposit confirmed: 1,000,000 ROGUE
- [ ] AccountExtension registered with factory
- [ ] Bundler wallet has sufficient balance (1,000,000 ROGUE)

---

## 📊 Resource Allocation

### Testnet Resources
| Resource | Amount | Purpose |
|----------|--------|---------|
| Factory Stake | 1.0 ROGUE | EntryPoint requirement |
| Paymaster Stake | 1.0 ROGUE | EntryPoint requirement |
| Paymaster Deposit | 9,998.12 ROGUE | Gas sponsorship |
| Bundler Balance | 10,000 ROGUE | Transaction submission |
| **Total Allocated** | **20,000+ ROGUE** | Testing & Development |

### Mainnet Resources
| Resource | Amount | Purpose |
|----------|--------|---------|
| Factory Stake | 1.0 ROGUE | EntryPoint requirement |
| Paymaster Stake | 1.0 ROGUE | EntryPoint requirement |
| Paymaster Deposit | 1,000,000 ROGUE | Gas sponsorship (production) |
| Bundler Balance | 1,000,000 ROGUE | Transaction submission |
| **Total Allocated** | **2,000,002 ROGUE** | Production Operations |

---

## 🔐 Security Considerations

### Environment Separation
- ✅ **Testnet** and **Mainnet** use completely separate contracts
- ✅ **Different factory addresses** prevent cross-network confusion
- ✅ **Different paymaster addresses** ensure proper accounting
- ✅ **Environment detection** is automatic and reliable

### Private Keys
- 🔒 **BUILDER_PRIVATE_KEY**: Required for bundler operation
  - Testnet: Same key can be used (low value)
  - Mainnet: **Use a dedicated, secure key** (high value)
- 🔒 **Deployer Key**: Has admin rights on factories
  - Keep secure - required for extension management

### Access Control
- Factory admin: Can add/remove extensions
- Paymaster owner: Can withdraw deposits
- Bundler wallet: Only needs transaction submission rights

---

## 📈 Monitoring & Maintenance

### What to Monitor

#### Paymaster Deposit Balance
```bash
# Check deposit balance (using verification script)
node scripts/verify-aa-deployment.js
```

**Alert when**:
- Testnet: < 1,000 ROGUE
- Mainnet: < 100,000 ROGUE

#### Bundler Wallet Balance
```bash
# Check bundler balance (using verification script)
node scripts/verify-aa-deployment.js
```

**Alert when**:
- Testnet: < 1,000 ROGUE
- Mainnet: < 100,000 ROGUE

#### Factory & Paymaster Stakes
- Both require 1.0 ROGUE minimum stake
- Monitor `depositInfo` on EntryPoint
- Alert if `staked == false`

### Maintenance Tasks

#### Top Up Paymaster Deposit
```solidity
// Call EntryPoint.depositTo(paymasterAddress)
// Send ROGUE with transaction
```

#### Top Up Bundler Wallet
```bash
# Send ROGUE to bundler wallet address
# 0xd75A64aDf49E180e6f4B1f1723ed4bdA16AFA06f
```

#### Update Extensions (if needed)
```solidity
// Deploy new extension
// Call factory.addExtension(extension, metadata)
```

---

## 🧪 Testing Procedures

### Frontend Testing

#### Test Testnet (Localhost)
1. Run Phoenix server: `mix phx.server`
2. Open browser: `http://localhost:4000`
3. Check console logs for configuration
4. Should show: **Chain ID: 71499284269**
5. Factory: `0x39CeCF786830d1E073e737870E2A6e66fE92FDE9`

#### Test Mainnet (Production)
1. Deploy to production server
2. Open browser: `https://your-production-url.com`
3. Check console logs for configuration
4. Should show: **Chain ID: 560013**
5. Factory: `0xfbbe1193496752e99BA6Ad74cdd641C33b48E0C3`

### Bundler Testing

#### Test Bundler Locally (Testnet)
```bash
cd bundler
docker build -t rogue-bundler:test .
docker run -p 3000:3000 \
  -e BUILDER_PRIVATE_KEY="0x..." \
  rogue-bundler:test

# Check logs for:
# "=== TESTNET CONFIGURATION ==="
# "Node RPC: https://testnet-rpc.roguechain.io"
```

#### Test Bundler Locally (Mainnet)
```bash
docker run -p 3000:3000 \
  -e BUILDER_PRIVATE_KEY="0x..." \
  -e ROGUE_ENV=mainnet \
  rogue-bundler:test

# Check logs for:
# "=== MAINNET CONFIGURATION ==="
# "Node RPC: https://rpc.roguechain.io/rpc"
```

#### Test End-to-End Transaction
1. Log in with email on frontend
2. Click "Test Paymaster" button (if available)
3. Check console for UserOperation flow
4. Verify transaction on block explorer
5. Confirm gas was sponsored by paymaster

---

## 🐛 Troubleshooting

### Problem: Wrong network detected on frontend

**Solution**:
```javascript
// Check window.location.origin in browser console
console.log(window.location.origin);

// Expected:
// Localhost: "http://localhost:4000" → Testnet
// Production: "https://your-domain.com" → Mainnet
```

### Problem: Bundler using wrong RPC

**Solution**:
```bash
# Check Fly.io environment variable
flyctl secrets list

# If ROGUE_ENV is not set → Testnet
# If ROGUE_ENV=mainnet → Mainnet

# Set it explicitly:
flyctl secrets set ROGUE_ENV=mainnet  # or unset for testnet
```

### Problem: AA14 error (initCode must return sender)

**Cause**: Factory address mismatch between frontend and bundler

**Solution**:
1. Verify factory address in `home_hooks.js` matches network
2. Verify bundler chain spec has correct chain ID
3. Clear browser cache and localStorage
4. Redeploy bundler with correct chain spec

### Problem: AA23 error (Invalid paymaster signature)

**Cause**: Bundler not running with `--unsafe` flag

**Solution**:
- Bundler `entrypoint.sh` already includes `--unsafe`
- Verify Rundler v0.9.2 is being used
- Check Fly.io logs: `flyctl logs`

### Problem: "Router: function does not exist"

**Cause**: AccountExtension not registered with factory

**Solution**:
```bash
# Verify extension registration
node scripts/verify-aa-deployment.js

# Should show: "✅ Extension registered with factory"
# If not, re-run addExtension transaction
```

---

## 📚 Related Documentation

- [ERC4337_MAINNET_CONTRACTS.md](./ERC4337_MAINNET_CONTRACTS.md) - Mainnet deployment details
- [ACCOUNT_ABSTRACTION_SETUP.md](./ACCOUNT_ABSTRACTION_SETUP.md) - Complete AA setup guide
- [ERC4337_DEPLOYMENT_GUIDE.md](./ERC4337_DEPLOYMENT_GUIDE.md) - Deployment procedures
- [Official ERC-4337 Spec](https://eips.ethereum.org/EIPS/eip-4337)
- [Thirdweb Smart Wallets](https://portal.thirdweb.com/contracts/smart-wallets)
- [Rundler Documentation](https://github.com/alchemyplatform/rundler)

---

## 🎯 Next Steps

### Before Fly.io Deployment

- [ ] Confirm bundler environment variable is set correctly
  ```bash
  # For mainnet deployment:
  flyctl secrets set ROGUE_ENV=mainnet

  # For testnet deployment:
  flyctl secrets unset ROGUE_ENV
  ```

- [ ] Verify `BUILDER_PRIVATE_KEY` is set on Fly.io
  ```bash
  flyctl secrets list | grep BUILDER_PRIVATE_KEY
  ```

- [ ] Review Fly.io app configuration
  ```bash
  flyctl config show
  ```

### Deployment Commands

#### Deploy to Mainnet
```bash
# 1. Set mainnet environment
flyctl secrets set ROGUE_ENV=mainnet

# 2. Deploy
flyctl deploy

# 3. Check logs
flyctl logs

# 4. Verify it's using mainnet
# Logs should show: "=== MAINNET CONFIGURATION ==="
```

#### Deploy to Testnet
```bash
# 1. Remove mainnet environment variable
flyctl secrets unset ROGUE_ENV

# 2. Deploy
flyctl deploy

# 3. Check logs
flyctl logs

# 4. Verify it's using testnet
# Logs should show: "=== TESTNET CONFIGURATION ==="
```

### Post-Deployment Verification

1. Check Fly.io logs for correct network
   ```bash
   flyctl logs --app rogue-bundler
   ```

2. Test bundler endpoint
   ```bash
   curl https://rogue-bundler.fly.dev/health
   ```

3. Run verification script
   ```bash
   node scripts/verify-aa-deployment.js
   ```

4. Test a real transaction from the frontend

---

## ✨ Summary

### ✅ What's Been Configured

1. **Frontend** (`home_hooks.js`)
   - Automatic environment detection based on URL
   - Testnet contracts for localhost:4000
   - Mainnet contracts for production URLs

2. **Bundler Configuration** (`entrypoint.sh`)
   - Environment variable support (`ROGUE_ENV`)
   - Automatic RPC and chain spec selection
   - Defaults to testnet if not specified

3. **Chain Specifications**
   - Separate chain specs for testnet and mainnet
   - Both included in Docker image

4. **Verification Tools**
   - Automated verification script for both networks
   - Checks all contracts, stakes, deposits, and balances

### ✅ Verification Status

```
Testnet:  ✅ ALL CHECKS PASSED (10/10)
Mainnet:  ✅ ALL CHECKS PASSED (10/10)
```

### 🎉 Production Ready!

Both testnet and mainnet Account Abstraction infrastructure is **fully configured, verified, and ready for deployment**.

The system will automatically use the correct network based on:
- **Frontend**: URL detection (localhost = testnet, production = mainnet)
- **Bundler**: `ROGUE_ENV` environment variable (default = testnet)

---

**Configuration completed**: November 16, 2025
**Status**: ✅ **READY FOR FLY.IO DEPLOYMENT**
**Total networks**: 2 (Testnet + Mainnet)
**Total contracts deployed**: 8 (4 per network)
**Total ROGUE allocated**: 2,020,002 ROGUE

**🚀 Awaiting user confirmation to deploy to Fly.io**
