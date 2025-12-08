/**
 * TimeTracker Hook
 * Tracks time spent on a page, pausing when tab loses focus,
 * and sends updates to the server periodically.
 */
export const TimeTracker = {
  mounted() {
    this.totalSeconds = 0;
    this.lastTick = null;
    this.isVisible = true;
    this.isPaused = false;
    this.updateInterval = 5000; // Send updates every 5 seconds
    this.tickInterval = 100; // Check every 100ms for smooth counting

    // Initialize with server-provided time from data attribute
    this.serverSeconds = parseInt(this.el.dataset.initialTime, 10) || 0;

    // Start tracking
    this.startTracking();

    // Visibility change handler
    this.handleVisibilityChange = () => {
      if (document.visibilityState === "hidden") {
        this.pause();
      } else {
        this.resume();
      }
    };

    // Before unload handler - send final time
    this.handleBeforeUnload = () => {
      this.sendFinalTime();
    };

    // Add event listeners
    document.addEventListener("visibilitychange", this.handleVisibilityChange);
    window.addEventListener("beforeunload", this.handleBeforeUnload);

    // Set up periodic server updates
    this.serverUpdateTimer = setInterval(() => {
      this.sendTimeUpdate();
    }, this.updateInterval);
  },

  startTracking() {
    this.lastTick = performance.now();
    this.isVisible = true;
    this.isPaused = false;

    // Use requestAnimationFrame for smooth counting
    this.rafId = requestAnimationFrame(() => this.tick());
  },

  tick() {
    if (this.isPaused || !this.isVisible) {
      this.rafId = requestAnimationFrame(() => this.tick());
      return;
    }

    const now = performance.now();
    const elapsed = (now - this.lastTick) / 1000; // Convert to seconds

    if (elapsed >= 1) {
      const wholeSeconds = Math.floor(elapsed);
      this.totalSeconds += wholeSeconds;
      this.lastTick = now - ((elapsed - wholeSeconds) * 1000);

      // Update the local display
      this.updateLocalDisplay();
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
  },

  sendTimeUpdate() {
    if (this.totalSeconds > 0) {
      const secondsToSend = this.totalSeconds;
      // Move sent time to serverSeconds (already persisted), reset local counter
      this.serverSeconds += secondsToSend;
      this.totalSeconds = 0;

      this.pushEvent("time_update", { seconds: secondsToSend });
    }
  },

  sendFinalTime() {
    // Use sendBeacon for reliable delivery on page unload
    if (this.totalSeconds > 0) {
      const userId = this.el.dataset.userId;
      const postId = this.el.dataset.postId;

      if (userId && postId) {
        // Try pushEvent first (may not work on unload)
        this.pushEvent("time_update", { seconds: this.totalSeconds });

        // Also use navigator.sendBeacon as backup
        const data = JSON.stringify({
          user_id: userId,
          post_id: postId,
          seconds: this.totalSeconds,
          _csrf_token: document.querySelector("meta[name='csrf-token']")?.content
        });

        navigator.sendBeacon("/api/time-tracker", data);
      }
    }
  },

  updateLocalDisplay() {
    const displayEl = document.getElementById("time-spent-display");
    if (displayEl) {
      // Total = server time (initial + already sent) + local unsent time
      displayEl.textContent = this.formatTime(this.serverSeconds + this.totalSeconds);
    }
  },

  formatTime(seconds) {
    if (seconds < 60) {
      return `${seconds}s`;
    } else if (seconds < 3600) {
      const mins = Math.floor(seconds / 60);
      const secs = seconds % 60;
      return `${mins}m ${secs}s`;
    } else {
      const hours = Math.floor(seconds / 3600);
      const mins = Math.floor((seconds % 3600) / 60);
      return `${hours}h ${mins}m`;
    }
  },

  destroyed() {
    // Send any remaining time
    this.sendFinalTime();

    // Clean up
    if (this.rafId) {
      cancelAnimationFrame(this.rafId);
    }
    if (this.serverUpdateTimer) {
      clearInterval(this.serverUpdateTimer);
    }
    document.removeEventListener("visibilitychange", this.handleVisibilityChange);
    window.removeEventListener("beforeunload", this.handleBeforeUnload);
  }
};
