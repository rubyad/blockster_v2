// High Rollers NFT - Affiliate Service

class AffiliateService {
  constructor() {
    this.STORAGE_KEY = 'high_rollers_affiliate';
    this.init();
  }

  init() {
    // Check URL for referral parameter
    const urlParams = new URLSearchParams(window.location.search);
    const refAddress = urlParams.get('ref');

    if (refAddress && this.isValidAddress(refAddress)) {
      this.setAffiliate(refAddress);
      // Clean URL without losing other params
      urlParams.delete('ref');
      const newUrl = window.location.pathname + (urlParams.toString() ? '?' + urlParams : '');
      history.replaceState({}, '', newUrl);
    }
  }

  isValidAddress(address) {
    return /^0x[a-fA-F0-9]{40}$/.test(address);
  }

  setAffiliate(address) {
    localStorage.setItem(this.STORAGE_KEY, address.toLowerCase());
    console.log(`[Affiliate] Set affiliate to: ${address}`);
  }

  getAffiliate() {
    return localStorage.getItem(this.STORAGE_KEY) || CONFIG.DEFAULT_AFFILIATE;
  }

  clearAffiliate() {
    localStorage.removeItem(this.STORAGE_KEY);
  }

  hasCustomAffiliate() {
    return localStorage.getItem(this.STORAGE_KEY) !== null;
  }

  /**
   * Get affiliate for a buyer - checks server first for permanent link
   * This ensures the first referrer always gets credit
   */
  async getAffiliateForBuyer(buyerAddress) {
    try {
      // Check server for existing permanent link first
      const response = await fetch(`${CONFIG.API_BASE}/buyer-affiliate/${buyerAddress}`);
      if (response.ok) {
        const data = await response.json();
        if (data.hasCustomAffiliate) {
          // Server has a permanent link - this takes priority
          console.log(`[Affiliate] Found permanent link for ${buyerAddress}: ${data.affiliate}`);
          return data.affiliate;
        }
      }
    } catch (error) {
      console.error('[Affiliate] Failed to check server for existing link:', error);
    }

    // Fall back to localStorage or default
    return this.getAffiliate();
  }

  /**
   * Link a buyer wallet to their affiliate permanently in the database
   * Called when wallet connects - ensures first referrer always gets credit
   */
  async linkBuyerToAffiliate(buyerAddress) {
    const affiliate = await this.getAffiliateForBuyer(buyerAddress);

    try {
      const response = await fetch(`${CONFIG.API_BASE}/link-affiliate`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          buyer: buyerAddress,
          affiliate: affiliate
        })
      });

      if (response.ok) {
        const data = await response.json();
        console.log(`[Affiliate] Linked ${buyerAddress} to ${data.affiliate} (isNew: ${data.isNew})`);
        return data;
      }
    } catch (error) {
      console.error('[Affiliate] Failed to link buyer to affiliate:', error);
    }

    return { success: false, affiliate };
  }

  /**
   * Generate referral link for current user
   */
  generateReferralLink(walletAddress) {
    const baseUrl = window.location.origin;
    return `${baseUrl}/?ref=${walletAddress}`;
  }

  /**
   * Copy referral link to clipboard
   */
  async copyReferralLink(walletAddress) {
    const link = this.generateReferralLink(walletAddress);
    try {
      await navigator.clipboard.writeText(link);
      return true;
    } catch (error) {
      // Fallback for older browsers
      const textarea = document.createElement('textarea');
      textarea.value = link;
      textarea.style.position = 'fixed';
      textarea.style.opacity = '0';
      document.body.appendChild(textarea);
      textarea.select();
      document.execCommand('copy');
      document.body.removeChild(textarea);
      return true;
    }
  }

  /**
   * Withdraw affiliate earnings
   */
  async withdrawEarnings() {
    if (!walletService.signer) {
      throw new Error('Please connect your wallet first');
    }

    const contract = walletService.getContract();

    // Execute withdrawal
    const tx = await contract.withdrawAffiliateBalance();

    return {
      txHash: tx.hash,
      wait: () => tx.wait()
    };
  }

  /**
   * Get affiliate balance from contract
   */
  async getAffiliateBalance(address) {
    try {
      const response = await fetch(`${CONFIG.API_BASE}/affiliates/${address}`);
      const data = await response.json();
      return data.tier1?.balance || '0';
    } catch (error) {
      console.error('Failed to get affiliate balance:', error);
      return '0';
    }
  }
}

// Global affiliate service instance
window.affiliateService = new AffiliateService();
