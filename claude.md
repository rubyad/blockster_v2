# Blockster V2

Phoenix LiveView application with Elixir backend, serving a web3 content platform with a shop, hubs, events, and token-based engagement system.

> **Claude Instructions**: After every conversation compaction/summarization, update this file with any new learnings, patterns, contract addresses, configuration changes, or important decisions made during the session. This file is persistent project memory - keep it current.
>
> **How to detect compaction**: If your first message contains "This session is being continued from a previous conversation" or similar summary text, that means compaction occurred. IMMEDIATELY update this file with learnings from the summary before doing anything else.
>
> **CRITICAL GIT RULE**: NEVER change git branches (checkout, switch, merge) without EXPLICIT user instructions to do so. Always stay on the current branch unless the user specifically tells you to change branches.

## Tech Stack
- **Backend**: Elixir/Phoenix 1.7+ with LiveView
- **Database**: PostgreSQL with Ecto
- **Distributed State**: Mnesia for real-time token balances, engagement tracking, X connections
- **Frontend**: TailwindCSS, TipTap editor, Thirdweb for wallet integration
- **Blockchain**: Rogue Chain **Mainnet** (Chain ID: 560013) - used for both local dev and production
- **Deployment**: Fly.io (app: blockster-v2)
- **Account Abstraction**: ERC-4337 with gasless smart wallets via Paymaster

## Key Directories
- `lib/blockster_v2/` - Core business logic (Shop, Blog, EngagementTracker, Social, etc.)
- `lib/blockster_v2_web/live/` - LiveView modules
- `assets/js/` - JavaScript hooks for LiveView (TipTap, image uploads, engagement tracking, etc.)
- `priv/repo/migrations/` - Ecto migrations
- `docs/` - Feature documentation (engagement tracking, rewards system, X integration, etc.)

## Running Locally

### Multi-node with Mnesia Persistence (Recommended)

**Cluster Discovery**: Uses **libcluster** (dev only) for automatic node discovery and connection. Production uses DNSCluster on Fly.io.

```bash
# Terminal 1
elixir --sname node1 -S mix phx.server

# Terminal 2
PORT=4001 elixir --sname node2 -S mix phx.server
```

Nodes will automatically discover and connect to each other via libcluster's Epmd strategy. Node2 will join node1's cluster and sync all Mnesia tables.

**Important Notes:**
- If nodes started independently before, delete `priv/mnesia/node2` to allow clean cluster join
- libcluster is configured only for dev environment (see `config/dev.exs`)
- Production continues to use DNSCluster (no changes to prod behavior)
- Node discovery happens before Mnesia initialization in supervision tree

### Single Node
```bash
elixir --sname blockster -S mix phx.server
```

### RAM-only (no persistence)
```bash
mix phx.server
```

## Deployment

**IMPORTANT: Never deploy to production without explicit user instructions to do so.**

- A previous "git push and fly deploy" instruction does NOT carry over to new changes
- After making additional edits, ALWAYS ask for explicit confirmation before deploying
- When in doubt, ask: "Should I deploy these changes to production?"

```bash
git push origin <branch> && flyctl deploy --app blockster-v2
```
Migrations run automatically via release commands during deploy.

---

## Development Guidelines

### UI/UX Rules
- **Always add `cursor-pointer`** to all links, buttons, and clickable elements
- Use custom fonts: `font-haas_medium_65`, `font-haas_roman_55` (defined in Tailwind config)
- Style links in content areas: `[&_a]:text-blue-500 [&_a]:no-underline [&_a:hover]:underline`
- **Prefer Tailwind utility classes over arbitrary hex values**: Use `text-black`, `text-gray-500`, `bg-white` instead of `text-[#141414]`, `text-[#6B7280]`, `bg-[#FFFFFF]`. Only use arbitrary values when the exact color is critical to the design.

### Code Principles

#### DRY (Don't Repeat Yourself)
Define constants once and reuse:
```elixir
# In LiveView module
@token_value_usd 0.10

def mount(_, _, socket) do
  {:ok, assign(socket, :token_value_usd, @token_value_usd)}
end
```
Then use `@token_value_usd` in templates instead of hardcoding values.

#### Phoenix LiveView Best Practices
- Use `phx-click`, `phx-change`, `phx-submit` for user interactions
- Use `phx-hook` for JavaScript interop
- Use `phx-update="ignore"` for elements managed by JS (Twitter embeds, TipTap editors)
- Always preload associations with ordered queries for consistent ordering
- Use `assign_async` for expensive operations that shouldn't block mount

##### Async API Calls - CRITICAL PERFORMANCE RULE
**ALWAYS use `start_async` for external API calls to avoid blocking the UI**:
- Blockchain RPC calls (house balance, token balances, contract queries)
- BUX Minter service calls (minting, balance fetching, game transactions)
- Third-party API calls (X/Twitter, webhooks, external services)
- Database queries that take >100ms

**Pattern**:
```elixir
# Mount - set defaults, start async fetch
def mount(_params, _session, socket) do
  socket
  |> assign(data: nil)  # Default value
  |> start_async(:fetch_data, fn -> fetch_data_from_api() end)
end

# Helper - does the actual API call
defp fetch_data_from_api() do
  case ExternalAPI.fetch() do
    {:ok, data} -> data
    {:error, _} -> nil
  end
end

# Handler - updates UI when complete
def handle_async(:fetch_data, {:ok, data}, socket) do
  {:noreply, assign(socket, :data, data)}
end
```

**When to use async**:
- Page mount (don't block initial render)
- User interactions that trigger API calls (token selection, form submissions)
- Background refreshes (balances, stats, game state)

**Benefits**:
- Page loads instantly with default values
- UI remains responsive during API calls
- Better perceived performance
- Prevents timeouts on slow networks

##### LiveView Double Mount
**CRITICAL**: LiveView mounts **twice** on initial page load:
1. **First mount (disconnected)**: Initial HTTP request, `connected?(socket)` returns `false`
2. **Second mount (connected)**: WebSocket connection established, `connected?(socket)` returns `true`

**When to use `connected?(socket)` check**:
- Operations that should happen **only once per page load** (not twice)
- Side effects like API calls, blockchain transactions, creating database records
- Expensive operations that would waste resources if run twice

**Example** (from BuxBoosterLive):
```elixir
def mount(_params, _session, socket) do
  # Only submit commitment to blockchain on connected mount
  {onchain_assigns, error_msg} = if wallet_address != nil and connected?(socket) do
    case BuxBoosterOnchain.get_or_init_game(user_id, wallet_address) do
      {:ok, game_session} -> # ... submit to blockchain
    end
  else
    # Skip on disconnected mount
    {%{onchain_ready: false}, nil}
  end

  {:ok, assign(socket, onchain_assigns)}
end
```

**Common pitfall**: Not using `connected?(socket)` for side effects causes them to execute twice, leading to:
- Duplicate transactions
- Incremented counters by 2 instead of 1
- Wasted API calls
- Race conditions

#### Database Optimization
- **Use ETS/Mnesia for caching** frequently accessed data to reduce PostgreSQL load
- Create named GenServers to manage ETS tables for caching
- Use `Repo.preload` with specific queries, not bare associations
- Batch database operations where possible
- Use indexes on frequently queried columns

#### Mnesia Best Practices
- **Always use dirty operations** (`dirty_read`, `dirty_write`, `dirty_delete`, `dirty_index_read`) instead of transactions for performance
- Dirty operations are faster and sufficient for most use cases in this application
- **For concurrent updates**: When Mnesia updates can come from multiple users simultaneously (e.g., game stats, counters), route all writes through a dedicated GenServer to serialize operations and prevent inconsistency. This makes dirty operations safe.
- **After creating new Mnesia tables in code**: You must restart both node1 and node2 for the tables to be created. The MnesiaInitializer only creates tables on application startup.

**CRITICAL - Modifying Existing Mnesia Tables**:
- **NEVER add fields in the middle of a table definition** - ALWAYS append new fields to the end
- **Production deployment process for table schema changes**:
  1. Add new field(s) to the END of the attributes list in MnesiaInitializer
  2. Create a migration function to transform existing records
  3. Scale down to 1 server in production before deploying
  4. Deploy the change (table will be recreated with new schema)
  5. Run migration function to transform existing records
  6. Scale back up to multiple servers
- **Development**: Delete `priv/mnesia/node1` and `priv/mnesia/node2`, restart nodes
- **Breaking this process will corrupt Mnesia data across the cluster**
- **Alternative**: Create a new table instead of modifying existing one (preferred for non-critical data)

- Example:
  ```elixir
  # GOOD - use dirty operations
  :mnesia.dirty_write({:my_table, key, value})
  :mnesia.dirty_read({:my_table, key})
  :mnesia.dirty_index_read(:my_table, value, :index_field)

  # AVOID - transactions are slower and rarely needed
  :mnesia.transaction(fn -> :mnesia.write({:my_table, key, value}) end)
  ```

#### Caching Pattern with ETS
```elixir
defmodule BlocksterV2.Cache.HubsCache do
  use GenServer

  @table_name :hubs_cache
  @refresh_interval :timer.minutes(5)

  def start_link(_), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  def get(slug) do
    case :ets.lookup(@table_name, slug) do
      [{^slug, hub}] -> {:ok, hub}
      [] -> {:miss, nil}
    end
  end

  def init(_) do
    :ets.new(@table_name, [:set, :public, :named_table, read_concurrency: true])
    schedule_refresh()
    {:ok, %{}}
  end
end
```

### LiveView Hooks
Hooks are defined in `assets/js/` and registered in `assets/js/app.js`:
```javascript
hooks: { TipTapEditor, ProductImageUpload, EngagementTracker, ... }
```

### Product Variants
Products use a checkbox-based system for sizes/colors that auto-generates variant combinations. Sizes stored in `option1`, colors in `option2`.

---

## Token System

### Overview
- **BUX** is the global token
- **Hub tokens** are per-hub (e.g., moonBUX, neoBUX, rogueBUX)
- Token balances tracked in Mnesia via `EngagementTracker`
- Products can have `bux_max_discount` and `hub_token_max_discount` (percentage 0-100)
- 1 token = $0.10 discount (configurable via `@token_value_usd`)

### Token Contracts (Rogue Chain Mainnet)
| Token | Contract Address |
|-------|------------------|
| BUX | `0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8` |
| moonBUX | `0x08F12025c1cFC4813F21c2325b124F6B6b5cfDF5` |
| neoBUX | `0x423656448374003C2cfEaFF88D5F64fb3A76487C` |
| rogueBUX | `0x56d271b1C1DCF597aA3ee454bCCb265d4Dee47b3` |
| flareBUX | `0xd27EcA9bc2401E8CEf92a14F5Ee9847508EDdaC8` |
| nftBUX | `0x9853e3Abea96985d55E9c6963afbAf1B0C9e49ED` |
| nolchaBUX | `0x4cE5C87FAbE273B58cb4Ef913aDEa5eE15AFb642` |
| solBUX | `0x92434779E281468611237d18AdE20A4f7F29DB38` |
| spaceBUX | `0xAcaCa77FbC674728088f41f6d978F0194cf3d55A` |
| tronBUX | `0x98eDb381281FA02b494FEd76f0D9F3AEFb2Db665` |
| tranBUX | `0xcDdE88C8bacB37Fc669fa6DECE92E3d8FE672d96` |
| blocksterBUX | `0x133Faa922052aE42485609E14A1565551323CdbE` |

---

## Account Abstraction (ERC-4337)

**Network**: Rogue Chain Mainnet (Chain ID: 560013) - used for both local and production

### Smart Wallet Infrastructure (Mainnet)
| Component | Address |
|-----------|---------|
| EntryPoint v0.6.0 | `0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789` |
| ManagedAccountFactory | `0xfbbe1193496752e99BA6Ad74cdd641C33b48E0C3` |
| Paymaster | `0x804cA06a85083eF01C9aE94bAE771446c25269a6` |
| RogueAccountExtension | `0xB447e3dBcf25f5C9E2894b9d9f1207c8B13DdFfd` |
| Bundler URL | `https://rogue-bundler-mainnet.fly.dev` |

### How It Works
1. User logs in → Thirdweb SDK creates smart wallet via ManagedAccountFactory
2. Transactions are gasless (Paymaster sponsors gas)
3. Bundler submits UserOperations to EntryPoint
4. Smart wallets use `execute()` and `executeBatch()` via AccountExtension

### Key Points
- **No ROGUE needed**: Users don't need native tokens for gas
- **Paymaster-sponsored**: All gas fees paid by Paymaster (1M ROGUE deposit)
- **CREATE2**: Wallet addresses are deterministic before deployment

### BUX Minter Service
Deployed at `https://bux-minter.fly.dev` - handles blockchain token minting and BUX Booster game transactions.

**Location**: `bux-minter/` directory in this repo
**Deployment**: Fly.io app `bux-minter`
**Tech Stack**: Node.js + Express + ethers.js

**Key Endpoints**:
- `POST /mint` - Mint tokens to a wallet address
- `GET /balance/:address` - Get single token balance
- `GET /aggregated-balances/:address` - Get all token balances in one call (via BalanceAggregator contract)
- `POST /submit-commitment` - Submit commitment hash to BuxBoosterGame contract
- `POST /settle-bet` - Settle a bet with server-calculated results (V3: accepts commitmentHash, serverSeed, results[], won)
- `GET /player-nonce/:address` - Get player's on-chain nonce from contract (for Mnesia sync)
- `GET /player-state/:address` - Get player's full state (nonce + unused commitment)

**Nonce Management** (Updated Dec 2024):
- **Mnesia is the ONLY source of truth** for nonces - contract does NOT validate nonces
- Nonce calculated from Mnesia by finding max nonce from placed/settled bets + 1
- Contract accepts all commitments regardless of nonce value
- No blockchain queries for nonces - purely server-side tracking
- `/player-nonce/:address` endpoint exists but is unused (legacy)

**Deployment**:
```bash
cd bux-minter
flyctl deploy  # Deploys to bux-minter.fly.dev
```

**Minting tokens as rewards is a very common operation - don't add unnecessary validation that would slow it down.**

```elixir
# Mint tokens (common operation - keep it fast)
BuxMinter.mint_bux(wallet_address, amount, user_id, post_id, :read, "moonBUX")

# Get balances
BuxMinter.get_all_balances(wallet_address)
```

---

## Mnesia Tables

All real-time data is stored in Mnesia for fast, distributed access:

| Table | Purpose | Key |
|-------|---------|-----|
| `user_bux_balances` | Per-token balances | `user_id` |
| `user_post_engagement` | Reading metrics | `{user_id, post_id}` |
| `user_post_rewards` | BUX rewards earned | `{user_id, post_id}` |
| `user_multipliers` | Reward multipliers | `user_id` |
| `x_connections` | X OAuth tokens | `user_id` |
| `x_oauth_states` | OAuth flow state | `state` |
| `share_campaigns` | Retweet campaigns | `post_id` |
| `share_rewards` | Share participation | `{user_id, campaign_id}` |
| `post_bux_points` | Post reward pools | `post_id` |

### Mnesia Directory
- **Production**: `/data/mnesia/blockster` (Fly.io persistent volume)
- **Development**: `priv/mnesia/{node_name}`

---

## Engagement Tracking

Users earn BUX for reading articles based on engagement score (1-10):

```
bux_earned = (engagement_score / 10) * base_bux_reward * user_multiplier
```

### Score Components
- **Time Score** (0-6 points): Based on `time_spent / min_read_time` ratio
- **Depth Score** (0-3 points): Based on scroll depth percentage
- **Base Score**: 1 point always awarded

### Bot Detection
- Too few scroll events (< 3)
- Extremely fast average scroll speed (> 5000 px/s)
- Reading faster than 300 wpm

---

## X (Twitter) Integration

### Features
- OAuth 2.0 with PKCE authentication
- Share campaigns for retweet rewards
- X account quality score (1-100) as `x_multiplier`
- Account locking to prevent gaming rewards

### X Score Components
| Component | Max Points |
|-----------|------------|
| Follower Quality | 25 |
| Engagement Rate | 35 |
| Account Age | 10 |
| Activity Level | 15 |
| List Presence | 5 |
| Follower Scale | 10 |

---

## Common Routes
- Hub routes: `/hubs/:slug`
- Product routes: `/shop/:slug` (handle field)
- Post routes: `/:slug` (post slug)
- Member routes: `/members/:id`

---

## Documentation Requirements

### After Building Features
1. Create a detailed documentation file in `docs/` for each major feature
2. Include architecture diagrams, data flows, and API references
3. Document configuration options and environment variables
4. Keep documentation up to date when making changes

### Documentation Structure
- `docs/mnesia_setup.md` - Mnesia configuration and multi-node setup
- `docs/engagement_tracking.md` - Engagement scoring and BUX rewards
- `docs/rewards_system.md` - Multi-token rewards architecture
- `docs/x_integration.md` - X OAuth and share campaigns
- `docs/bux_token.md` - Token contract addresses
- `docs/contract_upgrades.md` - BuxBoosterGame UUPS upgrade process and troubleshooting
- `docs/nonce_system_simplification.md` - Dec 2024 nonce system changes

---

## Security Notes

### CRITICAL: Provably Fair Server Seed Protection

**NEVER display the server seed for any game that has not been settled.** This is a critical security vulnerability that would allow players to predict all future results.

**Rules:**
1. Server seed MUST ONLY be revealed AFTER the bet is settled on-chain
2. Verify modal MUST ONLY show data for settled games (status = `:settled`)
3. NEVER fetch server seed from the current/pending game session
4. Always query Mnesia for settled games: `:mnesia.dirty_read({:bux_booster_onchain_games, game_id})` with `when status == :settled` guard
5. Any UI showing server seed must pass a specific `game_id` and verify it's settled before displaying

**Example of WRONG approach (NEVER do this):**
```elixir
# WRONG - This reveals upcoming game's server seed!
def handle_event("show_fairness_modal", _params, socket) do
  game_id = socket.assigns.onchain_game_id  # Current game
  server_seed = BuxBoosterOnchain.get_game(game_id).server_seed  # DANGER!
end
```

**Correct approach:**
```elixir
# CORRECT - Only shows settled games
def handle_event("show_fairness_modal", %{"game-id" => game_id}, socket) do
  case :mnesia.dirty_read({:bux_booster_onchain_games, game_id}) do
    [record] when elem(record, 7) == :settled ->  # status field check
      # Safe to show server seed
    _ -> {:noreply, socket}  # Reject non-settled games
  end
end
```

### General Security

- **Never read `.env` files** in code or expose environment variables
- Token owner private keys only exist in the BUX Minter service
- X OAuth tokens stored in Mnesia (not encrypted at rest - consider for future)
- PKCE used for OAuth flows

---

## Troubleshooting

### Mnesia Issues
```elixir
# Check if Mnesia is running
:mnesia.system_info(:is_running)

# Check connected nodes
Node.list()
:mnesia.system_info(:running_db_nodes)

# Force sync with other nodes
:mnesia.change_config(:extra_db_nodes, Node.list())
```

### Common Issues
- **Tables not syncing**: Check nodes are connected via `Node.list()`
- **Schema mismatch**: May need to delete and recreate schema on affected node
- **Token minting fails**: Check BUX Minter logs and wallet gas balance

---

## Full-Text Search

PostgreSQL full-text search with weighted ranking:

### Database Setup
- Uses `tsvector` column with weighted fields (A: title, B: excerpt, C: content)
- GIN index for fast lookups
- Prefix matching with `:*` wildcard

### Query Pattern
```elixir
Blog.search_posts_fulltext("moon", limit: 20)
# Transforms to: "moon:*" (matches moonpay, moonlight, etc.)
```

### Ranking
- Title matches get +100 boost
- `ts_rank_cd` for relevance scoring
- Secondary sort by `published_at`

---

## TipTap Editor

Rich text editor for posts and products.

### Key Files
- `assets/js/tiptap_editor.js` - Main editor hook
- `assets/js/tiptap_extensions/` - Custom extensions (tweet, spacer, image)
- `lib/blockster_v2_web/live/post_live/tiptap_renderer.ex` - Server-side HTML rendering

### Content Format
Content is stored as TipTap JSON in PostgreSQL:
```json
{"type": "doc", "content": [...]}
```

### Tweet Embeds
- Stored as `{"type": "tweet", "attrs": {"url": "...", "id": "..."}}`
- Rendered as blockquotes with `class="twitter-tweet"`
- Twitter's `widgets.js` processes them client-side
- Use `phx-hook="TwitterWidgets"` on content container

---

## Rogue Chain Network Info

**IMPORTANT**: Both local development and production use **Rogue Chain Mainnet**.

| Property | Value |
|----------|-------|
| Chain ID | `560013` |
| RPC URL | `https://rpc.roguechain.io/rpc` |
| Explorer | `https://roguescan.io` |
| Currency | ROGUE (18 decimals) |

### Bundler Service
- **Mainnet**: `https://rogue-bundler-mainnet.fly.dev`
- **Testnet** (for testing only): `https://rogue-bundler-testnet.fly.dev`

### ROGUE Token - Native Gas Token

**CRITICAL**: ROGUE is the native gas token of Rogue Chain (like ETH on Ethereum), NOT an ERC-20 token contract.

**Key Differences from BUX and other tokens**:
1. **No Contract Address**: ROGUE doesn't have a token contract address - it's part of the blockchain itself
2. **Balance Checking**: Use `provider.getBalance(address)` instead of ERC-20 `balanceOf()`
3. **Transfer Method**: Can be sent directly with transaction value (`{value: amountWei}`) - no approve/transferFrom needed
4. **Betting**: In BUX Booster, ROGUE bets can include token amount in the transaction value, unlike ERC-20s which require separate approval
5. **Aggregate Calculation**: ROGUE balance should NOT be included in BUX aggregate total (only BUX flavors count)

**Implementation Notes**:
- Display ROGUE balance in token dropdown but keep separate from BUX aggregate
- When fetching balances, use different method for ROGUE vs ERC-20 tokens
- ROGUE betting flow can be optimized (no approval step needed)

---

## Services & External Dependencies

| Service | URL | Purpose |
|---------|-----|---------|
| Main App | `https://blockster-v2.fly.dev` | Phoenix app (production) |
| BUX Minter | `https://bux-minter.fly.dev` | Token minting service |
| Mainnet Bundler | `https://rogue-bundler-mainnet.fly.dev` | ERC-4337 bundler |
| Rogue RPC | `https://rpc.roguechain.io/rpc` | Blockchain RPC |
| Explorer | `https://roguescan.io` | Block explorer |

---

## Performance Optimization

### Image Optimization with ImageKit

All images should be routed through ImageKit (`lib/blockster_v2/imagekit.ex`) for automatic optimization:

```elixir
# Use specific size functions for consistent optimization
ImageKit.w500_h500(url)   # Square thumbnails
ImageKit.w800_h800(url)   # Large product images
ImageKit.w600_h800(url)   # Portrait cards
ImageKit.w128_h128(url)   # Small thumbnails
```

**Default transforms applied automatically:**
- `quality=90` - Good balance of quality vs file size
- `format=auto` - Serves WebP where browser supports it

### Image Loading Best Practices

```html
<!-- Above-fold / LCP images: eager load with high priority -->
<img src={ImageKit.w600_h800(url)} fetchpriority="high" loading="eager" />

<!-- Below-fold images: lazy load -->
<img src={ImageKit.w500_h500(url)} loading="lazy" />

<!-- Product carousels: first image eager, rest lazy -->
<img fetchpriority={if idx == 0, do: "high", else: "low"}
     loading={if idx == 0, do: "eager", else: "lazy"} />
```

### Static Asset Caching

Cache headers configured in `endpoint.ex`:
- **`/assets/*`** (JS/CSS with digest): 1 year, immutable
- **Other static files**: 1 hour with must-revalidate

### Third-Party Dependencies

**Prefer self-hosting over CDN for critical dependencies:**
- Swiper is bundled via npm in `app.js` (not CDN)
- Eliminates external DNS lookup and connection overhead
- Bundle is gzipped and cached with app assets

**For non-critical scripts, defer loading:**
```html
<!-- Non-blocking font loading -->
<link href="fonts.googleapis.com/..." rel="stylesheet"
      media="print" onload="this.media='all'" />

<!-- Twitter widgets loaded async -->
<script async src="https://platform.twitter.com/widgets.js"></script>
```

### Resource Hints

Add preconnect for critical third-party origins in `root.html.heex`:
```html
<link rel="preconnect" href="https://ik.imagekit.io" crossorigin />
<link rel="preconnect" href="https://fonts.googleapis.com" />
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
```

### Core Web Vitals Targets

| Metric | Target | Key Factor |
|--------|--------|------------|
| LCP | < 500ms | Image optimization, preloading hero images |
| CLS | 0 | Reserve space for images (aspect-ratio or padding-bottom) |
| TTFB | < 100ms | Server-side caching, database optimization |

### Performance Checklist for New Components

1. **Images**: Route through ImageKit with appropriate size function
2. **Above-fold images**: Add `fetchpriority="high"` and `loading="eager"`
3. **Below-fold images**: Add `loading="lazy"`
4. **New npm packages**: Consider bundling vs CDN trade-offs
5. **Heavy JS**: Use `defer` attribute or dynamic imports
6. **Fonts**: Ensure `font-display: swap` is set

---

## Chrome DevTools MCP Server

Claude can inspect and control your live Chrome browser for debugging Blockster during development.

### Capabilities
- **Console logs**: View errors, warnings, and debug output
- **Network inspection**: Monitor API calls, WebSocket connections, blockchain RPC requests
- **Screenshots**: Capture current page state
- **Performance traces**: Profile slow operations
- **DOM inspection**: Select and analyze elements
- **JavaScript evaluation**: Run code in page context
- **Browser automation**: Click, fill forms, navigate

### Requirements
- Node.js 22+
- Chrome 143+ (Chrome 144+ for automatic session connection)

### Usage
1. Run Phoenix server (both nodes):
   ```bash
   # Terminal 1
   elixir --sname node1 -S mix phx.server

   # Terminal 2
   PORT=4001 elixir --sname node2 -S mix phx.server
   ```
2. Open Blockster in Chrome (`http://localhost:4000`)
3. Ask Claude to debug - it can now see your browser

### Use Cases for Blockster
- Debug Thirdweb wallet connection issues (network tab, console errors)
- Monitor engagement tracking JavaScript events
- Inspect LiveView WebSocket messages
- Profile TipTap editor performance
- Capture UI states for bug reports

---

## Session Learnings

### Number Formatting in Templates
Use `:erlang.float_to_binary/2` to avoid scientific notation in number inputs:
```elixir
value={:erlang.float_to_binary(@tokens_to_redeem / 1, decimals: 2)}
```
This prevents values like `1.1e3` appearing in input fields.

### Product Variants
- Sizes come from `option1` field on variants, colors from `option2`
- No fallback defaults - if a product has no variants, sizes/colors lists are empty
- Size selector section is hidden when `sizes` list is empty
- Color selector section is hidden when `colors` list is empty

### X Share Success State
After a successful retweet, check `@share_reward` to show success UI:
- Replace share button with green "Shared!" badge
- Display actual earned amount from `@share_reward[:bux_rewarded]`
- Located in [post_live/show.html.heex](lib/blockster_v2_web/live/post_live/show.html.heex)

### Tailwind Typography Plugin
- Required for `prose` class to style HTML content (paragraphs, lists, etc.)
- Installed via npm: `@tailwindcss/typography`
- Enabled in app.css: `@plugin "@tailwindcss/typography";`
- Used for product descriptions with `raw(@product.description)`

### Self-Hosted Dependencies
- Swiper is bundled via npm (not CDN) for better performance
- Eliminates external DNS lookup and connection overhead

### Libcluster Configuration (Dev Only)

**Added**: December 2024 to fix multi-node development cluster discovery.

**Problem**: DNSCluster is set to `:ignore` in development, so nodes wouldn't discover each other during startup, causing each node to initialize Mnesia independently.

**Solution**: Added libcluster with Epmd strategy for dev-only automatic cluster discovery.

**Files Changed**:
- [mix.exs](mix.exs:62) - Added `{:libcluster, "~> 3.4", only: :dev}`
- [config/dev.exs](config/dev.exs:94-103) - Configured Epmd topology with hardcoded node names
- [lib/blockster_v2/application.ex](lib/blockster_v2/application.ex:10-23) - Added libcluster to supervision tree only when `Mix.env() == :dev`

**Configuration** (config/dev.exs):
```elixir
config :libcluster,
  topologies: [
    local_epmd: [
      strategy: Cluster.Strategy.Epmd,
      config: [
        hosts: [:"node1@Adams-iMac-Pro", :"node2@Adams-iMac-Pro"]
      ]
    ]
  ]
```

**Production**: Unchanged - continues to use DNSCluster for Fly.io cluster discovery.

**Troubleshooting**: If nodes fail to sync Mnesia after connecting, delete `priv/mnesia/node2` and restart both nodes for a clean join.

### BUX Booster Game Contract
- **Contract Address (Proxy)**: `0x97b6d6A8f2c6AF6e6fb40f8d36d60DF2fFE4f17B`
- **Network**: Rogue Chain Mainnet (560013)
- **Pattern**: UUPS Upgradeable Proxy

### Upgradeable Smart Contract Storage Layout - CRITICAL

**VERY IMPORTANT**: When upgrading UUPS or Transparent proxy contracts, you MUST preserve the exact storage layout:

1. **NEVER change the order of state variables** - Moving a variable breaks storage
2. **NEVER remove state variables** - This shifts all subsequent slots
3. **ONLY add new variables at the END** - After all existing variables
4. **Inline array initialization doesn't work with proxies** - Use `reinitializer(N)` functions instead

Example of what NOT to do:
```solidity
// WRONG - changing order or removing
uint256 public foo;  // slot 0
uint256 public bar;  // slot 1 -> removing this breaks everything below
uint256 public baz;  // slot 2

// RIGHT - only add at end
uint256 public foo;  // slot 0
uint256 public bar;  // slot 1
uint256 public baz;  // slot 2
uint256 public newVar; // slot 3 - safe to add
```

For arrays with inline initialization in proxy contracts:
```solidity
// WRONG - inline init doesn't work in proxy storage
uint8[9] public FLIP_COUNTS = [5, 4, 3, 2, 1, 2, 3, 4, 5];

// RIGHT - declare, then initialize in reinitializer
uint8[9] public FLIP_COUNTS;

function initializeV2() reinitializer(2) public {
    FLIP_COUNTS[0] = 5;
    // ...
}
```

### Account Abstraction Performance Optimizations (Dec 2024)

**Problem**: BUX Booster transactions were taking ~6 seconds due to sequential approve + placeBet UserOperations.

**Solutions Attempted & Results**:

1. **~~Batch Transactions~~** (Abandoned Dec 28, 2024)
   - **Attempted**: Combine approve + placeBet into single UserOp with `sendBatchTransaction()`
   - **Issue**: Batch transactions don't propagate state changes between calls - approve sets allowance but placeBet can't see it in same transaction
   - **Error**: `SafeERC20FailedOperation` - placeBet failed because allowance was still 0
   - **Lesson**: Sequential transactions with receipt waiting are more reliable

2. **Infinite Approval + Caching** (✅ Primary Optimization)
   - Approve MAX_UINT256 once, cache in localStorage
   - **Results**: ~3.5s savings on repeat bets (50-67% improvement)
   - Cache verification: check on-chain allowance >= half of MAX_UINT256 before trusting cache

3. **Sequential Transactions with Receipt Waiting** (✅ Current Approach)
   - Execute approve → wait for confirmation → execute placeBet
   - **Results**: First bet ~4-5s, repeat bets ~2-3s
   - More reliable than batching, slower on first bet but cached approvals make repeats fast

4. **Optimistic UI Updates** (✅ Implemented Dec 28, 2024)
   - Deduct balance immediately in Mnesia when user places bet (before blockchain confirms)
   - Start coin animation immediately
   - Mark bet as `:placed` in Mnesia only after blockchain confirms transaction
   - On settlement, trigger async balance sync from blockchain
   - Use PubSub broadcasts to update all LiveViews when balances change
   - **Impact**: Instant UI feedback, ~2s+ perceived latency reduction
   - **Key Pattern**: Never use `Process.sleep()` after async calls - rely on broadcasts instead

**Performance Metrics**:
- First bet: ~6s → ~4-5s (17-33% improvement)
- Repeat bets: ~6s → ~2-3s (50-67% improvement via caching)
- UserOps per bet: 2 → 1-2 (sequential but cached)

**Key Files Changed**:
- `assets/js/bux_booster_onchain.js` - Sequential approve + placeBet with caching
- `bux-minter/index.js` - Updated ABI to V3 contract signature
- `lib/blockster_v2_web/live/bux_booster_live.ex` - Optimistic balance updates with PubSub
- `lib/blockster_v2_web/live/bux_balance_hook.ex` - Balance update broadcasts

**Documentation**: See [docs/AA_PERFORMANCE_OPTIMIZATIONS.md](docs/AA_PERFORMANCE_OPTIMIZATIONS.md) for full details.

**Critical Lessons for Optimistic UI**:
1. **NEVER use `Process.sleep()` after async operations** - Async means it runs in background, sleeping doesn't wait for it
2. **Use PubSub broadcasts for cross-LiveView updates** - Subscribe once, receive updates from anywhere
3. **Balance sync pattern**:
   - Page load: Trigger `BuxMinter.sync_user_balances_async()` on connected mount
   - Bet placed: Deduct from Mnesia immediately (optimistic)
   - Bet confirmed: Mark as `:placed` in Mnesia
   - Settlement: Trigger async sync, rely on broadcast to update UI
4. **Aggregate balance calculation bug**: When summing token balances, exclude the "aggregate" key itself to avoid double-counting
5. **LiveView hook conflicts**: Don't use `on_mount` for hooks that attach to `handle_info` - manually subscribe and add handlers instead
6. **Balance update flow**:
   ```elixir
   # Settlement completes
   BuxMinter.sync_user_balances_async(user_id, wallet) # Fetches from blockchain
   # When sync completes, BuxMinter broadcasts via BuxBalanceHook
   # All subscribed LiveViews receive {:token_balances_updated, balances}
   # UI updates automatically
   ```

**Cache Management**:
```javascript
// Clear approval cache for testing
Object.keys(localStorage)
  .filter(k => k.startsWith('approval_'))
  .forEach(k => localStorage.removeItem(k));
```

### BUX Booster Smart Contract Upgrades (Dec 2024)

**Contract**: `contracts/bux-booster-game/contracts/BuxBoosterGame.sol`
**Proxy Address**: `0x97b6d6A8f2c6AF6e6fb40f8d36d60DF2fFE4f17B` (Rogue Chain Mainnet)
**Pattern**: UUPS (Universal Upgradeable Proxy Standard)

**CRITICAL Storage Layout Rules**:
1. **NEVER remove state variables** - Shifts all subsequent slots, corrupts data
2. **NEVER reorder state variables** - Same corruption issue
3. **ONLY add new variables at the END** - After all existing variables
4. **KEEP unused variables** - If you stop using a variable, leave it in place with a comment

**Stack Too Deep Errors**:
- **NEVER enable `viaIR: true` to fix stack too deep errors** - This can cause unpredictable issues
- Instead, fix stack too deep by:
  - Moving code to helper functions
  - Caching struct fields to memory variables
  - Splitting large events into multiple smaller events
  - Reducing number of parameters passed to functions

**Upgrade Process**:
```bash
cd contracts/bux-booster-game

# 1. Compile
npx hardhat compile

# 2. Force import proxy (if needed)
npx hardhat run scripts/force-import.js --network rogueMainnet

# 3. Use manual upgrade (recommended for Rogue Chain)
npx hardhat run scripts/upgrade-manual.js --network rogueMainnet

# 4. Call initializer (e.g., initializeV3)
npx hardhat run scripts/init-v3.js --network rogueMainnet

# 5. Verify upgrade
npx hardhat run scripts/verify-upgrade.js --network rogueMainnet
```

**Common Issues**:
- **"Deployment not registered"**: Run `force-import.js` first
- **"execution reverted"**: Use `upgrade-manual.js` with explicit gas limits
- **Gas estimation fails**: Rogue Chain gas estimation issues, use manual upgrade
- **Stack too deep**: Follow rules above, NEVER use viaIR

**V3 Changes (Dec 28, 2024)**:
- **Architecture Change**: Server calculates results and sends to contract (eliminates nonce encoding mismatch between Elixir and Solidity)
- **Bet ID**: commitmentHash used as betId (simpler, more gas efficient)
- **Events Split**: BetSettled into two events (BetSettled + BetDetails) to avoid stack too deep
- **Gas Optimization**: Removed on-chain result generation (~100 lines, ~50k gas savings per bet, ~25% reduction)
- **New Implementation**: `0x9F3141bdcF91f66B3eC7E909032cd0b5A0fdd5eD`
- **Upgrade Transaction**: `0x776f3c1d3f5bc4f9f99c09409fba2bf5ad44380f523dc0968cc6a816d9982a61`
- **InitializeV3 Transaction**: `0x14527bf64278ae9d354b9deef2bdabaf7c5be29fb1ca8abba59df50101cb7982`

**V3 Contract Changes**:
- `settleBet()` now accepts `(commitmentHash, serverSeed, results[], won)` instead of calculating results on-chain
- `BetSettled` event now emits core settlement data (won, results, payout, serverSeed)
- `BetDetails` event emits game context (token, amount, difficulty, predictions, nonce, timestamp)
- Removed functions: `_generateClientSeed()`, `_generateResults()`, `_checkWin()`, string conversion helpers

**Trust Model**: V3 trusts server to calculate results correctly, but maintains provably fair properties:
- Server commits before seeing predictions ✓
- Server reveals seed after settlement ✓
- Players can verify results off-chain ✓
- Contract verifies seed matches commitment ✓

See [docs/contract_upgrades.md](docs/contract_upgrades.md), [docs/nonce_system_simplification.md](docs/nonce_system_simplification.md), and [docs/v3_upgrade_summary.md](docs/v3_upgrade_summary.md) for full details.


### BUX Booster Balance Update After Settlement (Dec 2024)

**Problem**: After winning a bet, the aggregate balance in the header and dropdown updated correctly, but the balance displayed in the BuxBoosterLive coin flip area did not update.

**Root Cause**:
- BuxBoosterLive uses `:balances` assign for the coin flip area balance display
- BuxBalanceHook (attached via `on_mount`) intercepts `:token_balances_updated` broadcasts and updates `:token_balances` assign (used by header)
- The hook was using `{:halt, ...}` which prevented the broadcast from reaching BuxBoosterLive's `handle_info`
- When settlement completed, `BuxMinter.sync_user_balances()` broadcast `:token_balances_updated` but only the header was updated

**Solution**:
1. **Updated BuxBalanceHook** ([bux_balance_hook.ex:47-55](lib/blockster_v2_web/live/bux_balance_hook.ex#L47-L55)) - Modified the `:token_balances_updated` handler to update BOTH `:token_balances` (for header) AND `:balances` (for BuxBoosterLive) when the assign exists:
   ```elixir
   {:token_balances_updated, token_balances}, socket ->
     socket = assign(socket, :token_balances, token_balances)
     socket = if Map.has_key?(socket.assigns, :balances) do
       assign(socket, :balances, token_balances)
     else
       socket
     end
     {:halt, socket}
   ```

2. **Added broadcast to sync** ([bux_minter.ex:230](lib/blockster_v2/bux_minter.ex#L230)) - Added `broadcast_token_balances_update()` call in `sync_user_balances()` to ensure all LiveViews receive balance updates after blockchain sync

3. **Removed duplicate handler** - Removed redundant `handle_info({:token_balances_updated, ...})` from BuxBoosterLive since the hook now handles it

**Result**: All three balance displays now update correctly after bet settlement:
- Top-right aggregate balance (header)
- Token dropdown balances (header)
- Coin flip area balance (BuxBoosterLive)

**Key Lesson**: When using `attach_hook` with `{:halt, ...}`, the hook intercepts the message and prevents it from reaching the LiveView's `handle_info`. If multiple assigns need updating from the same broadcast, update them all in the hook handler.


### Multi-Flip Coin Reveal Bug (Dec 2024)

**Problem**: In multi-flip games (2+ flips), the second and subsequent flips would spin continuously and never reveal the result.

**Root Cause**: The `reveal_result` event (which tells the JavaScript to stop spinning and show the final coin face) was only scheduled once during the initial bet confirmation. When moving to the next flip via `:next_flip`, no new `reveal_result` was scheduled, so the coin would spin forever.

**Solution**: Added `Process.send_after(self(), :reveal_flip_result, 3000)` to the `handle_info(:next_flip, socket)` handler ([bux_booster_live.ex:1600](lib/blockster_v2_web/live/bux_booster_live.ex#L1600)). Now every time we start a new flip, we schedule the reveal event 3 seconds later.

**Affected Difficulty Levels** (all now fixed):
- Win One Mode: 1.32x (2 flips), 1.13x (3 flips), 1.05x (4 flips), 1.02x (5 flips)
- Win All Mode: 3.96x (2 flips), 7.92x (3 flips), 15.84x (4 flips), 31.68x (5 flips)

**Flow for Multi-Flip Games**:
1. Bet confirmed → Schedule `reveal_flip_result` for flip 1
2. Flip 1 completes → Show result → Check win condition
3. If more flips needed → Send `:next_flip` → **Schedule `reveal_flip_result` for flip 2** ✓
4. Flip 2 completes → Show result → Check win condition
5. Continue until all flips done or win/loss determined

### House Balance & Max Bet Display (Dec 2025)

**Feature**: Display house bankroll and maximum bet limits in BUX Booster UI.

**Implementation**:
1. **BUX Minter API**: Added `/game-token-config/:token` endpoint
   - Queries `BuxBoosterGame.tokenConfigs(address)` on-chain
   - Returns: `{enabled: bool, houseBalance: string}`
   - Handles null values gracefully (token not configured)
   - Bug fix: Handles both `"0"` and `"123.45"` string formats (Dec 29, 2025)

2. **Phoenix Client**: Added `BuxMinter.get_house_balance/1`
   - Calls BUX minter API endpoint
   - Returns `{:ok, balance}` or `{:error, reason}`
   - **Async Optimization (Dec 29, 2025)**: All fetches now use `start_async` to avoid blocking UI

3. **Max Bet Calculation**: Client-side formula matching contract logic
   ```elixir
   defp calculate_max_bet(house_balance, difficulty_level, difficulty_options) do
     multiplier_bp = trunc(difficulty.multiplier * 10000)
     base_max_bet = house_balance * 0.001  # 0.1% of house
     max_bet = (base_max_bet * 20000) / multiplier_bp
     trunc(max_bet)  # Round down to integer
   end
   ```

4. **Async Fetching (Dec 29, 2025)**: Non-blocking house balance updates
   - On mount: Defaults to 0.0, fetches async via `start_async(:fetch_house_balance, ...)`
   - On token selection: Triggers async fetch for new token
   - On difficulty change: Triggers async fetch to recalculate max bet
   - On reset game: Triggers async fetch to refresh values
   - Helper: `fetch_house_balance_async/2` returns `{balance, max_bet}` tuple
   - Handler: `handle_async(:fetch_house_balance, ...)` updates assigns when complete

5. **UI Updates**:
   - House balance shown below token selector: "House: 59,704.26 BUX"
   - Max bet displayed on MAX button: "MAX (60)"
   - Updates dynamically when switching tokens or difficulties
   - Page loads instantly without waiting for API call

**Files Changed**:
- [bux-minter/index.js](bux-minter/index.js#L608-645) - Added `/game-token-config/:token` endpoint
- [lib/blockster_v2/bux_minter.ex](lib/blockster_v2/bux_minter.ex#L249-288) - Added `get_house_balance/1` with string parsing fix
- [lib/blockster_v2_web/live/bux_booster_live.ex](lib/blockster_v2_web/live/bux_booster_live.ex) - Async house balance fetch, max bet calculation, UI display

**Max Bet Formula** (Ensures max payout = 0.2% of house):
- Base: 0.1% of house balance (e.g., 59.7 BUX for 59,704 BUX house)
- Scaled by 20000 / multiplier (in basis points)
- Result: Higher multipliers = lower max bet = consistent max payout
- Example: 1.98x allows 60 BUX bet → 119 BUX payout (0.2% of 59,704)

**Why Limit Max Payout (Not Just Profit)?**
- Protects against winning streaks at low multipliers
- 1.02x has 96.9% win rate - player could win 20+ times in a row
- Limiting max bet by balance would let them drain bankroll
- Limiting max payout ensures house never loses >0.2% per bet

**Performance**: All house balance fetches are non-blocking via `start_async`. Page loads instantly, UI updates smoothly when data arrives.

**Documentation**: See [docs/bux_minter.md](docs/bux_minter.md) for complete BUX minter API reference.

### Infinite Scroll for Scrollable Divs (Dec 2024)

**Problem**: The existing `InfiniteScroll` hook only worked for window scrolling, not scrollable divs with `overflow-y: auto`.

**Solution**: Enhanced the hook to detect and handle both window scroll and element scroll:

```javascript
let InfiniteScroll = {
  mounted() {
    // Auto-detect if element is scrollable
    const hasOverflow = this.el.scrollHeight > this.el.clientHeight;
    const isScrollable = getComputedStyle(this.el).overflowY === 'auto' ||
                         getComputedStyle(this.el).overflowY === 'scroll';
    this.useElementScroll = hasOverflow && isScrollable;

    // Use element as IntersectionObserver root for scrollable divs
    this.observer = new IntersectionObserver(
      entries => { /* ... */ },
      {
        root: this.useElementScroll ? this.el : null,  // Key change
        rootMargin: '200px',
        threshold: 0
      }
    );

    // Attach scroll listener to element or window
    if (this.useElementScroll) {
      this.el.addEventListener('scroll', this.handleScroll, { passive: true });
    } else {
      window.addEventListener('scroll', this.handleScroll, { passive: true });
    }
  }
}
```

**Key Points**:
- IntersectionObserver's `root` option determines what is observed for scrolling
- `root: null` = observe window scroll (default)
- `root: this.el` = observe element scroll (for scrollable divs)
- Must attach scroll listener to the correct target (element vs window)
- Must clean up from the correct target in `destroyed()`

**Use Case**: BUX Booster Recent Games table with `max-h-96 overflow-y-auto`

**Files Changed**: [app.js:175-290](assets/js/app.js#L175-L290)

### Mnesia Pagination Pattern (Dec 2024)

**Pattern**: Load data from Mnesia with pagination using `Enum.drop` and `Enum.take`:

```elixir
defp load_recent_games(user_id, opts \\ []) do
  limit = Keyword.get(opts, :limit, 10)
  offset = Keyword.get(opts, :offset, 0)

  :mnesia.dirty_index_read(:bux_booster_onchain_games, user_id, :user_id)
  |> Enum.filter(fn record -> elem(record, 7) == :settled end)
  |> Enum.sort_by(fn record -> elem(record, 21) end, :desc)
  |> Enum.drop(offset)    # Skip already-loaded items
  |> Enum.take(limit)     # Take next batch
  |> Enum.map(fn record -> %{...} end)
end
```

**Socket State**:
```elixir
socket
|> assign(recent_games: load_recent_games(user_id, limit: 30))
|> assign(games_offset: 30)  # Track position for next load
```

**Event Handler**:
```elixir
def handle_event("load-more-games", _params, socket) do
  offset = socket.assigns.games_offset
  new_games = load_recent_games(user_id, limit: 30, offset: offset)
  
  if Enum.empty?(new_games) do
    {:reply, %{end_reached: true}, socket}  # Signal end to JS hook
  else
    {:noreply,
     socket
     |> assign(:recent_games, socket.assigns.recent_games ++ new_games)
     |> assign(:games_offset, offset + length(new_games))}
  end
end
```

**Performance**: Mnesia dirty reads are fast (~1-2ms for 30 records), but consider total memory for unbounded lists.

### Recent Games Table Implementation (Dec 2024)

**Feature**: Comprehensive game history with clickable transaction links and provably fair verification.

**Key Elements**:
1. **Nonce as Bet ID**: User-friendly identifier (#137) linked to bet placement tx
2. **Transaction Links**: All links include `?tab=logs` for immediate event log access
3. **Sticky Header**: `sticky top-0 bg-white z-10` keeps headers visible during scroll
4. **Security**: Verify button only appears for settled games with complete fairness data

**Template Pattern**:
```heex
<div id="recent-games-scroll" class="overflow-y-auto max-h-96" phx-hook="InfiniteScroll">
  <table class="w-full text-xs">
    <thead class="sticky top-0 bg-white z-10">
      <!-- Headers stay visible while scrolling -->
    </thead>
    <tbody>
      <%= for game <- @recent_games do %>
        <tr>
          <td>
            <a href={"https://roguescan.io/tx/#{game.bet_tx}?tab=logs"}>
              #<%= game.nonce %>
            </a>
          </td>
          <!-- ... more columns ... -->
        </tr>
      <% end %>
    </tbody>
  </table>
</div>
```

**Gotcha**: When adding `phx-hook="InfiniteScroll"` to a div, ensure the div itself is scrollable (`overflow-y-auto`), not a child element. The hook observes the element it's attached to.


### Unauthenticated User Access to BUX Booster (Dec 2024)

**Feature**: Allow non-logged-in users to interact with the full BUX Booster UI to preview the game before signing up.

**Implementation** ([bux_booster_live.ex](lib/blockster_v2_web/live/bux_booster_live.ex)):

1. **Mount Logic** (lines 27-167):
   - Removed redirect to login for unauthenticated users
   - Initialize zero balances: `%{"BUX" => 0, "ROGUE" => 0, "aggregate" => 0}`
   - No wallet initialization or blockchain calls
   - House balance still fetched via async for max bet calculation

2. **Event Handler Updates**:
   - `select_token` - Skip user stats load if `current_user == nil`
   - `set_max_bet` - Use contract max bet instead of user balance for unauthenticated users
   - `double_bet` - Cap at contract max instead of user balance for unauthenticated users
   - `halve_bet` - Works identically for all users (no changes)
   - `update_bet_amount` - Already accepts any positive integer (no changes)
   - `start_game` - Redirect to `/login` if `current_user == nil`
   - `reset_game` - Only reset UI state for unauthenticated users (no Mnesia ops)
   - `load-more-games` - Return empty immediately for unauthenticated users

3. **Template Updates**:
   - Provably Fair dropdown shows placeholder for unauthenticated users:
     ```heex
     <%= if @current_user do %>
       <!-- Show actual server seed hash -->
     <% else %>
       <code>&lt;hashed_server_seed_displays_here_when_you_are_logged_in&gt;</code>
     <% end %>
     ```

**What Works for Unauthenticated Users**:
- View `/play` page without redirect
- See zero balances in all displays
- Switch tokens (BUX/ROGUE) in dropdown
- Change difficulty levels (all 9 levels)
- Select predictions (heads/tails)
- Input any bet amount
- Use bet controls (½, 2×, MAX)
- See potential win calculations
- View Provably Fair dropdown (with placeholder)

**What Requires Login**:
- Clicking "Place Bet" → redirects to `/login`
- No blockchain transactions
- No commitment hash submitted
- No Mnesia operations

**Key Principle**: For any event handler that accesses `current_user.id`, add a guard clause:
```elixir
if socket.assigns.current_user == nil do
  # Handle unauthenticated case (redirect, skip, or use defaults)
else
  # Normal authenticated flow
end
```

**Benefits**:
- Better onboarding experience
- Users can explore mechanics before signup
- Educational preview of all features
- Zero security risk (no blockchain exposure)

**Documentation**: See [docs/bux_booster_onchain.md](docs/bux_booster_onchain.md#unauthenticated-user-access) for full details.

### Recent Games Table Live Update on Settlement (Dec 2024)

**Problem**: After a bet settled on-chain, the recent games table would not show the newly settled bet until the user clicked "Play Again".

**Root Cause**:
- Recent games are loaded during `:show_final_result` (line 1748), which happens BEFORE the settlement completes
- Settlement happens asynchronously in a spawned process after showing the game result
- When `BuxBoosterOnchain.settle_game/1` completes and updates the game status to `:settled` in Mnesia, the UI wasn't notified

**Solution** ([bux_booster_live.ex:1843-1856](lib/blockster_v2_web/live/bux_booster_live.ex#L1843-L1856)):
Added `recent_games = load_recent_games(user_id)` to the `:settlement_complete` handler:
```elixir
def handle_info({:settlement_complete, tx_hash}, socket) do
  user_id = socket.assigns.current_user.id
  wallet_address = socket.assigns.wallet_address

  # Sync balances from blockchain (async - will broadcast when complete)
  BuxMinter.sync_user_balances_async(user_id, wallet_address)

  # Reload recent games to show the newly settled bet
  recent_games = load_recent_games(user_id)

  {:noreply,
   socket
   |> assign(settlement_tx: tx_hash)
   |> assign(recent_games: recent_games)}
end
```

**Result**: The settled bet now appears in the recent games table immediately (2-3 seconds after the result is shown) without requiring user interaction.

**Timeline**:
1. User sees result animation → Game marked with result in `:show_final_result`
2. ~2-3s later → Settlement tx confirms on-chain
3. Settlement complete → Recent games table updates with new settled game
4. Balances sync → All balance displays update


### Aggregate Balance ROGUE Exclusion Fix (Dec 2024)

**Problem**: When a bet failed in BUX Booster (e.g., exceeding max bet size), the aggregate balance incorrectly included ROGUE balance in the calculation, inflating the displayed total in the header.

**Root Cause**:
- Aggregate balance represents the sum of BUX-flavored tokens only (BUX, moonBUX, neoBUX, etc.)
- ROGUE is the native gas token and stored separately in `user_rogue_balances` table
- `get_user_token_balances/1` returns a map with ALL tokens including ROGUE
- When recalculating aggregate after bet placement or refund, code was excluding only `"aggregate"` key but not `"ROGUE"` key
- This caused ROGUE balance to be summed into the aggregate

**Locations with Bug**:
1. Successful bet placement ([bux_booster_live.ex:1266-1271](lib/blockster_v2_web/live/bux_booster_live.ex#L1266-L1271))
2. Failed bet refund ([bux_booster_live.ex:1394-1401](lib/blockster_v2_web/live/bux_booster_live.ex#L1394-L1401))

**Solution**:
Exclude both `"aggregate"` and `"ROGUE"` keys when calculating aggregate:
```elixir
# CORRECT: Exclude both "aggregate" and "ROGUE"
aggregate_balance = balances
|> Map.delete("aggregate")
|> Map.delete("ROGUE")
|> Map.values()
|> Enum.sum()
```

**Why ROGUE is Separate**:
- ROGUE is Rogue Chain's native gas token (like ETH on Ethereum)
- ROGUE has no contract address - it's part of the blockchain itself
- ROGUE balance fetched with `provider.getBalance()`, not ERC-20 `balanceOf()`
- Aggregate represents BUX economy tokens only, not native chain tokens

**EngagementTracker Calculation**:
The `calculate_aggregate_balance/1` function in EngagementTracker was already correct:
```elixir
defp calculate_aggregate_balance(record) do
  # Sum all token balances (indices 5-15: BUX flavors only)
  Enum.reduce(5..15, 0.0, fn index, acc ->
    acc + (elem(record, index) || 0.0)
  end)
end
```
This sums indices 5-15 which are BUX-flavored tokens only. ROGUE is never stored in `user_bux_balances` table.

**Testing**:
1. Have ROGUE balance (e.g., 1.5M ROGUE)
2. Have BUX balance (e.g., 600 BUX)
3. Place a bet that fails (exceeds max bet)
4. Verify aggregate shows ~600 BUX, not ~1,500,600

**Files Changed**: [bux_booster_live.ex](lib/blockster_v2_web/live/bux_booster_live.ex#L1266-1271) and [bux_booster_live.ex](lib/blockster_v2_web/live/bux_booster_live.ex#L1394-1401)
