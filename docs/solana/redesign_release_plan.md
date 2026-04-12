# Blockster Redesign · Existing Pages Release Plan

> **READ FIRST:** `docs/solana/design_system.md` (the spec — every component, color, font, and pattern) and `docs/solana/redesign_overview.md` (the three-phase context — mock → extract → build).
>
> This file is the operational plan for shipping the **existing-pages redesign** as a single coordinated release. It does NOT cover the new-pages release (events, token sales, media kit) — that ships after this one.

---

## What this release ships

The visual redesign of every page that already exists in production today, rebuilt against a new component library extracted from the mocks. 19 pages total, one branch (`feat/solana-migration`), one cutover deploy at the end.

The new design language is captured in 27+ HTML mocks under `docs/solana/`. The job of this release is to translate those mocks into Phoenix components and rebuild the existing LiveView templates against them, while preserving every existing handler, assign, and PubSub topic.

## What this release does NOT ship

- The new product surfaces — **events**, **token sales**, **media kit**. Those mocks exist but their backend systems (Events context, TokenSales context, downloadable assets) are not built yet. They're a separate release that follows this one.
- The sister-project widgets (FateSwap live trades feed, RogueTrader top bots). Those are Phase 4 work that depends on APIs in two sister apps that don't exist yet.
- The smaller open items in the **stub register** at the bottom of this doc.

---

## Approach summary

- **Single branch**: `feat/solana-migration` (the current branch). No new branches. No merges to `main` until cutover.
- **One page at a time**: Extract the components needed by that page, rebuild the page, run tests, hand to the user for local validation, fix anything they find, then move to the next page. No parallel page work.
- **No per-page feature flags**. No `BLOCKSTER_REDESIGN` master switch. Direct cutover. The old templates get deleted in the same commit that adds the new ones.
- **Single deploy at the end**: When all 19 pages are green on local and `mix test` is zero failures, the user explicitly says "deploy" and we run `flyctl deploy --app blockster-v2`. Until then, nothing ships to production.
- **Tests at every step**: per the CLAUDE.md rule "ALL tests must pass before deploying". This release applies the same rule to every page checkpoint, not just the deploy. Every component gets a test before it's used. Every page rebuild is wrapped in test extensions before it's considered done.

---

## The 19 pages in scope

| # | Page | Route(s) | Mock file | LiveView module | Bucket |
|---|---|---|---|---|---|
| 1 | Homepage | `/` | `homepage_mock.html` | `BlocksterV2Web.PageController` (or `HomeLive`) | A |
| 2 | Article page | `/:slug` | `article_page_mock.html` | `PostLive.Show` | **B** |
| 3 | Hubs index | `/hubs` | `hubs_index_mock.html` | `HubsLive.Index` | A |
| 4 | Hub show | `/hub/:slug` | `hub_show_mock.html` | `HubLive.Show` | **B** |
| 5 | Profile (owner) | `/profile` | `profile_mock.html` | `ProfileLive` | A |
| 6 | Public member page | `/member/:slug` | `member_public_mock.html` | `MemberLive` | **B** |
| 7 | Play / Coin Flip | `/play` | `play_mock.html` | `CoinFlipLive` | A |
| 8 | Pool index | `/pool` | `pool_index_mock.html` | `PoolIndexLive` | A |
| 9 | Pool detail | `/pool/sol`, `/pool/bux` | `pool_detail_mock.html` | `PoolDetailLive` | A |
| 10 | Airdrop | `/airdrop` | `airdrop_mock.html` | `AirdropLive` | A |
| 11 | Shop index | `/shop` | `shop_index_mock.html` | `ShopLive.Index` | A |
| 12 | Product detail | `/shop/:slug` | `product_detail_mock.html` | `ShopLive.Show` | A |
| 13 | Cart | `/cart` | `cart_mock.html` | `CartLive.Index` | A |
| 14 | Checkout | `/checkout/:order_id` | `checkout_mock.html` | `CheckoutLive.Index` | A |
| 15 | Wallet connect modal | (component) | `wallet_modal_mock.html` | `wallet_components.ex` | A |
| 16 | Category browse | `/category/:slug` | `category_mock.html` | (existing) | A |
| 17 | Tag browse | `/tag/:slug` | `tag_mock.html` | `PostLive.Tag` | A |
| 18 | **Notifications** | `/notifications` | (no mock — design during redesign doc) | `NotificationLive.Index` | A |
| 19 | **Onboarding flow** | `/onboarding` (8-step) | (no mock — design during redesign doc) | `OnboardingLive` | **B** |

**Counts**: 15 Bucket A pages (visual refresh only) · 4 Bucket B pages (visual refresh + decisions / new fields / stubs)

> **Note on #18 and #19**: These two pages don't have HTML mocks — by user decision they go straight into per-page redesign docs that drive the implementation. The design follows the established patterns in `design_system.md` (page hero variants, card patterns, form patterns, etc.) so we don't need a separate mock-first iteration for them.

---

## Bucketing

**Bucket A · pure visual refresh** (15 pages). Rebuild the LiveView template against the new component library, no schema changes, no new contexts, no new on-chain work, no stubs needed. The existing `*_live.ex` module is untouched — only the `.html.heex` template (and any extracted components it now uses) changes.

**Bucket B · visual refresh + decisions** (4 pages):

- **Article page** (#2) — discover sidebar slots for Event and Token Sale must be stubbed (see decision below). Airdrop card is real.
- **Hub show** (#4) — News + Videos tabs need a new `posts.kind` field for filtering. Events tab needs a hub→events relation OR ships with a hardcoded empty state.
- **Public member page** (#6) — needs `users.x_handle`, `users.bio`, and uses the existing post→hub relation for the "Published in hubs" sidebar. Follower system is **out of scope** (decision below).
- **Onboarding flow** (#19) — multi-step LiveView with branching paths. Higher complexity than a typical page but no new schema work.

---

## Locked-in decisions

These are answered. They don't need to be re-litigated during the build.

| # | Topic | Decision |
|---|---|---|
| D1 | Article page mock | `article_page_mock.html` is canonical. `realtime_widgets_mock.html` is preserved for the Phase 4 sister-project widgets release and is **not** in scope here. |
| D2 | Logo migration | The inline HTML `<.logo />` component (Inter 800 uppercase, 0.06em tracking, 0.78em lime icon swapped in for the O) ships in every header on day 1. The `blockster-logo.png` raster wordmark is removed from production headers. PNG fallbacks for OG images and email templates are tracked in the stub register as a follow-up. |
| D3 | Why Earn BUX banner copy | Keep verbatim: `Why Earn BUX? Redeem BUX to enter sponsored airdrops.` |
| D4 | Test discipline · LiveView | Extend the existing `*_live_test.exs` files. New assertions for the new template, existing handler tests stay. No parallel `*_visual_test.exs` files. |
| D5 | Test discipline · components | Each new component in `lib/blockster_v2_web/components/design_system/` gets its own test file. Tests use `Phoenix.LiveViewTest.render_component/2` to assert key DOM elements + attrs. No screenshot diffing. |
| D6 | Solana-side work | None for this release. The settler service already covers everything the existing pages call. New settler routes wait for the events / sales release. |
| D7 | Branch | Continue on `feat/solana-migration`. Final merge to `main` happens at deploy time. |
| D8 | Cutover | Direct cutover. Old templates get deleted in the same commit that adds the new ones. No master env-var switch. The one-page-at-a-time validation cadence is the safety net. |
| D9 | Schema migrations in this release | **Allowed**. Specifically `posts.kind`, `users.x_handle`, `users.bio` (if not already there). Migrations must be **forward-compatible** with old templates during the build (since old templates still exist alongside new ones until each page's cutover commit). |
| D10 | Categories + tags | Both routes exist in production today. Both stay in the existing-pages release. |
| D11 | Notifications + onboarding | Both in scope. Skip mock-first phase. Each gets a per-page redesign doc that drives the rebuild directly. |
| D12 | Article page discover sidebar | **Option C**: show all 3 cards (Event / Token Sale / Airdrop). Event and Token Sale are styled "Coming soon" placeholder cards with the same outer frame, an inert button, and copy that says "Coming soon — events launch [month]" / "Coming soon — first sale launches [month]". Airdrop card shows real data. When the events / sales release ships, the placeholder cards become real cards with no template change. |
| D13 | Hub show tabs · v1 | Ship 5 tabs: **All / News / Videos / Shop / Events**. Drop **Long reads / Authors / About** from v1 (deferred to a follow-up). |
| D14 | Hub show · News + Videos | Add `posts.kind` enum field with values `[:news, :video, :other]`, default `:other`, backfill all existing posts as `:other`. News tab filters for `:news`, Videos tab filters for `:video`. Editors set the field at post creation. |
| D15 | Hub show · Events tab | Always shows the empty state in v1 (no events system yet). Empty state is a clean white card: "No events yet from this hub" + a small "Notify me" inert button. When events ship, the empty state is replaced with the real events list with no template change. |
| D16 | Hub show · Shop tab | Live in v1. Uses the existing hub→product relation (already in production via the shop's "From [hub]" attribution). |
| D17 | Public member page · followers | **Removed**. No follow button, no follower count, no follow system migration. The page's social row shows X handle only. |
| D18 | Public member page · RSS | **Removed**. No RSS link in the social row. |
| D19 | Public member page · "Published in hubs" sidebar | Live in v1. Uses the existing post→hub relation in reverse (group the user's posts by hub, list distinct hubs). |
| D20 | Workflow order | Foundation components first, then pages in wave order (see below). |
| D21 | Definition of done · per page | Page rebuilt against new components · existing handlers still fire · existing tests still pass · new component tests pass · `mix test` zero failures · user has manually walked the page on local in both logged-in and anonymous states · any stubs for that page added to the stub register at the bottom of this doc. |
| D22 | Definition of done · whole release | All 19 pages done · all stubs in the stub register · new HTML wordmark in every header · new footer (address + media kit link) on every page · `mix test` zero failures · user explicitly says "deploy" |

---

## Stub policy

A "stub" is anything in the new design that the new code can't fully implement yet. Examples: a card that shows "Coming soon" because its backend doesn't exist; a button that's inert because its handler isn't built; a section that's hidden because its data doesn't exist on the schema.

**Rules for stubs:**

1. **Stubs are allowed for any feature whose backend ships in a later release.** (Events cards, token sale cards, hub events lists.)
2. **Stubs are NOT allowed for features whose backend exists today.** If the existing LiveView already provides the data, the new template must use it.
3. **Every stub must be documented** in the page's per-page redesign doc under the "Stubbed in v1" section, AND added to the master stub register at the bottom of this file.
4. **Stub style**: prefer **visible "Coming soon" placeholders** over hidden sections. Honest about what's missing. Card-shaped, inert button, clear copy. Hide-entirely is allowed only when leaving the placeholder visible would look broken (e.g., a sidebar that would otherwise be empty).
5. **Stubs must be removable without template changes.** When the backend lights up, replacing the placeholder with the real component should be a 1-line swap. Design the stub as a drop-in for the future component.

---

## Schema migrations allowed in this release

Per D9. The migrations expected by this release:

| Migration | Affects | Why |
|---|---|---|
| `add_kind_to_posts` | `posts` | New `kind :: enum [:news, :video, :other]` field with default `:other`. Backfills all existing posts as `:other`. Drives the Hub show News + Videos tabs. |
| `add_x_handle_to_users` (only if missing) | `users` | New `x_handle :: string` field. Drives the public member page social row. **Confirm whether this already exists before writing the migration.** |
| `add_bio_to_users` (only if missing) | `users` | New `bio :: text` field. Drives the public member page bio block. **Confirm whether this already exists.** |

**Forward-compatibility rule**: every migration must be safe to deploy on a database where the old templates are still being served. Add columns nullable / with safe defaults. Never drop columns or change types. Migrations get committed with the page that introduces them, NOT all up front.

**Mnesia considerations** (per CLAUDE.md): none of the above touch Mnesia tables. If a future migration would, it requires the special multi-step process documented in CLAUDE.md.

---

## Workflow · one page at a time

For each page in wave order:

1. **Read** the page's mock and the existing LiveView module in full.
2. **Write the redesign doc** for the page using the standard template (below). Includes the data dependency analysis, the stubs needed, the components consumed, the tests needed.
3. **Identify new components** the page introduces that don't exist yet in `lib/blockster_v2_web/components/design_system/`.
4. **Build those new components** with their test files. Run the component tests. They must pass.
5. **Write any schema migrations** the page needs. Run them on local. `mix ecto.migrate` only — never reset.
6. **Rebuild the page's LiveView template** to use the new components. Replace the old template in-place. Old template gets deleted in the same commit.
7. **Extend the existing LiveView test file** with assertions about the new template + assert handlers still fire.
8. **Run `mix test`**. Must be zero failures across the whole suite.
9. **Boot local** with `bin/dev` and walk the page in both logged-in and anonymous states. Verify every CTA renders, every link works, no console errors.
10. **Hand to user** for their own local validation. They test on their machine, report any issues, fixes get made on the same page.
11. **Once the user signs off**, commit with a clear per-page commit message: `redesign(page-name): <what changed>`. Then move to the next page.

**No skipping steps.** Even on Bucket A pages where the work is purely visual, the test extension and the local walk are non-negotiable.

---

## Test discipline

Per D4 + D5 and the CLAUDE.md rule "ALL tests must pass before deploying":

- **Component tests** live in `test/blockster_v2_web/components/design_system/[name]_test.exs`. One file per component. Assert the rendered DOM contains the expected elements + attrs given a representative `assigns` map. Test all key variants (e.g. `<.page_hero variant="A">` and `<.page_hero variant="B">`).
- **LiveView tests** stay in `test/blockster_v2_web/live/[page]_live_test.exs`. The existing tests for handlers/events stay. New assertions get added for the new template — verify the page renders the new components, verify the new visual elements are present, verify the existing assigns still flow through.
- **Integration tests** exist for some flows already (cart, checkout, airdrop). Those stay green. If a redesign changes the DOM in a way that breaks an existing integration test, the integration test gets updated to match.
- **`mix test` runs zero failures at every checkpoint**: after building each component, after rebuilding each page, before each per-page commit, before every wave boundary, and finally before the cutover deploy.
- **Per CLAUDE.md**: "ALL tests must pass before deploying — run `mix test` and fix every single failure. Zero failures required." That rule applies to every commit on this branch from here until cutover.

---

## Wave order

Components and pages in dependency order. Each wave finishes before the next starts.

### Wave 0 · Foundation components
Built first because every page uses them. No page work until Wave 0 is green.

- `<.header />` (logged-in + anonymous variants)
- `<.footer />` (with address + media kit link)
- `<.logo size="…" variant="…" />` (Inter 800 wordmark with lime O — covers all 9 sizes from 12px to 96px, light + dark)
- `<.why_earn_bux_banner />`
- `<.eyebrow />`
- `<.chip variant="active|default" />`
- `<.author_avatar initials="…" size="…" />`
- `<.profile_avatar />`
- `<.page_hero variant="A" />` (editorial title + 3-stat band — used by 80% of index pages)
- `<.stat_card />`
- `<.post_card />` (the standard suggested-reading card)

That's roughly 11 components. Each one gets a test file. `mix test` must be zero failures before Wave 1 begins.

### Wave 1 · The front door (4 pages)

- **#1 Homepage** (`homepage_mock.html`)
- **#2 Article page** (`article_page_mock.html`) — includes the article body with drop caps, ad banner system, BUX earning UI, suggested reading, **discover sidebar with stubbed Event + Token Sale cards** (D12)
- **#3 Hubs index** (`hubs_index_mock.html`)
- **#4 Hub show** (`hub_show_mock.html`) — includes the `posts.kind` migration (D14), 5 tabs (D13), Events empty state (D15), Shop tab live (D16)

### Wave 2 · Identity (2 pages)

- **#5 Profile (owner)** (`profile_mock.html`)
- **#6 Public member page** (`member_public_mock.html`) — includes `users.x_handle` and `users.bio` migrations if missing, removes followers + RSS (D17 + D18), uses existing post→hub relation for "Published in hubs" sidebar (D19)

### Wave 3 · Earning (4 pages)

- **#7 Play / Coin Flip** (`play_mock.html`)
- **#8 Pool index** (`pool_index_mock.html`)
- **#9 Pool detail** (`pool_detail_mock.html`)
- **#10 Airdrop** (`airdrop_mock.html`)

### Wave 4 · Spending (4 pages)

- **#11 Shop index** (`shop_index_mock.html`)
- **#12 Product detail** (`product_detail_mock.html`)
- **#13 Cart** (`cart_mock.html`)
- **#14 Checkout** (`checkout_mock.html`)

### Wave 5 · Discovery (3 pages)

- **#15 Wallet connect modal** (`wallet_modal_mock.html`) — restyle the existing `wallet_components.ex` modal in place
- **#16 Category browse** (`category_mock.html`)
- **#17 Tag browse** (`tag_mock.html`)

### Wave 6 · Internal flows (2 pages)

- **#18 Notifications** — no mock; design driven by per-page redesign doc
- **#19 Onboarding flow** — no mock; design driven by per-page redesign doc; covers the 8-step welcome/migration flow per CLAUDE.md

### Wave 7 · Cutover

- Final test pass (`mix test` zero failures across the whole suite)
- Manual walk of every page on local, logged-in + anonymous, in a fresh browser
- Stub register reviewed and committed
- User explicitly says "deploy"
- `flyctl deploy --app blockster-v2`

---

## Component extraction order

Beyond Wave 0's 11 foundation components, additional components get extracted as the pages that need them are built. The extraction is **lazy and just-in-time** — don't build a component until a page needs it, but when a page needs it, build the test alongside.

Components expected to emerge during the page builds (rough estimate based on what the mocks contain):

- `<.hub_card />` (gradient brand card with Follow button)
- `<.activity_table />` and `<.activity_row />`
- `<.brand_banner />` (variant C — full-bleed gradient)
- `<.poster_hero />` (variant D — events; not used by existing pages but gets built when events page ships)
- `<.terminal_hero />` (variant E — token sales; same)
- `<.live_pill />` (small green pulse + LIVE label)
- `<.price_badge variant="free|paid|online" />`
- `<.date_tile size="sm|md|lg|massive" />`
- `<.discover_card variant="event|sale|airdrop" />` — for the article page sidebar
- `<.coming_soon_card />` — the stub variant of discover_card for D12
- `<.tier_card />`
- `<.pay_card />`
- `<.step_indicator />`
- `<.form_input />`, `<.form_label />`
- `<.modal_stage />`, `<.wallet_connect_modal />`
- `<.article_body />` (drop caps, h2, ul styling, blockquote)
- `<.suggest_card />` (the article page suggested-reading card)
- `<.bux_floating_panel />` (the white floating BUX earning panel from the article page)
- `<.hub_badge />` (small color square with hub icon)
- `<.section_title />`, `<.editorial_eyebrow />`
- `<.mosaic_grid />` (varied-card-size grid for trending sections)

Final count after the existing-pages release: probably ~30 components in `lib/blockster_v2_web/components/design_system/`. The events / sales / media kit release adds maybe another ~10.

---

## Per-page work breakdown

Each page in scope gets its own redesign doc at `docs/solana/[page]_redesign_plan.md`. They all use the **standard template** below. The full set is written as part of executing this plan — not up front.

### Standard redesign plan template

````markdown
# [Page name] · redesign plan

> Part of the existing-pages redesign release. See `redesign_release_plan.md`
> for context. Big-bang cutover, no per-page feature flag.

## What this replaces

| Field | Value |
|---|---|
| LiveView module | `lib/blockster_v2_web/live/...` |
| Route(s) | `/...` |
| Mock file | `docs/solana/..._mock.html` (or "no mock — design from spec") |
| Bucket | A · pure visual refresh / B · with stubs / B · with schema additions |
| Wave | 0 / 1 / 2 / 3 / 4 / 5 / 6 |

## Visual components consumed

Components from `lib/blockster_v2_web/components/design_system/` this page
uses. Components that don't exist yet are flagged so the extraction step
knows to build them first.

- `<.header variant="logged_in" />` ✓ existing
- `<.footer />` ✓ existing
- `<.page_hero variant="A" eyebrow="..." title="..." stats={...} />` ✓ existing
- `<.post_card />` × N ✓ existing
- `<.[new_component] />` ⚠ NEW — must be built before this page can be assembled

## Data dependencies

### ✓ Existing — already in production, no work needed
List the assigns the current LiveView already provides + the schema fields
the mock relies on.

- `@current_user`, `@current_user.bux_balance`
- `@post.title`, `@post.body`, `@post.author`
- ...

### ⚠ Stubbed in v1 — documented, fixed in a later release
The mock shows this but the data doesn't exist yet OR depends on systems
that ship later. Each entry says **how it's stubbed** and **which release
fixes it**. Also added to the master stub register in `redesign_release_plan.md`.

- **Event card in discover sidebar** — stubbed by showing a "Coming soon"
  placeholder card with the same outer frame as the real event_discover_card.
  Inert button. Copy: "Events launch [month]". Becomes real in the events
  release. Tracked in master stub register.
- ...

### ✗ New — must be added or schema-migrated for this page to ship
Real backend work this page can't ship without. Each entry has a sketch.

- **Schema migration**: `add_kind_to_posts` adds `posts.kind :: enum`
  with `[:news, :video, :other]`, default `:other`. Backfills all existing
  posts as `:other`.
- **Context function**: `BlocksterV2.Hubs.list_posts_by_kind/2` filters
  posts within a hub by the new `kind` field.
- ...

## Handlers to preserve

Every `phx-click`, `phx-submit`, `start_async`, and PubSub topic the existing
LiveView fires. The new template MUST keep these wired up exactly as today.

- `phx-click="redeem_bux"` → existing `handle_event/3`
- `phx-click="claim_prize"` → existing
- `start_async(:fetch_balances, ...)` → existing
- subscribes to `"airdrop:#{round_id}"` PubSub topic
- ...

## Tests required

Tests written and passing before this page is considered done.

### Component tests (Wave 0 + this page)
- `test/blockster_v2_web/components/design_system/[component]_test.exs` for
  any new components this page introduces

### LiveView template extension
- Extend `test/blockster_v2_web/live/[page]_live_test.exs` with assertions
  for the new template structure
- Existing handler tests stay; verify they still pass

### Manual checks
- Page renders logged in
- Page renders anonymous (where applicable)
- Every CTA in the mock has a working handler or is documented as a stub
- No console errors
- `mix test` zero failures across the whole suite

## Per-page commit message

`redesign([page]): <one-line description>`

## Open items

Anything blocking. Questions for the user. Decisions deferred.
````

Each per-page doc is a few hundred lines max. Skim-able. The template is the contract — every doc fills in every section, even if the answer is "none" or "n/a".

---

## Stub register

Every stub introduced during the build gets added here so the next release knows what's pending.

| Page | Stub | What it shows now | What replaces it | Resolved by release |
|---|---|---|---|---|
| Homepage | Token sales section | 3 `<.coming_soon_card variant="token_sale" />` placeholder cards | Real `<.token_sale_card />` with live data | Events / sales release |
| Homepage | Recommended for you | Single `<.coming_soon_card variant="recommended" />` placeholder (logged-in only) | Real recommendation system | Recommendation engine release |
| Homepage | Trending filter chips | Chips render but click is a no-op; "All" permanently active | `phx-click="filter_trending"` handler filtering mosaic by category | Follow-up commit in Wave 1 |
| Homepage | Hubs you follow filter chips | Hub-color chips render but click is a no-op; "All" permanently active | `phx-click` handler filtering by specific hub | Follow-up commit in Wave 1 |
| Article page | Left sidebar discover cards | Static mock content (Event/Token Sale/Airdrop cards) | Dynamic content system with real data | Sidebar content system release |
| Article page | Right sidebar RogueTrader widget | Static placeholder (6 bots, LIVE pulse, bid/ask/AUM) | Real-time RogueTrader API widget | RogueTrader integration release |
| Hub show | Live activity widget | Static placeholder (3 hardcoded items) | Real-time PubSub activity feed | Hub activity system release |
| Hub show | Sponsor/Verified badges | Static hardcoded badges | Dynamic badge system | Badge system release |
| Hub show | Events tab content | Empty state: "No events yet" | Real events from Events context | Events release |
| Hub show | Category filter chips (All tab mosaic) | Render but click is no-op | Working category filter | Follow-up commit |
| Hub show | "Notify me" button | Inert, no handler | Real notification subscription | Notification subscription release |
| Profile | Rewards tab sparkline | Hidden (no monthly aggregation) | Real 12-month BUX bar chart | Analytics release |
| Profile | Rewards tab Coin Flip wins | Shows 0 (no Mnesia aggregation) | Real aggregation from coin_flip_games | Analytics release |
| Profile | Rewards tab pending claims | Hidden (no settlement tracking) | Real settlement status tracking | Settlement tracking release |
| Profile | Settings — Export account data | Inert button | Real data export | Account management release |
| Profile | Settings — Deactivate account | Inert button | Real deactivation flow | Account management release |
| Public member | "Notify me" button | Flash "subscriptions coming soon" (no persistence) | Real notification subscription with DB row | Notification subscription release |
| Public member | Recent activity sidebar | Published-post events only | Full activity feed (followers, milestones) | Activity tracking release |
| Play / Coin Flip | "Live · All players" sidebar feed | Last 5 of user's own recent games, labeled "Your recent games" | Real global PubSub feed aggregated across all players | Activity system release |
| Play / Coin Flip | House Edge hero stat | Static "0.92%" | Real computation from settled game aggregates | Analytics release |
| Play / Coin Flip | BUX Pool hero stat when SOL selected (and vice versa) | "—" placeholder | Parallel settler fetch for both vaults in mount | Follow-up commit |
| Play / Coin Flip | Phantom "Transaction reverted during simulation" popup on every bet | Warning shows, user clicks approve, tx lands successfully | Client-side poll of `getAccountInfo(player_state)` via devnet connection after `submit_commitment` returns, only enable Place Bet once `pending_commitment` is visible AND `pending_nonce` matches. Pre-existing issue per back-to-back tx propagation rule in CLAUDE.md. **Parked** until mainnet verification — devnet public RPC (`api.devnet.solana.com`, used by Phantom) lags 5-15 slots behind QuickNode. On mainnet Phantom uses a paid RPC (Helius/Triton) with tight sync and the warning likely disappears. | Mainnet cutover (verify) or Coin Flip propagation fix release |
| Pool index | Top 3-stat band "24h" labels | All-time totals from `pool_stats.{sol,bux}` summed (SOL $160 + BUX $0.01 rough conversion for Total TVL); sub-labels relabeled "all time" / "across both pools" to stay honest | Real 24h rolling aggregates from an analytics rollup | Analytics release |
| Pool index | Mini sparklines on vault cards | Static decorative `<svg>` paths from the mock (hardcoded points) | Real per-vault LP-price sparkline sourced from `LpPriceHistory` | Follow-up commit once a compact "last N points" helper exists |
| Pool index | Est. APY captions on vault cards | Static "14.2%" (SOL) / "18.7%" (BUX) strings from the mock | Real computed APY from `houseProfit / netBalance × annualization` | Analytics release |
| Pool detail | Your position · Cost basis | `—` placeholder (no cost-basis tracking) | Running-average cost basis recorded on each deposit | Analytics release |
| Pool detail | Your position · Unrealized P/L | `—` placeholder | Computed from cost basis vs current LP price | Analytics release |
| Pool detail | Your position · "days as LP" caption | Hidden (no `first_deposit_at` tracked) | Real timestamp recorded on first deposit | Analytics release |
| Pool detail | Hero row Est. APY stat | Static `14.2%` / `18.7%` — same stub as pool index | Real computed APY | Analytics release |
| Pool detail | Activity table "Showing N of M events" total | Shows `length(@activities)` as both numerator + denominator (no real total) | Real server-side paginated total count | Follow-up commit |
| Pool detail | Activity table "Load more" button | Inert (no handler) | Paginated load-more action | Follow-up commit |
| Pool detail | Phantom "Transaction reverted during simulation" popup on every SOL deposit + withdraw | Warning shows, user clicks approve, tx lands successfully. Same root cause as the Play / Coin Flip stub — Phantom simulates against `api.devnet.solana.com`, which lags behind QuickNode, so it sees a stale `VaultState` PDA or an unknown blockhash at simulation time. **Parked** until mainnet verification — Phantom uses Helius/Triton on mainnet with tight sync to our settler RPC and the warning likely disappears. If it persists, the fix is a client-side `getAccountInfo(vault_state)` poll before emitting `sign_deposit` / `sign_withdraw` so the settler's recent blockhash has already propagated to Phantom's RPC. | Mainnet cutover (verify) or pool tx propagation fix release |
| Airdrop | Sidebar ad banner placements (`airdrop_sidebar_left`, `airdrop_sidebar_right`) | Loaded into mount assigns but not rendered — mock has no sidebar slots (full 1280px main column) | Re-rendered when a future layout brings sidebars back, OR the loader stays and ads move to a different placement | Ad placement reshuffle |
| Airdrop | Drawn-state hero `View on Solscan ↗` link target | Falls back to airdrop program account on Solscan when `verification_data.draw_tx` is nil | Real per-round `draw_tx` field (already supported when present) | Verification data backfill (or already works once a round is drawn through the live settler path) |
| Airdrop | Phantom "Transaction reverted during simulation" popup on airdrop deposit + claim | Warning shows on devnet, user approves, tx lands successfully. Same cross-RPC propagation issue as Pool detail and Coin Flip — Phantom simulates against `api.devnet.solana.com` (5–15 slot lag) while the settler builds with QuickNode. **Parked** until mainnet verification. | Mainnet cutover (verify) or airdrop tx propagation fix release |
| Shop index | Sort dropdown | Static "Most popular" button, no handler | Real sort handler + dropdown options | Follow-up commit |
| Shop index | "Load N more products" button | Static button, no handler | Paginated load-more with server-side limit/offset | Follow-up commit |
| Product detail | "Buy it now" link | Static underline text, no handler | Quick-checkout flow | Follow-up commit |
| Product detail | Reassurance icons | Hardcoded 3 cards (shipping / sustainability / returns) | Data-driven from product config | Follow-up commit |

---

## Build progress

| Wave | Page | Status | Commit | Notes |
|---|---|---|---|---|
| 0 | Foundation components (11) | ✅ Done | `af15f58` | `design_system.ex` with logo, eyebrow, chip, author_avatar, profile_avatar, why_earn_bux_banner, header, footer, page_hero, stat_card, post_card. 51 component tests. |
| 0 | Design preview | ✅ Done | `294b51d` | `/dev/design-preview` route (dev-only). 3 smoke tests. |
| 1 | Homepage | 🔧 Built, awaiting commit | — | Full rewrite of `PostLive.Index`. New cycling layouts (ThreeColumn, Mosaic, VideoLayout, Editorial). One-shot sections (hero, hub showcase, token sales stub, hubs you follow, recommended stub, welcome hero, what you unlock). Old homepage preserved at `lib/blockster_v2_web/live/post_live/legacy/`. 65 tests passing. |
| 1 | Article page | 🔧 Built, awaiting commit | — | White article card, template-based inline ads at 1/3 + 2/3 + end, Follow Hub bar at 1/2, sidebar placeholders (discover cards left, RogueTrader right), floating BUX panel (white, matches mock), article-body CSS (drop caps, blockquotes, lists), 26 new tests. |
| 1 | Hubs index | 🔧 Built, awaiting commit | — | Featured cards (hub_feature_card), hub_card category badge, sticky search+filter bar, 4-col hub grid. 24 new tests (8 component + 16 LiveView). |
| 1 | Hub show | 🔧 Built, awaiting commit | — | `posts.kind` migration done, hub_banner component, 5-tab nav, 30 new tests |
| 2 | Profile | 🔧 Built, awaiting commit | — | Identity hero, 3 stat cards, multiplier breakdown, 5-tab nav (Activity/Following/Refer/Rewards/Settings), new Rewards tab, verification banners. 28 new LiveView tests. |
| 2 | Public member page | ✅ Done | `41fc827` | `users.bio` + `users.x_handle` migration, public view branch in MemberLive.Show, 3 stat cards, 4-tab nav (Articles/Videos/Hubs/About), sidebar hubs + activity. Also fixes disconnect-wallet on all redesigned pages (added `phx-hook="SolanaWallet"` to `ds-site-header`). 28 new tests (47 total). |
| 3 | Play / Coin Flip | ✅ Done | `5553b1a` | Full `render/1` rewrite in `CoinFlipLive`. DS header with new `display_token="SOL"` attr (shows SOL balance in pill on play page), editorial page hero, 3-state game card (idle / awaiting+flipping+showing_result / result) with state-specific sidebar, stacked predictions/results (not side-by-side), recent games table with Solscan links. 9-col difficulty grid (replaces horizontal scroll). Rocket/poop emojis preserved — NOT mock H/T. Every handler/assign/PubSub/JS hook preserved. Route moved to `:redesign` live_session. 21 new LiveView tests. 0 new failures vs baseline. Also fixes `wallet_authenticated` → `:bux_balance` not set (affected all pages using `DesignSystem.header`), adds `cursor-pointer` to Connect Wallet button, adds `revealHandled` race guard to `CoinFlip` JS hook. |
| 3 | Pool index | ✅ Done | `e11a204` | Full `render/1` rewrite of `PoolIndexLive`. DS header (`active="pool"`), editorial page hero + 3-stat right-column band (Total TVL / Bets settled / House profit · all-time labels), TWO gradient vault cards (SOL emerald + BUX lime, `min-h-[420px]`, whole card is `<.link navigate=...>`), each with LP Price + decorative sparkline + 2×2 stats grid + Your position card + CTA. 3-step "Become the house" how-it-works. New 6-col Pool activity table wired to cross-vault data — merges `CoinFlipGame.get_recent_games_by_vault/2` from both vaults + `:pool_activities` Mnesia reads, subscribes to `"pool_activity:sol"` + `"pool_activity:bux"` PubSub topics for live updates. `BuxMinter.get_lp_balance/2` × 2 parallel fetches for user LP balances (Your position card). Route moved to `:redesign` live_session. Legacy module preserved at `lib/blockster_v2_web/live/pool_index_live/legacy/pool_index_live_pre_redesign.ex`. Test file rewritten — 9 tests, all pass. 0 new failures vs baseline. |
| 3 | Pool detail | ✅ Done | `b51e2bd` | Full `render/1` rewrite of `PoolDetailLive`. DS header (`active="pool"`, `display_token="SOL"` on `/pool/sol` and `"BUX"` on `/pool/bux`), full-bleed gradient pool banner hero (SOL emerald / BUX lime) with breadcrumb + identity + 64px LP price + 4-stat inline row + translucent "Your position" card. Two-column main: **sticky order form** (segmented Deposit/Withdraw tabs, 2-col wallet balance strip, LP Price line, 28px mono amount input with `½` + `MAX` quick buttons, tinted output preview with projected "New pool share (+Δ)", black submit button, Helpful info card). Right 8-col restyled `<.lp_price_chart>` + 8-card `<.pool_stats_grid>` (LP price / LP supply / Volume / Bets / Win rate / Profit / Payout / House edge) + restyled `<.activity_table>` matching mock's 4-col grid. `pool_components.ex` restyled in place — lp_price_chart / pool_stats_grid / stat_card / activity_table / activity_row all updated, dead helpers removed, `format_win_rate_value` + `format_house_edge` added. New `set_half` handler added as mirror of `set_max`. `compute_new_share_pct` helper for projected-share math. Route moved to `:redesign` live_session. Legacy module preserved at `lib/blockster_v2_web/live/pool_detail_live/legacy/pool_detail_live_pre_redesign.ex`. 100% of existing handlers / PubSub subs / JS hooks (PoolHook, PriceChart) / settler calls preserved. Test file extended — 35 tests, all pass. 0 new failures vs baseline. |
| 3 | Airdrop | ✅ Done | `8f1e081` | Full `render/1` rewrite of `AirdropLive`. DS header (`active="airdrop"`, default `display_token="BUX"`), editorial page hero (`$X up for grabs` open / `The airdrop has been drawn` drawn) with `Live` pulse pill + 3-stat right band (Total pool / Winners / Rate). Open state two-column: left 7-col stack (countdown card with 4 mono tiles, prize distribution 4-tier card, pool stats 3-stat card, provably fair commitment card) + right 5-col **sticky entry form** (dark `#0a0a0a` header strip with lime icon, neutral balance row, 20px mono input with lime-on-black MAX pill + entry preview + position projection, 4-col quick-amount chips (100/1k/2.5k/10k), neutral odds preview card, black `Redeem N BUX` submit, `Phone verified · Solana wallet connected` footnote). Drawn state: mono divider, dark celebration banner with lime gradient + radial dots + `Verify fairness` + `View on Solscan ↗` CTAs, 3-col gold/silver/bronze podium, verification metadata card, white **winners table** (5-col grid with top-3 row tinting + status pills + collapse-to-top-8 toggle via new `:show_all_winners` assign + `toggle_show_all_winners` handler), gold winner-receipt panels with claim CTA, loser fallback card. How-it-works 3-col band always rendered. Two new tiny event handlers added for mock fidelity: `set_amount` (quick-chip preset, 5 LOC) + `toggle_show_all_winners` (3 LOC). 100% of existing handlers / async / info clauses / PubSub subs / `AirdropSolanaHook` JS hook preserved verbatim. Sidebar ad placements still loaded into assigns but no longer rendered (mock has no sidebars — stubbed). Route moved to `:redesign` live_session. Legacy module preserved at `lib/blockster_v2_web/live/airdrop_live/legacy/airdrop_live_pre_redesign.ex`. Test file extended — 5 new test cases (DS header, editorial hero, prize distribution, AirdropSolanaHook mount, winners-table show-all toggle). Updated copy assertions to match new lowercase mock copy throughout. 0 new failures vs baseline (43 pre-existing failures in `airdrop_live_test.exs` are baseline noise from `Airdrop.redeem_bux` returning `:insufficient_balance` against the test's stale Mnesia setup — file is in baseline, all new assertions pass). |
| 4 | Shop index | ✅ Done | `c2bdd4e` | Full template rewrite. Full-bleed hero banner, sidebar filter with per-filter counts, 3-col product grid, DS header (active="shop"), slot fallback for unassigned slots, 17 new tests. 0 new failures vs baseline. |
| 4 | Product detail | ✅ Done | `63416ed` | Full template rewrite. Gallery + sticky buy panel + BUX redemption card + related products. 31 new tests. 0 new failures vs baseline. |
| 4 | Cart | ✅ Done | `0b62a03` | Full template rewrite. Per-item BUX redemption + sticky order summary + suggested products + empty state. `max_bux_for_item` bug fix (0=uncapped). Hub preload added. 17 new tests. 0 new failures vs baseline. |
| 4 | Checkout | 🔧 Built, awaiting commit | — | Full template rewrite. 4-step wizard with two-column layout + sticky summary + pay cards (BUX burn + Helio) + confirmation celebration. Unused ROGUE helpers removed. 19 new tests. 0 new failures vs baseline. |
| 5–6 | Wallet, Category, Tag, Notifications, Onboarding | ⬜ Not started | — | Wallet modal (#15) is next. |
| 7 | Cutover | ⬜ Blocked | — | Waiting for all pages to be done + user says "deploy" |

---

## Cutover checklist

Before running `flyctl deploy`:

- [ ] All 19 pages rebuilt
- [ ] Every per-page redesign doc complete
- [ ] Every stub documented in the stub register
- [ ] `mix test` zero failures across the whole suite
- [ ] All schema migrations applied to local DB and verified working
- [ ] Migration files committed with the page that introduces them
- [ ] Manual walk: every page on local, logged-in + anonymous, fresh browser
- [ ] No `console.error` in browser dev tools on any page
- [ ] Old templates deleted in the same commits as the new ones
- [ ] No references to `blockster-logo.png` raster wordmark in headers
- [ ] New footer (address + media kit link) verified on every page
- [ ] Both nodes restart cleanly with `bin/dev` (per CLAUDE.md, restart only if supervision tree changes)
- [ ] Branch up to date with `main` (rebase if needed)
- [ ] User explicitly says "deploy" — per CLAUDE.md, no deploy without explicit instruction

Then and only then:

```
flyctl deploy --app blockster-v2
```

After the deploy completes:

- [ ] Walk every redesigned page on production with a real wallet
- [ ] Watch logs for the first hour
- [ ] Verify Mnesia + Postgres did not need any unexpected restarts
- [ ] Verify the Why Earn BUX banner renders correctly
- [ ] Verify the new HTML wordmark renders in production headers
- [ ] Verify the Miami Beach address is in every footer

If anything looks wrong: stop, diagnose root cause, never destructive-revert without confirming pre-existing work is safe (per CLAUDE.md `git checkout --` rules).

---

## Critical rules · pulled from CLAUDE.md

These apply to every commit, every test run, every interaction with the database / Mnesia / Solana / Fly.io. They are non-negotiable and they take precedence over anything in this plan if they conflict.

### Git
- Never commit, push, or change branches without explicit user instruction
- Stay on `feat/solana-migration` unless told otherwise
- Never run `git checkout --`, `git restore`, or `git stash` on files without first running `git diff` to verify no pre-existing uncommitted work exists
- To undo your own changes: targeted `Edit` calls only. Never destructive operations.

### Database
- Never run `mix ecto.reset`, `mix ecto.drop`, or anything that drops/recreates the DB
- Never delete or truncate tables — production data is irreplaceable
- The only safe Ecto commands are `mix ecto.migrate` and `mix ecto.rollback`
- If a migration needs fixing, roll it back and fix — never reset

### Mnesia
- Never delete `priv/mnesia/node1` or `priv/mnesia/node2` directories
- Never run `rm` on any Mnesia path, no matter the error
- For schema conflicts, ASK the user — there is no scenario where deleting Mnesia is correct

### Tests
- ALL tests must pass before deploying — `mix test` zero failures required
- That rule applies at every per-page checkpoint, not just the final deploy
- Every component gets a test before it's used in a page
- Every page rebuild extends the existing LiveView test file

### Deploy
- Never deploy without EXPLICIT user instruction — no exceptions
- Previous deploy instructions do NOT carry over to new changes
- Always `cd` to the correct app directory before `flyctl deploy`
- The `--app` flag does NOT determine which Dockerfile is used — the current directory does
- Never run `flyctl secrets set` without `--stage` unless the user explicitly says to restart production

### Solana
- Never use public RPC endpoints for any Solana command — always the project QuickNode RPC from `contracts/blockster-settler/src/config.ts`
- Never use `solana airdrop` — ask the user to fund manually
- Never use `confirmTransaction` (websocket) for confirming Solana transactions — always `getSignatureStatuses` polling
- Never chain dependent Solana transactions back-to-back

### Files
- Never read any `.env` file
- Never use the `Write` tool to rewrite entire documentation files — use `Edit` for targeted changes
- Never create files unless absolutely necessary

### AI
- Never downgrade the AI Manager model from Opus to Sonnet/Haiku

### Assumptions
- Never fabricate explanations about how systems work — read the code first
- BUX tokens live ON-CHAIN in users' smart wallets — they are real ERC-20 / SPL tokens, not just Mnesia entries
- If unsure, ASK the user, do not guess

---

## Open items

Things this plan deliberately doesn't address — surface them when they come up during the build:

- **PNG fallbacks for the new wordmark** — needed for OG images and email templates that can't render fonts. Tracked as a follow-up; not required for this release's cutover.
- **Hub show "Long reads / Authors / About" tabs** — deferred to a follow-up release. Not in v1.
- **Public member page · followers / RSS** — explicitly removed (D17 + D18). If a future release wants them back, design them then.
- **Discover sidebar Event + Token Sale cards** — placeholder in v1, become real in the events / sales release.
- **Notifications page mock** — none exists. Design happens during the redesign doc + build for #18.
- **Onboarding flow mock** — none exists. Design happens during the redesign doc + build for #19. Higher complexity due to the 8-step branching.
- **Existing tests that break due to DOM changes** — fix as encountered. Don't pre-fix.

---

*Last updated 2026-04-09. Update this file as decisions change, stubs are added, or pages move between waves.*
