# Homepage · redesign plan

> Part of the existing-pages redesign release. See `redesign_release_plan.md`
> for context. Big-bang cutover, no per-page feature flag.

## What this replaces

| Field | Value |
|---|---|
| LiveView module | `lib/blockster_v2_web/live/post_live/index.ex` |
| Template | `lib/blockster_v2_web/live/post_live/index.html.heex` |
| Route(s) | `/` (live route in `:default` live_session) |
| Mock file | `docs/solana/homepage_mock.html` |
| Bucket | **B-ish** — the release plan calls this Bucket A (visual refresh), but the mock introduces several brand-new named sections (Hero / AI × Crypto / Trending mosaic / Hub showcase / Watch / From the editors / Hubs you follow / Recommended for you / Welcome hero / What you unlock) on top of, or in place of, the current infinite-scroll feed. Several of those sections need backend data the existing LiveView doesn't fetch yet. None of it changes the schema. |
| Wave | 1 |

## Mock structure (top to bottom)

| # | Section | Anonymous? | Logged-in? | Data source | Status |
|---|---|---|---|---|---|
| 1 | **Hero · Magazine-cover featured article** (eyebrow "Today's Story" + huge title + hub badge + author byline + lime BUX reward + Read article CTA) | ✅ | ✅ | `Blog.list_published_posts_by_date(limit: 1)` — most recent post | ✅ Real |
| 2 | **AI × Crypto** category row (3 cards) | ✅ | ✅ | `Blog.list_published_posts_by_date_category("ai", limit: 3)` | ✅ Real |
| 3 | **Trending** mosaic (14 mixed-size cards, with filter chips All / DeFi / L2s / AI × Crypto / Stables / RWA) | ✅ | ✅ | `Blog.list_published_posts_by_date(limit: 14)` ordered by `view_count desc` | ✅ Real (filter chips inert in v1) |
| 4 | **Sponsored** ad slot (Helios stat showcase in mock) | ✅ | ✅ | Existing `homepage_inline_desktop` / `homepage_inline_mobile` ad banners (`@inline_desktop_banners`) | ✅ Real (reuses existing ad banner system) |
| 5 | **Hub showcase** (8 hub cards + "+ N more hubs" tile) | ✅ | ✅ | `Blog.list_hubs()` ordered by post count | ✅ Real |
| 6 | **Upcoming token sales** (3 brand-color cards) | ✅ | ✅ | **No backend** — Sales context ships in the events/sales release | ⚠ STUB ("Coming soon" cards) |
| 7 | **Sponsored** Forbes-style follow strip ("Follow Moonpay in Hubs") | ✅ | ✅ | Same `@inline_desktop_banners` rotation | ✅ Real (reuses existing ad banner system) |
| 8 | **Watch** section (1 big + 2 medium + 4 small video cards) | ✅ | ✅ | `Blog.list_published_posts_by_date(limit: 7)` filtered by `video_url != nil` | ✅ Real (new context fn needed) |
| 9 | **From the editors** (4 large cards) | ✅ | ✅ | Top 4 posts by `view_count desc` not already shown above | ✅ Real (proxy for "editorial pick" — no `:featured` flag exists) |
| 10 | **Sponsored** quote/testimonial card (Meridian) | ✅ | ✅ | Same ad banner rotation | ✅ Real |
| 11 | **Sponsored** Moonpay split-bottom card | ✅ | ✅ | Same ad banner rotation | ✅ Real |
| 12 | **Welcome / Sign-in hero** (anonymous CTA — dark gradient + big title + Connect Wallet) | ✅ | ❌ | Static copy + Connect Wallet button (fires existing `show_wallet_selector`) | ✅ Real |
| 13 | **What you unlock** (3 feature cards) | ✅ | ❌ | Static copy | ✅ Real |
| 14 | **From hubs you follow** (8 cards in 4-col grid + chip filter per hub) | ❌ | ✅ | `Blog.list_published_posts_by_date` filtered by `hub_id in @current_user.followed_hub_ids` | ✅ Real (need new context fn `Blog.list_posts_from_followed_hubs/2`) |
| 15 | **Recommended for you** (3 horizontal cards) | ❌ | ✅ | **No backend** — no recommendation system exists | ⚠ STUB ("Coming soon" / hide entirely / use a simple heuristic — TBD) |
| 16 | **Infinite-scroll feed tail** (the existing cycling PostsThree/Four/Five/Six layout components) | ✅ | ✅ | Existing `Blog.list_published_posts_by_date(offset:)` paged | ⚠ DECISION NEEDED — keep, drop, or simplify? |
| 17 | **Footer** | ✅ | ✅ | Static (DesignSystem `<.footer />`) | ✅ Real |

## Visual components consumed

From `lib/blockster_v2_web/components/design_system.ex`:

- `<.header current_user={@current_user} active="home" bux_balance={…} cart_item_count={@cart_item_count} unread_notification_count={@unread_notification_count} />` ✓ existing (Wave 0)
- `<.footer />` ✓ existing (Wave 0)
- `<.eyebrow>…</.eyebrow>` ✓ existing
- `<.chip variant="active|default">…</.chip>` ✓ existing
- `<.author_avatar initials="MV" size="md" />` ✓ existing
- `<.post_card href image hub_name hub_color title author read_minutes bux_reward />` ✓ existing
- `<.hero_feature_card />` ⚠ NEW — Variant B magazine-cover hero (7-col image + 5-col title/byline/CTA)
- `<.section_header eyebrow title see_all_href />` ⚠ NEW — the eyebrow + section title + "See all →" pattern repeated across every section
- `<.mosaic_grid />` + `<.mosaic_card variant="big|medium|small" />` ⚠ NEW — the 12-col 180px-row mosaic with mixed-size cards
- `<.hub_card name primary secondary post_count reader_count sponsor=true />` ⚠ NEW — full-bleed brand-color hub card with Follow button
- `<.video_card variant="big|medium|small" />` ⚠ NEW — post card with play overlay + duration badge + LIVE/NEW pill
- `<.editorial_card />` ⚠ NEW — bigger version of post_card with description, used in "From the editors" section
- `<.welcome_hero />` ⚠ NEW — the dark gradient anonymous-only CTA section (welcome eyebrow in lime, huge dual-tone title, Connect Wallet button, stats row, tilted preview card)
- `<.what_you_unlock_grid />` ⚠ NEW — the 3-feature card grid for anonymous users
- `<.coming_soon_card variant="token_sale" />` ⚠ NEW — the token sale card stub for D12-style placeholders (different from the article-page version which is `variant="event|sale|airdrop"`)
- `<.recommendation_card />` ⚠ NEW (or hidden if we drop the section)

That's roughly **9 new components** for this page alone. They get tests as we build them.

## Data dependencies

### ✓ Existing — already in production, no work needed

- `@current_user` (assigned by `BlocksterV2Web.UserAuth` `on_mount`)
- `@token_balances` (assigned by UserAuth's `sync_balances_on_nav`)
- `@cart_item_count` (assigned by `BlocksterV2Web.NotificationHook`? — need to verify which hook owns it)
- `@unread_notification_count` (assigned by `BlocksterV2Web.NotificationHook`)
- Existing `Blog` API: `list_published_posts_by_date/1`, `list_published_posts_by_date_category/2`, `list_hubs/0`, `search_posts_fulltext/2`
- Existing `EngagementTracker.subscribe_to_all_bux_updates/0` and `:bux_update` PubSub
- Existing `bux_balances` map flow (post `id => total_distributed BUX`)
- Existing ad banner infrastructure (`Ads.list_active_banners_by_placement/1`)
- Existing `current_user.followed_hubs` association (via `hub_followers` join table) — but no context fn yet to query "posts from these hubs"

### ⚠ Stubbed in v1 — documented, fixed in a later release

- **Upcoming token sales section** — no Sales context, no migrations. Renders as `<.coming_soon_card variant="token_sale" />` cards with hardcoded "Coming soon — first sale launches [month]" copy. Replaces a real `<.token_sale_card />` in the events/sales release with no template change. Tracked in master stub register.
- **Recommended for you section (logged-in only)** — no recommendation system exists. **Three options for v1**:
  1. Hide entirely until backend lands (cleanest)
  2. Show "Coming soon" placeholder card explaining personalization is on the way
  3. Use a simple heuristic — e.g., "posts in the same hubs as the user's most recently read post" — and label it accurately
  
  I default to **option 1 (hide entirely)** because option 2 visually clutters the personalized area and option 3 needs new context functions and may give weird results before any read history exists. Tracked in master stub register.
- **Trending filter chips (DeFi / L2s / AI × Crypto / Stables / RWA)** — visual only in v1. Clicking a chip is a no-op. The "All" chip is permanently active. The chip-filtered fetches need new context functions (filter by tag/category) which we can add in a follow-up. Tracked in master stub register.
- **Editorial picks** — no `:editorial_pick` boolean exists on `posts`. v1 uses "top 4 by view_count not already shown above" as a proxy. When an editorial-pick flag is added later, the section becomes a `Blog.list_editorial_picks/1` query with no template change.
- **"From hubs you follow" hub-filter chips** — need to render real followed-hub colors but the chip click-to-filter is inert in v1 (always shows All).

### ✗ New — must be added or schema-migrated for this page to ship

- **Context function**: `Blog.list_published_videos/1` — filters `published_posts_query()` by `video_url != nil`. Returns posts ordered by `published_at desc`.
- **Context function**: `Blog.list_posts_from_followed_hubs(user, opts)` — joins `posts -> hub_followers -> users` and filters by user_id. Returns posts ordered by `published_at desc`.
- **No schema migrations.** All needed fields already exist (`video_url`, `video_duration`, `featured_image`, `excerpt`, `view_count`, `bux_total`, `hub_id`, `category_id`, etc.).

## Handlers to preserve

Every `phx-click`, `phx-submit`, `start_async`, and PubSub topic the existing `PostLive.Index` fires. The new template MUST keep these wired up:

| Handler / event | Why | New template uses it? |
|---|---|---|
| `phx-click="search_posts"` (via header search) | Live search dropdown | Yes (header search button opens overlay; existing handler runs from `:live_view` macro) |
| `phx-click="close_search"` | Close search dropdown | Yes |
| `phx-click="toggle_notification_dropdown"` | Notification bell | Yes (header bell button) |
| `phx-click="show_wallet_selector"` | Connect Wallet button | Yes (anonymous header + welcome hero CTA) |
| `phx-click="open_mobile_search"` / `"close_mobile_search"` | Mobile search overlay | Probably not in v1 — search overlay is desktop-only via icon button |
| `phx-click="load-more"` | Infinite scroll | **Decision point — see scope question** |
| `phx-click="open_bux_deposit_modal"` (admin only) | Quick BUX top-up modal | Yes (admin-only — modal stays as-is in the new template) |
| `phx-click="close_bux_deposit_modal"`, `phx-submit="deposit_bux"` | Same modal | Yes |
| `EngagementTracker.subscribe_to_all_bux_updates/0` | Real-time BUX updates on post cards | Yes (post cards still need to update their BUX badges on `:bux_update`) |
| `:bux_update` PubSub message handler | Same | Yes — but need to figure out how to route the update to the new section components without going through `send_update` to the old `PostsThreeComponent` etc. |
| `:posts_reordered` PubSub message handler | No-op currently | Yes (kept as-is) |

## Locked-in scope (decided 2026-04-09)

The new homepage is **structurally similar to the existing one** — posts in
date-desc order, infinite scroll forever — but the visual layouts come from
the mock. The mock's named sections become the new cycling layout components
that REPLACE the existing PostsThree / PostsFour / PostsFive / PostsSix
cycling components. Some sections of the mock are one-off marketing /
identity sections that render exactly once and never repeat in the cycle.

### One-shot sections (initial mount only, never re-rendered by load-more)

Rendered in this order at natural mock positions:

1. **Hero featured article** — `Blog.list_published_posts_by_date(limit: 1)` (most recent post)
2. **AI × Crypto cycling layout** (cycle batch 1)
3. **Trending mosaic** (cycle batch 1)
4. **Hub showcase** — `Blog.list_hubs/0` ordered by post count, top 8. No `is_sponsor` flag — all rendered as regular hub cards. The "+ N more hubs" tile links to `/hubs`.
5. **Upcoming token sales · STUB** — 3 `<.coming_soon_card variant="token_sale" />` placeholder cards. Tracked in master stub register. Replaced by real `<.token_sale_card />` in events/sales release with no template change.
6. **Watch layout** (cycle batch 1, video-filtered)
7. **Editorial layout** (cycle batch 1)
8. *(anonymous only)* **Welcome hero** — dark gradient CTA, Connect Wallet button fires existing `show_wallet_selector` handler
9. *(anonymous only)* **What you unlock** — 3 feature cards static copy
10. *(logged-in only)* **Hubs you follow** — `Blog.list_posts_from_followed_hubs(user, limit: 8)` in 4-col grid. Filter chips inert in v1 (always show All).
11. *(logged-in only)* **Recommended for you · STUB** — single `<.coming_soon_card variant="recommended" />` placeholder explaining personalization is on the way. Replaced by real recommendation system in a later release.

### Cycling sections (infinite scroll · feeds posts in date-desc order)

After the one-shots, the page cycles through these layouts ad infinitum:

| Order | Layout | Posts consumed | Visual |
|---|---|---|---|
| 1 | `<.three_column_layout />` (the AI × Crypto row) | 3 | 3-col grid of `<.post_card />` |
| 2 | `<.mosaic_layout />` (the Trending mosaic) | 14 | 12-col mosaic with mixed-size cards (1 big, 2 medium, 4 small, 1 medium, 1 big, 1 medium, 4 small) |
| 3 | `<.video_layout />` (the Watch grid) | 7 (filtered by `video_url != nil`) | 1 big + 2 medium + 4 small video cards. **SKIPPED when fewer than 7 video posts remain in the next batch.** |
| 4 | `<.editorial_layout />` (the From the editors grid) | 4 | 2x2 large editorial cards with descriptions |

Each cycle consumes 28 posts when the video layout fires, 21 posts when it
doesn't. After the editorial layout, the cycle restarts at `three_column`.

### Filter chips · all inert in v1

- Trending mosaic chips (DeFi / L2s / AI × Crypto / Stables / RWA): rendered for visual fidelity, click does nothing, "All" permanently active.
- Hubs you follow chips (per-hub filter): same — rendered with the hub's brand color, click is a no-op, "All" permanently active.
- Wired up in a follow-up commit after the first eyeball pass.

## Tests required

Tests written and passing before this page is considered done.

### Component tests (Wave 1 · added by this page)
- `test/blockster_v2_web/components/design_system/hero_feature_card_test.exs`
- `test/blockster_v2_web/components/design_system/section_header_test.exs`
- `test/blockster_v2_web/components/design_system/mosaic_grid_test.exs` (and `mosaic_card`)
- `test/blockster_v2_web/components/design_system/hub_card_test.exs`
- `test/blockster_v2_web/components/design_system/video_card_test.exs`
- `test/blockster_v2_web/components/design_system/editorial_card_test.exs`
- `test/blockster_v2_web/components/design_system/welcome_hero_test.exs`
- `test/blockster_v2_web/components/design_system/what_you_unlock_grid_test.exs`
- `test/blockster_v2_web/components/design_system/coming_soon_card_test.exs`

### LiveView template extension
- New file: `test/blockster_v2_web/live/post_live/index_test.exs` — there is currently no LiveView test for the homepage. The new test file asserts:
  - Page renders anonymous (Welcome hero + Unlock grid present, "Hubs you follow" + "Recommended for you" sections absent)
  - Page renders logged-in (Welcome hero + Unlock grid absent, BUX pill present in header, "Hubs you follow" section present)
  - Hero featured card shows the most recent post's title
  - Hub showcase shows up to 8 hubs from `Blog.list_hubs()`
  - Token sales section renders Coming Soon stub cards
  - All existing handlers still fire (`load-more`, `search_posts`, `open_bux_deposit_modal` for admin, etc.)
  - PubSub `:bux_update` still updates the right post card's BUX badge

### Manual checks
- Page renders logged in (with a connected wallet)
- Page renders anonymous (no wallet)
- Every CTA has a working handler or is documented as a stub
- Search works (header button opens overlay → typing triggers `search_posts`)
- Notification bell opens dropdown
- Cart icon shows count
- Connect Wallet button (anonymous) opens wallet selector
- Welcome hero "Connect Wallet to start earning" button (anonymous) opens wallet selector
- Hub cards link to the right `/hub/:slug` route
- Post cards link to the right `/:slug` route
- Real-time BUX update on a post card still works (verify by triggering one in another tab)
- Admin-only "Quick BUX deposit" modal still opens via `phx-click="open_bux_deposit_modal"` (test as admin)
- `mix test` zero NEW failures relative to baseline

## Per-page commit message

`redesign(homepage): rebuild against design system · hero / mosaic / hub showcase / video grid / welcome hero`

## Resolved decisions

| # | Question | Answer |
|---|---|---|
| 1 | Scope | Cycling layouts in date-desc order with infinite scroll, named-section one-offs interleaved at natural mock positions. |
| 2 | Recommended for you stub | Single `<.coming_soon_card variant="recommended" />` placeholder ("Coming soon — personalized recommendations launch soon"). Logged-in only. |
| 3 | Trending filter chips | Inert in v1. Wired up in a follow-up commit. |
| 4 | Hub showcase order | Post count desc. Top 8 hubs only. |
| 5 | Hub Sponsor badge | Dropped in v1. No schema migration. All hubs render as regular cards. |
| 6 | Watch section minimum | 7 video posts per layout instance. Skipped from a cycle when fewer than 7 video posts remain in the next batch. |
| 7 | Editorial picks proxy | Posts in date-desc order from the next batch (no `view_count`-based proxy needed since the cycle is just consuming the date-ordered feed). |
| 8 | `load-more` behavior | Keeps working exactly as today. Each load-more appends one full cycle (AI × Crypto → Trending → [Watch if videos available] → Editorial). |
| 9 | Hubs you follow filter chips | Inert in v1. Same as trending. Wired up in a follow-up. |
