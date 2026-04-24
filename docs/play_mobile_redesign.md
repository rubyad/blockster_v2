# /play Mobile Redesign — Diagnosis & Fix Proposal

**Date:** 2026-04-24
**Scope:** `lib/blockster_v2_web/live/coin_flip_live.ex` (feat/solana-migration), compared to the old `/play` on `main` (`BuxBoosterLive`, `lib/blockster_v2_web/live/bux_booster_live.ex`).
**Status:** Diagnosis only — no code changes.

---

## The problem in one number

On a 390 × 844 iPhone viewport, the current `/play` page is **3,573 px tall**. The bet-placement surface starts at **y = 617**, which is the *bottom* of the first viewport — meaning every single interactive control (difficulty, amount, prediction, place-bet) lives **below the fold**. The user has to scroll to even see the bet input, and scroll again to reach the "Make your prediction" CTA.

For reference, the old `main`-branch design put every control inside a **480-510 px fixed-height card** that fit entirely above the fold on the same viewport.

---

## Side-by-side (mobile, 390 × 844)

### Old design (`main` · `BuxBoosterLive`)

```
┌───────────────────────── viewport top ─────────────────────────┐
│  ┌────────────────────────────────────────────────────────┐   │
│  │  [1.02x] [1.05x] [1.13x] [1.32x] [1.98x] [3.96x] …    │   │  ← difficulty tabs
│  │  ─────────────────────────────────────────────         │   │    (horizontal scroll)
│  │  Bet Stake                                             │   │
│  │  [  0.5       ½ 2× ] [ SOL ▾ ] [Max 0.6094]            │   │  ← one row: input + ½/2× + token
│  │  You: 29.35 SOL · House: 60.33 SOL                     │   │
│  │  ┌─ Potential profit ───────────── + 0.49 SOL ──┐      │   │
│  │                                                          │   │
│  │        Predict (5 flips, win any)      ⓘ Provably fair │   │
│  │                                                          │   │
│  │              (1)  (2)  (3)  (4)  (5)                   │   │  ← prediction chips
│  │                                                          │   │
│  │  ┌─────── Make your prediction ───────────────┐         │   │  ← CTA
│  │  └─────────────────────────────────────────────┘        │   │
│  └────────────────────────────────────────────────────────┘   │
├───────────────────────── viewport bottom ──────────────────────┤
```

Everything — difficulty, token, amount, halve/double, max, potential profit, predictions, CTA — fits in the top ~480 px. Below the fold: only secondary content (stats, recent games, mode explanations).

### New design (this branch · `CoinFlipLive`)

```
┌───────────────────────── viewport top ─────────────────────────┐
│                                                                │
│  PROVABLY-FAIR · ON-CHAIN · SUB-1% HOUSE EDGE                 │  ← 12px eyebrow
│                                                                │
│  Coin Flip                                                     │  ← 60-80px h1
│                                                                │
│  Pick a side, place a bet, watch it settle on chain in under   │
│  a second. Every flip is verifiable. Every payout is funded    │  ← 3-line body
│  by the public bankroll.                                       │
│                                                                │
│  How Coin Flip works ↗   Verify a game ↗   Security audit ↗    │  ← 3 docs links
│                                                                │
│  ┌──SOL POOL─┐ ┌──BUX POOL─┐ ┌──HOUSE EDGE─┐                   │
│  │   60.33   │ │     —     │ │    0.92%    │                   │  ← 3 stat cards
│  │ View pool │ │ View pool │ │  verified   │                   │
│  └───────────┘ └───────────┘ └─────────────┘                   │
│                                                                │
│  ⚠ You have a stuck bet older than 5 minutes.     [Reclaim]    │  ← reclaim banner
│                                                                │
├──────────────────── viewport bottom (y≈844) ───────────────────┤
│                                                                │
│  [ SOL ] [ BUX ]     (token selector)                          │  ← TOKENS start at y≈617
│  Your balance: 29.35 SOL    House: 60.33 SOL ↗                 │
│                                                                │
│  DIFFICULTY                                                    │
│  ┌─1.02×─┐ ┌─1.05×─┐ ┌─1.13×─┐ ┌─1.32×─┐ ┌─1.98×─┐             │  ← 9 tiles in a
│  │ Win 1 │ │ Win 1 │ │ Win 1 │ │ Win 1 │ │ Win all│            │    2-row grid
│  └───────┘ └───────┘ └───────┘ └───────┘ └───────┘             │
│  ┌─3.96×─┐ ┌─7.92×─┐ …                                          │
│                                                                │
│  BET AMOUNT                           [½] [2×] [MAX 0.6094]    │
│  ┌──────────────────────── 0.5 ─────────── SOL ──┐             │
│  └─────────────────────────────────────────────────┘            │
│  [0.01] [0.05] [0.1] [0.25] [0.5] [1]                           │  ← quick amounts
│                                                                │
│  ┌─ Potential profit + MULTIPLIER ──────────────┐              │
│  │ + 0.49 SOL                        1.98×      │              │
│  └───────────────────────────────────────────────┘              │
│                                                                │
│  PICK YOUR SIDE · 1 FLIP · WIN ONE                             │
│         ( ○ )                                                   │  ← prediction chip
│                                                                │
│  ⓘ Provably fair · Server seed locked                          │
│                                                                │
│  ┌────────── Make your prediction (disabled) ────┐             │  ← CTA at y≈1850
│  └─────────────────────────────────────────────────┘            │
│                                                                │
│  YOUR STATS                                                    │
│  … Recent games … Two modes explainer … Last bets table …     │
│                                                                │
└─────────────────────────── y = 3573 ────────────────────────────┘
```

The new hero alone consumes ~600 vertical pixels. The user sees *marketing copy and pool stats* in the first viewport and has to scroll to do anything.

---

## What specifically is wrong — by section

All line references below are in `lib/blockster_v2_web/live/coin_flip_live.ex`.

### Hero (lines 211-251) — 602 px on mobile

| Element | Size | Useful on mobile? |
|---|---:|---|
| `eyebrow` "PROVABLY-FAIR · ON-CHAIN · SUB-1% HOUSE EDGE" (line 214-216) | ~40 px | Low |
| `h1 text-[60px] md:text-[80px]` "Coin Flip" (line 217) | ~75 px | The user already navigated here |
| Subtitle paragraph (line 218-220) | ~80 px | Could be a single line |
| 3 docs links row (line 221-225) | ~50 px | Rare action — move to a `?` button |
| 3-column stat card grid (line 227-249) | ~140 px | The non-selected token always shows `—` — wastes 33% of the row |

Total: ~600 px of "hello user, here's a page" before they can do anything.

**On desktop** this is fine (the stat cards sit beside the h1 in a 12-col grid). **On mobile**, `col-span-12 md:col-span-7` forces everything to stack. Nothing in this hero gets users closer to placing a bet.

### Reclaim banner (line 253-264) — conditional

Fine in isolation, but piles on when it's showing.

### Game card — token + balance (line 285-314) — ~80 px

Two pill buttons (SOL / BUX) + one line of balance + house info. The balance line is informational; it could collapse to one 12px row.

### Difficulty grid — ~200 px on mobile

New design uses a **2D grid** with tile heights of ~60 px × 2 rows = ~130 px. Old design used **one horizontal scroll row** of 48-55 px. New one is 2.5× taller.

Each tile in the new design has multiplier ("1.02×") + mode label ("Win one") + flip count ("5 flips") — three lines. Old had two lines ("1.02x" + "5 flips").

### Bet amount stack — ~240 px

- Label "BET AMOUNT" + ½/2×/MAX row (~40 px)
- Input + SOL suffix (~60 px) — old design inlined ½/2× and token inside this box
- Quick-amounts row: `[0.01] [0.05] [0.1] [0.25] [0.5] [1]` (~60 px) — six tiny buttons
- Potential profit + multiplier bar (~80 px)

Old design merged most of this into one horizontal row plus one compact profit bar. Six quick-amount buttons are a net-new addition that eats a row.

### Prediction chip(s) — ~150 px

"PICK YOUR SIDE · 1 FLIP · WIN ONE" label + centered single chip. Wastes vertical space with whitespace padding. Old design put chips tight next to each other.

### Provably-fair row — ~60 px

Always visible on the new design. Old design put it behind a toggle button — visible only on demand.

### CTA "Make your prediction" — ~60 px

Lands at **y ≈ 1,850** on a 844-px viewport.

### Secondary content (below CTA) — ~1,700 px

- YOUR STATS
- YOUR RECENT GAMES (3 rows)
- TWO MODES explainer
- YOUR LAST BETS (table)
- Footer

None of this is needed to place a bet. In the old design, most of this lived elsewhere or was collapsed.

---

## Recommended fix

The goal is the same as the old design: **the entire bet-placement flow should fit in one viewport on mobile**, with zero scrolling to place a bet. Secondary content can stay but should live below the fold or behind toggles.

### 1. Make the hero mobile-responsive (biggest single win)

Current hero is 602 px. Target: **≤ 150 px** on mobile.

Specifically:
- Drop `text-[60px]` to `text-[28px]` on `md:below` viewports. Keep desktop at `text-[80px]`.
  - `h1` becomes: `text-[28px] md:text-[80px]`
- Collapse the subtitle to a single line on mobile, or hide it behind a read-more:
  - Wrap the paragraph in `hidden md:block` and add a compact mobile version like `md:hidden text-xs text-neutral-500`
- Hide the three docs links on mobile, put them behind a `?` icon or a bottom info drawer:
  - Wrap `div class="mt-3 flex items-center gap-4 text-[12px] font-mono"` in `hidden md:flex`
- Replace the 3-column pool-stat grid on mobile with a **single compact row** showing only the active token's pool + house edge (2 numbers, not 3). The `—` for the non-selected token is pure visual noise.
  - On mobile, render as a 12px line right under the game's token toggle: `60.33 SOL · house edge 0.92%` with a `View pool ↗` link.

### 2. Move reclaim banner *inside* the game card

The amber "stuck bet" banner currently sits between the hero and the game card, pushing the game further down. It belongs inside the game card (top of the card, collapses after action), not as a standalone section.

### 3. Compact the game card to the old fixed-height pattern

On mobile, put the entire playable surface into a fixed-height card (~520 px) with internal overflow, exactly like the old design. This has three benefits:
- Forces the designer to be disciplined about what fits
- Guarantees above-the-fold placement
- Eliminates jank when the card expands (the old `absolute inset-0` pattern kept the height constant between `:idle` and `:flipping` states)

Inside the card, tight mobile spacing (`py-2 sm:py-3`, `text-xs sm:text-sm`) matching the old design.

### 4. Consolidate bet-amount controls into one row

On mobile, merge into a single input row:
```
┌────────────────────────────────────────────────────────┐
│  0.5                      ½  2×  [SOL ▾]  MAX 0.6094   │
└────────────────────────────────────────────────────────┘
```
This is literally what the old design (lines 236-278 of main's `bux_booster_live.ex`) did, and it saves ~120 px.

Drop the 6 quick-amount buttons on mobile (`[0.01] [0.05] …`) — the old design didn't have them, and the ½/2× buttons plus MAX plus free-form input cover all needs. If you want to keep them on desktop, wrap in `hidden md:flex`.

### 5. Flatten the difficulty grid to a horizontal scroll on mobile

Current: 9-tile 2-row grid.
Target: 9 tiles in a single horizontally-scrollable row, just like the old design at line 210 of main's template.

This trades one row of vertical height for horizontal scrolling, which is the right trade on mobile.

### 6. Make the provably-fair disclosure a toggle, not a static row

Wrap the provably-fair row in a `<details>` or a phx-click toggle with a single icon button. Old design saved ~50 px here; new design always shows it.

### 7. Push secondary content into tabs or an accordion

Below the CTA, there are 4 info sections (`YOUR STATS`, `YOUR RECENT GAMES`, `TWO MODES`, `YOUR LAST BETS`). Put them behind 2-3 tabs under the game card (`Stats · History · How it works`) so the page ends at ~900 px, not 3,573 px. Desktop can keep the current sidebar layout (`col-span-8` + `col-span-4`); mobile collapses to tabs.

### 8. Remove the 3 docs links above the fold

"How Coin Flip works / Verify a game / Security audit" are rarely clicked links that consume premium real estate. Link to them from:
- A `?` icon inside the game card (or next to the provably-fair disclosure)
- The "How it works" tab from point 7
- The footer

---

## Expected result

Approximate mobile page height after the fix:
```
Hero (compact):              150 px
Game card (fixed):            520 px
Tabs strip (above-fold):      40 px
─────────────────────────────────────
Above-the-fold total:         710 px   ← fits 844-px viewport with slack
─────────────────────────────────────
Tabs content (below fold):   400-600 px
Footer:                      200 px
Total page height:           1,310-1,510 px
```

vs. current **3,573 px** — a ~57% reduction, and the entire bet-placement UI is above the fold again.

---

## Implementation order if we do this

1. **Shrink the hero on mobile** (h1 size, hide docs links, hide/shrink subtitle, collapse 3-card grid to 1-line summary). ~30 min. Biggest single win, zero risk.
2. **Merge bet-amount controls** (input + ½/2× + token + max in one row, hide 6-quick-amounts on mobile). ~45 min.
3. **Move reclaim banner inside the card**. ~15 min.
4. **Flatten difficulty to horizontal scroll on mobile**. ~30 min — needs a `phx-hook="ScrollToCenter"` like the old design (there's already a hook by this name in the codebase).
5. **Tabs for secondary content**. 1-2 hours — touches more surface area but is pure layout.
6. **Fixed-height card + absolute-positioned inner content**. ~1 hour. The old design used `h-[480px] sm:h-[510px] flex flex-col overflow-hidden` on the outer card and `flex-1 relative min-h-0 ... absolute inset-0` on the inner. Copy that pattern.
7. **Provably-fair as toggle**. ~15 min.

Steps 1-4 alone get the page under 1,500 px and the bet flow above the fold. Steps 5-7 are polish.

---

## What the old design got right that we should copy verbatim

From `main:lib/blockster_v2_web/live/bux_booster_live.ex` lines 207-250:

- `max-w-2xl mx-auto px-3 sm:px-4 pt-6 sm:pt-24 pb-8` — narrow centered column, tiny mobile top padding (24 px), bigger on desktop
- `h-[480px] sm:h-[510px] flex flex-col overflow-hidden` on the card — commits to a fixed height
- `py-2 sm:py-3` inside the difficulty tabs — disciplined mobile spacing
- `min-w-[60px] sm:min-w-0` on tab buttons — lets them stay compact on mobile, expand on desktop
- `overflow-x-auto scrollbar-hide` on tab container — horizontal scroll without visible scrollbar
- `flex-1 relative min-h-0` + `absolute inset-0 p-3 sm:p-6 flex flex-col overflow-hidden` — inner content filled the card without pushing its height around between states

The current design's `max-w-[1280px]` container + `grid grid-cols-12` is a desktop-first layout that ports poorly to mobile. The old `max-w-2xl` column was mobile-first and happened to also look fine on desktop.
