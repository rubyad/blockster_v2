/**
 * EventTracker LiveView Hook
 *
 * Tracks client-side user behavior events and pushes them to the server.
 * Attach to elements with data attributes to configure tracking:
 *
 * - data-track-type: "product_view" | "article_view"
 * - data-target-id: ID of the entity being tracked
 * - data-target-type: "post" | "product" | "hub"
 *
 * Examples:
 *   <div id="event-tracker" phx-hook="EventTracker"
 *        data-track-type="product_view"
 *        data-target-id="42"
 *        data-target-type="product">
 */
export const EventTracker = {
  mounted() {
    this.viewStart = Date.now()
    this.tracked = false
    this.trackType = this.el.dataset.trackType
    this.targetId = this.el.dataset.targetId
    this.targetType = this.el.dataset.targetType

    // Track product view duration (>10s = serious interest)
    if (this.trackType === "product_view") {
      this.timer = setTimeout(() => {
        this.pushEvent("track_event", {
          type: "product_view_duration",
          target_type: this.targetType || "product",
          target_id: this.targetId,
          metadata: { duration_ms: Date.now() - this.viewStart }
        })
        this.tracked = true
      }, 10000)
    }

    // Track scroll depth for articles
    if (this.trackType === "article_view") {
      this.maxScrollDepth = 0
      this.scrollHandler = () => {
        const depth = this.getScrollDepth()
        if (depth > this.maxScrollDepth) {
          this.maxScrollDepth = depth
        }
      }
      window.addEventListener("scroll", this.scrollHandler, { passive: true })
    }
  },

  destroyed() {
    if (this.timer) clearTimeout(this.timer)
    if (this.scrollHandler) {
      window.removeEventListener("scroll", this.scrollHandler)
    }

    // Track partial reads / early exits for articles
    if (!this.tracked && this.trackType === "article_view") {
      const duration = Date.now() - this.viewStart
      if (duration > 3000) {
        // Use sendBeacon for reliable delivery on page unload
        const data = JSON.stringify({
          type: "article_read_partial",
          target_type: this.targetType || "post",
          target_id: this.targetId,
          metadata: {
            read_duration_ms: duration,
            scroll_depth_pct: this.maxScrollDepth || 0
          }
        })
        // Push via LiveView if still connected, fallback to beacon
        try {
          this.pushEvent("track_event", JSON.parse(data))
        } catch (e) {
          // LiveView might be disconnected during navigation
        }
      }
    }
  },

  getScrollDepth() {
    const scrollTop = window.scrollY
    const docHeight = document.documentElement.scrollHeight - window.innerHeight
    if (docHeight <= 0) return 100
    return Math.min(Math.round((scrollTop / docHeight) * 100), 100)
  }
}
