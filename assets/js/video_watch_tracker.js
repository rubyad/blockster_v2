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
 * - Pauses tracking when video is MUTED (must have audio to earn)
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
    this.userMultiplier = parseFloat(this.el.dataset.userMultiplier) || 1.0;

    // HIGH WATER MARK: Previous furthest position watched (from server/Mnesia)
    // User only earns BUX when currentPosition > highWaterMark
    this.highWaterMark = parseFloat(this.el.dataset.highWaterMark) || 0;
    this.totalBuxEarnedPreviously = parseFloat(this.el.dataset.totalBuxEarned) || 0;

    // Check if video is fully watched (high water mark >= duration)
    this.videoFullyWatched = this.videoDuration > 0 && this.highWaterMark >= this.videoDuration;

    // Track for both logged-in and anonymous users
    this.isAnonymous = !this.userId || this.userId === "anonymous";

    // Skip tracking conditions
    if (!this.isAnonymous && this.videoFullyWatched) {
      console.log("VideoWatchTracker: Video fully watched, no more BUX available");
      this.trackingEnabled = false;
    } else if (!this.isAnonymous && !this.poolAvailable) {
      console.log("VideoWatchTracker: Pool empty, no rewards available");
      this.trackingEnabled = false;
    } else {
      this.trackingEnabled = true;
      if (this.isAnonymous) {
        console.log("VideoWatchTracker: Anonymous user - tracking for claim on signup");
        // Anonymous users start with 0 high water mark (no previous watch history)
        this.highWaterMark = 0;
        this.totalBuxEarnedPreviously = 0;
      }
    }

    // Session tracking state
    this.sessionEarnableTime = 0;     // Seconds spent BEYOND high water mark this session
    this.sessionMaxPosition = 0;       // Highest position reached this session
    this.lastPosition = 0;             // Last polled position
    this.lastTickTime = null;
    this.isPlaying = false;
    this.isTabVisible = true;
    this.isMuted = false;             // Track mute state - no earnings while muted
    this.pauseCount = 0;
    this.tabAwayCount = 0;
    this.muteCount = 0;               // Track how many times user muted

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

    // Listen for seek-to-hwm custom event dispatched by JS.dispatch from rewatching button
    this.el.addEventListener("seek-to-hwm", () => {
      console.log("VideoWatchTracker: Received seek-to-hwm event");
      this.seekToHighWaterMark();
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
      // Update fully watched check with actual duration
      this.videoFullyWatched = this.highWaterMark >= duration;
      if (this.videoFullyWatched && this.trackingEnabled) {
        this.trackingEnabled = false;
        console.log("VideoWatchTracker: Video fully watched (updated with actual duration)");
      }
    }

    // Check initial mute state
    this.isMuted = this.player.isMuted() || this.player.getVolume() === 0;
    if (this.isMuted) {
      console.log("VideoWatchTracker: Video started muted - unmute to earn BUX");
      this.updateMuteIndicator();
    }

    // Set up mute state polling (YouTube API doesn't have mute change event)
    this.muteCheckInterval = setInterval(() => this.checkMuteState(), 1000);
  },

  seekToHighWaterMark() {
    if (!this.player) return;

    // Use the running high water mark (original + session max) for the seek target
    const runningHighWaterMark = Math.max(this.highWaterMark, this.sessionMaxPosition);

    // Seek to just past the running high water mark (add 1 second to ensure we're in new territory)
    const seekTarget = Math.min(runningHighWaterMark + 1, this.videoDuration);
    console.log(`VideoWatchTracker: Seeking to running high water mark at ${seekTarget}s`);

    this.player.seekTo(seekTarget, true);

    // Update last position and session max to avoid earning issues and indicator flickering
    this.lastPosition = seekTarget;
    this.sessionMaxPosition = seekTarget;

    // Immediately update the display to hide rewatching indicator
    this.updateBuxDisplay(seekTarget);
  },

  checkMuteState() {
    if (!this.player) return;

    const wasMuted = this.isMuted;
    this.isMuted = this.player.isMuted() || this.player.getVolume() === 0;

    if (this.isMuted !== wasMuted) {
      if (this.isMuted) {
        this.muteCount++;
        this.stopTracking();
        console.log("VideoWatchTracker: Video muted - pausing earnings");
      } else {
        console.log("VideoWatchTracker: Video unmuted - resuming earnings");
        // Resume tracking if video is playing and tab visible
        if (this.isPlaying && this.isTabVisible && this.trackingEnabled) {
          this.startTracking();
        }
      }
      this.updateMuteIndicator();
    }
  },

  updateMuteIndicator() {
    const muteIndicator = document.getElementById("video-muted-warning");
    if (muteIndicator) {
      muteIndicator.style.display = this.isMuted ? "block" : "none";
    }
    // Update panel colors when mute state changes
    this.updatePanelColor();
    this.updateAnonymousPanelColor();
    this.updatePanelColor();
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
    this.updatePanelColor();
    this.updateAnonymousPanelColor();
    this.pushEvent("video-playing", { post_id: this.postId });
  },

  onVideoPause() {
    console.log("VideoWatchTracker: Video paused");
    this.isPlaying = false;
    this.pauseCount++;
    this.stopTracking();
    this.updatePanelColor();
    this.updateAnonymousPanelColor();
    this.pushEvent("video-paused", {
      post_id: this.postId,
      session_earnable_time: this.sessionEarnableTime,
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
    // Tab visibility handler
    this.handleVisibilityChange = () => {
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
    };
    document.addEventListener("visibilitychange", this.handleVisibilityChange);

    // Window blur handler
    this.handleWindowBlur = () => {
      if (this.isPlaying) {
        this.stopTracking();
        console.log("VideoWatchTracker: Window blur, pausing");
      }
    };
    window.addEventListener("blur", this.handleWindowBlur);

    // Window focus handler
    this.handleWindowFocus = () => {
      if (this.isPlaying && this.isTabVisible && this.trackingEnabled) {
        this.startTracking();
        console.log("VideoWatchTracker: Window focus, resuming");
      }
    };
    window.addEventListener("focus", this.handleWindowFocus);
  },

  startTracking() {
    if (this.rafId) return; // Already tracking
    if (this.isMuted) return; // Don't start tracking if muted

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
    if (!this.isPlaying || !this.isTabVisible || !this.trackingEnabled || this.isMuted) {
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
      // Use the running high water mark (original + session max) to prevent re-earning
      const runningHighWaterMark = Math.max(this.highWaterMark, this.sessionMaxPosition);

      // Only count time if we're BEYOND the running high water mark
      if (currentPosition > runningHighWaterMark) {
        // Calculate how much NEW time was watched
        // If we jumped ahead (seeked), only count from where we landed
        const effectiveStartPosition = Math.max(this.lastPosition, runningHighWaterMark);

        if (currentPosition > effectiveStartPosition) {
          const newTimeWatched = currentPosition - effectiveStartPosition;
          // Clamp to actual elapsed time (prevents seek exploitation)
          this.sessionEarnableTime += Math.min(newTimeWatched, wholeSeconds);
        }
      }

      // Track session's maximum position (for updating high water mark on close)
      if (currentPosition > this.sessionMaxPosition) {
        this.sessionMaxPosition = currentPosition;
      }

      this.lastPosition = currentPosition;

      // Update BUX display - pass current position for accurate indicator
      this.updateBuxDisplay(currentPosition);
    }

    this.rafId = requestAnimationFrame(() => this.tick());
  },

  updateBuxDisplay(currentPosition = null) {
    // Use passed position or fall back to last known position
    const displayPosition = currentPosition !== null ? currentPosition : this.lastPosition;

    // Calculate BUX for THIS SESSION
    const earnableMinutes = this.sessionEarnableTime / 60;
    let sessionBux;

    if (this.isAnonymous) {
      // Anonymous users: 15 BUX per minute (no multiplier)
      sessionBux = earnableMinutes * 15.0;
    } else {
      // Logged-in users: use post's configured rate × user multiplier
      sessionBux = earnableMinutes * this.buxPerMinute * this.userMultiplier;
    }

    // Calculate max possible remaining BUX (from current high water mark to end)
    const remainingSeconds = Math.max(0, this.videoDuration - this.highWaterMark);
    const earnRate = this.isAnonymous ? 15.0 : this.buxPerMinute * this.userMultiplier;
    const maxRemainingBux = (remainingSeconds / 60) * earnRate;

    // Can't earn more than remaining video allows
    sessionBux = Math.min(sessionBux, maxRemainingBux);

    this.sessionBux = Math.round(sessionBux * 100) / 100; // Round to 2 decimals

    // Update the display element (template already has + prefix)
    const buxDisplay = document.getElementById("video-bux-earned");
    if (buxDisplay) {
      buxDisplay.textContent = this.sessionBux.toFixed(2);
    }

    // Update the total display (previously earned + this session)
    const totalDisplay = document.getElementById("video-bux-total");
    if (totalDisplay) {
      const total = this.totalBuxEarnedPreviously + this.sessionBux;
      totalDisplay.textContent = total.toFixed(2);
    }

    // Update anonymous video earnings
    const anonymousBuxDisplay = document.getElementById("anonymous-video-bux");
    if (anonymousBuxDisplay) {
      anonymousBuxDisplay.textContent = this.sessionBux.toFixed(2);
    }

    // Update progress bar - shows overall video completion
    const progressBar = document.getElementById("video-watch-progress");
    if (progressBar && this.videoDuration > 0) {
      const newHighWaterMark = Math.max(this.highWaterMark, this.sessionMaxPosition);
      const progress = Math.min(100, (newHighWaterMark / this.videoDuration) * 100);
      progressBar.style.width = `${progress}%`;
    }

    // Update anonymous progress bar
    const anonymousProgressBar = document.getElementById("anonymous-video-watch-progress");
    if (anonymousProgressBar && this.videoDuration > 0) {
      const newHighWaterMark = Math.max(this.highWaterMark, this.sessionMaxPosition);
      const progress = Math.min(100, (newHighWaterMark / this.videoDuration) * 100);
      anonymousProgressBar.style.width = `${progress}%`;
    }

    // Update video progress time display (current position / total)
    // Use displayPosition for real-time playback position (not high water mark)
    const progressTime = document.getElementById("video-progress-time");
    if (progressTime && this.videoDuration > 0) {
      const currentTime = this.formatTime(displayPosition);
      const totalTime = this.formatTime(this.videoDuration);
      progressTime.textContent = `${currentTime} / ${totalTime}`;
    }

    // Update anonymous progress time
    const anonymousProgressTime = document.getElementById("anonymous-video-progress-time");
    if (anonymousProgressTime && this.videoDuration > 0) {
      const currentTime = this.formatTime(displayPosition);
      const totalTime = this.formatTime(this.videoDuration);
      anonymousProgressTime.textContent = `${currentTime} / ${totalTime}`;
    }

    // Update "watching new content" indicator
    // Use displayPosition for accurate real-time indicator (not stale lastPosition)
    // Compare against running high water mark (original + session max) to prevent false positives
    const newContentIndicator = document.getElementById("video-new-content");
    const rewatchingIndicator = document.getElementById("video-rewatching");
    const anonymousNewContentIndicator = document.getElementById("anonymous-video-new-content");

    if (newContentIndicator && rewatchingIndicator) {
      const runningHighWaterMark = Math.max(this.highWaterMark, this.sessionMaxPosition);
      // Use >= to include the exact position when user seeks to high water mark
      const isWatchingNew = displayPosition >= runningHighWaterMark;
      const showRewatching = !isWatchingNew && this.isPlaying;

      // Use classList to toggle 'hidden' class (Tailwind's hidden uses !important)
      if (isWatchingNew) {
        newContentIndicator.classList.remove("hidden");
      } else {
        newContentIndicator.classList.add("hidden");
      }

      if (showRewatching) {
        rewatchingIndicator.classList.remove("hidden");
      } else {
        rewatchingIndicator.classList.add("hidden");
      }

      // Update panel color based on earning state
      this.updatePanelColor(isWatchingNew);
    }

    // Update anonymous new content indicator
    if (anonymousNewContentIndicator) {
      const runningHighWaterMark = Math.max(this.highWaterMark, this.sessionMaxPosition);
      const isWatchingNew = displayPosition >= runningHighWaterMark;

      if (isWatchingNew && this.isPlaying) {
        anonymousNewContentIndicator.classList.remove("hidden");
      } else {
        anonymousNewContentIndicator.classList.add("hidden");
      }

      // Update anonymous panel color
      this.updateAnonymousPanelColor(isWatchingNew);
    }
  },

  // Update the earnings panel background color based on whether user is currently earning
  updatePanelColor(isEarning = null) {
    const panel = document.getElementById("video-earnings-panel");
    if (!panel) return;

    // Determine if currently earning: must be playing, not muted, and watching new content
    let currentlyEarning = isEarning;
    if (currentlyEarning === null) {
      // Fallback calculation if not passed
      const runningHighWaterMark = Math.max(this.highWaterMark, this.sessionMaxPosition);
      currentlyEarning = this.lastPosition >= runningHighWaterMark;
    }

    const isActivelyEarning = this.isPlaying && !this.isMuted && currentlyEarning;

    // Use inline style for reliable color change
    if (isActivelyEarning) {
      panel.style.background = "linear-gradient(to right, #8AE388, #6BCB69)";
    } else {
      panel.style.background = "linear-gradient(to right, #6B7280, #4B5563)";
    }
  },

  // Update the anonymous earnings panel background color
  updateAnonymousPanelColor(isEarning = null) {
    const panel = document.getElementById("anonymous-video-earnings");
    if (!panel) return;

    // Determine if currently earning
    let currentlyEarning = isEarning;
    if (currentlyEarning === null) {
      const runningHighWaterMark = Math.max(this.highWaterMark, this.sessionMaxPosition);
      currentlyEarning = this.lastPosition >= runningHighWaterMark;
    }

    const isActivelyEarning = this.isPlaying && !this.isMuted && currentlyEarning;

    // Use inline style for reliable color change
    if (isActivelyEarning) {
      panel.style.background = "linear-gradient(to right, #8AE388, #6BCB69)";
    } else {
      panel.style.background = "linear-gradient(to right, #6B7280, #4B5563)";
    }
  },

  sendUpdate() {
    if (!this.trackingEnabled) return;

    // Only send if BUX amount changed significantly
    if (Math.abs(this.sessionBux - this.lastReportedBux) < 0.1) return;

    const newHighWaterMark = Math.max(this.highWaterMark, this.sessionMaxPosition);
    const completionPercentage = this.videoDuration > 0
      ? Math.round((newHighWaterMark / this.videoDuration) * 100)
      : 0;

    const metrics = {
      post_id: this.postId,
      session_earnable_time: this.sessionEarnableTime,
      session_max_position: this.sessionMaxPosition,
      new_high_water_mark: newHighWaterMark,
      video_duration: this.videoDuration,
      completion_percentage: completionPercentage,
      session_bux_earned: this.sessionBux,
      pause_count: this.pauseCount,
      tab_away_count: this.tabAwayCount,
      mute_count: this.muteCount
    };

    console.log("VideoWatchTracker: Sending update", metrics);
    this.pushEvent("video-watch-update", metrics);
    this.lastReportedBux = this.sessionBux;
  },

  finalizeWatching() {
    // Calculate new high water mark (highest of: previous, session max)
    const newHighWaterMark = Math.max(this.highWaterMark, this.sessionMaxPosition);
    const completionPercentage = this.videoDuration > 0
      ? Math.round((newHighWaterMark / this.videoDuration) * 100)
      : 0;

    // Handle anonymous users differently
    if (this.isAnonymous && this.sessionEarnableTime > 0) {
      // Store in localStorage for claim after signup
      this.storeVideoClaimData();
      // Show signup prompt
      try {
        this.pushEvent("show-anonymous-video-claim", {
          buxEarned: this.sessionBux,
          earnableTime: this.sessionEarnableTime
        });
      } catch (e) {
        console.debug("VideoWatchTracker: Could not send show-anonymous-video-claim (LiveView disconnected)");
      }
      return;
    }

    if (!this.trackingEnabled || this.sessionBux <= 0) {
      this.pushEvent("video-watch-complete", {
        post_id: this.postId,
        session_earnable_time: this.sessionEarnableTime,
        session_bux_earned: 0,
        session_max_position: this.sessionMaxPosition,
        previous_high_water_mark: this.highWaterMark,
        new_high_water_mark: newHighWaterMark,
        video_duration: this.videoDuration,
        completion_percentage: completionPercentage,
        pause_count: this.pauseCount,
        tab_away_count: this.tabAwayCount,
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
      completion_percentage: completionPercentage,
      // Anti-gaming metrics
      pause_count: this.pauseCount,
      tab_away_count: this.tabAwayCount,
      mute_count: this.muteCount
    };

    console.log("VideoWatchTracker: Finalizing session", metrics);
    this.pushEvent("video-watch-complete", metrics);
  },

  // Store video watch data in localStorage for claim after signup
  storeVideoClaimData() {
    const claimData = {
      postId: this.postId,
      type: 'video',
      earnableTime: this.sessionEarnableTime,
      earnedAmount: this.sessionBux,
      timestamp: Date.now(),
      expiresAt: Date.now() + (30 * 60 * 1000) // 30 minutes
    };

    try {
      localStorage.setItem(`pending_claim_video_${this.postId}`, JSON.stringify(claimData));
      console.log(`VideoWatchTracker: Stored claim for ${this.sessionBux} BUX in localStorage`);
    } catch (e) {
      console.error("VideoWatchTracker: Failed to store claim in localStorage", e);
    }
  },

  // Called when user closes modal without video ending
  closeModal() {
    this.stopTracking();
    if (this.player) {
      this.player.pauseVideo();
    }
    this.finalizeWatching();
  },

  // Format seconds to "M:SS" or "H:MM:SS" format
  formatTime(seconds) {
    const totalSeconds = Math.floor(seconds);
    const hours = Math.floor(totalSeconds / 3600);
    const minutes = Math.floor((totalSeconds % 3600) / 60);
    const secs = totalSeconds % 60;

    if (hours > 0) {
      return `${hours}:${String(minutes).padStart(2, "0")}:${String(secs).padStart(2, "0")}`;
    }
    return `${minutes}:${String(secs).padStart(2, "0")}`;
  },

  destroyed() {
    // Finalize the watching session before cleanup - this mints BUX if earned
    this.finalizeWatching();

    this.stopTracking();

    if (this.updateInterval) {
      clearInterval(this.updateInterval);
    }

    if (this.muteCheckInterval) {
      clearInterval(this.muteCheckInterval);
    }

    if (this.player) {
      this.player.destroy();
    }

    // Clean up event listeners
    document.removeEventListener("visibilitychange", this.handleVisibilityChange);
    window.removeEventListener("blur", this.handleWindowBlur);
    window.removeEventListener("focus", this.handleWindowFocus);

    console.log("VideoWatchTracker: Destroyed");
  }
};
