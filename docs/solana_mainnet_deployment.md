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

Send **3 SOL** (real SOL) to the authority wallet. Breakdown:
- ~0.1 SOL for program initialization (Bankroll + Airdrop PDAs, BUX mint)
- ~2 SOL for the one-time bot wallet rotation ATA surge (see [Step 7](#step-7-deploy-main-app))
- ~1 SOL of headroom for the first month of minting

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
| `PAYMENT_INTENT_SEED` | settler | 32-byte hex — HKDF master seed for shop checkout ephemeral keypairs |
| `SOL_TREASURY_ADDRESS` | settler | Solana pubkey that receives swept shop revenue |

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
