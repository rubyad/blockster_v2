# Bot Reader System

1000 bot accounts simulate natural reading behavior, earning BUX through the existing engagement pipeline with real on-chain minting visible on roguescan. Posts get a burst of activity on publish that decays over 7 days.

## How It Works

### On Deploy (automatic)

When `BOT_SYSTEM_ENABLED=true`, the coordinator starts via the supervision tree and handles everything:

1. **Boot** — BotCoordinator starts as a GlobalSingleton (one instance across the cluster)
2. **Init (T+30s)** — Queries DB for bot users. If zero found (first deploy), auto-creates 1000 via `BotSetup.create_all_bots(1000)`
3. **Activate** — Shuffles all bot IDs, picks 300 as the active pool, builds wallet cache, subscribes to `"post:published"` PubSub
4. **Backfill** — Fetches last 100 published posts within 7 days. Auto-seeds 5000 BUX on any post with pool < 100. Schedules bot reads on the decay curve for remaining time buckets
5. **Daily rotation** — At 3 AM UTC, shuffles which 300 bots are active

No manual scripts needed. Fully idempotent on restart.

### When a Post Is Published

The existing `Blog.publish_post/1` broadcasts `{:post_published, post}` on PubSub. The coordinator:

1. **Tracks the post** — reads pool balance from Mnesia, skips if < 100 BUX
2. **Generates schedule** — 60-85% of 300 active bots (180-255) distributed across 8 time buckets:

| Window | % of Readers | ~Bots | Description |
|--------|-------------|-------|-------------|
| 0-5 min | 15% | 27-38 | Instant readers |
| 5-15 min | 15% | 27-38 | Early birds |
| 15-30 min | 13% | 23-33 | First wave |
| 30min-1hr | 12% | 22-30 | Catching up |
| 1-4 hr | 12% | 22-30 | Steady flow |
| 4-12 hr | 10% | 18-25 | Afternoon |
| 12-48 hr | 10% | 18-25 | Next day |
| 48hr-7 days | 13% | 23-33 | Long tail |

3. **Schedules messages** — Each bot gets a `Process.send_after` with a random delay within its bucket

### Bot Reading Session (3 messages)

**Message 1: `bot_discover_post`** — Bot "visits" the post
- Checks: pool >= 100 BUX? Cap not reached (bots < 50% of deposited)?
- Calls `EngagementTracker.record_visit` (same as real users)
- Generates score target (10% skimmers, 20% partial, 40% good, 30% thorough)
- Schedules mid-read and completion based on calculated read time (min 10s)

**Message 2: `bot_reading_update`** — Mid-read at 50%
- Sends partial scroll depth and time to `EngagementTracker.update_engagement`

**Message 3: `bot_complete_read`** — Finish reading
- Sends final metrics to `EngagementTracker.record_read` → gets engagement score (0-10)
- Calculates BUX: `(score/10) * base_reward * multiplier`, floored to minimum 5 BUX
- Records reward, enqueues mint job

### Video Bonus (35% chance)

If the post has a video, 35% of bots that read it also "watch" 30-100% of the video. Earns additional BUX based on `video_bux_per_minute * watch_minutes * multiplier`, also floored to 5 BUX minimum.

### Mint Queue

Rate-limited FIFO queue processing one mint every 500ms. Each mint calls `BuxMinter.mint_bux/5` which hits the BUX minter service for real on-chain minting, then deducts from the post's pool.

### Pool Consumption Cap

Bots stop reading a post once they've consumed 50% of the `pool_deposited` amount. The other 50% is reserved for real users.

## Files

| File | Purpose |
|------|---------|
| `lib/blockster_v2/bot_system/bot_coordinator.ex` | GlobalSingleton GenServer — orchestrates everything |
| `lib/blockster_v2/bot_system/bot_setup.ex` | Creates 1000 bot users with wallets + multiplier tiers |
| `lib/blockster_v2/bot_system/engagement_simulator.ex` | Pure functions: decay scheduling, metric generation |
| `lib/blockster_v2/bot_system/deploy.ex` | Manual status check / forced re-init (not required) |
| `lib/blockster_v2/bot_system/dev_setup.ex` | Local dev helpers (seed pools, broadcast, send reads) |
| `priv/repo/migrations/20260223200001_add_is_bot_to_users.exs` | Adds `is_bot` boolean to users table |
| `test/blockster_v2/bot_system/` | 57 tests across 3 test files |

## Configuration

In `config/runtime.exs`:

```elixir
bot_system: [
  enabled: System.get_env("BOT_SYSTEM_ENABLED", "false") == "true",
  active_bot_count: String.to_integer(System.get_env("BOT_ACTIVE_COUNT", "300")),
  pool_cap_percentage: 0.5,     # Bots consume max 50% of pool
  mint_interval_ms: 500,        # One mint every 500ms
  backfill_days: 7,             # Backfill posts published within 7 days
  min_pool_balance: 100,        # Skip posts with pool < 100 BUX
  min_bot_reward: 5.0,          # Floor: bots earn at least 5 BUX per read
  default_pool_size: 5000,      # Auto-seed amount for posts without pools
  video_watch_percentage: 0.35  # 35% of readers also watch video
]
```

**Environment variables** (set on Fly.io):
- `BOT_SYSTEM_ENABLED=true` — master switch
- `BOT_ACTIVE_COUNT=300` — how many of 1000 bots are active at once

## Bot Multiplier Tiers

Bots have varied multipliers for natural earning diversity:

| Tier | % of Bots | Phone | Geo Tier | Overall Multiplier |
|------|-----------|-------|----------|-------------------|
| Casual | 40% | No | unverified | ~0.5x |
| Engaged | 35% | Yes | basic | ~1-4x |
| Power | 20% | Yes | standard | ~4-15x |
| Whale | 5% | Yes | premium | ~15-50x |

The 5 BUX minimum floor ensures even casual bots earn meaningful amounts.

## Where Pools Come From

Posts need BUX pools for bots (and real users) to earn from:

1. **Content Automation pipeline** — auto-deposits `reward * 500` (min 1000 BUX) when it publishes a post
2. **Coordinator backfill** — auto-seeds `default_pool_size` (5000 BUX) on recent posts with pool < 100 during initialization
3. **Admin UI** — manual deposit via post editor or posts admin page

## Restart Recovery

- **Bot users**: In Postgres — survive any restart
- **Multipliers**: In Mnesia (disc_copies) — survive restart
- **Active sessions**: Lost on restart — acceptable. Backfill picks up unread posts
- **Mint queue**: Lost — some rewards may not complete. Acceptable at bot scale
- **Post tracker**: Reconstructed during backfill

## Manual Operations

Status check (optional, not required):
```bash
flyctl ssh console --app blockster-v2 -C "bin/blockster_v2 rpc 'BlocksterV2.BotSystem.Deploy.status()'"
```

Force re-initialization:
```bash
flyctl ssh console --app blockster-v2 -C "bin/blockster_v2 rpc 'BlocksterV2.BotSystem.Deploy.initialize()'"
```
