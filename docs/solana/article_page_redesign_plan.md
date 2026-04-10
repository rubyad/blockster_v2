# Article page · redesign plan

> Part of the existing-pages redesign release. See `redesign_release_plan.md`
> for context. Big-bang cutover, no per-page feature flag.

## What this replaces

| Field | Value |
|---|---|
| LiveView module | `lib/blockster_v2_web/live/post_live/show.ex` |
| Template | `lib/blockster_v2_web/live/post_live/show.html.heex` |
| Route(s) | `/:slug` (moved from `:default` to `:redesign_article` live_session) |
| Mock file | `docs/solana/article_page_mock.html` |
| Bucket | **B** — visual refresh + template-based ad system + sidebar placeholders |
| Wave | 1 |

## Mock structure (top to bottom)

The mock shows a 3-column layout:

| # | Section | Description | Status |
|---|---|---|---|
| 1 | **Left sidebar** (200px, sticky) | Stack of 3 discover cards: Event / Token Sale / Airdrop. Static placeholders for now — will be replaced by dynamic content system. | PLACEHOLDER |
| 2 | **Article card** (center, flex-1) | White rounded card containing article header, hero image, body with inline ads, author card, tags, suggested reading | REAL |
| 3 | **Right sidebar** (200px, sticky) | RogueTrader widget (static placeholder). Will be replaced by dynamic real-time widget. | PLACEHOLDER |

### Article card breakdown

| # | Sub-section | Data source | Status |
|---|---|---|---|
| 2a | Category pill (lime bg, uppercase) + read time + date | `@post.category.name`, word count / 200, date | REAL |
| 2b | BUX earned pill (clean white, always visible) | `@bux_earned` or `@current_bux` or `@anonymous_earned` | REAL |
| 2c | Title (article-title class, Inter 700) | `@post.title` | REAL |
| 2d | Subtitle / excerpt | `@post.excerpt` | REAL |
| 2e | Author row: avatar (40px dark gradient) + name + role | `@author_persona`, `@post.author_name` | REAL |
| 2f | Hub badge (40px, same size as author avatar, separated) | `@post.hub`, `@hub_logo` | REAL |
| 2g | Share to X button (black pill with lime BUX badge) | `@share_campaign`, `@x_share_reward` | REAL |
| 2h | Hero image (16:9, rounded) | `@post.featured_image` via ImageKit | REAL |
| 2i | Article body with inline ads at 1/3, 1/2, 2/3 marks | Content split via `TipTapRenderer.render_content_split/2` | REAL |
| 2j | Follow Hub bar (at 1/2 mark, only if post has hub) | `@post.hub` — rendered directly, not from ad system | REAL |
| 2k | About the author card | `@author_persona` | REAL |
| 2l | Tags | `@post.tags` | REAL |
| 2m | Admin actions (publish/unpublish/delete) | `@current_user.is_admin` | REAL |
| 2n | Engagement metrics | `@engagement` | REAL |
| 2o | Suggested reading (2x2 grid) | `@suggested_posts` via `SharedComponents.post_card` | REAL |

### Floating BUX panel (bottom-right, matches mock exactly)

| State | Design |
|---|---|
| **Earning Live** | White panel, green pulse dot, `+N BUX` 26px bold, engagement/base/multiplier breakdown |
| **Earned** | Same white panel, green checkmark, "Earned" label, "View tx" Solscan link |
| **Video earned** | Same white panel, purple play icon, video tx links |
| **Not eligible** | White panel, SOL logo, "Add SOL to Start" |
| **Pool empty** | White panel, muted BUX icon, "Pool Empty" |

## Ad banner system (template-based redesign)

The old image-upload ad system was replaced with a template-based system where admins choose a template, provide text/params, and the system generates styled HTML ads matching `article_page_mock.html`.

### Schema changes

Migration `20260410181441_add_template_to_ad_banners`:
- Added `template` (string, default "image") — one of: `follow_bar`, `dark_gradient`, `portrait`, `split_card`, `image`
- Added `params` (map/jsonb, default %{}) — template-specific fields (heading, description, brand_color, cta_text, image_url, etc.)

### Ad templates (4 types, matching mock exactly)

| Template | Visual | Params |
|---|---|---|
| `follow_bar` | Dark Forbes-style "Follow X in Hubs" horizontal bar | `heading`, `brand_color`, `brand_name` |
| `dark_gradient` | Dark bg with gradient blobs, heading, description, lime CTA | `brand_name`, `brand_color`, `heading`, `description`, `cta_text` |
| `portrait` | Photo top + color block bottom (Stonepeak style) | `image_url`, `heading`, `subtitle`, `cta_text`, `brand_name`, `bg_color`, `accent_color` |
| `split_card` | Text left + colored stat panel right | `brand_name`, `brand_color`, `heading`, `description`, `cta_text`, `panel_color`, `stat_value`, `stat_label_top/bottom` |

### Inline ad placements

| Placement | Position | Current content |
|---|---|---|
| `article_inline_1` | 1/3 mark of article body | `dark_gradient` — Moonpay SOL On-Ramp |
| `article_inline_2` | 2/3 mark of article body | `portrait` — Heliosphere Capital |
| `article_inline_3` | End of article body (3/3 mark) | `split_card` — Moonpay Bottom CTA |

### Content splitting

`TipTapRenderer.render_content_split/2` splits the article's top-level TipTap nodes at fractional positions:
- **With hub**: splits at `[0.33, 0.5, 0.66]` → 4 chunks. Ad at 1/3, Follow Hub bar at 1/2, ad at 2/3, ad at end.
- **Without hub**: splits at `[0.33, 0.66]` → 3 chunks. Ad at 1/3, ad at 2/3, ad at end.

### Follow Hub bar

Rendered directly from `@post.hub` data (NOT from the ad banner system). Only appears on articles belonging to a hub. Links to `/hub/:slug`. Uses the hub's brand color and logo.

## Article body CSS

Added to `assets/css/app.css` — matches `article_page_mock.html` exactly:
- **Drop cap**: `#post-content-1 > p:first-child::first-letter` — Inter 700, 58px, only on first paragraph of first chunk
- **Blockquote**: lime `#CAFC00` 3px border-left, italic 22px Inter 500, attribution styled as small-caps (11px, uppercase, 0.14em tracking, gray)
- **Bullet lists**: left 2px gray border, 5px black dot bullets via `::before`, bold labels
- **Headings**: Inter 700, 28px, -0.015em tracking
- **Links**: blue-500, underline on hover

## Sidebar placeholders

Both sidebars contain static placeholder content that will be replaced by dynamic content systems in a future release:

### Left sidebar — Discover cards (placeholder)
Three static cards copied from `article_page_mock.html`:
- **Event card** — Moonpay × Solana NYC happy hour, date tile, event image, RSVP button
- **Token Sale card** — Phoenix Protocol $PHX, progress bar, raise stats, Register button
- **Airdrop card** — $2,000 prize pool, 33 winners, drawing countdown, links to `/airdrop`

Will be replaced by a dynamic sidebar content system that renders real events, sales, and airdrop data.

### Right sidebar — RogueTrader widget (placeholder)
Static dark trading terminal card with 6 bot entries (HERMES, AURUM, STERLING, WOLF, MACRO, ZEUS) matching the mock exactly. Includes header with LIVE pulse, bid/ask/AUM grids, P&L percentages, risk tags, footer with "Open RogueTrader" link.

Will be replaced by a real-time updating widget fed by the RogueTrader API.

## Visual components consumed

- `<DesignSystem.header />` ✓ existing (Wave 0)
- `<DesignSystem.footer />` ✓ existing (Wave 0)
- `<DesignSystem.ad_banner banner={banner} />` **NEW** — template-based ad rendering (4 templates)
- `<SharedComponents.post_card />` ✓ existing — used for suggested reading (2x2 grid, original card design)
- `<SharedComponents.token_badge />` ✓ existing — BUX balance on suggested cards

## Data dependencies

### New assigns added

- `@airdrop_round` — `Airdrop.get_current_round()` (for discover sidebar airdrop card)
- `@content_chunks` — `TipTapRenderer.render_content_split(post.content, positions)` (split article body)
- `@has_hub` — boolean, whether post has a loaded hub association
- `@article_inline_1`, `@article_inline_2`, `@article_inline_3` — template-based inline ad banners

### Backend changes

- `Blog.get_suggested_posts/3` — added `:hub` to preload (was only `:category`)
- `TipTapRenderer.render_content_split/2` — new function, splits content nodes at fractional positions
- `Banner` schema — added `template` and `params` fields
- `Banner` valid placements — added `article_inline_1`, `article_inline_2`, `article_inline_3`

## Handlers preserved (all 25 + 4 + 6)

All existing handlers preserved identically — see handlers list in previous version of this doc.

## Router change

Moved `/:slug` from `:default` to new `:redesign_article` live_session at the END of the scope (must stay last — catch-all). Uses `{BlocksterV2Web.Layouts, :redesign}` layout.

## Tests

- `test/blockster_v2_web/components/design_system/discover_card_test.exs` — 7 tests
- `test/blockster_v2_web/components/design_system/suggest_card_test.exs` — 6 tests
- `test/blockster_v2_web/live/post_live/show_test.exs` — 13 tests
- All 88+ redesign tests passing, 0 new failures vs baseline

## Test article

Seeded at `/the-quiet-revolution-of-onchain-liquidity-pools` with rich content covering all typography elements: drop caps, h2 headings, blockquote with attribution, bullet list with bold labels, inline links. Run `mix run priv/repo/seeds_test_article.exs` to create.

## Per-page commit message

`redesign(article): white card + template ads + sidebar placeholders + floating BUX panel`

## Stubbed in v1

| Stub | What it shows now | What replaces it | Resolved by release |
|---|---|---|---|
| Left sidebar discover cards | Static mock content (event/sale/airdrop) | Dynamic content system with real data | Sidebar content system release |
| Right sidebar RogueTrader | Static widget placeholder | Real-time RogueTrader API widget | RogueTrader integration release |
| Event discover card content | Moonpay × Solana NYC (static) | Real event data from Events context | Events release |
| Token Sale discover card content | Phoenix Protocol (static) | Real sale data from TokenSales context | Events/sales release |
