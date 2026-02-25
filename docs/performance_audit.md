# Performance Audit Report

**Date**: 2026-02-24
**Scope**: Full codebase audit — database, LiveView, GenServers, external APIs, frontend assets

---

## CRITICAL (Fix immediately — causes hangs, crashes, or severe user impact)

### C1. `with_bux_earned` — N+1 Mnesia read on every post listing
- **File**: `lib/blockster_v2/blog.ex:1335-1349`
- **Impact**: Every post-listing call (homepage, hub page, news components) runs one `dirty_read` per post inside an `Enum.map` loop. 20 posts = 20 serial Mnesia reads. This runs on nearly every page
- **Fix**: Add `get_posts_total_distributed_batch(post_ids)` to EngagementTracker that reads all post BUX data in one pass; replace the per-post loop with a single batch call

### C2. Extra `get_hub` DB query inside every `list_published_posts_by_hub`
- **File**: `lib/blockster_v2/blog.ex:168-170, 235-237`
- **Impact**: `list_published_posts_by_hub` calls `get_hub(hub_id)` to fetch `tag_name`, adding a wasted DB query. Hub page calls this 3x in mount = 3 unnecessary `get_hub` queries when the hub struct is already loaded
- **Fix**: Accept optional `tag_name` parameter or pass the already-loaded hub struct

### C3. Blocking X API calls in `share_to_x` handle_event
- **Files**: `post_live/show.ex:1062-1245`, `x_api_client.ex:265-295`
- **Impact**: User clicks "Share to X" → LiveView freezes for up to 60s while two sequential X API calls (retweet + like) + BUX mint complete synchronously
- **Fix**: Wrap in `start_async/3`, show "Sharing..." loading state, handle result in `handle_async`; parallelize the two independent X API calls with `Task.async`

### C4. Blocking HTTP in legacy Quill renderer (render path)
- **Files**: `post_live/show.ex:1699-1724`, `tiptap_renderer.ex:159-167`
- **Impact**: Old Quill-format posts with tweet embeds make a synchronous `Req.get` to Twitter oEmbed API during render — no timeout configured. Hangs the LiveView if Twitter is slow
- **Fix**: Remove dead code entirely (TipTap renderer already handles tweets via client-side widget.js). Also remove unused `fetch_tweet_html/1` in tiptap_renderer.ex

### C5. EventsComponent loads ALL users on every render
- **File**: `post_live/events_component.ex:15`
- **Impact**: `Accounts.list_users()` fires a full-table scan of the entire users table (1000+ bots + real users) on every component update, on every post page
- **Fix**: Pass attendees from parent assigns or remove this query entirely

### C6. Cart N+1 — 15-20 individual preload queries per checkout
- **File**: `lib/blockster_v2/cart.ex` (lines ~93, ~124, ~160, ~189)
- **Impact**: `validate_cart_items`, `calculate_totals`, `item_subtotal`, `clamp_bux_for_item` each call `Repo.preload(item.product, :variants)` per item inside loops. 5-item cart = 15-20 extra DB queries
- **Fix**: Preload all products+variants in a single query before entering these functions

### C7. Hub notification sends N individual INSERTs
- **File**: `lib/blockster_v2/blog.ex:763-787`
- **Impact**: `notify_hub_followers_of_new_post` does one `INSERT` per follower. A hub with 1,000 followers = 1,000 sequential INSERTs
- **Fix**: Use `Repo.insert_all/3` for batch insert

---

## HIGH (Fix soon — degrades performance noticeably)

### ~~H1. SortedPostsCache~~ — ALREADY DISABLED (not in supervision tree, dead code)

### H2. PostBuxPoolWriter — single global bottleneck for all rewards
- **File**: `post_bux_pool_writer.ex:44-65`
- **Impact**: Every BUX reward (bots + real users) goes through one global GenServer. 300+ bot mints + real reads funnel through a single process
- **Fix**: Use Mnesia transactions with optimistic concurrency, or per-post GenServers

### H3. EngagementTracker — 3-4 full Mnesia table scans per member profile
- **File**: `engagement_tracker.ex:331, 360, 386, 725`
- **Impact**: `get_user_read_post_ids`, `get_user_post_rewards_map`, `get_all_user_post_rewards` all use `dirty_match_object` scanning entire tables. Heavy reader = multiple full scans per page load
- **Fix**: Add secondary Mnesia index on `user_id` in `user_post_rewards` and `user_video_engagement` tables; use `dirty_index_read`

### H4. BotCoordinator — unbounded message queue flooding
- **File**: `bot_coordinator.ex:175-177`
- **Impact**: Each post publish schedules 300 `Process.send_after` messages. Backfill of 7 posts = 2,100+ messages immediately, each spawning 2 more. Single GenServer processes all sequentially
- **Fix**: Spawn individual Task processes per bot session; coordinator only manages mint queue

### H5. MemberLive.Show — 13+ synchronous queries in handle_params
- **File**: `member_live/show.ex:29-163`
- **Impact**: Loads all tabs' data upfront (referrals, following, wallet, activity) even when user only views one tab
- **Fix**: Lazy-load tab data on tab switch; defer non-visible tab queries

### H6. HubLive.Show — 6+ synchronous DB calls in mount, no connected? guard
- **File**: `hub_live/show.ex:13-65`
- **Impact**: All queries run on both static and connected mounts (double execution). Personalized queries (`user_follows_hub?`, `get_hub_follower_count`) don't need static render
- **Fix**: Guard personalized queries behind `connected?(socket)`

### H7. get_hub_by_slug_with_associations preloads ALL posts + events
- **File**: `lib/blockster_v2/blog.ex:1004-1008`
- **Impact**: `Repo.preload([:followers, :posts, :events])` loads unbounded data on every hub page
- **Fix**: Remove `:posts` and `:events` from preload — they're loaded separately with proper filtering

### H8. Admin list_posts/0 — no LIMIT, reloaded on every action
- **File**: `lib/blockster_v2/blog.ex:300-305`, `posts_admin_live.ex:75,93,124,152,180,208`
- **Impact**: Loads ALL posts with full preloads on mount and after every admin action (6x handle_events call it)
- **Fix**: Add pagination; only reload affected posts on mutations

### H9. get_user_followed_hubs_enriched — N+1 count query per hub
- **File**: `lib/blockster_v2/blog.ex:1286-1289`
- **Impact**: One `count_hub_posts` DB query per followed hub. 20 hubs = 20 queries
- **Fix**: Single query with `GROUP BY hub_id` subquery

### H10. ShopLive.Show — redundant DB query on every add_to_cart
- **File**: `shop_live/show.ex:377-397`
- **Impact**: `find_variant_id/5` re-fetches product + variants from DB even though they're already in socket assigns
- **Fix**: Use `socket.assigns.product.variants` instead of re-querying

### H11. Hub/event images — no ImageKit transforms, no lazy loading
- **Files**: `hub_live/show.html.heex:21`, `hub_live/index.html.heex:60`, `event_live/show.html.heex:93,333`
- **Impact**: Hub logos and event images served at full resolution with no optimization; hub grid loads all images eagerly
- **Fix**: Wrap in `ImageKit.w200_h200()` or similar; add `loading="lazy"` to below-fold images

### H12. testPaymaster() in production JS bundle
- **File**: `assets/js/home_hooks.js:1144-1461`
- **Impact**: Debug function that monkey-patches `window.fetch` globally exists in production bundle. If accidentally triggered, intercepts all network requests
- **Fix**: Remove or gate behind `process.env.NODE_ENV === "development"`

### H13. PostLive.Show handle_params — duplicate work on double mount
- **File**: `post_live/show.ex:60-228`
- **Impact**: Multiple DB/Mnesia reads run on both static and connected mounts. Redundant `get_user_multipliers` call
- **Fix**: Deduplicate; defer `get_suggested_posts` and `get_sidebar_products` to connected mount only

---

## MEDIUM (Fix in next sprint — affects scalability or code quality)

### M1. BotCoordinator — per-mint DB query ignores in-memory cache
- **File**: `bot_coordinator.ex:591-602`
- **Impact**: `process_mint_job` runs in spawned Task, can't access GenServer state, queries DB per mint. Hundreds of unnecessary queries
- **Fix**: Pass `wallet_address` into mint job struct when enqueuing

### M2. BuxBooster Mnesia — full table scans without indexes
- **Files**: `bux_booster_stats.ex:72,117,132`, `bux_booster_bet_settler.ex:81`, `bux_booster_onchain.ex:482`
- **Impact**: Player lookup by wallet, unsettled bets scan (every 60s), nonce calculation — all full table scans
- **Fix**: Add secondary Mnesia indexes on `wallet_address`, `status`, `user_id`

### M3. ReferralRewardPoller — two sequential blocking RPC calls per second
- **File**: `referral_reward_poller.ex:160-163`
- **Impact**: Two independent `eth_getLogs` calls run sequentially in handle_info. Blocks GenServer for duration
- **Fix**: Parallelize with `Task.async`; offload to background task

### M4. WalletMultiplierRefresher — sequential HTTP for all users in handle_call
- **File**: `wallet_multiplier_refresher.ex:123-147`
- **Impact**: Processes every connected-wallet user sequentially, each making external HTTP calls. Can block for minutes
- **Fix**: Use `Task.async_stream` with concurrency limit; move to handle_info

### M5. ContentQueue — Claude API call blocks GenServer
- **File**: `content_queue.ex:85-93`
- **Impact**: `force_publish_next` handle_call runs 30-60s AI call, blocking the scheduler tick
- **Fix**: Reply immediately, publish asynchronously

### M6. Missing HTTP timeouts on multiple X API calls
- **Files**: `x_api_client.ex:141,372,415,443,466,495`
- **Impact**: 6 `Req.get` calls without timeout configuration. Default timeout may cause hangs
- **Fix**: Apply `receive_timeout: 30_000` to all calls (the helper `req_options/0` exists but isn't used everywhere)

### M7. TwilioClient — HTTPoison with no explicit timeout
- **File**: `twilio_client.ex:31,64,92`
- **Impact**: Three HTTP calls with default timeouts
- **Fix**: Add explicit timeout options

### M8. MemberLive — blocking HTTP in handle_info for balance refresh
- **File**: `member_live/show.ex:708-732`
- **Impact**: `BuxMinter.get_aggregated_balances` called synchronously in handle_info
- **Fix**: Wrap in `start_async`

### M9. IO.inspect/IO.puts in production code
- **Files**: `post_live/show.ex:1258-1539`, `post_live/form_component.ex:399,443,449,489,522,526,531`
- **Impact**: Pollutes stdout, `IO.inspect(limit: :infinity)` on large data is expensive
- **Fix**: Remove or replace with `Logger.debug`

### M10. 289 console.log calls in production JS bundle
- **File**: `assets/js/home_hooks.js` (165), various others
- **Impact**: Browser console pollution, marginal performance cost
- **Fix**: Add `--drop:console` to esbuild production config

### M11. Engagement tracker sends updates every 2 seconds
- **File**: `assets/js/engagement_tracker.js:92`
- **Impact**: Every reader on every article sends a WebSocket message every 2s
- **Fix**: Increase to 5-10s or only send on meaningful state changes

### M12. Swiper CSS + BuxBooster ABI bundled on all pages
- **Files**: `assets/js/app.js:21-27,50`
- **Impact**: Swiper CSS and BuxBoosterGame ABI JSON loaded on every page regardless of need
- **Fix**: Dynamic `import()` for play page hook; scope Swiper CSS

### M13. Thirdweb SDK imported unconditionally
- **File**: `assets/js/home_hooks.js`
- **Impact**: Large library loaded on all pages even without wallet interaction
- **Fix**: Dynamic import on pages that need it

### M14. Nav hooks leak window event listeners
- **File**: `assets/js/app.js:183,238,283`
- **Impact**: `MobileNavHighlight`, `DesktopNavHighlight`, `CategoryNavHighlight` add `phx:navigate` listeners without cleanup in `destroyed()`
- **Fix**: Add `destroyed()` callback to remove listeners

### M15. RANDOM() for random posts/products
- **Files**: `lib/blockster_v2/blog.ex:282`, `lib/blockster_v2/shop.ex:100-118`
- **Impact**: `ORDER BY RANDOM()` forces full table scan + sort
- **Fix**: Use `TABLESAMPLE` or pre-cached random selection

### M16. Missing database indexes
- `posts.video_id` — hub video tab filter
- `notifications.dismissed_at` — every notification list query
- `notifications.metadata` (GIN) — dedup check on every notification create
- **Fix**: Add migration with these indexes

---

## LOW (Backlog — minor or infrequent impact)

### L1. PriceTracker — no retry on CoinGecko, PubSub storm on price tick
- **File**: `price_tracker.ex:270,287`
- **Fix**: Add `retry: :transient`; stagger subscriber re-renders

### L2. ImageFinder — no connect_options timeout
- **File**: `image_finder.ex:432`
- **Fix**: Add `connect_options: [timeout: 10_000]`

### L3. Event search missing phx-debounce
- **File**: `event_live/index.html.heex:136`
- **Fix**: Add `phx-debounce="300"`

### L4. No preconnect for platform.twitter.com
- **File**: `root.html.heex`
- **Fix**: Add `<link rel="preconnect" href="https://platform.twitter.com">`

### L5. CSS animations missing will-change hints
- **Files**: `post_live/show.html.heex:204`, `shop_live/show.html.heex:44-45`
- **Fix**: Add `will-change: transform` to animated elements

### L6. Notifications list_notification_activities — no LIMIT
- **File**: `notifications.ex:59-66`
- **Fix**: Add `limit: 50` or pagination

### L7. list_events/0 — unbounded with full preloads
- **File**: `events.ex:21-24`
- **Fix**: Add limit and filter by upcoming

### L8. Sync token refresh on share modal open
- **File**: `post_live/show.ex:1000-1025`
- **Fix**: Could use `start_async` but low frequency

---

## What's Already Done Well

- **BuxMinter HTTP**: Proper timeouts, retry with exponential backoff, inet backend
- **ClaudeClient/AIManager**: 90-120s timeouts, retry on rate limits
- **FeedPoller**: `Task.async_stream` with per-feed timeout + `:kill_task`
- **ImageFinder**: `Task.async_stream` with 30s per-image timeout
- **Helio/FingerprintVerifier**: Proper timeouts on all calls
- **TelegramNotifier**: 30s receive_timeout
- **Notification/BuxBalance hooks**: Correct `connected?(socket)` guards for PubSub
- **Search inputs**: Most use `phx-debounce="300"` correctly
- **Root layout**: Preconnect hints for ImageKit, Google Fonts already present
- **PostsOneComponent**: Correct `fetchpriority="high"` on hero image
- **ShopLive.Show**: Correct per-index fetchpriority on product images

---

## Recommended Priority Order

1. **C1-C7**: Fix all Critical items (blocking UX, N+1 explosions)
2. **H1-H2**: SortedPostsCache + PostBuxPoolWriter bottlenecks (architectural)
3. **H3-H6**: Mnesia indexes + LiveView mount optimizations (quick wins)
4. **H7-H10**: Unnecessary preloads + redundant queries (straightforward fixes)
5. **M16**: Missing DB indexes (single migration, high impact)
6. **M1-M5**: GenServer/background process improvements
7. **M6-M14**: HTTP timeouts + frontend bundle optimization
8. **L1-L8**: Low priority backlog items
