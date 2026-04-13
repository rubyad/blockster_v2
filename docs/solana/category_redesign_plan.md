# Category Browse · redesign plan

> Part of the existing-pages redesign release. See `redesign_release_plan.md`
> for context. Big-bang cutover, no per-page feature flag.

## What this replaces

| Field | Value |
|---|---|
| LiveView module | `lib/blockster_v2_web/live/post_live/category.ex` |
| Template | `lib/blockster_v2_web/live/post_live/category.html.heex` |
| Route(s) | `/category/:category` |
| Mock file | `docs/solana/category_mock.html` |
| Bucket | **A** — pure visual refresh, no schema changes, no new contexts |
| Wave | 5 (Page #16 — second page of Wave 5 Discovery) |

## Mock structure (top to bottom)

1. **Page hero** — editorial title hero (reuses `<.page_hero>`):
   - Eyebrow: "Category · [full name]"
   - Big `article-title` h1: category name (e.g. "DeFi")
   - Description paragraph (from `category.description`)
   - 3-stat right column: Posts (count), Readers (total view_count), BUX paid (total bux_earned)

2. **Featured post** — editor's pick section (reuses `<.hero_feature_card>`):
   - Eyebrow: "Editor's pick · [category]", meta: "Updated [time_ago]"
   - Large 16:11 image left (7-col), text right (5-col)
   - Hub badge + category label
   - Big `article-title` h2 + excerpt + author byline + BUX reward pill
   - "Read article" CTA button

3. **Filter + mosaic grid** — post grid section:
   - `<.section_header>` with eyebrow "[N] stories" + title "All [category] posts"
   - Filter chips: Trending / Latest / Most earned / Long reads (stubs — no sort handler change)
   - CSS grid mosaic with varied card sizes:
     - 1 large dark-overlay card (col-span-7, row-span-2)
     - 2 horizontal side cards (col-span-5, row-span-1 each)
     - 4+ small vertical cards (col-span-3, row-span-1 each)
   - "Load more" via existing InfiniteScroll hook

4. **Related categories** — 6-col grid:
   - Eyebrow: "Browse other categories"
   - Title: "If you like [category], you'll like"
   - Cards: white rounded-2xl, category name + post count, link to `/category/:slug`

5. **Featured author** — large author showcase card:
   - Eyebrow: "Most read author in [category]"
   - Title: "Featured writer"
   - Card: 3-col grid (avatar 3-col + bio 6-col + follow button 3-col)
   - Author stats: Posts / Reads / BUX paid out
   - "+ Follow" button (inert stub)

## Decisions applied from release plan

- **Bucket A**: no schema, no new contexts, no new on-chain calls.
- **Route moves**: `/category/:category` moves from `:default` to `:redesign` live_session.
- **Legacy preservation**: copy current files to
  `lib/blockster_v2_web/live/post_live/legacy/category_pre_redesign.ex` and
  `lib/blockster_v2_web/live/post_live/legacy/category_pre_redesign.html.heex`.
- **No new DS components needed** — all sections use existing DS components
  (`page_hero`, `hero_feature_card`, `section_header`, `chip`, `post_card`,
  `eyebrow`, `author_avatar`, `header`, `footer`) plus inline Tailwind for
  the mosaic large/horizontal card variants and the related-categories/featured-author
  cards (one-off patterns, not worth abstracting).
- **No new schema migrations.**
- **Filter chips are inert stubs** — the existing `sort_mode` assign stays at
  "latest" (the only mode the existing `build_components_batch` supports). The
  chips render but clicking doesn't change behavior. Stub-registered.
- **Featured author is a stub** — uses the first post's author from the initial
  batch. The mock shows a rich author card; we populate what we can from the
  author's User record. "+ Follow" button is inert. Stub-registered.
- **`live_component` removal**: the existing template delegates post rendering to
  4 cycling LiveComponents (`PostsThreeComponent` etc.). The redesign renders posts
  directly from the stream items' `:posts` field using inline Tailwind mosaic
  markup. The `send_update` call in `handle_info(:bux_update)` is removed — the
  assign-level `@bux_balances` update still happens, but individual stream items
  don't re-render in real time (BUX amounts update on next page load or load-more).
  This is acceptable for a category listing page.

## Visual components consumed

- `<BlocksterV2Web.DesignSystem.header />` ✓ existing (active="home")
- `<BlocksterV2Web.DesignSystem.footer />` ✓ existing
- `<BlocksterV2Web.DesignSystem.page_hero />` ✓ existing
- `<BlocksterV2Web.DesignSystem.hero_feature_card />` ✓ existing
- `<BlocksterV2Web.DesignSystem.section_header />` ✓ existing
- `<BlocksterV2Web.DesignSystem.chip />` ✓ existing
- `<BlocksterV2Web.DesignSystem.post_card />` ✓ existing (for small mosaic cards)
- `<BlocksterV2Web.DesignSystem.eyebrow />` ✓ existing
- `<BlocksterV2Web.DesignSystem.author_avatar />` ✓ existing

**No new DS components needed.**

## Data dependencies

### ✓ Existing — already in production

- `@category` (string) — category name, from `Blog.get_category_by_slug/1`
- `@category_slug` (string) — URL slug
- `@page_title` (string)
- `@sort_mode` (string) — currently always "latest"
- `@show_why_earn_bux` (boolean) — true
- `@displayed_post_ids` (list) — IDs of posts already rendered
- `@bux_balances` (map) — post_id → distributed BUX
- `@user_post_rewards` (map) — post_id → earned rewards
- `@post_to_component_map` (map) — post_id → {component_id, module}
- `@last_component_module` — tracks cycling position
- `@top_desktop_banners`, `@top_mobile_banners`, `@inline_desktop_banners`, `@inline_mobile_banners` — ad banners
- `@inline_banner_offset` — counter for rotating inline ads
- `@streams.components` — stream of component batches with posts

### ⚠ New assigns — additions for mock fidelity

- **`@category_record`** (Category struct) — full category record (need `.description`)
- **`@post_count`** (integer) — `Blog.count_published_posts_by_category/1`
- **`@total_readers`** (integer) — sum of `view_count` across category posts
- **`@total_bux_paid`** (integer) — sum of `bux_earned` across category posts
- **`@featured_post`** (Post struct | nil) — first post from initial batch, separated for hero_feature_card
- **`@related_categories`** (list of Category) — `Blog.list_categories/0` minus current
- **`@featured_author`** (User struct | nil) — author of the featured post (stub — future: most-read author)
- **`@filter`** (string) — currently selected filter chip, default "trending" (inert, no handler)

### ✗ New — must be added or schema-migrated

None. Bucket A. All new assigns derive from existing schema fields and context functions.

## Handlers to preserve

**`handle_event`:**
- `"load-more"` — InfiniteScroll infinite loading. Fires `build_components_batch`, streams new items. **Preserved exactly.**

**`handle_info`:**
- `{:bux_update, post_id, _pool_balance, total_distributed}` — PubSub from `"post_bux:all"`. Updates `@bux_balances` assign. **`send_update` call removed** (no more live_components), but the assign update stays.
- `{:bux_update, _post_id, _new_balance}` — legacy 3-element broadcast. **Preserved.**
- `{:posts_reordered, _post_id, _new_balance}` — **Preserved.**
- Catch-all `_msg` — **Preserved.**

**PubSub subscriptions:**
- `"post_bux:all"` — subscribed in `mount/3` under `connected?(socket)`. **Preserved.**

## JS hooks

- **`InfiniteScroll`** — on the `#category-components` stream container. Fires `"load-more"` event. **Preserved.**
- **`SolanaWallet`** — on the DS header (`#ds-site-header`). Auto-injected by the header component. **No changes.**

No new JS hooks.

## Tests required

### Component tests

None — no new DS components.

### LiveView tests

**Create** `test/blockster_v2_web/live/post_live/category_test.exs`.

**Assertions:**

- **Page renders with DS header**: assert `ds-site-header` element present
- **Page hero renders**: assert category name in h1, eyebrow contains "Category"
- **Stat cards render**: assert "Posts", "Readers", "BUX paid" stat labels
- **Featured post renders**: assert `ds-hero-feature` section present (when posts exist)
- **Filter chips render**: assert "Trending", "Latest", "Most earned", "Long reads" chip text
- **Mosaic grid renders**: assert post titles from seeded posts appear
- **Related categories render**: assert "Browse other categories" eyebrow
- **Featured author card renders**: assert "Featured writer" heading
- **DS footer renders**: assert footer element present
- **Category not found redirects**: assert redirect to "/" when slug doesn't match
- **Anonymous access works**: page renders without current_user

### Manual checks (on `bin/dev`)

- Page renders at `/category/[valid-slug]` logged in
- Page renders anonymous
- Page hero shows correct category name + description + stats
- Featured post links to article
- Filter chips render (inert)
- Mosaic grid shows posts with varied card sizes
- Scroll down triggers infinite scroll (new posts load)
- Related categories link to valid `/category/:slug` routes
- Featured author card renders with author info
- No console errors
- `mix test` — zero new failures vs baseline

## Per-page commit message

`redesign(category): category browse refresh · editorial hero + featured post + mosaic grid + related categories + featured author card`

## Stubbed in v1

| Stub | What it shows now | What replaces it | Release |
|---|---|---|---|
| Filter chips | Render but click is no-op; "Trending" permanently active | `phx-click="set_filter"` handler with sort_mode changes | Follow-up commit |
| Featured author "+ Follow" button | Inert, no handler | Real follow system | Follow-up release |
| Featured author selection | Uses first post's author | Real most-read-author aggregation query | Analytics release |
| Readers stat | Sum of view_count | Proper 30-day rolling reader count | Analytics release |

## Open items

None. All mock elements either map to existing data or are documented stubs.
