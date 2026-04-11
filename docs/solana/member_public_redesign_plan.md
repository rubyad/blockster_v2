# Public Member Page · redesign plan

> Part of the existing-pages redesign release. See `redesign_release_plan.md`
> for context. Big-bang cutover, no per-page feature flag.

## What this replaces

| Field | Value |
|---|---|
| LiveView module | `lib/blockster_v2_web/live/member_live/show.ex` (same module, public branch) |
| Template | `lib/blockster_v2_web/live/member_live/show.html.heex` (conditional on `@is_own_profile`) |
| Route(s) | `/member/:slug` (already in `:redesign` live_session from profile redesign) |
| Mock file | `docs/solana/member_public_mock.html` |
| Bucket | **B** — visual refresh + schema additions (`users.bio`, `users.x_handle`) |
| Wave | 2 |

**Architecture decision**: The public member page shares the `/member/:slug` route with the owner profile (MemberLive.Show). Rather than creating a separate module, we modify MemberLive.Show to:
1. Remove the security redirect for non-owners
2. Set `@is_own_profile` assign (already computed)
3. Load public-specific data when `is_own_profile` is false
4. Render a completely different template branch based on `@is_own_profile`

This keeps all member-related code in one place and avoids route conflicts.

## Mock structure (top to bottom) — public view only

| # | Section | Description | Status |
|---|---|---|---|
| 1 | **Identity hero** | 12-col grid: left 8-col (96→112px avatar + "Author profile" eyebrow + "Verified writer" badge + 44-52px name + @slug + profile URL + member since + bio paragraph + social row with X handle link + website link), right 4-col (~~Follow~~ + Notify me + Share buttons) | REAL (except Follow removed per D17, Notify me is STUB) |
| 2 | **Stats row** | ~~4-col~~ 3-col grid: Posts published (count + since date), Total reads (count + all-time), BUX paid out (count + to readers). ~~Followers removed per D17~~ | REAL |
| 3 | **Sticky tab nav** | 4 tabs: Articles (count) / Videos (count) / Hubs (count) / About. Lime active underline. Frosted glass bg at top:84px | REAL |
| 4 | **Articles tab (default)** | 12-col grid: 8-col post list (horizontal post cards with hub dot + title + excerpt + meta), 4-col sidebar ("Published in" hub cards + "Recent activity" feed) | REAL |
| 5 | **Videos tab** | Same layout as Articles but filtered by `kind: :video` | REAL |
| 6 | **Hubs tab** | Grid of hub cards the user has published in | REAL |
| 7 | **About tab** | Full bio + social links + member details | REAL |

## Decisions applied from release plan

- **D17**: Followers REMOVED — no Follow button, no follower count stat card, no follower activity rows. The mock's 4th stat card ("Followers") is dropped, leaving a 3-col stats grid. The mock's "Follow" button is dropped. The mock's "+128 followers this week" activity row is dropped.
- **D18**: RSS REMOVED — no RSS link in social row. The mock shows 3 social links (X, website, RSS); we show 2 (X, website).
- **D19**: "Published in hubs" sidebar — LIVE. Uses existing `post.hub_id` relation in reverse (group user's posts by hub, list distinct hubs with post counts).

## Visual components consumed

- `<DesignSystem.header />` ✓ existing (Wave 0)
- `<DesignSystem.footer />` ✓ existing (Wave 0)
- `<DesignSystem.eyebrow />` ✓ existing (Wave 0)
- `<DesignSystem.profile_avatar />` ✓ existing (Wave 0)
- `<DesignSystem.post_card />` ✓ existing (Wave 0) — but NOT used; public member posts use a **horizontal card layout** (180px image left, content right) that differs from the standard post_card. This is page-specific markup in the template.
- No new design_system components needed — the horizontal post card, hub sidebar card, activity feed, and stats are all page-specific since they're only used on this page.

## Data dependencies

### ✓ Existing — already in production, no work needed

**User identity:**
- `@member` — `Accounts.get_user_by_slug_or_address(slug)` (name, slug, wallet_address, inserted_at, is_author, avatar_url)
- `@current_user` — from UserAuth on_mount
- `@is_own_profile` — `current_user && current_user.id == member.id`

**X connection (for social row):**
- `@x_connection` — `Social.get_x_connection_for_user(member.id)` — provides `x_username` for the X link

**Post-hub relation (for sidebar):**
- `post.hub` preloaded — provides `hub.name`, `hub.slug`, `hub.color_primary`, `hub.color_secondary`, `hub.token`, `hub.logo_url`

### ⚠ Stubbed in v1

- **"Notify me" button**: wired to `phx-click="notify_me"` — shows a flash `"We'll let you know when [name] publishes — subscriptions coming soon."` but does NOT persist any subscription. Becomes real when notification subscription system is built.
- **"Share" button**: wired to `phx-hook="CopyToClipboard"` with `data-copy-text` containing the full profile URL. Copies URL to clipboard and shows checkmark feedback. Fully functional.
- **Recent activity sidebar**: shows only published-post events (derived from `@posts` timestamps). The mock shows follower and milestone activities which require tracking systems that don't exist.
- **"BUX paid out" stat**: computed from `@posts` `bux_total` field. May undercount if rewards were distributed outside the post system.
- **About tab — website link**: requires `users.website_url` or similar field. For v1, hidden if no data exists.

### ✗ New — must be added for this page to ship

- **Schema migration**: `add_bio_and_x_handle_to_users` adds:
  - `bio :: text` (nullable) — drives the hero bio paragraph
  - `x_handle :: string` (nullable) — drives the X link in the social row (user-editable handle, separate from OAuth x_connections data)
- **Blog context function**: `list_published_posts_by_author(user_id, opts)` — fetches published posts by `author_id`, preloads `:hub`, supports `limit`, `offset`, `kind` filtering
- **Blog context function**: `count_published_posts_by_author(user_id)` — count of published posts
- **Blog context function**: `sum_views_by_author(user_id)` — sum of `view_count` across author's posts
- **Blog context function**: `sum_bux_by_author(user_id)` — sum of `bux_total` across author's posts
- **Blog context function**: `list_author_hubs(user_id)` — distinct hubs with post counts for the author
- **MemberLive.Show modification**: remove security redirect, add public data loading, add public tab handlers

## Handlers to preserve (owner profile — unchanged)

All existing handlers from the profile redesign remain exactly as documented in `profile_redesign_plan.md`. The public view adds NEW tab handlers that don't conflict:

**New public-only handlers:**
- `handle_event("switch_tab", %{"tab" => "articles"}, ...)` — already handled by existing `switch_tab` (just add to accepted values)
- `handle_event("switch_tab", %{"tab" => "videos"}, ...)` — same
- `handle_event("switch_tab", %{"tab" => "hubs"}, ...)` — same
- `handle_event("switch_tab", %{"tab" => "about"}, ...)` — same
- `handle_event("load_more_posts", ...)` — paginates posts (public view only)

**Existing handlers preserved:**
All handlers from profile_redesign_plan.md (switch_tab, unfollow_hub, edit_username, save_username, connect_telegram, verification modals, wallet connection, transfers, referrals, activity time period, claims, PubSub). These only fire on the owner view.

## Tests required

### Component tests

No new design_system components — no new component test files needed.

### LiveView tests

Extend `test/blockster_v2_web/live/member_live/show_test.exs`:

**Public view — anonymous user:**
- Anonymous user can view public member page (no redirect)
- Identity hero renders: name, slug, member since
- Stats row renders: posts published, total reads, BUX paid out
- Tab nav renders 4 tabs (Articles / Videos / Hubs / About)
- Articles tab renders post cards with hub dots
- Sidebar renders "Published in" hub cards
- No settings tab, no multiplier breakdown, no email banner

**Public view — logged-in non-owner:**
- Non-owner sees public view (no redirect)
- Identity hero renders correctly
- Owner-only elements are hidden (settings, multiplier, referral)

**Public view — owner still sees owner view:**
- Owner visiting own profile still sees the full owner template

**Tab switching (public):**
- Switching to "videos" tab works
- Switching to "hubs" tab works
- Switching to "about" tab works

**Bio and X handle:**
- Bio renders in hero when present
- Bio hidden when nil
- X handle link renders when present
- X handle hidden when nil

### Manual checks

- Page renders for anonymous visitor (no login required)
- Page renders for logged-in non-owner
- Owner still sees full owner profile
- Identity hero shows user's name, slug, bio
- Stats show real post count, view count, BUX paid
- Tab switching works (all 4 tabs)
- Articles tab shows posts with hub color dots
- Sidebar shows "Published in" hub cards
- "Notify me" button present but inert
- No follower count (D17)
- No RSS link (D18)
- `mix test` zero new failures vs baseline

## Per-page commit message

`redesign(member-public): public profile view + bio/x_handle fields + author stats + 4-tab nav`

## Stubbed in v1

| Stub | What it shows now | What replaces it | Resolved by release |
|---|---|---|---|
| "Notify me" button | Flash "We'll let you know when [name] publishes — subscriptions coming soon." (no persistence) | Real notification subscription with DB row | Notification subscription release |
| Recent activity sidebar | Published-post events only (from post timestamps) | Full activity feed (followers, milestones, etc.) | Activity tracking release |
| About tab — website link | Hidden (no field) | Real `users.website_url` field | Account management release |
| BUX paid out stat | Sum of `post.bux_total` | Accurate aggregation from all reward sources | Analytics release |

## Fixed in same session

- **"Share" button** — fully working via `CopyToClipboard` hook with `data-copy-text`, copies full profile URL to clipboard with checkmark feedback.

## Open items

None — all decisions resolved by D17, D18, D19 in the release plan.
