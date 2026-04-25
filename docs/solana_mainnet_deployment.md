# Solana Mainnet Deployment Guide

Complete step-by-step instructions to deploy Blockster V2 on Solana mainnet.

**Prerequisites**: All code changes are on `feat/solana-migration` branch and tested on devnet.

**Last substantive update**: 2026-04-25 — pre-deploy code prerequisites landed. See "Code prerequisites" block below for the full list. 2026-04-23 context: Phase 13 removed the `WEB3AUTH_SOL_CHECKOUT_ENABLED` gate. Web3Auth users now pay SOL-priced orders the same way Wallet Standard users do (`payment_mode="wallet_sign"`; `SolPaymentHook` via `signAndConfirm` handles both signer sources). Only `SOCIAL_LOGIN_ENABLED` remains as the master rollout switch. 2026-04-21 context still relevant: Phase 0–10 Web3Auth social login shipped (see `docs/solana_build_history.md` 2026-04-20 + 2026-04-21 entries). Email sign-in runs through an in-app OTP flow (NOT Web3Auth's `EMAIL_PASSWORDLESS` popup) that issues a JWT consumed by Web3Auth's `CUSTOM` connector — requires a second dashboard verifier named `blockster-email`. Email-ownership-is-account-ownership design: any sign-in where the email matches an existing user merges that account into the new Web3Auth-derived Solana wallet (legacy BUX minted to new wallet via settler). Onboarding simplified — single "Get started" CTA, `migrate_email` step retired. See [docs/social_login_plan.md](social_login_plan.md) Appendices D + E for the session narratives.

---

## Code prerequisites (landed 2026-04-25)

Before this runbook is safe to execute, the following code-level deploy blockers must be in place. All of these landed on `feat/solana-migration` ahead of mainnet:

- ✅ **`window.__SOLANA_RPC_URL` wired from server-side env** — `lib/blockster_v2_web/components/layouts/root.html.heex` injects `<script>window.__SOLANA_RPC_URL = "<%= System.get_env("SOLANA_RPC_URL") %>"</script>` so the 7 client-side hooks (coin flip, pool, sol payment, BUX burn, airdrop, web3auth withdraw, web3auth modal) consume the configured RPC instead of falling back to a hardcoded devnet URL. Without this, every Wallet Standard tx on mainnet would silently submit to devnet.
- ✅ **All 30 hardcoded `?cluster=devnet` Solscan links replaced** with calls to `BlocksterV2Web.Solscan.tx_url/1`, `account_url/1`, `token_url/1`, `home_url/0`. The helper branches on `WEB3AUTH_CHAIN_ID` — `0x65` returns mainnet URLs, anything else falls back to devnet. Non-legacy `lib/` is now devnet-free; the `legacy/` pre-redesign templates are intentionally left as-is.
- ✅ **Devnet defaults raise in `:prod`** — `wallet_auth_events.ex` `default_chain_id`/`default_network`/`default_rpc_url` raise loudly if their env var is empty in `:prod`, falling back to dev defaults only in `:dev`/`:test`. A missed `flyctl secrets set` surfaces immediately instead of silently routing mainnet traffic to devnet.
- ✅ **`SOCIAL_LOGIN_ENABLED` defaults to `false`** — both `web3auth_config/0` and `social_login_enabled?/0` use `"false"` as the safe default. Even if Step 6's `--stage` set is forgotten, the social-login UI stays hidden.
- ✅ **Settler `/burn` endpoint deleted** — `contracts/blockster-settler/src/routes/mint.ts` was a misleading TODO stub that never burned anything on-chain. Removed entirely; the actual burn flow is client-side via `assets/js/hooks/solana_bux_burn.js` (SPL `BurnChecked` from the buyer's ATA).
- ✅ **`contracts/blockster-settler/fly.toml` checked in** — replaces the auto-generated config from `flyctl launch`. Reviewable + reproducible across deploys.
- ✅ **Stale `app-21f441de633c332460d74811d210643d.js` artifact deleted** — 3.86 MB Feb-stale build that was still shipping in the Docker image. Removed from `priv/static/assets/js/`.

**Test-suite status (2026-04-25 endpoint)**: `mix test` clean-shell run (no concurrent `bin/dev`) reports `3365 tests, 172 failures, 211 skipped`. The audit's PR 2e baseline was `3307 / 69 / 211`. Delta from baseline: +58 tests (most from the 5cb2cc2 in-flight commit + new Solscan helper), +103 failures. The +103 are predominantly pre-existing stale-copy assertions catalogued in `docs/bug_audit_2026_04_22.md` Phase 3 Notes (cart_live "Pay with USD via Helio" footer, MemberLive.ShowTest fixture mismatches, OnboardingLiveTest copy drift, HeaderTest layout assertions). They were known + documented at audit time and aren't deploy-blocking — but per CLAUDE.md they DO need explicit user sign-off before `flyctl deploy`. Triage list:

```bash
# Top-failing test modules in clean run:
#  27 BlocksterV2Web.MemberLive.ShowTest        (stale fixtures — audit follow-up PR 3c)
#  16 BlocksterV2Web.ShopLive.IndexTest         (stale "$65.00" / footer copy — audit follow-up PR 3d)
#   9 BlocksterV2Web.OnboardingLiveTest         (post-redesign copy drift)
#   7 BlocksterV2Web.DesignSystem.HeaderTest    (header re-shape from c9bfd9a wallet-UX work)
#   5 BlocksterV2Web.HubLive.IndexTest          (audit-known stale)
#   5 BlocksterV2Web.CoinFlipLiveTest           (legacy assertions vs new mobile layout)
```

Re-verify with:

```bash
# 1. window.__SOLANA_RPC_URL wired
grep -n "__SOLANA_RPC_URL" lib/blockster_v2_web/components/layouts/root.html.heex
# 2. No hardcoded devnet (legacy templates excluded)
grep -rn "?cluster=devnet" lib/ | grep -v "/legacy/" | grep -v "solscan.ex"
# 3. Solscan helper present
test -f lib/blockster_v2_web/solscan.ex && echo "ok"
# 4. /burn endpoint gone
grep -n 'router.post."/burn"' contracts/blockster-settler/src/routes/mint.ts
# 5. Settler fly.toml present
test -f contracts/blockster-settler/fly.toml && echo "ok"
```

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
    ├── Derives shop payment-intent keypairs (HKDF, stateless)
    │
    ▼
Solana Mainnet
    ├── BUX SPL Token (mint)
    ├── Bankroll Program (bets, LP, referrals)
    ├── Airdrop Program (rounds, prizes, claims)
    └── Shop payment intents (ephemeral pubkeys — direct SOL transfers)
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
| Bot wallet rotation ATAs (1000 bots × 0.002 SOL) | ~2 SOL | Authority (`6b4n...`) |
| **Total one-time** | **~7 SOL** | |

> **Bot ATA surge**: On the first main-app boot after deploy, `BotCoordinator` automatically rotates the 1000 read-to-earn bot wallets from EVM (`0x...`) to fresh Solana ed25519 keypairs. The first mint to each rotated bot creates an Associated Token Account, costing ~0.002 SOL each. This is a **one-time** cost — every subsequent boot is a no-op. See [Step 7](#step-7-deploy-main-app) for details. Make sure the authority has at least 3 SOL of headroom on top of init costs before deploying the main app, otherwise some bot mints will fail until you top up.

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

Send **4 SOL** (real SOL) to the authority wallet. Breakdown:
- ~0.1 SOL for program initialization (Bankroll + Airdrop PDAs, BUX mint)
- ~2 SOL for the one-time bot wallet rotation ATA surge (see [Step 7](#step-7-deploy-main-app))
- ~1 SOL of headroom for the first month of minting
- **~1 SOL rent float for bet_order PDAs** (new in Phase 1 — settler is the on-chain `rent_payer` for every SOL and BUX bet; each bet_order PDA costs ~0.00139 SOL at placement and returns to the settler on settle/reclaim. The float is cycled, not spent, but the wallet needs this balance for concurrent in-flight bets).

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

**Decision (2026-04-25)**: Reuse the same `keypairs/mint-authority.json` and `keypairs/bux-mint.json` as devnet. The same `6b4n...` authority and `7CuRyw2YkqQhUUFbw6CCnoedHWT8tK2c9UzZQYDGmxVX` mint address show up on mainnet — operators see one address everywhere, the bot rotation has already cached the authority pubkey, and `docs/addresses.md` doesn't need a per-network split.

```bash
cd contracts/blockster-settler
SOLANA_RPC_URL=https://YOUR_QUICKNODE_MAINNET_URL npx ts-node scripts/create-bux-token.ts
```

This creates the BUX SPL token on mainnet with:
- Mint address: `7CuRyw2YkqQhUUFbw6CCnoedHWT8tK2c9UzZQYDGmxVX` (derived from `keypairs/bux-mint.json`)
- Mint authority: `6b4nMSTWJ1yxZZVmqokf6QrVoF9euvBSdB11fC3qfuv1` (derived from `keypairs/mint-authority.json`)
- Decimals: 9
- Freeze authority: disabled

The same address on mainnet will be a fresh, empty token — no carryover BUX balances. Bot wallets that rotated on devnet keep their Solana pubkeys; their on-chain BUX balance starts at 0 on mainnet and accrues from new mints.

**IMPORTANT**: Record the mainnet BUX mint address (it's the same `7CuRyw...` value but capture it explicitly). You'll need it for all subsequent steps.

**Alternative (NOT chosen)**: Generate a new mainnet-only mint keypair via `solana-keygen new -o keypairs/bux-mint-mainnet.json` and update `create-bux-token.ts` to read from it. Discarded — different addresses per network creates more places to typo than it saves.

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

### Bankroll program contract (Phase 1 behavior)

The deployed bankroll program enforces **settler as mandatory rent_payer** on `place_bet_sol` / `place_bet_bux`. Implication for operators:

- Every `place_bet_*` tx now has two signers: the player AND the settler keypair.
- The settler pays PDA rent (~0.00139 SOL) at placement; `settle_bet` and `reclaim_expired` close the PDA with `close = rent_payer`, returning rent to settler. Net flow at steady state = zero SOL cost to settler beyond priority fees.
- Users never need to hold SOL for rent. Phase 1 is the on-chain mechanism for the "zero SOL gameplay" UX guarantee.
- If you ever upgrade the program binary, the `rent_payer` field at `BetOrder` offset 115–146 must remain (repurposed from pre-upgrade `_reserved: [u8; 32]` — same serialized bytes). Do not remove.

This is non-negotiable — the program reverts any `place_bet_*` where `rent_payer.key() != game_registry.settler`. The settler tx-builder in `contracts/blockster-settler/src/services/bankroll-service.ts` partial-signs the tx with settler to satisfy this; never bypass that path.

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
  PAYMENT_INTENT_SEED="$(openssl rand -hex 32)" \
  SOL_TREASURY_ADDRESS="MAINNET_TREASURY_PUBKEY" \
  --stage --app blockster-settler
```

**To get the keypair JSON array** (DO NOT share this — it's a private key):
```bash
cat contracts/blockster-settler/keypairs/mint-authority.json
```

**Shop payment intents** (Phase 5b):

- `PAYMENT_INTENT_SEED` — 32+ bytes of random hex. The settler HKDF-derives a unique ephemeral Solana keypair per order from `(seed, order_id)`, so no per-order key material is ever stored. Rotating this seed **invalidates every unswept payment intent** — only rotate after confirming all outstanding intents have `status: swept`.
- `SOL_TREASURY_ADDRESS` — Solana pubkey that receives swept SOL from funded checkout intents. Distinct from the authority wallet if you want shop revenue isolated from program-operations funds. If unset, the settler falls back to the mint authority pubkey (fine for devnet; explicit pubkey required on mainnet).

Sweep tx fees (~5000 lamports each) are paid by `MINT_AUTHORITY_KEYPAIR`, which already holds SOL for BUX minting — no additional budget needed beyond the authority wallet's existing runway.

### Multi-signer tx builders (Phase 4 behavior)

`contracts/blockster-settler/src/services/bankroll-service.ts` builds every `place_bet_*`, `reclaim_expired`, and `settle_bet` tx with the settler pre-included as a signer (for `place_bet_*`) or account slot (for `reclaim_expired` / `settle_bet`). The settler partial-signs before returning base64 to the client. Implications for operators:

- `MINT_AUTHORITY_KEYPAIR` is actively signing every bet placement, not just settlement. No behavioral change — settler was already on-line per-bet for commitment submission; partial-signing is additional but on the same keypair.
- **DO NOT modify** `feePayer` to be the settler for Wallet Standard (Phantom / Solflare / Backpack) users in ANY tx builder — `buildPlaceBetTx`, the four pool builders (`buildDepositSolTx`, `buildDepositBuxTx`, `buildWithdrawSolTx`, `buildWithdrawBuxTx`), or any future user-signed builder. Those wallets reject sign requests where the connected wallet isn't the fee payer ("Unexpected error" with no useful explanation). `feePayer = player` is required for them. Web3Auth-sourced sessions CAN use `feePayer = settler` because Web3Auth signs locally from an exported key with no wallet-approval invariants. Branching is centralized in `BuxMinter.fee_payer_mode_for_user/1` on the Elixir side + `parseFeePayerMode` helpers on the settler routes that safe-default unknown values to `"player"`. Never default `"settler"` server-side.
- Rust struct field order for `place_bet_sol/bux` / `reclaim_expired` / `settle_bet` is canonical. The TS keys array must match exactly. If you add a field in Rust, update the TS at the same index or Anchor fails with `Custom(3007) AccountOwnedByWrongProgram` — positional reads trip the ownership check.

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
  HOURLY_PROMO_ENABLED="false" \
  --stage --app blockster-v2
```

The `BLOCKSTER_SETTLER_SECRET` must match the `SETTLER_API_SECRET` set on the settler.

`HOURLY_PROMO_ENABLED=false` is the intended default — the `HourlyPromoScheduler` GenServer is gated behind this flag and will NOT start when it's unset or false. Keeping the Telegram promo bot silent on mainnet is the current product decision (see [docs/social_login_plan.md](social_login_plan.md) Appendix A). To re-enable later: `flyctl secrets set HOURLY_PROMO_ENABLED=true --stage --app blockster-v2`, deploy, then toggle the `hourly_promo_enabled` SystemConfig key true via `/admin/promo`.

### Web3Auth social login secrets (Phase 5+)

**These are staged now but the social login feature stays OFF until Phase 10 flips `SOCIAL_LOGIN_ENABLED=true`.** Set them at this step so the deploy picks them up; they're no-ops while the flag is off.

```bash
flyctl secrets set \
  WEB3AUTH_CLIENT_ID="<PROD_WEB3AUTH_CLIENT_ID>" \
  WEB3AUTH_NETWORK="SAPPHIRE_MAINNET" \
  WEB3AUTH_CHAIN_ID="0x65" \
  WEB3AUTH_TELEGRAM_VERIFIER_ID="blockster-telegram" \
  WEB3AUTH_JWT_SIGNING_KEY_PATH="/data/web3auth/signing_key.json" \
  BLOCKSTER_V2_BOT_TOKEN="<TELEGRAM_BOT_TOKEN>" \
  SOCIAL_LOGIN_ENABLED="false" \
  --stage --app blockster-v2
```

`WEB3AUTH_CLIENT_ID` comes from the Web3Auth dashboard — create a **separate Sapphire Mainnet** project for production (DO NOT reuse the Sapphire Devnet project). Whitelist `https://blockster.com` as the authorized origin. Set up the same four social Connections (Email Passwordless — left on but unused, keep enabled in case of fallback; Google; Apple; Twitter) PLUS two Custom JWT verifiers described below.

> **Mobile redirect whitelist (2026-04-24)**: the Web3Auth hook now uses `uxMode: "redirect"` on mobile UAs (iOS Safari + Android Chrome popups are unreliable). The user's browser navigates to `auth.web3auth.io` and back. This means **every origin a user lands back on after OAuth must be whitelisted** in the dashboard. For prod, that's `https://blockster.com`. For staging/dev, add the cloudflared tunnel hostname you're testing on (named tunnels keep a stable hostname; the default rotates per restart). Without the whitelist entry, mobile sign-ins fail post-redirect with a Web3Auth-side `unauthorized origin` error.

`WEB3AUTH_NETWORK=SAPPHIRE_MAINNET` + `WEB3AUTH_CHAIN_ID=0x65` tell the client-side hook to point at mainnet. Devnet was `SAPPHIRE_DEVNET` + `0x67` — these are ws-embed-specific IDs, not the `0x1`/`0x2`/`0x3` from Web3Auth's public Solana docs. See `docs/web3auth_integration.md` §1.

`WEB3AUTH_JWT_SIGNING_KEY_PATH` points at a Fly-mounted RSA private key file that the backend uses to sign JWTs for BOTH Custom JWT verifiers (email OTP + Telegram widget). The dev path (`priv/web3auth_keys/signing_key.json`, boot-generated) is NOT safe for prod — see "Provision the Web3Auth JWT signing key" below.

`BLOCKSTER_V2_BOT_TOKEN` is the existing Telegram bot token (already used for account-connect + group-join detection). The `POST /api/auth/telegram/verify` endpoint uses it to HMAC-verify Telegram Login Widget payloads before issuing a Blockster JWT.

`SOCIAL_LOGIN_ENABLED=false` is the kill switch — with this off the sign-in modal only shows Phantom/Solflare/Backpack (current behavior). Phase 10 is where this flips via the staged rollout procedure.

> **Note (2026-04-23)**: `WEB3AUTH_SOL_CHECKOUT_ENABLED` was removed. Web3Auth users now pay SOL-priced orders the same way Wallet Standard users do — `SolPaymentHook` + `signAndConfirm` handle both signer sources. No separate flag needed.

### Two Custom JWT verifiers must exist in the Web3Auth dashboard

Both point at OUR JWKS (`https://blockster.com/.well-known/jwks.json`). The dashboard needs two separate verifier entries so the MPC wallet derivation namespace stays distinct per identity type (email vs Telegram).

**Verifier 1 — `blockster-email`** (powers in-app email OTP sign-in):

| Field | Value |
|---|---|
| Auth Connection ID | `blockster-email` |
| JWKS Endpoint | `https://blockster.com/.well-known/jwks.json` |
| JWT user identifier | `sub` |
| Validations | `iss` = `blockster`, `aud` = `blockster-web3auth` |
| Algorithm | `RS256` |
| Case Sensitive User Identifier | ON (we lowercase the email server-side before signing, so all subs are lowercase regardless) |

**Verifier 2 — `blockster-telegram`** (powers the Telegram Login Widget path):

| Field | Value |
|---|---|
| Auth Connection ID | `blockster-telegram` |
| JWKS Endpoint | `https://blockster.com/.well-known/jwks.json` (same URL as above) |
| JWT user identifier | `sub` |
| Validations | `iss` = `blockster`, `aud` = `blockster-web3auth` |
| Algorithm | `RS256` |
| Case Sensitive User Identifier | ON |

Generate sample JWTs for the dashboard's paste-a-JWT-token validation step by running in IEx on the target environment:

```elixir
# Sample for blockster-email verifier
BlocksterV2.Auth.Web3AuthSigning.sign_id_token(%{
  "sub" => "sample@blockster.com",
  "email" => "sample@blockster.com",
  "email_verified" => true
})

# Sample for blockster-telegram verifier
BlocksterV2.Auth.Web3AuthSigning.sign_id_token(%{
  "sub" => "123456789",
  "telegram_user_id" => "123456789",
  "telegram_username" => "sample_user"
})
```

Paste the output into the dashboard's JWT field; the dropdown should populate with claims including `sub` — pick it. Generated tokens are 10-minute TTL.

### Provision the Web3Auth JWT signing key

The backend signs Telegram Custom JWTs with an RSA private key. In dev, `BlocksterV2.Auth.Web3AuthSigning` auto-generates one on boot and persists it to `priv/web3auth_keys/signing_key.json` (gitignored). On mainnet, **generate it once on a secure machine, mount as a Fly secret volume or file, and set `WEB3AUTH_JWT_SIGNING_KEY_PATH`**.

```bash
# One-time: generate a 2048-bit RSA keypair wrapped in the JSON format the
# backend reads (same shape as the dev file).
cat <<'EOF' > /tmp/gen_web3auth_key.exs
jwk = JOSE.JWK.generate_key({:rsa, 2048})
{_, pem_bin} = JOSE.JWK.to_pem(jwk)
pem = to_string(pem_bin)
kid = :crypto.hash(:sha256, pem)
      |> Base.encode16(case: :lower)
      |> binary_part(0, 16)
File.write!("/tmp/web3auth_signing_key.json", Jason.encode!(%{pem: pem, kid: kid}))
IO.puts("kid: #{kid}")
IO.puts("Saved to /tmp/web3auth_signing_key.json")
EOF
mix run /tmp/gen_web3auth_key.exs
```

Upload to Fly as a mounted file. Preferred: create a Fly volume just for this key so the filesystem path is stable across deploys.

```bash
# Create a tiny volume attached to the main app
flyctl volumes create web3auth_keys --size 1 --region iad --app blockster-v2

# Mount it in fly.toml under [mounts]:
#   [[mounts]]
#     source = "web3auth_keys"
#     destination = "/data/web3auth"

# On first deploy, SSH in and copy the key into the volume
flyctl ssh console --app blockster-v2
mkdir -p /data/web3auth
# paste the contents of /tmp/web3auth_signing_key.json into /data/web3auth/signing_key.json
# chmod 600 /data/web3auth/signing_key.json
```

Then register the PUBLIC key half with Web3Auth's dashboard (JWKS URL = `https://blockster.com/.well-known/jwks.json` — the backend serves the public JWK set from that path automatically).

**Rotation policy**: if you ever suspect the key is compromised, generate a new one + update the Fly volume + re-register the new JWKS URL (or serve both old and new `kid`s during a transition window). Outstanding Telegram JWTs issued with the old key become invalid at rotation time — users re-sign in.

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
| `PAYMENT_INTENT_SEED` | settler | 32-byte hex — HKDF master seed for shop checkout ephemeral keypairs |
| `SOL_TREASURY_ADDRESS` | settler | Solana pubkey that receives swept shop revenue |
| `WEB3AUTH_CLIENT_ID` | main app | Web3Auth Sapphire Mainnet project client ID |
| `WEB3AUTH_NETWORK` | main app | `SAPPHIRE_MAINNET` (dev: `SAPPHIRE_DEVNET`) |
| `WEB3AUTH_CHAIN_ID` | main app | `0x65` Solana mainnet (devnet: `0x67`) — ws-embed convention, NOT the docs' `0x1`/`0x2`/`0x3` |
| `WEB3AUTH_TELEGRAM_VERIFIER_ID` | main app | Telegram Custom JWT verifier name (usually `blockster-telegram`) |
| `WEB3AUTH_JWT_SIGNING_KEY_PATH` | main app | Path to mounted RSA private key file (e.g. `/data/web3auth/signing_key.json`). Signs BOTH the `blockster-email` and `blockster-telegram` JWTs |
| `SOCIAL_LOGIN_ENABLED` | main app | Master kill-switch for the social-login UI. `false` hides the email form + social tiles |
| `BLOCKSTER_V2_BOT_TOKEN` | main app | Telegram bot token for HMAC verification of Login Widget payloads |
| `SOCIAL_LOGIN_ENABLED` | main app | Feature flag — `false` keeps social login UI hidden |
| `HOURLY_PROMO_ENABLED` | main app | `false` — keeps the Telegram promo scheduler off |

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

### Seed Content Author Personas

The AI content automation pipeline assigns posts to one of the personas defined in `lib/blockster_v2/content_automation/author_rotator.ex`. Each persona needs a `User` row so that posts have a valid `author_id`. The seed script is **idempotent** — existing authors (matched by email) are skipped, so it's always safe to re-run.

This is required on the first mainnet deploy and any time new personas are added to `AuthorRotator`. The current run will provision the 2 Solana-focused personas added in `feat/solana-migration` (`priya_nakamura`, `diego_martinez`) alongside any other missing authors.

The seed logic from `priv/repo/seeds/content_authors.exs` is inlined below so it can run inside a release (release builds don't ship raw `.exs` seed files at predictable paths):

```bash
flyctl ssh console --app blockster-v2 -C "bin/blockster_v2 rpc '
alias BlocksterV2.{Repo, Accounts.User}
for persona <- BlocksterV2.ContentAutomation.AuthorRotator.personas() do
  wallet_hash = :crypto.hash(:sha256, persona.email) |> Base.encode16(case: :lower)
  fake_wallet = \"0x\" <> String.slice(wallet_hash, 0, 40)
  attrs = %{email: persona.email, wallet_address: fake_wallet, username: persona.username, auth_method: \"email\", is_admin: false, is_author: true}
  case Repo.insert(User.changeset(%User{}, attrs)) do
    {:ok, user} -> IO.puts(\"Created: #{persona.username} (id=#{user.id})\")
    {:error, _} -> IO.puts(\"Skipped (exists): #{persona.username}\")
  end
end
'"
```

Verify all 10 personas exist:
```bash
flyctl ssh console --app blockster-v2 -C "bin/blockster_v2 rpc '
alias BlocksterV2.{Repo, Accounts.User}; import Ecto.Query
emails = BlocksterV2.ContentAutomation.AuthorRotator.author_emails()
count = Repo.one(from u in User, where: u.email in ^emails, select: count(u.id))
IO.puts(\"Author personas in DB: #{count} / #{length(emails)}\")
'"
```

Expected: `Author personas in DB: 10 / 10`.

### Bot Wallet Auto-Rotation (first deploy only)

On the first boot after this deploy, `BotCoordinator.handle_info(:initialize, ...)` calls `BotSetup.rotate_to_solana_keypairs/0` exactly once. The function:

1. Selects every bot user whose `wallet_address` is not a valid 32-byte base58 Solana pubkey (i.e. legacy `0x...` EVM addresses).
2. Generates a fresh ed25519 keypair for each via `SolanaWalletCrypto.generate_keypair/0`.
3. Updates `users.wallet_address` (base58 pubkey) and `users.bot_private_key` (base58 64-byte secret) in Postgres.
4. Deletes the bot's stale `user_solana_balances` Mnesia row (the cached SOL/BUX balance belonged to the orphaned EVM wallet).

This runs ~30 seconds after the main app boots (the coordinator's `:initialize` delay). The rotation is **idempotent** — once every bot has a Solana wallet, every subsequent boot returns `{:ok, 0}` and is a no-op. No manual action required.

**Cost**: ~2 SOL one-time, charged to the authority wallet (`6b4n...`) as the rate-limited bot mint queue creates ATAs for the 1000 rotated bots over the following minutes/hours. The mint queue runs at one mint per 500ms, so the surge is paced — not a single burst.

**Confirm rotation succeeded** (see [Step 8](#step-8-post-deploy-verification)).

---

## Step 7.5: AIRDROP-02 Winner Address Backfill

**Required before public launch.** PR 2e (commits `cd44d3c`/`256c763`) ships a one-shot migration that rewrites legacy EVM-style winner addresses in `airdrop_winners` to Solana base58 by following each row's `merged_into_user_id` chain. The migration is gated on operator backup — it does NOT run automatically on `release_command = '/app/bin/migrate'` (it would, but you should ALWAYS back up first).

### 1. Back up the table

```bash
flyctl ssh console --app blockster-v2 -C "pg_dump --table=airdrop_winners --data-only $DATABASE_URL > /tmp/airdrop_winners_premigration_$(date +%Y%m%d_%H%M).sql"
flyctl ssh sftp get /tmp/airdrop_winners_premigration_*.sql --app blockster-v2
```

Confirm the file is non-empty before proceeding.

### 2. Dry-run the backfill

```bash
flyctl ssh console --app blockster-v2 -C "AIRDROP_WINNER_BACKFILL_DRY_RUN=1 bin/blockster_v2 rpc 'BlocksterV2.Airdrop.WinnerAddressBackfill.run(BlocksterV2.Repo) |> IO.inspect()'"
```

The output reports per-row decisions (rewrite to Solana, skip, unresolvable). Review the count; flag any "unresolvable" rows for manual review BEFORE running for real.

### 3. Run the backfill

```bash
flyctl ssh console --app blockster-v2 -C "bin/blockster_v2 rpc 'BlocksterV2.Airdrop.WinnerAddressBackfill.run(BlocksterV2.Repo) |> IO.inspect()'"
```

Idempotent — re-running produces zero writes for already-Solana rows. Module preserves the original wallet in `external_wallet` so the audit trail survives.

### 4. Verify

```bash
flyctl ssh console --app blockster-v2 -C "bin/blockster_v2 rpc '
import Ecto.Query
alias BlocksterV2.Repo
remaining = Repo.one(from w in \"airdrop_winners\", where: like(w.wallet_address, \"0x%\"), select: count(w.id))
IO.puts(\"EVM-style addresses remaining: #{remaining}\")
'"
```

Expected: `0`. If non-zero, those rows have no resolvable Solana wallet — they need manual reconciliation before they render on `/airdrop`.

> Do NOT combine this backfill with other migrations in the same deploy — it's the only reason for sequencing this step between Step 7 (Deploy Main App) and Step 8 (Verification).

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
7. **Shop checkout** (Phase 5b): Go to `/shop`, add a low-value item to cart, complete shipping → proceed to payment → verify a unique SOL address + expiry countdown render → click "Pay from connected wallet" → approve → verify order flips to "paid" within 10–20s and the confirmation page shows the funded tx Solscan link. Within the next minute or two `/admin/orders/:id` should show the `swept_tx_sig` populated (watcher ticks every 10s, sweep takes one extra tick after funding).

### Verify Bot Wallet Rotation

Confirm `BotCoordinator` rotated the bot wallets on first boot:

```bash
flyctl logs --app blockster-v2 | grep -i "Rotated.*bot wallets"
```

Expected log line (~30s after the first machine started):
```
[BotCoordinator] Rotated 1000 bot wallets from EVM → Solana
```

Then verify in the database that all bot wallets are Solana base58 (no `0x` prefix):

```bash
flyctl ssh console --app blockster-v2 -C "bin/blockster_v2 rpc '
alias BlocksterV2.{Repo, Accounts.User}; import Ecto.Query
total = Repo.one(from u in User, where: u.is_bot == true, select: count(u.id))
evm_remaining = Repo.one(from u in User, where: u.is_bot == true and like(u.wallet_address, \"0x%\"), select: count(u.id))
IO.puts(\"Total bots: #{total}, EVM remaining: #{evm_remaining}\")
'"
```

Expected: `Total bots: 1000, EVM remaining: 0`. If `EVM remaining > 0`, check the logs for `[BotSetup] Failed to rotate bot N` errors and re-run rotation manually:

```bash
flyctl ssh console --app blockster-v2 -C "bin/blockster_v2 rpc 'BlocksterV2.BotSystem.BotSetup.rotate_to_solana_keypairs() |> IO.inspect()'"
```

Finally, verify a bot mint actually landed on-chain by picking any bot and checking its Solana balance:

```bash
flyctl ssh console --app blockster-v2 -C "bin/blockster_v2 rpc '
alias BlocksterV2.{Repo, Accounts.User}; import Ecto.Query
user = Repo.one(from u in User, where: u.is_bot == true, limit: 1)
IO.puts(\"Bot wallet: #{user.wallet_address}\")
BlocksterV2.BuxMinter.get_balance(user.wallet_address) |> IO.inspect()
'"
```

After ~10 minutes of bot reads landing, this should show non-zero `bux` balance and a Solscan-visible tx history.

### Start First Airdrop Round (optional)

From the Elixir console:
```bash
flyctl ssh console --app blockster-v2 -C "bin/blockster_v2 rpc '
end_time = DateTime.add(DateTime.utc_now(), 7, :day)
BlocksterV2.Airdrop.create_round(end_time)
|> IO.inspect()
'"
```

### Phase 6 widgets + luxury ads — post-deploy seed

All banner rows (widgets + luxury ads + coin flip demos) are NOT seeded automatically by `release_command = '/app/bin/migrate'`. They must be inserted via a single seed script after the deploy lands.

**Single source of truth:** [`priv/repo/seeds_banners.exs`](../priv/repo/seeds_banners.exs) defines the full banner state — 57 active + 5 dormant rows spanning `article_inline_{1,2,3}`, `homepage_inline`, `homepage_top_desktop`, and `sidebar_{left,right}`. Replaces the legacy `seeds_ad_banners.exs`, `seeds_widget_banners.exs`, `seeds_luxury_ads.exs`, and `seeds_article_inline_force.exs` scripts (deleted). See [`ad_banners_system.md`](ad_banners_system.md) for the full reference on how templates/widgets/mobile swaps work.

Behaviour:
- Deactivates EVERY existing banner first (blank slate), then upserts every row in the file by `name`. Entries default to `is_active: true`; entries may set `is_active: false` to ship a dormant creative (admins toggle on via `/admin/banners`).
- Safe to re-run — running a second time updates every attribute to match the file (not just `is_active`).
- Any banner row NOT in the file stays in the DB but inactive. Admins can still edit/re-enable through `/admin/banners`.
- The source file is the authoritative state — edit it to change prod ad inventory, then re-run.

**1. Run the consolidated banner seed:**

```bash
flyctl ssh console --app blockster-v2 -C "/app/bin/blockster_v2 eval 'Code.eval_file(Path.wildcard(\"/app/lib/blockster_v2-*/priv/repo/seeds_banners.exs\") |> hd())'"
```

Expected output ends with:
```
Created: N
Updated: M
Total active:  57
Total dormant: 5  (created but is_active: false — toggle via /admin/banners)
```

> Reference doc for how the luxury templates work + how to add new dealer brands: [`luxury_ad_templates.md`](luxury_ad_templates.md).

All luxury images are hosted on ImageKit (`ik.imagekit.io/blockster/ads/<dealer>/...`) — no local-file dependency. ImageKit serves directly from the project's S3 bucket as origin.

**2. Stage `WIDGETS_ENABLED` to enable the real-time pollers**:

```bash
flyctl secrets set WIDGETS_ENABLED=true --stage --app blockster-v2
```

`--stage` is mandatory (per CLAUDE.md secrets rules) — without it the production server immediately restarts. Staged secrets take effect on the next deploy.

**3. Re-deploy to pick up the staged secret**:

```bash
flyctl deploy --app blockster-v2
```

After this deploy lands, the 3 trackers (`FateSwapFeedTracker`, `RogueTraderBotsTracker`, `RogueTraderChartTracker`) start polling. Combined load:
- FateSwap: ~20 req/min to `fateswap.fly.dev/api/feed/recent`
- RogueTrader: ~6 req/min to `roguetrader-v2.fly.dev/api/bots` + ~150 req/min to `roguetrader-v2.fly.dev/api/bots/:id/chart` (30 bots × 5 timeframes, staggered across 60s window)

Traffic is constant regardless of visitor count (single GlobalSingleton per cluster — no per-user fanout).

**4. Sanity check the widgets are receiving data**:

Open `https://blockster.com/` (homepage) and any article page — confirm:
- Top ticker (homepage) shows live RogueTrader bot prices scrolling
- Article right sidebar (`rt_skyscraper`) shows 30 ranked bots with live bid/ask prices
- Article left sidebar (`fs_skyscraper`) shows recent FateSwap trades with status pills
- No widget shows the "feed paused — retrying" amber error placeholder (means `last_error` is set)

If skeletons are stuck (no data after 30s), check:

```bash
flyctl logs --app blockster-v2 | grep -E "FateSwapFeedTracker|RogueTraderBotsTracker|RogueTraderChartTracker"
```

Expected log lines: `[<TrackerName>] Started — polling every <ms>ms`. If you see `Poll failed: ...`, the sister API is unhealthy or rate-limiting.

**5. Verify luxury ads render**:

Browse to any article page → confirm the Gray & Sons watch skyscraper, Ferrari/Lambo inline ads, Flight Finder Exclusive jet card render with **live SOL prices** (USD figures stored statically; SOL converted at render time via `BlocksterV2.PriceTracker.get_price("SOL")` reading the `token_prices` Mnesia cache that's refreshed every minute).

If SOL prices show `—` (em dash), the PriceTracker either hasn't fetched yet (give it 60s) or its CoinGecko fetch is failing — check logs for `[PriceTracker]` errors.

---

## Step 8.5: Social Login Rollout (Phase 10)

Social login ships behind `SOCIAL_LOGIN_ENABLED`. After the Phase 5–10 session delivers the UI + hook + onboarding + settings flows, roll out gradually:

### Pre-flight checklist before enabling

- [ ] Web3Auth Sapphire **Mainnet** project created (not devnet), client ID matches `WEB3AUTH_CLIENT_ID` secret.
- [ ] `WEB3AUTH_NETWORK=SAPPHIRE_MAINNET` and `WEB3AUTH_CHAIN_ID=0x65` staged (0x65 = Solana mainnet in ws-embed's chain ID convention — NOT `0x1`).
- [ ] `https://blockster.com` whitelisted as an authorized origin in the Web3Auth dashboard.
- [ ] OAuth Connections enabled: Google, Apple, Twitter (X). Email Passwordless kept on as an unused fallback — production email flow runs through the `blockster-email` Custom JWT verifier instead.
- [ ] **Custom JWT verifier `blockster-email` registered**: JWKS URL `https://blockster.com/.well-known/jwks.json`, verifier ID field `sub`, aud `blockster-web3auth`, iss `blockster`, alg `RS256`. See the two-verifier table in Step 7 (Web3Auth secrets) above.
- [ ] **Custom JWT verifier `blockster-telegram` registered** (same JWKS / aud / iss / alg), name matches `WEB3AUTH_TELEGRAM_VERIFIER_ID`.
- [ ] RSA signing key mounted at `/data/web3auth/signing_key.json` on the production volume. `mix run /tmp/gen_web3auth_key.exs` output placed there.
- [ ] `curl https://blockster.com/.well-known/jwks.json` returns a valid JWKS with one RSA key (matches the `kid` on the mounted signing key).
- [ ] `POST /api/auth/web3auth/email_otp/send` accepts a valid email and returns `{"success": true, "ttl": 600}`.
- [ ] `POST /api/auth/web3auth/email_otp/verify` returns `{"success": true, "id_token": "eyJ..."}` when given the emailed code.
- [ ] `POST /api/auth/telegram/verify` handles at least one known-good widget payload end-to-end.
- [ ] A manual Web3Auth email signup flow on staging completes: modal → email input → receive OTP → enter code in modal (no popup!) → Web3Auth MPC derives pubkey → user row created → session cookie set → onboarding lands.
- [ ] A legacy EVM user email sign-in on staging completes the reclaim merge: legacy user row deactivated, legacy BUX minted to new Solana wallet via settler, username/X/Telegram/phone transferred, returning user lands on `/` (onboarding skipped).
- [ ] SOL-priced shop checkout completes end-to-end as a Web3Auth user on devnet (the 2026-04-23 Phase 13 work removed the `WEB3AUTH_SOL_CHECKOUT_ENABLED` gate; prove `payment_mode="wallet_sign"` + `SolPaymentHook` take SOL off a Web3Auth-derived wallet to the ephemeral intent address).

### Staged rollout

```bash
# 1. Enable flag, staged (takes effect on next deploy)
flyctl secrets set SOCIAL_LOGIN_ENABLED=true --stage --app blockster-v2
flyctl deploy --app blockster-v2

# 2. Gate by user: the code checks SOCIAL_LOGIN_ENABLED + optionally an
#    allowlist hash for 10%/50% ramp. Adjust the allowlist helper as
#    needed (Phase 5 session will ship the exact mechanism).
```

Ramp: 10% → 50% → 100% over ~1 week. At each ramp, watch metrics for 24h before advancing.

### Metrics to watch during rollout

- **Signups by `auth_method`** per day — confirm social paths are seeing real traffic, not just errors.
- **Web3Auth JWT verify failure rate** — alerts if > 5%/hour (suggests JWKS issue or clock skew).
- **Settler balance drift per day** — should be net-zero at steady state (rent cycles). Slight negative for priority fees. If drifting negative fast, investigate — likely an unsettled-bet accumulation issue.
- **First-bet conversion per auth_method** — target > 60% for social signups. Lower means UX friction somewhere.
- **FEE_PAYER balance alert**: if settler < 5 SOL, top up. (Note: rent cycles through settler — the alert is about priority-fee depletion, not rent.)

### Rollback

If social login causes issues at any ramp, immediate kill:

```bash
flyctl secrets set SOCIAL_LOGIN_ENABLED=false --stage --app blockster-v2
flyctl deploy --app blockster-v2
```

Wallet Standard (Phantom) flow is defense-in-depth — disabling social login doesn't affect wallet users. Zero impact on existing users.

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

**Already automated as of 2026-04-25.** All Solscan link rendering goes through `BlocksterV2Web.Solscan` (`lib/blockster_v2_web/solscan.ex`). The helper checks `WEB3AUTH_CHAIN_ID`:

- `0x65` → `https://solscan.io/...` (no cluster query, mainnet)
- anything else → `https://solscan.io/...?cluster=devnet`

Setting `WEB3AUTH_CHAIN_ID=0x65` in Step 6 flips every Solscan link site-wide automatically. No code edit, no grep-and-replace. Affected sites: pool/coin-flip activity rows, airdrop verification panel, admin user table, member profile, wallet self-custody panel, footer "BUX on Solscan", design-system user dropdown, docs pages.

If you ever revert the `WEB3AUTH_CHAIN_ID` env (or it's lost), the cluster falls back to devnet — confirmed safe behavior, not a deploy-breaker. To audit any new code adding raw Solscan URLs:

```bash
grep -rn "?cluster=devnet" lib/ | grep -v "/legacy/" | grep -v "solscan.ex"
```

Should return zero hits. If non-zero, route the new code through `BlocksterV2Web.Solscan` before merging.

The narrative copy on `/docs` (e.g. "deployed on Solana devnet today") also branches on `BlocksterV2Web.Solscan.mainnet?/0` — flips to "deployed on Solana mainnet" when `WEB3AUTH_CHAIN_ID=0x65` is set.

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
#    49aNHDAduVnEcEEqCyEXMS1rT62UnW5TajA2fVtNpC1d — 5 SOL (program deploys)
#    6b4nMSTWJ1yxZZVmqokf6QrVoF9euvBSdB11fC3qfuv1 — 3 SOL (program init + bot ATA surge + 1 month headroom)

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
flyctl secrets set SOLANA_RPC_URL="$MAINNET_RPC" SOLANA_NETWORK="mainnet-beta" SETTLER_API_SECRET="$SHARED_SECRET" BUX_MINT_ADDRESS="MAINNET_MINT" BANKROLL_PROGRAM_ID="49up2uzZANpjTC3sgggbZazdHBii2vY9mVK3vk5dT2tm" AIRDROP_PROGRAM_ID="wxiuLBuqxem5ETmGDndiW8MMkxKXp5jVsNCqdZgmjaG" MINT_AUTHORITY_KEYPAIR="$(cat keypairs/mint-authority.json)" PAYMENT_INTENT_SEED="$(openssl rand -hex 32)" SOL_TREASURY_ADDRESS="MAINNET_TREASURY_PUBKEY" --stage --app blockster-settler
flyctl deploy --app blockster-settler

# 8. Configure and deploy main app
cd ../..
flyctl secrets set BLOCKSTER_SETTLER_URL="https://blockster-settler.fly.dev" BLOCKSTER_SETTLER_SECRET="$SHARED_SECRET" SOLANA_RPC_URL="$MAINNET_RPC" SOLANA_AUTHORITY_ADDRESS="6b4nMSTWJ1yxZZVmqokf6QrVoF9euvBSdB11fC3qfuv1" --stage --app blockster-v2
flyctl deploy --app blockster-v2

# 9. Verify
curl https://blockster-settler.fly.dev/health
curl https://blockster.com
```
