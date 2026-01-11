// High Rollers NFT - Time Reward Hook for Phoenix LiveView
// Provides real-time counting animation for per-NFT time reward pending amounts

/**
 * TimeRewardHook - Real-time pending time reward counter for individual NFTs
 *
 * Attach to any element displaying time reward pending amounts.
 * The element must have these data attributes:
 *   - data-rate-per-second: ROGUE earned per second (float)
 *   - data-start-time: Unix timestamp when rewards started
 *   - data-last-claim-time: Unix timestamp of last claim
 *   - data-total-claimed: Total ROGUE claimed so far (float)
 *
 * Example usage in HEEx:
 *   <div phx-hook="TimeRewardHook"
 *        id={"time-reward-#{nft.token_id}"}
 *        data-rate-per-second={nft.rate_per_second}
 *        data-start-time={nft.start_time}
 *        data-last-claim-time={nft.last_claim_time}
 *        data-total-claimed={nft.total_claimed}>
 *     <span class="pending-amount">0.00</span> ROGUE pending
 *   </div>
 *
 * CSS classes for child elements (optional):
 *   - .pending-amount: Displays current pending ROGUE
 *   - .time-remaining: Displays time remaining (e.g., "45d 12h remaining")
 *   - .progress-bar: Width set to percentage complete
 *   - .total-earned: Displays total earned since start
 */
const TimeRewardHook = {
  mounted() {
    this.initializeFromDataAttributes()
    this.startCounter()
  },

  updated() {
    // Re-initialize when server pushes new data (e.g., after claim)
    this.initializeFromDataAttributes()
  },

  destroyed() {
    this.stopCounter()
  },

  initializeFromDataAttributes() {
    this.ratePerSecond = parseFloat(this.el.dataset.ratePerSecond) || 0
    this.startTime = parseInt(this.el.dataset.startTime) || 0
    // Use lastClaimTime for pending calculation, defaults to startTime if not set or 0
    const lastClaim = parseInt(this.el.dataset.lastClaimTime) || 0
    this.lastClaimTime = lastClaim > 0 ? lastClaim : this.startTime
    this.totalClaimed = parseFloat(this.el.dataset.totalClaimed) || 0
    // Get base pending from server (for withdrawable amount tracking)
    this.basePending = parseFloat(this.el.dataset.basePending) || 0

    // 180 days duration
    this.endTime = this.startTime + (180 * 24 * 60 * 60)

    // Elements to update
    this.pendingEl = this.el.querySelector('.pending-amount')
    this.remainingEl = this.el.querySelector('.time-remaining')
    this.progressEl = this.el.querySelector('.progress-bar')
    this.totalEarnedEl = this.el.querySelector('.total-earned')
  },

  startCounter() {
    // Stop any existing interval
    this.stopCounter()

    // Only count if rewards are active
    if (this.ratePerSecond <= 0 || this.startTime === 0) {
      return
    }

    // Initial update
    this.updateDisplay()

    // Update every second
    this.interval = setInterval(() => this.updateDisplay(), 1000)
  },

  stopCounter() {
    if (this.interval) {
      clearInterval(this.interval)
      this.interval = null
    }
  },

  updateDisplay() {
    const now = Math.floor(Date.now() / 1000)

    // Cap at end time (180 days after start)
    const currentTime = Math.min(now, this.endTime)

    // Time elapsed since last claim (or start if never claimed)
    const claimTime = this.lastClaimTime || this.startTime
    const timeElapsed = Math.max(0, currentTime - claimTime)

    // Calculate pending amount
    const pending = this.ratePerSecond * timeElapsed

    // Calculate total earned since start
    const totalEarned = this.ratePerSecond * Math.max(0, currentTime - this.startTime)

    // Calculate time remaining
    const timeRemaining = Math.max(0, this.endTime - now)

    // Calculate progress percentage
    const duration = 180 * 24 * 60 * 60
    const elapsed = now - this.startTime
    const percentComplete = Math.min(100, (elapsed / duration) * 100)

    // Update DOM elements
    if (this.pendingEl) {
      this.pendingEl.textContent = this.formatRogue(pending)
    }

    if (this.totalEarnedEl) {
      this.totalEarnedEl.textContent = this.formatRogue(totalEarned)
    }

    if (this.remainingEl) {
      this.remainingEl.textContent = this.formatTimeRemaining(timeRemaining)
    }

    if (this.progressEl) {
      this.progressEl.style.width = `${percentComplete}%`
    }

    // Stop counter if rewards have ended
    if (now >= this.endTime) {
      this.stopCounter()
    }
  },

  formatRogue(amount) {
    // Format with commas, no decimal places (e.g., 618,802)
    return Math.floor(amount).toLocaleString('en-US')
  },

  formatTimeRemaining(seconds) {
    if (seconds <= 0) return 'Ended'

    const days = Math.floor(seconds / 86400)
    const hours = Math.floor((seconds % 86400) / 3600)
    const mins = Math.floor((seconds % 3600) / 60)
    const secs = seconds % 60

    // Always show days:hours:minutes:seconds format
    return `${days}d:${this.pad(hours)}h:${this.pad(mins)}m:${this.pad(secs)}s`
  },

  pad(n) {
    return n.toString().padStart(2, '0')
  }
}

export default TimeRewardHook
