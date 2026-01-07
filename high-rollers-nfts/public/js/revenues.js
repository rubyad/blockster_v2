// High Rollers NFT - Revenue Sharing Service

/**
 * PriceService - Handles ROGUE/USD price caching and formatting
 */
class PriceService {
  constructor() {
    this.roguePrice = 0;
    this.rogueUsd24hChange = 0;
    this.ethPrice = 0;
    this.ethUsd24hChange = 0;
    this.lastUpdated = 0;
  }

  /**
   * Update prices from WebSocket or API response
   */
  updatePrices(data) {
    if (data.rogue) {
      this.roguePrice = data.rogue.usdPrice || 0;
      this.rogueUsd24hChange = data.rogue.usd24hChange || 0;
    }
    if (data.eth) {
      this.ethPrice = data.eth.usdPrice || 0;
      this.ethUsd24hChange = data.eth.usd24hChange || 0;
    }
    this.lastUpdated = data.lastUpdated || Date.now();
  }

  /**
   * Format ROGUE amount to USD string
   * @param {number|string} rogueAmount - Amount in ROGUE
   * @returns {string} Formatted USD string (e.g., "$1.23", "$1.2k", "$1.2M")
   */
  formatUsd(rogueAmount) {
    const amount = typeof rogueAmount === 'string' ? parseFloat(rogueAmount) : rogueAmount;
    if (!this.roguePrice || amount === 0 || isNaN(amount)) return '$0.00';

    const usd = amount * this.roguePrice;

    if (usd >= 1_000_000) {
      return `$${(usd / 1_000_000).toFixed(2)}M`;
    } else if (usd >= 1_000) {
      return `$${(usd / 1_000).toFixed(2)}k`;
    } else if (usd >= 0.01) {
      return `$${usd.toFixed(2)}`;
    } else if (usd > 0) {
      return '<$0.01';
    }
    return '$0.00';
  }

  /**
   * Get NFT value in ROGUE based on 0.32 ETH mint price
   */
  getNftValueInRogue() {
    if (!this.ethPrice || !this.roguePrice) return 0;
    const nftValueUsd = 0.32 * this.ethPrice;
    return nftValueUsd / this.roguePrice;
  }
}

/**
 * RevenueService - Handles revenue data fetching and rendering
 */
class RevenueService {
  constructor() {
    this.priceService = new PriceService();
    this.globalStats = null;
    this.userEarnings = null;
    this.rewardHistory = [];
    this.isWithdrawing = false;
    this.lastWithdrawTxHash = null;
  }

  /**
   * Initialize the service - fetch prices and initial data
   */
  async init() {
    await this.fetchPrices();
  }

  /**
   * Fetch current ROGUE and ETH prices
   */
  async fetchPrices() {
    try {
      const response = await fetch(`${CONFIG.API_BASE}/revenues/prices`);
      if (response.ok) {
        const data = await response.json();
        this.priceService.updatePrices(data);
        console.log('[Revenues] Prices updated:', this.priceService.roguePrice, 'ROGUE/USD');
      }
    } catch (error) {
      console.error('[Revenues] Failed to fetch prices:', error);
    }
  }

  /**
   * Fetch global revenue statistics
   */
  async fetchGlobalStats() {
    try {
      const response = await fetch(`${CONFIG.API_BASE}/revenues/stats`);
      if (response.ok) {
        this.globalStats = await response.json();
        this.renderGlobalStats();
        return this.globalStats;
      }
    } catch (error) {
      console.error('[Revenues] Failed to fetch global stats:', error);
    }
    return null;
  }

  /**
   * Fetch user earnings for connected wallet (revenue sharing + time rewards)
   */
  async fetchUserEarnings(address) {
    try {
      // Fetch both revenue sharing and time rewards in parallel
      const [revenueResponse, timeRewardsResponse] = await Promise.all([
        fetch(`${CONFIG.API_BASE}/revenues/user/${address}`),
        fetch(`${CONFIG.API_BASE}/revenues/time-rewards/user/${address}`)
      ]);

      if (revenueResponse.ok) {
        this.userEarnings = await revenueResponse.json();
        this.renderUserEarnings();
      }

      // Handle time rewards separately
      if (timeRewardsResponse.ok) {
        this.userTimeRewards = await timeRewardsResponse.json();
        this.renderSpecialNFTsSection();
      }

      return this.userEarnings;
    } catch (error) {
      console.error('[Revenues] Failed to fetch user earnings:', error);
    }
    return null;
  }

  /**
   * Render the special NFTs time rewards section
   */
  renderSpecialNFTsSection() {
    const section = document.getElementById('special-nfts-section');
    if (!section) return;

    const data = this.userTimeRewards;
    if (!data || !data.nfts || data.nfts.length === 0) {
      section.classList.add('hidden');
      return;
    }

    // Show the section
    section.classList.remove('hidden');

    // Update NFT count in header
    document.getElementById('special-nfts-count').textContent = data.nftCount || data.nfts.length;

    // TimeRewardCounter handles all value updates via updateSpecialNFTsSection() every second
    window.timeRewardCounter?.updateMySpecialNFTsAPY();
  }

  /**
   * Fetch recent reward events history
   */
  async fetchRewardHistory(limit = 50) {
    try {
      const response = await fetch(`${CONFIG.API_BASE}/revenues/history?limit=${limit}`);
      if (response.ok) {
        const data = await response.json();
        this.rewardHistory = data.events || [];
        this.renderRewardHistory();
        return this.rewardHistory;
      }
    } catch (error) {
      console.error('[Revenues] Failed to fetch reward history:', error);
    }
    return [];
  }

  /**
   * Render global stats to the UI (mint tab)
   * Only updates data attributes - TimeRewardCounter handles display with combined values
   */
  renderGlobalStats() {
    if (!this.globalStats) return;

    const stats = this.globalStats;

    // Total Rewards Received (mint tab)
    // Store revenue-only value in data attribute, TimeRewardCounter adds time rewards
    const totalRewardsEl = document.getElementById('mint-total-rewards');
    if (totalRewardsEl) {
      totalRewardsEl.dataset.revenueTotal = stats.totalRewardsReceived || '0';
      // Only set content if TimeRewardCounter hasn't initialized yet
      if (!window.timeRewardCounter?.initialized) {
        // No decimal places for mint tab boxes
        const totalNum = parseFloat(stats.totalRewardsReceived || 0);
        totalRewardsEl.innerHTML = `${Math.floor(totalNum).toLocaleString('en-US')} <span class="text-sm text-gray-400 font-normal">ROGUE</span>`;
        document.getElementById('mint-total-rewards-usd').textContent =
          this.priceService.formatUsd(stats.totalRewardsReceived);
      }
    }

    // Last 24 Hours (mint tab)
    const last24hEl = document.getElementById('mint-last-24h-rewards');
    if (last24hEl) {
      last24hEl.dataset.revenue24h = stats.rewardsLast24Hours || '0';
      // Only set content if TimeRewardCounter hasn't initialized yet
      if (!window.timeRewardCounter?.initialized) {
        // No decimal places for mint tab boxes
        const last24hNum = parseFloat(stats.rewardsLast24Hours || 0);
        last24hEl.innerHTML = `${Math.floor(last24hNum).toLocaleString('en-US')} <span class="text-sm text-gray-400 font-normal">ROGUE</span>`;
        document.getElementById('mint-last-24h-rewards-usd').textContent =
          this.priceService.formatUsd(stats.rewardsLast24Hours);
      }
    }

    // Overall APY (mint tab) - use client-side calculation for special NFTs
    const apyEl = document.getElementById('mint-overall-apy');
    if (apyEl) {
      if (window.timeRewardCounter?.initialized) {
        window.timeRewardCounter.updateAPY();
      } else {
        apyEl.textContent = `${(stats.overallAPY || 0).toFixed(2)}%`;
      }
    }
  }

  /**
   * Render user earnings section
   */
  renderUserEarnings() {
    if (!this.userEarnings) return;

    const earnings = this.userEarnings;
    // Link to getUserPortfolioStats function - shows combined totals for all user NFTs (revenue + time rewards)
    const rewarderUrl = `${CONFIG.ROGUE_EXPLORER_URL}/address/${CONFIG.NFT_REWARDER_ADDRESS}?tab=read_write_proxy&source_address=${CONFIG.NFT_REWARDER_IMPL_ADDRESS}#${CONFIG.NFT_REWARDER_SELECTORS.getUserPortfolioStats}`;

    // Show the my-revenue-section, hide connect prompt
    document.getElementById('my-revenue-section')?.classList.remove('hidden');
    document.getElementById('revenue-connect-prompt')?.classList.add('hidden');

    // Store revenue values in data attributes for TimeRewardCounter to combine
    // TimeRewardCounter will update the display with combined values every second
    const totalEarnedEl = document.getElementById('my-total-earned');
    const pendingEl = document.getElementById('my-pending');
    const last24hEl = document.getElementById('my-last-24h');

    // Store revenue-only values in data attributes
    totalEarnedEl.dataset.revenueTotal = earnings.totalEarned;
    pendingEl.dataset.revenuePending = earnings.totalPending;
    last24hEl.dataset.revenue24h = earnings.totalLast24Hours;

    // Check if user owns any special NFTs (token IDs 2340-2700)
    const hasSpecialNFTs = earnings.nfts?.some(nft => nft.tokenId >= 2340 && nft.tokenId <= 2700);

    if (hasSpecialNFTs && window.timeRewardCounter?.initialized) {
      // TimeRewardCounter will update BOTH ROGUE and USD values with combined amounts
      // Don't set anything here - let timeRewardCounter handle everything
      window.timeRewardCounter.updateUI();
    } else {
      // No special NFTs - show revenue-only values (ROGUE and USD)
      totalEarnedEl.innerHTML = `${this.formatRogue(earnings.totalEarned)} <span class="text-sm text-gray-400 font-normal">ROGUE</span>`;
      pendingEl.innerHTML = `${this.formatRogue(earnings.totalPending)} <span class="text-sm text-gray-400 font-normal">ROGUE</span>`;
      last24hEl.innerHTML = `${this.formatRogue(earnings.totalLast24Hours)} <span class="text-sm text-gray-400 font-normal">ROGUE</span>`;

      // USD values for revenue-only users
      document.getElementById('my-total-earned-usd').textContent =
        this.priceService.formatUsd(earnings.totalEarned);
      document.getElementById('my-pending-usd').textContent =
        this.priceService.formatUsd(earnings.totalPending);
      document.getElementById('my-last-24h-usd').textContent =
        this.priceService.formatUsd(earnings.totalLast24Hours);
    }

    // Verification links
    document.getElementById('my-total-earned-link').href = rewarderUrl;
    document.getElementById('my-pending-link').href = rewarderUrl;

    // Enable/disable withdraw button - but preserve success state with TX links
    const withdrawBtn = document.getElementById('withdraw-revenues-btn');

    // Only update button state if not showing success TX links
    if (!this.lastWithdrawTxHashes) {
      const revenuePending = parseFloat(earnings.totalPending) > 0;
      const timeRewardsPending = (window.timeRewardCounter?.getTotals()?.myPending || 0) > 0;
      const hasPending = revenuePending || timeRewardsPending;
      withdrawBtn.disabled = !hasPending;
    }

    // Render per-NFT earnings table
    this.renderUserNFTTable();
  }

  /**
   * Render user's per-NFT earnings table
   * Uses incremental updates to prevent flickering on special NFT rows
   */
  renderUserNFTTable() {
    if (!this.userEarnings?.nfts) return;

    const tbody = document.getElementById('my-nft-revenues-table');
    if (!tbody) return;

    if (this.userEarnings.nfts.length === 0) {
      tbody.innerHTML = `
        <tr>
          <td colspan="7" class="p-4 text-center text-gray-400">
            You don't own any High Roller NFTs yet.
          </td>
        </tr>
      `;
      return;
    }

    // Sort by tokenId descending (newest at top)
    const sortedNfts = [...this.userEarnings.nfts].sort((a, b) => b.tokenId - a.tokenId);

    // Check if we have time reward data to merge
    const timeRewardsMap = {};
    if (this.userTimeRewards?.nfts) {
      this.userTimeRewards.nfts.forEach(tr => {
        timeRewardsMap[tr.tokenId] = tr;
      });
    }

    // Check if table already has rows - if so, only update data attributes (no DOM rebuild)
    const existingRows = tbody.querySelectorAll('tr[data-nft-row]');
    if (existingRows.length > 0) {
      // Update mode: just update data attributes, timeRewardCounter handles display
      sortedNfts.forEach(nft => {
        const row = tbody.querySelector(`tr[data-nft-row="${nft.tokenId}"]`);
        if (row) {
          // Update data attributes with new revenue values
          const totalEl = row.querySelector('[data-table-total-earned]');
          const pendingEl = row.querySelector('[data-table-pending]');
          const h24El = row.querySelector('[data-table-24h]');

          if (totalEl) totalEl.dataset.revenueTotal = nft.totalEarned || 0;
          if (pendingEl) pendingEl.dataset.revenuePending = nft.pendingAmount || 0;
          if (h24El) h24El.dataset.revenue24h = nft.last24Hours || 0;

          // For non-special NFTs, also update the displayed text
          const isSpecial = nft.tokenId >= 2340 && nft.tokenId <= 2700;
          if (!isSpecial) {
            if (totalEl) totalEl.textContent = this.formatRogue(nft.totalEarned);
            if (pendingEl) pendingEl.textContent = this.formatRogue(nft.pendingAmount);
            if (h24El) h24El.textContent = this.formatRogue(nft.last24Hours);
          }
        }
      });
      return; // Skip full rebuild
    }

    // Initial render: build the full table
    tbody.innerHTML = sortedNfts.map(nft => {
      const isSpecial = nft.tokenId >= 2340 && nft.tokenId <= 2700;
      // Special NFTs link to getEarningsBreakdown (time rewards), regular NFTs link to rewardInfo (revenue share)
      const verifySelector = isSpecial ? CONFIG.NFT_REWARDER_SELECTORS.getEarningsBreakdown : CONFIG.NFT_REWARDER_SELECTORS.getNFTEarnings;
      const verifyUrl = `${CONFIG.ROGUE_EXPLORER_URL}/address/${CONFIG.NFT_REWARDER_ADDRESS}?tab=read_write_proxy&source_address=${CONFIG.NFT_REWARDER_IMPL_ADDRESS}#${verifySelector}`;
      const timeReward = timeRewardsMap[nft.tokenId];

      // For special NFTs with time rewards, add data attributes for real-time updates
      // Time rewards are added ON TOP of revenue sharing earnings
      const revenueTotalEarned = nft.totalEarned || 0;
      const revenuePending = nft.pendingAmount || 0;
      const revenue24h = nft.last24Hours || 0;

      if (isSpecial && timeReward?.hasStarted) {
        // Special NFT with time rewards - calculate combined values for initial render
        // TimeRewardCounter will update these every second via data attributes
        const now = Math.floor(Date.now() / 1000);
        const oneDayAgo = now - 86400;

        // Get time reward data from timeRewardCounter if available
        const trc = window.timeRewardCounter;
        const nftData = trc?.nfts?.get(nft.tokenId);

        let combinedTotal = revenueTotalEarned;
        let combinedPending = revenuePending;
        let combined24h = revenue24h;

        if (nftData && trc) {
          const rate = trc.RATES[nftData.hostessIndex];
          const effectiveNow = Math.min(now, nftData.endTime);

          // Time total = everything since start
          const timeTotal = Math.max(0, effectiveNow - nftData.startTime) * rate;
          combinedTotal = revenueTotalEarned + timeTotal;

          // Time pending = since last claim
          const timePending = Math.max(0, effectiveNow - nftData.lastClaimTime) * rate;
          combinedPending = revenuePending + timePending;

          // Time 24h = overlap with last 24 hours
          const windowStart = Math.max(nftData.startTime, oneDayAgo);
          const windowEnd = Math.min(nftData.endTime, now);
          const time24h = windowEnd > windowStart ? (windowEnd - windowStart) * rate : 0;
          combined24h = revenue24h + time24h;
        }

        return `
          <tr class="border-t border-gray-600 hover:bg-gray-600/50 bg-gradient-to-r from-amber-900/20 to-transparent" data-nft-row="${nft.tokenId}">
            <td class="p-2">
              <a href="${CONFIG.EXPLORER_URL}/token/${CONFIG.CONTRACT_ADDRESS}?a=${nft.tokenId}"
                 target="_blank"
                 class="text-purple-400 hover:underline cursor-pointer">
                #${nft.tokenId} ⭐
              </a>
            </td>
            <td class="p-2">${nft.hostessName}</td>
            <td class="p-2 text-yellow-400">${nft.multiplier}x</td>
            <td class="p-2">
              <a href="${verifyUrl}" target="_blank" class="text-green-400 hover:underline cursor-pointer">
                <span data-table-total-earned="${nft.tokenId}" data-revenue-total="${revenueTotalEarned}">${this.formatRogue(combinedTotal)}</span> <span class="text-xs">↗</span>
              </a>
              <span class="text-gray-500 text-xs block" data-table-total-earned-usd="${nft.tokenId}">${this.priceService.formatUsd(combinedTotal)}</span>
            </td>
            <td class="p-2">
              <a href="${verifyUrl}" target="_blank" class="text-yellow-400 hover:underline cursor-pointer">
                <span data-table-pending="${nft.tokenId}" data-revenue-pending="${revenuePending}">${this.formatRogue(combinedPending)}</span> <span class="text-xs">↗</span>
              </a>
              <span class="text-gray-500 text-xs block" data-table-pending-usd="${nft.tokenId}">${this.priceService.formatUsd(combinedPending)}</span>
            </td>
            <td class="p-2">
              <span data-table-24h="${nft.tokenId}" data-revenue-24h="${revenue24h}">${this.formatRogue(combined24h)}</span>
              <span class="text-gray-500 text-xs block" data-table-24h-usd="${nft.tokenId}">${this.priceService.formatUsd(combined24h)}</span>
            </td>
          </tr>
        `;
      } else {
        // Regular NFT - static rendering with data attributes for incremental updates
        return `
          <tr class="border-t border-gray-600 hover:bg-gray-600/50" data-nft-row="${nft.tokenId}">
            <td class="p-2">
              <a href="${CONFIG.EXPLORER_URL}/token/${CONFIG.CONTRACT_ADDRESS}?a=${nft.tokenId}"
                 target="_blank"
                 class="text-purple-400 hover:underline cursor-pointer">
                #${nft.tokenId}
              </a>
            </td>
            <td class="p-2">${nft.hostessName}</td>
            <td class="p-2 text-yellow-400">${nft.multiplier}x</td>
            <td class="p-2">
              <a href="${verifyUrl}" target="_blank" class="text-green-400 hover:underline cursor-pointer">
                <span data-table-total-earned="${nft.tokenId}" data-revenue-total="${revenueTotalEarned}">${this.formatRogue(nft.totalEarned)}</span> <span class="text-xs">↗</span>
              </a>
              <span class="text-gray-500 text-xs block">${this.priceService.formatUsd(nft.totalEarned)}</span>
            </td>
            <td class="p-2">
              <a href="${verifyUrl}" target="_blank" class="text-yellow-400 hover:underline cursor-pointer">
                <span data-table-pending="${nft.tokenId}" data-revenue-pending="${revenuePending}">${this.formatRogue(nft.pendingAmount)}</span> <span class="text-xs">↗</span>
              </a>
              <span class="text-gray-500 text-xs block">${this.priceService.formatUsd(nft.pendingAmount)}</span>
            </td>
            <td class="p-2">
              <span data-table-24h="${nft.tokenId}" data-revenue-24h="${revenue24h}">${this.formatRogue(nft.last24Hours)}</span>
              <span class="text-gray-500 text-xs block">${this.priceService.formatUsd(nft.last24Hours)}</span>
            </td>
          </tr>
        `;
      }
    }).join('');
  }

  /**
   * Render recent reward events history
   */
  renderRewardHistory() {
    const tbody = document.getElementById('reward-events-table');
    const loading = document.getElementById('rewards-loading');
    const empty = document.getElementById('rewards-empty');

    if (!tbody) return;

    loading?.classList.add('hidden');

    if (this.rewardHistory.length === 0) {
      empty?.classList.remove('hidden');
      tbody.innerHTML = '';
      return;
    }

    empty?.classList.add('hidden');

    tbody.innerHTML = this.rewardHistory.map(event => `
      <tr class="border-t border-gray-700 hover:bg-gray-700/50">
        <td class="p-3 text-gray-400">${this.formatTimeAgo(event.timestamp)}</td>
        <td class="p-3 text-green-400 font-medium">${this.formatRogue(event.amount)} ROGUE</td>
        <td class="p-3 text-gray-400">${this.priceService.formatUsd(event.amount)}</td>
        <td class="p-3">
          <a href="${CONFIG.ROGUE_EXPLORER_URL}/tx/${event.txHash}?tab=logs"
             target="_blank"
             class="text-purple-400 hover:underline cursor-pointer">
            ${UI.truncateAddress(event.txHash)}
          </a>
        </td>
      </tr>
    `).join('');
  }

  /**
   * Handle withdrawal request - withdraws BOTH revenue sharing AND time-based rewards
   */
  async withdraw() {
    if (this.isWithdrawing) return;

    const btn = document.getElementById('withdraw-revenues-btn');
    const originalText = btn.textContent;

    try {
      this.isWithdrawing = true;
      btn.disabled = true;
      btn.textContent = 'Withdrawing...';

      // Get connected wallet address
      if (!walletService.isConnected()) {
        throw new Error('Wallet not connected');
      }

      const address = walletService.address;
      const txHashes = [];
      let totalWithdrawn = 0;

      // 1. Withdraw revenue sharing rewards
      const revenueResponse = await fetch(`${CONFIG.API_BASE}/revenues/withdraw`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ address })
      });

      if (revenueResponse.ok) {
        const revenueResult = await revenueResponse.json();
        txHashes.push(revenueResult.txHash);
        totalWithdrawn += parseFloat(revenueResult.amount) || 0;
        console.log(`[Revenues] Revenue sharing withdrawn: ${revenueResult.amount} ROGUE`);
      } else {
        // Log but don't fail - might just have no revenue pending
        const error = await revenueResponse.json();
        console.log('[Revenues] Revenue sharing withdraw skipped:', error.error);
      }

      // 2. Check and withdraw time-based rewards (special NFTs only)
      btn.textContent = 'Claiming time rewards...';

      const timeRewardsResponse = await fetch(`${CONFIG.API_BASE}/revenues/time-rewards/user/${address}`);
      if (timeRewardsResponse.ok) {
        const timeRewardsData = await timeRewardsResponse.json();

        // Get special NFTs with pending rewards
        const specialTokenIds = (timeRewardsData.nfts || [])
          .filter(nft => nft.hasStarted && nft.pending > 0)
          .map(nft => nft.tokenId);

        if (specialTokenIds.length > 0) {
          const timeClaimResponse = await fetch(`${CONFIG.API_BASE}/revenues/time-rewards/claim`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ tokenIds: specialTokenIds, recipient: address })
          });

          if (timeClaimResponse.ok) {
            const timeResult = await timeClaimResponse.json();
            txHashes.push(timeResult.txHash);
            totalWithdrawn += parseFloat(timeResult.amount) || 0;
            console.log(`[Revenues] Time rewards claimed: ${timeResult.amount} ROGUE`);

            // Update local time reward counter
            if (window.timeRewardCounter) {
              window.timeRewardCounter.onClaimed(specialTokenIds);
            }
          } else {
            const error = await timeClaimResponse.json();
            console.log('[Revenues] Time rewards claim skipped:', error.error);
          }
        }
      }

      // Show results
      if (txHashes.length > 0) {
        UI.showToast(`Withdrawal successful! ${this.formatRogue(totalWithdrawn)} ROGUE sent`, 'success');
        // Show success button with links to all transactions
        this.showWithdrawSuccess(btn, txHashes);
      } else {
        throw new Error('No rewards to withdraw');
      }

      // Refresh user earnings
      await this.fetchUserEarnings(address);

    } catch (error) {
      console.error('[Revenues] Withdrawal failed:', error);
      UI.showToast(error.message || 'Withdrawal failed', 'error');
      // Reset button on error
      btn.disabled = false;
      btn.textContent = originalText;
    } finally {
      this.isWithdrawing = false;
    }
  }

  /**
   * Show success state on withdraw button with link(s) to transaction(s)
   * @param {HTMLElement} btn - The withdraw button element
   * @param {string|string[]} txHashes - Single tx hash or array of tx hashes
   */
  showWithdrawSuccess(btn, txHashes) {
    // Normalize to array
    const hashes = Array.isArray(txHashes) ? txHashes : [txHashes];

    // Store the success state - prevents button from being reset
    this.lastWithdrawTxHashes = hashes;

    // Replace button with success message and explicit TX links
    btn.className = 'bg-gradient-to-r from-green-500 to-emerald-500 py-3 px-6 rounded-lg font-bold transition-all flex items-center justify-center gap-2';
    btn.disabled = true;
    btn.onclick = null;

    // Build TX links HTML
    const txLinks = hashes.map((hash, i) => {
      const label = hashes.length === 1 ? 'View TX' : `TX ${i + 1}`;
      return `<a href="${CONFIG.ROGUE_EXPLORER_URL}/tx/${hash}?tab=logs" target="_blank" class="underline hover:text-white">${label}</a>`;
    }).join(' · ');

    btn.innerHTML = `
      <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path>
      </svg>
      Success! ${txLinks}
    `;
  }

  /**
   * Reset withdraw button to original state (called on tab switch or page reload)
   */
  resetWithdrawButton() {
    const btn = document.getElementById('withdraw-revenues-btn');
    if (!btn) return;

    btn.className = 'bg-gradient-to-r from-green-600 to-emerald-600 hover:from-green-700 hover:to-emerald-700 py-3 px-6 rounded-lg font-bold cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed transition-all';
    btn.innerHTML = 'Withdraw All';
    btn.onclick = () => this.withdraw();

    // Re-evaluate disabled state based on pending amount (revenue sharing + time rewards)
    const revenuePending = this.userEarnings && parseFloat(this.userEarnings.totalPending) > 0;
    const timeRewardsPending = (window.timeRewardCounter?.getTotals()?.myPending || 0) > 0;
    const hasPending = revenuePending || timeRewardsPending;
    btn.disabled = !hasPending;

    this.lastWithdrawTxHashes = null;
  }

  /**
   * Handle WebSocket price update
   */
  handlePriceUpdate(data) {
    this.priceService.updatePrices(data);
    // Re-render stats with new prices
    this.renderGlobalStats();
    if (this.userEarnings) {
      this.renderUserEarnings();
    }
    this.renderRewardHistory();
  }

  /**
   * Handle WebSocket reward received event
   */
  handleRewardReceived(data) {
    // Add to history at the beginning
    this.rewardHistory.unshift({
      amount: data.amount,
      timestamp: data.timestamp,
      txHash: data.txHash
    });

    // Keep only last 50
    if (this.rewardHistory.length > 50) {
      this.rewardHistory = this.rewardHistory.slice(0, 50);
    }

    this.renderRewardHistory();

    // Show toast notification immediately
    // Stats will auto-update via EARNINGS_SYNCED broadcast every 10 seconds
    UI.showToast(`New reward: ${this.formatRogue(data.amount)} ROGUE distributed to NFT holders!`, 'info');
  }

  /**
   * Handle WebSocket earnings synced event (broadcast every 10 seconds after backend sync)
   * Uses data directly from WebSocket instead of re-fetching from API
   */
  handleEarningsSynced(data) {
    console.log('[Revenues] Earnings synced, updating UI from WebSocket data...');

    // Transform WebSocket data to match globalStats format expected by renderGlobalStats()
    // WebSocket sends raw wei strings, need to convert to ROGUE format
    const formatWei = (wei) => {
      if (!wei || wei === '0') return '0';
      try {
        // Convert wei string to BigInt, divide by 1e18, format with decimals
        const value = BigInt(wei);
        const whole = value / BigInt(1e18);
        const fraction = value % BigInt(1e18);
        const fractionStr = fraction.toString().padStart(18, '0').slice(0, 4);
        return `${whole}.${fractionStr}`.replace(/\.?0+$/, '') || '0';
      } catch {
        return '0';
      }
    };

    // Update global stats from WebSocket data
    this.globalStats = {
      totalRewardsReceived: formatWei(data.totalRewardsReceived),
      totalRewardsDistributed: formatWei(data.totalRewardsDistributed),
      rewardsLast24Hours: formatWei(data.rewardsLast24h),
      overallAPY: (data.overallAPY || 0) / 100, // Convert basis points to percentage
      hostessTypes: (data.hostessStats || []).map(h => ({
        index: h.hostess_index,
        name: ['Penelope Fatale', 'Mia Siren', 'Cleo Enchante', 'Sophia Spark',
               'Luna Mirage', 'Aurora Seductra', 'Scarlett Ember', 'Vivienne Allure'][h.hostess_index],
        multiplier: [100, 90, 80, 70, 60, 50, 40, 30][h.hostess_index],
        nftCount: h.nft_count,
        totalPoints: h.total_points,
        sharePercent: (h.share_basis_points || 0) / 100,
        last24HPerNFT: formatWei(h.last_24h_per_nft),
        apy: (h.apy_basis_points || 0) / 100
      })),
      lastUpdated: data.timestamp
    };

    // Re-render global stats immediately
    this.renderGlobalStats();

    // For user earnings, we still need to fetch since it requires querying per-user NFT data
    // But only if wallet is connected and we're on the revenues tab (not hidden)
    const revenuesTab = document.getElementById('tab-revenues');
    if (walletService.isConnected() && revenuesTab && !revenuesTab.classList.contains('hidden')) {
      this.fetchUserEarnings(walletService.address);
    }
  }

  /**
   * Handle WebSocket reward claimed event
   */
  handleRewardClaimed(data) {
    // If this is the connected user, refresh their earnings
    if (walletService.isConnected() &&
        data.user.toLowerCase() === walletService.address.toLowerCase()) {
      this.fetchUserEarnings(walletService.address);
    }

    // Refresh global stats
    this.fetchGlobalStats();
  }

  /**
   * Format ROGUE amount for display
   */
  formatRogue(amount) {
    if (!amount) return '0';
    const num = typeof amount === 'string' ? parseFloat(amount) : amount;
    if (isNaN(num)) return '0';

    if (num >= 1_000_000) {
      return `${(num / 1_000_000).toFixed(2)}M`;
    } else if (num >= 1_000) {
      return `${(num / 1_000).toFixed(2)}k`;
    } else if (num >= 1) {
      return num.toFixed(2);
    } else if (num > 0) {
      return num.toFixed(6);
    }
    return '0';
  }

  /**
   * Format timestamp to relative time
   */
  formatTimeAgo(timestamp) {
    const seconds = Math.floor(Date.now() / 1000) - timestamp;

    if (seconds < 60) return 'Just now';
    if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`;
    if (seconds < 86400) return `${Math.floor(seconds / 3600)}h ago`;
    if (seconds < 604800) return `${Math.floor(seconds / 86400)}d ago`;

    const date = new Date(timestamp * 1000);
    return date.toLocaleDateString();
  }

  /**
   * Reset UI when wallet disconnects
   */
  resetUserUI() {
    this.userEarnings = null;
    document.getElementById('my-revenue-section')?.classList.add('hidden');
    document.getElementById('revenue-connect-prompt')?.classList.remove('hidden');
  }
}

// Create global instance (attached to window for access from timeRewardCounter)
const revenueService = new RevenueService();
window.revenueService = revenueService;
