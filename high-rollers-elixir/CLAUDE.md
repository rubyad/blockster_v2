# High Rollers Elixir

Phoenix LiveView application for the High Rollers NFT revenue sharing system.

## CRITICAL RULES

### NEVER Delete Mnesia Data
- **NEVER** delete Mnesia directories (`priv/mnesia/hr1`, `priv/mnesia/hr2`, etc.) without EXPLICIT instructions from the user
- Even when instructed, you MUST confirm TWICE with the user before deleting any Mnesia data
- Mnesia contains persistent NFT data, earnings, reward events, and user data that cannot be easily recovered
- If tables are missing or corrupted, the solution is to resync from the blockchain, NOT delete data

### NEVER Read .env Files
- **NEVER** read, open, or access any `.env` file - these contain private keys and secrets
- Environment variables are configured via `.env` for local dev and Fly secrets for production
- If you need to know what env vars a service uses, check the config files, NOT the `.env` file

### NEVER Start Backfill Without Permission
- **NEVER** trigger any backfill function (`ArbitrumEventPoller.backfill/2`, `RogueRewardPoller.backfill/2`, etc.) without EXPLICIT instructions from the user
- Backfills can take a long time and consume RPC quota
- Always explain what the backfill will do and wait for explicit approval

### NEVER Deploy to Production Without Permission
- **NEVER** deploy to production (Fly.io or any other environment) without EXPLICIT instructions from the user
- Always confirm what will be deployed and wait for explicit approval
- A previous deploy instruction does NOT carry over to new changes

## Tech Stack
- **Backend**: Elixir/Phoenix 1.7+ with LiveView
- **Database**: Mnesia for all persistent data (NFTs, earnings, events)
- **Frontend**: TailwindCSS, DaisyUI
- **Blockchain**: Arbitrum (NFT contract), Rogue Chain (rewards)

## Running Locally

```bash
# Terminal 1 - Main node
elixir --sname hr1 -S mix phx.server

# Terminal 2 - Second node (optional)
PORT=4001 elixir --sname hr2 -S mix phx.server
```

## Key Directories
- `lib/high_rollers/` - Core business logic
- `lib/high_rollers_web/live/` - LiveView modules
- `assets/` - JavaScript, CSS, static files
- `priv/mnesia/` - Mnesia data directories (NEVER DELETE)

## Mnesia Tables
| Table | Purpose |
|-------|---------|
| `hr_nfts` | All 2,341 NFTs with earnings data |
| `hr_reward_events` | RewardReceived events from blockchain |
| `hr_reward_withdrawals` | Withdrawal history |
| `hr_users` | User preferences |
| `hr_affiliate_earnings` | Affiliate commission tracking |
| `hr_pending_mints` | In-progress mint requests |
| `hr_admin_ops` | Admin operation log |
| `hr_stats` | Cached global statistics |
| `hr_poller_state` | Last processed block for each poller |

## Data Recovery

If Mnesia tables are empty, resync from blockchain:

```elixir
# Reset poller blocks to trigger full backfill
:mnesia.dirty_write({:hr_poller_state, :arbitrum, 289_000_000})
:mnesia.dirty_write({:hr_poller_state, :rogue, 108_000_000})

# Then restart the server - pollers will backfill all data
```

## Global GenServers
These run as singletons across the cluster using GlobalSingleton:
- `MnesiaInitializer` - Schema and table setup
- `AdminTxQueue` - Serialized blockchain transactions
- `ArbitrumEventPoller` - NFTMinted, Transfer events
- `RogueRewardPoller` - RewardReceived, RewardClaimed events
- `EarningsSyncer` - Periodic earnings updates
- `OwnershipReconciler` - NFT ownership verification
