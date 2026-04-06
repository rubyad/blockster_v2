# Blockster V2

Phoenix LiveView application with Elixir backend, serving a web3 content platform with a shop, hubs, events, and token-based engagement system.

> **Claude Instructions**: For detailed historical bug fixes and implementation notes, see [docs/session_learnings.md](docs/session_learnings.md). Keep this file concise (~350 lines). Only add new learnings here if they represent stable patterns or critical rules. Move detailed narratives to session_learnings.md.
>
> **When user says "update docs"**: Update ALL of these as appropriate:
> - `docs/solana_build_history.md` — chronological build log (always update for Solana-related changes)
> - `docs/session_learnings.md` — detailed bug fix narratives
> - `CLAUDE.md` — only for stable patterns or critical rules
>
> **CRITICAL GIT RULES**:
> - NEVER add, commit, or push changes to git without EXPLICIT user instructions
> - NEVER change git branches without EXPLICIT user instructions
> - **NEVER run `git checkout --`, `git restore`, or `git stash` on files without first running `git diff` to verify no pre-existing uncommitted changes exist** — these commands destroy ALL unstaged work irreversibly, not just your own edits. To undo only your changes, use targeted Edit tool calls.
>
> **CRITICAL SECURITY RULES**:
> - NEVER read or access any `.env` file - these contain private keys and secrets
> - **NEVER use public RPC endpoints** (`api.devnet.solana.com`, `api.mainnet-beta.solana.com`) for ANY Solana command — always use the project QuickNode RPC from `contracts/blockster-settler/src/config.ts`. This applies to `solana program deploy`, `solana balance`, `solana transfer`, scripts, and ALL CLI commands. Public RPCs are rate-limited and unreliable.
> - NEVER use `solana airdrop` or any devnet faucet — they are rate-limited and do not work. Ask the user to fund the wallet manually.
>
> **CRITICAL SOLANA TX CONFIRMATION RULES**:
> - **NEVER use `confirmTransaction` (websocket subscriptions)** for confirming Solana transactions — it is unreliable, creates RPC contention when multiple txs are in flight, and causes slow/stuck confirmations
> - **NEVER use manual rebroadcast loops** (`setInterval` + `sendRawTransaction`) — `maxRetries` on `sendRawTransaction` handles delivery retries at the RPC level
> - **ALWAYS use `getSignatureStatuses` polling** (like ethers.js `tx.wait()`) — send the tx once with `maxRetries:5`, then poll `getSignatureStatuses` every 2s until "confirmed". See `rpc-client.ts:waitForConfirmation` and `coin_flip_solana.js:pollForConfirmation`
> - This applies to ALL Solana code: settler services, client-side JS hooks, scripts, and any new services
>
> **CRITICAL DEPENDENCY RULES**:
> - NEVER update Phoenix, LiveView, Ecto, or other core dependencies without EXPLICIT user permission
>
> **CRITICAL AI MODEL RULES**:
> - NEVER downgrade the AI Manager model to Sonnet or Haiku — always use the latest Opus model
> - The AI Manager (`ai_manager.ex`) must always use Claude Opus for API calls
>
> **CRITICAL DATABASE RULES**:
> - NEVER run `mix ecto.reset`, `mix ecto.drop`, or any command that drops/recreates the database
> - NEVER delete or truncate tables — production data (products, hubs, users) is manually curated and irreplaceable
> - The ONLY safe Ecto commands are `mix ecto.migrate` and `mix ecto.rollback`
> - If a migration needs fixing, roll it back and fix — NEVER reset the entire database
>
> **CRITICAL MNESIA RULES**:
> - NEVER delete Mnesia directories (`priv/mnesia/node1`, `priv/mnesia/node2`) - contains unrecoverable user data
> - When new Mnesia tables are added, restart both nodes to create them
> - There is NO scenario where deleting Mnesia directories is correct
>
> **CRITICAL FLY.IO SECRETS RULES**:
> - ALWAYS use `--stage` when setting secrets: `flyctl secrets set KEY=VALUE --stage --app blockster-v2`
> - `flyctl secrets set` WITHOUT `--stage` **immediately restarts the production server** — this is destructive
> - Staged secrets take effect on the next deploy, which is the safe and expected behavior
> - NEVER run `flyctl secrets set` without `--stage` unless the user EXPLICITLY says to restart production
>
> **CRITICAL SOLANA PROGRAM DEPLOY RULES**:
> - **Upgrade authority** for both Bankroll and Airdrop programs is the settler keypair (`6b4n...`), NOT the CLI wallet (`49aN...`)
> - Deploy command MUST use `--upgrade-authority` pointing to settler keypair:
>   ```
>   solana program deploy target/deploy/blockster_bankroll.so \
>     --program-id 49up2uzZANpjTC3sgggbZazdHBii2vY9mVK3vk5dT2tm \
>     --upgrade-authority contracts/blockster-settler/keypairs/mint-authority.json \
>     --url https://summer-sleek-shape.solana-devnet.quiknode.pro/92b7f51caa76f2981879528aee40a3e8e58cac60/
>   ```
> - Fee payer is the CLI wallet (`49aN...`) — needs ~5 SOL for program deploys
> - **IF DEPLOY FAILS** (insufficient funds, network error): Solana creates a **buffer account** with an ephemeral keypair. The output shows a 12-word seed phrase. **YOU MUST RECOVER AND CLOSE THIS BUFFER** or the SOL is lost:
>   1. Save the seed phrase from the error output
>   2. Recover keypair using `expect` (solana-keygen needs TTY, use this pattern):
>      ```
>      expect -c '
>      spawn solana-keygen recover --outfile /tmp/buffer-keypair.json --force --skip-seed-phrase-validation
>      expect "seed phrase:"
>      send "PASTE_SEED_PHRASE_HERE\r"
>      expect "passphrase"
>      send "\r"
>      expect "Continue"
>      send "y\r"
>      expect eof
>      '
>      ```
>   3. Close buffer to recover SOL: `solana program close /tmp/buffer-keypair.json --url https://summer-sleek-shape.solana-devnet.quiknode.pro/92b7f51caa76f2981879528aee40a3e8e58cac60/`
>   4. Retry deploy after funding the wallet
> - **NEVER ignore a failed deploy** — always recover the buffer first
>
> **CRITICAL BUX TOKEN RULES**:
> - BUX tokens live ON-CHAIN in users' smart wallets — they are real ERC-20 tokens, not just Mnesia entries
> - Mnesia tracks balances for fast reads, but the on-chain balance is the source of truth
> - To move BUX out of a user's wallet: approve() + transferFrom() — NEVER mint fresh tokens as a shortcut
> - The airdrop deposit flow MUST use approve + transferFrom from the user's smart wallet to the vault
> - NEVER assume tokens don't exist on-chain. If a user earned BUX and it was minted to their smart wallet, it's THERE.
> - DO NOT invent or assume how systems work — read the code, read the contracts, and if unsure ASK THE USER
>
> **DEVELOPMENT WORKFLOW**:
> - DO NOT restart nodes after code fixes - Elixir hot reloads. Only restart for supervision tree/config changes
> - NEVER use the Write tool to rewrite entire documentation files - use Edit for targeted changes
> - NEVER deploy without explicit user instructions
> - **ALL tests must pass before deploying** — run `mix test` and fix every single failure. Zero failures required.

## Branding

- **Brand Color**: `#CAFC00` (lime green) - accent ONLY, NOT for buttons, tabs, or large UI surfaces on light backgrounds
  - NEVER use as text color
  - NEVER use as button backgrounds — lime on white looks washed out
  - NEVER use random greens (green-600, emerald, etc.) for text — looks cheap
  - OK for: small accent dots, icon backgrounds, subtle borders/rings, progress indicators
  - **Buttons/tabs**: Use `bg-gray-900 text-white` (dark) or `bg-gray-100 text-gray-900` (light) — NOT lime
- **Logo**: `https://ik.imagekit.io/blockster/blockster-icon.png` - via `lightning_icon/1` component
- **Icons**: Heroicons solid style, pattern: `w-16 h-16 bg-[#CAFC00] rounded-xl` + `w-8 h-8 text-black`

## Tech Stack
- **Backend**: Elixir/Phoenix 1.7+ with LiveView
- **Database**: PostgreSQL with Ecto, Mnesia for real-time distributed state
- **Frontend**: TailwindCSS, TipTap editor, Thirdweb for wallet integration
- **Blockchain**: Rogue Chain Mainnet (Chain ID: 560013)
- **Deployment**: Fly.io (app: blockster-v2)
- **Account Abstraction**: ERC-4337 with gasless smart wallets via Paymaster

## Key Directories
- `lib/blockster_v2/` - Core business logic
- `lib/blockster_v2_web/live/` - LiveView modules
- `assets/js/` - JavaScript hooks for LiveView
- `priv/repo/migrations/` - Ecto migrations
- `docs/` - Feature documentation
- `contracts/legacy-evm/` - Solidity contracts (EVM, legacy - renamed from bux-booster-game)
- `contracts/blockster-bankroll/` - Anchor program: dual-vault bankroll (SOL + BUX)
- `contracts/blockster-settler/` - Node.js settler service: BUX minting, bet settlement

## Running Locally

### Quick Start (recommended)
```bash
bin/dev           # Starts settler + 2 Elixir nodes (full cluster)
bin/dev single    # Starts settler + 1 Elixir node (no cluster)
bin/dev settler   # Starts only the settler service
```
This starts all services in one terminal. Ctrl+C stops everything.

### What `bin/dev` starts
| Service | Port | Purpose |
|---------|------|---------|
| Settler | 3000 | Solana minter/settler (BUX mint, bet settlement, airdrop, pool txs) |
| Node 1 | 4000 | Main Phoenix app |
| Node 2 | 4001 | Cluster peer (Mnesia replication, GlobalSingleton failover) |

### Prerequisites
```bash
# 1. Install settler dependencies (first time only)
cd contracts/blockster-settler && npm install && cd ../..

# 2. Ensure keypairs exist (needed for Solana devnet minting)
ls contracts/blockster-settler/keypairs/mint-authority.json

# 3. Ensure PostgreSQL is running and DB is migrated
mix ecto.migrate
```

### Manual Start (separate terminals)
```bash
# Terminal 1: Settler service (Solana devnet, auth bypassed in dev)
cd contracts/blockster-settler && npx ts-node src/index.ts

# Terminal 2: Elixir node1
elixir --sname node1 -S mix phx.server

# Terminal 3: Elixir node2
PORT=4001 elixir --sname node2 -S mix phx.server
```

### Dev Environment Details
- **Settler auth**: Skipped in dev mode (`SETTLER_API_SECRET=dev-secret`)
- **Elixir→Settler**: BuxMinter defaults to `http://localhost:3000` when `BLOCKSTER_SETTLER_URL` is unset
- **Solana network**: Devnet (QuickNode RPC in settler config)
- **Mnesia**: Stored at `priv/mnesia/{node_name}` — NEVER delete these directories
- **libcluster**: Auto-discovers `node1`/`node2` in dev via Erlang distribution

## Deployment
```bash
git push origin <branch> && flyctl deploy --app blockster-v2
```

---

## Development Guidelines

### UI/UX
- Always add `cursor-pointer` to clickable elements
- Custom fonts: `font-haas_medium_65`, `font-haas_roman_55`
- Prefer Tailwind utility classes over arbitrary hex values
- Style content links: `[&_a]:text-blue-500 [&_a]:no-underline [&_a:hover]:underline`

### LiveView Patterns

**Async API Calls** - ALWAYS use `start_async` for external calls:
```elixir
# Extract values BEFORE start_async (NEVER access socket.assigns inside)
user_id = socket.assigns.current_user.id
start_async(socket, :fetch_data, fn -> fetch_data(user_id) end)
```

**HTTP Timeouts** - ALWAYS configure:
```elixir
Req.get(url, receive_timeout: 30_000)
# or for :httpc
:httpc.request(:get, {url, headers}, [{:timeout, 10_000}, {:connect_timeout, 5_000}], [])
```

**Double Mount**: LiveView mounts twice. Use `connected?(socket)` for side effects (API calls, blockchain transactions) to avoid duplicates.

### Mnesia
- **Always use dirty operations** (`dirty_read`, `dirty_write`, `dirty_delete`, `dirty_index_read`)
- **For concurrent updates**: Route writes through a dedicated GenServer to serialize
- **Modifying table schemas**: Add new fields to END only. Create migration function. Scale to 1 server before deploying. See CLAUDE.md history for full process.

### GenServer Global Registration
- Use `BlocksterV2.GlobalSingleton` for GenServers that should run once across cluster
- Handles rolling deploy conflicts safely (keeps existing process, rejects new)
- **Global**: MnesiaInitializer, PriceTracker, BuxBoosterBetSettler, TimeTracker, BotCoordinator
- **Local**: HubLogoCache (manages local ETS table)

### Smart Contract Upgrades (UUPS)
- NEVER change order or remove state variables - ONLY add at END
- NEVER enable `viaIR: true` for stack too deep - use helper functions instead
- Upgrade process: compile → force-import → upgrade-manual → init-vN → verify
- **ALL contracts must be flattened** (inline all OZ dependencies) so they can be verified as a single file on RogueScan/Arbiscan
- Never use `import "@openzeppelin/..."` — copy the needed code inline

---

## Token System

BUX is the only active token. ROGUE is the native gas token. Hub tokens (moonBUX, etc.) are deprecated.

### Contract Addresses (Rogue Chain Mainnet)
| Contract | Address |
|----------|---------|
| BUX Token | `0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8` |
| BuxBoosterGame (Proxy) | `0x97b6d6A8f2c6AF6e6fb40f8d36d60DF2fFE4f17B` |
| ROGUEBankroll | `0x51DB4eD2b69b598Fade1aCB5289C7426604AB2fd` |
| NFTRewarder | `0x96aB9560f1407586faE2b69Dc7f38a59BEACC594` |
| EntryPoint v0.6.0 | `0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789` |
| ManagedAccountFactory | `0xfbbe1193496752e99BA6Ad74cdd641C33b48E0C3` |
| Paymaster | `0x804cA06a85083eF01C9aE94bAE771446c25269a6` |
| Referral Admin | `0xbD6feD8fEeec6f405657d0cA4A004f89F81B04ad` |
| AirdropVault V3 (Proxy, Rogue) | `0x27049F96f8a00203fEC5f871e6DAa6Ee4c244F6c` |
| AirdropPrizePool (Proxy, Arbitrum) | `0x919149CA8DB412541D2d8B3F150fa567fEFB58e1` |
| Deployer Wallet | `0x4BDC5602f2A3E04c6e3a9321A7AC5000e0A623e0` |
| Vault Admin Wallet | `0xBd16aB578D55374061A78Bb6Cca8CB4ddFaBd4C9` |
| High Rollers NFT (Arbitrum) | `0x7176d2edd83aD037bd94b7eE717bd9F661F560DD` |

### BUX Minter Service
Deployed at `https://bux-minter.fly.dev` (Node.js + Express + ethers.js)

Key endpoints: `POST /mint`, `GET /balance/:address`, `GET /aggregated-balances/:address`, `POST /submit-commitment`, `POST /settle-bet`, `GET /game-token-config/:token`

Minting is a common operation - don't add unnecessary validation.

---

## User Registration & Wallet Fields

- `wallet_address` = **primary wallet** — Solana pubkey for new users, EOA for legacy EVM users. **Use this for all mint/sync/balance operations.**
- `smart_wallet_address` = legacy EVM ERC-4337 smart wallet (nil for Solana users, kept for schema compat)
- **NEVER use `smart_wallet_address` for BuxMinter calls** — Solana users don't have one, so mints silently skip
- Settler mint response key is `"signature"` (Solana tx sig), NOT `"transactionHash"` (EVM)

---

## Rogue Chain Network
| Property | Value |
|----------|-------|
| Chain ID | `560013` |
| RPC URL | `https://rpc.roguechain.io/rpc` |
| Explorer | `https://roguescan.io` |
| Bundler | `https://rogue-bundler-mainnet.fly.dev` |

## Solana Migration (Phases 1-12 complete)

Migration from Rogue Chain (EVM) to Solana. Full plan: [docs/solana_migration_plan.md](docs/solana_migration_plan.md). All addresses: [docs/addresses.md](docs/addresses.md).

| Resource | Address / Value |
|----------|----------------|
| BUX Mint (devnet) | `7CuRyw2YkqQhUUFbw6CCnoedHWT8tK2c9UzZQYDGmxVX` |
| Mint Authority | `6b4nMSTWJ1yxZZVmqokf6QrVoF9euvBSdB11fC3qfuv1` |
| Bankroll Program ID | `49up2uzZANpjTC3sgggbZazdHBii2vY9mVK3vk5dT2tm` |
| Airdrop Program ID | `wxiuLBuqxem5ETmGDndiW8MMkxKXp5jVsNCqdZgmjaG` |
| RPC (devnet) | QuickNode (see migration plan) |

**Deployment status (devnet)**: Both programs deployed and fully initialized. Coin Flip game registered (game_id=1). Authority = `6b4n...` (settler keypair). Deploy fee payer = `49aN...` (CLI wallet). See `docs/addresses.md` for all PDA addresses.

**Bankroll Program** (`contracts/blockster-bankroll/`): Anchor 0.30.1, dual-vault (SOL + BUX), LP tokens (bSOL + bBUX), game registry, provably fair commit-reveal, two-tier referrals. 4-step init due to SBF stack limits. IDL manually maintained at `target/idl/blockster_bankroll.json` (auto-gen broken on modern Rust). Per-difficulty max bet enforcement: `place_bet` accepts `difficulty: u8` (not `max_payout`), program computes max_payout on-chain from stored multipliers (matching EVM BuxBoosterGame). GameEntry stores `multipliers: [u16; 9]` as BPS/100. Config: `max_bet_bps=100` (1%), `min_bet=0.01 tokens`. **Concurrent bets**: `has_active_order` constraint removed from `place_bet` — multiple BetOrders can exist per player at different nonces. Each BetOrder PDA is seeded `[b"bet", player, nonce_le_bytes]` so they're fully independent. The `has_active_order` field is kept in PlayerState for layout compatibility but is no longer read or enforced.

**Airdrop Program** (`contracts/blockster-airdrop/`): Anchor 0.30.1, multi-round, any SPL/SOL prizes, BUX entries, SHA256 commit-reveal. IDL at `target/idl/blockster_airdrop.json`.

**Settler Service** (`contracts/blockster-settler/`): Node.js service for BUX minting, bet settlement, balance queries. Replaces bux-minter.fly.dev.

**Solana Auth** (Phase 2 — complete):
- SIWS: `lib/blockster_v2/auth/solana_auth.ex` + `nonce_store.ex`
- Wallet hook: `assets/js/hooks/solana_wallet.js` (Wallet Standard, deferred localStorage)
- WalletAuthEvents macro: `lib/blockster_v2_web/live/wallet_auth_events.ex`
- Wallet UI: `lib/blockster_v2_web/components/wallet_components.ex` (connect_button, wallet_selector_modal)
- Session: `POST/DELETE /api/auth/session`, UserAuth on_mount reads wallet_address from session + connect_params
- User model: `email_verified`, `legacy_email` fields added (migration `20260402200001`)
- `downcase_wallet_address` skips Solana base58 addresses (case-sensitive)
- Deps: hex `base58`; npm `@wallet-standard/app`, `bs58`, `@solana/web3.js`

**BUX Minter Service** (Phase 3 — complete):
- `lib/blockster_v2/bux_minter.ex` rewritten for Solana settler (`BLOCKSTER_SETTLER_URL` env var)
- Same `mint_bux/5` interface, calls `/mint` on settler service
- `get_balance/1` returns `%{sol: float, bux: float}` from settler `/balance/:wallet`
- New Mnesia table `user_solana_balances` `{user_id, wallet_address, updated_at, sol_balance, bux_balance}`
- EngagementTracker: `get_user_sol_balance/1`, `update_user_sol_balance/3`, `update_user_solana_bux_balance/3`
- Config: `settler_url`, `settler_secret`, `solana_rpc_url` in `runtime.exs`
- Deprecated: `get_aggregated_balances`, `get_rogue_house_balance`, `transfer_rogue` (return `{:error, :deprecated}`)

**User Onboarding & Migration** (Phase 4 — complete):
- Email verification: `lib/blockster_v2/accounts/email_verification.ex` (6-digit code, 10min expiry, Swoosh delivery)
- Legacy BUX migration: `lib/blockster_v2/migration/legacy_bux.ex` + PG table `legacy_bux_migrations`
- Onboarding modal: `lib/blockster_v2_web/components/onboarding_modal.ex` (welcome → email → claim)
- `/login` route removed — redirects to `/` via `PageController.login_redirect`

**Multiplier System Overhaul** (Phase 5 — complete):
- SOL multiplier: `lib/blockster_v2/sol_multiplier.ex` (10 tiers: 0x at <0.01 SOL → 5x at 10+ SOL)
- Email multiplier: `lib/blockster_v2/email_multiplier.ex` (verified=2x, unverified=1x)
- Unified multiplier rewritten: `overall = x * phone * sol * email`, max 200x
- New Mnesia table `unified_multipliers_v2` (replaces `unified_multipliers` fields: sol_multiplier, email_multiplier instead of rogue_multiplier, wallet_multiplier)
- Deleted: `rogue_multiplier.ex`, `wallet_multiplier.ex`, `wallet_multiplier_refresher.ex`
- Removed `WalletMultiplierRefresher` from supervision tree
- SOL multiplier refreshes on every `BuxMinter.sync_user_balances` call
- Email multiplier updates on `EmailVerification.verify_code` success

**Coin Flip Game on Solana** (Phase 6 — complete):
- Game logic: `lib/blockster_v2/coin_flip_game.ex` (replaces `bux_booster_onchain.ex` for new games)
- New Mnesia table `coin_flip_games` (19 fields, vault_type instead of token_address, Solana tx sigs instead of EVM hashes)
- Bet settler: `lib/blockster_v2/coin_flip_bet_settler.ex` (GlobalSingleton, checks every minute)
- JS hook: `assets/js/coin_flip_solana.js` (Wallet Standard API, optimistic flow)
- **Payout/max bet math**: MUST use `trunc`/`div` (not `Float.round`) to match on-chain integer truncation. See `calculate_payout` and `calculate_max_bet`.
- **Nonce management**: `get_or_init_game` computes nonce from Mnesia (like old `BuxBoosterOnchain`), NOT from on-chain state. This makes init instant (<1ms). On-chain fallback only on NonceMismatch (Mnesia out of sync). Settlement is fire-and-forget (`spawn`) — next bet doesn't wait for previous settlement.
- **Settlement status UI**: Result screen shows pending/settled/failed indicator. Settled links to Solscan tx. Failed shows auto-retry info.
- **Reclaim expired bets**: Global banner on `/play` checks every 30s for placed bets older than `bet_timeout` (5 min). User signs `reclaim_expired` tx to recover funds. Handler: `"reclaim_stuck_bet"` event in `coin_flip_live.ex`.
- **Settler tx confirmation**: All txs use priority fees (`computeBudgetIxs`) and `maxRetries:5` on `sendRawTransaction`. Confirmation uses `getSignatureStatuses` polling (like ethers `tx.wait()`), NOT websocket subscriptions. See `rpc-client.ts:waitForConfirmation`. Client-side JS (`coin_flip_solana.js`) uses the same polling pattern.
- LiveView: `lib/blockster_v2_web/live/coin_flip_live.ex` (SOL + BUX tokens, no ROGUE)
- Route `/play` → `CoinFlipLive` (was `BuxBoosterLive`)
- Old EVM game files preserved but no longer routed (BuxBoosterLive, bux_booster_onchain.ex)

**Bankroll Program & LP System** (Phase 7 — complete):
- Settler bankroll service: `contracts/blockster-settler/src/services/bankroll-service.ts` (PDA derivation, VaultState deserialization, tx builders)
- Init script: `contracts/blockster-settler/scripts/init-bankroll.ts` (4-step init, game registration, liquidity seeding)
- Settler pool routes: GET /pool-stats, /game-config/:gameId, /lp-balance/:wallet/:vaultType, POST /build-deposit-sol, /build-withdraw-sol, /build-deposit-bux, /build-withdraw-bux
- BuxMinter: `get_lp_balance/2`, `build_deposit_tx/3`, `build_withdraw_tx/3`, fixed `get_house_balance/1`
- New Mnesia table `user_lp_balances` `{user_id, wallet_address, updated_at, bsol_balance, bbux_balance}`
- EngagementTracker: `get_user_lp_balances/1`, `get_user_bsol_balance/1`, `get_user_bbux_balance/1`, `update_user_bsol_balance/3`, `update_user_bbux_balance/3`
- Pool Index: `lib/blockster_v2_web/live/pool_index_live.ex` (two vault cards with stats, links to detail pages)
- Pool Detail: `lib/blockster_v2_web/live/pool_detail_live.ex` (two-column layout: order form + chart/stats/activity)
- Pool Components: `lib/blockster_v2_web/components/pool_components.ex` (pool_card, lp_price_chart, pool_stats_grid, stat_card, activity_table)
- Pool JS hook: `assets/js/hooks/pool_hook.js` (Wallet Standard signing for deposit/withdraw)
- Price Chart hook: `assets/js/hooks/price_chart.js` (TradingView lightweight-charts, area series)
- LP Price History: `lib/blockster_v2/lp_price_history.ex` — Mnesia-backed price snapshots with per-timeframe downsampling (1H=60s, 24H=5m, 7D=30m, 30D=2h, All=1d), PubSub broadcast on `"pool_chart:#{vault_type}"`, chart stats (high/low/change_pct). Skips downsampling when <500 points.
- LP Price Tracker: `lib/blockster_v2/lp_price_tracker.ex` — GlobalSingleton GenServer, polls settler every 60s, subscribes to `"pool:settlements"` for real-time chart updates on bet settlement, daily Mnesia prune
- New Mnesia table `lp_price_history` `{id={vault_type,timestamp}, vault_type, timestamp, lp_price}` ordered_set, indexed by vault_type
- Real-time chart flow: bet settles → `CoinFlipGame` broadcasts `{:bet_settled, vault_type}` → LpPriceTracker fetches fresh LP price → records with `force: true` → PubSub → PoolDetailLive pushes `chart_update` to JS
- Routes: `/pool` → `PoolIndexLive`, `/pool/sol` → `PoolDetailLive`, `/pool/bux` → `PoolDetailLive`
- LP token display names: SOL-LP (was bSOL), BUX-LP (was bBUX)
- Old `pool_live.ex` deprecated (no longer routed)
- Coin Flip house balance links to `/pool`

**Airdrop Migration** (Phase 8 — complete):
- Settler airdrop service: `contracts/blockster-settler/src/services/airdrop-service.ts` (PDA derivation, state deserialization, tx builders)
- Init script: `contracts/blockster-settler/scripts/init-airdrop.ts`
- Settler airdrop routes: POST /airdrop-start-round, /airdrop-fund-prizes, /airdrop-close, /airdrop-draw-winners, /airdrop-build-deposit, /airdrop-build-claim. GET /airdrop-vault-round-id, /airdrop-round-info/:roundId, /airdrop-state
- Airdrop.ex rewritten: keccak256→SHA256 (`sha256_combined`, `derive_position`), slot_at_close instead of block_hash, wallet_address instead of smart_wallet
- Airdrop.Settler simplified: close→slot from settler, draw→on-chain via settler, no per-winner prize registration
- BuxMinter: removed `airdrop_deposit`, `airdrop_claim`, `airdrop_set_prize`, `airdrop_set_winner`, `airdrop_sync_prize_pool_round`. Added `airdrop_build_deposit/4`, `airdrop_build_claim/3`
- AirdropLive: WalletAuthEvents, wallet signing for deposit+claim, Solscan links, removed EVM/Arbitrum references
- JS hook: `assets/js/hooks/airdrop_solana.js` (Wallet Standard signing, registered in app.js)

**Shop & Referral Updates** (Phase 9 — complete):
- Checkout: ROGUE payment removed (slider, rate lock, discount, event handlers all no-op/zero). BUX + Helio only.
- Referrals: `normalize_wallet/1` handles EVM (downcase) and Solana (case-sensitive) addresses
- ReferralRewardPoller: EVM polling disabled (GenServer skeleton preserved for future Solana events)
- Orders: ROGUE affiliate payout returns `{:error, :deprecated}`, `get_current_rogue_rate` returns zero

**UI Overhaul** (Phase 10 — complete):
- Header/footer: Removed ROGUE references, replaced Roguescan with Solscan links
- Profile: ROGUE tab replaced with SOL balance, External Wallet tab removed, multiplier display updated (SOL + email)
- Hub ordering: sorted by post count descending
- Ad Banner system: migration, schema (`ads/banner.ex`), context (`ads.ex`), 19 tests. Placements: sidebar + mobile

**EVM Cleanup & Deprecation** (Phase 11 — complete):
- Deprecated JS hooks: ConnectWalletHook, WalletTransferHook, BalanceFetcherHook, BuxBoosterOnchain, RoguePaymentHook, AirdropDepositHook, AirdropApproveHook (all annotated with @deprecated)
- Deprecated EVM Thirdweb init block in `home_hooks.js` (rogueChain, thirdwebClient globals)
- Deprecated Elixir modules: `connected_wallet.ex`, `wallet_transfer.ex`, `wallets.ex`, `thirdweb_login_live.ex`, `bux_booster_onchain.ex` (all with @deprecated moduledoc)
- Deprecated config: `bux_minter_url`, `bux_minter_secret`, `thirdweb_client_id` in runtime.exs
- Deprecated EVM content: how_it_works.html.heex Rogue Chain/Arbitrum sections marked for update
- Renamed `contracts/bux-booster-game/` to `contracts/legacy-evm/`
- No files deleted (conservative approach — all still-referenced code kept with deprecation notes)
- `ROGUE_RPC_URL`, `BUNDLER_URL`, `PAYMASTER_URL` already absent from runtime.exs (clean)

**Testing & Documentation** (Phase 12 — complete):
- Phase 12A: All tests updated throughout Phases 1-11 (tests written per phase, not deferred)
- Phase 12B: Documentation updated — `claude.md`, `docs/addresses.md`, `docs/solana_migration_plan.md`
- Phase 12C: Final integration test pass — 2126 total tests, 0 new failures

## Services
| Service | URL |
|---------|-----|
| Main App | `https://blockster.com` |
| BUX Minter | `https://bux-minter.fly.dev` |
| Bundler | `https://rogue-bundler-mainnet.fly.dev` |

## Telegram
| Resource | URL |
|----------|-----|
| Blockster Group | `https://t.me/+7bIzOyrYBEc3OTdh` |
| Blockster V2 Bot | `https://t.me/BlocksterV2Bot` |

**IMPORTANT**: `t.me/blockster` is NOT ours. Never use it anywhere.

---

## Mnesia Tables

### Active Tables
| Table | Purpose | Key |
|-------|---------|-----|
| `user_solana_balances` | SOL + BUX balances (source of truth for display) | `user_id` |
| `user_post_engagement` | Reading metrics | `{user_id, post_id}` |
| `user_post_rewards` | BUX rewards earned | `{user_id, post_id}` |
| `unified_multipliers_v2` | Reward multipliers (SOL + email) | `user_id` |
| `coin_flip_games` | Solana coin flip game sessions | `game_id` |
| `user_lp_balances` | LP token balances (bSOL + bBUX) | `user_id` |
| `x_connections` | X OAuth tokens | `user_id` |
| `share_campaigns` | Retweet campaigns | `post_id` |
| `share_rewards` | Share participation | `{user_id, campaign_id}` |
| `token_prices` | CoinGecko price cache | `token_id` |

### Legacy Tables (not read, kept for schema compat)
| Table | Replaced By |
|-------|-------------|
| `user_bux_balances` | `user_solana_balances` |
| `user_rogue_balances` | N/A (ROGUE removed) |
| `bux_booster_onchain_games` | `coin_flip_games` |
| `unified_multipliers` | `unified_multipliers_v2` |

**Directories**: Production: `/data/mnesia/blockster`, Dev: `priv/mnesia/{node_name}`

---

## Engagement Tracking

Users earn BUX for reading: `bux = (engagement_score / 10) * base_reward * multiplier`
- Time Score (0-6), Depth Score (0-3), Base Score (1)
- Bot detection: <3 scroll events, >5000 px/s scroll speed, >300 wpm reading

---

## Bot Reader System

1000 bot accounts simulate reading with real on-chain BUX minting. See [docs/bot_reader_system.md](docs/bot_reader_system.md) for full docs.

- **Feature flag**: `BOT_SYSTEM_ENABLED=true` env var
- **Fully automatic**: auto-creates bots, seeds pools, schedules reads on deploy
- **Files**: `lib/blockster_v2/bot_system/` (coordinator, setup, simulator, deploy, dev_setup)
- **Config**: `config :blockster_v2, :bot_system` in `runtime.exs`
- **Key behavior**: 60-85% of 300 active bots read each post, ~55% in first hour, 500ms mint interval, 5 BUX minimum reward, 50% pool cap
- **Pools**: Content automation auto-deposits on publish; coordinator auto-seeds 5000 BUX on posts with < 100 during backfill

---

## Security

### Provably Fair Server Seed
**NEVER display server seed for unsettled games.** Only reveal AFTER bet is settled on-chain. Always verify `status == :settled` before showing.

### Fingerprint Anti-Sybil
Fingerprint verification is **non-blocking** — if FingerprintJS fails (ad blockers, Safari, Brave, privacy extensions), signup proceeds without device verification. When fingerprint data is available, anti-sybil checks apply as normal. Dev/test environments skip the FingerprintJS HTTP call entirely. The `SKIP_FINGERPRINT_CHECK` env var skips the server-side HTTP verification to FingerprintJS API but fingerprint DB operations (conflict detection, device tracking) still run when fingerprint data is present.

---

## Common Routes
- Hub: `/hub/:slug`
- Product: `/shop/:slug`
- Post: `/:slug`
- Member: `/member/:slug`
- Coin Flip: `/play`
- Pool Index: `/pool`
- Pool Detail: `/pool/sol`, `/pool/bux`
- Admin Stats: `/admin/stats`, `/admin/stats/players`, `/admin/stats/players/:address`

---

## Admin Operations

### Query User by Wallet
```bash
flyctl ssh console --app blockster-v2 -C "bin/blockster_v2 rpc 'alias BlocksterV2.{Repo, Accounts.User}; import Ecto.Query; Repo.all(from u in User, where: ilike(u.wallet_address, \"%PARTIAL%\") or ilike(u.smart_wallet_address, \"%PARTIAL%\"), select: {u.id, u.wallet_address, u.smart_wallet_address}) |> IO.inspect()'"
```

### Mint BUX
```bash
# Use smart_wallet_address, not wallet_address. Reward types: :read, :x_share, :video_watch, :signup, :phone_verified
flyctl ssh console --app blockster-v2 -C "bin/blockster_v2 rpc 'BlocksterV2.BuxMinter.mint_bux(\"SMART_WALLET\", 1000, USER_ID, nil, :signup) |> IO.inspect()'"
```

### Clear Phone Verification
```bash
flyctl ssh console --app blockster-v2 -C "bin/blockster_v2 rpc '
alias BlocksterV2.{Repo, Accounts.User, Accounts.PhoneVerification}; import Ecto.Query; user_id = 89
Repo.delete_all(from p in PhoneVerification, where: p.user_id == ^user_id)
Repo.update_all(from(u in User, where: u.id == ^user_id), set: [phone_verified: false, geo_multiplier: Decimal.new(\"0.5\"), geo_tier: \"unverified\"])
'"
```

---

## Performance

- Route images through `ImageKit` (`w500_h500`, `w800_h800`, etc.)
- Above-fold: `fetchpriority="high" loading="eager"`, below-fold: `loading="lazy"`
- Swiper bundled via npm (not CDN)
- Preconnect: `ik.imagekit.io`, `fonts.googleapis.com`, `fonts.gstatic.com`

---

*For detailed historical notes, bug fix narratives, and contract upgrade transaction hashes, see [docs/session_learnings.md](docs/session_learnings.md).*
