# Blockster V2 — Notification & Engagement System Plan

> **Status**: PHASES 1-18 COMPLETE (808 tests passing) + UI Polish pass
> **Created**: 2026-02-18
> **Branch**: `feat/notification-system`

## Progress Notes

### Phase 1: Database & Core Infrastructure — COMPLETE (57 tests)
- **Migrations**: 5 new migrations (notification_campaigns, notifications, notification_preferences, notification_email_log, alter hub_followers)
- **Schemas**: Campaign, Notification, NotificationPreference, EmailLog, HubFollower
- **Context**: `BlocksterV2.Notifications` — full CRUD for all schemas, PubSub broadcasting
- **Auto-create**: Notification preferences auto-created on user registration (both wallet and email)
- **Files created**: 6 new files (4 schemas + 1 context + 1 HubFollower schema), 1 modified (accounts.ex), 5 migrations
- **Tests**: 57 passing — schema validations, CRUD operations, PubSub broadcasting, preferences, campaigns, email logs
- **Note**: Added secondary sort `desc: n.id` to notification queries to prevent flaky ordering when `inserted_at` is identical

### Phase 2: Hub Subscribe Button — COMPLETE (21 tests, 78 cumulative)
- **Blog context**: Added `follow_hub/2`, `unfollow_hub/2`, `toggle_hub_follow/2`, `user_follows_hub?/2`, `get_user_followed_hub_ids/1`, `get_hub_follower_user_ids/1`, `get_hub_followers_with_preferences/1`
- **HubLive.Show**: Added `:user_follows_hub` and `:follower_count` assigns on mount, `handle_event("toggle_follow")` handler with login redirect for unauthenticated users
- **Template**: Replaced broken `onclick="toggleModal('shareModal')"` button with `phx-click="toggle_follow"` — shows lime `#CAFC00` "Subscribed" (with check icon) when following, dark "Subscribe" (with bell icon) when not. Shows subscriber count.
- **Files modified**: blog.ex (follow functions), hub_live/show.ex (mount + handler), hub_live/show.html.heex (button UI)
- **Files created**: blog/hub_follower.ex (schema)
- **Tests**: 21 passing — follow/unfollow CRUD, toggle, isolation, multi-hub, follower queries

### Phase 3: In-App Notifications — Bell Icon & Dropdown — COMPLETE (21 tests, 99 cumulative)
- **NotificationHook**: on_mount module — subscribes to PubSub, fetches unread count + recent notifications, handles all notification UI events (toggle/close dropdown, mark_all_read, click_notification, dismiss_toast) via `attach_hook` for both `:handle_info` and `:handle_event`
- **Router**: Added NotificationHook to all 5 live_sessions that use BuxBalanceHook (admin, authenticated, author_new, author_edit, default)
- **App layout**: Passes `unread_notification_count`, `notification_dropdown_open`, `recent_notifications` to site_header
- **Header bell icon** (desktop): Between cart icon and user dropdown — 40x40 rounded circle with bell SVG, red badge with count (caps at "99+"), dropdown on click with notification list, mark-all-read button, click-away close
- **Notification items**: Image/icon, title (bold if unread), body (2-line clamp), relative timestamp, blue dot for unread, click navigates to action_url
- **Time formatter**: `format_notification_time/1` — "just now", "2m ago", "3h ago", "5d ago", "Feb 20"
- **Files created**: notification_hook.ex
- **Files modified**: router.ex (5 live_sessions), layouts.ex (attrs + bell + dropdown + formatter), app.html.heex (new assigns)
- **Tests**: 21 passing — module loading, initial state, PubSub delivery, click/read flow, ordering, notification types, badge count

### Phase 4: Toast Notifications & Real-Time Delivery — COMPLETE (32 tests, 131 cumulative)
- **Toast component**: Added to `app.html.heex` — fixed position top-right, slides in from right with `animate-slide-in-right`, auto-dismiss progress bar (`animate-shrink-width`), image or lime bell fallback icon, title, body, close button, click navigates to action_url
- **CSS animations**: Added `slide-in-right` (0.3s ease-out) and `shrink-width` (linear forwards) keyframes to `app.css`
- **JS hook**: `NotificationToastHook` — auto-dismisses after 5s, pauses timer on hover (pauses progress bar animation too), resumes with 3s on mouse leave
- **Hub post publish → follower notifications**: `publish_post/1` now fires `Task.start` → `notify_hub_followers_of_new_post/1` when post has a hub_id. Creates one notification per follower with hub name, post title, featured image, and post slug as action_url
- **Order status → notifications**: `notify_order_status_change/1` creates notifications with status-specific copy (Confirmed/Shipped/Delivered/Cancelled/generic fallback). Wired into `update_order/2` (when status changes) and `process_paid_order/1`
- **Notification types expanded**: Added `order_paid`, `order_cancelled`, `order_processing`, `order_bux_paid`, `order_rogue_paid` to valid notification types
- **Files created**: `assets/js/hooks/notification_toast.js`
- **Files modified**: `app.css` (animations), `app.js` (hook import + registration), `app.html.heex` (toast component), `blog.ex` (publish triggers), `orders.ex` (status notifications), `notification.ex` (expanded valid types)
- **Tests**: 32 passing — toast state management, click navigation, auto-dismiss behavior, hub post publish triggers (follower isolation, no-hub skip, no-followers skip, metadata, image), order status notifications (paid/shipped/delivered/cancelled/unknown + PubSub broadcast), end-to-end delivery flow, toast+dropdown interaction, notification category coverage
- **Note**: Hub creation requires `tag_name` field (discovered in tests). Used `get_hub(id)` not `get_hub!(id)` (only `get_hub/1` exists in Blog context)

### Phase 5: Notifications Page — COMPLETE (39 tests, 170 cumulative)
- **NotificationLive.Index**: Full LiveView at `/notifications` — category tabs (All/Content/Offers/Social/Rewards/System), read/unread filter toggle, mark-as-read on click, bulk "Mark all read" button, infinite scroll via existing InfiniteScroll hook (`data-event="load-more-notifications"`), empty state messaging per category
- **Category icons**: Mapped category to Heroicon (newspaper/content, tag/offers, users/social, trophy/rewards, cog/system)
- **Time formatting**: Reuses `format_notification_time/1` pattern (just now, Xm, Xh, Xd, date)
- **Route**: Added before catch-all `/:slug` in `:default` live_session
- **Files created**: `lib/blockster_v2_web/live/notification_live/index.ex`
- **Files modified**: `router.ex` (notification routes)
- **Tests**: 39 passing — listing, category filtering, read/unread filter, mark as read, bulk mark all read, infinite scroll pagination, empty state, category icons, timestamp formatting

### Phase 6: Notification Settings Page — COMPLETE (36 tests, 206 cumulative)
- **NotificationSettingsLive.Index**: Full settings page at `/notifications/settings` — toggle components for email/SMS/in-app channels, type-specific toggles (hub_posts, special_offers, daily_digest, etc.), max emails/day slider (1-10), quiet hours (time inputs), timezone selector, per-hub notification toggles, "Unsubscribe from all" with confirmation dialog
- **Blog context additions**: `get_user_followed_hubs_with_settings/1` (join HubFollower→Hub for per-hub toggles), `update_hub_follow_notifications/3`
- **UnsubscribeController**: GET `/unsubscribe/:token` — one-click unsubscribe via token, redirects to `/` with flash
- **Auto-save**: Toggles save immediately with "Saved" badge that clears after 2s
- **Files created**: `notification_settings_live/index.ex`, `controllers/unsubscribe_controller.ex`
- **Files modified**: `router.ex` (settings + unsubscribe routes), `blog.ex` (hub settings queries)
- **Tests**: 36 passing — toggle states, preference persistence, per-hub settings, quiet hours, frequency controls, unsubscribe flow

### Phase 7: Email Infrastructure & Templates — COMPLETE (53 tests, 259 cumulative)
- **EmailBuilder**: 8 email templates — `single_article`, `daily_digest`, `promotional`, `referral_prompt`, `weekly_reward_summary`, `welcome`, `re_engagement`, `order_update`. Shared base HTML layout with Blockster branding (#CAFC00), dark mode CSS, CTA buttons, List-Unsubscribe headers (RFC 8058), HTML escaping
- **RateLimiter**: `can_send?/3` returns `:ok`/`:defer`/`{:error, reason}`. Checks: channel_enabled → type_enabled → rate_limit (daily email cap, weekly SMS cap) → quiet_hours (with timezone offset table). Maps email types to preference fields (e.g., "hub_post" → `:email_hub_posts`)
- **Files created**: `notifications/email_builder.ex`, `notifications/rate_limiter.ex`
- **Tests**: 53 passing — base layout, all 8 templates, from/to/headers, dark mode, unsubscribe links, rate limiter (channel/type/rate/quiet hours), preference field mapping

### Phase 8: Email Workers (Oban Jobs) — COMPLETE (51 tests, 310 cumulative)
- **Oban setup**: Added `{:oban, "~> 2.18"}` dep, configured queues (email_transactional:5, email_marketing:3, email_digest:2, sms:1, default:10), cron schedule (DailyDigest 9AM, WeeklyRewardSummary 10AM Mon, ReferralPrompt 2PM Wed, ReEngagement 11AM, CartAbandonment every 30min), test config (`testing: :inline`)
- **8 workers created**:
  1. `DailyDigestWorker` (email_digest) — batch finds eligible users, individual jobs send personalized digest from followed hub posts
  2. `WelcomeSeriesWorker` (email_transactional) — 4-email series on days 0/3/5/7, `enqueue_series/1` API
  3. `ReEngagementWorker` (email_marketing) — targets 3/7/14/30-day inactive users, 30d+ gets special offer
  4. `WeeklyRewardSummaryWorker` (email_marketing) — weekly BUX stats email
  5. `ReferralPromptWorker` (email_marketing) — weekly referral nudge with personalized link
  6. `HubPostNotificationWorker` (email_marketing) — batched hub post email alerts, `enqueue/3` API
  7. `PromoEmailWorker` (email_marketing) — campaign-triggered sends, `enqueue_campaign/1`, respects target_audience and send_in_app, updates campaign status
  8. `CartAbandonmentWorker` (email_transactional) — finds carts idle >2h, 24h dedup, sends reminder + in-app notification
- **Bug fixes during testing**: All 8 workers referenced `user.display_name` but User schema uses `username` — fixed to `user.username`. DailyDigest/ReEngagement queried `p.status == "published"` but Post uses `published_at` (non-nil) — fixed to `not is_nil(p.published_at)`. CartAbandonment queried `c.status == "active"` but Cart has no status field — fixed to join on cart_items existence. HubPostNotification used `post.body` but Post uses `excerpt` — fixed.
- **Files created**: 8 worker files in `lib/blockster_v2/workers/`
- **Files modified**: `mix.exs` (oban dep), `config/config.exs` (oban config), `config/test.exs` (oban testing), `application.ex` (supervision tree), oban migration
- **Tests**: 51 passing — all 8 workers (send/skip/rate-limit/missing-user), cross-worker integration (email log tracking, rate limit respect, email_enabled=false blocks all), Oban config validation (queues, max_attempts)

### Phase 9: SMS Notifications — COMPLETE (34 tests, 344 cumulative)
- **SmsNotifier module**: `notifications/sms_notifier.ex` — SMS template builder with 7 message types (flash_sale, bux_milestone, order_shipped, account_security, exclusive_drop, special_offer, generic fallback). 160-char limit with auto-truncation. "Reply STOP to opt out" footer on all messages. User eligibility check (phone_verified + sms_opt_in). Phone lookup via PhoneVerification table.
- **SmsNotificationWorker**: Oban worker on `:sms` queue — `enqueue/3` for single user, `enqueue_broadcast/2` for all eligible. Respects RateLimiter (weekly SMS cap, quiet hours, per-type opt-out). Logs SMS sends to email_log as type "sms".
- **TwilioWebhookController**: `POST /api/webhooks/twilio/sms` — handles opt-out (STOP/STOPALL/UNSUBSCRIBE/CANCEL/END/QUIT) and opt-in (START/YES/UNSTOP). Updates PhoneVerification.sms_opt_in, User.sms_opt_in, and NotificationPreference.sms_enabled. Returns TwiML 200.
- **Triggers wired**: Order shipped → SMS enqueued in `notify_order_status_change/1`. Campaign send_sms → SMS enqueued in PromoEmailWorker (flash_sale or special_offer type).
- **Files created**: `notifications/sms_notifier.ex`, `workers/sms_notification_worker.ex`, `controllers/twilio_webhook_controller.ex`
- **Files modified**: `router.ex` (webhook route), `orders.ex` (shipped SMS trigger), `workers/promo_email_worker.ex` (campaign SMS trigger)
- **Tests**: 34 passing — 9 template tests (all types + truncation + opt-out footer), 3 eligibility tests, 3 phone lookup tests, 7 worker tests (skip/send/rate-limit), 1 enqueue test, 6 rate limiter SMS integration tests, 4 webhook tests (opt-out/opt-in/unknown/keywords), 1 order trigger test
- **Key decisions**: Used Twilio Messages API (not Verify) for SMS sending. Logged SMS to existing email_log table with type "sms" for unified rate limiting. Truncation uses ".." (2 bytes) instead of "…" (3 bytes) to stay within 160 char limit.

### Phase 10: SendGrid Webhooks & Analytics — COMPLETE (27 tests, 371 cumulative)
- **SendgridWebhookController**: `POST /api/webhooks/sendgrid` — processes SendGrid event arrays. Handles: open (set opened_at, increment campaign.emails_opened), click (set clicked_at + opened_at, increment campaign.emails_clicked), bounce (set bounced=true, auto-suppress user email), spam_report (bounced+unsubscribed, disable all marketing prefs), unsubscribe (set unsubscribed, disable email_enabled). Strips `.filter...` suffix from sg_message_id.
- **EngagementScorer**: `notifications/engagement_scorer.ex` — `calculate_score/1` returns per-user 30-day metrics (open/click rates, preferred hour, top categories, engagement tier). `classify_tier/2` buckets into highly_engaged/moderately/low/dormant. `aggregate_stats/1` for admin dashboard totals. `daily_email_volume/1` for charting. `send_time_distribution/1` for heatmap. `channel_comparison/1` for email vs in-app vs SMS.
- **Files created**: `controllers/sendgrid_webhook_controller.ex`, `notifications/engagement_scorer.ex`
- **Files modified**: `router.ex` (webhook route)
- **Tests**: 27 passing — 3 open event tests (set/idempotent/campaign), 3 click tests (set/auto-open/campaign), 2 bounce tests (mark/suppress), 2 spam tests (mark/unsubscribe-all), 2 unsubscribe tests (mark/prefs), 5 edge case tests (unknown ID/empty/multiple/unknown event/filter suffix), 2 scorer calculation tests, 4 tier tests, 1 aggregate test, 1 daily volume test, 1 time distribution test, 1 channel comparison test
- **Key decisions**: Used Endpoint (not Router) in tests for JSON parsing. Campaign stats use `Repo.update_all` with `inc` for atomic increment. Spam reports disable multiple marketing preference fields (not just email_enabled).

### Phase 11: Admin Campaign Interface — COMPLETE (30 tests, 401 cumulative)
- **CampaignAdminLive.Index**: Campaign list page at `/admin/notifications/campaigns` — status filter tabs (All/Draft/Scheduled/Sending/Sent/Cancelled), Quick Send inline form (title/audience/body/channel checkboxes), Send Test button (sends promo email to admin's own email), delete/cancel campaign actions, channel badges (Email/In-App/SMS), performance columns (opens/clicks)
- **CampaignAdminLive.New**: 5-step wizard at `/admin/notifications/campaigns/new` — content (name/subject/title/body/image/action), audience (radio cards: all/hub_followers/active/dormant/phone_verified, hub selector, estimated recipient count), channels (email/in-app/SMS toggles with icons), schedule (send now vs datetime picker), review (summary + Send Test + Create Campaign). Uses `campaign_recipient_count/1` for live recipient estimates.
- **CampaignAdminLive.Show**: Campaign detail page at `/admin/notifications/campaigns/:id` — auto-refreshing stats (30s interval), stat cards (recipients/sent/opened/clicked), tabs (Overview/Email Stats/In-App Stats/Content), delivery funnel bars, rate calculations, campaign metadata display, Send Test and Cancel actions
- **Context additions**: `delete_campaign/1`, `campaign_recipient_count/1` (queries by target_audience: all/hub_followers/active_users/dormant_users/phone_verified), `get_campaign_stats/1` (joins email_logs + notifications for combined stats), `update_email_log/2`, `get_email_log_by_message_id/1`
- **Files created**: `campaign_admin_live/index.ex`, `campaign_admin_live/new.ex`, `campaign_admin_live/show.ex`
- **Files modified**: `router.ex` (3 admin routes), `notifications.ex` (5 new context functions)
- **Tests**: 30 passing — campaign CRUD (create/update/delete/list/filter), recipient counting (all/active/dormant/phone_verified), campaign stats (with activity/empty), email log operations, channel configuration, status workflow (draft→sending→sent, draft→cancelled, draft→scheduled→cancelled), audience validation, scheduling, stats field defaults + increment, content field storage
- **Key decisions**: Used `updated_at` as proxy for user activity (active_users: <7d, dormant_users: >30d) since `last_sign_in_at` column doesn't exist. Stats auto-refresh via `:timer.send_interval(30_000)`. Funnel bars use percentage width for visual representation.

### Phase 12: Notification Analytics Dashboard — COMPLETE (24 tests, 425 cumulative)
- **NotificationAnalyticsLive.Index**: Full analytics dashboard at `/admin/notifications/analytics` — period selector (7d/14d/30d/90d), overview stat cards (emails sent, open rate, click rate, bounce rate, in-app delivered, read rate, bounced, unsubscribed), channel comparison bars (email/in-app/SMS with engagement rates), daily email volume chart (last 14 days, sent vs opened bars), send time heatmap (24-hour grid with lime color intensity), top campaigns table (ranked by opens with rate), hub subscription analytics table (followers, notify-enabled, opt-in rate, distribution bar)
- **Context additions**: `top_campaigns/1` (sent campaigns with emails_sent > 0, ordered by opens), `hub_subscription_stats/0` (follower count + notify_enabled per hub, ordered by followers desc)
- **EngagementScorer**: Already built in Phase 10 — `aggregate_stats/1`, `daily_email_volume/1`, `send_time_distribution/1`, `channel_comparison/1` all consumed by dashboard
- **Files created**: `notification_analytics_live/index.ex`
- **Files modified**: `router.ex` (1 admin route), `notifications.ex` (2 new context functions)
- **Tests**: 24 passing — top campaigns (ordering/exclude draft/exclude 0 sent/limit/empty), hub subscription stats (follower counts/notify enabled/empty/ordering), engagement scorer aggregate stats (keys/period/counting/rates), daily volume (structure/fields/period), time distribution (structure/fields), channel comparison (all channels/fields/data), integration tests (email+notification independence, multi-user aggregation, per-user scoring)
- **Key decisions**: Used `updated_at` as user activity proxy (consistent with Phase 11). Campaign stat fields set via `Ecto.Changeset.change` in tests since not in Campaign changeset cast list. Hub stats use `HubFollower` schema (not string table) to access composite key. Heatmap uses lime color gradient with 5 intensity levels.

### Phase 13: User Behavior Tracking & Profiles — COMPLETE (73 tests, 498 cumulative)
- **Migrations**: 2 new — `create_user_events` (event stream table with 5 indexes), `create_user_profiles` (aggregated behavior data with 6 indexes including unique user_id)
- **Schemas**: `UserEvent` (38 valid event types across 6 categories with auto-categorize), `UserProfile` (60+ fields covering content/shopping/engagement/notification/referral/gambling/churn)
- **UserEvents module**: `track/3` (async fire-and-forget), `track_sync/3` (synchronous for tests), `track_batch/1` (bulk insert), `get_events/2`, `count_events/3`, `get_last_event/2`, `event_summary/2`, `get_event_types/2`, profile CRUD (`get_or_create_profile`, `upsert_profile`, `get_profile`), `users_needing_profile_update/1`, `users_without_profiles/0`
- **ProfileEngine**: `classify_engagement_tier/1` (7 tiers: new/casual/active/power/whale/dormant/churned), `calculate_engagement_score/1` (0-100 composite from 5 weighted dimensions), `classify_gambling_tier/1` (5 tiers: non_gambler through whale_gambler), `calculate_churn_risk/1` (0-1 score + 4 levels: low/medium/high/critical), `recalculate_profile/1` (full profile rebuild from event history)
- **ProfileRecalcWorker**: Oban worker on `:default` queue — batch recalc (cron every 6h) + single-user on-demand. Uses `unique: [period: 300]` for dedup.
- **EventTracker JS hook**: Client-side event tracking — product view duration (>10s), article scroll depth, partial read tracking on destroy
- **Config**: Added ProfileRecalcWorker to Oban cron (`0 */6 * * *`), registered EventTracker hook in app.js
- **Files created**: 5 new files — `notifications/user_event.ex`, `notifications/user_profile.ex`, `user_events.ex`, `notifications/profile_engine.ex`, `workers/profile_recalc_worker.ex`, `assets/js/hooks/event_tracker.js`, 2 migrations
- **Files modified**: `config/config.exs` (cron), `assets/js/app.js` (hook import + registration)
- **Tests**: 73 passing — schema validations (event types, categories, profile tiers, score ranges), tracking (sync/async/batch, metadata storage, string key normalization), querying (events, counts, last event, summaries, isolation), profile CRUD (create/upsert/get), tier classification (all 7 engagement tiers, 5 gambling tiers), churn risk (4 levels + score bounds), engagement score (empty/active/capped), full recalculation (content prefs, shopping, engagement, gambling, churn), worker (single/batch/enqueue), event counter tracking (increment + reset)
- **Key decisions**: Metadata keys normalized to strings on insertion (atom→string) for consistent DB roundtrip. Events use `timestamps(updated_at: false)` (append-only). Secondary sort by `desc: id` prevents flaky ordering. NaiveDateTime comparisons (not DateTime) for event timestamps. Engagement tier threshold: <1.0 sessions/week = casual (not <3).

### Phase 14: AI Personalization & A/B Testing — COMPLETE (86 tests, 584 cumulative)
- **Migration**: `create_ab_tests` — `ab_tests` table (name, email_type, element_tested, status, variants, start/end dates, min_sample_size, confidence_threshold, winning_variant, results) + `ab_test_assignments` table (ab_test_id, user_id, variant_id, opened, clicked) with unique index on [ab_test_id, user_id]
- **Schemas**: `ABTest` (valid statuses: running/completed/winner_applied, valid elements: subject/body/cta_text/cta_color/send_time/image/article_count/layout), `ABTestAssignment` (variant assignment + open/click tracking)
- **ABTestEngine**: `create_test/1`, `assign_variant/2` (deterministic via `:erlang.phash2`), `get_active_test/2`, `get_variant_for_user/3`, `record_open/2`, `record_click/2`, `check_significance/1` (chi-squared test with erfc approximation), `promote_winner/2`, `list_tests/1`, `get_test_results/1`
- **ContentSelector**: Article selection with weighted scoring model — hub_preference (0.35), category_preference (0.25), recency (0.25), popularity (0.15). Filters already-read articles. Supports pools: `:all`, `:hub_subscriptions`, `:trending`
- **OfferSelector**: Shopping behavior-based offer selection — priority: cart_reminder > product_highlight > cross_sell > bux_spend > trending. Urgency message generation.
- **CopyWriter**: Tier-based message framing for 7 email types — `digest_subject`, `referral_subject`, `cart_abandonment_subject`, `re_engagement_subject`, `welcome_subject`, `reward_summary_subject`, `cta_text`. Each adapts copy based on engagement tier and user behavior.
- **TriggerEngine**: 8 real-time notification triggers evaluated on each user event — cart_abandonment (session_end + carted items + >2h since cart), bux_milestone (1k/5k/10k/25k/50k/100k), reading_streak (3/7/14/30 days), hub_recommendation (3+ reads in category w/o following hub), price_drop (viewed product price decreased), purchase_thank_you (first purchase), dormancy_warning (return after 5-14 days), referral_opportunity (high propensity + article share/bux earned). All triggers have deduplication (daily/weekly/lifetime limits).
- **ABTestCheckWorker**: Oban worker on `:default` queue — checks all running tests every 6h, promotes winner when statistical significance reached
- **Config**: Added ABTestCheckWorker to Oban cron (`0 */6 * * *`)
- **Files created**: 7 new files — `notifications/ab_test.ex`, `notifications/ab_test_assignment.ex`, `notifications/ab_test_engine.ex`, `notifications/content_selector.ex`, `notifications/offer_selector.ex`, `notifications/copy_writer.ex`, `notifications/trigger_engine.ex`, `workers/ab_test_check_worker.ex`, 1 migration
- **Files modified**: `config/config.exs` (cron)
- **Tests**: 86 passing — ABTest schema (validation, statuses, elements), ABTestAssignment (validation, unique constraint), ABTestEngine (create, assign deterministically, active test lookup, variant for user, record open/click, results aggregation, significance check, promote winner, list/filter), CopyWriter (all 7 subject generators across all tiers, CTA text for all types), OfferSelector (default fallback, urgency messages for all types), ContentSelector (relevance scoring, hub boost, recency scoring, score clamping), TriggerEngine (all 8 triggers with fire + skip conditions, cart dedup, milestone dedup, evaluate_triggers integration), ABTestCheckWorker (batch + single + promote), full lifecycle integration test
- **Key decisions**: NaiveDateTime truncated to `:second` for Repo inserts. TriggerEngine fires real notifications via `Notifications.create_notification/2`. Deduplication via DB queries (not in-memory). Chi-squared significance uses erfc for df=1 and Wilson-Hilferty for df>1.

### Phase 15: BUX-to-ROGUE Conversion Funnel — COMPLETE (53 tests, 637 cumulative)
- **Migration**: `add_rogue_gambling_fields` — adds 13 new columns to user_profiles: ROGUE gambling (total_rogue_games, total_rogue_wagered, total_rogue_won, rogue_balance_estimate, games_played_last_7d, win_streak, loss_streak), VIP (vip_tier, vip_unlocked_at), conversion funnel (conversion_stage, last_rogue_offer_at, rogue_readiness_score)
- **Schema updates**: UserProfile extended with new fields + validations for `vip_tier` (none/bronze/silver/gold/diamond) and `conversion_stage` (earner/bux_player/rogue_curious/rogue_buyer/rogue_regular)
- **RogueOfferEngine**: `calculate_rogue_readiness/1` (0-1 score from 7 weighted signals: game frequency 0.25, wager size 0.20, engagement 0.15, purchases 0.10, referrals 0.10, content 0.15, tenure 0.05), `classify_vip_tier/1` (bronze 10+/silver 50+/gold 100+/diamond 100+ games & 100+ wagered), `classify_conversion_stage/1` (5-stage funnel), `calculate_airdrop_amount/2` (2.0/1.0/0.5/0.25 ROGUE by score), `airdrop_reason/1` (contextual message), `get_rogue_offer_candidates/1` (top N users filtered by tier + 14-day recency), `mark_rogue_offer_sent/1`
- **ConversionFunnelEngine**: 5-stage notification trigger system — Stage 1 (earner→BUX player: bux_booster_invite at 500 BUX, reader_gaming_nudge at 5th article), Stage 2 (bux_player→ROGUE: rogue_discovery at 5th game, loss_streak_offer at 3+ losses), Stage 3 (rogue_curious: purchase_nudge on first ROGUE game), Stage 4 (rogue_buyer: win_streak_celebration at 3+ wins, big_win_celebration at 10x+ multiplier), Stage 5 (rogue_regular→VIP). VIP upgrade notifications fire across all stages.
- **RogueAirdropWorker**: Oban worker on `:default` queue — batch job finds top 25 candidates, enqueues individual airdrop jobs. Creates in-app notification + marks offer timestamp. Scheduled Fridays 3 PM UTC.
- **Config**: Added RogueAirdropWorker to Oban cron (`0 15 * * 5`)
- **Files created**: 3 new files — `notifications/rogue_offer_engine.ex`, `notifications/conversion_funnel_engine.ex`, `workers/rogue_airdrop_worker.ex`, 1 migration
- **Files modified**: `notifications/user_profile.ex` (13 new fields, 2 new validators, 2 new constants), `config/config.exs` (cron)
- **Tests**: 53 passing — UserProfile ROGUE fields (schema, VIP validation, conversion stage validation, readiness score bounds), RogueOfferEngine (readiness scoring for inactive/active/max users, engagement tier effect, VIP tiers all 5 levels, conversion stages all 5 stages, airdrop amounts 4 tiers, airdrop reasons 4 variants, candidate selection sorted + exclusion + empty, mark_offer_sent), ConversionFunnelEngine (Stage 1 bux_booster_invite + reader_nudge + skip, Stage 2 rogue_discovery + loss_streak_offer, Stage 3 purchase_nudge, Stage 4 win_streak + big_win, VIP upgrade fire + no-fire, deduplication), RogueAirdropWorker (batch + single + mark_sent + missing user), integration (full funnel flow, readiness+airdrop high/low, VIP progression)

### Phase 16: Supercharged Referral Engine — COMPLETE (43 tests, 680 cumulative)
- **ReferralEngine**: Core referral system with 5-tier escalating rewards (1-5: 500 BUX, 6-15: 750 + ambassador badge, 16-30: 1000 + 1.0 ROGUE, 31-50: 1500 + vip_referrer badge, 51+: 2000 + blockster_legend + 0.5 ROGUE). Key functions: `get_reward_tier/1`, `calculate_referral_reward/1` → {referrer_bux, friend_bux, rogue}, `badge_at_count/1` (detects newly unlocked badges), `next_tier_info/1` (distance to next tier)
- **Lifecycle notifications**: 4 referral milestone notifications — `notify_referral_signup/3` (friend joins, BUX earned, badge unlock, next tier info), `notify_referral_first_bux/2` (friend earns first BUX), `notify_referral_first_purchase/2` (friend buys, 200 BUX bonus), `notify_referral_first_game/2` (friend plays, ROGUE hint)
- **Leaderboard**: `weekly_leaderboard/1` (ranked users by referral count, calculates total BUX earned per tier, limit param), `user_leaderboard_position/1` (individual rank + total participants)
- **Email integration**: `referral_block_for_email/2` — contextual referral blocks for 7 email types (daily_digest, reward_summary, bux_milestone, game_result, order_confirmation, cart_abandonment, default). Uses tier-appropriate reward amounts.
- **Prompt logic**: `should_prompt_referral?/2` — fatigue-aware prompting based on propensity (>0.7 weekly, >0.3 monthly, <0.3 never). Deduplicates against recent `referral_prompt` notifications.
- **ReferralLeaderboardWorker**: Oban worker on `:email_marketing` queue — logs top referrer weekly. Scheduled Tuesdays 10 AM UTC.
- **Config**: Added ReferralLeaderboardWorker to Oban cron (`0 10 * * 2`)
- **Files created**: 2 new files — `notifications/referral_engine.ex`, `workers/referral_leaderboard_worker.ex`
- **Files modified**: `config/config.exs` (cron)
- **Tests**: 43 passing — reward tiers (all 5 tiers), calculate_referral_reward (correct values, escalation, ROGUE bonus at tier 3+), badge_at_count (nil below threshold, ambassador/vip_referrer/blockster_legend at boundaries, nil within tier), next_tier_info (distance, max_tier, boundary), lifecycle notifications (signup with BUX/badge/next-tier, first_bux, first_purchase with bonus, first_game), leaderboard (sorted, excludes 0, BUX calculation, limit), user_position (rank/total, nil for 0 referrals), referral_block_for_email (all 7 types + tier-appropriate amounts), should_prompt_referral (high/low/dedup), ReferralLeaderboardWorker (with data + empty), integration (full lifecycle 4 notifications, tier progression escalation)

### Phase 17: Revival & Retention System — COMPLETE (79 tests, 759 cumulative)
- **ChurnPredictor**: 8-signal churn prediction — frequency_decline (sessions + inactivity), session_shortening (duration thresholds), email_engagement_decline (open + click rates), discovery_stall (hub diversity), bux_earning_decline (recent vs average reading ratio), notification_fatigue (fatigue score), no_purchases (0.3 weak signal), no_referrals (0.2 weak signal). Weighted aggregate (0-1), risk tiers (healthy/watch/at_risk/critical/churning), intervention selection per tier (none/personalization/re_engagement 100 BUX/rescue 500 BUX/all_out_save 1000 BUX + 0.5 ROGUE). Deduplication via 7-day lookback.
- **RevivalEngine**: User type classification (reader/gambler/shopper/hub_subscriber/general) via scoring. 4-stage revival sequences per user type (stage 1: 3d, stage 2: 7d, stage 3: 14d, stage 4: 30d) with escalating offers. Welcome back detection (7+ days, dedup, engagement-based bonus calculation). Engagement hooks: daily check-in bonus (50 BUX), streak rewards (3d:100, 7d:500, 14d:1500, 30d:5000), daily challenges (type-specific), weekly quests (type-specific). Analytics: churn_risk_distribution, engagement_tier_distribution, revival_success_rate (counts returned users within 7 days of intervention).
- **ChurnDetectionWorker**: Daily Oban worker on `:default` queue — scans users with churn_risk_score >= 0.5, fires interventions with deduplication. Scheduled 6 AM UTC.
- **Schema update**: Added 5 new notification types: `welcome_back`, `re_engagement`, `churn_intervention`, `daily_bonus` to Notification `@valid_types`
- **Config**: Added ChurnDetectionWorker to Oban cron (`0 6 * * *`)
- **Files created**: 3 new files — `notifications/churn_predictor.ex`, `notifications/revival_engine.ex`, `workers/churn_detection_worker.ex`
- **Files modified**: `notifications/notification.ex` (5 new types), `config/config.exs` (cron)
- **Tests**: 79 passing — individual signals (frequency_decline active/inactive, session_shortening long/short/none, email_engagement high/none, discovery_stall empty/diverse, bux_earning_decline match/dropped, no_purchases yes/no, no_referrals yes/no), aggregate_signals (low/high/capped), classify_risk_level (all 5 levels), get_risk_tier (healthy/at_risk/churning), select_intervention (all 5 tiers with correct types/offers/channels), predict_churn (healthy full/at-risk full), fire_intervention (create/skip), intervention_sent_recently (false/true), get_at_risk_users (above/below threshold), classify_user_type (reader/gambler/shopper/hub_subscriber/general), revival_stage (0-4), get_revival_message (reader stage 1/3, gambler stage 2, shopper stage 3, general fallback), check_welcome_back (eligible/skip recent/skip sent), calculate_return_bonus (escalating/engagement multiplier), fire_welcome_back (notification), check_daily_bonus (first/already), streak_reward (3/7/14/30/non-milestone), daily_challenge (reader/gambler), weekly_quest (reader/gambler), churn_risk_distribution (map), engagement_tier_distribution (map), revival_success_rate (empty/with data), ChurnDetectionWorker (with data/empty/no duplicates), integration (full lifecycle: predict→intervene→revival→welcome_back, engagement hooks: bonus+streak+challenge+quest)

### Phase 18: Advanced Analytics & Intelligence — COMPLETE (49 tests, 808 cumulative)
- **SendTimeOptimizer**: Per-user send-time optimization using `best_email_hour_utc` from UserProfile. Key functions: `optimal_send_hour/1` (DB lookup with population fallback), `optimal_send_hour_from_profile/1` (struct-based), `population_best_hour/0` (most popular open hour across all users), `delay_until_optimal/1` (seconds until best hour), `delay_from_profile/1` (struct-based delay), `has_sufficient_data?/1` (min 5 opened emails), `hourly_engagement_distribution/1` (hour→count map for analytics), `optimization_stats/0` (optimized vs default user counts). Default hour: 10 UTC.
- **DeliverabilityMonitor**: Email health tracking and alerting. Key functions: `calculate_metrics/1` (sent/delivered/bounced/opened/clicked with rates), `metrics_by_type/1` (per-email-type breakdown), `check_alerts/1` (bounce >5% warning/>10% critical, open <10% warning), `daily_send_volume/1` (date→count for charting), `recent_bounces/1` (latest bounce details), `health_score/1` (0-100 weighted: bounce 40%, open 35%, click 25%).
- **ViralCoefficientTracker**: Referral K-factor analytics. K = avg_invites × conversion_rate. Key functions: `calculate_k_factor/0` (full stats map with K), `referral_stats/0` (total_referrers/sent/converted/avg_invites/conversion_rate), `is_viral?/1` (K >= configurable target, default 1.0), `top_referrers/1` (sorted by conversions with personal conversion rate), `referral_funnel/0` (total→shared→converted with rates).
- **PriceAlertEngine**: ROGUE price movement notifications for holders. Key functions: `evaluate_price_change/2` (5% significant, 10% major thresholds → {:fire, alert_data} or :skip), `get_alert_eligible_users/0` (rogue_curious/rogue_buyer/rogue_regular stages), `fire_price_alerts/1` (batch fire with daily dedup), `fire_price_notification/2` (single user alert), `price_alert_copy/1` (4 copy variants: up/down × significant/major), `price_alert_sent_recently?/1` (daily dedup check).
- **Files created**: 4 new files — `notifications/send_time_optimizer.ex`, `notifications/deliverability_monitor.ex`, `notifications/viral_coefficient_tracker.ex`, `notifications/price_alert_engine.ex`
- **Tests**: 49 passing — SendTimeOptimizer (profile hour used, population fallback, default fallback, delay same/later/tomorrow, from_profile direct/nil, sufficient data yes/no, hourly distribution, optimization stats), DeliverabilityMonitor (metrics with data/empty, by_type grouping, bounce alert/no alert, open rate alert, health score healthy/degraded/no emails, daily volume, recent bounces), ViralCoefficientTracker (k_factor computation, zero referrers, is_viral boolean/threshold, top_referrers sorted/rate, referral_funnel all metrics), PriceAlertEngine (major up/down, significant up/down, below threshold, invalid input, price copy all 4 variants, fire_price_notification creates, dedup today/clear tomorrow, eligible users filter), integration (full system: send time + deliverability + viral + price alerts)
- **Key decisions**: EmailLog changeset only casts subset of fields — test helper uses `Ecto.Changeset.put_change/3` for `opened_at`, `clicked_at`, `bounced`. Health score uses `<=` not `<` for boundary assertion (exactly 40.0 is valid degraded). Viral coefficient tests avoid global state dependency (async test isolation). Price alerts use `price_drop` notification type (already in valid types).

### UI Polish Pass — COMPLETE (310 tests still passing)
- **Notifications Page** (`notification_live/index.ex`): Redesigned using `/frontend-design` plugin with "Editorial Precision" aesthetic direction
  - Page bg changed to `#F5F6FB` (matching app theme)
  - Lime bell icon badge in page header
  - Category tabs in white pill container; active tab = `bg-[#CAFC00]` with black text
  - Read/unread filter uses dark pills (`bg-[#141414]`) for active state
  - Unread notifications: 3px lime accent bar on left edge + subtle shadow
  - Read notifications: transparent bg (blend with page), dimmed text
  - Unread dot: lime with glow (`shadow-[0_0_6px_rgba(202,252,0,0.4)]`) instead of blue
  - Empty state: larger icon area with lime tinted background + checkmark badge
  - Mark all read: responsive mobile/desktop placement
- **Settings Page** (`notification_settings_live/index.ex`): Matching redesign
  - Section cards with lime accent bar indicator (vertical dot next to title)
  - Saved badge: lime background (`bg-[#CAFC00]`) with checkmark icon
  - Toggle switches: enlarged (h-7 w-12), better knob shadow, hover state on track
  - Email limit badge: lime square showing the number
  - Quiet hours: dark moon icon + inset `bg-[#F5F6FB]` panel + arrow icon + rounded-xl inputs
  - Hub cards: `bg-[#F5F6FB]` background with elevated white active toggles
  - Unsubscribe section: warning icon + two-column layout
  - Logged-out state: lock icon
- **All 310 tests pass** — no functional changes, purely visual

---

## Table of Contents

1. [Overview & Goals](#1-overview--goals)
2. [Current Infrastructure Audit](#2-current-infrastructure-audit)
3. [Database Schema](#3-database-schema)
4. [Hub Subscribe Button](#4-hub-subscribe-button)
5. [In-App Notification System](#5-in-app-notification-system)
6. [Email System](#6-email-system)
7. [SMS System](#7-sms-system)
8. [Notification Types Catalog](#8-notification-types-catalog)
9. [Smart Scheduling & Frequency Engine](#9-smart-scheduling--frequency-engine)
10. [Referral Prompting System](#10-referral-prompting-system)
11. [Admin Campaign Interface](#11-admin-campaign-interface)
12. [Analytics & Tracking](#12-analytics--tracking)
13. [AI-Driven Personalization & User Behavior Engine](#13-ai-driven-personalization--user-behavior-engine)
14. [Deep Dive: Email Content Creation & Lifecycle](#14-deep-dive-email-content-creation--lifecycle)
15. [BUX-to-ROGUE Conversion Funnel & Gambling Engagement](#15-bux-to-rogue-conversion-funnel--gambling-engagement)
16. [Supercharged Referral Engine](#16-supercharged-referral-engine)
17. [Revival & Retention Playbook](#17-revival--retention-playbook)
18. [Implementation Phases](#18-implementation-phases)

---

## 1. Overview & Goals

Build a comprehensive multi-channel notification and engagement system that:

- **Maximizes daily contact** — 1-3 emails per day with articles, offers, promos, engagement nudges
- **Activates the hub Subscribe button** — users follow hubs and receive content from them
- **Adds in-app notifications** — bell icon with dropdown, toast slide-ins, dedicated notifications page
- **Uses SMS sparingly** — high-value alerts only (special offers, account milestones)
- **Drives referrals** — periodic prompts asking users to invite friends
- **Re-engages dormant users** — win-back campaigns, "you missed this" summaries
- **Gives admins control** — campaign builder, template management, scheduling, analytics

### Success Metrics

| Metric | Target |
|--------|--------|
| Daily email send rate | 1-3 per active user |
| Email open rate | >25% |
| Email click-through rate | >5% |
| Hub subscription rate | >30% of active users follow at least 1 hub |
| In-app notification read rate | >60% |
| Referral conversion | >10% of prompted users share a link |
| DAU increase from notifications | >15% lift |

---

## 2. Current Infrastructure Audit

### What Exists

| Component | Status | Details |
|-----------|--------|---------|
| **Swoosh + SendGrid** | Working | `BlocksterV2.Mailer`, prod config with `SENDGRID_API_KEY` |
| **Email templates** | 2 exist | `OrderMailer` (fulfillment), `WaitlistEmail` (verification) |
| **Twilio** | Working | Phone verification only — `TwilioClient`, `PhoneVerification` |
| **Telegram Bot** | Working | Order notifications to fulfillment channel |
| **Phoenix PubSub** | Extensive | 10+ topics for real-time in-app updates |
| **Hub followers table** | Exists | `hub_followers` join table with `hub_id` + `user_id` |
| **Hub follower queries** | Exist | Count queries, preloading — but NO follow/unfollow functions |
| **User email field** | Exists | Email-auth users only; wallet-only users have no email |
| **User sms_opt_in** | Exists | Boolean, default true, set during phone verification |
| **Cart badge pattern** | Exists | Count badge on cart icon in header — reusable for notification bell |
| **BuxBalanceHook** | Exists | on_mount PubSub hook pattern — model for NotificationHook |

### What's Missing

| Component | Needed |
|-----------|--------|
| Notification preferences schema | User opt-in/out per channel per category |
| Notifications table | Persistent in-app notification records |
| Hub follow/unfollow functions | Context functions + LiveView handlers |
| Bell icon in header | UI component with dropdown |
| NotificationHook | on_mount hook for real-time delivery |
| Email campaign system | Templates, scheduling, batching, tracking |
| SMS notification sending | Extend Twilio beyond verification |
| Notification admin | Campaign builder, template editor, analytics |

---

## 3. Database Schema

### 3.1 Migration: `notification_preferences`

Per-user preferences controlling what they receive and how.

```elixir
create table(:notification_preferences) do
  add :user_id, references(:users, on_delete: :delete_all), null: false

  # Email preferences
  add :email_new_articles, :boolean, default: true
  add :email_hub_posts, :boolean, default: true
  add :email_special_offers, :boolean, default: true
  add :email_daily_digest, :boolean, default: true
  add :email_weekly_roundup, :boolean, default: true
  add :email_referral_prompts, :boolean, default: true
  add :email_reward_alerts, :boolean, default: true
  add :email_shop_deals, :boolean, default: true
  add :email_account_updates, :boolean, default: true
  add :email_re_engagement, :boolean, default: true

  # SMS preferences (sparingly used)
  add :sms_special_offers, :boolean, default: true
  add :sms_account_alerts, :boolean, default: true
  add :sms_milestone_rewards, :boolean, default: false

  # In-app preferences
  add :in_app_enabled, :boolean, default: true
  add :in_app_toast_enabled, :boolean, default: true
  add :in_app_sound_enabled, :boolean, default: false

  # Global controls
  add :email_enabled, :boolean, default: true
  add :sms_enabled, :boolean, default: true
  add :quiet_hours_start, :time, default: nil  # e.g., 22:00
  add :quiet_hours_end, :time, default: nil    # e.g., 08:00
  add :timezone, :string, default: "UTC"

  # Frequency controls
  add :max_emails_per_day, :integer, default: 3
  add :max_sms_per_week, :integer, default: 1

  # Unsubscribe token (for one-click email unsubscribe)
  add :unsubscribe_token, :string

  timestamps()
end

create unique_index(:notification_preferences, [:user_id])
create index(:notification_preferences, [:unsubscribe_token])
```

### 3.2 Migration: `notifications`

Persistent in-app notification records.

```elixir
create table(:notifications) do
  add :user_id, references(:users, on_delete: :delete_all), null: false
  add :type, :string, null: false          # "new_article", "hub_post", "promo", etc.
  add :category, :string, null: false      # "content", "offers", "social", "rewards", "system"
  add :title, :string, null: false
  add :body, :text
  add :image_url, :string                  # thumbnail/icon
  add :action_url, :string                 # link to navigate to
  add :action_label, :string               # "Read Article", "Shop Now", etc.

  # Metadata (flexible JSON for type-specific data)
  add :metadata, :map, default: %{}        # e.g., %{post_id: 123, hub_id: 5}

  # State
  add :read_at, :utc_datetime
  add :dismissed_at, :utc_datetime
  add :clicked_at, :utc_datetime

  # Delivery tracking
  add :email_sent_at, :utc_datetime
  add :sms_sent_at, :utc_datetime
  add :push_sent_at, :utc_datetime

  # Campaign linkage (nullable — not all notifications are from campaigns)
  add :campaign_id, references(:notification_campaigns, on_delete: :nilify_all)

  timestamps()
end

create index(:notifications, [:user_id, :read_at])
create index(:notifications, [:user_id, :inserted_at])
create index(:notifications, [:type])
create index(:notifications, [:campaign_id])
```

### 3.3 Migration: `notification_campaigns`

Admin-created campaigns for mass notifications.

```elixir
create table(:notification_campaigns) do
  add :name, :string, null: false
  add :type, :string, null: false          # "email_blast", "push_notification", "sms_blast", "multi_channel"
  add :status, :string, default: "draft"   # "draft", "scheduled", "sending", "sent", "cancelled"

  # Content
  add :subject, :string                    # email subject line
  add :title, :string                      # in-app notification title
  add :body, :text                         # rich content / HTML for email
  add :plain_text_body, :text              # plain text fallback
  add :image_url, :string
  add :action_url, :string
  add :action_label, :string

  # Targeting
  add :target_audience, :string, default: "all"  # "all", "hub_followers", "active_users", "dormant_users", "phone_verified", "custom"
  add :target_hub_id, references(:hubs, on_delete: :nilify_all)
  add :target_criteria, :map, default: %{}  # flexible filters: geo_tier, min_bux, etc.

  # Channels
  add :send_email, :boolean, default: true
  add :send_sms, :boolean, default: false
  add :send_in_app, :boolean, default: true

  # Scheduling
  add :scheduled_at, :utc_datetime
  add :sent_at, :utc_datetime
  add :timezone_aware, :boolean, default: true  # stagger by user timezone

  # Stats (denormalized for quick access)
  add :total_recipients, :integer, default: 0
  add :emails_sent, :integer, default: 0
  add :emails_opened, :integer, default: 0
  add :emails_clicked, :integer, default: 0
  add :sms_sent, :integer, default: 0
  add :in_app_delivered, :integer, default: 0
  add :in_app_read, :integer, default: 0

  add :created_by_id, references(:users, on_delete: :nilify_all)

  timestamps()
end

create index(:notification_campaigns, [:status])
create index(:notification_campaigns, [:scheduled_at])
```

### 3.4 Migration: `notification_email_log`

Track individual email sends for rate limiting and analytics.

```elixir
create table(:notification_email_log) do
  add :user_id, references(:users, on_delete: :delete_all), null: false
  add :notification_id, references(:notifications, on_delete: :nilify_all)
  add :campaign_id, references(:notification_campaigns, on_delete: :nilify_all)
  add :email_type, :string, null: false    # "digest", "promo", "hub_update", "referral", etc.
  add :subject, :string
  add :sent_at, :utc_datetime, null: false
  add :opened_at, :utc_datetime
  add :clicked_at, :utc_datetime
  add :bounced, :boolean, default: false
  add :unsubscribed, :boolean, default: false
  add :sendgrid_message_id, :string        # for tracking via SendGrid webhooks

  timestamps()
end

create index(:notification_email_log, [:user_id, :sent_at])
create index(:notification_email_log, [:campaign_id])
create index(:notification_email_log, [:sendgrid_message_id])
```

### 3.5 Migration: `hub_subscriptions` (enhance existing `hub_followers`)

Add notification preferences to hub follows.

```elixir
# Add columns to existing hub_followers table
alter table(:hub_followers) do
  add :notify_new_posts, :boolean, default: true
  add :notify_events, :boolean, default: true
  add :email_notifications, :boolean, default: true
  add :in_app_notifications, :boolean, default: true
end
```

---

## 4. Hub Subscribe Button

### 4.1 Context Functions

Add to `lib/blockster_v2/blog.ex`:

```elixir
# Follow / Unfollow
def follow_hub(user_id, hub_id)
def unfollow_hub(user_id, hub_id)
def toggle_hub_follow(user_id, hub_id)
def user_follows_hub?(user_id, hub_id)
def get_user_followed_hub_ids(user_id)

# Notification queries
def get_hub_follower_user_ids(hub_id)
def get_hub_followers_with_preferences(hub_id)
```

### 4.2 LiveView Changes — `hub_live/show.ex`

```elixir
# Mount: check if current user follows this hub
assign(socket, :user_follows_hub, Blog.user_follows_hub?(user.id, hub.id))

# Events:
def handle_event("toggle_follow", _, socket)  # follow/unfollow
def handle_event("update_hub_notifications", params, socket)  # per-hub notification settings
```

### 4.3 Subscribe Button UI — `hub_live/show.html.heex`

Replace the broken `onclick="toggleModal('shareModal')"` button with:

```heex
<%= if @current_user do %>
  <%= if @user_follows_hub do %>
    <button phx-click="toggle_follow" class="px-6 py-2.5 bg-[#CAFC00] text-black font-haas_medium_65
      rounded-full hover:bg-[#b8e600] transition-colors cursor-pointer flex items-center gap-2">
      <Heroicons.check_circle solid class="w-5 h-5" />
      Subscribed
    </button>
  <% else %>
    <button phx-click="toggle_follow" class="px-6 py-2.5 bg-[#141414] text-white font-haas_medium_65
      rounded-full hover:bg-[#2a2a2a] transition-colors cursor-pointer flex items-center gap-2">
      <Heroicons.bell solid class="w-5 h-5" />
      Subscribe
    </button>
  <% end %>
<% else %>
  <button phx-click="require_login" class="px-6 py-2.5 bg-[#141414] text-white font-haas_medium_65
    rounded-full hover:bg-[#2a2a2a] transition-colors cursor-pointer flex items-center gap-2">
    <Heroicons.bell solid class="w-5 h-5" />
    Subscribe
  </button>
<% end %>
```

### 4.4 Hub Post Notification Trigger

When a post is published to a hub, notify all followers:

```elixir
# In Blog context, after post publish:
def notify_hub_followers_of_new_post(post) do
  hub = get_hub!(post.hub_id)
  follower_ids = get_hub_follower_user_ids(hub.id)

  Enum.each(follower_ids, fn user_id ->
    Notifications.create_notification(user_id, %{
      type: "hub_post",
      category: "content",
      title: "New in #{hub.name}",
      body: post.title,
      image_url: post.featured_image,
      action_url: "/#{post.slug}",
      action_label: "Read Article",
      metadata: %{post_id: post.id, hub_id: hub.id}
    })
  end)
end
```

### 4.5 Hub Subscribe Count Display

Update the hub show page to display live follower count and animate on follow/unfollow.

### 4.6 "Subscribed Hubs" Feed

Add a personalized feed on the homepage or a dedicated `/feed` route showing posts from all hubs the user follows, sorted by recency.

---

## 5. In-App Notification System

### 5.1 NotificationHook (on_mount)

New file: `lib/blockster_v2_web/live/notification_hook.ex`

Follow the `BuxBalanceHook` pattern:

```elixir
defmodule BlocksterV2Web.NotificationHook do
  import Phoenix.LiveView

  def on_mount(:default, _params, _session, socket) do
    if connected?(socket) and socket.assigns[:current_user] do
      user_id = socket.assigns.current_user.id

      Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "notifications:#{user_id}")

      unread_count = BlocksterV2.Notifications.unread_count(user_id)

      socket =
        socket
        |> assign(:unread_notification_count, unread_count)
        |> assign(:notification_dropdown_open, false)
        |> assign(:recent_notifications, [])
        |> assign(:toast_notification, nil)
        |> attach_hook(:notification_handler, :handle_info, &handle_notification/2)

      {:cont, socket}
    else
      socket =
        socket
        |> assign(:unread_notification_count, 0)
        |> assign(:notification_dropdown_open, false)
        |> assign(:recent_notifications, [])
        |> assign(:toast_notification, nil)

      {:cont, socket}
    end
  end

  defp handle_notification({:new_notification, notification}, socket) do
    # Increment count, show toast, add to recent list
    {:halt,
     socket
     |> update(:unread_notification_count, &(&1 + 1))
     |> assign(:toast_notification, notification)
     |> update(:recent_notifications, &[notification | Enum.take(&1, 9)])}
  end

  defp handle_notification(_msg, socket), do: {:cont, socket}
end
```

Add to router on_mount chain (after BuxBalanceHook):
```elixir
on_mount [{SearchHook, :default}, {UserAuth, :mount_current_user},
          {BuxBalanceHook, :default}, {NotificationHook, :default}]
```

### 5.2 Bell Icon in Header

Add to `layouts.ex` `site_header/1`, placed between cart icon and user dropdown.

**Desktop** (after cart icon, before user dropdown):

```heex
<!-- Notification Bell -->
<div class="relative" id="notification-bell" phx-hook="NotificationBell">
  <button phx-click="toggle_notification_dropdown"
    class="relative flex items-center justify-center w-10 h-10 rounded-full bg-gray-100
    hover:bg-gray-200 transition-colors cursor-pointer">
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-5 h-5 text-[#141414]">
      <path fill-rule="evenodd" d="M5.25 9a6.75 6.75 0 0 1 13.5 0v.75c0 2.123.8 4.057 2.118
        5.52a.75.75 0 0 1-.297 1.206c-1.544.57-3.16.99-4.831 1.243a3.75 3.75 0 1 1-7.48
        0 24.585 24.585 0 0 1-4.831-1.244.75.75 0 0 1-.298-1.205A8.217 8.217 0 0 0 5.25
        9.75V9Zm4.502 8.9a2.25 2.25 0 1 0 4.496 0 25.057 25.057 0 0 1-4.496 0Z" clip-rule="evenodd" />
    </svg>
    <!-- Unread badge -->
    <%= if @unread_notification_count > 0 do %>
      <span class="absolute -top-1 -right-1 bg-red-500 text-white text-xs font-haas_medium_65
        rounded-full min-w-[18px] h-[18px] flex items-center justify-center px-1 animate-pulse"
        id="notification-badge">
        <%= if @unread_notification_count > 99, do: "99+", else: @unread_notification_count %>
      </span>
    <% end %>
  </button>

  <!-- Notification Dropdown -->
  <div id="notification-dropdown" class="hidden absolute right-0 top-12 w-96 bg-white rounded-2xl
    shadow-2xl border border-gray-100 z-50 overflow-hidden" phx-click-away="close_notification_dropdown">
    <!-- Header -->
    <div class="flex items-center justify-between px-4 py-3 border-b border-gray-100">
      <h3 class="font-haas_medium_65 text-[#141414]">Notifications</h3>
      <div class="flex items-center gap-2">
        <button phx-click="mark_all_notifications_read"
          class="text-xs text-gray-500 hover:text-[#141414] cursor-pointer">Mark all read</button>
        <a href="/notifications" class="text-xs text-blue-500 hover:underline">View all</a>
      </div>
    </div>
    <!-- Notification list (max 10 recent) -->
    <div class="max-h-[420px] overflow-y-auto divide-y divide-gray-50">
      <%= for notification <- @recent_notifications do %>
        <.notification_item notification={notification} />
      <% end %>
      <%= if @recent_notifications == [] do %>
        <div class="py-12 text-center text-gray-400 text-sm">
          No notifications yet
        </div>
      <% end %>
    </div>
    <!-- Footer -->
    <div class="px-4 py-3 border-t border-gray-100 bg-gray-50">
      <a href="/notifications/settings" class="text-xs text-gray-500 hover:text-[#141414] cursor-pointer">
        Notification Settings
      </a>
    </div>
  </div>
</div>
```

### 5.3 Toast Slide-In Notification

When a new notification arrives in real-time, show a toast in the top-right corner that slides in and auto-dismisses after 5 seconds.

```heex
<!-- Toast notification (rendered in app layout) -->
<%= if @toast_notification do %>
  <div id="notification-toast" class="fixed top-20 right-4 z-[100] w-80 bg-white rounded-xl shadow-2xl
    border border-gray-100 p-4 animate-slide-in-right cursor-pointer"
    phx-click="click_notification" phx-value-id={@toast_notification.id}
    phx-hook="NotificationToast">
    <div class="flex items-start gap-3">
      <%= if @toast_notification.image_url do %>
        <img src={@toast_notification.image_url} class="w-10 h-10 rounded-lg object-cover" />
      <% else %>
        <div class="w-10 h-10 rounded-lg bg-[#CAFC00] flex items-center justify-center">
          <svg class="w-5 h-5 text-black"><!-- bell icon --></svg>
        </div>
      <% end %>
      <div class="flex-1 min-w-0">
        <p class="font-haas_medium_65 text-sm text-[#141414] truncate"><%= @toast_notification.title %></p>
        <p class="text-xs text-gray-500 mt-0.5 line-clamp-2"><%= @toast_notification.body %></p>
      </div>
      <button phx-click="dismiss_toast" class="text-gray-400 hover:text-gray-600 cursor-pointer">
        <svg class="w-4 h-4"><!-- X icon --></svg>
      </button>
    </div>
    <!-- Auto-dismiss progress bar -->
    <div class="mt-2 h-0.5 bg-gray-100 rounded-full overflow-hidden">
      <div class="h-full bg-[#CAFC00] animate-shrink-width" style="animation-duration: 5s;"></div>
    </div>
  </div>
<% end %>
```

**CSS animations** (add to `assets/css/app.css`):

```css
@keyframes slide-in-right {
  from { transform: translateX(100%); opacity: 0; }
  to { transform: translateX(0); opacity: 1; }
}
@keyframes shrink-width {
  from { width: 100%; }
  to { width: 0%; }
}
.animate-slide-in-right { animation: slide-in-right 0.3s ease-out; }
.animate-shrink-width { animation: shrink-width linear forwards; }
```

### 5.4 Dedicated Notifications Page (`/notifications`)

Full-page notification center at `/notifications`:

- **Tabs**: All | Content | Offers | Social | Rewards | System
- **Filter**: Read / Unread / All
- **Bulk actions**: Mark selected as read, Dismiss selected
- **Infinite scroll** (reuse existing `InfiniteScroll` hook)
- **Each notification**: Image, title, body, timestamp ("2m ago"), action button, read/unread indicator
- **Empty state**: "You're all caught up!" with illustration

### 5.5 Notification Settings Page (`/notifications/settings`)

User-facing preference management:

- **Email section**: Toggle each email type (articles, hub posts, offers, digest, referral prompts, etc.)
- **SMS section**: Toggle each SMS type (offers, alerts, milestones)
- **In-app section**: Toggle toasts, sounds
- **Quiet hours**: Set start/end times + timezone
- **Frequency**: Max emails per day slider (1-5, default 3)
- **Hub-specific**: List of subscribed hubs with per-hub notification toggles
- **One-click unsubscribe all**: Prominent option with confirmation

### 5.6 JS Hook: NotificationBell

```javascript
// assets/js/hooks/notification_bell.js
export const NotificationBell = {
  mounted() {
    // Animate badge on new notification
    this.handleEvent("new_notification", ({count}) => {
      const badge = document.getElementById("notification-badge")
      if (badge) {
        badge.classList.remove("animate-pulse")
        void badge.offsetWidth // trigger reflow
        badge.classList.add("animate-pulse")
      }
      // Optional: browser notification sound
      if (this.el.dataset.soundEnabled === "true") {
        new Audio("/sounds/notification.mp3").play().catch(() => {})
      }
    })
  }
}
```

### 5.7 JS Hook: NotificationToast

```javascript
// assets/js/hooks/notification_toast.js
export const NotificationToast = {
  mounted() {
    // Auto-dismiss after 5 seconds
    this.timer = setTimeout(() => {
      this.pushEvent("dismiss_toast", {})
    }, 5000)

    // Pause timer on hover
    this.el.addEventListener("mouseenter", () => clearTimeout(this.timer))
    this.el.addEventListener("mouseleave", () => {
      this.timer = setTimeout(() => {
        this.pushEvent("dismiss_toast", {})
      }, 3000)
    })
  },
  destroyed() {
    clearTimeout(this.timer)
  }
}
```

---

## 6. Email System

### 6.1 Email Types & Templates

| Email Type | Frequency | Content | Priority |
|------------|-----------|---------|----------|
| **Daily Digest** | 1x/day (morning) | Top 3-5 articles from followed hubs + trending | High |
| **New Article Alert** | As published (batched) | Single article from followed hub | Medium |
| **Special Offer** | 2-3x/week | Shop deals, limited promos, flash sales | High |
| **Referral Prompt** | 1x/week | "Invite friends, earn BUX" with personalized link | Medium |
| **Reward Summary** | 1x/week | "You earned X BUX this week" with breakdown | Medium |
| **Re-engagement** | After 3/7/14/30 days inactive | "You missed this" + top content | Medium |
| **Welcome Series** | Days 1, 3, 5, 7 after signup | Onboarding tips, feature discovery | High |
| **Hub Recommendation** | 1x/week | "Based on your reading, you might like..." | Low |
| **Shop Newsletter** | 1-2x/week | New products, restocks, curated picks | Medium |
| **BUX Milestone** | On achievement | "You hit 10,000 BUX!" celebration | Low |
| **Event Reminder** | Before hub events | "Event starting in 24h / 1h" | Medium |
| **Order Updates** | On status change | Shipping confirmation, delivery updates | High |
| **Account Security** | On suspicious activity | Login from new device, password change | Critical |

### 6.2 Email Template System

Create a base email template module: `lib/blockster_v2/notifications/email_templates.ex`

**Base layout** — all emails share:
- Blockster logo header with brand color (#CAFC00) accent
- Responsive HTML (mobile-first, max-width 600px)
- Dark mode support (`@media (prefers-color-scheme: dark)`)
- One-click unsubscribe link (via `unsubscribe_token`)
- "Manage preferences" link to `/notifications/settings`
- Physical address footer (CAN-SPAM compliance)
- Tracking pixel for open tracking (via SendGrid)

**Template variants:**
1. **Single Article** — hero image, title, excerpt, "Read More" CTA
2. **Digest** — 3-5 article cards in a vertical stack
3. **Promotional** — large hero banner, offer details, "Shop Now" CTA
4. **Referral** — social share buttons, personalized referral link, reward explanation
5. **Summary/Stats** — BUX earned chart, reading stats, achievements
6. **Minimal** — text-focused for account alerts and transactional emails

### 6.3 Email Delivery Pipeline

```
[Trigger] → [NotificationWorker (Oban)] → [Rate Limiter] → [Template Renderer] → [Swoosh/SendGrid] → [Log]
```

**Oban job queues:**

```elixir
# config/config.exs
config :blockster_v2, Oban,
  queues: [
    default: 10,
    email_transactional: 5,   # order updates, security alerts
    email_marketing: 3,        # promos, digests, referral prompts
    email_digest: 2,           # daily/weekly digests (batched)
    sms: 1,                    # SMS sending (rate limited)
    notifications: 5           # in-app notification creation
  ]
```

### 6.4 Daily Digest Worker

```elixir
defmodule BlocksterV2.Workers.DailyDigestWorker do
  use Oban.Worker, queue: :email_digest, max_attempts: 3

  # Scheduled via Oban cron at 9:00 AM UTC
  # Staggers by user timezone (sends at ~9 AM local)

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    users = Notifications.get_digest_eligible_users()

    Enum.each(users, fn user ->
      local_hour = get_user_local_hour(user)

      if local_hour_in_range?(local_hour, 8, 10) do
        # Send now
        send_digest(user)
      else
        # Schedule for user's morning
        delay = calculate_delay_to_morning(user)
        %{user_id: user.id}
        |> __MODULE__.new(schedule_in: delay)
        |> Oban.insert()
      end
    end)
  end

  defp send_digest(user) do
    articles = get_personalized_articles(user)
    unless Enum.empty?(articles) do
      Notifications.send_email(user, :daily_digest, %{articles: articles})
    end
  end
end
```

### 6.5 Promotional Email Worker

```elixir
defmodule BlocksterV2.Workers.PromoEmailWorker do
  use Oban.Worker, queue: :email_marketing, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"campaign_id" => campaign_id}}) do
    campaign = Notifications.get_campaign!(campaign_id)
    recipients = Notifications.get_campaign_recipients(campaign)

    Enum.each(recipients, fn user ->
      if Notifications.can_send_email?(user) do
        Notifications.send_campaign_email(user, campaign)
      end
    end)

    Notifications.update_campaign(campaign, %{status: "sent", sent_at: DateTime.utc_now()})
  end
end
```

### 6.6 Welcome Series

Triggered on user registration. 4-email sequence:

| Day | Subject | Content |
|-----|---------|---------|
| 0 (immediate) | "Welcome to Blockster!" | Account setup tips, first hub to follow, earn your first BUX |
| 3 | "You're earning BUX by reading" | Explain engagement system, show BUX balance, suggest articles |
| 5 | "Discover your hubs" | Personalized hub recommendations based on reading history |
| 7 | "Invite friends, earn together" | Referral link + bonus BUX for first referral |

### 6.7 Re-engagement Campaigns

Automated win-back emails triggered by inactivity:

| Days Inactive | Subject | Strategy |
|---------------|---------|----------|
| 3 | "You have unread articles from your hubs" | Show new hub posts they missed |
| 7 | "Your BUX are waiting" | Show accumulated unclaimed rewards |
| 14 | "We miss you! Here's what's new" | Top content digest + exclusive offer |
| 30 | "Special welcome back offer" | Bonus BUX or shop discount to return |

### 6.8 SendGrid Webhook Integration

Handle delivery events for analytics:

```elixir
# New route: POST /webhooks/sendgrid
def handle_sendgrid_webhook(conn, params) do
  Enum.each(params, fn event ->
    case event["event"] do
      "open" -> Notifications.mark_email_opened(event["sg_message_id"])
      "click" -> Notifications.mark_email_clicked(event["sg_message_id"])
      "bounce" -> Notifications.mark_email_bounced(event["sg_message_id"])
      "unsubscribe" -> Notifications.handle_email_unsubscribe(event["sg_message_id"])
      _ -> :ok
    end
  end)
end
```

---

## 7. SMS System

### 7.1 Usage Policy — Sparingly

SMS is expensive and intrusive. Reserved for **high-value, time-sensitive** notifications only.

**Maximum**: 1 SMS per week per user (configurable in preferences).

### 7.2 SMS-Eligible Notifications

| Type | Trigger | Example |
|------|---------|---------|
| **Flash Sale** | Admin-triggered | "50% off all merch for 2 hours! Shop now: link" |
| **BUX Milestone** | Automated | "You hit 100,000 BUX! Claim your reward: link" |
| **Order Shipped** | Status change | "Your Blockster order shipped! Track: link" |
| **Account Security** | Suspicious login | "New login detected. Not you? Secure: link" |
| **Exclusive Drop** | Admin-triggered | "Limited edition drop in 1 hour! link" |

### 7.3 SMS Sending Module

Extend existing `TwilioClient` with general SMS sending (separate from verification):

```elixir
defmodule BlocksterV2.SmsNotifier do
  @max_sms_length 160

  def send_sms(phone_number, message) when byte_size(message) <= @max_sms_length do
    # Use Twilio Messages API (not Verify)
    # Requires TWILIO_MESSAGING_SERVICE_SID or FROM number
    TwilioClient.send_message(phone_number, message)
  end

  def can_send_sms?(user) do
    user.phone_verified &&
    user.sms_opt_in &&
    prefs = Notifications.get_preferences(user.id)
    prefs.sms_enabled &&
    within_sms_limit?(user.id, prefs.max_sms_per_week)
  end
end
```

### 7.4 SMS Opt-Out

- Every SMS includes "Reply STOP to unsubscribe"
- Handle Twilio opt-out webhook to update `sms_opt_in` field
- Also manageable from notification settings page

---

## 8. Notification Types Catalog

### 8.1 Content Notifications (category: "content")

| Type | Trigger | Channels | Data |
|------|---------|----------|------|
| `new_article` | Post published (trending/featured) | In-app, Email digest | post_id, hub_id |
| `hub_post` | Post published in followed hub | In-app, Email | post_id, hub_id |
| `hub_event` | New event in followed hub | In-app, Email | event_id, hub_id |
| `content_recommendation` | ML/manual curation | In-app, Email | post_ids |
| `weekly_roundup` | Weekly cron | Email | top post_ids |

### 8.2 Offer Notifications (category: "offers")

| Type | Trigger | Channels | Data |
|------|---------|----------|------|
| `special_offer` | Admin campaign | In-app, Email, SMS (rare) | offer details, discount_code |
| `flash_sale` | Admin campaign | In-app, Email, SMS | sale details, end_time |
| `shop_new_product` | Product published | In-app, Email | product_id |
| `shop_restock` | Product restocked | In-app, Email | product_id |
| `price_drop` | Price reduced on viewed product | In-app, Email | product_id, old_price, new_price |
| `cart_abandonment` | Cart idle >2 hours | In-app, Email | cart_items |

### 8.3 Social Notifications (category: "social")

| Type | Trigger | Channels | Data |
|------|---------|----------|------|
| `referral_prompt` | Weekly cron / milestone | In-app, Email | referral_link |
| `referral_signup` | Referred user joins | In-app, Email | referrer_id, new_user_name |
| `referral_reward` | Referral bonus earned | In-app | bux_amount |
| `hub_milestone` | Hub hits follower milestone | In-app | hub_id, milestone |

### 8.4 Reward Notifications (category: "rewards")

| Type | Trigger | Channels | Data |
|------|---------|----------|------|
| `bux_earned` | Reading reward | In-app (toast only) | bux_amount, post_id |
| `bux_milestone` | Balance milestone (1k, 10k, etc.) | In-app, Email, SMS | milestone_amount |
| `reward_summary` | Weekly cron | Email | weekly_stats |
| `multiplier_upgrade` | Geo tier change | In-app, Email | new_multiplier |
| `game_settlement` | BuxBooster bet settled | In-app | game_id, result, payout |

### 8.5 System Notifications (category: "system")

| Type | Trigger | Channels | Data |
|------|---------|----------|------|
| `order_confirmed` | Order paid | In-app, Email | order_id |
| `order_shipped` | Order shipped | In-app, Email, SMS | order_id, tracking |
| `order_delivered` | Order delivered | In-app, Email | order_id |
| `welcome` | Registration | Email | - |
| `account_security` | Suspicious activity | Email, SMS | details |
| `maintenance` | Planned downtime | In-app, Email | schedule |

---

## 9. Smart Scheduling & Frequency Engine

### 9.1 Rate Limiter

```elixir
defmodule BlocksterV2.Notifications.RateLimiter do
  # Check before every email/SMS send
  def can_send?(user_id, channel, type) do
    prefs = get_preferences(user_id)

    cond do
      channel == :email and not prefs.email_enabled -> false
      channel == :sms and not prefs.sms_enabled -> false
      channel == :email and email_count_today(user_id) >= prefs.max_emails_per_day -> false
      channel == :sms and sms_count_this_week(user_id) >= prefs.max_sms_per_week -> false
      in_quiet_hours?(prefs) -> :defer  # reschedule for after quiet hours
      type_disabled?(prefs, channel, type) -> false
      true -> true
    end
  end
end
```

### 9.2 Priority System

When multiple notifications compete for limited daily email slots:

| Priority | Types | Rule |
|----------|-------|------|
| **Critical** | Account security, order updates | Always send immediately, doesn't count toward limit |
| **High** | Daily digest, special offers | First 1-2 email slots |
| **Medium** | Hub posts, referral prompts, reward summary | Remaining slots |
| **Low** | Recommendations, re-engagement | Only if slots available |

### 9.3 Timezone-Aware Delivery

```elixir
defmodule BlocksterV2.Notifications.Scheduler do
  # Preferred delivery windows (user's local time)
  @morning_window {8, 10}   # Digest
  @midday_window {11, 14}   # Promo/offers
  @evening_window {17, 19}  # Engagement/social

  def schedule_for_window(user, type) do
    window = get_window(type)
    tz = user.notification_preferences.timezone || "UTC"
    # Calculate delay to next window opening in user's timezone
    # Schedule Oban job with calculated delay
  end
end
```

### 9.4 Smart Batching

Instead of sending individual emails for each hub post, batch them:

- **Hub posts**: Collect for 2-4 hours, then send one "New from your hubs" email
- **Rewards**: Aggregate into weekly summary instead of per-reward emails
- **Recommendations**: Bundle 3-5 suggestions into one email

### 9.5 A/B Testing Support

```elixir
# Campaign supports variants
add :variant, :string  # "A", "B", "C"
add :variant_config, :map  # %{subject_variants: [...], body_variants: [...]}

# Assign users to variants
def assign_variant(user_id, campaign) do
  rem(:erlang.phash2(user_id), length(campaign.variants))
end
```

---

## 10. Referral Prompting System

### 10.1 Referral Notification Strategy

**Goal**: Regularly remind users to invite friends without being annoying.

| Trigger | Message | Channel |
|---------|---------|---------|
| Weekly cron (Tuesdays) | "Invite friends, earn 500 BUX per signup" | Email |
| After earning BUX milestone | "Share the love! Refer friends and both earn BUX" | In-app |
| After first purchase | "Know someone who'd love this? Share and save" | Email |
| After 7 days without referral | "Your referral link hasn't been used yet" | In-app |
| Referral joins | "Your friend X just joined! Here's your reward" | In-app, Email |

### 10.2 Referral Link in Every Email

Every marketing email includes a footer section:

```html
<div style="background: #CAFC00; padding: 16px; text-align: center; border-radius: 8px;">
  <p style="font-weight: bold; color: #141414;">Share Blockster, Earn BUX</p>
  <p>Your referral link: <a href="https://blockster.com?ref=USER_CODE">blockster.com?ref=USER_CODE</a></p>
  <p>You earn 500 BUX for every friend who joins!</p>
</div>
```

### 10.3 Social Share Buttons in Notifications

In-app notifications for referral include quick-share buttons:
- Copy link
- Share on X (Twitter)
- Share on Telegram
- Share via email

---

## 11. Admin Campaign Interface

### 11.1 Routes

```elixir
live "/admin/notifications", NotificationAdminLive.Index, :index
live "/admin/notifications/campaigns", CampaignAdminLive.Index, :index
live "/admin/notifications/campaigns/new", CampaignAdminLive.New, :new
live "/admin/notifications/campaigns/:id", CampaignAdminLive.Show, :show
live "/admin/notifications/campaigns/:id/edit", CampaignAdminLive.Edit, :edit
live "/admin/notifications/templates", TemplateAdminLive.Index, :index
live "/admin/notifications/analytics", NotificationAnalyticsLive.Index, :index
```

### 11.2 Campaign Builder

Admin page to create notification campaigns:

**Step 1: Content**
- Subject line (with emoji picker)
- Title (for in-app notification)
- Body (rich text editor — reuse TipTap)
- Image upload
- Action URL + label
- Preview (desktop + mobile + email)

**Step 2: Audience**
- Target: All users / Hub followers / Active users (last 7d) / Dormant users / Phone verified / Custom
- Custom filters: geo_tier, min_bux_balance, registered_before/after, has_purchased, hub_subscriptions
- Estimated recipient count shown live

**Step 3: Channels**
- Checkboxes: Email / In-app / SMS
- Email-specific: Subject line, preview text
- SMS-specific: Short message (160 char limit, char counter)

**Step 4: Schedule**
- Send now / Schedule for date+time
- Timezone-aware delivery toggle
- A/B test toggle (with variant editor)

**Step 5: Review & Send**
- Summary of all settings
- "Send Test" button (sends to admin's email)
- "Schedule" or "Send Now" button

### 11.3 Campaign Dashboard

Overview showing:
- Active campaigns with stats (sent, opened, clicked)
- Scheduled campaigns (with edit/cancel)
- Campaign performance chart (opens, clicks over time)
- Top performing campaigns (by click rate)

### 11.4 Quick Send

For fast notifications without full campaign setup:
- One-line form: "Send notification to [audience] saying [message] via [channels]"
- Pre-built templates for common notifications (new article, flash sale, etc.)

### 11.5 Template Manager

- List of saved templates
- Create/edit templates with live preview
- Template categories: Article, Offer, Referral, Digest, Alert
- Variable interpolation: `{{user.name}}`, `{{bux_balance}}`, `{{referral_link}}`, `{{hub.name}}`

---

## 12. Analytics & Tracking

### 12.1 Dashboard Metrics

**Notification Admin Dashboard** (`/admin/notifications`):

**Overall Stats:**
- Emails sent today / this week / this month
- Average open rate (7-day rolling)
- Average click rate (7-day rolling)
- SMS sent this week
- In-app delivery rate
- Unsubscribe rate

**Charts:**
- Email volume over time (line chart)
- Open rate trend (line chart)
- Best performing notification types (bar chart)
- Send time heatmap (which hours get best engagement)
- Channel comparison (email vs in-app vs SMS engagement)

**User Engagement:**
- Users with notifications enabled (by channel)
- Hub subscription distribution
- Most subscribed hubs
- Notification preference breakdown

### 12.2 Per-Campaign Analytics

- Recipient count vs. delivered vs. opened vs. clicked
- Open rate by time-of-day
- Click heatmap on email (if using SendGrid click tracking)
- A/B variant performance comparison
- Revenue attributed (if action_url leads to shop)

### 12.3 SendGrid Event Tracking

| Event | Action |
|-------|--------|
| `delivered` | Update email_log |
| `open` | Update email_log.opened_at, increment campaign.emails_opened |
| `click` | Update email_log.clicked_at, increment campaign.emails_clicked |
| `bounce` | Mark email as bounced, suppress future sends |
| `spam_report` | Auto-unsubscribe user from all marketing |
| `unsubscribe` | Update user preferences |

### 12.4 Engagement Scoring

Track notification engagement to personalize future sends:

```elixir
# User engagement score based on notification interaction
defmodule BlocksterV2.Notifications.EngagementScorer do
  def calculate_score(user_id) do
    %{
      email_open_rate: email_opens_last_30d(user_id) / emails_sent_last_30d(user_id),
      email_click_rate: email_clicks_last_30d(user_id) / emails_sent_last_30d(user_id),
      in_app_read_rate: in_app_reads_last_30d(user_id) / in_app_sent_last_30d(user_id),
      preferred_time: most_active_hour(user_id),
      preferred_categories: top_clicked_categories(user_id)
    }
  end
end
```

Use engagement score to:
- Adjust email frequency (highly engaged users get more, low-engaged get fewer)
- Optimize send time per user
- Choose which content types to include in digest
- Decide when to trigger re-engagement vs. leave alone

---

## 13. AI-Driven Personalization & User Behavior Engine

This is the brain of the entire notification system. Every user action is tracked, scored, and fed into a personalization engine that determines **what** each user sees, **when** they see it, and **how** it's framed — then measures the result to continuously optimize.

### 13.1 User Action Tracking — The Event Stream

Every meaningful user action is captured as a structured event and stored for analysis. This is the raw fuel for all personalization.

#### 13.1.1 Migration: `user_events`

```elixir
create table(:user_events) do
  add :user_id, references(:users, on_delete: :delete_all), null: false
  add :event_type, :string, null: false       # see catalog below
  add :event_category, :string, null: false   # "content", "shop", "social", "engagement", "navigation"
  add :target_type, :string                   # "post", "product", "hub", "notification", "email", "page"
  add :target_id, :string                     # polymorphic: post_id, product_id, hub_id, etc.
  add :metadata, :map, default: %{}           # event-specific data (see examples below)
  add :session_id, :string                    # group events by session
  add :source, :string                        # "web", "email", "sms", "push", "direct"
  add :referrer, :string                      # what led them here (notification_id, campaign_id, utm_source)

  timestamps(updated_at: false)               # events are append-only, no updates
end

create index(:user_events, [:user_id, :inserted_at])
create index(:user_events, [:user_id, :event_type])
create index(:user_events, [:event_type, :inserted_at])
create index(:user_events, [:target_type, :target_id])
create index(:user_events, [:session_id])
```

#### 13.1.2 Event Type Catalog — Everything We Track

**Content Events:**

| Event Type | Trigger | Metadata | What It Tells Us |
|------------|---------|----------|------------------|
| `article_view` | User opens an article | `%{post_id, hub_id, category_id, read_duration_ms: nil}` | What topics/hubs they're interested in |
| `article_read_complete` | Engagement tracker fires "complete" | `%{post_id, hub_id, read_duration_ms, scroll_depth_pct, engagement_score}` | They actually read it (not just clicked) |
| `article_read_partial` | User leaves mid-read | `%{post_id, hub_id, read_duration_ms, scroll_depth_pct, exit_point}` | Interest level, attention span |
| `article_share` | User shares article (X, copy link) | `%{post_id, platform, share_type}` | Content they find share-worthy |
| `article_bookmark` | User bookmarks (future feature) | `%{post_id}` | Content they want to return to |
| `video_watch` | Video watch tracker fires | `%{post_id, watch_duration_ms, total_duration_ms, completion_pct}` | Video content preferences |
| `category_browse` | User clicks a category filter | `%{category_id, category_name}` | Topic interests |

**Shop Events:**

| Event Type | Trigger | Metadata | What It Tells Us |
|------------|---------|----------|------------------|
| `product_view` | User opens product page | `%{product_id, product_slug, price, currency}` | What products attract them |
| `product_view_duration` | User stays on product page >10s | `%{product_id, duration_ms}` | Serious product interest |
| `product_add_to_cart` | Item added to cart | `%{product_id, variant_id, quantity, price}` | Purchase intent |
| `product_remove_from_cart` | Item removed from cart | `%{product_id, variant_id}` | Changed mind / price sensitivity |
| `cart_view` | User visits cart page | `%{item_count, cart_total}` | Considering checkout |
| `checkout_start` | User begins checkout | `%{cart_total, item_count, payment_method}` | High purchase intent |
| `checkout_abandon` | User leaves checkout without paying | `%{cart_total, step_abandoned, time_on_checkout_ms}` | Friction point identification |
| `purchase_complete` | Order paid | `%{order_id, total, payment_method, item_count}` | Buyer — highest value signal |
| `product_search` | User searches in shop | `%{query, results_count}` | What they're looking for |

**Hub & Social Events:**

| Event Type | Trigger | Metadata | What It Tells Us |
|------------|---------|----------|------------------|
| `hub_view` | User visits hub page | `%{hub_id, hub_slug}` | Hub interest |
| `hub_subscribe` | User follows a hub | `%{hub_id}` | Committed interest in hub topic |
| `hub_unsubscribe` | User unfollows a hub | `%{hub_id, days_subscribed}` | Lost interest — trigger analysis |
| `referral_link_copy` | User copies referral link | `%{referral_code}` | Willing to share |
| `referral_link_share` | User shares via platform | `%{referral_code, platform}` | Active advocate |
| `referral_conversion` | Referred user signs up | `%{referred_user_id, referral_code}` | Successful advocate |

**Engagement & Reward Events:**

| Event Type | Trigger | Metadata | What It Tells Us |
|------------|---------|----------|------------------|
| `bux_earned` | BUX reward minted | `%{amount, source: :read/:share/:signup, post_id}` | Reward-motivated behavior |
| `bux_spent` | BUX used for purchase | `%{amount, order_id}` | BUX as currency — engaged shopper |
| `game_played` | BuxBooster game session | `%{game_id, bet_amount, token, result, payout}` | Gamification engagement |
| `multiplier_earned` | Multiplier upgrade | `%{old_multiplier, new_multiplier, source}` | Engagement milestone |
| `daily_login` | First page view of the day | `%{consecutive_days}` | Retention signal |
| `session_start` | New session detected | `%{device_type, browser, referrer_url}` | Traffic source, device preference |
| `session_end` | Session timeout (30 min idle) | `%{duration_ms, pages_viewed, events_count}` | Session depth |

**Notification Interaction Events:**

| Event Type | Trigger | Metadata | What It Tells Us |
|------------|---------|----------|------------------|
| `notification_received` | In-app notification created | `%{notification_id, type, category}` | Delivery tracking |
| `notification_viewed` | Toast shown or dropdown opened | `%{notification_id, type, view_source: :toast/:dropdown}` | Attention capture rate |
| `notification_clicked` | User clicks notification action | `%{notification_id, type, action_url}` | Notification effectiveness |
| `notification_dismissed` | User dismisses without clicking | `%{notification_id, type}` | Notification fatigue signal |
| `email_opened` | SendGrid open event | `%{email_log_id, campaign_id, email_type}` | Email engagement |
| `email_clicked` | SendGrid click event | `%{email_log_id, campaign_id, email_type, clicked_url}` | Email CTA effectiveness |
| `email_unsubscribed` | User unsubscribes via email | `%{email_type, campaign_id}` | Fatigue — reduce frequency |
| `sms_clicked` | SMS link click (via redirect) | `%{sms_type, campaign_id}` | SMS effectiveness |

#### 13.1.3 Event Capture Implementation

**Server-side capture** — hook into existing systems:

```elixir
defmodule BlocksterV2.UserEvents do
  @doc "Fire-and-forget event tracking. Never blocks the caller."
  def track(user_id, event_type, metadata \\ %{}) do
    Task.start(fn ->
      %{
        user_id: user_id,
        event_type: event_type,
        event_category: categorize(event_type),
        target_type: metadata[:target_type],
        target_id: to_string(metadata[:target_id]),
        metadata: Map.drop(metadata, [:target_type, :target_id]),
        session_id: metadata[:session_id],
        source: metadata[:source] || "web",
        referrer: metadata[:referrer]
      }
      |> BlocksterV2.Notifications.UserEvent.changeset()
      |> BlocksterV2.Repo.insert()
    end)
  end

  # Batch insert for high-volume events (engagement ticks, etc.)
  def track_batch(events) do
    Task.start(fn ->
      Repo.insert_all(:user_events, events, on_conflict: :nothing)
    end)
  end
end
```

**Client-side capture** — JS hook for page-level events:

```javascript
// assets/js/hooks/event_tracker.js
export const EventTracker = {
  mounted() {
    // Track product view duration
    this.viewStart = Date.now()
    this.tracked = false

    // Track >10s product views
    if (this.el.dataset.trackType === "product_view") {
      this.timer = setTimeout(() => {
        this.pushEvent("track_event", {
          type: "product_view_duration",
          target_type: "product",
          target_id: this.el.dataset.targetId,
          metadata: { duration_ms: Date.now() - this.viewStart }
        })
        this.tracked = true
      }, 10000)
    }
  },
  destroyed() {
    clearTimeout(this.timer)
    // Track partial reads / early exits
    if (!this.tracked && this.el.dataset.trackType === "article_view") {
      const duration = Date.now() - this.viewStart
      if (duration > 3000) { // Only track if they stayed >3s
        navigator.sendBeacon("/api/track", JSON.stringify({
          type: "article_read_partial",
          target_id: this.el.dataset.targetId,
          metadata: { read_duration_ms: duration, scroll_depth_pct: this.getScrollDepth() }
        }))
      }
    }
  },
  getScrollDepth() {
    const scrollTop = window.scrollY
    const docHeight = document.documentElement.scrollHeight - window.innerHeight
    return Math.round((scrollTop / docHeight) * 100)
  }
}
```

#### 13.1.4 Event Aggregation & User Profile Building

Raw events are aggregated into a **user profile** that powers all personalization decisions. Recalculated periodically (every 6 hours) by an Oban worker.

**Migration: `user_profiles`**

```elixir
create table(:user_profiles) do
  add :user_id, references(:users, on_delete: :delete_all), null: false

  # Content preferences (derived from reading behavior)
  add :preferred_categories, {:array, :map}, default: []    # [%{id: 1, name: "DeFi", score: 0.85}, ...]
  add :preferred_hubs, {:array, :map}, default: []           # [%{id: 5, name: "Rogue Chain", score: 0.92}, ...]
  add :preferred_tags, {:array, :map}, default: []           # [%{id: 12, name: "NFTs", score: 0.7}, ...]
  add :avg_read_duration_ms, :integer, default: 0
  add :avg_scroll_depth_pct, :integer, default: 0
  add :content_completion_rate, :float, default: 0.0         # % of articles they finish reading
  add :articles_read_last_7d, :integer, default: 0
  add :articles_read_last_30d, :integer, default: 0
  add :total_articles_read, :integer, default: 0

  # Shopping behavior
  add :shop_interest_score, :float, default: 0.0             # 0-1 based on shop browsing
  add :avg_cart_value, :decimal                               # average cart value
  add :purchase_count, :integer, default: 0
  add :total_spent, :decimal, default: Decimal.new("0")
  add :viewed_products_last_30d, {:array, :integer}, default: []  # product_ids
  add :carted_not_purchased, {:array, :integer}, default: []      # product_ids in cart but never bought
  add :price_sensitivity, :string, default: "unknown"        # "low", "medium", "high" (based on cart abandonment at what prices)
  add :preferred_payment_method, :string                     # "bux", "rogue", "helio"

  # Engagement patterns
  add :engagement_tier, :string, default: "new"              # "new", "casual", "active", "power", "whale", "dormant", "churned"
  add :engagement_score, :float, default: 0.0                # 0-100 composite score
  add :last_active_at, :utc_datetime
  add :days_since_last_active, :integer, default: 0
  add :avg_sessions_per_week, :float, default: 0.0
  add :avg_session_duration_ms, :integer, default: 0
  add :consecutive_active_days, :integer, default: 0
  add :lifetime_days, :integer, default: 0                   # days since registration

  # Notification responsiveness
  add :email_open_rate_30d, :float, default: 0.0
  add :email_click_rate_30d, :float, default: 0.0
  add :in_app_click_rate_30d, :float, default: 0.0
  add :best_email_hour_utc, :integer                         # hour (0-23) with highest open rate
  add :best_email_day, :string                               # day of week with highest open rate
  add :notification_fatigue_score, :float, default: 0.0      # 0-1, high = they're ignoring/dismissing
  add :preferred_content_in_email, {:array, :string}, default: []  # ["articles", "offers", "rewards"]

  # Referral behavior
  add :referral_propensity, :float, default: 0.0             # 0-1, likelihood to refer
  add :referrals_sent, :integer, default: 0
  add :referrals_converted, :integer, default: 0

  # BUX & gamification
  add :bux_balance, :decimal, default: Decimal.new("0")
  add :bux_earned_last_30d, :decimal, default: Decimal.new("0")
  add :games_played_last_30d, :integer, default: 0
  add :gamification_score, :float, default: 0.0              # how much they engage with BUX/games

  # Recalculation tracking
  add :last_calculated_at, :utc_datetime
  add :events_since_last_calc, :integer, default: 0

  timestamps()
end

create unique_index(:user_profiles, [:user_id])
create index(:user_profiles, [:engagement_tier])
create index(:user_profiles, [:engagement_score])
create index(:user_profiles, [:last_active_at])
```

#### 13.1.5 Engagement Tier Classification

```elixir
defmodule BlocksterV2.Notifications.ProfileEngine do
  @doc "Classify user into engagement tier based on behavior signals"
  def classify_engagement_tier(profile) do
    cond do
      profile.days_since_last_active > 30 -> "churned"
      profile.days_since_last_active > 14 -> "dormant"
      profile.lifetime_days < 7 -> "new"
      profile.avg_sessions_per_week < 0.5 -> "casual"
      profile.avg_sessions_per_week < 3 and profile.purchase_count == 0 -> "casual"
      profile.avg_sessions_per_week >= 3 and profile.purchase_count > 0 -> "power"
      profile.total_spent > Decimal.new("100") or profile.purchase_count > 5 -> "whale"
      true -> "active"
    end
  end
end
```

| Tier | Criteria | Notification Strategy |
|------|----------|----------------------|
| **new** | <7 days old | Welcome series, onboarding tips, gentle nudges, hub recommendations |
| **casual** | <0.5 sessions/week, no purchases | Re-engage with top content, BUX rewards, easy wins |
| **active** | 1-3 sessions/week | Full engagement: digests, offers, referral prompts |
| **power** | 3+ sessions/week, has purchased | Priority access, exclusive offers, ambassador prompts |
| **whale** | >$100 spent or >5 purchases | VIP treatment, early access, personal offers, low frequency (don't annoy) |
| **dormant** | 14-30 days inactive | Re-engagement sequence: missed content, BUX waiting, special offer |
| **churned** | >30 days inactive | Last-chance win-back: aggressive offer, then reduce to monthly |

### 13.2 AI Content Personalization Engine

The personalization engine selects, ranks, and frames content for each individual user across all channels.

#### 13.2.1 Content Selection Algorithm

For every email/notification, the engine answers: "What content will this specific user most likely engage with?"

```elixir
defmodule BlocksterV2.Notifications.ContentSelector do
  @doc """
  Selects the best N articles for a user based on their profile.
  Used by: Daily Digest, Hub Post Alerts, Recommendations, Re-engagement.
  Returns articles ranked by personalized relevance score.
  """
  def select_articles(user_id, opts \\ []) do
    count = opts[:count] || 5
    since = opts[:since] || days_ago(1)  # articles published since
    pool = opts[:pool] || :all           # :all, :hub_subscriptions, :trending

    profile = Profiles.get_profile!(user_id)
    candidate_articles = get_candidate_pool(pool, user_id, since)

    candidate_articles
    |> Enum.map(fn article ->
      score = calculate_relevance_score(article, profile)
      {article, score}
    end)
    |> Enum.sort_by(fn {_, score} -> score end, :desc)
    |> Enum.reject(fn {article, _} -> already_read?(user_id, article.id) end)
    |> Enum.take(count)
    |> Enum.map(fn {article, _score} -> article end)
  end

  defp calculate_relevance_score(article, profile) do
    # Weighted scoring model
    weights = %{
      hub_preference: 0.30,      # is this from a hub they like?
      category_preference: 0.20,  # is this in a category they read?
      tag_overlap: 0.15,          # do the tags match their interests?
      recency: 0.15,              # newer is better
      popularity: 0.10,           # view count / engagement rate
      author_affinity: 0.05,      # have they read this author before?
      bux_reward: 0.05            # higher BUX reward = more enticing
    }

    hub_score = hub_preference_score(article.hub_id, profile.preferred_hubs)
    cat_score = category_preference_score(article.category_id, profile.preferred_categories)
    tag_score = tag_overlap_score(article.tag_ids, profile.preferred_tags)
    recency_score = recency_score(article.published_at)
    popularity_score = popularity_score(article.view_count, article.engagement_score)
    author_score = author_affinity_score(article.author_id, profile)
    bux_score = bux_reward_score(article.base_bux_reward)

    weights.hub_preference * hub_score +
    weights.category_preference * cat_score +
    weights.tag_overlap * tag_score +
    weights.recency * recency_score +
    weights.popularity * popularity_score +
    weights.author_affinity * author_score +
    weights.bux_reward * bux_score
  end
end
```

#### 13.2.2 Offer Personalization

For shop-related notifications, the engine selects offers based on browsing and purchase history.

```elixir
defmodule BlocksterV2.Notifications.OfferSelector do
  @doc """
  Generates personalized offer for a user.
  Returns offer type + content based on user's shop behavior.
  """
  def select_offer(user_id) do
    profile = Profiles.get_profile!(user_id)

    cond do
      # High intent: they have items in cart — nudge to complete
      profile.carted_not_purchased != [] ->
        product = get_most_recent_carted(profile.carted_not_purchased)
        {:cart_reminder, product, generate_urgency_message(product)}

      # Viewed products but never carted — highlight with social proof
      profile.viewed_products_last_30d != [] and profile.purchase_count == 0 ->
        product = get_most_viewed_product(user_id, profile.viewed_products_last_30d)
        {:product_highlight, product, "#{product.view_count} people viewed this"}

      # Previous buyer — cross-sell related products
      profile.purchase_count > 0 ->
        products = get_complementary_products(user_id)
        {:cross_sell, products, "Based on your previous purchase"}

      # BUX-rich user who hasn't shopped — show BUX-payable products
      Decimal.compare(profile.bux_balance, Decimal.new("5000")) == :gt and profile.purchase_count == 0 ->
        products = get_bux_affordable_products(profile.bux_balance)
        {:bux_spend, products, "Your #{format_bux(profile.bux_balance)} BUX can get you..."}

      # Default: trending products
      true ->
        products = get_trending_products(3)
        {:trending, products, "Trending in the shop"}
    end
  end

  defp generate_urgency_message(product) do
    cond do
      product.stock_quantity < 5 -> "Only #{product.stock_quantity} left!"
      product.on_sale -> "Sale ends soon"
      true -> "Still in your cart"
    end
  end
end
```

#### 13.2.3 Message Framing — Personalized Copy

The same notification type gets different copy depending on the user's tier and behavior:

```elixir
defmodule BlocksterV2.Notifications.CopyWriter do
  @doc "Generate personalized subject lines and body copy for emails"

  # Daily Digest — different framing per tier
  def digest_subject(profile) do
    case profile.engagement_tier do
      "new" -> "Your daily Blockster briefing is ready"
      "casual" -> "#{profile.articles_read_last_7d} articles picked for you today"
      "active" -> "Today's top stories from your hubs"
      "power" -> "#{length(profile.preferred_hubs)} hubs have new content for you"
      "whale" -> "Exclusive: your personalized daily brief"
      _ -> "Don't miss today's top stories"
    end
  end

  # Referral prompt — different angle per behavior
  def referral_subject(profile) do
    cond do
      profile.referrals_converted > 0 ->
        "Your referrals earned you #{format_bux(profile.referral_bux_earned)} BUX — keep going!"
      profile.bux_earned_last_30d > Decimal.new("1000") ->
        "You earned #{format_bux(profile.bux_earned_last_30d)} BUX this month — share the love"
      profile.purchase_count > 0 ->
        "Give your friends $5 off, get 500 BUX for yourself"
      true ->
        "Invite friends to Blockster, earn 500 BUX each"
    end
  end

  # Cart abandonment — escalating urgency
  def cart_abandonment_subject(profile, hours_since_abandon) do
    case hours_since_abandon do
      h when h < 4 -> "You left something in your cart"
      h when h < 24 -> "Your cart is waiting — complete your order"
      h when h < 48 -> "Last chance: your cart items are going fast"
      _ -> "We saved your cart — here's a little something to help you decide"
    end
  end
end
```

### 13.3 A/B Split Testing Framework

Every automated email type is continuously split-tested to optimize engagement.

#### 13.3.1 Migration: `ab_tests`

```elixir
create table(:ab_tests) do
  add :name, :string, null: false                    # "digest_subject_v12", "referral_cta_test"
  add :email_type, :string, null: false              # "daily_digest", "referral_prompt", etc.
  add :element_tested, :string, null: false          # "subject", "body", "cta_text", "cta_color", "send_time", "image"
  add :status, :string, default: "running"           # "running", "completed", "winner_applied"
  add :variants, {:array, :map}, default: []         # [%{id: "A", value: "...", weight: 50}, %{id: "B", value: "...", weight: 50}]
  add :start_date, :utc_datetime, null: false
  add :end_date, :utc_datetime                       # auto-end after statistical significance
  add :min_sample_size, :integer, default: 100       # per variant
  add :confidence_threshold, :float, default: 0.95   # statistical significance level
  add :winning_variant, :string                      # set when test completes
  add :results, :map, default: %{}                   # %{"A" => %{sent: 500, opened: 150, clicked: 45}, ...}

  timestamps()
end

create index(:ab_tests, [:email_type, :status])
```

#### 13.3.2 Migration: `ab_test_assignments`

```elixir
create table(:ab_test_assignments) do
  add :ab_test_id, references(:ab_tests, on_delete: :delete_all), null: false
  add :user_id, references(:users, on_delete: :delete_all), null: false
  add :variant_id, :string, null: false              # "A", "B", "C"
  add :email_log_id, references(:notification_email_log, on_delete: :nilify_all)
  add :opened, :boolean, default: false
  add :clicked, :boolean, default: false

  timestamps(updated_at: false)
end

create unique_index(:ab_test_assignments, [:ab_test_id, :user_id])
create index(:ab_test_assignments, [:ab_test_id, :variant_id])
```

#### 13.3.3 Split Test Engine

```elixir
defmodule BlocksterV2.Notifications.ABTestEngine do
  @doc """
  Assigns a user to a variant for an active test.
  Uses deterministic hashing so the same user always gets the same variant
  for a given test (consistent experience across re-sends).
  """
  def assign_variant(user_id, test) do
    # Check if already assigned
    case get_existing_assignment(test.id, user_id) do
      %{variant_id: variant} -> variant
      nil ->
        # Deterministic assignment via hash
        hash = :erlang.phash2({user_id, test.id})
        variant = select_variant_by_weight(test.variants, hash)

        create_assignment(test.id, user_id, variant)
        variant
    end
  end

  @doc """
  Checks if a test has reached statistical significance.
  Uses chi-squared test for proportions.
  """
  def check_significance(test) do
    results = get_test_results(test.id)

    if all_variants_have_min_sample?(results, test.min_sample_size) do
      {significant?, p_value, winner} = chi_squared_test(results, :open_rate)

      if significant? and p_value < (1 - test.confidence_threshold) do
        {:significant, winner, p_value}
      else
        {:not_yet, nil, p_value}
      end
    else
      {:insufficient_data, nil, nil}
    end
  end

  @doc "Auto-promote winning variant and retire the test"
  def promote_winner(test, winning_variant) do
    # Update the test
    update_test(test, %{
      status: "winner_applied",
      winning_variant: winning_variant,
      end_date: DateTime.utc_now()
    })

    # Apply winner to the email template defaults
    apply_winning_variant(test.email_type, test.element_tested, winning_variant)

    # Log for admin dashboard
    Logger.info("A/B test #{test.name}: variant #{winning_variant} won for #{test.element_tested}")
  end
end
```

#### 13.3.4 What Gets Split Tested

| Email Type | Elements Tested | Example Variants |
|------------|----------------|------------------|
| **Daily Digest** | Subject line | "Your daily brief" vs "5 articles picked for you" vs "New from your hubs" |
| **Daily Digest** | Article count | 3 articles vs 5 articles vs 7 articles |
| **Daily Digest** | Send time | 8 AM vs 9 AM vs 10 AM local |
| **Daily Digest** | CTA text | "Read More" vs "Continue Reading" vs "Open Article" |
| **Referral Prompt** | Subject line | BUX incentive framing vs social framing vs FOMO framing |
| **Referral Prompt** | CTA button | "Share Now" vs "Invite Friends" vs "Get 500 BUX" |
| **Referral Prompt** | Reward amount visibility | Show "500 BUX" vs show "~$5 value" vs show both |
| **Cart Abandonment** | Timing | 2 hours vs 4 hours vs 24 hours after abandon |
| **Cart Abandonment** | Incentive | No discount vs "5% off" vs "Free shipping" vs "100 bonus BUX" |
| **Cart Abandonment** | Subject urgency | Low urgency vs medium vs high ("Only 2 left!") |
| **Welcome Series** | Email spacing | Days 0/3/5/7 vs 0/2/4/7 vs 0/1/3/7 |
| **Welcome Series** | First email CTA | "Read your first article" vs "Follow a hub" vs "Explore the shop" |
| **Re-engagement** | Hook | Content they missed vs BUX waiting vs exclusive offer |
| **Special Offers** | Discount framing | "20% off" vs "Save $10" vs "Earn 2x BUX" |
| **Special Offers** | Image style | Product photo vs lifestyle shot vs BUX overlay |
| **Hub Post Alert** | Batch size | Individual alerts vs batch 3 articles vs daily batch |

#### 13.3.5 Continuous Optimization Loop

```
1. New email type deployed with 2-3 subject/body variants
2. Users randomly assigned to variants (50/50 or 33/33/33)
3. SendGrid webhook tracks opens + clicks per variant
4. ABTestCheckWorker runs every 6 hours:
   - If significant winner found → promote winner, start new test
   - If no winner after 14 days → declare tie, pick simpler variant
5. New test begins with winner as control + new challenger variants
6. Repeat forever — every email type is always being optimized
```

### 13.4 User Behavior Monitoring — Real-Time Triggers

Beyond scheduled emails, the system monitors behavior patterns and fires notifications in real-time when opportunities are detected.

#### 13.4.1 Real-Time Trigger Rules

```elixir
defmodule BlocksterV2.Notifications.TriggerEngine do
  @doc """
  Evaluate triggers after each user event.
  Called by UserEvents.track/3 after recording the event.
  """
  def evaluate_triggers(user_id, event) do
    profile = Profiles.get_profile!(user_id)

    triggers = [
      &cart_abandonment_trigger/3,
      &bux_milestone_trigger/3,
      &reading_streak_trigger/3,
      &hub_recommendation_trigger/3,
      &purchase_thank_you_trigger/3,
      &dormancy_warning_trigger/3,
      &price_drop_trigger/3,
      &referral_opportunity_trigger/3
    ]

    Enum.each(triggers, fn trigger ->
      case trigger.(user_id, event, profile) do
        {:fire, notification_type, data} ->
          Notifications.create_and_deliver(user_id, notification_type, data)
        :skip ->
          :ok
      end
    end)
  end

  # Trigger: Cart abandoned for >2 hours
  defp cart_abandonment_trigger(user_id, %{event_type: "session_end"}, profile) do
    if profile.carted_not_purchased != [] do
      last_cart_event = get_last_event(user_id, "product_add_to_cart")

      if last_cart_event && hours_since(last_cart_event.inserted_at) >= 2 do
        unless already_sent_today?(user_id, "cart_abandonment") do
          {:fire, "cart_abandonment", %{
            products: profile.carted_not_purchased,
            hours_since: hours_since(last_cart_event.inserted_at)
          }}
        end
      end
    else
      :skip
    end
  end

  # Trigger: BUX balance hits milestone (1k, 5k, 10k, 25k, 50k, 100k)
  defp bux_milestone_trigger(user_id, %{event_type: "bux_earned", metadata: %{new_balance: balance}}, _profile) do
    milestones = [1_000, 5_000, 10_000, 25_000, 50_000, 100_000]
    hit = Enum.find(milestones, fn m -> balance >= m and (balance - m) < 500 end)

    if hit && !milestone_already_celebrated?(user_id, hit) do
      {:fire, "bux_milestone", %{milestone: hit, balance: balance}}
    else
      :skip
    end
  end

  # Trigger: Reading streak — 3, 7, 14, 30 consecutive days
  defp reading_streak_trigger(user_id, %{event_type: "article_read_complete"}, profile) do
    streaks = [3, 7, 14, 30]
    current = profile.consecutive_active_days

    if current in streaks and !streak_already_celebrated?(user_id, current) do
      {:fire, "reading_streak", %{days: current}}
    else
      :skip
    end
  end

  # Trigger: Recommend hubs after reading 3+ articles in a category without hub subscription
  defp hub_recommendation_trigger(user_id, %{event_type: "article_read_complete", metadata: meta}, profile) do
    category_read_count = count_category_reads_last_7d(user_id, meta.category_id)

    if category_read_count >= 3 do
      unsubscribed_hubs = get_hubs_in_category_not_followed(user_id, meta.category_id)

      if unsubscribed_hubs != [] do
        {:fire, "hub_recommendation", %{hubs: Enum.take(unsubscribed_hubs, 3), reason: "category_interest"}}
      else
        :skip
      end
    else
      :skip
    end
  end

  # Trigger: Price drop on viewed product
  defp price_drop_trigger(user_id, %{event_type: "product_price_changed", metadata: meta}, profile) do
    if meta.product_id in profile.viewed_products_last_30d and meta.new_price < meta.old_price do
      {:fire, "price_drop", %{
        product_id: meta.product_id,
        old_price: meta.old_price,
        new_price: meta.new_price,
        savings_pct: round((1 - meta.new_price / meta.old_price) * 100)
      }}
    else
      :skip
    end
  end

  # Trigger: After first purchase — thank you + referral nudge
  defp purchase_thank_you_trigger(user_id, %{event_type: "purchase_complete"}, profile) do
    if profile.purchase_count == 1 do
      {:fire, "first_purchase_thank_you", %{order_id: profile.last_order_id}}
    else
      :skip
    end
  end

  # Trigger: User going dormant — 5 days without activity (early warning)
  defp dormancy_warning_trigger(user_id, %{event_type: "daily_login"}, profile) do
    # Paradoxically, we check PREVIOUS gap when they return
    if profile.days_since_last_active >= 5 and profile.days_since_last_active < 14 do
      {:fire, "welcome_back", %{days_away: profile.days_since_last_active}}
    else
      :skip
    end
  end

  # Trigger: High referral propensity — after sharing content or hitting milestones
  defp referral_opportunity_trigger(user_id, %{event_type: type}, profile) when type in ["article_share", "bux_milestone"] do
    if profile.referral_propensity > 0.6 and !sent_referral_prompt_this_week?(user_id) do
      {:fire, "referral_prompt", %{trigger: type}}
    else
      :skip
    end
  end

  defp referral_opportunity_trigger(_, _, _), do: :skip
end
```

### 13.5 Feedback Loops — How Results Train Future Behavior

Every notification interaction feeds back into the user profile, creating a self-improving system.

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      FEEDBACK LOOP ARCHITECTURE                        │
│                                                                        │
│  ┌──────────┐    ┌──────────────┐    ┌───────────────┐    ┌─────────┐ │
│  │  User     │    │  Event       │    │  Profile      │    │ Content │ │
│  │  Actions  │───>│  Stream      │───>│  Engine       │───>│ Selector│ │
│  │           │    │  (user_events)│    │  (user_profile)│   │         │ │
│  └──────────┘    └──────────────┘    └───────────────┘    └────┬────┘ │
│       ^                                                         │      │
│       │          ┌──────────────┐    ┌───────────────┐         │      │
│       │          │  A/B Test    │    │  Notification  │         │      │
│       └──────────│  Engine      │<───│  Delivery     │<────────┘      │
│                  │  (ab_tests)  │    │  (Oban + PubSub)│              │
│                  └──────────────┘    └───────────────┘                │
└─────────────────────────────────────────────────────────────────────────┘

Example cycle:
1. User reads 3 DeFi articles → event_stream records article_read_complete x3
2. Profile engine recalculates → preferred_categories now shows DeFi at 0.85
3. Content selector picks DeFi-heavy digest for tomorrow
4. Digest sent with A/B test: subject variant A (DeFi focus) vs B (general)
5. User opens variant A, clicks 2 articles → email_opened + email_clicked events
6. A/B engine records: variant A outperforming for this user segment
7. Profile engine updates: email_open_rate increases, best_email_hour confirmed
8. Next digest: even more DeFi-focused, sent at user's optimal hour
9. User shares an article → referral_propensity increases
10. Referral prompt triggered with personalized DeFi angle
```

#### 13.5.1 Profile Recalculation Worker

```elixir
defmodule BlocksterV2.Workers.ProfileRecalcWorker do
  use Oban.Worker, queue: :default, max_attempts: 3

  # Runs every 6 hours via Oban cron
  # Also triggered on-demand after high-value events (purchase, milestone)

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    # Process users in batches, prioritizing those with most new events
    users_needing_update()
    |> Enum.chunk_every(100)
    |> Enum.each(fn batch ->
      Enum.each(batch, &recalculate_profile/1)
    end)
  end

  defp recalculate_profile(user_id) do
    events_30d = UserEvents.get_events(user_id, days: 30)
    events_7d = Enum.filter(events_30d, &within_last_7_days?/1)

    profile = %{
      # Content preferences — weighted by recency and depth
      preferred_categories: extract_category_preferences(events_30d),
      preferred_hubs: extract_hub_preferences(events_30d),
      preferred_tags: extract_tag_preferences(events_30d),
      avg_read_duration_ms: avg_read_duration(events_30d),
      avg_scroll_depth_pct: avg_scroll_depth(events_30d),
      content_completion_rate: completion_rate(events_30d),
      articles_read_last_7d: count_type(events_7d, "article_read_complete"),
      articles_read_last_30d: count_type(events_30d, "article_read_complete"),

      # Shopping behavior
      shop_interest_score: calculate_shop_interest(events_30d),
      viewed_products_last_30d: extract_viewed_products(events_30d),
      carted_not_purchased: extract_carted_not_purchased(user_id),
      price_sensitivity: calculate_price_sensitivity(events_30d),

      # Engagement
      last_active_at: most_recent_event_time(events_30d),
      days_since_last_active: days_since_active(events_30d),
      avg_sessions_per_week: calculate_session_frequency(events_30d),
      consecutive_active_days: calculate_streak(user_id),

      # Notification responsiveness
      email_open_rate_30d: calculate_email_open_rate(user_id, 30),
      email_click_rate_30d: calculate_email_click_rate(user_id, 30),
      in_app_click_rate_30d: calculate_in_app_click_rate(user_id, 30),
      best_email_hour_utc: find_best_email_hour(user_id),
      best_email_day: find_best_email_day(user_id),
      notification_fatigue_score: calculate_fatigue(user_id),

      # Referral propensity
      referral_propensity: calculate_referral_propensity(events_30d),

      last_calculated_at: DateTime.utc_now(),
      events_since_last_calc: 0
    }

    # Classify engagement tier
    profile = Map.put(profile, :engagement_tier,
      ProfileEngine.classify_engagement_tier(profile))

    # Calculate composite engagement score (0-100)
    profile = Map.put(profile, :engagement_score,
      ProfileEngine.calculate_engagement_score(profile))

    Profiles.upsert_profile(user_id, profile)
  end
end
```

#### 13.5.2 Notification Fatigue Detection

The system actively monitors for signs that a user is getting too many notifications:

```elixir
defp calculate_fatigue(user_id) do
  recent_notifications = Notifications.get_notifications(user_id, days: 7)
  recent_emails = EmailLog.get_log(user_id, days: 7)

  signals = %{
    # High dismiss rate = fatigue
    dismiss_rate: count_dismissed(recent_notifications) / max(length(recent_notifications), 1),
    # Declining open rate = fatigue
    open_rate_trend: open_rate_trend(user_id, periods: 4, period_days: 7),
    # Rapid dismiss (within 1s of toast) = annoyance
    rapid_dismiss_count: count_rapid_dismissals(recent_notifications),
    # Unsubscribe actions = serious fatigue
    recent_unsubscribes: count_recent_unsubscribes(user_id, days: 30),
    # Not logging in after notifications = they're ignoring us
    notification_to_visit_rate: notifications_that_led_to_visit(user_id, days: 7)
  }

  # Score 0-1 (1 = maximum fatigue)
  fatigue = (
    signals.dismiss_rate * 0.3 +
    (1 - signals.open_rate_trend) * 0.25 +
    min(signals.rapid_dismiss_count / 5, 1.0) * 0.2 +
    min(signals.recent_unsubscribes / 2, 1.0) * 0.15 +
    (1 - signals.notification_to_visit_rate) * 0.1
  )

  Float.round(fatigue, 2)
end
```

**Fatigue response actions:**

| Fatigue Score | Action |
|---------------|--------|
| 0.0 - 0.3 | Normal frequency (up to max_emails_per_day) |
| 0.3 - 0.5 | Reduce to max 2 emails/day, suppress low-priority notifications |
| 0.5 - 0.7 | Reduce to 1 email/day, only high-priority in-app toasts |
| 0.7 - 0.9 | Reduce to 3 emails/week, minimal in-app, no promos |
| 0.9 - 1.0 | Pause all marketing, only transactional. Flag for manual review. |

### 13.6 Admin AI Dashboard

Admins see a dedicated AI insights panel showing how the personalization engine is performing:

- **Content affinity heatmap**: Which hubs/categories resonate with which user segments
- **Fatigue alerts**: Users approaching fatigue threshold, with recommended action
- **A/B test status board**: All running tests with current winner, sample size, confidence level
- **Trigger firing rates**: Which real-time triggers fire most, conversion rate per trigger
- **Engagement tier flow**: Sankey diagram showing user movement between tiers over time
- **Optimal send time distribution**: Histogram of best email hours across user base
- **Personalization lift**: Comparing personalized vs. non-personalized email performance

---

## 14. Deep Dive: Email Content Creation & Lifecycle

This section details exactly how each email type's content is assembled, personalized, and delivered — from trigger to inbox.

### 14.1 Daily Digest — Full Lifecycle

**Purpose**: The flagship daily email. Each user's digest is unique.

**Trigger**: Oban cron at 9 AM UTC, staggered by user timezone.

**Content Assembly Process**:

```
Step 1: ELIGIBILITY CHECK
├── User has email? (wallet-only users excluded)
├── email_daily_digest preference enabled?
├── email_enabled global toggle on?
├── Not in quiet hours?
├── Under daily email limit?
├── Not fatigued (score < 0.7)?
└── Haven't sent digest today already?

Step 2: ARTICLE SELECTION (via ContentSelector)
├── Pool A: New posts from subscribed hubs (last 24h)
├── Pool B: Trending articles across all hubs (last 24h)
├── Pool C: Recommendations based on reading history
├── Merge pools, deduplicate, remove already-read articles
├── Score each article against user profile
├── Select top 5 (A/B test: 3 vs 5 vs 7)
└── If <2 articles available → skip digest today (don't send empty emails)

Step 3: OFFER INSERTION (via OfferSelector)
├── If user has cart items → cart reminder block
├── If user has viewed products → "trending for you" product block
├── If active campaign targeting this user → campaign offer block
├── If no specific offer → skip offer section
└── Offer always placed after article #2 (A/B tested position)

Step 4: PERSONALIZED SECTIONS ASSEMBLY
├── Header: "Good morning, {name}" or "Your daily brief" (A/B tested)
├── BUX summary: "You have {bux_balance} BUX (+{earned_yesterday} yesterday)"
├── Article cards (personalized order from step 2)
├── Offer block (from step 3)
├── Hub recommendation: If user follows <3 hubs, suggest 1-2 new ones
├── Referral footer: Personalized referral link + "share and earn" CTA
├── Reading streak: "You've read articles {X} days in a row!" (if applicable)
└── Unsubscribe + manage preferences links

Step 5: A/B VARIANT APPLICATION
├── Check running A/B tests for "daily_digest"
├── Assign user to variant for each active test
├── Apply variant: subject line, article count, CTA text, layout
└── Record assignment in ab_test_assignments

Step 6: TEMPLATE RENDERING
├── Render EEx/HEEx template with all assembled data
├── Generate HTML version (responsive, dark-mode compatible)
├── Generate plain text version (accessibility + spam filter compliance)
├── Inline CSS (email clients strip <style> tags)
└── Add tracking pixel + click tracking rewrites (via SendGrid)

Step 7: DELIVERY
├── Build Swoosh email struct
├── Set List-Unsubscribe header
├── Set X-SG-EID for SendGrid tracking
├── Deliver via SendGrid API
├── Record in notification_email_log (subject, sent_at, sendgrid_message_id)
├── Create in-app notification mirroring digest ("Your daily digest is ready")
└── Broadcast to PubSub "notifications:{user_id}"

Step 8: POST-SEND TRACKING
├── SendGrid webhook: opened? → update email_log, record user_event
├── SendGrid webhook: clicked? → update email_log, record user_event (with clicked_url)
├── SendGrid webhook: bounced? → suppress future sends, flag account
├── No open after 48h? → record as "ignored" for fatigue scoring
└── Clicked article → track which position in digest was clicked (for layout optimization)
```

**Example assembled digest for a "power" tier user who follows DeFi and NFT hubs:**

```
Subject: "5 new articles from DeFi Weekly and NFT Pulse"  [A/B variant A]
Preview text: "Plus: your BUX balance hit a new high this week"

──────────────────────────────────────────
BLOCKSTER DAILY BRIEF
Good morning, Alex! Here's what's new.

💰 Your BUX: 12,450 (+320 yesterday)
🔥 Reading streak: 7 days — keep it up!
──────────────────────────────────────────

📰 FROM YOUR HUBS

1. [DeFi Weekly] "Rogue Chain TVL Hits $50M Milestone"
   The DeFi ecosystem on Rogue Chain reached a new...
   → Read Article (earn up to 15 BUX)

2. [NFT Pulse] "Top 10 NFT Drops This Week"
   From High Rollers to emerging artists...
   → Read Article (earn up to 12 BUX)

──────────────────────────────────────────
🛒 STILL IN YOUR CART
   Blockster Hoodie — Black (L)
   $45.00 or 9,000 BUX
   → Complete Your Order
──────────────────────────────────────────

3. [DeFi Weekly] "How to Maximize Yield on Rogue Chain"
   A step-by-step guide to the top yield...
   → Read Article (earn up to 18 BUX)

4. [TRENDING] "Blockster Launches Hub Subscriptions"
   Now you can subscribe to your favorite...
   → Read Article (earn up to 10 BUX)

5. [NFT Pulse] "Artist Spotlight: Digital Rogue"
   Meet the artist behind the latest...
   → Read Article (earn up to 8 BUX)

──────────────────────────────────────────
🌟 HUB RECOMMENDATION
   Based on your reading, you might enjoy:
   [Gaming Hub] — 234 followers, 45 articles
   → Subscribe to Gaming Hub
──────────────────────────────────────────

👥 SHARE BLOCKSTER, EARN BUX
   Your referral link: blockster.com?ref=ALEX123
   You earn 500 BUX for every friend who joins!
   [Copy Link] [Share on X] [Share on Telegram]

──────────────────────────────────────────
Manage notification preferences | Unsubscribe
Blockster Inc. | blockster.com
```

### 14.2 Hub Post Alerts — Full Lifecycle

**Purpose**: Notify hub subscribers when new content drops.

**Trigger**: When a post is published to a hub (via Blog context).

**Batching Strategy**: Instead of sending one email per article, batch articles over a 4-hour window.

```
Step 1: POST PUBLISH EVENT
├── Blog.publish_post(post) called
├── If post has hub_id → enqueue HubPostNotificationWorker
└── Worker defers for 4 hours to allow batching

Step 2: BATCH COLLECTION (after 4-hour window)
├── Collect all posts published in this hub in the last 4 hours
├── Get all hub followers with notification preferences
├── Filter: email_hub_posts enabled, email_enabled, under limit
└── Group by user for personalized delivery

Step 3: CONTENT ASSEMBLY PER USER
├── If 1 post → single article email template
│   Subject: "New from {hub_name}: {post_title}"
│   Body: Hero image + excerpt + "Read Article" CTA
│
├── If 2-3 posts → multi-article template
│   Subject: "{count} new articles from {hub_name}"
│   Body: Article cards stacked vertically
│
└── If 4+ posts → digest-style template
    Subject: "{hub_name} roundup: {count} new articles"
    Body: Compact list with thumbnails

Step 4: PERSONALIZATION
├── Article order: ranked by user's content preferences (ContentSelector)
├── Include BUX reward amount per article
├── If user also follows other hubs with new posts → add "Also new:" section
├── Include hub follower count ("Join 1,234 subscribers")
└── Referral link in footer

Step 5: DELIVERY
├── Render template → Swoosh → SendGrid
├── Create in-app notification per user per post
├── PubSub broadcast for real-time toast
└── Log in notification_email_log
```

**De-duplication**: If a hub post was already included in today's daily digest, don't send a separate hub alert for it. Check `notification_email_log` for the article URL.

### 14.3 Promotional Offers — Full Lifecycle

**Purpose**: Drive shop revenue and BUX engagement. Highly personalized.

**Trigger**: Admin campaign (manual) or automated triggers (cart abandonment, price drop, inventory).

```
Step 1: OFFER DETERMINATION (per user, via OfferSelector)

The system picks the BEST offer for each user based on their behavior:

User Behavior                    → Offer Type              → Subject Line Framework
─────────────────────────────────────────────────────────────────────────────────────
Has items in cart (>2h)          → Cart recovery           → "Your {product} is waiting"
Viewed product 3+ times          → Product spotlight       → "{product} is trending — grab yours"
Viewed but never bought          → First purchase incentive → "Your first order ships free"
Previous buyer                   → Cross-sell              → "Goes great with your {last_purchase}"
High BUX balance, no purchases   → BUX spend nudge         → "Your {bux_amount} BUX can get you..."
Browsed shop category            → Category deals          → "New drops in {category}"
No shop activity                 → Discovery               → "Explore the Blockster Shop"

Step 2: OFFER CONTENT CREATION

For each offer type, the system assembles:

├── Product imagery (from product.featured_image via ImageKit)
├── Price display (show both $ and BUX price)
├── Urgency element:
│   ├── Low stock: "Only {n} left"
│   ├── Time-limited: "Offer expires in {hours}h"
│   ├── Social proof: "{n} people bought this today"
│   └── BUX incentive: "Earn 2x BUX on this purchase"
├── Personalized recommendation reason:
│   ├── "Because you viewed {similar_product}"
│   ├── "Popular with {hub_name} subscribers"
│   └── "Top pick for {engagement_tier} members"
└── CTA: "Shop Now" / "Complete Your Order" / "Spend Your BUX"

Step 3: A/B TEST VARIANTS
├── Subject: urgency framing vs benefit framing vs curiosity framing
├── CTA button: color (brand green vs red vs blue), text variations
├── Image: product-only vs lifestyle context
├── Discount framing: "20% off" vs "Save $10" vs "100 bonus BUX"
└── Send time: morning vs lunch vs evening
```

### 14.4 Referral Prompts — Full Lifecycle

**Purpose**: Turn users into advocates. Contextually triggered.

**Triggers**:
1. Weekly cron (Tuesdays) — for users who haven't referred recently
2. After BUX milestone — "Share the wealth"
3. After content share — "You already share great content — share Blockster too"
4. After first purchase — "Know someone who'd love this?"
5. Re-engagement return — "Welcome back! Bring friends next time"

```
Step 1: TRIGGER EVALUATION
├── Check referral_propensity score (from user profile)
│   ├── >0.7 (high): send referral prompt
│   ├── 0.3-0.7 (medium): send only on strong triggers (milestone, purchase)
│   └── <0.3 (low): skip most prompts, only send quarterly
├── Check: sent referral prompt this week? (max 1/week)
└── Check: user has made any referrals before? (adjust messaging)

Step 2: MESSAGE PERSONALIZATION

For FIRST-TIME referrers:
├── Subject: "Invite friends to Blockster, earn 500 BUX each"
├── Body: Explain the referral program simply
├── Emphasize: "It takes 10 seconds"
├── Show: big "Share Now" button
└── Social proof: "{n} users joined through referrals this week"

For RETURNING referrers (have referred before):
├── Subject: "Your referrals earned you {total_bux} BUX — keep going!"
├── Body: Referral stats dashboard (sent, joined, BUX earned)
├── Emphasize: leaderboard position or next milestone
├── Show: "You're {n} referrals from {reward}"
└── Quick share buttons (pre-filled message for X, Telegram, email)

For POST-MILESTONE trigger:
├── Subject: "You hit {milestone} BUX! Share the wealth 🎉"
├── Body: Celebration + "your friends could earn BUX too"
├── Emphasize: the milestone achievement (dopamine hit)
└── Frame referral as "sharing the secret"

For POST-PURCHASE trigger:
├── Subject: "Love your new {product}? Your friends will too"
├── Body: Order summary + "give your friends $5 off"
├── Emphasize: dual incentive (friend gets discount, user gets BUX)
└── Time this 2 days after purchase (let excitement build)

Step 3: REFERRAL LINK GENERATION
├── Unique link per user: blockster.com?ref={referral_code}
├── UTM parameters for tracking: utm_source=referral&utm_medium={channel}&utm_campaign=notification
├── Short link version for SMS / social sharing
└── QR code generation (for in-person sharing)

Step 4: MULTI-CHANNEL DELIVERY
├── Email: full referral email with stats + share buttons
├── In-app: notification card with one-tap share
├── In-app toast: brief "Share Blockster, earn BUX" slide-in
└── SMS (rare, whale tier only): "Your friends are missing out! Share: {short_link}"
```

### 14.5 Welcome Series — Full Lifecycle

**Purpose**: Onboard new users, teach them the platform, convert to engaged users.

**Trigger**: User registration (email-auth users only).

**Series Architecture**: 4 emails over 7 days, each building on the last, with **conditional branching** based on user behavior.

```
DAY 0 — IMMEDIATE: "Welcome to Blockster!"
────────────────────────────────────────────
Trigger: User.create → enqueue WelcomeSeriesWorker (delay: 0)

Content:
├── Welcome header with user's name
├── "Here's what you can do on Blockster:"
│   ├── 📰 Read articles and earn BUX tokens
│   ├── 🏠 Follow hubs to get content you care about
│   ├── 🛒 Shop with BUX or traditional payment
│   └── 🎮 Play BUX Booster to multiply your earnings
├── Quick action CTA (A/B tested):
│   ├── Variant A: "Read your first article" → trending article
│   ├── Variant B: "Follow your first hub" → hub discovery page
│   └── Variant C: "Explore the shop" → shop page
├── Current BUX balance: "You have 0 BUX — start earning!"
└── Profile completion reminder (upload avatar, etc.)

Conditional: Track which CTA they click → informs Day 3 email


DAY 3 — "You're earning BUX by reading"
────────────────────────────────────────────
Trigger: WelcomeSeriesWorker fires at Day 3

PRE-CHECK: Has user been active since signup?
├── YES (read articles): Celebrate progress
│   Subject: "You've already earned {bux_amount} BUX!"
│   Body: Show their BUX balance, articles read count
│   CTA: "Keep reading to unlock multipliers"
│
├── YES (browsed shop): Pivot to shop
│   Subject: "The Blockster Shop is powered by BUX"
│   Body: Show products they can afford with BUX
│   CTA: "Start earning BUX to unlock products"
│
└── NO (inactive since signup): Re-engage
    Subject: "You haven't visited yet — here's what you're missing"
    Body: Top 3 trending articles + "earn BUX for reading"
    CTA: "Claim your first BUX reward"

Conditional: Track response → informs Day 5


DAY 5 — "Discover your hubs"
────────────────────────────────────────────
Trigger: WelcomeSeriesWorker fires at Day 5

Content (personalized by now):
├── IF user has read articles → recommend hubs matching their reading patterns
│   "Based on your reading, you'll love these hubs:"
│   [3 hub cards with subscribe buttons]
│
├── IF user followed a hub → show content from that hub
│   "New from {hub_name} since you subscribed:"
│   [2-3 article cards from their hub]
│
├── IF user has been inactive → more aggressive re-engagement
│   "We picked 3 articles just for you"
│   [3 trending articles with BUX reward amounts highlighted]
│
└── ALWAYS include: "You're following {n} hubs. Follow 3+ to get a personalized daily digest!"

CTA: "Browse all hubs" or "Read recommended articles"


DAY 7 — "Invite friends, earn together"
────────────────────────────────────────────
Trigger: WelcomeSeriesWorker fires at Day 7

PRE-CHECK: User engagement level by now?
├── ENGAGED (3+ articles, 1+ hub): Full referral push
│   Subject: "Share Blockster with friends, earn 500 BUX each"
│   Body: Explain referral, show social share buttons
│   Emphasis: "You've already earned {bux} — help your friends start earning too"
│
├── MODERATE (1-2 articles): Soft referral + re-engage
│   Subject: "One week in! Here's what you and your friends can earn"
│   Body: Weekly summary + gentle referral mention
│   CTA: "Read more" (primary) / "Share with friends" (secondary)
│
└── INACTIVE: Last chance re-engagement (no referral ask)
    Subject: "We saved your spot at Blockster"
    Body: "It's not too late — here's the best of this week"
    CTA: "Come back and start earning BUX"
    NOTE: If they don't engage after this → they enter re-engagement flow
```

**Welcome Series → Re-engagement Handoff**: If a user completes the welcome series without becoming "active" (defined as: 2+ sessions in 7 days), they're automatically enrolled in the re-engagement flow starting at the 14-day mark.

### 14.6 Re-engagement — Full Lifecycle

**Purpose**: Win back dormant users before they churn permanently.

**Trigger**: Daily cron checks `days_since_last_active` on user profiles.

```
TIER 1: 3 DAYS INACTIVE — "Soft nudge"
────────────────────────────────────────────
Subject (A/B tested):
├── A: "You have unread articles from your hubs"
├── B: "{n} new articles since your last visit"
└── C: "Your BUX balance: {amount} — earn more today"

Content:
├── Show 3 articles from followed hubs published since last visit
├── Show BUX balance + "you could have earned ~{estimate} BUX"
├── If they had reading streak: "Your {n}-day streak needs you!"
└── Gentle CTA: "Catch up on the latest"

Channel: Email only (not in-app since they're not logging in)


TIER 2: 7 DAYS INACTIVE — "FOMO trigger"
────────────────────────────────────────────
Subject (A/B tested):
├── A: "Your BUX are waiting — claim your rewards"
├── B: "You missed {n} articles from your hubs this week"
└── C: "The Blockster community grew by {n}% — come see what's new"

Content:
├── "This week on Blockster:" — summary stats
│   ├── {n} new articles published
│   ├── {n} new members joined
│   └── {n} BUX earned by readers
├── Top 3 articles of the week (personalized by profile)
├── If shop has new products → show 1-2 "New arrivals"
├── BUX balance reminder + estimated weekly earning potential
└── CTA: "Get back in the game"

Channel: Email + queue in-app notification (they'll see it when they return)


TIER 3: 14 DAYS INACTIVE — "Exclusive offer"
────────────────────────────────────────────
Subject (A/B tested):
├── A: "We miss you! Here's something special"
├── B: "Exclusive: 2x BUX rewards for the next 48 hours"
└── C: "14 days away — here's what you missed"

Content:
├── Personal touch: "Hey {name}, it's been 2 weeks..."
├── Best content roundup (personalized top 5 articles)
├── EXCLUSIVE OFFER (A/B tested):
│   ├── A: "2x BUX multiplier for 48 hours after return"
│   ├── B: "500 bonus BUX credited when you read your next article"
│   └── C: "Free shipping on your next shop order"
├── Show social proof: "While you were away, {n} readers earned BUX"
└── CTA: "Claim your reward"

Channel: Email + SMS (if phone verified + sms_re_engagement enabled)
Note: This is one of the few SMS-eligible events


TIER 4: 30 DAYS INACTIVE — "Last chance"
────────────────────────────────────────────
Subject: "Special welcome back offer — just for you"

Content:
├── Acknowledge the gap: "It's been a while! A lot has changed."
├── What's new: 3 biggest features/content since they left
├── AGGRESSIVE OFFER (biggest incentive):
│   ├── "1,000 bonus BUX when you come back today"
│   └── "25% off your first shop order"
├── Simplified CTA: single big button "Come Back to Blockster"
└── Unsubscribe prominent: "Not interested anymore? Unsubscribe"

Channel: Email only (respectful — don't SMS at this stage)

POST-30 DAYS: Reduce to monthly "what you missed" digest.
After 90 days: Stop all marketing. Only send if they return (welcome back trigger).
```

### 14.7 Weekly Reward Summary — Full Lifecycle

**Purpose**: Gamification reinforcement. Show users their progress to keep them earning.

**Trigger**: Monday 8 AM UTC via Oban cron (staggered by timezone).

```
Step 1: DATA COLLECTION (per user, last 7 days)
├── BUX earned breakdown:
│   ├── From reading: {amount} BUX across {n} articles
│   ├── From sharing: {amount} BUX across {n} shares
│   ├── From games: {amount} BUX net (wins - losses)
│   ├── From referrals: {amount} BUX from {n} signups
│   └── Total: {total} BUX this week
├── Reading stats:
│   ├── Articles read: {n}
│   ├── Total reading time: {minutes} min
│   ├── Longest streak: {n} days
│   └── Favorite hub: {hub_name}
├── Ranking (gamification):
│   ├── "You earned more than {percentile}% of readers"
│   └── "Top reader in {hub_name}" (if applicable)
├── Balance: current BUX balance + week-over-week change
└── Multiplier status: current multiplier + progress to next tier

Step 2: PERSONALIZED FRAMING

For HIGH earners (above average):
├── Subject: "🏆 You earned {amount} BUX this week — top {percentile}%!"
├── Tone: Celebratory, competitive
├── CTA: "Can you beat your record next week?"
└── Include: Leaderboard position, share achievement button

For MODERATE earners:
├── Subject: "Your weekly BUX report: {amount} BUX earned"
├── Tone: Encouraging, progress-focused
├── CTA: "Read 2 more articles to hit {next_milestone}"
└── Include: Progress bar to next milestone

For LOW earners:
├── Subject: "You earned {amount} BUX this week — here's how to earn more"
├── Tone: Helpful, educational
├── CTA: "Easy ways to earn more BUX"
└── Include: Tips (read articles, follow hubs, complete profile, refer friends)

For ZERO earners:
├── Subject: "Your BUX balance: {balance} — don't let it sit!"
├── Tone: Gentle nudge, highlight what they're missing
├── CTA: "Start earning with your first article today"
└── Include: 3 quick-read articles with high BUX rewards

Step 3: SHOP INTEGRATION
├── Show "What your BUX can buy" section
├── Product closest to their balance: "{product} — {bux_price} BUX (you have {balance})"
├── If balance > cheapest product: "You can already afford {product}!"
└── If balance < any product: "Earn {remaining} more BUX to unlock {cheapest_product}"

Step 4: REFERRAL NUDGE
├── If they referred someone this week: "Your referral earned you {amount} BUX!"
├── If no referrals: "Earn 500 BUX per friend — share your link"
└── Always: referral link + one-click share buttons
```

### 14.8 Cart Abandonment — Full Lifecycle

**Purpose**: Recover lost revenue from users who added items but didn't complete checkout.

**Detection**: `CartAbandonmentWorker` runs every 30 minutes, checks for carts with items where the user hasn't visited checkout in >2 hours.

```
Step 1: CART DETECTION
├── Query: carts with items WHERE last_activity > 2 hours ago
│   AND no order placed
│   AND user has email
│   AND not already sent abandonment email today
├── For each abandoned cart:
│   ├── Get cart items with product details
│   ├── Calculate cart total (in $ and BUX)
│   ├── Get user profile for personalization
│   └── Check: did they get to checkout page? (higher intent)
└── Batch process all abandoned carts

Step 2: TIMING STRATEGY (A/B tested)
├── Email 1: 2 hours after abandonment (reminder)
├── Email 2: 24 hours (urgency + incentive)
├── Email 3: 48 hours (final attempt + bigger incentive)
└── Stop: after email 3 or if user completes purchase or empties cart

Step 3: EMAIL SEQUENCE

EMAIL 1 (2 hours) — Simple Reminder:
├── Subject (A/B): "You left something behind" vs "Your cart is waiting"
├── Body:
│   ├── Product image(s) from cart
│   ├── Product names + prices
│   ├── "Complete your order" button → direct to checkout
│   └── No discount — just remind them
├── In-app: toast notification "Complete your order"
└── Track: opened? clicked? converted?

EMAIL 2 (24 hours, only if email 1 didn't convert) — Add Urgency:
├── Subject (A/B): "Your cart items are popular — don't miss out" vs "24 hours left before your cart expires"
├── Body:
│   ├── Cart items with stock indicators ("Only 3 left!")
│   ├── Social proof: "{n} people bought this today"
│   ├── BUX alternative: "Or pay with {bux_price} BUX"
│   ├── If applicable: "You have {bux_balance} BUX — use them!"
│   └── CTA: "Complete Your Order"
├── A/B test incentive:
│   ├── A: No incentive (control)
│   ├── B: "100 bonus BUX with this order"
│   └── C: "Free shipping on this order" (if applicable)
└── Track: compare conversion rates across variants

EMAIL 3 (48 hours, only if email 2 didn't convert) — Final Push:
├── Subject: "Last chance: we saved your cart"
├── Body:
│   ├── Cart items
│   ├── Strongest incentive available:
│   │   ├── 5% discount code
│   │   ├── OR 200 bonus BUX
│   │   └── OR free shipping + bonus BUX
│   ├── Expiry: "This offer expires in 24 hours"
│   └── CTA: "Claim Your Offer"
├── If user has phone + SMS enabled:
│   └── Send SMS: "Your Blockster cart is about to expire! Complete your order: {link}"
└── After email 3: mark cart abandonment sequence as complete, don't retry

Step 4: CONVERSION TRACKING
├── If user completes purchase → log conversion, attribute to cart abandonment campaign
├── Calculate: revenue recovered per email in sequence
├── Track: which incentive type converts best (for A/B optimization)
├── Track: which products have highest abandonment rate (flag for pricing review)
└── Feed results back into offer personalization engine
```

### 14.9 Content Creation Pipeline for Automated Emails

All automated emails need content that feels hand-crafted. Here's how the system assembles it:

```elixir
defmodule BlocksterV2.Notifications.EmailAssembler do
  @doc """
  Master assembler that constructs any email type with full personalization.
  """
  def assemble(user, email_type, params \\ %{}) do
    profile = Profiles.get_profile!(user.id)
    prefs = Notifications.get_preferences(user.id)

    %EmailContent{
      user: user,
      profile: profile,

      # Subject line (personalized + A/B tested)
      subject: get_subject(email_type, profile, params),

      # Preheader text (shown in inbox preview)
      preheader: get_preheader(email_type, profile, params),

      # Main content blocks (ordered list)
      blocks: assemble_blocks(email_type, user, profile, params),

      # Sidebar/footer extras
      bux_balance: get_bux_balance(user.id),
      referral_link: get_referral_link(user),
      unsubscribe_url: build_unsubscribe_url(prefs.unsubscribe_token),
      preferences_url: build_preferences_url(prefs.unsubscribe_token),

      # Tracking
      ab_test_assignments: get_ab_assignments(user.id, email_type),
      tracking_params: %{
        utm_source: "email",
        utm_medium: email_type,
        utm_campaign: params[:campaign_id] || "automated"
      }
    }
  end

  defp assemble_blocks(:daily_digest, user, profile, _params) do
    articles = ContentSelector.select_articles(user.id, count: 5, since: days_ago(1))
    offer = OfferSelector.select_offer(user.id)
    hub_rec = get_hub_recommendation(user.id, profile)
    streak = get_reading_streak(user.id)

    blocks = []

    # Block 1: Greeting + stats
    blocks = blocks ++ [%Block{type: :greeting, data: %{
      name: user.name || "there",
      bux_earned_yesterday: bux_earned_since(user.id, days_ago(1)),
      streak: streak
    }}]

    # Block 2-3: First 2 articles
    blocks = blocks ++ Enum.map(Enum.take(articles, 2), fn article ->
      %Block{type: :article_card, data: article}
    end)

    # Block 4: Offer (if available)
    if offer do
      blocks = blocks ++ [%Block{type: :offer, data: offer}]
    end

    # Block 5-7: Remaining articles
    blocks = blocks ++ Enum.map(Enum.drop(articles, 2), fn article ->
      %Block{type: :article_card, data: article}
    end)

    # Block 8: Hub recommendation (if user follows <3 hubs)
    if hub_rec do
      blocks = blocks ++ [%Block{type: :hub_recommendation, data: hub_rec}]
    end

    # Block 9: Referral CTA
    blocks = blocks ++ [%Block{type: :referral_cta, data: %{
      referral_code: user.referral_code
    }}]

    blocks
  end
end
```

---

## 15. BUX-to-ROGUE Conversion Funnel & Gambling Engagement

The ultimate goal of the engagement system: **get users earning BUX → playing BUX Booster → discovering ROGUE → buying and betting with ROGUE**. The notification system is the engine that drives this funnel.

### 15.1 The Funnel

```
STAGE 1: EARN BUX (reading, sharing, referrals)
    ↓  notification nudges them to play
STAGE 2: PLAY WITH BUX (BUX Booster — free-to-play feel)
    ↓  they experience gambling excitement
STAGE 3: DISCOVER ROGUE (game shows ROGUE option, higher payouts)
    ↓  notifications offer free ROGUE to try it
STAGE 4: BUY ROGUE (bridge from BUX-curious to ROGUE buyer)
    ↓  personalized offers based on gambling profile
STAGE 5: BET WITH ROGUE (high-value user, repeat bettor)
    ↓  VIP treatment, exclusive offers, retention
```

### 15.2 Gambling Activity Tracking

Add to `user_profiles` schema:

```elixir
# Gambling behavior (added to user_profiles migration)
add :gambling_tier, :string, default: "non_player"
# "non_player", "bux_curious", "bux_regular", "rogue_curious", "rogue_regular", "high_roller"

add :total_bux_games, :integer, default: 0
add :total_rogue_games, :integer, default: 0
add :total_bux_wagered, :decimal, default: Decimal.new("0")
add :total_rogue_wagered, :decimal, default: Decimal.new("0")
add :total_bux_won, :decimal, default: Decimal.new("0")
add :total_rogue_won, :decimal, default: Decimal.new("0")
add :net_bux_result, :decimal, default: Decimal.new("0")      # wins - losses
add :net_rogue_result, :decimal, default: Decimal.new("0")
add :biggest_bux_win, :decimal, default: Decimal.new("0")
add :biggest_rogue_win, :decimal, default: Decimal.new("0")
add :avg_bet_size_bux, :decimal
add :avg_bet_size_rogue, :decimal
add :last_game_played_at, :utc_datetime
add :games_played_last_7d, :integer, default: 0
add :games_played_last_30d, :integer, default: 0
add :preferred_game_type, :string                              # "coin_flip", "plinko", etc.
add :win_streak, :integer, default: 0
add :loss_streak, :integer, default: 0
add :rogue_purchase_history, {:array, :map}, default: []       # [{amount, date, source}]
add :rogue_balance_estimate, :decimal, default: Decimal.new("0")
```

#### Gambling Tier Classification

```elixir
def classify_gambling_tier(profile) do
  cond do
    profile.total_rogue_games > 20 and Decimal.compare(profile.total_rogue_wagered, Decimal.new("10")) == :gt ->
      "high_roller"
    profile.total_rogue_games > 0 ->
      "rogue_regular"
    profile.total_rogue_games == 0 and profile.total_bux_games > 0 and
      Decimal.compare(profile.total_bux_wagered, Decimal.new("5000")) == :gt ->
      "rogue_curious"  # BUX gambler ready for ROGUE upgrade
    profile.total_bux_games > 5 ->
      "bux_regular"
    profile.total_bux_games > 0 ->
      "bux_curious"
    true ->
      "non_player"
  end
end
```

### 15.3 Stage-by-Stage Notification Offers

#### Stage 1 → 2: Get BUX earners to try BUX Booster

**Target**: Users with BUX balance >500 who have never played.

| Trigger | Notification | Channel |
|---------|-------------|---------|
| BUX balance hits 500 | "You have {bux} BUX — try your luck on BUX Booster!" | In-app toast + email |
| After 5th article read | "Readers love BUX Booster — double your earnings with a flip!" | In-app toast |
| Weekly reward summary | Add "Play BUX Booster" CTA section showing potential wins | Email block |
| After hub subscribe | "Celebrate! Flip a coin with 50 BUX — new subscriber bonus" | In-app toast |
| Daily digest | Add "BUX Booster Spotlight" section: "Today's top win: {user} won {amount}!" | Email block |

**Example email block:**
```
───────────────────────────────────────
🎮 BUX BOOSTER — MULTIPLY YOUR EARNINGS
   Your balance: 2,450 BUX
   Minimum bet: 100 BUX
   Potential win: up to 19.8x your bet!

   "I turned 500 BUX into 9,900!" — @CryptoReader
   → Play BUX Booster Now
───────────────────────────────────────
```

#### Stage 2 → 3: Get BUX players to discover ROGUE

**Target**: `bux_regular` tier (played >5 BUX games).

| Trigger | Notification | Channel |
|---------|-------------|---------|
| After 5th BUX game | "Level up: play with ROGUE for bigger payouts" | In-app |
| After BUX win | "Nice win! With ROGUE, that could have been {rogue_equivalent}" | In-app toast |
| After BUX loss streak (3+) | "Try ROGUE games — different odds, fresh start. Here's 0.5 ROGUE free" | In-app + email |
| Weekly reward summary for gamblers | Add ROGUE comparison: "If you'd played with ROGUE..." | Email block |
| BUX Booster page visit | Show ROGUE tab highlight with "NEW" badge | In-app UI |

**Key offer: FREE ROGUE airdrop** for first-time ROGUE players:

```
Subject: "🎁 Free ROGUE tokens — try ROGUE Booster on us"

Hey {name},

You've played {bux_games} BUX Booster games and won {total_bux_won} BUX.
Ready for the next level?

We just dropped 1 ROGUE into your wallet — enough for your first
ROGUE game. ROGUE games have higher stakes and bigger payouts.

Your free ROGUE: 1.0 ROGUE (~$0.00006 value... but it's about the thrill!)
→ Play Your Free ROGUE Game Now

Pro tip: ROGUE is the native gas token of Rogue Chain.
As the ecosystem grows, so does ROGUE's utility.
```

#### Stage 3 → 4: Convert ROGUE-curious to ROGUE buyers

**Target**: `rogue_curious` tier (BUX regulars who showed interest in ROGUE).

| Trigger | Notification | Channel |
|---------|-------------|---------|
| After free ROGUE game (win or lose) | "Want more ROGUE? Here's how to get it" | In-app + email |
| After viewing ROGUE price page | "ROGUE is at {price} — load up before the next game" | In-app toast |
| After someone in their hub buys ROGUE | "{hub_name} members are buying ROGUE — join the action" | In-app |
| Flash ROGUE sale / bonus event | "2x ROGUE bonus on purchases this weekend" | Email + SMS |
| Payday timing (1st and 15th of month) | "Payday special: buy ROGUE, get 500 bonus BUX" | Email |

**ROGUE purchase CTA in multiple email types:**
```
───────────────────────────────────────
💎 POWER UP WITH ROGUE
   Current ROGUE price: $0.00006
   Your ROGUE balance: 0.5 ROGUE

   Buy ROGUE to unlock bigger games:
   • $5 → ~83,333 ROGUE (hundreds of games)
   • $10 → ~166,666 ROGUE + 500 bonus BUX
   • $25 → ~416,666 ROGUE + 2,000 bonus BUX + VIP badge

   → Buy ROGUE Now (via Helio/card)
───────────────────────────────────────
```

#### Stage 4 → 5: Keep ROGUE bettors engaged and betting

**Target**: `rogue_regular` and `high_roller` tiers.

| Trigger | Notification | Channel |
|---------|-------------|---------|
| Win streak (3+ wins) | "You're on fire! 🔥 {streak} wins in a row — keep it going?" | In-app toast |
| Big win (>10x payout) | "MASSIVE WIN! 🎉 You just won {amount} ROGUE! Share your win?" | In-app toast + in-app notification |
| Loss streak (5+ losses) | "Take a breather. Here's 0.2 ROGUE on us to come back fresh" | In-app + email |
| 24h since last game | "The game awaits! Your balance: {rogue} ROGUE" | In-app toast |
| 3 days no game | "Miss the action? Your ROGUE is waiting: {balance}" | Email |
| 7 days no game | "Welcome back bonus: play today, get 0.5 free ROGUE" | Email + in-app |
| New game type launched | "NEW GAME: Plinko with ROGUE! Try it first" | Email + in-app + SMS |
| ROGUE price change (>10% up) | "ROGUE is pumping! Your {balance} ROGUE is now worth more" | In-app toast |
| Monthly gambling summary | Full stats: games, wins, losses, streaks, rank | Email |

### 15.4 ROGUE VIP Program — Notification-Driven Tiers

Based on gambling activity, unlock VIP perks communicated via notifications:

| Tier | Criteria | Perks Notified |
|------|----------|----------------|
| **Bronze** | 10+ ROGUE games | "You unlocked Bronze! 5% cashback on losses this week" |
| **Silver** | 50+ ROGUE games OR 5+ ROGUE purchased | "Silver unlocked! Free ROGUE airdrop every Monday" |
| **Gold** | 100+ ROGUE games AND 10+ ROGUE purchased | "Gold status! Exclusive high-stakes games + priority support" |
| **Diamond** | Top 1% by ROGUE wagered | "Diamond VIP! Personal offers, early access, 1-on-1 support" |

VIP tier upgrades are celebrated with:
- In-app toast with confetti animation
- Celebratory email with new perks breakdown
- Badge on profile visible to other users

### 15.5 Identifying Best ROGUE Candidates — The "Free ROGUE" Offer Engine

The system automatically identifies the best candidates to receive free ROGUE tokens based on behavior signals:

```elixir
defmodule BlocksterV2.Notifications.RogueOfferEngine do
  @doc """
  Score users for free ROGUE airdrop eligibility.
  Higher score = more likely to convert from BUX player to ROGUE buyer.
  """
  def calculate_rogue_readiness(profile) do
    signals = %{
      # High BUX gambling activity = loves the game
      bux_game_frequency: min(profile.games_played_last_30d / 30, 1.0) * 0.25,

      # Large BUX wagers = willing to risk tokens
      bux_wager_size: min(Decimal.to_float(profile.avg_bet_size_bux || 0) / 1000, 1.0) * 0.20,

      # Views ROGUE content / pricing = curiosity signal
      rogue_content_interest: rogue_page_views(profile.user_id) |> min(5) |> div(5) * 0.15,

      # High engagement tier = invested in platform
      engagement_factor: engagement_tier_score(profile.engagement_tier) * 0.15,

      # Has purchased before (shop) = comfortable spending on Blockster
      purchase_history: min(profile.purchase_count / 3, 1.0) * 0.10,

      # Referral activity = trusts platform enough to recommend
      referral_factor: min(profile.referrals_converted / 2, 1.0) * 0.10,

      # Time on platform = not a fly-by-night user
      tenure_factor: min(profile.lifetime_days / 30, 1.0) * 0.05
    }

    score = Enum.reduce(signals, 0, fn {_key, val}, acc -> acc + val end)
    Float.round(score, 3)
  end

  @doc """
  Get top N users ready for a free ROGUE offer.
  Excludes users who already play with ROGUE or received a ROGUE offer recently.
  """
  def get_rogue_offer_candidates(count \\ 50) do
    Profiles.list_profiles()
    |> Enum.filter(fn p ->
      p.gambling_tier in ["bux_regular", "bux_curious", "rogue_curious"] and
      not received_rogue_offer_recently?(p.user_id, days: 14)
    end)
    |> Enum.map(fn p -> {p, calculate_rogue_readiness(p)} end)
    |> Enum.sort_by(fn {_, score} -> score end, :desc)
    |> Enum.take(count)
  end

  defp engagement_tier_score("whale"), do: 1.0
  defp engagement_tier_score("power"), do: 0.9
  defp engagement_tier_score("active"), do: 0.7
  defp engagement_tier_score("casual"), do: 0.3
  defp engagement_tier_score(_), do: 0.1
end
```

**Automated ROGUE Airdrop Worker** — runs weekly, identifies top candidates, airdrops small amounts:

```elixir
defmodule BlocksterV2.Workers.RogueAirdropWorker do
  use Oban.Worker, queue: :default, max_attempts: 3

  # Weekly cron — Fridays at 3 PM UTC (before weekend gaming)
  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    candidates = RogueOfferEngine.get_rogue_offer_candidates(25)

    Enum.each(candidates, fn {profile, score} ->
      amount = calculate_airdrop_amount(profile, score)

      # Send ROGUE via bux-minter or direct transfer
      case send_rogue_airdrop(profile.user_id, amount) do
        :ok ->
          # Notify them
          Notifications.create_and_deliver(profile.user_id, "rogue_airdrop", %{
            amount: amount,
            reason: airdrop_reason(profile),
            cta: "Play your free ROGUE now!"
          })

          # Send email
          Notifications.send_email_by_type(profile.user_id, :rogue_airdrop, %{
            amount: amount,
            reason: airdrop_reason(profile)
          })

        {:error, reason} ->
          Logger.warn("ROGUE airdrop failed for user #{profile.user_id}: #{reason}")
      end
    end)
  end

  defp calculate_airdrop_amount(profile, score) do
    cond do
      score > 0.8 -> 2.0    # High confidence — generous offer
      score > 0.6 -> 1.0    # Medium confidence — standard offer
      score > 0.4 -> 0.5    # Lower confidence — teaser
      true -> 0.25           # Minimum viable taste
    end
  end

  defp airdrop_reason(profile) do
    cond do
      profile.total_bux_games > 20 -> "You're a BUX Booster regular — time to try ROGUE!"
      profile.engagement_score > 80 -> "You're one of our most active members — VIP ROGUE bonus"
      profile.purchase_count > 0 -> "As a Blockster shopper, here's something extra"
      true -> "We think you'll love ROGUE gaming"
    end
  end
end
```

### 15.6 Gambling-Focused Email Templates

**Monthly Gambling Summary** (for `bux_regular` and above):

```
Subject: "Your January Gaming Report: {total_games} games, {biggest_win} biggest win"

───────────────────────────────────────
🎮 YOUR MONTHLY GAMING STATS
───────────────────────────────────────

Games Played:     {total_games}
Win Rate:         {win_rate}%
Total Wagered:    {total_wagered} BUX / {total_rogue_wagered} ROGUE
Net Result:       +{net_result} BUX
Biggest Win:      {biggest_win} BUX (on {date})
Current Streak:   {streak_type} {streak_count}

───────────────────────────────────────
🏆 YOUR RANK
───────────────────────────────────────
You're in the top {percentile}% of players!
{rank_message based on tier}

───────────────────────────────────────
💎 UPGRADE TO ROGUE
───────────────────────────────────────
If you'd played those {bux_games} BUX games with ROGUE:
• Bigger potential payouts
• Higher max bets
• Exclusive ROGUE-only games coming soon

Buy ROGUE → Get 500 bonus BUX free
→ Upgrade to ROGUE Gaming
───────────────────────────────────────

👥 CHALLENGE YOUR FRIENDS
Share your stats and challenge friends to beat your record!
Your referral link: blockster.com?ref={code}
→ Share Stats on X | Share on Telegram
```

### 15.7 Creative Offer Types

| Offer | Target | Content | Goal |
|-------|--------|---------|------|
| **"Double or Nothing" Email** | BUX players after a win | "You just won {amount} BUX. Double it with one more game?" + direct game link | Increase game frequency |
| **"Friday Night Games"** | All gamblers | "Weekend gaming special: 2x BUX rewards on games tonight 7-10 PM" | Drive engagement timing |
| **"Streak Bonus"** | Players on win streaks | "3 wins in a row! Win one more and get {bonus} free ROGUE" | Reward hot streaks |
| **"Comeback Special"** | Players on loss streaks (5+) | "Tough run. Here's {amount} free ROGUE — fresh start, new game" | Retain losing players |
| **"ROGUE Price Alert"** | ROGUE holders/buyers | "ROGUE up {pct}% today! Your balance worth more — play while it's hot" | Drive activity on price movement |
| **"High Roller Challenge"** | Top gamblers | "This week's challenge: biggest single ROGUE bet wins {prize}" | Competition engagement |
| **"New Game Alert"** | All gamblers | "NEW: Plinko is live! First 100 players get {bonus} free games" | Drive new game adoption |
| **"Lucky Day"** | Random selection | "Today's your lucky day! Free 1 ROGUE airdrop — play now" | Surprise delight |
| **"Social Proof Win Alert"** | Non-players | "🎉 @{username} just won {amount} ROGUE on BUX Booster! You could too" | Social proof conversion |
| **"Whale Watcher"** | Top spenders | "Exclusive: new high-stakes ROGUE game. Max bet: 100 ROGUE. You're invited" | VIP exclusivity |
| **"BUX Millionaire Club"** | Users nearing 100k BUX | "You're {remaining} BUX from 100K! Play BUX Booster to get there faster" | Milestone gamification |
| **"Refer & Play"** | Gamblers with referral potential | "Refer a friend who plays — you BOTH get 2 free ROGUE" | Referral + gaming |
| **"Idle BUX Alert"** | High BUX balance, no recent games | "Your {balance} BUX are just sitting there. Put them to work on BUX Booster" | Activate idle balances |
| **"ROGUE Starter Pack"** | First-time ROGUE buyers | "Buy 5 ROGUE, get 5 ROGUE free + 1,000 bonus BUX. Limited time." | First ROGUE purchase |

---

## 16. Supercharged Referral Engine

The referral system is woven into every notification type. The goal: make sharing Blockster feel rewarding, easy, and competitive.

### 16.1 Referral Incentive Tiers

| Referrals Converted | Reward Per Referral | Bonus Unlocks |
|---------------------|--------------------|----|
| 1-5 | 500 BUX to referrer + 500 BUX to friend | Basic |
| 6-15 | 750 BUX to referrer + 500 BUX to friend | "Ambassador" badge on profile |
| 16-30 | 1,000 BUX to referrer + 750 BUX to friend | Free ROGUE airdrop (1 ROGUE/month) |
| 31-50 | 1,500 BUX to referrer + 1,000 BUX to friend | VIP notification tier (exclusive offers) |
| 51+ | 2,000 BUX to referrer + 1,000 BUX to friend + 0.5 ROGUE to both | "Blockster Legend" badge |

### 16.2 Referral Notifications by Trigger

**When a referral signs up:**
```
In-app toast: "🎉 Your friend just joined Blockster! +500 BUX"
Email: "Your friend {name} just joined — you earned 500 BUX!"
  Body: Show leaderboard position, how many more to next tier, share again CTA
```

**When a referral earns their first BUX:**
```
In-app: "Your friend {name} earned their first BUX! Looks like they're hooked 😎"
```

**When a referral makes their first purchase:**
```
In-app + email: "Your friend {name} just made a purchase!
  As a thank you, here's an extra 200 BUX bonus."
```

**When a referral plays their first game:**
```
In-app: "Your friend {name} just tried BUX Booster!
  Refer 2 more friends who play and get 1 free ROGUE"
```

### 16.3 Referral Prompt Placement Strategy

The referral prompt appears in strategic locations across ALL notification types:

| Email Type | Referral Angle | Placement |
|------------|---------------|-----------|
| Daily Digest | "Share the knowledge — invite friends" | Footer section |
| Weekly Reward Summary | "You earned {bux} BUX — your friends can earn too" | After stats section |
| BUX Milestone | "Celebrate! Share Blockster and earn even more" | Primary CTA option |
| Game Win | "Share your win! Refer friends who play = free ROGUE" | Post-win celebration |
| Welcome Series (Day 7) | "Invite friends, earn together" | Entire email dedicated |
| Re-engagement | "Come back AND bring friends — double bonus for both" | Incentive add-on |
| Order Confirmation | "Love your purchase? Friends get $5 off their first order" | Post-order section |
| Cart Abandonment | "Tell a friend about this product — earn 500 BUX while you decide" | Alternative CTA |

### 16.4 Referral Competition System

**Weekly Referral Leaderboard** (communicated via notifications):

```
Subject: "This Week's Referral Champions — Can you make the top 10?"

🏆 REFERRAL LEADERBOARD (This Week)
─────────────────────────────────────
#1  @CryptoKing     — 12 referrals — 9,000 BUX earned
#2  @BlocksterFan   — 8 referrals  — 6,000 BUX earned
#3  @DeFiDave       — 6 referrals  — 4,500 BUX earned
...
#47 @You            — 1 referral   — 500 BUX earned

🎯 Refer 2 more friends this week to move up 20 spots!
→ Share Your Link Now

WEEKLY PRIZE: Top referrer gets 5,000 bonus BUX + 5 ROGUE
```

### 16.5 "Bring a Friend" Campaigns

Admin-triggered special referral events with boosted rewards:

| Campaign | Duration | Reward | Notification |
|----------|----------|--------|-------------|
| **Double BUX Weekend** | Fri-Sun | 1,000 BUX per referral (2x) | Email Friday + in-app banner |
| **ROGUE for Referrals** | 1 week | 500 BUX + 0.5 ROGUE per referral | Email + SMS + in-app |
| **Holiday Blitz** | Special events | 2,000 BUX per referral | Full multi-channel campaign |
| **Hub Race** | 1 week | Hub with most new followers (via referral) wins bonus | In-app + email to hub followers |

### 16.6 Friend-Gets-Friend Viral Loops

When a referred user signs up, they immediately enter their OWN referral funnel:

```
Day 0: Friend signs up via referral
  → Welcome email emphasizes: "Your friend gave you 500 BUX!
     Share Blockster and give YOUR friends the same gift."
  → Referral link prominently shown

Day 3: If friend hasn't referred anyone:
  → "You joined thanks to a friend. Pass it on — refer 1 friend, get 500 more BUX"

Day 7: Referral prompt regardless:
  → "Your first week earned you {bux} BUX. Imagine if your friends joined too!"
```

---

## 17. Revival & Retention Playbook

Beyond basic re-engagement emails, this is a comprehensive system for keeping EVERY user engaged at every lifecycle stage and reviving them when they drift.

### 17.1 Lifecycle Stage Map

```
[Registration] → [Onboarding] → [Activation] → [Engagement] → [Monetization] → [Advocacy]
                                       ↓                ↓              ↓
                                  [At Risk]       [Dormant]       [Churned]
                                       ↓                ↓              ↓
                                  [Recovery]      [Win-back]     [Last Chance]
```

### 17.2 "At Risk" Detection — Before They Go Dormant

Don't wait for users to disappear. Detect early warning signs:

```elixir
defmodule BlocksterV2.Notifications.ChurnPredictor do
  @doc """
  Score users for churn risk. Higher = more likely to leave.
  Runs daily, flags at-risk users for intervention.
  """
  def calculate_churn_risk(profile) do
    signals = %{
      # Declining frequency
      frequency_decline: calculate_frequency_decline(profile),
      # Shorter sessions
      session_shortening: calculate_session_trend(profile),
      # Lower email engagement
      email_engagement_decline: calculate_email_trend(profile),
      # Not following new hubs (plateau)
      discovery_stall: if(profile.days_since_last_hub_follow > 30, do: 0.8, else: 0.0),
      # Not earning BUX (disengaging from rewards)
      bux_earning_decline: calculate_bux_trend(profile),
      # Dismissing notifications (fatigue)
      notification_fatigue: profile.notification_fatigue_score,
      # No purchases (never monetized — weaker connection)
      no_purchases: if(profile.purchase_count == 0, do: 0.3, else: 0.0),
      # No referrals (no social investment)
      no_referrals: if(profile.referrals_sent == 0, do: 0.2, else: 0.0)
    }

    risk = Enum.reduce(signals, 0, fn {_key, val}, acc -> acc + val end) / map_size(signals)
    Float.round(min(risk, 1.0), 3)
  end
end
```

| Risk Score | Status | Intervention |
|------------|--------|-------------|
| 0.0 - 0.3 | Healthy | Normal notifications |
| 0.3 - 0.5 | Watch | Increase personalization quality, add gamification nudges |
| 0.5 - 0.7 | At Risk | Trigger "We miss you" in-app toast + personalized offer email |
| 0.7 - 0.9 | Critical | Free BUX bonus + exclusive offer + hub recommendation burst |
| 0.9 - 1.0 | Churning | All-out save attempt: SMS + email + in-app + free ROGUE |

### 17.3 Retention Mechanisms — Keeping Users Active

#### Daily Engagement Hooks

| Mechanism | How It Works | Notification |
|-----------|-------------|-------------|
| **Daily Check-in Bonus** | +50 BUX for first article read each day | In-app toast: "Daily bonus! +50 BUX for reading today" |
| **Reading Streaks** | 3-day: +100 BUX, 7-day: +500 BUX, 14-day: +1,500 BUX, 30-day: +5,000 BUX | Toast + email milestone celebration |
| **Daily Challenge** | "Read 2 articles today for 2x BUX rewards" | Morning digest includes daily challenge |
| **Weekly Quest** | "Read from 3 different hubs this week for 1,000 bonus BUX" | Monday email + in-app progress tracker |
| **BUX Booster Daily Free Spin** | One free game per day (low bet, real reward) | In-app toast: "Your free daily game is ready!" |

#### Weekly Engagement Hooks

| Mechanism | How It Works | Notification |
|-----------|-------------|-------------|
| **Weekly Leaderboard** | Top readers/earners by BUX | Monday email with last week's results |
| **Hub of the Week** | Featured hub with bonus BUX for following | In-app banner + email spotlight |
| **Flash Game Event** | 2-hour window with 2x game payouts | In-app push + email 1 hour before |
| **Community Milestone** | "Blockster community earned 1M BUX this week!" | Celebratory in-app + email |
| **Referral Spotlight** | Feature top referrer of the week | Email to all + profile badge |

#### Monthly Engagement Hooks

| Mechanism | How It Works | Notification |
|-----------|-------------|-------------|
| **Monthly BUX Report** | Full breakdown + comparison vs. community | Email with shareable stats card |
| **Season Pass** | Monthly challenges with cumulative rewards | In-app progress tracker + weekly reminders |
| **Exclusive Drop** | Shop product only available to active users (read 10+ articles/month) | Email + in-app + SMS for eligible users |

### 17.4 Revival Sequences — By User Type

Different users need different revival approaches. The system detects WHAT they used to engage with and targets that:

**Content Reader Gone Dormant:**
```
Day 3: "You missed {n} articles from {favorite_hub}" → curated content
Day 7: "Your reading streak was {streak} days. Start a new one?" → streak gamification
Day 14: "Here's 200 bonus BUX — read 1 article to claim" → free BUX incentive
Day 30: "We wrote a special roundup just for you: Best of {month}" → curated digest
```

**Gambler Gone Dormant:**
```
Day 3: "The game table misses you. Your balance: {bux} BUX" → balance reminder
Day 7: "Free game! We credited 100 BUX to your account. Play now" → free game
Day 14: "New game mode just launched! + 0.5 free ROGUE to try it" → new feature + free ROGUE
Day 30: "Exclusive: Double-or-nothing with 500 free BUX. One game. What do you say?" → challenge
```

**Shopper Gone Dormant:**
```
Day 3: "Items you viewed are selling fast: {product}" → urgency
Day 7: "Your BUX can now buy {product} — claim before prices change" → BUX-to-product bridge
Day 14: "Exclusive 15% off for returning shoppers. 48 hours only." → discount
Day 30: "New arrivals + your exclusive welcome-back discount" → discovery + discount
```

**Hub Subscriber Gone Dormant:**
```
Day 3: "{hub_name} published {n} new articles since your last visit" → FOMO
Day 7: "Your hubs are active! {hub_name}: {post_title}" → specific content
Day 14: "Members of {hub_name} earned {total_bux} BUX this week" → social proof
Day 30: "Hub spotlight: why {hub_name} subscribers keep coming back" → community angle
```

### 17.5 "Welcome Back" Experience

When a dormant user DOES return, make it special:

```elixir
# Trigger: user logs in after 7+ days away
defp welcome_back_trigger(user_id, %{event_type: "session_start"}, profile) do
  if profile.days_since_last_active >= 7 do
    {:fire, "welcome_back", %{
      days_away: profile.days_since_last_active,
      missed_articles_count: count_articles_since(profile.last_active_at),
      bux_waiting: calculate_unclaimed_bux(user_id),
      bonus_offered: calculate_return_bonus(profile)
    }}
  else
    :skip
  end
end
```

**In-app welcome back popup** (like OnboardingPopup but for returning users):

```
─────────────────────────────────────
🎉 Welcome Back, {name}!

While you were away:
• {n} new articles published
• {hub_name} added {n} posts
• You have {bux} BUX waiting

BONUS: We added {bonus_bux} BUX to your balance
just for coming back!

→ See What You Missed    → Play BUX Booster
─────────────────────────────────────
```

### 17.6 Retention Analytics Dashboard

Admin dashboard showing retention health:

- **Retention curve**: Day 1, 7, 14, 30 retention by cohort
- **Churn risk distribution**: pie chart of users by risk tier
- **Revival success rate**: % of dormant users successfully revived, by channel
- **Lifetime value by engagement tier**: revenue + BUX earned per tier
- **At-risk interventions**: recent interventions and their outcomes
- **Funnel drop-off**: where users leave the BUX → ROGUE conversion funnel
- **Referral viral coefficient**: how many new users each referral generates (target: >1.0)

---

## 18. Implementation Phases

### Phase 1: Database & Core Infrastructure (Foundation)
**Priority: Critical | Estimated files: 8-10 new, 3-5 modified**

- [ ] Migration: `notification_preferences` table
- [ ] Migration: `notifications` table
- [ ] Migration: `notification_campaigns` table
- [ ] Migration: `notification_email_log` table
- [ ] Migration: Alter `hub_followers` with notification columns
- [ ] Schema: `BlocksterV2.Notifications.NotificationPreference`
- [ ] Schema: `BlocksterV2.Notifications.Notification`
- [ ] Schema: `BlocksterV2.Notifications.Campaign`
- [ ] Schema: `BlocksterV2.Notifications.EmailLog`
- [ ] Context: `BlocksterV2.Notifications` (CRUD for all schemas)
- [ ] Auto-create preferences on user registration
- [ ] Tests: Schema validations, context functions

### Phase 2: Hub Subscribe Button (Quick Win)
**Priority: High | Estimated files: 2-3 modified**

- [ ] Add `follow_hub/2`, `unfollow_hub/2`, `toggle_hub_follow/2` to Blog context
- [ ] Add `user_follows_hub?/2`, `get_hub_follower_user_ids/1` queries
- [ ] Wire up Subscribe button in `hub_live/show.ex` with `handle_event("toggle_follow")`
- [ ] Update `hub_live/show.html.heex` with proper Subscribe/Subscribed button
- [ ] Show follower count update on follow/unfollow
- [ ] Handle unauthenticated users (redirect to login)
- [ ] Tests: Follow/unfollow, toggle, button states

### Phase 3: In-App Notifications — Bell Icon & Dropdown
**Priority: High | Estimated files: 5-7 new, 3-4 modified**

- [ ] `NotificationHook` on_mount module (subscribe to PubSub)
- [ ] Add NotificationHook to router on_mount chain
- [ ] Bell icon + unread badge in `site_header` (desktop + mobile)
- [ ] Notification dropdown component with recent items
- [ ] Pass `unread_notification_count` and `recent_notifications` through layout
- [ ] `notification_item` component (image, title, body, time, action)
- [ ] Event handlers: toggle dropdown, mark read, mark all read, click notification
- [ ] JS hook: `NotificationBell` for badge animation
- [ ] Tests: Hook assigns, event handlers, PubSub delivery

### Phase 4: Toast Notifications & Real-Time Delivery
**Priority: High | Estimated files: 2-3 new, 2-3 modified**

- [ ] Toast slide-in component in app layout
- [ ] CSS animations (slide-in-right, shrink-width)
- [ ] JS hook: `NotificationToast` with auto-dismiss + hover pause
- [ ] PubSub broadcast function in Notifications context
- [ ] Wire up hub post publish → create notification → broadcast
- [ ] Wire up order status changes → notification → broadcast
- [ ] Tests: Toast display, auto-dismiss, PubSub broadcast

### Phase 5: Notifications Page
**Priority: Medium | Estimated files: 2-3 new**

- [ ] `NotificationLive.Index` at `/notifications`
- [ ] Category tabs: All / Content / Offers / Social / Rewards / System
- [ ] Read/Unread filter
- [ ] Mark as read on click, bulk mark as read
- [ ] Infinite scroll (reuse InfiniteScroll hook)
- [ ] Empty state
- [ ] Tests: Page load, filtering, pagination, mark read

### Phase 6: Notification Settings Page
**Priority: Medium | Estimated files: 2-3 new**

- [ ] `NotificationSettingsLive.Index` at `/notifications/settings`
- [ ] Email toggles per type
- [ ] SMS toggles per type
- [ ] In-app toggles (toasts, sound)
- [ ] Quiet hours configuration
- [ ] Max emails per day slider
- [ ] Per-hub notification settings
- [ ] Unsubscribe all with confirmation
- [ ] One-click unsubscribe from email link
- [ ] Tests: Preference updates, toggle behavior

### Phase 7: Email Infrastructure & Templates
**Priority: High | Estimated files: 5-8 new, 2-3 modified**

- [ ] Base email layout template (HTML + plain text)
- [ ] `BlocksterV2.Notifications.EmailBuilder` module
- [ ] Template: Single article
- [ ] Template: Daily digest (multi-article)
- [ ] Template: Promotional/offer
- [ ] Template: Referral prompt
- [ ] Template: Weekly reward summary
- [ ] Template: Welcome email
- [ ] Template: Re-engagement
- [ ] Template: Order update
- [ ] Unsubscribe token generation + one-click unsubscribe route
- [ ] Rate limiter: `Notifications.RateLimiter`
- [ ] Tests: Template rendering, rate limiting, unsubscribe flow

### Phase 8: Email Workers (Oban Jobs)
**Priority: High | Estimated files: 5-7 new, 1-2 modified**

- [ ] Oban queue configuration (email_transactional, email_marketing, email_digest, sms)
- [ ] `Workers.DailyDigestWorker` — morning digest with timezone staggering
- [ ] `Workers.WelcomeSeriesWorker` — 4-email onboarding sequence (day 0, 3, 5, 7)
- [ ] `Workers.ReEngagementWorker` — inactivity-triggered win-back (3d, 7d, 14d, 30d)
- [ ] `Workers.WeeklyRewardSummaryWorker` — weekly BUX earnings summary
- [ ] `Workers.ReferralPromptWorker` — weekly referral nudge
- [ ] `Workers.HubPostNotificationWorker` — batched hub post alerts
- [ ] `Workers.PromoEmailWorker` — campaign-triggered promotional sends
- [ ] `Workers.CartAbandonmentWorker` — 2-hour idle cart reminder
- [ ] Oban cron schedule for recurring workers
- [ ] Tests: Worker execution, rate limiting, timezone handling

### Phase 9: SMS Notifications
**Priority: Low | Estimated files: 2-3 new, 1-2 modified**

- [ ] `BlocksterV2.SmsNotifier` module (extend TwilioClient for general SMS)
- [ ] SMS template system (160 char limit)
- [ ] SMS rate limiter (max per week)
- [ ] `Workers.SmsNotificationWorker`
- [ ] Wire up: flash sale, milestone, order shipped triggers
- [ ] Twilio opt-out webhook handler
- [ ] Tests: SMS sending, rate limiting, opt-out

### Phase 10: SendGrid Webhooks & Analytics
**Priority: Medium | Estimated files: 3-4 new, 1-2 modified**

- [ ] Webhook endpoint: `POST /webhooks/sendgrid`
- [ ] Handle events: open, click, bounce, spam_report, unsubscribe
- [ ] Update email_log records with event timestamps
- [ ] Auto-suppress bounced emails
- [ ] Auto-unsubscribe on spam report
- [ ] Engagement scoring module
- [ ] Tests: Webhook parsing, event handling

### Phase 11: Admin Campaign Interface
**Priority: Medium | Estimated files: 6-8 new**

- [ ] `CampaignAdminLive.Index` — list campaigns with stats
- [ ] `CampaignAdminLive.New` — campaign builder (content → audience → channels → schedule → review)
- [ ] `CampaignAdminLive.Show` — campaign detail with analytics
- [ ] Audience targeting: all, hub_followers, active, dormant, custom filters
- [ ] "Send Test" functionality
- [ ] Quick send form for simple notifications
- [ ] Template manager (list, create, edit, preview)
- [ ] Campaign analytics charts
- [ ] Tests: Campaign CRUD, audience targeting, scheduling

### Phase 12: Notification Analytics Dashboard
**Priority: Low | Estimated files: 2-3 new**

- [ ] `NotificationAnalyticsLive.Index` at `/admin/notifications/analytics`
- [ ] Overall stats: sent, opened, clicked rates
- [ ] Charts: volume over time, open rate trend, channel comparison
- [ ] Best performing campaigns table
- [ ] Send time heatmap
- [ ] User engagement breakdown
- [ ] Hub subscription analytics

### Phase 13: User Behavior Tracking & Profiles
**Priority: High | Estimated files: 6-8 new, 3-5 modified**

- [ ] Migration: `user_events` table (event stream)
- [ ] Migration: `user_profiles` table (aggregated behavior data)
- [ ] `BlocksterV2.UserEvents` module (track/2, track_batch/1)
- [ ] `BlocksterV2.Notifications.ProfileEngine` (tier classification, scoring)
- [ ] `EventTracker` JS hook for client-side events (product view duration, scroll depth)
- [ ] Wire event tracking into existing flows: article read, product view, game play, purchase
- [ ] `Workers.ProfileRecalcWorker` — recalculate profiles every 6 hours
- [ ] Gambling tier classification in profile engine
- [ ] Churn risk predictor module
- [ ] Tests: Event recording, profile calculation, tier classification

### Phase 14: AI Personalization & A/B Testing
**Priority: Medium | Estimated files: 6-8 new, 2-3 modified**

- [ ] Migration: `ab_tests` and `ab_test_assignments` tables
- [ ] `BlocksterV2.Notifications.ContentSelector` — personalized article ranking
- [ ] `BlocksterV2.Notifications.OfferSelector` — personalized offer selection
- [ ] `BlocksterV2.Notifications.CopyWriter` — tier-based message framing
- [ ] `BlocksterV2.Notifications.ABTestEngine` — variant assignment, significance checking, winner promotion
- [ ] `BlocksterV2.Notifications.TriggerEngine` — real-time notification triggers
- [ ] `Workers.ABTestCheckWorker` — check significance every 6 hours
- [ ] Notification fatigue detection and auto-throttling
- [ ] Tests: Content selection, A/B assignment, trigger evaluation

### Phase 15: BUX-to-ROGUE Conversion Funnel
**Priority: High | Estimated files: 4-6 new, 2-3 modified**

- [ ] Gambling activity tracking fields on user_profiles
- [ ] `BlocksterV2.Notifications.RogueOfferEngine` — ROGUE readiness scoring
- [ ] Stage-based notification triggers (BUX player → ROGUE curious → ROGUE buyer)
- [ ] Free ROGUE airdrop logic + delivery via bux-minter
- [ ] `Workers.RogueAirdropWorker` — weekly ROGUE giveaway to top candidates
- [ ] Gambling-focused email templates (monthly gaming report, win celebrations)
- [ ] ROGUE purchase CTA blocks for insertion into existing email types
- [ ] VIP tier system (Bronze/Silver/Gold/Diamond) with notification-driven upgrades
- [ ] Creative offer notifications (streak bonus, comeback special, lucky day, etc.)
- [ ] Tests: ROGUE readiness scoring, airdrop worker, gambling tier classification

### Phase 16: Supercharged Referral Engine
**Priority: High | Estimated files: 3-5 new, 3-5 modified**

- [ ] Tiered referral rewards (escalating BUX + ROGUE at higher tiers)
- [ ] Referral lifecycle notifications (friend signs up, earns BUX, first purchase, first game)
- [ ] Referral leaderboard (weekly rankings, top referrer prize)
- [ ] Referral block insertion into ALL email types
- [ ] "Bring a Friend" campaign system (double BUX weekend, ROGUE for referrals)
- [ ] Friend-gets-friend viral loop in welcome series
- [ ] Referral competition UI + admin management
- [ ] Tests: Tiered rewards, leaderboard, campaign execution

### Phase 17: Revival & Retention System
**Priority: Medium | Estimated files: 4-6 new, 2-3 modified**

- [ ] Churn risk daily scan + intervention triggers
- [ ] User-type-specific revival sequences (reader, gambler, shopper, hub subscriber)
- [ ] "Welcome Back" in-app popup for returning dormant users
- [ ] Daily/weekly/monthly engagement hooks (check-in bonus, streaks, quests, leaderboards)
- [ ] Retention analytics dashboard (cohort retention, churn risk distribution, revival success)
- [ ] `Workers.ChurnDetectionWorker` — daily scan for at-risk users
- [ ] Tests: Churn prediction, revival sequences, welcome back triggers

### Phase 18: Advanced Features & Optimization
**Priority: Low | Estimated files: varies**

- [ ] Smart send-time optimization (per user based on engagement history)
- [ ] Browser push notification support (Web Push API)
- [ ] Email deliverability monitoring (bounce rate alerts)
- [ ] "Subscribed hubs" personalized feed at `/feed`
- [ ] Season pass / monthly challenge system
- [ ] Referral viral coefficient tracking (target >1.0)
- [ ] ROGUE price movement notifications for holders
- [ ] AI-generated email subject lines (Claude API integration for copywriting)

---

## Appendix A: File Structure

```
lib/blockster_v2/
├── notifications/
│   ├── notification.ex              # Notification schema
│   ├── notification_preference.ex   # Preference schema
│   ├── campaign.ex                  # Campaign schema
│   ├── email_log.ex                 # Email log schema
│   ├── user_event.ex               # Event stream schema
│   ├── user_profile.ex             # Aggregated user profile schema
│   ├── ab_test.ex                  # A/B test schema
│   ├── ab_test_assignment.ex       # A/B test assignment schema
│   ├── email_builder.ex             # Template rendering
│   ├── email_assembler.ex          # Master email content assembler
│   ├── content_selector.ex         # AI article ranking
│   ├── offer_selector.ex           # Personalized offer selection
│   ├── copy_writer.ex              # Tier-based message framing
│   ├── rogue_offer_engine.ex       # ROGUE conversion scoring
│   ├── trigger_engine.ex           # Real-time notification triggers
│   ├── ab_test_engine.ex           # A/B split testing
│   ├── profile_engine.ex           # User tier classification
│   ├── churn_predictor.ex          # Churn risk scoring
│   ├── rate_limiter.ex              # Frequency capping
│   ├── scheduler.ex                 # Timezone-aware scheduling
│   └── engagement_scorer.ex         # User engagement scoring
├── notifications.ex                 # Notifications context
├── user_events.ex                  # Event tracking module
├── sms_notifier.ex                  # SMS sending module
├── workers/
│   ├── daily_digest_worker.ex
│   ├── welcome_series_worker.ex
│   ├── re_engagement_worker.ex
│   ├── weekly_reward_summary_worker.ex
│   ├── referral_prompt_worker.ex
│   ├── hub_post_notification_worker.ex
│   ├── promo_email_worker.ex
│   ├── cart_abandonment_worker.ex
│   ├── sms_notification_worker.ex
│   ├── profile_recalc_worker.ex    # User profile recalculation (6h)
│   ├── ab_test_check_worker.ex     # A/B test significance check (6h)
│   ├── rogue_airdrop_worker.ex     # Weekly ROGUE giveaway
│   └── churn_detection_worker.ex   # Daily churn risk scan

lib/blockster_v2_web/
├── live/
│   ├── notification_hook.ex         # on_mount PubSub hook
│   ├── notification_live/
│   │   ├── index.ex                 # /notifications page
│   │   └── index.html.heex
│   ├── notification_settings_live/
│   │   ├── index.ex                 # /notifications/settings page
│   │   └── index.html.heex
│   ├── campaign_admin_live/
│   │   ├── index.ex                 # Campaign list
│   │   ├── new.ex                   # Campaign builder
│   │   ├── show.ex                  # Campaign detail
│   │   └── *.html.heex
│   └── notification_analytics_live/
│       ├── index.ex
│       └── index.html.heex
├── controllers/
│   └── webhook_controller.ex        # SendGrid webhooks (add to existing or new)

assets/js/
├── hooks/
│   ├── notification_bell.js
│   ├── notification_toast.js
│   └── event_tracker.js            # Client-side event capture
```

## Appendix B: PubSub Topics

| Topic | Payload | Publisher | Subscriber |
|-------|---------|-----------|------------|
| `notifications:#{user_id}` | `{:new_notification, %Notification{}}` | Notifications context | NotificationHook |
| `notification_campaigns:admin` | `{:campaign_updated, campaign}` | Campaign workers | Campaign admin LiveView |

## Appendix C: Oban Cron Schedule

```elixir
config :blockster_v2, Oban,
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [
       # Existing jobs...

       # === Email Workers ===
       {"0 9 * * *", BlocksterV2.Workers.DailyDigestWorker},           # 9 AM UTC daily
       {"0 10 * * 2", BlocksterV2.Workers.ReferralPromptWorker},       # Tuesday 10 AM UTC
       {"0 8 * * 1", BlocksterV2.Workers.WeeklyRewardSummaryWorker},   # Monday 8 AM UTC
       {"0 */4 * * *", BlocksterV2.Workers.HubPostNotificationWorker}, # Every 4 hours (batch)
       {"0 12 * * *", BlocksterV2.Workers.ReEngagementWorker},         # Noon UTC daily
       {"*/30 * * * *", BlocksterV2.Workers.CartAbandonmentWorker},    # Every 30 min

       # === AI / Personalization Workers ===
       {"0 */6 * * *", BlocksterV2.Workers.ProfileRecalcWorker},       # Every 6 hours
       {"30 */6 * * *", BlocksterV2.Workers.ABTestCheckWorker},        # Every 6 hours (offset)
       {"0 6 * * *", BlocksterV2.Workers.ChurnDetectionWorker},        # 6 AM UTC daily

       # === ROGUE Conversion ===
       {"0 15 * * 5", BlocksterV2.Workers.RogueAirdropWorker}          # Friday 3 PM UTC
     ]}
  ]
```

## Appendix D: Email Compliance

- **CAN-SPAM**: Physical address in footer, one-click unsubscribe, honor opt-outs within 10 days
- **GDPR**: Explicit consent at registration, data export support, right to deletion
- **Unsubscribe header**: Include `List-Unsubscribe` header in all marketing emails
- **Suppression list**: Maintain bounced/unsubscribed email list, never send to suppressed addresses
