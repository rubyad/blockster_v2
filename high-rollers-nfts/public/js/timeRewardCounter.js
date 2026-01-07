/**
 * TimeRewardCounter - Efficient client-side real-time updates for time-based NFT rewards
 *
 * DESIGN PRINCIPLES:
 * - ZERO database queries at runtime - all math done client-side
 * - ZERO contract reads during normal operation
 * - Single API call on init to get static NFT data
 * - All calculations deterministic from startTime + hostessIndex + currentTime
 */
class TimeRewardCounter {
  constructor() {
    // Constants matching smart contract exactly
    this.TIME_REWARD_DURATION = 180 * 24 * 60 * 60; // 180 days in seconds (15,552,000)
    this.SPECIAL_NFT_START = 2340;
    this.SPECIAL_NFT_END = 2700;

    // Rates per second for each hostess (ROGUE, matching contract initializeV3)
    // Index 0-7 = hostess types (Penelope to Vivienne)
    this.RATES = [
      2.125029,  // Penelope (100x) - 2.125029 ROGUE/sec
      1.912007,  // Mia (90x) - 1.912007 ROGUE/sec
      1.700492,  // Cleo (80x) - 1.700492 ROGUE/sec
      1.487470,  // Sophia (70x) - 1.487470 ROGUE/sec
      1.274962,  // Luna (60x) - 1.274962 ROGUE/sec
      1.062454,  // Aurora (50x) - 1.062454 ROGUE/sec
      0.849946,  // Scarlett (40x) - 0.849946 ROGUE/sec
      0.637438,  // Vivienne (30x) - 0.637438 ROGUE/sec
    ];

    // NFT data: Map<tokenId, { hostessIndex, startTime, lastClaimTime, owner, endTime }>
    this.nfts = new Map();

    // Cached aggregates (recalculated only when NFT data changes)
    this.cache = {
      globalRate: 0,        // Sum of all active rates
      myRate: 0,            // Sum of my NFT rates
      hostessRates: new Array(8).fill(0),  // Per-hostess active rates
      lastUpdate: 0,        // Timestamp of last full recalc
    };

    this.myWallet = null;
    this.intervalId = null;
    this.initialized = false;
  }

  /**
   * Initialize with static NFT data from API
   * @param {string} myWallet - Current user's wallet address (optional)
   */
  async initialize(myWallet = null) {
    this.myWallet = myWallet?.toLowerCase();

    try {
      // Single API call - returns only static data, no calculations
      const response = await fetch(`${CONFIG.API_BASE}/revenues/time-rewards/static-data`);
      if (!response.ok) {
        console.warn('[TimeRewardCounter] Failed to fetch static data:', response.status);
        return;
      }

      const nftData = await response.json();

      this.nfts.clear();
      const now = Math.floor(Date.now() / 1000);

      for (const nft of nftData) {
        // Skip if not started
        if (!nft.startTime) continue;

        const endTime = nft.startTime + this.TIME_REWARD_DURATION;

        // Skip if already ended
        if (now >= endTime) continue;

        this.nfts.set(nft.tokenId, {
          hostessIndex: nft.hostessIndex,
          startTime: nft.startTime,
          lastClaimTime: nft.lastClaimTime || nft.startTime,
          owner: nft.owner?.toLowerCase(),
          endTime: endTime,
        });
      }

      // Calculate aggregate rates (once)
      this.recalculateCache();
      this.initialized = true;

      // Update APY (depends on prices, so may need to wait for price service)
      this.updateAPY();

      console.log(`[TimeRewardCounter] Initialized: ${this.nfts.size} active NFTs, global rate: ${this.cache.globalRate.toFixed(3)}/sec`);
    } catch (error) {
      console.error('[TimeRewardCounter] Initialization error:', error);
    }
  }

  /**
   * Recalculate cached aggregates (only on data change, not every tick)
   */
  recalculateCache() {
    this.cache.globalRate = 0;
    this.cache.myRate = 0;
    this.cache.hostessRates = new Array(8).fill(0);

    const now = Math.floor(Date.now() / 1000);

    for (const [tokenId, data] of this.nfts) {
      // Skip ended NFTs
      if (now >= data.endTime) continue;

      const rate = this.RATES[data.hostessIndex];
      this.cache.globalRate += rate;
      this.cache.hostessRates[data.hostessIndex] += rate;

      if (this.myWallet && data.owner === this.myWallet) {
        this.cache.myRate += rate;
      }
    }

    this.cache.lastUpdate = now;
  }

  /**
   * Calculate pending for a single NFT (pure math, no queries)
   * @param {number} tokenId
   * @returns {number} Pending amount in ROGUE
   */
  getPending(tokenId) {
    const data = this.nfts.get(tokenId);
    if (!data) return 0;

    const now = Math.floor(Date.now() / 1000);
    const effectiveNow = Math.min(now, data.endTime);
    const elapsed = Math.max(0, effectiveNow - data.lastClaimTime);

    return elapsed * this.RATES[data.hostessIndex];
  }

  /**
   * Calculate all pending totals (pure math, no queries)
   * @returns {Object} { globalPending, myPending, hostessPending[] }
   */
  getTotals() {
    const now = Math.floor(Date.now() / 1000);
    let globalPending = 0;
    let myPending = 0;
    const hostessPending = new Array(8).fill(0);

    for (const [tokenId, data] of this.nfts) {
      const effectiveNow = Math.min(now, data.endTime);
      const elapsed = Math.max(0, effectiveNow - data.lastClaimTime);
      const pending = elapsed * this.RATES[data.hostessIndex];

      globalPending += pending;
      hostessPending[data.hostessIndex] += pending;

      if (this.myWallet && data.owner === this.myWallet) {
        myPending += pending;
      }
    }

    return { globalPending, myPending, hostessPending };
  }

  /**
   * Get 24h earnings - handles edge cases accurately
   *
   * Formula: 24h = rate * (min(endTime, now) - max(startTime, oneDayAgo))
   * Clamped to 0 if result is negative
   *
   * @returns {Object} { global, my, hostess[] }
   */
  get24hEarnings() {
    const now = Math.floor(Date.now() / 1000);
    const oneDayAgo = now - 86400;

    let global24h = 0;
    let my24h = 0;
    const hostess24h = new Array(8).fill(0);

    for (const [tokenId, data] of this.nfts) {
      const rate = this.RATES[data.hostessIndex];

      // Calculate the overlap between [startTime, endTime] and [oneDayAgo, now]
      const windowStart = Math.max(data.startTime, oneDayAgo);
      const windowEnd = Math.min(data.endTime, now);

      let nft24h = 0;
      if (windowEnd > windowStart) {
        // NFT was active for this many seconds in the last 24 hours
        nft24h = rate * (windowEnd - windowStart);
      }

      global24h += nft24h;
      hostess24h[data.hostessIndex] += nft24h;

      if (this.myWallet && data.owner === this.myWallet) {
        my24h += nft24h;
      }
    }

    return { global: global24h, my: my24h, hostess: hostess24h };
  }

  /**
   * Get global total earned from all time rewards (since start, not just pending)
   * @param {number} now - Current Unix timestamp
   * @returns {number} Total ROGUE earned from time rewards
   */
  getGlobalTotalEarned(now) {
    let totalEarned = 0;

    for (const [tokenId, data] of this.nfts) {
      const effectiveNow = Math.min(now, data.endTime);
      const elapsed = Math.max(0, effectiveNow - data.startTime);
      totalEarned += elapsed * this.RATES[data.hostessIndex];
    }

    return totalEarned;
  }

  /**
   * Update Mint Tab stats boxes with combined values (revenue + time rewards)
   * Reads revenue values from data attributes, adds time rewards in real-time
   * @param {number} globalTimeTotal - Global time rewards total earned
   * @param {number} global24h - Global time rewards earned in last 24h
   */
  updateMintTabStats(globalTimeTotal, global24h) {
    const roguePrice = window.revenueService?.priceService?.roguePrice || 0;

    // Total Rewards Received = revenue total + time rewards total
    const totalEl = document.getElementById('mint-total-rewards');
    const totalUsdEl = document.getElementById('mint-total-rewards-usd');
    if (totalEl && totalEl.dataset.revenueTotal !== undefined) {
      const revenueTotal = parseFloat(totalEl.dataset.revenueTotal || 0);
      const combinedTotal = revenueTotal + globalTimeTotal;
      // No decimal places for mint tab boxes
      totalEl.innerHTML = `${Math.floor(combinedTotal).toLocaleString('en-US')} <span class="text-sm text-gray-400 font-normal">ROGUE</span>`;
      if (totalUsdEl) {
        totalUsdEl.textContent = this.formatUSD(combinedTotal, roguePrice);
      }
    }

    // Last 24 Hours = revenue 24h + time rewards 24h
    const last24hEl = document.getElementById('mint-last-24h-rewards');
    const last24hUsdEl = document.getElementById('mint-last-24h-rewards-usd');
    if (last24hEl && last24hEl.dataset.revenue24h !== undefined) {
      const revenue24h = parseFloat(last24hEl.dataset.revenue24h || 0);
      const combined24h = revenue24h + global24h;
      // No decimal places for mint tab boxes
      last24hEl.innerHTML = `${Math.floor(combined24h).toLocaleString('en-US')} <span class="text-sm text-gray-400 font-normal">ROGUE</span>`;
      if (last24hUsdEl) {
        last24hUsdEl.textContent = this.formatUSD(combined24h, roguePrice);
      }
    }

  }

  /**
   * Calculate APY for special NFTs based on time rewards
   * APY = (average 180d earnings / NFT cost in ROGUE) * (365/180) * 100
   */
  calculateSpecialNFTsAPY() {
    const nftValueInRogue = window.revenueService?.priceService?.getNftValueInRogue() || 0;
    if (nftValueInRogue === 0 || this.nfts.size === 0) return 0;

    // Calculate average 180-day earnings across all active special NFTs
    // Each NFT earns: rate * TIME_REWARD_DURATION ROGUE over 180 days
    let totalEarningsFor180Days = 0;
    let activeNftCount = 0;

    for (const [tokenId, data] of this.nfts) {
      const rate = this.RATES[data.hostessIndex];
      totalEarningsFor180Days += rate * this.TIME_REWARD_DURATION;
      activeNftCount++;
    }

    if (activeNftCount === 0) return 0;

    const avgEarningsFor180Days = totalEarningsFor180Days / activeNftCount;

    // APY = (180d earnings / cost) * (365/180) * 100
    const apy = (avgEarningsFor180Days / nftValueInRogue) * (365 / 180) * 100;
    return apy;
  }

  /**
   * Update the APY display on Mint tab
   * Called on init and when prices change (not every second)
   */
  updateAPY() {
    const apyEl = document.getElementById('mint-overall-apy');
    if (apyEl) {
      const apy = this.calculateSpecialNFTsAPY();
      apyEl.textContent = `${apy.toFixed(2)}%`;
    }
  }

  /**
   * Calculate APY for user's special NFTs only
   * @returns {number} APY percentage for user's special NFTs
   */
  calculateMySpecialNFTsAPY() {
    if (!this.myWallet) return 0;

    const nftValueInRogue = window.revenueService?.priceService?.getNftValueInRogue() || 0;
    if (nftValueInRogue === 0) return 0;

    let totalEarningsFor180Days = 0;
    let myNftCount = 0;

    for (const [tokenId, data] of this.nfts) {
      if (data.owner === this.myWallet) {
        const rate = this.RATES[data.hostessIndex];
        totalEarningsFor180Days += rate * this.TIME_REWARD_DURATION;
        myNftCount++;
      }
    }

    if (myNftCount === 0) return 0;

    const avgEarningsFor180Days = totalEarningsFor180Days / myNftCount;
    const apy = (avgEarningsFor180Days / nftValueInRogue) * (365 / 180) * 100;
    return apy;
  }

  /**
   * Update My Special NFTs APY display
   */
  updateMySpecialNFTsAPY() {
    const apyEl = document.getElementById('my-special-nfts-apy');
    if (apyEl) {
      const apy = this.calculateMySpecialNFTsAPY();
      apyEl.textContent = `${apy.toFixed(2)}%`;
    }
  }

  /**
   * Get user's special NFTs with time reward data
   * @returns {Array} Array of NFT data with calculated time rewards
   */
  getMyNFTsWithTimeRewards() {
    if (!this.myWallet) return [];

    const results = [];
    const now = Math.floor(Date.now() / 1000);
    const oneDayAgo = now - 86400;

    for (const [tokenId, data] of this.nfts) {
      if (data.owner !== this.myWallet) continue;

      const effectiveNow = Math.min(now, data.endTime);
      const elapsed = Math.max(0, effectiveNow - data.lastClaimTime);
      const pending = elapsed * this.RATES[data.hostessIndex];
      const timeRemaining = Math.max(0, data.endTime - now);
      const totalFor180Days = this.RATES[data.hostessIndex] * this.TIME_REWARD_DURATION;

      // Total earned since start
      const totalEarned = Math.max(0, effectiveNow - data.startTime) * this.RATES[data.hostessIndex];

      // 24h earnings (overlap between [startTime, endTime] and [oneDayAgo, now])
      const windowStart = Math.max(data.startTime, oneDayAgo);
      const windowEnd = Math.min(data.endTime, now);
      const last24h = windowEnd > windowStart ? (windowEnd - windowStart) * this.RATES[data.hostessIndex] : 0;

      results.push({
        tokenId,
        hostessIndex: data.hostessIndex,
        hasStarted: true,
        pending,
        last24h,
        totalEarned,
        ratePerSecond: this.RATES[data.hostessIndex],
        timeRemaining,
        totalFor180Days,
        startTime: data.startTime,
        endTime: data.endTime,
      });
    }

    return results;
  }

  /**
   * Start 1-second UI update loop
   */
  start() {
    if (this.intervalId) return;

    this.intervalId = setInterval(() => {
      this.updateUI();
    }, 1000);

    // Initial update
    this.updateUI();
  }

  /**
   * Stop the update loop
   */
  stop() {
    if (this.intervalId) {
      clearInterval(this.intervalId);
      this.intervalId = null;
    }
  }

  /**
   * Update all UI elements (no queries, just display cached/calculated values)
   */
  updateUI() {
    if (!this.initialized) return;

    const now = Math.floor(Date.now() / 1000);
    const totals = this.getTotals();
    const earnings24h = this.get24hEarnings();
    const globalTotalEarned = this.getGlobalTotalEarned(now);

    // ---- Mint Tab Stats Boxes (combined revenue + time rewards) ----
    this.updateMintTabStats(globalTotalEarned, earnings24h.global);

    // ---- Global Stats (Mint Tab, Revenues Tab) ----
    this.updateElement('global-time-rewards-pending', totals.globalPending);
    this.updateElement('global-time-rewards-24h', earnings24h.global);

    // ---- My Earnings ----
    this.updateElement('my-time-rewards-pending', totals.myPending);
    this.updateElement('my-time-rewards-24h', earnings24h.my);

    // ---- My Earnings Top Stats Boxes (Revenues Tab) ----
    // Combine revenue sharing + time rewards for users with special NFTs
    // Always call if user has wallet connected and owns special NFTs
    if (this.myWallet && this.hasMySpecialNFTs()) {
      this.updateMyEarningsStats(totals, earnings24h);
      this.updateSpecialNFTsSection(totals, earnings24h, now);
    }

    // ---- Per-NFT Cards (My NFTs Tab) ----
    // Pending
    document.querySelectorAll('[data-time-reward-token]').forEach(el => {
      const tokenId = parseInt(el.dataset.timeRewardToken);
      const pending = this.getPending(tokenId);
      el.innerHTML = `${this.formatROGUE(pending)} <span class="text-xs text-gray-500 font-normal">ROGUE</span>`;
    });

    // Total earned (since start)
    document.querySelectorAll('[data-time-reward-total]').forEach(el => {
      const tokenId = parseInt(el.dataset.timeRewardTotal);
      const data = this.nfts.get(tokenId);
      if (data) {
        const effectiveNow = Math.min(now, data.endTime);
        const totalEarned = Math.max(0, effectiveNow - data.startTime) * this.RATES[data.hostessIndex];
        el.innerHTML = `${this.formatROGUE(totalEarned)} <span class="text-xs text-gray-500 font-normal">ROGUE</span>`;
      }
    });

    // ---- Countdown Timers ----
    document.querySelectorAll('[data-time-remaining-token]').forEach(el => {
      const tokenId = parseInt(el.dataset.timeRemainingToken);
      const data = this.nfts.get(tokenId);
      if (data) {
        const remaining = Math.max(0, data.endTime - now);
        el.textContent = this.formatTimeRemaining(remaining);
      }
    });

    // ---- Per-Hostess (Gallery/Stats) ----
    for (let i = 0; i < 8; i++) {
      this.updateElement(`hostess-${i}-time-24h`, earnings24h.hostess[i]);
      this.updateElement(`hostess-${i}-time-pending`, totals.hostessPending[i]);
    }

    // ---- Earnings Table (Revenues Tab) - combine revenue sharing + time rewards ----
    this.updateEarningsTable(now);
  }

  /**
   * Update the My Earnings top stats boxes with combined values
   * Reads revenue values from data attributes, adds time rewards
   * Also updates USD values using cached ROGUE price (no API calls)
   */
  updateMyEarningsStats(totals, earnings24h) {
    const now = Math.floor(Date.now() / 1000);
    // Get cached ROGUE price from priceService (no API call - just reads cached value)
    const roguePrice = window.revenueService?.priceService?.roguePrice || 0;

    // Total Earned = revenue total + time rewards total earned (from start)
    const totalEarnedEl = document.getElementById('my-total-earned');
    const totalEarnedUsdEl = document.getElementById('my-total-earned-usd');
    if (totalEarnedEl) {
      const revenueTotal = parseFloat(totalEarnedEl.dataset.revenueTotal || 0);
      // Calculate total time rewards earned (from startTime, not lastClaimTime)
      let myTimeTotal = 0;
      for (const [tokenId, data] of this.nfts) {
        if (this.myWallet && data.owner === this.myWallet) {
          const effectiveNow = Math.min(now, data.endTime);
          myTimeTotal += Math.max(0, effectiveNow - data.startTime) * this.RATES[data.hostessIndex];
        }
      }
      const combinedTotal = revenueTotal + myTimeTotal;
      totalEarnedEl.innerHTML = `${this.formatROGUE(combinedTotal)} <span class="text-sm text-gray-400 font-normal">ROGUE</span>`;
      if (totalEarnedUsdEl) {
        totalEarnedUsdEl.textContent = this.formatUSD(combinedTotal, roguePrice);
      }
    }

    // Pending = revenue pending + time rewards pending (from lastClaimTime)
    const pendingEl = document.getElementById('my-pending');
    const pendingUsdEl = document.getElementById('my-pending-usd');
    if (pendingEl) {
      const revenuePending = parseFloat(pendingEl.dataset.revenuePending || 0);
      const combinedPending = revenuePending + totals.myPending;
      pendingEl.innerHTML = `${this.formatROGUE(combinedPending)} <span class="text-sm text-gray-400 font-normal">ROGUE</span>`;
      if (pendingUsdEl) {
        pendingUsdEl.textContent = this.formatUSD(combinedPending, roguePrice);
      }
    }

    // Last 24h = revenue 24h + time rewards 24h
    const last24hEl = document.getElementById('my-last-24h');
    const last24hUsdEl = document.getElementById('my-last-24h-usd');
    if (last24hEl) {
      const revenue24h = parseFloat(last24hEl.dataset.revenue24h || 0);
      const combined24h = revenue24h + earnings24h.my;
      last24hEl.innerHTML = `${this.formatROGUE(combined24h)} <span class="text-sm text-gray-400 font-normal">ROGUE</span>`;
      if (last24hUsdEl) {
        last24hUsdEl.textContent = this.formatUSD(combined24h, roguePrice);
      }
    }
  }

  /**
   * Update the Special NFTs section on My Earnings tab
   * Shows time-based rewards stats with USD values
   */
  updateSpecialNFTsSection(totals, earnings24h, now) {
    const roguePrice = window.revenueService?.priceService?.roguePrice || 0;

    // Calculate my total time rewards earned (from startTime)
    let myTimeTotal = 0;
    let myTotal180d = 0;
    let myNftCount = 0;
    for (const [tokenId, data] of this.nfts) {
      if (this.myWallet && data.owner === this.myWallet) {
        const effectiveNow = Math.min(now, data.endTime);
        myTimeTotal += Math.max(0, effectiveNow - data.startTime) * this.RATES[data.hostessIndex];
        myTotal180d += this.RATES[data.hostessIndex] * this.TIME_REWARD_DURATION;
        myNftCount++;
      }
    }

    // Total Earned (no decimals for special NFTs section)
    const totalEl = document.getElementById('my-time-rewards-total');
    const totalUsdEl = document.getElementById('my-time-rewards-total-usd');
    if (totalEl) {
      totalEl.innerHTML = `${Math.floor(myTimeTotal).toLocaleString('en-US')} <span class="text-sm text-gray-400 font-normal">ROGUE</span>`;
      if (totalUsdEl) {
        totalUsdEl.textContent = this.formatUSD(myTimeTotal, roguePrice);
      }
    }

    // Pending (no decimals for special NFTs section)
    const pendingEl = document.getElementById('my-time-rewards-pending');
    const pendingUsdEl = document.getElementById('my-time-rewards-pending-usd');
    if (pendingEl) {
      pendingEl.innerHTML = `${Math.floor(totals.myPending).toLocaleString('en-US')} <span class="text-sm text-gray-400 font-normal">ROGUE</span>`;
      if (pendingUsdEl) {
        pendingUsdEl.textContent = this.formatUSD(totals.myPending, roguePrice);
      }
    }

    // 24h (no decimals for special NFTs section)
    const h24El = document.getElementById('my-time-rewards-24h');
    const h24UsdEl = document.getElementById('my-time-rewards-24h-usd');
    if (h24El) {
      h24El.innerHTML = `${Math.floor(earnings24h.my).toLocaleString('en-US')} <span class="text-sm text-gray-400 font-normal">ROGUE</span>`;
      if (h24UsdEl) {
        h24UsdEl.textContent = this.formatUSD(earnings24h.my, roguePrice);
      }
    }

    // 180d Total (no decimals for special NFTs section)
    const total180dEl = document.getElementById('special-nfts-180d');
    const total180dUsdEl = document.getElementById('special-nfts-180d-usd');
    if (total180dEl) {
      total180dEl.innerHTML = `${Math.floor(myTotal180d).toLocaleString('en-US')} <span class="text-sm text-gray-400 font-normal">ROGUE</span>`;
      if (total180dUsdEl) {
        total180dUsdEl.textContent = this.formatUSD(myTotal180d, roguePrice);
      }
    }

    // NFT Count
    const countEl = document.getElementById('special-nfts-count');
    if (countEl) {
      countEl.textContent = myNftCount;
    }
  }

  /**
   * Update the Earnings by NFT table for special NFTs
   * Combines revenue sharing earnings with time-based rewards
   * Also updates USD values using cached ROGUE price
   */
  updateEarningsTable(now) {
    const oneDayAgo = now - 86400;
    // Get cached ROGUE price from priceService (no API call - just reads cached value)
    const roguePrice = window.revenueService?.priceService?.roguePrice || 0;

    // Update Total Earned column (revenue + time rewards total earned)
    document.querySelectorAll('[data-table-total-earned]').forEach(el => {
      const tokenId = parseInt(el.dataset.tableTotalEarned);
      const data = this.nfts.get(tokenId);
      if (!data) return;

      const revenueTotal = parseFloat(el.dataset.revenueTotal || 0);
      // Time rewards "total earned" = everything earned since start (not just pending)
      const effectiveNow = Math.min(now, data.endTime);
      const timeTotal = Math.max(0, effectiveNow - data.startTime) * this.RATES[data.hostessIndex];
      const combinedTotal = revenueTotal + timeTotal;
      el.textContent = this.formatROGUE(combinedTotal);

      // Update USD value - el is inside <a>, USD span is sibling of <a> in <td>
      const tdEl = el.closest('td');
      const usdEl = tdEl?.querySelector('.text-gray-500.text-xs');
      if (usdEl && roguePrice) {
        usdEl.textContent = this.formatUSD(combinedTotal, roguePrice);
      }
    });

    // Update Pending column (revenue pending + time rewards pending since last claim)
    document.querySelectorAll('[data-table-pending]').forEach(el => {
      const tokenId = parseInt(el.dataset.tablePending);
      const data = this.nfts.get(tokenId);
      if (!data) return; // Skip non-special NFTs

      const timePending = this.getPending(tokenId);
      const revenuePending = parseFloat(el.dataset.revenuePending || 0);
      const combinedPending = revenuePending + timePending;
      el.textContent = this.formatROGUE(combinedPending);

      // Update USD value - el is inside <a>, USD span is sibling of <a> in <td>
      const tdEl = el.closest('td');
      const usdEl = tdEl?.querySelector('.text-gray-500.text-xs');
      if (usdEl && roguePrice) {
        usdEl.textContent = this.formatUSD(combinedPending, roguePrice);
      }
    });

    // Update 24h column (revenue 24h + time rewards 24h)
    document.querySelectorAll('[data-table-24h]').forEach(el => {
      const tokenId = parseInt(el.getAttribute('data-table-24h'));
      const data = this.nfts.get(tokenId);
      if (!data) return; // Skip non-special NFTs

      const revenue24h = parseFloat(el.dataset.revenue24h || 0);
      // Calculate time rewards earned in last 24 hours
      const windowStart = Math.max(data.startTime, oneDayAgo);
      const windowEnd = Math.min(data.endTime, now);
      const time24h = windowEnd > windowStart ? (windowEnd - windowStart) * this.RATES[data.hostessIndex] : 0;
      const combined24h = revenue24h + time24h;
      el.textContent = this.formatROGUE(combined24h);

      // Update USD value - find the sibling USD element in <td>
      const tdEl = el.closest('td');
      const usdEl = tdEl?.querySelector('.text-gray-500.text-xs');
      if (usdEl && roguePrice) {
        usdEl.textContent = this.formatUSD(combined24h, roguePrice);
      }
    });
  }

  /**
   * Update a single element by ID with formatted ROGUE value
   */
  updateElement(id, value) {
    const el = document.getElementById(id);
    if (el) el.innerHTML = `${this.formatROGUE(value)} <span class="text-sm text-gray-400 font-normal">ROGUE</span>`;
  }

  /**
   * Format ROGUE amount with comma delimiters (full number, no abbreviation)
   */
  formatROGUE(amount) {
    if (!amount || amount === 0) return '0';
    // Format with 2 decimal places and comma separators
    return amount.toLocaleString('en-US', {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2
    });
  }

  /**
   * Format USD amount using cached ROGUE price (no API call)
   * @param {number} rogueAmount - Amount in ROGUE
   * @param {number} roguePrice - Cached ROGUE price in USD
   * @returns {string} Formatted USD string with comma separators
   */
  formatUSD(rogueAmount, roguePrice) {
    if (!roguePrice || rogueAmount === 0 || isNaN(rogueAmount)) return '$0.00';
    const usd = rogueAmount * roguePrice;
    // Format with 2 decimal places and comma separators
    return '$' + usd.toLocaleString('en-US', {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2
    });
  }

  /**
   * Format time remaining (days/hours/minutes)
   */
  formatTimeRemaining(seconds) {
    if (!seconds || seconds <= 0) return 'Ended';
    const days = Math.floor(seconds / 86400);
    const hours = Math.floor((seconds % 86400) / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);
    const secs = Math.floor(seconds % 60);

    const pad = (n) => n.toString().padStart(2, '0');
    return `${days}d:${pad(hours)}h:${pad(minutes)}m:${pad(secs)}s`;
  }

  /**
   * Called after successful claim - update local state (no API call)
   * @param {Array} tokenIds - Array of token IDs that were claimed
   */
  onClaimed(tokenIds) {
    const now = Math.floor(Date.now() / 1000);
    for (const tokenId of tokenIds) {
      const data = this.nfts.get(tokenId);
      if (data) {
        data.lastClaimTime = now;
      }
    }
    // No need to recalculate cache - rates don't change on claim
  }

  /**
   * Called when new special NFT is registered (WebSocket event)
   * @param {Object} nft - { tokenId, hostessIndex, startTime, owner }
   */
  onNewNFT(nft) {
    const endTime = nft.startTime + this.TIME_REWARD_DURATION;

    this.nfts.set(nft.tokenId, {
      hostessIndex: nft.hostessIndex,
      startTime: nft.startTime,
      lastClaimTime: nft.startTime,
      owner: nft.owner?.toLowerCase(),
      endTime: endTime,
    });

    // Recalculate cache since rates changed
    this.recalculateCache();
  }

  /**
   * Called when wallet connects/disconnects
   * @param {string} wallet - Wallet address or null
   */
  setMyWallet(wallet) {
    this.myWallet = wallet?.toLowerCase();
    this.recalculateCache();
  }

  /**
   * Check if a token ID is a special NFT
   * @param {number} tokenId
   * @returns {boolean}
   */
  isSpecialNFT(tokenId) {
    return tokenId >= this.SPECIAL_NFT_START && tokenId <= this.SPECIAL_NFT_END;
  }

  /**
   * Check if the connected wallet owns any special NFTs
   * @returns {boolean}
   */
  hasMySpecialNFTs() {
    if (!this.myWallet) return false;
    for (const [_tokenId, data] of this.nfts) {
      if (data.owner === this.myWallet) {
        return true;
      }
    }
    return false;
  }
}

// Global instance
window.timeRewardCounter = new TimeRewardCounter();
