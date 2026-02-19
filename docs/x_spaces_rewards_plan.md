# X Spaces BUX Reward System — Design Plan

> **Status**: Research Complete — Awaiting Approval
> **Date**: Feb 18, 2026
> **Branch**: TBD

---

## Executive Summary

We want to display upcoming X Spaces on Blockster, let users listen through our UI, track their presence, and reward them with BUX for every second they are actively listening — similar to our existing YouTube video BUX reward system.

**Key Finding: This is feasible but with significant constraints.** X provides no embed widget or audio stream API for Spaces. The recommended architecture is a **"Listen & Earn" popup model** — we open the X Space in a popup window, track whether the popup is open, and reward BUX based on listening time on our side. The X API v2 provides Space metadata (scheduling, state, participant count) but cannot identify individual listeners.

**Critical Risk: X's Developer Agreement prohibits compensating users for "actions on X."** Our mitigation strategy frames rewards as Blockster platform engagement (checking in to a scheduled event) rather than payment for joining an X Space. See Section 11 for full ToS analysis.

---

## Table of Contents

1. [X API Capabilities & Limitations](#1-x-api-capabilities--limitations)
2. [Existing YouTube Reward System (Reference Pattern)](#2-existing-youtube-reward-system-reference-pattern)
3. [Architecture Overview](#3-architecture-overview)
4. [Embedding Strategy](#4-embedding-strategy)
5. [Presence Tracking & State Machine](#5-presence-tracking--state-machine)
6. [BUX Reward System](#6-bux-reward-system)
7. [Anti-Abuse Measures](#7-anti-abuse-measures)
8. [Admin Interface](#8-admin-interface)
9. [Database Schema](#9-database-schema)
10. [Implementation Phases](#10-implementation-phases)
11. [ToS Risk Analysis & Mitigation](#11-tos-risk-analysis--mitigation)
12. [API Costs](#12-api-costs)
13. [Limitations & Future Opportunities](#13-limitations--future-opportunities)

---

## 1. X API Capabilities & Limitations

### What We CAN Do (Official API v2)

| Capability | Endpoint | Notes |
|-----------|----------|-------|
| List scheduled Spaces by host | `GET /2/spaces/by/creator_ids` | Up to 100 creator IDs, returns `live` + `scheduled` |
| Search Spaces by keyword | `GET /2/spaces/search` | Returns live and scheduled matches |
| Look up Space metadata | `GET /2/spaces/:id` | Title, state, host, participant_count, scheduled_start |
| Get aggregate participant count | `GET /2/spaces/:id` | Total count only (hosts + speakers + listeners) |
| Get host/speaker identity | `GET /2/spaces/:id` with `user.fields` | `host_ids`, `speaker_ids`, `creator_id` |
| Detect Space state changes | Poll `GET /2/spaces/:id` | `scheduled` → `live` → `ended` |
| Get tweets shared in Space | `GET /2/spaces/:id/tweets` | Tweets posted during the Space |

### What We CANNOT Do

| Capability | Why Not |
|-----------|---------|
| **Identify individual listeners** | API only returns aggregate `participant_count`, not a list |
| **Get audio stream URL** | Not exposed in official API; internal HLS via Periscope CDN requires auth cookies |
| **Embed Space audio player** | No embed widget, iframe, or oEmbed exists |
| **Real-time join/leave events** | No webhooks or streaming; must poll REST endpoints |
| **Detect if user is actually listening** | Cross-origin browser security prevents reading popup state |
| **Join a user to a Space programmatically** | Not possible via API |

### Rate Limits

- **300 requests per 15-minute window** (20/min) per App and per User
- `GET /2/spaces/by/creator_ids`: additional 1 req/second limit
- Sufficient for our needs (polling every 30-60 seconds per active Space)

### Authentication

- **OAuth 2.0 Authorization Code with PKCE** (User Context) or **Bearer Token** (App-only)
- Required scopes: `space.read`, `tweet.read`, `users.read`
- We already have X OAuth integration (for `x_connections` Mnesia table)

---

## 2. Existing YouTube Reward System (Reference Pattern)

Our YouTube video BUX system is the direct template. Key files and patterns:

| Component | File | Purpose |
|-----------|------|---------|
| JS Hook | `assets/js/video_watch_tracker.js` (695 lines) | Client-side tracking |
| LiveView | `lib/blockster_v2_web/live/post_live/show.ex` (lines 686-942) | Server-side validation |
| Engagement | `lib/blockster_v2/engagement_tracker.ex` (lines 2812-3020) | Mnesia persistence |
| Minting | `lib/blockster_v2/bux_minter.ex` | BUX minting service |
| Multiplier | `lib/blockster_v2/unified_multiplier.ex` | Reward multiplier calculation |

### Key Patterns to Reuse

1. **Dual Calculation**: JS calculates BUX for real-time display; server recalculates authoritatively for minting
2. **State Gating**: Rewards only accrue when `isPlaying && isTabVisible && !isMuted` — we adapt this to `isPopupOpen && isTabVisible && isSpaceLive`
3. **requestAnimationFrame Tick Loop**: 1-second granularity time accumulation
4. **5-Second Server Sync**: Periodic push events for state persistence
5. **Finalize on Destroy**: Session always completes, even on unexpected close
6. **Async Minting**: `Task.start` for non-blocking BUX minting
7. **Server-Side Penalties**: Excessive tab-switching or suspicious patterns reduce rewards
8. **Guaranteed Earnings**: Pool checked on join, reward guaranteed even if pool depletes mid-session

### Key Differences from YouTube

| Aspect | YouTube System | X Spaces System |
|--------|---------------|-----------------|
| Content location | Embedded iframe on our page | Popup window to x.com |
| Play state detection | YouTube iFrame API events | `window.closed` polling |
| Mute detection | `player.isMuted()` API | Not possible (cross-origin) |
| Content duration | Known (video length) | Unknown (live, open-ended) |
| High water mark | Prevents re-earning same content | N/A — live content is always "new" |
| Max reward | Per-video cap | Per-Space cap (admin configurable) |

---

## 3. Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    ADMIN DASHBOARD                       │
│  Upcoming Spaces | Live Listeners | Rewards Tracker     │
└────────────────────────┬────────────────────────────────┘
                         │ LiveView PubSub
┌────────────────────────┼────────────────────────────────┐
│                   BLOCKSTER SERVER                       │
│                                                         │
│  ┌─────────────────┐  ┌──────────────────────────────┐  │
│  │ SpaceScheduler  │  │ SpaceRewardEngine            │  │
│  │ (GenServer)     │  │ (per-user reward calc)       │  │
│  │                 │  │                              │  │
│  │ • Poll X API    │  │ • Validate listen events     │  │
│  │ • Detect live   │  │ • Calculate BUX per second   │  │
│  │ • Notify users  │  │ • Apply multipliers          │  │
│  │ • Track state   │  │ • Anti-abuse penalties       │  │
│  └────────┬────────┘  │ • Mint BUX on finalize       │  │
│           │           └──────────────┬───────────────┘  │
│           │                          │                   │
│  ┌────────▼──────────────────────────▼───────────────┐  │
│  │              Mnesia Tables                         │  │
│  │  spaces_schedule | space_listen_sessions           │  │
│  │  space_rewards   | space_listener_presence         │  │
│  └───────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
                         │
              ┌──────────┴──────────┐
              │    X API v2         │
              │ GET /2/spaces/:id   │
              │ GET /2/spaces/by/   │
              │   creator_ids       │
              └─────────────────────┘

┌─────────────────────────────────────────────────────────┐
│                    USER BROWSER                          │
│                                                         │
│  ┌───────────────────────┐    ┌──────────────────────┐  │
│  │  Blockster Page       │    │  X Space Popup       │  │
│  │  (SpacesLive)         │    │  (x.com/i/spaces/ID) │  │
│  │                       │    │                      │  │
│  │  • Space cards        │◄───│  window.closed poll  │  │
│  │  • Listen & Earn btn  │    │  (1s interval)       │  │
│  │  • BUX counter        │    │                      │  │
│  │  • Timer display      │    │  User listens to     │  │
│  │  • SpaceTracker hook  │    │  Space audio here    │  │
│  └───────────────────────┘    └──────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

---

## 4. Embedding Strategy

### Primary: Popup Window Approach

Since X provides no embed mechanism, we open the Space in a managed popup:

```javascript
// Open Space in a sized popup window
const spaceWindow = window.open(
  `https://x.com/i/spaces/${spaceId}`,
  'blockster_space',
  'width=500,height=700,menubar=no,toolbar=no,status=no'
);
```

**UX Flow:**
1. User sees upcoming/live Space cards on Blockster Spaces page
2. User clicks **"Listen & Earn BUX"** button
3. Popup opens to `x.com/i/spaces/{space_id}`
4. User logs into X (if not already) and joins the Space in the popup
5. Our page shows a live timer + BUX counter: `"Listening... 5:23 | +26.9 BUX earned"`
6. When user closes popup OR Space ends, session finalizes and BUX is minted
7. User sees reward confirmation with transaction hash

**Why popup over new tab:**
- We can detect `window.closed` (not possible with `window.open` in new tab on some browsers)
- We control the window size for a "companion" feel
- User keeps Blockster visible alongside the Space

### Fallback: New Tab with Visibility Tracking

If popup is blocked (common on mobile), fall back to:
1. Open Space in a new tab via `<a href="..." target="_blank">`
2. Track time on our page using Page Visibility API
3. User manually clicks "I'm back" or we detect tab focus return
4. Less reliable but still functional

---

## 5. Presence Tracking & State Machine

### JS Hook: `SpaceListenTracker`

The hook tracks a state machine with these conditions:

```
EARNING = isPopupOpen && isOurTabVisible && isSpaceLive && hasMinimumTime
```

**States:**
- `idle` — Not listening, no popup
- `connecting` — Popup opened, warmup period (60s before rewards start)
- `listening` — Actively earning BUX (all conditions met)
- `paused` — Popup open but our tab not visible (user switched away from Blockster)
- `popup_closed` — Popup was closed, session may be finalizing
- `ended` — Space ended or session finalized

**Tracking mechanisms:**

| Check | Method | Frequency |
|-------|--------|-----------|
| Popup still open | `spaceWindow.closed` property | 1 second |
| Our tab visible | `document.visibilityState` | Event-driven |
| Space still live | Server polls X API `GET /2/spaces/:id` | 30 seconds |
| Minimum time met | Local timer | Continuous |

### Server-Side Space State Polling

A `SpaceScheduler` GenServer polls the X API to track Space lifecycle:

```elixir
# Every 30 seconds for active Spaces with listeners
case get_space_state(space_id) do
  "live" -> :continue
  "ended" -> broadcast_space_ended(space_id)  # All listeners finalize
  _ -> :noop
end
```

When the Space ends, we broadcast to all connected listeners via PubSub, triggering their session finalization regardless of popup state.

---

## 6. BUX Reward System

### Reward Calculation

Follows the YouTube pattern — dual calculation with server authority:

**Client-side (for display):**
```javascript
// Every second while EARNING state is active
sessionSeconds += 1;
sessionBux = (sessionSeconds / 60) * buxPerMinute * userMultiplier;
// Update UI: "Listening 5:23 | +26.9 BUX"
```

**Server-side (authoritative, on finalize):**
```elixir
session_minutes = session_seconds / 60
session_bux = session_minutes * space.bux_per_minute * user_multiplier
session_bux = min(session_bux, space.max_reward - already_earned)
session_bux = apply_penalties(session_bux, metrics)
```

### Configurable Parameters (per Space, set by admin)

| Parameter | Default | Description |
|-----------|---------|-------------|
| `bux_per_minute` | `1.0` | Base BUX earned per minute of listening |
| `max_reward` | `nil` (no cap) | Maximum BUX earnable from this Space |
| `warmup_seconds` | `60` | Seconds before rewards start accruing |
| `pool_budget` | `nil` (unlimited) | Total BUX budget for this Space across all listeners |

### Multiplier System

Reuses `UnifiedMultiplier` (same as video/article rewards):
- X score multiplier (0-100 → 1.0-10.0x)
- Phone verification multiplier (0.5x unverified, 1.0x verified)
- ROGUE balance multiplier
- Wallet token multiplier

### Session Lifecycle

```
1. User clicks "Listen & Earn"
2. Server checks: user logged in, Space is live, pool available
3. Server creates listen session in Mnesia (status: :connecting)
4. 60-second warmup (popup must stay open)
5. Status transitions to :listening, BUX starts accruing
6. Every 5 seconds: client pushes heartbeat to server
7. Session ends when: popup closed, Space ends, or max reward reached
8. Server validates session_seconds, recalculates BUX, applies penalties
9. BUX minted via BuxMinter service (async Task.start)
10. Mnesia record updated with final amounts and tx_hash
```

---

## 7. Anti-Abuse Measures

### Client-Side

| Measure | Implementation |
|---------|---------------|
| **Warmup period** | No rewards for first 60 seconds (prevents quick open/close farming) |
| **Popup open check** | `window.closed` polled every 1 second |
| **Tab visibility** | `document.visibilityState` — pauses if user leaves Blockster tab |
| **Single Space limit** | Only one Space earning session at a time |
| **Heartbeat required** | 5-second server heartbeats; missing 3 consecutive → session paused |

### Server-Side

| Measure | Implementation |
|---------|---------------|
| **Server BUX recalculation** | Never trust client's BUX amount; recalculate from `session_seconds` |
| **Space liveness verification** | Server polls X API to confirm Space is still live |
| **Max reward cap** | Per-Space configurable cap on total earnable BUX |
| **Pool budget** | Total BUX budget per Space; no more rewards once depleted |
| **Tab-away penalty** | >5 tab-away events → 10% reward reduction |
| **Suspicious timing penalty** | If `session_seconds` exceeds Space actual duration → reject |
| **Daily Space limit** | Max N Spaces per user per day earning BUX (configurable, default: 5) |
| **Minimum session duration** | Sessions under 2 minutes earn nothing |
| **Rate limiting** | Max 1 concurrent earning session per user |
| **IP-based limits** | Flag multiple users earning from same IP |

### What We Cannot Detect (Honest Limitations)

- Whether the user is actually listening to audio in the popup (cross-origin restriction)
- Whether the user muted the X Space tab
- Whether the user is genuinely engaged vs. just keeping a window open

**Mitigation**: The warmup period, tab visibility tracking, heartbeat checks, and daily caps make casual farming tedious enough to discourage it without perfectly detecting engagement. This is an acceptable tradeoff for a reward system — similar to how our video system can't truly verify someone is "watching."

---

## 8. Admin Interface

### Spaces Management Page (`/admin/spaces`)

**Upcoming Spaces Panel:**
- List of scheduled Spaces (pulled from X API by creator IDs we configure)
- Admin can manually add Spaces by URL/ID
- Configure per-Space: `bux_per_minute`, `max_reward`, `warmup_seconds`, `pool_budget`
- Toggle: enable/disable earning for each Space
- Auto-detect when scheduled Space goes live

**Live Space Dashboard (real-time):**

```
┌──────────────────────────────────────────────────────┐
│  🎙️ LIVE: "Blockster Weekly AMA"                     │
│  Host: @blockster_io | Started: 14 min ago           │
│  X Participants: 234 | Blockster Listeners: 47       │
├──────────────────────────────────────────────────────┤
│                                                      │
│  Active Listeners (47)           BUX Being Earned    │
│  ┌─────────────────────────────────────────────────┐ │
│  │ User          │ Duration │ BUX Earned │ Status  │ │
│  ├───────────────┼──────────┼────────────┼─────────┤ │
│  │ @alice        │ 12:34    │ 12.6 BUX   │ ● live  │ │
│  │ @bob          │ 08:21    │ 8.4 BUX    │ ● live  │ │
│  │ @carol        │ 03:45    │ 3.8 BUX    │ ◐ warm  │ │
│  │ @dave         │ 14:02    │ 14.0 BUX   │ ○ away  │ │
│  └─────────────────────────────────────────────────┘ │
│                                                      │
│  Total BUX Distributed: 482.3 / 5000 pool            │
│  Avg Session: 9:12 | Median: 7:45                    │
│  ████████░░░░░░░░░░░░ 9.6% of pool used              │
└──────────────────────────────────────────────────────┘
```

**Key Admin Features:**
- Real-time listener count with status indicators (listening, warming up, tab-away)
- Per-listener BUX accrual visible in real-time
- Pool budget progress bar
- Ability to pause/stop rewards for a Space mid-session
- Export session data to CSV
- Alerts when pool is running low

### Spaces History Page (`/admin/spaces/history`)

- Past Spaces with aggregate stats: total listeners, total BUX distributed, avg session duration
- Per-Space drill-down: individual listener sessions, rewards, tx hashes
- Flagged suspicious sessions (excessive tab-away, very short sessions, IP clustering)

### Configuration (`/admin/spaces/settings`)

- Default `bux_per_minute` for new Spaces
- Default `max_reward` cap
- Daily Space earning limit per user
- Pool budget defaults
- X API creator IDs to monitor (whose Spaces to display)
- Auto-enable earning for Spaces by configured hosts

---

## 9. Database Schema

### Postgres Tables

```sql
-- Spaces that admins have configured for display/earning
CREATE TABLE spaces (
  id BIGSERIAL PRIMARY KEY,
  space_id VARCHAR(255) NOT NULL,          -- X Space ID (e.g., "1DXxyRYNejbKM")
  title VARCHAR(500),
  host_username VARCHAR(255),
  host_user_id VARCHAR(255),
  state VARCHAR(50) DEFAULT 'scheduled',   -- scheduled, live, ended
  scheduled_start TIMESTAMPTZ,
  actual_start TIMESTAMPTZ,
  ended_at TIMESTAMPTZ,
  bux_per_minute DECIMAL DEFAULT 1.0,
  max_reward DECIMAL,                      -- per-user cap, nil = no cap
  warmup_seconds INTEGER DEFAULT 60,
  pool_budget DECIMAL,                     -- total BUX budget, nil = unlimited
  pool_spent DECIMAL DEFAULT 0,
  earning_enabled BOOLEAN DEFAULT true,
  participant_count INTEGER DEFAULT 0,     -- from X API polling
  created_by_id BIGINT REFERENCES users(id),
  inserted_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL
);

CREATE UNIQUE INDEX spaces_space_id_index ON spaces(space_id);
CREATE INDEX spaces_state_index ON spaces(state);
CREATE INDEX spaces_scheduled_start_index ON spaces(scheduled_start);

-- Completed listen sessions (permanent record)
CREATE TABLE space_listen_sessions (
  id BIGSERIAL PRIMARY KEY,
  space_id VARCHAR(255) NOT NULL,          -- X Space ID
  user_id BIGINT NOT NULL REFERENCES users(id),
  started_at TIMESTAMPTZ NOT NULL,
  ended_at TIMESTAMPTZ,
  total_seconds INTEGER DEFAULT 0,         -- earned seconds (excluding warmup, away time)
  raw_seconds INTEGER DEFAULT 0,           -- wall clock seconds popup was open
  bux_earned DECIMAL DEFAULT 0,
  multiplier DECIMAL DEFAULT 1.0,
  tx_hash VARCHAR(255),                    -- BUX mint transaction hash
  end_reason VARCHAR(50),                  -- popup_closed, space_ended, max_reached, manual
  tab_away_count INTEGER DEFAULT 0,
  heartbeat_gaps INTEGER DEFAULT 0,        -- missed heartbeats
  penalty_applied DECIMAL DEFAULT 0,       -- percentage penalty applied
  inserted_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX space_listen_sessions_space_id_index ON space_listen_sessions(space_id);
CREATE INDEX space_listen_sessions_user_id_index ON space_listen_sessions(user_id);
CREATE INDEX space_listen_sessions_started_at_index ON space_listen_sessions(started_at);
```

### Mnesia Tables (Real-Time State)

```elixir
# Active listen sessions (ephemeral, real-time tracking)
# Table: :space_listener_presence
# Type: :set
# Key: {user_id, space_id}
%{
  key: {user_id, space_id},
  user_id: integer,
  space_id: string,
  status: :connecting | :listening | :paused | :finalizing,
  started_at: integer,           # Unix timestamp
  earned_seconds: integer,       # Seconds that count toward BUX
  last_heartbeat: integer,       # Unix timestamp of last heartbeat
  tab_away_count: integer,
  bux_accrued: float,            # Running BUX total for display
  warmup_complete: boolean
}

# Space state cache (polled from X API)
# Table: :space_state_cache
# Type: :set
# Key: space_id
%{
  space_id: string,
  state: :scheduled | :live | :ended,
  participant_count: integer,
  last_polled_at: integer,       # Unix timestamp
  host_username: string,
  title: string
}
```

---

## 10. Implementation Phases

### Phase 1: Space Scheduling & Display (Backend + UI)
**New files**: ~4 | **Modified**: ~3 | **Estimate**: ~15 tests

- Postgres migration for `spaces` table
- `BlocksterV2.Spaces` context (CRUD for spaces)
- `SpaceScheduler` GenServer — polls X API for configured host creator IDs, detects live/ended
- `SpacesLive` LiveView — displays upcoming and live Space cards
- Space card component with title, host, scheduled time, participant count, status badge
- Admin: add/edit Space configuration (manual add by URL, auto-detect from hosts)
- X API client module for Spaces endpoints

### Phase 2: Listen & Earn Core (JS Hook + LiveView)
**New files**: ~3 | **Modified**: ~4 | **Estimate**: ~20 tests

- `SpaceListenTracker` JS hook (popup management, state machine, heartbeats)
- LiveView handlers for: `space-listen-start`, `space-heartbeat`, `space-listen-complete`
- Mnesia table: `space_listener_presence` (real-time session tracking)
- Warmup timer logic (60s before rewards)
- BUX accrual display (timer + counter in UI)
- Session finalization on popup close / Space end
- PubSub broadcasts for listener count updates

### Phase 3: Reward Calculation & Minting
**New files**: ~2 | **Modified**: ~3 | **Estimate**: ~15 tests

- `SpaceRewardEngine` module — server-side BUX calculation with multipliers
- Postgres migration for `space_listen_sessions` table
- Session persistence: Mnesia → Postgres on finalize
- BUX minting integration (async via BuxMinter service)
- Pool budget tracking and depletion handling
- Penalty calculation (tab-away, heartbeat gaps)
- Max reward cap enforcement

### Phase 4: Admin Dashboard
**New files**: ~2 | **Modified**: ~2 | **Estimate**: ~15 tests

- `SpacesAdminLive` — real-time admin dashboard
- Live listener table with status, duration, BUX accrued (updates via PubSub)
- Pool budget progress bar
- Space history view with aggregate stats
- Per-Space drill-down: individual sessions, tx hashes
- Pause/stop rewards control
- Export to CSV

### Phase 5: Anti-Abuse & Polish
**New files**: ~1 | **Modified**: ~4 | **Estimate**: ~15 tests

- Daily Space earning limit per user
- Minimum session duration enforcement
- Concurrent session prevention
- IP-based flagging for suspicious patterns
- Suspicious session flagging in admin
- Mobile fallback (new tab instead of popup)
- Space ended notification in UI
- Anonymous user flow (preview timer, signup prompt)

**Total Estimate: ~80 tests across 5 phases**

---

## 11. ToS Risk Analysis & Mitigation

### The Risk

X's Developer Agreement states:
> "Your service shouldn't compensate people to take actions on X, as that results in inauthentic engagement that degrades the health of the platform."
> "You may not sell or receive monetary or virtual compensation for any X actions."

**"Actions on X"** explicitly includes: Posts, follows, unfollows, reposts, likes, comments, replies. **Joining a Space is not explicitly listed**, but "actions on X" is broad.

### Risk Assessment: MODERATE

- Joining/listening to a Space IS an X action
- However, Spaces listening is passive consumption (like viewing a tweet), not engagement amplification
- X's policy targets inauthentic engagement that "degrades health" — rewarding genuine listening arguably doesn't degrade anything
- No enforcement precedent found for Space listening rewards specifically
- Risk is primarily around API access revocation, not legal action

### Mitigation Strategy

1. **Frame as Blockster platform engagement, not X actions:**
   - Rewards are for "attending a Blockster event" that happens to be hosted on X Spaces
   - The BUX reward is tied to time spent on the Blockster platform, not time in the X Space
   - Users earn for having Blockster open, not for joining the Space

2. **Don't use the X API to verify participation:**
   - We track presence entirely on our side (popup open + heartbeats)
   - We don't call the API to check if a specific user is in the Space
   - We only use the API for Space metadata (title, state, schedule)

3. **Conservative API usage:**
   - Read-only access (no posting, no engagement)
   - Low rate (polling every 30-60s, well within limits)
   - No automation of user actions

4. **Graceful degradation if API revoked:**
   - The system works without the X API — admin can manually add Space details
   - API is only used for auto-discovery and state polling, not core functionality
   - Earning system is entirely self-contained on Blockster

---

## 12. API Costs

| Item | Cost | Notes |
|------|------|-------|
| X API Basic tier | $200/month | Required for Spaces lookup endpoints |
| BUX Minter service | Already deployed | Existing infrastructure |
| Mnesia storage | Negligible | Small records, ephemeral |
| Postgres storage | Negligible | Adding 2 tables to existing DB |

**Alternative: X API pay-per-use** (closed beta as of Nov 2025)
- 1 credit per Space lookup
- If monitoring 5 Spaces, polling every 30s = ~15,000 calls/day
- Cost depends on credit pricing (TBD)

**Recommendation**: Start with Basic tier ($200/month). The 300 req/15min limit gives us 28,800 requests/day — more than enough for polling multiple Spaces.

---

## 13. Limitations & Future Opportunities

### Known Limitations

1. **Cannot verify actual listening** — We track popup open state, not audio consumption. Users could open the popup and mute the X tab. Mitigation: warmup period + session caps make this tedious to exploit at scale.

2. **Popup blockers** — Some browsers/mobile block popups. Fallback: new tab with degraded tracking.

3. **X login required** — Users must be logged into X to join Spaces. We can't control this.

4. **No listener identification via API** — We can't cross-reference our users with X's listener list. We rely entirely on our own tracking.

5. **Space discovery is limited** — We can only auto-discover Spaces from creator IDs we configure. Manual addition covers the rest.

### Future Opportunities

1. **Self-hosted audio rooms** — Use LiveKit/Agora to host our own audio alongside X Spaces. Full tracking control, no ToS risk.

2. **Recorded Space playback** — Hosts can provide Space recordings. We could build a YouTube-like player for recorded Spaces with full tracking (high water mark, mute detection).

3. **Browser extension** — A Blockster browser extension could detect X Space audio playing and verify engagement. High friction but high accuracy.

4. **X API expansion** — If X adds embed widgets or listener APIs in the future, we can upgrade the system.

5. **Quizzes/polls during Spaces** — Require users to answer questions during the Space to prove engagement. This would be the strongest anti-abuse measure.

---

## Appendix: Key Technical Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Popup vs iframe | Popup | X provides no embed; popup allows `window.closed` detection |
| Polling vs webhooks | Polling | X Spaces API has no webhook support |
| Mnesia vs Postgres for active sessions | Mnesia | Real-time, distributed, in-memory; finalized to Postgres |
| 1 GenServer vs per-Space GenServer | 1 `SpaceScheduler` | Simpler; we'll have few concurrent Spaces |
| Reward on finalize vs incremental | On finalize | Server authority; prevents partial mint complexity |
| Warmup period | 60 seconds | Prevents quick open/close farming |
