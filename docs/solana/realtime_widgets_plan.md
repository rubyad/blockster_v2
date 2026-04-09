# Real-Time Sister-Project Widgets

> Replace the left + right tall skyscraper banner positions on Blockster article pages with live, real-time activity widgets sourced from our two sister Phoenix LiveView apps:
> - **Left sidebar** → FateSwap live trade feed
> - **Right sidebar** → RogueTrader live RogueBot leaderboard

This is **Phase 1** of a broader sister-project widget framework. The same pattern can later be extended to `play_sidebar_*`, `airdrop_sidebar_*`, etc.

---

## Decisions locked in (per user)

| # | Question | Decision |
|---|---|---|
| 1 | Data delivery | **Polling.** Add public REST endpoints in FateSwap + RogueTrader. Blockster runs a `GlobalSingleton` poller that fetches → caches → broadcasts via local PubSub. |
| 2 | Sidebar width | **Keep 200px.** Make rows taller / multi-line to fit info-dense content. |
| 3 | Replacement model | **Option C.** Reuse the existing `ad_banners` table. Add new `placement` enum values and a special `widget_type` field. The `image_url` is unused for widget rows; the renderer dispatches to a widget component when `widget_type` is set. Tracking, scheduling, admin UI all keep working. |
| 4 | Visual style | **Dark widget on light page.** Trading-app aesthetic — pops on Blockster's white background, matches FateSwap/RogueTrader brand. |
| 5 | Logo assets | Use the assets that already exist in each project. |
| 6 | Click destinations | Always link to the project homepage (no per-row deep links in v1). |
| 7 | Tracking | Reuse the `ad_banners` impressions/clicks columns. Each widget row in the table gets one impression on render and one click when the widget is clicked. |

---

## Logo assets (confirmed)

**FateSwap**
- Wordmark (SVG, 220×28): `https://fateswap.io/images/logo-full.svg` — three colored bars + "FATESWAP" wordmark in green/yellow/red gradient. Public — served from FateSwap's `priv/static/images/`.
- Icon-only (SVG, 26×17): `https://fateswap.io/images/logo-bars.svg` — three horizontal bars only.
- Fallback PNGs: `/images/exports/logo-bars-{32,48,64,128,256,512}.png` and `/images/exports/logo-full.png`.

**RogueTrader**
- Wordmark (PNG on ImageKit, 413×128): `https://ik.imagekit.io/blockster/rogue-logo-white.png` — white "ROGUE" wordmark suitable for dark backgrounds.
- Icon-only (SVG, 71×48): `https://roguetrader.io/images/logo.svg` — stylized "R" mark in `#FD4F00`.

Both can be embedded directly via `<img>`. No new asset hosting required.

---

## Architecture overview

```
┌──────────────────────┐         ┌──────────────────────┐
│  FateSwap (ord)      │         │  RogueTrader (iad)   │
│  Phoenix LiveView    │         │  Phoenix LiveView    │
│                      │         │                      │
│  GET /api/feed/      │         │  GET /api/bots       │
│  recent              │         │  (returns 30 bots,   │
│  (returns 20 latest  │         │   sorted by lp_price)│
│   settled trades)    │         │                      │
└──────────┬───────────┘         └──────────┬───────────┘
           │ HTTPS                          │ HTTPS
           │ poll every 3s                  │ poll every 10s
           ▼                                ▼
   ┌────────────────────────────────────────────────┐
   │  Blockster V2 (ord)                            │
   │                                                │
   │  ┌──────────────────────────────────────────┐  │
   │  │ FateSwapFeedTracker (GlobalSingleton)    │  │
   │  │ RogueTraderBotsTracker (GlobalSingleton) │  │
   │  │                                          │  │
   │  │ - poll external API on interval          │  │
   │  │ - diff vs last snapshot                  │  │
   │  │ - write to Mnesia ETS-backed cache       │  │
   │  │ - broadcast on local PubSub if changed   │  │
   │  └──────────┬───────────────────────────────┘  │
   │             │                                  │
   │             ▼                                  │
   │  Phoenix.PubSub topics:                        │
   │   "fateswap:feed"      → {:fateswap_trades, list}
   │   "roguetrader:bots"   → {:roguetrader_bots, list}
   │             │                                  │
   │             ▼                                  │
   │  PostLive.Show subscribes on mount             │
   │             │                                  │
   │             ▼                                  │
   │  push_event("widget:fateswap:update", payload) │
   │  push_event("widget:roguetrader:update", payload)
   │             │                                  │
   │             ▼                                  │
   │  JS hooks (FateSwapWidget / RogueTraderWidget) │
   │  - animate new rows in at top                  │
   │  - update existing row deltas (price changes)  │
   │  - drop oldest off the bottom                  │
   └────────────────────────────────────────────────┘
```

**Why polling and not webhooks/clustering**: simplicity, decoupling, no shared infra, no cross-region clustering fragility (RogueTrader is `iad`, Blockster + FateSwap are `ord`). 3-second lag on a sidebar widget is invisible.

---

## Backend changes

### A. FateSwap — new public API endpoint

**File**: `lib/fateswap_web/controllers/api/feed_controller.ex` *(new)*
**Route**: `GET /api/feed/recent?limit=20`
**Auth**: Public read-only. Rate-limit by IP via existing `Hammer` if installed, otherwise add a simple `Plug` cap (60 req/min per IP).

```elixir
defmodule FateSwapWeb.Api.FeedController do
  use FateSwapWeb, :controller
  alias FateSwap.Orders

  def recent(conn, params) do
    limit = parse_limit(params, default: 20, max: 50)
    trades =
      Orders.list_recent_settled(limit: limit)
      |> Enum.map(&serialize_trade/1)

    json(conn, %{trades: trades, fetched_at: DateTime.utc_now()})
  end

  defp serialize_trade(order) do
    %{
      id: order.id,
      side: order.side,                              # "buy" | "sell"
      token_symbol: order.token_symbol,
      token_logo_url: order.token_logo_url,
      sol_amount: order.sol_amount,                  # lamports
      sol_amount_ui: order.sol_amount / 1_000_000_000,
      payout: order.payout,                          # lamports
      payout_ui: order.payout / 1_000_000_000,
      multiplier: order.multiplier_bps / 100_000,    # 110000 → 1.10
      filled: order.filled,
      profit_lamports: order.payout - order.sol_amount,
      profit_ui: (order.payout - order.sol_amount) / 1_000_000_000,
      sol_price_usd: order.sol_price_usd,
      wallet_address: order.wallet_address,
      wallet_truncated: truncate(order.wallet_address),
      settled_at: order.settled_at
    }
  end
end
```

**Router**: in `lib/fateswap_web/router.ex`, inside the existing `scope "/api"`:
```elixir
get "/feed/recent", Api.FeedController, :recent
```

**CORS**: add `cors_plug` to the `:api` pipeline if not already present, allowing `GET` from `https://blockster.com` and `http://localhost:4000`. *(FateSwap currently has no CORS — confirm with test before deploy.)*

---

### B. RogueTrader — new public API endpoint

**File**: `lib/roguetrader_web/controllers/api/bots_controller.ex` *(new)*
**Route**: `GET /api/bots`
**Auth**: Public read-only.

```elixir
defmodule RogueTraderWeb.Api.BotsController do
  use RogueTraderWeb, :controller
  alias RogueTrader.Stats.StatsTracker
  alias RogueTrader.Bots

  def index(conn, _params) do
    stats = StatsTracker.get_all_stats()        # 30-element list, ETS read
    bots_meta = Bots.list_all() |> Map.new(&{&1.bot_id, &1})

    payload =
      stats
      |> Enum.map(fn s ->
        meta = Map.get(bots_meta, s["bot_id"], %{})
        %{
          bot_id: s["bot_id"],
          name: meta.name,
          group_name: meta.group_name,
          group_color: group_color(meta.group_name),
          archetype: meta.archetype,
          risk_level: meta.risk_level,
          lp_price: s["lp_price"],
          lp_price_change_1h_pct: s["lp_price_change_1h_pct"],
          lp_price_change_24h_pct: s["lp_price_change_24h_pct"],
          sol_balance_ui: s["sol_balance"] / 1_000_000_000,
          win_rate: s["win_rate"],
          active_bet_count: s["active_bet_count"],
          market_open: s["market_open"]
        }
      end)
      |> Enum.sort_by(& &1.lp_price, :desc)

    json(conn, %{bots: payload, fetched_at: DateTime.utc_now()})
  end
end
```

**Router**: in `lib/roguetrader_web/router.ex`:
```elixir
get "/bots", Api.BotsController, :index
```

**CORS**: same as FateSwap.

---

### C. Blockster — new poller GenServers

Two new modules under `lib/blockster_v2/widgets/`:

#### `lib/blockster_v2/widgets/fateswap_feed_tracker.ex`
- `GlobalSingleton` GenServer (mirrors `LpPriceTracker` pattern)
- State: `%{trades: [], last_fetched_at: nil, last_error: nil}`
- `:poll` every **3000ms**
- HTTP: `Req.get!("https://fateswap.io/api/feed/recent?limit=20", receive_timeout: 5_000)`
- On success: diff vs last snapshot. If new trades present → `Phoenix.PubSub.broadcast(BlocksterV2.PubSub, "widgets:fateswap_feed", {:fateswap_trades, trades})`
- On error: log + keep serving stale cache (do not crash)
- Public API: `FateSwapFeedTracker.get_trades/0` (returns latest list, used for initial mount paint)
- Mnesia table `widget_fateswap_feed_cache` `{:singleton, trades, fetched_at}` so non-singleton nodes can read without RPC

#### `lib/blockster_v2/widgets/roguetrader_bots_tracker.ex`
- Same pattern. Polls **every 10000ms** (matches RogueTrader's internal `StatsTracker` cadence).
- URL: `https://roguetrader.io/api/bots`
- PubSub topic: `"widgets:roguetrader_bots"` → `{:roguetrader_bots, bots}`
- Cache table `widget_roguetrader_bots_cache`

**Supervision**: register both in `application.ex` under `BlocksterV2.GlobalSingleton` so they run on exactly one node across the cluster (rolling-deploy safe).

**Config**: add to `runtime.exs`:
```elixir
config :blockster_v2, :widgets,
  fateswap_feed_url: System.get_env("FATESWAP_FEED_URL", "https://fateswap.io/api/feed/recent?limit=20"),
  roguetrader_bots_url: System.get_env("ROGUETRADER_BOTS_URL", "https://roguetrader.io/api/bots"),
  fateswap_poll_interval_ms: 3_000,
  roguetrader_poll_interval_ms: 10_000
```

---

### D. Banners table — schema additions

**Migration** `priv/repo/migrations/{ts}_add_widget_columns_to_ad_banners.exs`:
```elixir
def change do
  alter table(:ad_banners) do
    add :widget_type, :string             # nil for normal banners; "fateswap_feed" | "roguetrader_bots" | future widgets
    add :widget_config, :map, default: %{} # optional per-widget knobs (e.g., max_rows)
  end
  create index(:ad_banners, [:widget_type])
end
```

**Schema** `lib/blockster_v2/ads/banner.ex`:
- Add `widget_type` and `widget_config` to schema + changeset cast
- Extend `@valid_placements` with `sidebar_left` / `sidebar_right` (already present — no change needed)
- Add a `@valid_widget_types ~w(fateswap_feed roguetrader_bots)` and `validate_inclusion(:widget_type, [nil | @valid_widget_types])`
- `image_url` becomes optional when `widget_type` is set

**Context** `lib/blockster_v2/ads.ex`:
- No new functions needed; the existing `list_active_banners_by_placement/1` already returns rows. The renderer just inspects `banner.widget_type`.
- Keep `increment_impressions/1` and `increment_clicks/1` — they work for both types.

---

### E. PostLive.Show wiring

`lib/blockster_v2_web/live/post_live/show.ex`:

```elixir
# inside mount/handle_params, after loading banners:
if connected?(socket) do
  Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "widgets:fateswap_feed")
  Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "widgets:roguetrader_bots")
end

initial_fateswap_trades =
  if connected?(socket), do: BlocksterV2.Widgets.FateSwapFeedTracker.get_trades(), else: []
initial_roguetrader_bots =
  if connected?(socket), do: BlocksterV2.Widgets.RogueTraderBotsTracker.get_bots(), else: []

socket
|> assign(:fateswap_trades, initial_fateswap_trades)
|> assign(:roguetrader_bots, initial_roguetrader_bots)
```

```elixir
def handle_info({:fateswap_trades, trades}, socket) do
  {:noreply,
   socket
   |> assign(:fateswap_trades, trades)
   |> push_event("widget:fateswap:update", %{trades: trades})}
end

def handle_info({:roguetrader_bots, bots}, socket) do
  {:noreply,
   socket
   |> assign(:roguetrader_bots, bots)
   |> push_event("widget:roguetrader:update", %{bots: bots})}
end
```

---

### F. Widget components

`lib/blockster_v2_web/components/widget_components.ex` *(new)*

```elixir
defmodule BlocksterV2Web.WidgetComponents do
  use Phoenix.Component

  attr :banner, :map, required: true     # the ad_banners row
  attr :trades, :list, default: []
  def fateswap_feed_widget(assigns)

  attr :banner, :map, required: true
  attr :bots, :list, default: []
  def roguetrader_bots_widget(assigns)
end
```

Each widget is a self-contained dark card matching the 200px sidebar width, with a header (logo + label + live indicator) and a scrollable list. JS hook attached for incremental DOM updates.

**Banner renderer dispatch** in `show.html.heex` (replacing the current `<%= for banner <- @left_sidebar_banners %>` blocks):

```heex
<aside class="hidden lg:block w-[200px] shrink-0">
  <div class="sticky top-36 space-y-4">
    <%= for banner <- @left_sidebar_banners do %>
      <%= case banner.widget_type do %>
        <% "fateswap_feed" -> %>
          <.fateswap_feed_widget banner={banner} trades={@fateswap_trades} />
        <% "roguetrader_bots" -> %>
          <.roguetrader_bots_widget banner={banner} bots={@roguetrader_bots} />
        <% _ -> %>
          <a href={banner.link_url} target="_blank" rel="noopener" class="block rounded-lg overflow-hidden hover:shadow-lg transition-shadow cursor-pointer" phx-click="track_ad_click" phx-value-id={banner.id}>
            <img src={banner.image_url} alt={banner.name} class="w-full" loading="lazy" />
          </a>
      <% end %>
    <% end %>
    <%!-- empty state unchanged --%>
  </div>
</aside>
```

The same dispatch goes in the right sidebar block. No empty-state changes.

---

### G. JS hooks

Two new hooks under `assets/js/hooks/`:

#### `widgets/fateswap_feed_widget.js`
```js
export const FateSwapFeedWidget = {
  mounted() {
    this.handleEvent("widget:fateswap:update", ({ trades }) => {
      this.renderTrades(trades);
    });
    // request initial paint if server hasn't pushed yet
  },
  renderTrades(trades) {
    // diff against currently rendered list, animate new rows in at top,
    // animate stale rows out at bottom. Uses minimal DOM ops.
  }
}
```

#### `widgets/roguetrader_bots_widget.js`
```js
export const RogueTraderBotsWidget = {
  mounted() {
    this.handleEvent("widget:roguetrader:update", ({ bots }) => {
      this.renderBots(bots);
    });
  },
  renderBots(bots) {
    // update price, %chg, AUM in place. Re-sort by lp_price desc.
    // Flash green/red on price changes (200ms).
  }
}
```

Register both in `assets/js/app.js` Hooks object.

---

### H. Impression / click tracking

**Impression**: when the widget renders for the first time on a page (in `show.ex` mount, on connected socket), call `Ads.increment_impressions(banner.id)` once per banner. This already happens for regular banners — extend it to widgets so the metric is comparable.

**Click**: the entire widget card has `phx-click="track_ad_click" phx-value-id={banner.id}` and a `phx-window-event` is unnecessary. Existing `handle_event("track_ad_click", ...)` works as-is. The widget links to the homepage of the source project (`https://fateswap.io` / `https://roguetrader.io`) — handled by the same `<a target="_blank">` wrapper.

---

## Visual design — what each widget looks like

> A separate visual mock will be generated via `/frontend-design` and shown before any code is written. The text below is the spec the mock will follow.

**Both widgets** share these constraints:
- **Width**: 200px (matches sidebar)
- **Theme**: dark — `#0A0A0F` background, `#14141A` rows, `#E8E4DD` text, `#22C55E` win/positive, `#EF4444` loss/negative, `#EAB308` accent
- **Border-radius**: `rounded-2xl` (Tailwind 1rem)
- **Shadow**: subtle `shadow-2xl shadow-black/40`
- **Header**: 56px tall, project logo on left, "LIVE" pill with pulsing green dot on right
- **Footer**: thin "Powered by [project name] →" link
- **Font**: monospace (`font-mono`) for all numeric data, `font-haas_medium_65` for labels
- **Hover**: subtle row highlight (`bg-white/5`)
- **Empty state**: spinner + "Loading live feed…"

### FateSwap left widget

**Header**: FateSwap wordmark (40×16 effective at 200px) + green pulsing "LIVE" pill
**Subheader**: tiny line "Latest trades" with last-updated relative time
**Rows** (5 visible, scrollable to 20):
```
┌──────────────────────────────┐
│ ▲ BUY     2h ago  ◢ FILLED   │   ← side icon (green ▲ buy / red ▼ sell), result tag
│ 0.50 SOL → 0.55 SOL          │   ← amount in / payout out
│ +0.05 SOL  ($8.20)           │   ← profit (green) or loss (red), USD eq
│ 7xQk…3mPa                    │   ← truncated wallet, monospace
└──────────────────────────────┘
```
- Filled rows: subtle green tint left border (`border-l-2 border-fate-green`)
- Unfilled rows: subtle red tint left border
- New row animation: slide down from top, 300ms ease-out, brief lime ring highlight

### RogueTrader right widget

**Header**: RogueTrader wordmark (white on dark) + orange pulsing "LIVE" pill (`#FD4F00` matches their R icon)
**Subheader**: tiny line "Top RogueBots" with refresh tick
**Rows** (5 visible, scrollable to 30):
```
┌──────────────────────────────┐
│ #1  ● Crypto                 │   ← rank + colored group dot + group name
│ Apex Hunter         HIGH     │   ← name + risk badge
│ 1.2456 SOL                   │   ← LP price (large, primary)
│ ▲ +12.4% 24h        Open ●   │   ← 24h % (green/red) + market open dot
└──────────────────────────────┘
```
- Group color dot uses RogueTrader palette: Crypto `#3B82F6`, Equities `#10B981`, Indexes `#8B5CF6`, Commodities `#F59E0B`, Forex `#F43F5E`
- Risk badge: green pill for Low, yellow for Med, red for High
- Price-change cell flashes green/red on update (200ms), sticky background subtly tints
- Re-sort animation when rank changes: 250ms FLIP-style row slide

---

## Phased build order

**Phase 0 — Visual design (do first, before any code)**
- [ ] Run `/frontend-design` to mock both widgets at 200×400px
- [ ] Show user, get approval

**Phase 1 — Sister-app APIs**
- [ ] FateSwap: add `Api.FeedController`, route, CORS, test
- [ ] RogueTrader: add `Api.BotsController`, route, CORS, test
- [ ] Manually deploy both, verify endpoints publicly reachable
- [ ] Hit each from Blockster dev with `Req.get!`

**Phase 2 — Blockster pollers**
- [ ] `lib/blockster_v2/widgets/fateswap_feed_tracker.ex` (GlobalSingleton)
- [ ] `lib/blockster_v2/widgets/roguetrader_bots_tracker.ex` (GlobalSingleton)
- [ ] Mnesia cache tables in `mnesia_initializer.ex`
- [ ] Wire into `application.ex` supervision
- [ ] Tests with stubbed HTTP via `Req.Test`

**Phase 3 — Banners schema**
- [ ] Migration: `widget_type`, `widget_config` columns
- [ ] Schema + changeset updates
- [ ] Update banner admin form (if exists) to allow widget selection
- [ ] Tests for changeset validation

**Phase 4 — Widget components + JS hooks**
- [ ] `lib/blockster_v2_web/components/widget_components.ex`
- [ ] `assets/js/hooks/widgets/fateswap_feed_widget.js`
- [ ] `assets/js/hooks/widgets/roguetrader_bots_widget.js`
- [ ] Register in `app.js`
- [ ] Visual smoke test in dev

**Phase 5 — PostLive.Show integration**
- [ ] Subscribe to PubSub topics in mount
- [ ] Add `handle_info` handlers
- [ ] Replace banner loop with widget-dispatch in template
- [ ] Both sidebars

**Phase 6 — Tracking & polish**
- [ ] Verify impressions/clicks increment
- [ ] Add loading skeleton + error state
- [ ] Mobile: confirm widgets remain hidden behind `lg:block` (no mobile widget in v1)
- [ ] Run full test suite, zero failures required

**Phase 7 — Production rollout**
- [ ] Insert two `ad_banners` rows manually via Blockster admin / SQL:
  - `name: "FateSwap Live Feed", placement: "sidebar_left", widget_type: "fateswap_feed", link_url: "https://fateswap.io", is_active: true`
  - `name: "RogueTrader Bots", placement: "sidebar_right", widget_type: "roguetrader_bots", link_url: "https://roguetrader.io", is_active: true`
- [ ] User-confirmed deploy

---

## Risks / open considerations

1. **CORS on FateSwap & RogueTrader**: neither app currently has CORS configured. We're calling these from Blockster's *server* (not the browser), so CORS technically doesn't apply — but if we ever want to fall back to a browser-side fetch, we'd need it. **Decision: skip CORS for v1**, server-to-server only.

2. **Rate limiting**: 3s polls = ~28k req/day to FateSwap from one Blockster node. Acceptable. RogueTrader at 10s = ~8.6k/day. Both are negligible.

3. **API stability across sister-app deploys**: if FateSwap renames a field, the Blockster widget breaks. Mitigation: poller logs serialization errors, falls back to last good snapshot. Field changes should be coordinated via this plan doc.

4. **Cross-region latency to RogueTrader (`iad`)**: ord→iad is ~25ms. Negligible for a 10s poll cadence.

5. **What if a poller node dies mid-poll?**: `GlobalSingleton` failover: another node takes over within seconds, resumes polling. Cache survives in Mnesia.

6. **Tracking double-counting**: a single page view triggers one impression per widget. Refreshes count again — same as regular banners. No special handling needed.

7. **Widget config column unused in v1**: keeping it for future per-instance overrides (e.g., max rows, filter to only "wins" feed).

8. **No mobile widget in v1**: sidebars are desktop-only (`hidden lg:block`). If we want mobile, we'd add a new placement (`mobile_widget`) and a different vertical layout — out of scope.

9. **Server seed / privacy**: trades returned by the FateSwap API are already public (settled, on-chain). No PII concerns. Wallet addresses are already shown publicly on FateSwap's own site.

---

## File inventory

### New files
- `/Users/tenmerry/Projects/fateswap/lib/fateswap_web/controllers/api/feed_controller.ex`
- `/Users/tenmerry/Projects/roguetrader/lib/roguetrader_web/controllers/api/bots_controller.ex`
- `/Users/tenmerry/Projects/blockster_v2/lib/blockster_v2/widgets/fateswap_feed_tracker.ex`
- `/Users/tenmerry/Projects/blockster_v2/lib/blockster_v2/widgets/roguetrader_bots_tracker.ex`
- `/Users/tenmerry/Projects/blockster_v2/lib/blockster_v2_web/components/widget_components.ex`
- `/Users/tenmerry/Projects/blockster_v2/assets/js/hooks/widgets/fateswap_feed_widget.js`
- `/Users/tenmerry/Projects/blockster_v2/assets/js/hooks/widgets/roguetrader_bots_widget.js`
- `/Users/tenmerry/Projects/blockster_v2/priv/repo/migrations/{ts}_add_widget_columns_to_ad_banners.exs`

### Modified files
- `/Users/tenmerry/Projects/fateswap/lib/fateswap_web/router.ex` (add route)
- `/Users/tenmerry/Projects/roguetrader/lib/roguetrader_web/router.ex` (add route)
- `/Users/tenmerry/Projects/blockster_v2/lib/blockster_v2/ads/banner.ex` (widget_type + widget_config)
- `/Users/tenmerry/Projects/blockster_v2/lib/blockster_v2/ads.ex` (no change unless we add filter helpers)
- `/Users/tenmerry/Projects/blockster_v2/lib/blockster_v2/application.ex` (supervise pollers via GlobalSingleton)
- `/Users/tenmerry/Projects/blockster_v2/lib/blockster_v2/mnesia_initializer.ex` (two new cache tables)
- `/Users/tenmerry/Projects/blockster_v2/lib/blockster_v2_web/live/post_live/show.ex` (PubSub subscribe + handle_info + assigns)
- `/Users/tenmerry/Projects/blockster_v2/lib/blockster_v2_web/live/post_live/show.html.heex` (banner-renderer dispatch in both sidebars)
- `/Users/tenmerry/Projects/blockster_v2/assets/js/app.js` (register hooks)
- `/Users/tenmerry/Projects/blockster_v2/config/runtime.exs` (widget URLs + intervals)
