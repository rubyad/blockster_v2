# 🚀 Quick Deploy Reference - Dual Bundler Setup

**Two bundlers running 24/7 on Fly.io - one for mainnet, one for testnet**

---

## 📋 Architecture

**Two Separate Bundlers:**
- **Mainnet Bundler**: `rogue-bundler-mainnet.fly.dev` (for production)
- **Testnet Bundler**: `rogue-bundler-testnet.fly.dev` (for localhost)

**Frontend Auto-Detection:**
- Production URL → Uses mainnet bundler
- `localhost:4000` → Uses testnet bundler

---

## 🎯 Deploy Mainnet Bundler

```bash
cd /Users/tenmerry/Projects/blockster_v2/bundler

# First time only: Create app and set secrets
flyctl apps create rogue-bundler-mainnet
flyctl secrets set BUILDER_PRIVATE_KEY="your_key"

# Deploy
flyctl deploy

# Verify
flyctl logs --app rogue-bundler-mainnet | grep "MAINNET"
```

**Expected output:**
```
=== ROGUE MAINNET BUNDLER ===
Chain: Rogue Mainnet (560013)
Node RPC: https://rpc.roguechain.io/rpc
```

---

## 🧪 Deploy Testnet Bundler

```bash
cd /Users/tenmerry/Projects/blockster_v2/bundler-testnet

# First time only: Create app and set secrets
flyctl apps create rogue-bundler-testnet
flyctl secrets set BUILDER_PRIVATE_KEY="your_key"

# Deploy
flyctl deploy

# Verify
flyctl logs --app rogue-bundler-testnet | grep "TESTNET"
```

**Expected output:**
```
=== ROGUE TESTNET BUNDLER ===
Chain: Rogue Testnet (71499284269)
Node RPC: https://testnet-rpc.roguechain.io
```

---

## 🔍 Quick Verification

```bash
# Run automated verification (checks both networks)
node scripts/verify-aa-deployment.js

# Should show:
# Testnet: ✅ PASSED
# Mainnet: ✅ PASSED
```

---

## 📊 Network Configuration

### Testnet (localhost:4000)
```
Chain ID:   71499284269
Bundler:    https://rogue-bundler-testnet.fly.dev
Factory:    0x39CeCF786830d1E073e737870E2A6e66fE92FDE9
Paymaster:  0xd4ECb9C22e0c7495e167698cb8D0D9c84F65c02a
```

### Mainnet (production)
```
Chain ID:   560013
Bundler:    https://rogue-bundler-mainnet.fly.dev
Factory:    0xfbbe1193496752e99BA6Ad74cdd641C33b48E0C3
Paymaster:  0x804cA06a85083eF01C9aE94bAE771446c25269a6
```

---

## 🔧 Common Commands

```bash
# Check bundler status
flyctl status --app rogue-bundler-mainnet
flyctl status --app rogue-bundler-testnet

# View logs
flyctl logs --app rogue-bundler-mainnet
flyctl logs --app rogue-bundler-testnet

# Restart bundlers
flyctl apps restart rogue-bundler-mainnet
flyctl apps restart rogue-bundler-testnet

# Update bundlers
cd bundler && flyctl deploy
cd bundler-testnet && flyctl deploy
```

---

## ✅ Current Status

**As of November 16, 2025**:

- ✅ Dual bundler architecture configured
- ✅ Frontend auto-detects correct bundler
- ✅ Testnet: 9,998 ROGUE in paymaster
- ✅ Mainnet: 1,000,000 ROGUE in paymaster
- ✅ Both networks verified and ready

**🎉 READY TO DEPLOY BOTH BUNDLERS**

---

For detailed information, see [DUAL_BUNDLER_DEPLOYMENT.md](./DUAL_BUNDLER_DEPLOYMENT.md)
