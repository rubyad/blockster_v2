# Tag Browse · redesign plan

> Part of the existing-pages redesign release. See `redesign_release_plan.md`
> for context. Big-bang cutover, no per-page feature flag.

## What this replaces

| Field | Value |
|---|---|
| LiveView module | `lib/blockster_v2_web/live/post_live/tag.ex` |
| Template | `lib/blockster_v2_web/live/post_live/tag.html.heex` |
| Route(s) | `/tag/:tag` |
| Mock file | `docs/solana/tag_mock.html` |
| Bucket | **A** — pure visual refresh, no schema changes, no new contexts |
| Wave | 5 (Page #17 — third and final page of Wave 5 Discovery) |

## Mock structure (top to bottom)

1. **Compact tag hero** — intentionally slimmer than category hero:
   - Eyebrow: "Tag" + inline stat line "218 posts · 84k reads this month" (font-mono)
   - Big `article-title` h1: `#[tag_name]` (60px mobile, 80px desktop)
   - Description paragraph (max-w-[560px]) — **stubbed**: Tag schema has no
     `description` field. Omit in v1 (Bucket A, no schema changes).

2. **Filter row** — border-t divider with chips + post count/pagination info:
   - Chips: Latest (active) / Popular / Long reads / Most earned (stubs — no sort handler)
   - Right side: `@post_count posts · page 1 of N` (static label, no real pagination)

3. **Post grid** — straight 3-col (`grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5`):
   - Each card: white rounded-2xl, 16:9 image, hub badge + label, title (line-clamp-2),
     author + read time, BUX reward pill
   - This is NOT a mosaic (unlike category). Standard `<.post_card />`-style layout.
   - "Load more" button with remaining count, via existing `InfiniteScroll` hook

4. **Related tags** — chip cloud (flex-wrap):
   - Eyebrow: "Related tags"
   - Title: "More like #[tag_name]"
   - Chips: `#tag_name` + post count (font-mono), rounded-full white pills
   - Links to `/tag/:slug`

5. **DS footer**

## Decisions applied from release plan

- **Bucket A**: no schema, no new contexts, no new on-chain calls.
- **Route moves**: `/tag/:tag` moves from `:default` to `:redesign` live_session.
- **Legacy preservation**: copy current files to
  `lib/blockster_v2_web/live/post_live/legacy/tag_pre_redesign.ex` and
  `lib/blockster_v2_web/live/post_live/legacy/tag_pre_redesign.html.heex`.
- **`live_component` removal**: the existing template delegates post rendering to
  4 cycling LiveComponents (`PostsThreeComponent` etc.). The redesign renders posts
  directly from a flat stream of post pages using inline Tailwind card markup
  (same approach as the category redesign). The `send_update` call in
  `handle_info(:bux_update)` is removed — the assign-level `@bux_balances` update
  still happens, but individual stream items don't re-render in real time (BUX
  amounts update on next page load or load-more). Acceptable for a tag listing page.
- **No new DS components needed** — all sections use existing DS components
  (`header`, `footer`, `eyebrow`, `chip`) plus inline Tailwind for the compact
  hero, post grid cards, and related tags chip cloud.
- **No new schema migrations.**
- **Filter chips are inert stubs** — the chips render but clicking doesn't change
  behavior. Default active chip: "Latest". Stub-registered.
- **Tag description is hidden** — Tag schema has no `description` field. Adding one
  would be a schema change (violates Bucket A). The description paragraph from the
  mock is omitted. Stub-registered.

## Visual components consumed

- `<BlocksterV2Web.DesignSystem.header />` ✓ existing (active="home")
- `<BlocksterV2Web.DesignSystem.footer />` ✓ existing
- `<BlocksterV2Web.DesignSystem.eyebrow />` ✓ existing
- `<BlocksterV2Web.DesignSystem.chip />` ✓ existing

**No new DS components needed.**

## Data dependencies

### ✓ Existing — already in production

- `@tag_name` (string) — tag name, from `Blog.get_tag_by_slug/1`
- `@tag_slug` (string) — URL slug
- `@page_title` (string)
- `@sort_mode` (string) — currently always "latest"
- `@show_why_earn_bux` (boolean) — true
- `@displayed_post_ids` (list) — IDs of posts already rendered
- `@bux_balances` (map) — post_id → distributed BUX
- `@user_post_rewards` (map) — post_id → earned rewards
- `@inline_desktop_banners`, `@inline_mobile_banners` — ad banners
- `@current_user` — from UserAuth on_mount

### ⚠ New assigns — additions for mock fidelity

- **`@post_count`** (integer) — `Blog.count_published_posts_by_tag/1`
- **`@total_reads`** (integer) — sum of `view_count` across tag posts (new helper query)
- **`@related_tags`** (list of maps) — `Blog.list_tags/0` minus current, enriched with
  post counts via `Blog.count_published_posts_by_tag/1`, sorted by count desc, take 12
- **`@filter`** (string) — currently selected filter chip, default "latest" (inert stub)
- **`@page_num`** (integer) — tracks stream page number for load-more

### ✗ Removed assigns (no longer needed)

- `@post_to_component_map` — cycling LiveComponents removed
- `@last_component_module` — cycling LiveComponents removed
- `@show_categories` — not used in redesigned template
- `@top_desktop_banners` / `@top_mobile_banners` — top banners not in tag mock
- `@inline_banner_offset` — replaced by page_num-based rotation

### ✗ New — must be added or schema-migrated

None. Bucket A. All new assigns derive from existing schema fields and context functions.

## Handlers to preserve

**`handle_event`:**
- `"load-more"` — InfiniteScroll infinite loading. Simplified: fetches flat post pages
  instead of cycling component batches. **Preserved (rewritten).**

**`handle_info`:**
- `{:bux_update, post_id, _pool_balance, total_distributed}` — PubSub from `"post_bux:all"`.
  Updates `@bux_balances` assign. **`send_update` call removed** (no more live_components),
  but the assign update stays.
- `{:bux_update, _post_id, _new_balance}` — legacy 3-element broadcast. **Preserved.**
- `{:posts_reordered, _post_id, _new_balance}` — **Preserved.**
- Catch-all `_msg` — **Preserved.**

**PubSub subscriptions:**
- `"post_bux:all"` — subscribed in `mount/3` under `connected?(socket)`. **Preserved.**

## JS hooks

- **`InfiniteScroll`** — on the `#tag-posts` stream container. Fires `"load-more"` event. **Preserved.**
- **`SolanaWallet`** — on the DS header (`#ds-site-header`). Auto-injected by the header
  component. **No changes.**

No new JS hooks.

## Tests required

### Component tests

None — no new DS components.

### LiveView tests

**Create** `test/blockster_v2_web/live/post_live/tag_test.exs`.

**Assertions:**

- **Page renders with DS header**: assert `ds-site-header` element present
- **Page renders with DS footer**: assert "Where the chain meets the model"
- **Compact hero renders**: assert tag name in h1 with `#` prefix, eyebrow contains "Tag"
- **Hero stats line renders**: assert "posts" text in stats line
- **Filter chips render**: assert "Latest", "Popular", "Most earned", "Long reads" chip text
- **Post grid renders**: assert post titles from seeded posts appear
- **Post cards show hub badge**: assert hub name appears in grid
- **Post cards show BUX reward**: assert BUX reward pill present
- **Related tags render**: assert "Related tags" eyebrow, "More like" title
- **Tag not found redirects**: assert redirect to "/" when slug doesn't match
- **Anonymous access works**: page renders without current_user
- **Logged-in access works**: page renders with current_user

### Manual checks (on `bin/dev`)

- Page renders at `/tag/[valid-slug]` logged in
- Page renders anonymous
- Compact hero shows `#tag_name` + stats line
- Filter chips render (inert)
- 3-col grid shows posts with hub badges + BUX pills
- Scroll down triggers infinite scroll (new posts load)
- Related tags cloud links to valid `/tag/:slug` routes
- No console errors
- `mix test` — zero new failures vs baseline

## Per-page commit message

`redesign(tag): tag browse refresh · compact hero + 3-col post grid + related tags chip cloud`

## Stubbed in v1

| Stub | What it shows now | What replaces it | Release |
|---|---|---|---|
| Filter chips | Render but click is no-op; "Latest" permanently active | `phx-click="set_filter"` handler with sort_mode changes | Follow-up commit |
| Tag description | Hidden — Tag schema has no `description` field | Add `description` to tags table, render in compact hero | Schema update release |
| Pagination label | Static "page 1 of N" label | Real page tracking or remove label | Follow-up commit |

## Open items

None. All mock elements either map to existing data or are documented stubs.
