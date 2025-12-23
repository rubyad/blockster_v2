# Blockster V2

Phoenix LiveView application with Elixir backend, serving a web3 content platform with a shop, hubs, events, and token-based engagement system.

> **Claude Instructions**: After every conversation compaction/summarization, update this file with any new learnings, patterns, contract addresses, configuration changes, or important decisions made during the session. This file is persistent project memory - keep it current.

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
```bash
# Terminal 1
elixir --sname node1 -S mix phx.server

# Terminal 2
PORT=4001 elixir --sname node2 -S mix phx.server
```

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

#### Database Optimization
- **Use ETS/Mnesia for caching** frequently accessed data to reduce PostgreSQL load
- Create named GenServers to manage ETS tables for caching
- Use `Repo.preload` with specific queries, not bare associations
- Batch database operations where possible
- Use indexes on frequently queried columns

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
| BUX | `0xbe46C2A9C729768aE938bc62eaC51C7Ad560F18d` |
| moonBUX | `0x08F12025c1cFC4813F21c2325b124F6B6b5cfDF5` |
| neoBUX | `0x423656448374003C2cfEaFF88D5F64fb3A76487C` |
| rogueBUX | `0x56d271b1C1DCF597aA3ee454bCCb265d4Dee47b3` |
| flareBUX | `0xd27EcA9bc2401E8CEf92a14F5Ee9847508EDdaC8` |

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
Deployed at `https://bux-minter.fly.dev` - handles blockchain token minting.

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

---

## Security Notes

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

---

## Services & External Dependencies

| Service | URL | Purpose |
|---------|-----|---------|
| Main App | `https://blockster-v2.fly.dev` | Phoenix app |
| v2 Domain | `https://v2.blockster.com` | Production domain |
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
