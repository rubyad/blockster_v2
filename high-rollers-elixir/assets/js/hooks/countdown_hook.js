// High Rollers NFT - Countdown Hook for Phoenix LiveView
// Provides real-time countdown timer for time-based rewards remaining time

/**
 * CountdownHook - Real-time countdown timer
 *
 * Used on MyNftsLive to display countdown for special NFT time rewards.
 * Counts down every second from the initial time remaining.
 *
 * Data attributes:
 *   - data-seconds-remaining: Initial seconds remaining (integer)
 *
 * Example usage:
 *   <span phx-hook="CountdownHook"
 *         id="countdown-2340"
 *         data-seconds-remaining={@nft.time_reward.time_remaining}>
 *     175d:12h:34m:56s
 *   </span>
 */
const CountdownHook = {
  mounted() {
    this.initializeFromDataAttributes()
    this.startCountdown()
  },

  updated() {
    // Re-initialize when LiveView updates the element
    this.initializeFromDataAttributes()
    this.startCountdown()
  },

  destroyed() {
    this.stopCountdown()
  },

  initializeFromDataAttributes() {
    this.secondsRemaining = parseInt(this.el.dataset.secondsRemaining) || 0
    this.startTime = Math.floor(Date.now() / 1000)
  },

  startCountdown() {
    this.stopCountdown()

    // Only count if there's time remaining
    if (this.secondsRemaining <= 0) {
      this.el.textContent = 'Ended'
      return
    }

    // Initial update
    this.updateDisplay()

    // Update every second
    this.interval = setInterval(() => this.updateDisplay(), 1000)
  },

  stopCountdown() {
    if (this.interval) {
      clearInterval(this.interval)
      this.interval = null
    }
  },

  updateDisplay() {
    const now = Math.floor(Date.now() / 1000)
    const elapsed = now - this.startTime
    const remaining = Math.max(0, this.secondsRemaining - elapsed)

    if (remaining <= 0) {
      this.el.textContent = 'Ended'
      this.stopCountdown()
      return
    }

    this.el.textContent = this.formatTime(remaining)
  },

  formatTime(seconds) {
    const days = Math.floor(seconds / 86400)
    const hours = Math.floor((seconds % 86400) / 3600)
    const minutes = Math.floor((seconds % 3600) / 60)
    const secs = seconds % 60

    return `${days}d:${this.pad(hours)}h:${this.pad(minutes)}m:${this.pad(secs)}s`
  },

  pad(n) {
    return n.toString().padStart(2, '0')
  }
}

export default CountdownHook
