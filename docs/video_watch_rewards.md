# Video Watch Rewards System

## Overview

This document describes the implementation of a video watching rewards feature for Blockster posts. Users can earn BUX tokens from **two separate reward streams** on video posts:

1. **Video Watch Reward** - One-time reward for watching the embedded video
2. **Read Reward** - Existing scroll-based reward for reading the article content below the video

These rewards are **completely independent** - users can earn from both by watching the video AND reading the article.

---

## Dual Reward System

### Key Principles

| Aspect | Video Watch Reward | Read Reward (Existing) |
|--------|-------------------|------------------------|
| **Trigger** | Watching video in modal | Scrolling article content |
| **Earning Method** | Time-based (BUX per minute watched) | Score-based (engagement 1-10) |
| **One-Time?** | Yes - once modal closes, done | Yes - once article completed |
| **UI Location** | Inside video modal (bottom-right) | Fixed panel (bottom-right of page) |
| **Can Earn Both?** | Yes | Yes |
| **Separate Pools?** | No - both draw from post's BUX pool | Same pool |

### User Experience Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│  1. User visits video post                                               │
│     - Sees featured image with PLAY button overlay                       │
│     - Sees existing "Earning BUX" panel (bottom-right) for READ reward  │
├─────────────────────────────────────────────────────────────────────────┤
│  2. User clicks PLAY button                                              │
│     - Full-screen video modal opens                                      │
│     - VIDEO earnings panel appears inside modal (bottom-right)          │
│     - Counter shows "+0.0 BUX" and updates every 5 seconds              │
│     - READ reward panel is hidden while modal is open                   │
├─────────────────────────────────────────────────────────────────────────┤
│  3. User watches video                                                   │
│     - BUX accumulates based on watch time                               │
│     - Earnings PAUSE when: video paused, tab hidden, window blur        │
│     - Progress bar shows % of video watched                             │
├─────────────────────────────────────────────────────────────────────────┤
│  4. User closes modal OR video ends                                      │
│     - Video reward is FINALIZED and minted                              │
│     - Modal shows "Earned X BUX" confirmation briefly                   │
│     - User returns to article page                                       │
│     - VIDEO reward is now LOCKED (can't earn more from video)           │
├─────────────────────────────────────────────────────────────────────────┤
│  5. User continues on article page                                       │
│     - "Video Earned" badge shows what they got from video               │
│     - READ reward panel resumes tracking (if not already completed)     │
│     - User can scroll article to earn ADDITIONAL read reward            │
├─────────────────────────────────────────────────────────────────────────┤
│  6. User scrolls to end of article                                       │
│     - READ reward is calculated and minted (separate transaction)       │
│     - Both rewards now shown: Video X BUX + Read Y BUX                  │
└─────────────────────────────────────────────────────────────────────────┘
```

### Important Behavior Notes

1. **Video reward tracks HIGHEST POSITION REACHED (High Water Mark)**
   - User earns BUX only when watching BEYOND their previous furthest point
   - Rewatching already-seen portions does NOT earn additional BUX
   - User can earn the full video reward across multiple sessions
   - **Seeking behavior:**
     - If user seeks PAST their high water mark → starts earning immediately
     - If user seeks BEFORE their high water mark → does NOT earn until they pass it
   - **Skip to High Water Mark button:** When rewatching content, a "Rewatching - skip ahead to resume earning" button appears. Clicking it automatically seeks the video to just past the user's high water mark so they can immediately start earning again.

   **Example (10-minute video, high water mark at 2:30):**

   | Action | Earns BUX? | Why |
   |--------|------------|-----|
   | Seek to 0:00, watch to 1:30 | ❌ No | Position never exceeds 2:30 |
   | Seek to 2:00, watch to 3:30 | ✅ Yes (1 min) | Earns from 2:30→3:30 only |
   | Seek to 3:00, watch to 5:00 | ✅ Yes (2 min) | Position immediately > high water mark |
   | Seek to 8:00, watch to 10:00 | ✅ Yes (2 min) | All new territory |

2. **Read reward is SEPARATE and unaffected**
   - Works exactly as before (engagement score based on scroll depth + time)
   - Video watching does NOT count toward read reward
   - User must scroll the article content to earn read reward

3. **Both rewards draw from the SAME pool**
   - Post has a single BUX pool (e.g., 1000 BUX)
   - Video rewards deduct from this pool
   - Read rewards also deduct from this pool
   - If pool is empty, neither reward type is available

4. **UI shows both reward states**
   - While video modal is open: Only video earnings panel visible
   - After video modal closes: Video earned badge + Read earnings panel
   - After both complete: Both earned amounts shown with transaction links

5. **Video reward is MINTED when modal closes**
   - BUX is minted for the NEW watch time when user closes modal
   - User can return later to watch more and earn more (up to full video)
   - Once user has watched to 100% of video, no more video BUX can be earned

### High Water Mark Tracking (Technical)

The YouTube iFrame API provides `getCurrentTime()` which returns the current playback position in seconds. We poll this every second while video is playing and track the maximum position reached.

```
┌─────────────────────────────────────────────────────────────────────────┐
│  Video Timeline (10 minute video = 600 seconds)                         │
│                                                                          │
│  Stored in Mnesia: highest_position_reached = 150 (2:30)                │
│                                                                          │
│  ═══════════════════════════════════════════════════════════════════    │
│  0:00          2:30                                             10:00   │
│  ├──────────────┼─────────────────────────────────────────────────┤    │
│  │▓▓▓▓▓▓▓▓▓▓▓▓▓▓│░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░│    │
│  │   WATCHED    │              NOT YET WATCHED                    │    │
│  │  (no BUX)    │              (earns BUX)                        │    │
│  ═══════════════════════════════════════════════════════════════════    │
│                                                                          │
│  Current Session Logic:                                                  │
│  - If currentPosition <= 150: this.sessionEarnableTime = 0              │
│  - If currentPosition > 150: this.sessionEarnableTime += delta          │
│                                                                          │
│  On Modal Close:                                                         │
│  - new_high_water_mark = max(old_high_water_mark, session_max_position) │
│  - bux_earned = sessionEarnableTime / 60 * bux_per_minute               │
│  - Mint BUX, update Mnesia with new high water mark                     │
└─────────────────────────────────────────────────────────────────────────┘
```

**Key YouTube API Methods Used:**
- `getCurrentTime()` - Returns current playback position in seconds (polled every second)
- `getDuration()` - Returns total video duration in seconds
- `onStateChange` event - Detects play/pause/end states to start/stop tracking

Reference: [YouTube IFrame Player API](https://developers.google.com/youtube/iframe_api_reference)

### Edge Case: User Seeks Past High Water Mark

**Question**: If user's high water mark is at 2:30 and they seek to 5:00, do they earn for 2:30 → 5:00 immediately?

**Answer**: **NO** - they only earn for time spent WATCHING beyond the high water mark.

**Rationale**:
- Seeking is not watching - user hasn't actually consumed the content
- If we credited seek time, users could seek to the end and claim full reward
- The system tracks `sessionEarnableTime` which only increments when video is actively playing AND position > high water mark

**Implementation**:
```javascript
// In tick() function - only increment when PLAYING and position increases
if (currentPosition > this.highWaterMark) {
  // Only count actual watch time, not seek jumps
  const effectiveStartPosition = Math.max(this.lastPosition, this.highWaterMark);
  if (currentPosition > effectiveStartPosition) {
    const newTimeWatched = currentPosition - effectiveStartPosition;
    // Clamp to actual elapsed time (prevents seek exploitation)
    this.sessionEarnableTime += Math.min(newTimeWatched, wholeSeconds);
  }
}
```

**Examples**:
| Scenario | High Water Mark | Action | BUX Earned |
|----------|-----------------|--------|------------|
| Seek to 5:00, watch 30s | 0:00 | Position goes 5:00 → 5:30 | 30 seconds worth |
| Seek to end, close immediately | 0:00 | Position = 10:00, but no time watched | 0 BUX |
| Watch 0:00 → 2:30, seek to 8:00, watch 1 min | 2:30 | New high water mark = 9:00, earned 1 min | 1 minute worth |

---

## Architecture

### High-Level Component Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           Post Show Page                                │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  Featured Image with Play Button Overlay                         │   │
│  │  (click triggers video modal)                                    │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  Video Watch Modal (Full-Screen)                                 │   │
│  │  ┌──────────────────────────────────────────────────────────┐   │   │
│  │  │  YouTube iFrame Player                                     │   │   │
│  │  │  (phx-hook="VideoWatchTracker")                            │   │   │
│  │  └──────────────────────────────────────────────────────────┘   │   │
│  │  ┌──────────────┐                                                │   │
│  │  │ BUX Earnings │  ← Updates every 5 seconds                     │   │
│  │  │ +12.5 BUX    │                                                │   │
│  │  └──────────────┘                                                │   │
│  └─────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘

        │                                │
        │ pushEvent("video-*")           │ handle_event("video-*")
        ▼                                ▼
┌─────────────────────┐          ┌─────────────────────────┐
│  JavaScript Hook    │◀────────▶│  LiveView (show.ex)     │
│  VideoWatchTracker  │          │  - Video state tracking │
│  - YouTube API      │          │  - Score calculation    │
│  - Tab visibility   │          │  - Pool management      │
│  - Time tracking    │          │  - BUX minting          │
└─────────────────────┘          └─────────────────────────┘
                                          │
                                          ▼
                                 ┌─────────────────────────┐
                                 │  EngagementTracker      │
                                 │  - Mnesia storage       │
                                 │  - Reward tracking      │
                                 └─────────────────────────┘
                                          │
                                          ▼
                                 ┌─────────────────────────┐
                                 │  BuxMinter Service      │
                                 │  - Token minting        │
                                 │  - Pool deduction       │
                                 └─────────────────────────┘
```

---

## Database Schema Changes

### Posts Table (Ecto Migration)

```elixir
# priv/repo/migrations/YYYYMMDDHHMMSS_add_video_fields_to_posts.exs
defmodule BlocksterV2.Repo.Migrations.AddVideoFieldsToPosts do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      add :video_url, :string               # YouTube URL (e.g., https://youtube.com/watch?v=abc123)
      add :video_id, :string                # Extracted YouTube ID (e.g., abc123)
      add :video_duration, :integer         # Duration in seconds (from YouTube API)
      add :video_bux_per_minute, :decimal   # BUX earned per minute of watching (default: 1.0)
      add :video_max_reward, :decimal       # Maximum BUX earnable from this video (optional cap)
    end

    create index(:posts, [:video_id])
  end
end
```

### Post Schema Update

```elixir
# lib/blockster_v2/blog/post.ex (additions)
schema "posts" do
  # ... existing fields ...

  # Video fields
  field :video_url, :string
  field :video_id, :string
  field :video_duration, :integer        # seconds
  field :video_bux_per_minute, :decimal, default: Decimal.new("1.0")
  field :video_max_reward, :decimal       # nil = no cap
end

def changeset(post, attrs) do
  post
  |> cast(attrs, [
    # ... existing fields ...
    :video_url,
    :video_id,
    :video_duration,
    :video_bux_per_minute,
    :video_max_reward
  ])
  |> extract_video_id()
end

defp extract_video_id(changeset) do
  case get_change(changeset, :video_url) do
    nil -> changeset
    url ->
      # Extract YouTube video ID from various URL formats
      video_id = extract_youtube_id(url)
      put_change(changeset, :video_id, video_id)
  end
end

defp extract_youtube_id(url) do
  cond do
    # Standard: youtube.com/watch?v=VIDEO_ID
    String.contains?(url, "youtube.com/watch?v=") ->
      URI.parse(url).query
      |> URI.decode_query()
      |> Map.get("v")

    # Short: youtu.be/VIDEO_ID
    String.contains?(url, "youtu.be/") ->
      URI.parse(url).path |> String.trim_leading("/")

    # Embed: youtube.com/embed/VIDEO_ID
    String.contains?(url, "youtube.com/embed/") ->
      URI.parse(url).path |> String.split("/") |> List.last()

    true -> nil
  end
end
```

### Mnesia Table: `user_video_engagement`

Add to `MnesiaInitializer`:

```elixir
# New table for video engagement tracking with HIGH WATER MARK system
:mnesia.create_table(:user_video_engagement, [
  attributes: [
    :key,                      # {user_id, post_id}
    :user_id,
    :post_id,
    :high_water_mark,          # CRITICAL: Highest position (seconds) user has watched to
    :total_earnable_time,      # Total seconds spent BEYOND high water mark (across all sessions)
    :video_duration,           # Video length in seconds (cached from post)
    :completion_percentage,    # 0-100% (high_water_mark / video_duration)
    :total_bux_earned,         # Total BUX earned from this video (across all sessions)
    :last_session_bux,         # BUX earned in most recent session
    :total_pause_count,        # Cumulative pause count (anti-gaming metric)
    :total_tab_away_count,     # Cumulative tab switches (anti-gaming metric)
    :session_count,            # Number of viewing sessions
    :last_watched_at,          # Unix timestamp of last session
    :created_at,
    :updated_at
  ],
  disc_copies: [node()],
  index: [:user_id, :post_id],
  type: :set
])

# Key insight: high_water_mark is the single source of truth for what's been watched.
# User only earns BUX when their currentPosition > high_water_mark.
# After each session, high_water_mark is updated to max(old_high_water_mark, session_max_position).
```

**Mnesia Record Indices:**
| Index | Field | Description |
|-------|-------|-------------|
| 0 | :user_video_engagement | Table name |
| 1 | key | `{user_id, post_id}` tuple |
| 2 | user_id | Integer |
| 3 | post_id | Integer |
| 4 | **high_water_mark** | Float - highest position watched (seconds) |
| 5 | total_earnable_time | Float - total seconds spent beyond high water mark |
| 6 | video_duration | Integer - video length in seconds |
| 7 | completion_percentage | Integer - 0-100 |
| 8 | total_bux_earned | Float - cumulative BUX earned |
| 9 | last_session_bux | Float - most recent session's BUX |
| 10 | total_pause_count | Integer |
| 11 | total_tab_away_count | Integer |
| 12 | session_count | Integer |
| 13 | last_watched_at | Unix timestamp |
| 14 | created_at | Unix timestamp |
| 15 | updated_at | Unix timestamp |
```

### Mnesia Table: `post_video_stats`

```elixir
# Aggregate stats per video post
:mnesia.create_table(:post_video_stats, [
  attributes: [
    :post_id,                # Primary key
    :total_views,            # Number of unique viewers
    :total_watch_time,       # Aggregate watch time across all users
    :completions,            # Users who watched 90%+
    :bux_distributed,        # Total BUX given out for this video
    :updated_at
  ],
  disc_copies: [node()],
  type: :set
])
```

---

## JavaScript Hook: `VideoWatchTracker`

```javascript
// assets/js/video_watch_tracker.js

/**
 * VideoWatchTracker Hook
 *
 * Tracks YouTube video watch time using HIGH WATER MARK system.
 * User only earns BUX when watching BEYOND their previous furthest point.
 *
 * Anti-gaming measures:
 * - Only earns when currentPosition > highWaterMark
 * - Pauses tracking when video is paused
 * - Pauses tracking when tab loses focus
 * - Pauses tracking when browser window loses focus
 * - Uses YouTube iFrame API for accurate playback state
 */
export const VideoWatchTracker = {
  mounted() {
    // Extract config from data attributes
    this.userId = this.el.dataset.userId;
    this.postId = this.el.dataset.postId;
    this.videoId = this.el.dataset.videoId;
    this.videoDuration = parseInt(this.el.dataset.videoDuration, 10) || 0;
    this.buxPerMinute = parseFloat(this.el.dataset.buxPerMinute) || 1.0;
    this.maxReward = this.el.dataset.maxReward ? parseFloat(this.el.dataset.maxReward) : null;
    this.poolAvailable = this.el.dataset.poolAvailable === "true";

    // HIGH WATER MARK: Previous furthest position watched (from server/Mnesia)
    // User only earns BUX when currentPosition > highWaterMark
    this.highWaterMark = parseFloat(this.el.dataset.highWaterMark) || 0;
    this.totalBuxEarnedPreviously = parseFloat(this.el.dataset.totalBuxEarned) || 0;

    // Check if video is fully watched (high water mark >= duration)
    this.videoFullyWatched = this.videoDuration > 0 && this.highWaterMark >= this.videoDuration;

    // Skip tracking conditions
    if (!this.userId || this.userId === "anonymous") {
      console.log("VideoWatchTracker: Anonymous user, watch for fun only");
      this.trackingEnabled = false;
    } else if (this.videoFullyWatched) {
      console.log("VideoWatchTracker: Video fully watched, no more BUX available");
      this.trackingEnabled = false;
    } else if (!this.poolAvailable) {
      console.log("VideoWatchTracker: Pool empty, no rewards available");
      this.trackingEnabled = false;
    } else {
      this.trackingEnabled = true;
    }

    // Session tracking state
    this.sessionEarnableTime = 0;     // Seconds spent BEYOND high water mark this session
    this.sessionMaxPosition = 0;       // Highest position reached this session
    this.lastPosition = 0;             // Last polled position
    this.lastTickTime = null;
    this.isPlaying = false;
    this.isTabVisible = true;
    this.pauseCount = 0;
    this.tabAwayCount = 0;

    // BUX display state
    this.sessionBux = 0;              // BUX earned THIS session (new territory only)
    this.lastReportedBux = 0;

    // Load YouTube iFrame API
    this.loadYouTubeAPI();

    // Set up visibility tracking
    this.setupVisibilityTracking();

    // Set up 5-second update interval for server sync
    this.updateInterval = setInterval(() => this.sendUpdate(), 5000);

    // Notify server that video modal opened
    this.pushEvent("video-modal-opened", {
      post_id: this.postId,
      high_water_mark: this.highWaterMark
    });

    console.log(`VideoWatchTracker: Started - highWaterMark=${this.highWaterMark}s, duration=${this.videoDuration}s`);
  },

  loadYouTubeAPI() {
    // Check if API is already loaded
    if (window.YT && window.YT.Player) {
      this.initPlayer();
      return;
    }

    // Load the API script
    const tag = document.createElement('script');
    tag.src = 'https://www.youtube.com/iframe_api';
    const firstScriptTag = document.getElementsByTagName('script')[0];
    firstScriptTag.parentNode.insertBefore(tag, firstScriptTag);

    // Set up callback for when API is ready
    window.onYouTubeIframeAPIReady = () => this.initPlayer();
  },

  initPlayer() {
    const playerContainer = this.el.querySelector('[data-video-player]');
    if (!playerContainer) {
      console.error("VideoWatchTracker: Player container not found");
      return;
    }

    this.player = new YT.Player(playerContainer, {
      videoId: this.videoId,
      width: '100%',
      height: '100%',
      playerVars: {
        autoplay: 1,
        modestbranding: 1,
        rel: 0,
        playsinline: 1
      },
      events: {
        onReady: (event) => this.onPlayerReady(event),
        onStateChange: (event) => this.onPlayerStateChange(event),
        onError: (event) => this.onPlayerError(event)
      }
    });
  },

  onPlayerReady(event) {
    console.log("VideoWatchTracker: Player ready");
    // Get actual video duration from YouTube
    const duration = this.player.getDuration();
    if (duration > 0) {
      this.videoDuration = duration;
    }
  },

  onPlayerStateChange(event) {
    switch (event.data) {
      case YT.PlayerState.PLAYING:
        this.onVideoPlay();
        break;
      case YT.PlayerState.PAUSED:
        this.onVideoPause();
        break;
      case YT.PlayerState.ENDED:
        this.onVideoEnded();
        break;
      case YT.PlayerState.BUFFERING:
        // Don't count buffering time
        this.stopTracking();
        break;
    }
  },

  onVideoPlay() {
    console.log("VideoWatchTracker: Video playing");
    this.isPlaying = true;
    if (this.isTabVisible && this.trackingEnabled) {
      this.startTracking();
    }
    this.pushEvent("video-playing", { post_id: this.postId });
  },

  onVideoPause() {
    console.log("VideoWatchTracker: Video paused");
    this.isPlaying = false;
    this.pauseCount++;
    this.stopTracking();
    this.pushEvent("video-paused", {
      post_id: this.postId,
      watch_time: this.watchTime,
      pause_count: this.pauseCount
    });
  },

  onVideoEnded() {
    console.log("VideoWatchTracker: Video ended");
    this.isPlaying = false;
    this.stopTracking();
    this.finalizeWatching();
  },

  onPlayerError(event) {
    console.error("VideoWatchTracker: Player error", event.data);
    this.stopTracking();
  },

  setupVisibilityTracking() {
    // Tab visibility
    document.addEventListener("visibilitychange", () => {
      if (document.visibilityState === "hidden") {
        this.isTabVisible = false;
        this.tabAwayCount++;
        this.stopTracking();
        console.log("VideoWatchTracker: Tab hidden, pausing tracking");
      } else {
        this.isTabVisible = true;
        if (this.isPlaying && this.trackingEnabled) {
          this.startTracking();
        }
        console.log("VideoWatchTracker: Tab visible, resuming");
      }
    });

    // Window focus (catches cases visibilitychange might miss)
    window.addEventListener("blur", () => {
      if (this.isPlaying) {
        this.stopTracking();
        console.log("VideoWatchTracker: Window blur, pausing");
      }
    });

    window.addEventListener("focus", () => {
      if (this.isPlaying && this.isTabVisible && this.trackingEnabled) {
        this.startTracking();
        console.log("VideoWatchTracker: Window focus, resuming");
      }
    });
  },

  startTracking() {
    if (this.rafId) return; // Already tracking

    this.lastTickTime = performance.now();
    this.tick();
  },

  stopTracking() {
    if (this.rafId) {
      cancelAnimationFrame(this.rafId);
      this.rafId = null;
    }
  },

  tick() {
    if (!this.isPlaying || !this.isTabVisible || !this.trackingEnabled) {
      this.rafId = null;
      return;
    }

    const now = performance.now();
    const delta = (now - this.lastTickTime) / 1000; // Convert to seconds

    if (delta >= 1) {
      const wholeSeconds = Math.floor(delta);
      this.lastTickTime = now - ((delta - wholeSeconds) * 1000);

      // Get current video position from YouTube API
      const currentPosition = this.player ? this.player.getCurrentTime() : 0;

      // HIGH WATER MARK LOGIC:
      // Only count time if we're BEYOND the previous high water mark
      if (currentPosition > this.highWaterMark) {
        // Calculate how much NEW time was watched
        // If we jumped ahead (seeked), only count from where we landed
        const effectiveStartPosition = Math.max(this.lastPosition, this.highWaterMark);

        if (currentPosition > effectiveStartPosition) {
          const newTimeWatched = currentPosition - effectiveStartPosition;
          this.sessionEarnableTime += Math.min(newTimeWatched, wholeSeconds);
        }
      }

      // Track session's maximum position (for updating high water mark on close)
      if (currentPosition > this.sessionMaxPosition) {
        this.sessionMaxPosition = currentPosition;
      }

      this.lastPosition = currentPosition;

      // Update BUX display
      this.updateBuxDisplay();
    }

    this.rafId = requestAnimationFrame(() => this.tick());
  },

  updateBuxDisplay() {
    // Calculate BUX for THIS SESSION only (new territory beyond high water mark)
    const earnableMinutes = this.sessionEarnableTime / 60;
    let sessionBux = earnableMinutes * this.buxPerMinute;

    // Calculate max possible remaining BUX (from current high water mark to end)
    const remainingSeconds = Math.max(0, this.videoDuration - this.highWaterMark);
    const maxRemainingBux = (remainingSeconds / 60) * this.buxPerMinute;

    // Apply max reward cap if set (considering previously earned)
    if (this.maxReward !== null) {
      const maxSessionBux = this.maxReward - this.totalBuxEarnedPreviously;
      sessionBux = Math.min(sessionBux, maxSessionBux);
    }

    // Can't earn more than remaining video allows
    sessionBux = Math.min(sessionBux, maxRemainingBux);

    this.sessionBux = Math.round(sessionBux * 10) / 10; // Round to 1 decimal

    // Update the display element
    const buxDisplay = document.getElementById("video-bux-earned");
    if (buxDisplay) {
      buxDisplay.textContent = `+${this.sessionBux}`;
    }

    // Update the total display (previously earned + this session)
    const totalDisplay = document.getElementById("video-bux-total");
    if (totalDisplay) {
      const total = this.totalBuxEarnedPreviously + this.sessionBux;
      totalDisplay.textContent = total.toFixed(1);
    }

    // Update progress bar - shows overall video completion
    const progressBar = document.getElementById("video-watch-progress");
    if (progressBar && this.videoDuration > 0) {
      const newHighWaterMark = Math.max(this.highWaterMark, this.sessionMaxPosition);
      const progress = Math.min(100, (newHighWaterMark / this.videoDuration) * 100);
      progressBar.style.width = `${progress}%`;
    }

    // Update "watching new content" indicator
    const newContentIndicator = document.getElementById("video-new-content");
    if (newContentIndicator) {
      const isWatchingNew = this.lastPosition > this.highWaterMark;
      newContentIndicator.style.display = isWatchingNew ? "block" : "none";
    }
  },

  sendUpdate() {
    if (!this.trackingEnabled) return;

    // Only send if BUX amount changed
    if (this.currentBux === this.lastReportedBux) return;

    const metrics = {
      post_id: this.postId,
      watch_time: this.watchTime,
      video_duration: this.videoDuration,
      completion_percentage: Math.round((this.watchTime / this.videoDuration) * 100),
      bux_earned: this.currentBux,
      pause_count: this.pauseCount,
      tab_away_count: this.tabAwayCount
    };

    console.log("VideoWatchTracker: Sending update", metrics);
    this.pushEvent("video-watch-update", metrics);
    this.lastReportedBux = this.currentBux;
  },

  finalizeWatching() {
    // Calculate new high water mark (highest of: previous, session max)
    const newHighWaterMark = Math.max(this.highWaterMark, this.sessionMaxPosition);

    if (!this.trackingEnabled || this.sessionBux <= 0) {
      this.pushEvent("video-watch-complete", {
        post_id: this.postId,
        session_earnable_time: this.sessionEarnableTime,
        session_bux_earned: 0,
        new_high_water_mark: newHighWaterMark,
        reason: this.trackingEnabled ? "no_new_content_watched" : "tracking_disabled"
      });
      return;
    }

    const metrics = {
      post_id: this.postId,
      // Session-specific metrics
      session_earnable_time: this.sessionEarnableTime,  // Time spent beyond high water mark
      session_bux_earned: this.sessionBux,              // BUX earned THIS session
      session_max_position: this.sessionMaxPosition,    // Highest position this session
      // High water mark update
      previous_high_water_mark: this.highWaterMark,
      new_high_water_mark: newHighWaterMark,
      // Video info
      video_duration: this.videoDuration,
      completion_percentage: Math.round((newHighWaterMark / this.videoDuration) * 100),
      // Anti-gaming metrics
      pause_count: this.pauseCount,
      tab_away_count: this.tabAwayCount
    };

    console.log("VideoWatchTracker: Finalizing session", metrics);
    this.pushEvent("video-watch-complete", metrics);
  },

  // Called when user closes modal without video ending
  closeModal() {
    this.stopTracking();
    if (this.player) {
      this.player.pauseVideo();
    }
    this.finalizeWatching();
  },

  destroyed() {
    this.stopTracking();

    if (this.updateInterval) {
      clearInterval(this.updateInterval);
    }

    if (this.player) {
      this.player.destroy();
    }

    // Clean up event listeners
    document.removeEventListener("visibilitychange", this.handleVisibility);

    console.log("VideoWatchTracker: Destroyed");
  }
};
```

---

## LiveView Implementation

### Post Show LiveView Updates (`show.ex`)

```elixir
# lib/blockster_v2_web/live/post_live/show.ex

defmodule BlocksterV2Web.PostLive.Show do
  # ... existing code ...

  @impl true
  def mount(params, session, socket) do
    # ... existing mount code ...

    # Add video-specific assigns
    socket =
      socket
      |> assign(:video_modal_open, false)
      |> assign(:video_high_water_mark, 0.0)        # Highest position watched (seconds)
      |> assign(:video_total_bux_earned, 0.0)       # Total BUX earned across all sessions
      |> assign(:video_completion_percentage, 0)    # % of video watched
      |> assign(:video_fully_watched, false)        # True when high water mark >= duration
      |> load_video_engagement()

    {:ok, socket}
  end

  # Load existing video engagement for this user/post
  defp load_video_engagement(socket) do
    if socket.assigns.current_user && socket.assigns.post.video_id do
      user_id = socket.assigns.current_user.id
      post_id = socket.assigns.post.id
      video_duration = socket.assigns.post.video_duration || 0

      case EngagementTracker.get_video_engagement(user_id, post_id) do
        {:ok, engagement} ->
          fully_watched = video_duration > 0 && engagement.high_water_mark >= video_duration

          socket
          |> assign(:video_high_water_mark, engagement.high_water_mark)
          |> assign(:video_total_bux_earned, engagement.total_bux_earned)
          |> assign(:video_completion_percentage, engagement.completion_percentage)
          |> assign(:video_fully_watched, fully_watched)

        {:error, :not_found} ->
          # No previous engagement - user starts fresh
          socket
      end
    else
      socket
    end
  end

  # Open video modal
  @impl true
  def handle_event("open_video_modal", _params, socket) do
    {:noreply, assign(socket, :video_modal_open, true)}
  end

  # Close video modal
  def handle_event("close_video_modal", _params, socket) do
    {:noreply, assign(socket, :video_modal_open, false)}
  end

  # Video modal opened (from JS hook)
  def handle_event("video-modal-opened", %{"post_id" => _post_id}, socket) do
    # Record video view start
    if socket.assigns.current_user do
      user_id = socket.assigns.current_user.id
      post_id = socket.assigns.post.id
      EngagementTracker.record_video_view(user_id, post_id)
    end

    {:noreply, socket}
  end

  # Video playing state change
  def handle_event("video-playing", _params, socket) do
    {:noreply, socket}
  end

  # Video paused
  def handle_event("video-paused", %{"watch_time" => watch_time, "pause_count" => pause_count}, socket) do
    if socket.assigns.current_user do
      user_id = socket.assigns.current_user.id
      post_id = socket.assigns.post.id

      EngagementTracker.update_video_engagement(user_id, post_id, %{
        session_watch_time: watch_time,
        pause_count: pause_count
      })
    end

    {:noreply, assign(socket, :video_watch_time, watch_time)}
  end

  # Periodic watch update (every 5 seconds)
  def handle_event("video-watch-update", params, socket) do
    %{
      "watch_time" => watch_time,
      "completion_percentage" => completion,
      "bux_earned" => bux_earned,
      "pause_count" => pause_count,
      "tab_away_count" => tab_away_count
    } = params

    if socket.assigns.current_user do
      user_id = socket.assigns.current_user.id
      post_id = socket.assigns.post.id

      EngagementTracker.update_video_engagement(user_id, post_id, %{
        session_watch_time: watch_time,
        completion_percentage: completion,
        bux_earned: bux_earned,
        pause_count: pause_count,
        tab_away_count: tab_away_count
      })
    end

    {:noreply,
     socket
     |> assign(:video_watch_time, watch_time)
     |> assign(:video_bux_earned, bux_earned)}
  end

  # Video watching complete - mint BUX for NEW territory watched
  def handle_event("video-watch-complete", params, socket) do
    %{
      "session_earnable_time" => session_earnable_time,
      "session_bux_earned" => client_session_bux,
      "previous_high_water_mark" => previous_hwm,
      "new_high_water_mark" => new_hwm,
      "video_duration" => video_duration,
      "completion_percentage" => completion,
      "pause_count" => pause_count,
      "tab_away_count" => tab_away_count
    } = params

    user = socket.assigns.current_user
    post = socket.assigns.post

    cond do
      # Not logged in
      is_nil(user) ->
        {:noreply, socket |> put_flash(:error, "Please log in to earn BUX")}

      # No new territory watched (session_earnable_time <= 0)
      session_earnable_time <= 0 ->
        # Still update last_watched_at even if no new BUX earned
        if new_hwm > previous_hwm do
          EngagementTracker.update_video_high_water_mark(user.id, post.id, new_hwm)
        end
        {:noreply, socket |> assign(:video_modal_open, false)}

      # Video fully watched already
      socket.assigns.video_fully_watched ->
        {:noreply,
         socket
         |> assign(:video_modal_open, false)
         |> put_flash(:info, "You've watched the full video and earned all available BUX")}

      # Validate and mint for NEW territory
      true ->
        socket = mint_video_session_reward(socket, user, post, %{
          session_earnable_time: session_earnable_time,
          client_session_bux: client_session_bux,
          previous_high_water_mark: previous_hwm,
          new_high_water_mark: new_hwm,
          video_duration: video_duration,
          completion_percentage: completion,
          pause_count: pause_count,
          tab_away_count: tab_away_count
        })

        {:noreply, socket |> assign(:video_modal_open, false)}
    end
  end

  # Server-side BUX calculation and minting for a VIDEO SESSION
  # Only mints BUX for NEW territory watched (beyond previous high water mark)
  defp mint_video_session_reward(socket, user, post, metrics) do
    bux_per_minute = Decimal.to_float(post.video_bux_per_minute || Decimal.new("1.0"))
    max_total_reward = post.video_max_reward && Decimal.to_float(post.video_max_reward)
    previous_total_earned = socket.assigns.video_total_bux_earned

    # Server-side validation: Calculate BUX for NEW territory only
    # session_earnable_time = seconds spent BEYOND previous high water mark
    server_calculated_bux = calculate_session_video_bux(
      metrics.session_earnable_time,
      bux_per_minute,
      max_total_reward,
      previous_total_earned
    )

    # Apply anti-gaming penalties
    final_session_bux = apply_video_penalties(server_calculated_bux, metrics)

    # Check pool availability
    pool_balance = EngagementTracker.get_post_bux_pool(post.id)

    cond do
      final_session_bux <= 0 ->
        # Update high water mark even if no BUX earned (they watched new territory)
        EngagementTracker.update_video_engagement_session(user.id, post.id, %{
          new_high_water_mark: metrics.new_high_water_mark,
          session_bux: 0,
          pause_count: metrics.pause_count,
          tab_away_count: metrics.tab_away_count
        })
        socket |> put_flash(:info, "Keep watching new content to earn BUX!")

      pool_balance <= 0 ->
        socket |> put_flash(:info, "This post's BUX pool is empty")

      true ->
        # Mint the BUX for this session (async)
        wallet_address = user.smart_wallet_address
        new_total_earned = previous_total_earned + final_session_bux
        new_completion = metrics.completion_percentage

        Task.start(fn ->
          case BuxMinter.mint_bux(wallet_address, final_session_bux, user.id, post.id, :video_watch) do
            {:ok, response} ->
              tx_hash = response["transactionHash"]

              # Update video engagement with new high water mark and BUX earned
              EngagementTracker.update_video_engagement_session(user.id, post.id, %{
                new_high_water_mark: metrics.new_high_water_mark,
                session_bux: final_session_bux,
                session_earnable_time: metrics.session_earnable_time,
                pause_count: metrics.pause_count,
                tab_away_count: metrics.tab_away_count,
                tx_hash: tx_hash
              })

              # Deduct from pool
              EngagementTracker.try_deduct_from_pool(post.id, final_session_bux)

              # Send PubSub update for real-time UI refresh
              Phoenix.PubSub.broadcast(
                BlocksterV2.PubSub,
                "video_reward:#{user.id}",
                {:video_session_complete, tx_hash, final_session_bux, new_total_earned, new_completion}
              )

            {:error, reason} ->
              Logger.error("Failed to mint video reward: #{inspect(reason)}")
          end
        end)

        video_duration = post.video_duration || 0
        fully_watched = video_duration > 0 && metrics.new_high_water_mark >= video_duration

        socket
        |> assign(:video_high_water_mark, metrics.new_high_water_mark)
        |> assign(:video_total_bux_earned, new_total_earned)
        |> assign(:video_completion_percentage, new_completion)
        |> assign(:video_fully_watched, fully_watched)
        |> put_flash(:success, "You earned +#{final_session_bux} BUX for watching new content!")
    end
  end

  # Calculate BUX for SESSION (new territory only)
  defp calculate_session_video_bux(session_earnable_time, bux_per_minute, max_total_reward, previous_total_earned) do
    session_minutes = session_earnable_time / 60
    session_bux = session_minutes * bux_per_minute

    # Apply max total reward cap if set
    if max_total_reward do
      remaining_earnable = max_total_reward - previous_total_earned
      min(session_bux, remaining_earnable) |> max(0) |> Float.round(1)
    else
      Float.round(session_bux, 1)
    end
  end

  # Apply penalties for suspicious behavior in this session
  defp apply_video_penalties(bux, metrics) do
    penalty_multiplier = 1.0

    # Penalty for excessive pausing (potential gaming)
    penalty_multiplier = if metrics.pause_count > 10 do
      penalty_multiplier * 0.8  # 20% reduction
    else
      penalty_multiplier
    end

    # Penalty for excessive tab switching (potential gaming)
    penalty_multiplier = if metrics.tab_away_count > 5 do
      penalty_multiplier * 0.9  # 10% reduction
    else
      penalty_multiplier
    end

    Float.round(bux * penalty_multiplier, 1)
  end
end
```

---

## Template Updates

### Featured Image with Play Button Overlay

```heex
<!-- In show.html.heex, update the Featured Image section -->

<%= if @post.featured_image do %>
  <div class="mb-10 rounded-2xl overflow-hidden aspect-square relative group">
    <img
      src={ImageKit.w800(@post.featured_image)}
      alt={@post.title}
      class="w-full h-full object-cover"
    />

    <%= if @post.video_id do %>
      <!-- Play Button Overlay -->
      <button
        phx-click="open_video_modal"
        class="absolute inset-0 flex items-center justify-center bg-black/30 opacity-0 group-hover:opacity-100 transition-opacity cursor-pointer"
      >
        <div class="w-20 h-20 bg-white/90 rounded-full flex items-center justify-center shadow-2xl transform hover:scale-110 transition-transform">
          <svg class="w-10 h-10 text-[#141414] ml-1" fill="currentColor" viewBox="0 0 24 24">
            <path d="M8 5v14l11-7z"/>
          </svg>
        </div>
      </button>

      <!-- Always-visible play indicator -->
      <div class="absolute bottom-4 right-4 bg-black/70 text-white px-3 py-1.5 rounded-full text-sm font-haas_medium_65 flex items-center gap-2">
        <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 24 24">
          <path d="M8 5v14l11-7z"/>
        </svg>
        Watch & Earn BUX
      </div>
    <% end %>
  </div>
<% end %>
```

### Video Modal

```heex
<!-- Video Watch Modal - add after the featured image section -->

<%= if @video_modal_open && @post.video_id do %>
  <div
    id="video-modal"
    class="fixed inset-0 z-[100] flex items-center justify-center bg-black/95"
    phx-window-keydown="close_video_modal"
    phx-key="Escape"
  >
    <!-- Close Button -->
    <button
      phx-click="close_video_modal"
      class="absolute top-4 right-4 z-10 w-12 h-12 flex items-center justify-center rounded-full bg-white/10 hover:bg-white/20 transition-colors cursor-pointer"
    >
      <svg class="w-6 h-6 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
      </svg>
    </button>

    <!-- Video Container -->
    <div
      id="video-watch-container"
      class="w-full max-w-5xl mx-4 aspect-video"
      phx-hook="VideoWatchTracker"
      data-user-id={if @current_user, do: @current_user.id, else: "anonymous"}
      data-post-id={@post.id}
      data-video-id={@post.video_id}
      data-video-duration={@post.video_duration || 0}
      data-bux-per-minute={Decimal.to_float(@post.video_bux_per_minute || Decimal.new("1.0"))}
      data-max-reward={if @post.video_max_reward, do: Decimal.to_float(@post.video_max_reward), else: ""}
      data-high-water-mark={@video_high_water_mark || 0}
      data-total-bux-earned={@video_total_bux_earned || 0}
      data-pool-available={to_string(@pool_available)}
    >
      <!-- YouTube player will be injected here -->
      <div data-video-player class="w-full h-full bg-black"></div>
    </div>

    <!-- BUX Earnings Panel - HIGH WATER MARK AWARE -->
    <%= if @current_user && @pool_available && !@video_fully_watched do %>
      <div class="absolute bottom-8 right-8 bg-gradient-to-r from-[#8AE388] to-[#6BCB69] text-white rounded-2xl shadow-2xl p-4 min-w-[220px]">
        <div class="flex items-center gap-3">
          <img src="https://ik.imagekit.io/blockster/blockster-icon.png" alt="BUX" class="w-10 h-10 rounded-full object-cover" />
          <div>
            <div class="text-xs opacity-90">This Session</div>
            <div class="text-2xl font-bold">
              +<span id="video-bux-earned">0.0</span> BUX
            </div>
          </div>
        </div>

        <!-- New Content Indicator (hidden by default, JS shows when watching new) -->
        <div id="video-new-content" class="hidden mt-2 text-xs bg-white/20 rounded-full px-2 py-1 text-center">
          ✨ Watching new content - earning BUX!
        </div>

        <!-- Rewatching Indicator (hidden by default, JS shows when rewatching) -->
        <div id="video-rewatching" class="hidden mt-2 text-xs bg-white/10 rounded-full px-2 py-1 text-center opacity-75">
          ↩ Rewatching - skip ahead to earn more
        </div>

        <!-- Watch Progress Bar (overall video completion) -->
        <div class="mt-3">
          <div class="flex justify-between text-xs opacity-75 mb-1">
            <span>Video Progress</span>
            <span><span id="video-completion-pct">{@video_completion_percentage}</span>%</span>
          </div>
          <div class="h-1.5 bg-white/30 rounded-full overflow-hidden">
            <div
              id="video-watch-progress"
              class="h-full bg-white rounded-full transition-all duration-500"
              style={"width: #{@video_completion_percentage}%"}
            ></div>
          </div>
        </div>

        <!-- Previously Earned (if any) -->
        <%= if @video_total_bux_earned > 0 do %>
          <div class="mt-2 pt-2 border-t border-white/20 text-xs">
            <div class="flex justify-between opacity-75">
              <span>Previously earned:</span>
              <span class="font-bold">{Float.round(@video_total_bux_earned, 1)} BUX</span>
            </div>
            <div class="flex justify-between opacity-75 mt-1">
              <span>Total:</span>
              <span class="font-bold"><span id="video-bux-total">{Float.round(@video_total_bux_earned, 1)}</span> BUX</span>
            </div>
          </div>
        <% end %>
      </div>
    <% end %>

    <!-- Video Fully Watched State -->
    <%= if @video_fully_watched do %>
      <div class="absolute bottom-8 right-8 bg-gradient-to-r from-amber-400 to-amber-500 text-white rounded-2xl shadow-2xl p-4 min-w-[200px]">
        <div class="flex items-center gap-3">
          <img src="https://ik.imagekit.io/blockster/blockster-icon.png" alt="BUX" class="w-10 h-10 rounded-full object-cover" />
          <div>
            <div class="text-xs opacity-90">Video Complete!</div>
            <div class="text-2xl font-bold">{Float.round(@video_total_bux_earned, 1)} BUX</div>
          </div>
        </div>
        <div class="mt-2 pt-2 border-t border-white/20 text-xs opacity-90">
          <div class="flex items-center gap-1">
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
            </svg>
            You've watched the full video
          </div>
        </div>
      </div>
    <% end %>
  </div>
<% end %>
```

---

## EngagementTracker Updates

```elixir
# lib/blockster_v2/engagement_tracker.ex (additions)

# ============================================
# VIDEO ENGAGEMENT FUNCTIONS (HIGH WATER MARK SYSTEM)
# ============================================

@doc """
Records that a user started watching a video.
Creates initial engagement record if not exists.
"""
def record_video_view(user_id, post_id, video_duration \\ 0) do
  now = System.system_time(:second)
  key = {user_id, post_id}

  case :mnesia.dirty_read({:user_video_engagement, key}) do
    [] ->
      # Create new engagement record with high water mark at 0
      record = {
        :user_video_engagement,
        key,                    # 1: key
        user_id,                # 2: user_id
        post_id,                # 3: post_id
        0.0,                    # 4: high_water_mark (seconds)
        0.0,                    # 5: total_earnable_time
        video_duration,         # 6: video_duration
        0,                      # 7: completion_percentage
        0.0,                    # 8: total_bux_earned
        0.0,                    # 9: last_session_bux
        0,                      # 10: total_pause_count
        0,                      # 11: total_tab_away_count
        1,                      # 12: session_count
        now,                    # 13: last_watched_at
        now,                    # 14: created_at
        now                     # 15: updated_at
      }
      :mnesia.dirty_write(record)

      # Update post stats
      increment_video_views(post_id)

      {:ok, :created}

    [existing] ->
      # Increment session count and update last_watched_at
      updated = existing
      |> put_elem(12, elem(existing, 12) + 1)  # session_count
      |> put_elem(13, now)                      # last_watched_at
      |> put_elem(15, now)                      # updated_at

      :mnesia.dirty_write(updated)
      {:ok, :updated}
  end
end

@doc """
Gets video engagement for a user/post.
Returns the high water mark and total BUX earned.
"""
def get_video_engagement(user_id, post_id) do
  key = {user_id, post_id}

  case :mnesia.dirty_read({:user_video_engagement, key}) do
    [] ->
      {:error, :not_found}

    [record] ->
      {:ok, %{
        high_water_mark: elem(record, 4),
        total_earnable_time: elem(record, 5),
        video_duration: elem(record, 6),
        completion_percentage: elem(record, 7),
        total_bux_earned: elem(record, 8),
        last_session_bux: elem(record, 9),
        total_pause_count: elem(record, 10),
        total_tab_away_count: elem(record, 11),
        session_count: elem(record, 12),
        last_watched_at: elem(record, 13)
      }}
  end
end

@doc """
Updates video engagement after a session completes.
Updates high water mark and accumulates BUX earned.
"""
def update_video_engagement_session(user_id, post_id, session_data) do
  key = {user_id, post_id}
  now = System.system_time(:second)

  %{
    new_high_water_mark: new_hwm,
    session_bux: session_bux,
    pause_count: pause_count,
    tab_away_count: tab_away_count
  } = session_data

  session_earnable_time = Map.get(session_data, :session_earnable_time, 0)
  tx_hash = Map.get(session_data, :tx_hash)

  case :mnesia.dirty_read({:user_video_engagement, key}) do
    [] ->
      {:error, :not_found}

    [record] ->
      old_hwm = elem(record, 4)
      video_duration = elem(record, 6)

      # Only update high water mark if new position is higher
      updated_hwm = max(old_hwm, new_hwm)

      # Calculate new completion percentage
      completion = if video_duration > 0 do
        trunc((updated_hwm / video_duration) * 100) |> min(100)
      else
        0
      end

      # Accumulate totals
      new_total_earnable_time = elem(record, 5) + session_earnable_time
      new_total_bux = elem(record, 8) + session_bux
      new_total_pauses = elem(record, 10) + pause_count
      new_total_tab_away = elem(record, 11) + tab_away_count

      updated_record = record
      |> put_elem(4, updated_hwm)              # high_water_mark
      |> put_elem(5, new_total_earnable_time)  # total_earnable_time
      |> put_elem(7, completion)               # completion_percentage
      |> put_elem(8, new_total_bux)            # total_bux_earned
      |> put_elem(9, session_bux)              # last_session_bux
      |> put_elem(10, new_total_pauses)        # total_pause_count
      |> put_elem(11, new_total_tab_away)      # total_tab_away_count
      |> put_elem(13, now)                     # last_watched_at
      |> put_elem(15, now)                     # updated_at

      :mnesia.dirty_write(updated_record)

      # Update post stats if BUX was earned
      if session_bux > 0 do
        update_video_stats(post_id, %{
          bux_distributed_delta: session_bux,
          watch_time_delta: session_earnable_time,
          completion: completion >= 90
        })
      end

      {:ok, %{
        high_water_mark: updated_hwm,
        total_bux_earned: new_total_bux,
        completion_percentage: completion,
        tx_hash: tx_hash
      }}
  end
end

@doc """
Simple high water mark update (no BUX earned, just position tracking).
"""
def update_video_high_water_mark(user_id, post_id, new_position) do
  key = {user_id, post_id}
  now = System.system_time(:second)

  case :mnesia.dirty_read({:user_video_engagement, key}) do
    [] ->
      {:error, :not_found}

    [record] ->
      old_hwm = elem(record, 4)

      if new_position > old_hwm do
        video_duration = elem(record, 6)
        completion = if video_duration > 0 do
          trunc((new_position / video_duration) * 100) |> min(100)
        else
          0
        end

        updated = record
        |> put_elem(4, new_position)   # high_water_mark
        |> put_elem(7, completion)     # completion_percentage
        |> put_elem(13, now)           # last_watched_at
        |> put_elem(15, now)           # updated_at

        :mnesia.dirty_write(updated)
        {:ok, new_position}
      else
        {:ok, old_hwm}  # No change needed
      end
  end
end

@doc """
Increments video view count for a post.
"""
defp increment_video_views(post_id) do
  case :mnesia.dirty_read({:post_video_stats, post_id}) do
    [] ->
      record = {:post_video_stats, post_id, 1, 0, 0, 0.0, System.system_time(:second)}
      :mnesia.dirty_write(record)

    [record] ->
      updated = put_elem(record, 2, elem(record, 2) + 1)
      |> put_elem(6, System.system_time(:second))
      :mnesia.dirty_write(updated)
  end
end

@doc """
Updates aggregate video stats for a post.
"""
defp update_video_stats(post_id, updates) do
  case :mnesia.dirty_read({:post_video_stats, post_id}) do
    [] ->
      # Create if not exists
      record = {
        :post_video_stats,
        post_id,
        0,                                              # total_views
        Map.get(updates, :watch_time_delta, 0),        # total_watch_time
        if(Map.get(updates, :completion), do: 1, else: 0), # completions
        Map.get(updates, :bux_distributed_delta, 0.0), # bux_distributed
        System.system_time(:second)
      }
      :mnesia.dirty_write(record)

    [record] ->
      updated = record
      |> put_elem(3, elem(record, 3) + Map.get(updates, :watch_time_delta, 0))
      |> put_elem(4, elem(record, 4) + if(Map.get(updates, :completion), do: 1, else: 0))
      |> put_elem(5, elem(record, 5) + Map.get(updates, :bux_distributed_delta, 0.0))
      |> put_elem(6, System.system_time(:second))

      :mnesia.dirty_write(updated)
  end
end
```

---

## BuxMinter Updates

```elixir
# lib/blockster_v2/bux_minter.ex

# Add :video_watch to valid reward types
def mint_bux(wallet_address, amount, user_id, post_id, reward_type, _token \\ "BUX", _hub_id \\ nil)
    when reward_type in [:read, :x_share, :video_watch] do
  # ... existing implementation ...

  # Update the reward marking section:
  case reward_type do
    :read ->
      EngagementTracker.mark_read_reward_paid(user_id, post_id, tx_hash)
    :video_watch ->
      # Video rewards are marked separately with additional data
      :ok
    :x_share ->
      :ok
  end

  # ... rest of implementation ...
end
```

---

## Anti-Gaming Measures

### 1. Tab Visibility Detection

The JavaScript hook uses the Page Visibility API to detect when the user switches tabs:

```javascript
document.addEventListener("visibilitychange", () => {
  if (document.visibilityState === "hidden") {
    // Stop earning BUX
    this.stopTracking();
    this.tabAwayCount++;
  }
});
```

### 2. Window Focus Detection

Catches edge cases where visibility API might not fire:

```javascript
window.addEventListener("blur", () => this.stopTracking());
window.addEventListener("focus", () => this.startTracking());
```

### 3. Video State Tracking

Uses YouTube iFrame API to track actual playback state:

```javascript
onPlayerStateChange(event) {
  switch (event.data) {
    case YT.PlayerState.PLAYING:
      // Start earning
      break;
    case YT.PlayerState.PAUSED:
    case YT.PlayerState.BUFFERING:
      // Stop earning
      break;
  }
}
```

### 4. Server-Side Validation

All BUX calculations are verified server-side:

```elixir
# Server recalculates BUX based on actual watch time
server_calculated_bux = calculate_video_bux(
  metrics.watch_time,
  post.video_duration,
  post.video_bux_per_minute,
  post.video_max_reward
)

# Apply penalties for suspicious behavior
final_bux = apply_video_penalties(server_calculated_bux, metrics)
```

### 5. Penalty System

Excessive pausing or tab switching results in reduced rewards:

| Behavior | Threshold | Penalty |
|----------|-----------|---------|
| Excessive pausing | > 10 pauses | -20% BUX |
| Excessive tab switching | > 5 switches | -10% BUX |
| Combined | Both | -28% BUX (multiplicative) |

### 6. Rate Limiting (Future Enhancement)

Consider implementing:
- Maximum BUX per day from videos
- Cooldown between video rewards
- IP-based rate limiting

---

## Admin Configuration

### Post Editor Updates

Add video fields to the post editor form:

```heex
<!-- In post form template -->
<div class="space-y-4 border-t pt-4 mt-4">
  <h3 class="font-haas_medium_65 text-lg">Video Settings</h3>

  <.input
    field={@form[:video_url]}
    type="text"
    label="YouTube Video URL"
    placeholder="https://youtube.com/watch?v=..."
  />

  <.input
    field={@form[:video_bux_per_minute]}
    type="number"
    step="0.1"
    label="BUX per Minute"
    placeholder="1.0"
  />

  <.input
    field={@form[:video_max_reward]}
    type="number"
    step="0.1"
    label="Max BUX Reward (optional)"
    placeholder="Leave empty for no cap"
  />
</div>
```

---

## Implementation Checklist

### Phase 1: Database & Schema (Day 1) ✅ COMPLETE

- [x] Create migration for video fields on posts table
  - [x] `video_url` (string)
  - [x] `video_id` (string, extracted from URL)
  - [x] `video_duration` (integer, seconds)
  - [x] `video_bux_per_minute` (decimal, default 1.0)
  - [x] `video_max_reward` (decimal, optional cap)
- [x] Update Post schema with video fields
- [x] Add YouTube ID extraction helper (supports youtube.com, youtu.be, embed URLs)
- [x] Add `user_video_engagement` Mnesia table definition (with high_water_mark)
- [x] Add `post_video_stats` Mnesia table definition
- [x] Restart nodes to create new Mnesia tables

**Files Created/Modified:**
- `priv/repo/migrations/20260121195735_add_video_fields_to_posts.exs` - Migration for video fields
- `lib/blockster_v2/blog/post.ex` - Added video fields, `extract_video_id/1`, `extract_youtube_id/1`
- `lib/blockster_v2/mnesia_initializer.ex` - Added `user_video_engagement` and `post_video_stats` tables

### Phase 2: JavaScript Hook - High Water Mark System (Day 2) ✅ COMPLETE

- [x] Create `assets/js/video_watch_tracker.js`
- [x] Implement YouTube iFrame API loading and initialization
- [x] Implement `getCurrentTime()` polling (every second while playing)
- [x] Implement HIGH WATER MARK tracking logic:
  - [x] Store `highWaterMark` from server (data attribute)
  - [x] Track `sessionMaxPosition` (highest position this session)
  - [x] Track `sessionEarnableTime` (time spent beyond high water mark)
  - [x] Only increment `sessionEarnableTime` when `currentPosition > highWaterMark`
- [x] Implement tab visibility detection (pause tracking when hidden)
- [x] Implement window focus detection (pause tracking on blur)
- [x] Implement mute detection (no earnings while video muted)
- [x] Add mute warning UI indicator ("🔇 Video muted - unmute to earn BUX")
- [x] Implement real-time UI updates:
  - [x] Session BUX earned counter
  - [x] "Watching new content" / "Rewatching" indicators
  - [x] Progress bar (overall video completion)
  - [x] Total BUX display (previous + session)
- [x] Add hook to `assets/js/app.js`
- [ ] Test seeking behavior (seek past high water mark should start earning)

**Files Created/Modified:**
- `assets/js/video_watch_tracker.js` - Complete VideoWatchTracker hook with high water mark system
- `assets/js/app.js` - Imported and registered VideoWatchTracker hook

### Phase 3: LiveView Backend - High Water Mark System (Day 3) ✅ COMPLETE

- [x] Add video state assigns to `show.ex` mount:
  - [x] `video_modal_open`
  - [x] `video_high_water_mark`
  - [x] `video_total_bux_earned`
  - [x] `video_completion_percentage`
  - [x] `video_fully_watched`
- [x] Add `load_video_engagement/1` helper (loads high water mark from Mnesia)
- [x] Implement event handlers:
  - [x] `handle_event("open_video_modal", ...)` - opens modal
  - [x] `handle_event("close_video_modal", ...)` - closes modal
  - [x] `handle_event("video-modal-opened", ...)` - records view start
  - [x] `handle_event("video-playing", ...)` - state tracking
  - [x] `handle_event("video-paused", ...)` - pause tracking
  - [x] `handle_event("video-watch-update", ...)` - periodic sync (every 5s)
  - [x] `handle_event("video-watch-complete", ...)` - finalize and mint
- [x] Implement `mint_video_session_reward/4` (mints for NEW territory only)
- [x] Implement `calculate_session_video_bux/4` (server-side calculation)
- [x] Implement `apply_video_penalties/2` (anti-gaming penalties)

**Files Modified:**
- `lib/blockster_v2_web/live/post_live/show.ex` - Added video state assigns, load_video_engagement/1 helper, all video event handlers, mint_video_session_reward/4, calculate_session_video_bux/4, apply_video_penalties/2

### Phase 4: EngagementTracker - High Water Mark Functions (Day 3) ✅ COMPLETE

- [x] Add `record_video_view/3` (creates initial record with high_water_mark = 0)
- [x] Add `get_video_engagement/2` (returns high_water_mark and totals)
- [x] Add `update_video_engagement_session/3` (updates high_water_mark and accumulates BUX)
- [x] Add `update_video_high_water_mark/3` (simple position update, no BUX)
- [x] Add `increment_video_views/1` (post stats - private)
- [x] Add `update_video_stats/2` (post stats aggregation - private)

**Files Modified:**
- `lib/blockster_v2/engagement_tracker.ex` - Added all video engagement functions (~200 lines)

### Phase 5: BuxMinter Updates (Day 3) ✅ COMPLETE

- [x] Add `:video_watch` to valid reward types in `mint_bux/7`
- [ ] Test minting flow end-to-end with session-based rewards

**Files Modified:**
- `lib/blockster_v2/bux_minter.ex` - Added `:video_watch` to valid reward types

### Phase 6: UI Templates - Dual Reward Display (Day 4) ✅ COMPLETE

- [x] Update featured image with play button overlay
- [x] Create video modal component with data attributes:
  - [x] `data-high-water-mark`
  - [x] `data-total-bux-earned`
  - [x] `data-video-duration`
  - [x] `data-bux-per-minute`
  - [x] `data-max-reward`
  - [x] `data-pool-available`
- [x] Create session BUX earnings panel (inside modal)
- [x] Add "Watching new content" indicator (green)
- [x] Add "Rewatching" indicator (gray)
- [x] Add progress bar showing overall video completion
- [x] Add "Video Complete!" state for fully watched videos
- [x] Add pool empty state panel
- [x] Add anonymous user login prompt
- [x] Add Video Earned badge (purple) shown outside modal after watching
- [x] Hide READ reward panel while video modal is open
- [x] Updated JS hook to finalize session on modal close (destroyed callback)

**Files Modified:**
- `lib/blockster_v2_web/live/post_live/show.html.heex` - Added play button overlay on featured image, full video modal with YouTube player, BUX earnings panel with new content/rewatching indicators, progress bar, completion states, Video Earned badge outside modal
- `assets/js/video_watch_tracker.js` - Added `finalizeWatching()` call in `destroyed()` callback to ensure BUX minting when modal closes

### Phase 7: Admin Interface (Day 4) ✅ COMPLETE

- [x] Add video URL field to post form
- [x] Add video duration field to post form
- [x] Add BUX per minute field to post form
- [x] Add max reward field to post form
- [x] Test video URL extraction (all YouTube URL formats)
- [x] Add Video Reward Preview panel (shows duration, rate, max earnable)
- [x] Show extracted video ID confirmation when URL is valid
- [ ] Consider: Auto-fetch video duration from YouTube API (future enhancement)

**Files Modified:**
- `lib/blockster_v2_web/live/post_live/form_component.html.heex` - Added Video Watch Rewards section with all fields, validation feedback, and reward preview panel

**Tested YouTube URL Formats (all working):**
- Standard: `https://www.youtube.com/watch?v=VIDEO_ID` ✓
- Short: `https://youtu.be/VIDEO_ID` ✓
- Embed: `https://www.youtube.com/embed/VIDEO_ID` ✓
- With timestamp: `?t=120` parameters handled correctly ✓
- HTTP URLs (auto-upgraded to HTTPS) ✓

### Phase 8: Testing - High Water Mark Scenarios (Day 5)

**Basic Functionality:**
- [ ] Test anonymous user experience (watch without earning)
- [ ] Test logged-in user first watch (fresh start, high_water_mark = 0)
- [ ] Test tab switching pauses earnings
- [ ] Test video pause pauses earnings
- [ ] Test video completion mints BUX

**High Water Mark Specific:**
- [ ] Test returning user sees previous progress (high_water_mark restored)
- [ ] Test rewatching old content does NOT earn BUX
- [ ] Test seeking PAST high water mark immediately starts earning
- [ ] Test seeking BEFORE high water mark shows "Rewatching" indicator
- [ ] Test multiple sessions accumulate correctly
- [ ] Test video fully watched state (no more BUX available)

**Edge Cases:**
- [ ] Test user watches 0:00 → 2:30, returns, watches 0:00 → 1:30 → no new BUX
- [ ] Test user watches 0:00 → 2:30, returns, watches 2:00 → 4:00 → earns 1:30 worth
- [ ] Test user seeks to 5:00 immediately → earns from 0:00 → current position? (decide: NO - only earns when position INCREASES beyond high water mark)
- [ ] Test pool depletion mid-session
- [ ] Test penalty calculations (excessive pausing/tab switching)

**Integration:**
- [ ] Test video reward + read reward on same post (both work independently)
- [ ] Test mobile experience (touch controls, fullscreen)
- [ ] Test various video lengths (short: 1min, medium: 10min, long: 60min)

### Phase 9: Deployment (Day 5)

- [ ] Run migration on production
- [ ] Deploy code changes
- [ ] Verify Mnesia tables created on all nodes
- [ ] Create test post with video
- [ ] Test complete flow on production
- [ ] Monitor for errors in logs

---

## Future Enhancements

1. **Video Chapters Support**: Track which chapters were watched, reward differently based on educational value
2. **Multi-Video Posts**: Support multiple videos per post with separate tracking
3. **Video Quality Score**: Weight rewards based on interaction quality (full-screen, unmuted)
4. **Rewatch Rewards**: Diminishing rewards for rewatching (e.g., 50% on second watch)
5. **Daily Caps**: Maximum BUX earnable from videos per day
6. **Video Analytics Dashboard**: Admin view of video performance metrics
7. **Vimeo Support**: Extend to support Vimeo embeds
8. **Native Video Upload**: Support for self-hosted videos

---

## Security Considerations

1. **Server-Side Calculation**: Never trust client-reported BUX amounts
2. **Rate Limiting**: Implement per-user video reward limits
3. **Pool Validation**: Always check pool balance before minting
4. **Transaction Verification**: Mark rewards paid only after confirmed mint
5. **Bot Detection**: Monitor for patterns (same IP, multiple accounts)
6. **Video Duration Validation**: Verify against YouTube API duration

---

## Performance Notes

1. **YouTube API**: Loaded once per page, cached by browser
2. **Update Frequency**: 5-second intervals balance UX and server load
3. **Mnesia Ops**: All dirty operations for speed
4. **Async Minting**: Minting happens in background Task
5. **PubSub Updates**: Real-time balance updates via Phoenix PubSub
