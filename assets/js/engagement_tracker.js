/**
 * EngagementTracker Hook
 *
 * Tracks user engagement with articles to determine reading quality.
 * Measures:
 * - Time spent on page (pauses when tab loses focus)
 * - Scroll depth and patterns
 * - Whether user reached end of article
 * - Natural vs bot-like scrolling behavior
 *
 * Sends "engagement-update" events periodically to let the server calculate
 * the engagement score. Server-side calculation is the single source of truth.
 */
export const EngagementTracker = {
  mounted() {
    // Track for both logged-in and anonymous users
    this.userId = this.el.dataset.userId;
    this.isAnonymous = !this.userId || this.userId === "anonymous";

    if (!this.isAnonymous) {
      // Logged-in user specific checks
      // Check if user already received reward for this article
      this.alreadyRewarded = this.el.dataset.alreadyRewarded === "true";
      if (this.alreadyRewarded) {
        console.log("EngagementTracker: User already rewarded for this article, skipping tracking");
        return;
      }

      // Check if pool has BUX available - no point tracking if there's nothing to earn
      this.poolAvailable = this.el.dataset.poolAvailable === "true";
      if (!this.poolAvailable) {
        console.log("EngagementTracker: Pool is empty, skipping tracking");
        return;
      }
    }

    console.log(`EngagementTracker: Starting ${this.isAnonymous ? 'anonymous' : 'authenticated'} tracking`);

    // Initialize tracking state
    this.postId = this.el.dataset.postId;
    this.wordCount = parseInt(this.el.dataset.wordCount, 10) || 0;
    this.minReadTime = Math.max(Math.floor(this.wordCount / 10), 5); // 10 words/sec, min 5s

    // Time tracking
    this.timeSpent = 0;
    this.lastTick = performance.now();
    this.isVisible = true;
    this.isPaused = false;

    // Scroll tracking
    this.scrollDepth = 0;
    this.scrollEvents = 0;
    this.scrollSpeeds = [];
    this.avgScrollSpeed = 0;
    this.maxScrollSpeed = 0;
    this.lastScrollY = window.scrollY;
    this.lastScrollTime = performance.now();
    this.scrollReversals = 0;
    this.lastScrollDirection = null;

    // Focus tracking
    this.focusChanges = 0;

    // State flags
    this.reachedEnd = false;
    this.hasRecordedRead = false;

    // Get article content element for calculating scroll depth
    this.articleEl = document.getElementById("post-content");
    // Get the end marker element for detecting when user reaches the end
    this.endMarkerEl = document.getElementById("article-end-marker");

    // Send initial visit event (only for logged-in users)
    if (!this.isAnonymous) {
      this.pushEvent("article-visited", {
        min_read_time: this.minReadTime,
        word_count: this.wordCount
      });
    }

    console.log(`EngagementTracker: Started tracking post ${this.postId} (${this.wordCount} words, ${this.minReadTime}s min read)`);

    // Start time tracking
    this.startTimeTracking();

    // Set up visibility tracking
    this.handleVisibilityChange = () => {
      if (document.visibilityState === "hidden") {
        this.pause();
        this.focusChanges++;
      } else {
        this.resume();
      }
    };
    document.addEventListener("visibilitychange", this.handleVisibilityChange);

    // Send updates periodically (every 2 seconds) - server calculates the score
    this.updateInterval = setInterval(() => {
      if (!this.isPaused && !this.hasRecordedRead) {
        this.sendEngagementUpdate();
      }
    }, 2000);

    // Send initial update immediately for anonymous users to show the panel
    if (this.isAnonymous) {
      setTimeout(() => this.sendEngagementUpdate(), 100);
    }

    // Delay scroll tracking setup to let page scroll position settle after navigation
    // This prevents false "end reached" triggers when navigating from a scrolled page
    setTimeout(() => {
      // Set up scroll tracking
      this.handleScroll = this.throttle(() => this.trackScroll(), 100);
      window.addEventListener("scroll", this.handleScroll, { passive: true });

      // Initial scroll depth check (in case article is short)
      setTimeout(() => this.trackScroll(), 500);
    }, 500);

    // Watch for video modal state changes via MutationObserver on data attribute
    this.videoModalObserver = new MutationObserver((mutations) => {
      for (const mutation of mutations) {
        if (mutation.type === "attributes" && mutation.attributeName === "data-video-modal-open") {
          const isVideoModalOpen = this.el.dataset.videoModalOpen === "true";
          if (isVideoModalOpen) {
            console.log("EngagementTracker: Video modal opened, pausing tracking");
            this.pause();
          } else {
            console.log("EngagementTracker: Video modal closed, resuming tracking");
            this.resume();
          }
        }
      }
    });
    this.videoModalObserver.observe(this.el, { attributes: true, attributeFilter: ["data-video-modal-open"] });
  },

  // Send engagement update to server - server calculates the score
  sendEngagementUpdate() {
    const metrics = {
      time_spent: this.timeSpent,
      min_read_time: this.minReadTime,
      scroll_depth: Math.round(this.scrollDepth),
      reached_end: this.reachedEnd,
      scroll_events: this.scrollEvents,
      avg_scroll_speed: Math.round(this.avgScrollSpeed),
      max_scroll_speed: Math.round(this.maxScrollSpeed),
      scroll_reversals: this.scrollReversals,
      focus_changes: this.focusChanges
    };

    console.log(`EngagementTracker: Sending update - time: ${this.timeSpent}s, depth: ${Math.round(this.scrollDepth)}%, events: ${this.scrollEvents}`);

    try {
      if (this.isAnonymous) {
        // Send anonymous engagement update (no DB persistence, just score calculation)
        this.pushEvent("anonymous-engagement-update", metrics);
      } else {
        // Send normal engagement update for logged-in users
        this.pushEvent("engagement-update", metrics);
      }
    } catch (e) {
      // LiveView may be disconnected during page navigation, this is expected
      console.debug("EngagementTracker: Could not send engagement-update (LiveView disconnected)");
    }
  },

  startTimeTracking() {
    this.lastTick = performance.now();
    this.isVisible = true;
    this.isPaused = false;

    // Use requestAnimationFrame for accurate time tracking
    this.rafId = requestAnimationFrame(() => this.tick());
  },

  tick() {
    if (this.isPaused || !this.isVisible) {
      this.rafId = requestAnimationFrame(() => this.tick());
      return;
    }

    const now = performance.now();
    const elapsed = (now - this.lastTick) / 1000;

    if (elapsed >= 1) {
      const wholeSeconds = Math.floor(elapsed);
      this.timeSpent += wholeSeconds;
      this.lastTick = now - ((elapsed - wholeSeconds) * 1000);
    }

    this.rafId = requestAnimationFrame(() => this.tick());
  },

  pause() {
    this.isPaused = true;
    this.isVisible = false;
  },

  resume() {
    this.isPaused = false;
    this.isVisible = true;
    this.lastTick = performance.now();
    this.lastScrollTime = performance.now();
  },

  trackScroll() {
    if (!this.articleEl || this.isPaused) return;

    const now = performance.now();
    const currentScrollY = window.scrollY;

    // Calculate scroll speed (pixels per second)
    const timeDelta = (now - this.lastScrollTime) / 1000;
    if (timeDelta > 0) {
      const scrollDelta = Math.abs(currentScrollY - this.lastScrollY);
      const speed = scrollDelta / timeDelta;

      if (speed > 0) {
        this.scrollSpeeds.push(speed);
        // Keep last 50 scroll speed measurements
        if (this.scrollSpeeds.length > 50) {
          this.scrollSpeeds.shift();
        }

        // Update max speed
        if (speed > this.maxScrollSpeed) {
          this.maxScrollSpeed = speed;
        }

        // Calculate average
        this.avgScrollSpeed = this.scrollSpeeds.reduce((a, b) => a + b, 0) / this.scrollSpeeds.length;
      }
    }

    // Track scroll direction changes (reversals indicate reading back)
    const direction = currentScrollY > this.lastScrollY ? "down" : "up";
    if (this.lastScrollDirection && direction !== this.lastScrollDirection) {
      this.scrollReversals++;
    }
    this.lastScrollDirection = direction;

    this.lastScrollY = currentScrollY;
    this.lastScrollTime = now;
    this.scrollEvents++;

    // Calculate scroll depth relative to article content
    const articleRect = this.articleEl.getBoundingClientRect();
    const articleTop = articleRect.top + window.scrollY;
    const viewportBottom = window.scrollY + window.innerHeight;

    // Calculate how much of the article has been scrolled past
    const articleScrolled = viewportBottom - articleTop;
    const articleHeight = articleRect.height;

    if (articleHeight > 0) {
      const newDepth = Math.min(100, Math.max(0, (articleScrolled / articleHeight) * 100));
      if (newDepth > this.scrollDepth) {
        this.scrollDepth = newDepth;
      }
    }

    // Check if the end marker is visible in the viewport
    // Use the dedicated end marker if available, otherwise fall back to article bottom
    // Require the marker to be at least 200px above the bottom of the viewport
    // This ensures user has scrolled well past the content, not just reached it
    let isEndReached = false;

    if (this.endMarkerEl) {
      const markerRect = this.endMarkerEl.getBoundingClientRect();
      // Marker must be visible and at least 200px from bottom of viewport
      isEndReached = markerRect.top <= (window.innerHeight - 200);
    } else {
      // Fallback: article bottom must be at least 200px from bottom of viewport
      isEndReached = articleRect.bottom <= (window.innerHeight - 200);
    }

    if (isEndReached && !this.reachedEnd) {
      this.reachedEnd = true;
      this.scrollDepth = 100; // Set to 100% since we've actually seen the end
      console.log("EngagementTracker: User reached end of article (marker/bottom visible with 100px buffer)");

      // Send the article-read event
      this.sendReadEvent();
    }
  },

  sendReadEvent() {
    if (this.hasRecordedRead) return;
    this.hasRecordedRead = true;

    const metrics = {
      time_spent: this.timeSpent,
      min_read_time: this.minReadTime,
      scroll_depth: Math.round(this.scrollDepth),
      reached_end: this.reachedEnd,
      scroll_events: this.scrollEvents,
      avg_scroll_speed: Math.round(this.avgScrollSpeed),
      max_scroll_speed: Math.round(this.maxScrollSpeed),
      scroll_reversals: this.scrollReversals,
      focus_changes: this.focusChanges
    };

    console.log("EngagementTracker: Sending article-read event", metrics);

    if (this.isAnonymous) {
      // For anonymous users, store in localStorage and show signup prompt
      this.storeForClaim(metrics);
      try {
        this.pushEvent("show-anonymous-claim", { metrics });
      } catch (e) {
        console.debug("EngagementTracker: Could not send show-anonymous-claim event (LiveView disconnected)");
      }
    } else {
      // For logged-in users, send normal article-read event
      try {
        this.pushEvent("article-read", metrics);
      } catch (e) {
        console.debug("EngagementTracker: Could not send article-read event (LiveView disconnected)");
      }
    }
  },

  // Store engagement data in localStorage for claim after signup
  storeForClaim(metrics) {
    // Calculate earned amount (5 BUX per engagement point)
    // We'll calculate the score here to store the exact amount
    const score = this.calculateEngagementScore(metrics);
    const earnedAmount = score * 5.0;

    const claimData = {
      postId: this.postId,
      type: 'read',
      metrics: metrics,
      earnedAmount: earnedAmount,
      timestamp: Date.now(),
      expiresAt: Date.now() + (30 * 60 * 1000) // 30 minutes
    };

    try {
      localStorage.setItem(`pending_claim_read_${this.postId}`, JSON.stringify(claimData));
      console.log(`EngagementTracker: Stored claim for ${earnedAmount} BUX in localStorage`);
    } catch (e) {
      console.error("EngagementTracker: Failed to store claim in localStorage", e);
    }
  },

  // Calculate engagement score client-side (mirrors server logic)
  calculateEngagementScore(metrics) {
    const baseScore = 1.0;

    // Time score (0-6 points)
    const timeRatio = metrics.min_read_time > 0 ? metrics.time_spent / metrics.min_read_time : 0;
    let timeScore = 0;
    if (timeRatio >= 1.0) timeScore = 6;
    else if (timeRatio >= 0.9) timeScore = 5;
    else if (timeRatio >= 0.8) timeScore = 4;
    else if (timeRatio >= 0.7) timeScore = 3;
    else if (timeRatio >= 0.5) timeScore = 2;
    else if (timeRatio >= 0.3) timeScore = 1;

    // Depth score (0-3 points)
    let depthScore = 0;
    if (metrics.reached_end || metrics.scroll_depth >= 100) depthScore = 3;
    else if (metrics.scroll_depth >= 66) depthScore = 2;
    else if (metrics.scroll_depth >= 33) depthScore = 1;

    const finalScore = baseScore + timeScore + depthScore;
    return Math.min(Math.max(finalScore, 1.0), 10.0);
  },

  // Utility: throttle function to limit scroll event frequency
  throttle(func, limit) {
    let inThrottle;
    return function(...args) {
      if (!inThrottle) {
        func.apply(this, args);
        inThrottle = true;
        setTimeout(() => inThrottle = false, limit);
      }
    };
  },

  destroyed() {
    // Clean up
    if (this.rafId) {
      cancelAnimationFrame(this.rafId);
    }
    if (this.updateInterval) {
      clearInterval(this.updateInterval);
    }
    if (this.handleScroll) {
      window.removeEventListener("scroll", this.handleScroll);
    }
    if (this.handleVisibilityChange) {
      document.removeEventListener("visibilitychange", this.handleVisibilityChange);
    }
    if (this.videoModalObserver) {
      this.videoModalObserver.disconnect();
    }

    // Don't try to push events in destroyed() - LiveView is already disconnecting
    // Trying to push here causes "unable to push hook event" errors
    console.debug("EngagementTracker: Hook destroyed, cleanup complete");
  }
};
