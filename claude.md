# Blockster V2

Phoenix LiveView application with Elixir backend, serving a web3 content platform with a shop, hubs, events, and token-based engagement system.

> **Claude Instructions**: For detailed historical bug fixes and implementation notes, see [docs/session_learnings.md](docs/session_learnings.md). Keep this file concise (~350 lines). Only add new learnings here if they represent stable patterns or critical rules. Move detailed narratives to session_learnings.md.
>
> **CRITICAL GIT RULES**:
> - NEVER add, commit, or push changes to git without EXPLICIT user instructions
> - NEVER change git branches without EXPLICIT user instructions
>
> **CRITICAL SECURITY RULES**:
> - NEVER read or access any `.env` file - these contain private keys and secrets
> - NEVER use public RPC endpoints for scripts/server code - use project-configured RPC URLs
>
> **CRITICAL DEPENDENCY RULES**:
> - NEVER update Phoenix, LiveView, Ecto, or other core dependencies without EXPLICIT user permission
>
> **CRITICAL AI MODEL RULES**:
> - NEVER downgrade the AI Manager model to Sonnet or Haiku — always use the latest Opus model
> - The AI Manager (`ai_manager.ex`) must always use Claude Opus for API calls
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
> **DEVELOPMENT WORKFLOW**:
> - DO NOT restart nodes after code fixes - Elixir hot reloads. Only restart for supervision tree/config changes
> - NEVER use the Write tool to rewrite entire documentation files - use Edit for targeted changes
> - NEVER deploy without explicit user instructions

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
- `contracts/bux-booster-game/` - Solidity contracts

## Running Locally
```bash
# Multi-node (recommended) - libcluster auto-discovers in dev
elixir --sname node1 -S mix phx.server          # Terminal 1
PORT=4001 elixir --sname node2 -S mix phx.server # Terminal 2

# Single node
elixir --sname blockster -S mix phx.server
```

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
| High Rollers NFT (Arbitrum) | `0x7176d2edd83aD037bd94b7eE717bd9F661F560DD` |

### BUX Minter Service
Deployed at `https://bux-minter.fly.dev` (Node.js + Express + ethers.js)

Key endpoints: `POST /mint`, `GET /balance/:address`, `GET /aggregated-balances/:address`, `POST /submit-commitment`, `POST /settle-bet`, `GET /game-token-config/:token`

Minting is a common operation - don't add unnecessary validation.

---

## User Registration & Account Abstraction

Registration is **email only**. Thirdweb creates an ERC-4337 smart wallet automatically. No MetaMask required.
- `wallet_address` = EOA wallet (login)
- `smart_wallet_address` = ERC-4337 smart wallet (receives tokens)

---

## Rogue Chain Network
| Property | Value |
|----------|-------|
| Chain ID | `560013` |
| RPC URL | `https://rpc.roguechain.io/rpc` |
| Explorer | `https://roguescan.io` |
| Bundler | `https://rogue-bundler-mainnet.fly.dev` |

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
| Table | Purpose | Key |
|-------|---------|-----|
| `user_bux_balances` | Per-token balances | `user_id` |
| `user_post_engagement` | Reading metrics | `{user_id, post_id}` |
| `user_post_rewards` | BUX rewards earned | `{user_id, post_id}` |
| `user_multipliers` | Reward multipliers | `user_id` |
| `x_connections` | X OAuth tokens | `user_id` |
| `share_campaigns` | Retweet campaigns | `post_id` |
| `share_rewards` | Share participation | `{user_id, campaign_id}` |
| `token_prices` | CoinGecko price cache | `token_id` |
| `bux_booster_onchain_games` | Game sessions (22 fields) | `game_id` |
| `bux_booster_players` | Player index | `wallet_address` |

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
Bypass: Dev mode auto-skips. Production: `flyctl secrets set SKIP_FINGERPRINT_CHECK=true --app blockster-v2`

---

## Common Routes
- Hub: `/hub/:slug`
- Product: `/shop/:slug`
- Post: `/:slug`
- Member: `/member/:slug`
- BUX Booster: `/play`
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
