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
   */
  renderHostessCard(hostess, count = 0) {
    const imageUrl = ImageKit.getOptimizedUrl(hostess.image, 'card');

    return `
      <div class="hostess-card bg-gray-800 rounded-lg overflow-hidden">
        <div class="aspect-square bg-gray-700">
          <img
            src="${imageUrl}"
            alt="${hostess.name}"
            class="w-full h-full object-cover"
            loading="lazy"
          />
        </div>
        <div class="p-4">
          <h3 class="font-bold text-lg">${hostess.name}</h3>
          <div class="flex justify-between items-center mt-2">
            <span class="text-sm px-2 py-1 rounded ${this.getRarityClass(hostess.rarity)}">${hostess.rarity}</span>
            <span class="text-yellow-400 font-bold">${hostess.multiplier}x</span>
          </div>
          <p class="text-gray-400 text-sm mt-2">${hostess.description}</p>
          <p class="text-gray-500 text-xs mt-2">Minted: ${this.formatNumber(count)}</p>
        </div>
      </div>
    `;
  },

  /**
   * Render NFT card for My NFTs grid
   */
  renderNFTCard(nft) {
    const imageUrl = ImageKit.getHostessImage(nft.hostess_index, 'card');

    return `
      <div class="nft-card bg-gray-800 rounded-lg overflow-hidden cursor-pointer">
        <div class="aspect-square bg-gray-700">
          <img
            src="${imageUrl}"
            alt="${nft.hostess_name}"
            class="w-full h-full object-cover"
            loading="lazy"
          />
        </div>
        <div class="p-3">
          <p class="font-bold text-sm">${nft.hostess_name}</p>
          <p class="text-gray-400 text-xs">#${nft.token_id}</p>
          <span class="text-xs px-2 py-0.5 rounded mt-1 inline-block ${this.getRarityClass(nft.hostessRarity || CONFIG.HOSTESSES[nft.hostess_index]?.rarity)}">
            ${CONFIG.HOSTESSES[nft.hostess_index]?.multiplier || 0}x
          </span>
        </div>
      </div>
    `;
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
  },

  /**
   * Render rarity card for mint page
   */
  renderRarityCard(hostess) {
    const imageUrl = ImageKit.getOptimizedUrl(hostess.image, 'card');

    return `
      <div class="bg-gray-700 rounded-lg p-4 flex items-center gap-4">
        <img src="${imageUrl}" alt="${hostess.name}" class="w-20 h-20 rounded-lg object-cover">
        <div>
          <p class="font-bold">${hostess.name}</p>
          <div class="flex items-center gap-2 mt-2">
            <span class="text-sm px-2 py-1 rounded ${this.getRarityClass(hostess.rarity)}">${hostess.rarity}</span>
            <span class="text-yellow-400 font-bold">${hostess.multiplier}x</span>
          </div>
        </div>
      </div>
    `;
  }
};
