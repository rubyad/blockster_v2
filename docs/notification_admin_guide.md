# Notification System — Admin Operations Guide

## Admin Pages

### 1. Campaign Manager — `/admin/notifications/campaigns`

Your main control center for sending targeted communications.

**What you see:** A table of all campaigns with status badges (Draft/Scheduled/Sending/Sent/Cancelled), channel pills (Email/In-App/SMS), recipient counts, and open/click performance.

**Actions:**

| Action | How | What happens |
|--------|-----|--------------|
| **Quick Send** | Click "Quick Send" button at top | Opens inline form — type a title, pick audience, write message, check channels (Email/In-App/SMS), hit Send Now. Campaign is created and immediately queued. |
| **New Campaign** (wizard) | Click "+ New Campaign" | Opens 5-step wizard (see below) |
| **Filter by status** | Click status tabs (All/Draft/Scheduled/Sending/Sent/Cancelled) | Filters the table |
| **Send Test** | Click "Test" on any campaign row | Sends a test email to YOUR email address only |
| **Cancel** | Click "Cancel" on draft/scheduled campaigns | Stops campaign from sending |
| **Delete** | Click "Delete" on draft/cancelled campaigns | Permanently removes campaign |

---

### 2. Campaign Creation Wizard — `/admin/notifications/campaigns/new`

**5 steps:**

1. **Content** — Campaign name, email subject, notification title, body text, optional image URL, optional action URL + button label
2. **Audience** — Pick one:
   - **All Users** — everyone in the system
   - **Hub Followers** — followers of a specific hub (dropdown to pick which hub)
   - **Active Users** — logged in within 7 days
   - **Dormant Users** — not seen in 30+ days
   - **Phone Verified** — users who verified their phone
   - Shows **estimated recipient count** that updates live as you pick
3. **Channels** — Toggle on/off:
   - **Email** — branded HTML email via SendGrid
   - **In-App** — bell notification + toast popup
   - **SMS** — text message (phone verified users only)
4. **Schedule** — Send Now or pick a specific date/time (UTC)
5. **Review** — Summary of everything + "Send Test" to preview + "Send Campaign" / "Schedule Campaign" to go live

**What happens when you send:** The system creates the campaign record, then enqueues a `PromoEmailWorker` job. That worker:
1. Queries the target audience
2. Creates one Oban job per recipient
3. Each job checks rate limits and quiet hours before sending
4. If email channel enabled → sends branded HTML email via SendGrid
5. If in-app enabled → creates in-app notification (bell + toast)
6. If SMS enabled → enqueues SMS job via Twilio
7. Logs every send to `email_log` for tracking

---

### 3. Campaign Detail — `/admin/notifications/campaigns/:id`

**Auto-refreshes every 30 seconds** so you can watch a send in progress.

**4 tabs:**

- **Overview** — Status, type, audience, channels, created/sent dates, open/click/bounce rates
- **Email Stats** — Sent/Opened/Clicked/Bounced counts with delivery funnel visualization (bars showing drop-off from sent → opened → clicked)
- **In-App Stats** — Delivered/Read/Clicked counts with engagement funnel bars
- **Content** — The actual subject, title, body, image, and CTA displayed

---

### 4. Analytics Dashboard — `/admin/notifications/analytics`

**Period selector:** 7d / 14d / 30d / 90d (default 30d)

**Overview cards (top row):**
- Emails Sent (total)
- Open Rate %
- Click Rate %
- Bounce Rate %
- In-App Delivered
- In-App Read Rate %
- Bounced count
- Unsubscribed count

**Charts:**
- **Channel Comparison** — Email vs In-App vs SMS engagement rates as horizontal bars
- **Daily Email Volume** — Bar chart of sent vs opened per day (last 14 days)
- **Send Time Heatmap** — 24-hour grid colored by send volume (lime intensity) with open rates, shows which hours perform best
- **Top Campaigns** — Top 5 campaigns ranked by opens, linked to their detail pages
- **Hub Subscription Analytics** — Table showing each hub's follower count, how many have notifications enabled, and the opt-in rate

---

## Automated Systems (Runs Without Admin Action)

These workers run on cron schedules. The admin doesn't need to do anything — they just work.

### Daily

| Time (UTC) | Worker | What it does |
|------------|--------|-------------|
| **6:00 AM** | Churn Detection | Scans all user profiles for churn risk score >= 50%. Fires escalating interventions: personalized content (watch tier), 100 BUX re-engagement offer (at-risk), 500 BUX rescue offer (critical), 1000 BUX + 0.5 ROGUE all-out save (churning). Won't re-send within 7 days. |
| **9:00 AM** | Daily Digest | Sends personalized digest emails with recent posts from user's followed hubs. Only to users with email enabled + digest preference on. |
| **11:00 AM** | Re-Engagement | Targets users inactive for exactly 3, 7, 14, or 30 days. Sends "we miss you" emails with recent articles. 30+ day users get a special offer (2x BUX on next 3 articles). |
| **Every 30 min** | Cart Abandonment | Finds shopping carts idle for 2+ hours. Sends reminder email + in-app notification. Won't re-send within 24 hours. |

### Weekly

| Time (UTC) | Worker | What it does |
|------------|--------|-------------|
| **Monday 10 AM** | Weekly Reward Summary | Sends BUX earnings recap email: total earned, articles read, days active, top hub. |
| **Tuesday 10 AM** | Referral Leaderboard | Logs top 10 referrers for the week. |
| **Wednesday 2 PM** | Referral Prompt | Sends "invite your friends" email with personalized referral link and 500 BUX reward amount. |
| **Friday 3 PM** | ROGUE Airdrop | Finds top 25 users most likely to convert to ROGUE based on readiness score. Creates in-app notification about airdrop opportunity. Timed before weekend gaming. |

### Every 6 Hours

| Worker | What it does |
|--------|-------------|
| Profile Recalc | Rebuilds user behavior profiles from event history: engagement tier, churn risk, content preferences, gambling stats, conversion stage. Processes users with new events since last calc. |
| A/B Test Check | Evaluates running A/B tests for statistical significance (chi-squared). Auto-promotes winning variant when confidence threshold is met. |

### Event-Triggered (Real-Time)

These fire immediately when specific events happen:

| Trigger | When it fires | What it sends |
|---------|--------------|---------------|
| **Hub post published** | Author publishes a post in a hub | In-app notification to all hub followers + email (60s delay for batching) |
| **Order status change** | Order moves to paid/shipped/delivered/cancelled | In-app notification with status-specific copy + SMS for shipped orders |
| **User registration** | New user signs up | 4-email welcome series on days 0, 3, 5, 7 (welcome → BUX intro → hub discovery → referral prompt) |
| **BUX milestone** | User crosses 1K/5K/10K/25K/50K/100K BUX | In-app notification celebrating the milestone |
| **Reading streak** | 3/7/14/30 consecutive reading days | In-app notification with streak badge |
| **Cart abandonment** | User ends session with items in cart | Email + in-app after 2 hours |
| **First purchase** | User makes their first order | Thank you notification |
| **Price drop** | Product price drops and user viewed it | In-app alert with savings percentage |
| **Hub recommendation** | User reads 3+ articles in a category | Suggests unfollowed hubs in that category |
| **Return from dormancy** | User logs in after 5-14 days away | Welcome back notification |
| **Referral opportunity** | User shares article or earns BUX, and has high referral propensity | Referral nudge notification |
| **ROGUE price movement** | ROGUE price moves 5%+ (significant) or 10%+ (major) | Price alert to ROGUE-curious/buyer/regular users, max 1 per day |

---

## Intelligent Systems

### Rate Limiting

Every notification goes through a 4-step gate:
1. **Channel enabled?** — Is email/SMS/in-app turned on for this user?
2. **Type opted in?** — Has the user disabled this specific notification type?
3. **Rate limit?** — Has the user hit their daily email cap (configurable 1-10/day) or weekly SMS cap?
4. **Quiet hours?** — Is it within their quiet hours? If so, the send is deferred (rescheduled 1 hour later).

### Send Time Optimization

Each user has a `best_email_hour_utc` in their profile, calculated from when they actually open emails. If a user tends to open at 2 PM, their emails get delayed to that hour. Falls back to population-level best hour, then to 10 AM UTC default.

### Churn Prediction (8 signals)

The system scores every user on 8 behavioral signals:
- Frequency decline (sessions dropping)
- Session shortening
- Email engagement declining
- Discovery stall (not exploring new hubs)
- BUX earning decline
- Notification fatigue
- No purchases (weak signal)
- No referrals (weak signal)

Score 0-1 maps to risk tiers: healthy → watch → at_risk → critical → churning. Interventions escalate automatically.

### Revival Engine

When churned users return, the system:
1. Classifies their user type (reader/gambler/shopper/hub_subscriber/general)
2. Fires a welcome-back notification with engagement-based BUX bonus
3. Offers daily check-in bonuses (50 BUX), streak rewards (100-5000 BUX), type-specific daily challenges, and weekly quests

### Referral Engine (5-tier)

Referral rewards escalate:

| Tier | Referrals | Referrer BUX | Friend BUX | ROGUE | Badge |
|------|-----------|-------------|-----------|-------|-------|
| 1 | 1-5 | 500 | 250 | — | — |
| 2 | 6-15 | 750 | 375 | — | Ambassador |
| 3 | 16-30 | 1000 | 500 | 1.0 | — |
| 4 | 31-50 | 1500 | 750 | — | VIP Referrer |
| 5 | 51+ | 2000 | 1000 | 0.5 | Blockster Legend |

4 lifecycle notifications fire automatically: friend signs up, friend earns first BUX, friend makes first purchase (200 BUX bonus), friend plays first game.

### BUX-to-ROGUE Conversion Funnel (5 stages)

Users progress through: Earner → BUX Player → ROGUE Curious → ROGUE Buyer → ROGUE Regular. Each stage has automated nudge notifications. VIP tiers (Bronze/Silver/Gold/Diamond) unlock at game count thresholds.

### A/B Testing

The system can A/B test email subject lines, body copy, CTA text/color, send times, images, article count, and layout. Tests auto-resolve when statistical significance is reached (chi-squared test).

---

## Webhook Endpoints (External Services)

These endpoints must be configured in SendGrid and Twilio settings.

| Endpoint | Service | What it processes |
|----------|---------|-------------------|
| `POST /api/webhooks/sendgrid` | SendGrid | Email events: open → updates opened_at + campaign stats. Click → updates clicked_at. Bounce → marks bounced, auto-suppresses user email. Spam report → marks bounced + unsubscribed, disables all marketing prefs. |
| `POST /api/webhooks/twilio/sms` | Twilio | SMS replies: STOP/CANCEL/END/QUIT/UNSUBSCRIBE → opts user out. START/YES/UNSTOP → opts user back in. |
| `GET /unsubscribe/:token` | Email footer link | One-click unsubscribe — disables all email + SMS for the user. Redirects to homepage with flash message. |

---

## Monitoring & Health

**From the Analytics Dashboard:**
- Watch **bounce rate** — above 5% triggers a warning, above 10% is critical (can get your SendGrid account flagged)
- Watch **open rate** — below 10% means your subjects/timing need work
- Check the **send time heatmap** to see when users actually engage
- **Deliverability health score** (0-100) combines bounce (40% weight), open (35%), click (25%)

**Automated protections:**
- Bounced emails auto-suppress (user's email_enabled set to false)
- Spam reports auto-disable all marketing preferences
- Rate limiter prevents over-mailing any single user
- Quiet hours respect user timezone preferences
- 7-day dedup on churn interventions prevents notification spam

---

## Oban Queue Capacity

| Queue | Concurrency | Purpose |
|-------|-------------|---------|
| `default` | 10 | Profile recalc, A/B tests, churn detection, ROGUE airdrop |
| `email_transactional` | 5 | Welcome series, cart abandonment |
| `email_marketing` | 3 | Digest, re-engagement, referral, promos, hub post emails |
| `email_digest` | 2 | Daily digest only |
| `sms` | 1 | All SMS (serialized to avoid Twilio rate limits) |

Jobs are pruned after 7 days. Failed jobs retry with backoff (max 3 attempts for most workers).

---

## User-Facing Pages

These are not admin-only — regular users access these:

| Page | URL | What it does |
|------|-----|-------------|
| Notifications | `/notifications` | List of all notifications with category tabs (All/Content/Offers/Social/Rewards/System), read/unread filter, mark-as-read, infinite scroll |
| Settings | `/notifications/settings` | Toggle email/SMS/in-app channels, per-type opt-in/out, max emails/day slider, quiet hours, per-hub notification toggles, unsubscribe all |

---

## Quick Reference — Admin URLs

| Page | URL |
|------|-----|
| Campaign List | `/admin/notifications/campaigns` |
| Create Campaign | `/admin/notifications/campaigns/new` |
| Campaign Detail | `/admin/notifications/campaigns/:id` |
| Analytics Dashboard | `/admin/notifications/analytics` |
