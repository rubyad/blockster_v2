# Hubs index · redesign plan

> Part of the existing-pages redesign release. See `redesign_release_plan.md`
> for context. Big-bang cutover, no per-page feature flag.

## What this replaces

| Field | Value |
|---|---|
| LiveView module | `lib/blockster_v2_web/live/hub_live/index.ex` |
| Template | `lib/blockster_v2_web/live/hub_live/index.html.heex` |
| Route(s) | `/hubs` (moved from `:default` to `:redesign` live_session) |
| Mock file | `docs/solana/hubs_index_mock.html` |
| Bucket | **A** — pure visual refresh |
| Wave | 1 |

## Mock structure (top to bottom)

The mock shows a single-column layout with 4 sections:

| # | Section | Description | Status |
|---|---|---|---|
| 1 | **Page hero** | "Browse" eyebrow, "Hubs" 64px/80px title, description, 3 stat tiles (Hubs / Articles / BUX Paid) | REAL |
| 2 | **Featured hubs** | "Featured this week" eyebrow + "All featured →" link, 3 large gradient cards (5+4+3 = 12 col grid) | REAL |
| 3 | **Search + filters** | Sticky white card with search input, sort-by dropdown, category chips (All + 8 categories + Sponsors) | REAL (search), STUB (sort/filter chips) |
| 4 | **Hub grid** | 4-col grid of gradient hub cards (15 cards + 1 "more" dashed card) + "Showing X of Y" stat | REAL |

### Featured hubs breakdown

3 large cards with different column spans and layouts:

| Card | Col span | Badge | Stats layout | Button style |
|---|---|---|---|---|
| **Card 1** (e.g. Moonpay) | `col-span-12 md:col-span-6 lg:col-span-5` | "Sponsor" with lime pulse | Horizontal row | White bg + "Visit →" text link |
| **Card 2** (e.g. Solana) | `col-span-12 md:col-span-6 lg:col-span-4` | "Trending" with lime pulse | Horizontal row | Glass bg + "Visit →" text link |
| **Card 3** (e.g. Bitcoin) | `col-span-12 md:col-span-12 lg:col-span-3` | None | Vertical stacked rows | Full-width glass button, no visit link |

All 3 share: 320px min-height, dot pattern overlay, blur glow, 56px logo square, 36px title, 14px description, stats (posts/followers/BUX), "+ Follow Hub" button.

### Hub grid card breakdown

Each card in the 4-col grid:

| Element | Detail |
|---|---|
| Background | 135deg linear-gradient from `color_primary` → `color_secondary`, 240px min-height |
| Top-left | 36px rounded-md logo square (glass bg, ring-1) with ticker or logo |
| Top-right | Category badge (9px uppercase, glass bg, rounded-full) |
| Title | 20px bold, tracking-tight |
| Description | 11px, white/75-80, line-clamp-2 |
| Bottom-left | Posts count + readers count (14px bold + 10px label) |
| Bottom-right | "+ Follow" button (white or glass bg depending on gradient lightness) |

### "View all" card

Dashed border white card at the end of the grid: 240px min-height, centered content, arrow icon in circle (hover → lime bg), "+N more hubs" title, "Browse all categories" subtitle.

### Search + filter bar

Sticky below header (`top-[88px]`), white card with:
- Search input: `pl-11` with search icon, rounded-full, 14px placeholder
- Sort-by: text label + bold button (stub — no-op for now)
- Category chips: "All" (active/dark) + 8 category chips (default/white) + "Sponsors" (with lime dot)
- Each chip shows a count in mono font

## Visual components consumed

- `<DesignSystem.header />` ✓ existing (Wave 0)
- `<DesignSystem.footer />` ✓ existing (Wave 0)
- `<DesignSystem.page_hero />` ✓ existing (Wave 0, variant A)
- `<DesignSystem.hub_card />` ✓ existing (Wave 1 homepage) — needs `:category` attr added
- `<DesignSystem.hub_card_more />` ✓ existing (Wave 1 homepage) — needs minor updates to match mock
- `<DesignSystem.chip />` ✓ existing (Wave 0)
- `<DesignSystem.hub_feature_card />` **NEW** — must be built before this page

## Data dependencies

### ✓ Existing — already in production, no work needed

- `@hubs` — `Blog.list_hubs_with_followers()` (sorted by post count desc, preloads followers/posts/events)
- `@all_hubs` — unfiltered hub list for search
- `@search_query` — current search input text
- `@active_category` — currently selected category filter
- `@current_user` — from UserAuth on_mount
- `@bux_balance` — from BuxBalanceHook on_mount

### ✓ Computed from existing data — no new queries needed

- `@featured_hubs` — first 3 hubs from `@all_hubs` (sorted by post count desc)
- `@grid_hubs` — remaining hubs after featured (4th onward), filtered by search/category
- `@total_hub_count` — `length(@all_hubs)`
- `@total_post_count` — sum of post counts across all hubs
- `@categories` — distinct categories derived from hub data (or hardcoded list matching mock)

### ⚠ Stubbed in v1

- **Sort-by dropdown**: renders the "Most followed" button text but clicking is a no-op. Hubs are always sorted by post count desc (the existing `list_hubs_with_followers` order).
- **Category filter chips**: chips render with counts, clicking sets `@active_category` but actual category-based filtering requires a `category` field on hubs (not in schema). For v1, chips are visual-only stubs. The "All" chip is always active.

### ✗ New — none required

No schema migrations or new context functions needed. This is a Bucket A pure visual refresh.

## Handlers to preserve

All existing handlers from `HubLive.Index`:

- `handle_event("search", %{"value" => query}, socket)` — filters hubs by name/description match
- `handle_event("filter_category", %{"category" => category}, socket)` — sets `@active_category` (currently visual-only)
- `handle_params/3` — no-op, required by Phoenix

## Tests required

### Component tests

- `test/blockster_v2_web/components/design_system/hub_feature_card_test.exs` — new component tests for the featured hub card (horizontal + vertical layouts, badge variants, logo/ticker rendering)

### LiveView tests

- `test/blockster_v2_web/live/hub_live/index_test.exs` — **NEW** file (no existing test)
  - Page renders with hubs
  - Page hero section present with title "Hubs"
  - Featured section present
  - Hub grid renders hub cards
  - Search filters hubs by name
  - Search filters hubs by description
  - Empty search shows all hubs
  - Category chips render
  - "Showing X of Y" stat renders
  - Anonymous user sees Connect Wallet button
  - Logged-in user sees BUX balance

### Manual checks

- Page renders logged in
- Page renders anonymous
- Search filters correctly
- Hub cards link to correct `/hub/:slug` routes
- Featured cards display correctly at all breakpoints
- Sticky search bar stays below header on scroll
- `mix test` zero new failures vs baseline

## Per-page commit message

`redesign(hubs-index): featured cards + search/filter bar + 4-col hub grid`

## Open items

None — this is a Bucket A pure visual refresh. No decisions needed, no schema changes, no stubs that require user input.
