# Pool Page UI Overhaul Plan

**Created**: 2026-04-04
**Status**: Complete — All 6 phases done
**Branch**: `feat/solana-migration`

---

## Overview

Split the single `/pool` page into a pool index and two dedicated vault pages (SOL + BUX), modeled after the FateSwap pool page. Each vault page has a two-column layout: deposit/withdraw form on the left, chart + stats + activity on the right.

---

## Routes

| Route | LiveView | Description |
|-------|----------|-------------|
| `/pool` | `PoolIndexLive` | Pool selector — two cards linking to each vault |
| `/pool/sol` | `PoolDetailLive` | SOL vault — deposit/withdraw, chart, stats, activity |
| `/pool/bux` | `PoolDetailLive` | BUX vault — same layout, different data |

`PoolDetailLive` is a single LiveView that takes `vault_type` from the URL param and renders for either SOL or BUX.

---

## Design Direction

**Aesthetic**: Clean financial dashboard — light background, dark chart container, crisp typography, subtle depth. Not flashy, not flat — confident and readable. Think Bloomberg Terminal meets modern DeFi, stripped of noise.

**Color System**:
- Background: `#F5F6FB` (light gray-blue)
- Cards: `white` with `border-gray-200`, `rounded-2xl`, `shadow-sm`
- Chart container: `bg-gray-900` with `rounded-xl` — dark for contrast
- SOL accent: violet gradient (`from-violet-500 to-fuchsia-500`)
- BUX accent: amber gradient (`from-amber-400 to-orange-500`)
- Positive: `text-emerald-500`
- Negative: `text-red-500`
- Buttons: `bg-gray-900 text-white` (primary), `bg-gray-100 text-gray-900` (secondary)
- Brand lime `#CAFC00`: small accents only (dot indicators, subtle highlights)

**Typography**:
- Headings/labels: `font-haas_medium_65`
- Body/values: `font-haas_roman_55`
- Monospace values (prices, amounts): `tabular-nums` for alignment

---

## File Structure

### New Files
```
lib/blockster_v2_web/live/pool_index_live.ex          # Pool selector page
lib/blockster_v2_web/live/pool_detail_live.ex          # Individual vault page
lib/blockster_v2_web/components/pool_components.ex     # All pool function components
assets/js/hooks/price_chart.js                         # TradingView lightweight-charts hook
```

### Modified Files
```
lib/blockster_v2_web/router.ex                         # New routes
assets/js/app.js                                       # Register PriceChart hook
assets/package.json                                    # Add lightweight-charts
lib/blockster_v2_web/live/pool_live.ex                 # DELETE (replaced)
```

### Dependencies
```bash
cd assets && npm install lightweight-charts
```

---

## Phase 1: Pool Index Page (`/pool`)

Simple page with two pool cards. Each card shows:
- Pool icon (SOL gradient circle / BUX lightning bolt)
- Pool name
- Current TVL (total balance)
- LP price
- LP supply
- House profit
- "Enter Pool" button → navigates to `/pool/sol` or `/pool/bux`

**Layout**: Centered, max-w-3xl, two cards side by side (stacked on mobile).

### Implementation
1. Create `PoolIndexLive` — mount fetches pool stats via `start_async`
2. Render two cards with stats
3. Add routes to router

---

## Phase 2: Pool Detail Page — Layout & Deposit/Withdraw

### Two-Column Layout

```
Desktop (lg+):
┌─────────────────────────────────────────────────────────┐
│ ← Back to Pools          SOL Pool                       │
├──────────────┬──────────────────────────────────────────┤
│              │                                          │
│  ORDER FORM  │  LP PRICE CHART                         │
│  (380px)     │  (flex-1)                               │
│              │                                          │
│  ┌────────┐  │  ┌────────────────────────────────────┐  │
│  │Balances│  │  │ bSOL Price   $1.0004  +0.04%       │  │
│  ├────────┤  │  │ ┌──────────────────────────────┐   │  │
│  │Dep/With│  │  │ │                              │   │  │
│  ├────────┤  │  │ │    AREA CHART (dark bg)      │   │  │
│  │LP Price│  │  │ │                              │   │  │
│  ├────────┤  │  │ └──────────────────────────────┘   │  │
│  │Amount  │  │  │ [1H] [24H] [7D] [30D] [All]       │  │
│  ├────────┤  │  └────────────────────────────────────┘  │
│  │Receive │  │                                          │
│  ├────────┤  │  STATS GRID (2x4)                       │
│  │Rate    │  │  ┌────┬────┬────┬────┐                  │
│  ├────────┤  │  │Price│Supp│Bank│Vol │                  │
│  │[Submit]│  │  ├────┼────┼────┼────┤                  │
│  └────────┘  │  │Bets│Win%│Prof│Pay │                  │
│              │  └────┴────┴────┴────┘                  │
│              │                                          │
│              │  ACTIVITY TABLE                          │
│              │  [All] [Wins] [Losses] [Liquidity]      │
│              │  ┌──────────────────────────────────┐   │
│              │  │ rows...                          │   │
│              │  └──────────────────────────────────┘   │
└──────────────┴──────────────────────────────────────────┘

Mobile:
┌─────────────────────┐
│ ← Back    SOL Pool  │
├─────────────────────┤
│ ORDER FORM          │
│ (full width)        │
├─────────────────────┤
│ LP PRICE CHART      │
├─────────────────────┤
│ STATS GRID (2x2)    │
├─────────────────────┤
│ ACTIVITY TABLE      │
└─────────────────────┘
```

### Order Form Component (`pool_order_form/1`)

```
┌─ Order Form ─────────────────────┐
│                                   │
│  Your Balances                    │
│  ┌─────────────────────────────┐  │
│  │ ◎ 1.234 SOL     ~$185.10   │  │
│  │ ◎ 1.001 bSOL    ~$150.22   │  │
│  └─────────────────────────────┘  │
│                                   │
│  [  Deposit  ] [  Withdraw  ]     │
│                                   │
│  bSOL Price                       │
│  1.000400 SOL                     │
│                                   │
│  Amount                           │
│  ┌─────────────────────── MAX ┐   │
│  │ 0.00                  SOL  │   │
│  └────────────────────────────┘   │
│                                   │
│  You receive                      │
│  ┌────────────────────────────┐   │
│  │ ≈ 0.00               bSOL │   │
│  └────────────────────────────┘   │
│                                   │
│  1 bSOL = 1.0004 SOL              │
│                                   │
│  ┌────────────────────────────┐   │
│  │      Deposit SOL           │   │
│  └────────────────────────────┘   │
│                                   │
│  ┌─ TX Confirmed ────────────┐   │
│  │ ✓ Deposited 1.0 SOL       │   │
│  │   Received ≈ 0.9996 bSOL  │   │
│  │   View on Solscan →       │   │
│  └────────────────────────────┘   │
│                                   │
└───────────────────────────────────┘
```

### Implementation
1. Create `PoolDetailLive` with mount that reads `vault_type` param
2. Create `pool_components.ex` with `pool_order_form/1`
3. Port deposit/withdraw logic from existing `pool_live.ex`
4. Add `sync_on_mount` and `sync_post_tx` async handlers (already built)

---

## Phase 3: LP Price Chart

### Chart Hook (`price_chart.js`)

Uses TradingView's `lightweight-charts` library.

**Configuration**:
- Chart type: Area series with gradient fill
- Background: `#111827` (gray-900)
- Text color: `#9CA3AF` (gray-400)
- Line color: `#CAFC00` (brand lime)
- Area gradient: `#CAFC00` at 30% opacity → transparent
- Grid: `#1F2937` at 10% opacity
- Crosshair: enabled, with tooltip
- Font: system monospace
- Responsive via ResizeObserver

**Events**:
- `mounted()` → push `"request_chart_data"` to server
- Server pushes `"chart_data"` → `series.setData(points)`
- Server pushes `"chart_update"` → `series.update(point)` (real-time)
- `"set_chart_timeframe"` → server recalculates data, pushes new `"chart_data"`

**Data format**: `[{ time: unix_seconds, value: lp_price_float }, ...]`

### Chart Component (`lp_price_chart/1`)

Renders:
- Current LP price (large, 6 decimal places) + change % badge
- High/Low for selected timeframe
- Chart container div with `phx-hook="PriceChart"`
- Timeframe selector buttons: 1H, 24H, 7D, 30D, All

### Server-Side Price History

**Initial approach** (no DB table yet):
- On mount, return a single point (current price) for chart
- Empty state: show "No price history" message in chart area
- Later: add `lp_price_snapshots` table + GenServer to record price every minute

**Timeframe handling**:
- `set_chart_timeframe` event → filter price history by timeframe → push to chart
- Period stats (volume, bets, profit) also filtered by timeframe

### Implementation
1. `npm install lightweight-charts` in assets
2. Create `assets/js/hooks/price_chart.js`
3. Register in `app.js`
4. Add `lp_price_chart/1` component to `pool_components.ex`
5. Add chart data handlers to `PoolDetailLive`

---

## Phase 4: Stats Grid

### Stats Grid Component (`pool_stats_grid/1`)

Two rows, four columns each (2x2 on mobile):

**Row 1** (always visible):
| Stat | Source | Format |
|------|--------|--------|
| LP Price | `pool_stats.lpPrice` | 6 decimals + " SOL" |
| LP Supply | `pool_stats.lpSupply` | 2 decimals + " bSOL" |
| Bankroll | `pool_stats.totalBalance` | 4 decimals + " SOL" |
| Volume | `pool_stats.totalVolume` | 4 decimals + " SOL" (filtered by timeframe) |

**Row 2** (always visible):
| Stat | Source | Format |
|------|--------|--------|
| Total Bets | `pool_stats.totalBets` | Integer with commas |
| Win Rate | computed | Percentage (1 decimal) |
| House Profit | `pool_stats.houseProfit` | 4 decimals, green/red |
| Total Payout | `pool_stats.totalPayout` | 4 decimals + " SOL" |

### Stat Card Component (`stat_card/1`)

```
┌──────────────────┐
│ Label             │
│ 1.000400 SOL      │  ← main value + suffix
│ ~$150.06          │  ← optional sub-value
└──────────────────┘
```

- Loading state: animated pulse skeleton
- Optional color for value (green for positive profit, red for negative)

### Implementation
1. Add `pool_stats_grid/1` and `stat_card/1` to `pool_components.ex`
2. Wire timeframe-filtered stats (initially just all-time from pool_stats)

---

## Phase 5: Activity Table

### Activity Table Component (`activity_table/1`)

**Tabs**: All | Wins | Losses | Liquidity

**Trade columns** (All/Wins/Losses tabs):
| Column | Description |
|--------|-------------|
| Type | "Bet" with game name |
| Amount | SOL wagered |
| Result | Won/Lost badge (green/red) |
| Payout | SOL received (0 if lost) |
| Wallet | Truncated address, linked to Solscan |
| Time | Relative ("5m ago") |

**Liquidity columns** (Liquidity tab):
| Column | Description |
|--------|-------------|
| Type | Deposit/Withdraw badge (green/red) |
| Amount | SOL deposited/withdrawn |
| LP Price | Price at time of TX |
| LP Amount | bSOL minted/burned |
| Wallet | Truncated address |
| Time | Relative |

### Data Source

**Initial approach** (no activity DB table yet):
- Show "No activity yet" empty state
- Later: record bet settlements and LP events to a `pool_activities` PG table
- Infinite scroll with cursor-based pagination

### Implementation
1. Add `activity_table/1`, `trade_row/1`, `pool_activity_row/1` to `pool_components.ex`
2. Empty state rendering
3. Pagination scaffolding (streams + cursors ready for data)

---

## Phase 6: Cleanup & Polish

1. Delete old `pool_live.ex`
2. Update nav highlighting (already done: `/pool` highlights "Play")
3. Update "Back to Play" link on pool index
4. Ensure deposit/withdraw flows work identically to current
5. Mobile responsive testing
6. Update docs

---

## Implementation Order

```
Phase 1: Pool Index Page (/pool)
  ├── PoolIndexLive
  ├── Router changes
  └── Pool selector cards

Phase 2: Pool Detail Page (/pool/sol, /pool/bux)
  ├── PoolDetailLive (parameterized by vault_type)
  ├── pool_components.ex
  │   ├── pool_order_form/1
  │   └── helpers (format_lp_price, format_sol, etc.)
  ├── Deposit/Withdraw logic (ported from pool_live.ex)
  └── Balance sync on mount + post-tx

Phase 3: LP Price Chart
  ├── npm install lightweight-charts
  ├── assets/js/hooks/price_chart.js
  ├── pool_components: lp_price_chart/1
  └── Chart data handlers (initial: single point / empty)

Phase 4: Stats Grid
  ├── pool_components: pool_stats_grid/1, stat_card/1
  └── Timeframe filtering (initially all-time only)

Phase 5: Activity Table
  ├── pool_components: activity_table/1, trade_row/1, pool_activity_row/1
  └── Empty state (data recording added later)

Phase 6: Cleanup
  ├── Delete pool_live.ex
  ├── Update router (remove old /pool route)
  ├── Update nav highlighting for /pool/*
  └── Docs update
```

---

## Component API Reference

### pool_order_form/1
```elixir
attr :vault_type, :string, required: true          # "sol" or "bux"
attr :tab, :atom, default: :deposit                # :deposit or :withdraw
attr :amount, :string, default: ""
attr :balances, :map, required: true               # %{"SOL" => float, "BUX" => float}
attr :lp_balances, :map, required: true            # %{bsol: float, bbux: float}
attr :lp_price, :float, default: 1.0
attr :processing, :boolean, default: false
attr :current_user, :any, default: nil
attr :tx_result, :map, default: nil                # %{sig: "", amount: "", received: ""}
```

### lp_price_chart/1
```elixir
attr :vault_type, :string, required: true
attr :lp_price, :float, default: 1.0
attr :change_pct, :float, default: 0.0
attr :high, :float, default: nil
attr :low, :float, default: nil
attr :timeframe, :string, default: "24H"
attr :loading, :boolean, default: false
```

### pool_stats_grid/1
```elixir
attr :pool_stats, :map, default: nil
attr :loading, :boolean, default: false
attr :vault_type, :string, required: true
attr :timeframe, :string, default: "All"
```

### activity_table/1
```elixir
attr :tab, :atom, default: :all                    # :all, :wins, :losses, :liquidity
attr :vault_type, :string, required: true
attr :activities, :list, default: []
attr :has_more, :boolean, default: false
```

---

## Nav Highlighting Update

Already done: `/pool` and `/pool/*` highlight "Play" nav item.

Update the `DesktopNavHighlight` hook to also match `/pool/sol` and `/pool/bux`:
```javascript
} else if (navPath === '/play') {
  isActive = currentPath === '/play' || currentPath.startsWith('/play/') || currentPath.startsWith('/pool');
}
```

This is already implemented.

---

## Settler API Endpoints Used

| Endpoint | Purpose |
|----------|---------|
| `GET /pool-stats` | TVL, LP price, LP supply, house profit, bets, volume, payout |
| `GET /lp-balance/:wallet/:vaultType` | User's LP token balance |
| `POST /build-deposit-sol` | Build unsigned deposit SOL tx |
| `POST /build-withdraw-sol` | Build unsigned withdraw SOL tx |
| `POST /build-deposit-bux` | Build unsigned deposit BUX tx |
| `POST /build-withdraw-bux` | Build unsigned withdraw BUX tx |

All existing and working.

---

## Future Enhancements (Not in this plan)

- **Price history DB table**: `lp_price_snapshots` — record price every minute for chart data
- **Activity DB table**: `pool_activities` — record bets, settlements, deposits, withdrawals
- **Real-time PubSub**: Broadcast pool stat changes to connected clients
- **USD conversion**: Show USD values alongside SOL amounts (requires price feed)
- **Timeframe-filtered stats**: Volume, bets, profit filtered by selected timeframe (requires activity table)
