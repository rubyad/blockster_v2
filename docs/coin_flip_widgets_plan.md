# Coin Flip Widgets — Implementation Reference

> 6 widget types for the Blockster Coin Flip game (`/play`). 3 demo ("how it works" animations) + 3 live (real game data). Built Apr 2026.

**Mocks (source of truth)**: `docs/solana/widgets_mocks/cf_*.html` (25 files).

---

## Widget Catalog

### Demo widgets (animated "how it works", no live data)

| `widget_type` | Component | Format | Cycling | CSS system |
|---|---|---|---|---|
| `cf_sidebar_demo` | `CfSidebarDemo` | 200 × 340 sidebar | **None** — single difficulty (Win All 3 flips, 7.92×), 18s pure CSS loop | `.bw-widget .bw-shell .cf-sb` (Phase 4 CSS + keyframes) |
| `cf_inline_landscape_demo` | `CfInlineLandscapeDemo` | full-width 2-column | 9 difficulties, synced left/right panels via `CfDemoCycle` JS hook | `.bw-widget.cfd .vw.vw--land` |
| `cf_portrait_demo` | `CfPortraitDemo` | 400px max-width, centered | 9 difficulties, single panel set via `CfDemoCycle` JS hook | `.bw-widget.cfd .vw` |

### Live widgets (show real game data, cycling through last 10 settled SOL games)

| `widget_type` | Component | Format | Data | CSS system |
|---|---|---|---|---|
| `cf_sidebar_tile` | `CfSidebarTile` | 200 × 340 | Last 10 SOL games, 5s cycle via `CfLiveCycle` | `.bw-widget .bw-shell .cf-sb` (Phase 4 CSS) |
| `cf_inline_landscape` | `CfInlineLandscape` | full-width 2-column | Same | `.bw-widget .cf-land` (Phase 4 CSS) |
| `cf_portrait` | `CfPortrait` | 400px max-width | Same | `.bw-widget .cf-port` (Phase 4 CSS) |

---

## Architecture

### Demo widgets

**Sidebar demo** (`cf_sidebar_demo`):
- Single hardcoded difficulty — Win All · 3 Flips · 7.92×
- 18-second pure CSS animation loop: 3 coin spins → result reveals → coin area collapses → winner banner → reset
- NO JS hook, NO panel cycling — the mock is a single self-contained animation
- Uses `.bw-widget .bw-shell .cf-sb` + `.cf-sb__*` class hierarchy
- Animation keyframes: `cf-demo-op-1/2/3`, `cf-demo-rot-1/2/3`, `cf-sb-coinarea-collapse`, `cf-demo-result-1/2/3`, `cf-demo-ph-1/2/3`, `cf-demo-status-spin1/hold1/...`, `cf-demo-winner`, `cf-demo-stake-op`
- USD values computed from `PriceTracker.get_price("SOL")` at render time

**Landscape demo** (`cf_inline_landscape_demo`):
- 9 panels (p0–p8) cycling through all difficulties
- Two-column layout: `.cf-panels-left` (45%, coin zone + winner overlay) + `.cf-panels-right` (55%, picks/results/stats)
- Left and right panels synced by `CfDemoCycle` JS hook
- Per-panel CSS keyframes scoped by `.p0`–`.p8` class (e.g., `.p0 .d-slot-1`, `.p1 .d-rot`)
- `phx-update="ignore"` on root to prevent LiveView re-renders from resetting cycling state
- Uses `.bw-widget.cfd` design system (`.vw`, `.vw--land`, `.bd`, `.bm`, `.v-*`, `.d-*`)

**Portrait demo** (`cf_portrait_demo`):
- 9 panels (p0–p8) cycling, same as landscape but single-column vertical layout
- `.vw` with `max-width:400px; margin:0 auto` for centering
- `.cf-panels` with `min-height:400px` to prevent height jank between panel switches
- Same per-panel keyframes as landscape (shared CSS)
- `phx-update="ignore"` on root

**JS cycling** (`CfDemoCycle` hook):
- Detects landscape vs portrait by checking for `.vw--land` class
- Landscape: syncs `.cf-panels-left > [data-cf-panel]` and `.cf-panels-right [data-cf-panel]`
- Portrait: single set of `[data-cf-panel]` elements
- Uses `data-hidden` attribute toggle (not inline styles) — CSS handles visual: `display:none` for landscape, `opacity:0;position:absolute` for portrait
- Duration per panel from `data-duration` attribute (seconds): [9, 13, 17, 21, 25, 13, 17, 17, 17]
- Random start index so adjacent widgets don't sync

### Live widgets

**Data source**: `CoinFlipGame.get_recent_games_by_vault(:sol, 10)` — direct Mnesia read, no HTTP polling.

**Real-time updates**: PubSub subscription on `"pool:settlements"` topic, `{:bet_settled, "sol"}` message.

**Cycling**: `CfLiveCycle` JS hook, 5-second intervals, crossfade animation. Game data passed as JSON `data-games` attribute, updated via LiveView patches.

**Helpers**: `BlocksterV2Web.Widgets.CfHelpers` — `format_cf_game/1`, `get_sol_price/0`, `sol_to_usd/2`, `truncate_wallet/1`, `chip_side/1`, `matched?/3`.

---

## File Inventory

### Elixir components
| File | Purpose |
|---|---|
| `lib/blockster_v2_web/components/widgets/cf_sidebar_demo.ex` | Sidebar demo — exact copy of mock HTML |
| `lib/blockster_v2_web/components/widgets/cf_inline_landscape_demo.ex` | Landscape demo — mock HTML + dynamic USD |
| `lib/blockster_v2_web/components/widgets/cf_portrait_demo.ex` | Portrait demo — mock HTML + dynamic USD |
| `lib/blockster_v2_web/components/widgets/cf_sidebar_tile.ex` | Sidebar live — game data rendering |
| `lib/blockster_v2_web/components/widgets/cf_inline_landscape.ex` | Landscape live — game data rendering |
| `lib/blockster_v2_web/components/widgets/cf_portrait.ex` | Portrait live — game data rendering |
| `lib/blockster_v2_web/components/widgets/cf_helpers.ex` | Shared helpers (formatting, pricing, chips) |

### JS hooks
| File | Purpose |
|---|---|
| `assets/js/hooks/widgets/cf_demo_cycle.js` | Panel cycling for landscape + portrait demos |
| `assets/js/hooks/widgets/cf_live_cycle.js` | Game cycling for live widgets |

### CSS
| Location | Purpose |
|---|---|
| `assets/css/widgets.css` (`.bw-widget .cf-sb__*` block) | Sidebar shell + 18s animation keyframes |
| `assets/css/widgets.css` (`.bw-widget.cfd` block) | Landscape/portrait design system + per-panel keyframes (p0–p8) |

### Schema + Admin
| File | Change |
|---|---|
| `lib/blockster_v2/ads/banner.ex` | 6 new `@valid_widget_types` |
| `lib/blockster_v2_web/live/banners_admin_live.ex` | 6 new `@widget_types` dropdown entries |
| `lib/blockster_v2_web/components/widget_components.ex` | 6 new dispatch clauses + `cf_games` attr |

### Tests (93 total, all passing)
| File | Tests |
|---|---|
| `test/blockster_v2/ads/coin_flip_widget_types_test.exs` | 3 |
| `test/blockster_v2_web/components/widgets/cf_sidebar_demo_test.exs` | 12 |
| `test/blockster_v2_web/components/widgets/cf_inline_landscape_demo_test.exs` | 14 |
| `test/blockster_v2_web/components/widgets/cf_portrait_demo_test.exs` | 14 |
| `test/blockster_v2_web/components/widgets/cf_helpers_test.exs` | 17 |
| `test/blockster_v2_web/components/widgets/cf_sidebar_tile_test.exs` | 10 |
| `test/blockster_v2_web/components/widgets/cf_inline_landscape_test.exs` | 10 |
| `test/blockster_v2_web/components/widgets/cf_portrait_test.exs` | 9 |

---

## Two CSS Systems

The demo widgets use two DIFFERENT CSS systems because the mocks were built at different times:

1. **Sidebar demo** — uses the original `.bw-widget` namespace with `.bw-shell`, `.cf-sb`, `.cf-sb__*`, `.cf-demo-*` classes. These are the same Phase 4 classes used by the live sidebar tile. Animation keyframes are global (`cf-demo-op-1`, etc.).

2. **Landscape + portrait demos** — use the `.cfd` (coin-flip-demo) namespace scoped under `.bw-widget.cfd`. Short class names from the mocks: `.vw`, `.bd`, `.bm`, `.v-head`, `.v-chip`, `.d-face`, etc. Per-panel keyframes scoped by `.p0`–`.p8`. Landscape adds `.vw--land` overrides.

**CRITICAL**: `.bw-widget.cfd` (no space) = both classes on the SAME element. `.bw-widget .cfd` (with space) = `.cfd` is a DESCENDANT. The root `<a>` tag has both classes, so the CSS must use the no-space variant. Getting this wrong makes all styles fail silently.

---

## USD Pricing

All demo widgets compute USD values dynamically from `PriceTracker.get_price("SOL")` at render time:

- **Landscape + portrait**: `usd/2` helper computes per-panel stake and payout USD as assigns (`@s0`–`@s8`, `@w0`–`@w8`), interpolated into the static HTML
- **Sidebar**: Computes `@stake_usd` (0.50 SOL) and `@win_usd` (+3.46 SOL) as assigns
- **Fallback**: Returns `"—"` if Mnesia price table unavailable (dev without PriceTracker running)
- **`phx-update="ignore"`** on landscape/portrait roots means USD values are computed ONCE at mount and never re-rendered — acceptable since the widget content is static animation

---

## Key CSS Fixes (post-mock-copy)

These issues arose because the mock's CSS worked in isolation but broke when embedded in Blockster's LiveView/Tailwind context:

1. **Flex column blockification**: `display:inline-flex` children inside `display:flex;flex-direction:column` parents get blockified to `display:flex` by CSS spec, then stretch to fill available main-axis height. Fix: explicit `height` and `flex:none` on `.v-winner-amount` (36px) and `.v-card-val` (20px).

2. **Winner overlay positioning**: In landscape, `.v-winner` (position:absolute) was trapped inside `.v-coin-area` (position:relative). The mock intended it to fill the entire left column. Fix: `position:static` on `.vw--land .v-coin-area`.

3. **Portrait winner bottom bleed**: Status text (`.v-st-wrap`) extended below `.v-winner` bottom edge. Fix: `inset:10px 10px 0 10px` (zero bottom inset) on `.v-winner`.

4. **Height jank on panel switch**: Panels with 4–5 flips (36px chips) are 12px shorter than panels with 1–3 flips (42px chips). Fix: `min-height` on `.cf-panels` (portrait: 400px) and `.cf-panels-right` (landscape: 280px).

5. **Portrait centering**: `.vw` has `max-width:400px` but was left-aligned in wider containers. Fix: `margin:0 auto`.
