// High Rollers NFT - UI Helpers

const UI = {
  /**
   * Format ETH value for display
   */
  formatETH(weiValue) {
    if (!weiValue) return '0';
    try {
      const eth = ethers.formatEther(weiValue.toString());
      const num = parseFloat(eth);
      if (num === 0) return '0';
      if (num < 0.0001) return '<0.0001';
      return num.toFixed(4).replace(/\.?0+$/, '');
    } catch (e) {
      return '0';
    }
  },

  /**
   * Truncate address for display
   */
  truncateAddress(address) {
    if (!address) return '';
    return `${address.slice(0, 6)}...${address.slice(-4)}`;
  },

  /**
   * Format timestamp to relative time
   */
  formatTimeAgo(timestamp) {
    const seconds = Math.floor((Date.now() / 1000) - timestamp);

    if (seconds < 60) return 'Just now';
    if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`;
    if (seconds < 86400) return `${Math.floor(seconds / 3600)}h ago`;
    if (seconds < 604800) return `${Math.floor(seconds / 86400)}d ago`;

    return new Date(timestamp * 1000).toLocaleDateString();
  },

  /**
   * Format number with commas
   */
  formatNumber(num) {
    return num.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  },

  /**
   * Get rarity badge class
   */
  getRarityClass(rarity) {
    const percent = parseFloat(rarity);
    if (percent <= 1) return 'rarity-legendary';
    if (percent <= 7.5) return 'rarity-epic';
    if (percent <= 12.5) return 'rarity-rare';
    return 'rarity-common';
  },

  /**
   * Translate blockchain error messages to user-friendly text
   */
  translateError(error) {
    const message = error?.reason || error?.message || String(error);

    // Common error patterns
    const errorMappings = [
      { pattern: /insufficient funds/i, message: 'Insufficient ETH balance. You need 0.32 ETH plus gas fees.' },
      { pattern: /user rejected/i, message: 'Transaction was cancelled by user' },
      { pattern: /user denied/i, message: 'Transaction was cancelled by user' },
      { pattern: /nonce too low/i, message: 'Transaction conflict. Please try again.' },
      { pattern: /replacement.*underpriced/i, message: 'Gas price too low. Please increase gas and try again.' },
      { pattern: /exceeds block gas limit/i, message: 'Transaction too complex. Please try again.' },
      { pattern: /execution reverted/i, message: 'Transaction failed on-chain. Contract rejected the request.' },
      { pattern: /network changed/i, message: 'Network changed. Please connect to Arbitrum One.' },
      { pattern: /chain.*mismatch/i, message: 'Wrong network. Please switch to Arbitrum One.' },
      { pattern: /already pending/i, message: 'Transaction already pending. Please wait for it to complete.' },
      { pattern: /max supply/i, message: 'Maximum supply reached. Collection is sold out.' },
      { pattern: /mint.*paused/i, message: 'Minting is currently paused. Please try again later.' },
      { pattern: /not.*owner/i, message: 'You do not own this NFT.' },
      { pattern: /timeout|timed out/i, message: 'Request timed out. Please check your connection and try again.' },
      { pattern: /rate limit/i, message: 'Too many requests. Please wait a moment and try again.' },
      { pattern: /cannot estimate gas/i, message: 'Transaction would fail. Please check your balance (need 0.32+ ETH).' },
      { pattern: /unpredictable gas/i, message: 'Unable to estimate gas. The transaction may fail.' },
      { pattern: /missing revert data/i, message: 'Transaction would fail. Please ensure you have 0.32 ETH plus gas fees.' },
      { pattern: /CALL_EXCEPTION/i, message: 'Contract call failed. Please check your balance and try again.' },
    ];

    for (const { pattern, message: friendlyMessage } of errorMappings) {
      if (pattern.test(message)) {
        return friendlyMessage;
      }
    }

    // Return original if no mapping found, but clean it up
    return message.length > 150 ? message.substring(0, 150) + '...' : message;
  },

  /**
   * Show toast notification
   * Error toasts stay until manually closed
   */
  showToast(message, type = 'info') {
    // Translate error messages
    const displayMessage = type === 'error' ? this.translateError(message) : message;

    const toast = document.createElement('div');
    toast.className = `toast ${type}`;

    if (type === 'error') {
      // Error toasts have a close button and don't auto-dismiss
      toast.innerHTML = `
        <div class="toast-content">
          <span class="toast-message">${displayMessage}</span>
          <button class="toast-close" aria-label="Close">&times;</button>
        </div>
      `;

      toast.querySelector('.toast-close').addEventListener('click', () => {
        toast.classList.add('toast-fade-out');
        setTimeout(() => toast.remove(), 300);
      });

      document.body.appendChild(toast);
    } else {
      // Non-error toasts auto-dismiss after 3 seconds
      toast.textContent = displayMessage;
      document.body.appendChild(toast);

      setTimeout(() => {
        toast.classList.add('toast-fade-out');
        setTimeout(() => toast.remove(), 300);
      }, 3000);
    }
  },

  /**
   * Render hostess card for gallery
   * @param {Object} hostess - Hostess config data
   * @param {number} count - Number minted
   * @param {number} roguePrice - Current ROGUE price in USD
   */
  renderHostessCard(hostess, count = 0, roguePrice = 0) {
    const imageUrl = ImageKit.getOptimizedUrl(hostess.image, 'card');

    // Time reward rates per second for each hostess type (ROGUE)
    // These are hardcoded - same as in timeRewardCounter.js
    const TIME_REWARD_RATES = [
      2.125029,  // Penelope (100x)
      1.912007,  // Mia (90x)
      1.700492,  // Cleo (80x)
      1.487470,  // Sophia (70x)
      1.274962,  // Luna (60x)
      1.062454,  // Aurora (50x)
      0.849946,  // Scarlett (40x)
      0.637438,  // Vivienne (30x)
    ];

    // Calculate total 180-day earnings: rate per second × 180 days in seconds
    const SECONDS_IN_180_DAYS = 180 * 24 * 60 * 60; // 15,552,000
    const total180Days = TIME_REWARD_RATES[hostess.index] * SECONDS_IN_180_DAYS;

    // Format with comma delimiters, no decimal places
    const totalDisplay = Math.floor(total180Days).toLocaleString('en-US');

    // Calculate USD value using passed price or fallback to priceService
    const price = roguePrice || window.revenueService?.priceService?.roguePrice || 0;
    const usdValue = total180Days * price;
    const usdDisplay = usdValue.toLocaleString('en-US', {
      style: 'currency',
      currency: 'USD',
      minimumFractionDigits: 0,
      maximumFractionDigits: 0
    });

    return `
      <div class="hostess-card bg-gray-800 rounded-lg overflow-hidden">
        <div class="aspect-square bg-gray-700 relative">
          <img
            src="${imageUrl}"
            alt="${hostess.name}"
            class="w-full h-full object-cover"
            loading="lazy"
          />
        </div>
        <div class="p-4">
          <h3 class="font-bold text-lg text-center">${hostess.name}</h3>
          <div class="text-center mt-3">
            <p class="text-2xl font-bold text-green-400 flex items-baseline justify-center gap-1">
              <img src="https://ik.imagekit.io/blockster/rogue-white-in-indigo-logo.png" alt="ROGUE" class="w-5 h-5 self-center">
              ${totalDisplay} <span class="text-sm text-gray-400 font-normal">ROGUE</span>
            </p>
            <p class="text-gray-400 text-sm">${usdDisplay}</p>
            <div class="flex flex-col items-center">
              <span class="text-gray-400 text-xs mt-1 text-center">Minimum earnings in next 180 days on new mints</span>
            </div>
          </div>
          <div class="flex justify-between items-center mt-4 text-sm">
            <span class="text-gray-400">Rarity: <span class="text-white">${hostess.rarity}</span></span>
            <span class="text-gray-400">Minted: <span class="text-white">${this.formatNumber(count)}</span></span>
          </div>
        </div>
      </div>
    `;
  },

  /**
   * Check if NFT is a special time-reward NFT
   * @param {number} tokenId - NFT token ID
   * @returns {boolean}
   */
  isSpecialNFT(tokenId) {
    return tokenId >= 2340 && tokenId <= 2700;
  },

  /**
   * Render NFT card for My NFTs grid
   * @param {Object} nft - NFT data
   * @param {Object} earnings - Earnings data for this NFT (optional)
   */
  renderNFTCard(nft, earnings = null) {
    const imageUrl = ImageKit.getHostessImage(nft.hostess_index, 'card');
    const isSpecial = this.isSpecialNFT(nft.token_id);

    // Card classes - special NFTs get golden animated glow
    const cardClasses = isSpecial
      ? 'nft-card special-nft-glow bg-gray-800 rounded-lg overflow-hidden cursor-pointer block transition-all relative'
      : 'nft-card bg-gray-800 rounded-lg overflow-hidden cursor-pointer block hover:ring-2 hover:ring-purple-500 transition-all relative';

    // Special badge for time-reward NFTs
    const specialBadge = isSpecial ? `
      <div class="absolute top-2 right-2 z-10">
        <span class="bg-gradient-to-r from-yellow-500 to-amber-500 text-black text-xs px-2 py-1 rounded-full font-bold shadow-lg">
          ⭐ SPECIAL
        </span>
      </div>
    ` : '';

    // Revenue sharing earnings display (all NFTs)
    let earningsDisplay = '';
    if (earnings) {
      const pendingAmount = parseFloat(earnings.pendingAmount || 0);
      const totalEarned = parseFloat(earnings.totalEarned || 0);

      // Get USD values from priceService if available
      const priceService = window.revenueService?.priceService;
      const pendingUsd = priceService ? priceService.formatUsd(pendingAmount) : '';
      const totalUsd = priceService ? priceService.formatUsd(totalEarned) : '';

      earningsDisplay = `
        <div class="mt-2 pt-2 border-t border-gray-700 text-xs" data-nft-earnings="${nft.token_id}">
          <p class="text-green-400 font-bold mb-1">🎰 Betting Rewards</p>
          <div class="flex justify-between items-baseline">
            <span class="text-gray-400">Pending:</span>
            <span class="text-green-400 font-bold" data-nft-pending="${nft.token_id}">${pendingAmount.toFixed(2)} <span class="text-xs text-gray-500 font-normal">ROGUE</span></span>
          </div>
          <div class="text-right text-gray-500 text-xs" data-nft-pending-usd="${nft.token_id}">${pendingUsd}</div>
          <div class="flex justify-between items-baseline mt-1">
            <span class="text-gray-400">Total:</span>
            <span class="text-white" data-nft-total="${nft.token_id}">${totalEarned.toFixed(2)} <span class="text-xs text-gray-500 font-normal">ROGUE</span></span>
          </div>
          <div class="text-right text-gray-500 text-xs" data-nft-total-usd="${nft.token_id}">${totalUsd}</div>
        </div>
      `;
    }

    // Time-based rewards section (special NFTs only)
    let timeRewardsDisplay = '';
    if (isSpecial && nft.timeReward) {
      const tr = nft.timeReward;
      if (tr.hasStarted) {
        timeRewardsDisplay = `
          <div class="mt-2 pt-2 border-t border-violet-500/30 text-xs">
            <p class="text-violet-400 font-bold mb-1">⏱️ Time Rewards</p>
            <div class="flex justify-between items-baseline">
              <span class="text-gray-400">Pending:</span>
              <span class="text-violet-400 font-bold" data-time-reward-token="${nft.token_id}">
                ${this.formatTimeRewardAmount(tr.pending)} <span class="text-xs text-gray-500 font-normal">ROGUE</span>
              </span>
            </div>
            <div class="flex justify-between items-baseline mt-1">
              <span class="text-gray-400">Total:</span>
              <span class="text-violet-300" data-time-reward-total="${nft.token_id}">
                ${this.formatTimeRewardAmount(tr.totalEarned || 0)} <span class="text-xs text-gray-500 font-normal">ROGUE</span>
              </span>
            </div>
            <div class="flex justify-between items-baseline mt-1">
              <span class="text-gray-400">Remaining:</span>
              <span class="text-white font-mono" data-time-remaining-token="${nft.token_id}">
                ${this.formatTimeRemaining(tr.timeRemaining)}
              </span>
            </div>
            <div class="flex justify-between items-baseline mt-1">
              <span class="text-gray-400">180d Total:</span>
              <span class="text-violet-200">${this.formatTimeRewardAmount(tr.totalFor180Days)} <span class="text-xs text-gray-500 font-normal">ROGUE</span></span>
            </div>
          </div>
        `;
      } else {
        timeRewardsDisplay = `
          <div class="mt-2 pt-2 border-t border-violet-500/30 text-xs">
            <p class="text-violet-400 font-bold mb-1">⏱️ Time Rewards</p>
            <p class="text-gray-400 italic">Not yet started</p>
          </div>
        `;
      }
    }

    return `
      <a href="${CONFIG.EXPLORER_URL}/token/${CONFIG.CONTRACT_ADDRESS}?a=${nft.token_id}" target="_blank" class="${cardClasses}">
        ${specialBadge}
        <div class="aspect-square bg-gray-700">
          <img
            src="${imageUrl}"
            alt="${nft.hostess_name}"
            class="w-full h-full object-cover"
            loading="lazy"
          />
        </div>
        <div class="p-3">
          <div class="flex justify-between items-center">
            <p class="font-bold text-sm">${nft.hostess_name}</p>
            <span class="text-xs px-2 py-0.5 rounded ${this.getRarityClass(nft.hostessRarity || CONFIG.HOSTESSES[nft.hostess_index]?.rarity)}">
              ${CONFIG.HOSTESSES[nft.hostess_index]?.multiplier || 0}x
            </span>
          </div>
          <p class="text-gray-400 text-xs">#${nft.token_id}</p>
          ${earningsDisplay}
          ${timeRewardsDisplay}
        </div>
      </a>
    `;
  },

  /**
   * Format time reward amount (K/M suffixes for large numbers)
   */
  formatTimeRewardAmount(amount) {
    if (!amount || amount === 0) return '0';
    if (amount >= 1_000_000) {
      return (amount / 1_000_000).toFixed(2) + 'M';
    } else if (amount >= 1_000) {
      return (amount / 1_000).toFixed(2) + 'K';
    } else {
      return amount.toFixed(2);
    }
  },

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
  },

  /**
   * Render sale row for sales table
   */
  renderSaleRow(sale) {
    const thumbnailUrl = ImageKit.getHostessImage(sale.hostess_index, 'thumbnail');

    return `
      <tr class="border-b border-gray-700">
        <td class="p-3">
          <div class="flex items-center gap-3">
            <img src="${thumbnailUrl}" alt="${sale.hostess_name}" class="w-12 h-12 rounded-lg object-cover">
            <a href="${CONFIG.EXPLORER_URL}/token/${CONFIG.CONTRACT_ADDRESS}?a=${sale.token_id}" target="_blank" class="text-purple-400 hover:underline cursor-pointer">#${sale.token_id}</a>
          </div>
        </td>
        <td class="p-3">
          <div class="flex items-center gap-2">
            <span>${sale.hostess_name}</span>
            <span class="text-xs px-2 py-0.5 rounded bg-purple-900 text-purple-300">${CONFIG.HOSTESSES[sale.hostess_index]?.multiplier || 0}x</span>
          </div>
        </td>
        <td class="p-3">
          <a href="${CONFIG.EXPLORER_URL}/address/${sale.buyer}" target="_blank" class="text-purple-400 hover:underline cursor-pointer">
            ${this.truncateAddress(sale.buyer)}
          </a>
        </td>
        <td class="p-3">${sale.priceETH || this.formatETH(sale.price)} ETH</td>
        <td class="p-3">${this.formatTimeAgo(sale.timestamp)}</td>
        <td class="p-3">
          <a href="${CONFIG.EXPLORER_URL}/tx/${sale.tx_hash}" target="_blank" class="text-purple-400 hover:underline cursor-pointer">
            View
          </a>
        </td>
      </tr>
    `;
  },

  /**
   * Render affiliate earning row
   */
  renderAffiliateRow(earning) {
    const thumbnailUrl = ImageKit.getHostessImage(earning.hostess_index, 'thumbnail');
    const tierClass = earning.tier === 1 ? 'bg-green-900 text-green-400' : 'bg-blue-900 text-blue-400';

    return `
      <tr class="border-b border-gray-700">
        <td class="p-3">
          <div class="flex items-center gap-3">
            <img src="${thumbnailUrl}" alt="" class="w-12 h-12 rounded-lg object-cover">
            <a href="${CONFIG.EXPLORER_URL}/token/${CONFIG.CONTRACT_ADDRESS}?a=${earning.token_id}" target="_blank" class="text-purple-400 hover:underline cursor-pointer">#${earning.token_id}</a>
          </div>
        </td>
        <td class="p-3">
          <span class="px-2 py-1 rounded text-sm ${tierClass}">
            Tier ${earning.tier}
          </span>
        </td>
        <td class="p-3">
          <a href="${CONFIG.EXPLORER_URL}/address/${earning.affiliate}" target="_blank" class="text-purple-400 hover:underline cursor-pointer">
            ${this.truncateAddress(earning.affiliate)}
          </a>
        </td>
        <td class="p-3 text-green-400">${earning.earningsETH || this.formatETH(earning.earnings)} ETH</td>
      </tr>
    `;
  }
};
