# 🚀 Dual Bundler Deployment Guide

**Two separate bundlers running 24/7 on Fly.io**

---

## 📋 Overview

Your Account Abstraction infrastructure uses **two separate bundlers**:

1. **Mainnet Bundler** - For production (rogue-bundler-mainnet.fly.dev)
2. **Testnet Bundler** - For local development (rogue-bundler-testnet.fly.dev)

This allows you to:
- Work on localhost with testnet without any configuration changes
- Use production with mainnet automatically
- Keep both environments running 24/7

---

## 🌐 Bundler URLs

| Environment | Bundler URL | Chain ID | Used By |
|-------------|-------------|----------|---------|
| **Mainnet** | `https://rogue-bundler-mainnet.fly.dev` | 560013 | Production app |
| **Testnet** | `https://rogue-bundler-testnet.fly.dev` | 71499284269 | localhost:4000 |

### Frontend Configuration

The frontend automatically selects the correct bundler:

```javascript
// In home_hooks.js
if (window.location.origin != "http://localhost:4000") {
    bundlerUrl = "https://rogue-bundler-mainnet.fly.dev"  // Production
} else {
    bundlerUrl = "https://rogue-bundler-testnet.fly.dev"  // Development
}
```

---

## 📁 Directory Structure

```
blockster_v2/
├── bundler/                  # MAINNET bundler
│   ├── Dockerfile
│   ├── entrypoint.sh        # Hardcoded to mainnet
│   ├── chain-spec-mainnet.json
│   ├── Caddyfile
│   └── fly.toml             # app: rogue-bundler-mainnet
│
└── bundler-testnet/         # TESTNET bundler
    ├── Dockerfile
    ├── entrypoint.sh        # Hardcoded to testnet
    ├── chain-spec.json      # Testnet chain spec
    ├── Caddyfile
    └── fly.toml             # app: rogue-bundler-testnet
```

---

## 🚀 Deployment Instructions

### First Time Setup

#### 1. Create Mainnet Bundler App

```bash
cd /Users/tenmerry/Projects/blockster_v2/bundler

# Create the app
flyctl apps create rogue-bundler-mainnet

# Set the builder private key
flyctl secrets set BUILDER_PRIVATE_KEY="your_mainnet_private_key"

# Deploy
flyctl deploy
```

#### 2. Create Testnet Bundler App

```bash
cd /Users/tenmerry/Projects/blockster_v2/bundler-testnet

# Create the app
flyctl apps create rogue-bundler-testnet

# Set the builder private key (can be same or different)
flyctl secrets set BUILDER_PRIVATE_KEY="your_testnet_private_key"

# Deploy
flyctl deploy
```

### Updating Deployments

#### Update Mainnet Bundler

```bash
cd /Users/tenmerry/Projects/blockster_v2/bundler
flyctl deploy
```

#### Update Testnet Bundler

```bash
cd /Users/tenmerry/Projects/blockster_v2/bundler-testnet
flyctl deploy
```

---

## ✅ Verification

### Check Both Bundlers Are Running

```bash
# Check mainnet bundler
flyctl status --app rogue-bundler-mainnet

# Check testnet bundler
flyctl status --app rogue-bundler-testnet
```

### View Logs

```bash
# Mainnet bundler logs
flyctl logs --app rogue-bundler-mainnet

# Testnet bundler logs
flyctl logs --app rogue-bundler-testnet
```

### Expected Log Output

**Mainnet Bundler:**
```
=== ROGUE MAINNET BUNDLER ===
Chain: Rogue Mainnet (560013)
Node RPC: https://rpc.roguechain.io/rpc
Chain Spec: /app/chain-spec-mainnet.json
```

**Testnet Bundler:**
```
=== ROGUE TESTNET BUNDLER ===
Chain: Rogue Testnet (71499284269)
Node RPC: https://testnet-rpc.roguechain.io
Chain Spec: /app/chain-spec.json
```

### Test Bundler Endpoints

```bash
# Test mainnet bundler (should work)
curl https://rogue-bundler-mainnet.fly.dev/health

# Test testnet bundler (should work)
curl https://rogue-bundler-testnet.fly.dev/health
```

---

## 🔍 Contract Verification

Run the verification script to ensure both networks are ready:

```bash
node scripts/verify-aa-deployment.js
```

**Expected output:**
```
Testnet: ✅ PASSED
Mainnet: ✅ PASSED

🎉 All networks are ready for Account Abstraction!
```

---

## 🧪 Testing

### Test Mainnet (Production)

1. Deploy your app to production
2. Open production URL in browser
3. Open browser console
4. Look for: `Bundler: https://rogue-bundler-mainnet.fly.dev`
5. Try logging in and creating a smart wallet
6. Transaction should appear on https://roguescan.io

### Test Testnet (Localhost)

1. Run Phoenix server: `mix phx.server`
2. Open `http://localhost:4000` in browser
3. Open browser console
4. Look for: `Bundler: https://rogue-bundler-testnet.fly.dev`
5. Try logging in and creating a smart wallet
6. Transaction should appear on https://testnet-explorer.roguechain.io

---

## 💰 Resource Management

### Mainnet Resources

| Resource | Amount | Purpose |
|----------|--------|---------|
| Factory Stake | 1.0 ROGUE | EntryPoint requirement |
| Paymaster Stake | 1.0 ROGUE | EntryPoint requirement |
| Paymaster Deposit | 1,000,000 ROGUE | Gas sponsorship |
| Bundler Balance | 1,000,000 ROGUE | Transaction submission |

**Monitor mainnet paymaster deposit** - this will decrease as users create wallets and transactions.

### Testnet Resources

| Resource | Amount | Purpose |
|----------|--------|---------|
| Factory Stake | 1.0 ROGUE | EntryPoint requirement |
| Paymaster Stake | 1.0 ROGUE | EntryPoint requirement |
| Paymaster Deposit | 9,998 ROGUE | Gas sponsorship |
| Bundler Balance | 10,000 ROGUE | Transaction submission |

---

## 🔧 Maintenance

### Monitoring Checklist

- [ ] Check mainnet bundler is running: `flyctl status --app rogue-bundler-mainnet`
- [ ] Check testnet bundler is running: `flyctl status --app rogue-bundler-testnet`
- [ ] Monitor mainnet paymaster deposit (alert if < 100,000 ROGUE)
- [ ] Monitor testnet paymaster deposit (alert if < 1,000 ROGUE)
- [ ] Check bundler wallet balances
- [ ] Review logs for errors

### Common Maintenance Tasks

#### Top Up Mainnet Paymaster

```bash
# Send ROGUE to paymaster deposit on mainnet
# Use EntryPoint.depositTo(0x804cA06a85083eF01C9aE94bAE771446c25269a6)
```

#### Top Up Testnet Paymaster

```bash
# Send ROGUE to paymaster deposit on testnet
# Use EntryPoint.depositTo(0xd4ECb9C22e0c7495e167698cb8D0D9c84F65c02a)
```

#### Restart Bundler

```bash
# Restart mainnet bundler
flyctl apps restart rogue-bundler-mainnet

# Restart testnet bundler
flyctl apps restart rogue-bundler-testnet
```

---

## 🐛 Troubleshooting

### Problem: Frontend using wrong bundler

**Check:**
```javascript
// In browser console on your app
console.log(window.location.origin);
```

- If `http://localhost:4000` → Should use testnet bundler
- If production URL → Should use mainnet bundler

**Solution:** Check `home_hooks.js` line 25-44 for bundler URL configuration

### Problem: Bundler not responding

**Check:**
```bash
# Check if app is running
flyctl status --app rogue-bundler-mainnet

# Check logs
flyctl logs --app rogue-bundler-mainnet
```

**Solution:** Restart the bundler
```bash
flyctl apps restart rogue-bundler-mainnet
```

### Problem: Wrong network in bundler logs

**Mainnet bundler should show:**
- Chain: Rogue Mainnet (560013)
- Node RPC: https://rpc.roguechain.io/rpc

**Testnet bundler should show:**
- Chain: Rogue Testnet (71499284269)
- Node RPC: https://testnet-rpc.roguechain.io

**Solution:** Redeploy the correct bundler from the correct directory

### Problem: AA14 error (address mismatch)

**Cause:** Bundler on wrong network for the factory being used

**Check:**
- Localhost → Should use testnet bundler + testnet factory
- Production → Should use mainnet bundler + mainnet factory

**Solution:** Verify frontend is using correct bundler URL for the environment

---

## 📊 Fly.io App Details

### Mainnet Bundler

```
App Name:     rogue-bundler-mainnet
URL:          https://rogue-bundler-mainnet.fly.dev
Region:       ord (Chicago)
VM:           shared-cpu-2x, 2GB RAM
Auto-stop:    disabled (always running)
```

### Testnet Bundler

```
App Name:     rogue-bundler-testnet
URL:          https://rogue-bundler-testnet.fly.dev
Region:       ord (Chicago)
VM:           shared-cpu-2x, 2GB RAM
Auto-stop:    disabled (always running)
```

---

## 🔐 Security

### Private Keys

- **Mainnet bundler** (`BUILDER_PRIVATE_KEY`): Should have high-value ROGUE
  - Set via: `flyctl secrets set BUILDER_PRIVATE_KEY="..." --app rogue-bundler-mainnet`

- **Testnet bundler** (`BUILDER_PRIVATE_KEY`): Can use same or different key
  - Set via: `flyctl secrets set BUILDER_PRIVATE_KEY="..." --app rogue-bundler-testnet`

### Viewing Secrets

```bash
# List secrets (won't show values)
flyctl secrets list --app rogue-bundler-mainnet
flyctl secrets list --app rogue-bundler-testnet
```

---

## 📚 Related Documentation

- [MAINNET_AA_CONFIGURATION.md](./MAINNET_AA_CONFIGURATION.md) - Complete mainnet configuration
- [ERC4337_MAINNET_CONTRACTS.md](./ERC4337_MAINNET_CONTRACTS.md) - Mainnet contract addresses
- [ACCOUNT_ABSTRACTION_SETUP.md](./ACCOUNT_ABSTRACTION_SETUP.md) - Original AA setup guide

---

## ✨ Summary

### ✅ Current Setup

- ✅ **Two separate Fly.io apps** for mainnet and testnet
- ✅ **Frontend auto-detects** which bundler to use
- ✅ **Always-on** - both bundlers run 24/7
- ✅ **Zero configuration** needed when switching between localhost and production

### 🎯 Quick Commands

```bash
# Deploy mainnet bundler
cd bundler && flyctl deploy

# Deploy testnet bundler
cd bundler-testnet && flyctl deploy

# Check status
flyctl status --app rogue-bundler-mainnet
flyctl status --app rogue-bundler-testnet

# View logs
flyctl logs --app rogue-bundler-mainnet
flyctl logs --app rogue-bundler-testnet

# Verify all contracts
node scripts/verify-aa-deployment.js
```

---

**Status**: ✅ **READY FOR DEPLOYMENT**

**Created**: November 16, 2025
