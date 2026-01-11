// High Rollers NFT - Infinite Scroll Hook for Phoenix LiveView
// Uses IntersectionObserver for efficient pagination triggers

/**
 * InfiniteScrollHook - Triggers load_more events when sentinel comes into view
 *
 * Attach to a container with a sentinel element at the bottom:
 *   <div phx-hook="InfiniteScrollHook" id="sales-scroll-container">
 *     <div id="sales-list">... items ...</div>
 *     <div id="sales-sentinel" data-page={@page}></div>
 *   </div>
 *
 * The hook observes the sentinel element. When it becomes visible,
 * it pushes a "load_more" event to LiveView.
 *
 * Data attributes:
 *   - data-page: Current page number (optional, for debugging)
 *   - data-loading: Set to "true" when loading to prevent duplicate requests
 *   - data-end: Set to "true" when no more items to load
 *
 * Events pushed TO LiveView:
 *   - load_more: {}
 */
const InfiniteScrollHook = {
  mounted() {
    this.observer = null
    this.sentinel = null
    this.loading = false
    this.setupObserver()
  },

  updated() {
    // Re-observe after LiveView updates the DOM
    this.loading = false
    this.reobserveSentinel()
  },

  destroyed() {
    if (this.observer) {
      this.observer.disconnect()
    }
  },

  setupObserver() {
    // Check if element is scrollable container or uses window scroll
    const hasOverflow = this.el.scrollHeight > this.el.clientHeight
    const overflowStyle = getComputedStyle(this.el).overflowY
    const isScrollable = overflowStyle === 'auto' || overflowStyle === 'scroll'
    this.useElementScroll = hasOverflow && isScrollable

    // Create IntersectionObserver
    this.observer = new IntersectionObserver(
      (entries) => {
        entries.forEach(entry => {
          if (entry.isIntersecting && !this.loading && !this.isEndReached()) {
            this.loadMore()
          }
        })
      },
      {
        root: this.useElementScroll ? this.el : null, // Element scroll vs window scroll
        rootMargin: '200px', // Load before sentinel is fully visible
        threshold: 0
      }
    )

    this.observeSentinel()
  },

  observeSentinel() {
    // Find sentinel element (element with id ending in -sentinel or class .infinite-scroll-sentinel)
    this.sentinel = this.el.querySelector('[id$="-sentinel"], .infinite-scroll-sentinel')

    if (this.sentinel) {
      this.observer.observe(this.sentinel)
    }
  },

  reobserveSentinel() {
    if (this.observer && this.sentinel) {
      this.observer.unobserve(this.sentinel)
    }
    this.observeSentinel()
  },

  isEndReached() {
    // Check if we've reached the end (no more items to load)
    return this.el.dataset.end === 'true' ||
           this.sentinel?.dataset.end === 'true'
  },

  loadMore() {
    if (this.loading || this.isEndReached()) return

    this.loading = true
    // Get custom event name from data-event attribute, default to "load_more"
    const eventName = this.el.dataset.event || "load_more"
    console.log(`[InfiniteScrollHook] Loading more (event: ${eventName})...`)

    this.pushEvent(eventName, {})
  }
}

export default InfiniteScrollHook
