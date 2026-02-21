# Notification System Wiring + AI Manager — Implementation Plan

## Context

The notification system has 808 passing tests and solid backend logic, but **nothing is connected to real user actions**. `UserEvents.track()` is never called from production code. `TriggerEngine.evaluate_triggers()` is never invoked. Welcome emails don't fire on signup. Hub post emails don't send. Price alerts aren't disconnected from PriceTracker. Re-engagement emails promise fake "2x BUX". The conversion funnel only updates Fridays. The referral notification engine sits unused alongside a working Referrals system.

This plan wires everything up, replaces fake copy, builds an **AI Manager (Opus 4.6)** as the autonomous controller of the entire notification system, upgrades the referral system (both parties rewarded, bigger amounts, AI-adjustable), and moves the referral UI into the notifications system.

---

## How the System Works After Implementation

### Every Tracked User Action → What Happens

| # | Event | Where Tracked | What Fires |
|---|-------|--------------|------------|
| 1 | **User signs up** | `auth_controller.ex` | Welcome series enqueued (4 emails: day 0,3,5,7). Preferences created. Referee gets 250 BUX if referred. Referrer gets 500 BUX. `session_start` + `daily_login` tracked. |
| 2 | **User logs in** | `auth_controller.ex` | `daily_login` tracked → Trigger 7 checks dormancy (5-14 days away → "welcome back" notification). |
| 3 | **Article viewed** | `post_live/show.ex` (connected only) | `article_view` tracked. No notification fires (just analytics). |
| 4 | **Article read complete** | `post_live/show.ex` after `record_read` | `article_read_complete` tracked → Trigger 3 (reading streak milestones: 3,7,14,30 days), Trigger 4 (hub recommendation if 3+ articles in same category), Funnel 1B (5th article → gaming nudge). |
| 5 | **Article shared on X** | `post_live/show.ex` after share reward | `article_share` tracked → Trigger 8 (referral opportunity if propensity > 0.6). |
| 6 | **Hub followed** | `hub_live/show.ex` + `blog.ex` | `hub_subscribe` tracked. No notification (the follow IS the action). |
| 7 | **Hub unfollowed** | `hub_live/show.ex` + `blog.ex` | `hub_unsubscribe` tracked. No notification. |
| 8 | **Hub post published** | `blog.ex` `notify_hub_followers_of_new_post` | Followers with `notify_new_posts=true` + `in_app_notifications=true` get bell notification. Those with `email_notifications=true` also get email via `HubPostNotificationWorker`. Non-hub posts: no blast (surfaces in daily digest). |
| 9 | **Product viewed** | `shop_live/show.ex` (connected only) | `product_view` tracked. No notification (just analytics for cart abandonment). |
| 10 | **Product added to cart** | `shop_live/show.ex` after cart add | `product_add_to_cart` tracked. No immediate notification (used by cart abandonment trigger later). |
| 11 | **Checkout started** | `checkout_live/index.ex` on review step | `checkout_start` tracked. No notification. |
| 12 | **Purchase complete** | `checkout_live/index.ex` + `orders.ex` | `purchase_complete` tracked → Trigger 6 (first purchase → thank you + referral prompt), ProfileRecalcWorker enqueued, conversion stage updated if applicable. If buyer has referrer + first order → referrer notified. |
| 13 | **BUX game played** | `bux_booster_live.ex` after bet confirmed | `game_played` tracked with `{token: "BUX", result, multiplier}` → Funnel 1A (BUX balance ≥500 → booster invite), Funnel 2A (5th BUX game → ROGUE discovery), Funnel 2B (3+ loss streak → ROGUE offer), Funnel 4A (3+ win streak → celebration), Funnel 4B (10x+ multiplier → big win), VIP tier check. Conversion stage: first BUX game → `bux_player`. ProfileRecalcWorker enqueued. |
| 14 | **ROGUE game played** | `bux_booster_live.ex` after bet confirmed | Same as #13 but with `{token: "ROGUE"}` → Funnel 3A (first ROGUE game → purchase nudge). Conversion stage: first ROGUE game → `rogue_curious`. |
| 15 | **BUX earned (reading reward)** | `post_live/show.ex` with `new_balance` | `bux_earned` tracked → Trigger 2 (BUX milestones: 1K, 5K, 10K, 25K, 50K, 100K), Trigger 8 (referral opportunity if high propensity), Funnel 1A (balance ≥500 → gaming nudge). |
| 16 | **Session ends** | Browser `beforeunload` or timeout | `session_end` tracked → Trigger 1 (cart abandonment if items in cart ≥2 hours). |
| 17 | **ROGUE price moves ≥10%** | `PriceTracker` broadcast → `EventProcessor` | `PriceAlertEngine.evaluate_price_change/2` fires → users with `email_reward_alerts=true` get price alert email. |
| 18 | **Referral friend signs up** | `referrals.ex` `process_signup_referral` | Referrer gets 500 BUX (minted on-chain) + in-app notification. Referee gets 250 BUX (minted on-chain) + welcome email mentions bonus. |
| 19 | **Referral friend verifies phone** | `referrals.ex` `process_phone_verification_reward` | Referrer gets 100 BUX + notification. |
| 20 | **Referral friend plays BUX game** | On-chain: `ReferralRewardPoller` detects `ReferralRewardPaid` event from BuxBoosterGame contract | Referrer earns 1% of friend's losing bet (auto, on-chain). Earning recorded in Mnesia. Real-time PubSub update to referrer's UI. |
| 21 | **Referral friend deposits/plays ROGUE** | On-chain: `ReferralRewardPoller` detects `ReferralRewardPaid` event from ROGUEBankroll contract | Referrer earns 0.2% of friend's losing bet (auto, on-chain). Same Mnesia + PubSub flow. |

### How On-Chain Referral Payouts Work

1. When a referred user plays BUX Booster or ROGUE games, the smart contracts (BuxBoosterGame / ROGUEBankroll) automatically calculate the referrer's cut (1% BUX / 0.2% ROGUE of losing bets)
2. The contract emits a `ReferralRewardPaid(commitmentHash, referrer, player, token, amount)` event
3. `ReferralRewardPoller` polls Rogue Chain RPC every 1 second, detects these events
4. Deduplicates by `commitment_hash`, records earning in Mnesia `:referral_earnings` table
5. Syncs balances via `BuxMinter.sync_user_balances_async` — the tokens are already on-chain, just updating the UI
6. Broadcasts real-time update via PubSub `"referral:#{referrer_id}"`

### How Signup BUX Rewards Are Minted

1. `Referrals.process_signup_referral/2` calls `BuxMinter.mint_bux(wallet, amount, user_id, nil, :signup)`
2. `BuxMinter` makes HTTP POST to `https://bux-minter.fly.dev/mint` with `{walletAddress, amount, userId}`
3. The minter service (Node.js + ethers.js) sends an on-chain transaction on Rogue Chain
4. Returns `transactionHash` — updates Mnesia balance tables
5. Same flow for referee reward (new: 250 BUX minted to referee's smart wallet)

### Daily Digest & Preference Checking

- **Daily Digest Worker**: Fully hooked up. Runs 9 AM UTC daily. Checks `prefs.email_enabled && prefs.email_daily_digest` before sending. Uses `RateLimiter.can_send?` for rate limits + quiet hours. Selects 5 articles from followed hubs + trending fallback.
- **Re-engagement Worker**: Fully hooked up. Runs 11 AM UTC daily. Checks `prefs.email_enabled && prefs.email_re_engagement`. Targets users inactive for [3, 7, 14, 30] days.
- **Welcome Series**: Hooked up but does NOT check preferences (transactional — will add check in Phase W3).
- **All workers**: Go through 4-step rate limiting: (1) channel enabled? (2) type opted-in? (3) daily/weekly cap? (4) quiet hours?

---

## The AI Manager

### Architecture

The AI Manager is an **Opus 4.6-powered autonomous controller** of the entire notification system. It's not just a chatbot — it owns the system configuration and can modify any aspect of how notifications work.

**Core Concept**: A `SystemConfig` PostgreSQL table stores all configurable parameters as JSON. The AI Manager reads and writes this config via Claude tool_use. The EventProcessor and all workers read from SystemConfig (cached in ETS with 5-minute TTL) to decide behavior. When the AI Manager changes config, the cache invalidates and the system immediately adapts.

### What the AI Manager Controls

| Config Area | Examples | How It's Applied |
|-------------|----------|-----------------|
| **Referral Amounts** | `referrer_signup_bux: 500`, `referee_signup_bux: 250`, `phone_verify_bux: 100` | Read by `Referrals.process_signup_referral/2` at mint time |
| **Trigger Thresholds** | `bux_milestones: [1000, 5000, ...]`, `reading_streak_days: [3, 7, ...]`, `cart_abandon_hours: 2` | Read by `TriggerEngine.evaluate_triggers/3` |
| **Notification Copy** | Per-type title/body templates with `{variable}` placeholders | Read by `CopyWriter` (AI Manager can override any template) |
| **Conversion Funnel** | `bux_balance_gaming_nudge: 500`, `articles_before_nudge: 5`, `games_before_rogue_nudge: 5` | Read by `ConversionFunnelEngine` |
| **Rate Limits** | `default_max_emails_per_day: 3`, `global_max_per_hour: 8` | Read by `RateLimiter` as system-wide defaults |
| **Event Responses** | Custom rules: `"When user reads 10 articles in one day, send congratulations"` | Stored as JSON rules, evaluated by EventProcessor |
| **Campaign Defaults** | Default audience, channels, timing preferences | Read by campaign creation flow |

### AI Manager Tools (Claude tool_use)

The AI Manager has these tools available when processing admin messages:

1. **`get_system_config`** — Read current config (all or by section)
2. **`update_system_config`** — Modify any config value. Validates ranges, invalidates ETS cache
3. **`create_campaign`** — Create + optionally send a campaign. Calls `Notifications.create_campaign/1` + `PromoEmailWorker.enqueue_campaign/1`
4. **`get_system_stats`** — Aggregate metrics: total notifications sent (24h/7d/30d), open rates, click rates, active users, conversion funnel distribution, referral stats
5. **`get_user_profile`** — Look up a specific user's notification profile, preferences, conversion stage, engagement tier
6. **`adjust_referral_rewards`** — Change referrer/referee BUX amounts. Updates SystemConfig + logs the change
7. **`modify_trigger`** — Change trigger conditions (thresholds, enabled/disabled, copy). Updates SystemConfig
8. **`add_custom_rule`** — Add a new event → response mapping (stored in SystemConfig as JSON, evaluated by EventProcessor)
9. **`remove_custom_rule`** — Remove a custom rule
10. **`list_campaigns`** — Recent campaigns with stats
11. **`analyze_performance`** — AI-generated analysis of recent campaign/notification performance
12. **`get_referral_stats`** — System-wide referral metrics
13. **`send_test_notification`** — Send a test notification/email to a specific user

### Admin ↔ AI Manager Interface

**Route**: `/admin/ai-manager` (new LiveView page, added to admin dropdown)

**UI**: Full-page chat interface (not a sidebar):
- Left: conversation history (scrollable, persisted in assigns per-session)
- Starter prompts: "How is the notification system performing?", "Increase referral rewards to 1000 BUX", "Create a flash sale campaign", "What are the most engaged users doing?", "Disable cart abandonment emails", "Add a rule: congratulate users on their 100th article"
- When AI Manager executes a tool, the result is shown inline (e.g., "Updated referral rewards: referrer 500→1000 BUX, referee 250→500 BUX")
- Admin can also give broad directives: "Optimize the system for more ROGUE conversions" → AI Manager analyzes funnel, adjusts thresholds, updates copy

### Autonomous AI Manager Behavior

The AI Manager also runs **periodic autonomous reviews** via Oban worker:

- **Daily Review** (6 AM UTC): Fetches system stats for last 24h. If any metric is anomalous (open rate drops >20%, spike in unsubscribes, notification volume unusually high/low), generates a report and creates an in-app notification for admin. Can auto-adjust if the issue is clear (e.g., too many notifications → tighten rate limits).
- **Weekly Optimization** (Monday 7 AM UTC): Analyzes full week. Suggests referral amount adjustments based on conversion rates. Suggests trigger threshold changes. Logs recommendations to admin chat history.

The AI Manager is **conservative by default** — it won't make dramatic changes without admin approval. For autonomous changes, it limits to: ±20% on numeric values, enabling/disabling individual triggers, adjusting copy. Major changes (new event types, large reward changes, campaign sends) require admin confirmation via the chat.

### Cost Estimate

- **AI Manager chat**: ~$0.03-0.08 per admin message (Opus 4.6, ~2000 input tokens + system prompt, ~500 output)
- **Daily autonomous review**: ~$0.05/day ($1.50/month)
- **Weekly optimization**: ~$0.10/week ($0.40/month)
- **Total estimated**: ~$2-5/month for autonomous operation + admin usage

---

## Referral System Changes

### Current State
- Referrer gets 100 BUX on signup, 100 BUX on phone verify
- Referee gets nothing
- UI is on member page Refer tab only
- On-chain tracking (1% BUX / 0.2% ROGUE of losing bets) works via ReferralRewardPoller

### New State
- **Referrer**: 500 BUX on signup (up from 100), 100 BUX on phone verify (unchanged)
- **Referee**: 250 BUX on signup (NEW — minted via same BuxMinter flow)
- **All amounts editable** by AI Manager via `adjust_referral_rewards` tool → updates SystemConfig
- **On-chain tracking unchanged** — contract percentages (1% BUX / 0.2% ROGUE) are set on-chain, not adjustable by AI Manager (would require contract upgrade)
- **Referral UI**: New page at `/notifications/referrals` with full dashboard:
  - Referral link + copy button + share buttons
  - Stats cards: Total Referrals, Verified, BUX Earned, ROGUE Earned
  - Earnings table with infinite scroll (same data as member page)
  - Visual progress showing referral tier/badges
  - "Invite friends" CTA with personalized message
- **Member page Refer tab**: Keep but simplify — show referral link + "View full dashboard" link to `/notifications/referrals`

### How Referee Gets BUX

In `Referrals.process_signup_referral/2`, after minting referrer's reward, also:
```elixir
referee_amount = SystemConfig.get(:referee_signup_bux, 250)
BuxMinter.mint_bux(new_user.smart_wallet_address, referee_amount, new_user.id, nil, :signup)
```
The welcome email mentions: "You received 250 BUX as a signup bonus from your friend's referral!"

---

## Implementation Phases

### Phase W1: SystemConfig + Event Pipeline Foundation (~20 tests)

**Goal**: Create SystemConfig table, build EventProcessor GenServer that routes events to triggers.

#### Create
- **`priv/repo/migrations/xxx_create_system_config.exs`** — Single-row table: `id`, `config` (jsonb, default `{}`), `updated_at`, `updated_by` (string, "ai_manager" or "admin" or "system")
- **`lib/blockster_v2/notifications/system_config.ex`** — Module with ETS-cached reads:
  - `get(key, default)` — reads from ETS cache, falls back to DB
  - `put(key, value, updated_by)` — writes to DB, invalidates ETS cache
  - `get_all()` — full config map
  - `seed_defaults()` — called on app start, populates defaults if empty
  - Default config includes all referral amounts, trigger thresholds, rate limits, copy templates
- **`lib/blockster_v2/notifications/event_processor.ex`** — GenServer (GlobalSingleton):
  - Subscribes to `"user_events"` and `"token_prices"` PubSub topics
  - On `{:user_event, user_id, event_type, metadata}`: dispatches to `TriggerEngine.evaluate_triggers/3` + `ConversionFunnelEngine.evaluate_funnel_triggers/3` in a Task. For `game_played`/`purchase_complete`, also enqueues `ProfileRecalcWorker` and immediately updates conversion stage
  - On `{:token_prices_updated, prices}`: compares ROGUE price vs stored previous, fires price alerts if ≥10% change
  - Evaluates custom rules from SystemConfig

#### Modify
- **`lib/blockster_v2/user_events.ex`** — After successful `Repo.insert` in `track/3` and `track_sync/3`, broadcast `{:user_event, user_id, event_type, metadata}` on PubSub topic `"user_events"`
- **`lib/blockster_v2/application.ex`** — Add `EventProcessor` to supervision tree (after Oban)

### Phase W2: Wire UserEvents.track() into Production Code (~22 tests)

**Goal**: Add tracking calls to all production action points.

#### Modify (add `UserEvents.track` calls)
- **`lib/blockster_v2_web/live/post_live/show.ex`** — `article_view` on mount (connected only), `article_read_complete` after `record_read`, `article_share` after X share reward
- **`lib/blockster_v2_web/live/shop_live/show.ex`** — `product_view` on mount (connected only), `product_add_to_cart` after cart add
- **`lib/blockster_v2_web/live/checkout_live/index.ex`** — `checkout_start` on review step, `purchase_complete` after order completion
- **`lib/blockster_v2_web/live/hub_live/show.ex`** — `hub_view` on mount (connected only), `hub_subscribe`/`hub_unsubscribe` after toggle_follow
- **`lib/blockster_v2_web/live/bux_booster_live.ex`** — `game_played` after bet confirmed with `%{token: token, result: result, multiplier: multiplier}`
- **`lib/blockster_v2/blog.ex`** — `hub_subscribe`/`hub_unsubscribe` in `follow_hub/2` and `unfollow_hub/2`
- **`lib/blockster_v2/orders.ex`** — `purchase_complete` in `process_paid_order/1`
- **`lib/blockster_v2_web/controllers/auth_controller.ex`** — `daily_login` on every auth, `session_start` on new user signup

Pattern: All calls use fire-and-forget `UserEvents.track/3`. In LiveViews, only inside `if connected?(socket)` to avoid double-mount.

### Phase W3: Welcome Series + Hub Post Email Wiring (~15 tests)

**Goal**: Trigger welcome emails on signup, send hub post emails respecting preferences.

#### Modify
- **`lib/blockster_v2/accounts.ex`** — In `create_user_from_email/1` and `create_user_from_wallet/1`, after `Notifications.create_preferences(user.id)`, call `WelcomeSeriesWorker.enqueue_series(user.id)`
- **`lib/blockster_v2/blog.ex`** — In `notify_hub_followers_of_new_post/1`: use `get_hub_followers_with_preferences/1`, filter by `in_app_notifications + notify_new_posts` for bell, `email_notifications + notify_new_posts` for email via `HubPostNotificationWorker`
- **`lib/blockster_v2/workers/welcome_series_worker.ex`** — Day 0: "Welcome to Blockster!" (no username). Add preference check. If referred, mention signup bonus in welcome email.

### Phase W4: Referral Upgrade + Re-engagement Fix (~20 tests)

**Goal**: Referee gets BUX, bigger amounts, amounts read from SystemConfig, honest re-engagement copy.

#### Modify
- **`lib/blockster_v2/referrals.ex`** — In `process_signup_referral/2`:
  - Read `referrer_amount = SystemConfig.get(:referrer_signup_bux, 500)` and `referee_amount = SystemConfig.get(:referee_signup_bux, 250)`
  - Mint `referrer_amount` to referrer (was hardcoded 100)
  - **NEW**: Mint `referee_amount` to referee's smart wallet
  - Call `ReferralEngine.notify_referral_signup(referrer_id, ...)` for referrer notification
  - Create in-app notification for referee: "You received {amount} BUX as a signup bonus!"
- **`lib/blockster_v2/referrals.ex`** — In `process_phone_verification_reward/2`:
  - Read `phone_verify_amount = SystemConfig.get(:phone_verify_bux, 100)`
- **`lib/blockster_v2/notifications/referral_engine.ex`** — Update reward amounts to read from SystemConfig
- **`lib/blockster_v2/workers/re_engagement_worker.ex`** — Replace fake "2x BUX" with honest copy: "Your favorite hubs have new content — pick up where you left off!"
- **`lib/blockster_v2/notifications/email_builder.ex`** — Update `re_engagement/4`: remove `special_offer` lime banner, replace with "Your hubs miss you" personalized message

### Phase W5: AI Manager Core (~25 tests)

**Goal**: Build the AI Manager module with Opus 4.6 tool_use, all 13 tools, and autonomous review workers.

#### Create
- **`lib/blockster_v2/notifications/ai_manager.ex`** — Stateless module:

  **`process_message(admin_message, conversation_history, admin_user_id)`**
  - Uses `BlocksterV2.ContentAutomation.ClaudeClient` with `model: "claude-opus-4-6"`
  - System prompt: "You are Blockster's AI Manager. You autonomously control the notification and engagement system. You can adjust referral rewards, modify triggers, create campaigns, analyze performance, and add custom event rules. Be decisive but conservative — don't make changes >20% without confirmation. Always explain what you're doing and why."
  - 13 tool schemas (listed above in Architecture section)
  - Multi-turn tool_use: if Claude returns a tool call, execute it, feed result back, let Claude continue
  - Returns `{:ok, response_text, tool_results}` or `{:error, reason}`

  **`autonomous_daily_review()`**
  - Called by `AIManagerReviewWorker` at 6 AM UTC
  - Builds a stats summary, sends to Claude with prompt: "Review these 24h metrics. Flag anomalies. Make conservative adjustments if needed. Generate a brief report."
  - If changes made, creates admin notification
  - Logs review to `ai_manager_logs` table

  **`autonomous_weekly_optimization()`**
  - Called Mondays 7 AM UTC
  - Full week analysis + optimization suggestions
  - More detailed than daily — can suggest referral amount changes, trigger adjustments

- **`lib/blockster_v2/workers/ai_manager_review_worker.ex`** — Oban cron worker for daily/weekly reviews
- **`priv/repo/migrations/xxx_create_ai_manager_logs.exs`** — Table: `id`, `review_type` (daily/weekly/admin_chat), `input_summary`, `output_summary`, `changes_made` (jsonb), `inserted_at`

### Phase W6: AI Manager Admin UI (~18 tests)

**Goal**: Full-page admin chat interface at `/admin/ai-manager`.

#### Create
- **`lib/blockster_v2_web/live/ai_manager_live/index.ex`** — LiveView:
  - Full-page chat UI (not sidebar)
  - Assigns: `chat_messages`, `chat_loading`, `system_config` (for sidebar display)
  - `handle_event("send_message")` → `start_async` with `AIManager.process_message/3`
  - `handle_async(:ai_response)` → append response, refresh config sidebar if changed
  - Sidebar shows current SystemConfig values (referral amounts, trigger states, etc.) — updates live when AI Manager changes them
  - Starter prompts as clickable chips
  - Tool execution results shown inline with styled cards (e.g., campaign created → green card with link)
  - Review log section at bottom showing recent autonomous actions

#### Modify
- **`lib/blockster_v2_web/router.ex`** — Add `/admin/ai-manager` route
- **`lib/blockster_v2_web/components/layouts.ex`** — Add "AI Manager" link to admin dropdown (after Notification Analytics)
- **`lib/blockster_v2_web/live/campaign_admin_live/index.ex`** — Add link to AI Manager: "Need help? Ask the AI Manager →"

### Phase W7: Referral Dashboard UI (~15 tests)

**Goal**: User-facing referral dashboard at `/notifications/referrals`.

#### Create
- **`lib/blockster_v2_web/live/notification_live/referrals.ex`** — LiveView:
  - Referral link + copy button + share buttons (X, WhatsApp, Telegram, email)
  - Stats cards: Total Referrals, Phone Verified, BUX Earned, ROGUE Earned (from Mnesia `:referral_stats`)
  - Current reward amounts: "You earn {referrer_amount} BUX per signup. Your friend gets {referee_amount} BUX too!" (reads from SystemConfig)
  - Earnings table with infinite scroll (pulls from Mnesia `:referral_earnings`, same as member page)
  - Achievement badges / tier visualization (from ReferralEngine)
  - PubSub subscription for real-time earnings updates

#### Modify
- **`lib/blockster_v2_web/router.ex`** — Add `/notifications/referrals` route
- **`lib/blockster_v2_web/live/notification_live/index.ex`** — Add "Referrals" tab/link
- **`lib/blockster_v2_web/live/member_live/show.html.heex`** — Simplify Refer tab: keep referral link + copy button, add "View full referral dashboard →" link to `/notifications/referrals`

### Phase W8: Conversion Funnel Continuous Updates (~14 tests)

**Goal**: Update conversion stage in real-time, not just Fridays.

#### Modify
- **`lib/blockster_v2/notifications/profile_engine.ex`** — Add `calculate_conversion_stage/1` that determines stage from profile fields. Call from `recalculate_profile/1` so it updates every 6h.
- **`lib/blockster_v2/notifications/event_processor.ex`** — For `game_played` events, directly update conversion stage when transition is obvious: first BUX game → `bux_player`, first ROGUE game → `rogue_curious`. For `purchase_complete`, check if first purchase.

### Phase W9: Integration Testing (~22 tests)

**Goal**: End-to-end tests proving the full pipeline works.

#### Create
- **`test/blockster_v2/notifications/integration_wiring_test.exs`** — Tests:
  - Signup → welcome series + preferences + referee BUX
  - Article read → reading streak trigger fires
  - Hub post → followers notified (respecting preferences)
  - Referral signup → both parties get BUX + notifications
  - Price alert → PriceTracker → EventProcessor → email
  - Re-engagement → honest copy (no fake 2x BUX)
  - AI Manager → admin message → config change → system adapts
  - Conversion funnel → first game → stage updates immediately
  - SystemConfig change → ETS invalidated → next event uses new config
  - Referral amount change via AI Manager → next signup uses new amount

---

## Summary

| Phase | Goal | Est. Tests |
|-------|------|------------|
| W1 | SystemConfig + EventProcessor GenServer | ~20 |
| W2 | Wire track() to all production actions | ~22 |
| W3 | Welcome series + hub post emails | ~15 |
| W4 | Referral upgrade + re-engagement fix | ~20 |
| W5 | AI Manager core (Opus 4.6 + 13 tools) | ~25 |
| W6 | AI Manager admin UI (full chat page) | ~18 |
| W7 | Referral dashboard UI | ~15 |
| W8 | Conversion funnel continuous updates | ~14 |
| W9 | End-to-end integration tests | ~22 |
| **Total** | | **~171** |

## Key Design Decisions

1. **SystemConfig as single source of truth** — All configurable values (referral amounts, trigger thresholds, copy templates, rate limits) stored in one PostgreSQL jsonb column, cached in ETS with 5-minute TTL. AI Manager writes here, everything else reads from here.
2. **AI Manager = Opus 4.6** everywhere (admin chat, daily review, weekly optimization). Cost: ~$2-5/month for autonomous operation.
3. **EventProcessor as GenServer** (not Oban per-event) — PubSub is async, non-blocking, avoids queue pressure. Dispatches to Tasks for actual work.
4. **Referee gets BUX** — Same `BuxMinter.mint_bux/5` flow as referrer. Both amounts configurable via SystemConfig.
5. **On-chain referral percentages NOT adjustable** — 1% BUX / 0.2% ROGUE are in smart contracts. Only signup/verify BUX amounts are adjustable.
6. **Referral UI**: New dashboard at `/notifications/referrals`, member page Refer tab simplified with link to dashboard.
7. **AI Manager is conservative by default** — ±20% autonomous changes max. Major changes require admin confirmation in chat.
8. **"2x BUX" removed entirely** — replaced with honest "your hubs miss you" messaging.
9. **Existing ClaudeClient reused** — Same `Config.anthropic_api_key()`, same retry logic, just different model and tools.

## Critical Files

| File | Purpose |
|------|---------|
| `lib/blockster_v2/notifications/system_config.ex` | NEW — Central config with ETS cache |
| `lib/blockster_v2/notifications/event_processor.ex` | NEW — PubSub → trigger dispatcher |
| `lib/blockster_v2/notifications/ai_manager.ex` | NEW — Opus 4.6 AI controller |
| `lib/blockster_v2/workers/ai_manager_review_worker.ex` | NEW — Autonomous daily/weekly reviews |
| `lib/blockster_v2_web/live/ai_manager_live/index.ex` | NEW — Admin chat UI |
| `lib/blockster_v2_web/live/notification_live/referrals.ex` | NEW — User referral dashboard |
| `lib/blockster_v2/user_events.ex` | MODIFY — Add PubSub broadcast |
| `lib/blockster_v2/referrals.ex` | MODIFY — Bigger amounts, referee reward, SystemConfig reads |
| `lib/blockster_v2/content_automation/claude_client.ex` | REUSE — Existing Claude API integration |
| `lib/blockster_v2/notifications/trigger_engine.ex` | REUSE — 8 triggers, already built |
| `lib/blockster_v2/notifications/conversion_funnel_engine.ex` | REUSE — 5-stage funnel, already built |

## Verification

After each phase:
```bash
mix test test/blockster_v2/notifications/ 2>&1 | tail -5
```
All 808 existing + new tests must pass with 0 failures.

After all phases, verify manually:
1. Sign up new user with referral link → both parties get BUX + notifications
2. Read 3 articles → reading streak notification fires
3. Publish hub post → followers get bell + email (respecting preferences)
4. Open `/admin/ai-manager` → ask "Increase referral rewards to 1000 BUX" → verify change applies
5. Open `/notifications/referrals` → see referral dashboard with stats
6. Check `/admin/ai-manager` next morning → autonomous review ran + logged
