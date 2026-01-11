// High Rollers NFT - Global Time Reward Hook for Phoenix LiveView
// Provides real-time counting for aggregate time reward totals on homepage

/**
 * GlobalTimeRewardHook - Real-time aggregate time reward counter for homepage
 *
 * Used on MintLive (homepage) to display total time rewards across ALL special NFTs.
 * Counts up every second using the aggregate rate from all active special NFTs.
 *
 * How it works:
 * 1. Server calculates current totals and sum of all active rates at page load
 * 2. Client receives: base_total, base_time, total_rate (sum of all special NFT rates)
 * 3. Client counts up every second: current = base_total + (total_rate × seconds_elapsed)
 * 4. On EarningsSyncer sync (every 60s), server pushes new base values to correct any drift
 *
 * Data attributes:
 *   - data-total-rate: Sum of all special NFT rates (ROGUE per second, float)
 *   - data-base-time: Unix timestamp when base values were calculated
 *   - data-base-total: Total earned at base-time (float)
 *
 * Example usage:
 *   <div phx-hook="GlobalTimeRewardHook"
 *        id="global-time-rewards"
 *        phx-update="ignore"
 *        data-total-rate={@time_reward_stats.total_rate_per_second}
 *        data-base-time={@current_time}
 *        data-base-total={@time_reward_stats.total_earned}>
 *     <span class="global-time-total">0.00</span> ROGUE
 *   </div>
 */
const GlobalTimeRewardHook = {
  mounted() {
    this.initializeFromDataAttributes()
    this.startCounter()
  },

  updated() {
    // Re-initialize when LiveView updates the element (e.g., revenue update via PubSub)
    // This allows both real-time revenue updates AND real-time time counting
    this.initializeFromDataAttributes()
    this.startCounter()
  },

  destroyed() {
    this.stopCounter()
  },

  initializeFromDataAttributes() {
    this.totalRate = parseFloat(this.el.dataset.totalRate) || 0
    this.baseTime = parseInt(this.el.dataset.baseTime) || Math.floor(Date.now() / 1000)
    this.baseTotal = parseFloat(this.el.dataset.baseTotal) || 0
    this.roguePrice = parseFloat(this.el.dataset.roguePrice) || 0

    // Elements to update (ROGUE amount and USD value)
    this.totalEl = this.el.querySelector('.global-time-total')
    this.usdEl = this.el.querySelector('.global-time-usd')
  },

  startCounter() {
    this.stopCounter()

    // Only count if there are active time rewards
    if (this.totalRate <= 0) {
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
    const elapsed = now - this.baseTime

    // Current total = base + (rate × elapsed seconds)
    // baseTotal already includes combined revenue + time rewards from server
    const currentTotal = this.baseTotal + (this.totalRate * elapsed)

    // Update ROGUE amount
    if (this.totalEl) {
      this.totalEl.textContent = this.formatRogue(currentTotal)
    }

    // Update USD value (currentTotal × roguePrice)
    if (this.usdEl && this.roguePrice > 0) {
      const usdValue = currentTotal * this.roguePrice
      this.usdEl.textContent = this.formatUsd(usdValue)
    }
  },

  formatRogue(amount) {
    // Format with commas, no decimal places (e.g., 618,802)
    return Math.floor(amount).toLocaleString('en-US')
  },

  formatUsd(amount) {
    // Format as USD with $ prefix (e.g., $1,234.56)
    return '$' + amount.toFixed(2)
  }
}

export default GlobalTimeRewardHook
