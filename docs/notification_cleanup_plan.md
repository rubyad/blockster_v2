# Notification System Cleanup Plan

## Context

The notification system has ~31 modules with significant duplication and dead code. Key problems:
1. **NotificationHook** runs 2 sync DB queries on every page load (blocks rendering)
2. **`user_profiles` table** (100+ fields) duplicates data already in Mnesia (`user_betting_stats`, `user_bux_balances`, `referral_stats`, etc.)
3. **`Notifications.UserEvent` schema** is a duplicate alias for the same `user_events` table that `UserEvents` module already manages
4. **~6 dead code modules** (never called from anywhere)
5. **ProfileRecalcWorker** runs every 6h to recompute user_profiles from user_events — wasteful when Mnesia already has real-time data

## Approach

**Keep** `user_events` table (PostgreSQL) — it's a valuable append-only event log used by 14+ callsites. Keep `UserEvents.track()` and its query functions.

**Remove** `user_profiles` table — replace all reads with direct Mnesia lookups or inline computation from `user_events`. The triggers that read profile fields only need ~8 fields, most of which exist in Mnesia already or can be computed cheaply.

**Remove** dead code modules and the duplicate `Notifications.UserEvent` schema.

---

## Phase 1: Fix NotificationHook (async page loads)

**File:** `lib/blockster_v2_web/live/notification_hook.ex`

- Move `unread_count` and `list_recent_notifications` from sync mount to `start_async`
- Set initial assigns to `0` / `[]`, update via `handle_async`
- Only fetch when `connected?(socket)` (skip static render)

---

## Phase 2: Remove dead code modules + shop notification infrastructure

**Delete these files (confirmed never called):**
- `lib/blockster_v2/notifications/offer_selector.ex`
- `lib/blockster_v2/notifications/content_selector.ex`
- `lib/blockster_v2/notifications/send_time_optimizer.ex`
- `lib/blockster_v2/notifications/viral_coefficient_tracker.ex`
- `lib/blockster_v2/notifications/deliverability_monitor.ex`
- `lib/blockster_v2/notifications/revival_engine.ex`
- `lib/blockster_v2/notifications/price_alert_engine.ex` (no product price tracking exists)
- `lib/blockster_v2/workers/cart_abandonment_worker.ex`

**Remove shop triggers from TriggerEngine** (`trigger_engine.ex`):
- Delete `cart_abandonment_trigger` (depends on carted_not_purchased profile field we're removing)
- Delete `price_drop_trigger` (no product price change events exist)
- Delete `purchase_thank_you_trigger` (can be a simple inline notification in orders.ex if ever needed)

**Remove shop event tracking calls:**
- `lib/blockster_v2_web/live/shop_live/show.ex` — remove `UserEvents.track("product_view")` and `UserEvents.track("product_add_to_cart")`
- `lib/blockster_v2_web/live/checkout_live/index.ex` — remove `UserEvents.track("checkout_start")`
- Keep `purchase_complete` tracking in `lib/blockster_v2/orders.ex` (useful for analytics)

**Remove shop references from AI Manager system prompt and templates** (cart abandonment email templates, price drop templates)

**Remove from SystemConfig defaults:** `cart_abandon_hours`, `trigger_cart_abandonment_enabled`, `trigger_price_drop_enabled`

---

## Phase 3: Remove `user_profiles` table and dependencies

### 3a: Remove `UserProfile` schema and `ProfileEngine`

**Delete:**
- `lib/blockster_v2/notifications/user_profile.ex` (schema)
- `lib/blockster_v2/notifications/profile_engine.ex` (computes profiles from events)
- `lib/blockster_v2/workers/profile_recalc_worker.ex` (6h cron that calls ProfileEngine)

**Create rollback migration:** `DROP TABLE IF EXISTS user_profiles`

### 3b: Refactor `UserEvents` module

**File:** `lib/blockster_v2/user_events.ex`

- Remove `UserProfile` alias and all profile CRUD (`get_profile`, `get_or_create_profile`, `upsert_profile`, `users_needing_profile_update`, `users_without_profiles`)
- Remove `increment_events_since_calc` (no more profile counter)
- Keep all event tracking functions (`track`, `track_sync`, `track_batch`, `get_events`, `count_events`, `get_last_event`, `event_summary`, `get_event_types`)

### 3c: Refactor TriggerEngine to use Mnesia + inline queries

**File:** `lib/blockster_v2/notifications/trigger_engine.ex`

Current: `profile = UserEvents.get_profile(user_id)` → reads user_profiles table

New: With shop triggers removed, only 5 triggers remain: `bux_milestone`, `reading_streak`, `hub_recommendation`, `dormancy_warning`, `referral_opportunity`. Their data needs are minimal:

| Field | Source | Used By |
|-------|--------|---------|
| `consecutive_active_days` | `user_events` query (count distinct recent dates) | reading_streak |
| `days_since_last_active` | `user_events` query (last event timestamp) | dormancy_warning |
| `referral_propensity` | Simplify — check if user has shared articles OR has referrals in Mnesia `referral_stats` | referral_opportunity |

`bux_milestone` and `hub_recommendation` don't need profile at all (they use event metadata and inline queries).

**New function:** `build_trigger_context(user_id)` — lightweight map from:
1. A single `user_events` query for recent activity dates
2. Mnesia `referral_stats` for referral data (optional, only for referral trigger)

### 3d: Refactor EventProcessor

**File:** `lib/blockster_v2/notifications/event_processor.ex`

- Remove `UserEvents.get_profile()` call in `maybe_update_conversion_stage`
- Conversion stage tracking: move to SystemConfig or remove (it's only used by ConversionFunnelEngine)
- Keep enriched metadata (betting stats from Mnesia) — already done

### 3e: Refactor ConversionFunnelEngine

**File:** `lib/blockster_v2/notifications/conversion_funnel_engine.ex`

- Replace `UserEvents.get_profile()` reads with direct Mnesia lookups
- Betting data → `BuxBoosterStats.get_user_stats(user_id)`
- BUX balance → `EngagementTracker.get_user_token_balances(user_id)`

### 3f: Refactor remaining modules that read user_profiles

These modules read user_profiles and need updating:
- `churn_predictor.ex` — Replace profile queries with Mnesia reads
- `rogue_offer_engine.ex` — Replace profile queries with Mnesia reads
- `referral_engine.ex` — Replace profile reads with `referral_stats` Mnesia table
- `ai_manager.ex` — `build_user_report` already has Mnesia data, remove profile section

### 3g: Remove `Notifications.UserEvent` duplicate schema

**Delete:** `lib/blockster_v2/notifications/user_event.ex`

**Update all references** to use the event queries in `UserEvents` module directly. Files that reference `Notifications.UserEvent`:
- `trigger_engine.ex` line 363 — change to `UserEvents.count_events`
- `ai_manager.ex` gather_system_stats — query `user_events` table directly via Ecto fragment or keep the schema but move it to `UserEvents` module

**Decision:** Keep the schema file but move it to `lib/blockster_v2/user_event.ex` (rename module to `BlocksterV2.UserEvent`) since it's the backing schema for the `user_events` table that `UserEvents` module uses.

---

## Phase 4: Remove AB test dead infrastructure

**Delete:**
- `lib/blockster_v2/notifications/ab_test.ex`
- `lib/blockster_v2/notifications/ab_test_assignment.ex`
- `lib/blockster_v2/notifications/ab_test_engine.ex`
- `lib/blockster_v2/workers/ab_test_check_worker.ex`

**Create rollback migration:** `DROP TABLE IF EXISTS ab_test_assignments; DROP TABLE IF EXISTS ab_tests`

**Remove** AB test cron from `config/config.exs` Oban config.

---

## Phase 5: Clean up Oban config and Application.ex

**File:** `config/config.exs`
- Remove `ProfileRecalcWorker` cron entry
- Remove `ABTestCheckWorker` cron entry

**File:** `lib/blockster_v2/application.ex`
- No changes needed (EventProcessor is the only notification GenServer in supervision tree)

---

## Phase 6: Update AI Manager

**File:** `lib/blockster_v2/notifications/ai_manager.ex`

- `build_user_report` — remove `notification_profile` section (was from UserProfile), keep betting_stats/balances/referrals (all from Mnesia)
- `gather_system_stats` — update UserEvent reference to use the renamed schema
- System prompt — remove references to user_profiles fields, update to reflect Mnesia-first architecture

---

## Files Modified (summary)

**Delete (16 files):**
- `lib/blockster_v2/notifications/offer_selector.ex`
- `lib/blockster_v2/notifications/content_selector.ex`
- `lib/blockster_v2/notifications/send_time_optimizer.ex`
- `lib/blockster_v2/notifications/viral_coefficient_tracker.ex`
- `lib/blockster_v2/notifications/deliverability_monitor.ex`
- `lib/blockster_v2/notifications/revival_engine.ex`
- `lib/blockster_v2/notifications/price_alert_engine.ex`
- `lib/blockster_v2/workers/cart_abandonment_worker.ex`
- `lib/blockster_v2/notifications/user_profile.ex`
- `lib/blockster_v2/notifications/profile_engine.ex`
- `lib/blockster_v2/workers/profile_recalc_worker.ex`
- `lib/blockster_v2/notifications/ab_test.ex`
- `lib/blockster_v2/notifications/ab_test_assignment.ex`
- `lib/blockster_v2/notifications/ab_test_engine.ex`
- `lib/blockster_v2/workers/ab_test_check_worker.ex`
- `lib/blockster_v2/notifications/copy_writer.ex` (only used in tests)

**Modify (~11 files):**
- `lib/blockster_v2_web/live/notification_hook.ex` — async mount
- `lib/blockster_v2/user_events.ex` — remove profile CRUD
- `lib/blockster_v2/notifications/trigger_engine.ex` — remove shop triggers, Mnesia-based context
- `lib/blockster_v2/notifications/event_processor.ex` — remove profile reads, remove PriceAlertEngine dispatch
- `lib/blockster_v2/notifications/conversion_funnel_engine.ex` — Mnesia reads
- `lib/blockster_v2/notifications/ai_manager.ex` — remove profile, remove shop templates, update stats
- `lib/blockster_v2/notifications/churn_predictor.ex` — Mnesia reads
- `lib/blockster_v2_web/live/shop_live/show.ex` — remove UserEvents.track calls
- `lib/blockster_v2_web/live/checkout_live/index.ex` — remove UserEvents.track call
- `config/config.exs` — remove dead worker crons (ProfileRecalc, ABTest, CartAbandonment)
- `lib/blockster_v2/notifications/system_config.ex` — remove shop-related defaults

**New (1 file):**
- Migration to drop `user_profiles`, `ab_tests`, `ab_test_assignments` tables

---

## Verification

1. `mix compile` — zero errors
2. Restart node1 + node2 — verify boot, Mnesia sync, no crashes
3. Browse the app — verify pages load fast (no sync notification queries)
4. Check notification dropdown — verify it works async
5. Trigger a test event (read an article) — verify TriggerEngine fires
6. Check AI Manager admin page — verify it can still query stats
