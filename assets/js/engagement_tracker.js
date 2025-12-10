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
 * Sends "article-visited" on mount and "article-read" when user scrolls to end.
 */
export const EngagementTracker = {
  mounted() {
    // Only track for logged-in users
    this.userId = this.el.dataset.userId;
    if (!this.userId || this.userId === "anonymous") {
      console.log("EngagementTracker: Anonymous user, skipping tracking");
      return;
    }

    // Check if user already received reward for this article
    this.alreadyRewarded = this.el.dataset.alreadyRewarded === "true";
    if (this.alreadyRewarded) {
      console.log("EngagementTracker: User already rewarded for this article, skipping tracking");
      return;
    }

    // Initialize tracking state
    this.postId = this.el.dataset.postId;
    this.wordCount = parseInt(this.el.dataset.wordCount, 10) || 0;
    this.minReadTime = Math.max(Math.floor(this.wordCount / 5), 10); // 5 words/sec, min 10s

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

    // BUX reward data from server
    this.baseBuxReward = parseInt(this.el.dataset.baseBuxReward, 10) || 1;
    this.userMultiplier = parseInt(this.el.dataset.userMultiplier, 10) || 1;

    // Get article content element for calculating scroll depth
    this.articleEl = document.getElementById("post-content");

    // Send initial visit event
    this.pushEvent("article-visited", {
      min_read_time: this.minReadTime,
      word_count: this.wordCount
    });

    console.log(`EngagementTracker: Started tracking post ${this.postId} (${this.wordCount} words, ${this.minReadTime}s min read, base reward: ${this.baseBuxReward}, multiplier: ${this.userMultiplier})`);

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

    // Delay scroll tracking setup to let page scroll position settle after navigation
    // This prevents false "end reached" triggers when navigating from a scrolled page
    setTimeout(() => {
      // Set up scroll tracking
      this.handleScroll = this.throttle(() => this.trackScroll(), 100);
      window.addEventListener("scroll", this.handleScroll, { passive: true });

      // Initial scroll depth check (in case article is short)
      setTimeout(() => this.trackScroll(), 500);
    }, 500);
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

    // Check if the actual bottom of the article is visible in the viewport
    // articleRect.bottom is relative to viewport, so if it's <= window.innerHeight, it's visible
    const isBottomVisible = articleRect.bottom <= window.innerHeight;

    if (isBottomVisible && !this.reachedEnd) {
      this.reachedEnd = true;
      this.scrollDepth = 100; // Set to 100% since we've actually seen the end
      console.log("EngagementTracker: User reached end of article (bottom visible)");

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
    try {
      this.pushEvent("article-read", metrics);
    } catch (e) {
      // LiveView may be disconnected during page navigation, this is expected
      console.debug("EngagementTracker: Could not send article-read event (LiveView disconnected)");
    }
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
    window.removeEventListener("scroll", this.handleScroll);
    document.removeEventListener("visibilitychange", this.handleVisibilityChange);

    // Send final read event if user reached end but we haven't sent it yet
    if (this.reachedEnd && !this.hasRecordedRead) {
      this.sendReadEvent();
    }
  }
};
