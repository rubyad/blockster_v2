# Blockster Redesign — Project Overview

> The north-star doc for the design refresh that started as a small sidebar-widget integration and quietly grew into a full design-language overhaul. Read this first; it explains what we're doing, how we got here, and the order in which everything happens.
>
> **For design tokens, typography, the canonical CSS template, component patterns, conventions, and rejected approaches, read [`design_system.md`](design_system.md).** That doc is the spec. This doc is the project plan.

---

## How we got here

This project started as one thing and became three. The honest history:

1. **Day 1.** User asked for two real-time sidebar widgets on the article page — one streaming live trades from FateSwap, one streaming top RogueBots from RogueTrader. Tight scope. Plan written: `docs/solana/realtime_widgets_plan.md`. Mock written: `docs/solana/realtime_widgets_mock.html`.

2. **Iteration 1–N.** As we iterated on the mock to make the widgets look right "in their natural context," the rest of the article page came along for the ride. We restyled the header, redesigned the BUX earning UI, rebuilt the ad banner system, added drop caps, added a Moonpay hub badge, added suggested-reading cards, designed a new dark footer, picked new fonts (Inter + JetBrains Mono + Segoe), and locked in a color palette.

3. **The realization.** What started as "two widgets" became a full visual reset of the article page. The new design language is stronger than the existing site and the user wants to apply it across every page, not just the article. **The widgets project is now nested inside a much larger redesign project that nobody planned.**

This doc exists so the next person who reads `realtime_widgets_plan.md` doesn't think the scope is two widgets when it's actually three projects sharing one mock file.

---

## What we're actually doing (the three projects)

| # | Project | Status | Scope | Risk |
|---|---|---|---|---|
| 1 | **Sister-project widgets** | Plan written, no code | FateSwap + RogueTrader sidebars on article page only. New APIs in 2 sister apps + 2 pollers + 2 widgets in Blockster. | Low — scoped, contained |
| 2 | **Article page redesign** | Mock complete (`realtime_widgets_mock.html`), no plan doc, no code | Full visual + structural redesign of `/post/:slug`. New header, footer, ad system, BUX earning UI, drop caps, byline, hub badges, cards. | Medium — touches `show.html.heex` (~1200 lines) and a lot of LiveView state |
| 3 | **Site-wide rollout** | No mocks, no plans, no code | Apply the redesign + design system to every other page: homepage, hub, profile, shop, pool, play, airdrop, category, member. | High — many pages, broad blast radius |

The widgets (project #1) are designed to live inside the redesigned article page (project #2), which uses components that will also be used by the rest of the site (project #3). Doing them out of order would mean building things twice.

---

## The approach (mock first, then extract, then build)

We're following a strict three-phase rhythm:

**Phase 1 — Mock.** Each page gets a full visual mock in HTML/Tailwind, in the same `docs/*.html` style as the article mock. Iterate until the design is signed off. This is where all the design decisions happen.

**Phase 2 — Extract.** Once *all* pages are mocked, we go through them and pull every recurring element into a reusable Phoenix component library: `lib/blockster_v2_web/components/design_system/`. Each component becomes a `.heex` function with proper assigns. We also write `docs/design_system.md` documenting tokens (colors, fonts, spacing, shadows) and component usage.

**Phase 3 — Build.** Each page is rebuilt in Phoenix using the new component library, preserving every existing LiveView handler and event. Pages ship one at a time, optionally behind a feature flag, so we never break production.

Why this order:
- **Mock first** captures the full design language before we touch real code, so we don't extract the same component twice.
- **Extract second** consolidates everything in one pass, with the benefit of seeing how components are reused across pages.
- **Build third** lets us ship pages incrementally with low risk because the components are already validated by the mocks.

---

## Doc split (still TBD)

The current `realtime_widgets_plan.md` and `realtime_widgets_mock.html` are doing too much work. They're the only docs that exist for what is now a much larger project. We need to split them after all the page mocks are done. The split looks like this:

| Doc | Purpose | Status |
|---|---|---|
| `docs/redesign_overview.md` | This doc — north star, project history, sequencing | **Just created** |
| `docs/solana/realtime_widgets_plan.md` | Just the widget integration: APIs, pollers, JS hooks, PubSub topics. Stays narrow. | Exists, needs trimming after the split |
| `docs/solana/realtime_widgets_mock.html` | Visual source of truth for the **article page** redesign + the widgets that live inside it | Exists, will be renamed to `article_page_mock.html` after the split |
| `docs/article_page_redesign_plan.md` | Buildable plan for the article page redesign (separate from the widgets) | **Doesn't exist yet — written after all page mocks done** |
| `docs/homepage_mock.html` | Visual mock of the new homepage | **Next file to create** |
| `docs/homepage_redesign_plan.md` | Buildable plan for the homepage redesign | Written after homepage mock signed off |
| `docs/[page]_mock.html` × N | One mock file per page (hub, profile, shop, pool, play, airdrop, category, member) | One per page, written in sequence |
| `docs/[page]_redesign_plan.md` × N | One plan per page | Written after each mock |
| `docs/design_system.md` | Design tokens + component reference. Single source of truth for fonts, colors, spacing, shadows, and every reusable component in `lib/blockster_v2_web/components/design_system/`. | **Written during Phase 2 (extract)** |

The doc split happens **after** all the page mocks are done, not now. Splitting too early would mean rewriting the same files multiple times as we discover new components in later mocks.

---

## What's locked in already

Captured in `docs/solana/realtime_widgets_mock.html`:

- **Color palette** — `#0a0a0a` (dark surfaces), `#fafaf9` (page bg), `#141414` (text), `#343434` (body text), `#CAFC00` (lime brand accent), `#7D00FF` (Moonpay purple), `#22C55E`/`#EF4444`/`#EAB308` (trading semantics), `#9CA3AF`/`#6B7280` (muted)
- **Typography** — `Inter` for haas-fallback display + body, `Segoe UI` for article body (matching `font-segoe_regular`), `JetBrains Mono` for numerics, `IBM Plex Sans` for trading widget UI
- **Drop caps** — Inter 700 / 58px / `padding: 6px 8px 0 0` on every article body paragraph
- **Trading widgets** — dark `#0A0A0F` cards, JetBrains Mono numerics, IBM Plex Sans labels, pulsing LIVE pills, fixed `760px` height, "Sponsored" caption above
- **Header** — `https://ik.imagekit.io/blockster/blockster-logo.png` at `h-[22px]`, BUX balance pill, lime "Why Earn BUX?" sticky band underneath
- **BUX earning UI** — clean white pill at top of article + clean white floating panel bottom-right (NOT dark, NOT pastel green — both directions tried and rejected)
- **Ad banner system** — four variants in the mock: `inline_dark` (dark gradient with ambient blur orbs), `split_bottom` (white card with image-block split), `portrait_stonepeak` (tall portrait ad with photo + colored block), `follow_strip` (Forbes-style horizontal black bar)
- **Suggested reading cards** — white card, hub badge, 3-line title clamp, author + read time, lime BUX reward pill, hover lift
- **Hub badge** — small purple square with hub icon + name, used inline in author bylines and ad banners
- **Author byline** — initials avatar (dark gradient with 2-letter initials in Inter 700)
- **Footer** — dark `#0a0a0a` 4-column layout with mission line, social icons, link columns, newsletter form

Everything else is fair game.

---

## Homepage direction (locked from the planning chat)

The homepage redesign will follow these directional decisions, made before the mock starts:

**1. Layout**: Magazine cover with editorial hierarchy. One large featured story dominates above the fold (big image, big headline, byline, BUX reward, hub badge). Beneath it, **infinite scroll continues** but cards are **non-equal sizes** — a mosaic / masonry layout that mixes large, medium, and small cards rather than a uniform grid. Treats Blockster as a publication that curates, not a feed reader.

**2. BUX earning prominence**: **Quiet.** No earning hero band. No "you've earned X today" headline. The BUX angle is communicated through small earning badges on each post card (current behavior, just restyled in the new design language) and the existing lime "Why Earn BUX?" banner that's already in the header. Reading is the front; earning is a layer underneath.

**3. Hub showcase**: **Yes, big.** With 66 real hubs already seeded in production (Solana `#00FFA3`, Ethereum `#627EEA`, Bitcoin `#F7931A`, Polygon `#8247E5`, Arbitrum `#28A0F0`, Base `#0052FF`, Moonpay `#7B3FE4`, plus 59 more) there's a strong visual element here. Dedicated section with a horizontal scroller / grid of branded hub cards. Each card: brand color background, logo, post count, follower count, "Follow" button styled like the Forbes-strip CTA. Sits high on the page, second only to the hero. Sponsored hubs (like Moonpay) get prominent placement worth paying for.

**4. Logged-in personalization**: **Yes.** Logged-in users see different sections than anonymous users:
- "Continue reading" — articles in progress
- "Hubs you follow" — personalized feed
- "Recommended for you" — based on reading history
- Personal BUX earnings stat (in the existing pill, no extra hero)

Anonymous users see editorial picks + a sign-in CTA woven into the page (not a hard wall).

We'll mock both states in the same file.

---

The widgets are at the END of the build sequence on purpose. They live inside the redesigned article page, so they get built once on top of stable foundations rather than twice (once on the old page, once on the new page).

---

## Why this isn't insane

It looks bigger than necessary because the work that's already been done is invisible — it lives in one HTML mock file. But:

- The design is **already done** for the article page. Phase 1 just propagates it to every other page through more mocks.
- Phase 2 (component extraction) is **mostly mechanical translation** of mock HTML into Phoenix components. Each component is small.
- Phase 3 (build) is **the actual risk**, but it's surface-level (visual layer over existing LiveView state). No business logic changes.
- Phase 4 (widgets) is the **only project that needs new APIs and cross-app coordination**. By the time we get there, the article page is already in production with the new design.

The unusual thing about this project is that the design language emerged from the wrong starting point — a widget integration. But the mock that came out of it is the real artifact, and the work is now to apply it everywhere it should have been applied from the start.

---

## Mocks status · what's done and what's next

> **Read [`design_system.md`](design_system.md) first.** It captures every reusable pattern, the canonical CSS template, color tokens, conventions, and the things we tried and rejected. A new session can read that doc + one example mock and produce a stylistically consistent next page.

### Done ✓

- [x] **Article page** → `realtime_widgets_mock.html` (drop caps, ad banner system, sister-project widgets in sidebars, BUX earning UI, suggested reading)
- [x] **Homepage** → `homepage_mock.html` (anonymous lead with Connect Wallet header, magazine-cover featured story, AI × Crypto category row, trending mosaic, hub showcase, dedicated videos section, logged-in additions)
- [x] **Hubs index** → `hubs_index_mock.html` (featured hub strip, sticky search + category chips, 4-col hub grid)
- [x] **Hub show** (Moonpay example) → `hub_show_mock.html` (full-bleed brand banner, sticky tab nav, pinned post, mosaic, authors, hub-sponsored ad)
- [x] **Profile** → `profile_mock.html` (identity hero, 3 stat cards, multiplier breakdown, all 5 stacked tab states: Activity / Following / Refer / Rewards / Settings)
- [x] **Play** (Coin Flip) → `play_mock.html` (3 stacked states: Place bet / In progress / Result win+loss, stylized H/T coin design, recent games table)
- [x] **Pool index** → `pool_index_mock.html` (two big vault cards SOL + BUX, how it works 3-step, cross-pool activity)
- [x] **Pool detail** (SOL pool example) → `pool_detail_mock.html` (brand banner, sticky order form with deposit/withdraw tabs, LP price chart, 8-stat grid, activity table)

### Remaining ☐

**Hub show — additional tab states**
- [ ] Update `hub_show_mock.html` to add stacked tab states for the remaining tabs (currently only the **All** tab is shown). Add: News, Videos, Long reads, Shop (hub-specific products), Events, Authors (full author roster), About (full hub bio + team + links). Use the `state-divider` pattern with mono labels above each tab state. The Moonpay example should remain consistent throughout.


**Shop**
- [ ] `shop_index_mock.html` — main shop page (product grid, category filters, featured products, BUX/Helio price toggle, trending strip)
- [ ] `product_detail_mock.html` — single product page (image gallery, variants/sizes, description, BUX vs Helio payment, reviews, related products, partner hub badge if applicable)
- [ ] `cart_mock.html` — cart drawer or page (line items, totals, BUX balance check, proceed to checkout)
- [ ] `checkout_mock.html` — multi-step checkout (shipping, payment method selector — BUX or Helio, order confirmation, all states)

**Airdrop**
- [ ] `airdrop_mock.html` — airdrop page (current round, prize pool, your entries, recent winners, deposit BUX to enter, history of past rounds)

**Token Sales** *(new section requested)*
- [ ] `token_sales_index_mock.html` — index of upcoming token sales (cards with project name, brand color, raise target, allocation type, countdown, "Register" CTA)
- [ ] `token_sale_detail_mock.html` — single sale page (project hero, tokenomics, schedule, allocation tiers, your entry status, FAQ)
- [ ] **Plus**: add a token sales promo strip section to `homepage_mock.html` showing the next 2-3 upcoming sales

**Categories + Tags** *(new section requested)*
- [ ] `category_mock.html` — category browse page (e.g. /category/defi) — filtered post grid with category-specific styling, related categories, featured author in this category
- [ ] `tag_mock.html` — tag browse page (e.g. /tag/solana) — similar to category but for free-form tags

**Member**
- [ ] `member_public_mock.html` — public-facing member page (`/member/:slug` viewed by someone else, not the owner) — author bio, post count, BUX earned, reading streak, recent published articles, social links, follow button. Distinct from `profile_mock.html` which is the owner-only view.

**Wallet UI** *(new request)*
- [ ] `wallet_modal_mock.html` — wallet connect modal that appears when "Connect Wallet" is clicked, showing Phantom / Solflare / Backpack with logos and connect buttons. Could be a standalone mock or included as a state in the homepage mock.

### After all mocks are done

- Split `realtime_widgets_plan.md` into widget-only plan (what stays) + redesign plans per page
- Update `design_system.md` if any new patterns emerged during the remaining mocks
- Start Phase 2 (component extraction in `lib/blockster_v2_web/components/design_system/`)

---

## Order of operations (current → eventual)

```
NOW          ↓
─────────────────────────────────────────────────────────
Phase 1 — Mocks (in progress)
  [done]     Article page · Home · Hubs index · Hub show · Profile · Play · Pool index · Pool detail
  [next]     Shop main · Product · Cart · Checkout
             Airdrop
             Token sales index · Token sale detail · homepage promo strip
             Category · Tag
             Public member page
             Wallet connect modal
─────────────────────────────────────────────────────────
Phase 1.5 — Doc split + design system finalization
             Split realtime_widgets_plan.md into widget-only + redesign plans
             Finalize design_system.md
             Write per-page redesign plans
─────────────────────────────────────────────────────────
Phase 2 — Component extraction
             Build lib/blockster_v2_web/components/design_system/
─────────────────────────────────────────────────────────
Phase 3 — Build (page by page, behind feature flag)
─────────────────────────────────────────────────────────
Phase 4 — Sister-project widgets
─────────────────────────────────────────────────────────
LATER        ↓
```

---

*Last updated 2026-04-09. Update the "Mocks status" checklist as mocks complete.*
