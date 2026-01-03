# Engagement Tracking System

> **Note (January 2026)**: Hub tokens have been removed from the application. All reading rewards are now paid in BUX tokens only, regardless of which hub the content belongs to.

## Overview

The engagement tracking system monitors user reading behavior on article pages to determine reading quality and detect bot-like behavior. It calculates an engagement score from 1-10 based on multiple behavioral signals.

## Architecture

The system consists of three main components:

1. **JavaScript Client** (`assets/js/engagement_tracker.js`) - Tracks user behavior in the browser
2. **Elixir Backend** (`lib/blockster_v2/engagement_tracker.ex`) - Calculates scores and stores data
3. **Mnesia Storage** - Distributed in-memory database for real-time data

```
┌─────────────────────────────────────────────────────────────────┐
│                         Browser                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │              EngagementTracker Hook                      │    │
│  │  - Time tracking (requestAnimationFrame)                 │    │
│  │  - Scroll depth calculation                              │    │
│  │  - Scroll speed measurement                              │    │
│  │  - Visibility detection                                  │    │
│  └─────────────────────────────────────────────────────────┘    │
│                              │                                   │
│                   LiveView Events                                │
│              "article-visited" / "article-read"                  │
└──────────────────────────────┼──────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Phoenix Server                              │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                  PostLive.Show                           │    │
│  │  - Handles events from client                            │    │
│  │  - Calls EngagementTracker module                        │    │
│  └─────────────────────────────────────────────────────────┘    │
│                              │                                   │
│                              ▼                                   │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │               EngagementTracker Module                   │    │
│  │  - Calculates engagement score                           │    │
│  │  - Writes to Mnesia                                      │    │
│  └─────────────────────────────────────────────────────────┘    │
│                              │                                   │
│                              ▼                                   │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                    Mnesia Database                       │    │
│  │  - Table: user_post_engagement                           │    │
│  │  - Replicated across cluster nodes                       │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

## Data Flow

### 1. Page Load (article-visited)

When a user lands on an article page:

1. The `EngagementTracker` LiveView hook mounts
2. Word count is calculated from the TipTap JSON content
3. Minimum read time is calculated: `word_count / 5` (300 wpm)
4. An `article-visited` event is sent to the server
5. A record is created in Mnesia with engagement_score = 1

### 2. Reading (continuous tracking)

While the user reads:

- **Time tracking**: Uses `requestAnimationFrame` for accurate second-by-second tracking
- **Scroll tracking**: Throttled to 100ms intervals to measure scroll behavior
- **Visibility tracking**: Pauses when tab loses focus

### 3. Article Completion (article-read)

When the user scrolls to the bottom of the article (bottom of `#post-content` is visible):

1. All metrics are sent to the server
2. Engagement score is calculated
3. Record is updated in Mnesia
4. Score is pushed back to client

## Metrics Collected

| Metric | Description | Collection Method |
|--------|-------------|-------------------|
| `time_spent` | Seconds spent on page (active only) | requestAnimationFrame counter |
| `min_read_time` | Expected read time based on word count | `word_count / 5` |
| `scroll_depth` | 0-100% of article scrolled | Viewport position relative to article |
| `reached_end` | Boolean - did bottom become visible | `articleRect.bottom <= window.innerHeight` |
| `scroll_events` | Number of scroll events | Counter incremented on each throttled scroll |
| `avg_scroll_speed` | Average pixels/second scrolled | Rolling average of last 50 measurements |
| `max_scroll_speed` | Peak scroll speed detected | Max value tracker |
| `scroll_reversals` | Times user scrolled back up | Direction change counter |
| `focus_changes` | Tab visibility changes | visibilitychange event counter |

## Scoring Algorithm

The engagement score is calculated from 4 components totaling 10 points:

### Base Score: 1 point
Always awarded.

### Time Score: 0-3 points

Based on `time_spent / min_read_time` ratio:

| Ratio | Points | Interpretation |
|-------|--------|----------------|
| >= 90% | 3.0 | Full reading time |
| >= 70% | 2.0 | Good reading pace |
| >= 50% | 1.0 | Moderate pace |
| < 50% | 0.0 | Too fast |

### Depth Score: 0-2 points

Based on scroll depth percentage:

| Depth | Points | Interpretation |
|-------|--------|----------------|
| >= 100% | 2.0 | Reached the end |
| >= 70% | 1.5 | Most of article |
| >= 50% | 1.0 | Half of article |
| >= 30% | 0.5 | Partial read |
| < 30% | 0.0 | Barely scrolled |

### Scroll Naturalness Score: 0-4 points

Based on scroll event count and average speed:

| Condition | Points | Interpretation |
|-----------|--------|----------------|
| < 3 events | 0.0 | Bot-like (no scrolling) |
| avg_speed > 5000 | 0.0 | Bot-like (automated scroll) |
| >= 50 events, avg < 1000 | 4.0 | Excellent - natural reading |
| >= 50 events, avg < 2000 | 3.0 | Good - some fast scrolling |
| >= 25 events, avg < 2000 | 2.0 | Moderate engagement |
| >= 10 events | 1.0 | Light engagement |
| >= 3 events | 0.5 | Minimal engagement |

### Score Labels

| Score | Color | Label |
|-------|-------|-------|
| 9-10 | Green | Excellent Reader |
| 7-8 | Green | Good Reader |
| 5-6 | Blue | Moderate Engagement |
| 3-4 | Yellow | Light Skimmer |
| 1-2 | Red | Quick Glance |

## Bot Detection

The system detects bot-like behavior through:

1. **Too few scroll events** (< 3): Indicates page was opened but not scrolled
2. **Extremely fast average scroll speed** (> 5000 px/s): Indicates automated scrolling
3. **Time too short**: Reading faster than 300 wpm is flagged

Note: **Max scroll speed is NOT used** for bot detection because momentary fast scrolls are normal human behavior (e.g., quickly scrolling past images).

## Database Schema

```elixir
%{
  name: :user_post_engagement,
  type: :set,
  attributes: [
    :key,                    # {user_id, post_id} tuple
    :user_id,
    :post_id,
    :time_spent,             # Integer - seconds
    :min_read_time,          # Integer - calculated minimum
    :scroll_depth,           # Integer - 0-100
    :reached_end,            # Boolean
    :scroll_events,          # Integer - count
    :avg_scroll_speed,       # Float - pixels/second
    :max_scroll_speed,       # Float - pixels/second
    :scroll_reversals,       # Integer - count
    :focus_changes,          # Integer - count
    :engagement_score,       # Integer - 1-10
    :is_read,                # Boolean
    :created_at,             # Unix timestamp
    :updated_at              # Unix timestamp
  ],
  index: [:user_id, :post_id, :engagement_score, :is_read]
}
```

## Edge Cases Handled

### Navigation from Scrolled Page
When navigating from a scrolled homepage to an article, the scroll position persists momentarily. A 500ms delay before initializing scroll tracking prevents false "end reached" triggers.

### Short Articles
Articles shorter than the viewport height will trigger "end reached" on the first scroll check (after the 1-second delay).

### Tab Switching
Time tracking pauses when the tab loses focus. Focus changes are counted but do not affect the score.

### Anonymous Users
Tracking is skipped entirely for users without a session. The hook checks for `anonymous` user ID and returns early.

### Twitter Embeds
The post content div uses `phx-update="ignore"` to prevent LiveView re-renders from causing Twitter widgets to flicker when engagement data updates.

## LiveView Integration

### Template Setup

```heex
<div
  id="engagement-tracker"
  phx-hook="EngagementTracker"
  data-user-id={@current_user && @current_user.id || "anonymous"}
  data-post-id={@post.id}
  data-word-count={@word_count}
>
```

### Event Handlers

```elixir
# Handle initial visit
def handle_event("article-visited", %{"min_read_time" => min_read_time}, socket)

# Handle article completion
def handle_event("article-read", params, socket)
```

## Configuration

### Reading Speed
Currently set to 5 words/second (300 wpm). Adjust in both files:
- `engagement_tracker.ex`: `calculate_min_read_time/1`
- `engagement_tracker.js`: `this.minReadTime = Math.max(Math.floor(this.wordCount / 5), 10)`

### Scroll Tracking
- Throttle interval: 100ms
- Initial delay: 500ms (to let page settle after navigation)
- Speed measurement window: Last 50 scroll events

### Score Thresholds
All scoring thresholds are in `engagement_tracker.ex` in the `calculate_engagement_score/9` function.

## BUX Rewards System

The engagement tracking system ties directly into BUX token rewards. Users earn BUX for reading articles and sharing them on social media.

### Storage Architecture

All reward data is stored in **Mnesia** for fast, distributed access:
- **Read rewards**: `user_post_rewards` Mnesia table
- **X share rewards**: `share_rewards` Mnesia table (keyed by `{user_id, post_id}`)
- **User multipliers**: `user_multipliers` Mnesia table

**Important**: The retweet flow uses Mnesia only. No PostgreSQL queries occur during the retweet action - user and post data are already loaded in the LiveView socket from page mount.

### Reward Types

Users can earn BUX from three activities per article:

1. **Read Reward** - Earned when completing an article with sufficient engagement
2. **X (Twitter) Share Reward** - Earned for sharing the article on X
3. **LinkedIn Share Reward** - Earned for sharing the article on LinkedIn

Each reward type can only be earned once per user per article.

### BUX Calculation Formula

```
bux_earned = (engagement_score / 10) * base_bux_reward * user_multiplier
```

Where:
- **engagement_score**: 1-10 score from the engagement tracking algorithm
- **base_bux_reward**: Per-article reward amount set by admins (default: 1)
- **user_multiplier**: User-specific multiplier based on social presence (default: 1)

#### Example Calculations

| Engagement Score | Base Reward | Multiplier | BUX Earned |
|-----------------|-------------|------------|------------|
| 10 | 1 | 1.0 | 1.00 |
| 10 | 5 | 1.0 | 5.00 |
| 10 | 5 | 1.5 | 7.50 |
| 7 | 1 | 1.0 | 0.70 |
| 5 | 10 | 2.0 | 10.00 |

### Base BUX Reward Configuration

Each article has a `base_bux_reward` field (PostgreSQL, default: 1) that determines the potential reward. Admins can adjust this per article to incentivize reading specific content.

```elixir
# In Post schema
field :base_bux_reward, :integer, default: 1
```

### User Multipliers

User multipliers are stored in the `user_multipliers` Mnesia table and can boost earnings:

- **x_multiplier**: Boost for verified X/Twitter presence
- **linkedin_multiplier**: Boost for verified LinkedIn presence
- **personal_multiplier**: Boost for verified personal website
- **rogue_multiplier**: Platform-specific boost
- **overall_multiplier**: Computed total multiplier

### Rewards Recording Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    User Finishes Reading                         │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│               Calculate Engagement Score (1-10)                  │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                Calculate BUX Earned                              │
│     (engagement_score / 10) * base_bux_reward * multiplier       │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│              record_read_reward(user_id, post_id, bux)           │
│                                                                  │
│   Check existing record:                                         │
│   - No record → Create new record with read_bux                  │
│   - Has record, no read_bux → Update with read_bux               │
│   - Has record, has read_bux → Return {:already_rewarded, bux}   │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Push Result to Client                         │
│   - Show earned BUX if new                                       │
│   - Show "already earned" notification if duplicate              │
└─────────────────────────────────────────────────────────────────┘
```

### Already-Rewarded Detection

When a user attempts to earn a reward they've already received:

1. The `record_*_reward` functions check for existing rewards
2. If found, they return `{:already_rewarded, existing_bux}`
3. The LiveView displays a notification showing previously earned amount
4. No duplicate rewards are ever granted

### user_post_rewards Mnesia Table

```elixir
%{
  name: :user_post_rewards,
  type: :set,
  attributes: [
    :key,                    # {user_id, post_id} tuple as primary key
    :user_id,
    :post_id,
    :read_bux,               # BUX earned for reading the article
    :read_paid,              # Boolean - has read reward been paid out
    :read_tx_id,             # Transaction ID of read reward payout
    :x_share_bux,            # BUX earned for sharing on X (Twitter)
    :x_share_paid,           # Boolean - has X share reward been paid out
    :x_share_tx_id,          # Transaction ID of X share payout
    :linkedin_share_bux,     # BUX earned for sharing on LinkedIn
    :linkedin_share_paid,    # Boolean - has LinkedIn share reward been paid out
    :linkedin_share_tx_id,   # Transaction ID of LinkedIn share payout
    :total_bux,              # Total BUX earned for this post
    :total_paid_bux,         # Total BUX that has been paid out
    :created_at,             # Unix timestamp
    :updated_at              # Unix timestamp
  ],
  index: [:user_id, :post_id, :total_bux, :read_paid, :x_share_paid, :linkedin_share_paid]
}
```

### Mnesia Tuple Structure

Mnesia stores records as tuples. **Important:** Index 0 is always the table name, so field indices are off by one from the schema definition:

```
Index 0:  :user_post_rewards (table name)
Index 1:  key ({user_id, post_id})
Index 2:  user_id
Index 3:  post_id
Index 4:  read_bux
Index 5:  read_paid
Index 6:  read_tx_id
Index 7:  x_share_bux
Index 8:  x_share_paid
Index 9:  x_share_tx_id
Index 10: linkedin_share_bux
Index 11: linkedin_share_paid
Index 12: linkedin_share_tx_id
Index 13: total_bux
Index 14: total_paid_bux
Index 15: created_at
Index 16: updated_at
```

### API Functions

```elixir
# Calculate BUX earned
EngagementTracker.calculate_bux_earned(engagement_score, base_bux_reward, user_multiplier)

# Record rewards (returns {:ok, bux} or {:already_rewarded, existing_bux})
EngagementTracker.record_read_reward(user_id, post_id, bux_earned)
EngagementTracker.record_x_share_reward(user_id, post_id, bux_earned)
EngagementTracker.record_linkedin_share_reward(user_id, post_id, bux_earned)

# Query rewards
EngagementTracker.get_rewards(user_id, post_id)      # Returns raw Mnesia tuple
EngagementTracker.get_rewards_map(user_id, post_id)  # Returns map with named fields

# Admin cleanup
EngagementTracker.delete_rewards(user_id, post_id)
```

### Payout Tracking

The `*_paid` and `*_tx_id` fields track blockchain payouts:

- `read_paid`: Set to `true` when BUX tokens are transferred to user's wallet
- `read_tx_id`: Transaction hash from the blockchain transfer
- Same pattern for `x_share_*` and `linkedin_share_*`

This enables:
- Resumable payout processing (pick up where you left off)
- Audit trail of all payouts
- Reconciliation between Mnesia records and blockchain state

## Future Improvements

Potential enhancements:
- Track reading position (where user stops/resumes)
- Measure time spent in viewport per section
- A/B test different scoring algorithms
- Add engagement analytics dashboard
- Aggregate engagement scores for article quality metrics
- Implement automated payout scheduling
- Add referral bonuses for sharing
