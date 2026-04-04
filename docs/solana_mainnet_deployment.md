# Solana Mainnet Deployment Guide

Complete step-by-step instructions to deploy Blockster V2 on Solana mainnet.

**Prerequisites**: All code changes are on `feat/solana-migration` branch and tested on devnet.

---

## Table of Contents

1. [Overview](#overview)
2. [Cost Summary](#cost-summary)
3. [Step 1: Prepare Wallets](#step-1-prepare-wallets)
4. [Step 2: Create BUX Token on Mainnet](#step-2-create-bux-token-on-mainnet)
5. [Step 3: Deploy Programs to Mainnet](#step-3-deploy-programs-to-mainnet)
6. [Step 4: Initialize Programs](#step-4-initialize-programs)
7. [Step 5: Deploy Settler Service](#step-5-deploy-settler-service)
8. [Step 6: Configure Main App Secrets](#step-6-configure-main-app-secrets)
9. [Step 7: Deploy Main App](#step-7-deploy-main-app)
10. [Step 8: Post-Deploy Verification](#step-8-post-deploy-verification)
11. [Step 9: Shut Down Legacy Services](#step-9-shut-down-legacy-services)
12. [Ongoing Operations](#ongoing-operations)
13. [Rollback Plan](#rollback-plan)

---

## Overview

### Architecture

```
Users (Phantom/Solflare)
    │
    ├── Wallet signing (bets, deposits, claims)
    │
    ▼
Blockster App (blockster-v2, Fly.io)
    │
    ├── BUX minting, bet settlement, airdrop ops
    │
    ▼
Blockster Settler (blockster-settler, Fly.io)
    │
    ├── Signs with authority keypair
    │
    ▼
Solana Mainnet
    ├── BUX SPL Token (mint)
    ├── Bankroll Program (bets, LP, referrals)
    └── Airdrop Program (rounds, prizes, claims)
```

### Wallets

| Wallet | Purpose | Needs SOL? |
|--------|---------|------------|
| CLI Wallet (`49aN...`) | Pays program deploy fees (one-time) | ~5 SOL one-time |
| Authority (`6b4n...`) | Program authority, BUX minting, settler signing | ~1 SOL/month ongoing |

### Programs & Token

| Resource | Devnet Address | Mainnet Address |
|----------|---------------|-----------------|
| BUX Mint | `7CuRyw2YkqQhUUFbw6CCnoedHWT8tK2c9UzZQYDGmxVX` | TBD (new keypair or same) |
| Bankroll Program | `49up2uzZANpjTC3sgggbZazdHBii2vY9mVK3vk5dT2tm` | Same (keypair-derived) |
| Airdrop Program | `wxiuLBuqxem5ETmGDndiW8MMkxKXp5jVsNCqdZgmjaG` | Same (keypair-derived) |

---

## Cost Summary

### One-Time Costs (SOL)

| Item | Cost | Paid By |
|------|------|---------|
| Deploy Bankroll program (665KB) | ~2.3 SOL | CLI wallet (`49aN...`) |
| Deploy Airdrop program (356KB) | ~1.2 SOL | CLI wallet (`49aN...`) |
| Create BUX token | ~0.01 SOL | Authority (`6b4n...`) |
| Initialize Bankroll (6 PDAs) | ~0.1 SOL | Authority (`6b4n...`) |
| Initialize Airdrop (1 PDA) | ~0.01 SOL | Authority (`6b4n...`) |
| Seed initial liquidity | Variable | Authority (`6b4n...`) |
| **Total one-time** | **~5 SOL** | |

### Ongoing Costs (Monthly)

| Item | Formula | At 1000 mints/day | At 5000 mints/day |
|------|---------|-------------------|-------------------|
| Mint tx fees | 0.000005 SOL each | 0.15 SOL | 0.75 SOL |
| New user ATA creation | 0.002 SOL each | ~3 SOL (50 new/day) | ~6 SOL (100 new/day) |
| Airdrop admin txs | ~0.001 SOL/round | ~0.03 SOL | ~0.03 SOL |
| **Total monthly** | | **~3.2 SOL** | **~6.8 SOL** |

### Fly.io Costs

| Service | Machine | Est. Cost |
|---------|---------|-----------|
| blockster-settler | shared-cpu-1x, 256MB | ~$0-3/month (free tier eligible) |

---

## Step 1: Prepare Wallets

### Fund CLI Wallet

Send **5 SOL** (real SOL) to the CLI deploy wallet:

```
49aNHDAduVnEcEEqCyEXMS1rT62UnW5TajA2fVtNpC1d
```

Verify:
```bash
solana balance 49aNHDAduVnEcEEqCyEXMS1rT62UnW5TajA2fVtNpC1d --url mainnet-beta
```

### Fund Authority Wallet

Send **1 SOL** (real SOL) to the authority wallet for initialization + first month of minting:

```
6b4nMSTWJ1yxZZVmqokf6QrVoF9euvBSdB11fC3qfuv1
```

Verify:
```bash
solana balance 6b4nMSTWJ1yxZZVmqokf6QrVoF9euvBSdB11fC3qfuv1 --url mainnet-beta
```

### Set Solana CLI to Mainnet

```bash
solana config set --url https://api.mainnet-beta.solana.com
```

Or use your QuickNode mainnet RPC:
```bash
solana config set --url https://YOUR_QUICKNODE_MAINNET_URL
```

---

## Step 2: Create BUX Token on Mainnet

**Option A**: Reuse the same mint keypair (same address as devnet):
```bash
cd contracts/blockster-settler
npx ts-node scripts/create-bux-token.ts
```

This creates the BUX SPL token on mainnet with:
- Mint address: derived from `keypairs/bux-mint.json`
- Mint authority: `6b4nMSTWJ1yxZZVmqokf6QrVoF9euvBSdB11fC3qfuv1`
- Decimals: 9
- Freeze authority: disabled

**Option B**: Create a new mint keypair for mainnet (different address):
```bash
solana-keygen new -o keypairs/bux-mint-mainnet.json
# Update create-bux-token.ts to use the new keypair
```

**IMPORTANT**: Record the mainnet BUX mint address. You'll need it for all subsequent steps.

**Environment variable needed**: `SOLANA_RPC_URL` must point to mainnet before running.

```bash
SOLANA_RPC_URL=https://YOUR_QUICKNODE_MAINNET_URL npx ts-node scripts/create-bux-token.ts
```

---

## Step 3: Deploy Programs to Mainnet

### Set QuickNode Mainnet RPC

All deploy commands use `--url`. Use your QuickNode mainnet endpoint (NOT the public `api.mainnet-beta.solana.com` — it rate-limits deploys).

```
MAINNET_RPC=https://YOUR_QUICKNODE_MAINNET_URL
```

### Deploy Bankroll Program

```bash
cd contracts/blockster-bankroll
solana program deploy \
  --url $MAINNET_RPC \
  --keypair ~/.config/solana/id.json \
  --upgrade-authority ../blockster-settler/keypairs/mint-authority.json \
  --program-id target/deploy/blockster_bankroll-keypair.json \
  target/deploy/blockster_bankroll.so
```

Expected output:
```
Program Id: 49up2uzZANpjTC3sgggbZazdHBii2vY9mVK3vk5dT2tm
```

Cost: ~2.3 SOL from CLI wallet.

### Deploy Airdrop Program

```bash
cd contracts/blockster-airdrop
solana program deploy \
  --url $MAINNET_RPC \
  --keypair ~/.config/solana/id.json \
  --upgrade-authority ../blockster-settler/keypairs/mint-authority.json \
  --program-id target/deploy/blockster_airdrop-keypair.json \
  target/deploy/blockster_airdrop.so
```

Expected output:
```
Program Id: wxiuLBuqxem5ETmGDndiW8MMkxKXp5jVsNCqdZgmjaG
```

Cost: ~1.2 SOL from CLI wallet.

### Verify Both Programs

```bash
solana program show 49up2uzZANpjTC3sgggbZazdHBii2vY9mVK3vk5dT2tm --url $MAINNET_RPC
solana program show wxiuLBuqxem5ETmGDndiW8MMkxKXp5jVsNCqdZgmjaG --url $MAINNET_RPC
```

Both should show `Authority: 6b4nMSTWJ1yxZZVmqokf6QrVoF9euvBSdB11fC3qfuv1`.

---

## Step 4: Initialize Programs

### Initialize Bankroll

```bash
cd contracts/blockster-settler
SOLANA_RPC_URL=$MAINNET_RPC npx ts-node scripts/init-bankroll.ts
```

This runs 4 steps + game registration:
1. initializeRegistry — creates GameRegistry, SolVaultState, BuxVaultState
2. initializeSolPool — creates bSOL LP mint
3. initializeBuxPool — creates bBUX LP mint
4. initializeBuxVault — creates BUX token vault
5. registerGame — registers Coin Flip (game_id=1)

**DO NOT use `--seed-liquidity`** — it deposits SOL directly into the vault without issuing LP tokens, which distorts the LP price. Instead, after initialization, manually deposit SOL via the Pool page UI so you receive bSOL LP tokens at the correct 1:1 initial price.

### Initialize Airdrop

```bash
SOLANA_RPC_URL=$MAINNET_RPC npx ts-node scripts/init-airdrop.ts
```

Creates the AirdropState PDA.

### Verify Initialization

```bash
cd contracts/blockster-settler
SOLANA_RPC_URL=$MAINNET_RPC npx ts-node -e "
const { getPoolStats } = require('./src/services/bankroll-service');
const { getAirdropState } = require('./src/services/airdrop-service');
getPoolStats().then(s => console.log('Pool Stats:', JSON.stringify(s, null, 2)));
getAirdropState().then(s => console.log('Airdrop State:', JSON.stringify(s, null, 2)));
"
```

---

## Step 5: Deploy Settler Service

### Build TypeScript

```bash
cd contracts/blockster-settler
npm run build
```

This compiles TypeScript to `dist/`.

### Create Fly.io App

```bash
cd contracts/blockster-settler
flyctl launch --name blockster-settler --region iad --no-deploy
```

If prompted, use the existing `Dockerfile`.

### Generate a Strong API Secret

```bash
openssl rand -hex 32
```

Save this — you'll use it for both the settler and the main app.

### Set Settler Secrets

**IMPORTANT**: Always use `--stage` to avoid immediate restart.

```bash
flyctl secrets set \
  SOLANA_RPC_URL="https://YOUR_QUICKNODE_MAINNET_URL" \
  SOLANA_NETWORK="mainnet-beta" \
  SETTLER_API_SECRET="YOUR_GENERATED_SECRET" \
  BUX_MINT_ADDRESS="MAINNET_BUX_MINT_ADDRESS" \
  BANKROLL_PROGRAM_ID="49up2uzZANpjTC3sgggbZazdHBii2vY9mVK3vk5dT2tm" \
  AIRDROP_PROGRAM_ID="wxiuLBuqxem5ETmGDndiW8MMkxKXp5jVsNCqdZgmjaG" \
  MINT_AUTHORITY_KEYPAIR='[PASTE_FULL_KEYPAIR_JSON_ARRAY]' \
  --stage --app blockster-settler
```

**To get the keypair JSON array** (DO NOT share this — it's a private key):
```bash
cat contracts/blockster-settler/keypairs/mint-authority.json
```

### Deploy Settler

```bash
flyctl deploy --app blockster-settler
```

### Verify Settler Health

```bash
curl https://blockster-settler.fly.dev/health
```

Expected:
```json
{
  "status": "ok",
  "network": "mainnet-beta",
  "buxMint": "MAINNET_BUX_MINT_ADDRESS",
  "mintAuthority": "6b4nMSTWJ1yxZZVmqokf6QrVoF9euvBSdB11fC3qfuv1"
}
```

---

## Step 6: Configure Main App Secrets

**IMPORTANT**: Always use `--stage`. These take effect on next deploy.

```bash
flyctl secrets set \
  BLOCKSTER_SETTLER_URL="https://blockster-settler.fly.dev" \
  BLOCKSTER_SETTLER_SECRET="YOUR_GENERATED_SECRET" \
  SOLANA_RPC_URL="https://YOUR_QUICKNODE_MAINNET_URL" \
  SOLANA_AUTHORITY_ADDRESS="6b4nMSTWJ1yxZZVmqokf6QrVoF9euvBSdB11fC3qfuv1" \
  --stage --app blockster-v2
```

The `BLOCKSTER_SETTLER_SECRET` must match the `SETTLER_API_SECRET` set on the settler.

### Secrets Reference

| Secret | Set On | Value |
|--------|--------|-------|
| `SOLANA_RPC_URL` | settler + main app | QuickNode mainnet RPC URL |
| `SOLANA_NETWORK` | settler | `mainnet-beta` |
| `SETTLER_API_SECRET` | settler | Random 64-char hex (shared secret) |
| `BLOCKSTER_SETTLER_URL` | main app | `https://blockster-settler.fly.dev` |
| `BLOCKSTER_SETTLER_SECRET` | main app | Same as `SETTLER_API_SECRET` |
| `SOLANA_AUTHORITY_ADDRESS` | main app | `6b4nMSTWJ1yxZZVmqokf6QrVoF9euvBSdB11fC3qfuv1` |
| `MINT_AUTHORITY_KEYPAIR` | settler | Full JSON array from `keypairs/mint-authority.json` |
| `BUX_MINT_ADDRESS` | settler | Mainnet BUX mint address |
| `BANKROLL_PROGRAM_ID` | settler | `49up2uzZANpjTC3sgggbZazdHBii2vY9mVK3vk5dT2tm` |
| `AIRDROP_PROGRAM_ID` | settler | `wxiuLBuqxem5ETmGDndiW8MMkxKXp5jVsNCqdZgmjaG` |

---

## Step 7: Deploy Main App

### Merge and Deploy

```bash
# From project root
git checkout feat/solana-migration
git push origin feat/solana-migration

# Deploy
flyctl deploy --app blockster-v2
```

### Run Migrations

Migrations run automatically on deploy. If needed manually:
```bash
flyctl ssh console --app blockster-v2 -C "bin/blockster_v2 rpc 'BlocksterV2.Release.migrate()'"
```

---

## Step 8: Post-Deploy Verification

### Health Checks

```bash
# Settler health
curl https://blockster-settler.fly.dev/health

# Main app health
curl https://blockster.com
```

### Functional Tests

1. **Wallet Connect**: Open blockster.com in a browser with Phantom → connect wallet → verify user created
2. **BUX Minting**: Read an article → verify BUX balance increases (check admin stats page)
3. **Authority Balance**: Go to `/admin/stats` → verify authority wallet SOL balance shows
4. **Coin Flip**: Go to `/play` → place a SOL bet → verify game works
5. **Pool**: Go to `/pool` → deposit SOL → verify LP tokens received
6. **Airdrop**: Go to `/airdrop` → verify page loads (round must be started first)

### Start First Airdrop Round (optional)

From the Elixir console:
```bash
flyctl ssh console --app blockster-v2 -C "bin/blockster_v2 rpc '
end_time = DateTime.add(DateTime.utc_now(), 7, :day)
BlocksterV2.Airdrop.create_round(end_time)
|> IO.inspect()
'"
```

---

## Step 9: Shut Down Legacy Services

**Only after confirming mainnet is stable (wait at least 24-48 hours).**

### Stop Old BUX Minter

```bash
flyctl scale count 0 --app bux-minter
```

### Stop Bundler

```bash
flyctl scale count 0 --app rogue-bundler-mainnet
```

### Remove Legacy Secrets from Main App (optional)

```bash
flyctl secrets unset BUX_MINTER_URL BUX_MINTER_SECRET --stage --app blockster-v2
```

---

## Ongoing Operations

### Monitor Authority Wallet

The `/admin/stats` page shows:
- Current SOL balance (green > 1 SOL, yellow 0.5-1, red < 0.5)
- Daily mint count and ATA creations
- Daily gas spend (tx fees + ATA rent)
- 7-day history

### Top Up Authority Wallet

When balance drops below 0.5 SOL, send more SOL to:
```
6b4nMSTWJ1yxZZVmqokf6QrVoF9euvBSdB11fC3qfuv1
```

Expected monthly spend at scale:
- 1,000 mints/day + 50 new users/day → ~3.2 SOL/month
- 5,000 mints/day + 100 new users/day → ~6.8 SOL/month

### Program Upgrades

Both programs have upgrade authority set to `6b4n...`. To upgrade:

```bash
# Build new .so
cd contracts/blockster-bankroll
anchor build

# Deploy upgrade
solana program deploy \
  --url $MAINNET_RPC \
  --keypair ../blockster-settler/keypairs/mint-authority.json \
  --program-id 49up2uzZANpjTC3sgggbZazdHBii2vY9mVK3vk5dT2tm \
  target/deploy/blockster_bankroll.so \
  --upgrade-authority ../blockster-settler/keypairs/mint-authority.json
```

### Updating Solscan Links

After mainnet deploy, remove `?cluster=devnet` from all Solscan links. Search and replace in:
- `lib/blockster_v2_web/live/airdrop_live.ex`
- `lib/blockster_v2_web/live/member_live/show.html.heex`
- `lib/blockster_v2_web/components/layouts.ex`

```bash
grep -r "cluster=devnet" lib/ --include="*.ex" --include="*.heex" -l
```

---

## Rollback Plan

If mainnet deploy fails:

1. **Revert main app**: `flyctl deploy --image registry.fly.io/blockster-v2:previous --app blockster-v2`
2. **Revert secrets**: `flyctl secrets unset BLOCKSTER_SETTLER_URL BLOCKSTER_SETTLER_SECRET SOLANA_RPC_URL --stage --app blockster-v2`
3. **Scale up legacy services**: `flyctl scale count 1 --app bux-minter` and `flyctl scale count 1 --app rogue-bundler-mainnet`
4. **Programs stay deployed** — they don't affect anything if the main app isn't calling them

The EVM code is preserved on the `evm-archive` branch. The Solana code paths only activate when `BLOCKSTER_SETTLER_URL` is set.

---

## Quick Reference: All Commands in Order

```bash
# 1. Fund wallets (send SOL from exchange/wallet)
#    49aNHDAduVnEcEEqCyEXMS1rT62UnW5TajA2fVtNpC1d — 5 SOL
#    6b4nMSTWJ1yxZZVmqokf6QrVoF9euvBSdB11fC3qfuv1 — 1 SOL

# 2. Set RPC
export MAINNET_RPC=https://YOUR_QUICKNODE_MAINNET_URL

# 3. Create BUX token
cd contracts/blockster-settler
SOLANA_RPC_URL=$MAINNET_RPC npx ts-node scripts/create-bux-token.ts

# 4. Deploy programs
cd ../blockster-bankroll
solana program deploy --url $MAINNET_RPC --keypair ~/.config/solana/id.json --upgrade-authority ../blockster-settler/keypairs/mint-authority.json --program-id target/deploy/blockster_bankroll-keypair.json target/deploy/blockster_bankroll.so

cd ../blockster-airdrop
solana program deploy --url $MAINNET_RPC --keypair ~/.config/solana/id.json --upgrade-authority ../blockster-settler/keypairs/mint-authority.json --program-id target/deploy/blockster_airdrop-keypair.json target/deploy/blockster_airdrop.so

# 5. Initialize programs
cd ../blockster-settler
# DO NOT use --seed-liquidity (distorts LP price). Deposit manually via Pool page UI after deploy.
SOLANA_RPC_URL=$MAINNET_RPC npx ts-node scripts/init-bankroll.ts
SOLANA_RPC_URL=$MAINNET_RPC npx ts-node scripts/init-airdrop.ts

# 6. Generate shared secret
export SHARED_SECRET=$(openssl rand -hex 32)
echo "Save this: $SHARED_SECRET"

# 7. Build and deploy settler
npm run build
flyctl launch --name blockster-settler --region iad --no-deploy
flyctl secrets set SOLANA_RPC_URL="$MAINNET_RPC" SOLANA_NETWORK="mainnet-beta" SETTLER_API_SECRET="$SHARED_SECRET" BUX_MINT_ADDRESS="MAINNET_MINT" BANKROLL_PROGRAM_ID="49up2uzZANpjTC3sgggbZazdHBii2vY9mVK3vk5dT2tm" AIRDROP_PROGRAM_ID="wxiuLBuqxem5ETmGDndiW8MMkxKXp5jVsNCqdZgmjaG" MINT_AUTHORITY_KEYPAIR="$(cat keypairs/mint-authority.json)" --stage --app blockster-settler
flyctl deploy --app blockster-settler

# 8. Configure and deploy main app
cd ../..
flyctl secrets set BLOCKSTER_SETTLER_URL="https://blockster-settler.fly.dev" BLOCKSTER_SETTLER_SECRET="$SHARED_SECRET" SOLANA_RPC_URL="$MAINNET_RPC" SOLANA_AUTHORITY_ADDRESS="6b4nMSTWJ1yxZZVmqokf6QrVoF9euvBSdB11fC3qfuv1" --stage --app blockster-v2
flyctl deploy --app blockster-v2

# 9. Verify
curl https://blockster-settler.fly.dev/health
curl https://blockster.com
```
