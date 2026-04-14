# Real-Time Sister-Project Widgets (v2 — full framework)

> Replace **all** sister-project ad placements on Blockster (article page, homepage, video player) with live, dynamic widgets in multiple shapes and formats, sourced from our two sister Phoenix LiveView apps:
> - **RogueTrader** → bot prices, charts, leaderboards (matches `roguetrader.io` UI exactly)
> - **FateSwap** → live trade feed, order-filled hero cards (matches `fateswap.io` UI exactly)

Both apps already share an identical dark trading-app design system (same color tokens, same fonts, same chart library). We import that design system into Blockster as a scoped widget CSS module and build a catalogue of widget components that render in any placement (200px sidebar, ~720px inline, full-bleed homepage, horizontal ticker, mobile-responsive).

<!-- v2 confirmations log:
  · 2026-04-13 — User confirmed RogueTrader chart history is already persisted; no ETS ring buffer needed.
  · 2026-04-13 — User confirmed `fateswap.io/orders/:id` exists; self-selected fs_hero clicks land there.
-->

**Why this is a v2 rewrite of the original plan**: v1 assumed two sidebar widgets only, gated by the existing `ad_banners.template` enum. After reviewing the actual `roguetrader.io` and `fateswap.io` UIs the user wants matched, the original constraints are too narrow — chart widgets, multi-card stat grids, hero cards with conviction bars, and self-selecting "best performer" logic don't fit in the existing `image | follow_bar | dark_gradient | portrait | split_card` template enum. v2 introduces a **dedicated widget framework** that runs alongside the existing template-based ad system without disturbing it.

---

## Decisions locked in (v2)

| # | Question | Decision |
|---|---|---|
| 1 | Data delivery | **Polling.** Three endpoints per sister project (current snapshot, chart history per timeframe, per-record detail). Blockster runs `GlobalSingleton` pollers that fetch → cache in Mnesia → broadcast via local PubSub. |
| 2 | Schema model | **Add `widget_type` + `widget_config` columns to `ad_banners`** (separate from existing `template`/`params`). When `widget_type` is set, the renderer dispatches to a dedicated widget component and `template`/`image_url`/`params` are ignored (made nullable). The existing image-based ad system is untouched. |
| 3 | Visual fidelity | **Pixel-match the source projects' UIs.** Import RogueTrader/FateSwap shared color tokens, fonts (Satoshi + JetBrains Mono), card patterns, chart styling. Scope all widget CSS to a `.bw-widget` namespace so it never leaks into Blockster's own design system. |
| 4 | Widget catalog | **14 widgets total** — 8 RogueTrader formats + 6 FateSwap formats (includes `rt_sidebar_tile`, `fs_square_compact`, `fs_sidebar_tile` added during Phase 0 visual design). See [Widget Catalog](#widget-catalog) below. Each widget supports the placements listed in its row. |
| 5 | Placements | Article page (sidebar_left, sidebar_right, article_inline_1/2/3, video_player_top), homepage (top_desktop, top_mobile, inline_desktop, inline_mobile, inline), play & airdrop sidebars. **Mobile versions for every widget on article + homepage.** |
| 6 | Self-selection | Chart widgets that show a single bot/order **dynamically pick the best performer** across all bots × all timeframes (or all recent orders). Configurable via `widget_config` JSONB: `biggest_gainer` (default), `biggest_mover`, `highest_aum`, `biggest_profit`, or `fixed`. |
| 7 | Click destinations | **Self-selected bot widgets → that bot's detail page** (`roguetrader.io/bot/:slug`). **Self-selected order widgets → that order's share page** (`fateswap.io/orders/:id` if exists, else homepage). All-data widgets (skyscrapers, tickers) → project homepage. **Exception: `rt_leaderboard_inline` rows are individually clickable** — each row click goes to that bot's detail page (matches `home_live.ex` `phx-click="navigate_bot"` behavior). |
| 8 | Existing rt-widget on right sidebar | **Replace entirely** with the live `rt_skyscraper` widget. The current 6-bot mock HTML in `show.html.heex` lines 979–1180 is removed. |
| 9 | Charts | **TradingView lightweight-charts v5.1.0** (already used by Blockster pool charts and RogueTrader). Same library, same Area series, identical green-up / red-down behaviour. |
| 10 | Tracking | Reuse `ad_banners.impressions`/`clicks` columns. One impression per widget per page render, one click per widget click. Self-selected variants also bubble up the `bot_id` / `order_id` in the click event so we can later report which entities get the most click-through. |
| 11 | Reference mock | The existing `docs/solana/realtime_widgets_mock.html` (1392 lines) is the v1 reference for the two skyscraper widgets. The other 9 widgets need new mocks generated via `/frontend-design` before code (Phase 0 of build order). |

---

## Design tokens, fonts & assets (shared across both widget families)

Both `roguetrader.io` and `fateswap.io` use an **identical dark trading-app design system**. We import it into Blockster as a scoped CSS module so all widgets share one token set and one font load.

### Color tokens (CSS variables)

```css
/* assets/css/widgets.css — scoped under .bw-widget */
.bw-widget {
  --bw-bg:           #0A0A0F;                   /* widget shell / page-bg-equivalent */
  --bw-card:         #14141A;                   /* card / row background */
  --bw-row-hover:    #1c1c25;                   /* row hover */
  --bw-primary:      #E8E4DD;                   /* primary text (off-white) */
  --bw-secondary:    #6B7280;                   /* labels, secondary */
  --bw-faint:        #4B5563;                   /* tertiary, timestamps */
  --bw-data:         #9CA3AF;                   /* data row text */
  --bw-green:        #22C55E;                   /* positive / filled / buy */
  --bw-green-bright: #4ade80;                   /* bid / win label */
  --bw-red:          #EF4444;                   /* negative / unfilled / sell */
  --bw-red-bright:   #f87171;                   /* ask / loss label */
  --bw-yellow:       #EAB308;                   /* discount %, highlights */
  --bw-yellow-bright:#facc15;                   /* discount value */
  --bw-rogue-orange: #FD4F00;                   /* RogueTrader brand accent */
  --bw-fate-orange:  #8B2500;                   /* FateSwap not-filled bg */
  --bw-border:       rgba(255, 255, 255, 0.06); /* subtle borders */
  --bw-border-strong:rgba(255, 255, 255, 0.10); /* hover borders */

  /* Group accent colors (RogueTrader bot categories) */
  --bw-group-crypto:      #3B82F6;
  --bw-group-equities:    #10B981;
  --bw-group-indexes:     #8B5CF6;
  --bw-group-commodities: #F59E0B;
  --bw-group-forex:       #F43F5E;

  /* FateSwap brand gradient (used in conviction bars, dividers, logo) */
  --bw-brand-gradient: linear-gradient(90deg, #22C55E 0%, #EAB308 50%, #EF4444 100%);
}
```

### Fonts

Add to Blockster's `<head>` (root layout). Both fonts are CDN-hosted, no self-hosting.

```html
<link rel="preconnect" href="https://api.fontshare.com" crossorigin>
<link rel="preconnect" href="https://fonts.googleapis.com" crossorigin>
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>

<!-- Satoshi (RogueTrader + FateSwap display font) -->
<link href="https://api.fontshare.com/v2/css?f[]=satoshi@400,500,700,900&display=swap" rel="stylesheet">

<!-- JetBrains Mono (numbers / prices / data) -->
<link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;500;600;700&display=swap" rel="stylesheet">
```

Tailwind class hooks (added to widget CSS):
```css
.bw-widget { --bw-font-display: 'Satoshi', system-ui, sans-serif; --bw-font-mono: 'JetBrains Mono', ui-monospace, monospace; }
.bw-display { font-family: var(--bw-font-display); }
.bw-mono { font-family: var(--bw-font-mono); font-variant-numeric: tabular-nums; }
```

### Shared utility classes

```css
.bw-card        { background: var(--bw-card); border: 1px solid var(--bw-border); border-radius: 0.75rem; }
.bw-card-hover  { transition: background 0.18s ease; }
.bw-card-hover:hover { background: var(--bw-row-hover); }
.bw-shell       { background: var(--bw-bg); border-radius: 1rem; overflow: hidden;
                  box-shadow: 0 30px 60px -15px rgba(0,0,0,0.35), 0 12px 25px -8px rgba(0,0,0,0.20); }
.bw-shell-bg-grid { background-image: radial-gradient(circle at center, rgba(255,255,255,0.03) 1px, transparent 1.2px);
                    background-size: 14px 14px; }

/* Pulse pill (LIVE indicator) — scoped */
@keyframes bw-pulse-dot { 0%,100% { opacity: 1; transform: scale(1); } 50% { opacity: .6; transform: scale(1.2); } }
@keyframes bw-pulse-ring { 0% { opacity: .8; transform: scale(1); } 100% { opacity: 0; transform: scale(2.4); } }
.bw-pulse-dot  { animation: bw-pulse-dot 1.6s cubic-bezier(.4,0,.6,1) infinite; }
.bw-pulse-ring { animation: bw-pulse-ring 2s ease-out infinite; }

/* Flash animations for new rows / price changes */
@keyframes bw-flash-new { 0% { background-color: rgba(34,197,94,0.18); } 100% { background-color: transparent; } }
@keyframes bw-flash-up { 0% { color: #22C55E; } 100% { color: var(--bw-green-bright); } }
@keyframes bw-flash-down { 0% { color: #EF4444; } 100% { color: var(--bw-red-bright); } }
.bw-flash-new  { animation: bw-flash-new 3s ease-out 0.3s 1; }
.bw-flash-up   { animation: bw-flash-up 2.4s ease-out 0.5s 1; }
.bw-flash-down { animation: bw-flash-down 2.4s ease-out 0.5s 1; }

/* Custom scrollbar for skyscraper widgets */
.bw-scroll::-webkit-scrollbar { width: 4px; }
.bw-scroll::-webkit-scrollbar-thumb { background: rgba(255,255,255,0.10); border-radius: 2px; }
.bw-scroll::-webkit-scrollbar-thumb:hover { background: rgba(255,255,255,0.20); }
```

### Logo assets

**FateSwap**
- Wordmark (SVG 220×28): `https://fateswap.io/images/logo-full.svg` — 3 bars + FATESWAP text in green/yellow/red gradient
- Bars-only (SVG 26×17): `https://fateswap.io/images/logo-bars.svg`

**RogueTrader**
- Wordmark — render inline as HEEx (matches site nav exactly):
  ```heex
  <span class="bw-display font-bold text-[12px] text-[--bw-primary]">ROGUE</span>
  <span class="bw-display font-semibold text-[7px] text-[--bw-rogue-orange]">TRADER</span>
  ```
- R icon (SVG): `https://roguetrader.io/images/logo.svg` (orange `#FD4F00` brushstroke "R")

All can be embedded via `<img>`. No asset hosting needed in Blockster.

### Mnesia-side: nothing here — pure CSS/asset layer.

---

## Widget Catalog

The framework ships **14 widgets**. Each is a self-contained Phoenix component under `BlocksterV2Web.Widgets.*`, with an optional JS hook (`assets/js/hooks/widgets/*`) for live updates and chart rendering. The `widget_type` column on `ad_banners` selects which widget renders in a placement.

### RogueTrader widgets

| `widget_type` | Component | Dimensions | Placements | Data | Self-selects? | Click |
|---|---|---|---|---|---|---|
| `rt_skyscraper` | `RtSkyscraper` | 200 × ~760 | `sidebar_right`, `sidebar_left`, `play_sidebar_*`, `airdrop_sidebar_*` | All 30 bots, perf-ordered, scrollable, live | ❌ shows all | `roguetrader.io` |
| `rt_square_compact` | `RtSquareCompact` | 200 × 200 | `sidebar_left`, `sidebar_right`, small slots | 1 bot + sparkline + price/change | ✅ top mover | `/bot/:slug` |
| `rt_sidebar_tile` | `RtSidebarTile` | 200 × 300 | `sidebar_left`, `sidebar_right`, `play_sidebar_*`, `airdrop_sidebar_*` (matches article-page discover-card height) | 1 bot + H/L + larger sparkline | ✅ top mover | `/bot/:slug` |
| `rt_chart_landscape` | `RtChartLandscape` | full × 360 (mobile: full × 280) | `article_inline_*`, `homepage_inline_desktop`, `homepage_inline_mobile`, `video_player_top` | 1 bot, full chart + price/change/H/L header + tf pills (image #1 reference) | ✅ best perf bot+tf | `/bot/:slug` |
| `rt_chart_portrait` | `RtChartPortrait` | 440 × 640 (mobile: full × 600) | `article_inline_*`, `homepage_inline_*` | 1 bot, vertical chart card + tf pills (image #2 reference) | ✅ best perf bot+tf | `/bot/:slug` |
| `rt_full_card` | `RtFullCard` | full × ~900 (mobile: full × auto) | `article_inline_*`, `homepage_inline_desktop` | 1 bot, chart + 8-card stats grid (AUM, LP Supply, Rank, CP Liability, Wins/Settled, Win Rate, Volume, Avg Stake) — image #4 reference | ✅ top performer | `/bot/:slug` |
| `rt_ticker` | `RtTicker` | full × 56 (mobile: full × 48) | `homepage_top_desktop`, `homepage_top_mobile`, header strip | All 30 bots, horizontal scrolling marquee with live prices + change % | ❌ shows all | `roguetrader.io` |
| `rt_leaderboard_inline` | `RtLeaderboardInline` | full × ~480 (mobile: full × auto, condensed) | `article_inline_*`, `homepage_inline_*` | Top 10 bots in table form (matches `home_live.ex` desktop row) | ❌ shows top 10 | **per row → `/bot/:slug`** |

### FateSwap widgets

| `widget_type` | Component | Dimensions | Placements | Data | Self-selects? | Click |
|---|---|---|---|---|---|---|
| `fs_skyscraper` | `FsSkyscraper` | 200 × ~760 | `sidebar_left`, `sidebar_right`, `play_sidebar_*`, `airdrop_sidebar_*` | Last 20 trades, scrollable, live (matches `realtime_widgets_mock.html` left widget exactly) | ❌ shows all | `fateswap.io` |
| `fs_hero_portrait` | `FsHeroPortrait` | 440 × 640 (mobile: full × 600) | `article_inline_*`, `homepage_inline_*`, `sidebar_*` (200×anything variant) | 1 order — "ORDER FILLED" / "DISCOUNT FILLED" pill, "Bought X TOKEN" headline, YOU RECEIVED + YOU PAID stacked, PROFIT row (image #5 reference) | ✅ biggest profit | `/orders/:id` |
| `fs_hero_landscape` | `FsHeroLandscape` | full × 480 (mobile: full × auto) | `article_inline_*`, `homepage_inline_desktop`, `video_player_top` | 1 order — "DISCOUNT FILLED" pill, big headline, two-col grid (You paid + You received), Profit + Fill Chance cards, conviction bar with rainbow gradient + quote, FATESWAP footer (image #6 reference) | ✅ biggest profit | `/orders/:id` |
| `fs_ticker` | `FsTicker` | full × 56 (mobile: full × 48) | `homepage_top_desktop`, `homepage_top_mobile` | Last 20 trades scrolling marquee with token logos, side arrows, profit/loss | ❌ shows all | `fateswap.io` |
| `fs_square_compact` | `FsSquareCompact` | 200 × 200 | `sidebar_left`, `sidebar_right`, small slots | 1 order — side arrow + token + bid/ask + profit pill + conviction bar | ✅ biggest profit | `/orders/:id` |
| `fs_sidebar_tile` | `FsSidebarTile` | 200 × 320 | `sidebar_left`, `sidebar_right`, `play_sidebar_*`, `airdrop_sidebar_*` (matches article-page discover-card height) | 1 order — ORDER FILLED pill, headline, Trader Received / Trader Paid (with USD), Profit, conviction bar | ✅ biggest profit | `/orders/:id` |

### Placement × widget compatibility matrix

| Placement | RogueTrader options | FateSwap options |
|---|---|---|
| `sidebar_left` (200) | `rt_skyscraper`, `rt_square_compact`, `rt_sidebar_tile` | `fs_skyscraper`, `fs_square_compact`, `fs_sidebar_tile` |
| `sidebar_right` (200) | `rt_skyscraper`, `rt_square_compact`, `rt_sidebar_tile` | `fs_skyscraper`, `fs_square_compact`, `fs_sidebar_tile` |
| `article_inline_1/2/3` (~720) | `rt_chart_landscape`, `rt_chart_portrait`, `rt_full_card`, `rt_leaderboard_inline` | `fs_hero_landscape`, `fs_hero_portrait` |
| `video_player_top` (~720) | `rt_chart_landscape`, `rt_full_card` | `fs_hero_landscape` |
| `homepage_top_desktop` (full) | `rt_ticker` | `fs_ticker` |
| `homepage_top_mobile` (full mobile) | `rt_ticker` | `fs_ticker` |
| `homepage_inline_desktop` (full) | `rt_chart_landscape`, `rt_full_card`, `rt_leaderboard_inline` | `fs_hero_landscape` |
| `homepage_inline_mobile` (full mobile) | `rt_chart_landscape`, `rt_chart_portrait` | `fs_hero_portrait` |
| `homepage_inline` (legacy ~720) | `rt_chart_landscape`, `rt_leaderboard_inline` | `fs_hero_landscape` |
| `play_sidebar_*` (200) | `rt_skyscraper`, `rt_square_compact`, `rt_sidebar_tile` | `fs_skyscraper`, `fs_square_compact`, `fs_sidebar_tile` |
| `airdrop_sidebar_*` (200) | `rt_skyscraper`, `rt_square_compact`, `rt_sidebar_tile` | `fs_skyscraper`, `fs_square_compact`, `fs_sidebar_tile` |

The renderer doesn't enforce this matrix — it's a guideline for admin UI dropdowns. Any `widget_type` will render in any placement; widgets are responsive within their declared dimension targets.

---

## Self-Selection Logic

Widgets that show a single bot/order (`rt_chart_*`, `rt_full_card`, `rt_square_compact`, `fs_hero_*`) need to dynamically pick the most compelling subject. Selection happens on every poll cycle and is cached in Mnesia so all renders for a given widget instance see the same pick.

### Selection modes (set per banner via `widget_config.selection`)

**RogueTrader:**
- `biggest_gainer` *(default)* — scan all 30 bots × {1H, 6H, 24H, 48H, 7D}, pick the (bot, tf) combo with the largest **positive** % change. Return `{bot_id, tf}`.
- `biggest_mover` — same scan, but rank by `abs(% change)` (gainers OR losers).
- `highest_aum` — bot with the largest `sol_balance`. Default tf: `7D`.
- `top_ranked` — bot at rank 1 by `lp_price`. Default tf: `24H`.
- `fixed` — pin a specific bot. Requires `widget_config.bot_id` (e.g., `"kronos"`). Default tf from `widget_config.timeframe` or `7D`.

**FateSwap:**
- `biggest_profit` *(default)* — scan last 100 settled orders, pick the one with the largest **positive** `profit_lamports` (or `payout - sol_amount` if profit isn't a column). Return `{order_id}`.
- `biggest_discount` — pick the order with the largest `discount_pct` for buys (largest positive multiplier).
- `most_recent_filled` — most recent settled `filled: true` order.
- `random_recent` — random pick from last 20 settled (rotation effect).
- `fixed` — pin a specific `order_id`.

### Implementation

`lib/blockster_v2/widgets/widget_selector.ex` — pure module, no GenServer:

```elixir
defmodule BlocksterV2.Widgets.WidgetSelector do
  alias BlocksterV2.Widgets.{RogueTraderBotsTracker, RogueTraderChartTracker, FateSwapFeedTracker}

  # Returns {bot_id, timeframe} or nil
  def pick_rt(:biggest_gainer, _config) do
    bots = RogueTraderBotsTracker.get_bots()
    timeframes = ~w(1h 6h 24h 48h 7d)a

    candidates =
      for bot <- bots, tf <- timeframes do
        change = pct_change(bot, tf)        # reads cached chart history
        {bot.bot_id, tf, change}
      end

    candidates
    |> Enum.filter(fn {_, _, c} -> is_number(c) end)
    |> Enum.max_by(fn {_, _, c} -> c end, fn -> nil end)
    |> case do
         {bot_id, tf, _} -> {bot_id, tf}
         nil -> nil
       end
  end

  def pick_rt(:biggest_mover, config), do: # ... rank by abs(change)
  def pick_rt(:highest_aum, _config),  do: # ... pick max sol_balance
  def pick_rt(:fixed, %{"bot_id" => id, "timeframe" => tf}), do: {id, tf || "7d"}

  # Returns order_id or nil
  def pick_fs(:biggest_profit, _config) do
    FateSwapFeedTracker.get_trades()
    |> Enum.max_by(& &1.profit_lamports, fn -> nil end)
    |> case do
         %{id: id} -> id
         nil -> nil
       end
  end

  def pick_fs(:biggest_discount, _config), do: # ...
  def pick_fs(:fixed, %{"order_id" => id}),  do: id
end
```

### Cache key & PubSub

For each banner instance, the picked subject is cached and broadcast:

```
Mnesia table widget_selections: {banner_id, picked_at, subject}
PubSub topic "widgets:selection:#{banner_id}" → {:selection_changed, subject}
```

The pollers (`RogueTraderBotsTracker`, `FateSwapFeedTracker`) re-run selection at the end of every successful poll for every active banner. If the pick changed since last poll, broadcast.

`PostLive.Show` and `PostLive.Index` subscribe to `widgets:selection:#{banner_id}` for any banner currently rendered, then `push_event` to the JS hook so the chart can switch bots without a full page re-render.

### Why this matters

Without self-selection, every chart widget on the homepage would always show "KRONOS-LP 7D" forever. With it, the homepage rotates through the most exciting bot/timeframe combos automatically — closer to a curated CNBC-style ticker than a static ad.

---

## Architecture overview

```
┌──────────────────────────────┐    ┌──────────────────────────────┐
│  FateSwap (ord)              │    │  RogueTrader (iad)           │
│  Phoenix LiveView            │    │  Phoenix LiveView            │
│                              │    │                              │
│  GET /api/feed/recent        │    │  GET /api/bots               │
│  GET /api/orders/:id         │    │  GET /api/bots/:id/chart     │
│  (NEW endpoints, public)     │    │      ?tf=1h|6h|24h|48h|7d    │
│                              │    │  GET /api/bots/:id           │
│                              │    │  (all NEW, public)           │
└────────────┬─────────────────┘    └────────────┬─────────────────┘
             │ HTTPS                              │ HTTPS
             │ feed: poll 3s                      │ snapshot: poll 10s
             │ order detail: on-demand            │ chart: poll 60s
             ▼                                    ▼
   ┌──────────────────────────────────────────────────────────────┐
   │  Blockster V2 (ord)                                          │
   │                                                              │
   │  ┌────────────────────────────────────────────────────────┐  │
   │  │ Pollers (all GlobalSingleton, supervised):             │  │
   │  │  · FateSwapFeedTracker        (3s)  → feed snapshot    │  │
   │  │  · RogueTraderBotsTracker     (10s) → bot snapshots    │  │
   │  │  · RogueTraderChartTracker    (60s) → per-bot per-tf   │  │
   │  │    history series (5 tfs × 30 bots = 150 series)       │  │
   │  │                                                        │  │
   │  │ At end of each poll:                                   │  │
   │  │  · diff vs last snapshot                               │  │
   │  │  · write to Mnesia cache                               │  │
   │  │  · re-run WidgetSelector for every active banner       │  │
   │  │  · broadcast on PubSub                                 │  │
   │  └────────────┬───────────────────────────────────────────┘  │
   │               │                                              │
   │               ▼                                              │
   │  Phoenix.PubSub topics                                       │
   │   "widgets:fateswap:feed"        → {:fs_trades, list}        │
   │   "widgets:roguetrader:bots"     → {:rt_bots, list}          │
   │   "widgets:roguetrader:chart:#{bot}_#{tf}" → {:rt_chart, …}  │
   │   "widgets:selection:#{banner_id}" → {:selection_changed,…}  │
   │               │                                              │
   │               ▼                                              │
   │  Each LiveView (PostLive.Show, PostLive.Index, …) on mount:  │
   │   · loads active banners for its placements                  │
   │   · subscribes to relevant data topics + per-banner topic    │
   │                                                              │
   │               │                                              │
   │               ▼                                              │
   │  push_event("widget:#{banner_id}:data", payload)             │
   │  push_event("widget:#{banner_id}:select", subject)           │
   │               │                                              │
   │               ▼                                              │
   │  JS hooks under assets/js/hooks/widgets/*                    │
   │   · skyscraper hooks animate row in/out (FLIP-style)         │
   │   · chart hooks render lightweight-charts Area series        │
   │   · ticker hooks animate marquee scroll                      │
   │   · hero card hooks animate price flash + new-card swap      │
   └──────────────────────────────────────────────────────────────┘
```

**Why polling and not webhooks/clustering**: simplicity, decoupling, no shared infra, no cross-region clustering fragility (RogueTrader is `iad`, Blockster + FateSwap are `ord`). A 3–10s lag on a widget is invisible.

**Why a separate chart tracker**: chart history is much heavier than a snapshot (300+ datapoints per bot per timeframe). 60s cadence is plenty — the chart's last point is always the live snapshot from the bot tracker, so the chart never looks stale.

---

## Backend changes

### A. FateSwap — new public API endpoints

Three new endpoints, all under the existing `scope "/api", FateSwapWeb` block in `lib/fateswap_web/router.ex`. All public, read-only.

**File 1: `lib/fateswap_web/controllers/api/feed_controller.ex`** *(new)*
- `GET /api/feed/recent?limit=20` — last N settled orders (default 20, max 100)
- `GET /api/feed/top_profit?window=1h` — single order with biggest profit in window (used by `WidgetSelector` for `biggest_profit`)
- `GET /api/feed/top_discount?window=1h` — single order with biggest discount in window

**File 2: `lib/fateswap_web/controllers/api/orders_controller.ex`** *(new)*
- `GET /api/orders/:id` — full detail for one order (used by `fs_hero_*` widgets when `selection: fixed` or after self-selection)

**Serializer** (shared, includes everything `fs_hero_landscape` needs):
```elixir
defp serialize_trade(order) do
  profit_lamports = order.payout - order.sol_amount
  multiplier = order.multiplier_bps / 100_000.0
  fill_chance_pct = compute_fill_chance(order)        # uses commitment math

  %{
    id: order.id,
    side: order.side,                              # "buy" | "sell"
    status_text: status_text(order.side, order.filled),  # "DISCOUNT FILLED" | "ORDER FILLED" | "NOT FILLED"
    filled: order.filled,
    token_symbol: order.token_symbol,
    token_logo_url: order.token_logo_url,
    token_decimals: order.token_decimals,
    token_amount_sold: order.token_amount_sold,
    sol_amount: order.sol_amount,
    sol_amount_ui: order.sol_amount / 1_000_000_000,
    payout: order.payout,
    payout_ui: order.payout / 1_000_000_000,
    multiplier: multiplier,                        # 1.10 etc.
    discount_pct: discount_pct(order),             # for buys
    profit_lamports: profit_lamports,
    profit_ui: profit_lamports / 1_000_000_000,
    profit_pct: profit_pct(order),
    sol_price_usd: order.sol_price_usd,
    token_price_usd: order.token_price_usd,
    received_usd: received_usd(order),
    paid_usd: paid_usd(order),
    profit_usd: profit_lamports / 1_000_000_000 * order.sol_price_usd,
    fill_chance_pct: fill_chance_pct,
    conviction_label: FateSwap.Social.Quotes.conviction_label(multiplier),
    quote: FateSwap.Social.Quotes.random_quote(order),    # "Fate loves a bargain hunter."
    wallet_address: order.wallet_address,
    wallet_truncated: truncate(order.wallet_address),
    referral_code: order.referral_code,
    settled_at: order.settled_at
  }
end
```

**`status_text`** mirrors `trade_components.ex`:
```elixir
defp status_text("buy", true), do: "DISCOUNT FILLED"
defp status_text(_side, true), do: "ORDER FILLED"
defp status_text(_, false),    do: "NOT FILLED"
```

**Router additions**:
```elixir
scope "/api", FateSwapWeb do
  pipe_through :api
  get "/feed/recent", Api.FeedController, :recent
  get "/feed/top_profit", Api.FeedController, :top_profit
  get "/feed/top_discount", Api.FeedController, :top_discount
  get "/orders/:id", Api.OrdersController, :show
end
```

**CORS**: `cors_plug` on the `:api` pipeline allowing `GET` from `https://blockster.com` and `http://localhost:4000`. (FateSwap has no CORS today — server-to-server polling makes it optional, but adding it costs nothing and unlocks future browser-side widgets.)

**Rate limit**: existing `Hammer` if present, otherwise simple `RateLimiter` plug at 120 req/min per IP. Blockster polls at 3s = 20 req/min from one node.

---

### B. RogueTrader — new public API endpoints

Three new endpoints under a new `scope "/api"` block in `lib/roguetrader_web/router.ex` (today only `/api/verify/account/:address` exists).

**File 1: `lib/roguetrader_web/controllers/api/bots_controller.ex`** *(new)*
- `GET /api/bots` — snapshot of all 30 bots (current prices, AUM, change %, market state)
- `GET /api/bots/:id` — full detail for one bot (everything `rt_full_card` needs)

**File 2: `lib/roguetrader_web/controllers/api/charts_controller.ex`** *(new)*
- `GET /api/bots/:id/chart?tf=1h|6h|24h|48h|7d` — price history series for one bot at one timeframe

**Bot snapshot serializer** (`/api/bots`):
```elixir
defp serialize_bot(stats, meta) do
  %{
    bot_id: stats["bot_id"],
    slug: meta.slug || meta.bot_id,
    name: meta.name,
    group_id: meta.group_id,
    group_name: meta.group_name,
    group_color: group_color(meta.group_name),
    archetype: meta.archetype,
    risk_level: meta.risk_level,                       # "Low" | "Med" | "High"
    strategy_description: meta.strategy_description,
    lp_price: stats["lp_price"],
    bid_price: bid(stats["lp_price"]),
    ask_price: ask(stats["lp_price"]),
    lp_price_change_1h_pct: stats["lp_price_change_1h_pct"],
    lp_price_change_6h_pct: stats["lp_price_change_6h_pct"],
    lp_price_change_24h_pct: stats["lp_price_change_24h_pct"],
    lp_price_change_48h_pct: stats["lp_price_change_48h_pct"],
    lp_price_change_7d_pct: stats["lp_price_change_7d_pct"],
    lp_supply: stats["lp_supply"],
    sol_balance: stats["sol_balance"],
    sol_balance_ui: stats["sol_balance"] / 1_000_000_000,
    counterparty_locked_sol: stats["counterparty_locked_sol"],
    win_rate: stats["win_rate"],
    wins_settled_7d: %{wins: stats["wins_7d"], total: stats["settled_7d"]},
    volume_7d_sol: stats["volume_7d"] / 1_000_000_000,
    avg_stake_7d_sol: stats["avg_stake_7d"] / 1_000_000_000,
    active_bet_count: stats["active_bet_count"],
    market_open: stats["market_open"],
    rank: stats["rank"]
  }
end
```

The 1h/6h/24h/48h/7d change fields may not exist in `StatsTracker` today — the controller computes them from chart history if missing. **Action item**: add change fields to `StatsTracker.get_all_stats/0` so the API can return them without computation.

**Chart series serializer** (`/api/bots/:id/chart`):
```elixir
def show(conn, %{"id" => bot_id, "tf" => tf}) do
  points = ChartHistory.fetch(bot_id, tf)            # [%{time: unix, value: lp_price}, ...]
  json(conn, %{
    bot_id: bot_id,
    timeframe: tf,
    points: points,
    high: Enum.max_by(points, & &1.value).value,
    low:  Enum.min_by(points, & &1.value).value,
    change_pct: pct_change(points),
    fetched_at: DateTime.utc_now()
  })
end
```

`ChartHistory.fetch/2` reads from RogueTrader's existing chart Mnesia table (the same one `BotChart` JS hook uses). If a separate persistence layer doesn't exist for chart points, **action item**: add one — even a simple ETS ring buffer per (bot, tf) is enough.

**Router additions**:
```elixir
scope "/api", RogueTraderWeb do
  pipe_through :api
  get "/bots", Api.BotsController, :index
  get "/bots/:id", Api.BotsController, :show
  get "/bots/:id/chart", Api.ChartsController, :show
end
```

**CORS + rate limit**: same as FateSwap. Blockster polls bots at 10s (6 req/min) and chart at 60s × 5 tfs × 30 bots = 150 req/min total — bursty, recommend rate limit at 300 req/min per IP.

---

### C. Blockster — new poller GenServers

Three new GenServers + one selector module + one Mnesia helper, all under `lib/blockster_v2/widgets/`. All GenServers run as `GlobalSingleton` (one per cluster, rolling-deploy safe).

#### `lib/blockster_v2/widgets/fateswap_feed_tracker.ex`
- Polls `GET /api/feed/recent?limit=20` every **3 s**
- State: `%{trades: [], last_fetched_at: nil, last_error: nil}`
- On change: writes Mnesia cache, broadcasts `{:fs_trades, trades}` on `"widgets:fateswap:feed"`
- Re-runs `WidgetSelector.pick_fs/2` for every active FateSwap banner — broadcasts `"widgets:selection:#{banner_id}"` if pick changed
- Public API: `get_trades/0`, `get_top_profit_order/0`, `get_top_discount_order/0`
- On error: log + keep serving stale cache (do not crash)
- Mnesia table `widget_fs_feed_cache` — `{:singleton, trades, fetched_at}`

#### `lib/blockster_v2/widgets/roguetrader_bots_tracker.ex`
- Polls `GET /api/bots` every **10 s**
- State: `%{bots: [], last_fetched_at: nil, last_error: nil}`
- On change: writes Mnesia cache, broadcasts `{:rt_bots, bots}` on `"widgets:roguetrader:bots"`
- Re-runs `WidgetSelector.pick_rt/2` for every active RogueTrader banner
- Public API: `get_bots/0`, `get_bot/1`, `get_top_gainer/0`, `get_top_mover/0`, `get_top_aum/0`
- Mnesia table `widget_rt_bots_cache`

#### `lib/blockster_v2/widgets/roguetrader_chart_tracker.ex` *(NEW in v2)*
- Polls `GET /api/bots/:id/chart?tf=:tf` every **60 s** for **30 bots × 5 timeframes = 150 series**
- Stagger requests across the 60 s window (avg 2.5/s) to not hammer RogueTrader
- State: `%{series: %{{bot_id, tf} => [%{time, value}, ...]}, last_fetched_at, errors}`
- Topic: `"widgets:roguetrader:chart:#{bot_id}_#{tf}"` → `{:rt_chart, bot_id, tf, points}`
- Public API: `get_series/2`, `get_change_pct/2`, `get_high_low/2`
- Mnesia table `widget_rt_chart_cache` — `{{bot_id, tf}, points, fetched_at}` ordered_set
- **Why 60 s and not 10 s**: chart data is heavy (300+ points × 150 series = ~45k data points) and the chart's last point is always the live snapshot from the bot tracker — the chart never looks stale.

#### `lib/blockster_v2/widgets/widget_selector.ex` *(see [Self-Selection Logic](#self-selection-logic) above)*
- Pure module, no GenServer
- Called by both trackers at the end of every poll
- Looks up active banners via `BlocksterV2.Ads.list_widget_banners/0`
- For each banner with a self-selecting `widget_type`, computes the new pick from `widget_config.selection`
- Caches result in Mnesia table `widget_selections` and broadcasts on `"widgets:selection:#{banner_id}"` if changed

#### `lib/blockster_v2/widgets/mnesia_init.ex`
- Helper called from `BlocksterV2.MnesiaInitializer` to create the four new tables on cluster boot:
  - `widget_fs_feed_cache`
  - `widget_rt_bots_cache`
  - `widget_rt_chart_cache`
  - `widget_selections`

**Supervision**: register all three trackers in `application.ex` under `BlocksterV2.GlobalSingleton` (the same pattern used by `LpPriceTracker`, `BuxBoosterBetSettler`, etc.).

**Config**: add to `runtime.exs`:
```elixir
config :blockster_v2, :widgets,
  fateswap_base_url:        System.get_env("FATESWAP_API_URL",    "https://fateswap.io"),
  roguetrader_base_url:     System.get_env("ROGUETRADER_API_URL", "https://roguetrader.io"),
  fateswap_poll_interval_ms:    3_000,
  roguetrader_bots_poll_interval_ms:  10_000,
  roguetrader_chart_poll_interval_ms: 60_000,
  http_timeout_ms: 5_000
```

---

### D. Banners table — schema additions

**Migration** `priv/repo/migrations/{ts}_add_widget_columns_to_ad_banners.exs`:
```elixir
def change do
  alter table(:ad_banners) do
    add :widget_type,   :string             # nil for normal image-based ads; one of @valid_widget_types
    add :widget_config, :map, default: %{}  # selection mode, fixed bot_id/order_id/timeframe, etc.
  end

  # image_url becomes optional when widget_type is set — handled in changeset, not DB
  create index(:ad_banners, [:widget_type])
end
```

**Schema** `lib/blockster_v2/ads/banner.ex`:
```elixir
@valid_widget_types ~w(
  rt_skyscraper rt_square_compact rt_chart_landscape rt_chart_portrait
  rt_full_card rt_ticker rt_leaderboard_inline
  fs_skyscraper fs_hero_portrait fs_hero_landscape fs_ticker
)

field :widget_type,   :string
field :widget_config, :map, default: %{}

def changeset(banner, attrs) do
  banner
  |> cast(attrs, [..., :widget_type, :widget_config])
  |> validate_inclusion(:widget_type, [nil | @valid_widget_types])
  |> maybe_validate_image_url()       # only required when widget_type is nil
end

defp maybe_validate_image_url(changeset) do
  case get_field(changeset, :widget_type) do
    nil -> validate_required(changeset, [:image_url])
    _   -> changeset                  # image_url ignored for widget rows
  end
end
```

**Context** `lib/blockster_v2/ads.ex` — additions:
```elixir
# Returns all active banners that have a widget_type (used by WidgetSelector)
def list_widget_banners do
  Repo.all(
    from b in Banner,
    where: b.is_active == true and not is_nil(b.widget_type)
  )
end

# Existing list_active_banners_by_placement/1 unchanged — the template-renderer
# branches on banner.widget_type to dispatch to the widget component.
```

**Tracking**: `increment_impressions/1` and `increment_clicks/1` are reused as-is. Widget rows accumulate metrics in the same `impressions` / `clicks` columns.

**Admin UI** (`/admin/banners` LiveView): add a "Widget Type" dropdown above the Template dropdown. When Widget Type is set:
- Hide Template, Image URL, Params fields
- Show Widget Config form: `selection` dropdown (biggest_gainer / biggest_mover / etc.), conditional `bot_id` / `order_id` / `timeframe` inputs when selection = `fixed`
- Live preview pane on the right rendering the widget at its target dimensions

---

### E. LiveView integration (PostLive.Show, PostLive.Index, video player)

A shared macro `BlocksterV2Web.WidgetEvents` (`lib/blockster_v2_web/live/widget_events.ex`) provides `use BlocksterV2Web.WidgetEvents` on any LiveView that renders widgets. It handles:
- Subscribing to relevant PubSub topics on `connected?(socket)` mount
- Loading initial data from Mnesia caches (so first paint isn't empty)
- `handle_info` clauses for all widget data + selection updates
- `handle_event("widget_click", %{"banner_id" => id, "subject" => subj})` → records click + builds redirect URL

Used by:
- `lib/blockster_v2_web/live/post_live/show.ex` (article page — sidebars + inline + video_player_top)
- `lib/blockster_v2_web/live/post_live/index.ex` (homepage — top banners + inline)
- Any future LiveView that wants widgets

#### Macro shape

```elixir
defmodule BlocksterV2Web.WidgetEvents do
  defmacro __using__(_) do
    quote do
      alias BlocksterV2.Widgets.{FateSwapFeedTracker, RogueTraderBotsTracker, RogueTraderChartTracker}

      def mount_widgets(socket, banners) do
        if connected?(socket) do
          # Subscribe to data topics
          Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "widgets:fateswap:feed")
          Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "widgets:roguetrader:bots")

          # Per-banner: subscribe to selection topic + chart topic for current pick
          for banner <- banners, banner.widget_type do
            Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "widgets:selection:#{banner.id}")
            BlocksterV2.Ads.increment_impressions(banner.id)
          end
        end

        socket
        |> assign(:fs_trades, FateSwapFeedTracker.get_trades())
        |> assign(:rt_bots, RogueTraderBotsTracker.get_bots())
        |> assign(:widget_selections, load_initial_selections(banners))
        |> assign(:widget_chart_data, load_initial_chart_data(banners))
      end

      @impl true
      def handle_info({:fs_trades, trades}, socket) do
        {:noreply,
         socket
         |> assign(:fs_trades, trades)
         |> push_event("widget:fs_feed:update", %{trades: trades})}
      end

      @impl true
      def handle_info({:rt_bots, bots}, socket) do
        {:noreply,
         socket
         |> assign(:rt_bots, bots)
         |> push_event("widget:rt_bots:update", %{bots: bots})}
      end

      @impl true
      def handle_info({:rt_chart, bot_id, tf, points}, socket) do
        {:noreply,
         push_event(socket, "widget:rt_chart:update", %{bot_id: bot_id, tf: tf, points: points})}
      end

      @impl true
      def handle_info({:selection_changed, banner_id, subject}, socket) do
        # Subject is {bot_id, tf} or order_id depending on widget family.
        # Subscribe to the new chart topic, fetch chart data, push to client.
        new_selections = Map.put(socket.assigns.widget_selections, banner_id, subject)

        case subject do
          {bot_id, tf} ->
            Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "widgets:roguetrader:chart:#{bot_id}_#{tf}")
            points = RogueTraderChartTracker.get_series(bot_id, tf)
            {:noreply,
             socket
             |> assign(:widget_selections, new_selections)
             |> push_event("widget:#{banner_id}:select", %{bot_id: bot_id, tf: tf, points: points})}

          order_id when is_binary(order_id) ->
            order = FateSwapFeedTracker.get_order(order_id)
            {:noreply,
             socket
             |> assign(:widget_selections, new_selections)
             |> push_event("widget:#{banner_id}:select", %{order: order})}
        end
      end

      @impl true
      def handle_event("widget_click", %{"banner_id" => id, "subject" => subj}, socket) do
        BlocksterV2.Ads.increment_clicks(id)
        {:noreply, redirect(socket, external: BlocksterV2.Widgets.ClickRouter.url_for(id, subj))}
      end
    end
  end
end
```

#### `BlocksterV2.Widgets.ClickRouter`

Builds the click destination per [Decision #7](#decisions-locked-in-v2):

```elixir
defmodule BlocksterV2.Widgets.ClickRouter do
  @rt_base "https://roguetrader.io"
  @fs_base "https://fateswap.io"

  def url_for(_banner_id, {bot_id, _tf}) when is_binary(bot_id), do: "#{@rt_base}/bot/#{bot_id}"
  def url_for(_banner_id, order_id) when is_binary(order_id),     do: "#{@fs_base}/orders/#{order_id}"
  def url_for(_banner_id, :rt), do: @rt_base
  def url_for(_banner_id, :fs), do: @fs_base
end
```

#### Template changes

- **`show.html.heex`**: delete the entire static `rt-widget` block (lines 979–1180), replace with the dynamic banner-renderer dispatch (see [Section F](#f-widget-components)). Same dispatch goes in the left sidebar slot, plus new `video_player_top` slot above the article video.
- **`index.html.heex`**: replace `<.ad_banner banner={first_ad} />` calls with the dispatcher. Top desktop / top mobile banners can now be `rt_ticker` / `fs_ticker`.

The dispatcher `<.widget_or_ad banner={banner} ... />` lives in `WidgetComponents` and falls back to the existing `<.ad_banner />` when `widget_type` is nil — zero changes to existing image ads.

---

### F. Widget components

All widgets live under `lib/blockster_v2_web/components/widgets/` — one file per widget for clarity (14 files). They're aggregated in `lib/blockster_v2_web/components/widget_components.ex` which exposes the dispatcher.

```elixir
defmodule BlocksterV2Web.WidgetComponents do
  use Phoenix.Component
  import BlocksterV2Web.Widgets.{
    RtSkyscraper, RtSquareCompact, RtChartLandscape, RtChartPortrait,
    RtFullCard, RtTicker, RtLeaderboardInline,
    FsSkyscraper, FsHeroPortrait, FsHeroLandscape, FsTicker
  }

  attr :banner, :map, required: true
  attr :rest, :global

  def widget_or_ad(%{banner: %{widget_type: nil}} = assigns) do
    # Falls back to existing image-based ad renderer
    ~H"<BlocksterV2Web.DesignSystem.ad_banner banner={@banner} />"
  end

  def widget_or_ad(%{banner: %{widget_type: "rt_skyscraper"}} = assigns),
    do: ~H"<.rt_skyscraper banner={@banner} {@rest} />"

  def widget_or_ad(%{banner: %{widget_type: "rt_chart_landscape"}} = assigns),
    do: ~H"<.rt_chart_landscape banner={@banner} {@rest} />"

  # ... one clause per widget_type
end
```

Each widget component:
- Receives `banner`, plus any data assigns it needs (`bots`, `selection`, `chart_points`)
- Wraps its root in `<div class="bw-widget bw-shell" id={"widget-#{@banner.id}"} phx-hook={hook_name}>` — scope CSS + attach JS hook
- Includes `data-banner-id`, `data-widget-type`, plus selection-specific data attrs so the hook knows what to render
- Click target is `<a phx-click="widget_click" phx-value-banner_id={@banner.id} phx-value-subject={subject_for(@banner)}>` so click tracking + redirect goes through the WidgetEvents macro

Per-widget HEEx specs follow. Tailwind classes use the widget tokens defined in [Design Tokens](#design-tokens-fonts--assets-shared-across-both-widget-families). Sizes/text/spacing are taken verbatim from the source projects.

#### `rt_skyscraper` (replaces existing static rt-widget)

Header (logo + LIVE pill) + scrollable body of all 30 bots, ranked by `lp_price` desc. Each row matches the existing mock in `realtime_widgets_mock.html` lines 600–800 (rank + group dot + name + risk tag + 3-col bid/ask/AUM grid + change% + market dot). New rows: re-sort with FLIP animation; price changes flash green/red.

```heex
<div class="bw-widget bw-shell flex flex-col w-[200px] h-[760px]"
     id={"widget-#{@banner.id}"}
     phx-hook="RtSkyscraperWidget"
     data-banner-id={@banner.id}>
  <.widget_header brand="rt" subtitle="TOP ROGUEBOTS" updated_ago={@updated_ago} />
  <div class="bw-scroll flex-1 overflow-y-auto">
    <div :for={bot <- @bots} class="bw-card bw-card-hover px-2.5 py-2.5 border-b border-[--bw-border]">
      <%!-- exact mock structure --%>
    </div>
  </div>
  <.widget_footer brand="rt" tagline="30 AI agents trading crypto, stocks, forex, commodities." link_text="Open RogueTrader" link_href="https://roguetrader.io" />
</div>
```

#### `rt_square_compact` (200×200)

One bot card with sparkline. Header: bot name + risk tag. Body: large bid/ask, 24h change %, mini Area chart sparkline (60 points, 100×40 SVG). Footer: market open dot.

#### `rt_chart_landscape` (full × 360, mobile full × 280) — image #1

Two-column header (left: bot name + bid/ask/change%, right: tf pills 1H/6H/24H/48H/7D), big chart below. Tailwind matches `bot_live.ex` lines 927–972 verbatim. Chart container has `phx-hook="RtChartWidget"` + `phx-update="ignore"`.

#### `rt_chart_portrait` (440×640, mobile full × 600) — image #2

Same as landscape but vertical: bot label and price stacked at top, tf pills below as a row, chart fills remaining space. Slightly smaller chart canvas.

#### `rt_full_card` (full × ~900, mobile auto) — image #4

Full bot detail card. Header (price + change + H/L + tf pills) → chart → 2×4 stats grid (AUM, LP Supply, Rank, CP Liability, Wins/Settled, Win Rate, Volume, Avg Stake). Stats use the `stat_card` snippet from `bot_live.ex` lines 1448–1469 verbatim. Footer pinned with "View on RogueTrader →" link.

#### `rt_ticker` (full × 56, mobile full × 48)

Horizontal CSS marquee `@keyframes bw-marquee-scroll` (left → right, 60s loop). Each ticker item: bot name + bid (green) / ask (red) + change% pill. Hover pauses. CSS-only animation, no JS hook needed for the scroll itself — only for live data updates.

#### `rt_leaderboard_inline` (full × 480, mobile auto condensed)

Top 10 bots in a table matching `home_live.ex` desktop row (lines 522–621). Mobile collapses to a 2-column card grid. Header: "Top RogueBots" + "View all 30 →" link.

#### `fs_skyscraper` (200 × 760)

Live trade feed. Matches `realtime_widgets_mock.html` left widget exactly (lines 200–600). Each row: side arrow + side+token label, filled/unfilled tag, price line `0.50 → 0.55`, gain/loss with USD eq, wallet truncated + relative time. `bw-flash-new` animation on incoming rows.

#### `fs_hero_portrait` (440×640, mobile full × 600) — image #5

```
┌─────────────────────────────────┐
│        [ ORDER FILLED ]         │  ← green pill
│                                 │
│      Bought 669.36 BULL         │  ← Satoshi 700, 32px
│        at 9.1% discount         │  ← Satoshi 500, 16px
│                                 │
│ ┌─────────────────────────────┐ │
│ │ YOU RECEIVED   669.36 BULL  │ │  ← bg-bw-green/10
│ │                ≈ $4.72      │ │
│ └─────────────────────────────┘ │
│ ┌─────────────────────────────┐ │
│ │ YOU PAID       0.0500 SOL   │ │  ← bg-white/5
│ │                ≈ $4.29      │ │
│ └─────────────────────────────┘ │
│  ─────────────────────────────  │
│  PROFIT     +60.85 BULL (+10%)  │  ← green
│             ≈ $0.43             │
└─────────────────────────────────┘
```

Pull from `trade_components.ex` HEEx verbatim — tokens, padding, font weights all match `fateswap.io` settled-order overlay. The "ORDER FILLED" / "DISCOUNT FILLED" / "NOT FILLED" pill comes from the API's `status_text` field.

#### `fs_hero_landscape` (full × 480, mobile auto) — image #6

Wider variant. "DISCOUNT FILLED" pill (smaller, top-left) + big 56px headline ("Bought 17.2 USD1 at 6.5% discount") spanning full width. Two-col grid (You paid / You received) below. Two-col grid below that (Profit / Fill Chance). Then "Conviction: Conservative" label + 4px-tall rainbow gradient bar (green→yellow→red — `var(--bw-brand-gradient)`). Italic quote ("Fate loves a bargain hunter."). Thin 2px gradient divider. Footer row: FATESWAP wordmark + "Memecoin trading on steroids." tagline + ref link `fateswap.io/?ref={code}` right-aligned. Mirrors `share_card_generator.ex` SVG output as HTML.

#### `fs_ticker` (full × 56, mobile full × 48)

Same marquee pattern as `rt_ticker`. Each item: side arrow + token logo + token symbol + amount + profit/loss pill. Loops last 20 settled orders.

---

### G. JS hooks

All widget hooks live under `assets/js/hooks/widgets/` and are registered in `assets/js/app.js`:

```js
import { RtSkyscraperWidget } from "./hooks/widgets/rt_skyscraper.js"
import { RtSquareCompactWidget } from "./hooks/widgets/rt_square_compact.js"
import { RtChartWidget } from "./hooks/widgets/rt_chart.js"      // shared by landscape, portrait, full_card
import { RtTickerWidget } from "./hooks/widgets/rt_ticker.js"
import { RtLeaderboardWidget } from "./hooks/widgets/rt_leaderboard.js"
import { FsSkyscraperWidget } from "./hooks/widgets/fs_skyscraper.js"
import { FsHeroWidget } from "./hooks/widgets/fs_hero.js"          // shared by portrait, landscape
import { FsTickerWidget } from "./hooks/widgets/fs_ticker.js"

const Hooks = {
  ...existing,
  RtSkyscraperWidget, RtSquareCompactWidget, RtChartWidget,
  RtTickerWidget, RtLeaderboardWidget,
  FsSkyscraperWidget, FsHeroWidget, FsTickerWidget,
}
```

#### Hook responsibilities

| Hook | What it does |
|---|---|
| `RtSkyscraperWidget` | Listens for `widget:rt_bots:update`. Reconciles bot list — new rank order via FLIP animation. Flashes price cells green/red on change. |
| `RtSquareCompactWidget` | Same data subscription. Updates price + % + sparkline (uses lightweight-charts mini Area series). Re-renders sparkline on each new datapoint. |
| `RtChartWidget` | Initializes lightweight-charts Area series with RogueTrader's exact config (line color green/red, transparent grid, JetBrains Mono labels). Listens for `widget:rt_chart:update` (full series replacement) and `widget:#{banner_id}:select` (bot/tf changed — fetches new series). Tf pills inside the widget click → `pushEvent("switch_timeframe", {banner_id, tf})` which the LiveView translates to a manual fetch from RogueTraderChartTracker. |
| `RtTickerWidget` | Pure CSS marquee for scroll. JS only swaps text content on `widget:rt_bots:update`. |
| `RtLeaderboardWidget` | Listens for `widget:rt_bots:update`. Re-renders top 10 rows. FLIP rank changes. |
| `FsSkyscraperWidget` | Listens for `widget:fs_feed:update`. Slides new rows in at top with `bw-flash-new`. Drops rows past the 20-row cap with fade-out. |
| `FsHeroWidget` | Listens for `widget:#{banner_id}:select`. Cross-fades in the new order card (250ms). Re-renders all order data fields. |
| `FsTickerWidget` | Same as RtTickerWidget but for trades. |

#### Chart hook implementation note

`RtChartWidget` reuses the exact config from `roguetrader/assets/js/hooks/bot_chart.js`:

```js
import { createChart, AreaSeries } from "lightweight-charts"

mounted() {
  const isUp = this.dataset.changePct >= 0
  const lineColor = isUp ? "#22C55E" : "#EF4444"
  const topColor = isUp ? "rgba(34,197,94,0.15)" : "rgba(239,68,68,0.15)"

  this.chart = createChart(this.el, {
    width: this.el.clientWidth, height: this.el.clientHeight,
    layout: { background: { type: "solid", color: "transparent" },
              textColor: "#6B7280", fontSize: 10, fontFamily: "JetBrains Mono, monospace" },
    grid: { vertLines: { color: "rgba(255,255,255,0.03)" }, horzLines: { color: "rgba(255,255,255,0.03)" } },
    rightPriceScale: { borderColor: "rgba(255,255,255,0.06)", scaleMargins: { top: 0.1, bottom: 0.1 } },
    timeScale: { borderColor: "rgba(255,255,255,0.06)", timeVisible: true, secondsVisible: false },
    handleScroll: false, handleScale: false
  })

  this.series = this.chart.addSeries(AreaSeries, {
    lineColor, topColor, bottomColor: "rgba(0,0,0,0)", lineWidth: 2,
    priceLineVisible: false, lastValueVisible: true
  })

  this.handleEvent(`widget:${this.dataset.bannerId}:select`, ({ points, bot_id, tf }) => {
    this.series.setData(points)
    // Update header price/change/H/L via querySelector — no React, no LiveView re-render needed
  })

  this.handleEvent(`widget:rt_chart:update`, ({ bot_id, tf, points }) => {
    if (bot_id === this.dataset.botId && tf === this.dataset.tf) {
      this.series.setData(points)
    }
  })
}
```

Same library is already in Blockster's bundle (`assets/package.json` includes `lightweight-charts` for the pool charts), so no new dep.

---

### H. Impression / click tracking

**Impression**: handled in the `WidgetEvents` macro on `mount_widgets/2` — one increment per banner per page load. Same as regular banners, same column.

**Click**: every widget root or interactive sub-element has:
```heex
phx-click="widget_click"
phx-value-banner_id={@banner.id}
phx-value-subject={subject_for(@banner)}
```
The `WidgetEvents` macro routes through `ClickRouter.url_for/2` so self-selected widgets land on `/bot/:slug` or `/orders/:id` while all-data widgets land on the project homepage. Click increments the existing `clicks` column.

**Future telemetry (out of scope for v1)**: bubble up `bot_id` / `order_id` into a dedicated `widget_click_events` table to report which entities drive the most click-through. Not needed for launch.

---

## Visual design

> Per-widget visual specs are inline in the [Widget Catalog](#widget-catalog) and [Section F](#f-widget-components) above. Shared design tokens, fonts, and utility classes are in [Design tokens, fonts & assets](#design-tokens-fonts--assets-shared-across-both-widget-families).

**Phase 0** of the build will generate visual mocks for the 9 widgets that don't already exist in `realtime_widgets_mock.html` — using `/frontend-design` and the per-widget spec text — and get user approval before code is written for that widget.

The two skyscraper widgets (`rt_skyscraper`, `fs_skyscraper`) already have approved mocks in `realtime_widgets_mock.html` and can skip Phase 0.

---

## Phased build order

The v2 framework is bigger than v1, so the build is split into **7 phases × ~11 widget mini-phases**. Phase 1 (foundation) is shared; Phases 2–6 ship widgets in groups so we can deploy incrementally and validate before adding more.

### Phase 0 — Visual design ✅ COMPLETE (2026-04-14)

All 14 widget mocks approved by the user. Mock files live in `docs/solana/widgets_mocks/`:

- [x] `rt_chart_landscape_mock.html` — desktop + mobile
- [x] `rt_chart_portrait_mock.html` — desktop + mobile
- [x] `rt_full_card_mock.html` — desktop + mobile
- [x] `rt_square_compact_mock.html` — desktop only
- [x] `rt_sidebar_tile_mock.html` *(added variant — 200 × 300 to match article-page discover-card height)* — desktop only
- [x] `rt_ticker_mock.html` — desktop + mobile
- [x] `rt_leaderboard_inline_mock.html` — desktop + mobile
- [x] `fs_hero_portrait_mock.html` — desktop + mobile, buy + sell variants
- [x] `fs_hero_landscape_mock.html` — desktop + mobile, buy + sell variants
- [x] `fs_ticker_mock.html` — desktop + mobile
- [x] `fs_square_compact_mock.html` *(added variant)* — desktop only
- [x] `fs_sidebar_tile_mock.html` *(added variant)* — desktop only
- [x] `rt_skyscraper` + `fs_skyscraper` — existing v1 `realtime_widgets_mock.html` updated in place (real logos, group tags, compact bot rows, "SOLANA DEX" + "Gamble for a better price than market" brand header, entire skyscraper clickable)

**Locked-in design decisions from Phase 0** (implementation must honor these):
- Bot widgets use the real `ik.imagekit.io/blockster/rogue-logo-white.png` + "TRADER" mono overlay in green `#22C55E`, NOT text-only "ROGUE TRADER"
- FateSwap widgets use the real `fateswap.io/images/logo-full.svg`, paired with a bold `"SOLANA DEX"` label above the brand-gradient tagline `"Gamble for a better price than market"`
- FateSwap hero copy uses **third-person** framing: `Trader Received / Trader Paid / Trader Sold` (NOT "You received / You paid")
- SOL token icon uses `ik.imagekit.io/blockster/solana-sol-logo.png` (the same logo used in `coin_flip_live.ex` at /play)
- RogueTrader bot rows use **group tags** (`CRYPTO / EQUITIES / INDEXES / COMMODITIES / FOREX`) — risk tags (Low/Med/High) were removed from the skyscraper layout entirely
- `rt_leaderboard_inline` and `rt_skyscraper` row clicks route per-row to `/bot/:slug` (not the project homepage) — see Decision #7 exception
- Fill chance + TX hash footer on `fs_hero_*` (Roll number dropped)
- Swap Complete green-checkmark badge on filled FS orders
- All prices use 4 decimal places, not 5

🛑 Phase 0 HARD STOP cleared — Phase 1 is unblocked.

### Phase 1 — Sister-app APIs ✅ COMPLETE (2026-04-14, deployed)

- [x] **RogueTrader**: `Api.BotsController` — `GET /api/bots`, `GET /api/bots/:id` (numeric id or case-insensitive name) — `lib/roguetrader_web/controllers/api/bots_controller.ex`
- [x] **RogueTrader**: `Api.ChartsController` — `GET /api/bots/:id/chart?tf=1h|6h|24h|48h|7d` (default `24h`) — `lib/roguetrader_web/controllers/api/charts_controller.ex`
- [x] **RogueTrader**: 5-tf change % implemented in `lib/roguetrader/stats/chart_history.ex` (`change_pct_all_bots/0`, single DISTINCT-ON aggregate per tf) — **NOT** in StatsTracker (deviation: kept change% out of the hot sync loop; controller composes on demand)
- [x] **RogueTrader**: chart history reads from existing `vault_snapshots` table via `ChartHistory.fetch/2` (≤500 points downsampled)
- [x] **RogueTrader**: inline ETS-backed `Plugs.CorsApi` + `Plugs.RateLimit` (300 req/min/IP) on new `:public_api` pipeline. No new deps (no `cors_plug`, no `hammer`).
- [x] **FateSwap**: `Api.FeedController` — `GET /api/feed/recent`, `GET /api/feed/top_profit`, `GET /api/feed/top_discount` — `lib/fateswap_web/controllers/api/feed_controller.ex`
- [x] **FateSwap**: `Api.OrdersController` — `GET /api/orders/:id` (404 on bad/unknown UUID) — `lib/fateswap_web/controllers/api/orders_controller.ex`
- [x] **FateSwap**: shared `Api.OrderSerializer` — canonical `status_text` ("DISCOUNT FILLED" / "ORDER FILLED" / "NOT FILLED"), `discount_pct` (buys), `profit_lamports/ui/pct`, `fill_chance_pct` via `ProvablyFair`, `conviction_label` + `quote` via `Social.Quotes`
- [x] **FateSwap**: inline ETS-backed CORS + rate limit (120 req/min/IP) on `:public_api` pipeline
- [x] Deployed to Fly: RT → `roguetrader-v2.fly.dev`, FS → `fateswap.fly.dev`
- [x] Production verified: `/api/bots` returns 30 bots, `/api/bots/1/chart?tf=1h` returns real points (264ms), `/api/feed/recent` returns real trades (278ms), OPTIONS preflights return 204 with Origin echoed back

**Test counts**: RT 24 new tests (mix test 272/0). FS 27 new tests (mix test 591 total, 1 pre-existing PoolLiveTest failure unrelated).

**Plan deviations honored**:
- Did NOT mutate `StatsTracker` to include change% — composed on demand from `ChartHistory` to keep the sync tick fast. Plan's fallback path explicitly allowed this.
- No new dependencies. CORS + rate limit are tiny inline plugs (no `cors_plug`, no `hammer`).
- `OrderSerializer.status_text` for `(buy, true)` is "DISCOUNT FILLED" (per plan). The existing `trade_components.ex` only emits "ORDER FILLED" / "NOT FILLED" — unchanged. The plan's serializer wins for API consumers; the on-site UI is unchanged.

### Phase 2 — Blockster foundation (pollers, schema, design tokens)

Split into 2a (backend + schema) and 2b (foundation glue — CSS, fonts, macro, dispatcher).

#### Phase 2a ✅ COMPLETE (2026-04-14)

- [x] Migration `20260414120000_add_widget_columns_to_ad_banners` — adds `widget_type` (string), `widget_config` (map default `%{}`), `index(:widget_type)`
- [x] `Banner` schema + changeset — 14-type whitelist (added `rt_sidebar_tile`, `fs_square_compact`, `fs_sidebar_tile` per Phase 0), `image_url` required only when `widget_type` is nil, `widget_config` defaults to `%{}`
- [x] `Ads.list_widget_banners/0` — returns active banners with non-nil `widget_type`
- [x] `Ads.increment_impressions/1` + `Ads.increment_clicks/1` overloaded to accept `%Banner{}` or integer id (macro-friendly)
- [x] `lib/blockster_v2/widgets/fateswap_feed_tracker.ex` (3 s)
- [x] `lib/blockster_v2/widgets/roguetrader_bots_tracker.ex` (10 s)
- [x] `lib/blockster_v2/widgets/roguetrader_chart_tracker.ex` (60 s sweep, 30 bots × 5 tfs staggered)
- [x] `lib/blockster_v2/widgets/widget_selector.ex` — pure module, all 5 RT + 5 FS modes, unknown modes return `nil` (no silent default), `partition_banners/1` helper
- [x] `lib/blockster_v2/widgets/click_router.ex` — `url_for/1` and `url_for/2` with clauses for `{bot_id, tf}` / `order_id` / `:rt` / `:fs` / fallback `"/"`
- [x] Mnesia tables appended to `@tables` in `mnesia_initializer.ex`: `widget_fs_feed_cache` (`{:singleton, trades, fetched_at}`), `widget_rt_bots_cache` (`{:singleton, bots, fetched_at}`), `widget_rt_chart_cache` (composite `{bot_id, tf}` key with points / high / low / change_pct / fetched_at), `widget_selections` (banner_id key + widget_type + subject + picked_at)
- [x] Supervise 3 trackers via `BlocksterV2.GlobalSingleton` in `application.ex`, **behind `WIDGETS_ENABLED` flag** so they don't spin up in dev/test unless explicitly enabled
- [x] `runtime.exs` config block `:widgets` — URLs default to `https://fateswap.fly.dev` and `https://roguetrader-v2.fly.dev` (Phase 1 Fly URLs), intervals as speced, `WIDGETS_ENABLED` default false
- [x] Tests: 84 tests, 0 failures across `test/blockster_v2/widgets/**` + `test/blockster_v2/ads/banner_widget_test.exs`. Full suite 2747 tests, 117 failures — all pre-existing flakes (baseline 119 on the same seed range); zero new failures introduced.

**Phase 2a deviations from plan (now load-bearing)**:

1. **Selector reads change% off the `/api/bots` snapshot, not the chart cache.** Phase 1's `OrderSerializer` already exposes `lp_price_change_{1h,6h,24h,48h,7d}_pct` on every bot row, so the selector doesn't have to coordinate with `RogueTraderChartTracker`. Same answer, no cross-tracker dependency at selection time.
2. **Trackers cache in Mnesia and all reads are `dirty_read` from the local node** — no cross-node `GenServer.call`. The GlobalSingleton is just the writer; non-leader nodes serve widgets from their own Mnesia copy. This matches the `LpPriceTracker` pattern.
3. **Selector returns `:unknown` (→ `nil` pick) for unrecognised selection modes** instead of silently falling back to `biggest_gainer`/`biggest_profit`. Mis-typed admin configs surface as blank widgets (loading state) rather than wrong picks.
4. **Req calls in all three trackers use `retry: false`.** Default Req retries 3× on 5xx / transport errors, adding ~7 s per failed poll. Pollers just try again at the next interval — retries inside a poll step are worse than waiting.
5. **Production Mnesia table creation stays in `MnesiaInitializer.@tables`** rather than a separate `widgets/mnesia_init.ex` helper (plan allowed either). Test-only table setup lives in `test/support/widgets_mnesia_case.ex` following the `airdrop_live_test.exs` pattern (`start_genservers: false` in test env means `MnesiaInitializer` isn't started during test runs, so the support module brings the 4 widget tables up as `ram_copies`).
6. **Tracker processes use `Req.Test.allow/3` + an initial seed stub** so the GenServer process can see the stub the test process installed (`Req.Test.allow` needs the named stub to exist at the time of the allow call). Every tracker accepts a `:req_options` keyword so tests inject `plug: {Req.Test, StubName}`, and `:auto_start`/`:skip_global` keywords so tests can drive polling synchronously via `poll_now/1` without a background timer.

#### Phase 2b — foundation glue (no widgets yet)

- [ ] `assets/css/widgets.css` — scoped `.bw-widget` tokens, Satoshi + JetBrains Mono font-family hooks, `bw-card/bw-shell/bw-pulse-dot/bw-flash-*` utilities, marquee keyframes (full block from `Design tokens, fonts & assets` above)
- [ ] Satoshi + JetBrains Mono `<link>` tags in `root.html.heex`, with `<link rel="preconnect">` for fontshare.com / fonts.gstatic.com
- [ ] `@import "widgets.css"` in `assets/css/app.css`
- [ ] `lib/blockster_v2_web/live/widget_events.ex` — `use BlocksterV2Web.WidgetEvents` macro with `mount_widgets/2`, `handle_info({:fs_trades, _} | {:rt_bots, _} | {:rt_chart, …} | {:selection_changed, …})`, `handle_event("widget_click", …)`
- [ ] `lib/blockster_v2_web/components/widget_components.ex` — `widget_or_ad/1` dispatcher that falls through to `BlocksterV2Web.DesignSystem.ad_banner/1` when `widget_type` is nil. For widgets, **raise** until Phase 3+ adds the component modules — explicit failure beats silent blank slot.
- [ ] Tests: macro — a minimal LiveView host that mounts via `use WidgetEvents`, asserts PubSub subscription happens on connected mount, `handle_info` routes update `assigns` + pushes events, `widget_click` hits `Ads.increment_clicks` and redirects via `ClickRouter`. Dispatcher — `widget_type: nil` falls through to `ad_banner`; `widget_type: "rt_skyscraper"` raises (no component yet).

### Phase 2c onwards — see Phase 3+ below for skyscrapers, charts, tickers, heroes.

### Phase 3 — Skyscrapers (replace existing rt-widget + add fs counterpart)

- [ ] `rt_skyscraper` component + `RtSkyscraperWidget` JS hook
- [ ] `fs_skyscraper` component + `FsSkyscraperWidget` JS hook
- [ ] Delete static rt-widget HTML from `show.html.heex` lines 979–1180
- [ ] Wire `WidgetEvents` into `PostLive.Show`
- [ ] Insert two `ad_banners` rows: `rt_skyscraper` on `sidebar_right`, `fs_skyscraper` on `sidebar_left`
- [ ] Visual QA in dev — both widgets pixel-match `realtime_widgets_mock.html`
- [ ] Tests: render component with sample data; hook integration test via Wallaby/Hound

### Phase 4 — Chart widgets (RogueTrader)

- [ ] `rt_chart_landscape` component + share `RtChartWidget` JS hook (lightweight-charts)
- [ ] `rt_chart_portrait` component (shares hook)
- [ ] `rt_full_card` component (shares hook + adds stat grid)
- [ ] `rt_square_compact` component + `RtSquareCompactWidget` hook (mini sparkline)
- [ ] Self-selection wired end-to-end: tracker → selector → PubSub → LiveView → push_event → hook re-renders chart
- [ ] Add `article_inline_*` and `homepage_inline_*` placement support to `PostLive.Show` and `PostLive.Index`
- [ ] Add `video_player_top` placement to `PostLive.Show` (above article video)
- [ ] Insert sample banners for each widget × placement to test
- [ ] Visual QA — confirm pixel-match against images #1, #2, #4

### Phase 5 — Tickers + leaderboard + FateSwap heroes

- [ ] `rt_ticker` component + `RtTickerWidget` hook (CSS marquee + live data swap)
- [ ] `fs_ticker` component + `FsTickerWidget` hook
- [ ] `rt_leaderboard_inline` component + `RtLeaderboardWidget` hook
- [ ] `fs_hero_portrait` component + `FsHeroWidget` hook
- [ ] `fs_hero_landscape` component (shares `FsHeroWidget` hook)
- [ ] Add `homepage_top_desktop` / `homepage_top_mobile` ticker support to `PostLive.Index`
- [ ] FateSwap selection wired end-to-end
- [ ] Visual QA — confirm pixel-match against images #5, #6

### Phase 6 — Mobile, admin, tracking, polish

- [ ] Mobile responsive QA pass on every widget × every supported placement
- [ ] `/admin/banners` UI: Widget Type dropdown + conditional Widget Config form + live preview
- [ ] Admin tests: create/edit/delete widget banner; switch selection mode; preview renders correctly
- [ ] Loading skeletons for every widget (when tracker has no data yet)
- [ ] Error states (when tracker is in `last_error` state) — show subtle "data temporarily unavailable" placeholder, not a broken card
- [ ] Verify impression + click counts increment correctly across all widgets
- [ ] Verify self-selected click events route to `/bot/:slug` and `/orders/:id`
- [ ] Run full test suite — **zero failures required** before deploy
- [ ] Lighthouse audit on article + homepage with all widgets active — confirm no major perf regression

### Phase 7 — Production rollout

- [ ] Stage RogueTrader + FateSwap deploys (API endpoints live)
- [ ] Stage Blockster deploy (with feature-flag env var `WIDGETS_ENABLED=true` defaulting to false, so we can toggle without redeploying)
- [ ] Insert all production banner rows via Blockster admin
- [ ] Enable widgets in production via secret toggle
- [ ] Monitor poller error rate, RogueTrader/FateSwap rate limit response codes, click-through metrics
- [ ] User-confirmed full deploy

---

## Risks / open considerations

1. **Chart history persistence in RogueTrader**: the chart endpoint requires per-bot per-tf historical price points. If `StatsTracker` only keeps current snapshots, we need to add a ring-buffer ETS table that retains the last 300 points per `{bot_id, tf}`. Confirm during Phase 1 — may add 1–2 days to that phase if missing.

2. **API payload size**: `GET /api/bots` returns ~30 bots × ~25 fields = a few KB. `GET /api/bots/:id/chart` returns 300 points × 2 floats = ~10 KB. Small enough that polling cost is fine, but a misconfigured chart tracker could hammer RogueTrader (150 series × 60s = 2.5 req/s). **Mitigation**: stagger requests across the poll window, log per-series latency, alert if any series 5xx-rates exceed 1%.

3. **CSS scope leakage**: the `.bw-widget` namespace + token redefinition is critical. If a widget root forgets the class, RogueTrader's dark tokens could leak into Blockster's white design system and break the page. **Mitigation**: every component's root has `class="bw-widget"` enforced via the `widget_or_ad` dispatcher; CSS uses the descendant selector `.bw-widget *` for tokens.

4. **Font loading flash (FOIT/FOUT)**: Satoshi + JetBrains Mono load via CDN. If they're slow on first paint, widgets render in fallback fonts then reflow. **Mitigation**: `font-display: swap` (default), `<link rel="preconnect">` for both font hosts, and acceptance of a brief reflow as cosmetic-only.

5. **Self-selection thrash**: if 5 banners with `biggest_gainer` mode all repeatedly pick the same bot, every new poll could trigger a re-render across all 5. **Mitigation**: `WidgetSelector` only broadcasts when the pick *changes* — same pick → no broadcast → no re-render.

6. **Cross-region latency to RogueTrader (iad)**: ord→iad is ~25 ms. Negligible at 10 s cadence; for the 60 s chart tracker even less so.

7. **API stability across sister-app deploys**: if FateSwap renames `payout` to `received`, all FS widgets break. **Mitigation**: pollers log serialization errors and serve last good snapshot. Coordinate field changes via PRs that update this plan doc.

8. **GlobalSingleton failover**: a poller node dying mid-poll → another node picks up within seconds; Mnesia cache survives. Tested pattern (LpPriceTracker, BuxBoosterBetSettler).

9. **Tracking double-counting**: refreshes count as new impressions — same as regular banners. No special handling.

10. **Mobile UX**: mobile placements add 11 new layouts to QA. Many of the "full × 480" widgets may need a smaller mobile variant (already speced, e.g. `rt_chart_landscape` becomes `full × 280` on mobile). Phase 6 budget assumes this.

11. **Privacy**: all data exposed via the new APIs is already public on the source sites' own UIs. No PII.

12. **Click-through accuracy for self-selected widgets**: at click time, the picked subject may have already changed since last broadcast. We pass `subject` from the rendered DOM (set during last `push_event`), so the redirect always reflects what the user actually saw.

13. **Lightweight-charts bundle size**: already in Blockster's bundle for pool charts, so no marginal cost. If we ever drop pool charts, the widgets' usage keeps the lib in the bundle (~30 KB gzipped).

14. **Feature flag**: Phase 7 ships behind `WIDGETS_ENABLED` so we can roll back fast if the new pollers cause unexpected load.

---

## File inventory

### New files — FateSwap
- `lib/fateswap_web/controllers/api/feed_controller.ex`
- `lib/fateswap_web/controllers/api/orders_controller.ex`
- `lib/fateswap/social/quotes.ex` *(may already exist — confirmed from explorer report)*

### New files — RogueTrader
- `lib/roguetrader_web/controllers/api/bots_controller.ex`
- `lib/roguetrader_web/controllers/api/charts_controller.ex`
- `lib/roguetrader/stats/chart_history.ex` *(if not already present — ETS ring buffer per `{bot_id, tf}`)*

### New files — Blockster (Elixir)
- `lib/blockster_v2/widgets/fateswap_feed_tracker.ex`
- `lib/blockster_v2/widgets/roguetrader_bots_tracker.ex`
- `lib/blockster_v2/widgets/roguetrader_chart_tracker.ex`
- `lib/blockster_v2/widgets/widget_selector.ex`
- `lib/blockster_v2/widgets/click_router.ex`
- `lib/blockster_v2/widgets/mnesia_init.ex`
- `lib/blockster_v2_web/live/widget_events.ex` *(macro)*
- `lib/blockster_v2_web/components/widget_components.ex` *(dispatcher)*
- `lib/blockster_v2_web/components/widgets/rt_skyscraper.ex`
- `lib/blockster_v2_web/components/widgets/rt_square_compact.ex`
- `lib/blockster_v2_web/components/widgets/rt_sidebar_tile.ex`
- `lib/blockster_v2_web/components/widgets/rt_chart_landscape.ex`
- `lib/blockster_v2_web/components/widgets/rt_chart_portrait.ex`
- `lib/blockster_v2_web/components/widgets/rt_full_card.ex`
- `lib/blockster_v2_web/components/widgets/rt_ticker.ex`
- `lib/blockster_v2_web/components/widgets/rt_leaderboard_inline.ex`
- `lib/blockster_v2_web/components/widgets/fs_skyscraper.ex`
- `lib/blockster_v2_web/components/widgets/fs_hero_portrait.ex`
- `lib/blockster_v2_web/components/widgets/fs_hero_landscape.ex`
- `lib/blockster_v2_web/components/widgets/fs_ticker.ex`
- `lib/blockster_v2_web/components/widgets/fs_square_compact.ex`
- `lib/blockster_v2_web/components/widgets/fs_sidebar_tile.ex`
- `lib/blockster_v2_web/components/widgets/shared.ex` *(widget_header, widget_footer, conviction_bar primitives)*
- `priv/repo/migrations/{ts}_add_widget_columns_to_ad_banners.exs`

### New files — Blockster (assets)
- `assets/css/widgets.css` *(scoped tokens, fonts, animations, utilities)*
- `assets/js/hooks/widgets/rt_skyscraper.js`
- `assets/js/hooks/widgets/rt_square_compact.js`
- `assets/js/hooks/widgets/rt_chart.js` *(shared by landscape / portrait / full_card)*
- `assets/js/hooks/widgets/rt_ticker.js`
- `assets/js/hooks/widgets/rt_leaderboard.js`
- `assets/js/hooks/widgets/fs_skyscraper.js`
- `assets/js/hooks/widgets/fs_hero.js` *(shared by portrait / landscape)*
- `assets/js/hooks/widgets/fs_ticker.js`

### Modified files — FateSwap
- `lib/fateswap_web/router.ex` (4 new API routes)
- `lib/fateswap_web/endpoint.ex` (CORS plug if not present)

### Modified files — RogueTrader
- `lib/roguetrader_web/router.ex` (3 new API routes, add `scope "/api"` block)
- `lib/roguetrader_web/endpoint.ex` (CORS plug if not present)
- `lib/roguetrader/stats/stats_tracker.ex` (add change% across all 5 timeframes)

### Modified files — Blockster
- `lib/blockster_v2/ads/banner.ex` (`widget_type`, `widget_config`, conditional `image_url` validation)
- `lib/blockster_v2/ads.ex` (`list_widget_banners/0`)
- `lib/blockster_v2/application.ex` (supervise 3 trackers via `GlobalSingleton`)
- `lib/blockster_v2/mnesia_initializer.ex` (4 new cache tables)
- `lib/blockster_v2_web/live/post_live/show.ex` (use `WidgetEvents` macro)
- `lib/blockster_v2_web/live/post_live/show.html.heex` (delete static rt-widget lines 979–1180; add widget dispatchers in both sidebars + inline + video_player_top slots)
- `lib/blockster_v2_web/live/post_live/index.ex` (use `WidgetEvents` macro)
- `lib/blockster_v2_web/live/post_live/index.html.heex` (replace static `<.ad_banner>` with `<.widget_or_ad>` dispatcher in top + inline slots)
- `lib/blockster_v2_web/live/banners_admin_live.ex` (Widget Type dropdown + Widget Config form + preview)
- `lib/blockster_v2_web/live/banners_admin_live.html.heex` (admin form additions)
- `lib/blockster_v2_web/components/layouts/root.html.heex` (Satoshi + JetBrains Mono `<link>` tags)
- `assets/css/app.css` (`@import "widgets.css"`)
- `assets/js/app.js` (register 8 new hooks)
- `config/runtime.exs` (widget URLs, intervals, `WIDGETS_ENABLED` flag)

### Files that get deleted
- The static rt-widget block in `show.html.heex` lines 979–1180 (replaced by live `rt_skyscraper`)

### Test files (new)
- `test/blockster_v2/widgets/fateswap_feed_tracker_test.exs`
- `test/blockster_v2/widgets/roguetrader_bots_tracker_test.exs`
- `test/blockster_v2/widgets/roguetrader_chart_tracker_test.exs`
- `test/blockster_v2/widgets/widget_selector_test.exs`
- `test/blockster_v2/widgets/click_router_test.exs`
- `test/blockster_v2/ads/banner_widget_test.exs` *(changeset validation)*
- `test/blockster_v2_web/live/widget_events_test.exs` *(macro behaviour)*
- `test/blockster_v2_web/components/widgets/*_test.exs` *(11 component render tests)*
- `test/fateswap_web/controllers/api/feed_controller_test.exs` *(in fateswap repo)*
- `test/fateswap_web/controllers/api/orders_controller_test.exs`
- `test/roguetrader_web/controllers/api/bots_controller_test.exs` *(in roguetrader repo)*
- `test/roguetrader_web/controllers/api/charts_controller_test.exs`
