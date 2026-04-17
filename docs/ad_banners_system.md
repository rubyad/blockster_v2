# Ad Banners System — Source of Truth

Everything that renders in an `ad_banners` slot on Blockster — template ads, real-time widgets, coin-flip demos — flows through one table, one admin UI, and one seed script. This doc is the single reference. When the system changes, update here first.

> **Current inventory** (2026-04-17): 57 active + 5 dormant banners. See §6 for the seed flow.

> **Quick map**
> - Schema: `lib/blockster_v2/ads/banner.ex`
> - Context: `lib/blockster_v2/ads.ex`
> - Admin UI: `lib/blockster_v2_web/live/banners_admin_live.ex` → `/admin/banners`
> - Template renderer: `lib/blockster_v2_web/components/design_system.ex` (each `def ad_banner(%{banner: %{template: "..."}}) ...`)
> - Widget dispatcher: `lib/blockster_v2_web/components/widget_components.ex`
> - Widget components: `lib/blockster_v2_web/components/widgets/*.ex`
> - Inline responsive slot: `WidgetComponents.inline_ad_slot/1`
> - Production seed: `priv/repo/seeds_banners.exs`
> - Deploy runbook: [`solana_mainnet_deployment.md`](solana_mainnet_deployment.md) → "Phase 6 widgets + luxury ads — post-deploy seed"
> - Luxury template catalog: [`luxury_ad_templates.md`](luxury_ad_templates.md)

---

## Contents

1. [Data model](#1-data-model)
2. [Two render paths: template vs widget](#2-two-render-paths-template-vs-widget)
3. [Placements](#3-placements)
4. [Inline ad dedupe — class-based](#4-inline-ad-dedupe--class-based)
5. [Desktop → mobile auto-swap](#5-desktop--mobile-auto-swap)
6. [Seed flow (local + production)](#6-seed-flow-local--production)
7. [Admin workflow](#7-admin-workflow)
8. [Adding a new template or widget](#8-adding-a-new-template-or-widget)

---

## 1. Data model

One table: `ad_banners`. Relevant fields:

| Field | Type | Purpose |
|-------|------|---------|
| `name` | string | Unique human-readable key; seed upserts by this |
| `placement` | string | Where the banner renders (see [Placements](#3-placements)) |
| `template` | string | Template name (e.g. `luxury_car`) when widget_type is nil |
| `widget_type` | string | Widget name (e.g. `rt_chart_landscape`) — takes priority over template |
| `widget_config` | map | Widget-specific params (e.g. `%{"selection" => "biggest_gainer"}`) |
| `link_url` | string | Destination URL on click (opens in new tab for inline templates) |
| `image_url` | string | Hero image for template ads |
| `params` | map | Template-specific config (headline, price_usd, colors, etc.) |
| `is_active` | bool | Only active banners are picked |
| `sort_order` | int | Lower sorts first; picker uses it for deterministic ordering |

Valid placements + templates + widget types are whitelisted in `lib/blockster_v2/ads/banner.ex`. The schema enforces inclusion — invalid values can't reach the DB.

---

## 2. Two render paths: template vs widget

A row renders through exactly one of two paths:

**Template path** (static + CSS-animated ads — luxury verticals, streaming, patriotic, etc.)
- `widget_type` is nil.
- `template` selects a `BlocksterV2Web.DesignSystem.ad_banner/1` clause.
- `params` + `link_url` + `image_url` drive the content.
- Styling is Tailwind-based, fully responsive (stacks below `md:` or `lg:` depending on the template).
- Catalog + admin param forms: [`luxury_ad_templates.md`](luxury_ad_templates.md).

Currently shipped templates:

| Template | Purpose |
|----------|---------|
| `image` | Legacy raw `<img>` banner (fallback) |
| `follow_bar` | Compact dark bar — hub follow prompt |
| `dark_gradient` | Dark card with heading + description + CTA (Moonpay Buy SOL etc.) |
| `portrait` | Image + dark panel (Heliosphere-style) |
| `split_card` | White card left + colored stat panel right (Moonpay Bottom CTA etc.) |
| `luxury_watch` | Editorial — brand, full-width watch, model, price |
| `luxury_watch_compact_full` | Image-driven height, no crop |
| `luxury_watch_skyscraper` | 200 × tall sidebar watch variant |
| `luxury_watch_banner` | Full-width horizontal watch leaderboard |
| `luxury_watch_split` | Info left, watch image right (article inline) |
| `luxury_car` | Landscape hero, year/model/spec/price (Ferrari, Lambo) |
| `luxury_car_skyscraper` | 200 × tall sidebar car variant |
| `luxury_car_banner` | Full-width horizontal car leaderboard |
| `jet_card_compact` | Narrower 560px jet card |
| `jet_card_skyscraper` | 200 × tall sidebar jet variant |
| `streaming_trial` | Streaming service trial (FOX One, Hulu, etc.) — hero image + trial badge + CTA |
| `patriotic_portrait` | Centered editorial portrait with red/white/blue flag stripe |
| `patriotic_loop` | Square animated CSS loop — headline → image → "THANK YOU / 47" |
| `trump_2028_loop` | Square animated CSS loop — headline → image → "TRUMP / 2028 / subtitle" |

**Widget path** (real-time RogueTrader / FateSwap / Coin Flip data)
- `widget_type` is set (e.g. `rt_chart_landscape`, `cf_inline_landscape_demo`).
- `WidgetComponents.widget_or_ad/1` dispatches to `BlocksterV2Web.Widgets.*`.
- Widget pulls data from Mnesia trackers (live) or renders a pre-canned demo (demo suffix).
- Plan + deep docs: [`solana/realtime_widgets_plan.md`](solana/realtime_widgets_plan.md), [`coin_flip_widgets_plan.md`](coin_flip_widgets_plan.md).

Unknown `widget_type` values raise `ArgumentError` — mis-typed admin configs surface loudly. `widget_type: nil` + `template: "image"` is the legacy raw-image banner mode.

---

## 3. Placements

Every placement in `@valid_placements` (`lib/blockster_v2/ads/banner.ex`):

| Placement | Renders in |
|-----------|-----------|
| `article_top` | Flush under header on article pages, edge-to-edge (desktop only) |
| `article_inline_1` | Article body at the 1/3 mark |
| `article_inline_2` | Article body at the 1/2 mark (hub) / 2/3 mark (no-hub) |
| `article_inline_3` | Article body at the end |
| `article_bottom` | Below the article body (desktop only) |
| `sidebar_left` | Article left sidebar (desktop only) |
| `sidebar_right` | Article right sidebar (desktop only) |
| `video_player_top` | Above the video player on video posts |
| `homepage_top_desktop` | Homepage ticker strip (desktop) |
| `homepage_top_mobile` | Homepage ticker strip (mobile) |
| `homepage_inline` | Between homepage components (mix of desktop+mobile) |
| `homepage_inline_desktop` / `_mobile` | Viewport-specific homepage inline slots |
| `play_sidebar_left` / `_right` | `/play` page sidebars |
| `airdrop_sidebar_left` / `_right` | `/airdrop` page sidebars |

**Retired** (removed in mobile auto-swap refactor — see §5):
`mobile_top`, `mobile_mid`, `mobile_bottom`. These used to carry separate image-only rows for mobile. The inline slots now drive both viewports via the auto-swap.

---

## 4. Inline ad dedupe — class-based

`pick_distinct_inline/3` in `lib/blockster_v2_web/live/post_live/show.ex` selects one banner per inline slot with no two banners from the same "class" appearing on the same page view. The shared classification lives in `BlocksterV2.Ads.banner_class/1`.

Classes:

| Class | Matches |
|-------|---------|
| `:rt` | any widget with `rt_*` prefix (chart, ticker, leaderboard, sidebar tile, etc.) |
| `:cf` | any widget with `cf_*` prefix (coin flip live + demo) |
| `:fs` | any widget with `fs_*` prefix (FateSwap) |
| `:car` | any template containing `luxury_car` |
| `:jet` | any template containing `jet_card` |
| `:watch` | any template containing `luxury_watch` |
| `:moonpay` | any banner with `params["brand_name"] == "Moonpay"` (matches both `dark_gradient` + `split_card` treatments) |
| `{:template, t}` | any other template — unique per template |
| `{:widget, t}` | any other widget — unique per widget_type |

This is per-page-view dedupe only — the same class can still appear on sidebars (sidebars have their own list-based rendering, no inline coupling).

### Homepage class rotation

The homepage uses a stronger guarantee than the article page: not only "no class twice on the same page", but **"no class repeats within any K-slot window"** where K = number of distinct classes in the pool.

`BlocksterV2.Ads.random_class_rotated_pool/2` (called from `post_live/index.ex`) builds the rotation at mount:

1. Groups `homepage_inline` banners by `banner_class/1`.
2. Shuffles the class order — so every mount sees a different cycle (e.g. one visit is car → jet → watch, next is watch → car → jet).
3. For each slot, picks a **random banner from that class's group** — multiple Rolexes / Ferraris / Moonpay variants per class are all fair game; users see different creatives in the watch/car/moonpay slots across visits.
4. Returns a list N × K long (default N=4, so 20 slots for a 5-class pool) so modulo wrap in the render layer doesn't produce same-class collisions at the boundary.

The simpler `pick_one_per_class/1` exists for future placements that only need "one per class per mount" without random ordering.

---

## 5. Desktop → mobile auto-swap

Some templates/widgets don't read well at narrow widths. `WidgetComponents.inline_ad_slot/1` wraps each inline ad in a responsive pair: desktop renders the original, mobile renders a swapped clone. DB row is never mutated — only the map passed to `widget_or_ad` is cloned.

| Desktop | Mobile | Why |
|---------|--------|-----|
| `cf_inline_landscape_demo` | `cf_portrait_demo` | Landscape demo too wide at 375 px |
| `rt_chart_landscape` | `rt_chart_portrait` | Landscape chart too wide at 375 px |
| `luxury_watch_split` | `luxury_watch` | Sidebar-style compact doesn't work as a mobile hero |

Everything else renders the same banner on both viewports. The swap map lives in `mobile_swap/1` inside `widget_components.ex` — add clauses there to add swaps.

The legacy `mobile_top` / `mobile_mid` / `mobile_bottom` placements were retired on 2026-04-16; admins no longer maintain separate mobile-only creative.

---

## 6. Seed flow (local + production)

**Single source of truth for banner inventory:** `priv/repo/seeds_banners.exs`.

Behaviour:
1. Deactivates every banner row first (blank slate).
2. Upserts each banner defined in the file by `name` with `is_active: true`.
3. Rows not in the file stay in the DB but inactive — admins can still toggle them through `/admin/banners`.

Local:
```bash
mix run priv/repo/seeds_banners.exs
```

Production (after a deploy):
```bash
flyctl ssh console --app blockster-v2 -C "/app/bin/blockster_v2 eval \
  'Code.eval_file(Path.wildcard(\"/app/lib/blockster_v2-*/priv/repo/seeds_banners.exs\") |> hd())'"
```

Expected output ends with `Created: N  Updated: M  Total active: <n>`.

The deploy release (`/app/bin/migrate`) **does NOT** run this automatically. Deploy runbook: [`solana_mainnet_deployment.md`](solana_mainnet_deployment.md) → "Phase 6 widgets + luxury ads — post-deploy seed".

> **Retired seed scripts** (replaced by `seeds_banners.exs`): `seeds_ad_banners.exs`, `seeds_widget_banners.exs`, `seeds_luxury_ads.exs`, `seeds_article_inline_force.exs`.

---

## 7. Admin workflow

`/admin/banners` (LiveView in `lib/blockster_v2_web/live/banners_admin_live.ex`):
- Placement dropdown — same `@valid_placements` list as the schema.
- Template dropdown — luxury templates + `image` fallback.
- Widget type dropdown — populated from `Banner.valid_widget_types/0`.
- Per-template param fields rendered dynamically from `@template_params` / `@enum_params`.
- Image/logo upload hook (`BannerAdminUpload`) pushes files to ImageKit origin.
- `sort_order` — lower displays first when a placement has multiple active rows.

Live edits take effect immediately. Seed runs only on deploy (or manually) — admin UI is the day-to-day lever.

---

## 8. Adding a new template or widget

**New template ad:**
1. Add a `def ad_banner(%{banner: %{template: "new_name"}})` clause in `design_system.ex`.
2. Add `"new_name"` to `@valid_templates` in `ads/banner.ex`.
3. Add the admin form params in `@templates` + `@template_params` in `banners_admin_live.ex`.
4. Add any banner rows to `seeds_banners.exs`.
5. Document param shape in [`luxury_ad_templates.md`](luxury_ad_templates.md) if luxury vertical.

**New widget:**
1. Build component at `lib/blockster_v2_web/components/widgets/new_name.ex`.
2. Import + add a `widget_or_ad` clause in `widget_components.ex`.
3. Add `"new_name"` to `@valid_widget_types` in `ads/banner.ex`.
4. If it has a landscape/portrait pair, add a `mobile_swap/1` clause in `widget_components.ex`.
5. Add banner rows to `seeds_banners.exs`.
6. Document in [`solana/realtime_widgets_plan.md`](solana/realtime_widgets_plan.md) or [`coin_flip_widgets_plan.md`](coin_flip_widgets_plan.md).

**New class-based dedupe group:** add a clause in `banner_key/1` inside `post_live/show.ex`.

---

*Keep this file up to date when the placement enum, dedupe classes, mobile-swap map, or seed script change. Everything else is code/comment-level and doesn't need to live here.*
