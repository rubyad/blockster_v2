// High Rollers NFT - Global Time Reward 24h Hook for Phoenix LiveView
// Provides real-time counting for the "Time Rewards 24h" stat on homepage

/**
 * GlobalTimeReward24hHook - Real-time 24h time reward counter for homepage
 *
 * Similar to GlobalTimeRewardHook but for 24h earnings display.
 * Uses a simplified counting model that gets corrected every 60s by server sync.
 *
 * Simplification: We approximate by just adding rate × elapsed. The 60-second sync
 * from EarningsSyncer corrects for the "falling off" effect (old earnings leaving
 * the 24h window). This gives smooth counting without complex client-side calculations.
 *
 * Data attributes:
 *   - data-total-rate: Sum of all special NFT rates (ROGUE per second, float)
 *   - data-base-time: Unix timestamp when base values were calculated
 *   - data-base-24h: 24h earnings at base-time (float)
 *
 * Example usage:
 *   <div phx-hook="GlobalTimeReward24hHook"
 *        id="global-time-rewards-24h"
 *        phx-update="ignore"
 *        data-total-rate={@time_reward_stats.total_rate_per_second}
 *        data-base-time={@current_time}
 *        data-base-24h={@time_reward_stats.earned_last_24h}>
 *     <span class="global-time-24h">0.00</span> ROGUE
 *   </div>
 */
const GlobalTimeReward24hHook = {
  mounted() {
    this.initializeFromDataAttributes()
    this.startCounter()
  },

  destroyed() {
    this.stopCounter()
  },

  initializeFromDataAttributes() {
    this.totalRate = parseFloat(this.el.dataset.totalRate) || 0
    this.baseTime = parseInt(this.el.dataset.baseTime) || Math.floor(Date.now() / 1000)
    this.base24h = parseFloat(this.el.dataset.base24h) || 0

    this.h24El = this.el.querySelector('.global-time-24h')
  },

  startCounter() {
    this.stopCounter()

    if (this.totalRate <= 0) {
      return
    }

    this.updateDisplay()
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

    // Approximate: 24h value + rate × elapsed
    // Server corrects every 60s for earnings that "fall off" the 24h window
    const current24h = this.base24h + (this.totalRate * elapsed)

    if (this.h24El) {
      this.h24El.textContent = this.formatRogue(current24h)
    }
  },

  formatRogue(amount) {
    if (amount >= 1000000) {
      return (amount / 1000000).toFixed(2) + 'M'
    } else if (amount >= 1000) {
      return (amount / 1000).toFixed(2) + 'K'
    } else {
      return amount.toFixed(2)
    }
  }
}

export default GlobalTimeReward24hHook
