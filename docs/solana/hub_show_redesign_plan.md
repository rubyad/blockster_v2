# Hub show · redesign plan

> Part of the existing-pages redesign release. See `redesign_release_plan.md`
> for context. Big-bang cutover, no per-page feature flag.

## What this replaces

| Field | Value |
|---|---|
| LiveView module | `lib/blockster_v2_web/live/hub_live/show.ex` |
| Template | `lib/blockster_v2_web/live/hub_live/show.html.heex` |
| Route(s) | `/hub/:slug` (moved from `:default` to `:redesign` live_session) |
| Mock file | `docs/solana/hub_show_mock.html` |
| Bucket | **B** — visual refresh + schema migration (`posts.kind`) |
| Wave | 1 |

## Mock structure (top to bottom)

The mock shows a hub-specific page with a brand-color hero and tabbed content:

| # | Section | Description | Status |
|---|---|---|---|
| 1 | **Hub banner** (Variant C) | Full-bleed gradient using hub brand colors. Identity block (80px logo + name + badges), description, stats row (Posts/Followers/BUX Paid/Authors), CTAs (Follow Hub/Notify me), social icons, live activity widget (frosted glass card on right) | REAL (except live activity widget is STUB) |
| 2 | **Sticky tab nav** | 5 tabs: All / News / Videos / Shop / Events with mono counts. Active tab has brand-color underline. | REAL |
| 3 | **All tab** | Pinned post, latest stories mosaic, authors strip, inline sponsored ad, about + stats card | REAL (pinned = first post, ad is hub-branded placeholder) |
| 4 | **News tab** | Mosaic of posts with `kind = :news` | REAL (empty until editors categorize posts) |
| 5 | **Videos tab** | Featured video + sidebar stack (uses `video_id` filter) | REAL |
| 6 | **Shop tab** | 4-col product grid with hub color dot | REAL (uses existing hub→product relation) |
| 7 | **Events tab** | Empty state: white card "No events yet from this hub" + inert "Notify me" | STUB (D15) |

### Hub banner breakdown

Full-bleed section using `linear-gradient(135deg, hub.color_primary, hub.color_secondary)`:
- Dot pattern overlay (radial-gradient, 32px grid)
- Top-right blur glow (radial-gradient, 50% width)
- Breadcrumb: "Hubs / {hub.name}"
- Identity block: 80px rounded-2xl glass logo square + name (56-68px) + badges (Sponsor lime pill, Verified glass pill)
- Description: 18px white/85, max-w 640px
- Stats row: Posts / Followers / BUX Paid / Authors — 28px mono bold, 10px uppercase labels, separated by 1px dividers
- CTAs: lime "Follow Hub" button, glass "Notify me" button, social icon circles (website/X/telegram/discord)
- Right column (md:col-span-4): frosted glass "Latest Activity" widget

### Sticky tab nav breakdown

Sticky below header (`top: 84px`), frosted glass background:
- 5 tab buttons with mono count badges
- Active tab: bold text + 2px brand-color underline

### Pinned post breakdown

12-col grid: 7-col image left (16/11 aspect, brand color "Pinned" badge), 5-col text right:
- Hub badge + hub name + category/genre label
- 44-52px article-title
- 16px description
- Author avatar + name + read time + BUX earn badge
- Dark "Read article" CTA that hovers to hub brand color

### Mosaic breakdown

Same mosaic pattern as homepage: big feature (7-col 2-row), medium (5-col 1-row) × 2, small (3-col 1-row) × 4.
- Category chips above: All / News / Analysis / Product / Compliance (stub — visual only)
- Each card links to article

### Shop tab breakdown

4-col product grid. Each card:
- Square image with hub color dot badge (top-left)
- Product name (14px bold)
- Price: strikethrough original + discounted price + "with BUX tokens"
- Dark "Buy Now" button

### Events tab empty state (D15)

White card with border: "No events yet from this hub" heading + "Notify me" inert button.

## Visual components consumed

- `<DesignSystem.header />` ✓ existing (Wave 0)
- `<DesignSystem.footer />` ✓ existing (Wave 0)
- `<DesignSystem.eyebrow />` ✓ existing (Wave 0)
- `<DesignSystem.chip />` ✓ existing (Wave 0)
- `<DesignSystem.author_avatar />` ✓ existing (Wave 0)
- `<DesignSystem.hub_banner />` **NEW** — must be built before this page
- No other new design_system components needed — remaining sections (tabs, mosaic, pinned post, shop grid, events empty state) are inlined in the template since they're page-specific.

## Data dependencies

### ✓ Existing — already in production, no work needed

- `@hub` — `Blog.get_hub_by_slug_with_associations(slug)` (preloads followers, posts, events)
- `@hub.name`, `@hub.slug`, `@hub.description`, `@hub.logo_url`
- `@hub.color_primary`, `@hub.color_secondary`
- `@hub.website_url`, `@hub.twitter_url`, `@hub.telegram_url`, `@hub.discord_url`
- `@hub.token` — short symbol for logo square fallback
- `@current_user` — from UserAuth on_mount
- `@bux_balance` — from BuxBalanceHook on_mount
- `@user_follows_hub` — `Blog.user_follows_hub?(user.id, hub.id)`
- `@follower_count` — `Blog.get_hub_follower_count(hub.id)`
- `@hub_products` — `Shop.list_products_by_hub(hub.id)`
- `@videos_posts` — `Blog.list_video_posts_by_hub(hub.id, ...)`
- `@posts_three`, `@posts_four` — `Blog.list_published_posts_by_hub(hub.id, ...)`

### ✓ Computed from existing data — no new queries needed

- `@post_count` — `length(hub.posts)` or count from association
- `@pinned_post` — first post from `@all_posts` (most recent)
- `@mosaic_posts` — remaining posts after pinned (next 7-8 posts)
- `@all_posts` — all published posts for this hub
- `@news_count`, `@video_count` — counts filtered by kind/video_id

### ⚠ Stubbed in v1

- **Live activity widget**: renders static placeholder data (3-4 hardcoded activity items). Will be replaced by real-time PubSub-driven activity feed in a follow-up.
- **Category filter chips on All tab mosaic**: chips render but click is a no-op. "All" permanently active.
- **"Notify me" button on hub banner**: inert button with no handler.
- **"Sponsor" / "Verified" badges**: hardcoded static badges. No badge system exists yet.
- **Authors strip**: deferred per D13 (no Authors tab), but the "Authors writing in [hub]" section in All tab is also deferred to simplify v1.
- **"About this hub" section**: deferred to simplify v1 (shown in mock All tab but not critical for launch).
- **Inline sponsored ad**: deferred — the ad banner system exists but hub-specific sponsored ads are not seeded yet.

### ✗ New — must be added for this page to ship

- **Schema migration**: `add_kind_to_posts` adds `posts.kind :: string` with values `news`, `video`, `other`, default `other`. Backfills all existing posts as `other`.
- **Context function**: `Blog.list_posts_by_hub_and_kind/3` filters posts within a hub by the `kind` field.

## Handlers to preserve

All existing handlers from `HubLive.Show`:

- `handle_event("toggle_mobile_menu", ...)` — toggles mobile tab dropdown
- `handle_event("close_mobile_menu", ...)` — closes mobile dropdown
- `handle_event("switch_tab", %{"tab" => tab}, ...)` — switches active tab (all/news/videos/shop/events)
- `handle_event("update_hub_logo", %{"logo_url" => url}, ...)` — admin logo upload
- `handle_event("toggle_follow", ...)` — follow/unfollow hub
- `handle_event("load-more-news", ...)` — infinite scroll for news tab (removed in redesign — news tab uses simple mosaic)

## Tests required

### Component tests

- `test/blockster_v2_web/components/design_system/hub_banner_test.exs` — new component tests for the brand-color full-bleed banner (renders with hub data, shows stats, shows social icons, follow button)

### LiveView tests

- `test/blockster_v2_web/live/hub_live/show_test.exs` — **NEW** file (no existing test)
  - Page renders with hub data (name, description)
  - Hub banner section present with brand gradient
  - Tab navigation renders 5 tabs (All/News/Videos/Shop/Events)
  - All tab shows posts from the hub
  - Switching tabs works (switch_tab event)
  - Events tab shows empty state
  - Shop tab shows products when available
  - Shop tab shows empty state when no products
  - Follow button renders for anonymous users
  - Follow button renders for logged-in users
  - Hub not found redirects to homepage
  - Design system header and footer present

### Manual checks

- Page renders logged in
- Page renders anonymous
- Hub banner uses correct brand colors
- Tab switching works
- Follow/Unfollow works
- Shop products link to correct `/shop/:slug`
- Post cards link to correct `/:slug`
- `mix test` zero new failures vs baseline

## Per-page commit message

`redesign(hub-show): brand banner + 5-tab nav + posts.kind migration + shop/events stubs`

## Stubbed in v1

| Stub | What it shows now | What replaces it | Resolved by release |
|---|---|---|---|
| Live activity widget | Static placeholder (4 hardcoded items) | Real-time PubSub activity feed | Hub activity system release |
| Sponsor/Verified badges | Static hardcoded badges | Dynamic badge system based on hub metadata | Badge system release |
| Events tab content | Empty state: "No events yet" | Real events list from Events context | Events release |
| Category filter chips on mosaic | Visual-only chips, "All" always active | Working filter by post category | Follow-up commit |
| Notify me button | Inert button, no handler | Real notification subscription system | Notification subscription release |

## Open items

None — all decisions are locked (D13-D16). The migration is straightforward and the component extraction is minimal.
