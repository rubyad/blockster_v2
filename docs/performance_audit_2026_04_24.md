# Blockster Performance Audit — 2026-04-24

**Scope:** Runtime performance of Blockster V2 Phoenix LiveView app on `feat/solana-migration` branch, measured against local dev cluster (Node 1 :4000, Node 2 :4001, settler :3000) while signed in as `adam@blockster.com` (user_id 1011, wallet `EPhSojGV2NNMDh8dR2NUYA41eDPib3ey35c7pRhUnXoo`).

**Method:**
- Playwright/Chromium instrumentation of each primary route
- `PerformanceNavigationTiming` + `PerformanceResourceTiming` extraction
- Console-log capture of LV diffs, server log tee-through via `phoenix/live_reload/frame`
- Static inspection of `lib/blockster_v2_web/live/*` for mount-time work
- Bundle size checks against `priv/static/assets/*`

**Bottom line:** The app is **fast** on the dev hot path — every page paints under 500 ms FCP with very small initial HTML payloads (typically 70-90 KB, capped by the homepage at 157 KB and `/shop` at 249 KB). The real cost is elsewhere: oversized hero images, the article page's 3,544-node DOM with a duplicate-ID widget bug, a 1-second `:timer.send_interval` on `/airdrop`, triple-broadcast balance refresh on checkout, and background schedulers (TopicEngine, FeedPoller) that burn CPU without guardrails. There are no blocking synchronous HTTP calls on the critical user path; `start_async` is used correctly in the LiveViews most users hit.

This report is **measurements + recommendations only** — no code changes.

---

## 1. Top-line numbers (navigation timing, dev cluster, warm cache)

| Page | TTFB | FCP | DCL | Load | Doc HTML KB | Total KB | Resources | DOM nodes |
|------|-----:|----:|----:|-----:|------------:|---------:|----------:|----------:|
| `/` (home) | 224 | 416 | 326 | 454 | 157 | 865 | 38 | 1,701 |
| `/hubs` | 214 | 404 | 392 | 508 | 221 | 201 | 26 | 1,509 |
| `/hub/flare` | — | — | — | — | — | — | — | — *(500 error — see §7)* |
| `/shop` | 171 | 484 | 275 | 523 | 249 | **897** | 39 | 1,336 |
| `/shop/digital-distraction` | 158 | 348 | 201 | 389 | 70 | 288 | 32 | 407 |
| `/cart` | 210 | 408 | 288 | 467 | 74 | 203 | 34 | 420 |
| `/checkout/:id` | — | — | — | — | — | — | — | — *(live_patch — no full nav)* |
| `/play` | 187 | 356 | 232 | 399 | 82 | 200 | 25 | 568 |
| `/pool` | 287 | 472 | 333 | 494 | 78 | 200 | 25 | 552 |
| `/pool/sol` | 174 | 348 | 216 | 380 | 81 | 200 | 25 | 1,418 |
| `/pool/bux` | 191 | 308 | 233 | 326 | 81 | 200 | 25 | 1,420 |
| `/binance-...-7he-selection` (article) | 177 | 320 | 221 | 338 | 77 | **908** | 35 | **3,544** |
| `/wallet` | 191 | 368 | 242 | 384 | 90 | 200 | 26 | 658 |
| `/notifications` | 189 | 296 | 232 | 341 | 69 | 200 | 27 | 358 |
| `/airdrop` | 208 | 308 | 276 | 368 | 78 | 200 | 26 | 493 |
| `/member/:pubkey` | 288 | 432 | 351 | 469 | 84 | 200 | 26 | 549 |

> **Reading the columns:** TTFB/FCP/DCL/Load in ms. `Doc HTML KB` = size of the initial HTML document (decoded); `Total KB` = sum of every resource the page pulled in; `Resources` = count of requests (including the `/phoenix/live_reload/frame`, which is dev-only).

### What stands out
- **FCP is consistently 300-500 ms.** That's excellent for a non-edge-served LiveView in dev. On prod (Fly.io IAD, CDN-fronted) expect 150-250 ms for the same shell.
- **The homepage ships 559 KB of imagery** across 14 `<img>` elements. Three Unsplash banners (120 KB + 120 KB + 80 KB) and one 152 KB Gray & Sons ad dominate. See §3.
- **`/shop` is the weight leader — 897 KB total, 697 KB from a *single* PNG:** `ik.imagekit.io/blockster/Web%20Banner%203.png`. No `?tr=w-...,f-auto` transform on that URL. See §3.
- **Article pages carry 908 KB + 3,544 DOM nodes** — driven by eight widget tiles, a second-content sidebar, a recommendations rail, multiple Unsplash hero/inline photos, and the site-wide rogue-trader ticker. The ticker alone contributes ~800 nodes (32 tickers duplicated for infinite-scroll animation). Worst offender on any route by a wide margin. See §4.
- **All LV mounts emit 3-5 separate diff updates inside the first second** (e.g. homepage console: `mount` at 639 ms, then `update` at ~720 ms, ~760 ms, ~1600 ms, ~1950 ms). Each is a server→client roundtrip. Not blocking FCP, but each extra diff is a patch + re-render pass. Pattern: mount returns skeleton, then one or more `start_async` results arrive, then a PubSub broadcast lands, then a periodic tick fires. See §5.

---

## 2. Front-end bundle

```
/Users/tenmerry/Projects/blockster_v2/priv/static/assets/
  app-e1e8a0bbed56b65d41a4f831b48bce09.js          6,857,439  bytes  (uncompressed)
  app-e1e8a0bbed56b65d41a4f831b48bce09.js.gz       1,907,921  bytes  (gzip)
  app-e66e699d7e655d61a1bf5df0ca166133.css            12,292  bytes
  app-e66e699d7e655d61a1bf5df0ca166133.css.gz          2,370  bytes
  /js/app-9310b3897911386e5033d870e025d86f.js        625,255  bytes  (alt entry)
  /js/app-21f441de633c332460d74811d210643d.js      3,859,569  bytes  (stale Feb build?)
```

- **Prod `app.js` ships 1.91 MB gzipped, 6.86 MB uncompressed.** That is heavy for a Phoenix site — the weight is Web3Auth + their transitive deps (ws-embed, `@web3auth/sapphire-auth-session`, MPC-core-kit bits, `@noble/hashes`, `@solana/web3.js`, plus the TipTap editor for the post composer). Two non-obvious passengers the build pulls in for hub discovery but rarely exercised:
  - **React + React DevTools noise** — console emits `Download the React DevTools for a better development experience:` on every page. Some dependency is bundling React even though Blockster is 100% LiveView + vanilla JS hooks. Worth chasing — eliminating React alone would likely cut 30-40 KB gz.
  - **i18next** — console emits `i18next is made possible by our own product, Locize`. Web3Auth's wallet selector is the likely consumer; it registers the full i18n runtime on every page load. Not visibly wired up anywhere in Blockster's UI.
- **Dev-only `app.js` (1.59 MB) is served without gzip** by the Phoenix esbuild watcher. Fine in dev, but note that the first load in a fresh browser eats a ~1.6 MB uncompressed script on the dev server.
- **Second, stale build artifact:** `priv/static/assets/js/app-21f441de633c332460d74811d210643d.js` is 3.86 MB and last-modified Feb 4. It's not referenced by the current manifest but still ships to production in the Docker image. Delete it to save ~4 MB per deploy image.
- **app.css is 12 KB uncompressed.** Virtually everything comes from Tailwind's JIT output, which is inlined per-page — that's already optimal.

### Recommendations
1. **Audit the Web3Auth bundle.** `@web3auth/modal` pulls in React (`react`, `react-dom`, `@emotion/*`) that is not used outside the modal. If the modal itself is rendered server-side and only the signing code is JS, the modal UI bundle is dead weight on 100% of page loads. Consider `import()`-splitting the modal so it only downloads on `Connect Wallet` click.
2. **Lazy-load the TipTap editor.** It's only needed on admin/composer routes. Currently imported eagerly in `app.js`.
3. **Delete `priv/static/assets/js/app-*.js` stale entries.** Keep only the current hashed filename.
4. **Remove `i18next`** if nothing in Blockster UI actually uses it (it ships with Web3Auth's wallet modal; if you control the modal config you can disable locale bundling).

---

## 3. Images

### Offenders (sizes are decoded, not transfer)

| URL (trimmed) | Size | Where | Fix |
|---|---:|---|---|
| `ik.imagekit.io/blockster/Web%20Banner%203.png` | **697 KB** | `/shop` hero | Add `?tr=w-1600,q-85,f-auto` — target ≤ 120 KB |
| `images.unsplash.com/photo-1639762681485-…?w=1600&q=80&auto=format&fit=crop` | **173 KB** | article hero | Lower to `w=1000` — ~90 KB |
| `ik.imagekit.io/blockster/ads/grayandsons/1776222731-879ba0a4c7b8-submariner-snug.jpg?tr=w-1200,q-95,f-auto` | **152 KB** | sidebar ad on `/` | Drop `q=95` to `q=85` — ~95 KB |
| `ik.imagekit.io/blockster/ads/grayandsons/1776222731-552693c61f97-gmt-snug.jpg?tr=w-1200,q-95,f-auto` | **158 KB** | sidebar ad on article | Same |
| `images.unsplash.com/photo-1622630998477-…?w=1200&h=600&fit=crop` | 120 KB | hub card on `/` | `w=600` |
| `images.unsplash.com/photo-1518546305927-…?w=1200&h=600&fit=crop` | 120 KB | hub card on `/` | `w=600` |
| `images.unsplash.com/photo-1640340434855-…?w=1200&h=600&fit=crop` | 79 KB | hub card on `/` | `w=600` |
| `images.unsplash.com/photo-1611974789855-…?w=1200&h=600&fit=crop` | 73 KB | article inline | `w=600` |
| `ik.imagekit.io/.../63fad1d7-…png?tr=w-800,h-600,q-90,f-auto` | 74 KB | shop card | Already sized — fine |

### Counts
- Homepage: 14 `<img>`, 559 KB.
- Article page: **82 `<img>`**, 733 KB (most lazy-loaded, but they still negotiate connections and decode on scroll).
- `/shop`: 17 `<img>`, 722 KB — but has **93 product cards marked `loading="lazy"`** (12 eager). Initial payload is OK; scrolling will pull the rest.

### Recommendations
1. **Put the `/shop` hero behind ImageKit's transform layer** — it is the single highest-leverage win on the whole site. Shrinks 697 KB → ~110 KB.
2. **Ad banners served via ImageKit use `q=95`.** Drop to `q=85` across the `grayandsons/*` ads. Visually indistinguishable, ~35 % smaller.
3. **Hub-card Unsplash URLs use `w=1200&h=600`** even though the rendered slot is 560 px wide on desktop, 380 px on mobile. Halve them.
4. **Enforce ImageKit usage in the Banner schema.** Today editors can paste raw Unsplash / S3 / imagekit URLs interchangeably; nothing normalizes or attaches `tr=` params on save. Consider a helper `ImageKit.transform/2` used anywhere `banner.image_url` is rendered.
5. **Homepage hero/ticker images render with `loading="eager"`** — correct. Confirmed 12 eager + 93 lazy on `/shop` (numbers match the above-the-fold rule from CLAUDE.md).

---

## 4. DOM weight — especially article pages

Article page (`/binance-...-7he-selection`) has **3,544 DOM nodes**. For reference, Google recommends < 1,500 for LCP-sensitive surfaces. Breakdown:

| Contributor | Approx. nodes | Notes |
|---|---:|---|
| Rogue Trader ticker | ~800 | 32 token tiles × 2 copies (for CSS marquee loop) × ~12 nodes per tile |
| Rendered article body (TipTap) | ~400-1000 | Depends on article |
| Sidebar recommendations (6 articles × 3 columns grid) | ~400 | |
| Inline widgets (ads, banner, newsletter CTA) | ~150 | |
| Footer + header + hub CTAs | ~400 | |
| Widget duplicates (see next §) | ~150 | bug |

The ticker — rendered by `lib/blockster_v2_web/components/rogue_trader_ticker.ex` (inferred from `/` markup — `generic "TRADER Live ... Deposit SOL"`) — is CSS-animated by duplicating the list. That's the right technique, but with 32 tokens × 2 it eats 768 nodes on **every** page (it's in the root layout). Consider reducing to the top 8 most-traded tokens, or virtualizing with `IntersectionObserver` to pause ticker animation when it's not in the viewport.

### The widget-69 bug (confirmed by a sub-agent)
- **Where:** `lib/blockster_v2_web/components/widget_components.ex:61-89`, the `inline_ad_slot` component.
- **Symptom:** Console logs `Multiple IDs detected: widget-69` five or more times during mount, and again on every LV update that involves that widget.
- **Root cause:** The component renders the same widget twice in the DOM — once in a `hidden lg:block` wrapper, once in a `lg:hidden` wrapper — both with the same `id={"widget-#{@banner.id}"}`. `mobile_swap` transforms the content but not the id.
- **Perf impact:** Every duplicate-ID error forces the LV morphdom diff to re-scan and degrade to a fallback patch path for that subtree. Small per-update, but article pages fire LV updates every 2 seconds (engagement tracker, see §5), so the error count accumulates to dozens per article view.
- **Recommendation:** Suffix the id per viewport: `id={"widget-#{@banner.id}-#{@viewport}"}` or conditionally render only one per breakpoint.

---

## 5. LiveView mount timing & diff storms

Every page emits 3-5 diffs in the first second or two of mount. Example `/play` console trace:

```
507 ms  phx mount (s:71 -> server sends initial fingerprint)
734 ms  update {0, p}                 (balance sync returns)
744 ms  update {0, p}                 (PubSub subscribe echo)
769 ms  update {0}                    
1612 ms update {0, p}  orphan bet detected
1948 ms update {0, p}  [CoinFlipGame] Commitment submitted on chain
```

That last 1,948 ms event is **an on-chain Solana transaction submitted by simply visiting `/play`** — see §8.

### Why multiple diffs happen
- Every LiveView does its `connected?` branch in mount, kicks `BuxMinter.sync_user_balances_async`, subscribes to `"bux_balance:<user_id>"`, then later receives a `{:token_balances_update, ...}` broadcast.
- That broadcast fires **three separate times** on login/refresh — once per token update plus once combined — see next subsection.
- Then any `start_async` assigns complete and trigger their own diff.

This isn't *broken*, but it means the page lights up 3-5× between FCP and interactive. Each diff is a ~0.3-1 KB WS payload and a morphdom pass.

### BuxBalanceHook triple-broadcast (confirmed)
- **Where:** `lib/blockster_v2/bux_minter.ex:199-223`, function `sync_user_balances/2`.
- **Today:** `update_user_solana_bux_balance` broadcasts `%{"BUX" => ...}`, then `update_user_sol_balance` broadcasts `%{"SOL" => ...}`, then `broadcast_token_balances_update` broadcasts both. All three hit `bux_balance:#{user_id}` and wake up every subscribed LV.
- **Observed on `/checkout`:** three separate LV updates, three re-renders.
- **Fix direction:** Drop the two per-token broadcasts. Only emit the combined broadcast once, after both updates complete. Single-line change with broad impact (`/play`, `/checkout`, `/cart`, `/wallet`, `/pool/*`, `/shop/:slug`, and anywhere `<.balance_display>` is rendered all subscribe to this topic).

### `/airdrop` re-renders 60×/minute on every viewer
- **Where:** `lib/blockster_v2_web/live/airdrop_live.ex:73`
- `:timer.send_interval(1000, self(), :tick)` fires regardless of whether the countdown label changed. The assign patterns inside `:tick` rebuild the same HH:MM:SS strings each second.
- **Fix direction:** Reduce to 15 s intervals, or compute the remaining seconds once and let the client do the count-down via a JS hook (`CountdownHook` with `start_ts` passed in once). Either eliminates 95% of the tick traffic.

### Checkout polling fallback
- **Where:** `lib/blockster_v2_web/live/checkout_live/index.ex:399, 461`
- `Process.send_after(self(), :poll_intent_status, 1500)` polls the settler every 1.5 s as a safety net against PubSub drops.
- Not a hot problem (short-lived per checkout), but on a `PaymentIntentWatcher` stall every 1.5 s is a settler HTTP call. Consider exponential backoff to `1500 → 3000 → 5000` and a cap of ~60 s.

---

## 6. Engagement tracker on article pages

- **Where:** `assets/js/app.js:361593` (`EngagementTracker`)
- **Cadence observed:** `Sending update - time: 2s, depth: 11%, events: 1` at **2-second intervals** after first scroll event. That's **30 `push_event` round-trips per minute per open article**. Each pushes a small payload (~50 B) and triggers an LV `update` diff.
- **Server-side consequence:** Each update calls into `EngagementTracker` which touches Mnesia and potentially schedules reward calculation. Cheap individually, but at 30 updates/min × 100 concurrent readers = 3,000 Mnesia writes/min on one node.
- **Recommendation:**
  1. Coalesce updates to every **10 seconds** (or on `visibilitychange` / `beforeunload`). A 5× reduction is invisible to the reward math — the server only needs the total seconds read and final depth, not a sample every 2 s.
  2. If you truly want 2-second fidelity for bot-detection scroll velocity, keep it **client-side** and only push the derived bot-score/engagement-score on 10 s intervals.

---

## 7. Functional errors that degrade perceived perf

While measuring I hit two hard server errors. They're not pure perf issues but they produce slow UX (full 500 page, retry, etc.):

### 7.1 `/hub/:slug` — `KeyError :variants`
- **URL:** Any `/hub/:slug` — confirmed on `/hub/flare` and `/hub/solana`.
- **Stack:** `lib/blockster_v2/shop.ex:63` — `product.variants |> List.first()`.
- **Root cause (from error body):** `prepare_product_for_display/1` is being called with an already-transformed map (the map in the error shows keys `id, name, slug, image, images, price, total_max_discount, max_discounted_price` — the output shape of the function). So either:
  - The hub code calls `prepare_product_for_display` on `prepare_product_for_display`'s own output (double-transform), or
  - A cached transformed map is being fed back into the pipeline.
- **Where to look:** `lib/blockster_v2_web/live/hub_live/show.ex` around the featured-products section. Grep for `prepare_product_for_display` — expect to see it called once too many times.
- **Impact:** Every hub page currently 500s. Silent graveyard — nobody is hitting hubs right now per analytics you'd have on file, but the link exists in the nav.

### 7.2 `[TelegramNotifier] Failed to send: Req.TransportError{reason: :closed}` during checkout
- **Where:** `lib/blockster_v2/notifications/*` fires on order status transitions.
- **Impact:** User clicks "Proceed to checkout" → the flow fires a Telegram notification that fails with a transport error. The failure path is async, so it doesn't block the user, but each failure surfaces as a `[TelegramNotifier] Failed…` + `[Fulfillment] Unexpected result:` pair. In production it would retry once and give up; in dev the error is cosmetic.
- **Recommendation:** The fulfillment pipeline should swallow Telegram failures and record them as a job-retry, not crash the fulfillment step.

---

## 8. Solana / on-chain side effects on page load

Two noteworthy, probably-intentional, but worth-flagging side effects:

### 8.1 `/play` submits an on-chain commitment at mount
- **Observed console:** `[CoinFlipGame] Commitment submitted - sig: 1PHc…, player: EPhSoj…, nonce: 3` fires ~1,950 ms after mount, with no user input.
- **Mechanism:** `coin_flip_live.ex:57` — `start_async(:init_game, fn -> CoinFlipGame.get_or_init_game(user_id, wallet) end)` — calls the settler, which builds and submits a commitment tx.
- **Why it exists:** To make the *first* bet placement feel instant (the commitment is pre-submitted).
- **Why it's a cost:** Every `/play` mount with no existing unplayed game burns a transaction fee from the settler's mint-authority keypair. If the user doesn't actually bet, that SOL is gone.
- **Recommendation:** Gate commitment submission behind the first user interaction (token/amount/prediction selection), not behind mount. The settler-side tx cost scales linearly with drive-by `/play` visits.

### 8.2 `[BuxBalanceHook] Broadcasting…` fires via the dev live-reload overlay every page
- This is the triple-broadcast from §5. Confirmed in prod code path too — not just dev.

---

## 9. Background workers that burn idle CPU

Surfaced by the dev live-reload overlay (server log teed to client). All run in a `GlobalSingleton` so the cost is cluster-wide, not per-node.

### 9.1 TopicEngine / ContentGenerator
- **Where:** `lib/blockster_v2/content_automation/topic_engine.ex`, `.../content_generator.ex`
- **Cadence:** every **15 minutes** (`topic_analysis_interval`).
- **Current behavior:** Consumes the last 50 feed items, clusters with Claude (expensive API call), ranks, picks top 4, hands each to `ContentGenerator`. `ContentGenerator` immediately logs `No author account found — run seeds first` and exits.
- **Cost per cycle right now:** 1× Claude API call (topic clustering), 4× early-exit. Claude call cost is non-trivial; it runs 96×/day.
- **Recommendation:** Guard the whole pipeline with `if AuthorRotator.has_personas?() do ... end`. When no authors are seeded, skip the clustering entirely.

### 9.2 FeedPoller
- **Where:** `lib/blockster_v2/content_automation/feed_poller.ex`
- **Cadence:** every **5 minutes** (`feed_poll_interval`).
- **Observed:** 58 ok, 5 failed, 1 new item stored. Failures are recurring TLS errors (`:unexpected_message`, `{:unsupported_record_type, 72}`) against Optimism Blog, Base Blog, zkSync Blog, Scroll Blog (404), and one parse failure.
- **No backoff:** Same 5 feeds fail every 5 minutes forever.
- **Recommendation:** Track consecutive failures per feed; skip for 4× the interval after 3 consecutive failures; auto-heal when the feed recovers. Also catalog the TLS errors — they look like feeds that require HTTP/2 ALPN or a newer OpenSSL cipher than the embedded Erlang SSL offers. A `Req.get(..., connect_options: [transport_opts: [versions: [:"tlsv1.3"]]])` on those specific hosts may fix them.

### 9.3 Observed LV diff cascade on mount
From the broader server log stream (seen via live-reload teeing), every LV mount also triggers:
- Multiplier recalculation (BUX earnings depend on on-chain state)
- Ad rotation decision (one of `dark_gradient`, `split_card`, `portrait`, etc.)
- `PriceTracker.get_price("SOL")` hit (GenServer call — cheap, but it's on every page)
- Hub logo cache touches (local ETS)

None of those are hot, but together they form the 3-5 mount-time `update` pattern.

---

## 10. Admin pages (not in user hot path, but worth flagging)

- `lib/blockster_v2_web/live/admin_live.ex:9` — `Accounts.list_users()` on mount (and re-runs on every filter event at lines 59, 79, 128). Full-table scan of `users` including all 1000 bots. Currently this probably hits ~5 MB of JSON on every mount. Pagination needed.
- `lib/blockster_v2_web/live/posts_admin_live.ex:12` and `campaigns_admin_live.ex:12` — `Blog.list_posts()` on mount, and repeated on edit/filter events (lines 75, 93, 124, 152, 180, 208 of posts_admin_live).

Not touching user experience for now but these will fall over as the post/user tables grow.

---

## 11. High-fanout PubSub topics

- `lib/blockster_v2_web/live/post_live/category.ex:16` and `post_live/tag.ex:16` subscribe to `"post_bux:all"`.
- **Why it's a concern:** Every BUX-earn event on *any* post (fire-hose for a reader platform) is broadcast to every open category/tag page. Even a one-field change in the aggregate diff triggers a re-render across many sockets.
- **Recommendation:** Narrow to `"post_bux:#{post_id}"` and only subscribe per post that's actually rendered in the current view. Or, aggregate server-side into a per-category channel.

---

## 12. tiptap_renderer synchronous HTTP
- `lib/blockster_v2_web/live/post_live/tiptap_renderer.ex:206` — `Req.get(...)` call to Twitter oEmbed.
- **Status:** The Feb audit (`docs/performance_audit.md` C4) flagged and *removed* the Quill-format version of this, but it still lives here for TipTap. Worth reading the whole function — if this is only hit on render for tweets in a post body, the failure mode (Twitter slow) stalls LV rendering.
- **Recommendation:** Cache tweet embeds in Mnesia on publish, not on render. Fallback to `<a>` link on cache miss, fill in later.

---

## 13. Quick-win priority list (ordered)

1. **`/shop` hero image** — `Web Banner 3.png` is 697 KB. Add `?tr=w-1600,q-85,f-auto`. Expected: ~580 KB saved, `/shop` total → ~300 KB.
2. **BuxMinter triple-broadcast** — collapse to a single broadcast. Ten-line change in `bux_minter.ex:199-223`. Saves 2/3 of every balance-update render on `/play`, `/checkout`, `/cart`, `/wallet`, `/pool/*`, `/shop/:slug`.
3. **`/airdrop` 1-second timer** — bump to 15 s or move countdown to client. 60 → 4 renders/minute per viewer.
4. **widget-69 duplicate IDs** — unique id per viewport. Eliminates console error spam and morphdom fallbacks.
5. **EngagementTracker 2 s cadence** — raise to 10 s. 5× reduction in mount-to-settle traffic.
6. **`/play` commitment at mount** — gate behind first interaction. Stops SOL burn on drive-by visits.
7. **`/hub/:slug` double-transform bug** — fix the `prepare_product_for_display` call site. Currently every hub page 500s.
8. **TopicEngine guardrail** — skip when no authors seeded. Avoid Claude API billing on idle clusters.
9. **Stale `app-21f441de…js`** — delete from `priv/static/assets/js/`. Saves 4 MB in each Fly deploy image.
10. **Web3Auth modal code-split** — dynamic import so its React/i18next payload only downloads on click. Likely shaves 200-400 KB gzipped off the main bundle.

---

## 14. What's working well

- **TTFB consistently under 300 ms** in dev. Phoenix + Ecto + Mnesia cluster is healthy.
- **Initial HTML payloads are tight** — 70-249 KB decoded across every measured page, heavily compressed (13× ratio observed on `/hubs`).
- **`start_async` is used correctly** on every user-facing LV I inspected. No sync HTTP on the user-hot path (the Twitter oEmbed is the only exception, and it's conditional).
- **Image loading attributes look right** — 93 `loading="lazy"` on `/shop` with 12 eager for above-the-fold. That matches the CLAUDE.md rule.
- **Protocol is h2/h3** for ImageKit/Unsplash/fonts.gstatic. No HTTP/1.1 head-of-line blocking on imagery.
- **Fixed from the Feb audit are holding:** The `with_bux_earned` N+1 and cart N+1 are no longer visible in logs. `EventsComponent`'s `list_users` full scan is gone. Legacy Quill renderer is deleted.

---

## Appendix A — Raw measurement files

All on disk at `.playwright-mcp/perf/*.json`. Files captured:
`home-metrics.json`, `hubs-metrics.json`, `shop-metrics.json`, `product-detail-metrics.json`, `cart-metrics.json`, `checkout-metrics.json`, `play-metrics.json`, `pool-metrics.json`, `pool-sol-metrics.json`, `pool-bux-metrics.json`, `article-metrics.json`, `wallet-metrics.json`, `notifications-metrics.json`, `airdrop-metrics.json`, `member-metrics.json`.

Console traces and DOM snapshots from each navigation are in `.playwright-mcp/console-*.log` and `.playwright-mcp/page-*.yml`.

## Appendix B — Things I did *not* measure

- **Cold-cache production load** (I measured local dev with warm file cache). Prod will differ on image fetch times and `app.js` TTFB.
- **Server-side DB query plans.** No slow query log on in the dev `config/dev.exs`. Enabling `:telemetry` → LiveDashboard slow-query tracing for a day would reveal per-page Ecto times.
- **Actual coin-flip bet placement perf.** I intentionally skipped signing a real on-chain tx with the connected wallet to avoid burning SOL.
- **Checkout-to-paid round trip.** Stopped at `/checkout/:id` without completing SOL payment.
- **Real-device (mobile) timing.** Measurements above are desktop Chromium, local cluster.
- **Lighthouse a11y/SEO scores.** Scoped to performance only.
