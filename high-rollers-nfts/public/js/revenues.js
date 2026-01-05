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
   * Fetch user earnings for connected wallet
   */
  async fetchUserEarnings(address) {
    try {
      const response = await fetch(`${CONFIG.API_BASE}/revenues/user/${address}`);
      if (response.ok) {
        this.userEarnings = await response.json();
        this.renderUserEarnings();
        return this.userEarnings;
      }
    } catch (error) {
      console.error('[Revenues] Failed to fetch user earnings:', error);
    }
    return null;
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
   */
  renderGlobalStats() {
    if (!this.globalStats) return;

    const stats = this.globalStats;

    // Total Rewards Received (mint tab)
    const totalRewardsEl = document.getElementById('mint-total-rewards');
    if (totalRewardsEl) {
      totalRewardsEl.textContent = `${this.formatRogue(stats.totalRewardsReceived)} ROGUE`;
      document.getElementById('mint-total-rewards-usd').textContent =
        this.priceService.formatUsd(stats.totalRewardsReceived);
    }

    // Last 24 Hours (mint tab)
    const last24hEl = document.getElementById('mint-last-24h-rewards');
    if (last24hEl) {
      last24hEl.textContent = `${this.formatRogue(stats.rewardsLast24Hours)} ROGUE`;
      document.getElementById('mint-last-24h-rewards-usd').textContent =
        this.priceService.formatUsd(stats.rewardsLast24Hours);
    }

    // Overall APY (mint tab)
    const apyEl = document.getElementById('mint-overall-apy');
    if (apyEl) {
      apyEl.textContent = `${(stats.overallAPY || 0).toFixed(2)}%`;
    }
  }

  /**
   * Render user earnings section
   */
  renderUserEarnings() {
    if (!this.userEarnings) return;

    const earnings = this.userEarnings;
    const rewarderUrl = `${CONFIG.ROGUE_EXPLORER_URL}/address/${CONFIG.NFT_REWARDER_ADDRESS}?tab=read_write_proxy&source_address=0x2634727150cf1B3d4D63Cd4716b9B19Ef1798240#0x93c8949f`;

    // Show the my-revenue-section, hide connect prompt
    document.getElementById('my-revenue-section')?.classList.remove('hidden');
    document.getElementById('revenue-connect-prompt')?.classList.add('hidden');

    // Total Earned with verification link
    document.getElementById('my-total-earned').textContent =
      `${this.formatRogue(earnings.totalEarned)} ROGUE`;
    document.getElementById('my-total-earned-usd').textContent =
      this.priceService.formatUsd(earnings.totalEarned);
    document.getElementById('my-total-earned-link').href = rewarderUrl;

    // Pending Balance with verification link
    document.getElementById('my-pending').textContent =
      `${this.formatRogue(earnings.totalPending)} ROGUE`;
    document.getElementById('my-pending-usd').textContent =
      this.priceService.formatUsd(earnings.totalPending);
    document.getElementById('my-pending-link').href = rewarderUrl;

    // Last 24 Hours
    document.getElementById('my-last-24h').textContent =
      `${this.formatRogue(earnings.totalLast24Hours)} ROGUE`;
    document.getElementById('my-last-24h-usd').textContent =
      this.priceService.formatUsd(earnings.totalLast24Hours);

    // Portfolio APY
    document.getElementById('my-apy').textContent =
      `${(earnings.overallAPY || 0).toFixed(2)}%`;

    // Enable/disable withdraw button - reset to original state if we have new pending
    const withdrawBtn = document.getElementById('withdraw-revenues-btn');
    const hasPending = parseFloat(earnings.totalPending) > 0;

    // If there's new pending balance, reset button to allow another withdrawal
    if (hasPending && this.lastWithdrawTxHash) {
      this.resetWithdrawButton();
    } else if (!this.lastWithdrawTxHash) {
      // Only update disabled state if not in success state
      withdrawBtn.disabled = !hasPending;
    }

    // Render per-NFT earnings table
    this.renderUserNFTTable();
  }

  /**
   * Render user's per-NFT earnings table
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

    tbody.innerHTML = this.userEarnings.nfts.map(nft => {
      const verifyUrl = `${CONFIG.ROGUE_EXPLORER_URL}/address/${CONFIG.NFT_REWARDER_ADDRESS}?tab=read_write_proxy&source_address=0x2634727150cf1B3d4D63Cd4716b9B19Ef1798240#0x9a3b5a1d`;

      return `
        <tr class="border-t border-gray-600 hover:bg-gray-600/50">
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
              ${this.formatRogue(nft.totalEarned)} <span class="text-xs">↗</span>
            </a>
            <span class="text-gray-500 text-xs block">${this.priceService.formatUsd(nft.totalEarned)}</span>
          </td>
          <td class="p-2">
            <a href="${verifyUrl}" target="_blank" class="text-yellow-400 hover:underline cursor-pointer">
              ${this.formatRogue(nft.pendingAmount)} <span class="text-xs">↗</span>
            </a>
            <span class="text-gray-500 text-xs block">${this.priceService.formatUsd(nft.pendingAmount)}</span>
          </td>
          <td class="p-2">
            <span>${this.formatRogue(nft.last24Hours)}</span>
            <span class="text-gray-500 text-xs block">${this.priceService.formatUsd(nft.last24Hours)}</span>
          </td>
          <td class="p-2 text-purple-400">${nft.apy.toFixed(2)}%</td>
        </tr>
      `;
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
   * Handle withdrawal request
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

      // Call withdraw endpoint
      const response = await fetch(`${CONFIG.API_BASE}/revenues/withdraw`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ address })
      });

      if (!response.ok) {
        const error = await response.json();
        throw new Error(error.message || 'Withdrawal failed');
      }

      const result = await response.json();

      UI.showToast(`Withdrawal successful! ${this.formatRogue(result.amount)} ROGUE sent`, 'success');

      // Show success button with link to transaction
      this.showWithdrawSuccess(btn, result.txHash);

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
   * Show success state on withdraw button with link to transaction
   */
  showWithdrawSuccess(btn, txHash) {
    const txUrl = `${CONFIG.ROGUE_EXPLORER_URL}/tx/${txHash}?tab=logs`;

    // Replace button with success link
    btn.className = 'bg-gradient-to-r from-green-500 to-emerald-500 py-3 px-6 rounded-lg font-bold cursor-pointer transition-all flex items-center justify-center gap-2';
    btn.innerHTML = `
      <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path>
      </svg>
      Success! View TX
    `;
    btn.disabled = false;

    // Make the button a link
    btn.onclick = () => window.open(txUrl, '_blank');

    // Store the success state
    this.lastWithdrawTxHash = txHash;
  }

  /**
   * Reset withdraw button to original state
   */
  resetWithdrawButton() {
    const btn = document.getElementById('withdraw-revenues-btn');
    if (!btn) return;

    btn.className = 'bg-gradient-to-r from-green-600 to-emerald-600 hover:from-green-700 hover:to-emerald-700 py-3 px-6 rounded-lg font-bold cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed transition-all';
    btn.innerHTML = 'Withdraw All';
    btn.onclick = () => this.withdraw();

    // Re-evaluate disabled state based on pending amount
    const hasPending = this.userEarnings && parseFloat(this.userEarnings.totalPending) > 0;
    btn.disabled = !hasPending;

    this.lastWithdrawTxHash = null;
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

// Create global instance
const revenueService = new RevenueService();
